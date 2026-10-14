"""Georreferencia la captura de Google Maps: geocodifica los nombres de los pueblos (Nominatim) y ajusta
lon = a + b x, lat = c + d y. Da las coordenadas del corazon y de la estrella."""
import json, time, urllib.request, urllib.parse
import numpy as np

ETIQUETAS = {  # nombre en la captura: (x, y) del centro de la etiqueta (imagen de 1838 x 904)
    "Los Alcázares": (1105, 174), "La Puebla, Cartagena": (952, 250), "La Aljorra": (647, 323), "Las Palas, Fuente Álamo": (404, 397),
    "Isla Plana": (360, 625), "La Azohía": (420, 641), "Portmán": (1095, 586), "Mar de Cristal": (1276, 453),
    "Los Urrutias": (1133, 351), "El Jimenado": (722, 126), "Balsapintada": (580, 157), "Puerto de Mazarrón": (253, 650),
    "Atamaría": (1205, 570), "Cánovas, Fuente Álamo": (218, 203), "Los Almagros, Fuente Álamo": (247, 140), "El Escobar, Fuente Álamo": (343, 116),
    "Bolnuevo": (158, 657), "Cuevas de Reyllo": (285, 200), "Dolores de Pacheco": (1060, 92), "Valladolises": (540, 93),
    "El Saladillo, Mazarrón": (102, 358), "La Pinilla, Fuente Álamo": (215, 340), "Bahía Bella": (1072, 252),
}
pts = []
for nombre, (x, y) in ETIQUETAS.items():
    q = urllib.parse.urlencode({"q": nombre + ", Región de Murcia", "format": "json", "limit": 1})
    req = urllib.request.Request("https://nominatim.openstreetmap.org/search?" + q, headers={"User-Agent": "entrenador-vuelo-rc/1.0 (+https://github.com/AlvarLegaz/entrenador-vuelo-rc)"})
    try:
        r = json.load(urllib.request.urlopen(req, timeout=20))
        if r:
            pts.append((nombre, x, y, float(r[0]["lon"]), float(r[0]["lat"]), r[0].get("display_name", "")[:60]))
            print("%-32s %7.4f %8.4f  %s" % (nombre, float(r[0]["lat"]), float(r[0]["lon"]), r[0].get("display_name", "")[:50]))
        else:
            print("%-32s sin resultado" % nombre)
    except Exception as e:
        print(nombre, "error", e)
    time.sleep(1.1)
P = np.array([[p[1], p[2], p[3], p[4]] for p in pts])
# ajuste robusto: lineal y luego quitar los puntos con residuo grande (geocodificaciones erroneas)
def ajustar(P):
    A = np.c_[np.ones(len(P)), P[:, 0]]; b_lon = np.linalg.lstsq(A, P[:, 2], rcond=None)[0]
    A2 = np.c_[np.ones(len(P)), P[:, 1]]; b_lat = np.linalg.lstsq(A2, P[:, 3], rcond=None)[0]
    return b_lon, b_lat
for _ in range(3):
    b_lon, b_lat = ajustar(P)
    res = np.hypot((b_lon[0] + b_lon[1] * P[:, 0] - P[:, 2]) * 88.0, (b_lat[0] + b_lat[1] * P[:, 1] - P[:, 3]) * 111.0)   # km
    ok = res < max(1.5, 2.5 * np.median(res))
    print("residuos km:", np.round(res, 2), "descartados:", [pts[i][0] for i in range(len(pts)) if not ok[i]])
    P = P[ok]; pts = [p for p, k in zip(pts, ok) if k]
b_lon, b_lat = ajustar(P)
f = lambda x, y: (b_lat[0] + b_lat[1] * y, b_lon[0] + b_lon[1] * x)
print("px/km: %.1f (lon) %.1f (lat)" % (1 / (b_lon[1] * 88.0), -1 / (b_lat[1] * 111.0)))
print("corazon (696,525):", f(696, 525)); print("estrella (393,423):", f(393, 423))
print("esquinas: NO", f(0, 0), "SE", f(1838, 904))
json.dump(dict(b_lon=b_lon.tolist(), b_lat=b_lat.tolist(), corazon=f(696, 525), estrella=f(393, 423), NO=f(0, 0), SE=f(1838, 904)), open("georef.json", "w"), indent=1)
