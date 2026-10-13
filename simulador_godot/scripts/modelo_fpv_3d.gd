class_name ModeloFPV3D
extends RefCounted
## Modelo 3D del dron FPV (datos.modelo3d de simulador/aviones/FPV.js, el mismo que construye ModeloFPV.construir3D en
## el navegador): piezas (cajas y cilindros con su color) en ejes cuerpo NED (x adelante, y derecha, z abajo; metros,
## origen en el CG), 4 rotores de 3 palas con un disco translucido cuando giran deprisa y las luces de los brazos (fijas
## armado, parpadean desarmado). Lo cuelga de su Avion3D (raiz) y lo anima en cada cuadro (actualizar).

var raiz: Node3D
var rotores := []          # [Node3D del rotor, palas, disco, sentido]
var luces := []

const D2R := PI / 180.0

static func _mat(c: int, alfa := 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color.hex((c << 8) | 0xff); m.albedo_color.a = alfa; m.roughness = 0.55
	if alfa < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m

## Giro de una pieza como en Three (orden ZYX): primero ry sobre el eje y del cuerpo, despues rz sobre el z.
static func _giro(P: Dictionary) -> Basis:
	return Basis(Vector3(0, 0, 1), float(P.get("rz", 0.0)) * D2R) * Basis(Vector3(0, 1, 0), float(P.get("ry", 0.0)) * D2R)

func _init(r: Node3D, datos: Dictionary) -> void:
	raiz = r
	var K: Dictionary = datos["modelo3d"]
	for P in K["piezas"]:
		var mi := MeshInstance3D.new(); var b := _giro(P)
		if P["f"] == "caja":
			var bm := BoxMesh.new(); bm.size = Vector3(P["l"][0], P["l"][1], P["l"][2]); mi.mesh = bm
		else:                                   # cilindro: su eje es el z del cuerpo (CylinderMesh lo tiene en y)
			var cm := CylinderMesh.new(); cm.top_radius = P["r"]; cm.bottom_radius = P["r"]; cm.height = P["h"]; cm.radial_segments = 18; cm.rings = 1; mi.mesh = cm
			b = b * Basis(Vector3(1, 0, 0), PI / 2)
		mi.transform = Transform3D(b, Vector3(P["c"][0], P["c"][1], P["c"][2]))
		mi.material_override = _mat(int(P["col"]))
		raiz.add_child(mi)
	var R: Dictionary = K["rotor"]
	for ro in K["rotores"]:
		var n := Node3D.new(); n.position = Vector3(ro[0], ro[1], ro[2]); raiz.add_child(n)
		var s: float = ro[3]
		var palas := Node3D.new(); n.add_child(palas)
		for k in int(R["palas"]):                # pala: de r0 a r1, girada su paso sobre su eje largo
			var pg := Node3D.new(); pg.rotation = Vector3(0, 0, k * 2 * PI / R["palas"]); palas.add_child(pg)
			var pm := MeshInstance3D.new(); var bm := BoxMesh.new(); bm.size = Vector3(R["r1"] - R["r0"], R["ancho"], R["grueso"]); pm.mesh = bm
			pm.position = Vector3(0.5 * (R["r0"] + R["r1"]), 0, 0); pm.rotation = Vector3(s * R["paso_grados"] * D2R, 0, 0)
			pm.material_override = _mat(int(R["col"]), 0.8); pg.add_child(pm)
		var disco := MeshInstance3D.new(); var dm := CylinderMesh.new(); dm.top_radius = R["r1"]; dm.bottom_radius = R["r1"]; dm.height = 0.001
		dm.radial_segments = 32; dm.rings = 1; disco.mesh = dm; disco.rotation = Vector3(PI / 2, 0, 0)
		disco.material_override = _mat(int(R["col"]), R["disco_opacidad"]); disco.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		disco.visible = false; n.add_child(disco)
		rotores.append([n, palas, disco, s])
	# luces (tira de LED bajo los brazos): punto de tamano fijo en pantalla y una bolita, como las del DJI (Avion3D)
	for l in K["luces"]:
		var g := Node3D.new(); g.position = Vector3(l["p"][0], l["p"][1], l["p"][2])
		var color := Color.hex((int(l["color"]) << 8) | 0xff)
		var sp := Sprite3D.new(); sp.texture = Avion3D._textura_luz(); sp.modulate = color; sp.fixed_size = true
		sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED; sp.shaded = false; sp.transparent = true; sp.double_sided = true
		sp.pixel_size = 0.01 / 32; sp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		g.add_child(sp)
		var bola := MeshInstance3D.new(); var esf := SphereMesh.new(); esf.radius = 0.004; esf.height = 0.008; esf.radial_segments = 8; esf.rings = 6
		var mb := StandardMaterial3D.new(); mb.albedo_color = color; mb.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		bola.mesh = esf; bola.material_override = mb; bola.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; g.add_child(bola)
		raiz.add_child(g); luces.append(g)

## Cada cuadro: rotores (palas quietas o disco girando), luces (fijas armado, parpadean desarmado) y, con la camara FPV
## (camara_fpv), el dron oculto: la camara va dentro del bastidor (como animar() en el navegador).
func actualizar(av: Dictionary, dt: float, camara_fpv: bool) -> void:
	var ms: Array = av.get("motores", [0.0, 0.0, 0.0, 0.0])
	for i in rotores.size():
		var r: Array = rotores[i]; var f: float = ms[i] if i < ms.size() else 0.0; var rapido := f > 0.03
		r[2].visible = rapido; r[1].visible = not rapido
		if f > 0: r[1].rotation.z += r[3] * f * 40 * dt     # girando despacio al pararse
	var tl := fmod(Time.get_ticks_msec() / 1000.0, 1.0)
	var cam: Camera3D = raiz.get_viewport().get_camera_3d() if raiz.is_inside_tree() else null
	var alto := raiz.get_viewport().get_visible_rect().size.y if raiz.is_inside_tree() else 900.0
	var sc := 14 * 2 * tan(deg_to_rad(cam.fov) / 2) / alto if cam else 0.01
	for l in luces:
		l.visible = bool(av.get("armado", false)) or tl < 0.5
		(l.get_child(0) as Sprite3D).pixel_size = sc / 32
	raiz.visible = not camara_fpv
