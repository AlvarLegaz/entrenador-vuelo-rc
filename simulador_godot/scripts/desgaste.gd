class_name Desgaste
## Desgaste y averias de los vehiculos: traduccion LITERAL de simulador_web/js/desgaste.js (los mismos datos, el mismo azar
## y los mismos efectos, para que los dos simuladores vuelen igual; simulador_godot/Tests/prueba_averias.gd lo compara). Cada vehiculo
## de cada alumno lleva su estado (en el aula y, sin conexion, en user://vehiculos.json): horas de vuelo, horas de cada
## componente, salud y ciclos de la bateria, averias y libro de mantenimiento. La primera hora de vuelo del vehiculo no
## pasa nada; despues, cada vuelo puede estropear algo (mas cuanto mas usado esta), y tambien un golpe, una descarga por
## debajo del 10 % o calentar la bateria. El profesor puede poner averias (en vuelo, solo en una sala de multijugador).
## Nada se bloquea: se vuela con la averia, con los avisos de la app y los sintomas; en el Taller se inspecciona y se repara.

const D2R := PI / 180.0
const G0 := 9.81
const HORAS_SIN_AVERIAS := 1.0
## motores del cuadricoptero: 1 delantero derecho, 2 delantero izquierdo, 3 trasero izquierdo, 4 trasero derecho;
## [x (+ delante), y (+ derecha), giro (+1 horario visto desde arriba)]
const MOTORES := [[1, 1, -1], [1, -1, 1], [-1, -1, -1], [-1, 1, 1]]
const NOMBRE_MOTOR := ["delantero derecho", "delantero izquierdo", "trasero izquierdo", "trasero derecho"]
const NOMBRE_HELICE := ["delantera derecha", "delantera izquierda", "trasera izquierda", "trasera derecha"]
const SUPERFICIES := { "alerones": "los alerones", "profundidad": "la profundidad", "timon": "el timón", "elevon_izq": "el elevón izquierdo", "elevon_der": "el elevón derecho" }
const CLAVE_SUP := { "alerones": "da", "profundidad": "de", "timon": "dr", "elevon_izq": "elevon_izq", "elevon_der": "elevon_der" }
const TASAS := { "helice": [0.06, 1], "motor": [0.02, 1], "servo": [0.04, 1], "bisagra": [0.03, 1], "celda": [0.02, 1], "brujula": [0.05, 0], "imu": [0.03, 0], "gps": [0.02, 0], "barometro": [0.02, 0] }
const VIB := { "cuad": 45.0, "fpv": 250.0, "avion": 120.0, "comb": 120.0, "uav": 120.0 }
const MONTAJE := { "ala": ["el ala", "Ala"], "cola": ["la cola", "Cola (botalón y estabilizador)"], "morro": ["el morro de cámaras", "Morro de cámaras"] }
const SUELTA_TOMA := [["montaje_ala", 0.35], ["montaje_cola", 0.3], ["montaje_morro", 0.15]]     # probabilidad de soltarse en la toma en perdida
const TIPO_FAMILIA := { "helice": "mella", "motor": "rodamiento", "brujula": "descalibrada", "imu": "descalibrada", "gps": "antena", "barometro": "deriva", "servo": "holgura", "bisagra": "floja", "montaje": "suelto" }
const DESEQ := [0, -0.006, 0.003, -0.004, 0.005, -0.002]
const F_LOCAL := "user://vehiculos.json"

## Clase del vehiculo: "cuad", "fpv", "avion" (electrico), "comb" (de combustion) o "" (el bipode no tiene).
static func clase(A: Dictionary) -> String:
	if A.is_empty() or A.get("tipo", "") == "bipode": return ""
	if A.get("tipo", "") == "cuadricoptero": return "cuad"
	if A.get("tipo", "") == "fpv": return "fpv"
	if A.get("uav", false) and A.get("lanzado_a_mano", false): return "uav"
	return "comb" if A.get("propulsion", {}).get("combustible", false) else "avion"

