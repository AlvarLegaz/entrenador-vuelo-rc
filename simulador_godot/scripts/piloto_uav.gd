class_name PilotoUAV
extends RefCounted
## Piloto automatico de un UAV de ala fija (Cernicalo XM-7): traduccion LITERAL de simulador/js/piloto_uav.js (mismas
## capas, mismos modos y mismas ganancias, que vienen en datos.piloto). pruebas/prueba_piloto_uav.gd compara los dos.
## Por capas: el lazo interior lleva el alabeo y el cabeceo con los alerones y la profundidad (y amortigua la guinada con
## los timones; con proteccion contra la perdida); encima, el rumbo, la altura y la velocidad (con el gas); y encima, la
## navegacion (ir a un punto y dar vueltas sobre el, volver a la base) y el despegue y el aterrizaje en la pista.
## Angulos en radianes; posiciones NED (m) del simulador; altura = -p[2].

const MODOS := ["MANUAL", "ESTAB", "CRUCERO", "PUNTO", "BASE", "DESPEGUE", "ATERRIZAJE"]
const NOMBRE := { "MANUAL": "Manual", "ESTAB": "Estabilizado", "CRUCERO": "Crucero", "PUNTO": "Ir a punto", "BASE": "Vuelta a base",
				  "DESPEGUE": "Despegue automático", "ATERRIZAJE": "Aterrizaje automático" }
const D2R := PI / 180.0
const G0 := 9.81

var P: Dictionary
var pista = null                 # {n, e, rumbo (grados), largo, h} o null
var casa: Array                  # [N, E, h] del despegue
var modo := "MANUAL"
var fase := ""
var c := { "alt": 0.0, "rumbo": 0.0, "vel": 0.0, "punto": null }
var iTh := 0.0
var iV := 0.0
var automatico := false          # si se ha usado el despegue o el aterrizaje automatico
var gas_visto = null             # la palanca del gas: en crucero, al moverla cambia la velocidad pedida

func _init(P_: Dictionary, pista_, casa_: Array) -> void:
	P = P_; pista = pista_; casa = casa_; c["vel"] = float(P["v_crucero"])

static func envolver(a: float) -> float: return a - TAU * floor(a / TAU + 0.5)      # Math.round de JS: las mitades hacia arriba
static func lim(x: float, a: float, b: float) -> float: return maxf(a, minf(b, x))
static func _norma(v: Array) -> float: return sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2])

## Cambia de modo con las consignas de lo que esta haciendo ahora. Devuelve el texto para el aviso o "" si no se puede.
func poner(m: String, av: Dictionary, punto = null) -> String:
	var e := Cuat.euler(av["q"]); var V := _norma(av["v"]); var h: float = -av["p"][2]
	var en_tierra: bool = av.get("enTierra", false)
	if m == "DESPEGUE" and not (pista != null and en_tierra): return ""
	if m == "ATERRIZAJE" and (pista == null or en_tierra): return ""
	if m in ["CRUCERO", "PUNTO", "BASE", "ESTAB"] and en_tierra: return ""
	modo = m; fase = ""; iTh = 0.0; iV = 0.0; gas_visto = null
	c["alt"] = h; c["rumbo"] = e[2]; c["vel"] = lim(V, P["v_min"], P["v_max"])
	if m == "CRUCERO": c["vel"] = float(P["v_crucero"])
	if m == "PUNTO": c["punto"] = (punto as Array).duplicate() if punto != null else [av["p"][0], av["p"][1]]; c["alt"] = maxf(h, suelo0() + P["h_min"]); c["vel"] = maxf(c["vel"], P["v_crucero"])
	if m == "BASE": c["punto"] = punto_base(); c["alt"] = suelo0() + P["h_base"]; c["vel"] = float(P["v_crucero"])
	if m == "DESPEGUE": fase = "carrera"; automatico = true
	if m == "ATERRIZAJE": fase = "llegada"; automatico = true; c["vel"] = float(P["v_aprox"])
	return NOMBRE[m]

func suelo0() -> float: return float(pista["h"]) if pista != null else float(casa[2])
func punto_base() -> Array: return centro_pista() if pista != null else [casa[0], casa[1]]
## Punto de la pista a d m del umbral (a lo largo del eje) y t m a su derecha.
func en_pista(d: float, t: float) -> Array:
	var r: float = float(pista["rumbo"]) * D2R
	return [pista["n"] + d * cos(r) - t * sin(r), pista["e"] + d * sin(r) + t * cos(r)]
