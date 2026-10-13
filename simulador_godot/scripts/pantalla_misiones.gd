class_name PantallaMisiones
extends RefCounted
## Entrenamientos (#pEntrenamientos) y vuelo libre (#pVolar) de simulador/simulador.html, con el panel de condiciones
## (#condiciones) que comparten, y los iconos de las misiones (iconoMision, los mismos SVG).

## Icono esquematico de cada mision (SVG de 200 x 110), igual que iconoMision de la web.
static func icono(id: String) -> String:
	var avion := func(x: float, y: float, a: float, c := "#fff") -> String:
		return '<g transform="translate(%s %s) rotate(%s)"><path d="M-9 0H9M-2 -7V7M6 -3V3" stroke="%s" stroke-width="2.6" stroke-linecap="round" fill="none"/></g>' % [x, y, a, c]
	var pil := func(x: float, y: float, c: String) -> String: return '<circle cx="%s" cy="%s" r="5" fill="%s" stroke="#000" stroke-width="1"/>' % [x, y, c]
	var P := ["#4caf50", "#ffeb3b", "#f44336", "#42a5f5"]; var tr := "#ffc83d"
	var pista := func(x: float, y: float, w: float, h: float) -> String: return '<rect x="%s" y="%s" width="%s" height="%s" fill="#8a8a8a" rx="2"/>' % [x, y, w, h]
	var flecha := func(x: float, y: float, a: float) -> String: return '<g transform="translate(%s %s) rotate(%s)"><path d="M-5 -4L2 0-5 4z" fill="%s"/></g>' % [x, y, a, tr]
	var ini := '<svg viewBox="0 0 200 110" width="200" height="110" xmlns="http://www.w3.org/2000/svg">'; var fin := "</svg>"
	match id:
		"primer_vuelo": return ini + pista.call(96, 70, 8, 30) + '<path d="M60 35 Q100 10 140 35 Q165 55 140 80 Q100 100 60 80 Q35 55 60 35z" fill="none" stroke="%s" stroke-width="2" stroke-dasharray="6 4"/>' % tr + \
			pil.call(60, 35, P[0]) + pil.call(140, 35, P[1]) + pil.call(140, 80, P[2]) + pil.call(60, 80, P[3]) + flecha.call(100, 21, 0) + avion.call(100, 55, -10) + fin
		"orientacion": return ini + '<path d="M100 55 C70 20 25 25 25 55 C25 85 70 90 100 55 C130 20 175 25 175 55 C175 85 130 90 100 55" fill="none" stroke="%s" stroke-width="2.5"/>' % tr + \
			pil.call(140, 35, P[2]) + pil.call(140, 75, P[3]) + pil.call(60, 35, P[1]) + pil.call(60, 75, P[0]) + flecha.call(173, 45, -80) + flecha.call(27, 65, 100) + avion.call(100, 55, 30) + fin
		"viento_cruzado": return ini + pista.call(92, 15, 16, 80) + '<g stroke="#4fc3f7" stroke-width="2.5" stroke-linecap="round" fill="none"><path d="M20 35h30M20 55h40M20 75h30"/><path d="M44 29l6 6-6 6M54 49l6 6-6 6M44 69l6 6-6 6"/></g>' + \
			avion.call(140, 55, -70) + '<path d="M140 80 L140 100" stroke="%s" stroke-width="2" stroke-dasharray="4 3"/>' % tr + fin
		"emergencia": return ini + '<path d="M40 25 C80 30 120 55 170 90" fill="none" stroke="%s" stroke-width="2" stroke-dasharray="6 4"/><path d="M10 92h180" stroke="#6b4a1e" stroke-width="3"/>' % tr + \
			avion.call(40, 25, 20) + '<g stroke="#ff5252" stroke-width="3" stroke-linecap="round"><path d="M58 12l10 10M68 12l-10 10"/></g>' + fin
		"puerta": return ini + '<rect x="70" y="20" width="6" height="70" fill="#ff8f00"/><rect x="124" y="20" width="6" height="70" fill="#ff8f00"/>' + \
			'<path d="M20 60 H180" stroke="%s" stroke-width="2" stroke-dasharray="6 4"/>' % tr + flecha.call(170, 60, 0) + flecha.call(30, 72, 180) + avion.call(100, 60, 0) + fin
		"pasada_baja": return ini + '<rect x="20" y="78" width="160" height="12" fill="#8d6e63" rx="2"/><path d="M15 60 H185" stroke="%s" stroke-width="2" stroke-dasharray="6 4"/>' % tr + \
			'<path d="M30 48 H60" stroke="#fff" stroke-width="1" stroke-dasharray="2 2"/><text x="64" y="51" fill="#fff" font-size="9">2–8 m</text>' + avion.call(100, 60, 0) + flecha.call(175, 60, 0) + fin
		"diana": return ini + '<g fill="none" stroke="#e0e0e0" stroke-width="1.5"><circle cx="100" cy="68" r="34"/><circle cx="100" cy="68" r="22"/><circle cx="100" cy="68" r="10"/></g><circle cx="100" cy="68" r="3" fill="#ff5252"/>' + \
			'<path d="M30 15 Q70 30 96 62" fill="none" stroke="%s" stroke-width="2" stroke-dasharray="6 4"/>' % tr + avion.call(36, 18, 35) + fin
		"recorrido": return ini + '<rect x="10" y="80" width="60" height="9" fill="#8d6e63" rx="2"/><rect x="92" y="30" width="4" height="40" fill="#ff8f00"/><rect x="118" y="30" width="4" height="40" fill="#ff8f00"/>' + \
			'<g fill="none" stroke="#e0e0e0" stroke-width="1.5"><circle cx="165" cy="80" r="18"/><circle cx="165" cy="80" r="8"/></g>' + \
			'<path d="M15 70 H70 Q90 60 105 50 L130 50 Q150 55 162 76" fill="none" stroke="%s" stroke-width="2" stroke-dasharray="6 4"/>' % tr + \
			'<g fill="%s" font-size="12" font-weight="700"><text x="36" y="72">1</text><text x="102" y="24">2</text><text x="148" y="106">3</text></g>' % tr + fin
		"aterrizaje": return ini + pista.call(28, 20, 12, 70) + '<path d="M34 25 C34 10 170 10 170 25 L170 85 C170 100 34 100 34 90" fill="none" stroke="%s" stroke-width="2" stroke-dasharray="6 4"/>' % tr + \
			flecha.call(102, 15, 0) + flecha.call(170, 55, 90) + flecha.call(102, 95, 180) + avion.call(34, 60, -90) + '<text x="46" y="60" fill="#fff" font-size="9">final</text>' + fin
		"campo": return ini + pista.call(96, 25, 8, 55) + pil.call(70, 30, P[0]) + pil.call(130, 30, P[1]) + pil.call(130, 75, P[2]) + pil.call(70, 75, P[3]) + \
			'<circle cx="100" cy="95" r="4" fill="#fff"/><text x="108" y="98" fill="#fff" font-size="9">piloto</text>' + avion.call(150, 50, -30) + fin
	return ini + avion.call(100, 55, 0) + fin

