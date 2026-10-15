"""Prueba de la patrulla de vertidos (op_patrulla) con el UAV Cernicalo XM-7 en el simulador del navegador: el trabajo sale
con el XM-7 en la cabecera 05R; despegue automatico; en cada vertido (el avion puesto a ~700 m y 300 m de altura), la
torreta fijada en la mancha: con zoom 1x esta demasiado lejos, con la cruz desplazada no vale, con 4x vale y envia la
posicion; con la termica el medidor lee la mancha caliente; y vuelta con el aterrizaje automatico hasta pararse en la
pista: vertidos y pista ok, a mano mal (se uso el automatico). Con una carpeta, guarda capturas (EO e IR de un vertido).

    python simulador_godot/pruebas/prueba_patrulla_web.py [carpeta de las capturas]
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
async () => {
  window.requestAnimationFrame = cb => setTimeout(() => cb(performance.now()), 5);
  salirDelAula(); irInicio(); volarOperacion("op_patrulla");
  await new Promise(r => { const f = () => (pantallaActual === null && ev && av && ev.op) ? r() : setTimeout(f, 100); f(); });
  pantallaActual = "prueba";
  const P = pistaActual(), [d, t] = piloto.ejePista(av.p[0], av.p[1]);
  return { avion: sesion.avion, vertidos: ev.op.d.vertidos, sectores: ev.op.d.sectores, eje: [d, t], obj: Object.keys(ev.obj), ahora: ev.op.ahora(ev.obj, av) };
}
"""
DESPEGUE = r"""
() => { lanzar(); quitarFrenoAparc(); uavPoner("DESPEGUE"); let n = 0; while (piloto.modo === "DESPEGUE" && n < 120 / DT) { paso(DT); n++; }
  return { modo: piloto.modo, agl: av.agl, despegue: ev.obj.despegue.estado, ahora: ev.op.ahora(ev.obj, av) }; }
"""
# coloca el avion a "dist" m del vertido i (al suroeste), a 300 m sobre el agua, rumbo al vertido, y fija la torreta en (N, E) + desvio
JUNTO = r"""
([i, dist, zoom, ter, desvio]) => {
  const [vn, ve] = ev.op.d.vertidos[i], h = entorno.altura(vn, ve), a = 1.0, pn = vn - dist * Math.cos(a), pe = ve - dist * Math.sin(a);
  av.p = [pn, pe, -(h + 300)]; av.q = Cuat.desdeEuler(0, 0, a); av.v = [32, 0, 0]; av.w = [0, 0, 0];
  if (piloto.modo === "DESPEGUE" || piloto.modo === "MANUAL") uavPoner("CRUCERO");
  DJI.zoomI = modelo.camara.zoom.indexOf(zoom); DJI.termica = ter;
  UAV.fijo = [vn + desvio, ve, h]; moverTorreta(0);
  for (let k = 0; k < 0.5 / DT; k++) { paso(DT); av.p = [pn, pe, -(h + 300)]; av.v = [32, 0, 0]; moverTorreta(DT); }
  const toasts = []; const t0 = window.toast; window.toast = s => toasts.push(s); uavFoto(); window.toast = t0;
  return { T: toasts, lectura: ev.op.lectura, vertidos: ev.obj.vertidos.estado, hechos: ev.op.hechos.slice(), cruz: UAV.cruz };
}
"""
VUELTA = r"""
() => {
  const P = piloto.pista, r = P.rumbo * D2R, ent = piloto.enPista(-6000, 0), h = P.h + 300;
  av.p = [ent[0], ent[1], -h]; av.q = Cuat.desdeEuler(0, 0, r); av.v = [32, 0, 0]; av.w = [0, 0, 0];
  uavPoner("CRUCERO"); uavPoner("ATERRIZAJE"); let n = 0;
  const L = []; while (av.estado === "volando" && n < 600 / DT) { paso(DT); n++; if (n % 2500 === 0) L.push([n * DT, piloto.fase, piloto.ejePista(av.p[0], av.p[1]).map(Math.round), Math.round(av.agl), Math.hypot(...av.v).toFixed(1)]); }
  return { estado: av.estado, final: vuelo && vuelo.final, L, fin: [n * DT, piloto.fase, piloto.ejePista(av.p[0], av.p[1]).map(Math.round), av.agl, av.v], obj: Object.fromEntries(Object.entries(ev.obj).map(([k, o]) => [k, o.estado + " | " + o.texto])) };
}
"""
FOTO = r"""
(cam) => { visor.camara = cam; pantallaActual = null; hud(); visor.dibujar(av); hud(); visor.dibujar(av); pantallaActual = "prueba"; }
"""


