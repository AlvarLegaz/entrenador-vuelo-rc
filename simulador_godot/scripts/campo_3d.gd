class_name Campo3D
extends Node3D
## EL CAMPO DE VUELO DEL CLUB en 3D (version Godot): la isla que se vuela en el vuelo libre y en todos los
## entrenamientos. Traduccion de Visor._campo() de simulador_web/js/visor.js (la escena del navegador cuando no hay mundo
## real), con los mismos generadores deterministas (semilla, ruido, fbm, costa, bordeMonte, alturaTerreno) y las mismas
## listas de arboles, matas, coches y nubes: el suelo pintado (pintarCampo: bancales de almendros sobre tierra rojiza,
## la rambla, el monte bajo del cerro, los caminos, la autopista, la pista 1 con sus marcas de cal y la zona 2 con la
## pista 2, la diana y la linea de la puerta) en una textura de 1400 m alrededor del campo y otra lejana de 6000 m que
## acaba en la costa; el mar, el cerro del oeste, los almendros, los arboles grandes, las matas, el cortijo, la
## autopista con trafico, las estacas cada 50 m, los 4 pilones hinchables del circuito y los 2 naranjas de la puerta, la
## furgoneta, la mesa y la manga de viento (sin carpa: tapaba la vista), y el cielo de Three (Preetham), el sol, la
## calima y las nubes. Las medidas de la pista, los pilones y la zona 2 salen del Entorno. Todo es decorado: las reglas
## del suelo siguen en Entorno.
## El suelo se pinta en la GPU (un SubViewport 2D, como el canvas del navegador) unos fotogramas despues de construir:
## hasta entonces es de color tierra; al acabar se emite suelo_listo.
## Ejes: x = este, y = arriba, z = sur (Avion3D.ned()), como Three en el navegador.

signal suelo_listo

var calidad := 2                   # 0 baja, 1 media, 2 alta (se fija antes de construir)
var ent: Entorno
var base := Vector3.ZERO           # posicion del piloto (en la isla siempre el origen)
var manga: MeshInstance3D
var sol: DirectionalLight3D
var lejanos := []                  # celdas de almendros lejanas: solo con calidad 2
var prescindibles := []            # nubes y matas: no con calidad 0
var listo := false                 # true cuando el suelo ya esta pintado
var _trafico := {}
var _mat_cerca: StandardMaterial3D
var _mat_lejos: StandardMaterial3D
var _arboles := []                 # almendros [E, N, s] (los devuelve el pintado del suelo, como en el navegador)

const D2R := PI / 180.0
const SOL := Vector3(-350, 520, 260)        # posicion del sol (Three)
const LIENZO_TESELA := 2048                 # el lienzo de 4096 px se pinta en 4 teselas

# =====================================================================================================================
#  GENERADORES DETERMINISTAS (los mismos que visor.js: el campo es siempre el mismo)
# =====================================================================================================================

## mulberry32 de visor.js (semilla(s)): r() en [0, 1), con la aritmetica de enteros de 32 bits de JavaScript.
class Semilla:
	var s := 0
	func _init(x: int) -> void:
		s = x & 0xFFFFFFFF
	static func imul(a: int, b: int) -> int:
		return ((a * (b & 0xFFFF)) + (((a * (b >> 16)) & 0xFFFF) << 16)) & 0xFFFFFFFF
	func r() -> float:
		s = (s + 0x6D2B79F5) & 0xFFFFFFFF
		var t := imul(s ^ (s >> 15), 1 | s)
		t = ((t + imul(t ^ (t >> 7), 61 | t)) & 0xFFFFFFFF) ^ t
		return float((t ^ (t >> 14)) & 0xFFFFFFFF) / 4294967296.0

static var _PERM := PackedInt32Array()

static func _perm() -> PackedInt32Array:
	if _PERM.is_empty():
		var r := Semilla.new(7); var p := PackedInt32Array(); p.resize(512)
		for i in 256: p[i] = i
		for i in range(255, 0, -1):
			var j := int(floor(r.r() * (i + 1))); var t := p[i]; p[i] = p[j]; p[j] = t
		for i in 256: p[256 + i] = p[i]
		_PERM = p
	return _PERM

## Ruido de valor suavizado, en [0, 1].
static func ruido(x: float, y: float) -> float:
	var P := _perm()
	var xi := int(floor(x)); var yi := int(floor(y)); var fx := x - xi; var fy := y - yi
	var sx := fx * fx * (3 - 2 * fx); var sy := fy * fy * (3 - 2 * fy)
	var a := P[(P[xi & 255] + (yi & 255)) & 511] / 255.0; var b := P[(P[(xi + 1) & 255] + (yi & 255)) & 511] / 255.0
	var c := P[(P[xi & 255] + ((yi + 1) & 255)) & 511] / 255.0; var d := P[(P[(xi + 1) & 255] + ((yi + 1) & 255)) & 511] / 255.0
	return a + (b - a) * sx + (c - a) * sy + (a - b - c + d) * sx * sy

static func fbm(x: float, y: float, oct := 4) -> float:
	var s := 0.0; var a := 0.5; var f := 1.0; var n := 0.0
	for i in oct:
		s += a * ruido(x * f + 31 * i, y * f - 17 * i); n += a; a *= 0.5; f *= 2.1
	return s / n

## E del eje de la rambla segun N.
static func rambla(N: float) -> float:
	return 385 + 30 * sin(N / 170) + 15 * sin(N / 61 + 1)

## E donde el campo cultivado deja paso al monte bajo del cerro, segun N (borde irregular).
static func borde_monte(N: float) -> float:
	return -95 + 100 * (fbm(N / 150 + 5, 3) - 0.5)

## La isla: radio de la costa (m) segun el rumbo desde el piloto (el mundo es finito y lo rodea el mar).
static func costa(theta: float) -> float:
	return 1700 + 520 * (fbm(2.2 * cos(theta) + 20, 2.2 * sin(theta) + 20) - 0.5) + 90 * sin(3 * theta + 1)

static func poligono_costa(desfase: float, n := 240) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n:
		var th := float(i) / n * PI * 2; var R := costa(th) + desfase
		pts.append(Vector2(R * cos(th), R * sin(th)))
	return pts

static func en_isla(E: float, N: float, margen := 0.0) -> bool:
	return sqrt(E * E + N * N) < costa(atan2(N, E)) - margen

## Altura del terreno (m) en (E, N): llano en el campo de vuelo, cerro al oeste que cae al mar en la costa.
static func altura_terreno(E: float, N: float) -> float:
	var d_costa := costa(atan2(N, E)) - sqrt(E * E + N * N); var k := maxf(0, minf(1, d_costa / 160))
	if E > -110: return 0 * k - 6 * (1 - k)
	var h := altura_tierra_adentro(E, N)
	return h * k - 6 * (1 - k)

static func altura_tierra_adentro(E: float, N: float) -> float:
	var t := minf(1, (-110 - E) / 450); var t2 := minf(1, maxf(0, (-560 - E) / 600))
	return 42 * pow(t, 1.7) + 40 * fbm(E / 260, N / 260) * t * t + 12 * fbm(E / 110, N / 110) * t + 2.5 * fbm(E / 45, N / 45) * t + 30 * t2 * t2

## THREE.Color.setHSL (en el espacio de trabajo lineal de Three: el color sale ya lineal).
static func hsl(h: float, s: float, l: float) -> Color:
	h = fposmod(h, 1.0); s = clampf(s, 0, 1); l = clampf(l, 0, 1)
	if s == 0: return Color(l, l, l)
	var p := l * (1 + s) if l <= 0.5 else l + s - (l * s); var q := 2 * l - p
	var f := func(t: float) -> float:
		if t < 0: t += 1
		if t > 1: t -= 1
		if t < 1.0 / 6: return q + (p - q) * 6 * t
		if t < 1.0 / 2: return p
		if t < 2.0 / 3: return q + (p - q) * 6 * (2.0 / 3 - t)
		return q
	return Color(f.call(h + 1.0 / 3), f.call(h), f.call(h - 1.0 / 3))

## Color de un hex de Three (sRGB) en lineal, como THREE.Color.setHex.
static func lin(c: int) -> Color:
	return Color.hex((c << 8) | 0xff).srgb_to_linear()

const CAMPO := {
	# bancales de almendros: centro (E, N), largo (a lo largo de su norte girado), ancho, giro en grados (+ hacia el
	# este), paso entre muros de bancal y paleta de tonos de la tierra
	"bancales": [
		{ "c": [130, 230], "l": 540, "a": 430, "giro": 20, "paso": 38, "tono": 0 },
		{ "c": [150, -270], "l": 440, "a": 540, "giro": -12, "paso": 32, "tono": 1 },
		{ "c": [-38, 60], "l": 440, "a": 48, "giro": 25, "paso": 45, "tono": 2 },
		{ "c": [640, 160], "l": 780, "a": 440, "giro": 30, "paso": 50, "tono": 3 },
		{ "c": [90, 650], "l": 440, "a": 540, "giro": -30, "paso": 40, "tono": 1 },
		{ "c": [-30, -660], "l": 460, "a": 620, "giro": 8, "paso": 36, "tono": 0 },
		{ "c": [540, -540], "l": 520, "a": 520, "giro": 15, "paso": 42, "tono": 3 },
		{ "c": [-150, -1100], "l": 500, "a": 700, "giro": 0, "paso": 40, "tono": 2 },
		{ "c": [700, 800], "l": 600, "a": 600, "giro": 35, "paso": 48, "tono": 3 },
	],
	"tonos": [["#b3673f", "#a85d38", "#c07a52", "#9c5431"], ["#a65c38", "#9a5230", "#b56b45", "#8f4a2b"],
			  ["#bf7a55", "#b26c47", "#c98a66", "#a8633f"], ["#c8906a", "#bb8260", "#d19d78", "#b07655"]],
	"pistas": [[[0, -6], [-9, 15], [-10, 120], [-4, 200], [20, 262], [60, 330], [150, 470], [330, 770]],   # al cortijo y a la autopista
			   [[0, -6], [6, -40], [-20, -150], [-60, -300], [-70, -620]],
			   [[-9, 100], [-130, 112]], [[-4, 190], [-210, 232]], [[10, -20], [200, -25], [372, -20]]],
	"autopista": { "p0": [330, 790], "p1": [1340, 300], "ancho": 28, "alto": 2.4 },
	"cortijo": [[60, 205, 14, 9, 4.5], [78, 222, 9, 7, 3.5], [66, 233, 6, 5, 3], [690, 60, 40, 18, 7], [690, 20, 25, 12, 5]],   # E, N, ancho E, ancho N, alto
}

