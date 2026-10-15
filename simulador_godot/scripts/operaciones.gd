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
## op.paso(p_ant, av, dt, {gimbal, grabando, zoom, termica}) devuelve los avisos y deja op.choque si ha chocado; con cada foto
## op.foto(av, gimbal, {zoom, termica}); al acabar op.final(final, av, {bateria}); op.ahora(obj, av) es la linea "Ahora: ..." del panel.
## Con la termica, op.lectura es lo que mide el medidor puntual ({T, tipo, nombre} o null) y op.termicos lo que se ve caliente o frio.

const TECHO := 120.0
const VLOS := 500.0
const ARP := { "nombre": "aeropuerto de San Javier", "n": 17936.4, "e": 20962.4, "r": 8000.0 }
const CAM_V := 29.0
static var CAM_H := atan(tan(29 * PI / 180) * 4 / 3) * 180 / PI
const CASA := 10.0
const RESERVA := 20.0
const RETICULA := 0.6               # radio de la cruz del medidor puntual de la termica (grados con zoom 1x)
const AMBIENTE := 29.5              # lo que mide la termica en el suelo (grados C)
## Temperatura (grados C) -> "calor" de la imagen termica (0 frio, 1 lo mas caliente): opCalor de operaciones.js.
static func calor(T: float) -> float:
	if T >= 40: return 0.55 + 0.45 * minf(1, (T - 40) / 110)
	if T <= 10: return 0.15 * maxf(0, (T + 20) / 30)
	return 0.15 + 0.4 * (T - 10) / 30
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
var termicos := []                  # termica: lo que se ve caliente o frio
var lectura = null                  # lo que mide el medidor puntual
var medida = null
var hechos_c := []                  # puntos calientes medidos (fabrica) o fotografiados (paneles)
var modulos_c := []
var racks_pista := []
var boca := []
var placa := []
var valvula := []
var unidad_fuga := {}
var hecho_fuga := false
var hecho_placa := false
var hecho_piloto := false
var t_todo = null
var solido := Callable()

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

## (n, e) dentro del poligono [[n, e], ...] (Operacion.dentro de la web).
static func dentro(P: Array, n: float, e: float) -> bool:
	var d := false; var j := P.size() - 1
	for i in P.size():
		var ni: float = P[i][0]; var ei: float = P[i][1]; var nj: float = P[j][0]; var ej: float = P[j][1]
		if (ni > n) != (nj > n) and e < (ej - ei) * (n - ni) / (nj - ni) + ei: d = not d
		j = i
	return d
