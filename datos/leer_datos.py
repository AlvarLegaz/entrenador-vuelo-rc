"""Lectura de los datos comunes desde Python (servidor del aula, pruebas y generadores): los escenarios, en el orden de
datos/escenarios.js, como el diccionario que la web tiene en window.ESCENARIOS.

    import sys; sys.path.insert(0, "<repo>/datos"); from leer_datos import escenarios
    E = escenarios()                     # {id: {...}} en el orden de la app
"""
import json, os, re

DATOS = os.path.dirname(os.path.abspath(__file__))


def ficheros(datos=DATOS):
    """La lista de ficheros de los escenarios (relativa a datos/), en el orden de la app."""
    t = open(os.path.join(datos, "escenarios.js"), encoding="utf-8").read()
    m = re.search(r"ESCENARIOS_FICHEROS = (\[.*?\]);", t, re.S)
    return json.loads(m.group(1))


def escenario(ruta):
    """(id, datos) de un fichero de escenario: ESCENARIOS["<id>"] = {...};"""
    t = open(ruta, encoding="utf-8").read()
    m = re.search(r'(?m)^ESCENARIOS\["([^"]+)"\] = ', t)
    return m.group(1), json.loads(t[m.end():t.rindex("}") + 1])


def escenarios(datos=DATOS):
    """{id: datos} de todos los escenarios, en el orden de la app."""
    return dict(escenario(os.path.join(datos, f)) for f in ficheros(datos))


def escribir(id_, datos, carpeta, antes_de="escenarios/libre_cartagena.js", base=DATOS):
    """Escribe el escenario id_ en <carpeta>/<id_>.js (carpeta: "entrenamientos", "operaciones" o "escenarios") y, si es
    nuevo, lo pone en la lista de datos/escenarios.js delante de antes_de (al final si no esta). Devuelve su ruta.
    Lo usan los generadores de analisis/ (op_patrulla.py, op_sabic.py, carrera_cifp.py, candidatos_inspeccion.py)."""
    rel = "%s/%s.js" % (carpeta, id_); ruta = os.path.join(base, rel)
    txt = "// %s. Datos comunes de los simuladores: ver datos/escenarios.js.\nESCENARIOS[%s] = %s;\n" % (
        datos.get("nombre", id_), json.dumps(id_), json.dumps(datos, ensure_ascii=False, indent=1))
    open(ruta, "w", encoding="utf-8", newline="").write(txt)
    lista = ficheros(base)
    if rel not in lista:
        lista.insert(lista.index(antes_de) if antes_de in lista else len(lista), rel)
        p = os.path.join(base, "escenarios.js"); t = open(p, encoding="utf-8").read()
        m = re.search(r"ESCENARIOS_FICHEROS = (\[.*?\]);", t, re.S)
        open(p, "w", encoding="utf-8", newline="").write(t[:m.start(1)] + json.dumps(lista, indent=1) + t[m.end(1):])
    return ruta
