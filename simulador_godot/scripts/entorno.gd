class_name Entorno
extends RefCounted
## El entorno fisico: viento con rachas, turbulencia de alabeo, viento junto al suelo, contacto con el suelo y, segun el
## mundo, la isla del campo de vuelo del club (mundo vacio: la pista, los 4 pilones del circuito, la zona 2 con la pista 2,
## la diana y la puerta, y los limites del campo) o un mundo real (terreno del mundo y, donde la hay, el de la zona de
## detalle a 5 m, y el agua). Traduccion literal de Entorno (simulador_web/js/entorno.js): simulador_godot/Tests/prueba_fisica.gd compara
## los mundos reales y simulador_godot/Tests/prueba_campo.gd la isla (con ContadorVueltas y PasadaBaja) con el navegador.
## Coordenadas NED en metros con origen en el piloto, que mira al norte. La pista va hacia el norte.

const D2R := PI / 180.0

var viento := { "base": 2.0, "rumbo": PI, "rachas": true, "r": [0.0, 0.0, 0.0, 0.0], "actual": [0.0, 0.0, 0.0] }
## limites de un aterrizaje sin danos, y del campo: a mas de aviso_m se avisa, a mas de distancia_m el avion ya no se
## ve desde el piloto y el vuelo termina "fuera de limites" (solo en la isla)
var limites := { "descenso_ms": 2.5, "alabeo_grados": 30.0, "vel_suelo_ms": 12.0, "cabeceo_grados": 25.0, "aviso_m": 400.0, "distancia_m": 650.0 }
var pista := { "n0": 10.0, "n1": 70.0, "ancho": 10.0 }                 # N 10 a 70, centrada en E = 0
## circuito: rectangulo de 120 x 180 m delante del piloto, con la pista dentro. Pilones en las esquinas (N, E), ordenados
## por angulo alrededor del centro: los indices consecutivos son esquinas vecinas. Cada pilon tiene su color. Indices
## crecientes (verde -> amarillo -> rojo -> azul) = vuelta en sentido horario visto desde arriba. Sentido -1 = al reves.
var circuito := { "centro": [100.0, 0.0], "pilones": [[40.0, -90.0], [160.0, -90.0], [160.0, 90.0], [40.0, 90.0]],
				  "colores": [{ "nombre": "verde", "hex": "#2e7d32" }, { "nombre": "amarillo", "hex": "#f9a825" },
							  { "nombre": "rojo", "hex": "#c62828" }, { "nombre": "azul", "hex": "#1565c0" }] }
var pilon := { "alto": 20.0, "r0": 1.4, "r1": 0.45 }                   # cono hinchable: radio abajo y arriba
## ZONA 2, detras del piloto (al sur; el piloto se da la vuelta): entrenamiento de precision.
##  - pista 2: franja de tierra de este a oeste para la pasada baja (de punta a punta entre hmin y hmax, sin salirse
##    por los lados) y con la diana de aterrizaje en el centro
##  - diana: circulos de cal de 5, 10 y 20 m con sus puntos
##  - puerta: dos pilones naranjas separados 16 m; se cruza de este a oeste o al reves, por debajo de lo alto
##  - despejado: rectangulo sin almendros ni estacas
var zona2 := {
	"pista": { "n": -45.0, "e0": -35.0, "e1": 35.0, "ancho": 10.0, "margen": 5.0, "hmin": 2.0, "hmax": 8.0 },
	"diana": { "n": -45.0, "e": 0.0, "anillos": [[5.0, 100], [10.0, 50], [20.0, 20]] },
	"puerta": { "e": 60.0, "n0": -123.0, "n1": -107.0, "color": { "nombre": "naranja", "hex": "#ef6c00" } },
	"despejado": { "n0": -150.0, "n1": -14.0, "e0": -60.0, "e1": 95.0 },
}
var mundo := {}             # mundo real activo ({} = la isla del campo de pilones)
var terreno := {}           # H (PackedInt32Array, m sobre el mar), paso, N0, E0, nN, nE, h0
var agua := PackedByteArray(); var laguna := PackedByteArray()
var zona := {}              # la primera zona de detalle puesta ({ meta, dem, base }) o vacio
var zonas := []             # todas las zonas de detalle puestas (poner_zonas)
var _libres := []           # por zona: [sur, norte, oeste, este] sin otra zona pegada
var facil := false          # dificultad facil: el mismo viento a cualquier altura y rachas que no alabean

