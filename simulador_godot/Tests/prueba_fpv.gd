extends SceneTree
## Prueba de que el dron FPV (ModeloFPV, con su controlador tipo Betaflight) es el mismo en los dos simuladores.
## simulador_godot/Tests/referencia_fpv_js.json son trazas del navegador (clase ModeloFPV de datos/vehiculos/FPV.js) con un guion de
## mandos: armar, despegar, ANGLE adelante, alabeo y guinada, HORIZON con una vuelta, ACRO con otra, ANGLE con viento,
## caida con poco gas (propwash), bajar hasta posarse y desarmar (aterrizado); con los datos de diseno y configurado
## (masa, temperatura, empuje, resistencia) en dificultad facil; y un choque (desarmado a 20 m). Aqui se repite el mismo
## guion (el de simulador_godot/Tests/generar_referencia_fpv.py, que genera la referencia) y se compara. Comprueba tambien que los
## datos del modelo 3D que lee DatosComunes son los de JS y que la lista de aviones incluye el FPV.
## Uso (desde la carpeta del repositorio):
##   herramientas/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path simulador_godot --script res://Tests/prueba_fpv.gd

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

## Piloto de la altura: gas = 0,31 + 0,05 (hObj - h) - 0,04 vz, entre 0 y 1.
func _sujetar(a: Dictionary, h_obj: float) -> void:
	var vz: float = -Cuat.rot(a["q"], a["v"])[2]
	a["gases"] = maxf(0, minf(1, 0.31 + 0.05 * (h_obj + a["p"][2]) - 0.04 * vz))

## Piloto de la deriva: en ANGLE, inclina contra la velocidad respecto al suelo.
func _frenar(a: Dictionary, mando: Dictionary) -> void:
	var vn := Cuat.rot(a["q"], a["v"]); var yaw: float = Cuat.euler(a["q"])[2]; var cy := cos(yaw); var sy := sin(yaw)
	var vf: float = vn[0] * cy + vn[1] * sy; var vr: float = -vn[0] * sy + vn[1] * cy
	mando["pitch"] = maxf(-0.5, minf(0.5, 0.12 * vf)); mando["yaw"] = maxf(-0.5, minf(0.5, -0.12 * vr))

func _completo(m: ModeloFPV, a: Dictionary, mando: Dictionary, i: int) -> void:
	if i == 250: m.lanzar(a)
	if i == 6500: m.modo = "HORIZON"
	if i == 8000: m.modo = "ACRO"
	if i == 9000: m.modo = "ANGLE"
	if i == 26000: m.desarmar(a)
	mando["pitch"] = -1.0 if _en(6, 9, i) else (-0.7 if _en(16, 16.3, i) else 0.0)
	mando["yaw"] = 0.6 if _en(11, 13, i) else (1.0 if _en(13, 14, i) else (1.0 if _en(16.5, 17.04, i) else 0.0))
	if i >= 12000 and i < 26000: _frenar(a, mando)
	mando["guinada"] = 0.5 if _en(11, 13, i) else (-1.0 if _en(19, 20, i) else 0.0)
	if i < 500: a["gases"] = 0.0
	elif _en(1, 22, i): _sujetar(a, 15)
	elif _en(22, 23.2, i): a["gases"] = 0.1
	elif _en(23.2, 24, i): _sujetar(a, 15)
	elif _en(24, 28, i): _sujetar(a, 8)
	elif i < 26000:
		var vz: float = -Cuat.rot(a["q"], a["v"])[2]
		a["gases"] = 0.0 if a["posado"] else maxf(0, minf(1, 0.31 + 0.1 * (-0.8 - vz)))
	else: a["gases"] = 0.0

func _choque(m: ModeloFPV, a: Dictionary, mando: Dictionary, i: int) -> void:
	if i == 250: m.lanzar(a)
	if i == 2500: m.modo = "ACRO"
	if i == 3000: m.desarmar(a)
	mando["yaw"] = 0.4 if _en(5.2, 5.5, i) else 0.0
	if i < 500: a["gases"] = 0.0
	elif i < 3000: _sujetar(a, 20)
	else: a["gases"] = 0.0

