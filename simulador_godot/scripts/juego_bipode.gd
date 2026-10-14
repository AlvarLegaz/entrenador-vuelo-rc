class_name JuegoBipode
## Juego del bipode: drones diana y disparos. Traduccion LITERAL de la clase JuegoBipode de simulador/js/bipode.js (misma
## semilla, mismo azar Park-Miller): drones que patrullan alrededor del bipode a 15-55 m sobre el suelo, balas con su caida
## (una de cada tres, trazadora), impacto con un dron (cae al primero) o con el suelo, y los drones derribados caen dando
## vueltas y explotan al llegar al suelo; a los 6 s sale otro lejos. Multijugador: blancos (los aviones y drones de los
## demas en el aire) y golpes (impactos dados a cada uno, que van en el estado que se manda a la sala). Todo en NED del
## mundo; el suelo es la funcion altura(N, E) del terreno (Callable; vacio = llano).

const D2R := PI / 180.0
var B: Dictionary
var D: Dictionary
var s := 1
var drones := []
var balas := []
var eventos := []
var derribados := 0
var disparos := 0
var t := 0.0
var n_id := 0
var blancos := []
var golpes := {}

func _init(datos: Dictionary, semilla: int) -> void:
	B = datos["bipode"]; D = B["drones"]; s = (semilla % 2147483646) + 1

func azar() -> float:
	s = (s * 16807) % 2147483647; return (s - 1) / 2147483646.0

func _suelo(altura: Callable, N: float, E: float) -> float:
	return -(float(altura.call(N, E)) if altura.is_valid() else 0.0)

## Punto de patrulla al azar a radio_m (como mucho) del centro y a su altura sobre el suelo.
func _punto(c: Array, altura: Callable, lejos: bool) -> Array:
	var a := azar() * TAU; var r: float = D["radio_m"] * ((0.7 + 0.3 * azar()) if lejos else (0.25 + 0.75 * sqrt(azar())))
	var N: float = c[0] + r * cos(a); var E: float = c[1] + r * sin(a); var h: float = D["alt_min_m"] + (D["alt_max_m"] - D["alt_min_m"]) * azar()
	return [N, E, -((float(altura.call(N, E)) if altura.is_valid() else 0.0) + h)]

func nuevo_dron(c: Array, altura: Callable, lejos: bool) -> void:
	var p := _punto(c, altura, lejos); var o := _punto(c, altura, false)
	n_id += 1
	drones.append({ "id": n_id, "p": p, "v": [0.0, 0.0, 0.0], "obj": o, "estado": "vuela", "vida": int(D["vida"]), "rumbo": 0.0, "giro": 0.0, "tFin": 0.0, "inclina": [0.0, 0.0] })

func iniciar(c: Array, altura: Callable) -> void:
	drones = []; balas = []; eventos = []
	for k in int(D["n"]): nuevo_dron(c, altura, true)

## Una bala desde a = { o, d } (apuntado), con la dispersion del cañon.
func disparo(a: Dictionary) -> void:
	var ds: float = B["dispersion_grados"] * D2R; var u := (azar() - 0.5) * 2 * ds; var w := (azar() - 0.5) * 2 * ds
	var d: Array = a["d"]; var h := Vector2(d[0], d[1]).length()
	var e1 := [-d[1] / h, d[0] / h, 0.0] if h > 1e-6 else [0.0, 1.0, 0.0]
	var e2 := [d[1] * e1[2] - d[2] * e1[1], d[2] * e1[0] - d[0] * e1[2], d[0] * e1[1] - d[1] * e1[0]]
	var dir := [d[0] + u * e1[0] + w * e2[0], d[1] + u * e1[1] + w * e2[1], d[2] + u * e1[2] + w * e2[2]]; var n := Vector3(dir[0], dir[1], dir[2]).length()
	var vb: float = B["bala_ms"]
	balas.append({ "p": (a["o"] as Array).duplicate(), "v": [dir[0] / n * vb, dir[1] / n * vb, dir[2] / n * vb], "t": 0.0, "traza": true })

static func _cerca(p0: Array, p1: Array, c: Array, r: float) -> bool:
	var sv := Vector3(p1[0] - p0[0], p1[1] - p0[1], p1[2] - p0[2]); var q := Vector3(c[0] - p0[0], c[1] - p0[1], c[2] - p0[2])
	var k := clampf(q.dot(sv) / maxf(sv.length_squared(), 1e-9), 0.0, 1.0)
	return (q - sv * k).length_squared() < r * r

