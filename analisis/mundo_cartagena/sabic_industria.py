"""Instalaciones de la fabrica de SABIC de La Aljorra para simulador/singulares.js (pedido del usuario 2026-10-14: "la
factoria de sabic tiene muy poco detalle"). El Catastro solo trae naves y oficinas; lo que da el aspecto de planta
quimica (tanques, racks de tuberias, estructuras de proceso, columnas, torres de refrigeracion, chimeneas) sale de aqui:

  - tanques, balas, esferas, torres de refrigeracion y racks: medidos a mano en la ortofoto PNOA de la zona
    "fotovoltaica" (0,25 m), en un marco girado con las calles de la fabrica: u a lo largo de 46 grados (noreste),
    v a lo largo de 136 (sureste), origen en (E, N) = (2000, 2000) desde la esquina suroeste de la zona;
  - estructuras de proceso y columnas: dentro de los recintos de las unidades (rectangulos medidos en u, v), donde la
    ortofoto tiene mas detalle (densidad de bordes: aparatos, tuberias y sombras), sin pisar tanques ni racks.

Fotos de referencia: no hay fotos publicas utiles del interior; las formas siguen la ortofoto y lo tipico de una planta
de policarbonato (LX1/LX2, ULTEM, compounding) con sus servicios (vapor y electricidad de Energyworks, gases de Air
Liquide).

    python analisis/mundo_cartagena/sabic_industria.py      (necesita la zona simulador/zonas/fotovoltaica)
"""
import json, math, os, re
import numpy as np
from PIL import Image
from scipy import ndimage

AQUI = os.path.dirname(os.path.abspath(__file__))
RAIZ = os.path.join(AQUI, "..", "..")
ZDIR = os.path.join(RAIZ, "simulador", "zonas", "fotovoltaica")
NOMBRE = "Fábrica de SABIC (La Aljorra)"
R = 46.0                                                      # rumbo de las calles de la fabrica (eje u)
SU, CU = math.sin(math.radians(R)), math.cos(math.radians(R))

