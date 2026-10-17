"""Exporta el modelo de vuelo del Poli-1 al simulador (datos/vehiculos/G1.js). Es un avion de foam ya construido,
sin piezas impresas: todo sale de scripts/parametros_g1.py (medidas del avion, la foto y estimaciones marcadas).

    python scripts/modelo_aero_g1.py

Lo que hace, como modelo_aero_e1.py para los entrenadores impresos:
  - masa, CG e inercias con la lista de masas de parametros_g1.py (la bateria se coloca para dejar el CG en X_CG)
  - calado del estabilizador para volar a la velocidad de crucero con la profundidad neutra, punto neutro y tablas y
    derivadas del VLM (analisis/vlm_e1.py con ENTRENADOR=G1), con alerones y timon a la vez
  - resistencia parasita estimada (foam con cinta, tren fijo con ruedas) y helice 8x4 con el A2208/14T 1400 KV en 3S
  - una malla ligera para el visor (cajas y prismas: no hay STL) con la franja negra, las ruedas y el motor
y escribe datos/vehiculos/G1.js con la clase ModeloG1 (scripts/clase_g1.js: alerones en la palanca derecha y timon en
la izquierda, o A / D) y lo anade a datos/vehiculos/indice.js.

Ejes cuerpo estandar (x adelante, y derecha, z abajo); coeficientes por radian. La malla va en metros, en ejes cuerpo
con origen en el CG.
"""
import json, os, sys
import numpy as np

os.environ["ENTRENADOR"] = "G1"
AQUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, AQUI); sys.path.insert(0, os.path.join(AQUI, "..", "analisis"))
from avion import ID, P   # noqa: E402
assert ID == "G1"
import vlm_e1 as V        # noqa: E402

DIR_DATOS = os.path.join(AQUI, "..", "datos")                 # datos comunes de los simuladores
V_CRUCERO = 12.0          # m/s: ~1,3 veces la perdida

# =====================================================================
#  MASA, CG E INERCIAS
# =====================================================================
nb, mbat, ybat, zbat = P.BATERIA
fijas = sum(m for _, m, *_ in P.MASAS)
k_rep = (P.MASA_TOTAL - fijas - mbat) / sum(P.REPARTIDAS.values())   # foam, cinta y pegamento hasta el peso medido
REP = {k: v * k_rep for k, v in P.REPARTIDAS.items()}
xs = np.linspace(0, P.L, 120)
sec = np.array([P.fus_seccion(x) for x in xs])                     # semiancho, semialto, z
w_fus = 2 * (sec[:, 0] + sec[:, 1])                                # foam de la caja: proporcional al perimetro
x_fus, z_fus = np.average(xs, weights=w_fus), np.average(sec[:, 2], weights=w_fus)
# cuerpos repartidos: (masa, X, Z, dimensiones para su inercia propia: (largo en X, ancho en Y, alto en Z))
cuerpos = [
    ("ala", REP["ala"], P.X_LE + 0.42 * P.C, P.Z_ALA + 8.0, (P.C, P.B, 18.0)),
    ("fuselaje", REP["fuselaje"] + 0.0, x_fus, z_fus, (P.L, P.FUS_W, P.FUS_H)),
    ("estabilizador", REP["estab"], P.HT_XLE + 0.5 * P.HT_C, P.HT_Z, (P.HT_C, P.HT_B, 5.0)),
    ("deriva", REP["deriva"], P.FIN_XLE + 0.5 * P.FIN_C, P.fus_lomo(P.FIN_XLE) + 0.5 * P.FIN_H, (P.FIN_C, 5.0, P.FIN_H)),
]
puntos = [(n, m, x, y, z) for n, m, x, y, z in P.MASAS] + [(n, m, x, 0.0, z) for n, m, x, z, _ in cuerpos]
M = P.MASA_TOTAL
mx_sin_bat = sum(m * x for _, m, x, _, _ in puntos)
x_bat_ideal = (P.X_CG * M - mx_sin_bat) / mbat                    # donde iria la bateria para el CG objetivo
x_bat = float(np.clip(x_bat_ideal, P.BAT_X_MIN, P.BAT_X_MAX))
puntos.append((nb, mbat, x_bat, ybat, zbat))
x_cg = sum(m * x for _, m, x, _, _ in puntos) / M
z_cg = sum(m * z for _, m, _, _, z in puntos) / M
I = np.zeros((3, 3))                                               # ejes cuerpo (x adelante, y derecha, z abajo), kg m2
for n, m, x, y, z in puntos:
    r = np.array([-(x - x_cg), y, -(z - z_cg)]) / 1e3
    I += m / 1e3 * (np.dot(r, r) * np.eye(3) - np.outer(r, r))
