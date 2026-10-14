extends Node3D
## Simulador de vuelo RC, version 2 (Godot 4). Es la MISMA aplicacion que la version 1 (simulador/simulador.html): las
## mismas pantallas (inicio, pilotos, hangar, entrenamientos, vuelo libre, punto de lanzamiento, ajustes, resultado y
## progreso), el mismo HUD, las mismas misiones (simulador/escenarios.js), el aula (servidor o registro local), la caja
## negra, la repeticion, el sonido y el DJI con su app. Los aviones, el mundo y la fisica son comunes (modelo_avion.gd,
## modelo_cuadricoptero.gd y entorno.gd traducen modelos.js, DJI_MINI.js y entorno.js; ver pruebas/). Este fichero es
## la parte <script> de simulador.html: sesion, navegacion entre pantallas, vuelo (500 pasos por segundo), teclado,
## mando, camaras y HUD. Lo que se dibuja esta en las pantallas (pantalla_*.gd), hud_vuelo.gd, hud_dji.gd y capas.gd.
##
## Opciones de linea de ordenes (tras --), para pruebas: --auto (vuela sin menu), --escenario=ID (libre_cartagena),
## --avion=ID, --camara=N, --gases=0..1, --esperar=S, --captura=ruta.png (guarda la pantalla a los S segundos y sale),
## --pantalla=pInicio|pHangar|... (captura de una pantalla), --calidad=0..2, --dificultad=real|facil, --cenital=H, --traza,
## --terminar=S (termina el vuelo a los S s de vuelo: captura del resultado), --pausa=S y --ayuda=S (pausa o controles a los S s),
## --repeticion (con --terminar: abre la repeticion desde el resultado), --lat=G --lon=G [--rumbo=G] (punto de despegue en un mundo real), --destacado[=K] (el punto destacado K del mapa, 1 = el CIFP, 2 = Los Halcones).

const DT := 1.0 / 500
const D2R := PI / 180.0
const R2D := 180.0 / PI
const G0 := 9.81
const RHO := 1.225
const CN_CADA := 25
const LANZ := { "prueba_s": 5.0, "fallo_s": 6.0, "fallo_h": 5.0 }
const MUNDO := "cartagena"
const LANZ_DEFECTO := { "cartagena": { "lat": 37.648889, "lon": -1.193194, "rumbo": 90 } }   # 37°38'56.0"N 1°11'35.5"W, hacia el este
# recorrido mecanico (grados a palanca a tope sin dual rate) de cada avion: el mismo que en simulador.html
const RECORRIDO_MECANICO := { "E1": { "prof": 12, "timon": 15 }, "E2": { "prof": 12, "aleron": 15 }, "E3": { "prof": 12, "aleron": 15 }, "T1": { "prof": 15, "aleron": 15 } }
const DIFICULTAD_INFO := {
	"real": "Par y estela de la hélice (el avión tiende a alabear y guiñar a la izquierda con gas), efecto P y giroscópico, pérdida por semiala (cae de un ala, puede entrar en barrena), efecto suelo, resistencia de perfil y de la hélice parada, viento más flojo junto al suelo, turbulencia que alabea, densidad según la temperatura, calibración con el avión real y lanzamiento con dispersión.",
	"facil": "Sin par ni estela de la hélice, sin efectos P ni giroscópico, pérdida simétrica, sin efecto suelo, el mismo viento a cualquier altura, rachas sin alabeo, aire estándar y lanzamiento perfecto. Para aprender; el avión real se parece más al modo real." }
const CN_COLUMNAS := ["t_s", "x_norte_m", "y_este_m", "z_altura_m", "vel_aire_ms", "vel_suelo_ms", "vel_vertical_ms",
	"alabeo_grados", "cabeceo_grados", "rumbo_grados", "alfa_grados", "resbale_grados", "carga_g",
	"gases_pct", "motor_rpm", "empuje_N", "energia_Wh", "bateria_pct", "palanca_profundidad", "palanca_timon",
	"compensador_grados", "profundidad_grados", "timon_grados", "aleron_grados", "viento_norte_ms", "viento_este_ms", "perdida"]
const NOMBRES_MODO := { "C": "Cine", "N": "Normal", "S": "Sport" }

# ---- sesion y ajustes (se guardan en user://) ----
var sesion := { "alumno": null, "sin_registrar": false, "avion": "", "escenario": "libre", "viento": { "vel": 2.0, "desde": 0, "rachas": true },
				"dificultad": "real", "lanz": {}, "lanz_real": true }
var aj := { "calidad_modo": "auto", "zoom_piloto": 0.03, "zoom_v": 0, "cn_auto": false, "cm": {}, "cfg_avion": {} }
var sitio_sel := "libre"
var ids_aviones := []

# ---- vuelo ----
var ent := Entorno.new()
var _ent_campo := Entorno.new()     # el campo del club (para las fichas de las misiones, aunque se este en un mundo real)
var modelo                          # ModeloAvion o ModeloCuadricoptero
var av := {}
var mando := { "pitch": 0.0, "yaw": 0.0, "pitchObj": 0.0, "yawObj": 0.0, "trim": 0.0, "guinada": 0.0, "vz": 0.0, "guinadaObj": 0.0, "vzObj": 0.0, "gimbal": 0.0 }
var vuelo = null                    # registro del vuelo en curso (de L al final)
var ultimo_vuelo = null
var ev: Escenarios.Evaluador = null
var cn_contador := 0
var casa := { "N": 0.0, "E": 0.0 }
var vel_perdida := 8.0
var camara := 1
var era_dron := false
var sin_instrumentos := false
var mostrar_hud := false
var pausado := false
var salir_tras := false
var pantalla_actual := "pInicio"
var DJI := { "grabando": false, "tRec": 0.0, "fotos": 0, "video": false, "tAnt": 0.0 }
var REP := { "activa": false, "filas": [], "t": 0.0, "dur": 0.0, "pausa": false, "i": 0, "vuelo": null }
var rep_activa := false
var _acum := 0.0
var _t_obj := 0.0
var _vs := 0.0
var _fov1 := -1.0
var _mando_usado := false
var _gas_fpv_mando := false          # FPV con mando de consola: la palanca del gas manda (gasFpv de la web)
var _botones_antes := {}
var _cache_lanz := { "clave": null }
var _cache_gmin := {}

# ---- mundo y dibujo ----
var mundo_datos := {}
var indice_zonas := []
var zonas_cache := {}
var orto := []                      # [Image, ImageTexture] de la region
var mundo3d: Mundo3D
var campo3d: Campo3D
var vista: Node3D                   # el mundo puesto (mundo3d o campo3d)
var avion3d: Avion3D
var cam: Camera3D

# ---- interfaz ----
var aula: Aula
var mando_cfg := MandoCfg.new()
var sonido: Sonido
var ui: CanvasLayer
var hud: HudVuelo
var hud_dji: HudDji
var briefing: PanelContainer; var briefing_img: TextureRect
var hud_fpv: HudFPV                 # OSD de Betaflight del dron FPV
var pantallas := {}
var condiciones: PantallaMisiones.Condiciones
var pausa := {}
var carga := {}
var modal := {}
var dialogo: FileDialog
signal _modal_resp(si: bool)

var _args := {}
var _t_auto := 0.0
var _rend := []
var _us := []                      # pruebas: microsegundos de la fisica y de todo _process de esta escena

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	get_window().title = "Entrenador de vuelo RC"
	ids_aviones = DatosComunes.aviones()
	_cargar()
	if _args.has("avion"): sesion["avion"] = _args["avion"]
	if _args.has("calidad"): aj["calidad_modo"] = str(int(_args["calidad"]))
	if _args.has("dificultad"): sesion["dificultad"] = _args["dificultad"]
	if not ids_aviones.has(sesion["avion"]): sesion["avion"] = ids_aviones[0]
	mundo_datos = DatosComunes.mundo(MUNDO)
	ent.poner_mundo(mundo_datos); ent.poner_mundo({})      # el terreno del mundo queda guardado (mapa, rumbo despejado)
	indice_zonas = DatosComunes.indice_zonas().filter(func(z): return z["mundo"] == MUNDO)
	orto = Mundo3D.cargar_orto_region(MUNDO)
	cam = Camera3D.new(); cam.near = 0.05; cam.far = 16000.0; cam.fov = 50; add_child(cam); cam.current = true
	aula = Aula.new(); add_child(aula)
	sonido = Sonido.new(); add_child(sonido); sonido.cargar_cfg()
	_construir_ui()
	if _args.has("auto"):
		sesion["escenario"] = _args.get("escenario", "libre_cartagena"); sesion["sin_registrar"] = true
		var O: Dictionary = Escenarios.datos()[sesion["escenario"]].get("operacion", {})       # pruebas: un trabajo, desde su punto de despegue
		if not O.is_empty(): sesion["lanz"] = { "mundo": mundo_datos["id"], "N": float(O["salida"]["n"]), "E": float(O["salida"]["e"]), "rumbo": float(O["salida"]["rumbo"]) }
		if Escenarios.es_mundo(sesion["escenario"]): _lanz_por_defecto()
		if _args.has("destacado") and not destacados_lanz().is_empty(): elegir_destacado(destacados_lanz()[clampi(int(_args["destacado"]) - 1, 0, destacados_lanz().size() - 1)])      # pruebas: despegar del CIFP
		if _args.has("lat") and _args.has("lon"):      # pruebas: despegar desde (lat, lon) con el rumbo dado o el mas despejado
			var ne := lat_lon_a_ne(mundo_datos, float(_args["lat"]), float(_args["lon"]))
			sesion["lanz"] = { "mundo": mundo_datos["id"], "N": round(ne[0]), "E": round(ne[1]),
							   "rumbo": float(_args["rumbo"]) if _args.has("rumbo") else rumbo_despejado(ne[0], ne[1]) }
		call_deferred("empezar")
		return
	await aula.iniciar(); await perfil_al_arrancar()
	ir_inicio()
	if _args.has("pantalla"):
		var id: String = _args["pantalla"]
		match id:
			"pHangar": ir_hangar()
			"pEntrenamientos": ir_entrenamientos()
			"pVolar": ir_volar()
			"pOperaciones": ir_operaciones()
			"pAjustes": ir_ajustes(_args.get("seccion", ""))
			"pAlumno": ir_pilotos(ir_inicio)
			"pLanzamiento":
				sesion["escenario"] = "libre_cartagena"; ir_lanzamiento()
				if _args.has("destacado") and not destacados_lanz().is_empty(): elegir_destacado(destacados_lanz()[clampi(int(_args["destacado"]) - 1, 0, destacados_lanz().size() - 1)]); pantallas["pLanzamiento"].pintar()
	if _args.has("captura"):
		await get_tree().create_timer(float(_args.get("esperar", "2"))).timeout
		get_viewport().get_texture().get_image().save_png(_args["captura"]); get_tree().quit()

# =====================================================================
#  GUARDADO (localStorage de la web)
# =====================================================================
func _cargar() -> void:
	var cf := ConfigFile.new()
	if cf.load("user://simulador.cfg") != OK: return
	for k in ["avion", "dificultad", "viento", "lanz"]:
		if cf.has_section_key("sesion", k): sesion[k] = cf.get_value("sesion", k)
	for k in aj.keys():
		if cf.has_section_key("ajustes", k): aj[k] = cf.get_value("ajustes", k)
	if int(aj.get("zoom_v", 0)) < 2: aj["zoom_piloto"] = 0.03; aj["zoom_v"] = 2      # nuevo por defecto del zoom del piloto: 3 %

func _guardar() -> void:
	var cf := ConfigFile.new()
	for k in ["avion", "dificultad", "viento", "lanz"]: cf.set_value("sesion", k, sesion[k])
	for k in aj.keys(): cf.set_value("ajustes", k, aj[k])
	cf.save("user://simulador.cfg")

func guardar_sesion() -> void: _guardar()
func guardar_ajustes() -> void: _guardar()

# ---- centro de gravedad y peso (cmCfg), emisora y calibracion (cfgAvion) ----
func cm_diseno(A: Dictionary) -> Dictionary:
	return { "cg": int(round((A["cg_mm"][0] - A["x_le_mm"]) / (A["c_m"] * 1000) * 100)), "masa": int(round(A["masa_kg"] * 100) * 10) }
func cm_actual(id: String) -> Dictionary:
	return aj["cm"][id] if aj["cm"].has(id) else cm_diseno(DatosComunes.avion(id))
func cm_es_diseno(id: String) -> bool:
	var A := DatosComunes.avion(id)
	if not A.has("x_le_mm"): return true
	var a := cm_actual(id); var d := cm_diseno(A)
	return int(a["cg"]) == d["cg"] and int(a["masa"]) == d["masa"]
func poner_cm(id: String, cg: int, masa: int) -> void:
	aj["cm"][id] = { "cg": cg, "masa": masa }; _guardar()
func borrar_cm(id: String) -> void:
	aj["cm"].erase(id); _guardar()
func cfg_de(id: String) -> Dictionary:
	var c := { "drAlabeo": 100.0, "drProf": 100.0, "empuje": "", "res": 100.0, "temp": 20.0, "lanzReal": true }
	c.merge(aj["cfg_avion"].get(id, {}), true)
	return c
func poner_cfg(id: String, c: Dictionary) -> void:
	aj["cfg_avion"][id] = c; _guardar()
func recorrido_mecanico(id: String) -> Dictionary:
	if RECORRIDO_MECANICO.has(id): return RECORRIDO_MECANICO[id]
	return DatosComunes.avion(id).get("mandos", {}).get("mecanico", {})
func texto_cm() -> String:
	var c := cm_actual(sesion["avion"])
	return "CG y peso de diseño" if cm_es_diseno(sesion["avion"]) else "CG %d %% de la cuerda · %d g" % [int(c["cg"]), int(c["masa"])]

func calidad_actual() -> int:
	var m: String = aj.get("calidad_modo", "auto")
	return 2 if m == "auto" else int(m)
func poner_zoom_piloto(z: float) -> void:
	aj["zoom_piloto"] = z; _guardar()
	if pantallas.has("pAjustes"): pantallas["pAjustes"].refrescar()
func sonido_on(x: bool) -> void:
	sonido.on = x; sonido.guardar_cfg()
	if x: sonido.iniciar()
	sonido.silenciar(not x or pantalla_actual != "" or pausado)
func sonido_volumen(x: float) -> void:
	sonido.vol = x; sonido.guardar_cfg()

# =====================================================================
#  MODELO DE VUELO: CG y peso, calibracion, recorridos de la emisora y dificultad
# =====================================================================
func crear_modelo(id: String):
	var A := DatosComunes.avion(id)
	if A.get("tipo", "") == "fpv": return ModeloFPV.new(A)
	return ModeloCuadricoptero.new(A) if A.get("tipo", "") == "cuadricoptero" else ModeloAvion.new(A)
func es_dron() -> bool: return modelo is ModeloCuadricoptero or modelo is ModeloFPV
func es_fpv() -> bool: return modelo is ModeloFPV

func aplicar_cm(m) -> void:
	var A := DatosComunes.avion(sesion["avion"])
	if not A.has("x_le_mm") or cm_es_diseno(sesion["avion"]): return     # los valores de diseno exactos (sin redondear)
	var c := cm_actual(sesion["avion"])
	m.configurar({ "masa_kg": c["masa"] / 1000.0, "cg_mm": A["x_le_mm"] + c["cg"] / 100.0 * A["c_m"] * 1000 })
func aplicar_calibracion(m) -> void:
	var c := cfg_de(sesion["avion"])
	m.configurar({ "temperatura": float(c["temp"]), "empuje_gf": String(c["empuje"]).to_float() if String(c["empuje"]) != "" else 0.0, "resistencia": float(c["res"]) / 100.0 })
	sesion["lanz_real"] = c["lanzReal"]
	m.set_meta("mandos_base", m.mandos.duplicate()); m.set_meta("fuente", "")
