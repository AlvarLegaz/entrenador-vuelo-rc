"""Sirve el simulador web para que los alumnos lo abran en su navegador desde otro ordenador: la carpeta simulador_web en
/ y los datos comunes (../datos: vehiculos, escenarios, entrenamientos y operaciones) en /datos/, que es donde los busca
la pagina ("../datos/..." desde simulador.html). Solo entrega ficheros: la fisica, el 3D y la evaluacion las hace el
navegador de cada alumno. Lo usan SERVIDOR_WEB.bat, SERVIDOR_WEB.sh y DESPLEGAR_UBUNTU.sh.

    python simulador_web/servidor_web.py [puerto]          (80 si no se dice)
"""
import functools, http.server, os, sys

WEB = os.path.dirname(os.path.abspath(__file__))
DATOS = os.path.normpath(os.path.join(WEB, "..", "datos"))
DE_DATOS = (".js", ".json", ".jpg", ".png", ".bin", ".txt")           # de datos/ solo datos (no los .py ni los .ps1)


class Pagina(http.server.SimpleHTTPRequestHandler):
    def translate_path(self, ruta):
        p = super().translate_path(ruta)                   # dentro de simulador_web (ya sin "..", %2e ni barras raras)
        rel = os.path.relpath(p, WEB)
        if rel == "datos" or rel.startswith("datos" + os.sep):
            q = os.path.normpath(os.path.join(DATOS, rel[len("datos"):].lstrip(os.sep)))
            return q if q.startswith(DATOS + os.sep) and q.endswith(DE_DATOS) else os.path.join(WEB, "no-existe")
        if rel == "Tests" or rel.startswith("Tests" + os.sep) or rel.endswith(".py"):
            return os.path.join(WEB, "no-existe")          # las pruebas y este servidor no se sirven
        return p


if __name__ == "__main__":
    puerto = int(sys.argv[1]) if len(sys.argv) > 1 else 80
    srv = http.server.ThreadingHTTPServer(("0.0.0.0", puerto), functools.partial(Pagina, directory=WEB))
    print("Simulador web en el puerto %d (Ctrl+C para parar)" % puerto)
    try: srv.serve_forever()
    except KeyboardInterrupt: pass
