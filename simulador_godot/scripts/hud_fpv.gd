class_name HudFPV
extends Control
## OSD de Betaflight del dron FPV (#fpv de simulador/simulador.html): lo que se ve en las gafas, en letra de ancho fijo
## blanca con borde negro. Arriba el modo (ANGL / HOR / ACRO), el tiempo armado y el gas; en el centro la mira (solo con
## la camara FPV); a los lados la altura y la velocidad; abajo la bateria (total y por celda), ARMED / DISARMED y la
## corriente con los mAh gastados; y los avisos (bateria baja, aterriza ya, desarma para terminar). p es la escena principal.

const NOMBRES := { "ANGLE": "ANGL", "HORIZON": "HOR", "ACRO": "ACRO" }
var p: Node
var modo: Label; var tiempo: Label; var gas: Label; var aviso: Label; var alt: Label; var vel: Label
var bat: Label; var arm: Label; var amp: Label
var mira: Control
static var fuente: SystemFont

## Etiqueta del OSD: x, y en fraccion de la pantalla (como left/top o right/bottom de la web); lado: -1 izquierda
## (left: x), 0 centrada en x, 1 derecha (right: x); abajo: medida desde abajo (bottom: y).
func _osd(x: float, y: float, lado: int, abajo := false, tam := 22) -> Label:
	if fuente == null:
		fuente = SystemFont.new(); fuente.font_names = PackedStringArray(["Consolas", "Courier New", "DejaVu Sans Mono", "monospace"]); fuente.font_weight = 700
	var l := Label.new(); l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("font", fuente); l.add_theme_font_size_override("font_size", tam)
	l.add_theme_color_override("font_color", Color.WHITE); l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 4)
	var ax := x if lado <= 0 else 1.0 - x
	l.anchor_left = ax; l.anchor_right = ax
	l.grow_horizontal = Control.GROW_DIRECTION_END if lado < 0 else (Control.GROW_DIRECTION_BOTH if lado == 0 else Control.GROW_DIRECTION_BEGIN)
	if lado == 0: l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var ay := 1.0 - y if abajo else y
	l.anchor_top = ay; l.anchor_bottom = ay; l.grow_vertical = Control.GROW_DIRECTION_BEGIN if abajo else Control.GROW_DIRECTION_END
	add_child(l); return l

func _init(p_: Node) -> void:
	p = p_; set_anchors_preset(Control.PRESET_FULL_RECT); mouse_filter = Control.MOUSE_FILTER_IGNORE
	mira = Control.new(); mira.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mira.anchor_left = 0.5; mira.anchor_right = 0.5; mira.anchor_top = 0.5; mira.anchor_bottom = 0.5
	mira.offset_left = -45; mira.offset_right = 45; mira.offset_top = -15; mira.offset_bottom = 15
	mira.draw.connect(func():          # la mira de Betaflight: -+- (con borde negro)
		for capa in [[Color.BLACK, 5.0], [Color.WHITE, 2.5]]:
			mira.draw_line(Vector2(8, 15), Vector2(34, 15), capa[0], capa[1]); mira.draw_line(Vector2(56, 15), Vector2(82, 15), capa[0], capa[1])
			mira.draw_line(Vector2(45, 9), Vector2(45, 21), capa[0], capa[1]))
	add_child(mira)
	modo = _osd(0.30, 0.09, -1); tiempo = _osd(0.5, 0.09, 0); gas = _osd(0.63, 0.09, -1)
	aviso = _osd(0.5, 0.15, 0, false, 30)
	alt = _osd(0.12, 0.5, -1); vel = _osd(0.12, 0.5, 1)
	bat = _osd(0.16, 0.09, -1, true); arm = _osd(0.5, 0.09, 0, true); amp = _osd(0.16, 0.09, 1, true)

static func _color(l: Label, cl: String) -> void:
	l.add_theme_color_override("font_color", Color("#ff5252") if cl == "rojo" else (Color("#ffd740") if cl == "ambar" else Color.WHITE))

static func fmt_tiempo(s: float) -> String: return "%d:%02d" % [int(s / 60), int(fmod(s, 60))]

## hudFpv: lo que muestra el OSD en cada cuadro. h: altura (m sobre el origen), vn: velocidad NED.
func pintar(h: float, vn: Array) -> void:
	var av: Dictionary = p.av; var modelo = p.modelo; var F: Dictionary = modelo.fc; var celda: float = av["Vbat"] / modelo.propulsion["celdas"]
	var c: Dictionary = p.casa; var h_casa: float = p.ent.altura(c["N"], c["E"]); var V := sqrt(vn[0] * vn[0] + vn[1] * vn[1] + vn[2] * vn[2])
	mira.visible = p.camara == 3
	modo.text = NOMBRES.get(modelo.modo, modelo.modo)
	tiempo.text = "TIME " + fmt_tiempo(av.get("tArmado", 0.0))
	gas.text = "THR %d" % int(round(av["gases"] * 100))
	alt.text = "ALT %.1fm" % (-p.av["p"][2] - h_casa)      # sobre el punto de despegue, como Betaflight (h viene recortado a 0)
	vel.text = "%dkm/h" % int(round(V * 3.6))
	bat.text = "%.1fV %.2fV" % [av["Vbat"], celda]
	_color(bat, "rojo" if celda < F["critico_celda_V"] else ("ambar" if celda < F["aviso_celda_V"] else ""))
	amp.text = "%.1fA %dmAh" % [av["I"], int(round(av["mAh"]))]
	var armado: bool = av["estado"] == "volando" and av.get("armado", false); var parpadeo := fmod(Time.get_ticks_msec() / 1000.0, 1.0) < 0.6
	arm.text = "REPETICIÓN" if p.rep_activa else (("ARMED" if av.get("tArmado", 0.0) < 1.5 else "") if armado else ("DISARMED" if av["estado"] in ["volando", "en mano"] else String(av["estado"]).to_upper()))
	_color(arm, "" if armado else "rojo")
	var avs := ""; var cl := "rojo"
	if armado:
		if celda < F["critico_celda_V"]: avs = "¡ATERRIZA YA!" if parpadeo else ""
		elif celda < F["aviso_celda_V"]:
			avs = "BATERÍA BAJA" if parpadeo else ""; cl = "ambar"
		elif av.get("posado", false) and av.get("despegado", false):
			avs = "DESARMA (L) PARA TERMINAR"; cl = ""
	if p.pausado: avs = "PAUSA"; cl = ""
	aviso.text = avs; _color(aviso, cl)
