class_name HudCarrera
extends Control
## Carrera de drones (hudCarrera de simulador_web/simulador.html): la barra de arriba (el mejor tiempo de la sala o de la
## sesion, el cronometro y el obstaculo que toca) y el indicador del siguiente obstaculo: un rombo con su numero y la
## distancia encima de el o, si no esta a la vista, una flecha en el borde de la pantalla hacia donde esta. p: la escena
## principal.

const VERDE := Color("#66bb6a")
var p: Node
var record: Label; var tiempo: Label; var peq: Label
var _sig := {}                     # lo que se dibuja del siguiente: { "pos", "flecha", "ang", "txt" }

static func _sombra(l: Label) -> void:
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9)); l.add_theme_constant_override("shadow_outline_size", 6)
	l.add_theme_constant_override("shadow_offset_x", 0); l.add_theme_constant_override("shadow_offset_y", 2)

func _init(p_: Node) -> void:
	p = p_; set_anchors_preset(Control.PRESET_FULL_RECT); mouse_filter = Control.MOUSE_FILTER_IGNORE
	var caja := VBoxContainer.new(); caja.mouse_filter = Control.MOUSE_FILTER_IGNORE; caja.alignment = BoxContainer.ALIGNMENT_BEGIN
	caja.anchor_left = 0.5; caja.anchor_right = 0.5; caja.anchor_top = 0.26; caja.anchor_bottom = 0.26; caja.grow_horizontal = Control.GROW_DIRECTION_BOTH   # bajo los avisos (20 %)
	caja.add_theme_constant_override("separation", 2); add_child(caja)
	var pc := PanelContainer.new(); pc.mouse_filter = Control.MOUSE_FILTER_IGNORE; pc.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	pc.add_theme_stylebox_override("panel", Tema.caja(Color(0, 0, 0, 0.55), Color("#ffd54f99"), 16, 1, 12, 3)); caja.add_child(pc)
	record = Tema.etiqueta("", 13, Color("#ffd54f"), true); pc.add_child(record)
	var h := HBoxContainer.new(); h.mouse_filter = Control.MOUSE_FILTER_IGNORE; h.alignment = BoxContainer.ALIGNMENT_CENTER; h.add_theme_constant_override("separation", 8); caja.add_child(h)
	tiempo = Tema.etiqueta("", 30, Color.WHITE, true); _sombra(tiempo); h.add_child(tiempo)
	peq = Tema.etiqueta("", 16, Color("#cfe8ff"), true); _sombra(peq); h.add_child(peq)

## Cada cuadro (hudCarrera): oculta todo fuera de la carrera.
func pintar() -> void:
	var op = p.ev.op if p.ev != null else null
	if op == null or op.carr == null: visible = false; return
	visible = true; var C: Dictionary = op.carr; var n: int = op.obst.size()
	var nom := func(id: String) -> String: return String(DatosComunes.avion(id).get("nombre", id)) if p.ids_aviones.has(id) else id
	if not p.sala.is_empty():
		var R = p.sala.get("record")
		record.text = ("🏆 Mejor de la sala: %s · %s (%s)" % [String(R["nombre"]).left(30), Operacion.crono(R["t"]), nom.call(String(R["avion"]))]) if R is Dictionary else "🏆 Sala: nadie ha terminado todavía"
	else:
		record.text = ("🏆 Tu mejor de la sesión: %s (%s)" % [Operacion.crono(p.carrera_mejor["t"]), nom.call(String(p.carrera_mejor["avion"]))]) if p.carrera_mejor != null else "🏆 Sin tiempo todavía en esta sesión"
	var t: float = (C["tFin"] - C["t0"]) if C["tFin"] != null else ((p.av["t"] - C["t0"]) if C["t0"] != null else 0.0)
	if C["fuera"] != null:
		tiempo.text = "DESCALIFICADO"; peq.text = "te saltaste el %d" % (C["fuera"] + 1); tiempo.add_theme_color_override("font_color", Color("#ff8a80"))
	else:
		tiempo.text = Operacion.crono(t); peq.text = "¡META!" if C["tFin"] != null else "%d/%d" % [C["k"] + 1, n]; tiempo.add_theme_color_override("font_color", Color.WHITE)
	if p.mundo3d != null: p.mundo3d.resaltar_carrera(-1 if (C["fuera"] != null or C["tFin"] != null) else C["k"])
	# el indicador
	_sig = {}
	var s: Dictionary = op.siguiente(p.av)
	if not s.is_empty() and p.av["estado"] != "roto" and p.cam != null:
		var o: Dictionary = s["o"]; var yc: float = o["y0"] if o["tipo"] == "picado" else o["y0"] + o["alto"] / 2.0
		var w := Vector3(o["e"], yc, -o["n"]); var cam: Camera3D = p.cam
		var detras := cam.is_position_behind(w); var q := cam.unproject_position(w); var W := size.x; var H := size.y; var m := 46.0
		var d: float = s["d"]
		var txt := "%d · %s" % [s["i"] + 1, ("%d m" % int(round(d))) if d < 1000 else ("%s km" % ("%.1f" % (d / 1000)).replace(".", ","))]
		if not detras and q.x > m and q.x < W - m and q.y > m and q.y < H - m:
			_sig = { "pos": q, "flecha": false, "txt": txt }
		else:
			var dx := q.x - W / 2; var dy := q.y - H / 2
			if detras: dx = -dx; dy = -dy
			if Vector2(dx, dy).length() < 1: dy = 1
			var mv := H * 0.26 + 80 if dy < 0 else m                          # arriba, por debajo de la barra
			var k := minf((W / 2 - m) / maxf(absf(dx), 1e-9), (H / 2 - mv) / maxf(absf(dy), 1e-9))
			_sig = { "pos": Vector2(W / 2 + dx * k, H / 2 + dy * k), "flecha": true, "ang": atan2(dy, dx), "txt": txt }
	queue_redraw()

func _draw() -> void:
	if _sig.is_empty(): return
	var f: Font = Tema.negrita; var q: Vector2 = _sig["pos"]
	var texto := func(pos: Vector2) -> void:
		var ancho := f.get_string_size(_sig["txt"], HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		draw_string_outline(f, pos - Vector2(ancho / 2, 0), _sig["txt"], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, 3, Color(0, 0, 0, 0.75))
		draw_string(f, pos - Vector2(ancho / 2, 0), _sig["txt"], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.WHITE)
	if not _sig["flecha"]:                                             # a la vista: un rombo encima
		var r := PackedVector2Array([q + Vector2(0, -18), q + Vector2(18, 0), q + Vector2(0, 18), q + Vector2(-18, 0)])
		draw_colored_polygon(r, Color(0.4, 0.73, 0.42, 0.25)); r.append(r[0]); draw_polyline(r, VERDE, 3)
		texto.call(q + Vector2(0, -26))
		return
	var a: float = _sig["ang"]; var rot := Transform2D(a, q)                   # fuera de la vista: una flecha en el borde
	var pts := PackedVector2Array([rot * Vector2(22, 0), rot * Vector2(-10, -16), rot * Vector2(-4, 0), rot * Vector2(-10, 16)])
	draw_colored_polygon(pts, VERDE); pts.append(pts[0]); draw_polyline(pts, Color(0, 0, 0, 0.75), 2)
	texto.call(q - Vector2(cos(a), sin(a)) * 34 + Vector2(0, 5))
