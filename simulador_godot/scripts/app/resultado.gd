class_name AppResultado
extends RefCounted
## Resultado y guardado del vuelo y caja negra (CSV a 20 Hz).
## Parte de principal.gd (como js/app/resultado.js de la web): el estado esta en principal.gd (p).

var p: Principal

func _init(principal: Principal) -> void: p = principal

func datos_resultado(v: Dictionary) -> Dictionary:
	var E: Dictionary = Escenarios.datos()[v["escenario"]]; var libre := (E["objetivos"] as Array).is_empty()
	var objs := []
	for k in p.ev.orden: objs.append({ "id": k, "texto": p.ev.obj[k]["texto"], "ok": p.ev.obj[k]["estado"] == "ok" })
	if not libre and not E.has("operacion"): objs.append({ "id": "camara", "texto": "Volar con las gafas FPV (cámara 3)" if p.app_vuelo.con_gafas() else "Volar mirando al dron o con las gafas FPV (cámaras 1 o 3)" if p.es_fpv() else ("Volar mirando al dron o la pantalla de la app (cámaras 1 o 3)" if p.es_dron() else "Volar desde el puesto del piloto (cámara 1)"), "ok": not v["otraCamara"] })
	var apto: bool = not libre and v["final"] == "aterrizado" and objs.all(func(o): return o["ok"])
	return { "E": E, "libre": libre, "objs": objs, "apto": apto, "resultado": "LIBRE" if libre else ("APTO" if apto else "NO APTO") }

func guardar_vuelo(v: Dictionary, d: Dictionary) -> Dictionary:
	if p.sesion["alumno"] == null or v.get("guardado", false): return { "estado": "sin_aula" }
	v["guardado"] = true
	var vv: Dictionary = d["E"].get("viento", p.sesion["viento"]).duplicate()
	if not p.app_avion_ajustes.cm_es_diseno(p.sesion["avion"]): vv["cg_pct"] = p.app_avion_ajustes.cm_actual(p.sesion["avion"])["cg"]; vv["masa_g"] = p.app_avion_ajustes.cm_actual(p.sesion["avion"])["masa"]
	if v["dificultad"] == "facil": vv["fisica"] = "facil"
	var final: String = v["final"]
	return await p.aula.enviar_vuelo({ "id": v["id"], "alumno_id": p.sesion["alumno"]["id"], "inicio": v["inicio"], "fin": Aula.ahora_iso(),
		"avion": DatosComunes.avion(p.sesion["avion"]).get("nombre", p.sesion["avion"]), "escenario": v["escenario"], "tiempo_vuelo_s": snappedf(v["tVuelo"], 0.1),
		"accidentes": 1 if final.begins_with("roto") else 0, "aterrizajes": 1 if final == "aterrizado" else 0,
		"objetivos": d["objs"], "resultado": d["resultado"], "final": final, "viento": vv, "marca": snappedf(v["marca"], 0.01) if v.has("marca") else null })

func mostrar_resultado(v: Dictionary) -> void:
	var R: PantallaResultado.Resultado = p.pantallas["pResultado"]
	if v.get("mostrado", false): p.mostrar("pResultado"); return
	v["mostrado"] = true
	var r := datos_resultado(v)
	R.pintar(v, r); p.mostrar("pResultado")
	if p.sesion["alumno"] == null: R.guardado.text = "Sin conexión con el aula: este vuelo no se ha guardado."; return
	R.guardado.text = "Guardando…"
	var g := await guardar_vuelo(v, r)
	match String(g["estado"]):
		"ok":
			R.guardado.text = "✓ Guardado en el registro del aula."
			var antes = p.sesion["alumno"].get("progreso"); p.sesion["alumno"]["progreso"] = g.get("progreso", {})
			var nuevos := PantallaResultado.logros_nuevos(antes, p.sesion["alumno"]["progreso"])
			if not nuevos.is_empty(): R.guardado.text += " " + " · ".join(nuevos); p.app_avion_ajustes.poner_toast_menu(nuevos[-1])
		"cola": R.guardado.text = "Sin conexión con el aula: se guardará solo en cuanto vuelva (no se perderá)."
		_: R.guardado.text = "No se pudo guardar: " + String(g.get("msg", ""))

func texto_vueltas_plano() -> String:
	if p.ev == null: return ""
	var re := RegEx.new(); re.compile("\\[[^\\]]*\\]")
	return re.sub(p.ev.texto_vueltas(p.sesion["escenario"]), "", true).replace("\n", " · ")

