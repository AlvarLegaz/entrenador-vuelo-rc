"""Planos PDF A4 apaisado (coordenadas de página en mm)."""
import json, pickle, os, numpy as np, matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.backends.backend_pdf import PdfPages
from matplotlib.collections import PolyCollection
from matplotlib.patches import Rectangle, Circle, Polygon
import geom as G

OUT = G.OUT
I = json.load(open(f"{OUT}/info.json")); MS = json.load(open(f"{OUT}/mass.json"))
MESH = pickle.load(open(f"{OUT}/glob_meshes.pkl", "rb"))
W, H = 297, 210
INK, GREY, ACC, BLUE = "#1c1c1c", "#9aa0a6", "#c0392b", "#2c5d8a"

def page(title, scale_txt=""):
    fig = plt.figure(figsize=(W/25.4, H/25.4))
    ax = fig.add_axes([0, 0, 1, 1]); ax.set_xlim(0, W); ax.set_ylim(0, H); ax.axis("off")
    ax.add_patch(Rectangle((8, 8), W-16, H-16, fill=False, lw=0.8, ec=INK))
    ax.add_patch(Rectangle((8, 8), W-16, 12, fill=False, lw=0.6, ec=INK))
    ax.text(12, 14, title, fontsize=10, weight="bold", va="center", color=INK)
    ax.text(W-12, 14, f"Avión tándem ALFA-T · v2 · {scale_txt} · cotas en mm", fontsize=7.5, va="center", ha="right", color=INK)
    return fig, ax

def proj(ax, keys, f, fc, ec=INK, lw=0.15, z=1):
    for k in keys:
        v, t = MESH[k]
        P = f(v)[t]
        ax.add_collection(PolyCollection(P, facecolors=fc, edgecolors="none", zorder=z, rasterized=True))
    # contorno aproximado: bordes de triángulos proyectados no se dibujan (demasiados); usamos relleno

def dim(ax, p0, p1, off, txt, horiz=True, fs=6.5, col=BLUE):
    (x0, y0), (x1, y1) = p0, p1
    if horiz:
        y = y0 + off
        ax.plot([x0, x0], [y0, y], lw=0.3, c=col); ax.plot([x1, x1], [y1, y], lw=0.3, c=col)
        ax.annotate("", (x0, y), (x1, y), arrowprops=dict(arrowstyle="<->", lw=0.4, color=col, shrinkA=0, shrinkB=0))
        ax.text((x0+x1)/2, y + (1.2 if off >= 0 else -1.2), txt, fontsize=fs, ha="center", va="bottom" if off >= 0 else "top", color=col)
    else:
        x = x0 + off
        ax.plot([x0, x], [y0, y0], lw=0.3, c=col); ax.plot([x1, x], [y1, y1], lw=0.3, c=col)
        ax.annotate("", (x, y0), (x, y1), arrowprops=dict(arrowstyle="<->", lw=0.4, color=col, shrinkA=0, shrinkB=0))
        ax.text(x + (1.2 if off >= 0 else -1.2), (y0+y1)/2, txt, fontsize=fs, ha="left" if off >= 0 else "right", va="center", rotation=90, color=col)

FUS = [k for k in MESH if k[0] == "F"]; WF = [k for k in MESH if k.startswith("AD")]
WR = [k for k in MESH if k.startswith("AT")]; EL = [k for k in MESH if k.startswith("EL")]
CG = MS["CG"]; L = G.L
xLEf, xLEr, cf, cr = G.X_LE_F, G.X_LE_R, G.C_F, G.C_R

def cg_mark(ax, x, y, r=2.2):
    ax.add_patch(Circle((x, y), r, fc="white", ec=ACC, lw=0.8, zorder=9))
    ax.add_patch(Polygon([(x, y), (x+r, y), (x+r*np.cos(np.pi/2), y+r)], fc=ACC, ec="none", zorder=10))
    ax.add_patch(Polygon([(x, y), (x-r, y), (x, y-r)], fc=ACC, ec="none", zorder=10))

pdf = PdfPages(f"{OUT}/ALFA-T_planos.pdf")

