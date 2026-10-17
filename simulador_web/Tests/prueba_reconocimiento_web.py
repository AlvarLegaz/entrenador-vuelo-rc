"""Prueba de los trabajos de reconocimiento (op_rec_*) en el simulador del navegador, con los tres vehiculos que los
pueden volar: el Grajo MX-2 (morro fijo y orientable), el Poli-1 y el Entrenador 1. Para cada uno: el trabajo sale con el
elegido desde Los Halcones, con los camiones sorteados y su motor caliente; se lanza; el avion puesto a unos cientos de
metros del objetivo, mirandolo (los aviones y el morro fijo, apuntando con el avion; la torreta, fijada en el punto), y
la foto (F) o la vigilancia; y la vuelta del Grajo, con la toma en perdida. Con una carpeta, guarda capturas de la
camara 3 (con la mira de a bordo) y del mapa.

    python simulador_web/Tests/prueba_reconocimiento_web.py [carpeta de las capturas]
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
async ([m, a, morro]) => {
  window.requestAnimationFrame = cb => setTimeout(() => cb(performance.now()), 5);
  try { localStorage.setItem("sim_morro_GRAJO", morro); } catch (e) {}
  // cada trabajo con el vehiculo como nuevo: tras la toma en perdida de otro vuelo se puede haber soltado el ala (montaje)
  try { localStorage.removeItem("uxs_vehiculos"); } catch (e) {} Desgaste.cache = {};
  salirDelAula(); irInicio(); opVehiculo[m] = a; volarOperacion(m);
  await new Promise(r => { const f = () => (pantallaActual === null && ev && av && ev.op) ? r() : setTimeout(f, 100); f(); });
  pantallaActual = "prueba";
  const c = casa();
  return { avion: sesion.avion, veh: ev.op.d.vehiculos, con: ev.op.d.conVehiculo || null, motores: ev.op.termicos.filter(o => o.tipo === "motor").length,
           obj: Object.keys(ev.obj), ahora: ev.op.ahora(ev.obj, av), d: Math.hypot(av.p[0] - c.N, av.p[1] - c.E), estado: av.estado, morro: morroDe(sesion.avion) };
}
"""
LANZAR = r"""
() => {
  lanzar(); if (!modelo.uav) av.gases = 1;
  const s = modelo.uav ? 25 : 6; for (let n = 0; n < s / DT && av.estado === "volando"; n++) paso(DT);
  return { estado: av.estado, final: vuelo && vuelo.final, agl: av.agl, modo: piloto ? piloto.modo : null, V: Math.hypot(...av.v), ahora: ev.op.ahora(ev.obj, av) };
}
"""
# el avion a "dist" m del punto (N, E) hacia "ang" (rad), a h m sobre el suelo, mirandolo: los aviones y el morro fijo con
# el cabeceo (el frontal del fijo ya mira 15 grados abajo), la torreta fijada en el punto; s segundos quieto ahi y la foto
JUNTO = r"""
async ([N, E, dist, h, ang, s, foto, cam]) => {
  const H = entorno.altura(N, E), pn = N + dist * Math.cos(ang), pe = E + dist * Math.sin(ang), up = entorno.altura(pn, pe) + h;
  const y = Math.atan2(E - pe, N - pn), g = Math.atan2(H + 1.5 - up, dist), fijo = modelo.uav && morroDe(sesion.avion) === "fijo";
  const p = fijo ? g - Modelos.datos(sesion.avion).malla.cam_fija.frontal[1] * D2R : modelo.uav ? 0 : g;
  const pon = () => { av.p = [pn, pe, -up]; av.q = Cuat.desdeEuler(0, p, y); av.v = Cuat.rot(av.q, [modelo.uav ? 18 : 13, 0, 0]); av.w = [0, 0, 0]; };
  if (piloto && (piloto.modo === "LANZAMIENTO" || piloto.modo === "MANUAL")) uavPoner("CRUCERO");
  if (modelo.uav && !fijo) { UAV.fijo = [N, E, H + 1.5]; }
  pon(); const toasts = []; const t0 = window.toast; window.toast = s => toasts.push(s);
  for (let k = 0; k < s / DT; k++) { paso(DT); pon(); if (modelo.uav) moverTorreta(DT); }
  if (cam) { visor.camara = cam; pantallaActual = null; hud(); visor.dibujar(av); hud(); visor.dibujar(av); pantallaActual = "prueba"; await new Promise(r => setTimeout(r, 300)); }
  if (foto) { if (modelo.uav) uavFoto(); else avionFoto(); }
  window.toast = t0; const co = camaraOp();
  return { T: toasts, final: vuelo && vuelo.final, co: [co.gimbal, co.pan], hechos: ev.op.hechos.slice(), vig: ev.op.vig, ahora: ev.op.ahora(ev.obj, av),
           obj: Object.fromEntries(Object.entries(ev.obj).map(([k, o]) => [k, o.estado])) };
}
"""
VUELTA = r"""
() => {
  const c = casa(), vto = entorno.viento, desde = vto.base > 0.2 ? vto.rumbo + Math.PI : 0;
  const pn = c.N + 500 * Math.cos(desde), pe = c.E + 500 * Math.sin(desde), up = entorno.altura(pn, pe) + 60;
  av.p = [pn, pe, -up]; av.q = Cuat.desdeEuler(0, 0, desde + Math.PI); av.v = Cuat.rot(av.q, [14, 0, 0]); av.w = [0, 0, 0];
  uavPoner("CRUCERO"); uavPoner("ATERRIZAJE");
  let n = 0; while (av.estado === "volando" && n < 400 / DT) { paso(DT); n++; }
  return { estado: av.estado, final: vuelo && vuelo.final, t: n * DT, d: Math.hypot(av.p[0] - c.N, av.p[1] - c.E), obj: Object.fromEntries(Object.entries(ev.obj).map(([k, o]) => [k, o.estado + " | " + o.texto])) };
}
"""
MAPA = r"""
() => { pantallaActual = null; hud(); pintarGPS(Cuat.euler(av.q)[2] * R2D); pantallaActual = "prueba"; return true; }
"""


