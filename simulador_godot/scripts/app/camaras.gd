class_name AppCamaras
extends RefCounted
## Camaras de trabajo: la torreta EO/IR y el morro fijo del UAV, la camara de a bordo de los aviones y sus fotos.
## Parte de principal.gd (como js/app/camaras.js de la web): el estado esta en principal.gd (p).

var p: Principal

func _init(principal: Principal) -> void: p = principal

## Las flechas mueven la torreta (y no el avion) con el piloto automatico navegando, o con Mayusculas.
func torreta_con_flechas() -> bool:
	return p.piloto != null and (Input.is_physical_key_pressed(KEY_SHIFT) or p.piloto.modo in ["PUNTO", "BASE", "DESPEGUE", "ATERRIZAJE"])

## Donde esta la torreta (NED) y hacia donde mira (vector unitario NED).
func eje_torreta() -> Array:
	if p.avion3d != null and p.avion3d.cam_fija != null:            # morro fijo: sujeta al avion
		var tf: Dictionary = p.av["torreta"]; var ct := cos(float(tf["tilt"])); var st := sin(float(tf["tilt"])); var cf := Cuat.rot(p.av["q"], p.avion3d.cam_fija["pos"])
		return [[p.av["p"][0] + cf[0], p.av["p"][1] + cf[1], p.av["p"][2] + cf[2]], Cuat.rot(p.av["q"], [ct * cos(float(tf["pan"])), ct * sin(float(tf["pan"])), -st])]
	var tr: Dictionary = p.av["torreta"]; var yaw: float = Cuat.euler(p.av["q"])[2] + tr["pan"]
	var c := Cuat.rot(p.av["q"], p.modelo.datos["malla"]["torreta"]["centro"]) if p.modelo.datos["malla"].has("torreta") else [0.0, 0.0, 0.0]
	return [[p.av["p"][0] + c[0], p.av["p"][1] + c[1], p.av["p"][2] + c[2]], [cos(yaw) * cos(tr["tilt"]), sin(yaw) * cos(tr["tilt"]), -sin(tr["tilt"])]]

## El punto de la cruz: [N, E, altura del suelo, distancia] donde el eje de la torreta corta el terreno (o el agua), o null.
func punto_cruz() -> Variant:
	var et := eje_torreta(); var o: Array = et[0]; var d: Array = et[1]
	if d[2] <= 0.002: return null
	var H := func(N: float, E: float) -> float: return p.ent.altura(N, E) if p.en_mundo() else 0.0
	var s := 5.0; var ant := 0.0
	while s < 20000:
		if -(o[2] + s * d[2]) <= H.call(o[0] + s * d[0], o[1] + s * d[1]):
			var a := ant; var b := s
			for k in 12:
				var m := (a + b) / 2
				if -(o[2] + m * d[2]) <= H.call(o[0] + m * d[0], o[1] + m * d[1]): b = m
				else: a = m
			return [o[0] + b * d[0], o[1] + b * d[1], H.call(o[0] + b * d[0], o[1] + b * d[1]), b]
		ant = s; s += maxf(5, s * 0.02)
	return null

## Cada cuadro: mueve la torreta con las flechas, Q/E y el mando (mas despacio cuanto mas zoom) o la apunta al punto fijo.
## Morro fijo: la camara de la ventana elegida (frontal o lateral), con su inclinacion fija respecto al avion.
func poner_vista_fija() -> void:
	var F: Array = DatosComunes.avion(p.sesion["avion"])["malla"]["cam_fija"][p.UAV.get("vista", "frontal")]
	p.av["torreta"] = { "pan": float(F[0]) * p.D2R, "tilt": float(F[1]) * p.D2R }

func cambiar_vista_fija() -> void:
	p.UAV["vista"] = "frontal" if p.UAV.get("vista", "frontal") == "lateral" else "lateral"; poner_vista_fija()
	p.poner_toast("Cámara lateral (izquierda)" if p.UAV["vista"] == "lateral" else "Cámara frontal")

