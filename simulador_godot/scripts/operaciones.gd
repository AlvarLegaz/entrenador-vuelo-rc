class_name Operacion
extends RefCounted
## OPERACIONES: los trabajos de operador de dron (escenarios.js, "operacion") en el mapa real de Cartagena, con el DJI.
## Traduccion literal de simulador/js/operaciones.js (pruebas/prueba_operaciones.gd la compara con la web): evalua lo que
## pide cada orden de trabajo (inspeccion de edificios, fotogrametria, busqueda y rescate, agricultura, paneles
## fotovoltaicos y video) y las normas del operador (120 m, a la vista, fuera de la zona del aeropuerto, aterrizar en el punto de despegue
## y con reserva de bateria), y detecta los choques con los paneles y el faro. Lo dibuja mundo_3d.gd
## (poner_operacion).
##
## Uso: op = Operacion.new(Operacion.sortear(datos), marcar, anotar, {casa: [N, E], suelo: Callable(N, E), h0}); en cada paso de la fisica
## op.paso(p_ant, av, dt, {gimbal, grabando}) devuelve los avisos y deja op.choque si ha chocado; con cada foto
## op.foto(av, gimbal); al acabar op.final(final, av, {bateria}); op.ahora(obj, av) es la linea "Ahora: ..." del panel.

const TECHO := 120.0
const VLOS := 500.0
const ARP := { "nombre": "aeropuerto de San Javier", "n": 17936.4, "e": 20962.4, "r": 8000.0 }
const CAM_V := 29.0
static var CAM_H := atan(tan(29 * PI / 180) * 4 / 3) * 180 / PI
const CASA := 10.0
const RESERVA := 20.0
const D2R := PI / 180.0
const R2D := 180.0 / PI

var d: Dictionary
var marcar: Callable
var anotar: Callable
var casa: Array
var suelo: Callable
var h0: float
var choque := ""
var avisos := {}
var t0 = null
var fotos := 0
var hechos := []
var celdas := []
var mesas := []
var modulos := []
var encontrado := false
var error = null
var orb = null
var yaw_ant = null
var giro := 0.0

static func desenrollar(x: float) -> float: return x - TAU * round(x / TAU)
# nombres de los desperfectos de la inspeccion: los sitios salen al azar de "candidatos" y cada uno lleva uno de estos
const NOMBRES_CUBIERTA := ["Lucernario de la cubierta", "Placas solares de la cubierta", "Extractor de la cubierta", "Antena del tejado",
	"Impermeabilización levantada", "Claraboya rota", "Chimenea de ventilación", "Equipo de aire acondicionado"]
const NOMBRES_FACHADA := ["Grieta en la fachada", "Canalón de la fachada", "Desconchado en la fachada", "Bajante roto en la fachada"]
static func orientacion(g: float) -> String: return ["norte", "este", "sur", "oeste"][int(round(fposmod(g, 360) / 90)) % 4]

## Los datos de un trabajo con los objetivos en sitios al azar dentro de su zona (sortear de operaciones.js): la inspeccion
## elige cubiertas y fachadas de "candidatos" (con su nombre), los paneles los modulos danados, la agricultura las manchas
## (sin pisarse) y la busqueda al senderista. rnd: numeros al azar en [0, 1) (randf; las pruebas pasan uno con semilla).
static func _tomar(lista: Array, k: int, rnd: Callable, lejos := 0.0) -> Array:
	var L := lista.duplicate(); var r := []
	while r.size() < k and not L.is_empty():
		var vale := L.filter(func(q): return r.all(func(x): return Vector2(q["n"] - x["n"], q["e"] - x["e"]).length() >= lejos))
		var de: Array = vale if not vale.is_empty() else L
		var q = de[int(floor(rnd.call() * de.size()))]; r.append(q); L.remove_at(L.find(q))
	return r

