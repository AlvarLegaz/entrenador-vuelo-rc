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

def vuelo(nombre, mision, piezas, final="aterrizado", bateria=60, persona=None, calientes=None, vertidos=None, automatico=False):
    """piezas: lista de (N, E, altura sobre el suelo, rumbo, gimbal, grabando, foto, posado[, termica, zoom[, pan]]). Estados:
    [N, E, arriba, rumbo, posado, gimbal, grabando, foto, t, termica, zoom, pan]. calientes: los modulos con el diodo averiado
    (paneles); vertidos: (vertidos, sectores) de la patrulla; pan: el giro de la torreta del UAV (rad); automatico: el UAV
    aterriza con el piloto automatico."""
    est = []
    for k, pz in enumerate(piezas):
        N, E, h, y, g, rec, foto, pos = pz[:8]; ter, zoom = pz[8:10] if len(pz) > 8 else (0, 1); pan = pz[10] if len(pz) > 10 else 0
        est.append([round(N, 3), round(E, 3), round(suelo(N, E) + h, 3), round(y, 3), int(pos), round(g, 3), int(rec), int(foto), round(k * DT, 2), int(ter), zoom, round(pan, 4)])
    return {"nombre": nombre, "mision": mision, "estados": est, "final": final, "bateria": bateria, "persona": persona, "calientes": calientes,
            "vertidos": vertidos[0] if vertidos else None, "sectores": vertidos[1] if vertidos else None, "automatico": automatico}

def tramo(a, b, v=8.0, y=None, g=-10, rec=0):
    """de a a b (N, E, h) a v m/s; y None = mirando hacia donde va."""
    d = math.dist(a, b); n = max(1, int(d / v / DT)); r = []
    yy = y if y is not None else (math.degrees(math.atan2(b[1] - a[1], b[0] - a[0])) if math.hypot(b[0] - a[0], b[1] - a[1]) > 1e-6 else 0)
    for i in range(n): f = i / n; r.append((a[0] + f * (b[0] - a[0]), a[1] + f * (b[1] - a[1]), a[2] + f * (b[2] - a[2]), yy, g, rec, 0, False))
    return r
def quieto(p, s, y, g=-10, rec=0): return [(p[0], p[1], p[2], y, g, rec, 0, False)] * int(s / DT)
def foto(p, y, g, ter=0, zoom=1): return [(p[0], p[1], p[2], y, g, 0, 1, False, ter, zoom), (p[0], p[1], p[2], y, g, 0, 0, False, ter, zoom)]
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
def modulo(f, x):                                      # Operacion.ne: filas con su rumbo (90 = hacia el este)
    r = math.radians(PL.get("rumbo", 90)); t = f * PL["separacion"]
    return (PL["n0"] + x * math.cos(r) + t * math.sin(r), PL["e0"] + x * math.sin(r) - t * math.cos(r))
DIODOS = [[2, 40], [9, 150], [15, 260]]                 # los modulos con el diodo de bypass averiado (sin sortear)
def paneles(h=12, g=-90, todos=True, camaras="bien", zoom=1):
    """camaras "bien": cristal roto con la normal, excrementos con la termica y diodos con la termica; "mal": al reves
    (cristal roto con la termica, diodos con la normal); "normal": todo con la normal."""
    r = despegue(C); u = (C[0], C[1], 5)
    for k, (f, x) in enumerate(O["defectos"] + DIODOS):
        diodo = k >= len(O["defectos"])
        if not todos and k % 2: continue
        ter = {"bien": diodo or k % 2 == 1, "mal": not diodo and k % 2 == 0, "normal": False}[camaras]
        n, e = modulo(f, x); p = (n, e, h); r += tramo(u, (n, e, max(h, 10))) + tramo((n, e, max(h, 10)), p, v=3) + foto(p, 0, g, int(ter), zoom); u = p
    return r, u
