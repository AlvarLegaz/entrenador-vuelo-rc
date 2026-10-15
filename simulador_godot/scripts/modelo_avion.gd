class_name ModeloAvion
extends RefCounted
## Fisica de 6 grados de libertad de un avion: traduccion LITERAL de ModeloAvion (simulador/js/modelos.js) y de las
## clases ModeloE2 (alerones) y ModeloT1 (elevones) de scripts/clase_e2.js y clase_t1.js. Mismos datos (los .js de
## simulador/aviones), mismas formulas, mismo orden: pruebas/prueba_fisica.gd la compara con trazas de la del
## navegador. Si se cambia algo aqui, hay que cambiarlo igual alli (y al reves).
## Ejes: cuerpo (x adelante, y derecha, z abajo) y mundo NED. El estado del avion (av) es un Dictionary con las
## mismas claves que en JS.

const D2R := PI / 180.0
const R2D := 180.0 / PI
const G0 := 9.81
const GVEC := [0.0, 0.0, G0]          # la gravedad en NED (solo se lee)
const RHO := 1.225

var datos: Dictionary
var tipo := "timon"            # "timon" (E1), "alerones" (E2, E3), "elevones" (T1) o "cuatro" (G1: alerones, profundidad y timon)
var S_m2: float; var b_m: float; var c_m: float; var masa_kg: float; var CD0: float
var inercia: Dictionary; var inercia_diseno: Dictionary; var masa_diseno_kg: float
var cg_mm: Array; var perdida: Dictionary; var propulsion: Dictionary; var mandos: Dictionary; var malla: Dictionary
var compensador_grados := 0.0; var lanzamiento: Dictionary
var TA := []; var TCL := []; var TCDI := []; var TCM := []; var DA := []; var DER := {}
var dcg := 0.0; var rho := RHO; var calib := { "empuje": 1.0, "resistencia": 1.0 }
var Qmax: float; var Ihelice: float; var CD_helice_parada: float; var k_perfil: float
var chorro := {}; var brazoDeriva: float; var brazoPerdida: float
var CD_helice_parada_datos := 0.0
var tren = null                 # aviones de pista: ruedas, muelles, rodadura y frenos (datos.tren)
## DIFICULTAD: con facil = true, paso() es la fisica de antes de las mejoras de realismo (sin par del motor, estela, efecto
## P ni giroscopico, sin perdida por semiala, efecto suelo ni resistencia de perfil, densidad estandar y sin calibracion),
## como ModeloAvion.facil en modelos.js. El Entorno, con su propio facil, quita el viento junto al suelo y la turbulencia
var facil := false

func _init(d: Dictionary) -> void:
	datos = d
	S_m2 = d["S_m2"]; b_m = d["b_m"]; c_m = d["c_m"]; masa_kg = d["masa_kg"]; CD0 = d["CD0"]
	inercia = d["inercia"].duplicate(); inercia_diseno = d["inercia"].duplicate(); masa_diseno_kg = d["masa_kg"]
	cg_mm = d["cg_mm"]; perdida = d["perdida"]; propulsion = d["propulsion"]; mandos = d["mandos"].duplicate(); malla = d.get("malla", {})
	compensador_grados = d.get("compensador_grados", 0.0); lanzamiento = d["lanzamiento"]
	if mandos.has("elevon_max_grados"): tipo = "elevones"
	elif mandos.has("aleron_max_grados") and float(mandos.get("timon_max_grados", 0)) > 0: tipo = "cuatro"
	elif mandos.has("aleron_max_grados"): tipo = "alerones"
	for t in d["tabla_alfa"]:
		TA.append(t["alfa"]); TCL.append(t["CL"]); TCDI.append(t["CDi"]); TCM.append(t["Cm"])
	for dd in d["derivadas"]: DA.append(dd["alfa"])
	for k in d["derivadas"][0].keys():
		var col := []
		for dd in d["derivadas"]: col.append(dd[k])
		DER[k] = col
	var pr := propulsion; var Dm: float = pr["D_m"]
	Qmax = pr["P_max_W"] / (2 * PI * pr["n_max_rps"])
	Ihelice = d["I_helice"] if d.has("I_helice") else 0.012 * pow(Dm / 0.2286, 3) * Dm * Dm / 12
	CD_helice_parada_datos = d.get("CD_helice_parada", 0.0)
	CD_helice_parada = d["CD_helice_parada"] if d.has("CD_helice_parada") else 0.0027 * pow(Dm / 0.2286, 2) / S_m2
	k_perfil = d["k_perfil"] if d.has("k_perfil") else 0.02
	var ch: Dictionary = d.get("chorro", {})
	chorro = { "prof": ch.get("prof", 0.3 if (malla.has("prof")) else 0.0), "timon": ch.get("timon", 0.35), "deriva": ch.get("deriva", 0.1) }
	var xmin := 0.0
	if malla.has("fuselaje"):
		var fv: Array = malla["fuselaje"]["v"]
		for i in range(0, fv.size(), 3): xmin = minf(xmin, fv[i])
	brazoDeriva = maxf(0.1, -xmin - 0.06)
	brazoPerdida = d.get("brazo_perdida", 0.2)
	tren = d.get("tren")

