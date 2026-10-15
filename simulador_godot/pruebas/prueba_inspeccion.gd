extends SceneTree
## Prueba del dron de inspeccion (Inspector HQ-3T) en el simulador Godot, la misma que pruebas/prueba_inspeccion_web.py en
## el navegador: el dron esta en el hangar; los trabajos de la fabrica de SABIC y de los paneles salen con el, y los demas
## con el Mini Dron HQ; zoom y camara termica con las teclas Z / X / C; en la fabrica, el medidor puntual sostenido 3 s
## sobre un punto caliente lo da por medido, la fuga igual (sin entrar en la zona ATEX), la placa de la antorcha se lee
## con 28x desde mas de 60 m y su piloto con la termica; en los paneles, los puntos calientes solo valen con la termica.
## Con ventana (sin --headless) y --fotos=<prefijo>, guarda capturas de la termica y del zoom.
## Uso (desde la carpeta del repositorio):
##   herramientas/godot/Godot_v4.7.2-stable_win64_console.exe --path simulador_godot --resolution 1280x720 --script res://pruebas/prueba_inspeccion.gd -- --fotos=<prefijo>

const R2D := 180.0 / PI
const DT := 1.0 / 500
var fallos := 0
var p
var prefijo := ""

func _ok(nombre: String, cond: bool, detalle := "") -> void:
	if not cond: fallos += 1
	print("  %s %s %s" % ["OK " if cond else "MAL", nombre, detalle])

func _preparar(id: String) -> void:
	p.volar_operacion(id)
	for k in 600:
		await process_frame
		if p.pantalla_actual == "" and p.ev != null and not p.av.is_empty(): break
	p.pantalla_actual = "prueba"

## Coloca el dron a "dist" m del punto P (N, E, arriba), a "dh" m por encima, mirandolo (desde el rumbo "desde", o el de
## 1 rad), y avanza el trabajo "s" segundos sin fisica (APUNTAR de la prueba web).
func _apuntar(P: Array, dist: float, dh: float, s: float, zoom: float, termica: bool, foto: bool, desde = null) -> Dictionary:
	var av: Dictionary = p.av; var op: Operacion = p.ev.op
	var N: float = P[0]; var E: float = P[1]; var up: float = P[2]
	var a: float = 1.0 if desde == null else float(desde) + PI
	var pn := N - dist * cos(a); var pe := E - dist * sin(a); var pu := up + dh
	if av["estado"] == "en mano": p.lanzar(); p.modelo.despegar(av)
	av["posado"] = false; av["despegado"] = true; av["rth"] = null; av["despegueAuto"] = false
	p.DJI["zoomI"] = (p.camara_dron()["zoom"] as Array).find(zoom); p.DJI["termica"] = termica
	var T := []
	for i in int(round(s / DT)):
		av["p"] = [pn, pe, -pu]; av["v"] = [0.0, 0.0, 0.0]; av["w"] = [0.0, 0.0, 0.0]
		av["q"] = Cuat.desde_euler(0, 0, atan2(E - pe, N - pn))
		av["gimbal"] = atan2(up - pu, Vector2(N - pn, E - pe).length()) * R2D; av["hold"] = null
		T.append_array(op.paso((av["p"] as Array).duplicate(), av, DT, { "gimbal": av["gimbal"], "grabando": false }.merged(p.cam_dji())))
		av["t"] += DT
	if foto: T.append_array(op.foto(av, av["gimbal"], p.cam_dji()))
	var est := func(k: String): return p.ev.obj[k]["estado"] if p.ev.obj.has(k) else null
	return { "T": T, "lectura": op.lectura, "calientes": est.call("calientes"), "fuga": est.call("fuga"), "atex": est.call("atex"),
			 "placa": est.call("placa"), "piloto": est.call("piloto"), "defectos": est.call("defectos") }