## vel en m/s; desde = de donde viene el viento (grados: 0 norte, 90 este...).
func configurar_viento(vel: float, desde: float, rachas: bool) -> void:
	viento["base"] = vel; viento["rumbo"] = fmod(desde + 180, 360) * PI / 180; viento["rachas"] = rachas
	viento["r"] = [0.0, 0.0, 0.0, 0.0]

## Viento a la altura h sobre el suelo (perfil logaritmico, rugosidad 5 cm; referencia a 10 m).
func viento_a(vw: Array, h: float) -> Array:
	if facil: return vw.duplicate()
	var z0 := 0.05; var k := maxf(0, log(maxf(h, 0.2) / z0) / log(10 / z0))
	return [vw[0] * minf(1.25, k), vw[1] * minf(1.25, k), vw[2] * minf(1, k)]

## Velocidad de alabeo de la turbulencia (Dryden) para un avion de envergadura b a la altura h.
func rafaga_alabeo(b: float, h: float) -> float:
	if facil or not viento["rachas"] or viento["base"] < 0.01: return 0.0
	var sw: float = 0.5 * (0.18 * viento["base"] + 0.15); var Lw := maxf(3, minf(h, 300))
	return viento["r"][3] * sw * sqrt(0.8 / Lw * pow(PI * Lw / (4 * b), 1.0 / 3.0) / (2 * 4 * b / PI))

## Rachas: tres ruidos filtrados de 1,2 s y uno de alabeo de 0,15 s.
func actualizar(dt: float) -> Array:
	var W: float = viento["base"]; var base := [W * cos(viento["rumbo"]), W * sin(viento["rumbo"]), 0.0]
	var r: Array = viento["r"]
	if viento["rachas"] and W > 0.01:
		var sigma := 0.18 * W + 0.15; var tau := 1.2
		for i in 3:
			var s := 0.5 * sigma if i == 2 else sigma
			r[i] += (-r[i] / tau + s * sqrt(2 / tau) * (randf() * 2 - 1) * sqrt(3.0) / sqrt(dt)) * dt
		var tp := 0.15
		r[3] += (-r[3] / tp + sqrt(2 / tp) * (randf() * 2 - 1) * sqrt(3.0) / sqrt(dt)) * dt
	else:
		viento["r"] = [0.0, 0.0, 0.0, 0.0]; r = viento["r"]
	viento["actual"] = [base[0] + r[0], base[1] + r[1], r[2]]
	return viento["actual"]

# ---------------- terreno ----------------

static func _b64_int16(s: String) -> PackedInt32Array:
	var bytes := Marshalls.base64_to_raw(s)
	var out := PackedInt32Array(); out.resize(bytes.size() / 2)
	for k in out.size(): out[k] = bytes.decode_s16(2 * k)
	return out

static func _b64_bits(s: String, n: int) -> PackedByteArray:
	var bytes := Marshalls.base64_to_raw(s)
	var out := PackedByteArray(); out.resize(n)
	for i in n: out[i] = (bytes[i >> 3] >> (7 - (i & 7))) & 1
	return out

## Activa un mundo real (DatosComunes.mundo(id)) o vuelve a la isla ({}): en la isla el suelo esta a 0 m y no hay
## mar (altura y en_mar miran mundo). Como en el navegador, el terreno del ultimo mundo se queda guardado.
func poner_mundo(m: Dictionary) -> void:
	mundo = m; zona = {}; zonas = []; _libres = []; _rej_arb = null
	if m.is_empty(): return
	var T: Dictionary = m["terreno"]
	terreno = { "H": _b64_int16(T["alturas_b64"]), "paso": float(T["paso"]), "N0": float(T["N0"]), "E0": float(T["E0"]),
				"nN": int(T["nN"]), "nE": int(T["nE"]), "h0": float(T["h0"]) }
	agua = _b64_bits(T["agua_b64"], terreno["nN"] * terreno["nE"]) if T.has("agua_b64") else PackedByteArray()
	laguna = _b64_bits(T["laguna_b64"], terreno["nN"] * terreno["nE"]) if T.has("laguna_b64") else PackedByteArray()