## Superficies de mando de un avion (las que tienen servo y bisagra).
static func superficies(A: Dictionary) -> Array:
	var m: Dictionary = A.get("mandos", {}); var s := []
	if m.get("elevon_max_grados", 0): s.append_array(["elevon_izq", "elevon_der"])
	else:
		if float(m.get("aleron_max_grados", 0)) > 0: s.append("alerones")
		if float(m.get("prof_max_grados", 0)) > 0: s.append("profundidad")
	if float(m.get("timon_max_grados", 0)) > 0: s.append("timon")
	return s

static func _sin_articulo(t: String) -> String:
	for a in ["los ", "la ", "el "]:
		if t.begins_with(a): return t.substr(a.length())
	return t

## "de los alerones", "de la profundidad", "del timon".
static func de(t: String) -> String: return "del " + t.substr(3) if t.begins_with("el ") else "de " + t

static func _minus1(t: String) -> String: return t.substr(0, 1).to_lower() + t.substr(1)

## Componentes del vehiculo: [id, nombre].
static func componentes(A: Dictionary) -> Array:
	var k := clase(A); var c := []
	if k == "": return c
	if k == "cuad" or k == "fpv":
		for i in range(1, 5): c.append(["helice%d" % i, "Hélice %d (%s)" % [i, NOMBRE_HELICE[i - 1]]])
		for i in range(1, 5): c.append(["motor%d" % i, "Motor %d (%s)" % [i, NOMBRE_MOTOR[i - 1]]])
	else: c.append_array([["helice", "Hélice"], ["motor", "Motor"]])
	if k != "comb": c.append(["bateria", "Batería"])
	if k == "cuad" or k == "uav": c.append_array([["brujula", "Brújula"], ["imu", "IMU"], ["gps", "GPS"], ["barometro", "Barómetro"]])
	if k == "uav":
		for m in MONTAJE: c.append(["montaje_" + m, MONTAJE[m][1] + " (montaje)"])
	for s in superficies(A if k == "avion" or k == "comb" or k == "uav" else {}):
		c.append(["servo_" + s, "Servo " + de(SUPERFICIES[s])]); c.append(["bisagra_" + s, "Bisagra " + de(SUPERFICIES[s])])
	return c

static func nuevo() -> Dictionary: return { "version": 0, "horas": 0.0, "h": {}, "bateria": { "salud": 1.0, "ciclos": 0 }, "averias": [], "libro": [] }

## Familia de una averia (la del componente).
static func familia(c: String) -> String:
	var r := RegEx.create_from_string("\\d+$"); var f := r.sub(c, "")
	var i := f.find("_")
	return f if i < 0 else f.substr(0, i)

static func _num(c: String) -> String: return RegEx.create_from_string("\\D").sub(c, "", true)
static func _sup(c: String) -> String: return RegEx.create_from_string("^[a-z]+_").sub(c, "")

## Nombre de una averia (para el profesor y el libro de mantenimiento).
static func nombre(a: Dictionary) -> String:
	var c: String = a["c"]; var f := familia(c); var n := _num(c); var s := _sup(c)
	if f == "helice": return "Hélice %s dañada" % n if n != "" else "Hélice dañada"
	if f == "motor": return "Rodamiento del motor %s gastado" % n if n != "" else "Rodamiento del motor gastado"
	if f == "bateria": return "Batería hinchada" if a["tipo"] == "hinchada" else ("Celda %d de la batería débil" % (int(a.get("n", 0)) + 1) if a["tipo"] == "celda" else "Batería envejecida")
	if f == "brujula": return "Brújula descalibrada"
	if f == "imu": return "IMU descalibrada"
	if f == "gps": return "Antena del GPS dañada"
	if f == "barometro": return "Barómetro con deriva"
	if f == "servo": return "Holgura en el servo " + de(SUPERFICIES.get(s, s))
	if f == "bisagra": return "Bisagra floja en " + SUPERFICIES.get(s, s)
	if f == "montaje": return MONTAJE.get(s, [s, s])[1] + " sin asegurar (se soltó)"
	return c

