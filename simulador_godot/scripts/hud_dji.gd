class_name HudDji
extends Control
## Pantalla de la app DJI Fly (#dji de simulador/simulador.html): barra de arriba (modo, estado, grabacion, GPS, senal y
## bateria), botones de despegar/aterrizar y volver a casa a la izquierda, gimbal y disparador a la derecha, y abajo el
## mapa (el GPS del HUD, que se mueve aqui) y la telemetria D/H/HS/VS. p es la escena principal.

var p: Node
var modo: Button; var estado: Label; var rec: Label; var bat: Label; var bat_icono: Control
var b_despegar: Button; var b_rth: Button; var b_briefing: Button
var gimbal: Control; var gimbal_marca: ColorRect; var gimbal_txt: Label
var disparo: Button; var cam_txt: Label
var mapa: PanelContainer
var t_d: Label; var t_h: Label; var t_hs: Label; var t_vs: Label
var flash: ColorRect
var _bat_pct := 100.0; var _bat_rojo := false
var _video := false; var _grabando := false
# ⇧ y ⇩ de la web (flecha hueca), dibujadas en SVG
static var FLECHA_ARRIBA: ImageTexture = Tema.svg('<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 18 18"><path d="M9 2 L16 9 H12 V16 H6 V9 H2 Z" fill="none" stroke="#fff" stroke-width="1.6" stroke-linejoin="round"/></svg>')
static var MAPA: ImageTexture = Tema.svg('<svg xmlns="http://www.w3.org/2000/svg" width="22" height="22" viewBox="0 0 24 24"><path d="M3 6l6-2 6 2 6-2v14l-6 2-6-2-6 2z M9 4v14 M15 6v14" fill="none" stroke="#fff" stroke-width="1.7" stroke-linejoin="round"/></svg>')
static var FLECHA_ABAJO: ImageTexture = Tema.svg('<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 18 18"><path d="M9 16 L16 9 H12 V2 H6 V9 H2 Z" fill="none" stroke="#fff" stroke-width="1.6" stroke-linejoin="round"/></svg>')

static func _sombra(l: Label) -> void:
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9)); l.add_theme_constant_override("shadow_outline_size", 4)
	l.add_theme_constant_override("shadow_offset_x", 0); l.add_theme_constant_override("shadow_offset_y", 0)

# radio un poco menor que medio lado: con el radio justo de la mitad StyleBoxFlat deja una costura vertical en el centro
static func _redondo(lado: float, fondo: Color, borde: Color, grosor := 1) -> StyleBoxFlat:
	var s := Tema.caja(fondo, borde, int(lado / 2) - 1, grosor); s.corner_detail = 16; s.content_margin_left = 0; s.content_margin_right = 0; s.content_margin_top = 0; s.content_margin_bottom = 0
	return s

func _boton_redondo(texto: String, tip: String, f: Callable) -> Button:
	var b := Button.new(); b.text = texto; b.tooltip_text = tip; b.custom_minimum_size = Vector2(44, 44); b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 15); b.add_theme_font_override("font", Tema.negrita)
	for e in ["normal", "focus", "disabled"]: b.add_theme_stylebox_override(e, _redondo(44, Color(0, 0, 0, 0.55), Color(1, 1, 1, 0.4)))
	for e in ["hover", "pressed"]: b.add_theme_stylebox_override(e, _redondo(44, Color(1, 1, 1, 0.22), Color(1, 1, 1, 0.4)))
	for e in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]: b.add_theme_color_override(e, Color.WHITE)
	b.pressed.connect(f)
	return b

