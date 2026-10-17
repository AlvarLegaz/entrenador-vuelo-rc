class_name AppPantallas
extends RefCounted
## Interfaz: construir las pantallas y capas, la navegacion entre ellas y el modal.
## Parte de principal.gd (como js/app/pantallas.js de la web): el estado esta en principal.gd (p).

var p: Principal

func _init(principal: Principal) -> void: p = principal

func _construir_ui() -> void:
	p.ui = CanvasLayer.new(); p.add_child(p.ui)
	var raiz := Control.new(); raiz.set_anchors_preset(Control.PRESET_FULL_RECT); raiz.mouse_filter = Control.MOUSE_FILTER_IGNORE
	raiz.theme = Tema.crear(); p.ui.add_child(raiz)
	p.hud = HudVuelo.new(p); raiz.add_child(p.hud); p.hud.visible = false
	p.hud_dji = HudDji.new(p); raiz.add_child(p.hud_dji); p.hud_dji.visible = false; p.hud.dji = p.hud_dji
	raiz.move_child(p.hud_dji, 0)
	p.hud_fpv = HudFPV.new(p); raiz.add_child(p.hud_fpv); p.hud_fpv.visible = false; raiz.move_child(p.hud_fpv, 0)
	p.hud_uav = HudUav.new(p); raiz.add_child(p.hud_uav); p.hud_uav.visible = false; raiz.move_child(p.hud_uav, 0); p.hud.uav = p.hud_uav
	p.hud_carrera = HudCarrera.new(p); raiz.add_child(p.hud_carrera); p.hud_carrera.visible = false
	p.mira_recon = Control.new(); p.mira_recon.mouse_filter = Control.MOUSE_FILTER_IGNORE; p.mira_recon.visible = false      # reconocimiento con un avion: la mira de la camara 3, con el centro libre
	p.mira_recon.anchor_left = 0.5; p.mira_recon.anchor_right = 0.5; p.mira_recon.anchor_top = 0.5; p.mira_recon.anchor_bottom = 0.5
	p.mira_recon.offset_left = -45; p.mira_recon.offset_right = 45; p.mira_recon.offset_top = -15; p.mira_recon.offset_bottom = 15
	p.mira_recon.draw.connect(func():
		for capa in [[Color.BLACK, 5.0], [Color.WHITE, 2.5]]:
			p.mira_recon.draw_line(Vector2(8, 15), Vector2(36, 15), capa[0], capa[1]); p.mira_recon.draw_line(Vector2(54, 15), Vector2(82, 15), capa[0], capa[1])
			p.mira_recon.draw_line(Vector2(45, 2), Vector2(45, 8), capa[0], capa[1]); p.mira_recon.draw_line(Vector2(45, 22), Vector2(45, 28), capa[0], capa[1]))
	raiz.add_child(p.mira_recon)
	p.condiciones = PantallaMisiones.Condiciones.new(p)
	p.pantallas = { "pInicio": PantallaInicio.new(p), "pAlumno": PantallaPilotos.new(p), "pRegistro": PantallaRegistro.new(p), "pHangar": PantallaHangar.new(p),
				  "pEntrenamientos": PantallaMisiones.Entrenamientos.new(p), "pVolar": PantallaMisiones.Volar.new(p),
				  "pOperaciones": PantallaMisiones.Operaciones.new(p), "pMulti": PantallaMisiones.Multijugador.new(p),
				  "pLanzamiento": PantallaLanzamiento.new(p), "pAjustes": PantallaAjustes.new(p), "pTaller": PantallaTaller.new(p),
				  "pResultado": PantallaResultado.Resultado.new(p), "pProgreso": PantallaResultado.Progreso.new(p) }
	for k in p.pantallas: p.pantallas[k].visible = false; raiz.add_child(p.pantallas[k])
	# multijugador: quien hay en la sala (#salaInfo de la web), abajo a la derecha
	p.sala_info = PanelContainer.new(); p.sala_info.add_theme_stylebox_override("panel", Tema.caja(Color(0, 0, 0, 0.5), Color(0, 0, 0, 0), 10, 0, 12, 8))
	p.sala_info.anchor_left = 1; p.sala_info.anchor_right = 1; p.sala_info.anchor_top = 1; p.sala_info.anchor_bottom = 1
	p.sala_info.offset_right = -16; p.sala_info.offset_bottom = -236; p.sala_info.grow_horizontal = Control.GROW_DIRECTION_BEGIN; p.sala_info.grow_vertical = Control.GROW_DIRECTION_BEGIN
	p.sala_info.mouse_filter = Control.MOUSE_FILTER_IGNORE; p.sala_info.visible = false; raiz.add_child(p.sala_info)
	p.sala_info_rt = Tema.rico("", 12); p.sala_info_rt.fit_content = true; p.sala_info_rt.autowrap_mode = TextServer.AUTOWRAP_OFF; p.sala_info.add_child(p.sala_info_rt)
	# ordenes del profesor (#ordenesHud de la web): ATERRIZA YA y los NOTAM, arriba en el centro
	p.ordenes_hud = VBoxContainer.new(); p.ordenes_hud.add_theme_constant_override("separation", 6); p.ordenes_hud.alignment = BoxContainer.ALIGNMENT_BEGIN
	p.ordenes_hud.anchor_left = 0.5; p.ordenes_hud.anchor_right = 0.5; p.ordenes_hud.offset_top = 64; p.ordenes_hud.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.ordenes_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE; raiz.add_child(p.ordenes_hud)
	# trabajos: el briefing (la imagen de la orden de trabajo) encima del vuelo, con B o el boton del mapa (#briefing de la web)
	p.briefing = PanelContainer.new(); p.briefing.add_theme_stylebox_override("panel", Tema.caja(Color(0, 0, 0, 0.6), Color(1, 1, 1, 0.25), 12, 1, 8, 8))
	p.briefing.visible = false; p.briefing.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND; p.briefing.tooltip_text = "Pulsa B, Esc o haz clic para cerrarlo"
	p.briefing.gui_input.connect(func(ev: InputEvent): if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT: p.app_vuelo.ver_briefing(false))
	var bv := VBoxContainer.new(); bv.add_theme_constant_override("separation", 6); bv.mouse_filter = Control.MOUSE_FILTER_IGNORE; p.briefing.add_child(bv)
	p.briefing_img = TextureRect.new(); p.briefing_img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; p.briefing_img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	p.briefing_img.mouse_filter = Control.MOUSE_FILTER_IGNORE; bv.add_child(p.briefing_img)
	var bl := Tema.rico("[center][color=#9fb3c8]Briefing de la orden de trabajo · [b]B[/b] o clic para cerrar[/color][/center]", 12); bl.fit_content = true; bl.autowrap_mode = TextServer.AUTOWRAP_OFF; bl.mouse_filter = Control.MOUSE_FILTER_IGNORE; bv.add_child(bl)
	raiz.add_child(p.briefing)
	p.pausa = Capas.pausa(p); raiz.add_child(p.pausa["raiz"])
	p.carga = Capas.carga(); raiz.add_child(p.carga["raiz"])
	p.modal = Capas.modal(); raiz.add_child(p.modal["raiz"])
	p.modal["si"].pressed.connect(func(): p.modal["raiz"].visible = false; p._modal_resp.emit(true))
	p.modal["no"].pressed.connect(func(): p.modal["raiz"].visible = false; p._modal_resp.emit(false))
	for c in [p.modal["clave"], p.modal["clave2"]]: c.text_submitted.connect(func(_t): p.modal["raiz"].visible = false; p._modal_resp.emit(true))
	p.dialogo = FileDialog.new(); p.dialogo.access = FileDialog.ACCESS_FILESYSTEM; p.dialogo.use_native_dialog = true
	p.dialogo.file_mode = FileDialog.FILE_MODE_SAVE_FILE; p.dialogo.filters = PackedStringArray(["*.csv ; Caja negra CSV"]); raiz.add_child(p.dialogo)

