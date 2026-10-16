extends SceneTree
## Parte Godot de pruebas/prueba_taller.py: con el registro que ha grabado la web (--web=<json> con el registro, su
## resumen, sus graficas y su CSV), el modo Taller (pantalla_taller.gd) da lo mismo que el de la web: el Mini con 1
## registro y sin el bipode, "Conectar y descargar" lo lista, el mismo resumen, las mismas graficas, el cursor y el
## mismo CSV; borrado de la carpeta de datos, con el alumno en el aula (--aula, --usuario, --clave), lo baja del aula.

var p
var fallos := 0

func _ok(nombre: String, cond: bool, detalle := "") -> void:
	if not cond: fallos += 1
	print("  %s %s %s" % ["OK " if cond else "MAL", nombre, detalle])

func _initialize() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1); args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var W: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args["web"]))
	var reg: Dictionary = W["reg"]
	DirAccess.make_dir_recursive_absolute(RegistroVuelo.DIR.path_join("DJI_MINI"))
	var ruta := RegistroVuelo.DIR.path_join("DJI_MINI").path_join(String(reg["id"]) + ".json")
	var fa := FileAccess.open(ruta, FileAccess.WRITE); fa.store_string(JSON.stringify(reg)); fa.close()
	p = load("res://escenas/principal.tscn").instantiate(); root.add_child(p)
	while p.aula == null or p.pantallas.is_empty() or not p.pantallas["pAlumno"].visible: await create_timer(0.2).timeout
	p.aula.url = Aula.normalizar_url(args.get("aula", "http://127.0.0.1:8097"))
	var r: Dictionary = await p.aula.api("POST", "entrar", { "usuario": args.get("usuario", "Piloto Taller"), "clave": args.get("clave", "abcd") }, "-")
	if not r["ok"]: print("MAL no se pudo entrar en el aula: ", r["error"]); quit(1); return
	p.aula.activo = true; p.aula.pase = String(r["datos"]["pase"]); p.aula.pase_id = String(r["datos"]["alumno"]["id"]); p.dentro_del_aula(r["datos"]["alumno"])
	p.ir_inicio(); p.sesion["avion"] = "DJI_MINI"
	var T: PantallaTaller = p.pantallas["pTaller"]
	p.ir_taller(); await process_frame
	_ok("se abre el Taller con el Mini", p.pantalla_actual == "pTaller" and T.avion == "DJI_MINI")
	_ok("sin el bipode", not T.ids().has("BIPODE") and T.ids().has("DJI_MINI") and T.ids().has("E3"), str(T.ids()))
	var txt := []
	for b in T.lista_veh.get_children(): for l in b.get_child(0).get_children(): txt.append(l.text)
	_ok("el Mini, con 1 registro en este ordenador", txt.has("1 registro en este ordenador"), str(txt))
	_ok("la ficha de su bateria", T.bateria_texto("DJI_MINI").begins_with("Batería Li-ion 2S de 2250 mAh"), T.bateria_texto("DJI_MINI"))
	await T.conectar()
	_ok("conectar y descargar lista el vuelo (de este ordenador, aunque tambien este en el aula)", T.lista.size() == 1 and not T.lista[0].get("_aula", false), str(T.lista.size()))
	await T.ver(T.lista[0]); await process_frame
	_ok("el MISMO resumen que la web", JSON.stringify(PantallaTaller.resumen(T.reg)) == JSON.stringify(W["resumen"]), str(PantallaTaller.resumen(T.reg)))
	var pan := PantallaTaller.paneles(T.reg).map(func(x): return [x[0], (x[1] as Array).map(func(s): return s[0])])
	_ok("las MISMAS graficas que la web", JSON.stringify(pan) == JSON.stringify(W["paneles"]), str(pan.map(func(x): return x[0])))
	await process_frame
	var mm := InputEventMouseMotion.new(); mm.position = Vector2(T.grafica.size.x / 2, 80); T.grafica._gui_input(mm); T.grafica.queue_redraw()
	await process_frame; await process_frame
	var lec: String = T.lectura.get_parsed_text()
	_ok("el cursor da los valores en ese momento", "bateria pct" in lec and "celda2 V" in lec and "altura despegue m" in lec, lec.substr(0, 140))
	var fcsv := OS.get_cache_dir().path_join("prueba_taller.csv")
	T.exportar(fcsv)
	var bytes := FileAccess.get_file_as_bytes(fcsv); DirAccess.remove_absolute(fcsv)
	_ok("el MISMO CSV que la web (byte a byte, con la marca UTF-8)", bytes == String(W["csv"]).to_utf8_buffer(), "%d / %d bytes" % [bytes.size(), String(W["csv"]).to_utf8_buffer().size()])
	_ok("con su nombre", T.nombre_csv(T.reg).begins_with("registro_DJI_MINI_"), T.nombre_csv(T.reg))
	# borrado de la carpeta de datos: lo baja del aula
	DirAccess.remove_absolute(ruta)
	p.ir_inicio(); p.ir_taller(); await process_frame
	await T.conectar()
	_ok("borrado de este ordenador, conectar lo baja del aula", T.lista.size() == 1 and T.lista[0].get("_aula", false))
	await T.ver(T.lista[0]); await process_frame
	_ok("y su detalle es el mismo", JSON.stringify(PantallaTaller.resumen(T.reg)) == JSON.stringify(W["resumen"]))
	print("RESULTADO: ", "todo bien" if fallos == 0 else "%d fallos" % fallos)
	quit(1 if fallos else 0)