# ---------------- Página 1: vista general 1:4 ----------------
fig, ax = page("1 · Vista general", "escala 1:5 (A4 al 100 %)")
s = 0.2
# planta: morro a la izquierda, envergadura vertical
ox, oy = 30, 112
f_top = lambda v: np.c_[ox + s*v[:, 0], oy + s*v[:, 1]]
proj(ax, WF + WR, f_top, "#d9dde2"); proj(ax, EL, f_top, "#f0c89a", z=2); proj(ax, FUS, f_top, "#9fb3c8", z=3)
ax.text(ox, oy+72, "PLANTA", fontsize=8, weight="bold")
ax.plot([ox - 22*s, ox], [oy, oy], c=INK, lw=0.6); ax.plot([ox-22*s]*2, [oy-50.8*s, oy+50.8*s], c=INK, lw=1.0)
dim(ax, (ox, oy-75*s-4), (ox+L*s, oy-75*s-4), 0, f"{L:.0f} (fuselaje)")
dim(ax, (ox+xLEf*s, oy+300*s), (ox+xLEr*s, oy+300*s), 4, f"{xLEr-xLEf:.0f} (BA-BA)")
dim(ax, (ox+(xLEr+cr)*s, oy-300*s), (ox+(xLEr+cr)*s, oy+300*s), 6, "600", horiz=False)
dim(ax, (ox+xLEf*s, oy-300*s), (ox+(xLEf+cf)*s, oy-300*s), -3, f"{cf:.0f}")
dim(ax, (ox+xLEr*s, oy-300*s), (ox+(xLEr+cr)*s, oy-300*s), -3, f"{cr:.0f}")
dim(ax, (ox, oy+300*s), (ox+xLEf*s, oy+300*s), 4, f"{xLEf:.0f}")
cg_mark(ax, ox+CG*s, oy); ax.text(ox+CG*s, oy-5, f"CG {CG}", fontsize=6.5, color=ACC, ha="center", va="top")
# alzado lateral
ox2, oy2 = 170, 168
f_side = lambda v: np.c_[ox2 + s*v[:, 0], oy2 + s*v[:, 2]]
proj(ax, WF + WR, f_side, "#d9dde2", z=4); proj(ax, EL, f_side, "#f0c89a", z=5); proj(ax, FUS, f_side, "#9fb3c8", z=3)
ax.plot([ox2-8*s, ox2], [oy2, oy2], c=INK, lw=2.5); ax.plot([ox2-22*s]*2, [oy2-50.8*s, oy2+50.8*s], c=INK, lw=1.0)
ax.text(ox2, oy2+22, "ALZADO LATERAL", fontsize=8, weight="bold")
dim(ax, (ox2-22*s, oy2+50.8*s), (ox2+L*s, oy2+50.8*s), 3, f"≈{L+22:.0f} total con hélice")
dim(ax, (ox2+L*s, oy2-25*s), (ox2+L*s, oy2+25*s), 3, "Ø50", horiz=False)
cg_mark(ax, ox2+CG*s, oy2)
ax.text(ox2+130*s, oy2-13, "ala delantera bajo el fuselaje, calado +2°", fontsize=6, ha="center")
ax.text(ox2+410*s, oy2+10, "ala trasera sobre el fuselaje, calado 0°", fontsize=6, ha="center")
# vista frontal
ox3, oy3 = 218, 112
f_front = lambda v: np.c_[ox3 + s*v[:, 1], oy3 + s*v[:, 2]]
proj(ax, FUS, f_front, "#9fb3c8", z=6); proj(ax, WR, f_front, "#d9dde2", z=2); proj(ax, WF, f_front, "#c5cad0", z=7)
ax.add_patch(Circle((ox3, oy3), 50.8*s, fill=False, ec=INK, lw=0.4, ls="--", zorder=8))
ax.text(ox3-60, oy3+16, "VISTA FRONTAL", fontsize=8, weight="bold")
dim(ax, (ox3-300*s, oy3-8), (ox3+300*s, oy3-8), -3, "600")
ax.text(ox3, oy3-20, "Hélice 4\" (Ø102): sobresale 26 mm bajo el fuselaje →\naterriza con motor parado o usa hélice plegable", fontsize=6, ha="center", va="top")
# datos
tx, ty = 160, 72
lines = [f"Peso estimado en vuelo: {MS['M']} g (estructura impresa {MS['airframe']:.0f} g)",
         f"Superficie alar total: {MS['S']} dm²  ·  carga alar {MS['Wl']} g/dm²",
         f"Punto neutro estimado: X = {MS['NP']} mm  ·  CG = {CG} mm (margen 15 %)",
         f"Pérdida ≈ {MS['Vstall']} m/s  ·  crucero ≈ {MS['Vcruise']}–11 m/s  ·  Re ≈ {MS['Re']/1000:.0f}k",
         "Perfil NACA 3407 en ambas alas · alargamiento 7,1 / 6,3",
         "X medido desde la cara frontal del soporte motor (morro)"]
for i, t in enumerate(lines): ax.text(tx, ty - i*4.6, t, fontsize=7)
pdf.savefig(fig); plt.close(fig)

