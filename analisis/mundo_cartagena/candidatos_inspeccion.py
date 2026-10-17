"""Sitios posibles de las placas del trabajo de inspeccion del CIFP (op_inspeccion de datos/escenarios.js,
"candidatos"): en cada vuelo el simulador elige al azar unas cubiertas y unas fachadas de esta lista (Operacion.sortear),
para que las placas no esten siempre en el mismo sitio.
Salen de los edificios del Catastro de la zona de detalle cifp_politecnico (los del recinto del CIFP, de mas de 150 m2):
 - cubiertas: puntos del tejado a mas de 3 m de cualquier borde, repartidos (de 1 a 4 por edificio segun su tamano), a la
   cota del tejado (base + 3 m por planta + 0,55, como los tejados que dibujan los simuladores);
 - fachadas: el centro de cada pared de mas de 10 m que da a un sitio libre (a 2 m por fuera no hay otro edificio y el
   suelo no tapa la pared, ni hay un arbol a menos de 5 m delante: es solido y estorbaria la foto), con su
   orientacion (normal, grados desde el norte) y a media altura.
Escribe la lista en escenarios.js (sustituye "candidatos" si ya esta).
    python analisis/mundo_cartagena/candidatos_inspeccion.py      (necesita la zona datos/escenarios/zonas/cifp_politecnico)
"""
import json, math, os, re
import numpy as np

RAIZ = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
Z = os.path.join(RAIZ, "datos", "escenarios", "zonas", "cifp_politecnico")
CAJA = (40, 260, 6580, 6780)          # N0, N1, E0, E1 del recinto del CIFP (plano del mundo, m)

zona = json.load(open(os.path.join(Z, "zona.json"), encoding="utf-8"))
ED = json.load(open(os.path.join(Z, "edificios.json"), encoding="utf-8"))
ARB = np.fromfile(os.path.join(Z, "arboles.bin"), dtype="<f4").reshape(-1, 3)        # E, N, radio de copa
dem = np.fromfile(os.path.join(Z, "dem.bin"), dtype="<i2").reshape(zona["dem"]["n"], zona["dem"]["n"]) / 10.0

def suelo(n, e):
    """cota del terreno (m sobre el mar), bilineal en el MDT de la zona (fila 0 = sur)."""
    p = zona["dem"]["paso_m"]; y = (n - zona["N0"]) / p; x = (e - zona["E0"]) / p
    i, j = int(y), int(x); fy, fx = y - i, x - j; D = dem
    return (D[i, j] * (1 - fx) + D[i, j + 1] * fx) * (1 - fy) + (D[i + 1, j] * (1 - fx) + D[i + 1, j + 1] * fx) * fy

def poli(ed): p = ed["p"]; return [(p[k + 1], p[k]) for k in range(0, len(p), 2)]          # [(N, E)]
def area(P): return 0.5 * sum(P[k][1] * P[(k + 1) % len(P)][0] - P[(k + 1) % len(P)][1] * P[k][0] for k in range(len(P)))   # > 0: antihorario en (E, N)
def dentro(P, n, e):
    c = False
    for k in range(len(P)):
        (n1, e1), (n2, e2) = P[k], P[(k + 1) % len(P)]
        if (n1 > n) != (n2 > n) and e < e1 + (n - n1) / (n2 - n1) * (e2 - e1): c = not c
    return c
def dist_borde(P, n, e):
    d = 1e9
    for k in range(len(P)):
        (n1, e1), (n2, e2) = P[k], P[(k + 1) % len(P)]; L2 = (n2 - n1) ** 2 + (e2 - e1) ** 2
        t = 0 if L2 == 0 else max(0, min(1, ((n - n1) * (n2 - n1) + (e - e1) * (e2 - e1)) / L2))
        d = min(d, math.hypot(n - n1 - t * (n2 - n1), e - e1 - t * (e2 - e1)))
    return d

todos = [poli(ed) for ed in ED]
recinto = []
for i, ed in enumerate(ED):
    P = todos[i]; cn = sum(q[0] for q in P) / len(P); ce = sum(q[1] for q in P) / len(P)
    if CAJA[0] < cn < CAJA[1] and CAJA[2] < ce < CAJA[3] and abs(area(P)) >= 150: recinto.append(i)
