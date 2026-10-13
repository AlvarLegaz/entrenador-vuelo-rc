class_name PistaFpv
extends RefCounted
## PISTA FPV: los entrenamientos del dron FPV (escenarios.js, "pista_fpv"), en la zona despejada de detras del piloto.
## Traduccion literal de simulador/js/pista_fpv.js (pruebas/prueba_pista_fpv.gd la compara con la web): evalua los
## objetivos de cada mision (estacionario en el cilindro, la caja de conos, slalom y ocho, el circuito de puertas, la recta
## en ACRO, power loop, split-S y picado; y en todas: modo, bateria, plataforma y desarmar) y detecta los choques con los
## postes, las puertas y la torre. Lo dibuja campo_3d.gd (poner_pista_fpv).
##
## Uso: pf = PistaFpv.new(datos, marcar); en cada paso de la fisica pf.paso(p_ant, av, dt, {modo, critica}) devuelve los
## avisos y deja pf.choque con el motivo si ha chocado; al acabar pf.final(final, av); pf.ahora(obj, av) es la linea
## "Ahora: ..." del panel (con <b> y {cono:i} = el pilon de color i del circuito).

const R_DRON := 0.15                  # radio del dron para los choques (m)
const GROSOR := 0.12                  # tubo del marco de las puertas (m)
const PUERTA := { "ancho": 2.4, "alto": 2.0, "h0": 0.0 }
const POSTE := { "r": 0.05, "alto": 4.0 }     # postes del slalom
const OCHO := { "r": 0.05, "alto": 5.0 }      # los dos postes del ocho (rojo y azul)
const CONO_R := 2.0
const CONO_H := 3.0
const RUMBO_TOL := 35.0
const COLOR_OCHO := [2, 3]                    # colores del circuito de los postes del ocho: rojo y azul
const D2R := PI / 180.0

var d: Dictionary
var marcar: Callable
var choque := ""
var t_posado = null
var t_bat := 0.0
var avisos := {}
var t_in := 0.0
var caja := { "fase": 1, "k": 0, "dentro": -1 }
var slalom := { "k": 0, "lado": 0, "empezado": false, "hecho": false }
var ocho := { "acc": [0.0, 0.0], "prev": [null, null], "hecho": false, "vuelta": [false, false] }
var t_fuera := 0.0
var circ := { "k": 0, "n": 0, "t0": null, "ultima": null, "mejor": null }
var recta: PasadaBaja = null
var alta := { "ult": null, "hmax": 0.0 }
var t_alto = null

static func desenrollar(x: float) -> float: return x - TAU * round(x / TAU)
static func _n(x) -> String: return PasadaBaja._num(float(x))

func _init(datos: Dictionary, marcar_: Callable) -> void:
	d = datos; marcar = marcar_
	if d.has("recta"): recta = PasadaBaja.new(d["recta"])

## Puertas del circuito con sus medidas.
func puertas() -> Array:
	var r := []
	for g in d.get("puertas", []):
		var x: Dictionary = PUERTA.duplicate(); x.merge(g, true); r.append(x)
	return r

## Cruce del plano de una puerta entre dos posiciones: {}, {tipo: "pasa", dir: 1 (de frente) | -1} o {tipo: "choque"}.
static func cruce(p_ant: Array, p: Array, g: Dictionary) -> Dictionary:
	var r: float = g["rumbo"] * D2R; var dN := cos(r); var dE := sin(r)
	var s0: float = (p_ant[0] - g["n"]) * dN + (p_ant[1] - g["e"]) * dE; var s1: float = (p[0] - g["n"]) * dN + (p[1] - g["e"]) * dE
	if (s0 < 0) == (s1 < 0): return {}
	var t := s0 / (s0 - s1); var N: float = p_ant[0] + t * (p[0] - p_ant[0]); var E: float = p_ant[1] + t * (p[1] - p_ant[1]); var v: float = -(p_ant[2] + t * (p[2] - p_ant[2]))
	var u := absf(-(N - g["n"]) * dE + (E - g["e"]) * dN); var A: float = g["ancho"] / 2; var H0: float = g["h0"]; var H1: float = g["h0"] + g["alto"]
	var gr := GROSOR; var R := R_DRON
	if u < A - R and v > H0 + R and v < H1 - R: return { "tipo": "pasa", "dir": 1 if s1 > s0 else -1 }
	if u <= A + gr + R and v <= H1 + gr + R and (u >= A - R or v >= H1 - R or (H0 > 0 and v >= H0 - gr - R and v <= H0 + R)): return { "tipo": "choque" }
	return {}

func _aviso(clave: String, texto: String, lista: Array) -> void:
	if not avisos.get(clave, false): avisos[clave] = true; lista.append(texto)

