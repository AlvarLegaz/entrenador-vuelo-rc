extends Node3D
## Simulador de vuelo RC, version 2 (Godot 4): vuelo libre sobre el Campo de Cartagena con el render de Godot. Todo lo
## demas es COMUN con la version 1 (el navegador, simulador/simulador.html): los aviones, el mundo, las zonas de
## detalle y la fisica (modelo_avion.gd y entorno.gd son traducciones literales de modelos.js y entorno.js, comprobadas
## con pruebas/prueba_fisica.gd). El bucle de vuelo es el de paso() en simulador.html: 500 pasos por segundo.
##
## Opciones de linea de ordenes (tras --), para pruebas: --auto (vuela sin menu), --camara=N, --gases=0..1,
## --esperar=S y --captura=ruta.png (guarda la pantalla a los S segundos y sale), --avion=ID.

const DT := 1.0 / 500
const D2R := PI / 180.0
const G0 := 9.81
const RHO := 1.225
const MUNDO := "cartagena"
# recorrido mecanico (grados a palanca a tope sin dual rate) de cada avion: el mismo que en simulador.html
const RECORRIDO_MECANICO := { "E1": { "prof": 12, "timon": 15 }, "E2": { "prof": 12, "aleron": 15 }, "E3": { "prof": 12, "aleron": 15 }, "T1": { "prof": 15, "aleron": 15 } }

# ---- estado que leen los instrumentos ----
var ent := Entorno.new()
var modelo: ModeloAvion
var av := {}
var mando := { "pitch": 0.0, "yaw": 0.0, "pitchObj": 0.0, "yawObj": 0.0, "trim": 0.0 }
var camara := 1
var mostrar_hud := true
var instrumentos := true
var ver_ayuda := false
var aviso := ""
var toast := ""
var toast_t := 0.0
var casa := { "N": 0.0, "E": 0.0 }
var texto_cm := ""
var vel_perdida := 8.0
var mundo3d: Mundo3D
var mundo_datos := {}
var volando_en_pantalla := false

# ---- ajustes (se guardan en user://ajustes.cfg) ----
var aj := { "avion": "", "cm_diseno": true, "cg_pct": 0.0, "masa_g": 0.0, "dr_alabeo": 100.0, "dr_prof": 100.0, "lanz_real": true,
			"empuje_gf": 0.0, "resistencia": 100.0, "temperatura": 20.0, "viento": 2.0, "viento_desde": 90.0, "rachas": true,
			"gas_mando": "incremental", "expo_mando": 30.0, "lanz": {}, "calidad": 2, "dificultad": "real" }
var ids_aviones := []
var indice_zonas := []
var zonas_cache := {}
var orto := []                     # [Image, ImageTexture] de la region
var avion3d: Avion3D
var cam: Camera3D
var _fov1 := -1.0
const ZOOM_PILOTO := 0.10          # fraccion del alto de la pantalla que ocupa la envergadura en la camara del piloto
var _acum := 0.0
var _mando_usado := false
var _botones_antes := {}
var _fuente_mandos := ""
var _mandos_base := {}
var _args := {}
var _t_auto := 0.0
var _rend := []

# ---- interfaz ----
var ui: CanvasLayer
var menu: Control
var hud: Instrumentos
var carga: Control
var mapa: MapaLanzamiento
var w := {}                        # controles del menu por nombre

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	ids_aviones = DatosComunes.aviones()
	_cargar_ajustes()
	if _args.has("avion"): aj["avion"] = _args["avion"]
	if _args.has("calidad"): aj["calidad"] = int(_args["calidad"])
	if _args.has("dificultad"): aj["dificultad"] = _args["dificultad"]
	if not ids_aviones.has(aj["avion"]): aj["avion"] = ids_aviones[0]
	mundo_datos = DatosComunes.mundo(MUNDO)
	ent.poner_mundo(mundo_datos)
	indice_zonas = DatosComunes.indice_zonas().filter(func(z): return z["mundo"] == MUNDO)
	orto = Mundo3D.cargar_orto_region(MUNDO)
	if aj["lanz"].is_empty():          # por defecto, el centro de la primera zona de detalle (como en el navegador)
		var N := 0.0; var E := 0.0
		if not indice_zonas.is_empty(): N = round(indice_zonas[0]["centro"]["N"]); E = round(indice_zonas[0]["centro"]["E"])
		aj["lanz"] = { "N": N, "E": E, "rumbo": rumbo_despejado(N, E) }
	cam = Camera3D.new(); cam.near = 0.05; cam.far = 16000.0; cam.fov = 50; add_child(cam); cam.current = true
	_construir_ui()
	if _args.has("auto"): call_deferred("_volar")
	elif _args.has("captura"):         # pruebas: captura del menu
		await get_tree().create_timer(2.0).timeout
		get_viewport().get_texture().get_image().save_png(_args["captura"]); get_tree().quit()