# tanques: (u, v, radio, techo, color)  color: 2 blanco, 3 crema, 4 oxido, 11 hormigon (decantadores)
TANQUES = [
    (595, 222, 12, "cupula", 2),
    (528, 138, 6, "cupula", 4), (528, 159, 7, "abierto", 11), (528, 175, 7, "abierto", 11), (529, 197, 7, "cupula", 4), (512, 137, 3, "plano", 2),
    (265, 135, 5.3, "cupula", 3), (244, 135, 6, "cupula", 3), (231, 137, 5, "cupula", 4), (219, 137, 5, "cupula", 3), (204, 138, 4, "cupula", 3),
    (259, 155, 5, "cupula", 4), (244, 155, 6, "cupula", 3), (232, 152, 5, "cupula", 3), (221, 152, 4, "cupula", 4), (256, 124, 3, "plano", 2),
    (193, 158, 9, "cupula", 2), (168, 135, 8, "cupula", 3), (168, 157, 8, "cupula", 3),
    (343, 170, 5, "plano", 2), (334, 170, 5, "plano", 2), (325, 170, 5, "plano", 2),
    (260, -156, 3.3, "cupula", 2), (260, -146, 3.3, "cupula", 2), (260, -129, 6, "cupula", 2), (227, -267, 6, "cupula", 2), (227, -249, 6, "cupula", 2),
    (239, -248, 3.5, "plano", 2), (232, -228, 2.5, "plano", 2), (302, -170, 3, "plano", 2), (190, -43, 5, "cupula", 4), (190, -30, 5, "cupula", 4),
    (68, -258, 5, "cupula", 2),
    (-170, 219, 9, "cupula", 2), (-85, 122, 3, "plano", 2), (-163, 143, 3, "plano", 2), (-90, 157, 3, "plano", 2), (-110, 168, 3, "plano", 2), (-110, 182, 3, "plano", 2),
    (-301, 67, 7, "cupula", 2), (-301, 87, 8, "cupula", 2),
    (-356, 13, 9, "cupula", 3), (-380, 13, 10, "cupula", 3), (-355, 38, 7, "cupula", 4), (-406, 35, 5, "cupula", 3), (-417, 20, 5, "cupula", 4),
    (-417, 37, 5, "cupula", 3), (-432, 18, 8, "cupula", 3), (-432, 37, 6, "cupula", 4), (-445, 13, 5, "cupula", 3), (-442, 42, 4, "cupula", 3),
    (-513, 10, 5, "cupula", 2), (-522, 10, 5, "cupula", 2),
]
ESFERAS = [(230, -161, 2.2), (230, -155.5, 2.2), (230, -150, 2.2)]                       # (u, v, radio)
BALAS = [(-83.5, v, 2.0, 33) for v in (150, 162.3, 174, 180.3, 186.7)]               # (u, v, radio, largo) a lo largo de u
REFRIGERACION = [(295, -147.5, 50, 21, 9, 4), (-360, 241.5, 54, 23, 9, 4)]          # (u, v, largo en u, ancho, alto, celdas)
CHIMENEAS = [(40, -292, 1.8, 62), (35, -203, 1.6, 55), (-540, 182, 1.5, 46), (-360, 160, 1.3, 38)]   # (u, v, radio, alto)
# racks: (u0, v0, u1, v1, alto, ancho, niveles)
RACKS = [
    (395, 56, 0, 50, 9, 7, 3), (0, 50, -275, 42, 9, 7, 3), (-275, 42, -275, 120, 8, 6, 3), (-275, 120, -607, 120, 9, 7, 3),
    (-275, 120, -275, 253, 7, 4, 2), (-392, 0, -392, 116, 6, 4, 2), (-358, 127, -358, 228, 6, 4, 2), (-532, 27, -532, 116, 7, 5, 2),
    (-532, 124, -532, 250, 7, 5, 2), (-450, 22, -560, 22, 6, 4, 2), (-137, 0, -137, 38, 6, 4, 2), (-218, 47, -218, 137, 6, 4, 2),
    (-9, 54, -9, 127, 6, 4, 2), (206, 60, 206, 217, 7, 5, 2), (395, 60, 395, 187, 7, 5, 2), (350, 154, 423, 154, 6, 4, 2),
    (350, 20, 453, 20, 6, 4, 2),
    (343, -261, 173, -261, 7, 5, 2), (215, -257, 215, -117, 7, 5, 2), (343, -113, 190, -113, 7, 5, 2), (259, -109, 259, -13, 6, 4, 2),
    (343, -173, 219, -173, 6, 4, 2), (342, -169, 342, -117, 6, 4, 2),
    (91, -300, 91, -107, 8, 6, 3), (150, -280, -50, -280, 7, 5, 2), (87, -215, -50, -215, 7, 5, 2), (-30, -276, -30, -219, 6, 4, 2),
    (150, -103, 53, -103, 7, 5, 2), (20, -99, 20, 0, 6, 4, 2), (20, 0, 20, 46, 6, 4, 2),
]
# recintos de las unidades de proceso: (u0, u1, v0, v1)
UNIDADES = [
    (307, 350, 0, 47), (230, 300, 60, 100), (223, 290, 0, 47), (300, 350, 60, 140), (350, 390, 0, 50), (350, 377, 160, 200),
    (250, 343, -290, -215), (230, 283, -37, 0),
    (-13, 73, -300, -284), (-17, 73, -233, -177), (57, 110, -60, 0), (117, 150, -300, -250),
    (63, 100, 58, 107), (100, 150, 0, 45),
    (-133, -50, 50, 97), (-177, -147, 50, 73),
    (-390, -327, 130, 200), (-450, -410, 127, 187), (-303, -250, 150, 187), (-323, -290, 85, 115),
    (-573, -503, 127, 233), (-550, -503, 30, 100), (-560, -503, 207, 253), (-520, -455, 100, 160),
]


