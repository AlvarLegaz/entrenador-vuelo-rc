extends SceneTree
## Prueba de la patrulla de vertidos (op_patrulla) con el UAV Cernicalo XM-7 en el simulador Godot, la misma que
## simulador_web/Tests/prueba_patrulla_web.py en el navegador: el trabajo sale con el XM-7 en la cabecera 05R; despegue automatico; en
## cada vertido (el avion puesto a 700 m y 300 m sobre el agua), la torreta fijada en la mancha: con zoom 1x a 1,6 km esta
## demasiado lejos, con la cruz desplazada no vale, con 4x vale y envia la posicion; con la termica el medidor lee la
## mancha; y vuelta con el aterrizaje automatico hasta pararse en la pista: vertidos y pista ok, a mano mal.
## Con ventana (sin --headless) y --fotos=<prefijo>, guarda capturas de la pista y de un vertido (EO e IR).
## Uso (desde la carpeta del repositorio):
##   herramientas/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path simulador_godot --script res://Tests/prueba_patrulla.gd
##   herramientas/godot/Godot_v4.7.2-stable_win64_console.exe --path simulador_godot --resolution 1280x760 --script res://Tests/prueba_patrulla.gd -- --fotos=<prefijo>

const D2R := PI / 180
const DT := 1.0 / 500
var fallos := 0
var p
var prefijo := ""

func _ok(nombre: String, cond: bool, detalle := "") -> void:
	if not cond: fallos += 1
	print("  %s %s %s" % ["OK " if cond else "MAL", nombre, detalle])

## Coloca el avion a "dist" m del vertido i (al suroeste), a 300 m sobre el agua, y fija la torreta en el vertido + desvio
## (m al norte); medio segundo de vuelo quieto ahi y una foto (JUNTO de la prueba web).
func _junto(i: int, dist: float, zoom: float, ter: bool, desvio: float) -> Dictionary:
	var av: Dictionary = p.av; var V: Array = p.ev.op.d["vertidos"][i]
	var vn: float = V[0]; var ve: float = V[1]; var h: float = p.ent.altura(vn, ve); var a := 1.0
	var pn := vn - dist * cos(a); var pe := ve - dist * sin(a)
	av["p"] = [pn, pe, -(h + 300)]; av["q"] = Cuat.desde_euler(0, 0, a); av["v"] = [32.0, 0.0, 0.0]; av["w"] = [0.0, 0.0, 0.0]
	if p.piloto.modo == "DESPEGUE" or p.piloto.modo == "MANUAL": p.app_mandos.uav_poner("CRUCERO")
	p.DJI["zoomI"] = (p.app_apps_dron.camara_dron()["zoom"] as Array).find(zoom); p.DJI["termica"] = ter
	p.UAV["fijo"] = [vn + desvio, ve, h]; p.app_camaras.mover_torreta(0)
	for k in int(0.5 / DT):
		p.app_vuelo.paso(DT); av["p"] = [pn, pe, -(h + 300)]; av["v"] = [32.0, 0.0, 0.0]; p.app_camaras.mover_torreta(DT)
	p.app_camaras.uav_foto()
	return { "T": String(p.hud.toast.text), "lectura": p.ev.op.lectura, "vertidos": p.ev.obj["vertidos"]["estado"], "hechos": (p.ev.op.hechos as Array).duplicate() }

