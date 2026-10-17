"""Exporta el modelo de vuelo del Tandem T1 al simulador (datos/vehiculos/T1.js), como modelo_aero_e1.py para los
entrenadores: tablas del VLM en configuracion tandem (dos alas, elevones, winglets, correcciones de fuselaje),
perdida ala por ala, resistencia parasita estimada, helice del E1, mandos (elevones), masa e inercias de
masas_t1.py y una malla ligera para el visor 3D.

Lo propio del tandem: las tablas CL, CDi y Cm en funcion de alfa no son las del VLM lineal sin mas; a cada ala se le
limita su CL propio a CLmax (perdida progresiva) y la sustentacion perdida se quita del total con su brazo al CG.
Asi el ala delantera (mas calada y sin el downwash de la otra) entra en perdida antes y el morro cae solo; la
perdida "total" del simulador (su sigmoide) se pone donde entra el ala trasera.

Ejes cuerpo estandar (x adelante, y derecha, z abajo); coeficientes por radian. La malla va en metros, en ejes
cuerpo con origen en el CG.

    $env:ENTRENADOR = "T1"; python scripts/modelo_aero_t1.py
"""
import json, os, sys
import numpy as np
from manifold3d import Manifold, CrossSection, set_circular_segments

os.environ.setdefault("ENTRENADOR", "T1")
AQUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, AQUI); sys.path.insert(0, os.path.join(AQUI, "..", "analisis"))
from avion import ID, P   # noqa: E402
assert ID == "T1"
import vlm_e1 as V        # noqa: E402
GT = P.GT

DIR_DATOS = os.path.join(AQUI, "..", "datos")                 # datos comunes de los simuladores
iner = json.load(open(os.path.join(GT.OUT, "inercias.json")))
x_cg, z_cg = iner["cg_mm"][0], iner["cg_mm"][2]
mod = V.Modelo(x_cg_mm=x_cg, z_cg_mm=z_cg)
VREF = 12.0
S = mod.S
S_SUP = dict(ala_del=P.B * P.C_F / 1e6, ala_tras=P.B * P.C_R / 1e6)
X_AC = dict(ala_del=P.X_LE_F + 0.25 * P.C_F, ala_tras=P.X_LE_R + 0.25 * P.C_R)
# NACA 3407 a Re 60-80k (cuerdas de 85-95 mm a 11-14 m/s): perfil fino con curvatura, CLmax ~1,0 y perdida
# negativa pronto (~-0,55). Son estimaciones hasta calibrar con planeos reales
CLMAX, CLMIN = 1.0, -0.55
CD_HELICE_PARADA = 0.025   # helice de 9 pulgadas parada (motor cortado): ~36 cm2 de pala de frente sobre 10,8 dm2 de ala


def saturar(cl, n=6.0):
    """Perdida progresiva de un ala: su CL lineal limitado a CLMAX (o CLMIN), con transicion suave que empieza a
    notarse al 85 % del maximo."""
    lim = CLMAX if cl >= 0 else CLMIN
    return lim * (1 - np.exp(-abs(cl / lim) ** n)) ** (1 / n)


# ---- tablas longitudinales vs alfa (alfa del fuselaje), con la perdida de cada ala ----
cmf = V.fus_Cm_alfa(mod)
tabla, propio = [], []
for a in np.arange(-14, 23, 1.0):
    r = mod.resolver(a, V=VREF, por_sup=True)
    CL, CDi, Cm = r["CL"], r["CDi"], r["Cm"] + cmf * np.radians(a)
    fila = dict(alfa=float(a))
    for nm in ("ala_del", "ala_tras"):
        cl_propio = r["sup"][nm]["CL"] * S / S_SUP[nm]            # CL del ala referido a su propia superficie
        dCL = (saturar(cl_propio) - cl_propio) * S_SUP[nm] / S    # sustentacion que pierde, referida a S
        CL += dCL
        Cm += dCL * (x_cg - X_AC[nm]) / P.C                       # ala delante del CG: perder sustentacion baja el morro
        CDi += 0.6 * abs(dCL)                                     # resistencia de la parte desprendida
        fila[nm] = float(cl_propio); fila[nm + "_sat"] = float(saturar(cl_propio))
    tabla.append(dict(alfa=float(a), CL=float(CL), CDi=float(CDi), Cm=float(Cm)))
    propio.append(fila)
