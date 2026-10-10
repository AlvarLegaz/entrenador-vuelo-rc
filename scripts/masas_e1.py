"""Entrenadores E1 y E2 (variable de entorno ENTRENADOR): masa, centro de gravedad, posicion de la bateria e
inercias del avion montado.

Piezas impresas desde las mallas montadas de geom_e1.py (out/glob_meshes.pkl); componentes como
masas puntuales (o lineales, los largueros). Escribe out/inercias.json en ejes cuerpo estandar
(x adelante, y derecha, z abajo, origen en el CG; kg y kg m2).
"""
import json, os, pickle
import numpy as np
from avion import ID, P
import geom_e1 as G

RHO_LW = 0.65      # LW-PLA espumado (g/cm3)
RHO_PLA = 1.24     # PLA normal (F1, por la bancada del motor: ademas el peso en el morro ayuda al CG)
F_PLACA = 0.35     # placas macizas (estabilizador, profundidad, timon, deriva) impresas con 2 perimetros,
                   # 3 capas arriba/abajo y 10 % de relleno: ~35 % del volumen es material


def masa_pieza(nm, vol_cm3, fin_vol):
    if nm in ("F1", "CUNA_MOTOR"):
        return vol_cm3 * RHO_PLA
    if nm == "F5":
        return (vol_cm3 - fin_vol) * RHO_LW + fin_vol * F_PLACA * RHO_LW
    if nm.startswith(("ESTAB", "PROF", "TIMON")):
        return vol_cm3 * F_PLACA * RHO_LW
    return vol_cm3 * RHO_LW          # ala y fuselaje: la malla ya es la pared real


# componentes: (nombre, g, X, Y, Z) en mm
Z_ALA_MEDIA = G.Z_LE
COMP = [("Motor SunnySky X2212 KV980", 57.0, -16.0, 0, 0), ("Helice APC 9x4.7 + adaptador", 12.0, -42.0, 0, 0),
        ("ESC 30 A", 26.0, 55.0, 0, -22.0), ("Receptor FlySky A6", 7.0, P.X_LE + 110.0, 0, -15.0),
        ("Servo 9 g profundidad", 9.0, G.SERVO_X[0] + 6.1, 0.0, G.SUELO_Z + 11.0),
        ("Varillas C 2 mm de la cola (union del estabilizador, pasadores de las bisagras)", 6.0, 750.0, 0, 0),
        ("Gomas del ala", 4.0, P.X_LE + 90.0, 0, 50.0),
        ("Palillos de las gomas: varilla C maciza 4 mm, 2 x 80 mm", 3.2, P.X_LE + 90.0, 0, 27.0),
        ("Cables, XT60, velcro", 15.0, 110.0, 0, -15.0)]
# llaves del quiebro: tubo de aluminio 6x4 mm, 100 mm (50 dentro de cada tubo de carbono), una por lado.
# Aguanta ~4,2 N m (6082-T6) frente a 0,8 N m en el quiebro a 4 g
for lado, left in (("izq", True), ("der", False)):
    X, Y, Z = G.punto_ala(0.0, 0.0, P.QUIEBRO, left)
    COMP.append(("Llave del quiebro (tubo aluminio 6x4 x 100) " + lado, 2.7 * np.pi / 4 * (0.36 - 0.16) * 10.0, X, Y, Z))
# larguerillos del fuselaje: varilla de carbono de 2 mm (4,9 g/m), tramos rectos en las 4 esquinas
for (sz, x0, x1) in G.LARG_TRAMOS:
    for sy in (-1, 1):
        pm = (G.larg_centro(x0, sy, sz) + G.larg_centro(x1, sy, sz)) / 2
        COMP.append(("Larguerillo C 2 mm X %.0f-%.0f" % (x0, x1), 4.9 * (x1 - x0) / 1000, *pm))
