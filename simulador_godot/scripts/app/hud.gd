class_name AppHud
extends RefCounted
## Camaras de vuelo, termica, HUD y el vuelo automatico de las pruebas.
## Parte de principal.gd (como js/app/hud.js de la web): el estado esta en principal.gd (p).

var p: Principal

func _init(principal: Principal) -> void: p = principal

func _leer_mando_en_menu() -> void:       # en las pantallas solo se mira el Start (como en la web, que no hace nada)
	pass

func lectura_vs() -> float: return p._vs

func _camara() -> void:
	var t := Avion3D.ned(p.av["p"])
	if p._args.has("cenital"):          # pruebas: vista vertical del punto de lanzamiento desde la altura dada
		p.cam.fov = 60; p.cam.global_position = p.vista.base + Vector3(0, float(p._args["cenital"]), 0); p.cam.look_at(p.vista.base, Vector3.FORWARD); return
	if p.es_uav() and p.camara == 3 and p.avion3d.cam_fija != null:      # morro fijo: la camara sujeta al avion, al frente o de lado
		var tf: Dictionary = p.av["torreta"]; var qf: Array = p.av["q"]; var ct := cos(float(tf["tilt"])); var st := sin(float(tf["tilt"])); var cp := cos(float(tf["pan"])); var sp := sin(float(tf["pan"]))
		var fwf := Avion3D.ned(Cuat.rot(qf, [ct * cp, ct * sp, -st])); var upf := Avion3D.ned(Cuat.rot(qf, [-st * cp, -st * sp, -ct]))
		var posf := t + Avion3D.ned(Cuat.rot(qf, p.avion3d.cam_fija["pos"])) + 0.03 * fwf; var zf: float = p.app_apps_dron.cam_dji()["zoom"]
		p.cam.fov = rad_to_deg(2 * atan(tan(29 * p.D2R) / zf)) if zf > 1 else 58.0; p.cam.global_position = posf; p.cam.look_at(posf + fwf, upf)
		return
	if p.es_uav() and p.camara != 2 and p.avion3d.torreta != null:
		if p.camara == 1:              # camara de vuelo: fija en el morro, algo inclinada hacia abajo
			var q: Array = p.av["q"]; var ti := -4 * p.D2R
			var pos := t + Avion3D.ned(Cuat.rot(q, [1.1, 0.0, 0.05])); var fw := Avion3D.ned(Cuat.rot(q, [cos(ti), 0.0, -sin(ti)])); var up := Avion3D.ned(Cuat.rot(q, [-sin(ti), 0.0, -cos(ti)]))
			p.cam.fov = 55; p.cam.global_position = pos; p.cam.look_at(pos + fw, up)
		else:                        # la torreta EO/IR, estabilizada, con su giro e inclinacion; con zoom, el campo se cierra
			var tr: Dictionary = p.av["torreta"]; var yaw: float = Cuat.euler(p.av["q"])[2] + tr["pan"]; var g: float = tr["tilt"]
			var fw := Avion3D.ned([cos(yaw) * cos(g), sin(yaw) * cos(g), -sin(g)])
			var pos := t + Avion3D.ned(Cuat.rot(p.av["q"], p.modelo.datos["malla"]["torreta"]["centro"])) + 0.22 * fw     # en la ventana, fuera de la bola (15 cm de radio)
			var zc: float = p.app_apps_dron.cam_dji()["zoom"]
			p.cam.fov = rad_to_deg(2 * atan(tan(29 * p.D2R) / zc)) if zc > 1 else 58.0; p.cam.global_position = pos
			p.cam.look_at(pos + fw, Vector3.UP if absf(g) < 89.5 * p.D2R else Avion3D.ned([cos(yaw), sin(yaw), 0.0]))
		return
	if p.camara == 1:
		# vista del piloto con ZOOM AUTOMATICO, como en el navegador: la envergadura ocupa la fraccion zoom_piloto del alto
		# de la pantalla (10 % por defecto; 0 = sin zoom, como lo ve el ojo), entre 50 y 1,5 grados. Suavizado
		var b: Vector3 = p.vista.base + Vector3(1.5, 1.7, 2)
		var env: float = float(p.modelo.b_m); var zp: float = p.aj.get("zoom_piloto", 0.03)
		var d: float = b.distance_to(t); var obj: float = clampf(rad_to_deg(env / (zp * maxf(d, 0.5))), 1.5, 50.0) if zp > 0 else 50.0
		p._fov1 = obj if p._fov1 < 0 else p._fov1 + (obj - p._fov1) * 0.08
		p.cam.fov = p._fov1; p.cam.global_position = b
		if d > 0.1: p.cam.look_at(t, Vector3.UP)
	elif p.avion3d.bipode and p.avion3d.bipode.camara(p.cam, p.av, p.camara): pass      # bipode: sus camaras 2 y 3
	elif p.camara == 2:
		# a escala del vehiculo: el dron de 25 cm se ve tan grande como el avion de 1,2 m (que sigue a 5 m y 1,5 m de altura)
		var yaw: float = Cuat.euler(p.av["q"])[2]; var dc: float = float(p.modelo.b_m) * (5.0 / 1.2); var hc: float = float(p.modelo.b_m) * (1.5 / 1.2)
		p.cam.fov = 60; p.cam.global_position = t + Avion3D.ned([-cos(yaw) * dc, -sin(yaw) * dc, -hc]); p.cam.look_at(t, Vector3.UP)
	elif p.es_fpv():
		# camara FPV: fija al bastidor, inclinada hacia arriba (uptilt) y gran angular (campo de vision HORIZONTAL fijo)
		var F: Dictionary = p.modelo.fc; var ti: float = F["camara_inclinacion_grados"] * p.D2R; var q: Array = p.av["q"]
		var pos := t + Avion3D.ned(Cuat.rot(q, F["camara_pos"])); var fw := Avion3D.ned(Cuat.rot(q, [cos(ti), 0.0, -sin(ti)])); var up := Avion3D.ned(Cuat.rot(q, [-sin(ti), 0.0, -cos(ti)]))
		var asp: float = p.get_viewport().get_visible_rect().size.aspect()
		p.cam.fov = rad_to_deg(2 * atan(tan(deg_to_rad(F["camara_fov_h_grados"]) / 2) / asp)); p.cam.global_position = pos; p.cam.look_at(pos + fw, up)
	elif p.es_dron():
		# camara del dron en su gimbal: nivelada, con el rumbo del dron y la inclinacion de la rueda (av.gimbal)
		var yaw: float = Cuat.euler(p.av["q"])[2]; var g: float = p.av.get("gimbal", -10.0) * p.D2R
		var pos := t + Avion3D.ned(Cuat.rot(p.av["q"], [0.1, 0.0, -0.1]))
		var fw := Avion3D.ned([cos(yaw) * cos(g), sin(yaw) * cos(g), -sin(g)])
		var zc: float = p.app_apps_dron.cam_dji()["zoom"]
		p.cam.fov = rad_to_deg(2 * atan(tan(29 * p.D2R) / zc)) if zc > 1 else 58.0; p.cam.global_position = pos     # con zoom, el campo se cierra
		p.cam.look_at(pos + fw, Vector3.UP if absf(g) < 89.5 * p.D2R else Avion3D.ned([cos(yaw), sin(yaw), 0.0]))
	else:
		var q: Array = p.av["q"]
		var pos := t + Avion3D.ned(Cuat.rot(q, [0.3, 0.0, -0.1])); var fw := Avion3D.ned(Cuat.rot(q, [1.0, 0.0, 0.0])); var up := Avion3D.ned(Cuat.rot(q, [0.0, 0.0, -1.0]))
		p.cam.fov = 80; p.cam.global_position = pos; p.cam.look_at(pos + fw, up)

