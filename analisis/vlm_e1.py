"""Aerodinamica de los entrenadores por red de torbellinos (VLM): ala alta con diedro (con alerones en
el E2), estabilizador con profundidad y deriva con timon (fija en el E2). Que avion se analiza lo dice la
variable de entorno ENTRENADOR (scripts/avion.py).

Ejes de la geometria: los del proyecto (X hacia la cola, Y derecha, Z arriba, mm). Los
coeficientes salen en ejes cuerpo estandar (x adelante, y derecha, z abajo): Cm > 0 encabrita,
Cl > 0 alabea a la derecha, Cn > 0 guina a la derecha. Derivadas por radian.

Mandos: de > 0 = profundidad con el borde de fuga abajo (morro abajo); dr > 0 = timon con el borde
de fuga a la derecha (morro a la derecha); da > 0 = aleron derecho arriba e izquierdo abajo (alabeo a
la derecha).

Limitaciones: teoria potencial lineal (sin perdida ni viscosidad). El fuselaje se anade con
correcciones empiricas (Raymer/DATCOM), marcadas.
"""
import json, os, sys
import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "scripts"))
from avion import ID, P

RHO, G0 = 1.225, 9.81


def camber_slope(s, m, p):
    return np.where(s < p, 2 * m / p ** 2 * (p - s), 2 * m / (1 - p) ** 2 * (p - s))


def geo_por_defecto():
    return {k: getattr(P, k) for k in dir(P) if k.isupper()}


# ----------------------- paneles -----------------------
def superficie_h(nombre, xle, zle, c, semi, inc, diedro, perfil, hinge=None, ns=16, nc=6, hinge_y=None, mando="prof"):
    """Superficie horizontal de dos mitades desde y = 0 hasta y = semi, con diedro (giro sobre la
    linea del borde de ataque en y = 0). Devuelve paneles en mm (A, B, punto de control) e info.
    hinge: bisagra de la superficie movil (fraccion de la cuerda); hinge_y = (y0, y1) la limita a ese
    tramo de la semienvergadura (alerones); mando: "prof" (de, las dos mitades igual) o "aleron" (da,
    antisimetrico)."""
    m, p, _ = perfil
    yb = semi * np.sin(np.linspace(0, np.pi / 2, ns + 1))          # mas paneles en la punta
    if hinge_y is not None:                                         # que el aleron empiece y acabe en un borde de panel
        yb = np.unique(np.r_[yb, hinge_y])
    # diedro: un numero (V desde la raiz) o (y_quiebro, diedro dentro, diedro fuera) para un poliedro
    yq, d_in, d_out = diedro if isinstance(diedro, tuple) else (semi + 1.0, diedro, diedro)
    if yq < semi:
        yb = np.unique(np.r_[yb, yq])                               # que el quiebro caiga en un borde de panel
    t_in, t_out = np.tan(np.radians(d_in)), np.tan(np.radians(d_out))
    zy = lambda y: y * t_in if y <= yq else yq * t_in + (y - yq) * t_out
    sc = 0.5 * (1 - np.cos(np.linspace(0, np.pi, nc + 1)))         # mas paneles en BA y BF
    if hinge is not None:                                           # que la bisagra caiga en un borde de panel
        sc = np.unique(np.r_[0.5 * (1 - np.cos(np.linspace(0, np.pi, nc + 1))), hinge])
    A, Bv, Cp, info = [], [], [], []
    ns = len(yb) - 1
    for lado in (+1, -1):
        def punto(y, s):
            a = np.radians(inc)
            return np.array([xle + s * c * np.cos(a), lado * y, zle - s * c * np.sin(a) + zy(y)])
        for j in range(ns):
            y0, y1 = yb[j], yb[j + 1]
            for i in range(len(sc) - 1):
                s0, s1 = sc[i], sc[i + 1]
                sq, s3 = s0 + 0.25 * (s1 - s0), s0 + 0.75 * (s1 - s0)
                ya, yb_ = (y0, y1) if lado > 0 else (y1, y0)
                A.append(punto(ya, sq)); Bv.append(punto(yb_, sq)); Cp.append(punto(0.5 * (y0 + y1), s3))
                en_y = hinge_y is None or (y0 >= hinge_y[0] - 1e-9 and y1 <= hinge_y[1] + 1e-9)
                info.append(dict(sup=nombre, tipo="H", lado=lado, inc=inc, die=d_in if 0.5 * (y0 + y1) < yq else d_out,
                                 slope=float(camber_slope(s3, m, p)) if m > 0 else 0.0,
                                 mando=mando if (hinge is not None and s0 >= hinge - 1e-9 and en_y) else None))
    return A, Bv, Cp, info