## Imagen de una tarjeta: fondo degradado azul (#1d3a56 -> #0f2235) con el icono encima.
static func imagen(id: String, alto: float) -> Control:
	var c := Control.new(); c.custom_minimum_size.y = alto; c.clip_contents = true
	var g := Gradient.new(); g.colors = PackedColorArray([Color("#1d3a56"), Color("#0f2235")]); g.offsets = PackedFloat32Array([0, 1])
	var gt := GradientTexture2D.new(); gt.gradient = g; gt.fill_from = Vector2(0.5, 0); gt.fill_to = Vector2(0.5, 1)
	var f := TextureRect.new(); f.texture = gt; f.set_anchors_preset(Control.PRESET_FULL_RECT); f.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; f.stretch_mode = TextureRect.STRETCH_SCALE
	c.add_child(f)
	var ic := TextureRect.new(); ic.texture = Tema.svg(icono(id), 2.0); ic.set_anchors_preset(Control.PRESET_FULL_RECT)
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED; c.add_child(ic)
	# el lector de SVG de Godot no dibuja <text>: los textos ("piloto", "final", "2–8 m", 1 2 3) se pintan encima, con la
	# misma escala y centrado que el dibujo (viewBox 0 0 200 110)
	var textos := textos_svg(icono(id))
	if not textos.is_empty():
		var tx := Control.new(); tx.set_anchors_preset(Control.PRESET_FULL_RECT); tx.mouse_filter = Control.MOUSE_FILTER_IGNORE; c.add_child(tx)
		tx.draw.connect(func():
			var k := minf(tx.size.x / 200.0, tx.size.y / 110.0); var o := (tx.size - Vector2(200, 110) * k) / 2
			for t in textos:
				tx.draw_string(Tema.negrita if t["negrita"] else Tema.fuente, o + t["pos"] * k, t["texto"], HORIZONTAL_ALIGNMENT_LEFT, -1, int(round(t["tam"] * k)), t["color"]))
	return c

