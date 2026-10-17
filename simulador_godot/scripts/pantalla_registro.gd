class_name PantallaRegistro
extends Control
## Registro de alumno nuevo (#pRegistro de simulador_web/simulador.html y irRegistro/enviarRegistro de
## simulador_web/js/app/aula_cliente.js): pagina aparte con nombre, apellidos, correo del centro (@alu.murciaeduca.es o @murciaeduca.es),
## usuario y la contrasena dos veces, en dos columnas (una si la ventana es estrecha). La cuenta queda pendiente hasta
## que la aprueba el profesor en su panel; mientras, se vuela sin conexion.

const DOMINIOS_REGISTRO := ["alu.murciaeduca.es", "murciaeduca.es"]     # los correos de la Consejeria de la Region de Murcia
var p: Node
var aula_l: Label; var err: Label; var cols: GridContainer
var e_nombre: LineEdit; var e_apellidos: LineEdit; var e_correo: LineEdit; var e_usuario: LineEdit; var e_clave: LineEdit; var e_clave2: LineEdit

func _init(p_: Node) -> void:
	p = p_; set_anchors_preset(Control.PRESET_FULL_RECT); mouse_filter = Control.MOUSE_FILTER_STOP
	var fondo := ColorRect.new(); fondo.color = Tema.FONDO; fondo.set_anchors_preset(Control.PRESET_FULL_RECT); add_child(fondo)
	if p.orto.size() > 1:
		var foto := TextureRect.new(); foto.texture = p.orto[1]; foto.set_anchors_preset(Control.PRESET_FULL_RECT)
		foto.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; foto.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED; add_child(foto)
	add_child(PantallaInicio._degradado(true)); add_child(PantallaInicio._degradado(false))
	var v := VBoxContainer.new(); v.set_anchors_preset(Control.PRESET_FULL_RECT); v.add_theme_constant_override("separation", 0); add_child(v)
	var centro := CenterContainer.new(); centro.size_flags_horizontal = Control.SIZE_EXPAND_FILL; centro.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var sc := Tema.desplazable(centro); sc.size_flags_vertical = Control.SIZE_EXPAND_FILL; v.add_child(sc)
	var caja := PanelContainer.new(); caja.add_theme_stylebox_override("panel", Tema.caja(Tema.PANEL, Tema.BORDE, 14, 1, 28, 26))
	caja.custom_minimum_size.x = 620; centro.add_child(Tema.margen(caja, 16, 24, 16, 24))
	var c := VBoxContainer.new(); c.add_theme_constant_override("separation", 6); caja.add_child(c)
	var pre := Tema.etiqueta("UxS TRAINER", 11, Tema.ACENTO, true)
	var fv := FontVariation.new(); fv.base_font = Tema.negrita; fv.spacing_glyph = 2; pre.add_theme_font_override("font", fv); c.add_child(pre)
	c.add_child(Tema.etiqueta("Registro de alumno nuevo", 26, Tema.TEXTO, true))
	var txt := Tema.etiqueta("Tu cuenta queda pendiente hasta que la apruebe el profesor. Después entrarás con tu usuario y tu contraseña.", 14, Tema.SUAVE, false, true)
	txt.custom_minimum_size.x = 564; c.add_child(txt)
	aula_l = Tema.etiqueta("", 13, Tema.SUAVE, false, true); c.add_child(aula_l)
	cols = GridContainer.new(); cols.columns = 2; cols.add_theme_constant_override("h_separation", 14); cols.add_theme_constant_override("v_separation", 0); c.add_child(cols)
	e_nombre = _campo("Nombre", ""); e_apellidos = _campo("Apellidos", "")
	e_correo = _campo("Correo del centro", "nombre@alu.murciaeduca.es o @murciaeduca.es"); e_correo.max_length = 80
	e_usuario = _campo("Usuario", ""); e_clave = _campo("Contraseña", "", true); e_clave2 = _campo("Repite la contraseña", "", true)
	err = Tema.etiqueta("", 14, Color("#ff8a80"), false, true); err.custom_minimum_size = Vector2(564, 18); c.add_child(Tema.margen(err, 0, 6, 0, 0))
	c.add_child(Tema.boton("Enviar solicitud", "BotonPrim", func(): enviar()))
	c.add_child(Tema.boton("Volver", "", func(): p.app_pantallas.ir_acceso()))
	var pie := HBoxContainer.new(); pie.add_child(Tema.espacio())
	pie.add_child(Tema.etiqueta("UxS Trainer · v2 Godot · © 2026 Álvar Legaz Aparicio · todos los derechos reservados", 13, Tema.SUAVE))
	v.add_child(Tema.margen(pie, 48, 12, 48, 18))
	resized.connect(func(): cols.columns = 1 if size.x < 700 else 2)      # una columna si la ventana es estrecha (la web: < 560 px)

func _campo(titulo: String, ejemplo: String, secreto := false) -> LineEdit:
	var b := VBoxContainer.new(); b.size_flags_horizontal = Control.SIZE_EXPAND_FILL; cols.add_child(b)
	b.add_child(Tema.margen(Tema.etiqueta(titulo, 13, Tema.SUAVE), 0, 8, 0, 0))
	var e := LineEdit.new(); e.placeholder_text = ejemplo; e.secret = secreto; e.max_length = 20 if secreto else 60; e.custom_minimum_size = Vector2(275, 38)
	e.text_submitted.connect(func(_t): enviar()); b.add_child(e)
	return e

## La pagina al llegar (irRegistro): el usuario que ya habia escrito en el acceso; lo demas, vacio.
func refrescar(direccion: String, usuario := "") -> void:
	aula_l.text = "Servidor del aula: " + direccion
	for e in [e_nombre, e_apellidos, e_correo, e_clave, e_clave2]: e.text = ""
	e_usuario.text = usuario; err.text = ""
	e_nombre.grab_focus.call_deferred()

## Lo que falta o esta mal en el formulario (el aula lo vuelve a comprobar), o "" (errorRegistro de la web).
static func error_registro(d: Dictionary) -> String:
	if d["nombre"] == "": return "Escribe tu nombre"
	if d["apellidos"] == "": return "Escribe tus apellidos"
	var re := RegEx.new(); re.compile("^[a-z0-9._%+-]+@(" + "|".join(DOMINIOS_REGISTRO.map(func(x): return x.replace(".", "\\."))) + ")$")
	if re.search(d["correo"]) == null: return "El correo tiene que ser el del centro: …@" + " o …@".join(DOMINIOS_REGISTRO)
	if String(d["usuario"]).length() < 2: return "Elige un usuario (2 letras como mínimo)"
	if String(d["clave"]).length() < 4 or String(d["clave"]).length() > 20: return "La contraseña tiene que tener de 4 a 20 caracteres"
	if d["clave"] != d["clave2"]: return "Las dos contraseñas no coinciden"
	return ""

func enviar() -> void:
	var d := { "nombre": e_nombre.text.strip_edges(), "apellidos": e_apellidos.text.strip_edges(), "correo": e_correo.text.strip_edges().to_lower(),
			   "usuario": " ".join(e_usuario.text.split(" ", false)), "clave": e_clave.text, "clave2": e_clave2.text }
	var e := error_registro(d)
	if e != "": err.text = e; return
	err.text = "Enviando…"
	var r: Dictionary = await p.aula.registro(d)
	if r["ok"]: p.app_pantallas.ir_acceso(String(r["mensaje"])); return
	err.text = String(r["error"])