func mover_torreta(dt: float) -> void:
	if p.modelo == null or not p.es_uav() or p.av.is_empty() or not p.av.has("torreta") or p.av["estado"] == "roto": return
	if p.app_evaluacion.morro_de(p.sesion["avion"]) == "fijo": p.UAV["cruz"] = punto_cruz(); return      # el morro fijo no se mueve: la cruz, donde mire el avion
	var tr: Dictionary = p.av["torreta"]; var z: float = p.app_apps_dron.cam_dji()["zoom"]; var k := p.TORRETA_VEL / pow(z, 0.7) * dt; var fl := torreta_con_flechas()
	var T := func(kk: int) -> float: return 1.0 if Input.is_physical_key_pressed(kk) else 0.0
	var dp: float = ((T.call(KEY_RIGHT) - T.call(KEY_LEFT)) if fl else 0.0) + (p._mando_torreta[0] if not p._mando_torreta.is_empty() else 0.0)
	var dtl: float = ((T.call(KEY_UP) - T.call(KEY_DOWN)) if fl else 0.0) + T.call(KEY_E) - T.call(KEY_Q) + (-p._mando_torreta[1] if not p._mando_torreta.is_empty() else 0.0) + p.mando_cfg.gimbal
	if dp != 0 or dtl != 0:
		if p.UAV["fijo"] != null: p.UAV["fijo"] = null; p.poner_toast("Torreta: punto suelto")
		tr["pan"] = PilotoUAV.envolver(tr["pan"] + dp * k); tr["tilt"] = clampf(tr["tilt"] + dtl * k, -90 * p.D2R, 10 * p.D2R)
	elif p.UAV["fijo"] != null:
		var o: Array = eje_torreta()[0]; var dn: float = p.UAV["fijo"][0] - o[0]; var de: float = p.UAV["fijo"][1] - o[1]; var dz: float = -p.UAV["fijo"][2] - o[2]
		tr["pan"] = PilotoUAV.envolver(atan2(de, dn) - Cuat.euler(p.av["q"])[2]); tr["tilt"] = clampf(-atan2(dz, Vector2(dn, de).length()), -90 * p.D2R, 10 * p.D2R)
	p.UAV["cruz"] = punto_cruz()

## K: fija la torreta en el punto de la cruz (o la suelta).
func uav_fijar() -> void:
	if p.app_evaluacion.morro_de(p.sesion["avion"]) == "fijo": p.poner_toast("Con el morro fijo no hay torreta: apunta con el avión"); return
	if not p.es_uav(): return
	if p.UAV["fijo"] != null: p.UAV["fijo"] = null; p.poner_toast("Torreta: punto suelto"); return
	var c: Variant = punto_cruz()
	if c == null: p.poner_toast("La cruz no apunta al suelo: baja la torreta"); return
	p.UAV["fijo"] = [c[0], c[1], c[2]]; p.poner_toast("Torreta fijada en " + p.app_mandos.coord_txt(c[0], c[1]))

## F: foto de la torreta (en un trabajo, lo que vale para el; si no, la foto con las coordenadas del punto de la cruz).
## Foto con la camara de a bordo de un avion (reconocimiento): mira al frente, con el cabeceo del avion.
func avion_foto() -> void:
	if p.av["estado"] != "volando" or p.rep_activa: return
	var co := camara_op(); p.poner_toast(" · ".join(p.ev.op.foto(p.av, co["gimbal"], { "pan": co["pan"], "zoom": 1.0 })))

## La camara de las operaciones como gimbal (grados) y giro respecto al rumbo del avion (rad) (camaraOp de la web): la
## torreta, tal cual; el morro fijo del UAV y la camara de a bordo de los aviones (al frente), con su direccion real.
func camara_op() -> Dictionary:
	if p.es_uav() and p.av.has("torreta") and not (p.avion3d != null and p.avion3d.cam_fija != null): return { "gimbal": p.av["torreta"]["tilt"] * p.R2D, "pan": p.av["torreta"]["pan"] }
	var dd: Array = eje_torreta()[1] if (p.es_uav() and p.av.has("torreta")) else Cuat.rot(p.av["q"], [1.0, 0.0, 0.0])
	return { "gimbal": -asin(clampf(dd[2], -1, 1)) * p.R2D, "pan": PilotoUAV.envolver(atan2(dd[1], dd[0]) - Cuat.euler(p.av["q"])[2]) }

func uav_foto() -> void:
	if not p.es_uav() or p.av["estado"] != "volando": return
	p.UAV["fotos"] += 1
	var co := camara_op(); var cm := p.app_apps_dron.cam_dji(); cm["pan"] = co["pan"]
	var Tt: Array = p.ev.op.foto(p.av, co["gimbal"], cm) if (p.ev != null and p.ev.op != null) else []
	var c = p.UAV["cruz"]; var txt := "Foto %d" % p.UAV["fotos"]
	if c != null and p.en_mundo(): txt += " · %s · a %s" % [p.app_mandos.coord_txt(c[0], c[1]), ("%d m" % int(round(c[3]))) if c[3] < 1000 else ("%s km" % ("%.1f" % (c[3] / 1000)).replace(".", ","))]
	p.poner_toast(" · ".join(Tt) if not Tt.is_empty() else txt)
