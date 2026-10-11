"""Mascara de agua para terreno.json a partir de la linea de costa de OpenStreetMap (osm_costa.json): una celda es
agua si esta en el lado de mar del tramo de costa mas cercano (en OSM la tierra queda a la izquierda del sentido de
la linea) y su altura SRTM no pasa de 3 m. Con la regla "altura <= 0" la llanura de la orilla del Mar Menor salia
inundada (el SRTM la deja a 0 o menos). Tambien exporta las masas de agua interiores (balsas de riego, lagunas) como
poligonos para pintarlas en la textura. Reescribe terreno.json y escribe agua.json."""
import base64, json
import numpy as np
from scipy.spatial import cKDTree

T = json.load(open("terreno.json"))
LAT0, LON0 = T["origen"]["lat"], T["origen"]["lon"]
M_LAT = 110574.0; M_LON = 111320.0 * np.cos(np.radians(LAT0))
NE = lambda lat, lon: ((lat - LAT0) * M_LAT, (lon - LON0) * M_LON)
H = np.frombuffer(base64.b64decode(T["alturas_b64"]), dtype="<i2").reshape(T["nN"], T["nE"]).astype(np.int16).copy()
el = json.load(open("osm_costa.json", encoding="utf-8"))["elements"]

# --- linea de costa densificada cada 40 m, con la direccion de cada tramo ---
P, D = [], []
for w in el:
    if w.get("type") != "way" or w.get("tags", {}).get("natural") != "coastline" or "geometry" not in w: continue
    pts = [NE(g["lat"], g["lon"]) for g in w["geometry"]]
    for (n0, e0), (n1, e1) in zip(pts[:-1], pts[1:]):
        L = np.hypot(n1 - n0, e1 - e0); k = max(1, int(L // 40)); d = np.array([e1 - e0, n1 - n0]) / (L or 1)
        for t in np.linspace(0, 1, k, endpoint=False): P.append([e0 + (e1 - e0) * t, n0 + (n1 - n0) * t]); D.append(d)
P = np.array(P); D = np.array(D); print("costa:", len(P), "puntos")
arbol = cKDTree(P)
Es = T["E0"] + T["paso"] * np.arange(T["nE"]); Ns = T["N0"] + T["paso"] * np.arange(T["nN"])
EE, NN = np.meshgrid(Es, Ns)
cand = H <= 3
q = np.c_[EE[cand], NN[cand]]
dist, idx = arbol.query(q)
v = q - P[idx]; cruz = D[idx, 0] * v[:, 1] - D[idx, 1] * v[:, 0]      # > 0: a la izquierda del sentido = tierra
# lejos de la costa (> 3 km) la linea cortada por la caja engana (quedan cunas de 'tierra' en alta mar): ahi vale h <= 0
agua = np.zeros(H.shape, bool); agua[cand] = np.where(dist < 3000, cruz < 0, H[cand] <= 0)
# (sin filtro de mayoria: se comia las franjas estrechas como La Manga, de 100-800 m, y su carretera quedaba en el agua)
# donde pasa una carretera (que no sea puente) hay tierra: se fuerza la celda (y su altura a 3 m como minimo)
carr = json.load(open("osm_carreteras.json", encoding="utf-8"))["elements"]
forzadas = 0
for w in carr:
    if "geometry" not in w or w.get("tags", {}).get("bridge") in ("yes", "viaduct"): continue
    pts = [NE(g["lat"], g["lon"]) for g in w["geometry"]]
    for (n0, e0), (n1, e1) in zip(pts[:-1], pts[1:]):
        k = max(1, int(np.hypot(n1 - n0, e1 - e0) // 30))
        for t in np.linspace(0, 1, k + 1):
            i = int(round((n0 + (n1 - n0) * t - T["N0"]) / T["paso"])); j = int(round((e0 + (e1 - e0) * t - T["E0"]) / T["paso"]))
            if 0 <= i < T["nN"] and 0 <= j < T["nE"]:
                if agua[i, j]: forzadas += 1
                agua[i, j] = False; H[i, j] = max(H[i, j], 3)
print("celdas de agua pasadas a tierra por una carretera:", forzadas)
print("agua: %.1f %% de las celdas (antes, h<=0: %.1f %%)" % (100 * agua.mean(), 100 * (H <= 0).mean()))
H[agua] = 0; H[~agua] = np.maximum(H[~agua], 1)
T["alturas_b64"] = base64.b64encode(H.astype("<i2").tobytes()).decode("ascii")
bits = np.packbits(agua.ravel()); T["agua_b64"] = base64.b64encode(bits.tobytes()).decode("ascii")
# laguna (Mar Menor): el agua que queda separada del Mediterraneo al cerrar las golas (erosion de 2 celdas), y luego
# devuelta a su tamano dentro del agua. Sirve para pintarla con su color, mas claro y verdoso
from scipy.ndimage import binary_erosion, binary_dilation, label
lab, n = label(binary_erosion(agua, iterations=2))
def celda_ll(lat, lon):
    n_, e_ = NE(lat, lon); return int(round((n_ - T["N0"]) / T["paso"])), int(round((e_ - T["E0"]) / T["paso"]))
il, jl = celda_ll(37.70, -0.78)
laguna = np.zeros_like(agua)
if lab[il, jl]:
    laguna = lab == lab[il, jl]
    laguna = binary_dilation(laguna, iterations=3) & agua
print("laguna: %.1f km2" % (laguna.sum() * T["paso"] ** 2 / 1e6))
T["laguna_b64"] = base64.b64encode(np.packbits(laguna.ravel()).tobytes()).decode("ascii")
T["nota_agua"] = "agua_b64: 1 bit por celda (packbits, orden de filas), agua segun la linea de costa de OSM; en esas celdas la altura es 0"
json.dump(T, open("terreno.json", "w"))

# --- masas de agua interiores: poligonos cerrados (balsas, lagunas, embalses), > 1500 m2 ---
def rdp(p, tol):
    if len(p) < 3: return p
    a, b = np.array(p[0]), np.array(p[-1]); d = b - a; L = np.hypot(*d)
    dist = [np.hypot(*(np.array(x) - a)) for x in p] if L < 1e-6 else [abs(d[0] * (x[1] - a[1]) - d[1] * (x[0] - a[0])) / L for x in p]
    i = int(np.argmax(dist))
    return rdp(p[:i + 1], tol)[:-1] + rdp(p[i:], tol) if dist[i] > tol else [p[0], p[-1]]
masas = []
for w in el:
    if w.get("type") != "way" or w.get("tags", {}).get("natural") != "water" or "geometry" not in w: continue
    g = w["geometry"]
    if len(g) < 4 or (g[0]["lat"], g[0]["lon"]) != (g[-1]["lat"], g[-1]["lon"]): continue
    pts = rdp([tuple(reversed(NE(p["lat"], p["lon"]))) for p in g], 8.0)   # (E, N)
    x = np.array([p[0] for p in pts]); y = np.array([p[1] for p in pts])
    area = 0.5 * abs(np.dot(x, np.roll(y, 1)) - np.dot(y, np.roll(x, 1)))
    if area < 1500 or len(pts) < 4: continue
    masas.append([round(v) for p in pts[:-1] for v in p])
print("masas de agua interiores:", len(masas))
json.dump(masas, open("agua.json", "w"))
# control: puntos conocidos
def celda(lat, lon):
    n, e = NE(lat, lon); return int(round((n - T["N0"]) / T["paso"])), int(round((e - T["E0"]) / T["paso"]))
for nm, lat, lon in [("Los Alcazares (pueblo)", 37.744, -0.850), ("Los Urrutias", 37.702, -0.852), ("Mar Menor centro", 37.70, -0.78), ("La Manga", 37.68, -0.735), ("Mediterraneo", 37.50, -1.0), ("Cartagena puerto", 37.595, -0.98), ("Portman bahia", 37.578, -0.845)]:
    i, j = celda(lat, lon); print("%-24s agua=%s h=%d" % (nm, agua[i, j], H[i, j]))