func _bilineal(A, N: float, E: float) -> float:
	var T := terreno
	var i := clampf((N - T["N0"]) / T["paso"], 0, T["nN"] - 1.001); var j := clampf((E - T["E0"]) / T["paso"], 0, T["nE"] - 1.001)
	var i0 := int(floor(i)); var j0 := int(floor(j)); var fi := i - i0; var fj := j - j0; var nE: int = T["nE"]; var k := i0 * nE + j0
	return A[k] * (1 - fi) * (1 - fj) + A[k + nE] * fi * (1 - fj) + A[k + 1] * (1 - fi) * fj + A[k + nE + 1] * fi * fj

## Altura sobre el nivel del mar del terreno del mundo (malla de 150 m), bilineal.
func altura_mar(N: float, E: float) -> float:
	return _bilineal(terreno["H"], N, E)

func fraccion_agua(N: float, E: float) -> float:
	if agua.is_empty(): return 1.0 if altura_mar(N, E) <= 0.5 else 0.0
	return _bilineal(agua, N, E)

func altura_mundo(N: float, E: float) -> float:
	return (0.0 if fraccion_agua(N, E) > 0.7 else maxf(0, altura_mar(N, E))) - terreno["h0"]

func en_mar_mundo(N: float, E: float) -> bool:
	return fraccion_agua(N, E) > 0.7

## Zona de detalle (DatosComunes.cargar_zona) o {} para quitarla.
func poner_zona(z: Dictionary) -> void:
	poner_zonas([] if z.is_empty() else [z])

## Varias zonas a la vez (ponerZonas de entorno.js): cada punto toma el suelo de la primera zona que lo contiene; la
## mezcla con el mundo en los ultimos 100 m solo en los lados SIN otra zona pegada.
func poner_zonas(lista: Array) -> void:
	zonas = lista.filter(func(z): return not (z as Dictionary).is_empty())
	zona = zonas[0] if not zonas.is_empty() else {}
	_libres = []
	for z in zonas:
		var Z: Dictionary = z["meta"]; var lado: float = (Z["dem"]["n"] - 1) * Z["dem"]["paso_m"]
		var pegada := func(dN: int, dE: int) -> bool:
			for o in zonas:
				if o != z and absf(o["meta"]["N0"] - (Z["N0"] + dN * lado)) < 0.5 and absf(o["meta"]["E0"] - (Z["E0"] + dE * lado)) < 0.5: return true
			return false
		_libres.append([not pegada.call(-1, 0), not pegada.call(1, 0), not pegada.call(0, -1), not pegada.call(0, 1)])   # sur, norte, oeste, este

## [altura sobre el mar, fraccion de agua] de una zona, bilineal, o [] fuera de ella.
static func _muestra(z: Dictionary, N: float, E: float) -> Array:
	var Z: Dictionary = z["meta"]; var D: PackedInt32Array = z["dem"]; var n: int = Z["dem"]["n"]; var paso: float = Z["dem"]["paso_m"]
	var i: float = (N - Z["N0"]) / paso; var j: float = (E - Z["E0"]) / paso
	if i < 0 or j < 0 or i > n - 1 or j > n - 1: return []
	i = minf(n - 1.001, i); j = minf(n - 1.001, j)
	var i0 := int(floor(i)); var j0 := int(floor(j)); var fi := i - i0; var fj := j - j0; var k := i0 * n + j0
	# las cuatro esquinas en este orden y con estas mismas operaciones (sin arrays por llamada): resultados identicos
	var w0 := (1 - fi) * (1 - fj); var w1 := fi * (1 - fj); var w2 := (1 - fi) * fj; var w3 := fi * fj
	var h := 0.0; var a := 0.0; var vv: int
	vv = D[k]
	if vv == -32768: a += w0
	else: h += w0 * vv / 10.0
	vv = D[k + n]
	if vv == -32768: a += w1
	else: h += w1 * vv / 10.0
	vv = D[k + 1]
	if vv == -32768: a += w2
	else: h += w2 * vv / 10.0
	vv = D[k + n + 1]
	if vv == -32768: a += w3
	else: h += w3 * vv / 10.0
	return [h / (1 - a) if a < 1 else 0.0, a]

