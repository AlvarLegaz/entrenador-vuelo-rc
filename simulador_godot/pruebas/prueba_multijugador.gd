extends SceneTree
## Prueba del multijugador contra un servidor del aula en marcha (aula/servidor_aula.py): crea una sala de vuelo libre,
## entra con el E1, lo lanza y, durante 20 s, escribe a quien ve en la sala (lineas "OTROS ..."). Sirve para probarlo con
## otro simulador (la web o este mismo) que entre en la sala que anuncia ("SALA <codigo>"). Al final guarda una captura
## con la camara de persecucion y sale de la sala.
## Uso (necesita ventana):
##   herramientas/godot/Godot_v4.7.2-stable_win64_console.exe --path simulador_godot --script res://pruebas/prueba_multijugador.gd -- --aula=http://127.0.0.1:8080 --pin=PIN_DEL_PROFESOR --foto=multi.png

var p: Node

func _initialize() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1); args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	p = load("res://escenas/principal.tscn").instantiate(); root.add_child(p)
	while p.aula == null or p.pantallas.is_empty() or not p.pantallas["pInicio"].visible: await create_timer(0.2).timeout   # que acabe su arranque (aula e inicio)
	# el aula de la prueba (sin guardar nada en la configuracion del usuario, que puede tener el registro local)
	p.aula.url = args.get("aula", "http://localhost:8080"); p.aula.activo = false; p.aula.modo = "servidor"
	p.aula.activo = (await p.aula.api("GET", "estado"))["ok"]
	print("AULA ", p.aula.activo, " ", p.aula.modo, " ", p.aula.url, " ", p.multi_posible())
	p.sesion["avion"] = "E1"
	# las salas las crea el profesor (con su PIN): la prueba entra como profesor para crearla
	var tok: Dictionary = await p.aula.api("POST", "profesor/entrar", { "pin": args.get("pin", "1234") })
	if not tok["ok"]: print("MAL no se pudo entrar como profesor: ", tok["error"]); quit(1); return
	var req := HTTPRequest.new(); root.add_child(req)
	req.request(p.aula.url.trim_suffix("/") + "/api/salas", PackedStringArray(["Content-Type: application/json", "Authorization: Bearer " + String(tok["datos"]["token"])]), HTTPClient.METHOD_POST,
		JSON.stringify({ "nombre": "Prueba Godot", "escenario": "libre", "lanz": null, "viento": { "vel": 0, "desde": 0, "rachas": false } }))
	var res: Array = await req.request_completed; req.queue_free()
	var sala = JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8())
	if res[1] < 200 or res[1] >= 300 or not (sala is Dictionary): print("MAL no se pudo crear la sala: ", res[1]); quit(1); return
	print("SALA ", sala["codigo"])
	p.entrar_sala(sala)
	await create_timer(2.0).timeout
	p.av["gases"] = 1.0; p.lanzar()
	for k in 20:
		await create_timer(1.0).timeout
		p.av["gases"] = 0.7; p.mando["pitch"] = 0.15 if k < 4 else 0.0; p.mando["yaw"] = 0.2
		var vistos := []
		for id in p.multi_otros: vistos.append("%s/%s/%s/%.0fm" % [p.multi_otros[id]["nombre"], p.multi_otros[id]["avion"], p.multi_otros[id]["estado"], -float(p.multi_otros[id]["p"][2])])
		print("OTROS ", vistos, " fantasmas ", p._fantasmas.size(), " panel ", p.sala_info.visible, " enviando ", p._multi_enviando, " pantalla ", p.pantalla_actual, " estado ", p.av.get("estado"))
	if args.has("foto"):
		p.camara = 1; await create_timer(1.0).timeout
		root.get_viewport().get_texture().get_image().save_png(args["foto"]); print("Captura en ", args["foto"])
	p.ir_inicio(); await create_timer(0.5).timeout
	print("FIN")
	quit()
