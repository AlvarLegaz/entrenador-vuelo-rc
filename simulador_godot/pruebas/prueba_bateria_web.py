"""Prueba de la bateria (js/bateria.js) en el simulador del navegador, en la pagina de verdad y con su paso(): el Mini
Dron HQ lejos de casa con la bateria justa vuelve a casa solo y aterrizo alli ("Batería justa para volver"); con la
bateria critica aterriza donde esta (aterrizaje forzoso) y no se puede cancelar; el Entrenador 1 a fondo con la bateria
casi vacia: el regulador corta el motor. La misma prueba que pruebas/prueba_bateria.gd en Godot.

    python simulador_godot/pruebas/prueba_bateria_web.py
"""
import http.server, pathlib, socketserver, sys, threading
from playwright.sync_api import sync_playwright

REPO = pathlib.Path(__file__).resolve().parent.parent.parent
fallos = 0


def ok(nombre, cond, detalle=""):
    global fallos
    if not cond: fallos += 1
    print("  %s %s %s" % ("OK " if cond else "MAL", nombre, detalle))


PREP = r"""
async (avion) => {
  window.requestAnimationFrame = cb => setTimeout(() => cb(performance.now()), 5);
  salirDelAula(); sesion.avion = avion; sesion.escenario = "libre"; irInicio(); await empezar();
  await new Promise(r => { const f = () => (pantallaActual === null && av && modelo) ? r() : setTimeout(f, 50); f(); });
  pantallaActual = "prueba"; const T = []; window.toast = s => T.push(s); window._T = T; return modelo.nombre;
}
"""
# el Mini a N metros de casa y h de altura, con la bateria al pct: s segundos de paso() con las palancas al centro
DRON = r"""
([N, h, pct, s, cancelar]) => {
  lanzar(); modelo.despegar(av);
  for (let i = 0; i < 2 / DT; i++) paso(DT);
  av.p = [N, 0, -((entorno.altura ? entorno.altura(N, 0) : 0) + h)]; av.posado = false; av.v = [0, 0, 0]; av.hold = null; av.despegado = true;
  const B = modelo.B; av.bat.mAh = (1 - pct / 100) * Bateria.capacidad(B, av.bat); av.bat.P = 40;
  for (const k of ["pitch", "yaw", "guinada", "vz"]) mando[k] = 0;
  let resto = null;
  for (let i = 0; i < s / DT && av.estado === "volando"; i++) {
    paso(DT);
    if (cancelar && av.batForzado && resto === null) { djiRTH(); mando.vz = 1; resto = [-av.p[2], av.t]; }
    if (resto && av.t - resto[1] > 3) mando.vz = 0;
  }
  return { estado: av.estado, final: vuelo && vuelo.final, N: av.p[0], E: av.p[1], agl: av.agl, pct: modelo.bateriaPct(av), aviso: av.avisoBat, forzado: av.batForzado,
           rth: av.batRth, T: _T.slice(), subio: resto ? -av.p[2] - resto[0] : null };
}
"""
AVION = r"""
() => {
  lanzar();
  av.p = [0, 0, -120]; av.v = [12, 0, 0]; av.q = Cuat.desdeEuler(0, 0, 0); av.w = [0, 0, 0];
  av.bat.mAh = 0.97 * Bateria.capacidad(modelo.B, av.bat);
  mando.pitch = 0; mando.yaw = 0;
  for (let i = 0; i < 90 / DT && av.estado === "volando" && !av.cortado; i++) { av.gases = 1; paso(DT); }
  const t0 = av.t; for (let i = 0; i < 2 / DT && av.estado === "volando"; i++) { av.gases = 1; paso(DT); }
  return { cortado: av.cortado, rpm: av.rpm, T: av.T, celda: Bateria.celdaMin(modelo.B, av.bat), pct: modelo.bateriaPct(av), toasts: _T.slice(), aviso: document.getElementById("aviso").textContent };
}
"""


def main():
    class H(http.server.SimpleHTTPRequestHandler):
        def __init__(s, *a, **k): super().__init__(*a, directory=str(REPO / "simulador"), **k)
        def log_message(s, *a): pass
    srv = socketserver.ThreadingTCPServer(("127.0.0.1", 0), H); srv.daemon_threads = True
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    url = "http://127.0.0.1:%d/simulador.html" % srv.server_address[1]
    with sync_playwright() as p:
        nav = p.chromium.launch(channel="chrome", headless=True, args=["--use-angle=swiftshader", "--enable-unsafe-swiftshader"])
        pg = nav.new_page(viewport={"width": 1280, "height": 720}); errs = []
        pg.on("pageerror", lambda e: errs.append(str(e)))
        def nueva(avion):
            pg.goto(url); pg.wait_for_function("typeof visor !== 'undefined' && visor && Modelos.ids().length > 0")
            return pg.evaluate(PREP, avion)
        nueva("DJI_MINI")
        r = pg.evaluate(DRON, [600, 40, 26, 200, False])
        ok("Mini a 600 m con el 26 %: vuelve a casa solo", r["rth"] and any("justa para volver" in t for t in r["T"]), str(r["T"][:3]))
        ok("y aterriza en casa", r["final"] is not None and "aterrizado" in r["final"] and abs(r["N"]) < 3 and abs(r["E"]) < 3, "%s N %.1f E %.1f" % (r["final"], r["N"], r["E"]))
        nueva("DJI_MINI")
        r = pg.evaluate(DRON, [300, 30, 9.9, 80, True])
        ok("Mini al 10 %: aterrizaje forzoso donde esta", r["forzado"] and any("Aterrizaje forzoso" in t for t in r["T"]), str(r["T"][:3]))
        ok("y no se puede cancelar (ni subir)", any("no se puede cancelar" in t for t in r["T"]) and r["subio"] is not None and r["subio"] < 0.5, "subio %s" % r["subio"])
        ok("aterriza lejos de casa, donde estaba", r["final"] is not None and "aterrizado" in r["final"] and abs(r["N"] - 300) < 5, "%s N %.1f" % (r["final"], r["N"]))
        nueva("E3")
        r = pg.evaluate(AVION)
        ok("Entrenador 1 casi vacio a fondo: el regulador corta el motor", r["cortado"] and r["rpm"] == 0 and r["T"] == 0, "celda %.2f V, %.1f %%" % (r["celda"], r["pct"]))
        ok("y lo avisa", any("cortado el motor" in t for t in r["toasts"]) and "Motor cortado" in r["aviso"], str(r["toasts"][:2]))
        ok("sin errores en la pagina", not errs, errs[:3])
        nav.close()
    srv.shutdown()
    print("RESULTADO:", "todo bien" if not fallos else "%d fallos" % fallos)
    sys.exit(1 if fallos else 0)


if __name__ == "__main__":
    main()
