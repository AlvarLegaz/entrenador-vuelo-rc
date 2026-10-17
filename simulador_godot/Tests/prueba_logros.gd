extends SceneTree
## Prueba de los logros en el simulador Godot, con la referencia del navegador (simulador_godot/Tests/referencia_logros_js.json, que
## escribe simulador_web/Tests/prueba_logros_web.py): las insignias son el mismo SVG que las de la web (los 4 logros, conseguidos y
## no), los avisos del ultimo vuelo son los mismos, la seccion Logros de Mi progreso tiene las 4 tarjetas (el robot como
## "Vehiculo secreto") y el robot solo sale en el hangar con los tres logros. Con ventana y --fotos=<prefijo>, guarda
## capturas de la seccion (con un logro y con los tres).
## Uso (desde la carpeta del repositorio):
##   herramientas/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path simulador_godot --script res://Tests/prueba_logros.gd
##   herramientas/godot/Godot_v4.7.2-stable_win64_console.exe --path simulador_godot --resolution 1360x900 --script res://Tests/prueba_logros.gd -- --fotos=<prefijo>

var fallos := 0
var prefijo := ""

func _ok(nombre: String, cond: bool, detalle := "") -> void:
	if not cond: fallos += 1
	print("  %s %s %s" % ["OK " if cond else "MAL", nombre, detalle])

## La seccion Logros sola, en una pantalla de prueba (para contar sus tarjetas y la captura).
func _seccion(p, g: Dictionary, nombre: String) -> Array:
	var cl := CanvasLayer.new(); cl.layer = 120; root.add_child(cl)                                   # por encima de la interfaz
	var capa := ColorRect.new(); capa.color = Tema.FONDO; capa.set_anchors_preset(Control.PRESET_FULL_RECT); cl.add_child(capa)
	var v := VBoxContainer.new(); v.set_anchors_preset(Control.PRESET_FULL_RECT); v.offset_left = 28; v.offset_top = 24; v.offset_right = -28; capa.add_child(v)
	v.add_child(Tema.etiqueta("Logros", 20, Tema.TEXTO, true))
	var rej := PantallaResultado.logros(g, p); v.add_child(rej)
	for k in 4: await process_frame
	if prefijo != "": root.get_texture().get_image().save_png(prefijo + "_" + nombre + ".png")
	var textos := []
	for t in rej.find_children("*", "Label", true, false): textos.append((t as Label).text)
	var n := rej.get_child_count()
	cl.queue_free()
	return [n, textos]

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--fotos=") and DisplayServer.get_name() != "headless": prefijo = a.substr(8)
	var p = load("res://escenas/principal.tscn").instantiate(); root.add_child(p)
	await create_timer(1.0).timeout
	var R: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://Tests/referencia_logros_js.json"))
	var dif := []
	for id in ["ala_fija", "dron", "operaciones", "robot"]:
		for ok in [true, false]:
			var k: String = id + ("_si" if ok else "_no")
			var gd := PantallaResultado.insignia(id, ok).replace(' width="120" height="120"', "")
			if gd != String(R["insignias"][k]): dif.append(k)
	_ok("las 8 insignias son el mismo SVG que en la web", dif.is_empty(), str(dif))
	var img := Image.new()
	_ok("y Godot las dibuja", img.load_svg_from_string(PantallaResultado.insignia("robot", false), 1.0) == OK and img.get_width() == 120)
	var nuevos := PantallaResultado.logros_nuevos(R["antes"], R["progreso"])
	_ok("los mismos avisos del ultimo vuelo", nuevos == R["nuevos"], str(nuevos))
	var r: Array = await _seccion(p, R["antes"], "logros_uno")
	_ok("Mi progreso: 4 tarjetas, el robot como Vehiculo secreto y sin decir que es", r[0] == 4 and r[1].has("Vehículo secreto") and not " ".join(r[1]).to_lower().contains("asalto"), str(r[1].slice(0, 6)))
	_ok("con un logro: 'Conseguido' una vez y lo que falta", r[1].count("✓ Conseguido") == 1 and " ".join(r[1]).contains("Te falta:"))
	r = await _seccion(p, R["progreso"], "logros_todos")
	_ok("con los tres: 3 conseguidos y el vehiculo secreto desbloqueado", r[1].count("✓ Conseguido") == 3 and r[1].has("✓ Desbloqueado"))
	# el robot en el hangar
	p.app_pantallas.salir_del_aula(); _ok("sin conexion, sin robot", not p.app_avion_ajustes.ids_hangar().has("BIPODE"))
	p.sesion["alumno"] = { "id": "x", "nombre": "Prueba", "progreso": R["antes"] }
	p.app_pantallas.elegir_avion("BIPODE"); p.app_pantallas.ir_hangar(); await process_frame
	_ok("sin los tres logros, sin robot (y el hangar vuelve al dron)", not p.app_avion_ajustes.ids_hangar().has("BIPODE") and p.sesion["avion"] == "DJI_MINI", str(p.sesion["avion"]))
	p.sesion["alumno"]["progreso"] = R["progreso"]
	_ok("con los tres, el robot en el hangar", p.app_avion_ajustes.ids_hangar().has("BIPODE"))
	p.app_pantallas.salir_del_aula(); p.app_pantallas.elegir_avion("DJI_MINI")
	print("RESULTADO: ", "todo bien" if fallos == 0 else "%d fallos" % fallos)
	quit(1 if fallos else 0)
