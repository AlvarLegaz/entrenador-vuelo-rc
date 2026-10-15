"""Entrenador E3: el E2 (alerones y profundidad, deriva fija) con el ala TOTALMENTE PLANA, sin diedro.
Todo lo que no se redefine aqui vale lo del E2 (parametros_e2.py), y por tanto lo del E1.

Las piezas son las del E2 salvo ALA_Q, que queda recta (la llave de aluminio del quiebro va sin doblar), y F5, con
la deriva mas alta (195 en vez de 145, ver abajo). Sin diedro el avion no tiende a nivelar las alas: es el paso
siguiente al E2, para quien ya vuela con alerones.

Se genera con la variable de entorno ENTRENADOR=E3 (ver avion.py).
"""
from parametros_e2 import *          # noqa: F401,F403

NOMBRE = "Entrenador 1"            # en el simulador (su id sigue siendo E3)
DESCRIPCION = ("Entrenador de ala alta con alerones y profundidad (2 canales), deriva fija y ala totalmente plana, "
               "sin diedro. Impreso en LW-PLA. No nivela las alas solo: hay que llevarlo con los alerones.")
DIEDRO = 0.0            # ala plana (el quiebro de la pieza ALA_Q queda a 0 grados)
BARRIDO_DIEDRO = (0, 1, 2, 3)

# ---------------- deriva (solo el E3) ----------------
# El E2 lleva la deriva pequena A PROPOSITO (120 x 145): con 7 de diedro, mas deriva abre la espiral. El E3 no tiene
# diedro, asi que su espiral la manda el ala plana y no la deriva: con la del E2 dobla en ~4 s y con cualquier deriva
# del barrido tambien (Cl_beta x Cn_r - Cn_beta x Cl_r < 0 siempre; para doblar en >= 20 s haria falta diedro). Lo que
# si cambia es el balanceo holandes ("da bandazos"): con 120 x 145 Cn_beta era 0,045 y Cn_r -0,049 (el Poli-1, 0,104
# y -0,19). Barrido con vlm_e1.py (alfa 3, 9,5 m/s, 1,227 kg, Ixx 0,0398, Izz 0,0870; espiral en todos ~+0,18-0,19 1/s):
#     cuerda x alto   Cn_beta   Cn_r     Cl_beta   holandes Hz  amort.   ancho de F5 al imprimir   deriva
#     120 x 145       0,045    -0,049   -0,019    0,47         0,156    179 mm                    10 g
#     120 x 175       0,067    -0,067   -0,025    0,56         0,160
#     120 x 185       0,075    -0,073   -0,027    0,59         0,161    219 mm                    13 g
#     120 x 195       0,083    -0,079   -0,030    0,62         0,163    229 mm                    14 g
#     150 x 185       0,082    -0,083   -0,028    0,62         0,170    218 mm                    16 g
#     170 x 175       0,076    -0,081   -0,026    0,60         0,173    207 mm (como el E1)       18 g
#     170 x 185       0,086    -0,090   -0,028    0,63         0,176    217 mm                    19 g
# Las cuerdas de mas de 120 pasan por detras del final del fuselaje (geom_e1.fin_fixed las recorta por encima de la
# profundidad, como el timon del E1) y casi no ganan: unos 5-8 g mas en la punta de la cola, que con el CG al 33 % y
# la bateria ya casi en la bancada (X 59, el minimo es ~44 con una 3S de 72 mm) obligarian a poner plomo en el morro.
# Se queda la cuerda de 120 (toda la deriva sigue en F5, de X 640 a 760) y 195 de alto: Cn_beta x1,85, Cn_r x1,6, el
# holandes decae a la mitad en ~1,1 s en vez de ~1,5 s y F5 sale de 229 mm de ancho, lo mismo que ESTAB (230), la pieza
# mas grande del proyecto. Cuesta +3,5 g en la cola: la bateria va 14 mm mas adelante, de X 59 a X 45 (masas_e1.py la
# coloca sola; 1.230 g, Ixx 0,0400, Izz 0,0884). El calado del estabilizador no cambia (el VLM pide -2,44 para 9,5 m/s,
# como antes; se sigue con -0,9 y compensa a ~11 m/s, decision de cuando se puso la pared de 5 mm)
FIN_C = 120.0
FIN_H = 195.0

# Fuselaje (F1 a F5) con pared de 5 mm (peticion del usuario, 2026-10-11: la de 1,6 mm le parecia demasiado fina para
# imprimir). Crece hacia dentro: la forma exterior y los encajes son los mismos; sin larguerillos ni cuadernas (sobran
# con esta pared y en la cola no caben). Las fundas de las transmisiones pasan por tuneles en la pared de la cola
PARED_FUS = 5.0
