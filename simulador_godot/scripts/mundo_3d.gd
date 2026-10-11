class_name Mundo3D
extends Node3D
## El mundo real en 3D (version Godot) con los MISMOS datos que el navegador: la malla de terreno del mundo
## (simulador/mundos/<id>.js) con la ortofoto PNOA de la region, el mar, las carreteras y zonas urbanas de OSM, los
## rotulos de los pueblos y, donde la hay, la zona de detalle (simulador/zonas/<id>/): terreno a 5 m con la ortofoto
## a 0,5 m, edificios del Catastro con sus plantas y arboles detectados en la ortofoto. Fuera de la zona, arboles
## sacados de la ortofoto de la region (pixeles de vegetacion). El suelo fisico es el de Entorno: aqui solo se dibuja.
## Ejes: x = este, y = arriba, z = sur (como en el navegador).

var ent: Entorno
var m: Dictionary
var h0: float
var sol: DirectionalLight3D
var img_region: Image
var tex_region: ImageTexture
var zona_bbox := []           # [N0, N1, E0, E1] de la zona de detalle puesta, o []
var zona_id := ""
var _terreno: MeshInstance3D
var _cintas: MeshInstance3D
var _edif_sint: Node3D
var _zona: Node3D
var _arboles_region: Node3D
var _arboles_NE := []
var manga: Node3D
var base := Vector3.ZERO
var claro := Vector2(INF, INF)     # (E, N) del piloto: sin arboles de la zona alrededor
var _claro_hecho := Vector2(INF, INF)
var _zona_arboles: Node3D
var _zona_datos := {}
var calidad := 2                   # 0 baja, 1 media, 2 alta (se fija antes de construir)

## Para medir el rendimiento: --sin=arboles,sombras,ssao,mar,edificios,niebla,cielo (tras -- en la linea de ordenes).
static func sin_(parte: String) -> bool:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--sin=") and parte in a.substr(6).split(","): return true
	return false

## Para afinar la luz desde la linea de ordenes: --luz=exposicion,ambiente,sol,cielo_en_ambiente
static func luz_(i: int, defecto: float) -> float:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--luz="):
			var v := a.substr(6).split(",")
			if i < v.size() and v[i] != "": return v[i].to_float()
	return defecto

static func lin(c: Color) -> Color:
	return c.srgb_to_linear()

static func _tex_de(ruta: String, ampliar := 1) -> ImageTexture:
	var img := Image.load_from_file(ruta)
	if img == null: return null
	# ampliada con interpolacion bicubica: de cerca se ven menos los bloques del JPEG y los pixeles de 0,5 m
	if ampliar > 1: img.resize(img.get_width() * ampliar, img.get_height() * ampliar, Image.INTERPOLATE_CUBIC)
	img.generate_mipmaps(); img.compress(Image.COMPRESS_S3TC, Image.COMPRESS_SOURCE_SRGB)     # 8 veces menos memoria de video
	return ImageTexture.create_from_image(img)

