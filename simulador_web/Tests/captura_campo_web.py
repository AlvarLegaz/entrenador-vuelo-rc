"""Capturas de la isla del campo de vuelo en el simulador del navegador, con las mismas vistas que simulador_godot/Tests/ver_campo.gd
(puesto del piloto mirando al norte y al sur con 50 grados de campo de vision, y una vista alta), para comparar Campo3D.

Uso (desde la carpeta del repositorio):
  python simulador_web/Tests/captura_campo_web.py C:/ruta/carpeta
Abre simulador_web/simulador.html con Chrome (Playwright, sin ventana, WebGL por SwiftShader): elegirPiloto(null),
elegirAvion('E1'), escenario 'libre', empezar(); calidad 2 fija; esconde el avion y la interfaz.
"""
import sys
import time
from pathlib import Path

from playwright.sync_api import sync_playwright

REPO = Path(__file__).resolve().parent.parent.parent
PAGINA = (REPO / "simulador_web" / "simulador.html").as_uri()
VISTAS = {"norte": [[1.5, 1.7, 2], [1.5, 1.7, -998]], "sur": [[1.5, 1.7, 2], [1.5, 1.7, 1002]], "alto": [[-60, 140, 260], [0, 0, -80]]}


def main():
    salida = Path(sys.argv[1] if len(sys.argv) > 1 else ".")
    salida.mkdir(parents=True, exist_ok=True)
    with sync_playwright() as p:
        nav = p.chromium.launch(channel="chrome", headless=True,
                                args=["--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist"])
        pag = nav.new_page(viewport={"width": 1600, "height": 900})
        pag.goto(PAGINA)
        pag.wait_for_function("typeof visor !== 'undefined' && visor && typeof empezar === 'function'", timeout=120000)
        pag.evaluate("""async () => {
          try { localStorage.setItem('sim_calidad', '2'); } catch (e) {}
          elegirPiloto(null); elegirAvion('E1'); sesion.escenario = 'libre'; await empezar();
          visor.calidadFija = true; visor.aplicarCalidad(2); visor.camara = 1;
          if (visor.avion) visor.avion.grupo.visible = false;
          for (const el of document.body.children) if (el.id !== 'vista') el.style.visibility = 'hidden';
          window.__vista = null;
          visor._camara = function () {             // camara fija para las capturas
            const v = window.__vista; if (!v) return;
            this.cam.fov = 50; this.cam.position.set(...v[0]); this.cam.up.set(0, 1, 0); this.cam.lookAt(...v[1]); this.cam.updateProjectionMatrix();
          };
        }""")
        for nombre, v in VISTAS.items():
            pag.evaluate("(v) => { window.__vista = v; }", v)
            time.sleep(6)                            # SwiftShader: unos fotogramas
            ruta = salida / f"web_{nombre}.png"
            pag.screenshot(path=str(ruta))
            print("captura:", ruta)
        nav.close()


if __name__ == "__main__":
    main()
