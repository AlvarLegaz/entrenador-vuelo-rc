extends SceneTree
## Prueba de la carrera de drones del Politecnico (op_carrera) en el simulador Godot, la misma que
## pruebas/prueba_carrera_web.py en el navegador: el trabajo sale con el FPV (y se puede elegir otro dron), los 19
## obstaculos se dibujan, el recorrido "perfecto" (por el centro de cada obstaculo y, entre uno y otro, la linea de
## carrera: hasta 18 m sobre el suelo, pendiente 1,2) no choca con nada con la fisica de verdad, cruza los 19 en orden y
## termina el vuelo con su marca; saltarse el 6 descalifica. Con ventana y --fotos=<prefijo>, guarda capturas.
## Uso (desde la carpeta del repositorio):
##   herramientas/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path simulador_godot --script res://pruebas/prueba_carrera.gd
##   herramientas/godot/Godot_v4.7.2-stable_win64_console.exe --path simulador_godot --resolution 1280x760 --script res://pruebas/prueba_carrera.gd -- --fotos=<prefijo> [--avion=DJI_MINI]

const DT := 1.0 / 500
var fallos := 0
var p
var prefijo := ""
var avion := ""

func _ok(nombre: String, cond: bool, detalle := "") -> void:
	if not cond: fallos += 1
	print("  %s %s %s" % ["OK " if cond else "MAL", nombre, detalle])

func _preparar() -> void:
	p.ir_operaciones(); var O = p.pantallas["pOperaciones"]; O.sel = "op_carrera"; O.refrescar()
	if avion != "": p.op_vehiculo["op_carrera"] = avion
	p.volar_operacion("op_carrera")
	for k in 900:
		await process_frame
		if p.pantalla_actual == "" and p.ev != null and p.ev.op != null and not p.av.is_empty() and not p.mundo3d.carrera_obst.is_empty(): break
	p.pantalla_actual = "prueba"

## El recorrido (VUELO de la prueba web): salta = indice que se salta (-1), hasta = cuantos obstaculos.
func _vuelo(v: float, salta: int, hasta: int) -> Dictionary:
	var M: Dictionary = Operacion.CARRERA["MEDIDAS"]; var O: Array = p.ev.op.obst; var H := 18.0; var K := 1.2; var seg := []
	var alt := func(n: float, e: float) -> float: return p.ent.altura(n, e)
	for j in mini(O.size(), hasta):
		if j == salta: continue
		var o: Dictionary = O[j]; var r: float = float(o["rumbo"]) * PI / 180
		if o["tipo"] == "picado": seg.append([[o["n"], o["e"], o["y0"] + 5], [o["n"], o["e"], o["y0"] - 3], [o["n"] + 5 * cos(r), o["e"] + 5 * sin(r), o["y0"] - 3]]); continue
		var h: float = o["y0"] + M[o["tipo"]][1] / 2.0
		seg.append([[o["n"] - 4 * cos(r), o["e"] - 4 * sin(r), h], [o["n"] + 4 * cos(r), o["e"] + 4 * sin(r), h]])
	if p.av["estado"] == "en mano": p.lanzar()
	var av: Dictionary = p.av; var a: Array = [av["p"][0], av["p"][1], -av["p"][2] + 1.5]; var donde = null
	var ir := func(q: Array, b: Array) -> bool:
		p.destino_prueba = [q[0], q[1], -q[2]]; p.av["q"] = Cuat.desde_euler(0, 0, atan2(b[1] - q[1], b[0] - q[0])); p.av["posado"] = false; p.av["enTierra"] = false
		if p.av["estado"] == "en mano": p.av["estado"] = "volando"         # llevado en volandas: ya ha despegado
		p.paso(DT); return p.av["estado"] == "volando"
	var roto := false
	for sg in seg:
		var ent: Array = sg[0]; var L := Vector2(ent[0] - a[0], ent[1] - a[1]).length()
		var ha: float = a[2] - alt.call(a[0], a[1]); var hb: float = ent[2] - alt.call(ent[0], ent[1]); var k := maxi(1, int(ceil(L / (v * DT))))
		for i in range(1, k + 1):                                          # la linea de carrera hasta la entrada del obstaculo
			var f := float(i) / k; var n: float = a[0] + f * (ent[0] - a[0]); var e: float = a[1] + f * (ent[1] - a[1]); var s := f * L
			var h: float = alt.call(n, e) + minf(maxf(H, maxf(ha, hb)), minf(ha + K * s, hb + K * (L - s)))
			if not ir.call([n, e, h], ent): donde = [n, e, h]; roto = true; break
		if roto: break
		for m in range(1, sg.size()):                                      # por el obstaculo (el picado: abajo y por delante)
			var p0: Array = sg[m - 1]; var sal: Array = sg[m]; var L2 := Vector3(sal[0] - p0[0], sal[1] - p0[1], sal[2] - p0[2]).length(); var k2 := maxi(1, int(ceil(L2 / (v * DT))))
			for i in range(1, k2 + 1):
				var f := float(i) / k2; var q := [p0[0] + f * (sal[0] - p0[0]), p0[1] + f * (sal[1] - p0[1]), p0[2] + f * (sal[2] - p0[2])]
				if not ir.call(q, sal): donde = q; roto = true; break
			if roto: break
		if roto: break
		a = sg[-1]
	p.destino_prueba = null
	var i := 0
	while i < int(3 / DT) and p.av["estado"] == "volando": p.av["v"] = [0.0, 0.0, 0.0]; p.paso(DT); i += 1
	var C: Dictionary = p.ev.op.carr; var o := {}
	for k in p.ev.obj: o[k] = p.ev.obj[k]["estado"]
	return { "final": String(p.vuelo["final"]) if p.vuelo != null else "", "donde": donde, "marca": p.vuelo.get("marca") if p.vuelo != null else null, "k": C["k"], "fuera": C["fuera"],
			 "t": (C["tFin"] - C["t0"]) if C["tFin"] != null else null, "obj": o }