func aplicar_dificultad(m) -> void:
	m.facil = sesion["dificultad"] == "facil"; ent.facil = m.facil
## Con mando: recorridos mecanicos por el dual rate y sin la exponencial del simulador. Con teclado: los del simulador.
func aplicar_recorridos(mod = null, forzar_mando := false) -> void:
	if mod == null: mod = modelo
	if mod == null or mod is ModeloCuadricoptero or not mod.has_meta("mandos_base"): return
	var fuente := "mando" if (_mando_usado or forzar_mando) else "teclado"
	if mod.get_meta("fuente") == fuente: return
	mod.set_meta("fuente", fuente)
	var B: Dictionary = mod.get_meta("mandos_base"); var m := B.duplicate()
	if fuente == "mando":
		var c := cfg_de(sesion["avion"]); var mec := recorrido_mecanico(sesion["avion"])
		m["expo"] = 0.0
		m["prof_max_grados"] = mec.get("prof", B["prof_max_grados"]) * c["drProf"] / 100.0
		if B.get("aleron_max_grados", 0): m["aleron_max_grados"] = mec.get("aleron", B["aleron_max_grados"]) * c["drAlabeo"] / 100.0
		if B.get("timon_max_grados", 0): m["timon_max_grados"] = mec.get("timon", B["timon_max_grados"]) * c["drAlabeo"] / 100.0
	mod.mandos = m

func _vel_perdida() -> float:
	var A := DatosComunes.avion(sesion["avion"])
	for fila in A.get("caracteristicas", []):
		if String(fila[0]).to_lower().begins_with("velocidad de p"):
			var v := String(fila[1]).replace(",", ".").to_float()
			if v > 0: return v
	return sqrt(2 * modelo.masa_kg * G0 / (RHO * modelo.S_m2 * 1.1))

# =====================================================================
#  LANZAMIENTO A MANO (pruebaLanzamiento, gasMinimoLanzamiento...)
# =====================================================================
func prueba_lanzamiento(gas: float, op: Dictionary) -> bool:
	var m = crear_modelo(sesion["avion"]); aplicar_cm(m); aplicar_calibracion(m); aplicar_recorridos(m, true); aplicar_dificultad(m)
	if op.has("masa_kg"): m.configurar({ "masa_kg": op["masa_kg"] })
	var a: Dictionary = m.estado_inicial(); colocar_en_base(a, m); a["gases"] = gas; m.lanzar(a)
	var rumbo: float = op.get("rumbo", 0.0)
	if not ent.mundo.is_empty(): rumbo = float(sesion["lanz"].get("rumbo", 0)) * D2R if not sesion["lanz"].is_empty() else 0.0
	if rumbo != 0:
		var e := Cuat.euler(a["q"]); a["q"] = Cuat.desde_euler(e[0], e[1], rumbo)
	var mm := { "pitch": 0.0, "yaw": 0.0, "trim": op.get("trim", m.compensador_grados) }
	var viento: Array = op.get("viento", [0.0, 0.0, 0.0])
	for i in int(LANZ["prueba_s"] / DT):
		# el piloto no toca la profundidad pero si mantiene las alas niveladas (el par del motor alabea el avion al soltarlo)
		var roll: float = Cuat.euler(a["q"])[0]; mm["yaw"] = clampf(-roll * 3 - a["w"][0] * 0.4, -1, 1)
		m.servos(a, mm, DT)
		if ent.contacto_suelo(a, m.paso(a, viento, DT)) != "": return false
	return true
## Gas minimo (0-1) para que salga de la mano, o null si no sale ni con todo el gas.
func gas_minimo_lanzamiento(op: Dictionary):
	if DatosComunes.avion(sesion["avion"]).get("tipo", "") in ["cuadricoptero", "fpv"]: return 0.0
	var clave := str([sesion["avion"], cm_actual(sesion["avion"]), cfg_de(sesion["avion"]), sesion["dificultad"], ent.mundo.is_empty(), sesion["lanz"], op])
	if _cache_gmin.has(clave): return _cache_gmin[clave]
	var r = null
	if prueba_lanzamiento(1, op):
		var lo := 0.0; var hi := 1.0
		for i in 7:
			var g := (lo + hi) / 2
			if prueba_lanzamiento(g, op): hi = g
			else: lo = g
		r = hi
	_cache_gmin[clave] = r
	return r
func masa_maxima_lanzamiento(op: Dictionary):
	var d: float = DatosComunes.avion(sesion["avion"])["masa_kg"]; var lo := 0.5 * d; var hi := 1.5 * d
	var o := op.duplicate(); o["masa_kg"] = lo
	if not prueba_lanzamiento(1, o): return null
	for i in 7:
		var mk := (lo + hi) / 2; o["masa_kg"] = mk
		if prueba_lanzamiento(1, o): lo = mk
		else: hi = mk
	return lo
func pct_gas(g: float) -> int: return int(ceil(g * 100 / 5.0) * 5)
func lanzamiento_actual() -> Dictionary:
	var vto: Dictionary = ent.viento; var rumbo := PI if Escenarios.zona_de(sesion["escenario"]) == 2 else 0.0
	var op := { "viento": [vto["base"] * cos(vto["rumbo"]), vto["base"] * sin(vto["rumbo"]), 0.0], "rumbo": rumbo, "trim": mando["trim"] }
	var clave := str([sesion["avion"], modelo.masa_kg, modelo.dcg, op])
	if _cache_lanz["clave"] != clave: _cache_lanz = { "clave": clave, "op": op, "gmin": gas_minimo_lanzamiento(op), "mmax": -1.0, "gminDiseno": -1.0, "sinViento": -1.0 }
	return _cache_lanz
func texto_peso_lanz(L: Dictionary) -> String:
	var d: float = DatosComunes.avion(sesion["avion"])["masa_kg"]; var extra := int(round((modelo.masa_kg - d) * 1000))
	if modelo.masa_kg < d * 1.05: return ""
	if typeof(L["gminDiseno"]) == TYPE_FLOAT and L["gminDiseno"] == -1.0:
		var o: Dictionary = L["op"].duplicate(); o["masa_kg"] = d; L["gminDiseno"] = gas_minimo_lanzamiento(o)
	return " Es por el peso: lleva %d g de más%s." % [extra, (" (con el peso de diseño bastaría el %d %%)" % pct_gas(L["gminDiseno"])) if L["gminDiseno"] != null else ""]
## Gas minimo SIN viento (o null): si con todo el gas no sale pero sin viento si, lo tira el viento, no el peso (gasSinViento).
func gas_sin_viento(L: Dictionary):
	if typeof(L["sinViento"]) == TYPE_FLOAT and L["sinViento"] == -1.0:
		var o: Dictionary = L["op"].duplicate(); o["viento"] = [0.0, 0.0, 0.0]; L["sinViento"] = gas_minimo_lanzamiento(o)
	return L["sinViento"]
const RUMBOS_TXT := ["norte", "nordeste", "este", "sudeste", "sur", "sudoeste", "oeste", "noroeste"]
func texto_viento_lanz() -> String:
	var v: Dictionary = ent.viento; var desde := fposmod(v["rumbo"] * R2D + 180, 360)
	return "%d m/s del %s" % [int(round(v["base"])), RUMBOS_TXT[int(round(desde / 45)) % 8]]
func aviso_lanzamiento() -> String:
	if es_dron(): return ""
	var L := lanzamiento_actual()
	if L["gmin"] == null and gas_sin_viento(L) != null:
		return "⚠ Con este viento (%s) no saldría de la mano sin tocar los mandos: lánzalo de cara al viento o prepárate para corregir con la profundidad nada más soltarlo." % texto_viento_lanz()
	if L["gmin"] == null: return "⚠ Pesa demasiado para lanzarlo a mano (%d g): no saldría ni con todo el gas. Quítale peso en la pantalla del avión." % int(round(modelo.masa_kg * 1000))
	if av["gases"] < L["gmin"]: return "⚠ Con el %d %% de gas no saldría de la mano: sube el gas al menos al %d %% (W)." % [int(round(av["gases"] * 100)), pct_gas(L["gmin"])] + texto_peso_lanz(L)
	return ""
func causa_lanzamiento_fallido(gas: float) -> Dictionary:
	var L := lanzamiento_actual(); var masa := int(round(modelo.masa_kg * 1000))
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

# =====================================================================
#  PUNTO DE LANZAMIENTO EN EL MUNDO REAL
# =====================================================================
func en_mundo() -> bool: return not ent.mundo.is_empty()
func ent_campo() -> Entorno: return _ent_campo
func _casa() -> Dictionary:
	return { "N": float(sesion["lanz"]["N"]), "E": float(sesion["lanz"]["E"]) } if (en_mundo() and not sesion["lanz"].is_empty()) else { "N": 0.0, "E": 0.0 }
func rumbo_despejado(N: float, E: float) -> float:
	var mejor := 0.0; var menos := INF; var r := 0.0
	while r < 360:
		var sube := -INF; var d := 100.0
		while d <= 1500:
			sube = maxf(sube, ent.altura_mar(N + d * cos(r * D2R), E + d * sin(r * D2R))); d += 50
		if sube < menos: menos = sube; mejor = r
		r += 22.5
	return mejor
func lat_lon_a_ne(m: Dictionary, lat: float, lon: float) -> Array:
	var o: Dictionary = m["origen"]
	return [(lat - o["lat"]) * 110574, (lon - o["lon"]) * 111320 * cos(o["lat"] * D2R)]
func _lanz_por_defecto() -> void:
	if not sesion["lanz"].is_empty() and sesion["lanz"].get("mundo", "") == mundo_datos["id"]: return
	var d: Dictionary = LANZ_DEFECTO.get(mundo_datos["id"], {})
	if not d.is_empty():
		var ne := lat_lon_a_ne(mundo_datos, d["lat"], d["lon"])
		sesion["lanz"] = { "mundo": mundo_datos["id"], "N": round(ne[0]), "E": round(ne[1]), "rumbo": d["rumbo"], "defecto": true }
	elif not indice_zonas.is_empty():
		var z: Dictionary = indice_zonas[0]
		sesion["lanz"] = { "mundo": mundo_datos["id"], "N": round(z["centro"]["N"]), "E": round(z["centro"]["E"]), "rumbo": rumbo_despejado(z["centro"]["N"], z["centro"]["E"]) }
	else: sesion["lanz"] = { "mundo": mundo_datos["id"], "N": 0.0, "E": 0.0, "rumbo": mundo_datos.get("rumbo_despegue", 0) }
## Puntos de despegue destacados del vuelo libre en el mundo real (escenarios.js: "destacados"; destacadosLanz de la web).
func destacados_lanz() -> Array:
	return Escenarios.datos().get(sesion["escenario"], {}).get("destacados", [])
func elegir_destacado(d: Dictionary) -> void:
	var ne := lat_lon_a_ne(mundo_datos, d["lat"], d["lon"])
	sesion["lanz"] = { "mundo": mundo_datos["id"], "N": round(ne[0]), "E": round(ne[1]), "rumbo": float(d["rumbo"]), "destacado": d["nombre"] }; _guardar()
func elegir_punto(N: float, E: float) -> void:
	sesion["lanz"] = { "mundo": mundo_datos["id"], "N": round(N), "E": round(E), "rumbo": rumbo_despejado(N, E) }; _guardar()
func colocar_en_base(a: Dictionary, m = null) -> void:
	if not en_mundo(): return
	if m == null: m = modelo
	var c := _casa()
	a["p"] = [c["N"], c["E"], -(ent.altura(c["N"], c["E"]) + (0.02 if (m is ModeloCuadricoptero or m is ModeloFPV) else 1.6))]   # en la mano (avion) o en el suelo (dron)

# =====================================================================
#  INTERFAZ: pantallas, HUD y capas
# =====================================================================
func _construir_ui() -> void:
	ui = CanvasLayer.new(); add_child(ui)
	var raiz := Control.new(); raiz.set_anchors_preset(Control.PRESET_FULL_RECT); raiz.mouse_filter = Control.MOUSE_FILTER_IGNORE
	raiz.theme = Tema.crear(); ui.add_child(raiz)
	hud = HudVuelo.new(self); raiz.add_child(hud); hud.visible = false
	hud_dji = HudDji.new(self); raiz.add_child(hud_dji); hud_dji.visible = false; hud.dji = hud_dji
	raiz.move_child(hud_dji, 0)
	hud_fpv = HudFPV.new(self); raiz.add_child(hud_fpv); hud_fpv.visible = false; raiz.move_child(hud_fpv, 0)
	condiciones = PantallaMisiones.Condiciones.new(self)
	pantallas = { "pInicio": PantallaInicio.new(self), "pAlumno": PantallaPilotos.new(self), "pHangar": PantallaHangar.new(self),
				  "pEntrenamientos": PantallaMisiones.Entrenamientos.new(self), "pVolar": PantallaMisiones.Volar.new(self),
				  "pOperaciones": PantallaMisiones.Operaciones.new(self), "pMulti": PantallaMisiones.Multijugador.new(self),
				  "pLanzamiento": PantallaLanzamiento.new(self), "pAjustes": PantallaAjustes.new(self),
				  "pResultado": PantallaResultado.Resultado.new(self), "pProgreso": PantallaResultado.Progreso.new(self) }
	for k in pantallas: pantallas[k].visible = false; raiz.add_child(pantallas[k])
	# multijugador: quien hay en la sala (#salaInfo de la web), abajo a la derecha
	sala_info = PanelContainer.new(); sala_info.add_theme_stylebox_override("panel", Tema.caja(Color(0, 0, 0, 0.5), Color(0, 0, 0, 0), 10, 0, 12, 8))
	sala_info.anchor_left = 1; sala_info.anchor_right = 1; sala_info.anchor_top = 1; sala_info.anchor_bottom = 1
	sala_info.offset_right = -16; sala_info.offset_bottom = -236; sala_info.grow_horizontal = Control.GROW_DIRECTION_BEGIN; sala_info.grow_vertical = Control.GROW_DIRECTION_BEGIN
	sala_info.mouse_filter = Control.MOUSE_FILTER_IGNORE; sala_info.visible = false; raiz.add_child(sala_info)
	sala_info_rt = Tema.rico("", 12); sala_info_rt.fit_content = true; sala_info_rt.autowrap_mode = TextServer.AUTOWRAP_OFF; sala_info.add_child(sala_info_rt)
	# ordenes del profesor (#ordenesHud de la web): ATERRIZA YA y los NOTAM, arriba en el centro
	ordenes_hud = VBoxContainer.new(); ordenes_hud.add_theme_constant_override("separation", 6); ordenes_hud.alignment = BoxContainer.ALIGNMENT_BEGIN
	ordenes_hud.anchor_left = 0.5; ordenes_hud.anchor_right = 0.5; ordenes_hud.offset_top = 64; ordenes_hud.grow_horizontal = Control.GROW_DIRECTION_BOTH
	ordenes_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE; raiz.add_child(ordenes_hud)
	# trabajos: el briefing (la imagen de la orden de trabajo) encima del vuelo, con B o el boton del mapa (#briefing de la web)
	briefing = PanelContainer.new(); briefing.add_theme_stylebox_override("panel", Tema.caja(Color(0, 0, 0, 0.6), Color(1, 1, 1, 0.25), 12, 1, 8, 8))
	briefing.visible = false; briefing.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND; briefing.tooltip_text = "Pulsa B, Esc o haz clic para cerrarlo"
	briefing.gui_input.connect(func(ev: InputEvent): if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT: ver_briefing(false))
	var bv := VBoxContainer.new(); bv.add_theme_constant_override("separation", 6); bv.mouse_filter = Control.MOUSE_FILTER_IGNORE; briefing.add_child(bv)
	briefing_img = TextureRect.new(); briefing_img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; briefing_img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	briefing_img.mouse_filter = Control.MOUSE_FILTER_IGNORE; bv.add_child(briefing_img)
	var bl := Tema.rico("[center][color=#9fb3c8]Briefing de la orden de trabajo · [b]B[/b] o clic para cerrar[/color][/center]", 12); bl.fit_content = true; bl.autowrap_mode = TextServer.AUTOWRAP_OFF; bl.mouse_filter = Control.MOUSE_FILTER_IGNORE; bv.add_child(bl)
	raiz.add_child(briefing)
	pausa = Capas.pausa(self); raiz.add_child(pausa["raiz"])
	carga = Capas.carga(); raiz.add_child(carga["raiz"])
	modal = Capas.modal(); raiz.add_child(modal["raiz"])
	modal["si"].pressed.connect(func(): modal["raiz"].visible = false; _modal_resp.emit(true))
	modal["no"].pressed.connect(func(): modal["raiz"].visible = false; _modal_resp.emit(false))
	dialogo = FileDialog.new(); dialogo.access = FileDialog.ACCESS_FILESYSTEM; dialogo.use_native_dialog = true
	dialogo.file_mode = FileDialog.FILE_MODE_SAVE_FILE; dialogo.filters = PackedStringArray(["*.csv ; Caja negra CSV"]); raiz.add_child(dialogo)