func _termica(activa: bool) -> void:
	if p.cam.get_cull_mask_value(2) != activa: p.cam.set_cull_mask_value(2, activa)
	if not activa:
		if p._ter != null and p._ter.visible: p._ter.visible = false; p.cam.environment = null
		return
	if p._ter == null:
		var q := QuadMesh.new(); q.size = Vector2(2, 2)
		var sm := ShaderMaterial.new(); sm.shader = Shader.new(); sm.shader.code = p.SOMBREADOR_TERMICA; sm.render_priority = 127
		p._ter = MeshInstance3D.new(); p._ter.mesh = q; p._ter.material_override = sm; p._ter.extra_cull_margin = 16384.0; p._ter.layers = 2
		p._ter.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; p.cam.add_child(p._ter)
	var fuente: Environment = p.cam.get_world_3d().environment if p.cam.get_world_3d() != null else null
	if fuente != p._ter_de or p._ter_env == null:
		p._ter_de = fuente; p._ter_env = fuente.duplicate() if fuente != null else Environment.new()
		p._ter_env.tonemap_mode = Environment.TONE_MAPPER_LINEAR; p._ter_env.tonemap_exposure = 1.0; p._ter_env.tonemap_white = 1.0
		p._ter_env.glow_enabled = false; p._ter_env.adjustment_enabled = false; p._ter_env.ssao_enabled = false; p._ter_env.ssil_enabled = false
	p.cam.environment = p._ter_env; p._ter.visible = true
	var tam := p.get_viewport().get_visible_rect().size
	(p._ter.material_override as ShaderMaterial).set_shader_parameter("res", Vector2(640, maxf(2, round(640 * tam.y / maxf(1, tam.x)))))

