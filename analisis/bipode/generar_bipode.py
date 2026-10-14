"""Bipode de asalto HQ-07 (vehiculo secreto del hangar): genera su modelo 3D y lo escribe como DATOS COMUNES de los
dos simuladores en simulador/aviones/BIPODE.js (entre las marcas // <DATOS> y // </DATOS>) y las calcomanias en
simulador/aviones/BIPODE_calcas.png. El navegador (BIPODE.js) y Godot (modelo_bipode_3d.gd) solo decodifican estas
mallas: la geometria es la misma en los dos por construccion.

Geometria: todo procedural (sin ficheros de malla). Placas de blindaje como cajas biseladas (con aristas redondeadas y
normales suaves: brillos en los cantos) que se pueden estrechar, piezas de torno (cilindros, cañones con su anima,
remaches, tornillos, pistones, toberas), tubos a lo largo de curvas (latiguillos y cables) y cadenas (la cinta de
municion). Por vértice se guarda: posición (int16, 0,1 mm, relativa al pivote de su pieza), normal (int8), material,
curvatura (convexo + / concavo -: desconchones de pintura en los cantos, mugre en los rincones), oclusion ambiental
calculada aqui con un voxelizado del modelo entero (3 cm) y la altura sobre el suelo en reposo (mugre de abajo) y UV
(solo las calcomanias).

Ejes: cuerpo NED como el resto de vehiculos (x adelante, y derecha, z abajo; metros), origen en el suelo bajo la
cadera. Piezas articuladas: pelvis -> cintura (gira 360 grados) -> torso -> hombros (brazos: cañon rotativo a la
derecha, puño a la izquierda) y pelvis -> cadera -> muslo -> rodilla -> espinilla -> tobillo -> pie, en cada pierna.

Paso: tabla de 64 fases del ciclo (dos pasos) con los angulos de cadera, rodilla y tobillo de cada pierna (cinematica
inversa con el pie plano apoyado), el sube y baja y el balanceo de la pelvis.

Uso: python analisis/bipode/generar_bipode.py
"""
import base64, json, math, os, re
import numpy as np
from PIL import Image, ImageDraw, ImageFont

RAIZ = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
F_JS = os.path.join(RAIZ, "simulador", "aviones", "BIPODE.js")
F_PNG = os.path.join(RAIZ, "simulador", "aviones", "BIPODE_calcas.png")

# ---------------------------------------------------------------- materiales
# nombre, color (sRGB), rugosidad, metalico. El sombreador les pone el desgaste.
MATERIALES = [
    ["pintura_amarilla", 0xD9A514, 0.55, 0.0],   # 0
    ["metal_oscuro", 0x2B2B2D, 0.42, 0.85],      # 1
    ["pintura_roja", 0x9E1A16, 0.5, 0.0],        # 2
    ["laton", 0xB08A3A, 0.32, 1.0],              # 3
    ["goma", 0x161616, 0.85, 0.0],               # 4
    ["acero", 0x8E9196, 0.3, 1.0],               # 5
    ["piloto_rojo", 0xFF2A1A, 0.2, 0.0],         # 6 (emisivo)
    ["calca", 0xFFFFFF, 0.6, 0.0],               # 7 (textura de calcomanias)
    ["hollin", 0x0E0D0C, 0.9, 0.2],              # 8 (bocas de escape y de los cañones)
    ["cable", 0x1E1F21, 0.6, 0.0],               # 9
    ["metal_quemado", 0x3A3632, 0.45, 0.9],      # 10 (escapes: el sombreador le pone el pavonado del calor)
]
M = {m[0]: i for i, m in enumerate(MATERIALES)}
AMA, OSC, ROJ, LAT, GOM, ACE, LUZ, CAL, HOL, CAB, QUE = (M[k] for k in ["pintura_amarilla", "metal_oscuro", "pintura_roja", "laton", "goma", "acero",
                                                                       "piloto_rojo", "calca", "hollin", "cable", "metal_quemado"])

def junta(c, eje_largo, largo, normal, ancho=0.008):
    """Junta entre paneles: una tira oscura y fina pegada a la cara (normal), de largo metros a lo largo de eje_largo."""
    n = nrm(normal); e = nrm(eje_largo); t = [0.0, 0.0, 0.0]
    for i, v in enumerate(e): t[i] += abs(v) * largo
    for i, v in enumerate(n): t[i] += abs(v) * 0.006
    for i in range(3):
        if t[i] == 0: t[i] = ancho
    return caja(np.asarray(c, float) + n * 0.002, tuple(t), 0.002, OSC, seg=1)

# ---------------------------------------------------------------- utilidades de geometria
def v3(*a): return np.array(a, dtype=float)
def nrm(a):
    a = np.asarray(a, float); n = np.linalg.norm(a, axis=-1, keepdims=True); return a / np.maximum(n, 1e-12)

def rot(eje, ang):
    """Matriz de giro (Rodrigues) alrededor de eje (no hace falta unitario)."""
    e = nrm(eje); x, y, z = e; c, s = math.cos(ang), math.sin(ang); C = 1 - c
    return np.array([[c + x * x * C, x * y * C - z * s, x * z * C + y * s],
                     [y * x * C + z * s, c + y * y * C, y * z * C - x * s],
                     [z * x * C - y * s, z * y * C + x * s, c + z * z * C]])

def base_de(eje):
    """Dos vectores perpendiculares a eje (y el eje unitario)."""
    w = nrm(eje); a = v3(0, 0, 1) if abs(w[2]) < 0.9 else v3(1, 0, 0)
    u = nrm(np.cross(w, a)); v = np.cross(w, u); return u, v, w


class Prim:
    """Pieza indexada: vertices (con soldadura propia para las normales suaves), triangulos y material por triangulo."""
    def __init__(self, V, F, mat, uv=None):
        self.V = np.asarray(V, float); self.F = np.asarray(F, np.int64); self.mat = mat; self.uv = uv

    def transformada(self, R=None, t=None, escala=None):
        V = self.V.copy()
        if escala is not None: V = V * np.asarray(escala, float)
        if R is not None: V = V @ np.asarray(R).T
        if t is not None: V = V + np.asarray(t, float)
        F = self.F.copy()
        if escala is not None and np.prod(np.sign(escala)) < 0: F = F[:, ::-1]
        return Prim(V, F, self.mat, self.uv)


