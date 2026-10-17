extends SceneTree
## Prueba de que el cuadricoptero Mini Dron HQ (ModeloCuadricoptero, con su controlador de vuelo) es el mismo en los dos
## simuladores. simulador_godot/Tests/referencia_cuadricoptero_js.json son trazas del navegador (clase ModeloCuadricoptero de
## datos/vehiculos/DJI_MINI.js) con un guion de mandos: armar, subir con vz, quieto con 4 m/s de viento, a tope
## adelante en los modos N, S y C, frenar, guinada y gimbal, bajar con la palanca abajo hasta aterrizar, despegue
## automatico, alejarse subiendo y volver a casa (RTH) hasta aterrizar; con los datos de diseno y configurado (masa,
## temperatura, empuje, resistencia) en dificultad facil. Aqui se repite el mismo guion (el de
## simulador_godot/Tests/generar_referencia_cuadricoptero.py, que genera la referencia) y se compara. Comprueba tambien que la malla
## que construye DatosComunes es la de JS (la referencia lleva un resumen) y que la lista de aviones incluye el dron.
## Uso (desde la carpeta del repositorio):
##   herramientas/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path simulador_godot --script res://Tests/prueba_cuadricoptero.gd

const DT := 0.002
const D2R := PI / 180.0

## Contacto con el suelo plano (altura 0): Entorno.contacto_suelo sin mundo ni mar (como en el guion de JS).
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

func _en(s0: float, s1: float, i: int) -> bool:
	return i >= s0 * 500 and i < s1 * 500

func _traza(conf: Dictionary, facil: bool, ent: Entorno, VIENTO: Array, FIN: int) -> Dictionary:
	var m := ModeloCuadricoptero.new(DatosComunes.avion("DJI_MINI"))
	if not conf.is_empty(): m.configurar(conf)
	m.facil = facil; ent.facil = facil
	var a := m.estado_inicial()
	var mando := { "pitch": 0.0, "yaw": 0.0, "guinada": 0.0, "vz": 0.0, "gimbal": 0.0, "trim": 0.0 }
	var muestras := []; var finales := []
	for i in FIN * 500 + 1:
		var t := i * DT
		if i == 250: m.lanzar(a)
		if i == 5000: m.modo = "N"
		if i == 10000: m.modo = "S"
		if i == 15000: m.modo = "C"
		if i == 23000: m.modo = "N"
		if i == 33000: m.despegar(a)
		if i == 39000: m.volver_a_casa(a)
		mando["vz"] = 0.8 if _en(1, 6, i) else (-1.0 if _en(46, 66, i) else (1.0 if _en(70, 76, i) else 0.0))
		mando["pitch"] = -1.0 if _en(10, 16, i) or _en(20, 26, i) or _en(30, 36, i) or _en(70, 76, i) else 0.0
		mando["yaw"] = 0.5 if _en(30, 36, i) else (0.3 if _en(70, 76, i) else 0.0)
		mando["guinada"] = 1.0 if _en(40, 44, i) else 0.0
		mando["gimbal"] = -1.0 if _en(40, 41, i) else (0.6 if _en(41, 41.5, i) else 0.0)
		if i % 250 == 0:
			var c: Dictionary = a["cmd"]
			muestras.append({ "t": t, "p": a["p"].duplicate(), "v": a["v"].duplicate(), "w": a["w"].duplicate(), "q": a["q"].duplicate(),
							  "cmd": [c["adelante"], c["derecha"], c["guinada"], c["vz"]], "T": a["T"], "Wh": a["Wh"], "gases": a["gases"], "gimbal": a["gimbal"],
							  "estado": a["estado"], "posado": a["posado"], "despegado": a["despegado"], "rth": a["rth"]["fase"] if a["rth"] else "",
							  "hold": a["hold"] != null, "auto": a["despegueAuto"] })
		m.servos(a, mando, DT)
		a["agl"] = -a["p"][2]
		var viento := ent.viento_a(VIENTO, a["agl"])
		a["pg"] = 0.03 * sin(3 * t)
		if a["estado"] != "volando": continue
		var vn := m.paso(a, viento, DT)
		var final := _contacto(ent, a, vn)
		if final != "":
			a["estado"] = "roto" if final.begins_with("roto") else ("aterrizado" if final == "aterrizado" else "terminado")
			a["v"] = [0.0, 0.0, 0.0]; a["w"] = [0.0, 0.0, 0.0]; a["rpm"] = 0.0
			finales.append({ "t": t, "final": final, "N": a["p"][0], "E": a["p"][1] })
	ent.facil = false
	return { "muestras": muestras, "finales": finales }

func _e(x: float) -> String:
	if x == 0: return "0"
	var ex := floori(log(x) / log(10.0))
	return "%.1fe%d" % [x / pow(10, ex), ex]

func _dif(x, y) -> float:
	if x is Array:
		var d := 0.0
		for k in x.size(): d = maxf(d, absf(float(x[k]) - float(y[k])))
		return d
	return absf(float(x) - float(y))

