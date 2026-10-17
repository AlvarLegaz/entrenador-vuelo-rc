"""Prueba de carga del servidor del aula: una clase entera a la vez contra un aula de verdad.

Cada alumno simulado hace lo que hace el simulador:
  - entra con usuario y clave (todos a la vez, al empezar la clase) y, si se pide, carga la pagina del simulador;
  - vuela en una sala multijugador mandando su estado 10 veces por segundo (lo mas pesado: 30 alumnos = 300 peticiones/s);
  - al acabar cada vuelo (cada --vuelo s) manda el vuelo y su registro de vuelo (gzip, 5 min a 10 Hz) y mira su ficha.
El panel del profesor refresca la lista de alumnos y las salas cada 2 s.

Mide, por tipo de peticion, cuantas, cuantos errores y los tiempos (mediana, p95, p99 y maximo). Pasa si no hay errores
(salvo algun corte suelto: < 0,5 %), el estado multijugador va a >= 90 % de su ritmo y su p95 es < 250 ms.

    python aula/Tests/prueba_carga_aula.py                         arranca un aula temporal en este ordenador
    python aula/Tests/prueba_carga_aula.py --alumnos 60 --duracion 120
    python aula/Tests/prueba_carga_aula.py --base https://192.168.1.20 --pin 123456 --pagina    contra un despliegue
                                         (Docker_web: certificado autofirmado aceptado; los alumnos "Carga NN" se borran al acabar)
"""
import argparse, gzip, http.client, json, math, os, pathlib, random, re, socket, ssl, statistics, subprocess, sys, tempfile, threading, time, urllib.parse, uuid

REPO = pathlib.Path(__file__).resolve().parents[2]
SIN_VERIFICAR = ssl._create_unverified_context()       # el certificado autofirmado de Docker_web


class Cliente:
    """Una conexion por hilo, reutilizada mientras el servidor la deje abierta (como el navegador con nginx; el aula sola
    cierra cada una: HTTP/1.0)."""
    def __init__(self, base):
        u = urllib.parse.urlsplit(base)
        self.https, self.host, self.puerto = u.scheme == "https", u.hostname, u.port or (443 if u.scheme == "https" else 80)
        self.c = None

    def pedir(self, metodo, ruta, cuerpo=None, cabeceras=None, crudo=None):
        h = dict(cabeceras or {})
        datos = crudo if crudo is not None else (json.dumps(cuerpo).encode() if cuerpo is not None else None)
        if cuerpo is not None and crudo is None: h["Content-Type"] = "application/json"
        for intento in (0, 1):
            if self.c is None:
                self.c = (http.client.HTTPSConnection(self.host, self.puerto, timeout=30, context=SIN_VERIFICAR) if self.https
                          else http.client.HTTPConnection(self.host, self.puerto, timeout=30))
            try:
                self.c.request(metodo, ruta, body=datos, headers=h)
                r = self.c.getresponse(); b = r.read()
                if r.will_close: self.c.close(); self.c = None
                return r.status, b
            except (http.client.RemoteDisconnected, BrokenPipeError, ConnectionResetError) as e:
                self.c.close(); self.c = None                 # conexion reutilizada que el servidor ya cerro: otra vez, una sola
                if intento: raise
            except Exception:
                if self.c: self.c.close()
                self.c = None; raise


class Medidas:
    def __init__(self):
        self.t, self.cod, self.ejemplo, self.cerrojo = {}, {}, {}, threading.Lock()

    def apuntar(self, tipo, seg, codigo):
        with self.cerrojo:
            self.t.setdefault(tipo, []).append(seg)
            self.cod.setdefault(tipo, {}); self.cod[tipo][codigo] = self.cod[tipo].get(codigo, 0) + 1

    def medir(self, cli, tipo, metodo, ruta, ok=(200, 201), **kw):
        t0 = time.perf_counter()
        try: c, b = cli.pedir(metodo, ruta, **kw)
        except Exception as e: c, b = type(e).__name__, b""
        self.apuntar(tipo, time.perf_counter() - t0, c if c in ok else "ERR %s" % c)
        if c not in ok:
            self.ejemplo.setdefault(tipo, "%s %s: %s" % (metodo, ruta, b[:160].decode("utf-8", "replace")))
            return None
        try: return json.loads(b) if b[:1] in (b"{", b"[") else b
        except ValueError: return b


