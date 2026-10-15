"""Medidas de rendimiento del simulador del navegador, para comparar antes y despues de un cambio (mismo PC, misma
version de Chrome; se repite cada medida varias veces y se da la mediana):
  - paso():   tiempo de 5.000 pasos de fisica (10 s de vuelo) del E3 en el campo y del dron comercial en SABIC (con zonas)
  - hud():    tiempo de 2.000 llamadas al HUD en vuelo (lo que escribe en la pagina cada cuadro)
  - dibujar:  tiempo de 60 cuadros de visor.dibujar + hud (con SwiftShader, solo sirve como comparacion relativa)
  - memoria:  geometrias y texturas vivas en la GPU (renderer.info.memory) tras 12 cambios de vehiculo, 12 vistas previas
              del hangar y 6 reinicios de una operacion; y el monton de JS (performance.memory) tras 5.000 pasos
  - empezar:  tiempo de empezar() en SABIC la 1.a vez y las 2 siguientes (la recarga de las zonas de detalle)
  - carga:    bytes de los scripts que descarga la pagina

    python simulador_godot/pruebas/medir_rendimiento_web.py [fichero.json]     (guarda las medidas si se da el fichero)
"""
import http.server, json, pathlib, socketserver, statistics, sys, threading
from playwright.sync_api import sync_playwright

REPO = pathlib.Path(__file__).resolve().parent.parent.parent
SIM = REPO / "simulador"

PREP = r"""
async ([avion, escenario, dest]) => {
  window.requestAnimationFrame = cb => setTimeout(() => cb(performance.now()), 5);
  salirDelAula(); irInicio();
  sesion.avion = avion; sesion.escenario = escenario; sesion.dificultad = "real";
  if (dest) { const M = mundoDe(escenario); const d = ESCENARIOS[escenario].destacados.find(x => x.nombre.startsWith(dest)); sesion.lanz = { mundo: M.id, N: Math.round(latLonANE(M, d.lat, d.lon)[0]), E: Math.round(latLonANE(M, d.lat, d.lon)[1]), rumbo: d.rumbo, destacado: d.nombre }; }
  const t0 = performance.now(); await empezar(); const t = performance.now() - t0;
  pantallaActual = "prueba"; reiniciar(); return t;
}
"""
MEDIR_PASO = r"""
(n) => {
  let s = 0x9e3779b9; Math.random = () => { s |= 0; s = s + 0x6D2B79F5 | 0; let t = Math.imul(s ^ s >>> 15, 1 | s); t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t; return ((t ^ t >>> 14) >>> 0) / 4294967296; };
  reiniciar(); if (av.estado === "en mano") lanzar(); av.p[2] -= 60; av.v = [modelo.esCuadricoptero ? 0 : 12, 0, 0]; av.estado = "volando"; av.posado = false;
  mando.pitch = 0.05; mando.yaw = 0.1; mando.vz = 0.2; av.gases = 0.7;
  const m0 = performance.memory ? performance.memory.usedJSHeapSize : 0, t0 = performance.now();
  for (let i = 0; i < n; i++) { if (av.estado !== "volando") { av.estado = "volando"; av.p[2] = -100; } paso(DT); }
  const t = performance.now() - t0; const m1 = performance.memory ? performance.memory.usedJSHeapSize : 0;
  return { ms: t, heapMB: (m1 - m0) / 1048576 };
}
"""
MEDIR_HUD = r"""
(n) => { av.estado = "volando"; vuelo = vuelo || { tVuelo: 0, hmax: 0, filas: [] }; pantallaActual = null;
  const t0 = performance.now(); for (let i = 0; i < n; i++) { av.t += 0.016; hud(); } const t = performance.now() - t0; pantallaActual = "prueba"; return t; }
"""
MEDIR_DIBUJAR = r"""
(n) => { av.estado = "volando"; pantallaActual = null; const t0 = performance.now();
  for (let i = 0; i < n; i++) { av.t += 0.016; av.p[0] += 0.3; visor.dibujar(av); hud(); } const t = performance.now() - t0; pantallaActual = "prueba";
  return { ms: t, llamadas: visor.renderer.info.render.calls, triangulos: visor.renderer.info.render.triangles }; }
"""
MEDIR_MEMORIA = r"""
async () => {
  const mem = () => ({ geometrias: visor.renderer.info.memory.geometries, texturas: visor.renderer.info.memory.textures });
  const ids = Modelos.ids().filter(id => !Modelos.datos(id).oculto);
  const antes = mem();
  for (let k = 0; k < 12; k++) visor.ponerAvion(Modelos.datos(ids[k % ids.length]));
  visor.ponerAvion(Modelos.datos(sesion.avion)); visor.dibujar(av); const vehiculos = mem();
  for (let k = 0; k < 12; k++) { previa.mostrar(Modelos.datos(ids[k % ids.length])); previa.pintar(performance.now()); }
  const previas = mem();
  let operacion = null;
  if (visor.ponerOperacion && ev && ev.op) { for (let k = 0; k < 6; k++) reiniciar(); visor.dibujar(av); operacion = mem(); }
  return { antes, vehiculos, previas, operacion };
}
"""


