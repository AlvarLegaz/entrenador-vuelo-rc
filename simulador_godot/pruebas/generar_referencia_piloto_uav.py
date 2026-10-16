"""Genera pruebas/referencia_piloto_uav_js.json para pruebas/prueba_piloto_uav.gd: un vuelo del Cernicalo XM-7 con el
piloto automatico del navegador (simulador/js/piloto_uav.js con la fisica de modelos.js) sobre un suelo plano con una
pista: despegue automatico, estabilizado con la palanca, crucero con cambios de rumbo, altura y velocidad, ir a punto
y aterrizaje automatico hasta pararse; y un vuelo del Grajo MX-2 (sin pista: lanzamiento, crucero y toma en perdida
profunda con viento). Aqui y alli, el mismo guion (si se cambia, hay que cambiarlo igual en los dos).
Necesita Python con playwright y Chrome. Uso (desde la carpeta del repositorio):
    python simulador_godot/pruebas/generar_referencia_piloto_uav.py
"""
import json, pathlib
from playwright.sync_api import sync_playwright
AQUI = pathlib.Path(__file__).resolve().parent
URL = (AQUI.parent.parent / "simulador" / "simulador.html").as_uri()
GUION = r"""
() => {
  const DT = 0.002, m = Modelos.crear("XM7"), a = m.estadoInicial(), out = [], cambios = [];
  const pista = { n: 0, e: 0, rumbo: 30, largo: 2300, h: 5 };
  const ap = new PilotoUAV(m.piloto, pista, [0, 0, 5]);
  a.p = [0, 0, -(5 + m.alturaEnTierra())]; a.q = Cuat.desdeEuler(0, 0, 30 * D2R); m.lanzar(a); a.asim = 0.37;
  const mm = { pitch: 0, yaw: 0, guinada: 0, trim: 0 };
  const poner = (t, modo, punto) => cambios.push([+t.toFixed(3), modo, ap.poner(modo, a, punto)]);
  poner(0, "DESPEGUE");
  let fin = "";
  for (let i = 0; i < Math.trunc(760 / DT); i++) {
    const t = i * DT;
    if (i === Math.trunc(45 / DT)) poner(t, "ESTAB");
    if (i === Math.trunc(60 / DT)) poner(t, "CRUCERO");
    if (i === Math.trunc(120 / DT)) poner(t, "PUNTO", [2500, 1800]);
    if (i === Math.trunc(220 / DT)) poner(t, "ATERRIZAJE");
    const pal = { pitch: t > 45 && t < 52 ? 0.3 : (t > 70 && t < 80 ? 0.5 : 0), yaw: t > 45 && t < 53 ? 0.4 : (t > 85 && t < 95 ? -0.6 : 0), guinada: 0 };
    a.agl = -a.p[2] - 5;
    const o = ap.paso(a, DT, pal, t < 100 ? 0.4 : 0.6);
    mm.pitch = o.pitch; mm.yaw = o.yaw; mm.guinada = o.guinada;
    if (o.gas !== null) a.gases = o.gas; else a.gases = 0.6;
    if (o.freno !== null) a.freno = o.freno;
    if (i % 1000 === 0) out.push({ t, p: a.p.slice(), q: a.q.slice(), v: a.v.slice(), modo: ap.modo, fase: ap.fase, gas: a.gases });
    m.servos(a, mm, DT);
    m.paso(a, [2, -1, 0], DT);
    const f = m.finTren(a);
    if (f) { fin = f; out.push({ t, fin: f, p: a.p.slice() }); break; }
  }
  // el Grajo MX-2 (sin pista): lanzado a mano, sube solo, crucero y toma en perdida profunda junto a la casa con 4 m/s
  // de viento del norte (la final, hacia el norte)
  const g = Modelos.crear("GRAJO"), b = g.estadoInicial(), og = [], cg = [];
  const apg = new PilotoUAV(g.piloto, null, [0, 0, 0]); apg.vientoDesde = 0; apg.vientoVel = 4;
  b.p = [0, 0, -1.6]; g.lanzar(b); b.asim = 0.2;
  const mg = { pitch: 0, yaw: 0, guinada: 0, trim: 0 };
  cg.push([0, "LANZAMIENTO", apg.poner("LANZAMIENTO", b)]);
  let fing = "";
  for (let i = 0; i < Math.trunc(400 / DT); i++) {
    const t = i * DT;
    if (i === Math.trunc(80 / DT)) cg.push([+t.toFixed(3), "ATERRIZAJE", apg.poner("ATERRIZAJE", b)]);
    b.agl = -b.p[2];
    const o = apg.paso(b, DT, { pitch: 0, yaw: 0, guinada: 0 }, 0);
    mg.pitch = o.pitch; mg.yaw = o.yaw; mg.guinada = o.guinada; b.gases = o.gas !== null ? o.gas : 0;
    if (i % 1000 === 0) og.push({ t, p: b.p.slice(), q: b.q.slice(), v: b.v.slice(), modo: apg.modo, fase: apg.fase, gas: b.gases });
    g.servos(b, mg, DT);
    g.paso(b, [-4, 0, 0], DT);
    if (-b.p[2] <= 0) { fing = b.alfa > g.toma_perdida.alfa_min ? "toma en perdida" : "otro"; og.push({ t, fin: fing, p: b.p.slice(), alfa: b.alfa }); break; }
  }
  // y otra vez con los sensores averiados (js/desgaste.js): el piloto trabaja con lo que creen el GPS, la brujula, la IMU
  // y el barometro: crucero y luego ir a un punto
  const s2 = Modelos.crear("GRAJO"), c2 = s2.estadoInicial(), os2 = [];
  const ap2 = new PilotoUAV(s2.piloto, null, [0, 0, 0]); ap2.vientoDesde = 0; ap2.vientoVel = 4;
  ap2.sens = { rumbo: 50 * D2R, alabeo: 3 * D2R, cabeceo: -2 * D2R, gps: 3.5, vz: 0.15 };
  c2.p = [0, 0, -1.6]; s2.lanzar(c2); c2.asim = 0.2; const m2 = { pitch: 0, yaw: 0, guinada: 0, trim: 0 };
  ap2.poner("LANZAMIENTO", c2);
  for (let i = 0; i < Math.trunc(150 / DT); i++) {
    const t = i * DT;
    if (i === Math.trunc(70 / DT)) ap2.poner("PUNTO", c2, [300, 200]);
    c2.agl = -c2.p[2];
    const o = ap2.paso(c2, DT, { pitch: 0, yaw: 0, guinada: 0 }, 0);
    m2.pitch = o.pitch; m2.yaw = o.yaw; c2.gases = o.gas !== null ? o.gas : 0;
    if (i % 1000 === 0) os2.push({ t, p: c2.p.slice(), q: c2.q.slice(), modo: ap2.modo, fase: ap2.fase });
    s2.servos(c2, m2, DT); s2.paso(c2, [-4, 0, 0], DT);
    if (-c2.p[2] <= 0) { os2.push({ t, fin: "suelo", p: c2.p.slice() }); break; }
  }
  return { muestras: out, cambios, fin, grajo: { muestras: og, cambios: cg, fin: fing }, grajo_sens: { muestras: os2 } };
}
"""
with sync_playwright() as p:
    b = p.chromium.launch(channel="chrome", args=["--allow-file-access-from-files"]); pg = b.new_page()
    err = []; pg.on("pageerror", lambda e: err.append(str(e)))
    pg.goto(URL); pg.wait_for_function("typeof Modelos !== 'undefined' && !!Modelos.datos('XM7') && !!Modelos.datos('GRAJO') && typeof PilotoUAV !== 'undefined'", timeout=60000)
    r = pg.evaluate(GUION); b.close()
assert not err, err
json.dump(r, open(AQUI / "referencia_piloto_uav_js.json", "w", encoding="utf-8"), separators=(",", ":"))
print(len(r["muestras"]), "muestras; cambios:", r["cambios"], "; final:", r["fin"], r["muestras"][-1].get("p"))
print("Grajo con sensores averiados:", len(r["grajo_sens"]["muestras"]), "muestras; final", r["grajo_sens"]["muestras"][-1])
G = r["grajo"]; print("Grajo:", len(G["muestras"]), "muestras; cambios:", G["cambios"], "; final:", G["fin"], G["muestras"][-1])