## Muestra una pantalla ("" = el vuelo).
func mostrar(id: String) -> void:
	for k in pantallas: pantallas[k].visible = k == id
	pantalla_actual = id
	var en_vuelo := id == ""
	hud.visible = en_vuelo
	hud_dji.visible = en_vuelo and modelo != null and es_dron() and not es_fpv() and not sin_instrumentos
	hud_fpv.visible = en_vuelo and modelo != null and es_fpv() and not sin_instrumentos
	get_viewport().disable_3d = not en_vuelo                  # en las pantallas no se dibuja el mundo
	if not en_vuelo: hud.ayuda.visible = false; poner_pausa(false); sonido.silenciar(true)
	else: sonido.silenciar(not sonido.on); get_viewport().gui_release_focus()

func confirmar(titulo: String, bb: String, texto_si := "Sí") -> bool:
	modal["titulo"].text = titulo; modal["texto"].text = bb; modal["si"].text = texto_si; modal["raiz"].visible = true
	return await _modal_resp

func poner_aviso(txt: String, segundos := 0.0) -> void:
	hud.aviso.text = txt
	if segundos > 0:
		await get_tree().create_timer(segundos).timeout
		if hud.aviso.text == txt: hud.aviso.text = ""
var _t_toast := 0
func poner_toast(txt: String) -> void:
	hud.toast.text = txt; _t_toast += 1; var n := _t_toast
	await get_tree().create_timer(1.5).timeout
	if n == _t_toast: hud.toast.text = ""

func mostrar_carga(titulo: String, texto: String, frac: float) -> void:
	carga["raiz"].visible = true; carga["titulo"].text = titulo; carga["texto"].text = texto; carga["barra"].size.x = 358 * frac
	await get_tree().process_frame; await get_tree().process_frame

# ---- navegacion ----
var _tras_piloto = null
func ir_pilotos(luego = null) -> void:
	_tras_piloto = luego; mostrar("pAlumno"); await reiniciar_aula(); pantallas["pAlumno"].refrescar()
## Arranca el aula en el modo guardado; si cambia de registro (local / online / ninguno), el perfil de antes no vale.
func reiniciar_aula() -> void:
	var antes: String = aula.modo if aula.activo else ""
	await aula.iniciar()
	if (aula.modo if aula.activo else "") != antes: sesion["alumno"] = null; sesion["sin_registrar"] = false
## Al arrancar, el ultimo perfil usado en el modo guardado.
func perfil_al_arrancar() -> void:
	if not aula.activo or sesion["alumno"] != null or sesion["sin_registrar"]: return
	var id := aula.perfil_recordado()
	if id == "": return
	var r: Dictionary = await aula.api("GET", "alumnos")
	if r["ok"]:
		for a in r["datos"]: if String(a["id"]) == id: sesion["alumno"] = a
func elegir_piloto(a) -> void:
	sesion["alumno"] = a; sesion["sin_registrar"] = a == null; aula.recordar_perfil(String(a["id"]) if a != null else "")
	var f = _tras_piloto; _tras_piloto = null
	if f != null: f.call()
	else: ir_inicio()
func ir_inicio() -> void:
	salir_sala()                                 # al volver al inicio se sale de la sala multijugador
	pantallas["pInicio"].refrescar(); mostrar("pInicio")
func elegir_avion(id: String) -> void:
	sesion["avion"] = id; _guardar()
func ir_hangar() -> void:
	pantallas["pHangar"].refrescar(); mostrar("pHangar")
func ir_entrenamientos() -> void:
	mostrar("pEntrenamientos"); pantallas["pEntrenamientos"].refrescar()
# =====================================================================
#  MULTIJUGADOR: salas del servidor del aula (MULTI de la web; el mismo protocolo, se puede volar mezclado). Cada
#  simulador manda su estado 10 veces por segundo y recibe el de los demas de su sala, que se dibujan como "fantasmas"
#  (sin choques entre ellos, cada uno con su fisica).
# =====================================================================
var sala := {}                  # la sala en la que se esta ({} = ninguna)
var multi_otros := {}           # id -> el ultimo estado recibido de cada uno, con "recibido" (s)
var _multi_id := ""
var _multi_enviando := false
var _t_csc := 0.0               # DJI: tiempo con las palancas en la combinacion de arranque (CSC)
var _multi_t := 0.0
var _fantasmas := {}            # id -> { nodo: Avion3D, et: Label3D, p: Array (NED), avion, nombre }
var sala_info: PanelContainer
var ordenes_hud: VBoxContainer
var _ordenes_firma := ""
var _exclusiones: Node3D
# ordenes del profesor a la sala (ORDENES de la web): viento, NOTAM, aterrizaje inmediato, zonas de exclusion y el
# desaparecido de la busqueda
var ordenes := {}
const EXCLUSION_TXT := "Respetar las zonas de exclusión que marca el profesor"
var sala_info_rt: RichTextLabel
func multi_id() -> String:
	if _multi_id == "": _multi_id = Aula.uuid4()
	return _multi_id
func multi_posible() -> bool: return aula.activo and aula.modo == "servidor" and aula.url != ""
func nombre_piloto() -> String: return String(sesion["alumno"]["nombre"]) if sesion["alumno"] != null else "Invitado " + multi_id().substr(0, 4)
func ir_multi() -> void:
	mostrar("pMulti"); pantallas["pMulti"].refrescar()
## Entra en una sala: su escenario, su punto de salida y su viento, con un vehiculo que valga para el; y a volar.
func entrar_sala(s: Dictionary) -> void:
	if not Escenarios.datos().has(s["escenario"]): poner_toast("Esta sala es de algo que este simulador no tiene: actualízalo"); return
	var E: Dictionary = Escenarios.datos()[s["escenario"]]
	sala = s; multi_otros = {}; reiniciar_ordenes()
	var veh: Array = E.get("vehiculos", ["avion", "dron", "fpv"])
	if not Escenarios.vehiculo_de(sesion["avion"]) in veh:
		for a in ids_aviones:
			if Escenarios.vehiculo_de(a) in veh: sesion["avion"] = a; break
	sesion["escenario"] = s["escenario"]
	if s.get("lanz") != null: sesion["lanz"] = s["lanz"]
	elif E.has("operacion"):                     # trabajos: su despegue
		var S0: Dictionary = E["operacion"]["salida"]; sesion["lanz"] = { "mundo": E["mundo"], "N": float(S0["n"]), "E": float(S0["e"]), "rumbo": float(S0["rumbo"]) }
	if s.get("viento") != null and not E.has("viento"): sesion["viento"] = s["viento"]
	poner_toast("Sala %s: %s" % [s["codigo"], s["nombre"]]); empezar()
func salir_sala() -> void:
	if sala.is_empty(): return
	var s := sala; sala = {}; multi_otros = {}; _poner_fantasmas(); sala_info.visible = false
	reiniciar_ordenes(); _pintar_ordenes(); _poner_exclusiones()
	aula.api("POST", "salas/%s/salir" % s["codigo"], { "id": multi_id() })
func reiniciar_ordenes() -> void:
	ordenes = { "n": 0, "viento": null, "notam": [], "aterrizar": 0.0, "en_aire": false, "zonas": [], "persona": null, "t_aviso": 0.0 }

func aplicar_ordenes(lista: Array) -> void:
	if ordenes.is_empty(): reiniciar_ordenes()
	var cambio := false
	for o in lista:
		if int(o["n"]) <= int(ordenes["n"]): continue
		ordenes["n"] = int(o["n"]); cambio = true
		var para := String(o.get("para", "*"))
		if para != "*" and para != multi_id(): continue
		var nueva: bool = float(o.get("edad", 0)) < 30          # las de antes de entrar en la sala se aplican sin anunciarlas
		match String(o["tipo"]):
			"viento":
				ordenes["viento"] = { "vel": float(o["vel"]), "desde": float(o["desde"]), "rachas": bool(o.get("rachas", false)) }
				ent.configurar_viento(float(o["vel"]), float(o["desde"]), bool(o.get("rachas", false)))
				if nueva: poner_toast("Viento: %s m/s del %s%s" % [PasadaBaja._num(float(o["vel"])), PantallaMisiones.RUMBOS_VIENTO[int(round(float(o["desde"]) / 45.0)) % 8], ", con rachas" if o.get("rachas", false) else ""])
			"notam":
				ordenes["notam"].append(String(o.get("texto", "")))
				if nueva: poner_toast("Nuevo NOTAM")
			"quitar_notam": ordenes["notam"] = []
			"aterrizar":
				if nueva: ordenes["aterrizar"] = Time.get_ticks_msec() / 1000.0; ordenes["en_aire"] = false
			"exclusion":
				ordenes["zonas"].append({ "id": int(o["n"]), "N": float(o["N"]), "E": float(o["E"]), "r": float(o["r"]) })
				if nueva: poner_toast("Nueva zona de exclusión: mírala en el mapa")
			"quitar_exclusion": ordenes["zonas"] = (ordenes["zonas"] as Array).filter(func(z): return z["id"] != int(o.get("id", -1)))
			"senderista":
				ordenes["persona"] = [float(o["N"]), float(o["E"])]
				if mover_desaparecido() and nueva: poner_toast("Nueva posición del desaparecido: búscalo")
	if cambio: ordenes_al_evaluador(); _poner_exclusiones()
	_pintar_ordenes()

## El desaparecido donde lo ha puesto el profesor (en la busqueda): hay que volver a encontrarlo.
func mover_desaparecido() -> bool:
	if ordenes.get("persona") == null or ev == null or ev.op == null or not ev.op.d.has("zona"): return false
	var op = ev.op; op.d["persona"] = (ordenes["persona"] as Array).duplicate(); op.encontrado = false; op.error = null
	for k in ["localizar", "posicion"]:
		if ev.obj.has(k) and ev.obj[k]["estado"] != "mal": ev.obj[k]["estado"] = "pend"
	if mundo3d != null: mundo3d.poner_operacion(op.d, [casa["N"], casa["E"]] if en_mundo() else [0.0, 0.0])
	return true

## Al empezar (o empezar de nuevo) un vuelo en la sala: el viento, el desaparecido y el objetivo de las zonas de exclusion.
func ordenes_al_evaluador() -> void:
	if sala.is_empty() or ev == null or ordenes.is_empty(): return
	if ordenes["viento"] != null and not ev.get_meta("viento_profesor", false):
		var V: Dictionary = ordenes["viento"]; ent.configurar_viento(V["vel"], V["desde"], V["rachas"]); ev.set_meta("viento_profesor", true)
	var P = ordenes["persona"]
	if P != null and ev.op != null and ev.op.d.has("zona") and (float(ev.op.d["persona"][0]) != P[0] or float(ev.op.d["persona"][1]) != P[1]): mover_desaparecido()
	if not (ordenes["zonas"] as Array).is_empty() and not ev.obj.has("exclusion"):
		ev.obj["exclusion"] = { "texto": EXCLUSION_TXT, "estado": "curso" }; ev.orden.append("exclusion")

## En cada paso en vuelo: dentro de una zona de exclusion, aviso y objetivo suspendido.
func vigilar_exclusiones() -> void:
	if sala.is_empty() or ordenes.is_empty() or (ordenes["zonas"] as Array).is_empty() or ev == null or av["estado"] != "volando" or av.get("posado", false): return
	for z in ordenes["zonas"]:
		if Vector2(av["p"][0] - z["N"], av["p"][1] - z["E"]).length() < z["r"]:
			ev.marcar("exclusion", "mal")
			var t := Time.get_ticks_msec() / 1000.0
			if t - float(ordenes["t_aviso"]) > 4: ordenes["t_aviso"] = t; poner_toast("¡Dentro de una zona de exclusión! Sal de ella")
			return

func _pintar_ordenes() -> void:
	if not ordenes.is_empty() and float(ordenes["aterrizar"]) > 0 and not av.is_empty():   # hasta que aterrice (si ya estaba en el suelo, 8 s)
		var en_suelo: bool = av["estado"] != "volando" or av.get("posado", false)
		if not en_suelo: ordenes["en_aire"] = true
		elif ordenes["en_aire"] or Time.get_ticks_msec() / 1000.0 - float(ordenes["aterrizar"]) > 8: ordenes["aterrizar"] = 0.0
	var aterriza: bool = not ordenes.is_empty() and float(ordenes["aterrizar"]) > 0
	var notam: Array = ordenes.get("notam", [])
	var firma := "%s|%s" % [aterriza, "|".join(notam)]
	if aterriza: ordenes_hud.modulate.a = 0.55 + 0.45 * absf(sin(Time.get_ticks_msec() / 1000.0 * PI))
	else: ordenes_hud.modulate.a = 1.0
	if firma == _ordenes_firma: return
	_ordenes_firma = firma
	for c in ordenes_hud.get_children(): c.queue_free()
	var caja := func(txt: String, fondo: Color, color: Color, tam: int) -> PanelContainer:
		var pc := PanelContainer.new(); pc.add_theme_stylebox_override("panel", Tema.caja(fondo, Color(0, 0, 0, 0), 10 if tam > 20 else 8, 0, 22 if tam > 20 else 14, 10 if tam > 20 else 5))
		pc.mouse_filter = Control.MOUSE_FILTER_IGNORE; pc.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		var l := Tema.etiqueta(txt, tam, color, true); l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; pc.add_child(l); return pc
	if aterriza: ordenes_hud.add_child(caja.call("ATERRIZA YA · orden del profesor", Color(0.83, 0.18, 0.18, 0.95), Color.WHITE, 26))
	for t in notam: ordenes_hud.add_child(caja.call("NOTAM · " + String(t), Color(1, 0.72, 0.3, 0.92), Color("#1a1000"), 14))

## Zonas de exclusion en 3D: cilindros rojos translucidos del suelo a 120 m (ponerExclusiones de la web).
func _poner_exclusiones() -> void:
	if _exclusiones != null: _exclusiones.queue_free(); _exclusiones = null
	if ordenes.is_empty() or (ordenes["zonas"] as Array).is_empty(): return
	_exclusiones = Node3D.new(); add_child(_exclusiones)
	var mat := StandardMaterial3D.new(); mat.albedo_color = Color(0.9, 0.22, 0.21, 0.18); mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var borde := mat.duplicate(); borde.albedo_color = Color(0.9, 0.22, 0.21, 0.7)
	for z in ordenes["zonas"]:
		var y: float = ent.altura(z["N"], z["E"]) if en_mundo() else 0.0
		var cm := CylinderMesh.new(); cm.top_radius = z["r"]; cm.bottom_radius = z["r"]; cm.height = 120; cm.cap_top = false; cm.cap_bottom = false; cm.radial_segments = 48
		var c := MeshInstance3D.new(); c.mesh = cm; c.material_override = mat; c.position = Vector3(z["E"], y + 60, -z["N"]); _exclusiones.add_child(c)
		for h in [0.5, 120.0]:
			var tm := TorusMesh.new(); tm.inner_radius = z["r"] - 0.6; tm.outer_radius = z["r"] + 0.6; tm.rings = 64
			var a := MeshInstance3D.new(); a.mesh = tm; a.material_override = borde; a.position = Vector3(z["E"], y + h, -z["N"]); a.scale = Vector3(1, 0.05, 1); _exclusiones.add_child(a)