static func interp(xs: Array, ys: Array, x: float) -> float:
	if x <= xs[0]: return ys[0]
	if x >= xs[xs.size() - 1]: return ys[ys.size() - 1]
	var i := 1
	while xs[i] < x: i += 1
	var t: float = (x - xs[i - 1]) / (xs[i] - xs[i - 1])
	return ys[i - 1] + t * (ys[i] - ys[i - 1])

## Masa (kg), X del CG (mm desde la bancada), temperatura (C), empuje estatico medido (gf) y factor de resistencia.
func configurar(op: Dictionary) -> void:
	if op.has("temperatura"): rho = 101325 / (287.05 * (op["temperatura"] + 273.15))
	if op.get("empuje_gf", 0):
		var pr := propulsion
		calib["empuje"] = op["empuje_gf"] / 1000.0 * G0 / (pr["CT0"] * RHO * pow(pr["n_max_rps"], 2) * pow(pr["D_m"], 4))
	if op.get("resistencia", 0): calib["resistencia"] = op["resistencia"]
	if op.get("masa_kg", 0):
		masa_kg = op["masa_kg"]
		var k := masa_kg / masa_diseno_kg
		for n in inercia_diseno.keys(): inercia[n] = inercia_diseno[n] * k
	if op.has("cg_mm"): dcg = (cg_mm[0] - op["cg_mm"]) / 1000.0

func deriv(nombre: String, alfa: float) -> float:
	var col = DER.get(nombre)
	return interp(DA, col, alfa) if col != null else 0.0

## Estado inicial: en la mano del piloto, a 1,6 m del suelo.
func estado_inicial() -> Dictionary:
	var av := { "p": [0.0, 0.0, -1.6], "q": Cuat.desde_euler(0, 2 * D2R, 0), "v": [0.0, 0.0, 0.0], "w": [0.0, 0.0, 0.0],
				"de": 0.0, "dr": 0.0, "da": 0.0, "gases": 0.0, "Wh": 0.0,
				"asim": (-1.0 if randf() < 0.5 else 1.0) * (0.2 + 0.4 * randf()),
				"estado": "en mano", "t": 0.0, "alfa": 0.0, "beta": 0.0, "V": 0.0, "g_carga": 1.0, "perdida": 0.0, "T": 0.0, "Q": 0.0,
				"rpm": 0.0, "motorRoto": false, "elevon_izq": 0.0, "elevon_der": 0.0, "perdidaLados": [0.0, 0.0] }
	if tren != null:
		av["p"] = [0.0, 0.0, -altura_en_tierra()]; av["q"] = Cuat.desde_euler(0, 0, 0); av["freno"] = 1.0; av["enTierra"] = true; av["despegado"] = false; av["trenComp"] = 0.0
	return av