# =====================================================================================================================
#  PINTADO DEL SUELO (pintarCampo de visor.js): triangulos con color en coordenadas del mundo (E, N), en el mismo orden
#  que el canvas del navegador; luego se dibujan en un SubViewport 2D con MSAA
# =====================================================================================================================

## Lista de triangulos 2D con color (en trozos de ~200 000 vertices). xf: transformacion de los puntos (bancales girados).
class Trazos:
	var trozos := []
	var pts := PackedVector2Array(); var cols := PackedColorArray(); var idx := PackedInt32Array()
	var xf := Transform2D.IDENTITY

	func _forma() -> int:
		if pts.size() > 200000:
			trozos.append([idx, pts, cols]); pts = PackedVector2Array(); cols = PackedColorArray(); idx = PackedInt32Array()
		return pts.size()

	func cerrar() -> Array:
		if not pts.is_empty(): trozos.append([idx, pts, cols])
		pts = PackedVector2Array(); cols = PackedColorArray(); idx = PackedInt32Array()
		return trozos

	func _v(p: Vector2, c: Color) -> void:
		pts.append(xf * p); cols.append(c)

	## fillRect(x, y, w, h)
	func rect(x: float, y: float, w: float, h: float, c: Color) -> void:
		var b := _forma()
		_v(Vector2(x, y), c); _v(Vector2(x + w, y), c); _v(Vector2(x + w, y + h), c); _v(Vector2(x, y + h), c)
		idx.append_array([b, b + 1, b + 2, b, b + 2, b + 3])

	## ellipse(cx, cy, rx, ry, rot, 0, 7) + fill
	func elipse(cx: float, cy: float, rx: float, ry: float, rot: float, c: Color) -> void:
		var n := clampi(int(ceil(maxf(rx, ry) * 3.5)), 8, 64)
		var b := _forma(); var cr := cos(rot); var sr := sin(rot)
		_v(Vector2(cx, cy), c)
		for k in n:
			var t := TAU * k / n; var x := rx * cos(t); var y := ry * sin(t)
			_v(Vector2(cx + x * cr - y * sr, cy + x * sr + y * cr), c)
			idx.append_array([b, b + 1 + k, b + 1 + (k + 1) % n])

	## Poligono cualquiera (simple) relleno.
	func poligono(P: PackedVector2Array, c: Color) -> void:
		var t := Geometry2D.triangulate_polygon(P)
		var b := _forma()
		for p in P: _v(p, c)
		for i in t: idx.append(b + i)

	## Medio disco (o disco entero) de radio r en p, del lado de dir (extremo redondo de una linea).
	func _disco(p: Vector2, r: float, dir: Vector2, c: Color, entero := false) -> void:
		var n := clampi(int(ceil(r * 3.5)), 8, 48); var a0 := dir.angle() - PI / 2; var arco := TAU if entero else PI
		var b := _forma(); _v(p, c)
		for k in n + 1: _v(p + Vector2.from_angle(a0 + arco * k / n) * r, c)
		for k in n: idx.append_array([b, b + 1 + k, b + 2 + k])

	## stroke() de una polilinea de ancho w. redondo: lineCap/lineJoin "round" (con color transparente no se ponen
	## las uniones, para no oscurecer el solape).
	func linea(P: PackedVector2Array, w: float, c: Color, cerrada := false, redondo := true) -> void:
		var n := P.size(); var segs := n if cerrada else n - 1
		for i in segs:
			var a := P[i]; var bb := P[(i + 1) % n]; var d := bb - a
			if d.length() < 1e-9: continue
			var nn := d.normalized().orthogonal() * (w / 2)
			var b := _forma()
			_v(a + nn, c); _v(bb + nn, c); _v(bb - nn, c); _v(a - nn, c)
			idx.append_array([b, b + 1, b + 2, b, b + 2, b + 3])
		if not redondo: return
		if c.a >= 1:
			for i in (n if cerrada else n - 2):
				_disco(P[(i + 1) % n] if not cerrada else P[i], w / 2, Vector2.RIGHT, c, true)
		if not cerrada:
			_disco(P[0], w / 2, P[0] - P[1], c); _disco(P[n - 1], w / 2, P[n - 1] - P[n - 2], c)

static func _c(s: String, a := 1.0) -> Color:
	var c := Color.html(s); c.a = a
	return c

static func _rgba(r: int, g: int, b: int, a: float) -> Color:
	return Color(r / 255.0, g / 255.0, b / 255.0, a)

## Fondo de un lienzo (depende de su extension): tierra y el pie del cerro con el monte bajo en tres franjas.
static func trazos_fondo(E0: float, N1: float, ancho: float, alto: float) -> Trazos:
	var T := Trazos.new()
	T.rect(E0, N1 - alto, ancho, alto, _c("#b3673f"))
	for fr in [[0.0, 1.0], [22.0, 0.5], [45.0, 0.25]]:     # el monte entra en el campo en tres franjas cada vez mas tenues
		var P := PackedVector2Array([Vector2(E0 - 10, N1 + 10)])
		var N := N1 + 10
		while N >= N1 - alto - 10:
			P.append(Vector2(borde_monte(N) + fr[0], N)); N -= 20
		P.append(Vector2(E0 - 10, N1 - alto - 10))
		T.poligono(P, _rgba(179, 171, 145, fr[1]))
	return T

## El resto de pintarCampo (igual en los dos lienzos): matas, bancales con sus almendros (que se anaden a arboles:
## [E, N, s]), rambla, caminos, autopista, cortijo, aparcamiento, pista 1 y zona 2. Devuelve [cuerpo, costa].
static func trazos_campo(z2: Dictionary, arboles: Array) -> Array:
	var r := Semilla.new(11); var T := Trazos.new()
	for i in 11000:       # matas y piedras del monte bajo, que se van espaciando hacia el campo
		var E := -1600 + r.r() * 1620; var N := -1600 + r.r() * 3200; var d := E - borde_monte(N)
		if d > 0 and r.r() < d / 80: continue
		var mata := r.r() < 0.7
		var col := (_c("#5b6a3c") if r.r() < 0.5 else _c("#6f7a48")) if mata else _c("#c2bba5")
		var rx := 1 + r.r() * 2.2 if mata else 0.6 + r.r() * 1.5
		var ry := 1 + r.r() * 1.8 if mata else 0.5 + r.r()
		T.elipse(E, N, rx, ry, 0, col)
	# bancales: tierra, muros, surcos y la sombra de cada almendro
	var Z: Dictionary = z2["despejado"]
	var pistas: Array = CAMPO["pistas"]
	var excluido := func(E: float, N: float) -> bool:
		if E < borde_monte(N) + 8 or (E > Z["e0"] and E < Z["e1"] and N > Z["n0"] and N < Z["n1"]) or (absf(E) < 11 and N > -2 and N < 82) \
				or (absf(E) < 16 and N > -14 and N < 10) or absf(E - rambla(N)) < 32 or (E > 40 and E < 130 and N > 195 and N < 250) \
				or (E > 660 and E < 730 and N > 0 and N < 90): return true
		for p in pistas:
			for i in range(1, p.size()):
				var x0: float = p[i - 1][0]; var y0: float = p[i - 1][1]; var dx: float = p[i][0] - x0; var dy: float = p[i][1] - y0
				var t := maxf(0, minf(1, ((E - x0) * dx + (N - y0) * dy) / (dx * dx + dy * dy)))
				var ex := E - x0 - t * dx; var ny := N - y0 - t * dy
				if sqrt(ex * ex + ny * ny) < 4.5: return true
		return false
	for b in CAMPO["bancales"]:
		var g: float = b["giro"] * D2R; var cs := cos(g); var sn := sin(g); var pal: Array = CAMPO["tonos"][b["tono"]]
		var l: float = b["l"]; var a: float = b["a"]; var paso: float = b["paso"]; var c0: float = b["c"][0]; var c1: float = b["c"][1]
		T.xf = Transform2D(-g, Vector2(c0, c1))          # el eje v (norte local) gira hacia el este
		var v := -l / 2
		while v < l / 2:
			T.rect(-a / 2, v, a, minf(paso, l / 2 - v), _c(pal[int(floor(r.r() * pal.size()))]))
			T.rect(-a / 2, v, a, 1.2, _rgba(110, 58, 34, 0.55))          # sombra del muro
			T.rect(-a / 2, v + 1.2, a, 1.4, _rgba(226, 190, 150, 0.85))  # muro de piedra seca
			v += paso
		var u := -a / 2
		while u < a / 2:                                                   # surcos
			T.linea(PackedVector2Array([Vector2(u, -l / 2), Vector2(u, l / 2)]), 0.45, _rgba(120, 60, 35, 0.28), false, false)
			u += 1.25
		T.xf = Transform2D.IDENTITY
		v = -l / 2 + 4
		while v < l / 2 - 3:
			u = -a / 2 + 4
			while u < a / 2 - 3:
				if r.r() < 0.08:
					u += 7.5; continue
				var uu := u + (r.r() - 0.5) * 1.2; var vv := v + (r.r() - 0.5) * 1.2
				var E := c0 + uu * cs + vv * sn; var N := c1 - uu * sn + vv * cs
				u += 7.5
				if excluido.call(E, N): continue
				var s := 0.75 + r.r() * 0.5
				if arboles != null: arboles.append([E, N, s])
				T.elipse(E + 1.4 * s, N - 1.1 * s, 1.9 * s, 1.3 * s, 0, _rgba(70, 38, 22, 0.55))
				T.elipse(E, N, 1.55 * s, 1.55 * s, 0, _c("#4f6a2d") if s > 1.05 else _c("#5d7a36"))
			v += 7.5
	# rambla: vegetacion de las orillas, cauce de arena y el canal
	var cauce := PackedVector2Array()
	var Nr := -1600.0
	while Nr <= 1600:
		cauce.append(Vector2(rambla(Nr), Nr)); Nr += 15
	T.linea(cauce, 62, _c("#4b5f31")); T.linea(cauce, 30, _c("#cdbf9f")); T.linea(cauce, 5, _c("#b8a98a"))
	var verdes := [_c("#3d5428"), _c("#4f6b33"), _c("#667a43"), _c("#8a9a5a")]
	for i in 2600:
		var N := -1600 + r.r() * 3200; var lado := -1 if r.r() < 0.5 else 1; var d := 14 + r.r() * 20; var E := rambla(N) + lado * d
		var col: Color = verdes[int(floor(r.r() * 4))]
		var rx := 2 + r.r() * 4; var ry := 1.5 + r.r() * 3; var rot := r.r() * 3
		T.elipse(E, N, rx, ry, rot, col)
	# pistas de tierra
	for p in pistas:
		var P := PackedVector2Array(); for q in p: P.append(Vector2(q[0], q[1]))
		T.linea(P, 4.2, _c("#dcc9a8"))
	for p in pistas:
		var P := PackedVector2Array(); for q in p: P.append(Vector2(q[0], q[1]))
		T.linea(P, 0.9, _rgba(170, 140, 105, 0.55))
	# terraplen de la autopista (la calzada va en 3D encima)
	var A: Dictionary = CAMPO["autopista"]; var AP := PackedVector2Array([Vector2(A["p0"][0], A["p0"][1]), Vector2(A["p1"][0], A["p1"][1])])
	T.linea(AP, 64, _c("#c2a98a")); T.linea(AP, A["ancho"], _c("#5e5e5e"))
	# era del cortijo y las naves
	T.rect(45, 196, 80, 50, _c("#d8c6a7")); T.rect(662, 2, 66, 86, _c("#d8c6a7"))
	# aparcamiento de grava y pista de tierra compactada con sus marcas de cal
	T.elipse(0, -2, 14, 9, 0, _c("#ccbfa7"))
	T.rect(-7, 7, 14, 67, _c("#d4bd98"))
	T.rect(-5, 9, 10, 62, _c("#c6ac86"))
	var E1 := -4.6
	while E1 < 5:
		T.linea(PackedVector2Array([Vector2(E1, 9), Vector2(E1, 71)]), 0.3, _rgba(140, 110, 80, 0.5)); E1 += 0.9
	var cal := _rgba(255, 255, 255, 0.9)
	for N in [10.5, 68.5]: T.rect(-4.5, N, 9, 1.0, cal)
	var N2 := 15.0
	while N2 < 66:
		T.rect(-0.18, N2, 0.36, 2.2, cal); N2 += 5
	# zona 2 (detras del piloto): pista 2 de este a oeste con la diana de cal en el centro y la linea de la puerta
	var P2: Dictionary = z2["pista"]; var D: Dictionary = z2["diana"]; var Pu: Dictionary = z2["puerta"]
	T.rect(P2["e0"] - 2, P2["n"] - P2["ancho"] / 2 - 2, P2["e1"] - P2["e0"] + 4, P2["ancho"] + 4, _c("#d4bd98"))
	T.rect(P2["e0"], P2["n"] - P2["ancho"] / 2, P2["e1"] - P2["e0"], P2["ancho"], _c("#c6ac86"))
	var Nz: float = P2["n"] - P2["ancho"] / 2 + 0.4
	while Nz < P2["n"] + P2["ancho"] / 2:
		T.linea(PackedVector2Array([Vector2(P2["e0"], Nz), Vector2(P2["e1"], Nz)]), 0.3, _rgba(140, 110, 80, 0.5)); Nz += 0.9
	for E in [P2["e0"] + 0.5, P2["e1"] - 1.5]: T.rect(E, P2["n"] - P2["ancho"] / 2 + 0.5, 1.0, P2["ancho"] - 1, cal)   # umbrales
	for an in D["anillos"]:
		var C := PackedVector2Array(); var ra: float = an[0]; var n := maxi(48, int(ra * 8))
		for k in n: C.append(Vector2(D["e"] + ra * cos(TAU * k / n), D["n"] + ra * sin(TAU * k / n)))
		T.linea(C, 0.45, _rgba(255, 255, 255, 0.92), true)
	var cal2 := _rgba(255, 255, 255, 0.92)
	T.elipse(D["e"], D["n"], 0.8, 0.8, 0, cal2)
	var Np: float = Pu["n0"] + 2
	while Np < Pu["n1"] - 1.5:
		T.rect(Pu["e"] - 0.2, Np, 0.4, 1.4, cal2); Np += 2.4                                          # linea de la puerta
	# la costa (solo en la textura lejana): agua somera, playa y espuma
	var K := Trazos.new()
	K.linea(poligono_costa(35), 70, _c("#4f9fb8"), true); K.linea(poligono_costa(-42), 84, _c("#e3d5b2"), true)
	K.linea(poligono_costa(0), 6, _rgba(255, 255, 255, 0.75), true)
	return [T, K]