func _pintar_objetivos() -> void:
	var E: Dictionary = Escenarios.datos()[p.sesion["escenario"]]
	var t := "[font_size=14][b][color=#ffc83d]%s[/color][/b][/font_size]\n" % E["nombre"]     # #objetivos h3: acento, 14 px
	if E.has("mundo") and p.ev.op != null:       # operacion: lo que toca ahora y la orden de trabajo
		t += p.app_vuelo.texto_fpv(p.ev.op.ahora(p.ev.obj, p.av), true) + "\n" + p.ev.lineas_objetivos()
		if p.sesion["alumno"] != null: t += "[font_size=12][color=#aaaaaa]%s[/color][/font_size]" % p.sesion["alumno"]["nombre"]
	elif E.has("mundo"):
		var suelo := p.ent.altura(p.av["p"][0], p.av["p"][1])
		t += "Terreno a %d m sobre el mar · casa a [b]%d m[/b]" % [int(round(suelo + p.ent.terreno["h0"])), int(round(Vector2(p.av["p"][0] - p.casa["N"], p.av["p"][1] - p.casa["E"]).length()))]
	elif (E["objetivos"] as Array).is_empty(): t += p.ev.texto_orden() + p.ev.texto_vueltas(p.sesion["escenario"])
	else:
		if p.ev.obj.has("circ1"): t += p.ev.texto_orden()
		if p.ev.obj.has("ocho1"): t += p.ev.texto_ocho()
		if p.ev.zona == 2 and p.ev.fpv == null: t += p.ev.texto_zona2(p.sesion["escenario"])
		if p.ev.fpv != null: t += p.app_vuelo.texto_fpv(p.ev.fpv.ahora(p.ev.obj, p.av), true) + "\n"
		t += p.ev.lineas_objetivos()
		if p.sesion["alumno"] != null: t += "[font_size=12][color=#aaaaaa]%s[/color][/font_size]" % p.sesion["alumno"]["nombre"]
	var ts := t.strip_edges()
	if p.hud.obj_rt.text != ts: p.hud.obj_rt.text = ts          # el BBCode solo se vuelve a interpretar si cambia
	p.hud.guia.visible = p.ev.guia_bb != "" and not p.ev.guia.is_empty() and p.av["estado"] == "volando"
	if p.hud.guia_rt.text != p.ev.guia_bb: p.hud.guia_rt.text = p.ev.guia_bb