static func _mi(mesh: Mesh, mat: Material, sombra := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new(); mi.mesh = mesh; mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if sombra else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

static func _malla(pos: PackedVector3Array, nor: PackedVector3Array, idx: PackedInt32Array, uv := PackedVector2Array(), col := PackedColorArray()) -> ArrayMesh:
	var arr := []; arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = pos; arr[Mesh.ARRAY_NORMAL] = nor
	if not idx.is_empty(): arr[Mesh.ARRAY_INDEX] = idx
	if not uv.is_empty(): arr[Mesh.ARRAY_TEX_UV] = uv
	if not col.is_empty(): arr[Mesh.ARRAY_COLOR] = col
	var am := ArrayMesh.new(); am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return am

## Ortofoto de la region de un mundo: [Image sin mipmaps (para leer pixeles), ImageTexture con mipmaps].
static func cargar_orto_region(id: String) -> Array:
	var img := Image.load_from_file(DatosComunes.ruta_orto_mundo(id))
	var img_mip := img.duplicate(); img_mip.generate_mipmaps(); img_mip.compress(Image.COMPRESS_S3TC, Image.COMPRESS_SOURCE_SRGB)
	return [img, ImageTexture.create_from_image(img_mip)]

## Construye el mundo. e: el Entorno con ese mundo ya puesto; orto: cargar_orto_region(id).
func construir(e: Entorno, datos_mundo: Dictionary, orto: Array) -> void:
	ent = e; m = datos_mundo; h0 = m["terreno"]["h0"]
	_cielo_y_luz()
	img_region = orto[0]; tex_region = orto[1]
	_terreno_lejano()
	if not sin_("mar"): _mar()
	_carreteras()
	if not sin_("edificios"): _edificios_sinteticos()
	_rotulos()
	_crear_manga()

# ---------------------------------------------------------------- cielo, sol, niebla
func _cielo_y_luz() -> void:
	var we := WorldEnvironment.new(); var env := Environment.new()
	var sky := Sky.new(); var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.3, 0.48, 0.72); sm.sky_horizon_color = Color(0.70, 0.78, 0.86); sm.sky_curve = 0.12
	sm.ground_horizon_color = Color(0.70, 0.78, 0.86); sm.ground_bottom_color = Color(0.36, 0.34, 0.3)
	sm.sun_angle_max = 20.0; sm.sun_curve = 0.1
	sky.sky_material = sm; env.sky = sky; env.background_mode = Environment.BG_COLOR if sin_("cielo") else Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY; env.ambient_light_sky_contribution = luz_(3, 0.4); env.ambient_light_energy = luz_(1, 0.5); env.ambient_light_color = Color(0.62, 0.62, 0.6)
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES; env.tonemap_exposure = luz_(0, 1.05); env.tonemap_white = 6.0
	env.ssao_enabled = not sin_("ssao") and calidad >= 2; env.ssao_radius = 1.5; env.ssao_intensity = 1.5
	env.glow_enabled = true; env.glow_intensity = 0.3; env.glow_bloom = 0.02
	# calima del Campo de Cartagena: niebla por distancia de 2,5 a 10,5 km (como el navegador) y perspectiva aerea
	env.fog_enabled = not sin_("niebla"); env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_depth_begin = 2500.0; env.fog_depth_end = 10500.0; env.fog_depth_curve = 1.3
	env.fog_light_color = Color(0.72, 0.79, 0.86); env.fog_aerial_perspective = 0.4; env.fog_sky_affect = 0.0
	env.adjustment_enabled = true; env.adjustment_saturation = luz_(5, 1.2); env.adjustment_contrast = luz_(4, 1.18)
	we.environment = env; add_child(we)
	sol = DirectionalLight3D.new()
	sol.look_at_from_position(Vector3(-3500, 5200, 2600).normalized(), Vector3.ZERO, Vector3.UP)
	sol.light_energy = luz_(2, 1.2); sol.light_color = Color(1.0, 0.96, 0.9); sol.light_angular_distance = 0.6
	sol.shadow_enabled = not sin_("sombras")
	sol.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if calidad > 0 else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sol.directional_shadow_max_distance = [300.0, 600.0, 900.0][calidad]; sol.directional_shadow_blend_splits = true
	sol.directional_shadow_split_1 = 0.03; sol.directional_shadow_split_2 = 0.12; sol.directional_shadow_split_3 = 0.4
	sol.shadow_bias = 0.04; sol.shadow_normal_bias = 1.2
	add_child(sol)

# ---------------------------------------------------------------- terreno lejano (malla del mundo, 150 m)
func _terreno_lejano() -> void:
	if _terreno: _terreno.queue_free()
	var T: Dictionary = ent.terreno; var H: PackedInt32Array = T["H"]
	var nN: int = T["nN"]; var nE: int = T["nE"]; var paso: float = T["paso"]; var N0: float = T["N0"]; var E0: float = T["E0"]
	var Y := PackedFloat32Array(); Y.resize(nN * nE)
	var agua := ent.agua; var hay_agua := not agua.is_empty()
	for i in nN:
		for j in nE:
			var k := i * nE + j; var h: float = H[k]
			var y := maxf(h, 1.0)
			var es_agua: bool = agua[k] == 1 if hay_agua else h <= 0
			if es_agua:
				# junto a la costa a -1,5 m (una franja de tierra de una celda, como La Manga, sigue viendose); mar adentro, -7 m
				var orilla := false
				for di in [-1, 0, 1]:
					for dj in [-1, 0, 1]:
						var ii: int = i + di; var jj: int = j + dj
						if ii >= 0 and ii < nN and jj >= 0 and jj < nE:
							var kk := ii * nE + jj
							if not (agua[kk] == 1 if hay_agua else H[kk] <= 0): orilla = true
				y = -1.5 if orilla else -7.0
			y -= h0
			if not zona_bbox.is_empty():          # bajo la zona de detalle se hunde 25 m: no asoma entre sus mallas
				var N := N0 + i * paso; var E := E0 + j * paso
				if N > zona_bbox[0] and N < zona_bbox[1] and E > zona_bbox[2] and E < zona_bbox[3]: y -= 25
			Y[k] = y
	var pos := PackedVector3Array(); pos.resize(nN * nE); var nor := PackedVector3Array(); nor.resize(nN * nE)
	var uv := PackedVector2Array(); uv.resize(nN * nE)
	for i in nN:
		for j in nE:
			var k := i * nE + j
			pos[k] = Vector3(E0 + j * paso, Y[k], -(N0 + i * paso))
			uv[k] = Vector2(float(j) / (nE - 1), 1.0 - float(i) / (nN - 1))
			var fE := (Y[k + (1 if j < nE - 1 else 0)] - Y[k - (1 if j > 0 else 0)]) / (2 * paso)
			var fN := (Y[k + (nE if i < nN - 1 else 0)] - Y[k - (nE if i > 0 else 0)]) / (2 * paso)
			nor[k] = Vector3(-fE, 1, fN).normalized()
	var idx := PackedInt32Array(); idx.resize((nN - 1) * (nE - 1) * 6); var q := 0
	for i in nN - 1:
		for j in nE - 1:
			var a := i * nE + j; var b := a + 1; var c := a + nE; var d := c + 1
			idx[q] = a; idx[q + 1] = c; idx[q + 2] = b; idx[q + 3] = b; idx[q + 4] = c; idx[q + 5] = d; q += 6
	var mat := StandardMaterial3D.new(); mat.albedo_texture = tex_region; mat.roughness = 1.0
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_terreno = _mi(_malla(pos, nor, idx, uv), mat, false); add_child(_terreno)

