"""Entrenador E2: la variante del E1 con ALERONES y profundidad (2 canales) y la deriva fija, sin timon.
Mismo fuselaje, misma cola horizontal y misma ala que el E1; cambian el diedro (menor, porque ahora
alabean los alerones), los alerones con sus dos servos en el ala y la deriva, mas pequena y con el canto
trasero cerrado. Todo lo que no se redefine aqui vale lo del E1 (parametros_e1.py).

Se genera con la variable de entorno ENTRENADOR=E2 (ver avion.py).
"""
from parametros_e1 import *          # noqa: F401,F403  (fuselaje, ala, cola, CG objetivo, fus_seccion, fus_lomo)

NOMBRE = "Entrenador E2"
DESCRIPCION = ("Entrenador de ala alta con alerones y profundidad (2 canales) y deriva fija. "
               "Impreso en LW-PLA. Las flechas izquierda y derecha mueven los alerones.")
MANDOS_TXT = "alerones y profundidad"

# ---------------- ala ----------------
QUIEBRO = 240.0         # poliedro: centro plano y quiebro justo antes del aleron (que va entero en el panel exterior)
DIEDRO = 7.0            # diedro de las puntas. VLM (poliedro, deriva 120 x 145): con 6 la espiral dobla en ~60 s,
                        # con 7 se corrige a la mitad en ~50 s (casi neutra, como debe ser un avion de alerones),
                        # con 8 en ~20 s. La V de 2,5 en la raiz doblaba en ~8 s; la de 5, casi neutra, pero con
                        # toda la flexion del ala pasando por la pieza central impresa
# alerones: 25 % de la cuerda, de 280 a 570 mm (fuera de la pieza del quiebro, que va de 200 a 280)
ALERON = dict(bisagra=0.75,                 # bisagra al 75 % de la cuerda: nudillos con pasador de carbono de 2 mm
              y0=280.0, y1=570.0,           # desde y hasta (mm desde el plano de simetria)
              max_grados=15.0,              # recorrido mecanico de cada aleron (horn y varilla)
              sim_max_grados=5.0,           # recorrido en el simulador: con teclado la palanca va siempre a tope y con 15
                                            # grados 1 s de aleron da la vuelta al avion (Cl_da 0,47/rad: ~240 grados/s);
                                            # en el avion real se ajusta con el dual-rate de la emisora
              tramos=[("ALERON_A_x2", 280.0, 420.0), ("ALERON_B_x2", 420.0, 570.0)],   # piezas (se unen con varilla de 2 mm)
              servo_y=350.0,                # un servo de 9 g por aleron, de costado en el intrados, delante del larguero
                                            # trasero, en el centro del tramo 280-420: asi la pieza vale para los dos lados
              servo_largo=24.0, servo_ancho=25.0, servo_fondo=12.5)
# tramos del ala (pieza, desde, hasta, mm desde el plano de simetria), aparte de ALA_C (-75 a 75) y ALA_Q
# (200 a 280). ALA_E2 lleva el aleron solo hasta 570: la derecha se imprime en espejo
TRAMOS = [("ALA_I_x2", 75.0, 200.0), ("ALA_E1_x2", 280.0, 420.0), ("ALA_E2_izq", 420.0, 600.0)]

# centro de gravedad: el E2 (y el E3) se quedan al 33 %: con los servos de los alerones en el ala la bateria
# tiene sitio de sobra (el E1 va al 35 %)
X_CG = X_LE + 0.33 * C

# ---------------- cola ----------------
HT_INC = -0.4           # calado del estabilizador: vuela a ~9,5 m/s con la profundidad neutra (vlm_e1.py con la masa
                        # y las inercias de masas_e1.py: 0,762 kg, Ixx 0,0373, Izz 0,0642 -> -0,38). El VLM del E2 lleva
                        # un borde de panel mas en el ala (la bisagra del aleron) y eso mueve el punto neutro unos mm
RUD_HINGE = 1.0         # sin timon: la deriva es solo la parte fija de F5, con el borde de fuga afinado y cerrado
FIN_C = 120.0           # cuerda de la deriva: de FIN_XLE (640) al final del fuselaje (760)
FIN_H = 145.0           # altura sobre el lomo. Con poco diedro hace falta MENOS deriva para que la espiral no se abra:
                        # Cn_beta 0,033 (con 175 de alto, 0,066, y la espiral dobla en 12 s con 4 de diedro)

BARRIDO_DIEDRO = (4, 5, 6, 7, 8, 9)

# simulador: clase de fisica propia (alerones en vez de timon), en scripts/clase_e2.js
CLASE_JS = ("ModeloE2", "clase_e2.js")