def caja(c, tam, bisel=0.02, mat=AMA, seg=2, estrecha=None, R=None):
    """Caja biselada: centro c, tamaño (x, y, z), bisel en metros (aristas redondeadas con seg tramos).
    estrecha = (eje_de, eje_a, k0, k1): el tamaño en eje_a se multiplica por k0 en el lado - de eje_de y por k1 en el +."""
    h = np.asarray(tam, float) / 2; b = min(bisel, *(h * 0.95))
    ts = [math.sin(0.5 * math.pi * k / seg) for k in range(seg + 1)]         # 0..1 dentro del bisel
    def ejes(hh):
        lo = [-hh + b * (1 - t) for t in ts]                                  # -hh .. -hh+b
        e = min(0.015, (hh - b) * 0.3)                                        # franja junto al bisel: la cara queda plana (normal y curvatura)
        if e > 1e-4: lo = lo + [-hh + b + e]
        lo = sorted(lo)
        return lo + [-x for x in lo[::-1]]
    xs, ys, zs = ejes(h[0]), ejes(h[1]), ejes(h[2])
    V, F, idx = [], [], {}
    def vid(p):
        k = (round(p[0], 7), round(p[1], 7), round(p[2], 7))
        if k not in idx: idx[k] = len(V); V.append(p)
        return idx[k]
    def cara(eje, signo):
        o = [a for a in range(3) if a != eje]; A = [xs, ys, zs]
        ua, va = A[o[0]], A[o[1]]
        for i in range(len(ua) - 1):
            for j in range(len(va) - 1):
                q = []
                for (ii, jj) in [(i, j), (i + 1, j), (i + 1, j + 1), (i, j + 1)]:
                    p = [0, 0, 0]; p[eje] = signo * h[eje]; p[o[0]] = ua[ii]; p[o[1]] = va[jj]
                    # proyeccion de caja redondeada: el punto del cubo sobre la caja interior + bisel en su direccion
                    inn = np.clip(p, -h + b, h - b); d = np.asarray(p) - inn; n = np.linalg.norm(d)
                    pp = inn + (d / n * b if n > 1e-12 else 0)
                    q.append(vid(tuple(pp)))
                a, bb, cc, dd = q
                if signo * (1 if (o[0], o[1]) in [(0, 1), (1, 2), (2, 0)] else -1) > 0: F.extend([[a, bb, cc], [a, cc, dd]])
                else: F.extend([[a, cc, bb], [a, dd, cc]])
    for e in range(3):
        for s in (-1, 1): cara(e, s)
    V = np.array(V); F = np.array(F)
    cen = V[F].mean(axis=1); fn = np.cross(V[F[:, 1]] - V[F[:, 0]], V[F[:, 2]] - V[F[:, 0]])
    dar = np.sum(fn * cen, axis=1) < 0; F[dar] = F[dar][:, ::-1]            # caras hacia fuera (la caja es convexa)
    if estrecha:
        de, a, k0, k1 = estrecha
        t = (V[:, de] + h[de]) / (2 * h[de]); V[:, a] *= k0 + (k1 - k0) * t
    P = Prim(V, F, mat)
    P = P.transformada(R=R, t=c)
    return P


def torno(perfil, eje=(1, 0, 0), o=(0, 0, 0), n=24, mat=AMA, ang0=0.0, ang=2 * math.pi):
    """Pieza de torno: perfil = [(r, x)] a lo largo del eje desde o (r >= 0). Un punto repetido = arista viva."""
    u, v, w = base_de(eje); o = np.asarray(o, float)
    # cada tramo largo lleva un punto cerca de cada extremo: la normal y la curvatura del canto no se extienden por la cara
    pp = []
    for i, q in enumerate(perfil):
        if i and perfil[i - 1] != q:
            a = np.asarray(perfil[i - 1], float); b_ = np.asarray(q, float); L = np.linalg.norm(b_ - a)
            if L > 0.03:
                e = min(0.012, L * 0.2) / L
                pp += [tuple(a + (b_ - a) * e), tuple(b_ - (b_ - a) * e)]
        pp.append(tuple(q))
    perfil = pp
    completo = abs(ang - 2 * math.pi) < 1e-9
    m = n if completo else n + 1
    V, F = [], []
    filas = []
    for (r, x) in perfil:
        fila = []
        for k in range(m):
            a = ang0 + ang * k / n
            fila.append(len(V)); V.append(o + w * x + (u * math.cos(a) + v * math.sin(a)) * r)
        filas.append(fila)
    for i in range(len(perfil) - 1):
        if perfil[i] == perfil[i + 1]: continue
        A, B = filas[i], filas[i + 1]
        for k in range(n):
            k1 = (k + 1) % m if completo else k + 1
            F.extend([[A[k], B[k], B[k1]], [A[k], B[k1], A[k1]]])
    V = np.array(V); F = np.array(F)
    a, b, c = V[F[:, 0]], V[F[:, 1]], V[F[:, 2]]
    # caras hacia fuera: la normal de cada cara se aleja del eje (o, si la cara es una tapa, sigue el sentido del perfil)
    cen = (a + b + c) / 3; rad = cen - o - np.outer(np.dot(cen - o, w), w)
    fn = np.cross(b - a, c - a)
    sig = np.sum(fn * rad, axis=1)
    if np.sum(sig) < 0: F = F[:, ::-1]
    return Prim(V, F, mat)


def cilindro(o, eje, r, L, mat=OSC, n=20, bisel=0.008, hueco=0.0):
    b = min(bisel, r * 0.3, L * 0.3)
    if hueco > 0:                                  # con anima: abierto delante, fondo al 30 % del largo
        p = [(0.0, 0.0), (r - b, 0.0), (r, b), (r, L - b), (r - b, L), (hueco, L), (hueco, L), (hueco, L * 0.3), (0.0, L * 0.3)]
        return torno(p, eje, o, n, mat)
    p = [(0.0, 0.0), (r - b, 0.0), (r, b), (r, L - b), (r - b, L), (0.0, L)]
    return torno(p, eje, o, n, mat)


def remache(p, nrm_, r=0.018, mat=AMA, n=8):
    """Cabeza de remache abombada sobre una superficie de normal nrm_."""
    perf = [(r, -0.004), (r, 0.0), (r * 0.92, r * 0.25), (r * 0.65, r * 0.48), (0.0, r * 0.58)]
    return torno(perf, nrm_, p, n, mat)


def tornillo_hex(p, nrm_, r=0.022, mat=OSC):
    perf = [(r, -0.003), (r, 0.0), (r, r * 0.55), (r * 0.8, r * 0.7), (0.0, r * 0.72)]
    return torno(perf, nrm_, p, 6, mat, ang0=math.pi / 6)


def tubo(puntos, r, mat=GOM, n=10, seg=48, anillas=0.0):
    """Tubo a lo largo de una curva Catmull-Rom por los puntos. anillas: radio extra de los anillos (latiguillo)."""
    P = [np.asarray(p, float) for p in puntos]
    P = [P[0] * 2 - P[1]] + P + [P[-1] * 2 - P[-2]]
    C = []
    for i in range(1, len(P) - 2):
        for k in range(seg // (len(P) - 3) + (1 if i == len(P) - 3 else 0)):
            t = k / (seg // (len(P) - 3)); p0, p1, p2, p3 = P[i - 1], P[i], P[i + 1], P[i + 2]
            C.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t + (-p0 + 3 * p1 - 3 * p2 + p3) * t ** 3))
    C = np.array(C)
    T = np.gradient(C, axis=0); T = nrm(T)
    a = v3(0, 0, 1) if abs(T[0][2]) < 0.9 else v3(1, 0, 0)
    U = nrm(np.cross(T[0], a)); V, F = [], []
    for i, (c, t) in enumerate(zip(C, T)):
        U = nrm(U - t * np.dot(U, t)); W = np.cross(t, U)
        rr = r + (anillas if anillas and i % 3 == 0 else 0)
        for k in range(n):
            a_ = 2 * math.pi * k / n; V.append(c + (U * math.cos(a_) + W * math.sin(a_)) * rr)
    for i in range(len(C) - 1):
        for k in range(n):
            a, b, c2, d = i * n + k, i * n + (k + 1) % n, (i + 1) * n + (k + 1) % n, (i + 1) * n + k
            F.extend([[a, b, c2], [a, c2, d]])
    V = np.array(V); F = np.array(F)
    fn = np.cross(V[F[0, 1]] - V[F[0, 0]], V[F[0, 2]] - V[F[0, 0]])
    if np.dot(fn, V[F[0, 0]] - C[0]) < 0: F = F[:, ::-1]
    return Prim(V, F, mat)