## Los ajustes del profesor al crear la sala ({cubiertas, fachadas, defectos, manchas, minutos, cobertura}) sobre los datos
## de un trabajo, antes de sortear (ajustar de operaciones.js).
static func ajustar(O: Dictionary, A) -> Dictionary:
	if A == null or not (A is Dictionary) or (A as Dictionary).is_empty(): return O
	var dd := O.duplicate()
	var n := func(v, a: int, b: int) -> int: return clampi(int(round(float(v))), a, b)
	if O.has("candidatos") and (A.get("cubiertas") != null or A.get("fachadas") != null):
		var C: Dictionary = O["candidatos"]
		var cu: int = n.call(A.get("cubiertas") if A.get("cubiertas") != null else C["elegir"][0], 0, (C["cubiertas"] as Array).size())
		var fa: int = n.call(A.get("fachadas") if A.get("fachadas") != null else C["elegir"][1], 0, (C["fachadas"] as Array).size())
		var C2 := C.duplicate(); C2["elegir"] = [cu, fa] if cu + fa > 0 else [1, 0]; dd["candidatos"] = C2
	if O.has("defectos") and A.get("defectos") != null:
		var k: int = n.call(A["defectos"], 1, 30); var r := []
		for i in k: r.append(O["defectos"][i % (O["defectos"] as Array).size()])
		dd["defectos"] = r
	if O.has("manchas") and A.get("manchas") != null:
		var k: int = n.call(A["manchas"], 1, 12); var r := []
		for i in k: r.append(O["manchas"][i % (O["manchas"] as Array).size()])
		dd["manchas"] = r
	if O.has("limite_s") and A.get("minutos") != null: dd["limite_s"] = n.call(A["minutos"], 1, 60) * 60
	if O.has("cubrir") and A.get("cobertura") != null: dd["cubrir"] = n.call(A["cobertura"], 30, 100) / 100.0
	return dd

## El texto de un objetivo con los numeros del trabajo ajustado (textoObjetivo de operaciones.js).
static func texto_objetivo(id: String, t: String, dd: Dictionary) -> String:
	var cambia := func(patron: String, nuevo: String) -> String:
		var re := RegEx.new(); re.compile(patron); return re.sub(t, nuevo)
	if id == "puntos" and dd.has("candidatos"): return cambia.call("los \\d+ puntos", "los %d puntos" % (int(dd["candidatos"]["elegir"][0]) + int(dd["candidatos"]["elegir"][1])))
	if id == "defectos" and dd.has("defectos"): return cambia.call("los \\d+ módulos", "los %d módulos" % (dd["defectos"] as Array).size())
	if id == "manchas" and dd.has("manchas"): return cambia.call("las \\d+ manchas", "las %d manchas" % (dd["manchas"] as Array).size())
	if id == "tiempo" and dd.has("limite_s"): return cambia.call("\\d+ minutos", "%d minutos" % int(round(float(dd["limite_s"]) / 60)))
	if id == "cobertura" and dd.has("cubrir"): return cambia.call("el \\d+ %", "el %d %%" % int(round(float(dd["cubrir"]) * 100)))
	return t

static func sortear(O: Dictionary, azar = null) -> Dictionary:
	var rnd: Callable = azar if azar != null else func() -> float: return randf()
	var dd := O.duplicate()
	if O.has("candidatos"):                           # inspeccion: unas cubiertas y unas fachadas, en orden al azar
		var C: Dictionary = O["candidatos"]
		var nc := _tomar(NOMBRES_CUBIERTA.map(func(n): return { "n": 0.0, "e": 0.0, "nombre": n }), int(C["elegir"][0]), rnd)
		var nf := _tomar(NOMBRES_FACHADA.map(func(n): return { "n": 0.0, "e": 0.0, "nombre": n }), int(C["elegir"][1]), rnd)
		var cub := []; var fac := []
		for q in _tomar(C["cubiertas"], int(C["elegir"][0]), rnd, 15): var c: Dictionary = q.duplicate(); c["nombre"] = nc[cub.size()]["nombre"]; cub.append(c)
		for q in _tomar(C["fachadas"], int(C["elegir"][1]), rnd, 15): var c: Dictionary = q.duplicate(); c["nombre"] = "%s %s" % [nf[fac.size()]["nombre"], orientacion(q["normal"])]; fac.append(c)
		dd["puntos"] = _tomar(cub + fac, cub.size() + fac.size(), rnd)
	if O.has("planta") and O.has("defectos"):         # paneles: modulos danados de filas y posiciones al azar
		var P: Dictionary = O["planta"]; var r := []
		while r.size() < (O["defectos"] as Array).size():
			var f := int(floor(rnd.call() * P["filas"])); var x := 3 + int(floor(rnd.call() * (P["largo"] - 6)))
			if r.all(func(g): return g[0] != f or absi(g[1] - x) >= 10): r.append([f, x])
		dd["defectos"] = r
	if O.has("parcela") and O.has("manchas"):         # agricultura: las manchas en la parcela, sin pisarse
		var P: Dictionary = O["parcela"]; var r := []
		for mm in O["manchas"]:
			var rad: float = mm[2]; var m = null; var k := 0
			while k < 200 and m == null:
				var n: float = P["n0"] + rad + 8 + rnd.call() * (P["n1"] - P["n0"] - 2 * rad - 16); var e: float = P["e0"] + rad + 8 + rnd.call() * (P["e1"] - P["e0"] - 2 * rad - 16)
				if r.all(func(o): return Vector2(n - o[0], e - o[1]).length() >= rad + o[2] + 20): m = [n, e, rad]
				k += 1
			r.append(m if m != null else O["manchas"][r.size()])
		dd["manchas"] = r
	if O.has("zona"):                                 # busqueda
		var Z: Dictionary = O["zona"]
		var pn: float = Z["n0"] + 20 + rnd.call() * (Z["n1"] - Z["n0"] - 40); var pe: float = Z["e0"] + 20 + rnd.call() * (Z["e1"] - Z["e0"] - 40)
		dd["persona"] = [pn, pe]
	return dd
