extends SceneTree
## Prueba del bipode secreto: lo desbloquea (con los tres logros del perfil), lo arranca en el vuelo libre, anda, gira la
## cintura, dispara a un dron diana y guarda capturas (persecucion y puesto de tiro). Escribe en user://simulador.cfg
## (el secreto y el vehiculo): copiar ese fichero antes y restaurarlo despues.
## Uso (necesita ventana):
##   herramientas/godot/Godot_v4.7.2-stable_win64_console.exe --path simulador_godot --script res://Tests/prueba_bipode.gd -- --foto=bipode

var p: Node
var fallos := 0

func _ok(nombre: String, cond: bool, detalle := "") -> void:
	print(("OK   " if cond else "MAL  ") + nombre + ("  " + detalle if detalle != "" else ""))
	if not cond: fallos += 1

func _tecla(k: int, abajo: bool) -> void:
	var e := InputEventKey.new(); e.physical_keycode = k; e.keycode = k; e.pressed = abajo; Input.parse_input_event(e)

func _initialize() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1); args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	p = load("res://escenas/principal.tscn").instantiate(); root.add_child(p)
	while p.aula == null or p.pantallas.is_empty() or not p.pantallas["pAlumno"].visible: await create_timer(0.2).timeout
	p.app_pantallas.salir_del_aula(); p.app_pantallas.ir_hangar(); await create_timer(0.3).timeout
	_ok("oculto en el hangar sin conexion", not p.app_avion_ajustes.ids_hangar().has("BIPODE"))
	p.sesion["alumno"] = { "id": "x", "nombre": "Prueba", "progreso": { "robot": false } }          # un piloto sin los tres logros
	p.app_pantallas.elegir_avion("BIPODE"); p.app_pantallas.ir_hangar(); await create_timer(0.3).timeout
	_ok("sin los tres logros, oculto (y el hangar vuelve al dron)", not p.app_avion_ajustes.ids_hangar().has("BIPODE") and p.sesion["avion"] == "DJI_MINI", str(p.sesion["avion"]))
	p.sesion["alumno"]["progreso"]["robot"] = true                                                    # con los tres
	p.app_pantallas.ir_hangar(); await create_timer(0.3).timeout; p.app_pantallas.elegir_avion("BIPODE")
	_ok("con los tres logros, en el hangar", p.app_avion_ajustes.ids_hangar().has("BIPODE") and p.sesion["avion"] == "BIPODE", str(p.sesion["avion"]))
	await create_timer(1.0).timeout
	if args.has("foto"): root.get_viewport().get_texture().get_image().save_png(args["foto"] + "_hangar.png")
	p.sesion["escenario"] = "libre"; p.app_vuelo.empezar()
	while p.pantalla_actual != "" or p.av.is_empty(): await create_timer(0.2).timeout
	await create_timer(1.0).timeout
	_ok("es el bipode", p.es_bipode() and p.juego_bip != null and p.juego_bip.drones.size() == 6)
	p.app_vuelo.lanzar(); _tecla(KEY_W, true)
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 4000: await process_frame
	_ok("anda", p.av["vel"] > 0.5 and p.av["amp"] > 0.5 and p.av["pisadas"] > 0, "vel %.2f amp %.2f pisadas %d p %s" % [p.av["vel"], p.av["amp"], p.av["pisadas"], str(p.av["p"])])
	if args.has("foto"): root.get_viewport().get_texture().get_image().save_png(args["foto"] + "_anda.png")
	_tecla(KEY_W, false)
	# apuntar a un dron diana y disparar
	_tecla(KEY_SPACE, true)
	var dr: Dictionary = p.juego_bip.drones[0]
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 6000 and p.juego_bip.derribados == 0:
		var a: Dictionary = p.modelo.apuntado(p.av); var d := [dr["p"][0] - a["o"][0], dr["p"][1] - a["o"][1], dr["p"][2] - a["o"][2]]
		p.av["cintura"] = fposmod(atan2(d[1], d[0]) - p.av["rumbo"], TAU); p.av["brazos"] = atan2(-d[2], Vector2(d[0], d[1]).length())
		await process_frame
	p.camara = 3; await create_timer(0.3).timeout
	if args.has("foto"): root.get_viewport().get_texture().get_image().save_png(args["foto"] + "_tiro.png")
	_tecla(KEY_SPACE, false)
	_ok("dispara y derriba", p.av["disparos"] > 0 and p.juego_bip.derribados > 0, "disparos %d derribados %d" % [p.av["disparos"], p.juego_bip.derribados])
	await create_timer(1.5).timeout
	p.camara = 2; await create_timer(0.5).timeout
	if args.has("foto"): root.get_viewport().get_texture().get_image().save_png(args["foto"] + "_cae.png")
	print("FALLOS ", fallos)
	quit(1 if fallos else 0)