# =====================================================================
#  AJUSTES
# =====================================================================
func _cargar_ajustes() -> void:
	var cf := ConfigFile.new()
	if cf.load("user://ajustes.cfg") != OK or not cf.has_section("v2"): return
	for k in cf.get_section_keys("v2"): aj[k] = cf.get_value("v2", k)

func _guardar_ajustes() -> void:
	var cf := ConfigFile.new()
	for k in aj.keys(): cf.set_value("v2", k, aj[k])
	cf.save("user://ajustes.cfg")

func cm_diseno(A: Dictionary) -> Dictionary:
	return { "cg": round((A["cg_mm"][0] - A["x_le_mm"]) / (A["c_m"] * 1000) * 100), "masa": round(A["masa_kg"] * 100) * 10 }

## Rumbo de lanzamiento mas despejado desde (N, E): el que menos terreno sube en 1,5 km (rumboDespejado del navegador).
func rumbo_despejado(N: float, E: float) -> float:
	var mejor := 0.0; var menos := INF; var r := 0.0
	while r < 360:
		var sube := -INF; var d := 100.0
		while d <= 1500:
			sube = maxf(sube, ent.altura_mar(N + d * cos(r * D2R), E + d * sin(r * D2R))); d += 50
		if sube < menos: menos = sube; mejor = r
		r += 22.5
	return mejor

# =====================================================================
#  MENU
# =====================================================================
func _fila(caja: VBoxContainer, texto: String, control: Control) -> Control:
	var h := HBoxContainer.new(); var l := Label.new(); l.text = texto; l.custom_minimum_size.x = 210
	h.add_child(l); control.size_flags_horizontal = Control.SIZE_EXPAND_FILL; h.add_child(control); caja.add_child(h)
	return control

func _spin(minv: float, maxv: float, paso: float, valor: float, sufijo := "") -> SpinBox:
	var s := SpinBox.new(); s.min_value = minv; s.max_value = maxv; s.step = paso; s.value = valor; s.suffix = sufijo
	return s

func _titulo(caja: VBoxContainer, texto: String) -> void:
	var l := Label.new(); l.text = texto; l.add_theme_font_size_override("font_size", 17); l.add_theme_color_override("font_color", Color(1, 0.84, 0.31))
	caja.add_child(l)