derivs = [dict(alfa=a, **{k: float(v) for k, v in V.derivadas(mod, a, V=VREF).items()}) for a in (-6.0, -2.0, 2.0, 6.0, 10.0)]
al = np.array([f["alfa"] for f in propio])
a_perd_del = float(np.interp(0.95 * CLMAX, [f["ala_del"] for f in propio], al))        # entra el ala delantera
a_perd_tras = float(np.interp(0.95 * CLMAX, [f["ala_tras"] for f in propio], al))      # entra tambien la trasera
a_perd_neg = float(np.interp(0.95 * CLMIN, [f["ala_del"] for f in propio], al))                 # CL del ala del. crece con alfa
perdida = dict(alfa_perdida_grados=round(a_perd_tras, 1), anchura_grados=3.0, alfa_perdida_neg_grados=round(a_perd_neg, 1),
               CL_placa_factor=0.8, mando_post_perdida=0.4, alfa_perdida_ala_delantera_grados=round(a_perd_del, 1),
               nota="la tabla CL/Cm ya lleva la perdida progresiva de cada ala (CLmax %.2f); la sigmoide del simulador "
                    "entra cuando tambien pierde el ala trasera" % CLMAX)

# ---- resistencia parasita (Re ~ 7e4 en las alas) ----
cf = lambda Re: 0.074 / Re ** 0.2
cd_alas = sum(2 * cf(VREF * c / 1e3 / 1.5e-5) * 1.2 * (P.B * c / 1e6) / S for c in (P.C_F, P.C_R))
xs = np.linspace(0, P.L, 200)
moj_fus = np.trapezoid([2 * np.pi * P.fus_seccion(x)[0] for x in xs], xs) / 1e6
cd_fus = cf(VREF * P.L / 1e3 / 1.5e-5) * 1.1 * moj_fus / S
W = P.WINGLET
moj_w = 2 * 2 * (0.5 * (W["c_raiz"] + W["c_punta"]) * W["h"]) / 1e6
cd_w = cf(VREF * 0.5 * (W["c_raiz"] + W["c_punta"]) / 1e3 / 1.5e-5) * 1.05 * moj_w / S
CD0 = (cd_alas + cd_fus + cd_w + 0.004) * 1.3      # +0,004 interferencias y gomas; x1,3 rugosidad de impresion

# ---- helice: la del E1 (SunnySky X2212 KV980 3S + APC 9x4.7: 840 gf a 8730 rpm, 13,2 A), sin downthrust ----
D_prop, n_max = 9 * 0.0254, 8730 / 60
CT0 = 0.840 * 9.81 / 1.225 / n_max ** 2 / D_prop ** 4
prop = dict(T_max_N=0.840 * 9.81, D_m=D_prop, n_max_rps=n_max, CT0=float(CT0), J0=0.72, I_max_A=13.2,
            P_max_W=146.5, masa_bateria_Wh=11.1 * 1.3, downthrust_grados=P.DOWNTHRUST)

EL = P.ELEVON
mandos = dict(prof_max_grados=EL["sim_prof_grados"], aleron_max_grados=EL["sim_aleron_grados"], elevon_max_grados=EL["max_grados"],
              timon_max_grados=0.0, expo=0.40, servo_tau_s=0.06, servo_vel_grados_s=400.0, izq_der="elevones (alabeo)",
              nota="de > 0 = elevones abajo (morro abajo); da > 0 = elevon derecho arriba (alabeo a la derecha); "
                   "cada elevon = de +- da, con tope elevon_max_grados")

# ---- equilibrio: elevon que compensa a cada velocidad; pérdida real = cuando el ala delantera llega a CLMAX ----
sys.path.insert(0, os.path.join(AQUI, "..", "analisis"))
from vlm_t1 import equilibrio, reparto   # noqa: E402
m_kg = iner["masa_kg"]
Vs = np.arange(8.0, 20.1, 0.25)
cl_del = []
for Vv in Vs:
    a_e, de_e, _ = equilibrio(mod, m_kg, Vv)
    cl_del.append(reparto(mod, a_e, de_e, Vv)["ala_del"])
v_perd = float(np.interp(-CLMAX, -np.array(cl_del), Vs))          # cl_del decrece con V
V_TRIM = max(13.0, float(round(1.2 * np.sqrt(2 * m_kg * 9.81 / (1.225 * S * 1.0)))))   # 1,2 veces la perdida (CLmax 1,0 del conjunto), minimo 13
a_trim, de_trim, _ = equilibrio(mod, m_kg, V_TRIM)
xnp = V.punto_neutro()

# ---- malla ligera para el visor (superficies exteriores) ----
set_circular_segments(24)


def a_cuerpo(m):
    mesh = m.to_mesh()
    v = np.asarray(mesh.vert_properties)[:, :3].astype(float)
    b = np.c_[-(v[:, 0] - x_cg), v[:, 1], -(v[:, 2] - z_cg)] / 1000.0
    return dict(v=np.round(b, 4).ravel().tolist(), i=np.asarray(mesh.tri_verts).ravel().astype(int).tolist())


def cuerpo_pt(X, Y, Z):
    return [-(X - x_cg) / 1000, Y / 1000, -(Z - z_cg) / 1000]