# ---------------- Página 2: implantación de equipos 1:2 ----------------
fig, ax = page("2 · Fuselaje e implantación de equipos (servos, receptor, FC, batería)", "escala 1:2 (A4 al 100 %)")
s = 0.5; ox, oy = 30, 150
f_side = lambda v: np.c_[ox + s*v[:, 0], oy + s*v[:, 2]]
proj(ax, FUS, f_side, "#dde5ee", z=1)
proj(ax, [k for k in WF+WR+EL if k.endswith("der")], f_side, "#eeeeee", z=0)
X = lambda x: ox + s*x; Z = lambda z: oy + s*z
def box(x0, x1, z0, z1, col, lab, lx=None, lz=None, ha="center"):
    ax.add_patch(Rectangle((X(x0), Z(z0)), s*(x1-x0), s*(z1-z0), fc=col, ec=INK, lw=0.4, zorder=5))
    if lab:
        ax.annotate(lab, ((X(x0)+X(x1))/2, (Z(z0)+Z(z1))/2), (X(lx if lx is not None else (x0+x1)/2), Z(lz)),
                    fontsize=6.3, ha=ha, arrowprops=dict(arrowstyle="-", lw=0.3, color=INK), zorder=11)
box(-15, 0, -9, 9, "#777", "Motor 1404", -14, 62)
ax.plot([X(-22)]*2, [Z(-50.8), Z(50.8)], c=INK, lw=1.2)
box(20, 60, 8, 9.5, "#bbbbbb", None); box(20, 88, -18.5, -17, "#bbbbbb", None)
box(22, 52, 9.5, 14.5, "#6fa8dc", "ESC 20 A sobre el ESTANTE de F1 (velcro)", 75, 44)
xb = MS["x_bat"]
box(xb-29, xb+29, -17, -4, "#f6b26b", f"Batería 2S 450 mAh sobre el SUELO de F1\n(velcro por las ranuras; centro X≈{xb}, ajusta para el CG)", 30, -62)
box(G.FLOOR_X0, G.FLOOR_X1, -11.2, -10, "#bbbbbb", None)
box(122, 169, -10, 4, "#93c47d", "receptor FS-A6 (o FC INAV + receptor nano)\nsobre el SUELO de F2 con velcro", 205, -62)
ax.plot([X(G.ANT_X)]*2, [Z(4), Z(58)], c="#8e7cc3", lw=0.8, zorder=6); ax.text(X(G.ANT_X+2), Z(56), "antena por Ø3,2 superior (F2)", fontsize=6)
sx0 = G.SERVO_WIN[0][0]
box(sx0, sx0 + G.SERVO_L, 0.5, 9.5, "#e06666", "2 servos 3,7 g en ventanas laterales de F3,\nencajados entre GUÍAS impresas (arriba/abajo)", 300, 44)
for zz in (10.1, -0.1):
    ax.plot([X(sx0), X(sx0 + G.SERVO_L), X(sx0 + G.SERVO_L + 18)], [Z(zz)]*3, c=INK, lw=1.0, zorder=7)
ax.plot([X(sx0 + 12), X(442)], [Z(5), Z(26.5)], c=INK, lw=0.7, ls="--", zorder=7)
ax.text(X(392), Z(22), "varilla 0,8 mm → horn bajo elevón", fontsize=6, rotation=8.5, ha="center")
for (yy, zz) in G.stringer_pos():
    if yy > 0: ax.plot([X(G.STR_X0), X(G.STR_X1)], [Z(zz)]*2, c="#555", lw=0.9, ls=(0, (6, 2)), zorder=4)
ax.text(X(400), Z(17.5), "larguerillos C Ø2", fontsize=5.6, color="#555")
for xd, zd in [(xLEf-6, 11), (xLEf+cf+6, 11), (xLEr-6, 20), (xLEr+cr+6, 20)]:
    ax.add_patch(Circle((X(xd), Z(zd)), 1.3, fc="white", ec=INK, lw=0.5, zorder=8))
ax.text(X(232), Z(-36), "pasadores C Ø2 × 60 + gomas", fontsize=6, ha="center")
for a, b in G.SEG[1:]:
    ax.plot([X(a)]*2, [Z(-25), Z(25)], c=INK, lw=0.4, ls=(0, (3, 2)), zorder=6)
for i, (a, b) in enumerate(G.SEG):
    ax.text(X((a+b)/2), Z(31) if i != 3 else Z(38), f"F{i+1}", fontsize=8, weight="bold", ha="center", color=BLUE)
    dim(ax, (X(a), Z(-25)), (X(b), Z(-25)), -38 + (4 if i % 2 else 0), f"{b-a:.0f}")
cg_mark(ax, X(CG), Z(0), 2.8); ax.text(X(CG), Z(-16), f"CG {CG}", color=ACC, fontsize=7, ha="center")
dim(ax, (X(0), Z(25)), (X(CG), Z(25)), 34, f"{CG} (CG)")
ax.text(14, 84, (
    "• ANCLAJES IMPRESOS (forman parte de las piezas):\n"
    "  F1: SUELO de batería (Z −17, 4 ranuras para cinta velcro de 10 mm) y ESTANTE del ESC (Z +8, 2 ranuras), ambos nacen de la placa motor.\n"
    "  F2: SUELO del receptor / FC (Z −10, X 114–200, 4 ranuras). F3: GUÍAS de servo; el servo entra por la ventana lateral y queda entre dos placas.\n"
    "• UNIONES: F1 entra a presión en el cuello de F2 (desmontable) con 2 CHAVETAS internas de 3 y 5 mm que encajan en muescas del cuello.\n"
    "  F2|F3 y F3|F4: BRIDAS pegadas cara con cara, 3 TETONES Ø3 en alojamientos y los 4 LARGUERILLOS Ø2 × 350 de F2 a F4 atravesándolas.\n"
    "• Sin INAV (FS-A6): batería → ESC en F1; del ESC sale un cable de servo al canal 3 del A6 en F2. Servos con alargador de 15 cm.\n"
    "• Ventanas de servo 20,6 × 9 mm (X 312–333). Si tus servos miden otra cosa, cambia SERVO_L / SERVO_W en geom.py y regenera."),
    fontsize=6.4, va="top", linespacing=1.45)
