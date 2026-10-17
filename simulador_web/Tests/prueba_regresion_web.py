"""Regresion de la fisica y la jugabilidad del simulador del navegador, de punta a punta: en la pagina REAL
(simulador.html servida por http) se entra sin conexion, se arranca cada vuelo como lo haria el alumno (empezar,
reiniciar, lanzar) y se repite un guion de mandos con la funcion paso() del simulador, con Math.random sustituido por un
generador con semilla. Se apuntan el estado del vehiculo cada 0,5 s y como acaba el vuelo (choque, aterrizaje...).

Seis vuelos: el Entrenador 1 (E3) en el campo (contacto con el suelo), el mismo en "primer vuelo" (evaluador y objetivos), FPV en el circuito
(pista_fpv), el dron comercial desde SABIC contra la fabrica (zonas de detalle, altura del terreno y choque con las
instalaciones), el dron en la operacion de paneles (operaciones.js) y el bipode andando por SABIC (pasoTerrestre).

    python simulador_web/Tests/prueba_regresion_web.py guardar  <fichero.json>   apunta la referencia
    python simulador_web/Tests/prueba_regresion_web.py comparar <fichero.json>   repite y compara: tiene que dar IGUAL

Necesita Python con playwright y Google Chrome. Levanta el solo un http.server en un puerto libre.
"""
import http.server, json, pathlib, socket, socketserver, sys, threading
from playwright.sync_api import sync_playwright

REPO = pathlib.Path(__file__).resolve().parent.parent.parent
SIM = REPO                                  # se sirve la raiz: la web lee ../datos

VUELOS = [
    # id, avion, escenario, lanz (destacado del mapa real o null), guion de mandos (JS: t -> {pitch, yaw, guinada, vz, gases}), duracion s
    ("e3_campo", "E3", "libre", None, "t => ({ pitch: t < 2 ? 0 : 0.35 * Math.sin(0.7 * t), yaw: 0.5 * Math.sin(1.1 * t), gases: t < 8 ? 1 : t < 14 ? 0.5 : 0 })", 30),
    ("e3_primer_vuelo", "E3", "primer_vuelo", None, "t => ({ pitch: t < 3 ? -0.1 : 0.25 * Math.sin(0.5 * t), yaw: 0.6 * Math.sin(0.8 * t), gases: t < 12 ? 1 : 0.6 })", 30),
    ("fpv_circuito", "FPV", "fpv_circuito", None, "t => ({ pitch: t < 1 ? 0 : -0.4 * Math.sin(0.9 * t), yaw: 0.3 * Math.sin(1.3 * t), guinada: 0.2 * Math.sin(0.4 * t), gases: t < 1 ? 0 : 0.55 + 0.1 * Math.sin(2 * t) })", 25),
    ("dron_sabic", "DJI_MINI", "libre_cartagena", "SABIC", "t => ({ vz: t < 4 ? 1 : 0, pitch: t > 4 ? -1 : 0, yaw: 0, guinada: t > 4 && t < 7 ? -0.5 : 0 })", 90),
    ("dron_paneles", "DJI_MINI", "op_paneles", None, "t => ({ vz: t < 3 ? 1 : 0, pitch: t > 3 ? -0.6 : 0, yaw: 0.2 * Math.sin(0.3 * t), guinada: 0 })", 40),
    ("bipode_sabic", "BIPODE", "libre_cartagena", "SABIC", "t => ({ vz: 1, guinada: t > 10 && t < 14 ? 0.5 : 0, yaw: 0.3, pitch: 0.2, disparo: t > 5 && t < 7 })", 60),
]

