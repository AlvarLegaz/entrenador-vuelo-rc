extends SceneTree
## Prueba de la pantalla de acceso contra un servidor del aula en marcha (aula/servidor_aula.py): usuario nuevo (se
## crea), Perfil -> progreso -> Cerrar sesion, contrasena mala, contrasena buena y sin conexion.
## OJO: entrar guarda la direccion y el usuario en user://aula.cfg: copiar ese fichero antes y restaurarlo despues.
## Uso (necesita ventana):
##   herramientas/godot/Godot_v4.7.2-stable_win64_console.exe --path simulador_godot --script res://pruebas/prueba_acceso.gd -- --aula=http://127.0.0.1:8080 --foto=acceso.png

var p: Node
var fallos := 0

func _ok(nombre: String, cond: bool, detalle := "") -> void:
	print(("OK   " if cond else "MAL  ") + nombre + ("  " + detalle if detalle != "" else ""))
	if not cond: fallos += 1

func _espera(pantalla: String, s := 10.0) -> bool:
	var t := 0.0
	while p.pantalla_actual != pantalla and t < s: await create_timer(0.1).timeout; t += 0.1
	return p.pantalla_actual == pantalla

func _initialize() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1); args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	p = load("res://escenas/principal.tscn").instantiate(); root.add_child(p)
	while p.aula == null or p.pantallas.is_empty() or not p.pantallas["pAlumno"].visible: await create_timer(0.2).timeout
	_ok("arranca en la pantalla de acceso", p.pantalla_actual == "pAlumno")
	var A: PantallaPilotos = p.pantallas["pAlumno"]
	var usuario := "Godot %d" % (Time.get_unix_time_from_system() as int % 100000)
	A.e_url.text = args.get("aula", "127.0.0.1:8080"); A.e_usuario.text = usuario; A.e_clave.text = "clave1"
	A._entrar(false)
	var t := 0.0
	while not p.modal["raiz"].visible and t < 8: await create_timer(0.1).timeout; t += 0.1
	_ok("usuario nuevo: pregunta si se crea", p.modal["raiz"].visible, p.modal["titulo"].text)
	p.modal["si"].pressed.emit()
	_ok("dentro del aula", await _espera("pInicio") and p.sesion["alumno"] != null and p.aula.activo, A.err.text)
	var I = p.pantallas["pInicio"]
	_ok("el inicio muestra el usuario", I.perfil_nombre.text == usuario and I.perfil_modo.text.begins_with("online"), I.perfil_nombre.text + " | " + I.perfil_modo.text)
	_ok("multijugador posible", p.multi_posible())
	p.ir_perfil(); await _espera("pProgreso"); await create_timer(1.0).timeout
	_ok("Perfil -> progreso con Cerrar sesión", p.pantallas["pProgreso"].b_cerrar.visible)
	p.cerrar_sesion()
	_ok("cerrar sesión -> acceso", await _espera("pAlumno") and p.sesion["alumno"] == null and not p.aula.activo, A.err.text)
	_ok("recuerda el usuario y la dirección", A.e_usuario.text == usuario and A.e_url.text == Aula.normalizar_url(args.get("aula", "127.0.0.1:8080")), A.e_url.text)
	A.e_clave.text = "mala"; await A._entrar(false)
	_ok("contraseña mala", p.pantalla_actual == "pAlumno" and A.err.text.contains("incorrecta"), A.err.text)
	A.e_clave.text = "clave1"; await A._entrar(false)
	_ok("contraseña buena", p.pantalla_actual == "pInicio" and p.sesion["alumno"] != null)
	p.cerrar_sesion(); await _espera("pAlumno")
	A.e_url.text = "127.0.0.1:8099"; A.e_clave.text = "clave1"; await A._entrar(false)
	_ok("servidor apagado: lo dice", A.err.text.begins_with("No se puede conectar"), A.err.text)
	p.salir_del_aula(); p.ir_inicio()
	_ok("sin conexión", p.pantalla_actual == "pInicio" and I.perfil_nombre.text == "Sin conexión" and not p.multi_posible(), I.perfil_modo.text)
	p.ir_perfil(); _ok("Perfil sin conexión -> acceso", p.pantalla_actual == "pAlumno")
	if args.has("foto"):
		A.refrescar("Sesión de %s cerrada." % usuario); await create_timer(0.5).timeout
		root.get_viewport().get_texture().get_image().save_png(args["foto"])
	print("FALLOS ", fallos)
	quit(1 if fallos else 0)