if G.ALERON:    # E2: los dos servos de los alerones van en el ala (cajeado de geom_e1.servo_caja) y solo hay una Bowden
    x0, x1, yt, _ = G.servo_caja()
    for lado, left in (("izq", True), ("der", False)):
        X, Y, Z = G.punto_ala((x0 + x1) / 2, yt - G.ALERON["servo_fondo"] / 2, G.ALERON["servo_y"], left)
        COMP.append(("Servo 9 g aleron " + lado, 9.0, X, Y, Z))
    COMP += [("Transmision Bowden (550 mm)", 6.0, 520.0, 0, -5.0), ("Cables de los servos del ala", 6.0, P.X_LE + 90.0, 0, 40.0),
             ("Varillas C 2 mm, horns y bisagras de los alerones", 6.0, P.X_LE + 90.0, 0, 50.0)]
else:
    COMP += [("Servo 9 g timon", 9.0, G.SERVO_X[1] + 6.1, 0.0, G.SUELO_Z + 11.0), ("Transmisiones Bowden (2 x 550 mm)", 12.0, 520.0, 0, -5.0)]
BATERIA = ("Bateria 3S 1300 mAh", 115.0)
Z_BAT = -20.0


def largueros():
    """Tubo 8x6 (34 g/m) al 25 % y varilla 3 mm (11 g/m) al 60 % de la cuerda, de punta a punta, siguiendo el
    poliedro (punto_ala): el tubo central es recto y los de las puntas van con el diedro."""
    _, (x2, y2) = G.wing_cs(P.C)
    pts = []
    for left in (True, False):
        for (u, v), gm in (((0.0, 0.0), 34.0), ((x2, y2), 11.0)):
            s = np.linspace(1.5, 598.5, 200)
            for si in s:
                X, Y, Z = G.punto_ala(u, v, si, left)
                pts.append(("largueros", gm * 0.6 / len(s), X, Y, Z))
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
    D = json.load(open(os.path.join(G.OUT, "info.json")))
    M = pickle.load(open(os.path.join(G.OUT, "glob_meshes.pkl"), "rb"))
    filas, Itot = [], np.zeros((3, 3))
    for nm, (v, t) in M.items():
        m = masa_pieza(nm, D["glob"][nm]["vol"], D["fin_vol"])
        cg, Io = inercia_malla(v, t, m)
        filas.append((nm, m, *cg)); Itot += Io
    puntos = COMP + largueros()
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
    res = dict(masa_kg=mt / 1e3, cg_mm=cg.round(1).tolist(), x_bateria_mm=round(float(x_bat), 1),
               Ixx=Ib[0, 0], Iyy=Ib[1, 1], Izz=Ib[2, 2], Ixz=-Ib[0, 2])
    if verbose:
        grupos = {}
        for nm, m, *_ in todo:
            k = ("Alerones impresos" if nm.startswith("ALERON") else "Ala impresa" if nm.startswith("ALA") else "Fuselaje F1 (PLA)" if nm == "F1" else
                 "Fuselaje F2-F5 (con la deriva)" if nm[0] == "F" and nm[1].isdigit() else
                 "Estabilizador, profundidad y timon" if nm.startswith(("ESTAB", "PROF", "TIMON")) else nm)
            grupos[k] = grupos.get(k, 0) + m
        for k, m in grupos.items(): print("  %-48s %6.1f g" % (k, m))
        S = P.B * P.C / 1e4
        print("%s: TOTAL %.0f g | carga alar %.1f g/dm2 | CG X %.1f mm (%.0f %% de la cuerda) | bateria centrada en X %.0f mm"
              % (ID, mt, mt / S, cg[0], (cg[0] - P.X_LE) / P.C * 100, x_bat))
        print("Ixx %.4f  Iyy %.4f  Izz %.4f  Ixz %.4f kg m2" % (res["Ixx"], res["Iyy"], res["Izz"], res["Ixz"]))
    return res


if __name__ == "__main__":
    r = calcular()
    json.dump(r, open(os.path.join(G.OUT, "inercias.json"), "w"), indent=1)
