extends SceneTree
## Prueba de la pantalla Operaciones del simulador Godot (#pOperaciones y #checkOp de la web): una fila de trabajos por
## vehiculo; Volar abre la ventana de las comprobaciones, todas sin marcar, y Despegar no vale hasta marcarlas todas;
## Cancelar la cierra y al volver a abrirla esta otra vez sin marcar; el UAV de pista tiene su propia lista; con todas
## marcadas, Despegar empieza el trabajo con su vehiculo. Con ventana y --fotos=<prefijo>, guarda capturas.
## Uso (desde la carpeta del repositorio):
##   herramientas/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path simulador_godot --script res://Tests/prueba_menu_operaciones.gd
##   herramientas/godot/Godot_v4.7.2-stable_win64_console.exe --path simulador_godot --resolution 1440x900 --script res://Tests/prueba_menu_operaciones.gd -- --fotos=<prefijo>

var fallos := 0
var prefijo := ""

func _ok(nombre: String, cond: bool, detalle := "") -> void:
	if not cond: fallos += 1
	print("  %s %s %s" % ["OK " if cond else "MAL", nombre, detalle])

func _foto(nombre: String) -> void:
	if prefijo == "": return
	for k in 4: await process_frame
	root.get_texture().get_image().save_png(prefijo + "_" + nombre + ".png")

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--fotos=") and DisplayServer.get_name() != "headless": prefijo = a.substr(8)
	var p = load("res://escenas/principal.tscn").instantiate(); root.add_child(p)
	await create_timer(1.0).timeout
	p.app_pantallas.ir_operaciones(); var O = p.pantallas["pOperaciones"]
	O.sel = "op_patrulla"; O.refrescar(); await process_frame
	var filas := 0
	for c in O.lista.get_children():
		if c is ScrollContainer and not c.is_queued_for_deletion(): filas += 1
	_ok("una fila por vehiculo (Mini Dron HQ, Inspector HQ-3T, Cernicalo XM-7, Grajo MX-2 y el FPV de la carrera)", filas == 5, str(filas))
	await _foto("operaciones")
	_ok("sin la ventana hasta pulsar Volar", not O.check.visible)
	O.b_volar.pressed.emit(); await process_frame
	var cbs: Array = O.check_lista.get_children().filter(func(x): return x is CheckBox and not x.is_queued_for_deletion())
	_ok("Volar abre las comprobaciones, todas sin marcar", O.check.visible and cbs.size() == 6 and cbs.all(func(x): return not x.button_pressed), "%d" % cbs.size())
	_ok("el UAV tiene su lista (la torre de San Javier)", "San Javier" in String(cbs[0].text), cbs[0].text)
	_ok("Despegar no vale sin marcarlas", O.check_si.disabled, O.check_si.text)
	for k in 3: cbs[k].button_pressed = true
	_ok("con 3 de 6 tampoco", O.check_si.disabled and "(3/6)" in O.check_si.text, O.check_si.text)
	await _foto("comprobaciones")
	O._despegar(); _ok("y si se fuerza, no despega", O.check.visible and p.pantalla_actual == "pOperaciones", str(p.pantalla_actual))
	O.check.visible = false; O.b_volar.pressed.emit(); await process_frame
	cbs = O.check_lista.get_children().filter(func(x): return x is CheckBox and not x.is_queued_for_deletion())
	_ok("al volver a abrirla, otra vez sin marcar", cbs.all(func(x): return not x.button_pressed))
	for c in cbs: c.button_pressed = true
	_ok("con todas, Despegar (con el vehiculo elegido)", not O.check_si.disabled and O.check_si.text == "Despegar con el Cernícalo XM-7 →", O.check_si.text)
	O.check.visible = false; O.sel = "op_inspeccion"; O.refrescar(); O.b_volar.pressed.emit(); await process_frame
	cbs = O.check_lista.get_children().filter(func(x): return x is CheckBox and not x.is_queued_for_deletion())
	_ok("el dron tiene la suya (AESA)", "AESA" in String(cbs[0].text), cbs[0].text)
	O.check.visible = false; O.sel = "op_patrulla"; O.refrescar(); O.b_volar.pressed.emit(); await process_frame
	for c in O.check_lista.get_children().filter(func(x): return x is CheckBox and not x.is_queued_for_deletion()): c.button_pressed = true
	O.check_si.pressed.emit()
	for k in 900:
		await process_frame
		if p.pantalla_actual == "" and not p.av.is_empty(): break
	_ok("Despegar empieza la patrulla con el XM-7", p.sesion["escenario"] == "op_patrulla" and p.sesion["avion"] == "XM7" and not O.check.visible, "%s %s" % [p.sesion["escenario"], p.sesion["avion"]])
	print("RESULTADO: ", "todo bien" if fallos == 0 else "%d fallos" % fallos)
	quit(1 if fallos else 0)
