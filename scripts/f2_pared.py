"""Variante de la pieza F2 del fuselaje con otra pared (por defecto 2 mm), que monta con F1 y F3 de la pared normal.

    set ENTRENADOR=E3   (o $env:ENTRENADOR = "E3")
    python scripts/f2_pared.py 2          ->  stl/E3/F2_pared2mm.stl

F2 se genera dos veces con geom_e1.py: con la pared del avion (PARED_FUS, 5 mm en el E2/E3) y con la pared pedida.
La pieza nueva es la fina salvo en las dos uniones, que se copian de la normal para que encajen sin tocar F1 ni F3:
  - delante, los 16 mm donde entra el cuello de F1 (por dentro necesita la pared normal, con su holgura de 0,15);
  - detras, el anillo de anclaje y el cuello que entra en F3 (desde 6 mm antes del final de F2).
Entre la pared fina y la gruesa hay una transicion a 45 grados (se imprime de pie sobre la cara delantera: sin
voladizos). La bandeja de los servos y las transmisiones quedan a la MISMA altura que en la F2 normal (las guias de
F3 a F5 no cambian): las placas de la bandeja bajan hasta el suelo, mas bajo con la pared fina. Sin larguerillos de
carbono (F1 y F3-F5 no los llevan); si lleva la cuaderna en U de F2 (detras de los servos), que con pared fina rigidiza.
"""
import importlib.util, os, sys
from avion import ID, P
from manifold3d import Manifold, CrossSection

PARED = float(sys.argv[1]) if len(sys.argv) > 1 else 2.0
AQUI = os.path.dirname(os.path.abspath(__file__))
PARED_NORMAL = getattr(P, "PARED_FUS", 1.6)


def cargar(nombre, pared):
    """geom_e1.py como modulo aparte con la pared dada (sus constantes se calculan al importarlo)."""
    P.PARED_FUS = pared
    spec = importlib.util.spec_from_file_location(nombre, os.path.join(AQUI, "geom_e1.py"))
    m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
    return m


G = cargar("geom_normal", PARED_NORMAL)
g = cargar("geom_fina", PARED)
P.PARED_FUS = PARED_NORMAL
g.LARG_TRAMOS = []                      # sin larguerillos: el resto del fuselaje no los lleva
g.SUELO_Z = G.SUELO_Z                   # servos y transmisiones a la altura de siempre
suelo_fino = -P.FUS_H / 2 + PARED       # cara de arriba del suelo con la pared fina


def bandeja_servos():
    """La bandeja de geom_e1 con las placas alargadas hacia abajo hasta el suelo fino (los tornillos, igual)."""
    S = g.SERVO
    y_in = S["largo"] / 2 + 0.4
    z0, z1 = suelo_fino - 0.5, G.SUELO_Z + S["alto_orejeta"]
    x0, x1 = g.SERVO_X[0] - 18.0, g.SERVO_X[-1] + S["ancho"] + 2.0
    out = None
    for sy in (-1, 1):
        prof = CrossSection([g.ccw([(x0, z0), (x1, z0), (x1, z1), (x0 + (z1 - z0), z1)])])
        placa = Manifold.extrude(prof, 3.0).rotate([90, 0, 0]).translate([0, (y_in + 3.0) if sy > 0 else -y_in, 0])
        out = placa if out is None else out + placa
    for xs in g.SERVO_X:
        for sy in (-1, 1):
            out = out - Manifold.cylinder(9.0, 0.8).translate([xs + S["ancho"] / 2, sy * S["tornillos"] / 2, z1 - 8.0])
    return out


g.bandeja_servos = bandeja_servos

K = 1                                    # F2
a, b = G.FUS_SEG[K]
normal = G.fuselage_segment(K)
fina = g.fuselage_segment(K)
L_DEL = G.SPIGOT_L + 1.0                 # zona de pared normal delante (cuello de F1: 15 mm)
L_TRA = 6.0                              # zona de pared normal detras (anillo de anclaje: 3,5 mm)
T = PARED_NORMAL - PARED                 # escalon de la pared (la transicion a 45 grados mide lo mismo en X)


def caja(x0, x1):
    return Manifold.cube([x1 - x0, 400, 400]).translate([x0, -200, -200])


def transicion(x_fino, x_grueso):
    """Anillo pegado a la pared por dentro: pared fina en x_fino, normal en x_grueso (45 grados). Bajo el ala no cierra
    el techo abierto de la escotilla."""
    xa, xb = min(x_fino, x_grueso), max(x_fino, x_grueso)
    ext = Manifold.batch_hull([G.slab(xa, PARED - 0.1), G.slab(xb, PARED - 0.1)])
    hueco = Manifold.batch_hull([G.slab(x_fino, PARED), G.slab(x_grueso, PARED_NORMAL)])
    return (ext - hueco) ^ _techo(xa, xb)


def _techo(xa, xb):
    """Todo salvo lo que queda por encima del arranque de las paredes del asiento del ala (techo abierto)."""
    if xb <= P.X_LE or xa >= P.X_LE + P.C:
        return caja(xa - 1, xb + 1)
    w, h, zc = P.fus_seccion(max(xa, P.X_LE))
    return caja(xa - 1, xb + 1) ^ Manifold.cube([xb - xa + 2, 400, 400]).translate([xa - 1, -200, zc + h - G.corner_r(w) - 1.0 - 400])


pieza = ((fina ^ caja(a + L_DEL + T, b - L_TRA - T))
         + (normal ^ caja(a - 1, a + L_DEL)) + (normal ^ caja(b - L_TRA, b + 30))
         + transicion(a + L_DEL + T, a + L_DEL) + transicion(b - L_TRA - T, b - L_TRA)
         + (fina ^ caja(a + L_DEL - 0.01, a + L_DEL + T + 0.01)) + (fina ^ caja(b - L_TRA - T - 0.01, b - L_TRA + 0.01)))

dest = os.path.join(AQUI, "..", "stl", ID, "F2_pared%gmm.stl" % PARED)
G.write_stl(pieza.rotate([0, -90, 0]), dest)          # de pie sobre la cara delantera, como la F2 normal
bb = pieza.bounding_box()
rho = 0.65                                              # LW-PLA espumado (masas_e1.py)
print("%s F2 pared %g mm: %s" % (ID, PARED, os.path.normpath(dest)))
print("  estado %s, genus %d, %.1f x %.1f x %.1f mm" % (pieza.status(), pieza.genus(), bb[3] - bb[0], bb[4] - bb[1], bb[5] - bb[2]))
print("  volumen %.1f cm3 (%.0f g en LW-PLA) frente a %.1f cm3 (%.0f g) con %g mm" % (
    pieza.volume() / 1000, pieza.volume() / 1000 * rho, normal.volume() / 1000, normal.volume() / 1000 * rho, PARED_NORMAL))
for nm, otra in [("F1", G.fuselage_segment(0)), ("F3", G.fuselage_segment(2))]:
    print("  interferencia con %s: %.2f mm3" % (nm, (pieza ^ otra).volume()))