for n, m, x, z, (lx, ly, lz) in cuerpos:                           # inercia propia de las piezas repartidas (cajas)
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

# ---- resistencia parasita: foam con cinta (rugoso), ala gruesa, caja de foam, tren fijo con ruedas ----
cf = lambda Re: 0.074 / Re ** 0.2
cd_ala = 2 * cf(V_CRUCERO * P.C / 1e3 / 1.5e-5) * 1.3                       # x1,3: perfil del 12 % y borde de ataque de foam
moj_fus = np.trapezoid(2 * (2 * sec[:, 0] + 2 * sec[:, 1]), xs) / 1e6
cd_fus = cf(V_CRUCERO * P.L / 1e3 / 1.5e-5) * 1.25 * moj_fus / S           # caja de cantos vivos
moj_cola = 2 * (P.HT_B * P.HT_C + P.FIN_C * P.FIN_H) / 1e6
cd_cola = cf(V_CRUCERO * P.HT_C / 1e3 / 1.5e-5) * 1.1 * moj_cola / S
# tren: dos ruedas de 56 x 18 mm (CD ~0,5 de frente) y las patas de alambre de 2 mm (CD 1,2), mas el patin
cd_tren = (2 * 0.056 * 0.018 * 0.5 + 2 * 0.11 * 0.002 * 1.2 + 0.03 * 0.004 * 1.0) / S
CD0 = (cd_ala + cd_fus + cd_cola + cd_tren + 0.004) * 1.2                 # +0,004 interferencias y gomas; x1,2 cinta y cantos

# ---- helice: A2208/14T 1400 KV en 3S con una 8x4 (SUPUESTO: datos tipicos de catalogo, ~700 gf a 12.000 rpm, 14 A) ----
D_prop, n_max, T_g = 8 * 0.0254, 12000 / 60, 700.0
CT0 = T_g / 1e3 * 9.81 / 1.225 / n_max ** 2 / D_prop ** 4
prop = dict(T_max_N=T_g / 1e3 * 9.81, D_m=D_prop, n_max_rps=n_max, CT0=float(CT0), J0=0.69, I_max_A=14.0,
            P_max_W=155.0, masa_bateria_Wh=P.BATERIA_WH, downthrust_grados=P.DOWNTHRUST)

# ---- mandos: recorridos con teclado (la palanca va siempre a tope) y los mecanicos (con mando, por el dual rate) ----
# alerones: los justos para ~150 grados/s de alabeo a la velocidad de crucero (p = -Clda da / Clp * 2V/b), sin pasar
# del recorrido mecanico (con alerones interiores puede no llegar)
tasa = lambda da_g: np.degrees(d2["Clda"] * np.radians(da_g) / -d2["Clp"] * 2 * V_CRUCERO / mod.b)
da_sim = float(np.radians(150.0) * mod.b / (2 * V_CRUCERO) * (-d2["Clp"]) / d2["Clda"])
da_sim = float(min(P.ALERON["max_grados"], round(np.degrees(da_sim) * 2) / 2))
mandos = dict(prof_max_grados=10.0, timon_max_grados=12.0, aleron_max_grados=da_sim, expo=0.40, servo_tau_s=0.06,
              servo_vel_grados_s=300.0, izq_der="alerones (A / D: timón)",
              mecanico=dict(prof=15.0, aleron=P.ALERON["max_grados"], timon=20.0),
              nota="de > 0 = profundidad abajo; dr > 0 = timon a la derecha; da > 0 = aleron derecho arriba (alabeo a "
                   "la derecha). Palanca derecha: profundidad y alerones; palanca izquierda de lado (A / D): timon")
# perdida: ala de foam plegada a Re ~1,2e5, ~11 grados de ala = 9 de fuselaje (calado 2)
perdida = dict(alfa_perdida_grados=11.0 - P.INC, anchura_grados=3.0, alfa_perdida_neg_grados=-9.0,
               CL_placa_factor=0.8, mando_post_perdida=0.4)

