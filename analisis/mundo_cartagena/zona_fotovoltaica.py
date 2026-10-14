"""Zona de detalle de las plantas fotovoltaicas reales y la fabrica de SABIC de La Aljorra (Campo de Cartagena; la planta
la marco el usuario en 37,698102 N 1,108462 O y pidio la fabrica de al lado, 2026-10-14): un cuadrado de 3 km que cubre
las dos cosas (una sola zona: dos zonas solapadas se pelearian en la profundidad), ortofoto PNOA a 0,25 m (ZONA_PX=2048),
MDT a 5 m, edificios del Catastro y arboles de la ortofoto. Las filas de paneles y la fabrica se ven en la ortofoto.

El detector de arboles de zona.py toma por copas las filas oscuras de los paneles y las tuberias, depositos y balsas de
la fabrica: aqui se quitan los arboles que caen en los paneles (textura de filas norte-sur: mucho mas gradiente de este
a oeste que de norte a sur, en ventanas de 12,5 m) y dentro del recinto de la fabrica (poligono medido en la ortofoto).

    python analisis/mundo_cartagena/zona_fotovoltaica.py            (unos 20 min; la zona no va al repositorio)
    python analisis/mundo_cartagena/zona_fotovoltaica.py limpiar    (solo vuelve a quitar los arboles falsos y los contornos)
"""
import json, os, subprocess, sys
import numpy as np
from PIL import Image
from scipy import ndimage

ID, LAT, LON, LADO = "fotovoltaica", 37.700823, -1.105491, 3000      # centro entre las plantas y la fabrica
# recinto de la fabrica de SABIC: (E, N) en metros desde la esquina suroeste de la zona
FABRICA = [(1500, 2900), (2475, 2900), (2750, 2275), (2500, 1825), (1750, 1275), (1075, 1887), (1400, 2375)]


def dentro(px, py, pol):
    """Punto en poligono (vectorizado): px, py arrays."""
    d = np.zeros(px.shape, bool); n = len(pol)
    for k in range(n):
        x0, y0 = pol[k]; x1, y1 = pol[(k + 1) % n]
        cruza = ((y0 > py) != (y1 > py)) & (px < (x1 - x0) * (py - y0) / ((y1 - y0) or 1e-9) + x0)
        d ^= cruza
    return d


def mascara_paneles(zdir, n_t, mpx=0.5):
    R = int(500 / mpx); g = np.zeros((n_t * R, n_t * R), np.float32)
    for i in range(n_t):
        for j in range(n_t):
            g[(n_t - 1 - i) * R:(n_t - i) * R, j * R:(j + 1) * R] = np.asarray(Image.open(os.path.join(zdir, "orto_%d_%d.jpg" % (i, j))).convert("L").resize((R, R), Image.BILINEAR), np.float32)
    gx = np.abs(np.diff(g, axis=1, append=g[:, -1:])); gy = np.abs(np.diff(g, axis=0, append=g[-1:, :]))
    w = int(12.5 / mpx); mx = ndimage.uniform_filter(gx, w); my = ndimage.uniform_filter(gy, w)
    p = (mx > 2.2 * my) & (mx > 7)
    p = ndimage.binary_opening(p, iterations=3); p = ndimage.binary_closing(p, iterations=20)
    p = ndimage.binary_fill_holes(p); p = ndimage.binary_dilation(p, iterations=6)
    return p                                                       # fila 0 = norte, mpx m por pixel


def limpiar(zdir):
    Z = json.load(open(os.path.join(zdir, "zona.json"))); N0, E0, lado = Z["N0"], Z["E0"], Z["lado_m"]
    a = np.fromfile(os.path.join(zdir, "arboles.bin"), dtype="<f4").reshape(-1, 3)
    if os.path.exists(os.path.join(zdir, "arboles_detectados.bin")):          # siempre desde lo que detecto zona.py
        a = np.fromfile(os.path.join(zdir, "arboles_detectados.bin"), dtype="<f4").reshape(-1, 3)
    else: a.tofile(os.path.join(zdir, "arboles_detectados.bin"))
    mpx = 0.5; P = mascara_paneles(zdir, int(round(lado / 500)), mpx)
    e = a[:, 0] - E0; n = a[:, 1] - N0
    fil = np.clip(((lado - n) / mpx).astype(int), 0, P.shape[0] - 1); col = np.clip((e / mpx).astype(int), 0, P.shape[1] - 1)
    fuera = P[fil, col] | dentro(e, n, FABRICA)
    b = a[~fuera]; b.astype("<f4").tofile(os.path.join(zdir, "arboles.bin"))
    Z["arboles"]["n"] = int(len(b)); json.dump(Z, open(os.path.join(zdir, "zona.json"), "w"), indent=1)
    print("arboles: %d -> %d (quitados %d en paneles y fabrica)" % (len(a), len(b), int(fuera.sum())))
    # el Catastro trae como "edificio" de una planta el contorno entero de algunas unidades de proceso (hasta 24.000 m2):
    # bloques planos que tapan las instalaciones de singulares.js (sabic_industria.py); fuera los de mas de 7.000 m2
    ed = json.load(open(os.path.join(zdir, "edificios.json")))
    def area(q): x, y = np.array(q[0::2]) - E0, np.array(q[1::2]) - N0; return 0.5 * abs(np.dot(x, np.roll(y, 1)) - np.dot(y, np.roll(x, 1)))
    def en_fabrica(q): return dentro(np.array([np.mean(q[0::2]) - E0]), np.array([np.mean(q[1::2]) - N0]), FABRICA)[0]
    quedan = [d for d in ed if not (d["pl"] == 1 and area(d["p"]) > 7000 and en_fabrica(d["p"]))]
    if len(quedan) != len(ed): json.dump(quedan, open(os.path.join(zdir, "edificios.json"), "w"), separators=(",", ":"))
    print("edificios: %d -> %d (contornos de unidades de proceso)" % (len(ed), len(quedan)))
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import empaquetar_fichero
    empaquetar_fichero.zona(zdir); empaquetar_fichero.indice(os.path.dirname(os.path.abspath(zdir)))


if __name__ == "__main__":
    aqui = os.path.dirname(os.path.abspath(__file__))
    zdir = os.path.join(aqui, "..", "..", "simulador", "zonas", ID)
    if len(sys.argv) < 2 or sys.argv[1] != "limpiar":
        mundo = os.path.join(aqui, "..", "..", "simulador", "mundos", "cartagena.js")
        if os.path.exists(os.path.join(zdir, "arboles_detectados.bin")): os.remove(os.path.join(zdir, "arboles_detectados.bin"))
        subprocess.run([sys.executable, os.path.join(aqui, "zona.py"), mundo, ID, "%.6f" % LAT, "%.6f" % LON, str(LADO)], cwd=aqui, check=True,
                       env=dict(os.environ, ZONA_PX="2048"))
    limpiar(zdir)