func _hud() -> void:
	p.hud_carrera.pintar()
	var e := Cuat.euler(p.av["q"]); var roll: float = e[0] * p.R2D; var pitch: float = e[1] * p.R2D; var yaw: float = e[2] * p.R2D
	var h := maxf(0, -p.av["p"][2]); var dist := Vector2(p.av["p"][0] - p.casa["N"], p.av["p"][1] - p.casa["E"]).length()
	var vn := Cuat.rot(p.av["q"], p.av["v"]); var vs: float = -vn[2]; p._vs = vs
	var vto: Dictionary = p.ent.viento; var suelo := p.ent.altura(p.av["p"][0], p.av["p"][1]); var dron := p.es_dron()
	var est := "REPETICIÓN" if p.rep_activa else ("EN EL SUELO" if (p.av["estado"] == "en mano" and dron) else ("MOTOR PARADO" if (p.av["estado"] == "en mano" and p.con_tren()) else String(p.av["estado"]).to_upper()))
	var partes := [["%s · %d s" % [est, int(p.av["t"])], false]]
	if p.vuelo != null and p.av["estado"] == "volando": partes.append(["● REC", true])
	if p.av["motorRoto"]: partes.append(["MOTOR PARADO", true])
	if p.modelo.facil: partes.append(["física fácil", false])
	if p.pausado: partes.append(["PAUSA", false])
	p.hud.pintar_estado(partes)
	if dron and p.av["estado"] == "volando" and not p.av.get("posado", false) and p.hud.aviso.text.begins_with("Sube el gas"): p.hud.aviso.text = ""
	if p.es_bipode(): _hud_bip(dist, yaw); return
	var bat: float = p.modelo.bateria_pct(p.av)
	var v_clase := "rojo" if (p.vel_perdida > 0 and p.av["V"] < 1.1 * p.vel_perdida) else ("ambar" if (p.vel_perdida > 0 and p.av["V"] < 1.3 * p.vel_perdida) else "")
	var lect := []
	if not ((p.av["estado"] == "en mano" and p.vuelo == null) or p.sin_instrumentos):
		lect = [["%.1f" % p.av["V"], "vel. aire m/s", v_clase], ["%d" % int(round(-p.av["p"][2] - suelo)), "altura m", ""], ["%s%.1f" % ["+" if vs >= 0 else "", vs], "asc. m/s", ""],
				["%03d°" % int(round(fposmod(yaw + 360, 360))), "rumbo", ""], ["%d" % int(round(dist)), "dist. m", ""], ["%d%%" % int(round(bat)), "combustible" if p.modelo.propulsion.get("combustible", false) else "batería", "rojo" if bat < 20 else ""]]
		if p.av["perdida"] > 0.5 and not p.av.get("enTierra", false): lect.append(["¡PÉRDIDA!", "alfa %d°" % int(round(p.av["alfa"])), "rojo"])
	p.hud.pintar_lecturas(lect)
	p.hud.hud_texto.visible = p.mostrar_hud and not dron
	if p.hud.hud_texto.visible:
		p.hud.hud_rt.text = ("vel. aire [b]%.1f[/b] m/s · suelo %.1f m/s · asc. %s%.1f m/s\n" % [p.av["V"], Vector2(vn[0], vn[1]).length(), "+" if vs >= 0 else "", vs]) + \
			("altura [b]%.1f[/b] m%s · distancia %d m\n" % [h, (" (sobre el terreno %d m)" % int(round(h - suelo))) if p.en_mundo() else "", int(round(dist))]) + \
			("alabeo %d° · cabeceo %d° · rumbo %d°\n" % [int(round(roll)), int(round(pitch)), int(round(fposmod(yaw + 360, 360)))]) + \
			("alfa %.1f° %s · carga %.1f g\n" % [p.av["alfa"], "[b]¡PÉRDIDA![/b]" if p.av["perdida"] > 0.5 else "", p.av["g_carga"]]) + \
			("gases [b]%d %%[/b] · batería %d %%\n" % [int(round(p.av["gases"] * 100)), int(round(bat))]) + \
			("viento %d m/s%s · compensador %.2f° · cámara %d" % [int(round(vto["base"])), " con rachas" if vto["rachas"] else "", p.mando["trim"], p.camara]) + \
			("" if p.app_avion_ajustes.cm_es_diseno(p.sesion["avion"]) else "\n[b][color=#ffb74d]%s[/color][/b]" % p.app_avion_ajustes.texto_cm())
	var L: Dictionary = p.ent.limites
	if p.av["estado"] == "volando" and not p.en_mundo() and dist > L["aviso_m"]:
		var hacia := int(round(fposmod(atan2(-p.av["p"][1], -p.av["p"][0]) * p.R2D + 360, 360)))
		p.hud.lejos_l.text = "¡Demasiado lejos! (%d m) Da la vuelta: el campo está al rumbo %d°. A %d m se pierde el avión." % [int(round(dist)), hacia, int(L["distancia_m"])]
	else: p.hud.lejos_l.text = p.app_avion_ajustes.aviso_lanzamiento() if (p.av["estado"] == "en mano" and not p.rep_activa) else ""
	p.hud.lejos.visible = p.hud.lejos_l.text != ""
	p.hud.disponer(p.camara == 1, p.sin_instrumentos, true, true, dron)
	p.hud_dji.visible = dron and not p.es_fpv() and not p.sin_instrumentos
	if dron and not p.es_fpv(): p.hud_dji.pintar(h, vn, vs, dist)
	p.hud_fpv.visible = p.es_fpv() and not p.sin_instrumentos
	if p.es_fpv(): p.hud_fpv.pintar(h, vn)
	p.hud_uav.visible = p.es_uav() and not p.sin_instrumentos
	if p.es_uav(): p.hud.estado.visible = false; p.hud_uav.pintar(vn, dist, yaw)
	p.mira_recon.visible = p.camara == 3 and not dron and not p.es_uav() and p.ev != null and p.ev.op != null and p.ev.op.d.has("recon")

