"""Prueba de la carrera de drones del Politecnico (op_carrera) en el simulador del navegador, con el mapa real y la fisica
de verdad (choques con edificios, arboles y los propios obstaculos): el trabajo sale con el FPV (y se puede elegir otro
dron del hangar), los 19 obstaculos se dibujan, y un vuelo "perfecto" (el dron llevado por el centro de cada obstaculo,
de uno a otro en linea recta) no choca con nada, cruza los 19 en orden, para el cronometro en la meta y termina el vuelo
con su marca; saltarse uno descalifica. Con una carpeta, guarda capturas (camara FPV con el indicador y la barra de
arriba, y la de persecucion).

    python simulador_godot/pruebas/prueba_carrera_web.py [carpeta de las capturas] [avion]
"""
import http.server, json, pathlib, socketserver, sys, threading
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
  salirDelAula(); irInicio(); opSel = "op_carrera"; irOperaciones();
  const botones = [...document.querySelectorAll("#fichaOperacion .elegirVeh button")].map(b => b.dataset.av);
  if (avion) document.querySelector(`#fichaOperacion .elegirVeh button[data-av="${avion}"]`).click();
  volarOperacion("op_carrera");
  await new Promise(r => { const f = () => (pantallaActual === null && ev && av && ev.op && visor.carreraObst) ? r() : setTimeout(f, 100); f(); });
  pantallaActual = "prueba";
  return { avion: sesion.avion, botones, obst: visor.carreraObst.length, n: ev.op.obst.length, obj: Object.keys(ev.obj), ahora: ev.op.ahora(ev.obj, av) };
}
"""
# el recorrido "perfecto": por el centro de cada obstaculo (de 4 m antes a 4 m despues, o de 5 m por encima del marco del
# picado a 3 m por debajo y 5 m por delante) y, entre uno y otro, la linea de carrera de analisis/mundo_cartagena/carrera_cifp.py
# (perfil): sube hasta 18 m sobre el suelo (por encima de los arboles) y baja al siguiente con pendiente 1,2; a "v" m/s, con la
# fisica de verdad del simulador (cada paso se pone el dron en su sitio y la fisica, los choques y la carrera hacen lo
# suyo). salta: indice del obstaculo que se salta (o -1); hasta: cuantos obstaculos
VUELO = r"""
async ([v, salta, hasta]) => {
  const M = CARRERA.MEDIDAS, O = ev.op.obst, H = 18, K = 1.2, alt = (n, e) => entorno.altura(n, e), seg = [];
  for (let j = 0; j < Math.min(O.length, hasta); j++) {
    if (j === salta) continue;
    const o = O[j], r = o.rumbo * D2R;
    if (o.tipo === "picado") { seg.push([[o.n, o.e, o.y0 + 5], [o.n, o.e, o.y0 - 3], [o.n + 5 * Math.cos(r), o.e + 5 * Math.sin(r), o.y0 - 3]]); continue; }
    const h = o.y0 + M[o.tipo][1] / 2; seg.push([[o.n - 4 * Math.cos(r), o.e - 4 * Math.sin(r), h], [o.n + 4 * Math.cos(r), o.e + 4 * Math.sin(r), h]]);
  }
  if (av.estado === "en mano") { lanzar(); if (modelo.despegar) modelo.despegar(av); }
  const T = [], toast0 = window.toast; window.toast = s => T.push(s);
  // el dron se lleva "en volandas": cada paso empieza donde acabo el anterior y la fisica lo deja en el punto siguiente
  // (asi el simulador ve el tramo recorrido en el paso: los cruces de los obstaculos y los choques)
  const fis = modelo.paso.bind(modelo); let destino = null;
  modelo.paso = (a_, w_, dt_) => { const r = fis(a_, w_, dt_); if (destino) { a_.p = destino.slice(); a_.v = [0, 0, 0]; a_.w = [0, 0, 0]; } return r; };
  const ir = (q, b) => { destino = [q[0], q[1], -q[2]]; av.q = Cuat.desdeEuler(0, 0, Math.atan2(b[1] - q[1], b[0] - q[0])); av.posado = false; av.enTierra = false;
    if (av.estado === "en mano") av.estado = "volando";               // llevado en volandas: ya ha despegado
    paso(DT); return av.estado === "volando"; };
  let a = [av.p[0], av.p[1], -av.p[2] + 1.5], donde = null;
  try {
    fuera: for (const sg of seg) {
      const ent = sg[0];
      const L = Math.hypot(ent[0] - a[0], ent[1] - a[1]), ha = a[2] - alt(a[0], a[1]), hb = ent[2] - alt(ent[0], ent[1]), k = Math.max(1, Math.ceil(L / (v * DT)));
      for (let i = 1; i <= k; i++) {                      // la linea de carrera hasta la entrada del obstaculo
        const f = i / k, n = a[0] + f * (ent[0] - a[0]), e = a[1] + f * (ent[1] - a[1]), s = f * L;
        const h = alt(n, e) + Math.min(Math.max(H, ha, hb), ha + K * s, hb + K * (L - s));
        if (!ir([n, e, h], ent)) { donde = [n, e, h]; break fuera; }
      }
      for (let m = 1; m < sg.length; m++) {               // por el obstaculo (el picado: abajo y por delante)
        const p0 = sg[m - 1], sal = sg[m], L2 = Math.hypot(sal[0] - p0[0], sal[1] - p0[1], sal[2] - p0[2]), k2 = Math.max(1, Math.ceil(L2 / (v * DT)));
        for (let i = 1; i <= k2; i++) {
          const f = i / k2, q = [p0[0] + f * (sal[0] - p0[0]), p0[1] + f * (sal[1] - p0[1]), p0[2] + f * (sal[2] - p0[2])];
          if (!ir(q, sal)) { donde = q; break fuera; }
        }
      }
      a = sg[sg.length - 1];
    }
    for (let i = 0; i < 3 / DT && av.estado === "volando"; i++) { av.v = [0, 0, 0]; paso(DT); }
  } finally { window.toast = toast0; destino = null; }
  const C = ev.op.carr;
  return { T, final: vuelo && vuelo.final, donde: donde && donde.map(x => +x.toFixed(1)), marca: vuelo && vuelo.marca, k: C.k, fuera: C.fuera, t: C.tFin !== null ? C.tFin - C.t0 : null, mejor: CARRERA_MEJOR,
           obj: Object.fromEntries(Object.entries(ev.obj).map(([k, o]) => [k, o.estado + " | " + o.texto])) };
}
"""
FOTO = r"""
(cam) => { visor.camara = cam; pantallaActual = null; visor.dibujar(av); hud(); visor.dibujar(av); hud(); pantallaActual = "prueba"; }
"""


def main():
    salida = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 and sys.argv[1] != "-" else None
    avion = sys.argv[2] if len(sys.argv) > 2 else None
    if salida: salida.mkdir(parents=True, exist_ok=True)
    class H(http.server.SimpleHTTPRequestHandler):
        def log_message(self, *a): pass
        def __init__(self, *a, **k): super().__init__(*a, directory=str(REPO / "simulador"), **k)
    srv = socketserver.ThreadingTCPServer(("127.0.0.1", 0), H); srv.daemon_threads = True; threading.Thread(target=srv.serve_forever, daemon=True).start()
    with sync_playwright() as p:
        nav = p.chromium.launch(channel="chrome", headless=True, args=["--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist"])
        pg = nav.new_page(viewport={"width": 1280, "height": 760}); errs = []; pg.on("pageerror", lambda e: errs.append(str(e)))
        url = "http://127.0.0.1:%d/simulador.html" % srv.server_address[1]
        pg.goto(url); pg.wait_for_function("typeof visor !== 'undefined' && visor && Modelos.ids().length > 0")
        r = pg.evaluate(PREP, avion)
        ok("la carrera sale con %s y deja elegir los drones del hangar" % (avion or "el FPV"), r["avion"] == (avion or "FPV") and set(r["botones"]) >= {"FPV", "DJI_MINI", "HQ3T"}, str(r["botones"]))
        ok("los 19 obstaculos se dibujan", r["obst"] == 19 and r["n"] == 19)
        ok("objetivos de la carrera", r["obj"] == ["secuencia", "meta", "tiempo", "choques"], str(r["obj"]))
        if salida: pg.evaluate(FOTO, 2); pg.screenshot(path=str(salida / "web_carrera_salida.png"))
        r = pg.evaluate(VUELO, [20, -1, 99])
        ok("el recorrido perfecto no choca con nada y llega a la meta", r["final"] == "carrera terminada", "%s %s" % (r["final"], r.get("donde", "")))
        ok("cruza los 19 en orden, con salida y meta", r.get("k") == 19 and any("¡Salida!" in t for t in r["T"]) and any("¡Meta!" in t for t in r["T"]), str(r["T"][-3:]))
        ok("la marca del vuelo y el mejor de la sesion", r.get("marca") and abs(r["marca"] - r["t"]) < 1e-6 and r["mejor"]["t"] == r["t"], "%s %s" % (r.get("marca"), r.get("mejor")))
        o = r.get("obj", {})
        ok("objetivos: todos ok (APTO)", all(v.startswith("ok") for v in o.values()), str(o))
        # otra vez, saltandose el 6: descalificado
        pg.goto(url); pg.wait_for_function("typeof visor !== 'undefined' && visor && Modelos.ids().length > 0"); pg.evaluate(PREP, avion)
        if salida:
            pg.evaluate(VUELO, [20, -1, 3])                                  # a medio camino, para las capturas del indicador
            pg.evaluate(FOTO, 3); pg.screenshot(path=str(salida / "web_carrera_fpv.png"))
            pg.evaluate("() => { av.q = Cuat.desdeEuler(0, 0, (Cuat.euler(av.q)[2] + Math.PI)); }"); pg.evaluate(FOTO, 3); pg.screenshot(path=str(salida / "web_carrera_flecha.png"))
            pg.evaluate(FOTO, 2); pg.screenshot(path=str(salida / "web_carrera_cam2.png"))
            pg.goto(url); pg.wait_for_function("typeof visor !== 'undefined' && visor && Modelos.ids().length > 0"); pg.evaluate(PREP, avion)
        r = pg.evaluate(VUELO, [20, 5, 99])
        ok("saltandose el 6: descalificado y se acaba el vuelo", r["final"] == "descalificado" and r["fuera"] == 5 and any("Descalificado" in t for t in r["T"]), "%s %s" % (r["final"], r.get("fuera")))
        ok("sin errores en la pagina", not errs, errs[:3])
        nav.close()
    srv.shutdown()
    print("RESULTADO:", "todo bien" if not fallos else "%d fallos" % fallos)
    sys.exit(1 if fallos else 0)


if __name__ == "__main__":
    main()