# =====================================================================
#  MALLA DEL VISOR (sin STL: prismas y cajas)
# =====================================================================
def a_cuerpo(v):
    v = np.asarray(v, float)
    return np.c_[-(v[:, 0] - x_cg), v[:, 1], -(v[:, 2] - z_cg)] / 1e3


def prisma(poli, a0, a1, eje):
    """Prisma de un poligono (estrellado desde su centroide) extruido a lo largo de un eje del proyecto:
    eje "y": poli en (X, Z); "z": poli en (X, Y); "x": poli en (Y, Z)."""
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


def barra(p0, p1, r):
    """Barra de seccion cuadrada (lado 2r) entre dos puntos."""
    p0, p1 = np.asarray(p0, float), np.asarray(p1, float); d = p1 - p0; d /= np.linalg.norm(d)
    a = np.cross(d, [0, 0, 1.0] if abs(d[2]) < 0.9 else [1.0, 0, 0]); a /= np.linalg.norm(a); b = np.cross(d, a)
    esq = [r * (sa * a + sb * b) for sa, sb in ((1, 1), (-1, 1), (-1, -1), (1, -1))]
    v = [tuple(p0 + e) for e in esq] + [tuple(p1 + e) for e in esq]
    i = []
    for k in range(4):
        j = (k + 1) % 4; i += [k, j, 4 + j, k, 4 + j, 4 + k]
    return v, i + [0, 1, 2, 0, 2, 3, 4, 6, 5, 4, 7, 6]


def juntar(*partes, color=None):
    v, i = [], []
    for pv, pi in partes:
        i += [k + len(v) for k in pi]; v += list(pv)
    m = dict(v=np.round(a_cuerpo(v), 4).ravel().tolist(), i=[int(k) for k in i])
    if color is not None: m["color"] = color
    return m


def circulo(cx, cz, r, n=16):
    return [(cx + r * np.cos(t), cz + r * np.sin(t)) for t in np.linspace(0, 2 * np.pi, n, endpoint=False)]


# ---- ala: perfil NACA de 4 cifras calado INC sobre el borde de ataque ----
mC, pC, tC = P.PERFIL
inc = np.radians(P.INC); Z0 = P.Z_ALA + 0.04 * P.C


def perfil(s0, s1, n=14, dz=0.0, solo_extrados=False):
    """Contorno del perfil entre las fracciones de cuerda s0 y s1 (extrados de ida, intrados de vuelta), en (X, Z)."""
    s = s0 + (s1 - s0) * 0.5 * (1 - np.cos(np.linspace(0, np.pi, n)))
    yt = 5 * tC * (0.2969 * np.sqrt(s) - 0.126 * s - 0.3516 * s ** 2 + 0.2843 * s ** 3 - 0.1036 * s ** 4)
    yc = np.where(s < pC, mC / pC ** 2 * (2 * pC * s - s ** 2), mC / (1 - pC) ** 2 * (1 - 2 * pC + 2 * pC * s - s ** 2))
    arriba, abajo = (yc + yt) * P.C + dz, (yc - yt) * P.C
    if solo_extrados: abajo = (yc + yt) * P.C - 0.6           # franja: una lamina fina pegada al extrados
    x = s * P.C
    pts = list(zip(x, arriba)) + list(zip(x[::-1], abajo[::-1]))
    return [(P.X_LE + px * np.cos(inc) + pz * np.sin(inc), Z0 + pz * np.cos(inc) - px * np.sin(inc)) for px, pz in pts]


AL = P.ALERON; sb = AL["bisagra"]; y0a, y1a, semi = AL["y0"], AL["y1"], P.B / 2
ala_partes, alerones = [], []
for lado in (-1, 1):
    for (ya, yb), (s0, s1) in (((0, y0a), (0, 1)), ((y0a, y1a), (0, sb)), ((y1a, semi), (0, 1))):
        a, b = sorted((lado * ya, lado * yb)); ala_partes.append(prisma(perfil(s0, s1), a, b, "y"))
    a, b = sorted((lado * y0a, lado * y1a))
    xb, zb = perfil(sb, sb, n=2)[0]                               # bisagra en el extrados, en la cuerda sb
    al = juntar(prisma(perfil(sb, 1.0, n=8), a, b, "y"), color=0xf2e21b)
    p0 = a_cuerpo([(xb, lado * y0a, zb)])[0]
    al.update(bisagra=np.round(p0, 4).tolist(), eje=[0.0, 1.0, 0.0], signo=1.0 if lado < 0 else -1.0)   # da > 0: el derecho sube
    alerones.append(al)
