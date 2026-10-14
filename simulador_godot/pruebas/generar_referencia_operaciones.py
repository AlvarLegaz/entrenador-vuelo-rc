# Genera pruebas/referencia_operaciones_js.json para pruebas/prueba_operaciones.gd: vuelos de prueba de los 6 trabajos del
# modo Operaciones (escenarios.js, "operacion"), con aciertos, fallos, choques y normas incumplidas (posiciones, gimbal,
# video y fotos dados, sin fisica, sobre un suelo ondulado de prueba) y lo que dice de cada uno la clase Operacion de
# simulador/js/operaciones.js en el navegador: objetivos (estado y texto), avisos, choque y la linea "Ahora". Ademas,
# pruebas/referencia_sorteos_js.json: lo que sortea Operacion.sortear (los objetivos al azar de cada trabajo) con unas
# semillas dadas, para comparar con el sortear de operaciones.gd.
# Necesita Python con playwright y Chrome. Uso (desde la carpeta del repositorio):
#     python simulador_godot/pruebas/generar_referencia_operaciones.py
import json, math, pathlib, re
from playwright.sync_api import sync_playwright
RAIZ = pathlib.Path(__file__).resolve().parents[2]
t = open(RAIZ / "simulador" / "escenarios.js", encoding="utf-8").read(); m = re.search(r"(?m)^window[.]ESCENARIOS = ", t)
ESC = json.loads(t[m.end():t.rindex("}") + 1])
DT = 0.1
suelo = lambda N, E: 3 * math.sin(N * 0.01) + 2 * math.cos(E * 0.013)      # el mismo suelo de prueba en los dos lados

def vuelo(nombre, mision, piezas, final="aterrizado", bateria=60, persona=None):
    """piezas: lista de (N, E, altura sobre el suelo, rumbo, gimbal, grabando, foto, posado). Estados: [N, E, arriba, rumbo,
    posado, gimbal, grabando, foto, t]."""
    est = []
    for k, (N, E, h, y, g, rec, foto, pos) in enumerate(piezas):
        est.append([round(N, 3), round(E, 3), round(suelo(N, E) + h, 3), round(y, 3), int(pos), round(g, 3), int(rec), int(foto), round(k * DT, 2)])
    return {"nombre": nombre, "mision": mision, "estados": est, "final": final, "bateria": bateria, "persona": persona}

def tramo(a, b, v=8.0, y=None, g=-10, rec=0):
    """de a a b (N, E, h) a v m/s; y None = mirando hacia donde va."""
    d = math.dist(a, b); n = max(1, int(d / v / DT)); r = []
    yy = y if y is not None else (math.degrees(math.atan2(b[1] - a[1], b[0] - a[0])) if math.hypot(b[0] - a[0], b[1] - a[1]) > 1e-6 else 0)
    for i in range(n): f = i / n; r.append((a[0] + f * (b[0] - a[0]), a[1] + f * (b[1] - a[1]), a[2] + f * (b[2] - a[2]), yy, g, rec, 0, False))
    return r
def quieto(p, s, y, g=-10, rec=0): return [(p[0], p[1], p[2], y, g, rec, 0, False)] * int(s / DT)
def foto(p, y, g): return [(p[0], p[1], p[2], y, g, 0, 1, False), (p[0], p[1], p[2], y, g, 0, 0, False)]
def despegue(c): return [(c[0], c[1], 0, 0, -10, 0, 0, True)] * 3 + tramo((c[0], c[1], 0.1), (c[0], c[1], 5), v=2, y=0)
def aterrizaje(desde, c, y=0): return tramo(desde, (c[0], c[1], 5), y=y) + tramo((c[0], c[1], 5), (c[0], c[1], 0.1), v=1.5, y=y) + [(c[0], c[1], 0, y, -10, 0, 0, True)] * 5
def apuntar(p, q):
    """rumbo y gimbal (grados) para que el punto q (N, E, arriba) salga en el centro desde p (N, E, arriba)."""
    dn, de, dz = q[0] - p[0], q[1] - p[1], q[2] - p[2]
    return math.degrees(math.atan2(de, dn)), math.degrees(math.atan2(dz, math.hypot(dn, de)))
def con_suelo(N, E, h): return (N, E, h)                  # alturas sobre el suelo en las piezas

V = []
# ---- inspeccion ----
O = ESC["op_inspeccion"]["operacion"]; C = (O["salida"]["n"], O["salida"]["e"])
def foto_punto(q, lejos=False, detras=False):
    z = q["cota"]
    if "normal" in q:
        s = -1 if detras else 1; d = 30 if lejos else 10; r = math.radians(q["normal"])
        p = (q["n"] + s * d * math.cos(r), q["e"] + s * d * math.sin(r), z)
    else:
        p = (q["n"] - (8 if not lejos else 22), q["e"], z + (10 if not lejos else 25))
    y, g = apuntar(p, (q["n"], q["e"], z)); h = p[2] - suelo(p[0], p[1])
    return (p[0], p[1], h), y, g
