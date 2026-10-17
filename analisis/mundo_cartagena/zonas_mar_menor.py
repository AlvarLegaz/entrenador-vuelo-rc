"""Zonas de detalle de La Manga, el Mar Menor y sus islas (2026-10-13): 18 zonas de 3 km PEGADAS en una rejilla
(esquinas en N = 1500 + 3000 k, E = 1000 + 3000 k desde el origen del mundo), las que tienen tierra de La Manga (de
Cabo de Palos al norte del mapa), de las islas y de la orilla sur del Mar Menor. Los simuladores cargan a la vez las
que hay a menos de 2 km del punto de lanzamiento (zonasCerca / zonas_cerca) y entre zonas pegadas el suelo es
continuo, asi que en toda esa zona se vuela con la ortofoto a 0,5 m, el MDT a 5 m y los edificios del Catastro.

Las zonas no van al repositorio (unos 25 MB cada una, 450 MB en total): en otro ordenador se generan con

    python analisis/mundo_cartagena/zonas_mar_menor.py          (unos 40 min: IGN, Catastro y OSM)

Las que ya estan (con zona.json) se saltan. Centros calculados con el terreno del mundo (celdas de tierra al este de
-0,80 de longitud entre 37,625 y 37,83 de latitud), con el desfase de rejilla que necesita menos zonas.
"""
import os, subprocess, sys

ZONAS = [
    ("mm_n03_e23", 37.639931, -0.783407),
    ("mm_n03_e26", 37.639931, -0.749387),
    ("mm_n03_e29", 37.639931, -0.715367),
    ("mm_n03_e32", 37.639931, -0.681346),
    ("mm_n06_e23", 37.667062, -0.783407),
    ("mm_n06_e26", 37.667062, -0.749387),
    ("mm_n06_e29", 37.667062, -0.715367),
    ("mm_n09_e23", 37.694193, -0.783407),
    ("mm_n09_e26", 37.694193, -0.749387),
    ("mm_n12_e23", 37.721325, -0.783407),
    ("mm_n12_e26", 37.721325, -0.749387),
    ("mm_n12_e29", 37.721325, -0.715367),
    ("mm_n15_e26", 37.748456, -0.749387),
    ("mm_n15_e29", 37.748456, -0.715367),
    ("mm_n18_e20", 37.775587, -0.817427),        # la base aerea de San Javier (pista 05R/23L del UAV), anadida en la fase 6
    ("mm_n18_e23", 37.775587, -0.783407),
    ("mm_n18_e26", 37.775587, -0.749387),
    ("mm_n21_e23", 37.802718, -0.783407),
    ("mm_n21_e26", 37.802718, -0.749387),
]

if __name__ == "__main__":
    aqui = os.path.dirname(os.path.abspath(__file__))
    mundo = os.path.join(aqui, "..", "..", "datos", "escenarios", "mundos", "cartagena.js")
    for zid, lat, lon in ZONAS:
        if os.path.isfile(os.path.join(aqui, "..", "..", "datos", "escenarios", "zonas", zid, "zona.json")):
            print(zid, "ya esta"); continue
        print("===", zid, flush=True)
        subprocess.run([sys.executable, os.path.join(aqui, "zona.py"), mundo, zid, "%.6f" % lat, "%.6f" % lon, "3000"], cwd=aqui, check=True)