## Textos de un SVG: [{ pos (x, y de la linea base), texto, tam, color, negrita }], con lo que heredan de su <g>.
static func textos_svg(svg: String) -> Array:
	var re := RegEx.new(); re.compile("<g ([^>]*)>|</g>|<text ([^>]*)>([^<]*)</text>")
	var at := RegEx.new(); at.compile("([a-z-]+)=\"([^\"]*)\"")
	var pila := [{}]; var out := []
	for m in re.search_all(svg):
		var s := m.get_string()
		if s.begins_with("</g"): pila.pop_back(); continue
		var d: Dictionary = (pila[-1] as Dictionary).duplicate()
		for a in at.search_all(m.get_string(1) if s.begins_with("<g") else m.get_string(2)): d[a.get_string(1)] = a.get_string(2)
		if s.begins_with("<g"): pila.append(d); continue
		out.append({ "pos": Vector2(float(d.get("x", "0")), float(d.get("y", "0"))), "texto": m.get_string(3), "tam": float(d.get("font-size", "10")),
					 "color": Color(d.get("fill", "#ffffff")), "negrita": d.get("font-weight", "") == "700" })
	return out


## Panel de condiciones (viento): velocidad, de donde viene y rachas. Uno solo, que se mueve a la pantalla que lo usa.
class Condiciones extends PanelContainer:
	var p: Node
	var s_vel: HSlider; var t_vel: Label; var o_dir: OptionButton; var c_rachas: CheckBox; var nota: Label
	const DIRS := [0, 45, 90, 135, 180, 225, 270, 315]
	func _init(p_: Node) -> void:
		p = p_; theme_type_variation = "Capa"
		var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 8); add_child(v)
		v.add_child(Tema.h2("Condiciones"))
		s_vel = Tema.deslizador(0, 10, 0.5, 2); t_vel = Tema.etiqueta("2 m/s", 14, Tema.TEXTO, true)
		var f := HBoxContainer.new(); f.add_theme_constant_override("separation", 10); f.size_flags_horizontal = Control.SIZE_EXPAND_FILL; f.add_child(s_vel); f.add_child(t_vel)
		v.add_child(Tema.fila("Viento", f, 110))
		o_dir = Tema.desplegable(["norte (de cara al piloto)", "nordeste", "este (cruzado)", "sudeste", "sur (de cola en la pista)", "sudoeste", "oeste (cruzado)", "noroeste"])
		v.add_child(Tema.fila("Viene del", o_dir, 110))
		c_rachas = Tema.casilla("y turbulencia", true); v.add_child(Tema.fila("Rachas", c_rachas, 110))
		nota = Tema.sub("", 13); v.add_child(nota)
		s_vel.value_changed.connect(func(_x): leer()); o_dir.item_selected.connect(func(_i): leer()); c_rachas.toggled.connect(func(_b): leer())
	var _montando := false
	func montar(E) -> void:
		_montando = true
		var fijo: bool = E != null and (E as Dictionary).has("viento")
		var vv: Dictionary = E["viento"] if fijo else p.sesion["viento"]
		s_vel.value = vv["vel"]; o_dir.selected = maxi(0, DIRS.find(int(vv["desde"]))); c_rachas.button_pressed = vv["rachas"]
		t_vel.text = _vel(vv["vel"])
		s_vel.editable = not fijo; o_dir.disabled = fijo; c_rachas.disabled = fijo
		nota.text = "Este entrenamiento fija su propio viento." if fijo else ("Para empezar, menos de 3 m/s. Física %s (se cambia en Ajustes)." % ("fácil" if p.sesion["dificultad"] == "facil" else "real"))
		_montando = false
	static func _vel(x: float) -> String: return (str(int(x)) if x == int(x) else ("%.1f" % x)) + " m/s"
	func leer() -> void:
		if _montando or not s_vel.editable: return
		p.sesion["viento"] = { "vel": s_vel.value, "desde": DIRS[o_dir.selected], "rachas": c_rachas.button_pressed }
		t_vel.text = _vel(s_vel.value); p.guardar_sesion()
	func mover_a(destino: Control) -> void:
		if get_parent() != destino:
			if get_parent(): get_parent().remove_child(self)
			destino.add_child(self); destino.move_child(self, 0)


