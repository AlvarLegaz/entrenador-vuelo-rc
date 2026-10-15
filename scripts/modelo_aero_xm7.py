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
  - una malla de cajas y prismas (la de respaldo: el visor usa el modelo detallado de aviones/XM7_3D.js si esta)
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
#  MALLA DE RESPALDO (prismas y cajas)
# =====================================================================
def prisma(poli, a0, a1, eje):
    poli = np.asarray(poli, float); n = len(poli)
    def p3(q, a):
        return {"y": (q[0], a, q[1]), "z": (q[0], q[1], a), "x": (a, q[0], q[1])}[eje]
    v = [p3(q, a0) for q in poli] + [p3(q, a1) for q in poli]
    c = poli.mean(0); v += [p3(c, a0), p3(c, a1)]
    i = []
    for k in range(n):
        j = (k + 1) % n
        i += [k, j, n + j, k, n + j, n + k, 2 * n, j, k, 2 * n + 1, n + k, n + j]
    return v, i


def caja(x0, x1, y0, y1, z0, z1):
    return prisma([(x0, z0), (x1, z0), (x1, z1), (x0, z1)], y0, y1, "y")


def barra(p0, p1, r, n=8):
    """Tubo de n lados de radio r entre dos puntos."""
    p0, p1 = np.asarray(p0, float), np.asarray(p1, float); d = p1 - p0; d /= np.linalg.norm(d)
    a = np.cross(d, [0, 0, 1.0] if abs(d[2]) < 0.9 else [1.0, 0, 0]); a /= np.linalg.norm(a); b = np.cross(d, a)
    esq = [r * (np.cos(t) * a + np.sin(t) * b) for t in np.linspace(0, 2 * np.pi, n, endpoint=False)]
    v = [tuple(p0 + e) for e in esq] + [tuple(p1 + e) for e in esq]
    i = []
    for k in range(n):
        j = (k + 1) % n; i += [k, j, n + j, k, n + j, n + k]
    for k in range(1, n - 1): i += [0, k + 1, k, n, n + k, n + k + 1]
    return v, i


def juntar(*partes, color=None):
    v, i = [], []
    for pv, pi in partes:
        i += [k + len(v) for k in pi]; v += list(pv)
    m = dict(v=np.round(a_cuerpo(v), 4).ravel().tolist(), i=[int(k) for k in i])
    if color is not None: m["color"] = color
    return m


def circulo(cx, cz, r, n=16):
    return [(cx + r * np.cos(t), cz + r * np.sin(t)) for t in np.linspace(0, 2 * np.pi, n, endpoint=False)]


mC, pC, tC = P.PERFIL
inc = np.radians(P.INC); Z0 = P.Z_ALA + 0.04 * P.C


def perfil(s0, s1, n=14):
    s = s0 + (s1 - s0) * 0.5 * (1 - np.cos(np.linspace(0, np.pi, n)))
    yt = 5 * tC * (0.2969 * np.sqrt(s) - 0.126 * s - 0.3516 * s ** 2 + 0.2843 * s ** 3 - 0.1036 * s ** 4)
    yc = np.where(s < pC, mC / pC ** 2 * (2 * pC * s - s ** 2), mC / (1 - pC) ** 2 * (1 - 2 * pC + 2 * pC * s - s ** 2))
    arriba, abajo = (yc + yt) * P.C, (yc - yt) * P.C
    x = s * P.C
    pts = list(zip(x, arriba)) + list(zip(x[::-1], abajo[::-1]))
    return [(P.X_LE + px * np.cos(inc) + pz * np.sin(inc), Z0 + pz * np.cos(inc) - px * np.sin(inc)) for px, pz in pts]


def con_diedro(m, lado):
    """Sube los vertices de una semiala con el diedro (giro sobre el plano de simetria)."""
    v = np.asarray(m[0], float).copy(); t = np.tan(np.radians(P.DIEDRO))
    v[:, 2] += np.abs(v[:, 1]) * t
    return [tuple(q) for q in v], m[1]


AL = P.ALERON; sb = AL["bisagra"]; y0a, y1a, semi = AL["y0"], AL["y1"], P.B / 2
ala_partes, alerones = [], []
for lado in (-1, 1):
    for (ya, yb), (s0, s1) in (((0, y0a), (0, 1)), ((y0a, y1a), (0, sb)), ((y1a, semi), (0, 1))):
        a, b = sorted((lado * ya, lado * yb)); ala_partes.append(con_diedro(prisma(perfil(s0, s1), a, b, "y"), lado))
    a, b = sorted((lado * y0a, lado * y1a))
    xb, zb = perfil(sb, sb, n=2)[0]
    al = juntar(con_diedro(prisma(perfil(sb, 1.0, n=8), a, b, "y"), lado))
    t = np.tan(np.radians(P.DIEDRO)); ye = lado * y0a
    p0 = a_cuerpo([(xb, ye, zb + abs(ye) * t)])[0]
    eje = np.array([0.0, 1.0, -lado * t]) if lado > 0 else np.array([0.0, 1.0, t])
    al.update(bisagra=np.round(p0, 4).tolist(), eje=np.round(eje / np.linalg.norm(eje), 4).tolist(), signo=1.0 if lado < 0 else -1.0)
    alerones.append(al)

