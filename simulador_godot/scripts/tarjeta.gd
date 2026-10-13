class_name Tarjeta
extends PanelContainer
## Tarjeta pulsable que se ajusta a su contenido (.avCarta, .mision, .sitio, .alumno de la web): fondo blanco al 5 %,
## borde al 12 %; al pasar el raton, borde amarillo al 50 %; la elegida, fondo y borde amarillos.

signal pulsada

var elegida := false: set = _poner_elegida
var radio := 12
var relleno := Vector2(14, 12)
var _encima := false

func _init(contenido: Control = null, radio_ := 12, relleno_ := Vector2(14, 12)) -> void:
	radio = radio_; relleno = relleno_
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND; mouse_filter = Control.MOUSE_FILTER_STOP
	if contenido: add_child(contenido)
	mouse_entered.connect(func(): _encima = true; _estilo())
	mouse_exited.connect(func(): _encima = false; _estilo())
	_estilo()

func _ready() -> void:
	for c in _descendientes(self): if c is Control and not (c is BaseButton): (c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE

static func _descendientes(n: Node) -> Array:
	var r := []
	for c in n.get_children(): r.append(c); r.append_array(_descendientes(c))
	return r

func _poner_elegida(v: bool) -> void:
	elegida = v; _estilo()

func _estilo() -> void:
	var s: StyleBoxFlat
	if elegida: s = Tema.caja(Color(1, 0.78, 0.24, 0.12), Tema.ACENTO, radio, 2, relleno.x, relleno.y)
	elif _encima: s = Tema.caja(Color(1, 1, 1, 0.1), Color(1, 0.78, 0.24, 0.5), radio, 1, relleno.x, relleno.y)
	else: s = Tema.caja(Color(1, 1, 1, 0.05), Color(1, 1, 1, 0.12), radio, 1, relleno.x, relleno.y)
	add_theme_stylebox_override("panel", s)

func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed:
		accept_event(); pulsada.emit()