## Las averias que se pueden poner: [{c, tipo, n?, nombre}].
static func posibles(A: Dictionary) -> Array:
	var L := []
	for cc in componentes(A):
		var c: String = cc[0]; var f := familia(c)
		if f == "bateria":
			L.append({ "c": c, "tipo": "envejecida" })
			var B := Bateria.datos(A.get("propulsion", {}))
			for i in int(B["celdas"]): L.append({ "c": c, "tipo": "celda", "n": i })
			L.append({ "c": c, "tipo": "hinchada" })
		else: L.append({ "c": c, "tipo": TIPO_FAMILIA[f] })
	for a in L: a["nombre"] = nombre(a)
	return L

static func _igual(x: Dictionary, a: Dictionary) -> bool:
	return x["c"] == a["c"] and x["tipo"] == a["tipo"] and int(x.get("n", 0)) == int(a.get("n", 0))

## Anade una averia (si no esta ya) con su origen.
static func anadir(est: Dictionary, a: Dictionary, origen: String, fecha: String):
	for x in est["averias"]:
		if _igual(x, a): return null
	var x := { "c": a["c"], "tipo": a["tipo"], "origen": origen, "fecha": fecha }
	if a.has("n"): x["n"] = int(a["n"])
	est["averias"].append(x)
	if a["c"] == "bateria" and a["tipo"] == "envejecida": est["bateria"]["salud"] = minf(float(est["bateria"]["salud"]), 0.78)
	if a["c"] == "bateria" and a["tipo"] == "hinchada": est["bateria"]["salud"] = minf(float(est["bateria"]["salud"]), 0.6)
	return x

# ---------------------------------------------------------------- efectos en el vuelo
## Pone en el modelo (recien creado y configurado) los efectos de las averias y de la salud de la bateria.
static func aplicar(m, est) -> void:
	m.averias = est["averias"] if est != null else []; m.sens = null; m.kT = null; m.kP = null; m.k_emp = 1.0; m.k_pot = 1.0; m._est = est
	m.efe = { "vib": 0.0, "par": [0.0, 0.0, 0.0], "sup": {}, "clase": clase(m.datos) }
	if est == null: return
	var E: Dictionary = m.efe; var k: String = E["clase"]; var B = m.B
	if B is Dictionary and not B.is_empty():
		if m._Bbase == null: m._Bbase = { "cap": B["capacidad_mAh"], "R": B["R_ohm"] }
		var s: float = est["bateria"]["salud"]
		for a in est["averias"]:
			if a["c"] == "bateria" and a["tipo"] == "hinchada": s = minf(s, 0.6)
		B["capacidad_mAh"] = m._Bbase["cap"]; B["R_ohm"] = m._Bbase["R"]; B.erase("debil")
		if s < 1:
			B["capacidad_mAh"] *= s; B["R_ohm"] *= 1 + 3 * (1 - s)
	for a in est["averias"]:
		var f := familia(a["c"]); var n := _num(a["c"]); var i: int = (int(n) if n != "" else 1) - 1
		if f == "bateria" and a["tipo"] == "celda" and B is Dictionary and not B.is_empty(): B["debil"] = { "i": mini(int(a.get("n", 0)), int(B["celdas"]) - 1), "k": 0.75 }
		if f == "helice" or f == "motor":
			var h := f == "helice"
			E["vib"] += 1.0 if h else 0.4
			if k == "fpv":
				if m.kT == null: m.kT = [1.0, 1.0, 1.0, 1.0]
				if m.kP == null: m.kP = [1.0, 1.0, 1.0, 1.0]
				m.kT[i] *= 0.75 if h else 0.93; m.kP[i] *= 1.1 if h else 1.15
			elif k == "cuad":
				m.k_emp *= 0.95 if h else 0.98; m.k_pot *= 1.06 if h else 1.08
				if h:
					var M: Array = MOTORES[i]; var t: float = m.fc["tau_max"]; var tg: float = m.fc["tau_guinada"]
					E["par"][0] += 0.01 * M[1] * t; E["par"][1] -= 0.01 * M[0] * t; E["par"][2] -= 0.05 * M[2] * tg
			else:
				m.k_emp *= 0.85 if h else 0.95; m.k_pot *= 1.05 if h else 1.12
		if f == "montaje":                         # montaje sin asegurar (el Grajo)
			var sm := _sup(a["c"])
			if sm == "ala": E["alaSuelta"] = true
			if sm == "morro": E["sinVideo"] = true
			if sm == "cola":
				if not E["sup"].has("de"): E["sup"]["de"] = { "h": 0.0, "ef": 1.0, "fl": 0.0 }
				var Pc: Dictionary = E["sup"]["de"]; Pc["ef"] = minf(Pc["ef"], 0.5); Pc["fl"] = maxf(Pc["fl"], 2.5 * D2R); Pc["h"] = maxf(Pc["h"], 2 * D2R)
		if (k == "cuad" or k == "uav") and f in ["brujula", "imu", "gps", "barometro"]:
			if m.sens == null: m.sens = { "rumbo": 0.0, "alabeo": 0.0, "cabeceo": 0.0, "gps": 0.0, "vz": 0.0 }
			if f == "brujula": m.sens["rumbo"] = 50 * D2R
			if f == "imu": m.sens["alabeo"] = 3 * D2R; m.sens["cabeceo"] = -2 * D2R
			if f == "gps": m.sens["gps"] = 3.5
			if f == "barometro": m.sens["vz"] = 0.15
		if f == "servo" or f == "bisagra":
			var key: String = CLAVE_SUP.get(_sup(a["c"]), "")
			if key == "": continue
			if not E["sup"].has(key): E["sup"][key] = { "h": 0.0, "ef": 1.0, "fl": 0.0 }
			var P: Dictionary = E["sup"][key]
			if f == "servo": P["h"] = 3 * D2R
			else:
				P["ef"] = 0.6; P["fl"] = 1.2 * D2R

