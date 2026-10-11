"""Avión tándem impreso 3D — versión B (tractora). Genera STL, perfil .dat y datos para planos.

Revisión 2026-10-11 (mejoras de los entrenadores E1/E2/E3 aplicadas aquí, ver README del repo):
  - pared del tubo de 1,2 mm (3 líneas de 0,4) en vez de 0,8 (WALL); todo se imprime en PLA normal
  - cuello de unión F1|F2 de 15 mm (COLLAR), radios derivados de la pared
  - bancada del motor para el SunnySky X2212 (cruz 16 x 19 mm, M3) en vez del 1404
  - bisagras de NUDILLOS en los elevones con pasador de carbono de 2 mm (pegado al elevón, libre en el ala)
  - palillos de las gomas de carbono macizo de 4 mm (DOWEL_D)
  - suelos con ranuras para cinta de velcro de 20 mm: batería 3S 1300 en F2, ESC en F3, receptor en F4
Ejes globales: X a lo largo del fuselaje (0 = cara del soporte motor, positivo hacia la cola),
Y envergadura (derecha +), Z arriba. Unidades: mm."""
import numpy as np, json, os, struct
from manifold3d import Manifold, CrossSection, set_circular_segments

set_circular_segments(96)
OUT = os.path.join(os.path.dirname(__file__), "out")
os.makedirs(os.path.join(OUT, "stl"), exist_ok=True)

# ---------------- Parámetros ----------------
R = 25.0          # radio exterior fuselaje (Ø50)
WALL = 1.2        # pared del tubo: 3 líneas de 0,4 (el E1 pasó a 1,6 por ser LW-PLA y de sección rectangular;
                  # el tubo de 50 en PLA normal es mucho más rígido: con 1,6 pesaría 70 g más). Cambiar y regenerar
RIN = R - WALL    # 23.8
SH = 30.0          # morro alargado 30 mm para centrar el CG
L = 450.0 + SH
SEG = [(0, 70+SH), (70+SH, 220+SH), (220+SH, 325+SH), (325+SH, L)]   # tramos fuselaje
COLLAR = 15.0                   # cuello macho de F2 que entra a presión en F1 (los entrenadores pasaron de 10 a 15)
COLLAR_R0, COLLAR_R1 = RIN - 0.9, RIN - 0.1   # radios interior y exterior del cuello
C_F, C_R = 85.0, 95.0     # cuerdas
B = 600.0                 # envergadura de ambas alas
X_LE_F, X_LE_R = 80.0 + SH, 335.0 + SH
INC_F, INC_R = 2.0, 0.0   # calado (grados, morro arriba)
WASHOUT = 1.5             # torsión en punta ala delantera
HINGE = 0.75              # línea de bisagra elevón (fracción de cuerda)
GAP = 0.6                 # (ya no se usa en la bisagra: ver NUDILLO_*)
SPAR_D = 4.2              # larguero principal: tubo de carbono 4x3 mm (25 % cuerda)
SPAR2_D = 2.2             # larguero secundario: varilla de carbono 2 mm (50 % cuerda)
SPAR2_X = 0.50
SPAR2_SLOT = 0.7          # holgura vertical extra en el ala delantera (torsión)
PIN_D_WING, PIN_D_SEAT = 2.3, 2.15   # pines de centrado ala-asiento (varilla 2 mm)
PIN_U, PIN_Y = 0.15, 12.0            # a 15 % de cuerda, a ±12 mm del plano de simetría
DOWEL_D = 4.2             # palillos de las gomas: carbono MACIZO de 4 mm (como en los entrenadores)
# --- bisagra de nudillos de los elevones (como los alerones del E2, a la escala de un perfil de 3,5 mm) ---
NUDILLO_R, NUDILLO_L, NUDILLO_HOLGURA = 2.1, 8.0, 0.5   # radio (pared de 1 mm alrededor del pasador), largo, holgura
NUDILLO_OFF = (16.0, 48.0)      # nudillos del ala a +-16 y +-48 mm del centro de cada elevón (simétricos: una sola
                                # pieza de elevón vale para los dos lados); no cruzan las juntas de los tramos del ala
PIN_HINGE_D = 2.2               # pasador de carbono de 2 mm (pegado al elevón, libre en los nudillos del ala)
MOTOR_X2212 = [(8.0, 0.0), (-8.0, 0.0), (0.0, 9.5), (0.0, -9.5)]   # cruz del X2212: 16 x 19 mm, M3
VELCRO_L, VELCRO_W = 22.0, 2.6  # ranuras para cinta de velcro de 20 mm
SEAT_HALF = 15.0
# --- estructura interna tipo cohete ---
STR_RC, STR_R, STR_HOLE = 21.8, 2.6, 2.3      # larguerillos: radio de centros, vaina, agujero (varilla C 2 mm)
STR_ANG = (45, 135, 225, 315)
STR_X0, STR_X1 = 112.0, 465.0                 # tramo de los larguerillos (F2..F4)
FL_RIN, FL_T = 18.5, 1.2                      # bridas de unión: radio interior, espesor de la cara
# --- chavetas antigiro ---
KEY_F1 = [(0.0, 3.0), (180.0, 5.0)]          # junta F1|F2: (ángulo, ancho) de las chavetas internas (anchos distintos = posición única)
KEY_R0, KEY_R1, KEY_X0, KEY_X1 = COLLAR_R0 - 0.7, RIN + 0.2, 70.0 + SH - COLLAR + 0.4, 70.0 + SH
STUD_ANG, STUD_RC = (90.0, 210.0, 330.0), 22.3   # juntas de brida: 3 tetones Ø3 (patrón a 120°, junto con los larguerillos solo encaja en una posición)
STUD_R, STUD_H, SOCK_R, SOCK_H = 1.5, 2.5, 1.65, 2.8
RINGS = {1: (106.0, 232.0), 2: (300.0,), 3: (395.0, 435.0)}   # anillos 45° (cuadernas ligeras) por tramo. Los de F2 van
                                                              # fuera de la zona de la batería (X 110-230: sus esquinas
                                                              # a r 22,4 tocarían un anillo, que entra hasta r 20,8)
