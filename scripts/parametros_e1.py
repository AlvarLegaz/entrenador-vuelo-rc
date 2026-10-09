"""Entrenador E1: avion de aprendizaje de ala alta con diedro, timon y profundidad (2 servos),
impreso en LW-PLA. Todos los numeros del diseno estan aqui; geometria, masas, VLM y simulador
los leen de este fichero.

Ejes del proyecto: X a lo largo del fuselaje (0 = cara de la bancada del motor, positivo hacia
la cola), Y a la derecha, Z arriba. Unidades: mm y grados.
"""

# ---------------- ala (alta, rectangular, con diedro) ----------------
B = 1200.0              # envergadura
C = 180.0               # cuerda (rectangular): S = 21,6 dm2, alargamiento 6,7
PERFIL = (0.02, 0.4, 0.12)   # NACA 2412: perdida suave, 12 % de espesor para el tubo de 8 mm
X_LE = 175.0            # borde de ataque (con 105 la cola pesaba demasiado: no habia sitio para centrar)
INC = 2.0               # calado respecto al eje del fuselaje (morro arriba +)
# Poliedro: el centro del ala es PLANO (un tubo de carbono recto lo atraviesa entero) y el diedro va en un
# quiebro a QUIEBRO mm del plano de simetria. Con la V en la raiz toda la flexion del ala (3,8 N m por lado a
# 4 g) la tenia que pasar la pieza central impresa; en el quiebro es 5 veces menor y la lleva una llave de
# aluminio de 6 mm doblada, metida en los tubos.
QUIEBRO = 300.0         # mm desde el plano de simetria
DIEDRO = 12.0           # diedro de las puntas (fuera del quiebro). Con solo timon, el diedro es lo que alabea el
                        # avion. VLM: igual efecto que la V de 8 en la raiz (Cl_beta -0,146 frente a -0,138), la
                        # espiral se corrige a la mitad en ~10 s; con 10 grados, en 24 s; con 14, en 7 s
ALA_C_SEMI = 75.0       # la pieza central ALA_C va de -75 a +75 (plana)
Q_SEMI = 40.0           # la pieza del quiebro ALA_Q va de QUIEBRO - 40 a QUIEBRO + 40 a lo largo del ala
# tramos del ala (pieza, desde, hasta, mm desde el plano de simetria), aparte de ALA_C y ALA_Q. Los nombres con
# _xN se imprimen N veces iguales; los _izq se imprimen una vez y otra en espejo (para la semiala derecha)
TRAMOS = [("ALA_I_x2", 75.0, 260.0), ("ALA_E_x4", 340.0, 470.0), ("ALA_E_x4", 470.0, 600.0)]
Z_ALA = 36.0            # el intrados del centro apoya en el lomo del fuselaje (Z = FUS_H/2)
BARRIDO_DIEDRO = (8, 10, 12, 14, 16)   # diedros de las puntas que barre vlm_e1.py

# ---------------- fuselaje impreso ----------------
# seccion rectangular redondeada, constante hasta X_TAPER y luego conica recta hasta la cola
L = 760.0
FUS_W, FUS_H = 60.0, 72.0           # seccion llena (ancho, alto), centrada en Z = 0
X_TAPER = 370.0                      # el asiento del ala (X 175-355) queda en la parte recta
TAIL_W, TAIL_H, TAIL_ZC = 18.0, 22.0, 1.0   # seccion en la cola (X = L)
CORNER = 12.0                        # radio de las esquinas de la seccion llena

# ---------------- cola ----------------
HT_B, HT_C = 420.0, 110.0          # estabilizador: 4,6 dm2 (21 % del ala), atraviesa el fuselaje
HT_XLE = 690.0
HT_Z = -5.0
HT_INC = -1.0                       # calado del estabilizador: con el, vuela a ~9,5 m/s con la profundidad neutra (vlm_e1.py)
ELEV_HINGE = 0.65                   # profundidad: 35 % de la cuerda, detras del final del fuselaje
FIN_XLE = 640.0                     # deriva impresa con el ultimo tramo del fuselaje
FIN_C = 170.0                       # cuerda total (parte fija 120 + timon 50)
FIN_H = 175.0                       # altura sobre el lomo. Con 125 el diedro de 8 deja Cn_beta en 0,006 (casi
                                    # sin estabilidad direccional); con 175, Cn_beta 0,072 y espiral estable
RUD_HINGE = 120.0 / 170.0           # bisagra del timon en X = 760 (el final del fuselaje)

# ---------------- centro de gravedad objetivo ----------------
X_CG = X_LE + 0.33 * C   # 33 % de la cuerda: con la bateria al fondo del morro (X ~ 46) no se llega al 30 %


def fus_seccion(X):
    """(semiancho, semialto, z del centro) del fuselaje en X."""
    if X <= X_TAPER:
        return FUS_W / 2, FUS_H / 2, 0.0
    t = min(1.0, (X - X_TAPER) / (L - X_TAPER))
    return (FUS_W / 2 + t * (TAIL_W - FUS_W) / 2, FUS_H / 2 + t * (TAIL_H - FUS_H) / 2, t * TAIL_ZC)


def fus_lomo(X):
    w, h, zc = fus_seccion(X)
    return zc + h