## Manda el estado propio y recoge el de los demas (enviarSala de la web).
func _enviar_sala() -> void:
	if sala.is_empty() or _multi_enviando or av.is_empty() or modelo == null: return
	_multi_enviando = true
	# objetivos: cumplidos, total y fallados (las normas siguen "en curso" hasta aterrizar); y lo que va haciendo en el trabajo
	var ok := 0; var tot := 0; var mal := 0; var ahora := ""
	if ev != null:
		for k in ev.obj:
			tot += 1
			if ev.obj[k]["estado"] == "ok": ok += 1
			elif ev.obj[k]["estado"] == "mal": mal += 1
		var guia = ev.op if ev.op != null else ev.fpv
		if guia != null:
			var re := RegEx.new(); re.compile("<[^>]+>"); ahora = re.sub(guia.ahora(ev.obj, av), "", true).left(160)
	var e := { "id": multi_id(), "nombre": nombre_piloto(), "avion": sesion["avion"], "p": av["p"], "q": av["q"], "vn": Cuat.rot(av["q"], av.get("v", [0.0, 0.0, 0.0])),
			   "estado": av["estado"], "gas": av.get("gases", 0.0), "agl": av.get("agl", 0.0), "objs": [ok, tot, mal] if ev != null else null, "ahora": ahora,
			   "tvuelo": vuelo["tVuelo"] if vuelo != null else 0.0, "final": vuelo["final"] if vuelo != null else null, "gimbal": av.get("gimbal", 0.0) }
	var cod: String = sala["codigo"]
	var r: Dictionary = await aula.api("POST", "salas/%s/estado" % cod, e)
	_multi_enviando = false
	if sala.is_empty() or sala["codigo"] != cod: return
	if r["ok"]:
		var t := Time.get_ticks_msec() / 1000.0; var vivos := {}
		for o in r["datos"]["otros"]: o["recibido"] = t; multi_otros[o["id"]] = o; vivos[o["id"]] = true
		for k in multi_otros.keys():
			if not vivos.has(k): multi_otros.erase(k)
		aplicar_ordenes(r["datos"].get("ordenes", []))
	elif r["status"] == 404: poner_toast("La sala se ha cerrado"); salir_sala()
## Los demas como fantasmas: su modelo y su nombre encima; la posicion, la ultima recibida avanzada con su velocidad (como
## mucho 0,3 s) y suavizada (ponerFantasmas de la web).
func _poner_fantasmas() -> void:
	var ahora := Time.get_ticks_msec() / 1000.0; var vivos := {}
	for id in multi_otros:
		var f: Dictionary = multi_otros[id]; vivos[id] = true
		var g = _fantasmas.get(id)
		if g == null or g["avion"] != f["avion"] or g["nombre"] != f["nombre"]:
			if g != null: g["nodo"].queue_free(); g["et"].queue_free()
			var datos := DatosComunes.avion(String(f["avion"]))
			if datos.is_empty(): continue
			var nodo := Avion3D.new(datos); add_child(nodo)
			var et := Label3D.new(); et.text = String(f["nombre"]); et.billboard = BaseMaterial3D.BILLBOARD_ENABLED; et.fixed_size = true; et.pixel_size = 0.0009
			et.font_size = 26; et.outline_size = 8; et.modulate = Color("#4fc3f7"); et.no_depth_test = true; et.font = Tema.negrita; add_child(et)
			g = { "nodo": nodo, "et": et, "p": (f["p"] as Array).duplicate(), "avion": f["avion"], "nombre": f["nombre"] }; _fantasmas[id] = g
		var dt := minf(0.3, ahora - float(f["recibido"])); var vn: Array = f.get("vn", [0.0, 0.0, 0.0])
		var obj := [f["p"][0] + vn[0] * dt, f["p"][1] + vn[1] * dt, f["p"][2] + vn[2] * dt]
		var lejos := Vector3(obj[0] - g["p"][0], obj[1] - g["p"][1], obj[2] - g["p"][2]).length() > 30
		for i in 3: g["p"][i] = obj[i] if lejos else g["p"][i] + (obj[i] - g["p"][i]) * 0.35
		var gas: float = f.get("gas", 0.0)
		g["nodo"].actualizar({ "p": g["p"], "q": f["q"], "de": 0.0, "dr": 0.0, "da": 0.0, "gases": gas, "estado": f.get("estado", "volando"),
							   "gimbal": f.get("gimbal", 0.0) if f.get("gimbal") != null else 0.0, "motores": [gas, gas, gas, gas] })
		g["et"].position = Avion3D.ned(g["p"]) + Vector3(0, 1.2, 0)
	for id in _fantasmas.keys():
		if not vivos.has(id): _fantasmas[id]["nodo"].queue_free(); _fantasmas[id]["et"].queue_free(); _fantasmas.erase(id)
## Panel de la sala en vuelo: quien esta y como va.
func _pintar_sala_info() -> void:
	sala_info.visible = not sala.is_empty() and pantalla_actual == ""
	if briefing.visible and pantalla_actual != "": briefing.visible = false
	if not sala_info.visible: return
	var t := "[color=#4fc3f7][b]Sala %s[/b][/color] · %s" % [sala["codigo"], sala["nombre"]]
	if multi_otros.is_empty(): t += "\nTodavía no hay nadie más"
	for id in multi_otros:
		var o: Dictionary = multi_otros[id]; var objs = o.get("objs")
		t += "\n● %s · %s · %s%s" % [o["nombre"], String(DatosComunes.avion(String(o["avion"])).get("nombre", o["avion"])),
			("%d m" % int(round(maxf(0, o.get("agl", 0.0))))) if o.get("estado", "") == "volando" else String(o.get("estado", "")),
			(" · %d✔%s de %d" % [objs[0], (" %d✘" % objs[2]) if objs.size() > 2 and objs[2] > 0 else "", objs[1]]) if objs != null and objs[1] > 0 else ""]
	sala_info_rt.text = t

func ir_operaciones() -> void:
	mostrar("pOperaciones"); pantallas["pOperaciones"].refrescar()
## Empieza el trabajo elegido: con el DJI (las operaciones son suyas), desde su punto de despegue (volarOperacion de la web).
func volar_operacion(id: String) -> void:
	var E: Dictionary = Escenarios.datos()[id]; var S: Dictionary = E["operacion"]["salida"]
	if Escenarios.vehiculo_de(sesion["avion"]) != "dron":
		for a in ids_aviones:
			if Escenarios.vehiculo_de(a) == "dron": sesion["avion"] = a; break
	sesion["escenario"] = id; sesion["lanz"] = { "mundo": mundo_datos["id"], "N": float(S["n"]), "E": float(S["e"]), "rumbo": float(S["rumbo"]) }
	guardar_sesion(); empezar()
func ir_volar() -> void:
	if Escenarios.libre(sesion["escenario"]): sitio_sel = sesion["escenario"]
	mostrar("pVolar"); pantallas["pVolar"].refrescar()
func ir_ajustes(seccion := "") -> void:
	pantallas["pAjustes"].refrescar()
	if seccion != "": pantallas["pAjustes"].seleccionar(seccion)
	mostrar("pAjustes")
func ir_lanzamiento() -> void:
	ent.poner_mundo(mundo_datos); _lanz_por_defecto()
	mostrar("pLanzamiento"); pantallas["pLanzamiento"].preparar()
func ir_progreso(desde: String, alumno = null) -> void:
	pantallas["pProgreso"].desde = desde; pantallas["pProgreso"].alumno = alumno if alumno != null else sesion["alumno"]
	mostrar("pProgreso"); pantallas["pProgreso"].cargar()

# =====================================================================
#  EMPEZAR, REINICIAR, LANZAR
# =====================================================================
func _poner_mundo_3d(es_m: bool, titulo: String) -> void:
	var cal := calidad_actual()
	if es_m:
		if mundo3d != null and mundo3d.calidad != cal: mundo3d.queue_free(); mundo3d = null; await get_tree().process_frame
		if mundo3d == null:
			await mostrar_carga(titulo, "Terreno, mar, carreteras y pueblos…", 0.3)
			mundo3d = Mundo3D.new(); mundo3d.calidad = cal; add_child(mundo3d); mundo3d.construir(ent, mundo_datos, orto)
		_poner_vista(mundo3d)
		await mostrar_carga(titulo, "Zonas de detalle: ortofoto, edificios y árboles…", 0.6)
		var c := _casa(); var zs := []
		for meta in zonas_cerca(c["N"], c["E"]):
			if not zonas_cache.has(meta["id"]): zonas_cache[meta["id"]] = DatosComunes.cargar_zona(meta)
			if not (zonas_cache[meta["id"]] as Dictionary).is_empty(): zs.append(zonas_cache[meta["id"]])
		mundo3d.claro = Vector2(c["E"], c["N"])
		ent.poner_zonas(zs); mundo3d.poner_zonas(zs); mundo3d.poner_base(c["N"], c["E"])
		await mostrar_carga(titulo, "Listo", 1.0)
	else:
		if campo3d != null and campo3d.calidad != cal: campo3d.queue_free(); campo3d = null; await get_tree().process_frame
		if campo3d == null:
			campo3d = Campo3D.new(); campo3d.calidad = cal; add_child(campo3d); campo3d.construir(ent)
		_poner_vista(campo3d)
	if campo3d != null: campo3d.poner_pista_fpv({} if es_m else Escenarios.datos()[sesion["escenario"]].get("pista_fpv", {}))

## Zonas de detalle a menos de RADIO_ZONAS m del punto (N, E), primero la que lo contiene (zonasCerca de
## simulador.html): con zonas pegadas, como las de La Manga y el Mar Menor, se vuela en detalle hasta ~2 km del piloto.
const RADIO_ZONAS := 2000.0
func zonas_cerca(N: float, E: float) -> Array:
	var dist := func(z: Dictionary) -> float:
		return Vector2(maxf(maxf(z["N0"] - N, 0.0), N - z["N0"] - z["lado_m"]), maxf(maxf(z["E0"] - E, 0.0), E - z["E0"] - z["lado_m"])).length()
	var dentro := DatosComunes.zona_en(indice_zonas, MUNDO, N, E)
	var lista := indice_zonas.filter(func(z): return z["mundo"] == MUNDO and dist.call(z) <= RADIO_ZONAS)
	lista.sort_custom(func(a, b):
		var da: int = 0 if (not dentro.is_empty() and a["id"] == dentro["id"]) else 1; var db: int = 0 if (not dentro.is_empty() and b["id"] == dentro["id"]) else 1
		return da < db if da != db else dist.call(a) < dist.call(b))
	return lista

## Solo un mundo en el arbol a la vez (cada uno trae su cielo, su luz y su WorldEnvironment).
func _poner_vista(v: Node3D) -> void:
	for w in [mundo3d, campo3d]:
		if w != null and w != v and w.is_inside_tree(): remove_child(w)
	if v.get_parent() == null: add_child(v)
	vista = v
	cam.far = 16000.0 if v == mundo3d else 3000.0     # como el navegador (cam.far de visor.js)

func empezar() -> void:
	var E: Dictionary = Escenarios.datos()[sesion["escenario"]]; var es_m := E.has("mundo")
	sonido.iniciar()
	if es_m: await mostrar_carga(mundo_datos["nombre"], "Avión y física…", 0.1)
	ent.poner_mundo(mundo_datos if es_m else {})
	if not es_m: ent.poner_zona({})
	modelo = crear_modelo(sesion["avion"])
	aplicar_cm(modelo); aplicar_calibracion(modelo); aplicar_dificultad(modelo)
	var A := DatosComunes.avion(sesion["avion"])
	if avion3d: avion3d.queue_free()
	avion3d = Avion3D.new(A); add_child(avion3d)
	_texto_ayuda(A)
	hud_dji.b_briefing.visible = E.has("operacion"); ver_briefing(false)   # trabajos: el briefing a mano (B)
	# el dron se vuela mirando la pantalla de la app (su camara); al volver a un avion, vista del piloto
	if es_dron() != era_dron: camara = 3 if es_dron() else 1
	era_dron = es_dron()
	if es_dron() and not es_fpv():
		if hud.gps.get_parent() != hud_dji.mapa: hud.gps.get_parent().remove_child(hud.gps); hud_dji.mapa.add_child(hud.gps)
		hud.gps.custom_minimum_size = Vector2(130, 130)
	elif hud.gps.get_parent() != hud.panel:
		hud.gps.get_parent().remove_child(hud.gps); hud.panel.add_child(hud.gps); hud.gps.custom_minimum_size = Vector2(190, 190)
	await _poner_mundo_3d(es_m, mundo_datos["nombre"])
	casa = _casa()
	vel_perdida = _vel_perdida()
	carga["raiz"].visible = false
	reiniciar(); mostrar("")

## Briefing de los trabajos: la misma imagen de la orden de trabajo (la zona y el despegue, sin las soluciones), encima del vuelo.
func ver_briefing(ver = null) -> void:
	var op: bool = Escenarios.datos()[sesion["escenario"]].has("operacion")
	var abrir: bool = op and (not briefing.visible if ver == null else bool(ver))
	if abrir:
		var f := DatosComunes.carpeta().path_join("operaciones/%s.jpg" % sesion["escenario"])
		var img := Image.load_from_file(f) if FileAccess.file_exists(f) else null
		briefing_img.texture = ImageTexture.create_from_image(img) if img != null else null
		var w := minf(900, get_viewport().get_visible_rect().size.x * 0.7); briefing_img.custom_minimum_size = Vector2(w, w * 2 / 3.0)
		briefing.size = Vector2.ZERO; briefing.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	briefing.visible = abrir
	var s := HudDji._redondo(44, Color("#ffb74d") if abrir else Color(0, 0, 0, 0.55), Color("#ffb74d") if abrir else Color(1, 1, 1, 0.4))
	for e in ["normal", "focus", "hover", "pressed"]: hud_dji.b_briefing.add_theme_stylebox_override(e, s)

