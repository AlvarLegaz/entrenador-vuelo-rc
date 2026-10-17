"""Prueba de los puntos de despegue destacados del vuelo libre en el Campo de Cartagena (escenarios.js "destacados"), en
el simulador del navegador: estan los cuatro (CIFP, Los Halcones de la Rambla en El Jimenado, la base aerea de San
Javier y SABIC), cada uno en su sitio; con el Entrenador 1 el de Los Halcones despega en Los Halcones (y no en San
Javier); el Cernicalo XM-7, que despega de pista, sale siempre de San Javier aunque se elija otro destacado o se pinche
en el mapa, y el vuelo empieza en la cabecera 05R. La misma prueba que simulador_godot/Tests/prueba_destacados.gd en Godot.

    python simulador_web/Tests/prueba_destacados_web.py
"""
import http.server, math, pathlib, socketserver, sys, threading
from playwright.sync_api import sync_playwright

REPO = pathlib.Path(__file__).resolve().parent.parent.parent
fallos = 0


def ok(nombre, cond, detalle=""):
    global fallos
    if not cond: fallos += 1
    print("  %s %s %s" % ("OK " if cond else "MAL", nombre, detalle))


G = r"""
async () => {
  window.requestAnimationFrame = cb => setTimeout(() => cb(performance.now()), 5);
  salirDelAula(); irInicio(); sesion.escenario = "libre_cartagena";
  const D = destacadosLanz(), out = { nombres: D.map(d => d.nombre) };
  const pos = d => { const [N, E] = latLonANE(mundoDe("libre_cartagena"), d.lat, d.lon); return [Math.round(N), Math.round(E)]; };
  out.pos = Object.fromEntries(D.map(d => [d.nombre, pos(d)]));
  sesion.avion = "E3"; await irLanzamiento();
  elegirDestacado(D.find(d => /Halcones/.test(d.nombre))); out.e3 = Object.assign({}, sesion.lanz);
  sesion.avion = "XM7"; await irLanzamiento(); out.xm7_entrar = Object.assign({}, sesion.lanz);
  elegirDestacado(D.find(d => /Halcones/.test(d.nombre))); out.xm7_halcones = Object.assign({}, sesion.lanz);
  const cv = document.getElementById("mapaLanz"), r = cv.getBoundingClientRect();
  cv.dispatchEvent(new MouseEvent("click", { clientX: r.left + r.width * 0.3, clientY: r.top + r.height * 0.6, bubbles: true })); out.xm7_clic = Object.assign({}, sesion.lanz);
  await empezar(); await new Promise(r => { const f = () => (pantallaActual === null && av && modelo) ? r() : setTimeout(f, 100); f(); });
  const P = pistaActual(); out.xm7_av = av.p.slice(); out.pista = [P.n, P.e];
  return out;
}
"""


def main():
    class H(http.server.SimpleHTTPRequestHandler):
        def __init__(s, *a, **k): super().__init__(*a, directory=str(REPO), **k)
        def log_message(s, *a): pass
    srv = socketserver.ThreadingTCPServer(("127.0.0.1", 0), H); srv.daemon_threads = True
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    with sync_playwright() as p:
        nav = p.chromium.launch(channel="chrome", headless=True, args=["--use-angle=swiftshader", "--enable-unsafe-swiftshader"])
        pg = nav.new_page(viewport={"width": 1400, "height": 850}); errs = []
        pg.on("pageerror", lambda e: errs.append(str(e)))
        pg.goto("http://127.0.0.1:%d/simulador_web/simulador.html" % srv.server_address[1]); pg.wait_for_function("typeof visor !== 'undefined' && visor && Modelos.ids().length > 0")
        r = pg.evaluate(G)
        nav.close()
    srv.shutdown()
    pos = r["pos"]; H_, SJ = pos.get("Los Halcones de la Rambla"), pos.get("Base aérea de San Javier")
    ok("los cuatro destacados", r["nombres"] == ["CIFP Politécnico", "Los Halcones de la Rambla", "Base aérea de San Javier", "SABIC (La Aljorra)"], str(r["nombres"]))
    ok("Los Halcones, en El Jimenado (junto a su zona de detalle) y a 17 km de San Javier", H_ and abs(H_[0] - 16428) < 200 and abs(H_[1] - 3290) < 200 and math.dist(H_, SJ) > 15000, "%s / %s" % (H_, SJ))
    ok("San Javier, en la cabecera 05R de su pista", SJ and math.dist(SJ, [17121.5 + 41.8, 20133.2 + 43.1]) < 5, str(SJ))
    ok("Entrenador 1: Los Halcones despega en Los Halcones", r["e3"].get("destacado") == "Los Halcones de la Rambla" and [r["e3"]["N"], r["e3"]["E"]] == H_, str(r["e3"]))
    ok("Cernicalo: al entrar, San Javier", r["xm7_entrar"].get("destacado") == "Base aérea de San Javier", str(r["xm7_entrar"]))
    ok("Cernicalo: aunque se elija Los Halcones", r["xm7_halcones"].get("destacado") == "Base aérea de San Javier", str(r["xm7_halcones"]))
    ok("Cernicalo: y aunque se pinche en el mapa", r["xm7_clic"].get("destacado") == "Base aérea de San Javier", str(r["xm7_clic"]))
    ok("Cernicalo: el vuelo empieza en la pista de San Javier", math.dist(r["xm7_av"][:2], r["pista"]) < 100, "%s / %s" % (r["xm7_av"][:2], r["pista"]))
    ok("sin errores en la pagina", not errs, errs[:3])
    print("RESULTADO:", "todo bien" if not fallos else "%d fallos" % fallos)
    sys.exit(1 if fallos else 0)


if __name__ == "__main__":
    main()
