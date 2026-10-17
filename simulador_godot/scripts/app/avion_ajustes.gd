class_name AppAvionAjustes
extends RefCounted
## Avion y viento: guardado de los ajustes, centro de gravedad y peso, emisora y calibracion, dificultad, el robot y la prueba del lanzamiento a mano.
## Parte de principal.gd (como js/app/avion_ajustes.js de la web): el estado esta en principal.gd (p).

var p: Principal

func _init(principal: Principal) -> void: p = principal

func _cargar() -> void:
	var cf := ConfigFile.new()
	if cf.load("user://simulador.cfg") != OK: return
	for k in ["avion", "dificultad", "viento", "lanz"]:
		if cf.has_section_key("sesion", k): p.sesion[k] = cf.get_value("sesion", k)
	for k in p.aj.keys():
		if cf.has_section_key("ajustes", k): p.aj[k] = cf.get_value("ajustes", k)
	if int(p.aj.get("zoom_v", 0)) < 2: p.aj["zoom_piloto"] = 0.03; p.aj["zoom_v"] = 2      # nuevo por defecto del zoom del piloto: 3 %

func _guardar() -> void:
	var cf := ConfigFile.new()
	for k in ["avion", "dificultad", "viento", "lanz"]: cf.set_value("sesion", k, p.sesion[k])
	for k in p.aj.keys(): cf.set_value("ajustes", k, p.aj[k])
	cf.save("user://simulador.cfg")

func guardar_sesion() -> void: _guardar()

func guardar_ajustes() -> void: _guardar()

func cm_diseno(A: Dictionary) -> Dictionary:
	return { "cg": int(round((A["cg_mm"][0] - A["x_le_mm"]) / (A["c_m"] * 1000) * 100)), "masa": int(round(A["masa_kg"] * 100) * 10) }

func cm_actual(id: String) -> Dictionary:
	return p.aj["cm"][id] if p.aj["cm"].has(id) else cm_diseno(DatosComunes.avion(id))

func cm_es_diseno(id: String) -> bool:
	var A := DatosComunes.avion(id)
	if not A.has("x_le_mm"): return true
	var a := cm_actual(id); var d := cm_diseno(A)
	return int(a["cg"]) == d["cg"] and int(a["masa"]) == d["masa"]

func poner_cm(id: String, cg: int, masa: int) -> void:
	p.aj["cm"][id] = { "cg": cg, "masa": masa }; _guardar()

func borrar_cm(id: String) -> void:
	p.aj["cm"].erase(id); _guardar()

func cfg_de(id: String) -> Dictionary:
	var c := { "drAlabeo": 100.0, "drProf": 100.0, "empuje": "", "res": 100.0, "temp": 20.0, "lanzReal": true }
	c.merge(p.aj["cfg_avion"].get(id, {}), true)
	return c

func poner_cfg(id: String, c: Dictionary) -> void:
	p.aj["cfg_avion"][id] = c; _guardar()

func recorrido_mecanico(id: String) -> Dictionary:
	if p.RECORRIDO_MECANICO.has(id): return p.RECORRIDO_MECANICO[id]
	return DatosComunes.avion(id).get("mandos", {}).get("mecanico", {})

func texto_cm() -> String:
	var c := cm_actual(p.sesion["avion"])
	return "CG y peso de diseño" if cm_es_diseno(p.sesion["avion"]) else "CG %d %% de la cuerda · %d g" % [int(c["cg"]), int(c["masa"])]

func calidad_actual() -> int:
	var m: String = p.aj.get("calidad_modo", "auto")
	if minimo(): return 0
	return 2 if m == "auto" else int(m)

## Rendimiento maximo (Ajustes; con la calidad automatica, en una tableta o un movil): la calidad 0, media resolucion
## y el mundo real con materiales sencillos (Mundo3D.minimo). Visor.minimo de la web.
func minimo() -> bool:
	var m: String = p.aj.get("calidad_modo", "auto")
	return m == "min" or (m == "auto" and OS.has_feature("mobile"))

func poner_zoom_piloto(z: float) -> void:
	p.aj["zoom_piloto"] = z; _guardar()
	if p.pantallas.has("pAjustes"): p.pantallas["pAjustes"].refrescar()

