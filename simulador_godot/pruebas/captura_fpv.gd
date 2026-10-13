extends SceneTree
## Capturas del modelo detallado del dron FPV (ModeloFPV3D dentro de Avion3D) desde varios lados, para compararlo a ojo
## con fotos de un 5" real: 3/4 delantero, frente, lado, arriba, detras y abajo (desarmado: palas quietas), primeros
## planos del motor y de la camara, armado con los motores a media potencia (helices con disco de desenfoque),
## frenando tras desarmar (palas que se ven girar despacio) y la camara FPV (camara 3: solo su sombra). Imprime el tiempo
## de construccion y los triangulos. Necesita ventana (no --headless).
## Uso (desde la carpeta del repositorio):
##   herramientas/godot/Godot_v4.7.2-stable_win64_console.exe --path simulador_godot --resolution 1280x800 --script res://pruebas/captura_fpv.gd -- --captura=<prefijo>
## Guarda <prefijo>_<vista>.png.

var prefijo := "user://fpv"

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--captura="): prefijo = a.substr(10)
	root.msaa_3d = Viewport.MSAA_4X
	var escena := Node3D.new(); root.add_child(escena)
	var env := Environment.new()
	var cielo := Sky.new(); var ps := ProceduralSkyMaterial.new(); cielo.sky_material = ps; env.sky = cielo
	env.background_mode = Environment.BG_COLOR; env.background_color = Color(0.93, 0.93, 0.93)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY; env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC; env.ssao_enabled = true; env.ssao_radius = 0.02; env.ssao_intensity = 1.5
	var we := WorldEnvironment.new(); we.environment = env; escena.add_child(we)
	var sol := DirectionalLight3D.new(); sol.shadow_enabled = true; sol.directional_shadow_max_distance = 3.0
	escena.add_child(sol); sol.look_at_from_position(Vector3(1.0, 2.0, 1.2), Vector3.ZERO, Vector3.UP)
	var suelo := MeshInstance3D.new(); var pm := PlaneMesh.new(); pm.size = Vector2(20, 20); suelo.mesh = pm
	var ms := StandardMaterial3D.new(); ms.albedo_color = Color(0.86, 0.86, 0.85); suelo.material_override = ms; escena.add_child(suelo)
	var t0 := Time.get_ticks_usec()
	var datos := DatosComunes.avion("FPV")
	var dron := Avion3D.new(datos); escena.add_child(dron)
	print("construccion del dron: %.1f ms (con las mallas)" % ((Time.get_ticks_usec() - t0) / 1000.0))
	t0 = Time.get_ticks_usec(); var otro := Avion3D.new(datos); otro.free()
	print("construccion de otro dron (mallas en cache): %.1f ms" % ((Time.get_ticks_usec() - t0) / 1000.0))
	var C := ModeloFPV3D.mallas(datos["modelo3d"])
	print("triangulos: fijo %d (una malla), palas+buje %d por rotor, disco %d por rotor" % [C["fija"].idx.size() / 3, C["palas"][1].idx.size() / 3, C["disco"].idx.size() / 3])
	var cam := Camera3D.new(); escena.add_child(cam); cam.current = true; cam.near = 0.005
	var m := ModeloFPV.new(datos)
	var av := m.estado_inicial()            # posado y desarmado ("en mano")
	dron.actualizar(av)
	var c := Avion3D.ned(av["p"])
	cam.fov = 30
	for v in [["34", [0.55, 0.40, -0.30]], ["frente", [0.75, 0.0, -0.12]], ["lado", [0.0, -0.75, -0.04]], ["arriba", [0.0, 0.0001, -0.85]],
			  ["detras", [-0.55, 0.40, -0.30]], ["abajo", [0.45, -0.35, 0.10]]]:
		var p: Array = v[1]
		cam.look_at_from_position(c + Avion3D.ned(p), c, Vector3.UP if v[0] != "arriba" else Vector3.FORWARD)
		await _cuadros(4); dron.actualizar(av)
		await _guardar("_" + v[0])
	# primeros planos: motor delantero derecho y camara
	cam.fov = 22
	var mot := c + Avion3D.ned([0.078, 0.078, -0.005])
	cam.look_at_from_position(mot + Avion3D.ned([0.10, 0.07, -0.07]), mot, Vector3.UP)
	await _cuadros(2); await _guardar("_motor")
	var cm := c + Avion3D.ned([0.06, 0.0, -0.008])
	cam.look_at_from_position(cm + Avion3D.ned([0.15, 0.08, -0.04]), cm, Vector3.UP)
	await _cuadros(2); await _guardar("_camara")
	# armado, motores a media potencia: discos de desenfoque
	cam.fov = 30
	av["estado"] = "volando"; av["armado"] = true; av["motores"] = [0.5, 0.5, 0.5, 0.5]
	for k in 30:
		dron.actualizar(av); await process_frame
	cam.look_at_from_position(c + Avion3D.ned([0.55, 0.40, -0.30]), c, Vector3.UP)
	await _cuadros(2); dron.actualizar(av); await _guardar("_girando")
	print("girando: rpm que se ven %.0f, palas visibles %s, disco visible %s" % [dron.fpv.rotores[0]["rpm"], dron.fpv.rotores[0]["palas"].visible, dron.fpv.rotores[0]["disco"].visible])
	# al ralenti (armado en el suelo)
	av["motores"] = [0.055, 0.055, 0.055, 0.055]
	for k in 40:
		dron.actualizar(av); await process_frame
	await _guardar("_ralenti")
	# desarmado: frenan hasta pararse (palas que se ven girar despacio)
	av["armado"] = false; av["motores"] = [0.0, 0.0, 0.0, 0.0]
	for k in 200:
		dron.actualizar(av); await process_frame
		if dron.fpv.rotores[0]["rpm"] < 400: break
	await _guardar("_frenando")
	print("frenando: rpm que se ven %.0f" % dron.fpv.rotores[0]["rpm"])
	# camara FPV (camara 3, dentro del bastidor): el dron no se dibuja, solo su sombra
	av["armado"] = true; av["motores"] = [0.3, 0.3, 0.3, 0.3]
	dron.camara_fpv = true
	cam.fov = 75; cam.global_position = c + Avion3D.ned([0.075, 0.0, -0.035])
	cam.look_at(c + Avion3D.ned([1.0, 0.0, -0.5]), Vector3.UP)
	for k in 5:
		dron.actualizar(av); await process_frame
	await _guardar("_camara3")
	cam.look_at_from_position(c + Avion3D.ned([0.0, 0.001, -0.9]), c, Vector3.FORWARD)
	await _cuadros(2); await _guardar("_camara3_sombra")
	quit()

func _cuadros(n: int) -> void:
	for k in n: await process_frame

func _guardar(suf: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(prefijo + suf + ".png")
	print("captura: ", prefijo + suf + ".png")
