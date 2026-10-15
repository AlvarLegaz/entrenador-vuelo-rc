extends SceneTree
## Prueba de que el piloto automatico del UAV (scripts/piloto_uav.gd) es el mismo que el del navegador
## (simulador/js/piloto_uav.js): repite el vuelo de pruebas/referencia_piloto_uav_js.json (generar_referencia_piloto_uav.py)
## con la fisica de modelo_avion.gd y compara posiciones, actitud, modos y fases y el final.
## Uso (desde la carpeta del repositorio):
##   herramientas/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path simulador_godot --script res://pruebas/prueba_piloto_uav.gd

const DT := 0.002
const D2R := PI / 180.0

func _init() -> void:
	var ref: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://pruebas/referencia_piloto_uav_js.json"))
	var m := ModeloAvion.new(DatosComunes.avion("XM7")); var a := m.estado_inicial(); var out := []; var cambios := []
	var pista := { "n": 0.0, "e": 0.0, "rumbo": 30.0, "largo": 2300.0, "h": 5.0 }
	var ap := PilotoUAV.new(m.datos["piloto"], pista, [0.0, 0.0, 5.0])
	a["p"] = [0.0, 0.0, -(5 + m.altura_en_tierra())]; a["q"] = Cuat.desde_euler(0, 0, 30 * D2R); m.lanzar(a); a["asim"] = 0.37
	var mm := { "pitch": 0.0, "yaw": 0.0, "guinada": 0.0, "trim": 0.0 }
	var poner := func(t: float, modo: String, punto = null) -> void: cambios.append([snappedf(t, 0.001), modo, ap.poner(modo, a, punto)])
	poner.call(0.0, "DESPEGUE")
	var fin := ""
	for i in int(760 / DT):
		var t := i * DT
		if i == int(45 / DT): poner.call(t, "ESTAB")
		if i == int(60 / DT): poner.call(t, "CRUCERO")
		if i == int(120 / DT): poner.call(t, "PUNTO", [2500.0, 1800.0])
		if i == int(220 / DT): poner.call(t, "ATERRIZAJE")
		var pal := { "pitch": 0.3 if (t > 45 and t < 52) else (0.5 if (t > 70 and t < 80) else 0.0), "yaw": 0.4 if (t > 45 and t < 53) else (-0.6 if (t > 85 and t < 95) else 0.0), "guinada": 0.0 }
		a["agl"] = -a["p"][2] - 5
		var o := ap.paso(a, DT, pal, 0.4 if t < 100 else 0.6)
		mm["pitch"] = o["pitch"]; mm["yaw"] = o["yaw"]; mm["guinada"] = o["guinada"]
		a["gases"] = o["gas"] if o["gas"] != null else 0.6
		if o["freno"] != null: a["freno"] = o["freno"]
		if i % 1000 == 0: out.append({ "t": t, "p": a["p"].duplicate(), "q": a["q"].duplicate(), "modo": ap.modo, "fase": ap.fase })
		m.servos(a, mm, DT)
		m.paso(a, [2.0, -1.0, 0.0], DT)
		var f := m.fin_tren(a)
		if f != "": fin = f; out.append({ "t": t, "fin": f, "p": a["p"].duplicate() }); break
	var R: Array = ref["muestras"]; var dp := 0.0; var dq := 0.0; var dmodo := 0; var primer := -1.0
	for k in mini(out.size(), R.size()):
		if R[k].has("fin") or out[k].has("fin"): continue
		for j in 3: dp = maxf(dp, absf(float(out[k]["p"][j]) - float(R[k]["p"][j])))
		for j in 4: dq = maxf(dq, absf(float(out[k]["q"][j]) - float(R[k]["q"][j])))
		if out[k]["modo"] != R[k]["modo"] or out[k]["fase"] != R[k]["fase"]: dmodo += 1
		if dp > 1e-3 and primer < 0: primer = R[k]["t"]
	var cam_ok := cambios.size() == (ref["cambios"] as Array).size()
	for k in mini(cambios.size(), (ref["cambios"] as Array).size()):
		if String(cambios[k][2]) != String(ref["cambios"][k][2]): cam_ok = false
	var ok := out.size() == R.size() and dp < 0.05 and dq < 1e-4 and dmodo == 0 and fin == String(ref["fin"]) and cam_ok
	print("Piloto automatico del UAV: %d muestras (navegador %d), final '%s' ('%s'), posicion %.6f m, actitud %.8f, modos o fases distintos %d%s" % [
		out.size(), R.size(), fin, ref["fin"], dp, dq, dmodo, "" if primer < 0 else " (primera diferencia > 1 mm en t=%.0f s)" % primer])
	print("  final en N %.1f E %.1f (navegador N %.1f E %.1f)" % [out[-1]["p"][0], out[-1]["p"][1], R[-1]["p"][0], R[-1]["p"][1]])
	print("RESULTADO: " + ("todo igual" if ok else "DISTINTO"))
	quit(0 if ok else 1)
