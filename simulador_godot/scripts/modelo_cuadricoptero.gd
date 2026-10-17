class_name ModeloCuadricoptero
extends RefCounted
## Mini Dron HQ (cuadricoptero de 249 g) con su controlador de vuelo: traduccion LITERAL de la clase ModeloCuadricoptero de
## datos/vehiculos/DJI_MINI.js (mismos datos, mismas formulas, mismo orden). simulador_godot/Tests/prueba_cuadricoptero.gd la compara
## con trazas de la del navegador. Si se cambia algo aqui, hay que cambiarlo igual alli (y al reves).
## El controlador es como el del dron comercial (modo estabilizado con retencion de posicion y altura, como con GPS): la palanca
## derecha pide velocidad horizontal (pitch: + = palanca hacia ti = atras; yaw: + = derecha), la izquierda velocidad
## vertical (vz) y giro sobre si mismo (guinada). Consigna de velocidad -> inclinacion -> velocidad angular -> par, con
## los limites de los motores, y dinamica de 6 grados de libertad con resistencia y viento. Modos C / N / S (modo),
## gimbal (av.gimbal, grados: 0 horizontal, -90 vertical), despegue automatico (despegar), volver a casa (volver_a_casa)
## y aterrizaje con la palanca abajo. Mismos ejes y mismo estado (av, Dictionary con las claves de JS) que ModeloAvion,
## y la misma interfaz, para que el simulador lo use igual. No tiene perdida (av.perdida = 0) ni angulo de ataque.

const D2R := PI / 180.0
const G0 := 9.81
const RHO := 1.225

var datos: Dictionary
var es_cuadricoptero := true
var modo := "N"                 # modo de vuelo: "C" (Cine), "N" (Normal) o "S" (Sport)
var casa = null                 # punto de despegue [N, E] (para el RTH), o null
var S_m2: float; var b_m: float; var c_m: float; var masa_kg: float
var inercia: Dictionary; var inercia_diseno: Dictionary; var masa_diseno_kg: float
var cg_mm: Array; var propulsion: Dictionary; var mandos: Dictionary; var malla: Dictionary; var fc: Dictionary
var compensador_grados := 0.0; var lanzamiento: Dictionary
var dcg := 0.0; var rho := RHO; var calib := { "empuje": 1.0, "resistencia": 1.0 }
var temp_c := 15.0; var B: Dictionary            # bateria Li-ion inteligente (bateria.gd)
var k_emp := 1.0; var k_pot := 1.0; var sens = null   # averias (desgaste.gd): empuje, consumo y sensores
var averias := []; var efe := {}; var _est = null; var _Bbase = null; var kT = null; var kP = null
## dificultad facil: la mitad del viento sobre la resistencia y sin la turbulencia que alabea (como en JS)
var facil := false

func _init(d: Dictionary) -> void:
	datos = d
	S_m2 = d["S_m2"]; b_m = d["b_m"]; c_m = d["c_m"]; masa_kg = d["masa_kg"]
	inercia = d["inercia"].duplicate(); inercia_diseno = d["inercia"].duplicate(); masa_diseno_kg = d["masa_kg"]
	cg_mm = d["cg_mm"]; propulsion = d["propulsion"]; fc = d["fc"]; mandos = d["mandos"].duplicate(); malla = d.get("malla", {})
	compensador_grados = d.get("compensador_grados", 0.0); lanzamiento = d["lanzamiento"]
	B = Bateria.datos(propulsion)

## Masa, temperatura (densidad), empuje medido (gf, el maximo de los 4 motores) y factor de resistencia. (cg_mm no se usa.)
func configurar(op: Dictionary) -> void:
	if op.has("temperatura"): rho = 101325 / (287.05 * (op["temperatura"] + 273.15)); temp_c = op["temperatura"]
	if op.get("empuje_gf", 0): calib["empuje"] = op["empuje_gf"] / 1000.0 * G0 / propulsion["empuje_max_N"]
	if op.get("resistencia", 0): calib["resistencia"] = op["resistencia"]
	if op.get("masa_kg", 0):
		masa_kg = op["masa_kg"]
		var k := masa_kg / masa_diseno_kg
		for n in inercia_diseno.keys(): inercia[n] = inercia_diseno[n] * k

