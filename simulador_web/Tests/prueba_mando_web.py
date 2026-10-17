"""Botones del mando en el simulador del navegador, con un mando simulado (navigator.getGamepads sustituido): RB cambia de
camara en el avion, el dron comercial, el FPV y el bipode (el mismo boton en todos), Y ya no lo hace en el avion, A lanza
el avion, Back reinicia el dron y Start pausa.

    python simulador_web/Tests/prueba_mando_web.py
"""
import http.server, pathlib, socketserver, sys, threading
from playwright.sync_api import sync_playwright

REPO = pathlib.Path(__file__).resolve().parent.parent.parent
fallos = 0


def ok(nombre, cond, detalle=""):
    global fallos
    if not cond: fallos += 1
    print("  %s %s %s" % ("OK " if cond else "MAL", nombre, detalle))


GUION = r"""
async ([avion, escenario]) => {
  window.requestAnimationFrame = cb => setTimeout(() => cb(performance.now()), 5);
  salirDelAula(); irInicio(); sesion.avion = avion; sesion.escenario = escenario; await empezar(); pantallaActual = null;
  const pad = { id: "prueba", connected: true, axes: [0, 0, 0, 0], buttons: Array.from({ length: 17 }, () => ({ pressed: false, value: 0 })) };
  navigator.getGamepads = () => [pad];
  const pulsa = i => { pad.buttons[i].pressed = true; pad.buttons[i].value = 1; leerMando(0.016); pad.buttons[i].pressed = false; pad.buttons[i].value = 0; leerMando(0.016); };
  const r = { c0: visor.camara };
  pulsa(5); r.c1 = visor.camara; pulsa(5); r.c2 = visor.camara;           // RB: siguiente camara, dos veces
  pulsa(3); r.cY = visor.camara;                                           // Y: en el avion ya no cambia (en el dron es foto)
  r.estado0 = av.estado; pulsa(0); r.estadoA = av.estado;                  // A: lanzar / despegar / armar / arrancar
  pulsa(9); r.pausa = pausado; pulsa(9); r.pausa2 = pausado;               // Start: pausa y sigue
  pantallaActual = "prueba"; navigator.getGamepads = () => [];
  return r;
}
"""


def main():
    class H(http.server.SimpleHTTPRequestHandler):
        def log_message(self, *a): pass
        def __init__(self, *a, **k): super().__init__(*a, directory=str(REPO), **k)
    srv = socketserver.ThreadingTCPServer(("127.0.0.1", 0), H); srv.daemon_threads = True; threading.Thread(target=srv.serve_forever, daemon=True).start()
    with sync_playwright() as p:
        nav = p.chromium.launch(channel="chrome", headless=True, args=["--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist"])
        pg = nav.new_page(viewport={"width": 1280, "height": 720}); errs = []; pg.on("pageerror", lambda e: errs.append(str(e)))
        pg.goto("http://127.0.0.1:%d/simulador_web/simulador.html" % srv.server_address[1]); pg.wait_for_function("typeof visor !== 'undefined' && visor && Modelos.ids().length > 0")
        for avion, esc, c0 in [("E3", "libre", 1), ("DJI_MINI", "libre", 3), ("FPV", "libre", 3), ("BIPODE", "libre", 2)]:
            r = pg.evaluate(GUION, [avion, esc])
            ok("%s: RB cambia de camara (%d -> %d -> %d)" % (avion, r["c0"], r["c1"], r["c2"]), r["c1"] == r["c0"] % 3 + 1 and r["c2"] == r["c1"] % 3 + 1)
            if avion == "E3": ok("E3: Y ya no cambia de camara", r["cY"] == r["c2"])
            ok("%s: A arranca (%s -> %s)" % (avion, r["estado0"], r["estadoA"]), r["estadoA"] == "volando")
            ok("%s: Start pausa y sigue" % avion, r["pausa"] is True and r["pausa2"] is False)
        ok("sin errores en la pagina", not errs, errs[:2])
        nav.close()
    srv.shutdown()
    print("RESULTADO:", "todo bien" if not fallos else "%d fallos" % fallos)
    sys.exit(1 if fallos else 0)


if __name__ == "__main__":
    main()