## Una averia que llega en vuelo (sala multijugador): se suma a las del modelo y se vuelven a poner sus efectos.
static func en_vuelo(m, a: Dictionary) -> void:
	var est: Dictionary = m._est if m._est != null else nuevo()
	var e2 := est.duplicate(); e2["averias"] = (m.averias as Array) + [a]; e2["bateria"] = (est["bateria"] as Dictionary).duplicate()
	if a["c"] == "bateria" and a["tipo"] == "envejecida": e2["bateria"]["salud"] = minf(float(e2["bateria"]["salud"]), 0.78)
	aplicar(m, e2)

## La averia que pide el profesor en los componentes de este vehiculo (la misma o la primera de su familia), o null.
static func adaptar(A: Dictionary, a: Dictionary):
	var P := posibles(A); var x = null
	for y in P:
		if _igual(y, a): x = y; break
	if x == null:
		for y in P:
			if familia(y["c"]) == familia(a["c"]) and y["tipo"] == a["tipo"] and int(y.get("n", 0)) == int(a.get("n", 0)): x = y; break
	if x == null: return null
	var r := { "c": x["c"], "tipo": x["tipo"] }
	if x.has("n"): r["n"] = x["n"]
	return r

## Antes de modelo.paso: la superficie que de verdad mueve el aire (holgura del servo, bisagra floja). Se deshace despues.
static func antes_paso(m, av: Dictionary) -> void:
	if m.get("efe") == null or m.efe.is_empty(): return
	var S: Dictionary = m.efe["sup"]
	if S.is_empty(): return
	av["_sup"] = { "de": av.get("de", 0.0), "da": av.get("da", 0.0), "dr": av.get("dr", 0.0) }
	if not av.has("_holg"): av["_holg"] = {}
	var ho: Dictionary = av["_holg"]; var t: float = av.get("t", 0.0); var fl := minf(1.0, float(av.get("V", 0.0)) / 10)
	var elev := false
	for k in S:
		var P: Dictionary = S[k]; var x: float = av.get(k, 0.0)
		if not av["_sup"].has(k): av["_sup"][k] = x
		var y: float = ho.get(k, x)
		if x - y > P["h"]: y = x - P["h"]
		elif y - x > P["h"]: y = x + P["h"]
		ho[k] = y
		av[k] = y * P["ef"] + P["fl"] * fl * sin(2 * PI * 6.7 * t + String(k).length())
		if String(k).begins_with("elevon"): elev = true
	if elev:
		av["de"] = 0.5 * (av["elevon_izq"] + av["elevon_der"]); av["da"] = 0.5 * (av["elevon_izq"] - av["elevon_der"])

