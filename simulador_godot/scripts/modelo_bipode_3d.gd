class_name ModeloBipode3D
extends Node3D
## El bipode en 3D: traduccion de ModeloBipode.construir3D (simulador_web/js/bipode.js). Las mallas vienen hechas en los
## datos (datos/vehiculos/BIPODE.js, generadas por analisis/bipode/generar_bipode.py): aqui solo se decodifican
## (18 bytes por vertice: posicion int16 x3 en 0,1 mm NED desde el pivote de la pieza, normal int8 x3, material,
## curvatura, oclusion, altura, relleno y uv uint16 x2) y se montan las piezas con sus pivotes. El sombreado es el comun
## (DATOS.modelo3d.sombreador, el mismo texto que usa el navegador) con la tabla de materiales; recibe la posicion y la
## normal en NED de la pieza (como en el navegador) para que el desgaste caiga en el mismo sitio.
## Ejes: como en Avion3D, dentro del vehiculo todo va en ejes cuerpo NED (el nodo del vehiculo pasa de NED a Godot): las
## mallas, los pivotes y los giros de las piezas son los mismos numeros que en el navegador.

static var _mallas := {}
static var _material: ShaderMaterial = null

var datos: Dictionary
var nodos := {}
var piv := {}
var tabla: Array
var _fogo: Node3D
var _luz_fogo: OmniLight3D
var _n_disp := -1
var _t_fogo := 0.0

static func ned(p: Array) -> Vector3: return Vector3(p[1], -p[2], -p[0])      # NED del mundo -> Godot (camaras)
static func v3(p: Array) -> Vector3: return Vector3(p[0], p[1], p[2])

func _init(d: Dictionary) -> void:
	datos = d
	var K: Dictionary = d["modelo3d"]
	for pz in K["piezas"]: piv[pz["nombre"]] = pz["pivote"]
	var mat := material(K); var M := mallas(K)
	for pz in K["piezas"]:
		var n := Node3D.new(); var pp: Array = piv[pz["padre"]] if String(pz["padre"]) != "" else [0.0, 0.0, 0.0]
		n.position = v3([pz["pivote"][0] - pp[0], pz["pivote"][1] - pp[1], pz["pivote"][2] - pp[2]])
		var mi := MeshInstance3D.new(); mi.mesh = M[pz["nombre"]]; mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON; n.add_child(mi)
		(nodos[pz["padre"]] if String(pz["padre"]) != "" else self).add_child(n); nodos[pz["nombre"]] = n
	tabla = K["paso"]["tabla"]
	# fogonazo en la boca del cañon: destello y luz que parpadean al disparar
	var B: Dictionary = d["bipode"]; var hb: Array = piv["brazo_d"]
	_fogo = Node3D.new(); _fogo.position = v3([B["boca"][0] - hb[0] + 0.1, B["boca"][1] - hb[1], B["boca"][2] - hb[2]]); nodos["brazo_d"].add_child(_fogo)
	var fm := StandardMaterial3D.new(); fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; fm.albedo_color = Color(1.0, 0.70, 0.28, 0.9)
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; fm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD; fm.cull_mode = BaseMaterial3D.CULL_DISABLED; fm.no_depth_test = false
	for k in 3:
		var q := MeshInstance3D.new(); var pm := QuadMesh.new(); pm.size = Vector2(0.8, 0.36); q.mesh = pm; q.material_override = fm
		q.basis = Basis(Vector3(1, 0, 0), k * PI / 3); q.position = Vector3(0.3, 0, 0)
		_fogo.add_child(q)
	_luz_fogo = OmniLight3D.new(); _luz_fogo.light_color = Color(1.0, 0.63, 0.25); _luz_fogo.omni_range = 14.0; _luz_fogo.light_energy = 0.0
	_luz_fogo.position = Vector3(0.3, 0, 0); _fogo.add_child(_luz_fogo); _fogo.visible = false

