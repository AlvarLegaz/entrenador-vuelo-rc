"""Exporta el modelo de vuelo del Cernicalo XM-7 al simulador (simulador/aviones/XM7.js). Es un UAV tactico de diseno
propio (scripts/parametros_xm7.py, todo SUPUESTO razonado con los de su clase), sin piezas impresas.

    python scripts/modelo_aero_xm7.py

Lo que hace, como modelo_aero_g1.py para el Poli-1:
  - masa, CG e inercias con la lista de masas de parametros_xm7.py (la carga util adicional se coloca para el CG)
  - calado del estabilizador para volar a la velocidad de crucero con la profundidad neutra, punto neutro y tablas y
    derivadas del VLM (analisis/vlm_e1.py con ENTRENADOR=XM7, con las dos derivas de la doble viga)
  - resistencia parasita (materiales compuestos lisos, barquilla, vigas, tren fijo y torreta) y helice propulsora de
    28" con un motor de 28 CV; el "combustible" es la energia en el eje de 45 l de gasolina
  - el tren triciclo (ruedas, amortiguadores, rodadura, frenos y rueda de morro dirigible) para la fisica en pista
  - el modelo 3D (barquilla, ala, vigas, cola en H, timones, motor, helice, torreta EO/IR, tren y antenas)
y escribe simulador/aviones/XM7.js con la clase ModeloG1 (scripts/clase_g1.js: alerones, profundidad y timon, de 4
canales como en una emisora) y lo anade a simulador/aviones/indice.js.

Ejes cuerpo estandar (x adelante, y derecha, z abajo); coeficientes por radian. La malla y el tren van en metros, en
ejes cuerpo con origen en el CG.
"""
import json, os, sys
import numpy as np

os.environ["ENTRENADOR"] = "XM7"
AQUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, AQUI); sys.path.insert(0, os.path.join(AQUI, "..", "analisis"))
from avion import ID, P   # noqa: E402
assert ID == "XM7"
import vlm_e1 as V        # noqa: E402

DIR_SIM = os.path.join(AQUI, "..", "simulador")
V_CRUCERO = 32.0          # m/s (115 km/h): ~1,35 veces la perdida

# =====================================================================
#  MASA, CG E INERCIAS (masas en g y mm, como en los demas aviones)
# =====================================================================
nb, mbat, ybat, zbat = P.BATERIA
fijas = sum(m for _, m, *_ in P.MASAS)
k_rep = (P.MASA_TOTAL - fijas - mbat) / sum(P.REPARTIDAS.values())
REP = {k: v * k_rep for k, v in P.REPARTIDAS.items()}
xs = np.linspace(0, P.L, 160)
sec = np.array([P.fus_seccion(x) for x in xs])
w_fus = 2 * (sec[:, 0] + sec[:, 1])
x_fus, z_fus = np.average(xs, weights=w_fus), np.average(sec[:, 2], weights=w_fus)
L_boom = P.BOOM_X1 - P.BOOM_X0
cuerpos = [
    ("ala", REP["ala"], P.X_LE + 0.42 * P.C, P.Z_ALA + 40.0, (P.C, P.B, 80.0)),
    ("barquilla", REP["fuselaje"], x_fus, z_fus, (P.L, P.FUS_W, P.FUS_H)),
    ("vigas", REP["vigas"], P.BOOM_X0 + 0.5 * L_boom, P.BOOM_Z, (L_boom, 2 * P.BOOM_Y, 90.0)),
    ("estabilizador", REP["estab"], P.HT_XLE + 0.5 * P.HT_C, P.HT_Z, (P.HT_C, P.HT_B, 30.0)),
    ("derivas", REP["deriva"], P.FIN_XLE + 0.5 * P.FIN_C, P.FIN_Z0 + 0.5 * P.FIN_H, (P.FIN_C, 2 * P.FIN_Y, P.FIN_H)),
]
puntos = [(n, m, x, y, z) for n, m, x, y, z in P.MASAS] + [(n, m, x, 0.0, z) for n, m, x, z, _ in cuerpos]
M = P.MASA_TOTAL
mx_sin_bat = sum(m * x for _, m, x, _, _ in puntos)
x_bat_ideal = (P.X_CG * M - mx_sin_bat) / mbat
x_bat = float(np.clip(x_bat_ideal, P.BAT_X_MIN, P.BAT_X_MAX))
puntos.append((nb, mbat, x_bat, ybat, zbat))
x_cg = sum(m * x for _, m, x, _, _ in puntos) / M
z_cg = sum(m * z for _, m, _, _, z in puntos) / M
I = np.zeros((3, 3))
for n, m, x, y, z in puntos:
    r = np.array([-(x - x_cg), y, -(z - z_cg)]) / 1e3
    I += m / 1e3 * (np.dot(r, r) * np.eye(3) - np.outer(r, r))
for n, m, x, z, (lx, ly, lz) in cuerpos:
    a, b, c = lx / 1e3, ly / 1e3, lz / 1e3
    I += m / 1e3 / 12 * np.diag([b * b + c * c, a * a + c * c, a * a + b * b])
iner = dict(masa_kg=M / 1e3, cg_mm=[round(x_cg, 1), 0.0, round(z_cg, 1)],
            Ixx=float(I[0, 0]), Iyy=float(I[1, 1]), Izz=float(I[2, 2]), Ixz=float(-I[0, 2]))

