extends SceneTree
## Prueba de que la fisica de los dos simuladores es la misma, en las dos dificultades (real y facil). pruebas/referencia_js.json son trazas del simulador
## del navegador (modelos.js y entorno.js) en un vuelo de 16 s con mandos, gases y viento variables, para los cuatro
## aviones con sus datos de diseno y con una configuracion distinta (masa, CG, temperatura, empuje, resistencia), y
## alturas del terreno, viento junto al suelo y turbulencia. Aqui se repite lo mismo con ModeloAvion y Entorno.
## Uso (desde la carpeta del repositorio):
##   herramientas/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path simulador_godot --script res://pruebas/prueba_fisica.gd

const DT := 0.002

func _traza(id: String, conf: Dictionary, ent: Entorno, facil := false) -> Array:
	var m := ModeloAvion.new(DatosComunes.avion(id))
	if not conf.is_empty(): m.configurar(conf)
	m.facil = facil; ent.facil = facil
	var a := m.estado_inicial()
	a["asim"] = 0.37; a["p"] = [0.0, 0.0, -80.0]; a["q"] = Cuat.desde_euler(0.05, 0.03, 0.2); a["v"] = [11.0, 0.3, 0.1]
	a["w"] = [0.0, 0.0, 0.0]; a["estado"] = "volando"
	var mm := { "pitch": 0.0, "yaw": 0.0, "trim": m.compensador_grados }
	var out := []
	for i in int(16 / DT) + 1:
		var t := i * DT
		mm["pitch"] = 1.0 if t >= 10 and t < 14 else 0.4 * sin(0.9 * t); mm["yaw"] = 0.6 * sin(1.7 * t)
		a["gases"] = 1.0 if t < 6 else (0.5 if t < 12 else 0.0)
		if i % 500 == 0:
			out.append({ "t": t, "p": a["p"].duplicate(), "v": a["v"].duplicate(), "w": a["w"].duplicate(), "q": a["q"].duplicate(),
						 "de": a["de"], "da": a["da"], "dr": a["dr"], "Wh": a["Wh"], "T": a["T"] })
		m.servos(a, mm, DT)
		a["agl"] = -a["p"][2]; a["pg"] = 0.05 * sin(3 * t)
		m.paso(a, ent.viento_a([2.0, -1.0, 0.2], a["agl"]), DT)
	ent.facil = false
	return out

