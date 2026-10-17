# Genera simulador_godot/Tests/referencia_pista_fpv_js.json para simulador_godot/Tests/prueba_pista_fpv.gd: vuelos de prueba por la pista FPV (las 6
# misiones del dron FPV de escenarios.js, con aciertos, fallos y choques; posiciones dadas, sin fisica) y lo que dice de
# cada uno la clase PistaFpv de simulador_web/js/pista_fpv.js en el navegador: objetivos, avisos, choque y la linea "Ahora".
# Necesita Python con playwright y Chrome. Uso (desde la carpeta del repositorio):
#     python simulador_godot/Tests/generar_referencia_pista_fpv.py
import json, math, os, pathlib
from playwright.sync_api import sync_playwright
RAIZ = pathlib.Path(__file__).resolve().parents[2]
DT = 0.05
def tramo(pts, v=8.0, yaw=None, modo=None):
    """pts: [(N, E, h)], a velocidad v; yaw None = mirando hacia donde va."""
    out = []
    for (a, b) in zip(pts, pts[1:]):
        d = math.dist(a, b); n = max(1, int(d / v / DT))
        y = yaw if yaw is not None else math.degrees(math.atan2(b[1] - a[1], b[0] - a[0])) if math.hypot(b[0]-a[0], b[1]-a[1]) > 1e-6 else None
        for i in range(n):
            f = i / n; out.append([a[0] + f * (b[0] - a[0]), a[1] + f * (b[1] - a[1]), a[2] + f * (b[2] - a[2]), y])
    out.append(list(pts[-1]) + [out[-1][3] if out else yaw])
    return out
def quieto(p, s, yaw): return [list(p) + [yaw]] * int(s / DT)
def circulo(c, r, h, a0, vueltas, sentido, v=6):
    n = int(2 * math.pi * r * vueltas / v / DT); out = []
    for i in range(n + 1):
        a = a0 + sentido * 2 * math.pi * vueltas * i / n
        yaw = math.degrees(a + sentido * math.pi / 2)
        out.append([c[0] + r * math.cos(a), c[1] + r * math.sin(a), h, yaw])
    return out
def vuelo(nombre, mision, cuerpo, aterriza=True, modo=None, desarma_tras=1.0):
    """despegue desde la plataforma, cuerpo, vuelta a la plataforma, posarse y desarmar"""
    S = [-20, 0]
    seq = quieto((S[0], S[1], 0.02), 0.5, 180) + tramo([(S[0], S[1], 0.02), (S[0], S[1], 2)], v=1.5, yaw=180)
    seq += cuerpo(seq[-1])
    if aterriza:
        u = seq[-1]; seq += tramo([(u[0], u[1], u[2]), (S[0], S[1], 2)], yaw=None) + tramo([(S[0], S[1], 2), (S[0], S[1], 0.02)], v=1, yaw=180)
    estados = []; t = 0; desp = False
    for i, (N, E, h, y) in enumerate(seq):
        if h > 0.3: desp = True
        posado = h <= 0.03
        estados.append([round(N, 3), round(E, 3), round(h, 3), round(y if y is not None else 180, 2), int(posado), int(desp), round(t, 2)])
        t += DT
    if aterriza:
        u = list(estados[-1])
        for k in range(int(desarma_tras / DT)): t += DT; u = u[:6] + [round(t, 2)]; estados.append(u)
    return {"nombre": nombre, "mision": mision, "modo": modo, "estados": estados, "final": "aterrizado" if aterriza else "roto"}