def superficie_v(xle, z0, c, h, hinge, nz=8, nc=6):
    """Deriva vertical en y = 0, perfil simetrico, de z0 a z0 + h."""
    zb = z0 + h * np.linspace(0, 1, nz + 1)
    sc = np.unique(np.r_[0.5 * (1 - np.cos(np.linspace(0, np.pi, nc + 1))), hinge])
    A, Bv, Cp, info = [], [], [], []
    for j in range(nz):
        for i in range(len(sc) - 1):
            s0, s1 = sc[i], sc[i + 1]
            xq, x3 = xle + (s0 + 0.25 * (s1 - s0)) * c, xle + (s0 + 0.75 * (s1 - s0)) * c
            A.append(np.array([xq, 0.0, zb[j]])); Bv.append(np.array([xq, 0.0, zb[j + 1]]))
            Cp.append(np.array([x3, 0.0, 0.5 * (zb[j] + zb[j + 1])]))
            info.append(dict(sup="deriva", tipo="V", lado=0, inc=0.0, die=0.0, slope=0.0,
                             mando="timon" if s0 >= hinge - 1e-9 else None))
    return A, Bv, Cp, info


def construir(g):
    al = g.get("ALERON")
    partes = [
        superficie_h("ala", g["X_LE"], g["Z_ALA"] + 0.0, g["C"], g["B"] / 2, g["INC"],
                     (g["QUIEBRO"], 0.0, g["DIEDRO"]) if "QUIEBRO" in g else g["DIEDRO"], g["PERFIL"],
                     hinge=al["bisagra"] if al else None, hinge_y=(al["y0"], al["y1"]) if al else None, mando="aleron"),
        superficie_h("estab", g["HT_XLE"], g["HT_Z"], g["HT_C"], g["HT_B"] / 2, g["HT_INC"], 0.0, (0, 0.4, 0.08),
                     hinge=g["ELEV_HINGE"], ns=10, nc=5),
        superficie_v(g["FIN_XLE"], P.fus_lomo(g["FIN_XLE"] + 0.5 * g["FIN_C"]), g["FIN_C"], g["FIN_H"], g["RUD_HINGE"]),
    ]
    A, Bv, Cp, info = [], [], [], []
    for a, b, c, i in partes:
        A += a; Bv += b; Cp += c; info += i
    return np.array(A) / 1e3, np.array(Bv) / 1e3, np.array(Cp) / 1e3, info


def normales(info, de=0.0, dr=0.0, da=0.0):
    N = []
    for k in info:
        if k["tipo"] == "V":
            d = np.radians(dr) if k["mando"] else 0.0       # borde de fuga a la derecha (+Y)
            N.append([-np.sin(d), np.cos(d), 0.0]); continue
        d = de if k["mando"] == "prof" else (-k["lado"] * da if k["mando"] == "aleron" else 0.0)   # aleron derecho arriba con da > 0
        a = np.radians(k["inc"] + d) - np.arctan(k["slope"])
        gm = np.radians(k["die"])
        N.append([np.sin(a), -k["lado"] * np.cos(a) * np.sin(gm), np.cos(a) * np.cos(gm)])
    return np.array(N)


def segmento(Pt, A, B, nucleo=1e-4):
    r1 = Pt[:, None, :] - A[None, :, :]
    r2 = Pt[:, None, :] - B[None, :, :]
    r0 = B - A
    cr = np.cross(r1, r2)
    cr2 = np.sum(cr ** 2, axis=-1)
    n1 = np.linalg.norm(r1, axis=-1); n2 = np.linalg.norm(r2, axis=-1)
    k = (np.einsum("jk,ijk->ij", r0, r1 / n1[..., None] - r2 / n2[..., None])) / (4 * np.pi * np.maximum(cr2, nucleo ** 2))
    return cr * k[..., None]


def herradura(Pt, A, B, largo=50.0):
    Ainf = A + np.array([largo, 0, 0]); Binf = B + np.array([largo, 0, 0])
    return segmento(Pt, Ainf, A) + segmento(Pt, A, B) + segmento(Pt, B, Binf)