## Grano fino de la tierra: tesela de 256 px que multiplica el lienzo (globalAlpha 0,28, "multiply").
static func _grano() -> ImageTexture:
	var img := Image.create(256, 256, false, Image.FORMAT_RGB8); var rr := Semilla.new(3)
	for y in 256:
		for x in 256:
			var v := clampf(roundf(150 + rr.r() * 110), 0, 255)
			var g := 1 - 0.28 + 0.28 * v / 255.0
			img.set_pixel(x, y, Color(g, g, g))
	return ImageTexture.create_from_image(img)

## Pinta los dos lienzos del suelo en la GPU y se los pone a los materiales del suelo (cerca: 4096 px para 1400 m;
## lejos: 2048 px para 6000 m).
func _pintar_suelos(cuerpo: Array, costa_: Array, fondo_cerca: Trazos, fondo_lejos: Trazos) -> void:
	var svp := SubViewport.new(); svp.size = Vector2i(LIENZO_TESELA, LIENZO_TESELA); svp.disable_3d = true
	svp.msaa_2d = Viewport.MSAA_4X; svp.transparent_bg = false; svp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(svp)
	await get_tree().process_frame
	var RS := RenderingServer; var canvas := svp.find_world_2d().canvas; var items := []
	var nuevo := func(z: int) -> RID:
		var it := RS.canvas_item_create(); RS.canvas_item_set_parent(it, canvas); RS.canvas_item_set_draw_index(it, z); items.append(it)
		return it
	var añadir := func(it: RID, trozos: Array) -> void:
		for t in trozos: RS.canvas_item_add_triangle_array(it, t[0], t[1], t[2])
	var i_fc: RID = nuevo.call(0); añadir.call(i_fc, fondo_cerca.cerrar())
	var i_fl: RID = nuevo.call(1); añadir.call(i_fl, fondo_lejos.cerrar())
	var i_cu: RID = nuevo.call(2); añadir.call(i_cu, cuerpo)
	var i_co: RID = nuevo.call(3); añadir.call(i_co, costa_)
	var i_gr: RID = nuevo.call(4)
	var grano := _grano(); var mat_mul := CanvasItemMaterial.new(); mat_mul.blend_mode = CanvasItemMaterial.BLEND_MODE_MUL
	RS.canvas_item_set_material(i_gr, mat_mul.get_rid())
	RS.canvas_item_set_default_texture_repeat(i_gr, RenderingServer.CANVAS_ITEM_TEXTURE_REPEAT_ENABLED)
	RS.canvas_item_set_default_texture_filter(i_gr, RenderingServer.CANVAS_ITEM_TEXTURE_FILTER_NEAREST)
	RS.canvas_item_add_texture_rect(i_gr, Rect2(0, 0, 4096, 4096), grano.get_rid(), true)
	var imgs := []
	for lienzo in [[4096, 1400.0, -700.0, 900.0, true], [2048, 6000.0, -3000.0, 3000.0, false]]:
		var W: int = lienzo[0]; var k: float = W / lienzo[1]; var E0: float = lienzo[2]; var N1: float = lienzo[3]; var cerca: bool = lienzo[4]
		var xf := Transform2D(Vector2(k, 0), Vector2(0, -k), Vector2(-E0 * k, N1 * k))
		for it in [i_fc, i_fl, i_cu, i_co]: RS.canvas_item_set_transform(it, xf)
		RS.canvas_item_set_visible(i_fc, cerca); RS.canvas_item_set_visible(i_fl, not cerca); RS.canvas_item_set_visible(i_co, not cerca)
		var img := Image.create(W, W, false, Image.FORMAT_RGBA8)
		for ty in W / LIENZO_TESELA:
			for tx in W / LIENZO_TESELA:
				svp.canvas_transform = Transform2D(0, Vector2(-tx * LIENZO_TESELA, -ty * LIENZO_TESELA))
				svp.render_target_update_mode = SubViewport.UPDATE_ONCE
				await get_tree().process_frame
				await RenderingServer.frame_post_draw
				var t := svp.get_texture().get_image() if is_inside_tree() else null
				if t == null or t.is_empty():           # sin GPU (--headless) o ya sin escena: el suelo se queda de color tierra
					for it in items: RS.free_rid(it)
					svp.queue_free(); return
				if t.get_format() != Image.FORMAT_RGBA8: t.convert(Image.FORMAT_RGBA8)
				img.blit_rect(t, Rect2i(0, 0, LIENZO_TESELA, LIENZO_TESELA), Vector2i(tx * LIENZO_TESELA, ty * LIENZO_TESELA))
		imgs.append(img)
	for it in items: RS.free_rid(it)
	svp.queue_free()
	for i in 2:
		var img: Image = imgs[i]; img.convert(Image.FORMAT_RGB8); img.generate_mipmaps()
		img.compress(Image.COMPRESS_S3TC, Image.COMPRESS_SOURCE_SRGB)      # 8 veces menos memoria de video
		var mat := _mat_cerca if i == 0 else _mat_lejos
		mat.albedo_texture = ImageTexture.create_from_image(img); mat.albedo_color = Color.WHITE
	listo = true
	suelo_listo.emit()

# =====================================================================================================================
#  GEOMETRIAS DE THREE (mismos vertices; Godot quiere las caras en sentido horario: se invierte el orden)
# =====================================================================================================================

static func _malla(pos: PackedVector3Array, nor: PackedVector3Array, idx: PackedInt32Array, uv := PackedVector2Array(), col := PackedColorArray()) -> ArrayMesh:
	var arr := []; arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = pos; arr[Mesh.ARRAY_NORMAL] = nor
	if not idx.is_empty(): arr[Mesh.ARRAY_INDEX] = idx
	if not uv.is_empty(): arr[Mesh.ARRAY_TEX_UV] = uv
	if not col.is_empty(): arr[Mesh.ARRAY_COLOR] = col
	var am := ArrayMesh.new(); am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return am