## Altura del CG sobre el suelo con el avion parado sobre sus ruedas (tren: con los amortiguadores con su carga).
func altura_en_tierra() -> float:
	var zmax := -INF
	for r in tren["ruedas"]: zmax = maxf(zmax, float(r["p"][2]))
	return zmax - masa_kg * G0 / (float(tren["k"]) * (tren["ruedas"] as Array).size())

func lanzar(av: Dictionary) -> void:
	if tren != null:                  # de pista: arranca el motor, sin lanzarlo
		av["estado"] = "volando"; av["v"] = [0.0, 0.0, 0.0]; av["w"] = [0.0, 0.0, 0.0]; return
	av["q"] = Cuat.desde_euler(0, lanzamiento["cabeceo_grados"] * D2R, 0)
	av["v"] = [float(lanzamiento["vel_ms"]), 0.0, 0.0]; av["w"] = [0.0, 0.0, 0.0]
	av["estado"] = "volando"

## Palanca (-1..1, con exponencial) -> consignas -> servos con retardo y velocidad maxima. mando: {pitch, yaw, trim}.
func servos(av: Dictionary, mando: Dictionary, dt: float) -> void:
	var m := mandos; var e: float = m["expo"]
	var ex := func(s: float) -> float: return (1 - e) * s + e * s * s * s
	var vmax: float = m["servo_vel_grados_s"] * D2R; var tau: float = m["servo_tau_s"]
	var deObj: float = -ex.call(mando["pitch"]) * m["prof_max_grados"] * D2R + mando["trim"] * D2R
	if tipo == "timon":
		var drObj: float = ex.call(mando["yaw"]) * m["timon_max_grados"] * D2R
		for par in [["de", deObj], ["dr", drObj]]:
			av[par[0]] += clampf((par[1] - av[par[0]]) * dt / tau, -vmax * dt, vmax * dt)
	elif tipo == "cuatro":      # ModeloG1: la palanca izquierda de lado (mando.guinada) mueve el timon
		var daObj: float = ex.call(mando["yaw"]) * m["aleron_max_grados"] * D2R
		var drObj: float = ex.call(mando.get("guinada", 0.0)) * m["timon_max_grados"] * D2R
		for par in [["de", deObj], ["da", daObj], ["dr", drObj]]:
			av[par[0]] += clampf((par[1] - av[par[0]]) * dt / tau, -vmax * dt, vmax * dt)
	elif tipo == "alerones":
		var daObj: float = ex.call(mando["yaw"]) * m["aleron_max_grados"] * D2R
		for par in [["de", deObj], ["da", daObj]]:
			av[par[0]] += clampf((par[1] - av[par[0]]) * dt / tau, -vmax * dt, vmax * dt)
		av["dr"] = 0.0
	else:   # elevones: mezcla de profundidad y alabeo con tope por superficie (como el mezclador de la emisora)
		var daObj: float = ex.call(mando["yaw"]) * m["aleron_max_grados"] * D2R
		var tope: float = m["elevon_max_grados"] * D2R; var suma := absf(deObj) + absf(daObj)
		if suma > tope:
			deObj *= tope / suma; daObj *= tope / suma
		for par in [["elevon_izq", deObj + daObj], ["elevon_der", deObj - daObj]]:
			av[par[0]] += clampf((par[1] - av[par[0]]) * dt / tau, -vmax * dt, vmax * dt)
		av["de"] = 0.5 * (av["elevon_izq"] + av["elevon_der"])
		av["da"] = 0.5 * (av["elevon_izq"] - av["elevon_der"])
		av["dr"] = 0.0