func _construir_ui() -> void:
	ui = CanvasLayer.new(); add_child(ui)
	hud = Instrumentos.new(); hud.p = self; ui.add_child(hud)
	menu = Control.new(); menu.set_anchors_preset(Control.PRESET_FULL_RECT); ui.add_child(menu)
	var fondo := ColorRect.new(); fondo.color = Color(0.06, 0.08, 0.11); fondo.set_anchors_preset(Control.PRESET_FULL_RECT); menu.add_child(fondo)
	var hb := HBoxContainer.new(); hb.set_anchors_preset(Control.PRESET_FULL_RECT); hb.add_theme_constant_override("separation", 12)
	hb.offset_left = 12; hb.offset_top = 12; hb.offset_right = -12; hb.offset_bottom = -12; menu.add_child(hb)
	var sc := ScrollContainer.new(); sc.custom_minimum_size.x = 520; sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; hb.add_child(sc)
	var c := VBoxContainer.new(); c.size_flags_horizontal = Control.SIZE_EXPAND_FILL; c.add_theme_constant_override("separation", 6); sc.add_child(c)
	var t := Label.new(); t.text = "Entrenador de vuelo RC · v2 (Godot)"; t.add_theme_font_size_override("font_size", 24); c.add_child(t)
	var st := Label.new(); st.text = "Vuelo libre: Campo de Cartagena. Mismos aviones, mundo y física que el simulador del navegador (v1)."
	st.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; st.add_theme_color_override("font_color", Color(0.7, 0.75, 0.8)); c.add_child(st)

	_titulo(c, "Dificultad")
	var od := OptionButton.new(); od.add_item("Real: como el avión de verdad (la más difícil)"); od.add_item("Fácil: la física sencilla de antes")
	od.selected = 1 if aj["dificultad"] == "facil" else 0; w["dificultad"] = _fila(c, "Física", od)
	var di := Label.new(); di.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; di.add_theme_color_override("font_color", Color(0.7, 0.75, 0.8)); c.add_child(di)
	var info_dif := func(i: int) -> void:
		di.text = ("Sin par ni estela de la hélice, sin efectos P ni giroscópico, pérdida simétrica, sin efecto suelo, el mismo viento a cualquier altura, rachas sin alabeo, aire estándar y lanzamiento perfecto. Para aprender." if i == 1
			else "Par y estela de la hélice, efecto P y giroscópico, pérdida por semiala (cae de un ala), efecto suelo, viento más flojo junto al suelo, turbulencia que alabea, densidad según la temperatura, calibración y lanzamiento con dispersión.")
	info_dif.call(od.selected); od.item_selected.connect(info_dif)

	_titulo(c, "Avión")
	var ob := OptionButton.new()
	for id in ids_aviones: ob.add_item("%s · %s" % [id, DatosComunes.avion(id).get("nombre", id)])
	ob.selected = ids_aviones.find(aj["avion"]); w["avion"] = _fila(c, "Avión", ob)
	var desc := Label.new(); desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; desc.add_theme_color_override("font_color", Color(0.7, 0.75, 0.8)); c.add_child(desc); w["desc"] = desc
	w["cm_diseno"] = _fila(c, "CG y peso", CheckBox.new()); w["cm_diseno"].text = "de diseño"
	w["cg_pct"] = _fila(c, "CG (% de la cuerda)", _spin(5, 60, 1, 25, " %"))
	w["masa_g"] = _fila(c, "Peso en vuelo", _spin(200, 3000, 10, 900, " g"))

	_titulo(c, "Emisora (con mando) y lanzamiento")
	w["dr_alabeo"] = _fila(c, "Dual rate alabeo/timón", _spin(20, 100, 5, aj["dr_alabeo"], " %"))
	w["dr_prof"] = _fila(c, "Dual rate profundidad", _spin(20, 100, 5, aj["dr_prof"], " %"))
	w["lanz_real"] = _fila(c, "Lanzamiento", CheckBox.new()); w["lanz_real"].text = "real (velocidad y actitud al azar)"; w["lanz_real"].button_pressed = aj["lanz_real"]
	var gm := OptionButton.new(); gm.add_item("incremental (la palanca sube/baja el gas)"); gm.add_item("absoluto (palanca = gas)")
	gm.selected = 0 if aj["gas_mando"] == "incremental" else 1; w["gas_mando"] = _fila(c, "Gas con el mando", gm)
	w["expo_mando"] = _fila(c, "Exponencial del mando", _spin(0, 80, 5, aj["expo_mando"], " %"))

	_titulo(c, "Calibración y aire")
	w["empuje_gf"] = _fila(c, "Empuje estático medido", _spin(0, 3000, 10, aj["empuje_gf"], " gf (0 = estimado)"))
	w["resistencia"] = _fila(c, "Resistencia", _spin(50, 200, 5, aj["resistencia"], " % de la estimada"))
	w["temperatura"] = _fila(c, "Temperatura", _spin(-5, 45, 1, aj["temperatura"], " °C"))

	_titulo(c, "Viento")
	w["viento"] = _fila(c, "Velocidad", _spin(0, 10, 0.5, aj["viento"], " m/s"))
	w["viento_desde"] = _fila(c, "Viene del", _spin(0, 359, 5, aj["viento_desde"], " ° (0 norte, 90 este)"))
	w["rachas"] = _fila(c, "Rachas", CheckBox.new()); w["rachas"].text = "con rachas y turbulencia"; w["rachas"].button_pressed = aj["rachas"]

	var oc := OptionButton.new(); oc.add_item("baja"); oc.add_item("media"); oc.add_item("alta (sombras lejanas, oclusión ambiental, más árboles)")
	oc.selected = int(aj["calidad"]); w["calidad"] = _fila(c, "Calidad gráfica", oc)

	_titulo(c, "Punto de lanzamiento")
	var lp := Label.new(); lp.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; c.add_child(lp); w["lanz_txt"] = lp
	var bz := Button.new(); bz.text = "Centro de la zona de detalle"; c.add_child(bz)
	bz.pressed.connect(func():
		if indice_zonas.is_empty(): return
		var z: Dictionary = indice_zonas[0]; _poner_punto(round(z["centro"]["N"]), round(z["centro"]["E"])))
	var sep := HSeparator.new(); c.add_child(sep)
	var bv := Button.new(); bv.text = "VOLAR"; bv.custom_minimum_size.y = 48; bv.add_theme_font_size_override("font_size", 22); c.add_child(bv)
	bv.pressed.connect(_volar)
	var ay := Label.new(); ay.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; ay.add_theme_color_override("font_color", Color(0.7, 0.75, 0.8))
	ay.text = "Teclado: flechas (palanca), W/S gases, L lanzar, R reiniciar, 1/2/3 cámaras, T ayuda, Esc menú. Mando: palanca derecha avión, izquierda gas, A lanzar."
	c.add_child(ay)

	mapa = MapaLanzamiento.new(); mapa.size_flags_horizontal = Control.SIZE_EXPAND_FILL; mapa.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hb.add_child(mapa); mapa.poner(orto[1], ent.terreno, mundo_datos["lugares"], indice_zonas)
	mapa.punto_elegido.connect(func(N, E): _poner_punto(round(N), round(E)))

	carga = ColorRect.new(); (carga as ColorRect).color = Color(0.06, 0.08, 0.11, 0.92); carga.set_anchors_preset(Control.PRESET_FULL_RECT)
	var lc := Label.new(); lc.text = "Construyendo el mundo (terreno, ortofoto, edificios y árboles)…"; lc.add_theme_font_size_override("font_size", 22)
	lc.set_anchors_preset(Control.PRESET_CENTER); lc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; lc.grow_horizontal = Control.GROW_DIRECTION_BOTH
	carga.add_child(lc); carga.visible = false; ui.add_child(carga)

	w["avion"].item_selected.connect(func(i): aj["avion"] = ids_aviones[i]; _pintar_avion())
	w["cm_diseno"].toggled.connect(func(_b): _pintar_cm())
	_pintar_avion(); _poner_punto(aj["lanz"]["N"], aj["lanz"]["E"])
	_mostrar_menu(true)