static func _n(x) -> String: return PasadaBaja._num(float(x))
static func mmss(s: float) -> String: return "%d:%02d" % [int(floor(s / 60)), int(floor(fmod(s, 60)))]
func _cuenta() -> int: return hechos.filter(func(x): return x).size()

func _init(datos: Dictionary, marcar_: Callable, anotar_: Callable, mundo: Dictionary) -> void:
	d = datos; marcar = marcar_; anotar = anotar_; casa = mundo["casa"]; suelo = mundo["suelo"]; h0 = mundo["h0"]
	var nh := 0
	for k in ["puntos", "manchas", "defectos"]:
		if d.has(k): nh = (d[k] as Array).size()
	for i in nh: hechos.append(false)
	if d.has("parcela") and d.has("solape"):                   # fotogrametria: celdas de 5 m de la parcela
		var P: Dictionary = d["parcela"]; var n: float = P["n0"] + 2.5
		while n < P["n1"]:
			var e: float = P["e0"] + 2.5
			while e < P["e1"]: celdas.append([n, e, 0]); e += 5
			n += 5
	if d.has("planta"): _planta()

## Punto de un objetivo: con cota (m sobre el mar) o h (m sobre el suelo).
func z(n: float, e: float, q: Dictionary) -> float:
	return q["cota"] - h0 if q.has("cota") else suelo.call(n, e) + float(q.get("h", 0.0))

## Un punto P (N, E, arriba) en la camara del dron (gimbal en grados): x delante, y derecha, z abajo de la imagen, d distancia.
static func camara(av: Dictionary, gimbal: float, P: Array) -> Dictionary:
	var y: float = Cuat.euler(av["q"])[2]; var g := gimbal * D2R; var cy := cos(y); var sy := sin(y); var cg := cos(g); var sg := sin(g)
	var v := [P[0] - av["p"][0], P[1] - av["p"][1], -(P[2] + av["p"][2])]
	return { "x": v[0] * cy * cg + v[1] * sy * cg - v[2] * sg, "y": -v[0] * sy + v[1] * cy, "z": v[0] * cy * sg + v[1] * sy * sg + v[2] * cg,
			 "d": sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]) }
static func en_foto(c: Dictionary, k: float) -> bool:
	return c["x"] > 0 and absf(c["y"]) <= k * tan(CAM_H * D2R) * c["x"] and absf(c["z"]) <= k * tan(CAM_V * D2R) * c["x"]

func _aviso(clave: String, texto: String, lista: Array) -> void:
	if not avisos.get(clave, false): avisos[clave] = true; lista.append(texto)

## Planta fotovoltaica: filas de mesas de paneles de este a oeste, inclinadas hacia el sur (_planta de la web).
func _planta() -> void:
	var P: Dictionary = d["planta"]; var c := cos(P["inclinacion"] * D2R); var s := sin(P["inclinacion"] * D2R)
	for i in int(P["filas"]):
		var n: float = P["n0"] + i * P["separacion"]
		mesas.append({ "n": n, "e0": float(P["e0"]), "e1": P["e0"] + P["largo"], "fondo": P["ancho"] * c, "y": suelo.call(n, P["e0"] + P["largo"] / 2), "alto": P["h0"] + P["ancho"] * s })
	for q in d["defectos"]:
		var M: Dictionary = mesas[int(q[0])]; modulos.append([M["n"], P["e0"] + q[1], M["y"] + P["h0"] + P["ancho"] * s / 2])

