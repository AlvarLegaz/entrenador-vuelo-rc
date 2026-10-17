"""Prueba del registro de alumnos nuevos de punta a punta, con un servidor del aula de prueba (datos temporales, PIN 2468):
en la web, el acceso con un usuario que no existe ofrece el registro; la pagina de registro (aparte, en dos columnas y en
una en el movil) comprueba el correo del centro y las dos contrasenas y envia la solicitud; la cuenta pendiente no entra;
en el panel del profesor sale en "Solicitudes de registro" con sus datos y se aprueba; y ya entra. Despues Godot
(simulador_godot/Tests/prueba_acceso.gd, con ventana) hace lo mismo con su pantalla de registro contra la misma aula.
Los datos de usuario de Godot se dejan como estaban.

    python aula/Tests/prueba_registro.py
"""
import http.server, json, os, pathlib, shutil, socketserver, subprocess, sys, tempfile, threading, time, urllib.request
from playwright.sync_api import sync_playwright

REPO = pathlib.Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(REPO / "aula"))
GODOT = REPO / "herramientas" / "godot" / "Godot_v4.7.2-stable_win64_console.exe"
PUERTO = 8095
BASE = "http://127.0.0.1:%d" % PUERTO
DATOS_GODOT = pathlib.Path(os.environ["APPDATA"]) / "Godot" / "app_userdata" / "Entrenador Vuelo RC v2 (Godot)"
fallos = 0


def ok(nombre, cond, detalle=""):
    global fallos
    if not cond: fallos += 1
    print("  %s %s %s" % ("OK " if cond else "MAL", nombre, detalle))


