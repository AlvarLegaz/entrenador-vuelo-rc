class_name AppMultijugador
extends RefCounted
## Multijugador: salas del aula, fantasmas, ordenes del profesor y el bipode en sala.
## Parte de principal.gd (como js/app/multijugador.js de la web): el estado esta en principal.gd (p).

var p: Principal

func _init(principal: Principal) -> void: p = principal

func multi_id() -> String:
	if p._multi_id == "": p._multi_id = Aula.uuid4()
	return p._multi_id

func multi_posible() -> bool: return p.aula.activo and p.sesion["alumno"] != null

func nombre_piloto() -> String: return String(p.sesion["alumno"]["nombre"]) if p.sesion["alumno"] != null else "Invitado " + multi_id().substr(0, 4)

func ir_multi() -> void:
	p.mostrar("pMulti"); p.pantallas["pMulti"].refrescar()

## Entra en una sala: su escenario, su punto de salida y su viento, con un vehiculo que valga para el; y a volar.
func entrar_sala(s: Dictionary) -> void:
	if not Escenarios.datos().has(s["escenario"]): p.poner_toast("Esta sala es de algo que este simulador no tiene: actualízalo"); return
	var E: Dictionary = Escenarios.datos()[s["escenario"]]
	p.sala = s; p.multi_otros = {}; reiniciar_ordenes()
	var veh: Array = (E.get("vehiculos", ["avion", "dron", "fpv"]) as Array).duplicate()
	if (E["objetivos"] as Array).is_empty() and not E.has("operacion"): veh.append("bipode")     # vuelo libre: tambien el bipode
	if E.has("operacion") and p.ids_aviones.has(String(E["operacion"].get("avion", ""))): p.sesion["avion"] = String(E["operacion"]["avion"])     # trabajos: el dron que piden
	elif not Escenarios.vehiculo_de(p.sesion["avion"]) in veh:
		for a in p.ids_aviones:
			if Escenarios.vehiculo_de(a) in veh: p.sesion["avion"] = a; break
	p.sesion["escenario"] = s["escenario"]
	var lz = s.get("lanz")
	if lz is Dictionary and _nums_finitos([lz.get("N", INF), lz.get("E", INF), lz.get("rumbo", INF)], 3): p.sesion["lanz"] = lz
	elif E.has("operacion"):                     # trabajos: su despegue
		var S0: Dictionary = E["operacion"]["salida"]; p.sesion["lanz"] = { "mundo": E["mundo"], "N": float(S0["n"]), "E": float(S0["e"]), "rumbo": float(S0["rumbo"]) }
	var vt = s.get("viento")
	if vt is Dictionary and _nums_finitos([vt.get("vel", INF), vt.get("desde", INF)], 2) and not E.has("viento"): p.sesion["viento"] = vt
	p.poner_toast("Sala %s: %s" % [s["codigo"], String(s.get("nombre", ""))]); p.app_vuelo.empezar()

func salir_sala() -> void:
	if p.sala.is_empty(): return
	var s := p.sala; p.sala = {}; p.multi_otros = {}; _poner_fantasmas(); p.sala_info.visible = false; p._golpes_vistos = {}; p._vida_multi = p.BIP_VIDAS
	reiniciar_ordenes(); _pintar_ordenes(); _poner_exclusiones()
	p.aula.api("POST", "salas/%s/salir" % s["codigo"], { "id": multi_id() })

func reiniciar_ordenes() -> void:
	p.ordenes = { "n": 0, "viento": null, "notam": [], "aterrizar": 0.0, "en_aire": false, "zonas": [], "persona": null, "fuga": null, "t_aviso": 0.0 }