## Aportacion de las superficies de mando a los coeficientes (d: derivada en el alfa actual; kman: eficacia).
func mandos_coef(av: Dictionary, aD: float, kman: float) -> Dictionary:
	var de: float = av["de"] * kman
	if tipo == "timon":
		var dr: float = av["dr"] * kman
		return { "CL": deriv("CLde", aD) * de, "CY": deriv("CYdr", aD) * dr, "Cl": deriv("Cldr", aD) * dr, "Cm": deriv("Cmde", aD) * de, "Cn": deriv("Cndr", aD) * dr }
	var da: float = av["da"] * kman
	if tipo == "cuatro":
		var dr: float = av["dr"] * kman
		return { "CL": deriv("CLde", aD) * de, "CY": deriv("CYda", aD) * da + deriv("CYdr", aD) * dr, "Cl": deriv("Clda", aD) * da + deriv("Cldr", aD) * dr,
				 "Cm": deriv("Cmde", aD) * de, "Cn": deriv("Cnda", aD) * da + deriv("Cndr", aD) * dr }
	return { "CL": deriv("CLde", aD) * de, "CY": deriv("CYda", aD) * da, "Cl": deriv("Clda", aD) * da, "Cm": deriv("Cmde", aD) * de, "Cn": deriv("Cnda", aD) * da }

