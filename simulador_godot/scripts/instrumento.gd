class_name Instrumento
extends Control
## Un instrumento del panel de vuelo, dibujado como el SVG o el lienzo de simulador/simulador.html:
##  "vario"  variometro (viewBox 150): -6 a +6 m/s, aguja y cifra
##  "anemo"  anemometro (viewBox 150) con las bandas del avion (construirAnemometro): rojo < 1,1 Vs, ambar < 1,3 Vs,
##           verde < 2 Vs, blanco por encima
##  "horiz"  horizonte artificial con brujula (viewBox 300): rosa de rumbos que gira, marcas de casa y del viento, bola
##           de actitud con la escalera de cabeceo, marcas de alabeo fijas y rumbo abajo
##  "gps"    mapa (200 px): campo del club (pista, pilones, zona 2, piloto, estela, avion) o mundo real (ortofoto,
##           carreteras, pueblos, casa); la rueda del raton encima cambia el zoom
##  "barra"  barra de gas (16 x 84) y palanca (84 x 84)
## p es la escena principal (estado del vuelo).

const D2R := PI / 180.0
const R2D := 180.0 / PI
const HZ_PX_GRADO := 3.2
const VA_MAX := 6.0
const TXT := Color("#e6edf3")

var tipo := ""
var p: Node
var gps_zoom := 1.0
var estela := []
var _t_estela := -1.0
var _mapa_mundo: ImageTexture        # GPS del mundo real: el mapa entero a 2 px por nodo, hecho una vez
var _mapa_de := ""

func _init(tipo_: String, p_: Node) -> void:
	tipo = tipo_; p = p_
	var tam := { "vario": 124, "anemo": 124, "horiz": 190, "gps": 190 }
	if tipo == "barra": custom_minimum_size = Vector2(16 + 8 + 84, 84)
	else: custom_minimum_size = Vector2(tam[tipo], tam[tipo])
	size_flags_vertical = Control.SIZE_SHRINK_END
	mouse_filter = Control.MOUSE_FILTER_STOP if tipo == "gps" else Control.MOUSE_FILTER_IGNORE
	clip_contents = tipo == "gps"          # el lienzo de la web recorta lo que cae fuera del mapa

func _gui_input(ev: InputEvent) -> void:
	if tipo == "gps" and ev is InputEventMouseButton and ev.pressed:
		if ev.button_index == MOUSE_BUTTON_WHEEL_UP: gps_zoom = maxf(0.12, gps_zoom * 0.8); accept_event()
		elif ev.button_index == MOUSE_BUTTON_WHEEL_DOWN: gps_zoom = minf(8.0, gps_zoom * 1.25); accept_event()

func _process(_dt: float) -> void:
	if is_visible_in_tree(): queue_redraw()

func _fuente() -> Font: return Tema.fuente if Tema.fuente else ThemeDB.fallback_font
func _negr() -> Font: return Tema.negrita if Tema.negrita else ThemeDB.fallback_font

