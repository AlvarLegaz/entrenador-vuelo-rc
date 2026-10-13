class_name MapaLanzamiento
extends Control
## Mapa para elegir el punto de lanzamiento, como pintarMapaLanz del navegador: la ortofoto de la region, las
## carreteras por tipo, los pueblos, las zonas de detalle (recuadros amarillos discontinuos), el origen del mundo y el
## punto elegido con el rumbo de despegue. Clic izquierdo: lanzar desde ahi. Ademas (no lo tiene la web): rueda para
## el zoom en el cursor y arrastrar con el boton derecho o el central para mover el mapa.

signal punto_elegido(N: float, E: float)
signal destacado_elegido(d: Dictionary)

var tex: Texture2D
var T: Dictionary              # terreno del mundo (N0, E0, nN, nE, paso)
var lugares := []
var carreteras := []
var zonas := []                # indice de zonas del mundo
var punto := {}                # { N, E, rumbo, destacado }
var destacados := []           # puntos de despegue resaltados (escenarios.js): { nombre, lat, lon, rumbo, contorno }
var a_ne: Callable             # (lat, lon) -> [N, E] (latLonANE)
var _xy := []                  # posicion en pantalla de cada destacado (para el clic)
var _esc := 0.0                # pixeles de pantalla por pixel de la imagen
var _org := Vector2.ZERO       # pixel de la imagen en la esquina superior izquierda
var _arrastre := false

func _ready() -> void:
	clip_contents = true; mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(_encajar)

func poner(textura: Texture2D, terreno: Dictionary, lugares_mundo: Array, indice_zonas: Array, carreteras_mundo := []) -> void:
	tex = textura; T = terreno; lugares = lugares_mundo; zonas = indice_zonas; carreteras = carreteras_mundo; _encajar()

func _encajar() -> void:
	if tex == null or size.x < 10: return
	_esc = minf(size.x / tex.get_width(), size.y / tex.get_height())
	_org = -(size / _esc - Vector2(tex.get_size())) / 2
	queue_redraw()

func _mpx() -> float:
	return (T["nE"] - 1) * T["paso"] / tex.get_width()

func a_pantalla(N: float, E: float) -> Vector2:
	var px := Vector2((E - T["E0"]) / _mpx(), tex.get_height() - 1 - (N - T["N0"]) / _mpx())
	return (px - _org) * _esc

func a_mundo(q: Vector2) -> Vector2:          # -> (N, E)
	var px := q / _esc + _org
	return Vector2(T["N0"] + (tex.get_height() - 1 - px.y) * _mpx(), T["E0"] + px.x * _mpx())

func _gui_input(ev: InputEvent) -> void:
	if tex == null: return
	if ev is InputEventMouseButton and ev.pressed:
		if ev.button_index == MOUSE_BUTTON_WHEEL_UP or ev.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			var f := 1.25 if ev.button_index == MOUSE_BUTTON_WHEEL_UP else 0.8
			var antes: Vector2 = ev.position / _esc + _org
			_esc = clampf(_esc * f, minf(size.x / tex.get_width(), size.y / tex.get_height()) * 0.8, 4.0)
			_org = antes - ev.position / _esc; queue_redraw(); accept_event()
		elif ev.button_index == MOUSE_BUTTON_LEFT:
			for k in _xy.size():          # clic en un destacado (su punto o su chincheta): se elige el destacado
				if ev.position.distance_to(_xy[k]) < 18 or ev.position.distance_to(_xy[k] - Vector2(0, 26)) < 14:
					destacado_elegido.emit(destacados[k]); accept_event(); return
			var ne := a_mundo(ev.position)
			if ne.x > T["N0"] and ne.x < T["N0"] + (T["nN"] - 1) * T["paso"] and ne.y > T["E0"] and ne.y < T["E0"] + (T["nE"] - 1) * T["paso"]:
				punto_elegido.emit(ne.x, ne.y)
			accept_event()
		elif ev.button_index == MOUSE_BUTTON_RIGHT or ev.button_index == MOUSE_BUTTON_MIDDLE:
			_arrastre = true
	elif ev is InputEventMouseButton and not ev.pressed and (ev.button_index == MOUSE_BUTTON_RIGHT or ev.button_index == MOUSE_BUTTON_MIDDLE):
		_arrastre = false
	elif ev is InputEventMouseMotion and _arrastre:
		_org -= ev.relative / _esc; queue_redraw()

