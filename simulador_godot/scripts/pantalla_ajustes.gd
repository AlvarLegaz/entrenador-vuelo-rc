class_name PantallaAjustes
extends Control
## Ajustes (#pAjustes de simulador/simulador.html): menu a la izquierda (Controles, Graficos, Sonido, Dificultad,
## Registro y aula) y el panel elegido a la derecha. Lo unico que no esta en la web es la direccion del servidor del
## aula (en la web es la de la propia pagina).

var p: Node
var d: Dictionary
var menu: VBoxContainer
var paneles := {}
var botones := {}
# controles
var t_mando: RichTextLabel; var o_gas: OptionButton; var s_expo: HSlider; var t_expo: Label; var o_perfil: OptionButton
var asist: PanelContainer; var asist_rt: RichTextLabel; var b_asist_no: Button; var aviso: Label
var monitor: GridContainer; var mon := {}
# graficos, sonido, dificultad, datos
var o_calidad: OptionButton; var t_calidad: Label; var o_zoom: OptionButton
var c_sonido: CheckBox; var s_vol: HSlider; var t_vol: Label
var o_dif: OptionButton; var t_dif: Label
var c_cn: CheckBox; var t_aula: Label; var e_url: LineEdit; var t_url: Label; var b_profesor: Button

const ZOOMS := [0.0, 0.03, 0.05, 0.1, 0.15, 0.22]

func _init(p_: Node) -> void:
	p = p_; set_anchors_preset(Control.PRESET_FULL_RECT)
	d = Tema.pantalla("Ajustes", "Se guardan en este ordenador."); add_child(d["raiz"])
	d["botones"].add_child(Tema.boton("← Inicio", "", func(): p.ir_inicio()))
	var g := HBoxContainer.new(); g.add_theme_constant_override("separation", 16); d["cuerpo"].add_child(g)
	menu = VBoxContainer.new(); menu.custom_minimum_size.x = 220; menu.add_theme_constant_override("separation", 2); g.add_child(menu)
	var der := VBoxContainer.new(); der.size_flags_horizontal = Control.SIZE_EXPAND_FILL; g.add_child(Tema.desplazable(der))
	for par in [["controles", "Controles"], ["graficos", "Gráficos"], ["sonido", "Sonido"], ["dificultad", "Dificultad"], ["datos", "Registro y aula"]]:
		var b := Tema.boton(par[1], "BotonPlano", func(): seleccionar(par[0])); b.alignment = HORIZONTAL_ALIGNMENT_LEFT; menu.add_child(b); botones[par[0]] = b
		var cp := Tema.capa(8); der.add_child(cp[0]); paneles[par[0]] = cp
	_controles(paneles["controles"][1]); _graficos(paneles["graficos"][1]); _sonido(paneles["sonido"][1])
	_dificultad(paneles["dificultad"][1]); _datos(paneles["datos"][1])
	seleccionar("controles")

func seleccionar(a: String) -> void:
	for k in paneles: paneles[k][0].visible = k == a; botones[k].theme_type_variation = "BotonPlanoSel" if k == a else "BotonPlano"