def quad_calca(c, eu, ev, ancho, alto, uv0, uv1):
    """Calcomania plana: centro c, ejes eu (derecha) y ev (arriba) unitarios, tamaño y rectangulo del atlas."""
    eu, ev = nrm(eu), nrm(ev)
    V = [c - eu * ancho / 2 - ev * alto / 2, c + eu * ancho / 2 - ev * alto / 2, c + eu * ancho / 2 + ev * alto / 2, c - eu * ancho / 2 + ev * alto / 2]
    uv = [(uv0[0], uv1[1]), (uv1[0], uv1[1]), (uv1[0], uv0[1]), (uv0[0], uv0[1])]
    F = [[0, 1, 2], [0, 2, 3]]
    P = Prim(np.array(V), F, CAL, uv=np.array(uv, float))
    return P


# ---------------------------------------------------------------- piezas y jerarquia
class Pieza:
    def __init__(self, nombre, padre, pivote):
        self.nombre, self.padre, self.pivote = nombre, padre, np.asarray(pivote, float)   # pivote en cuerpo (reposo)
        self.prims = []
    def add(self, *ps):
        for p in ps:
            if isinstance(p, list): self.prims.extend(p)
            else: self.prims.append(p)

PIEZAS = {}
def pieza(nombre, padre, pivote):
    PIEZAS[nombre] = Pieza(nombre, padre, pivote); return PIEZAS[nombre]

# Modelo en (adelante, derecha, ARRIBA) para pensar comodo; se pasa a NED (z abajo) al exportar.
def F_(x, y, z): return v3(x, y, z)
UP = v3(0, 0, 1); FW = v3(1, 0, 0); RT = v3(0, 1, 0)

def remaches_linea(p0, p1, n, nrm_, r=0.017, mat=AMA):
    return [remache(p0 + (p1 - p0) * (k / max(1, n - 1)), nrm_, r, mat) for k in range(n)]

# ---- medidas generales (m)
H_CADERA = 1.50          # cadera sobre el suelo
Y_PIERNA = 0.66          # separacion de cada cadera del centro
L_MUSLO, L_TIBIA, H_TOBILLO = 0.60, 0.60, 0.30      # pierna recta en reposo: 1,5 - 0,3 = 0,6 + 0,6
H_CINTURA = 1.78

# ======================= PELVIS (sube y baja con el paso; a ella cuelgan las piernas y la cintura)
pel = pieza("pelvis", None, F_(0, 0, H_CADERA))
pel.add(caja(F_(-0.05, 0, 1.62), (0.75, 0.95, 0.42), 0.05, OSC))                     # bloque de la cadera
pel.add(caja(F_(0.18, 0, 1.55), (0.22, 0.6, 0.3), 0.04, AMA))                        # faldon delantero
pel.add(caja(F_(0.32, 0, 1.38), (0.08, 0.5, 0.28), 0.03, AMA, estrecha=(2, 1, 0.75, 1.0)))
for s in (-1, 1):
    pel.add(cilindro(F_(-0.05, s * 0.36, 1.50), RT * s, 0.2, 0.16, OSC, 28))          # carcasa del motor de cadera
    pel.add(cilindro(F_(-0.05, s * 0.52, 1.50), RT * s, 0.14, 0.04, ACE, 24))
    for k in range(8):
        a = 2 * math.pi * k / 8
        pel.add(tornillo_hex(F_(-0.05 + 0.17 * math.cos(a), s * 0.52, 1.50 + 0.17 * math.sin(a)), RT * s, 0.016))
pel.add(remaches_linea(F_(0.29, -0.26, 1.69), F_(0.29, 0.26, 1.69), 6, FW, 0.014))
# latiguillos de la cadera
for s in (-1, 1):
    pel.add(tubo([F_(-0.38, s * 0.2, 1.72), F_(-0.48, s * 0.35, 1.55), F_(-0.30, s * 0.5, 1.36), F_(-0.08, s * 0.52, 1.30)], 0.028, GOM, 10, 36, anillas=0.004))

# ======================= PIERNAS
def pierna(s):
    lado = "d" if s > 0 else "i"; y = s * Y_PIERNA
    cad = pieza("cadera_" + lado, "pelvis", F_(0, y, H_CADERA))
    # muslo: articulacion, blindaje y piston
    cad.add(cilindro(F_(0, y - 0.17, H_CADERA), RT, 0.17, 0.34, OSC, 28))
    cad.add(caja(F_(0.03, y, H_CADERA - 0.3), (0.58, 0.54, 0.54), 0.07, AMA, estrecha=(2, 0, 0.82, 1.0)))   # blindaje del muslo
    cad.add(caja(F_(0.315, y, H_CADERA - 0.28), (0.05, 0.42, 0.4), 0.018, AMA))
    cad.add(remaches_linea(F_(0.34, y - 0.17, H_CADERA - 0.12), F_(0.34, y + 0.17, H_CADERA - 0.12), 5, FW))
    cad.add(remaches_linea(F_(0.34, y - 0.17, H_CADERA - 0.46), F_(0.34, y + 0.17, H_CADERA - 0.46), 5, FW))
    cad.add(junta(F_(0.03, y + 0.271, H_CADERA - 0.3), UP, 0.48, RT), junta(F_(0.03, y - 0.271, H_CADERA - 0.3), UP, 0.48, -RT))
    cad.add(cilindro(F_(-0.27, y + s * 0.16, H_CADERA - 0.05), -UP, 0.05, 0.42, ACE, 16))     # piston trasero
    cad.add(cilindro(F_(-0.27, y + s * 0.16, H_CADERA - 0.05), -UP, 0.07, 0.22, OSC, 16))
    cad.add(calca_marca(F_(0.342, y, H_CADERA - 0.29), FW, "peligro", 0.36, 0.08))
    rod = pieza("rodilla_" + lado, "cadera_" + lado, F_(0, y, H_CADERA - L_MUSLO))
    z = H_CADERA - L_MUSLO
    rod.add(cilindro(F_(0, y - 0.19, z), RT, 0.15, 0.38, OSC, 28))
    rod.add(cilindro(F_(0, y - 0.215, z), RT, 0.11, 0.43, ACE, 24))
    rod.add(caja(F_(0.2, y, z + 0.02), (0.26, 0.46, 0.36), 0.07, AMA, estrecha=(0, 2, 1.0, 0.7)))      # rodillera
    rod.add(remache(F_(0.33, y, z + 0.02), FW, 0.028))
    rod.add(caja(F_(0.04, y, z - 0.33), (0.58, 0.54, 0.52), 0.07, AMA, estrecha=(2, 0, 1.15, 0.9)))      # espinilla
    rod.add(caja(F_(0.32, y, z - 0.3), (0.045, 0.4, 0.36), 0.015, AMA))
    rod.add(remaches_linea(F_(0.345, y - 0.16, z - 0.16), F_(0.345, y - 0.16, z - 0.44), 4, FW))
    rod.add(remaches_linea(F_(0.345, y + 0.16, z - 0.16), F_(0.345, y + 0.16, z - 0.44), 4, FW))
    rod.add(cilindro(F_(-0.27, y, z - 0.05), -UP, 0.045, 0.45, ACE, 16))
    rod.add(cilindro(F_(-0.27, y, z - 0.30), -UP, 0.065, 0.24, OSC, 16))
    rod.add(tubo([F_(-0.22, y + s * 0.12, z + 0.1), F_(-0.28, y + s * 0.16, z - 0.1), F_(-0.24, y + s * 0.18, z - 0.42)], 0.02, GOM, 8, 24, anillas=0.003))
    tob = pieza("tobillo_" + lado, "rodilla_" + lado, F_(0, y, H_TOBILLO))
    tob.add(cilindro(F_(0, y - 0.15, H_TOBILLO), RT, 0.1, 0.3, OSC, 24))
    tob.add(caja(F_(0.06, y, 0.13), (0.82, 0.62, 0.18), 0.045, OSC))                   # planta
    tob.add(caja(F_(0.02, y, 0.22), (0.56, 0.54, 0.16), 0.06, AMA))
    for k, dy in enumerate((-0.2, 0.0, 0.2)):                                           # tres dedos delante
        tob.add(caja(F_(0.52, y + dy, 0.09), (0.32, 0.17, 0.16), 0.04, AMA, estrecha=(0, 2, 1.0, 0.6)))
        tob.add(caja(F_(0.69, y + dy, 0.045), (0.07, 0.16, 0.08), 0.02, OSC))
        tob.add(cilindro(F_(0.37, y + dy - 0.085, 0.1), RT, 0.055, 0.17, OSC, 16))
    tob.add(caja(F_(-0.42, y, 0.08), (0.28, 0.26, 0.15), 0.04, AMA))                   # espolon trasero
    tob.add(cilindro(F_(-0.3, y - 0.13, 0.1), RT, 0.055, 0.26, OSC, 16))
    tob.add(calca_marca(F_(0.1, y, 0.302), UP, "peligro", 0.4, 0.09, eu=RT))

