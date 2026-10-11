"""Terreno del Campo de Cartagena para el simulador: lee las teselas SRTM de 3 segundos (90 m) de
viewfinderpanoramas (J30.zip: N37W002.hgt y N37W001.hgt), las remuestrea a una malla de PASO metros en un plano
local NED centrado en el origen (el corazon de la captura) y escribe terreno.json con las alturas en int16.

Ejes: N hacia el norte, E hacia el este (m). Altura h en m sobre el nivel del mar; el simulador resta h0 (la del origen)."""
import base64, json, sys, zipfile
import numpy as np

ORIGEN = (37.612788, -1.049916)          # lat, lon del corazon (georef.py)
LAT0, LAT1, LON0, LON1 = 37.47, 37.81, -1.39, -0.50   # extension de la captura
PASO = 150.0                               # m entre nodos de la malla
M_LAT = 110574.0; M_LON = 111320.0 * np.cos(np.radians(ORIGEN[0]))

z = zipfile.ZipFile("J30.zip")
def tesela(nombre):
    d = np.frombuffer(z.read("J30/" + nombre), dtype=">i2").astype(np.float32).reshape(1201, 1201)
    d[d < -1000] = 0.0                   # huecos
    return d
T = {-2: tesela("N37W002.hgt"), -1: tesela("N37W001.hgt")}   # lon base -2 (de -2 a -1) y -1 (de -1 a 0)

def altura(lat, lon):
    """Interpolacion bilineal en las teselas (fila 0 = lat 38, col 0 = lon base)."""
    lat = np.asarray(lat); lon = np.asarray(lon)
    out = np.zeros(lat.shape, np.float32)
    for base, d in T.items():
        m = (lon >= base) & (lon < base + 1)
        if not m.any(): continue
        x = (lon[m] - base) * 1200.0; y = (38.0 - lat[m]) * 1200.0
        x0 = np.clip(np.floor(x).astype(int), 0, 1199); y0 = np.clip(np.floor(y).astype(int), 0, 1199)
        fx = x - x0; fy = y - y0
        out[m] = (d[y0, x0] * (1 - fx) * (1 - fy) + d[y0, x0 + 1] * fx * (1 - fy) + d[y0 + 1, x0] * (1 - fx) * fy + d[y0 + 1, x0 + 1] * fx * fy)
    return out

N0, N1 = (LAT0 - ORIGEN[0]) * M_LAT, (LAT1 - ORIGEN[0]) * M_LAT
E0, E1 = (LON0 - ORIGEN[1]) * M_LON, (LON1 - ORIGEN[1]) * M_LON
N0, E0 = np.floor(N0 / PASO) * PASO, np.floor(E0 / PASO) * PASO
nN, nE = int((N1 - N0) // PASO) + 1, int((E1 - E0) // PASO) + 1
Ns = N0 + PASO * np.arange(nN); Es = E0 + PASO * np.arange(nE)
EE, NN = np.meshgrid(Es, Ns)
H = altura(ORIGEN[0] + NN / M_LAT, ORIGEN[1] + EE / M_LON)
h0 = float(altura(np.array([ORIGEN[0]]), np.array([ORIGEN[1]]))[0])
Hi = np.round(H).astype(np.int16)
print("malla %d x %d (N %d..%d, E %d..%d m), paso %.0f m | h0 en el origen %.0f m | alturas %d..%d m | mar (h<=0): %.0f %%"
      % (nN, nE, N0, Ns[-1], E0, Es[-1], PASO, h0, Hi.min(), Hi.max(), 100 * (Hi <= 0).mean()))
json.dump(dict(origen=dict(lat=ORIGEN[0], lon=ORIGEN[1]), paso=PASO, N0=float(N0), E0=float(E0), nN=nN, nE=nE, h0=h0,
               alturas_b64=base64.b64encode(Hi.tobytes()).decode("ascii"), nota="int16 little-endian, fila = N (de N0 hacia el norte), columna = E"),
          open("terreno.json", "w"))
print("terreno.json", round(len(open("terreno.json").read()) / 1024), "kB")
