class_name Tema
extends RefCounted
## Estilo de la interfaz, el MISMO que la hoja de estilos de simulador/simulador.html (variables :root): colores, letra
## (Segoe UI, como el navegador en Windows), botones (normal, principal amarillo, peligro, grande), paneles «capa»,
## campos, desplegables, casillas, barras deslizantes y barras de desplazamiento. Mas unas funciones para construir
## las pantallas con los mismos bloques que el HTML (cabecera, cuerpo, pie, capa, fila, tabla de datos, chips...).

const FONDO := Color("#0b1521")
const PANEL := Color(16 / 255.0, 30 / 255.0, 46 / 255.0, 0.86)
const PANEL2 := Color(22 / 255.0, 40 / 255.0, 60 / 255.0, 0.92)
const BORDE := Color("#2a4766")
const TEXTO := Color("#e8eef5")
const SUAVE := Color("#9fb3c8")
const ACENTO := Color("#ffc83d")
const OK := Color("#58d06a")
const MAL := Color("#ff6e66")
const AZUL := Color("#4fb3ff")
const NARANJA := Color("#ffb74d")
const RADIO := 14

static var tema: Theme
static var fuente: SystemFont
static var negrita: SystemFont
static var _iconos := {}

static func _fuente(peso: int) -> SystemFont:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Segoe UI", "Noto Sans", "Arial", "sans-serif"])
	f.font_weight = peso; f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	return f

