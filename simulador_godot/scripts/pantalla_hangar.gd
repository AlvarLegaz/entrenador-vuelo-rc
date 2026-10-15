class_name PantallaHangar
extends Control
## Hangar (#pHangar de simulador/simulador.html): lista de aviones, el elegido girando con su nombre, y la ficha con dos
## pestanas: Ficha (caracteristicas) y Ajustes del avion (centro de gravedad y peso, recorridos de la emisora y
## lanzamiento, calibracion con el avion real y aire), en secciones plegables como los <details> de la web.

var p: Node
var d: Dictionary
var lista: VBoxContainer
var previa: VistaPrevia
var nombre: Label
var desc: Label
var pest_ficha: Button; var pest_ajustes: Button
var panel_ficha: VBoxContainer; var panel_ajustes: VBoxContainer
var tabla: VBoxContainer
var sec_cm: VBoxContainer
var s_cg: HSlider; var s_masa: HSlider
var t_cg: Label; var t_masa: Label; var t_efecto: Label; var t_bateria: Label
var s_dr_al: HSlider; var s_dr_prof: HSlider; var t_dr_al: Label; var t_dr_prof: Label; var c_lanz: CheckBox
var e_empuje: LineEdit; var s_res: HSlider; var s_temp: HSlider; var t_res: Label; var t_temp: Label; var t_cal: Label
var b_progreso: Button
var _pintando := false

func _init(p_: Node) -> void:
	p = p_; set_anchors_preset(Control.PRESET_FULL_RECT)
	d = Tema.pantalla("Hangar", "Elige el avión y, si quieres, ajústalo como el tuyo."); add_child(d["raiz"])
	b_progreso = Tema.boton("Mi progreso", "", func(): p.ir_progreso("pHangar")); d["botones"].add_child(b_progreso)
	d["botones"].add_child(Tema.boton("← Inicio", "", func(): p.ir_inicio()))
	d["botones"].add_child(Tema.boton("Volar con este avión →", "BotonPrim", func(): p.ir_inicio()))   # el vehiculo queda elegido: en el inicio se elige que volar
	var g := HBoxContainer.new(); g.add_theme_constant_override("separation", 16); d["cuerpo"].add_child(g)
	# lista de aviones
	lista = VBoxContainer.new(); lista.add_theme_constant_override("separation", 8)
	var sl := Tema.desplazable(lista); sl.custom_minimum_size.x = 220; sl.size_flags_horizontal = Control.SIZE_FILL; g.add_child(sl)
	# vista del avion
	var pv := Panel.new(); pv.size_flags_horizontal = Control.SIZE_EXPAND_FILL; pv.custom_minimum_size.y = 360; pv.clip_contents = true
	pv.add_theme_stylebox_override("panel", Tema.caja(Color("#142434"), Tema.BORDE, Tema.RADIO))
	var rad := TextureRect.new(); rad.set_anchors_preset(Control.PRESET_FULL_RECT); rad.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; rad.stretch_mode = TextureRect.STRETCH_SCALE
	var gr := Gradient.new(); gr.offsets = PackedFloat32Array([0, 0.6, 1]); gr.colors = PackedColorArray([Color("#35546f"), Color("#142434"), Color("#0b1521")])
	var gt := GradientTexture2D.new(); gt.gradient = gr; gt.fill = GradientTexture2D.FILL_RADIAL; gt.fill_from = Vector2(0.5, 0.7); gt.fill_to = Vector2(1.1, 1.3)
	rad.texture = gt; rad.mouse_filter = Control.MOUSE_FILTER_IGNORE; pv.add_child(rad)
	var suelo := ColorRect.new(); suelo.anchor_left = 0.1; suelo.anchor_right = 0.9; suelo.anchor_top = 0.82; suelo.anchor_bottom = 0.82; suelo.offset_bottom = 2
	suelo.color = Color(1, 1, 1, 0.1); pv.add_child(suelo)
	previa = VistaPrevia.new(); previa.set_anchors_preset(Control.PRESET_FULL_RECT); pv.add_child(previa)
	var marco := Panel.new(); marco.set_anchors_preset(Control.PRESET_FULL_RECT); marco.mouse_filter = Control.MOUSE_FILTER_IGNORE     # borde por encima del degradado
	marco.add_theme_stylebox_override("panel", Tema.caja(Color(0, 0, 0, 0), Tema.BORDE, Tema.RADIO)); pv.add_child(marco)
	var nv := VBoxContainer.new(); nv.position = Vector2(20, 16); nv.add_theme_constant_override("separation", 2)
	nombre = Tema.etiqueta("", 24, Tema.TEXTO, true); nv.add_child(nombre)
	desc = Tema.etiqueta("", 13, Tema.SUAVE, false, true); desc.custom_minimum_size.x = 420; nv.add_child(desc)
	pv.add_child(nv); g.add_child(pv)
	# ficha y ajustes
	var cp := Tema.capa(0); var capa: PanelContainer = cp[0]; var cv: VBoxContainer = cp[1]
	capa.custom_minimum_size.x = 420; g.add_child(capa)
	var pest := HBoxContainer.new(); pest.add_theme_constant_override("separation", 4)
	pest_ficha = Tema.boton("Ficha", "PestanaSel", func(): _pestana(true)); pest_ajustes = Tema.boton("Ajustes del avión", "Pestana", func(): _pestana(false))
	pest.add_child(pest_ficha); pest.add_child(pest_ajustes); cv.add_child(pest); cv.add_child(Tema.linea(0.1)); cv.add_child(Tema.margen(Control.new(), 0, 0, 0, 10))
	var cuerpo := VBoxContainer.new(); var sc := Tema.desplazable(cuerpo); cv.add_child(sc)
	panel_ficha = VBoxContainer.new(); cuerpo.add_child(panel_ficha)
	panel_ajustes = VBoxContainer.new(); panel_ajustes.add_theme_constant_override("separation", 4); panel_ajustes.visible = false; cuerpo.add_child(panel_ajustes)
	_construir_ajustes()