def pct(v, p):
    v = sorted(v); return v[min(len(v) - 1, int(math.ceil(p / 100 * len(v))) - 1)] if v else 0


def registro_vuelo(aid, n=3000):
    """Un registro de vuelo como el del simulador: 5 min a 10 Hz con 20 columnas, comprimido."""
    cols = ["tiempo_s", "latitud", "longitud", "altura_m", "agl_m", "vel_ms", "rumbo", "alabeo", "cabeceo", "gas", "bateria_v",
            "bateria_pct", "corriente_a", "mah", "viento_ms", "modo", "satelites", "senal", "distancia_m", "aviso"]
    filas = [[round(i / 10, 1), 37.61 + i * 1e-6, -1.05 + i * 1e-6, 30 + math.sin(i / 50) * 5, 28.0, 8.2, i % 360, 2.5, -1.0, 0.55,
              15.8 - i * 1e-4, 90 - i * 0.01, 12.3, i * 0.2, 3.1, "N", 14, 98, i * 0.8, None] for i in range(n)]
    reg = dict(id=str(uuid.uuid4()), alumno_id=aid, avion="DJI_MINI", avion_nombre="Mini Dron HQ", inicio="2026-10-17T10:00:00",
               escenario="libre", escenario_nombre="Vuelo libre", final="Aterrizaje", duracion_s=n / 10, columnas=cols, filas=filas,
               eventos=[[12.0, "Prueba de carga"]])
    return gzip.compress(json.dumps(reg).encode())


