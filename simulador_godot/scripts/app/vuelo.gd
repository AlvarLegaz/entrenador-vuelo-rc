class_name AppVuelo
extends RefCounted
## Vuelo: empezar, reiniciar, lanzar, el paso de la simulacion (500 por segundo), el juego del bipode y el final del vuelo.
## Parte de principal.gd (como js/app/vuelo.js de la web): el estado esta en principal.gd (p).

var p: Principal

func _init(principal: Principal) -> void: p = principal

func _poner_mundo_3d(es_m: bool, titulo: String) -> void:
	var cal := p.app_avion_ajustes.calidad_actual()
	p.get_viewport().scaling_3d_scale = 1.0 if p.vr != null else (0.5 if p.app_avion_ajustes.minimo() else 1.0)          # rendimiento maximo: media resolucion en 3D (en las gafas, la suya)
	if es_m:
		if p.mundo3d != null and (p.mundo3d.calidad != cal or p.mundo3d.minimo != p.app_avion_ajustes.minimo()): p.mundo3d.queue_free(); p.mundo3d = null; await p.get_tree().process_frame
		if p.mundo3d == null:
			await p.app_pantallas.mostrar_carga(titulo, "Terreno, mar, carreteras y pueblos…", 0.3)
			p.mundo3d = Mundo3D.new(); p.mundo3d.calidad = cal; p.mundo3d.minimo = p.app_avion_ajustes.minimo(); p.add_child(p.mundo3d); p.mundo3d.construir(p.ent, p.mundo_datos, p.orto)
		_poner_vista(p.mundo3d)
		await p.app_pantallas.mostrar_carga(titulo, "Zonas de detalle: ortofoto, edificios y árboles…", 0.6)
		var c := p.app_evaluacion._casa(); var zs := []
		for meta in zonas_cerca(c["N"], c["E"]):
			if not p.zonas_cache.has(meta["id"]): p.zonas_cache[meta["id"]] = DatosComunes.cargar_zona(meta)
			if not (p.zonas_cache[meta["id"]] as Dictionary).is_empty(): zs.append(p.zonas_cache[meta["id"]])
		p.mundo3d.claro = Vector2(c["E"], c["N"])
		p.ent.poner_zonas(zs); p.mundo3d.poner_zonas(zs); p.mundo3d.poner_base(c["N"], c["E"])
		await p.app_pantallas.mostrar_carga(titulo, "Listo", 1.0)
	else:
		if p.campo3d != null and (p.campo3d.calidad != cal or p.campo3d.minimo != p.app_avion_ajustes.minimo()): p.campo3d.queue_free(); p.campo3d = null; await p.get_tree().process_frame
		if p.campo3d == null:
			p.campo3d = Campo3D.new(); p.campo3d.calidad = cal; p.campo3d.minimo = p.app_avion_ajustes.minimo(); p.add_child(p.campo3d); p.campo3d.construir(p.ent)
		_poner_vista(p.campo3d)
	if p.campo3d != null: p.campo3d.poner_pista_fpv({} if es_m else Escenarios.datos()[p.sesion["escenario"]].get("pista_fpv", {}))

func zonas_cerca(N: float, E: float) -> Array:
	var dist := func(z: Dictionary) -> float:
		return Vector2(maxf(maxf(z["N0"] - N, 0.0), N - z["N0"] - z["lado_m"]), maxf(maxf(z["E0"] - E, 0.0), E - z["E0"] - z["lado_m"])).length()
	var dentro := DatosComunes.zona_en(p.indice_zonas, p.MUNDO, N, E)
	var lista := p.indice_zonas.filter(func(z): return z["mundo"] == p.MUNDO and dist.call(z) <= p.RADIO_ZONAS)
	lista.sort_custom(func(a, b):
		var da: int = 0 if (not dentro.is_empty() and a["id"] == dentro["id"]) else 1; var db: int = 0 if (not dentro.is_empty() and b["id"] == dentro["id"]) else 1
		return da < db if da != db else dist.call(a) < dist.call(b))
	return lista

## Solo un mundo en el arbol a la vez (cada uno trae su cielo, su luz y su WorldEnvironment).
func _poner_vista(v: Node3D) -> void:
	for w in [p.mundo3d, p.campo3d]:
		if w != null and w != v and w.is_inside_tree(): p.remove_child(w)
	if v.get_parent() == null: p.add_child(v)
	p.vista = v
	p.cam.far = 16000.0 if v == p.mundo3d else 3000.0     # como el navegador (cam.far de visor.js)

func empezar() -> void:
	var E: Dictionary = Escenarios.datos()[p.sesion["escenario"]]; var es_m := E.has("mundo")
	p.sonido.iniciar()
	if es_m: await p.app_pantallas.mostrar_carga(p.mundo_datos["nombre"], "Avión y física…", 0.1)
	p.ent.poner_mundo(p.mundo_datos if es_m else {})
	if not es_m: p.ent.poner_zona({})
	p.modelo = p.app_avion_ajustes.crear_modelo(p.sesion["avion"])
	p.app_avion_ajustes.aplicar_cm(p.modelo); p.app_avion_ajustes.aplicar_calibracion(p.modelo); p.app_avion_ajustes.aplicar_dificultad(p.modelo)
	var A := DatosComunes.avion(p.sesion["avion"])
	if Desgaste.clase(A) != "": Desgaste.aplicar(p.modelo, Desgaste.estado(p.sesion["avion"]))    # sus averias y el desgaste de la bateria
	if p.avion3d: p.avion3d.queue_free()
	p.avion3d = Avion3D.new(p.app_evaluacion.datos_visor(p.sesion["avion"])); p.add_child(p.avion3d)
	if p.app_evaluacion.morro_de(p.sesion["avion"]) == "orientable": p.modelo.configurar({ "masa_kg": p.modelo.masa_kg + float(A["camara"].get("masa_orientable_kg", 0.0)) })   # la torreta pesa
	_texto_ayuda(A)
	p.hud_dji.b_briefing.visible = E.has("operacion"); ver_briefing(false)   # trabajos: el briefing a mano (B)
	# el dron se vuela mirando la pantalla de la app (su camara); al volver a un avion, vista del piloto
	if p.es_dron() != p.era_dron: p.camara = 3 if p.es_dron() else 1
	p.era_dron = p.es_dron()
	if p.es_bipode(): p.camara = 2                    # el bipode se maneja desde detras
	if p.es_dron() and not p.es_fpv():
		if p.hud.gps.get_parent() != p.hud_dji.mapa: p.hud.gps.get_parent().remove_child(p.hud.gps); p.hud_dji.mapa.add_child(p.hud.gps)
		p.hud.gps.custom_minimum_size = Vector2(130, 130)
	elif p.hud.gps.get_parent() != p.hud.panel:
		p.hud.gps.get_parent().remove_child(p.hud.gps); p.hud.panel.add_child(p.hud.gps); p.hud.gps.custom_minimum_size = Vector2(190, 190)
	await _poner_mundo_3d(es_m, p.mundo_datos["nombre"])
	p.casa = p.app_evaluacion._casa()
	p.vel_perdida = p.app_avion_ajustes._vel_perdida()
	p.carga["raiz"].visible = false
	reiniciar(); p.mostrar("")