# --- recorrido de cables en el alzado ---
def wire(pts, col, lab=None, lpos=None):
    ax.plot([X(p[0]) for p in pts], [Z(p[1]) for p in pts], c=col, lw=1.0, zorder=9, solid_capstyle="round")
    if lab: ax.text(X(lpos[0]), Z(lpos[1]), lab, fontsize=5.8, color=col, zorder=12)
wire([(-3, 3), (5, 3), (15, 1)], "#b45f06", "3 fases motor", (-12, 12))
wire([(52, 12), (64, 6), (118, 6), (124, 0)], "#cc0000", "ESC → receptor (canal 3, BEC)", (66, 15))
wire([(MS["x_bat"]-20, -4), (35, 9.5)], "#38761d", "batería → ESC", (40, -2))
wire([(169, 0), (240, 0), (sx0 + 4, 3)], "#990000", "alargadores de servo", (250, 2.5))


pdf.savefig(fig); plt.close(fig)

# ---------------- Página 2b: secciones y detalles 1:1 ----------------
fig, ax = page("2b · Detalles: fijación de alas, mando de elevones y cableado", "escala 1:1 (A4 al 100 %)")
def base_sect(cx, cy, top):
    ax.add_patch(Circle((cx, cy), 25, fc="#dde5ee", ec=INK, lw=0.6, zorder=2))
    ax.add_patch(Circle((cx, cy), 24.2, fc="white", ec=INK, lw=0.3, zorder=3))
    sg = 1 if top else -1
    y0 = cy + (6 if top else -27.2)
    ax.add_patch(Rectangle((cx-G.SEAT_HALF, y0), 2*G.SEAT_HALF, 21.2, fc="#dde5ee", ec=INK, lw=0.4, zorder=1))
    wz = cy + sg*(27.2 + 3.2)
    return sg, wz
# A-A
cx, cy = 70, 132
ax.text(18, 172, "SECCIÓN A-A · ala delantera (vista desde el morro)", fontsize=7.5, weight="bold")
sg, wz = base_sect(cx, cy, False)
ax.add_patch(Rectangle((cx-48, wz-3), 96, 6, fc="#d9dde2", ec=INK, lw=0.5, zorder=4))
ax.text(cx+30, wz, "ala delantera", fontsize=5.5, va="center", zorder=9)
dz = cy + 11
ax.plot([cx-32, cx+32], [dz, dz], c=INK, lw=2, zorder=6)
for sx in (-1, 1):
    ax.plot([cx+sx*31, cx+sx*36, cx+sx*40, cx+sx*42], [dz, dz-20, wz-3.2, wz-3.2], c="#8a5a00", lw=0.8, zorder=7)
