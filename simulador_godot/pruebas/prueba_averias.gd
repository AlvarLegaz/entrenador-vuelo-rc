extends SceneTree
## Prueba de que las averias (scripts/desgaste.gd) son las mismas que las del navegador (simulador/js/desgaste.js):
## pruebas/referencia_averias_js.json (de pruebas/generar_referencia_averias.py) trae trazas de vuelo con cada averia
## (Mini Dron HQ, Inspector HQ-3T, FPV y aviones: helice, motor, sensores, bateria, servo y bisagra), el desgaste de 14
## vuelos seguidos de cada vehiculo (con su azar con semilla), lo que dice el Taller (revisiones, reparaciones y libro)
## y el catalogo de averias. Aqui se repite el mismo guion y se compara.
##   herramientas/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path simulador_godot --script res://pruebas/prueba_averias.gd

const DT := 0.002
const D2R := PI / 180.0
var fallos := 0

func _ok(nombre: String, cond: bool, detalle := "") -> void:
	if not cond: fallos += 1
	print("  %s %s %s" % ["OK " if cond else "MAL", nombre, detalle])

func _contacto(ent: Entorno, av: Dictionary, vn: Array) -> String:
	var p: Array = av["p"]
	if -p[2] > 0: return ""
	p[2] = -0.0
	var e := Cuat.euler(av["q"]); var vz: float = -vn[2]; var vel := sqrt(vn[0] * vn[0] + vn[1] * vn[1]); var L := ent.limites
	if vz < -L["descenso_ms"]: return "roto (demasiado descenso)"
	if absf(e[0]) > L["alabeo_grados"] * D2R: return "roto (ala en el suelo)"
	if vel > L["vel_suelo_ms"]: return "roto (demasiada velocidad)"
	if absf(e[1]) > L["cabeceo_grados"] * D2R: return "roto (morro en el suelo)"
	return "aterrizado"

func _en(s0: float, s1: float, i: int) -> bool: return i >= s0 * 500 and i < s1 * 500

func _modelo(id: String):
	var A := DatosComunes.avion(id)
	if A.get("tipo", "") == "fpv": return ModeloFPV.new(A)
	if A.get("tipo", "") == "cuadricoptero": return ModeloCuadricoptero.new(A)
	return ModeloAvion.new(A)

