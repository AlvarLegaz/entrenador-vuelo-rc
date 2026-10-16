extends SceneTree
## Prueba de los trabajos de reconocimiento (op_rec_*) en el simulador Godot, la misma que
## pruebas/prueba_reconocimiento_web.py en el navegador, con los tres vehiculos que los pueden volar: el Grajo MX-2 (morro
## fijo y orientable), el Poli-1 y el Entrenador 1. Para cada uno: el trabajo sale con el elegido desde Los Halcones, con
## los camiones sorteados y su motor caliente; se lanza (de cara al viento); el avion puesto a unos cientos de metros del
## objetivo, mirandolo (los aviones y el morro fijo, apuntando con el avion; la torreta, fijada en el punto), y la foto (F)
## o la vigilancia; y la vuelta del Grajo, con la toma en perdida.
## Con ventana (sin --headless) y --fotos=<prefijo>, guarda capturas de la camara 3 (con la mira de a bordo).
## Uso (desde la carpeta del repositorio):
##   herramientas/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path simulador_godot --script res://pruebas/prueba_reconocimiento.gd
##   herramientas/godot/Godot_v4.7.2-stable_win64_console.exe --path simulador_godot --resolution 1280x760 --script res://pruebas/prueba_reconocimiento.gd -- --fotos=<prefijo>

const D2R := PI / 180
const DT := 1.0 / 500
var fallos := 0
var p
var prefijo := ""

func _ok(nombre: String, cond: bool, detalle := "") -> void:
	if not cond: fallos += 1
	print("  %s %s %s" % ["OK " if cond else "MAL", nombre, detalle])

func _estados() -> Dictionary:
	var o := {}
	for k in p.ev.obj: o[k] = p.ev.obj[k]["estado"]
	return o

## El trabajo m con el vehiculo a (y el morro del Grajo), hasta que esta en mano; y lanzado (PREP y LANZAR de la web).
func _preparar(m: String, a: String, morro := "fijo") -> Dictionary:
	p.aj["morro"] = { "GRAJO": morro }                  # solo en memoria: la bateria guarda y restaura los datos del usuario
	p.op_vehiculo[m] = a; p.volar_operacion(m)
	for k in 600:
		await process_frame
		if p.pantalla_actual == "" and p.ev != null and p.ev.op != null and not p.av.is_empty(): break
	p.pantalla_actual = "prueba"
	var c: Dictionary = p._casa(); var VV: Array = p.ev.op.d.get("vehiculos", [])
	var motores: int = p.ev.op.termicos.filter(func(o): return o["tipo"] == "motor").size()
	_ok("%s sale con %s%s desde Los Halcones" % [m, a, (" (morro %s)" % morro) if a == "GRAJO" else ""], p.sesion["avion"] == a and p.av["estado"] == "en mano"
		and Vector2(p.av["p"][0] - c["N"], p.av["p"][1] - c["E"]).length() < 5 and (p.morro_de(a) == morro if a == "GRAJO" else p.morro_de(a) == null), "%s %s" % [p.sesion["avion"], p.av["estado"]])
	_ok("  un motor caliente por camion", motores == VV.size() and motores > 0, "%d camiones" % VV.size())
	var ah: String = p.ev.op.ahora(p.ev.obj, p.av); _ok("  'Ahora': lanzarlo", "lánzalo" in ah, ah)
	p.lanzar()
	if not p.es_uav(): p.av["gases"] = 1.0
	var n := 0; var s := 25.0 if p.es_uav() else 6.0
	while n < int(s / DT) and p.av["estado"] == "volando": p.paso(DT); n += 1
	_ok("  lanzado y volando", p.av["estado"] == "volando" and float(p.av.get("agl", 0.0)) > (15.0 if a == "GRAJO" else 2.0), "%s agl %.1f %s" % [p.av["estado"], float(p.av.get("agl", 0.0)), String(p.vuelo["final"]) if p.vuelo != null and p.vuelo.get("final") != null else ""])
	return { "veh": VV, "con": p.ev.op.d.get("conVehiculo", []) }