## Briefing de los trabajos: la misma imagen de la orden de trabajo (la zona y el despegue, sin las soluciones), encima del vuelo.
func ver_briefing(ver = null) -> void:
	var op: bool = Escenarios.datos()[p.sesion["escenario"]].has("operacion")
	var abrir: bool = op and (not p.briefing.visible if ver == null else bool(ver))
	if abrir:
		var f := DatosComunes.carpeta().path_join("operaciones/%s.jpg" % p.sesion["escenario"])
		var img := Image.load_from_file(f) if FileAccess.file_exists(f) else null
		p.briefing_img.texture = ImageTexture.create_from_image(img) if img != null else null
		var w := minf(900, p.get_viewport().get_visible_rect().size.x * 0.7); p.briefing_img.custom_minimum_size = Vector2(w, w * 2 / 3.0)
		p.briefing.size = Vector2.ZERO; p.briefing.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	p.briefing.visible = abrir
	var s := HudDji._redondo(44, Color("#ffb74d") if abrir else Color(0, 0, 0, 0.55), Color("#ffb74d") if abrir else Color(1, 1, 1, 0.4))
	for e in ["normal", "focus", "hover", "pressed"]: p.hud_dji.b_briefing.add_theme_stylebox_override(e, s)

func _texto_ayuda(A: Dictionary) -> void:
	var t := "[font_size=18][b]Controles[/b][/font_size]\n"
	if p.es_bipode():
		t += "[b]W[/b] / [b]S[/b] adelante / atrás · [b]A[/b] / [b]D[/b] girar · [b]← →[/b] girar la cintura (360°) · [b]↑ ↓[/b] subir / bajar los brazos\n"
		t += "[b]Espacio[/b] disparar (mantener) · [b]F[/b] cerrar el puño · [b]L[/b] arrancar / aparcar · [b]R[/b] empezar de nuevo\n"
		t += "[b]1[/b] [b]2[/b] [b]3[/b] cámara piloto / persecución / puesto de tiro (con la mira) · [b]Esc[/b] pausa · [b]T[/b] esta ayuda\n"
		t += "[b]Mando[/b]: palanca izquierda andar y girar, derecha cintura y brazos · gatillo derecho disparar · gatillo izquierdo puño · A arrancar / aparcar · RB cámara · Back empezar de nuevo · Start pausa\n"
		t += "[color=#8be08f]Derriba los drones diana que vuelan alrededor (caen al primer impacto); en multijugador, también los de tus compañeros.[/color]"
		p.hud.ayuda_rt.text = t; return
	if p.es_fpv():
		t += "[b]↑ ↓[/b] cabeceo (↑ adelante) · [b]← →[/b] alabeo · [b]W[/b] / [b]S[/b] gas (no vuelve al centro) · [b]Espacio[/b] gas a cero · [b]A[/b] / [b]D[/b] guiñada\n"
		t += "[b]L[/b] armar / desarmar (con el gas abajo) · [b]M[/b] modo ANGLE / HORIZON / ACRO · [b]R[/b] empezar de nuevo\n"
		t += "[b]1[/b] [b]2[/b] [b]3[/b] cámara piloto / persecución / FPV · [b]I[/b] OSD · [b]Esc[/b] pausa · [b]T[/b] esta ayuda\n"
		t += "[b]Mando[/b] (modo 2): izquierda gas y guiñada, derecha alabeo y cabeceo · A armar / desarmar · LB modo · RB cámara · Back empezar de nuevo · Start pausa\n"
		t += "[color=#8be08f]Mejor con una emisora RC por USB (el gas no tiene muelle) o un mando; con el teclado es muy difícil. Empieza en ANGLE.[/color]\n"
	elif p.es_dron():
		t += "[b]↓ ↑[/b] atrás / adelante · [b]← →[/b] laterales · [b]W[/b] / [b]S[/b] sube / baja · [b]A[/b] / [b]D[/b] gira sobre sí mismo\n"
		t += "[b]M[/b] modo Cine / Normal / Sport · [b]Q[/b] / [b]E[/b] gimbal · [b]F[/b] foto · [b]V[/b] vídeo · [b]H[/b] volver a casa · [b]L[/b] armar · [b]R[/b] empezar de nuevo · [b]B[/b] briefing (trabajos)\n"
		t += "[b]1[/b] [b]2[/b] [b]3[/b] cámara piloto / persecución / del dron · [b]I[/b] pantalla de la app · [b]Esc[/b] pausa · [b]T[/b] esta ayuda\n"
		t += "[b]Mando[/b] (modo 2): izquierda sube, baja y gira; derecha mueve · A despegar / aterrizar · combinación de palancas (CSC: las dos abajo y hacia dentro o hacia fuera, medio segundo): arrancar motores · B volver a casa · X vídeo · Y foto · LB modo · RB cámara · gatillos gimbal · Start pausa\n"
	else:
		t += "[b]↓ ↑[/b] profundidad (↓ tira: morro arriba) · [b]← →[/b] %s\n" % String(A.get("mandos", {}).get("izq_der", "timón"))
		t += "[b]W[/b] / [b]S[/b] gases · [b]Espacio[/b] cortar gases · [b]L[/b] lanzar · [b]R[/b] empezar de nuevo\n"
		t += "[b]1[/b] [b]2[/b] [b]3[/b] cámara piloto / persecución / a bordo · [b][[/b] [b]][/b] compensador\n"
		t += "[b]H[/b] datos de vuelo · [b]I[/b] instrumentos · [b]Esc[/b] pausa · [b]T[/b] esta ayuda\n"
		t += "[b]Mando[/b]: palanca derecha el avión, izquierda el gas · A lanzar · B cortar gas · RB cámara · X empezar de nuevo · Start pausa\n"
	if not p.es_fpv(): t += "[color=#ffb74d]Al lanzar a tope, el par del motor alabea el avión a la izquierda: corrige con un poco de alabeo a la derecha.[/color]\n"
	t += "[color=#aaaaaa]En vuelo libre: [b]+[/b] [b]−[/b] viento, [b]G[/b] rachas. %s[/color]" % String(A.get("ayuda", "El avión vira con el timón: el diedro inclina las alas solo. Si sueltas los mandos, vuelve a volar recto."))
	p.hud.ayuda_rt.text = t

