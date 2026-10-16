class_name ModoVR extends Node3D
## Gafas de realidad virtual autonomas (OpenXR: Pico 4, Pico Neo 3 y otras). Si al arrancar hay unas gafas, principal.gd
## crea este nodo: la imagen va a las gafas y el vuelo empieza directamente (todavia sin menus en VR). Las camaras:
##  - 1, el piloto de pie en el campo: la cabeza se mueve de verdad (seguimiento de 6 grados) para seguir al avion o dron;
##  - 3 del dron con gimbal (Mini Dron HQ, Inspector): como las gafas de dron con seguimiento de cabeza. La imagen sigue a
##    la cabeza al instante; el cabeceo de la cabeza inclina el gimbal (+10 a -89 grados) y el dron gira, a su velocidad,
##    hasta mirar hacia donde mira la cabeza (asi las fotos valen igual que en la pantalla: rumbo del dron + gimbal). La
##    palanca izquierda de lado gira la vista (y el dron la sigue);
##  - las demas (persecucion, FPV, a bordo), la camara de la pantalla con la cabeza libre.
## Mandos de las gafas como emisora en modo 2: izquierda gas (o subir y bajar) y guinada, derecha cabeceo y alabeo.
## A: armar o despegar · B: cambiar de camara · gatillo derecho: foto · X: volver a casa · Y: empezar de nuevo ·
## agarre izquierdo: poner la vista de frente. Un panel en la mano izquierda da altura, distancia, velocidad y avisos.

var p                                  # principal.gd
var origen: Node3D                     # XROrigin3D
var cabeza: Node3D                     # XRCamera3D (en las pruebas, un Node3D que hace de cabeza)
var izq: Node3D                        # XRController3D (en las pruebas, Node3D con las palancas en metadatos)
var der: Node3D
var panel: Label3D
var activo := false
var _cam_ant := -1
var _yaw_vista := 0.0                  # rumbo (Godot, radianes) del origen: hacia donde mira la vista con la cabeza al frente
var _t_panel := 0.0
var _t_fin := -1.0                     # tras el final de un vuelo, segundos hasta empezar otro

## Si hay unas gafas OpenXR en marcha, crea el modo VR bajo el nodo principal y lo devuelve; si no, null.
static func iniciar(principal) -> ModoVR:
	var xr := XRServer.find_interface("OpenXR")
	if xr == null or not xr.is_initialized(): return null
	principal.get_viewport().use_xr = true
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)      # el ritmo lo marcan las gafas
	var cx := XRCamera3D.new(); cx.near = 0.05; cx.far = 16000.0
	var ci := XRController3D.new(); ci.tracker = "left_hand"; var cd := XRController3D.new(); cd.tracker = "right_hand"
	var v := _crear(principal, XROrigin3D.new(), cx, ci, cd)
	cx.current = true
	cd.button_pressed.connect(func(b: String): v._boton(b, true))
	ci.button_pressed.connect(func(b: String): v._boton(b, false))
	return v

## Para las pruebas (pruebas/prueba_vr.gd), sin gafas: la cabeza y los mandos son nodos que mueve la prueba (las
## palancas, en el metadato "primary" de cada mando).
static func para_pruebas(principal) -> ModoVR:
	return _crear(principal, Node3D.new(), Node3D.new(), Node3D.new(), Node3D.new())

static func _crear(principal, o: Node3D, c: Node3D, i: Node3D, d: Node3D) -> ModoVR:
	var v := ModoVR.new(); v.p = principal; v.name = "ModoVR"; principal.add_child(v)
	v.origen = o; v.cabeza = c; v.izq = i; v.der = d
	v.add_child(o); o.add_child(c); o.add_child(i); o.add_child(d)
	for m in [i, d]: m.add_child(v._mando_visible())
	v.panel = Label3D.new(); v.panel.font_size = 40; v.panel.pixel_size = 0.0005; v.panel.outline_size = 12
	v.panel.no_depth_test = true; v.panel.billboard = BaseMaterial3D.BILLBOARD_ENABLED      # siempre de cara: se lee alzando la mano
	v.panel.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT; v.panel.position = Vector3(0.0, 0.09, -0.02)
	i.add_child(v.panel)
	v.activo = true
	return v

func _mando_visible() -> Node3D:      # un mando como los de Pico: empunadura gris oscura y el anillo de seguimiento
	var n := Node3D.new(); var mt := StandardMaterial3D.new(); mt.albedo_color = Color(0.13, 0.13, 0.15); mt.roughness = 0.6
	var e := MeshInstance3D.new(); var c := CapsuleMesh.new(); c.radius = 0.018; c.height = 0.11; e.mesh = c; e.material_override = mt
	e.rotation = Vector3(deg_to_rad(-60), 0, 0); e.position = Vector3(0, -0.035, 0.03); n.add_child(e)
	var a := MeshInstance3D.new(); var t := TorusMesh.new(); t.inner_radius = 0.034; t.outer_radius = 0.044; a.mesh = t; a.material_override = mt
	a.rotation = Vector3(deg_to_rad(20), 0, 0); a.position = Vector3(0, 0.015, -0.01); n.add_child(a)
	return n

## Rumbo NED (radianes, 0 norte, + hacia el este) de un vector de Godot (x este, z sur).
static func rumbo_de(f: Vector3) -> float: return atan2(f.x, -f.z)