franja = prisma(perfil(0.33, 0.58, n=10, dz=0.8, solo_extrados=True), -semi, semi, "y")

# ---- fuselaje: caja de foam con el morro redondeado, asiento del ala y tapa de la bateria ----
est = [(0.0, 0.84), (8.0, 0.95), (20.0, 1.0)] + [(x, 1.0) for x in np.linspace(40, P.L, 12)]
anillos = []
for x, k in est:
    w, h, zc = P.fus_seccion(x); w *= k; h *= k
    anillos.append([(x, -w, zc - h), (x, w, zc - h), (x, w, zc + h), (x, -w, zc + h)])
vf, fi = [p for a in anillos for p in a], []
for j in range(len(anillos) - 1):
    for k in range(4):
        a, b = 4 * j + k, 4 * j + (k + 1) % 4
        fi += [a, b, b + 4, a, b + 4, a + 4]
n4 = 4 * (len(anillos) - 1); fi += [0, 1, 2, 0, 2, 3, n4, n4 + 2, n4 + 1, n4, n4 + 3, n4 + 2]
asiento = caja(P.X_LE - 5, P.X_LE + P.C + 5, -P.FUS_W / 2, P.FUS_W / 2, P.FUS_H / 2, P.Z_ALA)

# ---- cola: estabilizador trapezoidal (borde de fuga recto) con la profundidad, y deriva en flecha con el timon ----
te_h = P.HT_XLE + P.HT_C; xh = te_h - (1 - P.ELEV_HINGE) * P.HT_C; sh = P.HT_B / 2
estab = [prisma([(te_h - P.HT_C_RAIZ, 0.0), (xh, 0.0), (xh, lado * sh), (te_h - P.HT_C_PUNTA, lado * sh)],
                P.HT_Z - 2.5, P.HT_Z + 2.5, "z") for lado in (-1, 1)]
prof = juntar(caja(xh, te_h, -sh, sh, P.HT_Z - 2.0, P.HT_Z + 2.0))
te_v = P.FIN_XLE + P.FIN_C; xr = te_v - (1 - P.RUD_HINGE) * P.FIN_C; z_l = P.fus_lomo(xr); z_p = z_l + P.FIN_H
deriva = prisma([(te_v - P.FIN_C_RAIZ, z_l), (xr, z_l), (xr, z_p), (te_v - P.FIN_C_PUNTA, z_p)], -2.5, 2.5, "y")
timon = juntar(caja(xr, te_v, -2.0, 2.0, z_l - 20.0, z_p))

# ---- piezas de otro color: franja negra del ala, tapa, motor, tren y ruedas, patin ----
x_rueda, y_rueda, z_eje, r_rueda = 150.0, 75.0, -P.FUS_H / 2 - 70.0, 28.0
tren = [barra((x_rueda - 25, s * 18, -P.FUS_H / 2), (x_rueda, s * y_rueda, z_eje), 1.5) for s in (-1, 1)]
tren += [barra((x_rueda, s * (y_rueda - 4), z_eje), (x_rueda, s * (y_rueda + 14), z_eje), 1.5) for s in (-1, 1)]
ruedas = [prisma(circulo(x_rueda, z_eje, r_rueda), s * (y_rueda + 4), s * (y_rueda + 22), "y") for s in (-1, 1)]
piezas = [
    juntar(franja, caja(70, 150, -P.FUS_W / 2 + 2, P.FUS_W / 2 - 2, P.FUS_H / 2, P.FUS_H / 2 + 4), color=0x1c1c1c),
    juntar(prisma(circulo(0.0, P.Z_MOTOR, 14.0), -28.0, 0.0, "x"), prisma(circulo(0.0, P.Z_MOTOR, 5.0), -48.0, -28.0, "x"), color=0xb8b8b8),
    juntar(*tren, color=0x3a3a3a),
    juntar(*ruedas, color=0x151515),
    juntar(barra((P.L - 30, 0, P.HT_Z), (P.L - 10, 0, P.HT_Z - 22), 2.5), color=0xd32f2f),
]
malla = dict(fuselaje=juntar((vf, fi), asiento), ala=juntar(*ala_partes), estab=juntar(*estab, deriva), prof=prof,
             bisagra_prof=np.round(a_cuerpo([(xh, 0.0, P.HT_Z)])[0], 4).tolist(),
             timon=timon, bisagra_timon=np.round(a_cuerpo([(xr, 0.0, z_l)])[0], 4).tolist(),
             alerones=alerones, piezas=piezas,
             helice=np.round(a_cuerpo([(-50.0, 0.0, P.Z_MOTOR)])[0], 4).tolist(), helice_r=D_prop / 2)

