class_name HudVuelo
extends Control
## HUD de vuelo, el MISMO que el de simulador/simulador.html (#estado, #hud, #aviso, #lejos, #guia, #toast, #objetivos,
## #panelVuelo, #ayuda, #repBarra): pastillas de estado arriba a la izquierda, objetivos arriba a la derecha, abajo el
## GPS, la barra de gas y la palanca, las lecturas en el centro y los relojes y el horizonte (en la camara del piloto el
## GPS va a la derecha y no hay relojes), avisos en el centro y la ventana de controles. p es la escena principal.

var p: Node
var estado: HBoxContainer
var hud_texto: PanelContainer; var hud_rt: RichTextLabel
var objetivos: PanelContainer; var obj_rt: RichTextLabel
var guia: PanelContainer; var guia_rt: RichTextLabel
var aviso: Label
var toast: Label
var lejos: PanelContainer; var lejos_l: Label
var ayuda: PanelContainer; var ayuda_rt: RichTextLabel
var rep: PanelContainer; var rep_l: RichTextLabel; var rep_barra: ColorRect; var rep_fondo: ColorRect
var panel: HBoxContainer
var gps: Instrumento; var barra: Instrumento; var vario: Instrumento; var anemo: Instrumento; var horiz: Instrumento
var lecturas: HBoxContainer
var esp1: Control; var esp2: Control
var dji: Control                 # pantalla de la app dron comercial (la pone principal con el dron)
var bip: HBoxContainer; var bip_drones: Label; var bip_canon: Label    # bipode: marcador (arriba en el centro)
var mira: Control                                                     # bipode: mira del puesto de tiro (camara 3)

static func _sombra_texto(l: Label, tam := 2) -> void:
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85)); l.add_theme_constant_override("shadow_outline_size", 6)
	l.add_theme_constant_override("shadow_offset_x", 0); l.add_theme_constant_override("shadow_offset_y", tam)