## Un paso de la fisica. info: {gimbal (grados), grabando (video)}.
func paso(_p_ant: Array, av: Dictionary, dt: float, info: Dictionary) -> Array:
	var T := []; var N: float = av["p"][0]; var E: float = av["p"][1]; var up: float = -av["p"][2]; var agl: float = up - suelo.call(N, E); var t: float = av["t"]; var m := marcar
	if av["estado"] != "volando": return T
	if t0 == null and not av.get("posado", false): t0 = t                   # despegue: empieza a contar el tiempo
	# ---- choques: paneles de la planta, faro ----
	if d.has("planta"):
		for M in mesas:
			if absf(N - M["n"]) < M["fondo"] / 2 + 0.15 and E > M["e0"] - 0.15 and E < M["e1"] + 0.15 and up - M["y"] < M["alto"] + 0.15 and not av.get("posado", false): choque = "choque con los paneles"
	if d.has("faro"):
		var F: Dictionary = d["faro"]
		if Vector2(N - F["n"], E - F["e"]).length() < F["radio"] + 0.3 and up - suelo.call(F["n"], F["e"]) < F["alto"]: choque = "choque con el faro"
	if choque != "": return T
	# ---- normas del operador ----
	if agl > TECHO: m.call("techo", "mal"); _aviso("techo", "¡Por encima de 120 m de altura! Baja", T)
	if Vector2(N - casa[0], E - casa[1]).length() > VLOS: m.call("vlos", "mal"); _aviso("vlos", "¡Más de 500 m del piloto! Ya no lo ves: vuelve", T)
	if Vector2(N - ARP["n"], E - ARP["e"]).length() < ARP["r"]: m.call("zona", "mal"); _aviso("zona", "¡Dentro de la zona del %s!" % ARP["nombre"], T)
	# ---- agricultura: nunca a menos de 5 m sobre el cultivo ----
	if d.has("manchas"):
		var P: Dictionary = d["parcela"]
		if N > P["n0"] and N < P["n1"] and E > P["e0"] and E < P["e1"] and agl < d["minima"] and not av.get("posado", false):
			m.call("baja", "mal"); _aviso("baja", "¡A %.1f m del cultivo! No bajes de %s m" % [agl, _n(d["minima"])], T)
	# ---- paneles: nunca a menos de 3 m sobre ellos ----
	if d.has("planta") and not av.get("posado", false):
		var M0: Dictionary = mesas[0]; var M1: Dictionary = mesas[mesas.size() - 1]
		if N > M0["n"] - M0["fondo"] and N < M1["n"] + M1["fondo"] and E > M0["e0"] and E < M0["e1"] and up - M0["y"] < M0["alto"] + d["minima"]:
			m.call("baja", "mal"); _aviso("baja", "¡A menos de %s m de los paneles! Sube" % _n(d["minima"]), T)
	# ---- busqueda: el tiempo ----
	if d.has("zona") and not encontrado and t0 != null and t - t0 > d["limite_s"]:
		m.call("tiempo", "mal"); _aviso("tiempo", "Se ha acabado el tiempo: el equipo de tierra sigue buscando", T)
	# ---- video: giro suave y orbita ----
	if d.has("faro"):
		var yaw: float = Cuat.euler(av["q"])[2]
		if yaw_ant != null and dt > 0: giro += (absf(desenrollar(yaw - yaw_ant)) / dt - giro) * minf(1, dt / 0.2)
		yaw_ant = yaw
		if info["grabando"] and giro > d["giro_max"] * D2R:
			m.call("suave", "mal"); _aviso("suave", "Tirón en el vídeo: giro de %d°/s (máximo %s)" % [int(round(giro * R2D)), _n(d["giro_max"])], T)
		var F: Dictionary = d["faro"]; var r := Vector2(N - F["n"], E - F["e"]).length()
		var c := camara(av, info["gimbal"], [F["n"], F["e"], suelo.call(F["n"], F["e"]) + 0.6 * F["alto"]])
		var centrado: bool = c["x"] > 0 and absf(c["y"]) <= tan(d["centrado"] * D2R) * c["x"] and absf(c["z"]) <= 0.9 * tan(CAM_V * D2R) * c["x"]
		var vale: bool = info["grabando"] and r >= d["orbita"][0] and r <= d["orbita"][1] and centrado; var a := atan2(E - F["e"], N - F["n"])
		if not avisos.get("orbita", false):
			if vale:
				if orb == null: orb = { "acc": 0.0, "prev": a, "hmin": up, "hmax": up, "fuera": 0.0 }; T.append("Órbita: empieza")
				var O: Dictionary = orb; O["acc"] += desenrollar(a - O["prev"]); O["prev"] = a; O["hmin"] = minf(O["hmin"], up); O["hmax"] = maxf(O["hmax"], up); O["fuera"] = 0.0
				if O["hmax"] - O["hmin"] > 2 * d["variacion"]: orb = null; T.append("Cambio de altura de más de %s m: la órbita empieza de nuevo" % _n(2 * d["variacion"]))
				elif absf(O["acc"]) >= TAU * 0.92: m.call("orbita", "ok"); _aviso("orbita", "¡Órbita completa! Vuelve al punto de despegue", T); orb = null
			elif orb != null:
				orb["prev"] = a; orb["fuera"] += dt
				if orb["fuera"] > 1:
					T.append("Órbita perdida: " + ("no estás grabando" if not info["grabando"] else ("demasiado cerca del faro" if r < d["orbita"][0] else ("demasiado lejos del faro" if r > d["orbita"][1] else "el faro se ha salido del centro de la imagen"))))
					orb = null
	return T