## THREE.CylinderGeometry(rt, rb, h, radiales, 1, abierto) (y ConeGeometry con rt = 0). UV de Godot: v = 0 arriba.
static func cilindro(rt: float, rb: float, h: float, radiales: int, abierto := false) -> ArrayMesh:
	var pos := PackedVector3Array(); var nor := PackedVector3Array(); var uv := PackedVector2Array(); var idx := PackedInt32Array()
	var pend := (rb - rt) / h
	for y in 2:
		var r := rt if y == 0 else rb
		for x in radiales + 1:
			var u := float(x) / radiales; var th := u * TAU
			pos.append(Vector3(r * sin(th), h / 2 - y * h, r * cos(th)))
			nor.append(Vector3(sin(th), pend, cos(th)).normalized()); uv.append(Vector2(u, y))
	for x in radiales:
		var a := x; var b := radiales + 1 + x; var c := radiales + 2 + x; var d := x + 1
		if rt > 0: idx.append_array([a, d, b])
		if rb > 0: idx.append_array([b, d, c])
	if not abierto:
		for tapa in [[rt, 1.0], [rb, -1.0]]:
			if tapa[0] <= 0: continue
			var sg: float = tapa[1]; var y0 := h / 2 * sg; var c0 := pos.size()
			for x in radiales:
				pos.append(Vector3(0, y0, 0)); nor.append(Vector3(0, sg, 0)); uv.append(Vector2(0.5, 0.5))
			var c1 := pos.size()
			for x in radiales + 1:
				var th := float(x) / radiales * TAU
				pos.append(Vector3(tapa[0] * sin(th), y0, tapa[0] * cos(th))); nor.append(Vector3(0, sg, 0))
				uv.append(Vector2(cos(th) * 0.5 + 0.5, 1 - (sin(th) * 0.5 * sg + 0.5)))
			for x in radiales:
				if sg > 0: idx.append_array([c1 + x, c1 + x + 1, c0 + x])
				else: idx.append_array([c1 + x + 1, c1 + x, c0 + x])
	return _malla(pos, nor, idx, uv)

## THREE.IcosahedronGeometry(radio, detalle): caras planas con detalle 0, normales suaves con mas detalle.
static func icosaedro(radio: float, detalle: int) -> ArrayMesh:
	var t := (1 + sqrt(5.0)) / 2
	var V := [-1, t, 0, 1, t, 0, -1, -t, 0, 1, -t, 0, 0, -1, t, 0, 1, t, 0, -1, -t, 0, 1, -t, t, 0, -1, t, 0, 1, -t, 0, -1, -t, 0, 1]
	var I := [0, 11, 5, 0, 5, 1, 0, 1, 7, 0, 7, 10, 0, 10, 11, 1, 5, 9, 5, 11, 4, 11, 10, 2, 10, 7, 6, 7, 1, 8,
			  3, 9, 4, 3, 4, 2, 3, 2, 6, 3, 6, 8, 3, 8, 9, 4, 9, 5, 2, 4, 11, 6, 2, 10, 8, 6, 7, 9, 8, 1]
	var vv := func(i: int) -> Vector3: return Vector3(V[3 * i], V[3 * i + 1], V[3 * i + 2])
	var tris := []
	for f in range(0, I.size(), 3):
		var a: Vector3 = vv.call(I[f]); var b: Vector3 = vv.call(I[f + 1]); var c: Vector3 = vv.call(I[f + 2])
		var cols := detalle + 1; var v := []
		for i in cols + 1:
			v.append([]); var aj := a.lerp(c, float(i) / cols); var bj := b.lerp(c, float(i) / cols); var filas := cols - i
			for j in filas + 1: v[i].append(aj if j == 0 and i == cols else aj.lerp(bj, float(j) / filas))
		for i in cols:
			for j in 2 * (cols - i) - 1:
				var k := int(floor(j / 2.0))
				if j % 2 == 0: tris.append([v[i][k + 1], v[i + 1][k], v[i][k]])
				else: tris.append([v[i][k + 1], v[i + 1][k + 1], v[i + 1][k]])
	var pos := PackedVector3Array(); var nor := PackedVector3Array()
	for tr in tris:
		var a: Vector3 = tr[0].normalized() * radio; var b: Vector3 = tr[1].normalized() * radio; var c: Vector3 = tr[2].normalized() * radio
		pos.append_array([a, c, b])
		if detalle == 0:
			var n := (b - a).cross(c - a).normalized(); nor.append_array([n, n, n])
		else: nor.append_array([a.normalized(), c.normalized(), b.normalized()])
	return _malla(pos, nor, PackedInt32Array())