# ---------------------------------------------------------------- mar
const SHADER_MAR := """
shader_type spatial;
render_mode depth_draw_opaque;
uniform vec3 color_agua : source_color = vec3(0.10, 0.26, 0.36);
uniform sampler2D ondas1 : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D ondas2 : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
varying vec3 pmundo;
void vertex() { pmundo = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 p = pmundo.xz;
	vec3 n1 = texture(ondas1, p / 47.0 + TIME * vec2(0.011, 0.007)).xyz;
	vec3 n2 = texture(ondas2, p / 13.0 - TIME * vec2(0.013, 0.019)).xyz;
	NORMAL_MAP = normalize(n1 + n2 - 1.0) * 0.5 + 0.5;
	float d = length(VERTEX);
	NORMAL_MAP_DEPTH = mix(0.9, 0.15, clamp(d / 3000.0, 0.0, 1.0));   // lejos, mas liso (sin centelleo)
	ALBEDO = color_agua;
	ROUGHNESS = 0.04; METALLIC = 0.0; SPECULAR = 0.55;
}
"""

func _mar() -> void:
	var sh := Shader.new(); sh.code = SHADER_MAR
	var mat := ShaderMaterial.new(); mat.shader = sh
	for k in ["ondas1", "ondas2"]:
		var nt := NoiseTexture2D.new(); nt.width = 512; nt.height = 512; nt.seamless = true; nt.as_normal_map = true
		nt.bump_strength = 6.0 if k == "ondas1" else 3.0; nt.generate_mipmaps = true
		var fn := FastNoiseLite.new(); fn.frequency = 0.012 if k == "ondas1" else 0.025; fn.seed = 7 if k == "ondas1" else 13
		fn.fractal_octaves = 4; nt.noise = fn
		mat.set_shader_parameter(k, nt)
	var pm := PlaneMesh.new(); pm.size = Vector2(300000, 300000)
	var mi := _mi(pm, mat, false); mi.position = Vector3(0, -h0 + 0.4, 0); add_child(mi)

# ---------------------------------------------------------------- carreteras (cintas) fuera de la zona de detalle
func _dentro_zona(n: float, e: float, margen: float) -> bool:
	var Z := zona_bbox
	return not Z.is_empty() and n > Z[0] - margen and n < Z[1] + margen and e > Z[2] - margen and e < Z[3] + margen

func _carreteras() -> void:
	if _cintas: _cintas.queue_free(); _cintas = null
	var W := { 1: 11.0, 2: 6.5, 3: 5.0, 4: 4.0 }
	var CL := { 1: lin(Color.hex(0xe6dfcaff)), 2: lin(Color.hex(0xd8d0b3ff)), 3: lin(Color.hex(0xc7c2adff)), 4: lin(Color.hex(0xb6b2a0ff)) }
	var pos := PackedVector3Array(); var col := PackedColorArray(); var idx := PackedInt32Array(); var nor := PackedVector3Array()
	for c in m["carreteras"]:
		# sin los tramos dentro de la zona de detalle (alli la ortofoto ya las muestra)
		var tramos := []; var tramo := []
		for i in range(1, c.size(), 2):
			if _dentro_zona(c[i + 1], c[i], 30):
				if tramo.size() >= 2: tramos.append(tramo)
				tramo = []
			else: tramo.append(Vector2(c[i], c[i + 1]))
		if tramo.size() >= 2: tramos.append(tramo)
		var t: int = int(c[0]); var w: float = W[t]; var color: Color = CL[t]
		for pts in tramos:
			var P := []
			for i in pts.size():
				if i > 0:
					var a: Vector2 = pts[i - 1]; var b: Vector2 = pts[i]; var k := int(ceil(a.distance_to(b) / 120))
					for j in range(1, k): P.append(a.lerp(b, float(j) / k))
				P.append(pts[i])
			var base_i := pos.size()
			for i in P.size():
				var p: Vector2 = P[i]; var pa: Vector2 = P[maxi(0, i - 1)]; var pb: Vector2 = P[mini(P.size() - 1, i + 1)]
				var dx := pb.x - pa.x; var dz := -(pb.y - pa.y); var L := maxf(1e-6, sqrt(dx * dx + dz * dz)); dx /= L; dz /= L
				var nx := -dz; var nz := dx; var y := ent.altura(p.y, p.x) + 1.0
				pos.append(Vector3(p.x + nx * w, y, -p.y + nz * w)); pos.append(Vector3(p.x - nx * w, y, -p.y - nz * w))
				nor.append(Vector3.UP); nor.append(Vector3.UP); col.append(color); col.append(color)
				if i > 0:
					var b := base_i + 2 * i
					idx.append_array([b - 2, b - 1, b, b - 1, b + 1, b])
	if pos.is_empty(): return
	var mat := StandardMaterial3D.new(); mat.vertex_color_use_as_albedo = true; mat.cull_mode = BaseMaterial3D.CULL_DISABLED; mat.roughness = 0.95
	_cintas = _mi(_malla(pos, nor, idx, PackedVector2Array(), col), mat, false); add_child(_cintas)

