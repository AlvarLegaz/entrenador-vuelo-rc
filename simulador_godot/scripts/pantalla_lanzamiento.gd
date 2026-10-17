class_name PantallaLanzamiento
extends Control
## ¿Desde donde sales? (#pLanzamiento de simulador_web/simulador.html): el mapa del mundo real para elegir el punto de
## lanzamiento (clic), con el texto del punto elegido abajo (#lanzInfo) y los botones Vuelo libre / Despegar aqui.

var p: Node
var d: Dictionary
var mapa: MapaLanzamiento
var info: RichTextLabel
var b_aqui: Button
var _puesto := false
var b_dest: HBoxContainer          # botones de los puntos destacados (#lanzDestacados)

func _init(p_: Node) -> void:
	p = p_; set_anchors_preset(Control.PRESET_FULL_RECT)
	d = Tema.pantalla("¿Desde dónde sales?", "Haz clic en el mapa para elegir el punto de lanzamiento. Se despega hacia el lado más despejado."); add_child(d["raiz"])
	b_dest = HBoxContainer.new(); b_dest.add_theme_constant_override("separation", 10); d["botones"].add_child(b_dest)
	d["botones"].add_child(Tema.boton("← Vuelo libre", "", func(): p.app_pantallas.ir_volar()))
	b_aqui = Tema.boton("Despegar aquí →", "BotonPrimGrande", func(): p.app_vuelo.empezar()); d["botones"].add_child(b_aqui)
	var caja := PanelContainer.new(); caja.add_theme_stylebox_override("panel", Tema.caja(Color("#0b0f14"), Tema.BORDE, Tema.RADIO, 1, 0, 0))
	caja.size_flags_vertical = Control.SIZE_EXPAND_FILL; caja.size_flags_horizontal = Control.SIZE_EXPAND_FILL; caja.custom_minimum_size.y = 300; caja.clip_contents = true
	d["cuerpo"].add_child(caja)
	var dentro := Control.new(); dentro.size_flags_vertical = Control.SIZE_EXPAND_FILL; dentro.size_flags_horizontal = Control.SIZE_EXPAND_FILL; caja.add_child(dentro)
	mapa = MapaLanzamiento.new(); mapa.set_anchors_preset(Control.PRESET_FULL_RECT); mapa.offset_left = 1; mapa.offset_top = 1; mapa.offset_right = -1; mapa.offset_bottom = -1; mapa.mouse_default_cursor_shape = Control.CURSOR_CROSS; dentro.add_child(mapa)
	mapa.punto_elegido.connect(func(N, E): p.app_evaluacion.elegir_punto(N, E); pintar())
	mapa.destacado_elegido.connect(func(dd): p.app_evaluacion.elegir_destacado(dd); pintar())
	var pi := PanelContainer.new(); pi.add_theme_stylebox_override("panel", Tema.caja(Color(8 / 255.0, 14 / 255.0, 22 / 255.0, 0.78), Color(0, 0, 0, 0), 10, 0, 12, 8))
	pi.anchor_left = 0; pi.anchor_right = 1; pi.anchor_top = 1; pi.anchor_bottom = 1; pi.offset_left = 14; pi.offset_right = -14; pi.offset_bottom = -12
	pi.grow_vertical = Control.GROW_DIRECTION_BEGIN; pi.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info = Tema.rico("", 13); info.fit_content = true; pi.add_child(info); dentro.add_child(pi)

## Pone el mapa del mundo (la primera vez) y pinta el punto elegido.
func preparar() -> void:
	if not _puesto:
		_puesto = true
		var M: Dictionary = p.mundo_datos
		mapa.poner(p.orto[1], p.ent.terreno, M["lugares"], p.indice_zonas, M.get("carreteras", []))
		mapa.a_ne = func(la: float, lo: float) -> Array: return p.app_evaluacion.lat_lon_a_ne(M, la, lo)
	mapa.destacados = p.app_evaluacion.destacados_lanz()
	for x in b_dest.get_children(): x.queue_free()
	for dd in mapa.destacados:
		var b := Tema.boton("📍 " + String(dd["nombre"]), "", func(): p.app_evaluacion.elegir_destacado(dd); pintar())
		b.tooltip_text = "Despegar desde " + String(dd["nombre"])
		for e in ["normal", "hover", "pressed", "focus"]:           # .btn.destacado de la web: borde naranja
			b.add_theme_stylebox_override(e, Tema.caja(Color(1, 1, 1, 0.12 if e == "hover" else 0.06), Color("#ff8c00"), 10, 1, 18, 9))
		for e in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]: b.add_theme_color_override(e, Color("#ffb74d"))
		b.add_theme_font_override("font", Tema.negrita)
		b_dest.add_child(b)
	pintar()

func pintar() -> void:
	var L: Dictionary = p.sesion["lanz"]; var M: Dictionary = p.mundo_datos; var T: Dictionary = p.ent.terreno
	mapa.punto = L; mapa.queue_redraw()
	var o: Dictionary = M["origen"]; var M_LAT := 110574.0; var M_LON := 111320.0 * cos(o["lat"] * PI / 180)
	var lat: float = o["lat"] + L["N"] / M_LAT; var lon: float = o["lon"] + L["E"] / M_LON
	var mar: bool = p.ent.en_mar(L["N"], L["E"]); var h_mar: float = p.ent.altura_mar(L["N"], L["E"])
	var ancho_m: float = (T["nE"] - 1) * T["paso"]
	var dsel := {}
	for dd in mapa.destacados:
		if L.get("destacado", "") == dd["nombre"]: dsel = dd
	if not dsel.is_empty():
		info.text = "[b][color=#ff8c00]%s[/color][/b] · %s · despegue con rumbo [b]%d°[/b]%s" % [dsel["nombre"], dsel.get("nota", ""), int(round(L["rumbo"])),
			"" if not DatosComunes.zona_en(p.indice_zonas, M["id"], L["N"], L["E"]).is_empty() else " · [b][color=#ff6e66]falta su zona de detalle en simulador/zonas[/color][/b]"]
	elif mar: info.text = "[b][color=#ff6e66]Eso es mar: elige un punto en tierra.[/color][/b]"
	else:
		var zona := DatosComunes.zona_en(p.indice_zonas, M["id"], L["N"], L["E"])
		info.text = ("Punto elegido: [b]%.5f N, %.5f O[/b] · %d m sobre el mar · a %.1f km del origen · despegue con rumbo [b]%d°[/b] (%s) · escala: %d km de ancho" % [
			lat, -lon, int(round(h_mar)), Vector2(L["N"], L["E"]).length() / 1000, int(round(L["rumbo"])),
			"punto de salida por defecto, hacia el este" if L.get("defecto", false) else "el más despejado", int(round(ancho_m / 1000))]) + \
			(" · [b][color=#ffd54f]dentro de una zona de detalle[/color][/b] (foto a 0,5 m, terreno a 5 m, edificios y árboles reales)" if not zona.is_empty()
			 else " · fuera de las zonas de detalle (recuadros amarillos): terreno a 150 m y foto a 12 m")
	b_aqui.disabled = mar