## Botones de los mandos (acciones del mapa de OpenXR por defecto de Godot).
func _boton(b: String, derecho: bool) -> void:
	if p.av.is_empty() or p.pantalla_actual != "": return
	match [b, derecho]:
		["ax_button", true]:
			if p.es_dron() and not p.es_fpv(): p.dji_despegar()
			else: p.lanzar()
		["by_button", true]: p.camara = p.camara % 3 + 1
		["trigger_click", true]: if p.es_dron() and not p.es_fpv(): p.dji_foto()
		["ax_button", false]: if p.es_dron() and not p.es_fpv(): p.dji_rth()
		["by_button", false]: p.empezar()
		["grip_click", false]: _cam_ant = -1          # al volver a colocar la vista queda de frente

## Lee los mandos de las gafas como una emisora (en lugar de _leer_mando con el mando de consola). Devuelve true.
func leer_mandos(dt: float) -> bool:
	var L := _palanca(izq); var R := _palanca(der)
	var m: Dictionary = p.mando
	m["pitch"] = -R.y; m["yaw"] = R.x; m["pitchObj"] = m["pitch"]; m["yawObj"] = m["yaw"]
	var cuad: bool = (p.es_dron() and not p.es_fpv()) or p.es_bipode()
	var con_cabeza := _sigue_cabeza()
	if con_cabeza:                           # la palanca de lado gira la vista; el dron la sigue (actualizar)
		_yaw_vista -= L.x * 1.6 * dt
	else:
		m["guinada"] = L.x; m["guinadaObj"] = L.x
	if cuad: m["vz"] = L.y; m["vzObj"] = L.y
	elif not p.av.is_empty() and not p.av.get("motorRoto", false): p.av["gases"] = clampf(p.av["gases"] + L.y * 0.7 * dt, 0, 1)
	return true

static func _palanca(c: Node3D) -> Vector2:
	return (c as XRController3D).get_vector2("primary") if c is XRController3D else c.get_meta("primary", Vector2.ZERO)

func _sigue_cabeza() -> bool:
	return p.camara == 3 and not p.av.is_empty() and p.es_dron() and not p.es_fpv() and p.av.has("gimbal")

## Cada fotograma, despues de _camara() de principal (que deja en p.cam la camara de la pantalla): coloca el origen de
## las gafas segun la camara, y con la del dron mueve el gimbal y el rumbo del dron con la cabeza. Tambien el panel.
func actualizar(dt: float) -> void:
	if p.av.is_empty() or p.modelo == null: return
	var h := cabeza.transform                     # la cabeza respecto al origen
	var yaw_cab := rumbo_de(-h.basis.z)           # rumbo de la cabeza respecto al origen (NED)
	if p.camara != _cam_ant:                      # al cambiar de camara (o al recentrar), la vista queda de frente
		_cam_ant = p.camara
		var objetivo: float
		if p.camara == 1: objetivo = rumbo_de(Avion3D.ned(p.av["p"]) - (p.vista.base + Vector3(1.5, 1.7, 2)))
		elif _sigue_cabeza(): objetivo = Cuat.euler(p.av["q"])[2]
		else: objetivo = rumbo_de(-p.cam.global_transform.basis.z)
		_yaw_vista = -(objetivo - yaw_cab)        # Godot gira al reves que el rumbo
	var B := Basis(Vector3.UP, _yaw_vista)
	if p.camara == 1:                              # el piloto de pie en el campo: la cabeza se mueve de verdad
		origen.global_transform = Transform3D(B, p.vista.base + Vector3(1.5, 0, 2))
	else:                                          # la cabeza en el sitio de la camara (sin moverse con el cuerpo)
		origen.global_transform = Transform3D(B, p.cam.global_position - B * h.origin)
	if _sigue_cabeza():
		var f := (B * h.basis) * Vector3.FORWARD
		p.av["gimbal"] = clampf(rad_to_deg(asin(clampf(f.y, -1, 1))), -89.0, 10.0)
		var err := wrapf(rumbo_de(f) - Cuat.euler(p.av["q"])[2], -PI, PI)
		p.mando["guinada"] = clampf(err * 2.5, -1, 1); p.mando["guinadaObj"] = p.mando["guinada"]
	_t_panel -= dt
	if _t_panel <= 0: _t_panel = 0.2; _pintar_panel()

func _pintar_panel() -> void:
	var av: Dictionary = p.av; var t := Avion3D.ned(av["p"]); var d := Vector2(t.x - p.vista.base.x, t.z - p.vista.base.z).length()
	var v: Array = av.get("v", [0, 0, 0]); var vel := Vector3(v[0], v[1], v[2]).length()
	var txt := "%s · cámara %d\nAltura %.0f m · distancia %.0f m · %.1f m/s" % [p.modelo.datos.get("nombre", p.sesion["avion"]), p.camara, float(av.get("agl", 0.0)), d, vel]
	if _sigue_cabeza(): txt += "\nGimbal %.0f°" % float(av["gimbal"])
	if p.modelo.has_method("bateria_pct") and av.has("Wh"): txt += " · batería %.0f %%" % p.modelo.bateria_pct(av)
	if p.hud != null and p.hud.aviso.text != "": txt += "\n" + p.hud.aviso.text
	txt += "\nA armar/despegar · B cámara · gatillo foto · X casa · Y empezar"
	panel.text = txt

## Con una pantalla de la interfaz delante (el resultado de un vuelo...), que en VR todavia no se ve: avisa en el panel y
## a los 4 s empieza otro vuelo.
func en_pantalla(dt: float) -> void:
	if _t_fin < 0: _t_fin = 4.0; panel.text = "Vuelo terminado.\nEmpieza otro en unos segundos…"
	_t_fin -= dt
	if _t_fin <= 0: _t_fin = -1.0; p.empezar()