## Un paso de integracion. viento: velocidad del aire en NED (m/s). Opcionales en av: agl (efecto suelo) y pg
## (alabeo de la turbulencia). Devuelve la velocidad en NED.
func paso(av: Dictionary, viento: Array, dt: float) -> Array:
	var q: Array = av["q"]; var v: Array = av["v"]; var w: Array = av["w"]; var fac := facil; var dens: float = RHO if fac else rho
	var wb := Cuat.rot_inv(q, viento)
	var va := [v[0] - wb[0], v[1] - wb[1], v[2] - wb[2]]
	var V := maxf(0.3, sqrt(va[0] * va[0] + va[1] * va[1] + va[2] * va[2]))
	var alfa := atan2(va[2], va[0]); var beta := asin(clampf(va[1] / V, -1.0, 1.0))
	var ad := alfa * R2D
	var qS := 0.5 * dens * V * V * S_m2; var b := b_m; var c := c_m
	var ph: float = (w[0] - (0.0 if fac else av.get("pg", 0.0))) * b / (2 * V); var qh: float = w[1] * c / (2 * V); var rh: float = w[2] * b / (2 * V)
	# perdida por semiala
	var P := perdida; var an: float = P["anchura_grados"] / 2
	var aPerd: float = P["alfa_perdida_grados"]; var aNeg: float = P["alfa_perdida_neg_grados"]
	var fPerd := func(a: float) -> float: return maxf(1 / (1 + exp(-(a - aPerd) / an)), 1 / (1 + exp((a - aNeg) / an)))
	var yc := brazoPerdida * b; var dAp: float = 0.0 if fac else w[0] * yc / V * R2D; var asim: float = 0.0 if fac else av.get("asim", 0.0)
	var fR: float = fPerd.call(ad + dAp + asim / 2); var fL: float = fPerd.call(ad - dAp - asim / 2); var f := 0.5 * (fR + fL)
	var CLlin := interp(TA, TCL, ad); var Cmlin := interp(TA, TCM, ad)
	var CDi := interp(TA, TCDI, ad)
	var CLplaca: float = P["CL_placa_factor"] * 2 * sin(alfa) * cos(alfa)
	# efecto suelo
	var fiS := 1.0
	if not fac and av.has("agl") and av["agl"] != null:
		var x16 := pow(16 * maxf(0.05, av["agl"]) / b, 2)
		fiS = x16 / (1 + x16)
	CDi *= fiS
	var CL0 := ((1 - f) * CLlin + f * CLplaca) * (1 + 0.06 * (1 - fiS))
	var pr := propulsion; var g: float = 0.0 if av["motorRoto"] else av["gases"]
	var CDhel := (CD_helice_parada_datos if fac else CD_helice_parada) if g < 0.05 else 0.0
	var s2a := pow(sin(alfa), 2)                     # sin(alfa) al cuadrado, una vez (se usaba tres veces)
	var CD: float = CD0 + CDhel + (1 - f) * CDi + f * 2 * s2a if fac else CD0 * calib["resistencia"] + k_perfil * pow(CL0 - 0.3, 2) + (1 - f) * CDi + f * 2 * s2a + CDhel
	var aP: float = aPerd if ad > 0 else aNeg
	var Cm0 := (1 - f) * Cmlin + f * (interp(TA, TCM, aP) - 0.5 * (alfa - aP * D2R))
	var kman: float = 1 - f * (1 - P["mando_post_perdida"])
	var aD := clampf(ad, DA[0], DA[DA.size() - 1])
	var M := mandos_coef(av, aD, kman)
	# motor y helice
	if av["motorRoto"]: av["gases"] = 0.0
	var bat := maxf(0, 1 - av["Wh"] / pr["masa_bateria_Wh"]); var n: float = pr["n_max_rps"] * g * (1.0 if (fac or pr.get("combustible", false)) else 1 - 0.10 * (1 - bat))
	var T := 0.0; var Q := 0.0; var J := 0.0
	if g > 0.02:
		J = V / (n * pr["D_m"])
		T = pr["CT0"] * (1.0 if fac else calib["empuje"]) * maxf(0, 1 - J / pr["J0"]) * dens * n * n * pow(pr["D_m"], 4)
		Q = 0.0 if fac else Qmax * pow(n / pr["n_max_rps"], 2) * (0.6 + 0.4 * maxf(0, 1 - J / pr["J0"]))
		av["Wh"] += pr["P_max_W"] * g * g * g * dt / 3600
	av["T"] = T; av["Q"] = Q; av["rpm"] = n * 60 if g > 0.02 else 0.0
	# chorro de la helice sobre la cola
	var Adisco: float = PI * pr["D_m"] * pr["D_m"] / 4; var rq := 1.0 if fac else minf(6, 1 + 0.8 * 2 * T / (dens * Adisco) / (V * V))
	var kProf: float = 1 + chorro["prof"] * (rq - 1); var kTimon: float = 1 + chorro["timon"] * (rq - 1)
	M["CL"] *= kProf; M["Cm"] *= kProf
	if mandos["timon_max_grados"] > 0:
		M["CY"] *= kTimon; M["Cl"] *= kTimon; M["Cn"] *= kTimon
	var ClpEf: float = deriv("Clp", aD) if fac else deriv("Clp", aD) * (1 - 0.6 * f)
	var CL: float = CL0 + deriv("CLq", aD) * qh + M["CL"]
	var CY: float = deriv("CYb", aD) * beta + deriv("CYp", aD) * ph + deriv("CYr", aD) * rh + M["CY"]
	var dCLside := maxf(0, minf(CLlin, interp(TA, TCL, aPerd)) - CLplaca); var yP := brazoPerdida * b
	var Cl: float = deriv("Clb", aD) * beta + ClpEf * ph + deriv("Clr", aD) * rh + M["Cl"] + (fR - fL) * dCLside * yP / (2 * b)
	var Cm: float = Cm0 + deriv("Cmq", aD) * qh + M["Cm"]
	var Cn: float = deriv("Cnb", aD) * beta + deriv("Cnp", aD) * ph + deriv("Cnr", aD) * rh + M["Cn"] + (fR - fL) * maxf(0, 2 * s2a - CDi) * yP / (2 * b)
	var ca := cos(alfa); var sa := sin(alfa)
	var Fa := [qS * (-CD * ca + CL * sa), qS * CY, qS * (-CD * sa - CL * ca)]
	var Ma := [qS * b * Cl, qS * c * Cm, qS * b * Cn]
	var dx := dcg
	Ma[1] += dx * Fa[2]; Ma[2] -= dx * Fa[1]
	var dth: float = pr.get("downthrust_grados", 0.0) * D2R
	var hp: Array = malla["helice"] if malla.has("helice") else [0.0, 0.0, 0.0]
	var Tx := T * cos(dth); var Tz := T * sin(dth)
	Ma[1] += hp[2] * Tx - (hp[0] - dx) * Tz
	# efectos de la helice (sentido horario visto desde atras: s = +1)
	var s: float = pr.get("sentido", 1); var sw: float = chorro["deriva"]; var hFin := 0.05
	Ma[0] += -s * Q + s * sw * Q
	var Fsw := s * sw * Q / hFin
	Fa[1] += Fsw; Ma[2] += -brazoDeriva * Fsw
	if T > 0 and not fac:
		var e: float = 0.5 * (pr["D_m"] / 2) * V * sin(alfa) / (2 * PI * n * 0.75 * pr["D_m"] / 2 + 1e-3)
		Ma[2] += -s * T * e
	var Hx: float = 0.0 if fac else s * Ihelice * 2 * PI * n
	Ma[1] += -w[2] * Hx; Ma[2] += w[1] * Hx
	var gb := Cuat.rot_inv(q, GVEC); var m := masa_kg
	var F := [Fa[0] + Tx + m * gb[0], Fa[1] + m * gb[1], Fa[2] + Tz + m * gb[2]]
	if tren != null: fuerzas_tren(av, F, Ma)
	var dv := [F[0] / m - (w[1] * v[2] - w[2] * v[1]), F[1] / m - (w[2] * v[0] - w[0] * v[2]), F[2] / m - (w[0] * v[1] - w[1] * v[0])]
	var I := inercia; var Ixx: float = I["Ixx"]; var Iyy: float = I["Iyy"]; var Izz: float = I["Izz"]; var Ixz: float = I["Ixz"]
	var Iw := [Ixx * w[0] - Ixz * w[2], Iyy * w[1], Izz * w[2] - Ixz * w[0]]
	var wxIw := [w[1] * Iw[2] - w[2] * Iw[1], w[2] * Iw[0] - w[0] * Iw[2], w[0] * Iw[1] - w[1] * Iw[0]]
	var Mx: float = Ma[0] - wxIw[0]; var My: float = Ma[1] - wxIw[1]; var Mz: float = Ma[2] - wxIw[2]; var det := Ixx * Izz - Ixz * Ixz
	var dw := [(Mx * Izz + Mz * Ixz) / det, My / Iyy, (Mz * Ixx + Mx * Ixz) / det]
	for i in 3:
		v[i] += dv[i] * dt; w[i] += dw[i] * dt
	var dq := Cuat.mul(q, [0.0, w[0], w[1], w[2]])
	av["q"] = Cuat.norm([q[0] + 0.5 * dq[0] * dt, q[1] + 0.5 * dq[1] * dt, q[2] + 0.5 * dq[2] * dt, q[3] + 0.5 * dq[3] * dt])
	var vn := Cuat.rot(av["q"], v)
	var p: Array = av["p"]
	for i in 3: p[i] += vn[i] * dt
	av["t"] += dt; av["alfa"] = ad; av["beta"] = beta * R2D; av["V"] = V; av["perdida"] = f; av["perdidaLados"] = [fL, fR]
	av["g_carga"] = -Fa[2] / (m * G0)
	return vn

