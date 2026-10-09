"""Servidor del aula del simulador: sirve el simulador a todos los ordenadores y guarda alumnos y
vuelos en una base de datos SQLite comun. Solo usa la biblioteca estandar de Python.

  python servidor_aula.py                 arranca en el puerto 8080 (la 1.a vez pide el PIN del profesor)
  python servidor_aula.py --puerto 8000
  python servidor_aula.py --cambiar-pin   cambia el PIN del profesor y sale
  python servidor_aula.py --datos OTRA    usa otra carpeta de datos (por ejemplo, para pruebas)

Los demas ordenadores abren en el navegador  http://<IP de este ordenador>:8080
Datos: aula/datos/aula.db. Copias de seguridad: aula/datos/copias (al arrancar, cada hora si hubo
cambios y antes de cada borrado definitivo; se guardan las 60 ultimas).

Proteccion: elegir alumno, darlo de alta, archivarlo (con confirmacion; se puede restaurar) y
guardar vuelos no piden nada. Editar, borrar definitivamente, exportar, copias y autorizar el
avion real piden el PIN del profesor (sesion de 8 h; 5 fallos seguidos bloquean 2 minutos).
"""
import argparse, csv, datetime as dt, getpass, hashlib, hmac, io, json, mimetypes, os, re, secrets, socket
import sqlite3, sys, threading, time, unicodedata, uuid
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs

AQUI = os.path.dirname(os.path.abspath(__file__))
DIR_SIM = os.path.normpath(os.path.join(AQUI, "..", "simulador"))
DIR_DATOS = os.path.join(AQUI, "datos")
DB = os.path.join(DIR_DATOS, "aula.db")
DIR_COPIAS = os.path.join(DIR_DATOS, "copias")
MAX_COPIAS = 60

HORAS_MINIMAS = 10.0
ESCENARIOS = ["primer_vuelo", "orientacion", "viento_cruzado", "emergencia"]
NOMBRES_ESC = {"primer_vuelo": "Primer vuelo", "orientacion": "Orientación", "viento_cruzado": "Viento cruzado",
               "emergencia": "Emergencia", "libre": "Vuelo libre"}

SESIONES = {}            # token -> caduca (epoch)
FALLOS = {}              # ip -> (n fallos, bloqueado hasta)
CERROJO = threading.Lock()
CAMBIOS = {"desde_copia": 0}


# ======================= base de datos =======================
def usar_datos(carpeta):
    global DIR_DATOS, DB, DIR_COPIAS
    DIR_DATOS = os.path.abspath(carpeta)
    DB, DIR_COPIAS = os.path.join(DIR_DATOS, "aula.db"), os.path.join(DIR_DATOS, "copias")


def conectar():
    con = sqlite3.connect(DB, timeout=10)
    con.row_factory = sqlite3.Row
    con.execute("PRAGMA foreign_keys = ON")
    con.execute("PRAGMA busy_timeout = 10000")
    return con


def crear_bd():
    os.makedirs(DIR_COPIAS, exist_ok=True)
    con = conectar()
    con.execute("PRAGMA journal_mode = WAL")
    con.executescript("""
    CREATE TABLE IF NOT EXISTS alumnos (
        id TEXT PRIMARY KEY, nombre TEXT NOT NULL, nombre_norm TEXT NOT NULL, creado TEXT NOT NULL,
        notas TEXT NOT NULL DEFAULT '', archivado INTEGER NOT NULL DEFAULT 0, archivado_en TEXT,
        habilitado INTEGER NOT NULL DEFAULT 0, habilitado_en TEXT);
    CREATE UNIQUE INDEX IF NOT EXISTS alumnos_nombre_activo ON alumnos(nombre_norm) WHERE archivado = 0;
    CREATE TABLE IF NOT EXISTS vuelos (
        id TEXT PRIMARY KEY, alumno_id TEXT NOT NULL REFERENCES alumnos(id) ON DELETE CASCADE,
        inicio TEXT NOT NULL, fin TEXT, equipo TEXT, avion TEXT NOT NULL, escenario TEXT NOT NULL,
        tiempo_vuelo_s REAL NOT NULL DEFAULT 0, accidentes INTEGER NOT NULL DEFAULT 0,
        aterrizajes INTEGER NOT NULL DEFAULT 0, objetivos TEXT NOT NULL DEFAULT '[]',
        resultado TEXT NOT NULL, final TEXT, viento TEXT, recibido TEXT NOT NULL);
    CREATE INDEX IF NOT EXISTS vuelos_alumno ON vuelos(alumno_id, inicio);
    CREATE TABLE IF NOT EXISTS config (clave TEXT PRIMARY KEY, valor TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS registro (id INTEGER PRIMARY KEY AUTOINCREMENT, fecha TEXT NOT NULL,
        accion TEXT NOT NULL, detalle TEXT NOT NULL);
    """)
    con.commit(); con.close()


