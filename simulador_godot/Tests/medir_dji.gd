extends SceneTree
## Coste de dibujo del modelo detallado del dron comercial (ModeloDJI3D) frente a la malla de cajas de los datos (la de antes):
## mismo dron, misma escena (cielo, sol con sombras), a 0,7 m (ocupa media pantalla) y a 5 m (camara 2), con los rotores
## girando. Alterna bloques A/B para que la carga variable de la GPU (otros procesos) afecte a los dos por igual.
## Mide el tiempo de GPU y de CPU de dibujo del viewport. Necesita ventana (no --headless).
## Uso: herramientas/godot/Godot_v4.7.2-stable_win64_console.exe --path simulador_godot --resolution 1440x900 --script res://Tests/medir_dji.gd

func _initialize() -> void:
	var escena := Node3D.new(); root.add_child(escena)
	var env := Environment.new()
	var cielo := Sky.new(); cielo.sky_material = ProceduralSkyMaterial.new(); env.sky = cielo; env.background_mode = Environment.BG_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new(); we.environment = env; escena.add_child(we)
	var sol := DirectionalLight3D.new(); sol.shadow_enabled = true; escena.add_child(sol)
	sol.look_at_from_position(Vector3(1.0, 2.0, 1.2), Vector3.ZERO, Vector3.UP)
	var suelo := MeshInstance3D.new(); var pm := PlaneMesh.new(); pm.size = Vector2(200, 200); suelo.mesh = pm; escena.add_child(suelo)
	var datos := DatosComunes.avion("DJI_MINI")
	var viejo := datos.duplicate(true); viejo["tipo"] = "cajas"          # sin tipo cuadricoptero: la malla de cajas
	var A := Avion3D.new(viejo); var B := Avion3D.new(datos)
	escena.add_child(A); escena.add_child(B)
	var m := ModeloCuadricoptero.new(datos); var av := m.estado_inicial(); m.lanzar(av)
	av["p"] = [0.0, 0.0, -1.0]; av["q"] = Cuat.desde_euler(0.05, -0.1, 0.3); av["gases"] = 0.5; av["rpm"] = 11000.0; av["posado"] = false
	var cam := Camera3D.new(); escena.add_child(cam); cam.current = true; cam.fov = 40
	var vp := root.get_viewport_rid(); RenderingServer.viewport_set_measure_render_time(vp, true)
	var c := Avion3D.ned(av["p"])
	for dist in [0.7, 5.0]:
		cam.look_at_from_position(c + Avion3D.ned([-dist * 0.8, -dist * 0.4, -dist * 0.45]), c, Vector3.UP)
		var res := { "A": [], "B": [] }
		for bloque in 8:
			for k in ["A", "B"]:
				A.visible = k == "A"; B.visible = k == "B"
				for f in 10:
					A.actualizar(av); B.actualizar(av); await process_frame
				var g := 0.0; var cpu := 0.0
				for f in 30:
					A.actualizar(av); B.actualizar(av); await process_frame
					g += RenderingServer.viewport_get_measured_render_time_gpu(vp); cpu += RenderingServer.viewport_get_measured_render_time_cpu(vp)
				res[k].append([g / 30, cpu / 30])
		var med := func(l: Array, i: int) -> float:
			var v := []
			for x in l: v.append(x[i])
			v.sort(); return v[v.size() / 2]
		print("a %.1f m: GPU cajas %.3f ms, detallado %.3f ms (mediana de 8 bloques); CPU de dibujo cajas %.3f ms, detallado %.3f ms" % [
			dist, med.call(res["A"], 0), med.call(res["B"], 0), med.call(res["A"], 1), med.call(res["B"], 1)])
	quit()