# =====================================================================
#  AERODINAMICA (VLM)
# =====================================================================
m_kg = iner["masa_kg"]
HT_INC = float(V.calado_estab_para(V_CRUCERO, m_kg, x_cg))
mod = V.Modelo(x_cg_mm=x_cg, z_cg_mm=z_cg, HT_INC=HT_INC)
xnp = float(V.punto_neutro(HT_INC=HT_INC))
S = mod.S
tabla = []
for a in np.arange(-10, 16, 2.0):
    r = mod.resolver(a, V=V_CRUCERO)
    tabla.append(dict(alfa=float(a), CL=r["CL"], CDi=r["CDi"], Cm=r["Cm"] + V.fus_Cm_alfa(mod) * np.radians(a)))
derivs = [dict(alfa=a, **{k: float(v) for k, v in V.derivadas(mod, a, V=V_CRUCERO).items()}) for a in (-6.0, -2.0, 2.0, 6.0, 10.0)]
d2 = derivs[2]
modos = V.modos_laterales(d2, m_kg, iner["Ixx"], iner["Izz"], V_CRUCERO, S, mod.b)

# ---- resistencia parasita: compuestos lisos, barquilla, vigas, cola, tren fijo, torreta y antenas ----
nu = 1.5e-5
cf = lambda Re: 0.074 / Re ** 0.2
cd_ala = 2 * cf(V_CRUCERO * P.C / 1e3 / nu) * 1.35                          # perfil del 15 %
moj_fus = np.trapezoid(2 * np.pi * np.sqrt(0.5 * (sec[:, 0] ** 2 + sec[:, 1] ** 2)), xs) / 1e6
cd_fus = cf(V_CRUCERO * P.L / 1e3 / nu) * 1.15 * moj_fus / S
cd_vigas = 2 * cf(V_CRUCERO * L_boom / 1e3 / nu) * 1.05 * (np.pi * 2 * P.BOOM_R * L_boom / 1e6) / S
moj_cola = 2 * (P.HT_B * P.HT_C + 2 * P.FIN_C * P.FIN_H) / 1e6
cd_cola = cf(V_CRUCERO * P.HT_C / 1e3 / nu) * 1.1 * moj_cola / S
cd_tren = (3 * 2 * P.R_RUEDA / 1e3 * 0.1 * 0.5 + 3 * 0.45 * 0.05 * 0.3) / S       # ruedas de 28 cm con carenas a medias y patas carenadas
cd_torreta = np.pi * 0.15 ** 2 * 0.35 / S                                          # bola de 30 cm bajo el morro
CD0 = cd_ala + cd_fus + cd_vigas + cd_cola + cd_tren + cd_torreta + 0.004           # +0,004 antenas, refrigeracion e interferencias

# ---- helice propulsora de 28" con un motor de 28 CV (21 kW) a 6500 rpm: ~60 kgf estaticos ----
D_prop, n_max, T_N = P.D_HELICE_MM / 1e3, 6500 / 60, 600.0
CT0 = T_N / 1.225 / n_max ** 2 / D_prop ** 4
E_comb = P.COMBUSTIBLE_L * 8.9e3 * 0.24            # Wh en el eje: gasolina 8,9 kWh/l con un 24 % de rendimiento
prop = dict(T_max_N=T_N, D_m=D_prop, n_max_rps=n_max, CT0=float(CT0), J0=1.05, I_max_A=0.0, P_max_W=21000.0,
            masa_bateria_Wh=float(E_comb), combustible=True, combustible_l=P.COMBUSTIBLE_L, downthrust_grados=P.DOWNTHRUST)

# ---- mandos: alerones para ~60 grados/s de alabeo a la velocidad de crucero (un avion de 5,5 m) ----
tasa = lambda da_g: np.degrees(d2["Clda"] * np.radians(da_g) / -d2["Clp"] * 2 * V_CRUCERO / mod.b)
da_sim = float(np.radians(60.0) * mod.b / (2 * V_CRUCERO) * (-d2["Clp"]) / d2["Clda"])
da_sim = float(min(P.ALERON["max_grados"], round(np.degrees(da_sim) * 2) / 2))
mandos = dict(prof_max_grados=12.0, timon_max_grados=18.0, aleron_max_grados=da_sim, expo=0.35, servo_tau_s=0.08,
              servo_vel_grados_s=120.0, izq_der="alerones (A / D: timones y rueda de morro)",
              mecanico=dict(prof=18.0, aleron=P.ALERON["max_grados"], timon=25.0),
              nota="de > 0 = profundidad abajo; dr > 0 = timones a la derecha (y la rueda de morro); da > 0 = aleron "
                   "derecho arriba. Con el piloto automatico las palancas mandan consignas (ver js/piloto_uav.js)")
# perdida: el VLM es lineal; un ala de alargamiento 10 con el NACA 4415 a Re ~1,2e6 llega a un CLmax 3D de ~1,45, que en
# la tabla cae en ~8,5 grados de barquilla (10,5 de ala con el calado): ~84 km/h de perdida con 150 kg
perdida = dict(alfa_perdida_grados=8.5, anchura_grados=3.0, alfa_perdida_neg_grados=-10.0,
               CL_placa_factor=0.8, mando_post_perdida=0.4)

