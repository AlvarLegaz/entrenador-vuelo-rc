extends SceneTree
## Prueba del modo de realidad virtual (scripts/modo_vr.gd) sin gafas: con una cabeza y unos mandos simulados
## (ModoVR.para_pruebas), el Mini Dron HQ en el campo del club con la fisica de verdad: el cabeceo de la cabeza mueve el
## gimbal (+10 a -89), al girar la cabeza el dron gira hasta mirar hacia alli y la vista sigue a la cabeza, las palancas
## de los mandos son la emisora (modo 2) y la camara 1 pone al piloto de pie en el campo. Sin gafas no hay modo VR.
##   herramientas/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path simulador_godot --script res://../simulador_pico/Tests/prueba_vr.gd

var fallos := 0
var p

func _ok(nombre: String, cond: bool, detalle := "") -> void:
	if not cond: fallos += 1
	print("  %s %s %s" % ["OK " if cond else "MAL", nombre, detalle])

func _cabeza(v: ModoVR, cabeceo: float, giro: float) -> void:       # grados; giro + = a la derecha
	v.cabeza.transform = Transform3D(Basis.from_euler(Vector3(deg_to_rad(cabeceo), deg_to_rad(-giro), 0), EULER_ORDER_YXZ), Vector3(0, 1.6, 0))

func _esperar(s: float) -> void:
	var t := Time.get_ticks_msec() + int(s * 1000)
	while Time.get_ticks_msec() < t: await process_frame

func _rumbo() -> float: return rad_to_deg(Cuat.euler(p.av["q"])[2])

func _initialize() -> void:
	p = load("res://escenas/principal.tscn").instantiate(); root.add_child(p)
	await create_timer(1.0).timeout
	_ok("sin gafas no hay modo VR", p.vr == null)
	p.sesion["escenario"] = "libre"; p.sesion["avion"] = "DJI_MINI"; p.sesion["sin_registrar"] = true
	p.app_vuelo.empezar()
	for k in 900:
		await process_frame
		if p.pantalla_actual == "" and not p.av.is_empty() and p.modelo != null: break
	var v := ModoVR.para_pruebas(p); p.vr = v
	_ok("el Mini empieza con su camara (la 3)", p.camara == 3, str(p.camara))
	_cabeza(v, 0, 0)
	v._boton("ax_button", true)                     # A: despegar
	await _esperar(5.0)
	_ok("A despega el dron", p.av.get("estado", "") == "volando" and not p.av.get("posado", true) and float(p.av.get("agl", 0)) > 0.8, "agl %.1f" % float(p.av.get("agl", 0)))
	for c in [[-45.0, -45.0], [30.0, 10.0], [-89.9, -89.0], [-20.0, -20.0]]:
		_cabeza(v, c[0], 0); await _esperar(0.2)
		_ok("cabeza a %.0f grados: gimbal a %.0f" % [c[0], c[1]], absf(float(p.av["gimbal"]) - c[1]) < 0.6, "%.1f" % float(p.av["gimbal"]))
	var r0 := _rumbo()
	_cabeza(v, -10, 90); await _esperar(4.0)
	var dr := wrapf(_rumbo() - r0, -180, 180)
	_ok("girar la cabeza 90 grados a la derecha: el dron gira hasta alli", absf(dr - 90) < 6, "%.1f grados" % dr)
	var fw: Vector3 = -v.cabeza.global_transform.basis.z
	_ok("y la vista mira hacia donde mira la cabeza (el rumbo del dron)", absf(wrapf(rad_to_deg(ModoVR.rumbo_de(fw)) - _rumbo(), -180, 180)) < 6, "%.1f" % rad_to_deg(ModoVR.rumbo_de(fw)))
	_ok("la cabeza esta en la camara del dron", v.cabeza.global_position.distance_to(p.cam.global_position) < 0.05, "%.2f m" % v.cabeza.global_position.distance_to(p.cam.global_position))
	var r1 := _rumbo()
	v.izq.set_meta("primary", Vector2(0.5, 0)); await _esperar(1.0); v.izq.set_meta("primary", Vector2.ZERO); await _esperar(2.0)
	_ok("la palanca izquierda de lado gira la vista y el dron la sigue", wrapf(_rumbo() - r1, -180, 180) > 20, "%.1f grados" % wrapf(_rumbo() - r1, -180, 180))
	v.der.set_meta("primary", Vector2(0.3, 1.0)); v.izq.set_meta("primary", Vector2(0, 1.0)); await _esperar(0.2)
	_ok("palanca derecha adelante: cabeceo adelante; de lado: alabeo", is_equal_approx(float(p.mando["pitch"]), -1.0) and is_equal_approx(float(p.mando["yaw"]), 0.3), "%s %s" % [p.mando["pitch"], p.mando["yaw"]])
	_ok("palanca izquierda arriba: sube", float(p.mando["vz"]) == 1.0, str(p.mando["vz"]))
	v.der.set_meta("primary", Vector2.ZERO); v.izq.set_meta("primary", Vector2.ZERO)
	p.camara = 1; _cabeza(v, 0, 0); await _esperar(0.3)
	var pie: Vector3 = p.vista.base + Vector3(1.5, 0, 2)
	_ok("camara 1: el piloto de pie en el campo (la cabeza a su altura)", v.origen.global_position.distance_to(pie) < 0.01 and absf(v.cabeza.global_position.y - pie.y - 1.6) < 0.01, str(v.origen.global_position))
	var al_dron := (Avion3D.ned(p.av["p"]) - v.cabeza.global_position)
	_ok("y de cara al dron al cambiar de camara", absf(wrapf(rad_to_deg(ModoVR.rumbo_de(-v.cabeza.global_transform.basis.z) - ModoVR.rumbo_de(al_dron)), -180, 180)) < 3)
	_ok("el panel de la mano dice altura y distancia", v.panel.text.contains("Altura") and v.panel.text.contains("distancia"), v.panel.text.split("\n")[1] if v.panel.text.contains("\n") else v.panel.text)
	p.poner_toast("Aviso de prueba"); v._t_panel = 0; await _esperar(0.3)
	_ok("y los avisos de la app (bateria, averias, fotos)", v.panel.text.contains("Aviso de prueba"), v.panel.text)
	v._boton("by_button", true); await _esperar(0.2)
	_ok("B cambia de camara", p.camara == 2, str(p.camara))
	var h0: float = float(Desgaste.estado(p.sesion["avion"])["horas"])
	p.app_vuelo.desgaste_tras_vuelo(p.vuelo, "aterrizado")
	var h1: float = float(Desgaste.estado(p.sesion["avion"])["horas"])
	_ok("en las gafas el vehiculo no se desgasta (aun no hay Taller en VR)", h1 == h0, "%.3f -> %.3f h" % [h0, h1])
	print("RESULTADO: ", "todo bien" if fallos == 0 else "%d fallos" % fallos)
	quit(1 if fallos else 0)
