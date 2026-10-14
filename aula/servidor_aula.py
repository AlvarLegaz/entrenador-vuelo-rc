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
import argparse, csv, datetime as dt, getpass, hashlib, hmac, io, json, math, mimetypes, os, re, secrets, socket
import sqlite3, sys, threading, time, unicodedata, uuid
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs

AQUI = os.path.dirname(os.path.abspath(__file__))
DIR_SIM = os.path.normpath(os.path.join(AQUI, "..", "simulador"))
DIR_DATOS = os.path.join(AQUI, "datos")
DB = os.path.join(DIR_DATOS, "aula.db")
DIR_COPIAS = os.path.join(DIR_DATOS, "copias")
MAX_COPIAS = 60

# el certificado de pilotaje que concede el profesor: lo define el mismo en su panel (nombre, horas de vuelo y pruebas
# a superar, APTO en cada una); estos son los valores de partida
HORAS_MINIMAS = 10.0
ESCENARIOS = ["primer_vuelo", "orientacion", "viento_cruzado", "emergencia"]
CERT_DEFECTO = dict(nombre="Certificado de pilotaje", horas=HORAS_MINIMAS, pruebas=ESCENARIOS)
NOMBRES_ESC = {"primer_vuelo": "Primer vuelo", "orientacion": "Orientación", "viento_cruzado": "Viento cruzado",
               "emergencia": "Emergencia", "libre": "Vuelo libre",
               # zona 2 (precision, detras del piloto): practica, no cuentan para la autorizacion
               "puerta": "Puerta (zona 2)", "pasada_baja": "Pasada baja (zona 2)", "diana": "Diana (zona 2)",
               "recorrido": "Recorrido de precisión (zona 2)", "aterrizaje": "Aterrizaje guiado",
               # dron FPV (pista FPV detras del piloto): practica, no cuentan para la autorizacion del avion
               "fpv_estacionario": "FPV: despegue y estacionario", "fpv_caja": "FPV: la caja", "fpv_slalom": "FPV: slalom y ocho",
               "fpv_circuito": "FPV: circuito de puertas", "fpv_acro": "FPV: paso a ACRO", "fpv_tecnica": "FPV: técnica",
               # operaciones (trabajos de operador de dron con el dron comercial en el mapa real)
               "op_inspeccion": "Operación: inspección de edificios", "op_fotogrametria": "Operación: fotogrametría",
               "op_busqueda": "Operación: búsqueda y rescate", "op_agricultura": "Operación: agricultura",
               "op_paneles": "Operación: paneles fotovoltaicos", "op_video": "Operación: grabación de vídeo", "libre_cartagena": "Vuelo libre (Cartagena)"}

SESIONES = {}            # token -> caduca (epoch)
# ---- multijugador: salas en memoria (no van a la base de datos). Cada simulador manda su estado unas 10 veces por
# segundo y recibe el de los demas de su sala; el panel del profesor las ve en directo ----
SALAS = {}               # codigo -> dict(codigo, nombre, escenario, lanz, viento, creada, ultimo, jugadores={id: estado})
CERROJO_SALAS = threading.Lock()
# ordenes del profesor a una sala (panel del profesor, con PIN): viento, NOTAM, aterrizaje, zonas de exclusion y el
# desaparecido de la busqueda. Cada orden lleva su numero (n) y los simuladores aplican las que no han visto.
ORDENES_SALA = ("viento", "notam", "quitar_notam", "aterrizar", "exclusion", "quitar_exclusion", "senderista")
JUGADOR_CADUCA = 6       # s sin noticias: el jugador sale de la sala
SALA_CADUCA = 3 * 3600   # s sin nadie: la sala se cierra sola
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
    if "clave" not in [c[1] for c in con.execute("PRAGMA table_info(alumnos)")]:      # clave de acceso de cada alumno (2026-10-14)
        con.execute("ALTER TABLE alumnos ADD COLUMN clave TEXT")
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


