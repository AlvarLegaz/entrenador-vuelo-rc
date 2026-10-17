extends SceneTree
## Prueba de la mision 5 · Puerta en Godot (la misma que simulador_web/Tests/prueba_puertas_web.py en el navegador): las dos
## puertas de la zona 2 en orden (naranja, verde, naranja, verde). Cruzar la que no toca, por encima de los pilones o por
## fuera no cuenta; la verde se cruza de norte a sur o al reves; al acabar, el panel dice "aterrizar".
##   herramientas/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path simulador_godot --script res://Tests/prueba_puertas.gd

var fallos := 0
var p

func _ok(nombre: String, cond: bool, detalle := "") -> void:
	if not cond: fallos += 1
	print("  %s %s %s" % ["OK " if cond else "MAL", nombre, detalle])

func _estados() -> String:
	return ",".join(["puerta1", "puerta2", "puerta3", "puerta4"].map(func(k): return String(p.ev.obj[k]["estado"])))

func _cruza(a: Array, b: Array) -> void:
	p.av["p"] = b.duplicate(); p.app_vuelo._zona2(a)

func _initialize() -> void:
	p = load("res://escenas/principal.tscn").instantiate(); root.add_child(p)
	await create_timer(1.0).timeout
	p.sesion["avion"] = "DJI_MINI"; p.sesion["escenario"] = "puerta"; p.sesion["sin_registrar"] = true
	p.app_vuelo.empezar()
	for k in 900:
		await process_frame
		if p.pantalla_actual == "" and not p.av.is_empty() and p.modelo != null: break
	p.pantalla_actual = "prueba"; p.toasts_registro = []
	p.av["estado"] = "volando"; p.ev.subido = true
	var N := [[-115.0, 65.0, -10.0], [-115.0, 55.0, -10.0]]; var V := [[-130.0, -23.0, -10.0], [-140.0, -23.0, -10.0]]
	_cruza(V[0], V[1])
	_ok("la verde primero no cuenta", _estados() == "pend,pend,pend,pend" and String(p.toasts_registro[-1]).contains("ahora toca la naranja"), str(p.toasts_registro[-1]))
	_cruza(N[0], N[1])
	_ok("la naranja: primera", _estados() == "ok,pend,pend,pend" and p.ev.texto_zona2("puerta").contains("cruzar la puerta verde (1/4)"), p.ev.texto_zona2("puerta").strip_edges())
	_cruza(N[0], N[1])
	_ok("otra vez la naranja: no toca", _estados() == "ok,pend,pend,pend")
	_cruza([-130.0, -23.0, -30.0], [-140.0, -23.0, -30.0])
	_ok("la verde por encima de los pilones no cuenta", _estados() == "ok,pend,pend,pend" and String(p.toasts_registro[-1]).contains("Por encima de la puerta verde"))
	_cruza([-140.0, -23.0, -10.0], [-130.0, -23.0, -10.0])
	_ok("la verde hacia el norte: segunda", _estados() == "ok,ok,pend,pend")
	_cruza([-115.0, 55.0, -10.0], [-115.0, 65.0, -10.0])
	_ok("la naranja hacia el este: tercera", _estados() == "ok,ok,ok,pend")
	_cruza([-130.0, 5.0, -10.0], [-140.0, 5.0, -10.0])
	_ok("por fuera de la verde no cuenta", _estados() == "ok,ok,ok,pend" and String(p.toasts_registro[-1]).contains("Por fuera de la puerta verde"))
	_cruza(V[0], V[1])
	_ok("la verde: cuarta, y a aterrizar", _estados() == "ok,ok,ok,ok" and p.ev.texto_zona2("puerta").contains("aterrizar"), str(p.toasts_registro[-1]))
	_ok("los pilones verdes son solidos", p.ent.choca_pilon([-135.0, -31.0, -5.0], 0.2))
	print("RESULTADO: %s" % ("todo bien" if fallos == 0 else "%d fallos" % fallos))
	quit(1 if fallos else 0)
