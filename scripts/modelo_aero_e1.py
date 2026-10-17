"""Exporta el modelo de vuelo del entrenador (E1, o el que diga la variable de entorno ENTRENADOR) al
simulador (datos/vehiculos/E1.js o E2.js):
tablas del VLM (ala + cola + correcciones de fuselaje), perdida, resistencia parasita estimada,
helice, mandos, masa e inercias de masas_e1.py y una malla ligera para el visor 3D.

Ejes cuerpo estandar (x adelante, y derecha, z abajo); coeficientes por radian. La malla va en
metros, en ejes cuerpo con origen en el CG.
"""
import json, os, sys
import numpy as np
from manifold3d import Manifold, CrossSection, set_circular_segments
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "analisis"))
from avion import ID, P
import geom_e1 as G
import vlm_e1 as V

DIR_DATOS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "datos")                 # datos comunes de los simuladores
iner = json.load(open(os.path.join(G.OUT, "inercias.json")))
x_cg, z_cg = iner["cg_mm"][0], iner["cg_mm"][2]
mod = V.Modelo(x_cg_mm=x_cg, z_cg_mm=z_cg)
VREF = 9.5

# ---- tablas longitudinales vs alfa (alfa del fuselaje) ----
tabla = []
for a in np.arange(-10, 16, 2.0):
    r = mod.resolver(a, V=VREF)
    tabla.append(dict(alfa=float(a), CL=r["CL"], CDi=r["CDi"], Cm=r["Cm"] + V.fus_Cm_alfa(mod) * np.radians(a)))
derivs = [dict(alfa=a, **{k: float(v) for k, v in V.derivadas(mod, a, V=VREF).items()}) for a in (-6.0, -2.0, 2.0, 6.0, 10.0)]

# ---- resistencia parasita (Re ~ 1,1e5 en el ala, piezas impresas con lineas de capa) ----
S = mod.S
cf = lambda Re: 0.074 / Re ** 0.2
Re_ala = VREF * P.C / 1e3 / 1.5e-5
cd_ala = 2 * cf(Re_ala) * 1.2
xs = np.linspace(0, P.L, 100)
moj_fus = np.trapezoid([2 * (2 * P.fus_seccion(x)[0] + 2 * P.fus_seccion(x)[1]) * 0.9 for x in xs], xs) / 1e6
cd_fus = cf(VREF * P.L / 1e3 / 1.5e-5) * 1.1 * moj_fus / S
moj_cola = 2 * (P.HT_B * P.HT_C + P.FIN_C * P.FIN_H) / 1e6
cd_cola = cf(VREF * P.HT_C / 1e3 / 1.5e-5) * 1.05 * moj_cola / S
CD0 = (cd_ala + cd_fus + cd_cola + 0.004) * 1.3      # +0,004 interferencias y gomas; x1,3 rugosidad de impresion

# ---- helice: SunnySky X2212 KV980 3S + APC 9x4.7 (tabla del fabricante: 840 gf a 8730 rpm, 13,2 A) ----
D_prop, n_max = 9 * 0.0254, 8730 / 60
CT0 = 0.840 * 9.81 / 1.225 / n_max ** 2 / D_prop ** 4
prop = dict(T_max_N=0.840 * 9.81, D_m=D_prop, n_max_rps=n_max, CT0=float(CT0), J0=0.72, I_max_A=13.2,
            P_max_W=146.5, masa_bateria_Wh=11.1 * 1.3,
            downthrust_grados=P.DOWNTHRUST)      # bancada de F1 inclinada: el empuje apunta hacia abajo

# timon: con 25 grados, 3 s a tope ponian el avion a 150 grados de alabeo; con teclado la palanca siempre va a tope
mandos = dict(prof_max_grados=12.0, timon_max_grados=15.0 if G.CON_TIMON else 0.0, expo=0.40, servo_tau_s=0.06,
              servo_vel_grados_s=300.0, izq_der="timón" if G.CON_TIMON else "alerones",
              nota="de > 0 = profundidad abajo (morro abajo); dr > 0 = timon a la derecha (morro a la derecha); "
                   "da > 0 = aleron derecho arriba (alabeo a la derecha)")
if G.ALERON:
    mandos["aleron_max_grados"] = G.ALERON.get("sim_max_grados", G.ALERON["max_grados"])   # con teclado, la palanca siempre va a tope
# perdida del NACA 2412 a Re ~ 1e5: ~12 grados de ala = 10 de fuselaje (calado 2)
perdida = dict(alfa_perdida_grados=12.0 - P.INC, anchura_grados=3.0, alfa_perdida_neg_grados=-10.0,
               CL_placa_factor=0.8, mando_post_perdida=0.4)

# ---- malla ligera para el visor (superficies exteriores, sin estructura interior) ----
set_circular_segments(20)


def a_cuerpo(m):
    mesh = m.to_mesh()
    v = np.asarray(mesh.vert_properties)[:, :3].astype(float)
    b = np.c_[-(v[:, 0] - x_cg), v[:, 1], -(v[:, 2] - z_cg)] / 1000.0
    return dict(v=np.round(b, 4).ravel().tolist(), i=np.asarray(mesh.tri_verts).ravel().astype(int).tolist())


