class_name Aula
extends Node
## Aula y registro de vuelos, como en simulador/simulador.html (api, cola de vuelos, AulaLocal):
##  - servidor del aula (aula/servidor_aula.py): las mismas rutas /api/... por HTTP. En la web la direccion es la de la
##    propia pagina; aqui se escribe en Ajustes › Registro y aula (p. ej. http://192.168.1.20:8000).
##  - registro local: alumnos y vuelos en este ordenador (user://registro_local.json y, si se elige, un archivo JSON
##    que se reescribe tras cada cambio), con el mismo progreso que calcula el servidor.
##  - sin aula: los vuelos no se guardan.
## Los vuelos que no se pueden enviar al servidor se guardan en una cola (user://cola_vuelos.json) y se reenvian.

const HORAS_MINIMAS := 10.0
const ESC := ["primer_vuelo", "orientacion", "viento_cruzado", "emergencia"]
const F_LOCAL := "user://registro_local.json"
const F_COLA := "user://cola_vuelos.json"
const F_CFG := "user://aula.cfg"

var activo := false            # sesion.aula
var modo := "servidor"         # "servidor" | "local"
var nombre_aula := ""
var url := ""                  # servidor del aula (vacio = no hay)
var pase := ""                 # el pase del alumno online (al entrar con su clave; solo mientras el simulador esta abierto)
var pase_id := ""
var datos := {}                # registro local: { version, creado, alumnos: [], vuelos: [] }
var archivo := ""              # archivo JSON del registro local (ademas de user://)
var error_archivo := ""
var _temporizador := 0.0

func _ready() -> void:
	var cf := ConfigFile.new()
	if cf.load(F_CFG) == OK:
		url = cf.get_value("aula", "url", ""); archivo = cf.get_value("aula", "archivo", "")

func _guardar_cfg(modo_guardado := "") -> void:
	var cf := ConfigFile.new(); cf.load(F_CFG)
	cf.set_value("aula", "url", url); cf.set_value("aula", "archivo", archivo)
	if modo_guardado != "": cf.set_value("aula", "modo", modo_guardado)
	cf.save(F_CFG)

func _modo_guardado() -> String:
	var cf := ConfigFile.new()
	return cf.get_value("aula", "modo", "") if cf.load(F_CFG) == OK else ""

func _process(dt: float) -> void:
	_temporizador += dt
	if _temporizador > 30: _temporizador = 0; vaciar_cola()

# =====================================================================
#  ARRANQUE (iniciarAula, activarAulaLocal)
# =====================================================================
func iniciar() -> void:
	activo = false; modo = "servidor"
	if _modo_guardado() == "local": activar_local()
	elif url != "":
		var r := await api("GET", "estado")
		if r["ok"]: activo = true; nombre_aula = String(r["datos"].get("aula", url))

## El ultimo perfil elegido en cada modo (recordarPerfil / perfilRecordado).
func recordar_perfil(id: String) -> void:
	var cf := ConfigFile.new(); cf.load(F_CFG); cf.set_value("aula", "perfil_" + modo, id); cf.save(F_CFG)
func perfil_recordado() -> String:
	var cf := ConfigFile.new()
	return String(cf.get_value("aula", "perfil_" + modo, "")) if cf.load(F_CFG) == OK else ""

func activar_local() -> void:
	_cargar_local(); activo = true; modo = "local"; nombre_aula = "este ordenador"
	_guardar_cfg("local")

func texto_estado() -> String:
	if not activo: return "Sin aula: los vuelos no se guardan"
	return "Registro local de este ordenador" if modo == "local" else "Aula: " + nombre_aula