def recursos_pagina(cli):
    """simulador.html y lo que carga (scripts, el indice de escenarios y cada escenario): lo que baja un alumno al abrirlo."""
    c, html = cli.pedir("GET", "/simulador.html")
    if c != 200: return ["/simulador.html"]
    txt = html.decode("utf-8", "replace")
    rs = ["/simulador.html"] + ["/" + s.lstrip("./") for s in re.findall(r'<script src="([^"\' +]+)"', txt)]   # no los que arma un script (' + f + ')
    c, idx = cli.pedir("GET", "/datos/escenarios.js")
    if c == 200: rs += ["/datos/" + f for f in re.findall(r'"([a-z0-9_/]+\.js)"', idx.decode("utf-8", "replace"))]
    return rs


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--base", help="el aula (sin esto, arranca una temporal en este ordenador)")
    ap.add_argument("--pin", default="2468", help="PIN del profesor del aula (para dar de alta a los alumnos y crear las salas)")
    ap.add_argument("--alumnos", type=int, default=30)
    ap.add_argument("--duracion", type=float, default=60, help="segundos de clase")
    ap.add_argument("--hz", type=float, default=10, help="estados por segundo de cada alumno en su sala")
    ap.add_argument("--por-sala", type=int, default=15, help="alumnos por sala multijugador")
    ap.add_argument("--vuelo", type=float, default=20, help="cada cuantos segundos acaba un vuelo cada alumno")
    ap.add_argument("--pagina", action="store_true", help="cada alumno carga tambien el simulador web (servido en --base)")
    a = ap.parse_args()

    proc, base = None, a.base
    if not base:                                            # un aula temporal: datos aparte, PIN de UXS_PIN_PROFESOR
        s = socket.socket(); s.bind(("127.0.0.1", 0)); puerto = s.getsockname()[1]; s.close()
        datos = tempfile.mkdtemp(prefix="aula_carga_")
        proc = subprocess.Popen([sys.executable, str(REPO / "aula" / "servidor_aula.py"), "--puerto", str(puerto), "--datos", datos],
                                env=dict(os.environ, UXS_PIN_PROFESOR=a.pin), stdin=subprocess.DEVNULL,
                                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        base = "http://127.0.0.1:%d" % puerto
        for _ in range(100):
            try:
                if Cliente(base).pedir("GET", "/api/estado")[0] == 200: break
            except OSError: time.sleep(0.1)
    base = base.rstrip("/")
    print("Prueba de carga del aula en %s: %d alumnos, %.0f s, estado a %.0f Hz en salas de %d" % (base, a.alumnos, a.duracion, a.hz, a.por_sala))
    M, prof = Medidas(), Cliente(base)
    alumnos, salas = [], []
    try:
        # ---- preparar: el profesor da de alta a los alumnos y crea las salas ----
        c, b = prof.pedir("POST", "/api/profesor/entrar", {"pin": a.pin})
        if c not in (200, 201): sys.exit("No entra el profesor (%s): %s" % (c, b[:200]))
        tok = json.loads(b)["token"]; P = {"Authorization": "Bearer " + tok}
        marca = uuid.uuid4().hex[:4]
        for i in range(a.alumnos):
            nombre, clave = "Carga %s %02d" % (marca, i + 1), "clave%04d" % i
            c, b = prof.pedir("POST", "/api/profesor/alumnos", {"nombre": nombre, "clave": clave}, P)
            if c not in (200, 201): sys.exit("No se pudo dar de alta a %s (%s): %s" % (nombre, c, b[:200]))
            alumnos.append(dict(nombre=nombre, clave=clave))
        for k in range(math.ceil(a.alumnos / a.por_sala)):
            c, b = prof.pedir("POST", "/api/salas", {"escenario": "libre", "nombre": "Carga %s %d" % (marca, k + 1)}, P)
            if c not in (200, 201): sys.exit("No se pudo crear la sala (%s): %s" % (c, b[:200]))
            salas.append(json.loads(b)["codigo"])
        print("  %d alumnos dados de alta y %d salas creadas" % (len(alumnos), len(salas)))

        fin, empezar = [0.0], threading.Barrier(a.alumnos + 2)      # los alumnos, el profesor y este hilo
        pagina = recursos_pagina(Cliente(base)) if a.pagina else []
        if a.pagina: print("  la pagina del simulador: %d ficheros" % len(pagina))

        def alumno(i):
            al, cli = alumnos[i], Cliente(base)
            empezar.wait()
            for r in pagina: M.medir(cli, "pagina (ficheros)", "GET", r)
            d = M.medir(cli, "entrar (clave)", "POST", "/api/entrar", cuerpo={"usuario": al["nombre"], "clave": al["clave"]})
            if not d: return
            aid, pase = d["alumno"]["id"], d["pase"]; X = {"X-Alumno": pase}; al["id"] = aid
            sala, jid = salas[i // a.por_sala], "carga-%s" % uuid.uuid4().hex[:10]
            M.medir(cli, "sala: entrar", "POST", "/api/salas/%s/entrar" % sala, cuerpo={"id": jid, "nombre": al["nombre"]})
            hilo_acc = threading.Thread(target=acciones, args=(aid, X), daemon=True); hilo_acc.start()
            periodo, sig, k = 1 / a.hz, time.perf_counter() + random.random() / a.hz, 0
            while time.time() < fin[0]:
                k += 1; ang = k / 100 + i
                M.medir(cli, "sala: estado (10 Hz)", "POST", "/api/salas/%s/estado" % sala,
                        cuerpo={"id": jid, "nombre": al["nombre"], "avion": "DJI_MINI", "alumno": aid, "p": [100 * math.cos(ang), 100 * math.sin(ang), 30],
                                "q": [1, 0, 0, 0], "vn": [1, 0, 0], "gas": 0.5, "agl": 30, "tvuelo": k * periodo, "estado": "volando"})
                sig += periodo; espera = sig - time.perf_counter()
                if espera > 0: time.sleep(espera)
                else: sig = time.perf_counter()               # va con retraso: no acumula
            M.medir(cli, "sala: salir", "POST", "/api/salas/%s/salir" % sala, cuerpo={"id": jid})
            hilo_acc.join()

        def acciones(aid, X):
            """Lo que el alumno manda al acabar cada vuelo (en paralelo a la sala, como el simulador)."""
            cli = Cliente(base); time.sleep(random.uniform(0, min(a.vuelo, a.duracion / 2)))
            reg = registro_vuelo(aid)
            while time.time() < fin[0]:
                M.medir(cli, "vuelo", "POST", "/api/vuelos", cabeceras=X, cuerpo={"id": str(uuid.uuid4()), "alumno_id": aid, "inicio": "2026-10-17T10:00:00",
                        "avion": "Mini Dron HQ", "escenario": "libre", "resultado": "APTO", "tiempo_vuelo_s": 300})
                r = json.loads(gzip.decompress(reg)); r["id"] = str(uuid.uuid4())
                M.medir(cli, "registro de vuelo (gzip)", "POST", "/api/registros", cabeceras=dict(X, **{"Content-Type": "application/gzip"}),
                        crudo=gzip.compress(json.dumps(r).encode(), 6))
                M.medir(cli, "ficha del alumno", "GET", "/api/alumnos/" + aid)
                hasta = time.time() + a.vuelo
                while time.time() < min(hasta, fin[0]): time.sleep(0.2)

        def profesor():
            cli = Cliente(base); empezar.wait()
            while time.time() < fin[0]:
                M.medir(cli, "panel: alumnos", "GET", "/api/profesor/alumnos", cabeceras=P)
                M.medir(cli, "panel: salas", "GET", "/api/salas", cabeceras=P)
                for s in salas: M.medir(cli, "panel: sala", "GET", "/api/salas/" + s, cabeceras=P)
                time.sleep(2)

        hilos = [threading.Thread(target=alumno, args=(i,), daemon=True) for i in range(a.alumnos)]
        hp = threading.Thread(target=profesor, daemon=True)
        for h in hilos + [hp]: h.start()
        fin[0] = time.time() + a.duracion + 30              # provisional: hasta que todos hayan entrado
        t0 = time.time(); empezar.wait()
        # la clase dura --duracion desde que entra el ultimo
        while sum(1 for x in alumnos if "id" in x) < a.alumnos and time.time() - t0 < 60: time.sleep(0.05)
        t_entrada = time.time() - t0
        fin[0] = time.time() + a.duracion; tc0 = time.time()
        for h in hilos + [hp]: h.join(a.duracion + 120)
        t_clase = a.duracion

        # ---- resultado ----
        print("\n  todos dentro en %.1f s; clase de %.0f s\n" % (t_entrada, t_clase))
        print("  %-26s %7s %6s %8s %8s %8s %8s" % ("peticion", "n", "error", "mediana", "p95", "p99", "max"))
        total = err = 0
        for tipo in sorted(M.t):
            v, cods = M.t[tipo], M.cod[tipo]; e = sum(n for k, n in cods.items() if isinstance(k, str)); total += len(v); err += e
            print("  %-26s %7d %6d %7.0fms %7.0fms %7.0fms %7.0fms" % (tipo, len(v), e, 1000 * statistics.median(v), 1000 * pct(v, 95), 1000 * pct(v, 99), 1000 * max(v)))
            if e: print("      errores: %s; el primero: %s" % ({k: n for k, n in cods.items() if isinstance(k, str)}, M.ejemplo.get(tipo)))
        est = M.t.get("sala: estado (10 Hz)", [])
        ritmo = len(est) / (a.alumnos * a.hz * t_clase) if t_clase else 0
        print("\n  %d peticiones en total (%.0f/s), %d errores (%.2f %%); estado multijugador al %.0f %% de su ritmo" %
              (total, total / max(1, t_clase), err, 100 * err / max(1, total), 100 * ritmo))
        bien = err <= 0.005 * total and ritmo >= 0.90 and pct(est, 95) < 0.25
        print("  %s" % ("PASA" if bien else "NO PASA"))
        return 0 if bien else 1
    finally:
        # ---- limpiar: las salas y los alumnos de la prueba (archivar y borrar definitivamente) ----
        try:
            c, b = prof.pedir("POST", "/api/profesor/entrar", {"pin": a.pin}); P = {"Authorization": "Bearer " + json.loads(b)["token"]}
            for s in salas: prof.pedir("DELETE", "/api/salas/" + s, cabeceras=P)
            c, b = prof.pedir("GET", "/api/profesor/alumnos", cabeceras=P)
            nombres = {x["nombre"] for x in alumnos}
            for x in (json.loads(b) if c == 200 else []):
                if x.get("nombre") in nombres:
                    prof.pedir("DELETE", "/api/alumnos/" + x["id"]); prof.pedir("DELETE", "/api/profesor/alumnos/" + x["id"], cabeceras=P)
        except Exception as e:
            print("  (no se pudo limpiar: %s)" % e)
        if proc: proc.terminate(); proc.wait(10)


if __name__ == "__main__":
    sys.exit(main())