# ======================= clave de cada alumno =======================
# Los alumnos entran en su perfil online con su clave (de 4 a 20 caracteres, guardada como el PIN: sal + PBKDF2). Al
# entrar reciben un pase firmado (HMAC con el secreto del aula sobre su id y su clave): el simulador lo guarda y lo manda
# con cada vuelo en la cabecera X-Alumno. Sirve hasta que cambie su clave; no caduca al reiniciar el servidor.
def secreto(con):
    s = config(con, "secreto")
    if not s:
        s = secrets.token_hex(32)
        with con: con.execute("INSERT OR REPLACE INTO config (clave, valor) VALUES ('secreto', ?)", (s,))
    return s


def pase_alumno(con, row):
    return row["id"] + "." + hmac.new(bytes.fromhex(secreto(con)), (row["id"] + "|" + (row["clave"] or "")).encode(), hashlib.sha256).hexdigest()


def clave_valida(c):
    c = str(c or "")
    if not 4 <= len(c) <= 20: raise Error(400, "La clave tiene que tener de 4 a 20 caracteres")
    return c


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
def certificado(con):
    """El certificado que ha definido el profesor (config "certificado") o el de partida."""
    try: c = json.loads(config(con, "certificado") or "null")
    except ValueError: c = None
    if not isinstance(c, dict): return dict(CERT_DEFECTO)
    return dict(nombre=str(c.get("nombre") or CERT_DEFECTO["nombre"])[:80], horas=max(0.0, float(c.get("horas", HORAS_MINIMAS))),
                pruebas=[str(x)[:40] for x in c.get("pruebas", []) if re.fullmatch(r"[a-z0-9_]{1,40}", str(x))])


def progreso(con, alumno_id, C=None):
    C = C or certificado(con); PR, HM = C["pruebas"], C["horas"]
    r = con.execute("""SELECT COUNT(*) n, COALESCE(SUM(tiempo_vuelo_s), 0) t, COALESCE(SUM(accidentes), 0) acc,
                       COALESCE(SUM(aterrizajes), 0) att, MAX(inicio) ultimo FROM vuelos WHERE alumno_id = ?""",
                    (alumno_id,)).fetchone()
    sup = {row["escenario"] for row in con.execute(
        "SELECT DISTINCT escenario FROM vuelos WHERE alumno_id = ? AND resultado = 'APTO'", (alumno_id,))}
    intentos = {row["escenario"]: row["n"] for row in con.execute(
        "SELECT escenario, COUNT(*) n FROM vuelos WHERE alumno_id = ? GROUP BY escenario", (alumno_id,))}
    horas = r["t"] / 3600.0
    req = horas >= HM and all(e in sup for e in PR)
    return dict(vuelos=r["n"], horas=round(horas, 3), accidentes=r["acc"], aterrizajes=r["att"], ultimo_vuelo=r["ultimo"],
                escenarios={e: dict(superado=e in sup, intentos=intentos.get(e, 0)) for e in PR},
                escenarios_superados=sum(e in sup for e in PR), escenarios_total=len(PR), horas_minimas=HM,
                certificado=C["nombre"], requisitos_cumplidos=req)