func reiniciar() -> void:
	p._gas_fpv_mando = false; p._caida = {}
	p.av = p.modelo.estado_inicial(); p.app_evaluacion.colocar_en_base(p.av)
	if p.es_uav():
		var c0 := p.app_evaluacion._casa(); p.piloto = PilotoUAV.new(PilotoUAV.para_masa(p.modelo.datos["piloto"], p.modelo.masa_kg / float(DatosComunes.avion(p.sesion["avion"])["masa_kg"])), p.app_evaluacion.pista_actual() if p.con_tren() else null, [c0["N"], c0["E"], p.ent.altura(c0["N"], c0["E"]) if p.en_mundo() else 0.0])
		p.av["torreta"] = { "pan": 0.0, "tilt": -20 * p.D2R }; p.UAV["fijo"] = null; p.UAV["cruz"] = null; p.UAV["fotos"] = 0
		if p.app_evaluacion.morro_de(p.sesion["avion"]) == "fijo": p.UAV["vista"] = "frontal"; p.app_camaras.poner_vista_fija()     # morro fijo: la camara frontal
	else: p.piloto = null
	var F: Dictionary = Escenarios.datos()[p.sesion["escenario"]].get("pista_fpv", {})
	if not F.is_empty() and p.es_fpv() and not p.en_mundo():                 # en la plataforma y en el modo de la mision
		p.av["p"] = [float(F["salida"][0]), float(F["salida"][1]), -0.02]; p.modelo.modo = String(F["modo"])
	_orientar_lanzamiento()
	p.mando["pitch"] = 0.0; p.mando["yaw"] = 0.0; p.mando["trim"] = p.modelo.compensador_grados; p.mando["gimbal"] = 0.0
	var E: Dictionary = Escenarios.datos()[p.sesion["escenario"]]; var vv: Dictionary = E.get("viento", p.sesion["viento"])
	p.ent.configurar_viento(float(vv["vel"]), float(vv["desde"]), bool(vv["rachas"]))
	p.ev = Escenarios.Evaluador.new(p.sesion["escenario"], p.ent, p); p.vuelo = null; p.app_repeticion.poner_pausa(false); p.app_multijugador.ordenes_al_evaluador()
	if p.mundo3d != null: p.mundo3d.poner_operacion(p.ev.op.d if p.ev.op != null else {}, [p.casa["N"], p.casa["E"]] if p.en_mundo() else [0.0, 0.0])
	if p.mundo3d != null: p.mundo3d.poner_pista(p.app_evaluacion.pista_actual())
	p.DJI["grabando"] = false; p.DJI["tRec"] = 0.0; p.DJI["tAnt"] = 0.0; p.DJI["zoomI"] = 0; p.DJI["termica"] = false
	p.hud.guia.visible = false; p.hud.lejos_l.text = ""; p.hud.aviso.text = ""; p.hud.gps.estela = []
	p._fov1 = -1.0; p._acum = 0.0
	_iniciar_juego_bip()
	if p.es_bipode(): p.hud.aviso.text = "Pulsa L (o el botón A) para arrancar el bípode"; return
	if E.has("enVuelo"): _empezar_en_vuelo(); return
	if p.con_tren(): p.av["frenoAparc"] = true; p.hud.aviso.text = "Pulsa L (o el botón A) para arrancar el motor"; return
	p.hud.aviso.text = "Gas abajo del todo y L (o botón A) para armar" if p.es_fpv() else ("Pulsa el botón de despegue (⇧), L o la combinación de palancas para armar" if p.es_dron() else "Pulsa L para lanzar")

func _nuevo_vuelo(h0: float) -> void:
	p.vuelo = { "id": Aula.uuid4(), "inicio": Aula.ahora_iso(), "inicio_local": Time.get_datetime_dict_from_system(), "tVuelo": 0.0, "filas": [], "final": "",
			  "escenario": p.sesion["escenario"], "dificultad": p.sesion["dificultad"], "gasLanz": p.av["gases"], "hmax": h0, "otraCamara": false }
	p.cn_contador = 0; RegistroVuelo.empezar(p, p.vuelo); p.app_resultado.grabar_muestra()
	if not p.es_bipode():                          # el autodiagnostico de la app al armar
		var ap := Desgaste.avisos_app(p.modelo.averias, DatosComunes.avion(p.sesion["avion"]))
		if not ap.is_empty(): p.poner_toast(" · ".join(PackedStringArray(ap)))

## Coloca el avion en vuelo (escenarios con enVuelo), como si acabara de lanzarse y subir.
func _empezar_en_vuelo() -> void:
	var C: Dictionary = Escenarios.datos()[p.sesion["escenario"]]["enVuelo"]; var vs := p.app_avion_ajustes._vel_perdida()
	var V0 := maxf(p.modelo.lanzamiento["vel_ms"] + 1, 1.35 * vs)
	p.av["p"] = [float(C["N"]), float(C["E"]), -float(C["h"])]; p.av["q"] = Cuat.desde_euler(0, 3 * p.D2R, C["rumbo"] * p.D2R); p.av["v"] = [V0, 0.0, 0.0]; p.av["w"] = [0.0, 0.0, 0.0]
	p.av["gases"] = float(C["gas"]); p.av["estado"] = "volando"
	if p.es_fpv(): p.modelo.armar_en_vuelo(p.av)           # dron FPV: armado y con el gas que lo sostiene
	_nuevo_vuelo(float(C["h"]))
	p.ev.empezar_guia(vs)
	p.hud.aviso.text = ""; p.ev.guiar(p.av)

