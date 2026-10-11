"""Tandem T1: avion de dos alas en tandem (delantera baja, trasera alta con elevones y winglets), impreso en
PLA NORMAL, con el mismo motor y bateria que los entrenadores E1/E2 (SunnySky X2212 KV980, APC 9x4,7, 3S 1300).

La geometria la genera stl/T1/scripts/geom.py (es el diseno que trajo el usuario: 600 mm de envergadura,
cuerdas 85 y 95 mm, NACA 3407, fuselaje tubular de 50 mm). Aqui solo estan los numeros que necesitan masas,
VLM y simulador, tomados de ese fichero para no duplicarlos, mas las decisiones que no estan en la geometria
(material, componentes, centro de gravedad, mandos).

Ejes del proyecto: X a lo largo del fuselaje (0 = cara de la placa del motor, positivo hacia la cola), Y a la
derecha, Z arriba. Unidades: mm y grados. Se usa con la variable de entorno ENTRENADOR=T1 (ver avion.py).
"""
import os, sys

RAIZ = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
DIR_T1 = os.path.join(RAIZ, "stl", "T1", "scripts")       # generador y su salida (out/info.json, out/glob_meshes.pkl)
sys.path.insert(0, DIR_T1)
import geom as GT                                          # noqa: E402  (define las cotas; al importarlo no genera nada)

TANDEM = True
NOMBRE = "Tándem T1"
DESCRIPCION = ("Avión tándem: ala delantera baja y ala trasera alta con elevones y dos derivas junto al fuselaje, sin cola. Impreso en PLA "
               "normal, con el motor y la batería del E1. Las flechas izquierda y derecha alabean con los elevones.")
MANDOS_TXT = "elevones (profundidad y alabeo en el ala trasera)"

# ---------------- alas ----------------
B = GT.B                        # envergadura de las dos alas (600)
C_F, C_R = GT.C_F, GT.C_R       # cuerdas delantera y trasera (85, 95)
C = 0.5 * (C_F + C_R)           # cuerda de referencia de los coeficientes de momento (90). S = B (C_F + C_R)
X_LE_F, X_LE_R = GT.X_LE_F, GT.X_LE_R          # bordes de ataque (110, 365)
Z_LE_F, Z_LE_R = GT.Z_LE_F, GT.Z_LE_R          # altura de los bordes de ataque: la delantera bajo el tubo, la trasera encima
INC_F, INC_R = GT.INC_F, GT.INC_R              # calados (+2, 0): decalaje de 2 para que la delantera entre antes en perdida
WASHOUT = -GT.WASHOUT                          # torsion del ala delantera: 0 en la raiz, -1,5 en la punta
PERFIL = (0.03, 0.4, 0.07)                     # NACA 3407 en las dos alas
X_LE = X_LE_F                                  # referencia del simulador para dar el CG (borde de ataque delantero)
# elevones: 25 % de la cuerda del ala trasera, de 26 a 297 mm del plano de simetria (dos piezas por lado)
ELEVON = dict(bisagra=GT.HINGE, y0=26.0, y1=26.0 + 2 * (297 - 26) / 2,
              max_grados=15.0,                 # recorrido mecanico de cada elevon (varilla de 0,8 y horn)
              sim_prof_grados=10.0,            # recorrido de profundidad en el simulador (palanca a tope)
              sim_aleron_grados=2.5)           # recorrido de alabeo en el simulador (con teclado va siempre a tope): con
                                               # Ixx 0,0057, Cl_da 0,34/rad y sin derivas en las puntas que frenen el alabeo,
                                               # 4 grados ponian el avion a 120 de alabeo en 1 s de palanca; con 2,5, a unos
                                               # 70. En el avion real, dual-rate y exponencial en la emisora
# derivas ("winglets" en los planos): dos placas de 2 mm sobre el ala trasera, junto al fuselaje, hacia arriba, con
# el borde de fuga alineado con el del ala (en el final del fuselaje). Van a +-20 mm del plano de simetria: en el
# tramo del ala de cuerda entera, por dentro del arranque de los elevones (26 mm)
WINGLET = dict(c_raiz=80.0, c_punta=50.0, h=75.0, x_te=X_LE_R + C_R, y=20.0, z0=Z_LE_R + 0.06 * C_R)

# ---------------- fuselaje (tubo de 50 mm) ----------------
L = GT.L                        # 480
FUS_W = FUS_H = 2 * GT.R        # 50: las correcciones empiricas del fuselaje usan ancho y alto
Z_ALA = Z_LE_R                  # (no se usa en el tandem: fus_Cl_beta suma las dos alas)
DOWNTHRUST = 0.0                # la placa del motor es perpendicular al tubo


def fus_seccion(X):
    """(semiancho, semialto, z del centro) del fuselaje en X."""
    r = GT.r_out(min(max(X, 0.0), L))
    return r, r, 0.0


def fus_lomo(X):
    return fus_seccion(X)[0]


# ---------------- centro de gravedad objetivo ----------------
# El VLM (analisis/vlm_t1.py) da el punto neutro en X 235 mm (el plano original decia 234); se deja un margen
# estatico del 15 % de la cuerda media (13,5 mm), como el diseno original (234 -> 220). masas_t1.py coloca la
# bateria donde haga falta para ponerlo aqui (y dice si cabe).
X_CG = 221.0

# simulador: clase de fisica propia (elevones: profundidad y alabeo con las mismas superficies)
CLASE_JS = ("ModeloT1", "clase_t1.js")
