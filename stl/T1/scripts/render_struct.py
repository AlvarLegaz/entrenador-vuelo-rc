import geom as G, numpy as np, matplotlib; matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.path import Path
from matplotlib.patches import PathPatch
from manifold3d import Manifold

def draw_cs(ax, cs, fc="#9fb3c8", ec="#1c1c1c", lw=0.4):
    polys = cs.to_polygons()
    if not polys: return
    verts, codes = [], []
    for p in polys:
        p = np.asarray(p)
        verts += list(p) + [p[0]]; codes += [Path.MOVETO] + [Path.LINETO]*(len(p)-1) + [Path.CLOSEPOLY]
    ax.add_patch(PathPatch(Path(verts, codes), fc=fc, ec=ec, lw=lw))

def sec_y(m, y):        # corte por el plano Y=y -> polígonos en (X, Z)
    return m.rotate([90, 0, 0]).slice(-y) if False else m.transform([[1,0,0,0],[0,0,1,0],[0,-1,0,0]]).slice(-y)

def sec_x(m, x):        # corte por X=x -> polígonos en (Y, Z)
    return m.transform([[0,1,0,0],[0,0,1,0],[1,0,0,0]]).slice(x)

fus = [G.fuselage_segment(k) for k in range(4)]
fig = plt.figure(figsize=(16, 10), dpi=110)
# 1) corte longitudinal por el plano de dos larguerillos (y = -15.4) e y = 0
ax = fig.add_axes([0.03, 0.55, 0.94, 0.4]); ax.set_aspect("equal"); ax.axis("off")
ys = -G.STR_RC*np.sin(np.radians(45))
cols = ["#c9d3df", "#9fb3c8", "#b8c6d6", "#9fb3c8"]
for m, c in zip(fus, cols):
    draw_cs(ax, sec_y(m, 0.0), fc=c)
for (y, z) in G.stringer_pos():
    ax.plot([G.STR_X0, G.STR_X1], [z, z], c="#222", lw=2.2, alpha=0.85)
for i, (a, b) in enumerate(G.SEG):
    ax.text((a+b)/2, 32 if i != 3 else 40, f"F{i+1}", ha="center", fontsize=11, weight="bold", color="#2c5d8a")
ax.annotate("brida/cuaderna de unión\n(base plana de impresión + cara de pegado)", (250, -20), (215, -62), fontsize=8, arrowprops=dict(arrowstyle="-", lw=0.5))
ax.annotate("anillo 45°", (150, 21.5), (140, 44), fontsize=8, arrowprops=dict(arrowstyle="-", lw=0.5))
ax.annotate("larguerillos de carbono Ø2 × 350 (4)", (380, 15.4), (380, 50), fontsize=8, arrowprops=dict(arrowstyle="-", lw=0.5))
ax.annotate("suelo batería", (40, -17.7), (30, -45), fontsize=8, arrowprops=dict(arrowstyle="-", lw=0.5))
ax.annotate("estante ESC", (30, 8.7), (25, 40), fontsize=8, arrowprops=dict(arrowstyle="-", lw=0.5))
ax.annotate("suelo receptor / FC", (160, -10.6), (175, -50), fontsize=8, arrowprops=dict(arrowstyle="-", lw=0.5))
ax.annotate("cono 45°", (4, 20), (-25, 35), fontsize=8, arrowprops=dict(arrowstyle="-", lw=0.5))
ax.set_xlim(-30, 490); ax.set_ylim(-70, 60)
ax.set_title("Corte longitudinal del fuselaje (plano de simetría); en negro, los larguerillos de carbono", fontsize=11)
# 2) secciones transversales
for j, (x, k, t) in enumerate([(150, 1, "X=150 (F2, anillo + suelo)"), (300, 2, "X=300 (F3, anillo)"), (322, 2, "X=322 (F3, servos)"), (420, 3, "X=420 (F4)")]):
    ax = fig.add_axes([0.03 + j*0.16, 0.08, 0.15, 0.38]); ax.set_aspect("equal"); ax.axis("off")
    draw_cs(ax, sec_x(fus[k], x))
    for (y, z) in G.stringer_pos(): ax.add_patch(plt.Circle((y, z), 1.0, color="#222"))
    ax.set_xlim(-30, 30); ax.set_ylim(-36, 36); ax.set_title(t, fontsize=9)
# 3) ala: corte por la línea media (muestra la celosía) y sección
fs, (us, vs) = G.front_wing_segments(); seg = fs[1]
ax = fig.add_axes([0.66, 0.05, 0.2, 0.44]); ax.set_aspect("equal"); ax.axis("off")
mid = seg.transform([[1,0,0,0],[0,0,1,0],[0,1,0,0]]).slice(G.camber_at(0.35)*G.C_F - vs)
draw_cs(ax, mid, fc="#d9dde2")
ax.set_title("Tramo de ala cortado por dentro:\ncelosía ±45°, 2 largueros, tapas", fontsize=9)
ax.set_xlim(-25, 65); ax.set_ylim(-3, 103)
ax = fig.add_axes([0.87, 0.2, 0.12, 0.2]); ax.set_aspect("equal"); ax.axis("off")
draw_cs(ax, seg.slice(37.0), fc="#d9dde2", lw=0.3)
ax.set_xlim(-25, 65); ax.set_ylim(-12, 12); ax.set_title("sección (piel 0,5 mm)", fontsize=8)
plt.savefig("ALFA-T_estructura.png", bbox_inches="tight")