def h(v, i):
    """El mismo pseudoazar que Visor.azarInd / Industria.azar (web y Godot)."""
    x = math.sin((v * 1000 + i) * 12.9898) * 43758.5453
    return x - math.floor(x)


def main():
    Z = json.load(open(os.path.join(ZDIR, "zona.json"))); N0, E0, lado = Z["N0"], Z["E0"], Z["lado_m"]
    EN = lambda u, v: (E0 + 2000 + u * SU + v * CU, N0 + 2000 + u * CU - v * SU)
    # ortofoto a 0,5 m (fila 0 = norte) y densidad de bordes en ventanas de 10 m
    mpx = 0.5; nt = int(round(lado / 500)); T = int(500 / mpx)
    g = np.zeros((nt * T, nt * T), np.float32)
    for i in range(nt):
        for j in range(nt):
            g[(nt - 1 - i) * T:(nt - i) * T, j * T:(j + 1) * T] = np.asarray(Image.open(os.path.join(ZDIR, "orto_%d_%d.jpg" % (i, j))).convert("L").resize((T, T), Image.BILINEAR), np.float32)
    gx = ndimage.sobel(g, 1); gy = ndimage.sobel(g, 0)
    bordes = ndimage.uniform_filter((np.hypot(gx, gy) > 120).astype(np.float32), int(10 / mpx))
    def densidad(u, v):
        E, N = EN(u, v); x = int((E - E0) / mpx); y = int((lado - (N - N0)) / mpx)
        return float(bordes[min(max(y, 0), bordes.shape[0] - 1), min(max(x, 0), bordes.shape[1] - 1)])
    def a_rack(u, v):
        m = 1e9
        for u0, v0, u1, v1, al, an, nv in RACKS:
            du, dv = u1 - u0, v1 - v0; L2 = du * du + dv * dv; t = max(0, min(1, ((u - u0) * du + (v - v0) * dv) / L2))
            m = min(m, math.hypot(u0 + t * du - u, v0 + t * dv - v) - an / 2)
        return m

    piezas = []
    r1 = lambda x: round(x, 1)
    def pon(d, u, v):
        E, N = EN(u, v); d2 = {"tipo": d.pop("tipo"), "e": r1(E), "n": r1(N)}; d2.update(d); piezas.append(d2)
    for u, v, r, techo, col in TANQUES:
        alto = r1(min(16, max(5, 1.1 * r + 3))) if techo != "abierto" else 4.5
        pon({"tipo": "tanque", "radio": r, "alto": alto, "techo": techo, "color": col}, u, v)
    for u, v, r in ESFERAS: pon({"tipo": "esfera", "radio": r}, u, v)
    for u, v, r, L in BALAS: pon({"tipo": "bala", "radio": r, "largo": L, "rumbo": R}, u, v)
    for u, v, L, A, al, c in REFRIGERACION: pon({"tipo": "refrigeracion", "largo": L, "ancho": A, "alto": al, "rumbo": R, "celdas": c}, u, v)
    for u, v, r, al in CHIMENEAS: pon({"tipo": "chimenea", "radio": r, "alto": al}, u, v)
    for u0, v0, u1, v1, al, an, nv in RACKS:
        E0r, N0r = EN(u0, v0); E1r, N1r = EN(u1, v1)
        piezas.append({"tipo": "rack", "e0": r1(E0r), "n0": r1(N0r), "e1": r1(E1r), "n1": r1(N1r), "alto": al, "ancho": an, "niveles": nv})

    # estructuras de proceso y columnas en los recintos de las unidades
    ocup = [(u - r - 1, u + r + 1, v - r - 1, v + r + 1) for u, v, r, *_ in TANQUES] + [(u - 3, u + 3, v - 3, v + 3) for u, v, *_ in CHIMENEAS]
    ocup += [(u - L / 2 - 1, u + L / 2 + 1, v - A / 2 - 1, v + A / 2 + 1) for u, v, L, A, *_ in REFRIGERACION]
    libre = lambda a: all(a[1] < b[0] or a[0] > b[1] or a[3] < b[2] or a[2] > b[3] for b in ocup)
    semilla = 0; n_est = n_col = 0
    for k, (U0, U1, V0, V1) in enumerate(UNIDADES):
        cand = sorted(((densidad(u, v), u, v) for u in np.arange(U0 + 3, U1 - 2, 3.0) for v in np.arange(V0 + 3, V1 - 2, 3.0)), reverse=True)
        for d, u, v in cand:
            if d < 0.13: break
            semilla += 1; s = semilla
            L = [6, 8, 10, 12, 14][int(h(s, 1) * 5)]; A = [6, 7, 8, 10][int(h(s, 2) * 4)]
            a = (u - L / 2, u + L / 2, v - A / 2, v + A / 2)
            if a[0] < U0 or a[1] > U1 or a[2] < V0 or a[3] > V1: continue
            if not libre((a[0] - 1.5, a[1] + 1.5, a[2] - 1.5, a[3] + 1.5)) or a_rack(u, v) < max(L, A) / 2 + 0.5: continue
            alto = r1(7 + min(1.0, d / 0.45) * 16 * (0.55 + 0.45 * h(s, 3))); pisos = max(1, int(round(alto / 5.5)))
            pon({"tipo": "estructura", "largo": L, "ancho": A, "alto": alto, "pisos": pisos, "rumbo": R, "semilla": s}, u, v)
            ocup.append(a); n_est += 1
        cols = 1 + int((U1 - U0) * (V1 - V0) // 2500); hechas = 0
        for d, u, v in cand:
            if hechas >= cols or d < 0.12: break
            semilla += 1; s = semilla; r = r1(0.9 + 1.2 * h(s, 4))
            a = (u - r - 1, u + r + 1, v - r - 1, v + r + 1)
            if not libre(a) or a_rack(u, v) < r + 1: continue
            pon({"tipo": "columna", "radio": r, "alto": r1(16 + 26 * h(s, 5))}, u, v); ocup.append(a); hechas += 1; n_col += 1
    print("piezas %d: %d estructuras, %d columnas, %d tanques, %d racks" % (len(piezas), n_est, n_col, len(TANQUES), len(RACKS)))

    # a singulares.js: sustituye la entrada de SABIC si ya estaba
    p = os.path.join(RAIZ, "simulador", "singulares.js"); s = open(p, encoding="utf-8").read()
    nueva = entrada({"mundo": "cartagena", "nombre": NOMBRE,
                     "nota": "Generado por analisis/mundo_cartagena/sabic_industria.py desde la ortofoto PNOA a 0,25 m: tanques, racks, torres de refrigeración y balas medidos a mano; estructuras de proceso y columnas donde la foto muestra las unidades.",
                     "piezas": piezas})
    marca = ' {\n  "mundo": "cartagena",\n  "nombre": ' + json.dumps(NOMBRE, ensure_ascii=False)
    if marca in s: s = s[:s.index(marca)].rstrip().rstrip(",") + "\n" + s[s.rindex("]"):]     # la entrada de SABIC es la ultima
    j = s.rindex("]"); s = s[:j].rstrip() + ",\n" + nueva + "\n" + s[j:]
    json.loads(s[s.index("window.SINGULARES = ") + 20:s.rindex("]") + 1])                     # sigue siendo JSON estricto
    open(p, "w", encoding="utf-8", newline="\n").write(s)


def entrada(q):
    """Una entrada con una pieza por linea (como las que ya habia)."""
    cab = ' {\n  "mundo": %s,\n  "nombre": %s,\n  "nota": %s,\n  "piezas": [\n' % tuple(json.dumps(q[k], ensure_ascii=False) for k in ("mundo", "nombre", "nota"))
    return cab + ",\n".join("   " + json.dumps(pz, ensure_ascii=False, separators=(", ", ": ")) for pz in q["piezas"]) + "\n  ]\n }"


if __name__ == "__main__":
    main()
