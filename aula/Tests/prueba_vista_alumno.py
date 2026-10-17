"""Prueba de la vista del alumno del panel del profesor (aula/profesor.html + espectador.html, el simulador en modo
espectador servido por el aula): levanta un servidor del aula de prueba (PIN 2468) con una sala, un "alumno" que vuela en
circulo mandando su estado como el simulador (con la camara 3 y zoom 2) y otro piloto quieto; en el panel, "Ver" abre la
vista del alumno en lugar del mapa: sigue a ese piloto (su vehiculo, su camara y su zoom, y el otro como fantasma) y
"Mapa" la cierra. Sin el PIN, espectador.html no ensena nada. Con una carpeta, guarda capturas del panel.

    python aula/Tests/prueba_vista_alumno.py [carpeta de las capturas]
"""
import json, math, pathlib, shutil, subprocess, sys, tempfile, threading, time, urllib.error, urllib.request
from playwright.sync_api import sync_playwright

REPO = pathlib.Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(REPO / "aula"))
PUERTO = 8096
BASE = "http://127.0.0.1:%d" % PUERTO
fallos = 0


def ok(nombre, cond, detalle=""):
    global fallos
    if not cond: fallos += 1
    print("  %s %s %s" % ("OK " if cond else "MAL", nombre, detalle))


def pedir(metodo, ruta, cuerpo=None, token=None):
    datos = json.dumps(cuerpo).encode() if cuerpo is not None else None
    req = urllib.request.Request(BASE + ruta, data=datos, method=metodo)
    if datos is not None: req.add_header("Content-Type", "application/json")
    if token: req.add_header("Authorization", "Bearer " + token)
    try:
        with urllib.request.urlopen(req, timeout=10) as r: return r.status, json.loads(r.read().decode("utf-8"))
    except urllib.error.HTTPError as e: return e.code, e.read().decode("utf-8", "replace")


