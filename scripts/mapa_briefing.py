"""Mapa del campo de vuelo del simulador para el briefing: vista cenital con el norte arriba, a escala.

Zona 1 (delante del piloto): pista 1, los 4 pilones de colores y el sentido de vuelta de cada escenario.
Zona 2 (detras del piloto): pista 2 con la diana, la puerta naranja y las pasadas bajas.
Los datos son los de simulador_web/js/entorno.js (Entorno: pista, circuito, zona2); si cambian alli, cambiar aqui.
Escribe mapa_campo_briefing.png en la raiz del proyecto.
"""
import os
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import Rectangle, Circle, FancyArrowPatch, Polygon

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# --- datos de entorno.js (N, E en metros; origen en el piloto) ---
PISTA1 = dict(n0=10, n1=70, ancho=10)
CENTRO = (100, 0)
PILONES = [((40, -90), "VERDE", "#2e7d32"), ((160, -90), "AMARILLO", "#f9a825"),
           ((160, 90), "ROJO", "#c62828"), ((40, 90), "AZUL", "#1565c0")]
PISTA2 = dict(n=-45, e0=-35, e1=35, ancho=10, margen=5)
DIANA = dict(n=-45, e=0, anillos=[(20, 20), (10, 50), (5, 100)])
PUERTA = dict(e=60, n0=-123, n1=-107)
DESPEJADO = dict(n0=-150, n1=-14, e0=-60, e1=95)

TIERRA, TIERRA_CLARA, PISTA_C, BORDE = "#e8c4a0", "#f2dcc4", "#d9c29d", "#8a6a4a"
plt.rcParams["font.family"] = "DejaVu Sans"


def P(n, e):
    """(N, E) -> (x, y) del dibujo: x = este, y = norte."""
    return (e, n)


def flecha(ax, a, b, color, ancho=2.5, rad=0.0, cabeza=18, estilo="-|>", ls="-", z=5):
    ax.add_patch(FancyArrowPatch(P(*a), P(*b), connectionstyle=f"arc3,rad={rad}", arrowstyle=estilo,
                                 mutation_scale=cabeza, lw=ancho, color=color, linestyle=ls, zorder=z))


def pilon(ax, n, e, color, etiqueta, dn=0, de=0, ha="center"):
    ax.add_patch(Circle(P(n, e), 4.2, facecolor=color, edgecolor="white", lw=2, zorder=8))
    ax.add_patch(Circle(P(n, e), 1.6, facecolor="white", edgecolor="none", zorder=9))
    if etiqueta:
        ax.text(e + de, n + dn, etiqueta, color=color, fontsize=13, fontweight="bold", ha=ha, va="center", zorder=9,
                bbox=dict(boxstyle="round,pad=0.25", fc="white", ec=color, lw=1.5))