## En la zona 2 el piloto se da la vuelta (se lanza hacia el sur); en un mundo real, con el rumbo del punto elegido.
func _orientar_lanzamiento() -> void:
	var es_m := p.en_mundo()
	if Escenarios.zona_de(p.sesion["escenario"]) != 2 and not es_m: return
	var e := Cuat.euler(p.av["q"])
	var c := p.app_evaluacion._casa()
	var rumbo: float = (float(c["rumbo"]) * p.D2R if c.has("rumbo") else (float(p.sesion["lanz"].get("rumbo", 0)) * p.D2R if not p.sesion["lanz"].is_empty() else 0.0)) if es_m else PI
	p.av["q"] = Cuat.desde_euler(e[0], e[1], rumbo)
	# operaciones: el avion lanzado a mano (reconocimiento) sale de cara al viento, como se lanza de verdad
	if Escenarios.datos()[p.sesion["escenario"]].has("operacion") and p.modelo is ModeloAvion and not p.con_tren() and float(p.ent.viento["base"]) > 1: p.av["q"] = Cuat.desde_euler(e[0], e[1], float(p.ent.viento["rumbo"]) + PI)

func lanzar() -> void:
	if p.es_bipode() and p.av.get("estado", "") == "volando":     # bipode en marcha: L lo aparca (si esta parado) y acaba
		if absf(p.av["vel"]) > 0.2: p.poner_toast("Para antes de aparcar"); return
		terminar_vuelo("aparcado", [0.0, 0.0, 0.0]); return
	if p.av.get("estado", "") != "en mano": return
	p.modelo.lanzar(p.av); _orientar_lanzamiento()
	if p.es_bipode(): p.av["rumbo"] = fposmod(Cuat.euler(p.av["q"])[2], TAU)
	p.hud.aviso.text = "Sube el gas (W o palanca izquierda arriba) para despegar" if p.es_dron() else ("Motor en marcha: quita el freno (espacio) y acelera (W)" if p.con_tren() else "")
	if p.es_fpv(): p.poner_toast("ARMADO")
	if p.es_dron():
		p.get_tree().create_timer(3.0).timeout.connect(func(): if p.av.get("estado") == "volando" and p.av.get("posado", false): p.hud.aviso.text = "")
	if p.sesion["lanz_real"] and not p.modelo.facil and not p.es_dron() and not p.es_bipode() and not p.con_tren():     # un lanzamiento a mano nunca es perfecto
		var gauss := func() -> float: return (randf() + randf() + randf() - 1.5) / 0.5
		var e := Cuat.euler(p.av["q"])
		p.av["v"][0] *= 1 + 0.08 * gauss.call()
		p.av["q"] = Cuat.desde_euler(e[0] + 4 * p.D2R * gauss.call(), e[1] + 2.5 * p.D2R * gauss.call(), e[2] + 3 * p.D2R * gauss.call())
	_nuevo_vuelo(0.0)
	if p.piloto != null and p.modelo.datos.get("lanzado_a_mano", false):           # lanzado a mano: sube solo
		p.piloto.c["rumbo"] = Cuat.euler(p.av["q"])[2]; p.piloto.poner("LANZAMIENTO", p.av); p.piloto.c["rumbo"] = Cuat.euler(p.av["q"])[2]; p._piloto_visto = p.piloto.modo

## Entrenamiento del FPV que se vuela con las gafas (solo cuenta la camara 3): conGafas de la web.
func con_gafas() -> bool:
	var F: Dictionary = Escenarios.datos()[p.sesion["escenario"]].get("pista_fpv", {})
	return F.get("camara", "") == "gafas" and p.es_fpv()

func camara_valida() -> bool: return Escenarios.datos()[p.sesion["escenario"]].has("operacion") or (p.camara == 3 if con_gafas() else (p.camara == 1 or (p.es_dron() and p.camara == 3)))   # en las operaciones vale cualquier camara

## Texto de la pista FPV: {cono:i} -> el pilon de color i (BBCode o solo el nombre) y <b> -> [b] (textoFpv de la web).
func texto_fpv(s: String, bb: bool) -> String:
	var re := RegEx.new(); re.compile("\\{cono:(\\d)\\}")
	for m in re.search_all(s):
		var i := int(m.get_string(1))
		s = s.replace(m.get_string(), Escenarios.pilon_bb(p.ent, i, true) if bb else String(p.ent.circuito["colores"][i]["nombre"]))
	return s.replace("<b>", "[b]").replace("</b>", "[/b]") if bb else s