perfil = [(GT.r_out(x), x) for x in np.linspace(0, P.L, 50)] + [(0.01, P.L), (0.01, 0.0)]
pp = np.array(perfil)
if 0.5 * np.sum(pp[:, 0] * np.roll(pp[:, 1], -1) - np.roll(pp[:, 0], -1) * pp[:, 1]) < 0: pp = pp[::-1]
fus = GT.along_x(Manifold.revolve(CrossSection([pp.tolist()]), 24))


def semiala(c, xle, zle, inc, left, cs=None, z0=0.0, z1=None):
    cs = cs or CrossSection([GT.section_pts(c).tolist()])
    seg = Manifold.extrude(cs, (P.B / 2 if z1 is None else z1) - z0)
    return GT.wing_to_global(seg, 0.0, 0.0, xle, zle, inc, z0, left)


cs_r = CrossSection([GT.section_pts(P.C_R).tolist()])
xh, big = GT.HINGE * P.C_R, 500
cs_main = cs_r ^ CrossSection.square([big, big]).translate([xh - big, -big / 2])
cs_elev = cs_r ^ CrossSection.square([big, big]).translate([xh + GT.GAP, -big / 2])
e_len = (EL["y1"] - EL["y0"]) / 2
ala, elevones = None, []
Z_H = P.Z_LE_R + GT.camber_at(GT.HINGE) * P.C_R
for left, signo in ((True, 1.0), (False, -1.0)):
    s = semiala(P.C_F, P.X_LE_F, P.Z_LE_F, P.INC_F, left)
    s = s + semiala(P.C_R, P.X_LE_R, P.Z_LE_R, P.INC_R, left, cs=cs_r, z0=0.0, z1=EL["y0"])
    s = s + semiala(P.C_R, P.X_LE_R, P.Z_LE_R, P.INC_R, left, cs=cs_main, z0=EL["y0"], z1=EL["y1"])
    s = s + semiala(P.C_R, P.X_LE_R, P.Z_LE_R, P.INC_R, left, cs=cs_r, z0=EL["y1"], z1=P.B / 2)
    ala = s if ala is None else ala + s
    for j in range(2):   # dos elevones por lado, cada uno gira sobre la bisagra del ala trasera (eje +y del cuerpo)
        y0 = EL["y0"] + j * e_len
        pieza = semiala(P.C_R, P.X_LE_R, P.Z_LE_R, P.INC_R, left, cs=cs_elev, z0=y0, z1=y0 + e_len)
        elevones.append(dict(**a_cuerpo(pieza), bisagra=cuerpo_pt(P.X_LE_R + xh, (-1 if left else 1) * y0, Z_H),
                             eje=[0.0, 1.0, 0.0], signo=signo, prof=True))    # giro = de + signo * da
wl = None
for sg in (-1, 1):
    w = GT.fin().translate([W["x_te"], sg * W["y"], W["z0"]])
    wl = w if wl is None else wl + w
malla = dict(fuselaje=a_cuerpo(fus), ala=a_cuerpo(ala), estab=a_cuerpo(wl), alerones=elevones,
             helice=cuerpo_pt(-42.0, 0.0, 0.0), helice_r=D_prop / 2)