# ---------------------------------------------------------------- instancias por celdas
## Una MultiMesh por celda de `celda` m, con su nodo en el centro de la celda (para los rangos de visibilidad).
## lista: elementos [E, N, ...]; colocar(it) -> [Transform3D, Color]
func _instanciar(padre: Node3D, mesh: Mesh, mat: Material, lista: Array, colocar: Callable, celda: float, vis_ini := 0.0, vis_fin := 0.0,
		sombra := GeometryInstance3D.SHADOW_CASTING_SETTING_ON) -> void:
	var celdas := {}
	for it in lista:
		var k := Vector2i(floori(it[0] / celda), floori(it[1] / celda))
		if not celdas.has(k): celdas[k] = []
		celdas[k].append(it)
	for k in celdas:
		var items: Array = celdas[k]
		var trs := []; var cols := []; var ysum := 0.0
		for it in items:
			var r: Array = colocar.call(it)
			trs.append(r[0]); cols.append(r[1]); ysum += (r[0] as Transform3D).origin.y
		var centro := Vector3((k.x + 0.5) * celda, ysum / items.size(), -(k.y + 0.5) * celda)
		var mm := MultiMesh.new(); mm.transform_format = MultiMesh.TRANSFORM_3D; mm.use_colors = true; mm.mesh = mesh
		mm.instance_count = items.size()
		for i in items.size():
			var tr: Transform3D = trs[i]; tr.origin -= centro
			mm.set_instance_transform(i, tr); mm.set_instance_color(i, cols[i])
		var mmi := MultiMeshInstance3D.new(); mmi.multimesh = mm; mmi.material_override = mat; mmi.cast_shadow = sombra
		mmi.position = centro
		if vis_fin > 0:
			mmi.visibility_range_begin = vis_ini; mmi.visibility_range_end = vis_fin
		padre.add_child(mmi)

static func _esfera(radiales: int, anillos: int) -> SphereMesh:
	var s := SphereMesh.new(); s.radius = 1.0; s.height = 2.0; s.radial_segments = radiales; s.rings = anillos
	return s

const SHADER_SUELO := """
shader_type spatial;
render_mode cull_disabled;
// Suelo con la ortofoto y, cerca de la camara, un grano fino (piedras, matas, tierra) que rompe los pixeles de 0,5 m.
uniform sampler2D orto : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D grano : filter_linear_mipmap, repeat_enable;
varying vec3 pm;
void vertex() { pm = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec3 c = texture(orto, UV).rgb;
	float g = texture(grano, pm.xz / 3.7).r * 0.55 + texture(grano, pm.xz / 0.83).r * 0.45;
	float k = mix(0.68 + 0.64 * g, 1.0, smoothstep(20.0, 160.0, length(VERTEX)));
	ALBEDO = c * k; ROUGHNESS = 1.0; SPECULAR = 0.3;
}
"""

static var _grano: NoiseTexture2D

static func _mat_suelo(tex: Texture2D) -> ShaderMaterial:
	if _grano == null:
		_grano = NoiseTexture2D.new(); _grano.width = 512; _grano.height = 512; _grano.seamless = true; _grano.generate_mipmaps = true
		var fn := FastNoiseLite.new(); fn.frequency = 0.05; fn.fractal_octaves = 5; fn.seed = 3; _grano.noise = fn
	var sh := Shader.new(); sh.code = SHADER_SUELO
	var m := ShaderMaterial.new(); m.shader = sh; m.set_shader_parameter("orto", tex); m.set_shader_parameter("grano", _grano)
	return m

const SHADER_ARBOL := """
shader_type spatial;
// Copa de arbol: la esfera se deforma con ruido (silueta irregular, distinta en cada arbol) y el color lleva manchas
// de hojas y sombra interior; la luz que atraviesa las hojas (BACKLIGHT) la aclara a contraluz.
uniform float rugosidad = 0.28;
varying float hueco;
float hash(vec3 p) { p = fract(p * 0.3183099 + 0.1); p *= 17.0; return fract(p.x * p.y * p.z * (p.x + p.y + p.z)); }
float ruido(vec3 x) {
	vec3 i = floor(x); vec3 f = fract(x); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
			   mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}
void vertex() {
	vec3 s = vec3(float(INSTANCE_ID) * 1.73, float(INSTANCE_ID) * 0.37, 0.0);
	float n = ruido(VERTEX * 1.6 + s) * 0.6 + ruido(VERTEX * 4.1 + s) * 0.4;
	VERTEX += NORMAL * (n - 0.5) * 2.0 * rugosidad;
	hueco = n;
}
void fragment() {
	vec3 pm = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float f = ruido(pm * 2.7) * 0.55 + ruido(pm * 8.3) * 0.45;
	ALBEDO = COLOR.rgb * (0.6 + 0.75 * f) * (0.7 + 0.5 * hueco);
	ROUGHNESS = 0.92; SPECULAR = 0.15;
	BACKLIGHT = COLOR.rgb * 0.35;
}
"""