## Distancia de (n, e) al borde del poligono (m) (Operacion.aBorde).
static func a_borde(P: Array, n: float, e: float) -> float:
	var m := 1e9; var j := P.size() - 1
	for i in P.size():
		var ni: float = P[i][0]; var ei: float = P[i][1]; var dn: float = float(P[j][0]) - ni; var de: float = float(P[j][1]) - ei; var L2 := dn * dn + de * de
		var t := clampf(((n - ni) * dn + (e - ei) * de) / L2, 0, 1) if L2 > 0 else 0.0
		m = minf(m, Vector2(ni + t * dn - n, ei + t * de - e).length()); j = i
	return m

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
			if P.has("huecos") and f in P["huecos"]: continue               # pasillo sin paneles
			if r.all(func(g): return g[0] != f or absi(g[1] - x) >= 10): r.append([f, x])
		dd["defectos"] = r
		if O.has("calientes"):                      # y los modulos con punto caliente (solo se ven con la termica), en otros sitios
			var c := []
			while c.size() < int(O["calientes"]):
				var f := int(floor(rnd.call() * P["filas"])); var x := 3 + int(floor(rnd.call() * (P["largo"] - 6)))
				if P.has("huecos") and f in P["huecos"]: continue
				if (r + c).all(func(g): return g[0] != f or absi(g[1] - x) >= 10): c.append([f, x])
			dd["calientes"] = c
	if O.has("racks"):                                # fabrica: puntos calientes en tuberias de plata de racks distintos, la fuga y la antorcha
		var libres := []
		for i in (O["racks"] as Array).size(): libres.append(i)
		var c := []
		while c.size() < int(O["calientes"]):
			var k := int(floor(rnd.call() * libres.size())); var ri: int
			if not libres.is_empty(): ri = libres[k]; libres.remove_at(k)
			else: ri = int(floor(rnd.call() * (O["racks"] as Array).size()))
			var tbs := Industria.tuberias(O["racks"][ri]); var plata := []
			for i in tbs.size():
				if int(tbs[i]["color"]) == 5: plata.append(i)
			var ti: int = plata[int(floor(rnd.call() * plata.size()))]
			var f := roundf((0.15 + 0.7 * rnd.call()) * 1000) / 1000; var Tc := roundf(105 + 30 * rnd.call())
			c.append([ri, ti, f, Tc])
		dd["puntosCalientes"] = c
		var ui := int(floor(rnd.call() * (O["unidades"] as Array).size()))
		var vi := int(floor(rnd.call() * (O["unidades"][ui]["valvulas"] as Array).size())); var lado := int(floor(rnd.call() * 4))
		dd["fuga"] = [ui, vi, lado]
		dd["placaTxt"] = "A-%d" % (10 + int(floor(rnd.call() * 90))); dd["piloto"] = rnd.call() < 0.7
	if O.has("parcela") and O.has("manchas"):         # agricultura: las manchas en la parcela (o en su poligono), sin pisarse
		var P: Dictionary = O["parcela"]; var r := []
		for mm in O["manchas"]:
			var rad: float = mm[2]; var m = null; var k := 0
			while k < 200 and m == null:
				var n: float = P["n0"] + rad + 8 + rnd.call() * (P["n1"] - P["n0"] - 2 * rad - 16); var e: float = P["e0"] + rad + 8 + rnd.call() * (P["e1"] - P["e0"] - 2 * rad - 16)
				k += 1
				if P.has("poligono") and not (dentro(P["poligono"], n, e) and a_borde(P["poligono"], n, e) >= rad + 8): continue
				if r.all(func(o): return Vector2(n - o[0], e - o[1]).length() >= rad + o[2] + 20): m = [n, e, rad]
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
	solido = mundo.get("solido", Callable())         # (N, E, arriba) -> true si hay un edificio o una instalacion: tapa la vista de la termica
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
	if d.has("racks"): _fabrica()

## Punto de un objetivo: con cota (m sobre el mar) o h (m sobre el suelo).
func z(n: float, e: float, q: Dictionary) -> float:
	return q["cota"] - h0 if q.has("cota") else suelo.call(n, e) + float(q.get("h", 0.0))

## Un punto P (N, E, arriba) en la camara del dron (gimbal en grados): x delante, y derecha, z abajo de la imagen, d distancia.
static func camara(av: Dictionary, gimbal: float, P: Array) -> Dictionary:
	var y: float = Cuat.euler(av["q"])[2]; var g := gimbal * D2R; var cy := cos(y); var sy := sin(y); var cg := cos(g); var sg := sin(g)
	var v := [P[0] - av["p"][0], P[1] - av["p"][1], -(P[2] + av["p"][2])]
	return { "x": v[0] * cy * cg + v[1] * sy * cg - v[2] * sg, "y": -v[0] * sy + v[1] * cy, "z": v[0] * cy * sg + v[1] * sy * sg + v[2] * cg,
			 "d": sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]) }
static func en_foto(c: Dictionary, k: float, zoom := 1.0) -> bool:
	return c["x"] > 0 and absf(c["y"]) <= k * tan(CAM_H * D2R) / zoom * c["x"] and absf(c["z"]) <= k * tan(CAM_V * D2R) / zoom * c["x"]

