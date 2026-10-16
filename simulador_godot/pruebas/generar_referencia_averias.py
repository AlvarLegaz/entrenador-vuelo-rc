"""Genera pruebas/referencia_averias_js.json con simulador/js/desgaste.js en el navegador: (1) trazas de vuelo con cada
averia (Mini Dron HQ: helice, motor, brujula, IMU, GPS, barometro y bateria; FPV: helice y motor; aviones: helice,
motor, servo con holgura, bisagra floja y celda debil) con un guion de mandos, aplicando las averias como el simulador
(Desgaste.aplicar, antesPaso y despuesPaso alrededor de modelo.paso); (2) el desgaste de muchos vuelos seguidos de cada
vehiculo (trasVuelo, con su azar con semilla) y (3) lo que dice el Taller (revisiones, reparaciones y el libro).
Escribe tambien simulador/js/catalogo_averias.js (las averias de cada vehiculo, para el panel del profesor).
pruebas/prueba_averias.gd repite lo mismo en Godot y compara. Si se cambia el guion aqui, hay que cambiarlo igual alli.

    python simulador_godot/pruebas/generar_referencia_averias.py
"""
import asyncio, json, pathlib, sys
from playwright.async_api import async_playwright

AQUI = pathlib.Path(__file__).resolve().parent
URL = sys.argv[1] if len(sys.argv) > 1 else (AQUI.parent.parent / "simulador" / "simulador.html").as_uri()