## Codigo comun del sombreado: la tabla de materiales (colores en lineal, rugosidad, metalico) + DATOS.modelo3d.sombreador.
static func codigo(K: Dictionary) -> String:
	var lin := func(x: float) -> float: return x / 12.92 if x <= 0.04045 else pow((x + 0.055) / 1.055, 2.4)
	var s := "vec3 bip_color(float m) {\n"
	var mats: Array = K["materiales"]
	for i in mats.size():
		var c := int(mats[i][1])
		s += "\tif (m < %.6f) return vec3(%.6f, %.6f, %.6f);\n" % [i + 0.5, lin.call(((c >> 16) & 255) / 255.0), lin.call(((c >> 8) & 255) / 255.0), lin.call((c & 255) / 255.0)]
	s += "\treturn vec3(1.0);\n}\nvec2 bip_rm(float m) {\n"
	for i in mats.size(): s += "\tif (m < %.6f) return vec2(%.6f, %.6f);\n" % [i + 0.5, float(mats[i][2]), float(mats[i][3])]
	return s + "\treturn vec2(0.5, 0.0);\n}\n" + "\n".join(K["sombreador"]) + "\n"

static func material(K: Dictionary) -> ShaderMaterial:
	if _material != null: return _material
	var sh := Shader.new()
	sh.code = "shader_type spatial;\nrender_mode cull_back, depth_draw_opaque;\n" + \
		"uniform sampler2D calcas : source_color, filter_linear_mipmap_anisotropic, repeat_disable;\n" + \
		"varying vec3 pl;\nvarying vec3 nl;\nvarying vec4 bip;\nvarying vec2 uvc;\n" + codigo(K) + """
void vertex() {
	pl = VERTEX; nl = NORMAL; bip = COLOR; uvc = UV;
}
void fragment() {
	float bM = floor(bip.x * 255.0 + 0.5); float bK = (bip.y * 255.0 - 128.0) / 127.0; float bAo = bip.z; float bH = bip.w;
	vec3 alb = bip_color(bM); vec2 rm = bip_rm(bM); vec3 emi = vec3(0.0);
	if (abs(bM - 7.0) < 0.5) { vec4 tc = texture(calcas, uvc); if (tc.a < 0.5 || bip_calca_saltada(pl) > 0.5) { discard; } alb = tc.rgb; }
	float rug = rm.x; float met = rm.y;
	bip_superficie(pl, nl, bM, bK, bH, alb, rug, met, emi);
	ALBEDO = alb; ROUGHNESS = rug; METALLIC = met; EMISSION = emi; AO = bAo; AO_LIGHT_AFFECT = 0.35;
}
"""
	_material = ShaderMaterial.new(); _material.shader = sh
	var f := DatosComunes.carpeta().path_join("vehiculos").path_join(String(K["calcas"]))
	var img := Image.load_from_file(f) if FileAccess.file_exists(f) else null
	if img != null:
		img.generate_mipmaps(); _material.set_shader_parameter("calcas", ImageTexture.create_from_image(img))
	return _material

## Las mallas de cada pieza (una vez para todo el programa).
static func mallas(K: Dictionary) -> Dictionary:
	if not _mallas.is_empty(): return _mallas
	for pz in K["piezas"]:
		var b := Marshalls.base64_to_raw(pz["v"]); var n := int(pz["vertices"])
		var pos := PackedVector3Array(); pos.resize(n); var nor := PackedVector3Array(); nor.resize(n)
		var col := PackedColorArray(); col.resize(n); var uv := PackedVector2Array(); uv.resize(n)
		for k in n:
			var o := 18 * k
			pos[k] = Vector3(b.decode_s16(o) / 10000.0, b.decode_s16(o + 2) / 10000.0, b.decode_s16(o + 4) / 10000.0)
			nor[k] = Vector3(b.decode_s8(o + 6) / 127.0, b.decode_s8(o + 7) / 127.0, b.decode_s8(o + 8) / 127.0).normalized()
			col[k] = Color(b[o + 9] / 255.0, (b.decode_s8(o + 10) + 128) / 255.0, b[o + 11] / 255.0, b[o + 12] / 255.0)
			uv[k] = Vector2(b.decode_u16(o + 14) / 65535.0, b.decode_u16(o + 16) / 65535.0)
		var ib := Marshalls.base64_to_raw(pz["i"]); var idx := PackedInt32Array(); idx.resize(ib.size() / 2)
		for i in range(0, idx.size(), 3):           # Godot: cara delantera en sentido horario (al reves que en los datos)
			idx[i] = ib.decode_u16(2 * i); idx[i + 1] = ib.decode_u16(2 * i + 4); idx[i + 2] = ib.decode_u16(2 * i + 2)
		var arr := []; arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = pos; arr[Mesh.ARRAY_NORMAL] = nor; arr[Mesh.ARRAY_COLOR] = col; arr[Mesh.ARRAY_TEX_UV] = uv; arr[Mesh.ARRAY_INDEX] = idx
		var am := ArrayMesh.new(); am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		_mallas[pz["nombre"]] = am
	return _mallas

