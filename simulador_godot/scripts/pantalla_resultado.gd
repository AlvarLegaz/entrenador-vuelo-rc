class_name PantallaResultado
extends RefCounted
## Resultado (#pResultado) y progreso (#pProgreso) de simulador_web/simulador.html.

static func fmt_min(s: float) -> String: return "%d:%02d" % [int(s / 60), int(round(fmod(s, 60)))]

## Insignia de un logro (ala_fija, dron, operaciones o robot), en color si esta conseguido y en gris si no; el robot
## bloqueado lleva un candado. El mismo SVG que insigniaSvg de la web.
static func insignia(id: String, ok: bool) -> String:
	var COL := { "ala_fija": ["#1e88e5", "#1565c0"], "dron": ["#43a047", "#2e7d32"], "operaciones": ["#ef6c00", "#bf360c"], "robot": ["#8e24aa", "#5e35b1"] }
	var c1: String = COL[id][0] if ok else "#38424d"; var c2: String = COL[id][1] if ok else "#29313a"
	var b := "#ffd54f" if ok else "#5d6875"; var s := "#ffffff" if ok else "#8a96a3"
	var forma: String = {
		"ala_fija": '<circle cx="60" cy="50" r="42" fill="%s" stroke="%s" stroke-width="5"/><circle cx="60" cy="50" r="33" fill="none" stroke="%s" stroke-opacity="0.6" stroke-width="1.5"/>' % [c1, b, b],
		"dron": '<path d="M60 6L98 28L98 72L60 94L22 72L22 28z" fill="%s" stroke="%s" stroke-width="5"/><path d="M60 16L89 33L89 67L60 84L31 67L31 33z" fill="none" stroke="%s" stroke-opacity="0.6" stroke-width="1.5"/>' % [c1, b, b],
		"operaciones": '<path d="M60 6L98 18V48C98 72 81 88 60 96C39 88 22 72 22 48V18z" fill="%s" stroke="%s" stroke-width="5"/><path d="M60 15L90 25V48C90 67 77 80 60 87C43 80 30 67 30 48V25z" fill="none" stroke="%s" stroke-opacity="0.6" stroke-width="1.5"/>' % [c1, b, b],
		"robot": '<path d="M60 4L68 19L84 13L82 30L98 34L87 46L98 58L82 62L84 79L68 73L60 88L52 73L36 79L38 62L22 58L33 46L22 34L38 30L36 13L52 19z" fill="%s" stroke="%s" stroke-width="4" stroke-linejoin="round"/><circle cx="60" cy="46" r="28" fill="none" stroke="%s" stroke-opacity="0.6" stroke-width="1.5"/>' % [c1, b, b],
	}[id]
	var simbolo: String = {
		"ala_fija": '<path d="M60 22L64 40L86 48V54L64 50L63 66L71 72V76L60 73L49 76V72L57 66L56 50L34 54V48L56 40z" fill="%s"/>' % s,
		"dron": '<path d="M44 34L76 66M76 34L44 66" stroke="%s" stroke-width="4" stroke-linecap="round"/><g fill="none" stroke="%s" stroke-width="3"><circle cx="44" cy="34" r="9"/><circle cx="76" cy="34" r="9"/><circle cx="44" cy="66" r="9"/><circle cx="76" cy="66" r="9"/></g><rect x="53" y="43" width="14" height="14" rx="3" fill="%s"/>' % [s, s, s],
		"operaciones": '<circle cx="60" cy="48" r="17" fill="none" stroke="%s" stroke-width="4"/><path d="M60 22V36M60 60V74M34 48H48M72 48H86" stroke="%s" stroke-width="4" stroke-linecap="round"/><circle cx="60" cy="48" r="5" fill="%s"/>' % [s, s, s],
		"robot": ('<rect x="45" y="27" width="30" height="19" rx="4" fill="%s"/><rect x="62" y="32" width="9" height="5" fill="%s"/><path d="M45 33H36" stroke="%s" stroke-width="4" stroke-linecap="round"/><path d="M52 46L46 57L51 68M68 46L74 57L69 68" fill="none" stroke="%s" stroke-width="5" stroke-linecap="round" stroke-linejoin="round"/><path d="M45 68H56M64 68H75" stroke="%s" stroke-width="4" stroke-linecap="round"/>' % [s, c1, s, s, s]) if ok
			else '<path d="M50 36C50 26 70 26 70 36C70 44 60 44 60 52V55" fill="none" stroke="%s" stroke-width="6" stroke-linecap="round"/><circle cx="60" cy="66" r="4" fill="%s"/>' % [s, s],     # bloqueado: un misterio
	}[id]
	var cintas := '<path d="M40 74L30 114L45 106L53 118L60 84z" fill="%s"/><path d="M80 74L90 114L75 106L67 118L60 84z" fill="%s"/>' % [c2, c2]
	var candado := '<g transform="translate(86 84)"><path d="M-6 -6V-11A6 6 0 0 1 6 -11V-6" fill="none" stroke="#ffd54f" stroke-width="3.5"/><rect x="-11" y="-6" width="22" height="18" rx="3" fill="#ffd54f"/><circle cx="0" cy="3" r="3" fill="#29313a"/></g>' if (id == "robot" and not ok) else ""
	return '<svg viewBox="0 0 120 120" width="120" height="120" xmlns="http://www.w3.org/2000/svg">' + cintas + forma + simbolo + candado + '</svg>'