def main():
    import servidor_aula as sa
    datos = tempfile.mkdtemp(prefix="aula_registro_")
    sa.usar_datos(datos); sa.crear_bd()
    con = sa.conectar()
    with con: con.execute("INSERT OR REPLACE INTO config (clave, valor) VALUES ('pin', ?)", (sa.hash_pin("2468"),))
    con.close()
    copia = tempfile.mkdtemp(prefix="godot_datos_")             # prueba_acceso.gd guarda la direccion y el usuario en user://aula.cfg
    for f in list(DATOS_GODOT.glob("*.cfg")) + list(DATOS_GODOT.glob("*.json")): shutil.copy2(f, copia)
    antes = {f.name for f in DATOS_GODOT.iterdir() if f.is_file()}
    pr = subprocess.Popen([sys.executable, str(REPO / "aula" / "servidor_aula.py"), "--puerto", str(PUERTO), "--datos", datos], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        for _ in range(100):
            try: urllib.request.urlopen(BASE + "/api/estado", timeout=2); break
            except Exception: time.sleep(0.1)
        web()
        godot()
    finally:
        pr.kill(); pr.wait(); shutil.rmtree(datos, ignore_errors=True)
        for f in DATOS_GODOT.iterdir():
            if f.is_file() and f.name not in antes and f.suffix in (".cfg", ".json"): f.unlink()
        for f in pathlib.Path(copia).glob("*.*"): shutil.copy2(f, DATOS_GODOT)
        shutil.rmtree(copia, ignore_errors=True)
    print("RESULTADO:", "todo bien" if not fallos else "%d fallos" % fallos)
    sys.exit(1 if fallos else 0)


def web():
    class H(http.server.SimpleHTTPRequestHandler):
        def __init__(s, *a, **k): super().__init__(*a, directory=str(REPO), **k)
        def log_message(s, *a): pass
    srv = socketserver.ThreadingTCPServer(("127.0.0.1", 0), H); srv.daemon_threads = True
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    with sync_playwright() as p:
        nav = p.chromium.launch(channel="chrome", headless=True, args=["--use-angle=swiftshader", "--enable-unsafe-swiftshader"])
        pg = nav.new_page(viewport={"width": 1280, "height": 800}); errs = []; pg.on("pageerror", lambda e: errs.append(str(e)))
        pg.goto("http://127.0.0.1:%d/simulador_web/simulador.html" % srv.server_address[1]); pg.wait_for_function("typeof visor !== 'undefined' && visor && Modelos.ids().length > 0")
        pg.evaluate("irAcceso()"); pg.fill("#urlAula", BASE); pg.fill("#accUsuario", "Marta Web"); pg.fill("#accClave", "abcd"); pg.click("#btnEntrar")
        pg.wait_for_selector("#modal.activa", timeout=10000)
        ok("web: usuario que no existe: ofrece el registro", "Registrarte" in pg.inner_text("#modTitulo"), pg.inner_text("#modTitulo"))
        pg.click("#modSi"); pg.wait_for_selector("#pRegistro.activa")
        ok("web: pagina de registro aparte, con el usuario ya puesto", pg.input_value("#regUsuario") == "Marta Web" and BASE in pg.inner_text("#regAula"))
        dos = pg.evaluate("getComputedStyle(document.querySelector('.regCols')).gridTemplateColumns.split(' ').length")
        ok("web: en dos columnas", dos == 2, str(dos))
        pg.set_viewport_size({"width": 380, "height": 800}); pg.wait_for_timeout(200)
        una = pg.evaluate("getComputedStyle(document.querySelector('.regCols')).gridTemplateColumns.split(' ').length")
        ok("web: en el movil, en una columna", una == 1, str(una))
        pg.set_viewport_size({"width": 1280, "height": 800})
        for k, v in {"#regNombre": "Marta", "#regApellidos": "Web Prueba", "#regCorreo": "marta@gmail.com", "#regClave": "abcd", "#regClave2": "abcd"}.items(): pg.fill(k, v)
        pg.click("#btnRegistrar"); ok("web: solo el correo del centro", "alu.murciaeduca.es" in pg.inner_text("#errRegistro"), pg.inner_text("#errRegistro"))
        pg.fill("#regCorreo", "marta.web@alu.murciaeduca.es"); pg.fill("#regClave2", "otra"); pg.click("#btnRegistrar")
        ok("web: las contrasenas tienen que coincidir", "no coinciden" in pg.inner_text("#errRegistro"), pg.inner_text("#errRegistro"))
        pg.fill("#regClave2", "abcd"); pg.click("#btnRegistrar"); pg.wait_for_selector("#pAlumno.activa", timeout=10000)
        ok("web: solicitud enviada: vuelve al acceso con el aviso", "Solicitud enviada" in pg.inner_text("#errAlumno") and pg.input_value("#accUsuario") == "Marta Web", pg.inner_text("#errAlumno"))
        pg.fill("#accClave", "abcd"); pg.click("#btnEntrar"); pg.wait_for_function("/pendiente/.test(document.getElementById('errAlumno').textContent)", timeout=10000)
        ok("web: pendiente: no entra", pg.evaluate("pantallaActual") == "pAlumno" and not pg.evaluate("sesion.aula"), pg.inner_text("#errAlumno"))
        # el profesor la aprueba en su panel
        pp = nav.new_page(viewport={"width": 1400, "height": 900}); errp = []; pp.on("pageerror", lambda e: errp.append(str(e)))
        pp.goto(BASE + "/profesor.html"); pp.fill("#pin", "2468"); pp.click("#entrar"); pp.wait_for_selector("#tSolicitudes tr td", timeout=10000)
        sol = pp.inner_text("#tSolicitudes")
        ok("panel: la solicitud con sus datos", "Marta Web" in sol and "Marta Web Prueba" in sol and "marta.web@alu.murciaeduca.es" in sol, sol.replace("\n", " | ")[:200])
        ok("panel: no sale en la lista de alumnos hasta aprobarla", "Marta Web" not in pp.inner_text("#tAlumnos"))
        pp.click("#tSolicitudes button[data-a=aprobar]"); pp.wait_for_function("document.getElementById('solicitudes').style.display === 'none'", timeout=10000)
        ok("panel: aprobada: sale en la lista de alumnos con su correo", "Marta Web" in pp.inner_text("#tAlumnos") and "marta.web@alu.murciaeduca.es" in pp.inner_text("#tAlumnos"))
        ok("panel: sin errores", not errp, errp[:2])
        pg.fill("#accClave", "abcd"); pg.click("#btnEntrar"); pg.wait_for_function("sesion.aula === true", timeout=10000)
        ok("web: aprobada: entra en el aula", pg.evaluate("[pantallaActual, sesion.alumno && sesion.alumno.nombre]") == ["pInicio", "Marta Web"])
        ok("web: sin errores en la pagina", not errs, errs[:3])
        nav.close()
    srv.shutdown()


def godot():
    g = subprocess.run([str(GODOT), "--path", str(REPO / "simulador_godot"), "--resolution", "1280x800", "--script", "res://Tests/prueba_acceso.gd", "--",
                        "--aula=" + BASE, "--pin=2468"], capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=600)
    L = [l for l in g.stdout.splitlines() if l.startswith(("OK", "MAL", "FALLOS"))]
    for l in L:
        if l.startswith(("OK", "MAL")): ok("Godot: " + l[5:].strip(), l.startswith("OK"))
    ok("Godot: la prueba de acceso termina", any(l.startswith("FALLOS 0") for l in L), "\n".join(g.stdout.splitlines()[-5:]))


if __name__ == "__main__":
    main()
