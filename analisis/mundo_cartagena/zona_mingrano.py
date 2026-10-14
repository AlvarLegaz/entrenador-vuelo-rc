"""Zona de detalle de El Mingrano (Fuente Alamo, Campo de Cartagena) para el trabajo de inspeccion de paneles
fotovoltaicos del modo Operaciones (2026-10-14): cuadrado de 2 km centrado al norte del caserio, ortofoto PNOA a 0,5 m,
MDT a 5 m, edificios del Catastro y arboles de la ortofoto. Los paneles son del simulador (escenarios.js, op_paneles):
en la ortofoto no hay ninguna planta fotovoltaica.

    python analisis/mundo_cartagena/zona_mingrano.py      (unos 5 min; la zona no va al repositorio)
"""
import os, subprocess, sys

ID, LAT, LON, LADO = "mingrano", 37.6415, -1.2170, 2000     # al norte del caserio de El Mingrano (37,6387 N, 1,2178 O)

if __name__ == "__main__":
    aqui = os.path.dirname(os.path.abspath(__file__))
    mundo = os.path.join(aqui, "..", "..", "simulador", "mundos", "cartagena.js")
    subprocess.run([sys.executable, os.path.join(aqui, "zona.py"), mundo, ID, "%.6f" % LAT, "%.6f" % LON, str(LADO)], cwd=aqui, check=True)