GUION = r"""
async ([id, avion, escenario, dest, fmando, dur]) => {
  const errores = [];
  window.addEventListener("error", e => errores.push(String(e.message)));
  // sin el bucle de animacion: la fisica la llevamos nosotros
  window.requestAnimationFrame = cb => setTimeout(() => cb(performance.now()), 5);
  salirDelAula(); irInicio();
  sesion.avion = avion; sesion.escenario = escenario; sesion.dificultad = "real"; sesion.viento = { vel: 3, desde: 45, rachas: true };
  if (dest) { const M = mundoDe(escenario); const d = ESCENARIOS[escenario].destacados.find(x => x.nombre.startsWith(dest)); sesion.lanz = { mundo: M.id, N: Math.round(latLonANE(M, d.lat, d.lon)[0]), E: Math.round(latLonANE(M, d.lat, d.lon)[1]), rumbo: d.rumbo, destacado: d.nombre }; }
  await empezar();
  pantallaActual = "prueba";                 // el bucle del simulador no toca la fisica
  // azar con semilla (mulberry32): mismos numeros en cada ejecucion
  let s = 0x9e3779b9; Math.random = () => { s |= 0; s = s + 0x6D2B79F5 | 0; let t = Math.imul(s ^ s >>> 15, 1 | s); t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t; return ((t ^ t >>> 14) >>> 0) / 4294967296; };
  reiniciar();
  const f = eval(fmando), out = { id, muestras: [], final: null, toasts: [] };
  const toast0 = window.toast; window.toast = (m) => { out.toasts.push(String(m)); toast0(m); };
  const tv0 = window.terminarVuelo; window.terminarVuelo = (f, vn) => { out.final = String(f); tv0(f, vn); };
  const empieza = () => { if (av.estado === "en mano") { if (modelo.esFPV) av.gases = 0; lanzar(); } };
  for (let i = 0; i <= Math.round(dur / DT); i++) {
    const t = i * DT, m = f(t);
    if (i === 25) empieza();
    mando.pitch = m.pitch || 0; mando.yaw = m.yaw || 0; mando.guinada = m.guinada || 0; mando.vz = m.vz || 0; mando.disparo = !!m.disparo;
    if (m.gases !== undefined) av.gases = m.gases;
    if (modelo.esCuadricoptero && !modelo.esFPV && av.estado === "volando" && av.posado && i > 30) av.gases = 1;   // el dron: gas para despegar
    paso(DT);
    if (i % 250 === 0) out.muestras.push({ t: +t.toFixed(3), p: av.p.slice(), v: av.v.slice(), q: av.q.slice(), estado: av.estado, V: av.V, agl: av.agl, gases: av.gases, T: av.T, Wh: av.Wh });
    if (av.estado !== "volando" && i > 100) { out.muestras.push({ t: +t.toFixed(3), p: av.p.slice(), estado: av.estado }); break; }
  }
  out.objetivos = ev && ev.obj ? Object.fromEntries(Object.entries(ev.obj).map(([k, o]) => [k, o.estado])) : null;
  out.errores = errores;
  window.toast = toast0; window.terminarVuelo = tv0;
  return out;
}
"""


def servidor():
    class Silencioso(http.server.SimpleHTTPRequestHandler):
        def log_message(self, *a): pass
        def __init__(self, *a, **k): super().__init__(*a, directory=str(SIM), **k)
    s = socketserver.ThreadingTCPServer(("127.0.0.1", 0), Silencioso); s.daemon_threads = True
    threading.Thread(target=s.serve_forever, daemon=True).start()
    return s, s.server_address[1]


def ejecutar():
    srv, puerto = servidor(); res = {}
    with sync_playwright() as p:
        nav = p.chromium.launch(channel="chrome", headless=True, args=["--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist"])
        pg = nav.new_page(viewport={"width": 1280, "height": 720}); errores = []
        pg.on("pageerror", lambda e: errores.append(str(e)))
        pg.goto(f"http://127.0.0.1:{puerto}/simulador_web/simulador.html"); pg.wait_for_function("typeof visor !== \"undefined\" && visor && Modelos.ids().length > 0")
        for v in VUELOS:
            r = pg.evaluate(GUION, list(v)); r["errores"] += errores[:]; errores.clear()
            res[v[0]] = r
            print("  %-16s muestras %3d  final: %s  errores: %d" % (v[0], len(r["muestras"]), r["final"], len(r["errores"])))
        nav.close()
    srv.shutdown()
    return res


def main():
    modo, fichero = sys.argv[1], pathlib.Path(sys.argv[2])
    res = ejecutar()
    if modo == "guardar":
        fichero.write_text(json.dumps(res, indent=0), encoding="utf-8"); print("guardado", fichero); return
    ref = json.loads(fichero.read_text(encoding="utf-8")); mal = 0
    for k, r in res.items():
        if r.get("errores"): print("MAL", k, "errores en la pagina:", r["errores"][:3]); mal += 1
        if k not in ref: print("MAL", k, "no esta en la referencia"); mal += 1; continue
        a, b = ref[k], r
        igual = a["muestras"] == b["muestras"] and a["final"] == b["final"] and a["objetivos"] == b["objetivos"] and a["toasts"] == b["toasts"]
        if not igual:
            mal += 1; dif = next((i for i, (x, y) in enumerate(zip(a["muestras"], b["muestras"])) if x != y), None)
            print("MAL", k, "distinto; primera muestra distinta:", dif, "final", a["final"], "->", b["final"])
        else: print("OK ", k, "identico (%d muestras, final: %s)" % (len(b["muestras"]), b["final"]))
    print("RESULTADO:", "todo igual" if not mal else "%d vuelos distintos" % mal)
    sys.exit(1 if mal else 0)


if __name__ == "__main__":
    main()
