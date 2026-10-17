"""Capturas del mundo real en el simulador del navegador, sin la interfaz, desde unas vistas fijas alrededor del CIFP
Politecnico (las mismas que simulador_godot/Tests/capturas_mundo.gd en Godot), para comparar el aspecto de edificios, suelo y arboles
antes y despues de un cambio, o entre la web y Godot. Mide tambien las llamadas de dibujo, los triangulos y los ms por
fotograma (con la GPU de verdad: Chrome con D3D11).

    python simulador_web/Tests/capturas_mundo_web.py <carpeta> [prefijo] [--cpu] [--minimo]

--cpu dibuja con SwiftShader (por procesador): los ms se parecen mas a los de un PC sin tarjeta grafica.
--minimo: con la calidad "Rendimiento maximo" (la de portatiles y tabletas sencillos); si no, la alta.
"""
import http.server, json, pathlib, socketserver, sys, threading
from playwright.sync_api import sync_playwright

REPO = pathlib.Path(__file__).resolve().parent.parent.parent
# nombre: [N, E, altura sobre el suelo, rumbo (grados), gimbal (grados, - abajo)]; camara 3 del Mini Dron HQ
VISTAS = {
    "fachadas": [10, 6310, 18, 270, -8], "calle": [0, 6212, 2.5, 315, 3], "cifp_baja": [40, 6640, 8, 40, -8],
    "cifp_alta": [-40, 6600, 45, 35, -30], "barrio": [120, 6760, 25, 200, -15], "lejos": [0, 6650, 120, 300, -12],
}

PREP = r"""
async () => {
  salirDelAula(); irInicio(); opSel = "op_carrera"; irOperaciones();
  document.querySelector('#fichaOperacion .elegirVeh button[data-av="DJI_MINI"]').click();
  volarOperacion("op_carrera");
  await new Promise(r => { const f = () => (pantallaActual === null && av && visor.carreraObst) ? r() : setTimeout(f, 100); f(); });
  visor.ponerOperacion(null);                         // solo el mundo, sin los obstaculos
  await new Promise(r => setTimeout(r, 8000));        // que lleguen edificios, arboles y ortofotos
  pantallaActual = "prueba";
  document.body.classList.add("espectador");           // sin la interfaz
  const st = document.createElement("style"); st.textContent = "body > *:not(canvas) { visibility: hidden !important; }"; document.head.appendChild(st);
  return visor.calidad;
}
"""
MEDIR = r"""
async ([n, e, h, rumbo, gimbal]) => {
  av.p = [n, e, -(entorno.altura(n, e) + h)]; av.v = [0, 0, 0]; av.q = Cuat.desdeEuler(0, 0, rumbo * D2R); av.gimbal = gimbal;
  visor.camara = 3; pantallaActual = null;
  for (let i = 0; i < 30; i++) visor.dibujar(av);
  const R = visor.renderer, gl = R.getContext(), px = new Uint8Array(4);
  R.info.autoReset = false; R.info.reset(); visor.dibujar(av); const info = { llamadas: R.info.render.calls, triangulos: R.info.render.triangles }; R.info.autoReset = true;
  gl.readPixels(0, 0, 1, 1, gl.RGBA, gl.UNSIGNED_BYTE, px);
  const N = 60, t0 = performance.now(); for (let i = 0; i < N; i++) { visor.dibujar(av); gl.readPixels(0, 0, 1, 1, gl.RGBA, gl.UNSIGNED_BYTE, px); }
  info.ms = +((performance.now() - t0) / N).toFixed(2); visor.dibujar(av); pantallaActual = "prueba";
  return info;
}
"""


def main():
    sal = pathlib.Path(sys.argv[1]); sal.mkdir(parents=True, exist_ok=True)
    pref = next((a for a in sys.argv[2:] if not a.startswith("--")), "web")
    cpu, minimo = "--cpu" in sys.argv, "--minimo" in sys.argv

    class H(http.server.SimpleHTTPRequestHandler):
        def __init__(s, *a, **k): super().__init__(*a, directory=str(REPO), **k)
        def log_message(s, *a): pass

    srv = socketserver.ThreadingTCPServer(("127.0.0.1", 0), H); srv.daemon_threads = True
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    args = ["--use-angle=swiftshader", "--enable-unsafe-swiftshader"] if cpu else ["--use-angle=d3d11", "--enable-gpu"]
    res, errs = {}, []
    with sync_playwright() as p:
        nav = p.chromium.launch(channel="chrome", headless=True, args=args + ["--ignore-gpu-blocklist"])
        pg = nav.new_page(viewport={"width": 1280, "height": 720})
        pg.on("pageerror", lambda e: errs.append(str(e)))
        pg.add_init_script("try { localStorage.setItem('sim_calidad_modo', '%s'); } catch (e) {}" % ("min" if minimo else "2"))
        pg.goto("http://127.0.0.1:%d/simulador_web/simulador.html" % srv.server_address[1])
        pg.wait_for_function("typeof visor !== 'undefined' && visor && Modelos.ids().length > 0")
        if not minimo: pg.evaluate("() => { visor.calidadFija = true; visor.aplicarCalidad(2); }")
        pg.evaluate(PREP)
        for k, v in VISTAS.items():
            res[k] = pg.evaluate(MEDIR, v)
            pg.screenshot(path=str(sal / ("%s_%s.png" % (pref, k))))
            print("  %-10s %s" % (k, res[k]))
        nav.close()
    srv.shutdown()
    json.dump(res, open(sal / ("%s_medidas.json" % pref), "w"), indent=1)
    print("errores:", errs[:3])


if __name__ == "__main__":
    main()
