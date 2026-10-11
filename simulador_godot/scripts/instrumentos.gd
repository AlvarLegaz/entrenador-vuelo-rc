class_name Instrumentos
extends Control
## Instrumentos del vuelo, como en el simulador del navegador: en la camara 1 los datos en texto (arriba a la
## izquierda); en las camaras 2 y 3, horizonte artificial con la rosa de rumbos en el anillo exterior (abajo a la
## derecha), anemometro con las bandas de la velocidad de perdida, variometro y GPS con la ortofoto (abajo a la
## izquierda; la rueda del raton encima cambia el zoom). Siempre: barra de gases, palanca y avisos.

const D2R := PI / 180.0
const R2D := 180.0 / PI
const BLANCO := Color(0.9, 0.93, 0.95)
const HZ_PX_GRADO := 3.2

var p: Node                      # la escena principal (estado del vuelo)
var gps_zoom := 1.0
var estela := []
var _t_estela := -1.0
var fuente: Font

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS
	fuente = ThemeDB.fallback_font

func _rect_gps() -> Rect2:
	var W := minf(280.0, size.y * 0.32)
	return Rect2(16, size.y - W - 16, W, W)

func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and _rect_gps().has_point(ev.position) and p.camara != 1:
		if ev.button_index == MOUSE_BUTTON_WHEEL_UP: gps_zoom = maxf(0.05, gps_zoom / 1.25); accept_event()
		elif ev.button_index == MOUSE_BUTTON_WHEEL_DOWN: gps_zoom = minf(8.0, gps_zoom * 1.25); accept_event()

func _process(_dt: float) -> void:
	queue_redraw()

func _txt(pos: Vector2, s: String, tam := 15, color := BLANCO, alin := HORIZONTAL_ALIGNMENT_LEFT, ancho := -1.0) -> void:
	draw_string_outline(fuente, pos, s, alin, ancho, tam, 4, Color(0, 0, 0, 0.75))
	draw_string(fuente, pos, s, alin, ancho, tam, color)

func _draw() -> void:
	if p == null or p.av.is_empty() or not p.volando_en_pantalla: return
	var av: Dictionary = p.av
	var e := Cuat.euler(av["q"]); var roll: float = e[0] * R2D; var pitch: float = e[1] * R2D; var yaw: float = e[2] * R2D
	var vn := Cuat.rot(av["q"], av["v"]); var vs: float = -vn[2]
	var suelo: float = p.ent.altura(av["p"][0], av["p"][1])
	var cam: int = p.camara
	if cam == 1 and p.mostrar_hud: _texto(av, roll, pitch, yaw, vn, vs, suelo)
	if cam != 1 and p.instrumentos:
		_horizonte(av, roll, pitch, yaw)
		if not (av["estado"] == "en mano"):
			_anemometro(av["V"]); _variometro(vs)
		_gps(av, yaw, suelo)
	_gases(av)
	_palanca()
	if p.aviso != "": _txt(Vector2(0, size.y * 0.22), p.aviso, 26, Color(1, 0.85, 0.3), HORIZONTAL_ALIGNMENT_CENTER, size.x)
	if p.toast_t > 0: _txt(Vector2(0, size.y * 0.30), p.toast, 20, BLANCO, HORIZONTAL_ALIGNMENT_CENTER, size.x)
	if p.ver_ayuda: _ayuda()

func _texto(av: Dictionary, roll: float, pitch: float, yaw: float, vn: Array, vs: float, suelo: float) -> void:
	var h: float = -av["p"][2]; var C: Dictionary = p.casa
	var dist := Vector2(av["p"][0] - C["N"], av["p"][1] - C["E"]).length(); var vto: Dictionary = p.ent.viento
	var l := [
		"%s   t %.1f s%s" % [String(av["estado"]).to_upper(), av["t"], "   MOTOR PARADO" if av["motorRoto"] else ""],
		"vel. aire %.1f m/s · suelo %.1f m/s · asc. %+.1f m/s" % [av["V"], Vector2(vn[0], vn[1]).length(), vs],
		"altura sobre el terreno %.0f m · distancia %.0f m" % [h - suelo, dist],
		"alabeo %.0f° · cabeceo %.0f° · rumbo %.0f°" % [roll, pitch, fposmod(yaw, 360)],
		"alfa %.1f°%s · carga %.1f g" % [av["alfa"], "  ¡PÉRDIDA!" if av["perdida"] > 0.5 else "", av["g_carga"]],
		"gases %.0f %% · batería %.0f %%" % [av["gases"] * 100, p.modelo.bateria_pct(av)],
		("física fácil · " if p.modelo.facil else "") + "viento %.0f m/s%s · compensador %.2f° · cámara %d · T: ayuda · Esc: menú" % [vto["base"], " con rachas" if vto["rachas"] else "", p.mando["trim"], p.camara],
	]
	if p.texto_cm != "": l.append(p.texto_cm)
	for i in l.size(): _txt(Vector2(16, 30 + 22 * i), l[i], 16)

