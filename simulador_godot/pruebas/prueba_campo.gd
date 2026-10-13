extends SceneTree
## Prueba de que la isla del campo de vuelo (Entorno sin mundo real, ContadorVueltas y PasadaBaja) es la misma en los dos
## simuladores. pruebas/referencia_campo_js.json son casos calculados con el Entorno del navegador (simulador/js/entorno.js)
## por pruebas/generar_referencia_campo.py: contacto con el suelo, una trayectoria por el circuito con tres contadores de
## vueltas, pasadas por la pista 2, cruces de la puerta, diana, en_pista, choca_pilon, distancia y fuera_de_limites.
## Uso (desde la carpeta del repositorio):
##   herramientas/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path simulador_godot --script res://pruebas/prueba_campo.gd

const TOL := 1e-9
var fallos := 0

## Igualdad de valores JSON del navegador (null, numeros, textos, listas, diccionarios) con los de Godot ({} = null).
func _igual(g, j) -> bool:
	if j == null: return g == null or (g is Dictionary and g.is_empty()) or (g is String and g == "")
	if j is bool: return g is bool and g == j
	if j is float or j is int:
		return (g is float or g is int) and absf(float(g) - float(j)) <= TOL * maxf(1.0, absf(float(j)))
	if j is String: return g is String and g == j
	if j is Array:
		if not (g is Array) or g.size() != j.size(): return false
		for k in j.size():
			if not _igual(g[k], j[k]): return false
		return true
	if j is Dictionary:
		if not (g is Dictionary) or g.size() != j.size(): return false
		for k in j:
			if not g.has(k) or not _igual(g[k], j[k]): return false
		return true
	return false

func _linea(nombre: String, distintos: int, total: int, detalle := "") -> void:
	if distintos: fallos += 1
	print("  %-34s %s  (%d casos%s)%s" % [nombre, "OK " if distintos == 0 else "MAL", total,
		"" if distintos == 0 else ", %d distintos" % distintos, detalle])

func _contacto(ent: Entorno, entrada: Array, ref: Array) -> int:
	var dist := 0
	for k in entrada.size():
		var c: Dictionary = entrada[k]; var r: Dictionary = ref[k]
		var q := Cuat.desde_euler(c["e"][0], c["e"][1], c["e"][2])
		var av := { "p": (c["p"] as Array).duplicate(), "q": q }
		var res := ent.contacto_suelo(av, c["vn"])
		if not (_igual(q, r["q"]) and _igual(res, r["res"]) and _igual(av["p"], r["p"])):
			dist += 1
			if dist <= 3: print("    contacto %d: Godot %s %s, navegador %s %s" % [k, res, av["p"], r["res"], r["p"]])
	return dist

