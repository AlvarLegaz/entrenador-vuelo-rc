"""Lamina con planta, alzado, perfil y vista 3D del Tandem T1 montado (TANDEM_T1_vistas.png), a partir de las
mallas montadas de stl/T1/scripts/geom.py (out/glob_meshes.pkl) mas los winglets.

    $env:ENTRENADOR = "T1"; python scripts/vistas_t1.py
"""
import os, pickle, sys
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.collections import PolyCollection

os.environ.setdefault("ENTRENADOR", "T1")
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from avion import ID, P   # noqa: E402
assert ID == "T1"
GT = P.GT

M = pickle.load(open(os.path.join(GT.OUT, "glob_meshes.pkl"), "rb"))
W = P.WINGLET
for sg, nm in ((-1, "WL_izq"), (1, "WL_der")):
    mesh = GT.fin().translate([W["x_te"], sg * W["y"], W["z0"]]).to_mesh()
    M[nm] = (np.asarray(mesh.vert_properties)[:, :3], np.asarray(mesh.tri_verts))
COLOR = lambda nm: ("#4caf50" if nm.startswith(("AD", "AT")) else "#d32f2f" if nm.startswith("EL") else
                    "#bdbdbd" if nm.startswith("WL") else "#f4f4f4")
LUZ = np.array([0.4, -0.5, 0.75]); LUZ /= np.linalg.norm(LUZ)


def dibujar(ax, R, titulo):
    polys, cols, prof = [], [], []
    for nm, (v, t) in M.items():
        w = v @ R.T
        tri = w[t]
        n = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0])
        nn = np.linalg.norm(n, axis=1); ok = nn > 1e-9
        n = n[ok] / nn[ok, None]; tri = tri[ok]
        brillo = 0.45 + 0.55 * np.abs(n @ (R @ LUZ))
        base = np.array(matplotlib.colors.to_rgb(COLOR(nm)))
        polys += list(tri[:, :, :2]); cols += list(np.clip(base[None] * brillo[:, None], 0, 1)); prof += list(tri[:, :, 2].mean(1))
    orden = np.argsort(prof)
    ax.add_collection(PolyCollection([polys[i] for i in orden], facecolors=[cols[i] for i in orden], edgecolors="none"))
    todo = np.vstack([v @ R.T for v, _ in M.values()])
    ax.set_xlim(todo[:, 0].min() - 20, todo[:, 0].max() + 20); ax.set_ylim(todo[:, 1].min() - 20, todo[:, 1].max() + 20)
    ax.set_aspect("equal"); ax.set_title(titulo, fontsize=12); ax.tick_params(labelsize=8)


fig = plt.figure(figsize=(16, 11))
dibujar(fig.add_subplot(2, 2, 1), np.array([[1, 0, 0], [0, -1, 0], [0, 0, 1]]), "Planta (morro a la izquierda, mm)")
dibujar(fig.add_subplot(2, 2, 2), np.array([[0, 1, 0], [0, 0, 1], [-1, 0, 0]]), "Frente (mm): ala delantera bajo el tubo, trasera encima, dos derivas junto al fuselaje")
dibujar(fig.add_subplot(2, 2, 3), np.array([[1, 0, 0], [0, 0, 1], [0, 1, 0]]), "Perfil (mm): calado +2° delante, 0° detrás")
a, b = np.radians(35), np.radians(25)
Rz = np.array([[np.cos(a), -np.sin(a), 0], [np.sin(a), np.cos(a), 0], [0, 0, 1]])
Rx = np.array([[1, 0, 0], [0, np.cos(b), -np.sin(b)], [0, np.sin(b), np.cos(b)]])
Riso = Rx @ np.array([[0, 1, 0], [0, 0, 1], [-1, 0, 0]]) @ Rz
ax = fig.add_subplot(2, 2, 4); dibujar(ax, Riso, "Vista 3D"); ax.axis("off")
fig.suptitle("%s · %.1f m de envergadura · dos alas en tándem · %s" % (P.NOMBRE, P.B / 1000, P.MANDOS_TXT), fontsize=15)
fig.tight_layout()
sal = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "TANDEM_T1_vistas.png")
fig.savefig(sal, dpi=110)
print("guardado", os.path.abspath(sal))
