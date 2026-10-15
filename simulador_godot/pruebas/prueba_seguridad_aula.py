"""Bateria de pruebas de seguridad del servidor del aula (aula/servidor_aula.py), del panel del profesor
(simulador/profesor.html) y del cliente web (simulador/simulador.html) frente a un alumno "curioso" de la red del aula.
Levanta un servidor de prueba con su propia carpeta de datos (PIN 2468) y, con Playwright, abre el panel del profesor y
el simulador como lo haria cada uno. Cada prueba imprime OK o MAL; al final, "RESULTADO: todo bien" si no hay fallos.

Lo que comprueba:
  - XSS: vuelos y estados de multijugador con HTML dentro no ejecutan nada ni en el panel ni en el simulador de los demas.
  - Robustez: estados de multijugador mal formados (p null, avion raro, numeros infinitos) no rompen el panel (el boton
    Expulsar sigue), ni el bucle del simulador de los companeros.
  - Fuerza bruta: 40 intentos de PIN a la vez solo calculan 5; los demas reciben 429 (esta prueba va la ultima: bloquea la IP).
  - Peticiones malas: Content-Length negativo, no numerico o enorme; un cliente que no manda el cuerpo no congela las salas.
  - Datos: horas de vuelo infinitas o absurdas se rechazan; las notas privadas y la IP de los jugadores no salen sin PIN;
    el CSV neutraliza formulas; limites de jugadores y de tamanos en las salas.
  - Lo que ya estaba bien (regresion): sin PIN no se expulsa ni se cierra una sala; no se sale de simulador/ al pedir ficheros.

    python simulador_godot/pruebas/prueba_seguridad_aula.py [puerto]      (por defecto 8097)
"""
import http.client, json, os, pathlib, shutil, socket, subprocess, sys, tempfile, threading, time, urllib.error, urllib.request
from concurrent.futures import ThreadPoolExecutor

REPO = pathlib.Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(REPO / "aula"))
PUERTO = int(sys.argv[1]) if len(sys.argv) > 1 else 8097
BASE = "http://127.0.0.1:%d" % PUERTO
PIN = "2468"
fallos = 0


def ok(nombre, cond, detalle=""):
    global fallos
    if not cond: fallos += 1
    print("  %s %s %s" % ("OK " if cond else "MAL", nombre, detalle))


def pedir(metodo, ruta, cuerpo=None, token=None, pase=None, crudo=False, timeout=10):
    """Devuelve (codigo, json o texto)."""
    datos = json.dumps(cuerpo).encode() if cuerpo is not None else None
    req = urllib.request.Request(BASE + ruta, data=datos, method=metodo)
    if datos is not None: req.add_header("Content-Type", "application/json")
    if token: req.add_header("Authorization", "Bearer " + token)
    if pase: req.add_header("X-Alumno", pase)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            b = r.read()
            if crudo: return r.status, b
            try: return r.status, json.loads(b.decode("utf-8"), parse_constant=lambda k: (_ for _ in ()).throw(ValueError(k)))
            except ValueError as e: return r.status, "JSON no valido: %s" % e
    except urllib.error.HTTPError as e:
        b = e.read()
        try: return e.code, json.loads(b.decode("utf-8"))
        except ValueError: return e.code, b
    except (urllib.error.URLError, socket.timeout, TimeoutError, ConnectionError) as e:
        return 0, str(e)


def crudo(lineas, timeout=4):
    """Manda una peticion HTTP escrita a mano y devuelve la primera linea de la respuesta ('' si no contesta)."""
    s = socket.create_connection(("127.0.0.1", PUERTO), timeout=timeout)
    try:
        s.sendall(lineas.encode())
        try: return s.recv(200).decode(errors="replace").split("\r\n")[0]
        except socket.timeout: return ""
    finally: s.close()


