extends SceneTree
## Prueba del UAV (Cernicalo XM-7) en el simulador Godot entero, como sim_ap de la web: sale de la cabecera 05R de San
## Javier, arranca (L), despegue automatico, crucero, ir a punto (lo que haria un clic en el mapa) y aterrizaje automatico
## hasta pararse en la pista. Comprueba tambien que el UAV no sale en los entrenamientos de lanzar a mano.
## Uso (desde la carpeta del repositorio):
##   herramientas/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path simulador_godot --script res://pruebas/prueba_uav.gd

const DT := 1.0 / 500
var fallos := 0

func _ok(nombre: String, cond: bool, detalle := "") -> void:
	if not cond: fallos += 1
	print("  %s %s %s" % ["OK " if cond else "MAL", nombre, detalle])

func _initialize() -> void:
	var p = load("res://escenas/principal.tscn").instantiate(); root.add_child(p)
	await create_timer(1.0).timeout
	_ok("el XM-7 es un UAV", Escenarios.vehiculo_de("XM7") == "uav")
	_ok("y no sale en los entrenamientos de avion", not Escenarios.misiones_de("uav").has("primer_vuelo") and not Escenarios.misiones_de("avion").is_empty())
	p.sesion["avion"] = "XM7"; p.sesion["escenario"] = "libre_cartagena"; p.empezar()
	for k in 600:
		await process_frame
		if p.pantalla_actual == "" and not p.av.is_empty(): break
	p.pantalla_actual = "prueba"
	var P = p.pista_actual(); var c: Dictionary = p._casa(); var e: Array = Cuat.euler(p.av["q"])
	_ok("sale de la cabecera de la pista, hacia 046", P != null and absf(e[2] * 180 / PI - 45.86) < 0.1 and absf(c["N"] - 17163.3) < 1, "(%s, rumbo %.1f)" % [str(c), e[2] * 180 / PI])
	_ok("sobre sus ruedas", absf(p.av["agl"] - 0.88) < 0.05 if p.av.has("agl") else true)
	p.lanzar(); p.quitar_freno_aparc(); p.uav_poner("DESPEGUE")
	_ok("despegue automatico", p.piloto.modo == "DESPEGUE")
	var fin := ""; var modos := []
	for i in int(800 / DT):
		var t: float = p.av["t"]
		if absf(t - 100) < DT / 2: p.uav_poner("PUNTO", [12000.0, 24000.0])
		if absf(t - 330) < DT / 2: p.uav_poner("ATERRIZAJE")
		p.paso(DT)
		if not modos.has(p.piloto.modo): modos.append(p.piloto.modo)
		if p.av["estado"] != "volando": fin = String(p.vuelo["final"]) if p.vuelo != null else String(p.av["estado"]); break
	var dt_: Array = p.piloto.eje_pista(p.av["p"][0], p.av["p"][1])
	_ok("despega, va al punto y aterriza solo en la pista", fin == "aterrizado" and dt_[0] > 0 and dt_[0] < 2311 and absf(dt_[1]) < 10,
		"(final '%s', en la pista a %.0f m del umbral y %.1f m del eje; modos %s)" % [fin, dt_[0], dt_[1], str(modos)])
	print("RESULTADO: ", "todo bien" if fallos == 0 else "%d fallos" % fallos)
	quit(1 if fallos else 0)