# =====================================================================
#  FICHERO DEL SIMULADOR
# =====================================================================
v_perd = float(np.sqrt(2 * m_kg * 9.81 / (1.225 * S * 1.0)))
margen = (xnp - x_cg) / P.C * 100
modelo = dict(
    id=ID, nombre=P.NOMBRE, descripcion=P.DESCRIPCION,
    ayuda=("Cuatro canales, como en la emisora: palanca derecha (flechas) profundidad y alerones; palanca izquierda "
           "gas y, de lado (A / D), timón. Inclina con los alerones y tira un poco para virar; el timón sirve para "
           "coordinar y para corregir en la toma. Con el ala plana no se nivela solo: nivélalo tú. Si entra en pérdida, "
           "suelta la profundidad enseguida: cae de ala y, si sigues tirando, entra en barrena."),
    perfil="foam plegado (≈ NACA %d%d%02d)" % (round(mC * 100), round(pC * 10), round(tC * 100)),
    caracteristicas=[["Envergadura", "%.2f m" % (P.B / 1e3)], ["Cuerda", "%.0f mm" % P.C],
                     ["Superficie alar", "%.1f dm²" % (S * 100)], ["Masa en vuelo", "%.0f g" % (m_kg * 1e3)],
                     ["Carga alar", "%.1f g/dm²" % (m_kg * 1e3 / (S * 100))], ["Mandos", P.MANDOS_TXT],
                     ["Motor", "A2208/14T 1400 KV, hélice 8×4 (21 cm), 3S 1300 mAh"], ["Empuje / peso", "%.2f" % (T_g / 1e3 / m_kg)],
                     ["Velocidad de pérdida", "%.1f m/s" % v_perd], ["Crucero (compensado)", "≈ %.0f m/s" % V_CRUCERO],
                     ["Brazo de cola", "400 mm (centro del ala a centro del estabilizador)"],
                     ["Centro de gravedad", "%.0f %% de la cuerda (margen estático %.0f %%)" % ((x_cg - P.X_LE) / P.C * 100, margen)],
                     ["Construcción", "foam, tren fijo de dos ruedas y patín de cola"]],
    S_m2=S, b_m=mod.b, c_m=mod.c, masa_kg=m_kg, cg_mm=iner["cg_mm"],
    inercia=dict(Ixx=iner["Ixx"], Iyy=iner["Iyy"], Izz=iner["Izz"], Ixz=iner["Ixz"]),
    tabla_alfa=tabla, derivadas=derivs, CD0=float(CD0),
    desglose_CD0=dict(ala=float(cd_ala), fuselaje=float(cd_fus), cola=float(cd_cola), tren=float(cd_tren)),
    perdida=perdida, propulsion=prop, mandos=mandos, compensador_grados=0.0,
    lanzamiento=dict(vel_ms=10.0, cabeceo_grados=8.0),     # la perdida esta en ~9,4 m/s: lanzamiento firme y con gas
    malla=malla, punto_neutro_mm=xnp, x_le_mm=P.X_LE,
    colores=dict(fuselaje=0xf2e21b, ala=0xf2e21b, estab=0xf2e21b, moviles=0x1c1c1c),
    origen="Avión real (no impreso): medidas del usuario y estimaciones de scripts/parametros_g1.py",
)
DIR_AV = os.path.join(DIR_DATOS, "vehiculos"); NL = chr(10)
clase = open(os.path.join(AQUI, "clase_g1.js"), encoding="utf-8").read().rstrip()
clase = clase.replace("class ModeloG1 extends", "window.ModeloG1 = window.ModeloG1 || class ModeloG1 extends", 1)
with open(os.path.join(DIR_AV, ID + ".js"), "w", encoding="utf-8") as fj:
    fj.write("// %s. Generado por scripts/modelo_aero_g1.py: no editar a mano." % P.NOMBRE + NL + clase + ";" + NL)
    fj.write("Modelos.registrar(" + json.dumps(modelo, ensure_ascii=False) + ", window.ModeloG1);" + NL)
