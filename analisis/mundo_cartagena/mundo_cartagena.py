"""Junta terreno.json (SRTM) y los ficheros de OpenStreetMap (Overpass) en simulador/mundos/cartagena.js:
el mundo real del Campo de Cartagena para el vuelo libre. Coordenadas locales NED en metros con origen en el
corazon de la captura (lat 37.612788, lon -1.049916); alturas sobre el nivel del mar."""
import json, sys
import numpy as np

SALIDA = sys.argv[1]
T = json.load(open("terreno.json"))
LAT0, LON0 = T["origen"]["lat"], T["origen"]["lon"]
M_LAT = 110574.0; M_LON = 111320.0 * np.cos(np.radians(LAT0))
NE = lambda lat, lon: ((lat - LAT0) * M_LAT, (lon - LON0) * M_LON)
# el simulador lee los puntos como (E, N): EN() es la que se usa para todo lo que se exporta
EN = lambda lat, lon: ((lon - LON0) * M_LON, (lat - LAT0) * M_LAT)


def rdp(p, tol):
    """Simplificacion de Douglas-Peucker (p: lista de puntos 2D)."""
    if len(p) < 3: return p
    a, b = np.array(p[0]), np.array(p[-1]); d = b - a; L = np.hypot(*d)
    if L < 1e-6: dist = [np.hypot(*(np.array(q) - a)) for q in p]
    else: dist = [abs(d[0] * (q[1] - a[1]) - d[1] * (q[0] - a[0])) / L for q in p]
    i = int(np.argmax(dist))
    if dist[i] > tol: return rdp(p[:i + 1], tol)[:-1] + rdp(p[i:], tol)
    return [p[0], p[-1]]


def leer(nombre):
    try: return json.load(open(nombre, encoding="utf-8"))["elements"]
    except Exception as e: print("sin", nombre, e); return []


# ---- carreteras: polilineas por tipo, simplificadas a 15 m ----
TIPOS = {"motorway": 1, "motorway_link": 1, "trunk": 1, "trunk_link": 1, "primary": 2, "secondary": 3, "tertiary": 4}
carreteras, npts = [], 0
for w in leer("osm_carreteras.json"):
    if w.get("type") != "way" or "geometry" not in w: continue
    t = TIPOS.get(w["tags"].get("highway"), 0)
    if not t: continue
    pts = rdp([EN(g["lat"], g["lon"]) for g in w["geometry"]], 15.0)
    if len(pts) < 2: continue
    carreteras.append([t] + [round(v) for q in pts for v in q]); npts += len(pts)
print("carreteras:", len(carreteras), "tramos,", npts, "puntos")

# ---- zonas urbanas: poligonos cerrados (ways), simplificados a 25 m, de mas de 1,5 ha ----
urbano, area_tot = [], 0.0
for w in leer("osm_urbano.json"):
    if w.get("type") != "way" or "geometry" not in w: continue
    g = w["geometry"]
    if len(g) < 4 or (g[0]["lat"], g[0]["lon"]) != (g[-1]["lat"], g[-1]["lon"]): continue
    pts = rdp([EN(p["lat"], p["lon"]) for p in g], 25.0)
    if len(pts) < 4: continue
    x = np.array([p[0] for p in pts]); y = np.array([p[1] for p in pts])
    area = 0.5 * abs(np.dot(x, np.roll(y, 1)) - np.dot(y, np.roll(x, 1)))
    if area < 15000: continue
    tipo = 1 if w["tags"].get("landuse") == "residential" else 2
    urbano.append([tipo] + [round(v) for q in pts[:-1] for v in q]); area_tot += area
print("urbano:", len(urbano), "poligonos,", round(area_tot / 1e6, 1), "km2")

# ---- lugares con nombre ----
RANGO = {"city": 1, "town": 2, "village": 3, "suburb": 4, "hamlet": 5}   # en 3D se rotulan hasta 3; en el GPS, hasta 4
lugares = []
for n in leer("osm_lugares.json"):
    if n.get("type") != "node" or "name" not in n.get("tags", {}): continue
    e, nn = EN(n["lat"], n["lon"]); lugares.append([n["tags"]["name"], RANGO.get(n["tags"].get("place"), 5), round(e), round(nn)])
print("lugares:", len(lugares))

# ---- rumbo de despegue: el de los 8 con menos terreno por delante en 1,5 km ----
import base64
H = np.frombuffer(base64.b64decode(T["alturas_b64"]), dtype="<i2").reshape(T["nN"], T["nE"]).astype(float)
def h_en(N, E):
    i = (N - T["N0"]) / T["paso"]; j = (E - T["E0"]) / T["paso"]
    i = np.clip(i, 0, T["nN"] - 1.001); j = np.clip(j, 0, T["nE"] - 1.001)
    i0, j0 = np.floor(i).astype(int), np.floor(j).astype(int); fi, fj = i - i0, j - j0
    return H[i0, j0] * (1 - fi) * (1 - fj) + H[i0 + 1, j0] * fi * (1 - fj) + H[i0, j0 + 1] * (1 - fi) * fj + H[i0 + 1, j0 + 1] * fi * fj
mejor = None
for r in range(0, 360, 45):
    d = np.linspace(100, 1500, 29); N = d * np.cos(np.radians(r)); E = d * np.sin(np.radians(r))
    sube = (h_en(N, E) - T["h0"]).max()
    print("  rumbo %3d: terreno hasta %+4.0f m respecto al origen en 1,5 km" % (r, sube))
    if mejor is None or sube < mejor[1]: mejor = (r, sube)
print("rumbo de despegue:", mejor[0])

try: agua = json.load(open("agua.json"))          # masas de agua interiores (agua.py): balsas de riego, lagunas
except Exception: agua = []
print("masas de agua:", len(agua))
mundo = dict(id="cartagena", nombre="Campo de Cartagena (mapa real)", origen=T["origen"], terreno=T, carreteras=carreteras, urbano=urbano, agua=agua,
             lugares=lugares, rumbo_despegue=mejor[0], fuente="Terreno: SRTM 3\" (viewfinderpanoramas.org). Carreteras, zonas urbanas y lugares: OpenStreetMap (ODbL).")
with open(SALIDA, "w", encoding="utf-8") as f:
    f.write("// Mundo real del Campo de Cartagena para el vuelo libre. Generado por mundo_cartagena.py: no editar a mano.\n")
    f.write("// " + mundo["fuente"] + "\n")
    f.write("Mundos.registrar(" + json.dumps(mundo, ensure_ascii=False, separators=(",", ":")) + ");\n")
import os
print("escrito", SALIDA, round(os.path.getsize(SALIDA) / 1024), "kB")