func _traza(conf: Dictionary, facil: bool, guion: Callable, ent: Entorno, VIENTO: Array, FIN: int) -> Dictionary:
	var m := ModeloFPV.new(DatosComunes.avion("FPV"))
	if not conf.is_empty(): m.configurar(conf)
	m.facil = facil; ent.facil = facil
	var a := m.estado_inicial()
	var mando := { "pitch": 0.0, "yaw": 0.0, "guinada": 0.0, "trim": 0.0 }
	var muestras := []; var finales := []
	for i in FIN * 500 + 1:
		var t := i * DT
		guion.call(m, a, mando, i)
		if i % 250 == 0:
			var c: Dictionary = a["cmd"]
			muestras.append({ "t": t, "p": a["p"].duplicate(), "v": a["v"].duplicate(), "w": a["w"].duplicate(), "q": a["q"].duplicate(), "motores": a["motores"].duplicate(),
							  "cmd": [c["alabeo"], c["cabeceo"], c["guinada"]], "gases": a["gases"], "T": a["T"], "Vbat": a["Vbat"], "mAh": a["mAh"], "Wh": a["Wh"],
							  "propwash": a["propwash"], "integ": a["integ"].duplicate(), "estado": a["estado"], "posado": a["posado"], "despegado": a["despegado"],
							  "armado": a["armado"], "modo": m.modo })
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
	var ref: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://Tests/referencia_fpv_js.json"))
	var ent := Entorno.new()
	var fallos := 0
	# datos y modelo 3D
	var ids := DatosComunes.aviones(); var A := DatosComunes.avion("FPV"); var K: Dictionary = A.get("modelo3d", {})
	var suma := _suma_num(K)
	var rm: Dictionary = ref["modelo3d"]
	var ok_datos: bool = ids.has("FPV") and A.get("tipo", "") == "fpv" and K.get("piezas", []).size() == int(rm["piezas"]) and K.get("rotores", []).size() == int(rm["rotores"]) 		and K.get("luces", []).size() == int(rm["luces"]) and absf(suma - rm["suma"]) < 1e-6 * maxf(1.0, absf(suma))
	if not ok_datos: fallos += 1
	print("Datos del FPV: aviones() = %s; modelo 3D %d piezas, %d rotores, %d luces  %s" % [", ".join(ids), K.get("piezas", []).size(), K.get("rotores", []).size(), K.get("luces", []).size(), "OK" if ok_datos else "MAL"])
	# la misma malla que el navegador: vertices y triangulos iguales, area y suma de posiciones con el redondeo de float32
	var C := ModeloFPV3D.mallas(K)
	var mg := { "fija": ModeloFPV3D.resumen(C["fija"]), "palas": ModeloFPV3D.resumen(C["palas"][1]), "palas_inv": ModeloFPV3D.resumen(C["palas"][-1]), "disco": ModeloFPV3D.resumen(C["disco"]) }
	for k in ["fija", "palas", "palas_inv", "disco"]:
		var g: Dictionary = mg[k]; var j: Dictionary = rm["mallas"][k]
		var ok_m: bool = int(g["vertices"]) == int(j["vertices"]) and int(g["triangulos"]) == int(j["triangulos"]) 			and absf(g["area"] - j["area"]) < 1e-5 * j["area"] and absf(g["suma"] - j["suma"]) < 1e-3
		if not ok_m: fallos += 1
		print("Malla %s: %d vertices, %d triangulos, area %.6f m2 (navegador %d, %d, %.6f)  %s" % [k, g["vertices"], g["triangulos"], g["area"], j["vertices"], j["triangulos"], j["area"], "OK" if ok_m else "MAL"])
	print("FPV: diferencia maxima con el navegador (posicion m, velocidad m/s, giro rad/s, actitud, motores, consignas, tension V, mAh, empuje N)")
	var guiones := { "normal": [{}, false, _completo, 55], "config_facil": [{ "masa_kg": 0.72, "temperatura": 32.0, "empuje_gf": 5200.0, "resistencia": 1.3 }, true, _completo, 55],
					 "choque": [{}, false, _choque, 12] }
	for nombre in guiones:
		var G: Array = guiones[nombre]
		var g := _traza(G[0], G[1], G[2], ent, ref["VIENTO"], G[3])
		var r: Array = ref[nombre]["muestras"]; var gm: Array = g["muestras"]
		var dmax := {}; var t_primer := -1.0; var discretos := 0; var t_disc := -1.0
		for k in r.size():
			for c in ["p", "v", "w", "q", "motores", "cmd", "gases", "Vbat", "mAh", "T", "integ", "propwash"]:
				var d := _dif(gm[k][c], r[k][c])
				dmax[c] = maxf(dmax.get(c, 0.0), d)
				if d > 1e-6 and t_primer < 0: t_primer = r[k]["t"]
			for c in ["estado", "posado", "despegado", "armado", "modo"]:
				if gm[k][c] != r[k][c]:
					discretos += 1
					if t_disc < 0: t_disc = r[k]["t"]
		var fr: Array = ref[nombre]["finales"]; var fg: Array = g["finales"]; var ok_fin := fr.size() == fg.size()
		var txt_fin := []
		for k in mini(fr.size(), fg.size()):
			if fg[k]["final"] != fr[k]["final"] or absf(fg[k]["t"] - fr[k]["t"]) > 1e-9 or absf(fg[k]["N"] - fr[k]["N"]) > 1e-3 or absf(fg[k]["E"] - fr[k]["E"]) > 1e-3: ok_fin = false
			txt_fin.append("%s a %.1f s (N %.1f, E %.1f)" % [fg[k]["final"], fg[k]["t"], fg[k]["N"], fg[k]["E"]])
		var ok: bool = r.size() == gm.size() and dmax["p"] < 1e-3 and dmax["q"] < 1e-6 and discretos == 0 and ok_fin
		if not ok: fallos += 1
		print("  %-12s %s  p %s  v %s  w %s  q %s  motores %s  consignas %s  V %s  mAh %s  T %s  estados distintos %d%s%s" % [nombre, "OK " if ok else "MAL",
			_e(dmax["p"]), _e(dmax["v"]), _e(dmax["w"]), _e(dmax["q"]), _e(dmax["motores"]), _e(dmax["cmd"]), _e(dmax["Vbat"]), _e(dmax["mAh"]), _e(dmax["T"]), discretos,
			"" if t_primer < 0 else "  (primera diferencia > 1e-6 en t=%.1f s)" % t_primer, "" if t_disc < 0 else "  (primer estado distinto en t=%.1f s)" % t_disc])
		print("               %s%s" % ["; ".join(txt_fin), "" if ok_fin else "   <- distinto del navegador: %s" % str(fr)])
	print("RESULTADO: " + ("todo igual" if fallos == 0 else "%d casos distintos" % fallos))
	quit(1 if fallos else 0)

## Suma de todos los numeros de un dato JSON (diccionarios y listas anidados).
static func _suma_num(o) -> float:
	if o is float or o is int: return float(o)
	var s := 0.0
	if o is Array:
		for x in o: s += _suma_num(x)
	elif o is Dictionary:
		for x in o.values(): s += _suma_num(x)
	return s