func aplicar_ordenes(lista: Array) -> void:
	if p.ordenes.is_empty(): reiniciar_ordenes()
	var cambio := false
	for o in lista:
		if not (o is Dictionary) or int(o.get("n", 0)) <= int(p.ordenes["n"]): continue
		p.ordenes["n"] = int(o.get("n", 0)); cambio = true
		var para := String(o.get("para", "*"))
		if para != "*" and para != multi_id(): continue
		var nueva: bool = float(o.get("edad", 0)) < 30          # las de antes de entrar en la sala se aplican sin anunciarlas
		match String(o.get("tipo", "")):
			"viento":
				p.ordenes["viento"] = { "vel": float(o.get("vel", 0)), "desde": float(o.get("desde", 0)), "rachas": bool(o.get("rachas", false)) }
				p.ent.configurar_viento(float(o.get("vel", 0)), float(o.get("desde", 0)), bool(o.get("rachas", false)))
				if nueva: p.poner_toast("Viento: %s m/s del %s%s" % [PasadaBaja._num(float(o.get("vel", 0))), PantallaMisiones.RUMBOS_VIENTO[int(round(float(o.get("desde", 0)) / 45.0)) % 8], ", con rachas" if o.get("rachas", false) else ""])
			"notam":
				p.ordenes["notam"].append(String(o.get("texto", "")))
				if nueva: p.poner_toast("Nuevo NOTAM")
			"quitar_notam": p.ordenes["notam"] = []
			"aterrizar":
				if nueva: p.ordenes["aterrizar"] = Time.get_ticks_msec() / 1000.0; p.ordenes["en_aire"] = false
			"exclusion":
				p.ordenes["zonas"].append({ "id": int(o.get("n", 0)), "N": float(o.get("N", 0)), "E": float(o.get("E", 0)), "r": float(o.get("r", 0)) })
				if nueva: p.poner_toast("Nueva zona de exclusión: mírala en el mapa")
			"quitar_exclusion": p.ordenes["zonas"] = (p.ordenes["zonas"] as Array).filter(func(z): return z["id"] != int(o.get("id", -1)))
			"senderista":
				p.ordenes["persona"] = [float(o.get("N", 0)), float(o.get("E", 0))]
				if mover_desaparecido() and nueva: p.poner_toast("Nueva posición del desaparecido: búscalo")
			"fuga":
				p.ordenes["fuga"] = [float(o.get("N", 0)), float(o.get("E", 0))]
				if mover_fuga_profesor() and nueva: p.poner_toast("La fuga de gas ahora está en otra unidad: localízala de nuevo")
			"averia":                                # averia en vuelo: sin avisar (como en la realidad)
				if nueva and p.modelo != null and p.vuelo != null and not p.av.is_empty() and p.av["estado"] == "volando" and not p.es_bipode():
					var pide := { "c": String(o.get("c", "")), "tipo": String(o.get("averia", "")) }
					if o.has("celda"): pide["n"] = int(o["celda"])
					var a = Desgaste.adaptar(DatosComunes.avion(p.sesion["avion"]), pide)
					if a != null:
						Desgaste.en_vuelo(p.modelo, a)
						if not p.vuelo.has("averiasSala"): p.vuelo["averiasSala"] = []
						p.vuelo["averiasSala"].append(a)
						var ap := Desgaste.avisos_app([a], DatosComunes.avion(p.sesion["avion"]))
						if not ap.is_empty(): p.poner_toast(" · ".join(PackedStringArray(ap)))
	if cambio: ordenes_al_evaluador(); _poner_exclusiones()
	_pintar_ordenes()

## El desaparecido donde lo ha puesto el profesor (en la busqueda): hay que volver a encontrarlo.
func mover_desaparecido() -> bool:
	if p.ordenes.get("persona") == null or p.ev == null or p.ev.op == null or not p.ev.op.d.has("zona"): return false
	var op = p.ev.op; op.d["persona"] = (p.ordenes["persona"] as Array).duplicate(); op.encontrado = false; op.error = null
	for k in ["localizar", "posicion"]:
		if p.ev.obj.has(k) and p.ev.obj[k]["estado"] != "mal": p.ev.obj[k]["estado"] = "pend"
	if p.mundo3d != null: p.mundo3d.poner_operacion(op.d, [p.casa["N"], p.casa["E"]] if p.en_mundo() else [0.0, 0.0])
	return true