V = []
# 1. estacionario: 21 s en el cilindro; y otro que sale a los 10 s
V.append(vuelo("estacionario ok", "fpv_estacionario", lambda u: tramo([(u[0], u[1], 2), (-32, 0, 2)], yaw=180) + quieto((-32, 0.5, 2), 21, 180)))
V.append(vuelo("estacionario corto + desarma tarde", "fpv_estacionario", lambda u: tramo([(u[0], u[1], 2), (-32, 0, 2)], yaw=180) + quieto((-32, 0, 2), 10, 180) + quieto((-32, 0, 3.2), 1, 180) + quieto((-32, 0, 2), 12, 180), desarma_tras=4))
# 2. la caja: fase 1 morro al sur, fase 2 morro hacia cada cono
C = [(-28, -10), (-48, -10), (-48, 10), (-28, 10)]
def caja(u):
    s = tramo([(u[0], u[1], 1.5), (C[0][0], C[0][1], 1.5)], yaw=180)
    for a, b in zip(C, C[1:]): s += tramo([(a[0], a[1], 1.5), (b[0], b[1], 1.5)], yaw=180)
    s += tramo([(C[3][0], C[3][1], 1.5), (-20, 0, 1.5), (C[0][0], C[0][1], 1.5)])
    for a, b in zip(C, C[1:]): s += tramo([(a[0], a[1], 1.5), (b[0], b[1], 1.5)])
    return s
V.append(vuelo("caja ok", "fpv_caja", caja))
V.append(vuelo("caja con giro en fase 1 y techo", "fpv_caja", lambda u: tramo([(u[0], u[1], 1.5), (C[0][0], C[0][1], 1.5)], yaw=180) + tramo([(C[0][0], C[0][1], 1.5), (C[1][0], C[1][1], 1.5)]) + tramo([(C[1][0], C[1][1], 1.5), (C[1][0], C[1][1], 5)], yaw=180)))
# 3. slalom alternando y ocho
def slalom(u, malo=False):
    pts = [(u[0], u[1], 2), (-50, 0, 2)]
    lados = [3, -3, 3, -3, 3] if not malo else [3, -3, -3, 3, -3]
    for k, n in enumerate([-55, -70, -85, -100, -115]): pts.append((n, lados[k], 2))
    pts.append((-125, 0, 2)); s = tramo(pts)
    s += tramo([(-125, 0, 2), (-135, -7, 2)]) + circulo((-135, -12), 5, 2, 0, 1.0, 1) + tramo([(-135, -7, 2), (-135, 7, 2)]) + circulo((-135, 12), 5, 2, math.pi, 1.0, -1)
    s += tramo([(-135, 7, 2), (-60, 20, 2)])
    return s
V.append(vuelo("slalom y ocho ok", "fpv_slalom", slalom))
V.append(vuelo("slalom mismo lado", "fpv_slalom", lambda u: slalom(u, True)))
V.append(vuelo("choque con poste", "fpv_slalom", lambda u: tramo([(u[0], u[1], 2), (-50, 0, 2), (-55, 0, 2)]), aterriza=False))
# 4. circuito: 2 vueltas (3 m antes y 3 m despues de cada puerta, a 1 m)
G = [(-60, -25, 180), (-95, -35, 180), (-130, -10, 90), (-120, 30, 0), (-85, 35, 0), (-60, 15, 270)]
def antes_despues(g, d=4, h=1):
    r = math.radians(g[2]); return [(g[0] - d * math.cos(r), g[1] - d * math.sin(r), h), (g[0] + d * math.cos(r), g[1] + d * math.sin(r), h)]
def circuito(u, vueltas=2, saltar=False):
    pts = [(u[0], u[1], 1)]
    for v in range(vueltas):
        for i, g in enumerate(G):
            if saltar and v == 0 and i == 2: continue
            pts += antes_despues(g)
    return tramo(pts, v=12)
