class_name RegistroVuelo
## Registro de vuelo de cada vehiculo, como el que se descarga de un dron comercial: RegistroVuelo de
## simulador/js/registro.js, con las mismas columnas y el mismo formato. 10 muestras por segundo con la posicion
## (latitud y longitud), alturas, velocidades, actitud, la bateria (carga, tension, corriente, potencia, temperatura y
## cada celda), gas y vueltas, palancas, gimbal, modo y estado, y los avisos del vuelo. Se guarda en la carpeta de datos
## (user://registros/<vehiculo>/<id>.json, los ultimos 30 de cada uno) y, con el alumno en el aula, tambien en el
## servidor (comprimido; si no hay red, se reintenta: user://registros/pendientes.json). Lo lee el modo Taller.

const CADA_S := 0.1
const MAX_POR_VEHICULO := 30
const DIR := "user://registros"
const F_PEND := "user://registros/pendientes.json"

## Columnas del registro de un modelo (las celdas segun su bateria).
static func columnas(m) -> Array:
	var B = m.get("B") if m != null else null
	var n: int = int(B["celdas"]) if B is Dictionary and not B.is_empty() else 0
	var c := ["tiempo_s", "latitud", "longitud", "altura_despegue_m", "altura_suelo_m", "velocidad_h_ms", "velocidad_v_ms",
			  "distancia_m", "rumbo_grados", "alabeo_grados", "cabeceo_grados", "bateria_pct", "tension_V", "corriente_A", "potencia_W", "temperatura_bateria_C"]
	for i in range(1, n + 1): c.append("celda%d_V" % i)
	return c + ["gas_pct", "rpm", "palanca_cabeceo", "palanca_alabeo", "palanca_guinada", "palanca_gas", "gimbal_grados", "modo", "estado"]

## Empieza el registro de un vuelo (vuelo.reg). p: principal.gd.
static func empezar(p, vuelo: Dictionary) -> void:
	if p.es_bipode(): return                         # el bipode no lleva registro
	var M: Dictionary = p.ent.mundo
	var o: Dictionary = M["origen"] if M.has("origen") else { "lat": 37.612788, "lon": -1.049916 }     # el campo del club: junto al origen de Cartagena
	var av: Dictionary = p.av
	vuelo["reg"] = { "columnas": columnas(p.modelo), "filas": [], "eventos": [], "casa": [av["p"][0], av["p"][1], -av["p"][2]], "origen": o, "tUlt": -1.0 }

## Estado del vehiculo en palabras.
static func estado(av: Dictionary) -> String:
	if av["estado"] != "volando": return av["estado"]
	if av.get("sinBateria", false): return "sin bateria"
	if av.get("cortado", false): return "motor cortado"
	if av.get("batForzado", false): return "aterrizaje forzoso"
	if av.get("rth") != null: return "volviendo a casa"
	if av.get("posado", false) or av.get("enTierra", false): return "en tierra"
	return "volando"

static func _r(x, n: int):
	if x == null: return null
	var f := float(x)
	if is_nan(f) or is_inf(f): return null
	return snappedf(f, pow(10, -n))

