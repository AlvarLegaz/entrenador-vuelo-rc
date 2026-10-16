"""Prueba del modo Taller (js/taller.js y scripts/pantalla_taller.gd) de punta a punta, con un servidor del aula de
prueba (datos temporales, PIN 2468): en la web un alumno vuela el Mini Dron HQ 40 s (con un aviso en pantalla); en el Taller el
Mini dice que tiene 1 registro (y el bipode no sale), "Conectar y descargar" lo lista, su detalle da el resumen, las
graficas con el cursor y el CSV que se descarga es el del registro; borrado del navegador, el Taller lo baja del aula.
Despues Godot (pruebas/prueba_taller.gd) abre ESE MISMO registro: el mismo resumen, las mismas graficas y el mismo CSV
que la web, y tambien lo baja del aula. Los datos de usuario de Godot se dejan como estaban.

    python simulador_godot/pruebas/prueba_taller.py
"""
import http.server, json, pathlib, os, shutil, socketserver, subprocess, sys, tempfile, threading, time, urllib.error, urllib.request
from playwright.sync_api import sync_playwright

REPO = pathlib.Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(REPO / "aula"))
GODOT = REPO / "herramientas" / "godot" / "Godot_v4.7.2-stable_win64_console.exe"
PUERTO = 8097
BASE = "http://127.0.0.1:%d" % PUERTO
DATOS_GODOT = pathlib.Path(os.environ["APPDATA"]) / "Godot" / "app_userdata" / "Entrenador Vuelo RC v2 (Godot)"
fallos = 0


def ok(nombre, cond, detalle=""):
    global fallos
    if not cond: fallos += 1
    print("  %s %s %s" % ("OK " if cond else "MAL", nombre, detalle))


VOLAR = r"""
async ([base]) => {
  window.requestAnimationFrame = cb => setTimeout(() => cb(performance.now()), 5);
  salirDelAula(); irInicio(); try { localStorage.setItem("evrc_url_aula", base); } catch (e) {}
  const ent = await api("POST", "entrar", { usuario: "Piloto Taller", clave: "abcd", crear: true });
  sesion.alumno = ent.alumno; sesion.pase = ent.pase; sesion.aula = true;
  sesion.avion = "DJI_MINI"; sesion.escenario = "libre"; await empezar();
  await new Promise(r => { const f = () => (pantallaActual === null && av && modelo) ? r() : setTimeout(f, 50); f(); });
  pantallaActual = "prueba"; lanzar(); modelo.despegar(av);
  for (let i = 0; i < 40 / DT; i++) {
    const t = i * DT; mando.vz = t < 6 ? 1 : 0; mando.pitch = t > 8 && t < 25 ? -0.8 : (t > 28 ? 0.8 : 0); paso(DT);
    if (i === Math.round(15 / DT)) toast("Aviso de prueba del taller");
  }
  const id = vuelo.id; terminarVuelo("abandonado");
  let reg = null; for (let k = 0; k < 50 && !reg; k++) { await new Promise(r => setTimeout(r, 100)); reg = await RegistroDB.leer(id); }
  for (let k = 0; k < 100 && reg && reg.subir; k++) { await new Promise(r => setTimeout(r, 100)); reg = await RegistroDB.leer(id); }
  irInicio();
  const { subir, ...limpio } = reg;
  return { reg: limpio, alumno: ent.alumno.id, resumen: Taller.resumen(reg), paneles: Taller.paneles(reg).map(p => [p[0], p[1].map(s => s[0])]), csv: registroCSV(reg) };
}
"""


def main():
    import servidor_aula as sa
    datos = tempfile.mkdtemp(prefix="aula_taller_")
    sa.usar_datos(datos); sa.crear_bd()
    con = sa.conectar()                              # con el PIN puesto (si no, el servidor lo pregunta al arrancar)
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
        pruebas(datos)
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


