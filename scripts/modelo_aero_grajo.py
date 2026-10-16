"""Exporta el modelo de vuelo del Grajo MX-2 al simulador (simulador/aviones/GRAJO.js). Es un mini UAV lanzado a mano
como el RQ-11B Raven (scripts/parametros_grajo.py: lo publico del real y supuestos marcados), sin piezas impresas.

    python scripts/modelo_aero_grajo.py

Lo que hace, como modelo_aero_g1.py y modelo_aero_xm7.py:
  - masa, CG e inercias con la lista de masas de parametros_grajo.py (la bateria se coloca para el CG)
  - calado del estabilizador para volar a la velocidad de crucero con la profundidad neutra, punto neutro y tablas y
    derivadas del VLM (analisis/vlm_e1.py con ENTRENADOR=GRAJO): ala en poliedro, sin alerones, timon y profundidad
  - resistencia parasita (piel lisa, vaina, botalon, cola, morro de camaras) y helice propulsora de 9" con un motor
    sin escobillas; bateria Li-ion 4S de 5,2 Ah (js/bateria.js)
  - la perdida con mucha profundidad disponible despues: con la profundidad arriba del todo y el motor parado entra en
    perdida profunda estable (~45 grados de senda), que es como aterriza (js/piloto_uav.js, modo ATERRIZAJE sin pista)
  - el piloto automatico (velocidades, alturas y ganancias para un avion de 1,9 kg que vira con el timon)
  - el modelo 3D (vaina con el morro de camaras, ala con su poliedro, pilono, motor y helice propulsora, botalon, cola)
y escribe simulador/aviones/GRAJO.js (clase ModeloAvion: timon y profundidad) y lo anade a simulador/aviones/indice.js.

Ejes cuerpo estandar (x adelante, y derecha, z abajo); coeficientes por radian. La malla va en metros, en ejes cuerpo
con origen en el CG.
"""
import json, os, sys
import numpy as np

os.environ["ENTRENADOR"] = "GRAJO"
AQUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, AQUI); sys.path.insert(0, os.path.join(AQUI, "..", "analisis"))
from avion import ID, P   # noqa: E402
assert ID == "GRAJO"
import vlm_e1 as V        # noqa: E402

DIR_SIM = os.path.join(AQUI, "..", "simulador")
V_CRUCERO = 11.5          # m/s: REAL ~42 km/h (26 mph de la ficha de la USAF)

