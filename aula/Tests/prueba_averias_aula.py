"""Prueba de las averias con el aula de punta a punta (js/desgaste.js, scripts/desgaste.gd, aula/servidor_aula.py y el
panel del profesor), con un servidor del aula de prueba (datos temporales, PIN 2468):
  - el profesor pone al Mini Dron HQ de un alumno una helice danada y la brujula descalibrada;
  - en la web el alumno vuela con ellas (el modelo las lleva, la app avisa del error de brujula al armar y queda en el
    registro), una averia en vuelo de la sala (GPS) se suma, y al acabar suben las horas del vehiculo en el aula;
  - en el Taller la inspeccion de las helices ensena la mella de la 2 y la repara: queda en el libro de mantenimiento;
  - el panel del profesor ve el vehiculo con sus averias y su origen y el libro con lo que arreglo cada trabajo, pone una
    averia (IMU) y la quita;
  - el servidor rechaza un estado viejo (409), uno mal formado (400) y sin el pase (401), y valida la orden de averia;
  - Godot (simulador_godot/Tests/prueba_averias_aula.gd), con el mismo alumno, lee las mismas averias, la app avisa al armar, el
    Taller las ensena y repara la brujula.
Los datos de usuario de Godot se dejan como estaban.

    python aula/Tests/prueba_averias_aula.py
"""
import http.server, json, os, pathlib, shutil, socketserver, subprocess, sys, tempfile, threading, time, urllib.error, urllib.request
from playwright.sync_api import sync_playwright

REPO = pathlib.Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(REPO / "aula"))
GODOT = REPO / "herramientas" / "godot" / "Godot_v4.7.2-stable_win64_console.exe"
PUERTO = 8096
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


def pedir(metodo, ruta, cuerpo=None, token=None, pase=None):
    datos = json.dumps(cuerpo).encode() if cuerpo is not None else None
    req = urllib.request.Request(BASE + ruta, data=datos, method=metodo)
    if datos is not None: req.add_header("Content-Type", "application/json")
    if token: req.add_header("Authorization", "Bearer " + token)
    if pase: req.add_header("X-Alumno", pase)
    try:
        with urllib.request.urlopen(req, timeout=20) as r: return r.status, json.loads(r.read().decode("utf-8"))
    except urllib.error.HTTPError as e: return e.code, e.read().decode("utf-8", "replace")


VOLAR = r"""
async ([base]) => {
  window.requestAnimationFrame = cb => setTimeout(() => cb(performance.now()), 5);
  salirDelAula(); irInicio(); try { localStorage.setItem("evrc_url_aula", base); } catch (e) {}
  const ent = await api("POST", "entrar", { usuario: "Piloto Averias", clave: "abcd" });
  await dentroDelAula(ent.alumno, ent.pase); await Desgaste.cargar();
  const antes = JSON.parse(JSON.stringify(Desgaste.estado("DJI_MINI")));
  sesion.avion = "DJI_MINI"; sesion.escenario = "libre"; await empezar();
  await new Promise(r => { const f = () => (pantallaActual === null && av && modelo) ? r() : setTimeout(f, 50); f(); });
  pantallaActual = "prueba"; lanzar(); modelo.despegar(av);
  const out = { antes, alumno: ent.alumno.id, pase: ent.pase, averiasModelo: modelo.averias.map(a => a.c), vib: modelo.efe.vib, rumbo: modelo.sens ? modelo.sens.rumbo / D2R : null };
  for (let i = 0; i < 40 / DT; i++) {
    mando.vz = i * DT < 5 ? 1 : 0; paso(DT);
    if (i === Math.round(10 / DT)) aplicarOrdenes([{ n: 1, tipo: "averia", para: "*", c: "gps", averia: "antena", edad: 0 }]);   // la orden de la sala
  }
  out.gpsEnVuelo = modelo.sens ? modelo.sens.gps : null;
  const id = vuelo.id; terminarVuelo("abandonado");
  let reg = null; for (let k = 0; k < 50 && !reg; k++) { await new Promise(r => setTimeout(r, 100)); reg = await RegistroDB.leer(id); }
  out.eventos = reg.eventos.map(e => e[1]);
  for (let k = 0; k < 50; k++) { await new Promise(r => setTimeout(r, 100)); if (Desgaste.estado("DJI_MINI").horas > antes.horas) break; }
  out.despues = JSON.parse(JSON.stringify(Desgaste.estado("DJI_MINI")));
  irInicio();
  return out;
}
"""


