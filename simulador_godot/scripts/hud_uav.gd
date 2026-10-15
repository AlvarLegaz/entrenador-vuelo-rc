class_name HudUav
extends Control
## Estacion de control del UAV (Cernicalo XM-7): #gcs de simulador/simulador.html (hudUav). Barra de arriba (modo del
## piloto automatico, estado, enlace de datos y combustible), consignas del automatico, botones a la derecha (modos,
## zoom, termica, fijar y foto) y, con la camara 3, la mira de la torreta EO/IR con el punto de la cruz y su distancia,
## los datos del sensor y la escala de temperaturas. Los instrumentos del avion siguen abajo (hud_vuelo.gd). p: la escena principal.

const VERDE := Color("#b8f5b0"); const CIAN := Color("#4dd0e1"); const NARANJA := Color("#ffb74d")
var p: Node
var modo: Label; var estado: Label; var enlace: Label; var comb: Label
var consignas: Label
var botones := {}; var b_auto: Button
var zoom_txt: Label; var b_ir: Button; var b_fijar: Button
var mira: VBoxContainer; var obj: RichTextLabel
var sensor: Label
var paleta: VBoxContainer
var _clase_modo := ""; var _activos := {}

static func _sombra(l: Control) -> void:
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9)); l.add_theme_constant_override("shadow_outline_size", 4)
	l.add_theme_constant_override("shadow_offset_x", 0); l.add_theme_constant_override("shadow_offset_y", 0)

func _boton(texto: String, tip: String, f: Callable) -> Button:
	var b := Button.new(); b.text = texto; b.tooltip_text = tip; b.custom_minimum_size = Vector2(52, 30); b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 12); b.add_theme_font_override("font", Tema.negrita); b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_estilo(b, false); b.pressed.connect(f); return b

static func _estilo(b: Button, activo: bool) -> void:
	var s := Tema.caja(Color("#ffb74d") if activo else Color(0, 0, 0, 0.55), Color("#ffb74d") if activo else Color(1, 1, 1, 0.4), 5, 1)
	var h := Tema.caja(Color(1, 1, 1, 0.22), Color(1, 1, 1, 0.4), 5, 1)
	for e in ["normal", "focus", "disabled"]: b.add_theme_stylebox_override(e, s)
	for e in ["hover", "pressed"]: b.add_theme_stylebox_override(e, h)
	for e in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]: b.add_theme_color_override(e, Color.BLACK if activo else Color.WHITE)

func _poner_activo(b: Button, si: bool) -> void:
	if _activos.get(b) == si: return
	_activos[b] = si; _estilo(b, si)

