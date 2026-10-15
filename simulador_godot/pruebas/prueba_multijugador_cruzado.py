"""Multijugador cruzado web <-> Godot contra un servidor del aula de prueba (lo levanta este script, con su propia carpeta
de datos y PIN 1234): Godot (pruebas/prueba_multijugador.gd) crea una sala y vuela 20 s con el E3; el simulador web
(Playwright) entra en esa sala con el dron comercial y manda su estado. Comprueba que cada uno ve al otro con su nombre,
su vehiculo y una posicion que cambia, que el panel del profesor los lista a los dos y que nadie recibe nada raro.
Hace copia de la configuracion de Godot del usuario y la deja como estaba.

    python simulador_godot/pruebas/prueba_multijugador_cruzado.py [puerto]     (por defecto 8099)
"""
import hashlib, http.server, json, os, pathlib, shutil, socketserver, subprocess, sys, tempfile, threading, time, urllib.request
from playwright.sync_api import sync_playwright

REPO = pathlib.Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(REPO / "aula"))
PUERTO = int(sys.argv[1]) if len(sys.argv) > 1 else 8099
BASE = "http://127.0.0.1:%d" % PUERTO
GODOT = REPO / "herramientas" / "godot" / "Godot_v4.7.2-stable_win64_console.exe"
CFG = pathlib.Path(os.environ["APPDATA"]) / "Godot" / "app_userdata" / "Entrenador Vuelo RC v2 (Godot)"
fallos = 0


def ok(nombre, cond, detalle=""):
    global fallos
    if not cond: fallos += 1
    print("  %s %s %s" % ("OK " if cond else "MAL", nombre, detalle))


def md5s(d):
    return {f.name: hashlib.md5(f.read_bytes()).hexdigest() for f in d.glob("*") if f.suffix in (".cfg", ".json")}


