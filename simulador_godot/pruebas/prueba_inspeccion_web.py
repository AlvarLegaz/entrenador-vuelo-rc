"""Prueba del dron de inspeccion (Inspector HQ-3T) en el simulador del navegador: el dron esta en el hangar; los trabajos
de la fabrica de SABIC y de los paneles salen con el, y los demas con el Mini Dron HQ; zoom y camara termica con las
teclas Z / X / C; en la fabrica, el medidor puntual sostenido 3 s sobre un punto caliente lo da por medido, la fuga
igual (sin entrar en la zona ATEX), la placa de la antorcha se lee con 28x desde mas de 60 m y su piloto con la termica;
en los paneles, los puntos calientes solo valen con la termica. Con una carpeta, guarda capturas (termica y zoom).

    python simulador_godot/pruebas/prueba_inspeccion_web.py [carpeta de las capturas]
"""
import http.server, math, pathlib, socketserver, sys, threading
from playwright.sync_api import sync_playwright

REPO = pathlib.Path(__file__).resolve().parent.parent.parent
fallos = 0


def ok(nombre, cond, detalle=""):
    global fallos
    if not cond: fallos += 1
    print("  %s %s %s" % ("OK " if cond else "MAL", nombre, detalle))


PREP = r"""
async (id) => {
  window.requestAnimationFrame = cb => setTimeout(() => cb(performance.now()), 5);
  salirDelAula(); irInicio(); volarOperacion(id);
  await new Promise(r => { const f = () => (pantallaActual === null && ev && av) ? r() : setTimeout(f, 100); f(); });
  pantallaActual = "prueba";
  return { avion: sesion.avion, op: !!ev.op, termicos: ev.op ? ev.op.termicos.length : 0 };
}
"""
# coloca el dron a "dist" m del punto P (N, E, arriba), a "dh" m por encima, mirandolo, y avanza la fisica "s" segundos
APUNTAR = r"""
([P, dist, dh, s, zoom, termica, foto, desde]) => {
  const [N, E, up] = P, a = desde === undefined || desde === null ? 1.0 : desde + Math.PI, pn = N - dist * Math.cos(a), pe = E - dist * Math.sin(a), pu = up + dh;
  if (av.estado === "en mano") { lanzar(); modelo.despegar(av); }
  av.posado = false; av.despegado = true; av.rth = null; av.despegueAuto = false;
  DJI.zoomI = modelo.camara.zoom.indexOf(zoom); DJI.termica = termica;
  const T = [];
  for (let i = 0; i < Math.round(s / DT); i++) {
    av.p = [pn, pe, -pu]; av.v = [0, 0, 0]; av.w = [0, 0, 0];
    const yaw = Math.atan2(E - pe, N - pn); av.q = Cuat.desdeEuler(0, 0, yaw);
    av.gimbal = Math.atan2(up - pu, Math.hypot(N - pn, E - pe)) * R2D; av.hold = null;
    for (const t of ev.op.paso(av.p.slice(), av, DT, Object.assign({ gimbal: av.gimbal, grabando: false }, camDJI()))) T.push(t);
    av.t += DT;
  }
  if (foto) for (const t of ev.op.foto(av, av.gimbal, camDJI())) T.push(t);
  const est = k => ev.obj[k] ? ev.obj[k].estado : null;
  return { T, lectura: ev.op.lectura, calientes: est("calientes"), fuga: est("fuga"), atex: est("atex"), placa: est("placa"), piloto: est("piloto"), unidades: est("unidades"), defectos: est("defectos") };
}
"""
# rumbo (desde el objeto), altura sobre el, distancia y zoom desde los que el medidor ve el objeto P de ese tipo (sin
# estructuras delante; la fuga, desde fuera de la zona ATEX), o null. zoom null: 2x hasta 60 m y 4x mas lejos (los 256
# sitios posibles de la fuga tienen vista a 45-75 m)
BUSCAR_VISTA = r"""
([P, tipo, dists, zoom0, libre]) => {
  const [N, E, up] = P, U = ev.op.unidadFuga ? ev.op.unidadFuga.poligono : null;
  for (const dist of dists) for (const dh of [5, 8, 10, 15, 20, 30, 45, 60]) for (let k = 0; k < 24; k++) {
    const a = k * Math.PI / 12, pn = N + dist * Math.cos(a), pe = E + dist * Math.sin(a), pu = up + dh, zoom = zoom0 || (dist > 60 ? 4 : 2);
    if (!libre && U && (Operacion.dentro(U, pn, pe) || Operacion.aBorde(U, pn, pe) <= ev.op.d.atex)) continue;     // sin entrar en la ATEX
    const g = Math.atan2(up - pu, Math.hypot(N - pn, E - pe)) * R2D, q = Cuat.desdeEuler(0, 0, Math.atan2(E - pe, N - pn));
    const L = ev.op.medir({ p: [pn, pe, -pu], q }, g, zoom);
    if (L && L.tipo === tipo && Math.abs(L.dist - Math.hypot(dist, dh)) < 3) return [a, dh, dist, zoom];
  }
  return null;
}
"""
FOTO = r"""
(cam) => { visor.camara = cam; pantallaActual = null; visor.dibujar(av); hud(); visor.dibujar(av); hud(); pantallaActual = "prueba"; return [visor.cam.fov, visor.termica]; }
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
        pg = nav.new_page(viewport={"width": 1280, "height": 720}); errs = []; pg.on("pageerror", lambda e: errs.append(str(e)))
        pg.goto("http://127.0.0.1:%d/simulador.html" % srv.server_address[1]); pg.wait_for_function("typeof visor !== 'undefined' && visor && Modelos.ids().length > 0")
        ok("el Inspector HQ-3T esta en el hangar", pg.evaluate("idsHangar().includes('HQ3T') && Modelos.datos('HQ3T').nombre === 'Inspector HQ-3T'"))
        ok("se crea con la fisica del dron comercial", pg.evaluate("Modelos.crear('HQ3T').esCuadricoptero === true"))
        for op_id, dron in [("op_inspeccion", "DJI_MINI"), ("op_video", "DJI_MINI"), ("op_paneles", "HQ3T")]:
            r = pg.evaluate(PREP, op_id); ok("%s sale con %s" % (op_id, dron), r["avion"] == dron, str(r))
        # ---- paneles: cristal roto (solo camara normal), excrementos (las dos) y diodo de bypass (solo termica)
        r = pg.evaluate("[ev.op.modulos.length, ev.op.modulosC.length]"); ok("paneles: 6 modulos danados a simple vista y 3 diodos averiados", r == [6, 3], str(r))
        Pm = pg.evaluate("ev.op.modulosC[0]")
        r = pg.evaluate(APUNTAR, [Pm, 0.01, 12, 0.1, 1, False, True]); ok("diodo: sin termica no vale", not any("Diodo" in t for t in r["T"]), str(r["T"]))
        r = pg.evaluate(APUNTAR, [Pm, 0.01, 12, 0.1, 1, True, True]); ok("diodo: con termica vale", any("Diodo de bypass averiado 1" in t for t in r["T"]), str(r["T"]))
        Pr, Pe = pg.evaluate("ev.op.modulos.slice(0, 2)")
        r = pg.evaluate(APUNTAR, [Pr, 0.01, 12, 0.1, 1, True, True]); ok("cristal roto: con termica no vale", not any("Cristal roto" in t for t in r["T"]), str(r["T"]))
        r = pg.evaluate(APUNTAR, [Pr, 0.01, 12, 0.1, 1, False, True]); ok("cristal roto: con la camara normal vale", any("Cristal roto (módulo 1)" in t for t in r["T"]), str(r["T"]))
        r = pg.evaluate(APUNTAR, [Pe, 0.01, 12, 0.1, 1, True, True]); ok("excrementos: con termica vale (punto caliente)", any("Excrementos de aves (módulo 2), punto caliente" in t for t in r["T"]), str(r["T"]))
        if salida: pg.evaluate(FOTO, 3); pg.screenshot(path=str(salida / "paneles_termica.png"))
        # ---- fabrica
        r = pg.evaluate(PREP, "op_sabic"); ok("op_sabic sale con el HQ3T y sus objetos termicos", r["avion"] == "HQ3T" and r["termicos"] > 10, str(r))
        H_ = pg.evaluate("ev.op.termicos.filter(o => o.tipo === 'caliente').map(o => [(o.P0[0] + o.P1[0]) / 2, (o.P0[1] + o.P1[1]) / 2, (o.P0[2] + o.P1[2]) / 2])")
        a, dh, _, _ = pg.evaluate(BUSCAR_VISTA, [H_[0], "caliente", [40], 4]) or pg.evaluate(BUSCAR_VISTA, [H_[0], "caliente", [40], 4, True])     # una vista libre a 40 m
        r = pg.evaluate(APUNTAR, [H_[0], 40, dh, 3.2, 1, True, False, a]); ok("punto caliente a 40 m sin zoom: no se mide", not any("Punto caliente" in t for t in r["T"]) and r["calientes"] != "ok", str(r["T"]))      # pide acercarse (o la cruz cae antes en el vapor)
        r = pg.evaluate(APUNTAR, [H_[0], 40, dh, 3.2, 4, True, False, a]); ok("con 4x de zoom se mide en 3 s", any("Punto caliente 1" in t for t in r["T"]), str(r["T"]) + " " + str(r["lectura"]))
        if salida: pg.evaluate(FOTO, 3); pg.screenshot(path=str(salida / "sabic_caliente_termica.png"))
        for k in range(1, len(H_)):
            a, dh, _, _ = pg.evaluate(BUSCAR_VISTA, [H_[k], "caliente", [12], 1]) or pg.evaluate(BUSCAR_VISTA, [H_[k], "caliente", [12], 1, True]); r = pg.evaluate(APUNTAR, [H_[k], 12, dh, 3.2, 1, True, False, a])
        ok("los 4 puntos calientes medidos", r["calientes"] == "ok", str(r["calientes"]))
        V = pg.evaluate("ev.op.valvula")
        vista = pg.evaluate(BUSCAR_VISTA, [V, "fuga", [45, 60, 75, 90], None])                         # un sitio con la valvula a la vista, fuera de la ATEX
        ok("hay desde donde ver la fuga sin entrar en la ATEX", vista is not None, str(vista))
        atex0 = pg.evaluate("ev.obj.atex.estado")                    # (un punto caliente pegado a la ATEX puede haber obligado a entrar)
        a, dh, dist, zoom = vista
        r = pg.evaluate(APUNTAR, [V, dist, dh, 3.2, zoom, True, False, a]); ok("fuga desde fuera de la zona ATEX con zoom %dx" % zoom, r["fuga"] == "ok" and (r["atex"] != "mal" or atex0 == "mal"), str(r["T"]) + " atex " + str(r["atex"]))
        if salida: pg.evaluate(FOTO, 3); pg.screenshot(path=str(salida / "sabic_fuga_termica.png"))
        Pl = pg.evaluate("ev.op.placa.slice(0, 3)"); A = pg.evaluate("[ev.op.d.antorcha.n, ev.op.d.antorcha.e, ev.op.boca[2]]")
        suelo_pl = pg.evaluate("entorno.altura(ev.op.d.antorcha.n, ev.op.d.antorcha.e)")
        rp = pg.evaluate("ev.op.placa[3] * Math.PI / 180")              # la cara de la placa (hacia el despegue)
        r = pg.evaluate(APUNTAR, [Pl, 80, 0, 0.1, 28, False, True, rp + math.pi]); ok("placa desde el otro lado: no se ve", any("este lado" in t for t in r["T"]), str(r["T"]))
        r = pg.evaluate(APUNTAR, [Pl, 80, 0, 0.1, 14, False, True, rp]); ok("placa con 14x: no se lee", any("28x" in t for t in r["T"]), str(r["T"]))
        dh = 75 + suelo_pl - Pl[2]                                     # a 75 m sobre el suelo
        r = pg.evaluate(APUNTAR, [Pl, 80, dh, 0.1, 28, False, True, rp]); ok("placa con 28x desde 80 m y a 75 m de altura", r["placa"] == "ok", str(r["T"]))
        if salida: pg.evaluate(FOTO, 3); pg.screenshot(path=str(salida / "sabic_placa_zoom28.png"))
        r = pg.evaluate(APUNTAR, [A, 60, 10, 0.1, 2, False, True]); ok("piloto sin termica: la pide", any("térmica" in t for t in r["T"]), str(r["T"]))
        r = pg.evaluate(APUNTAR, [A, 60, 10, 0.1, 2, True, True]); ok("piloto con la termica", r["piloto"] == "ok", str(r["T"]))
        if salida: pg.evaluate(FOTO, 3); pg.screenshot(path=str(salida / "sabic_antorcha_termica.png"))
        r = pg.evaluate(APUNTAR, [V, 5, 2, 0.2, 1, True, False]); ok("entrar en la zona ATEX se marca", r["atex"] == "mal", str(r["atex"]))
        # orden del profesor: la fuga pasa a la unidad mas cercana al clic y hay que volver a localizarla
        r = pg.evaluate("""() => {
          const U = ev.op.d.unidades.find(u => u !== ev.op.unidadFuga), c = U.poligono.reduce((s, q) => [s[0] + q[0] / U.poligono.length, s[1] + q[1] / U.poligono.length], [0, 0]);
          ORDENES.reiniciar(); aplicarOrdenes([{ n: 1, tipo: "fuga", N: c[0], E: c[1], edad: 0 }]);
          return [U.nombre, ev.op.unidadFuga.nombre, ev.obj.fuga.estado, ev.op.termicos.filter(o => o.tipo === "fuga").length];
        }""")
        ok("orden del profesor: la fuga pasa a otra unidad y hay que localizarla de nuevo", r[0] == r[1] and r[2] == "pend" and r[3] == 1, str(r))
        for op_id, dron in [("op_inspeccion", "DJI_MINI"), ("op_sabic", "HQ3T"), ("op_fotogrametria", "DJI_MINI"), ("op_paneles", "HQ3T"), ("op_busqueda", "DJI_MINI"), ("op_agricultura", "DJI_MINI")]:
            r = pg.evaluate(PREP, op_id); ok("%s (despues de otro trabajo) sale con %s" % (op_id, dron), r["avion"] == dron, str(r))
        ok("sin errores en la pagina", not errs, errs[:3])
        nav.close()
    srv.shutdown()
    print("RESULTADO:", "todo bien" if not fallos else "%d fallos" % fallos)
    sys.exit(1 if fallos else 0)


if __name__ == "__main__":
    main()
