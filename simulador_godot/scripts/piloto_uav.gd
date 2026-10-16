class_name PilotoUAV
extends RefCounted
## Piloto automatico de un UAV de ala fija (Cernicalo XM-7 y Grajo MX-2): traduccion LITERAL de simulador/js/piloto_uav.js (mismas
## capas, mismos modos y mismas ganancias, que vienen en datos.piloto). pruebas/prueba_piloto_uav.gd compara los dos.
## Por capas: el lazo interior lleva el alabeo y el cabeceo con los alerones y la profundidad (y amortigua la guinada con
## los timones; con proteccion contra la perdida); encima, el rumbo, la altura y la velocidad (con el gas); y encima, la
## navegacion (ir a un punto y dar vueltas sobre el, volver a la base) y el despegue y el aterrizaje en la pista. Sin pista
## (el Grajo, lanzado a mano): LANZAMIENTO y ATERRIZAJE en perdida profunda en un punto (datos.piloto.toma), contra el viento.
## Angulos en radianes; posiciones NED (m) del simulador; altura = -p[2].

const MODOS := ["MANUAL", "ESTAB", "CRUCERO", "PUNTO", "BASE", "DESPEGUE", "ATERRIZAJE", "LANZAMIENTO"]
const NOMBRE := { "MANUAL": "Manual", "ESTAB": "Estabilizado", "CRUCERO": "Crucero", "PUNTO": "Ir a punto", "BASE": "Vuelta a base",
				  "DESPEGUE": "Despegue automático", "ATERRIZAJE": "Aterrizaje automático", "LANZAMIENTO": "Lanzamiento" }
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
var viento_desde := 0.0          # de donde viene el viento (rad): la toma sin pista se hace contra el
var viento_vel := 0.0

func _init(P_: Dictionary, pista_, casa_: Array) -> void:
	P = P_; pista = pista_; casa = casa_; c["vel"] = float(P["v_crucero"])

static func envolver(a: float) -> float: return a - TAU * floor(a / TAU + 0.5)      # Math.round de JS: las mitades hacia arriba
static func lim(x: float, a: float, b: float) -> float: return maxf(a, minf(b, x))
static func _norma(v: Array) -> float: return sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2])

## Cambia de modo con las consignas de lo que esta haciendo ahora. Devuelve el texto para el aviso o "" si no se puede.
func poner(m: String, av: Dictionary, punto = null) -> String:
	var e := Cuat.euler(av["q"]); var V: float = float(av["V"]) if P.get("pitot", false) and av.get("V") != null else _norma(av["v"]); var h: float = -av["p"][2]
	var en_tierra: bool = av.get("enTierra", false)
	if m == "DESPEGUE" and not (pista != null and en_tierra): return ""
	if m == "ATERRIZAJE" and ((pista == null and not P.has("toma")) or en_tierra): return ""
	if m == "LANZAMIENTO" and pista != null: return ""
	if m in ["CRUCERO", "PUNTO", "BASE", "ESTAB"] and en_tierra: return ""
	modo = m; fase = ""; iTh = 0.0; iV = 0.0; gas_visto = null
	c["alt"] = h; c["rumbo"] = e[2]; c["vel"] = lim(V, P["v_min"], P["v_max"])
	if m == "CRUCERO": c["vel"] = float(P["v_crucero"])
	if m == "PUNTO": c["punto"] = (punto as Array).duplicate() if punto != null else [av["p"][0], av["p"][1]]; c["alt"] = maxf(h, suelo0() + P["h_min"]); c["vel"] = maxf(c["vel"], P["v_crucero"])
	if m == "BASE": c["punto"] = punto_base(); c["alt"] = suelo0() + P["h_base"]; c["vel"] = float(P["v_crucero"])
	if m == "DESPEGUE": fase = "carrera"; automatico = true
	if m == "ATERRIZAJE":
		fase = "llegada"; automatico = true; c["vel"] = float(P["v_aprox"])
		if pista == null: c["punto"] = (punto as Array).duplicate() if punto != null else [casa[0], casa[1]]
	if m == "LANZAMIENTO": fase = "subida"; automatico = true
	av["profToma"] = false
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
	# sin alerones (el Grajo: datos.piloto.timon_alabeo): el timon hace alabear (con el poliedro) y amortigua la guinada a la vez
	if P.get("timon_alabeo", false): _out["yaw"] = lim(P["k_alabeo"] * (phi - e[0]) - P["k_p"] * av["w"][0] - P["k_r"] * (av["w"][2] - G0 * sin(e[0]) / _V), -1, 1)
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
var sens = null                  # sensores averiados (desgaste.gd: el Grajo); el piloto trabaja con lo que creen
var _con_sens := false
func paso(av: Dictionary, dt: float, pal: Dictionary, gas_palanca: float) -> Dictionary:
	if sens != null and not _con_sens:          # con lo que creen el GPS, la brujula, la IMU y el barometro (como en JS)
		var S: Dictionary = sens; var e0 := Cuat.euler(av["q"]); var t: float = av["t"]; var dz: float = S["vz"] * t
		var ae := av.duplicate()
		ae["p"] = [av["p"][0] + (S["gps"] * cos(2 * PI * t / 25) if S["gps"] else 0.0), av["p"][1] + (S["gps"] * sin(2 * PI * t / 31) if S["gps"] else 0.0), av["p"][2] + dz]
		ae["q"] = Cuat.desde_euler(e0[0] + S["alabeo"], e0[1] + S["cabeceo"], e0[2] + S["rumbo"])
		if av.get("agl") != null: ae["agl"] = av["agl"] - dz
		_con_sens = true; var r := paso(ae, dt, pal, gas_palanca); _con_sens = false
		av["profToma"] = ae.get("profToma", false); return r
	_e = Cuat.euler(av["q"]); _V = maxf(1, float(av["V"]) if P.get("pitot", false) and av.get("V") != null else _norma(av["v"])); _dt = dt; _av = av   # con datos.piloto.pitot (el Grajo), la del aire
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
	if m == "LANZAMIENTO":             # lanzado a mano: motor a tope, alas niveladas y a subir; arriba, crucero
		out["gas"] = 1.0; _actitud(0.0, P["cabeceo_subida"] * D2R)
		var agl0: float = float(av["agl"]) if av.get("agl") != null else h - suelo0()
		if agl0 > P["h_fin_despegue"]:
			var r: float = c["rumbo"]; poner("CRUCERO", av); c["alt"] = suelo0() + P["h_base"]; c["rumbo"] = r; c["vel"] = float(P["v_crucero"])
			return paso(av, 0.0, { "pitch": 0.0, "yaw": 0.0, "guinada": 0.0 }, gas_palanca)
		return out
	if m == "ATERRIZAJE" and pista == null: return _toma_perdida(av, out, e, h, vz)
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