class Modelo:
    def __init__(self, x_cg_mm, z_cg_mm=0.0, **cambios):
        self.g = geo_por_defecto(); self.g.update(cambios)
        g = self.g
        self.S, self.b, self.c = g["B"] * g["C"] / 1e6, g["B"] / 1e3, g["C"] / 1e3
        self.A, self.B, self.Cp, self.info = construir(g)
        self.AIC = herradura(self.Cp, self.A, self.B)
        self.mid = 0.5 * (self.A + self.B)
        self.AICm = herradura(self.mid, self.A, self.B)
        self.cg = np.array([x_cg_mm, 0.0, z_cg_mm]) / 1e3

    def resolver(self, alfa, beta=0.0, p=0.0, q=0.0, r=0.0, de=0.0, dr=0.0, da=0.0, V=10.0):
        a, b = np.radians(alfa), np.radians(beta)
        Vinf = V * np.array([np.cos(a) * np.cos(b), -np.sin(b), np.sin(a) * np.cos(b)])   # aire en ejes del proyecto
        w = np.array([-p, q, -r])
        N = normales(self.info, de, dr, da)
        Vcp = Vinf - np.cross(w, self.Cp - self.cg)
        Am = np.einsum("ijk,ik->ij", self.AIC, N)
        Gm = np.linalg.solve(Am, -np.sum(Vcp * N, axis=1))
        Vm = Vinf - np.cross(w, self.mid - self.cg) + np.einsum("ijk,j->ik", self.AICm, Gm)
        F = RHO * Gm[:, None] * np.cross(Vm, self.B - self.A)
        M = np.cross(self.mid - self.cg, F)
        Rt = np.diag([-1.0, 1.0, -1.0])
        Fb, Mb = F.sum(0) @ Rt.T, M.sum(0) @ Rt.T
        qS = 0.5 * RHO * V ** 2 * self.S
        ca, sa = np.cos(a), np.sin(a)
        return dict(CL=(-Fb[2] * ca + Fb[0] * sa) / qS, CDi=(-Fb[0] * ca - Fb[2] * sa) / qS, CY=Fb[1] / qS,
                    Cl=Mb[0] / (qS * self.b), Cm=Mb[1] / (qS * self.c), Cn=Mb[2] / (qS * self.b))


# --------------- correcciones empiricas del fuselaje (vaina) ---------------
def fus_volumen():
    """Volumen del fuselaje (m3), integrando la seccion rectangular redondeada (factor 0,85)."""
    xs = np.linspace(0, P.L, 200)
    a = [0.85 * 4 * P.fus_seccion(x)[0] * P.fus_seccion(x)[1] for x in xs]
    return np.trapezoid(a, xs) / 1e9


def fus_Cm_alfa(m):
    """Raymer (Gilruth): Kf W^2 L / (c S) por grado; Kf ~ 0,005 con el ala al 18 % del fuselaje."""
    g = m.g
    return 0.005 * (g["FUS_W"] / 1e3) ** 2 * (g["L"] / 1e3) / (m.c * m.S) * 57.3


def fus_Cn_beta(m):
    """Raymer: -1,3 Vol / (S b) (D/W) por radian."""
    g = m.g
    return -1.3 * fus_volumen() / (m.S * m.b) * (g["FUS_H"] / g["FUS_W"])


def fus_Cl_beta(m):
    """DATCOM simplificado: ala alta estabiliza. z_wf < 0 para ala por encima del eje."""
    g = m.g
    A = g["B"] / g["C"]
    zwf = -(g["Z_ALA"] + 0.06 * g["C"]) / 1e3
    D = 0.5 * (g["FUS_W"] + g["FUS_H"]) / 1e3
    return 1.2 * np.sqrt(A) * (zwf / m.b) * (2 * D / m.b)