r, u = paneles(); V.append(vuelo("paneles ok", "op_paneles", r + aterrizaje((u[0], u[1], 12), C), calientes=DIODOS))
r, u = paneles(todos=False); V.append(vuelo("paneles la mitad", "op_paneles", r + aterrizaje((u[0], u[1], 12), C), calientes=DIODOS))
r, u = paneles(camaras="mal"); V.append(vuelo("paneles con la camara equivocada", "op_paneles", r + aterrizaje((u[0], u[1], 12), C), calientes=DIODOS))
r, u = paneles(camaras="normal"); V.append(vuelo("paneles todo con la camara normal", "op_paneles", r + aterrizaje((u[0], u[1], 12), C), calientes=DIODOS))
r, u = paneles(g=-20); V.append(vuelo("paneles camara horizontal", "op_paneles", r + aterrizaje((u[0], u[1], 12), C), calientes=DIODOS))
r, u = paneles(h=30); V.append(vuelo("paneles demasiado alto", "op_paneles", r + aterrizaje((u[0], u[1], 30), C), calientes=DIODOS))
r, u = paneles(h=45, zoom=4); V.append(vuelo("paneles a 45 m con zoom 4x", "op_paneles", r + aterrizaje((u[0], u[1], 45), C), calientes=DIODOS))
n, e = modulo(5, 70)
V.append(vuelo("paneles demasiado bajo", "op_paneles", despegue(C) + tramo((C[0], C[1], 5), (n, e, 12)) + tramo((n, e, 12), (n, e, 3.5), v=2) + aterrizaje((n, e, 12), C)))
V.append(vuelo("choca con los paneles", "op_paneles", despegue(C) + tramo((C[0], C[1], 5), (n, e, 12)) + tramo((n, e, 12), (n, e, 0.8), v=2), final="roto"))
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
# ---- patrulla del Mar Menor (UAV): la torreta girada (pan), vertidos fijos, pista, altura minima y aterrizaje a mano ----
O = ESC["op_patrulla"]["operacion"]; P = O["pista"]; RP = math.radians(P["rumbo"])
def en_pista(l, t=0.0): return (P["n"] + l * math.cos(RP) - t * math.sin(RP), P["e"] + l * math.sin(RP) + t * math.cos(RP))
CV = O["candidatos_vertido"]; VERT = [[CV[i][0], CV[i][1], 150, 60, 30 + 50 * k, 7 + k] for k, i in enumerate((0, 25, 50))]
SECT = [[v[0] + 300, v[1] - 200] for v in VERT]
def junto(v, dist, h, pan, zoom, ter, desvio=0.0):
    """el avion a "dist" m del vertido v (al suroeste) y "h" m sobre el, la torreta girada "pan" grados mirando al vertido
    (+ desvio m al norte): quieto 1 s y una foto."""
    a = 1.0; p = (v[0] - dist * math.cos(a), v[1] - dist * math.sin(a), h); y, g = apuntar(p, (v[0] + desvio, v[1], 0))
    q = (p[0], p[1], p[2] - suelo(p[0], p[1]) + suelo(v[0], v[1]))         # misma altura sobre el agua (el suelo de prueba no es plano)
    return [(q[0], q[1], q[2], y - pan, g, 0, 0, False, ter, zoom, math.radians(pan))] * 10 + [(q[0], q[1], q[2], y - pan, g, 0, 1, False, ter, zoom, math.radians(pan)), (q[0], q[1], q[2], y - pan, g, 0, 0, False, ter, zoom, math.radians(pan))]
def pista_despegue(t=0.0):
    a = en_pista(60, t); b = en_pista(1500, t)
    return [(a[0], a[1], 0, P["rumbo"], -10, 0, 0, True)] * 3 + tramo((a[0], a[1], 0.1), (b[0], b[1], 60), v=30)
def pista_toma(l=600, t=0.0):
    a = en_pista(-3000, t); b = en_pista(l - 300, t); c = en_pista(l, t)
    return tramo((a[0], a[1], 200), (b[0], b[1], 0.5), v=30) + tramo((b[0], b[1], 0.5), (c[0], c[1], 0.1), v=10) + [(c[0], c[1], 0, P["rumbo"], -10, 0, 0, True)] * 5
pz = (pista_despegue() + junto(VERT[0], 700, 300, 90, 4, 0) + junto(VERT[1], 1600, 300, 0, 1, 0) + junto(VERT[1], 700, 300, -60, 4, 1)
      + junto(VERT[2], 700, 300, 0, 4, 0, desvio=130) + junto(VERT[2], 700, 300, 30, 8, 1) + pista_toma())