## [altura, fraccion de agua, indice de la zona] en la primera zona que contiene (N, E), o [].
func _buscar(N: float, E: float) -> Array:
	for q in zonas.size():
		var m := _muestra(zonas[q], N, E)
		if not m.is_empty(): return [m[0], m[1], q]
	return []

## [altura sobre el mar, fraccion de agua] de las zonas, o [] fuera de ellas.
func muestra_zona(N: float, E: float) -> Array:
	var r := _buscar(N, E)
	return [] if r.is_empty() else [r[0], r[1]]

## Altura del suelo (m sobre el origen del mundo) en (N, E): la de la zona si la hay (mezclada con la del mundo en
## los ultimos 100 m de sus bordes libres) o la del mundo. En la isla, 0 (en el navegador Entorno.altura es null).
func altura(N: float, E: float) -> float:
	if mundo.is_empty(): return 0.0
	var r := _buscar(N, E)
	if r.is_empty(): return altura_mundo(N, E)
	var q: int = r[2]; var Z: Dictionary = zonas[q]["meta"]; var lado: float = (Z["dem"]["n"] - 1) * Z["dem"]["paso_m"]; var L: Array = _libres[q]
	var hz: float = (0.0 if r[1] > 0.7 else maxf(0, r[0])) - terreno["h0"]
	var d := minf(minf(N - Z["N0"] if L[0] else INF, Z["N0"] + lado - N if L[1] else INF), minf(E - Z["E0"] if L[2] else INF, Z["E0"] + lado - E if L[3] else INF))
	return hz if d >= 100 else hz * d / 100 + altura_mundo(N, E) * (1 - d / 100)

## true si (N, E) es agua. En la isla, nunca (en el navegador Entorno.enMar es null: la isla no tiene suelo de mar).
func en_mar(N: float, E: float) -> bool:
	if mundo.is_empty(): return false
	var m := muestra_zona(N, E)
	return m[1] > 0.7 if not m.is_empty() else en_mar_mundo(N, E)

## Contacto con el suelo: "" si sigue en el aire; si no, "aterrizado" o "roto (motivo)".
func contacto_suelo(av: Dictionary, vn: Array, suelo_dado: float = NAN, toma = null) -> String:
	var p: Array = av["p"]
	var suelo := altura(p[0], p[1]) if is_nan(suelo_dado) else suelo_dado      # quien ya la ha calculado en esa posicion, la pasa
	if -p[2] > suelo: return ""
	p[2] = -suelo
	if en_mar(p[0], p[1]): return "roto (ha caído al mar)"
	var e := Cuat.euler(av["q"]); var vz: float = -vn[2]; var vel := sqrt(vn[0] * vn[0] + vn[1] * vn[1]); var L := limites
	# toma en perdida profunda (datos.toma_perdida: el Grajo): mucho angulo de ataque, bajando deprisa y casi sin avance
	if toma != null and float(av.get("alfa", 0.0)) > float(toma["alfa_min"]) and vz > -float(toma["vz_max_ms"]) and vel < float(toma["vel_max_ms"]) and absf(e[0]) < 35 * D2R:
		av["tomaPerdida"] = true; return "aterrizado"
	if vz < -L["descenso_ms"]: return "roto (demasiado descenso)"
	if absf(e[0]) > L["alabeo_grados"] * D2R: return "roto (ala en el suelo)"
	if vel > L["vel_suelo_ms"]: return "roto (demasiada velocidad)"
	if absf(e[1]) > L["cabeceo_grados"] * D2R: return "roto (morro en el suelo)"
	return "aterrizado"

# ---------------- la isla: pista, circuito de pilones y zona 2 ----------------

static func _hypot(x: float, y: float) -> float:
	return sqrt(x * x + y * y)

func pilones() -> Array:
	return circuito["pilones"]

## Los dos pilones de la puerta de la zona 2, (N, E).
func pilones_puerta() -> Array:
	var P: Dictionary = zona2["puerta"]
	return [[P["n0"], P["e"]], [P["n1"], P["e"]]]

## Distancia horizontal al piloto (m) y si esta fuera del campo. En un mundo real no hay limite.
func distancia(p: Array) -> float:
	return _hypot(p[0], p[1])

func fuera_de_limites(p: Array) -> bool:
	return mundo.is_empty() and distancia(p) > limites["distancia_m"]