def derivadas(m, alfa0, V=10.0, h=1.0):
    r0 = m.resolver(alfa0, V=V)
    ra = m.resolver(alfa0 + h, V=V)
    rb = m.resolver(alfa0, beta=h, V=V)
    hr = np.radians(h)
    bw, cw = 2 * V / m.b, 2 * V / m.c
    rp = m.resolver(alfa0, p=0.1 * bw, V=V)
    rq = m.resolver(alfa0, q=0.1 * cw, V=V)
    rr = m.resolver(alfa0, r=0.1 * bw, V=V)
    re = m.resolver(alfa0, de=h, V=V)
    rt = m.resolver(alfa0, dr=h, V=V)
    D = dict(CL=r0["CL"], Cm=r0["Cm"], CDi=r0["CDi"],
             CLa=(ra["CL"] - r0["CL"]) / hr, Cma=(ra["Cm"] - r0["Cm"]) / hr,
             CYb=(rb["CY"] - r0["CY"]) / hr, Clb=(rb["Cl"] - r0["Cl"]) / hr, Cnb=(rb["Cn"] - r0["Cn"]) / hr,
             CYp=(rp["CY"] - r0["CY"]) / 0.1, Clp=(rp["Cl"] - r0["Cl"]) / 0.1, Cnp=(rp["Cn"] - r0["Cn"]) / 0.1,
             Cmq=(rq["Cm"] - r0["Cm"]) / 0.1, CLq=(rq["CL"] - r0["CL"]) / 0.1,
             CYr=(rr["CY"] - r0["CY"]) / 0.1, Clr=(rr["Cl"] - r0["Cl"]) / 0.1, Cnr=(rr["Cn"] - r0["Cn"]) / 0.1,
             Cmde=(re["Cm"] - r0["Cm"]) / hr, CLde=(re["CL"] - r0["CL"]) / hr,
             CYdr=(rt["CY"] - r0["CY"]) / hr, Cldr=(rt["Cl"] - r0["Cl"]) / hr, Cndr=(rt["Cn"] - r0["Cn"]) / hr)
    if any(k["mando"] == "aleron" for k in m.info):
        rd = m.resolver(alfa0, da=h, V=V)
        D.update(CLda=(rd["CL"] - r0["CL"]) / hr, CYda=(rd["CY"] - r0["CY"]) / hr,
                 Clda=(rd["Cl"] - r0["Cl"]) / hr, Cnda=(rd["Cn"] - r0["Cn"]) / hr)
    D["Cma"] += fus_Cm_alfa(m)
    D["Cnb"] += fus_Cn_beta(m)
    D["Clb"] += fus_Cl_beta(m)
    return D


def punto_neutro(**cambios):
    m1, m2 = Modelo(100.0, **cambios), Modelo(250.0, **cambios)
    c1 = (m1.resolver(1.0)["Cm"] - m1.resolver(0.0)["Cm"]) / np.radians(1) + fus_Cm_alfa(m1)
    c2 = (m2.resolver(1.0)["Cm"] - m2.resolver(0.0)["Cm"]) / np.radians(1) + fus_Cm_alfa(m2)
    return 100.0 + (0 - c1) * 150.0 / (c2 - c1)


def modos_laterales(D, masa, Ixx, Izz, V, S, b):
    """Autovalores del modelo lateral linealizado (beta, p, r, phi), ejes de estabilidad, Ixz = 0."""
    qS = 0.5 * RHO * V ** 2 * S
    Yb, Yp, Yr = qS * D["CYb"] / masa, qS * b * D["CYp"] / (2 * V * masa), qS * b * D["CYr"] / (2 * V * masa)
    Lb, Lp, Lr = qS * b * D["Clb"] / Ixx, qS * b * b * D["Clp"] / (2 * V * Ixx), qS * b * b * D["Clr"] / (2 * V * Ixx)
    Nb, Np, Nr = qS * b * D["Cnb"] / Izz, qS * b * b * D["Cnp"] / (2 * V * Izz), qS * b * b * D["Cnr"] / (2 * V * Izz)
    A = np.array([[Yb / V, Yp / V, Yr / V - 1, G0 / V],
                  [Lb, Lp, Lr, 0],
                  [Nb, Np, Nr, 0],
                  [0, 1, 0, 0]])
    ev = np.linalg.eigvals(A)
    reales = sorted([e.real for e in ev if abs(e.imag) < 1e-9])
    compl = [e for e in ev if e.imag > 1e-9]
    espiral = max(reales, key=lambda x: x) if reales else float("nan")        # el menos negativo
    rodadura = min(reales) if reales else float("nan")
    hol = compl[0] if compl else None
    return dict(espiral=espiral, rodadura=rodadura,
                holandes_hz=abs(hol.imag) / (2 * np.pi) if hol is not None else float("nan"),
                holandes_amort=-hol.real / abs(hol) if hol is not None else float("nan"))


