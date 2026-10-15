"""Carrera de drones del CIFP Politecnico (op_carrera, escenarios.js): el recorrido de obstaculos por el campus y el barrio
de al lado, en la zona de detalle cifp_politecnico. Comprueba que ninguna puerta ni ningun tramo recto entre dos
seguidas toca un edificio del Catastro (con su altura) y dibuja el recorrido sobre la ortofoto
(analisis/mundo_cartagena/carrera_cifp.jpg); con --escribir lo pone en simulador/escenarios.js.

Obstaculos (n, e: centro en m del origen del mundo; rumbo: hacia donde se cruza, grados; h: altura del suelo al
borde de abajo, m):
  puerta   marco de carrera de 3 x 2,4 m
  arco     arco hinchable de 6 x 4 m
  banderas dos banderas de 5 m de alto a 5 m una de otra: se pasa entre ellas
  picado   marco horizontal de 4 x 4 m en lo alto de un andamio: se cruza hacia abajo y se sale por delante (rumbo):
           el andamio solo tiene cruces en los lados
Los arboles solidos de la zona (los que tiene la fisica del simulador) estan en carrera_cifp_arboles.json ([E, N, radio,
pie, copa], m sobre el suelo), sacados del simulador; la prueba de verdad es simulador_godot/pruebas/prueba_carrera_web.py.

    python analisis/mundo_cartagena/carrera_cifp.py [--escribir]
"""
import json, math, os, re, sys
from PIL import Image, ImageDraw, ImageFont

AQUI = os.path.dirname(os.path.abspath(__file__)); RAIZ = os.path.join(AQUI, "..", "..")
SIM = os.path.join(RAIZ, "simulador"); Z = os.path.join(SIM, "zonas", "cifp_politecnico")
MEDIDAS = {"puerta": (3.0, 2.4), "arco": (6.0, 4.0), "banderas": (5.0, 5.0), "picado": (4.0, 4.0)}   # ancho, alto (picado: lado)
SALIDA = dict(n=58.0, e=6653.0, rumbo=95.0)          # el aparcamiento interior del CIFP (destacado del vuelo libre)
# el recorrido, en orden
OBST = [
    dict(tipo="puerta", n=54, e=6722, rumbo=100, h=1.5),       # salida del aparcamiento hacia el descampado
    dict(tipo="arco", n=60, e=6860, rumbo=80, h=0),
    dict(tipo="banderas", n=150, e=6900, rumbo=20, h=0),
    dict(tipo="picado", n=300, e=6880, rumbo=312, h=12),       # al otro lado de la via, en el campo (se sale hacia el 5)
    dict(tipo="arco", n=419.5, e=6747.4, rumbo=300, h=0),
    dict(tipo="banderas", n=330, e=6640, rumbo=220, h=0),
    dict(tipo="puerta", n=239.4, e=6736, rumbo=150, h=2),        # otra vez la via, de vuelta
    dict(tipo="arco", n=130, e=6790, rumbo=160, h=0),
    dict(tipo="banderas", n=-9, e=6730.1, rumbo=210, h=0),
    dict(tipo="arco", n=-60, e=6646, rumbo=180, h=0),          # la avenida hacia el sur
    dict(tipo="puerta", n=-150, e=6646, rumbo=180, h=1.5),
    dict(tipo="puerta", n=-200, e=6650, rumbo=180, h=1.5),     # el cruce
    dict(tipo="banderas", n=-202.9, e=6722.7, rumbo=90, h=0),      # la calle hacia el este
    dict(tipo="puerta", n=-200, e=6788, rumbo=90, h=1.5),
    dict(tipo="puerta", n=-144, e=6793, rumbo=0, h=1.5),       # la calle estrecha, al norte
    dict(tipo="puerta", n=-144, e=6876, rumbo=90, h=1.5),      # hasta la avenida del puente
    dict(tipo="arco", n=-100, e=6884, rumbo=0, h=0),
    dict(tipo="puerta", n=-86.1, e=6780.5, rumbo=270, h=1.5),      # la calle del descampado, al oeste
    dict(tipo="arco", n=18.5, e=6704.3, rumbo=330, h=0),           # meta
]


def mundo():
    s = open(os.path.join(SIM, "mundos", "cartagena.js"), encoding="utf-8").read()
    return json.loads(s[s.index("Mundos.registrar(") + 17: s.rindex(");")])


