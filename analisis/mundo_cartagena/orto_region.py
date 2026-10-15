"""Ortofoto PNOA de toda la region de un mundo real (fondo lejano de los dos simuladores), ajustada exactamente a
la malla de terreno del mundo: de (N0, E0) a (N0 + (nN-1) paso, E0 + (nE-1) paso). Escribe <mundo>_orto.jpg junto al
fichero del mundo, con fila 0 = borde norte. Por defecto 12 m/px (para el mundo de Cartagena, 6537 x 3127 px: cabe en
una textura de 8192 de cualquier grafica).

    python orto_region.py <mundo.js> [m_por_px]

Fuente: ortofoto (c) Instituto Geografico Nacional (CC BY 4.0).
"""
import io, json, math, os, sys, time, urllib.request
from PIL import Image

UA = {"User-Agent": "uxs-trainer/1.0 (+https://github.com/AlvarLegaz/uxs-trainer)"}
Image.MAX_IMAGE_PIXELS = None


def get(url, intentos=4):
    for k in range(intentos):
        try: return urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=180).read()
        except Exception as e:
            if k == intentos - 1: raise
            print("  reintento", e); time.sleep(4 * (k + 1))


ruta = sys.argv[1]; mpx = float(sys.argv[2]) if len(sys.argv) > 2 else 12.0
s = open(ruta, encoding="utf-8").read(); M = json.loads(s[s.index("Mundos.registrar(") + 17: s.rindex(");")])
T = M["terreno"]; LAT0, LON0 = M["origen"]["lat"], M["origen"]["lon"]
M_LAT = 110574.0; M_LON = 111320.0 * math.cos(math.radians(LAT0))
anchoM, altoM = (T["nE"] - 1) * T["paso"], (T["nN"] - 1) * T["paso"]
W, Hh = int(round(anchoM / mpx)), int(round(altoM / mpx))
img = Image.new("RGB", (W, Hh))
BLOQ = 2048
for y0 in range(0, Hh, BLOQ):
    for x0 in range(0, W, BLOQ):
        w, h = min(BLOQ, W - x0), min(BLOQ, Hh - y0)
        e0, e1 = T["E0"] + x0 * anchoM / W, T["E0"] + (x0 + w) * anchoM / W
        n1, n0 = T["N0"] + altoM - y0 * altoM / Hh, T["N0"] + altoM - (y0 + h) * altoM / Hh
        url = ("https://www.ign.es/wms-inspire/pnoa-ma?SERVICE=WMS&REQUEST=GetMap&VERSION=1.3.0&LAYERS=OI.OrthoimageCoverage&STYLES="
               "&CRS=EPSG:4326&BBOX=%.7f,%.7f,%.7f,%.7f&WIDTH=%d&HEIGHT=%d&FORMAT=image/jpeg"
               % (LAT0 + n0 / M_LAT, LON0 + e0 / M_LON, LAT0 + n1 / M_LAT, LON0 + e1 / M_LON, w, h))
        img.paste(Image.open(io.BytesIO(get(url))).convert("RGB"), (x0, y0))
        print("  bloque", x0, y0)
# mar abierto: el PNOA no tiene foto (sale blanco o negro): azul mar
import numpy as np
A = np.array(img); sin = (A.min(axis=2) >= 248) | (A.max(axis=2) <= 4)
A[sin] = (28, 62, 96); img = Image.fromarray(A)
sal = os.path.join(os.path.dirname(os.path.abspath(ruta)), M["id"] + "_orto.jpg")
img.save(sal, quality=85)
print("escrito", sal, W, "x", Hh, round(os.path.getsize(sal) / 1e6, 1), "MB")
# la misma foto empaquetada en .js, para abrir simulador.html con doble clic (ver empaquetar_fichero.py)
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import empaquetar_fichero
empaquetar_fichero.ortofoto_mundo(sal)
