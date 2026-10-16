extends SceneTree
## Parte Godot de pruebas/prueba_registros.py: entra en el aula (--aula, --usuario, --clave), vuela el Mini Dron HQ
## 25 s (sube, avanza, un aviso en pantalla) y termina el vuelo; el registro de vuelo (registro_vuelo.gd) queda en la
## carpeta de datos y se envia al aula. Escribe REGISTRO <id> <muestras> <columnas> y COLUMNAS <...> por la salida.

const DT := 1.0 / 500
var p

func _initialize() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1); args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	p = load("res://escenas/principal.tscn").instantiate(); root.add_child(p)
	while p.aula == null or p.pantallas.is_empty() or not p.pantallas["pAlumno"].visible: await create_timer(0.2).timeout
	p.aula.url = Aula.normalizar_url(args.get("aula", "http://127.0.0.1:8098"))
	var r: Dictionary = await p.aula.api("POST", "entrar", { "usuario": args.get("usuario", "Prueba Godot"), "clave": args.get("clave", "prueba"), "crear": true }, "-")
	if not r["ok"]: r = await p.aula.api("POST", "entrar", { "usuario": args.get("usuario", "Prueba Godot"), "clave": args.get("clave", "prueba") }, "-")
	if not r["ok"]: print("MAL no se pudo entrar en el aula: ", r["error"]); quit(1); return
	p.aula.activo = true; p.aula.pase = String(r["datos"]["pase"]); p.aula.pase_id = String(r["datos"]["alumno"]["id"]); p.dentro_del_aula(r["datos"]["alumno"])
	p.sesion["avion"] = "DJI_MINI"; p.sesion["escenario"] = "libre"
	p.empezar()
	for k in 900:
		await process_frame
		if p.pantalla_actual == "" and not p.av.is_empty() and p.modelo != null: break
	p.pantalla_actual = "prueba"
	p.lanzar(); p.modelo.despegar(p.av)
	for i in int(25 / DT):
		p.mando["vz"] = 1.0 if i * DT < 6 else 0.0; p.mando["pitch"] = -0.6 if i * DT > 8 else 0.0
		p.paso(DT)
		if i == int(12 / DT): p.poner_toast("Aviso de prueba del registro")
	var id: String = p.vuelo["id"]
	p.terminar_vuelo("abandonado")
	for k in 100: await create_timer(0.1).timeout          # que se envie al aula
	var reg := RegistroVuelo.leer("DJI_MINI", id)
	print("REGISTRO %s %d %d %d" % [id, (reg.get("filas", []) as Array).size(), (reg.get("columnas", []) as Array).size(), (reg.get("eventos", []) as Array).size()])
	print("COLUMNAS " + ",".join(PackedStringArray(reg.get("columnas", []))))
	var csv := RegistroVuelo.csv(reg); var lineas := csv.split("\n", false)
	print("CSV %d %s" % [lineas.size(), "aviso de prueba" in csv.to_lower()])
	print("PENDIENTES %d" % RegistroVuelo._pendientes().size())
	quit(0)
