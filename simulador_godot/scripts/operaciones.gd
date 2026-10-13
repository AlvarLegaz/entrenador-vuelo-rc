class_name Operacion
extends RefCounted
## OPERACIONES: los trabajos de operador de dron (escenarios.js, "operacion") en el mapa real de Cartagena, con el DJI.
## Traduccion literal de simulador/js/operaciones.js (pruebas/prueba_operaciones.gd la compara con la web): evalua lo que
## pide cada orden de trabajo (inspeccion de edificios, fotogrametria, busqueda y rescate, agricultura, linea electrica y
## video) y las normas del operador (120 m, a la vista, fuera de la zona del aeropuerto, aterrizar en el punto de despegue
## y con reserva de bateria), y detecta los choques con los cables, las torres y el faro. Lo dibuja mundo_3d.gd
## (poner_operacion).
##
## Uso: op = Operacion.new(datos, marcar, anotar, {casa: [N, E], suelo: Callable(N, E), h0}); en cada paso de la fisica
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
var bases := []
var laterales := []
var enganches := []
var cables := []
var encontrado := false
var error = null
var orb = null
var yaw_ant = null
var giro := 0.0
var d_cables := INF

static func desenrollar(x: float) -> float: return x - TAU * round(x / TAU)
static func _n(x) -> String: return PasadaBaja._num(float(x))
static func mmss(s: float) -> String: return "%d:%02d" % [int(floor(s / 60)), int(floor(fmod(s, 60)))]
func _cuenta() -> int: return hechos.filter(func(x): return x).size()

func _init(datos: Dictionary, marcar_: Callable, anotar_: Callable, mundo: Dictionary) -> void:
	d = datos; marcar = marcar_; anotar = anotar_; casa = mundo["casa"]; suelo = mundo["suelo"]; h0 = mundo["h0"]
	var nh := 0
	for k in ["puntos", "manchas", "torres"]:
		if d.has(k): nh = (d[k] as Array).size()
	for i in nh: hechos.append(false)
	if d.has("parcela") and d.has("solape"):                   # fotogrametria: celdas de 5 m de la parcela
		var P: Dictionary = d["parcela"]; var n: float = P["n0"] + 2.5
		while n < P["n1"]:
			var e: float = P["e0"] + 2.5
			while e < P["e1"]: celdas.append([n, e, 0]); e += 5
			n += 5
	if d.has("torres"): _linea()

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

## Linea electrica: postes de cada torre y vanos de los cables (dos fases y el de tierra), con su flecha.
func _linea() -> void:
	var T: Array = d["torres"]; var n := T.size()
	for q in T: bases.append(suelo.call(q[0], q[1]))
	for i in n:
		var a: Array = T[maxi(0, i - 1)]; var b: Array = T[mini(n - 1, i + 1)]; var L := Vector2(b[0] - a[0], b[1] - a[1]).length()
		laterales.append([-(b[1] - a[1]) / L, (b[0] - a[0]) / L])
	for i in n:
		var r := []
		for k in [-1, 1, 0]:
			r.append([T[i][0] + laterales[i][0] * d["brazo"] * k, T[i][1] + laterales[i][1] * d["brazo"] * k, bases[i] + (d["alto"] if k == 0 else d["fases"])])
		enganches.append(r)
	for i in n - 1:
		for k in 3:
			var A: Array = enganches[i][k]; var B: Array = enganches[i + 1][k]
			var M := [(A[0] + B[0]) / 2, (A[1] + B[1]) / 2, (A[2] + B[2]) / 2 - d["flecha"]]
			cables.append([A, M]); cables.append([M, B])
static func dist_segmento(P: Array, A: Array, B: Array) -> float:
	var ab := Vector3(B[0] - A[0], B[1] - A[1], B[2] - A[2]); var ap := Vector3(P[0] - A[0], P[1] - A[1], P[2] - A[2])
	var t := clampf(ap.dot(ab) / ab.dot(ab), 0, 1)
	return (ap - t * ab).length()

## Un paso de la fisica. info: {gimbal (grados), grabando (video)}.
func paso(_p_ant: Array, av: Dictionary, dt: float, info: Dictionary) -> Array:
	var T := []; var N: float = av["p"][0]; var E: float = av["p"][1]; var up: float = -av["p"][2]; var agl: float = up - suelo.call(N, E); var t: float = av["t"]; var m := marcar
	if av["estado"] != "volando": return T
	if t0 == null and not av.get("posado", false): t0 = t                   # despegue: empieza a contar el tiempo
	# ---- choques: cables y torres de la linea, faro ----
	if d.has("torres"):
		d_cables = INF
		for c in cables: d_cables = minf(d_cables, dist_segmento([N, E, up], c[0], c[1]))
		if d_cables < 0.6: choque = "choque con los cables"
		var TT: Array = d["torres"]
		for i in TT.size():
			var tn: float = TT[i][0]; var te: float = TT[i][1]; var hb: float = up - bases[i]; var L: Array = laterales[i]
			var a: float = (N - tn) * L[0] + (E - te) * L[1]; var b: float = -(N - tn) * L[1] + (E - te) * L[0]
			if hb < d["alto"] and absf(N - tn) < 1.6 and absf(E - te) < 1.6: choque = "choque con la torre %d" % (i + 1)
			if absf(hb - d["fases"] - 1.2) < 0.6 and absf(a) < d["brazo"] + 0.3 and absf(b) < 0.6: choque = "choque con la cruceta de la torre %d" % (i + 1)
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
	# ---- linea: distancia de seguridad a los cables ----
	if d.has("torres") and d_cables < d["seguridad"]:
		m.call("distancia", "mal"); _aviso("distancia", "¡A %.1f m de los cables! La distancia de seguridad son %s m" % [d_cables, _n(d["seguridad"])], T)
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
	if d.has("torres"):                                # linea: los aisladores de cada torre, de 8 a 25 m
		var motivo := ""; var TT: Array = d["torres"]
		for i in TT.size():
			if hechos[i]: continue
			var c := camara(av, gimbal, [TT[i][0], TT[i][1], bases[i] + d["fases"]])
			if not en_foto(c, 0.8): continue
			if c["d"] > d["dist"][1]:
				if motivo == "": motivo = "torre %d demasiado lejos (%d m; a menos de %s m)" % [i + 1, int(round(c["d"])), _n(d["dist"][1])]
			elif c["d"] < d["dist"][0]:
				if motivo == "": motivo = "torre %d demasiado cerca" % (i + 1)
			else:
				hechos[i] = true; T.append("Torre %d ✓ (%d/%d)" % [i + 1, _cuenta(), TT.size()])
		if _cuenta() == TT.size(): m.call("torres", "ok")
		if T.is_empty(): T.append(("Foto no válida: " + motivo) if motivo != "" else "Foto sin los aisladores de ninguna torre")
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
	if d.has("torres"): a.call("torres", "%d de %d" % [n, (d["torres"] as Array).size()])

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
	if d.has("torres"): return volver if n == (d["torres"] as Array).size() else "Torres: <b>%d de %d</b> · a %d m de los cables" % [n, (d["torres"] as Array).size(), int(round(d_cables))]
	if d.has("faro"): return volver if hecho.call("orbita") else "Órbita: <b>%d°</b> de 330° · a %d m del faro" % [int(round(absf(orb["acc"] * R2D))) if orb != null else 0, int(round(Vector2(N - d["faro"]["n"], E - d["faro"]["e"]).length()))]
	return volver
