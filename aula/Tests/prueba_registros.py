"""Prueba de los registros de vuelo (js/registro.js y scripts/registro_vuelo.gd) de punta a punta, con un servidor del
aula de prueba (datos temporales, PIN 2468): en la web un alumno vuela el Mini Dron HQ, termina el vuelo y su registro
queda en el navegador (10 muestras por segundo, las dos celdas, la bateria que baja y el aviso en pantalla) y llega al
aula; en Godot otro alumno hace lo mismo (simulador_godot/Tests/prueba_registros.gd) y su registro tiene las MISMAS columnas. El
profesor lista los registros y descarga el CSV; el alumno lista los suyos con su pase; el servidor rechaza lo que no es
un registro, el que no trae el pase y el de un alumno que no existe. Los datos de usuario de Godot se dejan como estaban.

    python aula/Tests/prueba_registros.py
"""
import csv, gzip, http.server, io, json, pathlib, os, shutil, socketserver, subprocess, sys, tempfile, threading, time, urllib.error, urllib.request
from playwright.sync_api import sync_playwright

REPO = pathlib.Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(REPO / "aula"))
GODOT = REPO / "herramientas" / "godot" / "Godot_v4.7.2-stable_win64_console.exe"
PUERTO = 8098
BASE = "http://127.0.0.1:%d" % PUERTO
DATOS_GODOT = pathlib.Path(os.environ["APPDATA"]) / "Godot" / "app_userdata" / "Entrenador Vuelo RC v2 (Godot)"
fallos = 0



def alta_profesor(base, pin, usuario, clave):
    """El alumno, dado de alta por el profesor desde su panel (ya aprobado): los que se registran desde el simulador quedan
    pendientes hasta que el profesor los aprueba."""
    import json, urllib.error, urllib.request
    def post(ruta, cuerpo, tok=None):
        req = urllib.request.Request(base + ruta, data=json.dumps(cuerpo).encode(), method="POST"); req.add_header("Content-Type", "application/json")
        if tok: req.add_header("Authorization", "Bearer " + tok)
        return json.loads(urllib.request.urlopen(req, timeout=10).read())
    tok = post("/api/profesor/entrar", {"pin": pin})["token"]
    try: post("/api/profesor/alumnos", {"nombre": usuario, "clave": clave}, tok)
    except urllib.error.HTTPError as e:
        if e.code != 409: raise                                    # 409: ya estaba

def ok(nombre, cond, detalle=""):
    global fallos
    if not cond: fallos += 1
    print("  %s %s %s" % ("OK " if cond else "MAL", nombre, detalle))


def pedir(metodo, ruta, cuerpo=None, token=None, pase=None, crudo=None, tipo="application/json"):
    datos = crudo if crudo is not None else (json.dumps(cuerpo).encode() if cuerpo is not None else None)
    req = urllib.request.Request(BASE + ruta, data=datos, method=metodo)
    if datos is not None: req.add_header("Content-Type", tipo)
    if token: req.add_header("Authorization", "Bearer " + token)
    if pase: req.add_header("X-Alumno", pase)
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            b = r.read(); return r.status, (json.loads(b.decode("utf-8")) if r.headers.get_content_type() == "application/json" else b.decode("utf-8-sig"))
    except urllib.error.HTTPError as e: return e.code, e.read().decode("utf-8", "replace")


WEB = r"""
async ([base]) => {
  window.requestAnimationFrame = cb => setTimeout(() => cb(performance.now()), 5);
  salirDelAula(); irInicio(); try { localStorage.setItem("evrc_url_aula", base); } catch (e) {}
  const ent = await api("POST", "entrar", { usuario: "Piloto Web", clave: "abcd" });
  sesion.alumno = ent.alumno; sesion.pase = ent.pase; sesion.aula = true;
  sesion.avion = "DJI_MINI"; sesion.escenario = "libre"; await empezar();
  await new Promise(r => { const f = () => (pantallaActual === null && av && modelo) ? r() : setTimeout(f, 50); f(); });
  pantallaActual = "prueba"; lanzar(); modelo.despegar(av);
  for (let i = 0; i < 25 / DT; i++) {
    mando.vz = i * DT < 6 ? 1 : 0; mando.pitch = i * DT > 8 ? -0.6 : 0; paso(DT);
    if (i === Math.round(12 / DT)) toast("Aviso de prueba del registro");
  }
  const id = vuelo.id; terminarVuelo("abandonado");
  let reg = null; for (let k = 0; k < 50 && !reg; k++) { await new Promise(r => setTimeout(r, 100)); reg = await RegistroDB.leer(id); }
  for (let k = 0; k < 100 && reg && reg.subir; k++) { await new Promise(r => setTimeout(r, 100)); reg = await RegistroDB.leer(id); }
  const lista = await RegistroDB.listar("DJI_MINI"), c = reg.columnas, ib = c.indexOf("bateria_pct"), ic = c.indexOf("celda2_V");
  return { id, alumno: ent.alumno.id, pase: ent.pase, n: reg.filas.length, columnas: c, eventos: reg.eventos, pendiente: !!reg.subir,
           bat0: reg.filas[0][ib], bat1: reg.filas[reg.filas.length - 1][ib], celda: reg.filas[50][ic], lista: lista.map(x => x.id),
           csv: registroCSV(reg).split("\n").length, t1: reg.filas[reg.filas.length - 1][0] };
}
"""