## Arboles solidos (los que se dibujan): listas [E, N, radio, y0, y1] (pie y copa, m hacia arriba como -p[2]) por clave:
## "campo" (la isla) y en un mundo real "region" y "zona:<id>". Los de la isla solo cuentan en la isla y los demas solo en
## el mundo real. Rejilla de 25 m. Lo mismo que ponerArboles / chocaArbol de entorno.js.
var _arboles := {}
var _rej_arb = null
func poner_arboles(clave: String, lista: Array) -> void:
	if lista.is_empty(): _arboles.erase(clave)
	else: _arboles[clave] = lista
	_rej_arb = null
func quitar_arboles(prefijo: String) -> void:
	for k in _arboles.keys():
		if String(k).begins_with(prefijo): _arboles.erase(k)
	_rej_arb = null
## Copa solida de un arbol de las zonas de radio de copa rc sobre el suelo y: [radio, y0, y1] (arbolZona de entorno.js).
static func arbol_zona(rc: float, y: float) -> Array:
	return [0.9 * rc, y, y + 1.0 + 0.3 * rc + 1.15 * rc] if rc < 2.5 else [0.9 * rc, y, y + 1.5 + 0.4 * rc + 1.7 * rc]
## true si el avion (posicion NED, semienvergadura en m) toca un arbol.
func choca_arbol(p: Array, semi: float) -> bool:
	if _rej_arb == null:
		_rej_arb = {}
		for k in _arboles:
			if (k == "campo") != mundo.is_empty(): continue
			for t in _arboles[k]:
				for i in range(int(floor((t[0] - t[2]) / 25.0)), int(floor((t[0] + t[2]) / 25.0)) + 1):
					for j in range(int(floor((t[1] - t[2]) / 25.0)), int(floor((t[1] + t[2]) / 25.0)) + 1):
						var q := Vector2i(i, j)
						if not _rej_arb.has(q): _rej_arb[q] = []
						_rej_arb[q].append(t)
	var up: float = -p[2]; var celda := Vector2i(int(floor(p[1] / 25.0)), int(floor(p[0] / 25.0)))
	if not _rej_arb.has(celda): return false
	for t in _rej_arb[celda]:
		if up < t[4] and up > t[3] - 0.3 and _hypot(p[1] - t[0], p[0] - t[1]) < t[2] + 0.8 * semi: return true
	return false

## Edificios solidos (ponerEdificios de entorno.js): [planta [E0, N0, E1, N1, ...], y0, y1] por clave ("sinteticos",
## "zona:<id>"). Rejilla de 25 m.
var _edificios := {}
var _rej_edif = null
func poner_edificios(clave: String, lista: Array) -> void:
	if lista.is_empty(): _edificios.erase(clave)
	else: _edificios[clave] = lista
	_rej_edif = null
func quitar_edificios(prefijo: String) -> void:
	for k in _edificios.keys():
		if String(k).begins_with(prefijo): _edificios.erase(k)
	_rej_edif = null
## true si el avion toca un edificio: dentro de su planta o a menos de 0,6 de la semienvergadura de una fachada, entre el
## pie y el tejado (chocaEdificio de entorno.js).
func choca_edificio(p: Array, semi: float) -> bool:
	if mundo.is_empty() or _edificios.is_empty(): return false
	if _rej_edif == null:
		_rej_edif = {}
		for k in _edificios:
			for ed in _edificios[k]:
				var P: Array = ed[0]; var e0 := 1e9; var e1 := -1e9; var n0 := 1e9; var n1 := -1e9
				for i in range(0, P.size(), 2):
					e0 = minf(e0, P[i]); e1 = maxf(e1, P[i]); n0 = minf(n0, P[i + 1]); n1 = maxf(n1, P[i + 1])
				for i in range(int(floor((e0 - 3) / 25.0)), int(floor((e1 + 3) / 25.0)) + 1):
					for j in range(int(floor((n0 - 3) / 25.0)), int(floor((n1 + 3) / 25.0)) + 1):
						var q := Vector2i(i, j)
						if not _rej_edif.has(q): _rej_edif[q] = []
						_rej_edif[q].append(ed)
	var up: float = -p[2]; var x: float = p[1]; var y: float = p[0]; var m := 0.6 * semi; var celda := Vector2i(int(floor(x / 25.0)), int(floor(y / 25.0)))
	if not _rej_edif.has(celda): return false
	for ed in _rej_edif[celda]:
		if up > ed[2] + m or up < ed[1]: continue
		var P: Array = ed[0]; var n := P.size() / 2; var dentro := false; var d2 := 1e18; var j := n - 1
		for i in n:
			var xi: float = P[2 * i]; var yi: float = P[2 * i + 1]; var xj: float = P[2 * j]; var yj: float = P[2 * j + 1]
			if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi) + xi: dentro = not dentro
			var dx := xj - xi; var dy := yj - yi; var L2 := dx * dx + dy * dy; var t := clampf(((x - xi) * dx + (y - yi) * dy) / L2, 0, 1) if L2 > 0 else 0.0
			var ex := xi + t * dx - x; var ey := yi + t * dy - y; d2 = minf(d2, ex * ex + ey * ey)
			j = i
		if dentro or d2 < m * m: return true
	return false