## Una muestra (cada 0,1 s de vuelo, y la ultima al acabar).
static func muestra(p, vuelo, forzar := false) -> void:
	if vuelo == null or not vuelo.has("reg"): return
	var R: Dictionary = vuelo["reg"]; var av: Dictionary = p.av
	if not forzar and av["t"] - R["tUlt"] < CADA_S - 1e-9: return
	R["tUlt"] = av["t"]
	var o: Dictionary = R["origen"]; var D := PI / 180
	var eu := Cuat.euler(av["q"]); var vn := Cuat.rot(av["q"], av["v"]); var m = p.modelo; var B = m.get("B"); var e = av.get("bat")
	var fila := [_r(av["t"], 2), _r(o["lat"] + av["p"][0] / 110574, 7), _r(o["lon"] + av["p"][1] / (111320 * cos(o["lat"] * D)), 7), _r(-av["p"][2] - R["casa"][2], 2),
		_r(av["agl"] if av.get("agl") != null else -av["p"][2], 2), _r(Vector2(vn[0], vn[1]).length(), 2), _r(-vn[2], 2),
		_r(Vector2(av["p"][0] - R["casa"][0], av["p"][1] - R["casa"][1]).length(), 1), _r(fposmod(eu[2] / D + 360, 360), 1), _r(eu[0] / D, 1), _r(eu[1] / D, 1),
		_r(m.bateria_pct(av) if m.has_method("bateria_pct") else null, 1),
		_r(e["V"] if e != null else null, 3), _r(e["I"] if e != null else null, 2), _r(e["P"] if e != null else null, 1), _r(e["T"] if e != null else null, 2)]
	if B is Dictionary and not B.is_empty():
		for i in int(B["celdas"]): fila.append(_r(e["celdas"][i] if e != null else null, 3))
	var gas = p.mando.get("vz", 0.0) if (p.es_dron() and not p.es_fpv()) else av["gases"]
	var modo = (p.piloto.modo if p.piloto != null and p.es_uav() else (m.get("modo") if m.get("modo") != null else "manual"))
	var gimbal = av["gimbal"] if av.has("gimbal") else (av["torreta"]["tilt"] / D if av.has("torreta") else null)
	fila.append_array([_r(float(av.get("gasMotor", av["gases"])) * 100, 1), _r(av["rpm"], 0), _r(p.mando["pitch"], 3), _r(p.mando["yaw"], 3), _r(p.mando.get("guinada", 0.0), 3), _r(gas, 3),
		_r(gimbal, 1), String(modo), estado(av)])
	R["filas"].append(fila)

## Un aviso del vuelo (lo que sale en pantalla), con su tiempo.
static func evento(p, vuelo, txt: String) -> void:
	if vuelo != null and vuelo.has("reg") and txt != "": vuelo["reg"]["eventos"].append([snappedf(float(p.av.get("t", 0.0)), 0.1), txt])

## Al acabar el vuelo: el registro completo, guardado en la carpeta de datos y enviado al aula. Devuelve el registro.
static func cerrar(p, vuelo) -> Dictionary:
	if vuelo == null or not vuelo.has("reg") or vuelo["reg"].get("cerrado", false): return {}
	muestra(p, vuelo, true)
	var R: Dictionary = vuelo["reg"]; R["cerrado"] = true
	var E: Dictionary = Escenarios.datos().get(vuelo["escenario"], {}); var B = p.modelo.get("B")
	var reg := { "id": vuelo["id"], "avion": p.sesion["avion"], "avion_nombre": p.modelo.datos.get("nombre", p.sesion["avion"]), "inicio": vuelo["inicio"],
		"escenario": vuelo["escenario"], "escenario_nombre": E.get("nombre", vuelo["escenario"]), "alumno": p.sesion["alumno"]["nombre"] if p.sesion.get("alumno") is Dictionary else null,
		"final": vuelo["final"], "duracion_s": snappedf(float(p.av.get("t", 0.0)), 0.1),
		"bateria": { "quimica": B["quimica"], "celdas": B["celdas"], "capacidad_mAh": B["capacidad_mAh"] } if B is Dictionary and not B.is_empty() else null,
		"columnas": R["columnas"], "filas": R["filas"], "eventos": R["eventos"] }
	guardar(reg, { "alumno_id": p.sesion["alumno"]["id"], "pase": p.aula.pase } if p.aula.activo and p.sesion.get("alumno") is Dictionary else {})
	subir_pendientes(p.aula)
	return reg