## Caja con fondo, borde y esquinas redondeadas (como border-radius y border de CSS).
static func caja(fondo: Color, borde := Color(0, 0, 0, 0), radio := 10, grosor := 1, pad_x := 0.0, pad_y := 0.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fondo; s.border_color = borde
	s.set_border_width_all(grosor if borde.a > 0 else 0); s.set_corner_radius_all(radio)
	s.content_margin_left = pad_x; s.content_margin_right = pad_x; s.content_margin_top = pad_y; s.content_margin_bottom = pad_y
	s.anti_aliasing = true
	return s

static func crear() -> Theme:
	if tema != null: return tema
	fuente = _fuente(400); negrita = _fuente(700)
	var t := Theme.new()
	t.default_font = fuente; t.default_font_size = 15
	t.set_color("font_color", "Label", TEXTO)
	# ---- botones (.btn): fondo blanco al 8 %, borde al 18 %, radio 10, 10 x 18 de relleno ----
	var bn := caja(Color(1, 1, 1, 0.08), Color(1, 1, 1, 0.18), 10, 1, 18, 9)
	var bh := caja(Color(1, 1, 1, 0.14), Color(1, 1, 1, 0.18), 10, 1, 18, 9)
	var bd := caja(Color(1, 1, 1, 0.04), Color(1, 1, 1, 0.1), 10, 1, 18, 9)
	for tipo in ["Button", "OptionButton", "MenuButton"]:
		t.set_stylebox("normal", tipo, bn); t.set_stylebox("hover", tipo, bh); t.set_stylebox("pressed", tipo, bh)
		t.set_stylebox("disabled", tipo, bd); t.set_stylebox("focus", tipo, StyleBoxEmpty.new())
		t.set_color("font_color", tipo, TEXTO); t.set_color("font_hover_color", tipo, TEXTO); t.set_color("font_pressed_color", tipo, TEXTO)
		t.set_color("font_focus_color", tipo, TEXTO); t.set_color("font_disabled_color", tipo, Color(TEXTO, 0.4))
	# desplegables y campos (select, input): fondo negro al 35 %, borde azul, radio 8
	var campo := caja(Color(0, 0, 0, 0.35), BORDE, 8, 1, 12, 7)
	var campo_h := caja(Color(0, 0, 0, 0.45), Color(BORDE, 1).lightened(0.2), 8, 1, 12, 7)
	t.set_stylebox("normal", "OptionButton", campo); t.set_stylebox("hover", "OptionButton", campo_h); t.set_stylebox("pressed", "OptionButton", campo_h)
	t.set_stylebox("normal", "LineEdit", campo); t.set_stylebox("focus", "LineEdit", caja(Color(0, 0, 0, 0.35), ACENTO, 8, 1, 12, 7))
	t.set_stylebox("read_only", "LineEdit", campo)
	t.set_color("font_color", "LineEdit", TEXTO); t.set_color("font_placeholder_color", "LineEdit", Color(SUAVE, 0.7))
	t.set_color("caret_color", "LineEdit", ACENTO); t.set_color("selection_color", "LineEdit", Color(ACENTO, 0.35))
	t.set_font_size("font_size", "LineEdit", 14); t.set_font_size("font_size", "OptionButton", 14)
	# menu de los desplegables
	t.set_stylebox("panel", "PopupMenu", caja(Color("#13243a"), BORDE, 8, 1, 4, 4))
	t.set_stylebox("hover", "PopupMenu", caja(Color(1, 1, 1, 0.1), Color(0, 0, 0, 0), 6))
	t.set_color("font_color", "PopupMenu", TEXTO); t.set_color("font_hover_color", "PopupMenu", TEXTO); t.set_font_size("font_size", "PopupMenu", 14)
	# variantes de boton: principal (amarillo), peligro (rojo oscuro), grande y principal grande
	t.add_type("BotonPrim"); t.set_type_variation("BotonPrim", "Button")
	t.set_stylebox("normal", "BotonPrim", caja(ACENTO, ACENTO, 10, 1, 18, 9)); t.set_stylebox("hover", "BotonPrim", caja(Color("#ffd666"), ACENTO, 10, 1, 18, 9))
	t.set_stylebox("pressed", "BotonPrim", caja(Color("#ffd666"), ACENTO, 10, 1, 18, 9)); t.set_stylebox("disabled", "BotonPrim", caja(Color(ACENTO, 0.4), Color(ACENTO, 0.4), 10, 1, 18, 9))
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]: t.set_color(k, "BotonPrim", Color("#1a1400"))
	t.set_font("font", "BotonPrim", negrita)
	t.add_type("BotonPrimGrande"); t.set_type_variation("BotonPrimGrande", "BotonPrim")
	t.set_stylebox("normal", "BotonPrimGrande", caja(ACENTO, ACENTO, 12, 1, 28, 13)); t.set_stylebox("hover", "BotonPrimGrande", caja(Color("#ffd666"), ACENTO, 12, 1, 28, 13))
	t.set_stylebox("pressed", "BotonPrimGrande", caja(Color("#ffd666"), ACENTO, 12, 1, 28, 13)); t.set_stylebox("disabled", "BotonPrimGrande", caja(Color(ACENTO, 0.4), Color(ACENTO, 0.4), 12, 1, 28, 13))
	t.set_font_size("font_size", "BotonPrimGrande", 18)
	t.add_type("BotonPeligro"); t.set_type_variation("BotonPeligro", "Button")
	t.set_stylebox("normal", "BotonPeligro", caja(Color("#5a1e1e"), Color("#8a2c2c"), 10, 1, 18, 9)); t.set_stylebox("hover", "BotonPeligro", caja(Color("#6e2626"), Color("#8a2c2c"), 10, 1, 18, 9))
	t.set_stylebox("pressed", "BotonPeligro", caja(Color("#6e2626"), Color("#8a2c2c"), 10, 1, 18, 9))
	# pestanas (.pestanas button) y menu lateral de ajustes (#ajustesMenu button): planos, el elegido resaltado
	t.add_type("BotonPlano"); t.set_type_variation("BotonPlano", "Button")
	var plano := StyleBoxEmpty.new(); plano.content_margin_left = 14; plano.content_margin_right = 14; plano.content_margin_top = 9; plano.content_margin_bottom = 9
	for k in ["normal", "hover", "pressed", "disabled"]: t.set_stylebox(k, "BotonPlano", plano)
	t.set_color("font_color", "BotonPlano", SUAVE); t.set_color("font_hover_color", "BotonPlano", TEXTO); t.set_color("font_pressed_color", "BotonPlano", TEXTO)
	t.add_type("BotonPlanoSel"); t.set_type_variation("BotonPlanoSel", "Button")
	var sel := caja(Color(1, 1, 1, 0.08), Color(1, 1, 1, 0.12), 10, 1, 14, 9)
	for k in ["normal", "hover", "pressed"]: t.set_stylebox(k, "BotonPlanoSel", sel)
	t.add_type("Pestana"); t.set_type_variation("Pestana", "Button")
	var pn := StyleBoxFlat.new(); pn.bg_color = Color(0, 0, 0, 0); pn.content_margin_left = 16; pn.content_margin_right = 16; pn.content_margin_top = 10; pn.content_margin_bottom = 10
	pn.border_width_bottom = 2; pn.border_color = Color(0, 0, 0, 0)
	for k in ["normal", "hover", "pressed"]: t.set_stylebox(k, "Pestana", pn)
	t.set_color("font_color", "Pestana", SUAVE); t.set_color("font_hover_color", "Pestana", TEXTO); t.set_color("font_pressed_color", "Pestana", TEXTO)
	t.add_type("PestanaSel"); t.set_type_variation("PestanaSel", "Pestana")
	var ps := pn.duplicate(); ps.border_color = ACENTO
	for k in ["normal", "hover", "pressed"]: t.set_stylebox(k, "PestanaSel", ps)
	t.set_color("font_color", "PestanaSel", TEXTO)
	# tarjetas pulsables (.avCarta, .mision, .sitio, .alumno, .menu-btn): fondo al 5 %, borde al 12 %; la elegida, amarilla
	t.add_type("Tarjeta"); t.set_type_variation("Tarjeta", "Button")
	t.set_stylebox("normal", "Tarjeta", caja(Color(1, 1, 1, 0.05), Color(1, 1, 1, 0.12), 12, 1, 14, 12))
	t.set_stylebox("hover", "Tarjeta", caja(Color(1, 1, 1, 0.1), Color(1, 0.78, 0.24, 0.5), 12, 1, 14, 12))
	t.set_stylebox("pressed", "Tarjeta", caja(Color(1, 1, 1, 0.1), Color(1, 0.78, 0.24, 0.5), 12, 1, 14, 12))
	t.add_type("TarjetaSel"); t.set_type_variation("TarjetaSel", "Tarjeta")
	for k in ["normal", "hover", "pressed"]: t.set_stylebox(k, "TarjetaSel", caja(Color(1, 0.78, 0.24, 0.12), ACENTO, 12, 2, 14, 12))
	t.add_type("BotonMenu"); t.set_type_variation("BotonMenu", "Button")
	t.set_stylebox("normal", "BotonMenu", caja(Color(1, 1, 1, 0.06), Color(1, 1, 1, 0.12), 14, 1, 18, 14))
	t.set_stylebox("hover", "BotonMenu", caja(Color(1, 0.78, 0.24, 0.14), Color(1, 0.78, 0.24, 0.5), 14, 1, 18, 14))
	t.set_stylebox("pressed", "BotonMenu", caja(Color(1, 0.78, 0.24, 0.14), Color(1, 0.78, 0.24, 0.5), 14, 1, 18, 14))
	# paneles (.capa) y chips
	t.add_type("Capa"); t.set_type_variation("Capa", "PanelContainer")
	t.set_stylebox("panel", "Capa", caja(PANEL, BORDE, RADIO, 1, 18, 16))
	t.add_type("Chip"); t.set_type_variation("Chip", "PanelContainer")
	t.set_stylebox("panel", "Chip", caja(Color(1, 1, 1, 0.1), Color(0, 0, 0, 0), 12, 0, 10, 3))
	# casillas: el check con el acento
	t.set_color("font_color", "CheckBox", TEXTO); t.set_color("font_hover_color", "CheckBox", TEXTO); t.set_color("font_pressed_color", "CheckBox", TEXTO)
	for k in ["normal", "hover", "pressed", "focus", "hover_pressed"]: t.set_stylebox(k, "CheckBox", StyleBoxEmpty.new())
	t.set_icon("checked", "CheckBox", _icono_casilla(true)); t.set_icon("unchecked", "CheckBox", _icono_casilla(false))
	t.set_icon("checked_disabled", "CheckBox", _icono_casilla(true, 0.4)); t.set_icon("unchecked_disabled", "CheckBox", _icono_casilla(false, 0.4))
	# barras deslizantes (input type=range con accent-color)
	t.set_stylebox("slider", "HSlider", caja(Color(1, 1, 1, 0.18), Color(0, 0, 0, 0), 3, 0, 0, 2))
	t.set_stylebox("grabber_area", "HSlider", caja(ACENTO, Color(0, 0, 0, 0), 3, 0, 0, 2))
	t.set_stylebox("grabber_area_highlight", "HSlider", caja(ACENTO, Color(0, 0, 0, 0), 3, 0, 0, 2))
	t.set_icon("grabber", "HSlider", _icono_punto(8, ACENTO)); t.set_icon("grabber_highlight", "HSlider", _icono_punto(9, Color("#ffd666")))
	t.set_icon("grabber_disabled", "HSlider", _icono_punto(8, Color(SUAVE, 0.5)))
	# barras de desplazamiento finas (::-webkit-scrollbar)
	for tipo in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", tipo, StyleBoxEmpty.new())
		var g := caja(BORDE, Color(0, 0, 0, 0), 5); g.content_margin_left = 5; g.content_margin_right = 5
		t.set_stylebox("grabber", tipo, g); t.set_stylebox("grabber_highlight", tipo, caja(BORDE.lightened(0.15), Color(0, 0, 0, 0), 5))
		t.set_stylebox("grabber_pressed", tipo, caja(BORDE.lightened(0.25), Color(0, 0, 0, 0), 5))
	# SpinBox (input type=number)
	t.set_stylebox("normal", "LineEdit", campo)
	# texto con formato (RichTextLabel): mismos colores
	t.set_color("default_color", "RichTextLabel", TEXTO); t.set_font("bold_font", "RichTextLabel", negrita)
	t.set_font_size("normal_font_size", "RichTextLabel", 15); t.set_font_size("bold_font_size", "RichTextLabel", 15)
	t.set_stylebox("normal", "RichTextLabel", StyleBoxEmpty.new())
	t.set_stylebox("panel", "TooltipPanel", caja(Color("#13243a"), BORDE, 6, 1, 8, 5)); t.set_color("font_color", "TooltipLabel", TEXTO)
	tema = t
	return t