func _pintar_avion() -> void:
	var A := DatosComunes.avion(aj["avion"])
	w["desc"].text = String(A.get("descripcion", ""))
	var d := cm_diseno(A)
	var guardado: Dictionary = aj.get("cm_" + aj["avion"], {})
	w["cm_diseno"].button_pressed = guardado.is_empty()
	w["cg_pct"].value = guardado.get("cg", d["cg"]); w["masa_g"].value = guardado.get("masa", d["masa"])
	_pintar_cm()

func _pintar_cm() -> void:
	var dis: bool = w["cm_diseno"].button_pressed
	w["cg_pct"].editable = not dis; w["masa_g"].editable = not dis
	if dis:
		var d := cm_diseno(DatosComunes.avion(aj["avion"])); w["cg_pct"].value = d["cg"]; w["masa_g"].value = d["masa"]

func _poner_punto(N: float, E: float) -> void:
	aj["lanz"] = { "N": N, "E": E, "rumbo": rumbo_despejado(N, E) }
	var z := DatosComunes.zona_en(indice_zonas, MUNDO, N, E)
	w["lanz_txt"].text = "N %+.0f m, E %+.0f m (desde el corazón) · terreno a %.0f m sobre el mar · lanzamiento hacia %.0f°\n%s" % [
		N, E, ent.altura_mar(N, E), aj["lanz"]["rumbo"],
		("Dentro de la zona de detalle «%s»: terreno a 5 m, ortofoto a 0,5 m, edificios y árboles reales." % z["id"]) if not z.is_empty()
		else "Fuera de las zonas de detalle: terreno de 150 m con la ortofoto de la región."]
	mapa.punto = aj["lanz"]; mapa.queue_redraw()

func _leer_menu() -> void:
	for k in ["dr_alabeo", "dr_prof", "expo_mando", "empuje_gf", "resistencia", "temperatura", "viento", "viento_desde"]: aj[k] = w[k].value
	for k in ["lanz_real", "rachas"]: aj[k] = w[k].button_pressed
	aj["gas_mando"] = "incremental" if w["gas_mando"].selected == 0 else "absoluto"
	aj["calidad"] = w["calidad"].selected
	aj["dificultad"] = "facil" if w["dificultad"].selected == 1 else "real"
	if w["cm_diseno"].button_pressed: aj.erase("cm_" + aj["avion"])
	else: aj["cm_" + aj["avion"]] = { "cg": w["cg_pct"].value, "masa": w["masa_g"].value }
	_guardar_ajustes()

func _mostrar_menu(si: bool) -> void:
	menu.visible = si; hud.visible = not si; volando_en_pantalla = not si