static var _mat_arbol: ShaderMaterial

static func _mat_copas() -> ShaderMaterial:
	if _mat_arbol == null:
		var sh := Shader.new(); sh.code = SHADER_ARBOL
		_mat_arbol = ShaderMaterial.new(); _mat_arbol.shader = sh
	return _mat_arbol

static func _mat_instancias() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new(); mat.vertex_color_use_as_albedo = true; mat.roughness = 1.0
	return mat

# ---------------------------------------------------------------- edificios genericos en las zonas urbanas de OSM
static func _en_poligono(P: Array, x: float, y: float) -> bool:
	var d := false; var j := P.size() - 1
	for i in P.size():
		var a: Vector2 = P[i]; var b: Vector2 = P[j]
		if (a.y > y) != (b.y > y) and x < (b.x - a.x) * (y - a.y) / (b.y - a.y) + a.x: d = not d
		j = i
	return d

func _edificios_sinteticos() -> void:
	if _edif_sint: _edif_sint.queue_free()
	_edif_sint = Node3D.new(); add_child(_edif_sint)
	var r := RandomNumberGenerator.new(); r.seed = 17
	var edificios := []
	for u in m["urbano"]:
		var P := []
		var e0 := 1e9; var e1 := -1e9; var n0 := 1e9; var n1 := -1e9
		for i in range(1, u.size(), 2):
			P.append(Vector2(u[i], u[i + 1]))
			e0 = minf(e0, u[i]); e1 = maxf(e1, u[i]); n0 = minf(n0, u[i + 1]); n1 = maxf(n1, u[i + 1])
		var tipo: int = int(u[0]); var paso := 48.0 if tipo == 1 else 70.0
		var e := e0
		while e < e1:
			var n := n0
			while n < n1:
				var ee := e + (r.randf() - 0.5) * paso * 0.7; var nn := n + (r.randf() - 0.5) * paso * 0.7
				if not _dentro_zona(nn, ee, 20) and edificios.size() < 14000 and _en_poligono(P, ee, nn) and not ent.en_mar(nn, ee) and ent.altura_mar(nn, ee) > 0:
					edificios.append([ee, nn, (8 + r.randf() * 8) if tipo == 1 else (12 + r.randf() * 14), tipo, r.randf()])
				n += paso
			e += paso
	var colores1 := [0xf2ede4, 0xe8dcc8, 0xd9c4a8, 0xf5f0e8]; var colores2 := [0xd0d4d8, 0xc3c7cc, 0xb9bec4]
	_instanciar(_edif_sint, BoxMesh.new(), _mat_instancias(), edificios, func(it: Array) -> Array:
		var s: float = it[2]; var z: float = it[4]; var h: float = (4 + z * 7) if it[3] == 1 else (6 + z * 6)
		var b := Basis(Vector3.UP, z * 3.14).scaled_local(Vector3(s, h, s * (0.7 + z * 0.5)))
		var c: int = colores1[int(z * 4) % 4] if it[3] == 1 else colores2[int(z * 3) % 3]
		return [Transform3D(b, Vector3(it[0], ent.altura(it[1], it[0]) + h / 2, -it[1])), lin(Color.hex((c << 8) | 0xff))], 1200.0)

# ---------------------------------------------------------------- rotulos de los pueblos
func _rotulos() -> void:
	for l in m["lugares"]:
		var rango: int = int(l[1])
		if rango > 3: continue
		var e: float = l[2]; var n: float = l[3]
		var s := 1600.0 if rango == 1 else (1000.0 if rango == 2 else 600.0)
		var lb := Label3D.new(); lb.text = l[0]; lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED; lb.no_depth_test = true
		lb.font_size = 96; lb.outline_size = 18; lb.pixel_size = s / 1500.0; lb.modulate = Color(1, 1, 1, 0.85)
		lb.position = Vector3(e, ent.altura(n, e) + s * 0.18, -n)
		lb.visibility_range_begin = 600.0
		add_child(lb)

# ---------------------------------------------------------------- manga de viento junto al piloto
func _crear_manga() -> void:
	manga = Node3D.new(); add_child(manga)
	var palo := MeshInstance3D.new(); var pm := CylinderMesh.new(); pm.top_radius = 0.03; pm.bottom_radius = 0.04; pm.height = 4.0
	palo.mesh = pm; palo.position = Vector3(0, 2.0, 0); var mp := StandardMaterial3D.new(); mp.albedo_color = Color(0.6, 0.6, 0.6); palo.material_override = mp
	manga.add_child(palo)
	var saco := MeshInstance3D.new(); var sm := CylinderMesh.new(); sm.top_radius = 0.22; sm.bottom_radius = 0.08; sm.height = 1.2
	saco.mesh = sm; var ms := StandardMaterial3D.new(); ms.albedo_color = Color(1.0, 0.45, 0.1); saco.material_override = ms
	saco.name = "saco"; manga.add_child(saco)