func centro_pista() -> Array: return en_pista(pista["largo"] / 2.0, 0.0)
## (d, t): distancia a lo largo del eje de la pista desde el umbral y desvio lateral (+ a la derecha).
func eje_pista(N: float, E: float) -> Array:
	var r: float = float(pista["rumbo"]) * D2R; var dn: float = N - pista["n"]; var de: float = E - pista["e"]
	return [dn * cos(r) + de * sin(r), -dn * sin(r) + de * cos(r)]

var _out := {}
var _e := []
var _V := 1.0
var _dt := 0.0
var _av := {}
var _vzc := 0.0                  # la subida pedida (la pone _altura; si no, la que lleva)

func _actitud(phi: float, th: float) -> void:
	var av := _av; var e := _e
	_out["yaw"] = lim(P["k_alabeo"] * (phi - e[0]) - P["k_p"] * av["w"][0], -1, 1)
	var sobra: float = av["alfa"] - P["alfa_max"]; var lento: float = P["v_alarma"] - _V
	if sobra > 0 or lento > 0: th = minf(th, e[1] - P["k_alfa"] * maxf(sobra, 0) * D2R - 0.02 * maxf(lento, 0))
	if sobra <= 0 and lento <= 0: iTh = lim(iTh + P["k_i_cabeceo"] * (th - e[1]) * _dt, -0.5, 0.5)     # con la proteccion actuando, el integrador quieto
	_out["pitch"] = lim(P["k_cabeceo"] * (th - e[1]) - P["k_q"] * av["w"][1] + iTh, -1, 1)
	_out["guinada"] = lim(-P["k_derrape"] * av["beta"] * D2R - P["k_r"] * (av["w"][2] - G0 * sin(e[0]) / _V), -1, 1)

func _rumbo(psi: float) -> float:          # despacio, menos alabeo
	var aMax: float = P["alabeo_max"] * D2R * lim((_V - P["v_alarma"]) / (P["v_crucero"] - P["v_alarma"]), 0.3, 1)
	return lim(P["k_rumbo"] * envolver(psi - _e[2]), -aMax, aMax)

func _altura(hc: float, vz_max: float, h: float, vz: float) -> float:
	var vzc := lim(P["k_altura"] * (hc - h), -vz_max, vz_max); _vzc = vzc
	return lim(atan2(vzc, _V) + P["k_vz"] * (vzc - vz) + P["cabeceo_crucero"] * D2R, P["cabeceo_min"] * D2R, P["cabeceo_max"] * D2R)

func _velocidad(vc: float, vz: float) -> float:          # y mas gas si tiene que subir
	iV = lim(iV + P["k_i_gas"] * (vc - _V) * _dt, -0.4, 0.4)
	return 1.0 if _V < P["v_alarma"] else lim(P["gas_crucero"] + P["k_gas"] * (vc - _V) + P["k_gas_vz"] * (_vzc - vz) + iV, 0, 1)