## Lecturas del bipode (hudBip de la web): velocidad, rumbo, cintura, brazos, pendiente y distancia; sin instrumentos de avion.
func _hud_bip(dist: float, yaw: float) -> void:
	var pend: Array = p.av.get("pendiente", [0.0, 0.0]); var pd: float = (pend[0] * cos(float(p.av["rumbo"])) + pend[1] * sin(float(p.av["rumbo"]))) * 100
	var cint := fposmod(p.av["cintura"] * p.R2D + 180, 360) - 180
	p.hud.pintar_estado([["%s · %d s" % ["REPETICIÓN" if p.rep_activa else ("PARADO" if p.av["estado"] == "en mano" else "EN MARCHA"), int(p.av["t"])], false]] + ([["PAUSA", false]] if p.pausado else []))
	var lect := []
	if not ((p.av["estado"] == "en mano" and p.vuelo == null) or p.sin_instrumentos):
		lect = [["%.1f" % (p.av["vel"] * 3.6), "km/h", ""], ["%03d°" % int(round(fposmod(yaw + 360, 360))), "rumbo", ""], ["%s%d°" % ["+" if cint >= 0 else "", int(round(cint))], "cintura", ""],
				["%d°" % int(round(p.av["brazos"] * p.R2D)), "brazos", ""], ["%s%d %%" % ["+" if pd >= 0 else "", int(round(pd))], "pendiente", "ambar" if absf(pd) > 45 else ""], ["%d" % int(round(dist)), "dist. m", ""]]
	p.hud.pintar_lecturas(lect)
	p.hud.hud_texto.visible = false; p.hud.lejos.visible = false
	p.hud.disponer(p.camara == 1, p.sin_instrumentos, false, true, false)
	p.hud.horiz.visible = false; p.hud.vario.visible = false; p.hud.anemo.visible = false; p.hud.barra.visible = false
	p.hud_dji.visible = false; p.hud_fpv.visible = false

## Piloto automatico de las pruebas: alas niveladas, subida suave hasta 60 m sobre el terreno y luego crucero.
func _piloto_auto() -> void:
	if p.av["estado"] != "volando": return
	if p.es_fpv():            # dron FPV en ANGLE: sube a 30 m con el gas y vuela en circulo despacio
		var vz: float = -Cuat.rot(p.av["q"], p.av["v"])[2]; var hh: float = p.av.get("agl", 0.0); var eu := Cuat.euler(p.av["q"])
		p.av["gases"] = clampf(0.32 / maxf(0.5, cos(eu[0]) * cos(eu[1])) + 0.04 * (30.0 - hh) - 0.05 * vz, 0, 1)
		p.mando["pitch"] = -0.3 if hh > 8 else 0.0; p.mando["yaw"] = 0.12 if hh > 8 else 0.0; p.mando["guinada"] = 0.0
		return
	var e := Cuat.euler(p.av["q"]); var alto: bool = p.av.get("agl", 0.0) > 60
	p.mando["yaw"] = clampf(-(e[0] / p.D2R - (20.0 if alto else 0.0)) / 45.0, -0.6, 0.6)
	p.mando["pitch"] = clampf(((2.0 if alto else 10.0) - e[1] / p.D2R) / 15.0, -0.6, 0.6)
	if p.es_dron(): p.mando["vz"] = 0.6 if p.av.get("agl", 0.0) < 30 else 0.0; p.mando["pitch"] = -0.5 if p.av.get("agl", 0.0) > 10 else 0.0; p.mando["yaw"] = 0.0
	else: p.av["gases"] = 0.55 if alto else float(p._args.get("gases", "1"))