# =====================================================================
#  API (la misma que el servidor)
# =====================================================================
## Devuelve { ok, status, datos, error }.
func api(metodo: String, ruta: String, cuerpo = null, con_pase = null) -> Dictionary:
	if modo == "local" and activo: return _api_local(metodo, ruta, cuerpo)
	if url == "": return { "ok": false, "status": 0, "datos": null, "error": "no hay servidor del aula" }
	var req := HTTPRequest.new(); req.timeout = 6; add_child(req)
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
	if not activo or modo == "local": return
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
	if r["ok"]: vaciar_cola(); return { "estado": "ok", "progreso": r["datos"].get("progreso", {}) }
	if r["status"] >= 400 and r["status"] < 500 and r["status"] != 401 and r["status"] != 429: return { "estado": "error", "msg": r["error"] }
	var vc := v.duplicate(); vc["_pase"] = pase
	var c := _leer_cola(); c.append(vc); _guardar_cola(c)
	return { "estado": "cola" }

# =====================================================================
#  REGISTRO LOCAL (AulaLocal)
# =====================================================================
func _cargar_local() -> void:
	var t := ""
	if archivo != "" and FileAccess.file_exists(archivo): t = FileAccess.get_file_as_string(archivo)     # el archivo manda
	if t == "": t = FileAccess.get_file_as_string(F_LOCAL)
	var d = JSON.parse_string(t) if t != "" else null
	if d is Dictionary and d.get("alumnos") is Array and d.get("vuelos") is Array: datos = d
	else: datos = { "version": 1, "creado": Time.get_datetime_string_from_system(true) + "Z", "alumnos": [], "vuelos": [] }

func guardar_local() -> void:
	var txt := JSON.stringify(datos, " ")
	var f := FileAccess.open(F_LOCAL, FileAccess.WRITE)
	if f: f.store_string(txt); f.close()
	if archivo != "":
		var g := FileAccess.open(archivo, FileAccess.WRITE)
		if g: g.store_string(txt); g.close(); error_archivo = ""
		else: error_archivo = "no se pudo escribir (%s)" % error_string(FileAccess.get_open_error())

## Archivo JSON del registro: nuevo (escribe lo actual) o existente (lo carga).
func usar_archivo(ruta: String, escribir_primero: bool) -> String:
	if not escribir_primero:
		var d = JSON.parse_string(FileAccess.get_file_as_string(ruta))
		if not (d is Dictionary and d.get("alumnos") is Array and d.get("vuelos") is Array): return "El archivo no es un registro del simulador"
		datos = d
	archivo = ruta; _guardar_cfg(); guardar_local()
	return ""

func exportar(ruta: String) -> void:
	var f := FileAccess.open(ruta, FileAccess.WRITE)
	if f: f.store_string(JSON.stringify(datos, " "))

func importar(ruta: String) -> String:
	var d = JSON.parse_string(FileAccess.get_file_as_string(ruta))
	if not (d is Dictionary and d.get("alumnos") is Array and d.get("vuelos") is Array): return "El archivo no es un registro del simulador"
	datos = d; guardar_local()
	return ""

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

func progreso(id: String) -> Dictionary:
	var vs := (datos["vuelos"] as Array).filter(func(v): return v["alumno_id"] == id)
	var sup := {}
	for v in vs:
		if v.get("resultado", "") == "APTO": sup[v["escenario"]] = true
	var horas := 0.0; var acc := 0; var ate := 0; var ult := ""
	for v in vs:
		horas += float(v.get("tiempo_vuelo_s", 0)); acc += int(v.get("accidentes", 0)); ate += int(v.get("aterrizajes", 0))
		if String(v.get("inicio", "")) > ult: ult = v["inicio"]
	horas /= 3600.0
	var esc := {}; var n_sup := 0
	for e in ESC:
		esc[e] = { "superado": sup.has(e), "intentos": vs.filter(func(v): return v["escenario"] == e).size() }
		if sup.has(e): n_sup += 1
	return { "vuelos": vs.size(), "horas": snappedf(horas, 0.001), "accidentes": acc, "aterrizajes": ate, "ultimo_vuelo": ult if ult != "" else null,
			 "escenarios": esc, "escenarios_superados": n_sup, "escenarios_total": ESC.size(), "horas_minimas": HORAS_MINIMAS, "certificado": "Certificado de pilotaje",
			 "requisitos_cumplidos": horas >= HORAS_MINIMAS and n_sup == ESC.size() }