## En el suelo, motores parados ("en mano" para el simulador: lanzar() los arma).
func estado_inicial() -> Dictionary:
	return { "p": [0.0, 0.0, -0.02], "q": Cuat.desde_euler(0, 0, 0), "v": [0.0, 0.0, 0.0], "w": [0.0, 0.0, 0.0], "de": 0.0, "dr": 0.0, "da": 0.0,
			 "gases": 0.0, "Wh": 0.0, "asim": 0.0, "estado": "en mano", "t": 0.0, "alfa": 0.0, "beta": 0.0, "V": 0.0, "g_carga": 1.0, "perdida": 0.0,
			 "T": 0.0, "rpm": 0.0, "motorRoto": false, "posado": true, "despegado": false, "tParar": 0.0,
			 "cmd": { "adelante": 0.0, "derecha": 0.0, "guinada": 0.0, "vz": 0.0 }, "gimbal": -10.0, "rth": null, "despegueAuto": false, "hold": null,
			 "bat": Bateria.nueva(B, temp_c), "sinBateria": false, "avisoBat": "", "batRth": false, "batForzado": false }

## Armar: motores al ralenti en el suelo; despega al pedir velocidad vertical.
func lanzar(av: Dictionary) -> void:
	av["v"] = [0.0, 0.0, 0.0]; av["w"] = [0.0, 0.0, 0.0]; av["estado"] = "volando"; av["posado"] = true; av["despegado"] = false; av["tParar"] = 0.0
	av["q"] = Cuat.desde_euler(0, 0, Cuat.euler(av["q"])[2])
	av["rth"] = null; av["despegueAuto"] = false; av["hold"] = null; casa = [av["p"][0], av["p"][1]]     # punto de casa: donde arranca

## av.agl como en JS: si no esta (undefined), las comparaciones dan falso (NAN).
static func _agl(av: Dictionary) -> float:
	return av["agl"] if av.get("agl") != null else NAN

static func _cl(x) -> float:
	var f: float = 0.0 if x == null else float(x)
	if is_nan(f): f = 0.0
	return maxf(-1, minf(1, f))

## Palancas -> consignas (con la exponencial del simulador; con mando la pone el mando y expo vale 0), suavizadas
## como la respuesta de la emisora. mando: pitch (+ = palanca hacia ti = atras), yaw (+ = derecha), guinada, vz, gimbal.
func servos(av: Dictionary, mando: Dictionary, dt: float) -> void:
	var e: float = mandos.get("expo", 0.0)
	var ex := func(s: float) -> float: return (1 - e) * s + e * s * s * s
	var obj := { "adelante": ex.call(_cl(-float(mando.get("pitch", 0.0)))), "derecha": ex.call(_cl(mando.get("yaw"))),
				 "guinada": ex.call(_cl(mando.get("guinada"))), "vz": _cl(mando.get("vz")) }
	_bateria_baja(av)
	# cualquier palanca cancela el RTH y el despegue automatico (como en el dron comercial); el aterrizaje forzoso por
	# bateria critica no: se puede mover en horizontal para buscar sitio, pero sigue bajando
	var mx := 0.0
	for k in obj: mx = maxf(mx, absf(obj[k]))
	if av.get("batForzado", false):
		av["rth"] = null; av["despegueAuto"] = false; obj["vz"] = minf(obj["vz"], -0.6)
	elif mx > 0.3:
		av["rth"] = null; av["despegueAuto"] = false
	if av["rth"]: _rth(av, obj)
	elif av["despegueAuto"]:
		obj["adelante"] = 0.0; obj["derecha"] = 0.0; obj["guinada"] = 0.0; obj["vz"] = 0.5 if _agl(av) < 1.2 else 0.0
		if _agl(av) >= 1.2: av["despegueAuto"] = false
	var cmd: Dictionary = av["cmd"]
	for k in obj: cmd[k] += maxf(-10 * dt, minf(10 * dt, obj[k] - cmd[k]))
	av["gimbal"] = maxf(-89, minf(10, av["gimbal"] + 45 * _cl(mando.get("gimbal")) * dt))      # rueda del gimbal: 45 grados/s, hasta -89 (como en la web)

