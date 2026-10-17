extends SceneTree
## Capturas del modelo detallado del Mini Dron HQ (ModeloDJI3D dentro de Avion3D) desde varios lados, para compararlo a
## ojo con fotos del dron real: 3/4 delantero, frente, lado, arriba y detras (parado, palas quietas), en vuelo (helices
## con disco de desenfoque, inclinado hacia delante y camara estabilizada a -30 grados), la camara mirando abajo (-90),
## y el tiempo de construccion. Necesita ventana (no --headless).
## Uso (desde la carpeta del repositorio):
##   herramientas/godot/Godot_v4.7.2-stable_win64_console.exe --path simulador_godot --resolution 1280x800 --script res://Tests/captura_dji.gd -- --captura=<prefijo>
## Guarda <prefijo>_<vista>.png.

var prefijo := "user://dji"

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
	var datos := DatosComunes.avion("DJI_MINI")
	var dron := Avion3D.new(datos); escena.add_child(dron)
	print("construccion del dron: %.1f ms (con la malla de los datos)" % ((Time.get_ticks_usec() - t0) / 1000.0))
	t0 = Time.get_ticks_usec(); var otro := Avion3D.new(datos); otro.free()
	print("construccion de otro dron (mallas en cache): %.1f ms" % ((Time.get_ticks_usec() - t0) / 1000.0))
	var tri := 0
	for mi in dron.find_children("*", "MeshInstance3D", true, false):
		var m: Mesh = (mi as MeshInstance3D).mesh
		for s in m.get_surface_count(): tri += (m.surface_get_arrays(s)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	print("triangulos del dron (con las palas y discos de los 4 rotores): %d" % tri)
	var cam := Camera3D.new(); escena.add_child(cam); cam.current = true; cam.near = 0.01
	var m := ModeloCuadricoptero.new(datos)
	var av := m.estado_inicial()            # posado, motores parados ("en mano")
	av["gimbal"] = 0.0
	dron.actualizar(av)
	var c := Avion3D.ned(av["p"])
	cam.fov = 30
	for v in [["34", [0.42, -0.30, -0.22]], ["frente", [0.55, 0.0, -0.20]], ["lado", [0.0, -0.6, -0.02]], ["arriba", [0.0, 0.0001, -0.6]],
			  ["detras", [-0.45, 0.25, -0.18]], ["abajo", [0.25, -0.20, 0.10]]]:
		var p: Array = v[1]
		cam.look_at_from_position(c + Avion3D.ned(p), c, Vector3.UP if v[0] != "arriba" else Vector3.FORWARD)
		await _cuadros(4); dron.actualizar(av)
		await _guardar("_" + v[0])
	# primer plano del morro: gimbal a 0 y a -90
	cam.fov = 22
	cam.look_at_from_position(c + Avion3D.ned([0.25, -0.12, -0.03]), c + Avion3D.ned([0.06, 0.0, 0.0]), Vector3.UP)
	await _cuadros(2); await _guardar("_morro0")
	av["gimbal"] = -90.0; dron.actualizar(av); await _cuadros(2); await _guardar("_morro90")
	# en vuelo: armado, 11000 rpm, inclinado 15 grados adelante y girado; camara a -30 (estabilizada)
	m.lanzar(av); av["p"] = [0.0, 0.0, -1.0]; av["q"] = Cuat.desde_euler(0.05, -0.26, 0.3); av["rpm"] = 11000.0; av["gases"] = 0.5
	av["gimbal"] = -30.0; av["posado"] = false
	for k in 40:
		dron.actualizar(av); await process_frame
	c = Avion3D.ned(av["p"]); cam.fov = 30
	cam.look_at_from_position(c + Avion3D.ned([0.45, -0.35, -0.2]), c, Vector3.UP)
	await _cuadros(2); dron.actualizar(av); await _guardar("_vuelo")
	print("en vuelo: rpm que se ven %.0f, palas visibles %s, disco visible %s" % [dron.dji.rpm, dron.dji.rotores[0]["palas"].visible, dron.dji.rotores[0]["disco"].visible])
	# arranque: 400 rpm (palas fundiendose con el disco)
	av["rpm"] = 0.0; av["estado"] = "en mano"
	for k in 90:
		dron.actualizar(av); await process_frame
		if dron.dji.rpm < 420: break
	await _guardar("_frenando")
	print("frenando: rpm que se ven %.0f" % dron.dji.rpm)
	# camara dentro del dron (como la camara 3): el dron no debe verse
	cam.fov = 58; cam.global_position = c + Avion3D.ned(Cuat.rot(av["q"], [0.1, 0.0, -0.1]))
	cam.look_at(cam.global_position + Avion3D.ned([0.0, 0.0, 1.0]) + Vector3(0.001, 0, 0), Vector3.UP)
	await _cuadros(3); dron.actualizar(av); await _cuadros(1)
	await _guardar("_camara3")
	quit()

func _cuadros(n: int) -> void:
	for k in n: await process_frame

func _guardar(suf: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(prefijo + suf + ".png")
	print("captura: ", prefijo + suf + ".png")