# ---------------------------------------------------------------- controles
func _controles(c: VBoxContainer) -> void:
	c.add_child(Tema.h2("Mando o emisora por USB"))
	t_mando = Tema.rico("", 14); c.add_child(t_mando)
	o_gas = Tema.desplegable(["Palanca con muelle (mando de consola): arriba sube el gas, abajo lo baja", "Palanca sin muelle (emisora RC): la posición es el gas"])
	o_gas.item_selected.connect(func(i): p.mando_cfg.gas = "incremental" if i == 0 else "absoluto"; p.mando_cfg.guardar())
	c.add_child(Tema.fila("Gas", o_gas))
	s_expo = Tema.deslizador(0, 100, 5, 60); s_expo.size_flags_horizontal = Control.SIZE_FILL; s_expo.custom_minimum_size.x = 320
	t_expo = Tema.etiqueta("", 14, Tema.TEXTO, true)
	var fe := HBoxContainer.new(); fe.add_theme_constant_override("separation", 12); fe.add_child(s_expo); fe.add_child(t_expo)
	s_expo.value_changed.connect(func(x): p.mando_cfg.expo = x / 100.0; p.mando_cfg.guardar(); t_expo.text = _texto_expo())
	c.add_child(Tema.fila("Exponencial", fe))
	o_perfil = Tema.desplegable(["Mando de consola (Xbox, PlayStation…)", "Emisora RC, canales AETR (EdgeTX, OpenTX, RadioMaster, FrSky, Jumper)",
								 "Emisora RC, canales TAER (Spektrum, Futaba)", "Asignado con el asistente"])
	o_perfil.item_selected.connect(func(i):
		var perf: String = ["consola", "aetr", "taer", "propio"][i]
		if perf == "propio" and not p.mando_cfg.asist.has("nuevos"): _empezar_asistente()
		else: p.mando_cfg.poner_perfil(perf)
		refrescar())
	c.add_child(Tema.fila("Orden de los ejes", o_perfil))
	var fa := HBoxContainer.new(); fa.add_theme_constant_override("separation", 12)
	fa.add_child(Tema.boton("Asignar las palancas moviéndolas…", "", _empezar_asistente))
	var la := Tema.sub("Detecta qué eje es cada palanca y en qué sentido va. Sirve para cualquier emisora.", 13); la.size_flags_horizontal = Control.SIZE_EXPAND_FILL; fa.add_child(la)
	c.add_child(Tema.fila("", fa))
	asist = PanelContainer.new(); asist.add_theme_stylebox_override("panel", Tema.caja(Color(1, 0.78, 0.24, 0.08), Tema.ACENTO, 10, 1, 14, 12))
	var av := VBoxContainer.new(); av.add_theme_constant_override("separation", 8); asist.add_child(av)
	asist_rt = Tema.rico("", 15); av.add_child(asist_rt)
	b_asist_no = Tema.boton("Cancelar", "", func(): p.mando_cfg.asist["activo"] = false; asist.visible = false)
	b_asist_no.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN; av.add_child(b_asist_no); asist.visible = false; c.add_child(asist)
	aviso = Tema.etiqueta("", 13, Tema.NARANJA, false, true); c.add_child(aviso)
	monitor = GridContainer.new(); monitor.columns = 4; monitor.add_theme_constant_override("h_separation", 10); monitor.add_theme_constant_override("v_separation", 6)
	for par in MandoCfg.PALANCAS:
		var k: String = par[0]
		var nom := Tema.etiqueta(par[1], 13, Tema.SUAVE); nom.custom_minimum_size.x = 230
		var barra := Panel.new(); barra.custom_minimum_size = Vector2(200, 12); barra.size_flags_horizontal = Control.SIZE_EXPAND_FILL; barra.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		barra.add_theme_stylebox_override("panel", Tema.caja(Color(1, 1, 1, 0.08), Color(0, 0, 0, 0), 6))
		var med := ColorRect.new(); med.color = Color(1, 1, 1, 0.35); med.anchor_left = 0.5; med.anchor_right = 0.5; med.anchor_bottom = 1; med.offset_right = 1; barra.add_child(med)
		var rel := ColorRect.new(); rel.color = Tema.ACENTO; rel.anchor_bottom = 1; barra.add_child(rel)
		var eje := Tema.etiqueta("", 13, Tema.SUAVE); eje.custom_minimum_size.x = 52
		var inv := Tema.casilla("invertir", false)
		inv.toggled.connect(func(x):
			if _pintando: return
			var base = MandoCfg.PERFILES.get(p.mando_cfg.perfil, {}).get(k)
			var s_base: int = base[1] if base != null else 1
			p.mando_cfg.ejes[k]["s"] = -s_base if x else s_base; p.mando_cfg.guardar())
		for w in [nom, barra, eje, inv]: monitor.add_child(w)
		mon[k] = { "barra": barra, "rel": rel, "eje": eje, "inv": inv }
	c.add_child(Tema.margen(monitor, 0, 10, 0, 4))
	c.add_child(Tema.sub("Modo 2: palanca derecha profundidad (hacia ti, morro arriba) y alerones o timón; palanca izquierda gas (y guiñada en el cuadricóptero). En el monitor, la barra va a la derecha al subir el gas, al mover a la derecha y al empujar la palanca de profundidad; si alguna va al revés, marca «invertir». Botones del mando de consola: A lanzar · B cortar gas · Y cámara · X empezar de nuevo · cruceta compensador · Start pausa.", 13))
	c.add_child(Tema.margen(Tema.h2("Teclado"), 0, 18, 0, 0))
	var teclas := [["↓ ↑", "Profundidad: ↓ tira (morro arriba), ↑ empuja"], ["← →", "Timón o alerones"],
				   ["A D", "Timón en los aviones de 4 canales (alerones y timón, como el Poli-1); guiñada en el cuadricóptero"],
				   ["W S", "Gases más / menos · Espacio cortar gases"], ["L", "Lanzar a mano · R empezar de nuevo"], ["1 2 3", "Cámara piloto / persecución / a bordo"],
				   ["[ ]", "Compensador de profundidad"], ["H I", "Datos de vuelo en texto · instrumentos sí/no"], ["Esc", "Pausa"],
				   ["L M", "Dron FPV: armar / desarmar (con el gas abajo) · modo ANGLE / HORIZON / ACRO; W / S son el gas, que se queda donde lo dejas"]]
	var tv := VBoxContainer.new(); tv.add_theme_constant_override("separation", 0)
	for t in teclas:
		var h := HBoxContainer.new(); h.add_theme_constant_override("separation", 10)
		var kb := HBoxContainer.new(); kb.add_theme_constant_override("separation", 4); kb.custom_minimum_size.x = 135
		for tecla in String(t[0]).split(" "):
			var kp := PanelContainer.new(); kp.add_theme_stylebox_override("panel", Tema.caja(Color(1, 1, 1, 0.12), Color(0, 0, 0, 0), 5, 0, 7, 1))
			kp.add_child(Tema.etiqueta(tecla, 13)); kb.add_child(kp)
		h.add_child(kb); var l := Tema.etiqueta(t[1], 14, Tema.TEXTO, false, true); l.size_flags_horizontal = Control.SIZE_EXPAND_FILL; h.add_child(l)
		tv.add_child(Tema.margen(h, 8, 6, 8, 6)); tv.add_child(Tema.linea())
	c.add_child(tv)