## Volver a casa: sube a la altura de RTH, va al punto de despegue a 8 m/s mirando hacia el, y aterriza. Escribe las consignas en obj.
func _rth(av: Dictionary, obj: Dictionary) -> void:
	var R: Dictionary = av["rth"]; var ca: Array = casa if casa != null else [0.0, 0.0]
	var dN: float = ca[0] - av["p"][0]; var dE: float = ca[1] - av["p"][1]; var d := sqrt(dN * dN + dE * dE)
	var vn := Cuat.rot(av["q"], av["v"]); var yaw: float = Cuat.euler(av["q"])[2]
	var M: Dictionary = fc["modos"][modo] if fc["modos"].has(modo) else fc["modos"]["N"]
	var agl := _agl(av); var alt_rth: float = fc["rth_altura_m"]
	obj["adelante"] = 0.0; obj["derecha"] = 0.0; obj["guinada"] = 0.0; obj["vz"] = 0.0
	if R["fase"] == "subir":
		obj["vz"] = 1.0 if agl < alt_rth - 0.5 else 0.0
		if agl >= alt_rth - 0.5 or d < 5: R["fase"] = "volver"
	if R["fase"] == "volver":
		var vObj := minf(8, d * 0.6); var vN := dN / maxf(d, 1e-3) * vObj; var vE := dE / maxf(d, 1e-3) * vObj
		var cy := cos(yaw); var sy := sin(yaw)     # velocidad objetivo en ejes de rumbo, como si fuera la palanca
		obj["adelante"] = _cl((vN * cy + vE * sy) / M["vmax_ms"]); obj["derecha"] = _cl((-vN * sy + vE * cy) / M["vmax_ms"])
		var rumbo := atan2(dE, dN); var err := atan2(sin(rumbo - yaw), cos(rumbo - yaw))
		obj["guinada"] = _cl(err * 2) if d > 3 else 0.0
		if d < 1.5 and sqrt(vn[0] * vn[0] + vn[1] * vn[1]) < 0.8: R["fase"] = "bajar"
	if R["fase"] == "bajar":
		obj["vz"] = -1.0; av["hold"] = [ca[0], ca[1]]      # baja sujetando la posicion sobre casa

## Bateria baja como en el dron comercial (av.avisoBat lo cuenta al simulador): al 30 % avisa; cuando la carga justo
## alcanza para volver (la vuelta a 8 m/s con la subida y la bajada, un 30 % mas de lo que gasta ahora y un 15 % de reserva) vuelve
## a casa solo (una vez; con las palancas se cancela); al 10 % aterrizaje forzoso donde este. Como _bateriaBaja en JS.
func _bateria_baja(av: Dictionary) -> void:
	if av["estado"] != "volando" or av["posado"] or av.get("bat") == null: return
	var pc := bateria_pct(av)
	if pc <= 10 and not av["batForzado"]:
		av["batForzado"] = true; av["avisoBat"] = "critica"; return
	# una celda que se hunde (celda debil: desgaste.gd) tambien obliga a aterrizar, aunque la carga diga otra cosa
	if not av["batForzado"] and Bateria.celda_min(B, av["bat"]) < 2.85:
		av["batForzado"] = true; av["avisoBat"] = "celda"; return
	if av["batForzado"]: return
	var ca: Array = casa if casa != null else [0.0, 0.0]
	var d := Vector2(ca[0] - av["p"][0], ca[1] - av["p"][1]).length(); var agl: float = av["agl"] if av.get("agl") != null else 0.0; var hR: float = fc["rth_altura_m"]
	if not av["batRth"] and d > 15:
		var t := d / 8 + maxf(0.0, hR - agl) / 3 + maxf(agl, hR) / 1.5 + 10; var Pw: float = av["bat"]["P"] if av["bat"]["P"] > 1 else 40.0
		var pct_vuelta := 100 * 1.3 * Pw * t / 3600 / (Bateria.capacidad(B, av["bat"]) / 1000 * int(B["celdas"]) * 3.7) + 15   # volando gasta mas; llegar sobre el 10 % del forzoso
		if pc <= pct_vuelta:
			av["batRth"] = true; av["avisoBat"] = "rth"
			if not av["rth"]: volver_a_casa(av)
			return
	if pc <= 30 and av["avisoBat"] == "": av["avisoBat"] = "baja"