func _fila(f: float) -> Array:
	var NT := tabla.size(); var x: float = f * NT; var i := int(floorf(x)) % NT; var j := (i + 1) % NT; var a: float = x - floorf(x)
	var r := []
	for k in (tabla[i] as Array).size(): r.append(tabla[i][k] + (tabla[j][k] - tabla[i][k]) * a)
	return r

## Cada cuadro (animar de la web): paso, cintura, brazos, cañones, puño y fogonazo.
func actualizar(av: Dictionary, dt: float) -> void:
	var a: float = av.get("amp", 0.0); var r := _fila(av.get("fase", 0.0))
	nodos["cadera_d"].rotation = Vector3(0, a * r[0], 0); nodos["rodilla_d"].rotation = Vector3(0, a * r[1], 0); nodos["tobillo_d"].rotation = Vector3(0, a * r[2], 0)
	nodos["cadera_i"].rotation = Vector3(0, a * r[3], 0); nodos["rodilla_i"].rotation = Vector3(0, a * r[4], 0); nodos["tobillo_i"].rotation = Vector3(0, a * r[5], 0)
	var pv: Array = piv["pelvis"]
	nodos["pelvis"].position = v3([pv[0], pv[1], pv[2] - a * r[6]]); nodos["pelvis"].rotation = Vector3(a * r[7], 0, 0)
	nodos["cintura"].rotation = Vector3(0, 0, float(av.get("cintura", 0.0)))
	var br: float = av.get("brazos", 0.0)
	nodos["brazo_d"].rotation = Vector3(0, br, 0); nodos["brazo_i"].rotation = Vector3(0, 0.6 * br, 0)
	nodos["canones"].rotation = Vector3(float(av.get("angCanones", 0.0)), 0, 0)
	nodos["dedos"].rotation = Vector3(0, -1.1 * float(av.get("puno", 0.0)), 0)
	var nd := int(av.get("disparos", 0))
	if nd != _n_disp:
		if _n_disp >= 0 and nd > _n_disp: _t_fogo = 0.05
		_n_disp = nd
	_t_fogo -= dt; _fogo.visible = _t_fogo > 0; _luz_fogo.light_energy = 6.0 if _t_fogo > 0 else 0.0
	if _fogo.visible: _fogo.rotation = Vector3(randf() * PI, 0, 0)

## Camaras propias: 2 detras del torso, mirando hacia donde apunta la cintura; 3 puesto de tiro sobre el hombro del cañon.
func camara(cam: Camera3D, av: Dictionary, n: int) -> bool:
	var t := ned(av["p"]); var yaw: float = Cuat.euler(av["q"])[2] + float(av.get("cintura", 0.0))
	if n == 2:
		cam.fov = 60; cam.global_position = t + ned([-cos(yaw) * 7.5, -sin(yaw) * 7.5, -4.6])
		cam.look_at(t + ned([cos(yaw) * 5, sin(yaw) * 5, -2.2]), Vector3.UP); return true
	if n == 3:
		var ap := ModeloBipode.apuntado_con(piv, datos["bipode"], av); var p: Array = av["p"]
		cam.fov = 55; cam.global_position = ned([p[0] - cos(yaw) * 3.6 - sin(yaw) * 2.3, p[1] - sin(yaw) * 3.6 + cos(yaw) * 2.3, p[2] - 2.7])
		cam.look_at(ned([ap["o"][0] + ap["d"][0] * 80, ap["o"][1] + ap["d"][1] * 80, ap["o"][2] + ap["d"][2] * 80]), Vector3.UP); return true
	return false