sec = CrossSection([G.ccw((G.section_pts(P.C) - G.spar_origin(P.C)).tolist())])
# poliedro: la parte de dentro (plana) hasta el quiebro y la de fuera con el diedro
dentro = Manifold.extrude(sec, P.QUIEBRO)
fuera = Manifold.extrude(sec, P.B / 2 - P.QUIEBRO)
if G.ALERON:   # el ala sin el hueco del aleron, y cada aleron como pieza movil con su bisagra (ejes cuerpo)
    AL = G.ALERON
    xw, xe = G.aleron_x()
    _, ye = G.aleron_eje()
    fuera = fuera - Manifold.cube([P.C, 100, AL["y1"] - AL["y0"]]).translate([xw, -50, AL["y0"] - P.QUIEBRO])
    aleron = Manifold.extrude(G.aleron_cs(), AL["y1"] - AL["y0"])
    alerones = []
    for left, signo in ((True, 1.0), (False, -1.0)):      # comprobado en el visor: giro + sobre el eje = borde de fuga abajo
        p0, p1 = (G.punto_ala(xe, ye, s, left) for s in (AL["y0"], AL["y1"]))
        eje = (p1 - p0) if not left else (p0 - p1)              # hacia +y del cuerpo en los dos lados
        eje = np.array([-eje[0], eje[1], -eje[2]]) / np.linalg.norm(eje)
        alerones.append(dict(**a_cuerpo(G.wing_to_global(aleron, AL["y0"], left)),
                             bisagra=[-(p0[0] - x_cg) / 1000, p0[1] / 1000, -(p0[2] - z_cg) / 1000],
                             eje=np.round(eje, 5).tolist(), signo=signo))   # giro = signo * da: con da > 0 el derecho sube y el izquierdo baja
ala = None
for left in (True, False):
    semi = G.wing_to_global(dentro, 0.0, left, exterior=False) + G.wing_to_global(fuera, P.QUIEBRO, left, exterior=True)
    ala = semi if ala is None else ala + semi
fus = G.solid(0, P.L) + (G.fin_fixed() - G.solid(G.FUS_SEG[-1][0], P.L))
estab = G.stab_global(True) + G.stab_global(False)
prof = G.elevator_global(True) + G.elevator_global(False)
malla = dict(fuselaje=a_cuerpo(fus), ala=a_cuerpo(ala), estab=a_cuerpo(estab), prof=a_cuerpo(prof),
             bisagra_prof=[-(G.X_HINGE_H + G.EJE_H - x_cg) / 1000, 0.0, -(P.HT_Z + G.EJE_HZ - G.PLATE_T / 2 - z_cg) / 1000],
             helice=[-(-25.0 - x_cg) / 1000, 0.0, -(0.0 - z_cg) / 1000], helice_r=D_prop / 2)
if G.CON_TIMON:
    malla.update(timon=a_cuerpo(G.rudder()), bisagra_timon=[-(G.X_EJE_T - x_cg) / 1000, 0.0, 0.0])
if G.ALERON:
    malla["alerones"] = alerones