func _empezar_asistente() -> void:
	var dev := MandoCfg.conectado()
	if dev < 0: aviso.text = "Conecta la emisora por USB y mueve una palanca para que la vea el simulador."; return
	p.mando_cfg.empezar_asistente(dev); asist.visible = true; b_asist_no.text = "Cancelar"

var _pintando := false
func _process(_dt: float) -> void:
	if not is_visible_in_tree(): return
	var dev := MandoCfg.conectado(); var M: MandoCfg = p.mando_cfg
	t_mando.text = ("[color=#8be08f][b]Mando conectado:[/b][/color] %s" % Input.get_joy_name(dev)) if dev >= 0 else "Sin mando: se vuela con el teclado. Conecta un mando (o una emisora RC por USB) y pulsa cualquier botón."
	aviso.text = M.aviso(dev) if dev >= 0 else aviso.text
	aviso.visible = aviso.text != ""
	monitor.modulate.a = 1.0 if dev >= 0 else 0.45
	for par in MandoCfg.PALANCAS:
		var k: String = par[0]; var m: Dictionary = mon[k]
		m["eje"].text = "eje %d" % int(M.ejes[k]["i"])
		if dev >= 0:
			var vv := M.eje(dev, k); var dd: float = -vv if (k == "ly" or k == "ry") else vv
			var W: float = m["barra"].size.x
			m["rel"].position.x = W * (0.5 + 0.5 * minf(0, dd)); m["rel"].size.x = W * 0.5 * absf(dd)
	if M.asist["activo"] and dev >= 0:
		if M.paso_asistente(dev):
			asist_rt.text = "[b][color=#ffc83d]Listo.[/color][/b] Comprueba en el monitor que cada barra va hacia la derecha al subir el gas, mover a la derecha y empujar la profundidad." + \
				(" Si es una emisora, elige arriba [b][color=#ffc83d]Gas: palanca sin muelle[/color][/b]." if M.gas == "incremental" else "")
			b_asist_no.text = "Cerrar"; refrescar()
		else: asist_rt.text = M.texto_asistente()