def main():
    salida = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else None
    if salida: salida.mkdir(parents=True, exist_ok=True)
    class H(http.server.SimpleHTTPRequestHandler):
        def log_message(self, *a): pass
        def __init__(self, *a, **k): super().__init__(*a, directory=str(REPO), **k)
    srv = socketserver.ThreadingTCPServer(("127.0.0.1", 0), H); srv.daemon_threads = True; threading.Thread(target=srv.serve_forever, daemon=True).start()
    with sync_playwright() as p:
        nav = p.chromium.launch(channel="chrome", headless=True, args=["--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist"])
        pg = nav.new_page(viewport={"width": 1280, "height": 760}); errs = []; pg.on("pageerror", lambda e: errs.append(str(e)))
        pg.goto("http://127.0.0.1:%d/simulador_web/simulador.html" % srv.server_address[1]); pg.wait_for_function("typeof visor !== 'undefined' && visor && Modelos.ids().length > 0")
        cap = lambda nombre: salida and pg.screenshot(path=str(salida / nombre))

        def preparar(m, a, morro="fijo"):
            r = pg.evaluate(PREP, [m, a, morro])
            ok("%s sale con %s%s desde Los Halcones" % (m, a, " (morro %s)" % morro if a == "GRAJO" else ""), r["avion"] == a and r["d"] < 5 and r["estado"] == "en mano"
               and (r["morro"] == morro if a == "GRAJO" else r["morro"] is None), str({k: r[k] for k in ("avion", "d", "estado", "morro")}))
            ok("  un motor caliente por camion", r["motores"] == len(r["veh"]) > 0, "%d camiones" % len(r["veh"]))
            ok("  'Ahora': lanzarlo", "lánzalo" in r["ahora"], r["ahora"])
            r2 = pg.evaluate(LANZAR); ok("  lanzado y volando", r2["estado"] == "volando" and r2["agl"] > (15 if a == "GRAJO" else 2), str(r2))
            return r

        # ---- itinerario: el Grajo (fijo), el Poli-1 y el Entrenador 1 ----
        for a in ("GRAJO", "G1", "E3"):
            r = preparar("op_rec_itinerario", a); ok("  dos de los cuatro puntos con camion", len(r["con"]) == 2, str(r["con"]))
            PQ = pg.evaluate("ESCENARIOS.op_rec_itinerario.operacion.recon.puntos.map(q => [q.n, q.e])")
            x = pg.evaluate(JUNTO, [PQ[0][0], PQ[0][1], 450, 100, 3.14159, 0.5, True, 0]); ok("  a 450 m: demasiado lejos", any("demasiado lejos" in t for t in x["T"]), str(x["T"]))
            for i, q in enumerate(PQ):
                x = pg.evaluate(JUNTO, [q[0], q[1], 200, 100, 3.14159, 0.5, True, 3 if i == 0 else 0])
                if i == 0: cap("rec_itinerario_%s_cam3.png" % a)
                hay = i in r["con"]
                ok("  foto del punto %d (%s)" % (i + 1, "con camion" if hay else "sin camion"), x["hechos"][i] and any(("HAY UN VEHÍCULO" if hay else "sin vehículos") in t for t in x["T"]), str(x["T"]) + " co=" + str([round(v, 1) for v in x["co"]]))
            ok("  puntos, vehiculos y tiempo ok", all(x["obj"][k] == "ok" for k in ("puntos", "vehiculos", "tiempo")), str(x["obj"]))
            ok("  'Ahora': vuelve", "vuelve" in x["ahora"], x["ahora"])
            if a == "GRAJO": pg.evaluate(MAPA); cap("rec_itinerario_mapa.png")
            if a != "GRAJO": continue                              # el aterrizaje a mano de los aviones ya lo prueban sus entrenamientos
            v = pg.evaluate(VUELTA)
            ok("  vuelta y aterrizaje", v["final"] == "aterrizado", str({k: v[k] for k in ("estado", "final", "t", "d")}))
            ok("  con la toma en perdida, en casa", v["obj"]["casa"].startswith("ok") and v["obj"]["minima"].startswith("ok"), v["obj"]["casa"] + " / " + v["obj"]["minima"])
        # ---- vigilancia: el Grajo con la torreta y el Poli-1 ----
        for a, morro in (("GRAJO", "orientable"), ("G1", "fijo")):
            r = preparar("op_rec_vigilancia", a, morro); vn, ve = r["veh"][0][:2]
            x = pg.evaluate(JUNTO, [vn, ve, 260, 120, 2.0, 50, True, 0]); ok("  foto antes de acabar la vigilancia", any("la vigilancia sigue" in t for t in x["T"]), str(x["T"]))
            x = pg.evaluate(JUNTO, [vn, ve, 400, 120, 2.0, 45, False, 3]); cap("rec_vigilancia_%s_cam3.png" % a)
            ok("  vigilancia completa", x["obj"]["vigilar"] == "ok" and any("Vigilancia completa" in t for t in x["T"]), str(x["T"]) + " vig=%.1f %s" % (x["vig"], x["final"]))
            x = pg.evaluate(JUNTO, [vn, ve, 200, 120, 2.0, 0.5, True, 0]); ok("  foto del vehiculo", x["obj"]["foto"] == "ok", str(x["T"]))
            ok("  sin que le oigan", x["obj"]["ruido"] == "curso", x["obj"]["ruido"])
            x = pg.evaluate(JUNTO, [vn, ve, 150, 50, 2.0, 0.5, False, 0]); ok("  bajo y cerca: le oyen", x["obj"]["ruido"] == "mal" and any("oír" in t for t in x["T"]), str(x["T"]))
        # ---- busqueda: el Entrenador 1 y el Grajo (fijo) ----
        for a in ("E3", "GRAJO"):
            r = preparar("op_rec_busqueda", a); vn, ve = r["veh"][0][:2]
            x = pg.evaluate(JUNTO, [vn, ve, 150, 110, 0.7, 0.5, True, 3]); cap("rec_busqueda_%s_cam3.png" % a)
            ok("  camion localizado con poco error", x["obj"]["localizar"] == "ok" and x["obj"]["posicion"] == "ok", str(x["T"]))
        ok("sin errores en la pagina", not errs, str(errs[:3]))
        nav.close()
    srv.shutdown()
    print("RESULTADO:", "todo bien" if fallos == 0 else "%d fallos" % fallos)


if __name__ == "__main__":
    main()