# ======================= CINTURA Y TORSO (gira 360 grados)
def calca_marca(c, normal, cual, ancho, alto, eu=None):
    # ojo: (adelante, derecha, arriba) es un triedro a izquierdas: la derecha de quien mira la calcomania es n x arriba
    n = nrm(normal)
    if eu is None: eu = nrm(np.cross(n, UP)) if abs(n[2]) < 0.9 else RT
    ev = np.cross(eu, n)
    u0, u1 = ATLAS[cual]
    P = quad_calca(np.asarray(c, float) + n * 0.004, eu, ev, ancho, alto, u0, u1); P.normal_fija = n
    return P

# atlas de calcomanias (u0, v0) - (u1, v1) en [0, 1]; la imagen se dibuja en dibujar_atlas()
ATLAS = {"numero": ((0.0, 0.0), (0.25, 0.5)), "emblema": ((0.25, 0.0), (0.5, 0.5)), "peligro": ((0.5, 0.0), (1.0, 0.25)),
         "serie": ((0.5, 0.25), (1.0, 0.5)), "aviso": ((0.0, 0.5), (0.5, 0.75)), "flecha": ((0.5, 0.5), (0.75, 0.75)),
         "rejilla": ((0.75, 0.5), (1.0, 0.75)), "carga": ((0.0, 0.75), (0.5, 1.0))}

for s in (1, -1): pierna(s)

cin = pieza("cintura", "pelvis", F_(0, 0, H_CINTURA))
cin.add(cilindro(F_(0, 0, 1.78), UP, 0.36, 0.1, OSC, 40))                    # corona de giro
cin.add(cilindro(F_(0, 0, 1.7), UP, 0.3, 0.1, ACE, 40))
for k in range(16):
    a = 2 * math.pi * k / 16; cin.add(tornillo_hex(F_(0.33 * math.cos(a), 0.33 * math.sin(a), 1.88), UP, 0.015))
# torso: sarcofago
cin.add(caja(F_(0.02, 0, 2.42), (1.25, 1.45, 1.2), 0.09, AMA))                    # casco principal
cin.add(caja(F_(0.62, 0, 2.38), (0.16, 0.95, 0.98), 0.05, AMA, estrecha=(2, 1, 0.82, 1.0)))   # placa frontal
cin.add(caja(F_(0.66, 0, 2.93), (0.3, 0.98, 0.1), 0.03, AMA, R=rot(RT, -0.55)))      # blindaje inclinado sobre el pecho
cin.add(caja(F_(0.69, 0, 1.87), (0.12, 1.02, 0.1), 0.03, OSC))                       # faldon bajo del pecho
for s_ in (-1, 1):
    cin.add(junta(F_(0.03, s_ * 0.727, 2.42), UP, 1.0, RT * s_), junta(F_(-0.3, s_ * 0.727, 2.42), UP, 1.0, RT * s_))
    cin.add(tubo([F_(0.45, s_ * 0.79, 2.05), F_(0.5, s_ * 0.83, 2.1), F_(0.5, s_ * 0.83, 2.4), F_(0.45, s_ * 0.79, 2.45)], 0.018, ACE, 8, 24))   # asideros
cin.add(caja(F_(0.71, 0, 2.12), (0.06, 0.34, 0.3), 0.02, OSC))                    # ventanilla del piloto (marco)
cin.add(caja(F_(0.735, 0, 2.12), (0.02, 0.28, 0.06), 0.008, LUZ))                 # rendija con luz
for k in range(4): cin.add(caja(F_(0.745, 0, 2.03 + k * 0.06 if k < 2 else 2.16 + (k - 2) * 0.06), (0.02, 0.3, 0.02), 0.006, OSC))
cin.add(caja(F_(0.71, 0, 2.62), (0.05, 0.6, 0.22), 0.03, OSC))                    # rejilla de ventilacion
for k in range(7): cin.add(caja(F_(0.735, 0, 2.53 + k * 0.03), (0.02, 0.56, 0.012), 0.004, ACE))
cin.add(remaches_linea(F_(0.715, -0.4, 2.84), F_(0.715, 0.4, 2.84), 8, FW))
cin.add(remaches_linea(F_(0.715, -0.4, 1.92), F_(0.715, 0.4, 1.92), 8, FW))
cin.add(remaches_linea(F_(0.715, -0.42, 2.0), F_(0.715, -0.42, 2.78), 7, FW))
cin.add(remaches_linea(F_(0.715, 0.42, 2.0), F_(0.715, 0.42, 2.78), 7, FW))
cin.add(calca_marca(F_(0.715, 0.0, 2.38), FW, "serie", 0.5, 0.12))
for s in (-1, 1):                                                                  # pilotos rojos y placas laterales
    cin.add(cilindro(F_(0.69, s * 0.33, 2.9), FW, 0.03, 0.04, OSC, 16), cilindro(F_(0.72, s * 0.33, 2.9), FW, 0.022, 0.015, LUZ, 16))
    cin.add(caja(F_(0.1, s * 0.74, 2.25), (0.9, 0.06, 0.62), 0.025, AMA))
    cin.add(remaches_linea(F_(-0.3, s * 0.775, 2.5), F_(0.5, s * 0.775, 2.5), 8, RT * s))
# techo: lanzagranadas de humo (3 tubos) y antenas
cin.add(caja(F_(0.05, 0, 3.06), (0.9, 1.1, 0.12), 0.04, AMA))
cin.add(caja(F_(0.35, 0, 3.17), (0.22, 0.5, 0.14), 0.03, OSC))
for k, dy in enumerate((-0.15, 0.0, 0.15)):
    cin.add(cilindro(F_(0.3, dy, 3.2), rot(RT, -0.55) @ FW, 0.065, 0.3, OSC, 18, 0.01, hueco=0.045))
    cin.add(cilindro(F_(0.3, dy, 3.2), rot(RT, -0.55) @ FW, 0.072, 0.05, LAT, 18))
cin.add(cilindro(F_(-0.3, 0.42, 3.12), UP, 0.012, 0.55, ACE, 8), cilindro(F_(-0.3, 0.42, 3.12), UP, 0.025, 0.06, OSC, 10))
# espalda: dos toberas de escape con aletas y la mochila del reactor
cin.add(caja(F_(-0.7, 0, 2.4), (0.3, 1.0, 0.9), 0.06, AMA))
for s in (-1, 1):
    y = s * 0.32
    cin.add(cilindro(F_(-0.86, y, 2.15), UP, 0.16, 1.1, QUE, 28, 0.02))
    for k in range(9): cin.add(cilindro(F_(-0.86, y, 2.32 + k * 0.088), UP, 0.188, 0.03, QUE, 28, 0.008))   # aletas de refrigeracion
    cin.add(cilindro(F_(-0.86, y, 3.24), UP, 0.15, 0.1, QUE, 24, 0.01, hueco=0.11))
    cin.add(cilindro(F_(-0.86, y, 3.27), UP, 0.111, 0.07, HOL, 20))
    cin.add(caja(F_(-0.86, y, 2.08), (0.36, 0.36, 0.1), 0.03, OSC))
