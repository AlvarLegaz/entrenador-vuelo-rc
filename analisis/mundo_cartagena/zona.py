"""Zona de detalle de un mundo real, comun a los dos simuladores (v1 navegador y v2 Godot).

Descarga, para un cuadrado de LADO metros centrado en (lat, lon), en el plano local del mundo (el mismo de
simulador/mundos/<mundo>.js: N y E en metros desde su origen, alturas sobre el nivel del mar):
  - ortofoto PNOA del IGN (WMS, ~0,5 m/px) en teselas JPEG de 500 m (orto_<i>_<j>.jpg, i hacia el norte, j hacia el este)
  - modelo digital del terreno del IGN a 5 m (WCS Elevacion4258_5), suavizado (viene en metros enteros) -> dem.bin (int16, dm)
  - edificios del Catastro (WFS BU:BuildingPart): huella, plantas y color del tejado sacado de la ortofoto -> edificios.json
  - arboles: manchas oscuras y verdosas de la ortofoto (copas), con su radio -> arboles.bin (float32: E, N, radio)
  - agua: lado de mar de la linea de costa de OSM, a 5 m -> agua en dem.bin (valor -32768)
y escribe zona.json con todo lo necesario para colocarla. Uso:

    python zona.py <mundo.js> <id> <lat> <lon> [lado_m] [salida_dir]

Fuentes: ortofoto y MDT (c) Instituto Geografico Nacional (CC BY 4.0); edificios (c) Direccion General del Catastro;
costa (c) colaboradores de OpenStreetMap (ODbL).
"""
import io, json, math, os, re, struct, sys, time, urllib.parse, urllib.request
import numpy as np
from PIL import Image
from scipy import ndimage
from scipy.spatial import cKDTree

UA = {"User-Agent": "entrenador-vuelo-rc/1.0 (alvarlegaz@gmail.com)"}
TESELA_M, TESELA_PX, PASO_DEM = 500.0, 1024, 5.0


def get(url, datos=None, intentos=4, espera=3):
    for k in range(intentos):
        try:
            req = urllib.request.Request(url, data=datos, headers=UA)
            return urllib.request.urlopen(req, timeout=180).read()
        except Exception as e:
            if k == intentos - 1: raise
            print("  reintento", k + 1, "->", e); time.sleep(espera * (k + 1))


def leer_mundo(ruta):
    s = open(ruta, encoding="utf-8").read()
    return json.loads(s[s.index("Mundos.registrar(") + 17: s.rindex(");")])


