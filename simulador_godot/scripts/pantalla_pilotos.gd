class_name PantallaPilotos
extends Control
## Acceso (#pAlumno de simulador_web/simulador.html): lo primero al abrir el simulador. La ortofoto de fondo y, en el
## centro, la direccion del servidor del aula, el usuario y la contrasena; "Conectar" entra en el aula (si el usuario no
## existe, ofrece el registro), "Soy nuevo: registrarme" lleva al registro (pantalla_registro.gd) y "Continuar sin
## conexion" deja volar sin guardar los vuelos ni el progreso.

var p: Node
var e_url: LineEdit; var e_usuario: LineEdit; var e_clave: LineEdit
var err: Label
var pendientes: Label

func _init(p_: Node) -> void:
	p = p_; set_anchors_preset(Control.PRESET_FULL_RECT); mouse_filter = Control.MOUSE_FILTER_STOP
	# fondo: como el inicio, la ortofoto con el degradado
	var fondo := ColorRect.new(); fondo.color = Tema.FONDO; fondo.set_anchors_preset(Control.PRESET_FULL_RECT); add_child(fondo)
	if p.orto.size() > 1:
		var foto := TextureRect.new(); foto.texture = p.orto[1]; foto.set_anchors_preset(Control.PRESET_FULL_RECT)
		foto.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; foto.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED; add_child(foto)
	add_child(PantallaInicio._degradado(true)); add_child(PantallaInicio._degradado(false))
	var v := VBoxContainer.new(); v.set_anchors_preset(Control.PRESET_FULL_RECT); v.add_theme_constant_override("separation", 0); add_child(v)
	var centro := CenterContainer.new(); centro.size_flags_horizontal = Control.SIZE_EXPAND_FILL; centro.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var sc := Tema.desplazable(centro); sc.size_flags_vertical = Control.SIZE_EXPAND_FILL; v.add_child(sc)
	# la caja (#accesoCaja)
	var caja := PanelContainer.new(); caja.add_theme_stylebox_override("panel", Tema.caja(Tema.PANEL, Tema.BORDE, 14, 1, 28, 26))
	caja.custom_minimum_size.x = 440; centro.add_child(Tema.margen(caja, 16, 24, 16, 24))
	var c := VBoxContainer.new(); c.add_theme_constant_override("separation", 6); caja.add_child(c)
	var pre := Tema.etiqueta("UxS TRAINER", 11, Tema.ACENTO, true)
	var fv := FontVariation.new(); fv.base_font = Tema.negrita; fv.spacing_glyph = 2; pre.add_theme_font_override("font", fv); c.add_child(pre)
	c.add_child(Tema.etiqueta("Entrar en el aula", 26, Tema.TEXTO, true))
	var txt := Tema.etiqueta("Con tu usuario se guardan tus vuelos y tu progreso en el servidor del aula (el PC del profesor).", 14, Tema.SUAVE, false, true)
	txt.custom_minimum_size.x = 384; c.add_child(txt)
	e_url = _campo(c, "Servidor del aula", "http://192.168.1.20:8080", false)
	e_usuario = _campo(c, "Usuario", "", false); e_usuario.max_length = 60
	e_clave = _campo(c, "Contraseña", "", true); e_clave.max_length = 20
	err = Tema.etiqueta("", 14, Color("#ff8a80"), false, true); err.custom_minimum_size = Vector2(384, 18); c.add_child(Tema.margen(err, 0, 6, 0, 0))
	c.add_child(Tema.boton("Conectar", "BotonPrim", func(): _entrar()))
	c.add_child(Tema.boton("Soy nuevo: registrarme", "", func(): _ir_registro(e_usuario.text.strip_edges())))
	c.add_child(Tema.boton("Continuar sin conexión", "", func(): p.app_pantallas.salir_del_aula(); p.app_pantallas.ir_inicio()))
	var nota := Tema.etiqueta("Sin conexión se vuela igual, pero no se guardan los vuelos ni el progreso.", 13, Tema.SUAVE, false, true)
	nota.custom_minimum_size.x = 384; c.add_child(Tema.margen(nota, 0, 4, 0, 0))
	pendientes = Tema.etiqueta("", 13, Tema.SUAVE, false, true); pendientes.custom_minimum_size.x = 384; c.add_child(pendientes)
	var bp := Tema.boton("Panel del profesor", "", func():
		var u := Aula.normalizar_url(e_url.text)
		if u != "": OS.shell_open(u + "/profesor.html")
		else: err.text = "Escribe la dirección del servidor del aula")
	bp.add_theme_font_size_override("font_size", 13); c.add_child(Tema.margen(bp, 0, 10, 0, 0))
	# pie
	var pie := HBoxContainer.new(); pie.add_child(Tema.espacio())
	pie.add_child(Tema.etiqueta("UxS Trainer · v2 Godot · © 2026 Álvar Legaz Aparicio · todos los derechos reservados", 13, Tema.SUAVE))
	v.add_child(Tema.margen(pie, 48, 12, 48, 18))

func _campo(c: VBoxContainer, titulo: String, ejemplo: String, secreto: bool) -> LineEdit:
	c.add_child(Tema.margen(Tema.etiqueta(titulo, 13, Tema.SUAVE), 0, 8, 0, 0))
	var e := LineEdit.new(); e.placeholder_text = ejemplo; e.secret = secreto; e.custom_minimum_size = Vector2(384, 38)
	e.text_submitted.connect(func(_t): _entrar()); c.add_child(e)
	return e

## La pantalla al llegar (irAcceso): la ultima direccion y el ultimo usuario ya puestos; la contrasena, vacia.
func refrescar(msg := "") -> void:
	e_url.text = p.aula.url; e_usuario.text = p.aula.usuario; e_clave.text = ""; err.text = msg
	var n: int = p.aula._leer_cola().size()
	pendientes.text = ("%d vuelo(s) de este ordenador pendientes de enviar al aula." % n) if n else ""
	(e_clave if e_usuario.text != "" else e_usuario).grab_focus.call_deferred()

## Al registro (irRegistro de la web), con el usuario que haya escrito; hace falta la direccion del aula.
func _ir_registro(usuario: String) -> void:
	var u := Aula.normalizar_url(e_url.text)
	if u == "": err.text = "Escribe la dirección del servidor del aula"; return
	p.aula.url = u; p.app_pantallas.ir_registro(usuario)

func _entrar() -> void:
	var usuario := " ".join(e_usuario.text.split(" ", false))
	if Aula.normalizar_url(e_url.text) == "": err.text = "Escribe la dirección del servidor del aula"; return
	if usuario == "": err.text = "Escribe tu usuario"; return
	if e_clave.text == "": err.text = "Escribe tu contraseña"; return
	err.text = "Conectando…"
	var r: Dictionary = await p.aula.entrar(e_url.text, usuario, e_clave.text)
	if r["ok"]: err.text = ""; p.app_pantallas.dentro_del_aula(r["alumno"]); p.app_pantallas.ir_inicio(); return
	if r["status"] == 404:                           # no existe: los alumnos nuevos se registran (y los aprueba el profesor)
		err.text = String(r["error"])
		if await p.app_pantallas.confirmar("¿Registrarte como «%s»?" % usuario, "No hay ningún alumno con ese usuario en el aula. Si eres nuevo, regístrate: el profesor tiene que aprobar tu cuenta.", "Registrarme"):
			_ir_registro(usuario)
		return
	err.text = String(r["error"])

static func fmt_horas(h: float) -> String:
	var m := int(round(h * 60)); return "%d h %02d min" % [m / 60, m % 60]