# ---------------------------------------------------------------- horizonte con brujula
static func _recortar(poli: PackedVector2Array, n: Vector2, c: float) -> PackedVector2Array:
	# Sutherland-Hodgman contra el semiplano n.x >= c
	var out := PackedVector2Array()
	for i in poli.size():
		var a := poli[i]; var b := poli[(i + 1) % poli.size()]
		var da := n.dot(a) - c; var db := n.dot(b) - c
		if da >= 0: out.append(a)
		if (da >= 0) != (db >= 0): out.append(a.lerp(b, da / (da - db)))
	return out

func _horizonte(av: Dictionary, roll: float, pitch: float, rumbo: float) -> void:
	var R := minf(150.0, size.y * 0.17); var k := R / 150.0
	var c := Vector2(size.x - R - 20, size.y - R - 20)
	draw_circle(c, R, Color(0.04, 0.06, 0.08, 0.85))
	# bola de actitud (radio 100): cielo y tierra separados por el horizonte, girado con el alabeo y desplazado con el cabeceo
	var r_in := 100.0 * k
	var circulo := PackedVector2Array()
	for i in 64: circulo.append(c + Vector2(cos(TAU * i / 64), sin(TAU * i / 64)) * r_in)
	var ang := -roll * D2R; var abajo := Vector2(-sin(ang), cos(ang))       # normal del horizonte hacia la tierra
	var desp := pitch * HZ_PX_GRADO * k
	var c_h := abajo.dot(c) + desp
	var tierra := _recortar(circulo, abajo, c_h); var cielo := _recortar(circulo, -abajo, -c_h)
	if cielo.size() >= 3: draw_colored_polygon(cielo, Color(0.23, 0.5, 0.8))
	if tierra.size() >= 3: draw_colored_polygon(tierra, Color(0.55, 0.38, 0.2))
	var dirH := Vector2(cos(ang), sin(ang))
	for g in range(-60, 61, 10):        # escala de cabeceo
		var y := (g * HZ_PX_GRADO * k)
		var centro := c + abajo * (desp - y)
		var mitad := (40.0 if g == 0 else (22.0 if g % 20 == 0 else 12.0)) * k
		if g == 0: mitad = r_in
		var a := centro - dirH * mitad; var b := centro + dirH * mitad
		if a.distance_to(c) < r_in + 1 and b.distance_to(c) < r_in + 1:
			draw_line(a, b, Color.WHITE, 2.0 if g == 0 else 1.2, true)
			if g != 0 and g % 20 == 0: _txt(b + dirH * 3 + Vector2(0, 5), str(absi(g)), 11)
	draw_arc(c, r_in, 0, TAU, 64, Color(0.9, 0.9, 0.9, 0.6), 1.5, true)
	# avion fijo
	var amar := Color(1, 0.84, 0.31)
	draw_line(c + Vector2(-48, 0) * k, c + Vector2(-16, 0) * k, amar, 4, true); draw_line(c + Vector2(16, 0) * k, c + Vector2(48, 0) * k, amar, 4, true)
	draw_line(c + Vector2(-16, 0) * k, c + Vector2(0, 10) * k, amar, 4, true); draw_line(c + Vector2(0, 10) * k, c + Vector2(16, 0) * k, amar, 4, true)
	draw_circle(c, 3, amar)
	# rosa de rumbos en el anillo exterior: gira con el rumbo (el morro apunta arriba)
	var card := { 0: "N", 90: "E", 180: "S", 270: "W" }
	for a in range(0, 360, 5):
		var t := (a - rumbo) * D2R; var u := Vector2(sin(t), -cos(t))
		var mayor := a % 30 == 0; var largo := (14.0 if mayor else (9.0 if a % 10 == 0 else 6.0)) * k
		draw_line(c + u * (R - 4 * k), c + u * (R - 4 * k - largo), BLANCO, 2.5 if mayor else 1.2, true)
		if mayor:
			var s: String = card[a] if card.has(a) else str(a)
			var tam := int((18 if card.has(a) else 12) * maxf(k, 0.7))
			var q := c + u * (R - (34 if card.has(a) else 30) * k)
			_txt(q + Vector2(-30, tam * 0.35), s, tam, Color(0.97, 0.32, 0.29) if a == 0 else BLANCO, HORIZONTAL_ALIGNMENT_CENTER, 60)
	# marcas: casa (hacia el punto de lanzamiento) y viento (de donde viene)
	var C: Dictionary = p.casa
	var casa := atan2(C["E"] - av["p"][1], C["N"] - av["p"][0]) * R2D
	_marca(c, R, casa - rumbo, Color.WHITE, k)
	var vto: Dictionary = p.ent.viento
	if vto["base"] > 0.3: _marca(c, R, fmod(vto["rumbo"] * R2D + 180, 360) - rumbo, Color(0.31, 0.76, 0.97), k)
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -R + 2), c + Vector2(-7, -R - 10), c + Vector2(7, -R - 10)]), amar)
	_txt(c + Vector2(-40, -R - 14), "%03d°" % (int(round(fposmod(rumbo, 360))) % 360), 16, BLANCO, HORIZONTAL_ALIGNMENT_CENTER, 80)

