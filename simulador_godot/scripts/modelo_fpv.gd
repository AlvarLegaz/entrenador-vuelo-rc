class_name ModeloFPV
extends RefCounted
## Dron FPV de 5 pulgadas con controlador tipo Betaflight: traduccion LITERAL de la clase ModeloFPV de
## simulador/aviones/FPV.js (mismos datos, mismas formulas, mismo orden). pruebas/prueba_fpv.gd la compara con trazas
## de la del navegador. Si se cambia algo aqui, hay que cambiarlo igual alli (y al reves).
## Sin GPS ni retencion de posicion ni de altura: el gas (av.gases, 0-1) va directo a los motores. Modos de Betaflight
## (modo): ANGLE (la palanca derecha pide inclinacion, hasta 55 grados, y al soltarla se nivela), HORIZON (ANGLE cerca
## del centro, ACRO a fondo) y ACRO (pide velocidad de giro con las tasas RC rate / super rate / expo; sin autonivelado).
## PI de velocidades de giro -> mezclador en X con airmode -> 4 motores con su respuesta -> empuje (entrada de aire,
## efecto suelo, propwash), par de reaccion y de aceleracion de los rotores -> 6 grados de libertad. Bateria 4S con caida
## de tension (sag). Armado (lanzar), desarmado (desarmar), posado en el suelo y aterrizado al desarmar tras volar.
## Mandos: yaw = alabeo, pitch = cabeceo (+ = palanca hacia ti), guinada. Mismos ejes y estado que ModeloCuadricoptero.

const D2R := PI / 180.0
const G0 := 9.81
const RHO := 1.225

var datos: Dictionary
var es_cuadricoptero := true
var es_fpv := true
var modo := "ANGLE"             # modo de vuelo de Betaflight: "ANGLE", "HORIZON" o "ACRO"
var S_m2: float; var b_m: float; var c_m: float; var masa_kg: float
var inercia: Dictionary; var inercia_diseno: Dictionary; var masa_diseno_kg: float
var cg_mm: Array; var propulsion: Dictionary; var mandos: Dictionary; var fc: Dictionary
var compensador_grados := 0.0; var lanzamiento: Dictionary
var dcg := 0.0; var rho := RHO; var calib := { "empuje": 1.0, "resistencia": 1.0 }
var temp_c := 15.0; var B: Dictionary            # LiPo 4S con su curva (bateria.gd)
## dificultad facil: la mitad del viento sobre la resistencia, sin turbulencia que alabea, sin entrada de aire en el
## empuje, sin efecto suelo y sin propwash (como en JS)
var facil := false

func _init(d: Dictionary) -> void:
	datos = d
	S_m2 = d["S_m2"]; b_m = d["b_m"]; c_m = d.get("c_m", 0.0); masa_kg = d["masa_kg"]
	inercia = d["inercia"].duplicate(); inercia_diseno = d["inercia"].duplicate(); masa_diseno_kg = d["masa_kg"]
	cg_mm = d["cg_mm"]; propulsion = d["propulsion"]; fc = d["fc"]; mandos = d["mandos"].duplicate()
	compensador_grados = d.get("compensador_grados", 0.0); lanzamiento = d["lanzamiento"]
	B = Bateria.datos(propulsion)

## Masa, temperatura (densidad), empuje estatico medido (gf, el de los 4 motores) y factor de resistencia. (cg_mm no se usa.)
func configurar(op: Dictionary) -> void:
	if op.has("temperatura"): rho = 101325 / (287.05 * (op["temperatura"] + 273.15)); temp_c = op["temperatura"]
	if op.get("empuje_gf", 0): calib["empuje"] = op["empuje_gf"] / 1000.0 * G0 / (4 * propulsion["empuje_motor_N"])
	if op.get("resistencia", 0): calib["resistencia"] = op["resistencia"]
	if op.get("masa_kg", 0):
		masa_kg = op["masa_kg"]
		var k := masa_kg / masa_diseno_kg
		for n in inercia_diseno.keys(): inercia[n] = inercia_diseno[n] * k

## Tension en vacio de la bateria (V) con lo gastado hasta ahora.
func _voc(av: Dictionary) -> float:
	var s := 0.0; var o := Bateria.ocv_celda(B, av["bat"])
	for i in int(B["celdas"]): s += o
	return s