## Distancia del rayo del centro de la camara (rumbo y gimbal) a un segmento P0-P1 (N, E, arriba): {t, d} (rayoSegmento).
static func rayo_segmento(av: Dictionary, gimbal: float, P0: Array, P1: Array) -> Dictionary:
	var y: float = Cuat.euler(av["q"])[2]; var g := gimbal * D2R; var u := [cos(y) * cos(g), sin(y) * cos(g), sin(g)]
	var O := [av["p"][0], av["p"][1], -av["p"][2]]; var v := [P1[0] - P0[0], P1[1] - P0[1], P1[2] - P0[2]]; var w0 := [O[0] - P0[0], O[1] - P0[1], O[2] - P0[2]]
	var b: float = u[0] * v[0] + u[1] * v[1] + u[2] * v[2]; var c: float = v[0] * v[0] + v[1] * v[1] + v[2] * v[2]
	var dd: float = u[0] * w0[0] + u[1] * w0[1] + u[2] * w0[2]; var e: float = v[0] * w0[0] + v[1] * w0[1] + v[2] * w0[2]
	var s := 0.0
	if c > 1e-9:
		var den := c - b * b; s = clampf((e - b * dd) / den, 0, 1) if den > 1e-12 else 0.0
	var t := maxf(0, s * b - dd)
	if c > 1e-9: s = clampf((e + t * b) / c, 0, 1)
	var q := [w0[0] + t * u[0] - s * v[0], w0[1] + t * u[1] - s * v[1], w0[2] + t * u[2] - s * v[2]]
	return { "t": t, "d": sqrt(q[0] * q[0] + q[1] * q[1] + q[2] * q[2]) }
## Lo que mide el medidor puntual de la termica: el objeto termico mas cercano dentro de la cruz del centro, o null.
func medir(av: Dictionary, gimbal: float, zoom: float):
	var mejor = null; var tm := 0.0
	for o in termicos:
		var r := rayo_segmento(av, gimbal, o["P0"], o["P1"])
		if r["t"] > 0.5 and r["d"] <= o["r"] + r["t"] * tan(RETICULA * D2R) / zoom and (mejor == null or r["t"] < tm): mejor = o; tm = r["t"]
	if mejor != null and solido.is_valid() and _tapado(av, gimbal, tm): return null
	return { "T": mejor["T"], "tipo": mejor["tipo"], "nombre": mejor["nombre"], "i": mejor["i"], "dist": tm } if mejor != null else null
## Si un edificio o una instalacion tapa el rayo del centro antes de llegar a t m (los ultimos 6 m no cuentan) (_tapado).
func _tapado(av: Dictionary, gimbal: float, t: float) -> bool:
	var y: float = Cuat.euler(av["q"])[2]; var g := gimbal * D2R; var u := [cos(y) * cos(g), sin(y) * cos(g), sin(g)]
	var s := 2.5
	while s < t - 6:
		if solido.call(av["p"][0] + s * u[0], av["p"][1] + s * u[1], -av["p"][2] + s * u[2]): return true
		s += 2.5
	return false

func _aviso(clave: String, texto: String, lista: Array) -> void:
	if not avisos.get(clave, false): avisos[clave] = true; lista.append(texto)

## Planta fotovoltaica (_planta de la web): filas que salen de (n0, e0) hacia "rumbo" (90 = este), apiladas a su derecha
## cada "separacion" m, inclinadas con el borde alto hacia la fila siguiente; mesas de "tramo" m asentadas en el terreno;
## "huecos": filas que son pasillos. l a lo largo de la fila, t a traves.
var pl := {}
var mesas_fila := []
func ne(l: float, t: float) -> Array:
	var P: Dictionary = d["planta"]; return [P["n0"] + l * pl["cr"] + t * pl["sr"], P["e0"] + l * pl["sr"] - t * pl["cr"]]
func lt(N: float, E: float) -> Array:
	var P: Dictionary = d["planta"]; var dn: float = N - P["n0"]; var de: float = E - P["e0"]
	return [dn * pl["cr"] + de * pl["sr"], dn * pl["sr"] - de * pl["cr"]]