static func _icono_casilla(marcada: bool, alfa := 1.0) -> ImageTexture:
	var n := 18; var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var borde := x < 2 or y < 2 or x >= n - 2 or y >= n - 2
			var c := Color(0, 0, 0, 0)
			if marcada: c = ACENTO
			elif borde: c = Color(SUAVE, 0.9)
			else: c = Color(0, 0, 0, 0.35)
			if marcada:      # la marca de comprobacion en oscuro
				var en_marca := (x >= 4 and x <= 7 and absi(y - (x + 5)) <= 1) or (x >= 7 and x <= 14 and absi(y - (19 - x)) <= 1)
				if en_marca: c = Color("#1a1400")
			c.a *= alfa; img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)

static func _icono_punto(r: int, color: Color) -> ImageTexture:
	var n := 2 * r + 2; var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var d := Vector2(x + 0.5 - n / 2.0, y + 0.5 - n / 2.0).length()
			img.set_pixel(x, y, Color(color, clampf(r + 0.5 - d, 0, 1)))
	return ImageTexture.create_from_image(img)

## Icono SVG (los mismos de la web) como textura, a la escala pedida. Se guarda en cache por texto y escala.
static func svg(texto: String, escala := 1.0) -> ImageTexture:
	var clave := str(texto.hash()) + "@" + str(escala)
	if _iconos.has(clave): return _iconos[clave]
	var img := Image.new()
	if img.load_svg_from_string(texto, escala) != 0: img = Image.create(8, 8, false, Image.FORMAT_RGBA8)
	var tex := ImageTexture.create_from_image(img)
	_iconos[clave] = tex
	return tex