# --- alas ---
WSEG = 100.0                                  # tramos de ala de 100 mm (3 por semiala)
SKIN, RIB_T, CAP = 0.45, 0.45, 0.6              # piel, nervios de celosía, tapas de los extremos
RIB_P = 30.0                                  # paso de la celosía diagonal (mm, a lo largo de la cuerda)
SERVO_L, SERVO_W = 20.6, 9.0          # hueco para servo 20x8,5 mm
SERVO_WIN = [(312.0, -1), (312.0, +1)]  # en F3, enfrentados (18 mm de fondo cada uno, no chocan)
SERVO_Z = 5.0

# ---------------- Perfil NACA 3407 (TE cerrado) ----------------
def naca4(m, p, t, n=90):
    beta = np.linspace(0, np.pi, n)
    x = 0.5 * (1 - np.cos(beta))
    yt = 5 * t * (0.2969*np.sqrt(x) - 0.1260*x - 0.3516*x**2 + 0.2843*x**3 - 0.1036*x**4)
    yc = np.where(x < p, m/p**2*(2*p*x - x**2), m/(1-p)**2*((1-2*p) + 2*p*x - x**2))
    dyc = np.where(x < p, 2*m/p**2*(p - x), 2*m/(1-p)**2*(p - x))
    th = np.arctan(dyc)
    xu, yu = x - yt*np.sin(th), yc + yt*np.cos(th)
    xl, yl = x + yt*np.sin(th), yc - yt*np.cos(th)
    return (xu, yu), (xl, yl), (x, yc)

(XU, YU), (XL, YL), (XC, YC) = naca4(0.03, 0.4, 0.07)

def camber_at(u):
    return float(np.interp(u, XC, YC))

def section_pts(c):
    """Polígono CCW: extradós TE->LE, intradós LE->TE (sin repetir puntos)."""
    up = np.c_[XU[::-1], YU[::-1]] * c
    lo = np.c_[XL[1:-1], YL[1:-1]] * c
    return np.vstack([up, lo])

def write_dat(path):
    with open(path, "w") as f:
        f.write("NACA 3407\n")
        for x, y in zip(XU[::-1], YU[::-1]): f.write(f"{x:.6f} {y:.6f}\n")
        for x, y in zip(XL[1:], YL[1:]): f.write(f"{x:.6f} {y:.6f}\n")

def wing_cs(c, slot=False):
    """Sección con origen en el larguero (25 % cuerda, sobre línea media) + agujero."""
    us, vs = 0.25*c, camber_at(0.25)*c
    pts = section_pts(c) - [us, vs]
    cs = CrossSection([pts.tolist()])
    cs = cs - CrossSection.circle(SPAR_D/2)
    x2, y2 = SPAR2_X*c - us, camber_at(SPAR2_X)*c - vs
    r2 = SPAR2_D/2
    if slot:   # ranura vertical (estadio) para que una varilla recta pase por el ala con torsión
        h = SPAR2_SLOT
        cs = cs - (CrossSection.circle(r2).translate([x2, y2 - h/2]) + CrossSection.circle(r2).translate([x2, y2 + h/2])
                   + CrossSection.square([2*r2, h]).translate([x2 - r2, y2 - h/2]))
    else:
        cs = cs - CrossSection.circle(r2).translate([x2, y2])
    return cs, (us, vs)

def pin_hole_wing(c, us, vs, upper):
    """Agujero ciego de 2,5 mm en la cara que apoya en el asiento, a z=PIN_Y del plano de simetría."""
    u = PIN_U*c
    if upper:
        v = float(np.interp(PIN_U, XU, YU))*c; y0 = v - 2.5
    else:
        v = float(np.interp(PIN_U, XL, YL))*c; y0 = v - 1.0
    return Manifold.cylinder(3.5, PIN_D_WING/2).rotate([-90, 0, 0]).translate([u - us, y0 - vs, PIN_Y])

# ---------------- Utilidades ----------------
def write_stl(man, path):
    mesh = man.to_mesh()
    v = np.asarray(mesh.vert_properties)[:, :3]; t = np.asarray(mesh.tri_verts)
    with open(path, "wb") as f:
        f.write(b"\0"*80); f.write(struct.pack("<I", len(t)))
        for tri in t:
            a, b, c = v[tri]
            n = np.cross(b-a, c-a); n = n/(np.linalg.norm(n) or 1)
            f.write(struct.pack("<12fH", *n, *a, *b, *c, 0))