## Material Lambert de Three: difuso sin brillo (sin reflejos del cielo).
static func lambert(c: Color, tex: Texture2D = null, color_vertices := false, doble := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new(); m.albedo_color = c; m.roughness = 1.0; m.metallic_specular = 0.0
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT; m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	if tex != null:
		m.albedo_texture = tex; m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	m.vertex_color_use_as_albedo = color_vertices
	if doble: m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m

func _mi(mesh: Mesh, mat: Material, pos := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new(); mi.mesh = mesh; mi.material_override = mat; mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF      # en el navegador solo el avion da sombra
	add_child(mi)
	return mi

static func _caja(x: float, y: float, z: float) -> BoxMesh:
	var b := BoxMesh.new(); b.size = Vector3(x, y, z)
	return b

## Textura de un Image con mipmaps (sRGB).
static func _tex(img: Image) -> ImageTexture:
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

## fillRect con antialias de un lienzo pequeno (cobertura fraccionaria de cada pixel), sobre un Image.
static func _rect_img(img: Image, x: float, y: float, w: float, h: float, c: Color) -> void:
	for py in range(maxi(0, int(floor(y))), mini(img.get_height(), int(ceil(y + h)))):
		var cy := minf(py + 1, y + h) - maxf(py, y)
		for px in range(maxi(0, int(floor(x))), mini(img.get_width(), int(ceil(x + w)))):
			var cb := cy * (minf(px + 1, x + w) - maxf(px, x)) * c.a
			if cb <= 0: continue
			var d := img.get_pixel(px, py); var o := d.lerp(Color(c.r, c.g, c.b, 1), cb); o.a = d.a + cb * (1 - d.a)
			img.set_pixel(px, py, o)

# =====================================================================================================================
#  CONSTRUCCION
# =====================================================================================================================

## Construye la isla. e: el Entorno (con la isla puesta: e.poner_mundo({})); de el salen la pista, los pilones y la zona 2.
func construir(e: Entorno) -> void:
	ent = e
	_cielo_y_luz()
	_campo()
	aplicar_calidad(calidad)

## Visibilidad segun la calidad (Visor.aplicarCalidad): almendros lejanos con 2, nubes y matas con 1 o 2, sombras con 1 o 2.
func aplicar_calidad(q: int) -> void:
	calidad = q
	for m in lejanos: m.visible = q >= 2
	for m in prescindibles: m.visible = q >= 1
	if sol: sol.shadow_enabled = q >= 1

# ---------------------------------------------------------------- cielo, sol, calima, nubes
const SHADER_CIELO_FN := """
// Cielo fisico de Three (examples/jsm/objects/Sky.js, modelo de Preetham) con turbidity 3,5, rayleigh 2,2,
// mieCoefficient 0,003 y mieDirectionalG 0,8, como en el navegador. Devuelve el color antes del mapeo de tonos.
uniform vec3 sol_dir = vec3(-0.5157, 0.7663, 0.3831);
const float e_ = 2.71828182845904523536028747135266249775724709369995957;
const float pi_ = 3.141592653589793238462643383279502884197169;
const vec3 totalRayleigh = vec3(5.804542996261093E-6, 1.3562911419845635E-5, 3.0265902468824876E-5);
const vec3 MieConst = vec3(1.8399918514433978E14, 2.7798023919660528E14, 4.0790479543861094E14);
const float cutoffAngle = 1.6110731556870734;
const float steepness = 1.5;
const float EE = 1000.0;
const float rayleighZenithLength = 8.4E3;
const float mieZenithLength = 1.25E3;
const float sunAngularDiameterCos = 0.999956676946448443553574619906976478926848692873900859324;
const float THREE_OVER_SIXTEENPI = 0.05968310365946075;
const float ONE_OVER_FOURPI = 0.07957747154594767;
vec3 cielo_three(vec3 direction) {
	float turbidity = 3.5; float rayleigh = 2.2; float mieCoefficient = 0.003; float mieDirectionalG = 0.8;
	vec3 up = vec3(0.0, 1.0, 0.0);
	vec3 vSunDirection = normalize(sol_dir);
	float zc = clamp(dot(vSunDirection, up), -1.0, 1.0);
	float vSunE = EE * max(0.0, 1.0 - pow(e_, -((cutoffAngle - acos(zc)) / steepness)));
	float vSunfade = 1.0 - clamp(1.0 - exp((vSunDirection.y / 450000.0)), 0.0, 1.0);
	float rayleighCoefficient = rayleigh - (1.0 * (1.0 - vSunfade));
	vec3 vBetaR = totalRayleigh * rayleighCoefficient;
	vec3 vBetaM = 0.434 * ((0.2 * turbidity) * 10E-18) * MieConst * mieCoefficient;
	float zenithAngle = acos(max(0.0, dot(up, direction)));
	float inverse = 1.0 / (cos(zenithAngle) + 0.15 * pow(93.885 - ((zenithAngle * 180.0) / pi_), -1.253));
	float sR = rayleighZenithLength * inverse;
	float sM = mieZenithLength * inverse;
	vec3 Fex = exp(-(vBetaR * sR + vBetaM * sM));
	float cosTheta = dot(direction, vSunDirection);
	float rPhase = THREE_OVER_SIXTEENPI * (1.0 + pow(cosTheta * 0.5 + 0.5, 2.0));
	vec3 betaRTheta = vBetaR * rPhase;
	float g2 = pow(mieDirectionalG, 2.0);
	float mPhase = ONE_OVER_FOURPI * ((1.0 - g2) * (1.0 / pow(1.0 - 2.0 * mieDirectionalG * cosTheta + g2, 1.5)));
	vec3 betaMTheta = vBetaM * mPhase;
	vec3 Lin = pow(vSunE * ((betaRTheta + betaMTheta) / (vBetaR + vBetaM)) * (1.0 - Fex), vec3(1.5));
	Lin *= mix(vec3(1.0), pow(vSunE * ((betaRTheta + betaMTheta) / (vBetaR + vBetaM)) * Fex, vec3(1.0 / 2.0)), clamp(pow(1.0 - dot(up, vSunDirection), 5.0), 0.0, 1.0));
	vec3 L0 = vec3(0.1) * Fex;
	float sundisk = smoothstep(sunAngularDiameterCos, sunAngularDiameterCos + 0.00002, cosTheta);
	L0 += (vSunE * 19000.0 * Fex) * sundisk;
	vec3 texColor = (Lin + L0) * 0.04 + vec3(0.0, 0.0003, 0.00075);
	return pow(texColor, vec3(1.0 / (1.2 + (1.2 * vSunfade))));
}
"""

const SHADER_CIELO := """
shader_type sky;
// El fondo es el cielo de Three; la luz ambiente (el mapa de radiancia) es la HemisphereLight del navegador: el color
// del cielo arriba y el de la tierra rojiza abajo (Godot la convoluciona: 0,5 + 0,5 n.y, como la de Three).
uniform vec3 hemi_cielo;
uniform vec3 hemi_suelo;
%s
void sky() {
	if (AT_CUBEMAP_PASS) COLOR = EYEDIR.y >= 0.0 ? hemi_cielo : hemi_suelo;
	else COLOR = cielo_three(EYEDIR);
}
"""

## Exposicion de Three (0,5 con su ACES, que divide por 0,6) en el ACES de Godot (que multiplica por 1,8); con blanco 16
## los dos dan lo mismo (medido: menos de 1/255 de diferencia).
const EXPOSICION := 0.5 / 0.6 / 1.8
## Color de la calima antes del mapeo de tonos: en el navegador la niebla se mezcla DESPUES (lo lejano acaba en
## #d3dfe9 en pantalla); aqui se mezcla antes, asi que se usa el color que, tras el ACES, da #d3dfe9.
const NIEBLA_LINEAL := Vector3(1.2120, 1.8049, 2.6129)

func _cielo_y_luz() -> void:
	var we := WorldEnvironment.new(); var env := Environment.new()
	var sky := Sky.new(); var sm := ShaderMaterial.new(); var sh := Shader.new(); sh.code = SHADER_CIELO % SHADER_CIELO_FN; sm.shader = sh
	# HemisphereLight(0xd9e8ff, 0x8a5a3a, 0,72 * 2 pi): en Three la luz difusa se divide por pi -> 1,44 x color. Va en el
	# propio mapa de radiancia: con todo el ambiente del cielo (sky_contribution 1) Godot no usa ambient_light_energy
	var hc := lin(0xd9e8ff); var hs := lin(0x8a5a3a); var kh := 0.72 * 2
	sm.set_shader_parameter("hemi_cielo", Vector3(hc.r, hc.g, hc.b) * kh); sm.set_shader_parameter("hemi_suelo", Vector3(hs.r, hs.g, hs.b) * kh)
	sm.set_shader_parameter("sol_dir", SOL.normalized())
	sky.sky_material = sm; sky.radiance_size = Sky.RADIANCE_SIZE_64; env.sky = sky; env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY; env.ambient_light_sky_contribution = 1.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES; env.tonemap_exposure = EXPOSICION; env.tonemap_white = 16.0
	# calima: niebla de 450 a 2700 m (THREE.Fog(0xd3dfe9, 450, 2700), lineal); el cielo no lleva niebla. Como aqui se mezcla
	# antes del mapeo de tonos con un color muy brillante, la curva 2,5 hace que la mezcla se vea como la lineal de Three
	# (ajustada sobre suelo, monte, arboles y pista)
	var nm := NIEBLA_LINEAL; var en := maxf(nm.x, maxf(nm.y, nm.z))
	env.fog_enabled = true; env.fog_mode = Environment.FOG_MODE_DEPTH; env.fog_density = 1.0
	env.fog_depth_begin = 450.0; env.fog_depth_end = 2700.0; env.fog_depth_curve = 2.5
	env.fog_light_color = Color(nm.x / en, nm.y / en, nm.z / en).linear_to_srgb(); env.fog_light_energy = en
	env.fog_sun_scatter = 0.0; env.fog_aerial_perspective = 0.0; env.fog_sky_affect = 0.0
	we.environment = env; add_child(we)
	# sol: DirectionalLight(0xfff1dc, 1,05 * 2 pi) en (-350, 520, 260): en Three la luz difusa se divide por pi -> 2,1
	sol = DirectionalLight3D.new()
	sol.look_at_from_position(SOL.normalized(), Vector3.ZERO, Vector3.UP)
	sol.light_energy = 1.05 * 2; sol.light_color = Color.hex(0xfff1dcff); sol.light_specular = 0.0
	sol.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS; sol.directional_shadow_max_distance = 250.0
	sol.shadow_bias = 0.03; sol.shadow_normal_bias = 1.0
	add_child(sol)
	_nubes()

## Nubes lejanas (sprites con 26 manchas de degradado radial), como Visor._cielo.
func _nubes() -> void:
	var r := Semilla.new(5); var W := 256; var H := 128
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8); img.fill(Color(0, 0, 0, 0))
	var paradas := [[0.0, Color8(255, 255, 255), 0.75], [0.6, Color8(250, 250, 252), 0.35], [1.0, Color8(245, 245, 250), 0.0]]
	for i in 26:
		var x := 40 + r.r() * 176; var y := 50 + r.r() * 40; var rad := 18 + r.r() * 26
		for py in range(maxi(0, int(y - rad)), mini(H, int(ceil(y + rad)) + 1)):
			for px in range(maxi(0, int(x - rad)), mini(W, int(ceil(x + rad)) + 1)):
				var t := Vector2(px + 0.5 - x, py + 0.5 - y).length() / rad
				if t >= 1: continue
				var k := 0 if t < 0.6 else 1; var f: float = (t - paradas[k][0]) / (paradas[k + 1][0] - paradas[k][0])
				var c: Color = (paradas[k][1] as Color).lerp(paradas[k + 1][1], f); var a: float = lerpf(paradas[k][2], paradas[k + 1][2], f)
				var d := img.get_pixel(px, py); var oa := a + d.a * (1 - a)
				if oa <= 0: continue
				var o := (c * a + d * d.a * (1 - a)) / oa; o.a = oa
				img.set_pixel(px, py, o)
	var tex := _tex(img)
	for i in 14:
		var a := r.r() * PI * 2; var d := 900 + r.r() * 1400; var s := 260 + r.r() * 420
		var nube := Sprite3D.new(); nube.texture = tex; nube.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		nube.pixel_size = s / W; nube.scale = Vector3(1, 0.42 * W / H, 1); nube.modulate = Color(1, 1, 1, 0.9)
		nube.shaded = false; nube.double_sided = true; nube.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		nube.position = Vector3(d * cos(a), 420 + r.r() * 380, d * sin(a))
		add_child(nube); prescindibles.append(nube)

# ---------------------------------------------------------------- mar
const SHADER_AGUA := """
shader_type spatial;
render_mode unshaded;
// THREE.Water del navegador (calidad 2): reflejo (aqui el cielo de Three en la direccion reflejada; el navegador refleja
// la escena entera con un espejo), dispersion del color del agua, brillo del sol y oleaje con mapas de normales.
uniform vec3 color_agua;
uniform vec3 color_sol;
uniform sampler2D ondas : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D ondas_g : hint_normal, filter_linear_mipmap, repeat_enable;
varying vec3 pm;
%s
void vertex() { pm = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float t = TIME * 0.6;
	vec2 uv = pm.xz * 2.5;
	vec3 n = texture(ondas, uv / 103.0 + vec2(t / 17.0, t / 29.0)).rgb + texture(ondas, uv / 107.0 - vec2(t / -19.0, t / 31.0)).rgb
		+ texture(ondas_g, uv / vec2(8907.0, 9803.0) + vec2(t / 101.0, t / 97.0)).rgb + texture(ondas_g, uv / vec2(1091.0, 1027.0) - vec2(t / 109.0, t / -113.0)).rgb;
	n = n * 0.5 - 1.0;
	vec3 sn = normalize(vec3(n.x, n.z, -n.y) * vec3(1.5, 1.0, 1.5));
	vec3 ojo = CAMERA_POSITION_WORLD - pm; vec3 eyeDirection = normalize(ojo);
	vec3 sd = normalize(sol_dir);
	float dirsol = max(0.0, dot(eyeDirection, normalize(reflect(-sd, sn))));
	vec3 specularLight = pow(dirsol, 100.0) * color_sol * 2.0;
	vec3 diffuseLight = max(dot(sd, sn), 0.0) * color_sol * 0.5;
	vec3 rd = reflect(-eyeDirection, sn); rd.y = abs(rd.y);
	vec3 reflectionSample = cielo_three(normalize(rd));
	float theta = max(dot(eyeDirection, sn), 0.0);
	float reflectance = 0.3 + 0.7 * pow(1.0 - theta, 5.0);
	vec3 scatter = max(0.0, dot(sn, eyeDirection)) * color_agua;
	ALBEDO = mix(color_sol * diffuseLight * 0.3 + scatter, vec3(0.1) + reflectionSample * 0.9 + reflectionSample * specularLight, reflectance);
}
"""

static func _ondas(frec: float, semilla_: int, fuerza: float) -> NoiseTexture2D:
	var nt := NoiseTexture2D.new(); nt.width = 512; nt.height = 512; nt.seamless = true; nt.as_normal_map = true
	nt.bump_strength = fuerza; nt.generate_mipmaps = true
	var fn := FastNoiseLite.new(); fn.frequency = frec; fn.seed = semilla_; fn.fractal_octaves = 4; nt.noise = fn
	return nt

## Mar a 1,2 m bajo el suelo (nunca parpadea sobre la isla), de 40 km. Calidad 2: el agua con reflejos; menos: un plano
## con el brillo del sol (MeshPhongMaterial 0x245f88).
func _mar() -> void:
	var pm := PlaneMesh.new(); pm.size = Vector2(40000, 40000)
	var mat: Material
	if calidad >= 2:
		var sh := Shader.new(); sh.code = SHADER_AGUA % SHADER_CIELO_FN
		var m := ShaderMaterial.new(); m.shader = sh
		var ca := lin(0x245f88); var cs := lin(0xfff4e0)
		m.set_shader_parameter("color_agua", Vector3(ca.r, ca.g, ca.b)); m.set_shader_parameter("color_sol", Vector3(cs.r, cs.g, cs.b))
		m.set_shader_parameter("sol_dir", SOL.normalized())
		m.set_shader_parameter("ondas", _ondas(0.02, 91, 4.0)); m.set_shader_parameter("ondas_g", _ondas(0.01, 92, 3.0))
		mat = m
	else:
		var m := StandardMaterial3D.new(); m.albedo_color = Color.hex(0x245f88ff); m.roughness = 0.3; m.metallic_specular = 0.6
		m.normal_enabled = true; m.normal_texture = _ondas(0.02, 91, 4.0); m.normal_scale = 0.35; m.uv1_scale = Vector3(1000, 1000, 1)
		mat = m
	_mi(pm, mat, Vector3(0, -1.2, 0))

# ---------------------------------------------------------------- el campo (Visor._campo)
## Mallas instanciadas por celdas de 300 m (Visor._instanciar). lista: [E, N, ...]; colocar(item) -> [Transform3D, Color
## lineal]. Las celdas a mas de lejos_m del campo van a lejanos. Devuelve los nodos creados.
func _instanciar(mesh: Mesh, mat: Material, lista: Array, colocar: Callable, lejos_m := 520.0) -> Array:
	var celdas := {}
	for it in lista:
		var k := Vector2i(floori(it[0] / 300.0), floori(it[1] / 300.0))
		if not celdas.has(k): celdas[k] = []
		celdas[k].append(it)
	var nodos := []
	for k in celdas:
		var items: Array = celdas[k]
		var mm := MultiMesh.new(); mm.transform_format = MultiMesh.TRANSFORM_3D; mm.use_colors = true; mm.mesh = mesh
		mm.instance_count = items.size()
		var cx := 0.0; var cz := 0.0
		for i in items.size():
			var res: Array = colocar.call(items[i])
			mm.set_instance_transform(i, res[0]); mm.set_instance_color(i, res[1])
			cx += items[i][0]; cz -= items[i][1]
		cx /= items.size(); cz /= items.size()
		var mmi := MultiMeshInstance3D.new(); mmi.multimesh = mm; mmi.material_override = mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi); nodos.append(mmi)
		if Vector2(cx, cz + 110).length() > lejos_m: lejanos.append(mmi)
	return nodos