func _pestana(ficha: bool) -> void:
	panel_ficha.visible = ficha; panel_ajustes.visible = not ficha
	pest_ficha.theme_type_variation = "PestanaSel" if ficha else "Pestana"; pest_ajustes.theme_type_variation = "Pestana" if ficha else "PestanaSel"

## Seccion plegable (<details class="avanzado">): titulo con ▸/▾ y el contenido.
static func plegable(titulo: String, abierta: bool) -> Array:
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 6)
	v.add_child(Tema.linea(0.08))
	var b := Tema.boton(("▾ " if abierta else "▸ ") + titulo, "BotonPlano"); b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_stylebox_override("normal", StyleBoxEmpty.new()); b.add_theme_stylebox_override("hover", StyleBoxEmpty.new()); b.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	b.add_theme_font_size_override("font_size", 14)
	var cont := VBoxContainer.new(); cont.add_theme_constant_override("separation", 6); cont.visible = abierta
	b.pressed.connect(func(): cont.visible = not cont.visible; b.text = ("▾ " if cont.visible else "▸ ") + titulo)
	v.add_child(b); v.add_child(cont)
	return [v, cont]

func _txt_b(tam := 14) -> Label:
	var l := Tema.etiqueta("", tam, Tema.TEXTO, true, true); return l