## Orienta la manga hacia donde va el viento (vn: viento NED actual, m/s); con poco viento cuelga.
func actualizar_manga(vn: Array) -> void:
	var saco := manga.get_node("saco") as MeshInstance3D
	var dir := Vector3(vn[1], 0, -vn[0]); var vel := dir.length()
	if vel < 0.05: dir = Vector3(1, 0, 0)
	dir = dir.normalized()
	var colgado := clampf(1.0 - vel / 7.0, 0.05, 1.0) * 1.3
	var eje := dir.rotated(dir.cross(Vector3.UP).normalized(), colgado)     # hacia donde apunta la boca estrecha
	# el cilindro va a lo largo de su y: de la boca (radio 0,22, arriba) a la cola (0,08, abajo) -> y = -eje
	var y := -eje; var x := y.cross(Vector3.UP if absf(y.y) < 0.99 else Vector3.RIGHT).normalized(); var z := x.cross(y)
	saco.basis = Basis(x, y, z)
	saco.position = Vector3(0, 3.9, 0) + eje * 0.6

## Punto de lanzamiento (N, E): ahi van el piloto (camara 1), la manga y los arboles de la region alrededor.
func poner_base(N: float, E: float) -> void:
	var h := ent.altura(N, E); base = Vector3(E, h, -N); claro = Vector2(E, N)
	if _zona != null and _zona_arboles != null and claro.distance_to(_claro_hecho) > 5 and not sin_("arboles"): _arboles_zona(_zona_datos)
	manga.position = Vector3(E - 14, ent.altura(N + 10, E - 14), -N - 10)
	if sin_("arboles"): return
	if _arboles_NE.is_empty() or Vector2(_arboles_NE[0] - N, _arboles_NE[1] - E).length() > 1500:
		_arboles_de_la_region(N, E)

# ---------------------------------------------------------------- arboles de la region (de la ortofoto)
## Fuera de la zona de detalle, un arbol donde la ortofoto de la region (12 m por pixel) es vegetacion: verde oscuro
## (almendros, algarrobos, pinos). Hasta 7 km del punto de lanzamiento; mas lejos lo tapa la calima.
func _arboles_de_la_region(cN: float, cE: float) -> void:
	if _arboles_region: _arboles_region.queue_free()
	_arboles_region = Node3D.new(); add_child(_arboles_region); _arboles_NE = [cN, cE]
	var T: Dictionary = ent.terreno; var W := img_region.get_width(); var Hh := img_region.get_height()
	var mpx: float = (T["nE"] - 1) * T["paso"] / W
	var r := RandomNumberGenerator.new(); r.seed = 11 + int(cN / 97) + int(cE / 89)
	var arboles := []; var paso := 24.0; var R: float = [2500.0, 4500.0, 7000.0][calidad]
	var n := -R
	while n <= R and arboles.size() < 60000:
		var e := -R
		while e <= R and arboles.size() < 60000:
			var ee := cE + e + (r.randf() - 0.5) * paso; var nn := cN + n + (r.randf() - 0.5) * paso
			var d2 := e * e + n * n
			e += paso
			if d2 > R * R or _dentro_zona(nn, ee, 10): continue
			var x := int((ee - T["E0"]) / mpx); var y := int(Hh - 1 - (nn - T["N0"]) / mpx)
			if x < 0 or y < 0 or x >= W or y >= Hh: continue
			var c := img_region.get_pixel(x, y)
			var lum := 0.3 * c.r + 0.59 * c.g + 0.11 * c.b
			if not (c.g > c.r * 0.97 and c.g > c.b * 1.08 and lum < 0.45 and lum > 0.08): continue
			if r.randf() > 0.7 or ent.en_mar(nn, ee): continue
			arboles.append([ee, nn, 2.0 + r.randf() * 2.0, c.darkened(0.05 + 0.2 * r.randf())])
		n += paso
	_instanciar(_arboles_region, _esfera(6, 3), _mat_copas(), arboles, func(it: Array) -> Array:
		var s: float = it[2]
		var b := Basis(Vector3.UP, s * 5.0).scaled_local(Vector3(s, s * 0.8, s))
		return [Transform3D(b, Vector3(it[0], ent.altura(it[1], it[0]) + s * 0.75, -it[1])), lin(it[3])], 1000.0, 0.0, 7500.0)

# ---------------------------------------------------------------- zona de detalle
## Pone la zona de detalle z = DatosComunes.cargar_zona(...) (o {} para quitarla). El Entorno ya la tiene.
func poner_zona(z: Dictionary) -> void:
	var nuevo_id: String = z["meta"]["id"] if not z.is_empty() else ""
	if nuevo_id == zona_id and (_zona != null or z.is_empty()): return
	if _zona: _zona.queue_free(); _zona = null
	var Zm: Dictionary = z.get("meta", {})
	zona_bbox = [] if z.is_empty() else [Zm["N0"], Zm["N0"] + Zm["lado_m"], Zm["E0"], Zm["E0"] + Zm["lado_m"]]
	zona_id = nuevo_id
	_terreno_lejano(); _carreteras(); _edificios_sinteticos()
	_arboles_NE = []
	if z.is_empty(): return
	_zona = Node3D.new(); add_child(_zona); _zona_datos = z; _zona_arboles = null
	_terreno_zona(z)
	if not sin_("edificios"): _edificios_zona(z)
	if not sin_("arboles"): _arboles_zona(z)