def servidor():
    class H(http.server.SimpleHTTPRequestHandler):
        def log_message(self, *a): pass
        def __init__(self, *a, **k): super().__init__(*a, directory=str(SIM), **k)
    s = socketserver.ThreadingTCPServer(("127.0.0.1", 0), H); s.daemon_threads = True
    threading.Thread(target=s.serve_forever, daemon=True).start()
    return s, s.server_address[1]


def mediana(f, n=5):
    return statistics.median(f() for _ in range(n))


def main():
    srv, puerto = servidor(); R = {}
    with sync_playwright() as p:
        nav = p.chromium.launch(channel="chrome", headless=True, args=["--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist", "--enable-precise-memory-info"])
        pg = nav.new_page(viewport={"width": 1280, "height": 720}); bytes_js = {}
        pg.on("response", lambda r: bytes_js.__setitem__(r.url.split("/")[-1], int(r.headers.get("content-length") or 0)) if r.url.endswith(".js") else None)
        pg.goto(f"http://127.0.0.1:{puerto}/simulador.html"); pg.wait_for_function("typeof visor !== 'undefined' && visor && Modelos.ids().length > 0")
        pg.wait_for_timeout(1500)
        R["carga_js_kB"] = {k: round(v / 1024) for k, v in sorted(bytes_js.items(), key=lambda kv: -kv[1])[:8]}
        R["carga_js_total_kB"] = round(sum(bytes_js.values()) / 1024)
        # E3 en el campo
        pg.evaluate(PREP, ["E3", "libre", None])
        R["paso_e1_campo_ms"] = round(mediana(lambda: pg.evaluate(MEDIR_PASO, 5000)["ms"]), 1)
        R["heap_e1_5000pasos_MB"] = round(pg.evaluate(MEDIR_PASO, 5000)["heapMB"], 2)
        R["hud_e1_2000_ms"] = round(mediana(lambda: pg.evaluate(MEDIR_HUD, 2000)), 1)
        d = pg.evaluate(MEDIR_DIBUJAR, 60); R["dibujar_e1_60_ms"] = round(mediana(lambda: pg.evaluate(MEDIR_DIBUJAR, 60)["ms"], 3), 1); R["dibujar_e1_llamadas"] = d["llamadas"]
        # dron en SABIC (zonas de detalle)
        t1 = pg.evaluate(PREP, ["DJI_MINI", "libre_cartagena", "SABIC"]); t2 = pg.evaluate(PREP, ["DJI_MINI", "libre_cartagena", "SABIC"]); t3 = pg.evaluate(PREP, ["DJI_MINI", "libre_cartagena", "SABIC"])
        R["empezar_sabic_ms"] = [round(t1), round(t2), round(t3)]
        R["paso_dron_sabic_ms"] = round(mediana(lambda: pg.evaluate(MEDIR_PASO, 5000)["ms"]), 1)
        R["heap_dron_5000pasos_MB"] = round(pg.evaluate(MEDIR_PASO, 5000)["heapMB"], 2)
        R["hud_dron_2000_ms"] = round(mediana(lambda: pg.evaluate(MEDIR_HUD, 2000)), 1)
        d = pg.evaluate(MEDIR_DIBUJAR, 60); R["dibujar_dron_60_ms"] = round(mediana(lambda: pg.evaluate(MEDIR_DIBUJAR, 60)["ms"], 3), 1); R["dibujar_dron_llamadas"] = d["llamadas"]
        # memoria de la GPU: cambios de vehiculo, vistas previas y reinicios de una operacion
        pg.evaluate(PREP, ["DJI_MINI", "op_paneles", None])
        R["memoria_gpu"] = pg.evaluate(MEDIR_MEMORIA)
        nav.close()
    srv.shutdown()
    for k, v in R.items(): print("  %-28s %s" % (k, v))
    if len(sys.argv) > 1: pathlib.Path(sys.argv[1]).write_text(json.dumps(R, indent=1), encoding="utf-8"); print("guardado", sys.argv[1])


if __name__ == "__main__":
    main()
