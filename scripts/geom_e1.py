"""Entrenadores E1 y E2: genera las piezas imprimibles (STL) y las mallas montadas para masas e inercias.
Que avion se genera lo dice la variable de entorno ENTRENADOR (avion.py): E1 por defecto, E2 con alerones.

Ejes globales (los de parametros_e1.py): X a lo largo del fuselaje (0 = bancada del motor, + hacia
la cola), Y a la derecha, Z arriba, mm.

Piezas (todas imprimibles sin soportes):
  ALA_C            pieza central del ala, plana (el tubo de carbono central la atraviesa)
  ALA_Q_izq        pieza del quiebro del poliedro (la derecha, en espejo): lleva el angulo del diedro, el tope
                   de los tubos y el paso de la llave de aluminio que los une
  ALA_*            tramos de ala (P.TRAMOS), piel + celosia diagonal (se imprimen de pie)
  F1..F5           fuselaje en 5 tramos que encajan con un cuello y se pegan; F2 lleva la bandeja de los
                   servos, F2-F5 las guias de las transmisiones y F5 la deriva
  ESTAB_x2         estabilizador (placa plana), atraviesa F5 por una ranura y se une con 2 varillas; lleva los
                   nudillos de la bisagra
  PROF_x2          profundidad: dos mitades con el horn impreso (en la izquierda) que giran sobre un pasador
                   de carbono de 2 mm que atraviesa los nudillos y une las dos mitades
  TIMON            timon (solo el E1), con su horn y sus nudillos; gira sobre un pasador vertical de 2 mm
E2 (parametros_e2.py): en los tramos que cruza el aleron, el ala lleva el corte con su pared de cierre y los
nudillos de la bisagra y, en el tramo del servo, el cajeado del servo de 9 g abierto por el intrados. Los
alerones (ALERON_A y _B) son tramos huecos como el ala; el pasador de 2 mm de la bisagra los une. La deriva
de F5 va sin timon, con el canto trasero afinado.
Compras: tubo de carbono 8x6 (central + 2 puntas), varilla de carbono 3 mm, 2 mm y 4 mm maciza (palillos de
las gomas), barra de aluminio de 6 mm (2 llaves del quiebro), 2 transmisiones tipo Bowden de 550 mm, gomas.
"""
import json, os, pickle, struct
import numpy as np
from manifold3d import Manifold, CrossSection, OpType, set_circular_segments
from avion import ID, P, OUT_NOMBRE

set_circular_segments(72)
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), OUT_NOMBRE)

# ---------------- construccion ----------------
WALL = 1.0                    # pared de cierre y cajeado del servo de las piezas del ala
WALL_F = 1.6                  # pared del fuselaje: 4 lineas de 0,4 mm (con 1,0, dos lineas, salia flojo al imprimir)
SPIGOT_L, SPIGOT_T = 15.0, 1.2   # cuello de union entre tramos (entra en el tramo siguiente); 15 mm suaviza el escalon donde rompe la pared
FUS_SEG = [(0, 180), (180, 330), (330, 500), (500, 640), (640, P.L)]   # F1 llega a 180: el palillo delantero (X 171) y su taco caen dentro
SPAR_D, SPAR2_D, SPAR2_X = 8.2, 3.2, 0.60   # tubo 8x6 al 25 % de la cuerda, varilla 3 mm al 60 %
LLAVE_D = 6.3                 # paso de la llave del quiebro (barra de aluminio de 6 mm, dentro de los tubos 8x6)
# canal del cable de los servos de alerón (E2/E3): agujero de 8 mm a lo largo del ala entre el tubo y el larguero
# trasero (x local 24 = 69 mm de cuerda, en la linea media), por celosia, tapas y nervio del quiebro, desde el
# cajeado del servo hasta ALA_C, donde sale por el intrados sobre la escotilla del fuselaje
CABLE_X, CABLE_Y, CABLE_R = 24.0, 0.0, 4.0
CABLE_BOCA = 24.0             # largo (envergadura) de la boca de salida en ALA_C, centrada
SKIN, RIB_T, CAP, RIB_P = 0.45, 0.45, 0.6, 40.0   # paso 40: con 30 el ala pesaba 243 g
TRAMOS = P.TRAMOS             # tramos del ala (pieza, desde, hasta), aparte de ALA_C y ALA_Q
ALERON = getattr(P, "ALERON", None)      # alerones (E2): bisagra, tramo de envergadura, piezas y servo
CON_TIMON = P.RUD_HINGE < 1.0
PLATE_T = 4.0                 # espesor de estabilizador, deriva y timon
TE_T = 1.2                    # borde de fuga de las superficies moviles
GAP = 1.0                     # holgura de bisagra
# bisagras de nudillos: pasador de carbono de 2 mm, pegado en la superficie movil y libre en la fija
PIN_D, PIN_LIBRE, PIN_PEGADO = 2.0, 2.4, 2.15
NUDILLO_R, NUDILLO_L, NUDILLO_HOLGURA = 2.6, 8.0, 0.5   # radio del nudillo, largo, holgura con el de enfrente
DOWEL_D = 4.3                 # palillos de las gomas del ala: varilla de carbono MACIZA de 4 mm (el bambu de 3 mm
                              # rompia con ~40 N por extremo, margen 1,8 en un golpe; el carbono, con ~750 N)
DOWEL_BOSS_R, DOWEL_BOSS_T = 6.0, 5.0    # taco de cada pared: arranca con ~370 N (margen ~16)
DOWELS = [(P.X_LE - 14.0, 27.0), (P.X_LE + P.C + 14.0, 27.0)]
HT_PIN_D = 2.2                # varillas de 2 mm que unen las dos mitades del estabilizador
X_HINGE_H = P.HT_XLE + P.ELEV_HINGE * P.HT_C


# ---------------- utilidades ----------------
def ccw(p):
    p = np.array(p, float); a = 0.5 * np.sum(p[:, 0] * np.roll(p[:, 1], -1) - np.roll(p[:, 0], -1) * p[:, 1])
    return (p if a > 0 else p[::-1]).tolist()


def write_stl(man, path):
    mesh = man.to_mesh()
    v = np.asarray(mesh.vert_properties)[:, :3]; t = np.asarray(mesh.tri_verts)
    with open(path, "wb") as f:
        f.write(b"\0" * 80); f.write(struct.pack("<I", len(t)))
        for tri in t:
            a, b, c = v[tri]
            n = np.cross(b - a, c - a); n = n / (np.linalg.norm(n) or 1)
            f.write(struct.pack("<12fH", *n, *a, *b, *c, 0))


def centroid(man):
    mesh = man.to_mesh()
    v = np.asarray(mesh.vert_properties)[:, :3]; t = np.asarray(mesh.tri_verts)
    a, b, c = v[t[:, 0]], v[t[:, 1]], v[t[:, 2]]
    vol = np.einsum("ij,ij->i", a, np.cross(b, c)) / 6
    return ((a + b + c) / 4 * vol[:, None]).sum(0) / vol.sum()


def to_print(man):
    x0, y0, z0, x1, y1, z1 = man.bounding_box()
    return man.translate([-(x0 + x1) / 2, -(y0 + y1) / 2, -z0])


def along_x(man):            # eje Z local -> X global; x local -> -Z global
    return man.rotate([0, 90, 0])


# ---------------- perfil ----------------
def naca4(m, p, t, n=80):
    beta = np.linspace(0, np.pi, n)
    x = 0.5 * (1 - np.cos(beta))
    yt = 5 * t * (0.2969 * np.sqrt(x) - 0.1260 * x - 0.3516 * x ** 2 + 0.2843 * x ** 3 - 0.1036 * x ** 4)
    if m > 0:
        yc = np.where(x < p, m / p ** 2 * (2 * p * x - x ** 2), m / (1 - p) ** 2 * ((1 - 2 * p) + 2 * p * x - x ** 2))
        dyc = np.where(x < p, 2 * m / p ** 2 * (p - x), 2 * m / (1 - p) ** 2 * (p - x))
    else:
        yc, dyc = 0 * x, 0 * x
    th = np.arctan(dyc)
    return (x - yt * np.sin(th), yc + yt * np.cos(th)), (x + yt * np.sin(th), yc - yt * np.cos(th)), (x, yc)


(XU, YU), (XL, YL), (XC, YC) = naca4(*P.PERFIL)


def camber_at(u):
    return float(np.interp(u, XC, YC))


def section_pts(c):
    up = np.c_[XU[::-1], YU[::-1]] * c
    lo = np.c_[XL[1:-1], YL[1:-1]] * c
    return np.vstack([up, lo])