ax.plot([cx-42, cx+42], [wz-3.2]*2, c="#8a5a00", lw=0.8, zorder=7)
ax.text(cx+34, dz+2, "pasador de carbono Ø2 × 60 (pasa por F2, Z=+11)", fontsize=5.8)
ax.text(18, wz-7, "goma: pasador delantero → por debajo del ala → pasador trasero (2 gomas por ala,\ncruzadas en X). El asiento copia el extradós con +2° de calado, y 2 pines de\ncarbono Ø2 × 6 mm (a ±12 mm del centro, 15 % de cuerda) pegados en el asiento\nentran en agujeros ciegos del ala: no puede resbalar ni girar. En un golpe la\ngoma cede y el ala se suelta sin romper el fuselaje.", fontsize=5.8, va="top")
for px in (-12, 12): ax.plot([cx+px]*2, [wz+3-2.5, wz+3+3.5], c=BLUE, lw=2.2, zorder=9)
ax.text(cx, wz+9, "pines Ø2", fontsize=5.5, color=BLUE, ha="center", zorder=9)
ax.text(cx, cy-4, "receptor sobre\nel suelo de F2", fontsize=5.5, ha="center", va="center", color="#38761d", zorder=8)
for (yy, zz) in G.stringer_pos(): ax.add_patch(Circle((cx+yy, cy+zz), 1.0, fc=INK, zorder=8))
# B-B
cx, cy = 215, 128
ax.text(160, 172, "SECCIÓN B-B · mando de elevones (vista desde atrás)", fontsize=7.5, weight="bold")
sg, wz = base_sect(cx, cy, True)
ax.add_patch(Rectangle((cx-70, wz-3.2), 140, 6.4, fc="#d9dde2", ec=INK, lw=0.5, zorder=4))
ax.add_patch(Rectangle((cx+26, wz-1.7), 44, 3.4, fc="#f0c89a", ec=INK, lw=0.5, zorder=5))
ax.add_patch(Rectangle((cx-70, wz-1.7), 44, 3.4, fc="#f0c89a", ec=INK, lw=0.5, zorder=5))
ax.text(cx+48, wz+5, "elevón der. (balsa)", fontsize=5.8, ha="center")
for sx in (-1, 1):   # servos en la ventana (proyectados, están en F3 más adelante)
    ax.add_patch(Rectangle((cx+sx*25 - (18 if sx > 0 else 0), cy+0.5), 18, 9, fc="#e06666", ec=INK, lw=0.4, zorder=6, alpha=0.8))
    ax.plot([cx+sx*25, cx+sx*29], [cy+5]*2, c=INK, lw=1.6, zorder=7)          # eje + brazo
    ax.plot([cx+sx*29, cx+sx*27, cx+sx*41], [cy+5, cy+12, wz-3.2-4], c=INK, lw=0.6, ls="--", zorder=7)
    ax.plot([cx+sx*41]*2, [wz-1.7, wz-1.7-4], c=INK, lw=1.4, zorder=7)       # horn
ax.text(cx, cy-10, "servos 3,7 g en las ventanas laterales de F3\n(dibujados proyectados; eje hacia fuera)", fontsize=5.6, va="top", ha="center", zorder=9)
for (yy, zz) in G.stringer_pos(): ax.add_patch(Circle((cx+yy, cy+zz), 1.0, fc=INK, zorder=8))
ax.text(160, 88, "varilla 0,8 mm (≈120 mm) desde el brazo del servo, por el\ncostado del fuselaje, hasta el horn bajo el elevón a 15 mm de\nsu raíz. Bisagra: cinta por el extradós. Nada de cables entra\nen las alas: se desmontan quitando dos gomas.", fontsize=5.8, va="top")
# Cableado
ax.text(18, 60, "CABLEADO (todo por dentro del tubo)", fontsize=7.5, weight="bold")
cab = ["Motor → ESC: 3 cables cortos por el agujero Ø5 de la placa motor; ESC sobre el estante de F1, junto a los respiraderos.",
       "Batería → ESC (XT30) dentro de F1. Con INAV: batería → FC en F2 y la FC alimenta el ESC.",
       "ESC → receptor: cable de servo de ≈12 cm por el techo del tubo hasta el canal 3 del A6 (alimenta el receptor por BEC).",
       "Servos → receptor: alargadores de 15 cm por el hueco central (Ø37) de las bridas F2|F3.",
       "Antena del receptor: por el Ø3,2 del techo de F2, en vertical.",
       "Al quitar el morro solo se desenchufa el cable del canal 3 (y la batería, si la cambias); el resto queda dentro."]
for i, t in enumerate(cab): ax.text(18, 54 - i*4.8, "• " + t, fontsize=6.4)
# DETALLE C: chavetas antigiro (escala 3:4)
sc = 0.75
ax.text(176, 69, "DETALLE C · chavetas antigiro (escala 3:4, vista desde el morro)", fontsize=7, weight="bold")
for cx0, ttl in [(200, "junta F1|F2"), (252, "juntas F2|F3 y F3|F4")]:
    cy0 = 44
    ax.add_patch(Circle((cx0, cy0), 25*sc, fc="#dde5ee", ec=INK, lw=0.5, zorder=2))
    ax.add_patch(Circle((cx0, cy0), 24.2*sc, fc="white", ec=INK, lw=0.3, zorder=3))
    ax.text(cx0, cy0 - 22, ttl, fontsize=6, ha="center")
    if cx0 == 200:
        ax.add_patch(Circle((cx0, cy0), 24.1*sc, fc="none", ec="#2c5d8a", lw=0.6, zorder=4))
        ax.add_patch(Circle((cx0, cy0), 23.3*sc, fc="none", ec="#2c5d8a", lw=0.6, zorder=4))
        for ang, w in G.KEY_F1:
            y, z = G.polar(ang, (G.KEY_R0 + G.KEY_R1)/2*sc)
            ax.add_patch(Rectangle((cx0 + y - (G.KEY_R1 - G.KEY_R0)*sc/2, cy0 + z - w*sc/2), (G.KEY_R1 - G.KEY_R0)*sc, w*sc, fc=ACC, ec=INK, lw=0.3, zorder=5))
            ax.text(cx0 + y*0.7, cy0 + z*0.7 + 2.5, f"{w:.0f} mm", fontsize=5.5, ha="center", color=ACC)
        ax.text(cx0, cy0 - 3, "chavetas en F1,\nmuescas en el\ncuello de F2", fontsize=5.2, ha="center", va="center")
    else:
        ax.add_patch(matplotlib.patches.Wedge((cx0, cy0), 24.2*sc, 0, 360, width=(24.2 - G.FL_RIN)*sc, fc="#c9d3df", ec="none", zorder=3))
        for (y, z) in G.stringer_pos(): ax.add_patch(Circle((cx0 + y*sc, cy0 + z*sc), 1.15*sc, fc=INK, zorder=6))
        for ang in G.STUD_ANG:
            y, z = G.polar(ang, G.STUD_RC); ax.add_patch(Circle((cx0 + y*sc, cy0 + z*sc), G.STUD_R*sc, fc=ACC, ec=INK, lw=0.3, zorder=6))
        ax.text(cx0, cy0, "tetones Ø3 × 2,5 (rojo)\nlarguerillos Ø2 (negro)", fontsize=5.0, ha="center", va="center")

