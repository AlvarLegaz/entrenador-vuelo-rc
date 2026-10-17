class_name AppRepeticion
extends RefCounted
## Repeticion del vuelo grabado y pausa.
## Parte de principal.gd (como js/app/repeticion.js de la web): el estado esta en principal.gd (p).

var p: Principal

func _init(principal: Principal) -> void: p = principal

func ver_repeticion() -> void:
	var v = p.ultimo_vuelo
	if v == null or (v["filas"] as Array).size() < 2: return
	p.REP = { "activa": true, "filas": v["filas"], "t": 0.0, "dur": float(v["filas"][-1][0]), "pausa": false, "i": 0, "vuelo": v }; p.rep_activa = true
	p.av = p.modelo.estado_inicial(); p.av["estado"] = "repetición"; p.app_evaluacion.colocar_en_base(p.av)
	p.hud.rep.visible = true; p.mostrar(""); p.hud.obj_rt.text = ""; p.hud.aviso.text = ""

func _paso_repeticion(dt: float) -> void:
	var f: Array = p.REP["filas"]
	if not p.REP["pausa"]: p.REP["t"] = minf(p.REP["dur"], p.REP["t"] + dt)
	var i: int = p.REP["i"]
	while i < f.size() - 2 and f[i + 1][0] <= p.REP["t"]: i += 1
	while i > 0 and f[i][0] > p.REP["t"]: i -= 1
	p.REP["i"] = i
	var a: Array = f[i]; var b: Array = f[mini(f.size() - 1, i + 1)]
	var u: float = clampf((p.REP["t"] - a[0]) / (b[0] - a[0]), 0, 1) if b[0] > a[0] else 0.0
	var L := func(j: int) -> float: return a[j] + (b[j] - a[j]) * u
	var ang := func(j: int) -> float:
		var d: float = b[j] - a[j]
		if d > 180: d -= 360
		if d < -180: d += 360
		return a[j] + d * u
	p.av["p"] = [L.call(1), L.call(2), -L.call(3)]; p.av["q"] = Cuat.desde_euler(ang.call(7) * p.D2R, ang.call(8) * p.D2R, ang.call(9) * p.D2R)
	p.av["V"] = L.call(4); p.av["alfa"] = L.call(10); p.av["g_carga"] = L.call(12); p.av["gases"] = L.call(13) / 100; p.av["rpm"] = L.call(14); p.av["Wh"] = L.call(16)
	p.av["perdida"] = L.call(26); p.av["t"] = p.REP["t"]; p.av["de"] = L.call(21) * p.D2R; p.av["dr"] = L.call(22) * p.D2R; p.av["da"] = L.call(23) * p.D2R; p.av["v"] = [p.av["V"], 0.0, 0.0]
	p.mando["pitch"] = L.call(18); p.mando["yaw"] = L.call(19)
	p.hud.rep_l.text = "[b]REPETICIÓN[/b] · %.1f s de %.1f%s · espacio: pausa · ← →: 5 s · 1/2/3: cámara · Esc: salir" % [p.REP["t"], p.REP["dur"], " · pausa" if p.REP["pausa"] else ""]
	p.hud.rep_barra.size.x = p.hud.rep_fondo.size.x * p.REP["t"] / maxf(0.1, p.REP["dur"])
	if p.REP["t"] >= p.REP["dur"]: p.REP["pausa"] = true

func _salir_repeticion() -> void:
	p.REP["activa"] = false; p.rep_activa = false; p.hud.rep.visible = false; p.app_resultado.mostrar_resultado(p.REP["vuelo"])

func _nombre_camara(n: int) -> String: return ["", "piloto", "persecución", "FPV (gafas)" if (p.modelo != null and p.es_fpv()) else ("del dron" if (p.modelo != null and p.es_dron()) else ("puesto de tiro" if (p.modelo != null and p.es_bipode()) else "a bordo"))][n]

func _texto_instr() -> String: return ("OSD: " if p.es_fpv() else ("Pantalla de la app: " if p.es_dron() else "Instrumentos: ")) + ("no" if p.sin_instrumentos else "sí")

func poner_pausa(si: bool) -> void:
	if si == p.pausado: return
	p.pausado = si; p.pausa["raiz"].visible = si
	if si:
		p.pausa["camara"].text = "Cámara: " + _nombre_camara(p.camara)
		p.pausa["instr"].text = _texto_instr()
		p.pausa["sonido"].set_pressed_no_signal(p.sonido.on)
		p.pausa["info"].text = "%s · %s" % [DatosComunes.avion(p.sesion["avion"]).get("nombre", ""), Escenarios.datos()[p.sesion["escenario"]]["nombre"]]
		p.sonido.silenciar(true)
	else:
		p.sonido.silenciar(not p.sonido.on or p.pantalla_actual != ""); p.hud.ayuda.visible = false; p.get_viewport().gui_release_focus()

func cambiar_camara_pausa() -> void:
	p.camara = p.camara % 3 + 1; p.pausa["camara"].text = "Cámara: " + _nombre_camara(p.camara)

func cambiar_instrumentos_pausa() -> void:
	p.sin_instrumentos = not p.sin_instrumentos
	p.pausa["instr"].text = _texto_instr()

func terminar_desde_pausa() -> void:
	poner_pausa(false)
	if p.av["estado"] == "volando": p.app_vuelo.terminar_vuelo("abandonado")
	elif p.vuelo != null and p.vuelo["final"] != "": p.app_resultado.mostrar_resultado(p.vuelo)
	else: p.app_pantallas.ir_inicio()

## Sale al menu principal: si habia un vuelo en marcha se guarda (si hay piloto) sin pasar por el resultado.
func salir_al_menu() -> void:
	poner_pausa(false)
	if not p.av.is_empty() and p.av["estado"] == "volando" and p.vuelo != null: p.salir_tras = true; p.app_vuelo.terminar_vuelo("abandonado")
	else: p.app_pantallas.ir_inicio()