def main():
    fig, ax = plt.subplots(figsize=(16, 13.5), dpi=180)
    E0, E1, N0, N1 = -175, 215, -185, 235
    ax.set_xlim(E0, E1); ax.set_ylim(N0, N1); ax.set_aspect("equal")
    ax.add_patch(Rectangle((E0, N0), E1 - E0, N1 - N0, facecolor=TIERRA, zorder=0))
    # reticula de 50 m
    for x in range(-150, 201, 50):
        ax.plot([x, x], [N0, N1], color="#c9a37f", lw=0.6, zorder=1)
    for y in range(-150, 201, 50):
        ax.plot([E0, E1], [y, y], color="#c9a37f", lw=0.6, zorder=1)

    # ---------------- ZONA 1 ----------------
    (cn, ce) = CENTRO
    esq = [P(n, e) for (n, e), _, _ in PILONES]
    ax.add_patch(Polygon(esq, closed=True, facecolor="#f6e3cf", edgecolor="none", alpha=0.55, zorder=1))
    ax.add_patch(Polygon(esq, closed=True, fill=False, edgecolor="#7a5a3a", lw=1.2, ls=(0, (6, 5)), zorder=2))
    ax.add_patch(Rectangle(P(PISTA1["n0"], -PISTA1["ancho"] / 2), PISTA1["ancho"], PISTA1["n1"] - PISTA1["n0"],
                           facecolor=PISTA_C, edgecolor=BORDE, lw=1.5, zorder=3))
    ax.text(0, (PISTA1["n0"] + PISTA1["n1"]) / 2, "PISTA 1", rotation=90, ha="center", va="center", fontsize=11,
            color="#5a4028", fontweight="bold", zorder=4)
    # circuito por fuera de los pilones, sentido del primer vuelo (verde -> amarillo -> rojo -> azul)
    m = 22
    ruta = [(40 - m, -90 - m * 0.4), (160 + m * 0.4, -90 - m), (160 + m, 90 + m * 0.4), (40 - m * 0.4, 90 + m)]
    for i in range(4):
        a, b = ruta[i], ruta[(i + 1) % 4]
        flecha(ax, a, b, "#1b5e20", ancho=3, rad=-0.12, cabeza=22, z=4)
    ax.text(-147, 100, "PRIMER VUELO (1)\nverde → amarillo → rojo → azul\nsubes por la izquierda", color="#1b5e20",
            fontsize=11, ha="center", va="center", rotation=90, fontweight="bold", zorder=6)
    ax.text(150, 100, "VIENTO CRUZADO (3)\nal revés: azul → rojo → amarillo → verde\nsubes por la derecha", color="#7b1fa2",
            fontsize=11, ha="center", va="center", rotation=-90, fontweight="bold", zorder=6)
    flecha(ax, (55, 133), (145, 133), "#7b1fa2", ancho=2, cabeza=16, z=4)
    ax.text(ce, 115, "Las vueltas se dan\nPOR FUERA de los 4 pilones\n(cortar por dentro anula la vuelta)",
            ha="center", va="center", fontsize=10.5, color="#5a4028", style="italic", zorder=4,
            bbox=dict(boxstyle="round,pad=0.4", fc="#fbf1e6", ec="#c9a37f"))
    for (n, e), nom, col in PILONES:
        lado = -1 if e < 0 else 1
        pilon(ax, n, e, col, nom, dn=(-13 if n < 100 else 13), de=0)
    ax.text(-165, 228, "ZONA 1 · CIRCUITO DE PILONES (delante del piloto)", fontsize=15, fontweight="bold",
            color="#3e2a18", va="top", zorder=10)
    ax.text(-165, 219, "Escenarios 1-4 (cuentan para la maqueta real) · pilones de 20 m", fontsize=11,
            color="#3e2a18", va="top", zorder=10)

    # ---------------- PILOTO ----------------
    ax.add_patch(Circle(P(0, 0), 7, facecolor="#cfc3ad", edgecolor="#8a7a60", lw=1, zorder=3))   # aparcamiento
    ax.plot([0], [0], marker="o", ms=13, mfc="black", mec="white", mew=2, zorder=12)
    ax.text(9, -3, "PILOTO", fontsize=13, fontweight="bold", va="center", zorder=12,
            bbox=dict(boxstyle="round,pad=0.25", fc="white", ec="black", lw=1.2))
    flecha(ax, (2, 0), (24, 0), "black", ancho=3, cabeza=20, z=11)
    ax.text(-4, 18, "lanza zona 1", fontsize=9.5, ha="right", va="center", zorder=11)
    flecha(ax, (-2, 0), (-22, 0), "#e65100", ancho=3, cabeza=20, z=11)
    ax.text(-4, -11, "lanza zona 2 (se da la vuelta)", fontsize=9.5, ha="right", va="center", color="#e65100", zorder=11)
    ax.plot([E0, E1], [0, 0], color="black", lw=1, ls=(0, (2, 4)), zorder=2)
    ax.text(E1 - 3, 3, "línea del piloto", fontsize=9, ha="right", va="bottom", zorder=2)

    # ---------------- ZONA 2 ----------------
    D = DESPEJADO
    ax.add_patch(Rectangle((D["e0"], D["n0"]), D["e1"] - D["e0"], D["n1"] - D["n0"], facecolor=TIERRA_CLARA,
                           edgecolor="#c9a37f", lw=1, ls=(0, (4, 4)), zorder=1))
    p2 = PISTA2
    ax.add_patch(Rectangle((p2["e0"], p2["n"] - p2["ancho"] / 2 - p2["margen"]), p2["e1"] - p2["e0"],
                           p2["ancho"] + 2 * p2["margen"], fill=False, edgecolor="#1565c0", lw=1, ls=(0, (3, 3)), zorder=3))
    ax.add_patch(Rectangle((p2["e0"], p2["n"] - p2["ancho"] / 2), p2["e1"] - p2["e0"], p2["ancho"],
                           facecolor=PISTA_C, edgecolor=BORDE, lw=1.5, zorder=3))
    for r, pts in DIANA["anillos"]:
        ax.add_patch(Circle(P(DIANA["n"], DIANA["e"]), r, fill=False, edgecolor="white", lw=2.2, zorder=4))
        ax.text(DIANA["e"] + r * 0.72, DIANA["n"] - r * 0.72 - 1, f"{pts}", fontsize=9, color="#3e2a18",
                fontweight="bold", ha="center", va="center", zorder=5)
    ax.add_patch(Circle(P(DIANA["n"], DIANA["e"]), 1.2, facecolor="white", zorder=5))
    ax.text(0, -71, "DIANA  5 / 10 / 20 m → 100 / 50 / 20 puntos", fontsize=10.5, ha="center", fontweight="bold",
            color="#3e2a18", zorder=6)
    ax.text(-37, -45, "PISTA 2", fontsize=10.5, ha="right", va="center", fontweight="bold", color="#5a4028", zorder=6)
    # pasadas bajas
    flecha(ax, (-31, -30), (-31, 30), "#1565c0", ancho=2.2, cabeza=16, z=6)
    flecha(ax, (-59, 30), (-59, -30), "#1565c0", ancho=2.2, cabeza=16, z=6)
    ax.text(0, -27, "PASADA BAJA: de punta a punta entre 2 y 8 m", fontsize=10, ha="center", color="#1565c0",
            fontweight="bold", zorder=6)
    # puerta
    pilon(ax, PUERTA["n0"], PUERTA["e"], "#ef6c00", None)
    pilon(ax, PUERTA["n1"], PUERTA["e"], "#ef6c00", None)
    ax.plot([PUERTA["e"]] * 2, [PUERTA["n0"] + 4, PUERTA["n1"] - 4], color="white", lw=2, ls=(0, (2, 2)), zorder=7)
    nm = (PUERTA["n0"] + PUERTA["n1"]) / 2
    flecha(ax, (nm, PUERTA["e"] - 26), (nm, PUERTA["e"] + 26), "#ef6c00", ancho=2.2, cabeza=16, estilo="<|-|>", z=6)
    ax.text(PUERTA["e"] + 8, PUERTA["n0"] - 9, "PUERTA (16 m)\nentre los pilones naranjas,\npor debajo de 20 m",
            fontsize=10, color="#bf360c", fontweight="bold", va="top", zorder=9)
    ax.text(-165, -150, "ZONA 2 · PRECISIÓN (detrás del piloto)", fontsize=15, fontweight="bold", color="#3e2a18",
            va="top", zorder=10)
    ax.text(-165, -159, "Escenarios 5-8, práctica · 5 Puerta ×3 · 6 Pasada baja (una a cada lado)\n"
            "7 Diana (< 10 m) · 8 Recorrido: pasada baja → puerta → diana", fontsize=10.5, color="#3e2a18",
            va="top", zorder=10)
    ax.text(D["e1"] - 2, D["n1"] - 3, "sin árboles", fontsize=8.5, color="#8a6a4a", ha="right", va="top", zorder=2)

    # ---------------- NORTE, ESCALA ----------------
    nx, ny = 195, 190
    ax.add_patch(Polygon([(nx, ny + 22), (nx - 7, ny), (nx, ny + 5), (nx + 7, ny)], closed=True, fc="black", zorder=12))
    ax.text(nx, ny + 27, "N", fontsize=16, fontweight="bold", ha="center", zorder=12)
    sx, sy = 100, -175
    for i in range(4):
        ax.add_patch(Rectangle((sx + i * 25, sy), 25, 3.5, fc="black" if i % 2 == 0 else "white", ec="black", lw=1, zorder=12))
    for i in range(0, 5):
        ax.text(sx + i * 25, sy + 6, f"{i * 25}", fontsize=9, ha="center", zorder=12)
    ax.text(sx + 104, sy + 1.7, "m", fontsize=10, va="center", zorder=12)
    ax.text(E1 - 3, N1 - 4, "Cuadrícula de 50 m", fontsize=9, ha="right", va="top", color="#7a5a3a", zorder=10)
    ax.text(E0 + 3, N0 + 3, "A más de 400 m del piloto: aviso «demasiado lejos» · a 650 m el avión se pierde.  "
            "Tocar un pilón rompe el avión.", fontsize=9, color="#3e2a18", zorder=10)

    ax.set_xticks([]); ax.set_yticks([])
    for s in ax.spines.values():
        s.set_color("#3e2a18"); s.set_linewidth(1.5)
    ax.set_title("Campo de vuelo del simulador · Entrenador RC — mapa de briefing", fontsize=18, fontweight="bold",
                 color="#3e2a18", pad=12)
    fig.tight_layout()
    salida = os.path.join(RAIZ, "mapa_campo_briefing.png")
    fig.savefig(salida, dpi=180)
    print("escrito", salida)


if __name__ == "__main__":
    main()