PERFIL_TXT = "NACA 3407"
modelo = dict(
    id=ID, nombre=P.NOMBRE, descripcion=P.DESCRIPCION,
    ayuda=("Elevones: las flechas ← → alabean y ↑ ↓ cabecean con las mismas superficies. Sin diedro, no nivela solo. "
           "Vuela rápido: no lo dejes bajar de 12 m/s, el ala delantera entra en pérdida antes que la trasera."),
    perfil=PERFIL_TXT,
    caracteristicas=[["Envergadura", "%.2f m (dos alas)" % (P.B / 1e3)], ["Cuerdas", "%.0f mm delantera / %.0f mm trasera" % (P.C_F, P.C_R)],
                     ["Perfil alar", PERFIL_TXT], ["Superficie alar", "%.1f dm² (las dos alas)" % (S * 100)],
                     ["Masa en vuelo", "%.0f g (todo en PLA normal)" % (m_kg * 1e3)], ["Carga alar", "%.1f g/dm²" % (m_kg * 1e3 / (S * 100))],
                     ["Diedro", "ninguno; dos derivas de 80×75 mm sobre el ala trasera, junto al fuselaje"], ["Mandos", P.MANDOS_TXT],
                     ["Velocidad de pérdida", "%.1f m/s (entra el ala delantera; la trasera a %.0f°)" % (v_perd, a_perd_tras)],
                     ["Crucero (compensado)", "≈ %.0f m/s con %.1f° de elevón" % (V_TRIM, de_trim)],
                     ["Motor", "SunnySky X2212 KV980, hélice 9×4,7"], ["Batería", "3S 1300 mAh, en F2 (X %.0f mm)" % iner["x_bateria_mm"]],
                     ["Empuje / peso", "%.2f" % (0.840 / m_kg)], ["Margen estático", "%.0f %% de la cuerda media" % ((xnp - x_cg) / P.C * 100)]],
    S_m2=S, b_m=mod.b, c_m=mod.c, masa_kg=m_kg, cg_mm=iner["cg_mm"],
    inercia=dict(Ixx=iner["Ixx"], Iyy=iner["Iyy"], Izz=iner["Izz"], Ixz=iner["Ixz"]),
    tabla_alfa=tabla, derivadas=derivs, CD0=float(CD0), CD_helice_parada=CD_HELICE_PARADA,
    desglose_CD0=dict(alas=float(cd_alas), fuselaje=float(cd_fus), winglets=float(cd_w)),
    perdida=perdida, propulsion=prop, mandos=mandos, compensador_grados=round(float(de_trim), 2),
    lanzamiento=dict(vel_ms=10.0, cabeceo_grados=5.0),       # a mano no se le saca mucho mas; la perdida esta en ~11 m/s
    malla=malla, punto_neutro_mm=xnp, x_le_mm=P.X_LE,
    cg_rango_pct=[100, 160], cg_ref_texto="la cuerda media (90 mm) desde el borde de ataque del ala delantera",
    colores=dict(fuselaje=0xf4f4f4, ala=0x4caf50, estab=0xdddddd, moviles=0xd32f2f),
    reparto_alas=propio,
)
DIR_AV = os.path.join(DIR_DATOS, "vehiculos")
NL = chr(10)
clase = P.CLASE_JS
with open(os.path.join(DIR_AV, ID + ".js"), "w", encoding="utf-8") as fj:
    fj.write("// %s. Generado por scripts/modelo_aero_t1.py (ENTRENADOR=%s): no editar a mano." % (modelo["nombre"], ID) + NL)
    codigo = open(os.path.join(AQUI, clase[1]), encoding="utf-8").read().rstrip()
    codigo = codigo.replace("class %s extends" % clase[0], "window.%s = window.%s || class %s extends" % ((clase[0],) * 3), 1)
    fj.write(codigo + ";" + NL)
    fj.write("Modelos.registrar(" + json.dumps(modelo) + ", window." + clase[0] + ");" + NL)
fich = sorted(f for f in os.listdir(DIR_AV) if f.endswith(".js") and f != "indice.js")
with open(os.path.join(DIR_AV, "indice.js"), "w", encoding="utf-8") as fj:
    fj.write("// Ficheros de aviones de esta carpeta. Lo reescribe scripts/modelo_aero_e1.py; con el servidor del aula se genera solo." + NL
             + "Modelos.indice(" + json.dumps(fich) + ");" + NL)
print("%s: CG %.1f mm, punto neutro %.1f mm, margen %.1f %% de la cuerda media | CD0 %.4f (alas %.4f, fus %.4f, winglets %.4f) + helice parada %.3f"
      % (ID, x_cg, xnp, (xnp - x_cg) / P.C * 100, CD0, cd_alas, cd_fus, cd_w, CD_HELICE_PARADA))
print("perdida: ala delantera a alfa %.1f (en vuelo equilibrado, %.1f m/s); ala trasera a alfa %.1f; negativa a %.1f | compensador %.2f (%.0f m/s)"
      % (a_perd_del, v_perd, a_perd_tras, a_perd_neg, de_trim, V_TRIM))
print(" alfa   CL     CDi     Cm    | CL propio del. (sat)  tras. (sat)")
for t, f in zip(tabla, propio):
    if t["alfa"] % 2 == 0: print("  %+3.0f  %+.3f  %.4f  %+.4f | %+.2f (%+.2f)   %+.2f (%+.2f)" % (t["alfa"], t["CL"], t["CDi"], t["Cm"], f["ala_del"], f["ala_del_sat"], f["ala_tras"], f["ala_tras_sat"]))
d = derivs[2]
print("  alfa 2: Clb %+.4f Cnb %+.4f Clp %+.3f Cnr %+.4f Cmq %+.2f Cmde %+.3f CLde %+.3f Clda %+.4f Cnda %+.4f CYda %+.4f"
      % (d["Clb"], d["Cnb"], d["Clp"], d["Cnr"], d["Cmq"], d["Cmde"], d["CLde"], d["Clda"], d["Cnda"], d["CYda"]))
ntri = sum(len(m["i"]) // 3 for m in malla.values() if isinstance(m, dict)) + sum(len(a["i"]) // 3 for a in malla["alerones"])
print("malla: %d triangulos | %.0f kB" % (ntri, os.path.getsize(os.path.join(DIR_AV, ID + ".js")) / 1024))
