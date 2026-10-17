extends SceneTree
## Comprobacion visual de la isla del campo de vuelo (Campo3D): la construye, espera a que el suelo este pintado y guarda
## capturas desde el puesto del piloto (camara 1 del navegador: base + (1,5; 1,7; 2), campo de vision de 50 grados sin
## zoom) mirando al norte (circuito) y al sur (zona 2), y una vista alta. Para compararlas con las del navegador
## (simulador_web/Tests/captura_campo_web.py hace las mismas). Necesita GPU (no --headless):
##   herramientas/godot/Godot_v4.7.2-stable_win64_console.exe --path simulador_godot --script res://Tests/ver_campo.gd -- --salida=C:/ruta/carpeta [--calidad=2]

const VISTAS := {
	"norte": [Vector3(1.5, 1.7, 2), Vector3(1.5, 1.7, -998)],
	"sur": [Vector3(1.5, 1.7, 2), Vector3(1.5, 1.7, 1002)],
	"alto": [Vector3(-60, 140, 260), Vector3(0, 0, -80)],
}

func _init() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1); args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var salida: String = args.get("salida", OS.get_user_data_dir())
	DirAccess.make_dir_recursive_absolute(salida)
	root.size = Vector2i(1280, 720)
	var ent := Entorno.new(); ent.poner_mundo({}); ent.configurar_viento(4, 270, false); ent.actualizar(0.01)
	var campo := Campo3D.new(); campo.calidad = int(args.get("calidad", "2")); root.add_child(campo)
	var t0 := Time.get_ticks_msec()
	campo.construir(ent)
	print("construir: %d ms" % (Time.get_ticks_msec() - t0))
	campo.poner_base(0, 0); campo.actualizar_manga(ent.viento["actual"])
	var cam := Camera3D.new(); cam.fov = 50; cam.near = 0.1; cam.far = 3000; root.add_child(cam); cam.current = true
	if not campo.listo: await campo.suelo_listo
	print("suelo pintado: %d ms" % (Time.get_ticks_msec() - t0))
	for nombre in VISTAS:
		var v: Array = VISTAS[nombre]
		cam.position = campo.base + v[0]; cam.look_at(campo.base + v[1], Vector3.UP)
		for i in 4: await process_frame
		await RenderingServer.frame_post_draw
		var ruta := salida.path_join("godot_%s.png" % nombre)
		root.get_texture().get_image().save_png(ruta); print("captura: ", ruta)
	quit()
