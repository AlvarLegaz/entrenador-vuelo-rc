"""Grajo MX-2: mini UAV de ala fija lanzado a mano, como el AeroVironment RQ-11B Raven que usa el Ejercito de Tierra
(pedido del usuario el 2026-10-16 para que sus alumnos del Ejercito aprendan su mantenimiento; en la app no se usan
marcas). Lo mas parecido posible al real con lo que es publico (fichas de la USAF, el fabricante y prensa
especializada), marcado REAL; lo que no es publico es un SUPUESTO razonado y esta marcado.

REAL: envergadura 1,37 m, longitud 0,91 m, 1,9 kg (2,2 con el morro de camara orientable), motor electrico de la
clase del Aveox 27/26/7 con helice bipala PROPULSORA arriba y detras del fuselaje, ala alta con las puntas levantadas
(poliedro), botalon de cola con estabilizador y deriva, 32-81 km/h (crucero ~42 km/h), 30-150 m sobre el suelo,
60-90 min con bateria recargable, 10 km, lanzamiento a mano y toma en perdida profunda (~45 grados) en un punto.
SUPUESTO: cuerda y perfil del ala, quiebro y angulo del poliedro, cola, bateria (Li-ion 4S de 5,2 Ah: los 60-90 min
con ~60 W), helice de 9", reparto de masas y que no lleva alerones (timon y profundidad, como un velero de vuelo libre).

Solo lo usan analisis/vlm_e1.py (con ENTRENADOR=GRAJO) y scripts/modelo_aero_grajo.py, que escribe
simulador/aviones/GRAJO.js:  python scripts/modelo_aero_grajo.py

Ejes del proyecto (los de vlm_e1.py): X a lo largo del fuselaje (0 = punta del morro, positivo hacia la cola), Y a la
derecha, Z arriba. Unidades: mm y grados.
"""

NOMBRE = "Grajo MX-2"
DESCRIPCION = ("Mini UAV de reconocimiento de 1,9 kg y 1,37 m de envergadura que se lanza a mano: ala alta en "
               "poliedro, hélice propulsora y botalón de cola, cámaras de día e infrarrojas en el morro (fijas o "
               "en torreta orientable), piloto automático y toma en pérdida profunda. Se monta y desmonta por piezas.")
MANDOS_TXT = "timón y profundidad (sin alerones: el poliedro del ala hace alabear con el timón)"

# ---------------- ala (alta, sobre el fuselaje; tramo central plano y puntas levantadas) ----------------
B = 1370.0              # REAL: envergadura 4,5 ft
C = 215.0               # SUPUESTO: S = 0,295 m2, alargamiento 6,4; carga alar ~64 N/m2
PERFIL = (0.035, 0.35, 0.10)   # SUPUESTO: perfil fino curvado de velero (Re ~1,5e5)
X_LE = 285.0            # SUPUESTO: borde de ataque a 28,5 cm del morro (el motor, justo detras del borde de fuga)
INC = 3.0               # SUPUESTO: calado del ala
QUIEBRO = 330.0         # SUPUESTO: el tramo central (66 cm) es plano; las puntas, desmontables, se levantan
DIEDRO = 12.0           # SUPUESTO: poliedro de las puntas (con solo timon hace falta bastante)
Z_ALA = 50.0            # el ala apoya en el lomo del fuselaje (Z = 45)
ALERON = None           # SUPUESTO: sin alerones (timon y profundidad)

# ---------------- motor y helice propulsora (arriba y detras del fuselaje) ----------------
DOWNTHRUST = 0.0
Z_MOTOR = 95.0          # sobre un pilono, por encima del botalon
X_HELICE = 590.0
D_HELICE_MM = 230.0     # SUPUESTO: 9"