func _init(p_: Node) -> void:
	p = p_
	set_anchors_preset(Control.PRESET_FULL_RECT); mouse_filter = Control.MOUSE_FILTER_IGNORE
	# ---- estado (pastillas) ----
	estado = HBoxContainer.new(); estado.add_theme_constant_override("separation", 10); estado.position = Vector2(16, 14); estado.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(estado)
	# ---- datos en texto (tecla H) ----
	hud_texto = PanelContainer.new(); hud_texto.add_theme_stylebox_override("panel", Tema.caja(Color(0, 0, 0, 0.45), Color(0, 0, 0, 0), 10, 0, 12, 8))
	hud_texto.position = Vector2(16, 14); hud_texto.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_rt = Tema.rico("", 14); hud_rt.fit_content = true; hud_rt.autowrap_mode = TextServer.AUTOWRAP_OFF; hud_texto.add_child(hud_rt); hud_texto.visible = false
	add_child(hud_texto)
	# ---- objetivos (arriba a la derecha) ----
	objetivos = PanelContainer.new(); objetivos.add_theme_stylebox_override("panel", Tema.caja(Color(0, 0, 0, 0.5), Color(1, 1, 1, 0.1), 10, 1, 14, 10))
	objetivos.mouse_filter = Control.MOUSE_FILTER_IGNORE
	obj_rt = Tema.rico("", 13); obj_rt.custom_minimum_size.x = 240; obj_rt.add_theme_constant_override("line_separation", 3); objetivos.add_child(obj_rt)
	add_child(objetivos)
	# ---- banda de la guia (aterrizaje guiado) ----
	guia = PanelContainer.new(); var sg := Tema.caja(Color(0, 0, 0, 0.62), Color(0, 0, 0, 0), 10, 0, 14, 10); sg.border_width_left = 5; sg.border_color = Tema.ACENTO
	guia.add_theme_stylebox_override("panel", sg); guia.position = Vector2(16, 60); guia.mouse_filter = Control.MOUSE_FILTER_IGNORE
	guia_rt = Tema.rico("", 17); guia_rt.fit_content = true; guia.add_child(guia_rt); guia.visible = false
	add_child(guia)
	# ---- aviso, toast y "demasiado lejos" ----
	aviso = Tema.etiqueta("", 34, Color.WHITE, true); aviso.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; _sombra_texto(aviso, 2); add_child(aviso)
	toast = Tema.etiqueta("", 26, Tema.ACENTO, true); toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; _sombra_texto(toast, 2); add_child(toast)
	lejos = PanelContainer.new(); lejos.add_theme_stylebox_override("panel", Tema.caja(Color(0, 0, 0, 0.45), Color(0, 0, 0, 0), 10, 0, 14, 6)); lejos.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lejos_l = Tema.etiqueta("", 17, Tema.NARANJA, true, true); lejos_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; lejos.add_child(lejos_l); add_child(lejos)
	# ---- bipode: marcador de drones derribados y estado del cañon (#hudBip) y mira (#miraBip) ----
	bip = HBoxContainer.new(); bip.add_theme_constant_override("separation", 10); bip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bip.anchor_left = 0.5; bip.anchor_right = 0.5; bip.offset_top = 16; bip.grow_horizontal = Control.GROW_DIRECTION_BOTH; bip.visible = false
	for i in 2:
		var pc := PanelContainer.new(); pc.add_theme_stylebox_override("panel", Tema.caja(Color(0, 0, 0, 0.45), Color(1, 0.78, 0.24, 0.4), 999, 1, 12, 5))
		var l := Tema.etiqueta("", 14, Color("#ffe9a8"), true); _sombra_texto(l, 1); pc.add_child(l); bip.add_child(pc)
		if i == 0: bip_drones = l
		else: bip_canon = l
	add_child(bip)
	mira = Control.new(); mira.mouse_filter = Control.MOUSE_FILTER_IGNORE; mira.anchor_left = 0.5; mira.anchor_right = 0.5; mira.anchor_top = 0.5; mira.anchor_bottom = 0.5
	mira.offset_left = -28; mira.offset_right = 28; mira.offset_top = -28; mira.offset_bottom = 28; mira.visible = false
	mira.draw.connect(func():
		var c := Color("#ffd36a"); var m := Vector2(28, 28)
		mira.draw_arc(m, 14, 0, TAU, 40, Color(c, 0.85), 2.0, true)
		for v in [[Vector2(28, 4), Vector2(28, 16)], [Vector2(28, 40), Vector2(28, 52)], [Vector2(4, 28), Vector2(16, 28)], [Vector2(40, 28), Vector2(52, 28)]]: mira.draw_line(v[0], v[1], c, 2.0, true)
		mira.draw_circle(m, 1.5, c))
	add_child(mira)
	# ---- panel de abajo: GPS, gas y palanca, lecturas, relojes y horizonte ----
	panel = HBoxContainer.new(); panel.add_theme_constant_override("separation", 12); panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.anchor_left = 0; panel.anchor_right = 1; panel.anchor_top = 1; panel.anchor_bottom = 1
	panel.offset_left = 16; panel.offset_right = -16; panel.offset_bottom = -14; panel.offset_top = -14 - 190; panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(panel)
	gps = Instrumento.new("gps", p); barra = Instrumento.new("barra", p)
	esp1 = Tema.espacio(); esp2 = Tema.espacio()
	lecturas = HBoxContainer.new(); lecturas.add_theme_constant_override("separation", 8); lecturas.size_flags_vertical = Control.SIZE_SHRINK_END; lecturas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vario = Instrumento.new("vario", p); anemo = Instrumento.new("anemo", p); horiz = Instrumento.new("horiz", p)
	for c in [gps, barra, esp1, lecturas, esp2, vario, anemo, horiz]: panel.add_child(c)
	# ---- repeticion ----
	rep = PanelContainer.new(); rep.add_theme_stylebox_override("panel", Tema.caja(Color(0, 0, 0, 0.6), Color(1, 1, 1, 0.15), 12, 1, 16, 8)); rep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rv := VBoxContainer.new(); rv.add_theme_constant_override("separation", 6); rep.add_child(rv)
	rep_l = Tema.rico("", 14); rep_l.fit_content = true; rep_l.autowrap_mode = TextServer.AUTOWRAP_OFF; rep_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; rv.add_child(rep_l)
	rep_fondo = ColorRect.new(); rep_fondo.color = Color(1, 1, 1, 0.15); rep_fondo.custom_minimum_size.y = 6; rv.add_child(rep_fondo)
	rep_barra = ColorRect.new(); rep_barra.color = Tema.ACENTO; rep_fondo.add_child(rep_barra); rep_barra.size = Vector2(0, 6)
	rep.visible = false; add_child(rep)
	# ---- ventana de controles (T o desde la pausa) ----
	ayuda = PanelContainer.new(); var sa := Tema.caja(Color(8 / 255.0, 14 / 255.0, 22 / 255.0, 0.92), Tema.BORDE, Tema.RADIO, 1, 22, 18)
	ayuda.add_theme_stylebox_override("panel", sa); ayuda.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ayuda_rt = Tema.rico("", 14); ayuda_rt.custom_minimum_size.x = 540; ayuda_rt.add_theme_constant_override("line_separation", 6); ayuda.add_child(ayuda_rt)
	ayuda.visible = false; add_child(ayuda)

