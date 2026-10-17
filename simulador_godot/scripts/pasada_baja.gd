class_name PasadaBaja
extends RefCounted
## PASADA BAJA por la pista 2 de la zona 2 de la isla (Entorno.pasada_baja). Traduccion literal de PasadaBaja en
## simulador_web/js/entorno.js (simulador_godot/Tests/prueba_campo.gd la compara con el navegador): entrar por una punta de la pista (de
## este a oeste o al reves), recorrerla entera sin salirse por los lados (ancho/2 + margen a cada lado del eje) y salir por
## la otra punta, siempre entre hmin y hmax de altura. Tocar el suelo ya termina el vuelo (lo mira el Entorno).

var P: Dictionary           # Entorno.zona2.pista
var en = null               # null o la pasada en curso: { desde, e, hmin, hmax }
var validas := 0

func _init(pista: Dictionary) -> void:
	P = pista

## Un numero como lo escribe JavaScript en un texto: 8 y no 8.0.
static func _num(x: float) -> String:
	return str(int(x)) if x == floorf(x) and absf(x) < 1e15 else str(x)

## Devuelve {} o, al salir de la pista, {ok, sentido: "este" | "oeste" | "lado", hmin, hmax, motivo (si no vale)}.
func actualizar(p: Array) -> Dictionary:
	var h: float = -p[2]
	var dentro: bool = absf(p[0] - P["n"]) <= P["ancho"] / 2 + P["margen"] and p[1] >= P["e0"] and p[1] <= P["e1"]
	if dentro:
		if en == null: en = { "desde": "oeste" if p[1] < (P["e0"] + P["e1"]) / 2 else "este", "e": p[1], "hmin": h, "hmax": h }
		else:
			en["hmin"] = minf(en["hmin"], h); en["hmax"] = maxf(en["hmax"], h)
		return {}
	if en == null: return {}
	var e: Dictionary = en; en = null
	var sale := "este" if p[1] > P["e1"] else ("oeste" if p[1] < P["e0"] else "lado")
	var r := { "ok": false, "sentido": sale, "hmin": e["hmin"], "hmax": e["hmax"] }
	if sale == "lado": r["motivo"] = "te has salido de la pista por un lado"
	elif sale == e["desde"]: r["motivo"] = "no la has recorrido de punta a punta"
	elif e["hmax"] > P["hmax"]: r["motivo"] = "demasiado alta (%.1f m; máximo %s m)" % [e["hmax"], _num(P["hmax"])]
	elif e["hmin"] < P["hmin"]: r["motivo"] = "demasiado baja (%.1f m; mínimo %s m)" % [e["hmin"], _num(P["hmin"])]
	else:
		r["ok"] = true; validas += 1
	# solo avisa de las que de verdad intentan ser una pasada: bajas y siguiendo la pista al menos 20 m (cruzarla alta o
	# de lado, como al lanzar, no es nada)
	return r if e["hmin"] <= P["hmax"] + 7 and (sale != "lado" or absf(p[1] - e["e"]) > 20) else {}
