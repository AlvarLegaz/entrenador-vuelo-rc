class_name PantallaPilotos
extends Control
## Perfil (#pAlumno de simulador/simulador.html): pestanas Local (este ordenador) y Online (servidor del aula); sin
## servidor, su direccion o los perfiles locales; con registro, buscar, anadir perfiles, sus tarjetas (horas, vuelos,
## escenarios superados, si estan autorizados para el avion real; el elegido resaltado) con Progreso y la papelera, los
## vuelos pendientes de enviar y la barra de los perfiles locales (guardar o abrir un archivo, exportar e importar).

var p: Node
var d: Dictionary
var b_profesor: Button
var pest_local: Button; var pest_online: Button; var e_url: LineEdit
var sin_aula: PanelContainer
var con_aula: VBoxContainer
var e_buscar: LineEdit; var e_nuevo: LineEdit; var err: Label
var lista: GridAdaptable
var pendientes: Label
var barra_local: VBoxContainer
var alumnos := []
var dialogo: FileDialog

func _init(p_: Node) -> void:
	p = p_; set_anchors_preset(Control.PRESET_FULL_RECT)
	d = Tema.pantalla("Perfil", "Conectando con el aula…"); add_child(d["raiz"])
	b_profesor = Tema.boton("Panel del profesor", "", func(): OS.shell_open(p.aula.url.trim_suffix("/") + "/profesor.html")); d["botones"].add_child(b_profesor)
	d["botones"].add_child(Tema.boton("← Inicio", "", func(): p.ir_inicio()))
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 10); d["cuerpo"].add_child(Tema.desplazable(v))
	# pestanas: perfiles locales u online
	var pest := HBoxContainer.new(); pest.add_theme_constant_override("separation", 4)
	pest_local = Tema.boton("Local · este ordenador", "Pestana", func(): _modo("local")); pest_online = Tema.boton("Online · servidor del aula", "Pestana", func(): _modo("servidor"))
	pest.add_child(pest_local); pest.add_child(pest_online); v.add_child(pest); v.add_child(Tema.linea(0.1))
	# sin servidor
	sin_aula = PanelContainer.new(); sin_aula.add_theme_stylebox_override("panel", Tema.caja(Color(1, 0.78, 0.24, 0.1), Color(1, 0.78, 0.24, 0.35), 12, 1, 16, 12))
	var sv := VBoxContainer.new(); sv.add_theme_constant_override("separation", 8); sin_aula.add_child(sv)
	sv.add_child(Tema.etiqueta("No hay servidor del aula: los perfiles online están en el PC del profesor (aula/servidor_aula.py). Escribe la dirección que indica el servidor, o usa los perfiles locales de este ordenador.", 15, Color("#ffe6a6"), false, true))
	var su := HBoxContainer.new(); su.add_theme_constant_override("separation", 8)
	e_url = LineEdit.new(); e_url.placeholder_text = "http://192.168.1.20:8000"; e_url.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	e_url.text_submitted.connect(func(_t): _conectar())
	su.add_child(e_url); su.add_child(Tema.boton("Conectar", "", _conectar)); sv.add_child(su)
	var sb := HBoxContainer.new(); sb.add_theme_constant_override("separation", 8)
	sb.add_child(Tema.boton("Usar perfiles locales", "BotonPrim", func(): _modo("local")))
	sb.add_child(Tema.boton("Volar sin perfil", "", func(): p.elegir_piloto(null)))
	sv.add_child(sb)
	sv.add_child(Tema.sub("Los perfiles locales guardan vuelos y progreso en este ordenador y, si quieres, en un archivo JSON que puedes copiar a otro ordenador.", 14))
	v.add_child(sin_aula)
	# con aula
	con_aula = VBoxContainer.new(); con_aula.add_theme_constant_override("separation", 10); v.add_child(con_aula)
	var f := HBoxContainer.new(); f.add_theme_constant_override("separation", 12)
	e_buscar = LineEdit.new(); e_buscar.placeholder_text = "Buscar perfil…"; e_buscar.size_flags_horizontal = Control.SIZE_EXPAND_FILL; e_buscar.custom_minimum_size.x = 200
	e_buscar.text_changed.connect(func(_t): pintar_alumnos())
	e_nuevo = LineEdit.new(); e_nuevo.placeholder_text = "Nombre del perfil nuevo"; e_nuevo.max_length = 60; e_nuevo.custom_minimum_size.x = 220
	e_nuevo.text_submitted.connect(func(_t): _anadir())
	f.add_child(e_buscar); f.add_child(e_nuevo); f.add_child(Tema.boton("Añadir", "", _anadir)); var bsp := Tema.boton("Volar sin perfil", "", func(): p.elegir_piloto(null)); bsp.tooltip_text = "Los vuelos no se guardan"; f.add_child(bsp)
	con_aula.add_child(f)
	err = Tema.etiqueta("", 14, Color("#ff8a80")); con_aula.add_child(err)
	lista = Tema.rejilla(260, 10); con_aula.add_child(lista)
	pendientes = Tema.sub("", 14); con_aula.add_child(pendientes)
	barra_local = VBoxContainer.new(); barra_local.add_theme_constant_override("separation", 8); con_aula.add_child(barra_local)
	dialogo = FileDialog.new(); dialogo.access = FileDialog.ACCESS_FILESYSTEM; dialogo.use_native_dialog = true
	dialogo.filters = PackedStringArray(["*.json ; Registro JSON"]); add_child(dialogo)