func _construir_ajustes() -> void:
	# ---- centro de gravedad y peso ----
	var pc := plegable("Centro de gravedad y peso", true); sec_cm = pc[0]; var c: VBoxContainer = pc[1]; panel_ajustes.add_child(sec_cm)
	s_cg = Tema.deslizador(15, 60, 1, 30)
	var f := HBoxContainer.new(); f.add_theme_constant_override("separation", 8)
	f.add_child(Tema.etiqueta("morro", 14, Tema.SUAVE)); f.add_child(s_cg); f.add_child(Tema.etiqueta("cola", 14, Tema.SUAVE))
	c.add_child(Tema.fila("Centro de gravedad", f, 140)); f.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t_cg = _txt_b(); c.add_child(t_cg)
	s_masa = Tema.deslizador(500, 1500, 10, 900)
	var f2 := HBoxContainer.new(); f2.add_theme_constant_override("separation", 8); f2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	f2.add_child(Tema.etiqueta("ligero", 14, Tema.SUAVE)); f2.add_child(s_masa); f2.add_child(Tema.etiqueta("pesado", 14, Tema.SUAVE))
	c.add_child(Tema.fila("Peso", f2, 140))
	t_masa = _txt_b(); c.add_child(t_masa)
	t_efecto = Tema.etiqueta("", 13, Tema.OK, false, true); c.add_child(t_efecto)
	t_bateria = Tema.sub("", 13); c.add_child(t_bateria)
	var bd := Tema.boton("Volver a los valores de diseño", "", func(): p.borrar_cm(p.sesion["avion"]); refrescar_cm())
	bd.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN; c.add_child(bd)
	s_cg.value_changed.connect(func(_x): _leer_cm()); s_masa.value_changed.connect(func(_x): _leer_cm())
	# ---- emisora: recorridos y lanzamiento ----
	var pe := plegable("Emisora: recorridos y lanzamiento", false); panel_ajustes.add_child(pe[0]); var e: VBoxContainer = pe[1]
	e.add_child(Tema.rico("[color=#9fb3c8]Con mando, la palanca a tope mueve las superficies el recorrido mecánico del avión por este porcentaje, igual que el [b]dual rate[/b] de la emisora. Con teclado se usan recorridos reducidos.[/color]", 13))
	s_dr_al = Tema.deslizador(20, 100, 5, 100); e.add_child(Tema.fila("Alabeo", s_dr_al, 140)); t_dr_al = _txt_b(13); e.add_child(t_dr_al)
	s_dr_prof = Tema.deslizador(20, 100, 5, 100); e.add_child(Tema.fila("Profundidad", s_dr_prof, 140)); t_dr_prof = _txt_b(13); e.add_child(t_dr_prof)
	c_lanz = Tema.casilla("velocidad, cabeceo y alabeo al azar, como al lanzar a mano", true); e.add_child(Tema.fila("Lanzamiento real", c_lanz, 140))
	# ---- calibracion y aire ----
	var pk := plegable("Calibración con el avión real y aire", false); panel_ajustes.add_child(pk[0]); var k: VBoxContainer = pk[1]
	e_empuje = LineEdit.new(); e_empuje.placeholder_text = "del fabricante"; e_empuje.custom_minimum_size.x = 130
	var fe := HBoxContainer.new(); fe.add_theme_constant_override("separation", 8); fe.add_child(e_empuje); fe.add_child(Tema.etiqueta("gramos, con báscula", 13, Tema.SUAVE))
	k.add_child(Tema.fila("Empuje estático medido", fe, 140))
	s_res = Tema.deslizador(70, 160, 5, 100); k.add_child(Tema.fila("Resistencia", s_res, 140)); t_res = _txt_b(13); k.add_child(t_res)
	s_temp = Tema.deslizador(0, 40, 1, 20); k.add_child(Tema.fila("Temperatura del aire", s_temp, 140)); t_temp = _txt_b(13); k.add_child(t_temp)
	t_cal = Tema.sub("", 13); k.add_child(t_cal)
	for s in [s_dr_al, s_dr_prof, s_res, s_temp]: s.value_changed.connect(func(_x): _leer_cfg())
	c_lanz.toggled.connect(func(_x): _leer_cfg())
	e_empuje.text_changed.connect(func(_x): _leer_cfg())

