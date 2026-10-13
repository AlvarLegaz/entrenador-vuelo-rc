class_name Avion3D
extends Node3D
## El avion en 3D a partir de la malla de sus datos (simulador/aviones/<id>.js, la misma que usa el navegador): piezas
## en ejes cuerpo NED (metros, origen en el CG) y superficies moviles que giran sobre su bisagra. Mismo montaje que
## construirAvion() en simulador/js/visor.js. Un multicoptero (malla.helices) lleva un disco horizontal por rotor y
## puede traer luces (malla.luces) que parpadean y se ven siempre del mismo tamano en pantalla, como en el navegador.
## Un cuadricoptero (tipo "cuadricoptero") no usa la malla de cajas de sus datos: lleva el modelo detallado de
## modelo_dji_3d.gd (ModeloDJI3D: cuerpo, brazos, motores, helices con disco de desenfoque y gimbal), con las mismas luces.

var prof: Node3D; var timon: Node3D; var alerones := []; var helice: Node3D; var luces := []
var fpv: ModeloFPV3D = null      # dron FPV: su modelo 3D (modelo_fpv_3d.gd, con los datos de aviones/FPV.js)
var camara_fpv := false          # con la camara FPV el dron no se dibuja (la camara va dentro del bastidor)
var dji: ModeloDJI3D            # cuadricoptero: el modelo detallado (null en los aviones)
static var _tex_luz: ImageTexture

## NED (n, e, d) -> Godot (x = este, y = arriba, z = sur). Los mismos ejes que Three en el navegador.
static func ned(p: Array) -> Vector3:
	return Vector3(p[1], -p[2], -p[0])

static func _malla(m: Dictionary) -> ArrayMesh:
	var v: Array = m["v"]; var idx: Array = m["i"]
	var pos := PackedVector3Array(); var nor := PackedVector3Array()
	for k in range(0, idx.size() - 2, 3):
		var a := Vector3(v[3 * idx[k]], v[3 * idx[k] + 1], v[3 * idx[k] + 2])
		var b := Vector3(v[3 * idx[k + 1]], v[3 * idx[k + 1] + 1], v[3 * idx[k + 1] + 2])
		var c := Vector3(v[3 * idx[k + 2]], v[3 * idx[k + 2] + 1], v[3 * idx[k + 2] + 2])
		var n := (c - a).cross(b - a).normalized()     # normal de cara (Godot: cara frontal en sentido horario)
		pos.append_array([a, b, c]); nor.append_array([n, n, n])
	var arr := []; arr.resize(Mesh.ARRAY_MAX); arr[Mesh.ARRAY_VERTEX] = pos; arr[Mesh.ARRAY_NORMAL] = nor
	var am := ArrayMesh.new(); am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return am

static func _mat(c: int) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color.hex((c << 8) | 0xff); m.cull_mode = BaseMaterial3D.CULL_DISABLED; m.roughness = 0.55
	return m

func _pieza(padre: Node3D, malla: Dictionary, color: int) -> MeshInstance3D:
	var mi := MeshInstance3D.new(); mi.mesh = _malla(malla); mi.material_override = _mat(color)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
	padre.add_child(mi); return mi

func _pivote(malla: Dictionary, eje: Array, color: int) -> Node3D:
	var p := Node3D.new(); p.position = Vector3(eje[0], eje[1], eje[2]); add_child(p)
	var mi := _pieza(p, malla, color); mi.position = -p.position
	return p

func _init(datos: Dictionary) -> void:
	if datos.get("tipo", "") == "fpv":
		prof = Node3D.new(); timon = Node3D.new(); helice = Node3D.new(); add_child(prof); add_child(timon); add_child(helice)
		fpv = ModeloFPV3D.new(self, datos); return
	var K: Dictionary = datos["malla"]
	var col := { "fuselaje": 0xf4f4f4, "ala": 0xffc107, "estab": 0xdddddd, "moviles": 0xd32f2f }
	if datos.has("colores"):
		for k in datos["colores"]: col[k] = int(datos["colores"][k])
	if datos.get("tipo", "") == "cuadricoptero":
		dji = ModeloDJI3D.new(datos); add_child(dji); helice = dji
		prof = Node3D.new(); timon = Node3D.new()
		_luces(K)
		return
	for k in ["fuselaje", "ala", "estab"]:
		if K.has(k): _pieza(self, K[k], col[k])
	for pz in K.get("piezas", []):          # piezas de otro color (franjas, ruedas, motor)
		_pieza(self, pz, int(pz["color"]))
	prof = _pivote(K["prof"], K["bisagra_prof"], int(K["prof"].get("color", col["moviles"]))) if K.has("prof") else Node3D.new()
	timon = _pivote(K["timon"], K["bisagra_timon"], int(K["timon"].get("color", col["moviles"]))) if K.has("timon") else Node3D.new()
	for a in K.get("alerones", []):
		var p := _pivote(a, a["bisagra"], int(a.get("color", col["moviles"])))
		p.set_meta("eje", Vector3(a["eje"][0], a["eje"][1], a["eje"][2]).normalized())
		p.set_meta("signo", float(a["signo"])); p.set_meta("prof", bool(a.get("prof", false)))
		alerones.append(p)
	if K.has("helices"):        # multicoptero: un disco horizontal por rotor (en ejes cuerpo el plano x-y ya es horizontal)
		helice = Node3D.new()
		for hp in K["helices"]:
			var d := _disco_helice(K["helice_r"]); d.position = Vector3(hp[0], hp[1], hp[2]); d.rotation = Vector3(PI / 2, 0, 0); helice.add_child(d)
		add_child(helice)
	else:                       # disco de la helice girando (semitransparente) y cono
		helice = _disco_helice(K["helice_r"])
		helice.position = Vector3(K["helice"][0], K["helice"][1], K["helice"][2]); helice.rotation = Vector3(0, 0, PI / 2); add_child(helice)
		var cono := MeshInstance3D.new(); var cm := CylinderMesh.new(); cm.top_radius = 0.0; cm.bottom_radius = 0.018; cm.height = 0.04
		cono.mesh = cm; cono.material_override = _mat(0x333333)
		cono.position = Vector3(K["helice"][0] + 0.02, 0, K["helice"][2]); cono.rotation = Vector3(0, 0, -PI / 2); add_child(cono)
	_luces(K)