cin.add(caja(F_(-0.88, 0, 2.6), (0.1, 0.24, 0.3), 0.02, AMA))
cin.add(calca_marca(F_(-0.93, 0, 2.6), -FW, "aviso", 0.22, 0.11))
cin.add(caja(F_(-0.86, 0, 1.98), (0.18, 0.5, 0.16), 0.03, OSC))
cin.add(tubo([F_(-0.86, -0.32, 2.0), F_(-0.95, 0, 1.9), F_(-0.86, 0.32, 2.0)], 0.03, CAB, 10, 30))
cin.add(tubo([F_(-0.6, 0.55, 1.95), F_(-0.5, 0.75, 1.9), F_(-0.2, 0.8, 1.95)], 0.024, GOM, 8, 24, anillas=0.004))
cin.add(tubo([F_(-0.6, -0.55, 1.95), F_(-0.5, -0.75, 1.9), F_(-0.2, -0.8, 1.95)], 0.024, GOM, 8, 24, anillas=0.004))
# hombreras (fijas al torso)
for s in (-1, 1):
    y = s * 1.0
    cin.add(caja(F_(0.02, y, 2.7), (1.12, 0.6, 0.82), 0.1, AMA, estrecha=(2, 0, 0.82, 1.0)))            # hombrera: casco
    cin.add(caja(F_(0.02, y + s * 0.315, 2.68), (0.98, 0.05, 0.66), 0.025, AMA, estrecha=(2, 0, 0.82, 1.0)))   # placa exterior
    cin.add(caja(F_(0.02, y + s * 0.345, 2.68), (0.8, 0.03, 0.5), 0.012, AMA, estrecha=(2, 0, 0.82, 1.0)))    # segunda placa
    cin.add(caja(F_(0.02, y, 3.12), (1.02, 0.56, 0.06), 0.025, OSC))                                       # ribete de arriba
    cin.add(caja(F_(0.02, y, 2.3), (0.98, 0.62, 0.06), 0.025, OSC))                                        # ribete de abajo
    cin.add(caja(F_(0.6, y, 2.7), (0.05, 0.5, 0.66), 0.02, AMA, estrecha=(2, 1, 0.85, 1.0)))              # placa delantera
    cin.add(junta(F_(0.02, y + s * 0.301, 2.47), FW, 0.9, RT * s), junta(F_(0.02, y, 3.091), FW, 0.95, UP))
    cin.add(remaches_linea(F_(-0.42, y + s * 0.342, 2.97), F_(0.44, y + s * 0.342, 2.97), 10, RT * s))
    cin.add(remaches_linea(F_(-0.38, y + s * 0.342, 2.4), F_(0.4, y + s * 0.342, 2.4), 9, RT * s))
    cin.add(remaches_linea(F_(-0.45, y + s * 0.342, 2.5), F_(-0.45, y + s * 0.342, 2.88), 4, RT * s))
    cin.add(remaches_linea(F_(0.47, y + s * 0.342, 2.5), F_(0.47, y + s * 0.342, 2.88), 4, RT * s))
    cin.add(remaches_linea(F_(0.63, y - 0.2, 2.98), F_(0.63, y + 0.2, 2.98), 5, FW))
    cin.add(calca_marca(F_(0.04, y + s * 0.362, 2.68), RT * s, "numero" if s < 0 else "emblema", 0.42, 0.42, eu=FW * s))
    cin.add(calca_marca(F_(0.55, y, 2.88), FW, "flecha", 0.14, 0.14))

# ======================= BRAZO DERECHO: CAÑON ROTATIVO (hombro pivota en cabeceo; los cañones giran)
Y_HOMBRO = 1.0; Z_HOMBRO = 2.5
bd = pieza("brazo_d", "cintura", F_(0.0, Y_HOMBRO + 0.12, Z_HOMBRO))
y = Y_HOMBRO + 0.15
bd.add(cilindro(F_(0, y - 0.18, Z_HOMBRO), RT, 0.2, 0.42, OSC, 28))
bd.add(caja(F_(0.0, y + 0.08, 2.08), (0.36, 0.36, 0.62), 0.05, OSC))                 # brazo
bd.add(cilindro(F_(-0.05, y + 0.08, 1.98), RT, 0.17, 0.4, ACE, 24))
bd.add(caja(F_(0.12, y + 0.1, 1.68), (0.62, 0.46, 0.4), 0.05, OSC))                 # carcasa del arma
bd.add(caja(F_(0.12, y + 0.1, 1.9), (0.5, 0.4, 0.08), 0.02, AMA))
bd.add(remaches_linea(F_(-0.12, y + 0.34, 1.6), F_(0.36, y + 0.34, 1.6), 6, RT, 0.014, OSC))
bd.add(calca_marca(F_(0.12, y + 0.334, 1.75), RT, "carga", 0.36, 0.1, eu=FW))
# cinta de municion: eslabones desde la carcasa hacia atras y abajo
for k in range(14):
    t = k / 13; px = 0.0 - 0.32 * t; pz = 1.52 - 0.05 * math.sin(t * math.pi) - 0.1 * t
    bd.add(caja(F_(px, y - 0.08 + 0.02 * math.sin(t * 6), pz), (0.035, 0.2, 0.07), 0.01, LAT))
    bd.add(caja(F_(px, y - 0.08, pz - 0.035), (0.03, 0.22, 0.02), 0.006, OSC))
X_CANON = 0.43; Z_CANON = 1.68
bd.add(cilindro(F_(X_CANON, y + 0.1, Z_CANON), FW, 0.21, 0.16, OSC, 32, 0.02))         # brida
cn = pieza("canones", "brazo_d", F_(X_CANON, y + 0.1, Z_CANON))
for k in range(6):
    a = 2 * math.pi * k / 6; dy, dz = 0.12 * math.cos(a), 0.12 * math.sin(a)
    cn.add(cilindro(F_(X_CANON + 0.1, y + 0.1 + dy, Z_CANON + dz), FW, 0.048, 0.98, OSC, 16, 0.006, hueco=0.026))
    cn.add(cilindro(F_(X_CANON + 1.05, y + 0.1 + dy, Z_CANON + dz), FW, 0.026, 0.03, HOL, 12))
for xx, rr in ((0.2, 0.19), (0.6, 0.18), (0.98, 0.18)):                               # abrazaderas
    cn.add(cilindro(F_(X_CANON + xx, y + 0.1, Z_CANON), FW, rr, 0.07, OSC, 30, 0.012, hueco=0.06))
cn.add(cilindro(F_(X_CANON + 0.1, y + 0.1, Z_CANON), FW, 0.05, 0.95, ACE, 16))