func _init() -> void:
	var todo: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://pruebas/referencia_campo_js.json"))
	var d: Dictionary = todo["entrada"]; var js: Dictionary = todo["js"]
	var ent := Entorno.new()
	print("Isla del campo de vuelo: Godot (entorno.gd, contador_vueltas.gd, pasada_baja.gd) frente al navegador (entorno.js)")
	var nd := 0
	for k in js["datos"]:
		if not _igual(ent.get(k), js["datos"][k]):
			nd += 1; print("    dato distinto: ent.%s = %s; navegador %s" % [k, ent.get(k), js["datos"][k]])
	_linea("datos (pista, circuito, pilon, zona2, limites)", nd, js["datos"].size())

	_linea("contacto_suelo", _contacto(ent, d["contacto"], js["contacto"]), d["contacto"].size())
	if js["contactoTrasMundo"] != null:
		ent.poner_mundo(DatosComunes.mundo("cartagena"))
		var df := 0; var dc := 0
		for k in d["fuera"].size():
			if ent.fuera_de_limites(d["fuera"][k]) != js["fueraEnMundo"][k]: df += 1
		for k in d["choca"].size():
			if ent.choca_pilon(d["choca"][k][0], d["choca"][k][1]) != js["chocaEnMundo"][k]: dc += 1
		_linea("en Cartagena: sin limites ni pilones", df + dc, d["fuera"].size() + d["choca"].size())
		ent.poner_mundo({})
		_linea("contacto_suelo tras volver a la isla", _contacto(ent, d["contacto"], js["contactoTrasMundo"]), d["contacto"].size())

	var P: Array = d["circuito"]
	for s in [0, 1, -1]:
		var cv := ent.contador_vueltas(s); var ev := []
		for k in range(1, P.size()):
			var e := cv.actualizar([P[k - 1][1], P[k - 1][2], -50.0], [P[k][1], P[k][2], -50.0], P[k][0])
			if not e.is_empty(): ev.append({ "k": k, "e": e, "sig": cv.siguiente() })
		var r: Dictionary = js["circuito"][str(s)]
		var dist := 0; var n: int = maxi(ev.size(), r["eventos"].size())
		for k in n:
			if k >= ev.size() or k >= r["eventos"].size() or not _igual(ev[k], r["eventos"][k]):
				dist += 1
				if dist <= 3: print("    suceso %d: Godot %s, navegador %s" % [k, ev[k] if k < ev.size() else "-", r["eventos"][k] if k < r["eventos"].size() else "-"])
		for c in ["vueltas", "mejor", "ultima"]:
			if not _igual(cv.get(c), r[c]):
				dist += 1; print("    %s: Godot %s, navegador %s" % [c, cv.get(c), r[c]])
		if not _igual(cv.siguiente(), r["siguiente"]): dist += 1
		var tipos := {}
		for x in ev: tipos[x["e"]["tipo"]] = true
		_linea("ContadorVueltas sentido %+d" % s if s else "ContadorVueltas sentido libre", dist, r["eventos"].size(),
			"  %d vueltas, mejor %.2f s, sucesos %s" % [cv.vueltas, cv.mejor if cv.mejor != null else -1.0, ", ".join(PackedStringArray(tipos.keys()))])

	var pb := ent.pasada_baja(); var pas := []
	for k in d["pasadas"].size():
		var e := pb.actualizar(d["pasadas"][k])
		if not e.is_empty(): pas.append({ "k": k, "e": e })
	var dp := 0 if _igual(pas, js["pasadas"]["resultados"]) and pb.validas == js["pasadas"]["validas"] else 1
	if dp: print("    Godot %s\n    navegador %s" % [pas, js["pasadas"]["resultados"]])
	_linea("PasadaBaja", dp, js["pasadas"]["resultados"].size(), "  %d validas" % pb.validas)

	var dist := 0
	for k in d["puerta"].size():
		if not _igual(ent.cruza_puerta(d["puerta"][k][0], d["puerta"][k][1]), js["puerta"][k]):
			dist += 1
			if dist <= 3: print("    puerta %d: Godot %s, navegador %s" % [k, ent.cruza_puerta(d["puerta"][k][0], d["puerta"][k][1]), js["puerta"][k]])
	_linea("cruza_puerta", dist, d["puerta"].size())
	dist = 0
	for k in d["diana"].size():
		if not _igual(ent.diana(d["diana"][k][0], d["diana"][k][1]), js["diana"][k]): dist += 1
	_linea("diana", dist, d["diana"].size())
	dist = 0
	for k in d["en_pista"].size():
		var c: Array = d["en_pista"][k]
		var g := ent.en_pista(c[0], c[1]) if c[2] == null else ent.en_pista(c[0], c[1], c[2])
		if g != js["en_pista"][k]: dist += 1
	_linea("en_pista", dist, d["en_pista"].size())
	dist = 0
	for k in d["choca"].size():
		if ent.choca_pilon(d["choca"][k][0], d["choca"][k][1]) != js["choca"][k]: dist += 1
	_linea("choca_pilon", dist, d["choca"].size())
	dist = 0
	for k in d["fuera"].size():
		if not _igual([ent.distancia(d["fuera"][k]), ent.fuera_de_limites(d["fuera"][k])], js["fuera"][k]): dist += 1
	_linea("distancia y fuera_de_limites", dist, d["fuera"].size())
	dist = 0
	for k in 3:
		if ent.orden_pilones([-1, 0, 1][k]) != js["orden"][k]: dist += 1
	_linea("orden_pilones", dist, 3, "  \"%s\"" % ent.orden_pilones(1))
	# generadores del decorado (Campo3D frente a visor.js) y la lista de almendros del pintado del suelo
	var D: Dictionary = d["decor"]; var J: Dictionary = js["decor"]
	var s23 := Campo3D.Semilla.new(23); var g_sem := []
	for i in J["semilla"].size(): g_sem.append(s23.r())
	_linea("semilla (mulberry32)", 0 if _igual(g_sem, J["semilla"]) else 1, J["semilla"].size())
	var dist2 := 0
	for k in D["pts"].size():
		var x: float = D["pts"][k][0]; var y: float = D["pts"][k][1]
		if not _igual(Campo3D.ruido(x, y), J["ruido"][k]) or not _igual(Campo3D.fbm(x / 37, y / 41), J["fbm"][k]): dist2 += 1
	_linea("ruido y fbm", dist2, D["pts"].size())
	dist2 = 0
	for k in D["th"].size():
		if not _igual(Campo3D.costa(D["th"][k]), J["costa"][k]): dist2 += 1
	for k in D["en"].size():
		if not _igual(Campo3D.altura_terreno(D["en"][k][0], D["en"][k][1]), J["altura"][k]): dist2 += 1
	for k in D["n"].size():
		if not _igual(Campo3D.borde_monte(D["n"][k]), J["borde"][k]): dist2 += 1
	_linea("costa, altura_terreno, borde_monte", dist2, D["th"].size() + D["en"].size() + D["n"].size())
	var t0 := Time.get_ticks_msec(); var arb := []
	Campo3D.trazos_campo(ent.zona2, arb)
	var JA: Dictionary = J["arboles"]; var suma := 0.0; var muestra := []
	for i in arb.size():
		suma += arb[i][0] + 2 * arb[i][1] + 3 * arb[i][2]
		if i % 97 == 0 or i == arb.size() - 1: muestra.append(arb[i])
	var da := 0 if arb.size() == int(JA["n"]) and _igual(muestra, JA["muestra"]) and absf(suma - JA["suma"]) < 1e-6 * absf(suma) else 1
	_linea("almendros del pintado del suelo", da, int(JA["n"]), "  %d almendros (%d ms)" % [arb.size(), Time.get_ticks_msec() - t0])
	# Campo3D se construye tambien sin GPU (--headless): el suelo se queda de color tierra
	var campo := Campo3D.new(); campo.calidad = 1; root.add_child(campo); campo.construir(ent)
	campo.poner_base(0, 0); ent.configurar_viento(5, 90, false); campo.actualizar_manga(ent.actualizar(0.01))
	var ok_c := campo.get_child_count() > 50 and campo.arboles().size() == arb.size() and campo.base == Vector3.ZERO
	_linea("Campo3D.construir (sin pintar el suelo)", 0 if ok_c else 1, 1, "  %d nodos" % campo.get_child_count())
	print("RESULTADO: " + ("todo igual" if fallos == 0 else "%d pruebas distintas" % fallos))
	campo.queue_free()
	for i in 3: await process_frame
	quit(1 if fallos else 0)