def centroid(man):
    mesh = man.to_mesh()
    v = np.asarray(mesh.vert_properties)[:, :3]; t = np.asarray(mesh.tri_verts)
    a, b, c = v[t[:, 0]], v[t[:, 1]], v[t[:, 2]]
    vol = np.einsum("ij,ij->i", a, np.cross(b, c)) / 6
    return ((a+b+c)/4 * vol[:, None]).sum(0) / vol.sum()

def to_print(man):
    """Coloca la pieza con su mínimo en z=0 y centrada en XY."""
    (x0, y0, z0, x1, y1, z1) = man.bounding_box()
    return man.translate([-(x0+x1)/2, -(y0+y1)/2, -z0])

def along_x(man):   # eje Z local -> X global
    return man.rotate([0, 90, 0])    # (x,y,z)->(z,y,-x)

def revolve_profile(pts):
    """pts: lista (r, X). Revoluciona y alinea con X global."""
    p = np.array(pts, float)
    a = 0.5*np.sum(p[:, 0]*np.roll(p[:, 1], -1) - np.roll(p[:, 0], -1)*p[:, 1])
    if a < 0: p = p[::-1]
    cs = CrossSection([p.tolist()])
    return along_x(Manifold.revolve(cs, 96))

def r_out(X):
    if X <= 9:    # cono del morro a 45° (imprimible desde la placa motor): r16 en X=0 -> r25 en X=9
        return 16 + X
    if X >= L - 12:
        return 25 - 11*(X - (L - 12))/12
    return R

def annulus(a, b, r0a, r1a, r0b=None, r1b=None):
    """Anillo entre radios r0..r1 (pueden cambiar de a a b)."""
    r0b = r0a if r0b is None else r0b; r1b = r1a if r1b is None else r1b
    return revolve_profile([(r0a, a), (r1a, a), (r1b, b), (r0b, b)])

def cyl_x(x0, x1, r):
    return along_x(Manifold.cylinder(x1-x0, r)).translate([x0, 0, 0])

def hole_y(X, Z, d, length=80):
    return Manifold.cylinder(length, d/2, center=True).rotate([90, 0, 0]).translate([X, 0, Z])

def hole_x(X0, Y, Z, d, length=10):
    return along_x(Manifold.cylinder(length, d/2)).translate([X0, Y, Z])

# ---------------- Posición de alas y asientos ----------------
def placed_surface(c, xle, inc, which):
    """Extradós ('up') o intradós ('lo') en coords globales (X,Z) con Z_LE=0."""
    xs, ys = (XU, YU) if which == "up" else (XL, YL)
    u, v = xs*c, ys*c
    i = np.radians(inc)
    X = xle + u*np.cos(i) + v*np.sin(i)
    Z = -u*np.sin(i) + v*np.cos(i)
    return X, Z

# ala delantera bajo el fuselaje: punto más alto del extradós a Z = -(R+1)
Xu_f, Zu_f = placed_surface(C_F, X_LE_F, INC_F, "up")
Z_LE_F = -(R + 1) - Zu_f.max()
# ala trasera sobre el fuselaje: punto más bajo del intradós a Z = R+1
Xl_r, Zl_r = placed_surface(C_R, X_LE_R, INC_R, "lo")
Z_LE_R = (R + 1) - Zl_r.min()


def ccw(p):
    p = np.array(p, float); a = 0.5*np.sum(p[:, 0]*np.roll(p[:, 1], -1) - np.roll(p[:, 0], -1)*p[:, 1])
    return (p if a > 0 else p[::-1]).tolist()

def seat(front):
    """Asiento del ala. En impresión el eje X es vertical con +X hacia la cama: la cara del extremo +X
    se hace a 45° (sin voladizos) y en F4 se recorta en la cola para apoyar en la cama."""
    if front:
        X, Z = Xu_f, Zu_f + Z_LE_F + 0.2
        env = [(X[0]-15, Z[0])] + list(zip(X, Z)) + [(X[-1]+60, Z[-1]), (X[-1]+60, 5), (X[0]-15, 5)]
        xa, xb = X.min()-10, X.max()+10
        trap = [(xa, 1), (xa, -R), (xa+40, -R-40), (xb-40, -R-40), (xb-40 + R+41, 1)]
    else:
        X, Z = Xl_r, Zl_r + Z_LE_R - 0.2
        env = [(X[0]-15, Z[0])] + list(zip(X, Z)) + [(X[-1]+60, Z[-1]), (X[-1]+60, -5), (X[0]-15, -5)]
        xa, xb = X.min()-10, X.max()+10
        trap = [(xa, -1), (xb + R + 1, -1), (xb - 40, R + 40), (xa + 40, R + 40), (xa, R)]
    cs = CrossSection([ccw(env)]) ^ CrossSection([ccw(trap)])
    return Manifold.extrude(cs, 2*SEAT_HALF).translate([0, 0, -SEAT_HALF]).rotate([90, 0, 0])

def seat_pins(front):
    c, xle, zle, inc = (C_F, X_LE_F, Z_LE_F, INC_F) if front else (C_R, X_LE_R, Z_LE_R, INC_R)
    xs, ys = (XU, YU) if front else (XL, YL)
    u, v = PIN_U*c, float(np.interp(PIN_U, xs, ys))*c
    i = np.radians(inc)
    X = xle + u*np.cos(i) + v*np.sin(i); Z = zle - u*np.sin(i) + v*np.cos(i)
    z0 = Z - 0.5 if front else Z - 3.5
    h = Manifold.cylinder(4.0, PIN_D_SEAT/2)
    return h.translate([X, PIN_Y, z0]) + h.translate([X, -PIN_Y, z0])