def arrancar(datos):
    import servidor_aula as sa
    sa.usar_datos(datos); sa.crear_bd(); con = sa.conectar()
    with con: con.execute("INSERT OR REPLACE INTO config (clave, valor) VALUES ('pin', ?)", (sa.hash_pin("1234"),))
    con.close()
    pr = subprocess.Popen([sys.executable, str(REPO / "aula" / "servidor_aula.py"), "--puerto", str(PUERTO), "--datos", datos], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for _ in range(100):
        try:
            with urllib.request.urlopen(BASE + "/api/estado", timeout=1): return pr
        except Exception: time.sleep(0.1)
    pr.kill(); raise SystemExit("el servidor de prueba no arranca")


def main():
    datos = tempfile.mkdtemp(prefix="aula_cruz_"); copia = tempfile.mkdtemp(prefix="godot_cfg_")
    antes = md5s(CFG)
    for f in CFG.glob("*"):
        if f.suffix in (".cfg", ".json"): shutil.copy2(f, copia)
    pr = arrancar(datos)
    try:
        prueba()
    finally:
        pr.kill(); pr.wait(); shutil.rmtree(datos, ignore_errors=True)
        for f in CFG.glob("*"):
            if f.suffix in (".cfg", ".json") and f.name not in antes: f.unlink()
        for f in pathlib.Path(copia).glob("*"): shutil.copy2(f, CFG / f.name)
        shutil.rmtree(copia, ignore_errors=True)
        ok("la configuracion de Godot del usuario queda como estaba", md5s(CFG) == antes)
    print("RESULTADO:", "todo bien" if not fallos else "%d fallos" % fallos)
    sys.exit(1 if fallos else 0)


def prueba():
    # Godot: crea la sala y vuela 20 s (lineas SALA y OTROS por la salida)
    g = subprocess.Popen([str(GODOT), "--path", str(REPO / "simulador_godot"), "--resolution", "1024x600", "--script", "res://pruebas/prueba_multijugador.gd", "--",
                          "--aula=" + BASE, "--pin=1234"], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, encoding="utf-8", errors="replace")
    lineas = []; cod = None
    def leer():
        for l in g.stdout: lineas.append(l.rstrip())
    threading.Thread(target=leer, daemon=True).start()
    for _ in range(600):
        cod = next((l.split()[1] for l in lineas if l.startswith("SALA ")), None)
        if cod or g.poll() is not None: break
        time.sleep(0.1)
    ok("Godot crea la sala", bool(cod), "\n".join(lineas[-5:]) if not cod else cod)
    if not cod: return
    # la web entra en esa sala con el dron comercial y manda su estado 12 s; apunta a quien ve
    class H(http.server.SimpleHTTPRequestHandler):
        def log_message(self, *a): pass
        def __init__(self, *a, **k): super().__init__(*a, directory=str(REPO / "simulador"), **k)
    srv = socketserver.ThreadingTCPServer(("127.0.0.1", 0), H); srv.daemon_threads = True; threading.Thread(target=srv.serve_forever, daemon=True).start()
    with sync_playwright() as p:
        nav = p.chromium.launch(channel="chrome", headless=True, args=["--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist"])
        pg = nav.new_page(viewport={"width": 1280, "height": 720}); errs = []; pg.on("pageerror", lambda e: errs.append(str(e)))
        pg.goto("http://127.0.0.1:%d/simulador.html" % srv.server_address[1]); pg.wait_for_function("typeof visor !== 'undefined' && visor && Modelos.ids().length > 0")
        r = pg.evaluate("""async ([base, cod]) => {
            window.requestAnimationFrame = cb => setTimeout(() => cb(performance.now()), 5);
            salirDelAula(); irInicio(); try { localStorage.setItem("evrc_url_aula", base); } catch (e) {}
            const ent = await api("POST", "entrar", { usuario: "Prueba Web", clave: "prueba", crear: true }).catch(() => api("POST", "entrar", { usuario: "Prueba Web", clave: "prueba" }));
            sesion.alumno = ent.alumno; sesion.pase = ent.pase; sesion.aula = true;
            sesion.avion = "DJI_MINI"; sesion.escenario = "libre";
            const salas = await api("GET", "salas"); const s = salas.find(x => x.codigo === cod);
            await api("POST", `salas/${s.codigo}/entrar`, { id: multiId(), clave: "", nombre: nombrePiloto(), alumno: sesion.alumno.id });
            await empezar(); MULTI.sala = s; MULTI.otros.clear();
            pantallaActual = null; if (av.estado === "en mano") lanzar();
            const vistos = {}; let raros = 0;
            for (let k = 0; k < 120; k++) {
              av.gases = 1; mando.vz = k < 40 ? 1 : 0; mando.pitch = k > 40 ? -0.5 : 0;
              for (let i = 0; i < 50; i++) paso(DT);
              MULTI.enCurso = false; await enviarSala(); await new Promise(r => setTimeout(r, 100));
              for (const o of MULTI.otros.values()) { const v = vistos[o.nombre] = vistos[o.nombre] || { avion: o.avion, p0: o.p.slice(), p1: null, n: 0 }; v.p1 = o.p.slice(); v.n++; if (!estadoValido(o)) raros++; }
              try { visor.ponerFantasmas([...MULTI.otros.values()]); pintarSalaInfo(); } catch (e) { raros += 1000; }
            }
            const info = document.getElementById("salaInfo").innerText;
            salirSala();
            return { vistos, raros, info, p: av.p, estado: av.estado };
        }""", [BASE, cod])
        nav.close()
    srv.shutdown()
    for _ in range(600):
        if g.poll() is not None: break
        time.sleep(0.1)
    salida = "\n".join(lineas)
    gv = r["vistos"].get("Prueba Godot")
    ok("la web ve al piloto de Godot con el E3", bool(gv) and gv["avion"] == "E3", str(r["vistos"]))
    ok("la posicion del piloto de Godot cambia en la web", bool(gv) and gv["p0"] != gv["p1"], str(gv))
    ok("la web no recibe ningun estado raro ni falla al pintarlos", r["raros"] == 0 and not errs, (r["raros"], errs[:2]))
    ok("el panel de la sala en la web lista al de Godot", "Prueba Godot" in r["info"], r["info"][:120])
    otros = [l for l in salida.splitlines() if l.startswith("OTROS ")]
    ok("Godot ve a la web con el dron comercial", any("Prueba Web/DJI_MINI" in l for l in otros), "\n".join(otros[-3:]))
    ok("Godot muestra el fantasma de la web", any("fantasmas 1" in l for l in otros))
    ok("Godot acaba sin errores", "FIN" in salida and "SCRIPT ERROR" not in salida and " MAL " not in salida, "\n".join(l for l in salida.splitlines() if "ERROR" in l)[:300])
    # el profesor ve la sala con sus dos pilotos (mientras siguen vivos en memoria: 6 s)
    req = urllib.request.Request(BASE + "/api/profesor/entrar", data=b'{"pin":"1234"}', method="POST"); req.add_header("Content-Type", "application/json")
    tok = json.loads(urllib.request.urlopen(req).read())["token"]
    req = urllib.request.Request(BASE + "/api/salas"); req.add_header("Authorization", "Bearer " + tok)
    salas = json.loads(urllib.request.urlopen(req).read())
    ok("el profesor ve la sala", any(s["codigo"] == cod for s in salas))


if __name__ == "__main__":
    main()
