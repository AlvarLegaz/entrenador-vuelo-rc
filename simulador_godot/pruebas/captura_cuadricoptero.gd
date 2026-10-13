extends SceneTree
## Captura del dron DJI Mini dibujado por Avion3D (malla de DatosComunes, 4 rotores y luces), para mirarlo a ojo:
## de cerca (rotores girando y luces), de lejos con el zoom del piloto (las luces se ven de ~16 px aunque el dron
## ocupe un par de pixeles) y en el suelo con los motores parados (sin rotores ni luces). Necesita ventana (no --headless).
## Uso (desde la carpeta del repositorio):
##   herramientas/godot/Godot_v4.7.2-stable_win64_console.exe --path simulador_godot --script res://pruebas/captura_cuadricoptero.gd -- --captura=<prefijo>
## Guarda <prefijo>_cerca.png, <prefijo>_lejos.png y <prefijo>_suelo.png.

func _initialize() -> void:
	var prefijo := "user://dron"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--captura="): prefijo = a.substr(10)
	var escena := Node3D.new(); root.add_child(escena)
	var env := Environment.new(); env.background_mode = Environment.BG_COLOR; env.background_color = Color(0.55, 0.72, 0.92)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; env.ambient_light_color = Color(0.6, 0.6, 0.6)
	var we := WorldEnvironment.new(); we.environment = env; escena.add_child(we)
	var sol := DirectionalLight3D.new(); sol.rotation = Vector3(-0.9, 0.6, 0); escena.add_child(sol)
	var suelo := MeshInstance3D.new(); var pm := PlaneMesh.new(); pm.size = Vector2(200, 200); suelo.mesh = pm
	var ms := StandardMaterial3D.new(); ms.albedo_color = Color(0.45, 0.4, 0.3); suelo.material_override = ms; escena.add_child(suelo)
	var dron := Avion3D.new(DatosComunes.avion("DJI_MINI")); escena.add_child(dron)
	var cam := Camera3D.new(); escena.add_child(cam); cam.current = true
	var m := ModeloCuadricoptero.new(DatosComunes.avion("DJI_MINI"))
	var av := m.estado_inicial(); m.lanzar(av)
	av["p"] = [0.0, 0.0, -2.0]; av["q"] = Cuat.desde_euler(0.1, -0.15, 0.4); av["gases"] = 0.5; av["posado"] = false
	# 1) de cerca, en vuelo: rotores y luces (se espera a un instante con las tres encendidas: estrobo en 0-0,06 s)
	dron.actualizar(av)
	cam.fov = 40; cam.look_at_from_position(Avion3D.ned([-0.55, -0.35, -2.25]), Avion3D.ned(av["p"]), Vector3.UP)
	await _instante_estrobo(dron, av)
	await _guardar(prefijo + "_cerca.png")
	# 2) de lejos (60 m) con el zoom del piloto (fov 6 grados): las luces del mismo tamano en pixeles
	cam.fov = 6; cam.look_at_from_position(Avion3D.ned([-60.0, 0.0, -1.6]), Avion3D.ned(av["p"]), Vector3.UP)
	await _instante_estrobo(dron, av)
	await _guardar(prefijo + "_lejos.png")
	# 3) en el suelo con los motores parados ("en mano"): sin rotores ni luces
	av = m.estado_inicial(); dron.actualizar(av)
	cam.fov = 40; cam.look_at_from_position(Avion3D.ned([-0.55, -0.35, -0.3]), Avion3D.ned(av["p"]), Vector3.UP)
	for k in 3: await process_frame
	dron.actualizar(av)
	await _guardar(prefijo + "_suelo.png")
	var vis := []
	for l in dron.luces: vis.append(l.visible)
	print("en el suelo: rotores visibles %s, luces visibles %s" % [dron.helice.visible, vis])
	quit()

func _instante_estrobo(dron: Avion3D, av: Dictionary) -> void:
	while fmod(Time.get_ticks_msec() / 1000.0, 1.0) > 0.02: await process_frame
	dron.actualizar(av)
	var vis := []
	for l in dron.luces: vis.append(l.visible)
	print("rotores visibles %s, luces visibles %s, tamano de la luz %.5f m por m de profundidad" % [dron.helice.visible, vis, (dron.luces[0].get_child(0) as Sprite3D).pixel_size * 32])

func _guardar(ruta: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ruta)
	print("captura: ", ruta)