func _init() -> void:
	var ref: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://Tests/referencia_cuadricoptero_js.json"))
	var ent := Entorno.new()
	var fallos := 0
	# datos y malla
	var ids := DatosComunes.aviones(); var A := DatosComunes.avion("DJI_MINI"); var K: Dictionary = A.get("malla", {})
	var ok_datos: bool = ids.has("DJI_MINI") and A.get("tipo", "") == "cuadricoptero" and K.has("fuselaje") and K.has("estab") and K.get("helices", []).size() == 4 and K.get("luces", []).size() == 3
	var rm: Dictionary = ref.get("malla", {})
	if ok_datos and not rm.is_empty():
		for parte in ["fuselaje", "estab"]:
			var v: Array = K[parte]["v"]; var ii: Array = K[parte]["i"]; var sv := 0.0; var si := 0
			for x in v: sv += absf(x)
			for x in ii: si += int(x)
			if v.size() != int(rm[parte]["nv"]) or ii.size() != int(rm[parte]["ni"]) or absf(sv - rm[parte]["suma_v"]) > 1e-9 or si != int(rm[parte]["suma_i"]): ok_datos = false
		if _dif(K["helices"].reduce(func(acc, h): return acc + h, []), rm["helices"]) > 1e-12: ok_datos = false
	if not ok_datos: fallos += 1
	print("Datos del dron: aviones() = %s; malla fuselaje %d, estab %d vertices, %d rotores, %d luces%s  %s" % [", ".join(ids),
		K.get("fuselaje", {}).get("v", []).size() / 3, K.get("estab", {}).get("v", []).size() / 3, K.get("helices", []).size(), K.get("luces", []).size(),
		"" if not rm.is_empty() else " (la referencia no trae la malla)", "OK" if ok_datos else "MAL"])
	print("Cuadricoptero: diferencia maxima con el navegador (posicion m, velocidad m/s, giro rad/s, actitud, consignas, gimbal grados, Wh, empuje N)")
	for nombre in ["normal", "config_facil"]:
		var conf := {} if nombre == "normal" else { "masa_kg": 0.27, "temperatura": 30.0, "empuje_gf": 560.0, "resistencia": 1.2 }
		var g := _traza(conf, nombre != "normal", ent, ref["VIENTO"], int(ref["FIN"]))
		var r: Array = ref[nombre]["muestras"]; var gm: Array = g["muestras"]
		var dmax := {}; var t_primer := -1.0; var discretos := 0; var t_disc := -1.0
		for k in r.size():
			for c in ["p", "v", "w", "q", "cmd", "gimbal", "Wh", "T"]:
				var d := _dif(gm[k][c], r[k][c])
				dmax[c] = maxf(dmax.get(c, 0.0), d)
				if d > 1e-6 and t_primer < 0: t_primer = r[k]["t"]
			for c in ["estado", "posado", "despegado", "rth", "hold", "auto"]:
				if gm[k][c] != r[k][c]:
					discretos += 1
					if t_disc < 0: t_disc = r[k]["t"]
		# finales (aterrizajes): mismos, en el mismo paso y en el mismo sitio
		var fr: Array = ref[nombre]["finales"]; var fg: Array = g["finales"]; var ok_fin := fr.size() == fg.size()
		var txt_fin := []
		for k in mini(fr.size(), fg.size()):
			if fg[k]["final"] != fr[k]["final"] or absf(fg[k]["t"] - fr[k]["t"]) > 1e-9 or absf(fg[k]["N"] - fr[k]["N"]) > 1e-3 or absf(fg[k]["E"] - fr[k]["E"]) > 1e-3: ok_fin = false
			txt_fin.append("%s a %.1f s (N %.1f, E %.1f)" % [fg[k]["final"], fg[k]["t"], fg[k]["N"], fg[k]["E"]])
		var ok: bool = dmax["p"] < 1e-3 and dmax["q"] < 1e-6 and discretos == 0 and ok_fin
		if not ok: fallos += 1
		print("  %-12s %s  p %s  v %s  w %s  q %s  consignas %s  gimbal %s  Wh %s  T %s  estados distintos %d%s%s" % [nombre, "OK " if ok else "MAL",
			_e(dmax["p"]), _e(dmax["v"]), _e(dmax["w"]), _e(dmax["q"]), _e(dmax["cmd"]), _e(dmax["gimbal"]), _e(dmax["Wh"]), _e(dmax["T"]), discretos,
			"" if t_primer < 0 else "  (primera diferencia > 1e-6 en t=%.1f s)" % t_primer, "" if t_disc < 0 else "  (primer estado distinto en t=%.1f s)" % t_disc])
		print("               %s%s" % ["; ".join(txt_fin), "" if ok_fin else "   <- distinto del navegador: %s" % str(fr)])
	print("RESULTADO: " + ("todo igual" if fallos == 0 else "%d casos distintos" % fallos))
	quit(1 if fallos else 0)
