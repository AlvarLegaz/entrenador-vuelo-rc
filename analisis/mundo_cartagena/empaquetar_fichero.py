"""Empaqueta la ortofoto de la region y las zonas de detalle como scripts .js, para que el simulador del navegador funcione
tambien abriendo simulador.html con doble clic (file://). Asi el navegador no deja leer ficheros con fetch y trata las
imagenes sueltas como de otro origen: WebGL no las acepta y el suelo sale negro. Un <script> si se carga, y una imagen
en data: no tiene ese problema. Con servidor (aula o http.server) se siguen usando los ficheros sueltos.

Escribe:
  simulador/mundos/<id>_orto.js     Mundos.ortofoto("<id>", "data:image/jpeg;base64,...")
  simulador/zonas/indice.js         Zonas.indice([...])            (el mismo contenido que indice.json)
  simulador/zonas/<id>/zona.js      Zonas.registrar("<id>", { dem, arboles (base64), edificios, orto: {"i_j": data:...} })

Uso:  python analisis/mundo_cartagena/empaquetar_fichero.py [carpeta simulador]
zona.py y orto_region.py lo llaman solos al terminar.
"""
import base64, glob, json, os, sys


def _b64(ruta):
    return base64.b64encode(open(ruta, "rb").read()).decode("ascii")


def ortofoto_mundo(ruta_jpg):
    mid = os.path.basename(ruta_jpg)[:-len("_orto.jpg")]
    sal = ruta_jpg[:-4] + ".js"
    with open(sal, "w", encoding="ascii") as f:
        f.write('Mundos.ortofoto(%s, "data:image/jpeg;base64,%s");\n' % (json.dumps(mid), _b64(ruta_jpg)))
    print("escrito", sal, round(os.path.getsize(sal) / 1e6, 1), "MB")


def zona(dir_zona):
    meta = json.load(open(os.path.join(dir_zona, "zona.json")))
    orto = {}
    for i in range(meta["orto"]["teselas"]):
        for j in range(meta["orto"]["teselas"]):
            nombre = meta["orto"]["archivo"].replace("{i}", str(i)).replace("{j}", str(j))
            orto["%d_%d" % (i, j)] = "data:image/jpeg;base64," + _b64(os.path.join(dir_zona, nombre))
    datos = dict(dem=_b64(os.path.join(dir_zona, meta["dem"]["archivo"])),
                 arboles=_b64(os.path.join(dir_zona, meta["arboles"]["archivo"])),
                 edificios=json.load(open(os.path.join(dir_zona, meta["edificios"]["archivo"]))), orto=orto)
    sal = os.path.join(dir_zona, "zona.js")
    with open(sal, "w", encoding="utf-8") as f:
        f.write("Zonas.registrar(%s, %s);\n" % (json.dumps(meta["id"]), json.dumps(datos, separators=(",", ":"))))
    print("escrito", sal, round(os.path.getsize(sal) / 1e6, 1), "MB")


def indice(dir_zonas):
    lista = json.load(open(os.path.join(dir_zonas, "indice.json")))
    with open(os.path.join(dir_zonas, "indice.js"), "w", encoding="utf-8") as f:
        f.write("Zonas.indice(%s);\n" % json.dumps(lista, ensure_ascii=False))


def todo(dir_sim):
    for jpg in glob.glob(os.path.join(dir_sim, "mundos", "*_orto.jpg")):
        ortofoto_mundo(jpg)
    dz = os.path.join(dir_sim, "zonas")
    if os.path.isfile(os.path.join(dz, "indice.json")):
        indice(dz)
        for d in sorted(os.listdir(dz)):
            if os.path.isfile(os.path.join(dz, d, "zona.json")):
                zona(os.path.join(dz, d))


if __name__ == "__main__":
    todo(sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "simulador"))