V.append(vuelo("patrulla ok, a mano", "op_patrulla", pz, vertidos=(VERT, SECT)))
pz = pista_despegue(t=120) + junto(VERT[0], 700, 100, 0, 4, 0) + junto(VERT[1], 600, 300, 180, 4, 1) + pista_toma(t=90)
V.append(vuelo("patrulla baja, fuera de pista y con el automatico", "op_patrulla", pz, vertidos=(VERT, SECT), automatico=True))
# ---- carrera de drones del Politecnico: completa, saltandose uno, chocando con un poste y cruzando uno al reves ----
O = ESC["op_carrera"]["operacion"]; OB = O["carrera"]["obstaculos"]; MED = {"puerta": (3, 2.4), "arco": (6, 4), "banderas": (5, 5), "picado": (4, 4)}
SAL = (O["salida"]["n"], O["salida"]["e"])
def por_obst(o, antes=6, despues=6, lateral=0.0, al_reves=False):
    """puntos (N, E, h) para cruzar el obstaculo o por el centro (lateral: desplazado a su derecha, m)."""
    if o["tipo"] == "picado": return [(o["n"], o["e"], o["h"] + 5), (o["n"], o["e"], o["h"] - 3)]
    r = math.radians(o["rumbo"] + (180 if al_reves else 0)); h = o["h"] + MED[o["tipo"]][1] / 2; ln, le = -math.sin(r) * lateral, math.cos(r) * lateral
    return [(o["n"] - antes * math.cos(r) + ln, o["e"] - antes * math.sin(r) + le, h), (o["n"] + despues * math.cos(r) + ln, o["e"] + despues * math.sin(r) + le, h)]
def carrera(lista, choque_en=None):
    """la carrera por los obstaculos de "lista" (indices; ("reves", i) lo cruza al reves), y con choque_en = i se va contra un poste de ese."""
    pz = [(SAL[0], SAL[1], 0, O["salida"]["rumbo"], -10, 0, 0, True)] * 3; ant = (SAL[0], SAL[1], 0.1)
    for x in lista:
        rev = isinstance(x, tuple); o = OB[x[1] if rev else x]
        P = por_obst(o, lateral=(MED[o["tipo"]][0] / 2 if x == choque_en else 0), al_reves=rev)
        for q in P: pz += tramo(ant, q, v=20); ant = q
    return pz + [(ant[0], ant[1], ant[2], 0, -10, 0, 0, False)] * 25          # unos segundos despues de la meta
V.append(vuelo("carrera completa", "op_carrera", carrera(range(len(OB))), final="carrera terminada"))
V.append(vuelo("carrera saltandose el 5", "op_carrera", carrera([0, 1, 2, 3, 5, 6]), final="descalificado"))
V.append(vuelo("carrera contra un poste del 3", "op_carrera", carrera([0, 1, 2], choque_en=2), final="roto"))
V.append(vuelo("carrera con el 2 al reves", "op_carrera", carrera([0, ("reves", 1), 1, 2, 3]), final="aterrizado"))