# ======================= BRAZO IZQUIERDO: PUÑO (hombro pivota; los dedos se cierran)
bi = pieza("brazo_i", "cintura", F_(0.0, -(Y_HOMBRO + 0.12), Z_HOMBRO))
y = -(Y_HOMBRO + 0.15)
bi.add(cilindro(F_(0, y - 0.24, Z_HOMBRO), RT, 0.2, 0.42, OSC, 28))
bi.add(caja(F_(0.0, y - 0.08, 2.1), (0.36, 0.36, 0.62), 0.05, OSC))
bi.add(cilindro(F_(-0.05, y - 0.28, 1.98), RT, 0.17, 0.4, ACE, 24))
bi.add(caja(F_(0.12, y - 0.1, 1.48), (0.72, 0.62, 0.72), 0.1, ROJ))                  # antebrazo-puño
bi.add(caja(F_(0.12, y - 0.1, 1.86), (0.6, 0.5, 0.06), 0.02, OSC))
bi.add(caja(F_(0.12, y - 0.42, 1.5), (0.6, 0.04, 0.6), 0.02, ROJ))
bi.add(remaches_linea(F_(-0.15, y - 0.445, 1.75), F_(0.4, y - 0.445, 1.75), 6, -RT, 0.016, ROJ))
bi.add(remaches_linea(F_(-0.15, y - 0.445, 1.24), F_(0.4, y - 0.445, 1.24), 6, -RT, 0.016, ROJ))
bi.add(calca_marca(F_(0.12, y - 0.443, 1.5), -RT, "emblema", 0.36, 0.36, eu=-FW))
bi.add(cilindro(F_(0.12, y + 0.22, 1.7), RT, 0.08, 0.05, OSC, 16))
X_DEDOS = 0.48; Z_DEDOS = 1.3
dd = pieza("dedos", "brazo_i", F_(X_DEDOS, y - 0.1, Z_DEDOS))
for k, dy in enumerate((-0.21, -0.07, 0.07, 0.21)):
    for j in range(3):                                                                 # tres falanges en arco
        a = -0.25 - j * 0.42; px = X_DEDOS + 0.05 + j * 0.1 * math.cos(-a); pz = Z_DEDOS - 0.02 - j * 0.11
        dd.add(caja(F_(px, y - 0.1 + dy, pz), (0.13, 0.12, 0.13), 0.03, ROJ, R=rot(RT, -a)))
        dd.add(cilindro(F_(px - 0.06, y - 0.1 + dy - 0.065, pz + 0.04), RT, 0.035, 0.13, OSC, 12))
dd.add(caja(F_(X_DEDOS + 0.04, y + 0.24, Z_DEDOS + 0.12), (0.14, 0.12, 0.26), 0.03, ROJ, R=rot(FW, 0.35)))     # pulgar


# ---------------------------------------------------------------- normales, curvatura, oclusion
def preparar(p: Prim):
    V, F = p.V, p.F
    if getattr(p, "normal_fija", None) is not None:
        N = np.tile(nrm(p.normal_fija), (len(V), 1)); return V, F, N, np.zeros(len(V))
    # soldadura por posicion dentro de la primitiva (el torno repite puntos solo en las aristas vivas)
    key = np.round(V, 6); _, inv = np.unique(key, axis=0, return_inverse=True); inv = inv.reshape(-1)
    a, b, c = V[F[:, 0]], V[F[:, 1]], V[F[:, 2]]
    fn = np.cross(b - a, c - a); area = np.linalg.norm(fn, axis=1); ok = area > 1e-12
    F, fn, area = F[ok], fn[ok], area[ok]; fnu = fn / area[:, None]
    # suavizado con angulo limite (40 grados): cada esquina promedia las caras de su posicion parecidas a la suya
    G = inv[F]                                                   # grupo de posicion de cada esquina
    acc = np.zeros((inv.max() + 1, 3)); np.add.at(acc, G.reshape(-1), np.repeat(fn, 3, axis=0))
    N = np.zeros((len(F) * 3, 3)); Vc = V[F.reshape(-1)]
    # aproximacion: normal suave del grupo si se parece a la de la cara; si no, la de la cara (arista viva)
    ns = nrm(acc[G.reshape(-1)]); nf = np.repeat(fnu, 3, axis=0)
    usa = np.sum(ns * nf, axis=1) > math.cos(math.radians(40))
    N = np.where(usa[:, None], ns, nf)
    # curvatura por grupo: media de dot(n, (centroide - v)/|..|) de las caras vecinas (negativo = convexo)
    cen = np.repeat((a[ok] + b[ok] + c[ok]) / 3, 3, axis=0); d = cen - Vc
    k = -np.sum(ns * nrm(d), axis=1)
    kac = np.zeros(inv.max() + 1); cnt = np.zeros(inv.max() + 1)
    np.add.at(kac, G.reshape(-1), k); np.add.at(cnt, G.reshape(-1), 1)
    curv = (kac / np.maximum(cnt, 1))[G.reshape(-1)]
    Fn = np.arange(len(F) * 3).reshape(-1, 3)
    return Vc, Fn, N, curv


def volcar_mundo():
    """Triangulos de todo el modelo en reposo (cuerpo, z arriba) para el voxelizado de la oclusion."""
    T = []
    for P in PIEZAS.values():
        for p in P.prims:
            if p.mat == CAL: continue
            T.append(p.V[p.F])
    return np.concatenate(T)


_OCC = {}
def oclusion(puntos, normales, tris, vox=0.03, alcance=0.55, n_dir=20):
    if not _OCC: _OCC.update(ocupacion(tris, vox))
    lo, dim, occ = _OCC["lo"], _OCC["dim"], _OCC["occ"]
    return _marcha(puntos, normales, lo, dim, occ, vox, alcance, n_dir)

def ocupacion(tris, vox):
    lo = tris.reshape(-1, 3).min(axis=0) - 0.6; hi = tris.reshape(-1, 3).max(axis=0) + 0.6
    dim = np.ceil((hi - lo) / vox).astype(int) + 1
    occ = np.zeros(dim, bool)
    # muestras sobre cada triangulo (rejilla baricentrica segun su tamaño)
    for t in tris:
        L = max(np.linalg.norm(t[1] - t[0]), np.linalg.norm(t[2] - t[0]), np.linalg.norm(t[2] - t[1]))
        m = int(math.ceil(L / (vox * 0.7))) + 1
        u = np.linspace(0, 1, m + 1); U, W = np.meshgrid(u, u); s = (U + W) <= 1
        P = t[0] + U[s][:, None] * (t[1] - t[0]) + W[s][:, None] * (t[2] - t[0])
        ii = np.floor((P - lo) / vox).astype(int); occ[ii[:, 0], ii[:, 1], ii[:, 2]] = True
    return {"lo": lo, "dim": dim, "occ": occ}

def _marcha(puntos, normales, lo, dim, occ, vox, alcance, n_dir):
    # direcciones de la semiesfera (espiral de Fibonacci, coseno)
    k = np.arange(n_dir) + 0.5; th = np.arccos(np.sqrt(1 - k / n_dir)); ph = math.pi * (1 + 5 ** 0.5) * k
    D = np.stack([np.sin(th) * np.cos(ph), np.sin(th) * np.sin(ph), np.cos(th)], 1)
    ao = np.zeros(len(puntos))
    for i0 in range(0, len(puntos), 4000):
        Nn = normales[i0:i0 + 4000]; P = puntos[i0:i0 + 4000] + Nn * (vox * 1.5)     # fuera de la propia capa de voxeles
        u, v, w = np.zeros_like(Nn), np.zeros_like(Nn), Nn
        a = np.where(np.abs(Nn[:, 2:3]) < 0.9, np.array([[0, 0, 1.0]]), np.array([[1.0, 0, 0]]))
        u = nrm(np.cross(w, a)); v = np.cross(w, u)
        vis = np.zeros(len(P))
        for d in D:
            dirs = u * d[0] + v * d[1] + w * d[2]
            libre = np.ones(len(P), bool); peso = np.zeros(len(P))
            for paso in np.arange(vox, alcance, vox):
                q = P + dirs * paso; ii = np.floor((q - lo) / vox).astype(int)
                dentro = np.all((ii >= 0) & (ii < dim), axis=1)
                ii = np.clip(ii, 0, dim - 1)
                golpe = occ[ii[:, 0], ii[:, 1], ii[:, 2]] & dentro & libre
                peso[golpe] = 1 - paso / alcance; libre &= ~golpe
            vis += 1 - peso
        ao[i0:i0 + 4000] = vis / n_dir
    return ao


