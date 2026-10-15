"""Cernicalo XM-7: UAV tactico ligero de vigilancia (diseno propio de este proyecto, no copia de ningun avion real),
de la clase de los de 150 kg que usan los ejercitos para reconocimiento: barquilla con la torreta EO/IR bajo el morro,
ala alta recta, motor de combustion de dos cilindros con helice propulsora detras de la barquilla, doble viga de
cola con estabilizador entre las vigas y una deriva con timon al final de cada una, y tren triciclo fijo para
despegar y aterrizar en pista. Todas las cifras son SUPUESTOS razonados con las de esa clase de aviones.

Solo lo usan analisis/vlm_e1.py (con ENTRENADOR=XM7) y scripts/modelo_aero_xm7.py, que escribe
simulador/aviones/XM7.js:  python scripts/modelo_aero_xm7.py

Ejes del proyecto (los de vlm_e1.py): X a lo largo de la barquilla (0 = punta del morro, positivo hacia la cola),
Y a la derecha, Z arriba. Unidades: mm y grados.
"""

NOMBRE = "Cernícalo XM-7"
DESCRIPCION = ("UAV táctico de vigilancia de 150 kg y 5,5 m de envergadura: ala alta, doble viga de cola, motor de "
               "combustión con hélice propulsora, torreta EO/IR con zoom y cámara térmica bajo el morro y tren triciclo "
               "para despegar y aterrizar en pista. Con piloto automático (estabilizado, crucero, ir a punto y vuelta a "
               "base) y despegue y aterrizaje automáticos.")
MANDOS_TXT = "alerones, profundidad y timones (con piloto automático)"

# ---------------- ala (alta, recta, de perfil grueso; de dos piezas sobre la barquilla) ----------------
B = 5500.0              # envergadura: S = 3,03 m2, alargamiento 10
C = 550.0               # cuerda
PERFIL = (0.04, 0.40, 0.15)   # NACA 4415: mucha sustentacion y espacio para el combustible
X_LE = 1400.0           # borde de ataque a 1,40 m del morro
INC = 2.0               # calado del ala respecto al eje de la barquilla
DIEDRO = 2.0            # algo de diedro: estabilidad en espiral con el piloto automatico desconectado
Z_ALA = 270.0           # el ala apoya en el lomo de la barquilla (Z = 260)
ALERON = dict(bisagra=0.75,                 # alerones exteriores de 25 % de la cuerda
              y0=1500.0, y1=2650.0,
              max_grados=20.0,
              sim_max_grados=None)

# ---------------- motor: dos cilindros opuestos de dos tiempos, 28 CV, helice bipala propulsora de 28" ----------------
DOWNTHRUST = 0.0
Z_MOTOR = 60.0          # eje del motor a media altura del final de la barquilla
X_HELICE = 2330.0       # plano de la helice, detras de la barquilla
D_HELICE_MM = 710.0

# ---------------- barquilla (fuselaje) ----------------
L = 2250.0              # del morro a la bancada del motor
FUS_W, FUS_H = 480.0, 520.0         # seccion maxima, centrada en Z = 0
X_MORRO = 520.0                     # el morro se redondea en los primeros 520 mm
X_TAPER = 1850.0                    # detras del ala la barquilla se estrecha hasta el motor
TAIL_W, TAIL_H, TAIL_ZC = 260.0, 300.0, 60.0


def fus_seccion(X):
    """(semiancho, semialto, z del centro) de la barquilla en X."""
    if X <= X_MORRO:
        t = max(0.0, X / X_MORRO); k = (1 - (1 - t) ** 2) ** 0.5             # morro redondeado (elipse)
        return max(20.0, k * FUS_W / 2), max(20.0, k * FUS_H / 2), -40.0 * (1 - k)
    if X <= X_TAPER:
        return FUS_W / 2, FUS_H / 2, 0.0
    t = min(1.0, (X - X_TAPER) / (L - X_TAPER))
    return (FUS_W / 2 + t * (TAIL_W - FUS_W) / 2, FUS_H / 2 + t * (TAIL_H - FUS_H) / 2, t * TAIL_ZC)