## Despues de modelo.paso: las superficies como estaban; vibracion y par de la helice danada.
static func despues_paso(m, av: Dictionary, dt: float) -> void:
	if av.get("_sup") != null:
		for k in av["_sup"]: av[k] = av["_sup"][k]
		av["_sup"] = null
	if m.get("efe") == null or m.efe.is_empty(): return
	var E: Dictionary = m.efe
	if av["estado"] != "volando" or av.get("posado", false) or av.get("armado", true) == false: return
	if E.get("alaSuelta", false) and float(av.get("g_carga", 1.0)) > 1.6 and not av.has("roturaMontaje"): av["roturaMontaje"] = "se ha soltado el ala en vuelo: no estaba asegurada"
	var t: float = av["t"]; var g := clampf(float(av.get("gases", 0.0)), 0.0, 1.0); var w: Array = av["w"]; var I: Dictionary = m.inercia
	if E["vib"]:
		var A: float = E["vib"] * VIB[E["clase"]] * g
		w[0] += A * (0.6 * sin(TAU * 11.3 * t) + 0.4 * sin(TAU * 17.9 * t + 1.1)) * dt
		w[1] += A * (0.6 * sin(TAU * 12.7 * t + 0.5) + 0.4 * sin(TAU * 16.3 * t + 2.3)) * dt
		w[2] += 0.3 * A * sin(TAU * 9.1 * t + 0.9) * dt
	var par: Array = E["par"]
	if par[0] or par[1] or par[2]:
		var kT := minf(1.5, float(av.get("T", 0.0)) / (m.masa_kg * G0))
		w[0] += par[0] / I["Ixx"] * kT * dt; w[1] += par[1] / I["Iyy"] * kT * dt; w[2] += par[2] / I["Izz"] * kT * dt

## Avisos de la app al armar (el autodiagnostico del dron comercial).
static func avisos_app(averias: Array, A: Dictionary) -> Array:
	if clase(A) != "cuad" and clase(A) != "uav": return []
	var L := []
	for a in averias:
		if a["c"] == "brujula": L.append("Error de brújula: calibra la brújula")
		if a["c"] == "imu": L.append("Es necesario calibrar la IMU")
		if a["c"] == "gps": L.append("Señal GPS débil: el posicionamiento puede ser impreciso")
	return L

# ---------------------------------------------------------------- desgaste de cada vuelo
## Azar con semilla (Park-Miller, el de los sorteos de las operaciones), como Desgaste.azar en JS: [estado] y _rnd(estado).
static func azar(texto: String) -> Array:
	var h := 7
	for i in texto.length(): h = (h * 31 + texto.unicode_at(i)) % 2147483647
	return [h if h else 1]

static func _rnd(s: Array) -> float:
	s[0] = (s[0] * 48271) % 2147483647
	return float(s[0]) / 2147483647

static func _r6(x: float) -> float: return snappedf(x, 0.000001)

