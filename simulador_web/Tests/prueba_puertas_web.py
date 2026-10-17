"""Prueba de la mision 5 · Puerta en el navegador (la misma que simulador_godot/Tests/prueba_puertas.gd en Godot): las dos
puertas de la zona 2 en orden (naranja, verde, naranja, verde). Cruzar la que no toca, por encima de los pilones o por
fuera no cuenta; la verde se cruza de norte a sur o al reves; al acabar, el panel dice "aterrizar".

    python simulador_web/Tests/prueba_puertas_web.py
"""
import http.server, pathlib, socketserver, sys, threading
from playwright.sync_api import sync_playwright

REPO = pathlib.Path(__file__).resolve().parent.parent.parent

GUION = r"""
async () => {
  salirDelAula(); irInicio(); elegirAvion('DJI_MINI'); sesion.escenario = 'puerta'; await empezar(); pantallaActual = 'prueba';
  const T = [], t0 = window.toast; window.toast = m => { T.push(String(m)); };
  av.estado = 'volando'; ev.subido = true;
  const cruza = (a, b) => { av.p = b.slice(); zona2(a); };
  const est = () => ['puerta1', 'puerta2', 'puerta3', 'puerta4'].map(k => ev.obj[k].estado).join(',');
  const N = [[-115, 65, -10], [-115, 55, -10]], V = [[-130, -23, -10], [-140, -23, -10]], r = [];
  cruza(...V); r.push(['la verde primero no cuenta', est() === 'pend,pend,pend,pend' && T.at(-1).includes('ahora toca la naranja'), T.at(-1)]);
  cruza(...N); r.push(['la naranja: primera', est() === 'ok,pend,pend,pend' && textoZona2().includes('cruzar la puerta verde (1/4)'), '']);
  cruza(...N); r.push(['otra vez la naranja: no toca', est() === 'ok,pend,pend,pend', '']);
  cruza([-130, -23, -30], [-140, -23, -30]); r.push(['la verde por encima de los pilones no cuenta', est() === 'ok,pend,pend,pend' && T.at(-1).includes('Por encima de la puerta verde'), '']);
  cruza([-140, -23, -10], [-130, -23, -10]); r.push(['la verde hacia el norte: segunda', est() === 'ok,ok,pend,pend', '']);
  cruza([-115, 55, -10], [-115, 65, -10]); r.push(['la naranja hacia el este: tercera', est() === 'ok,ok,ok,pend', '']);
  cruza([-130, 5, -10], [-140, 5, -10]); r.push(['por fuera de la verde no cuenta', est() === 'ok,ok,ok,pend' && T.at(-1).includes('Por fuera de la puerta verde'), '']);
  cruza(...V); r.push(['la verde: cuarta, y a aterrizar', est() === 'ok,ok,ok,ok' && textoZona2().includes('aterrizar'), T.at(-1)]);
  r.push(['los pilones verdes son solidos', entorno.chocaPilon([-135, -31, -5], 0.2), '']);
  window.toast = t0;
  return r;
}
"""


def main():
    class H(http.server.SimpleHTTPRequestHandler):
        def __init__(s, *a, **k): super().__init__(*a, directory=str(REPO), **k)
        def log_message(s, *a): pass

    srv = socketserver.ThreadingTCPServer(("127.0.0.1", 0), H); srv.daemon_threads = True
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    fallos, errores = 0, []
    with sync_playwright() as p:
        nav = p.chromium.launch(channel="chrome", headless=True, args=["--use-angle=swiftshader", "--enable-unsafe-swiftshader"])
        pag = nav.new_page(); pag.on("pageerror", lambda e: errores.append(str(e)))
        pag.goto("http://127.0.0.1:%d/simulador_web/simulador.html" % srv.server_address[1])
        pag.wait_for_function("typeof visor !== 'undefined' && visor && Modelos.ids().length > 0", timeout=120000)
        for nombre, ok, detalle in pag.evaluate(GUION):
            fallos += 0 if ok else 1
            print("  %s %s %s" % ("OK " if ok else "MAL", nombre, detalle))
        nav.close()
    srv.shutdown()
    if errores: fallos += 1; print("  MAL errores en la pagina:", errores[:3])
    print("RESULTADO:", "todo bien" if fallos == 0 else "%d fallos" % fallos)
    sys.exit(1 if fallos else 0)


if __name__ == "__main__":
    main()
