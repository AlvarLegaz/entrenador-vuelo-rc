"""Regenera la parte "aviones" de pruebas/referencia_js.json: trazas del simulador del navegador (ModeloAvion de
simulador/js/modelos.js, las clases de simulador/aviones/*.js y Entorno.vientoA de simulador/js/entorno.js) en el
mismo vuelo de 16 s que _traza() de pruebas/prueba_fisica.gd, para el E3 (Entrenador 1) y el T1 con sus datos de diseno, con una
configuracion distinta y en la dificultad facil. Si se cambia el vuelo aqui, hay que cambiarlo igual alli.

La parte "entorno" (terreno, viento junto al suelo, turbulencia) no depende de los aviones: se deja como esta.
Hay que lanzarlo despues de regenerar un avion (scripts/modelo_aero_e1.py), porque sus trazas cambian.

Uso (desde la carpeta del repositorio; necesita Python con playwright y Google Chrome instalado):
    python simulador_godot/pruebas/generar_referencia_fisica.py [url de simulador.html]
Sin url abre simulador/simulador.html como fichero (no hace falta servidor).
"""
import asyncio, json, pathlib, sys
from playwright.async_api import async_playwright

AQUI = pathlib.Path(__file__).resolve().parent
URL = sys.argv[1] if len(sys.argv) > 1 else (AQUI.parent.parent / "simulador" / "simulador.html").as_uri()
REF = AQUI / "referencia_js.json"
AVIONES = ["E3", "T1"]

# _traza() de prueba_fisica.gd, linea a linea
GUION = r"""
(() => {
  const DT = 0.002, ent = new Entorno();
  function traza(id, conf, facil) {
    const m = Modelos.crear(id);
    if (conf) m.configurar(conf);
    m.facil = facil; ent.facil = facil;
    const a = m.estadoInicial();
    a.asim = 0.37; a.p = [0, 0, -80]; a.q = Cuat.desdeEuler(0.05, 0.03, 0.2); a.v = [11, 0.3, 0.1];
    a.w = [0, 0, 0]; a.estado = "volando";
    const mm = { pitch: 0, yaw: 0, trim: m.compensador_grados };
    const out = [];
    for (let i = 0; i < Math.trunc(16 / DT) + 1; i++) {
      const t = i * DT;
      mm.pitch = t >= 10 && t < 14 ? 1 : 0.4 * Math.sin(0.9 * t); mm.yaw = 0.6 * Math.sin(1.7 * t);
      a.gases = t < 6 ? 1 : (t < 12 ? 0.5 : 0);
      if (i % 500 === 0)
        out.push({ t, p: a.p.slice(), v: a.v.slice(), w: a.w.slice(), q: a.q.slice(), de: a.de, da: a.da, dr: a.dr, Wh: a.Wh, T: a.T });
      m.servos(a, mm, DT);
      a.agl = -a.p[2]; a.pg = 0.05 * Math.sin(3 * t);
      m.paso(a, ent.vientoA([2, -1, 0.2], a.agl), DT);
    }
    ent.facil = false;
    return out;
  }
  // avion de pista (XM-7): parado con freno, gas, suelta el freno, carrera con la rueda de morro, rotacion y subida
  function pista(id) {
    const m = Modelos.crear(id), a = m.estadoInicial(), out = [];
    m.lanzar(a); a.asim = 0.37;
    const mm = { pitch: 0, yaw: 0, guinada: 0, trim: m.compensador_grados };
    for (let i = 0; i < Math.trunc(24 / DT) + 1; i++) {
      const t = i * DT;
      a.gases = t < 1 ? 0.1 : 1; a.freno = t < 2 ? 1 : 0;
      mm.pitch = t >= 12 && t < 14 ? 0.4 : (t >= 14 ? 0.12 : 0); mm.guinada = 0.15 * Math.sin(0.6 * t); mm.yaw = t > 15 ? 0.3 * Math.sin(0.8 * t) : 0;
      if (i % 500 === 0)
        out.push({ t, p: a.p.slice(), v: a.v.slice(), w: a.w.slice(), q: a.q.slice(), de: a.de, da: a.da, dr: a.dr, Wh: a.Wh, T: a.T, tierra: a.enTierra ? 1 : 0 });
      m.servos(a, mm, DT);
      a.agl = -a.p[2] - 0.02 * Math.sin(0.05 * a.p[0]); a.pg = 0;
      m.paso(a, ent.vientoA([3, 1, 0], a.agl), DT);
      const f = m.finTren(a);
      if (f) { out.push({ fin: f, t }); break; }
    }
    return out;
  }
  const res = {};
  res.XM7 = { pista: pista("XM7") };
  for (const id of AVIONES_JSON) {
    const A = Modelos.datos(id);
    const cf = { masa_kg: A.masa_kg * 1.1, cg_mm: A.cg_mm[0] + 5, temperatura: 30, empuje_gf: 800, resistencia: 1.2 };
    res[id] = { normal: traza(id, null, false), config: traza(id, cf, false), facil: traza(id, cf, true) };
  }
  return JSON.stringify(res);
})()
""".replace("AVIONES_JSON", json.dumps(AVIONES))


async def main():
    async with async_playwright() as p:
        b = await p.chromium.launch(channel="chrome", headless=True,
                                    args=["--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist"])
        pg = await b.new_page()
        errores = []
        pg.on("pageerror", lambda e: errores.append(str(e)))
        await pg.goto(URL)
        await pg.wait_for_function("typeof Modelos !== 'undefined' && %s.every(id => !!Modelos.datos(id))" % json.dumps(AVIONES + ["XM7"]),
                                   timeout=30000)
        nuevas = json.loads(await pg.evaluate(GUION))
        await b.close()
    if errores:
        print("errores en la pagina:", errores)
    ref = json.loads(REF.read_text(encoding="utf-8"))
    for id_ in AVIONES:   # diferencia con la referencia anterior (los aviones que no se han tocado deben dar 0)
        d = 0.0
        for nombre, tr in nuevas[id_].items():
            for a, b_ in zip(tr, ref["aviones"].get(id_, {}).get(nombre, [])):
                d = max(d, max(abs(x - y) for x, y in zip(a["p"], b_["p"])))
        print("%s: diferencia maxima de posicion con la referencia anterior %.3g m" % (id_, d))
    ref["aviones"] = nuevas
    REF.write_text(json.dumps(ref, separators=(",", ":")), encoding="utf-8")
    print("escrito", REF)


asyncio.run(main())