static func _tr(P: Vector3, ang: float, S: Vector3) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, ang).scaled_local(S), P)

func _campo() -> void:
	var r := Semilla.new(23)
	# suelo: un lienzo de detalle de 1400 m alrededor del campo de vuelo y otro lejano de 6000 m (se pintan en la GPU)
	_arboles = []
	var tz := trazos_campo(ent.zona2, _arboles)
	var cuerpo: Array = tz[0].cerrar(); var costa_: Array = tz[1].cerrar()
	_mat_cerca = lambert(Color.html("#b3673f")); _mat_lejos = lambert(Color.html("#b3673f"))
	for m in [_mat_cerca, _mat_lejos]: m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	# cerca: 1400 x 1400 m, de E -700 a 700 y de N 900 a -500, a 1 cm
	var pos := PackedVector3Array([Vector3(-700, 0.01, -900), Vector3(700, 0.01, -900), Vector3(700, 0.01, 500), Vector3(-700, 0.01, 500)])
	var nor := PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP])
	_mi(_malla(pos, nor, PackedInt32Array([0, 1, 2, 0, 2, 3]), PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])), _mat_cerca)
	# lejos: la isla (costa + 70 m) con un hueco bajo la textura cercana; UV: E / 6000 + 0,5
	var isla := poligono_costa(70)
	var piezas := [Rect2(-10000, 900, 20000, 10000), Rect2(-10000, -10500, 20000, 10000), Rect2(-10000, -500, 9300, 1400), Rect2(700, -500, 9300, 1400)]
	pos = PackedVector3Array(); nor = PackedVector3Array(); var uv := PackedVector2Array(); var idx := PackedInt32Array()
	for rc in piezas:
		var R := PackedVector2Array([rc.position, rc.position + Vector2(rc.size.x, 0), rc.end, rc.position + Vector2(0, rc.size.y)])
		for P in Geometry2D.intersect_polygons(isla, R):
			var t := Geometry2D.triangulate_polygon(P); var b := pos.size()
			for p in P:
				pos.append(Vector3(p.x, 0, -p.y)); nor.append(Vector3.UP); uv.append(Vector2(p.x / 6000 + 0.5, 0.5 - p.y / 6000))
			for i in range(0, t.size(), 3):
				var A := pos[b + t[i]]; var B := pos[b + t[i + 1]]; var C := pos[b + t[i + 2]]
				if (C - A).cross(B - A).y > 0: idx.append_array([b + t[i], b + t[i + 1], b + t[i + 2]])
				else: idx.append_array([b + t[i], b + t[i + 2], b + t[i + 1]])
	_mi(_malla(pos, nor, idx, uv), _mat_lejos)
	_mar()
	_cerro()
	# almendros en reticula (instancias): tronco y copa; los de cerca con mas detalle que los lejanos
	var m_tronco := lambert(Color.hex(0x5b4330ff), null, true); var m_copa := lambert(Color.WHITE, null, true)
	for banda in [[0.0, 150.0, 1], [150.0, 680.0, 0]]:      # solo cerca del campo las copas llevan mas caras
		var lista := _arboles.filter(func(a): var d := Vector2(a[0], a[1] - 110).length(); return d >= banda[0] and d < banda[1])
		_instanciar(cilindro(0.08, 0.14, 1.0, 5), m_tronco, lista, func(it: Array) -> Array:
			var s: float = it[2]
			return [_tr(Vector3(it[0], 0.5 * s, -it[1]), r.r() * 6.28, Vector3(s, s, s)), Color.WHITE])
		_instanciar(icosaedro(1.3, banda[2]), m_copa, lista, func(it: Array) -> Array:
			var s: float = it[2]
			var S := Vector3(s * (0.85 + 0.35 * r.r()), s * 0.68, 0); S.z = s * (0.85 + 0.35 * r.r())
			var tr := _tr(Vector3(it[0], 1.55 * s, -it[1]), r.r() * 6.28, S)
			var hh := 0.22 + 0.06 * r.r(); var ss := 0.26 + 0.16 * r.r(); var ll := 0.2 + 0.09 * r.r()
			return [tr, hsl(hh, ss, ll)])
	# arboles grandes (algarrobos y pinos) sueltos, matorral de la rambla y matas del cerro
	var grandes := []
	var Z: Dictionary = ent.zona2["despejado"]
	for i in 70:
		var Ex := -300 + r.r() * 1100; var Nn := -700 + r.r() * 1500
		if Vector2(Ex, Nn - 40).length() < 95 or (Ex > Z["e0"] - 10 and Ex < Z["e1"] + 10 and Nn > Z["n0"] - 10 and Nn < Z["n1"] + 10) \
				or absf(Ex - rambla(Nn)) < 36 or not en_isla(Ex, Nn, 80): continue
		var s := 2.2 + r.r() * 2.2
		grandes.append([Ex, Nn, s, r.r() < 0.4])
	for i in 36:
		var Nn := -600 + r.r() * 1300; var lado := -1 if r.r() < 0.5 else 1; var dd := 18 + r.r() * 12
		var s := 2.6 + r.r() * 2.4
		grandes.append([rambla(Nn) + lado * dd, Nn, s, false])
	for a in [[52, 240, 4.2, false], [100, 198, 3.6, false], [-18, 207, 3.4, true], [120, 240, 3.8, false]]: grandes.append(a)
	# arboles solidos de la isla (Entorno.choca_arbol): almendros (copa de 1,1 s de radio hasta 2,4 s) y los grandes
	var solidos := []
	for a in _arboles: solidos.append([a[0], a[1], 1.1 * a[2], 0.0, 2.4 * a[2]])
	for a in grandes:
		var hg := altura_terreno(a[0], a[1]); var sg: float = a[2]
		solidos.append([a[0], a[1], 0.9 * sg, hg, hg + (3.2 * sg / 2.5 + 2.2 * sg if a[3] else 1.1 * sg / 2.5 + 1.4 * sg)])
	ent.poner_arboles("campo", solidos)
	_instanciar(cilindro(0.2, 0.32, 1, 6), lambert(Color.hex(0x5a4634ff), null, true), grandes, func(it: Array) -> Array:
		var s: float = it[2]; var ht: float = 3.2 * s / 2.5 if it[3] else 1.1 * s / 2.5; var h := altura_terreno(it[0], it[1])
		return [_tr(Vector3(it[0], h + ht / 2, -it[1]), 0, Vector3(s / 2.5, ht, s / 2.5)), Color.WHITE], 1e9)
	_instanciar(icosaedro(1, 2), lambert(Color.WHITE, null, true), grandes, func(it: Array) -> Array:
		var s: float = it[2]; var pino: bool = it[3]; var ht: float = 3.2 * s / 2.5 if pino else 1.1 * s / 2.5; var h := altura_terreno(it[0], it[1])
		var tr := _tr(Vector3(it[0], h + ht + s * (0.95 if pino else 0.6), -it[1]), 0, Vector3(s, s * (1.25 if pino else 0.8), s * (0.9 + 0.2 * r.r())))
		var c: Color
		if pino: c = hsl(0.27, 0.35, 0.2 + 0.05 * r.r())
		else:
			var hh := 0.22 + 0.04 * r.r(); c = hsl(hh, 0.3, 0.25 + 0.06 * r.r())
		return [tr, c], 1e9)
	var matas := []
	for i in 4600:
		var Ex := -900 + r.r() * 900; var Nn := -800 + r.r() * 1600; var d := Ex - borde_monte(Nn)
		if (d > 0 and r.r() < d / 70) or not en_isla(Ex, Nn, 100): continue
		matas.append([Ex, Nn, 0.8 + r.r() * 1.8, 0])
	for i in 700:
		var Nn := -1000 + r.r() * 2000; var lado := -1 if r.r() < 0.5 else 1; var dd := 16 + r.r() * 15
		matas.append([rambla(Nn) + lado * dd, Nn, 1.2 + r.r() * 2.2, 1])
	prescindibles.append_array(_instanciar(icosaedro(1, 0), lambert(Color.WHITE, null, true), matas, func(it: Array) -> Array:
		var s: float = it[2]
		var S := Vector3(s, s * 0.6, s * (0.8 + 0.4 * r.r()))
		var tr := _tr(Vector3(it[0], altura_terreno(it[0], it[1]) + s * 0.45, -it[1]), r.r() * 6.28, S)
		var c: Color
		if it[3]:
			var hh := 0.25 + 0.05 * r.r(); var ss := 0.3 + 0.2 * r.r(); c = hsl(hh, ss, 0.22 + 0.1 * r.r())
		else:
			var hh := 0.2 + 0.05 * r.r(); c = hsl(hh, 0.22, 0.3 + 0.08 * r.r())
		return [tr, c], 1e9))         # las matas sobran en calidad 0
	# cortijo y naves: cajas blancas con azotea; una con tejado
	for cj in CAMPO["cortijo"]:
		var Ex: float = cj[0]; var Nn: float = cj[1]; var a: float = cj[2]; var b: float = cj[3]; var h: float = cj[4]; var nave := a > 20
		_mi(_caja(a, h, b), lambert(Color.hex((0xd9d6cf if nave else 0xeae4d8) << 8 | 0xff)), Vector3(Ex, h / 2, -Nn))
		if not nave and a > 10:
			var tej := _mi(cilindro(0, a * 0.75, 2.2, 4), lambert(Color.hex(0xb0563bff)), Vector3(Ex, h + 1.1, -Nn))
			tej.rotation.y = PI / 4; tej.scale.z = b / a
		else: _mi(_caja(a + 0.4, 0.3, b + 0.4), lambert(Color.hex((0x9a9a98 if nave else 0xc7b9a1) << 8 | 0xff)), Vector3(Ex, h, -Nn))
	_mi(_caja(70, 1.6, 0.4), lambert(Color.hex(0xe0d7c6ff)), Vector3(85, 0.8, -248))     # tapia
	_autopista(r)
	# estacas blancas cada 50 m para juzgar distancias
	var estaca := cilindro(0.05, 0.05, 1.5, 5); var m_est := lambert(Color.hex(0xf2f2f2ff))
	for x in range(-200, 201, 50):
		for z in range(-200, 201, 50):
			if (x == 0 and z == 0) or (x > Z["e0"] and x < Z["e1"] and -z > Z["n0"] and -z < Z["n1"]): continue
			_mi(estaca, m_est, Vector3(x, 0.75, z))
	# pilones hinchables tipo Red Bull, cada uno de su color (Entorno.circuito.colores; la puerta de la zona 2, naranja):
	# banda de cuadros arriba y franja blanca abajo
	var Pi: Dictionary = ent.pilon; var colores: Array = ent.circuito["colores"]
	var gpil := cilindro(Pi["r1"], Pi["r0"], Pi["alto"], 20, true)
	var gtapa := SphereMesh.new(); gtapa.radius = Pi["r1"]; gtapa.height = 2 * Pi["r1"]; gtapa.radial_segments = 12; gtapa.rings = 7
	var pilones := []
	var lp := ent.pilones()
	for i in lp.size(): pilones.append([lp[i], colores[i % colores.size()]["hex"]])
	for s in ent.pilones_puerta(): pilones.append([s, ent.zona2["puerta"]["color"]["hex"]])
	for pc in pilones:
		var s: Array = pc[0]; var hex: String = pc[1]
		var img := Image.create(64, 512, false, Image.FORMAT_RGB8); img.fill(Color.html(hex))
		for y in 3:
			for x in 8: img.fill_rect(Rect2i(x * 8, 40 + y * 8, 8, 8), Color.WHITE if (x + y) % 2 else Color.html("#111111"))
		img.fill_rect(Rect2i(0, 430, 64, 14), Color.WHITE)
		_mi(gpil, lambert(Color.WHITE, _tex(img)), Vector3(s[1], Pi["alto"] / 2, -s[0]))
		_mi(gtapa, lambert(Color.html(hex)), Vector3(s[1], Pi["alto"], -s[0]))
	# el aparcamiento: la furgoneta, la mesa del piloto y la manga de viento a rayas (sin carpa: tapaba la vista)
	_mi(_caja(2.0, 2.1, 4.8), lambert(Color.hex(0xecececff)), Vector3(8, 1.05, 9))
	_mi(_caja(2.04, 0.7, 3.2), lambert(Color.hex(0x2b3a48ff)), Vector3(8, 1.5, 9.3))
	_mi(_caja(1.6, 0.05, 0.7), lambert(Color.hex(0xcfcfcfff)), Vector3(-7, 0.78, 7))
	_mi(cilindro(0.03, 0.03, 4, 6), m_est, Vector3(-14, 2, -10)).name = "mastil"
	var img_m := Image.create(32, 128, false, Image.FORMAT_RGBA8); img_m.fill(Color(0, 0, 0, 0))
	for i in 5: _rect_img(img_m, 0, i * 25.6, 32, 25.6, Color.WHITE if i % 2 else Color.html("#ff6d00"))
	manga = _mi(cilindro(0, 0.25, 1.4, 12, true), lambert(Color.WHITE, _tex(img_m), false, true), Vector3(-14, 3.8, -10))
	_pintar_suelos.call_deferred(cuerpo, costa_, trazos_fondo(-700, 900, 1400, 1400), trazos_fondo(-3000, 3000, 6000, 6000))

