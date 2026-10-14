extends SceneTree
## Teclado y mando de verdad (sin el piloto automatico de --auto): inyecta teclas, botones y palancas en un vuelo con el
## E1 (con mando de consola y con una emisora AETR, y el asistente), otro con el Poli-1 (timon de 4 canales), otro con
## el dron comercial y otro con el dron FPV (armar, gas, modo, camara) y comprueba que el simulador responde. Necesita ventana
## (no --headless). El mando se simula en el
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

func _ejes_a_cero() -> void:
	for i in MandoCfg.N_EJES: _eje(i, 0.0)

## Emisora EdgeTX por USB (canales AETR en los ejes 0-3, palanca arriba = +1): con el orden AETR la izquierda vertical
## es el gas, sin muelle, y la derecha profundidad y alerones; el orden y el invertir se guardan en user://mando.cfg; el
## asistente asigna las palancas moviendolas. Al final vuelve al mando de consola.
func _emisora() -> void:
	print("Avion (E1), emisora AETR por USB:")
	var M: MandoCfg = p.mando_cfg
	M.poner_perfil("aetr"); p._mando_usado = false
	_ok("AETR pone el gas sin muelle", M.gas == "absoluto")
	_eje(2, -1.0); await create_timer(0.3).timeout
	_eje(2, 1.0); await create_timer(0.3).timeout
	_ok("canal 3 (gas) arriba: gas a tope", p.av["gases"] > 0.99, "(%.2f)" % p.av["gases"])
	_eje(2, 0.2); await create_timer(0.3).timeout
	_ok("canal 3 un poco por encima del centro: 60 % de gas, sin muelle", absf(p.av["gases"] - 0.6) < 0.01, "(%.2f)" % p.av["gases"])
	_eje(2, -1.0); await create_timer(0.3).timeout
	_ok("canal 3 abajo: gas cero", p.av["gases"] < 0.01, "(%.2f)" % p.av["gases"])
	_ok("el gas no mueve el alabeo", absf(p.mando["yaw"]) < 0.01, "(%.2f)" % p.mando["yaw"])
	_eje(1, -0.8); await create_timer(0.3).timeout
	_ok("canal 2 (profundidad) abajo tira", p.mando["pitch"] > 0.5 and absf(p.mando["yaw"]) < 0.01, "(%.2f)" % p.mando["pitch"]); _eje(1, 0.0)
	_eje(0, 0.8); await create_timer(0.3).timeout
	_ok("canal 1 (alerones) a la derecha", p.mando["yaw"] > 0.5 and absf(p.mando["pitch"]) < 0.01, "(%.2f)" % p.mando["yaw"]); _eje(0, 0.0)
	_eje(3, -0.8); await create_timer(0.3).timeout
	_ok("canal 4 (timon) a la izquierda", p.mando["guinada"] < -0.5, "(%.2f)" % p.mando["guinada"]); _eje(3, 0.0)
	_ok("el orden se guarda", MandoCfg.new().perfil == "aetr" and MandoCfg.new().gas == "absoluto")
	M.ejes["ry"]["s"] = -int(M.ejes["ry"]["s"]); M.guardar()
	_ok("invertir se guarda", int(MandoCfg.new().ejes["ry"]["s"]) == 1)
	print("Asistente, emisora con otro orden (gas en el eje 5, timon en el 4 y al reves, alerones 6, profundidad 7):")
	_ejes_a_cero(); _eje(5, -1.0); await process_frame
	M.empezar_asistente(0)
	for m in [[5, 1.0], [4, -1.0], [6, 1.0], [7, 1.0]]:      # eje y extremo (en crudo) de cada paso: gas arriba, derecha, derecha, empujada
		_eje(m[0], -0.6 * m[1]); await create_timer(0.2).timeout; M.paso_asistente(0)
		_eje(m[0], m[1])
		for i in 10:
			await create_timer(0.1).timeout; M.paso_asistente(0)
		_eje(m[0], 0.0); await process_frame
	_ok("el asistente termina", not M.asist["activo"] and M.perfil == "propio", "(paso %s)" % str(M.asist.get("paso")))
	var e := M.ejes
	_ok("y asigna cada eje con su sentido", int(e["ly"]["i"]) == 5 and int(e["ly"]["s"]) == -1 and int(e["lx"]["i"]) == 4 and int(e["lx"]["s"]) == -1 		and int(e["rx"]["i"]) == 6 and int(e["rx"]["s"]) == 1 and int(e["ry"]["i"]) == 7 and int(e["ry"]["s"]) == -1, str(e))
	_ok("y se guarda", MandoCfg.new().perfil == "propio" and int(MandoCfg.new().ejes["ly"]["i"]) == 5)
	_ejes_a_cero(); M.poner_perfil("consola"); p._mando_usado = false; await create_timer(0.1).timeout

