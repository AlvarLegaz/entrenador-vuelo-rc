class_name ContadorVueltas
extends RefCounted
## VUELTAS AL CIRCUITO de la isla (Entorno.contador_vueltas). Traduccion literal de ContadorVueltas en
## simulador_web/js/entorno.js (simulador_godot/Tests/prueba_campo.gd lo compara con el navegador).
## Se mira el angulo del avion alrededor del centro del rectangulo: cuando cruza la direccion de un pilon, ese pilon esta
## pasado; por fuera si el avion esta mas lejos del centro que el pilon. Una vuelta = rodear las 4 esquinas por fuera, en
## el mismo sentido, hasta volver al pilon de salida. Cortar uno por dentro anula la vuelta en curso. Si el circuito tiene
## sentido obligatorio, pasar un pilon en el sentido contrario tampoco cuenta y anula la vuelta en curso.

var c: Array                # centro del circuito (N, E)
var pil := []               # por pilon: { ang, r } alrededor del centro
var sentido := 0            # +1, -1 o 0 (cualquiera)
var serie := []             # pilones pasados por fuera en la vuelta en curso: { i, sentido }
var vueltas := 0
var t_inicio = null         # null o el tiempo (s) del pilon de salida de la vuelta en curso
var mejor = null            # null o la mejor vuelta (s)
var ultima = null           # null o la ultima vuelta (s)

func _init(circuito: Dictionary, sentido_ := 0) -> void:
	c = circuito["centro"]
	for s in circuito["pilones"]:
		var dn: float = s[0] - c[0]; var de: float = s[1] - c[1]
		pil.append({ "ang": atan2(de, dn), "r": sqrt(dn * dn + de * de) })
	sentido = sentido_

## Indice del siguiente pilon que toca rodear, o null si aun no se ha pasado ninguno (se puede salir de cualquiera).
func siguiente():
	if serie.is_empty(): return null
	var ult: Dictionary = serie[-1]
	return (ult["i"] + (sentido if sentido else ult["sentido"]) + 4) % 4

## x llevado a [-pi, pi] (Math.round de JS: redondea las mitades hacia arriba).
static func _vuelta(x: float) -> float:
	return x - 2 * PI * floor(x / (2 * PI) + 0.5)

## Devuelve {} o un suceso: {tipo: "pilon" | "dentro" | "sentido" | "vuelta", i, n, tiempo}.
func actualizar(p_ant: Array, p: Array, t: float) -> Dictionary:
	var a0 := atan2(p_ant[1] - c[1], p_ant[0] - c[0]); var a1 := atan2(p[1] - c[1], p[0] - c[0])
	var dn: float = p[0] - c[0]; var de: float = p[1] - c[1]; var r := sqrt(dn * dn + de * de)
	if r < 15: return {}
	var d := _vuelta(a1 - a0)
	if d == 0: return {}
	for i in pil.size():
		var hasta := _vuelta(pil[i]["ang"] - a0)
		if signf(hasta) != signf(d) or absf(hasta) > absf(d): continue         # no cruza este pilon
		var sen := int(signf(d))
		if r <= pil[i]["r"]:
			serie = []; t_inicio = null; return { "tipo": "dentro", "i": i }
		if sentido and sen != sentido:
			serie = []; t_inicio = null; return { "tipo": "sentido", "i": i }
		if not serie.is_empty():
			var ult: Dictionary = serie[-1]
			if ult["sentido"] != sen or i != (ult["i"] + sen + 4) % 4: serie = []
		if serie.is_empty(): t_inicio = t
		serie.append({ "i": i, "sentido": sen })
		if serie.size() == 5:       # de vuelta al pilon de salida: las 4 esquinas rodeadas
			vueltas += 1; ultima = t - t_inicio
			if mejor == null or ultima < mejor: mejor = ultima
			serie = [{ "i": i, "sentido": sen }]; t_inicio = t      # este pilon abre la vuelta siguiente
			return { "tipo": "vuelta", "i": i, "n": vueltas, "tiempo": ultima }
		return { "tipo": "pilon", "i": i, "n": serie.size() }
	return {}