func _planta() -> void:
	var P: Dictionary = d["planta"]; var c := cos(P["inclinacion"] * D2R); var s := sin(P["inclinacion"] * D2R); var r: float = float(P.get("rumbo", 90)) * D2R
	pl = { "cr": cos(r), "sr": sin(r) }
	var tr: float = float(P.get("tramo", P["largo"])); var hueco := 0.4 if P.has("tramo") else 0.0
	for i in int(P["filas"]):
		var t: float = i * P["separacion"]; var fila := []
		if not (P.has("huecos") and i in P["huecos"]):
			var l0 := 0.0
			while l0 < P["largo"] - 0.01:
				var l1 := minf(P["largo"], l0 + tr - hueco); var q := ne((l0 + l1) / 2, t)
				var M := { "fila": i, "t": t, "l0": l0, "l1": l1, "fondo": P["ancho"] * c, "y": suelo.call(q[0], q[1]), "alto": P["h0"] + P["ancho"] * s }
				mesas.append(M); fila.append(M); l0 += tr
		mesas_fila.append(fila)
	for q in d["defectos"]:
		var F: Array = mesas_fila[int(q[0])]; var M: Dictionary = F[0]; var x: float = q[1]
		for mm in F: if x >= mm["l0"] and x <= mm["l1"]: M = mm; break
		var pq := ne(x, int(q[0]) * P["separacion"]); modulos.append([pq[0], pq[1], M["y"] + P["h0"] + P["ancho"] * s / 2])
	var ic := 0
	for q in (d["calientes"] if d.get("calientes") is Array else []):    # modulos con punto caliente: una celula quemada a 70-95 grados
		var F: Array = mesas_fila[int(q[0])]; var M: Dictionary = F[0]; var x: float = q[1]
		for mm in F: if x >= mm["l0"] and x <= mm["l1"]: M = mm; break
		var pq := ne(x, int(q[0]) * P["separacion"]); var P3 := [pq[0], pq[1], M["y"] + P["h0"] + P["ancho"] * s / 2]
		var Tm := 70 + 5 * ((int(q[0]) * 7 + int(q[1])) % 6)
		termicos.append({ "tipo": "modulo", "i": ic, "nombre": "módulo con punto caliente", "T": Tm, "P0": P3, "P1": P3.duplicate(), "r": 0.5 })
		modulos_c.append(P3); hechos_c.append(false); ic += 1

## Fabrica (trabajo de SABIC): los objetos de la termica, la valvula de la fuga y su zona ATEX, y la placa de la antorcha (_fabrica).
func _fabrica() -> void:
	var T := termicos; var k := 0
	for pc in d["puntosCalientes"]:
		var ri: int = int(pc[0]); var R: Dictionary = d["racks"][ri]; var tb: Dictionary = Industria.tuberias(R)[int(pc[1])]
		var y: float = suelo.call((R["n0"] + R["n1"]) / 2, (R["e0"] + R["e1"]) / 2) + tb["yc"]
		var L := Vector2(tb["n1"] - tb["n0"], tb["e1"] - tb["e0"]).length(); var un: float = (tb["n1"] - tb["n0"]) / L; var ue: float = (tb["e1"] - tb["e0"]) / L
		var f: float = pc[2]; var n: float = tb["n0"] + f * (tb["n1"] - tb["n0"]); var e: float = tb["e0"] + f * (tb["e1"] - tb["e0"])
		T.append({ "tipo": "caliente", "i": k, "nombre": "aislamiento roto en el rack %s" % R["nombre"], "T": pc[3], "P0": [n - 0.6 * un, e - 0.6 * ue, y], "P1": [n + 0.6 * un, e + 0.6 * ue, y], "r": tb["d"] / 2 + 0.05 })
		if not ri in racks_pista:
			racks_pista.append(ri)
			for v in Industria.tuberias(R):
				if int(v["color"]) == 6:              # las de vapor de ese rack: calientes de verdad
					T.append({ "tipo": "vapor", "i": -1, "nombre": "tubería de vapor del rack %s" % R["nombre"], "T": 62, "P0": [v["n0"], v["e0"], y - tb["yc"] + v["yc"]], "P1": [v["n1"], v["e1"], y - tb["yc"] + v["yc"]], "r": v["d"] / 2 + 0.03 })
		k += 1; hechos_c.append(false)
	for C in d["chimeneas"]:                       # chimeneas: la parte de arriba templada
		var yc: float = suelo.call(C["n"], C["e"])
		T.append({ "tipo": "chimenea", "i": -1, "nombre": "chimenea", "T": 85, "P0": [C["n"], C["e"], yc + 0.85 * C["alto"]], "P1": [C["n"], C["e"], yc + C["alto"]], "r": C["radio"] + 0.3 })
	var A: Dictionary = d["antorcha"]; var ya: float = suelo.call(A["n"], A["e"])
	boca = [A["n"], A["e"], ya + A["alto"]]
	T.append({ "tipo": "antorcha", "i": -1, "nombre": "llama del piloto de la antorcha" if d["piloto"] else "boca de la antorcha (piloto apagado)", "T": 600 if d["piloto"] else 70,
			   "P0": [A["n"], A["e"], ya + A["alto"] - 1], "P1": [A["n"], A["e"], ya + A["alto"] + (1.5 if d["piloto"] else 0.0)], "r": A["radio"] })
	var a := atan2(casa[1] - A["e"], casa[0] - A["n"])      # la placa, en la boca de la antorcha, de cara al despegue
	placa = [A["n"] + (A["radio"] + 0.3) * cos(a), A["e"] + (A["radio"] + 0.3) * sin(a), ya + A["alto"] - 2.2, a * R2D]
	_fuga()