# ---- tren triciclo: posiciones de los puntos de contacto (fondo de cada rueda) en ejes cuerpo ----
def a_cuerpo(v):
    v = np.asarray(v, float)
    return np.c_[-(v[:, 0] - x_cg), v[:, 1], -(v[:, 2] - z_cg)] / 1e3

z_contacto = P.TREN_Z - P.R_RUEDA
ruedas = [dict(p=np.round(a_cuerpo([(P.TREN_MORRO_X, 0.0, z_contacto)])[0], 4).tolist(), morro=True)]
ruedas += [dict(p=np.round(a_cuerpo([(P.TREN_PPAL_X, s * P.TREN_PPAL_Y, z_contacto)])[0], 4).tolist(), morro=False) for s in (-1, 1)]
# carga estatica en las principales ~88 %: k para ~6 cm de compresion con el peso, amortiguamiento cerca del critico
k_ppal = 0.88 * m_kg * 9.81 / 2 / 0.06
tren = dict(ruedas=ruedas, k=float(k_ppal), c=float(2 * 0.6 * np.sqrt(k_ppal * m_kg / 3)), radio=P.R_RUEDA / 1e3,
            mu_rodadura=0.025, mu_freno=0.55, mu_lateral=0.7, giro_morro_grados=25.0, v_toma_max_ms=2.5,
            nota="Fuerzas por rueda: muelle y amortiguador vertical, rodadura (con frenos en las principales) y "
                 "agarre lateral; la rueda de morro gira con los timones. Lo usa ModeloAvion.paso (fuerzasTren)")

# =====================================================================
#  MODELO 3D (el mismo en los dos simuladores: construirAvion de visor.js y avion_3d.gd lo montan de "malla")
#  Barquilla torneada con la torreta EO/IR bajo el morro (gira con la camara: malla.torreta), ala con su perfil,
#  vigas, cola en H con la profundidad, dos derivas con sus timones (alerones con timon: true), motor y escape,
#  helice bipala con el cono, tren triciclo y antenas. Coordenadas del proyecto (mm) -> ejes cuerpo (m).
# =====================================================================
GRIS, OSCURO, NEGRO, CRISTAL, AMARILLO = 0x7c8288, 0x2b2f33, 0x141618, 0x0d1a24, 0xf2c200


def juntar(*partes, color=None, suave=False):
    v, i = [], []
    for pv, pi in partes:
        i += [k + len(v) for k in pi]; v += list(pv)
    m = dict(v=np.round(a_cuerpo(v), 4).ravel().tolist(), i=[int(k) for k in i])
    if color is not None: m["color"] = color
    if suave: m["suave"] = True
    return m


def anillos(secciones, n=20, cerrar=(True, True)):
    """Superficie torneada: secciones [(X, semiancho, semialto, Zc)] (elipses a lo largo de X). Tapas si se piden."""
    v, i = [], []
    for x, w, h, zc in secciones:
        v += [(x, w * np.cos(t), zc + h * np.sin(t)) for t in np.linspace(0, 2 * np.pi, n, endpoint=False)]
    for j in range(len(secciones) - 1):
        for k in range(n):
            a, b = j * n + k, j * n + (k + 1) % n
            i += [a, n + b, b, a, n + a, n + b]
    for extremo, cierra in ((0, cerrar[0]), (len(secciones) - 1, cerrar[1])):
        if not cierra: continue
        x, w, h, zc = secciones[extremo]; c = len(v); v.append((x, 0.0, zc)); base = extremo * n
        for k in range(n):
            a, b = base + k, base + (k + 1) % n
            i += [c, b, a] if extremo == 0 else [c, a, b]
    return v, i


def tubo(p0, p1, r0, r1=None, n=14, tapas=True):
    """Tubo (o tronco de cono) entre dos puntos."""
    r1 = r0 if r1 is None else r1
    p0, p1 = np.asarray(p0, float), np.asarray(p1, float); d = p1 - p0; L = np.linalg.norm(d); d /= L
    a = np.cross(d, [0, 0, 1.0] if abs(d[2]) < 0.9 else [1.0, 0, 0]); a /= np.linalg.norm(a); b = np.cross(d, a)
    v = [tuple(p0 + r0 * (np.cos(t) * a + np.sin(t) * b)) for t in np.linspace(0, 2 * np.pi, n, endpoint=False)]
    v += [tuple(p1 + r1 * (np.cos(t) * a + np.sin(t) * b)) for t in np.linspace(0, 2 * np.pi, n, endpoint=False)]
    i = []
    for k in range(n):
        j = (k + 1) % n; i += [k, j, n + j, k, n + j, n + k]
    if tapas:
        c0, c1 = len(v), len(v) + 1; v += [tuple(p0), tuple(p1)]
        for k in range(n): j = (k + 1) % n; i += [c0, j, k, c1, n + k, n + j]
    return v, i


def esfera(c, r, n=16, m=10, z0=-1.0, z1=1.0):
    """Esfera (o casquete entre las alturas relativas z0..z1) de centro c y radio r."""
    v, i = [], []
    fs = np.linspace(np.arcsin(z0), np.arcsin(z1), m + 1)
    for f in fs:
        v += [(c[0] + r * np.cos(f) * np.cos(t), c[1] + r * np.cos(f) * np.sin(t), c[2] + r * np.sin(f)) for t in np.linspace(0, 2 * np.pi, n, endpoint=False)]
    for j in range(m):
        for k in range(n):
            a, b = j * n + k, j * n + (k + 1) % n
            i += [a, b, n + b, a, n + b, n + a]
    return v, i