def arrancar(datos):
    import servidor_aula as sa
    sa.usar_datos(datos); sa.crear_bd()
    con = sa.conectar()
    with con: con.execute("INSERT OR REPLACE INTO config (clave, valor) VALUES ('pin', ?)", (sa.hash_pin(PIN),))
    con.close()
    pr = subprocess.Popen([sys.executable, str(REPO / "aula" / "servidor_aula.py"), "--puerto", str(PUERTO), "--datos", datos],
                          stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for _ in range(100):
        if pedir("GET", "/api/estado")[0] == 200: return pr
        time.sleep(0.1)
    pr.kill(); raise SystemExit("el servidor de prueba no arranca")


XSS = '<img src=x onerror="window.__xss=(window.__xss||0)+1">'


def main():
    global fallos
    datos = tempfile.mkdtemp(prefix="aula_seg_")
    pr = arrancar(datos)
    try:
        pruebas()
    finally:
        pr.kill(); pr.wait()
        shutil.rmtree(datos, ignore_errors=True)
    print("RESULTADO:", "todo bien" if not fallos else "%d fallos" % fallos)
    sys.exit(1 if fallos else 0)


def pruebas():
    from playwright.sync_api import sync_playwright
    c, d = pedir("POST", "/api/profesor/entrar", {"pin": PIN}); tok = d.get("token"); ok("entrar con el PIN", c in (200, 201) and tok)
    # alumnos: uno normal (con clave) y uno con nombre-formula
    c, a1 = pedir("POST", "/api/entrar", {"usuario": "Ana Prueba", "clave": "abcd", "crear": True}); ok("alta de alumno", c in (200, 201), str(c))
    pase1, id1 = a1["pase"], a1["alumno"]["id"]
    c, a2 = pedir("POST", "/api/entrar", {"usuario": "=HYPERLINK(\"x\")", "clave": "abcd", "crear": True}); ok("alta de alumno con nombre-formula", c in (200, 201))
    c, a3 = pedir("POST", "/api/entrar", {"usuario": "Hostil", "clave": "abcd", "crear": True}); pase3, id3 = a3["pase"], a3["alumno"]["id"]

    print("-- vuelos con datos hostiles")
    import uuid
    v = dict(id=str(uuid.uuid4()), alumno_id=id1, inicio=XSS, avion="E3", escenario="libre", resultado="LIBRE", tiempo_vuelo_s=12)
    c, r = pedir("POST", "/api/vuelos", v, pase=pase1); xss_inicio_aceptado = c in (200, 201)
    print("     vuelo con HTML en la fecha: %s" % c)
    for nombre, campo in [("tiempo infinito", dict(tiempo_vuelo_s=float("inf"))), ("tiempo 1e308", dict(tiempo_vuelo_s=1e308)),
                          ("tiempo de 3 dias", dict(tiempo_vuelo_s=3 * 86400)), ("objetivos que no son lista", dict(objetivos="x")),
                          ("accidentes negativos", dict(accidentes=-5)), ("resultado inventado", dict(resultado="APTO<b>"))]:
        vv = dict(v, id=str(uuid.uuid4()), alumno_id=id3, inicio="2026-10-15T10:00:00", **campo)
        c, r = pedir("POST", "/api/vuelos", vv, pase=pase3); ok("se rechaza un vuelo con %s" % nombre, c == 400, str(c))
    c, r = pedir("GET", "/api/profesor/alumnos", token=tok); ok("la lista de alumnos del profesor sigue siendo JSON valido (sin Infinity)", c == 200 and isinstance(r, list), str(r)[:80])
    c, r = pedir("POST", "/api/vuelos", dict(v, id=str(uuid.uuid4()), inicio="2026-10-15T10:00:00"), pase="x.malo"); ok("un vuelo con pase falso se rechaza", c == 401)
    c, r = pedir("POST", "/api/vuelos", dict(v, id=str(uuid.uuid4()), inicio="2026-10-15T10:05:00", tiempo_vuelo_s=600, resultado="APTO", escenario="primer_vuelo"), pase=pase1); ok("un vuelo correcto se guarda", c in (200, 201), str(c))

    print("-- datos privados")
    c, r = pedir("PUT", "/api/profesor/alumnos/" + id1, {"notas": "nota privada del profesor"}, token=tok); ok("el profesor pone una nota", c == 200)
    c, r = pedir("GET", "/api/alumnos"); ok("sin PIN no salen las notas del profesor", c == 200 and all("notas" not in a or not a["notas"] for a in r))
    c, r = pedir("GET", "/api/alumnos/" + id1); ok("sin PIN no sale la nota en la ficha", c == 200 and isinstance(r, dict) and not r.get("notas"))
    c, r = pedir("GET", "/api/profesor/alumnos", token=tok); ok("con PIN si sale la nota", c == 200 and isinstance(r, list) and any(a.get("notas") == "nota privada del profesor" for a in r))
    c, r = pedir("GET", "/api/profesor/exportar?tipo=alumnos", token=tok, crudo=True); txt = r.decode("utf-8-sig") if isinstance(r, bytes) else ""
    ok("el CSV neutraliza las formulas", c == 200 and "'=HYPERLINK" in txt and ";=HYPERLINK" not in txt)

    print("-- peticiones mal formadas")
    l = crudo("POST /api/vuelos HTTP/1.1\r\nHost: x\r\nContent-Length: -1\r\nConnection: close\r\n\r\n"); ok("Content-Length negativo: responde con error", l.startswith("HTTP/1.") and " 4" in l, repr(l))
    l = crudo("POST /api/vuelos HTTP/1.1\r\nHost: x\r\nContent-Length: abc\r\nConnection: close\r\n\r\n"); ok("Content-Length no numerico: responde con error", l.startswith("HTTP/1.") and " 4" in l, repr(l))
    l = crudo("POST /api/vuelos HTTP/1.1\r\nHost: x\r\nContent-Length: 2000000\r\nConnection: close\r\n\r\n"); ok("Content-Length enorme: 413", " 413 " in l, repr(l))
    c, r = pedir("GET", "/zonas/../aula/datos/aula.db", crudo=True); ok("no se sale de simulador/ (..)", c == 404)
    c, r = pedir("GET", "/zonas/..%5c..%5caula%5cdatos%5caula.db", crudo=True); ok("no se sale de simulador/ (%5c)", c == 404)
    c, r = pedir("GET", "/profesor.html", crudo=True); ok("el panel se sirve", c == 200)
    c, r = pedir("GET", "/escenarios.js", crudo=True); ok("escenarios.js se sirve", c == 200)

    print("-- multijugador")
    c, sala = pedir("POST", "/api/salas", {"escenario": "libre", "nombre": "Sala <b>x</b>"}, token=tok); ok("el profesor crea una sala", c == 201, str(c)); cod = sala["codigo"]
    c, r = pedir("POST", "/api/salas", {"escenario": "libre"}); ok("sin PIN no se crea una sala", c == 401)
    c, r = pedir("POST", "/api/salas/%s/expulsar" % cod, {"id": "x"}); ok("sin PIN no se expulsa", c == 401)
    c, r = pedir("DELETE", "/api/salas/" + cod); ok("sin PIN no se cierra la sala", c == 401)
    bueno = dict(id="bueno-1", nombre="Pepe", avion="E3", p=[10, 20, -30], q=[1, 0, 0, 0], vn=[5, 0, 0], estado="volando", agl=30, objs=[1, 3, 0], tvuelo=12)
    c, r = pedir("POST", "/api/salas/%s/estado" % cod, bueno); ok("un estado normal entra", c == 201, str(c))
    malos = [("objs con HTML", dict(bueno, id="malo-1", objs=[1, XSS, 0])), ("estado con HTML", dict(bueno, id="malo-2", estado=XSS, final=XSS, ahora=XSS)),
             ("p null", dict(bueno, id="malo-3", p=None)), ("p con texto", dict(bueno, id="malo-4", p=["a", "b", "c"])), ("q corto", dict(bueno, id="malo-5", q=[1])),
             ("avion __proto__", dict(bueno, id="malo-6", avion="__proto__")), ("agl infinito", dict(bueno, id="malo-7", agl=1e400)), ("nombre con HTML", dict(bueno, id="malo-8", nombre=XSS)),
             ("texto de 100 kB", dict(bueno, id="malo-9", ahora="A" * 100000))]
    for nombre, e in malos:
        c, r = pedir("POST", "/api/salas/%s/estado" % cod, e); print("     estado %-18s -> %s" % (nombre, c))
    c, r = pedir("GET", "/api/salas"); s0 = r[0] if c == 200 and isinstance(r, list) and r else {}
    ok("sin PIN no sale la IP de los jugadores", c == 200 and all("_ip" not in j for j in (s0.get("jugadores") or []) if isinstance(j, dict)))
    ok("sin PIN no sale el id de perfil de los jugadores", all("alumno" not in j and "id" not in j for j in (s0.get("jugadores") or []) if isinstance(j, dict)))
    J = [j for j in (s0.get("jugadores") or []) if isinstance(j, dict)]
    ok("los textos largos se recortan", all(len(str(j.get("ahora") or "")) <= 300 for j in J))
    c, r = pedir("POST", "/api/salas/%s/estado" % cod, bueno); otros = r.get("otros", []) if c == 201 and isinstance(r, dict) else []
    ok("ningun estado mal formado llega a los companeros", all(isinstance(o.get("p"), list) and len(o["p"]) == 3 and all(isinstance(x, (int, float)) and abs(x) < 1e7 for x in o["p"]) and isinstance(o.get("q"), list) and len(o["q"]) == 4 for o in otros),
       "otros: %s" % [o.get("id") for o in otros])
    ok("los objs llegan como numeros", all(all(isinstance(x, (int, float)) for x in o["objs"]) for o in otros if "objs" in o))
    for k in range(70):
        c, r = pedir("POST", "/api/salas/%s/estado" % cod, dict(bueno, id="muchos-%d" % k, nombre="Piloto %d" % k))
        if c != 201: break
    ok("hay un limite de jugadores por sala", c != 201, "entraron %d" % (k + 1))
    # un cliente que no manda el cuerpo no congela a los demas
    s = socket.create_connection(("127.0.0.1", PUERTO)); s.sendall(("POST /api/salas/%s/estado HTTP/1.1\r\nHost: x\r\nContent-Type: application/json\r\nContent-Length: 100\r\n\r\n" % cod).encode())
    t0 = time.time(); c, r = pedir("GET", "/api/salas", timeout=4); s.close()
    ok("un cliente lento no congela las salas", c == 200 and time.time() - t0 < 3, "%.1f s, %s" % (time.time() - t0, c))

    print("-- el panel del profesor y el simulador de los companeros (Playwright)")
    with sync_playwright() as p:
        nav = p.chromium.launch(channel="chrome", headless=True, args=["--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist"])
        pg = nav.new_page(viewport={"width": 1400, "height": 900}); errs = []; pg.on("pageerror", lambda e: errs.append(str(e)))
        pg.goto(BASE + "/profesor.html"); pg.fill("#pin", PIN); pg.click("#entrar")
        try: pg.wait_for_selector("#panel", state="visible", timeout=15000); pg.wait_for_function("document.querySelectorAll('#tAlumnos tr').length > 1"); abre = True
        except Exception as e: abre = False
        ok("el panel abre la lista de alumnos", abre and "Ana Prueba" in pg.inner_text("#tAlumnos"), "" if abre else "el panel no abre: %s" % pg.inner_text("#errLogin"))
        if not abre: nav.close(); return
        ok("el HTML de la fecha del vuelo no se ejecuta en la lista", pg.evaluate("window.__xss || 0") == 0)
        pg.click(".pestanas button[data-p=historial]"); pg.wait_for_function("document.querySelectorAll('#tVuelos tr, #p-historial table tr').length > 1")
        ok("el HTML de la fecha del vuelo no se ejecuta en el historial", pg.evaluate("window.__xss || 0") == 0)
        pedir("POST", "/api/salas/%s/estado" % cod, bueno)      # que siga en la sala
        for nombre, e in malos: pedir("POST", "/api/salas/%s/estado" % cod, e)
        pg.click(".pestanas button[data-p=multi]"); pg.wait_for_function("document.querySelectorAll('#tJugadores tr').length > 1", timeout=15000)
        pg.wait_for_timeout(1500)
        ok("el HTML de los estados no se ejecuta en el panel", pg.evaluate("window.__xss || 0") == 0, "ejecuciones: %s" % pg.evaluate("window.__xss || 0"))
        ok("el panel pinta la sala sin errores", not errs, errs[:2])
        ok("el boton Expulsar sigue (los estados raros no rompen la tabla)", pg.evaluate("document.querySelectorAll('#tJugadores button[data-expulsar]').length") >= 1)
        ok("Pepe esta en la tabla", "Pepe" in pg.inner_text("#tJugadores"))
        # el simulador de un companero en la misma sala
        pg2 = nav.new_page(viewport={"width": 1280, "height": 720}); errs2 = []; pg2.on("pageerror", lambda e: errs2.append(str(e)))
        pg2.goto(BASE + "/simulador.html")
        if pg2.url.endswith("profesor.html"):           # el aula no sirve el simulador: se abre de la carpeta por http
            import http.server, socketserver
            class H(http.server.SimpleHTTPRequestHandler):
                def log_message(self, *a): pass
                def __init__(self, *a, **k): super().__init__(*a, directory=str(REPO / "simulador"), **k)
            srv = socketserver.ThreadingTCPServer(("127.0.0.1", 0), H); srv.daemon_threads = True; threading.Thread(target=srv.serve_forever, daemon=True).start()
            pg2.goto("http://127.0.0.1:%d/simulador.html" % srv.server_address[1])
        pg2.wait_for_function("typeof visor !== 'undefined' && visor && Modelos.ids().length > 0")
        r = pg2.evaluate("""async ([base, cod, estados]) => {
            window.requestAnimationFrame = cb => setTimeout(() => cb(performance.now()), 5);
            salirDelAula(); irInicio(); try { localStorage.setItem("evrc_url_aula", base); } catch (e) {}
            if (typeof AULA !== "undefined" && AULA) AULA.url = base;
            sesion.avion = "E3"; sesion.escenario = "libre"; await empezar();
            const salas = await api("GET", "salas"); const s = salas[0];
            await api("POST", `salas/${s.codigo}/entrar`, { id: multiId(), clave: "", nombre: "Companero", alumno: null });
            MULTI.sala = s; MULTI.otros.clear();
            for (const e of estados) await fetch(base + "/api/salas/" + cod + "/estado", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(e) });   // los companeros, recien llegados
            for (let k = 0; k < 3; k++) { MULTI.enCurso = false; await enviarSala(); await new Promise(r => setTimeout(r, 150)); }
            pintarSalaInfo();
            let errBucle = null; try { pantallaActual = null; for (let k = 0; k < 5; k++) bucle(performance.now() + k * 16); } catch (e) { errBucle = String(e); }
            return { otros: MULTI.otros.size, xss: window.__xss || 0, html: document.getElementById("salaInfo").innerHTML, errBucle, t: av.t, fantasmas: visor.fantasmas ? visor.fantasmas.size : -1 };
        }""", [BASE, cod, [bueno] + [e for _, e in malos]])
        ok("el simulador recibe a los companeros", r["otros"] >= 1, "otros: %s" % r["otros"])
        ok("el HTML de los estados no se ejecuta en el simulador", r["xss"] == 0 and "<img" not in r["html"], "xss: %s" % r["xss"])
        ok("el bucle del simulador sigue con estados raros en la sala", r["errBucle"] is None and not errs2, (r["errBucle"], errs2[:2]))
        nav.close()

    print("-- fuerza bruta del PIN (al final: bloquea esta IP)")
    with ThreadPoolExecutor(max_workers=40) as ex:
        codigos = list(ex.map(lambda _: pedir("POST", "/api/profesor/entrar", {"pin": "0000"})[0], range(40)))
    n401, n429 = codigos.count(401), codigos.count(429)
    ok("40 intentos a la vez: como mucho 5 se comprueban", n401 <= 5 and n429 >= 35, "401: %d, 429: %d" % (n401, n429))
    c, r = pedir("POST", "/api/profesor/entrar", {"pin": PIN}); ok("tras el bloqueo, ni el PIN bueno entra hasta que pase el tiempo", c == 429, str(c))


if __name__ == "__main__":
    main()
