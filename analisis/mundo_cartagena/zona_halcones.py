"""Zona de detalle del campo de vuelo del Club Deportivo de Aeromodelismo "Los Halcones de la Rambla" (El Jimenado,
Torre-Pacheco) a la maxima calidad de las fuentes abiertas (2026-10-13): cuadrado de 2 km centrado en el campo,
ortofoto PNOA a 0,25 m (ZONA_PX=2048), MDT a 5 m, edificios del Catastro y arboles de la ortofoto. Coordenadas del
campo y de la pista (asfalto de 175 x 18 m pintada, 230 x 25 m reales, orientada 250-70 grados) de la web del club,
http://www.cdaloshalcones.es/?page_id=1791. El punto de despegue esta destacado en el mapa de salida
(datos/escenarios.js, "destacados" del vuelo libre en Cartagena).

    python analisis/mundo_cartagena/zona_halcones.py      (unos 5 min; la zona no va al repositorio)
"""
import os, subprocess, sys

ID, LAT, LON, LADO = "halcones_rambla", 37.761361, -1.012611, 2000     # 37 45' 40,9" N, 1 00' 45,4" O

if __name__ == "__main__":
    aqui = os.path.dirname(os.path.abspath(__file__))
    mundo = os.path.join(aqui, "..", "..", "datos", "escenarios", "mundos", "cartagena.js")
    subprocess.run([sys.executable, os.path.join(aqui, "zona.py"), mundo, ID, "%.6f" % LAT, "%.6f" % LON, str(LADO)], cwd=aqui,
                   env=dict(os.environ, ZONA_PX="2048"), check=True)