## La fuga de gas de SABIC en la unidad mas cercana a donde la ha puesto el profesor: hay que volver a localizarla.
func mover_fuga_profesor() -> bool:
	if p.ordenes.get("fuga") == null or p.ev == null or p.ev.op == null or not p.ev.op.d.has("racks"): return false
	p.ev.op.mover_fuga(p.ordenes["fuga"][0], p.ordenes["fuga"][1]); p.ev.set_meta("fuga_profesor", true)
	if p.ev.obj.has("fuga") and p.ev.obj["fuga"]["estado"] != "mal": p.ev.obj["fuga"]["estado"] = "pend"
	if p.mundo3d != null: p.mundo3d.poner_operacion(p.ev.op.d, [p.casa["N"], p.casa["E"]] if p.en_mundo() else [0.0, 0.0])
	return true

## Al empezar (o empezar de nuevo) un vuelo en la sala: el viento, el desaparecido y el objetivo de las zonas de exclusion.
func ordenes_al_evaluador() -> void:
	if p.sala.is_empty() or p.ev == null or p.ordenes.is_empty(): return
	if p.ev.op != null and p.sala.get("ajustes") != null:              # "los 12 modulos..."
		for k in p.ev.obj: p.ev.obj[k]["texto"] = Operacion.texto_objetivo(k, p.ev.obj[k]["texto"], p.ev.op.d)
	var V = p.ordenes["viento"] if p.ordenes["viento"] != null else p.sala.get("viento")   # el viento de la sala (o el que haya mandado el profesor despues)
	if V != null and not p.ev.get_meta("viento_profesor", false):
		p.ent.configurar_viento(float(V["vel"]), float(V["desde"]), bool(V.get("rachas", false))); p.ev.set_meta("viento_profesor", true)
	var P = p.ordenes["persona"]
	if P != null and p.ev.op != null and p.ev.op.d.has("zona") and (float(p.ev.op.d["persona"][0]) != P[0] or float(p.ev.op.d["persona"][1]) != P[1]): mover_desaparecido()
	if p.ordenes.get("fuga") != null and p.ev.op != null and p.ev.op.d.has("racks") and not p.ev.get_meta("fuga_profesor", false): mover_fuga_profesor()
	if not (p.ordenes["zonas"] as Array).is_empty() and not p.ev.obj.has("exclusion"):
		p.ev.obj["exclusion"] = { "texto": p.EXCLUSION_TXT, "estado": "curso" }; p.ev.orden.append("exclusion")

## En cada paso en vuelo: dentro de una zona de exclusion, aviso y objetivo suspendido.
func vigilar_exclusiones() -> void:
	if p.sala.is_empty() or p.ordenes.is_empty() or (p.ordenes["zonas"] as Array).is_empty() or p.ev == null or p.av["estado"] != "volando" or p.av.get("posado", false): return
	for z in p.ordenes["zonas"]:
		if Vector2(p.av["p"][0] - z["N"], p.av["p"][1] - z["E"]).length() < z["r"]:
			p.ev.marcar("exclusion", "mal")
			var t := Time.get_ticks_msec() / 1000.0
			if t - float(p.ordenes["t_aviso"]) > 4: p.ordenes["t_aviso"] = t; p.poner_toast("¡Dentro de una zona de exclusión! Sal de ella")
			return

func _pintar_ordenes() -> void:
	if not p.ordenes.is_empty() and float(p.ordenes["aterrizar"]) > 0 and not p.av.is_empty():   # hasta que aterrice (si ya estaba en el suelo, 8 s)
		var en_suelo: bool = p.av["estado"] != "volando" or p.av.get("posado", false)
		if not en_suelo: p.ordenes["en_aire"] = true
		elif p.ordenes["en_aire"] or Time.get_ticks_msec() / 1000.0 - float(p.ordenes["aterrizar"]) > 8: p.ordenes["aterrizar"] = 0.0
	var aterriza: bool = not p.ordenes.is_empty() and float(p.ordenes["aterrizar"]) > 0
	var notam: Array = p.ordenes.get("notam", [])
	var firma := "%s|%s" % [aterriza, "|".join(notam)]
	if aterriza: p.ordenes_hud.modulate.a = 0.55 + 0.45 * absf(sin(Time.get_ticks_msec() / 1000.0 * PI))
	else: p.ordenes_hud.modulate.a = 1.0
	if firma == p._ordenes_firma: return
	p._ordenes_firma = firma
	for c in p.ordenes_hud.get_children(): c.queue_free()
	var caja := func(txt: String, fondo: Color, color: Color, tam: int) -> PanelContainer:
		var pc := PanelContainer.new(); pc.add_theme_stylebox_override("panel", Tema.caja(fondo, Color(0, 0, 0, 0), 10 if tam > 20 else 8, 0, 22 if tam > 20 else 14, 10 if tam > 20 else 5))
		pc.mouse_filter = Control.MOUSE_FILTER_IGNORE; pc.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		var l := Tema.etiqueta(txt, tam, color, true); l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; pc.add_child(l); return pc
	if aterriza: p.ordenes_hud.add_child(caja.call("ATERRIZA YA · orden del profesor", Color(0.83, 0.18, 0.18, 0.95), Color.WHITE, 26))
	for t in notam: p.ordenes_hud.add_child(caja.call("NOTAM · " + String(t), Color(1, 0.72, 0.3, 0.92), Color("#1a1000"), 14))