## true si el avion (posicion NED, semienvergadura en m) toca un pilon.
func choca_pilon(p: Array, semi: float) -> bool:
	if not mundo.is_empty(): return false
	var h: float = -p[2]; var P := pilon
	if h > P["alto"] + 0.3: return false
	var r: float = P["r0"] + (P["r1"] - P["r0"]) * maxf(0, h) / P["alto"]
	if _pilones_de != circuito: _pilones_de = circuito; _pilones_todos = pilones() + pilones_puerta()   # la misma lista en cada paso
	for s in _pilones_todos:
		if _hypot(p[0] - s[0], p[1] - s[1]) < r + semi * 0.8: return true
	return false
var _pilones_todos := []
var _pilones_de = null

## Cuenta vueltas al circuito: un objeto por vuelo, con actualizar(p_ant, p, t) en cada paso. sentido: +1 (verde,
## amarillo, rojo, azul), -1 (al reves) o 0 (cualquiera).
func contador_vueltas(sentido := 0) -> ContadorVueltas:
	return ContadorVueltas.new(circuito, sentido)

## Texto del orden de paso de un sentido: "verde → amarillo → rojo → azul".
func orden_pilones(sentido: int) -> String:
	var n := PackedStringArray()
	for c in circuito["colores"]: n.append(c["nombre"])
	if not sentido: return "en cualquier sentido"
	if sentido < 0: n.reverse()
	return " → ".join(n)

## Cruce de la linea de la puerta entre dos pasos: {} (no cruza), {tipo: "puerta", sentido: "este" | "oeste", h},
## {tipo: "alta", h} (por encima de los pilones: no cuenta) o {tipo: "fuera"} (por el lado de un pilon).
func cruza_puerta(p_ant: Array, p: Array) -> Dictionary:
	var P: Dictionary = zona2["puerta"]; var a: float = p_ant[1] - P["e"]; var b: float = p[1] - P["e"]
	if (a < 0) == (b < 0): return {}
	var t := a / (a - b); var n: float = p_ant[0] + t * (p[0] - p_ant[0]); var h: float = -(p_ant[2] + t * (p[2] - p_ant[2]))
	if n > P["n0"] and n < P["n1"]:
		return { "tipo": "puerta", "sentido": "este" if b > a else "oeste", "h": h } if h < pilon["alto"] else { "tipo": "alta", "h": h }
	if n > P["n0"] - 30 and n < P["n1"] + 30 and h < 40: return { "tipo": "fuera" }
	return {}

## Pasadas bajas por la pista 2: un objeto por vuelo, con actualizar(p) en cada paso.
func pasada_baja() -> PasadaBaja:
	return PasadaBaja.new(zona2["pista"])

## Distancia horizontal (m) de (N, E) al centro de la diana y los puntos de esa toma: {d, puntos}.
func diana(N: float, E: float) -> Dictionary:
	var D: Dictionary = zona2["diana"]; var d := _hypot(N - D["n"], E - D["e"]); var puntos := 0
	for a in D["anillos"]:
		if d <= a[0]:
			puntos = a[1]; break
	return { "d": d, "puntos": puntos }

## true si (N, E) esta sobre la pista, con margen.
func en_pista(N: float, E: float, margen := 3.0) -> bool:
	var P := pista
	return absf(E) <= P["ancho"] / 2 + margen and N >= P["n0"] - 5 and N <= P["n1"] + 15
