class_name ModeloBipode
## Bipode de asalto HQ-07 (vehiculo secreto): traduccion LITERAL de la clase ModeloBipode de simulador/js/bipode.js.
## Anda por el terreno: palanca izquierda (mando.vz adelante, mando.guinada giro), derecha (mando.yaw cintura sin tope,
## mando.pitch brazos) y gatillos (mando.disparo, mando.puno). El suelo lo pone el simulador (av.agl y av.pendiente).

const D2R := PI / 180.0

var datos: Dictionary
var nombre := ""
var b_m := 3.2
var masa_kg := 7500.0
var facil := false
var compensador_grados := 0.0
var lanzamiento := { "vel_ms": 0, "cabeceo_grados": 0 }
var mandos := {}
var bp: Dictionary
var piv := {}

func _init(d: Dictionary) -> void:
	datos = d; nombre = String(d.get("nombre", "")); b_m = float(d.get("b_m", 3.2)); masa_kg = float(d.get("masa_kg", 7500))
	mandos = d.get("mandos", {}); bp = d["bipode"]
	for pz in d["modelo3d"]["piezas"]: piv[pz["nombre"]] = pz["pivote"]

func configurar(_c: Dictionary) -> void: pass
func bateria_pct(_av: Dictionary) -> float: return 100.0

## Parado y con el reactor apagado ("en mano" para el simulador: L o A lo arrancan).
func estado_inicial() -> Dictionary:
	return { "p": [0.0, 0.0, 0.0], "q": Cuat.desde_euler(0, 0, 0), "v": [0.0, 0.0, 0.0], "w": [0.0, 0.0, 0.0], "de": 0.0, "dr": 0.0, "da": 0.0,
			 "gases": 0.0, "Wh": 0.0, "asim": 0.0, "estado": "en mano", "t": 0.0, "alfa": 0.0, "beta": 0.0, "V": 0.0, "g_carga": 1.0, "perdida": 0.0,
			 "T": 0.0, "rpm": 0.0, "motorRoto": false,
			 "rumbo": 0.0, "vel": 0.0, "giro": 0.0, "alabeo": 0.0, "cabeceo": 0.0, "cintura": 0.0, "brazos": 0.0, "fase": 0.0, "amp": 0.0, "pisadas": 0,
			 "wCanones": 0.0, "angCanones": 0.0, "tDisparo": 0.0, "disparos": 0, "puno": 0.0,
			 "cmd": { "avance": 0.0, "giro": 0.0, "cintura": 0.0, "brazos": 0.0, "fuego": 0.0, "puno": 0.0 } }

## Arrancar: ya puede andar.
func lanzar(av: Dictionary) -> void:
	av["estado"] = "volando"; av["rumbo"] = fposmod(Cuat.euler(av["q"])[2], TAU); av["v"] = [0.0, 0.0, 0.0]
func desarmar(_av: Dictionary) -> void: pass
func armar_en_vuelo(av: Dictionary) -> void: lanzar(av)

func servos(av: Dictionary, mando: Dictionary, _dt: float) -> void:
	var c: Dictionary = av["cmd"]
	c["avance"] = float(mando.get("vz", 0.0)); c["giro"] = float(mando.get("guinada", 0.0)); c["cintura"] = float(mando.get("yaw", 0.0)); c["brazos"] = float(mando.get("pitch", 0.0))
	c["fuego"] = 1.0 if mando.get("disparo", false) else 0.0; c["puno"] = 1.0 if mando.get("puno", false) else 0.0