func _init(p_: Node) -> void:
	p = p_; set_anchors_preset(Control.PRESET_FULL_RECT); mouse_filter = Control.MOUSE_FILTER_IGNORE
	# ---- barra de arriba con degradado ----
	var deg := Gradient.new(); deg.set_color(0, Color(0, 0, 0, 0.7)); deg.set_color(1, Color(0, 0, 0, 0))
	var gt := GradientTexture2D.new(); gt.gradient = deg; gt.fill_from = Vector2(0, 0); gt.fill_to = Vector2(0, 1); gt.width = 4; gt.height = 42
	var fondo := TextureRect.new(); fondo.texture = gt; fondo.stretch_mode = TextureRect.STRETCH_SCALE; fondo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fondo.anchor_right = 1; fondo.offset_bottom = 42; add_child(fondo)
	var top := HBoxContainer.new(); top.add_theme_constant_override("separation", 16); top.anchor_right = 1; top.offset_left = 16; top.offset_right = -16; top.offset_bottom = 42
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE; top.alignment = BoxContainer.ALIGNMENT_CENTER; add_child(top)
	modo = Button.new(); modo.text = "N"; modo.tooltip_text = "Modo de vuelo: Cine / Normal / Sport (M, LB)"; modo.focus_mode = Control.FOCUS_NONE
	modo.custom_minimum_size = Vector2(40, 0); modo.add_theme_font_size_override("font_size", 13); modo.add_theme_font_override("font", Tema.negrita)
	modo.pressed.connect(func(): p.dji_modo()); modo.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(modo); _estilo_modo("N")
	estado = Tema.etiqueta("", 13, Color("#8be08f"), true); estado.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; estado.size_flags_horizontal = Control.SIZE_EXPAND_FILL; _sombra(estado); top.add_child(estado)
	rec = Tema.etiqueta("", 13, Color("#ff5252"), true); _sombra(rec); top.add_child(rec)
	var gps := Tema.etiqueta("GPS 18", 13); gps.tooltip_text = "Satélites GPS"; gps.mouse_filter = Control.MOUSE_FILTER_PASS; _sombra(gps); top.add_child(gps)
	var rc := Tema.etiqueta("RC ▮▮▮▮ · HD ▮▮▮▮", 13); rc.tooltip_text = "Señal del mando y del vídeo"; rc.mouse_filter = Control.MOUSE_FILTER_PASS; _sombra(rc); top.add_child(rc)
	var hb := HBoxContainer.new(); hb.add_theme_constant_override("separation", 5); hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bat_icono = Control.new(); bat_icono.custom_minimum_size = Vector2(26, 11); bat_icono.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bat_icono.draw.connect(func():
		bat_icono.draw_rect(Rect2(0.5, 0.5, 25, 10), Color.WHITE, false, 1)
		bat_icono.draw_rect(Rect2(1.5, 1.5, 22 * _bat_pct / 100.0, 8), Color("#ff5252") if _bat_rojo else Color("#8be08f")))
	hb.add_child(bat_icono)
	bat = Tema.etiqueta("100 % · 30:00", 13, Tema.TEXTO, true); _sombra(bat); hb.add_child(bat); top.add_child(hb)
	# ---- botones de la izquierda ----
	var izq := VBoxContainer.new(); izq.add_theme_constant_override("separation", 10); izq.anchor_top = 0.5; izq.anchor_bottom = 0.5; izq.offset_left = 16
	izq.grow_vertical = Control.GROW_DIRECTION_BOTH; izq.offset_top = -49; izq.offset_bottom = 49   # el VBox crece por los dos lados con el tercer boton
	b_despegar = _boton_redondo("", "", func(): p.dji_despegar()); b_despegar.icon = FLECHA_ARRIBA; b_despegar.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	izq.add_child(b_despegar)
	b_rth = _boton_redondo("H", "Volver a casa (H, botón B)", func(): p.dji_rth()); izq.add_child(b_rth)
	b_briefing = _boton_redondo("", "Briefing: mapa de la zona de trabajo (B)", func(): p.ver_briefing()); b_briefing.icon = MAPA; b_briefing.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b_briefing.visible = false; izq.add_child(b_briefing)                       # solo en los trabajos
	add_child(izq)
	# ---- gimbal ----
	gimbal = Panel.new(); gimbal.add_theme_stylebox_override("panel", Tema.caja(Color(1, 1, 1, 0.25), Color(0, 0, 0, 0), 3))
	gimbal.anchor_left = 1; gimbal.anchor_right = 1; gimbal.anchor_top = 0.5; gimbal.anchor_bottom = 0.5
	gimbal.offset_left = -99; gimbal.offset_right = -94; gimbal.offset_top = -65; gimbal.offset_bottom = 65
	gimbal.tooltip_text = "Inclinación de la cámara (Q/E, gatillos)"; gimbal.mouse_filter = Control.MOUSE_FILTER_PASS
	gimbal_marca = ColorRect.new(); gimbal_marca.color = Color.WHITE; gimbal_marca.size = Vector2(17, 4); gimbal_marca.position = Vector2(-6, 0); gimbal.add_child(gimbal_marca)
	gimbal_txt = Tema.etiqueta("−10°", 11); _sombra(gimbal_txt); gimbal_txt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT; gimbal_txt.size = Vector2(60, 16); gimbal.add_child(gimbal_txt)
	add_child(gimbal)
	# ---- disparador ----
	var der := VBoxContainer.new(); der.add_theme_constant_override("separation", 10); der.alignment = BoxContainer.ALIGNMENT_CENTER
	der.anchor_left = 1; der.anchor_right = 1; der.anchor_top = 0.5; der.anchor_bottom = 0.5; der.offset_right = -16; der.offset_left = -76
	der.offset_top = -70; der.offset_bottom = 70; der.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	disparo = Button.new(); disparo.custom_minimum_size = Vector2(60, 60); disparo.focus_mode = Control.FOCUS_NONE; disparo.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	disparo.tooltip_text = "Disparar: foto o vídeo (F / V, botones Y / X)"
	for e in ["normal", "focus", "hover", "pressed"]: disparo.add_theme_stylebox_override(e, _redondo(60, Color(0, 0, 0, 0.35), Color.WHITE, 3))
	disparo.draw.connect(func():
		var c := disparo.size / 2
		if _video and _grabando: disparo.draw_style_box(Tema.caja(Color("#ff3d3d"), Color(0, 0, 0, 0), 4), Rect2(c - Vector2(11, 11), Vector2(22, 22)))
		else: disparo.draw_circle(c, 21, Color("#ff3d3d") if _video else Color.WHITE, true, -1, true))
	disparo.pressed.connect(func(): p.dji_disparo())
	der.add_child(disparo)
	var bcm := _boton_redondo("⇄", "Cambiar entre foto y vídeo", func(): p.dji_cam_modo()); bcm.size_flags_horizontal = Control.SIZE_SHRINK_CENTER; der.add_child(bcm)
	cam_txt = Tema.etiqueta("FOTO", 10, Tema.SUAVE); cam_txt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; _sombra(cam_txt); der.add_child(cam_txt)
	add_child(der)
	# ---- abajo: mapa y telemetria ----
	var abajo := HBoxContainer.new(); abajo.add_theme_constant_override("separation", 16); abajo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	abajo.anchor_top = 1; abajo.anchor_bottom = 1; abajo.anchor_right = 1; abajo.offset_left = 16; abajo.offset_right = -16; abajo.offset_bottom = -12; abajo.offset_top = -12 - 130
	abajo.grow_vertical = Control.GROW_DIRECTION_BEGIN
	mapa = PanelContainer.new(); mapa.custom_minimum_size = Vector2(130, 130); mapa.clip_contents = true
	mapa.add_theme_stylebox_override("panel", Tema.caja(Color(0, 0, 0, 0.5), Color(1, 1, 1, 0.25), 10, 1, 0, 0)); abajo.add_child(mapa)
	var tele := PanelContainer.new(); tele.add_theme_stylebox_override("panel", Tema.caja(Color(0, 0, 0, 0.5), Color(0, 0, 0, 0), 8, 0, 14, 6))
	tele.size_flags_vertical = Control.SIZE_SHRINK_END; tele.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var th := HBoxContainer.new(); th.add_theme_constant_override("separation", 22); tele.add_child(th)
	var dato := func(nombre: String) -> Label:
		var h := HBoxContainer.new(); h.add_theme_constant_override("separation", 5)
		var s := Tema.etiqueta(nombre, 12, Tema.SUAVE); s.size_flags_vertical = Control.SIZE_SHRINK_CENTER; _sombra(s); h.add_child(s)
		var b := Tema.etiqueta("0 m", 16, Tema.TEXTO, true); _sombra(b); h.add_child(b); th.add_child(h); return b
	t_d = dato.call("D"); t_h = dato.call("H"); t_hs = dato.call("HS"); t_vs = dato.call("VS")
	abajo.add_child(tele); add_child(abajo)
	flash = ColorRect.new(); flash.color = Color(1, 1, 1, 0); flash.set_anchors_preset(Control.PRESET_FULL_RECT); flash.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(flash)

