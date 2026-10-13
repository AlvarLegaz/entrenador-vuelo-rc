extends SceneTree
## Teclado y mando de verdad (sin el piloto automatico de --auto): inyecta teclas, botones y palancas en un vuelo con el
## E1, otro con el Poli-1 (timon de 4 canales) y otro con el DJI y comprueba que el simulador responde. Necesita ventana (no --headless). El mando se simula en el
## dispositivo 0 aunque no haya ninguno conectado (Input acepta los eventos igual).
## Uso: herramientas/godot/Godot_v4.7.2-stable_win64_console.exe --path simulador_godot --script res://pruebas/prueba_entradas.gd

var p: Node
var fallos := 0

func _ok(nombre: String, cond: bool, detalle := "") -> void:
	if not cond: fallos += 1
	print("  %s %s %s" % ["OK " if cond else "MAL", nombre, detalle])

func _tecla(k: int, si: bool) -> void:
	var e := InputEventKey.new(); e.physical_keycode = k; e.keycode = k; e.pressed = si; Input.parse_input_event(e)

func _pulsa(k: int) -> void:
	_tecla(k, true); await process_frame; await process_frame; _tecla(k, false); await process_frame

func _boton(b: int) -> void:
	var e := InputEventJoypadButton.new(); e.device = 0; e.button_index = b; e.pressed = true; Input.parse_input_event(e)
	await create_timer(0.15).timeout; e = e.duplicate(); e.pressed = false; Input.parse_input_event(e); await create_timer(0.1).timeout

func _eje(a: int, v: float) -> void:
	var e := InputEventJoypadMotion.new(); e.device = 0; e.axis = a; e.axis_value = v; Input.parse_input_event(e)

func _volar(avion: String) -> void:
	p.sesion["avion"] = avion; p.sesion["escenario"] = "libre"; p.sesion["sin_registrar"] = true
	p.empezar(); await create_timer(3.0).timeout