GUION = r"""
(() => {
  const DT = 0.002, VIENTO = [-3.2, 2.4, 0];
  const ent = new Entorno();
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
  function traza(caso) {
    const A = Modelos.datos(caso.avion), k = Desgaste.clase(A), m = Modelos.crear(caso.avion);
    const est = Object.assign(Desgaste.nuevo(), { averias: caso.averias.map(a => Object.assign({ origen: "profesor", fecha: "" }, a)) });
    if (caso.salud) est.bateria.salud = caso.salud;
    Desgaste.aplicar(m, est);
    const a = m.estadoInicial(), mando = { pitch: 0, yaw: 0, guinada: 0, vz: 0, gimbal: 0, trim: 0 }, FIN = k === "cuad" ? 40 : k === "fpv" ? 20 : 25;
    const muestras = [], finales = [];
    for (let i = 0; i <= FIN * 500; i++) {
      const t = i * DT;
      if (k === "cuad") {
        if (i === 250) m.lanzar(a);
        mando.vz = en(1, 6, i) ? 0.8 : 0; mando.pitch = en(10, 14, i) ? -1 : 0; mando.yaw = en(16, 18, i) ? 0.5 : 0; mando.guinada = en(20, 22, i) ? 1 : 0;
      } else if (k === "fpv") {
        if (i === 250) m.lanzar(a);
        if (i >= 250) a.gases = 0.62;
        mando.yaw = en(8, 9, i) ? 0.3 : 0; mando.pitch = en(10, 12, i) ? -0.3 : 0;
      } else {
        if (i === 0) { m.lanzar(a); a.asim = 0.37; a.p = [0, 0, -80]; a.q = Cuat.desdeEuler(0.05, 0.03, 0.2); a.v = [12, 0.3, 0.1]; mando.trim = m.compensador_grados || 0; }
        a.gases = 0.8; mando.pitch = 0.4 * Math.sin(0.9 * t); mando.yaw = 0.6 * Math.sin(1.7 * t);
      }
      if (i % 250 === 0)
        muestras.push({ t, p: a.p.slice(), v: a.v.slice(), w: a.w.slice(), q: a.q.slice(), Wh: a.Wh, estado: a.estado,
                        V: a.bat ? a.bat.V : 0, celdas: a.bat ? a.bat.celdas.slice() : [], avisoBat: a.avisoBat || "" });
      m.servos(a, mando, DT);
      a.agl = -a.p[2];
      const viento = ent.vientoA(VIENTO, a.agl);
      a.pg = 0.03 * Math.sin(3 * t);
      if (a.estado !== "volando") continue;
      Desgaste.antesPaso(m, a);
      const vn = m.paso(a, viento, DT);
      Desgaste.despuesPaso(m, a, DT);
      const final = contacto(a, vn);
      if (final) {
        a.estado = final.startsWith("roto") ? "roto" : final === "aterrizado" ? "aterrizado" : "terminado";
        a.v = [0, 0, 0]; a.w = [0, 0, 0]; a.rpm = 0;
        finales.push({ t, final, N: a.p[0], E: a.p[1] });
      }
    }
    return { muestras, finales };
  }
  const CASOS = [
    { id: "mini_sin", avion: "DJI_MINI", averias: [] },
    { id: "mini_helice", avion: "DJI_MINI", averias: [{ c: "helice2", tipo: "mella" }] },
    { id: "mini_motor", avion: "DJI_MINI", averias: [{ c: "motor3", tipo: "rodamiento" }] },
    { id: "mini_brujula", avion: "DJI_MINI", averias: [{ c: "brujula", tipo: "descalibrada" }] },
    { id: "mini_imu", avion: "DJI_MINI", averias: [{ c: "imu", tipo: "descalibrada" }] },
    { id: "mini_gps", avion: "DJI_MINI", averias: [{ c: "gps", tipo: "antena" }] },
    { id: "mini_barometro", avion: "DJI_MINI", averias: [{ c: "barometro", tipo: "deriva" }] },
    { id: "mini_celda", avion: "DJI_MINI", averias: [{ c: "bateria", tipo: "celda", n: 1 }] },
    { id: "mini_hinchada", avion: "DJI_MINI", averias: [{ c: "bateria", tipo: "hinchada" }] },
    { id: "mini_envejecida", avion: "DJI_MINI", averias: [{ c: "bateria", tipo: "envejecida" }], salud: 0.7 },
    { id: "hq3t_varias", avion: "HQ3T", averias: [{ c: "helice4", tipo: "mella" }, { c: "gps", tipo: "antena" }, { c: "bateria", tipo: "celda", n: 3 }] },
    { id: "fpv_helice", avion: "FPV", averias: [{ c: "helice1", tipo: "mella" }] },
    { id: "fpv_motor", avion: "FPV", averias: [{ c: "motor2", tipo: "rodamiento" }] },
    { id: "e3_helice", avion: "E3", averias: [{ c: "helice", tipo: "mella" }] },
    { id: "e3_motor", avion: "E3", averias: [{ c: "motor", tipo: "rodamiento" }] },
    { id: "e3_servo", avion: "E3", averias: [{ c: "servo_alerones", tipo: "holgura" }] },
    { id: "e3_bisagra", avion: "E3", averias: [{ c: "bisagra_profundidad", tipo: "floja" }] },
    { id: "e3_celda", avion: "E3", averias: [{ c: "bateria", tipo: "celda", n: 2 }] },
    { id: "t1_servo", avion: "T1", averias: [{ c: "servo_elevon_izq", tipo: "holgura" }, { c: "bisagra_elevon_der", tipo: "floja" }] },
    { id: "g1_timon", avion: "G1", averias: [{ c: "bisagra_timon", tipo: "floja" }, { c: "servo_profundidad", tipo: "holgura" }] },
  ];
  const trazas = {};
  for (const c of CASOS) trazas[c.id] = traza(c);
  // desgaste de 14 vuelos seguidos de cada vehiculo (empieza con 0,8 h: los primeros no rompen nada)
  const desgaste = {}, taller = {}, catalogo = {};
  for (const id of ["DJI_MINI", "HQ3T", "FPV", "E3", "T1", "G1", "XM7"]) {
    const A = Modelos.datos(id), est = Object.assign(Desgaste.nuevo(), { horas: 0.8 }), pasos = [];
    for (let k = 0; k < 14; k++) {
      const info = { s: 600 + 97 * k, roto: k % 5 === 3, bat0: 100, bat1: k % 4 === 2 ? 7 : 35, tempMax: k % 6 === 4 ? 61 : 32, semilla: "vuelo-" + k + "-" + id, fecha: "2026-10-16T10:" + String(k).padStart(2, "0") + ":00Z" };
      const nuevas = Desgaste.trasVuelo(est, A, info);
      pasos.push({ nuevas: nuevas.map(a => [a.c, a.tipo, a.n === undefined ? -1 : a.n, a.origen]), horas: est.horas, salud: est.bateria.salud, ciclos: est.bateria.ciclos, n: est.averias.length });
    }
    desgaste[id] = pasos;
    const rev = Object.fromEntries(Desgaste.revisiones(A).map(([r]) => [r, Desgaste.revisar(est, A, r)]));
    const reps = Desgaste.reparaciones(A).map(r => [r[0], r[1], r[2]]);
    const libro = [];
    for (const r of [reps[0][0], est.averias.length ? (reps.find(x => x[2].includes(est.averias[0].c)) || reps[0])[0] : reps[1][0], "bateria"])
      libro.push(Desgaste.reparar(est, A, r, "2026-10-16T12:00:00Z"));
    taller[id] = { revisiones: rev, reparaciones: reps, libro, quedan: est.averias.map(Desgaste.nombre), h: est.h, bateria: est.bateria };
    catalogo[id] = Desgaste.posibles(A).map(a => [a.c, a.tipo, a.n === undefined ? -1 : a.n, a.nombre]);
  }
  const nombres = Object.fromEntries(Object.keys(catalogo).map(id => [id, Modelos.datos(id).nombre]));
  return JSON.stringify({ DT, VIENTO, CASOS, trazas, desgaste, taller, catalogo, nombres });
})()
"""


