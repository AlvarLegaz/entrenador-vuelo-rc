"""Prueba de los logros en el simulador del navegador, con un servidor del aula de prueba (su propia carpeta de datos): un
piloto con solo el logro de ala fija ve en Mi progreso las tres insignias y la del robot (una conseguida, el robot con
candado) y no tiene el robot en el hangar (aunque lo tuviera elegido); al conseguir los otros dos, el robot sale en el
hangar y el aviso del ultimo vuelo lo dice. Con una carpeta, guarda capturas del perfil (antes y despues). Escribe
pruebas/referencia_logros_js.json (las insignias, los avisos y un progreso) para prueba_logros.gd.

    python simulador_godot/pruebas/prueba_logros_web.py [carpeta de las capturas]
"""
import json, pathlib, shutil, subprocess, sys, tempfile, time, urllib.error, urllib.request, uuid
from playwright.sync_api import sync_playwright

REPO = pathlib.Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(REPO / "aula"))
PUERTO = 8099
BASE = "http://127.0.0.1:%d" % PUERTO
fallos = 0


def ok(nombre, cond, detalle=""):
    global fallos
    if not cond: fallos += 1
    print("  %s %s %s" % ("OK " if cond else "MAL", nombre, detalle))


def pedir(metodo, ruta, cuerpo=None, pase=None):
    datos = json.dumps(cuerpo).encode() if cuerpo is not None else None
    req = urllib.request.Request(BASE + ruta, data=datos, method=metodo)
    if datos is not None: req.add_header("Content-Type", "application/json")
    if pase: req.add_header("X-Alumno", pase)
    try:
        with urllib.request.urlopen(req, timeout=10) as r: return r.status, json.loads(r.read().decode("utf-8"))
    except urllib.error.HTTPError as e: return e.code, e.read().decode("utf-8", "replace")
    except (urllib.error.URLError, OSError) as e: return 0, str(e)


ENTRAR = r"""
async ([base, alumno, pase]) => {
  window.requestAnimationFrame = cb => setTimeout(() => cb(performance.now()), 5);
  try { localStorage.setItem("evrc_url_aula", base); } catch (e) {}
  await dentroDelAula(alumno, pase); irInicio();
}
"""
PERFIL = r"""
async () => {
  await irProgreso("pInicio");
  await new Promise(r => { const f = () => document.querySelectorAll("#progContenido .logro").length ? r() : setTimeout(f, 100); f(); });
  const L = [...document.querySelectorAll("#progContenido .logro")];
  return { n: L.length, ok: L.map(x => x.classList.contains("ok")), titulos: L.map(x => x.querySelector("h3").textContent),
           candado: L[3].innerHTML.includes("#ffd54f\" stroke-width=\"3.5\""), asalto: document.getElementById("progContenido").innerText.toLowerCase().includes("asalto"), hangar: idsHangar().includes("BIPODE") };
}
"""


