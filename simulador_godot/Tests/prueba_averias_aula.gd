extends SceneTree
## Parte Godot de aula/Tests/prueba_averias_aula.py: con el alumno del aula (--aula, --usuario, --clave) lee el estado de
## su Mini Dron HQ (las averias que le ha puesto el profesor y la de la sala), vuela con ellas (el modelo las lleva y la
## app avisa del error de brujula al armar), y en el Taller (pantalla_taller.gd) la revision las ensena y repara la
## brujula, que queda en el libro de mantenimiento del aula.

const DT := 1.0 / 500
var p
var fallos := 0

func _ok(nombre: String, cond: bool, detalle := "") -> void:
	if not cond: fallos += 1
	print("  %s %s %s" % ["OK " if cond else "MAL", nombre, detalle])

func _initialize() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1); args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	p = load("res://escenas/principal.tscn").instantiate(); root.add_child(p)
	while p.aula == null or p.pantallas.is_empty() or not p.pantallas["pAlumno"].visible: await create_timer(0.2).timeout
	p.aula.url = Aula.normalizar_url(args.get("aula", "http://127.0.0.1:8096"))
	var r: Dictionary = await p.aula.api("POST", "entrar", { "usuario": args.get("usuario", "Piloto Averias"), "clave": args.get("clave", "abcd") }, "-")
	if not r["ok"]: print("MAL no se pudo entrar en el aula: ", r["error"]); quit(1); return
	p.aula.activo = true; p.aula.pase = String(r["datos"]["pase"]); p.aula.pase_id = String(r["datos"]["alumno"]["id"]); p.app_pantallas.dentro_del_aula(r["datos"]["alumno"])
	await Desgaste.cargar(p)
	var est := Desgaste.estado("DJI_MINI")
	_ok("lee las averias del aula", (est["averias"] as Array).map(func(a): return a["c"]) == ["brujula", "gps"], str((est["averias"] as Array).map(func(a): return a["c"])))
	p.toasts_registro = []
	p.sesion["avion"] = "DJI_MINI"; p.sesion["escenario"] = "libre"
	p.app_vuelo.empezar()
	for k in 900:
		await process_frame
		if p.pantalla_actual == "" and not p.av.is_empty() and p.modelo != null: break
	p.pantalla_actual = "prueba"
	_ok("el vuelo las lleva (brujula girada 50 grados y el punto del GPS que se mueve)", p.modelo.sens != null and absf(p.modelo.sens["rumbo"] - 50 * PI / 180) < 1e-9 and p.modelo.sens["gps"] == 3.5)
	p.app_vuelo.lanzar(); p.modelo.despegar(p.av)
	_ok("la app avisa del error de brujula al armar", (p.toasts_registro as Array).any(func(t): return "Error de brújula" in t), str(p.toasts_registro))
	for i in int(20 / DT):
		p.mando["vz"] = 1.0 if i * DT < 5 else 0.0
		p.app_vuelo.paso(DT)
	p.app_vuelo.terminar_vuelo("abandonado")
	for k in 60:
		await create_timer(0.1).timeout
		if float(Desgaste.estado("DJI_MINI")["horas"]) > float(est["horas"]): break
	_ok("al acabar, suben las horas del vehiculo en el aula", float(Desgaste.estado("DJI_MINI")["horas"]) > float(est["horas"]), str(Desgaste.estado("DJI_MINI")["horas"]))
	# el Taller
	p.app_pantallas.ir_inicio(); p.app_pantallas.ir_taller(); var T: PantallaTaller = p.pantallas["pTaller"]
	await T.conectar()
	T.pestana = "revision"; T.pintar_centro(); T.revisar("app"); T.revisar("helices")
	var lineas: Array = T.vistos["app"] + T.vistos["helices"]
	_ok("el Taller ensena el error de brujula y las helices nuevas", lineas.any(func(l): return "Error de brújula" in l) and lineas.any(func(l): return l.begins_with("Hélice 2 (delantera izquierda): sin daños")), str(lineas))
	await T.reparar("brujula", true)
	var e2 := Desgaste.estado("DJI_MINI")
	_ok("repara la brujula y queda en el libro", (e2["averias"] as Array).map(func(a): return a["c"]) == ["gps"] and String(e2["libro"][-1]["texto"]) == "Calibrar la brújula", str(e2["libro"].map(func(x): return x["texto"])))
	await process_frame
	_ok("el libro se ve en la pestana", T.centro.find_child("Libro", true, false) != null)
	print("RESULTADO: ", "todo bien" if fallos == 0 else "%d fallos" % fallos)
	quit(1 if fallos else 0)