func _foto(nombre: String, camara: int) -> void:
	if prefijo == "": return
	p.camara = camara; p.pantalla_actual = ""; p.pausado = true
	for k in 6: p.avion3d.actualizar(p.av); await process_frame
	p.pantalla_actual = "prueba"; p.pausado = false
	root.get_texture().get_image().save_png(prefijo + "_" + nombre + ".png")

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--fotos=") and DisplayServer.get_name() != "headless": prefijo = a.substr(8)
		if a.begins_with("--avion="): avion = a.substr(8)
	p = load("res://escenas/principal.tscn").instantiate(); root.add_child(p)
	await create_timer(1.0).timeout
	await _preparar()
	_ok("la carrera sale con %s" % (avion if avion != "" else "el FPV"), p.sesion["avion"] == (avion if avion != "" else "FPV"), p.sesion["avion"])
	_ok("los 19 obstaculos se dibujan", p.mundo3d.carrera_obst.size() == 19 and p.ev.op.obst.size() == 19)
	_ok("objetivos de la carrera", p.ev.obj.keys() == ["secuencia", "meta", "tiempo", "choques"], str(p.ev.obj.keys()))
	if prefijo != "":
		_vuelo(20, -1, 3); await _foto("carrera_fpv", 3); await _foto("carrera_cam2", 2)
		await _preparar()
	var r := _vuelo(20, -1, 99)
	_ok("el recorrido perfecto no choca con nada y llega a la meta", r["final"] == "carrera terminada", "%s %s" % [r["final"], str(r["donde"])])
	_ok("cruza los 19 en orden", r["k"] == 19 and r["t"] != null, "%d obstaculos, %s" % [r["k"], Operacion.crono(r["t"]) if r["t"] != null else "-"])
	_ok("la marca del vuelo y el mejor de la sesion", r["marca"] != null and p.carrera_mejor != null and absf(p.carrera_mejor["t"] - r["t"]) < 1e-9, str(p.carrera_mejor))
	_ok("objetivos: todos ok (APTO)", (r["obj"] as Dictionary).values().all(func(x): return x == "ok"), str(r["obj"]))
	await _preparar()
	r = _vuelo(20, 5, 99)
	_ok("saltandose el 6: descalificado y se acaba el vuelo", r["final"] == "descalificado" and r["fuera"] == 5, "%s %s" % [r["final"], str(r["fuera"])])
	print("RESULTADO: ", "todo bien" if fallos == 0 else "%d fallos" % fallos)
	quit(1 if fallos else 0)
