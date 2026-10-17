class_name AppAppsDron
extends RefCounted
## La app del dron comercial (modos, foto, video, despegue, RTH) y el dron FPV (armar y modos de Betaflight).
## Parte de principal.gd (como js/app/apps_dron.js de la web): el estado esta en principal.gd (p).

var p: Principal

func _init(principal: Principal) -> void: p = principal

func dji_modo(m := "") -> void:
	if p.modelo == null or not p.es_dron() or p.es_fpv(): return
	p.modelo.modo = m if m != "" else { "N": "S", "S": "C", "C": "N" }.get(p.modelo.modo, "N")
	p.poner_toast("Modo %s%s" % [p.NOMBRES_MODO[p.modelo.modo], " · sin frenado suave" if p.modelo.modo == "S" else ""])

func dji_foto() -> void:
	if p.modelo == null or not p.es_dron(): return
	p.DJI["fotos"] += 1; p.hud_dji.foto()
	var T: Array = p.ev.op.foto(p.av, p.av.get("gimbal", -10.0), cam_dji()) if (p.ev != null and p.ev.op != null) else []     # operaciones: lo que vale esa foto
	p.poner_toast(" · ".join(T) if not T.is_empty() else "Foto %d" % p.DJI["fotos"])

func dji_video() -> void:
	if p.modelo == null or not p.es_dron(): return
	p.DJI["video"] = true; p.DJI["grabando"] = not p.DJI["grabando"]
	if p.DJI["grabando"]: p.DJI["tRec"] = 0.0; p.DJI["tAnt"] = p.av["t"]
	p.poner_toast("Grabando" if p.DJI["grabando"] else "Vídeo guardado")

func dji_disparo() -> void:
	if p.DJI["video"]: dji_video()
	else: dji_foto()

func dji_cam_modo() -> void:
	p.DJI["video"] = not p.DJI["video"]
	if not p.DJI["video"]: p.DJI["grabando"] = false

## La camara del dron de inspeccion (datos.camara: niveles de zoom, hasta donde es optico y si lleva termica), o null.
func camara_dron():
	var Dm = p.modelo.get("datos") if p.modelo != null else null
	return Dm["camara"] if Dm is Dictionary and Dm.get("camara") is Dictionary else null

## El zoom actual y si esta la termica (camDJI de la web).
func cam_dji() -> Dictionary:
	var C = camara_dron()
	if C == null: return { "zoom": 1.0, "termica": false }
	var Z: Array = C["zoom"]
	return { "zoom": float(Z[clampi(p.DJI["zoomI"], 0, Z.size() - 1)]), "termica": bool(C.get("termica", false)) and p.DJI["termica"] }

func dji_zoom(paso: int) -> void:
	var C = camara_dron()
	if C == null or p.rep_activa: return
	var Z: Array = C["zoom"]; p.DJI["zoomI"] = clampi(p.DJI["zoomI"] + paso, 0, Z.size() - 1); var z: float = Z[p.DJI["zoomI"]]
	p.poner_toast("Zoom %dx" % int(z) + (" · gran angular" if z == 1 else (" · teleobjetivo" if z <= float(C["zoom_optico"]) else " · digital")))

func dji_termica() -> void:
	var C = camara_dron()
	if C == null or not C.get("termica", false) or p.rep_activa: return
	p.DJI["termica"] = not p.DJI["termica"]; p.poner_toast("Cámara térmica" if p.DJI["termica"] else "Cámara normal")

## Boton de despegue de la app: en el suelo arma y sube a 1,2 m; en vuelo, aterriza en el sitio.
func dji_despegar() -> void:
	if p.modelo == null or not p.es_dron() or p.rep_activa: return
	if p.av["estado"] == "en mano": p.app_vuelo.lanzar(); p.modelo.despegar(p.av); p.hud.aviso.text = ""
	elif p.av["estado"] == "volando" and p.av.get("posado", false): p.modelo.despegar(p.av)
	elif p.av["estado"] == "volando": p.av["rth"] = { "fase": "bajar" }; p.poner_toast("Aterrizando")

func dji_rth() -> void:
	if p.modelo == null or not p.es_dron() or p.rep_activa or p.av["estado"] != "volando" or p.av.get("posado", false): return
	if p.av.get("batForzado", false): p.poner_toast("Aterrizaje forzoso por batería crítica: no se puede cancelar"); return
	if p.av.get("rth") != null and p.av["rth"]["fase"] != "bajar": p.av["rth"] = null; p.poner_toast("Volver a casa cancelado"); return
	p.modelo.volver_a_casa(p.av); p.poner_toast("Volviendo a casa")

func gas_fpv_consola(s: float) -> float:
	var f := func(x: float) -> float: return 0.25 * x + 0.75 * x * x * x
	if (p.av.get("posado", false) or p.av["estado"] == "en mano") and s <= 0.05: return 0.0
	return p.FPV_GAS_ESTACIONARIO + (1 - p.FPV_GAS_ESTACIONARIO) * f.call(s) if s >= 0 else p.FPV_GAS_ESTACIONARIO * (1 - f.call(-s))

func fpv_armar() -> void:
	if p.modelo == null or not p.es_fpv() or p.rep_activa: return
	if p.av["estado"] == "en mano":
		if p.av["gases"] > 0.05: p.poner_toast("Para armar, baja el gas del todo (S o palanca izquierda abajo)"); return
		p.app_vuelo.lanzar()
	elif p.av["estado"] == "volando" and p.av["armado"]:
		p.modelo.desarmar(p.av); p.poner_toast("DESARMADO")
		if p.av["estado"] == "en mano": p.hud.aviso.text = "Gas abajo del todo y L (o botón A) para armar"

## Modo de vuelo de Betaflight: ANGLE -> HORIZON -> ACRO -> ANGLE (tecla M, LB del mando o el que se pida).
func fpv_modo(m := "") -> void:
	if p.modelo == null or not p.es_fpv(): return
	p.modelo.modo = m if m != "" else { "ANGLE": "HORIZON", "HORIZON": "ACRO", "ACRO": "ANGLE" }.get(p.modelo.modo, "ANGLE")
	p.poner_toast("Modo %s%s" % [p.modelo.modo, " · sin autonivelado" if p.modelo.modo == "ACRO" else (" · se nivela solo" if p.modelo.modo == "ANGLE" else "")])