func _texto_ayuda(A: Dictionary) -> void:
	var t := "[font_size=18][b]Controles[/b][/font_size]\n"
	if es_fpv():
		t += "[b]↑ ↓[/b] cabeceo (↑ adelante) · [b]← →[/b] alabeo · [b]W[/b] / [b]S[/b] gas (no vuelve al centro) · [b]Espacio[/b] gas a cero · [b]A[/b] / [b]D[/b] guiñada\n"
		t += "[b]L[/b] armar / desarmar (con el gas abajo) · [b]M[/b] modo ANGLE / HORIZON / ACRO · [b]R[/b] empezar de nuevo\n"
		t += "[b]1[/b] [b]2[/b] [b]3[/b] cámara piloto / persecución / FPV · [b]I[/b] OSD · [b]Esc[/b] pausa · [b]T[/b] esta ayuda\n"
		t += "[b]Mando[/b] (modo 2): izquierda gas y guiñada, derecha alabeo y cabeceo · A armar / desarmar · LB modo · RB cámara · Back empezar de nuevo · Start pausa\n"
		t += "[color=#8be08f]Mejor con una emisora RC por USB (el gas no tiene muelle) o un mando; con el teclado es muy difícil. Empieza en ANGLE.[/color]\n"
	elif es_dron():
		t += "[b]↓ ↑[/b] atrás / adelante · [b]← →[/b] laterales · [b]W[/b] / [b]S[/b] sube / baja · [b]A[/b] / [b]D[/b] gira sobre sí mismo\n"
		t += "[b]M[/b] modo Cine / Normal / Sport · [b]Q[/b] / [b]E[/b] gimbal · [b]F[/b] foto · [b]V[/b] vídeo · [b]H[/b] volver a casa · [b]L[/b] armar · [b]R[/b] empezar de nuevo · [b]B[/b] briefing (trabajos)\n"
		t += "[b]1[/b] [b]2[/b] [b]3[/b] cámara piloto / persecución / del dron · [b]I[/b] pantalla de la app · [b]Esc[/b] pausa · [b]T[/b] esta ayuda\n"
		t += "[b]Mando[/b] (modo 2): izquierda sube, baja y gira; derecha mueve · A despegar / aterrizar · combinación de palancas (CSC: las dos abajo y hacia dentro o hacia fuera, medio segundo): arrancar motores · B volver a casa · X vídeo · Y foto · LB modo · RB cámara · gatillos gimbal · Start pausa\n"
	else:
		t += "[b]↓ ↑[/b] profundidad (↓ tira: morro arriba) · [b]← →[/b] %s\n" % String(A.get("mandos", {}).get("izq_der", "timón"))
		t += "[b]W[/b] / [b]S[/b] gases · [b]Espacio[/b] cortar gases · [b]L[/b] lanzar · [b]R[/b] empezar de nuevo\n"
		t += "[b]1[/b] [b]2[/b] [b]3[/b] cámara piloto / persecución / a bordo · [b][[/b] [b]][/b] compensador\n"
		t += "[b]H[/b] datos de vuelo · [b]I[/b] instrumentos · [b]Esc[/b] pausa · [b]T[/b] esta ayuda\n"
		t += "[b]Mando[/b]: palanca derecha el avión, izquierda el gas · A lanzar · B cortar gas · Y cámara · X empezar de nuevo · Start pausa\n"
	if not es_fpv(): t += "[color=#ffb74d]Al lanzar a tope, el par del motor alabea el avión a la izquierda: corrige con un poco de alabeo a la derecha.[/color]\n"
	t += "[color=#aaaaaa]En vuelo libre: [b]+[/b] [b]−[/b] viento, [b]G[/b] rachas. %s[/color]" % String(A.get("ayuda", "El avión vira con el timón: el diedro inclina las alas solo. Si sueltas los mandos, vuelve a volar recto."))
	hud.ayuda_rt.text = t

func reiniciar() -> void:
	_gas_fpv_mando = false
	av = modelo.estado_inicial(); colocar_en_base(av)
	var F: Dictionary = Escenarios.datos()[sesion["escenario"]].get("pista_fpv", {})
	if not F.is_empty() and es_fpv() and not en_mundo():                 # en la plataforma y en el modo de la mision
		av["p"] = [float(F["salida"][0]), float(F["salida"][1]), -0.02]; modelo.modo = String(F["modo"])
	_orientar_lanzamiento()
	mando["pitch"] = 0.0; mando["yaw"] = 0.0; mando["trim"] = modelo.compensador_grados; mando["gimbal"] = 0.0
	var E: Dictionary = Escenarios.datos()[sesion["escenario"]]; var vv: Dictionary = E.get("viento", sesion["viento"])
	ent.configurar_viento(float(vv["vel"]), float(vv["desde"]), bool(vv["rachas"]))
	ev = Escenarios.Evaluador.new(sesion["escenario"], ent, self); vuelo = null; poner_pausa(false); ordenes_al_evaluador()
	if mundo3d != null: mundo3d.poner_operacion(ev.op.d if ev.op != null else {}, [casa["N"], casa["E"]] if en_mundo() else [0.0, 0.0])
	DJI["grabando"] = false; DJI["tRec"] = 0.0; DJI["tAnt"] = 0.0
	hud.guia.visible = false; hud.lejos_l.text = ""; hud.aviso.text = ""; hud.gps.estela = []
	_fov1 = -1.0; _acum = 0.0
	if E.has("enVuelo"): _empezar_en_vuelo(); return
	hud.aviso.text = "Gas abajo del todo y L (o botón A) para armar" if es_fpv() else ("Pulsa el botón de despegue (⇧), L o la combinación de palancas para armar" if es_dron() else "Pulsa L para lanzar")

func _nuevo_vuelo(h0: float) -> void:
	vuelo = { "id": Aula.uuid4(), "inicio": Aula.ahora_iso(), "inicio_local": Time.get_datetime_dict_from_system(), "tVuelo": 0.0, "filas": [], "final": "",
			  "escenario": sesion["escenario"], "dificultad": sesion["dificultad"], "gasLanz": av["gases"], "hmax": h0, "otraCamara": false }
	cn_contador = 0; grabar_muestra()

## Coloca el avion en vuelo (escenarios con enVuelo), como si acabara de lanzarse y subir.
func _empezar_en_vuelo() -> void:
	var C: Dictionary = Escenarios.datos()[sesion["escenario"]]["enVuelo"]; var vs := _vel_perdida()
	var V0 := maxf(modelo.lanzamiento["vel_ms"] + 1, 1.35 * vs)
	av["p"] = [float(C["N"]), float(C["E"]), -float(C["h"])]; av["q"] = Cuat.desde_euler(0, 3 * D2R, C["rumbo"] * D2R); av["v"] = [V0, 0.0, 0.0]; av["w"] = [0.0, 0.0, 0.0]
	av["gases"] = float(C["gas"]); av["estado"] = "volando"
	if es_fpv(): modelo.armar_en_vuelo(av)           # dron FPV: armado y con el gas que lo sostiene
	_nuevo_vuelo(float(C["h"]))
	ev.empezar_guia(vs)
	hud.aviso.text = ""; ev.guiar(av)

## En la zona 2 el piloto se da la vuelta (se lanza hacia el sur); en un mundo real, con el rumbo del punto elegido.
func _orientar_lanzamiento() -> void:
	var es_m := en_mundo()
	if Escenarios.zona_de(sesion["escenario"]) != 2 and not es_m: return
	var e := Cuat.euler(av["q"])
	var rumbo: float = (float(sesion["lanz"].get("rumbo", 0)) * D2R if not sesion["lanz"].is_empty() else 0.0) if es_m else PI
	av["q"] = Cuat.desde_euler(e[0], e[1], rumbo)

func lanzar() -> void:
	if av.get("estado", "") != "en mano": return
	modelo.lanzar(av); _orientar_lanzamiento()
	hud.aviso.text = "Sube el gas (W o palanca izquierda arriba) para despegar" if es_dron() else ""
	if es_fpv(): poner_toast("ARMADO")
	if es_dron():
		get_tree().create_timer(3.0).timeout.connect(func(): if av.get("estado") == "volando" and av.get("posado", false): hud.aviso.text = "")
	if sesion["lanz_real"] and not modelo.facil and not es_dron():     # un lanzamiento a mano nunca es perfecto
		var gauss := func() -> float: return (randf() + randf() + randf() - 1.5) / 0.5
		var e := Cuat.euler(av["q"])
		av["v"][0] *= 1 + 0.08 * gauss.call()
		av["q"] = Cuat.desde_euler(e[0] + 4 * D2R * gauss.call(), e[1] + 2.5 * D2R * gauss.call(), e[2] + 3 * D2R * gauss.call())
	_nuevo_vuelo(0.0)

# =====================================================================
#  PASO DE LA SIMULACION (paso() de simulador.html)
# =====================================================================
## Entrenamiento del FPV que se vuela con las gafas (solo cuenta la camara 3): conGafas de la web.
func con_gafas() -> bool:
	var F: Dictionary = Escenarios.datos()[sesion["escenario"]].get("pista_fpv", {})
	return F.get("camara", "") == "gafas" and es_fpv()
func camara_valida() -> bool: return camara == 3 if con_gafas() else (camara == 1 or (es_dron() and camara == 3))
## Texto de la pista FPV: {cono:i} -> el pilon de color i (BBCode o solo el nombre) y <b> -> [b] (textoFpv de la web).
func texto_fpv(s: String, bb: bool) -> String:
	var re := RegEx.new(); re.compile("\\{cono:(\\d)\\}")
	for m in re.search_all(s):
		var i := int(m.get_string(1))
		s = s.replace(m.get_string(), Escenarios.pilon_bb(ent, i, true) if bb else String(ent.circuito["colores"][i]["nombre"]))
	return s.replace("<b>", "[b]").replace("</b>", "[/b]") if bb else s

func paso(dt: float) -> void:
	aplicar_recorridos()
	var viento := ent.actualizar(dt)
	modelo.servos(av, mando, dt)
	av["agl"] = -av["p"][2] - ent.altura(av["p"][0], av["p"][1])
	viento = ent.viento_a(viento, av["agl"])
	av["pg"] = ent.rafaga_alabeo(modelo.b_m, av["agl"])
	if av["estado"] != "volando": return
	var p_ant: Array = av["p"].duplicate()
	var vn: Array = modelo.paso(av, viento, dt)
	var E: Dictionary = Escenarios.datos()[sesion["escenario"]]
	if vuelo != null:
		vuelo["tVuelo"] += dt; vuelo["hmax"] = maxf(vuelo["hmax"], -av["p"][2] - ent.altura(av["p"][0], av["p"][1]))
		# un entrenamiento solo se supera visto desde el piloto (camara 1); con el dron vale tambien la pantalla de la app
		if not vuelo["otraCamara"] and not camara_valida() and not (E["objetivos"] as Array).is_empty():
			vuelo["otraCamara"] = true; poner_toast("Sin las gafas el entrenamiento no cuenta: vuelve a la cámara FPV (3)" if con_gafas() else "Con esta cámara el entrenamiento no cuenta: vuelve a la del piloto (1)")
	cn_contador += 1
	if cn_contador % CN_CADA == 0: grabar_muestra(); ev.evaluar(av, CN_CADA * DT); vigilar_exclusiones()
	if av["estado"] != "volando": return
	if ent.choca_pilon(av["p"], modelo.b_m / 2): terminar_vuelo("roto (choque con un pilón)", vn); return
	if ent.choca_arbol(av["p"], modelo.b_m / 2): terminar_vuelo("roto (choque con un árbol)", vn); return
	if ev.fpv != null:                        # pista FPV: objetivos y choques con postes, puertas y torre
		for t in ev.fpv.paso(p_ant, av, dt, { "modo": modelo.modo, "critica": modelo.celda(av) < modelo.fc["critico_celda_V"] }): poner_toast(texto_fpv(t, false))
		if ev.fpv.choque != "": terminar_vuelo("roto (" + ev.fpv.choque + ")", vn); return
	if ev.op != null:                         # operaciones: normas del operador, el trabajo y los choques con cables, torres y faro
		for t in ev.op.paso(p_ant, av, dt, { "gimbal": av.get("gimbal", -10.0), "grabando": DJI["grabando"] }): poner_toast(t)
		if ev.op.choque != "": terminar_vuelo("roto (" + ev.op.choque + ")", vn); return
	if ent.fuera_de_limites(av["p"]): terminar_vuelo("fuera de límites", vn); return
	var su = ev.contador.actualizar(p_ant, av["p"], av["t"]) if (ev.zona == 1 and ev.contador != null) else {}
	if ev.zona <= 2 and not E.has("mundo") and ev.fpv == null: _zona2(p_ant)
	if su != null and not (su as Dictionary).is_empty():
		var nom: String = ent.circuito["colores"][su["i"]]["nombre"]; var sen := int(E.get("sentido", 0))
		match String(su["tipo"]):
			"vuelta": poner_toast("¡Vuelta %d!  %.1f s" % [su["n"], su["tiempo"]])
			"dentro": poner_toast("¡Por dentro del pilón %s! Vuelta anulada" % nom)
			"sentido": poner_toast("¡Sentido contrario en el %s! El orden es %s" % [nom, ent.orden_pilones(sen)])
			_: poner_toast(("Pilón %s: salida" % nom) if int(su["n"]) == 1 else ("Pilón %s %d/4" % [nom, int(su["n"]) - 1]))
	var suelo := ent.contacto_suelo(av, vn)
	if suelo != "": terminar_vuelo(suelo, vn)

## Puerta y pasadas bajas de la zona 2 (en sus misiones y en vuelo libre), con su aviso.
func _zona2(p_ant: Array) -> void:
	var pu: Dictionary = ent.cruza_puerta(p_ant, av["p"])
	if not pu.is_empty():
		if pu["tipo"] == "puerta":
			ev.puertas += 1
			if ev.obj.has("puertaR") and ev.obj.has("pasada") and ev.obj["pasada"]["estado"] == "ok": ev.marcar("puertaR", "ok")
			poner_toast("¡Puerta %d!  (hacia el %s, a %d m)" % [ev.puertas, pu["sentido"], int(round(pu["h"]))])
		else: poner_toast(("Por encima de la puerta (%d m): no cuenta" % int(round(pu["h"]))) if pu["tipo"] == "alta" else "Por fuera de la puerta: no cuenta")
	if not ev.subido or ev.pasada == null: return          # el lanzamiento cruza la pista 2: las pasadas cuentan despues de subir
	var pb: Dictionary = ev.pasada.actualizar(av["p"])
	if not pb.is_empty():
		if pb["ok"]: ev.pasadas[pb["sentido"]] += 1; poner_toast("¡Pasada baja hacia el %s!  (%.1f–%.1f m)" % [pb["sentido"], pb["hmin"], pb["hmax"]])
		else: poner_toast("Pasada baja no válida: " + String(pb["motivo"]))

func terminar_vuelo(final: String, vn = null) -> void:
	if av["estado"] != "volando": return
	if vn == null: vn = [0.0, 0.0, 0.0]
	# lanzamiento fallido: en el suelo antes de 6 s sin pasar de 5 m. No cuenta como aterrizaje; si se ha roto, como accidente
	if vuelo != null and not es_dron() and av["t"] < LANZ["fallo_s"] and vuelo["hmax"] < LANZ["fallo_h"] and (final == "aterrizado" or final.begins_with("roto")):
		vuelo["lanzamiento"] = causa_lanzamiento_fallido(vuelo["gasLanz"])
		var roto := final.begins_with("roto")
		final = ("roto (" if roto else "") + "lanzamiento fallido: " + String(vuelo["lanzamiento"]["corto"]) + (")" if roto else "")
	av["estado"] = "roto" if final.begins_with("roto") else ("aterrizado" if final == "aterrizado" else "terminado")
	av["v"] = [0.0, 0.0, 0.0]; av["w"] = [0.0, 0.0, 0.0]; av["rpm"] = 0.0
	hud.guia.visible = false
	if vuelo == null: return
	vuelo["final"] = final; grabar_muestra()
	ev.evaluar_final(sesion["escenario"], final, av, vn)
	hud.aviso.text = ("LANZAMIENTO FALLIDO: " + String(vuelo["lanzamiento"]["corto"])) if vuelo.has("lanzamiento") else \
		(("¡ROTO!  (" + final.substr(6, final.length() - 7) + ")") if final.begins_with("roto") else ("Aterrizado" if final == "aterrizado" else
		("FUERA DE LÍMITES: el avión se ha perdido de vista" if final == "fuera de límites" else "")))
	hud.lejos_l.text = ""
	ultimo_vuelo = vuelo
	if aj.get("cn_auto", false): guardar_csv(vuelo, OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS).path_join(nombre_csv(vuelo)))
	if final == "aterrizado" or final.begins_with("roto"): sonido.evento("roto" if final.begins_with("roto") else "toque")
	var v = vuelo
	if salir_tras: salir_tras = false; guardar_vuelo(v, datos_resultado(v)); ir_inicio(); return
	if final != "abandonado": await get_tree().create_timer(1.8).timeout
	if vuelo == v and pantalla_actual == "" and not rep_activa: mostrar_resultado(v)     # si entretanto se pulso R o se salio, ya no toca

