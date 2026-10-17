class_name AppMandos
extends RefCounted
## Teclado y mando (mando de consola o emisora por USB).
## Parte de principal.gd (como js/app/mandos.js de la web): el estado esta en principal.gd (p).

var p: Principal

func _init(principal: Principal) -> void: p = principal

static func _zona_muerta(x: float, z: float) -> float: return 0.0 if absf(x) < z else signf(x) * (absf(x) - z) / (1 - z)

static func _expo(x: float, e: float) -> float: return (1 - e) * x + e * x * x * x

func _leer_mando(dt: float) -> bool:
	if p.vr != null: return p.vr.leer_mandos(dt)       # gafas de VR: sus mandos son la emisora
	var M := p.mando_cfg; var dev := MandoCfg.conectado()
	if dev < 0: return false
	var rx := _zona_muerta(M.eje(dev, "rx"), M.zona); var ry := _zona_muerta(M.eje(dev, "ry"), M.zona)
	var ly := _zona_muerta(M.eje(dev, "ly"), M.zona); var lx := _zona_muerta(M.eje(dev, "lx"), M.zona)
	p._mando_torreta = []
	if p.es_uav() and p.app_camaras.torreta_con_flechas(): p._mando_torreta = [rx, ry]; rx = 0.0; ry = 0.0      # UAV con el automatico navegando: la palanca derecha mueve la torreta
	var cuad := p.modelo != null and ((p.es_dron() and not p.es_fpv()) or p.es_bipode()); var fpv := p.modelo != null and p.es_fpv()   # el FPV lleva el gas como un avion; el bipode, la izquierda como el dron
	var bip := p.modelo != null and p.es_bipode()
	p._mando_disparo = false; p._mando_puno = false
	var pulsado := func(b: int) -> bool:
		var ahora := Input.is_joy_button_pressed(dev, b); var antes: bool = p._botones_antes.get(b, false); p._botones_antes[b] = ahora
		return ahora and not antes
	var b_start: bool = pulsado.call(JOY_BUTTON_START)
	var bs := {}
	for b in [JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_X, JOY_BUTTON_Y, JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER, JOY_BUTTON_BACK, JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_RIGHT, JOY_BUTTON_DPAD_LEFT]:
		bs[b] = pulsado.call(b)
	if p.pantalla_actual == "" and b_start: p.app_repeticion.poner_pausa(not p.pausado)
	M.gimbal = 0.0
	if p.pantalla_actual == "" and not p.pausado and bip:     # bipode: A arrancar / aparcar, RB camara, Back reiniciar; gatillos: disparar (RT) y puño (LT)
		if bs[JOY_BUTTON_A]: p.app_vuelo.lanzar()
		if bs[JOY_BUTTON_RIGHT_SHOULDER]: p.camara = p.camara % 3 + 1
		if bs[JOY_BUTTON_BACK]: p.app_vuelo.reiniciar()
		p._mando_disparo = Input.get_joy_axis(dev, JOY_AXIS_TRIGGER_RIGHT) > 0.4; p._mando_puno = Input.get_joy_axis(dev, JOY_AXIS_TRIGGER_LEFT) > 0.4
	elif p.pantalla_actual == "" and not p.pausado and fpv:     # dron FPV: A armar/desarmar, LB modo, RB camara, Back reiniciar
		if bs[JOY_BUTTON_A]: p.app_apps_dron.fpv_armar()
		if bs[JOY_BUTTON_LEFT_SHOULDER]: p.app_apps_dron.fpv_modo()
		if bs[JOY_BUTTON_RIGHT_SHOULDER]: p.camara = p.camara % 3 + 1
		if bs[JOY_BUTTON_BACK]: p.app_vuelo.reiniciar()
	elif p.pantalla_actual == "" and not p.pausado and cuad:    # mando del dron comercial: A despegar/aterrizar, B casa, X video, Y foto, LB modo, RB camara, Back reiniciar
		if bs[JOY_BUTTON_A]: p.app_apps_dron.dji_despegar()
		if bs[JOY_BUTTON_B]: p.app_apps_dron.dji_rth()
		if bs[JOY_BUTTON_X]: p.app_apps_dron.dji_video()
		if bs[JOY_BUTTON_Y]: p.app_apps_dron.dji_foto()
		if bs[JOY_BUTTON_LEFT_SHOULDER]: p.app_apps_dron.dji_modo()
		if bs[JOY_BUTTON_RIGHT_SHOULDER]: p.camara = p.camara % 3 + 1
		if bs[JOY_BUTTON_BACK]: p.app_vuelo.reiniciar()
		if bs[JOY_BUTTON_DPAD_UP]: p.app_apps_dron.dji_zoom(1)                 # cruceta: arriba y abajo el zoom, a la derecha la termica
		if bs[JOY_BUTTON_DPAD_DOWN]: p.app_apps_dron.dji_zoom(-1)
		if bs[JOY_BUTTON_DPAD_RIGHT]: p.app_apps_dron.dji_termica()
		if M.perfil == "consola": M.gimbal = Input.get_joy_axis(dev, JOY_AXIS_TRIGGER_RIGHT) - Input.get_joy_axis(dev, JOY_AXIS_TRIGGER_LEFT)   # gatillos: rueda del gimbal
		# CSC (combinacion de palancas de los drones comerciales): las dos abajo y hacia dentro (o hacia fuera) medio segundo arranca los motores
		var csc := ly > 0.8 and ry > 0.8 and ((lx > 0.6 and rx < -0.6) or (lx < -0.6 and rx > 0.6))
		p._t_csc = p._t_csc + dt if csc else 0.0
		if p._t_csc > 0.5 and p.av.get("estado", "") == "en mano": p._t_csc = -1e9; p.app_vuelo.lanzar(); p.poner_toast("Motores en marcha (CSC): sube la palanca izquierda para despegar")
	elif p.pantalla_actual == "" and not p.pausado:
		if bs[JOY_BUTTON_A]: p.app_vuelo.lanzar()
		if p.es_uav():                       # UAV: LB modo, Y base, cruceta izquierda: despegue o aterrizaje automatico
			if bs[JOY_BUTTON_LEFT_SHOULDER]: uav_modo()
			if bs[JOY_BUTTON_Y]: uav_poner("BASE")
			if bs[JOY_BUTTON_DPAD_LEFT]: uav_poner("DESPEGUE" if p.av.get("enTierra", false) else "ATERRIZAJE")
			if bs[JOY_BUTTON_DPAD_UP]: p.app_apps_dron.dji_zoom(1)              # cruceta arriba y abajo zoom, derecha termica; X foto; gatillos: torreta arriba y abajo
			if bs[JOY_BUTTON_DPAD_DOWN]: p.app_apps_dron.dji_zoom(-1)
			if bs[JOY_BUTTON_DPAD_RIGHT]: p.app_apps_dron.dji_termica()
			if bs[JOY_BUTTON_X]: p.app_camaras.uav_foto()
			M.gimbal = Input.get_joy_axis(dev, JOY_AXIS_TRIGGER_RIGHT) - Input.get_joy_axis(dev, JOY_AXIS_TRIGGER_LEFT)
		if p.con_tren():                     # avion de pista: B frena
			p._mando_freno = Input.is_joy_button_pressed(dev, JOY_BUTTON_B)
			if bs[JOY_BUTTON_B]: quitar_freno_aparc()
		elif bs[JOY_BUTTON_B]: p.av["gases"] = 0.0
		if bs[JOY_BUTTON_RIGHT_SHOULDER]: p.camara = p.camara % 3 + 1     # el mismo boton que en el dron, el FPV y el bipode
		if bs[JOY_BUTTON_X] and not p.es_uav(): p.app_vuelo.reiniciar()
		if bs[JOY_BUTTON_DPAD_UP] and not p.es_uav(): p.mando["trim"] = minf(6, p.mando["trim"] + 0.25)
		if bs[JOY_BUTTON_DPAD_DOWN] and not p.es_uav(): p.mando["trim"] = maxf(-6, p.mando["trim"] - 0.25)
	if p.pausado: return false
	# palanca derecha: hacia ti = tirar = morro arriba; a la derecha = alabeo/timon a la derecha
	var moviendo := rx != 0 or ry != 0 or lx != 0 or (cuad and ly != 0)
	if moviendo or p._mando_usado:
		p.mando["pitch"] = _expo(ry, M.expo); p.mando["yaw"] = _expo(rx, M.expo)
		p.mando["pitchObj"] = p.mando["pitch"]; p.mando["yawObj"] = p.mando["yaw"]
		p.mando["guinada"] = _expo(lx, M.expo); p.mando["guinadaObj"] = p.mando["guinada"]   # izquierda de lado: guinada del dron o timon de 4 canales
		if cuad: p.mando["vz"] = -ly; p.mando["vzObj"] = p.mando["vz"]
	if moviendo: p._mando_usado = true
	# palanca izquierda: gas (eje Y negativo = arriba)
	if not p.av["motorRoto"] and fpv and M.perfil == "consola":     # FPV con mando de consola (palanca con muelle): gas_fpv_consola
		if ly != 0: p._gas_fpv_mando = true                          # desde que se toca la palanca del gas en este vuelo
		if p._gas_fpv_mando: p.av["gases"] = p.app_apps_dron.gas_fpv_consola(-ly)
	elif not p.av["motorRoto"] and not cuad:
		if M.gas == "absoluto":
			if p._mando_usado or ly != 0: p.av["gases"] = clampf((1 - M.eje(dev, "ly")) / 2, 0, 1)
		elif ly != 0: p.av["gases"] = clampf(p.av["gases"] - ly * 0.7 * dt, 0, 1)
	return moviendo or p._mando_usado

