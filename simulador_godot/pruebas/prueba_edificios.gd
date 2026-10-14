extends SceneTree
## Prueba del choque con los edificios: sale desde SABIC (destacado del vuelo libre en Cartagena), comprueba que la zona
## de detalle tiene sus edificios solidos y que Entorno.choca_edificio da dentro de uno y no por encima ni lejos.
## Uso: ... --script res://pruebas/prueba_edificios.gd [-- --foto=f.png]

func _initialize() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1); args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var p = load("res://escenas/principal.tscn").instantiate(); root.add_child(p)
	while p.aula == null or p.pantallas.is_empty() or not p.pantallas["pAlumno"].visible: await create_timer(0.2).timeout
	p.salir_del_aula(); p.sesion["avion"] = "DJI_MINI"; p.sesion["escenario"] = "libre_cartagena"
	var d = null
	for x in p.destacados_lanz(): if String(x["nombre"]).begins_with("SABIC"): d = x
	print("DESTACADO ", d["nombre"] if d != null else "NO"); p.elegir_destacado(d)
	p.empezar()
	while p.pantalla_actual != "" or p.av.is_empty(): await create_timer(0.2).timeout
	await create_timer(2.0).timeout
	var E = p.ent; var L: Array = E._edificios.get("zona:fotovoltaica", [])
	print("SOLIDOS ", E._edificios.keys(), " zona ", L.size())
	var g = L[0]
	for x in L: if x[2] - x[1] > g[2] - g[1]: g = x
	var P: Array = g[0]; var e := 0.0; var n := 0.0
	for i in range(0, P.size(), 2): e += P[i]; n += P[i + 1]
	e /= P.size() / 2; n /= P.size() / 2; var h: float = (g[1] + g[2]) / 2
	print("DENTRO ", E.choca_edificio([n, e, -h], 0.15), " ENCIMA ", E.choca_edificio([n, e, -(g[2] + 20)], 0.15), " LEJOS ", E.choca_edificio([n + 200, e + 200, -h], 0.15))
	if args.has("foto"): p.camara = 2; await create_timer(0.5).timeout; root.get_viewport().get_texture().get_image().save_png(args["foto"])
	quit(0)