func _volar(avion: String) -> void:
	p.sesion["avion"] = avion; p.sesion["escenario"] = "libre"; p.sesion["sin_registrar"] = true
	p.empezar(); await create_timer(3.0).timeout

func _initialize() -> void:
	# la prueba cambia el orden de los ejes: la configuracion del mando del usuario se guarda y se deja como estaba
	var cfg_antes := FileAccess.get_file_as_bytes(MandoCfg.F_CFG) if FileAccess.file_exists(MandoCfg.F_CFG) else PackedByteArray()
	p = load("res://escenas/principal.tscn").instantiate(); root.add_child(p)
	p.mando_cfg.poner_perfil("consola")
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
	await _emisora()
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
	print("dron comercial, teclado y mando:")
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
	await _pulsa(KEY_R); await create_timer(0.3).timeout
	p.mando_cfg.poner_perfil("consola")
	_eje(JOY_AXIS_LEFT_X, 0.95); _eje(JOY_AXIS_LEFT_Y, 1.0); _eje(JOY_AXIS_RIGHT_X, -0.95); _eje(JOY_AXIS_RIGHT_Y, 1.0)   # CSC: abajo y hacia dentro
	await create_timer(0.25).timeout
	_ok("CSC: un cuarto de segundo no basta", p.av["estado"] == "en mano")
	await create_timer(0.6).timeout
	_ok("CSC: medio segundo arranca los motores (en el suelo)", p.av["estado"] == "volando" and p.av.get("posado", false), "(%s)" % p.av["estado"])
	_ejes_a_cero(); await create_timer(0.2).timeout
	print("Dron FPV, teclado y mando:")
	p.salir_al_menu(); await create_timer(0.5).timeout
	await _volar("FPV")
	_ok("camara FPV (3) y OSD de Betaflight (no la app del dron comercial)", p.camara == 3 and p.hud_fpv.visible and not p.hud_dji.visible and p.modelo.modo == "ANGLE")
	_tecla(KEY_W, true); await create_timer(0.3).timeout; _tecla(KEY_W, false)
	await _pulsa(KEY_L); await create_timer(0.2).timeout
	_ok("con el gas arriba L no arma", p.av["estado"] == "en mano", "(gas %.2f)" % p.av["gases"])
	await _pulsa(KEY_SPACE)
	await _pulsa(KEY_L); await create_timer(0.3).timeout
	_ok("L arma con el gas abajo y los motores giran al ralenti", p.av["estado"] == "volando" and p.av["armado"] and p.av["motores"][0] > 0.03,
		"(motor 1 al %.3f)" % p.av["motores"][0])
	_ok("OSD: ARMED", p.hud_fpv.arm.text == "ARMED", "(%s)" % p.hud_fpv.arm.text)
	_tecla(KEY_W, true); await create_timer(1.3).timeout; _tecla(KEY_W, false)
	var g1: float = p.av["gases"]; await create_timer(0.5).timeout
	_ok("W sube el gas y se queda (sin muelle)", g1 > 0.35 and absf(p.av["gases"] - g1) < 1e-6, "(%.2f)" % p.av["gases"])
	await create_timer(1.0).timeout
	var h: float = -p.av["p"][2] - p.ent.altura(p.av["p"][0], p.av["p"][1])
	_ok("despega", h > 0.5, "(altura %.1f m)" % h)
	p.av["gases"] = 0.33
	await _pulsa(KEY_M); _ok("M cambia a HORIZON", p.modelo.modo == "HORIZON", "(%s)" % p.modelo.modo)
	_tecla(KEY_RIGHT, true); await create_timer(0.4).timeout
	_ok("flecha derecha alabea", p.mando["yaw"] > 0.9 and p.av["cmd"]["alabeo"] > 0.5, "(palanca %.2f, consigna %.2f)" % [p.mando["yaw"], p.av["cmd"]["alabeo"]]); _tecla(KEY_RIGHT, false)
	await _pulsa(KEY_2); _ok("2: camara de persecucion", p.camara == 2)
	await _pulsa(KEY_3); _ok("3: camara FPV", p.camara == 3 and p.avion3d.camara_fpv)
	await _boton(JOY_BUTTON_LEFT_SHOULDER); _ok("LB cambia a ACRO", p.modelo.modo == "ACRO", "(%s)" % p.modelo.modo)
	await _boton(JOY_BUTTON_RIGHT_SHOULDER); _ok("RB cambia la camara", p.camara == 1, "(camara %d)" % p.camara)
	var g2: float = p.av["gases"]
	_eje(JOY_AXIS_LEFT_Y, -1.0); await create_timer(0.4).timeout; _eje(JOY_AXIS_LEFT_Y, 0.0)
	_ok("palanca izquierda arriba sube el gas", p.av["gases"] > g2 + 0.1, "(%.2f -> %.2f)" % [g2, p.av["gases"]])
	await _boton(JOY_BUTTON_A); _ok("A desarma", not p.av["armado"])
	await _pulsa(KEY_R); _ok("R empieza de nuevo (desarmado en el suelo)", p.av["estado"] == "en mano" and not p.av["armado"])
	print("Dron FPV con mando de consola (palanca de gas con muelle: el centro es el estacionario):")
	p.mando_cfg.poner_perfil("consola")
	var alt := func() -> float: return -p.av["p"][2] - p.ent.altura(p.av["p"][0], p.av["p"][1])
	_eje(JOY_AXIS_RIGHT_X, 0.3); await create_timer(0.1).timeout; _eje(JOY_AXIS_RIGHT_X, 0.0)      # el mando manda
	await _boton(JOY_BUTTON_A); await create_timer(1.0).timeout
	_ok("armado con la palanca en reposo no despega", p.av["armado"] and alt.call() < 0.3, "(gas %.2f, altura %.2f m)" % [p.av["gases"], alt.call()])
	_eje(JOY_AXIS_LEFT_Y, -0.3); await create_timer(1.5).timeout; _eje(JOY_AXIS_LEFT_Y, 0.0)
	var h1: float = alt.call()
	_ok("un toque arriba sube despacio", h1 > 0.5 and h1 < 8.0, "(%.1f m en 1,5 s)" % h1)
	var vz := func() -> float: return -Cuat.rot(p.av["q"], p.av["v"])[2]
	var v1: float = vz.call(); await create_timer(2.5).timeout; var v2: float = vz.call(); var h3: float = alt.call()
	# soltando, el gas vuelve al del estacionario: sigue subiendo por la inercia (un FPV no mantiene la altura), pero cada
	# vez mas despacio (al subir empuja menos) y no se escapa
	_ok("soltando vuelve al estacionario y la subida se frena", absf(p.av["gases"] - 0.30) < 0.01 and v2 < v1 and h3 < 20.0,
		"(gas %.2f, subida %.1f -> %.1f m/s, %.1f m)" % [p.av["gases"], v1, v2, h3])
	_eje(JOY_AXIS_LEFT_Y, 1.0); await create_timer(0.3).timeout
	_ok("abajo del todo, gas cero", p.av["gases"] < 0.01, "(%.2f)" % p.av["gases"]); _eje(JOY_AXIS_LEFT_Y, 0.0)
	await _pulsa(KEY_R)
	if cfg_antes.is_empty(): DirAccess.remove_absolute(ProjectSettings.globalize_path(MandoCfg.F_CFG))
	else: FileAccess.open(MandoCfg.F_CFG, FileAccess.WRITE).store_buffer(cfg_antes)
	print("RESULTADO: " + ("todo bien" if fallos == 0 else "%d fallos" % fallos))
	quit(1 if fallos else 0)