## Una foto (boton de foto del DJI): lo que vale para el trabajo y el aviso.
func foto(av: Dictionary, gimbal: float) -> Array:
	var T := []; var N: float = av["p"][0]; var E: float = av["p"][1]; var up: float = -av["p"][2]; var agl: float = up - suelo.call(N, E); var m := marcar
	fotos += 1
	if av["estado"] != "volando" or av.get("posado", false): return T
	if d.has("puntos"):                                # inspeccion: cada punto bien encuadrado, cerca, de frente o desde arriba
		var motivo := ""; var P_: Array = d["puntos"]
		for i in P_.size():
			if hechos[i]: continue
			var q: Dictionary = P_[i]; var P := [q["n"], q["e"], z(q["n"], q["e"], q)]; var c := camara(av, gimbal, P)
			if not en_foto(c, 1): continue
			var cara: float = ((N - P[0]) * cos(q["normal"] * D2R) + (E - P[1]) * sin(q["normal"] * D2R)) / c["d"] if q.has("normal") else (up - P[2]) / c["d"]
			if c["d"] > d["dist"][1]:
				if motivo == "": motivo = "punto %d demasiado lejos (%d m; acércate a menos de %s m)" % [i + 1, int(round(c["d"])), _n(d["dist"][1])]
			elif c["d"] < d["dist"][0]:
				if motivo == "": motivo = "punto %d demasiado cerca" % (i + 1)
			elif not en_foto(c, 0.8):
				if motivo == "": motivo = "punto %d en el borde de la foto: encuádralo" % (i + 1)
			elif cara < 0.5:
				if motivo == "": motivo = "punto %d: %s" % [i + 1, "la fachada se fotografía de frente" if q.has("normal") else "la cubierta se fotografía desde arriba"]
			else:
				hechos[i] = true; T.append("Punto %d: %s ✓ (%d/%d)" % [i + 1, q["nombre"], _cuenta(), P_.size()])
		if _cuenta() == P_.size(): m.call("puntos", "ok")
		if T.is_empty(): T.append(("Foto no válida: " + motivo) if motivo != "" else "Foto sin ningún punto de inspección")
	if d.has("solape"):                                # fotogrametria: cobertura de cada foto vertical a la altura pedida
		if gimbal > d["gimbal"]: T.append("Foto no válida: la cámara no mira abajo (%d°; hace falta %s° o más)" % [int(round(gimbal)), _n(d["gimbal"])])
		elif agl < d["altura"][0] or agl > d["altura"][1]: T.append("Foto no válida: a %d m (entre %s y %s m)" % [int(round(agl)), _n(d["altura"][0]), _n(d["altura"][1])])
		else:
			var y: float = Cuat.euler(av["q"])[2]; var cy := cos(y); var sy := sin(y); var lv := agl * tan(CAM_V * D2R); var lh := agl * tan(CAM_H * D2R)
			var dentro := 0
			for q in celdas:
				var dn: float = q[0] - N; var de: float = q[1] - E
				if absf(dn * cy + de * sy) <= lv and absf(-dn * sy + de * cy) <= lh: q[2] += 1; dentro += 1
			if dentro == 0: T.append("La foto no cae en la parcela")
			else:
				var pct := cobertura()
				T.append("Foto válida · parcela cubierta con solape: %d %%" % int(round(pct * 100)))
				if pct >= d["cubrir"]: m.call("cobertura", "ok"); _aviso("cobertura", "¡Parcela cubierta! Vuelve al punto de despegue", T)
	if d.has("zona") and d.has("persona") and not encontrado:   # busqueda: foto con la persona en el centro y la posicion enviada
		var pe: Array = d["persona"]; var sp: float = suelo.call(pe[0], pe[1]); var c := camara(av, gimbal, [pe[0], pe[1], sp + 0.9])
		if en_foto(c, 0.3) and c["d"] <= d["dist"]:
			var y: float = Cuat.euler(av["q"])[2]; var g := gimbal * D2R; var est := [N, E]
			if sin(g) < -0.05:
				var k := (sp - up) / sin(g); est = [N + k * cos(y) * cos(g), E + k * sin(y) * cos(g)]
			error = Vector2(est[0] - pe[0], est[1] - pe[1]).length(); encontrado = true
			m.call("localizar", "ok"); m.call("posicion", "ok" if error <= 10 else "mal")
			m.call("tiempo", "ok" if (t0 != null and av["t"] - t0 <= d["limite_s"]) else "mal")
			T.append("¡Encontrado! Posición enviada a %.1f m de la real" % error + ("" if error <= 10 else ": demasiado error (inclina la cámara hacia él)"))
		elif en_foto(c, 1) and c["d"] <= 2 * d["dist"]: T.append("Sale en la foto, pero no en el centro: céntralo y acércate para enviar su posición")
		else: T.append("Foto %d: no se le ve" % fotos)
	if d.has("manchas"):                               # agricultura: cada mancha desde arriba y a la altura pedida
		var motivo := ""; var Ms: Array = d["manchas"]
		for i in Ms.size():
			if hechos[i]: continue
			var mn: float = Ms[i][0]; var me: float = Ms[i][1]; var sm: float = suelo.call(mn, me); var c := camara(av, gimbal, [mn, me, sm])
			if not en_foto(c, 0.9): continue
			var h := up - sm
			if gimbal > d["gimbal"]:
				if motivo == "": motivo = "la cámara tiene que mirar abajo (%s° o más)" % _n(d["gimbal"])
			elif h < d["altura"][0] or h > d["altura"][1]:
				if motivo == "": motivo = "a %d m de la mancha %d (entre %s y %s m)" % [int(round(h)), i + 1, _n(d["altura"][0]), _n(d["altura"][1])]
			else:
				hechos[i] = true; T.append("Mancha %d ✓ (%d/%d)" % [i + 1, _cuenta(), Ms.size()])
		if _cuenta() == Ms.size(): m.call("manchas", "ok")
		if T.is_empty(): T.append(("Foto no válida: " + motivo) if motivo != "" else "Foto sin ninguna mancha")
	if d.has("planta"):                                # paneles: cada modulo danado, desde arriba y de 4 a 20 m
		var motivo := ""
		for i in modulos.size():
			if hechos[i]: continue
			var c := camara(av, gimbal, modulos[i])
			if not en_foto(c, 1): continue
			if gimbal > d["gimbal"]:
				if motivo == "": motivo = "los paneles se fotografían desde arriba (cámara a %s° o más)" % _n(d["gimbal"])
			elif c["d"] > d["dist"][1]:
				if motivo == "": motivo = "módulo %d demasiado lejos (%d m; a menos de %s m)" % [i + 1, int(round(c["d"])), _n(d["dist"][1])]
			elif c["d"] < d["dist"][0]:
				if motivo == "": motivo = "módulo %d demasiado cerca" % (i + 1)
			elif not en_foto(c, 0.8):
				if motivo == "": motivo = "módulo %d en el borde de la foto: encuádralo" % (i + 1)
			else:
				hechos[i] = true; T.append("Módulo dañado %d ✓ (%d/%d)" % [i + 1, _cuenta(), modulos.size()])
		if _cuenta() == modulos.size(): m.call("defectos", "ok")
		if T.is_empty(): T.append(("Foto no válida: " + motivo) if motivo != "" else "Foto sin ningún módulo dañado")
	if d.has("faro"): T.append("Este trabajo es de vídeo: pulsa V para grabar")
	return T