# =====================================================================
#  BLOQUES DE LAS PANTALLAS (los del HTML)
# =====================================================================
static func etiqueta(texto: String, tam := 15, color := TEXTO, negr := false, ajuste := false) -> Label:
	var l := Label.new(); l.text = texto
	l.add_theme_font_size_override("font_size", tam); l.add_theme_color_override("font_color", color)
	if negr: l.add_theme_font_override("font", negrita)
	if ajuste: l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

static func sub(texto: String, tam := 14) -> Label:
	return etiqueta(texto, tam, SUAVE, false, true)

## Texto con formato (BBCode): para los parrafos con negritas y colores del HTML.
## Un texto que viene de fuera (nombres de salas y de pilotos, mensajes del servidor) dentro de un RichTextLabel: sin BBCode.
static func bb(s: String) -> String: return s.replace("[", "[lb]")

static func rico(bb := "", tam := 15) -> RichTextLabel:
	var r := RichTextLabel.new(); r.bbcode_enabled = true; r.fit_content = true; r.scroll_active = false
	r.add_theme_font_size_override("normal_font_size", tam); r.add_theme_font_size_override("bold_font_size", tam)
	r.text = bb; r.mouse_filter = Control.MOUSE_FILTER_PASS
	return r

## Titulo de seccion dentro de una capa (.capa h2): amarillo, mayusculas, letra espaciada.
static func h2(texto: String) -> Label:
	var l := etiqueta(texto.to_upper(), 15, ACENTO, true)
	var fv := FontVariation.new(); fv.base_font = negrita; fv.spacing_glyph = 1
	l.add_theme_font_override("font", fv)
	return l