def inspeccion(fallos=False):
    r = despegue(C); u = (C[0], C[1], 5)
    for i, q in enumerate(O["puntos"]):
        p, y, g = foto_punto(q, lejos=fallos and i == 0, detras=fallos and i == 3)
        r += tramo(u, (p[0], p[1], 40)) + tramo((p[0], p[1], 40), p, v=4, y=y, g=g) + foto(p, y, g); u = p
    return r, u
r, u = inspeccion(); V.append(vuelo("inspeccion ok", "op_inspeccion", r + aterrizaje(u, C)))
r, u = inspeccion(True); V.append(vuelo("inspeccion lejos, por detras y aterriza lejos", "op_inspeccion", r + aterrizaje(u, (C[0] + 30, C[1])), bateria=15))
# ---- fotogrametria ----
O = ESC["op_fotogrametria"]["operacion"]; C = (O["salida"]["n"], O["salida"]["e"]); P = O["parcela"]
def malla(h=50, g=-90):
    r = despegue(C) + tramo((C[0], C[1], 5), (P["n0"] + 15, P["e0"] - 10, h)); u = (P["n0"] + 15, P["e0"] - 10, h)
    for k, n in enumerate([P["n0"] + 15, P["n0"] + 60, P["n0"] + 105]):
        e0, e1 = (P["e0"] - 10, P["e1"] + 10) if k % 2 == 0 else (P["e1"] + 10, P["e0"] - 10); y = 90 if k % 2 == 0 else 270
        r += tramo(u, (n, e0, h), y=y, g=g)
        for j in range(10):
            e = e0 + (e1 - e0) * j / 9; p = (n, e, h); r += tramo((n, e0 if j == 0 else e0 + (e1 - e0) * (j - 1) / 9, h), p, y=y, g=g) + foto(p, y, g)
        u = (n, e1, h)
    return r, u
r, u = malla(); V.append(vuelo("fotogrametria ok", "op_fotogrametria", foto((C[0], C[1], 5), 0, -40) + r + aterrizaje(u, C)))
r, u = malla(30); V.append(vuelo("fotogrametria baja", "op_fotogrametria", r + aterrizaje(u, C)))
r, u = malla(50, -40); V.append(vuelo("fotogrametria camara inclinada", "op_fotogrametria", r + aterrizaje(u, C)))
# ---- busqueda ----
O = ESC["op_busqueda"]["operacion"]; C = (O["salida"]["n"], O["salida"]["e"]); PER = [3150.0, -12900.0]
def busqueda(h=40, centrado=True):
    q = (PER[0], PER[1], suelo(*PER) + 0.9); p = (PER[0] + 30, PER[1] + 10, h); pa = (p[0], p[1], suelo(p[0], p[1]) + h)
    y, g = apuntar(pa, q)
    r = despegue(C) + tramo((C[0], C[1], 5), (3300, -12900, h)) + tramo((3300, -12900, h), p)
    r += foto(p, y + 25, g)                                     # sale de lado: no vale
    r += foto(p, y if centrado else y + 20, g)
    return r, p
r, u = busqueda(); V.append(vuelo("busqueda ok", "op_busqueda", r + aterrizaje(u, C), persona=PER))
r, u = busqueda(centrado=False); V.append(vuelo("busqueda con mucho error", "op_busqueda", r + aterrizaje(u, C), persona=PER))
V.append(vuelo("busqueda sin encontrarlo", "op_busqueda", despegue(C) + tramo((C[0], C[1], 5), (3300, -13100, 40)) + quieto((3300, -13100, 40), 490, 0) + aterrizaje((3300, -13100, 40), C), persona=PER))
r, u = busqueda(h=4); V.append(vuelo("busqueda a 4 m", "op_busqueda", r + aterrizaje(u, C), persona=PER))
# ---- agricultura ----
O = ESC["op_agricultura"]["operacion"]; C = (O["salida"]["n"], O["salida"]["e"])
def agricultura(h=20, g=-90, baja=False):
    r = despegue(C); u = (C[0], C[1], 5)
    for (n, e, _) in O["manchas"]:
        p = (n, e, h); r += tramo(u, p) + foto(p, 0, g); u = p
    if baja: r += tramo(u, (16300, 3300, 3)); u = (16300, 3300, 3)
    return r, u