## Volver a casa (boton RTH de la app o tecla H).
func volver_a_casa(av: Dictionary) -> void:
	if av["estado"] != "volando" or av["posado"]: return
	av["despegueAuto"] = false; av["rth"] = { "fase": "subir" if _agl(av) < fc["rth_altura_m"] - 0.5 else "volver" }

## Despegue automatico (boton de la app): arma los motores y sube a 1,2 m.
func despegar(av: Dictionary) -> void:
	if av["estado"] != "volando": lanzar(av)
	if av["posado"]: av["despegueAuto"] = true

## Sin superficies de mando (misma firma que ModeloAvion.mandos_coef; en JS mandosCoef() no lleva argumentos).
func mandos_coef(_av = null, _d = null, _kman = 1.0) -> Dictionary:
	return { "CL": 0.0, "CY": 0.0, "Cl": 0.0, "Cm": 0.0, "Cn": 0.0 }

## Un paso: controlador de vuelo -> empuje y pares -> dinamica de 6 grados de libertad. viento: NED (m/s). Opcionales
## en av: agl (altura sobre el suelo) y pg (alabeo de la turbulencia). Devuelve la velocidad NED.
func paso(av: Dictionary, viento: Array, dt: float) -> Array:
	var m := masa_kg; var I := inercia; var F := fc; var pr := propulsion; var q: Array = av["q"]; var v: Array = av["v"]; var w: Array = av["w"]
	# bateria: el empuje maximo baja cuando la tension cae por debajo de la nominal (3,7 V por celda); agotada (una celda
	# por debajo de 2,9 V con carga), los motores se paran
	var eb: Dictionary = av["bat"]; var Vb := Bateria.tension(B, eb); var kV := minf(1.0, Vb / (int(B["celdas"]) * 3.7))
	if not av["sinBateria"] and av["estado"] == "volando" and Bateria.pct(B, eb) <= 0 and Bateria.celda_min(B, eb) < 2.9: av["sinBateria"] = true
	var parado: bool = av["motorRoto"] or av["sinBateria"]
	var Tmax: float = pr["empuje_max_N"] * calib["empuje"] * kV * kV * k_emp
	var tiene_agl: bool = av.get("agl") != null
	var suelo: float = 0.0 if not tiene_agl else -av["p"][2] - av["agl"]
	var M: Dictionary = F["modos"][modo] if F["modos"].has(modo) else F["modos"]["N"]
	var tilt: float = M["inclinacion_grados"] * D2R; var c: Dictionary = av["cmd"]
	if parado: c["vz"] = -1.0
	# --- estado: velocidad respecto al suelo en NED y en ejes de rumbo (adelante, derecha), angulos ---
	# con un sensor averiado (sens, desgaste.gd) el controlador cree otra cosa: brujula (rumbo), IMU (actitud), barometro
	# (velocidad vertical) y GPS (el punto que sujeta se le va moviendo)
	var S = sens
	var vn := Cuat.rot(q, v); var eu := Cuat.euler(q); var roll: float = eu[0]; var pitch: float = eu[1]; var yaw: float = eu[2]
	var yawE: float = yaw + S["rumbo"] if S != null else yaw; var rollE: float = roll + S["alabeo"] if S != null else roll
	var pitchE: float = pitch + S["cabeceo"] if S != null else pitch
	var cy := cos(yawE); var sy := sin(yawE)
	var vf: float = vn[0] * cy + vn[1] * sy; var vr: float = -vn[0] * sy + vn[1] * cy; var vzUp: float = -vn[2] - S["vz"] if S != null else -vn[2]
	# --- controlador de vuelo ---
	# velocidad horizontal objetivo (palanca derecha) -> aceleracion -> inclinacion objetivo (tope: inclinacion maxima)
	var amax := G0 * tan(tilt)
	# retencion de posicion (GPS): con la palanca derecha en el centro y ya frenado, se sujeta el punto donde se paro
	var quieto: bool = absf(c["adelante"]) < 0.02 and absf(c["derecha"]) < 0.02
	if quieto and not av["posado"]:
		if av["hold"] == null and sqrt(vf * vf + vr * vr) < 0.5: av["hold"] = [av["p"][0], av["p"][1]]
	else: av["hold"] = null
	var vfObj: float = c["adelante"] * M["vmax_ms"]; var vrObj: float = c["derecha"] * M["vmax_ms"]
	if av["hold"] != null:
		var gN: float = S["gps"] * cos(2 * PI * av["t"] / 25) if S != null and S["gps"] else 0.0
		var gE: float = S["gps"] * sin(2 * PI * av["t"] / 31) if S != null and S["gps"] else 0.0
		var vN := clampf(0.7 * (av["hold"][0] + gN - av["p"][0]), -2, 2); var vE := clampf(0.7 * (av["hold"][1] + gE - av["p"][1]), -2, 2)
		vfObj += vN * cy + vE * sy; vrObj += -vN * sy + vE * cy
	var af: float = M["kv"] * (vfObj - vf); var ar: float = M["kv"] * (vrObj - vr)
	var an := sqrt(af * af + ar * ar)
	if an > amax:
		af *= amax / an; ar *= amax / an
	var pitchObj := -atan(af / G0); var rollObj := atan(ar / G0)
	# velocidad vertical objetivo (palanca izquierda): sube a vzmax_sube, baja a vzmax_baja; al centro mantiene la altura
	# proteccion de aterrizaje como la del dron comercial: cerca del suelo la bajada se limita (0,6 m/s por debajo de 3 m, 1,5 por debajo de 8)
	var agl: float = 100.0 if not tiene_agl else av["agl"]
	var bajaMax: float = minf(M["vzmax_baja"], 0.6 if agl < 3 else (1.5 if agl < 8 else M["vzmax_baja"]))
	var vzObj: float = c["vz"] * M["vzmax_sube"] if c["vz"] > 0 else c["vz"] * bajaMax
	var T: float = 0.0 if parado else m * (G0 + F["kz"] * (vzObj - vzUp)) / maxf(0.5, cos(rollE) * cos(pitchE))
	T = maxf(0, minf(Tmax, T))
	# en el suelo: los motores al ralenti hasta que se pide subir; con la palanca abajo un rato, se paran (aterrizado)
	if av["posado"]:
		if c["vz"] <= 0.05 or parado: T = 0.0
		if T <= m * G0 * 1.02:
			av["v"] = [0.0, 0.0, 0.0]; av["w"] = [0.0, 0.0, 0.0]; av["q"] = Cuat.desde_euler(0, 0, yaw); av["p"][2] = -(suelo + 0.02)
			av["T"] = T; av["gases"] = 0.0 if parado else 0.08; av["rpm"] = 0.0 if parado else 0.25 * pr["rpm_max"]
			av["V"] = 0.0; av["g_carga"] = 1.0; av["alfa"] = 0.0; av["beta"] = 0.0; av["t"] += dt
			Bateria.gastar(B, eb, 0.0 if parado else 6.0, dt); av["Wh"] = eb["Wh"]
			av["tParar"] = av["tParar"] + dt if (c["vz"] < -0.3 or av["rth"]) and av["despegado"] else 0.0   # RTH: al posarse para los motores
			if av["tParar"] > 0.8 or (parado and av["despegado"]): av["p"][2] = -(suelo - 0.05)    # posado y motores parados: el simulador lo da por aterrizado
			return [0.0, 0.0, 0.0]
		av["posado"] = false    # despega
	# --- pares: angulos objetivo -> velocidades angulares objetivo -> par, con los topes de los motores ---
	var pObj: float = F["ka"] * (rollObj - rollE); var qObj: float = F["ka"] * (pitchObj - pitchE); var rObj: float = c["guinada"] * M["rmax_grados_s"] * D2R
	var Mx: float = clampf(I["Ixx"] * F["kr"] * (pObj - w[0]), -F["tau_max"], F["tau_max"])
	var My: float = clampf(I["Iyy"] * F["kr"] * (qObj - w[1]), -F["tau_max"], F["tau_max"])
	var Mz: float = clampf(I["Izz"] * F["kr"] * (rObj - w[2]), -F["tau_guinada"], F["tau_guinada"])
	if parado:
		Mx = 0.0; My = 0.0; Mz = 0.0
	# turbulencia que alabea (Entorno.rafaga_alabeo): el dron la nota y el controlador la corrige
	var pg: float = float(av.get("pg", 0.0)) if av.get("pg") != null else 0.0
	if pg and not facil: Mx += I["Ixx"] * pg * 4
	# --- fuerzas en ejes cuerpo: empuje hacia arriba, peso, resistencia con el viento (la mitad en fisica facil) ---
	var wb := Cuat.rot_inv(q, [0.5 * viento[0], 0.5 * viento[1], 0.5 * viento[2]] if facil else viento)
	var va := [v[0] - wb[0], v[1] - wb[1], v[2] - wb[2]]; var Va := sqrt(va[0] * va[0] + va[1] * va[1] + va[2] * va[2])
	var kd: float = 0.5 * rho * Va * calib["resistencia"]
	var Fd := [-kd * F["cda_h"] * va[0], -kd * F["cda_h"] * va[1], -kd * F["cda_v"] * va[2]]
	var gb := Cuat.rot_inv(q, [0.0, 0.0, G0])
	var Fx: float = Fd[0] + m * gb[0]; var Fy: float = Fd[1] + m * gb[1]; var Fz: float = Fd[2] + m * gb[2] - T
	# --- ecuaciones de Euler (sin producto de inercia) e integracion ---
	var dv := [Fx / m - (w[1] * v[2] - w[2] * v[1]), Fy / m - (w[2] * v[0] - w[0] * v[2]), Fz / m - (w[0] * v[1] - w[1] * v[0])]
	var Iw := [I["Ixx"] * w[0], I["Iyy"] * w[1], I["Izz"] * w[2]]
	var dw := [(Mx - (w[1] * Iw[2] - w[2] * Iw[1])) / I["Ixx"], (My - (w[2] * Iw[0] - w[0] * Iw[2])) / I["Iyy"], (Mz - (w[0] * Iw[1] - w[1] * Iw[0])) / I["Izz"]]
	for i in 3:
		v[i] += dv[i] * dt; w[i] += dw[i] * dt
	var dq := Cuat.mul(q, [0.0, w[0], w[1], w[2]])
	av["q"] = Cuat.norm([q[0] + 0.5 * dq[0] * dt, q[1] + 0.5 * dq[1] * dt, q[2] + 0.5 * dq[2] * dt, q[3] + 0.5 * dq[3] * dt])
	var vn2 := Cuat.rot(av["q"], v)
	var p: Array = av["p"]
	for i in 3: p[i] += vn2[i] * dt
	# --- suelo: toma suave (poco descenso, casi nivelado) -> posado; dura o inclinada -> la decide el simulador ---
	var agl2: float = -p[2] - suelo
	if agl2 > 0.3: av["despegado"] = true
	if agl2 <= 0.02 and vn2[2] >= 0 and vn2[2] < 2.0 and absf(roll) < 20 * D2R and absf(pitch) < 20 * D2R and c["vz"] <= 0.05:
		av["posado"] = true; av["v"] = [0.0, 0.0, 0.0]; av["w"] = [0.0, 0.0, 0.0]; av["q"] = Cuat.desde_euler(0, 0, Cuat.euler(av["q"])[2]); p[2] = -(suelo + 0.02)
	# --- bateria (potencia inducida de los 4 rotores + electronica), revoluciones y lecturas ---
	var A4: float = 4 * PI * pow(pr["D_m"] / 2, 2); var P: float = (pow(T, 1.5) / sqrt(2 * rho * A4) / 0.55 + 4) * k_pot
	Bateria.gastar(B, eb, P, dt); av["Wh"] = eb["Wh"]
	av["T"] = T; av["gases"] = T / Tmax; av["rpm"] = sqrt(T / Tmax) * pr["rpm_max"]
	av["t"] += dt; av["V"] = Va; av["alfa"] = 0.0; av["beta"] = 0.0; av["perdida"] = 0.0; av["g_carga"] = T / (m * G0)
	return vn2

func bateria_pct(av: Dictionary) -> float:
	if av.get("bat") != null: return Bateria.pct(B, av["bat"])
	return maxf(0, 100 * (1 - av["Wh"] / propulsion["masa_bateria_Wh"]))