func sonido_on(x: bool) -> void:
	p.sonido.on = x; p.sonido.guardar_cfg()
	if x: p.sonido.iniciar()
	p.sonido.silenciar(not x or p.pantalla_actual != "" or p.pausado)

func sonido_volumen(x: float) -> void:
	p.sonido.vol = x; p.sonido.guardar_cfg()

func crear_modelo(id: String):
	var A := DatosComunes.avion(id)
	if A.get("tipo", "") == "fpv": return ModeloFPV.new(A)
	if A.get("tipo", "") == "bipode": return ModeloBipode.new(A)
	return ModeloCuadricoptero.new(A) if A.get("tipo", "") == "cuadricoptero" else ModeloAvion.new(A)

func robot_desbloqueado() -> bool:
	var al = p.sesion["alumno"]
	return al != null and al.get("progreso") is Dictionary and bool(al["progreso"].get("robot", false))

## Los vehiculos del hangar: el robot, solo con los logros.
func ids_hangar() -> Array:
	var v := robot_desbloqueado()
	return p.ids_aviones.filter(func(id): return v or not DatosComunes.avion(id).get("oculto", false))

## Si el vehiculo elegido es el robot y este piloto no lo tiene, vuelve al dron comercial.
func vehiculo_permitido() -> void:
	if p.ids_aviones.has(p.sesion["avion"]) and DatosComunes.avion(p.sesion["avion"]).get("oculto", false) and not robot_desbloqueado():
		p.app_pantallas.elegir_avion("DJI_MINI" if p.ids_aviones.has("DJI_MINI") else ids_hangar()[0])

func poner_toast_menu(txt: String) -> void:
	var l := Tema.etiqueta(txt, 22, Tema.ACENTO, true); l.set_anchors_preset(Control.PRESET_CENTER_TOP); l.position.y = 90
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85)); l.add_theme_constant_override("shadow_outline_size", 6)
	p.ui.get_child(0).add_child(l); l.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.get_tree().create_timer(1.6).timeout.connect(func(): l.queue_free())

func aplicar_cm(m) -> void:
	var A := DatosComunes.avion(p.sesion["avion"])
	if not A.has("x_le_mm") or cm_es_diseno(p.sesion["avion"]): return     # los valores de diseno exactos (sin redondear)
	var c := cm_actual(p.sesion["avion"])
	m.configurar({ "masa_kg": c["masa"] / 1000.0, "cg_mm": A["x_le_mm"] + c["cg"] / 100.0 * A["c_m"] * 1000 })

func aplicar_calibracion(m) -> void:
	var c := cfg_de(p.sesion["avion"])
	m.configurar({ "temperatura": float(c["temp"]), "empuje_gf": String(c["empuje"]).to_float() if String(c["empuje"]) != "" else 0.0, "resistencia": float(c["res"]) / 100.0 })
	p.sesion["lanz_real"] = c["lanzReal"]
	m.set_meta("mandos_base", m.mandos.duplicate()); m.set_meta("fuente", "")

func aplicar_dificultad(m) -> void:
	m.facil = p.sesion["dificultad"] == "facil"; p.ent.facil = m.facil

## Con mando: recorridos mecanicos por el dual rate y sin la exponencial del simulador. Con teclado: los del simulador.
func aplicar_recorridos(mod = null, forzar_mando := false) -> void:
	if mod == null: mod = p.modelo
	if mod == null or mod is ModeloCuadricoptero or not mod.has_meta("mandos_base"): return
	var fuente := "mando" if (p._mando_usado or forzar_mando) else "teclado"
	if mod.get_meta("fuente") == fuente: return
	mod.set_meta("fuente", fuente)
	var B: Dictionary = mod.get_meta("mandos_base"); var m := B.duplicate()
	if fuente == "mando":
		var c := cfg_de(p.sesion["avion"]); var mec := recorrido_mecanico(p.sesion["avion"])
		m["expo"] = 0.0
		m["prof_max_grados"] = mec.get("prof", B["prof_max_grados"]) * c["drProf"] / 100.0
		if B.get("aleron_max_grados", 0): m["aleron_max_grados"] = mec.get("aleron", B["aleron_max_grados"]) * c["drAlabeo"] / 100.0
		if B.get("timon_max_grados", 0): m["timon_max_grados"] = mec.get("timon", B["timon_max_grados"]) * c["drAlabeo"] / 100.0
	mod.mandos = m