func _traza(caso: Dictionary, ent: Entorno, VIENTO: Array) -> Dictionary:
	var A := DatosComunes.avion(caso["avion"]); var k := Desgaste.clase(A); var m = _modelo(caso["avion"])
	var est := Desgaste.nuevo()
	for a in caso["averias"]:
		var x: Dictionary = { "origen": "profesor", "fecha": "" }; x.merge(a, true)
		if x.has("n"): x["n"] = int(x["n"])
		est["averias"].append(x)
	if caso.has("salud"): est["bateria"]["salud"] = float(caso["salud"])
	Desgaste.aplicar(m, est)
	var a: Dictionary = m.estado_inicial(); var mando := { "pitch": 0.0, "yaw": 0.0, "guinada": 0.0, "vz": 0.0, "gimbal": 0.0, "trim": 0.0 }
	var FIN := 40 if k == "cuad" else (20 if k == "fpv" else 25)
	var muestras := []; var finales := []
	for i in FIN * 500 + 1:
		var t := i * DT
		if k == "cuad":
			if i == 250: m.lanzar(a)
			mando["vz"] = 0.8 if _en(1, 6, i) else 0.0; mando["pitch"] = -1.0 if _en(10, 14, i) else 0.0
			mando["yaw"] = 0.5 if _en(16, 18, i) else 0.0; mando["guinada"] = 1.0 if _en(20, 22, i) else 0.0
		elif k == "fpv":
			if i == 250: m.lanzar(a)
			if i >= 250: a["gases"] = 0.62
			mando["yaw"] = 0.3 if _en(8, 9, i) else 0.0; mando["pitch"] = -0.3 if _en(10, 12, i) else 0.0
		else:
			if i == 0:
				m.lanzar(a); a["asim"] = 0.37; a["p"] = [0.0, 0.0, -80.0]; a["q"] = Cuat.desde_euler(0.05, 0.03, 0.2); a["v"] = [12.0, 0.3, 0.1]
				mando["trim"] = float(m.compensador_grados)
			a["gases"] = 0.8; mando["pitch"] = 0.4 * sin(0.9 * t); mando["yaw"] = 0.6 * sin(1.7 * t)
		if i % 250 == 0:
			var b = a.get("bat")
			muestras.append({ "t": t, "p": a["p"].duplicate(), "v": a["v"].duplicate(), "w": a["w"].duplicate(), "q": a["q"].duplicate(), "Wh": a["Wh"], "estado": a["estado"],
							  "V": b["V"] if b != null else 0.0, "celdas": (b["celdas"] as Array).duplicate() if b != null else [], "avisoBat": String(a.get("avisoBat", "")) })
		m.servos(a, mando, DT)
		a["agl"] = -a["p"][2]
		var viento := ent.viento_a(VIENTO, a["agl"])
		a["pg"] = 0.03 * sin(3 * t)
		if a["estado"] != "volando": continue
		Desgaste.antes_paso(m, a)
		var vn: Array = m.paso(a, viento, DT)
		Desgaste.despues_paso(m, a, DT)
		var final := _contacto(ent, a, vn)
		if final != "":
			a["estado"] = "roto" if final.begins_with("roto") else ("aterrizado" if final == "aterrizado" else "terminado")
			a["v"] = [0.0, 0.0, 0.0]; a["w"] = [0.0, 0.0, 0.0]; a["rpm"] = 0.0
			finales.append({ "t": t, "final": final, "N": a["p"][0], "E": a["p"][1] })
	return { "muestras": muestras, "finales": finales }

func _e(x: float) -> String:
	if x == 0: return "0"
	if is_inf(x): return "inf"
	var ex := floori(log(x) / log(10.0))
	return "%.1fe%d" % [x / pow(10, ex), ex]

func _dif(x, y) -> float:
	if x is Array:
		if (x as Array).size() != (y as Array).size(): return INF
		var d := 0.0
		for k in x.size(): d = maxf(d, absf(float(x[k]) - float(y[k])))
		return d
	return absf(float(x) - float(y))