## Entrenamientos: tarjetas por grupo a la izquierda; ficha, condiciones y Volar a la derecha.
class Entrenamientos extends Control:
	var p: Node; var d: Dictionary
	var lista: VBoxContainer; var ficha_rt: RichTextLabel; var hueco: VBoxContainer
	var sel := "primer_vuelo"
	func _init(p_: Node) -> void:
		p = p_; set_anchors_preset(Control.PRESET_FULL_RECT)
		d = Tema.pantalla("Entrenamientos", " "); add_child(d["raiz"])
		d["botones"].add_child(Tema.boton("← Inicio", "", func(): p.ir_inicio()))
		var dos := HBoxContainer.new(); dos.add_theme_constant_override("separation", 16); d["cuerpo"].add_child(dos)
		lista = VBoxContainer.new(); lista.add_theme_constant_override("separation", 10)
		var sc := Tema.desplazable(lista); dos.add_child(sc)
		var der := VBoxContainer.new(); der.custom_minimum_size.x = 380; der.add_theme_constant_override("separation", 12)
		var sd := Tema.desplazable(der); sd.size_flags_horizontal = Control.SIZE_FILL; dos.add_child(sd)       # .dos: 1fr 380px
		var cf := Tema.capa(6); der.add_child(cf[0])
		ficha_rt = Tema.rico("", 14); (cf[1] as VBoxContainer).add_child(ficha_rt)
		hueco = VBoxContainer.new(); der.add_child(hueco)
		var bv := Tema.boton("Volar →", "BotonPrimGrande", func(): p.sesion["escenario"] = sel; p.guardar_sesion(); p.empezar())
		bv.size_flags_horizontal = Control.SIZE_FILL; der.add_child(bv)
	func refrescar() -> void:
		var E := Escenarios.datos(); var al = p.sesion["alumno"]
		var g = al["progreso"] if al != null and al.has("progreso") else null
		d["subtitulo"].text = String(DatosComunes.avion(p.sesion["avion"]).get("nombre", "")) + ((" · %d/4 escenarios superados" % int(g["escenarios_superados"])) if g != null else " · sin registro")
		if not E.has(sel) or Escenarios.libre(sel): sel = "primer_vuelo"
		for x in lista.get_children(): x.queue_free()
		var rejilla: GridAdaptable = null
		for id in E:
			var M: Dictionary = E[id]
			if (M["objetivos"] as Array).is_empty(): continue
			if M.has("titulo_grupo") or rejilla == null:
				if M.has("titulo_grupo"):
					var t := Tema.etiqueta(String(M["titulo_grupo"]).to_upper(), 13, Tema.SUAVE, true)
					var fv := FontVariation.new(); fv.base_font = Tema.negrita; fv.spacing_glyph = 1; t.add_theme_font_override("font", fv)
					lista.add_child(Tema.margen(t, 0, 10 if lista.get_child_count() else 0, 0, 2))
				rejilla = Tema.rejilla(230, 12); lista.add_child(rejilla)
			var st = g["escenarios"].get(id) if g != null else null
			rejilla.add_child(_tarjeta(id, M, st))
		var M: Dictionary = E[sel]
		var bb := "[font_size=20][b]%s[/b][/font_size]\n[color=#9fb3c8]%s[/color]\n" % [M["nombre"], M["desc"]]
		if M.has("sentido"): bb += "Orden de los pilones: %s\n" % Escenarios.orden_bb(p.ent_campo(), int(M["sentido"]))
		bb += "\n[font_size=12][color=#9fb3c8][b]OBJETIVOS[/b][/color][/font_size]\n"
		for o in M["objetivos"]: bb += "  •  %s\n" % o[1]
		ficha_rt.text = bb
		p.condiciones.mover_a(hueco); p.condiciones.montar(M)
	func _tarjeta(id: String, M: Dictionary, st) -> Tarjeta:
		var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 0)
		v.add_child(PantallaMisiones.imagen(id, 110))
		var tx := VBoxContainer.new(); tx.add_theme_constant_override("separation", 4)
		var h := HBoxContainer.new(); h.add_theme_constant_override("separation", 6)
		h.add_child(Tema.etiqueta(String(M["nombre"]).substr(4) if String(M["nombre"]).substr(1, 3) == " · " else String(M["nombre"]), 15, Tema.TEXTO, true))
		if st != null and st["superado"]: h.add_child(Tema.etiqueta("✓", 15, Tema.OK, true))
		tx.add_child(h)
		var dsc := Tema.etiqueta(String(M["desc"]), 12, Tema.SUAVE, false, true); dsc.max_lines_visible = 2; dsc.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		tx.add_child(dsc)
		var dif := int(M.get("dificultad", 1))
		var meta := "[color=#ffc83d]%s%s[/color]" % ["★".repeat(dif), "☆".repeat(3 - dif)]
		if st != null and int(st["intentos"]) > 0: meta += "[color=#9fb3c8] · %d intento%s[/color]" % [int(st["intentos"]), "s" if int(st["intentos"]) > 1 else ""]
		tx.add_child(Tema.rico(meta, 12))
		v.add_child(Tema.margen(tx, 12, 10, 12, 12))
		var t := Tarjeta.new(v, 14, Vector2(0, 0)); t.elegida = id == sel
		t.pulsada.connect(func(): sel = id; refrescar())
		return t