# ---------------------------------------------------------------- graficos
func _graficos(c: VBoxContainer) -> void:
	c.add_child(Tema.h2("Calidad gráfica"))
	o_calidad = Tema.desplegable(["Automática: alta, y baja sola si no llega a 35 fps", "Alta: sombras, agua con reflejos, vegetación lejana", "Media: sin vegetación lejana ni reflejos", "Baja: tres cuartos de resolución, sin matas ni nubes"])
	o_calidad.item_selected.connect(func(i): p.aj["calidad_modo"] = ["auto", "2", "1", "0"][i]; p.guardar_ajustes(); refrescar())
	c.add_child(Tema.fila("Calidad", o_calidad))
	t_calidad = Tema.sub("", 13); c.add_child(t_calidad)
	c.add_child(Tema.margen(Tema.h2("Cámara del piloto"), 0, 18, 0, 0))
	o_zoom = Tema.desplegable(["Sin zoom: como lo ve el ojo (el avión se hace pequeño al alejarse)", "Por defecto: la envergadura ocupa un 3 % de la pantalla", "Poco: un 5 % de la pantalla", "Medio: un 10 % de la pantalla",
							   "Mucho: un 15 % de la pantalla", "Máximo: un 22 % de la pantalla", "Ajustado con la rueda del ratón"])
	o_zoom.set_item_disabled(6, true)
	o_zoom.item_selected.connect(func(i): if i < 6: p.poner_zoom_piloto(ZOOMS[i]))
	c.add_child(Tema.fila("Zoom automático", o_zoom))
	c.add_child(Tema.sub("Con zoom, el campo de visión se cierra al alejarse el avión para que se vea siempre del mismo tamaño (hasta un teleobjetivo de 1,5°). En vuelo, con la cámara del piloto, la rueda del ratón lo ajusta.", 13))

func _sonido(c: VBoxContainer) -> void:
	c.add_child(Tema.h2("Sonido"))
	c_sonido = Tema.casilla("motor, viento y aviso de pérdida", true); c_sonido.toggled.connect(func(x): p.sonido_on(x))
	c.add_child(Tema.fila("Sonido", c_sonido))
	s_vol = Tema.deslizador(0, 100, 5, 60); s_vol.size_flags_horizontal = Control.SIZE_FILL; s_vol.custom_minimum_size.x = 320
	t_vol = Tema.etiqueta("", 14, Tema.TEXTO, true)
	var f := HBoxContainer.new(); f.add_theme_constant_override("separation", 12); f.add_child(s_vol); f.add_child(t_vol)
	s_vol.value_changed.connect(func(x): p.sonido_volumen(x / 100.0); t_vol.text = "%d %%" % int(x))
	c.add_child(Tema.fila("Volumen", f))
	c.add_child(Tema.sub("En la cámara del piloto el motor suena más lejano cuanto más se aleja el avión, como en el campo.", 13))

func _dificultad(c: VBoxContainer) -> void:
	c.add_child(Tema.h2("Física"))
	o_dif = Tema.desplegable(["Real: como el avión de verdad (la más difícil)", "Fácil: la física sencilla"])
	o_dif.item_selected.connect(func(i): p.sesion["dificultad"] = "facil" if i == 1 else "real"; p.guardar_sesion(); refrescar())
	c.add_child(Tema.fila("Dificultad", o_dif))
	t_dif = Tema.sub("", 13); c.add_child(t_dif)

