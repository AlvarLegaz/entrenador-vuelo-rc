"""Tandem T1: estabilidad y mandos con el VLM de vlm_e1.py (configuracion tandem: dos alas, elevones, winglets).

Lo que no tiene el E1: no hay estabilizador que calar, el equilibrio lo da el elevon (de), asi que se calcula el
elevon y el angulo de ataque de equilibrio a la velocidad de crucero, el reparto de sustentacion entre las dos
alas (que ala entra antes en perdida) y, como en el E1, punto neutro, derivadas y modos laterales. Escribe
analisis/vlm_resultados_T1.json.

    $env:ENTRENADOR = "T1"; python analisis/vlm_t1.py            (masa e inercias de out/inercias.json si existe)
    python analisis/vlm_t1.py 0.57 0.012 0.025                    (masa kg, Ixx, Izz a mano)
"""
import json, os, sys
import numpy as np

os.environ.setdefault("ENTRENADOR", "T1")
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import vlm_e1 as V   # noqa: E402
from vlm_e1 import P, ID, RHO, G0   # noqa: E402
assert ID == "T1"


def equilibrio(m, masa, V_obj):
    """(alfa, de) que dan CL = peso y Cm = 0 a V_obj, con el modelo lineal en alfa y de (fuselaje incluido)."""
    CLobj = 2 * masa * G0 / (RHO * V_obj ** 2 * m.S)
    r0, ra, re = m.resolver(0.0, V=V_obj), m.resolver(1.0, V=V_obj), m.resolver(0.0, de=1.0, V=V_obj)
    cmf = V.fus_Cm_alfa(m) * np.radians(1)        # por grado
    A = np.array([[ra["CL"] - r0["CL"], re["CL"] - r0["CL"]],
                  [ra["Cm"] - r0["Cm"] + cmf, re["Cm"] - r0["Cm"]]])
    alfa, de = np.linalg.solve(A, [CLobj - r0["CL"], -r0["Cm"]])
    return float(alfa), float(de), CLobj


def reparto(m, alfa, de, V_obj):
    """CL propio de cada ala (referido a su superficie) en esa condicion."""
    r = m.resolver(alfa, de=de, V=V_obj, por_sup=True)
    Sf, Sr = P.B * P.C_F / 1e6, P.B * P.C_R / 1e6
    return dict(ala_del=r["sup"]["ala_del"]["CL"] * m.S / Sf, ala_tras=r["sup"]["ala_tras"]["CL"] * m.S / Sr, total=r["CL"])


if __name__ == "__main__":
    iner = os.path.join(P.DIR_T1, "out", "inercias.json")
    if len(sys.argv) > 1:
        masa, Ixx, Izz = float(sys.argv[1]), float(sys.argv[2]), float(sys.argv[3]); zcg = 0.0
    elif os.path.exists(iner):
        d = json.load(open(iner)); masa, Ixx, Izz, zcg = d["masa_kg"], d["Ixx"], d["Izz"], d["cg_mm"][2]
    else:
        masa, Ixx, Izz, zcg = 0.57, 0.012, 0.025, 0.0
    xcg = P.X_CG
    xnp = V.punto_neutro()
    m = V.Modelo(xcg, z_cg_mm=zcg)
    print("%s: masa %.3f kg, CG X %.0f mm | S %.3f m2 (dos alas), cuerda de referencia %.0f mm" % (ID, masa, xcg, m.S, P.C))
    print("punto neutro X %.1f mm -> margen estatico %.1f %% de la cuerda media (%.0f mm)" % (xnp, (xnp - xcg) / P.C * 100, xnp - xcg))
    print("carga alar %.1f g/dm2 | perdida (CLmax 1,0 del conjunto) %.1f m/s" % (masa * 1e3 / (m.S * 100), np.sqrt(2 * masa * G0 / (RHO * m.S * 1.0))))
    res = dict(avion=ID, masa=masa, x_cg=xcg, xnp=xnp, equilibrio=[], derivadas={})
    print("\nEQUILIBRIO (elevon + = borde de fuga abajo):")
    print("   V m/s   CL    alfa fus.  elevon   CL ala del.  CL ala tras.")
    for Vv in (9.0, 10.0, 11.0, 12.0, 13.0, 15.0, 18.0):
        a, de, CL = equilibrio(m, masa, Vv)
        rp = reparto(m, a, de, Vv)
        print("   %4.1f   %.2f   %+5.1f     %+5.1f     %.2f         %.2f" % (Vv, CL, a, de, rp["ala_del"], rp["ala_tras"]))
        res["equilibrio"].append(dict(V=Vv, CL=CL, alfa=a, de=de, **rp))
    Vc = 12.0
    a_c, de_c, _ = equilibrio(m, masa, Vc)
    D = V.derivadas(m, a_c, V=Vc)
    mo = V.modos_laterales(D, masa, Ixx, Izz, Vc, m.S, m.b)
    res["derivadas"] = {k: float(v) for k, v in D.items()}; res["modos"] = mo; res["V_ref"] = Vc
    s = mo["espiral"]
    t = ("dobla en %.0f s" % (np.log(2) / s)) if s > 0 else ("se corrige a la mitad en %.0f s" % (np.log(2) / -s))
    print("\nDERIVADAS a %.0f m/s (alfa %.1f, elevon %.1f):" % (Vc, a_c, de_c))
    print("  CLa %.2f  Cma %+.3f  Cmq %+.2f | CLde %+.3f  Cmde %+.3f | Clda %+.3f  Cnda %+.4f  CYda %+.4f (guinada adversa Cnda/Clda %+.3f)"
          % (D["CLa"], D["Cma"], D["Cmq"], D["CLde"], D["Cmde"], D["Clda"], D["Cnda"], D["CYda"], D["Cnda"] / D["Clda"]))
    print("  Clb %+.4f  Cnb %+.4f  CYb %+.3f  Clp %+.3f  Cnr %+.4f  Clr %+.4f  Cnp %+.4f" % (D["Clb"], D["Cnb"], D["CYb"], D["Clp"], D["Cnr"], D["Clr"], D["Cnp"]))
    print("  espiral %+.4f 1/s (%s) | balanceo holandes %.2f Hz, amortiguamiento %.2f | rodadura %.2f 1/s"
          % (s, t, mo["holandes_hz"], mo["holandes_amort"], mo["rodadura"]))
    # sensibilidad: sin winglets y con winglets dobles, para saber que hacen
    print("\nWINGLETS (a %.0f m/s): Cnb, Clb y espiral" % Vc)
    for nombre, esc in (("sin winglets", 0.01), ("de diseno (80/50 x 75)", 1.0), ("doble altura", 2.0)):
        W = dict(P.WINGLET); W["h"] = P.WINGLET["h"] * esc
        mm = V.Modelo(xcg, z_cg_mm=zcg, WINGLET=W)
        Dw = V.derivadas(mm, a_c, V=Vc); mw = V.modos_laterales(Dw, masa, Ixx, Izz, Vc, mm.S, mm.b)
        sw = mw["espiral"]
        print("  %-24s Cnb %+.4f  Clb %+.4f  espiral %+.4f (%s)  holandes %.2f Hz amort. %.2f"
              % (nombre, Dw["Cnb"], Dw["Clb"], sw, ("dobla en %.0f s" % (np.log(2) / sw)) if sw > 0 else ("mitad en %.0f s" % (np.log(2) / -sw)),
                 mw["holandes_hz"], mw["holandes_amort"]))
    json.dump(res, open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "vlm_resultados_T1.json"), "w"), indent=1)
