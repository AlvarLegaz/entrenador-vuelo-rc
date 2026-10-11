extends SceneTree
## Mide el coste de un paso de la fisica (ModeloAvion.paso y lo que lo rodea en principal.gd) en GDScript.
func _init() -> void:
	var ent := Entorno.new(); ent.poner_mundo(DatosComunes.mundo("cartagena"))
	var z := DatosComunes.cargar_zona(DatosComunes.indice_zonas()[0]); ent.poner_zona(z)
	ent.configurar_viento(2, 90, true)
	var m := ModeloAvion.new(DatosComunes.avion("E1")); var a := m.estado_inicial(); m.lanzar(a); a["p"] = [0.0, 0.0, -150.0]; a["gases"] = 0.7
	var mm := { "pitch": 0.0, "yaw": 0.0, "trim": 0.0 }
	var n := 5000
	for parte in ["completo", "solo paso", "solo altura", "solo servos", "solo viento"]:
		var t0 := Time.get_ticks_usec()
		for i in n:
			match parte:
				"completo":
					var v := ent.actualizar(0.002); m.servos(a, mm, 0.002)
					a["agl"] = -a["p"][2] - ent.altura(a["p"][0], a["p"][1]); v = ent.viento_a(v, a["agl"]); a["pg"] = ent.rafaga_alabeo(m.b_m, a["agl"])
					m.paso(a, v, 0.002)
				"solo paso": m.paso(a, [0.0, 0.0, 0.0], 0.002)
				"solo altura": ent.altura(a["p"][0], a["p"][1])
				"solo servos": m.servos(a, mm, 0.002)
				"solo viento": ent.actualizar(0.002)
		print("%-12s %.1f us por paso" % [parte, float(Time.get_ticks_usec() - t0) / n])
	quit()