func _modo(m: String) -> void:
	p.aula._guardar_cfg(m); await p.reiniciar_aula(); refrescar()   # otro registro: reiniciar_aula olvida el perfil de antes

func _conectar() -> void:
	p.aula.url = e_url.text.strip_edges(); await _modo("servidor")

func refrescar() -> void:
	var A: Aula = p.aula; var local := A.modo == "local"
	pest_local.theme_type_variation = "PestanaSel" if local else "Pestana"; pest_online.theme_type_variation = "Pestana" if local else "PestanaSel"
	if e_url.text == "": e_url.text = A.url
	sin_aula.visible = not A.activo; con_aula.visible = A.activo
	b_profesor.visible = A.activo and not local
	d["subtitulo"].text = "Sin servidor del aula" if not A.activo else ("Perfiles locales de este ordenador · elige el tuyo" if local else "Perfiles online del aula %s · elige el tuyo" % A.nombre_aula)
	_pintar_barra_local()
	if A.activo: await cargar_alumnos(); A.vaciar_cola()

func cargar_alumnos() -> void:
	var r: Dictionary = await p.aula.api("GET", "alumnos")
	if r["ok"]: alumnos = r["datos"]; err.text = ""
	else: err.text = "No se pudo leer la lista: " + String(r["error"])
	if p.sesion["alumno"] == null and not p.sesion["sin_registrar"]:               # el ultimo perfil usado
		for a in alumnos: if String(a["id"]) == p.aula.perfil_recordado(): p.sesion["alumno"] = a
	pintar_alumnos()

static func fmt_horas(h: float) -> String:
	var m := int(round(h * 60)); return "%d h %02d min" % [m / 60, m % 60]

func pintar_alumnos() -> void:
	for x in lista.get_children(): x.queue_free()
	var f := Aula.norm(e_buscar.text)
	var vis := alumnos.filter(func(a): return f == "" or Aula.norm(a["nombre"]).contains(f))   # en Godot contains("") es false
	pendientes.text = ("%d vuelo(s) de este ordenador pendientes de enviar." % p.aula.pendientes) if p.aula.pendientes else ""
	if vis.is_empty():
		lista.add_child(Tema.sub("Nadie coincide con la búsqueda." if not alumnos.is_empty() else "Todavía no hay perfiles: añade el primero arriba.", 14)); return
	for a in vis:
		var g: Dictionary = a["progreso"]
		var h := HBoxContainer.new(); h.add_theme_constant_override("separation", 10)
		var cv := VBoxContainer.new(); cv.size_flags_horizontal = Control.SIZE_EXPAND_FILL; cv.add_theme_constant_override("separation", 2)
		cv.add_child(Tema.etiqueta(String(a["nombre"]), 16, Tema.TEXTO, true))
		var det := HBoxContainer.new(); det.add_theme_constant_override("separation", 6)
		det.add_child(Tema.etiqueta("%s · %d vuelos · %d/4 escenarios" % [fmt_horas(g["horas"]), int(g["vuelos"]), int(g["escenarios_superados"])], 12, Tema.SUAVE))
		if a.get("habilitado", false): det.add_child(Tema.chip("avión real", "ok"))
		cv.add_child(det); h.add_child(cv)
		var borrar := Tema.boton("🗑", "BotonPlano"); borrar.tooltip_text = "Quitar de la lista"; borrar.add_theme_color_override("font_color", Color("#cc9988"))
		borrar.pressed.connect(func():
			var ok: bool = await p.confirmar("¿Quitar a %s?" % a["nombre"], "Desaparecerá de esta lista. Sus [b]%d vuelos[/b] y sus horas se conservan, y el profesor puede devolverlo a la lista." % int(g["vuelos"]), "Quitar")
			if not ok: return
			var r: Dictionary = await p.aula.api("DELETE", "alumnos/" + String(a["id"]))
			if not r["ok"]: err.text = r["error"]
			elif p.sesion["alumno"] != null and String(p.sesion["alumno"]["id"]) == String(a["id"]): p.sesion["alumno"] = null; p.aula.recordar_perfil("")
			cargar_alumnos())
		var bp := Tema.boton("Progreso", ""); bp.size_flags_vertical = Control.SIZE_SHRINK_CENTER; bp.add_theme_font_size_override("font_size", 13)
		bp.pressed.connect(func(): p.ir_progreso("pAlumno", a)); h.add_child(bp)
		h.add_child(borrar)
		var t := Tarjeta.new(h, 12, Vector2(14, 12)); t.pulsada.connect(func(): p.elegir_piloto(a))
		t.elegida = p.sesion["alumno"] != null and String(p.sesion["alumno"]["id"]) == String(a["id"])
		lista.add_child(t)