## Zonas de exclusion en 3D: cilindros rojos translucidos del suelo a 120 m (ponerExclusiones de la web).
func _poner_exclusiones() -> void:
	if p._exclusiones != null: p._exclusiones.queue_free(); p._exclusiones = null
	if p.ordenes.is_empty() or (p.ordenes["zonas"] as Array).is_empty(): return
	p._exclusiones = Node3D.new(); p.add_child(p._exclusiones)
	var mat := StandardMaterial3D.new(); mat.albedo_color = Color(0.9, 0.22, 0.21, 0.18); mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var borde := mat.duplicate(); borde.albedo_color = Color(0.9, 0.22, 0.21, 0.7)
	for z in p.ordenes["zonas"]:
		var y: float = p.ent.altura(z["N"], z["E"]) if p.en_mundo() else 0.0
		var cm := CylinderMesh.new(); cm.top_radius = z["r"]; cm.bottom_radius = z["r"]; cm.height = 120; cm.cap_top = false; cm.cap_bottom = false; cm.radial_segments = 48
		var c := MeshInstance3D.new(); c.mesh = cm; c.material_override = mat; c.position = Vector3(z["E"], y + 60, -z["N"]); p._exclusiones.add_child(c)
		for h in [0.5, 120.0]:
			var tm := TorusMesh.new(); tm.inner_radius = z["r"] - 0.6; tm.outer_radius = z["r"] + 0.6; tm.rings = 64
			var a := MeshInstance3D.new(); a.mesh = tm; a.material_override = borde; a.position = Vector3(z["E"], y + h, -z["N"]); a.scale = Vector3(1, 0.05, 1); p._exclusiones.add_child(a)