def main():
    ruta_mundo, zid, lat, lon = sys.argv[1], sys.argv[2], float(sys.argv[3]), float(sys.argv[4])
    lado = float(sys.argv[5]) if len(sys.argv) > 5 else 3000.0
    raiz = os.path.dirname(os.path.abspath(ruta_mundo))
    salida = sys.argv[6] if len(sys.argv) > 6 else os.path.join(raiz, "..", "zonas", zid)
    os.makedirs(salida, exist_ok=True)
    M = leer_mundo(ruta_mundo)
    LAT0, LON0 = M["origen"]["lat"], M["origen"]["lon"]
    M_LAT = 110574.0; M_LON = 111320.0 * math.cos(math.radians(LAT0))
    a_ll = lambda N, E: (LAT0 + N / M_LAT, LON0 + E / M_LON)
    Nc, Ec = (lat - LAT0) * M_LAT, (lon - LON0) * M_LON
    n_t = int(math.ceil(lado / TESELA_M)); lado = n_t * TESELA_M
    N0, E0 = Nc - lado / 2, Ec - lado / 2                       # esquina suroeste de la zona (m, plano del mundo)
    print("zona %s: %.0f x %.0f m, esquina SO en N %.0f E %.0f (del origen del mundo)" % (zid, lado, lado, N0, E0))

    # ---------------- ortofoto: n_t x n_t teselas de 500 m ----------------
    orto = np.zeros((n_t * TESELA_PX, n_t * TESELA_PX, 3), np.uint8)   # fila 0 = norte
    for i in range(n_t):
        for j in range(n_t):
            nombre = os.path.join(salida, "orto_%d_%d.jpg" % (i, j))
            la0, lo0 = a_ll(N0 + i * TESELA_M, E0 + j * TESELA_M); la1, lo1 = a_ll(N0 + (i + 1) * TESELA_M, E0 + (j + 1) * TESELA_M)
            if not os.path.exists(nombre):
                url = ("https://www.ign.es/wms-inspire/pnoa-ma?SERVICE=WMS&REQUEST=GetMap&VERSION=1.3.0&LAYERS=OI.OrthoimageCoverage&STYLES="
                       "&CRS=EPSG:4326&BBOX=%.7f,%.7f,%.7f,%.7f&WIDTH=%d&HEIGHT=%d&FORMAT=image/jpeg" % (la0, lo0, la1, lo1, TESELA_PX, TESELA_PX))
                open(nombre, "wb").write(get(url))
            im = np.array(Image.open(nombre).convert("RGB"))
            orto[(n_t - 1 - i) * TESELA_PX:(n_t - i) * TESELA_PX, j * TESELA_PX:(j + 1) * TESELA_PX] = im
        print("  ortofoto fila %d/%d" % (i + 1, n_t))
    mpx = TESELA_M / TESELA_PX                                   # m por pixel

    # ---------------- MDT a 5 m ----------------
    m = 300.0                                                   # margen para interpolar en los bordes
    la0, lo0 = a_ll(N0 - m, E0 - m); la1, lo1 = a_ll(N0 + lado + m, E0 + lado + m)
    tif = os.path.join(salida, "_mdt.tif")
    if not os.path.exists(tif):
        url = ("https://servicios.idee.es/wcs-inspire/mdt?SERVICE=WCS&REQUEST=GetCoverage&VERSION=2.0.1&COVERAGEID=Elevacion4258_5"
               "&SUBSET=Lat(%.6f,%.6f)&SUBSET=Long(%.6f,%.6f)&FORMAT=image/tiff" % (la0, la1, lo0, lo1))
        open(tif, "wb").write(get(url))
    im = Image.open(tif); A = np.array(im).astype(np.float32)
    sx, sy = im.tag_v2[33550][0], im.tag_v2[33550][1]; tlon, tlat = im.tag_v2[33922][3], im.tag_v2[33922][4]
    A[A < -100] = 0.0
    A = ndimage.gaussian_filter(A, 1.2)                         # viene en metros enteros: sin esto hace escalones
    nD = int(lado / PASO_DEM) + 1
    Ns = N0 + PASO_DEM * np.arange(nD); Es = E0 + PASO_DEM * np.arange(nD)
    EE, NN = np.meshgrid(Es, Ns)
    LA, LO = a_ll(NN, EE)
    fi, fj = (tlat - LA) / sy - 0.5, (LO - tlon) / sx - 0.5
    H = ndimage.map_coordinates(A, [fi, fj], order=1, mode="nearest")   # fila 0 = sur (N0)
    print("  MDT: %d x %d a 5 m, %.0f..%.0f m" % (nD, nD, H.min(), H.max()))

    # ---------------- agua: linea de costa de OSM (lado de mar del tramo mas cercano) ----------------
    la0, lo0 = a_ll(N0 - 3000, E0 - 3000); la1, lo1 = a_ll(N0 + lado + 3000, E0 + lado + 3000)
    q = '[out:json][timeout:120];way["natural"="coastline"](%.5f,%.5f,%.5f,%.5f);out geom;' % (la0, lo0, la1, lo1)
    try: costa = json.loads(get("https://overpass-api.de/api/interpreter", urllib.parse.urlencode({"data": q}).encode()))["elements"]
    except Exception as e: print("  sin costa de OSM:", e); costa = []
    agua = np.zeros(H.shape, bool)
    P, Dd = [], []
    for w in costa:
        pts = [((g["lat"] - LAT0) * M_LAT, (g["lon"] - LON0) * M_LON) for g in w.get("geometry", [])]
        for (n0, e0), (n1, e1) in zip(pts[:-1], pts[1:]):
            L = math.hypot(n1 - n0, e1 - e0); k = max(1, int(L // 10)); d = np.array([e1 - e0, n1 - n0]) / (L or 1)
            for t in np.linspace(0, 1, k, endpoint=False): P.append([e0 + (e1 - e0) * t, n0 + (n1 - n0) * t]); Dd.append(d)
    if P:
        P, Dd = np.array(P), np.array(Dd); cand = H <= 4
        if cand.any():
            q2 = np.c_[EE[cand], NN[cand]]; dist, idx = cKDTree(P).query(q2); v = q2 - P[idx]
            agua[cand] = np.where(dist < 3000, Dd[idx, 0] * v[:, 1] - Dd[idx, 1] * v[:, 0] < 0, H[cand] <= 0)
    print("  agua: %.1f %% de la zona" % (100 * agua.mean()))
    Hdm = np.round(H * 10).astype(np.int16); Hdm[agua] = -32768
    Hdm.astype("<i2").tofile(os.path.join(salida, "dem.bin"))

    # ---------------- arboles: copas oscuras y verdosas en la ortofoto ----------------
    o = orto.astype(np.float32); lum = o.mean(axis=2)
    fondo = ndimage.uniform_filter(lum, size=int(30 / mpx))      # luminosidad del entorno (30 m)
    verde = o[:, :, 1] - 0.5 * (o[:, :, 0] + o[:, :, 2])
    copa = (lum < 0.80 * fondo) & (lum < 120) & (verde > -6)
    copa = ndimage.binary_opening(copa, iterations=1)
    lab, n = ndimage.label(copa)
    arboles = []
    if n:
        sl = ndimage.find_objects(lab); areas = ndimage.sum(np.ones_like(lab), lab, index=np.arange(1, n + 1))
        cms = ndimage.center_of_mass(copa, lab, np.arange(1, n + 1))
        for (r, c), ar in zip(cms, areas):
            area_m2 = ar * mpx * mpx
            if area_m2 < 3 or area_m2 > 250: continue                # matas sueltas o sombras de edificios
            Np, Ep = N0 + lado - (r + 0.5) * mpx, E0 + (c + 0.5) * mpx
            ii, jj = int((Np - N0) / PASO_DEM), int((Ep - E0) / PASO_DEM)
            if agua[min(ii, nD - 1), min(jj, nD - 1)]: continue
            arboles.append((Ep, Np, math.sqrt(area_m2 / math.pi)))
    np.array(arboles, dtype="<f4").tofile(os.path.join(salida, "arboles.bin"))
    print("  arboles: %d" % len(arboles))

    # ---------------- edificios del Catastro (BuildingPart: huella y plantas), por cuadros de 1 km ----------------
    edificios, vistos = [], set()
    c_km = 1000.0
    for a in range(int(math.ceil(lado / c_km))):
        for b in range(int(math.ceil(lado / c_km))):
            la0, lo0 = a_ll(N0 + a * c_km, E0 + b * c_km); la1, lo1 = a_ll(N0 + (a + 1) * c_km, E0 + (b + 1) * c_km)
            cache = os.path.join(salida, "_catastro_%d_%d.xml" % (a, b))
            if not os.path.exists(cache):
                url = ("https://ovc.catastro.meh.es/INSPIRE/wfsBU.aspx?service=WFS&version=2.0.0&request=GetFeature&typeNames=BU:BuildingPart"
                       "&srsName=EPSG::4326&bbox=%.6f,%.6f,%.6f,%.6f" % (la0, lo0, la1, lo1))
                try: open(cache, "wb").write(get(url))
                except Exception as e: print("  catastro %d,%d sin datos: %s" % (a, b, e)); continue
            s = open(cache, encoding="latin-1").read()
            for f in s.split("<gml:featureMember>")[1:]:
                gid = re.search(r'gml:id="([^"]+)"', f)
                if not gid or gid.group(1) in vistos: continue
                vistos.add(gid.group(1))
                pl = re.search(r"numberOfFloorsAboveGround>(\d+)<", f)
                plantas = int(pl.group(1)) if pl else 1
                if plantas <= 0: continue
                for pos in re.findall(r"<gml:posList[^>]*>([^<]+)</gml:posList>", f)[:1]:
                    v = [float(x) for x in pos.split()]
                    pts = [((v[k] - LAT0) * M_LAT, (v[k + 1] - LON0) * M_LON) for k in range(0, len(v) - 2, 2)]   # (N, E), sin repetir el primero
                    if len(pts) < 3: continue
                    n_m = sum(p[0] for p in pts) / len(pts); e_m = sum(p[1] for p in pts) / len(pts)
                    if not (N0 <= n_m <= N0 + lado and E0 <= e_m <= E0 + lado): continue
                    r_px = int((N0 + lado - n_m) / mpx); c_px = int((e_m - E0) / mpx)
                    r_px, c_px = min(max(r_px, 2), orto.shape[0] - 3), min(max(c_px, 2), orto.shape[1] - 3)
                    col = orto[r_px - 2:r_px + 3, c_px - 2:c_px + 3].reshape(-1, 3).mean(0)
                    ii, jj = int((n_m - N0) / PASO_DEM), int((e_m - E0) / PASO_DEM)
                    base = float(H[min(ii, nD - 1), min(jj, nD - 1)])
                    edificios.append({"p": [round(c, 1) for q_ in pts for c in (q_[1], q_[0])], "pl": plantas,
                                      "b": round(base, 1), "c": "#%02x%02x%02x" % tuple(int(x) for x in col)})
        print("  catastro fila %d: %d edificios" % (a + 1, len(edificios)))
    json.dump(edificios, open(os.path.join(salida, "edificios.json"), "w"), separators=(",", ":"))

    zona = dict(id=zid, mundo=M["id"], centro=dict(lat=lat, lon=lon, N=round(Nc, 1), E=round(Ec, 1)), lado_m=lado, N0=N0, E0=E0,
                orto=dict(teselas=n_t, tesela_m=TESELA_M, tesela_px=TESELA_PX, archivo="orto_{i}_{j}.jpg", nota="i hacia el norte, j hacia el este; fila 0 de cada imagen = su borde norte"),
                dem=dict(archivo="dem.bin", n=nD, paso_m=PASO_DEM, unidad="dm sobre el nivel del mar, int16 little-endian, fila 0 = sur, -32768 = agua"),
                edificios=dict(archivo="edificios.json", n=len(edificios), nota="p: [E, N, ...] (m, plano del mundo); pl: plantas; b: cota de la base (m); c: color del tejado"),
                arboles=dict(archivo="arboles.bin", n=len(arboles), nota="float32 little-endian: E, N, radio de copa (m)"),
                fuente="Ortofoto y MDT: (c) Instituto Geografico Nacional (CC BY 4.0). Edificios: (c) Direccion General del Catastro. Costa: (c) OpenStreetMap (ODbL).")
    json.dump(zona, open(os.path.join(salida, "zona.json"), "w"), indent=1)
    for f in os.listdir(salida):                                # los temporales de descarga no hacen falta en el simulador
        if f.startswith("_"): os.remove(os.path.join(salida, f))
    escribir_indice(os.path.dirname(os.path.abspath(salida)))
    print("zona escrita en", os.path.abspath(salida))


def escribir_indice(dir_zonas):
    """zonas/indice.json: la cabecera (zona.json) de todas las zonas de la carpeta, para que los dos simuladores sepan
    cuales hay sin recorrer el disco (el navegador no puede)."""
    lista = []
    for d in sorted(os.listdir(dir_zonas)):
        f = os.path.join(dir_zonas, d, "zona.json")
        if os.path.isfile(f): lista.append(json.load(open(f)))
    json.dump(lista, open(os.path.join(dir_zonas, "indice.json"), "w"), indent=1)


if __name__ == "__main__":
    main()
