"""Imagenes de briefing de los trabajos del modo Operaciones (simulador/operaciones/<id>.jpg): la ortofoto de la zona de
detalle con la zona de trabajo (discontinua amarilla) y el punto de despegue (H) marcados, el norte, la escala y la
atribucion del PNOA. Sin las soluciones: ni los puntos que fotografiar, ni las manchas, ni el senderista, ni los modulos
danados. Las leen las dos versiones del simulador (la orden de trabajo de la pantalla de Operaciones).

    python analisis/mundo_cartagena/briefing_operaciones.py [id ...]     (necesita las zonas de detalle en simulador/zonas)

Un trabajo mas grande que las zonas de detalle (la patrulla del Mar Menor) sale sobre la ortofoto de toda la region
(simulador/mundos/cartagena_orto.jpg, 12 m/px).
"""
import json, math, os, re, sys
from PIL import Image, ImageDraw, ImageFont

RAIZ = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
SIM = os.path.join(RAIZ, "simulador")
t = open(os.path.join(SIM, "escenarios.js"), encoding="utf-8").read(); m = re.search(r"(?m)^window[.]ESCENARIOS = ", t)
ESC = json.loads(t[m.end():t.rindex("}") + 1])
ZONAS = json.load(open(os.path.join(SIM, "zonas", "indice.json"), encoding="utf-8"))
W, H = 1200, 800
try: F = lambda n: ImageFont.truetype("arialbd.ttf", n)
except OSError: F = lambda n: ImageFont.load_default()
AMARILLO = (255, 200, 61)

def zona_de(n, e):
    for z in ZONAS:
        if z["N0"] <= n <= z["N0"] + z["lado_m"] and z["E0"] <= e <= z["E0"] + z["lado_m"]: return z
    raise SystemExit("sin zona de detalle en N %.0f E %.0f" % (n, e))

def zona_que_cubre(n0, n1, e0, e1):
    for z in ZONAS:
        if z["N0"] <= n0 and n1 <= z["N0"] + z["lado_m"] and z["E0"] <= e0 and e1 <= z["E0"] + z["lado_m"]: return z
    return None

def recorte_region(n0, n1, e0, e1):
    """Lo mismo sobre la ortofoto de la region (fila 0 = borde norte de la malla del mundo)."""
    s = open(os.path.join(SIM, "mundos", "cartagena.js"), encoding="utf-8").read(); T = json.loads(s[s.index("Mundos.registrar(") + 17: s.rindex(");")])["terreno"]
    Image.MAX_IMAGE_PIXELS = None; big = Image.open(os.path.join(SIM, "mundos", "cartagena_orto.jpg")).convert("RGB")
    k = big.size[0] / ((T["nE"] - 1) * T["paso"]); Nn = T["N0"] + (T["nN"] - 1) * T["paso"]
    return big.crop((int((e0 - T["E0"]) * k), int((Nn - n1) * k), int((e1 - T["E0"]) * k), int((Nn - n0) * k))), k

def recorte(n0, n1, e0, e1):
    """Ortofoto de la zona entre n0..n1, e0..e1 (m), con la misma escala en los dos ejes; devuelve (imagen, m->px)."""
    z = zona_que_cubre(n0, n1, e0, e1)
    if z is None and (n1 - n0) > 3000: return recorte_region(n0, n1, e0, e1)
    z = z or zona_de((n0 + n1) / 2, (e0 + e1) / 2); meta = json.load(open(os.path.join(SIM, "zonas", z["id"], "zona.json"), encoding="utf-8"))
    O = meta["orto"]; nt, tm = O["teselas"], O["tesela_m"]; px = Image.open(os.path.join(SIM, "zonas", z["id"], O["archivo"].format(i=0, j=0))).size[0]
    k = px / tm; big = Image.new("RGB", (nt * px, nt * px))
    for i in range(nt):
        for j in range(nt):
            big.paste(Image.open(os.path.join(SIM, "zonas", z["id"], O["archivo"].format(i=i, j=j))).convert("RGB"), (j * px, (nt - 1 - i) * px))
    N0, E0, L = meta["N0"], meta["E0"], nt * tm
    caja = (int((e0 - E0) * k), int((N0 + L - n1) * k), int((e1 - E0) * k), int((N0 + L - n0) * k))
    return big.crop(caja), k