# ---------------------------------------------------------------- paso: cinematica inversa
def tabla_paso(n=64, paso=1.0, alza=0.2, apoyo=0.62):
    """Angulos (rad, + = hacia delante) de cadera, rodilla y tobillo de cada pierna y sube-baja de la pelvis en n
    fases del ciclo (dos pasos; la pierna derecha empieza apoyando). paso: largo de cada paso (m)."""
    filas = []
    a, b = L_MUSLO, L_TIBIA
    for i in range(n):
        f = i / n; fila = []
        bob = -0.1 - 0.035 * (0.5 + 0.5 * math.cos(4 * math.pi * f))   # andando va agachado (y mas con los dos pies en el suelo)
        for desfase in (0.0, 0.5):
            g = (f + desfase) % 1
            if g < apoyo: x = paso / 2 - paso * g / apoyo; zf = 0.0          # apoyado: el pie va hacia atras
            else:
                s = (g - apoyo) / (1 - apoyo); x = -paso / 2 + paso * (0.5 - 0.5 * math.cos(math.pi * s)); zf = alza * math.sin(math.pi * s)
            hz = H_CADERA + bob - (H_TOBILLO + zf)          # bajada de la cadera al tobillo
            d = min(math.hypot(x, hz), 0.995 * (a + b))
            ang_d = math.atan2(x, hz)                        # + = tobillo por delante de la cadera
            c_k = (a * a + b * b - d * d) / (2 * a * b); k = math.pi - math.acos(max(-1, min(1, c_k)))   # flexion de rodilla
            c_h = (a * a + d * d - b * b) / (2 * a * d); al = math.acos(max(-1, min(1, c_h)))
            cad = ang_d + al                                 # muslo hacia delante de la linea cadera-tobillo
            rod = -k                                         # la rodilla dobla hacia atras (espinilla hacia atras)
            tob = -(cad + rod)                               # pie plano
            if g >= apoyo: tob += 0.25 * math.sin(math.pi * (g - apoyo) / (1 - apoyo))
            fila += [cad, rod, tob]
        balanceo = 0.035 * math.sin(2 * math.pi * f)
        filas.append([round(x, 5) for x in fila + [bob, balanceo]])
    return {"tabla": filas, "columnas": ["cadera_d", "rodilla_d", "tobillo_d", "cadera_i", "rodilla_i", "tobillo_i", "pelvis_z", "pelvis_alabeo"],
            "paso_m": paso, "apoyo": apoyo}