def edificios():
    """[(planta [(E, N)...], altura sobre el suelo m)] de la zona."""
    L = []
    for b in json.load(open(os.path.join(Z, "edificios.json"), encoding="utf-8")):
        p = b["p"]; L.append(([(p[i], p[i + 1]) for i in range(0, len(p), 2)], b.get("pl", 1) * 3.0 + 0.5))
    return L


def arboles():
    f = os.path.join(AQUI, "carrera_cifp_arboles.json")
    return json.load(open(f)) if os.path.isfile(f) else []


def arbol_en(AR, x, y, h, margen=1.2):
    """el arbol que toca el punto (E, N) a h m sobre el suelo, o None"""
    return next((t for t in AR if abs(t[0] - x) < t[2] + margen and abs(t[1] - y) < t[2] + margen and math.hypot(t[0] - x, t[1] - y) < t[2] + margen and t[3] - 0.5 < h < t[4] + 0.5), None)


def dist_seg(px, py, ax, ay, bx, by):
    dx, dy = bx - ax, by - ay; L2 = dx * dx + dy * dy
    t = max(0, min(1, ((px - ax) * dx + (py - ay) * dy) / L2)) if L2 else 0
    return math.hypot(ax + t * dx - px, ay + t * dy - py)


def dentro(P, x, y):
    d = False
    for i in range(len(P)):
        (xi, yi), (xj, yj) = P[i], P[i - 1]
        if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi) + xi: d = not d
    return d


def dist_poli(P, x, y):
    return 0.0 if dentro(P, x, y) else min(dist_seg(x, y, *P[i - 1], *P[i]) for i in range(len(P)))


def puntos_obst(o):
    """Puntos (E, N) del obstaculo para la comprobacion: los dos lados (o el contorno del picado)."""
    a, al = MEDIDAS[o["tipo"]]; r = math.radians(o["rumbo"])
    if o["tipo"] == "picado":
        return [(o["e"] + u * math.cos(r) + v * math.sin(r), o["n"] - u * math.sin(r) + v * math.cos(r)) for u in (-a / 2, 0, a / 2) for v in (-a / 2, 0, a / 2)]
    return [(o["e"] + s * a / 2 * math.cos(r), o["n"] - s * a / 2 * math.sin(r)) for s in (-1, -0.5, 0, 0.5, 1)]


H_CRUCERO, PENDIENTE, PASILLO = 18.0, 1.2, 4.0   # la linea de carrera: por encima de los arboles entre obstaculo y obstaculo, bajando
                                                # a cada uno; los ultimos y primeros PASILLO m, a la altura del obstaculo


def altura_paso(o, llegada):
    """altura (m sobre el suelo) a la que se cruza el obstaculo o (el picado: de 5 m por encima a 3 m por debajo de su marco)"""
    if o.get("tipo") is None: return 1.5
    if o["tipo"] == "picado": return o["h"] + 5 if llegada else o["h"] - 3
    return o["h"] + MEDIDAS[o["tipo"]][1] / 2


def perfil(ha, hb, L, s):
    """altura de la linea de carrera a s m del obstaculo de salida (en un tramo de L m): sube con la pendiente hasta el
    crucero y baja con la misma hasta el siguiente (como VUELO de prueba_carrera_web.py y prueba_carrera.gd)"""
    return min(max(H_CRUCERO, ha, hb), ha + PENDIENTE * max(0, s - PASILLO), hb + PENDIENTE * max(0, L - s - PASILLO))


def corredor(o, largo=5):
    """los puntos (E, N) del pasillo por el que se cruza el obstaculo: de "largo" m antes a "largo" m despues, por su centro"""
    r = math.radians(o["rumbo"])
    if o["tipo"] == "picado": return [(o["e"] + s * math.sin(r), o["n"] + s * math.cos(r)) for s in range(0, largo + 1)]
    return [(o["e"] + s * math.sin(r), o["n"] + s * math.cos(r)) for s in range(-largo, largo + 1)]