func _estilo_modo(M: String) -> void:
	var col: Color = { "S": Color("#ff5252"), "C": Color("#4fc3f7") }.get(M, Color(1, 1, 1, 0.4))
	var txt: Color = { "S": Color("#ff5252"), "C": Color("#4fc3f7") }.get(M, Color.WHITE)
	var s := Tema.caja(Color(1, 1, 1, 0.12), col, 6, 1, 9, 2)
	for e in ["normal", "focus", "hover", "pressed"]: modo.add_theme_stylebox_override(e, s)
	for e in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]: modo.add_theme_color_override(e, txt)

func foto() -> void:
	flash.color.a = 0.75
	create_tween().tween_property(flash, "color:a", 0.0, 0.3).set_delay(0.08)

static func fmt_tiempo(s: float) -> String: return "%d:%02d" % [int(s / 60), int(fmod(s, 60))]
static func _f1(x: float) -> String: return ("%.1f" % (0.0 if absf(x) < 0.05 else x)).replace(".", ",")

## hudDji: lo que muestra la app en cada cuadro. h: altura (m sobre el mar del modelo), vn: velocidad NED, vs: vertical.
func pintar(h: float, vn: Array, vs: float, dist: float) -> void:
	var av: Dictionary = p.av; var modelo = p.modelo; var M: String = modelo.modo if modelo.modo != "" else "N"; var D: Dictionary = p.DJI
	modo.text = M; _estilo_modo(M)
	var est := ""; var cl := ""
	if p.rep_activa: est = "REPETICIÓN"
	elif av["estado"] == "en mano": est = "Motores parados · pulsa despegar o L"; cl = "aviso"
	elif av["estado"] == "volando":
		var rth = av.get("rth")
		if rth != null: est = "Aterrizando…" if rth["fase"] == "bajar" else ("Volviendo a casa: subiendo…" if rth["fase"] == "subir" else "Volviendo a casa…"); cl = "aviso"
		elif av.get("despegueAuto", false): est = "Despegando…"; cl = "aviso"
		elif av.get("posado", false): est = "Aterrizado · motores al ralentí" if av.get("despegado", false) else "Listo para despegar"
		else: est = "En vuelo · modo Sport" if M == "S" else "En vuelo (GPS)"
	else: est = String(av["estado"]).to_upper(); cl = "" if av["estado"] == "aterrizado" else "rojo"
	if p.pausado: est += " · PAUSA"
	estado.text = est
	estado.add_theme_color_override("font_color", Color("#ffb74d") if cl == "aviso" else (Color("#ff5252") if cl == "rojo" else Color("#8be08f")))
	if D["grabando"] and not p.pausado: D["tRec"] += maxf(0, av["t"] - D["tAnt"])
	D["tAnt"] = av["t"]
	rec.text = ("● REC " + fmt_tiempo(D["tRec"])) if D["grabando"] else ""; rec.visible = D["grabando"]
	var b: float = modelo.bateria_pct(av); var rest_wh: float = modelo.propulsion["masa_bateria_Wh"] * b / 100
	var P: float = av["Wh"] / av["t"] * 3600 if (av["t"] > 5 and av["Wh"] > 0) else 35.0
	_bat_pct = b; _bat_rojo = b < 20; bat_icono.queue_redraw()
	bat.text = "%d %% · %s" % [int(round(b)), fmt_tiempo(minf(5999, rest_wh / P * 3600))]
	bat.add_theme_color_override("font_color", Color("#ff5252") if _bat_rojo else Tema.TEXTO)
	var c: Dictionary = p.casa; var h_casa: float = p.ent.altura(c["N"], c["E"])
	t_d.text = (_f1(dist / 1000) + " km") if dist >= 1000 else ("%d m" % int(round(dist)))
	t_h.text = "%d m" % int(round(maxf(0, -p.av["p"][2] - h_casa)))      # sobre el punto de despegue (h viene recortado a 0)
	t_hs.text = _f1(Vector2(vn[0], vn[1]).length()) + " m/s"; t_vs.text = _f1(vs) + " m/s"
	var g: float = av.get("gimbal", -10.0)
	var y := (10 - g) / 100.0 * 130
	gimbal_marca.position.y = y - 2; gimbal_txt.position = Vector2(-16 - 60 + 5, y - 7 - 1)
	gimbal_txt.text = ("−" if g < 0 else "") + str(int(round(absf(g)))) + "°"
	var volando: bool = av["estado"] == "volando" and not av.get("posado", false)
	b_despegar.icon = FLECHA_ABAJO if volando else FLECHA_ARRIBA
	b_despegar.tooltip_text = "Aterrizar aquí (botón A del mando)" if volando else "Despegar: arma y sube a 1,2 m (botón A del mando)"
	var activo: bool = av.get("rth") != null and av["rth"]["fase"] != "bajar"
	var s_rth := _redondo(44, Color("#ffb74d") if activo else Color(0, 0, 0, 0.55), Color("#ffb74d") if activo else Color(1, 1, 1, 0.4))
	b_rth.add_theme_stylebox_override("normal", s_rth); b_rth.add_theme_color_override("font_color", Color.BLACK if activo else Color.WHITE)
	if _video != D["video"] or _grabando != D["grabando"]: _video = D["video"]; _grabando = D["grabando"]; disparo.queue_redraw()
	cam_txt.text = "VÍDEO" if D["video"] else "FOTO"