func _datos(c: VBoxContainer) -> void:
	c.add_child(Tema.h2("Caja negra"))
	c_cn = Tema.casilla("un CSV a 20 Hz de cada vuelo (también se puede guardar desde el resultado)", false)
	c_cn.toggled.connect(func(x): p.aj["cn_auto"] = x; p.guardar_ajustes())
	c.add_child(Tema.fila("Descarga automática", c_cn))
	c.add_child(Tema.margen(Tema.h2("Perfiles y registro de vuelos"), 0, 18, 0, 0))
	t_aula = Tema.sub("", 13); c.add_child(t_aula)
	e_url = LineEdit.new(); e_url.placeholder_text = "http://192.168.1.20:8000 (vacío: sin servidor)"; e_url.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var fu := HBoxContainer.new(); fu.add_theme_constant_override("separation", 10); fu.add_child(e_url)
	fu.add_child(Tema.boton("Conectar", "", func(): p.aula.url = e_url.text.strip_edges(); p.aula._guardar_cfg("servidor"); await p.reiniciar_aula(); refrescar()))
	c.add_child(Tema.fila("Servidor del aula", fu))
	t_url = Tema.sub("La dirección que muestra SERVIDOR_AULA.bat en el PC del profesor. El simulador se abre en cada ordenador; el aula guarda los perfiles online, los vuelos y las salas.", 13); c.add_child(t_url)
	var fb := HBoxContainer.new(); fb.add_theme_constant_override("separation", 12)
	fb.add_child(Tema.boton("Perfiles…", "", func(): p.ir_pilotos(func(): p.ir_ajustes("datos"))))
	b_profesor = Tema.boton("Panel del profesor", "", func(): if p.aula.url != "": OS.shell_open(p.aula.url.trim_suffix("/") + "/profesor.html"))
	fb.add_child(b_profesor); c.add_child(fb)

# ---------------------------------------------------------------- pintar
func refrescar() -> void:
	_pintando = true
	var M: MandoCfg = p.mando_cfg
	o_gas.selected = 0 if M.gas == "incremental" else 1
	s_expo.set_value_no_signal(round(M.expo * 100)); t_expo.text = _texto_expo()
	o_perfil.selected = ["consola", "aetr", "taer", "propio"].find(M.perfil)
	for par in MandoCfg.PALANCAS:
		var k: String = par[0]; var base = MandoCfg.PERFILES.get(M.perfil, {}).get(k)
		mon[k]["inv"].button_pressed = (int(M.ejes[k]["s"]) != int(base[1])) if base != null else int(M.ejes[k]["s"]) < 0
	var modo: String = p.aj.get("calidad_modo", "auto")
	o_calidad.selected = ["auto", "2", "1", "0"].find(modo)
	t_calidad.text = "Ahora: %s%s. La alta necesita una tarjeta gráfica decente; si el vuelo va a tirones, baja un nivel." % [["baja", "media", "alta"][p.calidad_actual()], " (automática)" if modo == "auto" else ""]
	var z: float = p.aj.get("zoom_piloto", 0.03); var iz := -1
	for i in ZOOMS.size():
		if absf(ZOOMS[i] - z) < 0.004: iz = i
	if iz < 0: o_zoom.set_item_text(6, "Ajustado con la rueda del ratón: un %d %% de la pantalla" % int(round(z * 100))); iz = 6
	o_zoom.selected = iz
	c_sonido.button_pressed = p.sonido.on if p.sonido else true
	s_vol.value = round((p.sonido.vol if p.sonido else 0.6) * 100); t_vol.text = "%d %%" % int(s_vol.value)
	o_dif.selected = 1 if p.sesion["dificultad"] == "facil" else 0
	t_dif.text = p.DIFICULTAD_INFO[p.sesion["dificultad"]]
	c_cn.button_pressed = p.aj.get("cn_auto", false)
	var A: Aula = p.aula
	t_aula.text = (("Registro local: los alumnos y los vuelos se guardan en este ordenador (y en un archivo, si lo eliges)." if A.modo == "local" else "Aula «%s»: los vuelos se guardan en el servidor." % A.nombre_aula)
				   if A.activo else "Sin aula ni registro: los vuelos no se guardan. Desde «Perfil» puedes usar los perfiles locales.")
	if not e_url.has_focus(): e_url.text = A.url
	b_profesor.disabled = A.url == "" or A.modo == "local"
	_pintando = false

func _texto_expo() -> String:
	var M: MandoCfg = p.mando_cfg
	return "%d %% · a media palanca, el %d %% del recorrido" % [int(round(M.expo * 100)), int(round(M.media_palanca() * 100))]