def comprobar(ED, AR=()):
    fallos = []
    for k, o in enumerate(OBST):
        hc = o["h"] + MEDIDAS[o["tipo"]][1] / 2 if o["tipo"] != "picado" else o["h"] - 3
        for x, y in puntos_obst(o) + corredor(o):
            t = arbol_en(AR, x, y, hc)
            if t: fallos.append("obstaculo %d (%s): arbol en E%.0f N%.0f (r %.1f, %.0f m)" % (k + 1, o["tipo"], t[0], t[1], t[2], t[4])); break
    for k, o in enumerate(OBST):
        for x, y in puntos_obst(o):
            for P, h in ED:
                if h > o["h"] and dist_poli(P, x, y) < 3: fallos.append("obstaculo %d (%s) a menos de 3 m de un edificio de %.0f m" % (k + 1, o["tipo"], h)); break
            else: continue
            break
    ruta = [dict(n=SALIDA["n"], e=SALIDA["e"], h=0)] + OBST
    for k in range(1, len(ruta)):
        a, b = ruta[k - 1], ruta[k]; L = math.hypot(b["n"] - a["n"], b["e"] - a["e"])
        ha, hb = altura_paso(a, False), altura_paso(b, True)
        for s in range(0, int(L) + 1, 2):
            f = s / L if L else 0; x, y, hh = a["e"] + f * (b["e"] - a["e"]), a["n"] + f * (b["n"] - a["n"]), perfil(ha, hb, L, s)
            choca = next((h for P, h in ED if h > hh - 1.5 and dist_poli(P, x, y) < 2.5), None)
            if choca: fallos.append("tramo %d -> %d: edificio de %.0f m a %.0f m del obstaculo %d (vuela a %.0f m)" % (k - 1, k, choca, L - s, k, hh)); break
            t = arbol_en(AR, x, y, hh)
            if t: fallos.append("tramo %d -> %d: arbol (E%.0f N%.0f, r %.1f, %.0f m) a %.0f m del obstaculo %d (vuela a %.1f m)" % (k - 1, k, t[0], t[1], t[2], t[4], L - s, k, hh)); break
    return fallos