func bateria_pct(av: Dictionary) -> float:
	return maxf(0, 100 * (1 - av["Wh"] / propulsion["masa_bateria_Wh"]))

static func _sg(x: float, e: float) -> float: return x / sqrt(x * x + e * e)      # signo suave: sin saltos al pararse

## Tren de aterrizaje (fuerzasTren de modelos.js): cada rueda es un muelle con amortiguador vertical, con rodadura (y
## freno en las principales) y agarre lateral; la de morro gira con los timones. Suma fuerzas y momentos a F y Ma.
func fuerzas_tren(av: Dictionary, F: Array, Ma: Array) -> void:
	var q: Array = av["q"]; var v: Array = av["v"]; var w: Array = av["w"]; var agl: float = av.get("agl", 1e9)
	var vn := Cuat.rot(q, v); var fx := Cuat.rot(q, [1.0, 0.0, 0.0]); var hx := Vector2(fx[0], fx[1]).length(); var qi := Cuat.inv(q)
	if hx == 0: hx = 1.0
	var n := 0; var comp := 0.0; var ds = av.get("dSuelo")     # cuanto mas alto esta el suelo bajo cada rueda que bajo el CG
	for k in (tren["ruedas"] as Array).size():
		var r: Dictionary = tren["ruedas"][k]; var rp: Array = r["p"]; var rw := Cuat.rot(q, rp); var pen: float = rw[2] - agl + (float(ds[k]) if ds != null else 0.0)
		if pen <= 0: continue
		n += 1; comp = maxf(comp, pen)
		var wn := Cuat.rot(q, [w[1] * rp[2] - w[2] * rp[1], w[2] * rp[0] - w[0] * rp[2], w[0] * rp[1] - w[1] * rp[0]])
		var vp := [vn[0] + wn[0], vn[1] + wn[1], vn[2] + wn[2]]
		var N := maxf(0, float(tren["k"]) * pen + float(tren["c"]) * vp[2])
		var ux: float = fx[0] / hx; var uy: float = fx[1] / hx
		if r.get("morro", false):         # rueda de morro: gira con los timones, menos cuanto mas deprisa
			var vh := Vector2(vn[0], vn[1]).length(); var g: float = av.get("dr", 0.0) / (float(mandos["timon_max_grados"]) * D2R) * float(tren["giro_morro_grados"]) * D2R / (1 + (vh / 8) * (vh / 8))
			var c := cos(g); var s := sin(g)
			var x := ux * c - uy * s; uy = ux * s + uy * c; ux = x
		var vl: float = vp[0] * ux + vp[1] * uy; var vt: float = -vp[0] * uy + vp[1] * ux
		var mu: float = float(tren["mu_rodadura"]) + (0.0 if r.get("morro", false) else float(av.get("freno", 0.0)) * float(tren["mu_freno"]))
		var Fl := -mu * N * _sg(vl, 0.2); var Ft := -float(tren["mu_lateral"]) * N * _sg(vt, 0.3)
		var Fb := Cuat.rot(qi, [Fl * ux - Ft * uy, Fl * uy + Ft * ux, -N])
		for i in 3: F[i] += Fb[i]
		Ma[0] += rp[1] * Fb[2] - rp[2] * Fb[1]; Ma[1] += rp[2] * Fb[0] - rp[0] * Fb[2]; Ma[2] += rp[0] * Fb[1] - rp[1] * Fb[0]
	if n > 0 and not av.get("enTierra", false): av["vzToma"] = vn[2]
	av["enTierra"] = n > 0; av["trenComp"] = comp

