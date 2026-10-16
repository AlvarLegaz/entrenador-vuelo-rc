class_name Aula
extends Node
## Aula y registro de vuelos, como en simulador/simulador.html (pantalla de acceso, api, cola de vuelos):
##  - al abrir el simulador, la pantalla de acceso: direccion del servidor del aula (aula/servidor_aula.py, el PC del
##    profesor), usuario y contrasena. Dentro, los vuelos y el progreso se guardan en el servidor (las mismas rutas
##    /api/... por HTTP); el alumno manda su pase con cada vuelo.
##  - sin conexion: se vuela igual, pero los vuelos no se guardan.
## Los vuelos que no se pueden enviar al servidor se guardan en una cola (user://cola_vuelos.json) y se reenvian.

const F_COLA := "user://cola_vuelos.json"
const F_CFG := "user://aula.cfg"

var activo := false            # dentro del aula (sesion.aula)
var nombre_aula := ""
var url := ""                  # servidor del aula (la ultima que se uso)
var usuario := ""              # el ultimo usuario que entro (para no volver a escribirlo)
var pase := ""                 # el pase del alumno (al entrar con su contrasena; solo mientras el simulador esta abierto)
var pase_id := ""
var _temporizador := 0.0

func _ready() -> void:
	var cf := ConfigFile.new()
	if cf.load(F_CFG) == OK:
		url = cf.get_value("aula", "url", ""); usuario = cf.get_value("aula", "usuario", "")

func _guardar_cfg() -> void:
	var cf := ConfigFile.new(); cf.load(F_CFG)
	cf.set_value("aula", "url", url); cf.set_value("aula", "usuario", usuario)
	cf.save(F_CFG)

func _process(dt: float) -> void:
	_temporizador += dt
	if _temporizador > 30: _temporizador = 0; vaciar_cola()

# =====================================================================
#  ACCESO (entrarAula de la web)
# =====================================================================
## La direccion como la escribe el alumno: sin http:// se le pone; "localhost" falla en Godot (lo resuelve a IPv6).
static func normalizar_url(u: String) -> String:
	u = u.strip_edges().trim_suffix("/")
	if u != "" and not (u.begins_with("http://") or u.begins_with("https://")): u = "http://" + u
	return u.replace("://localhost", "://127.0.0.1")

## Entra en el aula con usuario y contrasena (crear: alta del usuario si no existe). { ok, status, alumno, error }.
func entrar(direccion: String, usu: String, clave: String, crear := false) -> Dictionary:
	url = normalizar_url(direccion); usuario = " ".join(usu.split(" ", false)); _guardar_cfg()
	var r := await api("POST", "entrar", { "usuario": usuario, "clave": clave, "crear": crear }, "-")
	if not r["ok"]:
		if r["status"] == 0: r["error"] = "No se puede conectar con el aula en %s. Comprueba la dirección y que el profesor tenga abierto SERVIDOR_AULA.bat." % url
		return { "ok": false, "status": r["status"], "alumno": null, "error": r["error"] }
	var d = r["datos"]
	if not (d is Dictionary and d.get("alumno") is Dictionary and d.get("pase") is String and d["alumno"].get("id") is String):
		return { "ok": false, "status": r["status"], "alumno": null, "error": "El servidor del aula ha respondido algo que no entiendo: comprueba la dirección." }
	activo = true; pase = String(d["pase"]); pase_id = String(d["alumno"]["id"]); nombre_aula = url
	var e := await api("GET", "estado")
	if e["ok"] and e["datos"] is Dictionary: nombre_aula = String(e["datos"].get("aula", url))
	vaciar_cola()
	return { "ok": true, "status": r["status"], "alumno": r["datos"]["alumno"], "error": "" }

## Sin conexion (o al cerrar la sesion): se vuela igual, sin guardar.
func salir() -> void:
	activo = false; pase = ""; pase_id = ""

func texto_estado() -> String:
	return "Aula: " + nombre_aula if activo else "Sin conexión: los vuelos no se guardan"

# =====================================================================
#  API
# =====================================================================
## Devuelve { ok, status, datos, error }.
func api(metodo: String, ruta: String, cuerpo = null, con_pase = null) -> Dictionary:
	if url == "": return { "ok": false, "status": 0, "datos": null, "error": "no hay servidor del aula" }
	var req := HTTPRequest.new(); req.timeout = 6; req.body_size_limit = 8 << 20; req.max_redirects = 0; add_child(req)   # respuestas de menos de 8 MB y sin saltar a otro servidor
	var cab := PackedStringArray(["Content-Type: application/json"]) if cuerpo != null else PackedStringArray()
	var P: String = String(con_pase) if con_pase != null else pase
	if P != "": cab.append("X-Alumno: " + P)       # sin el, el servidor no acepta los vuelos del alumno
	var m: int = { "GET": HTTPClient.METHOD_GET, "POST": HTTPClient.METHOD_POST, "DELETE": HTTPClient.METHOD_DELETE }[metodo]
	var err := req.request(url.trim_suffix("/") + "/api/" + ruta, cab, m, JSON.stringify(cuerpo) if cuerpo != null else "")
	if err != OK: req.queue_free(); return { "ok": false, "status": 0, "datos": null, "error": "sin conexión" }
	var res: Array = await req.request_completed
	req.queue_free()
	var status: int = res[1]; var d = JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8()) if (res[3] as PackedByteArray).size() else null
	if res[0] != HTTPRequest.RESULT_SUCCESS: return { "ok": false, "status": 0, "datos": null, "error": "sin conexión con el aula" }
	if status < 200 or status >= 300:
		return { "ok": false, "status": status, "datos": d, "error": (d.get("error", "error %d" % status) if d is Dictionary else "error %d" % status) }
	return { "ok": true, "status": status, "datos": d, "error": "" }