def dibujar(ED, M, fallos, AR=()):
    m = json.load(open(os.path.join(Z, "zona.json"), encoding="utf-8")); O = m["orto"]; N0, E0, lado = m["N0"], m["E0"], m["lado_m"]
    nt, tm, px = O["teselas"], O["tesela_m"], O["tesela_px"]
    ns = [o["n"] for o in OBST] + [SALIDA["n"]]; es = [o["e"] for o in OBST] + [SALIDA["e"]]
    n0, n1, e0, e1 = min(ns) - 80, max(ns) + 80, min(es) - 80, max(es) + 80
    k = px / tm; big = Image.new("RGB", (nt * px, nt * px))
    for i in range(nt):
        for j in range(nt): big.paste(Image.open(os.path.join(Z, O["archivo"].format(i=i, j=j))).convert("RGB"), (j * px, (nt - 1 - i) * px))
    W = 1600; esc = W / (e1 - e0); H = int((n1 - n0) * esc)
    img = big.crop((int((e0 - E0) * k), int((N0 + lado - n1) * k), int((e1 - E0) * k), int((N0 + lado - n0) * k))).resize((W, H))
    X = lambda e: (e - e0) * esc; Y = lambda n: (n1 - n) * esc
    d = ImageDraw.Draw(img, "RGBA"); F = ImageFont.truetype("arialbd.ttf", 20); f2 = ImageFont.truetype("arial.ttf", 14)
    for P, h in ED:
        q = [(X(x), Y(y)) for x, y in P]
        if any(0 <= a <= W and 0 <= b <= H for a, b in q): d.polygon(q, outline=(255, 80, 80, 160))
    for t in AR: d.ellipse([X(t[0] - t[2]), Y(t[1] + t[2]), X(t[0] + t[2]), Y(t[1] - t[2])], outline=(80, 255, 120, 170), width=2)
    ruta = [(SALIDA["e"], SALIDA["n"])] + [(o["e"], o["n"]) for o in OBST]
    d.line([(X(e), Y(n)) for e, n in ruta], fill=(255, 200, 61, 220), width=3)
    for v in range(int(n0 // 50 * 50), int(n1) + 1, 50): d.text((3, Y(v) - 16), "N%d" % v, fill="white", font=f2, stroke_width=2, stroke_fill="black")
    for v in range(int(e0 // 50 * 50), int(e1) + 1, 100): d.text((X(v) + 2, 2), "E%d" % v, fill="white", font=f2, stroke_width=2, stroke_fill="black")
    d.ellipse([X(SALIDA["e"]) - 12, Y(SALIDA["n"]) - 12, X(SALIDA["e"]) + 12, Y(SALIDA["n"]) + 12], fill=(255, 109, 0)); d.text((X(SALIDA["e"]), Y(SALIDA["n"])), "H", fill="white", font=F, anchor="mm")
    for k2, o in enumerate(OBST):
        pts = puntos_obst(o); col = {"puerta": (79, 195, 247), "arco": (255, 64, 129), "banderas": (255, 235, 59), "picado": (124, 77, 255)}[o["tipo"]]
        if o["tipo"] == "picado": d.rectangle([min(X(x) for x, _ in pts), min(Y(y) for _, y in pts), max(X(x) for x, _ in pts), max(Y(y) for _, y in pts)], outline=col, width=4)
        else: d.line([(X(pts[0][0]), Y(pts[0][1])), (X(pts[-1][0]), Y(pts[-1][1]))], fill=col, width=6)
        d.text((X(o["e"]) + 12, Y(o["n"]) - 12), str(k2 + 1), fill="white", font=F, stroke_width=3, stroke_fill="black")
    L = sum(math.hypot(ruta[i][0] - ruta[i - 1][0], ruta[i][1] - ruta[i - 1][1]) for i in range(1, len(ruta)))
    d.text((10, H - 30), "%d obstaculos, %.0f m en linea recta; %s" % (len(OBST), L, "sin choques con edificios" if not fallos else "%d fallos" % len(fallos)),
           fill="white", font=F, stroke_width=3, stroke_fill="black")
    img.save(os.path.join(AQUI, "carrera_cifp.jpg"), quality=85)
    return L


LIMITE_S = 240                                     # para el APTO: la carrera en menos de 4 min (se puede con el Mini Dron)


def escribir():
    n = len(OBST)
    O = {
        "nombre": "Carrera de drones del Politécnico",
        "vehiculos": ["fpv", "dron"],
        "mundo": "cartagena",
        "zona": 3,
        "dificultad": 3,
        "viento": {"vel": 3, "desde": 90, "rachas": False},
        "desc": "Carrera de drones por el CIFP Politécnico y el barrio de al lado: %d obstáculos (puertas, arcos hinchables, banderas y un picado desde un andamio) que hay que pasar en orden. El cronómetro empieza al cruzar el primero y para en la meta; si te saltas uno, quedas descalificado. Vale cualquier dron del hangar." % n,
        "objetivos": [
            ["secuencia", "Pasar los %d obstáculos en orden, sin saltarse ninguno" % n],
            ["meta", "Cruzar la meta (el obstáculo %d)" % n],
            ["tiempo", "Terminar la carrera en menos de %d minutos" % (LIMITE_S // 60)],
            ["choques", "Sin chocar con los obstáculos, los edificios ni los árboles"]],
        "operacion": {
            "avion": "FPV",
            "elegir": ["fpv", "dron"],
            "cliente": "Club de drones del CIFP Politécnico · liga escolar de carreras",
            "lugar": "CIFP Politécnico de Cartagena (calle Grecia, 56), el descampado, el campo de al lado de la vía y las calles del barrio. Salida desde el aparcamiento interior.",
            "trabajo": "Despega y pasa los %d obstáculos en su orden: los marcos y los arcos por dentro y de frente, entre las dos banderas y el picado del andamio de arriba abajo. Una marca en la pantalla señala el siguiente (con una flecha en el borde si no está a la vista) y se ilumina de verde. El cronómetro empieza en el primero y para en la meta. Si cruzas uno que no toca, quedas descalificado." % n,
            "entrega": "El tiempo de la carrera: el mejor de la sala sale arriba de la pantalla y el mejor de cada piloto se guarda en su perfil.",
            "salida": dict(SALIDA),
            "carrera": {"obstaculos": OBST, "limite_s": LIMITE_S},
        },
    }
    p = os.path.join(SIM, "escenarios.js"); t = open(p, encoding="utf-8").read()
    bloque = ' "op_carrera": ' + json.dumps(O, indent=1, ensure_ascii=False).replace("\n", "\n ") + ",\n"
    if '\n "op_carrera": {' in t:
        i = t.index('\n "op_carrera": {') + 1; j = t.index('\n "', i + 5) + 1; t = t[:i] + bloque + t[j:]
    else:
        i = t.index('\n "libre_cartagena": {') + 1; t = t[:i] + bloque + t[i:]
    m = re.search(r"(?m)^window[.]ESCENARIOS = ", t); json.loads(t[m.end():t.rindex("}") + 1])
    open(p, "w", encoding="utf-8", newline="\n").write(t)
    print("escrito op_carrera en", p)


if __name__ == "__main__":
    ED = edificios(); M = mundo(); AR = arboles(); fallos = comprobar(ED, AR); L = dibujar(ED, M, fallos, AR)
    for f in fallos: print("  MAL", f)
    print("%d obstaculos, %.0f m; %s" % (len(OBST), L, "todo libre" if not fallos else "%d fallos" % len(fallos)))
    if "--escribir" in sys.argv:
        if fallos: raise SystemExit("no se escribe: hay choques con edificios")
        escribir()