## El avion a "dist" m del punto (N, E) hacia "ang" (rad), a h m sobre el suelo, mirandolo (JUNTO de la web); s segundos
## quieto ahi y, con foto, la foto (F).
func _junto(N: float, E: float, dist: float, h: float, ang: float, s: float, foto: bool, cam := 0) -> Dictionary:
	var av: Dictionary = p.av; var H: float = p.ent.altura(N, E); var pn := N + dist * cos(ang); var pe := E + dist * sin(ang); var up: float = p.ent.altura(pn, pe) + h
	var y := atan2(E - pe, N - pn); var g := atan2(H + 1.5 - up, dist); var fijo: bool = p.es_uav() and p.morro_de(p.sesion["avion"]) == "fijo"
	var pt := (g - float(DatosComunes.avion(p.sesion["avion"])["malla"]["cam_fija"]["frontal"][1]) * D2R) if fijo else (0.0 if p.es_uav() else g)
	var v0 := 18.0 if p.es_uav() else 13.0
	var pon := func() -> void:
		av["p"] = [pn, pe, -up]; av["q"] = Cuat.desde_euler(0, pt, y); av["v"] = Cuat.rot(av["q"], [v0, 0.0, 0.0]); av["w"] = [0.0, 0.0, 0.0]
	if p.piloto != null and (p.piloto.modo == "LANZAMIENTO" or p.piloto.modo == "MANUAL"): p.uav_poner("CRUCERO")
	if p.es_uav() and not fijo: p.UAV["fijo"] = [N, E, H + 1.5]
	pon.call(); p.hud.toast.text = ""
	var avisos := []
	for k in int(s / DT):
		p.paso(DT); pon.call()
		if p.es_uav(): p.mover_torreta(DT)
		if p.hud.toast.text != "" and (avisos.is_empty() or avisos[-1] != p.hud.toast.text): avisos.append(String(p.hud.toast.text))
	if cam > 0: await _captura(cam)
	if foto:
		if p.es_uav(): p.uav_foto()
		else: p.avion_foto()
		avisos.append(String(p.hud.toast.text))
	return { "T": avisos, "hechos": (p.ev.op.hechos as Array).duplicate(), "vig": p.ev.op.vig, "ahora": p.ev.op.ahora(p.ev.obj, av), "obj": _estados() }