## Toma en perdida profunda en el punto c.punto (sin pista: el Grajo), contra el viento (tomaPerdida de JS): entrada a
## d_final m a sotavento a h_entrada; por la final bajando hasta h_perdida; y donde va a caer en el punto, motor parado,
## profundidad arriba del todo (av.profToma) y alas niveladas hasta el suelo.
func _toma_perdida(av: Dictionary, out: Dictionary, e: Array, h: float, vz: float) -> Dictionary:
	var T: Dictionary = P["toma"]; var tN: float = c["punto"][0]; var tE: float = c["punto"][1]; var hT: float = casa[2]
	var rf := viento_desde; var cf := cos(rf); var sf := sin(rf)
	var dn: float = av["p"][0] - tN; var de: float = av["p"][1] - tE; var a := -(dn * cf + de * sf); var t := -dn * sf + de * cf
	var agl: float = float(av["agl"]) if av.get("agl") != null else h - hT
	av["profToma"] = false
	if fase == "llegada":
		var eN: float = tN - T["d_final"] * cf; var eE: float = tE - T["d_final"] * sf; var d := Vector2(av["p"][0] - eN, av["p"][1] - eE).length()
		_actitud(_rumbo(atan2(eE - av["p"][1], eN - av["p"][0])), _altura(maxf(hT, h - agl) + T["h_entrada"], P["vz_max"], h, vz)); out["gas"] = _velocidad(P["v_crucero"], vz)
		if d < 25 or (a > 0.6 * T["d_final"] and a < 1.3 * T["d_final"] and absf(t) < 25 and absf(envolver(rf - e[2])) < 30 * D2R): fase = "final"
		return out
	if fase == "final":
		var hs: float = maxf(hT + T["h_perdida"] + maxf(0.0, a - d_perdida(agl)) * (T["h_entrada"] - T["h_perdida"]) / T["d_final"], h - agl + 0.8 * T["h_perdida"])
		_actitud(_rumbo(envolver(rf - atan(t / 30.0))), _altura(hs, P["vz_max"], h, vz))
		out["gas"] = _velocidad(P["v_aprox"], vz)
		if a <= d_perdida(agl): fase = "perdida"
		if a < -40: fase = "llegada"
		return out
	_actitud(0.0, 0.0); out["gas"] = 0.0; out["pitch"] = float(T["prof"]); av["profToma"] = true
	return out

## Lo que avanza sobre el suelo desde que entra en perdida a agl m de altura (dPerdida de JS).
func d_perdida(agl: float) -> float:
	var w := maxf(0.0, viento_vel); var vb := 6.0
	return maxf(0.0, agl * (vb - w) / vb) + 8