## Un paso de la fisica. info: {modo: modo de Betaflight, critica: bateria por debajo del aviso de aterrizar}.
func paso(p_ant: Array, av: Dictionary, dt: float, info: Dictionary) -> Array:
	var T := []; var p: Array = av["p"]; var N: float = p[0]; var E: float = p[1]; var h: float = -p[2]; var t: float = av["t"]
	var yaw: float = Cuat.euler(av["q"])[2]; var m := marcar
	if av["estado"] != "volando": return T
	# ---- choques: postes, postes del ocho, puertas, puerta alta y torre ----
	var poste := func(q: Array, c: Dictionary, nombre: String) -> void:
		if h < c["alto"] and Vector2(N - q[0], E - q[1]).length() < c["r"] + R_DRON: choque = "choque con " + nombre
	var postes: Array = d.get("postes", [])
	for i in postes.size(): poste.call(postes[i], POSTE, "el poste %d" % (i + 1))
	var och: Array = d.get("ocho", [])
	for i in och.size(): poste.call(och[i], OCHO, "el poste " + ["rojo", "azul"][i])
	if d.has("torre"):
		var q: Dictionary = d["torre"]; var l: float = q["lado"] / 2 + R_DRON
		if h < q["alto"] + R_DRON and absf(N - q["n"]) < l and absf(E - q["e"]) < l: choque = "choque con la torre"
	var gs := puertas(); var cruces := []
	for g in gs: cruces.append(cruce(p_ant, p, g))
	for i in cruces.size():
		if cruces[i].get("tipo", "") == "choque": choque = "choque con la puerta %d" % (i + 1)
	var ca := cruce(p_ant, p, d["puerta_alta"]) if d.has("puerta_alta") else {}
	if ca.get("tipo", "") == "choque": choque = "choque con la puerta alta"
	if choque != "": return T
	# ---- en todas: despegar, modo, bateria y el momento de posarse (para desarmar a tiempo) ----
	if av["despegado"]: m.call("despegar", "ok")
	if av["armado"] and info["modo"] != d["modo"]:
		m.call("modo", "mal"); _aviso("modo", "Has cambiado a %s: este entrenamiento es en %s" % [info["modo"], d["modo"]], T)
	t_bat = t_bat + dt if (info["critica"] and not av["posado"]) else 0.0
	if t_bat > 3: m.call("bateria", "mal"); _aviso("bateria", "Sigues volando con la batería agotada: aterriza ya", T)
	if av["posado"] and av["despegado"]:
		if t_posado == null: t_posado = t
	else: t_posado = null
	# ---- 1. estacionario en el cilindro ----
	if d.has("cilindro"):
		var c: Dictionary = d["cilindro"]
		var dentro: bool = Vector2(N - c["n"], E - c["e"]).length() <= c["r"] and h >= c["h0"] and h <= c["h1"]
		if dentro:
			t_in += dt
			if t_in >= c["t"] and not avisos.get("estacionario", false): m.call("estacionario", "ok"); _aviso("estacionario", "¡%s s en el cilindro! Vuelve a la plataforma" % _n(c["t"]), T)
		else:
			if t_in > 2 and not avisos.get("estacionario", false): T.append("Fuera del cilindro a los %.1f s: vuelve a entrar" % t_in)
			t_in = 0.0
	# ---- 2. la caja: los 4 conos en orden, primero con el morro al sur y luego con el morro hacia cada cono ----
	if d.has("conos"):
		var C := caja; var conos: Array = d["conos"]; var K := conos.size()
		if d.has("techo") and av["despegado"] and h > d["techo"]: m.call("bajo4", "mal"); _aviso("techo", "Por encima de %s m" % _n(d["techo"]), T)
		if C["fase"] == 1 and C["k"] > 0 and absf(desenrollar(yaw - PI)) > RUMBO_TOL * D2R:
			C["k"] = 0; T.append("El morro ha dejado de mirar al sur: empieza otra vez por el cono {cono:0}")
		var toca := -1
		for i in K:
			if Vector2(N - conos[i][0], E - conos[i][1]).length() <= CONO_R and h <= CONO_H: toca = i
		if toca != C["dentro"] and toca >= 0 and C["fase"] <= 2:          # acaba de llegar a un cono
			if toca != C["k"]: T.append("Ese no toca: ahora el cono {cono:%d}" % C["k"])
			else:
				var vale := true
				if C["fase"] == 2 and C["k"] > 0:
					var a: Array = conos[C["k"] - 1]; var b: Array = conos[C["k"]]; var rumbo := atan2(b[1] - a[1], b[0] - a[0])
					vale = absf(desenrollar(yaw - rumbo)) <= RUMBO_TOL * D2R
				if not vale: T.append("Llega al cono con el morro hacia él: gira con la guiñada (palanca izquierda de lado)")
				else:
					C["k"] += 1
					if C["k"] == K:
						m.call("caja1" if C["fase"] == 1 else "caja2", "ok")
						T.append("¡Caja hecha! Ahora otra vez, girando el morro hacia cada cono" if C["fase"] == 1 else "¡Caja hecha girando el morro! Vuelve a la plataforma")
						C["fase"] += 1; C["k"] = 0
					else: T.append("Cono %d/%d" % [C["k"], K])
		C["dentro"] = toca
	# ---- 3. slalom (hacia el sur, alternando el lado de cada poste) y ocho alrededor de los postes rojo y azul ----
	if d.has("postes"):
		var S := slalom
		for i in postes.size():
			var q: Array = postes[i]
			if S["hecho"] or not (p_ant[0] > q[0] and N <= q[0]) or absf(E - q[1]) >= 10 or h >= 6: continue
			var lado := 1 if E > q[1] else -1
			if i == 0: S["k"] = 1; S["lado"] = lado; S["empezado"] = true; T.append("Poste 1/5"); continue
			if i != S["k"]:
				if S["k"] > 0: T.append("Te has saltado el poste %d: empieza otra vez por el primero" % (S["k"] + 1))
				S["k"] = 0; continue
			if lado == S["lado"]: T.append("Poste %d por el mismo lado que el %d: empieza otra vez por el primero" % [i + 1, i]); S["k"] = 0; continue
			S["k"] += 1; S["lado"] = lado
			if S["k"] == postes.size(): S["hecho"] = true; m.call("slalom", "ok"); T.append("¡Slalom hecho! Ahora el ocho al fondo")
			else: T.append("Poste %d/%d" % [S["k"], postes.size()])
	if d.has("ocho"):
		var O := ocho; var ds := []; var VUELTA := 0.9 * TAU
		for q in och: ds.append(Vector2(N - q[0], E - q[1]).length())
		if ds.all(func(x): return x > 25): O["acc"] = [0.0, 0.0]; O["prev"] = [null, null]; O["vuelta"] = [false, false]
		for i in och.size():
			var q: Array = och[i]
			if ds[i] < 1 or ds[i] > 15: O["prev"][i] = null; continue
			var a := atan2(E - q[1], N - q[0])
			if O["prev"][i] != null: O["acc"][i] += desenrollar(a - O["prev"][i])
			O["prev"][i] = a
			if not O["vuelta"][i] and absf(O["acc"][i]) >= VUELTA:
				var j := 1 - i; var nombre: String = ["rojo", "azul"][i]
				if O["vuelta"][j] and signf(O["acc"][j]) == signf(O["acc"][i]):
					O["acc"][i] = 0.0; O["prev"][i] = null; T.append("Vuelta al poste %s en el mismo sentido que al otro: en un ocho, cada uno en un sentido" % nombre); continue
				O["vuelta"][i] = true; T.append("Vuelta al poste %s" % nombre)
				if O["vuelta"][j] and not O["hecho"]: O["hecho"] = true; m.call("ocho", "ok"); T.append("¡Ocho hecho! Vuelve a la plataforma")
	if d.has("banda"):
		var bd: Array = d["banda"]; var activa: bool = slalom["empezado"] and not ocho["hecho"]
		t_fuera = t_fuera + dt if (activa and (h < bd[0] or h > bd[1])) else 0.0
		if t_fuera > 1: m.call("altura13", "mal"); _aviso("banda", "Fuera de la franja de %s a %s m" % [_n(bd[0]), _n(bd[1])], T)
	# ---- 4. circuito de puertas, en orden y de frente ----
	if not gs.is_empty():
		var C := circ
		for i in cruces.size():
			var c: Dictionary = cruces[i]
			if c.get("tipo", "") != "pasa": continue
			if c["dir"] < 0: T.append("Puerta %d al revés: no cuenta" % (i + 1)); continue
			if i != C["k"]: T.append("Esa no toca: ahora la puerta %d" % (C["k"] + 1)); continue
			if i == 0: C["t0"] = t
			C["k"] += 1
			if C["k"] < gs.size(): T.append("Puerta %d/%d" % [C["k"], gs.size()]); continue
			C["k"] = 0; C["n"] += 1; C["ultima"] = t - C["t0"]; C["mejor"] = C["ultima"] if C["mejor"] == null else minf(C["mejor"], C["ultima"])
			if C["n"] <= int(d.get("vueltas", 1)): m.call("vuelta%d" % C["n"], "ok")
			T.append("¡Vuelta %d!  %.1f s" % [C["n"], C["ultima"]])
	# ---- 5. recta por la pista 2 entre 1,5 y 4 m ----
	if recta != null and av["despegado"]:
		var r := recta.actualizar(p)
		if not r.is_empty():
			if r["ok"]: m.call("rectaO" if r["sentido"] == "oeste" else "rectaE", "ok"); T.append("¡Recta hacia el %s!  (%.1f–%.1f m)" % [r["sentido"], r["hmin"], r["hmax"]])
			else: T.append("Recta no válida: " + String(r["motivo"]))
	# ---- 6. power loop y split-S por la puerta alta; picado desde la torre ----
	if d.has("puerta_alta"):
		var A := alta; var g: Dictionary = d["puerta_alta"]
		A["hmax"] = maxf(A["hmax"], h)
		if ca.get("tipo", "") == "pasa":
			var u = A["ult"]
			if u != null and ca["dir"] == u["dir"] and t - u["t"] <= 6 and A["hmax"] >= g["h0"] + g["alto"] + 1: m.call("powerloop", "ok"); T.append("¡Power loop!")
			elif u != null and ca["dir"] != u["dir"] and t - u["t"] <= 5: m.call("splits", "ok"); T.append("¡Split-S!")
			else: T.append("Puerta alta")
			A["ult"] = { "t": t, "dir": ca["dir"] }; A["hmax"] = h
	if d.has("torre"):
		var q: Dictionary = d["torre"]
		if h >= q["alto"] and Vector2(N - q["n"], E - q["e"]).length() <= 10: t_alto = t
		if t_alto != null and h < 5:
			if t - t_alto <= 4: m.call("picado", "ok"); _aviso("picado", "¡Picado! %.1f s" % (t - t_alto), T)
			t_alto = null
	return T