func _captura(cam: int) -> void:
	if prefijo == "": return
	p.camara = cam; p.pantalla_actual = ""; p.pausado = true
	for k in 6:
		p.avion3d.actualizar(p.av); await process_frame
	p.pantalla_actual = "prueba"; p.pausado = false
	root.get_texture().get_image().save_png("%s_%s_%s.png" % [prefijo, p.sesion["escenario"], p.sesion["avion"]])

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--fotos=") and DisplayServer.get_name() != "headless": prefijo = a.substr(8)
	p = load("res://escenas/principal.tscn").instantiate(); root.add_child(p)
	await create_timer(1.0).timeout
	# ---- itinerario: el Grajo (fijo), el Poli-1 y el Entrenador 1 ----
	for a in ["GRAJO", "G1", "E3"]:
		var r: Dictionary = await _preparar("op_rec_itinerario", a); var con: Array = (r["con"] as Array).map(func(x): return int(x))
		_ok("  dos de los cuatro puntos con camion", con.size() == 2, str(con))
		var PQ: Array = Escenarios.datos()["op_rec_itinerario"]["operacion"]["recon"]["puntos"]
		var x: Dictionary = await _junto(PQ[0]["n"], PQ[0]["e"], 450, 100, PI, 0.5, true)
		_ok("  a 450 m: demasiado lejos", x["T"].any(func(t): return "demasiado lejos" in t), str(x["T"]))
		for i in PQ.size():
			x = await _junto(PQ[i]["n"], PQ[i]["e"], 200, 100, PI, 0.5, true, 3 if i == 0 else 0)
			var hay := con.has(i)
			_ok("  foto del punto %d (%s)" % [i + 1, "con camion" if hay else "sin camion"], x["hechos"][i] and x["T"].any(func(t): return ("HAY UN VEHÍCULO" if hay else "sin vehículos") in t), str(x["T"]))
		_ok("  puntos, vehiculos y tiempo ok", ["puntos", "vehiculos", "tiempo"].all(func(k): return x["obj"][k] == "ok"), str(x["obj"]))
		_ok("  'Ahora': vuelve", "vuelve" in x["ahora"], x["ahora"])
		if a != "GRAJO": continue                          # el aterrizaje a mano de los aviones ya lo prueban sus entrenamientos
		var c: Dictionary = p._casa(); var vto: Dictionary = p.ent.viento; var desde: float = float(vto["rumbo"]) + PI if float(vto["base"]) > 0.2 else 0.0
		var pn: float = c["N"] + 500 * cos(desde); var pe: float = c["E"] + 500 * sin(desde)
		p.av["p"] = [pn, pe, -(p.ent.altura(pn, pe) + 60)]; p.av["q"] = Cuat.desde_euler(0, 0, desde + PI); p.av["v"] = Cuat.rot(p.av["q"], [14.0, 0.0, 0.0]); p.av["w"] = [0.0, 0.0, 0.0]
		p.uav_poner("CRUCERO"); p.uav_poner("ATERRIZAJE"); var n := 0
		while p.av["estado"] == "volando" and n < int(400 / DT): p.paso(DT); n += 1
		var fin: String = String(p.vuelo["final"]) if p.vuelo != null else String(p.av["estado"])
		_ok("  vuelta y aterrizaje", fin == "aterrizado", fin)
		_ok("  con la toma en perdida, en casa", p.ev.obj["casa"]["estado"] == "ok" and p.ev.obj["minima"]["estado"] == "ok", p.ev.obj["casa"]["texto"] + " / " + p.ev.obj["minima"]["estado"])
	# ---- vigilancia: el Grajo con la torreta y el Poli-1 ----
	for am in [["GRAJO", "orientable"], ["G1", "fijo"]]:
		var r: Dictionary = await _preparar("op_rec_vigilancia", am[0], am[1]); var vn: float = r["veh"][0][0]; var ve: float = r["veh"][0][1]
		var x: Dictionary = await _junto(vn, ve, 260, 120, 2.0, 50, true)
		_ok("  foto antes de acabar la vigilancia", x["T"].any(func(t): return "la vigilancia sigue" in t), str(x["T"]))
		x = await _junto(vn, ve, 400, 120, 2.0, 45, false, 3)
		_ok("  vigilancia completa", x["obj"]["vigilar"] == "ok" and x["T"].any(func(t): return "Vigilancia completa" in t), str(x["T"]) + " vig=%.1f" % x["vig"])
		x = await _junto(vn, ve, 200, 120, 2.0, 0.5, true); _ok("  foto del vehiculo", x["obj"]["foto"] == "ok", str(x["T"]))
		_ok("  sin que le oigan", x["obj"]["ruido"] == "curso", x["obj"]["ruido"])
		x = await _junto(vn, ve, 150, 50, 2.0, 0.5, false); _ok("  bajo y cerca: le oyen", x["obj"]["ruido"] == "mal" and x["T"].any(func(t): return "oír" in t), str(x["T"]))
	# ---- busqueda: el Entrenador 1 y el Grajo (fijo) ----
	for a in ["E3", "GRAJO"]:
		var r: Dictionary = await _preparar("op_rec_busqueda", a); var vn: float = r["veh"][0][0]; var ve: float = r["veh"][0][1]
		var x: Dictionary = await _junto(vn, ve, 150, 110, 0.7, 0.5, true, 3)
		_ok("  camion localizado con poco error", x["obj"]["localizar"] == "ok" and x["obj"]["posicion"] == "ok", str(x["T"]))
	print("RESULTADO: ", "todo bien" if fallos == 0 else "%d fallos" % fallos)
	quit(1 if fallos else 0)