## Vuelo libre: los dos sitios (campo del club y Campo de Cartagena), la nota, condiciones y Volar.
class Volar extends Control:
	var p: Node; var d: Dictionary
	var t_campo: Tarjeta; var t_cartagena: Tarjeta; var nota: Label; var hueco: VBoxContainer; var b_volar: Button
	func _init(p_: Node) -> void:
		p = p_; set_anchors_preset(Control.PRESET_FULL_RECT)
		d = Tema.pantalla("Vuelo libre", "Sin objetivos: cuenta como horas de entrenamiento."); add_child(d["raiz"])
		d["botones"].add_child(Tema.boton("← Inicio", "", func(): p.ir_inicio()))
		var dos := HBoxContainer.new(); dos.add_theme_constant_override("separation", 16); d["cuerpo"].add_child(dos)
		var izq := VBoxContainer.new(); izq.size_flags_horizontal = Control.SIZE_EXPAND_FILL; izq.add_theme_constant_override("separation", 14); dos.add_child(izq)
		var sitios := HBoxContainer.new(); sitios.add_theme_constant_override("separation", 12); izq.add_child(sitios)
		t_campo = _sitio(PantallaMisiones.imagen("campo", 160), "Campo de vuelo", "El campo del club: pista, circuito de pilones, zona de precisión detrás del piloto y límite de alcance de 400 m. Se cronometra cada vuelta.")
		var foto := TextureRect.new(); foto.custom_minimum_size.y = 160; foto.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; foto.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED; foto.clip_contents = true
		if p.orto.size() > 1: foto.texture = p.orto[1]
		t_cartagena = _sitio(foto, "Campo de Cartagena · mapa real", "78 × 38 km reales: Cartagena, el Mar Menor, La Manga, la sierra y los pueblos. Eliges el punto de lanzamiento en el mapa. Sin límite de alcance.")
		for t in [t_campo, t_cartagena]: t.size_flags_horizontal = Control.SIZE_EXPAND_FILL; sitios.add_child(t)
		t_campo.pulsada.connect(func(): p.sitio_sel = "libre"; refrescar()); t_cartagena.pulsada.connect(func(): p.sitio_sel = "libre_cartagena"; refrescar())
		nota = Tema.sub("", 13); izq.add_child(nota)
		var der := VBoxContainer.new(); der.custom_minimum_size.x = 380; der.add_theme_constant_override("separation", 12); dos.add_child(der)
		hueco = VBoxContainer.new(); der.add_child(hueco)
		b_volar = Tema.boton("Volar →", "BotonPrimGrande", func():
			p.sesion["escenario"] = p.sitio_sel; p.guardar_sesion()
			if p.sitio_sel == "libre_cartagena": p.ir_lanzamiento()
			else: p.empezar())
		der.add_child(b_volar)
	func _sitio(img: Control, titulo: String, texto: String) -> Tarjeta:
		var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 0)
		var marco := Control.new(); marco.custom_minimum_size.y = 160; marco.clip_contents = true; img.set_anchors_preset(Control.PRESET_FULL_RECT); marco.add_child(img); v.add_child(marco)
		var tx := VBoxContainer.new(); tx.add_theme_constant_override("separation", 4)
		tx.add_child(Tema.etiqueta(titulo, 17, Tema.TEXTO, true)); tx.add_child(Tema.etiqueta(texto, 13, Tema.SUAVE, false, true))
		v.add_child(Tema.margen(tx, 14, 12, 14, 12))
		return Tarjeta.new(v, 14, Vector2(0, 0))
	func refrescar() -> void:
		t_campo.elegida = p.sitio_sel == "libre"; t_cartagena.elegida = p.sitio_sel == "libre_cartagena"
		nota.text = "Lanzas desde el aparcamiento, de cara al norte; la pista va hacia delante. En vuelo, + y − cambian el viento y G las rachas." if p.sitio_sel == "libre" \
			else "El siguiente paso es el mapa: eliges dónde lanzar y se despega hacia el lado más despejado. En la zona de detalle hay ortofoto a 0,5 m, edificios y árboles reales."
		b_volar.text = "Volar →" if p.sitio_sel == "libre" else "Elegir el punto de lanzamiento →"
		p.condiciones.mover_a(hueco); p.condiciones.montar(null)