pdf.savefig(fig); plt.close(fig)

# ---------------- Página 2c: estructura interna ----------------
fig, ax = page("2c · Estructura interna tipo cohete: larguerillos, cuadernas, anillos y celosía de las alas", "sin escala")
img = plt.imread("ALFA-T_estructura.png")
hh, ww = img.shape[:2]; wmm = 277; hmm_ = wmm*hh/ww
if hmm_ > 150: hmm_ = 150; wmm = hmm_*ww/hh
ax.imshow(img, extent=(10 + (277 - wmm)/2, 10 + (277 - wmm)/2 + wmm, 42, 42 + hmm_), zorder=2)
ax.text(14, 38, (
    "FUSELAJE: 4 larguerillos de carbono Ø2 × 350 mm (a 45°, 135°, 225° y 315°) en vainas impresas de F2 a F4: absorben la flexión y atraviesan\n"
    "las juntas, que ya no dependen solo del pegamento. Bridas planas de 1,2 mm con chaflán de 45° en cada junta (cuadernas de unión, hueco Ø37\n"
    "para cables) con 3 tetones antigiro, chavetas en la junta del morro y anillos interiores triangulares cada 70–80 mm. Sin soportes.\n"
    "ALAS: piel de 0,45 mm, celosía diagonal ±45° (como el isogrid de un cohete), vainas alrededor de los 2 largueros y tapas de 0,6 mm en los\n"
    "extremos (dan base de impresión y superficie de pegado). Los tramos son de 100 mm para que no oscilen al imprimirse de pie."),
    fontsize=6.6, va="top", linespacing=1.5)
pdf.savefig(fig); plt.close(fig)

# ---------------- Página 3: perfiles 1:1 ----------------
fig, ax = page("3 · Perfil NACA 3407 y plantillas a tamaño real", "escala 1:1 — imprime SIN ajustar a página")
ax.plot([20, 120], [192, 192], c=INK, lw=1); [ax.plot([x]*2, [190.5, 193.5], c=INK, lw=0.6) for x in (20, 70, 120)]
ax.text(70, 194.5, "control: 100 mm", fontsize=6.5, ha="center")
def airfoil(ox, oy, c, name, hinge=False):
    up = np.c_[G.XU, G.YU]*c; lo = np.c_[G.XL, G.YL]*c
    ax.fill(np.r_[up[:, 0], lo[::-1, 0]] + ox, np.r_[up[:, 1], lo[::-1, 1]] + oy, fc="#eef2f6", ec=INK, lw=0.6)
    ax.plot(G.XC*c + ox, G.YC*c + oy, c=GREY, lw=0.3, ls="--")
    ax.plot([ox, ox+c], [oy, oy], c=GREY, lw=0.3)
    xs, ys = 0.25*c, G.camber_at(0.25)*c
    ax.add_patch(Circle((ox+xs, oy+ys), G.SPAR_D/2, fc="white", ec=ACC, lw=0.6))
    ax.text(ox+xs, oy-6, f"larguero ppal. Ø{G.SPAR_D:.1f} a {xs:.2f} mm (tubo 4×3)", fontsize=6, ha="center", color=ACC)
    x2, y2 = G.SPAR2_X*c, G.camber_at(G.SPAR2_X)*c
    hh = G.SPAR2_SLOT if not hinge else 0
    ax.add_patch(matplotlib.patches.FancyBboxPatch((ox+x2-G.SPAR2_D/2, oy+y2-G.SPAR2_D/2-hh/2), G.SPAR2_D, G.SPAR2_D+hh,
                 boxstyle=f"round,pad=0,rounding_size={G.SPAR2_D/2}", fc="white", ec=ACC, lw=0.6))
    ax.text(ox+x2+8, oy-6, f"secundario Ø2,2{' (ranura 2,9 alto)' if hh else ''} a {x2:.1f} mm (varilla 2)", fontsize=6, color=ACC)
    xp = G.PIN_U*c; yp = np.interp(G.PIN_U, G.XU if not hinge else G.XL, G.YU if not hinge else G.YL)*c
    ax.plot([ox+xp]*2, [oy+yp, oy+yp+(-2.5 if not hinge else 2.5)], c=BLUE, lw=1.6)
    ax.text(ox+xp-1.5, oy+yp+(1 if not hinge else -2.5), "pin", fontsize=5.5, color=BLUE, ha="right")
    t = np.interp(0.3, G.XU, G.YU) - np.interp(0.3, G.XL, G.YL)
    ax.text(ox, oy+10, f"{name} — cuerda {c:.0f} mm · espesor máx. {0.07*c:.2f} mm (7 %) al 30 % · curvatura 3 % al 40 %", fontsize=7, weight="bold")
    if hinge:
        xh = G.HINGE*c
        for xx in (xh, xh+G.GAP):
            yu, yl = np.interp(xx/c, G.XU, G.YU)*c, np.interp(xx/c, G.XL, G.YL)*c
            ax.plot([ox+xx]*2, [oy+yl, oy+yu], c=ACC, lw=0.6)
        ax.text(ox+xh+2, oy+6, f"bisagra a {xh:.2f} mm (75 %) · elevón {c-xh-G.GAP:.1f} mm", fontsize=6, color=ACC)