def main():
    import servidor_aula as sa
    datos = tempfile.mkdtemp(prefix="aula_registros_")
    sa.usar_datos(datos); sa.crear_bd()
    con = sa.conectar()
    with con: con.execute("INSERT OR REPLACE INTO config (clave, valor) VALUES ('pin', ?)", (sa.hash_pin("2468"),))
    con.close()
    copia = tempfile.mkdtemp(prefix="godot_datos_"); hay_reg = (DATOS_GODOT / "registros").exists()
    for f in list(DATOS_GODOT.glob("*.cfg")) + list(DATOS_GODOT.glob("*.json")): shutil.copy2(f, copia)
    if hay_reg: shutil.copytree(DATOS_GODOT / "registros", pathlib.Path(copia) / "registros")
    antes = {f.name for f in DATOS_GODOT.iterdir() if f.is_file()}
    pr = subprocess.Popen([sys.executable, str(REPO / "aula" / "servidor_aula.py"), "--puerto", str(PUERTO), "--datos", datos], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        for _ in range(100):
            if pedir("GET", "/api/estado")[0] == 200: break
            time.sleep(0.1)
        pruebas()
    finally:
        pr.kill(); pr.wait(); shutil.rmtree(datos, ignore_errors=True)
        for f in DATOS_GODOT.iterdir():
            if f.is_file() and f.name not in antes and f.suffix in (".cfg", ".json"): f.unlink()
        for f in pathlib.Path(copia).glob("*.*"): shutil.copy2(f, DATOS_GODOT)
        shutil.rmtree(DATOS_GODOT / "registros", ignore_errors=True)
        if hay_reg: shutil.copytree(pathlib.Path(copia) / "registros", DATOS_GODOT / "registros")
        shutil.rmtree(copia, ignore_errors=True)
    print("RESULTADO:", "todo bien" if not fallos else "%d fallos" % fallos)
    sys.exit(1 if fallos else 0)


def pruebas():
    c, d = pedir("POST", "/api/profesor/entrar", {"pin": "2468"}); tok = d["token"]
    alta_profesor(BASE, "2468", "Piloto Web", "abcd"); alta_profesor(BASE, "2468", "Piloto Godot", "wxyz")
    class H(http.server.SimpleHTTPRequestHandler):
        def __init__(s, *a, **k): super().__init__(*a, directory=str(REPO), **k)
        def log_message(s, *a): pass
    srv = socketserver.ThreadingTCPServer(("127.0.0.1", 0), H); srv.daemon_threads = True
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    with sync_playwright() as p:
        nav = p.chromium.launch(channel="chrome", headless=True, args=["--use-angle=swiftshader", "--enable-unsafe-swiftshader"])
        pg = nav.new_page(viewport={"width": 1280, "height": 720}); errs = []
        pg.on("pageerror", lambda e: errs.append(str(e)))
        pg.goto("http://127.0.0.1:%d/simulador_web/simulador.html" % srv.server_address[1]); pg.wait_for_function("typeof visor !== 'undefined' && visor && Modelos.ids().length > 0")
        w = pg.evaluate(WEB, [BASE])
        nav.close()
    srv.shutdown()
    ok("web: el registro queda en el navegador, a 10 muestras por segundo", w["id"] in w["lista"] and abs(w["n"] - 10 * w["t1"]) <= 3, "%d muestras en %.1f s" % (w["n"], w["t1"]))
    ok("web: con las dos celdas del Mini y la bateria que baja", "celda1_V" in w["columnas"] and "celda2_V" in w["columnas"] and w["bat1"] < w["bat0"] and 3.0 < w["celda"] < 4.3,
       "%s %% -> %s %%, celda %s V" % (w["bat0"], w["bat1"], w["celda"]))
    ok("web: el aviso de pantalla queda en el registro y en el CSV", any("Aviso de prueba" in e[1] for e in w["eventos"]) and w["csv"] >= w["n"] + 1)
    ok("web: enviado al aula (ya no queda pendiente)", not w["pendiente"])
    ok("sin errores en la pagina", not errs, errs[:3])
    # Godot, con otro alumno
    g = subprocess.run([str(GODOT), "--headless", "--path", str(REPO / "simulador_godot"), "--script", "res://Tests/prueba_registros.gd", "--",
                        "--aula=" + BASE, "--usuario=Piloto Godot", "--clave=wxyz"], capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=600)
    L = {l.split(" ", 1)[0]: l.split(" ", 1)[1] for l in g.stdout.splitlines() if l.split(" ", 1)[0] in ("REGISTRO", "COLUMNAS", "CSV", "PENDIENTES")}
    ok("Godot: el registro queda en la carpeta de datos", "REGISTRO" in L and int(L["REGISTRO"].split()[1]) >= 240, L.get("REGISTRO", g.stdout[-400:]))
    ok("Godot: con las MISMAS columnas que la web", L.get("COLUMNAS", "").split(",") == w["columnas"], L.get("COLUMNAS", "")[:120])
    ok("Godot: el aviso en el CSV y nada pendiente de enviar", L.get("CSV", "").endswith("true") and L.get("PENDIENTES") == "0", "%s / %s" % (L.get("CSV"), L.get("PENDIENTES")))
    # el aula
    c, lista = pedir("GET", "/api/profesor/registros", token=tok)
    ok("aula: el profesor ve los dos registros (web y Godot)", c == 200 and len(lista) == 2 and {x["alumno"] for x in lista} == {"Piloto Web", "Piloto Godot"},
       str([(x["alumno"], x["avion"], x["muestras"]) for x in lista]) if c == 200 else str(lista))
    c, texto = pedir("GET", "/api/profesor/registros/%s/csv" % w["id"], token=tok)
    filas = list(csv.reader(io.StringIO(texto))) if c == 200 else []
    ok("aula: el CSV del profesor, con todas las muestras y el aviso", c == 200 and filas[0][:3] == ["tiempo_s", "latitud", "longitud"] and len(filas) == w["n"] + 1 and any("Aviso de prueba" in f[-1] for f in filas[1:]),
       "%d filas" % len(filas))
    c, mios = pedir("GET", "/api/registros?alumno=%s" % w["alumno"], pase=w["pase"])
    ok("aula: el alumno lista los suyos con su pase", c == 200 and [x["id"] for x in mios] == [w["id"]])
    ok("aula: sin el pase no", pedir("GET", "/api/registros?alumno=%s" % w["alumno"])[0] == 401)
    c, uno = pedir("GET", "/api/registros/%s?alumno=%s" % (w["id"], w["alumno"]), pase=w["pase"])
    ok("aula: y lee uno entero", c == 200 and len(uno["filas"]) == w["n"])
    malo = gzip.compress(b"esto no es json")
    ok("aula: lo que no es un registro se rechaza (400)", pedir("POST", "/api/registros", crudo=malo, tipo="application/gzip")[0] == 400)
    reg = dict(uno if isinstance(uno, dict) else {}, id="11111111-2222-3333-4444-555555555555", alumno_id=w["alumno"])
    ok("aula: sin el pase del alumno, 401", pedir("POST", "/api/registros", crudo=gzip.compress(json.dumps(reg).encode()), tipo="application/gzip")[0] == 401)
    reg2 = dict(reg, alumno_id="00000000-0000-0000-0000-000000000000")
    ok("aula: de un alumno que no existe, 404", pedir("POST", "/api/registros", crudo=gzip.compress(json.dumps(reg2).encode()), tipo="application/gzip", pase=w["pase"])[0] == 404)
    reg3 = dict(reg, columnas=reg["columnas"] + ["<script>"])
    ok("aula: columnas raras, 400", pedir("POST", "/api/registros", crudo=gzip.compress(json.dumps(reg3).encode()), tipo="application/gzip", pase=w["pase"])[0] == 400)
    # el panel del profesor: la ficha del alumno (Ver) con su historial y sus registros, y la descarga del CSV
    with sync_playwright() as p:
        nav = p.chromium.launch(channel="chrome", headless=True); ctx = nav.new_context(accept_downloads=True); pg = ctx.new_page(); errs = []
        pg.on("pageerror", lambda e: errs.append(str(e)))
        pg.goto(BASE + "/profesor.html"); pg.fill("#pin", "2468"); pg.click("#entrar")
        pg.wait_for_selector('#tAlumnos button[data-a="ver"]')
        fila = pg.locator("#tAlumnos tr", has_text="Piloto Web"); fila.locator('button[data-a="ver"]').click()
        pg.wait_for_selector("#tRegAlumno")
        ok("panel: Ver abre la ficha del alumno (con su historial)", pg.inner_text("#mTitulo") == "Piloto Web" and "Historial" in pg.inner_text("#mCuerpo"), pg.inner_text("#mTitulo"))
        ok("panel: con su registro de vuelo", pg.locator("#tRegAlumno tr").count() == 2 and "Mini Dron HQ" in pg.inner_text("#tRegAlumno"), pg.inner_text("#tRegAlumno").replace("\n", " / ")[:160])
        with pg.expect_download() as dl: pg.click("#tRegAlumno button[data-reg]")
        ruta = dl.value.path(); texto = open(ruta, encoding="utf-8-sig").read()
        ok("panel: el boton CSV lo descarga", dl.value.suggested_filename.startswith("registro_Piloto_Web") and texto.startswith("tiempo_s,latitud") and texto.count("\n") == w["n"] + 1, dl.value.suggested_filename)
        ok("panel: sin errores", not errs, errs[:3])
        nav.close()


if __name__ == "__main__":
    main()