# =====================================================================
#  EMPEZAR, LANZAR, PASO
# =====================================================================
func _volar() -> void:
	if not _args.has("auto"): _leer_menu()
	carga.visible = true; menu.visible = false
	await get_tree().process_frame; await get_tree().process_frame
	var t0 := Time.get_ticks_msec()
	if mundo3d != null and mundo3d.calidad != int(aj["calidad"]):      # otra calidad: se rehace el mundo
		mundo3d.queue_free(); mundo3d = null; await get_tree().process_frame
	if mundo3d == null:
		mundo3d = Mundo3D.new(); mundo3d.calidad = int(aj["calidad"]); add_child(mundo3d); mundo3d.construir(ent, mundo_datos, orto)
	# zona de detalle del punto de lanzamiento (en la fisica y en el dibujo)
	var N: float = aj["lanz"]["N"]; var E: float = aj["lanz"]["E"]
	var meta := DatosComunes.zona_en(indice_zonas, MUNDO, N, E); var z := {}
	if not meta.is_empty():
		if not zonas_cache.has(meta["id"]): zonas_cache[meta["id"]] = DatosComunes.cargar_zona(meta)
		z = zonas_cache[meta["id"]]
	mundo3d.claro = Vector2(E, N)
	ent.poner_zona(z); mundo3d.poner_zona(z)
	casa = { "N": N, "E": E }
	mundo3d.poner_base(N, E)
	print("Mundo listo en %d ms" % (Time.get_ticks_msec() - t0))
	_empezar()
	carga.visible = false; _mostrar_menu(false)

func _empezar() -> void:
	var id: String = aj["avion"]; var A := DatosComunes.avion(id)
	modelo = ModeloAvion.new(A)
	texto_cm = ""
	if aj.has("cm_" + id) and A.has("x_le_mm"):
		var c: Dictionary = aj["cm_" + id]
		modelo.configurar({ "masa_kg": c["masa"] / 1000.0, "cg_mm": A["x_le_mm"] + c["cg"] / 100.0 * A["c_m"] * 1000 })
		texto_cm = "CG %d %% de la cuerda · %d g" % [int(c["cg"]), int(c["masa"])]
	modelo.configurar({ "temperatura": aj["temperatura"], "empuje_gf": aj["empuje_gf"], "resistencia": aj["resistencia"] / 100.0 })
	modelo.facil = aj["dificultad"] == "facil"; ent.facil = modelo.facil      # dificultad (ver ModeloAvion.facil)
	_mandos_base = modelo.mandos.duplicate(); _fuente_mandos = ""
	if avion3d: avion3d.queue_free()
	avion3d = Avion3D.new(A); add_child(avion3d)
	vel_perdida = _vel_perdida(A)
	_reiniciar()

func _vel_perdida(A: Dictionary) -> float:
	for fila in A.get("caracteristicas", []):
		if String(fila[0]).to_lower().begins_with("velocidad de p"):
			var v := String(fila[1]).replace(",", ".").to_float()
			if v > 0: return v
	return sqrt(2 * modelo.masa_kg * G0 / (RHO * modelo.S_m2 * 1.1))

func _reiniciar() -> void:
	av = modelo.estado_inicial()
	var C := casa; av["p"] = [C["N"], C["E"], -(ent.altura(C["N"], C["E"]) + 1.6)]
	_orientar()
	mando["pitch"] = 0.0; mando["yaw"] = 0.0; mando["trim"] = modelo.compensador_grados
	ent.configurar_viento(aj["viento"], aj["viento_desde"], aj["rachas"])
	hud.estela = []
	aviso = "Pulsa L para lanzar (pon antes gases con W)"
	_fov1 = -1.0; _acum = 0.0

func _orientar() -> void:
	var e := Cuat.euler(av["q"])
	av["q"] = Cuat.desde_euler(e[0], e[1], aj["lanz"]["rumbo"] * D2R)

func _lanzar() -> void:
	if av.get("estado", "") != "en mano": return
	modelo.lanzar(av); _orientar(); aviso = ""
	if aj["lanz_real"] and not modelo.facil:          # un lanzamiento a mano nunca es perfecto: velocidad, cabeceo y alabeo al azar
		var gauss := func() -> float: return (randf() + randf() + randf() - 1.5) / 0.5
		var e := Cuat.euler(av["q"])
		av["v"][0] *= 1 + 0.08 * gauss.call()
		av["q"] = Cuat.desde_euler(e[0] + 4 * D2R * gauss.call(), e[1] + 2.5 * D2R * gauss.call(), e[2] + 3 * D2R * gauss.call())