func _vel_perdida() -> float:
	if p.modelo is ModeloBipode: return 0.0
	var A := DatosComunes.avion(p.sesion["avion"])
	for fila in A.get("caracteristicas", []):
		if String(fila[0]).to_lower().begins_with("velocidad de p"):
			var v := String(fila[1]).replace(",", ".").to_float()
			if v > 0: return v
	return sqrt(2 * p.modelo.masa_kg * p.G0 / (p.RHO * p.modelo.S_m2 * 1.1))

func prueba_lanzamiento(gas: float, op: Dictionary) -> bool:
	var m = crear_modelo(p.sesion["avion"]); aplicar_cm(m); aplicar_calibracion(m); aplicar_recorridos(m, true); aplicar_dificultad(m)
	if op.has("masa_kg"): m.configurar({ "masa_kg": op["masa_kg"] })
	var a: Dictionary = m.estado_inicial(); p.app_evaluacion.colocar_en_base(a, m); a["gases"] = gas; m.lanzar(a)
	var rumbo: float = op.get("rumbo", 0.0)
	if not p.ent.mundo.is_empty(): rumbo = float(p.sesion["lanz"].get("rumbo", 0)) * p.D2R if not p.sesion["lanz"].is_empty() else 0.0
	if rumbo != 0:
		var e := Cuat.euler(a["q"]); a["q"] = Cuat.desde_euler(e[0], e[1], rumbo)
	var mm := { "pitch": 0.0, "yaw": 0.0, "trim": op.get("trim", m.compensador_grados) }
	var viento: Array = op.get("viento", [0.0, 0.0, 0.0])
	for i in int(p.LANZ["prueba_s"] / p.DT):
		# el piloto no toca la profundidad pero si mantiene las alas niveladas (el par del motor alabea el avion al soltarlo)
		var roll: float = Cuat.euler(a["q"])[0]; mm["yaw"] = clampf(-roll * 3 - a["w"][0] * 0.4, -1, 1)
		m.servos(a, mm, p.DT)
		if p.ent.contacto_suelo(a, m.paso(a, viento, p.DT)) != "": return false
	return true

## Gas minimo (0-1) para que salga de la mano, o null si no sale ni con todo el gas.
func gas_minimo_lanzamiento(op: Dictionary):
	if DatosComunes.avion(p.sesion["avion"]).get("tipo", "") in ["cuadricoptero", "fpv"]: return 0.0
	var clave := str([p.sesion["avion"], cm_actual(p.sesion["avion"]), cfg_de(p.sesion["avion"]), p.sesion["dificultad"], p.ent.mundo.is_empty(), p.sesion["lanz"], op])
	if p._cache_gmin.has(clave): return p._cache_gmin[clave]
	var r = null
	if prueba_lanzamiento(1, op):
		var lo := 0.0; var hi := 1.0
		for i in 7:
			var g := (lo + hi) / 2
			if prueba_lanzamiento(g, op): hi = g
			else: lo = g
		r = hi
	p._cache_gmin[clave] = r
	return r

func masa_maxima_lanzamiento(op: Dictionary):
	var d: float = DatosComunes.avion(p.sesion["avion"])["masa_kg"]; var lo := 0.5 * d; var hi := 1.5 * d
	var o := op.duplicate(); o["masa_kg"] = lo
	if not prueba_lanzamiento(1, o): return null
	for i in 7:
		var mk := (lo + hi) / 2; o["masa_kg"] = mk
		if prueba_lanzamiento(1, o): lo = mk
		else: hi = mk
	return lo

func pct_gas(g: float) -> int: return int(ceil(g * 100 / 5.0) * 5)

func lanzamiento_actual() -> Dictionary:
	var vto: Dictionary = p.ent.viento; var rumbo := PI if Escenarios.zona_de(p.sesion["escenario"]) == 2 else 0.0
	var op := { "viento": [vto["base"] * cos(vto["rumbo"]), vto["base"] * sin(vto["rumbo"]), 0.0], "rumbo": rumbo, "trim": p.mando["trim"] }
	var clave := str([p.sesion["avion"], p.modelo.masa_kg, p.modelo.dcg, op])
	if p._cache_lanz["clave"] != clave: p._cache_lanz = { "clave": clave, "op": op, "gmin": gas_minimo_lanzamiento(op), "mmax": -1.0, "gminDiseno": -1.0, "sinViento": -1.0 }
	return p._cache_lanz

