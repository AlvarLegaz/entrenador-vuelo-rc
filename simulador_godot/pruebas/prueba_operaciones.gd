extends SceneTree
## Prueba de que los trabajos del modo Operaciones (Operacion) son los mismos en los dos simuladores.
## pruebas/referencia_operaciones_js.json trae vuelos de prueba de los 6 trabajos de escenarios.js (con aciertos, fallos,
## choques y normas incumplidas; posiciones, gimbal, video y fotos dados, sin fisica, sobre un suelo ondulado de prueba) y
## lo que dice de cada uno la clase Operacion de simulador/js/operaciones.js en el navegador (la genera
## pruebas/generar_referencia_operaciones.py). Aqui se repiten con operaciones.gd y se comparan los objetivos (estado y
## texto), los avisos, el choque y la linea "Ahora" del panel. Comprueba tambien que las operaciones no salen en los
## entrenamientos.
## Uso (desde la carpeta del repositorio):
##   herramientas/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path simulador_godot --script res://pruebas/prueba_operaciones.gd

const D2R := PI / 180.0
var fallos := 0

func _ok(nombre: String, cond: bool, detalle := "") -> void:
	if not cond: fallos += 1
	print("  %s %s %s" % ["OK " if cond else "MAL", nombre, detalle])

func _vuelo(v: Dictionary) -> Dictionary:
	var E: Dictionary = Escenarios.datos()[v["mision"]]; var obj := {}; var orden := []
	for o in E["objetivos"]: obj[o[0]] = { "texto": o[1], "estado": "curso" if o[0] in ["techo", "vlos", "zona", "baja", "distancia", "suave"] else "pend" }; orden.append(o[0])
	var marcar := func(k: String, e: String) -> void:
		if obj.has(k) and obj[k]["estado"] != "mal": obj[k]["estado"] = e
	var anotar := func(k: String, t: String) -> void:
		if obj.has(k): obj[k]["texto"] += " (%s)" % t
	var d: Dictionary = E["operacion"].duplicate()
	if v["persona"] != null: d["persona"] = v["persona"]
	var suelo := func(N: float, Ee: float) -> float: return 3 * sin(N * 0.01) + 2 * cos(Ee * 0.013)
	var op := Operacion.new(d, marcar, anotar, { "casa": [E["operacion"]["salida"]["n"], E["operacion"]["salida"]["e"]], "suelo": suelo, "h0": 0.0 })
	var avisos := []; var ahora := []; var p_ant = null; var av := {}; var choque = null
	var est: Array = v["estados"]
	for i in est.size():
		var s: Array = est[i]
		av = { "p": [s[0], s[1], -s[2]], "q": Cuat.desde_euler(0, 0, s[3] * D2R), "estado": "volando", "posado": s[4] != 0, "t": s[8] }
		if choque != null: continue
		if p_ant != null:
			for t in op.paso(p_ant, av, 0.1, { "gimbal": s[5], "grabando": s[6] != 0 }): avisos.append("%.1f %s" % [s[8], t])
		if op.choque != "": choque = op.choque; continue
		if s[7] != 0:
			for t in op.foto(av, s[5]): avisos.append("%.1f foto: %s" % [s[8], t])
		if i % 50 == 0: ahora.append(op.ahora(obj, av))
		p_ant = av["p"]
	var fin: String = "roto" if choque != null else v["final"]
	op.final(fin, av, { "bateria": float(v["bateria"]) })
	if fin == "aterrizado": marcar.call("aterrizar", "ok")
	for k in orden:
		if obj[k]["estado"] == "curso": obj[k]["estado"] = "ok" if fin == "aterrizado" else "mal"
	for k in orden:
		if obj[k]["estado"] == "pend": obj[k]["estado"] = "mal"
	var r := {}
	for k in orden: r[k] = obj[k]["estado"] + " | " + obj[k]["texto"]
	return { "choque": choque, "objetivos": r, "avisos": avisos, "ahora": ahora }

func _initialize() -> void:
	var V = JSON.parse_string(FileAccess.get_file_as_string("res://pruebas/referencia_operaciones_js.json"))
	print("Operaciones: los mismos vuelos que en el navegador")
	for v in V:
		var g := _vuelo(v); var w: Dictionary = v["web"]; var dif := []
		if g["choque"] != w["choque"]: dif.append("choque %s / %s" % [g["choque"], w["choque"]])
		for k in w["objetivos"]:
			if g["objetivos"].get(k, "") != w["objetivos"][k]: dif.append("%s: '%s' / '%s'" % [k, g["objetivos"].get(k, ""), w["objetivos"][k]])
		for i in maxi(g["avisos"].size(), w["avisos"].size()):
			var a: String = g["avisos"][i] if i < g["avisos"].size() else "(nada)"; var b: String = w["avisos"][i] if i < w["avisos"].size() else "(nada)"
			if a != b: dif.append("aviso %d: '%s' / '%s'" % [i, a, b]); break
		for i in maxi(g["ahora"].size(), w["ahora"].size()):
			var a: String = g["ahora"][i] if i < g["ahora"].size() else "(nada)"; var b: String = w["ahora"][i] if i < w["ahora"].size() else "(nada)"
			if a != b: dif.append("ahora %d: '%s' / '%s'" % [i, a, b]); break
		_ok(v["nombre"], dif.is_empty(), "(%d avisos)" % g["avisos"].size() if dif.is_empty() else "\n      " + "\n      ".join(dif))
	print("Las operaciones no son entrenamientos:")
	_ok("el DJI tiene sus 6 entrenamientos", Escenarios.misiones_de("dron").size() == 6, str(Escenarios.misiones_de("dron")))
	_ok("y 6 operaciones", Escenarios.operaciones().size() == 6, str(Escenarios.operaciones()))
	print("RESULTADO: " + ("todo igual" if fallos == 0 else "%d fallos" % fallos))
	quit(1 if fallos else 0)