func _captura(nombre: String, ter: bool, cam := 3) -> void:
	if prefijo == "": return
	p.DJI["termica"] = ter; p.camara = cam; p.pantalla_actual = ""; p.pausado = true
	for k in 6:
		p.avion3d.actualizar(p.av); await process_frame
	p.pantalla_actual = "prueba"; p.pausado = false
	root.get_texture().get_image().save_png(prefijo + "_" + nombre + ".png")

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--fotos=") and DisplayServer.get_name() != "headless": prefijo = a.substr(8)
	p = load("res://escenas/principal.tscn").instantiate(); root.add_child(p)
	await create_timer(1.0).timeout
	p.app_pantallas.volar_operacion("op_patrulla")
	for k in 600:
		await process_frame
		if p.pantalla_actual == "" and p.ev != null and p.ev.op != null and not p.av.is_empty(): break
	p.pantalla_actual = "prueba"
	var op: Operacion = p.ev.op; var ej: Array = p.piloto.eje_pista(p.av["p"][0], p.av["p"][1])
	_ok("op_patrulla sale con el XM-7 en la cabecera 05R", p.sesion["avion"] == "XM7" and absf(ej[0] - 60) < 1 and absf(ej[1]) < 1, str(ej))
	var VV: Array = op.d["vertidos"]; var SS: Array = op.d["sectores"]; var cerca := VV.size() == 3
	for i in VV.size(): cerca = cerca and Vector2(VV[i][0] - SS[i][0], VV[i][1] - SS[i][1]).length() <= 600
	_ok("tres vertidos con su sector a menos de 1 km", cerca, str(SS))
	await _captura("pista", false, 2)                     # el XM-7 en la cabecera 05R, con la zona de detalle del aeropuerto
	_ok("objetivos de la patrulla", p.ev.obj.keys() == ["vertidos", "despegue", "a_mano", "altura", "techo", "tiempo", "pista", "aterrizar"], str(p.ev.obj.keys()))
	p.app_vuelo.lanzar(); p.app_mandos.quitar_freno_aparc(); p.app_mandos.uav_poner("DESPEGUE")
	var n := 0
	while p.piloto.modo == "DESPEGUE" and n < int(120 / DT): p.app_vuelo.paso(DT); n += 1
	_ok("despegue automatico desde la pista", p.piloto.modo == "CRUCERO" and p.ev.obj["despegue"]["estado"] == "ok", p.piloto.modo)
	var ah: String = op.ahora(p.ev.obj, p.av); _ok("'Ahora' apunta al sector 1", "sector 1" in ah, ah)
	var r := _junto(0, 1600, 1, false, 0); _ok("a 1,6 km sin zoom: demasiado lejos", "demasiado lejos" in r["T"], r["T"])
	r = _junto(0, 700, 4, false, 130); _ok("cruz a 130 m de la mancha: no vale", not "Vertido 1" in r["T"] and not r["hechos"][0], r["T"])
	r = _junto(0, 700, 4, true, 0); _ok("con la termica el medidor lee la mancha", r["lectura"] != null and r["lectura"]["tipo"] == "vertido", str(r["lectura"]))
	_ok("con 4x y la cruz en la mancha: vertido 1 y posicion enviada", "Vertido 1 ✓" in r["T"], r["T"])
	await _captura("vertido_ir", true); await _captura("vertido_eo", false)
	for i in [1, 2]: r = _junto(i, 700, 4, false, 0)
	_ok("los tres vertidos", r["vertidos"] == "ok" and not (r["hechos"] as Array).has(false), r["T"])
	# vuelta: a 6 km en el eje de la pista, a 300 m, y aterrizaje automatico
	var P: Dictionary = p.piloto.pista; var ent: Array = p.piloto.en_pista(-6000, 0)
	p.av["p"] = [ent[0], ent[1], -(float(P["h"]) + 300)]; p.av["q"] = Cuat.desde_euler(0, 0, float(P["rumbo"]) * D2R); p.av["v"] = [32.0, 0.0, 0.0]; p.av["w"] = [0.0, 0.0, 0.0]
	p.app_mandos.uav_poner("CRUCERO"); p.app_mandos.uav_poner("ATERRIZAJE"); n = 0
	while p.av["estado"] == "volando" and n < int(600 / DT): p.app_vuelo.paso(DT); n += 1
	var fin: String = String(p.vuelo["final"]) if p.vuelo != null else String(p.av["estado"])
	_ok("vuelve y aterriza solo en la pista", fin == "aterrizado", fin)
	var o: Dictionary = {}
	for k in p.ev.obj: o[k] = p.ev.obj[k]["estado"]
	_ok("objetivos: vertidos, despegue, pista y tiempo ok; a mano mal (automatico)",
		o["vertidos"] == "ok" and o["despegue"] == "ok" and o["pista"] == "ok" and o["tiempo"] == "ok" and o["a_mano"] == "mal", str(o))
	await _con_grajo()
	print("RESULTADO: ", "todo bien" if fallos == 0 else "%d fallos" % fallos)
	quit(1 if fallos else 0)