func _marca(c: Vector2, R: float, ang: float, color: Color, k: float) -> void:
	var t := ang * D2R; var u := Vector2(sin(t), -cos(t)); var n := Vector2(-u.y, u.x)
	var a := c + u * (R - 52 * k)
	draw_colored_polygon(PackedVector2Array([a + u * 10 * k, a - u * 4 * k + n * 6 * k, a - u * 4 * k - n * 6 * k]), color)

# ---------------------------------------------------------------- anemometro y variometro
func _dial(c: Vector2, R: float) -> void:
	draw_circle(c, R, Color(0.04, 0.06, 0.08, 0.85)); draw_arc(c, R, 0, TAU, 48, Color(0.5, 0.55, 0.6), 1.5, true)

static func _pt(c: Vector2, ang_grados: float, r: float) -> Vector2:
	return c + Vector2(sin(ang_grados * D2R), -cos(ang_grados * D2R)) * r

func _anemometro(V: float) -> void:
	var R := minf(75.0, size.y * 0.085); var k := R / 75.0
	var hz := minf(150.0, size.y * 0.17)
	var c := Vector2(size.x - 2 * hz - 40 - R, size.y - R - 20 - (2 * R + 12))
	_dial(c, R)
	var vs: float = p.vel_perdida; var vmax := ceilf(2.6 * vs / 5) * 5
	var ang := func(v: float) -> float: return -135 + 270 * clampf(v / vmax, 0, 1)
	var arco := func(v0: float, v1: float, color: Color) -> void:
		draw_arc(c, 62 * k, (ang.call(v0) - 90) * D2R, (ang.call(v1) - 90) * D2R, 24, color, 5 * k, true)
	arco.call(0, 1.1 * vs, Color(0.9, 0.22, 0.21)); arco.call(1.1 * vs, 1.3 * vs, Color(1, 0.7, 0)); arco.call(1.3 * vs, minf(2 * vs, vmax), Color(0.26, 0.63, 0.28))
	if 2 * vs < vmax: arco.call(2 * vs, vmax, BLANCO)
	for v in range(0, int(vmax) + 1):
		var mayor := v % 5 == 0
		draw_line(_pt(c, ang.call(v), 56 * k), _pt(c, ang.call(v), (46 if mayor else 51) * k), BLANCO, 2 if mayor else 1, true)
		if mayor: _txt(_pt(c, ang.call(v), 36 * k) + Vector2(-15, 4), str(v), 11, BLANCO, HORIZONTAL_ALIGNMENT_CENTER, 30)
	draw_line(c, _pt(c, ang.call(V), 55 * k), Color.WHITE, 3, true); draw_circle(c, 4, Color.WHITE)
	var col := Color(1, 0.32, 0.32) if V < 1.1 * vs else (Color(1, 0.7, 0) if V < 1.3 * vs else BLANCO)
	_txt(c + Vector2(-30, 30 * k), "%.1f" % V, 15, col, HORIZONTAL_ALIGNMENT_CENTER, 60)
	_txt(c + Vector2(-30, 46 * k), "m/s", 10, BLANCO, HORIZONTAL_ALIGNMENT_CENTER, 60)