func paso(av: Dictionary, _viento, dt: float) -> Array:
	var B := bp; var c: Dictionary = av["cmd"]; var suelo: float = (-av["p"][2] - av["agl"]) if av.has("agl") else 0.0
	av["t"] += dt
	# --- velocidad: la palanca pide una velocidad; la inercia de 7,5 t la alcanza con su aceleracion
	var v_obj: float = c["avance"] * B["vel_max_ms"] if c["avance"] >= 0 else c["avance"] * B["vel_atras_ms"]
	var pend: Array = av.get("pendiente", [0.0, 0.0]); var cr := cos(float(av["rumbo"])); var sr := sin(float(av["rumbo"]))
	var g_ad: float = pend[0] * cr + pend[1] * sr; var g_de: float = -pend[0] * sr + pend[1] * cr
	var subida := g_ad if v_obj >= 0 else -g_ad
	if subida > 0: v_obj *= maxf(0.0, 1.0 - subida / B["pendiente_max"])
	var dv: float = v_obj - av["vel"]
	var a: float = B["acel_ms2"] if (absf(v_obj) > absf(av["vel"]) and v_obj * av["vel"] >= 0) else B["frena_ms2"]
	av["vel"] += signf(dv) * minf(absf(dv), a * dt)
	# --- giro: mas lento cuanto mas deprisa anda
	var k := minf(1.0, absf(av["vel"]) / B["vel_max_ms"]); var giro_max: float = (B["giro_max_gs"] + (B["giro_marcha_gs"] - B["giro_max_gs"]) * k) * D2R
	av["giro"] += (c["giro"] * giro_max - av["giro"]) * minf(1.0, dt / 0.25)
	av["rumbo"] = fposmod(av["rumbo"] + av["giro"] * dt, TAU)
	# --- cintura (sin tope) y brazos
	av["cintura"] = fposmod(av["cintura"] + c["cintura"] * B["cintura_gs"] * D2R * dt, TAU)
	av["brazos"] = clampf(av["brazos"] + c["brazos"] * B["brazos_gs"] * D2R * dt, B["brazos_min_grados"] * D2R, B["brazos_max_grados"] * D2R)
	av["puno"] += (c["puno"] - av["puno"]) * minf(1.0, dt / 0.15)
	# --- posicion sobre el terreno (el simulador la ajusta a la altura del terreno donde quede)
	av["p"][0] += cr * av["vel"] * dt; av["p"][1] += sr * av["vel"] * dt; av["p"][2] = -suelo
	# --- el cuerpo se inclina con el terreno
	var kt := minf(1.0, dt / B["inclina_tau_s"])
	av["cabeceo"] += (atan(g_ad) - av["cabeceo"]) * kt; av["alabeo"] += (-atan(g_de) - av["alabeo"]) * kt
	av["q"] = Cuat.desde_euler(av["alabeo"], av["cabeceo"], av["rumbo"])
	av["v"] = [av["vel"], 0.0, 0.0]; av["V"] = absf(av["vel"])
	# --- paso: la fase avanza con lo andado (girando sobre si mismo tambien da pasos); amplitud segun la marcha
	var ciclo: float = B["paso_m"] / B["apoyo"]; var v_paso := maxf(absf(av["vel"]), absf(av["giro"]) * 0.9)
	var amp_obj := minf(1.0, v_paso / (0.35 * B["vel_max_ms"]))
	av["amp"] += (amp_obj - av["amp"]) * minf(1.0, dt / 0.35)
	var f0: float = av["fase"]
	av["fase"] = fposmod(av["fase"] + (-1.0 if av["vel"] < -0.01 else 1.0) * v_paso / ciclo * dt, 1.0)
	if av["amp"] > 0.3 and floori(f0 * 2) != floori(av["fase"] * 2): av["pisadas"] += 1
	# --- cañon rotativo: los tubos cogen vueltas con el gatillo; dispara a la cadencia cuando van al 80 %
	var w_max: float = B["cadencia_rpm"] / 60.0 / 6.0 * TAU
	av["wCanones"] += (c["fuego"] * w_max - av["wCanones"]) * minf(1.0, dt / B["giro_canones_tau_s"])
	av["angCanones"] = fmod(av["angCanones"] + av["wCanones"] * dt, TAU)
	if c["fuego"] > 0 and av["wCanones"] > 0.8 * w_max:
		av["tDisparo"] += dt
		var cada: float = 60.0 / B["cadencia_rpm"]
		while av["tDisparo"] >= cada: av["tDisparo"] -= cada; av["disparos"] += 1
	else: av["tDisparo"] = 0.0
	av["rpm"] = av["wCanones"] / TAU * 60.0; av["gases"] = minf(1.0, absf(av["vel"]) / B["vel_max_ms"])
	return [av["vel"] * cr, av["vel"] * sr, 0.0]

## Desde donde y hacia donde sale el disparo (NED del mundo): la boca del cañon con la cintura y los brazos girados.
## Vale para el estado de otro jugador: solo usa p, q, cintura y brazos.
func apuntado(av: Dictionary) -> Dictionary:
	return ModeloBipode.apuntado_con(piv, bp, av)

static func apuntado_con(P: Dictionary, B: Dictionary, av: Dictionary) -> Dictionary:
	var H: Array = P["brazo_d"]; var C: Array = P["cintura"]; var bo: Array = B["boca"]; var th: float = av["brazos"]; var ps: float = av["cintura"]
	var rb := func(v: Array) -> Array: return [v[0] * cos(th) + v[2] * sin(th), v[1], -v[0] * sin(th) + v[2] * cos(th)]
	var rc := func(v: Array) -> Array: return [v[0] * cos(ps) - v[1] * sin(ps), v[0] * sin(ps) + v[1] * cos(ps), v[2]]
	var b1: Array = rb.call([bo[0] - H[0], bo[1] - H[1], bo[2] - H[2]])
	var b3: Array = rc.call([H[0] + b1[0] - C[0], H[1] + b1[1] - C[1], H[2] + b1[2] - C[2]])
	var local := [C[0] + b3[0], C[1] + b3[1], C[2] + b3[2]]; var d: Array = rc.call(rb.call([1.0, 0.0, 0.0]))
	var o := Cuat.rot(av["q"], local); var dm := Cuat.rot(av["q"], d)
	return { "o": [av["p"][0] + o[0], av["p"][1] + o[1], av["p"][2] + o[2]], "d": dm }