func _terreno_zona(z: Dictionary) -> void:
	var Z: Dictionary = z["meta"]; var D: PackedInt32Array = z["dem"]; var n: int = Z["dem"]["n"]; var paso: float = Z["dem"]["paso_m"]
	var nt: int = Z["orto"]["teselas"]; var celdas := int(round(Z["orto"]["tesela_m"] / paso))
	var Y := PackedFloat32Array(); Y.resize(n * n)
	for k in n * n:
		var v := D[k]; Y[k] = (-1.5 if v == -32768 else maxf(1.0, v / 10.0)) - h0
	var N0: float = Z["N0"]; var E0: float = Z["E0"]
	for ti in nt:
		for tj in nt:
			var pos := PackedVector3Array(); var nor := PackedVector3Array(); var uv := PackedVector2Array(); var idx := PackedInt32Array()
			var i0 := ti * celdas; var j0 := tj * celdas; var w := celdas + 1
			for a in w:
				for b in w:
					var i := i0 + a; var j := j0 + b; var k := i * n + j
					pos.append(Vector3(E0 + j * paso, Y[k], -(N0 + i * paso)))
					var fE := (Y[k + (1 if j < n - 1 else 0)] - Y[k - (1 if j > 0 else 0)]) / (2 * paso)
					var fN := (Y[k + (n if i < n - 1 else 0)] - Y[k - (n if i > 0 else 0)]) / (2 * paso)
					nor.append(Vector3(-fE, 1, fN).normalized())
					uv.append(Vector2(float(b) / celdas, 1.0 - float(a) / celdas))
			for a in celdas:
				for b in celdas:
					var p := a * w + b
					idx.append_array([p, p + w, p + 1, p + 1, p + w, p + w + 1])
			# faldones en los bordes exteriores de la zona: bajan 30 m y tapan el escalon con el terreno lejano
			var lados := []
			if ti == 0: lados.append(range(w).map(func(bb): return [0, bb]))
			if ti == nt - 1: lados.append(range(w).map(func(bb): return [celdas, bb]))
			if tj == 0: lados.append(range(w).map(func(aa): return [aa, 0]))
			if tj == nt - 1: lados.append(range(w).map(func(aa): return [aa, celdas]))
			for lista in lados:
				var base_i := pos.size()
				for ab in lista:
					var kk: int = ab[0] * w + ab[1]
					pos.append(pos[kk] - Vector3(0, 30, 0)); nor.append(nor[kk]); uv.append(uv[kk])
				for q in lista.size() - 1:
					var p1: int = lista[q][0] * w + lista[q][1]; var p2: int = lista[q + 1][0] * w + lista[q + 1][1]
					idx.append_array([p1, p2, base_i + q, p2, base_i + q + 1, base_i + q])
			var nombre: String = Z["orto"]["archivo"].replace("{i}", str(ti)).replace("{j}", str(tj))
			_zona.add_child(_mi(_malla(pos, nor, idx, uv), _mat_suelo(_tex_de(String(z["base"]).path_join(nombre), 2 if calidad >= 1 else 1)), false))

## Edificios del Catastro: cada huella extruida a sus plantas (3 m por planta) desde la cota del terreno, con el tejado
## del color de la ortofoto y las fachadas claras. Todo en una malla.
func _edificios_zona(z: Dictionary) -> void:
	var ruta: String = String(z["base"]).path_join(z["meta"]["edificios"]["archivo"])
	if not FileAccess.file_exists(ruta): return
	var lista = JSON.parse_string(FileAccess.get_file_as_string(ruta))
	if not lista is Array: return
	var pos := PackedVector3Array(); var nor := PackedVector3Array(); var col := PackedColorArray()
	var crema := lin(Color.hex(0xeee6d8ff)); var r := RandomNumberGenerator.new(); r.seed = 5
	for ed in lista:
		var p: Array = ed["p"]
		if p.size() < 6: continue
		var P := PackedVector2Array()
		for i in range(0, p.size(), 2): P.append(Vector2(p[i], p[i + 1]))
		var y0: float = ed["b"] - h0 - 0.4; var y1: float = ed["b"] - h0 + ed["pl"] * 3.0 + 0.5
		var C := lin(Color.html(ed["c"])) * 1.08; C.a = 1.0
		var Cw := crema.lerp(C, 0.12) * (0.93 + 0.1 * r.randf()); Cw.a = 1.0
		var tris := []
		for k in P.size():
			var a := P[k]; var b := P[(k + 1) % P.size()]
			var A0 := Vector3(a.x, y0, -a.y); var B0 := Vector3(b.x, y0, -b.y); var A1 := Vector3(a.x, y1, -a.y); var B1 := Vector3(b.x, y1, -b.y)
			tris.append([A0, B0, B1, Cw]); tris.append([A0, B1, A1, Cw])
		var t := Geometry2D.triangulate_polygon(P)
		for q in range(0, t.size(), 3):
			tris.append([Vector3(P[t[q]].x, y1, -P[t[q]].y), Vector3(P[t[q + 1]].x, y1, -P[t[q + 1]].y), Vector3(P[t[q + 2]].x, y1, -P[t[q + 2]].y), C])
		for tr in tris:
			var nn: Vector3 = (tr[2] - tr[0]).cross(tr[1] - tr[0]).normalized()
			pos.append_array([tr[0], tr[1], tr[2]]); nor.append_array([nn, nn, nn]); col.append_array([tr[3], tr[3], tr[3]])
	var mat := StandardMaterial3D.new(); mat.vertex_color_use_as_albedo = true; mat.cull_mode = BaseMaterial3D.CULL_DISABLED; mat.roughness = 0.9
	var mi := _mi(_malla(pos, nor, PackedInt32Array(), PackedVector2Array(), col), mat)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
	_zona.add_child(mi)