## Manda el estado propio y recoge el de los demas (enviarSala de la web).
func _enviar_sala() -> void:
	if p.sala.is_empty() or p._multi_enviando or p.av.is_empty() or p.modelo == null: return
	p._multi_enviando = true
	# objetivos: cumplidos, total y fallados (las normas siguen "en curso" hasta aterrizar); y lo que va haciendo en el trabajo
	var ok := 0; var tot := 0; var mal := 0; var ahora := ""
	if p.ev != null:
		for k in p.ev.obj:
			tot += 1
			if p.ev.obj[k]["estado"] == "ok": ok += 1
			elif p.ev.obj[k]["estado"] == "mal": mal += 1
		var guia = p.ev.op if p.ev.op != null else p.ev.fpv
		if guia != null:
			var re := RegEx.new(); re.compile("<[^>]+>"); ahora = re.sub(guia.ahora(p.ev.obj, p.av), "", true).left(160)
	var e := { "id": multi_id(), "nombre": nombre_piloto(), "alumno": p.sesion["alumno"]["id"] if p.sesion["alumno"] != null else null, "avion": p.sesion["avion"], "p": p.av["p"], "q": p.av["q"], "vn": Cuat.rot(p.av["q"], p.av.get("v", [0.0, 0.0, 0.0])),
			   "estado": p.av["estado"], "gas": p.av.get("gases", 0.0), "agl": p.av.get("agl", 0.0), "objs": [ok, tot, mal] if p.ev != null else null, "ahora": ahora,
			   "tvuelo": p.vuelo["tVuelo"] if p.vuelo != null else 0.0, "final": p.vuelo["final"] if p.vuelo != null else null, "gimbal": p.av.get("gimbal", 0.0) }
	if p.es_bipode():
		e["bip"] = [p.av["cintura"], p.av["brazos"], p.av["fase"], p.av["amp"], p.av["angCanones"], p.av["disparos"], p.av["puno"]]
		if p.juego_bip != null: e["golpes"] = p.juego_bip.golpes
	if p.carrera_mejor != null and p.ev != null and p.ev.op != null and p.ev.op.carr != null: e["carrera"] = snappedf(p.carrera_mejor["t"], 0.01)   # carrera: el mejor de la sesion
	var cm_e := p.app_apps_dron.cam_dji(); e["cam"] = p.camara; e["zoom"] = float(cm_e["zoom"]); e["ter"] = bool(cm_e["termica"])            # lo que ve el piloto (vista del alumno del profesor)
	if p.av.has("torreta"): e["tor"] = [float(p.av["torreta"]["pan"]), float(p.av["torreta"]["tilt"])]
	var cod: String = p.sala["codigo"]
	var r: Dictionary = await p.aula.api("POST", "salas/%s/estado" % cod, e)
	p._multi_enviando = false
	if p.sala.is_empty() or p.sala["codigo"] != cod: return
	if r["ok"]:
		var t := Time.get_ticks_msec() / 1000.0; var vivos := {}
		for o in r["datos"]["otros"]:
			if not _estado_valido(o): continue          # posicion u orientacion que no son numeros, o vehiculo que no existe: se ignora
			o["recibido"] = t; p.multi_otros[o["id"]] = o; vivos[o["id"]] = true; p.app_vuelo._impactos_de(o)
		for k in p.multi_otros.keys():
			if not vivos.has(k): p.multi_otros.erase(k)
		aplicar_ordenes(r["datos"].get("ordenes", []))
		var sd = r["datos"].get("sala"); var rec = sd.get("record") if sd is Dictionary else null
		p.sala["record"] = rec if (rec is Dictionary and (rec.get("t") is float or rec.get("t") is int)) else null
	elif r["status"] == 404: p.poner_toast("La sala se ha cerrado"); salir_sala()
	elif r["status"] == 403: salir_sala(); p.app_pantallas.ir_inicio(); p.app_pantallas.confirmar("Fuera de la sala", Tema.bb(String(r["error"])), "Vale")   # expulsado por el profesor

## Un estado de otro jugador que se puede usar (estadoValido de la web): id, p de 3 y q de 4 numeros finitos, vn de 3 si
## viene, y un vehiculo que exista en aviones/.
static func _nums_finitos(a, n: int) -> bool:
	if not (a is Array) or a.size() != n: return false
	for x in a:
		if not (x is float or x is int) or (x is float and not is_finite(x)): return false
	return true

static func _nums_finitos_min(a, n: int) -> bool:
	return a is Array and a.size() >= n and _nums_finitos(a.slice(0, n), n)

func _estado_valido(o) -> bool:
	if not (o is Dictionary) or not (o.get("id") is String) or not _nums_finitos(o.get("p"), 3) or not _nums_finitos(o.get("q"), 4): return false
	if o.get("vn") != null and not _nums_finitos(o.get("vn"), 3): return false
	for k in ["estado", "nombre", "final", "ahora"]:
		if o.get(k) != null and not (o.get(k) is String): return false
	for k in ["gas", "agl", "gimbal", "tvuelo"]:
		var x = o.get(k)
		if x != null and not (x is int or (x is float and is_finite(x))): return false
	if o.get("objs") != null and not _nums_finitos_min(o.get("objs"), 2): return false
	if o.get("bip") != null and not _nums_finitos_min(o.get("bip"), 7): return false
	if o.get("golpes") != null and not (o.get("golpes") is Dictionary): return false
	return o.get("avion") is String and p.ids_aviones.has(o["avion"])