## Con mando: recorridos mecanicos por el dual rate y sin la exponencial del simulador. Con teclado: los del simulador.
func _aplicar_recorridos() -> void:
	var fuente := "mando" if _mando_usado else "teclado"
	if fuente == _fuente_mandos: return
	_fuente_mandos = fuente
	var B := _mandos_base; var m := B.duplicate()
	if fuente == "mando":
		var mec: Dictionary = RECORRIDO_MECANICO.get(aj["avion"], {})
		m["expo"] = 0.0
		m["prof_max_grados"] = mec.get("prof", B["prof_max_grados"]) * aj["dr_prof"] / 100.0
		if B.get("aleron_max_grados", 0): m["aleron_max_grados"] = mec.get("aleron", B["aleron_max_grados"]) * aj["dr_alabeo"] / 100.0
		if B.get("timon_max_grados", 0): m["timon_max_grados"] = mec.get("timon", B["timon_max_grados"]) * aj["dr_alabeo"] / 100.0
	modelo.mandos = m

## Un paso de la simulacion: el mismo que paso() en simulador.html (sin las misiones, que en v2 no hay).
func _paso(dt: float) -> void:
	_aplicar_recorridos()
	var viento := ent.actualizar(dt)
	modelo.servos(av, mando, dt)
	av["agl"] = -av["p"][2] - ent.altura(av["p"][0], av["p"][1])
	viento = ent.viento_a(viento, av["agl"])
	av["pg"] = ent.rafaga_alabeo(modelo.b_m, av["agl"])
	if av["estado"] != "volando": return
	var vn := modelo.paso(av, viento, dt)
	var suelo := ent.contacto_suelo(av, vn)
	if suelo != "": _terminar(suelo)

func _terminar(final: String) -> void:
	if av["estado"] != "volando": return
	av["estado"] = "roto" if final.begins_with("roto") else ("aterrizado" if final == "aterrizado" else "terminado")
	av["v"] = [0.0, 0.0, 0.0]; av["w"] = [0.0, 0.0, 0.0]
	aviso = ("¡ROTO!  (" + final.substr(6, final.length() - 7) + ")") if final.begins_with("roto") else ("Aterrizado" if final == "aterrizado" else "Vuelo terminado")
	aviso += "     R: otra vez · Esc: menú"

func _avisar(s: String) -> void:
	toast = s; toast_t = 2.5

# =====================================================================
#  ENTRADAS
# =====================================================================
func _unhandled_input(ev: InputEvent) -> void:
	if not (ev is InputEventKey and ev.pressed and not ev.echo): return
	if menu.visible or carga.visible: return
	var k: int = ev.physical_keycode
	match k:
		KEY_L: _lanzar()
		KEY_R:
			if av["estado"] == "volando": _terminar("abandonado")
			else: _reiniciar()
		KEY_ESCAPE:
			if av["estado"] == "volando": _terminar("abandonado")
			else: _mostrar_menu(true); _pintar_avion()
		KEY_SPACE: av["gases"] = 0.0
		KEY_1: camara = 1
		KEY_2: camara = 2
		KEY_3: camara = 3
		KEY_H: mostrar_hud = not mostrar_hud
		KEY_I: instrumentos = not instrumentos; _avisar("Instrumentos" if instrumentos else "Sin instrumentos (como en el campo)")
		KEY_T: ver_ayuda = not ver_ayuda
		KEY_G: ent.viento["rachas"] = not ent.viento["rachas"]; _avisar("Rachas " + ("sí" if ent.viento["rachas"] else "no"))
		KEY_BRACKETLEFT: mando["trim"] = maxf(-6, mando["trim"] - 0.25)
		KEY_BRACKETRIGHT: mando["trim"] = minf(6, mando["trim"] + 0.25)
	if ev.keycode == KEY_PLUS or ev.keycode == KEY_KP_ADD or ev.keycode == KEY_EQUAL:
		ent.viento["base"] = minf(10, ent.viento["base"] + 1); _avisar("Viento %.0f m/s" % ent.viento["base"])
	if ev.keycode == KEY_MINUS or ev.keycode == KEY_KP_SUBTRACT:
		ent.viento["base"] = maxf(0, ent.viento["base"] - 1); _avisar("Viento %.0f m/s" % ent.viento["base"])

static func _zona_muerta(x: float, z: float) -> float:
	return 0.0 if absf(x) < z else signf(x) * (absf(x) - z) / (1 - z)

static func _expo(x: float, e: float) -> float:
	return (1 - e) * x + e * x * x * x