## Parte de la parcela cubierta con solape (0-1).
func cobertura() -> float:
	var n := 0
	for q in celdas:
		if q[2] >= d["solape"]: n += 1
	return float(n) / celdas.size()

## Al acabar el vuelo: aterrizar en el punto de despegue y con reserva de bateria; y el resumen en los objetivos.
func final(fin: String, av: Dictionary, info: Dictionary) -> void:
	var a := anotar; var n := _cuenta()
	if fin == "aterrizado":
		var dc := Vector2(av["p"][0] - casa[0], av["p"][1] - casa[1]).length()
		marcar.call("casa", "ok" if dc <= CASA else "mal"); a.call("casa", "a %.1f m" % dc)
		marcar.call("reserva", "ok" if info["bateria"] >= RESERVA else "mal"); a.call("reserva", "%d %%" % int(round(info["bateria"])))
	if d.has("puntos"): a.call("puntos", "%d de %d" % [n, (d["puntos"] as Array).size()])
	if d.has("solape"): a.call("cobertura", "%d %%" % int(round(cobertura() * 100)))
	if d.has("zona") and error != null: a.call("posicion", "error %.1f m" % error)
	if d.has("manchas"): a.call("manchas", "%d de %d" % [n, (d["manchas"] as Array).size()])
	if d.has("planta"): a.call("defectos", "%d de %d" % [n, modulos.size()])