m_kg = iner["masa_kg"]
PERFIL_TXT = "NACA %d%d%02d" % (round(P.PERFIL[0] * 100), round(P.PERFIL[1] * 10), round(P.PERFIL[2] * 100))
v_perd = np.sqrt(2 * m_kg * 9.81 / (1.225 * S * 1.1))
v_crucero = 9.5
xnp = V.punto_neutro(HT_INC=P.HT_INC)
modelo = dict(
    id=ID, nombre=getattr(P, "NOMBRE", "Entrenador E1"),
    descripcion=getattr(P, "DESCRIPCION", "Entrenador de ala alta con diedro, timón y profundidad (2 servos). Impreso en LW-PLA. "
                        "Si sueltas los mandos, nivela las alas solo."),
    ayuda=("Las flechas ← → mueven los alerones: inclina el avión y tira un poco para virar. Con poco diedro, "
           "si sueltas los mandos tarda en nivelarse: nivélalo tú." if G.ALERON else
           "El avión vira con el timón: el diedro inclina las alas solo. Si sueltas los mandos, vuelve a volar recto."),
    perfil=PERFIL_TXT,
    caracteristicas=[["Envergadura", "%.2f m" % (P.B / 1e3)], ["Cuerda", "%.0f mm" % P.C], ["Perfil alar", PERFIL_TXT],
                     ["Superficie alar", "%.1f dm²" % (S * 100)],
                     ["Masa en vuelo", "%.0f g" % (m_kg * 1e3)], ["Carga alar", "%.1f g/dm²" % (m_kg * 1e3 / (S * 100))],
                     ["Diedro", "%.0f° en las puntas (centro plano hasta %.0f mm)" % (P.DIEDRO, P.QUIEBRO) if P.DIEDRO else "ninguno (ala plana)"], ["Mandos", getattr(P, "MANDOS_TXT", "timón y profundidad")],
                     ["Velocidad de pérdida", "%.1f m/s" % v_perd], ["Crucero (compensado)", "≈ %.1f m/s" % v_crucero],
                     ["Motor", "SunnySky X2212 KV980, hélice 9×4,7"], ["Batería", "3S 1300 mAh"],
                     ["Empuje / peso", "%.2f" % (0.840 / m_kg)], ["Margen estático", "%.0f %%" % ((xnp - x_cg) / P.C * 100)]],
    S_m2=S, b_m=mod.b, c_m=mod.c, masa_kg=m_kg, cg_mm=iner["cg_mm"],
    inercia=dict(Ixx=iner["Ixx"], Iyy=iner["Iyy"], Izz=iner["Izz"], Ixz=iner["Ixz"]),
    tabla_alfa=tabla, derivadas=derivs, CD0=float(CD0),
    desglose_CD0=dict(ala=float(cd_ala), fuselaje=float(cd_fus), cola=float(cd_cola)),
    perdida=perdida, propulsion=prop, mandos=mandos, compensador_grados=0.0,
    lanzamiento=dict(vel_ms=9.0, cabeceo_grados=8.0),     # lanzamiento firme: la perdida esta en 7,2 m/s
    malla=malla, punto_neutro_mm=xnp, x_le_mm=P.X_LE,     # borde de ataque: para dar el CG en % de la cuerda
)
# cada avion es un fichero de datos/vehiculos/ que se registra solo; indice.js lista los ficheros
# (el servidor del aula lo genera leyendo la carpeta; sin servidor vale el que se escribe aqui)
DIR_AV = os.path.join(DIR_DATOS, "vehiculos")
NL = chr(10)
if ID in ("E1", "E2"):                      # retirados del simulador (2026-10-15): el entrenador del simulador es el E3
    raise SystemExit("%s ya no esta en el simulador: no se exporta (el E3 es el Entrenador 1)" % ID)
os.makedirs(DIR_AV, exist_ok=True)
clase = getattr(P, "CLASE_JS", None)        # (nombre de la clase, fichero js en scripts/) para un avion con otra fisica
with open(os.path.join(DIR_AV, ID + ".js"), "w", encoding="utf-8") as fj:
    fj.write("// %s. Generado por scripts/modelo_aero_e1.py (ENTRENADOR=%s): no editar a mano." % (modelo["nombre"], ID) + NL)
    if clase:   # varios aviones pueden usar la misma clase (E2 y E3): se declara solo si no existe ya
        codigo = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), clase[1]), encoding="utf-8").read().rstrip()
        codigo = codigo.replace("class %s extends" % clase[0], "window.%s = window.%s || class %s extends" % ((clase[0],) * 3), 1)
        fj.write(codigo + ";" + NL)
    fj.write("Modelos.registrar(" + json.dumps(modelo) + (", window." + clase[0] if clase else "") + ");" + NL)
fich = sorted(f for f in os.listdir(DIR_AV) if f.endswith(".js") and f != "indice.js")
with open(os.path.join(DIR_AV, "indice.js"), "w", encoding="utf-8") as fj:
    fj.write("// Ficheros de aviones de esta carpeta. Lo reescribe scripts/modelo_aero_e1.py; con el servidor del aula se genera solo." + NL
             + "Modelos.indice(" + json.dumps(fich) + ");" + NL)
print("%s: CG %.1f mm, punto neutro %.1f mm, margen %.1f %% | CD0 %.4f (ala %.4f, fus %.4f, cola %.4f) | perdida %.1f m/s"
      % (ID, x_cg, xnp, (xnp - x_cg) / P.C * 100, CD0, cd_ala, cd_fus, cd_cola, v_perd))
for t in tabla:
    if t["alfa"] in (-4.0, 0.0, 4.0, 8.0): print("  alfa %+3.0f: CL %.3f CDi %.4f Cm %+.4f" % (t["alfa"], t["CL"], t["CDi"], t["Cm"]))
d = derivs[2]
print("  alfa 2: Clb %+.4f Cnb %+.4f Clp %+.3f Cnr %+.4f Cmq %+.2f Cmde %+.3f Cndr %+.4f Cldr %+.4f CYdr %+.4f"
      % (d["Clb"], d["Cnb"], d["Clp"], d["Cnr"], d["Cmq"], d["Cmde"], d["Cndr"], d["Cldr"], d["CYdr"]))
if G.ALERON:
    print("  alfa 2: Clda %+.4f Cnda %+.4f CYda %+.4f CLda %+.4f (guinada adversa Cnda/Clda %+.3f)"
          % (d["Clda"], d["Cnda"], d["CYda"], d["CLda"], d["Cnda"] / d["Clda"]))
ntri = sum(len(m["i"]) // 3 for m in malla.values() if isinstance(m, dict)) + sum(len(a["i"]) // 3 for a in malla.get("alerones", []))
print("malla: %d triangulos | %.0f kB" % (ntri, os.path.getsize(os.path.join(DIR_AV, ID + ".js")) / 1024))