def perfil_pts(perfil, n=16, s0=0.0, s1=1.0):
    """Contorno de un perfil NACA de 4 cifras (fracciones de cuerda: (s, z)), extrados e intrados, entre s0 y s1."""
    m_, p_, t_ = perfil
    s = s0 + (s1 - s0) * 0.5 * (1 - np.cos(np.linspace(0, np.pi, n)))
    yt = 5 * t_ * (0.2969 * np.sqrt(s) - 0.126 * s - 0.3516 * s ** 2 + 0.2843 * s ** 3 - 0.1036 * s ** 4)
    if m_ > 0: yc = np.where(s < p_, m_ / p_ ** 2 * (2 * p_ * s - s ** 2), m_ / (1 - p_) ** 2 * (1 - 2 * p_ + 2 * p_ * s - s ** 2))
    else: yc = 0 * s
    return list(zip(s, yc + yt)) + list(zip(s[::-1], (yc - yt)[::-1]))


def superficie(perfil, cuerda, xle, z, y0, y1, inc=0.0, diedro=0.0, s0=0.0, s1=1.0, n=16, cuerda1=None, eje="y"):
    """Superficie con perfil entre y0 e y1 (eje "y": horizontal, con diedro; eje "z": vertical, en el plano y = xle[1]).
    Cuerda constante o de cuerda (en y0) a cuerda1 (en y1) con el borde de fuga recto."""
    c1 = cuerda if cuerda1 is None else cuerda1
    pts = perfil_pts(perfil, n, s0, s1); k = len(pts); a = np.radians(inc); t = np.tan(np.radians(diedro))
    v = []
    for y, c in ((y0, cuerda), (y1, c1)):
        x0 = xle + (cuerda - c)                                 # borde de fuga recto
        for s, zz in pts:
            px, pz = s * c, zz * c
            X = x0 + px * np.cos(a) + pz * np.sin(a); Zs = pz * np.cos(a) - px * np.sin(a)
            v.append((X, y, z + Zs + abs(y) * t) if eje == "y" else (X, Zs, y))
    i = []
    for j in range(k):
        jj = (j + 1) % k; i += [j, k + j, k + jj, j, k + jj, jj]
    c0 = len(v); v.append(tuple(np.mean(v[:k], axis=0))); c1_ = len(v); v.append(tuple(np.mean(v[k:2 * k], axis=0)))
    for j in range(k): jj = (j + 1) % k; i += [c0, jj, j, c1_, k + j, k + jj]
    return v, i


def caja(x0, x1, y0, y1, z0, z1):
    v = [(x, y, z) for z in (z0, z1) for y in (y0, y1) for x in (x0, x1)]
    caras = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
    i = []
    for a, b, c, d in caras: i += [a, b, c, a, c, d]
    return v, i


# ---- barquilla: morro redondeado, flancos rectos, lomo para el ala y cola en cono hasta el motor ----
sec = []
for x in list(np.linspace(0, P.X_MORRO, 9)) + list(np.linspace(P.X_MORRO + 150, P.L, 12)):
    w, h, zc = P.fus_seccion(float(x)); sec.append((float(x), w, h, zc))
barquilla = anillos(sec, n=24, cerrar=(False, True))
morro = esfera((sec[0][0] + 0.0, 0.0, sec[0][3]), 20.0, n=24, m=4)          # tapa del morro
lomo = superficie((0, 0.4, 0.30), 900.0, P.X_LE - 120, P.FUS_H / 2 - 40, -160, 160, eje="y")      # carenado del ala sobre la barquilla
lomo = ([(x, y, max(z, P.FUS_H / 2 - 30)) for x, y, z in lomo[0]], lomo[1])
# ---- ala: dos semialas con el perfil, alerones exteriores y puntas redondeadas ----
AL = P.ALERON; sb = AL["bisagra"]; semi = P.B / 2; y0a, y1a = AL["y0"], AL["y1"]
ala_p, alerones = [], []
for lado in (-1, 1):
    for (ya, yb), (s0, s1) in (((0, y0a), (0, 1)), ((y0a, y1a), (0, sb)), ((y1a, semi - 60), (0, 1))):
        a_, b_ = sorted((lado * ya, lado * yb)); ala_p.append(superficie(P.PERFIL, P.C, P.X_LE, P.Z_ALA, a_, b_, inc=P.INC, diedro=P.DIEDRO, s0=s0, s1=s1, n=18))
    a_, b_ = sorted((lado * (semi - 60), lado * semi)); ala_p.append(superficie(P.PERFIL, P.C, P.X_LE, P.Z_ALA, a_, b_, inc=P.INC, diedro=P.DIEDRO, n=18, cuerda1=P.C * 0.7) if lado > 0
                                                                      else superficie(P.PERFIL, P.C * 0.7, P.X_LE + 0.3 * P.C, P.Z_ALA, a_, b_, inc=P.INC, diedro=P.DIEDRO, n=18, cuerda1=P.C))
    a_, b_ = sorted((lado * y0a, lado * y1a))
    al = juntar(superficie(P.PERFIL, P.C, P.X_LE, P.Z_ALA, a_, b_, inc=P.INC, diedro=P.DIEDRO, s0=sb, s1=1.0, n=10), color=GRIS)
    t = np.tan(np.radians(P.DIEDRO)); ye = lado * y0a
    xb = P.X_LE + sb * P.C * np.cos(np.radians(P.INC)); zb = P.Z_ALA - sb * P.C * np.sin(np.radians(P.INC)) + abs(ye) * t
    eje = np.array([0.0, 1.0, -lado * t]) if lado > 0 else np.array([0.0, 1.0, t])
    al.update(bisagra=np.round(a_cuerpo([(xb, ye, zb)])[0], 4).tolist(), eje=np.round(eje / np.linalg.norm(eje), 4).tolist(), signo=1.0 if lado < 0 else -1.0)
    alerones.append(al)