## Al acabar el vuelo: aterrizaje en la plataforma y desarmado a tiempo.
func final(fin: String, av: Dictionary) -> void:
	if fin != "aterrizado": return
	var s: Array = d["salida"]
	marcar.call("plataforma", "ok" if Vector2(av["p"][0] - s[0], av["p"][1] - s[1]).length() <= 1.5 else "mal")
	marcar.call("desarmar", "ok" if (t_posado != null and av["t"] - t_posado <= 3) else "mal")

## Lo que toca ahora (texto del panel, con <b> y {cono:i}). obj: los objetivos del evaluador.
func ahora(obj: Dictionary, av: Dictionary) -> String:
	var hecho := func(k: String) -> bool: return obj.has(k) and obj[k]["estado"] == "ok"
	var volver := "vuelve a la plataforma, aterriza y desarma (L)"
	if not av["despegado"]: return "Ahora: <b>arma con el gas abajo (L) y despega despacio</b>"
	if d.has("cilindro") and not hecho.call("estacionario"):
		return "Ahora: <b>quieto en el cilindro azul</b> · %.1f s de %s" % [t_in, _n(d["cilindro"]["t"])]
	if d.has("conos") and caja["fase"] <= 2:
		return "Ahora: cono <b>{cono:%d}</b> (%d/%d) · " % [caja["k"], caja["k"] + 1, (d["conos"] as Array).size()] + ("<b>con el morro al sur</b>" if caja["fase"] == 1 else "<b>con el morro hacia él</b>")
	if d.has("postes") and not slalom["hecho"]: return "Ahora: <b>slalom</b>, poste %d de %d (alterna el lado)" % [slalom["k"] + 1, (d["postes"] as Array).size()]
	if d.has("ocho") and not ocho["hecho"]: return "Ahora: <b>ocho</b> alrededor del poste {cono:2} y el {cono:3} (cada uno en un sentido)"
	if d.has("recta") and not (hecho.call("rectaO") and hecho.call("rectaE")): return "Ahora: <b>recta por la pista 2 hacia el %s</b>, entre 1,5 y 4 m" % ("este" if hecho.call("rectaO") else "oeste")
	var C := circ; var V := int(d.get("vueltas", 1))
	var tiempos := (" · última %.1f s · mejor %.1f s" % [C["ultima"], C["mejor"]]) if C["ultima"] != null else ""
	if d.has("puertas") and C["n"] < V: return "Ahora: vuelta %d de %d · <b>puerta %d</b> de %d" % [C["n"] + 1, V, C["k"] + 1, (d["puertas"] as Array).size()] + tiempos
	if d.has("puerta_alta"):
		var falta := []
		for x in [["powerloop", "power loop"], ["splits", "split-S"], ["picado", "picado desde la torre"]]:
			if not hecho.call(x[0]): falta.append(x[1])
		if not falta.is_empty(): return "Ahora: <b>" + " · ".join(falta) + "</b>"
	return "Ahora: <b>" + volver + "</b>" + tiempos