def pruebas(datos):
    class H(http.server.SimpleHTTPRequestHandler):
        def __init__(s, *a, **k): super().__init__(*a, directory=str(REPO / "simulador"), **k)
        def log_message(s, *a): pass
    srv = socketserver.ThreadingTCPServer(("127.0.0.1", 0), H); srv.daemon_threads = True
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    with sync_playwright() as p:
        nav = p.chromium.launch(channel="chrome", headless=True, args=["--use-angle=swiftshader", "--enable-unsafe-swiftshader"])
        ctx = nav.new_context(accept_downloads=True, viewport={"width": 1500, "height": 950}); pg = ctx.new_page(); errs = []
        pg.on("pageerror", lambda e: errs.append(str(e)))
        pg.goto("http://127.0.0.1:%d/simulador.html" % srv.server_address[1]); pg.wait_for_function("typeof visor !== 'undefined' && visor && Modelos.ids().length > 0")
        w = pg.evaluate(VOLAR, [BASE]); reg = w["reg"]
        pg.click("#mnTaller"); pg.wait_for_selector("#tallerConectar"); pg.wait_for_selector(".tallerVeh.sel")
        veh = pg.inner_text("#tallerLista")
        ok("web: el Taller lista los vehiculos (sin el bipode) y el Mini con su registro", "Mini Dron HQ\n1 registro en este ordenador" in veh and "Bípode" not in veh and "Vehículo secreto" not in veh, veh.replace("\n", " / ")[:200])
        ok("web: la ficha de su bateria", "Batería Li-ion 2S de 2250 mAh" in pg.inner_text("#tallerCentro"), pg.inner_text("#tallerCentro")[:120])
        pg.click("#tallerConectar"); pg.wait_for_selector(".tablaTaller tr[data-i]", timeout=10000)
        filas = pg.locator(".tablaTaller tr[data-i]")
        ok("web: conectar y descargar lista el vuelo (de este ordenador, aunque tambien este en el aula)", filas.count() == 1 and "este ordenador" in filas.first.inner_text(), filas.first.inner_text().replace("\t", " | "))
        filas.first.click(); pg.wait_for_selector("#tallerGraf")
        res = pg.locator(".resumenTaller div").all_inner_texts()
        ok("web: el resumen del detalle", [r.split("\n") for r in res] == w["resumen"], str(res[:4]))
        ok("web: las cinco graficas (bateria y tension, celdas, corriente y potencia, temperatura, altura y velocidad)", len(w["paneles"]) == 5 and w["paneles"][1][1] == ["celda1_V", "celda2_V"], str([x[0] for x in w["paneles"]]))
        ok("web: el aviso, en la lista de avisos", "Aviso de prueba del taller" in pg.inner_text("#tallerEventos"))
        bb = pg.locator("#tallerGraf").bounding_box(); pg.mouse.move(bb["x"] + bb["width"] / 2, bb["y"] + 80); pg.wait_for_timeout(100)
        cur = pg.inner_text("#tallerCursor")
        ok("web: el cursor da los valores en ese momento", "bateria pct" in cur and "celda2 V" in cur and "altura despegue m" in cur, cur[:140])
        with pg.expect_download() as dl: pg.click("#tallerCSV")
        texto = open(dl.value.path(), encoding="utf-8").read()
        ok("web: Exportar CSV descarga el registro", dl.value.suggested_filename.startswith("registro_DJI_MINI_") and texto == w["csv"] and texto.count("\n") == len(reg["filas"]) + 1, dl.value.suggested_filename)
        pg.screenshot(path=str(pathlib.Path(datos) / "taller_web.png"))
        # borrado del navegador: el Taller lo baja del aula
        pg.evaluate("async id => { await RegistroDB._tx('readwrite', s => s.delete(id)); irInicio(); }", reg["id"])
        pg.click("#mnTaller"); pg.wait_for_selector("#tallerConectar"); pg.wait_for_selector(".tallerVeh.sel")
        try: pg.wait_for_function("() => /sin registros/.test(document.querySelector('.tallerVeh.sel').innerText)", timeout=5000); sin = True
        except Exception: sin = False
        ok("web: sin el registro en el navegador", sin, pg.locator(".tallerVeh.sel").inner_text())
        pg.click("#tallerConectar"); pg.wait_for_selector(".tablaTaller tr[data-i]", timeout=10000)
        ok("web: conectar lo baja del aula", "aula" in pg.locator(".tablaTaller tr[data-i]").first.inner_text())
        pg.locator(".tablaTaller tr[data-i]").first.click(); pg.wait_for_selector("#tallerGraf")
        ok("web: y su detalle es el mismo", pg.locator(".resumenTaller div").all_inner_texts() == res)
        ok("web: sin errores en la pagina", not errs, errs[:3])
        nav.close()
    srv.shutdown()
    # Godot, con ESE MISMO registro y el mismo alumno
    f = pathlib.Path(datos) / "taller_web.json"
    f.write_text(json.dumps({"reg": reg, "resumen": w["resumen"], "paneles": w["paneles"], "csv": w["csv"]}, ensure_ascii=False), encoding="utf-8")
    g = subprocess.run([str(GODOT), "--headless", "--path", str(REPO / "simulador_godot"), "--script", "res://pruebas/prueba_taller.gd", "--",
                        "--web=" + str(f), "--aula=" + BASE, "--usuario=Piloto Taller", "--clave=abcd"], capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=600)
    lineas = [l for l in g.stdout.splitlines() if l.startswith("  OK ") or l.startswith("  MAL ")]
    for l in lineas:
        print("  Godot:", l.strip())
        if l.startswith("  MAL "): globals()["fallos"] += 1
    ok("Godot: la prueba ha corrido entera", "RESULTADO" in g.stdout and len(lineas) >= 8, "" if "RESULTADO" in g.stdout else g.stdout[-600:] + g.stderr[-600:])


if __name__ == "__main__":
    main()