# ---- vigas de cola: tubos con cono al final ----
vigas = []
for s in (-1, 1):
    y = s * P.BOOM_Y
    vigas.append(tubo((P.BOOM_X0, y, P.BOOM_Z), (P.BOOM_X1 - 80, y, P.BOOM_Z), P.BOOM_R, n=16, tapas=False))
    vigas.append(tubo((P.BOOM_X1 - 80, y, P.BOOM_Z), (P.BOOM_X1 + 60, y, P.BOOM_Z), P.BOOM_R, 12, n=16))
    vigas.append(tubo((P.BOOM_X0 - 60, y, P.BOOM_Z), (P.BOOM_X0, y, P.BOOM_Z), 15, P.BOOM_R, n=16))
# ---- cola en H: estabilizador con la profundidad y dos derivas con sus timones ----
te_h = P.HT_XLE + P.HT_C; xh = te_h - (1 - P.ELEV_HINGE) * P.HT_C; sh = P.HT_B / 2
estab = superficie((0, 0.4, 0.10), P.HT_C, P.HT_XLE, P.HT_Z, -sh, sh, s0=0.0, s1=P.ELEV_HINGE, n=12)
prof = juntar(superficie((0, 0.4, 0.10), P.HT_C, P.HT_XLE, P.HT_Z, -sh + 25, sh - 25, s0=P.ELEV_HINGE, s1=1.0, n=8), color=GRIS)
derivas, timones = [], []
te_v = P.FIN_XLE + P.FIN_C; xr = te_v - (1 - P.RUD_HINGE) * P.FIN_C
for s in (-1, 1):
    y = s * P.FIN_Y
    d = superficie((0, 0.4, 0.10), P.FIN_C, P.FIN_XLE, 0, P.FIN_Z0, P.FIN_Z0 + P.FIN_H, s0=0.0, s1=P.RUD_HINGE, n=12, cuerda1=P.FIN_C * 0.75, eje="z")
    derivas.append(([(x, yy + y, z) for x, yy, z in d[0]], d[1]))
    tm = superficie((0, 0.4, 0.10), P.FIN_C, P.FIN_XLE, 0, P.FIN_Z0 + 20, P.FIN_Z0 + P.FIN_H - 20, s0=P.RUD_HINGE, s1=1.0, n=8, cuerda1=P.FIN_C * 0.75, eje="z")
    t_ = juntar(([(x, yy + y, z) for x, yy, z in tm[0]], tm[1]), color=GRIS)
    t_.update(bisagra=np.round(a_cuerpo([(xr, y, P.FIN_Z0)])[0], 4).tolist(), eje=[0.0, 0.0, 1.0], signo=-1.0, timon=True)   # dr > 0: borde de fuga a la derecha
    timones.append(t_)
# ---- motor: carenado trasero, cilindros a los lados, escape, cono y palas de la helice ----
motor = [tubo((P.L - 20, 0, P.Z_MOTOR), (P.X_HELICE - 60, 0, P.Z_MOTOR), 150, 95, n=20)]
cilindros = [tubo((2080, s * 120, P.Z_MOTOR), (2080, s * 230, P.Z_MOTOR), 55, 45, n=12) for s in (-1, 1)]
escape = [tubo((2150, s * 150, P.Z_MOTOR - 60), (2330, s * 120, P.Z_MOTOR - 110), 22, n=10) for s in (-1, 1)]
cono = anillos([(P.X_HELICE - 40, 70, 70, P.Z_MOTOR), (P.X_HELICE + 30, 60, 60, P.Z_MOTOR), (P.X_HELICE + 130, 6, 6, P.Z_MOTOR)], n=16, cerrar=(True, True))
R_h = P.D_HELICE_MM / 2
palas = []
for s in (-1, 1):                       # bipala con torsion: una caja fina girada a lo largo
    v_, i_ = caja(-12, 12, 0, s * (R_h - 10), -45, 45)
    tw = lambda y: np.radians(35 - 20 * abs(y) / R_h) * s
    v_ = [(P.X_HELICE + x * np.cos(tw(y)) - z * np.sin(tw(y)), y, P.Z_MOTOR + x * np.sin(tw(y)) + z * np.cos(tw(y))) for x, y, z in v_]
    palas.append((v_, i_))