# =====================================================================
#  RESULTADO Y GUARDADO
# =====================================================================
func datos_resultado(v: Dictionary) -> Dictionary:
	var E: Dictionary = Escenarios.datos()[v["escenario"]]; var libre := (E["objetivos"] as Array).is_empty()
	var objs := []
	for k in ev.orden: objs.append({ "id": k, "texto": ev.obj[k]["texto"], "ok": ev.obj[k]["estado"] == "ok" })
	if not libre: objs.append({ "id": "camara", "texto": "Volar con las gafas FPV (cámara 3)" if con_gafas() else "Volar mirando al dron o con las gafas FPV (cámaras 1 o 3)" if es_fpv() else ("Volar mirando al dron o la pantalla de la app (cámaras 1 o 3)" if es_dron() else "Volar desde el puesto del piloto (cámara 1)"), "ok": not v["otraCamara"] })
	var apto: bool = not libre and v["final"] == "aterrizado" and objs.all(func(o): return o["ok"])
	return { "E": E, "libre": libre, "objs": objs, "apto": apto, "resultado": "LIBRE" if libre else ("APTO" if apto else "NO APTO") }

func guardar_vuelo(v: Dictionary, d: Dictionary) -> Dictionary:
	if sesion["alumno"] == null or v.get("guardado", false): return { "estado": "sin_aula" }
	v["guardado"] = true
	var vv: Dictionary = d["E"].get("viento", sesion["viento"]).duplicate()
	if not cm_es_diseno(sesion["avion"]): vv["cg_pct"] = cm_actual(sesion["avion"])["cg"]; vv["masa_g"] = cm_actual(sesion["avion"])["masa"]
	if v["dificultad"] == "facil": vv["fisica"] = "facil"
	var final: String = v["final"]
	return await aula.enviar_vuelo({ "id": v["id"], "alumno_id": sesion["alumno"]["id"], "inicio": v["inicio"], "fin": Aula.ahora_iso(),
		"avion": DatosComunes.avion(sesion["avion"]).get("nombre", sesion["avion"]), "escenario": v["escenario"], "tiempo_vuelo_s": snappedf(v["tVuelo"], 0.1),
		"accidentes": 1 if final.begins_with("roto") else 0, "aterrizajes": 1 if final == "aterrizado" else 0,
		"objetivos": d["objs"], "resultado": d["resultado"], "final": final, "viento": vv })

func mostrar_resultado(v: Dictionary) -> void:
	var R: PantallaResultado.Resultado = pantallas["pResultado"]
	if v.get("mostrado", false): mostrar("pResultado"); return
	v["mostrado"] = true
	var r := datos_resultado(v)
	R.pintar(v, r); mostrar("pResultado")
	if sesion["alumno"] == null: R.guardado.text = "Sin piloto registrado: este vuelo no se ha guardado."; return
	R.guardado.text = "Guardando…"
	var g := await guardar_vuelo(v, r)
	match String(g["estado"]):
		"ok":
			R.guardado.text = ("✓ Guardado en el registro local" + ((" y en %s." % aula.archivo.get_file()) if aula.archivo != "" else " de este ordenador.")) if aula.modo == "local" else "✓ Guardado en el registro del aula."
			sesion["alumno"]["progreso"] = g.get("progreso", {})
		"cola": R.guardado.text = "Sin conexión con el aula: se guardará solo en cuanto vuelva (no se perderá)."
		_: R.guardado.text = "No se pudo guardar: " + String(g.get("msg", ""))

func texto_vueltas_plano() -> String:
	if ev == null: return ""
	var re := RegEx.new(); re.compile("\\[[^\\]]*\\]")
	return re.sub(ev.texto_vueltas(sesion["escenario"]), "", true).replace("\n", " · ")

# =====================================================================
#  CAJA NEGRA (CSV de cada vuelo, a 20 Hz)
# =====================================================================
func grabar_muestra() -> void:
	if vuelo == null: return
	var e := Cuat.euler(av["q"]); var vn := Cuat.rot(av["q"], av["v"]); var w: Array = ent.viento["actual"]
	var r := func(x, n: int) -> float: return snappedf(float(x), pow(10, -n))
	vuelo["filas"].append([r.call(av["t"], 2), r.call(av["p"][0], 2), r.call(av["p"][1], 2), r.call(-av["p"][2], 2), r.call(av["V"], 2), r.call(Vector2(vn[0], vn[1]).length(), 2),
		r.call(-vn[2], 2), r.call(e[0] * R2D, 1), r.call(e[1] * R2D, 1), r.call(fposmod(e[2] * R2D + 360, 360), 1), r.call(av["alfa"], 2), r.call(av["beta"], 2), r.call(av["g_carga"], 2),
		r.call(av["gases"] * 100, 1), r.call(av["rpm"], 0), r.call(av["T"], 3), r.call(av["Wh"], 4), r.call(modelo.bateria_pct(av), 1),
		r.call(mando["pitch"], 3), r.call(mando["yaw"], 3), r.call(mando["trim"], 2), r.call(av["de"] * R2D, 2), r.call(av["dr"] * R2D, 2), r.call(av.get("da", 0.0) * R2D, 2),
		r.call(w[0], 2), r.call(w[1], 2), r.call(av["perdida"], 2)])

func nombre_csv(v: Dictionary) -> String:
	var d: Dictionary = v["inicio_local"]
	return "vuelo_%04d-%02d-%02d_%02d-%02d-%02d_%s_%s.csv" % [d["year"], d["month"], d["day"], d["hour"], d["minute"], d["second"], v["escenario"], String(v["final"]).split(" ")[0]]

func texto_csv(v: Dictionary) -> String:
	var d: Dictionary = v["inicio_local"]; var f: Array = v["filas"]
	var cab := ["# %s · vuelo del %02d/%02d/%04d, %02d:%02d:%02d · %s%s" % [DatosComunes.avion(sesion["avion"]).get("nombre", ""), d["day"], d["month"], d["year"], d["hour"], d["minute"], d["second"],
				Escenarios.datos()[v["escenario"]]["nombre"], (" · " + String(sesion["alumno"]["nombre"])) if sesion["alumno"] != null else ""],
		"# masa %d g · %s · viento %s m/s %s rachas · final: %s · %d muestras a 20 Hz" % [int(round(modelo.masa_kg * 1000)), texto_cm(), str(ent.viento["base"]), "con" if ent.viento["rachas"] else "sin", v["final"], f.size()],
		"# ruta: x al norte, y al este, z altura (m, desde el lanzamiento) · profundidad: + = abajo · timon: + = a la derecha · aleron: + = alabeo a la derecha"]
	var lineas := PackedStringArray(cab); lineas.append(",".join(CN_COLUMNAS))
	for x in f: lineas.append(",".join(x.map(func(n): return str(int(n)) if float(n) == int(n) else str(n))))
	return "\n".join(lineas) + "\n"

func guardar_csv(v: Dictionary, ruta: String) -> void:
	var fa := FileAccess.open(ruta, FileAccess.WRITE)
	if fa == null: poner_toast("No se pudo guardar la caja negra"); return
	fa.store_string(texto_csv(v)); fa.close()

func guardar_csv_dialogo() -> void:
	if ultimo_vuelo == null: return
	dialogo.title = "Guardar la caja negra"; dialogo.current_dir = OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS); dialogo.current_file = nombre_csv(ultimo_vuelo)
	for c in dialogo.file_selected.get_connections(): dialogo.file_selected.disconnect(c["callable"])
	dialogo.file_selected.connect(func(ruta): guardar_csv(ultimo_vuelo, ruta), CONNECT_ONE_SHOT)
	dialogo.popup_centered_ratio(0.6)

# =====================================================================
#  REPETICION: el vuelo grabado en la caja negra (20 Hz), interpolado
# =====================================================================
func ver_repeticion() -> void:
	var v = ultimo_vuelo
	if v == null or (v["filas"] as Array).size() < 2: return
	REP = { "activa": true, "filas": v["filas"], "t": 0.0, "dur": float(v["filas"][-1][0]), "pausa": false, "i": 0, "vuelo": v }; rep_activa = true
	av = modelo.estado_inicial(); av["estado"] = "repetición"; colocar_en_base(av)
	hud.rep.visible = true; mostrar(""); hud.obj_rt.text = ""; hud.aviso.text = ""

func _paso_repeticion(dt: float) -> void:
	var f: Array = REP["filas"]
	if not REP["pausa"]: REP["t"] = minf(REP["dur"], REP["t"] + dt)
	var i: int = REP["i"]
	while i < f.size() - 2 and f[i + 1][0] <= REP["t"]: i += 1
	while i > 0 and f[i][0] > REP["t"]: i -= 1
	REP["i"] = i
	var a: Array = f[i]; var b: Array = f[mini(f.size() - 1, i + 1)]
	var u: float = clampf((REP["t"] - a[0]) / (b[0] - a[0]), 0, 1) if b[0] > a[0] else 0.0
	var L := func(j: int) -> float: return a[j] + (b[j] - a[j]) * u
	var ang := func(j: int) -> float:
		var d: float = b[j] - a[j]
		if d > 180: d -= 360
		if d < -180: d += 360
		return a[j] + d * u
	av["p"] = [L.call(1), L.call(2), -L.call(3)]; av["q"] = Cuat.desde_euler(ang.call(7) * D2R, ang.call(8) * D2R, ang.call(9) * D2R)
	av["V"] = L.call(4); av["alfa"] = L.call(10); av["g_carga"] = L.call(12); av["gases"] = L.call(13) / 100; av["rpm"] = L.call(14); av["Wh"] = L.call(16)
	av["perdida"] = L.call(26); av["t"] = REP["t"]; av["de"] = L.call(21) * D2R; av["dr"] = L.call(22) * D2R; av["da"] = L.call(23) * D2R; av["v"] = [av["V"], 0.0, 0.0]
	mando["pitch"] = L.call(18); mando["yaw"] = L.call(19)
	hud.rep_l.text = "[b]REPETICIÓN[/b] · %.1f s de %.1f%s · espacio: pausa · ← →: 5 s · 1/2/3: cámara · Esc: salir" % [REP["t"], REP["dur"], " · pausa" if REP["pausa"] else ""]
	hud.rep_barra.size.x = hud.rep_fondo.size.x * REP["t"] / maxf(0.1, REP["dur"])
	if REP["t"] >= REP["dur"]: REP["pausa"] = true

func _salir_repeticion() -> void:
	REP["activa"] = false; rep_activa = false; hud.rep.visible = false; mostrar_resultado(REP["vuelo"])

# =====================================================================
#  PAUSA
# =====================================================================
func _nombre_camara(n: int) -> String: return ["", "piloto", "persecución", "FPV (gafas)" if (modelo != null and es_fpv()) else ("del dron" if (modelo != null and es_dron()) else "a bordo")][n]
func _texto_instr() -> String: return ("OSD: " if es_fpv() else ("Pantalla de la app: " if es_dron() else "Instrumentos: ")) + ("no" if sin_instrumentos else "sí")
func poner_pausa(si: bool) -> void:
	if si == pausado: return
	pausado = si; pausa["raiz"].visible = si
	if si:
		pausa["camara"].text = "Cámara: " + _nombre_camara(camara)
		pausa["instr"].text = _texto_instr()
		pausa["sonido"].set_pressed_no_signal(sonido.on)
		pausa["info"].text = "%s · %s" % [DatosComunes.avion(sesion["avion"]).get("nombre", ""), Escenarios.datos()[sesion["escenario"]]["nombre"]]
		sonido.silenciar(true)
	else:
		sonido.silenciar(not sonido.on or pantalla_actual != ""); hud.ayuda.visible = false; get_viewport().gui_release_focus()
func cambiar_camara_pausa() -> void:
	camara = camara % 3 + 1; pausa["camara"].text = "Cámara: " + _nombre_camara(camara)
func cambiar_instrumentos_pausa() -> void:
	sin_instrumentos = not sin_instrumentos
	pausa["instr"].text = _texto_instr()
func terminar_desde_pausa() -> void:
	poner_pausa(false)
	if av["estado"] == "volando": terminar_vuelo("abandonado")
	elif vuelo != null and vuelo["final"] != "": mostrar_resultado(vuelo)
	else: ir_inicio()
## Sale al menu principal: si habia un vuelo en marcha se guarda (si hay piloto) sin pasar por el resultado.
func salir_al_menu() -> void:
	poner_pausa(false)
	if not av.is_empty() and av["estado"] == "volando" and vuelo != null: salir_tras = true; terminar_vuelo("abandonado")
	else: ir_inicio()

# =====================================================================
#  APP DJI FLY (cuadricoptero)
# =====================================================================
func dji_modo(m := "") -> void:
	if modelo == null or not es_dron() or es_fpv(): return
	modelo.modo = m if m != "" else { "N": "S", "S": "C", "C": "N" }.get(modelo.modo, "N")
	poner_toast("Modo %s%s" % [NOMBRES_MODO[modelo.modo], " · sin frenado suave" if modelo.modo == "S" else ""])
func dji_foto() -> void:
	if modelo == null or not es_dron(): return
	DJI["fotos"] += 1; hud_dji.foto()
	var T: Array = ev.op.foto(av, av.get("gimbal", -10.0)) if (ev != null and ev.op != null) else []     # operaciones: lo que vale esa foto
	poner_toast(" · ".join(T) if not T.is_empty() else "Foto %d" % DJI["fotos"])
func dji_video() -> void:
	if modelo == null or not es_dron(): return
	DJI["video"] = true; DJI["grabando"] = not DJI["grabando"]
	if DJI["grabando"]: DJI["tRec"] = 0.0; DJI["tAnt"] = av["t"]
	poner_toast("Grabando" if DJI["grabando"] else "Vídeo guardado")
func dji_disparo() -> void:
	if DJI["video"]: dji_video()
	else: dji_foto()
func dji_cam_modo() -> void:
	DJI["video"] = not DJI["video"]
	if not DJI["video"]: DJI["grabando"] = false
## Boton de despegue de la app: en el suelo arma y sube a 1,2 m; en vuelo, aterriza en el sitio.
func dji_despegar() -> void:
	if modelo == null or not es_dron() or rep_activa: return
	if av["estado"] == "en mano": lanzar(); modelo.despegar(av); hud.aviso.text = ""
	elif av["estado"] == "volando" and av.get("posado", false): modelo.despegar(av)
	elif av["estado"] == "volando": av["rth"] = { "fase": "bajar" }; poner_toast("Aterrizando")
func dji_rth() -> void:
	if modelo == null or not es_dron() or rep_activa or av["estado"] != "volando" or av.get("posado", false): return
	if av.get("rth") != null and av["rth"]["fase"] != "bajar": av["rth"] = null; poner_toast("Volver a casa cancelado"); return
	modelo.volver_a_casa(av); poner_toast("Volviendo a casa")

# =====================================================================
#  DRON FPV: armar / desarmar y modos de Betaflight (el OSD esta en hud_fpv.gd)
# =====================================================================
## Armar (solo con el gas abajo, como un FPV de verdad) o desarmar (en el aire se cae; en el suelo tras volar, aterrizado).
## Gas del FPV con un mando de consola (gasFpvConsola de la web): el centro de la palanca con muelle es el gas del
## estacionario (thr_mid de Betaflight), arriba del todo todo el gas, abajo nada, con curva suave cerca del centro; en
## el suelo con la palanca en reposo, cero (se arma sin despegar). s: palanca (+1 arriba).
const FPV_GAS_ESTACIONARIO := 0.30               # medido: el FPV de 650 g se sostiene con el 30,4 % (bateria llena)
func gas_fpv_consola(s: float) -> float:
	var f := func(x: float) -> float: return 0.25 * x + 0.75 * x * x * x
	if (av.get("posado", false) or av["estado"] == "en mano") and s <= 0.05: return 0.0
	return FPV_GAS_ESTACIONARIO + (1 - FPV_GAS_ESTACIONARIO) * f.call(s) if s >= 0 else FPV_GAS_ESTACIONARIO * (1 - f.call(-s))