def ahora():
    return dt.datetime.now().isoformat(timespec="seconds")


def normalizar(nombre):
    s = unicodedata.normalize("NFKD", nombre).encode("ascii", "ignore").decode().lower()
    return re.sub(r"\s+", " ", s).strip()


def registrar(con, accion, detalle):
    con.execute("INSERT INTO registro (fecha, accion, detalle) VALUES (?, ?, ?)", (ahora(), accion, detalle))


def config(con, clave, defecto=None):
    r = con.execute("SELECT valor FROM config WHERE clave = ?", (clave,)).fetchone()
    return r["valor"] if r else defecto


# ======================= PIN del profesor =======================
def hash_pin(pin, sal=None):
    sal = sal or secrets.token_hex(16)
    return sal + "$" + hashlib.pbkdf2_hmac("sha256", pin.encode(), bytes.fromhex(sal), 200_000).hex()


def pin_correcto(con, pin):
    h = config(con, "pin")
    if not h: return False
    sal, _ = h.split("$", 1)
    return hmac.compare_digest(hash_pin(pin, sal), h)


def pedir_pin_consola():
    while True:
        p1 = getpass.getpass("PIN del profesor (4 a 12 cifras): ").strip()
        if not re.fullmatch(r"\d{4,12}", p1):
            print("  Tiene que ser de 4 a 12 cifras."); continue
        if getpass.getpass("Repítelo: ").strip() != p1:
            print("  No coinciden."); continue
        return p1


# ======================= copias de seguridad =======================
def hacer_copia(motivo):
    with CERROJO:
        os.makedirs(DIR_COPIAS, exist_ok=True)
        nombre = "aula_%s_%s.db" % (dt.datetime.now().strftime("%Y%m%d_%H%M%S"), motivo)
        src, dst = conectar(), sqlite3.connect(os.path.join(DIR_COPIAS, nombre))
        src.backup(dst); dst.close(); src.close()
        CAMBIOS["desde_copia"] = 0
        copias = sorted(f for f in os.listdir(DIR_COPIAS) if f.endswith(".db"))
        for f in copias[:-MAX_COPIAS]:
            os.remove(os.path.join(DIR_COPIAS, f))
        return nombre


def copias_periodicas():
    while True:
        time.sleep(3600)
        if CAMBIOS["desde_copia"] > 0:
            try: hacer_copia("hora")
            except Exception as e: print("copia fallida:", e)


# ======================= progreso =======================
def progreso(con, alumno_id):
    r = con.execute("""SELECT COUNT(*) n, COALESCE(SUM(tiempo_vuelo_s), 0) t, COALESCE(SUM(accidentes), 0) acc,
                       COALESCE(SUM(aterrizajes), 0) att, MAX(inicio) ultimo FROM vuelos WHERE alumno_id = ?""",
                    (alumno_id,)).fetchone()
    sup = {row["escenario"] for row in con.execute(
        "SELECT DISTINCT escenario FROM vuelos WHERE alumno_id = ? AND resultado = 'APTO'", (alumno_id,))}
    intentos = {row["escenario"]: row["n"] for row in con.execute(
        "SELECT escenario, COUNT(*) n FROM vuelos WHERE alumno_id = ? GROUP BY escenario", (alumno_id,))}
    horas = r["t"] / 3600.0
    req = horas >= HORAS_MINIMAS and all(e in sup for e in ESCENARIOS)
    return dict(vuelos=r["n"], horas=round(horas, 3), accidentes=r["acc"], aterrizajes=r["att"], ultimo_vuelo=r["ultimo"],
                escenarios={e: dict(superado=e in sup, intentos=intentos.get(e, 0)) for e in ESCENARIOS},
                escenarios_superados=sum(e in sup for e in ESCENARIOS), horas_minimas=HORAS_MINIMAS,
                requisitos_cumplidos=req)