def inner_plate(x0, x1, z0, z1, slots=()):
    p = Manifold.cube([x1-x0, 2*R, z1-z0]).translate([x0, -R, z0]) ^ cyl_x(x0-1, x1+1, RIN + 0.3)
    for (x, y, lx, ly) in slots:
        p = p - Manifold.cube([lx, ly, 10]).translate([x - lx/2, y - ly/2, z0 - 5])
    return p

ANT_X = 175.0                     # salida de la antena del receptor (techo de F2)
FLOOR_Z = -12.0                   # suelos a Z -12: la batería (24 mm de alto) queda bajo las vainas de los larguerillos de arriba (Z +12,8)
# suelos: (tramo, X0, X1 del centro de la V trasera, X de las ranuras de velcro, medio ancho entre ranuras)
#   F2: batería 3S 1300 (72 x 35 x 24), centrada donde diga masas_t1.py (X ~190); el extremo en V llega a 243 por
#       los lados, justo antes del chaflán de la brida (244). F3: ESC 30 A delante de los servos. F4: receptor
FLOORS = {1: (108.0, 222.0, (130.0, 160.0, 190.0, 215.0), 18.0), 2: (262.0, 290.0, (270.0, 284.0), 14.0), 3: (365.0, 395.0, (372.0, 388.0), 13.0)}
FLOOR_X0, FLOOR_X1 = FLOORS[1][0], FLOORS[1][1]   # (compatibilidad: suelo de F2)

def elec_floor(x0, x1, xs_velcro, y_velcro, aligerar=()):
    """Suelo de 1,2 mm a Z = FLOOR_Z dentro del tubo, de x0 a x1 (centro), con ranuras para cinta de velcro de
    20 mm a +-y_velcro y el extremo trasero en V a 45° (al imprimir con la cola abajo no hay voladizo)."""
    z0, z1 = FLOOR_Z - 1.2, FLOOR_Z
    w = float(np.sqrt(RIN**2 - z0**2)) + 0.3
    pts = [(x0, -w), (x1 + w, -w), (x1, 0.0), (x1 + w, w), (x0, w)]
    p = Manifold.extrude(CrossSection([ccw(pts)]), z1 - z0).translate([0, 0, z0]) ^ cyl_x(x0 - 1, x1 + w + 1, RIN + 0.3)
    for x in xs_velcro:
        for sy in (-1, 1):
            p = p - Manifold.cube([VELCRO_L, VELCRO_W, 10]).translate([x - VELCRO_L / 2, sy * y_velcro - VELCRO_W / 2, z0 - 5])
    for x in aligerar:      # ventanas de aligerado
        p = p - Manifold.cube([16, 22, 10]).translate([x, -11, z0 - 5])
    return p

def servo_guides():
    g = None
    for (x0, sgn) in SERVO_WIN:
        cs = CrossSection([[(x0, 7.0), (x0 + SERVO_L, 7.0), (x0 + SERVO_L + 18, 25.0), (x0, 25.0)]])
        for zc in (SERVO_Z + SERVO_W/2 + 0.6, SERVO_Z - SERVO_W/2 - 0.6):
            pl = Manifold.extrude(cs, 1.2).translate([0, 0, zc - 0.6])
            if sgn < 0: pl = pl.mirror([0, 1, 0])
            g = pl if g is None else g + pl
    return g ^ cyl_x(SEG[2][0], SEG[2][1] - FL_T, RIN + 0.3)

def flange(xface, toward):
    """Brida/cuaderna de unión: cara plana de 1,2 mm en xface y chaflán interior de 45° hacia `toward` (+1/-1).
    Agujero central Ø37 para cables. Es la base de impresión de cada tramo y la superficie de pegado."""
    d = RIN - FL_RIN
    pts = [(FL_RIN, xface), (RIN + 0.2, xface), (RIN + 0.2, xface + toward*(FL_T + d)), (FL_RIN, xface + toward*FL_T)]
    return revolve_profile(pts)

def ring(x0):
    """Anillo de refuerzo (cuaderna ligera) de sección triangular 45°/45°, 3 mm de fondo: imprimible sin soportes."""
    return revolve_profile([(RIN + 0.2, x0 - 3.2), (RIN - 3.0, x0), (RIN + 0.2, x0 + 3.2)])

def polar(ang, r):
    return r*np.cos(np.radians(ang)), r*np.sin(np.radians(ang))

def f1_keys():
    """Chavetas dentro de F1 (pared trasera). Perfil (r, X) con chaflán de 45° abajo (F1 se imprime con la placa motor en la cama)."""
    out = None
    for ang, w in KEY_F1:
        prof = CrossSection([ccw([(KEY_X0 - (KEY_R1 - KEY_R0), KEY_R1), (KEY_X1, KEY_R1), (KEY_X1, KEY_R0), (KEY_X0, KEY_R0)])])  # (X, r)
        k = Manifold.extrude(prof, w).translate([0, 0, -w/2])          # (X, r, t)
        k = k.transform([[1, 0, 0, 0], [0, 0, 1, 0], [0, 1, 0, 0]])     # -> (X, t, r): r sobre +Z
        k = k.rotate([ang - 90.0, 0, 0])                                # +Z -> dirección del ángulo
        out = k if out is None else out + k
    return out