## Pruebas desde la linea de ordenes: vuela solo (gases y lanzamiento), mide el tiempo por cuadro y guarda una captura.
func _auto(dt_real: float) -> void:
	if not p._args.has("auto"): return
	p._t_auto += dt_real
	if p._args.has("vista") and not p.av.is_empty():     # pruebas: dron quieto en N,E,altura,rumbo,gimbal para la captura
		var w := Array(String(p._args["vista"]).split(",")).map(func(x): return float(x))
		p.av["p"] = [w[0], w[1], -(p.ent.altura(w[0], w[1]) + w[2])]; p.av["q"] = Cuat.desde_euler(0, 0, w[3] * p.D2R); p.av["gimbal"] = w[4]; p.av["v"] = [0.0, 0.0, 0.0]
	var vp := p.get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	if p._t_auto > 1.5:
		p._rend.append([dt_real, Performance.get_monitor(Performance.TIME_PROCESS), Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
					  Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
					  RenderingServer.viewport_get_measured_render_time_cpu(vp) / 1000.0, RenderingServer.viewport_get_measured_render_time_gpu(vp) / 1000.0])
	if p._args.has("traza") and p.av["estado"] == "volando" and fmod(p.av["t"], 0.5) < p.DT * 30 and p.av["t"] - float(p._args.get("_tt", "-1")) > 0.3:
		p._args["_tt"] = str(p.av["t"]); var e := Cuat.euler(p.av["q"])
		print("  t %.1f  agl %.1f  V %.1f  alabeo %.0f  cabeceo %.0f  rumbo %.0f  gases %.2f  de %.1f  da %.1f  dr %.1f" % [p.av["t"], p.av["agl"], p.av["V"], e[0] / p.D2R, e[1] / p.D2R, e[2] / p.D2R, p.av["gases"], p.av["de"] / p.D2R, p.av["da"] / p.D2R, p.av["dr"] / p.D2R])
	if p._args.has("terminar") and p.av.get("estado") == "volando" and p.av["t"] >= float(p._args["terminar"]): p.app_vuelo.terminar_vuelo("abandonado")
	if p._args.has("repeticion") and p.pantalla_actual == "pResultado": p._args.erase("repeticion"); p.app_repeticion.ver_repeticion()
	if p._args.has("pausa") and not p.pausado and p.av.get("t", 0.0) >= float(p._args["pausa"]): p.app_repeticion.poner_pausa(true); p._args.erase("pausa")
	if p._args.has("ayuda") and p.av.get("t", 0.0) >= float(p._args["ayuda"]): p.hud.ayuda.visible = true; p._args.erase("ayuda")
	if p.av.get("estado") == "en mano" and p.pantalla_actual == "":
		p.av["gases"] = float(p._args.get("gases", "1")); p.camara = int(p._args.get("camara", "3" if p.es_dron() else "1"))
		if p._t_auto > 0.3:
			if p.es_fpv(): p.av["gases"] = 0.0; p.app_apps_dron.fpv_armar()
			elif p.es_dron(): p.app_apps_dron.dji_despegar()
			else: p.app_vuelo.lanzar()
	if p._t_auto >= float(p._args.get("esperar", "6")):
		var med := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
		for x in p._rend:
			for i in 6: med[i] += x[i] / maxf(1, p._rend.size())
		print("AUTO: %d cuadros, %.1f ms por cuadro (%.0f fps), proceso %.1f ms, render CPU %.1f ms GPU %.1f ms, %d llamadas de dibujo, %.1f M primitivas; estado %s, altura %.1f m, t %.1f s" % [
			p._rend.size(), med[0] * 1000, 1.0 / maxf(med[0], 1e-6), med[1] * 1000, med[4] * 1000, med[5] * 1000, med[2], med[3] / 1e6,
			p.av["estado"], -p.av["p"][2] - p.ent.altura(p.av["p"][0], p.av["p"][1]), p.av["t"]])
		var uf := 0.0; var ut := 0.0
		for x in p._us: uf += x[0] / maxf(1, p._us.size()); ut += x[1] / maxf(1, p._us.size())
		print("AUTO: principal._process %.2f ms por cuadro (fisica y mandos %.2f ms, camara y HUD %.2f ms)" % [ut / 1000, uf / 1000, (ut - uf) / 1000])
		if p._args.has("captura"):
			var img := p.get_viewport().get_texture().get_image(); img.save_png(p._args["captura"])
			print("Captura en " + p._args["captura"])
		p.get_tree().quit()