## En el suelo y desarmado ("en mano" para el simulador: lanzar() lo arma).
func estado_inicial() -> Dictionary:
	var bat := Bateria.nueva(B, temp_c)
	return { "p": [0.0, 0.0, -0.02], "q": Cuat.desde_euler(0, 0, 0), "v": [0.0, 0.0, 0.0], "w": [0.0, 0.0, 0.0], "de": 0.0, "dr": 0.0, "da": 0.0,
			 "gases": 0.0, "Wh": 0.0, "asim": 0.0, "estado": "en mano", "t": 0.0, "alfa": 0.0, "beta": 0.0, "V": 0.0, "g_carga": 1.0, "perdida": 0.0,
			 "T": 0.0, "rpm": 0.0, "motorRoto": false, "posado": true, "despegado": false, "armado": false, "tArmado": 0.0,
			 "cmd": { "alabeo": 0.0, "cabeceo": 0.0, "guinada": 0.0 }, "integ": [0.0, 0.0, 0.0], "motores": [0.0, 0.0, 0.0, 0.0],
			 "mAh": 0.0, "Vbat": bat["V"], "I": 0.0, "P": 0.0, "propwash": 0.0, "bat": bat }

## Armar (el simulador comprueba antes que el gas este abajo): motores al ralenti en el suelo.
func lanzar(av: Dictionary) -> void:
	av["v"] = [0.0, 0.0, 0.0]; av["w"] = [0.0, 0.0, 0.0]; av["estado"] = "volando"; av["armado"] = true; av["integ"] = [0.0, 0.0, 0.0]
	av["posado"] = true; av["despegado"] = false; av["q"] = Cuat.desde_euler(0, 0, Cuat.euler(av["q"])[2])

## Desarmar: los motores se paran. En el suelo antes de despegar vuelve a "en mano" (se puede armar otra vez).
func desarmar(av: Dictionary) -> void:
	av["armado"] = false
	if av["posado"] and not av["despegado"]: av["estado"] = "en mano"

## Para los escenarios que empiezan en el aire: armado, en vuelo y con el gas que lo sostiene.
func armar_en_vuelo(av: Dictionary) -> void:
	av["armado"] = true; av["posado"] = false; av["despegado"] = true; av["integ"] = [0.0, 0.0, 0.0]
	var F := fc; var kV: float = _voc(av) / propulsion["V_ref"]; var Tm: float = propulsion["empuje_motor_N"] * calib["empuje"] * kV * kV
	var u := sqrt(masa_kg * G0 / 4 / Tm)
	av["gases"] = clampf((u - F["ralenti"]) / (1 - F["ralenti"]), 0, 1); av["motores"] = [u * kV, u * kV, u * kV, u * kV]

static func _cl(x) -> float:
	var f: float = 0.0 if x == null else float(x)
	if is_nan(f): f = 0.0
	return maxf(-1, minf(1, f))

## Palancas -> consignas (con la exponencial del simulador: con mando la pone el mando y expo vale 0), con el suavizado
## de la emisora. mando: yaw = alabeo, pitch = cabeceo (+ = palanca hacia ti), guinada.
func servos(av: Dictionary, mando: Dictionary, dt: float) -> void:
	var e: float = mandos.get("expo", 0.0)
	var ex := func(s: float) -> float: return (1 - e) * s + e * s * s * s
	var obj := { "alabeo": ex.call(_cl(mando.get("yaw"))), "cabeceo": ex.call(_cl(-float(mando.get("pitch", 0.0)))), "guinada": ex.call(_cl(mando.get("guinada"))) }
	var k := minf(1, dt / fc["rc_suavizado_s"])
	var cmd: Dictionary = av["cmd"]
	for n in obj: cmd[n] += (obj[n] - cmd[n]) * k

## Sin superficies de mando (misma firma que ModeloAvion.mandos_coef).
func mandos_coef(_av = null, _d = null, _kman = 1.0) -> Dictionary:
	return { "CL": 0.0, "CY": 0.0, "Cl": 0.0, "Cm": 0.0, "Cn": 0.0 }

## Tasa de Betaflight (grados/s) de una palanca s (-1..1): RC rate, super rate y expo.
func tasa(s: float, R: Dictionary) -> float:
	var a := absf(s); var x: float = s * a * a * a * R["expo"] + s * (1 - R["expo"])
	var rc: float = R["rc"]
	if rc > 2: rc += 14.54 * (rc - 2)
	var t := 200 * rc * x
	if R["super"]: t *= 1 / maxf(0.01, minf(1, 1 - a * R["super"]))
	return maxf(-1998, minf(1998, t))