def calado_estab_para(V_obj, masa, x_cg, **cambios):
    """Calado del estabilizador para que con la profundidad neutra el avion vuele a V_obj."""
    def cm_eq(inc):
        m = Modelo(x_cg, HT_INC=inc, **cambios)
        CLobj = 2 * masa * G0 / (RHO * V_obj ** 2 * m.S)
        r0, r1 = m.resolver(0.0), m.resolver(4.0)
        a = 4.0 * (CLobj - r0["CL"]) / (r1["CL"] - r0["CL"])
        return m.resolver(a)["Cm"] + fus_Cm_alfa(m) * np.radians(a)
    i0, i1 = -4.0, 2.0
    c0, c1 = cm_eq(i0), cm_eq(i1)
    for _ in range(30):
        im = i1 - c1 * (i1 - i0) / (c1 - c0)
        i0, c0, i1, c1 = i1, c1, im, cm_eq(im)
        if abs(c1) < 1e-5: break
    return i1


if __name__ == "__main__":
    # uso: vlm_e1.py [masa_kg] [Ixx Izz]   (por defecto, estimaciones antes de tener las piezas)
    masa = float(sys.argv[1]) if len(sys.argv) > 1 else 0.65
    Ixx = float(sys.argv[2]) if len(sys.argv) > 2 else 0.030
    Izz = float(sys.argv[3]) if len(sys.argv) > 3 else 0.050
    V = 9.5
    xcg = P.X_CG
    inc = calado_estab_para(V, masa, xcg)
    xnp = punto_neutro(HT_INC=inc)
    print("%s: masa %.2f kg, CG X %.0f mm | calado del estabilizador para %.1f m/s con profundidad neutra: %+.2f deg"
          % (ID, masa, xcg, V, inc))
    print("punto neutro X %.1f mm -> margen estatico %.1f %%" % (xnp, (xnp - xcg) / P.C * 100))
    m = Modelo(xcg, HT_INC=inc)
    CLv = 2 * masa * G0 / (RHO * V ** 2 * m.S)
    print("carga alar %.1f g/dm2 | CL en crucero %.2f | perdida (CLmax 1,1) %.1f m/s"
          % (masa * 1e3 / (m.S * 100), CLv, np.sqrt(2 * masa * G0 / (RHO * m.S * 1.1))))
    res = dict(avion=ID, masa=masa, x_cg=xcg, HT_INC=inc, xnp=xnp, barrido=[])
    con_al = bool(getattr(P, "ALERON", None))
    print("\nDIEDRO  Cl_b     Cn_b     Cl_p    Cn_r   " + ("  Cl_da    Cn_da    CY_da " if con_al else "  Cn_dr    Cl_dr ")
          + " | espiral (1/s)  t_doble/t_mitad  holandes Hz  amort.")
    for die in getattr(P, "BARRIDO_DIEDRO", (0, 2, 4, 6, 8, 10)):
        mm = Modelo(xcg, HT_INC=inc, DIEDRO=die)
        D = derivadas(mm, 3.0, V=V)
        mo = modos_laterales(D, masa, Ixx, Izz, V, mm.S, mm.b)
        s = mo["espiral"]
        t = ("dobla en %.0f s" % (np.log(2) / s)) if s > 0 else ("se corrige a la mitad en %.0f s" % (np.log(2) / -s))
        m1, m2, m3 = (D["Clda"], D["Cnda"], D["CYda"]) if con_al else (D["Cndr"], D["Cldr"], 0.0)
        print("  %4.1f %+.4f  %+.4f  %+.3f  %+.4f  %+.4f  %+.4f  %+.4f | %+.4f  %-30s  %.2f  %.2f"
              % (die, D["Clb"], D["Cnb"], D["Clp"], D["Cnr"], m1, m2, m3, s, t, mo["holandes_hz"], mo["holandes_amort"]))
        res["barrido"].append(dict(diedro=die, **{k: float(v) for k, v in D.items()}, **mo))
    if con_al:   # guinada adversa: Cn_da / Cl_da (cuanto guina hacia fuera del viraje por cada unidad de alabeo)
        print("guinada adversa con el diedro de diseno: Cn_da / Cl_da = %+.3f" % (
            next(r["Cnda"] / r["Clda"] for r in res["barrido"] if r["diedro"] == P.DIEDRO)))
    nom = "vlm_resultados.json" if ID == "E1" else "vlm_resultados_%s.json" % ID
    json.dump(res, open(os.path.join(os.path.dirname(os.path.abspath(__file__)), nom), "w"), indent=1)
