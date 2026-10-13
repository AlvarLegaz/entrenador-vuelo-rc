"""Germán 1: avion de foam de ala alta, de 4 canales (alerones, profundidad, timon y motor), con tren fijo de dos
ruedas y patin de cola. NO es un diseno de este proyecto ni tiene piezas impresas: es el modelo de vuelo de un avion
ya construido, a partir de sus medidas y de una foto (2026-10-13). Solo lo usan analisis/vlm_e1.py (con
ENTRENADOR=G1) y scripts/modelo_aero_g1.py, que escribe simulador/aviones/G1.js.

Medidas dadas por el usuario: envergadura 720 mm, cuerda 150 mm, helice de 210 mm (8"), motor A2208/14T 1400 KV,
distancia del centro del ala al centro del estabilizador 400 mm y peso en vuelo 600 g. Todo lo demas sale de la
foto o es una estimacion, y esta marcado (FOTO / SUPUESTO). Cuando se midan en el avion, se cambian aqui y se vuelve
a generar: python scripts/modelo_aero_g1.py

Ejes del proyecto (los de vlm_e1.py): X a lo largo del fuselaje (0 = cara delantera del morro, donde va el motor,
positivo hacia la cola), Y a la derecha, Z arriba. Unidades: mm y grados.
"""

NOMBRE = "Germán 1"
DESCRIPCION = ("Avión de foam de ala alta y 4 canales (alerones, profundidad, timón y motor), con tren fijo. "
               "Hecho a partir de las medidas del avión real; las flechas ← → mueven los alerones y A / D el timón.")
MANDOS_TXT = "alerones, profundidad y timón"

# ---------------- ala (alta, rectangular, sujeta con gomas) ----------------
B = 720.0               # envergadura (medida): S = 10,8 dm2, alargamiento 4,8
C = 150.0               # cuerda (medida)
PERFIL = (0.03, 0.30, 0.12)   # SUPUESTO: ala de foam plegada (tipo FT) ~ curvatura 3 %, 12 % de espesor (en la foto, ~18 mm)
X_LE = 160.0            # FOTO: borde de ataque a ~160 mm del morro
INC = 2.0               # SUPUESTO: calado del asiento del ala respecto al eje del fuselaje
DIEDRO = 0.0            # FOTO: el ala se ve plana
Z_ALA = 45.0            # el intrados apoya en el asiento, por encima del lomo del fuselaje (Z = 35)
# alerones interiores (FOTO): tiras desde el fuselaje hasta casi media semiala, con el horn en el extrados
ALERON = dict(bisagra=0.73,                 # FOTO/SUPUESTO: ~40 mm de cuerda de aleron
              y0=30.0, y1=170.0,            # desde y hasta (mm desde el plano de simetria)
              max_grados=15.0,              # SUPUESTO: recorrido mecanico tipico
              sim_max_grados=None)          # con teclado: lo calcula modelo_aero_g1.py (~150 grados/s de alabeo)

# ---------------- motor ----------------
DOWNTHRUST = 0.0        # SUPUESTO: motor recto
Z_MOTOR = 5.0           # FOTO: el eje del motor va a media altura del morro

# ---------------- fuselaje (caja de foam) ----------------
# seccion rectangular, constante hasta X_TAPER; detras del ala el lomo sigue recto y la panza sube hasta la cola
L = 690.0
FUS_W, FUS_H = 50.0, 70.0           # SUPUESTO/FOTO: caja de 50 x 70 mm, centrada en Z = 0
X_TAPER = 330.0
TAIL_W, TAIL_H, TAIL_ZC = 20.0, 30.0, 20.0   # en la cola: lomo en Z = 35 (recto), panza en Z = 5