func paso(dt: float) -> void:
	p.app_avion_ajustes.aplicar_recorridos()
	var viento := p.ent.actualizar(dt)
	var gas_palanca = null
	if p.piloto != null and p.av["estado"] == "volando" and p.piloto.modo != "MANUAL":      # UAV con el piloto automatico: las superficies, y el gas y el freno si los lleva
		p.piloto.viento_desde = p.ent.viento["rumbo"] - PI; p.piloto.viento_vel = p.ent.viento["base"]     # la toma en perdida, contra el viento
		p.piloto.sens = p.modelo.sens                                                                  # sensores averiados (el Grajo)
		var o := p.piloto.paso(p.av, dt, p.mando, p.av["gases"])
		var mm := p.mando.duplicate(); mm["pitch"] = o["pitch"]; mm["yaw"] = o["yaw"]; mm["guinada"] = o["guinada"]
		p.modelo.servos(p.av, mm, dt)
		if o["gas"] != null: gas_palanca = p.av["gases"]; p.av["gases"] = o["gas"]
		if o["freno"] != null: p.av["freno"] = o["freno"]
		if p.piloto.modo != p._piloto_visto:
			if p._piloto_visto != "": p.poner_toast("Piloto automático: " + PilotoUAV.NOMBRE[p.piloto.modo])
			p._piloto_visto = p.piloto.modo
	else: p.modelo.servos(p.av, p.mando, dt)
	p.av["agl"] = -p.av["p"][2] - p.ent.altura(p.av["p"][0], p.av["p"][1])
	if p.con_tren():                     # avion de pista: el suelo bajo cada rueda (el terreno no es plano)
		var g0: float = -p.av["p"][2] - p.av["agl"]; var ds := []
		for r in p.modelo.tren["ruedas"]:
			var rw := Cuat.rot(p.av["q"], r["p"]); ds.append(p.ent.altura(p.av["p"][0] + rw[0], p.av["p"][1] + rw[1]) - g0)
		p.av["dSuelo"] = ds
	viento = p.ent.viento_a(viento, p.av["agl"])
	p.av["pg"] = p.ent.rafaga_alabeo(p.modelo.b_m, p.av["agl"])
	if p.av["estado"] != "volando": return
	if not p._caida.is_empty(): _caida_derribado(dt); return     # multijugador: derribado por un bipode
	var p_ant: Array = p.av["p"].duplicate()
	if p.es_bipode(): _paso_terrestre(dt, viento, p_ant); return
	Desgaste.antes_paso(p.modelo, p.av)               # averias: superficies con holgura o bisagra floja (desgaste.gd)
	var vn: Array = p.modelo.paso(p.av, viento, dt)
	Desgaste.despues_paso(p.modelo, p.av, dt)         # y vibraciones o el par de una helice danada
	if p.av.has("roturaMontaje"): terminar_vuelo("roto (" + String(p.av["roturaMontaje"]) + ")", vn); return     # el Grajo con el ala sin asegurar
	_avisos_bateria()
	if p.destino_prueba != null: p.av["p"] = (p.destino_prueba as Array).duplicate(); p.av["v"] = [0.0, 0.0, 0.0]; p.av["w"] = [0.0, 0.0, 0.0]   # pruebas: el dron llevado en volandas
	if gas_palanca != null: p.av["gasMotor"] = p.av["gases"]; p.av["gases"] = gas_palanca      # la palanca del gas no se mueve: en crucero elige la velocidad
	else: p.av["gasMotor"] = p.av["gases"]
	var E: Dictionary = Escenarios.datos()[p.sesion["escenario"]]
	var suelo_h := p.ent.altura(p.av["p"][0], p.av["p"][1])      # una vez: la usan hmax y el contacto con el suelo (misma posicion)
	if p.vuelo != null:
		p.vuelo["tVuelo"] += dt; p.vuelo["hmax"] = maxf(p.vuelo["hmax"], -p.av["p"][2] - suelo_h)
	if p.con_tren():                           # avion de pista: lo que rompe el tren o las alas en tierra y el final de la carrera
		var ft: String = p.modelo.fin_tren(p.av)
		if ft == "" and p.av["enTierra"] and p.ent.en_mar(p.av["p"][0], p.av["p"][1]): ft = "roto (ha caído al mar)"
		if ft != "": terminar_vuelo(ft, vn); return
		# un entrenamiento solo se supera visto desde el piloto (camara 1); con el dron vale tambien la pantalla de la app
		if not p.vuelo["otraCamara"] and not camara_valida() and not (E["objetivos"] as Array).is_empty():
			p.vuelo["otraCamara"] = true; p.poner_toast("Sin las gafas el entrenamiento no cuenta: vuelve a la cámara FPV (3)" if con_gafas() else "Con esta cámara el entrenamiento no cuenta: vuelve a la del piloto (1)")
	p.cn_contador += 1
	if p.cn_contador % p.CN_CADA == 0: p.app_resultado.grabar_muestra(); p.ev.evaluar(p.av, p.CN_CADA * p.DT); p.app_multijugador.vigilar_exclusiones()
	if p.av["estado"] != "volando": return
	if p.ent.choca_pilon(p.av["p"], p.modelo.b_m / 2): terminar_vuelo("roto (choque con un pilón)", vn); return
	if p.ent.choca_arbol(p.av["p"], p.modelo.b_m / 2): terminar_vuelo("roto (choque con un árbol)", vn); return
	if p.ent.choca_edificio(p.av["p"], p.modelo.b_m / 2): terminar_vuelo("roto (choque con un edificio)", vn); return
	if p.ev.fpv != null:                        # pista FPV: objetivos y choques con postes, puertas y torre
		for t in p.ev.fpv.paso(p_ant, p.av, dt, { "modo": p.modelo.modo, "critica": p.modelo.celda(p.av) < p.modelo.fc["critico_celda_V"] }): p.poner_toast(texto_fpv(t, false))
		if p.ev.fpv.choque != "": terminar_vuelo("roto (" + p.ev.fpv.choque + ")", vn); return
	if p.ev.op != null:                         # operaciones: normas del operador, el trabajo y los choques con cables, torres y faro
		var cam_op := p.app_camaras.camara_op().merged({ "grabando": false }) if ((p.es_uav() and p.av.has("torreta")) or (not p.es_dron() and p.ev.op.d.has("recon"))) else { "gimbal": p.av.get("gimbal", -10.0), "grabando": p.DJI["grabando"] }   # UAV: la torreta o el morro fijo; avion: la camara de a bordo
		for t in p.ev.op.paso(p_ant, p.av, dt, cam_op.merged(p.app_apps_dron.cam_dji()).merged({ "aterrizando": p.piloto != null and p.piloto.modo == "ATERRIZAJE" })): p.poner_toast(t)
		if p.ev.op.choque != "": terminar_vuelo("roto (" + p.ev.op.choque + ")", vn); return
		var C = p.ev.op.carr
		if C != null and C["tFin"] != null and not C.get("anotado", false):     # carrera: la meta, el mejor de la sesion y la marca del vuelo
			C["anotado"] = true; var s: float = C["tFin"] - C["t0"]
			if p.carrera_mejor == null or s < p.carrera_mejor["t"]: p.carrera_mejor = { "t": s, "avion": p.sesion["avion"] }
			if p.vuelo != null: p.vuelo["marca"] = s
		var fin_c: String = p.ev.op.acabada(p.av["t"])
		if fin_c != "": terminar_vuelo(fin_c, vn); return
	if p.ent.fuera_de_limites(p.av["p"]): terminar_vuelo("fuera de límites", vn); return
	# vueltas al circuito de pilones (no en la orientacion: sus avisos se solapaban con los de los ochos)
	var su = p.ev.contador.actualizar(p_ant, p.av["p"], p.av["t"]) if (p.ev.zona == 1 and p.ev.contador != null and not p.ev.obj.has("ocho1")) else {}
	if p.ev.zona <= 2 and not E.has("mundo") and p.ev.fpv == null: _zona2(p_ant)
	if su != null and not (su as Dictionary).is_empty():
		var nom: String = p.ent.circuito["colores"][su["i"]]["nombre"]; var sen := int(E.get("sentido", 0))
		match String(su["tipo"]):
			"vuelta": p.poner_toast("¡Vuelta %d!  %.1f s" % [su["n"], su["tiempo"]])
			"dentro": p.poner_toast("¡Por dentro del pilón %s! Vuelta anulada" % nom)
			"sentido": p.poner_toast("¡Sentido contrario en el %s! El orden es %s" % [nom, p.ent.orden_pilones(sen)])
			_: p.poner_toast(("Pilón %s: salida" % nom) if int(su["n"]) == 1 else ("Pilón %s %d/4" % [nom, int(su["n"]) - 1]))
	var suelo := p.ent.contacto_suelo(p.av, vn, suelo_h, p.modelo.datos.get("toma_perdida") if p.modelo is ModeloAvion else null)
	if suelo != "": terminar_vuelo(suelo, vn)

