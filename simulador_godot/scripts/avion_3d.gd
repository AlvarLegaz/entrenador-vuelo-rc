class_name Avion3D
extends Node3D
## El avion en 3D a partir de la malla de sus datos (simulador/aviones/<id>.js, la misma que usa el navegador): piezas
## en ejes cuerpo NED (metros, origen en el CG) y superficies moviles que giran sobre su bisagra. Mismo montaje que
## construirAvion() en simulador/js/visor.js.

var prof: Node3D; var timon: Node3D; var alerones := []; var helice: MeshInstance3D

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
	var K: Dictionary = datos["malla"]
	var col := { "fuselaje": 0xf4f4f4, "ala": 0xffc107, "estab": 0xdddddd, "moviles": 0xd32f2f }
	if datos.has("colores"):
		for k in datos["colores"]: col[k] = int(datos["colores"][k])
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
	# disco de la helice girando (semitransparente) y cono
	helice = MeshInstance3D.new()
	var disco := CylinderMesh.new(); disco.top_radius = K["helice_r"]; disco.bottom_radius = K["helice_r"]; disco.height = 0.002
	disco.radial_segments = 24; disco.rings = 1; helice.mesh = disco
	var mh := StandardMaterial3D.new(); mh.albedo_color = Color(0.2, 0.2, 0.2, 0.25); mh.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mh.cull_mode = BaseMaterial3D.CULL_DISABLED; helice.material_override = mh
	helice.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	helice.position = Vector3(K["helice"][0], K["helice"][1], K["helice"][2]); helice.rotation = Vector3(0, 0, PI / 2); add_child(helice)
	var cono := MeshInstance3D.new(); var cm := CylinderMesh.new(); cm.top_radius = 0.0; cm.bottom_radius = 0.018; cm.height = 0.04
	cono.mesh = cm; cono.material_override = _mat(0x333333)
	cono.position = Vector3(K["helice"][0] + 0.02, 0, K["helice"][2]); cono.rotation = Vector3(0, 0, -PI / 2); add_child(cono)

## Coloca el avion y sus mandos segun el estado de la fisica.
func actualizar(av: Dictionary) -> void:
	var q: Array = av["q"]
	transform = Transform3D(Basis(ned(Cuat.rot(q, [1.0, 0.0, 0.0])), ned(Cuat.rot(q, [0.0, 1.0, 0.0])), ned(Cuat.rot(q, [0.0, 0.0, 1.0]))), ned(av["p"]))
	prof.rotation = Vector3(0, av["de"], 0)          # + = borde de fuga abajo
	timon.rotation = Vector3(0, 0, -av["dr"])        # + = borde de fuga a la derecha
	for p in alerones:
		var ang: float = p.get_meta("signo") * av["da"] + (av["de"] if p.get_meta("prof") else 0.0)
		p.basis = Basis(p.get_meta("eje"), ang)
	helice.visible = av["gases"] > 0.05