## Despues de un vuelo: suma las horas y decide lo que se estropea (Desgaste.trasVuelo de JS). Devuelve las nuevas.
static func tras_vuelo(est: Dictionary, A: Dictionary, info: Dictionary) -> Array:
	var dh: float = maxf(0.0, float(info["s"])) / 3600; var comp := componentes(A); var nuevas := []
	if dh <= 0: return nuevas
	est["horas"] = _r6(float(est["horas"]) + dh)
	for cc in comp: est["h"][cc[0]] = _r6(float(est["h"].get(cc[0], 0.0)) + dh)
	var con_bat: bool = comp.any(func(cc): return cc[0] == "bateria") and info["bat0"] != null and info["bat1"] != null
	if con_bat and float(info["bat0"]) - float(info["bat1"]) > 25: est["bateria"]["ciclos"] = int(est["bateria"]["ciclos"]) + 1
	var F: String = info["fecha"]
	var poner := func(a: Dictionary, o: String) -> void:
		var x = anadir(est, a, o, F)
		if x != null: nuevas.append(x)
	if info.get("tomaPerdida", false) and clase(A) == "uav":       # la toma en perdida: piezas sueltas (tambien la primera hora: es su diseño)
		var rt := azar(String(info["semilla"]) + "/toma")
		for st in SUELTA_TOMA:
			if _rnd(rt) < st[1]: poner.call({ "c": st[0], "tipo": "suelto" }, "toma")
	if float(est["horas"]) <= HORAS_SIN_AVERIAS: return nuevas
	var rs := azar(String(info["semilla"]))
	if con_bat:
		var s: float = est["bateria"]["salud"]
		if float(info["bat0"]) - float(info["bat1"]) > 25: s -= 0.004
		if float(info["bat1"]) < 10:
			s -= 0.03
			if _rnd(rs) < 0.15: poner.call({ "c": "bateria", "tipo": "hinchada" }, "descarga")
		if info["tempMax"] != null and float(info["tempMax"]) > 55: s -= 0.01
		est["bateria"]["salud"] = snappedf(maxf(0.5, minf(float(est["bateria"]["salud"]), s)), 0.0001)
		if float(est["bateria"]["salud"]) < 0.8: poner.call({ "c": "bateria", "tipo": "envejecida" }, "desgaste")
	for cc in comp:
		var c: String = cc[0]; var f := familia(c); var T = TASAS.get("celda" if f == "bateria" else f)
		if T == null: continue
		var lam: float = T[0] * (maxf(0.5, float(est["h"][c])) if T[1] else 1.0); var p := 1 - exp(-lam * dh); var r := _rnd(rs)
		if r >= p: continue
		if f == "bateria":
			var nB: int = int(Bateria.datos(A.get("propulsion", {}))["celdas"])
			poner.call({ "c": c, "tipo": "celda", "n": int(floor(_rnd(rs) * nB)) }, "desgaste")
		else:
			for a in posibles(A):
				if a["c"] == c: poner.call(a, "desgaste"); break
	if info["roto"]:
		var hs := comp.filter(func(cc): return String(cc[0]).begins_with("helice"))
		if not hs.is_empty() and _rnd(rs) < 0.8: poner.call({ "c": hs[int(floor(_rnd(rs) * hs.size()))][0], "tipo": "mella" }, "golpe")
		if comp.any(func(cc): return cc[0] == "imu") and _rnd(rs) < 0.2: poner.call({ "c": "imu", "tipo": "descalibrada" }, "golpe")
	return nuevas

# ---------------------------------------------------------------- taller: inspeccion y reparacion
static func revisiones(A: Dictionary) -> Array:
	var k := clase(A); var r := [["helices", "Inspeccionar las hélices"], ["motores", "Girar los motores a mano"]]
	if k == "uav": r.push_front(["montaje", "Comprobar el montaje"])
	if k != "comb": r.append(["bateria", "Revisar la batería"])
	if k == "cuad": r.append(["app", "Autodiagnóstico de la app"])
	if k == "uav": r.append(["app", "Autodiagnóstico de la estación de control"])
	if k == "avion" or k == "comb" or k == "uav": r.append(["superficies", "Mover las superficies a mano"])
	return r