## dt en s; av y modelo del bipode (los disparos nuevos salen de modelo.apuntado; modelo puede ser null si no hay nuevos).
func paso(dt: float, av: Dictionary, modelo, altura: Callable) -> void:
	t += dt
	var g := 9.81; var c := [av["p"][0], av["p"][1]]
	while disparos < int(av["disparos"]):
		disparos += 1; disparo(modelo.apuntado(av)); balas[balas.size() - 1]["traza"] = disparos % 3 == 0
	# balas: vuelo con gravedad; choque con los drones (segmento contra esfera), con los compañeros y con el suelo
	var quedan := []
	for b in balas:
		var p0: Array = (b["p"] as Array).duplicate()
		b["v"][2] += g * dt; b["p"] = [b["p"][0] + b["v"][0] * dt, b["p"][1] + b["v"][1] * dt, b["p"][2] + b["v"][2] * dt]; b["t"] += dt
		var fuera: bool = b["t"] * B["bala_ms"] > B["alcance_m"]
		for dr in drones:
			if dr["estado"] != "vuela" or fuera: continue
			if _cerca(p0, b["p"], dr["p"], D["radio_impacto_m"]):
				fuera = true; dr["vida"] -= 1
				eventos.append({ "tipo": "impacto", "p": (dr["p"] as Array).duplicate() })
				if dr["vida"] <= 0:
					dr["estado"] = "cae"; dr["giro"] = (-1.0 if azar() < 0.5 else 1.0) * (6 + 6 * azar()); derribados += 1
					dr["v"] = [dr["v"][0] + b["v"][0] * 0.004, dr["v"][1] + b["v"][1] * 0.004, dr["v"][2] - 2]
					eventos.append({ "tipo": "derribado", "p": (dr["p"] as Array).duplicate() })
		for o in blancos:                  # multijugador: los aviones y drones de los compañeros
			if fuera: break
			if _cerca(p0, b["p"], o["p"], o["r"]):
				fuera = true; golpes[o["id"]] = int(golpes.get(o["id"], 0)) + 1; eventos.append({ "tipo": "impacto", "p": (o["p"] as Array).duplicate() })
		if not fuera and b["p"][2] > _suelo(altura, b["p"][0], b["p"][1]):
			fuera = true; eventos.append({ "tipo": "suelo", "p": [b["p"][0], b["p"][1], _suelo(altura, b["p"][0], b["p"][1])] })
		if not fuera: quedan.append(b)
	balas = quedan
	# drones: patrulla de punto en punto; derribados, caen con su giro hasta el suelo
	for dr in drones:
		if dr["estado"] == "vuela":
			var d := [dr["obj"][0] - dr["p"][0], dr["obj"][1] - dr["p"][1], dr["obj"][2] - dr["p"][2]]; var L := Vector3(d[0], d[1], d[2]).length()
			if L < 4: dr["obj"] = _punto(c, altura, false)
			var vo := [d[0] / L * D["vel_ms"], d[1] / L * D["vel_ms"], d[2] / L * D["vel_ms"]] if L > 1e-6 else [0.0, 0.0, 0.0]; var kk := minf(1.0, dt * 0.8)
			var ax: float = (vo[0] - dr["v"][0]) * kk; var ay: float = (vo[1] - dr["v"][1]) * kk
			dr["v"] = [dr["v"][0] + ax, dr["v"][1] + ay, dr["v"][2] + (vo[2] - dr["v"][2]) * kk]
			var ca := cos(float(dr["rumbo"])); var sa := sin(float(dr["rumbo"])); var aN := ax / maxf(dt, 1e-6) / g; var aE := ay / maxf(dt, 1e-6) / g
			dr["inclina"] = [clampf(-(aN * ca + aE * sa) - 0.12, -0.4, 0.4), clampf(-aN * sa + aE * ca, -0.4, 0.4)]
			if Vector2(dr["v"][0], dr["v"][1]).length() > 0.5: dr["rumbo"] = atan2(dr["v"][1], dr["v"][0])
		elif dr["estado"] == "cae":
			dr["v"][2] += g * dt; dr["rumbo"] += dr["giro"] * dt; dr["inclina"] = [0.6 * sin(t * 7), 0.6 * cos(t * 5)]
			if dr["p"][2] + dr["v"][2] * dt > _suelo(altura, dr["p"][0], dr["p"][1]):
				dr["estado"] = "roto"; dr["tFin"] = 0.0; dr["p"][2] = _suelo(altura, dr["p"][0], dr["p"][1]); dr["v"] = [0.0, 0.0, 0.0]
				eventos.append({ "tipo": "explosion", "p": (dr["p"] as Array).duplicate() })
		else: dr["tFin"] += dt
		if dr["estado"] != "roto": dr["p"] = [dr["p"][0] + dr["v"][0] * dt, dr["p"][1] + dr["v"][1] * dt, dr["p"][2] + dr["v"][2] * dt]
	var vivos := drones.filter(func(x): return not (x["estado"] == "roto" and x["tFin"] > 6))
	var faltan := drones.size() - vivos.size()
	drones = vivos
	for k in faltan: nuevo_dron(c, altura, true)