JS = r"""V => V.map(v => {
  const E = ESCENARIOS[v.mision], obj = {}, CURSO = ["techo", "vlos", "zona", "baja", "distancia", "suave", "altura"];
  for (const [id, t] of E.objetivos) obj[id] = { texto: t, estado: CURSO.includes(id) ? "curso" : "pend" };
  const marcar = (k, e) => { if (obj[k] && obj[k].estado !== "mal") obj[k].estado = e; };
  const anotar = (k, t) => { if (obj[k]) obj[k].texto += ` (${t})`; };
  const d = Object.assign({}, E.operacion); if (v.persona) d.persona = v.persona; if (v.calientes) d.calientes = v.calientes; if (v.vertidos) { d.vertidos = v.vertidos; d.sectores = v.sectores; }
  const suelo = (N, E) => 3 * Math.sin(N * 0.01) + 2 * Math.cos(E * 0.013);
  const op = new Operacion(d, marcar, anotar, { casa: [E.operacion.salida.n, E.operacion.salida.e], suelo, h0: 0 });
  const avisos = [], ahora = []; let pAnt = null, av = null, choque = null;
  v.estados.forEach((s, i) => {
    av = { p: [s[0], s[1], -s[2]], q: Cuat.desdeEuler(0, 0, s[3] * D2R), estado: "volando", posado: !!s[4], t: s[8] };
    if (choque) return;
    const cam = { termica: !!s[9], zoom: s[10], pan: s[11] || 0 };
    if (pAnt) for (const t of op.paso(pAnt, av, 0.1, Object.assign({ gimbal: s[5], grabando: !!s[6] }, cam))) avisos.push(s[8].toFixed(1) + " " + t);
    if (op.choque) { choque = op.choque; return; }
    if (s[7]) for (const t of op.foto(av, s[5], cam)) avisos.push(s[8].toFixed(1) + " foto: " + t);
    if (i % 50 === 0) ahora.push(op.ahora(obj, av));
    pAnt = av.p;
  });
  const fin = choque ? "roto" : v.final;
  op.final(fin, av, { bateria: v.bateria, automatico: !!v.automatico });
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
      return { semilla: s, mision: k, puntos: d.puntos || null, defectos: d.defectos || null, manchas: d.manchas || null, persona: d.persona || null,
               calientes: Array.isArray(d.calientes) ? d.calientes : null, puntosCalientes: d.puntosCalientes || null, fuga: d.fuga || null,
               placaTxt: d.placaTxt || null, piloto: d.piloto === undefined ? null : d.piloto,
               vertidos: Array.isArray(d.vertidos) ? d.vertidos : null, sectores: d.sectores || null };
    }))""", SEMILLAS); b.close()
assert not err, err
# lo sorteado tiene que estar dentro de su zona y sin repetirse
for x in S:
    O = ESC[x["mision"]]["operacion"]
    if x["mision"] == "op_inspeccion": assert len(x["puntos"]) == 6 and len({(q["n"], q["e"]) for q in x["puntos"]}) == 6, x
    if x["defectos"]: assert len({tuple(f) for f in x["defectos"] + x["calientes"]}) == len(O["defectos"]) + O["calientes"] and all(0 <= f < O["planta"]["filas"] and 3 <= e <= O["planta"]["largo"] - 4 for f, e in x["defectos"]), x
    if x["manchas"]:
        P = O["parcela"]; assert all(P["n0"] + r <= n <= P["n1"] - r and P["e0"] + r <= e <= P["e1"] - r for n, e, r in x["manchas"]), x
    if x["persona"]: Z = O["zona"]; assert Z["n0"] < x["persona"][0] < Z["n1"] and Z["e0"] < x["persona"][1] < Z["e1"], x
    if x["vertidos"]:                                      # patrulla: en sitios posibles, separados y cada uno dentro de su sector
        Vs = x["vertidos"]; assert len(Vs) == O["vertidos"] and all([v[0], v[1]] in O["candidatos_vertido"] for v in Vs), x
        assert all(math.dist(a[:2], b[:2]) >= O["separacion"] for i, a in enumerate(Vs) for b in Vs[i + 1:]), x
        assert all(math.dist(v[:2], s) <= O["radio_sector"] for v, s in zip(Vs, x["sectores"])), x
json.dump(S, open(RAIZ / "simulador_godot" / "pruebas" / "referencia_sorteos_js.json", "w", encoding="utf-8"), ensure_ascii=False, indent=1)
print(len(S), "sorteos; inspeccion con la semilla 1:", [q["nombre"] for q in S[0]["puntos"]] if S[0]["puntos"] else S[0])
for v, x in zip(V, r): v["web"] = x
json.dump(V, open(RAIZ / "simulador_godot" / "pruebas" / "referencia_operaciones_js.json", "w", encoding="utf-8"), ensure_ascii=False, separators=(",", ":"))
for x, v in zip(r, V):
    print("==", v["nombre"], "| choque:", x["choque"]); print("   ", " / ".join(f"{k}:{e.split(' | ')[0]}" + (f" ({e.split(' (')[-1]}" if " (" in e.split(" | ")[1][-20:] else "") for k, e in x["objetivos"].items()))
    print("   ", " / ".join(x["avisos"])[:600])