func confirmar(titulo: String, bb: String, texto_si := "Sí") -> bool:
	p.modal["titulo"].text = titulo; p.modal["texto"].text = bb; p.modal["si"].text = texto_si; p.modal["raiz"].visible = true
	return await p._modal_resp

## La clave de un perfil online (pedirClave de la web): [clave, repetida o null], o null si cancela.
func pedir_clave(titulo: String, texto: String, nueva: bool):
	p.modal["clave"].text = ""; p.modal["clave2"].text = ""; p.modal["clave"].visible = true; p.modal["clave2"].visible = nueva
	p.modal["titulo"].text = titulo; p.modal["texto"].text = texto; p.modal["si"].text = "Guardar" if nueva else "Entrar"; p.modal["raiz"].visible = true
	p.modal["clave"].grab_focus.call_deferred()
	var ok: bool = await p._modal_resp
	p.modal["clave"].visible = false; p.modal["clave2"].visible = false
	return [p.modal["clave"].text, p.modal["clave2"].text if nueva else null] if ok else null

func poner_aviso(txt: String, segundos := 0.0) -> void:
	p.hud.aviso.text = txt
	if segundos > 0:
		await p.get_tree().create_timer(segundos).timeout
		if p.hud.aviso.text == txt: p.hud.aviso.text = ""

