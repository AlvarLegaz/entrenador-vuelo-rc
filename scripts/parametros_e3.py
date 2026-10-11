"""Entrenador E3: el E2 (alerones y profundidad, deriva fija) con el ala TOTALMENTE PLANA, sin diedro.
Todo lo que no se redefine aqui vale lo del E2 (parametros_e2.py), y por tanto lo del E1.

Las piezas son las del E2 salvo ALA_Q, que queda recta (la llave de aluminio del quiebro va sin doblar). Sin
diedro el avion no tiende a nivelar las alas: es el paso siguiente al E2, para quien ya vuela con alerones.

Se genera con la variable de entorno ENTRENADOR=E3 (ver avion.py).
"""
from parametros_e2 import *          # noqa: F401,F403

NOMBRE = "Entrenador E3"
DESCRIPCION = ("Entrenador de ala alta con alerones y profundidad (2 canales), deriva fija y ala totalmente plana, "
               "sin diedro. Impreso en LW-PLA. No nivela las alas solo: hay que llevarlo con los alerones.")
DIEDRO = 0.0            # ala plana (el quiebro de la pieza ALA_Q queda a 0 grados)
BARRIDO_DIEDRO = (0, 1, 2, 3)

# Fuselaje (F1 a F5) con pared de 5 mm (peticion del usuario, 2026-10-11: la de 1,6 mm le parecia demasiado fina para
# imprimir). Crece hacia dentro: la forma exterior y los encajes son los mismos; sin larguerillos ni cuadernas (sobran
# con esta pared y en la cola no caben). Las fundas de las transmisiones pasan por tuneles en la pared de la cola
PARED_FUS = 5.0