## Un paso del bipode (pasoTerrestre de la web): la pendiente del terreno (a 1,5 m delante/detras y a los lados), el paso
## del modelo, la altura del terreno donde queda y los choques: arboles y pilones lo paran (no lo rompen); en el mar se hunde.
## Avisos de la bateria (bateria.gd), una vez cada uno: el dron con poca bateria (av.avisoBat del modelo: baja, vuelta a
## casa por bateria, aterrizaje forzoso), el avion al 20 % y con el motor cortado por el regulador, y sin bateria. Como
## avisosBateria() de simulador.html.
## Despues de cada vuelo, el desgaste del vehiculo (desgaste.gd): horas, bateria y lo que se estropea; y las averias que
## el profesor ha puesto en vuelo (sala multijugador). Se guarda en el aula (o en el ordenador). Como desgasteTrasVuelo.
func desgaste_tras_vuelo(v: Dictionary, final: String) -> void:
	var A := DatosComunes.avion(p.sesion["avion"])
	if Desgaste.clase(A) == "" or p.vr != null: return             # en las gafas aun no hay Taller donde repararlo: sin desgaste
	var R = v.get("reg")
	var col := func(n: String) -> Array:
		var i: int = (R["columnas"] as Array).find(n) if R != null else -1
		if i < 0: return []
		return (R["filas"] as Array).map(func(f): return f[i]).filter(func(x): return x is float or x is int)
	var T: Array = col.call("temperatura_bateria_C"); var B: Array = col.call("bateria_pct") if p.modelo.get("B") is Dictionary and not (p.modelo.B as Dictionary).is_empty() else []
	var extra: Array = (v.get("averiasSala", []) as Array).duplicate()
	var info := { "s": float(p.av["t"]), "roto": final.begins_with("roto"), "bat0": B[0] if not B.is_empty() else null, "bat1": B[-1] if not B.is_empty() else null,
				  "tempMax": T.max() if not T.is_empty() else null, "semilla": String(v["id"]), "fecha": Aula.ahora_iso(), "tomaPerdida": p.av.get("tomaPerdida", false) }
	Desgaste.modificar(p, p.sesion["avion"], func(est):
		for a in extra: Desgaste.anadir(est, a, "profesor", info["fecha"])
		return Desgaste.tras_vuelo(est, A, info))

func _avisos_bateria() -> void:
	if p.av.get("bat") == null: return
	var pc: float = p.modelo.bateria_pct(p.av)
	var k: String = (String(p.av.get("avisoBat", "")) if String(p.av.get("avisoBat", "")) != "" else ("baja" if not p.es_dron() and pc <= 20 else "")) + ("+cortado" if p.av.get("cortado", false) else "") + ("+agotada" if p.av.get("sinBateria", false) else "")
	var ant: String = p.av.get("_batVisto", "")
	if k == ant: return
	p.av["_batVisto"] = k
	if p.av.get("sinBateria", false) and not ant.contains("+agotada"): p.poner_toast("Batería agotada: los motores se paran"); return
	if p.av.get("cortado", false) and not ant.contains("+cortado"): p.poner_toast("El regulador ha cortado el motor: batería agotada. Planea y aterriza"); p.app_pantallas.poner_aviso("Motor cortado: batería agotada"); return
	if k.begins_with("baja") and not ant.begins_with("baja"): p.poner_toast("Batería baja (30 %): vuelve pronto" if p.es_dron() else "Batería baja (20 %): aterriza pronto")
	if k.begins_with("rth") and not ant.begins_with("rth"): p.poner_toast("Batería justa para volver: volviendo a casa (mueve las palancas para cancelar)")
	if k.begins_with("critica") and not ant.begins_with("critica"): p.poner_toast("¡Batería crítica! Aterrizaje forzoso: busca dónde posarlo"); p.app_pantallas.poner_aviso("Aterrizaje forzoso: batería crítica")
	if k.begins_with("celda") and not ant.begins_with("celda"): p.poner_toast("¡Tensión de celda muy baja! Aterrizaje forzoso"); p.app_pantallas.poner_aviso("Aterrizaje forzoso: una celda de la batería se ha hundido")

func _paso_terrestre(dt: float, viento, p_ant: Array) -> void:
	var pv: Array = p.av["p"]; var d := 1.5
	p.av["pendiente"] = [(p.ent.altura(pv[0] + d, pv[1]) - p.ent.altura(pv[0] - d, pv[1])) / (2 * d), (p.ent.altura(pv[0], pv[1] + d) - p.ent.altura(pv[0], pv[1] - d)) / (2 * d)]
	var vn: Array = p.modelo.paso(p.av, viento, dt)
	if p.vuelo != null: p.vuelo["tVuelo"] += dt
	if p.ent.choca_arbol(p.av["p"], 1.1) or p.ent.choca_pilon(p.av["p"], 1.1) or p.ent.choca_edificio(p.av["p"], 1.6):
		p.av["p"] = p_ant.duplicate(); p.av["vel"] = 0.0
		if not p._aviso_choque:
			p._aviso_choque = true; p.poner_toast("¡Choque! Da la vuelta"); p.get_tree().create_timer(1.5).timeout.connect(func(): p._aviso_choque = false)
	p.av["p"][2] = -p.ent.altura(p.av["p"][0], p.av["p"][1])
	p.cn_contador += 1
	if p.cn_contador % p.CN_CADA == 0: p.app_resultado.grabar_muestra(); p.ev.evaluar(p.av, p.CN_CADA * p.DT)
	if p.ent.en_mar(p.av["p"][0], p.av["p"][1]): terminar_vuelo("roto (se ha hundido en el mar)", vn); return
	if p.ent.fuera_de_limites(p.av["p"]): terminar_vuelo("fuera de límites", vn); return

func _altura_c() -> Callable: return func(N: float, E: float) -> float: return p.ent.altura(N, E)

func _iniciar_juego_bip() -> void:
	if p.efectos_bip != null: p.efectos_bip.queue_free(); p.efectos_bip = null
	p.juego_bip = null
	if not p.es_bipode(): return
	p.juego_bip = JuegoBipode.new(DatosComunes.avion(p.sesion["avion"]), (Time.get_ticks_msec() % 100000) + 1)
	p.juego_bip.iniciar([p.av["p"][0], p.av["p"][1]], _altura_c())
	p.efectos_bip = EfectosBipode.new(); p.add_child(p.efectos_bip)
	p._bip_oido = { "pisadas": p.av["pisadas"], "disparos": p.av["disparos"], "derribados": 0 }