func mostrar_carga(titulo: String, texto: String, frac: float) -> void:
	p.carga["raiz"].visible = true; p.carga["titulo"].text = titulo; p.carga["texto"].text = texto; p.carga["barra"].size.x = 358 * frac
	await p.get_tree().process_frame; await p.get_tree().process_frame

## La pantalla de acceso (irAcceso de la web): servidor del aula, usuario y contrasena, o sin conexion.
func ir_acceso(msg := "") -> void:
	p.pantallas["pAlumno"].refrescar(msg); p.mostrar("pAlumno")

## Registro de alumno nuevo (irRegistro de la web): pagina aparte; la cuenta queda pendiente del profesor.
func ir_registro(usuario := "") -> void:
	p.pantallas["pRegistro"].refrescar(p.aula.url, usuario); p.mostrar("pRegistro")

## Perfil (menu o el recuadro encima del dron): dentro del aula, su progreso (con Cerrar sesion); si no, el acceso.
func ir_perfil() -> void:
	if p.sesion["alumno"] != null: p.app_pantallas.ir_progreso("pInicio")
	else: ir_acceso()

func dentro_del_aula(alumno: Dictionary) -> void:
	p.sesion["alumno"] = alumno; p.sesion["sin_registrar"] = false
	Desgaste.cargar(p)                        # el estado de sus vehiculos (horas, averias): desgaste.gd

func salir_del_aula() -> void:
	p.aula.salir(); p.sesion["alumno"] = null; p.sesion["sin_registrar"] = true
	Desgaste.cargar(p)

func cerrar_sesion() -> void:
	var n = p.sesion["alumno"]["nombre"] if p.sesion["alumno"] != null else null
	salir_del_aula(); p.app_multijugador.salir_sala(); ir_acceso(("Sesión de %s cerrada." % n) if n != null else "")

func ir_inicio() -> void:
	p.app_multijugador.salir_sala()                                 # al volver al inicio se sale de la sala multijugador
	Desgaste.cargar(p)                        # el estado de los vehiculos, al dia (el profesor puede haber puesto averias)
	p.pantallas["pInicio"].refrescar(); p.mostrar("pInicio")

func elegir_avion(id: String) -> void:
	p.sesion["avion"] = id; p.app_avion_ajustes._guardar()

## El modo Taller (pantalla_taller.gd): los registros de vuelo de cada vehiculo.
func ir_taller() -> void: p.pantallas["pTaller"].abrir()

func ir_hangar() -> void:
	p.app_avion_ajustes.vehiculo_permitido(); p.pantallas["pHangar"].refrescar(); p.mostrar("pHangar")

