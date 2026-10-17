extends SceneTree
## Prueba del bipode en una sala multijugador (contra un servidor del aula en marcha): entra en la sala dada con el
## bipode, apunta al primer compañero que vea en el aire y dispara hasta que el servidor reparte el impacto.
## No toca la configuracion del usuario (entra a mano, sin Aula.entrar).
## Con --victima entra con el dron comercial, se queda en el aire 50 m al norte y a 15 m y espera a que lo derriben.
## Uso: ... --script res://Tests/prueba_bipode_sala.gd -- --aula=http://127.0.0.1:8080 --sala=CODIGO [--victima] [--foto=f.png]

var p: Node

func _initialize() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1); args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	p = load("res://escenas/principal.tscn").instantiate(); root.add_child(p)
	while p.aula == null or p.pantallas.is_empty() or not p.pantallas["pAlumno"].visible: await create_timer(0.2).timeout
	p.aula.url = Aula.normalizar_url(args.get("aula", "http://127.0.0.1:8080"))
	await preload("res://Tests/util_aula.gd").alta(p, p.aula.url, args.get("pin", "1234"), "Bipode Godot", "clave1")    # como el profesor desde su panel
	var r: Dictionary = await p.aula.api("POST", "entrar", { "usuario": "Bipode Godot", "clave": "clave1" }, "-")
	if not r["ok"]: print("MAL no se pudo entrar: ", r["error"]); quit(1); return
	p.aula.activo = true; p.aula.pase = String(r["datos"]["pase"]); p.app_pantallas.dentro_del_aula(r["datos"]["alumno"])
	var salas: Dictionary = await p.aula.api("GET", "salas")
	var sala = null
	for s in salas["datos"]: if String(s["codigo"]) == String(args.get("sala", "")): sala = s
	if sala == null: print("MAL no esta la sala"); quit(1); return
	p.sesion["avion"] = "DJI_MINI" if args.has("victima") else "BIPODE"
	await p.aula.api("POST", "salas/%s/entrar" % sala["codigo"], { "id": p.app_multijugador.multi_id(), "clave": "", "nombre": "Bipode Godot", "alumno": null })
	p.app_multijugador.entrar_sala(sala)
	while p.pantalla_actual != "" or p.av.is_empty(): await create_timer(0.2).timeout
	print("BIPODE ", p.sesion["avion"], " ", p.es_bipode())
	if args.has("victima"):
		p.app_vuelo.lanzar(); await create_timer(0.5).timeout
		var t1 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t1 < 90000 and p.av["estado"] == "volando":
			if p._caida.is_empty(): p.av["p"] = [50.0, 0.0, -15.0]; p.av["v"] = [0.0, 0.0, 0.0]; p.av["posado"] = false; p.av["despegado"] = true
			await process_frame
		print("VICTIMA ", p.av["estado"], " ", p.vuelo["final"] if p.vuelo != null else "", " altura ", -p.av["p"][2])
		quit(0); return
	p.app_vuelo.lanzar(); await create_timer(2.0).timeout
	var t0 := Time.get_ticks_msec()
	var e := InputEventKey.new(); e.physical_keycode = KEY_SPACE; e.keycode = KEY_SPACE; e.pressed = true; Input.parse_input_event(e)
	while Time.get_ticks_msec() - t0 < 30000:
		var bl: Array = p.app_vuelo._blancos_sala()
		if not bl.is_empty():
			var o: Dictionary = bl[0]; var a: Dictionary = p.modelo.apuntado(p.av); var d := [o["p"][0] - a["o"][0], o["p"][1] - a["o"][1], o["p"][2] - a["o"][2]]
			p.av["cintura"] = fposmod(atan2(d[1], d[0]) - p.av["rumbo"], TAU); p.av["brazos"] = atan2(-d[2], Vector2(d[0], d[1]).length())
		if p.juego_bip != null and not p.juego_bip.golpes.is_empty() and Time.get_ticks_msec() - t0 > 3000: break
		await process_frame
	for id in p.multi_otros: var o: Dictionary = p.multi_otros[id]; print("OTRO ", o["avion"], " ", o.get("estado"), " agl ", o.get("agl"), " p ", o.get("p"))
	print("SALA ", p.sala.get("codigo"), " otros ", p.multi_otros.size())
	print("GOLPES ", JSON.stringify(p.juego_bip.golpes), " blancos ", p.app_vuelo._blancos_sala().size(), " disparos ", p.av["disparos"])
	await create_timer(3.0).timeout
	if args.has("foto"): p.camara = 3; await create_timer(0.3).timeout; root.get_viewport().get_texture().get_image().save_png(args["foto"])
	quit(0)
