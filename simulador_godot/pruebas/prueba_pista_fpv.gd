extends SceneTree
## Prueba de que los entrenamientos del dron FPV (PistaFpv) son los mismos en los dos simuladores.
## pruebas/referencia_pista_fpv_js.json trae vuelos de prueba por las 6 misiones FPV de escenarios.js (con aciertos,
## fallos y choques; posiciones dadas, sin fisica) y lo que dice de cada uno la clase PistaFpv de simulador/js/pista_fpv.js
## en el navegador (la genera pruebas/generar_referencia_pista_fpv.py). Aqui se repiten con pista_fpv.gd y se comparan
## los objetivos, los avisos, el choque y la linea "Ahora" del panel. Comprueba tambien que cada vehiculo tiene sus
## entrenamientos (escenarios.js: "vehiculos").
## Uso (desde la carpeta del repositorio):
##   herramientas/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path simulador_godot --script res://pruebas/prueba_pista_fpv.gd

const D2R := PI / 180.0
var fallos := 0

func _ok(nombre: String, cond: bool, detalle := "") -> void:
	if not cond: fallos += 1
	print("  %s %s %s" % ["OK " if cond else "MAL", nombre, detalle])

func _vuelo(v: Dictionary) -> Dictionary:
	var E: Dictionary = Escenarios.datos()[v["mision"]]; var obj := {}; var orden := []
	for o in E["objetivos"]: obj[o[0]] = { "texto": o[1], "estado": "curso" if o[0] in ["modo", "bateria", "bajo4", "altura13"] else "pend" }; orden.append(o[0])
	var marcar := func(k: String, e: String) -> void:
		if obj.has(k) and obj[k]["estado"] != "mal": obj[k]["estado"] = e
	var pf := PistaFpv.new(E["pista_fpv"], marcar); var avisos := []; var ahora := []
	var p_ant = null; var av := {}; var choque = null
	var modo: String = v["modo"] if v["modo"] != null else E["pista_fpv"]["modo"]
	var est: Array = v["estados"]
	for i in est.size():
		var s: Array = est[i]
		av = { "p": [s[0], s[1], -s[2]], "q": Cuat.desde_euler(0, 0, s[3] * D2R), "estado": "volando", "posado": s[4] != 0, "despegado": s[5] != 0, "armado": true, "t": s[6] }
		if choque != null: continue
		if p_ant != null:
			for t in pf.paso(p_ant, av, 0.05, { "modo": modo, "critica": false }): avisos.append("%.2f %s" % [s[6], t])
		if pf.choque != "": choque = pf.choque
		if i % 100 == 0: ahora.append(pf.ahora(obj, av))
		p_ant = av["p"]
	var fin: String = "roto" if choque != null else v["final"]
	if fin == "aterrizado": pf.final(fin, av); marcar.call("aterrizar", "ok")
	for k in orden:
		if obj[k]["estado"] == "curso": obj[k]["estado"] = "ok" if fin == "aterrizado" else "mal"
	for k in orden:
		if obj[k]["estado"] == "pend": obj[k]["estado"] = "mal"
	var r := {}
	for k in orden: r[k] = obj[k]["estado"]
	return { "choque": choque, "objetivos": r, "avisos": avisos, "ahora": ahora }

func _initialize() -> void:
	var V = JSON.parse_string(FileAccess.get_file_as_string("res://pruebas/referencia_pista_fpv_js.json"))
	print("Pista FPV: los mismos vuelos que en el navegador")
	for v in V:
		var g := _vuelo(v); var w: Dictionary = v["web"]
		var dif := []
		if g["choque"] != w["choque"]: dif.append("choque %s / %s" % [g["choque"], w["choque"]])
		if JSON.stringify(g["objetivos"]) != JSON.stringify(w["objetivos"]): dif.append("objetivos %s / %s" % [g["objetivos"], w["objetivos"]])
		for i in maxi(g["avisos"].size(), w["avisos"].size()):
			var a: String = g["avisos"][i] if i < g["avisos"].size() else "(nada)"; var b: String = w["avisos"][i] if i < w["avisos"].size() else "(nada)"
			if a != b: dif.append("aviso %d: '%s' / '%s'" % [i, a, b]); break
		for i in maxi(g["ahora"].size(), w["ahora"].size()):
			var a: String = g["ahora"][i] if i < g["ahora"].size() else "(nada)"; var b: String = w["ahora"][i] if i < w["ahora"].size() else "(nada)"
			if a != b: dif.append("ahora %d: '%s' / '%s'" % [i, a, b]); break
		_ok(v["nombre"], dif.is_empty(), "(%d avisos)" % g["avisos"].size() if dif.is_empty() else "\n      " + "\n      ".join(dif))
	print("Entrenamientos de cada vehiculo:")
	var de := func(veh: String) -> Array: return Escenarios.misiones_de(veh)
	_ok("avion: los 9 de siempre", de.call("avion").size() == 9, str(de.call("avion")))
	_ok("dron comercial: 6 (sin viento cruzado, emergencia ni aterrizaje guiado)", de.call("dron").size() == 6 and not "emergencia" in de.call("dron"), str(de.call("dron")))
	_ok("FPV: solo los 6 suyos", de.call("fpv") == ["fpv_estacionario", "fpv_caja", "fpv_slalom", "fpv_circuito", "fpv_acro", "fpv_tecnica"], str(de.call("fpv")))
	print("RESULTADO: " + ("todo igual" if fallos == 0 else "%d fallos" % fallos))
	quit(1 if fallos else 0)