## Los avisos de lo conseguido con el ultimo vuelo (logrosNuevos de la web).
static func logros_nuevos(antes, ahora) -> Array:
	var ya := []; var T := []
	if antes is Dictionary:
		for x in antes.get("logros", []): if x.get("ok", false): ya.append(x["id"])
	if ahora is Dictionary:
		for x in ahora.get("logros", []): if x.get("ok", false) and not ya.has(x["id"]): T.append("🏅 ¡Logro conseguido: %s!" % x["nombre"])
		if ahora.get("robot", false) and not (antes is Dictionary and antes.get("robot", false)): T.append("🔓 ¡Vehículo secreto desbloqueado! Te espera en el Hangar")
	return T

## Nombre corto de un escenario (sin el "1 · " de los entrenamientos del certificado).
static func nombre_corto(k: String) -> String:
	var nm := String(Escenarios.datos().get(k, { "nombre": k })["nombre"])
	return nm.substr(4) if (nm.length() > 4 and nm.substr(1, 3) == " · " and nm.substr(0, 1).is_valid_int()) else nm

## Las tarjetas de los tres logros y la del robot (htmlLogros de la web).
static func logros(g: Dictionary, p: Node) -> GridAdaptable:
	var rej := Tema.rejilla(230, 12); var L: Array = g.get("logros", [])
	var barra := func(a: float, b: float) -> Panel:
		var fondo := Panel.new(); fondo.custom_minimum_size.y = 8; fondo.add_theme_stylebox_override("panel", Tema.caja(Color(0, 0, 0, 0.4), Tema.BORDE, 4))
		var r := ColorRect.new(); r.color = Tema.ACENTO; r.anchor_bottom = 1; r.anchor_right = clampf(a / b, 0, 1) if b > 0 else 0.0; r.offset_left = 1; r.offset_top = 1; r.offset_bottom = -1
		fondo.add_child(r); return fondo
	var linea := func(a: String, b: String) -> HBoxContainer:
		var h := HBoxContainer.new(); var l := Tema.etiqueta(a, 12); l.size_flags_horizontal = Control.SIZE_EXPAND_FILL; h.add_child(l); h.add_child(Tema.etiqueta(b, 12, Tema.TEXTO, true)); return h
	var tarjeta := func(id: String, ok: bool, nombre: String, desc: String) -> VBoxContainer:
		var pc := PanelContainer.new(); pc.add_theme_stylebox_override("panel", Tema.caja(Color(1, 1, 1, 0.05), Color("#ffd54f8c") if ok else Color(1, 1, 1, 0.12), 14, 1, 14, 14))
		var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 6); pc.add_child(v)
		var ic := TextureRect.new(); ic.texture = Tema.svg(insignia(id, ok), 2.0); ic.custom_minimum_size = Vector2(104, 104)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED; v.add_child(ic)
		var t := Tema.etiqueta(nombre, 16, Tema.TEXTO, true, true); t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; v.add_child(t)
		var d := Tema.etiqueta(desc, 13, Tema.SUAVE, false, true); d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; v.add_child(d)
		rej.add_child(pc); return v
	for x in L:
		var v: VBoxContainer = tarjeta.call(String(x["id"]), bool(x["ok"]), String(x["nombre"]), String(x["desc"]))
		if x.has("horas_meta"):
			v.add_child(linea.call("Horas de vuelo", "%s de %s h" % [PantallaPilotos.fmt_horas(minf(float(x["horas"]), float(x["horas_meta"]))), str(int(x["horas_meta"]))]))
			v.add_child(barra.call(float(x["horas"]), float(x["horas_meta"])))
		v.add_child(linea.call("Operaciones" if x["id"] == "operaciones" else "Entrenamientos", "%d de %d" % [int(x["hechas"]), int(x["total"])]))
		v.add_child(barra.call(float(x["hechas"]), float(x["total"])))
		if x["ok"]:
			var e := Tema.etiqueta("✓ Conseguido", 13, Color("#ffd54f"), true); e.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; v.add_child(e)
		elif not (x["pendientes"] as Array).is_empty():
			v.add_child(Tema.etiqueta("Te falta: " + ", ".join((x["pendientes"] as Array).map(func(k): return nombre_corto(String(k)))), 12, Tema.SUAVE, false, true))
	var n := L.filter(func(x): return x["ok"]).size(); var rb := bool(g.get("robot", false))
	var v: VBoxContainer = tarjeta.call("robot", rb, "Vehículo secreto",                # sin decir que es: un misterio hasta desbloquearlo
		"Desbloqueado: te espera en el Hangar." if rb else "¿Qué se esconde en el Hangar? Consigue los tres logros para descubrirlo.")
	v.add_child(linea.call("Logros", "%d de %d" % [n, L.size()])); v.add_child(barra.call(n, L.size()))
	if rb:
		var e := Tema.etiqueta("✓ Desbloqueado", 13, Color("#ffd54f"), true); e.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; v.add_child(e)
	return rej

