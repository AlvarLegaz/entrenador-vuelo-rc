extends SceneTree
## Capturas del UAV (Cernicalo XM-7) en el simulador Godot entero, las mismas que la web (pruebas de la fase 6): despegue
## automatico desde San Javier, ir a un punto y, a los 110 s, la torreta girada 69 grados y bajada 35, con la camara 3 (EO e
## IR con zoom 4x), la camara de vuelo (1) y la de persecucion (2). Escribe tambien el punto de la cruz. Necesita ventana.
##   herramientas/godot/Godot_v4.7.2-stable_win64_console.exe --path simulador_godot --resolution 1280x760 --script res://pruebas/captura_uav.gd -- --fotos=<prefijo>

const DT := 1.0 / 500
var prefijo := ""

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--fotos="): prefijo = a.substr(8)
	var p = load("res://escenas/principal.tscn").instantiate(); root.add_child(p)
	await create_timer(1.0).timeout
	p.sesion["avion"] = "XM7"; p.sesion["escenario"] = "libre_cartagena"; p.empezar()
	for k in 900:
		await process_frame
		if p.pantalla_actual == "" and not p.av.is_empty(): break
	await create_timer(1.5).timeout
	p.pantalla_actual = "prueba"
	p.lanzar(); p.quitar_freno_aparc(); p.uav_poner("DESPEGUE")
	for i in int(70 / DT): p.paso(DT)
	p.uav_poner("PUNTO", [15500.0, 22500.0])
	for i in int(40 / DT): p.paso(DT)
	p.av["torreta"] = { "pan": 1.2, "tilt": -35 * PI / 180 }; p.mover_torreta(0.0)
	print("modo ", p.piloto.modo, " p ", p.av["p"], " cruz ", p.UAV["cruz"])
	for v in [["torreta_eo", 3, 2, false], ["torreta_ir", 3, 2, true], ["camara1", 1, 0, false], ["camara2", 2, 0, false]]:
		p.camara = v[1]; p.DJI["zoomI"] = v[2]; p.DJI["termica"] = v[3]; p.pantalla_actual = ""; p.pausado = true
		for k in 8: await process_frame
		p.pantalla_actual = "prueba"
		if prefijo != "": root.get_texture().get_image().save_png(prefijo + "_" + v[0] + ".png")
	quit()