puntas = [caja(P.X_HELICE - 13, P.X_HELICE + 13, s * (R_h - 60), s * (R_h - 10), P.Z_MOTOR - 40, P.Z_MOTOR + 40) for s in (-1, 1)]
# ---- torreta EO/IR: horquilla fija bajo el morro y bola con la ventana (la bola gira con la camara) ----
TC = (230.0, 0.0, -P.FUS_H / 2 - 150.0)                 # centro de la bola
yugo = [tubo((TC[0], 0, -P.FUS_H / 2 + 20), (TC[0], 0, TC[2] + 140), 95, 80, n=20)]
bola = esfera(TC, 135.0, n=24, m=14)
ventanas = [esfera((TC[0] + 128, s * 38, TC[2]), 26.0, n=14, m=8) for s in (-1, 1)]   # dos ventanas: cámara diurna y térmica
# ---- tren triciclo: patas, horquilla de morro, ruedas ----
z_eje = P.TREN_Z
patas = [tubo((P.TREN_MORRO_X, 0, -P.FUS_H / 2 + 60), (P.TREN_MORRO_X, 0, z_eje + 60), 28, n=12),
         tubo((P.TREN_MORRO_X - 10, -60, z_eje + 60), (P.TREN_MORRO_X, -60, z_eje), 14, n=8), tubo((P.TREN_MORRO_X - 10, 60, z_eje + 60), (P.TREN_MORRO_X, 60, z_eje), 14, n=8)]
for s in (-1, 1):
    patas.append(tubo((P.TREN_PPAL_X - 120, s * 170, -P.FUS_H / 2 + 40), (P.TREN_PPAL_X, s * P.TREN_PPAL_Y, z_eje), 30, 24, n=12))
    patas.append(tubo((P.TREN_PPAL_X - 280, s * 150, -P.FUS_H / 2 + 60), (P.TREN_PPAL_X, s * (P.TREN_PPAL_Y - 40), z_eje + 40), 16, n=8))
ruedas3d = [tubo((P.TREN_MORRO_X, -40, z_eje), (P.TREN_MORRO_X, 40, z_eje), P.R_RUEDA * 0.85, n=20)]
ruedas3d += [tubo((P.TREN_PPAL_X, s * (P.TREN_PPAL_Y - 50), z_eje), (P.TREN_PPAL_X, s * (P.TREN_PPAL_Y + 50), z_eje), P.R_RUEDA, n=20) for s in (-1, 1)]
llantas = [tubo((P.TREN_MORRO_X, -42, z_eje), (P.TREN_MORRO_X, 42, z_eje), P.R_RUEDA * 0.45, n=12)]
llantas += [tubo((P.TREN_PPAL_X, s * (P.TREN_PPAL_Y - 52), z_eje), (P.TREN_PPAL_X, s * (P.TREN_PPAL_Y + 52), z_eje), P.R_RUEDA * 0.5, n=12) for s in (-1, 1)]
# ---- antenas: enlace de datos (aletas en el lomo y la panza), GPS y tubo de pitot ----
antenas = [superficie((0, 0.4, 0.12), 140.0, 820.0, 0, P.FUS_H / 2 - 10, P.FUS_H / 2 + 230, n=8, cuerda1=70.0, eje="z"),
           superficie((0, 0.4, 0.12), 120.0, 1500.0, 0, -P.FUS_H / 2 + 10, -P.FUS_H / 2 - 170, n=8, cuerda1=60.0, eje="z")]
antenas = [([(x, yy, z) for x, yy, z in a[0]], a[1]) for a in antenas]
gps = [tubo((1150, 0, P.FUS_H / 2 - 5), (1150, 0, P.FUS_H / 2 + 25), 45, n=14)]
pitot = [tubo((P.X_LE + 60, P.B / 2 - 300, P.Z_ALA - 40), (P.X_LE - 260, P.B / 2 - 300, P.Z_ALA - 40), 6, n=6)]

malla = dict(fuselaje=juntar(barquilla, morro, lomo, *vigas, color=GRIS, suave=True),
             ala=juntar(*ala_p, color=GRIS), estab=juntar(estab, *derivas, color=GRIS), prof=prof,
             bisagra_prof=np.round(a_cuerpo([(xh, 0.0, P.HT_Z)])[0], 4).tolist(),
             alerones=alerones + timones,
             torreta=dict(juntar(bola, color=OSCURO, suave=True), centro=np.round(a_cuerpo([TC])[0], 4).tolist(),
                          ventanas=juntar(*ventanas, color=CRISTAL, suave=True)),
             piezas=[juntar(*motor, cono, color=OSCURO, suave=True), juntar(*cilindros, *escape, color=NEGRO),
                     juntar(*palas, color=NEGRO), juntar(*puntas, color=AMARILLO), juntar(*yugo, color=OSCURO, suave=True),
                     juntar(*patas, color=OSCURO), juntar(*ruedas3d, color=NEGRO, suave=True), juntar(*llantas, color=0x9aa0a6),
                     juntar(*antenas, *gps, *pitot, color=NEGRO)],
             helice=np.round(a_cuerpo([(P.X_HELICE, 0.0, P.Z_MOTOR)])[0], 4).tolist(), helice_r=D_prop / 2)

