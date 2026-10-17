"""Zona de detalle del CIFP Politecnico de Cartagena (calle Grecia, 56) a la MAXIMA calidad que dan las fuentes
abiertas (2026-10-13): cuadrado de 2 km centrado en el centro, ortofoto PNOA a 0,25 m (ZONA_PX=2048: la resolucion
real del vuelo en Cartagena; a 0,125 m no se ve mas), MDT a 5 m, edificios del Catastro por partes con sus plantas
reales (los tejados se texturizan con la propia ortofoto y las fachadas llevan ventanas por planta en los dos
simuladores) y arboles de la ortofoto. El punto de despegue del CIFP esta destacado en el mapa de salida
(datos/escenarios.js, "destacados" del vuelo libre en Cartagena).

    python analisis/mundo_cartagena/zona_cifp.py          (unos 5 min; la zona no va al repositorio)
    python analisis/mundo_cartagena/zona_cifp.py --solo-fachadas      (solo vuelve a marcar las fachadas)
"""
import os, subprocess, sys

ID, LAT, LON, LADO = "cifp_politecnico", 37.61414, -0.97441, 2000
# parcela del CIFP (OpenStreetMap, way 77213611) y color de sus fachadas: ladrillo caravista rojo (fotos del centro,
# solo como referencia de color; no se copia ninguna imagen). Los edificios del Catastro de dentro llevan "f"
PARCELA = [[37.613164, -0.975122], [37.613178, -0.974609], [37.613191, -0.974021], [37.6132, -0.973826], [37.614295, -0.972974], [37.615252, -0.9748], [37.613979, -0.975854], [37.613164, -0.975122]]
LADRILLO = "#a4553f"


def marcar_fachadas(dir_zona):
    """Pone "f" (color de fachada) a los edificios de la zona cuyo centro cae dentro de la parcela del CIFP."""
    import json, math
    Z = json.load(open(os.path.join(dir_zona, "zona.json")))
    s = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "datos", "escenarios", "mundos", "cartagena.js"), encoding="utf-8").read()
    o = json.loads(s[s.index("Mundos.registrar(") + 17: s.rindex(");")])["origen"]
    M_LAT, M_LON = 110574.0, 111320.0 * math.cos(math.radians(o["lat"]))
    P = [((la - o["lat"]) * M_LAT, (lo - o["lon"]) * M_LON) for la, lo in PARCELA]       # (N, E)
    def dentro(n, e):
        d = False
        for i in range(len(P)):
            (n1, e1), (n2, e2) = P[i], P[i - 1]
            if (n1 > n) != (n2 > n) and e < (e2 - e1) * (n - n1) / (n2 - n1) + e1: d = not d
        return d
    ruta = os.path.join(dir_zona, Z["edificios"]["archivo"]); eds = json.load(open(ruta)); k = 0
    for ed in eds:
        p = ed["p"]; e = sum(p[0::2]) / (len(p) // 2); n = sum(p[1::2]) / (len(p) // 2)
        if dentro(n, e): ed["f"] = LADRILLO; k += 1
    json.dump(eds, open(ruta, "w"), separators=(",", ":"))
    print("fachadas de ladrillo en %d partes de edificio del CIFP" % k)

if __name__ == "__main__":
    aqui = os.path.dirname(os.path.abspath(__file__))
    mundo = os.path.join(aqui, "..", "..", "datos", "escenarios", "mundos", "cartagena.js")
    env = dict(os.environ, ZONA_PX="2048")
    dir_zona = os.path.join(aqui, "..", "..", "datos", "escenarios", "zonas", ID)
    if "--solo-fachadas" not in sys.argv:
        subprocess.run([sys.executable, os.path.join(aqui, "zona.py"), mundo, ID, "%.6f" % LAT, "%.6f" % LON, str(LADO)], cwd=aqui, env=env, check=True)
    marcar_fachadas(dir_zona)
    sys.path.insert(0, aqui)
    import empaquetar_fichero                        # la copia en .js (doble clic en simulador.html) con las fachadas
    empaquetar_fichero.zona(dir_zona)