# indice.js: se anade G1.js (delante del cuadricoptero) sin cambiar el orden de los demas
f_ind = os.path.join(DIR_AV, "indice.js"); txt = open(f_ind, encoding="utf-8").read()
lista = json.loads(txt[txt.index("Modelos.indice(") + 15: txt.rindex(");")])
if ID + ".js" not in lista:
    lista.insert(lista.index("DJI_MINI.js") if "DJI_MINI.js" in lista else len(lista), ID + ".js")
    open(f_ind, "w", encoding="utf-8").write(txt[:txt.index("Modelos.indice(")] + "Modelos.indice(" + json.dumps(lista) + ");" + NL)
res = dict(avion=ID, masa=m_kg, x_cg=x_cg, z_cg=z_cg, x_bateria=x_bat, x_bateria_ideal=x_bat_ideal, HT_INC=HT_INC, xnp=xnp,
           margen_pct=margen, CD0=CD0, inercia=iner, derivadas_alfa2=d2, modos=modos, aleron_sim_grados=da_sim)
json.dump(res, open(os.path.join(AQUI, "..", "analisis", "vlm_resultados_G1.json"), "w"), indent=1, default=float)

# ---- resumen ----
print("%s: %.0f g | CG X %.1f mm (%.1f %% de la cuerda), Z %.1f | bateria en X %.0f%s" % (
    P.NOMBRE, M, x_cg, (x_cg - P.X_LE) / P.C * 100, z_cg, x_bat,
    "" if abs(x_bat - x_bat_ideal) < 0.5 else " (TOPE: para el CG objetivo iria en X %.0f)" % x_bat_ideal))
print("  foam y cinta repartidos: %s g" % {k: round(v) for k, v in REP.items()})
print("  inercias Ixx %.4f Iyy %.4f Izz %.4f Ixz %+.5f kg m2" % (iner["Ixx"], iner["Iyy"], iner["Izz"], iner["Ixz"]))
print("  calado del estabilizador para %.0f m/s con la profundidad neutra: %+.2f grados" % (V_CRUCERO, HT_INC))
print("  punto neutro X %.1f mm -> margen estatico %.1f %% | perdida (CLmax 1,0) %.1f m/s | carga alar %.1f g/dm2"
      % (xnp, margen, v_perd, m_kg * 1e3 / (S * 100)))
print("  CD0 %.4f (ala %.4f, fus %.4f, cola %.4f, tren %.4f) | T/W %.2f" % (CD0, cd_ala, cd_fus, cd_cola, cd_tren, T_g / 1e3 / m_kg))
for t in tabla:
    if t["alfa"] in (-4.0, 0.0, 4.0, 8.0): print("  alfa %+3.0f: CL %.3f CDi %.4f Cm %+.4f" % (t["alfa"], t["CL"], t["CDi"], t["Cm"]))
print("  alfa 2: Clb %+.4f Cnb %+.4f Clp %+.3f Cnr %+.4f Cmq %+.2f Cmde %+.3f | Clda %+.4f Cnda %+.4f | Cndr %+.4f Cldr %+.4f"
      % (d2["Clb"], d2["Cnb"], d2["Clp"], d2["Cnr"], d2["Cmq"], d2["Cmde"], d2["Clda"], d2["Cnda"], d2["Cndr"], d2["Cldr"]))
s = modos["espiral"]
print("  espiral %+.4f 1/s (%s) | holandes %.2f Hz amort. %.2f | aleron con teclado %.1f grados: %.0f grados/s de alabeo a %.0f m/s" % (
    s, ("dobla en %.0f s" % (np.log(2) / s)) if s > 0 else ("se corrige a la mitad en %.0f s" % (np.log(2) / -s)),
    modos["holandes_hz"], modos["holandes_amort"], da_sim, tasa(da_sim), V_CRUCERO))
ntri = sum(len(m["i"]) // 3 for m in [malla["fuselaje"], malla["ala"], malla["estab"], prof, timon] + alerones + piezas)
print("  malla: %d triangulos | %.0f kB" % (ntri, os.path.getsize(os.path.join(DIR_AV, ID + ".js")) / 1024))