static func _tiene(est: Dictionary, c: String, t := "") -> bool:
	for a in est["averias"]:
		if a["c"] == c and (t == "" or a["tipo"] == t): return true
	return false

static func _coma(x: float, n: int) -> String: return (("%." + str(n) + "f") % x).replace(".", ",")

## El resultado de una revision: lineas de texto (lo que se ve, no el nombre de la averia).
static func revisar(est: Dictionary, A: Dictionary, id: String) -> Array:
	var comp := componentes(A); var L := []
	if id == "helices":
		for cc in comp:
			if String(cc[0]).begins_with("helice"): L.append(cc[1] + ": " + ("mella en el borde de ataque y una grieta junto al buje" if _tiene(est, cc[0]) else "sin daños, bien apretada"))
	if id == "motores":
		for cc in comp:
			if String(cc[0]).begins_with("motor"): L.append(cc[1] + ": " + ("gira áspero, con ruido de rodamiento y algo de juego en el eje" if _tiene(est, cc[0]) else "gira suave y sin ruido"))
	if id == "bateria":
		var B := Bateria.datos(A.get("propulsion", {})); var hin := _tiene(est, "bateria", "hinchada")
		var s: float = minf(float(est["bateria"]["salud"]), 0.6) if hin else float(est["bateria"]["salud"])
		var deb = null
		for a in est["averias"]:
			if a["c"] == "bateria" and a["tipo"] == "celda": deb = a; break
		L.append("Aspecto: la batería está hinchada (abombada). No se debe usar" if hin else "Aspecto: normal, sin golpes ni hinchazón")
		L.append("Ciclos de carga: %d" % int(est["bateria"]["ciclos"]))
		L.append("Capacidad a plena carga: %d mAh de %d (%d %%)" % [int(round(float(B["capacidad_mAh"]) * s)), int(round(float(B["capacidad_mAh"]))), int(round(100 * s))])
		var cs := PackedStringArray()
		for i in int(B["celdas"]): cs.append(_coma(3.85 + DESEQ[i % 6] - (0.09 if deb != null and int(deb.get("n", 0)) == i else 0.0), 2) + " V")
		L.append("Celdas en reposo: " + " · ".join(cs))
	if id == "app":
		var av := avisos_app(est["averias"], A)
		L.append_array(av if not av.is_empty() else ["Sin errores: brújula, IMU y GPS correctos"])
	if id == "montaje":
		for mm in MONTAJE:
			L.append(MONTAJE[mm][1] + ": " + ("se soltó en la toma (está hecho para soltarse): hay que montarlo y asegurar los cierres" if _tiene(est, "montaje_" + mm) else "montado y asegurado"))
	if id == "superficies":
		for s in superficies(A):
			var nom: String = SUPERFICIES[s]; var N := nom.substr(0, 1).to_upper() + nom.substr(1)
			if _tiene(est, "servo_" + s): L.append(N + (": tienen" if s == "alerones" else ": tiene") + " juego con el servo quieto (holgura en los engranajes del servo)")
			elif _tiene(est, "bisagra_" + s): L.append(N + ": la bisagra está despegada y la superficie se mueve de más")
			else: L.append(N + ": firme, sin holgura")
	return L

## Las reparaciones posibles: [id, texto, componentes que renueva].
static func reparaciones(A: Dictionary) -> Array:
	var comp := componentes(A); var r := []
	var hs := comp.filter(func(cc): return String(cc[0]).begins_with("helice"))
	if hs.size() > 1: r.append(["helices", "Cambiar todas las hélices", hs.map(func(cc): return cc[0])])
	for cc in comp:
		var c: String = cc[0]; var n: String = cc[1]; var f := familia(c)
		if f == "helice": r.append([c, "Cambiar la " + _minus1(n), [c]])
		elif f == "motor": r.append([c, "Cambiar el " + _minus1(n), [c]])
		elif f == "bateria": r.append([c, "Cambiar la batería", [c]])
		elif f == "brujula": r.append([c, "Calibrar la brújula", [c]])
		elif f == "imu": r.append([c, "Calibrar la IMU", [c]])
		elif f == "gps": r.append([c, "Cambiar el módulo GPS", [c]])
		elif f == "barometro": r.append([c, "Cambiar el barómetro", [c]])
		elif f == "servo" or f == "bisagra": r.append([c, ("Cambiar el " if f == "servo" else "Cambiar la ") + _minus1(n), [c]])
		elif f == "montaje": r.append([c, "Montar y asegurar " + MONTAJE[_sup(c)][0], [c]])
	return r if clase(A) != "" else []