def briefing(id_):
    E = ESC[id_]; O = E["operacion"]; S = O["salida"]; pts = [(S["n"], S["e"])]
    # zona de trabajo: poligono [N, E] (o un circulo para el video)
    if "puntos" in O:
        ns = [q["n"] for q in O["puntos"]]; es = [q["e"] for q in O["puntos"]]
        zona = [(min(ns) - 25, min(es) - 25), (min(ns) - 25, max(es) + 25), (max(ns) + 25, max(es) + 25), (max(ns) + 25, min(es) - 25)]
    elif "parcela" in O and "poligono" in O["parcela"]:
        zona = [tuple(q) for q in O["parcela"]["poligono"]]          # el bancal con su forma
    elif "parcela" in O or "zona" in O:
        P = O.get("parcela") or O["zona"]; zona = [(P["n0"], P["e0"]), (P["n0"], P["e1"]), (P["n1"], P["e1"]), (P["n1"], P["e0"])]
    elif "planta" in O:                                  # el bloque de filas, con su rumbo (90 = filas hacia el este)
        P = O["planta"]; fondo = P["ancho"] * math.cos(math.radians(P["inclinacion"])); r = math.radians(P.get("rumbo", 90))
        ne = lambda l, t: (P["n0"] + l * math.cos(r) + t * math.sin(r), P["e0"] + l * math.sin(r) - t * math.cos(r))
        t1 = (P["filas"] - 1) * P["separacion"] + fondo
        zona = [ne(0, -fondo), ne(P["largo"], -fondo), ne(P["largo"], t1), ne(0, t1)]
    elif "unidades" in O:                                # SABIC: las unidades de proceso, los racks y la antorcha
        q = [tuple(p) for U in O["unidades"] for p in U["poligono"]] + [(R[a], R[b]) for R in O["racks"] for a, b in (("n0", "e0"), ("n1", "e1"))]
        q.append((O["antorcha"]["n"], O["antorcha"]["e"]))
        n0, n1 = min(p[0] for p in q) - 20, max(p[0] for p in q) + 20; e0, e1 = min(p[1] for p in q) - 20, max(p[1] for p in q) + 20
        zona = [(n0, e0), (n0, e1), (n1, e1), (n1, e0)]
    elif "candidatos_vertido" in O:                      # patrulla: donde puede haber manchas, con el radio del sector
        R = O["radio_sector"]; q = sorted(set((round(n), round(e)) for n, e in O["candidatos_vertido"]))
        q = [(n + R * math.cos(a * math.pi / 8), e + R * math.sin(a * math.pi / 8)) for n, e in q for a in range(16)]
        def giro(o, a, b): return (a[1] - o[1]) * (b[0] - o[0]) - (a[0] - o[0]) * (b[1] - o[1])
        q.sort(key=lambda p: (p[1], p[0])); abajo, arriba = [], []      # envolvente convexa (cadena monotona, en E, N)
        for p in q:
            while len(abajo) >= 2 and giro(abajo[-2], abajo[-1], p) <= 0: abajo.pop()
            abajo.append(p)
        for p in reversed(q):
            while len(arriba) >= 2 and giro(arriba[-2], arriba[-1], p) <= 0: arriba.pop()
            arriba.append(p)
        zona = abajo[:-1] + arriba[:-1]
    else: zona = None
    if "faro" in O:
        Fr = O["faro"]; r0, r1 = O["orbita"]; pts += [(Fr["n"] - r1, Fr["e"] - r1), (Fr["n"] + r1, Fr["e"] + r1)]
    pts += zona or []
    ns = [p[0] for p in pts]; es = [p[1] for p in pts]
    cn, ce = (min(ns) + max(ns)) / 2, (min(es) + max(es)) / 2
    lado_e = max(max(es) - min(es), (max(ns) - min(ns)) * W / H) * 1.3 + 40; lado_n = lado_e * H / W
    if "candidatos_vertido" in O:                                 # sobre la ortofoto de la region: sin salirse de su borde norte
        s_ = open(os.path.join(SIM, "mundos", "cartagena.js"), encoding="utf-8").read(); T = json.loads(s_[s_.index("Mundos.registrar(") + 17: s_.rindex(");")])["terreno"]
        cn = min(cn, T["N0"] + (T["nN"] - 1) * T["paso"] - lado_n / 2 - 10)
    img, k0 = recorte(cn - lado_n / 2, cn + lado_n / 2, ce - lado_e / 2, ce + lado_e / 2)
    img = img.resize((W, H), Image.LANCZOS); k = W / lado_e
    X = lambda e: (e - (ce - lado_e / 2)) * k; Y = lambda n: ((cn + lado_n / 2) - n) * k
    d = ImageDraw.Draw(img, "RGBA")
    if "planta" in O and "rumbo" not in O["planta"]:              # paneles: las filas de la planta, si no estan en la ortofoto (en SABIC si)
        P = O["planta"]; fondo = P["ancho"] * math.cos(math.radians(P["inclinacion"]))
        for i in range(P["filas"]):                               # mismas mesas que Operacion._planta (sin los modulos danados)
            n = P["n0"] + i * P["separacion"]; x0, x1 = X(P["e0"]), X(P["e0"] + P["largo"])
            d.rectangle([x0, Y(n + fondo / 2 + 1.6), x1, Y(n + fondo / 2)], fill=(0, 0, 0, 90))          # sombra al norte
            d.rectangle([x0, Y(n + fondo / 2), x1, Y(n - fondo / 2)], fill=(24, 44, 82), outline=(176, 182, 187))
            for m in range(1, P["largo"]):
                if (X(P["e0"] + m) - x0) * 1 >= 0 and k >= 2.5: d.line([X(P["e0"] + m), Y(n + fondo / 2), X(P["e0"] + m), Y(n - fondo / 2)], fill=(70, 95, 140))
    if zona:                                                      # zona de trabajo: velo y borde discontinuo
        poli = [(X(e), Y(n)) for n, e in zona]
        d.polygon(poli, fill=(255, 200, 61, 40))
        for a, b in zip(poli, poli[1:] + poli[:1]):
            L = math.dist(a, b); nseg = max(1, int(L / 14))
            for s in range(0, nseg, 2):
                p0 = (a[0] + (b[0] - a[0]) * s / nseg, a[1] + (b[1] - a[1]) * s / nseg); p1 = (a[0] + (b[0] - a[0]) * (s + 1) / nseg, a[1] + (b[1] - a[1]) * (s + 1) / nseg)
                d.line([p0, p1], fill=AMARILLO, width=4)
    if "faro" in O:                                               # video: el anillo de la orbita
        Fr = O["faro"]
        for r, a in ((O["orbita"][1], 45), (O["orbita"][0], 0)):
            c = (X(Fr["e"]), Y(Fr["n"])); d.ellipse([c[0] - r * k, c[1] - r * k, c[0] + r * k, c[1] + r * k], outline=AMARILLO, width=4)
        d.text((X(Fr["e"]) + O["orbita"][1] * k + 8, Y(Fr["n"]) - 10), "órbita %d–%d m" % tuple(O["orbita"]), fill=AMARILLO, font=F(20))
    if "pista" in O:                                              # UAV: la pista de despegue y aterrizaje
        P = O["pista"]; r = math.radians(P["rumbo"]); ne = lambda l, t: (P["n"] + l * math.cos(r) - t * math.sin(r), P["e"] + l * math.sin(r) + t * math.cos(r))
        esq = [ne(0, -P["ancho"] / 2), ne(P["largo"], -P["ancho"] / 2), ne(P["largo"], P["ancho"] / 2), ne(0, P["ancho"] / 2)]
        d.polygon([(X(e), Y(n)) for n, e in esq], fill=(40, 40, 40), outline=(255, 255, 255))
        c = ne(P["largo"], 0); d.text((X(c[1]) + 14, Y(c[0]) - 12), P["nombre"], fill=(255, 255, 255), font=F(18), stroke_width=3, stroke_fill=(0, 0, 0))
    if "antorcha" in O:                                           # SABIC: la antorcha (la placa y el piloto)
        A = (X(O["antorcha"]["e"]), Y(O["antorcha"]["n"]))
        d.ellipse([A[0] - 13, A[1] - 13, A[0] + 13, A[1] + 13], fill=(255, 179, 0), outline=(0, 0, 0), width=2)
        d.text(A, "A", fill=(0, 0, 0), font=F(18), anchor="mm")
        d.text((A[0] + 18, A[1] - 10), "Antorcha", fill=(255, 255, 255), font=F(18), stroke_width=3, stroke_fill=(0, 0, 0))
    h = (X(S["e"]), Y(S["n"]))                                    # punto de despegue
    d.ellipse([h[0] - 16, h[1] - 16, h[0] + 16, h[1] + 16], fill=(255, 109, 0), outline=(0, 0, 0), width=2)
    d.text((h[0], h[1]), "H", fill=(255, 255, 255), font=F(20), anchor="mm")
    d.text((h[0] + 22, h[1] - 10), "Despegue", fill=(255, 255, 255), font=F(18), stroke_width=3, stroke_fill=(0, 0, 0))
    if zona and "candidatos_vertido" in O:
        cy = max(poli, key=lambda p: p[1]); d.text((cy[0], cy[1] + 10), "Zona de patrulla", fill=AMARILLO, font=F(20), anchor="mt", stroke_width=3, stroke_fill=(0, 0, 0))
    elif zona: d.text((poli[3][0] + 8, poli[3][1] + 6), "Zona de trabajo", fill=AMARILLO, font=F(20), stroke_width=3, stroke_fill=(0, 0, 0))
    # titulo, norte, escala y atribucion
    d.rectangle([0, 0, W, 56], fill=(11, 15, 20, 200)); d.text((18, 28), E["nombre"], fill=(255, 255, 255), font=F(28), anchor="lm")
    d.text((W - 18, 28), "Orden de trabajo · briefing", fill=(159, 179, 200), font=F(18), anchor="rm")
    nx, ny = W - 50, 110; d.polygon([(nx, ny - 30), (nx - 13, ny + 8), (nx, ny), (nx + 13, ny + 8)], fill=(255, 255, 255), outline=(0, 0, 0))
    d.text((nx, ny + 24), "N", fill=(255, 255, 255), font=F(22), anchor="mm", stroke_width=3, stroke_fill=(0, 0, 0))
    esc = next(v for v in (5000, 2000, 1000, 500, 200, 100, 50, 20, 10) if v * k < W / 4)
    d.rectangle([18, H - 64, 18 + esc * k, H - 56], fill=(255, 255, 255), outline=(0, 0, 0))
    d.text((18, H - 76), "%d km" % (esc // 1000) if esc >= 1000 else "%d m" % esc, fill=(255, 255, 255), font=F(18), stroke_width=3, stroke_fill=(0, 0, 0))
    d.text((W - 12, H - 12), "Ortofoto: PNOA © Instituto Geográfico Nacional (CC BY 4.0)", fill=(255, 255, 255), font=F(14), anchor="rs", stroke_width=2, stroke_fill=(0, 0, 0))
    os.makedirs(os.path.join(SIM, "operaciones"), exist_ok=True)
    salida = os.path.join(SIM, "operaciones", id_ + ".jpg"); img.save(salida, quality=84)
    print(id_, "->", salida, "(%d KB)" % (os.path.getsize(salida) // 1024))

for id_ in sys.argv[1:] or [k for k, v in ESC.items() if "operacion" in v]: briefing(id_)
