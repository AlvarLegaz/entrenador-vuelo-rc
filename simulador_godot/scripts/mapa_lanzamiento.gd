class_name MapaLanzamiento
extends Control
## Mapa para elegir el punto de lanzamiento, como en el navegador: la ortofoto de la region, las zonas de detalle
## (recuadros) y los pueblos. Clic izquierdo: lanzar desde ahi. Rueda: zoom en el cursor. Arrastrar con el boton
## derecho o el central: mover el mapa.

signal punto_elegido(N: float, E: float)

var tex: Texture2D
var T: Dictionary              # terreno del mundo (N0, E0, nN, nE, paso)
var lugares := []
var zonas := []                # indice de zonas del mundo
var punto := {}                # { N, E, rumbo }
var _esc := 0.0                # pixeles de pantalla por pixel de la imagen
var _org := Vector2.ZERO       # pixel de la imagen en la esquina superior izquierda
var _arrastre := false

func _ready() -> void:
	clip_contents = true; mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(_encajar)

func poner(textura: Texture2D, terreno: Dictionary, lugares_mundo: Array, indice_zonas: Array) -> void:
	tex = textura; T = terreno; lugares = lugares_mundo; zonas = indice_zonas; _encajar()

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

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.07, 0.1))
	if tex == null: return
	draw_texture_rect(tex, Rect2(-_org * _esc, Vector2(tex.get_size()) * _esc), false)
	var f := ThemeDB.fallback_font
	for l in lugares:
		if l[1] > (3 if _esc > 0.4 else 2): continue
		var q := a_pantalla(l[3], l[2])
		draw_rect(Rect2(q - Vector2(2, 2), Vector2(4, 4)), Color.WHITE)
		draw_string_outline(f, q + Vector2(5, -4), l[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 4, Color(0, 0, 0, 0.8))
		draw_string(f, q + Vector2(5, -4), l[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)
	for z in zonas:
		var a := a_pantalla(z["N0"] + z["lado_m"], z["E0"]); var b := a_pantalla(z["N0"], z["E0"] + z["lado_m"])
		draw_rect(Rect2(a, b - a), Color(0.31, 0.76, 0.97, 0.18)); draw_rect(Rect2(a, b - a), Color(0.31, 0.76, 0.97), false, 2)
		draw_string_outline(f, a + Vector2(3, -5), "zona de detalle: " + str(z["id"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 4, Color(0, 0, 0, 0.8))
		draw_string(f, a + Vector2(3, -5), "zona de detalle: " + str(z["id"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.6, 0.88, 1))
	if not punto.is_empty():
		var q := a_pantalla(punto["N"], punto["E"]); var r: float = punto.get("rumbo", 0.0) * PI / 180
		var u := Vector2(sin(r), -cos(r))
		draw_line(q, q + u * 26, Color(1, 0.84, 0.31), 3, true)
		draw_circle(q, 7, Color(0.9, 0.2, 0.2)); draw_arc(q, 7, 0, TAU, 20, Color.WHITE, 2, true)
	draw_string_outline(f, Vector2(10, size.y - 12), "Clic: punto de lanzamiento · rueda: zoom · botón derecho: mover", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 4, Color(0, 0, 0, 0.8))
	draw_string(f, Vector2(10, size.y - 12), "Clic: punto de lanzamiento · rueda: zoom · botón derecho: mover", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)