func _init(p_: Node) -> void:
	p = p_; set_anchors_preset(Control.PRESET_FULL_RECT); mouse_filter = Control.MOUSE_FILTER_IGNORE
	# ---- barra de arriba ----
	var deg := Gradient.new(); deg.set_color(0, Color(5 / 255.0, 12 / 255.0, 8 / 255.0, 0.85)); deg.set_color(1, Color(5 / 255.0, 12 / 255.0, 8 / 255.0, 0))
	var gt := GradientTexture2D.new(); gt.gradient = deg; gt.fill_from = Vector2(0, 0); gt.fill_to = Vector2(0, 1); gt.width = 4; gt.height = 40
	var fondo := TextureRect.new(); fondo.texture = gt; fondo.stretch_mode = TextureRect.STRETCH_SCALE; fondo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fondo.anchor_right = 1; fondo.offset_bottom = 40; add_child(fondo)
	var top := HBoxContainer.new(); top.add_theme_constant_override("separation", 18); top.anchor_right = 1; top.offset_left = 16; top.offset_right = -16; top.offset_bottom = 40
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE; top.alignment = BoxContainer.ALIGNMENT_CENTER; add_child(top)
	modo = Tema.etiqueta("MANUAL", 13, VERDE, true); modo.size_flags_vertical = Control.SIZE_SHRINK_CENTER; _sombra(modo); top.add_child(modo)
	estado = Tema.etiqueta("", 13, VERDE, true); estado.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; estado.size_flags_horizontal = Control.SIZE_EXPAND_FILL; _sombra(estado); top.add_child(estado)
	enlace = Tema.etiqueta("", 13, VERDE, true); _sombra(enlace); top.add_child(enlace)
	comb = Tema.etiqueta("", 13, VERDE, true); _sombra(comb); top.add_child(comb)
	_clase("")
	# ---- consignas del piloto automatico y datos del sensor ----
	consignas = Tema.etiqueta("", 12, CIAN, true); consignas.position = Vector2(16, 48); _sombra(consignas); add_child(consignas)
	sensor = Tema.etiqueta("", 12, VERDE, true); sensor.position = Vector2(16, 72); sensor.visible = false; _sombra(sensor); add_child(sensor)
	# ---- botones de la derecha ----
	var der := VBoxContainer.new(); der.add_theme_constant_override("separation", 10); der.alignment = BoxContainer.ALIGNMENT_CENTER
	der.anchor_left = 1; der.anchor_right = 1; der.anchor_top = 0.5; der.anchor_bottom = 0.5; der.offset_right = -16; der.offset_left = -68
	der.offset_top = -200; der.offset_bottom = 200; der.grow_horizontal = Control.GROW_DIRECTION_BEGIN; der.grow_vertical = Control.GROW_DIRECTION_BOTH
	for q in [["MAN", "MANUAL", "Manual (M)"], ["EST", "ESTAB", "Estabilizado (M)"], ["CRU", "CRUCERO", "Crucero: mantiene altura, rumbo y velocidad (M)"], ["BASE", "BASE", "Vuelta a base (H, Y)"]]:
		var m: String = q[1]; var b := _boton(q[0], q[2], func(): p.uav_poner(m)); botones[m] = b; der.add_child(b)
	b_auto = _boton("ATO", "Despegue o aterrizaje automático (P, cruceta izquierda)", func(): p.uav_poner("DESPEGUE" if p.av.get("enTierra", false) else "ATERRIZAJE")); der.add_child(b_auto)
	var sep := Control.new(); sep.custom_minimum_size = Vector2(0, 6); der.add_child(sep)
	der.add_child(_boton("+", "Acercar el zoom de la torreta (Z, cruceta arriba)", func(): p.dji_zoom(1)))
	zoom_txt = Tema.etiqueta("1x", 11, VERDE, true); zoom_txt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; _sombra(zoom_txt); der.add_child(zoom_txt)
	der.add_child(_boton("−", "Alejar el zoom (X, cruceta abajo)", func(): p.dji_zoom(-1)))
	b_ir = _boton("IR", "Cámara térmica (C, cruceta derecha)", func(): p.dji_termica()); der.add_child(b_ir)
	b_fijar = _boton("FIJAR", "Fijar la torreta en el punto de la cruz (K)", func(): p.uav_fijar()); der.add_child(b_fijar)
	der.add_child(_boton("FOTO", "Foto de la torreta (F, botón X)", func(): p.uav_foto()))
	add_child(der)
	# ---- mira de la torreta (camara 3) ----
	mira = VBoxContainer.new(); mira.add_theme_constant_override("separation", 2); mira.mouse_filter = Control.MOUSE_FILTER_IGNORE; mira.visible = false
	mira.set_anchors_preset(Control.PRESET_CENTER); mira.grow_horizontal = Control.GROW_DIRECTION_BOTH; mira.grow_vertical = Control.GROW_DIRECTION_BOTH
	var cruz := Control.new(); cruz.custom_minimum_size = Vector2(120, 120); cruz.size_flags_horizontal = Control.SIZE_SHRINK_CENTER; cruz.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cruz.draw.connect(func():
		for par in [[Color.BLACK, 3.0], [VERDE, 1.5]]:
			for s in [[Vector2(60, 8), Vector2(60, 44)], [Vector2(60, 76), Vector2(60, 112)], [Vector2(8, 60), Vector2(44, 60)], [Vector2(76, 60), Vector2(112, 60)]]:
				cruz.draw_line(s[0], s[1], par[0], par[1])
			for e in [[Vector2(38, 38), -1, -1], [Vector2(82, 38), 1, -1], [Vector2(38, 82), -1, 1], [Vector2(82, 82), 1, 1]]:
				var c: Vector2 = e[0]
				cruz.draw_polyline(PackedVector2Array([c, c + Vector2(8 * e[1], 0), c + Vector2(8 * e[1], 8 * -e[2])]), par[0], par[1])
		cruz.draw_arc(Vector2(60, 60), 2, 0, TAU, 12, VERDE, 1.5, true))
	mira.add_child(cruz)
	obj = RichTextLabel.new(); obj.bbcode_enabled = true; obj.fit_content = true; obj.scroll_active = false; obj.autowrap_mode = TextServer.AUTOWRAP_OFF
	obj.custom_minimum_size = Vector2(320, 0); obj.mouse_filter = Control.MOUSE_FILTER_IGNORE
	obj.add_theme_font_size_override("normal_font_size", 12); obj.add_theme_font_size_override("bold_font_size", 12); obj.add_theme_font_override("bold_font", Tema.negrita)
	obj.add_theme_color_override("default_color", VERDE); _sombra(obj); mira.add_child(obj)
	add_child(mira)
	# ---- escala de temperaturas (termica) ----
	paleta = VBoxContainer.new(); paleta.add_theme_constant_override("separation", 3); paleta.mouse_filter = Control.MOUSE_FILTER_IGNORE; paleta.visible = false
	paleta.anchor_left = 1; paleta.anchor_right = 1; paleta.anchor_top = 0.5; paleta.anchor_bottom = 0.5; paleta.offset_right = -90; paleta.offset_left = -90
	paleta.grow_horizontal = Control.GROW_DIRECTION_BEGIN; paleta.grow_vertical = Control.GROW_DIRECTION_BOTH
	var pa := Tema.etiqueta("150 °C", 11); pa.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; _sombra(pa); paleta.add_child(pa)
	var grad := Gradient.new(); grad.offsets = PackedFloat32Array([0.0, 0.07, 0.2, 0.35, 0.55, 0.78, 1.0])
	grad.colors = PackedColorArray([Color("#fffeed"), Color("#ffdb33"), Color("#ff8000"), Color("#db2933"), Color("#8c008c"), Color("#1f005c"), Color("#00000d")])
	var gtx := GradientTexture2D.new(); gtx.gradient = grad; gtx.fill_from = Vector2(0, 0); gtx.fill_to = Vector2(0, 1); gtx.width = 10; gtx.height = 120
	var barra := Control.new(); barra.custom_minimum_size = Vector2(12, 122); barra.size_flags_horizontal = Control.SIZE_SHRINK_CENTER; barra.mouse_filter = Control.MOUSE_FILTER_IGNORE
	barra.draw.connect(func():
		barra.draw_texture_rect(gtx, Rect2(1, 1, 10, 120), false)
		barra.draw_rect(Rect2(0.5, 0.5, 11, 121), Color(1, 1, 1, 0.5), false, 1))
	paleta.add_child(barra)
	var pb := Tema.etiqueta("−20 °C", 11); pb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; _sombra(pb); paleta.add_child(pb)
	add_child(paleta)