def f2_key_notches():
    out = None
    for ang, w in KEY_F1:
        n = Manifold.cube([KEY_X1 + 0.6 - (G0 := SEG[1][0] - COLLAR - 1), w + 0.4, 2.0]).translate([G0, -(w + 0.4)/2, COLLAR_R0 - 0.4])
        n = n.rotate([ang - 90.0, 0, 0])
        out = n if out is None else out + n
    return out

def studs(xface, toward):
    """Tetones que sobresalen de la cara de una brida hacia `toward` (-1: hacia delante)."""
    out = None
    for ang in STUD_ANG:
        y, z = polar(ang, STUD_RC)
        body = cyl_x(0, STUD_H - 0.5 + 0.5, STUD_R)                     # 0..STUD_H (incluye 0,5 dentro de la brida)
        tip = along_x(Manifold.cylinder(0.5, STUD_R, STUD_R - 0.5)).translate([STUD_H, 0, 0])
        st = (body + tip).translate([-0.5, 0, 0])                        # -0,5..STUD_H+0,5 a lo largo de +x local
        if toward < 0: st = st.mirror([1, 0, 0])
        st = st.translate([xface, y, z])
        out = st if out is None else out + st
    return out

def sockets(xface, toward):
    """Alojamientos ciegos en la cara de una brida, que se hunden hacia `toward`."""
    out = None
    for ang in STUD_ANG:
        y, z = polar(ang, STUD_RC)
        h = cyl_x(-0.1, SOCK_H, SOCK_R)
        if toward < 0: h = h.mirror([1, 0, 0])
        h = h.translate([xface, y, z])
        out = h if out is None else out + h
    return out

def stringer_pos():
    return [(STR_RC*np.cos(np.radians(t)), STR_RC*np.sin(np.radians(t))) for t in STR_ANG]

def stringer_sleeves(x0, x1):
    s = None
    for (y, z) in stringer_pos():
        c = cyl_x(x0, x1, STR_R).translate([0, y, z])
        s = c if s is None else s + c
    return s

def stringer_holes():
    s = None
    for (y, z) in stringer_pos():
        c = cyl_x(STR_X0 - 20, STR_X1 + 1, STR_HOLE/2).translate([0, y, z])
        s = c if s is None else s + c
    return s

# ---------------- Fuselaje ----------------
def fuselage_segment(k):
    a, b = SEG[k]
    xs = np.linspace(a, b, 80)
    outer = [(r_out(x), x) for x in xs]
    inner = [(max(r_out(x) - WALL, 0.5), x) for x in xs]
    body = revolve_profile(inner + outer[::-1])
    if k == 0:   # morro: placa motor (base de impresión), suelo de batería, estante del ESC
        body = body + revolve_profile([(0.01, 0), (r_out(0), 0), (r_out(2.5), 2.5), (0.01, 2.5)])
        body = body - hole_x(-1, 0, 0, 9.0, 5)                       # paso del eje del X2212
        for (y, z) in MOTOR_X2212:                                    # cruz 16 x 19, tornillos M3 con tuerca por dentro
            body = body - hole_x(-1, y, z, 3.3, 5)
        t = np.radians(22.5); body = body - hole_x(-1, 12*np.cos(t), 12*np.sin(t), 5.0, 5)
        for q in range(3):
            t = np.radians(200 + 50*q); body = body - hole_x(-1, 12*np.cos(t), 12*np.sin(t), 3.5, 5)
        nose_in = revolve_profile([(0.01, 0)] + [(r_out(x) - WALL + 0.3, x) for x in np.linspace(0, 100, 60)] + [(0.01, 100)])
        plates = inner_plate(2.5, 84, -18.5, -17, slots=[(45, 14, 12, 2.6), (45, -14, 12, 2.6), (72, 14, 12, 2.6), (72, -14, 12, 2.6)]) \
               + inner_plate(2.5, 60, 8, 9.5, slots=[(40, 12, 12, 2.6), (40, -12, 12, 2.6)])
        body = body + (plates ^ nose_in) + f1_keys()
        return body
    if k == 1:   # cuello macho hacia el morro (unión desmontable con F1)
        body = body + revolve_profile([(COLLAR_R0, a), (R - 0.1, a), (R - 0.1, a + 2.9), (RIN, a + 2.9), (COLLAR_R0, a + 2)])
        body = body + annulus(a-COLLAR, a+2, COLLAR_R0, COLLAR_R1)
        interior = revolve_profile([(0.0, a - COLLAR - 1), (COLLAR_R0, a - COLLAR - 1), (COLLAR_R0, a + 2), (RIN, a + 2.9), (RIN, b + 1), (0.0, b + 1)])
        body = (body + seat(True)) - interior - f2_key_notches()
    if k == 3:
        body = body + revolve_profile([(0.01, L-2.5), (r_out(L-2.5), L-2.5), (r_out(L), L), (0.01, L)])
        tail_in = revolve_profile([(0.0, a - 1)] + [(r_out(x) - WALL, x) for x in np.linspace(a - 1, L - 2.5, 50)] + [(0.0, L - 2.5)])
        body = (body + seat(False)) - tail_in
        body = body ^ Manifold.cube([L - a + 20, 300, 300]).translate([L - (L - a + 20), -150, -150])   # nada por detrás de la cola
        body = body ^ Manifold.cube([L - a + 5, 200, 200]).translate([a - 5, -100, -100])   # nada por detrás de la cola
    # --- estructura interna tipo cohete (F2..F4) ---
    if k in (2, 3):
        body = body + flange(a, +1)                  # brida delantera (arriba al imprimir, chaflán 45°)
    if k in (1, 2):
        body = body + flange(b, -1)                  # brida trasera = base plana de impresión
    if k in (2, 3):
        body = body + studs(a, -1)                   # tetones en la brida delantera (salen hacia delante, arriba al imprimir)
    for x0 in RINGS.get(k, ()):
        body = body + ring(x0)
    body = body + stringer_sleeves(max(a, STR_X0), min(b, STR_X1))
    if a <= STR_X1 <= b:   # remate cónico (45°) de las vainas: sin voladizo al imprimir con la cola abajo
        for (y, z) in stringer_pos():
            body = body + along_x(Manifold.cylinder(STR_R, STR_R, 0.01)).translate([STR_X1, y, z])
    if k in FLOORS:
        x0, x1, xs, yv = FLOORS[k]
        body = body + elec_floor(x0, x1, xs, yv, aligerar=(138,) if k == 1 else ())
    if k == 1:
        body = body - Manifold.cylinder(20, 1.6).translate([ANT_X, 0, 15])
    if k == 2:
        body = body + servo_guides()
        for (x0, sgn) in SERVO_WIN:
            body = body - Manifold.cube([SERVO_L, 12, SERVO_W], center=True).translate([x0 + SERVO_L/2, sgn*R, SERVO_Z])
    if k == 1:
        body = body - seat_pins(True)
        for Xd in (X_LE_F-4, X_LE_F+C_F+6):
            body = body - hole_y(Xd, 11, DOWEL_D)
    if k == 3:
        body = body - seat_pins(False) - hole_x(L-5, 0, 0, 6.0, 10)
        for Xd in (X_LE_R-6, X_LE_R+C_R+6):
            body = body - hole_y(Xd, 20, DOWEL_D)
    if k in (1, 2):
        body = body - sockets(b, -1)                 # alojamientos ciegos en la brida trasera (cara en la cama)
    body = body - stringer_holes()
    return body