func _luces(K: Dictionary) -> void:
	# luces (K.luces: posicion en ejes cuerpo, color y patron de parpadeo): un punto brillante de tamano fijo en pantalla
	# (sprite de tamano fijo), para que un dron de 25 cm se vea desde el puesto del piloto, y una bolita para las camaras cercanas
	for l in K.get("luces", []):
		var g := Node3D.new(); g.position = ModeloDJI3D.posicion_luz(l["p"]) if dji else Vector3(l["p"][0], l["p"][1], l["p"][2])
		g.set_meta("patron", l.get("patron", "fijo"))
		var color := Color.hex((int(l["color"]) << 8) | 0xff)
		var sp := Sprite3D.new(); sp.texture = _textura_luz(); sp.modulate = color; sp.fixed_size = true
		sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED; sp.shaded = false; sp.transparent = true; sp.double_sided = true
		sp.pixel_size = 0.01 / 32; sp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF     # se reescala cada cuadro a un tamano fijo en pixeles
		g.add_child(sp)
		var rb := 0.0026 if dji else 0.007      # en el modelo detallado, del tamano de su lente
		var bola := MeshInstance3D.new(); var esf := SphereMesh.new(); esf.radius = rb; esf.height = 2 * rb; esf.radial_segments = 8; esf.rings = 6
		var mb := StandardMaterial3D.new(); mb.albedo_color = color; mb.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		bola.mesh = esf; bola.material_override = mb; bola.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; g.add_child(bola)
		add_child(g); luces.append(g)

static func _disco_helice(r: float) -> MeshInstance3D:
	var h := MeshInstance3D.new()
	var disco := CylinderMesh.new(); disco.top_radius = r; disco.bottom_radius = r; disco.height = 0.002
	disco.radial_segments = 24; disco.rings = 1; h.mesh = disco
	var mh := StandardMaterial3D.new(); mh.albedo_color = Color(0.2, 0.2, 0.2, 0.25); mh.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mh.cull_mode = BaseMaterial3D.CULL_DISABLED; h.material_override = mh
	h.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return h

## Punto redondo con halo (32 x 32, blanco; el color lo pone el sprite), compartido: el degradado de visor.js.
static func _textura_luz() -> ImageTexture:
	if _tex_luz: return _tex_luz
	var img := Image.create_empty(32, 32, false, Image.FORMAT_RGBA8)
	for j in 32:
		for i in 32:
			var t := clampf((Vector2(i + 0.5, j + 0.5).distance_to(Vector2(16, 16)) - 2) / 14, 0, 1)
			img.set_pixel(i, j, Color(1, 1, 1, lerpf(1, 0.95, t / 0.45) if t < 0.45 else lerpf(0.95, 0, (t - 0.45) / 0.55)))
	_tex_luz = ImageTexture.create_from_image(img)
	return _tex_luz

## Coloca el avion y sus mandos segun el estado de la fisica.
func actualizar(av: Dictionary) -> void:
	var q: Array = av["q"]
	transform = Transform3D(Basis(ned(Cuat.rot(q, [1.0, 0.0, 0.0])), ned(Cuat.rot(q, [0.0, 1.0, 0.0])), ned(Cuat.rot(q, [0.0, 0.0, 1.0]))), ned(av["p"]))
	if fpv: fpv.actualizar(av, get_process_delta_time(), camara_fpv); return
	prof.rotation = Vector3(0, av["de"], 0)          # + = borde de fuga abajo
	timon.rotation = Vector3(0, 0, -av["dr"])        # + = borde de fuga a la derecha
	for p in alerones:
		var ang: float = p.get_meta("signo") * av["da"] + (av["de"] if p.get_meta("prof") else 0.0)
		p.basis = Basis(p.get_meta("eje"), ang)
	if dji: dji.actualizar(av)          # helices (palas o disco segun las rpm) y gimbal
	else: helice.visible = av["gases"] > 0.05
	if luces.is_empty(): return
	# luces: en el suelo con los motores parados, apagadas; "lento" (navegacion) 1 Hz, "estrobo" dos destellos por segundo.
	# Con fixed_size el sprite mide pixel_size * 32 por unidad de profundidad: se reescala a unos 16 px sea cual sea el zoom
	var tl := fmod(Time.get_ticks_msec() / 1000.0, 1.0); var enc: bool = av["estado"] != "en mano"
	var cam: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	var alto := get_viewport().get_visible_rect().size.y if is_inside_tree() else 900.0
	var sc := 16 * 2 * tan(deg_to_rad(cam.fov) / 2) / alto if cam else 0.01
	for l in luces:
		var pat: String = l.get_meta("patron")
		l.visible = enc and (tl < 0.5 if pat == "lento" else (tl < 0.06 or (tl > 0.15 and tl < 0.21)) if pat == "estrobo" else true)
		(l.get_child(0) as Sprite3D).pixel_size = sc / 32