func _paso_juego_bip(dt: float) -> void:
	_paso_balas_otros(dt)
	var J := p.juego_bip
	p.hud.bip.visible = J != null and p.pantalla_actual == ""
	p.hud.mira.visible = false
	if J == null: return
	J.blancos = _blancos_sala()
	if p.av["estado"] == "volando": J.paso(dt, p.av, p.modelo, _altura_c())
	if p.av["pisadas"] != p._bip_oido["pisadas"]: p._bip_oido["pisadas"] = p.av["pisadas"]; p.sonido.evento("pisada")
	if p.av["disparos"] != p._bip_oido["disparos"]: p._bip_oido["disparos"] = p.av["disparos"]; p.sonido.evento("disparo")
	for e in J.eventos:
		if e["tipo"] == "explosion": p.sonido.evento("explosion")
	if J.derribados != p._bip_oido["derribados"]: p._bip_oido["derribados"] = J.derribados; p.poner_toast("¡Dron derribado! (%d)" % J.derribados)
	p.efectos_bip.pintar(J, dt, p.cam)
	# mira (camaras 2 y 3): donde apunta de verdad el cañon, el punto a 120 m sobre su linea de tiro proyectado en la pantalla
	var ap: Dictionary = p.modelo.apuntado(p.av); var P := Avion3D.ned([ap["o"][0] + ap["d"][0] * 120, ap["o"][1] + ap["d"][1] * 120, ap["o"][2] + ap["d"][2] * 120])
	if (p.camara == 2 or p.camara == 3) and p.pantalla_actual == "" and not p.cam.is_position_behind(P):
		var sp := p.cam.unproject_position(P); var tam := p.get_viewport().get_visible_rect().size
		p.hud.mira.visible = sp.x > -20 and sp.y > -20 and sp.x < tam.x + 20 and sp.y < tam.y + 20
		p.hud.mira.position = sp - Vector2(28, 28)
	p.hud.bip_drones.text = "DRONES DERRIBADOS %d" % J.derribados
	var w: float = p.av["wCanones"] / (p.modelo.bp["cadencia_rpm"] / 60.0 / 6.0 * TAU)
	p.hud.bip_canon.text = ("FUEGO" if w > 0.8 else "CAÑÓN ACELERANDO %d %%" % int(round(w * 100))) if p.av["cmd"]["fuego"] > 0 else "CAÑÓN LISTO"

func _impactos_de(o: Dictionary) -> void:
	var g = o.get("golpes")
	if not (g is Dictionary) or p.av.is_empty() or p.modelo == null or p.es_bipode(): return
	if DatosComunes.avion(String(o.get("avion", ""))).get("tipo", "") != "bipode": return     # solo dispara el bipode
	var gv = g.get(p.app_multijugador.multi_id(), 0)
	if not (gv is int or (gv is float and is_finite(gv))): return
	var n := int(gv)
	if not p._golpes_vistos.has(o["id"]): p._golpes_vistos[o["id"]] = n; return      # los de antes de entrar no cuentan
	if n <= int(p._golpes_vistos[o["id"]]): return
	var nuevos: int = n - int(p._golpes_vistos[o["id"]]); p._golpes_vistos[o["id"]] = n
	if p.av["estado"] != "volando" or p.av.get("posado", false) or not p._caida.is_empty(): return
	p._vida_multi -= nuevos; p.sonido.evento("roto")
	if p._vida_multi > 0: p.poner_toast("¡Impacto de %s! Te quedan %d" % [o["nombre"], p._vida_multi]); return
	p._vida_multi = p.BIP_VIDAS; p.poner_toast("¡Derribado por %s!" % o["nombre"])
	p._caida = { "v": Cuat.rot(p.av["q"], p.av["v"]), "w": 3 + 3 * randf(), "nombre": o["nombre"] }     # cae dando vueltas hasta el suelo

## Derribado: los motores se paran y cae con su velocidad, dando vueltas, hasta el suelo; ahi acaba el vuelo (caidaDerribado).
func _caida_derribado(dt: float) -> void:
	var c := p._caida; var v: Array = c["v"]
	v[2] += 9.81 * dt; v[0] *= 1 - 0.3 * dt; v[1] *= 1 - 0.3 * dt
	p.av["p"] = [p.av["p"][0] + v[0] * dt, p.av["p"][1] + v[1] * dt, p.av["p"][2] + v[2] * dt]
	var e := Cuat.euler(p.av["q"]); var w: float = c["w"]
	p.av["q"] = Cuat.desde_euler(e[0] + w * dt, e[1] + 0.4 * w * dt, e[2] + 0.7 * w * dt)
	p.av["v"] = Cuat.rot(Cuat.inv(p.av["q"]), v); p.av["gases"] = 0.0; p.av["rpm"] = 0.0; p.av["motorRoto"] = true
	var suelo := p.ent.altura(p.av["p"][0], p.av["p"][1])
	if -p.av["p"][2] <= suelo:
		p.av["p"][2] = -suelo; p._caida = {}; terminar_vuelo("roto (derribado por %s)" % c["nombre"], v)

## Los blancos del bipode (multijugador): los aviones y drones de los demas que estan en el aire.
func _blancos_sala() -> Array:
	var lista := []
	if p.sala.is_empty(): return lista
	for id in p.multi_otros:
		var o: Dictionary = p.multi_otros[id]; var D := DatosComunes.avion(String(o["avion"]))
		if D.is_empty() or D.get("tipo", "") == "bipode" or o.get("estado", "") != "volando" or float(o.get("agl", 0.0)) < 0.3: continue
		var g = p._fantasmas.get(id)
		lista.append({ "id": id, "p": (g["p"] as Array).duplicate() if g != null else (o["p"] as Array).duplicate(), "r": maxf(0.8, float(D.get("b_m", 1.0)) / 2 + 0.25) })
	return lista