r, u = agricultura(); V.append(vuelo("agricultura ok", "op_agricultura", r + aterrizaje(u, C)))
r, u = agricultura(40, -90, True); V.append(vuelo("agricultura alta y rozando el cultivo", "op_agricultura", r + aterrizaje(u, C)))
r, u = agricultura(20, -45); V.append(vuelo("agricultura camara inclinada", "op_agricultura", r + aterrizaje(u, C)))
# ---- paneles fotovoltaicos ----
O = ESC["op_paneles"]["operacion"]; C = (O["salida"]["n"], O["salida"]["e"]); PL = O["planta"]
def modulo(f, x): s_ = math.sin(math.radians(PL["inclinacion"])); n = PL["n0"] + f * PL["separacion"]; e = PL["e0"] + x; return (n, e)
def paneles(h=12, g=-90, todos=True):
    r = despegue(C); u = (C[0], C[1], 5)
    for k, (f, x) in enumerate(O["defectos"]):
        if not todos and k % 2: continue
        n, e = modulo(f, x); p = (n, e, h); r += tramo(u, (n, e, max(h, 10))) + tramo((n, e, max(h, 10)), p, v=3) + foto(p, 0, g); u = p
    return r, u
r, u = paneles(); V.append(vuelo("paneles ok", "op_paneles", r + aterrizaje((u[0], u[1], 12), C)))
r, u = paneles(todos=False); V.append(vuelo("paneles la mitad", "op_paneles", r + aterrizaje((u[0], u[1], 12), C)))
r, u = paneles(g=-20); V.append(vuelo("paneles camara horizontal", "op_paneles", r + aterrizaje((u[0], u[1], 12), C)))
r, u = paneles(h=30); V.append(vuelo("paneles demasiado alto", "op_paneles", r + aterrizaje((u[0], u[1], 30), C)))
n, e = modulo(5, 70)
V.append(vuelo("paneles demasiado bajo", "op_paneles", despegue(C) + tramo((C[0], C[1], 5), (n, e, 12)) + tramo((n, e, 12), (n, e, 5), v=2) + aterrizaje((n, e, 12), C)))
V.append(vuelo("choca con los paneles", "op_paneles", despegue(C) + tramo((C[0], C[1], 5), (n, e, 12)) + tramo((n, e, 12), (n, e, 1.5), v=2), final="roto"))
# ---- video ----
O = ESC["op_video"]["operacion"]; C = (O["salida"]["n"], O["salida"]["e"]); F = O["faro"]
def orbita(r_=45, h=40, vueltas=1.0, salto=False, rec=1, cambio=0):
    fz = suelo(F["n"], F["e"]) + 0.6 * F["alto"]; res = []; n = int(2 * math.pi * r_ * vueltas / 5 / DT)
    for k in range(n + 1):
        a = -math.pi / 2 + 2 * math.pi * vueltas * k / n; p = (F["n"] + r_ * math.cos(a), F["e"] + r_ * math.sin(a))
        hh = h + (cambio if k > n // 2 else 0); pa = (p[0], p[1], suelo(*p) + hh); y, g = apuntar(pa, (F["n"], F["e"], fz))
        if salto and k == n // 3: y += 60
        res.append((p[0], p[1], hh, y, g, rec, 0, False))
    return res
def video(**kw):
    o = orbita(**kw); a = o[0]
    return despegue(C) + tramo((C[0], C[1], 5), (a[0], a[1], a[2]), y=a[3], g=a[4]) + o + foto((o[-1][0], o[-1][1], o[-1][2]), 0, 0) + aterrizaje(o[-1][:3], C)
V.append(vuelo("video ok", "op_video", video()))
V.append(vuelo("video sin grabar", "op_video", video(rec=0)))
V.append(vuelo("video con tiron", "op_video", video(salto=True)))
V.append(vuelo("video cambia de altura", "op_video", video(cambio=12)))
V.append(vuelo("video demasiado lejos", "op_video", video(r_=80)))
V.append(vuelo("choca con el faro", "op_video", despegue(C) + tramo((C[0], C[1], 5), (F["n"], F["e"], 20)), final="roto"))
# ---- normas ----
O = ESC["op_inspeccion"]["operacion"]; C = (O["salida"]["n"], O["salida"]["e"])
V.append(vuelo("normas: alto y lejos", "op_inspeccion", despegue(C) + tramo((C[0], C[1], 5), (C[0], C[1], 130), v=6) + tramo((C[0], C[1], 130), (C[0] + 600, C[1], 100)) + aterrizaje((C[0] + 600, C[1], 100), C)))

JS = r"""V => V.map(v => {
  const E = ESCENARIOS[v.mision], obj = {}, CURSO = ["techo", "vlos", "zona", "baja", "distancia", "suave"];
  for (const [id, t] of E.objetivos) obj[id] = { texto: t, estado: CURSO.includes(id) ? "curso" : "pend" };
  const marcar = (k, e) => { if (obj[k] && obj[k].estado !== "mal") obj[k].estado = e; };
  const anotar = (k, t) => { if (obj[k]) obj[k].texto += ` (${t})`; };
  const d = Object.assign({}, E.operacion); if (v.persona) d.persona = v.persona;
  const suelo = (N, E) => 3 * Math.sin(N * 0.01) + 2 * Math.cos(E * 0.013);
  const op = new Operacion(d, marcar, anotar, { casa: [E.operacion.salida.n, E.operacion.salida.e], suelo, h0: 0 });
  const avisos = [], ahora = []; let pAnt = null, av = null, choque = null;
  v.estados.forEach((s, i) => {
    av = { p: [s[0], s[1], -s[2]], q: Cuat.desdeEuler(0, 0, s[3] * D2R), estado: "volando", posado: !!s[4], t: s[8] };
    if (choque) return;
    if (pAnt) for (const t of op.paso(pAnt, av, 0.1, { gimbal: s[5], grabando: !!s[6] })) avisos.push(s[8].toFixed(1) + " " + t);
    if (op.choque) { choque = op.choque; return; }
    if (s[7]) for (const t of op.foto(av, s[5])) avisos.push(s[8].toFixed(1) + " foto: " + t);
    if (i % 50 === 0) ahora.push(op.ahora(obj, av));
    pAnt = av.p;
  });
  const fin = choque ? "roto" : v.final;
  op.final(fin, av, { bateria: v.bateria });
  if (fin === "aterrizado") marcar("aterrizar", "ok");
  for (const o of Object.values(obj)) if (o.estado === "curso") o.estado = fin === "aterrizado" ? "ok" : "mal";
  for (const o of Object.values(obj)) if (o.estado === "pend") o.estado = "mal";
  return { choque, objetivos: Object.fromEntries(Object.entries(obj).map(([k, o]) => [k, o.estado + " | " + o.texto])), avisos, ahora };
})"""
url = (RAIZ / "simulador" / "simulador.html").as_uri()
with sync_playwright() as p:
    b = p.chromium.launch(channel="chrome", args=["--use-angle=swiftshader", "--allow-file-access-from-files"]); pg = b.new_page()
    err = []; pg.on("pageerror", lambda e: err.append(str(e)))
    pg.goto(url); pg.wait_for_timeout(2500)
    r = pg.evaluate(JS, V)
    SEMILLAS = [1, 7, 42, 2026]
    S = pg.evaluate("""S => S.flatMap(s => Object.keys(ESCENARIOS).filter(k => ESCENARIOS[k].operacion).map(k => {
      let x = s; const rnd = () => (x = (x * 48271) % 2147483647) / 2147483647;          // Park-Miller: igual en GDScript
      const d = Operacion.sortear(ESCENARIOS[k].operacion, rnd);
      return { semilla: s, mision: k, puntos: d.puntos || null, defectos: d.defectos || null, manchas: d.manchas || null, persona: d.persona || null };
    }))""", SEMILLAS); b.close()
assert not err, err
# lo sorteado tiene que estar dentro de su zona y sin repetirse
for x in S:
    O = ESC[x["mision"]]["operacion"]
    if x["mision"] == "op_inspeccion": assert len(x["puntos"]) == 6 and len({(q["n"], q["e"]) for q in x["puntos"]}) == 6, x
    if x["defectos"]: assert len({tuple(f) for f in x["defectos"]}) == 8 and all(0 <= f < O["planta"]["filas"] and 3 <= e <= O["planta"]["largo"] - 4 for f, e in x["defectos"]), x
    if x["manchas"]:
        P = O["parcela"]; assert all(P["n0"] + r <= n <= P["n1"] - r and P["e0"] + r <= e <= P["e1"] - r for n, e, r in x["manchas"]), x
    if x["persona"]: Z = O["zona"]; assert Z["n0"] < x["persona"][0] < Z["n1"] and Z["e0"] < x["persona"][1] < Z["e1"], x
json.dump(S, open(RAIZ / "simulador_godot" / "pruebas" / "referencia_sorteos_js.json", "w", encoding="utf-8"), ensure_ascii=False, indent=1)
print(len(S), "sorteos; inspeccion con la semilla 1:", [q["nombre"] for q in S[0]["puntos"]] if S[0]["puntos"] else S[0])
for v, x in zip(V, r): v["web"] = x
json.dump(V, open(RAIZ / "simulador_godot" / "pruebas" / "referencia_operaciones_js.json", "w", encoding="utf-8"), ensure_ascii=False, separators=(",", ":"))
for x, v in zip(r, V):
    print("==", v["nombre"], "| choque:", x["choque"]); print("   ", " / ".join(f"{k}:{e.split(' | ')[0]}" + (f" ({e.split(' (')[-1]}" if " (" in e.split(" | ")[1][-20:] else "") for k, e in x["objetivos"].items()))
    print("   ", " / ".join(x["avisos"])[:600])
