class_name Capas
extends RefCounted
## Capas que van encima de todo, como en simulador_web/simulador.html (.velo): pausa (#pausa), carga (#carga) y la ventana
## de confirmar (#modal). Cada una es un Control a pantalla completa con el velo oscuro y su panel centrado.

static func _velo(alfa := 0.55) -> Control:
	var c := Control.new(); c.set_anchors_preset(Control.PRESET_FULL_RECT); c.mouse_filter = Control.MOUSE_FILTER_STOP
	var r := ColorRect.new(); r.color = Color(5 / 255.0, 10 / 255.0, 16 / 255.0, alfa); r.set_anchors_preset(Control.PRESET_FULL_RECT); r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(r)
	var cc := CenterContainer.new(); cc.set_anchors_preset(Control.PRESET_FULL_RECT); cc.mouse_filter = Control.MOUSE_FILTER_IGNORE; cc.name = "Centro"
	c.add_child(cc); c.visible = false
	return c

## Pausa: Continuar, Empezar de nuevo, Camara, Instrumentos, Controles, Terminar, Salir al menu y el sonido.
## Devuelve { raiz, camara, instr, sonido, info } (los botones se conectan en principal).
static func pausa(p: Node) -> Dictionary:
	var v := _velo()
	var cp := Tema.capa(8); var panel: PanelContainer = cp[0]; var caja: VBoxContainer = cp[1]
	panel.add_theme_stylebox_override("panel", Tema.caja(Tema.PANEL, Tema.BORDE, Tema.RADIO, 1, 26, 24)); panel.custom_minimum_size.x = 420
	v.get_node("Centro").add_child(panel)
	caja.add_child(Tema.etiqueta("Pausa", 22, Tema.TEXTO, true)); caja.add_child(Tema.margen(Control.new(), 0, 0, 0, 6))
	var b := func(texto: String, tipo: String, f: Callable) -> Button:
		var x := Tema.boton(texto, tipo, f); x.alignment = HORIZONTAL_ALIGNMENT_LEFT; caja.add_child(x); return x
	b.call("Continuar", "BotonPrim", func(): p.app_repeticion.poner_pausa(false))
	b.call("Empezar el vuelo de nuevo", "", func(): p.app_repeticion.poner_pausa(false); p.app_vuelo.reiniciar())
	var bc: Button = b.call("Cámara: piloto", "", func(): p.app_repeticion.cambiar_camara_pausa())
	var bi: Button = b.call("Instrumentos: sí", "", func(): p.app_repeticion.cambiar_instrumentos_pausa())
	b.call("Controles", "", func(): p.hud.ayuda.visible = not p.hud.ayuda.visible)
	b.call("Terminar el vuelo", "", func(): p.app_repeticion.terminar_desde_pausa())
	b.call("Salir al menú principal", "BotonPeligro", func(): p.app_repeticion.salir_al_menu())
	var f := HBoxContainer.new(); f.add_theme_constant_override("separation", 10)
	var cs := Tema.casilla("Sonido", true); cs.add_theme_color_override("font_color", Tema.SUAVE)
	cs.toggled.connect(func(x): p.app_avion_ajustes.sonido_on(x))
	var info := Tema.etiqueta("", 12, Tema.SUAVE); info.size_flags_horizontal = Control.SIZE_EXPAND_FILL; info.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	f.add_child(cs); f.add_child(info); caja.add_child(Tema.margen(f, 0, 6, 0, 0))
	return { "raiz": v, "camara": bc, "instr": bi, "sonido": cs, "info": info }

## Carga de los mundos reales: titulo, barra de progreso y texto del paso.
static func carga() -> Dictionary:
	var v := _velo(0.92)
	var caja := VBoxContainer.new(); caja.add_theme_constant_override("separation", 14); caja.alignment = BoxContainer.ALIGNMENT_CENTER
	v.get_node("Centro").add_child(caja)
	var t := Tema.etiqueta("Preparando el vuelo…", 22, Tema.TEXTO, true); t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; caja.add_child(t)
	var fondo := Panel.new(); fondo.custom_minimum_size = Vector2(360, 14); fondo.add_theme_stylebox_override("panel", Tema.caja(Color(0, 0, 0, 0.4), Tema.BORDE, 7))
	var barra := ColorRect.new(); barra.color = Tema.ACENTO; barra.position = Vector2(1, 1); barra.size = Vector2(0, 12); fondo.add_child(barra)
	caja.add_child(fondo)
	var tx := Tema.etiqueta("", 15, Tema.SUAVE); tx.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; caja.add_child(tx)
	return { "raiz": v, "titulo": t, "barra": barra, "texto": tx }

## Ventana de confirmar: titulo, texto (BBCode) y botones Cancelar / Si.
static func modal() -> Dictionary:
	var v := _velo()
	var cp := Tema.capa(8); var panel: PanelContainer = cp[0]; var caja: VBoxContainer = cp[1]
	panel.custom_minimum_size.x = 440; v.get_node("Centro").add_child(panel)
	var t := Tema.etiqueta("", 18, Tema.TEXTO, true); caja.add_child(t)
	var tx := Tema.rico("", 15); tx.custom_minimum_size.x = 400; caja.add_child(tx)
	var clave := LineEdit.new(); clave.secret = true; clave.max_length = 20; clave.visible = false; caja.add_child(clave)          # claves de los perfiles online
	var clave2 := LineEdit.new(); clave2.secret = true; clave2.max_length = 20; clave2.placeholder_text = "Repítela"; clave2.visible = false; caja.add_child(clave2)
	var bb := HBoxContainer.new(); bb.add_theme_constant_override("separation", 10); bb.alignment = BoxContainer.ALIGNMENT_END
	var no := Tema.boton("Cancelar"); var si := Tema.boton("Sí", "BotonPeligro"); bb.add_child(no); bb.add_child(si)
	caja.add_child(Tema.margen(bb, 0, 8, 0, 0))
	return { "raiz": v, "titulo": t, "texto": tx, "si": si, "no": no, "clave": clave, "clave2": clave2 }