## Mando (palanca derecha avion, izquierda gas). Devuelve true si manda el mando.
func _leer_mando(dt: float) -> bool:
	var js := Input.get_connected_joypads()
	if js.is_empty(): return false
	var d: int = js[0]; var zm := 0.06; var ex: float = aj["expo_mando"] / 100.0
	var rx := _zona_muerta(Input.get_joy_axis(d, JOY_AXIS_RIGHT_X), zm); var ry := _zona_muerta(Input.get_joy_axis(d, JOY_AXIS_RIGHT_Y), zm)
	var ly_raw := Input.get_joy_axis(d, JOY_AXIS_LEFT_Y); var ly := _zona_muerta(ly_raw, zm)
	var pulsado := func(b: int) -> bool:
		var ahora := Input.is_joy_button_pressed(d, b); var antes: bool = _botones_antes.get(b, false); _botones_antes[b] = ahora
		return ahora and not antes
	if pulsado.call(JOY_BUTTON_A): _lanzar()
	if pulsado.call(JOY_BUTTON_B): av["gases"] = 0.0
	if pulsado.call(JOY_BUTTON_Y): camara = camara % 3 + 1
	if pulsado.call(JOY_BUTTON_X):
		if av["estado"] == "volando": _terminar("abandonado")
		else: _reiniciar()
	if pulsado.call(JOY_BUTTON_START) and av["estado"] == "volando": _terminar("abandonado")
	if pulsado.call(JOY_BUTTON_DPAD_UP): mando["trim"] = minf(6, mando["trim"] + 0.25)
	if pulsado.call(JOY_BUTTON_DPAD_DOWN): mando["trim"] = maxf(-6, mando["trim"] - 0.25)
	var moviendo := rx != 0 or ry != 0
	if moviendo or _mando_usado:
		mando["pitch"] = _expo(ry, ex); mando["yaw"] = _expo(rx, ex)
		mando["pitchObj"] = mando["pitch"]; mando["yawObj"] = mando["yaw"]
	if moviendo: _mando_usado = true
	if not av["motorRoto"]:
		if aj["gas_mando"] == "absoluto":
			if _mando_usado or ly != 0: av["gases"] = clampf((1 - ly_raw) / 2, 0, 1)
		elif ly != 0: av["gases"] = clampf(av["gases"] - ly * 0.7 * dt, 0, 1)
	return moviendo or _mando_usado

func _leer_teclado(dt: float) -> void:
	var arriba := Input.is_physical_key_pressed(KEY_UP); var abajo := Input.is_physical_key_pressed(KEY_DOWN)
	var dcha := Input.is_physical_key_pressed(KEY_RIGHT); var izq := Input.is_physical_key_pressed(KEY_LEFT)
	var palanca := arriba or abajo or dcha or izq
	if palanca: _mando_usado = false
	if not (_leer_mando(dt) and not palanca):
		mando["pitchObj"] = (1.0 if abajo else 0.0) - (1.0 if arriba else 0.0)     # +1 = tirar
		mando["yawObj"] = (1.0 if dcha else 0.0) - (1.0 if izq else 0.0)
		for k in ["pitch", "yaw"]:      # la palanca va al tope a 5/s y vuelve al centro a 8/s
			var obj: float = mando[k + "Obj"]; var vel := 8.0 if obj == 0 else 5.0; var dd: float = obj - mando[k]
			mando[k] += signf(dd) * minf(absf(dd), vel * dt)
	if av["motorRoto"]: return
	if Input.is_physical_key_pressed(KEY_W): av["gases"] = minf(1, av["gases"] + 0.8 * dt)
	if Input.is_physical_key_pressed(KEY_S): av["gases"] = maxf(0, av["gases"] - 0.8 * dt)

# =====================================================================
#  BUCLE Y CAMARAS
# =====================================================================
func _process(dt_real: float) -> void:
	if toast_t > 0: toast_t -= dt_real
	if not volando_en_pantalla or av.is_empty(): return
	var dt := minf(0.1, dt_real)
	if _args.has("auto"): _piloto_auto()
	else: _leer_teclado(dt)
	_acum += dt
	while _acum >= DT:
		_paso(DT); _acum -= DT
	avion3d.actualizar(av)
	mundo3d.actualizar_manga(ent.viento["actual"])
	_camara()
	_auto(dt_real)