func fpv_armar() -> void:
	if modelo == null or not es_fpv() or rep_activa: return
	if av["estado"] == "en mano":
		if av["gases"] > 0.05: poner_toast("Para armar, baja el gas del todo (S o palanca izquierda abajo)"); return
		lanzar()
	elif av["estado"] == "volando" and av["armado"]:
		modelo.desarmar(av); poner_toast("DESARMADO")
		if av["estado"] == "en mano": hud.aviso.text = "Gas abajo del todo y L (o botón A) para armar"
## Modo de vuelo de Betaflight: ANGLE -> HORIZON -> ACRO -> ANGLE (tecla M, LB del mando o el que se pida).
func fpv_modo(m := "") -> void:
	if modelo == null or not es_fpv(): return
	modelo.modo = m if m != "" else { "ANGLE": "HORIZON", "HORIZON": "ACRO", "ACRO": "ANGLE" }.get(modelo.modo, "ANGLE")
	poner_toast("Modo %s%s" % [modelo.modo, " · sin autonivelado" if modelo.modo == "ACRO" else (" · se nivela solo" if modelo.modo == "ANGLE" else "")])

# =====================================================================
#  TECLADO
# =====================================================================
func _unhandled_input(e: InputEvent) -> void:
	if pantalla_actual != "" or modal["raiz"].visible: return
	if e is InputEventMouseButton and e.pressed and (e.button_index == MOUSE_BUTTON_WHEEL_UP or e.button_index == MOUSE_BUTTON_WHEEL_DOWN) and camara == 1:
		# con la camara del piloto, la rueda del raton cambia el zoom (fuera del GPS, que tiene su propia rueda)
		var abajo: bool = e.button_index == MOUSE_BUTTON_WHEEL_DOWN; var z0: float = aj.get("zoom_piloto", 0.03)
		var z := clampf(z0 * (0.85 if abajo else 1 / 0.85) if z0 > 0 else (0.03 if not abajo else 0.0), 0, 0.3)
		poner_zoom_piloto(0.0 if (z < 0.025 and abajo) else snappedf(z, 0.001))
		poner_toast(("Zoom del piloto: el avión ocupa un %d %% de la pantalla" % int(round(aj["zoom_piloto"] * 100))) if aj["zoom_piloto"] > 0 else "Sin zoom: como lo ve el ojo")
		return
	if not (e is InputEventKey and e.pressed and not e.echo): return
	var k: int = e.physical_keycode
	if rep_activa:          # repeticion: espacio pausa, flechas 5 s, 1/2/3 camara, Esc sale
		match k:
			KEY_ESCAPE: _salir_repeticion()
			KEY_SPACE: REP["pausa"] = not REP["pausa"]
			KEY_LEFT: REP["t"] = maxf(0, REP["t"] - 5)
			KEY_RIGHT: REP["t"] = minf(REP["dur"], REP["t"] + 5)
			KEY_1: camara = 1
			KEY_2: camara = 2
			KEY_3: camara = 3
		get_viewport().set_input_as_handled(); return
	if k == KEY_ESCAPE:     # con la ventana de controles abierta, Esc la cierra (y sigue el vuelo); si no, pausa
		if briefing.visible: ver_briefing(false)
		elif hud.ayuda.visible: hud.ayuda.visible = false; poner_pausa(false)
		else: poner_pausa(not pausado)
		get_viewport().set_input_as_handled(); return
	if pausado: return
	var libre := Escenarios.libre(sesion["escenario"]); var vto: Dictionary = ent.viento; var dron := es_dron()
	if es_fpv():            # dron FPV: L arma y desarma, M cambia de modo
		match k:
			KEY_M: fpv_modo()
			KEY_L: fpv_armar()
	elif dron:
		match k:
			KEY_M: dji_modo()
			KEY_H: dji_rth()
			KEY_F: dji_foto()
			KEY_V: dji_video()
	match k:
		KEY_L:
			if not es_fpv(): lanzar()
		KEY_R: reiniciar()
		KEY_B: ver_briefing()
		KEY_SPACE: av["gases"] = 0.0
		KEY_1: camara = 1
		KEY_2: camara = 2
		KEY_3: camara = 3
		KEY_I:
			sin_instrumentos = not sin_instrumentos
			poner_toast(("Sin OSD" if sin_instrumentos else "OSD") if es_fpv() else ("Sin la pantalla de la app" if sin_instrumentos else "Pantalla de la app") if dron else ("Sin instrumentos (como en el campo)" if sin_instrumentos else "Instrumentos"))
		KEY_T: hud.ayuda.visible = not hud.ayuda.visible
		KEY_BRACKETLEFT: mando["trim"] = maxf(-6, mando["trim"] - 0.25)
		KEY_BRACKETRIGHT: mando["trim"] = minf(6, mando["trim"] + 0.25)
	if k == KEY_H and not dron: mostrar_hud = not mostrar_hud
	if k == KEY_G and libre: vto["rachas"] = not vto["rachas"]
	var tecla: int = e.keycode
	if libre and (tecla == KEY_PLUS or tecla == KEY_KP_ADD or (e.unicode == 43)): vto["base"] = minf(10, vto["base"] + 1)
	if libre and (tecla == KEY_MINUS or tecla == KEY_KP_SUBTRACT or (e.unicode == 45)): vto["base"] = maxf(0, vto["base"] - 1)
	get_viewport().set_input_as_handled()

static func _zona_muerta(x: float, z: float) -> float: return 0.0 if absf(x) < z else signf(x) * (absf(x) - z) / (1 - z)
static func _expo(x: float, e: float) -> float: return (1 - e) * x + e * x * x * x

# =====================================================================
#  MANDO: palanca derecha = avion, izquierda = gas (o el mando del DJI). Ejes segun Ajustes › Controles (MandoCfg).
# =====================================================================
func _leer_mando(dt: float) -> bool:
	var M := mando_cfg; var dev := MandoCfg.conectado()
	if dev < 0: return false
	var rx := _zona_muerta(M.eje(dev, "rx"), M.zona); var ry := _zona_muerta(M.eje(dev, "ry"), M.zona)
	var ly := _zona_muerta(M.eje(dev, "ly"), M.zona); var lx := _zona_muerta(M.eje(dev, "lx"), M.zona)
	var cuad := modelo != null and es_dron() and not es_fpv(); var fpv := modelo != null and es_fpv()   # el FPV lleva el gas como un avion
	var pulsado := func(b: int) -> bool:
		var ahora := Input.is_joy_button_pressed(dev, b); var antes: bool = _botones_antes.get(b, false); _botones_antes[b] = ahora
		return ahora and not antes
	var b_start: bool = pulsado.call(JOY_BUTTON_START)
	var bs := {}
	for b in [JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_X, JOY_BUTTON_Y, JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER, JOY_BUTTON_BACK, JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN]:
		bs[b] = pulsado.call(b)
	if pantalla_actual == "" and b_start: poner_pausa(not pausado)
	M.gimbal = 0.0
	if pantalla_actual == "" and not pausado and fpv:     # dron FPV: A armar/desarmar, LB modo, RB camara, Back reiniciar
		if bs[JOY_BUTTON_A]: fpv_armar()
		if bs[JOY_BUTTON_LEFT_SHOULDER]: fpv_modo()
		if bs[JOY_BUTTON_RIGHT_SHOULDER]: camara = camara % 3 + 1
		if bs[JOY_BUTTON_BACK]: reiniciar()
	elif pantalla_actual == "" and not pausado and cuad:    # mando del DJI: A despegar/aterrizar, B casa, X video, Y foto, LB modo, RB camara, Back reiniciar
		if bs[JOY_BUTTON_A]: dji_despegar()
		if bs[JOY_BUTTON_B]: dji_rth()
		if bs[JOY_BUTTON_X]: dji_video()
		if bs[JOY_BUTTON_Y]: dji_foto()
		if bs[JOY_BUTTON_LEFT_SHOULDER]: dji_modo()
		if bs[JOY_BUTTON_RIGHT_SHOULDER]: camara = camara % 3 + 1
		if bs[JOY_BUTTON_BACK]: reiniciar()
		if M.perfil == "consola": M.gimbal = Input.get_joy_axis(dev, JOY_AXIS_TRIGGER_RIGHT) - Input.get_joy_axis(dev, JOY_AXIS_TRIGGER_LEFT)   # gatillos: rueda del gimbal
		# CSC (combinacion de palancas de DJI): las dos abajo y hacia dentro (o hacia fuera) medio segundo arranca los motores
		var csc := ly > 0.8 and ry > 0.8 and ((lx > 0.6 and rx < -0.6) or (lx < -0.6 and rx > 0.6))
		_t_csc = _t_csc + dt if csc else 0.0
		if _t_csc > 0.5 and av.get("estado", "") == "en mano": _t_csc = -1e9; lanzar(); poner_toast("Motores en marcha (CSC): sube la palanca izquierda para despegar")
	elif pantalla_actual == "" and not pausado:
		if bs[JOY_BUTTON_A]: lanzar()
		if bs[JOY_BUTTON_B]: av["gases"] = 0.0
		if bs[JOY_BUTTON_Y]: camara = camara % 3 + 1
		if bs[JOY_BUTTON_X]: reiniciar()
		if bs[JOY_BUTTON_DPAD_UP]: mando["trim"] = minf(6, mando["trim"] + 0.25)
		if bs[JOY_BUTTON_DPAD_DOWN]: mando["trim"] = maxf(-6, mando["trim"] - 0.25)
	if pausado: return false
	# palanca derecha: hacia ti = tirar = morro arriba; a la derecha = alabeo/timon a la derecha
	var moviendo := rx != 0 or ry != 0 or lx != 0 or (cuad and ly != 0)
	if moviendo or _mando_usado:
		mando["pitch"] = _expo(ry, M.expo); mando["yaw"] = _expo(rx, M.expo)
		mando["pitchObj"] = mando["pitch"]; mando["yawObj"] = mando["yaw"]
		mando["guinada"] = _expo(lx, M.expo); mando["guinadaObj"] = mando["guinada"]   # izquierda de lado: guinada del dron o timon de 4 canales
		if cuad: mando["vz"] = -ly; mando["vzObj"] = mando["vz"]
	if moviendo: _mando_usado = true
	# palanca izquierda: gas (eje Y negativo = arriba)
	if not av["motorRoto"] and fpv and M.perfil == "consola":     # FPV con mando de consola (palanca con muelle): gas_fpv_consola
		if ly != 0: _gas_fpv_mando = true                          # desde que se toca la palanca del gas en este vuelo
		if _gas_fpv_mando: av["gases"] = gas_fpv_consola(-ly)
	elif not av["motorRoto"] and not cuad:
		if M.gas == "absoluto":
			if _mando_usado or ly != 0: av["gases"] = clampf((1 - M.eje(dev, "ly")) / 2, 0, 1)
		elif ly != 0: av["gases"] = clampf(av["gases"] - ly * 0.7 * dt, 0, 1)
	return moviendo or _mando_usado

func _leer_teclado(dt: float) -> void:
	var cuad := es_dron() and not es_fpv(); var T := func(k: int) -> bool: return Input.is_physical_key_pressed(k)   # en el FPV W/S son el gas
	var tecla_palanca: bool = T.call(KEY_DOWN) or T.call(KEY_UP) or T.call(KEY_RIGHT) or T.call(KEY_LEFT) or T.call(KEY_A) or T.call(KEY_D) or ((cuad or es_fpv()) and (T.call(KEY_W) or T.call(KEY_S)))   # en el FPV, W/S tambien devuelven el gas al teclado
	if tecla_palanca: _mando_usado = false            # si se tocan las flechas, vuelve a mandar el teclado
	if es_fpv() and (T.call(KEY_W) or T.call(KEY_S)): _gas_fpv_mando = false      # W/S: el gas vuelve al teclado
	var gimbal_teclas := ((1.0 if T.call(KEY_E) else 0.0) - (1.0 if T.call(KEY_Q) else 0.0)) if cuad else 0.0
	if _leer_mando(dt) and not tecla_palanca:
		mando["gimbal"] = gimbal_teclas if gimbal_teclas != 0 else mando_cfg.gimbal; _leer_gas_teclado(dt); return
	mando["gimbal"] = gimbal_teclas if gimbal_teclas != 0 else mando_cfg.gimbal
	mando["pitchObj"] = (1.0 if T.call(KEY_DOWN) else 0.0) - (1.0 if T.call(KEY_UP) else 0.0)     # +1 = tirar
	mando["yawObj"] = (1.0 if T.call(KEY_RIGHT) else 0.0) - (1.0 if T.call(KEY_LEFT) else 0.0)
	mando["guinadaObj"] = (1.0 if T.call(KEY_D) else 0.0) - (1.0 if T.call(KEY_A) else 0.0)
	mando["vzObj"] = (1.0 if T.call(KEY_W) else 0.0) - (1.0 if T.call(KEY_S) else 0.0)
	for k in ["pitch", "yaw", "guinada", "vz"]:      # la palanca va al tope a 5/s y vuelve al centro a 8/s
		var obj: float = mando[k + "Obj"]; var vel := 8.0 if obj == 0 else 5.0; var d: float = obj - mando[k]
		mando[k] += signf(d) * minf(absf(d), vel * dt)
	_leer_gas_teclado(dt)

func _leer_gas_teclado(dt: float) -> void:
	if av["motorRoto"] or (es_dron() and not es_fpv()): return          # en el DJI W/S son velocidad vertical
	var k := 0.4 if es_fpv() else 0.8                # FPV: mas despacio (se sostiene con un 30 % de gas)
	if Input.is_physical_key_pressed(KEY_W): av["gases"] = minf(1, av["gases"] + k * dt)
	if Input.is_physical_key_pressed(KEY_S): av["gases"] = maxf(0, av["gases"] - k * dt)

# =====================================================================
#  BUCLE, CAMARAS Y HUD
# =====================================================================
func _process(dt_real: float) -> void:
	var dt := minf(0.1, dt_real)
	if not sala.is_empty():                           # multijugador: 10 veces por segundo
		_multi_t += dt_real
		if _multi_t >= 0.1: _multi_t = 0.0; _enviar_sala()
	if pantalla_actual != "" or av.is_empty() or modelo == null:
		_acum = 0.0
		if pantalla_actual != "": _leer_mando_en_menu()
		if _args.has("auto") and modelo != null and not av.is_empty(): _auto(dt_real)      # pruebas: la captura puede ser del resultado
		return
	var t_us := Time.get_ticks_usec()
	if rep_activa: _paso_repeticion(dt)
	elif pausado: _leer_mando(dt)
	else:
		if _args.has("auto"): _piloto_auto()
		else: _leer_teclado(dt)
		_acum += dt
		while _acum >= DT: paso(DT); _acum -= DT
		var b: Vector3 = vista.base + Vector3(1.5, 1.7, 2)
		sonido.actualizar(av, Sonido.lejos_de(b.distance_to(Avion3D.ned(av["p"]))), camara == 1)
		_t_obj += dt
		if _t_obj > 0.2: _t_obj = 0; _pintar_objetivos(); _pintar_sala_info()
	var t_fis := Time.get_ticks_usec() - t_us
	avion3d.camara_fpv = es_fpv() and camara == 3     # con la camara FPV el dron no se dibuja
	avion3d.actualizar(av)
	if not sala.is_empty() or not _fantasmas.is_empty(): _poner_fantasmas()
	vista.actualizar_manga(ent.viento["actual"])
	_camara()
	_hud()
	if _args.has("auto") and _t_auto > 1.5: _us.append([t_fis, Time.get_ticks_usec() - t_us])
	_auto(dt_real)