func _anadir() -> void:
	var nombre := e_nuevo.text.strip_edges()
	if nombre == "": return
	var r: Dictionary = await p.aula.api("POST", "alumnos", { "nombre": nombre })
	if r["ok"]: e_nuevo.text = ""; await cargar_alumnos(); err.text = "Añadido: " + String(r["datos"]["nombre"])
	else: err.text = r["error"]

func _dialogo(modo: FileDialog.FileMode, titulo: String, sugerido: String, f: Callable) -> void:
	dialogo.file_mode = modo; dialogo.title = titulo; dialogo.current_file = sugerido
	for c in dialogo.file_selected.get_connections(): dialogo.file_selected.disconnect(c["callable"])
	dialogo.file_selected.connect(f, CONNECT_ONE_SHOT); dialogo.popup_centered_ratio(0.6)

func _pintar_barra_local() -> void:
	for x in barra_local.get_children(): x.queue_free()
	var A: Aula = p.aula
	if A.modo != "local" or not A.activo: return
	var n := (A.datos["alumnos"] as Array).filter(func(a): return not a.get("archivado", false)).size()
	var arch := "Solo en este ordenador (en el perfil del simulador)"
	if A.archivo != "": arch = "Archivo: [b]%s[/b]%s" % [A.archivo.get_file(), (" [color=#ff8a80](%s)[/color]" % A.error_archivo) if A.error_archivo != "" else " (se actualiza tras cada vuelo)"]
	barra_local.add_child(Tema.rico("[color=#9fb3c8]Perfiles locales · %d perfil(es) · %d vuelo(s) · %s[/color]" % [n, (A.datos["vuelos"] as Array).size(), arch], 14))
	var b := HBoxContainer.new(); b.add_theme_constant_override("separation", 8)
	b.add_child(Tema.boton("Guardar en un archivo…", "", func(): _dialogo(FileDialog.FILE_MODE_SAVE_FILE, "Guardar el registro", "entrenador_vuelo_rc_registro.json",
		func(ruta): err.text = A.usar_archivo(ruta, true); refrescar())))
	b.add_child(Tema.boton("Abrir un archivo…", "", func(): _dialogo(FileDialog.FILE_MODE_OPEN_FILE, "Abrir un registro", "",
		func(ruta): err.text = A.usar_archivo(ruta, false); refrescar())))
	b.add_child(Tema.boton("Exportar copia", "", func(): _dialogo(FileDialog.FILE_MODE_SAVE_FILE, "Exportar una copia", "entrenador_vuelo_rc_registro_%s.json" % Time.get_date_string_from_system(),
		func(ruta): A.exportar(ruta))))
	b.add_child(Tema.boton("Importar copia", "", func(): _dialogo(FileDialog.FILE_MODE_OPEN_FILE, "Importar una copia", "",
		func(ruta): err.text = A.importar(ruta); refrescar())))
	barra_local.add_child(b)
