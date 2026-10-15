"""Genera pruebas/referencia_piloto_uav_js.json para pruebas/prueba_piloto_uav.gd: un vuelo del Cernicalo XM-7 con el
piloto automatico del navegador (simulador/js/piloto_uav.js con la fisica de modelos.js) sobre un suelo plano con una
pista: despegue automatico, estabilizado con la palanca, crucero con cambios de rumbo, altura y velocidad, ir a punto
y aterrizaje automatico hasta pararse. Aqui y alli, el mismo guion (si se cambia, hay que cambiarlo igual en los dos).
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
  return { muestras: out, cambios, fin };
}
"""
with sync_playwright() as p:
    b = p.chromium.launch(channel="chrome", args=["--allow-file-access-from-files"]); pg = b.new_page()
    err = []; pg.on("pageerror", lambda e: err.append(str(e)))
    pg.goto(URL); pg.wait_for_function("typeof Modelos !== 'undefined' && !!Modelos.datos('XM7') && typeof PilotoUAV !== 'undefined'", timeout=60000)
    r = pg.evaluate(GUION); b.close()
assert not err, err
json.dump(r, open(AQUI / "referencia_piloto_uav_js.json", "w", encoding="utf-8"), separators=(",", ":"))
print(len(r["muestras"]), "muestras; cambios:", r["cambios"], "; final:", r["fin"], r["muestras"][-1].get("p"))