## La misma patrulla con el Grajo MX-2 (como prueba_patrulla_web.py): se elige en la ventana de Volar, con las
## comprobaciones del avion lanzado a mano; sale en la cabecera de la 05R, se lanza (no cuenta como despegue automatico),
## encuentra los tres vertidos con la torreta a 4x y aterriza solo (toma en perdida) en la pista.
func _con_grajo() -> void:
	await Desgaste.modificar(p, "GRAJO", func(est):      # como nuevo (la toma en perdida de otro vuelo puede soltar el ala)
		var v = est.get("version", 0); est.clear(); est.merge(Desgaste.nuevo()); est["version"] = v)
	p.aj["morro"] = { "GRAJO": "orientable" }            # solo en memoria: la bateria guarda y restaura los datos del usuario
	var Op = p.pantallas["pOperaciones"]; p.mostrar("pOperaciones"); Op.sel = "op_patrulla"; Op.refrescar(); Op.pedir_comprobaciones()
	await process_frame
	var nombres := []
	for b in Op.check_veh_botones.get_children():
		if not b.is_queued_for_deletion(): nombres.append(String(b.text).split("\n")[0])
	_ok("al volar se elige el vehiculo: el Cernicalo o el Grajo", Op.check_veh.visible and nombres == ["Cernícalo XM-7", "Grajo MX-2"], str(nombres))
	p.op_vehiculo["op_patrulla"] = "GRAJO"; Op.pedir_comprobaciones()
	_ok("con el Grajo, las comprobaciones del avion lanzado a mano", Op.comprobaciones_de("op_patrulla") == PantallaMisiones.COMPROBACIONES_MANO and Op.check_si.disabled)
	Op.check.visible = false
	p.app_pantallas.volar_operacion("op_patrulla")
	for k in 600:
		await process_frame
		if p.pantalla_actual == "" and p.ev != null and p.ev.op != null and not p.av.is_empty(): break
	p.pantalla_actual = "prueba"
	var ej: Array = p.ev.op.eje_pista(p.av["p"][0], p.av["p"][1])
	_ok("sale con el Grajo, en mano, en la cabecera de la 05R", p.sesion["avion"] == "GRAJO" and p.av["estado"] == "en mano" and absf(ej[0] - 60) < 1 and absf(ej[1]) < 1, str(ej))
	p.app_vuelo.lanzar(); var n := 0
	while p.av["estado"] == "volando" and n < int(25 / DT): p.app_vuelo.paso(DT); n += 1
	_ok("lanzado a mano desde la pista: despegue ok y no cuenta como automatico", p.ev.obj["despegue"]["estado"] == "ok" and not p.piloto.automatico and float(p.av["agl"]) > 15,
		"%s %.1f m" % [p.ev.obj["despegue"]["estado"], float(p.av["agl"])])
	var r := {}
	for i in 3: r = _junto(i, 700, 4, false, 0)
	_ok("el Grajo encuentra los tres vertidos con la torreta a 4x", r["vertidos"] == "ok" and not (r["hechos"] as Array).has(false), r["T"])
	var c: Dictionary = p.app_evaluacion._casa(); var vto: Dictionary = p.ent.viento; var desde: float = float(vto["rumbo"]) + PI if float(vto["base"]) > 0.2 else 0.0
	var pn: float = c["N"] + 500 * cos(desde); var pe: float = c["E"] + 500 * sin(desde)
	p.av["p"] = [pn, pe, -(p.ent.altura(pn, pe) + 60)]; p.av["q"] = Cuat.desde_euler(0, 0, desde + PI); p.av["v"] = Cuat.rot(p.av["q"], [14.0, 0.0, 0.0]); p.av["w"] = [0.0, 0.0, 0.0]
	p.app_mandos.uav_poner("CRUCERO"); p.app_mandos.uav_poner("ATERRIZAJE"); n = 0
	while p.av["estado"] == "volando" and n < int(400 / DT): p.app_vuelo.paso(DT); n += 1
	var fin: String = String(p.vuelo["final"]) if p.vuelo != null else String(p.av["estado"])
	var o: Dictionary = {}
	for k in p.ev.obj: o[k] = p.ev.obj[k]["estado"]
	_ok("vuelve y aterriza solo (toma en perdida) en la pista", fin == "aterrizado" and o["pista"] == "ok", "%s %s" % [fin, str(p.ev.op.eje_pista(p.av["p"][0], p.av["p"][1]))])
	_ok("objetivos: vertidos, despegue y tiempo ok; a mano mal (aterrizaje automatico)",
		o["vertidos"] == "ok" and o["despegue"] == "ok" and o["tiempo"] == "ok" and o["a_mano"] == "mal", str(o))