## Hace una reparacion: renueva los componentes, quita sus averias y lo apunta en el libro. Devuelve la entrada.
static func reparar(est: Dictionary, A: Dictionary, id: String, fecha: String):
	var R = null
	for x in reparaciones(A):
		if x[0] == id: R = x; break
	if R == null: return null
	var arr := (est["averias"] as Array).filter(func(a): return (R[2] as Array).has(a["c"]))
	est["averias"] = (est["averias"] as Array).filter(func(a): return not (R[2] as Array).has(a["c"]))
	for c in R[2]: est["h"][c] = 0.0
	if (R[2] as Array).has("bateria"): est["bateria"] = { "salud": 1.0, "ciclos": 0 }
	var e := { "fecha": fecha, "accion": id, "texto": R[1], "arreglo": arr.map(func(a): return nombre(a)), "horas": snappedf(float(est["horas"]), 0.001) }
	est["libro"].append(e)
	if est["libro"].size() > 200: est["libro"] = (est["libro"] as Array).slice(est["libro"].size() - 200)
	return e

# ---------------------------------------------------------------- guardar: el aula (por alumno) o el ordenador
static var cache := {}

static func _local() -> Dictionary:
	var t := FileAccess.get_file_as_string(F_LOCAL)
	var d = JSON.parse_string(t) if t != "" else {}
	return d if d is Dictionary else {}

## Estado de un vehiculo (de lo ultimo cargado).
static func estado(avion: String) -> Dictionary: return cache[avion] if cache.has(avion) else nuevo()

## Carga los estados: los del alumno en el aula o, sin conexion, los de este ordenador. p: principal.gd.
static func cargar(p) -> bool:
	if p.aula.activo and p.sesion["alumno"] != null:
		var r: Dictionary = await p.aula.api("GET", "vehiculos?alumno=" + String(p.sesion["alumno"]["id"]).uri_encode())
		if r["ok"] and r["datos"] is Dictionary: cache = r["datos"]; return true
		return false
	cache = _local(); return true

## Cambia el estado de un vehiculo con f(estado) (en el aula, sobre el ultimo del servidor; con 409, se repite).
static func modificar(p, avion: String, f: Callable):
	if p.aula.activo and p.sesion["alumno"] != null:
		var aid := String(p.sesion["alumno"]["id"])
		for k in 4:
			var r: Dictionary = await p.aula.api("GET", "vehiculos?alumno=" + aid.uri_encode())
			if not r["ok"] or not r["datos"] is Dictionary: break
			var todos: Dictionary = r["datos"]
			var est: Dictionary = todos[avion] if todos.has(avion) else nuevo()
			var res = f.call(est)
			var g: Dictionary = await p.aula.api("POST", "vehiculos", { "alumno_id": aid, "avion": avion, "version": int(est["version"]), "estado": est })
			if g["ok"]: todos[avion] = g["datos"]; cache = todos; return res
			if g["status"] != 409: break
		return null
	var L := _local(); var est: Dictionary = L[avion] if L.has(avion) else nuevo()
	var res = f.call(est)
	est["version"] = int(est.get("version", 0)) + 1; L[avion] = est
	var fa := FileAccess.open(F_LOCAL, FileAccess.WRITE)
	if fa: fa.store_string(JSON.stringify(L)); fa.close()
	cache = L; return res