func _paso_balas_otros(dt: float) -> void:
	if p.sala.is_empty():
		if not p._balas_otros.is_empty(): p._balas_otros["ef"].queue_free(); p._balas_otros = {}
		return
	for id in p.multi_otros:
		var o: Dictionary = p.multi_otros[id]; var bp = o.get("bip")
		if not (bp is Array) or bp.size() < 7: continue
		var D := DatosComunes.avion(String(o["avion"]))
		if D.is_empty() or not D.has("bipode"): continue
		if p._balas_otros.is_empty():
			p._balas_otros = { "J": JuegoBipode.new(D, 7), "ef": EfectosBipode.new(), "vistos": {} }; p.add_child(p._balas_otros["ef"])
		var n := int(bp[5]); var v = p._balas_otros["vistos"].get(id); p._balas_otros["vistos"][id] = n
		if v == null or n <= int(v): continue
		var piv := {}
		for pz in D["modelo3d"]["piezas"]: piv[pz["nombre"]] = pz["pivote"]
		var g = p._fantasmas.get(id)
		var est := { "p": g["p"] if g != null else o["p"], "q": o["q"], "cintura": float(bp[0]), "brazos": float(bp[1]) }
		for k in mini(4, n - int(v)): p._balas_otros["J"].disparo(ModeloBipode.apuntado_con(piv, D["bipode"], est))
	if p._balas_otros.is_empty(): return
	var J: JuegoBipode = p._balas_otros["J"]
	J.paso(dt, { "p": [0.0, 0.0, 0.0], "disparos": J.disparos }, null, _altura_c())
	J.eventos = J.eventos.filter(func(e): return e["tipo"] == "suelo")
	p._balas_otros["ef"].pintar(J, dt, p.cam)

## Puerta y pasadas bajas de la zona 2 (en sus misiones y en vuelo libre), con su aviso.
func _zona2(p_ant: Array) -> void:
	var orden: Array = Escenarios.PUERTAS_ORDEN
	for cual in ["naranja", "verde"]:
		var pu: Dictionary = p.ent.cruza_puerta(p_ant, p.av["p"], cual)
		if pu.is_empty(): continue
		if pu["tipo"] != "puerta":
			p.poner_toast(("Por encima de la puerta %s (%d m): no cuenta" % [cual, int(round(pu["h"]))]) if pu["tipo"] == "alta" else "Por fuera de la puerta %s: no cuenta" % cual)
			continue
		p.ev.puertas += 1
		if cual == "naranja" and p.ev.obj.has("puertaR") and p.ev.obj.has("pasada") and p.ev.obj["pasada"]["estado"] == "ok": p.ev.marcar("puertaR", "ok")
		if p.ev.obj.has("puerta1"):          # la mision de la puerta: naranja, verde, naranja, verde, en ese orden
			var toca: String = orden[p.ev.paso_puerta] if p.ev.paso_puerta < orden.size() else ""
			if cual != toca:
				p.poner_toast(("Esa es la %s: ahora toca la %s" % [cual, toca]) if toca != "" else "Puerta %s: ya están todas, a aterrizar" % cual)
				continue
			p.ev.paso_puerta += 1; p.ev.marcar("puerta" + str(p.ev.paso_puerta), "ok")
			var sig := ("ahora la " + String(orden[p.ev.paso_puerta])) if p.ev.paso_puerta < orden.size() else "ahora, a aterrizar"
			p.poner_toast("¡Puerta %s! %d/%d (a %d m) · %s" % [cual, p.ev.paso_puerta, orden.size(), int(round(pu["h"])), sig])
		else: p.poner_toast("¡Puerta %s!  (hacia el %s, a %d m)" % [cual, pu["sentido"], int(round(pu["h"]))])
	if not p.ev.subido or p.ev.pasada == null: return          # el lanzamiento cruza la pista 2: las pasadas cuentan despues de subir
	var pb: Dictionary = p.ev.pasada.actualizar(p.av["p"])
	if not pb.is_empty():
		if pb["ok"]: p.ev.pasadas[pb["sentido"]] += 1; p.poner_toast("¡Pasada baja hacia el %s!  (%.1f–%.1f m)" % [pb["sentido"], pb["hmin"], pb["hmax"]])
		else: p.poner_toast("Pasada baja no válida: " + String(pb["motivo"]))

func terminar_vuelo(final: String, vn = null) -> void:
	if p.av["estado"] != "volando": return
	if vn == null: vn = [0.0, 0.0, 0.0]
	# lanzamiento fallido: en el suelo antes de 6 s sin pasar de 5 m. No cuenta como aterrizaje; si se ha roto, como accidente
	if p.vuelo != null and not p.es_dron() and not p.es_bipode() and not p.con_tren() and not p.modelo.datos.get("lanzado_a_mano", false) and p.av["t"] < p.LANZ["fallo_s"] and p.vuelo["hmax"] < p.LANZ["fallo_h"] and (final == "aterrizado" or final.begins_with("roto")):
		p.vuelo["lanzamiento"] = p.app_avion_ajustes.causa_lanzamiento_fallido(p.vuelo["gasLanz"])
		var roto := final.begins_with("roto")
		final = ("roto (" if roto else "") + "lanzamiento fallido: " + String(p.vuelo["lanzamiento"]["corto"]) + (")" if roto else "")
	p.av["estado"] = "roto" if final.begins_with("roto") else ("aterrizado" if final == "aterrizado" else "terminado")
	p.av["v"] = [0.0, 0.0, 0.0]; p.av["w"] = [0.0, 0.0, 0.0]; p.av["rpm"] = 0.0
	p.hud.guia.visible = false
	if p.vuelo == null: return
	p.vuelo["final"] = final; p.app_resultado.grabar_muestra(); RegistroVuelo.cerrar(p, p.vuelo); desgaste_tras_vuelo(p.vuelo, final)
	p.ev.evaluar_final(p.sesion["escenario"], final, p.av, vn)
	p.hud.aviso.text = ("LANZAMIENTO FALLIDO: " + String(p.vuelo["lanzamiento"]["corto"])) if p.vuelo.has("lanzamiento") else \
		(("¡ROTO!  (" + final.substr(6, final.length() - 7) + ")") if final.begins_with("roto") else ("Aterrizado" if final == "aterrizado" else ("Aparcado" if final == "aparcado" else "") if final == "aparcado" else
		("FUERA DE LÍMITES: el avión se ha perdido de vista" if final == "fuera de límites" else "")))
	p.hud.lejos_l.text = ""
	p.ultimo_vuelo = p.vuelo
	if p.aj.get("cn_auto", false): p.app_resultado.guardar_csv(p.vuelo, OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS).path_join(p.app_resultado.nombre_csv(p.vuelo)))
	if final == "aterrizado" or final.begins_with("roto"): p.sonido.evento("roto" if final.begins_with("roto") else "toque")
	var v = p.vuelo
	if p.salir_tras: p.salir_tras = false; p.app_resultado.guardar_vuelo(v, p.app_resultado.datos_resultado(v)); p.app_pantallas.ir_inicio(); return
	if final != "abandonado": await p.get_tree().create_timer(1.8).timeout
	if p.vuelo == v and p.pantalla_actual == "" and not p.rep_activa: p.app_resultado.mostrar_resultado(v)     # si entretanto se pulso R o se salio, ya no toca