# ---------------- Alas: piel + celosía diagonal + tapas ----------------
def lattice(c, h, us):
    """Nervios diagonales ±45° (plano que contiene el espesor): imprimibles de pie sin soportes."""
    out = None
    L2 = (h + c) * 1.6
    for sgn in (+1, -1):
        for k in range(-int(h // RIB_P) - 2, int(c // RIB_P) + 3):
            u0 = k*RIB_P + RIB_P/2 - us
            slab = Manifold.cube([RIB_T, 40, L2], center=True).rotate([0, sgn*45, 0]).translate([u0, 0, 0])
            out = slab if out is None else out + slab
    return out

def sleeve_2d(cs_hole_centers, r):
    s = None
    for (x, y) in cs_hole_centers:
        c = CrossSection.circle(r).translate([x, y]); s = c if s is None else s + c
    return s

def wing_segment(c, sections, h, twist0=0.0, twist=0.0, slot=False, pin=None):
    """sections: lista de (z0, z1, cs_outer) que componen el tramo (permite el corte del elevón).
    Devuelve el tramo hueco con piel SKIN, celosía, vainas de largueros, tapas en ambos extremos."""
    full_cs, (us, vs) = wing_cs(c, slot=slot)
    x2, y2 = SPAR2_X*c - us, camber_at(SPAR2_X)*c - vs
    nd = 4 if twist else 0
    def ext(cs, z0, z1):
        hh = z1 - z0
        tw0 = twist0 + twist*z0/h
        return Manifold.extrude(cs.rotate(tw0), hh, n_divisions=nd, twist_degrees=twist*hh/h).translate([0, 0, z0])
    outer, void = None, None
    for (z0, z1, cs) in sections:
        o = ext(cs, z0, z1)
        inner_cs = cs.offset(-SKIN)
        v = ext(inner_cs, z0, z1)
        outer = o if outer is None else outer + o
        void = v if void is None else void + v
    void = void ^ Manifold.cube([400, 400, h - 2*CAP]).translate([-200, -200, CAP])
    # vainas de largueros
    sl_r1 = SPAR_D/2 + 0.6
    sleeves = Manifold.extrude(CrossSection.circle(sl_r1), h)
    if slot:
        hgt = SPAR2_SLOT
        st = (CrossSection.circle(SPAR2_D/2 + 0.6).translate([x2, y2 - hgt/2]) + CrossSection.circle(SPAR2_D/2 + 0.6).translate([x2, y2 + hgt/2])
              + CrossSection.square([SPAR2_D + 1.2, hgt]).translate([x2 - SPAR2_D/2 - 0.6, y2 - hgt/2]))
        sleeves = sleeves + Manifold.extrude(st, h)
    else:
        sleeves = sleeves + Manifold.extrude(CrossSection.circle(SPAR2_D/2 + 0.6).translate([x2, y2]), h)
    structure = (lattice(c, h, us).translate([0, 0, h/2]) + sleeves)
    if pin is not None:
        structure = structure + Manifold.cylinder(30, 2.0, center=True).rotate([-90, 0, 0]).translate([PIN_U*c - us, 0, PIN_Y])
    body = (outer - void) + (structure ^ void)
    # agujeros de largueros (pasantes, también por las tapas)
    holes = Manifold.extrude(CrossSection.circle(SPAR_D/2), h + 2).translate([0, 0, -1])
    r2 = SPAR2_D/2
    if slot:
        hgt = SPAR2_SLOT
        h2 = (CrossSection.circle(r2).translate([x2, y2 - hgt/2]) + CrossSection.circle(r2).translate([x2, y2 + hgt/2])
              + CrossSection.square([2*r2, hgt]).translate([x2 - r2, y2 - hgt/2]))
    else:
        h2 = CrossSection.circle(r2).translate([x2, y2])
    holes = holes + Manifold.extrude(h2, h + 2).translate([0, 0, -1])
    body = body - holes
    if pin is not None:
        body = body - pin
    return body, (us, vs)

def front_wing_segments():
    cs, (us, vs) = wing_cs(C_F, slot=True)
    w = WASHOUT/3
    segs = []
    for k in range(3):
        pin = pin_hole_wing(C_F, us, vs, True) if k == 0 else None
        seg, _ = wing_segment(C_F, [(0, WSEG, cs)], WSEG, twist0=k*w, twist=w, slot=True, pin=pin)
        segs.append(seg)
    return segs, (us, vs)

ELEV_Y0, ELEV_Y1 = 26.0, 297.0            # envergadura que ocupan los elevones (dos por lado)
E_LEN = (ELEV_Y1 - ELEV_Y0) / 2


def hinge_axis(c=C_R):
    """(x, y) local del eje de la bisagra: en la línea de bisagra (HINGE) sobre la línea media del perfil, y x de
    la pared de cierre del ala (NUDILLO_R + 0,6 por delante del eje: el canto redondo del elevón gira libre)."""
    us, vs = 0.25*c, camber_at(0.25)*c
    xe, ye = HINGE*c - us, camber_at(HINGE)*c - vs
    return xe, ye, xe - NUDILLO_R - 0.6


def nudillos_global():
    """Envergaduras (globales, desde el plano de simetría) donde empiezan los nudillos del ala: 4 por elevón,
    simétricos respecto al centro de cada uno."""
    out = []
    for j in range(2):
        cen = ELEV_Y0 + (j + 0.5) * E_LEN
        for d in NUDILLO_OFF:
            out += [cen - d - NUDILLO_L / 2, cen + d - NUDILLO_L / 2]
    return sorted(out)


def rear_wing_segments():
    """Tramos del ala trasera con la pared de cierre delante de la bisagra, los nudillos (cilindro alrededor del
    eje con puente hasta la pared) y el agujero del pasador; y el elevón: perfil por detrás del eje más el canto
    redondo alrededor del pasador, con huecos para los nudillos del ala."""
    c = C_R
    cs, (us, vs) = wing_cs(c)
    xe, ye, xw = hinge_axis(c)
    big = 500
    main_cs = cs ^ CrossSection.square([big, big]).translate([xw - big, -big/2])
    elev_cs = (cs ^ CrossSection.square([big, big]).translate([xe, -big/2])) + CrossSection.circle(NUDILLO_R).translate([xe, ye])
    y1l = ELEV_Y1 - 2 * WSEG
    plans = [[(0, ELEV_Y0, cs), (ELEV_Y0, WSEG, main_cs)], [(0, WSEG, main_cs)], [(0, y1l, main_cs), (y1l, WSEG, cs)]]
    segs = []
    perfil = Manifold.extrude(cs, 400).translate([0, 0, -1])
    for k, pl in enumerate(plans):
        pin = pin_hole_wing(c, us, vs, False) if k == 0 else None
        seg, _ = wing_segment(c, pl, WSEG, pin=pin)
        for s0 in nudillos_global():                       # nudillos de este tramo
            z = s0 - k * WSEG
            if z < 0 or z + NUDILLO_L > WSEG: continue
            puente = Manifold.cube([xe - xw + 1.0, 2 * NUDILLO_R, NUDILLO_L]).translate([xw - 1.0, ye - NUDILLO_R, z]) ^ perfil
            seg = seg + Manifold.cylinder(NUDILLO_L, NUDILLO_R).translate([xe, ye, z]) + puente
        za, zb = max(0.0, ELEV_Y0 - k * WSEG) - 1, min(WSEG, ELEV_Y1 - k * WSEG) + 1   # agujero del pasador solo donde hay elevón
        if zb > za:
            seg = seg - Manifold.cylinder(zb - za, PIN_HINGE_D / 2).translate([xe, ye, za])
        segs.append(seg)
    elev = Manifold.extrude(elev_cs, E_LEN)
    for d in NUDILLO_OFF:                                   # huecos para los nudillos del ala (simétricos)
        for sk in (E_LEN / 2 - d - NUDILLO_L / 2, E_LEN / 2 + d - NUDILLO_L / 2):
            hueco = (Manifold.cylinder(NUDILLO_L + 2 * NUDILLO_HOLGURA, NUDILLO_R + 0.4).translate([xe, ye, sk - NUDILLO_HOLGURA])
                     + Manifold.cube([4.0, 2 * NUDILLO_R + 0.8, NUDILLO_L + 2 * NUDILLO_HOLGURA]).translate([xe - 4.0, ye - NUDILLO_R - 0.4, sk - NUDILLO_HOLGURA]))
            elev = elev - hueco
    elev = elev - Manifold.cylinder(E_LEN + 2, PIN_HINGE_D / 2).translate([xe, ye, -1])
    return segs, elev, E_LEN, (us, vs), xe

def fin():
    c, t = 80.0, 2.0
    n = 16
    pts = [(0, -0.4), (0, 0.4), (-0.3*c, t/2)] + [(-c + t/2 - t/2*np.cos(a), t/2*np.sin(a))
            for a in np.linspace(np.pi/2, -np.pi/2, n)][1:-1] + [(-0.3*c, -t/2)]
    cs = CrossSection([pts])
    if cs.area() < 0: cs = CrossSection([pts[::-1]])
    return Manifold.extrude(cs, 75, scale_top=(50/80, 1.0))

def flat(man):
    """Pieza de envergadura en Z -> tumbada: envergadura en X, cuerda en Y, espesor en Z."""
    return man.transform([[0, 0, 1, 0], [1, 0, 0, 0], [0, 1, 0, 0]])

def wing_to_global(seg, us, vs, xle, zle, inc, span_off=0.0, left=False):
    g = seg.translate([us, vs, span_off]).rotate([90, 0, 0])
    g = g.rotate([0, inc, 0]).translate([xle, 0, zle])
    return g if left else g.mirror([0, 1, 0])

def build():
    parts, glob = {}, {}
    names = ["F1_morro_motor", "F2_central_ala_del", "F3_central", "F4_cola_ala_tras"]
    for k, nm in enumerate(names):
        g = fuselage_segment(k)
        glob[nm] = g
        parts[nm] = g.rotate([0, -90, 0]) if k == 0 else g.rotate([0, 90, 0])
    fsegs, (usf, vsf) = front_wing_segments()
    rsegs, elev, e_len, (usr, vsr), xh = rear_wing_segments()
    for k in range(3):
        parts[f"AD{k+1}_der"] = fsegs[k]
        parts[f"AD{k+1}_izq"] = fsegs[k].mirror([0, 0, 1])
        parts[f"AT{k+1}_der"] = rsegs[k]
        parts[f"AT{k+1}_izq"] = rsegs[k].mirror([0, 0, 1])
    parts["ELEVON_x4"] = flat(elev)
    parts["WINGLET_x2"] = fin()
    for side in (False, True):
        s = "izq" if side else "der"
        for k in range(3):
            glob[f"AD{k+1}_{s}"] = wing_to_global(fsegs[k], usf, vsf, X_LE_F, Z_LE_F, INC_F, k*WSEG, side)
            glob[f"AT{k+1}_{s}"] = wing_to_global(rsegs[k], usr, vsr, X_LE_R, Z_LE_R, INC_R, k*WSEG, side)
        for j in range(2):
            glob[f"EL{j+1}_{s}"] = wing_to_global(elev, usr, vsr, X_LE_R, Z_LE_R, INC_R, ELEV_Y0 + j*e_len, side)
    for nm in list(parts):
        parts[nm] = to_print(parts[nm])
    return parts, glob, dict(usf=usf, vsf=vsf, usr=usr, vsr=vsr, xh=xh, e_len=e_len)

if __name__ == "__main__":
    import pickle, shutil
    write_dat(os.path.join(OUT, "NACA3407.dat"))
    shutil.rmtree(os.path.join(OUT, "stl"), ignore_errors=True); os.makedirs(os.path.join(OUT, "stl"))
    parts, glob, ex = build()
    info = {}
    for nm, m in parts.items():
        write_stl(m, os.path.join(OUT, "stl", nm + ".stl"))
        bb = m.bounding_box()
        info[nm] = dict(size=[round(bb[3]-bb[0], 1), round(bb[4]-bb[1], 1), round(bb[5]-bb[2], 1)],
                        vol=m.volume()/1000, area=m.surface_area()/100, genus=m.genus(),
                        ok=str(m.status()), tris=m.num_tri())
    gi = {nm: dict(vol=m.volume()/1000, area=m.surface_area()/100, cg=centroid(m).tolist(),
                   bb=list(m.bounding_box())) for nm, m in glob.items()}
    names = ["F1_morro_motor", "F2_central_ala_del", "F3_central", "F4_cola_ala_tras"]
    fus = glob[names[1]] + glob[names[3]]
    inter = {k: (fus ^ glob[k]).volume() for k in glob if k.startswith(("AD", "AT", "EL"))}
    # interferencias entre tramos de fuselaje montados
    seg_inter = {f"{names[i]}|{names[j]}": (glob[names[i]] ^ glob[names[j]]).volume()
                 for i in range(4) for j in range(i+1, 4)}
    json.dump(dict(parts=info, glob=gi, inter=inter, seg_inter=seg_inter, Z_LE_F=Z_LE_F, Z_LE_R=Z_LE_R, **ex),
              open(os.path.join(OUT, "info.json"), "w"), indent=1)
    pickle.dump({k: (np.asarray(m.to_mesh().vert_properties)[:, :3], np.asarray(m.to_mesh().tri_verts)) for k, m in glob.items()},
                open(os.path.join(OUT, "glob_meshes.pkl"), "wb"))
    for nm, v in info.items(): print(f"{nm:20s} {v['size']} vol={v['vol']:.1f} genus={v['genus']} {v['ok']}")
    print("inter ala-fus", max(inter.values()), "| entre tramos", {k: round(v, 2) for k, v in seg_inter.items() if v > 0.01})