def main():
    salida = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else None
    if salida: salida.mkdir(parents=True, exist_ok=True)
    import servidor_aula as sa
    datos = tempfile.mkdtemp(prefix="aula_vista_")
    sa.usar_datos(datos); sa.crear_bd()
    con = sa.conectar()
    with con: con.execute("INSERT OR REPLACE INTO config (clave, valor) VALUES ('pin', ?)", (sa.hash_pin("2468"),))
    con.close()
    pr = subprocess.Popen([sys.executable, str(REPO / "aula" / "servidor_aula.py"), "--puerto", str(PUERTO), "--datos", datos], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    vuela = threading.Event(); vuela.set()
    try:
        for _ in range(100):
            if pedir("GET", "/api/estado")[0] == 200: break
            time.sleep(0.1)
        c, d = pedir("POST", "/api/profesor/entrar", {"pin": "2468"}); tok = d["token"]
        c, s = pedir("POST", "/api/salas", {"escenario": "op_carrera", "nombre": "Clase"}, tok); cod = s["codigo"]
        # el alumno: vuela en circulo de 30 m de radio sobre el aparcamiento del CIFP a 12 m, con la camara 3 y zoom 2
        def alumno():
            t0 = time.time()
            while vuela.is_set():
                t = time.time() - t0; a = 0.25 * t
                p = [58 + 30 * math.cos(a), 6653 + 30 * math.sin(a), 61]
                yaw = a + math.pi / 2; q = [math.cos(yaw / 2), 0, 0, math.sin(yaw / 2)]
                pedir("POST", "/api/salas/%s/estado" % cod, {"id": "ana", "nombre": "Ana", "avion": "HQ3T", "p": p, "q": q, "vn": [-7.5 * math.sin(a), 7.5 * math.cos(a), 0],
                                                            "estado": "volando", "gas": 0.5, "agl": 12, "gimbal": -30, "cam": 3, "zoom": 2, "ter": False, "objs": [1, 4, 0],
                                                            "ahora": "Tiempo: 0:12,0 · siguiente: obstáculo 2 de 19"})
                pedir("POST", "/api/salas/%s/estado" % cod, {"id": "bea", "nombre": "Bea", "avion": "FPV", "p": [70, 6670, 64], "q": [1, 0, 0, 0], "estado": "volando", "cam": 2})
                time.sleep(0.1)
        threading.Thread(target=alumno, daemon=True).start()
        time.sleep(0.5)
        c, r = pedir("GET", "/api/salas/" + cod, token=tok); J = {j["id"]: j for j in r["jugadores"]}
        ok("el servidor guarda lo que ve el piloto (camara, zoom, termica)", J["ana"].get("cam") == 3 and J["ana"].get("zoom") == 2 and J["ana"].get("ter") is False, str({k: J["ana"].get(k) for k in ("cam", "zoom", "ter")}))
        c, r = pedir("POST", "/api/salas/%s/estado" % cod, {"id": "x", "nombre": "X", "avion": "FPV", "p": [0, 0, 0], "q": [1, 0, 0, 0], "cam": 9, "zoom": 1e9})
        ok("valores raros (camara 9, zoom enorme) se rechazan", c == 400, str(c))
        with urllib.request.urlopen(BASE + "/espectador.html", timeout=10) as rr: html = rr.read().decode("utf-8")
        ok("el aula sirve espectador.html (el simulador en modo espectador)", "ESPECTADOR" in html)
        try: urllib.request.urlopen(BASE + "/simulador.html", timeout=10); redir = urllib.request.urlopen(BASE + "/simulador.html").geturl().endswith("profesor.html")
        except urllib.error.HTTPError: redir = False
        ok("y simulador.html sigue llevando al panel (el aula no es para volar)", redir)
        with sync_playwright() as p:
            nav = p.chromium.launch(channel="chrome", headless=True, args=["--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist"])
            pg = nav.new_page(viewport={"width": 1500, "height": 950}); errs = []; pg.on("pageerror", lambda e: errs.append(str(e))); pg.on("console", lambda m: errs.append("consola: " + m.text + " " + str(m.location.get("url"))) if m.type == "error" and "favicon" not in str(m.location.get("url")) else None)
            pg.goto(BASE + "/profesor.html"); pg.fill("#pin", "2468"); pg.click("#entrar")
            pg.click('.pestanas button[data-p="multi"]'); pg.wait_for_selector('#tJugadores button[data-ver="ana"]', timeout=20000)
            ok("la tabla tiene un boton Ver por piloto", pg.locator("#tJugadores button[data-ver]").count() == 2)
            ok("al principio, el mapa", pg.is_visible("#mMapa") and not pg.is_visible("#mVista"))
            pg.click('#tJugadores button[data-ver="ana"]')
            ok("Ver: la vista del alumno en lugar del mapa", pg.is_visible("#mVista") and not pg.is_visible("#mMapa") and "Ana" in pg.inner_text("#vQuien"))
            for _ in range(100):
                f = next((x for x in pg.frames if "espectador.html" in x.url), None)
                if f: break
                time.sleep(0.1)
            f.wait_for_function("typeof ESP !== 'undefined' && ESP.est && typeof av !== 'undefined' && av && pantallaActual === null && visor && visor.camara === 3", timeout=120000)
            time.sleep(1.5)
            r = f.evaluate("({ p: av.p, est: ESP.est.p, avion: sesion.avion, cam: visor.camara, zoom: visor.zoomCam, barra: document.getElementById('espBar').innerText, fant: visor.fantasmas ? [...visor.fantasmas.keys()] : [], obst: (visor.carreraObst || []).length })")
            d = math.dist(r["p"], r["est"])
            ok("sigue al piloto (a menos de 3 m de su ultimo estado)", d < 3, "%.1f m" % d)
            ok("con su vehiculo, su camara y su zoom", r["avion"] == "HQ3T" and r["cam"] == 3 and r["zoom"] == 2, "%s cam %s zoom %s" % (r["avion"], r["cam"], r["zoom"]))
            ok("el otro piloto, como fantasma; los obstaculos de la carrera", r["fant"] == ["bea"] and r["obst"] == 19, "%s %s" % (r["fant"], r["obst"]))
            ok("la barra dice a quien se ve y que hace", "Ana" in r["barra"] and "Inspector HQ-3T" in r["barra"] and "siguiente: obstáculo 2" in r["barra"], r["barra"].replace("\n", " / "))
            if salida: pg.screenshot(path=str(salida / "panel_vista_alumno.png"))
            p1 = f.evaluate("av.p.slice()"); time.sleep(1.0); p2 = f.evaluate("av.p.slice()")
            ok("y se mueve con el (en directo)", math.dist(p1, p2) > 3, "%.1f m en 1 s" % math.dist(p1, p2))
            pg.click("#vMapa")
            ok("Mapa: vuelve el mapa y la vista se cierra", pg.is_visible("#mMapa") and not pg.is_visible("#mVista"))
            pg.click("#vAlumno")
            ok("Vista del alumno: vuelve a la del ultimo piloto", pg.is_visible("#mVista") and "Ana" in pg.inner_text("#vQuien"))
            ok("sin errores en el panel", not errs, errs[:3])
            # sin el PIN (otra ventana sin el pase del profesor): no ensena nada
            pg2 = nav.new_page(); pg2.goto(BASE + "/espectador.html?sala=%s&piloto=ana" % cod)
            pg2.wait_for_function("typeof ESP !== 'undefined' && document.getElementById('espBar').innerText.length > 5", timeout=60000)
            txt = pg2.inner_text("#espBar")
            ok("sin el PIN del profesor, espectador.html no ensena nada", "Solo el profesor" in txt and pg2.evaluate("!ESP.est"), txt)
            nav.close()
    finally:
        vuela.clear(); pr.kill(); pr.wait(); shutil.rmtree(datos, ignore_errors=True)
    print("RESULTADO:", "todo bien" if not fallos else "%d fallos" % fallos)
    sys.exit(1 if fallos else 0)


if __name__ == "__main__":
    main()
