"""Tandem T1: masa, centro de gravedad, posicion de la bateria e inercias del avion montado, TODO en PLA normal
y con el motor y la bateria del E1 (X2212 KV980, APC 9x4,7, ESC 30 A, 3S 1300 mAh).

Piezas impresas desde las mallas montadas de stl/T1/scripts/geom.py (out/glob_meshes.pkl); componentes como
masas puntuales (o lineales, los largueros). Escribe out/inercias.json en ejes cuerpo estandar (x adelante,
y derecha, z abajo, origen en el CG; kg y kg m2), que es lo que lee modelo_aero_t1.py.

    $env:ENTRENADOR = "T1"; python scripts/masas_t1.py
"""
import json, os, pickle, sys
import numpy as np

os.environ.setdefault("ENTRENADOR", "T1")
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from avion import ID, P   # noqa: E402
assert ID == "T1", "masas_t1.py es solo para el T1 (ENTRENADOR=T1)"
GT = P.GT
OUT = GT.OUT

RHO_PLA = 1.24     # PLA normal (g/cm3). El diseno original contaba con LW-PLA (0,65): aqui pesa casi el doble
PARED = GT.WALL / 10   # cm: pared del tubo (3 perimetros de 0,4). Las zonas macizas del fuselaje (asientos de las alas,
RELLENO = 0.15     # bridas, suelos) se imprimen con esa pared y un 15 % de relleno
F_PLACA = 0.45     # elevones (placa de 3,5 mm, 2 perimetros, 3 capas arriba y abajo, 10 % de relleno): ~45 % de material


def masa_pieza(nm, g):
    """Masa (g) de una pieza montada a partir de su volumen (cm3) y su area (cm2)."""
    vol, area = g["vol"], g["area"]
    if nm.startswith(("AD", "AT")):            # alas: piel + celosia + vainas; el volumen de la malla es material real
        return vol * RHO_PLA
    if nm.startswith("EL"):                    # elevones impresos en PLA (el diseno original los recomendaba en balsa)
        return vol * F_PLACA * RHO_PLA
    shell = min(vol, area * PARED)             # fuselaje: pared real + relleno de las zonas macizas
    return (shell + RELLENO * max(0.0, vol - shell)) * RHO_PLA


# componentes: (nombre, g, X, Y, Z) en mm. Con el motor del E1 (57 g en vez de 9) el morro ya pesa de sobra: la
# bateria 3S 1300 (72 x 35 x 24) va sobre el suelo de F2 (X 114-200, el que era del receptor) y para que el CG caiga
# en X_CG el ESC pasa a F3, delante de los servos, y el receptor a la cola (F4). En F1 solo queda el motor.
X_SERVO = GT.SERVO_WIN[0][0] + GT.SERVO_L / 2
COMP = [("Motor SunnySky X2212 KV980", 57.0, -16.0, 0, 0), ("Helice APC 9x4.7 + adaptador", 12.0, -42.0, 0, 0),
        ("ESC 30 A (suelo de F3)", 26.0, 280.0, 0, -6.0), ("Receptor FlySky A6 (suelo de F4)", 7.0, 383.0, 0, -4.0),
        ("Servo 3,7 g elevon izq", 4.0, X_SERVO, -20.0, GT.SERVO_Z), ("Servo 3,7 g elevon der", 4.0, X_SERVO, 20.0, GT.SERVO_Z),
        ("Varillas 0,8 mm + horns", 2.5, 400.0, 0, 20.0),
        ("Pines de centrado C 2 mm (4)", 0.2, 250.0, 0, 0), ("Palillos C macizo 4 mm (4 x 60) + gomas", 7.0, 280.0, 0, 0),
        ("Pasadores de los elevones C 2 mm (2 x 271)", 2.7, 436.0, 0, 29.0), ("Tornillos M3 y tuercas del motor", 4.0, 2.0, 0, 0),
        ("Cables, XT60, cinta", 15.0, 150.0, 0, -10.0)]
# larguerillos del fuselaje: 4 varillas de carbono de 2 mm (4,9 g/m) de F2 a F4, a 45 grados en el tubo
for ang in GT.STR_ANG:
    y, z = GT.polar(ang, GT.STR_RC)
    COMP.append(("Larguerillo C 2 mm %d" % ang, 4.9 * (GT.STR_X1 - GT.STR_X0) / 1000, 0.5 * (GT.STR_X0 + GT.STR_X1), y, z))
BATERIA = ("Bateria 3S 1300 mAh", 115.0)
Z_BAT = GT.FLOOR_Z + 12.0                     # sobre el suelo de F2 (Z -10), 24 mm de alto
PIEZAS_WINGLET = [("Winglet izq", -1), ("Winglet der", +1)]


def z_ala(xle, zle, c, inc, u):
    """Z de la linea media de un ala en la fraccion de cuerda u (sin torsion)."""
    i = np.radians(inc)
    return zle - u * c * np.sin(i) + GT.camber_at(u) * c * np.cos(i)


def largueros():
    """Tubo 4x3 de carbono (8,5 g/m) al 25 % y varilla de 2 mm (4,9 g/m) al 50 % de la cuerda, de punta a punta,
    en las dos alas."""
    pts = []
    for xle, zle, c, inc in ((P.X_LE_F, P.Z_LE_F, P.C_F, P.INC_F), (P.X_LE_R, P.Z_LE_R, P.C_R, P.INC_R)):
        for u, gm in ((0.25, 8.5), (0.50, 4.9)):
            ys = np.linspace(-P.B / 2 + 1.5, P.B / 2 - 1.5, 120)
            for y in ys:
                pts.append(("largueros", gm * (P.B - 3) / 1000 / len(ys), xle + u * c * np.cos(np.radians(inc)), y, z_ala(xle, zle, c, inc, u)))
    return pts