## La valvula de la fuga (d.fuga: unidad, estructura y cara), su objeto termico (gas frio) y la zona ATEX de su unidad (_fuga).
func _fuga() -> void:
	var fg: Array = d["fuga"]; var U: Dictionary = d["unidades"][int(fg[0])]; var V: Array = U["valvulas"][int(fg[1])]; var lado := int(fg[2])
	var e: float = V[0]; var n: float = V[1]; var h: float = V[2]; var largo: float = V[3]; var ancho: float = V[4]; var r: float = V[5] * D2R
	var x := (largo / 2 + 0.3) if lado == 0 else ((-largo / 2 - 0.3) if lado == 1 else 0.0); var z := (ancho / 2 + 0.3) if lado == 2 else ((-ancho / 2 - 0.3) if lado == 3 else 0.0)
	var N := n + x * cos(r) - z * sin(r); var E := e + x * sin(r) + z * cos(r); var up: float = suelo.call(n, e) + h
	valvula = [N, E, up]; unidad_fuga = U; hecho_fuga = false
	termicos = termicos.filter(func(o): return o["tipo"] != "fuga")
	termicos.append({ "tipo": "fuga", "i": -1, "nombre": "fuga de gas en la unidad %s" % U["nombre"], "T": -15, "P0": [N, E, up], "P1": [N, E, up], "r": 0.6 })
## Orden del profesor: la fuga pasa a la unidad mas cercana a (N, E), en su estructura mas cercana (moverFuga).
func mover_fuga(N: float, E: float) -> bool:
	if not d.has("racks"): return false
	var cen := func(U: Dictionary) -> Array:
		var sn := 0.0; var se := 0.0
		for p in U["poligono"]: sn += p[0]; se += p[1]
		return [sn / (U["poligono"] as Array).size(), se / (U["poligono"] as Array).size()]
	var ui := 0
	for i in (d["unidades"] as Array).size():
		var c: Array = cen.call(d["unidades"][i]); var c0: Array = cen.call(d["unidades"][ui])
		if Vector2(c[0] - N, c[1] - E).length() < Vector2(c0[0] - N, c0[1] - E).length(): ui = i
	var V: Array = d["unidades"][ui]["valvulas"]; var vi := 0
	for i in V.size():
		if Vector2(V[i][1] - N, V[i][0] - E).length() < Vector2(V[vi][1] - N, V[vi][0] - E).length(): vi = i
	d["fuga"] = [ui, vi, d["fuga"][2]]; _fuga(); return true