# barquilla: anillos octogonales que siguen la seccion
anillos = []
for x in list(np.linspace(0, P.X_MORRO, 8)) + list(np.linspace(P.X_MORRO + 100, P.L, 10)):
    w, h, zc = P.fus_seccion(x)
    anillos.append([(x, w * np.cos(t), zc + h * np.sin(t)) for t in np.linspace(0, 2 * np.pi, 12, endpoint=False)])
vf, fi = [p for a in anillos for p in a], []
for j in range(len(anillos) - 1):
    for k in range(12):
        a, b = 12 * j + k, 12 * j + (k + 1) % 12
        fi += [a, b, b + 12, a, b + 12, a + 12]
n12 = 12 * (len(anillos) - 1)
for k in range(1, 11): fi += [0, k, k + 1, n12, n12 + k + 1, n12 + k]
vigas = [barra((P.BOOM_X0, s * P.BOOM_Y, P.BOOM_Z), (P.BOOM_X1, s * P.BOOM_Y, P.BOOM_Z), P.BOOM_R) for s in (-1, 1)]

te_h = P.HT_XLE + P.HT_C; xh = te_h - (1 - P.ELEV_HINGE) * P.HT_C; sh = P.HT_B / 2
estab = caja(P.HT_XLE, xh, -sh, sh, P.HT_Z - 15, P.HT_Z + 15)
prof = juntar(caja(xh, te_h, -sh + 30, sh - 30, P.HT_Z - 12, P.HT_Z + 12))
te_v = P.FIN_XLE + P.FIN_C
derivas = [caja(P.FIN_XLE, te_v, s * P.FIN_Y - 18, s * P.FIN_Y + 18, P.FIN_Z0, P.FIN_Z0 + P.FIN_H) for s in (-1, 1)]

# tren, ruedas, motor, torreta y antenas
z_eje = P.TREN_Z
patas = [barra((P.TREN_MORRO_X, 0, -P.FUS_H / 2 + 40), (P.TREN_MORRO_X, 0, z_eje), 25)]
patas += [barra((P.TREN_PPAL_X - 100, s * 150, -P.FUS_H / 2 + 30), (P.TREN_PPAL_X, s * P.TREN_PPAL_Y, z_eje), 30) for s in (-1, 1)]
rued = [prisma(circulo(P.TREN_MORRO_X, z_eje, P.R_RUEDA * 0.85), -45, 45, "y")]
rued += [prisma(circulo(P.TREN_PPAL_X, z_eje, P.R_RUEDA), s * P.TREN_PPAL_Y - 55, s * P.TREN_PPAL_Y + 55, "y") for s in (-1, 1)]
torreta = prisma(circulo(230.0, -P.FUS_H / 2 - 120, 150.0), -150, 150, "y")
piezas = [
    juntar(*patas, color=0x2b2f33),
    juntar(*rued, color=0x111111),
    juntar(prisma(circulo(P.L, P.Z_MOTOR, 120.0), 0.0, 0.0, "x") if False else caja(P.L - 10, P.X_HELICE - 30, -110, 110, P.Z_MOTOR - 110, P.Z_MOTOR + 110), color=0x3a3f44),
    juntar(torreta, color=0x24272b),
    juntar(barra((900, 0, P.FUS_H / 2), (900, 0, P.FUS_H / 2 + 260), 8), barra((1700, 0, P.FUS_H / 2 - 20), (1700, 0, P.FUS_H / 2 + 180), 8), color=0x1c1c1c),
]
malla = dict(fuselaje=juntar((vf, fi), *vigas), ala=juntar(*ala_partes), estab=juntar(estab, *derivas), prof=prof,
             bisagra_prof=np.round(a_cuerpo([(xh, 0.0, P.HT_Z)])[0], 4).tolist(),
             alerones=alerones, piezas=piezas,
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
    ayuda=("Despega en pista: suelta el freno de aparcamiento (espacio), gas a tope y ve recto con los timones (A / D, "
           "que mueven la rueda de morro); a 30 m/s (108 km/h) tira suavemente. En el aire, el piloto automático: "
           "1 estabilizado, 2 crucero (mantiene altura, rumbo y velocidad), 3 ir a punto (clic en el mapa), 4 vuelta a "
           "base y 0 manual; P despega o aterriza solo. Con el automático puesto, las flechas mueven la torreta EO/IR "
           "(Z / X zoom, C térmica, F foto)."),
    perfil="NACA %d%d%02d" % (round(mC * 100), round(pC * 10), round(tC * 100)),
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
ntri = sum(len(m["i"]) // 3 for m in [malla["fuselaje"], malla["ala"], malla["estab"], prof] + alerones + piezas)
print("  malla: %d triangulos | %.0f kB" % (ntri, os.path.getsize(os.path.join(DIR_AV, ID + ".js")) / 1024))
