"""Genera pruebas/referencia_fpv_js.json: trazas del dron FPV del simulador del navegador (clase ModeloFPV de
simulador/aviones/FPV.js y Entorno.vientoA de simulador/js/entorno.js) en vuelos con mandos guionizados.
pruebas/prueba_fpv.gd repite el MISMO guion con ModeloFPV de Godot y compara. Si se cambia el guion aqui, hay que
cambiarlo igual alli.

Uso (desde la carpeta del repositorio; necesita Python con playwright y Google Chrome instalado):
    python simulador_godot/pruebas/generar_referencia_fpv.py [url de simulador.html]
Sin url abre simulador/simulador.html como fichero (no hace falta servidor).
"""
import asyncio, json, pathlib, sys
from playwright.async_api import async_playwright

AQUI = pathlib.Path(__file__).resolve().parent
URL = sys.argv[1] if len(sys.argv) > 1 else (AQUI.parent.parent / "simulador" / "simulador.html").as_uri()

# El guion, en JS. Los tiempos van en pasos de 2 ms (i), para que los dos simuladores cambien los mandos en el mismo paso.
# El gas lo pone un "piloto" sencillo que sujeta la altura (hObj) con la altura y la velocidad vertical del dron.
GUION = r"""
(() => {
  const DT = 0.002, VIENTO = [-3.2, 2.4, 0];
  const ent = new Entorno();
  // contacto con el suelo plano (altura 0): Entorno.contactoSuelo sin mundo ni mar
  function contacto(av, vn) {
    if (-av.p[2] > 0) return null;
    av.p[2] = -0;
    const [roll, pitch] = Cuat.euler(av.q), vz = -vn[2], vel = Math.hypot(vn[0], vn[1]), L = ent.limites;
    if (vz < -L.descenso_ms) return "roto (demasiado descenso)";
    if (Math.abs(roll) > L.alabeo_grados * D2R) return "roto (ala en el suelo)";
    if (vel > L.vel_suelo_ms) return "roto (demasiada velocidad)";
    if (Math.abs(pitch) > L.cabeceo_grados * D2R) return "roto (morro en el suelo)";
    return "aterrizado";
  }
  const en = (s0, s1, i) => i >= s0 * 500 && i < s1 * 500;
  function traza(conf, facil, guion, FIN) {
    const m = Modelos.crear("FPV");
    if (conf) m.configurar(conf);
    m.facil = facil; ent.facil = facil;
    const a = m.estadoInicial();
    const mando = { pitch: 0, yaw: 0, guinada: 0, trim: 0 };
    const muestras = [], finales = [];
    for (let i = 0; i <= FIN * 500; i++) {
      const t = i * DT;
      guion(m, a, mando, i);
      if (i % 250 === 0)
        muestras.push({ t, p: a.p.slice(), v: a.v.slice(), w: a.w.slice(), q: a.q.slice(), motores: a.motores.slice(),
                        cmd: [a.cmd.alabeo, a.cmd.cabeceo, a.cmd.guinada], gases: a.gases, T: a.T, Vbat: a.Vbat, mAh: a.mAh, Wh: a.Wh,
                        propwash: a.propwash, integ: a.integ.slice(), estado: a.estado, posado: a.posado, despegado: a.despegado, armado: a.armado, modo: m.modo });
      // el paso del simulador (paso() de simulador.html, sin rachas: viento fijo con el perfil junto al suelo)
      m.servos(a, mando, DT);
      a.agl = -a.p[2];
      const viento = ent.vientoA(VIENTO, a.agl);
      a.pg = 0.03 * Math.sin(3 * t);
      if (a.estado !== "volando") continue;
      const vn = m.paso(a, viento, DT);
      const final = contacto(a, vn);
      if (final) {
        a.estado = final.startsWith("roto") ? "roto" : final === "aterrizado" ? "aterrizado" : "terminado";
        a.v = [0, 0, 0]; a.w = [0, 0, 0]; a.rpm = 0;
        finales.push({ t, final, N: a.p[0], E: a.p[1] });
      }
    }
    ent.facil = false;
    return { muestras, finales };
  }
  // piloto de la altura: gas = 0,31 + 0,05 (hObj - h) - 0,04 vz, entre 0 y 1
  function sujetar(a, hObj) {
    const vz = -Cuat.rot(a.q, a.v)[2];
    a.gases = Math.max(0, Math.min(1, 0.31 + 0.05 * (hObj + a.p[2]) - 0.04 * vz));
  }
  // piloto de la deriva (de 24 s en adelante): en ANGLE, inclina contra la velocidad respecto al suelo para no derivar con el viento
  function frenar(a, mando) {
    const vn = Cuat.rot(a.q, a.v), yaw = Cuat.euler(a.q)[2], cy = Math.cos(yaw), sy = Math.sin(yaw);
    const vf = vn[0] * cy + vn[1] * sy, vr = -vn[0] * sy + vn[1] * cy;
    mando.pitch = Math.max(-0.5, Math.min(0.5, 0.12 * vf)); mando.yaw = Math.max(-0.5, Math.min(0.5, -0.12 * vr));
  }
  // vuelo completo: armar, despegar, ANGLE adelante, alabeo y guinada, HORIZON con vuelta, ACRO con vuelta, ANGLE con
  // viento, caida con poco gas (propwash), bajar despacio hasta posarse, desarmar (aterrizado)
  function completo(m, a, mando, i) {
    if (i === 250) m.lanzar(a);
    if (i === 6500) m.modo = "HORIZON";
    if (i === 8000) m.modo = "ACRO";
    if (i === 9000) m.modo = "ANGLE";
    if (i === 26000) m.desarmar(a);
    mando.pitch = en(6, 9, i) ? -1 : en(16, 16.3, i) ? -0.7 : 0;
    mando.yaw = en(11, 13, i) ? 0.6 : en(13, 14, i) ? 1 : en(16.5, 17.04, i) ? 1 : 0;
    if (i >= 12000 && i < 26000) frenar(a, mando);
    mando.guinada = en(11, 13, i) ? 0.5 : en(19, 20, i) ? -1 : 0;
    if (i < 500) a.gases = 0;
    else if (en(1, 22, i)) sujetar(a, 15);
    else if (en(22, 23.2, i)) a.gases = 0.1;
    else if (en(23.2, 24, i)) sujetar(a, 15);
    else if (en(24, 28, i)) sujetar(a, 8);
    else if (i < 26000) { const vz = -Cuat.rot(a.q, a.v)[2]; a.gases = a.posado ? 0 : Math.max(0, Math.min(1, 0.31 + 0.1 * (-0.8 - vz))); }
    else a.gases = 0;
  }
  // choque: ACRO, desarmado a 20 m: cae y se rompe
  function choque(m, a, mando, i) {
    if (i === 250) m.lanzar(a);
    if (i === 2500) m.modo = "ACRO";
    if (i === 3000) m.desarmar(a);
    mando.yaw = en(5.2, 5.5, i) ? 0.4 : 0;
    if (i < 500) a.gases = 0; else if (i < 3000) sujetar(a, 20); else a.gases = 0;
  }
  // resumen del modelo 3D (para comprobar que Godot lee los mismos datos y construye la misma malla): piezas, rotores,
  // luces, suma de todos los numeros de modelo3d y, de cada malla (fija, palas de cada sentido y disco), vertices,
  // triangulos, area y suma de posiciones
  const K = Modelos.datos("FPV").modelo3d;
  const sumaNum = o => typeof o === "number" ? o : Array.isArray(o) ? o.reduce((s, x) => s + sumaNum(x), 0) : (o && typeof o === "object") ? Object.values(o).reduce((s, x) => s + sumaNum(x), 0) : 0;
  return JSON.stringify({
    DT, VIENTO,
    modelo3d: { piezas: K.piezas.length, rotores: K.rotores.length, luces: K.luces.length, suma: sumaNum(K), mallas: ModeloFPV.mallas3D(Modelos.datos("FPV")) },
    normal: traza(null, false, completo, 55),
    config_facil: traza({ masa_kg: 0.72, temperatura: 32, empuje_gf: 5200, resistencia: 1.3 }, true, completo, 55),
    choque: traza(null, false, choque, 12),
  });
})()
"""


async def main():
    async with async_playwright() as p:
        b = await p.chromium.launch(channel="chrome", headless=True,
                                    args=["--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist"])
        pg = await b.new_page()
        errores = []
        pg.on("pageerror", lambda e: errores.append(str(e)))
        await pg.goto(URL)
        await pg.wait_for_function("typeof Modelos !== 'undefined' && !!Modelos.datos('FPV')", timeout=30000)
        ref = json.loads(await pg.evaluate(GUION))
        await b.close()
    if errores:
        print("errores en la pagina:", errores)
    (AQUI / "referencia_fpv_js.json").write_text(json.dumps(ref, separators=(",", ":")), encoding="utf-8")
    for k in ("normal", "config_facil", "choque"):
        print(k, "muestras:", len(ref[k]["muestras"]), "finales:", ref[k]["finales"])


asyncio.run(main())