V.append(vuelo("circuito 2 vueltas", "fpv_circuito", circuito))
V.append(vuelo("circuito saltando la 3", "fpv_circuito", lambda u: circuito(u, 1, True)))
V.append(vuelo("choque con la puerta 1", "fpv_circuito", lambda u: tramo([(u[0], u[1], 1), (-55, -23.8, 1), (-65, -23.8, 1)]), aterriza=False))
V.append(vuelo("cambio de modo", "fpv_circuito", lambda u: tramo([(u[0], u[1], 1), (-40, 0, 1)]), modo="ACRO"))
# 5. recta oeste y este y una vuelta
V.append(vuelo("acro ok", "fpv_acro", lambda u: tramo([(u[0], u[1], 2.5), (-45, 45, 2.5), (-45, -45, 2.5), (-45, 45, 2.5)]) + circuito((-45, 45, 1), 1)))
V.append(vuelo("recta alta", "fpv_acro", lambda u: tramo([(u[0], u[1], 5), (-45, 45, 5), (-45, -45, 5)])))
# 6. power loop, split-S y picado
PA = (-80, 15)
def tecnica(u):
    s = tramo([(u[0], u[1], 7.5), (-70, 15, 7.5), (-90, 15, 7.5), (-92, 15, 13), (-75, 15, 13), (-70, 15, 7.5), (-90, 15, 7.5)], v=14)   # power loop
    s += tramo([(-90, 15, 7.5), (-95, 15, 7.5), (-70, 15, 7.5)], v=14)                                                                # split-S
    s += tramo([(-70, 15, 7.5), (-100, -22, 27), (-100, -24, 27), (-100, -24, 4), (-60, 0, 3)], v=12)                                 # picado
    return s
V.append(vuelo("tecnica ok", "fpv_tecnica", tecnica))
V.append(vuelo("choque con la torre", "fpv_tecnica", lambda u: tramo([(u[0], u[1], 5), (-100, -30, 5)]), aterriza=False))

JS = r"""V => V.map(v => { const DTP = 0.05;
  const E = ESCENARIOS[v.mision], obj = {};
  for (const [id, t] of E.objetivos) obj[id] = { texto: t, estado: ["modo", "bateria", "bajo4", "altura13"].includes(id) ? "curso" : "pend" };
  const marcar = (k, e) => { if (obj[k] && obj[k].estado !== "mal") obj[k].estado = e; };
  const pf = new PistaFpv(E.pista_fpv, marcar), avisos = [], ahora = [];
  let pAnt = null, av = null, choque = null;
  v.estados.forEach((s, i) => {
    av = { p: [s[0], s[1], -s[2]], q: Cuat.desdeEuler(0, 0, s[3] * D2R), estado: "volando", posado: !!s[4], despegado: !!s[5], armado: true, t: s[6] };
    if (choque) return;
    if (pAnt) for (const t of pf.paso(pAnt, av, DTP, { modo: v.modo || E.pista_fpv.modo, critica: false })) avisos.push(s[6].toFixed(2) + " " + t);
    if (pf.choque) choque = pf.choque;
    if (i % 100 === 0) ahora.push(pf.ahora(obj, av));
    pAnt = av.p;
  });
  const fin = choque ? "roto" : v.final;
  if (fin === "aterrizado") { pf.final(fin, av); marcar("aterrizar", "ok"); }
  for (const o of Object.values(obj)) if (o.estado === "curso") o.estado = fin === "aterrizado" ? "ok" : "mal";
  for (const o of Object.values(obj)) if (o.estado === "pend") o.estado = "mal";
  return { nombre: v.nombre, choque, objetivos: Object.fromEntries(Object.entries(obj).map(([k, o]) => [k, o.estado])), avisos, ahora };
})"""
url = (RAIZ / "simulador_web" / "simulador.html").as_uri()
with sync_playwright() as p:
    b = p.chromium.launch(channel="chrome", args=["--use-angle=swiftshader", "--allow-file-access-from-files"]); pg = b.new_page()
    err = []; pg.on("pageerror", lambda e: err.append(str(e)))
    pg.goto(url); pg.wait_for_timeout(2500)
    r = pg.evaluate(JS, V); b.close()
assert not err, err
for v, x in zip(V, r): v["web"] = x
json.dump(V, open(RAIZ / "simulador_godot" / "Tests" / "referencia_pista_fpv_js.json", "w", encoding="utf-8"), ensure_ascii=False, separators=(",", ":"))
for x in r: print(x["nombre"], "| choque:", x["choque"], "|", " ".join(k for k, e in x["objetivos"].items() if e == "ok"))