## Avion de pista (XM-7): lo mismo que pista() de generar_referencia_fisica.py
func _pista(id: String, ent: Entorno) -> Array:
	var m := ModeloAvion.new(DatosComunes.avion(id)); var a := m.estado_inicial(); var out := []
	m.lanzar(a); a["asim"] = 0.37
	var mm := { "pitch": 0.0, "yaw": 0.0, "guinada": 0.0, "trim": m.compensador_grados }
	for i in int(24 / DT) + 1:
		var t := i * DT
		a["gases"] = 0.1 if t < 1 else 1.0; a["freno"] = 1.0 if t < 2 else 0.0
		mm["pitch"] = 0.4 if (t >= 12 and t < 14) else (0.12 if t >= 14 else 0.0); mm["guinada"] = 0.15 * sin(0.6 * t); mm["yaw"] = 0.3 * sin(0.8 * t) if t > 15 else 0.0
		if i % 500 == 0:
			out.append({ "t": t, "p": a["p"].duplicate(), "v": a["v"].duplicate(), "w": a["w"].duplicate(), "q": a["q"].duplicate(),
						 "de": a["de"], "da": a["da"], "dr": a["dr"], "Wh": a["Wh"], "T": a["T"], "tierra": 1 if a["enTierra"] else 0 })
		m.servos(a, mm, DT)
		a["agl"] = -a["p"][2] - 0.02 * sin(0.05 * a["p"][0]); a["pg"] = 0.0
		m.paso(a, ent.viento_a([3.0, 1.0, 0.0], a["agl"]), DT)
		var f := m.fin_tren(a)
		if f != "": out.append({ "fin": f, "t": t }); break
	return out

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
	var ref: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://pruebas/referencia_js.json"))
	var ent := Entorno.new()
	var fallos := 0
	print("Fisica del avion: diferencia maxima con el navegador (posicion m, velocidad m/s, giro rad/s, actitud, mandos rad)")
	for id in ["E3", "T1"]:
		var A := DatosComunes.avion(id)
		var cf := { "masa_kg": A["masa_kg"] * 1.1, "cg_mm": A["cg_mm"][0] + 5, "temperatura": 30.0, "empuje_gf": 800.0, "resistencia": 1.2 }
		var confs := { "normal": {}, "config": cf, "facil": cf }      # facil: la dificultad facil (la fisica de antes)
		for nombre in confs:
			var g := _traza(id, confs[nombre], ent, nombre == "facil"); var r: Array = ref["aviones"][id][nombre]
			var dmax := {}; var t_primer := -1.0
			for k in r.size():
				for c in ["p", "v", "w", "q", "de", "da", "dr", "Wh", "T"]:
					var d := _dif(g[k][c], r[k][c])
					dmax[c] = maxf(dmax.get(c, 0.0), d)
					if d > 1e-6 and t_primer < 0: t_primer = r[k]["t"]
			var ok: bool = dmax["p"] < 1e-3 and dmax["q"] < 1e-6
			if not ok: fallos += 1
			print("  %s %-6s %s  p %s  v %s  w %s  q %s  mandos %s  Wh %s  T %s%s" % [id, nombre, "OK " if ok else "MAL",
				_e(dmax["p"]), _e(dmax["v"]), _e(dmax["w"]), _e(dmax["q"]), _e(maxf(dmax["de"], maxf(dmax["da"], dmax["dr"]))), _e(dmax["Wh"]), _e(dmax["T"]),
				"" if t_primer < 0 else "  (primera diferencia > 1e-6 en t=%.0f s)" % t_primer])
	print("Avion de pista (XM-7): parado, carrera de despegue con la rueda de morro, rotacion y subida")
	var gp := _pista("XM7", ent); var rp: Array = ref["aviones"]["XM7"]["pista"]
	var dpm := 0.0; var dqm := 0.0; var dtierra := 0
	for k in mini(gp.size(), rp.size()):
		if rp[k].has("fin") or gp[k].has("fin"):
			if String(rp[k].get("fin", "")) != String(gp[k].get("fin", "")): dtierra += 1
			continue
		dpm = maxf(dpm, _dif(gp[k]["p"], rp[k]["p"])); dqm = maxf(dqm, _dif(gp[k]["q"], rp[k]["q"]))
		if int(gp[k]["tierra"]) != int(rp[k]["tierra"]): dtierra += 1
	var okp := gp.size() == rp.size() and dpm < 1e-3 and dqm < 1e-6 and dtierra == 0
	if not okp: fallos += 1
	print("  XM7 pista %s  p %s  q %s  (%d muestras, en tierra distinto en %d)" % ["OK " if okp else "MAL", _e(dpm), _e(dqm), gp.size(), dtierra])
	print("Entorno (mundo de Cartagena):")
	ent.poner_mundo(DatosComunes.mundo("cartagena"))
	for caso in ["sinZona", "conZona"]:
		if caso == "conZona":
			var meta := {}
			for z in DatosComunes.indice_zonas():
				if z["id"] == "origen": meta = z
			if meta.is_empty():
				print("  (no esta la zona 'origen' en simulador/zonas: se salta)"); continue
			ent.poner_zona(DatosComunes.cargar_zona(meta))
		var dh := 0.0; var dm := 0
		for p in ref["entorno"][caso]:
			dh = maxf(dh, absf(ent.altura(p[0], p[1]) - p[2]))
			if (1 if ent.en_mar(p[0], p[1]) else 0) != int(p[3]): dm += 1
		var ok := dh < 1e-6 and dm == 0
		if not ok: fallos += 1
		print("  terreno %s: altura %s m, agua distinta en %d puntos  %s" % [caso, _e(dh), dm, "OK" if ok else "MAL"])
	ent.poner_zona({})
	var dv := 0.0
	for f in ref["entorno"]["vientoA"]:
		dv = maxf(dv, _dif(ent.viento_a([4.0, -2.0, 0.5], f[0]), [f[1], f[2], f[3]]))
	ent.configurar_viento(4, 0, true); ent.viento["r"] = [0.0, 0.0, 0.0, 1.0]
	var dr := 0.0
	for f in ref["entorno"]["rafaga"]:
		dr = maxf(dr, absf(ent.rafaga_alabeo(f[0], f[1]) - f[2]))
	ent.facil = true
	for f in ref["entorno"]["vientoA_facil"]:
		dv = maxf(dv, _dif(ent.viento_a([4.0, -2.0, 0.5], f[0]), [f[1], f[2], f[3]]))
	for f in ref["entorno"]["rafaga_facil"]:
		dr = maxf(dr, absf(ent.rafaga_alabeo(f[0], f[1]) - f[2]))
	ent.facil = false
	if dv > 1e-9 or dr > 1e-9: fallos += 1
	print("  viento junto al suelo %s m/s, turbulencia de alabeo %s rad/s  %s" % [_e(dv), _e(dr), "OK" if dv <= 1e-9 and dr <= 1e-9 else "MAL"])
	print("RESULTADO: " + ("todo igual" if fallos == 0 else "%d casos distintos" % fallos))
	quit(1 if fallos else 0)