# =====================================================================
#  FICHERO DEL SIMULADOR
# =====================================================================
CLmax = float(max(t["CL"] for t in tabla if t["alfa"] <= perdida["alfa_perdida_grados"]))
v_perd = float(np.sqrt(2 * m_kg * 9.81 / (1.225 * S * CLmax)))
margen = (xnp - x_cg) / P.C * 100
modelo = dict(
    id=ID, nombre=P.NOMBRE, descripcion=P.DESCRIPCION, uav=True,
    categoria="150 kg, UAS militar clase I (táctico ligero)",
    ayuda=("Despega en pista: arranca (L), suelta el freno de aparcamiento (espacio), gas a tope y ve recto con los timones "
           "(A / D, que mueven la rueda de morro); a 29 m/s (104 km/h) tira suavemente. Piloto automático: M pasa de manual "
           "a estabilizado y a crucero (mantiene altura, rumbo y velocidad), un clic en el mapa va a ese punto y da vueltas "
           "sobre él, H vuelve a la base y P despega o aterriza solo. Torreta EO/IR (cámara 3; la 1 es la de vuelo, en el "
           "morro): las flechas con Mayúsculas (o solas con el automático navegando), Q / E la inclinan, K la fija en un "
           "punto, Z / X zoom, C térmica y F foto."),
    perfil="NACA %d%d%02d" % (round(P.PERFIL[0] * 100), round(P.PERFIL[1] * 10), round(P.PERFIL[2] * 100)),
    caracteristicas=[["Envergadura", "%.1f m" % (P.B / 1e3)], ["Longitud", "%.1f m" % ((P.BOOM_X1 + 60) / 1e3)],
                     ["Superficie alar", "%.2f m²" % S], ["Peso al despegue", "%.0f kg" % m_kg],
                     ["Carga alar", "%.0f kg/m²" % (m_kg / S)], ["Mandos", P.MANDOS_TXT],
                     ["Motor", "2 cilindros, 2 tiempos, 28 CV, hélice propulsora de 28\""],
                     ["Combustible", "%.0f l de gasolina (≈ %.0f h)" % (P.COMBUSTIBLE_L, E_comb / (21000 * 0.3))],
                     ["Velocidad de pérdida", "%.0f km/h (%.0f m/s)" % (v_perd * 3.6, v_perd)],
                     ["Crucero", "%.0f km/h" % (V_CRUCERO * 3.6)],
                     ["Carga útil", "torreta EO/IR: zoom 30× y cámara térmica"],
                     ["Tren", "triciclo fijo, rueda de morro dirigible y frenos"],
                     ["Centro de gravedad", "%.0f %% de la cuerda (margen estático %.0f %%)" % ((x_cg - P.X_LE) / P.C * 100, margen)]],
    S_m2=S, b_m=mod.b, c_m=mod.c, masa_kg=m_kg, cg_mm=iner["cg_mm"],
    inercia=dict(Ixx=iner["Ixx"], Iyy=iner["Iyy"], Izz=iner["Izz"], Ixz=iner["Ixz"]),
    tabla_alfa=tabla, derivadas=derivs, CD0=float(CD0),
    desglose_CD0=dict(ala=float(cd_ala), barquilla=float(cd_fus), vigas=float(cd_vigas), cola=float(cd_cola),
                      tren=float(cd_tren), torreta=float(cd_torreta)),
    perdida=perdida, propulsion=prop, mandos=mandos, compensador_grados=0.0, tren=tren,
    lanzamiento=dict(vel_ms=0.0, cabeceo_grados=0.0),        # no se lanza a mano: despega en pista
    I_helice=2.2 * D_prop ** 2 / 12, k_perfil=0.008, brazo_perdida=0.2,
    chorro=dict(prof=0.15, timon=0.15, deriva=0.0),            # helice propulsora: la cola en H queda por encima de la estela y no hay deriva central que la gire
    camara=dict(zoom=[1, 2, 4, 8, 15, 30], zoom_optico=30, termica=True, torreta=True),
    # piloto automatico (js/piloto_uav.js): velocidades (m/s), angulos (grados), alturas (m) y ganancias de los lazos
    piloto=dict(v_min=28.0, v_alarma=26.0, v_max=42.0, v_crucero=V_CRUCERO, v_aprox=31.0, v_rotacion=29.0, alfa_max=6.5, k_alfa=1.5,
                alabeo_max=30.0, cabeceo_max=15.0, cabeceo_min=-10.0, cabeceo_crucero=2.0, cabeceo_rotacion=8.0,
                cabeceo_subida=8.0, cabeceo_recogida=4.0, h_min=150.0, h_base=300.0, h_fin_despegue=60.0, vz_max=5.0,
                final_m=3000.0, senda_grados=4.0, h_umbral=8.0, h_recogida=4.0, vz_toma=0.4, k_recogida=0.3, radio_orbita=400.0, k_orbita=150.0,
                giro_consigna=15.0, subida_consigna=4.0,
                k_alabeo=2.5, k_p=0.4, k_cabeceo=3.0, k_q=0.6, k_i_cabeceo=1.0, k_derrape=1.5, k_r=0.6,
                k_rumbo=1.2, k_altura=0.15, k_vz=0.02, k_gas=0.08, k_gas_vz=0.06, k_i_gas=0.02, gas_crucero=0.55,
                k_rumbo_tierra=2.0, k_eje=0.03, k_r_tierra=0.6, k_eje_aire=150.0),
    malla=malla, punto_neutro_mm=xnp, x_le_mm=P.X_LE,
    colores=dict(fuselaje=0x7c8288, ala=0x7c8288, estab=0x7c8288, moviles=0x6d7378),
    origen="Diseño propio de UxS Trainer (scripts/parametros_xm7.py): no es un avión real",
)
DIR_AV = os.path.join(DIR_SIM, "aviones"); NL = chr(10)
clase = open(os.path.join(AQUI, "clase_g1.js"), encoding="utf-8").read().rstrip()
clase = clase.replace("class ModeloG1 extends", "window.ModeloG1 = window.ModeloG1 || class ModeloG1 extends", 1)
with open(os.path.join(DIR_AV, ID + ".js"), "w", encoding="utf-8") as fj:
    fj.write("// %s. Generado por scripts/modelo_aero_xm7.py: no editar a mano." % P.NOMBRE + NL + clase + ";" + NL)
    fj.write("Modelos.registrar(" + json.dumps(modelo, ensure_ascii=False) + ", window.ModeloG1);" + NL)
