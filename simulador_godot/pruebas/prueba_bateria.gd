extends SceneTree
## Prueba de la bateria (scripts/bateria.gd) en Godot, la misma que pruebas/prueba_bateria_web.py en el navegador: el
## Mini Dron HQ lejos de casa con la bateria justa vuelve a casa solo y aterriza alli; con la bateria critica aterriza
## donde esta (aterrizaje forzoso) y no se puede cancelar; el Entrenador 1 a fondo con la bateria casi vacia: el
## regulador corta el motor y lo avisa.
##   herramientas/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path simulador_godot --script res://pruebas/prueba_bateria.gd

const DT := 1.0 / 500
var fallos := 0
var p

func _ok(nombre: String, cond: bool, detalle := "") -> void:
	if not cond: fallos += 1
	print("  %s %s %s" % ["OK " if cond else "MAL", nombre, detalle])

func _preparar(avion: String) -> void:
	p.sesion["avion"] = avion; p.sesion["escenario"] = "libre"; p.sesion["sin_registrar"] = true
	p.empezar()
	for k in 900:
		await process_frame
		if p.pantalla_actual == "" and not p.av.is_empty() and p.modelo != null: break
	p.pantalla_actual = "prueba"; p.toasts_registro = []

func _hay(lista: Array, txt: String) -> bool: return lista.any(func(t): return String(t).contains(txt))

## El Mini a N metros de casa y h de altura, con la bateria al pct: s segundos de paso() con las palancas al centro.
func _dron(N: float, h: float, pc: float, s: float, cancelar: bool) -> Dictionary:
	var av: Dictionary = p.av
	p.lanzar(); p.modelo.despegar(av)
	for i in int(2 / DT): p.paso(DT)
	av = p.av
	av["p"] = [N, 0.0, -(p.ent.altura(N, 0) + h)]; av["posado"] = false; av["v"] = [0.0, 0.0, 0.0]; av["hold"] = null; av["despegado"] = true
	var B: Dictionary = p.modelo.B; av["bat"]["mAh"] = (1 - pc / 100) * Bateria.capacidad(B, av["bat"]); av["bat"]["P"] = 40.0
	for k in ["pitch", "yaw", "guinada", "vz"]: p.mando[k] = 0.0
	var resto = null; var i := 0
	while i < int(s / DT) and av["estado"] == "volando":
		p.paso(DT)
		if cancelar and av["batForzado"] and resto == null: p.dji_rth(); p.mando["vz"] = 1.0; resto = [-av["p"][2], av["t"]]
		if resto != null and av["t"] - resto[1] > 3: p.mando["vz"] = 0.0
		i += 1
	return { "final": String(p.vuelo["final"]) if p.vuelo != null and p.vuelo["final"] != null else "", "N": av["p"][0], "E": av["p"][1], "forzado": av["batForzado"],
			 "rth": av["batRth"], "T": p.toasts_registro.duplicate(), "subio": (-av["p"][2] - resto[0]) if resto != null else null }

func _initialize() -> void:
	p = load("res://escenas/principal.tscn").instantiate(); root.add_child(p)
	await create_timer(1.0).timeout
	await _preparar("DJI_MINI")
	var r := _dron(600, 40, 26, 200, false)
	_ok("Mini a 600 m con el 26 %: vuelve a casa solo", r["rth"] and _hay(r["T"], "justa para volver"), str(r["T"].slice(0, 3)))
	_ok("y aterriza en casa", r["final"].contains("aterrizado") and absf(r["N"]) < 3 and absf(r["E"]) < 3, "%s N %.1f E %.1f" % [r["final"], r["N"], r["E"]])
	await _preparar("DJI_MINI")
	r = _dron(300, 30, 9.9, 80, true)
	_ok("Mini al 10 %: aterrizaje forzoso donde esta", r["forzado"] and _hay(r["T"], "Aterrizaje forzoso"), str(r["T"].slice(0, 3)))
	_ok("y no se puede cancelar (ni subir)", _hay(r["T"], "no se puede cancelar") and r["subio"] != null and r["subio"] < 0.5, "subio %s" % str(r["subio"]))
	_ok("aterriza lejos de casa, donde estaba", r["final"].contains("aterrizado") and absf(r["N"] - 300) < 5, "%s N %.1f" % [r["final"], r["N"]])
	await _preparar("E3")
	p.lanzar(); var av: Dictionary = p.av
	av["p"] = [0.0, 0.0, -120.0]; av["v"] = [12.0, 0.0, 0.0]; av["q"] = Cuat.desde_euler(0, 0, 0); av["w"] = [0.0, 0.0, 0.0]
	av["bat"]["mAh"] = 0.97 * Bateria.capacidad(p.modelo.B, av["bat"]); p.mando["pitch"] = 0.0; p.mando["yaw"] = 0.0
	var i := 0
	while i < int(90 / DT) and av["estado"] == "volando" and not av["cortado"]: av["gases"] = 1.0; p.paso(DT); i += 1
	for k in int(2 / DT):
		if av["estado"] != "volando": break
		av["gases"] = 1.0; p.paso(DT)
	_ok("Entrenador 1 casi vacio a fondo: el regulador corta el motor", av["cortado"] and av["rpm"] == 0 and av["T"] == 0, "celda %.2f V, %.1f %%" % [Bateria.celda_min(p.modelo.B, av["bat"]), p.modelo.bateria_pct(av)])
	_ok("y lo avisa", _hay(p.toasts_registro, "cortado el motor") and p.hud.aviso.text.contains("Motor cortado"), str(p.toasts_registro.slice(0, 2)))
	print("RESULTADO: ", "todo bien" if fallos == 0 else "%d fallos" % fallos)
	quit(1 if fallos else 0)