def main():
    salida = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else None
    if salida: salida.mkdir(parents=True, exist_ok=True)
    class H(http.server.SimpleHTTPRequestHandler):
        def log_message(self, *a): pass
        def __init__(self, *a, **k): super().__init__(*a, directory=str(REPO / "simulador"), **k)
    srv = socketserver.ThreadingTCPServer(("127.0.0.1", 0), H); srv.daemon_threads = True; threading.Thread(target=srv.serve_forever, daemon=True).start()
    with sync_playwright() as p:
        nav = p.chromium.launch(channel="chrome", headless=True, args=["--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist"])
        pg = nav.new_page(viewport={"width": 1280, "height": 760}); errs = []; pg.on("pageerror", lambda e: errs.append(str(e)))
        pg.goto("http://127.0.0.1:%d/simulador.html" % srv.server_address[1]); pg.wait_for_function("typeof visor !== 'undefined' && visor && Modelos.ids().length > 0")
        r = pg.evaluate(PREP)
        ok("op_patrulla sale con el XM-7 en la cabecera 05R", r["avion"] == "XM7" and abs(r["eje"][0] - 60) < 1 and abs(r["eje"][1]) < 1, str(r["eje"]))
        ok("tres vertidos con su sector a menos de 1 km", len(r["vertidos"]) == 3 and all(((v[0] - s[0]) ** 2 + (v[1] - s[1]) ** 2) ** 0.5 <= 600 for v, s in zip(r["vertidos"], r["sectores"])), str(r["sectores"]))
        ok("objetivos de la patrulla", r["obj"] == ["vertidos", "despegue", "a_mano", "altura", "techo", "tiempo", "pista", "aterrizar"], str(r["obj"]))
        r = pg.evaluate(DESPEGUE); ok("despegue automatico desde la pista", r["modo"] == "CRUCERO" and r["despegue"] == "ok", str(r))
        ok("'Ahora' apunta al sector 1", "sector 1" in r["ahora"], r["ahora"])
        r = pg.evaluate(JUNTO, [0, 1600, 1, False, 0]); ok("a 1,6 km sin zoom: demasiado lejos", any("demasiado lejos" in t for t in r["T"]), str(r["T"]))
        r = pg.evaluate(JUNTO, [0, 700, 4, False, 130]); ok("cruz a 130 m de la mancha: no vale", not any("Vertido 1" in t for t in r["T"]) and not r["hechos"][0], str(r["T"]))
        r = pg.evaluate(JUNTO, [0, 700, 4, True, 0]); ok("con la termica el medidor lee la mancha", bool(r["lectura"]) and r["lectura"]["tipo"] == "vertido", str(r["lectura"]))
        ok("con 4x y la cruz en la mancha: vertido 1 y posicion enviada", any("Vertido 1 ✓" in t for t in r["T"]), str(r["T"]))
        if salida:
            pg.evaluate(FOTO, 3); pg.screenshot(path=str(salida / "web_vertido_ir.png"))
            pg.evaluate("() => { DJI.termica = false; }"); pg.evaluate(FOTO, 3); pg.screenshot(path=str(salida / "web_vertido_eo.png"))
            pg.evaluate(FOTO, 2); pg.screenshot(path=str(salida / "web_vertido_cam2.png"))
        for i in (1, 2): r = pg.evaluate(JUNTO, [i, 700, 4, False, 0])
        ok("los tres vertidos", r["vertidos"] == "ok" and all(r["hechos"]), str(r["T"]))
        r = pg.evaluate(VUELTA)
        o = r["obj"]
        ok("vuelve y aterriza solo en la pista", r["final"] == "aterrizado", str(r["final"]) + ("" if r["final"] == "aterrizado" else " " + str(r["fin"]) + " " + str(r["L"])))
        ok("objetivos: vertidos, despegue, pista y tiempo ok; a mano mal (automatico)",
           o["vertidos"].startswith("ok") and o["despegue"].startswith("ok") and o["pista"].startswith("ok") and o["tiempo"].startswith("ok") and o["a_mano"].startswith("mal"), str(o))
        ok("sin errores en la pagina", not errs, errs[:3])
        nav.close()
    srv.shutdown()
    print("RESULTADO:", "todo bien" if not fallos else "%d fallos" % fallos)
    sys.exit(1 if fallos else 0)


if __name__ == "__main__":
    main()
