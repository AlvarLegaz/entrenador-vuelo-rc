extends SceneTree
## Prueba de las instalaciones industriales (industria.gd, la fabrica de SABIC de singulares.js): numero de primitivas y
## una suma de control que debe dar lo mismo que Industria.primitivas de la web (js/industria.js), los solidos para el
## choque y una foto desde el aire.
## Uso: ... --script res://pruebas/prueba_industria.gd [-- --foto=f.png --vista=n,e,h,n2,e2,h2]

func _initialize() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1); args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var n_pr := 0; var suma := 0.0; var n_pz := 0
	for S in Mundo3D.singulares_datos():
		if not String(S["nombre"]).begins_with("Fábrica de SABIC"): continue
		for pz in S["piezas"]:
			n_pz += 1
			for q in Industria.primitivas(pz):
				for k in 9: suma += float(q[k]) * (1 + (n_pr % 7) + 0.1 * k)
				n_pr += 1
	print("INDUSTRIA piezas %d primitivas %d suma %.4f" % [n_pz, n_pr, suma])
	var p = load("res://escenas/principal.tscn").instantiate(); root.add_child(p)
	while p.aula == null or p.pantallas.is_empty() or not p.pantallas["pAlumno"].visible: await create_timer(0.2).timeout
	p.salir_del_aula(); p.sesion["avion"] = "DJI_MINI"; p.sesion["escenario"] = "libre_cartagena"
	var d = null
	for x in p.destacados_lanz(): if String(x["nombre"]).begins_with("SABIC"): d = x
	p.elegir_destacado(d); p.empezar()
	while p.pantalla_actual != "" or p.av.is_empty(): await create_timer(0.2).timeout
	await create_timer(3.0).timeout
	var E = p.ent; var L: Array = E._edificios.get("singulares", [])
	print("SOLIDOS singulares ", L.size())
	var g = L[0]; var P: Array = g[0]; var e := 0.0; var n := 0.0
	for i in range(0, P.size(), 2): e += P[i]; n += P[i + 1]
	e /= P.size() / 2; n /= P.size() / 2
	print("DENTRO ", E.choca_edificio([n, e, -(g[1] + g[2]) / 2], 0.15), " ENCIMA ", E.choca_edificio([n, e, -(g[2] + 20)], 0.15))
	if args.has("foto"):
		var v: PackedFloat64Array = PackedFloat64Array(Array(String(args.get("vista", "10500,-4700,160,10230,-4400,0")).split(",")).map(func(s): return float(s)))
		var cam := Camera3D.new(); cam.far = 16000; cam.fov = 60; root.add_child(cam)
		cam.position = Vector3(v[1], E.altura(v[0], v[1]) + v[2], -v[0]); cam.look_at(Vector3(v[4], E.altura(v[3], v[4]) + v[5], -v[3])); cam.make_current()
		for c in root.find_children("*", "CanvasLayer", true, false): c.visible = false
		await create_timer(1.5).timeout
		root.get_viewport().get_texture().get_image().save_png(args["foto"])
	quit(0)