async def main():
    async with async_playwright() as p:
        b = await p.chromium.launch(channel="chrome", headless=True, args=["--use-angle=swiftshader", "--enable-unsafe-swiftshader"])
        pg = await b.new_page(); errores = []
        pg.on("pageerror", lambda e: errores.append(str(e)))
        await pg.goto(URL)
        await pg.wait_for_function("typeof Modelos !== 'undefined' && !!Modelos.datos('DJI_MINI') && !!Modelos.datos('FPV') && !!Modelos.datos('HQ3T') && typeof Desgaste !== 'undefined'", timeout=30000)
        ref = json.loads(await pg.evaluate(GUION))
        await b.close()
    if errores: print("errores en la pagina:", errores)
    (AQUI / "referencia_averias_js.json").write_text(json.dumps(ref, separators=(",", ":"), ensure_ascii=False), encoding="utf-8")
    # el catalogo de averias de cada vehiculo para el panel del profesor (simulador/js/catalogo_averias.js)
    cat = {k: {"nombre": ref["nombres"][k], "averias": v} for k, v in ref["catalogo"].items()}
    (AQUI.parent.parent / "simulador" / "js" / "catalogo_averias.js").write_text(
        "// Generado por simulador_godot/pruebas/generar_referencia_averias.py con Desgaste.posibles (js/desgaste.js): no editar a mano.\n"
        "// Las averias que el profesor puede poner a cada vehiculo: [componente, tipo, celda (-1 si no), nombre].\n"
        "const CATALOGO_AVERIAS = " + json.dumps(cat, ensure_ascii=False, separators=(",", ":")) + ";\n", encoding="utf-8")
    for k, v in ref["trazas"].items():
        u = v["muestras"][-1]
        print("%-16s %3d muestras, final %s, p=%s, Wh=%.3f" % (k, len(v["muestras"]), v["finales"][:1] or u["estado"], [round(x, 2) for x in u["p"]], u["Wh"]))
    for k, v in ref["desgaste"].items():
        print("%-9s" % k, "averias nuevas:", sum(len(x["nuevas"]) for x in v), "salud", v[-1]["salud"], "| libro:", [e["texto"] + (" -> " + ", ".join(e["arreglo"]) if e["arreglo"] else "") for e in ref["taller"][k]["libro"] if e])


asyncio.run(main())
