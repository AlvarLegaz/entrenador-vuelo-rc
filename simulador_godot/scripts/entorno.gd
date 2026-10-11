class_name Entorno
extends RefCounted
## El entorno fisico de un mundo real: viento con rachas, turbulencia de alabeo, viento junto al suelo, terreno (el
## del mundo y, donde la hay, el de la zona de detalle a 5 m), agua y contacto con el suelo. Traduccion literal de
## la parte de mundos reales de Entorno (simulador/js/entorno.js): pruebas/prueba_fisica.gd compara los dos.

const D2R := PI / 180.0

var viento := { "base": 2.0, "rumbo": PI, "rachas": true, "r": [0.0, 0.0, 0.0, 0.0], "actual": [0.0, 0.0, 0.0] }
var limites := { "descenso_ms": 2.5, "alabeo_grados": 30.0, "vel_suelo_ms": 12.0, "cabeceo_grados": 25.0 }
var mundo := {}
var terreno := {}           # H (PackedInt32Array, m sobre el mar), paso, N0, E0, nN, nE, h0
var agua := PackedByteArray(); var laguna := PackedByteArray()
var zona := {}              # { meta, dem, base } o vacio

## vel en m/s; desde = de donde viene el viento (grados: 0 norte, 90 este...).
func configurar_viento(vel: float, desde: float, rachas: bool) -> void:
	viento["base"] = vel; viento["rumbo"] = fmod(desde + 180, 360) * PI / 180; viento["rachas"] = rachas
	viento["r"] = [0.0, 0.0, 0.0, 0.0]

## Viento a la altura h sobre el suelo (perfil logaritmico, rugosidad 5 cm; referencia a 10 m).
func viento_a(vw: Array, h: float) -> Array:
	var z0 := 0.05; var k := maxf(0, log(maxf(h, 0.2) / z0) / log(10 / z0))
	return [vw[0] * minf(1.25, k), vw[1] * minf(1.25, k), vw[2] * minf(1, k)]

## Velocidad de alabeo de la turbulencia (Dryden) para un avion de envergadura b a la altura h.
func rafaga_alabeo(b: float, h: float) -> float:
	if not viento["rachas"] or viento["base"] < 0.01: return 0.0
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

func poner_mundo(m: Dictionary) -> void:
	mundo = m; zona = {}
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
	zona = z

## [altura sobre el mar, fraccion de agua] de la zona, bilineal, o [] fuera de ella.
func muestra_zona(N: float, E: float) -> Array:
	if zona.is_empty(): return []
	var Z: Dictionary = zona["meta"]; var D: PackedInt32Array = zona["dem"]; var n: int = Z["dem"]["n"]; var paso: float = Z["dem"]["paso_m"]
	var i: float = (N - Z["N0"]) / paso; var j: float = (E - Z["E0"]) / paso
	if i < 0 or j < 0 or i > n - 1 or j > n - 1: return []
	i = minf(n - 1.001, i); j = minf(n - 1.001, j)
	var i0 := int(floor(i)); var j0 := int(floor(j)); var fi := i - i0; var fj := j - j0; var k := i0 * n + j0
	var h := 0.0; var a := 0.0
	for par in [[k, (1 - fi) * (1 - fj)], [k + n, fi * (1 - fj)], [k + 1, (1 - fi) * fj], [k + n + 1, fi * fj]]:
		var vv: int = D[par[0]]
		if vv == -32768: a += par[1]
		else: h += par[1] * vv / 10.0
	return [h / (1 - a) if a < 1 else 0.0, a]

## Altura del suelo (m sobre el origen del mundo) en (N, E): la de la zona si la hay (mezclada con la del mundo en
## los ultimos 100 m del borde) o la del mundo.
func altura(N: float, E: float) -> float:
	var m := muestra_zona(N, E)
	if m.is_empty(): return altura_mundo(N, E)
	var Z: Dictionary = zona["meta"]; var lado: float = (Z["dem"]["n"] - 1) * Z["dem"]["paso_m"]
	var hz: float = (0.0 if m[1] > 0.7 else maxf(0, m[0])) - terreno["h0"]
	var d := minf(minf(N - Z["N0"], Z["N0"] + lado - N), minf(E - Z["E0"], Z["E0"] + lado - E))
	return hz if d >= 100 else hz * d / 100 + altura_mundo(N, E) * (1 - d / 100)

func en_mar(N: float, E: float) -> bool:
	var m := muestra_zona(N, E)
	return m[1] > 0.7 if not m.is_empty() else en_mar_mundo(N, E)

## Contacto con el suelo: "" si sigue en el aire; si no, "aterrizado" o "roto (motivo)".
func contacto_suelo(av: Dictionary, vn: Array) -> String:
	var p: Array = av["p"]
	var suelo := altura(p[0], p[1])
	if -p[2] > suelo: return ""
	p[2] = -suelo
	if en_mar(p[0], p[1]): return "roto (ha caído al mar)"
	var e := Cuat.euler(av["q"]); var vz: float = -vn[2]; var vel := sqrt(vn[0] * vn[0] + vn[1] * vn[1]); var L := limites
	if vz < -L["descenso_ms"]: return "roto (demasiado descenso)"
	if absf(e[0]) > L["alabeo_grados"] * D2R: return "roto (ala en el suelo)"
	if vel > L["vel_suelo_ms"]: return "roto (demasiada velocidad)"
	if absf(e[1]) > L["cabeceo_grados"] * D2R: return "roto (morro en el suelo)"
	return "aterrizado"