## Guarda un registro (y, si hay que enviarlo al aula, lo apunta en los pendientes); deja los ultimos 30 del vehiculo.
static func guardar(reg: Dictionary, subir: Dictionary) -> void:
	var dir := DIR.path_join(String(reg["avion"])); DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(dir.path_join(String(reg["id"]) + ".json"), FileAccess.WRITE)
	if f: f.store_string(JSON.stringify(reg)); f.close()
	var pend := _pendientes()
	if not subir.is_empty(): pend.append({ "id": reg["id"], "avion": reg["avion"], "alumno_id": subir["alumno_id"], "pase": subir["pase"] }); _guardar_pendientes(pend)
	var ids_pend := pend.map(func(x): return String(x["id"]))
	var lista := listar(String(reg["avion"])).filter(func(x): return not ids_pend.has(String(x["id"])))
	for x in lista.slice(MAX_POR_VEHICULO): DirAccess.remove_absolute(dir.path_join(String(x["id"]) + ".json"))

static func _pendientes() -> Array:
	var t := FileAccess.get_file_as_string(F_PEND); var d = JSON.parse_string(t) if t != "" else []
	return d if d is Array else []

static func _guardar_pendientes(a: Array) -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var f := FileAccess.open(F_PEND, FileAccess.WRITE)
	if f: f.store_string(JSON.stringify(a)); f.close()

## Los registros (sin las muestras) de un vehiculo, o de todos ("" ), del mas nuevo al mas viejo.
static func listar(avion := "") -> Array:
	var out := []
	var dirs := [avion] if avion != "" else (Array(DirAccess.get_directories_at(DIR)) if DirAccess.dir_exists_absolute(DIR) else [])
	for a in dirs:
		var d := DIR.path_join(a)
		if not DirAccess.dir_exists_absolute(d): continue
		for fn in DirAccess.get_files_at(d):
			if not fn.ends_with(".json"): continue
			var reg = JSON.parse_string(FileAccess.get_file_as_string(d.path_join(fn)))
			if not reg is Dictionary: continue
			var meta: Dictionary = reg.duplicate(); meta.erase("filas"); meta.erase("columnas"); meta.erase("eventos")
			meta["muestras"] = (reg.get("filas", []) as Array).size(); meta["n_eventos"] = (reg.get("eventos", []) as Array).size()
			out.append(meta)
	out.sort_custom(func(x, y): return String(x["inicio"]) > String(y["inicio"]))
	return out

static func leer(avion: String, id: String) -> Dictionary:
	var reg = JSON.parse_string(FileAccess.get_file_as_string(DIR.path_join(avion).path_join(id + ".json")))
	return reg if reg is Dictionary else {}

## Envia al aula los registros pendientes (comprimidos con gzip, a /api/registros, con el pase de su alumno).
static func subir_pendientes(aula) -> void:
	if aula == null or aula.url == "": return
	var quedan := []
	for x in _pendientes():
		var reg := leer(String(x["avion"]), String(x["id"]))
		if reg.is_empty(): continue
		reg["alumno_id"] = x["alumno_id"]
		var r: Dictionary = await aula.subir_registro(JSON.stringify(reg).to_utf8_buffer().compress(FileAccess.COMPRESSION_GZIP), String(x["pase"]))
		if not r["ok"] and not (r["status"] >= 400 and r["status"] < 500 and r["status"] != 401 and r["status"] != 429): quedan.append(x)
	_guardar_pendientes(quedan)

## CSV de un registro (columnas en la primera linea; los avisos, en una columna mas, en su momento). Como registroCSV.
static func csv(reg: Dictionary) -> String:
	var ev: Array = (reg.get("eventos", []) as Array).duplicate(); var L := [",".join(PackedStringArray(Array(reg["columnas"]) + ["aviso"]))]
	for f in reg["filas"]:
		var avisos := []
		while not ev.is_empty() and float(ev[0][0]) <= float(f[0]) + 1e-9: avisos.append(String(ev.pop_front()[1]))
		var c := PackedStringArray()
		for x in f: c.append("" if x == null else ('"' + String(x) + '"' if x is String else _num(x)))
		c.append('"' + " | ".join(PackedStringArray(avisos)).replace('"', "'") + '"')
		L.append(",".join(c))
	return "﻿" + "\n".join(PackedStringArray(L)) + "\n"

static func _num(x) -> String:
	var f := float(x)
	return str(int(f)) if f == floor(f) and absf(f) < 1e15 else str(f)