func _initialize() -> void:
	var R: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://pruebas/referencia_averias_js.json"))
	var ent := Entorno.new()
	print("Vuelos con averias, igual que en el navegador (posicion, velocidad, giro, actitud, Wh, tension y celdas):")
	for caso in R["CASOS"]:
		var g := _traza(caso, ent, R["VIENTO"]); var r: Array = R["trazas"][caso["id"]]["muestras"]; var gm: Array = g["muestras"]
		var dmax := 0.0; var disc := 0; var t_primer := -1.0
		for k in mini(r.size(), gm.size()):
			for c in ["p", "v", "w", "q", "Wh", "V", "celdas"]:
				var d := _dif(gm[k][c], r[k][c]); dmax = maxf(dmax, d)
				if d > 1e-6 and t_primer < 0: t_primer = float(r[k]["t"])
			if gm[k]["estado"] != r[k]["estado"] or gm[k]["avisoBat"] != r[k]["avisoBat"]: disc += 1
		var fr: Array = R["trazas"][caso["id"]]["finales"]; var fg: Array = g["finales"]
		var ok_fin := fr.size() == fg.size()
		for k in mini(fr.size(), fg.size()):
			if fr[k]["final"] != fg[k]["final"] or absf(float(fr[k]["t"]) - float(fg[k]["t"])) > 1e-9: ok_fin = false
		_ok(caso["id"], r.size() == gm.size() and dmax < 1e-6 and disc == 0 and ok_fin, "dif max %s%s%s" % [_e(dmax), (" (desde t=%.1f s)" % t_primer) if t_primer >= 0 else "", "" if disc == 0 else ", %d estados distintos" % disc])
	print("Desgaste de 14 vuelos seguidos de cada vehiculo (azar con semilla), el Taller y el catalogo:")
	for id in R["desgaste"]:
		var A := DatosComunes.avion(id); var est := Desgaste.nuevo(); est["horas"] = 0.8
		var bien := true; var detalle := ""
		var pasos: Array = R["desgaste"][id]
		for k in pasos.size():
			var info := { "s": 600.0 + 97 * k, "roto": k % 5 == 3, "bat0": 100.0, "bat1": 7.0 if k % 4 == 2 else 35.0, "tempMax": 61.0 if k % 6 == 4 else 32.0,
						  "semilla": "vuelo-%d-%s" % [k, id], "fecha": "2026-10-16T10:%02d:00Z" % k }
			var nuevas := Desgaste.tras_vuelo(est, A, info)
			var nv := nuevas.map(func(a): return [a["c"], a["tipo"], int(a.get("n", -1)), a["origen"]])
			var P: Dictionary = pasos[k]
			if JSON.stringify(nv) != JSON.stringify((P["nuevas"] as Array).map(func(x): return [x[0], x[1], int(x[2]), x[3]])) or absf(float(est["horas"]) - float(P["horas"])) > 1e-6 \
				or absf(float(est["bateria"]["salud"]) - float(P["salud"])) > 1e-9 or int(est["bateria"]["ciclos"]) != int(P["ciclos"]) or (est["averias"] as Array).size() != int(P["n"]):
				if bien: detalle = "vuelo %d: %s / %s" % [k, str(nv), str(P["nuevas"])]
				bien = false
		_ok(id + ": desgaste", bien, detalle)
		var T: Dictionary = R["taller"][id]
		var rev := {}
		for r in Desgaste.revisiones(A): rev[r[0]] = Desgaste.revisar(est, A, r[0])
		_ok(id + ": revisiones del Taller", JSON.stringify(rev) == JSON.stringify(T["revisiones"]), "" if JSON.stringify(rev) == JSON.stringify(T["revisiones"]) else "%s\n      %s" % [str(rev), str(T["revisiones"])])
		var reps := Desgaste.reparaciones(A)
		_ok(id + ": reparaciones", JSON.stringify(reps) == JSON.stringify(T["reparaciones"]), str(reps.map(func(x): return x[1])))
		var libro := []
		var primera = reps[0][0]; var segunda = reps[1][0]
		if not (est["averias"] as Array).is_empty():
			segunda = reps[0][0]
			for x in reps:
				if (x[2] as Array).has(est["averias"][0]["c"]): segunda = x[0]; break
		for r in [primera, segunda, "bateria"]: libro.append(Desgaste.reparar(est, A, r, "2026-10-16T12:00:00Z"))
		var ok_libro := libro.size() == (T["libro"] as Array).size()
		for k in mini(libro.size(), (T["libro"] as Array).size()):
			var x = libro[k]; var y = T["libro"][k]
			if (x == null) != (y == null): ok_libro = false; continue
			if x == null: continue
			if x["texto"] != y["texto"] or JSON.stringify(x["arreglo"]) != JSON.stringify(y["arreglo"]) or absf(float(x["horas"]) - float(y["horas"])) > 1e-6: ok_libro = false
		var quedan := (est["averias"] as Array).map(func(a): return Desgaste.nombre(a))
		_ok(id + ": reparar y el libro de mantenimiento", ok_libro and JSON.stringify(quedan) == JSON.stringify(T["quedan"]), str(libro.map(func(x): return x["texto"] if x != null else null)))
		var cat := Desgaste.posibles(A).map(func(a): return [a["c"], a["tipo"], int(a.get("n", -1)), a["nombre"]])
		var cr: Array = (R["catalogo"][id] as Array).map(func(x): return [x[0], x[1], int(x[2]), x[3]])
		_ok(id + ": catalogo de averias", JSON.stringify(cat) == JSON.stringify(cr), "%d averias" % cat.size())
	print("RESULTADO: ", "todo igual" if fallos == 0 else "%d fallos" % fallos)
	quit(1 if fallos else 0)