static func boton(texto: String, tipo := "", al_pulsar: Callable = Callable()) -> Button:
	var b := Button.new(); b.text = texto
	if tipo != "": b.theme_type_variation = tipo
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND; b.focus_mode = Control.FOCUS_NONE
	if al_pulsar.is_valid(): b.pressed.connect(al_pulsar)
	return b

## Panel .capa con una caja vertical dentro; devuelve [panel, caja].
static func capa(sep := 8) -> Array:
	var pc := PanelContainer.new(); pc.theme_type_variation = "Capa"
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", sep); pc.add_child(v)
	return [pc, v]

## Fila etiqueta + control (.fila label con min-width 140 px).
static func fila(texto: String, control: Control, ancho_etiqueta := 150.0) -> HBoxContainer:
	var h := HBoxContainer.new(); h.add_theme_constant_override("separation", 12)
	var l := etiqueta(texto, 14, SUAVE); l.custom_minimum_size.x = ancho_etiqueta
	if control is BoxContainer: control.size_flags_horizontal = Control.SIZE_EXPAND_FILL     # filas compuestas: todo el ancho
	h.add_child(l); h.add_child(control)
	return h

static func desplegable(opciones: Array, elegida := 0) -> OptionButton:
	var o := OptionButton.new()
	for t in opciones: o.add_item(t)
	o.selected = elegida; o.size_flags_horizontal = Control.SIZE_EXPAND_FILL; o.focus_mode = Control.FOCUS_NONE
	o.fit_to_longest_item = false; o.clip_text = true
	return o

static func deslizador(minv: float, maxv: float, paso: float, valor: float) -> HSlider:
	var s := HSlider.new(); s.min_value = minv; s.max_value = maxv; s.step = paso; s.value = valor
	s.custom_minimum_size = Vector2(160, 20); s.size_flags_horizontal = Control.SIZE_EXPAND_FILL; s.focus_mode = Control.FOCUS_NONE
	return s

static func casilla(texto: String, marcada: bool) -> CheckBox:
	var c := CheckBox.new(); c.text = texto; c.button_pressed = marcada; c.focus_mode = Control.FOCUS_NONE
	c.add_theme_font_size_override("font_size", 13); c.add_theme_color_override("font_color", SUAVE)
	return c

static func chip(texto: String, tipo := "") -> PanelContainer:
	var pc := PanelContainer.new(); pc.theme_type_variation = "Chip"
	var colores := { "ok": [Color(0.345, 0.816, 0.416, 0.2), Color("#9be59f")], "mal": [Color(1, 0.43, 0.4, 0.2), Color("#ffb4ab")],
					 "acento": [Color(1, 0.78, 0.24, 0.2), ACENTO] }
	if colores.has(tipo): pc.add_theme_stylebox_override("panel", caja(colores[tipo][0], Color(0, 0, 0, 0), 12, 0, 10, 3))
	pc.add_child(etiqueta(texto, 12, colores[tipo][1] if colores.has(tipo) else TEXTO))
	return pc

## Tabla .datos de dos columnas (encabezado suave y valor), con linea fina entre filas.
static func tabla_datos(filas: Array, ancho_clave := 0.42) -> VBoxContainer:
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 0)
	for f in filas:
		var h := HBoxContainer.new(); h.add_theme_constant_override("separation", 10)
		var k := etiqueta(String(f[0]), 14, SUAVE, false, true); k.size_flags_horizontal = Control.SIZE_EXPAND_FILL; k.size_flags_stretch_ratio = ancho_clave
		var val := etiqueta(String(f[1]), 14, TEXTO, false, true); val.size_flags_horizontal = Control.SIZE_EXPAND_FILL; val.size_flags_stretch_ratio = 1 - ancho_clave
		h.add_child(k); h.add_child(val)
		var m := MarginContainer.new(); for lado in ["top", "bottom"]: m.add_theme_constant_override("margin_" + lado, 6)
		m.add_child(h); v.add_child(m); v.add_child(linea())
	return v