def main():
    import servidor_aula as sa
    datos = tempfile.mkdtemp(prefix="aula_averias_")
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
            try: urllib.request.urlopen(BASE + "/api/estado", timeout=2); break
            except Exception: time.sleep(0.1)
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
    alta_profesor(BASE, "2468", "Piloto Averias", "abcd")
    c, al = pedir("POST", "/api/entrar", {"usuario": "Piloto Averias", "clave": "abcd"}); aid, pase = al["alumno"]["id"], al["pase"]
    for c_, t_ in (("helice2", "mella"), ("brujula", "descalibrada")):
        c, r = pedir("POST", "/api/profesor/vehiculos/averia", {"alumno_id": aid, "avion": "DJI_MINI", "c": c_, "tipo": t_}, token=tok)
    ok("aula: el profesor pone dos averias al Mini del alumno", c in (200, 201) and [a["c"] for a in r["averias"]] == ["helice2", "brujula"] and r["version"] == 2, str(r)[:160])
    ok("aula: el alumno no las puede leer sin su pase", pedir("GET", "/api/vehiculos?alumno=" + aid)[0] == 401)
    class H(http.server.SimpleHTTPRequestHandler):
        def __init__(s, *a, **k): super().__init__(*a, directory=str(REPO), **k)
        def log_message(s, *a): pass
    srv = socketserver.ThreadingTCPServer(("127.0.0.1", 0), H); srv.daemon_threads = True
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    with sync_playwright() as p:
        nav = p.chromium.launch(channel="chrome", headless=True, args=["--use-angle=swiftshader", "--enable-unsafe-swiftshader"])
        pg = nav.new_page(viewport={"width": 1500, "height": 1000}); errs = []
        pg.on("pageerror", lambda e: errs.append(str(e)))
        pg.goto("http://127.0.0.1:%d/simulador_web/simulador.html" % srv.server_address[1]); pg.wait_for_function("typeof visor !== 'undefined' && visor && Modelos.ids().length > 0")
        w = pg.evaluate(VOLAR, [BASE])
        ok("web: el vuelo lleva las averias del aula (vibracion de la helice y brujula girada 50 grados)", w["averiasModelo"] == ["helice2", "brujula"] and w["vib"] > 0 and abs(w["rumbo"] - 50) < 1e-9, str(w["averiasModelo"]))
        ok("web: la app avisa del error de brujula al armar y queda en el registro", any("Error de brújula" in e for e in w["eventos"]), str(w["eventos"]))
        ok("web: la averia de la sala en vuelo (GPS) entra en el modelo", w["gpsEnVuelo"] == 3.5)
        D = w["despues"]
        ok("web: al acabar, el aula tiene las horas del vuelo y la averia de la sala", D["horas"] > w["antes"]["horas"] and abs(D["horas"] - 40 / 3600) < 0.002 and any(a["c"] == "gps" and a["origen"] == "profesor" for a in D["averias"]),
           "%.4f h, %s" % (D["horas"], [a["c"] for a in D["averias"]]))
        # el Taller: inspeccion y reparacion
        pg.click("#mnTaller"); pg.wait_for_selector(".tallerVeh.sel"); pg.click("#tallerConectar"); pg.wait_for_selector("button[data-pest]", timeout=10000)
        pg.click("button[data-pest=revision]"); pg.click("button[data-rev=helices]"); pg.click("button[data-rev=app]")
        rev = pg.inner_text("#tallerCentro")
        ok("web: el Taller ensena la mella de la helice 2 y el error de brujula", "Hélice 2 (delantera izquierda): mella" in rev and "Hélice 1 (delantera derecha): sin daños" in rev and "Error de brújula" in rev)
        pg.click("button[data-rep=helice2]"); pg.wait_for_timeout(200); pg.click("#modSi")
        pg.wait_for_function("() => Desgaste.estado('DJI_MINI').libro.length === 1", timeout=10000)
        c, V = pedir("GET", "/api/profesor/vehiculos?alumno=" + aid, token=tok)
        E = V.get("DJI_MINI", {})
        ok("web: la reparacion queda en el aula: sin la helice 2 y en el libro", [a["c"] for a in E.get("averias", [])] == ["brujula", "gps"] and E["libro"][0]["arreglo"] == ["Hélice 2 dañada"], str(E.get("libro")))
        pg.screenshot(path=str(REPO / "simulador_godot" / "Tests" / "_taller_revision.png")) if os.environ.get("CAPTURAS") else None
        ok("web: sin errores en la pagina", not errs, errs[:3])
        # el panel del profesor
        pp = nav.new_page(viewport={"width": 1400, "height": 1000}); errs2 = []; pp.on("pageerror", lambda e: errs2.append(str(e)))
        pp.goto(BASE + "/profesor.html"); pp.fill("#pin", "2468"); pp.click("#entrar")
        pp.wait_for_selector('#tAlumnos button[data-a="ver"]')
        pp.locator("#tAlumnos tr", has_text="Piloto Averias").locator('button[data-a="ver"]').click()
        pp.wait_for_selector("#tVehAlumno")
        t = pp.inner_text("#tVehAlumno")
        ok("panel: el vehiculo con sus averias, su origen y el libro", "Mini Dron HQ" in t and "Brújula descalibrada" in t and "puesta por ti" in t and "arregló: Hélice 2 dañada" in t, t.replace("\n", " / ")[:240])
        pp.select_option("#vaVeh", "DJI_MINI"); pp.select_option("#vaAv", label="IMU descalibrada"); pp.click("#vaPoner")
        pp.wait_for_function("() => document.getElementById('tVehAlumno').innerText.includes('IMU descalibrada')", timeout=10000)
        ok("panel: pone una averia (IMU)", any(a["c"] == "imu" for a in pedir("GET", "/api/profesor/vehiculos?alumno=" + aid, token=tok)[1]["DJI_MINI"]["averias"]))
        pp.locator("#tVehAlumno div", has_text="IMU descalibrada").locator("button[data-quitar]").click()
        pp.wait_for_function("() => !document.getElementById('tVehAlumno').innerText.includes('IMU descalibrada')", timeout=10000)
        ok("panel: y la quita", not any(a["c"] == "imu" for a in pedir("GET", "/api/profesor/vehiculos?alumno=" + aid, token=tok)[1]["DJI_MINI"]["averias"]))
        ok("panel: sin errores", not errs2, errs2[:3])
        nav.close()
    srv.shutdown()
    # el servidor
    c, V = pedir("GET", "/api/vehiculos?alumno=" + aid, pase=pase); e = V["DJI_MINI"]
    ok("aula: un estado viejo se rechaza (409)", pedir("POST", "/api/vehiculos", {"alumno_id": aid, "avion": "DJI_MINI", "version": e["version"] - 1, "estado": e}, pase=pase)[0] == 409)
    malo = dict(e, averias=[{"c": "<script>", "tipo": "mella"}])
    ok("aula: un estado mal formado se rechaza (400)", pedir("POST", "/api/vehiculos", {"alumno_id": aid, "avion": "DJI_MINI", "version": e["version"], "estado": malo}, pase=pase)[0] == 400)
    ok("aula: sin el pase, 401", pedir("POST", "/api/vehiculos", {"alumno_id": aid, "avion": "DJI_MINI", "version": e["version"], "estado": e})[0] == 401)
    c, s = pedir("POST", "/api/salas", {"escenario": "libre", "nombre": "Prueba averias"}, token=tok); cod = s.get("codigo") if c in (200, 201) else None
    c, o = pedir("POST", "/api/salas/%s/orden" % cod, {"tipo": "averia", "c": "bateria", "averia": "celda", "celda": 1}, token=tok)
    ok("aula: la orden de averia en vuelo de una sala (la celda aparte del numero de orden)", c in (200, 201) and o.get("n") == 1 and o.get("celda") == 1 and o.get("c") == "bateria" and o.get("averia") == "celda", str(o))
    ok("aula: y una orden de averia rara se rechaza", pedir("POST", "/api/salas/%s/orden" % cod, {"tipo": "averia", "c": "x y", "averia": "antena"}, token=tok)[0] == 400)
    # Godot, con el mismo alumno
    g = subprocess.run([str(GODOT), "--headless", "--path", str(REPO / "simulador_godot"), "--script", "res://Tests/prueba_averias_aula.gd", "--",
                        "--aula=" + BASE, "--usuario=Piloto Averias", "--clave=abcd"], capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=600)
    lineas = [l for l in g.stdout.splitlines() if l.startswith("  OK ") or l.startswith("  MAL ")]
    for l in lineas:
        print("  Godot:", l.strip())
        if l.startswith("  MAL "): globals()["fallos"] += 1
    ok("Godot: la prueba ha corrido entera", "RESULTADO" in g.stdout and len(lineas) >= 6, "" if "RESULTADO" in g.stdout else g.stdout[-800:] + g.stderr[-800:])
    c, V = pedir("GET", "/api/profesor/vehiculos?alumno=" + aid, token=tok); E = V["DJI_MINI"]
    ok("aula: tras Godot, la brujula reparada y en el libro", [a["c"] for a in E["averias"]] == ["gps"] and E["libro"][-1]["arreglo"] == ["Brújula descalibrada"], str([x["texto"] for x in E["libro"]]))


if __name__ == "__main__":
    main()