# ---------------- cola ----------------
# distancia del centro del ala al centro del estabilizador: 400 mm (medida). Estabilizador trapezoidal con la
# profundidad entera (FOTO): raiz 110, punta 60 -> cuerda media 85; el VLM lo toma rectangular con la cuerda media
HT_B, HT_C = 340.0, 85.0            # FOTO: 2,9 dm2 (27 % del ala)
HT_C_RAIZ, HT_C_PUNTA = 110.0, 60.0  # para la malla del visor
HT_XLE = X_LE + 0.5 * C + 400.0 - 0.5 * HT_C   # centro del estabilizador a 400 mm del centro del ala
HT_Z = 5.0                          # FOTO: el estabilizador va bajo la cola
HT_INC = 0.0                        # lo calcula modelo_aero_g1.py (vuela a la velocidad de crucero con la profundidad neutra)
ELEV_HINGE = 0.65                   # FOTO: banda negra de ~30 mm al borde de fuga
# deriva en flecha con timon (FOTO): raiz 140, punta 50, altura 130 -> cuerda media 95 para el VLM
FIN_C, FIN_H = 95.0, 130.0
FIN_C_RAIZ, FIN_C_PUNTA = 140.0, 50.0
FIN_XLE = HT_XLE + HT_C + 10.0 - FIN_C       # el borde de fuga del timon, 10 mm detras del de la profundidad
RUD_HINGE = 0.70                    # FOTO: banda negra de ~30 mm

# ---------------- masas (g, X, Y, Z en mm); peso total medido: 600 g ----------------
# SUPUESTO salvo el total. La bateria se coloca sola (modelo_aero_g1.py) para dejar el CG en X_CG, entre BAT_X_MIN y
# BAT_X_MAX (el hueco bajo la tapa de delante del ala); si no llega, el CG se queda donde caiga y lo dice.
MASA_TOTAL = 600.0
MASAS = [
    ("motor A2208/14T", 48.0, -18.0, 0.0, Z_MOTOR),
    ("hélice 8x4 y adaptador", 12.0, -38.0, 0.0, Z_MOTOR),
    ("variador 20-30 A", 25.0, 50.0, 0.0, -10.0),
    ("receptor", 8.0, 200.0, 0.0, -15.0),
    ("servo profundidad", 9.0, 260.0, 12.0, -10.0),
    ("servo timón", 9.0, 260.0, -12.0, -10.0),
    ("servo alerón izq.", 9.0, 215.0, -60.0, 50.0),
    ("servo alerón der.", 9.0, 215.0, 60.0, 50.0),
    ("tren de aterrizaje y ruedas", 36.0, 150.0, 0.0, -80.0),
    ("patín de cola", 3.0, 680.0, 0.0, 0.0),
    ("varillas y horns", 10.0, 450.0, 0.0, 0.0),
]
BATERIA = ("batería 3S 1300 mAh", 105.0, 0.0, -5.0)  # SUPUESTO (lo habitual con este motor); (nombre, g, Y, Z); la X la pone el script
BATERIA_WH = 11.1 * 1.3
BAT_X_MIN, BAT_X_MAX = 35.0, 190.0
# piezas repartidas (foam, cinta, pegamento): ala, fuselaje y cola; se escalan para que el total sea MASA_TOTAL
REPARTIDAS = dict(ala=150.0, fuselaje=105.0, estab=20.0, deriva=10.0)

# ---------------- centro de gravedad objetivo ----------------
X_CG = X_LE + 0.28 * C   # SUPUESTO: 28 % de la cuerda (entre el 25 y el 30 % habitual en un entrenador)


def fus_seccion(X):
    """(semiancho, semialto, z del centro) del fuselaje en X."""
    if X <= X_TAPER:
        return FUS_W / 2, FUS_H / 2, 0.0
    t = min(1.0, (X - X_TAPER) / (L - X_TAPER))
    return (FUS_W / 2 + t * (TAIL_W - FUS_W) / 2, FUS_H / 2 + t * (TAIL_H - FUS_H) / 2, t * TAIL_ZC)


def fus_lomo(X):
    w, h, zc = fus_seccion(X)
    return zc + h
