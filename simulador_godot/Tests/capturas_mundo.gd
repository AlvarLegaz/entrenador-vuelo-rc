extends SceneTree
## Capturas del mundo real en Godot, sin la interfaz, desde las mismas vistas fijas que
## simulador_web/Tests/capturas_mundo_web.py (alrededor del CIFP Politecnico o, con --sitio=sabic, de la fabrica de SABIC; camara 3 del Mini Dron HQ), para comparar el aspecto de
## edificios, suelo y arboles con la web o antes y despues de un cambio. Necesita ventana.
## Uso (desde la carpeta del repositorio):
##   herramientas/godot/Godot_v4.7.2-stable_win64_console.exe --path simulador_godot --resolution 1280x720 --script res://Tests/capturas_mundo.gd -- --calidad=2 --fotos=<carpeta>/<prefijo>

# por sitio (--sitio=cifp, por defecto, o sabic): el trabajo que lo carga y sus vistas,
# nombre: [N, E, altura sobre el suelo, rumbo (grados), gimbal (grados, - abajo)]
const SITIOS := {
	"cifp": { "op": "op_carrera", "vistas": {
		"fachadas": [10, 6310, 18, 270, -8], "calle": [0, 6212, 2.5, 315, 3], "cifp_baja": [40, 6640, 8, 40, -8],
		"cifp_alta": [-40, 6600, 45, 35, -30], "barrio": [120, 6760, 25, 200, -15], "lejos": [0, 6650, 120, 300, -12] } },
	"sabic": { "op": "op_sabic", "vistas": {
		"sabic_salida": [10342, -4491, 4, 46, -2], "sabic_alta": [10230, -4640, 70, 40, -22], "sabic_antorcha": [10420, -4515, 22, 313, 8],
		"sabic_racks": [10395, -4470, 10, 250, -12], "sabic_lejos": [10100, -4300, 130, 330, -15] } },
}
var p

func _initialize() -> void:
	var prefijo := ""; var sitio := "cifp"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--fotos="): prefijo = a.substr(8)
		if a.begins_with("--sitio="): sitio = a.substr(8)
	var S: Dictionary = SITIOS[sitio]; var VISTAS: Dictionary = S["vistas"]; var op: String = S["op"]
	if prefijo == "" or DisplayServer.get_name() == "headless": print("MAL hace falta ventana y --fotos=<prefijo>"); quit(1); return
	p = load("res://escenas/principal.tscn").instantiate(); root.add_child(p)
	await create_timer(1.0).timeout
	p.app_pantallas.ir_operaciones(); var O = p.pantallas["pOperaciones"]; O.sel = op; O.refrescar()
	p.op_vehiculo[op] = "DJI_MINI"
	p.app_pantallas.volar_operacion(op)
	for k in 900:
		await process_frame
		if p.pantalla_actual == "" and p.ev != null and not p.av.is_empty() and p.mundo3d != null and (op != "op_carrera" or not p.mundo3d.carrera_obst.is_empty()): break
	p.mundo3d.poner_operacion({}, [0, 0])                 # solo el mundo, sin los obstaculos
	await create_timer(3.0).timeout
	p.ui.visible = false
	for nombre in VISTAS:
		var v: Array = VISTAS[nombre]
		p.pantalla_actual = "prueba"; p.pausado = true
		p.av["p"] = [float(v[0]), float(v[1]), -(p.ent.altura(v[0], v[1]) + v[2])]; p.av["v"] = [0.0, 0.0, 0.0]
		p.av["q"] = Cuat.desde_euler(0, 0, float(v[3]) * PI / 180); p.av["gimbal"] = float(v[4]); p.camara = 3
		p.pantalla_actual = ""
		for k in 20: p.avion3d.actualizar(p.av); await process_frame
		p.pantalla_actual = "prueba"
		root.get_texture().get_image().save_png(prefijo + "_" + nombre + ".png")
		print("  ", nombre)
	p.pausado = false
	print("RESULTADO: capturas hechas")
	quit(0)
