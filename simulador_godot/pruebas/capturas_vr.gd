extends SceneTree
## Capturas de como se ve el modo de realidad virtual (scripts/modo_vr.gd) sin gafas: el Mini Dron HQ en el campo del
## club con la calidad de las gafas (rendimiento maximo), una imagen por ojo (64 mm entre ellos, campo de vision de las
## gafas) desde donde estaria la cabeza, con el mando izquierdo y su panel a la vista. Las junta capturas_vr.py.
##   herramientas/godot/Godot_v4.7.2-stable_win64_console.exe --path simulador_godot --rendering-method mobile --resolution 1000x1040 --script res://pruebas/capturas_vr.gd -- --calidad=min --fotos=<carpeta>/vr

const IPD := 0.064
var p

func _esperar(s: float) -> void:
	var t := Time.get_ticks_msec() + int(s * 1000)
	while Time.get_ticks_msec() < t: await process_frame

func _foto(v: ModoVR, prefijo: String, nombre: String) -> void:
	var cam := v.cabeza as Camera3D
	for ojo in [["izq", -1.0], ["der", 1.0]]:
		await process_frame                                   # actualizar() coloca la cabeza; luego se separa el ojo
		cam.global_position += cam.global_transform.basis.x * (ojo[1] * IPD / 2)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("%s_%s_%s.png" % [prefijo, nombre, ojo[0]])
		cam.global_position -= cam.global_transform.basis.x * (ojo[1] * IPD / 2)
	print("  ", nombre)

func _initialize() -> void:
	var prefijo := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--fotos="): prefijo = a.substr(8)
	if prefijo == "" or DisplayServer.get_name() == "headless": print("MAL hace falta ventana y --fotos=<prefijo>"); quit(1); return
	p = load("res://escenas/principal.tscn").instantiate(); root.add_child(p)
	await create_timer(1.0).timeout
	p.sesion["escenario"] = "libre"; p.sesion["avion"] = "DJI_MINI"; p.sesion["sin_registrar"] = true
	p.empezar()
	for k in 900:
		await process_frame
		if p.pantalla_actual == "" and not p.av.is_empty() and p.modelo != null: break
	p.ui.visible = false
	var cam := Camera3D.new(); cam.fov = 92; cam.near = 0.05; cam.far = 16000.0
	var v := ModoVR._crear(p, Node3D.new(), cam, Node3D.new(), Node3D.new()); p.vr = v; cam.current = true
	v.izq.position = Vector3(-0.13, 1.36, -0.33); v.izq.rotation = Vector3(-0.2, 0.3, 0.2)      # la mano izquierda delante, algo baja
	v.der.position = Vector3(0.19, 1.27, -0.3); v.der.rotation = Vector3(-0.3, -0.2, -0.1)
	cam.transform = Transform3D(Basis.from_euler(Vector3(deg_to_rad(-12), 0, 0)), Vector3(0, 1.6, 0))
	v._boton("ax_button", true); await _esperar(3.0)
	v.izq.set_meta("primary", Vector2(0, 1)); v.der.set_meta("primary", Vector2(0, 0.6)); await _esperar(5.0)       # sube y avanza
	v.izq.set_meta("primary", Vector2.ZERO); v.der.set_meta("primary", Vector2.ZERO); await _esperar(2.5)
	# 1. camara del dron: mirando al frente y algo abajo (gimbal -25), y luego mirando hacia abajo (gimbal -70)
	cam.transform = Transform3D(Basis.from_euler(Vector3(deg_to_rad(-25), 0, 0)), Vector3(0, 1.6, 0)); await _esperar(1.0)
	await _foto(v, prefijo, "dron_frente")
	cam.transform = Transform3D(Basis.from_euler(Vector3(deg_to_rad(-70), 0, 0)), Vector3(0, 1.6, 0)); await _esperar(1.0)
	await _foto(v, prefijo, "dron_abajo")
	# 2. camara del piloto, de pie en el campo, mirando al dron
	p.camara = 1; cam.transform = Transform3D(Basis(), Vector3(0, 1.6, 0)); await _esperar(0.5)
	var al := Avion3D.ned(p.av["p"]) - v.origen.global_position - v.origen.global_basis * Vector3(0, 1.6, 0)
	var loc := v.origen.global_basis.inverse() * al
	cam.transform = Transform3D(Basis.looking_at(loc.normalized(), Vector3.UP), Vector3(0, 1.6, 0)); await _esperar(0.5)
	await _foto(v, prefijo, "piloto")
	print("RESULTADO: capturas hechas")
	quit(0)