func texto_peso_lanz(L: Dictionary) -> String:
	var d: float = DatosComunes.avion(p.sesion["avion"])["masa_kg"]; var extra := int(round((p.modelo.masa_kg - d) * 1000))
	if p.modelo.masa_kg < d * 1.05: return ""
	if typeof(L["gminDiseno"]) == TYPE_FLOAT and L["gminDiseno"] == -1.0:
		var o: Dictionary = L["op"].duplicate(); o["masa_kg"] = d; L["gminDiseno"] = gas_minimo_lanzamiento(o)
	return " Es por el peso: lleva %d g de más%s." % [extra, (" (con el peso de diseño bastaría el %d %%)" % pct_gas(L["gminDiseno"])) if L["gminDiseno"] != null else ""]

## Gas minimo SIN viento (o null): si con todo el gas no sale pero sin viento si, lo tira el viento, no el peso (gasSinViento).
func gas_sin_viento(L: Dictionary):
	if typeof(L["sinViento"]) == TYPE_FLOAT and L["sinViento"] == -1.0:
		var o: Dictionary = L["op"].duplicate(); o["viento"] = [0.0, 0.0, 0.0]; L["sinViento"] = gas_minimo_lanzamiento(o)
	return L["sinViento"]

func texto_viento_lanz() -> String:
	var v: Dictionary = p.ent.viento; var desde := fposmod(v["rumbo"] * p.R2D + 180, 360)
	return "%d m/s del %s" % [int(round(v["base"])), p.RUMBOS_TXT[int(round(desde / 45)) % 8]]

func aviso_lanzamiento() -> String:
	if p.con_tren(): return ""                 # avion de pista: no se lanza a mano
	if p.es_dron(): return ""
	var L := lanzamiento_actual()
	if L["gmin"] == null and gas_sin_viento(L) != null:
		return "⚠ Con este viento (%s) no saldría de la mano sin tocar los mandos: lánzalo de cara al viento o prepárate para corregir con la profundidad nada más soltarlo." % texto_viento_lanz()
	if L["gmin"] == null: return "⚠ Pesa demasiado para lanzarlo a mano (%d g): no saldría ni con todo el gas. Quítale peso en la pantalla del avión." % int(round(p.modelo.masa_kg * 1000))
	if p.av["gases"] < L["gmin"]: return "⚠ Con el %d %% de gas no saldría de la mano: sube el gas al menos al %d %% (W)." % [int(round(p.av["gases"] * 100)), pct_gas(L["gmin"])] + texto_peso_lanz(L)
	return ""

func causa_lanzamiento_fallido(gas: float) -> Dictionary:
	var L := lanzamiento_actual(); var masa := int(round(p.modelo.masa_kg * 1000))
	if L["gmin"] == null and gas_sin_viento(L) != null:
		return { "corto": "viento", "texto": "con este viento (%s) no sale de la mano sin tocar los mandos: se encabrita, entra en pérdida y cae. Lánzalo de cara al viento y, al soltarlo, baja un poco el morro." % texto_viento_lanz() }
	if L["gmin"] == null:
		if typeof(L["mmax"]) == TYPE_FLOAT and L["mmax"] == -1.0: L["mmax"] = masa_maxima_lanzamiento(L["op"])
		if L["mmax"] != null: return { "corto": "demasiado peso", "texto": "pesa demasiado para lanzarlo a mano (%d g): no sale ni con todo el gas. Con el 100 %% sale hasta unos %d g." % [masa, int(floor(L["mmax"] * 100) * 10)] }
		return { "corto": "centro de gravedad", "texto": "no sale de la mano ni con todo el gas ni con poco peso: revisa el centro de gravedad." }
	if gas < L["gmin"]:
		var pp := texto_peso_lanz(L)
		return { "corto": "poco gas para su peso" if pp != "" else "poco gas", "texto": "con el %d %% de gas no tiene empuje para salir de la mano con %d g: lánzalo con al menos el %d %%." % [int(round(gas * 100)), masa, pct_gas(L["gmin"])] + pp }
	return { "corto": "mandos", "texto": "con el %d %% de gas salía bien sin tocar los mandos: el fallo fue de los mandos (tirar o empujar de más nada más lanzarlo) o una racha." % int(round(gas * 100)) }