# =====================================================================
func refrescar() -> void:
	var al = p.sesion["alumno"]
	d["subtitulo"].text = ("Piloto: " + String(al["nombre"])) if al != null else "Elige el avión y, si quieres, ajústalo como el tuyo."
	d["subtitulo"].visible = true
	b_progreso.visible = al != null
	for x in lista.get_children(): x.queue_free()
	for id in p.ids_hangar():
		var A := DatosComunes.avion(id)
		var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 2)
		v.add_child(Tema.etiqueta(String(A.get("nombre", id)), 16, Tema.TEXTO, true))
		var masa := ""; var mandos_txt := ""
		for r in A.get("caracteristicas", []):
			if String(r[0]).to_lower().begins_with("masa"): masa = String(r[1]).split(" (")[0]
			if String(r[0]) == "Mandos": mandos_txt = String(r[1])
		var sub := "cuadricóptero, mandos de dron comercial" if A.get("tipo", "") == "cuadricoptero" else "dron FPV, modos de Betaflight" if A.get("tipo", "") == "fpv" else "vehículo terrestre de dos patas" if A.get("tipo", "") == "bipode" else (mandos_txt if mandos_txt != "" else String(A.get("mandos", {}).get("izq_der", "timón")) + " y profundidad")
		v.add_child(Tema.etiqueta(sub + ((" · " + masa) if masa != "" else ""), 12, Tema.SUAVE, false, true))
		var t := Tarjeta.new(v); t.elegida = id == p.sesion["avion"]
		t.pulsada.connect(func(): p.elegir_avion(id); refrescar())
		lista.add_child(t)
	var A := DatosComunes.avion(p.sesion["avion"])
	nombre.text = String(A.get("nombre", "")); desc.text = String(A.get("descripcion", ""))
	# ficha: lo que trae el avion y, si no lo trae, la cuerda y el perfil
	var filas: Array = (A.get("caracteristicas", []) as Array).duplicate(true)
	var tiene := func(n: String) -> bool: return filas.any(func(f): return String(f[0]).to_lower().begins_with(n))
	if A.has("c_m") and not tiene.call("cuerda"): filas.insert(1, ["Cuerda", "%d mm" % int(round(A["c_m"] * 1000))])
	if A.has("perfil") and not tiene.call("perfil"): filas.insert(2, ["Perfil alar", A["perfil"]])
	for x in panel_ficha.get_children(): x.queue_free()
	panel_ficha.add_child(Tema.tabla_datos(filas))
	previa.mostrar(A, 1.4)
	refrescar_cm()

func refrescar_cm() -> void:
	_pintando = true
	_pintar_cfg()
	var id: String = p.sesion["avion"]; var A := DatosComunes.avion(id)
	if not A.has("x_le_mm") or not A.has("punto_neutro_mm"): sec_cm.visible = false; _pintando = false; return
	sec_cm.visible = true
	var C: float = A["c_m"] * 1000; var dd: Dictionary = p.cm_diseno(A); var c: Dictionary = p.cm_actual(id)
	var rango: Array = A.get("cg_rango_pct", [15, 60])
	s_cg.min_value = rango[0]; s_cg.max_value = rango[1]
	s_masa.min_value = round(dd["masa"] * 0.8 / 10) * 10; s_masa.max_value = round(dd["masa"] * 1.5 / 10) * 10
	s_cg.value = c["cg"]; s_masa.value = c["masa"]
	var np: float = (A["punto_neutro_mm"] - A["x_le_mm"]) / C * 100; var margen: float = np - c["cg"]
	t_cg.text = "%d %% de %s (%d mm tras el borde de ataque)%s" % [int(c["cg"]), A.get("cg_ref_texto", "la cuerda"), int(round(c["cg"] / 100.0 * C)), " · diseño" if c["cg"] == dd["cg"] else ""]
	var vs := sqrt(2 * c["masa"] / 1000.0 * 9.81 / (1.225 * A["S_m2"] * 1.1))
	t_masa.text = "%d g · carga alar %s g/dm² · pérdida %s m/s%s" % [int(c["masa"]), _f1(c["masa"] / (A["S_m2"] * 100)), _f1(vs), " · diseño" if c["masa"] == dd["masa"] else ""]
	var txt := ""; var color := Color("#8be08f")
	if margen < 0: color = Color("#ff6e66"); txt = "⚠ El centro de gravedad está DETRÁS del punto neutro (%d %%): el avión es inestable en cabeceo, cada perturbación crece sola. No se puede volar; en el avión real acaba en accidente nada más lanzarlo." % int(round(np))
	elif margen < 10: color = Color("#ffb74d"); txt = "Cola pesada: margen estático %d %% (punto neutro al %d %%). Muy sensible a la profundidad, le cuesta mantener la velocidad y entra en pérdida con facilidad." % [int(round(margen)), int(round(np))]
	elif margen > 30: color = Color("#ffb74d"); txt = "Morro pesado: margen estático %d %%. Muy estable, pero pide mucha profundidad arriba, vuela más rápido y puede no tener mando para recoger al aterrizar." % int(round(margen))
	else: txt = "Margen estático %d %% (punto neutro al %d %%): dentro de lo normal en un entrenador (10–30 %%)." % [int(round(margen)), int(round(np))]
	if c["masa"] > dd["masa"] * 1.15: txt += " Con %d g más, pierde a %s m/s: hay que lanzarlo más fuerte y aterrizar más rápido." % [int(c["masa"] - dd["masa"]), _f1(vs)]
	elif c["masa"] < dd["masa"] * 0.9: txt += " Más ligero: vuela más despacio, pero las rachas lo mueven más."
	var gmin = null if A.has("tren") else p.gas_minimo_lanzamiento({})      # un avion de pista no se lanza a mano
	if A.has("tren"): txt += " Despega y aterriza en pista."
	elif gmin == null: color = Color("#ff6e66"); txt += " ⚠ Con %d g no sale de la mano ni con todo el gas: demasiado peso para lanzarlo a mano." % int(c["masa"])
	else: txt += " Lanzado a mano (sin viento y sin tocar los mandos) sale con al menos el %d %% de gas." % p.pct_gas(gmin)
	t_efecto.text = txt; t_efecto.add_theme_color_override("font_color", color)
	var dbat: float = (c["cg"] - dd["cg"]) / 100.0 * C * c["masa"] / 115.0
	t_bateria.text = "En el avión real, el centro de gravedad se ajusta moviendo la batería." if c["cg"] == dd["cg"] else \
		"En el avión real equivale a mover la batería %d mm hacia %s%s" % [int(round(absf(dbat))), "la cola" if dbat > 0 else "el morro", " (no hay tanto sitio: haría falta lastre)." if absf(dbat) > 60 else "."]
	_pintando = false