static func _hsl(h: float, s: float, l: float) -> Color:
	var q := l * (1 + s) if l < 0.5 else l + s - l * s; var p := 2 * l - q
	var f := func(t: float) -> float:
		t = fposmod(t, 1.0)
		if t < 1.0 / 6: return p + (q - p) * 6 * t
		if t < 0.5: return q
		if t < 2.0 / 3: return p + (q - p) * (2.0 / 3 - t) * 6
		return p
	return Color(f.call(h + 1.0 / 3), f.call(h), f.call(h - 1.0 / 3))

## Arboles detectados en la ortofoto: los de copa grande con tronco y copa detallada cerca de la camara; los
## pequenos, como matorral bajo. Cada celda de 500 m lleva su version detallada (hasta 450 m) y la sencilla.
func _arboles_zona(z: Dictionary) -> void:
	if _zona_arboles: _zona_arboles.queue_free()
	var padre := Node3D.new(); _zona.add_child(padre); _zona_arboles = padre; _claro_hecho = claro
	var ruta: String = String(z["base"]).path_join(z["meta"]["arboles"]["archivo"])
	if not FileAccess.file_exists(ruta): return
	var A := FileAccess.get_file_as_bytes(ruta).to_float32_array()
	var arboles := []; var matas := []; var r := RandomNumberGenerator.new(); r.seed = 29
	for i in range(0, A.size(), 3):
		var it := [A[i], A[i + 1], A[i + 2], r.randf(), r.randf(), r.randf(), r.randf()]
		if Vector2(A[i] - claro.x, A[i + 1] - claro.y).length() < 25 + A[i + 2]: continue      # el claro del piloto
		if A[i + 2] < 1.3: matas.append(it)
		else: arboles.append(it)
	var copa := func(it: Array) -> Array:
		var rc: float = it[2]; var ht := 0.9 + 0.45 * rc
		var b := Basis(Vector3.UP, it[3] * TAU).scaled_local(Vector3(rc, rc * (0.7 + 0.25 * it[4]), rc))
		return [Transform3D(b, Vector3(it[0], ent.altura(it[1], it[0]) + ht + rc * 0.55, -it[1])), lin(_hsl(0.19 + 0.05 * it[5], 0.2 + 0.1 * it[6], 0.24 + 0.08 * it[4]))]
	var mat := _mat_copas()
	_instanciar(padre, _esfera(12, 7), mat, arboles, copa, 500.0, 0.0, 450.0)
	_instanciar(padre, _esfera(6, 3), mat, arboles, copa, 500.0, 450.0, [2500.0, 5000.0, 9000.0][calidad])
	var mt := StandardMaterial3D.new(); mt.albedo_color = Color.hex(0x5b4632ff); mt.roughness = 1.0
	var cil := CylinderMesh.new(); cil.top_radius = 0.12; cil.bottom_radius = 0.2; cil.height = 1.0; cil.radial_segments = 5; cil.rings = 0
	_instanciar(padre, cil, mt, arboles, func(it: Array) -> Array:
		var rc: float = it[2]; var ht := 0.9 + 0.45 * rc
		return [Transform3D(Basis().scaled(Vector3(rc / 2.2, ht, rc / 2.2)), Vector3(it[0], ent.altura(it[1], it[0]) + ht / 2, -it[1])), Color.WHITE], 500.0, 0.0, 450.0)
	_instanciar(padre, _esfera(5, 3), mat, matas, func(it: Array) -> Array:
		var rc: float = it[2]
		var b := Basis(Vector3.UP, it[3] * TAU).scaled_local(Vector3(rc, rc * 0.55, rc))
		return [Transform3D(b, Vector3(it[0], ent.altura(it[1], it[0]) + rc * 0.3, -it[1])), lin(_hsl(0.15 + 0.06 * it[5], 0.16 + 0.1 * it[6], 0.3 + 0.08 * it[4]))], 500.0, 0.0, 4000.0,
		GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