## Cerro del oeste: malla elevada con bandas de roca (colores por vertice, lineales como en Three).
func _cerro() -> void:
	var nx := 154; var ny := 320; var W := 1540.0; var Hh := 3200.0
	var pos := PackedVector3Array(); var col := PackedColorArray(); var idx := PackedInt32Array()
	var c_roca := lin(0xcfc5a8); var c_monte := lin(0xa69e84); var c_verde := lin(0x737a56); var c_pie := lin(0xb3ab91)
	for iy in ny + 1:
		var Nn := Hh / 2 - iy * (Hh / ny); var bm := borde_monte(Nn)
		for ix in nx + 1:
			var Ex := ix * (W / nx) - W / 2 - 830
			var db := bm - Ex; var kb := maxf(0, minf(1, db / 90))           # 0 en el borde del monte, 1 a 90 m
			var h := -1.5 if db < 0 else altura_terreno(Ex, Nn) * kb * kb   # al este del borde queda bajo el suelo
			var banda := maxf(0, 1 - absf(fmod(h + 3 * fbm(Ex / 90, Nn / 90), 9) - 4.5) / 1.3) * minf(1, h / 10)
			var sombra := 0.62 + 0.75 * fbm(Ex / 70 + 3, Nn / 70) + 0.25 * (ruido(Ex / 11, Nn / 11) - 0.5)   # barrancos, lomas y grano
			var c := c_monte.lerp(c_verde, 0.7 * fbm(Ex / 300 + 9, Nn / 300)).lerp(c_roca, 0.9 * banda)
			c = Color(c.r * sombra, c.g * sombra, c.b * sombra)
			c = c.lerp(c_pie, 1 - minf(1, db / 150))                          # en el pie, el color del suelo pintado
			c.a = 1
			pos.append(Vector3(Ex, h + 0.3, -Nn)); col.append(c)
	var g := nx + 1
	for iy in ny:
		for ix in nx:
			var a := ix + g * iy; var b := ix + g * (iy + 1); var c := ix + 1 + g * (iy + 1); var d := ix + 1 + g * iy
			idx.append_array([a, d, b, b, d, c])
	var nor := PackedVector3Array(); nor.resize(pos.size())
	for i in range(0, idx.size(), 3):      # normales suaves (computeVertexNormals: suma de las normales de las caras)
		var A := pos[idx[i]]; var B := pos[idx[i + 1]]; var C := pos[idx[i + 2]]; var n := (C - A).cross(B - A)
		nor[idx[i]] += n; nor[idx[i + 1]] += n; nor[idx[i + 2]] += n
	for i in nor.size(): nor[i] = nor[i].normalized()
	_mi(_malla(pos, nor, idx, PackedVector2Array(), col), lambert(Color.WHITE, null, true))

## Autopista AP-7 sobre terraplen, con sus marcas y trafico (44 coches y camiones).
func _autopista(r: Semilla) -> void:
	var A: Dictionary = CAMPO["autopista"]; var dx: float = A["p1"][0] - A["p0"][0]; var dz: float = -(A["p1"][1] - A["p0"][1])
	var L := sqrt(dx * dx + dz * dz); var ang := atan2(-dz, dx); var alto: float = A["alto"]; var ancho: float = A["ancho"]
	var img := Image.create(1024, 64, false, Image.FORMAT_RGBA8); img.fill(Color.html("#585858"))
	_rect_img(img, 0, 28, 1024, 8, Color.html("#7a8a5a"))
	for y in [3, 25, 37, 59]: _rect_img(img, 0, y, 1024, 1.5, Color.html("#e8e8e8"))
	for x in range(0, 1024, 24):
		_rect_img(img, x, 14, 12, 1.2, Color.html("#e8e8e8")); _rect_img(img, x, 48, 12, 1.2, Color.html("#e8e8e8"))
	img.convert(Image.FORMAT_RGB8)
	var c := Vector3((A["p0"][0] + A["p1"][0]) / 2.0, 0, -(A["p0"][1] + A["p1"][1]) / 2.0)
	var terraplen := _mi(_caja(L, alto, ancho), lambert(Color.hex(0xb9a486ff)), c + Vector3(0, alto / 2, 0)); terraplen.rotation.y = ang
	var h := alto + 0.005; var pos := PackedVector3Array([Vector3(-L / 2, h, -ancho / 2), Vector3(L / 2, h, -ancho / 2), Vector3(L / 2, h, ancho / 2), Vector3(-L / 2, h, ancho / 2)])
	var calzada := _mi(_malla(pos, PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP]), PackedInt32Array([0, 1, 2, 0, 2, 3]),
		PackedVector2Array([Vector2(0, 0), Vector2(L / 60, 0), Vector2(L / 60, 1), Vector2(0, 1)])), lambert(Color.WHITE, _tex(img)), c)
	calzada.rotation.y = ang
	var mm := MultiMesh.new(); mm.transform_format = MultiMesh.TRANSFORM_3D; mm.use_colors = true; mm.mesh = _caja(4.4, 1.6, 1.9); mm.instance_count = 44
	var s := []
	var paleta := [0xf0f0f0, 0xd8d8d8, 0x333333, 0xb0261b, 0x1f4e9a, 0x8c8c8c, 0xe6c84a]
	for i in 44:
		var carril := int(floor(r.r() * 4)); var camion := r.r() < 0.2
		var u := r.r() * L; var v := (-1 if carril < 2 else 1) * (23.0 if camion else 30 + r.r() * 8)
		s.append({ "u": u, "carril": carril, "v": v, "camion": camion })
		mm.set_instance_color(i, lin(paleta[int(floor(r.r() * 7))]))
	var coches := MultiMeshInstance3D.new(); coches.multimesh = mm; coches.material_override = lambert(Color.WHITE, null, true)
	coches.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; add_child(coches)
	_trafico = { "mm": mm, "s": s, "ang": ang, "c": c, "L": L, "alto": alto }
	_mover_trafico(0)

## Mueve los coches de la autopista (dt en segundos), como Visor._trafico.
func _mover_trafico(dt: float) -> void:
	var T := _trafico; var ang: float = T["ang"]; var cs := cos(ang); var sn := sin(ang); var L: float = T["L"]; var c: Vector3 = T["c"]
	var mm: MultiMesh = T["mm"]; var s: Array = T["s"]
	for i in s.size():
		var v: Dictionary = s[i]
		v["u"] = fmod(v["u"] + v["v"] * dt + L, L)
		var a: float = v["u"] - L / 2; var b: float = [-10.5, -4.0, 4.0, 10.5][v["carril"]]; var cam: bool = v["camion"]
		var P := Vector3(c.x + a * cs + b * sn, T["alto"] + (1.6 if cam else 0.8), c.z - a * sn + b * cs)
		mm.set_instance_transform(i, _tr(P, ang, Vector3(2.6, 2, 1.3) if cam else Vector3.ONE))