f_ind = os.path.join(DIR_AV, "indice.js"); txt = open(f_ind, encoding="utf-8").read()
lista = json.loads(txt[txt.index("Modelos.indice(") + 15: txt.rindex(");")])
if ID + ".js" not in lista:
    lista.insert(lista.index("DJI_MINI.js") if "DJI_MINI.js" in lista else len(lista), ID + ".js")
    open(f_ind, "w", encoding="utf-8").write(txt[:txt.index("Modelos.indice(")] + "Modelos.indice(" + json.dumps(lista) + ");" + NL)
res = dict(avion=ID, masa=m_kg, x_cg=x_cg, z_cg=z_cg, x_carga=x_bat, x_carga_ideal=x_bat_ideal, HT_INC=HT_INC, xnp=xnp,
           margen_pct=margen, CD0=CD0, inercia=iner, derivadas_alfa2=d2, modos=modos, aleron_sim_grados=da_sim, v_perdida=v_perd)
json.dump(res, open(os.path.join(AQUI, "..", "analisis", "vlm_resultados_XM7.json"), "w"), indent=1, default=float)

# ---- resumen ----
print("%s: %.1f kg | CG X %.0f mm (%.1f %% de la cuerda), Z %.0f | carga util en X %.0f%s" % (
    P.NOMBRE, m_kg, x_cg, (x_cg - P.X_LE) / P.C * 100, z_cg, x_bat,
    "" if abs(x_bat - x_bat_ideal) < 0.5 else " (TOPE: para el CG objetivo iria en X %.0f)" % x_bat_ideal))
print("  inercias Ixx %.1f Iyy %.1f Izz %.1f Ixz %+.2f kg m2" % (iner["Ixx"], iner["Iyy"], iner["Izz"], iner["Ixz"]))
print("  calado del estabilizador para %.0f m/s con la profundidad neutra: %+.2f grados" % (V_CRUCERO, HT_INC))
print("  punto neutro X %.0f mm -> margen estatico %.1f %% | CLmax %.2f -> perdida %.1f m/s (%.0f km/h) | carga alar %.0f kg/m2"
      % (xnp, margen, CLmax, v_perd, v_perd * 3.6, m_kg / S))
print("  CD0 %.4f (ala %.4f, barquilla %.4f, vigas %.4f, cola %.4f, tren %.4f, torreta %.4f) | T/W %.2f"
      % (CD0, cd_ala, cd_fus, cd_vigas, cd_cola, cd_tren, cd_torreta, T_N / (m_kg * 9.81)))
for t in tabla:
    if t["alfa"] in (-4.0, 0.0, 4.0, 8.0, 12.0): print("  alfa %+3.0f: CL %.3f CDi %.4f Cm %+.4f" % (t["alfa"], t["CL"], t["CDi"], t["Cm"]))
print("  alfa 2: Clb %+.4f Cnb %+.4f Clp %+.3f Cnr %+.4f Cmq %+.2f Cmde %+.3f | Clda %+.4f Cnda %+.4f | Cndr %+.4f Cldr %+.4f"
      % (d2["Clb"], d2["Cnb"], d2["Clp"], d2["Cnr"], d2["Cmq"], d2["Cmde"], d2["Clda"], d2["Cnda"], d2["Cndr"], d2["Cldr"]))
s = modos["espiral"]
print("  espiral %+.4f 1/s (%s) | holandes %.2f Hz amort. %.2f | aleron con teclado %.1f grados: %.0f grados/s de alabeo" % (
    s, ("dobla en %.0f s" % (np.log(2) / s)) if s > 0 else ("se corrige a la mitad en %.0f s" % (np.log(2) / -s)),
    modos["holandes_hz"], modos["holandes_amort"], da_sim, tasa(da_sim)))
print("  tren: k %.0f N/m, c %.0f N s/m | ruedas (ejes cuerpo, m): %s" % (tren["k"], tren["c"], [r["p"] for r in ruedas]))
ntri = sum(len(m["i"]) // 3 for m in [malla["fuselaje"], malla["ala"], malla["estab"], prof, malla["torreta"]] + malla["alerones"] + malla["piezas"])
print("  malla: %d triangulos | %.0f kB" % (ntri, os.path.getsize(os.path.join(DIR_AV, ID + ".js")) / 1024))