def fus_lomo(X):
    w, h, zc = fus_seccion(X)
    return zc + h


# ---------------- doble viga de cola ----------------
BOOM_Y = 900.0          # cada viga sale del ala a 0,9 m del plano de simetria
BOOM_R = 45.0           # tubos de 90 mm
BOOM_X0 = X_LE + 0.2 * C
BOOM_Z = Z_ALA + 20.0
# estabilizador entre las vigas, con la profundidad entera (brazo de cola ~2,35 m)
HT_B, HT_C = 2 * BOOM_Y, 190.0      # 0,34 m2 (11 % del ala): fuera de la estela del ala, la cola en H es muy eficaz
HT_XLE = X_LE + 0.25 * C + 2350.0 - 0.25 * HT_C
HT_Z = BOOM_Z + 380.0               # en lo alto de las derivas (cola en H invertida, fuera de la estela)
HT_INC = 0.0                        # lo calcula modelo_aero_xm7.py
ELEV_HINGE = 0.62
BOOM_X1 = HT_XLE + HT_C + 40.0      # las vigas acaban tras el borde de fuga
# una deriva con timon al final de cada viga, desde la viga hasta el estabilizador y algo por encima
FIN_Y = BOOM_Y
FIN_Z0 = BOOM_Z - 160.0             # la deriva baja un poco por debajo de la viga (protege la helice en la rotacion)
FIN_C, FIN_H = 420.0, 640.0         # 0,27 m2 cada una
FIN_XLE = HT_XLE - 60.0
RUD_HINGE = 0.62

# ---------------- tren triciclo fijo ----------------
TREN_MORRO_X = 380.0                # rueda de morro dirigible
TREN_PPAL_X = 1780.0                # principales, ~20 cm detras del CG
TREN_PPAL_Y = 650.0
TREN_Z = -FUS_H / 2 - 430.0         # eje de las ruedas
R_RUEDA = 140.0

# ---------------- masas (kg, X, Y, Z en mm); peso al despegue: 150 kg ----------------
MASA_TOTAL = 150000.0               # en g, como en los demas aviones
MASAS = [
    ("motor de 28 CV con escape y encendido", 17000.0, 2120.0, 0.0, Z_MOTOR),
    ("hélice bipala de 28\" y buje", 2200.0, X_HELICE, 0.0, Z_MOTOR),
    ("torreta EO/IR (cámara diurna con zoom y térmica)", 14000.0, 230.0, 0.0, -290.0),
    ("piloto automático, GPS e inercial", 4000.0, 450.0, 0.0, 20.0),
    ("enlace de datos y antenas", 5000.0, 550.0, 0.0, 120.0),
    ("generador, batería y distribución", 7500.0, 1150.0, 0.0, -80.0),
    ("servos de alerones", 1600.0, X_LE + 0.8 * C, 0.0, Z_ALA),
    ("servos de profundidad y timones", 1600.0, HT_XLE, 0.0, HT_Z),
    ("tren de aterrizaje y ruedas", 9500.0, 1350.0, 0.0, TREN_Z + 200.0),
    ("combustible (45 l)", 33000.0, X_LE + 0.30 * C, 0.0, Z_ALA - 30.0),
]
BATERIA = ("carga útil adicional y lastre", 4000.0, 0.0, -120.0)   # se coloca para dejar el CG en X_CG
BAT_X_MIN, BAT_X_MAX = 300.0, 1700.0
COMBUSTIBLE_L = 45.0
# estructura repartida (fibra de carbono y vidrio): se escala para que el total sea MASA_TOTAL
REPARTIDAS = dict(ala=24000.0, fuselaje=16000.0, vigas=6000.0, estab=4000.0, deriva=3000.0)

# ---------------- centro de gravedad objetivo ----------------
X_CG = X_LE + 0.35 * C   # con la cola en H alta (sin apenas rebufo del ala) el punto neutro queda muy atras