func _variometro(vz: float) -> void:
	var R := minf(75.0, size.y * 0.085); var k := R / 75.0
	var hz := minf(150.0, size.y * 0.17)
	var c := Vector2(size.x - 2 * hz - 40 - R, size.y - R - 20)
	_dial(c, R)
	var VA := 6.0
	var ang := func(v: float) -> float: return -90 + 160 * clampf(v / VA, -1, 1)
	for v in range(-6, 7):
		var mayor := v % 2 == 0
		var col := Color(0.55, 0.88, 0.56) if v > 0 else (Color(1, 0.54, 0.5) if v < 0 else Color.WHITE)
		draw_line(_pt(c, ang.call(v), 62 * k), _pt(c, ang.call(v), (50 if mayor else 56) * k), col, 2 if mayor else 1, true)
		if mayor: _txt(_pt(c, ang.call(v), 40 * k) + Vector2(-15, 4), ("+" if v > 0 else "") + str(v), 11, BLANCO, HORIZONTAL_ALIGNMENT_CENTER, 30)
	draw_line(c, _pt(c, ang.call(vz), 55 * k), Color.WHITE, 3, true); draw_circle(c, 4, Color.WHITE)
	_txt(c + Vector2(-5, 26 * k), "%+.1f" % vz, 14, BLANCO, HORIZONTAL_ALIGNMENT_CENTER, 60)

# ---------------------------------------------------------------- GPS
static func _escala_redonda(semi: float) -> float:
	var objetivo := semi * 0.5; var p10 := pow(10, floorf(log(objetivo) / log(10)))
	for f in [5.0, 2.0, 1.0]:
		if f * p10 <= objetivo: return f * p10
	return p10

func _gps(av: Dictionary, rumbo: float, suelo: float) -> void:
	var r := _rect_gps(); var W := r.size.x; var c := r.get_center()
	var N: float = av["p"][0]; var E: float = av["p"][1]
	if av["estado"] == "volando" and av["t"] - _t_estela >= 0.5: estela.append([N, E, av["t"]]); _t_estela = av["t"]
	if av["t"] < _t_estela: estela = []; _t_estela = -1.0
	while estela.size() and av["t"] - estela[0][2] > 60: estela.pop_front()
	draw_rect(r, Color(0.04, 0.06, 0.08))
	var T: Dictionary = p.ent.terreno; var tex: Texture2D = p.mundo3d.tex_region
	var semi := 3000.0 * gps_zoom; var k := W / (2 * semi)
	var mpx: float = (T["nE"] - 1) * T["paso"] / tex.get_width()           # metros por pixel de la ortofoto de la region
	var x0: float = (E - semi - T["E0"]) / mpx; var y0: float = tex.get_height() - 1 - (N + semi - T["N0"]) / mpx
	draw_texture_rect_region(tex, r, Rect2(x0, y0, 2 * semi / mpx, 2 * semi / mpx))
	var X := func(e: float) -> float: return c.x + (e - E) * k
	var Y := func(n: float) -> float: return c.y - (n - N) * k
	for l in p.mundo_datos["lugares"]:
		if l[1] <= (5 if semi < 5000 else 3) and absf(l[2] - E) < semi and absf(l[3] - N) < semi:
			var q := Vector2(X.call(l[2]), Y.call(l[3])); draw_rect(Rect2(q - Vector2(1.5, 1.5), Vector2(3, 3)), Color.WHITE)
			_txt(q + Vector2(3, -3), l[0], 10)
	if estela.size() > 1:
		var pts := PackedVector2Array()
		for s in estela: pts.append(Vector2(X.call(s[1]), Y.call(s[0])))
		pts.append(c); draw_polyline(pts, Color(1, 0.84, 0.31, 0.8), 1.5, true)
	var C: Dictionary = p.casa; var d := Vector2(N - C["N"], E - C["E"]).length()
	if absf(E - C["E"]) < semi and absf(N - C["N"]) < semi: draw_circle(Vector2(X.call(C["E"]), Y.call(C["N"])), 3.5, Color.WHITE)
	else:
		var a := atan2(C["E"] - E, C["N"] - N); var u := Vector2(sin(a), -cos(a)); var q := c + u * (W / 2 - 14); var nn := Vector2(-u.y, u.x)
		draw_colored_polygon(PackedVector2Array([q + u * 7, q - u * 5 + nn * 5, q - u * 5 - nn * 5]), Color.WHITE)
	var t := rumbo * D2R; var u2 := Vector2(sin(t), -cos(t)); var n2 := Vector2(-u2.y, u2.x)
	var avion := PackedVector2Array([c + u2 * 9, c - u2 * 7 + n2 * 6, c - u2 * 4, c - u2 * 7 - n2 * 6])
	draw_colored_polygon(avion, Color(1, 0.84, 0.31)); draw_polyline(avion + PackedVector2Array([avion[0]]), Color.BLACK, 1, true)
	var vto: Dictionary = p.ent.viento
	if vto["base"] > 0.3:
		var q := r.position + Vector2(W - 18, 18); var ru: float = vto["rumbo"]; var uu := Vector2(sin(ru), -cos(ru)); var nu := Vector2(-uu.y, uu.x)
		draw_line(q - uu * 8, q + uu * 8, Color(0.31, 0.76, 0.97), 2, true)
		draw_line(q + uu * 8, q + uu * 3 + nu * 4, Color(0.31, 0.76, 0.97), 2, true); draw_line(q + uu * 8, q + uu * 3 - nu * 4, Color(0.31, 0.76, 0.97), 2, true)
	_txt(r.position + Vector2(6, 16), "N", 12)
	_txt(r.position + Vector2(6, 32), "alt %.0f m" % maxf(0, -av["p"][2] - suelo), 13)
	if av["motorRoto"]: _txt(r.position + Vector2(6, 48), "MOTOR PARADO", 13, Color(1, 0.32, 0.32))
	var esc := _escala_redonda(semi)
	draw_line(r.position + Vector2(8, W - 10), r.position + Vector2(8 + esc * k, W - 10), BLANCO, 2)
	_txt(r.position + Vector2(10, W - 14), (str(esc / 1000) + " km") if esc >= 1000 else (str(int(esc)) + " m"), 11)
	_txt(r.position + Vector2(W - 90, W - 14), "casa " + (("%.1f km" % (d / 1000)) if d >= 1000 else ("%.0f m" % d)), 11, BLANCO, HORIZONTAL_ALIGNMENT_RIGHT, 84)
	draw_rect(r, Color(0.5, 0.55, 0.6), false, 1.5)