# ---- pastillas de estado ----
func _pill(texto: String, rojo := false) -> void:
	var pc := PanelContainer.new(); pc.add_theme_stylebox_override("panel", Tema.caja(Color(0, 0, 0, 0.5), Color(1, 1, 1, 0.15), 20, 1, 12, 5)); pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := Tema.etiqueta(texto, 14, Color("#ff5252") if rojo else Tema.TEXTO, true); _sombra_texto(l, 0); pc.add_child(l)
	estado.add_child(pc)

var _estado_ant := ""
func pintar_estado(partes: Array) -> void:          # [[texto, rojo], ...]
	var clave := str(partes)
	if clave == _estado_ant: return
	_estado_ant = clave
	for c in estado.get_children(): c.queue_free()
	for q in partes: _pill(q[0], q[1])

# ---- lecturas (cajas .lect) ----
## Las cajas se crean una vez por numero de lecturas; despues solo cambian sus textos y colores (cada cuadro).
var _lect := []
func pintar_lecturas(cajas: Array) -> void:          # [[valor, nombre, clase ("" | "rojo" | "ambar")], ...]
	if cajas.size() != _lect.size():
		for c in lecturas.get_children(): c.queue_free()
		_lect = []
		for q in cajas:
			var pc := PanelContainer.new(); pc.add_theme_stylebox_override("panel", Tema.caja(Color(0, 0, 0, 0.5), Color(1, 1, 1, 0.12), 10, 1, 12, 6))
			pc.custom_minimum_size.x = 86; pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 0); pc.add_child(v)
			var b := Tema.etiqueta("", 22, Tema.TEXTO, true); b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; v.add_child(b)
			var s := Tema.etiqueta("", 10, Tema.SUAVE); s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			var fv := FontVariation.new(); fv.base_font = Tema.fuente; fv.spacing_glyph = 1; s.add_theme_font_override("font", fv); v.add_child(s)
			lecturas.add_child(pc); _lect.append([b, s, ""])
	for i in cajas.size():
		var q: Array = cajas[i]; var L: Array = _lect[i]
		if L[0].text != String(q[0]): L[0].text = String(q[0])
		var nombre := String(q[1]).to_upper()
		if L[1].text != nombre: L[1].text = nombre
		if L[2] != q[2]:
			L[2] = q[2]; L[0].add_theme_color_override("font_color", Color("#ff5252") if q[2] == "rojo" else (Color("#ffb300") if q[2] == "ambar" else Tema.TEXTO))

## Coloca lo que depende del tamano de la pantalla (cada cuadro).
func _process(_dt: float) -> void:
	var W := size.x; var H := size.y
	objetivos.visible = obj_rt.text != ""          # #objetivos:empty de la web
	objetivos.position = Vector2(W - 16 - objetivos.size.x, 14 + (36 if dji and dji.visible else 0)); objetivos.size.x = 0
	obj_rt.custom_minimum_size.x = 240
	guia.position.y = 60 + (36 if dji and dji.visible else 0)
	guia_rt.custom_minimum_size.x = minf(520, W * 0.55) - 33
	aviso.position = Vector2(0, H * 0.30 - 20); aviso.size = Vector2(W, 48)
	toast.position = Vector2(0, H * 0.20 - 16); toast.size = Vector2(W, 36)
	lejos_l.custom_minimum_size.x = 0; lejos.size = Vector2.ZERO
	lejos.position = Vector2((W - lejos.size.x) / 2, H * 0.40); lejos_l.autowrap_mode = TextServer.AUTOWRAP_OFF
	if lejos.size.x > W * 0.7: lejos_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; lejos_l.custom_minimum_size.x = W * 0.7 - 28; lejos.position.x = W * 0.15
	ayuda.size = Vector2.ZERO; ayuda.position = (Vector2(W, H) - ayuda.size) / 2
	rep.position = Vector2((W - rep.size.x) / 2, H - 120 - rep.size.y)
	rep_fondo.custom_minimum_size.x = rep_l.size.x

## Coloca el GPS (en la camara del piloto, a la derecha) y ensena u oculta los instrumentos.
func disponer(camara1: bool, sin_instr: bool, relojes: bool, con_lecturas: bool, dron: bool) -> void:
	panel.visible = not dron
	estado.visible = not dron
	if gps.get_parent() == panel: panel.move_child(gps, panel.get_child_count() - 1 if camara1 else 0)
	gps.visible = not sin_instr
	barra.visible = not sin_instr
	lecturas.visible = con_lecturas and not sin_instr
	horiz.visible = not camara1 and not sin_instr
	vario.visible = relojes and not camara1 and not sin_instr
	anemo.visible = vario.visible