func _initialize() -> void:
	p = load("res://escenas/principal.tscn").instantiate(); root.add_child(p)
	await create_timer(1.0).timeout
	print("Avion (E1), teclado:")
	await _volar("E1")
	_tecla(KEY_W, true); await create_timer(1.0).timeout; _tecla(KEY_W, false)
	_ok("W sube el gas", p.av["gases"] > 0.5, "(%.2f)" % p.av["gases"])
	await _pulsa(KEY_L); await create_timer(0.3).timeout
	_ok("L lanza", p.av["estado"] == "volando")
	_tecla(KEY_DOWN, true); await create_timer(0.4).timeout
	_ok("flecha abajo tira", p.mando["pitch"] > 0.9 and p.av["de"] < -0.05, "(palanca %.2f, profundidad %.3f rad)" % [p.mando["pitch"], p.av["de"]]); _tecla(KEY_DOWN, false)
	_tecla(KEY_RIGHT, true); await create_timer(0.4).timeout
	_ok("flecha derecha", p.mando["yaw"] > 0.9, "(%.2f)" % p.mando["yaw"]); _tecla(KEY_RIGHT, false)
	await _pulsa(KEY_2); _ok("2 cambia la camara", p.camara == 2)
	await _pulsa(KEY_I); _ok("I quita los instrumentos", p.sin_instrumentos); await _pulsa(KEY_I)
	await _pulsa(KEY_ESCAPE); _ok("Esc pausa", p.pausado)
	await _pulsa(KEY_ESCAPE); _ok("Esc quita la pausa", not p.pausado)
	await _pulsa(KEY_T); _ok("T abre los controles", p.hud.ayuda.visible)
	await _pulsa(KEY_ESCAPE); _ok("Esc cierra los controles sin pausar", not p.hud.ayuda.visible and not p.pausado)
	await _pulsa(KEY_SPACE); _ok("Espacio corta el gas", p.av["gases"] == 0.0)
	print("Avion (E1), mando:")
	await _boton(JOY_BUTTON_Y); _ok("Y cambia la camara", p.camara == 3, "(camara %d)" % p.camara)
	_eje(JOY_AXIS_RIGHT_Y, 0.8); await create_timer(0.4).timeout
	_ok("palanca derecha hacia ti tira", p.mando["pitch"] > 0.5 and p._mando_usado, "(%.2f)" % p.mando["pitch"])
	_eje(JOY_AXIS_RIGHT_Y, 0.0); _eje(JOY_AXIS_LEFT_Y, -1.0); await create_timer(0.5).timeout
	_ok("palanca izquierda arriba sube el gas", p.av["gases"] > 0.2, "(%.2f)" % p.av["gases"]); _eje(JOY_AXIS_LEFT_Y, 0.0)
	await _boton(JOY_BUTTON_START); _ok("Start pausa", p.pausado)
	await _boton(JOY_BUTTON_START); _ok("Start quita la pausa", not p.pausado)
	_tecla(KEY_UP, true); await create_timer(0.3).timeout
	_ok("el teclado vuelve a mandar al tocarlo", not p._mando_usado and p.mando["pitch"] < -0.5, "(%.2f)" % p.mando["pitch"]); _tecla(KEY_UP, false)
	await _pulsa(KEY_R); _ok("R empieza de nuevo", p.av["estado"] == "en mano")
	print("Poli-1 (4 canales), timon con A / D y la palanca izquierda de lado:")
	p.salir_al_menu(); await create_timer(0.5).timeout
	await _volar("G1")
	_ok("es de 4 canales", p.modelo.tipo == "cuatro", "(tipo %s)" % p.modelo.tipo)
	_tecla(KEY_W, true); await create_timer(1.0).timeout; _tecla(KEY_W, false)
	await _pulsa(KEY_L); await create_timer(0.3).timeout
	_tecla(KEY_D, true); await create_timer(0.4).timeout
	_ok("D mueve el timon a la derecha (y no los alerones)", p.mando["guinada"] > 0.9 and p.av["dr"] > 0.05 and absf(p.av["da"]) < 0.01,
		"(palanca %.2f, timon %.3f rad, alerones %.3f rad)" % [p.mando["guinada"], p.av["dr"], p.av["da"]]); _tecla(KEY_D, false)
	await create_timer(0.4).timeout
	_tecla(KEY_A, true); await create_timer(0.4).timeout
	_ok("A mueve el timon a la izquierda", p.av["dr"] < -0.05, "(%.3f rad)" % p.av["dr"]); _tecla(KEY_A, false)
	await create_timer(0.4).timeout
	_tecla(KEY_RIGHT, true); await create_timer(0.4).timeout
	_ok("flecha derecha mueve los alerones (y no el timon)", p.av["da"] > 0.05 and absf(p.av["dr"]) < 0.01,
		"(alerones %.3f rad, timon %.3f rad)" % [p.av["da"], p.av["dr"]]); _tecla(KEY_RIGHT, false)
	_eje(JOY_AXIS_LEFT_X, -0.8); await create_timer(0.4).timeout
	_ok("palanca izquierda a la izquierda mueve el timon", p._mando_usado and p.mando["guinada"] < -0.5 and p.av["dr"] < -0.05,
		"(palanca %.2f, timon %.3f rad)" % [p.mando["guinada"], p.av["dr"]]); _eje(JOY_AXIS_LEFT_X, 0.0)
	_tecla(KEY_UP, true); await create_timer(0.1).timeout; _tecla(KEY_UP, false)
	await _pulsa(KEY_R)
	print("DJI, teclado y mando:")
	p.salir_al_menu(); await create_timer(0.5).timeout
	await _volar("DJI_MINI")
	print("  (pantalla '%s', modelo %s, estado %s, pausado %s, modal %s)" % [p.pantalla_actual, p.modelo.get_script().get_global_name(), p.av["estado"], p.pausado, p.modal["raiz"].visible])
	await _pulsa(KEY_L); await create_timer(0.3).timeout
	_ok("L arma el dron", p.av["estado"] == "volando")
	_tecla(KEY_W, true); await create_timer(1.5).timeout; _tecla(KEY_W, false)
	_ok("W sube", -p.av["p"][2] - p.ent.altura(p.av["p"][0], p.av["p"][1]) > 0.5, "(altura %.1f m)" % (-p.av["p"][2] - p.ent.altura(p.av["p"][0], p.av["p"][1])))
	var m0: String = p.modelo.modo
	await _pulsa(KEY_M); _ok("M cambia de modo", p.modelo.modo != m0, "(%s -> %s)" % [m0, p.modelo.modo])
	var g0: float = p.av.get("gimbal", -10.0)
	_tecla(KEY_Q, true); await create_timer(0.5).timeout; _tecla(KEY_Q, false)
	_ok("Q baja el gimbal", p.av.get("gimbal", -10.0) < g0 - 1, "(%.0f -> %.0f)" % [g0, p.av.get("gimbal", -10.0)])
	await _boton(JOY_BUTTON_LEFT_SHOULDER); _ok("LB cambia de modo", p.modelo.modo != "N" or m0 == "N")
	await _pulsa(KEY_F); _ok("F hace una foto", p.DJI["fotos"] == 1)
	print("RESULTADO: " + ("todo bien" if fallos == 0 else "%d fallos" % fallos))
	quit(1 if fallos else 0)