# ---------------------------------------------------------------- gases, palanca, ayuda
func _gases(av: Dictionary) -> void:
	var r := Rect2(size.x - 34, 20, 14, 160)
	draw_rect(r, Color(0, 0, 0, 0.5)); var h: float = r.size.y * av["gases"]
	draw_rect(Rect2(r.position.x, r.end.y - h, r.size.x, h), Color(1, 0.6, 0.15)); draw_rect(r, BLANCO, false, 1)
	_txt(Vector2(r.position.x - 30, r.end.y + 18), "gas", 12, BLANCO, HORIZONTAL_ALIGNMENT_CENTER, 74)

func _palanca() -> void:
	var r := Rect2(size.x - 130, 20, 80, 80)
	draw_rect(r, Color(0, 0, 0, 0.4)); draw_rect(r, Color(1, 1, 1, 0.5), false, 1)
	draw_line(r.get_center() - Vector2(0, 40), r.get_center() + Vector2(0, 40), Color(1, 1, 1, 0.25)); draw_line(r.get_center() - Vector2(40, 0), r.get_center() + Vector2(40, 0), Color(1, 1, 1, 0.25))
	draw_circle(r.position + Vector2(40 + 36 * p.mando["yaw"], 40 + 36 * p.mando["pitch"]), 5, Color(1, 0.84, 0.31))

func _ayuda() -> void:
	var l := [
		"TECLADO: flechas = palanca (abajo tira) · W/S gases · Espacio cortar motor · L lanzar · R reiniciar · Esc menú",
		"1/2/3 cámaras (piloto, persecución, a bordo) · [ ] compensador · H texto · I instrumentos · G rachas · +/- viento",
		"MANDO: palanca derecha = avión, palanca izquierda = gas · A lanzar · B cortar · X reiniciar · Y cámara · Start terminar · cruceta compensador",
		"La rueda del ratón sobre el GPS cambia su zoom. T oculta esta ayuda.",
	]
	var h := 26.0 * l.size() + 20
	draw_rect(Rect2(size.x * 0.08, size.y * 0.38, size.x * 0.84, h), Color(0, 0, 0, 0.7))
	for i in l.size(): _txt(Vector2(size.x * 0.08 + 16, size.y * 0.38 + 30 + 26 * i), l[i], 15)
