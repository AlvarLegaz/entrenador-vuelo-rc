class_name Escenarios
extends RefCounted
## Entrenamientos y vuelos libres: los datos son los de simulador/escenarios.js (COMUNES con la web) y la logica es una
## traduccion literal de la de simulador/simulador.html: nuevoEvaluador, marcar, evaluar, pasoOcho, la guia del
## aterrizaje (GUIA_TRAMOS, guiar), evaluarFinal y los textos del panel de objetivos (pintarObjetivos, textoOrden,
## textoVueltas, textoZona2, textoOcho), aqui en BBCode para un RichTextLabel.
##
## Uso desde principal.gd: E = Escenarios.datos(); ev = Escenarios.Evaluador.new(id, ent, p); en cada muestra de la caja
## negra ev.evaluar(av, dt); al acabar ev.evaluar_final(final, vn); ev.objetivos_bb(...) para el panel.

const D2R := PI / 180.0
const R2D := 180.0 / PI
static var _datos := {}

## ESCENARIOS de la web: { id: { nombre, desc, objetivos: [[id, texto]], sentido, zona, mundo, viento, guia, enVuelo,
## dificultad, titulo_grupo } }, en el orden del fichero.
static func datos() -> Dictionary:
	if not _datos.is_empty(): return _datos
	var t := FileAccess.get_file_as_string(DatosComunes.carpeta().path_join("escenarios.js"))
	var re := RegEx.new(); re.compile("(?m)^window[.]ESCENARIOS = ")     # la asignacion (el comentario de arriba la nombra)
	var m := re.search(t)
	if m == null: push_error("Sin escenarios.js"); return {}
	var resto := t.substr(m.get_end()); var d = JSON.parse_string(resto.substr(0, resto.rfind("}") + 1))
	_datos = d if d is Dictionary else {}
	return _datos

## Tipo de vehiculo de un avion: "avion", "dron" (el dron comercial) o "fpv" (escenarios.js: "vehiculos"; vehiculoDe de la web).
static func vehiculo_de(id: String) -> String:
	var D := DatosComunes.avion(id); var t := String(D.get("tipo", ""))
	if D.get("uav", false): return "uav"
	return "fpv" if t == "fpv" else ("dron" if t == "cuadricoptero" else ("bipode" if t == "bipode" else "avion"))
## Los entrenamientos (con objetivos) de un vehiculo, en el orden de escenarios.js (misionesDe).
static func misiones_de(veh: String) -> Array:
	var r := []
	for id in datos():
		if not (datos()[id]["objetivos"] as Array).is_empty() and not datos()[id].has("operacion") and veh in datos()[id].get("vehiculos", ["avion"]): r.append(id)
	return r
## Los trabajos del modo Operaciones (escenarios.js: "operacion"), en el orden del fichero (operacionesLista de la web).
static func operaciones() -> Array:
	var r := []
	for id in datos():
		if datos()[id].has("operacion"): r.append(id)
	return r
static func zona_de(id: String) -> int: return int(datos()[id].get("zona", 1))
static func libre(id: String) -> bool: return (datos()[id]["objetivos"] as Array).is_empty()
static func es_mundo(id: String) -> bool: return datos()[id].has("mundo")

## Pilon de color en BBCode (circulo del color y su nombre), como pilonHTML.
static func pilon_bb(ent: Entorno, i: int, mayus := false) -> String:
	var c: Dictionary = ent.circuito["colores"][i]
	var nom := String(c["nombre"])
	return "[color=%s]●[/color] %s" % [String(c["hex"]), nom.to_upper() if mayus else nom]

static func orden_bb(ent: Entorno, sentido: int) -> String:
	var idx := [0, 1, 2, 3]
	if sentido < 0: idx.reverse()
	var partes := []
	for i in idx: partes.append(pilon_bb(ent, i))
	return " → ".join(partes)

const OCHO_PASOS := ["por fuera del rojo y el azul", "cruzar el centro", "por fuera del amarillo y el verde", "cruzar el centro", "volver al pilón rojo"]