## Rumbo (desde el objeto), altura sobre el, distancia y zoom desde los que el medidor ve el objeto P de ese tipo (sin
## estructuras delante; la fuga, desde fuera de la zona ATEX), o null. zoom0 0: 2x hasta 60 m y 4x mas lejos
## (BUSCAR_VISTA de la prueba web).
func _buscar_vista(P: Array, tipo: String, dists: Array, zoom0: float, libre := false) -> Variant:
	var op: Operacion = p.ev.op; var U: Array = op.unidad_fuga.get("poligono", [])
	for dist in dists:
		for dh in [5.0, 8.0, 10.0, 15.0, 20.0, 30.0, 45.0, 60.0]:
			for k in 24:
				var a := k * PI / 12; var pn: float = P[0] + dist * cos(a); var pe: float = P[1] + dist * sin(a); var pu: float = P[2] + dh
				var zoom: float = zoom0 if zoom0 > 0 else (4.0 if dist > 60 else 2.0)
				if not libre and not U.is_empty() and (Operacion.dentro(U, pn, pe) or Operacion.a_borde(U, pn, pe) <= float(op.d["atex"])): continue     # sin entrar en la ATEX
				var g := atan2(P[2] - pu, Vector2(P[0] - pn, P[1] - pe).length()) * R2D; var q := Cuat.desde_euler(0, 0, atan2(P[1] - pe, P[0] - pn))
				var L = op.medir({ "p": [pn, pe, -pu], "q": q }, g, zoom)
				if L != null and L["tipo"] == tipo and absf(float(L["dist"]) - Vector2(dist, dh).length()) < 3: return [a, dh, float(dist), zoom]
	return null

func _captura(nombre: String) -> void:
	if prefijo == "": return
	p.camara = 3; p.pantalla_actual = ""; p.pausado = true
	for k in 6:
		p.avion3d.actualizar(p.av); await process_frame
	p.pantalla_actual = "prueba"
	root.get_texture().get_image().save_png(prefijo + "_" + nombre + ".png")