## Con tren, despues de cada paso (finTren de modelos.js): "" si no pasa nada, "roto (...)" si se rompe en tierra y
## "aterrizado" cuando, despues de haber volado, se para sobre sus ruedas.
func fin_tren(av: Dictionary) -> String:
	if not av.get("enTierra", false):
		if av.get("agl", 0.0) > 3: av["despegado"] = true
		return ""
	var e := Cuat.euler(av["q"]); var ds = av.get("dSuelo")
	if ds != null:                # alabeo y cabeceo respecto al suelo bajo las ruedas (el terreno puede estar inclinado)
		var R: Array = tren["ruedas"]; var iz := -1; var de := -1; var mo := -1
		for k in R.size():
			if R[k].get("morro", false): mo = k if mo < 0 else mo
			elif float(R[k]["p"][1]) < 0: iz = k if iz < 0 else iz
			else: de = k if de < 0 else de
		e[0] -= atan2(float(ds[iz]) - float(ds[de]), float(R[de]["p"][1]) - float(R[iz]["p"][1]))
		e[1] -= atan2(float(ds[mo]) - 0.5 * (float(ds[iz]) + float(ds[de])), float(R[mo]["p"][0]) - float(R[iz]["p"][0]))
	if av.has("vzToma"):
		var vz: float = av["vzToma"]; av.erase("vzToma")
		if vz > float(tren["v_toma_max_ms"]): return "roto (toma demasiado dura)"
	if av["trenComp"] > 0.25: return "roto (tren roto)"
	if absf(e[0]) > 20 * D2R: return "roto (punta del ala en el suelo)"
	if e[1] > 16 * D2R: return "roto (cola en el suelo)"
	if e[1] < -8 * D2R: return "roto (morro en el suelo)"
	if av.get("despegado", false) and Vector2(av["v"][0], av["v"][1]).length() < 0.5: return "aterrizado"
	return ""