## Lo que toca ahora (texto del panel, con <b>).
func ahora(obj: Dictionary, av: Dictionary) -> String:
	var hecho := func(k: String) -> bool: return obj.has(k) and obj[k]["estado"] == "ok"
	var N: float = av["p"][0]; var E: float = av["p"][1]; var n := _cuenta()
	var volver := "Ahora: <b>vuelve al punto de despegue y aterriza</b> (a %d m)" % int(round(Vector2(N - casa[0], E - casa[1]).length()))
	if t0 == null: return "Ahora: <b>despega</b> (botón de despegue o L) y ve a la zona de trabajo"
	if d.has("puntos"):
		var i := hechos.find(false)
		if i < 0: return volver
		var q: Dictionary = d["puntos"][i]
		return "Puntos fotografiados: <b>%d de %d</b> · siguiente: %s (punto %d, a %d m)" % [n, (d["puntos"] as Array).size(), q["nombre"], i + 1, int(round(Vector2(N - q["n"], E - q["e"]).length()))]
	if d.has("solape"): return volver if hecho.call("cobertura") else "Parcela cubierta con solape: <b>%d %%</b> (hace falta %d %%) · altura %d m" % [int(round(cobertura() * 100)), int(round(d["cubrir"] * 100)), int(round(maxf(0, -av["p"][2] - suelo.call(N, E))))]
	if d.has("zona"): return volver if encontrado else "Tiempo: <b>%s</b> · busca la chaqueta roja dentro de los jalones amarillos" % mmss(maxf(0, d["limite_s"] - (av["t"] - t0)))
	if d.has("manchas"): return volver if n == (d["manchas"] as Array).size() else "Manchas fotografiadas: <b>%d de %d</b> · fotos verticales de 10 a 30 m" % [n, (d["manchas"] as Array).size()]
	if d.has("planta"): return volver if n == modulos.size() else "Módulos dañados: <b>%d de %d</b> · recorre las filas con la cámara hacia abajo" % [n, modulos.size()]
	if d.has("faro"): return volver if hecho.call("orbita") else "Órbita: <b>%d°</b> de 330° · a %d m del faro" % [int(round(absf(orb["acc"] * R2D))) if orb != null else 0, int(round(Vector2(N - d["faro"]["n"], E - d["faro"]["e"]).length()))]
	return volver