## Un paso. pal: palancas {pitch, yaw, guinada}; gas_palanca (0..1): en crucero elige la velocidad. Devuelve
## {pitch, yaw, guinada, gas, freno}: gas y freno null si no los lleva.
func paso(av: Dictionary, dt: float, pal: Dictionary, gas_palanca: float) -> Dictionary:
	_e = Cuat.euler(av["q"]); _V = maxf(1, _norma(av["v"])); _dt = dt; _av = av
	var e := _e; var V := _V
	var vn := Cuat.rot(av["q"], av["v"]); var vz: float = -vn[2]; var h: float = -av["p"][2]; var m := modo
	_vzc = vz
	_out = { "pitch": pal["pitch"], "yaw": pal["yaw"], "guinada": pal["guinada"], "gas": null, "freno": null }
	var out := _out
	if m == "MANUAL": return out
	if m == "ESTAB":
		_actitud(pal["yaw"] * P["alabeo_max"] * D2R, (pal["pitch"] * P["cabeceo_max"] + (1 - absf(pal["pitch"])) * P["cabeceo_crucero"]) * D2R)
		return out
	if m == "CRUCERO":
		c["rumbo"] = envolver(c["rumbo"] + pal["yaw"] * P["giro_consigna"] * D2R * dt)
		c["alt"] = maxf(suelo0() + P["h_min"] * 0.5, c["alt"] + pal["pitch"] * P["subida_consigna"] * dt)
		if gas_visto != null and absf(gas_palanca - gas_visto) > 1e-3: c["vel"] = P["v_min"] + lim(gas_palanca, 0, 1) * (P["v_max"] - P["v_min"])
		gas_visto = gas_palanca
		_actitud(_rumbo(c["rumbo"]), _altura(c["alt"], P["vz_max"], h, vz)); out["gas"] = _velocidad(c["vel"], vz)
		return out
	if m == "PUNTO" or m == "BASE":
		var cN: float = c["punto"][0]; var cE: float = c["punto"][1]; var dn: float = av["p"][0] - cN; var de: float = av["p"][1] - cE
		var d := sqrt(dn * dn + de * de); var a := atan2(de, dn); var R: float = P["radio_orbita"]
		c["rumbo"] = atan2(-de, -dn) if d > 3 * R else envolver(a + PI / 2 + atan((d - R) / P["k_orbita"]))
		c["alt"] += pal["pitch"] * P["subida_consigna"] * dt
		_actitud(_rumbo(c["rumbo"]), _altura(c["alt"], P["vz_max"], h, vz)); out["gas"] = _velocidad(c["vel"], vz)
		return out
	var ps: Dictionary = pista; var rp: float = float(ps["rumbo"]) * D2R; var et := eje_pista(av["p"][0], av["p"][1]); var dEje: float = et[0]; var tEje: float = et[1]
	var agl: float = av["agl"] if av.has("agl") else h - ps["h"]
	if m == "DESPEGUE":
		out["freno"] = 0.0; out["gas"] = 1.0
		if fase == "carrera":
			out["yaw"] = lim(-P["k_alabeo"] * e[0] - P["k_p"] * av["w"][0], -1, 1)
			out["guinada"] = lim(P["k_rumbo_tierra"] * envolver(rp - e[2]) - P["k_eje"] * tEje - P["k_r_tierra"] * av["w"][2], -1, 1)
			out["pitch"] = lim(P["k_cabeceo"] * (P["cabeceo_rotacion"] * D2R - e[1]) - P["k_q"] * av["w"][1], -1, 1) if V > P["v_rotacion"] else 0.0
			if not av.get("enTierra", false) and agl > 2: fase = "subida"
			return out
		_actitud(_rumbo(envolver(rp - atan(tEje / 200.0))), P["cabeceo_subida"] * D2R)
		if agl > P["h_fin_despegue"]:
			poner("CRUCERO", av); c["alt"] = ps["h"] + P["h_base"]; c["rumbo"] = rp; c["vel"] = float(P["v_crucero"])
			return paso(av, 0.0, { "pitch": 0.0, "yaw": 0.0, "guinada": 0.0 }, gas_palanca)
		return out
	var dEntrada: float = P["final_m"] + 1500; var tg := tan(P["senda_grados"] * D2R); var hFinal: float = ps["h"] + P["final_m"] * tg
	if fase == "llegada":
		var f := en_pista(-dEntrada, 0.0); var d := Vector2(av["p"][0] - f[0], av["p"][1] - f[1]).length()
		_actitud(_rumbo(atan2(f[1] - av["p"][1], f[0] - av["p"][0])), _altura(maxf(hFinal, minf(h, ps["h"] + P["h_base"])), P["vz_max"], h, vz)); out["gas"] = _velocidad(P["v_crucero"], vz)
		if d < 500 or (dEje < -P["final_m"] and absf(tEje) < 300 and absf(envolver(rp - e[2])) < 45 * D2R): fase = "final"
		return out
	if fase == "final":
		var hs: float = ps["h"] + minf(P["final_m"], -dEje) * tg + P["h_umbral"]
		_actitud(_rumbo(envolver(rp - atan(tEje / P["k_eje_aire"]))), _altura(hs, P["vz_max"], h, vz)); out["gas"] = _velocidad(P["v_crucero"] if -dEje > P["final_m"] else P["v_aprox"], vz)
		if agl < P["h_recogida"]: fase = "recogida"
		return out
	if fase == "recogida":            # cerca del suelo: gas fuera, alas niveladas, el morro con la pista (sin deriva) y
		var vzr: float = -(P["vz_toma"] + P["k_recogida"] * agl); _vzc = vzr     # bajando cada vez mas despacio (sin flotar con el efecto suelo)
		_actitud(0.0, lim(atan2(vzr, _V) + P["k_vz"] * (vzr - vz) + P["cabeceo_crucero"] * D2R, 0, P["cabeceo_recogida"] * D2R)); out["gas"] = 0.0
		out["guinada"] = lim(P["k_rumbo_tierra"] * envolver(rp - e[2]) - P["k_r_tierra"] * av["w"][2], -1, 1)
		if av.get("enTierra", false): fase = "rodadura"
		return out
	out["gas"] = 0.0; out["freno"] = 0.7 if V > 2 else 1.0; out["pitch"] = -0.2
	out["yaw"] = lim(-P["k_alabeo"] * e[0] - P["k_p"] * av["w"][0], -1, 1)
	out["guinada"] = lim(P["k_rumbo_tierra"] * envolver(rp - e[2]) - P["k_eje"] * tEje - P["k_r_tierra"] * av["w"][2], -1, 1)
	return out