static func _f1(x: float) -> String: return ("%.1f" % x)

func _leer_cm() -> void:
	if _pintando: return
	p.poner_cm(p.sesion["avion"], int(s_cg.value), int(s_masa.value))
	refrescar_cm()

func _pintar_cfg() -> void:
	var id: String = p.sesion["avion"]; var c: Dictionary = p.cfg_de(id); var A := DatosComunes.avion(id); var mec: Dictionary = p.recorrido_mecanico(id)
	var M: Dictionary = A.get("mandos", {})
	var lat := "alerones y timón" if (M.get("timon_max_grados", 0) > 0 and M.get("aleron_max_grados", 0)) else ("timón" if M.get("timon_max_grados", 0) > 0 else "alerones")
	var mlat: float = mec.get("aleron", mec.get("timon", M.get("aleron_max_grados", M.get("timon_max_grados", 0))))
	s_dr_al.value = c["drAlabeo"]; s_dr_prof.value = c["drProf"]
	t_dr_al.text = "%d %% · %s ±%s° (mecánico ±%s°)" % [int(c["drAlabeo"]), lat, _f1(mlat * c["drAlabeo"] / 100.0), str(mlat)]
	var mp: float = mec.get("prof", M.get("prof_max_grados", 0))
	t_dr_prof.text = "%d %% · ±%s° (mecánico ±%s°)" % [int(c["drProf"]), _f1(mp * c["drProf"] / 100.0), str(mp)]
	c_lanz.button_pressed = c["lanzReal"]
	if not e_empuje.has_focus(): e_empuje.text = str(c["empuje"]) if str(c["empuje"]) != "" else ""
	s_res.value = c["res"]; s_temp.value = c["temp"]
	t_res.text = "%d %% de la estimada" % int(c["res"])
	t_temp.text = "%d °C · densidad %.3f kg/m³" % [int(c["temp"]), 101325 / (287.05 * (c["temp"] + 273.15))]
	t_cal.text = "La resistencia se ajusta con planeos a mano sin motor: si el avión real toca antes que en el simulador lanzado igual, súbela. El calor baja la densidad: a 35 °C la pérdida sube un 3 % y el motor empuja un 6 % menos."

func _leer_cfg() -> void:
	if _pintando: return
	var id: String = p.sesion["avion"]; var c: Dictionary = p.cfg_de(id)
	c["drAlabeo"] = s_dr_al.value; c["drProf"] = s_dr_prof.value; c["lanzReal"] = c_lanz.button_pressed
	c["empuje"] = e_empuje.text.strip_edges(); c["res"] = s_res.value; c["temp"] = s_temp.value
	p.poner_cfg(id, c)
	_pintando = true; _pintar_cfg(); _pintando = false
