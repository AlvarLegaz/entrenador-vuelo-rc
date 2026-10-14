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
var zonas_bbox := []          # [[N0, N1, E0, E1], ...] de las zonas de detalle puestas
var zona_id := ""             # ids de las zonas puestas, separados por comas
var _zonas := []              # por zona: { nodo, datos, arboles }
var mapa_zonas := []          # teselas de ortofoto de las zonas para el GPS: { tex, N0, E0, lado } (mapaZonas de la web)
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
	if ampliar > 1 and img.get_width() < 2048: img.resize(img.get_width() * ampliar, img.get_height() * ampliar, Image.INTERPOLATE_CUBIC)   # las de 0,25 m, no
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
			if not zonas_bbox.is_empty():         # bajo las zonas de detalle se hunde 25 m: no asoma entre sus mallas
				var N := N0 + i * paso; var E := E0 + j * paso
				for Zb in zonas_bbox:
					if N > Zb[0] and N < Zb[1] and E > Zb[2] and E < Zb[3]: y -= 25; break
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
uniform sampler2D laguna : filter_linear, repeat_disable;       // 1 = Mar Menor (Entorno.laguna), 0 = mar o tierra
uniform vec4 rect_laguna = vec4(0.0, 0.0, 1.0, 1.0);           // E0, N0, ancho, alto del terreno del mundo (m)
uniform float alfa_laguna = 1.0;
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
	// Mar Menor semitransparente: debajo esta la ortofoto con el color real del agua somera y del fondo (como en la web)
	float lg = texture(laguna, vec2((pmundo.x - rect_laguna.x) / rect_laguna.z, 1.0 - (-pmundo.z - rect_laguna.y) / rect_laguna.w)).r;
	ALPHA = mix(1.0, alfa_laguna, lg);
	ROUGHNESS = 0.04; METALLIC = 0.0; SPECULAR = 0.55;
}
"""

## Opacidad del agua del Mar Menor: la misma que Visor.ALFA_LAGUNA de la web (105 / 255).
const ALFA_LAGUNA := 105.0 / 255.0

## Mascara de la laguna (fila 0 = norte) para el shader del mar; sin laguna en el mundo, todo opaco.
func _mascara_laguna(mat: ShaderMaterial) -> void:
	var T: Dictionary = ent.terreno; var Lg: PackedByteArray = ent.laguna
	if Lg.is_empty(): return
	var nN: int = T["nN"]; var nE: int = T["nE"]
	var img := Image.create(nE, nN, false, Image.FORMAT_L8)
	for r in nN:
		for j in nE:
			img.set_pixel(j, r, Color(1, 1, 1) if Lg[(nN - 1 - r) * nE + j] == 1 else Color(0, 0, 0))
	mat.set_shader_parameter("laguna", ImageTexture.create_from_image(img))
	mat.set_shader_parameter("rect_laguna", Vector4(T["E0"], T["N0"], (nE - 1) * T["paso"], (nN - 1) * T["paso"]))
	mat.set_shader_parameter("alfa_laguna", ALFA_LAGUNA)

func _mar() -> void:
	var sh := Shader.new(); sh.code = SHADER_MAR
	var mat := ShaderMaterial.new(); mat.shader = sh
	for k in ["ondas1", "ondas2"]:
		var nt := NoiseTexture2D.new(); nt.width = 512; nt.height = 512; nt.seamless = true; nt.as_normal_map = true
		nt.bump_strength = 6.0 if k == "ondas1" else 3.0; nt.generate_mipmaps = true
		var fn := FastNoiseLite.new(); fn.frequency = 0.012 if k == "ondas1" else 0.025; fn.seed = 7 if k == "ondas1" else 13
		fn.fractal_octaves = 4; nt.noise = fn
		mat.set_shader_parameter(k, nt)
	_mascara_laguna(mat)
	var pm := PlaneMesh.new(); pm.size = Vector2(300000, 300000)
	var mi := _mi(pm, mat, false); mi.position = Vector3(0, -h0 + 0.4, 0); add_child(mi)

# ---------------------------------------------------------------- carreteras (cintas) fuera de la zona de detalle
func _dentro_zona(n: float, e: float, margen: float) -> bool:
	for Z in zonas_bbox:
		if n > Z[0] - margen and n < Z[1] + margen and e > Z[2] - margen and e < Z[3] + margen: return true
	return false

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
	if not _zonas.is_empty() and claro.distance_to(_claro_hecho) > 5 and not sin_("arboles"):
		for zz in _zonas:
			if zz["arboles"] == null: continue
			_zona = zz["nodo"]; _zona_arboles = zz["arboles"]; _arboles_zona(zz["datos"]); zz["arboles"] = _zona_arboles
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
			var it := [ee, nn, 2.0 + r.randf() * 2.0, c.darkened(0.05 + 0.2 * r.randf())]
			if Vector2(ee - cE, nn - cN).length() >= 25: arboles.append(it)      # claro de 25 m en el punto de salida
		n += paso
	# solidos (Entorno.choca_arbol): la copa, una esfera de radio s a 0,75 s del suelo achatada al 80 %
	var solidos := []
	for a in arboles: var y: float = ent.altura(a[1], a[0]); solidos.append([a[0], a[1], 0.9 * a[2], y, y + 1.55 * a[2]])
	ent.poner_arboles("region", solidos)
	_instanciar(_arboles_region, _esfera(6, 3), _mat_copas(), arboles, func(it: Array) -> Array:
		var s: float = it[2]
		var b := Basis(Vector3.UP, s * 5.0).scaled_local(Vector3(s, s * 0.8, s))
		return [Transform3D(b, Vector3(it[0], ent.altura(it[1], it[0]) + s * 0.75, -it[1])), lin(it[3])], 1000.0, 0.0, 7500.0)

# ---------------------------------------------------------------- zona de detalle
## Pone la zona de detalle z = DatosComunes.cargar_zona(...) (o {} para quitarla). El Entorno ya la tiene.
func poner_zona(z: Dictionary) -> void:
	poner_zonas([] if z.is_empty() else [z])

## Pone varias zonas de detalle a la vez (las que hay cerca del punto de lanzamiento; [] para quitarlas). Como
## ponerZonas de visor_real.js. El Entorno ya las tiene (poner_zonas) para que el suelo fisico sea el mismo.
func poner_zonas(lista: Array) -> void:
	var ids := ",".join(lista.map(func(z): return String(z["meta"]["id"])))
	if ids == zona_id and (not _zonas.is_empty() or lista.is_empty()): return
	for zz in _zonas: zz["nodo"].queue_free()
	_zonas = []; _zona = null; _zona_arboles = null; mapa_zonas = []
	ent.quitar_arboles("zona:")                      # los arboles solidos de las zonas que se quitan
	zonas_bbox = lista.map(func(z): return [z["meta"]["N0"], z["meta"]["N0"] + z["meta"]["lado_m"], z["meta"]["E0"], z["meta"]["E0"] + z["meta"]["lado_m"]])
	zona_id = ids
	_terreno_lejano(); _carreteras(); _edificios_sinteticos()
	_arboles_NE = []
	for z in lista:
		_zona = Node3D.new(); add_child(_zona); _zona_datos = z; _zona_arboles = null
		_terreno_zona(z)
		if not sin_("edificios"): _edificios_zona(z)
		if not sin_("arboles"): _arboles_zona(z)
		_zonas.append({ "nodo": _zona, "datos": z, "arboles": _zona_arboles })
	_singulares()                       # despues de las zonas: se asientan en su suelo

var _tex_orto := {}           # texturas de las teselas de la zona que se esta construyendo ("ti_tj")

func _terreno_zona(z: Dictionary) -> void:
	_tex_orto = {}
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
			var tx := _tex_de(String(z["base"]).path_join(nombre), 2 if calidad >= 1 else 1); _tex_orto[str(ti) + "_" + str(tj)] = tx
			mapa_zonas.append({ "tex": tx, "N0": Z["N0"] + ti * Z["orto"]["tesela_m"], "E0": Z["E0"] + tj * Z["orto"]["tesela_m"], "lado": Z["orto"]["tesela_m"] })
			_zona.add_child(_mi(_malla(pos, nor, idx, uv), _mat_suelo(tx), false))

## Edificios del Catastro: cada huella extruida a sus plantas (3 m por planta) desde la cota del terreno. Tejados con la
## propia ortofoto de la zona (la tesela de su centro: cubiertas reales, lucernarios, placas...), fachadas con una ventana
## por planta y modulo de 3,5 m (fachada()) del color claro de siempre o, si la zona lo trae ("f", p. ej. el ladrillo del
## CIFP Politecnico), con ladrillo caravista. Igual que _edificiosZona de visor_real.js.
func _edificios_zona(z: Dictionary) -> void:
	var ruta: String = String(z["base"]).path_join(z["meta"]["edificios"]["archivo"])
	if not FileAccess.file_exists(ruta): return
	var lista = JSON.parse_string(FileAccess.get_file_as_string(ruta))
	if not lista is Array: return
	var Z: Dictionary = z["meta"]; var nt: int = Z["orto"]["teselas"]; var tm: float = Z["orto"]["tesela_m"]
	var fach := { "claro": [PackedVector3Array(), PackedVector3Array(), PackedColorArray(), PackedVector2Array()],
				  "ladrillo": [PackedVector3Array(), PackedVector3Array(), PackedColorArray(), PackedVector2Array()] }
	var tejados := {}
	var crema := lin(Color.hex(0xeee6d8ff)); var r := RandomNumberGenerator.new(); r.seed = 5
	for ed in lista:
		var p: Array = ed["p"]
		if p.size() < 6: continue
		var P := PackedVector2Array()
		for i in range(0, p.size(), 2): P.append(Vector2(p[i], p[i + 1]))
		var y0: float = ed["b"] - h0 - 0.4; var y1: float = ed["b"] - h0 + ed["pl"] * 3.0 + 0.5; var alto := (y1 - y0) / 3.0
		var C := lin(Color.html(ed["c"])) * 1.08; C.a = 1.0
		var es_l: bool = ed.has("f")
		var F: Array = fach["ladrillo" if es_l else "claro"]
		var Cw: Color = Color.WHITE * (0.92 + 0.12 * r.randf()) if es_l else crema.lerp(C, 0.12) * (0.93 + 0.1 * r.randf()); Cw.a = 1.0
		var u := 0.0
		for k in P.size():                      # fachadas: u en modulos de 3,5 m, v en plantas (v = 0 arriba de la textura)
			var a := P[k]; var b := P[(k + 1) % P.size()]; var L := a.distance_to(b); var u0 := u / 3.5; var u1 := (u + L) / 3.5; u += L
			var A0 := Vector3(a.x, y0, -a.y); var B0 := Vector3(b.x, y0, -b.y); var A1 := Vector3(a.x, y1, -a.y); var B1 := Vector3(b.x, y1, -b.y)
			var nn := (B1 - A0).cross(B0 - A0).normalized()
			F[0].append_array([A0, B0, B1, A0, B1, A1]); for q in 6: F[1].append(nn); F[2].append(Cw)
			F[3].append_array([Vector2(u0, alto), Vector2(u1, alto), Vector2(u1, 0), Vector2(u0, alto), Vector2(u1, 0), Vector2(u0, 0)])
		var t := Geometry2D.triangulate_polygon(P)
		var ce := 0.0; var cn := 0.0
		for v in P: ce += v.x; cn += v.y
		ce /= P.size(); cn /= P.size()
		var ti := clampi(int(floor((cn - Z["N0"]) / tm)), 0, nt - 1); var tj := clampi(int(floor((ce - Z["E0"]) / tm)), 0, nt - 1)
		var clave := str(ti) + "_" + str(tj)
		if not tejados.has(clave): tejados[clave] = [PackedVector3Array(), PackedVector2Array(), Z["N0"] + ti * tm, Z["E0"] + tj * tm]
		var T: Array = tejados[clave]
		for q in range(0, t.size(), 3):         # tejado: la foto (en Godot la v de la tesela va de norte = 0 a sur = 1)
			for v in [t[q], t[q + 2], t[q + 1]]:
				T[0].append(Vector3(P[v].x, y1, -P[v].y)); T[1].append(Vector2((P[v].x - T[3]) / tm, 1.0 - (P[v].y - T[2]) / tm))
	for nombre in fach:
		var F: Array = fach[nombre]
		if F[0].is_empty(): continue
		var arr := []; arr.resize(Mesh.ARRAY_MAX); arr[Mesh.ARRAY_VERTEX] = F[0]; arr[Mesh.ARRAY_NORMAL] = F[1]; arr[Mesh.ARRAY_COLOR] = F[2]; arr[Mesh.ARRAY_TEX_UV] = F[3]
		var am := ArrayMesh.new(); am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		var mat := StandardMaterial3D.new(); mat.vertex_color_use_as_albedo = true; mat.albedo_texture = fachada(nombre); mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.roughness = 0.9; mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		var mi := MeshInstance3D.new(); mi.mesh = am; mi.material_override = mat; mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
		_zona.add_child(mi)
	for clave in tejados:
		var T: Array = tejados[clave]
		var nor := PackedVector3Array(); nor.resize(T[0].size()); nor.fill(Vector3.UP)
		var arr := []; arr.resize(Mesh.ARRAY_MAX); arr[Mesh.ARRAY_VERTEX] = T[0]; arr[Mesh.ARRAY_NORMAL] = nor; arr[Mesh.ARRAY_TEX_UV] = T[1]
		var am := ArrayMesh.new(); am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		var mat := StandardMaterial3D.new(); mat.cull_mode = BaseMaterial3D.CULL_DISABLED; mat.roughness = 0.9
		if _tex_orto.has(clave): mat.albedo_texture = _tex_orto[clave]
		else: mat.albedo_color = Color("#b8b0a4")
		var mi := MeshInstance3D.new(); mi.mesh = am; mi.material_override = mat; mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
		_zona.add_child(mi)

## Textura de un modulo de fachada (3,5 m por una planta de 3 m) que se repite: "claro" (pared blanca que tine el color
## del vertice, ventana de 2,1 x 1,2 m con marco) o "ladrillo" (caravista rojo con llagas y una ventana alta apaisada,
## como los talleres del CIFP). La misma que Visor.texturaFachada de visor_real.js.
static var _fachadas := {}
static func fachada(tipo: String) -> ImageTexture:
	if _fachadas.has(tipo): return _fachadas[tipo]
	var N := 128; var img := Image.create(N, N, false, Image.FORMAT_RGB8); var r := RandomNumberGenerator.new(); r.seed = 61 if tipo == "ladrillo" else 43
	var ven: Array = [44, 84, 22, 42] if tipo == "ladrillo" else [26, 102, 36, 87]      # x0, x1, y0, y1 (fila 0 = arriba de la planta)
	var lad := []
	if tipo == "ladrillo":
		for k in 32 * 9: lad.append(0.85 + 0.25 * r.randf())
	for y in N:
		for x in N:
			var c: Color
			if tipo == "ladrillo":           # hiladas de 4 px (7 cm), ladrillos de 15 px a soga
				var f := y >> 2; var xo := (x + (f & 1) * 7) % N; var k := mini(8, xo / 15); var tt: float = lad[f * 9 + k]
				c = Color8(196, 182, 164) if ((y & 3) == 3 or xo % 15 == 14) else Color8(int(164 * tt), int(85 * tt), int(63 * tt))
			else:
				var tt := 0.96 + 0.04 * r.randf(); c = Color8(int(244 * tt), int(241 * tt), int(236 * tt))
			if x >= ven[0] and x < ven[1] and y >= ven[2] and y < ven[3]:
				var marco: bool = x < ven[0] + 2 or x >= ven[1] - 2 or y < ven[2] + 2 or y >= ven[3] - 2 or absf(x - (ven[0] + ven[1]) / 2.0) < 1
				var fy: float = float(y - ven[2]) / (ven[3] - ven[2])
				c = Color8(205, 205, 200) if marco else Color8(int(58 + 30 * fy), int(72 + 30 * fy), int(86 + 28 * fy))
			if y >= ven[3] and y < ven[3] + 2 and x >= ven[0] - 2 and x < ven[1] + 2: c = Color8(215, 210, 200)      # alfeizar
			img.set_pixel(x, y, c)
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img); _fachadas[tipo] = t
	return t

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
## Rejilla de 40 m con los poligonos (E, N) de los edificios de una zona que tocan cada celda, para quitar los arboles
## que caen dentro (la deteccion de copas en la ortofoto confunde a veces cubiertas y patios con arboles).
func _rejilla_edificios(z: Dictionary) -> Dictionary:
	var rej := {}
	var ruta: String = String(z["base"]).path_join(z["meta"]["edificios"]["archivo"])
	if not FileAccess.file_exists(ruta): return rej
	var lista = JSON.parse_string(FileAccess.get_file_as_string(ruta))
	if not lista is Array: return rej
	for ed in lista:
		var p: Array = ed["p"]
		if p.size() < 6: continue
		var poli := PackedVector2Array(); var e0 := INF; var e1 := -INF; var n0 := INF; var n1 := -INF
		for i in range(0, p.size(), 2):
			poli.append(Vector2(p[i], p[i + 1])); e0 = minf(e0, p[i]); e1 = maxf(e1, p[i]); n0 = minf(n0, p[i + 1]); n1 = maxf(n1, p[i + 1])
		for i in range(int(floor((e0 - 4) / 40.0)), int(floor((e1 + 4) / 40.0)) + 1):
			for j in range(int(floor((n0 - 4) / 40.0)), int(floor((n1 + 4) / 40.0)) + 1):
				var k := Vector2i(i, j)
				if not rej.has(k): rej[k] = []
				rej[k].append(poli)
	return rej

## true si un arbol (centro E, N y radio de copa rc) cae dentro de un edificio o con el centro a menos de media copa de
## su borde (la copa se meteria en el muro). Lo mismo que _filtroEdificios de visor_real.js.
static func _en_edificio(rej: Dictionary, e: float, n: float, rc: float) -> bool:
	var pt := Vector2(e, n)
	for poli in rej.get(Vector2i(int(floor(e / 40.0)), int(floor(n / 40.0))), []):
		if Geometry2D.is_point_in_polygon(pt, poli): return true
		for i in poli.size():
			var a: Vector2 = poli[i]; var b: Vector2 = poli[(i + 1) % poli.size()]
			if pt.distance_squared_to(Geometry2D.get_closest_point_to_segment(pt, a, b)) < 0.25 * rc * rc: return true
	return false

func _arboles_zona(z: Dictionary) -> void:
	if _zona_arboles: _zona_arboles.queue_free()
	var padre := Node3D.new(); _zona.add_child(padre); _zona_arboles = padre; _claro_hecho = claro
	var ruta: String = String(z["base"]).path_join(z["meta"]["arboles"]["archivo"])
	if not FileAccess.file_exists(ruta): return
	var A := FileAccess.get_file_as_bytes(ruta).to_float32_array()
	var arboles := []; var matas := []; var r := RandomNumberGenerator.new(); r.seed = 29
	var rej := _rejilla_edificios(z); var solidos := []
	# sin arboles donde no los hay aunque la ortofoto lo parezca (escenarios.js, "sin_arboles": el aparcamiento del CIFP)
	var claros := []
	for id in Escenarios.datos():
		var Es: Dictionary = Escenarios.datos()[id]
		if Es.get("mundo", "") != m.get("id", ""): continue
		for dd in Es.get("destacados", []):
			if not dd.has("sin_arboles"): continue
			var pol := PackedVector2Array()
			for q in dd["sin_arboles"]: pol.append(Vector2(q[1], q[0]))
			claros.append(pol)
	for i in range(0, A.size(), 3):
		var it := [A[i], A[i + 1], A[i + 2], r.randf(), r.randf(), r.randf(), r.randf()]
		if Vector2(A[i] - claro.x, A[i + 1] - claro.y).length() < 25 + A[i + 2]: continue      # el claro del piloto
		if _en_edificio(rej, A[i], A[i + 1], A[i + 2]): continue                                 # ni dentro de los edificios ni en sus muros
		if claros.any(func(pol): return Geometry2D.is_point_in_polygon(Vector2(A[i], A[i + 1]), pol)): continue
		if A[i + 2] >= 1.3: solidos.append([A[i], A[i + 1]] + Entorno.arbol_zona(A[i + 2], ent.altura(A[i + 1], A[i])))
		if A[i + 2] < 1.3: matas.append(it)
		else: arboles.append(it)
	ent.poner_arboles("zona:" + String(z["meta"]["id"]), solidos)     # solidos (Entorno.choca_arbol)
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

# ---------------------------------------------------------------- elementos singulares (simulador/singulares.js)
## Elementos singulares del mundo (simulador/singulares.js, comun con la web: la entrada del CIFP Politecnico...), con
## las mismas piezas y texturas que _singulares de visor_real.js.
static var _singulares_datos = null
static func singulares_datos() -> Array:
	if _singulares_datos != null: return _singulares_datos
	_singulares_datos = []
	var t := FileAccess.get_file_as_string(DatosComunes.carpeta().path_join("singulares.js"))
	var re := RegEx.new(); re.compile("(?m)^window[.]SINGULARES = ")
	var mm := re.search(t)
	if mm != null:
		var resto := t.substr(mm.get_end()); var d = JSON.parse_string(resto.substr(0, resto.rfind("]") + 1))
		if d is Array: _singulares_datos = d
	return _singulares_datos

# ---------------------------------------------------------------- trabajos del modo Operaciones
## Lo que hay que ver en un trabajo (escenarios.js, "operacion"; las reglas en operaciones.gd), o {} para quitarlo: la
## plataforma de despegue, las placas numeradas de la inspeccion, los jalones de la parcela o de la zona de busqueda, el
## senderista, las manchas de plaga y las torres y cables de la linea (ponerOperacion de visor_real.js). casa: [N, E].
var _op: Node3D
func poner_operacion(d: Dictionary, casa: Array) -> void:
	if _op: _op.queue_free(); _op = null
	if d.is_empty(): return
	var G := Node3D.new(); add_child(G); _op = G
	var alt := func(n: float, e: float) -> float: return ent.altura(n, e)
	var std := func(c: Color, metal := 0.0, rug := 0.8) -> StandardMaterial3D:
		var mt := StandardMaterial3D.new(); mt.albedo_color = c; mt.metallic = metal; mt.roughness = rug; return mt
	var en := func(mesh: Mesh, mt: Material, N: float, E: float, y: float, padre: Node3D = G) -> MeshInstance3D:
		var mi := MeshInstance3D.new(); mi.mesh = mesh; mi.material_override = mt; mi.position = Vector3(E, y, -N); padre.add_child(mi); return mi
	var plano := func(c: Color) -> StandardMaterial3D:
		var mt := StandardMaterial3D.new(); mt.albedo_color = c; mt.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; mt.cull_mode = BaseMaterial3D.CULL_DISABLED; return mt
	var placa := func(N: float, E: float, y: float, texto: String, lado: float, rot: Vector3, padre: Node3D = G) -> void:
		var P := Node3D.new(); P.position = Vector3(E, y, -N); P.rotation = rot; padre.add_child(P)
		var img := Image.create(64, 64, false, Image.FORMAT_RGB8); img.fill(Color.html("#ff6d00")); img.fill_rect(Rect2i(4, 4, 56, 56), Color.WHITE); img.fill_rect(Rect2i(8, 8, 48, 48), Color.html("#ff6d00"))
		var mt := StandardMaterial3D.new(); mt.albedo_texture = ImageTexture.create_from_image(img); mt.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; mt.cull_mode = BaseMaterial3D.CULL_DISABLED
		var q := QuadMesh.new(); q.size = Vector2(lado, lado); var mi := MeshInstance3D.new(); mi.mesh = q; mi.material_override = mt; P.add_child(mi)
		for s in [1.0, -1.0]:
			var l := Label3D.new(); l.text = texto; l.font_size = 96; l.pixel_size = lado / 160.0; l.outline_size = 0; l.modulate = Color.WHITE; l.font = Tema.negrita
			l.double_sided = false; l.position = Vector3(0, 0, 0.01 * s); l.rotation.y = 0.0 if s > 0 else PI; P.add_child(l)
	var jalon := func(N: float, E: float, c1: Color) -> void:            # jalon de 2 m a franjas con banderin
		var y: float = alt.call(N, E); var img := Image.create(8, 64, false, Image.FORMAT_RGB8)
		for i in 8: img.fill_rect(Rect2i(0, i * 8, 8, 8), Color.WHITE if i % 2 else c1)
		var mt := StandardMaterial3D.new(); mt.albedo_texture = ImageTexture.create_from_image(img)
		var cm := CylinderMesh.new(); cm.top_radius = 0.03; cm.bottom_radius = 0.03; cm.height = 2; cm.radial_segments = 8
		en.call(cm, mt, N, E, y + 1)
		var qm := QuadMesh.new(); qm.size = Vector2(0.5, 0.35); var b: MeshInstance3D = en.call(qm, plano.call(c1), N, E, y + 1.8); b.position.x += 0.25
	var esquinas := func(P: Dictionary, c1: Color) -> void:
		for ne in [[P["n0"], P["e0"]], [P["n0"], P["e1"]], [P["n1"], P["e0"]], [P["n1"], P["e1"]]]: jalon.call(ne[0], ne[1], c1)
	# plataforma de despegue (a la que hay que volver)
	var pad := CylinderMesh.new(); pad.top_radius = 0.75; pad.bottom_radius = 0.75; pad.height = 0.03; pad.radial_segments = 32
	en.call(pad, std.call(Color.html("#ff6d00")), casa[0], casa[1], alt.call(casa[0], casa[1]) + 0.04)
	var lh := Label3D.new(); lh.text = "H"; lh.font_size = 96; lh.pixel_size = 0.009; lh.font = Tema.negrita; lh.modulate = Color.WHITE; lh.outline_size = 0
	lh.rotation = Vector3(-PI / 2, 0, 0); lh.position = Vector3(casa[1], alt.call(casa[0], casa[1]) + 0.06, -casa[0]); G.add_child(lh)
	var pts: Array = d.get("puntos", [])
	for i in pts.size():                                               # inspeccion: placas naranjas numeradas
		var q: Dictionary = pts[i]; var y: float = q["cota"] - h0 if q.has("cota") else alt.call(q["n"], q["e"]) + float(q.get("h", 0.0))
		if q.has("normal"):
			var r: float = q["normal"] * PI / 180
			placa.call(q["n"] + 0.06 * cos(r), q["e"] + 0.06 * sin(r), y, str(i + 1), 1.5, Vector3(0, PI - r, 0))
		else: placa.call(q["n"], q["e"], y + 0.06, str(i + 1), 1.5, Vector3(-PI / 2, 0, 0))
	if d.has("parcela"): esquinas.call(d["parcela"], Color.html("#e53935" if d.has("solape") else "#2e7d32"))
	if d.has("solape"):                                                # dianas de apoyo de la fotogrametria
		var P: Dictionary = d["parcela"]
		var img := Image.create(64, 64, false, Image.FORMAT_RGB8); img.fill(Color.WHITE); img.fill_rect(Rect2i(0, 0, 32, 32), Color.html("#111111")); img.fill_rect(Rect2i(32, 32, 32, 32), Color.html("#111111"))
		var mt := StandardMaterial3D.new(); mt.albedo_texture = ImageTexture.create_from_image(img); mt.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		for ne in [[P["n0"] + 15, P["e0"] + 15], [P["n0"] + 15, P["e1"] - 15], [P["n1"] - 15, P["e0"] + 15], [P["n1"] - 15, P["e1"] - 15], [(P["n0"] + P["n1"]) / 2, (P["e0"] + P["e1"]) / 2]]:
			var pm := PlaneMesh.new(); pm.size = Vector2(1.2, 1.2); en.call(pm, mt, ne[0], ne[1], alt.call(ne[0], ne[1]) + 0.05)
	if d.has("zona"):                                                  # busqueda: jalones amarillos y el senderista
		esquinas.call(d["zona"], Color.html("#fdd835"))
		if d.has("persona"):
			var N: float = d["persona"][0]; var E: float = d["persona"][1]; var P := Node3D.new(); P.position = Vector3(E, alt.call(N, E), -N); P.rotation.y = 0.7; G.add_child(P)
			var parte := func(mesh: Mesh, c: Color, pos: Vector3, rz := 0.0) -> void:
				var mi := MeshInstance3D.new(); mi.mesh = mesh; mi.material_override = std.call(c); mi.position = pos; mi.rotation.z = rz; P.add_child(mi)
			var cil := func(rt: float, rb: float, h: float) -> CylinderMesh:
				var c := CylinderMesh.new(); c.top_radius = rt; c.bottom_radius = rb; c.height = h; c.radial_segments = 10; return c
			for s in [-0.1, 0.1]: parte.call(cil.call(0.08, 0.07, 0.85), Color.html("#2b3440"), Vector3(s, 0.43, 0))
			parte.call(cil.call(0.2, 0.17, 0.62), Color.html("#d32f2f"), Vector3(0, 1.16, 0))
			var cab := SphereMesh.new(); cab.radius = 0.12; cab.height = 0.24; parte.call(cab, Color.html("#c68b6e"), Vector3(0, 1.6, 0))
			var mo := BoxMesh.new(); mo.size = Vector3(0.32, 0.45, 0.2); parte.call(mo, Color.html("#ff8f00"), Vector3(0, 1.2, 0.2))
			for s in [-1.0, 1.0]: parte.call(cil.call(0.06, 0.05, 0.6), Color.html("#d32f2f"), Vector3(s * 0.27, 1.12, 0), s * 0.2)
	var manchas: Array = d.get("manchas", [])
	for i in manchas.size():                                           # agricultura: rodales amarillos en el cultivo
		var N: float = manchas[i][0]; var E: float = manchas[i][1]; var r: float = manchas[i][2]
		var pol := PackedVector2Array()
		for k in 24:
			var a := k / 24.0 * TAU; var rr := r * (0.82 + 0.18 * sin(3 * a + i) * cos(2 * a - i)); pol.append(Vector2(rr * cos(a), -rr * sin(a)))
		var idx := Geometry2D.triangulate_polygon(pol); var pos := PackedVector3Array(); var nor := PackedVector3Array()
		for k in idx: pos.append(Vector3(pol[k].x, 0, pol[k].y)); nor.append(Vector3.UP)
		var am := ArrayMesh.new(); var arr := []; arr.resize(Mesh.ARRAY_MAX); arr[Mesh.ARRAY_VERTEX] = pos; arr[Mesh.ARRAY_NORMAL] = nor
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		var mt := StandardMaterial3D.new(); mt.albedo_color = Color(Color.html("#c9b13a"), 0.85); mt.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; mt.cull_mode = BaseMaterial3D.CULL_DISABLED
		en.call(am, mt, N, E, alt.call(N, E) + 0.12)
	if d.has("torres"):                                                # linea: torres de celosia, crucetas, aisladores y cables
		var op := Operacion.new(d, func(_a, _b): pass, func(_a, _b): pass, { "casa": casa, "suelo": alt, "h0": h0 })
		var acero: StandardMaterial3D = std.call(Color.html("#9ea4a8"), 0.5, 0.5)
		var barra := func(A: Array, B: Array, r: float, mt: Material) -> void:
			var a := Vector3(A[1], A[2], -A[0]); var b := Vector3(B[1], B[2], -B[0]); var L := a.distance_to(b)
			var c := CylinderMesh.new(); c.top_radius = r; c.bottom_radius = r; c.height = L; c.radial_segments = 6; c.rings = 0
			var mi := MeshInstance3D.new(); mi.mesh = c; mi.material_override = mt; G.add_child(mi)
			var dirv := (b - a).normalized(); var eje := Vector3.UP.cross(dirv)
			mi.transform = Transform3D(Basis(eje.normalized(), Vector3.UP.angle_to(dirv)) if eje.length() > 1e-6 else Basis(), (a + b) / 2)
		var TT: Array = d["torres"]
		for i in TT.size():
			var tn: float = TT[i][0]; var te: float = TT[i][1]; var b0: float = op.bases[i]; var L: Array = op.laterales[i]; var F := [L[1], -L[0]]
			var pata := func(s: float, t: float, h: float) -> Array:
				var w: float = 1.3 - 0.75 * h / d["alto"]; return [tn + (s * L[0] + t * F[0]) * w, te + (s * L[1] + t * F[1]) * w, b0 + h]
			for st in [[-1, -1], [-1, 1], [1, -1], [1, 1]]: barra.call(pata.call(st[0], st[1], 0), pata.call(st[0], st[1], d["alto"] - 1), 0.07, acero)
			var h := 0.0
			while h < d["alto"] - 2:
				for c in [[-1, -1, 1, -1], [-1, 1, 1, 1], [-1, -1, -1, 1], [1, -1, 1, 1]]:
					barra.call(pata.call(c[0], c[1], h), pata.call(c[2], c[3], h + 4), 0.03, acero); barra.call(pata.call(c[2], c[3], h), pata.call(c[0], c[1], h + 4), 0.03, acero)
				h += 4
			barra.call([tn + L[0] * d["brazo"], te + L[1] * d["brazo"], b0 + d["fases"] + 1.2], [tn - L[0] * d["brazo"], te - L[1] * d["brazo"], b0 + d["fases"] + 1.2], 0.09, acero)
			barra.call(pata.call(0, 0, d["alto"] - 1), [tn, te, b0 + d["alto"]], 0.08, acero)
			for k in [0, 1]:
				var A: Array = op.enganches[i][k]; barra.call([A[0], A[1], A[2] + 1.2], A, 0.07, std.call(Color.html("#8d6e63")))
		var mc: StandardMaterial3D = std.call(Color.html("#2f3133"), 0.6, 0.4)
		for c in op.cables: barra.call(c[0], c[1], 0.025, mc)

var _sing: Node3D
func _singulares() -> void:
	if _sing: _sing.queue_free()
	_sing = Node3D.new(); add_child(_sing)
	var alt := func(n: float, e: float) -> float: return ent.altura(n, e)
	var mat := func(tex: Texture2D, escala: float, metal := 0.0, rug := 0.9) -> StandardMaterial3D:
		var mt := StandardMaterial3D.new(); mt.albedo_texture = tex; mt.uv1_triplanar = true; mt.uv1_world_triplanar = true
		mt.uv1_scale = Vector3.ONE / escala; mt.metallic = metal; mt.roughness = rug; mt.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		return mt
	var color := func(c: Color, metal := 0.0, rug := 0.9) -> StandardMaterial3D:
		var mt := StandardMaterial3D.new(); mt.albedo_color = c; mt.metallic = metal; mt.roughness = rug; return mt
	var pon := func(mesh: Mesh, mt: Material, pos: Vector3, rot_y := 0.0, padre: Node3D = null) -> MeshInstance3D:
		var mi := MeshInstance3D.new(); mi.mesh = mesh; mi.material_override = mt; mi.position = pos; mi.rotation.y = rot_y
		(padre if padre else _sing).add_child(mi); return mi
	for S in singulares_datos():
		if S["mundo"] != m.get("id", ""): continue
		for p in S["piezas"]:
			match String(p["tipo"]):
				"muro":
					var de: float = p["e1"] - p["e0"]; var dn: float = p["n1"] - p["n0"]; var L := Vector2(de, dn).length()
					var y0: float = minf(alt.call(p["n0"], p["e0"]), alt.call(p["n1"], p["e1"])) - 0.3; var h: float = p["alto"] + 0.3
					var bm := BoxMesh.new(); bm.size = Vector3(L, h, p["grosor"])
					pon.call(bm, mat.call(textura_singular(p["textura"]), 1.6), Vector3((p["e0"] + p["e1"]) / 2, y0 + h / 2, -(p["n0"] + p["n1"]) / 2), atan2(dn, de))
				"cilindro":
					var y0: float = alt.call(p["n"], p["e"]) - 0.3; var h: float = p["alto"] + 0.3
					var cm := CylinderMesh.new(); cm.top_radius = p["radio"]; cm.bottom_radius = p["radio"]; cm.height = h; cm.radial_segments = 40
					pon.call(cm, mat.call(textura_singular(p["textura"]), 2.4), Vector3(p["e"], y0 + h / 2, -p["n"]))
				"disco":
					var c := Node3D.new(); c.position = Vector3(p["e"], alt.call(p["n"], p["e"]) + p["h"], -p["n"]); c.rotation.y = PI - deg_to_rad(p["rumbo"]); _sing.add_child(c)
					var cm := CylinderMesh.new(); cm.top_radius = p["radio"]; cm.bottom_radius = p["radio"]; cm.height = 0.04; cm.radial_segments = 48
					var mi: MeshInstance3D = pon.call(cm, mat.call(textura_singular("rejilla"), 0.9, 0.4, 0.5), Vector3.ZERO, 0.0, c); mi.rotation.x = PI / 2
					var tm := TorusMesh.new(); tm.inner_radius = p["radio"] - 0.06; tm.outer_radius = p["radio"] + 0.06
					var ar: MeshInstance3D = pon.call(tm, color.call(Color("#2b2f33"), 0.5, 0.4), Vector3.ZERO, 0.0, c); ar.rotation.x = PI / 2
				"cartel":
					_cartel(p, Vector3(p["e"], alt.call(p["n"], p["e"]) + p["h"], -p["n"]), PI - deg_to_rad(p["rumbo"]))
				"marquesina":
					var y: float = alt.call((p["n0"] + p["n1"]) / 2, (p["e0"] + p["e1"]) / 2); var ancho: float = p["e1"] - p["e0"] + p["vuelo"]; var fondo: float = p["n1"] - p["n0"]
					var acero: StandardMaterial3D = color.call(Color("#3a3f45"), 0.6, 0.45); var cx: float = (p["e0"] - p["vuelo"] + p["e1"]) / 2
					var bm := BoxMesh.new(); bm.size = Vector3(ancho, 0.22, fondo)
					pon.call(bm, color.call(Color("#d9dcdf"), 0.3, 0.5), Vector3(cx, y + p["h"], -(p["n0"] + p["n1"]) / 2))
					for k in 5:                 # cerchas metalicas bajo el techo
						var v := BoxMesh.new(); v.size = Vector3(ancho, 0.5, 0.08)
						pon.call(v, acero, Vector3(cx, y + p["h"] - 0.35, -(p["n0"] + 0.2 + k * (fondo - 0.4) / 4)))
					for n in [p["n0"] + 0.25, p["n1"] - 0.25]:      # pilares de la parte que vuela
						var cm := CylinderMesh.new(); cm.top_radius = 0.11; cm.bottom_radius = 0.11; cm.height = p["h"]; cm.radial_segments = 10
						pon.call(cm, acero, Vector3(p["e0"] - p["vuelo"] + 0.3, y + p["h"] / 2, -n))
				"submarino":
					var y: float = alt.call(p["n"], p["e"]); var metal: StandardMaterial3D = color.call(Color("#a7aeb5"), 0.35, 0.38)
					var g := Node3D.new(); g.position = Vector3(p["e"], y + p["peana"] + 0.9 + p["radio"], -p["n"]); g.rotation.y = -deg_to_rad(p["rumbo"]); _sing.add_child(g)
					pon.call(_casco_submarino(p["largo"], p["radio"]), metal, Vector3.ZERO, 0.0, g)
					var tc := CylinderMesh.new(); tc.top_radius = 0.22; tc.bottom_radius = 0.26; tc.height = 0.42
					pon.call(tc, metal, Vector3(0, p["radio"] + 0.12, -0.6), 0.0, g)
					var tb := BoxMesh.new(); tb.size = Vector3(0.05, 0.5, 0.35); pon.call(tb, metal, Vector3(0, 0, p["largo"] / 2 - 0.25), 0.0, g)
					var he := TorusMesh.new(); he.inner_radius = 0.19; he.outer_radius = 0.25
					var hm: MeshInstance3D = pon.call(he, metal, Vector3(0, 0, p["largo"] / 2 - 0.05), 0.0, g); hm.rotation.x = PI / 2
					var pb := BoxMesh.new(); pb.size = Vector3(1.4, p["peana"], 2.4)
					pon.call(pb, color.call(Color("#8f9499"), 0.0, 0.85), Vector3(p["e"], y + p["peana"] / 2, -p["n"]), g.rotation.y)
					var po := CylinderMesh.new(); po.top_radius = 0.06; po.bottom_radius = 0.08; po.height = 0.95
					pon.call(po, metal, Vector3(p["e"], y + p["peana"] + 0.47, -p["n"]))
				"mastil":
					var y: float = alt.call(p["n"], p["e"])
					var cm := CylinderMesh.new(); cm.top_radius = 0.035; cm.bottom_radius = 0.05; cm.height = p["alto"]; cm.radial_segments = 10
					pon.call(cm, color.call(Color("#d8dadc"), 0.6, 0.3), Vector3(p["e"], y + p["alto"] / 2, -p["n"]))
					var qm := QuadMesh.new(); qm.size = Vector2(1.5, 1.0)
					var mb := StandardMaterial3D.new(); mb.albedo_texture = textura_bandera(p["bandera"]); mb.cull_mode = BaseMaterial3D.CULL_DISABLED; mb.roughness = 0.8
					pon.call(qm, mb, Vector3(p["e"], y + p["alto"] - 0.6, -(p["n"] - 0.78)), PI / 2)      # ondea hacia el sur: de cara al aparcamiento
	for mi in _sing.find_children("*", "MeshInstance3D", true, false): (mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

## Casco del submarino: torno de un perfil de puro (como LatheGeometry en la web), eje a lo largo de z.
static func _casco_submarino(largo: float, radio: float) -> ArrayMesh:
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES); var seg := 32
	var perfil := []
	for k in 25:
		var t := k / 24.0; var r := radio * pow(sin(PI * minf(1, t * 1.15)), 0.62) * (1.0 if t < 0.87 else 1 - (t - 0.87) / 0.13 * 0.9)
		perfil.append(Vector2(maxf(0.01, r), (t - 0.5) * largo))
	for k in perfil.size() - 1:
		for s in seg:
			var a0 := TAU * s / seg; var a1 := TAU * (s + 1) / seg; var p0: Vector2 = perfil[k]; var p1: Vector2 = perfil[k + 1]
			var v := [Vector3(p0.x * cos(a0), p0.x * sin(a0), p0.y), Vector3(p0.x * cos(a1), p0.x * sin(a1), p0.y), Vector3(p1.x * cos(a1), p1.x * sin(a1), p1.y), Vector3(p1.x * cos(a0), p1.x * sin(a0), p1.y)]
			for q in [0, 2, 1, 0, 3, 2]:
				var w: Vector3 = v[q]; st.set_normal(Vector3(w.x, w.y, 0).normalized()); st.add_vertex(w)
	return st.commit()

## Cartel: imagen del panel (marco claro, cuadro naranja con engranaje, panel gris oscuro) y el texto con Label3D (Godot
## no escribe texto en una imagen): mismas medidas y colores que Visor.texturaCartel de la web.
func _cartel(p: Dictionary, pos: Vector3, rot_y: float) -> void:
	var c := Node3D.new(); c.position = pos; c.rotation.y = rot_y; _sing.add_child(c)
	var ancho: float = p["ancho"]; var alto: float = p["alto"]; var H := 256; var W := int(round(H * ancho / alto)); var k: float = alto / H
	var qm := QuadMesh.new(); qm.size = Vector2(ancho, alto)
	var mt := StandardMaterial3D.new(); mt.albedo_texture = textura_cartel(W, H); mt.roughness = 0.6
	var mi := MeshInstance3D.new(); mi.mesh = qm; mi.material_override = mt; c.add_child(mi)
	var fondo := BoxMesh.new(); fondo.size = Vector3(ancho + 0.08, alto + 0.08, 0.08)
	var fm := MeshInstance3D.new(); fm.mesh = fondo; var mf := StandardMaterial3D.new(); mf.albedo_color = Color("#e8e8e4"); fm.material_override = mf; fm.position.z = -0.05; c.add_child(fm)
	var m_ := 10; var lado := H - 2 * m_; var x0 := m_ + lado + 8; var disp := (W - x0 - m_ - 44) * k
	var total := 0.0
	for l in p["lineas"]: total += float(l[2])
	var esc := (H - 2 * m_ - 28) / total; var y := float(m_ + 14)
	for l in p["lineas"]:
		var px: float = float(l[2]) * esc; var f := int(round(px * 0.92))
		var lab := Label3D.new(); lab.text = l[0]; lab.font = Tema.negrita if Tema.negrita else null; lab.font_size = f; lab.pixel_size = k
		lab.modulate = Color(l[1]); lab.outline_size = 0; lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT; lab.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		lab.double_sided = false; lab.shaded = true
		var ancho_txt := (lab.font if lab.font else ThemeDB.fallback_font).get_string_size(l[0], HORIZONTAL_ALIGNMENT_LEFT, -1, f).x * k
		if ancho_txt > disp: lab.font_size = int(floor(f * disp / ancho_txt)); f = lab.font_size
		lab.position = Vector3(-ancho / 2 + (x0 + 22) * k, alto / 2 - (y + (px - f) / 2.0) * k, 0.02)
		c.add_child(lab); y += px

static func textura_cartel(W: int, H: int) -> ImageTexture:
	var img := Image.create(W, H, false, Image.FORMAT_RGB8); img.fill(Color8(244, 244, 242))
	var m_ := 10; var lado := H - 2 * m_; var cx := m_ + lado / 2.0; var cy := m_ + lado / 2.0
	img.fill_rect(Rect2i(m_, m_, lado, lado), Color8(236, 122, 38))
	for y in range(m_, m_ + lado):
		for x in range(m_, m_ + lado):
			var dx := (x - cx) / lado; var dy := (y - cy) / lado; var r := Vector2(dx, dy).length(); var a := fposmod(atan2(dy, dx), TAU)
			var diente := 0.38 if int(floor(a / (TAU / 24))) % 2 == 0 else 0.30
			var blanco := r < diente and r > 0.14
			var ca := cos(0.6); var sa := sin(0.6); var ex := (dx * ca + dy * sa) / 0.46; var ey := (-dx * sa + dy * ca) / 0.17
			if absf(sqrt(ex * ex + ey * ey) - 1.0) < 0.05: blanco = true          # la orbita del atomo
			if blanco: img.set_pixel(x, y, Color.WHITE)
	var x0 := m_ + lado + 8
	img.fill_rect(Rect2i(x0, m_, W - x0 - m_, H - 2 * m_), Color8(61, 66, 71))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

## Texturas de los singulares: "bloque" (bloque de hormigon de 40 x 20 cm, 1,6 m por textura), "hormigon" (2,4 m, con
## manchas), "rejilla" (lamas verticales), "sillar" (piedra del faro) y "linterna" (cristal con montantes). Las mismas que
## Visor.texturaSingular de la web.
static var _tex_sing := {}
static func textura_singular(tipo: String) -> ImageTexture:
	if _tex_sing.has(tipo): return _tex_sing[tipo]
	var N := 256; var img := Image.create(N, N, false, Image.FORMAT_RGB8); var r := RandomNumberGenerator.new(); r.seed = 71 if tipo == "bloque" else (73 if tipo == "hormigon" else 79)
	var tonos := []
	for k in 64: tonos.append(0.9 + 0.14 * r.randf())
	for y in N:
		for x in N:
			var c: Color
			if tipo == "bloque":
				var f := y >> 5; var xo := (x + (f & 1) * 32) % N; var k := (f * 4 + (xo >> 6)) % 64; var junta := (y & 31) >= 30 or (xo & 63) >= 62
				var t: float = tonos[k] * (0.94 + 0.12 * r.randf())
				c = Color8(int(150 * t / tonos[k]), int(150 * t / tonos[k]), int(146 * t / tonos[k])) if junta else Color8(int(minf(255, 190 * t)), int(minf(255, 190 * t)), int(minf(255, 185 * t)))
			elif tipo == "hormigon":
				var mancha := 0.88 + 0.12 * sin(x * 0.05 + sin(y * 0.03) * 2) * sin(y * 0.021); var gr := 0.95 + 0.08 * r.randf()
				c = Color8(int(minf(255, 205 * mancha * gr)), int(minf(255, 200 * mancha * gr)), int(minf(255, 190 * mancha * gr)))
			elif tipo == "sillar":         # sillares de piedra (faro): 3 a lo ancho, 6 hiladas, a matajuntas
				var f := y / 43; var xo := (x + (f & 1) * 43) % N; var k := (f * 3 + xo / 86) % 64; var junta := y % 43 >= 41 or xo % 86 >= 84
				var gr := 0.93 + 0.12 * r.randf()
				c = Color8(int(168 * gr), int(164 * gr), int(152 * gr)) if junta else Color8(int(minf(255, 196 * tonos[k] * gr)), int(minf(255, 190 * tonos[k] * gr)), int(minf(255, 176 * tonos[k] * gr)))
			elif tipo == "linterna":       # linterna del faro: cristal oscuro con montantes blancos
				c = Color8(236, 236, 230) if (x & 31) < 4 or y < 12 else Color8(int(48 + y * 0.12), int(66 + y * 0.12), int(82 + y * 0.1))
			else:
				c = Color8(62, 66, 70) if (x & 15) < 9 else Color8(22, 24, 26)
			img.set_pixel(x, y, c)
	img.generate_mipmaps()
	var tx := ImageTexture.create_from_image(img); _tex_sing[tipo] = tx
	return tx

## Banderas (3 x 2): "es", "ue" y "murcia" (simplificada), como Visor.texturaBandera.
static var _tex_band := {}
static func textura_bandera(tipo: String) -> ImageTexture:
	if _tex_band.has(tipo): return _tex_band[tipo]
	var W := 192; var H := 128; var img := Image.create(W, H, false, Image.FORMAT_RGB8)
	if tipo == "es":
		img.fill(Color8(198, 11, 30)); img.fill_rect(Rect2i(0, H / 4, W, H / 2), Color8(255, 196, 0))
	elif tipo == "ue":
		img.fill(Color8(0, 51, 153))
		for k in 12:
			var a := TAU * k / 12.0; var cx := W / 2.0 + cos(a) * 38; var cy := H / 2.0 + sin(a) * 38
			for y in range(int(cy) - 7, int(cy) + 8):
				for x in range(int(cx) - 7, int(cx) + 8):
					var b := atan2(y - cy, x - cx) + PI / 2; var rr := Vector2(x - cx, y - cy).length()
					var lim := 2.6 + (6.5 - 2.6) * pow(absf(cos(2.5 * b)), 3)          # estrella de 5 puntas
					if rr < lim: img.set_pixel(x, y, Color8(255, 204, 0))
	else:
		img.fill(Color8(155, 27, 48)); var oro := Color8(242, 194, 48)
		for q in [[10, 10], [34, 10], [10, 34], [34, 34]]:                   # castillos
			img.fill_rect(Rect2i(q[0], q[1] + 6, 18, 12), oro); img.fill_rect(Rect2i(q[0] + 2, q[1] + 2, 4, 5), oro); img.fill_rect(Rect2i(q[0] + 12, q[1] + 2, 4, 5), oro)
		for k in 7:                                                            # coronas
			var x := 150 + (k % 2) * 16; var y := 14 + k * 15
			img.fill_rect(Rect2i(x, y + 4, 12, 4), oro); img.fill_rect(Rect2i(x, y, 2, 4), oro); img.fill_rect(Rect2i(x + 5, y, 2, 4), oro); img.fill_rect(Rect2i(x + 10, y, 2, 4), oro)
	img.generate_mipmaps()
	var tx := ImageTexture.create_from_image(img); _tex_band[tipo] = tx
	return tx
