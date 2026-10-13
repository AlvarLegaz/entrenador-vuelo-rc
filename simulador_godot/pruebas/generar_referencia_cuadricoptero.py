"""Genera pruebas/referencia_cuadricoptero_js.json: trazas del cuadricoptero DJI Mini del simulador del navegador
(clase ModeloCuadricoptero de simulador/aviones/DJI_MINI.js y Entorno.vientoA de simulador/js/entorno.js) en un vuelo
con mandos guionizados. pruebas/prueba_cuadricoptero.gd repite el MISMO guion con ModeloCuadricoptero de Godot y
compara. Si se cambia el guion aqui, hay que cambiarlo igual alli.

Uso (desde la carpeta del repositorio; necesita Python con playwright y Google Chrome instalado):
    python simulador_godot/pruebas/generar_referencia_cuadricoptero.py [url de simulador.html]
Sin url abre simulador/simulador.html como fichero (no hace falta servidor).
"""
import asyncio, json, pathlib, sys
from playwright.async_api import async_playwright

AQUI = pathlib.Path(__file__).resolve().parent
URL = sys.argv[1] if len(sys.argv) > 1 else (AQUI.parent.parent / "simulador" / "simulador.html").as_uri()

# El guion, en JS. Los tiempos van en pasos de 2 ms (i), para que los dos simuladores cambien los mandos en el mismo paso.
GUION = r"""
(() => {
  const DT = 0.002, VIENTO = [-3.2, 2.4, 0], FIN = 130;
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
  function traza(conf, facil) {
    const m = Modelos.crear("DJI_MINI");
    if (conf) m.configurar(conf);
    m.facil = facil; ent.facil = facil;
    const a = m.estadoInicial();
    const mando = { pitch: 0, yaw: 0, guinada: 0, vz: 0, gimbal: 0, trim: 0 };
    const muestras = [], finales = [];
    const en = (s0, s1, i) => i >= s0 * 500 && i < s1 * 500;
    for (let i = 0; i <= FIN * 500; i++) {
      const t = i * DT;
      // eventos: armar, modos, despegue automatico y volver a casa
      if (i === 250) m.lanzar(a);
      if (i === 5000) m.modo = "N";
      if (i === 10000) m.modo = "S";
      if (i === 15000) m.modo = "C";
      if (i === 23000) m.modo = "N";
      if (i === 33000) m.despegar(a);
      if (i === 39000) m.volverACasa(a);
      // palancas: subir, hover con viento, a tope adelante en N, S y C (con algo de lateral en C), frenar, guinada y
      // gimbal, bajar con la palanca abajo hasta aterrizar, y tras el despegue automatico alejarse subiendo
      mando.vz = en(1, 6, i) ? 0.8 : en(46, 66, i) ? -1 : en(70, 76, i) ? 1 : 0;
      mando.pitch = en(10, 16, i) || en(20, 26, i) || en(30, 36, i) || en(70, 76, i) ? -1 : 0;
      mando.yaw = en(30, 36, i) ? 0.5 : en(70, 76, i) ? 0.3 : 0;
      mando.guinada = en(40, 44, i) ? 1 : 0;
      mando.gimbal = en(40, 41, i) ? -1 : en(41, 41.5, i) ? 0.6 : 0;
      if (i % 250 === 0)
        muestras.push({ t, p: a.p.slice(), v: a.v.slice(), w: a.w.slice(), q: a.q.slice(),
                        cmd: [a.cmd.adelante, a.cmd.derecha, a.cmd.guinada, a.cmd.vz], T: a.T, Wh: a.Wh, gases: a.gases, gimbal: a.gimbal,
                        estado: a.estado, posado: a.posado, despegado: a.despegado, rth: a.rth ? a.rth.fase : "", hold: !!a.hold, auto: a.despegueAuto });
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
  // resumen de la malla calculada en JS (para comprobar la que calcula DatosComunes en Godot)
  const K = Modelos.datos("DJI_MINI").malla, resumen = M => ({ nv: M.v.length, ni: M.i.length,
    suma_v: M.v.reduce((s, x) => s + Math.abs(x), 0), suma_i: M.i.reduce((s, x) => s + x, 0) });
  return JSON.stringify({
    DT, VIENTO, FIN,
    malla: { fuselaje: resumen(K.fuselaje), estab: resumen(K.estab), helices: [].concat(...K.helices) },
    normal: traza(null, false),
    // configurado (masa, temperatura, empuje y resistencia) y en dificultad facil; el ultimo: configurar() con masa
    // cambia la inercia de los datos registrados en JS (Object.assign copia la referencia)
    config_facil: traza({ masa_kg: 0.27, temperatura: 30, empuje_gf: 560, resistencia: 1.2 }, true),
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
        await pg.wait_for_function("typeof Modelos !== 'undefined' && !!Modelos.datos('DJI_MINI')", timeout=30000)
        ref = json.loads(await pg.evaluate(GUION))
        await b.close()
    if errores:
        print("errores en la pagina:", errores)
    (AQUI / "referencia_cuadricoptero_js.json").write_text(json.dumps(ref, separators=(",", ":")), encoding="utf-8")
    for k in ("normal", "config_facil"):
        print(k, "muestras:", len(ref[k]["muestras"]), "finales:", ref[k]["finales"])


asyncio.run(main())
