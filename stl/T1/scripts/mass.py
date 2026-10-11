"""Pesos, centro de gravedad, punto neutro y prestaciones."""
import json, numpy as np, os
import geom as G

D = json.load(open(os.path.join(G.OUT, "info.json")))
RHO_LW = 0.65   # g/cm3 LW-PLA espumado (conservador)
T_SHELL = 0.045 # cm, 1 perímetro de 0,45 mm

INFILL = 0.08   # gyroid 8 % en las zonas macizas del fuselaje (asientos, bridas)

def printed_mass(nm, solid=False):
    g = D["glob"][nm]
    if nm.startswith(("AD", "AT")):        # alas modeladas huecas (piel + celosía): el volumen es material real
        return g["vol"]*RHO_LW
    shell = min(g["vol"], g["area"]*T_SHELL)
    return (shell + INFILL*max(0.0, g["vol"] - shell))*RHO_LW

items = []   # (nombre, masa g, X mm)
for nm, g in D["glob"].items():
    if nm.startswith("EL"):   # elevones recomendados en balsa 3 mm (0,15 g/cm3)
        items.append((nm.replace("EL", "Elevón balsa"), g["vol"]*0.15, g["cg"][0])); continue
    items.append((nm, printed_mass(nm), g["cg"][0]))
# winglets y bandeja (no están en montaje global)
xw = G.X_LE_R + G.C_R - 40
items += [("Winglets x2 (Depron 3 mm)", 2*D["parts"]["WINGLET_x2"]["vol"]*1.5*0.04, xw)]
comp = [("Motor 1404 3800-4600 kV", 9.0, -10), ("Hélice 4\" (plegable o bipala)", 2.5, -22),
        ("ESC 20 A (BLHeli_S/AM32)", 5.0, 25), ("FC ala (F405 Wing mini) ", 7.0, 150),
        ("Receptor + antena", 1.5, 185), ("Servo 3,7 g izq", 4.0, 322), ("Servo 3,7 g der", 4.0, 322),
        ("Varillas 0,8 mm + horns", 2.5, 400),
        ("Larguero ppal. del. tubo C 4x3x600", 5.1, G.X_LE_F + 0.25*G.C_F),
        ("Larguero ppal. tras. tubo C 4x3x600", 5.1, G.X_LE_R + 0.25*G.C_R),
        ("Larguero sec. del. varilla C 2x600", 2.9, G.X_LE_F + 0.5*G.C_F),
        ("Larguero sec. tras. varilla C 2x600", 2.9, G.X_LE_R + 0.5*G.C_R),
        ("Pines centrado C 2x6 (4)", 0.2, 250),
        ("Larguerillos fuselaje C 2x353 (4)", 4*1.72, (G.STR_X0 + G.STR_X1)/2),
        ("Pasadores C 2 mm (4) + gomas", 4.0, 280), ("Cables, XT30, cola, cinta", 10.0, 190)]
items += comp
BAT = ("Batería 2S 450 mAh", 28.0)

S_f, S_r = G.B*G.C_F/1e4, G.B*G.C_R/1e4   # dm2
AR_f, AR_r = G.B**2/(G.B*G.C_F), G.B**2/(G.B*G.C_R)
a = lambda AR: 2*np.pi/(1 + 2/AR)
a_f, a_r = a(AR_f), a(AR_r)
deps = 2*a_f/(np.pi*AR_f)*0.85            # gradiente de downwash (factor 0,85 por separación)
x_f, x_r = G.X_LE_F + 0.25*G.C_F, G.X_LE_R + 0.25*G.C_R
np_x = (a_f*S_f*x_f + a_r*S_r*(1-deps)*x_r)/(a_f*S_f + a_r*S_r*(1-deps)) - 1.5   # -1,5 mm fuselaje
c_ref = (S_f*G.C_F + S_r*G.C_R)/(S_f + S_r)
CG = round(np_x - 0.15*c_ref)            # margen estático 15 %

m0 = sum(m for _, m, _ in items); mx0 = sum(m*x for _, m, x in items)
x_bat = (CG*(m0 + BAT[1]) - mx0)/BAT[1]
M = m0 + BAT[1]
S = S_f + S_r
Wl = M/S
rho = 1.225
V = lambda CL: np.sqrt(2*M/1000*9.81/(rho*S/100*CL))
res = dict(items=[(n, round(m, 1), round(x)) for n, m, x in items] + [(BAT[0], BAT[1], round(x_bat))],
           airframe=round(sum(m for n, m, _ in items if n[:2] in ("F1", "F2", "F3", "F4", "AD", "AT", "EL", "Wi", "Ba")), 1),
           M=round(M), S=round(S, 2), Wl=round(Wl, 1), NP=round(np_x), CG=CG, c_ref=round(c_ref, 1),
           deps=round(deps, 3), x_bat=round(x_bat), Vstall=round(V(0.9), 1), Vcruise=round(V(0.45), 1),
           Re=round(V(0.45)*c_ref/1000/1.5e-5, -3), AR=[round(AR_f, 2), round(AR_r, 2)])
json.dump(res, open(os.path.join(G.OUT, "mass.json"), "w"), indent=1, ensure_ascii=False)
for n, m, x in res["items"]: print(f"{n:36s} {m:6.1f} g  X={x}")
print({k: v for k, v in res.items() if k != "items"})