airfoil(20, 160, cf, "ALA DELANTERA")
airfoil(20, 125, cr, "ALA TRASERA", hinge=True)
# winglet
wx, wy = 195, 30
ax.add_patch(Polygon([(wx, wy), (wx+80, wy), (wx+80, wy+75), (wx+30, wy+75)], fc="#eef2f6", ec=INK, lw=0.6))
ax.text(wx, wy+80, "WINGLET ×2 · Depron 3 mm (o WINGLET_x2.stl)", fontsize=7, weight="bold")
ax.plot([wx, wx+80], [wy+12, wy+12], c=ACC, lw=0.4, ls="--"); ax.text(wx+2, wy+14, "línea del ala (extradós arriba)", fontsize=5.8, va="center", color=ACC)
ax.text(wx+40, wy-4, "80 (raíz, borde de fuga alineado con el del ala)", fontsize=6, ha="center")
ax.text(wx+55, wy+77, "50", fontsize=6, ha="center"); ax.text(wx+83, wy+60, "75", fontsize=6)
# tabla de coordenadas (selección)
ax.text(20, 102, "Coordenadas NACA 3407 (x/c, y/c) — fichero completo: NACA3407.dat (formato Selig, XFLR5/Fusion)", fontsize=7, weight="bold")
xs = np.array([0, .0125, .025, .05, .075, .1, .15, .2, .25, .3, .4, .5, .6, .7, .8, .9, .95, 1])
yu = np.interp(xs, G.XU, G.YU); yl = np.interp(xs, G.XL, G.YL)
cols = [("x/c", xs), ("y sup", yu), ("y inf", yl)]
for j in range(len(xs)):
    col, row = divmod(j, 9)
    x0 = 20 + col*60; y0 = 95 - row*4.6
    ax.text(x0, y0, f"{xs[j]:.4f}   {yu[j]:+.4f}   {yl[j]:+.4f}", fontsize=6.3, family="monospace")
for col in range(2): ax.text(20 + col*60, 99, "x/c        sup        inf", fontsize=6.3, family="monospace", color=BLUE)
ax.text(20, 45, ("Calados: delantera +2°, trasera 0° respecto al eje del fuselaje (decalaje 2°; ya integrados en los asientos de F2 y F4).\n"
                 "Ala delantera con torsión negativa lineal: 0° en raíz → −1,5° en punta (integrada en los STL AD_*).\n"
                 "Sin diedro: la estabilidad lateral la dan los winglets y la FC (INAV)."), fontsize=6.4, va="top", linespacing=1.45)
pdf.savefig(fig); plt.close(fig)

# ---------------- Página 4: piezas, impresión, pesos, montaje ----------------
fig, ax = page("4 · Piezas, impresión, pesos y montaje", "")
P = I["parts"]
rows = [("F1_morro_motor", "1", "placa motor en la cama"), ("F2_central_ala_del", "1", "brida trasera en la cama"),
        ("F3_central", "1", "brida trasera en la cama"), ("F4_cola_ala_tras", "1", "tapa de cola en la cama"),
        ("AD1/AD2/AD3 _der e _izq", "3+3", "de pie, 100 mm, tapa en la cama"),
        ("AT1/AT2/AT3 _der e _izq", "3+3", "de pie, 100 mm, tapa en la cama"),
        ("ELEVON_x4", "4", "tumbado (mejor balsa 3 mm)"), ("WINGLET_x2", "2", "opcional: mejor Depron 3 mm")]
