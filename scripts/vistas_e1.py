"""Lamina con planta, alzado, perfil y vista 3D del avion montado (ENTRENADOR_E1_vistas.png o
ENTRENADOR_E2_vistas.png segun la variable de entorno ENTRENADOR), a partir de las mallas montadas de geom_e1.py."""
import os, pickle
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.collections import PolyCollection
import geom_e1 as G
from avion import ID, P

M = pickle.load(open(os.path.join(G.OUT, "glob_meshes.pkl"), "rb"))
COLOR = lambda nm: ("#ffc107" if nm.startswith("ALA") else "#d32f2f" if nm.startswith(("PROF", "TIMON", "ALERON")) else
                    "#bdbdbd" if nm.startswith("ESTAB") else "#f4f4f4")
LUZ = np.array([0.4, -0.5, 0.75]); LUZ /= np.linalg.norm(LUZ)


def dibujar(ax, R, titulo):
    """R: matriz 3x3 que lleva (X, Y, Z) del proyecto a (horizontal, vertical, profundidad) de la vista."""
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
# planta: X hacia abajo de la hoja es raro; se dibuja con el morro a la izquierda
dibujar(fig.add_subplot(2, 2, 1), np.array([[1, 0, 0], [0, -1, 0], [0, 0, 1]]), "Planta (morro a la izquierda, mm)")
dibujar(fig.add_subplot(2, 2, 2), np.array([[0, 1, 0], [0, 0, 1], [-1, 0, 0]]), ("Frente (mm): centro plano hasta %.0f mm y %.0f° de diedro en las puntas" % (P.QUIEBRO, P.DIEDRO)) if P.DIEDRO else "Frente (mm): ala plana, sin diedro")
dibujar(fig.add_subplot(2, 2, 3), np.array([[1, 0, 0], [0, 0, 1], [0, 1, 0]]), "Perfil (mm)")
a, b = np.radians(35), np.radians(25)
Rz = np.array([[np.cos(a), -np.sin(a), 0], [np.sin(a), np.cos(a), 0], [0, 0, 1]])
Rx = np.array([[1, 0, 0], [0, np.cos(b), -np.sin(b)], [0, np.sin(b), np.cos(b)]])
Riso = Rx @ np.array([[0, 1, 0], [0, 0, 1], [-1, 0, 0]]) @ Rz
ax = fig.add_subplot(2, 2, 4); dibujar(ax, Riso, "Vista 3D"); ax.axis("off")
fig.suptitle("%s · %.1f m de envergadura · ala alta %s · %s" % (getattr(P, "NOMBRE", "Entrenador E1"), P.B / 1000,
                                                                 "con diedro" if P.DIEDRO else "plana",
                                                                 getattr(P, "MANDOS_TXT", "timón y profundidad")), fontsize=15)
fig.tight_layout()
sal = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "ENTRENADOR_%s_vistas.png" % ID)
fig.savefig(sal, dpi=110)
print("guardado", os.path.abspath(sal))