func _alumno(a: Dictionary) -> Dictionary:
	var d := a.duplicate(); d["progreso"] = progreso(a["id"])
	return d

func _err(status: int, msg: String) -> Dictionary: return { "ok": false, "status": status, "datos": null, "error": msg }
func _ok(d) -> Dictionary: return { "ok": true, "status": 200, "datos": d, "error": "" }

func _api_local(m: String, ruta: String, cuerpo) -> Dictionary:
	var p := ruta.split("/")
	if m == "GET" and ruta == "estado": return _ok({ "ok": true, "aula": "este ordenador", "horas_minimas": HORAS_MINIMAS, "escenarios": ESC, "local": true })
	if m == "GET" and ruta == "alumnos":
		var l := (datos["alumnos"] as Array).filter(func(a): return not a.get("archivado", false))
		l.sort_custom(func(a, b): return norm(a["nombre"]) < norm(b["nombre"]))
		return _ok(l.map(func(a): return _alumno(a)))
	if m == "POST" and ruta == "alumnos":
		var nombre := " ".join(String((cuerpo if cuerpo is Dictionary else {}).get("nombre", "")).split(" ", false)).strip_edges()
		if nombre.length() < 2 or nombre.length() > 60: return _err(400, "El nombre tiene que tener entre 2 y 60 caracteres")
		for a in datos["alumnos"]:
			if not a.get("archivado", false) and norm(a["nombre"]) == norm(nombre): return _err(409, "Ya hay un alumno con ese nombre")
		var a := { "id": uuid4(), "nombre": nombre, "creado": ahora_iso(), "notas": "", "archivado": false, "archivado_en": null, "habilitado": false, "habilitado_en": null }
		datos["alumnos"].append(a); guardar_local(); return _ok(_alumno(a))
	if p.size() == 2 and p[0] == "alumnos":
		var a = null
		for x in datos["alumnos"]:
			if x["id"] == p[1]: a = x
		if a == null: return _err(404, "alumno no encontrado")
		if m == "GET":
			var d := _alumno(a)
			var vs := (datos["vuelos"] as Array).filter(func(v): return v["alumno_id"] == a["id"])
			vs.sort_custom(func(x, y): return String(x["inicio"]) > String(y["inicio"]))
			var E := Escenarios.datos()
			d["vuelos"] = vs.map(func(v): var w: Dictionary = v.duplicate(); w["escenario_nombre"] = E.get(v["escenario"], {}).get("nombre", v["escenario"]); return w)
			return _ok(d)
		if m == "DELETE": a["archivado"] = true; a["archivado_en"] = ahora_iso(); guardar_local(); return _ok({ "ok": true })
	if m == "POST" and ruta == "vuelos":
		var v: Dictionary = cuerpo if cuerpo is Dictionary else {}
		for k in ["id", "alumno_id", "inicio", "avion", "escenario", "resultado"]:
			if not v.has(k) or String(v[k]) == "": return _err(400, "faltan campos: " + k)
		if not (datos["alumnos"] as Array).any(func(a): return a["id"] == v["alumno_id"]): return _err(404, "alumno no encontrado")
		var nuevo := not (datos["vuelos"] as Array).any(func(x): return x["id"] == v["id"])
		if nuevo:
			var w := v.duplicate(); w["tiempo_vuelo_s"] = maxf(0, float(v.get("tiempo_vuelo_s", 0))); w["recibido"] = ahora_iso()
			datos["vuelos"].append(w); guardar_local()
		return _ok({ "ok": true, "nuevo": nuevo, "progreso": progreso(v["alumno_id"]) })
	return _err(404, "ruta no disponible en el registro local: %s %s" % [m, ruta])