func ir_entrenamientos() -> void:
	p.mostrar("pEntrenamientos"); p.pantallas["pEntrenamientos"].refrescar()

# ---- navegacion a las demas pantallas y los trabajos del modo Operaciones (vehOp, opPermite y volarOperacion de
# js/app/menus.js de la web) ----
func ir_operaciones() -> void:
	p.mostrar("pOperaciones"); p.pantallas["pOperaciones"].refrescar()

## Empieza el trabajo elegido: con el dron comercial (las operaciones son suyas), desde su punto de despegue (volarOperacion de la web).
## Si el trabajo deja volarlo con el vehiculo a (operacion.elegir: clases de vehiculo o ids, como el reconocimiento).
func op_permite(O: Dictionary, a: String) -> bool:
	return O.has("elegir") and ((O["elegir"] as Array).has(Escenarios.vehiculo_de(a)) or (O["elegir"] as Array).has(a))

## El vehiculo con el que se vuela el trabajo id (vehOp de la web): el que pide o, si deja elegir, el elegido.
func veh_op(id: String) -> String:
	var O: Dictionary = Escenarios.datos()[id]["operacion"]; var a: String = p.op_vehiculo.get(id, "")
	if O.has("elegir") and p.ids_aviones.has(a) and op_permite(O, a): return a
	return String(O.get("avion", ""))

func volar_operacion(id: String) -> void:
	var E: Dictionary = Escenarios.datos()[id]; var S: Dictionary = E["operacion"]["salida"]
	if p.ids_aviones.has(veh_op(id)): p.sesion["avion"] = veh_op(id)     # el dron que pide el trabajo (o el elegido, en la carrera)
	elif Escenarios.vehiculo_de(p.sesion["avion"]) != "dron":
		for a in p.ids_aviones:
			if Escenarios.vehiculo_de(a) == "dron": p.sesion["avion"] = a; break
	p.sesion["escenario"] = id; p.sesion["lanz"] = { "mundo": p.mundo_datos["id"], "N": float(S["n"]), "E": float(S["e"]), "rumbo": float(S["rumbo"]) }
	p.app_avion_ajustes.guardar_sesion(); p.app_vuelo.empezar()

func ir_volar() -> void:
	p.app_avion_ajustes.vehiculo_permitido()
	if Escenarios.libre(p.sesion["escenario"]): p.sitio_sel = p.sesion["escenario"]
	p.mostrar("pVolar"); p.pantallas["pVolar"].refrescar()

func ir_ajustes(seccion := "") -> void:
	p.pantallas["pAjustes"].refrescar()
	if seccion != "": p.pantallas["pAjustes"].seleccionar(seccion)
	p.mostrar("pAjustes")

func ir_lanzamiento() -> void:
	p.ent.poner_mundo(p.mundo_datos); p.app_evaluacion._lanz_por_defecto()
	if p.app_evaluacion.necesita_pista() and not p.app_evaluacion.destacado_con_pista().is_empty() and p.sesion["lanz"].get("destacado", "") != p.app_evaluacion.destacado_con_pista()["nombre"]:
		var dp: Dictionary = p.app_evaluacion.destacado_con_pista(); var ne := p.app_evaluacion.lat_lon_a_ne(p.mundo_datos, dp["lat"], dp["lon"])
		p.sesion["lanz"] = { "mundo": p.mundo_datos["id"], "N": round(ne[0]), "E": round(ne[1]), "rumbo": float(dp["rumbo"]), "destacado": dp["nombre"] }
	p.mostrar("pLanzamiento"); p.pantallas["pLanzamiento"].preparar()

func ir_progreso(desde: String, alumno = null) -> void:
	p.pantallas["pProgreso"].desde = desde; p.pantallas["pProgreso"].alumno = alumno if alumno != null else p.sesion["alumno"]
	p.mostrar("pProgreso"); p.pantallas["pProgreso"].cargar()
