class_name AppEvaluacion
extends RefCounted
## El punto de lanzamiento en el mundo real (la evaluacion de los escenarios esta en escenarios.gd).
## Parte de principal.gd (como js/app/evaluacion.js de la web): el estado esta en principal.gd (p).

var p: Principal

func _init(principal: Principal) -> void: p = principal

func ent_campo() -> Entorno: return p._ent_campo

func _casa() -> Dictionary:
	if p.es_uav() and p.con_tren():           # UAV de pista: en la cabecera
		var P = pista_actual()
		if P != null:
			var r: float = float(P["rumbo"]) * p.D2R
			return { "N": P["n"] + 60 * cos(r), "E": P["e"] + 60 * sin(r), "rumbo": float(P["rumbo"]) }
	return { "N": float(p.sesion["lanz"]["N"]), "E": float(p.sesion["lanz"]["E"]) } if (p.en_mundo() and not p.sesion["lanz"].is_empty()) else { "N": 0.0, "E": 0.0 }

## La pista del escenario (escenarios.js "pista" o la de su trabajo), con la altura del suelo en el umbral, o null.
func pista_actual():
	var E: Dictionary = Escenarios.datos().get(p.sesion["escenario"], {}); var P = E.get("pista", E.get("operacion", {}).get("pista"))
	if P == null or not p.en_mundo(): return null
	var r: Dictionary = (P as Dictionary).duplicate(); r["h"] = p.ent.altura(float(P["n"]), float(P["e"])); return r

func rumbo_despejado(N: float, E: float) -> float:
	var mejor := 0.0; var menos := INF; var r := 0.0
	while r < 360:
		var sube := -INF; var d := 100.0
		while d <= 1500:
			sube = maxf(sube, p.ent.altura_mar(N + d * cos(r * p.D2R), E + d * sin(r * p.D2R))); d += 50
		if sube < menos: menos = sube; mejor = r
		r += 22.5
	return mejor

func lat_lon_a_ne(m: Dictionary, lat: float, lon: float) -> Array:
	var o: Dictionary = m["origen"]
	return [(lat - o["lat"]) * 110574, (lon - o["lon"]) * 111320 * cos(o["lat"] * p.D2R)]

func _lanz_por_defecto() -> void:
	if not p.sesion["lanz"].is_empty() and p.sesion["lanz"].get("mundo", "") == p.mundo_datos["id"]: return
	var d: Dictionary = p.LANZ_DEFECTO.get(p.mundo_datos["id"], {})
	if not d.is_empty():
		var ne := lat_lon_a_ne(p.mundo_datos, d["lat"], d["lon"])
		p.sesion["lanz"] = { "mundo": p.mundo_datos["id"], "N": round(ne[0]), "E": round(ne[1]), "rumbo": d["rumbo"], "defecto": true }
	elif not p.indice_zonas.is_empty():
		var z: Dictionary = p.indice_zonas[0]
		p.sesion["lanz"] = { "mundo": p.mundo_datos["id"], "N": round(z["centro"]["N"]), "E": round(z["centro"]["E"]), "rumbo": rumbo_despejado(z["centro"]["N"], z["centro"]["E"]) }
	else: p.sesion["lanz"] = { "mundo": p.mundo_datos["id"], "N": 0.0, "E": 0.0, "rumbo": p.mundo_datos.get("rumbo_despegue", 0) }

## Puntos de despegue destacados del vuelo libre en el mundo real (escenarios.js: "destacados"; destacadosLanz de la web).
func destacados_lanz() -> Array:
	return Escenarios.datos().get(p.sesion["escenario"], {}).get("destacados", [])

## El vehiculo elegido despega de pista (el Cernicalo XM-7): solo sale de un destacado con "pista" (la base de San
## Javier). Como necesitaPista() y destacadoConPista() de la web.
## ---- morro de camaras (datos.camara.morros: el Grajo): fijo (camaras sujetas al avion) u orientable (torreta, con su
## peso); se elige en el Hangar y se guarda por vehiculo (morroDe y datosVisor de la web) ----
func morro_de(id: String):
	var C = DatosComunes.avion(id).get("camara")
	if not C is Dictionary or not C.has("morros"): return null
	var m = p.aj.get("morro", {}).get(id)
	return m if (C["morros"] as Array).has(m) else C["morros"][0]

func poner_morro(id: String, m: String) -> void:
	if not p.aj.has("morro"): p.aj["morro"] = {}
	p.aj["morro"][id] = m; p.app_avion_ajustes._guardar()

## Los datos del vehiculo para dibujarlo, con el morro elegido.
func datos_visor(id: String) -> Dictionary:
	var A := DatosComunes.avion(id); var m = morro_de(id)
	if m == null or not A.has("malla"): return A
	var K: Dictionary = (A["malla"] as Dictionary).duplicate(); var B := A.duplicate(); B["malla"] = K
	if m == "fijo": K.erase("torreta")
	else: K.erase("cam_fija")
	return B

func necesita_pista() -> bool: return DatosComunes.avion(p.sesion["avion"]).get("tren") != null     # los de tren (el Cernicalo) despegan de pista; el Grajo, a mano

func destacado_con_pista() -> Dictionary:
	for d in destacados_lanz():
		if d.has("pista"): return d
	return {}

func elegir_destacado(d: Dictionary) -> void:
	if necesita_pista() and not d.has("pista") and not destacado_con_pista().is_empty():
		d = destacado_con_pista(); p.app_avion_ajustes.poner_toast_menu(String(DatosComunes.avion(p.sesion["avion"]).get("nombre", "")) + " despega de pista: sale de " + String(d["nombre"]))
	var ne := lat_lon_a_ne(p.mundo_datos, d["lat"], d["lon"])
	p.sesion["lanz"] = { "mundo": p.mundo_datos["id"], "N": round(ne[0]), "E": round(ne[1]), "rumbo": float(d["rumbo"]), "destacado": d["nombre"] }; p.app_avion_ajustes._guardar()

func elegir_punto(N: float, E: float) -> void:
	if necesita_pista() and not destacado_con_pista().is_empty(): elegir_destacado(destacado_con_pista()); return     # un avion de pista no sale del campo
	p.sesion["lanz"] = { "mundo": p.mundo_datos["id"], "N": round(N), "E": round(E), "rumbo": rumbo_despejado(N, E) }; p.app_avion_ajustes._guardar()

func colocar_en_base(a: Dictionary, m = null) -> void:
	if m == null: m = p.modelo
	if m is ModeloBipode:                 # el bipode, de pie en el suelo, delante del piloto (en el campo, 10 m al norte)
		if not p.en_mundo(): a["p"] = [10.0, 0.0, 0.0]; return
		var c0 := _casa(); a["p"] = [c0["N"], c0["E"], -p.ent.altura(c0["N"], c0["E"])]; return
	if m is ModeloAvion and m.tren != null:      # avion de pista: sobre sus ruedas
		var ct := _casa() if p.en_mundo() else { "N": 0.0, "E": 0.0 }
		a["p"] = [ct["N"], ct["E"], -((p.ent.altura(ct["N"], ct["E"]) if p.en_mundo() else 0.0) + m.altura_en_tierra())]; return
	if not p.en_mundo(): return
	var c := _casa()
	a["p"] = [c["N"], c["E"], -(p.ent.altura(c["N"], c["E"]) + (0.02 if (m is ModeloCuadricoptero or m is ModeloFPV) else 1.6))]   # en la mano (avion) o en el suelo (dron)