static func linea(alfa := 0.08) -> ColorRect:
	var r := ColorRect.new(); r.color = Color(1, 1, 1, alfa); r.custom_minimum_size.y = 1
	return r

static func margen(c: Control, izq: int, arr: int, der: int, aba: int) -> MarginContainer:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", izq); m.add_theme_constant_override("margin_top", arr)
	m.add_theme_constant_override("margin_right", der); m.add_theme_constant_override("margin_bottom", aba)
	m.add_child(c)
	return m

static func espacio() -> Control:
	var c := Control.new(); c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c

## Pantalla completa (.pantalla): fondo, cabecera (titulo, subtitulo, botones a la derecha), cuerpo y pie opcional.
## Devuelve un diccionario con las partes: raiz, titulo, subtitulo, botones (HBox de la cabecera), cuerpo, pie.
static func pantalla(titulo: String, subtitulo := "", con_pie := false) -> Dictionary:
	var raiz := Control.new(); raiz.set_anchors_preset(Control.PRESET_FULL_RECT); raiz.mouse_filter = Control.MOUSE_FILTER_STOP
	var fondo := ColorRect.new(); fondo.color = FONDO; fondo.set_anchors_preset(Control.PRESET_FULL_RECT); fondo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	raiz.add_child(fondo)
	var v := VBoxContainer.new(); v.set_anchors_preset(Control.PRESET_FULL_RECT); v.add_theme_constant_override("separation", 0); raiz.add_child(v)
	var cab := HBoxContainer.new(); cab.add_theme_constant_override("separation", 14)
	var tit := VBoxContainer.new(); tit.add_theme_constant_override("separation", 2)
	var lt := etiqueta(titulo, 26, TEXTO, true); tit.add_child(lt)
	var ls := sub(subtitulo); ls.visible = subtitulo != ""; tit.add_child(ls)
	tit.size_flags_horizontal = Control.SIZE_EXPAND_FILL       # el subtitulo usa todo el ancho que dejan los botones
	cab.add_child(tit)
	var botones := HBoxContainer.new(); botones.add_theme_constant_override("separation", 12); botones.alignment = BoxContainer.ALIGNMENT_END
	botones.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	cab.add_child(botones)
	v.add_child(margen(cab, 28, 18, 28, 12))
	var cuerpo := MarginContainer.new(); cuerpo.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cuerpo.add_theme_constant_override("margin_left", 28); cuerpo.add_theme_constant_override("margin_right", 28); cuerpo.add_theme_constant_override("margin_bottom", 24)
	v.add_child(cuerpo)
	var d := { "raiz": raiz, "titulo": lt, "subtitulo": ls, "botones": botones, "cuerpo": cuerpo, "cabecera": tit }
	if con_pie:
		var pie_fondo := PanelContainer.new()
		var sp := caja(Color(8 / 255.0, 14 / 255.0, 22 / 255.0, 0.6), Color(0, 0, 0, 0), 0, 0, 28, 14)
		sp.border_width_top = 1; sp.border_color = Color(1, 1, 1, 0.08)
		pie_fondo.add_theme_stylebox_override("panel", sp)
		var pie := HBoxContainer.new(); pie.add_theme_constant_override("separation", 12); pie_fondo.add_child(pie)
		v.add_child(pie_fondo); d["pie"] = pie
	return d

## Contenedor con desplazamiento vertical (overflow: auto) que llena su sitio.
static func desplazable(c: Control) -> ScrollContainer:
	var s := ScrollContainer.new(); s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL; s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL; s.add_child(c)
	return s

## Rejilla que se adapta al ancho como grid-template-columns: repeat(auto-fill, minmax(min_px, 1fr)).
static func rejilla(min_px: float, sep := 12) -> GridAdaptable:
	var g := GridAdaptable.new(); g.min_px = min_px; g.add_theme_constant_override("h_separation", sep); g.add_theme_constant_override("v_separation", sep)
	return g
