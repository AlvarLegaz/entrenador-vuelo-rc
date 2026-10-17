class_name Bateria
## Bateria de los vehiculos electricos: Bateria de simulador_web/js/bateria.js, el mismo calculo (para que los dos
## simuladores vuelen igual). Celdas en serie con su curva de tension en vacio segun la carga, LiPo (FPV y aviones) o
## Li-ion (drones comerciales); resistencia interna que hace caer la tension con la corriente (mas con frio); capacidad
## algo menor con frio; un pequeno desequilibrio entre celdas que crece al vaciarse; y la temperatura del pack, que sube
## con la corriente (I^2 R) y se enfria hacia la del aire. Agotada, la tension se desploma.
## Uso en un modelo: B = Bateria.datos(propulsion); estado e = Bateria.nueva(B, temp_c); en cada paso V =
## Bateria.tension(B, e) (con la potencia del paso anterior) y, con la potencia de este paso, Bateria.gastar(B, e, P, dt).

const CURVAS := {
	"lipo": { "soc": [0, 0.05, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1], "v": [3.27, 3.5, 3.62, 3.7, 3.75, 3.79, 3.83, 3.87, 3.92, 4.0, 4.08, 4.2] },
	"liion": { "soc": [0, 0.05, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1], "v": [3.0, 3.3, 3.42, 3.52, 3.6, 3.66, 3.72, 3.8, 3.89, 3.98, 4.08, 4.2] },
}
const DESEQUILIBRIO_V := [0.0, -0.006, 0.003, -0.004, 0.005, -0.002]     # de cada celda respecto a la media, llena
const H_W_K := 0.3                                                        # enfriamiento del pack (W por grado sobre el aire)

## Datos de la bateria de un vehiculo: su bloque "bateria" o, si no lo tiene, los de su propulsion (el FPV: celdas, mAh,
## resistencia y curva) o los de un avion electrico (LiPo 3S con la energia de masa_bateria_Wh).
static func datos(pr: Dictionary) -> Dictionary:
	if pr.has("bateria"):
		var b: Dictionary = { "curva": null, "R_ohm": 0.05, "masa_kg": 0.1 }; b.merge(pr["bateria"], true); return b
	if pr.has("celdas"):
		return { "quimica": "lipo", "celdas": int(pr["celdas"]), "capacidad_mAh": float(pr["capacidad_mAh"]), "R_ohm": float(pr["R_ohm"]),
				 "masa_kg": float(pr["masa_bateria_Wh"]) / 140, "curva": { "soc": pr["curva_soc"], "v": pr["curva_v"] } if pr.has("curva_soc") else null }
	return { "quimica": "lipo", "celdas": 3, "capacidad_mAh": float(round(float(pr["masa_bateria_Wh"]) / 11.1 * 1000)), "R_ohm": 0.03,
			 "masa_kg": float(pr["masa_bateria_Wh"]) / 140, "curva": null }

## Bateria llena a la temperatura del aire (grados C).
static func nueva(B: Dictionary, temp_c: float) -> Dictionary:
	var c := []; c.resize(int(B["celdas"])); c.fill(0.0)
	var e := { "mAh": 0.0, "Wh": 0.0, "P": 0.0, "I": 0.0, "V": 0.0, "T": temp_c, "Tamb": temp_c, "celdas": c,
			   "fCap": maxf(0.6, minf(1.0, 1 - 0.008 * maxf(0.0, 25 - temp_c))) }        # con frio rinde menos
	tension(B, e)
	return e

static func capacidad(B: Dictionary, e: Dictionary) -> float: return float(B["capacidad_mAh"]) * e["fCap"]
## Carga que le queda (%).
static func pct(B: Dictionary, e: Dictionary) -> float: return maxf(0.0, 100 * (1 - e["mAh"] / capacidad(B, e)))
## Resistencia interna del pack a su temperatura (sube con el frio).
static func R(B: Dictionary, e: Dictionary) -> float: return float(B["R_ohm"]) * (1 + 0.04 * maxf(0.0, 25 - e["T"]))

static func _interp(xs: Array, ys: Array, x: float) -> float:
	if x <= xs[0]: return ys[0]
	if x >= xs[-1]: return ys[-1]
	for i in range(1, xs.size()):
		if x <= xs[i]:
			var t: float = (x - xs[i - 1]) / (xs[i] - xs[i - 1]); return ys[i - 1] + t * (ys[i] - ys[i - 1])
	return ys[-1]

## Tension en vacio de una celda con la carga gastada; agotada (mas alla de su capacidad), se desploma (hasta 2,5 V).
static func ocv_celda(B: Dictionary, e: Dictionary, k := 1.0) -> float:
	var C: Dictionary = B["curva"] if B["curva"] != null else CURVAS.get(B["quimica"], CURVAS["lipo"])
	var cap := capacidad(B, e) * k; var soc := maxf(0.0, minf(1.0, 1 - e["mAh"] / cap))
	return maxf(2.5, _interp(C["soc"], C["v"], soc) - 6 * maxf(0.0, e["mAh"] - cap) / cap)

## Tension en bornes (V) con la potencia que se pide (la del paso anterior, e.P): en vacio menos la caida por la
## resistencia interna. Si se pide mas de lo que puede dar, se queda en la mitad (potencia maxima). Pone tambien la
## tension de cada celda. Una celda debil (B.debil = { i, k }: averia de desgaste.gd) se vacia antes, con el doble de
## resistencia. Como Bateria.tension en JS.
static func tension(B: Dictionary, e: Dictionary) -> float:
	var soc := maxf(0.0, minf(1.0, 1 - e["mAh"] / capacidad(B, e))); var ocv := ocv_celda(B, e); var r := R(B, e); var n: int = int(B["celdas"])
	var D = B.get("debil"); var di: int = int(D["i"]) if D != null else -1
	var rv: float = r * (n + 1) / n if D != null else r
	var celdas: Array = e["celdas"]; var Voc := 0.0
	for i in n: celdas[i] = (ocv_celda(B, e, float(D["k"])) if i == di else ocv) + DESEQUILIBRIO_V[i % 6] * (1 + 2 * (1 - soc)); Voc += celdas[i]
	var disc: float = Voc * Voc - 4 * rv * e["P"]; var V := 0.5 * (Voc + sqrt(disc)) if disc > 0 else 0.5 * Voc; var I: float = e["P"] / maxf(0.1, V)
	for i in n: celdas[i] -= I * r / n * (2.0 if i == di else 1.0)
	e["V"] = V; e["I"] = I
	return V

## Gasta la potencia P (W) durante dt (s): corriente, carga, energia y calentamiento.
static func gastar(B: Dictionary, e: Dictionary, P: float, dt: float) -> void:
	e["P"] = maxf(0.0, P); e["I"] = e["P"] / maxf(0.1, e["V"])
	e["mAh"] += e["I"] * dt / 3.6; e["Wh"] += e["P"] * dt / 3600
	e["T"] += (e["I"] * e["I"] * R(B, e) - H_W_K * (e["T"] - e["Tamb"])) * dt / (1000 * float(B["masa_kg"]))

## Tension de la celda mas baja (V).
static func celda_min(B: Dictionary, e: Dictionary) -> float:
	var m := INF
	for c in e["celdas"]: m = minf(m, c)
	return m
