class_name DatosComunes
## Acceso a los DATOS COMUNES de los dos simuladores, en la carpeta simulador/ del repositorio (la misma que usa el
## simulador del navegador): aviones (aviones/*.js), mundos reales (mundos/*.js y su ortofoto) y zonas de detalle
## (zonas/indice.json y zonas/<id>/). Los .js de aviones y mundos llevan los datos como JSON dentro de
## Modelos.registrar({...}) o Mundos.registrar({...}): aqui se saca ese JSON tal cual, sin copiarlo a otro sitio.

static func carpeta() -> String:
	# simulador_godot/ esta junto a simulador/; si se exporta, se busca junto al ejecutable
	var cand := [ProjectSettings.globalize_path("res://").path_join("../simulador"), OS.get_executable_path().get_base_dir().path_join("simulador"),
				 OS.get_executable_path().get_base_dir().path_join("../simulador")]
	for c in cand:
		if DirAccess.dir_exists_absolute(c): return c.simplify_path()
	return cand[0].simplify_path()

static func _json_de_registrar(ruta: String, marca: String) -> Dictionary:
	var texto := FileAccess.get_file_as_string(ruta)
	var i := texto.find(marca)
	if i < 0:
		push_error("Sin %s en %s" % [marca, ruta]); return {}
	var resto := texto.substr(i + marca.length())
	var fin := resto.rfind("}")
	var d = JSON.parse_string(resto.substr(0, fin + 1))
	return d if d is Dictionary else {}

## Ids de los aviones, en el orden de aviones/indice.js.
static func aviones() -> Array:
	var t := FileAccess.get_file_as_string(carpeta().path_join("aviones/indice.js"))
	var i := t.find("Modelos.indice(")
	var lista = JSON.parse_string(t.substr(i + 15, t.rfind("]") - i - 14))
	var ids := []
	for f in lista:
		# el cuadricoptero (controlador de vuelo propio, clase ModeloCuadricoptero en JS) aun no esta portado a Godot
		# (su fichero es JS con claves sin comillas, no JSON: se reconoce por la clase)
		if FileAccess.get_file_as_string(carpeta().path_join("aviones/%s" % f)).contains("ModeloCuadricoptero"): continue
		ids.append(String(f).get_basename())
	return ids

static func avion(id: String) -> Dictionary:
	return _json_de_registrar(carpeta().path_join("aviones/%s.js" % id), "Modelos.registrar(")

static func mundo(id: String) -> Dictionary:
	return _json_de_registrar(carpeta().path_join("mundos/%s.js" % id), "Mundos.registrar(")

static func ruta_orto_mundo(id: String) -> String:
	return carpeta().path_join("mundos/%s_orto.jpg" % id)

static func indice_zonas() -> Array:
	var ruta := carpeta().path_join("zonas/indice.json")
	if not FileAccess.file_exists(ruta): return []
	var d = JSON.parse_string(FileAccess.get_file_as_string(ruta))
	return d if d is Array else []

## La zona de un mundo que contiene (N, E) con 150 m de margen (la misma regla que zonaEn() en simulador.html).
static func zona_en(indice: Array, mundo_id: String, N: float, E: float) -> Dictionary:
	for z in indice:
		if z["mundo"] == mundo_id and N > z["N0"] + 150 and N < z["N0"] + z["lado_m"] - 150 and E > z["E0"] + 150 and E < z["E0"] + z["lado_m"] - 150:
			return z
	return {}

## { meta, dem: PackedInt32Array (dm sobre el mar, -32768 = agua), base: carpeta de la zona }
static func cargar_zona(meta: Dictionary) -> Dictionary:
	var base := carpeta().path_join("zonas/%s" % meta["id"])
	var bytes := FileAccess.get_file_as_bytes(base.path_join(meta["dem"]["archivo"]))
	var n := bytes.size() / 2
	var dem := PackedInt32Array(); dem.resize(n)
	for k in n: dem[k] = bytes.decode_s16(2 * k)
	return { "meta": meta, "dem": dem, "base": base }