# ---------------------------------------------------------------- calcomanias
def dibujar_atlas():
    W = 1024; im = Image.new("RGBA", (W, W), (0, 0, 0, 0)); g = ImageDraw.Draw(im)
    def fuente(t):
        for f in ["C:/Windows/Fonts/timesbd.ttf", "C:/Windows/Fonts/georgiab.ttf", "C:/Windows/Fonts/arialbd.ttf"]:
            if os.path.exists(f): return ImageFont.truetype(f, t)
        return ImageFont.load_default()
    def stencil(t):
        for f in ["C:/Windows/Fonts/impact.ttf", "C:/Windows/Fonts/arialbd.ttf"]:
            if os.path.exists(f): return ImageFont.truetype(f, t)
        return ImageFont.load_default()
    def caja_(uv0, uv1): return (int(uv0[0] * W), int(uv0[1] * W), int(uv1[0] * W), int(uv1[1] * W))
    NEG = (14, 12, 10, 255); BLA = (236, 230, 214, 255)
    # numero romano
    x0, y0, x1, y1 = caja_(*ATLAS["numero"])
    g.text(((x0 + x1) / 2, (y0 + y1) / 2), "VII", font=fuente(190), fill=NEG, anchor="mm")
    # emblema propio: disco blanco con borde, rueda dentada y rayo (marca HQ)
    x0, y0, x1, y1 = caja_(*ATLAS["emblema"]); cx, cy, R = (x0 + x1) / 2, (y0 + y1) / 2, (x1 - x0) * 0.46
    g.ellipse((cx - R, cy - R, cx + R, cy + R), fill=NEG); g.ellipse((cx - R * 0.9, cy - R * 0.9, cx + R * 0.9, cy + R * 0.9), fill=BLA)
    pts = []
    for k in range(48):
        a = 2 * math.pi * k / 48; r = R * (0.72 if (k // 2) % 2 == 0 else 0.6); pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    g.polygon(pts, fill=NEG); g.ellipse((cx - R * 0.42, cy - R * 0.42, cx + R * 0.42, cy + R * 0.42), fill=BLA)
    rayo = [(0.12, -0.62), (-0.2, 0.06), (0.02, 0.06), (-0.12, 0.62), (0.22, -0.1), (0.0, -0.1), (0.1, -0.62)]
    g.polygon([(cx + R * x, cy + R * y) for x, y in rayo], fill=(180, 24, 20, 255))
    # franjas de peligro
    x0, y0, x1, y1 = caja_(*ATLAS["peligro"]); g.rectangle((x0, y0, x1, y1), fill=(222, 170, 20, 255))
    for k in range(-4, 20):
        xa = x0 + k * 64; g.polygon([(xa, y1), (xa + 32, y1), (xa + 32 + (y1 - y0), y0), (xa + (y1 - y0), y0)], fill=NEG)
    # serie
    x0, y0, x1, y1 = caja_(*ATLAS["serie"]); g.text(((x0 + x1) / 2, (y0 + y1) / 2), "HQ-07 · 7,5 t", font=stencil(92), fill=NEG, anchor="mm")
    # aviso
    x0, y0, x1, y1 = caja_(*ATLAS["aviso"]); g.rectangle((x0 + 8, y0 + 8, x1 - 8, y1 - 8), outline=NEG, width=10)
    g.text(((x0 + x1) / 2, (y0 + y1) / 2 - 30), "¡ESCAPE CALIENTE!", font=stencil(52), fill=NEG, anchor="mm")
    g.text(((x0 + x1) / 2, (y0 + y1) / 2 + 40), "NO ACERCARSE", font=stencil(52), fill=NEG, anchor="mm")
    # flecha de elevacion
    x0, y0, x1, y1 = caja_(*ATLAS["flecha"]); cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    g.polygon([(cx, y0 + 20), (x1 - 30, cy + 10), (cx + 40, cy + 10), (cx + 40, y1 - 20), (cx - 40, y1 - 20), (cx - 40, cy + 10), (x0 + 30, cy + 10)], fill=NEG)
    # rejilla (sin usar de momento)
    x0, y0, x1, y1 = caja_(*ATLAS["rejilla"])
    for k in range(8): g.rectangle((x0 + 10, y0 + 12 + k * 30, x1 - 10, y0 + 24 + k * 30), fill=NEG)
    # carga de municion
    x0, y0, x1, y1 = caja_(*ATLAS["carga"]); g.text(((x0 + x1) / 2, (y0 + y1) / 2), "30 MM · CINTA", font=stencil(84), fill=NEG, anchor="mm")
    im.save(F_PNG)


# ---------------------------------------------------------------- exportar
def a_ned(P): return np.stack([P[:, 0], P[:, 1], -P[:, 2]], 1)

def b64(arr): return base64.b64encode(np.ascontiguousarray(arr).tobytes()).decode()

def exportar():
    tris = volcar_mundo()
    salida = []
    total_v = total_t = 0
    for P in PIEZAS.values():
        Vs, Fs, Ns, Ks, Ms, UVs = [], [], [], [], [], []; base = 0
        for p in P.prims:
            V, F, N, K = preparar(p)
            Vs.append(V); Ns.append(N); Ks.append(K); Fs.append(F + base); Ms.append(np.full(len(V), p.mat))
            UVs.append(p.uv[np.arange(len(V)) % len(p.uv)] if p.uv is not None and len(V) == len(p.uv) else (p.uv if p.uv is not None else np.zeros((len(V), 2))))
            base += len(V)
        V = np.concatenate(Vs); F = np.concatenate(Fs); N = nrm(np.concatenate(Ns)); K = np.concatenate(Ks); MA = np.concatenate(Ms); UV = np.concatenate(UVs)
        # soldar esquinas iguales (posicion, normal, material) para el indice
        clave = np.concatenate([np.round(V, 5), np.round(N, 3), MA[:, None], np.round(UV, 4)], 1)
        _, primero, inv = np.unique(clave, axis=0, return_index=True, return_inverse=True); inv = inv.reshape(-1)
        V, N, K, MA, UV = V[primero], N[primero], K[primero], MA[primero], UV[primero]; F = inv[F]
        AO = oclusion(V + N * 0.0, N, tris)
        AO = np.where(MA == CAL, 1.0, AO)
        alt = V[:, 2].copy()
        Vl = a_ned(V - P.pivote); Nl = a_ned(N)
        assert np.abs(Vl).max() < 3.2, (P.nombre, np.abs(Vl).max())
        assert len(V) < 65536, P.nombre
        reg = np.zeros(len(V), dtype=[("p", "<i2", 3), ("n", "i1", 3), ("m", "u1"), ("k", "i1"), ("ao", "u1"), ("h", "u1"), ("x", "u1"), ("uv", "<u2", 2)])
        reg["p"] = np.round(Vl * 10000).astype(np.int16); reg["n"] = np.round(Nl * 127).astype(np.int8)
        reg["m"] = MA; reg["k"] = np.round(np.clip(K * 3, -1, 1) * 127).astype(np.int8)
        reg["ao"] = np.round(np.clip(AO, 0, 1) * 255).astype(np.uint8); reg["h"] = np.round(np.clip(alt / 3.6, 0, 1) * 255).astype(np.uint8)
        reg["uv"] = np.round(np.clip(UV, 0, 1) * 65535).astype(np.uint16)
        # orientacion de los triangulos: cara delantera hacia la normal (en NED); se guarda en sentido antihorario visto desde fuera
        a, b, c = Vl[F[:, 0]], Vl[F[:, 1]], Vl[F[:, 2]]
        fn = np.cross(b - a, c - a); nm = Nl[F[:, 0]] + Nl[F[:, 1]] + Nl[F[:, 2]]
        dar = np.sum(fn * nm, axis=1) < 0; F[dar] = F[dar][:, ::-1]
        piv = a_ned(P.pivote[None, :])[0]; padre = PIEZAS[P.padre].pivote if P.padre else np.zeros(3)
        salida.append({"nombre": P.nombre, "padre": P.padre or "", "pivote": [round(float(x), 5) for x in piv],
                       "vertices": int(len(V)), "triangulos": int(len(F)),
                       "v": b64(reg), "i": b64(F.astype(np.uint16))})
        total_v += len(V); total_t += len(F)
        print("%-12s %6d vertices %6d triangulos" % (P.nombre, len(V), len(F)))
    print("total", total_v, "vertices", total_t, "triangulos")
    return salida


def escribir(piezas, paso):
    datos = {
        "id": "BIPODE", "nombre": "Bípode de asalto HQ-07", "tipo": "bipode", "oculto": True,
        "descripcion": "Vehículo terrestre de dos patas de 7,5 t y 3,4 m de alto, con la cintura que gira 360° y un cañón rotativo de 30 mm. Se maneja con la palanca izquierda; la derecha gira la cintura y apunta, y el gatillo derecho dispara.",
        "ayuda": "Palanca izquierda (o W/S y A/D): andar y girar. Palanca derecha (o flechas): girar la cintura 360° y subir o bajar los brazos. Gatillo derecho (o espacio): disparar el cañón rotativo. Derriba los drones diana.",
        "caracteristicas": [["Masa", "7,5 t"], ["Alto · ancho · largo", "3,4 · 3,2 · 3,0 m"], ["Velocidad", "hasta 6 km/h andando, 2,5 km/h marcha atrás"],
                            ["Pendiente máxima", "60 % (31°)"], ["Cintura", "gira 360° (40°/s)"], ["Cañón rotativo", "6 tubos de 30 mm, cinta, 900 disparos por minuto"],
                            ["Puño de combate", "servohidráulico, placas reforzadas"], ["Paso", "1 m por paso, cadencia de 0,8 pasos por segundo a tope"]],
        "masa_kg": 7500, "b_m": 3.2, "S_m2": 10, "cg_mm": [0, 0, 0], "inercia": {"Ixx": 1, "Iyy": 1, "Izz": 1, "Ixz": 0},
        "lanzamiento": {"vel_ms": 0, "cabeceo_grados": 0}, "compensador_grados": 0,
        "mandos": {"izq_der": "giro (A/D)"},
        "colores": {"fuselaje": 0xD9A514, "ala": 0xD9A514, "estab": 0x2B2B2D, "moviles": 0x9E1A16},
        "bipode": {"vel_max_ms": 1.65, "vel_atras_ms": 0.7, "acel_ms2": 0.6, "frena_ms2": 1.4, "giro_max_gs": 24, "giro_marcha_gs": 12,
                   "cintura_gs": 40, "brazos_min_grados": -15, "brazos_max_grados": 65, "brazos_gs": 30,
                   "pendiente_max": 0.6, "paso_m": 1.0, "apoyo": 0.62, "inclina_tau_s": 0.4,
                   "cadencia_rpm": 900, "giro_canones_tau_s": 0.35, "bala_ms": 900, "dispersion_grados": 0.6, "alcance_m": 1500,
                   "boca": [1.05 + 0.43, 1.25, -1.68], "hombro": [0.0, 1.12, -2.5], "ojo": [0.55, 0.0, -2.9],
                   "drones": {"n": 6, "radio_m": 180, "alt_min_m": 15, "alt_max_m": 55, "vel_ms": 9, "radio_impacto_m": 0.9, "vida": 1}},
        "modelo3d": {"materiales": MATERIALES, "piezas": piezas, "paso": paso, "calcas": "BIPODE_calcas.png",
                     "sombreador": open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "sombreador.glsl"), encoding="utf-8").read().rstrip().splitlines(),
                     "formato": "por vertice 18 bytes: pos int16 x3 (0,1 mm, NED, desde el pivote), normal int8 x3, material u8, curvatura i8, oclusion u8, altura u8 (x3,6 m), relleno u8, uv u16 x2"},
    }
    js = open(F_JS, encoding="utf-8").read()
    i = js.index("// <DATOS>"); j = js.index("// </DATOS>")
    nuevo = "// <DATOS>\n  const DATOS = " + json.dumps(datos, ensure_ascii=False, separators=(", ", ": ")) + ";\n  "
    open(F_JS, "w", encoding="utf-8", newline="\n").write(js[:i] + nuevo + js[j:])
    print("escrito", F_JS, os.path.getsize(F_JS) // 1024, "KB")


if __name__ == "__main__":
    dibujar_atlas()
    piezas = exportar()
    escribir(piezas, tabla_paso())