## Tramos del aterrizaje guiado (GUIA_TRAMOS de la web). fin: el tramo esta hecho (s = lo que ve el piloto).
static func guia_tramos() -> Array:
	return [
		{ "id": "nivelar", "texto": "Vuelas a 35 m sobre la pista, rumbo norte. Pon el gas al 50 % (S) y mantén el avión recto y nivelado hasta pasar el final de la pista.",
		  "rumbo": 0, "h": [28, 42], "gas": [0.4, 0.65], "fin": func(s): return s["N"] > 110 },
		{ "id": "viraje1", "texto": "Vira a la DERECHA (→) hasta rumbo 180° (sur): inclina unos 30° y tira un poco para no perder altura. Suelta el alabeo antes de llegar al rumbo.",
		  "rumbo": 180, "giro": 1, "h": [24, 42], "gas": [0.4, 0.65], "fin": func(s): return absf(s["err"]) < 25 and s["E"] > 20 },
		{ "id": "viento_cola", "texto": "Tramo con el viento en cola: recto rumbo 180°, pasando por tu derecha a 60–100 m. Baja el gas al 40 % (S) y deja que descienda a 20 m. Sigue hasta pasar por detrás de ti.",
		  "rumbo": 180, "h": [15, 30], "gas": [0.3, 0.5], "e": [30, 130], "fin": func(s): return s["N"] < -50 },
		{ "id": "base", "texto": "Base: vira a la DERECHA a rumbo 270° (oeste), gas al 30 %, y baja a 10–15 m. Cuando tengas la pista delante a la derecha, prepara el último viraje.",
		  "rumbo": 270, "giro": 1, "h": [8, 20], "gas": [0.2, 0.4], "fin": func(s): return s["E"] < 35 and absf(s["err"]) < 30 },
		{ "id": "final", "texto": "Final: vira a la DERECHA a rumbo 0° (norte) y alinéate con la pista. Gas al 20–30 %, morro un poco abajo, velocidad por encima de VMIN m/s. No tires de la profundidad hasta estar a 2 m.",
		  "rumbo": 0, "giro": 1, "h": [0, 14], "gas": [0.1, 0.35], "e": [-15, 15], "fin": func(s): return s["h"] < 2.5 and absf(s["err"]) < 35 },
		{ "id": "toma", "texto": "¡Ahora! Corta el gas (espacio) y tira un poquito (↓) para aplanar: deja que se pose solo, sin inclinar las alas.",
		  "rumbo": 0, "h": [0, 3], "gas": [0, 0.08], "fin": func(_s): return false },
	]

static func desenrollar(d: float) -> float: return d - TAU * round(d / TAU)
static func err_rumbo(rumbo: float, obj: float) -> float: return desenrollar((obj - rumbo) * D2R) * R2D
static func err_rumbo_derecha(rumbo: float, obj: float) -> float:
	var e := fposmod(obj - rumbo + 360, 360)
	return e - 360 if e > 340 else e