## Latitud y longitud (grados y minutos decimales, como las de un GPS) de un punto N, E del mapa.
func coord_txt(N: float, E: float) -> String:
	var O: Dictionary = p.mundo_datos["origen"]; var lat: float = O["lat"] + N / 110574.0; var lon: float = O["lon"] + E / (111320.0 * cos(float(O["lat"]) * p.D2R))
	var gm := func(x: float, pos: String, neg: String) -> String: return "%d°%s' %s" % [int(floor(absf(x))), ("%.3f" % (fmod(absf(x), 1.0) * 60)).pad_zeros(2), pos if x >= 0 else neg]
	return "%s %s" % [gm.call(lat, "N", "S"), gm.call(lon, "E", "W")]

## UAV: pone un modo del piloto automatico (con su aviso, o por que no se puede).
func uav_poner(m: String, punto = null) -> void:
	if p.piloto == null or p.av.is_empty() or p.av["estado"] != "volando" or p.rep_activa:
		if p.piloto != null and not p.av.is_empty() and p.av["estado"] == "en mano": p.poner_toast("Primero arranca el motor (L)")
		return
	var t := p.piloto.poner(m, p.av, punto)
	if t != "":
		p._piloto_visto = p.piloto.modo; p.poner_toast("Piloto automático: " + t)
		if m == "DESPEGUE": p.hud.aviso.text = ""
		return
	if m == "DESPEGUE": p.poner_toast("El despegue automático se pide parado en la pista")
	elif m == "ATERRIZAJE": p.poner_toast("En tierra no hay aterrizaje automático" if p.piloto.pista != null else "Sin pista no hay aterrizaje automático")
	else: p.poner_toast("En tierra: manual o despegue automático (P)")