func _texto(r: Dictionary) -> String: return " · ".join(r["T"])

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--fotos=") and DisplayServer.get_name() != "headless": prefijo = a.substr(8)
	p = load("res://escenas/principal.tscn").instantiate(); root.add_child(p)
	await create_timer(1.0).timeout
	_ok("el Inspector HQ-3T esta en el hangar", p.ids_hangar().has("HQ3T") and DatosComunes.avion("HQ3T")["nombre"] == "Inspector HQ-3T")
	_ok("se crea con la fisica del dron comercial", p.crear_modelo("HQ3T") is ModeloCuadricoptero)
	for par in [["op_inspeccion", "DJI_MINI"], ["op_video", "DJI_MINI"], ["op_paneles", "HQ3T"]]:
		await _preparar(par[0]); _ok("%s sale con %s" % par, p.sesion["avion"] == par[1], p.sesion["avion"])
	# ---- paneles: cristal roto (solo camara normal), excrementos (las dos) y diodo de bypass (solo termica)
	var op: Operacion = p.ev.op
	_ok("paneles: 6 modulos danados a simple vista y 3 diodos averiados", op.modulos.size() == 6 and op.modulos_c.size() == 3, "%d %d" % [op.modulos.size(), op.modulos_c.size()])
	var Pm: Array = op.modulos_c[0]
	var r := _apuntar(Pm, 0.01, 12, 0.1, 1, false, true); _ok("diodo: sin termica no vale", not "Diodo" in _texto(r), _texto(r))
	r = _apuntar(Pm, 0.01, 12, 0.1, 1, true, true); _ok("diodo: con termica vale", "Diodo de bypass averiado 1" in _texto(r), _texto(r))
	await _captura("paneles_termica")
	var Pr: Array = op.modulos[0]; var Pe: Array = op.modulos[1]
	r = _apuntar(Pr, 0.01, 12, 0.1, 1, true, true); _ok("cristal roto: con termica no vale", not "Cristal roto" in _texto(r), _texto(r))
	r = _apuntar(Pr, 0.01, 12, 0.1, 1, false, true); _ok("cristal roto: con la camara normal vale", "Cristal roto (módulo 1)" in _texto(r), _texto(r))
	await _captura("paneles_cristal")
	r = _apuntar(Pe, 0.01, 12, 0.1, 1, true, true); _ok("excrementos: con termica vale (punto caliente)", "Excrementos de aves (módulo 2), punto caliente" in _texto(r), _texto(r))
	await _captura("paneles_excrementos_termica")
	r = _apuntar(Pe, 0.01, 12, 0.1, 1, false, false)
	await _captura("paneles_excrementos")
	# ---- fabrica
	await _preparar("op_sabic"); op = p.ev.op
	_ok("op_sabic sale con el HQ3T y sus objetos termicos", p.sesion["avion"] == "HQ3T" and op.termicos.size() > 10, "%s %d" % [p.sesion["avion"], op.termicos.size()])
	var H := []
	for o in op.termicos:
		if o["tipo"] == "caliente": H.append([(o["P0"][0] + o["P1"][0]) / 2, (o["P0"][1] + o["P1"][1]) / 2, (o["P0"][2] + o["P1"][2]) / 2])
	var vc = _buscar_vista(H[0], "caliente", [40.0], 4.0)
	if vc == null: vc = _buscar_vista(H[0], "caliente", [40.0], 4.0, true)      # una vista libre a 40 m
	r = _apuntar(H[0], 40, vc[1], 3.2, 1, true, false, vc[0]); _ok("punto caliente a 40 m sin zoom: no se mide", not "Punto caliente" in _texto(r) and r["calientes"] != "ok", _texto(r))      # pide acercarse (o la cruz cae antes en el vapor)
	r = _apuntar(H[0], 40, vc[1], 3.2, 4, true, false, vc[0]); _ok("con 4x de zoom se mide en 3 s", "Punto caliente 1" in _texto(r), _texto(r) + " " + str(r["lectura"]))
	await _captura("sabic_caliente_termica")
	for k in range(1, H.size()):
		var vk = _buscar_vista(H[k], "caliente", [12.0], 1.0)
		if vk == null: vk = _buscar_vista(H[k], "caliente", [12.0], 1.0, true)
		r = _apuntar(H[k], 12, vk[1], 3.2, 1, true, false, vk[0])
	_ok("los 4 puntos calientes medidos", r["calientes"] == "ok", str(r["calientes"]))
	var V: Array = op.valvula
	var vista: Variant = _buscar_vista(V, "fuga", [45.0, 60.0, 75.0, 90.0], 0.0)
	_ok("hay desde donde ver la fuga sin entrar en la ATEX", vista != null, str(vista))
	var atex0 = p.ev.obj["atex"]["estado"]                 # (un punto caliente pegado a la ATEX puede haber obligado a entrar)
	if vista != null:
		r = _apuntar(V, vista[2], vista[1], 3.2, vista[3], true, false, vista[0]); _ok("fuga desde fuera de la zona ATEX con zoom %dx" % int(vista[3]), r["fuga"] == "ok" and (r["atex"] != "mal" or atex0 == "mal"), _texto(r) + " atex " + str(r["atex"]))
		await _captura("sabic_fuga_termica")
	var Pl: Array = op.placa.slice(0, 3); var A: Array = [float(op.d["antorcha"]["n"]), float(op.d["antorcha"]["e"]), float(op.boca[2])]
	var suelo_pl: float = p.ent.altura(float(op.d["antorcha"]["n"]), float(op.d["antorcha"]["e"]))
	var rp: float = float(op.placa[3]) * PI / 180
	r = _apuntar(Pl, 80, 0, 0.1, 28, false, true, rp + PI); _ok("placa desde el otro lado: no se ve", "este lado" in _texto(r), _texto(r))
	r = _apuntar(Pl, 80, 0, 0.1, 14, false, true, rp); _ok("placa con 14x: no se lee", "28x" in _texto(r), _texto(r))
	var dh: float = 75 + suelo_pl - float(Pl[2])
	r = _apuntar(Pl, 80, dh, 0.1, 28, false, true, rp); _ok("placa con 28x desde 80 m y a 75 m de altura", r["placa"] == "ok", _texto(r))
	await _captura("sabic_placa_zoom28")
	r = _apuntar(A, 60, 10, 0.1, 2, false, true); _ok("piloto sin termica: la pide", "térmica" in _texto(r), _texto(r))
	r = _apuntar(A, 60, 10, 0.1, 2, true, true); _ok("piloto con la termica", r["piloto"] == "ok", _texto(r))
	await _captura("sabic_antorcha_termica")
	r = _apuntar(V, 5, 2, 0.2, 1, true, false); _ok("entrar en la zona ATEX se marca", r["atex"] == "mal", str(r["atex"]))
	# teclas: Z / X el zoom, C la termica
	p.pantalla_actual = ""; p.pausado = false; p.DJI["zoomI"] = 0; p.DJI["termica"] = false
	for k in [KEY_Z, KEY_Z, KEY_X, KEY_C]:
		var e := InputEventKey.new(); e.keycode = k; e.physical_keycode = k; e.pressed = true; Input.parse_input_event(e); await process_frame
		e = e.duplicate(); e.pressed = false; Input.parse_input_event(e); await process_frame
	_ok("Z, Z, X dejan el zoom en 2x y C pone la termica", p.cam_dji()["zoom"] == 2.0 and p.cam_dji()["termica"], str(p.cam_dji()))
	print("RESULTADO: ", "todo bien" if fallos == 0 else "%d fallos" % fallos)
	quit(1 if fallos else 0)