# =====================================================================
#  MASA, CG E INERCIAS (g y mm)
# =====================================================================
nb, mbat, ybat, zbat = P.BATERIA
fijas = sum(m for _, m, *_ in P.MASAS)
k_rep = (P.MASA_TOTAL - fijas - mbat) / sum(P.REPARTIDAS.values())
REP = {k: v * k_rep for k, v in P.REPARTIDAS.items()}
L_boom = P.L - P.X_TAPER
cuerpos = [
    ("ala", REP["ala"], P.X_LE + 0.42 * P.C, P.Z_ALA + 10.0, (P.C, P.B, 22.0)),
    ("vaina", REP["fuselaje"], 0.45 * P.L_VAINA, 0.0, (P.L_VAINA, P.FUS_W, P.FUS_H)),
    ("botalon", REP["botalon"], P.X_TAPER + 0.5 * L_boom, P.BOOM_ZC, (L_boom, 2 * P.BOOM_R, 2 * P.BOOM_R)),
    ("estabilizador", REP["estab"], P.HT_XLE + 0.5 * P.HT_C, P.HT_Z, (P.HT_C, P.HT_B, 6.0)),
    ("deriva", REP["deriva"], P.FIN_XLE + 0.5 * P.FIN_C, P.fus_lomo(P.FIN_XLE) + 0.5 * P.FIN_H, (P.FIN_C, 6.0, P.FIN_H)),
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
for a in np.arange(-10, 18, 2.0):
    r = mod.resolver(a, V=V_CRUCERO)
    tabla.append(dict(alfa=float(a), CL=r["CL"], CDi=r["CDi"], Cm=r["Cm"] + V.fus_Cm_alfa(mod) * np.radians(a)))
derivs = [dict(alfa=a, **{k: float(v) for k, v in V.derivadas(mod, a, V=V_CRUCERO).items()}) for a in (-6.0, -2.0, 2.0, 6.0, 10.0)]
d2 = derivs[2]
modos = V.modos_laterales(d2, m_kg, iner["Ixx"], iner["Izz"], V_CRUCERO, S, mod.b)

# ---- resistencia parasita: piel lisa de kevlar/vidrio, vaina, botalon, cola y el morro de camaras ----
nu = 1.5e-5
cf = lambda Re: 0.074 / Re ** 0.2
cd_ala = 2 * cf(V_CRUCERO * P.C / 1e3 / nu) * 1.25
xs = np.linspace(0, P.L_VAINA, 80); sec = np.array([P.fus_seccion(x) for x in xs])
moj_fus = np.trapezoid(2 * np.pi * np.sqrt(0.5 * (sec[:, 0] ** 2 + sec[:, 1] ** 2)), xs) / 1e6
cd_fus = cf(V_CRUCERO * P.L_VAINA / 1e3 / nu) * 1.3 * moj_fus / S
cd_boom = cf(V_CRUCERO * L_boom / 1e3 / nu) * 1.1 * (np.pi * 2 * P.BOOM_R * L_boom / 1e6) / S
moj_cola = 2 * (P.HT_B * P.HT_C + P.FIN_C * P.FIN_H) / 1e6
cd_cola = cf(V_CRUCERO * P.HT_C / 1e3 / nu) * 1.1 * moj_cola / S
cd_morro = 0.25 * (P.FUS_W * P.FUS_H / 1e6) * 0.3 / S          # morro romo con las ventanas de las camaras
CD0 = (cd_ala + cd_fus + cd_boom + cd_cola + cd_morro + 0.005) * 1.15   # +0,005 pilono, motor, antenas e interferencias

# ---- helice propulsora de 9" con un motor sin escobillas en 4S: ~1,4 kgf estaticos a 9.800 rpm (SUPUESTO) ----
D_prop, n_max, T_N = P.D_HELICE_MM / 1e3, 9800 / 60, 14.0
CT0 = T_N / 1.225 / n_max ** 2 / D_prop ** 4
prop = dict(T_max_N=T_N, D_m=D_prop, n_max_rps=n_max, CT0=float(CT0), J0=0.75, I_max_A=18.0, P_max_W=260.0,
            masa_bateria_Wh=4 * 3.7 * 5.2, bateria=P.BATERIA_DATOS, downthrust_grados=P.DOWNTHRUST)

# ---- mandos: timon (que hace alabear con el poliedro) y profundidad; recorrido de profundidad grande para la
# perdida profunda ----
mandos = dict(prof_max_grados=12.0, timon_max_grados=25.0, expo=0.30, servo_tau_s=0.05, servo_vel_grados_s=300.0,
              izq_der="timón (vira: el poliedro lo hace alabear)", prof_toma_grados=30.0,
              mecanico=dict(prof=30.0, timon=30.0),
              nota="de > 0 = profundidad abajo; dr > 0 = timon a la derecha. Sin alerones. Para la toma, el piloto "
                   "automatico sube la profundidad hasta prof_toma_grados (perdida profunda)")
# perdida: ala de alargamiento 6 con perfil fino de velero a Re ~1,5e5: CLmax 3D ~1,1, a ~9 grados de fuselaje. Tras la
# perdida la cola (en el botalon, lejos de la estela del ala) sigue mandando bastante: la perdida profunda se sostiene
perdida = dict(alfa_perdida_grados=9.0, anchura_grados=3.0, alfa_perdida_neg_grados=-9.0,
               CL_placa_factor=0.85, mando_post_perdida=0.7)

# =====================================================================
#  MODELO 3D
# =====================================================================
def a_cuerpo(v):
    v = np.asarray(v, float)
    return np.c_[-(v[:, 0] - x_cg), v[:, 1], -(v[:, 2] - z_cg)] / 1e3


GRIS, OSCURO, NEGRO, CRISTAL, VERDE = 0x6f7568, 0x2b2f33, 0x141618, 0x0d1a24, 0x5d6650


def juntar(*partes, color=None, suave=False):
    v, i = [], []
    for pv, pi in partes:
        i += [k + len(v) for k in pi]; v += list(pv)
    m = dict(v=np.round(a_cuerpo(v), 4).ravel().tolist(), i=[int(k) for k in i])
    if color is not None: m["color"] = color
    if suave: m["suave"] = True
    return m


def anillos(secciones, n=20, cerrar=(True, True)):
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
    r1 = r0 if r1 is None else r1
    p0, p1 = np.asarray(p0, float), np.asarray(p1, float); d = p1 - p0; Ld = np.linalg.norm(d); d /= Ld
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
    v, i = [], []
    for f in np.linspace(np.arcsin(z0), np.arcsin(z1), m + 1):
        v += [(c[0] + r * np.cos(f) * np.cos(t), c[1] + r * np.cos(f) * np.sin(t), c[2] + r * np.sin(f)) for t in np.linspace(0, 2 * np.pi, n, endpoint=False)]
    for j in range(m):
        for k in range(n):
            a, b = j * n + k, j * n + (k + 1) % n
            i += [a, b, n + b, a, n + b, n + a]
    return v, i


def perfil_pts(perfil, n=16, s0=0.0, s1=1.0):
    m_, p_, t_ = perfil
    s = s0 + (s1 - s0) * 0.5 * (1 - np.cos(np.linspace(0, np.pi, n)))
    yt = 5 * t_ * (0.2969 * np.sqrt(s) - 0.126 * s - 0.3516 * s ** 2 + 0.2843 * s ** 3 - 0.1036 * s ** 4)
    yc = np.where(s < p_, m_ / p_ ** 2 * (2 * p_ * s - s ** 2), m_ / (1 - p_) ** 2 * (1 - 2 * p_ + 2 * p_ * s - s ** 2)) if m_ > 0 else 0 * s
    return list(zip(s, yc + yt)) + list(zip(s[::-1], (yc - yt)[::-1]))


def superficie(perfil, cuerda, xle, z, y0, y1, inc=0.0, diedro=0.0, s0=0.0, s1=1.0, n=16, cuerda1=None, eje="y", yz0=0.0):
    """Superficie con perfil entre y0 e y1 (eje "y": horizontal, con diedro que sube desde |y| = yz0; eje "z":
    vertical). Cuerda constante o de cuerda (en y0) a cuerda1 (en y1), con el borde de fuga recto."""
    c1 = cuerda if cuerda1 is None else cuerda1
    pts = perfil_pts(perfil, n, s0, s1); k = len(pts); a = np.radians(inc); t = np.tan(np.radians(diedro))
    v = []
    for y, c in ((y0, cuerda), (y1, c1)):
        x0 = xle + (cuerda - c)
        for s, zz in pts:
            px, pz = s * c, zz * c
            X = x0 + px * np.cos(a) + pz * np.sin(a); Zs = pz * np.cos(a) - px * np.sin(a)
            v.append((X, y, z + Zs + max(0.0, abs(y) - yz0) * t) if eje == "y" else (X, Zs, y))
    i = []
    for j in range(k):
        jj = (j + 1) % k; i += [j, k + j, k + jj, j, k + jj, jj]
    c0 = len(v); v.append(tuple(np.mean(v[:k], axis=0))); c1_ = len(v); v.append(tuple(np.mean(v[k:2 * k], axis=0)))
    for j in range(k): jj = (j + 1) % k; i += [c0, jj, j, c1_, k + j, k + jj]
    return v, i


def caja(x0, x1, y0, y1, z0, z1):
    v = [(x, y, z) for z in (z0, z1) for y in (y0, y1) for x in (x0, x1)]
    i = []
    for a, b, c, d in [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]: i += [a, b, c, a, c, d]
    return v, i


# ---- piezas lisas: secciones superelipticas a lo largo de X y superficies con perfil por estaciones ----
def superelipse(w, h, e=2.0, n=32):
    """Contorno de una superelipse (e = 2 elipse; mas, cantos mas cuadrados) de semiejes w (Y) y h (Z)."""
    t = np.linspace(0, 2 * np.pi, n, endpoint=False)
    c, s = np.cos(t), np.sin(t)
    return [(w * np.sign(ci) * abs(ci) ** (2 / e), h * np.sign(si) * abs(si) ** (2 / e)) for ci, si in zip(c, s)]


def cuerpo(secciones, n=32, cerrar=(True, True)):
    """Cuerpo liso: secciones [(X, semiancho, semialto, Zc, e)] unidas por franjas, con tapas si se piden."""
    v, i = [], []
    for x, w, h, zc, e in secciones:
        v += [(x, y, zc + z) for y, z in superelipse(w, h, e, n)]
    for j in range(len(secciones) - 1):
        for k in range(n):
            a, b = j * n + k, j * n + (k + 1) % n
            i += [a, n + b, b, a, n + a, n + b]
    for extremo, cierra in ((0, cerrar[0]), (len(secciones) - 1, cerrar[1])):
        if not cierra: continue
        x, w, h, zc, e = secciones[extremo]; c = len(v); v.append((x, 0.0, zc)); base = extremo * n
        for k in range(n):
            a, b = base + k, base + (k + 1) % n
            i += [c, b, a] if extremo == 0 else [c, a, b]
    return v, i


def loft(estaciones, perfil, n=28, eje="y", tapas=True):
    """Superficie con perfil por estaciones. eje "y" (ala, estabilizador): estaciones (y, x_borde_ataque, cuerda, z,
    calado); eje "z" (deriva): estaciones (z, x_borde_ataque, cuerda, y). Franjas entre estaciones y tapas."""
    pts = perfil_pts(perfil, n); k = len(pts); v = []
    for est in estaciones:
        if eje == "y":
            y, xle, c, z, inc = est; a = np.radians(inc)
            v += [(xle + s * c * np.cos(a) + zz * c * np.sin(a), y, z + zz * c * np.cos(a) - s * c * np.sin(a)) for s, zz in pts]
        else:
            z, xle, c, y = est
            v += [(xle + s * c, y + zz * c, z) for s, zz in pts]
    i = []
    for j in range(len(estaciones) - 1):
        for q in range(k):
            qq = (q + 1) % k; a0, a1 = j * k + q, j * k + qq
            i += [a0, a0 + k, a1 + k, a0, a1 + k, a1]
    if tapas:
        for j in (0, len(estaciones) - 1):
            c = len(v); v.append(tuple(np.mean(v[j * k:(j + 1) * k], axis=0)))
            for q in range(k):
                qq = (q + 1) % k; i += [c, j * k + qq, j * k + q] if j == 0 else [c, j * k + q, j * k + qq]
    return v, i


def punta_redonda(y0, y1, xle0, c0, z_de_y, inc, n_est=7, ataque=0.55):
    """Estaciones de una punta redondeada (elipse) de y0 a y1: la cuerda baja de c0 a casi nada; el borde de ataque
    retrocede una fraccion `ataque` de lo que se acorta (el resto, el de fuga)."""
    est = []
    for f in np.linspace(0, 1, n_est):
        c = max(0.06 * c0, c0 * np.sqrt(max(0.0, 1 - f ** 2)))
        y = y0 + f * (y1 - y0)
        est.append((y, xle0 + ataque * (c0 - c), c, z_de_y(y), inc))
    return est


# ---- vaina: morro de camaras (desmontable, de otro color), cuerpo de cantos redondeados y cola hacia el botalon ----
def sec_vaina(x):
    w, h, zc = P.fus_seccion(x)
    e = 2.0 + 1.2 * min(1.0, max(0.0, (x - 40) / 120)) * (1 - min(1.0, max(0.0, (x - P.X_TAPER) / (P.L_VAINA - P.X_TAPER))))
    return (float(x), w, h, zc, e)


xs_m = [0.0, 2.0, 6.0, 12.0, 20.0, 30.0, 44.0, 60.0, 80.0, 98.0, P.X_MORRO]
morro = cuerpo([sec_vaina(x) for x in xs_m], n=36, cerrar=(True, False))
xs_v = [P.X_MORRO, P.X_MORRO + 4] + list(np.linspace(P.X_MORRO + 20, P.X_TAPER, 8)) + list(np.linspace(P.X_TAPER + 15, P.L_VAINA, 7))
vaina = cuerpo([sec_vaina(x) for x in xs_v], n=36, cerrar=(False, True))
junta_morro = cuerpo([(P.X_MORRO - 1.5,) + sec_vaina(P.X_MORRO)[1:3] + (sec_vaina(P.X_MORRO)[3], sec_vaina(P.X_MORRO)[4]),
                      (P.X_MORRO + 1.5,) + tuple(1.012 * q for q in sec_vaina(P.X_MORRO)[1:3]) + sec_vaina(P.X_MORRO)[3:]], n=36, cerrar=(False, False))
junta_morro = ([(x, y * 1.01, z) for x, y, z in junta_morro[0]], junta_morro[1])
# ventanas de las camaras: frontal (en la punta) y lateral (a la izquierda), como cristales oscuros con su marco
ventanas = [esfera((5.0, 0.0, -12.0), 14.0, n=20, m=10, z0=-1, z1=1), esfera((58.0, -P.FUS_W / 2 + 6, -14.0), 12.0, n=18, m=8)]
marcos = [tubo((7.0, 0, -12.0), (1.0, 0, -12.0), 17.0, 16.0, n=20, tapas=False), tubo((58.0, -P.FUS_W / 2 + 9, -14.0), (58.0, -P.FUS_W / 2 + 2, -14.0), 15.0, 14.0, n=18, tapas=False)]
# carenado del ala sobre la vaina (el asiento del ala) y tapa de la bateria con sus cierres
asiento = cuerpo([(P.X_LE - 30 + d, 0.36 * P.FUS_W * f, 10.0 * f, P.FUS_H / 2 - 4 + 6 * f, 2.6) for d, f in
                  ((0, 0.2), (20, 0.8), (50, 1.0), (P.C - 10, 1.0), (P.C + 20, 0.7), (P.C + 45, 0.15))], n=24)
tapa = [caja(140.0, 255.0, -P.FUS_W / 2 + 6, P.FUS_W / 2 - 6, -P.FUS_H / 2 - 1.2, -P.FUS_H / 2 + 0.5)]
cierres = [tubo((s, 0, -P.FUS_H / 2 - 1.5), (s, 0, -P.FUS_H / 2 - 4), 6.0, n=10) for s in (150.0, 245.0)]
# ---- botalon de carbono con sus anclajes ----
botalon = [tubo((P.L_VAINA - 40, 0, P.BOOM_ZC), (P.L - 20, 0, P.BOOM_ZC), P.BOOM_R, 7.5, n=20, tapas=False),
           cuerpo([(P.L - 20, 7.5, 7.5, P.BOOM_ZC, 2.0), (P.L - 4, 6.0, 6.0, P.BOOM_ZC, 2.0), (P.L + 4, 2.0, 2.0, P.BOOM_ZC, 2.0)], n=16, cerrar=(False, True))]
anclajes = [tubo((P.L_VAINA - 45, 0, P.BOOM_ZC), (P.L_VAINA - 10, 0, P.BOOM_ZC), P.BOOM_R + 3.5, n=20),
            tubo((P.HT_XLE - 8, 0, P.BOOM_ZC), (P.HT_XLE + 30, 0, P.BOOM_ZC), P.BOOM_R + 2.5, n=20)]
# ---- ala: tramo central plano, puntas en poliedro (desmontables) con la punta redondeada ----
semi = P.B / 2; yq = P.QUIEBRO; td = np.tan(np.radians(P.DIEDRO))
z_ala = lambda y: P.Z_ALA + max(0.0, abs(y) - yq) * td
ala_p = [loft([(-yq, P.X_LE, P.C, P.Z_ALA, P.INC), (0.0, P.X_LE, P.C, P.Z_ALA, P.INC), (yq, P.X_LE, P.C, P.Z_ALA, P.INC)], P.PERFIL, n=30, tapas=False)]
juntas = []
for lado in (-1, 1):
    y_r = semi - 75.0                                   # empieza el redondeo de la punta
    est = [(lado * yq, P.X_LE, P.C, z_ala(yq), P.INC), (lado * (yq + 120), P.X_LE, P.C, z_ala(yq + 120), P.INC),
           (lado * y_r, P.X_LE, P.C, z_ala(y_r), P.INC)]
    est += [(lado * y, x, c, z, i_) for y, x, c, z, i_ in punta_redonda(y_r, semi, P.X_LE, P.C, z_ala, P.INC)[1:]]
    if lado < 0: est = est[::-1]
    ala_p.append(loft(est, P.PERFIL, n=30, tapas=False))
    juntas.append(loft([(lado * yq - 2.5, P.X_LE - 1, P.C + 2, P.Z_ALA + 0.4, P.INC), (lado * yq + 2.5, P.X_LE - 1, P.C + 2, z_ala(yq + 2.5) + 0.4, P.INC)][::lado], P.PERFIL, n=24))
# ---- pilono, motor con aletas de refrigeracion, cono y helice bipala con torsion ----
pilono = loft([(P.FUS_H / 2 - 18, 500.0, 62.0, 0.0), (P.FUS_H / 2 + 10, 512.0, 52.0, 0.0), (P.Z_MOTOR - 10, 524.0, 38.0, 0.0)], (0, 0.4, 0.22), n=22, eje="z")
aletas = []
for k, x in enumerate(np.linspace(536.0, 566.0, 7)):
    r = 17.5 if k % 2 == 0 else 15.5
    aletas.append(tubo((x, 0, P.Z_MOTOR), (x + 4.2, 0, P.Z_MOTOR), r, n=24, tapas=False))
motor = [tubo((530.0, 0, P.Z_MOTOR), (P.X_HELICE - 10, 0, P.Z_MOTOR), 15.0, 14.0, n=24), tubo((524.0, 0, P.Z_MOTOR), (530.0, 0, P.Z_MOTOR), 10.0, 15.0, n=24)]
cono = cuerpo([(P.X_HELICE - 10, 13.0, 13.0, P.Z_MOTOR, 2.0), (P.X_HELICE + 2, 12.5, 12.5, P.Z_MOTOR, 2.0), (P.X_HELICE + 12, 9.0, 9.0, P.Z_MOTOR, 2.0),
               (P.X_HELICE + 20, 4.0, 4.0, P.Z_MOTOR, 2.0), (P.X_HELICE + 24, 0.5, 0.5, P.Z_MOTOR, 2.0)], n=24, cerrar=(True, True))
R_h = P.D_HELICE_MM / 2
palas = []
for s in (-1, 1):                                       # pala con perfil, cuerda ancha cerca del buje y punta redonda; torsion de paso fijo
    v_, i_ = [], []
    radios = [12.0, 20.0, 35.0, 55.0, 75.0, 90.0, 100.0, 107.0, R_h - 1.5, R_h]
    pts = perfil_pts((0.04, 0.4, 0.10), 16); k = len(pts)
    for r in radios:
        c = 18.0 * (1 - 0.55 * (r / R_h) ** 2) * (np.sqrt(max(0.05, 1 - ((r - 100) / 15) ** 2)) if r > 100 else 1.0)
        th = np.arctan(0.152 / (2 * np.pi * r / 1e3))      # paso de 6" (152 mm)
        d = np.array([np.sin(th), 0, -s * np.cos(th)]); nn = np.array([np.cos(th), 0, s * np.sin(th)])
        ctr = np.array([P.X_HELICE + 2, s * r, P.Z_MOTOR])
        v_ += [tuple(ctr + (sx - 0.35) * c * d + zz * c * nn) for sx, zz in pts]
    for j in range(len(radios) - 1):
        for q in range(k):
            qq = (q + 1) % k; a0, a1 = j * k + q, j * k + qq
            i_ += [a0, a0 + k, a1 + k, a0, a1 + k, a1]
    palas.append((v_, i_))
# ---- cola: estabilizador trapezoidal con puntas redondeadas y la profundidad; deriva en flecha con el timon ----
te_h = P.HT_XLE + P.HT_C; xh = te_h - (1 - P.ELEV_HINGE) * P.HT_C; sh = P.HT_B / 2
def estab_est(s0, s1, signo):
    c_raiz, c_punta = P.HT_C * 1.12, P.HT_C * 0.78
    est = []
    for f in np.linspace(0, 1, 5):
        y = f * (sh - 25); c = c_raiz + (c_punta - c_raiz) * f; xle = te_h - c
        est.append((signo * y, xle + s0 * c, (s1 - s0) * c, P.HT_Z, 0.0))
    for y, x, c, z, i_ in punta_redonda(sh - 25, sh, te_h - c_punta, c_punta, lambda y: P.HT_Z, 0.0, n_est=5, ataque=0.8)[1:]:
        est.append((signo * y, x + s0 * c, (s1 - s0) * c, z, 0.0))
    return est if signo > 0 else est[::-1]
perf_cola = (0, 0.4, 0.08)
estab = [loft(estab_est(0.0, P.ELEV_HINGE - 0.02, -1)[::-1][::-1], perf_cola, n=18, tapas=False), loft(estab_est(0.0, P.ELEV_HINGE - 0.02, 1), perf_cola, n=18, tapas=False)]
prof = juntar(loft(estab_est(P.ELEV_HINGE, 1.0, -1), perf_cola, n=12, tapas=True), loft(estab_est(P.ELEV_HINGE, 1.0, 1), perf_cola, n=12, tapas=True), color=GRIS)
te_v = P.FIN_XLE + P.FIN_C; xr = te_v - (1 - P.RUD_HINGE) * P.FIN_C; z_l = P.fus_lomo(P.FIN_XLE + 0.5 * P.FIN_C)
def deriva_est(s0, s1):
    est = []
    for f in np.linspace(0, 1, 6):
        z = z_l - 3 + f * (P.FIN_H - 25); c = P.FIN_C * (1.15 - 0.45 * f); xle = te_v - c
        est.append((z, xle + s0 * c, (s1 - s0) * c, 0.0))
    for g in (0.45, 0.75, 0.93, 1.0):                   # tope redondeado
        c = P.FIN_C * 0.7 * np.sqrt(max(0.02, 1 - g ** 2)); z = z_l - 3 + P.FIN_H - 25 + g * 25; xle = te_v - c - 0.4 * (P.FIN_C * 0.7 - c)
        est.append((z, xle + s0 * c, max(1.0, (s1 - s0) * c), 0.0))
    return est
deriva = loft(deriva_est(0.0, P.RUD_HINGE - 0.02), perf_cola, n=18, eje="z")
timon = juntar(loft(deriva_est(P.RUD_HINGE, 1.0), perf_cola, n=12, eje="z"), color=GRIS)
timon.update(bisagra=np.round(a_cuerpo([(xr, 0.0, z_l)])[0], 4).tolist(), eje=[0.0, 0.0, 1.0], signo=-1.0, timon=True)
# ---- varillas y bocinas de mando, antenas del enlace y GPS ----
varillas = [tubo((470.0, 6, P.BOOM_ZC + 8), (xh - 6, 6, P.HT_Z + 4), 1.2, n=6), tubo((470.0, -6, P.BOOM_ZC + 8), (xr - 4, -4, z_l + 14), 1.2, n=6)]
bocinas = [caja(xh - 2, xh + 6, 4, 8, P.HT_Z, P.HT_Z + 12), caja(xr - 2, xr + 6, -8, -4, z_l + 6, z_l + 18)]
antenas = [tubo((395.0, 0, P.FUS_H / 2 - 4), (405.0, 0, P.FUS_H / 2 + 110), 2.2, 1.2, n=8), tubo((395.0, 0, P.FUS_H / 2 - 4), (395.0, 0, P.FUS_H / 2 + 8), 5.0, n=10)]
z_gps = P.Z_ALA + 0.06 * P.C + 8                          # sobre el extrados del tramo central, encima del CG
gps = [cuerpo([(P.X_LE + 70, 10, 3, z_gps, 2.0), (P.X_LE + 73, 14, 5, z_gps + 2, 2.0), (P.X_LE + 97, 14, 5, z_gps + 2, 2.0), (P.X_LE + 100, 10, 3, z_gps, 2.0)], n=24, cerrar=(True, True))]

# ---- morro orientable (como la modernizacion DDL): bola estabilizada bajo el morro, con su ventana; la camara fija va en
# las ventanas del morro (frontal y lateral izquierda), sujeta al avion ----
TC = (62.0, 0.0, -P.FUS_H / 2 - 22.0)
yugo_t = [tubo((TC[0], 0, -P.FUS_H / 2 + 6), (TC[0], 0, TC[2] + 16), 16.0, 13.0, n=20)]
bola_t = esfera(TC, 25.0, n=28, m=16)
ventana_t = [esfera((TC[0] + 23.0, 0.0, TC[2]), 9.0, n=16, m=8)]
malla = dict(fuselaje=juntar(vaina, asiento, color=GRIS, suave=True), ala=juntar(*ala_p, color=GRIS, suave=True),
             estab=juntar(*estab, deriva, color=GRIS, suave=True), prof=dict(prof, suave=True),
             bisagra_prof=np.round(a_cuerpo([(xh, 0.0, P.HT_Z)])[0], 4).tolist(),
             alerones=[dict(timon, suave=True)],
             piezas=[juntar(morro, color=VERDE, suave=True), juntar(*ventanas, color=CRISTAL, suave=True),
                     juntar(junta_morro, *marcos, *juntas, *tapa, *cierres, color=OSCURO),
                     juntar(*botalon, color=NEGRO, suave=True), juntar(*anclajes, color=OSCURO, suave=True),
                     juntar(pilono, color=GRIS, suave=True), juntar(*motor, *aletas, cono, color=OSCURO, suave=True),
                     juntar(*palas, color=NEGRO, suave=True), juntar(*gps, color=0xc9ccc4, suave=True), juntar(*varillas, *bocinas, *antenas, color=NEGRO)],
             torreta=dict(juntar(bola_t, color=OSCURO, suave=True), centro=np.round(a_cuerpo([TC])[0], 4).tolist(),
                          ventanas=juntar(*ventana_t, color=CRISTAL, suave=True), yugo=juntar(*yugo_t, color=OSCURO, suave=True)),
             cam_fija=dict(pos=np.round(a_cuerpo([(4.0, 0.0, -12.0)])[0], 4).tolist(), frontal=[0.0, -15.0], lateral=[-90.0, -35.0]),
             helice=np.round(a_cuerpo([(P.X_HELICE, 0.0, P.Z_MOTOR)])[0], 4).tolist(), helice_r=D_prop / 2)

# =====================================================================
#  FICHERO DEL SIMULADOR
# =====================================================================
CLmax = float(max(t["CL"] for t in tabla if t["alfa"] <= perdida["alfa_perdida_grados"]))
v_perd = float(np.sqrt(2 * m_kg * 9.81 / (1.225 * S * CLmax)))
margen = (xnp - x_cg) / P.C * 100
modelo = dict(
    id=ID, nombre=P.NOMBRE, descripcion=P.DESCRIPCION, uav=True, lanzado_a_mano=True,
    categoria="1,9 kg, mini UAS militar (clase I, lanzado a mano)",
    ayuda=("Se lanza a mano: L lo lanza con el motor a tope y el piloto automático sube solo (modo Lanzamiento). M cambia "
           "de modo (manual, estabilizado, crucero), un clic en el mapa va a ese punto y da vueltas sobre él, H vuelve "
           "a casa y P aterriza: va al punto de toma contra el viento y entra en pérdida profunda. Sin alerones: vira con "
           "el timón (flechas izquierda / derecha) y el poliedro del ala lo hace alabear. Cámaras (cámara 3): con el morro "
           "fijo, V cambia entre la frontal y la lateral; con el orientable, flechas con Mayúsculas y Q / E. C infrarroja, "
           "Z / X zoom y F foto."),
    perfil="NACA %d%d%02d (fino de velero)" % (round(P.PERFIL[0] * 100), round(P.PERFIL[1] * 10), round(P.PERFIL[2] * 100)),
    caracteristicas=[["Envergadura", "%.2f m" % (P.B / 1e3)], ["Longitud", "%.2f m" % (P.L / 1e3)],
                     ["Superficie alar", "%.1f dm²" % (S * 100)], ["Peso", "%.1f kg (%.1f con la cámara orientable)" % (m_kg, m_kg + 0.3)],
                     ["Carga alar", "%.0f g/dm²" % (m_kg * 1e3 / (S * 100))], ["Mandos", P.MANDOS_TXT],
                     ["Motor", "sin escobillas, hélice propulsora de 9\""], ["Batería", "Li-ion 4S 5200 mAh (77 Wh): 60-90 min"],
                     ["Velocidad de pérdida", "%.0f km/h (%.1f m/s)" % (v_perd * 3.6, v_perd)],
                     ["Crucero", "%.0f km/h" % (V_CRUCERO * 3.6)], ["Altura de trabajo", "30-150 m sobre el suelo"],
                     ["Lanzamiento y toma", "a mano; toma en pérdida profunda en un punto"],
                     ["Carga útil", "cámaras de color e infrarroja (frontal y lateral) o torreta orientable"],
                     ["Centro de gravedad", "%.0f %% de la cuerda (margen estático %.0f %%)" % ((x_cg - P.X_LE) / P.C * 100, margen)]],
    S_m2=S, b_m=mod.b, c_m=mod.c, masa_kg=m_kg, cg_mm=iner["cg_mm"],
    inercia=dict(Ixx=iner["Ixx"], Iyy=iner["Iyy"], Izz=iner["Izz"], Ixz=iner["Ixz"]),
    tabla_alfa=tabla, derivadas=derivs, CD0=float(CD0),
    desglose_CD0=dict(ala=float(cd_ala), vaina=float(cd_fus), botalon=float(cd_boom), cola=float(cd_cola), morro=float(cd_morro)),
    perdida=perdida, propulsion=prop, mandos=mandos, compensador_grados=0.0,
    lanzamiento=dict(vel_ms=11.5, cabeceo_grados=10.0),     # REAL: se lanza a mano, contra el viento, con carrerilla y el motor a tope
    I_helice=0.012 * D_prop ** 2 / 12, k_perfil=0.02, brazo_perdida=0.2,
    chorro=dict(prof=0.0, timon=0.0, deriva=0.0),            # helice propulsora: la cola no esta en su estela
    # toma en perdida profunda: la toca con mucha velocidad vertical (diseñada para eso) y puede soltarse alguna pieza
    toma_perdida=dict(alfa_min=20.0, vz_max_ms=9.5, vel_max_ms=8.0),
    # carga util (REAL): morro fijo con las camaras de color e infrarroja frontal y lateral (sin zoom optico: el digital
    # de la estacion) o el orientable de la modernizacion (torreta estabilizada, 0,3 kg mas). Se elige en el Hangar
    camara=dict(zoom=[1, 2, 4], zoom_optico=1, termica=True, morros=["fijo", "orientable"], masa_orientable_kg=0.3),
    piloto=dict(v_min=10.5, v_alarma=10.5, v_max=20.0, v_crucero=12.0, v_aprox=12.5, alfa_max=7.5, k_alfa=1.5,
                alabeo_max=30.0, cabeceo_max=14.0, cabeceo_min=-12.0, cabeceo_crucero=2.0, cabeceo_subida=12.0,
                h_min=30.0, h_base=90.0, h_fin_despegue=30.0, vz_max=3.0, radio_orbita=80.0, k_orbita=40.0,
                giro_consigna=20.0, subida_consigna=3.0,
                pitot=True, timon_alabeo=True, k_alabeo=0.8, k_p=0.2, k_cabeceo=1.5, k_q=0.8, k_i_cabeceo=1.0, k_derrape=0.0, k_r=0.8,
                k_rumbo=1.0, k_altura=0.2, k_vz=0.05, k_gas=0.3, k_gas_vz=0.1, k_i_gas=0.05, gas_crucero=0.5,
                toma=dict(h_entrada=30.0, d_final=150.0, h_perdida=18.0, prof=1.0)),
    malla=malla, punto_neutro_mm=xnp, x_le_mm=P.X_LE,
    colores=dict(fuselaje=GRIS, ala=GRIS, estab=GRIS, moviles=GRIS),
    origen="Como el RQ-11B Raven (lo público del real y supuestos de scripts/parametros_grajo.py); sin marcas",
)
DIR_AV = os.path.join(DIR_SIM, "aviones"); NL = chr(10)
with open(os.path.join(DIR_AV, ID + ".js"), "w", encoding="utf-8") as fj:
    fj.write("// %s. Generado por scripts/modelo_aero_grajo.py: no editar a mano." % P.NOMBRE + NL)
    fj.write("Modelos.registrar(" + json.dumps(modelo, ensure_ascii=False) + ");" + NL)
f_ind = os.path.join(DIR_AV, "indice.js"); txt = open(f_ind, encoding="utf-8").read()
lista = json.loads(txt[txt.index("Modelos.indice(") + 15: txt.rindex(");")])
if ID + ".js" not in lista:
    lista.insert(lista.index("DJI_MINI.js") if "DJI_MINI.js" in lista else len(lista), ID + ".js")
    open(f_ind, "w", encoding="utf-8").write(txt[:txt.index("Modelos.indice(")] + "Modelos.indice(" + json.dumps(lista) + ");" + NL)
res = dict(avion=ID, masa=m_kg, x_cg=x_cg, z_cg=z_cg, x_bateria=x_bat, x_bateria_ideal=x_bat_ideal, HT_INC=HT_INC, xnp=xnp,
           margen_pct=margen, CD0=CD0, inercia=iner, derivadas_alfa2=d2, modos=modos, v_perdida=v_perd)
json.dump(res, open(os.path.join(AQUI, "..", "analisis", "vlm_resultados_GRAJO.json"), "w"), indent=1, default=float)

print("%s: %.2f kg | CG X %.0f mm (%.1f %% de la cuerda), Z %.0f | bateria en X %.0f%s" % (
    P.NOMBRE, m_kg, x_cg, (x_cg - P.X_LE) / P.C * 100, z_cg, x_bat,
    "" if abs(x_bat - x_bat_ideal) < 0.5 else " (TOPE: para el CG objetivo iria en X %.0f)" % x_bat_ideal))
print("  estructura repartida: %s g" % {k: round(v) for k, v in REP.items()})
print("  inercias Ixx %.4f Iyy %.4f Izz %.4f Ixz %+.5f kg m2" % (iner["Ixx"], iner["Iyy"], iner["Izz"], iner["Ixz"]))
print("  calado del estabilizador para %.1f m/s con la profundidad neutra: %+.2f grados" % (V_CRUCERO, HT_INC))
print("  punto neutro X %.0f mm -> margen estatico %.1f %% | CLmax %.2f -> perdida %.1f m/s (%.0f km/h) | carga alar %.0f g/dm2"
      % (xnp, margen, CLmax, v_perd, v_perd * 3.6, m_kg * 1e3 / (S * 100)))
print("  CD0 %.4f (ala %.4f, vaina %.4f, botalon %.4f, cola %.4f, morro %.4f) | T/W %.2f"
      % (CD0, cd_ala, cd_fus, cd_boom, cd_cola, cd_morro, T_N / (m_kg * 9.81)))
for t in tabla:
    if t["alfa"] in (-4.0, 0.0, 4.0, 8.0, 12.0, 16.0): print("  alfa %+3.0f: CL %.3f CDi %.4f Cm %+.4f" % (t["alfa"], t["CL"], t["CDi"], t["Cm"]))
print("  alfa 2: Clb %+.4f Cnb %+.4f Clp %+.3f Cnr %+.4f Cmq %+.2f Cmde %+.3f | Cndr %+.4f Cldr %+.4f"
      % (d2["Clb"], d2["Cnb"], d2["Clp"], d2["Cnr"], d2["Cmq"], d2["Cmde"], d2["Cndr"], d2["Cldr"]))
s = modos["espiral"]
print("  espiral %+.4f 1/s (%s) | holandes %.2f Hz amort. %.2f" % (
    s, ("dobla en %.0f s" % (np.log(2) / s)) if s > 0 else ("se corrige a la mitad en %.0f s" % (np.log(2) / -s)),
    modos["holandes_hz"], modos["holandes_amort"]))
ntri = sum(len(m["i"]) // 3 for m in [malla["fuselaje"], malla["ala"], malla["estab"], malla["prof"]] + malla["alerones"] + malla["piezas"])
print("  malla: %d triangulos | %.0f kB" % (ntri, os.path.getsize(os.path.join(DIR_AV, ID + ".js")) / 1024))
