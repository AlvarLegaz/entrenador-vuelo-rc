extends SceneTree
## Fisica del Poli-1 (4 canales) igual que en el navegador: la misma traza de 16 s que prueba_fisica.gd con el timon movido
## por mando.guinada (referencia: pruebas/referencia_g1_js.json, de generar_referencia_g1.py).
## Uso: herramientas/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path simulador_godot --script res://pruebas/prueba_g1.gd

const DT := 0.002

func _e(x: float) -> String:
	if x == 0: return "0"
	var ex := floori(log(x) / log(10.0))
	return "%.1fe%d" % [x / pow(10, ex), ex]

func _dif(x, y) -> float:
	if x is Array:
		var d := 0.0
		for k in x.size(): d = maxf(d, absf(float(x[k]) - float(y[k])))
		return d
	return absf(float(x) - float(y))

func _init() -> void:
	var ref: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://pruebas/referencia_g1_js.json"))
	var A := DatosComunes.avion("G1"); var fallos := 0
	var cf := { "masa_kg": A["masa_kg"] * 1.1, "cg_mm": A["cg_mm"][0] + 5, "temperatura": 30.0, "empuje_gf": 800.0, "resistencia": 1.2 }
	for caso in [["normal", {}, false], ["config", cf, false], ["facil", cf, true]]:
		var ent := Entorno.new(); var m := ModeloAvion.new(A)
		if m.tipo != "cuatro": print("  el Poli-1 no es de 4 canales en modelo_avion.gd (tipo %s)" % m.tipo); quit(1); return
		if not (caso[1] as Dictionary).is_empty(): m.configurar(caso[1])
		m.facil = caso[2]; ent.facil = caso[2]
		var a := m.estado_inicial()
		a["asim"] = 0.37; a["p"] = [0.0, 0.0, -80.0]; a["q"] = Cuat.desde_euler(0.05, 0.03, 0.2); a["v"] = [11.0, 0.3, 0.1]; a["w"] = [0.0, 0.0, 0.0]; a["estado"] = "volando"
		var mm := { "pitch": 0.0, "yaw": 0.0, "guinada": 0.0, "trim": m.compensador_grados }
		var r: Array = ref[caso[0]]; var dmax := {}; var k := 0
		for i in int(16 / DT) + 1:
			var t := i * DT
			mm["pitch"] = 1.0 if t >= 10 and t < 14 else 0.4 * sin(0.9 * t); mm["yaw"] = 0.6 * sin(1.7 * t); mm["guinada"] = 0.5 * sin(1.3 * t + 0.4)
			a["gases"] = 1.0 if t < 6 else (0.5 if t < 12 else 0.0)
			if i % 500 == 0:
				for c in ["p", "v", "w", "q", "de", "da", "dr", "Wh", "T"]: dmax[c] = maxf(dmax.get(c, 0.0), _dif(a[c], r[k][c]))
				k += 1
			m.servos(a, mm, DT)
			a["agl"] = -a["p"][2]; a["pg"] = 0.05 * sin(3 * t)
			m.paso(a, ent.viento_a([2.0, -1.0, 0.2], a["agl"]), DT)
		var ok: bool = dmax["p"] < 1e-3 and dmax["q"] < 1e-6 and dmax["dr"] < 1e-9
		if not ok: fallos += 1
		print("  G1 %-6s %s  p %s  v %s  w %s  q %s  timon %s  alerones %s" % [caso[0], "OK " if ok else "MAL", _e(dmax["p"]), _e(dmax["v"]), _e(dmax["w"]), _e(dmax["q"]), _e(dmax["dr"]), _e(dmax["da"])])
	print("RESULTADO: " + ("todo igual" if fallos == 0 else "%d casos distintos" % fallos))
	quit(1 if fallos else 0)