## Evaluador del vuelo en curso (ev de la web).
class Evaluador extends RefCounted:
	var id := ""
	var E := {}
	var ent: Entorno
	var obj := {}            # id -> { texto, estado: "pend" | "curso" | "ok" | "mal" } en el orden de la mision
	var orden := []
	var contador = null      # ContadorVueltas (zona 1)
	var pasada = null        # PasadaBaja (zona 2)
	var zona := 1
	var pasadas := { "este": 0, "oeste": 0 }
	var puertas := 0
	var subido := false
	var toma := {}
	var perdida_t := 0.0
	var t40 := -1.0
	var t_fallo := -1.0
	var fallo_hecho := false
	var ocho_fase := -1
	var ochos := 0
	var guia := {}           # aterrizaje guiado: { i, vs, vmin }
	var tramos := []
	var guia_bb := ""        # texto de la banda de la guia
	var p                    # principal (avisos, toasts)
	var fpv: PistaFpv = null # entrenamientos del dron FPV (escenarios.js: "pista_fpv")
	var op: Operacion = null # trabajos del modo Operaciones (escenarios.js: "operacion")

	func _init(id_: String, ent_: Entorno, p_) -> void:
		id = id_; ent = ent_; p = p_; E = Escenarios.datos()[id]
		for o in E["objetivos"]: obj[o[0]] = { "texto": o[1], "estado": "pend" }; orden.append(o[0])
		zona = int(E.get("zona", 1))
		if not E.has("mundo"):
			contador = ent.contador_vueltas(int(E.get("sentido", 0)))
			pasada = ent.pasada_baja()
		for k in ["cerca", "sinPerdida", "modo", "bateria", "bajo4", "altura13", "techo", "vlos", "zona", "baja", "distancia", "suave", "atex", "unidades"]:
			if obj.has(k): obj[k]["estado"] = "curso"
		if E.has("operacion") and not ent.mundo.is_empty():    # el trabajo, con los desperfectos, las manchas o el senderista en sitios al azar de la zona
			var dd: Dictionary = Operacion.sortear(Operacion.ajustar(E["operacion"], p.sala.get("ajustes")))
			var anotar := func(k: String, tx: String) -> void:
				if obj.has(k): obj[k]["texto"] += " (%s)" % tx
			op = Operacion.new(dd, marcar, anotar, { "casa": [p.casa["N"], p.casa["E"]], "suelo": func(N: float, Ee: float) -> float: return ent.altura(N, Ee), "h0": float(ent.terreno["h0"]),
				"solido": func(N: float, Ee: float, up: float) -> bool: return ent.choca_edificio([N, Ee, -up], 0.0) })
		if E.has("pista_fpv") and not E.has("mundo"): fpv = PistaFpv.new(E["pista_fpv"], marcar)

	func marcar(k: String, estado: String) -> void:
		if obj.has(k) and obj[k]["estado"] != "mal": obj[k]["estado"] = estado

	func estado(k: String) -> String: return obj[k]["estado"] if obj.has(k) else ""

	## evaluar(dt) de la web: cada muestra de la caja negra (20 Hz).
	func evaluar(av: Dictionary, dt: float) -> void:
		if av["estado"] != "volando": return
		var h: float = -av["p"][2]; var N: float = av["p"][0]; var Ee: float = av["p"][1]; var dist := Vector2(N, Ee).length(); var t: float = av["t"]
		if h >= 20: marcar("subir", "ok"); subido = true
		if h >= 40:
			marcar("subir40", "ok")
			if t40 < 0: t40 = t; t_fallo = t + 8 + 12 * randf()
		if contador != null:
			if contador.vueltas >= 1: marcar("circ1", "ok")
			if contador.vueltas >= 2: marcar("circ2", "ok")
		for i in range(1, 4):
			if puertas >= i: marcar("puerta" + str(i), "ok")
		if pasadas["oeste"]: marcar("pasadaO", "ok")
		if pasadas["este"]: marcar("pasadaE", "ok")
		if pasadas["oeste"] + pasadas["este"]: marcar("pasada", "ok")
		if obj.has("ocho1"):
			var o := paso_ocho(N, Ee)
			if o >= 1: marcar("ocho1", "ok")
			if o >= 2: marcar("ocho2", "ok")
		if dist > 200: marcar("cerca", "mal")
		perdida_t = perdida_t + dt if (av["perdida"] > 0.6 and t > 3) else 0.0
		if perdida_t > 0.3:
			marcar("sinPerdida", "mal")
			if fallo_hecho: marcar("fallo", "mal")
		if id == "emergencia" and t_fallo >= 0 and not fallo_hecho and t >= t_fallo:
			fallo_hecho = true; av["motorRoto"] = true; av["gases"] = 0.0; marcar("fallo", "curso")
			p.poner_aviso("¡FALLO DE MOTOR!", 2.5)
		if not guia.is_empty(): guiar(av)

	## Pasos del ocho de la mision de orientacion con la posicion; devuelve los ochos completos (pasoOcho).
	func paso_ocho(N: float, Ee: float) -> int:
		var P: Array = ent.circuito["pilones"]; var es := []; var ns := []
		for q in P: ns.append(q[0]); es.append(q[1])
		var e_der: float = es.max(); var e_izq: float = es.min(); var n_min: float = ns.min() - 15; var n_max: float = ns.max() + 15; var rojo: Array = P[2]
		var en_franja := N > n_min and N < n_max
		if ocho_fase < 0: ocho_fase = 0; ochos = 0
		var f := ocho_fase
		if f == 0 and en_franja and Ee > e_der + 5: ocho_fase = 1
		elif f == 1 and absf(Ee) < 15: ocho_fase = 2
		elif f == 2 and en_franja and Ee < e_izq - 5: ocho_fase = 3
		elif f == 3 and absf(Ee) < 15: ocho_fase = 4
		elif f == 4 and Vector2(N - rojo[0], Ee - rojo[1]).length() < 45:
			ocho_fase = 0; ochos += 1; p.poner_toast("¡Ocho %d!" % ochos)
		if ocho_fase != f and ocho_fase != 0:
			var s: String = Escenarios.OCHO_PASOS[ocho_fase]; p.poner_toast(s.substr(0, 1).to_upper() + s.substr(1))
		return ochos

	func texto_ocho() -> String:
		if ocho_fase < 0: return ""
		if ochos >= 2: return "Los dos ochos hechos · Ahora: [b]aterrizar[/b]\n"
		return "Ocho %d de 2 · Ahora: [b]%s[/b]\n" % [ochos + 1, Escenarios.OCHO_PASOS[ocho_fase]]

	# ---- aterrizaje guiado ----
	func empezar_guia(vs: float) -> void:
		tramos = Escenarios.guia_tramos()
		guia = { "i": 0, "vs": vs, "vmin": round(1.3 * vs * 10) / 10.0 }

	func guiar(av: Dictionary) -> void:
		var g := guia; var F: Dictionary = tramos[g["i"]]
		var e := Cuat.euler(av["q"]); var h: float = -av["p"][2]
		var s := { "N": av["p"][0], "E": av["p"][1], "h": h, "V": av["V"], "gas": av["gases"], "rumbo": fposmod(e[2] * R2D + 360, 360), "roll": e[0] * R2D }
		s["err"] = Escenarios.err_rumbo_derecha(s["rumbo"], F["rumbo"]) if F.get("giro", 0) else Escenarios.err_rumbo(s["rumbo"], F["rumbo"])
		if F["fin"].call(s) and g["i"] < tramos.size() - 1:
			marcar(F["id"], "ok"); g["i"] += 1
			var sig: Dictionary = tramos[g["i"]]
			marcar(sig["id"], "curso")
			var nombre: String = String(obj[sig["id"]]["texto"]).substr(3) if obj.has(sig["id"]) else sig["id"]
			p.poner_toast("¡Corta gas y aplana!" if sig["id"] == "toma" else "Tramo %d de 5: %s" % [g["i"], nombre])
			guiar(av); return
		var P := []; var peligro := false
		if s["V"] < 1.1 * g["vs"] and h > 1: P.append("¡VELOCIDAD %.1f m/s! Baja el morro (↑) o da gas (W)" % s["V"]); peligro = true
		if F["id"] == "base" and s["E"] > 35 and absf(s["err"]) < 30: P.append("Sigue recto al oeste hasta tener la pista casi delante (te faltan %.0f m)" % (s["E"] - 20))
		if absf(s["roll"]) > 45: P.append("¡Alabeo %.0f°! Nivela las alas (%s)" % [absf(s["roll"]), "←" if s["roll"] > 0 else "→"])
		if absf(s["err"]) > 20: P.append("Rumbo %.0f° → %d°: gira a la %s" % [s["rumbo"], F["rumbo"], "derecha (→)" if s["err"] > 0 else "izquierda (←)"])
		if F.has("e") and (s["E"] < F["e"][0] or s["E"] > F["e"][1]):
			if F["id"] == "final": P.append("Estás %.0f m a la %s de la pista: corrige con un poco de %s" % [absf(s["E"]), "derecha" if s["E"] > 0 else "izquierda", "←" if s["E"] > 0 else "→"])
			else: P.append("Vas a %.0f m al este: el tramo va a 60–100 m de ti" % s["E"])
		if h < F["h"][0]: P.append("Altura %.0f m: demasiado bajo, un poco de gas (W)" % h)
		elif h > F["h"][1]: P.append("Altura %.0f m: demasiado alto, quita gas (S) y baja el morro" % h)
		var gm := int(round((F["gas"][0] + F["gas"][1]) * 50))
		if s["gas"] < F["gas"][0] - 0.02: P.append("Gas %.0f %%: súbelo al %d %% (W)" % [s["gas"] * 100, gm])
		elif s["gas"] > F["gas"][1] + 0.02: P.append("Gas %.0f %%: bájalo al %d %% (S)" % [s["gas"] * 100, gm])
		var texto: String = String(F["texto"]).replace("VMIN", str(g["vmin"]))
		var pistas := "Vas bien: sigue así" if P.is_empty() else "  ·  ".join(P.slice(0, 2))
		guia_bb = "[b]%d/6[/b] · %s\n[font_size=14][color=%s]%s[/color][/font_size]" % [g["i"] + 1, texto, "#ff5252" if peligro else "#ffb74d", ("[b]%s[/b]" % pistas) if peligro else pistas]

	## Al acabar el vuelo (evaluarFinal): aterrizaje, pista, alineacion, toma suave, diana...
	func evaluar_final(id_esc: String, final: String, av: Dictionary, vn: Array) -> void:
		var N: float = av["p"][0]; var Ee: float = av["p"][1]; var ok := final == "aterrizado"
		if ok:
			marcar("aterrizar", "mal" if (id_esc == "emergencia" and not fallo_hecho) else "ok")
			if not E.has("mundo"):
				var en_pista: bool = ent.en_pista(N, Ee)
				marcar("enPista", "ok" if en_pista else "mal")
				var tr := atan2(vn[1], vn[0]) * R2D; var desv := minf(absf(tr), 180 - absf(tr))
				marcar("alineado", "ok" if (en_pista and desv <= 25) else "mal")
				marcar("cerca100", "ok" if (fallo_hecho and Vector2(N, Ee).length() <= 100) else "mal")
				toma = ent.diana(N, Ee)
				marcar("suave", "ok" if vn[2] < 1.5 else "mal")
				marcar("diana10", "ok" if toma["d"] <= 10 else "mal")
				marcar("dianaR", "ok" if (toma["d"] <= 10 and obj.has("puertaR") and obj["puertaR"]["estado"] == "ok") else "mal")
		if fpv != null: fpv.final(final, av)
		if op != null: op.final(final, av, { "bateria": p.modelo.bateria_pct(av) })
		for k in orden:
			if obj[k]["estado"] == "curso": obj[k]["estado"] = "ok" if ok else "mal"
		for k in orden:
			if obj[k]["estado"] == "pend": obj[k]["estado"] = "mal"

	# ---- textos del panel de objetivos ----
	func texto_vueltas(id_esc: String) -> String:
		if contador == null: return ""
		var z2 := "Pasos por la puerta: [b]%d[/b] · pasadas bajas válidas: [b]%d[/b]" % [puertas, pasadas["este"] + pasadas["oeste"]]
		if not toma.is_empty() and toma["d"] <= 40: z2 += " · toma a [b]%.1f m[/b] de la diana: [b]%d puntos[/b]" % [toma["d"], toma["puntos"]]
		var z1 := "Vueltas por fuera de los pilones: [b]%d[/b]" % contador.vueltas
		if contador.mejor != null: z1 += " · mejor %.1f s" % contador.mejor
		if zona == 2: return z2
		if id_esc == "libre" and (puertas or pasadas["este"] + pasadas["oeste"] or (not toma.is_empty() and toma["d"] <= 40)): return z1 + "\n" + z2
		return z1

	func texto_zona2(id_esc: String) -> String:
		var hecho := func(k: String) -> bool: return obj.has(k) and obj[k]["estado"] == "ok"
		var sig := ""
		if not subido: sig = "sube a 20 m"
		elif id_esc == "puerta": sig = ("cruzar la puerta naranja (%d/3)" % puertas) if puertas < 3 else "aterrizar"
		elif id_esc == "pasada_baja": sig = "pasada baja hacia el oeste (de izquierda a derecha)" if not hecho.call("pasadaO") else ("pasada baja hacia el este (de derecha a izquierda)" if not hecho.call("pasadaE") else "aterrizar")
		elif id_esc == "diana": sig = "aterrizar en la diana"
		elif id_esc == "recorrido": sig = "1. pasada baja por la pista 2 (2 a 8 m)" if not hecho.call("pasada") else ("2. cruzar la puerta naranja" if not hecho.call("puertaR") else "3. aterrizar en la diana")
		return "Zona 2, detrás de ti · Ahora: [b]%s[/b]\n" % sig

	func texto_orden() -> String:
		if contador == null: return ""
		var sig = contador.siguiente()
		var sen := int(E.get("sentido", 0))
		var cab := ("Orden: " + Escenarios.orden_bb(ent, sen)) if sen else "Pilones en cualquier sentido"
		var siguiente := ("el que quieras para salir" if sen else "el que quieras") if sig == null else Escenarios.pilon_bb(ent, int(sig), true)
		return "%s\nSiguiente pilón: [b]%s[/b]\n" % [cab, siguiente]

	## Lineas de los objetivos con su icono y color (pintarObjetivos).
	func lineas_objetivos() -> String:
		var icono := { "ok": "✓", "mal": "✘", "pend": "○", "curso": "◔" }
		var color := { "ok": "#8be08f", "mal": "#ff8a80", "pend": "#dddddd", "curso": "#b3e5fc" }
		var t := ""
		for k in orden:
			var o: Dictionary = obj[k]
			t += "[color=%s]%s %s[/color]\n" % [color[o["estado"]], icono[o["estado"]], o["texto"]]
		return t