def alumno_dict(con, row, con_progreso=True):
    d = dict(id=row["id"], nombre=row["nombre"], creado=row["creado"], notas=row["notas"],
             archivado=bool(row["archivado"]), archivado_en=row["archivado_en"],
             habilitado=bool(row["habilitado"]), habilitado_en=row["habilitado_en"], tiene_clave=bool(row["clave"]))
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
        self.cabeceras_cors()
        for k, v in (extra or {}).items(): self.send_header(k, v)
        self.end_headers()
        self.wfile.write(datos)

    def cuerpo(self):
        n = int(self.headers.get("Content-Length") or 0)
        if n > 1_000_000: raise Error(413, "demasiado grande")
        try: return json.loads(self.rfile.read(n) or b"{}")
        except ValueError: raise Error(400, "JSON no valido")

    def es_profesor(self):
        try: self.profesor(); return True
        except Error: return False

    def profesor(self):
        tok = (self.headers.get("Authorization") or "").removeprefix("Bearer ").strip()
        cad = SESIONES.get(tok)
        if not cad or cad < time.time():
            SESIONES.pop(tok, None)
            raise Error(401, "Hace falta el PIN del profesor")
        SESIONES[tok] = time.time() + 8 * 3600

    def cabeceras_cors(self):
        """El simulador web se abre en cada ordenador (con doble clic, file://) y habla con el aula por su direccion: hay
        que dejarle. Lo que protege son el PIN del profesor y la clave de cada alumno, no el origen."""
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type, Authorization, X-Alumno")
        self.send_header("Access-Control-Allow-Private-Network", "true")
        self.send_header("Access-Control-Max-Age", "600")

    def do_OPTIONS(self):
        self.send_response(204); self.cabeceras_cors(); self.send_header("Content-Length", "0"); self.end_headers()

    def do_GET(self): self.despachar("GET")
    def do_POST(self): self.despachar("POST")
    def do_PUT(self): self.despachar("PUT")
    def do_DELETE(self): self.despachar("DELETE")

    def despachar(self, metodo):
        url = urlparse(self.path)
        try:
            if url.path.startswith("/api/salas"):       # multijugador: en memoria, sin abrir la base de datos
                self.enviar(201 if metodo == "POST" else 200, self.api_salas(metodo, url.path[5:].strip("/").split("/")))
            elif url.path.startswith("/api/"):
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
        if ruta in ("", "/", "/simulador.html"):         # el aula solo administra: el simulador lo tiene cada alumno en su ordenador
            self.send_response(302); self.send_header("Location", "/profesor.html"); self.end_headers(); return
        if not (ruta == "/profesor.html" or ruta == "/escenarios.js" or ruta.startswith(("/mundos/", "/zonas/", "/aviones/"))):
            raise Error(404, "El servidor del aula solo tiene el panel del profesor: el simulador se abre en cada ordenador")
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

    # ---- multijugador ----
    @staticmethod
    def _sala_publica(sala, con_jugadores=True, profesor=False):
        d = {k: sala.get(k) for k in ("codigo", "nombre", "escenario", "lanz", "viento", "ajustes", "creada")}
        d["con_clave"] = bool(sala.get("clave"))
        if profesor: d["clave"] = sala.get("clave"); d["expulsados"] = sorted(sala.get("expulsados_nombres", []))
        d["jugadores"] = list(sala["jugadores"].values()) if con_jugadores else len(sala["jugadores"])
        if con_jugadores: d["recorridos"] = {k: r["nombre"] for k, r in sala.get("rutas", {}).items()}   # quien tiene recorrido (aunque ya no este)
        if con_jugadores: d["ordenes"] = sala.get("ordenes", [])
        return d

    @staticmethod
    def _expulsado(sala, jid, e):
        """El piloto esta expulsado de la sala: por su id, su perfil o su nombre (para que no vuelva con otra pestana)."""
        X = sala.get("expulsados") or set()
        return jid in X or (e.get("alumno") and "alumno:" + str(e["alumno"]) in X) or (e.get("nombre") and "nombre:" + normalizar(str(e["nombre"])) in X)

    @staticmethod
    def _apuntar_ruta(sala, jid, e, t):
        """Recorrido de cada piloto para el panel del profesor: un punto [N, E, altura, t] cada 3 m (o cada 10 s quieto), aunque
        luego salga de la sala; un salto de mas de 150 m (empezar de nuevo) corta la linea con un null. Hasta 20.000 puntos."""
        try: n, e_, h = float(e["p"][0]), float(e["p"][1]), max(0.0, float(e.get("agl") or 0))
        except (KeyError, TypeError, ValueError, IndexError): return
        r = sala.setdefault("rutas", {}).setdefault(jid, dict(nombre=e["nombre"], avion=e.get("avion"), puntos=[]))
        r["nombre"] = e["nombre"]; P = r["puntos"]; u = next((x for x in reversed(P) if x), None)
        if u:
            d = math.hypot(n - u[0], e_ - u[1])
            if d < 3 and abs(h - u[2]) < 3 and t - u[3] < 10: return
            if d > 150: P.append(None)
        if len(P) < 20000: P.append([round(n, 1), round(e_, 1), round(h, 1), round(t, 1)])

    def api_salas(self, m, p):
        t = time.time()
        with CERROJO_SALAS:
            for cod in list(SALAS):                      # limpieza: jugadores callados y salas vacias hace mucho
                sala = SALAS[cod]
                for jid in [j for j, e in sala["jugadores"].items() if t - e["_t"] > JUGADOR_CADUCA]: del sala["jugadores"][jid]
                if not sala["jugadores"] and t - sala["ultimo"] > SALA_CADUCA: del SALAS[cod]
            if p == ["salas"] and m == "GET":
                prof = self.es_profesor()
                return sorted((self._sala_publica(s, profesor=prof) for s in SALAS.values()), key=lambda d: d["creada"])
            if p == ["salas"] and m == "POST":                 # solo el profesor crea salas
                self.profesor(); b = self.cuerpo()
                if not b.get("escenario"): raise Error(400, "falta el escenario")
                cod = next(c for c in (str(secrets.randbelow(9000) + 1000) for _ in range(100)) if c not in SALAS)
                SALAS[cod] = dict(codigo=cod, nombre=str(b.get("nombre") or "Sala " + cod)[:60], escenario=str(b["escenario"]),
                                  lanz=b.get("lanz"), viento=b.get("viento"), creada=ahora(), ultimo=t, jugadores={}, rutas={}, ordenes=[],
                                  ajustes={k: float(v) for k, v in (b.get("ajustes") or {}).items()
                                           if k in ("cubiertas", "fachadas", "defectos", "manchas", "minutos", "cobertura") and isinstance(v, (int, float))} or None,
                                  clave=str(b.get("clave") or "").strip()[:20] or None, admitidos=set(), expulsados=set(), expulsados_nombres=set())
                return self._sala_publica(SALAS[cod], profesor=True)
            if len(p) >= 2 and p[0] == "salas":
                sala = SALAS.get(p[1])
                if not sala: raise Error(404, "La sala ya no existe")
                if len(p) == 2 and m == "GET": return self._sala_publica(sala, profesor=self.es_profesor())
                if len(p) == 3 and p[2] == "entrar" and m == "POST":      # entrar en la sala: con su clave, si la tiene
                    b = self.cuerpo(); jid = str(b.get("id") or "")
                    if not jid: raise Error(400, "falta el id")
                    if self._expulsado(sala, jid, b): raise Error(403, "El profesor te ha expulsado de esta sala")
                    if sala.get("clave") and not hmac.compare_digest(str(b.get("clave") or ""), sala["clave"]): raise Error(403, "Clave de la sala incorrecta")
                    sala["admitidos"].add(jid); return self._sala_publica(sala, False)
                if len(p) == 3 and p[2] == "expulsar" and m == "POST":    # el profesor echa a un piloto (y no puede volver)
                    self.profesor(); jid = str(self.cuerpo().get("id") or "")
                    e = sala["jugadores"].pop(jid, None) or {}
                    sala["expulsados"].add(jid); sala["admitidos"].discard(jid)
                    if e.get("alumno"): sala["expulsados"].add("alumno:" + str(e["alumno"]))
                    if e.get("nombre"): sala["expulsados"].add("nombre:" + normalizar(e["nombre"])); sala["expulsados_nombres"].add(e["nombre"])
                    return dict(ok=True)
                if len(p) == 3 and p[2] == "readmitir" and m == "POST":   # el profesor deja volver a todos los expulsados
                    self.profesor(); sala["expulsados"].clear(); sala["expulsados_nombres"].clear(); return dict(ok=True)
                if len(p) == 2 and m == "DELETE":
                    self.profesor(); del SALAS[p[1]]; return dict(ok=True)
                if len(p) == 3 and p[2] == "estado" and m == "POST":
                    e = self.cuerpo(); jid = str(e.get("id") or ""); g = e.get("golpes")
                    if not jid: raise Error(400, "falta el id")
                    if self._expulsado(sala, jid, e): sala["jugadores"].pop(jid, None); raise Error(403, "El profesor te ha expulsado de esta sala")
                    if sala.get("clave") and jid not in sala["admitidos"]: raise Error(403, "Esta sala tiene clave: entra desde la lista de salas")
                    e = {k: e[k] for k in ("id", "nombre", "alumno", "avion", "p", "q", "vn", "estado", "gas", "agl", "objs", "ahora", "tvuelo", "final", "gimbal", "bip") if k in e}
                    if isinstance(g, dict):                      # bipode: impactos que lleva dados a cada piloto (id -> cuantos)
                        e["golpes"] = {str(k)[:40]: int(v) for k, v in list(g.items())[:30] if isinstance(v, (int, float))}
                    e["nombre"] = str(e.get("nombre") or "Piloto")[:40]; e["_t"] = t; e["_ip"] = self.client_address[0]
                    sala["jugadores"][jid] = e; sala["ultimo"] = t
                    self._apuntar_ruta(sala, jid, e, t)
                    return dict(otros=[x for k, x in sala["jugadores"].items() if k != jid], sala=self._sala_publica(sala, False),
                                ordenes=[dict(o, edad=round(t - o["t"])) for o in sala.get("ordenes", [])])
                if len(p) == 3 and p[2] == "orden" and m == "POST":       # el profesor manda una orden a la sala
                    self.profesor(); b = self.cuerpo(); tipo = str(b.get("tipo") or "")
                    if tipo not in ORDENES_SALA: raise Error(400, "orden desconocida")
                    O = sala.setdefault("ordenes", [])
                    if len(O) >= 300: raise Error(400, "demasiadas órdenes en esta sala")
                    o = dict(n=len(O) + 1, tipo=tipo, t=t, para=str(b.get("para") or "*")[:40])
                    try:
                        for k in ("vel", "desde", "N", "E", "r", "id"):
                            if b.get(k) is not None: o[k] = round(float(b[k]), 1)
                    except (TypeError, ValueError): raise Error(400, "datos de la orden no válidos")
                    if "rachas" in b: o["rachas"] = bool(b["rachas"])
                    if b.get("texto"): o["texto"] = str(b["texto"])[:200]
                    O.append(o); return o
                if len(p) == 3 and p[2] == "rutas" and m == "GET":       # el panel del profesor: lo recorrido por cada uno
                    return sala.get("rutas", {})
                if len(p) == 3 and p[2] == "salir" and m == "POST":
                    sala["jugadores"].pop(str(self.cuerpo().get("id") or ""), None); return dict(ok=True)
        raise Error(404, "ruta no encontrada")

    # ---- API ----
    def api(self, m, p, q, con):
        if p == ["estado"] and m == "GET":
            C = certificado(con)
            return dict(ok=True, aula=socket.gethostname(), horas_minimas=C["horas"], escenarios=C["pruebas"], certificado=C,
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
        if p == ["entrar"] and m == "POST":     # pantalla de inicio del simulador: usuario y contrasena -> { alumno, pase }
            d = self.cuerpo(); nombre = re.sub(r"\s+", " ", str(d.get("usuario", ""))).strip()
            if not nombre: raise Error(400, "Escribe tu usuario")
            r = con.execute("SELECT * FROM alumnos WHERE nombre_norm = ? AND archivado = 0", (normalizar(nombre),)).fetchone()
            if not r:
                if not d.get("crear"): raise Error(404, "No existe el usuario «%s» en este aula" % nombre)
                al = self.alta(con, dict(nombre=nombre, clave=d.get("clave")))      # alta del alumno con su contrasena
                return dict(alumno={k: v for k, v in al.items() if k != "pase"}, pase=al["pase"])
            clave = clave_valida(d.get("clave"))
            if not r["clave"]:                  # el profesor lo dio de alta sin contrasena: la primera que escribe se queda
                with con:
                    con.execute("UPDATE alumnos SET clave = ? WHERE id = ?", (hash_pin(clave), r["id"]))
                    registrar(con, "clave", "%s (%s) desde %s" % (r["nombre"], r["id"], self.address_string()))
            else:
                ip = (self.client_address[0], r["id"]); n, hasta = FALLOS.get(ip, (0, 0))
                if hasta > time.time(): raise Error(429, "Demasiados intentos. Espera %d s." % (hasta - time.time()))
                sal = r["clave"].split("$", 1)[0]
                if not hmac.compare_digest(hash_pin(clave, sal), r["clave"]):
                    n += 1; FALLOS[ip] = (0, time.time() + 60) if n >= 5 else (n, 0)
                    raise Error(403, "Contraseña incorrecta")
                FALLOS.pop(ip, None)
            r = con.execute("SELECT * FROM alumnos WHERE id = ?", (r["id"],)).fetchone()
            return dict(alumno=alumno_dict(con, r), pase=pase_alumno(con, r))
        if len(p) == 3 and p[0] == "alumnos" and p[2] == "entrar" and m == "POST":     # el alumno entra en su perfil
            r = con.execute("SELECT * FROM alumnos WHERE id = ? AND archivado = 0", (p[1],)).fetchone()
            if not r: raise Error(404, "alumno no encontrado")
            if not r["clave"]: return dict(sin_clave=True)
            ip = (self.client_address[0], p[1]); n, hasta = FALLOS.get(ip, (0, 0))
            if hasta > time.time(): raise Error(429, "Demasiados intentos. Espera %d s." % (hasta - time.time()))
            sal = r["clave"].split("$", 1)[0]
            if not hmac.compare_digest(hash_pin(str(self.cuerpo().get("clave", "")), sal), r["clave"]):
                n += 1; FALLOS[ip] = (0, time.time() + 60) if n >= 5 else (n, 0)
                raise Error(403, "Clave incorrecta")
            FALLOS.pop(ip, None)
            return dict(pase=pase_alumno(con, r))
        if len(p) == 3 and p[0] == "alumnos" and p[2] == "clave" and m == "POST":      # crearla (la primera vez) o cambiarla
            r = con.execute("SELECT * FROM alumnos WHERE id = ? AND archivado = 0", (p[1],)).fetchone()
            if not r: raise Error(404, "alumno no encontrado")
            if r["clave"] and not self.pase_ok(con, r): raise Error(403, "Para cambiar la clave hay que entrar con la de ahora")
            nueva = clave_valida(self.cuerpo().get("nueva"))
            with con:
                con.execute("UPDATE alumnos SET clave = ? WHERE id = ?", (hash_pin(nueva), p[1]))
                registrar(con, "clave", "%s (%s) desde %s" % (r["nombre"], p[1], self.address_string()))
            return dict(pase=pase_alumno(con, con.execute("SELECT * FROM alumnos WHERE id = ?", (p[1],)).fetchone()))
        if len(p) == 2 and p[0] == "alumnos" and m == "DELETE":
            # archivar: desaparece de la lista pero conserva sus vuelos; el profesor puede restaurarlo
            with con:
                r = con.execute("SELECT * FROM alumnos WHERE id = ? AND archivado = 0", (p[1],)).fetchone()
                if not r: raise Error(404, "alumno no encontrado")
                if not self.pase_ok(con, r): raise Error(403, "Para quitarte de la lista entra con tu clave")
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
                ra = con.execute("SELECT * FROM alumnos WHERE id = ?", (v["alumno_id"],)).fetchone()
                if not ra: raise Error(404, "alumno no encontrado")
                if not self.pase_ok(con, ra): raise Error(401, "Hace falta la clave del alumno")
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
        if p == ["profesor", "certificado"] and m == "POST":     # el profesor define el certificado
            self.profesor(); b = self.cuerpo()
            try: horas = float(b.get("horas"))
            except (TypeError, ValueError): raise Error(400, "Las horas tienen que ser un número")
            pruebas = [str(x) for x in (b.get("pruebas") or [])]
            if not 0 <= horas <= 500: raise Error(400, "Las horas tienen que estar entre 0 y 500")
            if any(not re.fullmatch(r"[a-z0-9_]{1,40}", x) for x in pruebas): raise Error(400, "Prueba no válida")
            C = dict(nombre=str(b.get("nombre") or "").strip()[:80] or CERT_DEFECTO["nombre"], horas=horas, pruebas=list(dict.fromkeys(pruebas)))
            with con:
                con.execute("INSERT OR REPLACE INTO config (clave, valor) VALUES ('certificado', ?)", (json.dumps(C, ensure_ascii=False),))
                registrar(con, "certificado", "%s: %g h, %s" % (C["nombre"], horas, ", ".join(C["pruebas"]) or "sin pruebas"))
            CAMBIOS["desde_copia"] += 1
            return C
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

    def pase_ok(self, con, row):
        """El pase del alumno (cabecera X-Alumno) es el suyo; si aun no tiene clave, no hace falta."""
        if not row["clave"]: return True
        return hmac.compare_digest(self.headers.get("X-Alumno") or "", pase_alumno(con, row))

    def alta(self, con, d, profesor=False):
        nombre = re.sub(r"\s+", " ", str(d.get("nombre", ""))).strip()
        clave = clave_valida(d.get("clave")) if (d.get("clave") or not profesor) else None
        if not (2 <= len(nombre) <= 60): raise Error(400, "El nombre tiene que tener entre 2 y 60 caracteres")
        norm = normalizar(nombre)
        with con:
            ya = con.execute("SELECT * FROM alumnos WHERE nombre_norm = ? AND archivado = 0", (norm,)).fetchone()
            if ya: raise Error(409, "Ya hay un alumno con ese nombre")
            aid = str(uuid.uuid4())
            con.execute("INSERT INTO alumnos (id, nombre, nombre_norm, creado, clave) VALUES (?, ?, ?, ?, ?)",
                        (aid, nombre, norm, ahora(), hash_pin(clave) if clave else None))
            registrar(con, "alta", "%s (%s) desde %s" % (nombre, aid, self.address_string()))
        CAMBIOS["desde_copia"] += 1
        row = con.execute("SELECT * FROM alumnos WHERE id = ?", (aid,)).fetchone()
        d = alumno_dict(con, row)
        if clave and not profesor: d["pase"] = pase_alumno(con, row)
        return d

    def api_profesor(self, m, p, q, con):
        if p == ["salir"] and m == "POST":
            SESIONES.pop((self.headers.get("Authorization") or "").removeprefix("Bearer ").strip(), None)
            return dict(ok=True)
        if p == ["alumnos"] and m == "GET":
            rows = con.execute("SELECT * FROM alumnos ORDER BY archivado, nombre_norm").fetchall()
            return [alumno_dict(con, r) for r in rows]
        if p == ["alumnos"] and m == "POST":
            return self.alta(con, self.cuerpo(), profesor=True)
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
            if p[2:] == ["clave"] and m == "POST":             # el profesor pone una clave nueva (o la quita: la creara el alumno)
                c = self.cuerpo().get("clave")
                with con:
                    con.execute("UPDATE alumnos SET clave = ? WHERE id = ?", (hash_pin(clave_valida(c)) if c else None, aid))
                    registrar(con, "clave por el profesor", "%s (%s): %s" % (r["nombre"], aid, "nueva" if c else "quitada"))
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
                    C = certificado(con)
                    raise Error(409, "Aún no cumple los requisitos: %s h de vuelo y %d pruebas superadas" % (("%g" % C["horas"]).replace(".", ","), len(C["pruebas"])))
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
            C = certificado(con)
            w.writerow(["alumno", "id", "alta", "archivado", "vuelos", "horas", "accidentes", "aterrizajes"]
                       + [NOMBRES_ESC.get(e, e) for e in C["pruebas"]] + ["requisitos cumplidos", C["nombre"], "concedido el", "notas"])
            for r in con.execute("SELECT * FROM alumnos ORDER BY nombre_norm"):
                g = progreso(con, r["id"], C)
                w.writerow([r["nombre"], r["id"], r["creado"], "sí" if r["archivado"] else "no", g["vuelos"],
                            ("%.2f" % g["horas"]).replace(".", ","), g["accidentes"], g["aterrizajes"]]
                           + ["superado" if g["escenarios"][e]["superado"] else "pendiente" for e in C["pruebas"]]
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
    ips = ips_locales() or ["localhost"]
    print("\nServidor del aula en marcha (solo administra: el simulador se abre en cada ordenador).")
    print("   Panel del profesor:        http://localhost:%d/profesor.html" % a.puerto)
    print("   En la pantalla de acceso del simulador (web o Godot) de cada alumno, escribid:")
    for ip in ips: print("                              http://%s:%d" % (ip, a.puerto))
    print("Ctrl+C para parar.\n")
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        if CAMBIOS["desde_copia"]: print("Copia al cerrar:", hacer_copia("cierre"))


if __name__ == "__main__":
    main()
