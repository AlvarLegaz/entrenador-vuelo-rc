extends SceneTree
## Prueba del multijugador contra un servidor del aula en marcha (aula/servidor_aula.py): crea una sala de vuelo libre,
## entra con el E1, lo lanza y, durante 20 s, escribe a quien ve en la sala (lineas "OTROS ..."). Sirve para probarlo con
## otro simulador (la web o este mismo) que entre en la sala que anuncia ("SALA <codigo>"). Al final guarda una captura
## con la camara de persecucion y sale de la sala.
## Uso (necesita ventana):
##   herramientas/godot/Godot_v4.7.2-stable_win64_console.exe --path simulador_godot --script res://pruebas/prueba_multijugador.gd -- --aula=http://localhost:8080 --foto=multi.png

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
	var r: Dictionary = await p.aula.api("POST", "salas", { "nombre": "Prueba Godot", "escenario": "libre", "lanz": null, "viento": { "vel": 0, "desde": 0, "rachas": false } })
	if not r["ok"]: print("MAL no se pudo crear la sala: ", r["error"]); quit(1); return
	print("SALA ", r["datos"]["codigo"])
	p.entrar_sala(r["datos"])
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