## Un paso de la fisica. info: {gimbal (grados), grabando (video)}.
func paso(_p_ant: Array, av: Dictionary, dt: float, info: Dictionary) -> Array:
	var T := []; var N: float = av["p"][0]; var E: float = av["p"][1]; var up: float = -av["p"][2]; var agl: float = up - suelo.call(N, E); var t: float = av["t"]; var m := marcar
	if av["estado"] != "volando": return T
	if t0 == null and not av.get("posado", false): t0 = t                   # despegue: empieza a contar el tiempo
	# ---- choques: paneles de la planta, faro ----
	if d.has("planta") and not av.get("posado", false):          # solo las mesas de la fila mas cercana y sus vecinas
		var q := lt(N, E); var i0 := int(round(q[1] / d["planta"]["separacion"]))
		for i in range(i0 - 1, i0 + 2):
			if i < 0 or i >= mesas_fila.size(): continue
			for M in mesas_fila[i]:
				if absf(q[1] - M["t"]) < M["fondo"] / 2 + 0.15 and q[0] > M["l0"] - 0.15 and q[0] < M["l1"] + 0.15 and up - M["y"] < M["alto"] + 0.15: choque = "choque con los paneles"
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
		var en_parcela: bool = dentro(P["poligono"], N, E) if P.has("poligono") else (N > P["n0"] and N < P["n1"] and E > P["e0"] and E < P["e1"])
		if en_parcela and agl < d["minima"] and not av.get("posado", false):
			m.call("baja", "mal"); _aviso("baja", "¡A %.1f m del cultivo! No bajes de %s m" % [agl, _n(d["minima"])], T)
	# ---- paneles: nunca a menos de 3 m sobre ellos ----
	if d.has("planta") and not av.get("posado", false):
		var P: Dictionary = d["planta"]; var q := lt(N, E); var M0: Dictionary = mesas[0]; var f: float = M0["fondo"]
		if q[1] > -f and q[1] < (P["filas"] - 1) * P["separacion"] + f and q[0] > 0 and q[0] < P["largo"] and agl < M0["alto"] + d["minima"]:
			m.call("baja", "mal"); _aviso("baja", "¡A menos de %s m de los paneles! Sube" % _n(d["minima"]), T)
	# ---- termica: lo que mide el medidor puntual (y, sostenido sobre un punto caliente o la fuga, se da por medido) ----
	var zoom: float = float(info.get("zoom", 1.0))
	lectura = medir(av, info["gimbal"], zoom) if info.get("termica", false) and not termicos.is_empty() else null
	var L = lectura
	if L != null and (L["tipo"] == "caliente" or L["tipo"] == "fuga") and not (hecho_fuga if L["tipo"] == "fuga" else hechos_c[L["i"]]):
		var lim: float = d["dist_fuga"] if L["tipo"] == "fuga" else d["dist_caliente"]; var clave := "%s%d" % [L["tipo"], L["i"]]
		if L["dist"] / zoom > lim:
			medida = null; _aviso("lejos" + clave, "%s está a %d m: acércate a menos de %s m o usa más zoom para medirlo" % ["La fuga" if L["tipo"] == "fuga" else "Un punto caliente", int(round(L["dist"])), _n(lim)], T)
		else:
			medida = { "clave": clave, "t": medida["t"] + dt } if (medida != null and medida["clave"] == clave) else { "clave": clave, "t": dt }
			if medida["t"] >= d["medir_s"]:
				medida = null
				if L["tipo"] == "fuga": hecho_fuga = true; m.call("fuga", "ok"); T.append("¡Fuga localizada! %s: gas a %s °C · posición enviada" % [L["nombre"], _n(L["T"])])
				else:
					hechos_c[L["i"]] = true; var k := hechos_c.filter(func(x): return x).size()
					T.append("Punto caliente %d: %s, %s °C ✓ (%d/%d)" % [k, L["nombre"], _n(L["T"]), k, (d["puntosCalientes"] as Array).size()])
					if k == (d["puntosCalientes"] as Array).size(): m.call("calientes", "ok")
				_todo(t)
	else: medida = null
	if L != null and L["tipo"] == "vapor": _aviso("vapor", "Tubería de vapor a 62 °C: está caliente por diseño (va aislada), no es una avería", T)
	# ---- fabrica: zona ATEX alrededor de la unidad con la fuga y nunca a menos de 10 m sobre las unidades ----
	if d.has("racks"):
		var A: Array = unidad_fuga["poligono"]
		if dentro(A, N, E) or a_borde(A, N, E) < d["atex"]: m.call("atex", "mal"); _aviso("atex", "¡Dentro de la zona ATEX de la unidad %s! Sal: no se puede volar a menos de %s m" % [unidad_fuga["nombre"], _n(d["atex"])], T)
		for U in d["unidades"]:
			if not av.get("posado", false) and dentro(U["poligono"], N, E) and agl < U["alto"] + d["sobre_unidades"]: m.call("unidades", "mal"); _aviso("unidades", "¡A menos de %s m por encima de la unidad %s! Sube" % [_n(d["sobre_unidades"]), U["nombre"]], T)
		if t0 != null and t - t0 > d["limite_s"] and t_todo == null: m.call("tiempo", "mal"); _aviso("tiempo", "Se han acabado los 30 minutos: termina lo que puedas y vuelve", T)
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