## Envia un registro de vuelo comprimido con gzip (registro_vuelo.gd) a /api/registros con el pase de su alumno.
func subir_registro(gz: PackedByteArray, con_pase: String) -> Dictionary:
	if url == "": return { "ok": false, "status": 0, "error": "no hay servidor del aula" }
	var req := HTTPRequest.new(); req.timeout = 30; req.max_redirects = 0; add_child(req)
	var cab := PackedStringArray(["Content-Type: application/gzip", "X-Alumno: " + con_pase])
	if req.request_raw(url.trim_suffix("/") + "/api/registros", cab, HTTPClient.METHOD_POST, gz) != OK: req.queue_free(); return { "ok": false, "status": 0, "error": "sin conexión" }
	var res: Array = await req.request_completed
	req.queue_free()
	if res[0] != HTTPRequest.RESULT_SUCCESS: return { "ok": false, "status": 0, "error": "sin conexión con el aula" }
	return { "ok": res[1] >= 200 and res[1] < 300, "status": res[1], "error": "" }

# ---- cola de vuelos sin enviar ----
func _leer_cola() -> Array:
	var t := FileAccess.get_file_as_string(F_COLA)
	var d = JSON.parse_string(t) if t != "" else []
	return d if d is Array else []

func _guardar_cola(c: Array) -> void:
	var f := FileAccess.open(F_COLA, FileAccess.WRITE)
	if f: f.store_string(JSON.stringify(c))

var pendientes := 0
func vaciar_cola() -> void:
	RegistroVuelo.subir_pendientes(self)            # y los registros de vuelo (registro_vuelo.gd)
	if not activo: return
	var quedan := []
	for v in _leer_cola():
		var cuerpo: Dictionary = v.duplicate(); var p_: String = String(cuerpo.get("_pase", "")); cuerpo.erase("_pase")
		var r := await api("POST", "vuelos", cuerpo, p_)
		if not r["ok"] and not (r["status"] >= 400 and r["status"] < 500 and r["status"] != 401 and r["status"] != 429): quedan.append(v)
	_guardar_cola(quedan); pendientes = quedan.size()

## Envia un vuelo (enviarVuelo): { estado: "ok" | "cola" | "error" | "sin_aula", progreso, msg }.
func enviar_vuelo(v: Dictionary) -> Dictionary:
	if not activo: return { "estado": "sin_aula" }
	var r := await api("POST", "vuelos", v)
	if r["ok"]: vaciar_cola(); return { "estado": "ok", "progreso": r["datos"].get("progreso", {}) if r["datos"] is Dictionary else {} }
	if r["status"] >= 400 and r["status"] < 500 and r["status"] != 401 and r["status"] != 429: return { "estado": "error", "msg": r["error"] }
	var vc := v.duplicate(); vc["_pase"] = pase
	var c := _leer_cola(); c.append(vc); _guardar_cola(c)
	return { "estado": "cola" }

static func norm(s: String) -> String:
	var r := s.to_lower().strip_edges()
	for par in [["á", "a"], ["à", "a"], ["ä", "a"], ["â", "a"], ["é", "e"], ["è", "e"], ["ë", "e"], ["ê", "e"], ["í", "i"], ["ì", "i"], ["ï", "i"],
				["î", "i"], ["ó", "o"], ["ò", "o"], ["ö", "o"], ["ô", "o"], ["ú", "u"], ["ù", "u"], ["ü", "u"], ["û", "u"], ["ñ", "n"], ["ç", "c"]]:
		r = r.replace(par[0], par[1])
	return r

static func uuid4() -> String:
	var b := Crypto.new().generate_random_bytes(16)
	b[6] = (b[6] & 15) | 64; b[8] = (b[8] & 63) | 128
	var h := b.hex_encode()
	return "%s-%s-%s-%s-%s" % [h.substr(0, 8), h.substr(8, 4), h.substr(12, 4), h.substr(16, 4), h.substr(20)]

static func ahora_iso() -> String: return Time.get_datetime_string_from_system(true) + "Z"
