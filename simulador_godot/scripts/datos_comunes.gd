class_name DatosComunes
## Acceso a los DATOS COMUNES de los dos simuladores, en la carpeta simulador/ del repositorio (la misma que usa el
## simulador del navegador): aviones (aviones/*.js), mundos reales (mundos/*.js y su ortofoto) y zonas de detalle
## (zonas/indice.json y zonas/<id>/). Los .js de aviones y mundos llevan los datos como JSON dentro de
## Modelos.registrar({...}) o Mundos.registrar({...}): aqui se saca ese JSON tal cual, sin copiarlo a otro sitio.
## El cuadricoptero (aviones/DJI_MINI.js) lleva sus datos como JSON en "const DATOS = {...}" y su malla la calcula
## el codigo JS que la sigue: aqui se lee ese JSON y la malla se calcula igual (_malla_cuadricoptero).

static func carpeta() -> String:
	# simulador_godot/ esta junto a simulador/; si se exporta, se busca junto al ejecutable
	var cand := [ProjectSettings.globalize_path("res://").path_join("../simulador"), OS.get_executable_path().get_base_dir().path_join("simulador"),
				 OS.get_executable_path().get_base_dir().path_join("../simulador")]
	for c in cand:
		if DirAccess.dir_exists_absolute(c): return c.simplify_path()
	return cand[0].simplify_path()

static func _json_de_registrar(ruta: String, marca: String) -> Dictionary:
	return _json_tras_marca(FileAccess.get_file_as_string(ruta), marca, ruta)

static func _json_tras_marca(texto: String, marca: String, ruta: String) -> Dictionary:
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
	for f in lista: ids.append(String(f).get_basename())
	return ids

## Datos de un avion. Los de un cuadricoptero (tipo "cuadricoptero", clase ModeloCuadricoptero) traen ademas su malla.
static var _grandes := {}           # los datos de cada avion, leidos y parseados una vez (se pedian en cada cuadro: HUD, multijugador)
static func avion(id: String) -> Dictionary:
	if _grandes.has(id): return _grandes[id]
	if not id.is_valid_filename() or id.begins_with("."): return {}      # un id raro (de la red) no lee nada del disco
	var ruta := carpeta().path_join("aviones/%s.js" % id)
	var d := {}
	if FileAccess.file_exists(ruta):
		var texto := FileAccess.get_file_as_string(ruta)
		var re := RegEx.create_from_string(MARCA_DATOS)
		var r := re.search(texto)
		d = _json_tras_marca(texto, "Modelos.registrar(", ruta) if r == null else _objeto_json(texto, r.get_end() - 1, ruta)
		if d.get("tipo", "") == "cuadricoptero": _malla_cuadricoptero(d)
	_grandes[id] = d
	return d

## Linea (no comentario) que empieza los datos de un fichero de aviones que no los lleva dentro de Modelos.registrar.
const MARCA_DATOS := r"(?m)^[ \t]*const DATOS = \{"

## El objeto JSON que empieza en la llave de la posicion i0: hasta la llave que la cierra (se cuentan las llaves que
## no estan dentro de una cadena), sin depender de lo que venga detras.
static func _objeto_json(texto: String, i0: int, ruta: String) -> Dictionary:
	var nivel := 0; var en_cadena := false; var escape := false; var k := i0
	while k < texto.length():
		var ch := texto[k]
		if en_cadena:
			if escape: escape = false
			elif ch == "\\": escape = true
			elif ch == "\"": en_cadena = false
		elif ch == "\"": en_cadena = true
		elif ch == "{": nivel += 1
		elif ch == "}":
			nivel -= 1
			if nivel == 0: break
		k += 1
	var d = JSON.parse_string(texto.substr(i0, k - i0 + 1))
	if not d is Dictionary: push_error("Datos JSON mal formados en %s" % ruta); return {}
	return d

## Malla del cuadricoptero: traduccion LITERAL del codigo que la construye en aviones/DJI_MINI.js (mismas cajas, mismo
## orden de vertices y caras). Cuerpo, brazos y patas (fuselaje), motores y camara (estab) y los 4 rotores (helices).
static func _malla_cuadricoptero(datos: Dictionary) -> void:
	var V := { "fuselaje": { "v": [], "i": [] }, "estab": { "v": [], "i": [] } }
	_caja(V, "fuselaje", 0, 0, 0, 0.14, 0.08, 0.05)                       # cuerpo
	_caja(V, "estab", 0.078, 0, 0.012, 0.025, 0.032, 0.03)                 # camara con su cardan, delante y abajo
	var brazos := [[0.095, 0.09], [0.095, -0.09], [-0.095, 0.09], [-0.095, -0.09]]
	for b in brazos:
		var x: float = b[0]; var y: float = b[1]
		_caja(V, "fuselaje", x * 0.62, y * 0.62, -0.004, 0.11, 0.012, 0.008, atan2(y, x))   # brazo
		_caja(V, "estab", x, y, -0.008, 0.02, 0.02, 0.016)                                   # motor
		_caja(V, "estab", x * 0.5, y * 0.4, 0.03, 0.01, 0.01, 0.02)                          # pata
	var S: float = float(datos.get("modelo3d", {}).get("escala", 1.0))     # aviones/HQ3T.js: la misma malla a escala
	if S != 1.0:
		for parte in V.values():
			var mv: Array = parte["v"]
			for i in mv.size(): mv[i] = mv[i] * S
	var malla: Dictionary = datos["malla"]
	malla["fuselaje"] = V["fuselaje"]; malla["estab"] = V["estab"]
	malla["helices"] = brazos.map(func(b): return [b[0] * S, b[1] * S, -0.018 * S])

## Caja centrada en (cx, cy, cz), de lados sx, sy, sz, girada ang radianes sobre z.
static func _caja(V: Dictionary, parte: String, cx: float, cy: float, cz: float, sx: float, sy: float, sz: float, ang := 0.0) -> void:
	var M: Dictionary = V[parte]; var mv: Array = M["v"]; var mi: Array = M["i"]
	var b := mv.size() / 3; var c := cos(ang); var s := sin(ang)
	for e in [[-1, -1, -1], [1, -1, -1], [1, 1, -1], [-1, 1, -1], [-1, -1, 1], [1, -1, 1], [1, 1, 1], [-1, 1, 1]]:
		var x: float = e[0] * sx / 2; var y: float = e[1] * sy / 2
		mv.append_array([cx + x * c - y * s, cy + x * s + y * c, cz + e[2] * sz / 2])
	for f in [[0, 1, 2, 3], [4, 7, 6, 5], [0, 4, 5, 1], [1, 5, 6, 2], [2, 6, 7, 3], [3, 7, 4, 0]]:
		mi.append_array([b + f[0], b + f[1], b + f[2], b + f[0], b + f[2], b + f[3]])

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
