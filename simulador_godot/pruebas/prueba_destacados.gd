extends SceneTree
## Prueba de los puntos de despegue destacados del vuelo libre en el Campo de Cartagena, la misma que
## pruebas/prueba_destacados_web.py en el navegador: los cuatro (CIFP, Los Halcones de la Rambla en El Jimenado, la
## base aerea de San Javier y SABIC) en su sitio; con el Entrenador 1 Los Halcones despega en Los Halcones; el
## Cernicalo XM-7 (de pista) sale siempre de San Javier, y su vuelo empieza en la cabecera 05R.
##   herramientas/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path simulador_godot --script res://pruebas/prueba_destacados.gd

var fallos := 0
var p

func _ok(nombre: String, cond: bool, detalle := "") -> void:
	if not cond: fallos += 1
	print("  %s %s %s" % ["OK " if cond else "MAL", nombre, detalle])

func _buscar(txt: String) -> Dictionary:
	for d in p.destacados_lanz():
		if String(d["nombre"]).contains(txt): return d
	return {}

func _initialize() -> void:
	p = load("res://escenas/principal.tscn").instantiate(); root.add_child(p)
	await create_timer(1.0).timeout
	p.sesion["escenario"] = "libre_cartagena"
	var nombres: Array = p.destacados_lanz().map(func(d): return d["nombre"])
	_ok("los cuatro destacados", nombres == ["CIFP Politécnico", "Los Halcones de la Rambla", "Base aérea de San Javier", "SABIC (La Aljorra)"], str(nombres))
	var Hd: Dictionary = _buscar("Halcones"); var SJ: Dictionary = _buscar("San Javier")
	var h: Array = p.lat_lon_a_ne(p.mundo_datos, Hd["lat"], Hd["lon"]); var sj: Array = p.lat_lon_a_ne(p.mundo_datos, SJ["lat"], SJ["lon"])
	_ok("Los Halcones en El Jimenado y San Javier en la cabecera 05R", absf(h[0] - 16428) < 200 and absf(h[1] - 3290) < 200 and Vector2(sj[0] - 17163.3, sj[1] - 20176.3).length() < 5, "%s / %s" % [str(h), str(sj)])
	p.sesion["avion"] = "E3"; p.ir_lanzamiento(); p.elegir_destacado(Hd)
	_ok("Entrenador 1: Los Halcones despega en Los Halcones", p.sesion["lanz"].get("destacado", "") == "Los Halcones de la Rambla", str(p.sesion["lanz"]))
	p.sesion["avion"] = "XM7"; p.ir_lanzamiento()
	_ok("Cernicalo: al entrar, San Javier", p.sesion["lanz"].get("destacado", "") == "Base aérea de San Javier", str(p.sesion["lanz"]))
	p.elegir_destacado(Hd)
	_ok("Cernicalo: aunque se elija Los Halcones", p.sesion["lanz"].get("destacado", "") == "Base aérea de San Javier", str(p.sesion["lanz"]))
	p.elegir_punto(5000.0, -3000.0)
	_ok("Cernicalo: y aunque se pinche en el mapa", p.sesion["lanz"].get("destacado", "") == "Base aérea de San Javier", str(p.sesion["lanz"]))
	p.empezar()
	for k in 900:
		await process_frame
		if p.pantalla_actual == "" and not p.av.is_empty() and p.modelo != null: break
	var P = p.pista_actual()
	_ok("Cernicalo: el vuelo empieza en la pista de San Javier", P != null and Vector2(p.av["p"][0] - P["n"], p.av["p"][1] - P["e"]).length() < 100, str(p.av["p"]))
	print("RESULTADO: ", "todo bien" if fallos == 0 else "%d fallos" % fallos)
	quit(1 if fallos else 0)