## Una foto (boton de foto del dron comercial): lo que vale para el trabajo y el aviso.
func foto(av: Dictionary, gimbal: float, cam := {}) -> Array:
	var T := []; var N: float = av["p"][0]; var E: float = av["p"][1]; var up: float = -av["p"][2]; var agl: float = up - suelo.call(N, E); var m := marcar
	var zoom: float = float(cam.get("zoom", 1.0)); var ter: bool = bool(cam.get("termica", false))
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
	if d.has("planta"):                                # paneles: cada modulo danado, desde arriba y de 4 a 20 m (con zoom, la distancia equivalente)
		var mot := [""]
		var revisar := func(lista: Array, hech: Array, termico: bool, nombre: String, id: String) -> void:
			for i in lista.size():
				if hech[i]: continue
				var c := camara(av, gimbal, lista[i]); var de: float = c["d"] / zoom
				if not en_foto(c, 1, zoom): continue
				var motivo := ""
				if termico != ter: motivo = ("el %s %d solo se ve con la cámara térmica (C)" % [nombre, i + 1]) if termico else "con la térmica no se ven los cristales rotos ni la suciedad: cambia a la cámara normal (C)"
				elif gimbal > d["gimbal"]: motivo = "los paneles se fotografían desde arriba (cámara a %s° o más)" % _n(d["gimbal"])
				elif de > d["dist"][1]: motivo = "%s %d demasiado lejos (%d m; a menos de %s m%s)" % [nombre, i + 1, int(round(c["d"])), _n(d["dist"][1]), " con este zoom" if zoom > 1 else ""]
				elif de < d["dist"][0]: motivo = "%s %d demasiado cerca" % [nombre, i + 1]
				elif not en_foto(c, 0.8, zoom): motivo = "%s %d en el borde de la foto: encuádralo" % [nombre, i + 1]
				else:
					hech[i] = true; var k := hech.filter(func(x): return x).size()
					T.append(("Punto caliente %d ✓ (%d/%d)" if termico else "Módulo dañado %d ✓ (%d/%d)") % [i + 1, k, lista.size()])
					if k == lista.size(): m.call(id, "ok")
				if motivo != "" and mot[0] == "": mot[0] = motivo
		revisar.call(modulos, hechos, false, "módulo", "defectos")
		while hechos_c.size() < modulos_c.size(): hechos_c.append(false)
		revisar.call(modulos_c, hechos_c, true, "punto caliente", "calientes")
		if T.is_empty(): T.append(("Foto no válida: " + mot[0]) if mot[0] != "" else "Foto sin ningún módulo dañado")
	if d.has("racks"):                                 # fabrica: la placa de la antorcha (zoom) y su piloto (termica)
		var A: Dictionary = d["antorcha"]; var P: Dictionary = d["placa"]; var h := Vector2(N - A["n"], E - A["e"]).length()
		if not hecho_placa:
			var c := camara(av, gimbal, placa); var frente := cos(desenrollar(atan2(E - placa[1], N - placa[0]) - placa[3] * D2R))   # 1 de frente, 0 de lado
			if en_foto(c, 0.5, zoom):
				if frente < 0.5: T.append("La placa no se ve desde este lado: está en la cara de la antorcha que da al despegue")
				elif ter: T.append("Con la térmica no se lee la placa: cambia a la cámara normal (C)")
				elif zoom < P["zoom"]: T.append("La placa no se lee: hace falta un zoom de %sx o más (ahora %sx)" % [_n(P["zoom"]), _n(zoom)])
				elif agl < P["altura"]: T.append("Foto no válida: a %d m de altura (desde más de %s m)" % [int(round(agl)), _n(P["altura"])])
				elif h < P["distancia"]: T.append("Foto no válida: a %d m de la antorcha (desde más de %s m)" % [int(round(h)), _n(P["distancia"])])
				else: hecho_placa = true; m.call("placa", "ok"); T.append("Placa de la antorcha: «%s» ✓" % d["placaTxt"]); _todo(av["t"])
		if not hecho_piloto:
			var c := camara(av, gimbal, boca)
			if en_foto(c, 0.5, zoom):
				if not ter: T.append("Para ver el piloto de la antorcha hace falta la cámara térmica (C)")
				elif c["d"] / zoom > 60: T.append("La boca de la antorcha sale muy pequeña (a %d m): acércate o usa más zoom" % int(round(c["d"])))
				else:
					hecho_piloto = true; m.call("piloto", "ok")
					T.append("Piloto de la antorcha: ENCENDIDO (la llama, a más de 150 °C) ✓" if d["piloto"] else "Piloto de la antorcha: APAGADO (la boca, a 70 °C): hay que avisar a la sala de control ✓"); _todo(av["t"])
		if T.is_empty(): T.append("Foto %d%s" % [fotos, " (térmica)" if ter else ""])
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
	if d.has("planta") and not modulos_c.is_empty(): a.call("calientes", "%d de %d" % [hechos_c.filter(func(x): return x).size(), modulos_c.size()])
	if d.has("racks"):
		a.call("calientes", "%d de %d" % [hechos_c.filter(func(x): return x).size(), (d["puntosCalientes"] as Array).size()])
		if t_todo != null: marcar.call("tiempo", "ok"); a.call("tiempo", mmss(t_todo - t0))