## Recuadro del modo: verde (manual y estabilizado), cian (navegacion automatica) o naranja (despegue y aterrizaje).
func _clase(cl: String) -> void:
	if cl == _clase_modo and modo.has_theme_stylebox_override("normal"): return
	_clase_modo = cl; var col: Color = CIAN if cl == "auto" else (NARANJA if cl == "pista" else VERDE)
	modo.add_theme_stylebox_override("normal", Tema.caja(Color(0, 0, 0, 0), col, 4, 1, 9, 3)); modo.add_theme_color_override("font_color", col)

static func _hm(h: float) -> String: return "%d:%02d" % [int(h), int(fmod(h, 1.0) * 60)]

## hudUav de la web: lo que se ve en cada cuadro.
func pintar(vn: Array, dist: float, yaw: float) -> void:
	var av: Dictionary = p.av; var pil = p.piloto; var m: String = pil.modo if pil != null else "MANUAL"
	var auto := not (m in ["MANUAL", "ESTAB"]); var pista_m := m == "DESPEGUE" or m == "ATERRIZAJE"
	modo.text = (PilotoUAV.NOMBRE[m] as String).to_upper() if pil != null else "MANUAL"; _clase("pista" if pista_m else ("auto" if auto else ""))
	var suelo: float = p.ent.altura(av["p"][0], av["p"][1]) if p.en_mundo() else 0.0; var agl: float = -av["p"][2] - suelo
	var est := "REPETICIÓN" if p.rep_activa else ("MOTOR PARADO · L arranca" if av["estado"] == "en mano" else (("EN TIERRA · FRENO DE APARCAMIENTO (espacio)" if av.get("frenoAparc", false) else "EN TIERRA") if av.get("enTierra", false) else "EN VUELO") if av["estado"] == "volando" else String(av["estado"]).to_upper())
	estado.text = "%s · %d km/h · %d m · rumbo %03d°%s" % [est, int(round(av["V"] * 3.6)), int(round(agl)), int(round(fposmod(yaw + 360, 360))), " · PAUSA" if p.pausado else ""]
	var c_pct: float = p.modelo.bateria_pct(av); var P: Dictionary = p.modelo.propulsion; var gm: float = av.get("gasMotor", av["gases"])
	var h_rest: float = c_pct / 100 * P["masa_bateria_Wh"] / maxf(500, P["P_max_W"] * gm * gm * gm); var dl := dist / 1000
	enlace.text = "ENLACE %s %s km" % ["▮▮▮▮" if dl < 60 else ("▮▮▮" if dl < 100 else "▮"), ("%.1f" % dl).replace(".", ",")]
	comb.text = "COMB %d %%" % int(round(c_pct)) + ((" · %s h" % _hm(h_rest)) if (av["estado"] == "volando" and gm > 0.05) else "")
	var t := ""
	if pil != null and auto:
		var c: Dictionary = pil.c
		if pista_m: t = "%s · fase %s" % [PilotoUAV.NOMBRE[m], pil.fase]
		else:
			t = "ALT %d m s/t · VEL %d km/h" % [int(round(c["alt"] - suelo)), int(round(c["vel"] * 3.6))]
			if m == "CRUCERO": t += " · RUMBO %03d°" % int(round(fposmod(c["rumbo"] * 180 / PI, 360)))
			else: t += " · PUNTO a %s km" % ("%.1f" % (Vector2(av["p"][0] - c["punto"][0], av["p"][1] - c["punto"][1]).length() / 1000)).replace(".", ",")
	consignas.text = t
	for k in botones: _poner_activo(botones[k], k == m)
	_poner_activo(b_auto, pista_m); b_auto.text = "ATO" if av.get("enTierra", false) else "ATL"
	# torreta
	var cm: Dictionary = p.cam_dji(); var cam3: bool = p.camara == 3; var tr: Dictionary = av.get("torreta", { "pan": 0.0, "tilt": 0.0 })
	zoom_txt.text = "%dx" % int(cm["zoom"]); _poner_activo(b_ir, cm["termica"]); _poner_activo(b_fijar, p.UAV["fijo"] != null)
	mira.visible = cam3; sensor.visible = cam3; paleta.visible = cam3 and cm["termica"]
	if cam3:
		var X = p.UAV["cruz"]; var L = p.ev.op.lectura if (p.ev != null and p.ev.op != null) else null
		var s := "[center]" + ("[b][color=#ffb74d]FIJADO[/color][/b]\n" if p.UAV["fijo"] != null else "")
		if X != null and p.en_mundo(): s += "%s\n%s" % [p.coord_txt(X[0], X[1]), ("%d m" % int(round(X[3]))) if X[3] < 1000 else ("%s km" % ("%.2f" % (X[3] / 1000)).replace(".", ","))]
		else: s += "sin punto en el suelo"
		if cm["termica"] and L != null: s += "\n[bgcolor=#0000008c][color=#ffffff] %s °C [/color][/bgcolor]" % ("%.1f" % L["T"]).replace(".", ",")
		obj.text = s + "[/center]"
		sensor.text = "%s %d×\nAZ %03d° EL %d°\nFOV %s°" % ["IR" if cm["termica"] else "EO", int(cm["zoom"]), int(round(fposmod(tr["pan"] * 180 / PI, 360))), int(round(tr["tilt"] * 180 / PI)), "%.1f" % p.cam.fov]