func _process(delta: float) -> void:
	if not _trafico.is_empty(): _mover_trafico(minf(0.1, delta))

# =====================================================================================================================
#  API (como Mundo3D)
# =====================================================================================================================

## Punto de lanzamiento (N, E): ahi van el piloto (camara 1) y la manga. En la isla el navegador lo deja siempre en el origen.
func poner_base(N: float, E: float) -> void:
	base = Vector3(E, 0, -N)
	manga.position = Vector3(E - 14, 3.8, -N - 10)
	var mastil := get_node_or_null("mastil") as Node3D
	if mastil: mastil.position = Vector3(E - 14, 2, -N - 10)

## Orienta la manga hacia donde va el viento (viento NED actual, m/s), como Visor.dibujar: con menos de 0,2 m/s de viento
## configurado se queda como esta.
func actualizar_manga(viento_actual: Array) -> void:
	if ent == null or ent.viento["base"] <= 0.2: return
	var vw := Vector3(viento_actual[1], 0, -viento_actual[0])
	if vw.length() < 1e-9: return
	# lookAt de Three (el +z del objeto hacia el viento) y rotateX(pi/2): la punta del cono (+y) apunta a sotavento
	manga.basis = Basis.looking_at(vw, Vector3.UP, true) * Basis(Vector3.RIGHT, PI / 2)

## Pista FPV de un entrenamiento del dron FPV (escenarios.js, "pista_fpv"; las reglas en pista_fpv.gd), o {} para
## quitarla: plataforma de salida, cilindro del estacionario, conos de colores, postes del slalom y del ocho, puertas
## numeradas con su flecha en el suelo, puerta alta y torre (ponerPistaFpv de visor.js).
var _pista_fpv: Node3D
func poner_pista_fpv(d: Dictionary) -> void:
	if _pista_fpv != null: _pista_fpv.queue_free(); _pista_fpv = null
	if d.is_empty(): return
	var G := Node3D.new(); add_child(G); _pista_fpv = G
	var col: Array = ent.circuito["colores"]
	var en := func(mesh: Mesh, mat: Material, N: float, E: float, y := 0.0, padre: Node3D = G) -> MeshInstance3D:
		var mi := MeshInstance3D.new(); mi.mesh = mesh; mi.material_override = mat; mi.position = Vector3(E, y, -N); padre.add_child(mi); return mi
	var plano := func(c: Color) -> StandardMaterial3D:
		var m := StandardMaterial3D.new(); m.albedo_color = c; m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; m.cull_mode = BaseMaterial3D.CULL_DISABLED; return m
	var rayas := func(c1: Color, c2: Color, n: int) -> StandardMaterial3D:
		var img := Image.create(8, 64, false, Image.FORMAT_RGB8)
		for i in n: img.fill_rect(Rect2i(0, i * 64 / n, 8, 64 / n), c2 if i % 2 else c1)
		return lambert(Color.WHITE, _tex(img))
	var anillo := func(N: float, E: float, r: float, c: Color, y := 0.04) -> void:
		var t := TorusMesh.new(); t.inner_radius = r - 0.07; t.outer_radius = r + 0.07; t.rings = 48; t.ring_segments = 4
		en.call(t, plano.call(c), N, E, y).scale = Vector3(1, 0.05, 1)
	# plataforma de salida: chapa oscura con el borde naranja y una H blanca
	var s: Array = d["salida"]
	en.call(_caja(2.4, 0.06, 2.4), lambert(Color.html("#2b2b2b")), s[0], s[1], 0.03)
	var img := Image.create(128, 128, false, Image.FORMAT_RGB8); img.fill(Color.html("#ff6d00")); img.fill_rect(Rect2i(8, 8, 112, 112), Color.html("#2b2b2b"))
	for r in [Rect2i(38, 30, 12, 68), Rect2i(78, 30, 12, 68), Rect2i(38, 58, 52, 12)]: img.fill_rect(r, Color.WHITE)
	var pm := PlaneMesh.new(); pm.size = Vector2(2.4, 2.4)
	en.call(pm, lambert(Color.WHITE, _tex(img)), s[0], s[1], 0.061)
	if d.has("cilindro"):                                             # cilindro translucido del estacionario, con sus circulos
		var c: Dictionary = d["cilindro"]; var m := StandardMaterial3D.new()
		m.albedo_color = Color(Color.html("#29b6f6"), 0.22); m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.cull_mode = BaseMaterial3D.CULL_DISABLED; m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		en.call(cilindro(c["r"], c["r"], c["h1"] - c["h0"], 40, true), m, c["n"], c["e"], (c["h0"] + c["h1"]) / 2)
		for y in [0.04, float(c["h0"]), float(c["h1"])]: anillo.call(c["n"], c["e"], c["r"], Color.html("#29b6f6"), y)
	var conos: Array = d.get("conos", [])
	for i in conos.size():                                            # conos de los colores del circuito, con el circulo donde se tocan
		var q: Array = conos[i]; var hx := Color.html(col[i % col.size()]["hex"])
		en.call(cilindro(0, 0.28, 0.7, 20), lambert(hx), q[0], q[1], 0.35)
		en.call(cilindro(0.2, 0.235, 0.12, 20), lambert(Color.WHITE), q[0], q[1], 0.33)
		anillo.call(q[0], q[1], PistaFpv.CONO_R, hx)
	for q in d.get("postes", []): en.call(cilindro(PistaFpv.POSTE["r"], PistaFpv.POSTE["r"], PistaFpv.POSTE["alto"], 10), rayas.call(Color.html("#e53935"), Color.WHITE, 8), q[0], q[1], PistaFpv.POSTE["alto"] / 2)
	var och: Array = d.get("ocho", [])
	for i in och.size():                                              # postes del ocho: rojo y azul, con banderin
		var q: Array = och[i]; var hx := Color.html(col[PistaFpv.COLOR_OCHO[i]]["hex"]); var O: Dictionary = PistaFpv.OCHO
		en.call(cilindro(O["r"], O["r"], O["alto"], 10), rayas.call(hx, Color.WHITE, 10), q[0], q[1], O["alto"] / 2)
		var qm := QuadMesh.new(); qm.size = Vector2(0.8, 0.5)
		en.call(qm, lambert(hx, null, false, true), q[0], q[1], O["alto"] - 0.3).position.x += 0.4
	# puertas: marco de tubo, numero arriba (por las dos caras) y flecha en el suelo antes de la puerta
	var puerta := func(g: Dictionary, color: Color, texto: String) -> void:
		var gr := PistaFpv.GROSOR; var H1: float = g["h0"] + g["alto"]; var A: float = g["ancho"] / 2; var P0 := Node3D.new(); G.add_child(P0); var m := lambert(color)
		for sg in [-1, 1]: en.call(_caja(gr, H1 + gr, gr), m, 0, 0, (H1 + gr) / 2, P0).position.x = sg * (A + gr / 2)
		en.call(_caja(g["ancho"] + 2 * gr, gr, gr), m, 0, 0, H1 + gr / 2, P0)
		if g["h0"] > 0: en.call(_caja(g["ancho"] + 2 * gr, gr, gr), m, 0, 0, g["h0"] - gr / 2, P0)
		var qm := QuadMesh.new(); qm.size = Vector2(0.8, 0.6)
		en.call(qm, plano.call(Color.html("#111111")), 0, 0, H1 + gr + 0.32, P0)
		for lado in [0.0, PI]:
			var l := Label3D.new(); l.text = texto; l.font_size = 96; l.outline_size = 0; l.pixel_size = 0.005; l.modulate = Color.WHITE
			l.double_sided = false; l.font = Tema.negrita; l.position = Vector3(0, H1 + gr + 0.3, 0) + Vector3(0, 0, 0.01).rotated(Vector3.UP, lado); l.rotation.y = lado
			P0.add_child(l)
		var fl := _malla(PackedVector3Array([Vector3(-0.5, 0.03, 2.6), Vector3(0.5, 0.03, 2.6), Vector3(0, 0.03, 1.5)]), PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP]), PackedInt32Array([0, 1, 2]))
		en.call(fl, plano.call(Color.WHITE), 0, 0, 0, P0)               # la punta hacia la puerta (-z local = sentido de paso)
		P0.rotation.y = -g["rumbo"] * D2R; P0.position = Vector3(g["e"], 0, -g["n"])
	var gs := PistaFpv.new(d, func(_k, _e): pass).puertas()
	for i in gs.size(): puerta.call(gs[i], Color.html("#ff6d00"), str(i + 1))
	if d.has("puerta_alta"): puerta.call(d["puerta_alta"], Color.html("#d81b60"), "▲")
	if d.has("torre"):                                                # torre de andamio galvanizado con baliza arriba
		var q: Dictionary = d["torre"]; var l: float = q["lado"] / 2; var mt := lambert(Color.html("#b8bcc0"))
		for ab in [[-l, -l], [-l, l], [l, -l], [l, l]]: en.call(cilindro(0.05, 0.05, q["alto"], 8), mt, q["n"] + ab[0], q["e"] + ab[1], q["alto"] / 2)
		var y := 2.5
		while y <= q["alto"]:
			for a in [-l, l]:
				en.call(_caja(0.05, 0.05, q["lado"]), mt, q["n"] + a, q["e"], y); en.call(_caja(q["lado"], 0.05, 0.05), mt, q["n"], q["e"] + a, y)
			y += 2.5
		en.call(_caja(q["lado"], 0.1, q["lado"]), lambert(Color.html("#8d6e63")), q["n"], q["e"], q["alto"])
		var sf := SphereMesh.new(); sf.radius = 0.18; sf.height = 0.36
		en.call(sf, plano.call(Color.html("#ff1744")), q["n"], q["e"], q["alto"] + 0.3)
	if d.has("recta"):                                                # conos naranjas en las cuatro esquinas del pasillo de la recta
		var R: Dictionary = d["recta"]; var w: float = R["ancho"] / 2 + R["margen"]
		for e in [R["e0"], R["e1"]]:
			for sg in [-1, 1]: en.call(cilindro(0, 0.25, 0.6, 16), lambert(Color.html("#ff6d00")), R["n"] + sg * w, e, 0.3)

## Los almendros [E, N, s] que salen del pintado del suelo (para las pruebas).
func arboles() -> Array:
	return _arboles