func grabar_muestra() -> void:
	if p.vuelo == null: return
	var e := Cuat.euler(p.av["q"]); var vn := Cuat.rot(p.av["q"], p.av["v"]); var w: Array = p.ent.viento["actual"]
	var r := func(x, n: int) -> float: return snappedf(float(x), pow(10, -n))
	p.vuelo["filas"].append([r.call(p.av["t"], 2), r.call(p.av["p"][0], 2), r.call(p.av["p"][1], 2), r.call(-p.av["p"][2], 2), r.call(p.av["V"], 2), r.call(Vector2(vn[0], vn[1]).length(), 2),
		r.call(-vn[2], 2), r.call(e[0] * p.R2D, 1), r.call(e[1] * p.R2D, 1), r.call(fposmod(e[2] * p.R2D + 360, 360), 1), r.call(p.av["alfa"], 2), r.call(p.av["beta"], 2), r.call(p.av["g_carga"], 2),
		r.call(p.av["gases"] * 100, 1), r.call(p.av["rpm"], 0), r.call(p.av["T"], 3), r.call(p.av["Wh"], 4), r.call(p.modelo.bateria_pct(p.av), 1),
		r.call(p.mando["pitch"], 3), r.call(p.mando["yaw"], 3), r.call(p.mando["trim"], 2), r.call(p.av["de"] * p.R2D, 2), r.call(p.av["dr"] * p.R2D, 2), r.call(p.av.get("da", 0.0) * p.R2D, 2),
		r.call(w[0], 2), r.call(w[1], 2), r.call(p.av["perdida"], 2)])
	RegistroVuelo.muestra(p, p.vuelo)                 # el registro de vuelo del vehiculo (registro_vuelo.gd), a 10 Hz

func nombre_csv(v: Dictionary) -> String:
	var d: Dictionary = v["inicio_local"]
	return "vuelo_%04d-%02d-%02d_%02d-%02d-%02d_%s_%s.csv" % [d["year"], d["month"], d["day"], d["hour"], d["minute"], d["second"], v["escenario"], String(v["final"]).split(" ")[0]]

func texto_csv(v: Dictionary) -> String:
	var d: Dictionary = v["inicio_local"]; var f: Array = v["filas"]
	var cab := ["# %s · vuelo del %02d/%02d/%04d, %02d:%02d:%02d · %s%s" % [DatosComunes.avion(p.sesion["avion"]).get("nombre", ""), d["day"], d["month"], d["year"], d["hour"], d["minute"], d["second"],
				Escenarios.datos()[v["escenario"]]["nombre"], (" · " + String(p.sesion["alumno"]["nombre"])) if p.sesion["alumno"] != null else ""],
		"# masa %d g · %s · viento %s m/s %s rachas · final: %s · %d muestras a 20 Hz" % [int(round(p.modelo.masa_kg * 1000)), p.app_avion_ajustes.texto_cm(), str(p.ent.viento["base"]), "con" if p.ent.viento["rachas"] else "sin", v["final"], f.size()],
		"# ruta: x al norte, y al este, z altura (m, desde el lanzamiento) · profundidad: + = abajo · timon: + = a la derecha · aleron: + = alabeo a la derecha"]
	var lineas := PackedStringArray(cab); lineas.append(",".join(p.CN_COLUMNAS))
	for x in f: lineas.append(",".join(x.map(func(n): return str(int(n)) if float(n) == int(n) else str(n))))
	return "\n".join(lineas) + "\n"

func guardar_csv(v: Dictionary, ruta: String) -> void:
	var fa := FileAccess.open(ruta, FileAccess.WRITE)
	if fa == null: p.poner_toast("No se pudo guardar la caja negra"); return
	fa.store_string(texto_csv(v)); fa.close()

func guardar_csv_dialogo() -> void:
	if p.ultimo_vuelo == null: return
	p.dialogo.title = "Guardar la caja negra"; p.dialogo.current_dir = OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS); p.dialogo.current_file = nombre_csv(p.ultimo_vuelo)
	for c in p.dialogo.file_selected.get_connections(): p.dialogo.file_selected.disconnect(c["callable"])
	p.dialogo.file_selected.connect(func(ruta): guardar_csv(p.ultimo_vuelo, ruta), CONNECT_ONE_SHOT)
	p.dialogo.popup_centered_ratio(0.6)