## Los demas como fantasmas: su modelo y su nombre encima; la posicion, la ultima recibida avanzada con su velocidad (como
## mucho 0,3 s) y suavizada (ponerFantasmas de la web).
func _poner_fantasmas() -> void:
	var ahora := Time.get_ticks_msec() / 1000.0; var vivos := {}
	for id in p.multi_otros:
		var f: Dictionary = p.multi_otros[id]; vivos[id] = true
		var g = p._fantasmas.get(id)
		if g == null or g["avion"] != f["avion"] or g["nombre"] != f["nombre"]:
			if g != null: g["nodo"].queue_free(); g["et"].queue_free()
			var datos := DatosComunes.avion(String(f["avion"]))
			if datos.is_empty(): continue
			var nodo := Avion3D.new(datos); p.add_child(nodo)
			var et := Label3D.new(); et.text = String(f["nombre"]); et.billboard = BaseMaterial3D.BILLBOARD_ENABLED; et.fixed_size = true; et.pixel_size = 0.0009
			et.font_size = 26; et.outline_size = 8; et.modulate = Color("#4fc3f7"); et.no_depth_test = true; et.font = Tema.negrita; p.add_child(et)
			g = { "nodo": nodo, "et": et, "p": (f["p"] as Array).duplicate(), "avion": f["avion"], "nombre": f["nombre"] }; p._fantasmas[id] = g
		var dt := minf(0.3, ahora - float(f["recibido"])); var vn: Array = f.get("vn", [0.0, 0.0, 0.0])
		var obj := [f["p"][0] + vn[0] * dt, f["p"][1] + vn[1] * dt, f["p"][2] + vn[2] * dt]
		var lejos := Vector3(obj[0] - g["p"][0], obj[1] - g["p"][1], obj[2] - g["p"][2]).length() > 30
		for i in 3: g["p"][i] = obj[i] if lejos else g["p"][i] + (obj[i] - g["p"][i]) * 0.35
		var gas: float = f.get("gas", 0.0)
		var est := { "p": g["p"], "q": f["q"], "de": 0.0, "dr": 0.0, "da": 0.0, "gases": gas, "estado": f.get("estado", "volando"),
					 "gimbal": f.get("gimbal", 0.0) if f.get("gimbal") != null else 0.0, "motores": [gas, gas, gas, gas] }
		var bp = f.get("bip")
		if bp is Array and bp.size() >= 7:            # bipode de otro jugador: paso, cintura, brazos, cañones y puño
			est.merge({ "cintura": float(bp[0]), "brazos": float(bp[1]), "fase": float(bp[2]), "amp": float(bp[3]), "angCanones": float(bp[4]), "disparos": int(bp[5]), "puno": float(bp[6]) })
		g["nodo"].actualizar(est)
		g["et"].position = Avion3D.ned(g["p"]) + Vector3(0, 4.2 if g["nodo"].bipode else 1.2, 0)
	for id in p._fantasmas.keys():
		if not vivos.has(id): p._fantasmas[id]["nodo"].queue_free(); p._fantasmas[id]["et"].queue_free(); p._fantasmas.erase(id)

## Panel de la sala en vuelo: quien esta y como va.
func _pintar_sala_info() -> void:
	p.sala_info.visible = not p.sala.is_empty() and p.pantalla_actual == ""
	if p.briefing.visible and p.pantalla_actual != "": p.briefing.visible = false
	if not p.sala_info.visible: return
	var t := "[color=#4fc3f7][b]Sala %s[/b][/color] · %s" % [Tema.bb(String(p.sala["codigo"])), Tema.bb(String(p.sala.get("nombre", "")))]
	if p.multi_otros.is_empty(): t += "\nTodavía no hay nadie más"
	for id in p.multi_otros:
		var o: Dictionary = p.multi_otros[id]; var objs = o.get("objs")
		t += "\n● %s · %s · %s%s" % [Tema.bb(String(o.get("nombre", ""))), Tema.bb(String(DatosComunes.avion(String(o["avion"])).get("nombre", o["avion"]))),
			("%d m" % int(round(maxf(0, o.get("agl", 0.0))))) if o.get("estado", "") == "volando" else String(o.get("estado", "")),
			(" · %d✔%s de %d" % [objs[0], (" %d✘" % objs[2]) if objs.size() > 2 and objs[2] > 0 else "", objs[1]]) if objs != null and objs[1] > 0 else ""]
	p.sala_info_rt.text = t
