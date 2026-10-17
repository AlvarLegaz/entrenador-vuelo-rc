"""Capturas de la isla del campo de vuelo en el simulador del navegador, con las mismas vistas que simulador_godot/Tests/ver_campo.gd
(puesto del piloto mirando al norte y al sur con 50 grados de campo de vision, una vista alta y otra de cerca de los almendros), para comparar Campo3D.

Uso (desde la carpeta del repositorio):
  python simulador_web/Tests/captura_campo_web.py C:/ruta/carpeta
Sirve el repositorio por HTTP y abre simulador_web/simulador.html con Chrome (Playwright, sin ventana, WebGL con la GPU;
--cpu: con SwiftShader): sin aula, avion E3, escenario 'libre', empezar(); calidad 2 fija; esconde el avion y la interfaz.
"""
import http.server
import socketserver
import sys
import threading
import time
from pathlib import Path

from playwright.sync_api import sync_playwright

REPO = Path(__file__).resolve().parent.parent.parent
VISTAS = {"norte": [[1.5, 1.7, 2], [1.5, 1.7, -998]], "sur": [[1.5, 1.7, 2], [1.5, 1.7, 1002]], "alto": [[-60, 140, 260], [0, 0, -80]],
          "almendros": [[60, 9, -150], [20, 0, -100]]}


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    salida = Path(args[0] if args else ".")
    salida.mkdir(parents=True, exist_ok=True)

    class H(http.server.SimpleHTTPRequestHandler):
        def __init__(s, *a, **k): super().__init__(*a, directory=str(REPO), **k)
        def log_message(s, *a): pass

    srv = socketserver.ThreadingTCPServer(("127.0.0.1", 0), H); srv.daemon_threads = True
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    gl = ["--use-angle=swiftshader", "--enable-unsafe-swiftshader"] if "--cpu" in sys.argv else ["--use-angle=d3d11", "--enable-gpu"]
    with sync_playwright() as p:
        nav = p.chromium.launch(channel="chrome", headless=True, args=gl + ["--ignore-gpu-blocklist"])
        pag = nav.new_page(viewport={"width": 1600, "height": 900})
        pag.add_init_script("try { localStorage.setItem('sim_calidad_modo', '2'); } catch (e) {}")
        pag.goto("http://127.0.0.1:%d/simulador_web/simulador.html" % srv.server_address[1])
        pag.wait_for_function("typeof visor !== 'undefined' && visor && Modelos.ids().length > 0", timeout=120000)
        pag.evaluate("""async () => {
          salirDelAula(); irInicio(); elegirAvion('E3'); sesion.escenario = 'libre'; await empezar();
          visor.calidadFija = true; visor.aplicarCalidad(2); visor.camara = 1;
          if (visor.avion) visor.avion.grupo.visible = false;
          const st = document.createElement("style"); st.textContent = "body > *:not(#vista) { visibility: hidden !important; }"; document.head.appendChild(st);
          window.__vista = null;
          visor._camara = function () {             // camara fija para las capturas
            const v = window.__vista; if (!v) return;
            this.cam.fov = 50; this.cam.position.set(...v[0]); this.cam.up.set(0, 1, 0); this.cam.lookAt(...v[1]); this.cam.updateProjectionMatrix();
          };
        }""")
        for nombre, v in VISTAS.items():
            pag.evaluate("(v) => { window.__vista = v; }", v)
            time.sleep(3)                            # unos fotogramas
            ruta = salida / f"web_{nombre}.png"
            pag.screenshot(path=str(ruta))
            print("captura:", ruta)
        nav.close()
    srv.shutdown()


if __name__ == "__main__":
    main()