## Curva de gas de Betaflight (thr_mid, thr_expo): con expo 0 es lineal.
func curva_gas(g: float) -> float:
	var F := fc; var d: float = g - F["gas_medio"]; var y: float = (1 - F["gas_medio"]) if d > 0 else (F["gas_medio"] if d < 0 else 1.0)
	return F["gas_medio"] + d * (1 - F["gas_expo"] + F["gas_expo"] * d * d / (y * y))

## Un paso: bateria -> controlador (tasas, PI, mezclador con airmode) -> motores -> empuje y pares -> 6 grados de libertad.
## viento: NED (m/s). Opcionales en av: agl (altura sobre el suelo) y pg (alabeo de la turbulencia). Devuelve la velocidad NED.
func paso(av: Dictionary, viento: Array, dt: float) -> Array:
	var m := masa_kg; var I := inercia; var F := fc; var pr := propulsion; var q: Array = av["q"]; var v: Array = av["v"]; var w: Array = av["w"]; var FAC := facil
	var tiene_agl: bool = av.get("agl") != null
	var suelo: float = 0.0 if not tiene_agl else -av["p"][2] - av["agl"]
	var agl: float = 100.0 if not tiene_agl else av["agl"]
	var eu := Cuat.euler(q); var roll: float = eu[0]; var pitch: float = eu[1]; var yaw: float = eu[2]
	# --- bateria: tension en vacio segun lo gastado y caida por la resistencia interna con la potencia del paso anterior ---
	var V := Bateria.tension(B, av["bat"])
	av["Vbat"] = V
	var kV: float = V / pr["V_ref"]; var Tref: float = pr["empuje_motor_N"] * calib["empuje"]; var TmaxV: float = Tref * kV * kV; var idle: float = F["ralenti"]
	# --- controlador de vuelo: consignas de velocidad de giro segun el modo ---
	var c: Dictionary = av["cmd"]; var T3: Dictionary = F["tasas"]; var lim: float = F["angulo_max_grados"] * D2R; var kn: float = F["k_nivel"]
	var acroP: float = tasa(c["alabeo"], T3["alabeo"]) * D2R; var acroQ: float = -tasa(c["cabeceo"], T3["cabeceo"]) * D2R; var rSet: float = tasa(c["guinada"], T3["guinada"]) * D2R
	var nivP: float = kn * (c["alabeo"] * lim - roll); var nivQ: float = kn * (-c["cabeceo"] * lim - pitch)
	var pSet: float; var qSet: float
	if modo == "ACRO":
		pSet = acroP; qSet = acroQ
	elif modo == "HORIZON":
		var lv := maxf(0, 1 - maxf(absf(c["alabeo"]), absf(c["cabeceo"])) / F["horizon_transicion"])
		pSet = lv * nivP + (1 - lv) * acroP; qSet = lv * nivQ + (1 - lv) * acroQ
	else:
		pSet = nivP; qSet = nivQ
	# PI de velocidades de giro (en el suelo, apagado y sin integral)
	var armado: bool = av["armado"] and not av["motorRoto"]
	var L := 0.0; var Mm := 0.0; var N := 0.0
	if armado and not av["posado"]:
		var e := [pSet - w[0], qSet - w[1], rSet - w[2]]
		var integ: Array = av["integ"]
		for i in 3: integ[i] = maxf(-F["i_max"], minf(F["i_max"], integ[i] + e[i] * dt))
		L = I["Ixx"] * (F["kp"][0] * e[0] + F["ki"][0] * integ[0])
		Mm = I["Iyy"] * (F["kp"][1] * e[1] + F["ki"][1] * integ[1])
		N = maxf(-F["tau_guinada"], minf(F["tau_guinada"], I["Izz"] * (F["kp"][2] * e[2] + F["ki"][2] * integ[2])))
	else: av["integ"] = [0.0, 0.0, 0.0]
	# mezclador en X con airmode
	var uc: float = idle + (1 - idle) * curva_gas(clampf(float(av.get("gases", 0.0)), 0, 1))
	var Tc: float = TmaxV * uc * uc
	var a: float = F["brazo_m"]; var kq: float = pr["k_par_m"]; var Mot: Array = F["motores"]; var dT := [0.0, 0.0, 0.0, 0.0]
	for i in 4:
		var x: float = Mot[i][0]; var y: float = Mot[i][1]; var s: float = Mot[i][2]
		dT[i] = -(1.0 if y > 0 else -1.0) * L / (4 * a) + (1.0 if x > 0 else -1.0) * Mm / (4 * a) - s * N / (4 * kq)
	var dmin: float = minf(minf(dT[0], dT[1]), minf(dT[2], dT[3])); var dmax: float = maxf(maxf(dT[0], dT[1]), maxf(dT[2], dT[3]))
	var Tmin := TmaxV * idle * idle; var rango := TmaxV - Tmin
	if dmax - dmin > rango:
		var k := rango / (dmax - dmin)
		for i in 4: dT[i] *= k
		dmin *= k; dmax *= k
	if Tc + dmax > TmaxV: Tc = TmaxV - dmax
	if Tc + dmin < Tmin: Tc = Tmin - dmin
	# --- motores: vueltas con su retardo; empuje con la entrada de aire, el efecto suelo y el propwash; pares de los rotores ---
	var wb := Cuat.rot_inv(q, [0.5 * viento[0], 0.5 * viento[1], 0.5 * viento[2]] if FAC else viento)
	var va := [v[0] - wb[0], v[1] - wb[1], v[2] - wb[2]]; var Va: float = sqrt(va[0] * va[0] + va[1] * va[1] + va[2] * va[2])
	var D: float = pr["D_m"]; var A: float = PI * D * D / 4; var Wmax: float = pr["rpm_max"] * 2 * PI / 60; var km: float = minf(1, dt / F["tau_motor_s"])
	var zs := maxf(agl, 0.06); var kGE: float = 1.0 if FAC else 1 / (1 - pow(D / 2 / (4 * zs), 2))
	var mot: Array = av["motores"]
	var T0 := 0.0
	for i in 4: T0 += Tref * mot[i] * mot[i]
	var vh: float = sqrt(maxf(T0, 0.05) / (2 * rho * 4 * A)); var vd: float = va[2]; var vlat2: float = va[0] * va[0] + va[1] * va[1]
	var ipw: float = 0.0 if (FAC or not armado) else exp(-pow((vd - 0.8 * vh) / (0.5 * vh), 2)) * exp(-vlat2 / 16)
	av["propwash"] = ipw
	var Tt := 0.0; var Lr := 0.0; var Mr := 0.0; var Nr := 0.0; var P: float = pr["P_electronica_W"]
	for i in 4:
		var x: float = Mot[i][0]; var y: float = Mot[i][1]; var s: float = Mot[i][2]
		var u: float = maxf(idle, minf(1, sqrt(maxf(0, (Tc + dT[i]) / TmaxV)))) if armado else 0.0
		var f0: float = mot[i]; var f: float = f0 + (u * kV - f0) * km
		mot[i] = f
		var n: float = f * pr["rpm_max"] / 60; var kJ: float = 1.0 if FAC else maxf(0, minf(1.15, 1 - -va[2] / (pr["J0"] * maxf(n, 1) * D)))
		var T: float = Tref * f * f * kJ * kGE * (1 - F["propwash_perdida"] * ipw)
		Tt += T
		Lr += -y * T; Mr += x * T; Nr += -s * (kq * T + pr["I_rotor"] * (f - f0) * Wmax / dt)
		P += kq * T * f * Wmax / pr["rendimiento"]
	# sacudidas del propwash (deterministas: dos senos de 7 y 13 Hz) y turbulencia que alabea (Entorno.rafaga_alabeo)
	var t: float = av["t"]
	Lr += ipw * F["propwash_par"] * (0.6 * sin(2 * PI * 7.3 * t) + 0.4 * sin(2 * PI * 12.9 * t + 1.3))
	Mr += ipw * F["propwash_par"] * (0.6 * sin(2 * PI * 8.1 * t + 0.7) + 0.4 * sin(2 * PI * 11.7 * t + 2.1))
	var pg: float = float(av.get("pg", 0.0)) if av.get("pg") != null else 0.0
	if pg and not FAC: Lr += I["Ixx"] * pg * 4
	# --- bateria: potencia de los motores y de la electronica; corriente con la tension ---
	var eb: Dictionary = av["bat"]; Bateria.gastar(B, eb, P, dt); av["P"] = eb["P"]; av["I"] = eb["I"]; av["mAh"] = eb["mAh"]; av["Wh"] = eb["Wh"]
	av["T"] = Tt; av["rpm"] = 0.25 * (mot[0] + mot[1] + mot[2] + mot[3]) * pr["rpm_max"]
	av["alfa"] = 0.0; av["beta"] = 0.0; av["perdida"] = 0.0; av["g_carga"] = Tt / (m * G0)
	if armado: av["tArmado"] += dt
	# --- en el suelo: quieto hasta que el empuje supera el peso; desarmado despues de volar, aterrizado ---
	if av["posado"]:
		if Tt <= m * G0 * 1.02 or not armado:
			av["v"] = [0.0, 0.0, 0.0]; av["w"] = [0.0, 0.0, 0.0]; av["q"] = Cuat.desde_euler(0, 0, yaw); av["p"][2] = -(suelo + 0.02); av["V"] = 0.0; av["t"] += dt
			if not av["armado"] and av["despegado"]: av["p"][2] = -(suelo - 0.05)        # desarmado tras volar: el simulador lo da por aterrizado
			return [0.0, 0.0, 0.0]
		av["posado"] = false    # despega
	# --- fuerzas en ejes cuerpo: empuje, peso, resistencia del cuerpo y de los rotores ---
	var kd: float = 0.5 * rho * Va * calib["resistencia"]
	var Fx: float = -kd * F["cda_h"] * va[0] - F["k_rotor"] * Tt * va[0]; var Fy: float = -kd * F["cda_h"] * va[1] - F["k_rotor"] * Tt * va[1]; var Fz0: float = -kd * F["cda_v"] * va[2]
	var gb := Cuat.rot_inv(q, [0.0, 0.0, G0])
	var Fb := [Fx + m * gb[0], Fy + m * gb[1], Fz0 + m * gb[2] - Tt]
	# --- ecuaciones de Euler (sin producto de inercia) e integracion ---
	var dv := [Fb[0] / m - (w[1] * v[2] - w[2] * v[1]), Fb[1] / m - (w[2] * v[0] - w[0] * v[2]), Fb[2] / m - (w[0] * v[1] - w[1] * v[0])]
	var Iw := [I["Ixx"] * w[0], I["Iyy"] * w[1], I["Izz"] * w[2]]
	var dw := [(Lr - (w[1] * Iw[2] - w[2] * Iw[1])) / I["Ixx"], (Mr - (w[2] * Iw[0] - w[0] * Iw[2])) / I["Iyy"], (Nr - (w[0] * Iw[1] - w[1] * Iw[0])) / I["Izz"]]
	for i in 3:
		v[i] += dv[i] * dt; w[i] += dw[i] * dt
	var dq := Cuat.mul(q, [0.0, w[0], w[1], w[2]])
	av["q"] = Cuat.norm([q[0] + 0.5 * dq[0] * dt, q[1] + 0.5 * dq[1] * dt, q[2] + 0.5 * dq[2] * dt, q[3] + 0.5 * dq[3] * dt])
	var vn2 := Cuat.rot(av["q"], v)
	var p: Array = av["p"]
	for i in 3: p[i] += vn2[i] * dt
	av["t"] += dt; av["V"] = Va
	# --- suelo: toma suave -> posado; si no, la decide el simulador (Entorno.contacto_suelo: aterrizado o roto) ---
	var agl2: float = -p[2] - suelo
	if agl2 > 0.3: av["despegado"] = true
	if agl2 <= 0.02 and vn2[2] >= 0 and vn2[2] < F["toma_vz"] and vn2[0] * vn2[0] + vn2[1] * vn2[1] < F["toma_vh"] * F["toma_vh"] and \
			absf(roll) < 25 * D2R and absf(pitch) < 25 * D2R and Tt < 1.3 * m * G0:
		av["posado"] = true; av["v"] = [0.0, 0.0, 0.0]; av["w"] = [0.0, 0.0, 0.0]; av["q"] = Cuat.desde_euler(0, 0, Cuat.euler(av["q"])[2]); p[2] = -(suelo + 0.02)
	return vn2

func bateria_pct(av: Dictionary) -> float:
	return Bateria.pct(B, av["bat"])

## Tension por celda (V) con la carga de ahora.
func celda(av: Dictionary) -> float:
	return av["Vbat"] / propulsion["celdas"]