## Fabrica: cuando estan las tres tareas (sin pasarse del tiempo), apunta cuando se acabaron (_todo).
func _todo(t: float) -> void:
	if not d.has("racks") or t_todo != null: return
	if hechos_c.filter(func(x): return x).size() == (d["puntosCalientes"] as Array).size() and hecho_fuga and hecho_placa and hecho_piloto and t0 != null and t - t0 <= d["limite_s"]: t_todo = t

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
	if d.has("planta"):
		var nc := hechos_c.filter(func(x): return x).size(); var tc := modulos_c.size()
		if n == modulos.size() and nc == tc: return volver
		return "Módulos dañados: <b>%d de %d</b>" % [n, modulos.size()] + ((" · puntos calientes (térmica): <b>%d de %d</b>" % [nc, tc]) if tc > 0 else "") + " · recorre las filas con la cámara hacia abajo"
	if d.has("racks"):
		var nc := hechos_c.filter(func(x): return x).size(); var tc := (d["puntosCalientes"] as Array).size(); var ok := func(x: bool) -> String: return "✓" if x else "pendiente"
		if nc == tc and hecho_fuga and hecho_placa and hecho_piloto: return volver
		return "Tiempo: <b>%s</b> · puntos calientes <b>%d de %d</b> · fuga %s · placa %s · piloto %s" % [mmss(maxf(0, d["limite_s"] - (av["t"] - t0))), nc, tc, ok.call(hecho_fuga), ok.call(hecho_placa), ok.call(hecho_piloto)]
	if d.has("faro"): return volver if hecho.call("orbita") else "Órbita: <b>%d°</b> de 330° · a %d m del faro" % [int(round(absf(orb["acc"] * R2D))) if orb != null else 0, int(round(Vector2(N - d["faro"]["n"], E - d["faro"]["e"]).length()))]
	return volver