## Estadisticas (.estadisticas): rejilla de cajas con cifra grande y nombre.
static func estadisticas(cajas: Array) -> GridAdaptable:
	var g := Tema.rejilla(150, 10)
	for q in cajas:
		var pc := PanelContainer.new(); pc.add_theme_stylebox_override("panel", Tema.caja(Tema.PANEL, Tema.BORDE, 12, 1, 14, 12))
		var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 2); pc.add_child(v)
		v.add_child(Tema.etiqueta(String(q[0]), 26, Tema.TEXTO, true))
		var s := Tema.etiqueta(String(q[1]).to_upper(), 12, Tema.SUAVE, false, true); v.add_child(s)
		g.add_child(pc)
	return g


## Traza del vuelo: planta coloreada por altura (azul bajo, amarillo alto) y perfil de altura (pintarResumen).
class Traza extends Control:
	var p: Node
	var filas := []
	var final := ""
	var casa := { "N": 0.0, "E": 0.0 }
	func _init(p_: Node) -> void:
		p = p_; custom_minimum_size = Vector2(400, 300); size_flags_horizontal = Control.SIZE_EXPAND_FILL
	func _draw() -> void:
		var W := size.x; var H := size.y
		draw_style_box(Tema.caja(Color("#0b0f14"), Color(0, 0, 0, 0), 10), Rect2(Vector2.ZERO, size))
		if filas.size() < 2: return
		var f: Font = Tema.fuente; var fb: Font = Tema.negrita
		var hs := []; var ns := []; var es := []; var ds := []
		for r in filas: hs.append(r[3]); ns.append(r[1] - casa["N"]); es.append(r[2] - casa["E"])
		for i in ns.size(): ds.append(Vector2(ns[i], es[i]).length())
		var S := H; var semi: float = maxf(60, ds.max()) * 1.15; var k := (S - 30) / (2 * semi)
		var X := func(e: float) -> float: return S / 2 + e * k
		var Y := func(n: float) -> float: return S / 2 - n * k
		var hmax: float = maxf(1, hs.max())
		var color := func(h: float) -> Color: return Color.from_hsv((210 - 160 * minf(1, maxf(0, h) / hmax)) / 360.0, 0.9 * 0.85, 0.95)
		for r in [50, 100, 200, 500, 1000, 2000, 5000]:
			if r < semi and r * k > 18:
				draw_arc(Vector2(X.call(0), Y.call(0)), r * k, 0, TAU, 64, Color(1, 1, 1, 0.12), 1, true)
				draw_string(f, Vector2(X.call(0) + r * k * 0.71 + 3, Y.call(0) - r * k * 0.71 - 2), ("%d km" % (r / 1000)) if r >= 1000 else ("%d m" % r), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.4))
		if not p.en_mundo():
			var P: Dictionary = p.ent.pista
			var rr := Rect2(X.call(-P["ancho"] / 2), Y.call(P["n1"]), P["ancho"] * k, (P["n1"] - P["n0"]) * k)
			draw_rect(rr, Color("#777777"))
			var pil: Array = p.ent.circuito["pilones"]
			for i in pil.size(): draw_circle(Vector2(X.call(pil[i][1]), Y.call(pil[i][0])), 3.5, Color(p.ent.circuito["colores"][i]["hex"]))
		for i in range(1, filas.size()):
			draw_line(Vector2(X.call(es[i - 1]), Y.call(ns[i - 1])), Vector2(X.call(es[i]), Y.call(ns[i])), color.call(hs[i]), 2, true)
		draw_circle(Vector2(X.call(0), Y.call(0)), 4, Color.WHITE)
		draw_string(fb, Vector2(8, 14), "N ↑", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#e6edf3"))
		draw_string(fb, Vector2(X.call(0) + 6, Y.call(0) + 12), "piloto", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#e6edf3"))
		draw_circle(Vector2(X.call(es[-1]), Y.call(ns[-1])), 4, Color("#ff5252") if final.begins_with("roto") else Color("#8be08f"))
		# perfil de altura
		var x0 := S + 44; var x1 := W - 14; var y0 := H - 26; var y1 := 18.0; var T: float = maxf(0.1, filas[-1][0])
		draw_polyline(PackedVector2Array([Vector2(x0, y1), Vector2(x0, y0), Vector2(x1, y0)]), Color(1, 1, 1, 0.25), 1)
		var c5 := Color(1, 1, 1, 0.5)
		draw_string(f, Vector2(x0 + 4, y1 + 10), "%d m" % int(round(hmax)), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, c5)
		draw_string(f, Vector2(x0 - 10, y0 + 4), "0", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, c5)
		draw_string(f, Vector2(x1 - 30, y0 + 14), PantallaResultado.fmt_min(T), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, c5)
		draw_string(f, Vector2(x0 + 4, y0 + 14), "altura · tiempo", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, c5)
		var pts := PackedVector2Array()
		for i in filas.size(): pts.append(Vector2(x0 + (x1 - x0) * filas[i][0] / T, y0 - (y0 - y1) * maxf(0, hs[i]) / hmax))
		draw_polyline(pts, Tema.ACENTO, 2, true)


## Pantalla del resultado.
class Resultado extends Control:
	var p: Node; var d: Dictionary
	var veredicto: Label; var t_final: Label; var stats: VBoxContainer; var traza: Traza; var objetivos: VBoxContainer; var guardado: Label
	var b_rep: Button; var b_otro: Button; var b_prog: Button; var b_cn: Button
	func _init(p_: Node) -> void:
		p = p_; set_anchors_preset(Control.PRESET_FULL_RECT)
		d = Tema.pantalla("", "", true); add_child(d["raiz"])
		veredicto = Tema.etiqueta("", 40, Tema.TEXTO, true); d["cabecera"].add_child(veredicto); d["cabecera"].move_child(veredicto, 1)
		t_final = d["subtitulo"]
		var g := HBoxContainer.new(); g.add_theme_constant_override("separation", 16); d["cuerpo"].add_child(g)
		var c1 := Tema.capa(10); (c1[0] as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL; g.add_child(c1[0])
		(c1[1] as VBoxContainer).add_child(Tema.h2("Resumen del vuelo"))
		stats = VBoxContainer.new(); (c1[1] as VBoxContainer).add_child(stats)
		traza = Traza.new(p); (c1[1] as VBoxContainer).add_child(traza)
		var c2 := Tema.capa(10); (c2[0] as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL; g.add_child(c2[0])
		(c2[1] as VBoxContainer).add_child(Tema.h2("Objetivos"))
		objetivos = VBoxContainer.new(); (c2[1] as VBoxContainer).add_child(objetivos)
		guardado = Tema.sub("", 13); (c2[1] as VBoxContainer).add_child(guardado)
		var pie: HBoxContainer = d["pie"]
		pie.add_child(Tema.boton("Volar otra vez", "BotonPrimGrande", func(): p.app_vuelo.empezar()))
		b_rep = Tema.boton("Ver la repetición", "", func(): p.app_repeticion.ver_repeticion()); pie.add_child(b_rep)
		b_otro = Tema.boton("Otro entrenamiento", "", func(): p.app_pantallas.ir_entrenamientos() if not Escenarios.libre(p.sesion["escenario"]) else p.app_pantallas.ir_volar()); pie.add_child(b_otro)
		b_prog = Tema.boton("Mi progreso", "", func(): p.app_pantallas.ir_progreso("pResultado")); pie.add_child(b_prog)
		b_cn = Tema.boton("Caja negra (CSV)", "", func(): p.app_resultado.guardar_csv_dialogo()); pie.add_child(b_cn)
		pie.add_child(Tema.espacio()); pie.add_child(Tema.boton("Menú principal", "", func(): p.app_pantallas.ir_inicio()))
	func pintar(v: Dictionary, r: Dictionary) -> void:
		var E: Dictionary = r["E"]; var libre: bool = r["libre"]
		d["titulo"].text = E["nombre"]
		veredicto.text = "Vuelo libre" if libre else r["resultado"]
		veredicto.add_theme_color_override("font_color", Tema.AZUL if libre else (Color("#66d36e") if r["apto"] else Color("#ff6e66")))
		var fin: String
		var final: String = v["final"]
		if v.has("lanzamiento"): fin = "Lanzamiento fallido%s: %s" % [" (se ha roto)" if final.begins_with("roto") else "", v["lanzamiento"]["texto"]]
		elif final == "aterrizado": fin = "Aterrizaje correcto"
		elif final.begins_with("roto"): fin = "Accidente: " + final.substr(6, final.length() - 7)
		elif final == "fuera de límites": fin = "Fuera de límites: a más de %d m el avión ya no se ve" % int(p.ent.limites.get("distancia_m", 650))
		else: fin = "Vuelo terminado sin aterrizar"
		var vueltas: String = "" if E.has("mundo") else (" · " + p.app_resultado.texto_vueltas_plano())
		t_final.text = "%s · tiempo de vuelo %.1f min%s" % [fin, v["tVuelo"] / 60.0, vueltas]; t_final.visible = true
		for x in objetivos.get_children(): x.queue_free()
		if (r["objs"] as Array).is_empty(): objetivos.add_child(Tema.etiqueta("Sin objetivos: el tiempo cuenta para las horas de entrenamiento.", 14, Tema.TEXTO, false, true))
		for o in r["objs"]:
			var h := HBoxContainer.new(); h.add_theme_constant_override("separation", 10)
			var ic := Tema.etiqueta("✓" if o["ok"] else "✘", 14, Color("#8be08f") if o["ok"] else Color("#ff8a80")); ic.custom_minimum_size.x = 20; h.add_child(ic)
			var t := Tema.etiqueta(o["texto"], 14, Tema.TEXTO, false, true); t.size_flags_horizontal = Control.SIZE_EXPAND_FILL; h.add_child(t)
			objetivos.add_child(Tema.margen(h, 8, 6, 8, 6)); objetivos.add_child(Tema.linea())
		b_prog.visible = p.sesion["alumno"] != null
		b_otro.text = "Otro vuelo" if libre else "Otro entrenamiento"
		b_cn.disabled = false
		# resumen
		var f: Array = v["filas"]
		for x in stats.get_children(): x.queue_free()
		b_rep.disabled = f.size() < 2
		traza.filas = f; traza.final = final; traza.casa = p.casa; traza.queue_redraw()
		if f.size() < 2: return
		var hs := f.map(func(x): return x[3]); var vs := f.map(func(x): return x[4]); var gs := f.map(func(x): return x[12])
		var ds := f.map(func(x): return Vector2(x[1] - p.casa["N"], x[2] - p.casa["E"]).length())
		var toma := ("%.1f m/s" % maxf(0, -f[-1][6])) if final == "aterrizado" else "—"
		stats.add_child(PantallaResultado.estadisticas([[PantallaResultado.fmt_min(v["tVuelo"]), "tiempo de vuelo"], ["%d m" % int(round(v.get("hmax", 0))), "altura máxima"],
			["%.1f m/s" % vs.max(), "velocidad máxima"], ["%d m" % int(round(ds.max())), "distancia máxima"], ["%.1f g" % gs.max(), "carga máxima"], [toma, "descenso en la toma"]]))


## Progreso del piloto (irProgreso).
class Progreso extends Control:
	var p: Node; var d: Dictionary; var cont: VBoxContainer; var desde := "pHangar"; var alumno = null; var b_cerrar: Button
	func _init(p_: Node) -> void:
		p = p_; set_anchors_preset(Control.PRESET_FULL_RECT)
		d = Tema.pantalla("", "Progreso del entrenamiento"); add_child(d["raiz"])
		b_cerrar = Tema.boton("Cerrar sesión", "", func(): p.app_pantallas.cerrar_sesion()); d["botones"].add_child(b_cerrar)
		d["botones"].add_child(Tema.boton("← Volver", "", func(): p.mostrar("pResultado") if desde == "pResultado" else p.app_pantallas.ir_inicio() if desde == "pInicio" else p.app_pantallas.ir_hangar()))
		cont = VBoxContainer.new(); cont.add_theme_constant_override("separation", 12); d["cuerpo"].add_child(Tema.desplazable(cont))
	func cargar() -> void:
		d["titulo"].text = String(alumno["nombre"]); b_cerrar.visible = desde == "pInicio"
		for x in cont.get_children(): x.queue_free()
		cont.add_child(Tema.sub("Cargando…", 14))
		var r: Dictionary = await p.aula.api("GET", "alumnos/" + String(alumno["id"]))
		for x in cont.get_children(): x.queue_free()
		if not r["ok"]: cont.add_child(Tema.etiqueta("No se pudo leer el progreso: " + String(r["error"]), 14, Color("#ff8a80"))); return
		var a: Dictionary = r["datos"]; alumno["progreso"] = a["progreso"]
		var g: Dictionary = a["progreso"]; var pct := minf(100, 100 * g["horas"] / g["horas_minimas"]); var faltan := []
		if g["horas"] < g["horas_minimas"]: faltan.append(PantallaPilotos.fmt_horas(g["horas_minimas"] - g["horas"]) + " de vuelo")
		var E := Escenarios.datos(); var pend := []
		var cert := String(g.get("certificado", "Certificado de pilotaje")); var total := int(g.get("escenarios_total", (g["escenarios"] as Dictionary).size()))
		var nom_esc := func(k: String) -> String: return String(E.get(k, { "nombre": k })["nombre"])
		for k in g["escenarios"]:
			var nm: String = nom_esc.call(k)
			if nm.length() > 4 and nm.substr(1, 3) == " · " and nm.substr(0, 1).is_valid_int(): nm = nm.substr(4)
			if not g["escenarios"][k]["superado"]: pend.append(nm)
		if not pend.is_empty(): faltan.append("superar " + ", ".join(pend))
		cont.add_child(PantallaResultado.estadisticas([[PantallaPilotos.fmt_horas(g["horas"]), "horas de vuelo"], [str(int(g["vuelos"])), "vuelos"], [str(int(g["aterrizajes"])), "aterrizajes"],
			[str(int(g["accidentes"])), "accidentes"], ["%d/%d" % [int(g["escenarios_superados"]), total], "pruebas superadas"]]))
		cont.add_child(Tema.etiqueta("Logros", 20, Tema.TEXTO, true))
		cont.add_child(PantallaResultado.logros(g, p))
		cont.add_child(Tema.etiqueta("Carrera de drones del Politécnico", 20, Tema.TEXTO, true))
		var cc := Tema.capa(10); cont.add_child(cc[0]); var C = g.get("carrera")
		(cc[1] as VBoxContainer).add_child(Tema.rico(("🏁 Tu mejor tiempo: [font_size=20][b]%s[/b][/font_size]  con %s, el %s" % [Operacion.crono(C["mejor"]), Tema.bb(String(C.get("avion", ""))), String(C.get("fecha", "")).substr(0, 16).replace("T", " ")])
			if C is Dictionary else "🏁 Todavía no has terminado la carrera (Operaciones → Carrera de drones del Politécnico).", 15))
		cont.add_child(Tema.etiqueta("Camino al certificado: " + cert, 20, Tema.TEXTO, true))
		var c := Tema.capa(10); cont.add_child(c[0]); var cv: VBoxContainer = c[1]
		cv.add_child(Tema.etiqueta("%s de %d h mínimas" % [PantallaPilotos.fmt_horas(g["horas"]), int(g["horas_minimas"])], 14, Tema.TEXTO, true))
		var fondo := Panel.new(); fondo.custom_minimum_size.y = 14; fondo.add_theme_stylebox_override("panel", Tema.caja(Color(0, 0, 0, 0.4), Tema.BORDE, 7))
		var barra := ColorRect.new(); barra.color = Tema.ACENTO; barra.anchor_bottom = 1; barra.anchor_right = pct / 100.0; barra.offset_left = 1; barra.offset_top = 1; barra.offset_bottom = -1
		fondo.add_child(barra); cv.add_child(fondo)
		var t := VBoxContainer.new(); t.add_theme_constant_override("separation", 0)
		for k in g["escenarios"]:
			var s: Dictionary = g["escenarios"][k]; var h := HBoxContainer.new(); h.add_theme_constant_override("separation", 10)
			var ic := Tema.etiqueta("✓" if s["superado"] else "○", 14, Color("#8be08f") if s["superado"] else Color("#dddddd")); ic.custom_minimum_size.x = 20; h.add_child(ic)
			var n := Tema.etiqueta(nom_esc.call(k), 14); n.size_flags_horizontal = Control.SIZE_EXPAND_FILL; h.add_child(n)
			h.add_child(Tema.etiqueta("%d intentos" % int(s["intentos"]), 14, Tema.SUAVE))
			t.add_child(Tema.margen(h, 8, 6, 8, 6)); t.add_child(Tema.linea())
		cv.add_child(t)
		var estado := ""
		if a.get("habilitado", false): estado = "[bgcolor=#58d06a33][color=#9be59f] CONCEDIDO [/color][/bgcolor] %s desde %s." % [Tema.bb(cert), Tema.bb(String(a.get("habilitado_en", "")))]
		elif g["requisitos_cumplidos"]: estado = "[bgcolor=#ffffff1a] Requisitos cumplidos [/bgcolor] Pide al profesor que te conceda el certificado."
		else: estado = "[bgcolor=#ff6e6633][color=#ffb4ab] Todavía no [/color][/bgcolor] Te falta: %s." % " y ".join(faltan)
		cv.add_child(Tema.rico(estado, 15))
		cont.add_child(Tema.etiqueta("Historial", 20, Tema.TEXTO, true))
		var c2 := Tema.capa(0); cont.add_child(c2[0])
		var tabla := GridContainer.new(); tabla.columns = 7; tabla.add_theme_constant_override("h_separation", 16); tabla.add_theme_constant_override("v_separation", 8)
		for cab in ["Fecha", "Avión", "Entrenamiento", "Tiempo", "Objetivos", "Final", "Resultado"]: tabla.add_child(Tema.etiqueta(cab, 14, Tema.SUAVE))
		var vuelos: Array = a.get("vuelos", [])
		if vuelos.is_empty(): (c2[1] as VBoxContainer).add_child(Tema.etiqueta("Todavía no hay vuelos.", 14))
		for v in vuelos:
			var objs: Array = v.get("objetivos", [])
			var bien := objs.filter(func(o): return o.get("ok", false)).size()
			var res: String = v.get("resultado", "")
			for txt in [String(v["inicio"]).substr(0, 16).replace("T", " "), String(v["avion"]), String(v.get("escenario_nombre", v["escenario"])), "%.1f min" % (float(v["tiempo_vuelo_s"]) / 60),
						("%d/%d" % [bien, objs.size()]) if not objs.is_empty() else "—", String(v.get("final", "")), res]:
				var l := Tema.etiqueta(txt, 14, Color("#8be08f") if (txt == res and res == "APTO") else (Color("#ff8a80") if (txt == res and res == "NO APTO") else Tema.TEXTO))
				tabla.add_child(l)
		(c2[1] as VBoxContainer).add_child(tabla)