func _txt(f: Font, q: Vector2, t: String, tam: int, c: Color) -> void:
	draw_string_outline(f, q, t, HORIZONTAL_ALIGNMENT_LEFT, -1, tam, 3, Color(0, 0, 0, 0.7))
	draw_string(f, q, t, HORIZONTAL_ALIGNMENT_LEFT, -1, tam, c)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("#0b0f14"))
	if tex == null: return
	draw_texture_rect(tex, Rect2(-_org * _esc, Vector2(tex.get_size()) * _esc), false)
	var f: Font = Tema.negrita if Tema.negrita else ThemeDB.fallback_font
	# carreteras: de las secundarias a las principales (colores y grosores de la web)
	var col := { 1: Color("#ffb74d"), 2: Color("#fff176"), 3: Color("#f5f5f5"), 4: Color("#cfd8dc") }
	var gro := { 1: 2.0, 2: 1.4, 3: 0.9, 4: 0.6 }
	for t in [4, 3, 2, 1]:
		for c in carreteras:
			if int(c[0]) != t: continue
			var pts := PackedVector2Array()
			for i in range(1, c.size(), 2): pts.append(a_pantalla(c[i + 1], c[i]))
			if pts.size() > 1: draw_polyline(pts, col[t], gro[t], true)
	for l in lugares:
		if l[1] > 4: continue
		var q := a_pantalla(l[3], l[2])
		draw_rect(Rect2(q - Vector2(2, 2), Vector2(4, 4)), Color.WHITE)
		_txt(f, q + Vector2(4, -3), l[0], 11, Color.WHITE)
	for z in zonas:
		var a := a_pantalla(z["N0"] + z["lado_m"], z["E0"]); var b := a_pantalla(z["N0"], z["E0"] + z["lado_m"])
		var r := Rect2(a, b - a); var am := Color("#ffd54f")
		for lado in [[r.position, Vector2(r.end.x, r.position.y)], [Vector2(r.end.x, r.position.y), r.end], [r.end, Vector2(r.position.x, r.end.y)], [Vector2(r.position.x, r.end.y), r.position]]:
			draw_dashed_line(lado[0], lado[1], am, 1.5, 4.0)
		_txt(f, a + Vector2(2, -3), "detalle", 10, am)
	# puntos destacados (CIFP...): contorno naranja, anillo, chincheta y rotulo (como pintarMapaLanz de la web)
	_xy = []
	var fb: Font = Tema.negrita if Tema.negrita else f
	for d in destacados:
		var dne: Array = a_ne.call(d["lat"], d["lon"]); var q := a_pantalla(dne[0], dne[1]); var sel: bool = punto.get("destacado", "") == d["nombre"]
		var naranja := Color("#ff8c00")
		if d.has("contorno"):
			var poli := PackedVector2Array()
			for ll in d["contorno"]:
				var c: Array = a_ne.call(ll[0], ll[1]); poli.append(a_pantalla(c[0], c[1]))
			if poli.size() >= 3 and Geometry2D.triangulate_polygon(poli).size() > 0: draw_colored_polygon(poli, Color(1, 0.55, 0, 0.35))
			poli.append(poli[0]); draw_polyline(poli, naranja, 2, true)
		draw_arc(q, 14, 0, TAU, 40, Color(1, 0.55, 0, 0.9), 3, true)
		var cab := q - Vector2(0, 26)
		draw_colored_polygon(PackedVector2Array([q, cab + Vector2(-8, 4), cab + Vector2(8, 4)]), naranja)
		draw_circle(cab, 9, naranja); draw_circle(cab, 3.5, Color.WHITE)
		var tw := fb.get_string_size(d["nombre"], HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		var caja := Rect2(q + Vector2(14, -46), Vector2(tw + 16, 24))
		draw_style_box(Tema.caja(naranja if sel else Color(8 / 255.0, 14 / 255.0, 22 / 255.0, 0.88), naranja, 6, 1, 0, 0), caja)
		draw_string(fb, q + Vector2(22, -29), d["nombre"], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("#111111") if sel else Color.WHITE)
		_xy.append(q)
	var o := a_pantalla(0, 0)                       # origen del mundo (el corazon)
	draw_circle(o, 4, Color("#ff5252")); _txt(Tema.fuente if Tema.fuente else f, o + Vector2(6, 4), "origen", 10, Color.WHITE)
	if not punto.is_empty():
		var q := a_pantalla(punto["N"], punto["E"]); var rr: float = punto.get("rumbo", 0.0) * PI / 180
		var am := Color("#ffd54f")
		draw_arc(q, 9, 0, TAU, 28, am, 2, true)
		draw_line(q, q + Vector2(sin(rr), -cos(rr)) * 26, am, 2, true)
		draw_circle(q, 3, am)