def write_dat(path):
    with open(path, "w") as f:
        f.write("NACA 2412\n")
        for x, y in zip(XU[::-1], YU[::-1]): f.write(f"{x:.6f} {y:.6f}\n")
        for x, y in zip(XL[1:], YL[1:]): f.write(f"{x:.6f} {y:.6f}\n")


def spar_origin(c):
    return 0.25 * c, camber_at(0.25) * c


def wing_cs(c):
    """Seccion con origen en el larguero principal (25 % de la cuerda, sobre la linea media)."""
    us, vs = spar_origin(c)
    cs = CrossSection([(section_pts(c) - [us, vs]).tolist()])
    x2, y2 = SPAR2_X * c - us, camber_at(SPAR2_X) * c - vs
    return cs, (x2, y2)


# ---------------- ala ----------------
def lattice(c, h, us):
    """Nervios diagonales a +-45 grados (planos que contienen el espesor): sin soportes de pie."""
    out = []
    L2 = (h + c) * 1.6
    for sgn in (+1, -1):
        for k in range(-int(h // RIB_P) - 2, int(c // RIB_P) + 3):
            u0 = k * RIB_P + RIB_P / 2 - us
            out.append(Manifold.cube([RIB_T, 40, L2], center=True).rotate([0, sgn * 45, 0]).translate([u0, 0, 0]))
    return Manifold.batch_boolean(out, OpType.Add)


def hollow(cs, h, caps=(True, True), c=P.C, con_largueros=True):
    """Cuerpo hueco de seccion cs: piel SKIN, celosia, tapas y, si con_largueros, las vainas de los dos
    largueros. Local: cuerda X, espesor Y, envergadura Z (0..h), origen en el larguero principal."""
    _, (x2, y2) = wing_cs(c)
    us, _ = spar_origin(c)
    outer = Manifold.extrude(cs, h)
    z0 = CAP if caps[0] else -1.0
    z1 = h - CAP if caps[1] else h + 1.0
    void = Manifold.extrude(cs.offset(-SKIN), h + 4).translate([0, 0, -2]) ^ Manifold.cube([400, 400, z1 - z0]).translate([-200, -200, z0])
    structure = lattice(c, h, us).translate([0, 0, h / 2])
    if con_largueros:
        structure = structure + Manifold.extrude(CrossSection.circle(SPAR_D / 2 + 0.6) + CrossSection.circle(SPAR2_D / 2 + 0.6).translate([x2, y2]), h)
    # la celosia se mete 0,1 mm en la piel y en las tapas: si solo las tocara, la pieza serian trozos sueltos
    dentro = Manifold.extrude(cs.offset(-SKIN + 0.1), h + 4).translate([0, 0, -2]) ^ Manifold.cube([400, 400, z1 - z0 + 0.2]).translate([-200, -200, z0 - 0.1])
    body = (outer - void) + (structure ^ dentro)
    if con_largueros:
        body = body - Manifold.extrude(CrossSection.circle(SPAR_D / 2) + CrossSection.circle(SPAR2_D / 2).translate([x2, y2]), h + 2).translate([0, 0, -1])
    return body


def y_superficie(u, c=P.C):
    """(y del extrados, y del intrados) en la coordenada local u (origen en el larguero principal)."""
    us, vs = spar_origin(c)
    x = (u + us) / c
    return float(np.interp(x, XU, YU)) * c - vs, float(np.interp(x, XL, YL)) * c - vs


def aleron_x(c=P.C):
    """x local de la cara trasera de la pared de cierre del ala y del eje de la bisagra del aleron. El eje va
    3 mm por detras de la pared y cerca del extrados (aleron_eje): al bajar, el canto inferior del aleron se
    adelanta ~1,6 mm y no llega a la pared."""
    xh = ALERON["bisagra"] * c - spar_origin(c)[0]
    return xh - 2.0, xh + 1.0


def aleron_eje(c=P.C):
    """(x, y) local del eje de la bisagra del aleron: 3,2 mm por debajo del extrados."""
    _, xe = aleron_x(c)
    return xe, y_superficie(xe, c)[0] - (NUDILLO_R + 0.6)


def nudillos_aleron(h):
    """Inicio (envergadura local) de los nudillos de un tramo de aleron de largo h: cada 45 mm."""
    return [float(s) for s in np.arange(12.0, h - NUDILLO_L - 10.0, 45.0)]


def nudillos_ala(h, s0):
    """Nudillos de la bisagra del aleron en el ala: cilindro alrededor del eje y puente hasta la pared, con la
    cara de abajo (al imprimir el tramo de pie) a 45 grados. s0: envergadura local donde empieza el aleron."""
    cs, _ = wing_cs(P.C)
    xw, _ = aleron_x()
    xe, ye = aleron_eje()
    out = None
    for sk in nudillos_aleron(h):
        z = s0 + sk
        n = (Manifold.cylinder(NUDILLO_L, NUDILLO_R).translate([xe, ye, z])
             + Manifold.cube([xe - xw + 1.0, 2 * NUDILLO_R, NUDILLO_L]).translate([xw - 1.0, ye - NUDILLO_R, z]))
        n = n ^ Manifold.extrude(cs, 400).translate([0, 0, -1])
        n = n.trim_by_plane([-1.0 / np.sqrt(2), 0.0, 1.0 / np.sqrt(2)], (z - (xw - 1.0)) / np.sqrt(2))   # z - x >= z_k - x_pared
        out = n if out is None else out + n
    return out - Manifold.cylinder(1000, PIN_LIBRE / 2).translate([xe, ye, -10])


def servo_caja(c=P.C):
    """Cajeado del servo del aleron en local (x0, x1, y_techo, ancho): de costado, delante del larguero
    trasero, abierto por el intrados; el brazo asoma por abajo y la varilla va al horn del aleron."""
    _, (x2, _) = wing_cs(c)
    x1 = x2 - SPAR2_D / 2 - 0.6 - 1.5
    x0 = x1 - ALERON["servo_largo"]
    y_int = max(y_superficie(x0)[1], y_superficie(x1)[1])         # el intrados mas alto de la zona
    return x0, x1, y_int + ALERON["servo_fondo"], ALERON["servo_ancho"]


def canal_cable(z0, z1):
    """Cilindro del canal del cable entre las envergaduras locales z0 y z1."""
    return Manifold.cylinder(z1 - z0, CABLE_R).translate([CABLE_X, CABLE_Y, z0])


def wing_segment(h, caps=(True, True), c=P.C, corte=None, servo_s=None, canal=None):
    """Tramo de ala hueco (ver hollow). corte = (s0, s1): tramo de envergadura (local) donde va el
    aleron: se quita el ala tras la bisagra y se cierra con una pared; servo_s: envergadura local del
    centro del cajeado del servo; canal = (z0, z1): tramo de envergadura local por el que pasa el canal
    del cable (None: sin canal)."""
    cs, _ = wing_cs(c)
    body = hollow(cs, h, caps, c)
    if corte is not None:
        s0, s1 = corte
        xh, _ = aleron_x(c)
        outer = Manifold.extrude(cs, h)
        paredes = outer ^ Manifold.cube([WALL, 100, s1 - s0]).translate([xh - WALL, -50, s0])          # pared de cierre
        if s0 > 0.01:   # tapa en el extremo del corte (el resto del tramo sigue entero)
            paredes = paredes + (outer ^ Manifold.cube([c, 100, CAP]).translate([xh - WALL, -50, s0 - CAP]))
        if s1 < h - 0.01:
            paredes = paredes + (outer ^ Manifold.cube([c, 100, CAP]).translate([xh - WALL, -50, s1]))
        body = body - Manifold.cube([c, 100, s1 - s0]).translate([xh, -50, s0]) + paredes
        body = body + nudillos_ala(s1 - s0, s0)
    if servo_s is not None:
        x0, x1, yt, w = servo_caja(c)
        outer = Manifold.extrude(cs, h)
        caja = Manifold.cube([x1 - x0, 60, w]).translate([x0, yt - 60, servo_s - w / 2])
        pared = outer ^ Manifold.cube([x1 - x0 + 2 * WALL, 60 + WALL, w + 2 * WALL]).translate([x0 - WALL, yt - 60, servo_s - w / 2 - WALL])
        body = body + pared - caja
        if canal is not None:   # abertura del cajeado al canal (por la pared delantera del cajeado)
            body = body - Manifold.cube([x0 + 1.0 - (CABLE_X - 1.0), 6.0, 8.0]).translate([CABLE_X - 1.0, -3.0, servo_s - 4.0])
    if canal is not None:
        body = body - canal_cable(canal[0], canal[1])
    return body


def aleron_cs(c=P.C):
    """Seccion del aleron: la del ala por detras del eje de la bisagra, mas un circulo de radio NUDILLO_R
    alrededor del eje (el canto delantero gira dentro del hueco que deja la pared de cierre, 3 mm por delante)."""
    cs, _ = wing_cs(c)
    xe, ye = aleron_eje(c)
    detras = cs ^ CrossSection.square([c + 50, 200]).translate([xe, -100])
    return detras + (cs ^ CrossSection.circle(NUDILLO_R).translate([xe, ye]))


def aileron_segment(h, horn_s=None, c=P.C):
    """Tramo de aleron hueco de altura h, con el canto delantero macizo alrededor del pasador de 2 mm (pegado:
    une los tramos y es el eje de la bisagra), huecos para los nudillos del ala y, si horn_s, la ranura del
    horn en el intrados (envergadura local horn_s)."""
    xe, ye = aleron_eje(c)
    cs = aleron_cs(c)
    m = hollow(cs, h, (True, True), c, con_largueros=False)
    m = m + (Manifold.extrude(CrossSection.circle(NUDILLO_R).translate([xe, ye]), h) ^ Manifold.extrude(cs, h))   # canto macizo
    for sk in nudillos_aleron(h):
        hueco = (Manifold.cylinder(NUDILLO_L + 2 * NUDILLO_HOLGURA, NUDILLO_R + 0.4).translate([xe, ye, sk - NUDILLO_HOLGURA])
                 + Manifold.cube([4.0, 2 * NUDILLO_R + 0.8, NUDILLO_L + 2 * NUDILLO_HOLGURA]).translate([xe - 4.0, ye - NUDILLO_R - 0.4, sk - NUDILLO_HOLGURA]))
        m = m - hueco
    m = m - Manifold.cylinder(h + 2, PIN_PEGADO / 2).translate([xe, ye, -1])
    if horn_s is not None:
        m = m - Manifold.cube([12.0, 20.0, 1.6]).translate([xe + 6.0, y_superficie(xe + 12.0, c)[1] - 20.0 + 6.0, horn_s - 0.8])
    return m


def wing_place():
    """Z del borde de ataque para que el punto mas bajo del intrados de la raiz quede en Z_ALA."""
    i = np.radians(P.INC)
    u, v = XL * P.C, YL * P.C
    Z = -u * np.sin(i) + v * np.cos(i)
    return P.Z_ALA - Z.min()


Z_LE = wing_place()


def wing_to_global(seg, span_off, left, exterior=None):
    """Tramo local -> global. La semiala izquierda va hacia -Y; la derecha es su espejo. Poliedro: hasta el
    quiebro el ala es plana; los tramos de fuera (exterior, por defecto si empiezan en el quiebro o mas alla)
    giran DIEDRO grados sobre la recta del quiebro (paralela a X, en y = -QUIEBRO, z = Z_LE)."""
    if exterior is None:
        exterior = span_off >= P.QUIEBRO - 1e-6
    us, vs = spar_origin(P.C)
    g = seg.translate([us, vs, span_off]).rotate([90, 0, 0])      # envergadura hacia -Y, espesor hacia +Z
    g = g.rotate([0, P.INC, 0])
    if exterior:
        g = g.translate([0, P.QUIEBRO, 0]).rotate([-P.DIEDRO, 0, 0]).translate([0, -P.QUIEBRO, 0])
    g = g.translate([P.X_LE, 0, Z_LE])
    return g if left else g.mirror([0, 1, 0])


def punto_ala(u, v, s, left):
    """El punto local (u, v, s) de un tramo de ala (origen en el larguero principal, s desde el plano de
    simetria) en coordenadas globales: la misma cadena de giros que wing_to_global."""
    us, vs = spar_origin(P.C)
    q = np.array([u + us, v + vs, s], float)
    q = np.array([q[0], -q[2], q[1]])                                              # giro de +90 sobre X
    i = np.radians(P.INC); q = np.array([q[0] * np.cos(i) + q[2] * np.sin(i), q[1], -q[0] * np.sin(i) + q[2] * np.cos(i)])
    if s >= P.QUIEBRO - 1e-6:
        q[1] += P.QUIEBRO
        d = np.radians(-P.DIEDRO); q = np.array([q[0], q[1] * np.cos(d) - q[2] * np.sin(d), q[1] * np.sin(d) + q[2] * np.cos(d)])
        q[1] -= P.QUIEBRO
    q = q + [P.X_LE, 0, Z_LE]
    return q if left else q * [1, -1, 1]


# Topes de ALA_C: dos nervios en cuna bajo el intrados, uno por lado, que entran justo por dentro de las pestanas
# del asiento del fuselaje (TOPE_HOLGURA mm por lado): el ala no se desliza de lado sobre el fuselaje y, al
# ponerla, se centra sola. En dos tramos de la cuerda donde hay pestana debajo (en X global). Seccion en V de
# 10 mm arriba y TOPE_HONDO bajo el intrados, con las caras a 45 grados: ALA_C se imprime de pie (envergadura
# vertical) y asi no hay voladizos.
TOPES_X = [(P.X_LE + 20.0, P.X_LE + 60.0), (P.X_LE + 105.0, P.X_LE + 145.0)]
TOPE_HONDO, TOPE_HOLGURA = 4.0, 0.3


def topes_ala_c(h):
    """Topes en local de ALA_C (cuerda X desde el larguero, espesor Y, envergadura Z de 0 a h)."""
    us, _ = spar_origin(P.C)
    y_cara = P.FUS_W / 2 - WALL_F - 4.0 - TOPE_HOLGURA        # cara de fuera, a la altura del intrados
    out = None
    for (X0, X1) in TOPES_X:
        for x in np.arange(X0, X1 - 0.1, 10.0):               # trozos de 10 mm, cada uno a la altura de su intrados
            u0 = (x - P.X_LE) / np.cos(np.radians(P.INC)) - us
            vi = max(y_superficie(u0)[1], y_superficie(u0 + 10.0)[1])
            for sgn in (-1, 1):                                # local z = h/2 - Y global: sgn -1 es Y > 0
                zf = h / 2 + sgn * y_cara
                tri = [(zf + sgn * 1.0, vi + 1.0), (zf - sgn * 9.0, vi + 1.0), (zf - sgn * 4.0, vi - TOPE_HONDO)]
                cs = CrossSection([ccw(tri)])
                t = Manifold.extrude(cs, 10.0).transform([[0, 0, 1, u0], [0, 1, 0, 0], [1, 0, 0, 0]])
                out = t if out is None else out + t
    return out


def center_piece():
    """Pieza central ALA_C, plana, de -ALA_C_SEMI a +ALA_C_SEMI: un tramo recto que atraviesa el tubo central,
    con los topes que la centran sobre el fuselaje. Se devuelve en local (de pie, para imprimir) y en global."""
    h = 2 * P.ALA_C_SEMI
    seg = wing_segment(h, canal=(-1.0, h + 1.0) if ALERON else None)
    if ALERON:   # boca de salida de los cables por el intrados, sobre la escotilla del fuselaje
        seg = seg - Manifold.cube([2 * CABLE_R + 2.0, 30.0, CABLE_BOCA]).translate([CABLE_X - CABLE_R - 1.0, -30.0, h / 2 - CABLE_BOCA / 2])
    seg = seg + topes_ala_c(h)
    return seg, wing_to_global(seg, -P.ALA_C_SEMI, True, exterior=False)


def _plano_quiebro():
    """Normal (semiala izquierda, hacia fuera) y desplazamiento del plano bisector del quiebro."""
    d = np.radians(P.DIEDRO)
    n = np.array([0.0, -(1 + np.cos(d)), np.sin(d)]); n /= np.linalg.norm(n)
    p0 = np.array([0.0, -P.QUIEBRO, Z_LE])
    return n, float(n @ p0)


def quiebro_piece():
    """Pieza del quiebro ALA_Q (semiala izquierda, en global): media pieza plana por dentro y media inclinada
    DIEDRO por fuera, cortadas por el plano bisector y unidas por un nervio macizo de 1,6 mm. Los tubos de
    carbono (central y de la punta) hacen tope en el nervio; la llave de aluminio de 6 mm pasa por el."""
    h = P.Q_SEMI
    n, off = _plano_quiebro()
    canal = (-1.0, h + 7.0) if ALERON else None
    dentro = wing_to_global(wing_segment(h + 6.0, caps=(True, False), canal=canal), P.QUIEBRO - h, True, exterior=False)
    fuera = wing_to_global(wing_segment(h + 6.0, caps=(False, True), canal=canal).translate([0, 0, -6.0]), P.QUIEBRO, True, exterior=True)
    dentro = dentro.trim_by_plane((-n).tolist(), -off)
    fuera = fuera.trim_by_plane(n.tolist(), off)
    us, vs = spar_origin(P.C)
    sec = CrossSection([(section_pts(P.C) - [us, vs]).tolist()])
    macizo = (wing_to_global(Manifold.extrude(sec, 20.0), P.QUIEBRO - 10.0, True, exterior=False)
              + wing_to_global(Manifold.extrude(sec, 20.0).translate([0, 0, -10.0]), P.QUIEBRO, True, exterior=True))
    nervio = macizo.trim_by_plane(n.tolist(), off - 0.8).trim_by_plane((-n).tolist(), -(off + 0.8))
    # paso de la llave por el nervio, en la linea del larguero principal
    c = punto_ala(0.0, 0.0, P.QUIEBRO, True)
    nervio = nervio - Manifold.cylinder(12.0, LLAVE_D / 2, center=True).rotate([90, 0, 0]).translate(c.tolist())
    if ALERON:   # paso del cable por el nervio (a lo largo del ala plana de dentro; el nervio esta a +-0,8 del quiebro)
        nervio = nervio - wing_to_global(canal_cable(-12.0, 12.0), P.QUIEBRO, True, exterior=False)
    return dentro + fuera + nervio


def quiebro_print(glob):
    """Para imprimir: de pie sobre la cara del lado del centro; la mitad de fuera queda inclinada DIEDRO
    grados respecto a la vertical (sin voladizos)."""
    return glob.translate([-P.X_LE, 0, -Z_LE]).rotate([0, -P.INC, 0]).rotate([-90, 0, 0])


# ---------------- fuselaje ----------------
def rrect(w, h, zc, r):
    """Rectangulo redondeado en el plano local (x = -Z, y = Y) para extruir a lo largo de X."""
    r = max(0.5, min(r, w - 0.2, h - 0.2))
    cs = [CrossSection.circle(r).translate([sx * (h - r) - zc, sy * (w - r)]) for sx in (-1, 1) for sy in (-1, 1)]
    return CrossSection.batch_hull(cs)


def corner_r(w):
    return P.CORNER * w / (P.FUS_W / 2)


def slab(X, inset=0.0, t=0.01):
    w, h, zc = P.fus_seccion(X)
    return along_x(Manifold.extrude(rrect(w - inset, h - inset, zc, corner_r(w) - inset), t)).translate([X, 0, 0])


def solid(a, b, inset=0.0):
    """Solido del fuselaje entre X = a y X = b: envolvente convexa de las secciones, partida en
    X_TAPER (donde empieza a estrecharse) para no estrechar la parte recta."""
    if a < P.X_TAPER - 0.5 and b > P.X_TAPER + 0.5:
        return solid(a, P.X_TAPER, inset) + solid(P.X_TAPER - 0.01, b, inset)
    return Manifold.batch_hull([slab(a, inset), slab(b - 0.01, inset)])


def saddle_cutter(up=True):
    """Todo lo que queda por encima del intrados del ala (para recortar el asiento del fuselaje)."""
    us, vs = spar_origin(P.C)
    lo = np.c_[XL, YL] * P.C - [us, vs]
    pts = [(-us - 30, lo[0, 1])] + lo.tolist() + [(P.C - us + 30, lo[-1, 1]), (P.C - us + 30, 150), (-us - 30, 150)]
    cs = CrossSection([ccw(pts)])
    half = Manifold.extrude(cs, 60).translate([0, 0, -2])
    return wing_to_global(half, 0.0, True) + wing_to_global(half, 0.0, False)


def fuselage_segment(k):
    a, b = FUS_SEG[k]
    last = k == len(FUS_SEG) - 1
    body = solid(a, b) - solid(a - 1, b + 1, WALL_F)
    xa, xb = P.X_LE, P.X_LE + P.C
    if not last:   # cuello hacia el tramo siguiente: encaja dentro de su pared, holgura 0,15
        # anclaje dentro de este tramo: un anillo pegado a la pared (se mete 0,2 mm en ella) con el canto de
        # abajo a 45 grados; el cuello que sale arranca 1 mm dentro del anillo
        anclaje = (Manifold.batch_hull([slab(b - 3.5, WALL_F - 0.2), slab(b, WALL_F - 0.2)])
                   - Manifold.batch_hull([slab(b - 3.51, WALL_F), slab(b - 3.5 + SPIGOT_T, WALL_F + SPIGOT_T), slab(b + 0.01, WALL_F + SPIGOT_T)]))
        cuello = anclaje + (Manifold.batch_hull([slab(b - 1.0, WALL_F + 0.15), slab(b + SPIGOT_L, WALL_F + 0.15)])
                            - Manifold.batch_hull([slab(b - 3, WALL_F + SPIGOT_T), slab(b + SPIGOT_L + 1, WALL_F + SPIGOT_T)]))
        if xa < b < xb:   # bajo el ala el cuello no lleva techo (la escotilla queda libre)
            w, h, zc = P.fus_seccion(b)
            cuello = cuello - Manifold.cube([SPIGOT_L + 4, 2 * w, 50]).translate([b - 3, -w, zc + h - 8.0])
        body = body + cuello
    # asiento del ala: en la zona de la cuerda las paredes suben hasta el intrados y el techo se abre
    if a < xb and b > xa:
        x0, x1 = max(a, xa), min(b, xb)
        w, h, zc = P.fus_seccion(x0)
        tall = along_x(Manifold.extrude(rrect(w, 60.0, 20.0, corner_r(w)), x1 - x0)).translate([x0, 0, 0])
        tall_in = along_x(Manifold.extrude(rrect(w - WALL_F, 80.0, 20.0, corner_r(w) - WALL_F), x1 - x0 + 2)).translate([x0 - 1, 0, 0])
        ledge_in = along_x(Manifold.extrude(rrect(w - WALL_F - 4.0, 80.0, 20.0, corner_r(w) - WALL_F - 4.0), x1 - x0 + 2)).translate([x0 - 1, 0, 0])
        cut = saddle_cutter()
        # las paredes del asiento arrancan rectas desde donde empieza la curva de la esquina del fuselaje: si
        # arrancaran en el lomo quedarian sueltas (la esquina redondeada ya se ha metido hacia dentro)
        top = Manifold.cube([x1 - x0, 2 * w + 2, 100]).translate([x0, -w - 1, zc + h - corner_r(w) - 1.0])
        body = body - (top ^ tall_in)                     # abre el techo: la escotilla es el propio ala
        body = body + ((tall - tall_in) ^ top)            # paredes del asiento
        # pestanas de apoyo (4 mm hacia dentro, 3 mm de grueso) solo en los costados
        xl = max(x0, a + SPIGOT_L + 0.5) if k > 0 else x0     # la pestana no pisa el cuello del tramo anterior
        band = (tall_in - ledge_in) ^ top ^ Manifold.cube([x1 - xl, 2 * w, 100]).translate([xl, -w, zc + h - 6.0])
        band = band - Manifold.cube([x1 - x0 + 2, 2 * (w - WALL_F - 4.0), 200]).translate([x0 - 1, -(w - WALL_F - 4.0), -50])
        body = body + band
        body = body - cut.translate([0, 0, -0.2])                 # 0,2 mm de holgura bajo el ala
    # tacos y agujeros de los palillos de las gomas (varilla de carbono de 4 mm)
    for (xd, zd) in DOWELS:
        if a + DOWEL_BOSS_R + 1 < xd < b - DOWEL_BOSS_R - 1:
            w = P.fus_seccion(xd)[0]
            boss = Manifold.cylinder(2 * w, DOWEL_BOSS_R, center=True).rotate([90, 0, 0]).translate([xd, 0, zd])
            pared = solid(xd - 12, xd + 12) - solid(xd - 13, xd + 13, WALL_F + DOWEL_BOSS_T)
            body = body + (boss ^ pared)
            body = body - Manifold.cylinder(2 * w + 10, DOWEL_D / 2, center=True).rotate([90, 0, 0]).translate([xd, 0, zd])
    if k == 0:     # bancada del motor: placa vertical de 4 mm maciza con los 4 agujeros de la cruz del X2212 (16 x 19,
        # M3) y 4 respiraderos, sin agujero central (el eje trasero y su clip caben en el de la cuna); el downthrust lo
        # da la pieza CUNA_MOTOR (cuna_motor), que va entre la cruz y la placa
        body = body + solid(0.0, 4.0)
        for (yy, zz, r) in [(8, 0, 1.7), (-8, 0, 1.7), (0, 9.5, 1.7), (0, -9.5, 1.7),
                            (21, 24, 4.0), (-21, 24, 4.0), (21, -24, 4.0), (-21, -24, 4.0)]:
            body = body - along_x(Manifold.cylinder(14, r)).translate([-5, yy, zz])
        # suelo: dos carriles que encajan la bateria (canal de 37 mm; el ESC, de 24, tambien cabe) y una fila de
        # ranuras transversales para pasar una cinta de velcro de 20 mm donde haga falta (ventilan ademas el ESC)
        for sy in (-1, 1):
            body = body + Manifold.cube([CARRIL_L, 1.2, 4.0]).translate([CARRIL_X0, sy * 18.5 - (0.0 if sy > 0 else 1.2), SUELO_Z - 0.2])
        for xr in RANURAS_X:
            body = body - Manifold.cube([2.6, 24.0, 10.0]).translate([xr, -12.0, -P.FUS_H / 2 - 5])
    if a < SERVO_X[0] < b:     # bandeja de los servos (bajo la escotilla del ala)
        body = body + bandeja_servos()
    if last:
        body = body + fin_fixed()
        body = body - solid(a - 1, b + 1, WALL_F)                              # la deriva no entra en el hueco
        body = body + (fin_fixed() ^ Manifold.cube([200, 10, 30]).translate([a + SPIGOT_L + 1, -5, P.fus_lomo(b) - 6]))  # raiz (tras el cuello de F4)
        # ranura del estabilizador (abierta por detras) y agujeros de las varillas de union
        body = body - ranura_estab()
        # salidas de las transmisiones: la de la profundidad por el costado izquierdo, por encima del
        # estabilizador; la del timon por el lomo, a la derecha de la deriva
        body = body - salida("prof")
        if CON_TIMON:
            body = body - salida("timon")
    # cuaderna, guias de las transmisiones y vainas de los larguerillos: al final, porque en F5 el hueco interior
    # se vacia otra vez al poner la deriva (antes se llevaba por delante la guia de X 675)
    body = body + cuaderna(k)
    if last:
        body = body - ranura_estab() - salida("prof")
        if CON_TIMON:
            body = body - salida("timon")
    for (xg, nombre) in guias_posiciones():
        if a + SPIGOT_L + 1 < xg - 14 and xg + 11 < b:
            body = body + guia(xg, nombre)
    body = body + vainas_larguerillos(a, b, k)
    body = body - guias_agujeros(a, b) - agujeros_larguerillos(a, b)
    return body


# ---------------- servos y transmisiones ----------------
# Servos de 9 g (23 x 12,2 x 22,5 mm, orejetas a 15,5 mm del fondo, tornillos a 27,8 mm) de pie en el suelo de
# F2, con el eje largo a lo ancho del fuselaje: las orejetas se atornillan a dos placas laterales que, al
# imprimir, son paredes verticales (el borde de abajo va a 45 grados: sin voladizos)
SERVO = dict(largo=23.0, ancho=12.2, alto_orejeta=15.5, tornillos=27.8)
SERVO_X = (P.X_LE + 40.0, P.X_LE + 56.0)   # X del canto delantero de cada servo (profundidad, timon): lo mas adelante que deja la
                                  # escotilla, para que la bateria quepa en el morro con el CG al 33 %
SUELO_Z = -P.FUS_H / 2 + WALL_F
CARRIL_X0, CARRIL_L = 8.0, 152.0            # carriles de la bateria en el suelo de F1 (X 8 a 160)
RANURAS_X = list(range(20, 160, 15))        # ranuras de la cinta de velcro (2,6 x 24 mm), cada 15 mm


def cuna_motor():
    """Cuna de bancada CUNA_MOTOR (global): 34 x 34 mm entre la cruz del motor y la placa de F1, de 2 mm de grueso
    abajo a 2 + 34 tan(DOWNTHRUST) arriba: la cara delantera mira DOWNTHRUST grados hacia abajo y el motor,
    atornillado a ella, apunta ese angulo por debajo del eje del fuselaje. Agujeros perpendiculares a su cara."""
    d = np.radians(P.DOWNTHRUST)
    n = [float(np.cos(d)), 0.0, float(np.sin(d))]
    grueso = 2.0 + 34.0 * np.tan(d)
    m = Manifold.cube([grueso + 1.0, 34.0, 34.0]).translate([-grueso - 1.0, -17.0, -17.0])
    m = m.trim_by_plane(n, float(np.dot(n, [-2.0, 0.0, -17.0])))           # cara delantera inclinada
    m = m.trim_by_plane([-1.0, 0.0, 0.0], 0.0)                               # cara trasera en X = 0
    agujeros = None
    for (yy, zz, r) in [(8, 0, 1.7), (-8, 0, 1.7), (0, 9.5, 1.7), (0, -9.5, 1.7), (0, 0, 5.0)]:
        h = along_x(Manifold.cylinder(20, r)).translate([-10, yy, zz])
        agujeros = h if agujeros is None else agujeros + h
    return m - agujeros.rotate([0, -P.DOWNTHRUST, 0])


def bandeja_servos():
    S = SERVO
    y_in = S["largo"] / 2 + 0.4                       # cara interior de las placas
    z0, z1 = SUELO_Z - 0.5, SUELO_Z + S["alto_orejeta"]
    x0, x1 = SERVO_X[0] - 18.0, SERVO_X[-1] + S["ancho"] + 2.0
    out = None
    for sy in (-1, 1):
        prof = CrossSection([ccw([(x0, z0), (x1, z0), (x1, z1), (x0 + (z1 - z0), z1)])])   # (X, Z), borde a 45
        placa = Manifold.extrude(prof, 3.0).rotate([90, 0, 0])                        # grosor hacia -Y
        placa = placa.translate([0, (y_in + 3.0) if sy > 0 else -y_in, 0])
        out = placa if out is None else out + placa
    # agujeros guia de los tornillos de las orejetas (1,6 mm, 8 mm de hondo)
    for xs in SERVO_X:
        for sy in (-1, 1):
            out = out - Manifold.cylinder(9.0, 0.8).translate([xs + S["ancho"] / 2, sy * S["tornillos"] / 2, z1 - 8.0])
    return out


def _linea_transmision(nombre):
    """Recta de la funda: del brazo del servo a la salida de F5 (X, Y, Z)."""
    if nombre == "prof":
        return np.array([SERVO_X[0] + 6.0, -9.0, SUELO_Z + 20.0]), np.array([735.0, -6.5, 3.75])
    return np.array([SERVO_X[1] + 6.0, 9.0, SUELO_Z + 20.0]), np.array([735.0, 5.5, P.fus_lomo(735) - 3.0])


def guias_posiciones():
    nombres = ["prof", "timon"] if CON_TIMON else ["prof"]
    return [(x, nm) for nm in nombres for x in (370.0, 470.0, 570.0, 675.0)]


def _punto_linea(nombre, x):
    p0, p1 = _linea_transmision(nombre)
    t = (x - p0[0]) / (p1[0] - p0[0])
    return p0 + t * (p1 - p0)


def guia(x, nombre, largo=10.0, r_ext=3.0):
    """Anillo de 10 mm por el que pasa la funda, unido a la pared del costado por un alma de 2 mm; por
    debajo (al imprimir) un apoyo a 45 grados hasta la pared."""
    p = _punto_linea(nombre, x)
    sy = -1 if p[1] < 0 else 1
    w, h, zc = P.fus_seccion(x)
    y_pared = sy * (w - WALL_F + 0.3)
    alma = CrossSection.square([abs(y_pared - p[1]), 2.0]).translate([min(y_pared, p[1]), p[2] - 1.0])
    perfil = CrossSection.circle(r_ext).translate([p[1], p[2]]) + alma                    # en el plano (Y, Z)
    def a_x(cs, x0, l):        # extruye el perfil (Y, Z) a lo largo de X
        return Manifold.extrude(cs, l).transform([[0, 0, 1, x0], [1, 0, 0, 0], [0, 1, 0, 0]])
    cuerpo = a_x(perfil, x, largo)
    alcance = abs(y_pared - p[1]) + r_ext
    apoyo = Manifold.batch_hull([a_x(perfil, x, 0.01),
                                 a_x(CrossSection.square([0.6, 2 * r_ext]).translate([y_pared - (0.6 if sy > 0 else 0), p[2] - r_ext]), x - alcance, 0.01)])
    return (cuerpo + apoyo) ^ solid(x - alcance - 1, x + largo + 1)


def guias_agujeros(a, b):
    """Taladro de la funda (3,2 mm: vale para fundas de 2 y de 3 mm) a lo largo de cada transmision."""
    out = None
    for nm in (["prof", "timon"] if CON_TIMON else ["prof"]):
        p0, p1 = _linea_transmision(nm)
        d = p1 - p0; L = np.linalg.norm(d)
        cil = Manifold.cylinder(L, 1.6)                                   # a lo largo de Z
        u = d / L
        # girar Z -> u
        ang = np.degrees(np.arccos(u[2])); eje = np.cross([0, 0, 1], u)
        R = _rot(eje, np.radians(ang))
        cil = cil.transform(np.c_[R, p0].tolist())
        out = cil if out is None else out + cil
    return out ^ Manifold.cube([b - a + 40, 200, 200]).translate([a - 20, -100, -100])


# ---------------- larguerillos ----------------
# Varillas de carbono de 2 mm por dentro de las 4 esquinas del fuselaje, en vainas impresas pegadas a la pared.
# El fuselaje se imprime de pie: un golpe que lo flexiona intenta despegar capa de capa, que es como peor aguanta
# una pieza impresa; las varillas llevan esa traccion y atan las uniones F2|F3, F3|F4 y F4|F5. Como la seccion
# es constante hasta X_TAPER y luego se estrecha en linea recta, las varillas son tramos rectos:
#  - abajo (dos esquinas): una en la parte recta, desde detras de los servos, y otra en la conica
#  - arriba (dos esquinas): solo en la conica, desde detras del palillo de atras del ala (X 369, que cruza el
#    fuselaje a esa altura). Delante el techo es la escotilla del ala, abierta
# Todas acaban antes de la ranura del estabilizador.
LARG_D, LARG_R = 2.3, 2.6          # agujero de la varilla de 2 mm y radio exterior de la vaina
LARG_TRAMOS = [(-1, P.X_LE + 30.0, P.X_TAPER - 1.0), (-1, P.X_TAPER + 1.0, P.HT_XLE - 5.0),   # (abajo -1 / arriba +1, desde, hasta)
               (1, max(P.X_TAPER + 8.0, DOWELS[1][0] + 10.0), P.HT_XLE - 5.0)]       # las de arriba, detras del taco del palillo


def larg_centro(X, sy, sz=-1):
    """Centro de la varilla en X: dentro de la esquina (sy = -1 izquierda, +1 derecha; sz = -1 abajo, +1 arriba),
    con la vaina metida 0,3 mm en la pared para que quede soldada a ella."""
    w, h, zc = P.fus_seccion(X)
    rc = corner_r(w); r_in = rc - WALL_F
    d = (r_in - LARG_R + 0.3) / np.sqrt(2)
    return np.array([X, sy * (w - rc) + sy * d, zc + sz * (h - rc + d)])


def _cil_entre(p0, p1, r):
    """Cilindro de radio r de p0 a p1."""
    p0, p1 = np.asarray(p0, float), np.asarray(p1, float)
    dd = p1 - p0; L = np.linalg.norm(dd); u = dd / L
    R = _rot(np.cross([0, 0, 1], u), np.arccos(np.clip(u[2], -1, 1)))
    return Manifold.cylinder(L, r).transform(np.c_[R, p0].tolist())


def vainas_larguerillos(a, b, k):
    """Vainas de este tramo, desde despues del cuello del tramo anterior; al principio de cada vaina, un cono a
    45 grados hasta la pared (al imprimir el tramo de pie la vaina no arranca en el aire)."""
    out = None
    for (sz, x0, x1) in LARG_TRAMOS:
        xa = max(x0, a + (SPIGOT_L + 1.0 + 2 * LARG_R + 0.5 if k > 0 else 0.0)); xb = min(x1, b)   # el cono no pisa el cuello
        if xb - xa < 5: continue
        for sy in (-1, 1):
            p0, p1 = larg_centro(xa, sy, sz), larg_centro(xb, sy, sz)
            w, h, zc = P.fus_seccion(xa); rc = corner_r(w)
            pared = np.array([xa - 2 * LARG_R, sy * (w - rc) + sy * (rc - WALL_F) / np.sqrt(2), zc + sz * (h - rc + (rc - WALL_F) / np.sqrt(2))])
            u = (p1 - p0) / np.linalg.norm(p1 - p0)
            cono = Manifold.batch_hull([_cil_entre(p0, p0 + u * 0.05, LARG_R), Manifold.sphere(0.4).translate(pared.tolist())])
            pieza = _cil_entre(p0, p1, LARG_R) + cono
            out = pieza if out is None else out + pieza
    if out is None: return Manifold()
    return out ^ solid(a - 1, b)


def agujeros_larguerillos(a, b):
    out = None
    for (sz, x0, x1) in LARG_TRAMOS:
        for sy in (-1, 1):
            h = _cil_entre(larg_centro(x0 - 1.0, sy, sz), larg_centro(x1 + 1.0, sy, sz), LARG_D / 2)
            out = h if out is None else out + h
    return out ^ Manifold.cube([b - a + 40, 200, 200]).translate([a - 20, -100, -100])


# ---------------- cuadernas ----------------
# Un marco a mitad de cada tramo: anillo pegado a la pared por dentro, de CUAD_T mm de grueso y CUAD_D de ancho
# (menos en la cola, donde la seccion es pequena), con la cara de abajo a 45 grados para imprimirlo de pie sin
# soportes. Ata las cuatro paredes entre si y abraza las vainas de los larguerillos (las varillas lo atraviesan).
#  - F1: sin travesano de abajo entre los carriles, para que la bateria siga entrando
#  - F2: en U, abierta por arriba, porque el techo bajo el ala es la escotilla
#  - las transmisiones lo atraviesan por su taladro: hace ademas de guia
CUADERNAS_X = [88.0, P.X_LE + 80.0, 415.0, 570.0, 670.0]   # entre las ranuras del velcro (F1), detras de los servos (F2),
                                                    # delante de la ranura del estabilizador (F5)
CUAD_D, CUAD_T = 5.0, 2.5


def cuaderna(k):
    xm = CUADERNAS_X[k]
    w, h, zc = P.fus_seccion(xm)
    D = min(CUAD_D, 0.3 * w)
    ext = Manifold.batch_hull([slab(xm - D, WALL_F - 0.2), slab(xm + CUAD_T, WALL_F - 0.2)])
    hueco = Manifold.batch_hull([slab(xm - D - 0.01, WALL_F), slab(xm, WALL_F + D), slab(xm + CUAD_T + 0.01, WALL_F + D)])
    c = ext - hueco
    if k == 0:       # paso de la bateria entre los carriles
        c = c - Manifold.cube([20, 41.0, 20]).translate([xm - 10, -20.5, SUELO_Z + D + 1 - 20])
    if P.X_LE <= xm <= P.X_LE + P.C:   # bajo la escotilla del ala: solo hasta donde arrancan las paredes del asiento
        c = c ^ Manifold.cube([20, 2 * w + 2, 200]).translate([xm - 10, -w - 1, zc + h - corner_r(w) - 1.0 - 200])
    return c


def ranura_estab():
    """Ranura del estabilizador en F5 (abierta por detras)."""
    return Manifold.cube([X_HINGE_H - P.HT_XLE + 5, 2 * P.HT_B, PLATE_T + 0.3]).translate(
        [-0.15, -P.HT_B, -(PLATE_T + 0.3) / 2]).rotate([0, P.HT_INC, 0]).translate([P.HT_XLE, 0, P.HT_Z])


def _rot(eje, ang):
    eje = np.asarray(eje, float); n = np.linalg.norm(eje)
    if n < 1e-12: return np.eye(3)
    k = eje / n; K = np.array([[0, -k[2], k[1]], [k[2], 0, -k[0]], [-k[1], k[0], 0]])
    return np.eye(3) + np.sin(ang) * K + (1 - np.cos(ang)) * K @ K


def salida(nombre):
    """Ventana de salida de la funda en F5, centrada en el final de la recta de la transmision."""
    p = _linea_transmision(nombre)[1]
    if nombre == "prof":       # costado izquierdo, por encima del estabilizador
        return Manifold.cube([16.0, 20.0, 4.0]).translate([p[0] - 8.0, -20.0, p[2] - 2.0])
    return Manifold.cube([22.0, 6.0, 8.0]).translate([p[0] - 11.0, 3.0, p[2] - 1.0])   # lomo, a la derecha de la deriva


# ---------------- cola ----------------
def plate_cs(c, t, le_round=True, te_t=None):
    """Seccion de placa con la cara inferior plana (se imprime tumbada): borde de ataque redondeado
    por arriba y, si te_t, afinada linealmente hasta te_t en el borde de fuga."""
    pts = []
    if le_round:
        pts += [(t * (1 - np.cos(a)), t * np.sin(a)) for a in np.linspace(0, np.pi / 2, 10)]
    else:
        pts += [(0, 0), (0, t)]
    pts += [(c, te_t if te_t else t), (c, 0)]
    return CrossSection([ccw(pts)])


# Bisagra de la profundidad: el eje esta EJE_H mm detras del borde de fuga del estabilizador y a EJE_HZ del
# fondo de la placa (el nudillo de radio NUDILLO_R no baja del fondo: las placas se imprimen tumbadas y
# sobresale 1,2 mm por arriba). El estabilizador lleva una acanaladura concava a lo largo del eje y nudillos
# cada 50 mm; la profundidad, el canto delantero redondo alrededor del eje y huecos donde entran los nudillos.
EJE_H, EJE_HZ = 1.2, NUDILLO_R
NUDILLOS_H = (25.0, 75.0, 125.0, 175.0)        # inicio de cada nudillo (mm desde el centro), 8 mm de largo


def _cil_y(largo, r, x, y0, z):
    """Cilindro a lo largo de -Y, de y0 a y0 - largo, con eje en (x, z)."""
    return Manifold.cylinder(largo, r).rotate([90, 0, 0]).translate([x, y0, z])


SOLAPE_H, SOLAPE_HOLGURA = 20.0, 0.2       # solape a media madera entre las dos mitades del estabilizador


def stab_half(solape="arriba"):
    """Media placa fija del estabilizador (local: cuerda X, espesor Z, envergadura Y de 0 a -HT_B/2). Las dos
    mitades se unen en el centro, dentro de la ranura de F5, con un solape a media madera de SOLAPE_H mm:
    cada una prolonga mas alla del centro solo media placa (la izquierda la de arriba, la derecha la de abajo)
    y vacia la otra media en su raiz, y las varillas de 2 mm atraviesan el solape. La derecha se construye
    como izquierda con solape="abajo" y se refleja."""
    c = P.ELEV_HINGE * P.HT_C
    xe = c + EJE_H
    m = Manifold.extrude(plate_cs(c, PLATE_T), P.HT_B / 2).rotate([90, 0, 0])   # envergadura hacia -Y (mitad izquierda)
    lengua = Manifold.extrude(plate_cs(c, PLATE_T), SOLAPE_H).rotate([90, 0, 0]).translate([0, SOLAPE_H, 0])   # y de 0 a +SOLAPE_H
    zc = PLATE_T / 2
    if solape == "arriba":
        lengua = lengua ^ Manifold.cube([c + 2, SOLAPE_H + 2, PLATE_T]).translate([-1, -1, zc + SOLAPE_HOLGURA / 2])
        raiz = Manifold.cube([c + 2, SOLAPE_H + 1, zc - SOLAPE_HOLGURA / 2 + 1]).translate([-1, -SOLAPE_H, -1])   # quita la media de abajo
    else:
        lengua = lengua ^ Manifold.cube([c + 2, SOLAPE_H + 2, zc - SOLAPE_HOLGURA / 2 + 1]).translate([-1, -1, -1])
        raiz = Manifold.cube([c + 2, SOLAPE_H + 1, PLATE_T]).translate([-1, -SOLAPE_H, zc + SOLAPE_HOLGURA / 2])   # quita la media de arriba
    m = m + lengua - raiz
    # las dos mitades se unen ademas con varillas de 2 mm al 25 % y al 70 % de la placa, 50 mm dentro de cada una
    for u in (0.25, 0.70):
        m = m - Manifold.cylinder(51 + SOLAPE_H, HT_PIN_D / 2).rotate([90, 0, 0]).translate([u * c, SOLAPE_H + 1, PLATE_T / 2])
    m = m - _cil_y(P.HT_B / 2 + 2 + SOLAPE_H, NUDILLO_R + 0.4, xe, SOLAPE_H + 1, EJE_HZ)    # acanaladura de la bisagra
    for yk in NUDILLOS_H:
        nud = _cil_y(NUDILLO_L, NUDILLO_R, xe, -yk, EJE_HZ) + Manifold.cube([xe - (c - 4.0), NUDILLO_L, PLATE_T]).translate([c - 4.0, -yk - NUDILLO_L, 0])
        m = m + nud
    return m - _cil_y(P.HT_B / 2 + 2 + SOLAPE_H, PIN_LIBRE / 2, xe, SOLAPE_H + 1, EJE_HZ)   # el pasador gira libre aqui


def elevator_half(con_horn=False):
    """Media profundidad (local: X desde el eje de la bisagra, envergadura 0 a -HT_B/2, fondo en Z = 0). Canto
    delantero redondo alrededor del eje, huecos para los nudillos del estabilizador y el pasador de 2 mm
    pegado (une las dos mitades). con_horn: horn impreso encima, a 14 mm del centro, con 3 agujeros de 1 mm
    para el doblez en Z del alambre, en la vertical del eje."""
    ce = P.HT_XLE + P.HT_C - (X_HINGE_H + EJE_H)
    m = Manifold.extrude(plate_cs(ce, PLATE_T, le_round=False, te_t=TE_T), P.HT_B / 2).rotate([90, 0, 0])
    m = m + _cil_y(P.HT_B / 2, NUDILLO_R, 0.0, 0.0, EJE_HZ)
    for yk in NUDILLOS_H:
        m = m - _cil_y(NUDILLO_L + 2 * NUDILLO_HOLGURA, NUDILLO_R + 0.4, 0.0, -yk + NUDILLO_HOLGURA, EJE_HZ)
    m = m - _cil_y(P.HT_B / 2 + 2, PIN_PEGADO / 2, 0.0, 1, EJE_HZ)
    if con_horn:
        zt = EJE_HZ + 12.5
        horn = Manifold.extrude(CrossSection([ccw([(-1.8, 2.0), (11.0, 2.0), (1.4, zt), (-1.4, zt)])]), 2.0).rotate([90, 0, 0]).translate([0, -13.0, 0])
        for dz in (6.0, 8.5, 11.0):
            horn = horn - _cil_y(4.0, 0.5, 0.0, -12.0, EJE_HZ + dz)
        m = m + horn
    return m


def fin_profile_pts(c, t, te_t):
    """Seccion simetrica de la deriva (en planta X-Y): canto de ataque redondeado, recta, y afinada."""
    up = [(t / 2 * (1 - np.cos(a)), t / 2 * np.sin(a)) for a in np.linspace(0, np.pi / 2, 10)] + [(c, te_t / 2)]
    return [(x, y) for x, y in up] + [(x, -y) for x, y in up[::-1]]


# Bisagra del timon (E1): eje vertical EJE_H mm detras del final del fuselaje, en y = 0. Nudillos en la deriva
# (que al imprimir F5 de pie salen hacia arriba por su extremo) y canto delantero redondo en el timon.
X_EJE_T = P.L + EJE_H


def _z_timon():
    return P.fus_lomo(P.L) + 1.0, fin_tip_z()


def _nudillos_t():
    z0, z1 = _z_timon()
    return [z0 + 12.0 + 40.0 * k for k in range(4) if z0 + 12.0 + 40.0 * k + NUDILLO_L < z1 - 8.0]


def fin_fixed():
    """Parte fija de la deriva en global: X de FIN_XLE a L (120 mm), desde dentro del lomo hasta la punta.
    Sin timon (E2) la deriva es toda la cuerda FIN_C, con el borde de fuga afinado. Con timon lleva la
    acanaladura y los nudillos de la bisagra."""
    c = P.L - P.FIN_XLE if CON_TIMON else P.FIN_C
    cs = CrossSection([ccw(fin_profile_pts(c, PLATE_T, PLATE_T if CON_TIMON else TE_T))])
    z0, z1 = P.fus_lomo(P.FIN_XLE) - 12.0, fin_tip_z()
    m = Manifold.extrude(cs, z1 - z0).translate([P.FIN_XLE, 0, z0])
    if CON_TIMON:
        zt0, zt1 = _z_timon()
        m = m - Manifold.cylinder(zt1 - zt0 + 2.0, NUDILLO_R + 0.4).translate([X_EJE_T, 0, zt0 - 0.5])
        for zk in _nudillos_t():
            m = m + Manifold.cylinder(NUDILLO_L, NUDILLO_R).translate([X_EJE_T, 0, zk])
            m = m + Manifold.cube([X_EJE_T - (P.L - 4.0), PLATE_T, NUDILLO_L]).translate([P.L - 4.0, -PLATE_T / 2, zk])
        m = m - Manifold.cylinder(zt1 - zt0 + 4.0, PIN_LIBRE / 2).translate([X_EJE_T, 0, zt0 - 1.0])
    return m


def fin_tip_z():
    return P.fus_lomo(P.FIN_XLE + 0.5 * P.FIN_C) + P.FIN_H


def rudder():
    """Timon en global: del eje de la bisagra (canto delantero redondo) al borde de fuga, del lomo en la cola
    a la punta, con huecos para los nudillos de la deriva, el pasador vertical de 2 mm pegado y el horn
    impreso abajo a la derecha (en la cara de apoyo al imprimir: el timon se imprime de pie)."""
    c = P.FIN_XLE + P.FIN_C - X_EJE_T
    cs = CrossSection([ccw([(0, PLATE_T / 2), (c, TE_T / 2), (c, -TE_T / 2), (0, -PLATE_T / 2)])])
    z0, z1 = _z_timon()
    m = Manifold.extrude(cs, z1 - z0).translate([X_EJE_T, 0, z0])
    m = m + Manifold.cylinder(z1 - z0, NUDILLO_R).translate([X_EJE_T, 0, z0])
    for zk in _nudillos_t():
        m = m - Manifold.cylinder(NUDILLO_L + 2 * NUDILLO_HOLGURA, NUDILLO_R + 0.4).translate([X_EJE_T, 0, zk - NUDILLO_HOLGURA])
    m = m - Manifold.cylinder(z1 - z0 + 2.0, PIN_PEGADO / 2).translate([X_EJE_T, 0, z0 - 1.0])
    horn = Manifold.extrude(CrossSection([ccw([(-0.8, 2.2), (11.0, 1.0), (1.4, 14.0), (-1.4, 14.0)])]), 2.0)   # a +-25 grados no toca la deriva
    for dy in (7.0, 9.5, 12.0):
        horn = horn - Manifold.cylinder(4.0, 0.5).translate([0.0, dy, -1.0])
    return m + horn.translate([X_EJE_T, 0, z0])


def stab_global(left):
    g = stab_half("arriba" if left else "abajo").translate([0, 0, -PLATE_T / 2]).rotate([0, P.HT_INC, 0]).translate([P.HT_XLE, 0, P.HT_Z])
    return g if left else g.mirror([0, 1, 0])


def elevator_global(left):
    g = elevator_half(con_horn=left).translate([X_HINGE_H + EJE_H - P.HT_XLE, 0, -PLATE_T / 2]).rotate([0, P.HT_INC, 0]).translate([P.HT_XLE, 0, P.HT_Z])
    return g if left else g.mirror([0, 1, 0])


# ---------------- montaje ----------------
def build():
    parts, glob = {}, {}
    for k in range(len(FUS_SEG)):
        g = fuselage_segment(k)
        nm = "F%d" % (k + 1)
        glob[nm] = g
        # de pie: F1 sobre la bancada (girada DOWNTHRUST para que la cara inclinada apoye plana); los demas sobre su
        # cara delantera (el cuello queda arriba)
        parts[nm] = g.rotate([0, -90, 0])
    glob["CUNA_MOTOR"] = cuna_motor()
    parts["CUNA_MOTOR"] = cuna_motor().rotate([0, 90, 0])             # tumbada sobre su cara trasera (plana)
    for k, (nm, s0, s1) in enumerate(TRAMOS):
        corte = servo_s = None
        if ALERON and ALERON["y0"] < s1 and ALERON["y1"] > s0:
            corte = (max(ALERON["y0"], s0) - s0, min(ALERON["y1"], s1) - s0)
        if ALERON and s0 < ALERON["servo_y"] < s1:
            servo_s = ALERON["servo_y"] - s0
        canal = None
        if ALERON and s0 < ALERON["servo_y"]:      # el canal del cable va del cajeado del servo hacia la raiz
            canal = (-1.0, servo_s if servo_s is not None else s1 - s0 + 1.0)
        seg = parts[nm] if nm in parts else wing_segment(s1 - s0, corte=corte, servo_s=servo_s, canal=canal)
        parts[nm] = seg
        for s, left in (("izq", True), ("der", False)):
            glob["ALA%d_%s" % (k + 1, s)] = wing_to_global(seg, s0, left)
    if ALERON:
        for nm, y0, y1 in ALERON["tramos"]:
            horn_s = ALERON["servo_y"] - y0 if y0 < ALERON["servo_y"] < y1 else None
            pieza = aileron_segment(y1 - y0, horn_s)
            parts[nm] = pieza
            for s, left in (("izq", True), ("der", False)):
                glob[nm.split("_x")[0] + "_" + s] = wing_to_global(pieza, y0, left)
    seg_c, glob["ALA_C"] = center_piece()
    parts["ALA_C"] = seg_c
    q = quiebro_piece()
    glob["ALA_Q_izq"], glob["ALA_Q_der"] = q, q.mirror([0, 1, 0])
    parts["ALA_Q_izq"] = quiebro_print(q)
    for s, left in (("izq", True), ("der", False)):
        glob["ESTAB_" + s] = stab_global(left)
        glob["PROF_" + s] = elevator_global(left)
    parts["ESTAB_izq"] = stab_half("arriba")           # solape de arriba
    parts["ESTAB_der"] = stab_half("abajo").mirror([0, 1, 0])   # solape de abajo
    parts["PROF_izq"] = elevator_half(con_horn=True)   # con el horn
    parts["PROF_der"] = elevator_half().mirror([0, 1, 0])
    if CON_TIMON:
        glob["TIMON"] = rudder()
        parts["TIMON"] = rudder()                          # de pie sobre su canto inferior, con el horn en la cama
    for nm in list(parts):
        parts[nm] = to_print(parts[nm])
    return parts, glob


if __name__ == "__main__":
    import shutil, time
    t0 = time.time()
    os.makedirs(OUT, exist_ok=True)
    write_dat(os.path.join(OUT, "NACA2412.dat"))
    shutil.rmtree(os.path.join(OUT, "stl"), ignore_errors=True); os.makedirs(os.path.join(OUT, "stl"))
    parts, glob = build()
    info = {}
    for nm, m in parts.items():
        write_stl(m, os.path.join(OUT, "stl", nm + ".stl"))
        bb = m.bounding_box()
        info[nm] = dict(size=[round(bb[3] - bb[0], 1), round(bb[4] - bb[1], 1), round(bb[5] - bb[2], 1)],
                        vol=m.volume() / 1000, genus=m.genus(), ok=str(m.status()), tris=m.num_tri())
    gi = {nm: dict(vol=m.volume() / 1000, area=m.surface_area() / 100, cg=centroid(m).tolist(),
                   bb=list(m.bounding_box())) for nm, m in glob.items()}
    # interferencias entre piezas montadas (deberian ser ~0)
    nombres = list(glob)
    inter = {}
    for i in range(len(nombres)):
        for j in range(i + 1, len(nombres)):
            a, b = glob[nombres[i]], glob[nombres[j]]
            ba, bb_ = a.bounding_box(), b.bounding_box()
            if all(ba[d] < bb_[d + 3] and bb_[d] < ba[d + 3] for d in range(3)):
                v = (a ^ b).volume()
                if v > 0.5: inter[nombres[i] + "|" + nombres[j]] = round(v, 1)
    fin_vol = (fin_fixed() - solid(FUS_SEG[-1][0] - 1, P.L + 1)).volume() / 1000   # deriva fuera del fuselaje (maciza en la malla)
    json.dump(dict(avion=ID, parts=info, glob=gi, inter=inter, Z_LE=Z_LE, fin_vol=fin_vol), open(os.path.join(OUT, "info.json"), "w"), indent=1)
    pickle.dump({k: (np.asarray(m.to_mesh().vert_properties)[:, :3], np.asarray(m.to_mesh().tri_verts)) for k, m in glob.items()},
                open(os.path.join(OUT, "glob_meshes.pkl"), "wb"))
    for nm, v in info.items(): print(f"{nm:12s} {v['size']} vol={v['vol']:.1f} cm3 genus={v['genus']} {v['ok']}")
    print("%s | interferencias (mm3):" % ID, inter or "ninguna")
    print("%.0f s" % (time.time() - t0))
