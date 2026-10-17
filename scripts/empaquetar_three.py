"""Empaqueta Three.js (paquete npm, p. ej. three-0.169.0.tgz descomprimido) como scripts GLOBALES para el simulador
del navegador, que carga todo con <script src> (tambien abriendo simulador.html con doble clic, sin servidor):

  simulador_web/lib/three.js          el nucleo (build/three.cjs envuelto: deja window.THREE)
  simulador_web/lib/three-extras.js   Sky, Water y CSM (examples/jsm), cada uno en su bloque, con sus import cambiados
                                  por lecturas de THREE y sus export por THREE.X = X

    python scripts/empaquetar_three.py <carpeta 'package' del tgz>
"""
import os, re, sys

pkg = sys.argv[1]
dst = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "simulador_web", "lib")
os.makedirs(dst, exist_ok=True)
version = re.search(r'"version":\s*"([^"]+)"', open(os.path.join(pkg, "package.json"), encoding="utf-8").read()).group(1)

nucleo = open(os.path.join(pkg, "build", "three.cjs"), encoding="utf-8").read()
with open(os.path.join(dst, "three.js"), "w", encoding="utf-8") as f:
    f.write("// Three.js %s (MIT), build/three.cjs envuelto como script global por scripts/empaquetar_three.py\n" % version)
    f.write("(function () {\nvar exports = {}; var module = { exports: exports };\n")
    f.write(nucleo)
    f.write("\nwindow.THREE = Object.assign({}, module.exports, exports);\n})();\n")

IMPORT = re.compile(r"import\s*\{([^}]*)\}\s*from\s*['\"]([^'\"]+)['\"];?")


def a_global(ruta):
    """Un modulo de examples/jsm a codigo de script: import {..} from '...' -> const {..} = THREE; sin export."""
    s = open(ruta, encoding="utf-8").read()
    s = IMPORT.sub(lambda m: "const {%s} = THREE;" % m.group(1), s)      # 'three' o un modulo hermano ya cargado en THREE
    exp = re.findall(r"export\s*\{([^}]*)\};?", s)
    s = re.sub(r"export\s*\{[^}]*\};?", "", s)
    s = re.sub(r"export\s+(class|function|const)\s+", r"\1 ", s)
    nombres = [n.strip().split(" as ")[-1] for e in exp for n in e.split(",") if n.strip()]
    nombres += re.findall(r"^(?:class|function|const)\s+([A-Z][A-Za-z0-9_]*)", s, re.M)
    return s, sorted(set(nombres))


partes, todos = [], []
for rel in ["objects/Sky.js", "objects/Water.js", "csm/CSMShader.js", "csm/CSMFrustum.js", "csm/CSM.js"]:
    s, n = a_global(os.path.join(pkg, "examples", "jsm", rel))
    exporta = "".join("if (typeof %s !== 'undefined') THREE.%s = %s;\n" % (x, x, x) for x in n)
    partes.append("// ---- examples/jsm/%s ----\n{\n%s\n%s}\n" % (rel, s, exporta))   # cada modulo en su bloque
    todos += n
with open(os.path.join(dst, "three-extras.js"), "w", encoding="utf-8") as f:
    f.write("// Three.js %s (MIT): Sky, Water y CSM de examples/jsm como script global (scripts/empaquetar_three.py)\n(function () {\n" % version)
    f.write("\n".join(partes))
    f.write("})();\n")
print("Three.js", version, "->", os.path.abspath(dst), "| extras:", ", ".join(sorted(set(todos))))
