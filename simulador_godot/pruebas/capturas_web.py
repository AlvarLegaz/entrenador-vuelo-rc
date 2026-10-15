"""Capturas deterministas del simulador del navegador para comparar los graficos antes y despues de un cambio: las
mismas vistas (vehiculo, escenario, camara, instante del vuelo con el azar sembrado y el reloj congelado) tienen que
dar la misma imagen. Con "comparar" cuenta los pixeles que cambian respecto a otra carpeta.

    python simulador_godot/pruebas/capturas_web.py guardar  <carpeta>
    python simulador_godot/pruebas/capturas_web.py comparar <carpeta_antes> <carpeta_despues>
"""
import http.server, pathlib, socketserver, sys, threading
from playwright.sync_api import sync_playwright

REPO = pathlib.Path(__file__).resolve().parent.parent.parent
SIM = REPO / "simulador"
VISTAS = [  # nombre, avion, escenario, destacado, camara, pasos de fisica antes de la foto
    ("e3_campo_cam1", "E3", "libre", None, 1, 1500), ("e3_campo_cam2", "E3", "libre", None, 2, 1500),
    ("t1_primer_vuelo_cam1", "T1", "primer_vuelo", None, 1, 1200), ("fpv_circuito_cam3", "FPV", "fpv_circuito", None, 3, 2000),
    ("dron_sabic_cam3", "DJI_MINI", "libre_cartagena", "SABIC", 3, 3000), ("dron_sabic_cam2", "DJI_MINI", "libre_cartagena", "SABIC", 2, 3000),
    ("dron_paneles_cam3", "DJI_MINI", "op_paneles", None, 3, 2500), ("bipode_sabic_cam2", "BIPODE", "libre_cartagena", "SABIC", 2, 2000),
]
GUION = r"""
async ([avion, escenario, dest, camara, pasos]) => {
  window.requestAnimationFrame = cb => setTimeout(() => cb(performance.now()), 5);
  salirDelAula(); irInicio();
  sesion.avion = avion; sesion.escenario = escenario; sesion.dificultad = "real"; sesion.viento = { vel: 2, desde: 0, rachas: false };
  if (dest) { const M = mundoDe(escenario); const d = ESCENARIOS[escenario].destacados.find(x => x.nombre.startsWith(dest)); sesion.lanz = { mundo: M.id, N: Math.round(latLonANE(M, d.lat, d.lon)[0]), E: Math.round(latLonANE(M, d.lat, d.lon)[1]), rumbo: d.rumbo, destacado: d.nombre }; }
  await empezar(); pantallaActual = "prueba";
  let s = 12345; Math.random = () => { s |= 0; s = s + 0x6D2B79F5 | 0; let t = Math.imul(s ^ s >>> 15, 1 | s); t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t; return ((t ^ t >>> 14) >>> 0) / 4294967296; };
  reiniciar(); if (modelo.esFPV) av.gases = 0; lanzar();
  for (let i = 0; i < pasos; i++) {
    const t = i * DT; mando.pitch = modelo.esCuadricoptero ? (t > 3 ? -0.5 : 0) : 0.2 * Math.sin(0.7 * t); mando.yaw = 0.3 * Math.sin(1.1 * t); mando.vz = t < 3 ? 1 : 0; mando.guinada = 0;
    av.gases = modelo.esFPV ? 0.5 : 1; if (modelo.esCuadricoptero && !modelo.esFPV && av.posado) av.gases = 1;
    paso(DT); if (av.estado !== "volando") break;
  }
  visor.camara = camara; pantallaActual = null;
  const pn = performance.now.bind(performance); performance.now = () => 987654;   // reloj congelado: agua, luces y humo quietos
  for (let k = 0; k < 3; k++) { visor.dibujar(av); hud(); }
  pantallaActual = "prueba"; performance.now = pn;
  return { p: av.p, estado: av.estado };
}
"""


def servidor():
    class H(http.server.SimpleHTTPRequestHandler):
        def log_message(self, *a): pass
        def __init__(self, *a, **k): super().__init__(*a, directory=str(SIM), **k)
    s = socketserver.ThreadingTCPServer(("127.0.0.1", 0), H); s.daemon_threads = True
    threading.Thread(target=s.serve_forever, daemon=True).start()
    return s, s.server_address[1]


def guardar(carpeta):
    carpeta.mkdir(parents=True, exist_ok=True); srv, puerto = servidor()
    with sync_playwright() as p:
        nav = p.chromium.launch(channel="chrome", headless=True, args=["--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist"])
        pg = nav.new_page(viewport={"width": 1280, "height": 720}, device_scale_factor=1)
        pg.goto(f"http://127.0.0.1:{puerto}/simulador.html"); pg.wait_for_function("typeof visor !== 'undefined' && visor && Modelos.ids().length > 0")
        for nombre, avion, esc, dest, cam, pasos in VISTAS:
            r = pg.evaluate(GUION, [avion, esc, dest, cam, pasos]); pg.wait_for_timeout(300)
            pg.screenshot(path=str(carpeta / (nombre + ".png"))); print("  %-22s %s %s" % (nombre, r["estado"], [round(x, 1) for x in r["p"]]))
        # la vista previa del hangar
        pg.evaluate("salirDelAula(); irInicio(); elegirAvion('DJI_MINI'); irHangar(); pantallaActual = 'prueba'; previa.pintar(100000)"); pg.wait_for_timeout(500)   # sin el bucle: el giro de la vista previa, fijo
        pg.evaluate("previa.pintar(100000)"); pg.screenshot(path=str(carpeta / "hangar_dron.png")); print("  hangar_dron")
        nav.close()
    srv.shutdown()


def comparar(a, b):
    from PIL import Image, ImageChops
    mal = 0
    for f in sorted(a.glob("*.png")):
        g = b / f.name
        if not g.exists(): print("MAL falta", g); mal += 1; continue
        A, B = Image.open(f).convert("RGB"), Image.open(g).convert("RGB")
        if A.size != B.size: print("MAL tamano distinto", f.name); mal += 1; continue
        d = ImageChops.difference(A, B).convert("L").point(lambda v: 255 if v > 8 else 0)
        n = sum(1 for v in d.getdata() if v); pct = 100.0 * n / (A.size[0] * A.size[1])
        print("  %s %-22s pixeles distintos: %6d (%.2f %%)" % ("OK " if pct < 0.5 else "MAL", f.name, n, pct))
        if pct >= 0.5: mal += 1
    print("RESULTADO:", "todo igual" if not mal else "%d capturas distintas" % mal)
    sys.exit(1 if mal else 0)


if __name__ == "__main__":
    if sys.argv[1] == "guardar": guardar(pathlib.Path(sys.argv[2]))
    else: comparar(pathlib.Path(sys.argv[2]), pathlib.Path(sys.argv[3]))