keys = ["F1_morro_motor", "F2_central_ala_del", "F3_central", "F4_cola_ala_tras", "AD1_der", "AT1_der", "ELEVON_x4", "WINGLET_x2"]
ax.text(14, 196, "PIEZAS (la mayor mide 160 mm: caben en cualquier Kobra/Vyper)", fontsize=7.5, weight="bold")
for i, ((n, q, o), key) in enumerate(zip(rows, keys)):
    sz = P[key]["size"]
    ax.text(14, 190 - i*4.3, f"{n:26s}{q:>4s}  {sz[0]:5.0f}×{sz[1]:4.0f}×{sz[2]:4.0f}  {o}", fontsize=6.0, family="monospace")
ax.text(14, 152, "IMPRESIÓN (LW-PLA espumado; con PLA normal pesa ~1,8× más)", fontsize=7.5, weight="bold")
pr = ["Cama: limpia + laca o pegamento de barra; borde (brim) de 8 mm; 1.ª capa lenta (20 mm/s);",
      "  sin ventilador en las 3 primeras capas. Alas a 30–40 mm/s y aceleración baja (≤1000 mm/s²).",
      "Fuselaje: 2 perímetros, gyroid 8 % (solo rellena asientos y bridas), 3 capas sup./inf.",
      "Alas: 1 perímetro, relleno 0 %, 3 capas sup./inf. Generador de paredes Arachne (por defecto",
      "  en Anycubic Slicer Next/Orca/Cura 5) para que la piel y la celosía salgan en una sola línea.",
      "Ninguna pieza necesita soportes. Repasa los agujeros con broca de 4,2 / 2,3 / 2,2 mm."]
for i, t in enumerate(pr): ax.text(14, 146 - i*4.3, t, fontsize=6.2)
ax.text(14, 116, "MONTAJE", fontsize=7.5, weight="bold")
st = ["1. Presenta F2+F3+F4 con los 4 larguerillos Ø2 × 350 metidos desde el morro de F2: así quedan",
      "   alineados los asientos. Pega las bridas cara con cara (CA medio o epoxi 5 min) y fija los",
      "   larguerillos con una gota de CA en cada brida. Los 3 tetones solo entran en una posición.",
      "   F1 entra a presión con sus 2 chavetas (3 y 5 mm) en las muescas del cuello de F2.",
      "2. Cada ala: tubo C 4×3×600 + varilla C 2×600 por sus 6 tramos; CA en las tapas de unión.",
      "3. Elevones de balsa 3 mm × 23 mm en cuña; bisagra de cinta por el extradós.",
      "4. Winglets en las puntas del ala trasera. Pines Ø2×6 pegados en los asientos.",
      "5. Servos entre las guías de F3, eje fuera; varilla 0,8 mm al horn de cada elevón.",
      "6. Receptor (o FC) en el suelo de F2 con velcro; antena por el techo de F2.",
      "7. Motor en F1 (M2); ESC en el estante y batería en el suelo de F1, con velcro.",
      "8. Pasadores de 2 mm y 2 gomas cruzadas por ala.",
      f"9. CG a {CG} mm de la placa motor ({CG - xLEf:.0f} mm tras el borde de ataque delantero),",
      "   moviendo la batería. Recorridos: profundidad ±7 mm, alabeo ±6 mm, expo 30 %."]
for i, t in enumerate(st): ax.text(14, 110 - i*4.3, t, fontsize=6.2)
ax.text(160, 196, "PESOS Y POSICIONES (X desde la placa motor)", fontsize=7.5, weight="bold")
agg = {}
for n, m, x in MS["items"]:
    k = ("Fuselaje impreso" if n[:2] in ("F1", "F2", "F3", "F4") else "Ala delantera impresa" if n.startswith("AD")
         else "Ala trasera impresa" if n.startswith("AT") else "Elevones (balsa)" if n.startswith("Elev") else n.strip())
    a = agg.setdefault(k, [0, 0]); a[0] += m; a[1] += m*x
for i, (k, (m, mx)) in enumerate(agg.items()):
    ax.text(160, 190 - i*4.0, f"{k[:32]:33s}{m:6.1f} g  X={mx/m:5.0f}", fontsize=6.0, family="monospace")
y = 190 - len(agg)*4.0 - 2
ax.text(160, y, f"{'TOTAL':33s}{MS['M']:6.0f} g  CG={CG}", fontsize=6.4, family="monospace", weight="bold")
ax.text(160, y-8, ("Las masas impresas son estimaciones (LW-PLA a 0,65 g/cm³). Pesa cada pieza:\n"
                   "si la cola sale más pesada, la batería irá más adelante. Por encima de 250 g\n"
                   "necesitas el certificado A1/A3 de AESA. No vueles con el CG por detrás de\n"
                   "225 mm. Diseño no probado en vuelo: trátalo como prototipo."),
        fontsize=6.2, va="top", color=ACC, linespacing=1.4)
pdf.savefig(fig); plt.close(fig)
pdf.close()
print("ok")