cerca = [k for k, P in enumerate(todos) if any(abs(q[0] - 150) < 250 and abs(q[1] - 6680) < 250 for q in P)]

# los arboles del recinto que dibujan los simuladores (los que caen dentro de un edificio no se dibujan)
arb = [(e, n, r) for e, n, r in ARB.tolist() if CAJA[0] - 40 < n < CAJA[1] + 40 and CAJA[2] - 40 < e < CAJA[3] + 40]
arb = [(e, n, r) for e, n, r in arb if not any(dentro(todos[j], n, e) for j in cerca)]
cubiertas, fachadas = [], []
for i in recinto:
    ed, P = ED[i], todos[i]; A = abs(area(P)); techo = ed["b"] + ed["pl"] * 3.0 + 0.55
    ns = [q[0] for q in P]; es = [q[1] for q in P]
    rej = [(n, e) for n in np.arange(min(ns), max(ns), 3.0) for e in np.arange(min(es), max(es), 3.0) if dentro(P, n, e) and dist_borde(P, n, e) >= 3]
    k = max(1, min(4, int(A / 250)))
    elegidos = []
    if rej:                                                      # repartidos: el mas alejado de los ya elegidos
        c = (sum(n for n, _ in rej) / len(rej), sum(e for _, e in rej) / len(rej))
        elegidos.append(min(rej, key=lambda q: math.dist(q, c)))
        while len(elegidos) < k:
            q = max(rej, key=lambda q: min(math.dist(q, x) for x in elegidos))
            if min(math.dist(q, x) for x in elegidos) < 8: break
            elegidos.append(q)
    for n, e in elegidos: cubiertas.append({"n": round(float(n), 1), "e": round(float(e), 1), "cota": round(techo, 2)})
    s = 1 if area(P) > 0 else -1                                 # antihorario en (E, N): la normal de fuera es (dE, -dN) girada
    for k2 in range(len(P)):
        (n1, e1), (n2, e2) = P[k2], P[(k2 + 1) % len(P)]; L = math.hypot(n2 - n1, e2 - e1)
        if L < 10: continue
        un, ue = (e2 - e1) / L * -s, (n2 - n1) / L * s        # normal hacia fuera (N, E)
        un, ue = -un, -ue
        mn, me = (n1 + n2) / 2, (e1 + e2) / 2
        fn, fe = mn + 2 * un, me + 2 * ue
        if dentro(P, fn, fe): un, ue = -un, -ue; fn, fe = mn + 2 * un, me + 2 * ue
        if dentro(P, fn, fe) or any(dentro(todos[j], fn, fe) for j in cerca if j != i): continue
        alto = ed["pl"] * 3.0; cota = ed["b"] + max(1.6, min(alto * 0.55, alto - 1.0))
        if suelo(fn, fe) > cota - 1.2: continue                   # el suelo de fuera tapa la placa
        fn5, fe5 = mn + 5 * un, me + 5 * ue
        if any(math.hypot(an - fn5, ae - fe5) < ar + 2 for ae, an, ar in arb): continue   # un arbol delante
        fachadas.append({"n": round(mn, 1), "e": round(me, 1), "cota": round(cota, 2), "normal": round(math.degrees(math.atan2(ue, un)) % 360)})

print(len(recinto), "edificios:", len(cubiertas), "cubiertas,", len(fachadas), "fachadas")
C = {"cubiertas": cubiertas, "fachadas": fachadas, "elegir": [4, 2]}

import sys
DATOS = os.path.join(RAIZ, "datos"); sys.path.insert(0, DATOS)
from leer_datos import escenario, escribir                               # datos/operaciones/op_inspeccion.js
_, E = escenario(os.path.join(DATOS, "operaciones", "op_inspeccion.js")); O2 = {}
for k, v in E["operacion"].items():                                      # "candidatos" delante de "puntos"
    if k == "puntos": O2["candidatos"] = C
    if k != "candidatos": O2[k] = v
E["operacion"] = O2
print("escrito en", escribir("op_inspeccion", E, "operaciones"))