## UAV: M pasa de manual a estabilizado, a crucero y otra vez a manual.
func uav_modo() -> void:
	if p.piloto == null: return
	var ciclo := ["MANUAL", "ESTAB", "CRUCERO"]; var i := ciclo.find(p.piloto.modo)
	uav_poner("MANUAL" if i < 0 else ciclo[(i + 1) % 3])

func quitar_freno_aparc() -> void:
	if not p.av.is_empty() and p.av.get("frenoAparc", false): p.av["frenoAparc"] = false; p.hud.aviso.text = ""; p.poner_toast("Freno de aparcamiento quitado: espacio (o B) frena")

func _leer_teclado(dt: float) -> void:
	if p.con_tren() and not p.av.is_empty(): p.av["freno"] = 1.0 if (p.av.get("frenoAparc", false) or Input.is_physical_key_pressed(KEY_SPACE) or p._mando_freno) else 0.0
	var tor := p.es_uav() and p.app_camaras.torreta_con_flechas()      # UAV: con el automatico navegando (o con Mayusculas) las flechas mueven la torreta
	var cuad := (p.es_dron() and not p.es_fpv()) or p.es_bipode(); var T := func(k: int) -> bool: return Input.is_physical_key_pressed(k) and not (tor and k in [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT])   # en el FPV W/S son el gas; el bipode anda con W/S y A/D
	if p.es_bipode(): p.mando["disparo"] = T.call(KEY_SPACE) or p._mando_disparo; p.mando["puno"] = T.call(KEY_F) or p._mando_puno
	var tecla_palanca: bool = T.call(KEY_DOWN) or T.call(KEY_UP) or T.call(KEY_RIGHT) or T.call(KEY_LEFT) or T.call(KEY_A) or T.call(KEY_D) or ((cuad or p.es_fpv()) and (T.call(KEY_W) or T.call(KEY_S)))   # en el FPV, W/S tambien devuelven el gas al teclado
	if tecla_palanca: p._mando_usado = false            # si se tocan las flechas, vuelve a mandar el teclado
	if p.es_fpv() and (T.call(KEY_W) or T.call(KEY_S)): p._gas_fpv_mando = false      # W/S: el gas vuelve al teclado
	var gimbal_teclas := ((1.0 if T.call(KEY_E) else 0.0) - (1.0 if T.call(KEY_Q) else 0.0)) if cuad and not p.es_bipode() else 0.0
	if _leer_mando(dt) and not tecla_palanca:
		p.mando["gimbal"] = gimbal_teclas if gimbal_teclas != 0 else p.mando_cfg.gimbal; _leer_gas_teclado(dt); return
	p.mando["gimbal"] = gimbal_teclas if gimbal_teclas != 0 else p.mando_cfg.gimbal
	p.mando["pitchObj"] = (1.0 if T.call(KEY_DOWN) else 0.0) - (1.0 if T.call(KEY_UP) else 0.0)     # +1 = tirar
	p.mando["yawObj"] = (1.0 if T.call(KEY_RIGHT) else 0.0) - (1.0 if T.call(KEY_LEFT) else 0.0)
	p.mando["guinadaObj"] = (1.0 if T.call(KEY_D) else 0.0) - (1.0 if T.call(KEY_A) else 0.0)
	p.mando["vzObj"] = (1.0 if T.call(KEY_W) else 0.0) - (1.0 if T.call(KEY_S) else 0.0)
	for k in ["pitch", "yaw", "guinada", "vz"]:      # la palanca va al tope a 5/s y vuelve al centro a 8/s
		var obj: float = p.mando[k + "Obj"]; var vel := 8.0 if obj == 0 else 5.0; var d: float = obj - p.mando[k]
		p.mando[k] += signf(d) * minf(absf(d), vel * dt)
	_leer_gas_teclado(dt)

func _leer_gas_teclado(dt: float) -> void:
	if p.av["motorRoto"] or (p.es_dron() and not p.es_fpv()) or p.es_bipode(): return          # en el dron comercial W/S son velocidad vertical; en el bipode, andar
	var k := 0.4 if p.es_fpv() else 0.8                # FPV: mas despacio (se sostiene con un 30 % de gas)
	if Input.is_physical_key_pressed(KEY_W): p.av["gases"] = minf(1, p.av["gases"] + k * dt)
	if Input.is_physical_key_pressed(KEY_S): p.av["gases"] = maxf(0, p.av["gases"] - k * dt)