def inercia_malla(v, t, masa_g):
    a, b, c = v[t[:, 0]], v[t[:, 1]], v[t[:, 2]]
    det = np.einsum("ij,ij->i", a, np.cross(b, c))
    vol = det.sum() / 6
    S = lambda f: (det * f).sum()
    mom2 = lambda i, j: S((a[:, i] * a[:, j] + b[:, i] * b[:, j] + c[:, i] * c[:, j]
                           + (a[:, i] + b[:, i] + c[:, i]) * (a[:, j] + b[:, j] + c[:, j])) / 120.0)
    cg = np.array([S((a[:, k] + b[:, k] + c[:, k]) / 24.0) for k in range(3)]) / vol
    I2 = np.array([[mom2(i, j) for j in range(3)] for i in range(3)])
    return cg, (np.trace(I2) * np.eye(3) - I2) * masa_g / vol


def calcular(x_bat=None, verbose=True):
    D = json.load(open(os.path.join(OUT, "info.json")))
    M = pickle.load(open(os.path.join(OUT, "glob_meshes.pkl"), "rb"))
    filas, Itot = [], np.zeros((3, 3))
    for nm, (v, t) in M.items():
        m = masa_pieza(nm, D["glob"][nm])
        cg, Io = inercia_malla(v, t, m)
        filas.append((nm, m, *cg)); Itot += Io
    # winglets: no estan en el montaje global de geom.py; placa de 2 mm maciza en la punta del ala trasera
    W = P.WINGLET
    m_w = D["parts"]["WINGLET_x2"]["vol"] * RHO_PLA
    cg_w = (W["x_te"] - 0.45 * (W["c_raiz"] + W["c_punta"]) / 2, W["z0"] + W["h"] * 0.45)
    puntos = [(nm, m_w, cg_w[0], s * W["y"], cg_w[1]) for nm, s in PIEZAS_WINGLET] + COMP + largueros()
    for _, m, x, y, z in puntos:
        if m == m_w:    # inercia propia de la placa del winglet (aprox. rectangulo c x h)
            c, h = 0.5 * (W["c_raiz"] + W["c_punta"]), W["h"]
            Itot += m / 12 * np.diag([h * h, c * c + h * h, c * c])
    m0 = sum(f[1] for f in filas) + sum(p[1] for p in puntos)
    mx0 = sum(f[1] * f[2] for f in filas) + sum(p[1] * p[2] for p in puntos)
    if x_bat is None:   # bateria donde haga falta para el CG objetivo
        x_bat = (P.X_CG * (m0 + BATERIA[1]) - mx0) / BATERIA[1]
    puntos = puntos + [(BATERIA[0], BATERIA[1], x_bat, 0.0, Z_BAT)]
    for _, m, x, y, z in puntos:
        r = np.array([x, y, z]); Itot += m * (r @ r * np.eye(3) - np.outer(r, r))
    todo = filas + puntos
    mt = sum(f[1] for f in todo)
    cg = np.array([sum(f[1] * f[k] for f in todo) for k in (2, 3, 4)]) / mt
    Icg = Itot - mt * (cg @ cg * np.eye(3) - np.outer(cg, cg))
    Rt = np.diag([-1.0, 1.0, -1.0])
    Ib = Rt @ Icg @ Rt.T * 1e-9
    S = P.B * (P.C_F + P.C_R) / 1e4
    res = dict(masa_kg=mt / 1e3, cg_mm=cg.round(1).tolist(), x_bateria_mm=round(float(x_bat), 1),
               Ixx=Ib[0, 0], Iyy=Ib[1, 1], Izz=Ib[2, 2], Ixz=-Ib[0, 2],
               masa_sin_bateria_g=round(m0, 1), cg_sin_bateria_mm=round(mx0 / m0, 1),
               impreso_g=round(sum(f[1] for f in filas) + 2 * m_w, 1))
    if verbose:
        grupos = {}
        for nm, m, *_ in todo:
            k = ("Ala delantera impresa (6 tramos)" if nm.startswith("AD") else "Ala trasera impresa (6 tramos)" if nm.startswith("AT") else
                 "Elevones impresos (4)" if nm.startswith("EL") else "Fuselaje F1-F4 impreso" if nm[0] == "F" and nm[1].isdigit() else
                 "Winglets impresos (2)" if nm.startswith("Winglet") else nm)
            grupos[k] = grupos.get(k, 0) + m
        for k, m in grupos.items(): print("  %-48s %6.1f g" % (k, m))
        print("%s: TOTAL %.0f g (impreso %.0f g, sin bateria %.0f g con el CG en X %.0f) | carga alar %.1f g/dm2 | CG X %.1f mm Z %.1f | bateria centrada en X %.0f mm"
              % (ID, mt, res["impreso_g"], m0, mx0 / m0, mt / S, cg[0], cg[2], x_bat))
        print("Ixx %.4f  Iyy %.4f  Izz %.4f  Ixz %.4f kg m2" % (res["Ixx"], res["Iyy"], res["Izz"], res["Ixz"]))
    return res


if __name__ == "__main__":
    r = calcular()
    json.dump(r, open(os.path.join(OUT, "inercias.json"), "w"), indent=1)