def alumno_dict(con, row, con_progreso=True):
    d = dict(id=row["id"], nombre=row["nombre"], creado=row["creado"], notas=row["notas"],
             archivado=bool(row["archivado"]), archivado_en=row["archivado_en"],
             habilitado=bool(row["habilitado"]), habilitado_en=row["habilitado_en"])
    if con_progreso: d["progreso"] = progreso(con, row["id"])
    return d


def vuelo_dict(row):
    d = dict(row); d["objetivos"] = json.loads(d["objetivos"] or "[]")
    d["escenario_nombre"] = NOMBRES_ESC.get(d["escenario"], d["escenario"])
    return d


# ======================= HTTP =======================
class Error(Exception):
    def __init__(self, codigo, mensaje):
        self.codigo, self.mensaje = codigo, mensaje


class Manejador(BaseHTTPRequestHandler):
    server_version = "AulaSimulador/1.0"

    def log_message(self, fmt, *args):
        if "/api/" in str(args[0] if args else ""):
            sys.stderr.write("%s %s\n" % (self.address_string(), fmt % args))

    # ---- respuestas ----
    def enviar(self, codigo, cuerpo, tipo="application/json; charset=utf-8", extra=None):
        datos = cuerpo if isinstance(cuerpo, bytes) else json.dumps(cuerpo, ensure_ascii=False).encode()
        self.send_response(codigo)
        self.send_header("Content-Type", tipo)
        self.send_header("Content-Length", str(len(datos)))
        self.send_header("Cache-Control", "no-store")
        for k, v in (extra or {}).items(): self.send_header(k, v)
        self.end_headers()
        self.wfile.write(datos)

    def cuerpo(self):
        n = int(self.headers.get("Content-Length") or 0)
        if n > 1_000_000: raise Error(413, "demasiado grande")
        try: return json.loads(self.rfile.read(n) or b"{}")
        except ValueError: raise Error(400, "JSON no valido")

    def profesor(self):
        tok = (self.headers.get("Authorization") or "").removeprefix("Bearer ").strip()
        cad = SESIONES.get(tok)
        if not cad or cad < time.time():
            SESIONES.pop(tok, None)
            raise Error(401, "Hace falta el PIN del profesor")
        SESIONES[tok] = time.time() + 8 * 3600

    def do_GET(self): self.despachar("GET")
    def do_POST(self): self.despachar("POST")
    def do_PUT(self): self.despachar("PUT")
    def do_DELETE(self): self.despachar("DELETE")

    def despachar(self, metodo):
        url = urlparse(self.path)
        try:
            if url.path.startswith("/api/"):
                con = conectar()
                try:
                    r = self.api(metodo, url.path[5:].strip("/").split("/"), parse_qs(url.query), con)
                finally:
                    con.close()
                if isinstance(r, tuple) and r[0] == "csv":
                    self.enviar(200, r[2].encode("utf-8-sig"), "text/csv; charset=utf-8",
                                {"Content-Disposition": 'attachment; filename="%s"' % r[1]})
                else:
                    self.enviar(201 if metodo == "POST" else 200, r)
            elif metodo == "GET":
                self.estatico(url.path)
            else:
                raise Error(405, "metodo no permitido")
        except Error as e:
            self.enviar(e.codigo, dict(error=e.mensaje))
        except sqlite3.IntegrityError as e:
            self.enviar(409, dict(error="conflicto: " + str(e)))
        except Exception as e:
            import traceback; traceback.print_exc()
            self.enviar(500, dict(error=str(e)))

    def estatico(self, ruta):
        if ruta in ("", "/"):
            self.send_response(302); self.send_header("Location", "/simulador.html"); self.end_headers(); return
        if ruta == "/aviones/indice.js":       # la carpeta de aviones se lee al momento: un avion nuevo aparece al copiarlo
            dav = os.path.join(DIR_SIM, "aviones")
            fs = sorted(f for f in os.listdir(dav) if f.endswith(".js") and f != "indice.js") if os.path.isdir(dav) else []
            self.enviar(200, ("Modelos.indice(%s);" % json.dumps(fs)).encode(), "text/javascript; charset=utf-8"); return
        f = os.path.normpath(os.path.join(DIR_SIM, ruta.lstrip("/")))
        if not f.startswith(DIR_SIM + os.sep) or not os.path.isfile(f):
            raise Error(404, "no existe")
        tipo = mimetypes.guess_type(f)[0] or "application/octet-stream"
        if tipo.startswith("text/") or tipo.endswith("javascript"): tipo += "; charset=utf-8"
        with open(f, "rb") as fh: self.enviar(200, fh.read(), tipo)

    # ---- API ----
    def api(self, m, p, q, con):
        if p == ["estado"] and m == "GET":
            return dict(ok=True, aula=socket.gethostname(), horas_minimas=HORAS_MINIMAS, escenarios=ESCENARIOS,
                        pin_configurado=bool(config(con, "pin")))

        # --- alumnos (sin PIN) ---
        if p == ["alumnos"] and m == "GET":
            filtro = normalizar(q.get("q", [""])[0])
            rows = con.execute("SELECT * FROM alumnos WHERE archivado = 0 ORDER BY nombre_norm").fetchall()
            return [alumno_dict(con, r) for r in rows if filtro in r["nombre_norm"]]
        if p == ["alumnos"] and m == "POST":
            return self.alta(con, self.cuerpo())
        if len(p) == 2 and p[0] == "alumnos" and m == "GET":
            r = con.execute("SELECT * FROM alumnos WHERE id = ?", (p[1],)).fetchone()
            if not r: raise Error(404, "alumno no encontrado")
            d = alumno_dict(con, r)
            d["vuelos"] = [vuelo_dict(v) for v in con.execute(
                "SELECT * FROM vuelos WHERE alumno_id = ? ORDER BY inicio DESC", (p[1],))]
            return d
        if len(p) == 2 and p[0] == "alumnos" and m == "DELETE":
            # archivar: desaparece de la lista pero conserva sus vuelos; el profesor puede restaurarlo
            with con:
                r = con.execute("SELECT nombre FROM alumnos WHERE id = ? AND archivado = 0", (p[1],)).fetchone()
                if not r: raise Error(404, "alumno no encontrado")
                con.execute("UPDATE alumnos SET archivado = 1, archivado_en = ? WHERE id = ?", (ahora(), p[1]))
                registrar(con, "archivar", "%s (%s) desde %s" % (r["nombre"], p[1], self.address_string()))
            CAMBIOS["desde_copia"] += 1
            return dict(ok=True)

        # --- vuelos (sin PIN; idempotente: el id lo pone el simulador) ---
        if p == ["vuelos"] and m == "POST":
            v = self.cuerpo()
            req = ["id", "alumno_id", "inicio", "avion", "escenario", "resultado"]
            if any(not v.get(k) for k in req): raise Error(400, "faltan campos: " + ", ".join(k for k in req if not v.get(k)))
            if v["resultado"] not in ("APTO", "NO APTO", "LIBRE"): raise Error(400, "resultado no valido")
            try: uuid.UUID(v["id"])
            except ValueError: raise Error(400, "id no valido")
            with con:
                if not con.execute("SELECT 1 FROM alumnos WHERE id = ?", (v["alumno_id"],)).fetchone():
                    raise Error(404, "alumno no encontrado")
                cur = con.execute("""INSERT OR IGNORE INTO vuelos (id, alumno_id, inicio, fin, equipo, avion, escenario,
                    tiempo_vuelo_s, accidentes, aterrizajes, objetivos, resultado, final, viento, recibido)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
                    (v["id"], v["alumno_id"], v["inicio"], v.get("fin"), v.get("equipo") or self.address_string(),
                     v["avion"], v["escenario"], max(0.0, float(v.get("tiempo_vuelo_s") or 0)),
                     int(v.get("accidentes") or 0), int(v.get("aterrizajes") or 0),
                     json.dumps(v.get("objetivos") or [], ensure_ascii=False), v["resultado"], v.get("final"),
                     json.dumps(v.get("viento") or {}, ensure_ascii=False), ahora()))
            CAMBIOS["desde_copia"] += 1
            return dict(ok=True, nuevo=cur.rowcount == 1, progreso=progreso(con, v["alumno_id"]))

        # --- profesor ---
        if p == ["profesor", "entrar"] and m == "POST":
            ip = self.client_address[0]
            n, hasta = FALLOS.get(ip, (0, 0))
            if hasta > time.time(): raise Error(429, "Demasiados intentos. Espera %d s." % (hasta - time.time()))
            if not config(con, "pin"): raise Error(503, "El PIN no está configurado: arranca el servidor en una consola")
            if not pin_correcto(con, str(self.cuerpo().get("pin", ""))):
                n += 1
                FALLOS[ip] = (0, time.time() + 120) if n >= 5 else (n, 0)
                raise Error(401, "PIN incorrecto")
            FALLOS.pop(ip, None)
            tok = secrets.token_urlsafe(24)
            SESIONES[tok] = time.time() + 8 * 3600
            return dict(token=tok)

        if p and p[0] == "profesor":
            self.profesor()
            return self.api_profesor(m, p[1:], q, con)
        raise Error(404, "ruta desconocida")

    def alta(self, con, d):
        nombre = re.sub(r"\s+", " ", str(d.get("nombre", ""))).strip()
        if not (2 <= len(nombre) <= 60): raise Error(400, "El nombre tiene que tener entre 2 y 60 caracteres")
        norm = normalizar(nombre)
        with con:
            ya = con.execute("SELECT * FROM alumnos WHERE nombre_norm = ? AND archivado = 0", (norm,)).fetchone()
            if ya: raise Error(409, "Ya hay un alumno con ese nombre")
            aid = str(uuid.uuid4())
            con.execute("INSERT INTO alumnos (id, nombre, nombre_norm, creado) VALUES (?, ?, ?, ?)", (aid, nombre, norm, ahora()))
            registrar(con, "alta", "%s (%s) desde %s" % (nombre, aid, self.address_string()))
        CAMBIOS["desde_copia"] += 1
        return alumno_dict(con, con.execute("SELECT * FROM alumnos WHERE id = ?", (aid,)).fetchone())

    def api_profesor(self, m, p, q, con):
        if p == ["salir"] and m == "POST":
            SESIONES.pop((self.headers.get("Authorization") or "").removeprefix("Bearer ").strip(), None)
            return dict(ok=True)
        if p == ["alumnos"] and m == "GET":
            rows = con.execute("SELECT * FROM alumnos ORDER BY archivado, nombre_norm").fetchall()
            return [alumno_dict(con, r) for r in rows]
        if p == ["alumnos"] and m == "POST":
            return self.alta(con, self.cuerpo())
        if len(p) >= 2 and p[0] == "alumnos":
            aid = p[1]
            r = con.execute("SELECT * FROM alumnos WHERE id = ?", (aid,)).fetchone()
            if not r: raise Error(404, "alumno no encontrado")
            if len(p) == 2 and m == "PUT":
                d = self.cuerpo()
                nombre = re.sub(r"\s+", " ", str(d.get("nombre", r["nombre"]))).strip()
                if not (2 <= len(nombre) <= 60): raise Error(400, "El nombre tiene que tener entre 2 y 60 caracteres")
                with con:
                    if not r["archivado"] and con.execute("SELECT 1 FROM alumnos WHERE nombre_norm = ? AND archivado = 0 AND id <> ?",
                                                          (normalizar(nombre), aid)).fetchone():
                        raise Error(409, "Ya hay un alumno con ese nombre")
                    con.execute("UPDATE alumnos SET nombre = ?, nombre_norm = ?, notas = ? WHERE id = ?",
                                (nombre, normalizar(nombre), str(d.get("notas", r["notas"]))[:2000], aid))
                    registrar(con, "editar", "%s -> %s (%s)" % (r["nombre"], nombre, aid))
                CAMBIOS["desde_copia"] += 1
                return alumno_dict(con, con.execute("SELECT * FROM alumnos WHERE id = ?", (aid,)).fetchone())
            if p[2:] == ["archivar"] and m == "POST":
                with con:
                    con.execute("UPDATE alumnos SET archivado = 1, archivado_en = ? WHERE id = ?", (ahora(), aid))
                    registrar(con, "archivar", "%s (%s) por el profesor" % (r["nombre"], aid))
                return dict(ok=True)
            if p[2:] == ["restaurar"] and m == "POST":
                with con:
                    if con.execute("SELECT 1 FROM alumnos WHERE nombre_norm = ? AND archivado = 0", (r["nombre_norm"],)).fetchone():
                        raise Error(409, "Ya hay otro alumno activo con ese nombre: renombra uno de los dos")
                    con.execute("UPDATE alumnos SET archivado = 0, archivado_en = NULL WHERE id = ?", (aid,))
                    registrar(con, "restaurar", "%s (%s)" % (r["nombre"], aid))
                return dict(ok=True)
            if len(p) == 2 and m == "DELETE":
                if not r["archivado"]: raise Error(409, "Archiva antes al alumno; el borrado definitivo es para archivados")
                copia = hacer_copia("antes_de_borrar")
                with con:
                    n = con.execute("SELECT COUNT(*) FROM vuelos WHERE alumno_id = ?", (aid,)).fetchone()[0]
                    con.execute("DELETE FROM alumnos WHERE id = ?", (aid,))
                    registrar(con, "borrar", "%s (%s) con %d vuelos; copia previa %s" % (r["nombre"], aid, n, copia))
                return dict(ok=True, copia=copia)
            if p[2:] == ["habilitar"] and m == "POST":
                autorizar = bool(self.cuerpo().get("autorizar"))
                if autorizar and not progreso(con, aid)["requisitos_cumplidos"]:
                    raise Error(409, "Aún no cumple los requisitos: %.0f h y los 4 escenarios" % HORAS_MINIMAS)
                with con:
                    con.execute("UPDATE alumnos SET habilitado = ?, habilitado_en = ? WHERE id = ?",
                                (int(autorizar), ahora() if autorizar else None, aid))
                    registrar(con, "habilitar" if autorizar else "retirar habilitacion", "%s (%s)" % (r["nombre"], aid))
                CAMBIOS["desde_copia"] += 1
                return alumno_dict(con, con.execute("SELECT * FROM alumnos WHERE id = ?", (aid,)).fetchone())
        if p == ["vuelos"] and m == "GET":
            aid = q.get("alumno", [None])[0]
            sql = "SELECT v.*, a.nombre AS alumno FROM vuelos v JOIN alumnos a ON a.id = v.alumno_id"
            rows = con.execute(sql + (" WHERE v.alumno_id = ?" if aid else "") + " ORDER BY v.inicio DESC", (aid,) if aid else ())
            return [vuelo_dict(v) for v in rows]
        if p == ["exportar"] and m == "GET":
            return self.exportar(con, q.get("tipo", ["vuelos"])[0])
        if p == ["copias"] and m == "GET":
            fs = sorted((f for f in os.listdir(DIR_COPIAS) if f.endswith(".db")), reverse=True)
            return [dict(nombre=f, kb=round(os.path.getsize(os.path.join(DIR_COPIAS, f)) / 1024, 1)) for f in fs]
        if p == ["copias"] and m == "POST":
            return dict(ok=True, copia=hacer_copia("manual"))
        if p == ["registro"] and m == "GET":
            return [dict(r) for r in con.execute("SELECT * FROM registro ORDER BY id DESC LIMIT 300")]
        if p == ["pin"] and m == "POST":
            d = self.cuerpo()
            if not pin_correcto(con, str(d.get("actual", ""))): raise Error(401, "El PIN actual no es correcto")
            nuevo = str(d.get("nuevo", ""))
            if not re.fullmatch(r"\d{4,12}", nuevo): raise Error(400, "El PIN nuevo tiene que tener de 4 a 12 cifras")
            with con:
                con.execute("INSERT OR REPLACE INTO config (clave, valor) VALUES ('pin', ?)", (hash_pin(nuevo),))
                registrar(con, "cambiar pin", "desde " + self.address_string())
            return dict(ok=True)
        raise Error(404, "ruta desconocida")

    @staticmethod
    def hora_local(iso):
        try: return dt.datetime.fromisoformat(iso.replace("Z", "+00:00")).astimezone().strftime("%Y-%m-%d %H:%M:%S")
        except (ValueError, AttributeError): return iso or ""

    @staticmethod
    def viento_txt(js):
        try:
            v = json.loads(js or "{}")
            return "%g m/s del %s%s" % (v["vel"], {0: "norte", 45: "nordeste", 90: "este", 135: "sudeste", 180: "sur", 225: "sudoeste",
                                                   270: "oeste", 315: "noroeste"}.get(int(v["desde"]), "%s°" % v["desde"]),
                                       " con rachas" if v.get("rachas") else "")
        except (ValueError, KeyError, TypeError): return js or ""

    def exportar(self, con, tipo):
        out = io.StringIO()
        w = csv.writer(out, delimiter=";")
        if tipo == "alumnos":
            w.writerow(["alumno", "id", "alta", "archivado", "vuelos", "horas", "accidentes", "aterrizajes"]
                       + [NOMBRES_ESC[e] for e in ESCENARIOS] + ["requisitos cumplidos", "habilitado avión real", "habilitado el", "notas"])
            for r in con.execute("SELECT * FROM alumnos ORDER BY nombre_norm"):
                g = progreso(con, r["id"])
                w.writerow([r["nombre"], r["id"], r["creado"], "sí" if r["archivado"] else "no", g["vuelos"],
                            ("%.2f" % g["horas"]).replace(".", ","), g["accidentes"], g["aterrizajes"]]
                           + ["superado" if g["escenarios"][e]["superado"] else "pendiente" for e in ESCENARIOS]
                           + ["sí" if g["requisitos_cumplidos"] else "no", "sí" if r["habilitado"] else "no",
                              r["habilitado_en"] or "", r["notas"]])
            nombre = "alumnos_%s.csv" % dt.date.today().isoformat()
        else:
            w.writerow(["alumno", "fecha y hora", "fin", "equipo", "avión", "escenario", "tiempo de vuelo (min)",
                        "accidentes", "aterrizajes", "objetivos completados", "objetivos", "resultado", "final", "viento", "id del vuelo"])
            for v in con.execute("SELECT v.*, a.nombre AS alumno FROM vuelos v JOIN alumnos a ON a.id = v.alumno_id ORDER BY v.inicio"):
                obj = json.loads(v["objetivos"] or "[]")
                w.writerow([v["alumno"], self.hora_local(v["inicio"]), self.hora_local(v["fin"]), v["equipo"] or "", v["avion"], NOMBRES_ESC.get(v["escenario"], v["escenario"]),
                            ("%.1f" % (v["tiempo_vuelo_s"] / 60)).replace(".", ","), v["accidentes"], v["aterrizajes"],
                            "%d/%d" % (sum(1 for o in obj if o.get("ok")), len(obj)),
                            " | ".join(("✔ " if o.get("ok") else "✘ ") + o.get("texto", "") for o in obj),
                            v["resultado"], v["final"] or "", self.viento_txt(v["viento"]), v["id"]])
            nombre = "vuelos_%s.csv" % dt.date.today().isoformat()
        return ("csv", nombre, out.getvalue())


def ips_locales():
    ips = set()
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); s.connect(("10.255.255.255", 1)); ips.add(s.getsockname()[0]); s.close()
    except OSError: pass
    try: ips.update(i[4][0] for i in socket.getaddrinfo(socket.gethostname(), None, socket.AF_INET))
    except OSError: pass
    return sorted(i for i in ips if not i.startswith("127."))


def main():
    ap = argparse.ArgumentParser(description="Servidor del aula del simulador")
    ap.add_argument("--puerto", type=int, default=8080)
    ap.add_argument("--cambiar-pin", action="store_true")
    ap.add_argument("--datos", help="carpeta de la base de datos y las copias (por defecto aula/datos)")
    a = ap.parse_args()
    if a.datos: usar_datos(a.datos)
    crear_bd()
    con = conectar()
    if a.cambiar_pin or not config(con, "pin"):
        if not sys.stdin.isatty():
            print("Falta el PIN del profesor: arranca el servidor en una consola para elegirlo."); sys.exit(1)
        print("Configura el PIN del profesor (protege el panel del profesor y la autorización del avión real).")
        with con:
            con.execute("INSERT OR REPLACE INTO config (clave, valor) VALUES ('pin', ?)", (hash_pin(pedir_pin_consola()),))
            registrar(con, "cambiar pin", "consola del servidor")
        print("PIN guardado.")
        if a.cambiar_pin: return
    con.close()
    print("Copia de seguridad al arrancar:", hacer_copia("arranque"))
    threading.Thread(target=copias_periodicas, daemon=True).start()
    srv = ThreadingHTTPServer(("0.0.0.0", a.puerto), Manejador)
    print("\nServidor del aula en marcha. Abrid en el navegador de cada ordenador:")
    print("   en este ordenador:  http://localhost:%d" % a.puerto)
    for ip in ips_locales(): print("   en el resto:        http://%s:%d" % (ip, a.puerto))
    print("Panel del profesor: botón 'Profesor' en la pantalla de alumnos.  Ctrl+C para parar.\n")
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        if CAMBIOS["desde_copia"]: print("Copia al cerrar:", hacer_copia("cierre"))


if __name__ == "__main__":
    main()
