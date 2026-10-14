"""Imagenes de briefing de los trabajos del modo Operaciones (simulador/operaciones/<id>.jpg): la ortofoto de la zona de
detalle con la zona de trabajo (discontinua amarilla) y el punto de despegue (H) marcados, el norte, la escala y la
atribucion del PNOA. Sin las soluciones: ni los puntos que fotografiar, ni las manchas, ni el senderista, ni los modulos
danados. Las leen las dos versiones del simulador (la orden de trabajo de la pantalla de Operaciones).

    python analisis/mundo_cartagena/briefing_operaciones.py      (necesita las zonas de detalle en simulador/zonas)
"""
import json, math, os, re
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

def recorte(n0, n1, e0, e1):
    """Ortofoto de la zona entre n0..n1, e0..e1 (m), con la misma escala en los dos ejes; devuelve (imagen, m->px)."""
    z = zona_de((n0 + n1) / 2, (e0 + e1) / 2); meta = json.load(open(os.path.join(SIM, "zonas", z["id"], "zona.json"), encoding="utf-8"))
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
    elif "parcela" in O or "zona" in O:
        P = O.get("parcela") or O["zona"]; zona = [(P["n0"], P["e0"]), (P["n0"], P["e1"]), (P["n1"], P["e1"]), (P["n1"], P["e0"])]
    elif "planta" in O:
        P = O["planta"]; fondo = P["ancho"] * math.cos(math.radians(P["inclinacion"]))
        n0, n1 = P["n0"] - fondo, P["n0"] + (P["filas"] - 1) * P["separacion"] + fondo
        zona = [(n0, P["e0"]), (n0, P["e0"] + P["largo"]), (n1, P["e0"] + P["largo"]), (n1, P["e0"])]
    else: zona = None
    if "faro" in O:
        Fr = O["faro"]; r0, r1 = O["orbita"]; pts += [(Fr["n"] - r1, Fr["e"] - r1), (Fr["n"] + r1, Fr["e"] + r1)]
    pts += zona or []
    ns = [p[0] for p in pts]; es = [p[1] for p in pts]
    cn, ce = (min(ns) + max(ns)) / 2, (min(es) + max(es)) / 2
    lado_e = max(max(es) - min(es), (max(ns) - min(ns)) * W / H) * 1.3 + 40; lado_n = lado_e * H / W
    img, k0 = recorte(cn - lado_n / 2, cn + lado_n / 2, ce - lado_e / 2, ce + lado_e / 2)
    img = img.resize((W, H), Image.LANCZOS); k = W / lado_e
    X = lambda e: (e - (ce - lado_e / 2)) * k; Y = lambda n: ((cn + lado_n / 2) - n) * k
    d = ImageDraw.Draw(img, "RGBA")
    if "planta" in O:                                             # paneles: las filas de la planta, que no estan en la ortofoto
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
    h = (X(S["e"]), Y(S["n"]))                                    # punto de despegue
    d.ellipse([h[0] - 16, h[1] - 16, h[0] + 16, h[1] + 16], fill=(255, 109, 0), outline=(0, 0, 0), width=2)
    d.text((h[0], h[1]), "H", fill=(255, 255, 255), font=F(20), anchor="mm")
    d.text((h[0] + 22, h[1] - 10), "Despegue", fill=(255, 255, 255), font=F(18), stroke_width=3, stroke_fill=(0, 0, 0))
    if zona: d.text((poli[3][0] + 8, poli[3][1] + 6), "Zona de trabajo", fill=AMARILLO, font=F(20), stroke_width=3, stroke_fill=(0, 0, 0))
    # titulo, norte, escala y atribucion
    d.rectangle([0, 0, W, 56], fill=(11, 15, 20, 200)); d.text((18, 28), E["nombre"], fill=(255, 255, 255), font=F(28), anchor="lm")
    d.text((W - 18, 28), "Orden de trabajo · briefing", fill=(159, 179, 200), font=F(18), anchor="rm")
    nx, ny = W - 50, 110; d.polygon([(nx, ny - 30), (nx - 13, ny + 8), (nx, ny), (nx + 13, ny + 8)], fill=(255, 255, 255), outline=(0, 0, 0))
    d.text((nx, ny + 24), "N", fill=(255, 255, 255), font=F(22), anchor="mm", stroke_width=3, stroke_fill=(0, 0, 0))
    esc = next(v for v in (500, 200, 100, 50, 20, 10) if v * k < W / 4)
    d.rectangle([18, H - 64, 18 + esc * k, H - 56], fill=(255, 255, 255), outline=(0, 0, 0))
    d.text((18, H - 76), "%d m" % esc, fill=(255, 255, 255), font=F(18), stroke_width=3, stroke_fill=(0, 0, 0))
    d.text((W - 12, H - 12), "Ortofoto: PNOA © Instituto Geográfico Nacional (CC BY 4.0)", fill=(255, 255, 255), font=F(14), anchor="rs", stroke_width=2, stroke_fill=(0, 0, 0))
    os.makedirs(os.path.join(SIM, "operaciones"), exist_ok=True)
    salida = os.path.join(SIM, "operaciones", id_ + ".jpg"); img.save(salida, quality=84)
    print(id_, "->", salida, "(%d KB)" % (os.path.getsize(salida) // 1024))

for id_ in [k for k, v in ESC.items() if "operacion" in v]: briefing(id_)