func _camara() -> void:
	var t := Avion3D.ned(av["p"])
	if _args.has("cenital"):          # pruebas: vista vertical del punto de lanzamiento desde la altura dada
		cam.fov = 60; cam.global_position = mundo3d.base + Vector3(0, float(_args["cenital"]), 0); cam.look_at(mundo3d.base, Vector3.FORWARD); return
	if camara == 1:
		# vista del piloto con ZOOM AUTOMATICO, como en el navegador: el campo de vision se cierra con la distancia para que
		# la envergadura ocupe siempre un 10 % del alto de la pantalla (ZOOM_PILOTO), entre 50 y 1,5 grados. Suavizado
		var b := mundo3d.base + Vector3(1.5, 1.7, 2)
		var env: float = float(modelo.b_m) if modelo != null else 1.0
		var d := b.distance_to(t); var obj := maxf(1.5, minf(50.0, rad_to_deg(env / (ZOOM_PILOTO * maxf(d, 0.5)))))
		_fov1 = obj if _fov1 < 0 else _fov1 + (obj - _fov1) * 0.08
		cam.fov = _fov1; cam.global_position = b
		if d > 0.1: cam.look_at(t, Vector3.UP)
	elif camara == 2:
		var yaw: float = Cuat.euler(av["q"])[2]
		cam.fov = 60; cam.global_position = t + Avion3D.ned([-cos(yaw) * 5, -sin(yaw) * 5, -1.5]); cam.look_at(t, Vector3.UP)
	else:
		var q: Array = av["q"]
		var pos := t + Avion3D.ned(Cuat.rot(q, [0.3, 0.0, -0.1])); var fw := Avion3D.ned(Cuat.rot(q, [1.0, 0.0, 0.0])); var up := Avion3D.ned(Cuat.rot(q, [0.0, 0.0, -1.0]))
		cam.fov = 80; cam.global_position = pos; cam.look_at(pos + fw, up)

## Piloto automatico de las pruebas: alas niveladas, subida suave hasta 60 m sobre el terreno y luego crucero.
func _piloto_auto() -> void:
	if av["estado"] != "volando": return
	var e := Cuat.euler(av["q"]); var alto: bool = av["agl"] > 60
	mando["yaw"] = clampf(-(e[0] / D2R - (20.0 if alto else 0.0)) / 45.0, -0.6, 0.6)
	mando["pitch"] = clampf(((2.0 if alto else 10.0) - e[1] / D2R) / 15.0, -0.6, 0.6)
	av["gases"] = 0.55 if alto else float(_args.get("gases", "1"))

## Pruebas desde la linea de ordenes: vuela solo (gases y lanzamiento), mide el tiempo por cuadro y guarda una captura.
func _auto(dt_real: float) -> void:
	if not _args.has("auto"): return
	_t_auto += dt_real
	var vp := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	if _t_auto > 1.5:
		_rend.append([dt_real, Performance.get_monitor(Performance.TIME_PROCESS), Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
					  Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
					  RenderingServer.viewport_get_measured_render_time_cpu(vp) / 1000.0, RenderingServer.viewport_get_measured_render_time_gpu(vp) / 1000.0])
	if _args.has("traza") and av["estado"] == "volando" and fmod(av["t"], 0.5) < DT * 30 and av["t"] - float(_args.get("_tt", "-1")) > 0.3:
		_args["_tt"] = str(av["t"]); var e := Cuat.euler(av["q"])
		print("  t %.1f  agl %.1f  V %.1f  alabeo %.0f  cabeceo %.0f  rumbo %.0f  gases %.2f  de %.1f  da %.1f  dr %.1f" % [av["t"], av["agl"], av["V"], e[0] / D2R, e[1] / D2R, e[2] / D2R, av["gases"], av["de"] / D2R, av["da"] / D2R, av["dr"] / D2R])
	if av["estado"] == "en mano":
		av["gases"] = float(_args.get("gases", "1")); camara = int(_args.get("camara", "1"))
		if _t_auto > 0.3: _lanzar()
	if _t_auto >= float(_args.get("esperar", "6")):
		var med := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
		for x in _rend:
			for i in 6: med[i] += x[i] / maxf(1, _rend.size())
		print("AUTO: %d cuadros, %.1f ms por cuadro (%.0f fps), proceso %.1f ms, render CPU %.1f ms GPU %.1f ms, %d llamadas de dibujo, %.1f M primitivas; estado %s, altura %.1f m, t %.1f s" % [
			_rend.size(), med[0] * 1000, 1.0 / maxf(med[0], 1e-6), med[1] * 1000, med[4] * 1000, med[5] * 1000, med[2], med[3] / 1e6,
			av["estado"], -av["p"][2] - ent.altura(av["p"][0], av["p"][1]), av["t"]])
		if _args.has("captura"):
			var img := get_viewport().get_texture().get_image(); img.save_png(_args["captura"])
			print("Captura en " + _args["captura"])
		get_tree().quit()