## Texto centrado (o alineado) en una posicion de la caja del SVG.
func _txt(pos: Vector2, s: String, tam: float, color: Color, negr := false, alin := HORIZONTAL_ALIGNMENT_CENTER) -> void:
	var f := _negr() if negr else _fuente()
	var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, int(tam)).x
	var x := pos.x - (w / 2 if alin == HORIZONTAL_ALIGNMENT_CENTER else (w if alin == HORIZONTAL_ALIGNMENT_RIGHT else 0.0))
	draw_string(f, Vector2(x, pos.y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, int(tam), color)

func _draw() -> void:
	if p == null or p.av.is_empty(): return
	match tipo:
		"vario": _vario()
		"anemo": _anemo()
		"horiz": _horiz()
		"gps": _gps()
		"barra": _barra()

func _sombra(c: Vector2, r: float) -> void:
	for i in 4: draw_circle(c + Vector2(0, 2), r + 1 + i * 1.5, Color(0, 0, 0, 0.12 - i * 0.025))

# ---------------------------------------------------------------- variometro y anemometro (viewBox 150)
func _esfera(k: float) -> void:
	var c := Vector2(75, 75) * k
	_sombra(c, 73 * k)
	draw_circle(c, 73 * k, Color(11 / 255.0, 15 / 255.0, 20 / 255.0, 0.85)); draw_arc(c, 73 * k, 0, TAU, 64, Color("#3d4956"), 2 * k, true)

static func _pt(ang: float, r: float, k: float) -> Vector2: return Vector2(75 + r * sin(ang * D2R), 75 - r * cos(ang * D2R)) * k

func _vario() -> void:
	var k := size.x / 150.0; _esfera(k)
	var vang := func(vz: float) -> float: return -90 + 135 * clampf(vz / VA_MAX, -1, 1)
	for vz in range(-6, 7):
		var mayor := vz % 2 == 0
		var col := Color("#8be08f") if vz > 0 else (Color("#ff8a80") if vz < 0 else Color.WHITE)
		draw_line(_pt(vang.call(vz), 62, k), _pt(vang.call(vz), 50 if mayor else 56, k), col, (2 if mayor else 1) * k, true)
		if mayor: _txt(_pt(vang.call(vz), 40, k) + Vector2(0, 4 * k), ("+" if vz > 0 else "") + str(vz), 11 * k, TXT)
	var vs: float = p.lectura_vs()
	draw_line(Vector2(75, 75) * k, _pt(vang.call(vs), 55, k), Color.WHITE, 3 * k, true); draw_circle(Vector2(75, 75) * k, 5 * k, Color.WHITE)
	_txt(Vector2(75, 118) * k, ("+" if vs >= 0 else "") + "%.1f" % vs, 17 * k, TXT, true)
	_txt(Vector2(75, 134) * k, "m/s · asc. / desc.", 9 * k, Color("#8b949e"))

func _anemo() -> void:
	var k := size.x / 150.0; _esfera(k)
	var vs: float = p.vel_perdida if p.vel_perdida > 0 else 0.0
	var vmax: float = ceilf(2.6 * vs / 5) * 5 if vs > 0 else 20.0
	var aang := func(v: float) -> float: return -135 + 270 * clampf(v / vmax, 0, 1)
	var arco := func(v0: float, v1: float, color: Color) -> void:
		draw_arc(Vector2(75, 75) * k, 62 * k, (aang.call(v0) - 90) * D2R, (aang.call(v1) - 90) * D2R, 32, color, 9 * k, true)
	if vs > 0:
		arco.call(0, 1.1 * vs, Color("#e53935")); arco.call(1.1 * vs, 1.3 * vs, Color("#ffb300")); arco.call(1.3 * vs, minf(2 * vs, vmax), Color("#43a047"))
	if 2 * vs < vmax: arco.call(2 * vs, vmax, TXT)
	for v in range(0, int(vmax) + 1):
		var mayor := v % 5 == 0
		draw_line(_pt(aang.call(v), 56, k), _pt(aang.call(v), 46 if mayor else 51, k), TXT, (2 if mayor else 1) * k, true)
		if mayor: _txt(_pt(aang.call(v), 36, k) + Vector2(0, 4 * k), str(v), 11 * k, TXT)
	var V: float = p.av["V"]
	draw_line(Vector2(75, 75) * k, _pt(aang.call(V), 55, k), Color.WHITE, 3 * k, true); draw_circle(Vector2(75, 75) * k, 5 * k, Color.WHITE)
	var col := Color("#ff5252") if (vs > 0 and V < 1.1 * vs) else (Color("#ffb300") if (vs > 0 and V < 1.3 * vs) else TXT)
	_txt(Vector2(75, 118) * k, "%.1f" % V, 17 * k, col, true)
	_txt(Vector2(75, 134) * k, "m/s · vel. aire", 9 * k, Color("#8b949e"))

# ---------------------------------------------------------------- horizonte con brujula (viewBox 300)
static func _rot(pt: Vector2, ang_grados: float, c := Vector2(150, 150)) -> Vector2:
	return c + (pt - c).rotated(ang_grados * D2R)

static func _recortar(poli: PackedVector2Array, n: Vector2, c: float) -> PackedVector2Array:
	var out := PackedVector2Array()            # Sutherland-Hodgman contra el semiplano n.x >= c
	for i in poli.size():
		var a := poli[i]; var b := poli[(i + 1) % poli.size()]
		var da := n.dot(a) - c; var db := n.dot(b) - c
		if da >= 0: out.append(a)
		if (da >= 0) != (db >= 0): out.append(a.lerp(b, da / (da - db)))
	return out

func _horiz() -> void:
	var k := size.x / 300.0; var av: Dictionary = p.av
	var e := Cuat.euler(av["q"]); var roll: float = e[0] * R2D; var pitch: float = e[1] * R2D; var rumbo: float = e[2] * R2D
	var C := func(v: Vector2) -> Vector2: return v * k
	_sombra(C.call(Vector2(150, 150)), 148 * k)
	draw_circle(C.call(Vector2(150, 150)), 148 * k, Color(11 / 255.0, 15 / 255.0, 20 / 255.0, 0.85)); draw_arc(C.call(Vector2(150, 150)), 148 * k, 0, TAU, 96, Color("#3d4956"), 2 * k, true)
	# rosa de rumbos (gira con -rumbo)
	var card := { 0: "N", 90: "E", 180: "S", 270: "W" }
	for a in range(0, 360, 5):
		var mayor := a % 30 == 0; var ang: float = a - rumbo
		draw_line(C.call(_rot(Vector2(150, 4), ang)), C.call(_rot(Vector2(150, 18 if mayor else (13 if a % 10 == 0 else 10)), ang)), TXT, (3 if mayor else 1.5) * k, true)
		if mayor:
			var es_card := card.has(a)
			var q: Vector2 = C.call(_rot(Vector2(150, 40 if es_card else 34), ang))
			var tam := (20 if es_card else 12) * k
			_txt(q + Vector2(0, tam * 0.35), card[a] if es_card else str(a), tam, Color("#f85149") if a == 0 else TXT, es_card)
	# marcas sobre la rosa: casa (hacia el punto de lanzamiento) y viento (de donde viene)
	var casa := atan2(p.casa["E"] - av["p"][1], p.casa["N"] - av["p"][0]) * R2D
	var tri := func(pts: Array, ang: float, color: Color) -> void:
		var poli := PackedVector2Array()
		for q in pts: poli.append(C.call(_rot(q, ang)))
		draw_colored_polygon(poli, color); poli.append(poli[0]); draw_polyline(poli, Color.BLACK, 1 * k, true)
	tri.call([Vector2(150, 20), Vector2(142, 34), Vector2(158, 34)], casa - rumbo, Color("#ffd54f"))
	var vto: Dictionary = p.ent.viento
	if vto["base"] > 0.3: tri.call([Vector2(150, 24), Vector2(141, 12), Vector2(159, 12)], fmod(vto["rumbo"] * R2D + 180, 360) - rumbo, Color("#4fc3f7"))
	# bola de actitud (radio 98): cielo y tierra, horizonte y escalera, girados con -alabeo y desplazados con el cabeceo
	var circulo := PackedVector2Array()
	for i in 72: circulo.append(C.call(Vector2(150, 150) + Vector2(cos(TAU * i / 72), sin(TAU * i / 72)) * 98))
	var t := func(q: Vector2) -> Vector2: return C.call(_rot(q + Vector2(0, pitch * HZ_PX_GRADO), -roll))
	var abajo := Vector2(0, 1).rotated(-roll * D2R)
	var h0: Vector2 = t.call(Vector2(150, 150))
	var c_h := abajo.dot(h0)
	var tierra := _recortar(circulo, abajo, c_h); var cielo := _recortar(circulo, -abajo, -c_h)
	if cielo.size() >= 3: draw_colored_polygon(cielo, Color("#1f7ae0"))
	if tierra.size() >= 3: draw_colored_polygon(tierra, Color("#6b4a1e"))
	var centro: Vector2 = C.call(Vector2(150, 150))
	var dentro := func(q: Vector2) -> bool: return q.distance_to(centro) < 98 * k
	var dirh := Vector2(1, 0).rotated(-roll * D2R)
	var lin := func(a: Vector2, b: Vector2, w: float) -> void:      # segmento recortado al circulo de la bola
		var pa: Vector2 = t.call(a); var pb: Vector2 = t.call(b)
		var d := pb - pa; var f := pa - centro; var R := 98 * k
		var A := d.dot(d); var B := 2 * f.dot(d); var Cc := f.dot(f) - R * R; var disc := B * B - 4 * A * Cc
		if disc <= 0: return
		var s0 := clampf((-B - sqrt(disc)) / (2 * A), 0, 1); var s1 := clampf((-B + sqrt(disc)) / (2 * A), 0, 1)
		if s1 > s0: draw_line(pa + d * s0, pa + d * s1, Color.WHITE, w * k, true)
	lin.call(Vector2(-600, 150), Vector2(900, 150), 1.5)
	for pp in range(-40, 45, 5):
		if pp == 0: continue
		var y := 150 - pp * HZ_PX_GRADO; var medio := 34.0 if pp % 10 == 0 else 12.0
		lin.call(Vector2(150 - medio, y), Vector2(150 + medio, y), 1.5)
		if pp % 10 == 0:
			for lado in [-1, 1]:
				var q: Vector2 = t.call(Vector2(150 + lado * (medio + 6), y + 4))
				if dentro.call(q): _txt(q, str(pp), 11 * k, Color.WHITE, false, HORIZONTAL_ALIGNMENT_RIGHT if lado < 0 else HORIZONTAL_ALIGNMENT_LEFT)
	draw_arc(centro, 98 * k, 0, TAU, 72, Color("#3d4956"), 2 * k, true)
	# marcas de alabeo fijas, indice, avion fijo, linea de fe roja y rumbo
	for a in [-60, -45, -30, -20, -10, 0, 10, 20, 30, 45, 60]:
		draw_line(C.call(_rot(Vector2(150, 52), a)), C.call(_rot(Vector2(150, 62 if a % 30 == 0 else 58), a)), Color.WHITE, (3 if a == 0 else 1.5) * k, true)
	draw_colored_polygon(PackedVector2Array([C.call(Vector2(150, 58)), C.call(Vector2(144, 70)), C.call(Vector2(156, 70))]), Color.WHITE)
	draw_arc(centro, 9 * k, 0, TAU, 24, Color.WHITE, 2.5 * k, true)
	draw_line(C.call(Vector2(100, 150)), C.call(Vector2(132, 150)), Color.WHITE, 3 * k, true); draw_line(C.call(Vector2(168, 150)), C.call(Vector2(200, 150)), Color.WHITE, 3 * k, true)
	draw_colored_polygon(PackedVector2Array([C.call(Vector2(150, 3)), C.call(Vector2(143, 16)), C.call(Vector2(157, 16))]), Color("#f85149"))
	_txt(C.call(Vector2(150, 290)), "%03d°" % (int(round(fposmod(rumbo + 360, 360))) % 360), 16 * k, TXT, true)

# ---------------------------------------------------------------- GPS
static func escala_redonda(semi: float) -> float:
	var mejor := 50.0
	for c in [50.0, 100.0, 200.0, 500.0, 1000.0, 2000.0, 5000.0, 10000.0]:
		if absf(c - semi / 3) < absf(mejor - semi / 3): mejor = c
	return mejor

func _gps() -> void:
	var av: Dictionary = p.av; var W := size.x; var k0 := W / 200.0
	var N: float = av["p"][0]; var E: float = av["p"][1]
	if av["estado"] == "volando" and av["t"] - _t_estela >= 0.5: estela.append([N, E, av["t"]]); _t_estela = av["t"]
	if av["t"] < _t_estela: estela = []; _t_estela = -1.0
	while estela.size() and av["t"] - estela[0][2] > 60: estela.pop_front()
	# sombra y fondo con esquinas redondeadas
	draw_style_box(Tema.caja(Color(0, 0, 0, 0.25), Color(0, 0, 0, 0), 12), Rect2(Vector2(0, 2), size + Vector2(0, 2)))
	var rumbo: float = Cuat.euler(av["q"])[2] * R2D
	if p.en_mundo(): _gps_mundo(W, k0, N, E, rumbo)
	else: _gps_campo(W, k0, N, E, rumbo)

func _flecha_viento(W: float, k0: float) -> void:
	var vto: Dictionary = p.ent.viento
	if vto["base"] <= 0.3: return
	var q := Vector2(W - 18 * k0, 18 * k0); var ru: float = vto["rumbo"]; var u := Vector2(sin(ru), -cos(ru)); var n := Vector2(-u.y, u.x)
	var c := Color("#4fc3f7")
	draw_line(q - u * 8 * k0, q + u * 8 * k0, c, 2, true)
	draw_line(q + u * 8 * k0, q + u * 3 * k0 + n * 4 * k0, c, 2, true); draw_line(q + u * 8 * k0, q + u * 3 * k0 - n * 4 * k0, c, 2, true)

func _avion_gps(q: Vector2, rumbo: float, k0: float) -> void:
	var u := Vector2(sin(rumbo * D2R), -cos(rumbo * D2R)); var n := Vector2(-u.y, u.x)
	var poli := PackedVector2Array([q + u * 9 * k0, q - u * 7 * k0 + n * 6 * k0, q - u * 4 * k0, q - u * 7 * k0 - n * 6 * k0])
	draw_colored_polygon(poli, Color("#ffd54f")); poli.append(poli[0]); draw_polyline(poli, Color.BLACK, 1, true)

func _textos_gps(W: float, k0: float, alt: float, escala: float, esc_px: float, dcha: String) -> void:
	_txt(Vector2(6, 14) * k0, "N", 11 * k0, TXT, true, HORIZONTAL_ALIGNMENT_LEFT)
	_txt(Vector2(6, 30) * k0, "alt %d m" % int(round(maxf(0, alt))), 12 * k0, TXT, true, HORIZONTAL_ALIGNMENT_LEFT)
	if p.av["motorRoto"]: _txt(Vector2(6, 46) * k0, "MOTOR PARADO", 12 * k0, Color("#ff5252"), true, HORIZONTAL_ALIGNMENT_LEFT)
	draw_line(Vector2(8 * k0, W - 10 * k0), Vector2(8 * k0 + esc_px, W - 10 * k0), TXT, 2)
	_txt(Vector2(10 * k0, W - 14 * k0), (str(int(escala / 1000)) + " km") if escala >= 1000 else (str(int(escala)) + " m"), 10 * k0, TXT, false, HORIZONTAL_ALIGNMENT_LEFT)
	_txt(Vector2(W - 6 * k0, W - 14 * k0), dcha, 10 * k0, TXT, false, HORIZONTAL_ALIGNMENT_RIGHT)

## Multijugador: los demas de la sala en el GPS, triangulos azules con su rumbo (pintarOtrosGPS de la web).
func _otros_gps(X: Callable, Y: Callable, W: float) -> void:
	if p.sala.is_empty(): return
	for z in p.ordenes.get("zonas", []):                # zonas de exclusion del profesor (recortadas al mapa)
		var k: float = absf(X.call(z["E"] + 100.0) - X.call(z["E"])) / 100.0; var c := Vector2(X.call(z["E"]), Y.call(z["N"])); var pts := PackedVector2Array()
		for i in 48: pts.append((c + Vector2(cos(i * TAU / 48), sin(i * TAU / 48)) * z["r"] * k).clamp(Vector2.ZERO, Vector2(W, W)))
		draw_colored_polygon(pts, Color(0.9, 0.22, 0.21, 0.28)); pts.append(pts[0]); draw_polyline(pts, Color("#e53935"), 2, true)
	for id in p.multi_otros:
		var o: Dictionary = p.multi_otros[id]; var c := Vector2(X.call(o["p"][1]), Y.call(o["p"][0]))
		if c.x < 0 or c.y < 0 or c.x > W or c.y > W: continue
		var a: float = Cuat.euler(o["q"])[2]; var u := Vector2(sin(a), -cos(a)); var n := Vector2(-u.y, u.x)
		var pts := PackedVector2Array([c + u * 7, c - u * 5 + n * 5, c - u * 3, c - u * 5 - n * 5])
		draw_colored_polygon(pts, Color("#4fc3f7")); pts.append(pts[0]); draw_polyline(pts, Color.BLACK, 1, true)

## dron comercial: como en las apps de los drones comerciales, el punto de despegue con su H amarilla y una linea del dron hasta el, recortada al mapa (casaDJI).
func _es_dji() -> bool: return p.modelo != null and p.es_dron() and not p.es_fpv()
func _casa_dji(a: Vector2, h: Vector2, W: float) -> void:
	var d := h - a; var dentro := maxf(absf(h.x - W / 2), absf(h.y - W / 2)) <= W / 2 - 8
	if not dentro:
		var k := 1.0
		if d.x > 0: k = minf(k, (W - 3 - a.x) / d.x)
		elif d.x < 0: k = minf(k, (3 - a.x) / d.x)
		if d.y > 0: k = minf(k, (W - 3 - a.y) / d.y)
		elif d.y < 0: k = minf(k, (3 - a.y) / d.y)
		d *= k
	draw_dashed_line(a, a + d, Color(1, 1, 1, 0.9), 1.5, 4.0)
	if dentro:
		draw_circle(h, 7, Color("#ffc83d")); draw_arc(h, 7, 0, TAU, 20, Color.BLACK, 1, true)
		draw_string(Tema.negrita, h + Vector2(-3.6, 3.6), "H", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("#111111"))

func _gps_campo(W: float, k0: float, N: float, E: float, rumbo: float) -> void:
	draw_style_box(Tema.caja(Color(11 / 255.0, 15 / 255.0, 20 / 255.0, 0.85), Color(0, 0, 0, 0), 10), Rect2(Vector2.ZERO, size))
	var cN := N / 2; var cE := E / 2
	var semi := maxf(150, 0.62 * maxf(absf(N), absf(E)) + 40) * gps_zoom; var k := W / 2 / semi
	var X := func(e: float) -> float: return W / 2 + (e - cE) * k
	var Y := func(n: float) -> float: return W / 2 - (n - cN) * k
	var ent: Entorno = p.ent; var P: Dictionary = ent.pista; var Z: Dictionary = ent.zona2
	var rr := func(x0: float, y0: float, w: float, h: float, c: Color) -> void:
		var r := Rect2(x0, y0, w, h).intersection(Rect2(Vector2.ZERO, size))
		if r.has_area(): draw_rect(r, c)
	rr.call(X.call(-P["ancho"] / 2), Y.call(P["n1"]), P["ancho"] * k, (P["n1"] - P["n0"]) * k, Color("#9e9e9e"))
	var P2: Dictionary = Z["pista"]
	rr.call(X.call(P2["e0"]), Y.call(P2["n"] + P2["ancho"] / 2), (P2["e1"] - P2["e0"]) * k, P2["ancho"] * k, Color("#8d6e63"))
	var D: Dictionary = Z["diana"]
	for an in D["anillos"]: draw_arc(Vector2(X.call(D["e"]), Y.call(D["n"])), maxf(1.5, an[0] * k), 0, TAU, 32, Color("#e0e0e0"), 1, true)
	var Pu: Dictionary = Z["puerta"]
	for q in [[Pu["n0"], Pu["e"]], [Pu["n1"], Pu["e"]]]: draw_circle(Vector2(X.call(q[1]), Y.call(q[0])), 3, Color(Pu["color"]["hex"]))
	var pil: Array = ent.circuito["pilones"]
	for i in pil.size():
		var q := Vector2(X.call(pil[i][1]), Y.call(pil[i][0]))
		draw_circle(q, 4, Color(ent.circuito["colores"][i]["hex"])); draw_arc(q, 4, 0, TAU, 16, Color.WHITE, 1, true)
	draw_circle(Vector2(X.call(0), Y.call(0)), 3.5, Color.WHITE)
	if estela.size() > 1:
		var pts := PackedVector2Array()
		for s in estela: pts.append(Vector2(X.call(s[1]), Y.call(s[0])))
		pts.append(Vector2(X.call(E), Y.call(N))); draw_polyline(pts, Color(1, 213 / 255.0, 79 / 255.0, 0.8), 1.5, true)
	if _es_dji(): _casa_dji(Vector2(X.call(E), Y.call(N)), Vector2(X.call(0), Y.call(0)), W)
	_otros_gps(X, Y, W)
	_avion_gps(Vector2(X.call(E), Y.call(N)), rumbo, k0)
	_flecha_viento(W, k0)
	var esc := escala_redonda(semi)
	_textos_gps(W, k0, -p.av["p"][2], esc, esc * k, "%d m" % int(round(Vector2(N, E).length())))

func _mapa_del_mundo() -> ImageTexture:
	# el mapa del GPS en un mundo real: la ortofoto de la region y las carreteras, a 2 px por nodo del terreno
	var M: Dictionary = p.mundo_datos; var T: Dictionary = p.ent.terreno
	if _mapa_mundo != null and _mapa_de == M.get("id", ""): return _mapa_mundo
	var PX := 2; var w: int = T["nE"] * PX; var h: int = T["nN"] * PX
	var img: Image
	var orto: Image = p.orto[0] if p.orto.size() else null
	if orto: img = orto.duplicate(); img.resize(w, h, Image.INTERPOLATE_BILINEAR)
	else: img = Image.create(w, h, false, Image.FORMAT_RGBA8); img.fill(Color("#8a8a7a"))
	img.convert(Image.FORMAT_RGBA8)
	var X := func(e: float) -> float: return (e - T["E0"]) / T["paso"] * PX
	var Y := func(n: float) -> float: return (T["nN"] - 1 - (n - T["N0"]) / T["paso"]) * PX
	var colores := { 1: Color("#ffb74d"), 2: Color("#fff176"), 3: Color("#f5f5f5"), 4: Color("#cfd8dc") }
	for tt in [4, 3, 2, 1]:
		for cc in M["carreteras"]:
			if int(cc[0]) != tt: continue
			var prev := Vector2.INF
			for i in range(1, cc.size(), 2):
				var q := Vector2(X.call(cc[i]), Y.call(cc[i + 1]))
				if prev != Vector2.INF: _linea_img(img, prev, q, colores[tt])
				prev = q
	_mapa_mundo = ImageTexture.create_from_image(img); _mapa_de = M.get("id", "")
	return _mapa_mundo

static func _linea_img(img: Image, a: Vector2, b: Vector2, c: Color) -> void:
	var n := int(maxf(absf(b.x - a.x), absf(b.y - a.y))) + 1
	for i in n + 1:
		var q := a.lerp(b, float(i) / n)
		if q.x >= 0 and q.y >= 0 and q.x < img.get_width() and q.y < img.get_height(): img.set_pixelv(Vector2i(q), c)

func _gps_mundo(W: float, k0: float, N: float, E: float, rumbo: float) -> void:
	var T: Dictionary = p.ent.terreno; var PX := 2.0
	var tex := _mapa_del_mundo()
	draw_style_box(Tema.caja(Color("#0b0f14"), Color(0, 0, 0, 0), 10), Rect2(Vector2.ZERO, size))
	var semi := (400.0 if (p.es_dron() and not p.es_fpv()) else 3000.0) * gps_zoom; var k := W / (2 * semi); var mpx: float = PX / T["paso"]   # un dron trabaja a cientos de metros
	var sx: float = (E - T["E0"]) / T["paso"] * PX - semi * mpx; var sy: float = (T["nN"] - 1 - (N - T["N0"]) / T["paso"]) * PX - semi * mpx
	draw_texture_rect_region(tex, Rect2(Vector2.ZERO, size), Rect2(sx, sy, 2 * semi * mpx, 2 * semi * mpx))
	var X := func(e: float) -> float: return W / 2 + (e - E) * k
	var Y := func(n: float) -> float: return W / 2 - (n - N) * k
	if p.mundo3d != null:                              # dentro de las zonas de detalle, su ortofoto (0,25-0,5 m) encima, recortada al mapa
		var vista := Rect2(Vector2.ZERO, Vector2(W, W))
		for t in p.mundo3d.mapa_zonas:
			var r := Rect2(X.call(t["E0"]), Y.call(t["N0"] + t["lado"]), t["lado"] * k, t["lado"] * k)
			var dentro := r.intersection(vista)
			if dentro.size.x <= 0 or dentro.size.y <= 0: continue
			var ts: Vector2 = (t["tex"] as Texture2D).get_size()
			draw_texture_rect_region(t["tex"], dentro, Rect2((dentro.position - r.position) / r.size * ts, dentro.size / r.size * ts))
	var op: Dictionary = Escenarios.datos()[p.sesion["escenario"]].get("operacion", {})
	if op.has("planta") and not op["planta"].has("rumbo"):     # paneles: las filas de la planta, si no estan en la ortofoto (en SABIC si)
		var PL: Dictionary = op["planta"]; var fondo: float = PL["ancho"] * cos(PL["inclinacion"] * PI / 180)
		for i in int(PL["filas"]):
			var n: float = PL["n0"] + i * PL["separacion"]
			var r := Rect2(X.call(PL["e0"]), Y.call(n + fondo / 2), PL["largo"] * k, maxf(1, fondo * k)).intersection(Rect2(0, 0, W, W))
			if r.size.x > 0 and r.size.y > 0: draw_rect(r, Color("#182c52"))
	for l in p.mundo_datos["lugares"]:
		if l[1] <= (5 if semi < 5000 else 3) and absf(l[2] - E) < semi and absf(l[3] - N) < semi:
			var q := Vector2(X.call(l[2]), Y.call(l[3]))
			draw_rect(Rect2(q - Vector2(1.5, 1.5), Vector2(3, 3)), Color.WHITE); _txt(q + Vector2(3, -3), String(l[0]), 10 * k0, Color.WHITE, true, HORIZONTAL_ALIGNMENT_LEFT)
	if estela.size() > 1:
		var pts := PackedVector2Array()
		for s in estela: pts.append(Vector2(X.call(s[1]), Y.call(s[0])))
		pts.append(Vector2(W / 2, W / 2)); draw_polyline(pts, Color(1, 213 / 255.0, 79 / 255.0, 0.8), 1.5, true)
	var C: Dictionary = p.casa; var d := Vector2(N - C["N"], E - C["E"]).length()
	if _es_dji(): _casa_dji(Vector2(W / 2, W / 2), Vector2(X.call(C["E"]), Y.call(C["N"])), W)
	_otros_gps(X, Y, W)
	if absf(E - C["E"]) < semi and absf(N - C["N"]) < semi: draw_circle(Vector2(X.call(C["E"]), Y.call(C["N"])), 3.5, Color.WHITE)
	else:
		var a := atan2(C["E"] - E, C["N"] - N); var u := Vector2(sin(a), -cos(a)); var nn := Vector2(-u.y, u.x); var q := Vector2(W / 2, W / 2) + u * (W / 2 - 14)
		draw_colored_polygon(PackedVector2Array([q + u * 7, q - u * 5 + nn * 5, q - u * 5 - nn * 5]), Color.WHITE)
	_avion_gps(Vector2(W / 2, W / 2), rumbo, k0)
	_flecha_viento(W, k0)
	var esc := escala_redonda(semi)
	_textos_gps(W, k0, -p.av["p"][2] - p.ent.altura(N, E), esc, esc * k, "casa " + (("%.1f km" % (d / 1000)) if d >= 1000 else ("%d m" % int(round(d)))))

# ---------------------------------------------------------------- gas y palanca
func _barra() -> void:
	var av: Dictionary = p.av
	var g := Rect2(0, 0, 16, 84)
	draw_style_box(Tema.caja(Color(0, 0, 0, 0.4), Color(1, 1, 1, 0.35), 6), g)
	var h: float = 84 * clampf(av["gases"], 0, 1)
	if h > 1:     # degradado verde -> amarillo desde abajo (linear-gradient(0deg, #58d06a, #ffc83d))
		var pts := PackedVector2Array([Vector2(1, 84 - h), Vector2(15, 84 - h), Vector2(15, 83), Vector2(1, 83)])
		var c1 := Color("#58d06a"); var c2 := Color("#58d06a").lerp(Color("#ffc83d"), h / 84)
		draw_polygon(pts, PackedColorArray([c2, c2, c1, c1]))
	var m := Rect2(24, 0, 84, 84)
	draw_style_box(Tema.caja(Color(0, 0, 0, 0.4), Color(1, 1, 1, 0.35), 10), m)
	draw_line(Vector2(66, 6), Vector2(66, 78), Color(1, 1, 1, 0.15)); draw_line(Vector2(30, 42), Vector2(102, 42), Color(1, 1, 1, 0.15))
	var q := Vector2(24 + 84 * (0.5 + 0.45 * p.mando["yaw"]), 84 * (0.5 + 0.45 * p.mando["pitch"]))
	draw_circle(q, 8, Color(0, 0, 0, 0.35)); draw_circle(q, 6, Tema.ACENTO)