# ---------------- fuselaje (vaina con el morro de camaras) y botalon de cola ----------------
L = 910.0               # REAL: 3 ft de punta a punta
L_VAINA = 560.0         # SUPUESTO: la vaina acaba bajo el motor
FUS_W, FUS_H = 80.0, 90.0           # SUPUESTO: seccion de la vaina, centrada en Z = 0
X_MORRO = 110.0                     # el morro (de camaras, desmontable) se redondea en los primeros 110 mm
X_TAPER = 470.0                     # desde aqui la vaina se estrecha hacia el botalon
BOOM_R, BOOM_ZC = 9.0, -25.0        # SUPUESTO: botalon de 18 mm que sale de la parte baja de la vaina


def fus_seccion(X):
    """(semiancho, semialto, z del centro) del fuselaje (vaina y botalon) en X."""
    if X <= X_MORRO:
        t = max(0.0, X / X_MORRO); k = (1 - (1 - t) ** 2) ** 0.5
        return max(6.0, k * FUS_W / 2), max(6.0, k * FUS_H / 2), -10.0 * (1 - k)
    if X <= X_TAPER:
        return FUS_W / 2, FUS_H / 2, 0.0
    if X <= L_VAINA:
        t = (X - X_TAPER) / (L_VAINA - X_TAPER)
        return FUS_W / 2 + t * (BOOM_R * 1.6 - FUS_W / 2), FUS_H / 2 + t * (BOOM_R * 1.6 - FUS_H / 2), t * BOOM_ZC
    return BOOM_R, BOOM_R, BOOM_ZC


def fus_lomo(X):
    w, h, zc = fus_seccion(X)
    return zc + h


# ---------------- cola en el botalon: estabilizador con la profundidad entera y deriva con timon ----------------
HT_B, HT_C = 420.0, 115.0           # SUPUESTO: 4,8 dm2 (16 % del ala)
HT_XLE = L - HT_C - 10.0
HT_Z = BOOM_ZC + BOOM_R + 2.0       # encima del botalon
HT_INC = 0.0                        # lo calcula modelo_aero_grajo.py
ELEV_HINGE = 0.60
FIN_C, FIN_H = 125.0, 150.0         # SUPUESTO: 1,9 dm2, con el timon grande (es el que hace virar)
FIN_XLE = L - FIN_C
RUD_HINGE = 0.55

# ---------------- masas (g, X, Y, Z en mm); peso en vuelo: 1,9 kg (REAL) ----------------
MASA_TOTAL = 1900.0
MASAS = [
    ("motor sin escobillas (clase Aveox 27/26/7)", 110.0, 565.0, 0.0, Z_MOTOR),
    ("hélice bipala de 9\" y buje", 15.0, X_HELICE, 0.0, Z_MOTOR),
    ("pilono del motor", 20.0, 545.0, 0.0, 70.0),
    ("variador", 25.0, 430.0, 0.0, 30.0),
    ("piloto automático, GPS e inercial", 45.0, 300.0, 0.0, 20.0),
    ("enlace de datos y antena", 90.0, 380.0, 0.0, 0.0),
    ("morro de cámaras (color e infrarroja, frontal y lateral)", 130.0, 50.0, 0.0, -10.0),
    ("servo de profundidad", 12.0, 430.0, 12.0, -20.0),
    ("servo de timón", 12.0, 430.0, -12.0, -20.0),
    ("varillas de mando", 15.0, 700.0, 0.0, -25.0),
]
BATERIA = ("batería Li-ion 4S 5200 mAh", 420.0, 0.0, -15.0)   # SUPUESTO; la X la pone el script (dentro de la vaina)
BATERIA_DATOS = dict(quimica="liion", celdas=4, capacidad_mAh=5200, R_ohm=0.06, masa_kg=0.42)
BAT_X_MIN, BAT_X_MAX = 120.0, 420.0
# estructura repartida (espuma con piel de kevlar/vidrio): se escala para que el total sea MASA_TOTAL
REPARTIDAS = dict(ala=330.0, fuselaje=260.0, botalon=70.0, estab=40.0, deriva=30.0)

# ---------------- centro de gravedad objetivo ----------------
X_CG = X_LE + 0.30 * C   # SUPUESTO: 30 % de la cuerda