func _leer_mando_en_menu() -> void:       # en las pantallas solo se mira el Start (como en la web, que no hace nada)
	pass

func lectura_vs() -> float: return _vs

func _camara() -> void:
	var t := Avion3D.ned(av["p"])
	if _args.has("cenital"):          # pruebas: vista vertical del punto de lanzamiento desde la altura dada
		cam.fov = 60; cam.global_position = vista.base + Vector3(0, float(_args["cenital"]), 0); cam.look_at(vista.base, Vector3.FORWARD); return
	if camara == 1:
		# vista del piloto con ZOOM AUTOMATICO, como en el navegador: la envergadura ocupa la fraccion zoom_piloto del alto
		# de la pantalla (10 % por defecto; 0 = sin zoom, como lo ve el ojo), entre 50 y 1,5 grados. Suavizado
		var b: Vector3 = vista.base + Vector3(1.5, 1.7, 2)
		var env: float = float(modelo.b_m); var zp: float = aj.get("zoom_piloto", 0.03)
		var d: float = b.distance_to(t); var obj: float = clampf(rad_to_deg(env / (zp * maxf(d, 0.5))), 1.5, 50.0) if zp > 0 else 50.0
		_fov1 = obj if _fov1 < 0 else _fov1 + (obj - _fov1) * 0.08
		cam.fov = _fov1; cam.global_position = b
		if d > 0.1: cam.look_at(t, Vector3.UP)
	elif camara == 2:
		var yaw: float = Cuat.euler(av["q"])[2]
		cam.fov = 60; cam.global_position = t + Avion3D.ned([-cos(yaw) * 5, -sin(yaw) * 5, -1.5]); cam.look_at(t, Vector3.UP)
	elif es_fpv():
		# camara FPV: fija al bastidor, inclinada hacia arriba (uptilt) y gran angular (campo de vision HORIZONTAL fijo)
		var F: Dictionary = modelo.fc; var ti: float = F["camara_inclinacion_grados"] * D2R; var q: Array = av["q"]
		var pos := t + Avion3D.ned(Cuat.rot(q, F["camara_pos"])); var fw := Avion3D.ned(Cuat.rot(q, [cos(ti), 0.0, -sin(ti)])); var up := Avion3D.ned(Cuat.rot(q, [-sin(ti), 0.0, -cos(ti)]))
		var asp: float = get_viewport().get_visible_rect().size.aspect()
		cam.fov = rad_to_deg(2 * atan(tan(deg_to_rad(F["camara_fov_h_grados"]) / 2) / asp)); cam.global_position = pos; cam.look_at(pos + fw, up)
	elif es_dron():
		# camara del dron en su gimbal: nivelada, con el rumbo del dron y la inclinacion de la rueda (av.gimbal)
		var yaw: float = Cuat.euler(av["q"])[2]; var g: float = av.get("gimbal", -10.0) * D2R
		var pos := t + Avion3D.ned(Cuat.rot(av["q"], [0.1, 0.0, -0.1]))
		var fw := Avion3D.ned([cos(yaw) * cos(g), sin(yaw) * cos(g), -sin(g)])
		cam.fov = 58; cam.global_position = pos
		cam.look_at(pos + fw, Vector3.UP if absf(g) < 89.5 * D2R else Avion3D.ned([cos(yaw), sin(yaw), 0.0]))
	else:
		var q: Array = av["q"]
		var pos := t + Avion3D.ned(Cuat.rot(q, [0.3, 0.0, -0.1])); var fw := Avion3D.ned(Cuat.rot(q, [1.0, 0.0, 0.0])); var up := Avion3D.ned(Cuat.rot(q, [0.0, 0.0, -1.0]))
		cam.fov = 80; cam.global_position = pos; cam.look_at(pos + fw, up)

func _pintar_objetivos() -> void:
	var E: Dictionary = Escenarios.datos()[sesion["escenario"]]
	var t := "[font_size=14][b][color=#ffc83d]%s[/color][/b][/font_size]\n" % E["nombre"]     # #objetivos h3: acento, 14 px
	if E.has("mundo") and ev.op != null:       # operacion: lo que toca ahora y la orden de trabajo
		t += texto_fpv(ev.op.ahora(ev.obj, av), true) + "\n" + ev.lineas_objetivos()
		if sesion["alumno"] != null: t += "[font_size=12][color=#aaaaaa]%s[/color][/font_size]" % sesion["alumno"]["nombre"]
	elif E.has("mundo"):
		var suelo := ent.altura(av["p"][0], av["p"][1])
		t += "Terreno a %d m sobre el mar · casa a [b]%d m[/b]" % [int(round(suelo + ent.terreno["h0"])), int(round(Vector2(av["p"][0] - casa["N"], av["p"][1] - casa["E"]).length()))]
	elif (E["objetivos"] as Array).is_empty(): t += ev.texto_orden() + ev.texto_vueltas(sesion["escenario"])
	else:
		if ev.obj.has("circ1"): t += ev.texto_orden()
		if ev.obj.has("ocho1"): t += ev.texto_ocho()
		if ev.zona == 2 and ev.fpv == null: t += ev.texto_zona2(sesion["escenario"])
		if ev.fpv != null: t += texto_fpv(ev.fpv.ahora(ev.obj, av), true) + "
"
		t += ev.lineas_objetivos()
		if sesion["alumno"] != null: t += "[font_size=12][color=#aaaaaa]%s[/color][/font_size]" % sesion["alumno"]["nombre"]
	hud.obj_rt.text = t.strip_edges()
	hud.guia.visible = ev.guia_bb != "" and not ev.guia.is_empty() and av["estado"] == "volando"
	hud.guia_rt.text = ev.guia_bb

func _hud() -> void:
	var e := Cuat.euler(av["q"]); var roll: float = e[0] * R2D; var pitch: float = e[1] * R2D; var yaw: float = e[2] * R2D
	var h := maxf(0, -av["p"][2]); var dist := Vector2(av["p"][0] - casa["N"], av["p"][1] - casa["E"]).length()
	var vn := Cuat.rot(av["q"], av["v"]); var vs: float = -vn[2]; _vs = vs
	var vto: Dictionary = ent.viento; var suelo := ent.altura(av["p"][0], av["p"][1]); var dron := es_dron()
	var est := "REPETICIÓN" if rep_activa else ("EN EL SUELO" if (av["estado"] == "en mano" and dron) else String(av["estado"]).to_upper())
	var partes := [["%s · %d s" % [est, int(av["t"])], false]]
	if vuelo != null and av["estado"] == "volando": partes.append(["● REC", true])
	if av["motorRoto"]: partes.append(["MOTOR PARADO", true])
	if modelo.facil: partes.append(["física fácil", false])
	if pausado: partes.append(["PAUSA", false])
	hud.pintar_estado(partes)
	if dron and av["estado"] == "volando" and not av.get("posado", false) and hud.aviso.text.begins_with("Sube el gas"): hud.aviso.text = ""
	var bat: float = modelo.bateria_pct(av)
	var v_clase := "rojo" if (vel_perdida > 0 and av["V"] < 1.1 * vel_perdida) else ("ambar" if (vel_perdida > 0 and av["V"] < 1.3 * vel_perdida) else "")
	var lect := []
	if not ((av["estado"] == "en mano" and vuelo == null) or sin_instrumentos):
		lect = [["%.1f" % av["V"], "vel. aire m/s", v_clase], ["%d" % int(round(h - suelo)), "altura m", ""], ["%s%.1f" % ["+" if vs >= 0 else "", vs], "asc. m/s", ""],
				["%03d°" % int(round(fposmod(yaw + 360, 360))), "rumbo", ""], ["%d" % int(round(dist)), "dist. m", ""], ["%d%%" % int(round(bat)), "batería", "rojo" if bat < 20 else ""]]
		if av["perdida"] > 0.5: lect.append(["¡PÉRDIDA!", "alfa %d°" % int(round(av["alfa"])), "rojo"])
	hud.pintar_lecturas(lect)
	hud.hud_texto.visible = mostrar_hud and not dron
	if hud.hud_texto.visible:
		hud.hud_rt.text = ("vel. aire [b]%.1f[/b] m/s · suelo %.1f m/s · asc. %s%.1f m/s\n" % [av["V"], Vector2(vn[0], vn[1]).length(), "+" if vs >= 0 else "", vs]) + \
			("altura [b]%.1f[/b] m%s · distancia %d m\n" % [h, (" (sobre el terreno %d m)" % int(round(h - suelo))) if en_mundo() else "", int(round(dist))]) + \
			("alabeo %d° · cabeceo %d° · rumbo %d°\n" % [int(round(roll)), int(round(pitch)), int(round(fposmod(yaw + 360, 360)))]) + \
			("alfa %.1f° %s · carga %.1f g\n" % [av["alfa"], "[b]¡PÉRDIDA![/b]" if av["perdida"] > 0.5 else "", av["g_carga"]]) + \
			("gases [b]%d %%[/b] · batería %d %%\n" % [int(round(av["gases"] * 100)), int(round(bat))]) + \
			("viento %d m/s%s · compensador %.2f° · cámara %d" % [int(round(vto["base"])), " con rachas" if vto["rachas"] else "", mando["trim"], camara]) + \
			("" if cm_es_diseno(sesion["avion"]) else "\n[b][color=#ffb74d]%s[/color][/b]" % texto_cm())
	var L: Dictionary = ent.limites
	if av["estado"] == "volando" and not en_mundo() and dist > L["aviso_m"]:
		var hacia := int(round(fposmod(atan2(-av["p"][1], -av["p"][0]) * R2D + 360, 360)))
		hud.lejos_l.text = "¡Demasiado lejos! (%d m) Da la vuelta: el campo está al rumbo %d°. A %d m se pierde el avión." % [int(round(dist)), hacia, int(L["distancia_m"])]
	else: hud.lejos_l.text = aviso_lanzamiento() if (av["estado"] == "en mano" and not rep_activa) else ""
	hud.lejos.visible = hud.lejos_l.text != ""
	hud.disponer(camara == 1, sin_instrumentos, true, true, dron)
	hud_dji.visible = dron and not es_fpv() and not sin_instrumentos
	if dron and not es_fpv(): hud_dji.pintar(h, vn, vs, dist)
	hud_fpv.visible = es_fpv() and not sin_instrumentos
	if es_fpv(): hud_fpv.pintar(h, vn)

## Piloto automatico de las pruebas: alas niveladas, subida suave hasta 60 m sobre el terreno y luego crucero.
func _piloto_auto() -> void:
	if av["estado"] != "volando": return
	if es_fpv():            # dron FPV en ANGLE: sube a 30 m con el gas y vuela en circulo despacio
		var vz: float = -Cuat.rot(av["q"], av["v"])[2]; var hh: float = av.get("agl", 0.0); var eu := Cuat.euler(av["q"])
		av["gases"] = clampf(0.32 / maxf(0.5, cos(eu[0]) * cos(eu[1])) + 0.04 * (30.0 - hh) - 0.05 * vz, 0, 1)
		mando["pitch"] = -0.3 if hh > 8 else 0.0; mando["yaw"] = 0.12 if hh > 8 else 0.0; mando["guinada"] = 0.0
		return
	var e := Cuat.euler(av["q"]); var alto: bool = av.get("agl", 0.0) > 60
	mando["yaw"] = clampf(-(e[0] / D2R - (20.0 if alto else 0.0)) / 45.0, -0.6, 0.6)
	mando["pitch"] = clampf(((2.0 if alto else 10.0) - e[1] / D2R) / 15.0, -0.6, 0.6)
	if es_dron(): mando["vz"] = 0.6 if av.get("agl", 0.0) < 30 else 0.0; mando["pitch"] = -0.5 if av.get("agl", 0.0) > 10 else 0.0; mando["yaw"] = 0.0
	else: av["gases"] = 0.55 if alto else float(_args.get("gases", "1"))

## Pruebas desde la linea de ordenes: vuela solo (gases y lanzamiento), mide el tiempo por cuadro y guarda una captura.
func _auto(dt_real: float) -> void:
	if not _args.has("auto"): return
	_t_auto += dt_real
	if _args.has("vista") and not av.is_empty():     # pruebas: dron quieto en N,E,altura,rumbo,gimbal para la captura
		var w := Array(String(_args["vista"]).split(",")).map(func(x): return float(x))
		av["p"] = [w[0], w[1], -(ent.altura(w[0], w[1]) + w[2])]; av["q"] = Cuat.desde_euler(0, 0, w[3] * D2R); av["gimbal"] = w[4]; av["v"] = [0.0, 0.0, 0.0]
	var vp := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	if _t_auto > 1.5:
		_rend.append([dt_real, Performance.get_monitor(Performance.TIME_PROCESS), Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
					  Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
					  RenderingServer.viewport_get_measured_render_time_cpu(vp) / 1000.0, RenderingServer.viewport_get_measured_render_time_gpu(vp) / 1000.0])
	if _args.has("traza") and av["estado"] == "volando" and fmod(av["t"], 0.5) < DT * 30 and av["t"] - float(_args.get("_tt", "-1")) > 0.3:
		_args["_tt"] = str(av["t"]); var e := Cuat.euler(av["q"])
		print("  t %.1f  agl %.1f  V %.1f  alabeo %.0f  cabeceo %.0f  rumbo %.0f  gases %.2f  de %.1f  da %.1f  dr %.1f" % [av["t"], av["agl"], av["V"], e[0] / D2R, e[1] / D2R, e[2] / D2R, av["gases"], av["de"] / D2R, av["da"] / D2R, av["dr"] / D2R])
	if _args.has("terminar") and av.get("estado") == "volando" and av["t"] >= float(_args["terminar"]): terminar_vuelo("abandonado")
	if _args.has("repeticion") and pantalla_actual == "pResultado": _args.erase("repeticion"); ver_repeticion()
	if _args.has("pausa") and not pausado and av.get("t", 0.0) >= float(_args["pausa"]): poner_pausa(true); _args.erase("pausa")
	if _args.has("ayuda") and av.get("t", 0.0) >= float(_args["ayuda"]): hud.ayuda.visible = true; _args.erase("ayuda")
	if av.get("estado") == "en mano" and pantalla_actual == "":
		av["gases"] = float(_args.get("gases", "1")); camara = int(_args.get("camara", "3" if es_dron() else "1"))
		if _t_auto > 0.3:
			if es_fpv(): av["gases"] = 0.0; fpv_armar()
			elif es_dron(): dji_despegar()
			else: lanzar()
	if _t_auto >= float(_args.get("esperar", "6")):
		var med := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
		for x in _rend:
			for i in 6: med[i] += x[i] / maxf(1, _rend.size())
		print("AUTO: %d cuadros, %.1f ms por cuadro (%.0f fps), proceso %.1f ms, render CPU %.1f ms GPU %.1f ms, %d llamadas de dibujo, %.1f M primitivas; estado %s, altura %.1f m, t %.1f s" % [
			_rend.size(), med[0] * 1000, 1.0 / maxf(med[0], 1e-6), med[1] * 1000, med[4] * 1000, med[5] * 1000, med[2], med[3] / 1e6,
			av["estado"], -av["p"][2] - ent.altura(av["p"][0], av["p"][1]), av["t"]])
		var uf := 0.0; var ut := 0.0
		for x in _us: uf += x[0] / maxf(1, _us.size()); ut += x[1] / maxf(1, _us.size())
		print("AUTO: principal._process %.2f ms por cuadro (fisica y mandos %.2f ms, camara y HUD %.2f ms)" % [ut / 1000, uf / 1000, (ut - uf) / 1000])
		if _args.has("captura"):
			var img := get_viewport().get_texture().get_image(); img.save_png(_args["captura"])
			print("Captura en " + _args["captura"])
		get_tree().quit()