def main():
    global fallos
    salida = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else None
    if salida: salida.mkdir(parents=True, exist_ok=True)
    import servidor_aula as sa
    datos = tempfile.mkdtemp(prefix="aula_logros_web_")
    sa.usar_datos(datos); sa.crear_bd()
    con = sa.conectar()
    with con: con.execute("INSERT OR REPLACE INTO config (clave, valor) VALUES ('pin', ?)", (sa.hash_pin("2468"),))
    con.close()
    pr = subprocess.Popen([sys.executable, str(REPO / "aula" / "servidor_aula.py"), "--puerto", str(PUERTO), "--datos", datos],
                          stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        for _ in range(100):
            if pedir("GET", "/api/estado")[0] == 200: break
            time.sleep(0.1)
        else: raise SystemExit("el servidor de prueba no arranca")
        pruebas(sa, salida)
    finally:
        pr.kill(); pr.wait(); shutil.rmtree(datos, ignore_errors=True)
    print("RESULTADO:", "todo bien" if not fallos else "%d fallos" % fallos)
    sys.exit(1 if fallos else 0)


def pruebas(sa, salida):
    K = sa.catalogo_logros()
    c, a = pedir("POST", "/api/entrar", {"usuario": "Piloto web", "clave": "abcd", "crear": True})
    pase, aid = a["pase"], a["alumno"]["id"]; n = [0]

    def vuelo(avion, escenario, minutos):
        n[0] += 1
        c, r = pedir("POST", "/api/vuelos", {"id": str(uuid.uuid4()), "alumno_id": aid, "inicio": "2026-10-15T%02d:%02d:00" % (8 + n[0] // 60, n[0] % 60),
                                            "avion": avion, "escenario": escenario, "resultado": "APTO", "tiempo_vuelo_s": minutos * 60}, pase=pase)
        assert c in (200, 201), (c, r)
        return r["progreso"]
    for e in K["ala"]: vuelo("E3", e, 14)                            # ala fija: 9 x 14 min > 2 h
    for e in K["dron"][:3]: vuelo("DJI_MINI", e, 10)                 # dron: a medias
    with sync_playwright() as p:
        nav = p.chromium.launch(channel="chrome", headless=True, args=["--use-angle=swiftshader", "--enable-unsafe-swiftshader"])
        pg = nav.new_page(viewport={"width": 1360, "height": 900}); errs = []; pg.on("pageerror", lambda e: errs.append(str(e)))
        import http.server, socketserver, threading                 # el simulador, servido aparte (el aula sirve el panel del profesor)
        class H(http.server.SimpleHTTPRequestHandler):
            def log_message(self, *a): pass
            def __init__(self, *a, **k): super().__init__(*a, directory=str(REPO / "simulador"), **k)
        srv = socketserver.ThreadingTCPServer(("127.0.0.1", 0), H); srv.daemon_threads = True; threading.Thread(target=srv.serve_forever, daemon=True).start()
        pg.goto("http://127.0.0.1:%d/simulador.html" % srv.server_address[1]); pg.wait_for_function("typeof visor !== 'undefined' && visor && Modelos.ids().length > 0")
        c, a = pedir("GET", "/api/alumnos/" + aid)
        pg.evaluate(ENTRAR, [BASE, a, pase])
        r = pg.evaluate(PERFIL)
        ok("Mi progreso: tres logros y el robot", r["n"] == 4 and r["titulos"][:3] == ["Piloto de ala fija", "Piloto de dron", "Operador profesional"], str(r["titulos"]))
        ok("solo el de ala fija conseguido y el robot con candado", r["ok"] == [True, False, False, False] and r["candado"], str(r["ok"]))
        ok("el robot no esta en el hangar", not r["hangar"])
        ok("la tarjeta del robot no dice que es (Vehiculo secreto, sin 'asalto')", r["titulos"][3] == "Vehículo secreto" and not r["asalto"], r["titulos"][3])
        txt = pg.inner_text("#progContenido")
        ok("el del dron dice lo que falta", "3 de 6" in txt and "Te falta:" in txt)
        if salida: pg.screenshot(path=str(salida / "web_logros_antes.png"), full_page=True)
        pg.evaluate("() => { elegirAvion('BIPODE'); irHangar(); }")
        ok("con el robot elegido sin los logros, el hangar vuelve al dron", pg.evaluate("sesion.avion") == "DJI_MINI", pg.evaluate("sesion.avion"))
        # los otros dos logros (el ultimo vuelo lo manda la pagina: el aviso del resultado)
        antes = pg.evaluate("sesion.alumno.progreso")
        for e in K["dron"][3:]: vuelo("DJI_MINI", e, 10)
        vuelo("FPV", "libre", 90)
        for e in K["operaciones"]: g = vuelo("HQ3T", e, 1)
        avisos = pg.evaluate("([a, b]) => logrosNuevos(a, b)", [antes, g])
        ok("el aviso del vuelo: dos logros nuevos y el robot", len(avisos) == 3 and "Piloto de dron" in avisos[0] and "Vehículo secreto desbloqueado" in avisos[2], str(avisos))
        r = pg.evaluate(PERFIL)
        ok("con los tres: todas las insignias en color y el robot desbloqueado", all(r["ok"]) and not r["candado"], str(r["ok"]))
        ok("y el robot ya esta en el hangar", r["hangar"])
        if salida: pg.screenshot(path=str(salida / "web_logros_despues.png"), full_page=True)
        ref = pg.evaluate("""([a, b]) => ({ insignias: Object.fromEntries(["ala_fija", "dron", "operaciones", "robot"].flatMap(id => [true, false].map(ok => [id + (ok ? "_si" : "_no"), insigniaSvg(id, ok)]))),
                                            nuevos: logrosNuevos(a, b), antes: a, progreso: b })""", [antes, g])
        json.dump(ref, open(REPO / "simulador_godot" / "pruebas" / "referencia_logros_js.json", "w", encoding="utf-8"), ensure_ascii=False, indent=1)   # para prueba_logros.gd
        pg.evaluate("() => { salirDelAula(); irInicio(); }")
        ok("sin conexion, sin robot", not pg.evaluate("idsHangar().includes('BIPODE')"))
        ok("sin errores en la pagina", not errs, errs[:3])
        nav.close()


if __name__ == "__main__":
    main()
