class_name ModeloDJI3D
extends Node3D
## Modelo 3D detallado del Mini Dron HQ, que Avion3D pone en lugar de la malla de cajas cuando los datos son de un
## cuadricoptero (tipo "cuadricoptero"). Todo procedural (sin ficheros de malla): superficies parametricas con normales
## suaves (carcasa, cuerpo, brazos y patas: secciones superelipticas a lo largo de una linea con tapas redondeadas;
## motores, objetivo, sensores y botones: piezas de revolucion; palas: perfil NACA con su cuerda, torsion y flecha) y
## materiales PBR (plastico satinado con barniz, metal de las campanas, cristal del objetivo, goma de los pies).
## Medidas y forma del Mini Dron HQ (fotos de producto como referencia): 245 x 289 x 56 mm desplegado con helices
## (helices de 4,7" = 119 mm; motores delanteros a 180 mm entre si, traseros a 170 mm y 128 mm de delante a atras;
## diagonal ~215 mm), cuerpo de 138 mm de largo con una carcasa superior gris muy claro de 62 mm de ancho que vuela sobre
## un cuerpo inferior gris algo mas oscuro, morro ancho y redondeado con dos tomas de aire y la camara en un gimbal de
## 3 ejes debajo; brazos planos: los delanteros salen de los lados del morro y bajo sus motores llevan las patas (las
## antenas) hasta el suelo; los traseros salen bajo la carcasa por detras y sus motores, mas bajos, hacen de pies.
## Helices gris oscuro con la punta naranja. Rejillas de ventilacion, sensores de vision hacia abajo, ToF, luz auxiliar,
## extremo de la bateria con sus 4 luces y boton, y las lentes de las luces de los brazos y de la cola.
## Ejes: los de Avion3D, cuerpo NED (x adelante, y derecha, z abajo; metros; origen en el CG = centro de los motores).
## El suelo queda en z = +0,02, la altura del CG del dron posado en la fisica.
## Helices: palas que giran con las rpm (av.rpm); a partir de unas centenas de rpm se funden en un disco translucido
## cuya opacidad a cada radio es la fraccion de la circunferencia que tapan las palas (como en una foto a 1/60 s), y
## paradas ("en mano") se ven las palas quietas. La camara del gimbal sigue av.gimbal (grados, 0 horizontal, -90 abajo)
## estabilizada: nivelada y con el rumbo del dron aunque este se incline. Si la camara de la escena esta dentro del dron
## (camara 3, la del gimbal) el modelo solo proyecta su sombra, para no tapar la vista.

const SUELO := 0.020
## Motores: x, y, altura del plano de las palas, sentido de giro (+1 horario visto desde arriba; delante derecha y
## detras izquierda antihorario).
const MOTORES := [[0.064, 0.090, -0.0355, -1.0], [0.064, -0.090, -0.0355, 1.0], [-0.064, 0.085, -0.0170, 1.0], [-0.064, -0.085, -0.0170, -1.0]]
const R_HELICE := 0.0595            # helice de 4,7" (119 mm)
const R0_HELICE := 0.0055           # raiz de la pala (dentro del buje)
const PASO := 0.066                 # paso geometrico (4726: 2,6")
const RPM_PALAS := 250.0            # por encima las palas se funden con el disco
const RPM_DISCO := 1100.0           # disco del todo formado
const CAMARA_DENTRO := 0.25         # m: camara de la escena mas cerca que esto = la del gimbal

# gimbal: ejes de guinada (vertical, bajo el morro), alabeo (longitudinal, detras de la camara) y cabeceo (lateral, por
# el centro de la camara)
const G_GUI := Vector3(0.0590, 0.0, -0.0080)
const G_ALA := Vector3(0.0592, 0.0, 0.0015)
const G_CAB := Vector3(0.0692, 0.0, 0.0015)

const C_CARCASA := Color("e3e3e0")      # gris muy claro de la carcasa superior
const C_CUERPO := Color("c4c5c4")       # cuerpo inferior
const C_BRAZO := Color("cdcecc")        # brazos, patas y carcasas de los motores
const C_HELICE := Color("3a3b3e")
const C_PUNTA := Color("f0782a")

static var _cache := {}
static var _sh_casco: Shader
static var _sh_disco: Shader

var rotores := []                   # { palas, disco, s, fase }
var gimbal_guinada: Node3D; var gimbal_alabeo: Node3D; var gimbal_cabeceo: Node3D
var rpm := 0.0                      # rpm que se ven (siguen a las de la fisica con la inercia del motor)
var _rpm_obj := 0.0
var _rpm_max := 16000.0
var _mats := {}
var _geom: Array[GeometryInstance3D] = []
var _oculto := false
var _luces_lejos := false
var _t := 0.0


func _init(datos: Dictionary = {}) -> void:
	name = "DJI_Mini_4K"
	_rpm_max = float(datos.get("propulsion", {}).get("rpm_max", 16000.0))
	_crear_materiales()
	var C := _mallas()
	# carcasa, cuerpo, brazos, motores, bujes y detalles fijos: una malla con una superficie por material
	_instancia(self, C["fijo"], Vector3.ZERO)
	# gimbal de 3 ejes: guinada -> alabeo -> cabeceo (camara); cada malla esta en ejes cuerpo y se desplaza a su eje
	gimbal_guinada = Node3D.new(); gimbal_guinada.position = G_GUI; add_child(gimbal_guinada)
	_instancia(gimbal_guinada, C["g_guinada"], -G_GUI)
	gimbal_alabeo = Node3D.new(); gimbal_alabeo.position = G_ALA - G_GUI; gimbal_guinada.add_child(gimbal_alabeo)
	_instancia(gimbal_alabeo, C["g_alabeo"], -G_ALA)
	gimbal_cabeceo = Node3D.new(); gimbal_cabeceo.position = G_CAB - G_ALA; gimbal_alabeo.add_child(gimbal_cabeceo)
	_instancia(gimbal_cabeceo, C["g_cabeceo"], -G_CAB)
	# rotores: palas (giran) y disco de desenfoque (translucido, sin sombra)
	for m in MOTORES:
		var nodo := Node3D.new(); nodo.position = Vector3(m[0], m[1], m[2]); add_child(nodo)
		var palas := _instancia(nodo, C["palas%+d" % int(m[3])], Vector3.ZERO)
		var disco := MeshInstance3D.new(); disco.mesh = C["disco"]; disco.material_override = _mats["disco"]
		disco.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; disco.visible = false; nodo.add_child(disco)
		rotores.append({ "palas": palas, "disco": disco, "s": float(m[3]), "fase": randf() * TAU })
	poner_gimbal(Basis.IDENTITY)
	_poner_palas()


## Posicion de una luz de los datos (malla.luces) sobre este modelo: las de los brazos traseros, por fuera de la
## carcasa de sus motores; la de la cola, en la trasera del cuerpo.
static func posicion_luz(p: Array) -> Vector3:
	var x: float = p[0]; var y: float = p[1]
	if x < -0.05 and absf(y) > 0.05: return Vector3(-0.0695, signf(y) * 0.0924, -0.0050)
	if x < 0.0 and absf(y) < 0.01: return Vector3(-0.0548, 0.0, -0.0125)
	return Vector3(p[0], p[1], p[2])


## Estado de la fisica: rpm de los motores (parados "en mano") e inclinacion de la camara, estabilizada.
func actualizar(av: Dictionary) -> void:
	if av.get("estado", "") == "en mano": _rpm_obj = 0.0
	else: _rpm_obj = float(av["rpm"]) if av.has("rpm") else float(av.get("gases", 0.0)) * _rpm_max
	var q: Array = av["q"]
	var rb := Basis(_v(Cuat.rot(q, [1.0, 0.0, 0.0])), _v(Cuat.rot(q, [0.0, 1.0, 0.0])), _v(Cuat.rot(q, [0.0, 0.0, 1.0])))
	var rumbo: float = Cuat.euler(q)[2]
	var g := deg_to_rad(float(av.get("gimbal", 0.0)))
	poner_gimbal(rb.transposed() * (Basis(Vector3(0, 0, 1), rumbo) * Basis(Vector3(0, 1, 0), g)))


## Orientacion de la camara respecto al cuerpo (NED) repartida entre los tres motores del gimbal (guinada, alabeo y
## el resto en el cabeceo), para que la camara quede exactamente asi.
func poner_gimbal(loc: Basis) -> void:
	var y := loc.y
	var b := clampf(asin(clampf(y.z, -1.0, 1.0)), -0.7, 0.7)
	var a := clampf(atan2(-y.x, y.y), -0.6, 0.6)
	gimbal_guinada.basis = Basis(Vector3(0, 0, 1), a)
	gimbal_alabeo.basis = Basis(Vector3(1, 0, 0), b)
	gimbal_cabeceo.basis = ((gimbal_guinada.basis * gimbal_alabeo.basis).transposed() * loc).orthonormalized()


static func _v(a: Array) -> Vector3: return Vector3(a[0], a[1], a[2])


func _process(dt: float) -> void:
	_t += dt
	# inercia de los motores: arrancan en ~0,1 s y al pararse frenan en un par de segundos
	var tau := 0.12 if _rpm_obj > rpm else 0.45
	rpm += (_rpm_obj - rpm) * (1.0 - exp(-dt / tau))
	if _rpm_obj <= 0.0: rpm = maxf(0.0, rpm - 300.0 * dt)
	_poner_palas()
	for r in rotores:
		r["fase"] = fmod(r["fase"] + r["s"] * rpm / 60.0 * TAU * dt, TAU)
		(r["palas"] as Node3D).basis = Basis(Vector3(0, 0, 1), r["fase"])
		# fantasma de las palas en el disco: gira despacio, como el efecto estroboscopico de una camara
		(r["disco"] as GeometryInstance3D).set_instance_shader_parameter("fase", r["s"] * _t * 1.7)
	# camara de la escena dentro del dron (la del gimbal): solo la sombra, ni palas, ni disco ni luces
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	var dentro := cam != null and cam.global_position.distance_to(global_position) < CAMARA_DENTRO
	if dentro != _oculto:
		_oculto = dentro
		for g in _geom:
			g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if dentro else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		_poner_palas()
	# luces: de lejos (el punto de 16 px es mayor que el dron) sin prueba de profundidad, para que el propio dron no
	# las tape; de cerca, sobre su lente y tapadas por el dron como una luz de verdad
	var lejos := cam != null and cam.global_position.distance_to(global_position) > 1.5
	if get_parent() is Avion3D:
		for l in (get_parent() as Avion3D).luces:
			if dentro: l.visible = false
			if lejos != _luces_lejos: (l.get_child(0) as Sprite3D).no_depth_test = lejos
	_luces_lejos = lejos


## Palas nitidas por debajo de RPM_PALAS, disco de desenfoque por encima (fundido con transparencia por tramado).
func _poner_palas() -> void:
	var a_palas := 1.0 - smoothstep(RPM_PALAS, RPM_PALAS * 3.0, rpm)
	var k_disco := smoothstep(RPM_PALAS, RPM_DISCO, rpm)
	var mp: StandardMaterial3D = _mats["palas"]
	var c := mp.albedo_color
	if absf(c.a - a_palas) > 1e-4:
		c.a = a_palas; mp.albedo_color = c
	(_mats["disco"] as ShaderMaterial).set_shader_parameter("intensidad", k_disco)
	for r in rotores:
		(r["palas"] as Node3D).visible = a_palas > 0.01
		(r["disco"] as Node3D).visible = k_disco > 0.01 and not _oculto


func _instancia(padre: Node3D, am: ArrayMesh, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new(); mi.mesh = am; mi.position = pos
	for i in am.get_surface_count(): mi.set_surface_override_material(i, _mats[am.surface_get_name(i)])
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	padre.add_child(mi); _geom.append(mi)
	return mi


# =====================================================================
#  MATERIALES
# =====================================================================
func _crear_materiales() -> void:
	if _sh_casco == null:
		_sh_casco = Shader.new(); _sh_casco.code = SHADER_CASCO
		_sh_disco = Shader.new(); _sh_disco.code = SHADER_DISCO
	var casco := ShaderMaterial.new(); casco.shader = _sh_casco
	casco.set_shader_parameter("carcasa", C_CARCASA); casco.set_shader_parameter("cuerpo", C_CUERPO); casco.set_shader_parameter("brazo", C_BRAZO)
	_mats["casco"] = casco
	_mats["oscuro"] = _std(Color("2b2c2f"), 0.5, 0.0, 0.2)
	_mats["camara"] = _std(Color("232427"), 0.42, 0.0, 0.35)
	_mats["frontal"] = _std(Color("b9bbbc"), 0.35, 0.0, 0.4)
	_mats["metal"] = _std(Color("6a6e74"), 0.32, 0.85, 0.0)
	_mats["aro"] = _std(Color("3c3e42"), 0.25, 0.9, 0.0)
	_mats["goma"] = _std(Color("1b1b1c"), 0.9, 0.0, 0.0)
	_mats["tornillo"] = _std(Color("8d9095"), 0.3, 1.0, 0.0)
	var vidrio := _std(Color("04060a"), 0.02, 0.0, 1.0); vidrio.clearcoat_roughness = 0.0; vidrio.metallic_specular = 1.0
	_mats["vidrio"] = vidrio
	_mats["sensor"] = _std(Color("0a0b0d"), 0.06, 0.0, 0.8)
	_mats["led"] = _std(Color("e6e9eb"), 0.1, 0.0, 0.7)
	_mats["buje"] = _std(Color("47484c"), 0.4, 0.2, 0.2)
	var palas := _std(Color(1, 1, 1), 0.38, 0.0, 0.25); palas.vertex_color_use_as_albedo = true; palas.vertex_color_is_srgb = true
	palas.cull_mode = BaseMaterial3D.CULL_DISABLED
	palas.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_HASH     # siempre (cambiarlo recompila el sombreador: tirones)
	_mats["palas"] = palas
	var disco := ShaderMaterial.new(); disco.shader = _sh_disco
	disco.set_shader_parameter("color", C_HELICE); disco.set_shader_parameter("punta", C_PUNTA)
	disco.set_shader_parameter("r0", R0_HELICE); disco.set_shader_parameter("R", R_HELICE)
	_mats["disco"] = disco

static func _std(c: Color, rug: float, met: float, barniz: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new(); m.albedo_color = c; m.roughness = rug; m.metallic = met
	if barniz > 0.0: m.clearcoat_enabled = true; m.clearcoat = barniz; m.clearcoat_roughness = 0.3
	return m

## Plastico gris satinado con barniz ligero. Color de vertice: r = 1 carcasa superior (gris muy claro; rejillas de
## ventilacion a los lados de detras y junta de la tapa de la bateria), g = 1 cuerpo inferior (gris; tomas de aire del
## morro, rejilla de la panza y extremo de la bateria en gris oscuro), resto brazos. Las juntas y ranuras se funden
## cuando son mas finas que un pixel (sin parpadeo de lejos).
const SHADER_CASCO := "shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;
uniform vec3 carcasa : source_color;
uniform vec3 cuerpo : source_color;
uniform vec3 brazo : source_color;
uniform vec3 oscuro : source_color = vec3(0.16, 0.165, 0.17);
varying vec3 lp;
varying vec3 ln;
varying vec2 marca;
void vertex() { lp = VERTEX; ln = NORMAL; marca = COLOR.rg; }
float linea(float d, float ancho, float fw0) {
	float fw = max(fw0, 1e-7);
	return (1.0 - smoothstep(ancho * 0.5, ancho * 0.5 + fw, abs(d))) * clamp(ancho / fw, 0.0, 1.0);
}
float caja(vec2 p, vec2 b, float r) { vec2 q = abs(p) - b + vec2(r); return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - r; }
float ranuras(float t, float periodo, float ancho) {
	float d = (fract(t / periodo) - 0.5) * periodo;
	return linea(d, ancho, fwidth(t));
}
float dentro(vec2 p, vec2 b, float r) { float d = caja(p, b, r); return 1.0 - smoothstep(-0.0002, 0.0002, d); }
void fragment() {
	vec3 col = brazo; float rug = 0.42; float hueco = 0.0; float junta = 0.0; float cc = 0.25;
	if (marca.r > 0.5) {
		col = carcasa; rug = 0.36; cc = 0.4;
		// rejilla de ventilacion a cada lado de la parte de atras
		float zl = dentro(vec2(lp.x + 0.0395, lp.z + 0.0215), vec2(0.0075, 0.0021), 0.0018) * smoothstep(0.45, 0.65, abs(ln.y));
		hueco = max(hueco, zl * ranuras(lp.x, 0.0021, 0.0011));
		// junta de la tapa de la bateria, de lado a lado por detras
		junta = linea(lp.x + 0.031, 0.0005, fwidth(lp.x)) * smoothstep(0.2, 0.4, abs(ln.y) + max(-ln.z, 0.0));
	} else if (marca.g > 0.5) {
		col = cuerpo; rug = 0.45;
		// dos tomas de aire en el frontal, bajo la carcasa
		float tf = dentro(vec2(abs(lp.y) - 0.0165, lp.z + 0.0105), vec2(0.0055, 0.0022), 0.0018) * smoothstep(0.3, 0.55, ln.x);
		hueco = max(hueco, tf * 0.92);
		// rejilla de la panza
		float zb = dentro(vec2(lp.x + 0.030, lp.y), vec2(0.0130, 0.0110), 0.003) * smoothstep(0.5, 0.75, ln.z);
		hueco = max(hueco, zb * ranuras(lp.y, 0.0024, 0.0011));
		// trasera: el extremo de la bateria, gris oscuro mate, con su junta
		float bat = smoothstep(-0.3, -0.55, ln.x) * smoothstep(-0.0470, -0.0490, lp.x);
		col = mix(col, oscuro, bat); rug = mix(rug, 0.62, bat);
		junta = linea(lp.x + 0.0478, 0.0005, fwidth(lp.x)) * (1.0 - bat);
	}
	col *= 1.0 - 0.7 * junta;
	col = mix(col, vec3(0.012), hueco);
	ALBEDO = col;
	ROUGHNESS = mix(rug, 0.9, hueco);
	SPECULAR = 0.5;
	CLEARCOAT = cc * (1.0 - hueco);
	CLEARCOAT_ROUGHNESS = 0.22;
	AO = 1.0 - 0.6 * max(junta, hueco);
	AO_LIGHT_AFFECT = 0.4;
}
"

## Disco de desenfoque de la helice: opacidad = fraccion de la circunferencia que tapan las dos palas a ese radio
## (2 c(r) / 2 pi r, la misma cuerda que la malla), con la punta naranja y un fantasma tenue de las palas.
const SHADER_DISCO := "shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_burley, specular_schlick_ggx;
uniform vec3 color : source_color;
uniform vec3 punta : source_color;
uniform float intensidad = 1.0;
uniform float r0 = 0.0055;
uniform float R = 0.0595;
instance uniform float fase = 0.0;
varying vec2 lp;
void vertex() { lp = VERTEX.xy; }
float cuerda(float xi) {
	float c = 0.0072 + 0.0064 * smoothstep(0.0, 0.3, xi) - 0.0034 * smoothstep(0.3, 0.9, xi);
	if (xi > 0.8) c *= sqrt(max(0.0, 1.0 - pow((xi - 0.8) / 0.2, 2.0)));
	return c;
}
void fragment() {
	float r = length(lp);
	float xi = clamp((r - r0) / (R - r0), 0.0, 1.0);
	float cob = clamp(2.0 * cuerda(xi) / (6.2831853 * max(r, 1e-4)), 0.0, 1.0);
	float a = atan(lp.y, lp.x) - fase;
	float fantasma = pow(abs(cos(a)), 16.0);
	ALBEDO = mix(color, punta, smoothstep(0.885, 0.905, xi));
	ROUGHNESS = 0.45;
	SPECULAR = 0.5;
	ALPHA = intensidad * clamp(cob * 1.6 * (0.75 + 0.6 * fantasma), 0.0, 1.0) * smoothstep(r0, r0 + 0.0015, r);
}
"


# =====================================================================
#  MALLAS (se construyen una vez y se comparten)
# =====================================================================
static func _mallas() -> Dictionary:
	if not _cache.is_empty(): return _cache
	var f := {}                # superficies de la parte fija por material
	for k in ["casco", "oscuro", "metal", "goma", "sensor", "led", "buje"]: f[k] = Acum.new()
	_cuerpo(f)
	for lado in [1.0, -1.0]:
		_brazo_delantero(f, lado)
		_brazo_trasero(f, lado)
	for m in MOTORES: _motor(f, m)
	_cache["fijo"] = _juntar(f)
	var g1 := { "casco": Acum.new(), "oscuro": Acum.new() }
	var g2 := { "oscuro": Acum.new() }
	var g3 := { "camara": Acum.new(), "frontal": Acum.new(), "aro": Acum.new(), "vidrio": Acum.new(), "oscuro": Acum.new() }
	_gimbal(g1, g2, g3)
	_cache["g_guinada"] = _juntar(g1); _cache["g_alabeo"] = _juntar(g2); _cache["g_cabeceo"] = _juntar(g3)
	# palas (una malla por sentido de giro, con sus tornillos) y disco
	for s in [1.0, -1.0]:
		var p := { "palas": Acum.new(), "tornillo": Acum.new() }
		_pala(p["palas"], s, 0.0); _pala(p["palas"], s, PI)
		for k in 2:
			var a: float = PI * k + 0.35 * s
			_torno(p["tornillo"], Vector3(cos(a) * 0.0040, sin(a) * 0.0040, -0.0016), Vector3(0, 0, -1),
				[[0.0, 0.0], [0.0013, 0.0], [0.0013, 0.0], [0.0013, 0.0005], [0.0010, 0.0009], [0.0, 0.0010]], 10)
		_cache["palas%+d" % int(s)] = _juntar(p)
	_cache["disco"] = _disco()
	return _cache

static func _juntar(acums: Dictionary) -> ArrayMesh:
	var am := ArrayMesh.new()
	for k in acums:
		var a: Acum = acums[k]
		if a.idx.is_empty(): continue
		var arr := []; arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = a.pos; arr[Mesh.ARRAY_NORMAL] = a.nor; arr[Mesh.ARRAY_COLOR] = a.col; arr[Mesh.ARRAY_INDEX] = a.idx
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		am.surface_set_name(am.get_surface_count() - 1, k)
	return am

static func _disco() -> ArrayMesh:
	var pos := PackedVector3Array(); var nor := PackedVector3Array(); var idx := PackedInt32Array()
	var n := 64
	for j in n:
		var a := TAU * j / n
		pos.append(Vector3(cos(a), sin(a), 0) * (R0_HELICE * 0.9)); pos.append(Vector3(cos(a), sin(a), 0) * R_HELICE)
		nor.append(Vector3(0, 0, -1)); nor.append(Vector3(0, 0, -1))
	for j in n:
		var a := 2 * j; var b := 2 * j + 1; var c := 2 * ((j + 1) % n); var d := c + 1
		idx.append_array([a, c, b, b, c, d])
	var arr := []; arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = pos; arr[Mesh.ARRAY_NORMAL] = nor; arr[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new(); am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return am


# ---- carcasa superior y cuerpo inferior ----
# carcasa: de x -0,056 a +0,082 (morro), ancha delante (62 mm) y mas estrecha detras; su borde (labio) vuela sobre el
# cuerpo inferior, que es 3-4 mm mas estrecho; el techo baja hacia el morro
const CX := [-0.050, -0.040, -0.025, -0.005, 0.015, 0.035, 0.050, 0.062, 0.070]
const C_ANCHO := [0.0228, 0.0250, 0.0275, 0.0300, 0.0311, 0.0313, 0.0311, 0.0304, 0.0294]
const C_TECHO := [-0.0265, -0.0288, -0.0304, -0.0310, -0.0304, -0.0284, -0.0258, -0.0228, -0.0205]
const C_LABIO := [-0.0180, -0.0177, -0.0174, -0.0171, -0.0168, -0.0165, -0.0162, -0.0159, -0.0156]
const BX := [-0.047, -0.035, -0.015, 0.010, 0.030, 0.042, 0.052]
const B_ANCHO := [0.0190, 0.0218, 0.0246, 0.0262, 0.0262, 0.0252, 0.0238]
const B_PANZA := [0.0042, 0.0058, 0.0064, 0.0064, 0.0054, 0.0035, -0.0005]

static func _interp(xs: Array, tabla: Array, x: float) -> float:
	# Catmull-Rom sobre una tabla (abscisas no uniformes, suficiente para perfiles suaves)
	var n := xs.size()
	if x <= xs[0]: return tabla[0]
	if x >= xs[n - 1]: return tabla[n - 1]
	var i := 0
	while x > xs[i + 1]: i += 1
	var t: float = (x - xs[i]) / (xs[i + 1] - xs[i])
	var p0: float = tabla[maxi(i - 1, 0)]; var p1: float = tabla[i]; var p2: float = tabla[i + 1]; var p3: float = tabla[mini(i + 2, n - 1)]
	return 0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t + (-p0 + 3 * p1 - 3 * p2 + p3) * t * t * t)

static func _cuerpo(f: Dictionary) -> void:
	var est := []
	for k in 25:
		var x: float = lerpf(CX[0], CX[CX.size() - 1], k / 24.0)
		var zc := _interp(CX, C_LABIO, x)
		est.append([Vector3(x, 0, zc), _interp(CX, C_ANCHO, x), zc - _interp(CX, C_TECHO, x), 0.0034])
	_loft(f["casco"], est, 3.4, 0.0065, 0.0115, Vector3(0, 0, -1), 64, 3.2, 3.4, Color(1, 0, 0), 9)
	est = []
	for k in 17:
		var x: float = lerpf(BX[0], BX[BX.size() - 1], k / 16.0)
		var bot := _interp(BX, B_PANZA, x); var top := -0.0225; var zc := (top + bot) / 2
		est.append([Vector3(x, 0, zc), _interp(BX, B_ANCHO, x), zc - top, bot - zc])
	_loft(f["casco"], est, 4.0, 0.0060, 0.0060, Vector3(0, 0, -1), 56, 3.2, 3.0, Color(0, 1, 0), 8)
	# extremo de la bateria: boton y 4 luces de carga
	_torno(f["oscuro"], Vector3(-0.0528, -0.0105, -0.0060), Vector3(-1, 0, 0), [[0.0, 0.0], [0.0023, 0.0], [0.0023, 0.0], [0.0023, 0.0012], [0.0018, 0.0016], [0.0, 0.0017]], 16)
	for k in 4:
		_torno(f["led"], Vector3(-0.0531, -0.0030 + 0.0040 * k, -0.0060), Vector3(-1, 0, 0), [[0.0, 0.0], [0.0007, 0.0], [0.0007, 0.0009], [0.0, 0.0011]], 8)
	# lentes de las luces (las enciende Avion3D): en los motores traseros y en la cola
	for lado in [1.0, -1.0]:
		var dir := Vector3(-0.6, 0.8 * lado, 0)
		_torno(f["led"], Vector3(-0.064, 0.085 * lado, -0.0050) + dir * 0.0068, dir, [[0.0, 0.0], [0.0024, 0.0], [0.0024, 0.0012], [0.0, 0.0018]], 12)
	_torno(f["led"], Vector3(-0.0535, 0.0, -0.0125), Vector3(-1, 0, 0), [[0.0, 0.0], [0.0034, 0.0], [0.0034, 0.0], [0.0034, 0.0010], [0.0, 0.0014]], 14)
	# panza: sensores de vision hacia abajo, ToF y luz auxiliar
	for y in [-0.0085, 0.0085]:
		_torno(f["oscuro"], Vector3(0.022, y, 0.0058), Vector3(0, 0, 1), [[0.0, 0.0], [0.0040, 0.0], [0.0040, 0.0], [0.0040, 0.0010], [0.0032, 0.0012], [0.0032, 0.0012], [0.0, 0.0008]], 18)
		_torno(f["sensor"], Vector3(0.022, y, 0.0064), Vector3(0, 0, 1), [[0.0, 0.0], [0.0025, 0.0], [0.0017, 0.0007], [0.0, 0.0009]], 16)
	_torno(f["sensor"], Vector3(0.006, 0.0, 0.0062), Vector3(0, 0, 1), [[0.0, 0.0], [0.0028, 0.0], [0.0028, 0.0], [0.0028, 0.0009], [0.0, 0.0010]], 14)
	_torno(f["led"], Vector3(-0.004, 0.0, 0.0062), Vector3(0, 0, 1), [[0.0, 0.0], [0.0022, 0.0], [0.0022, 0.0], [0.0022, 0.0009], [0.0, 0.0011]], 12)
	# puerto USB-C a un lado de la trasera
	_loft(f["oscuro"], [[Vector3(-0.0440, -0.0205, -0.0080), 0.0012, 0.0016, 0.0016], [Vector3(-0.0395, -0.0222, -0.0080), 0.0012, 0.0016, 0.0016]], 4.0, 0.0006, 0.0006, Vector3(0, 0, -1), 16, 2.0, 2.0, Color(0, 0, 0), 3)


# ---- brazos ----
static func _bezier(a: Vector3, b: Vector3, c: Vector3, t: float) -> Vector3:
	return a.lerp(b, t).lerp(b.lerp(c, t), t)

## Delantero: plano y ancho, sale del lado del morro bajo la carcasa hacia afuera y algo adelante; en la punta, la
## carcasa del motor, que sigue hacia abajo como pata (la antena) hasta el suelo, con un taco de goma.
static func _brazo_delantero(f: Dictionary, lado: float) -> void:
	var a := Vector3(0.042, 0.022 * lado, -0.0100); var c := Vector3(0.064, 0.090 * lado, -0.0195)
	var b := Vector3(0.056, 0.054 * lado, -0.0120)
	var est := []
	for k in 10:
		var t := k / 9.0
		est.append([_bezier(a, b, c, t), lerpf(0.0076, 0.0062, t), lerpf(0.0036, 0.0033, t), lerpf(0.0036, 0.0033, t)])
	_loft(f["casco"], est, 3.6, 0.0, 0.0, Vector3(0, 0, -1), 28)
	_torno(f["casco"], Vector3(0.0445, 0.0240 * lado, -0.0040), Vector3(0, 0, -1),     # bisagra (eje vertical)
		[[0.0, 0.0], [0.0050, 0.0], [0.0064, 0.0009], [0.0068, 0.0030], [0.0068, 0.0092], [0.0060, 0.0106], [0.0, 0.0110]], 24)
	# asiento del motor
	_torno(f["casco"], Vector3(0.064, 0.090 * lado, -0.0200), Vector3(0, 0, -1),
		[[0.0, 0.0], [0.0068, 0.0], [0.0078, 0.0030], [0.0084, 0.0062], [0.0085, 0.0075], [0.0085, 0.0075], [0.0076, 0.0080], [0.0, 0.0080]], 28)
	# pata: de seccion ovalada, mas ancha de delante a atras, algo abierta hacia afuera
	var pe := []
	for k in 8:
		var t := k / 7.0
		var p := Vector3(lerpf(0.0640, 0.0628, t), lado * lerpf(0.0900, 0.0950, t * t), lerpf(-0.0215, 0.0172, t))
		pe.append([p, lerpf(0.0050, 0.0036, t), lerpf(0.0085, 0.0056, t), lerpf(0.0085, 0.0056, t)])
	_loft(f["casco"], pe, 3.4, 0.0, 0.0, Vector3(1, 0, 0), 24)
	_loft(f["goma"], [[Vector3(0.0628, 0.0950 * lado, 0.0170), 0.0037, 0.0057, 0.0057], [Vector3(0.0628, 0.0950 * lado, 0.0186), 0.0036, 0.0055, 0.0055]], 3.4, 0.0, 0.0014, Vector3(1, 0, 0), 24, 2.0, 3.0, Color(0, 0, 0), 4)

## Trasero: sale bajo la carcasa por detras, hacia atras, afuera y abajo, hasta la carcasa del motor, que llega al suelo.
static func _brazo_trasero(f: Dictionary, lado: float) -> void:
	var a := Vector3(-0.026, 0.020 * lado, -0.0125); var c := Vector3(-0.064, 0.085 * lado, -0.0040)
	var b := Vector3(-0.044, 0.050 * lado, -0.0100)
	var est := []
	for k in 10:
		var t := k / 9.0
		est.append([_bezier(a, b, c, t), lerpf(0.0072, 0.0058, t), lerpf(0.0035, 0.0032, t), lerpf(0.0035, 0.0032, t)])
	_loft(f["casco"], est, 3.6, 0.0, 0.0, Vector3(0, 0, -1), 28)
	_torno(f["casco"], Vector3(-0.0262, 0.0215 * lado, -0.0070), Vector3(0, 0, -1),
		[[0.0, 0.0], [0.0050, 0.0], [0.0062, 0.0009], [0.0066, 0.0028], [0.0066, 0.0082], [0.0058, 0.0096], [0.0, 0.0100]], 24)
	# carcasa del motor trasero: del pie al asiento del motor
	_torno(f["casco"], Vector3(-0.064, 0.085 * lado, SUELO - 0.0016), Vector3(0, 0, -1),
		[[0.0, 0.0], [0.0050, 0.0], [0.0058, 0.0010], [0.0060, 0.0040], [0.0062, 0.0150], [0.0074, 0.0210], [0.0084, 0.0258], [0.0085, 0.0266], [0.0085, 0.0266], [0.0076, 0.0272], [0.0, 0.0272]], 28)
	_torno(f["goma"], Vector3(-0.064, 0.085 * lado, SUELO), Vector3(0, 0, -1),
		[[0.0, 0.0], [0.0040, 0.0], [0.0050, 0.0007], [0.0052, 0.0020], [0.0, 0.0020]], 20)

## Motor sin escobillas (campana de metal gris con una banda oscura) y buje de la helice sobre el asiento.
static func _motor(f: Dictionary, m: Array) -> void:
	var zp: float = m[2]; var o := Vector3(m[0], m[1], zp + 0.0080)
	_torno(f["metal"], o, Vector3(0, 0, -1),
		[[0.0, 0.0], [0.0064, 0.0], [0.0064, 0.0], [0.0069, 0.0006], [0.0070, 0.0040], [0.0067, 0.0058], [0.0061, 0.0064], [0.0061, 0.0064], [0.0, 0.0064]], 28)
	_torno(f["goma"], o + Vector3(0, 0, -0.0010), Vector3(0, 0, -1), [[0.00700, 0.0], [0.00706, 0.0004], [0.00706, 0.0016], [0.00700, 0.0020]], 28)
	_torno(f["buje"], Vector3(m[0], m[1], zp + 0.0016), Vector3(0, 0, -1),
		[[0.0, 0.0], [0.0062, 0.0], [0.0066, 0.0008], [0.0066, 0.0024], [0.0058, 0.0031], [0.0, 0.0032]], 24)


# ---- gimbal y camara ----
static func _gimbal(g1: Dictionary, g2: Dictionary, g3: Dictionary) -> void:
	# guinada: motor colgado bajo el morro y brazo que baja por detras de la camara
	_torno(g1["casco"], G_GUI + Vector3(0, 0, -0.0030), Vector3(0, 0, 1),
		[[0.0, 0.0], [0.0056, 0.0], [0.0060, 0.0010], [0.0060, 0.0040], [0.0054, 0.0050], [0.0, 0.0052]], 24)
	_loft(g1["oscuro"], [[G_GUI + Vector3(-0.0012, 0, 0.0018), 0.0040, 0.0024, 0.0024], [G_ALA + Vector3(-0.0030, 0, -0.0010), 0.0040, 0.0024, 0.0024]], 3.0, 0.0, 0.0016, Vector3(1, 0, 0), 20)
	# alabeo: motor detras de la camara (eje longitudinal) y brazo hacia la izquierda hasta el motor de cabeceo
	_torno(g2["oscuro"], G_ALA + Vector3(-0.0040, 0, 0), Vector3(1, 0, 0),
		[[0.0, 0.0], [0.0046, 0.0], [0.0052, 0.0008], [0.0052, 0.0036], [0.0046, 0.0044], [0.0, 0.0046]], 24)
	var ra := []
	var pa := G_ALA; var pb := Vector3(G_ALA.x, -0.0150, G_ALA.z); var pc := Vector3(G_CAB.x - 0.0015, -0.0150, G_CAB.z)
	for k in 7:
		ra.append([_bezier(pa, pb, pc, k / 6.0), 0.0015, 0.0040, 0.0040])
	_loft(g2["oscuro"], ra, 3.0, 0.0, 0.0012, Vector3(0, 0, -1), 20)
	_torno(g2["oscuro"], Vector3(G_CAB.x, -0.0174, G_CAB.z), Vector3(0, 1, 0),
		[[0.0, 0.0], [0.0048, 0.0], [0.0055, 0.0008], [0.0055, 0.0040], [0.0050, 0.0050], [0.0, 0.0052]], 24)
	# cabeceo: la camara (caja redondeada gris oscuro), su frontal gris claro y el objetivo
	var cx := G_CAB.x; var cz := G_CAB.z
	_loft(g3["camara"], [[Vector3(cx - 0.0062, 0, cz), 0.0106, 0.0086, 0.0086], [Vector3(cx + 0.0068, 0, cz), 0.0106, 0.0086, 0.0086]], 4.5, 0.0018, 0.0008, Vector3(0, 0, -1), 44, 2.6, 3.0, Color(0, 0, 0), 6)
	_loft(g3["frontal"], [[Vector3(cx + 0.0068, 0, cz), 0.0088, 0.0076, 0.0076], [Vector3(cx + 0.0082, 0, cz), 0.0086, 0.0074, 0.0074]], 5.0, 0.0, 0.0006, Vector3(0, 0, -1), 44, 3.0, 3.0, Color(0, 0, 0), 4)
	_torno(g3["camara"], Vector3(cx, -0.0106, cz), Vector3(0, -1, 0), [[0.0, 0.0], [0.0040, 0.0], [0.0040, 0.0016], [0.0034, 0.0022], [0.0, 0.0024]], 20)
	var lo := Vector3(cx + 0.0087, 0, cz)
	_torno(g3["aro"], lo, Vector3(1, 0, 0),
		[[0.0062, -0.0006], [0.0062, 0.0006], [0.0058, 0.0012], [0.0058, 0.0012], [0.0049, 0.0012], [0.0049, 0.0012], [0.0047, 0.0004]], 44)
	_torno(g3["oscuro"], lo, Vector3(1, 0, 0), [[0.0047, 0.0004], [0.0042, 0.0002], [0.0042, 0.0002], [0.0042, 0.0005]], 44)
	_torno(g3["vidrio"], lo, Vector3(1, 0, 0), [[0.0042, 0.0005], [0.0032, 0.0009], [0.0016, 0.0011], [0.0, 0.0012]], 44)


# ---- pala de helice ----
static func _cuerda(xi: float) -> float:
	var c := 0.0072 + 0.0064 * smoothstep(0.0, 0.3, xi) - 0.0034 * smoothstep(0.3, 0.9, xi)
	if xi > 0.8: c *= sqrt(maxf(0.0, 1.0 - pow((xi - 0.8) / 0.2, 2.0)))
	return c

static func _naca(u: float) -> float:
	return 5.0 * (0.2969 * sqrt(u) - 0.126 * u - 0.3516 * u * u + 0.2843 * u * u * u - 0.1036 * u * u * u * u)

## Una pala en ejes del rotor (z abajo), a lo largo de +x girada giro sobre z: cuerda, torsion (paso geometrico),
## flecha hacia atras en la punta, perfil curvado y la punta naranja; s = sentido de giro (+1 horario desde arriba: el
## borde de ataque mira a +y).
static func _pala(acum: Acum, s: float, giro: float) -> void:
	var filas := []; var cols := []
	var nfil := 24; var M := 10
	var rot := Basis(Vector3(0, 0, 1), giro)
	for k in nfil + 1:
		var xi := 1.0 - pow(1.0 - float(k) / nfil, 1.5)
		var r := R0_HELICE + (R_HELICE - R0_HELICE) * xi
		var c := _cuerda(xi)
		var beta := minf(atan(PASO / (TAU * r)), deg_to_rad(30.0))
		var esp := 0.12 - 0.065 * xi
		var flecha := 0.0060 * xi * xi
		var d := Vector3(0, s * cos(beta), -sin(beta))          # de salida a ataque
		var nn := Vector3(0, -s * sin(beta), -cos(beta))        # normal hacia arriba
		var centro := Vector3(r, -s * flecha, -0.0005 * xi)     # un poco de conicidad
		var fila := PackedVector3Array()
		for j in M:
			var u := (1.0 - cos(PI * j / (M - 1))) / 2.0
			fila.append(rot * (centro + d * ((0.35 - u) * c) + nn * (c * (0.16 * u * (1.0 - u) + esp * _naca(u)))))
		for j in range(M - 2, 0, -1):
			var u := (1.0 - cos(PI * j / (M - 1))) / 2.0
			fila.append(rot * (centro + d * ((0.35 - u) * c) + nn * (c * (0.16 * u * (1.0 - u) - esp * _naca(u)))))
		filas.append(fila)
		cols.append(C_PUNTA if xi > 0.895 else C_HELICE)
	acum.rejilla(filas, Color(0, 0, 0), cols)


# =====================================================================
#  GEOMETRIA PARAMETRICA
# =====================================================================
## Seccion superelíptica (exponente n) en el plano (l, u) alrededor de o: semiancho w, hacia arriba hu, hacia abajo hd.
static func _seccion(o: Vector3, l: Vector3, u: Vector3, w: float, hu: float, hd: float, n: float, nc: int) -> PackedVector3Array:
	var f := PackedVector3Array(); f.resize(nc)
	var e := 2.0 / n
	for j in nc:
		var a := TAU * j / nc
		var c := cos(a); var s := sin(a)
		f[j] = o + l * (signf(c) * pow(absf(c), e) * w) + u * (signf(s) * pow(absf(s), e) * (hu if s > 0 else hd))
	return f

## Pieza alargada: estaciones [punto, semiancho, alto hacia arriba, alto hacia abajo] a lo largo de una linea, secciones
## superelipticas de exponente n y tapas redondeadas (longitudes tapa0 y tapa1, exponentes m0 y m1; 0 = abierta).
static func _loft(acum: Acum, est: Array, n: float, tapa0: float, tapa1: float, arriba := Vector3(0, 0, -1), nc := 32,
		m0 := 2.0, m1 := 2.0, col := Color(0, 0, 0), nt := 6) -> void:
	var k := est.size(); var filas := []
	var T := []
	for i in k:
		var a: Vector3 = est[maxi(i - 1, 0)][0]; var b: Vector3 = est[mini(i + 1, k - 1)][0]
		T.append((b - a).normalized())
	var marco := func(t: Vector3) -> Array:
		var l := arriba.cross(t).normalized()
		return [l, t.cross(l)]
	if tapa0 > 0.0:
		var fr: Array = marco.call(T[0])
		for q in range(nt, 0, -1):
			var th := PI / 2 * q / nt
			var esc := 0.0 if q == nt else pow(maxf(cos(th), 0.0), 2.0 / m0)
			var dd := tapa0 * pow(sin(th), 2.0 / m0)
			filas.append(_seccion(est[0][0] - T[0] * dd, fr[0], fr[1], est[0][1] * esc, est[0][2] * esc, est[0][3] * esc, n, nc))
	for i in k:
		var fr: Array = marco.call(T[i])
		filas.append(_seccion(est[i][0], fr[0], fr[1], est[i][1], est[i][2], est[i][3], n, nc))
	if tapa1 > 0.0:
		var fr: Array = marco.call(T[k - 1])
		for q in range(1, nt + 1):
			var th := PI / 2 * q / nt
			var esc := 0.0 if q == nt else pow(maxf(cos(th), 0.0), 2.0 / m1)
			var dd := tapa1 * pow(sin(th), 2.0 / m1)
			filas.append(_seccion(est[k - 1][0] + T[k - 1] * dd, fr[0], fr[1], est[k - 1][1] * esc, est[k - 1][2] * esc, est[k - 1][3] * esc, n, nc))
	acum.rejilla(filas, col)

## Pieza de revolucion alrededor de eje desde o: perfil [[radio, altura], ...]; un punto repetido = arista viva.
static func _torno(acum: Acum, o: Vector3, eje: Vector3, perfil: Array, nc := 24, col := Color(0, 0, 0)) -> void:
	eje = eje.normalized()
	var ref := Vector3(1, 0, 0) if absf(eje.x) < 0.9 else Vector3(0, 1, 0)
	var u := eje.cross(ref).normalized(); var v := eje.cross(u)
	var filas := []
	for p in perfil:
		var fila := PackedVector3Array(); fila.resize(nc)
		for j in nc:
			var a := TAU * j / nc
			fila[j] = o + eje * float(p[1]) + (u * cos(a) + v * sin(a)) * float(p[0])
		filas.append(fila)
	acum.rejilla(filas, col)


## Acumulador de una superficie (un material): vertices, normales, color de vertice e indices.
class Acum:
	var pos := PackedVector3Array(); var nor := PackedVector3Array(); var col := PackedColorArray(); var idx := PackedInt32Array()

	static func _igual(A: PackedVector3Array, B: PackedVector3Array) -> bool:
		return A[0].is_equal_approx(B[0]) and A[A.size() / 2].is_equal_approx(B[B.size() / 2]) and A[A.size() / 4].is_equal_approx(B[B.size() / 4])

	static func _centro(A: PackedVector3Array) -> Vector3:
		var c := Vector3.ZERO
		for p in A: c += p
		return c / A.size()

	## Rejilla de filas cerradas (anillos) del mismo numero de puntos. Normales por diferencias centrales (dos filas
	## iguales seguidas = arista viva: cada una toma la normal de su lado), orientadas hacia fuera; en los polos (fila
	## de un solo punto), la media de las de la fila vecina. Triangulos con la cara delantera hacia la normal.
	## cols: color de cada fila (si no, c para todas).
	func rejilla(P: Array, c: Color, cols: Array = []) -> void:
		var nf := P.size(); var nc: int = (P[0] as PackedVector3Array).size(); var base := pos.size()
		var N := []
		for i in nf:
			var ip := i - 1 if i > 0 and not _igual(P[i - 1], P[i]) else i
			var inx := i + 1 if i < nf - 1 and not _igual(P[i], P[i + 1]) else i
			var F: PackedVector3Array = P[i]; var Fp: PackedVector3Array = P[ip]; var Fn: PackedVector3Array = P[inx]
			var fila := PackedVector3Array(); fila.resize(nc)
			for j in nc:
				fila[j] = (F[(j + 1) % nc] - F[(j - 1 + nc) % nc]).cross(Fn[j] - Fp[j])
			N.append(fila)
		# sentido hacia fuera: el mismo para toda la rejilla (la parametrizacion es coherente)
		var suma := 0.0
		for i in nf:
			var F: PackedVector3Array = P[i]; var cen := _centro(F); var fila: PackedVector3Array = N[i]
			for j in nc: suma += fila[j].normalized().dot(F[j] - cen)
		var signo := -1.0 if suma < 0.0 else 1.0
		for i in nf:
			var fila: PackedVector3Array = N[i]
			for j in nc: fila[j] = (fila[j] * signo).normalized() if fila[j].length_squared() > 1e-24 else Vector3.ZERO
			N[i] = fila
		for i in nf:      # polos
			var fila: PackedVector3Array = N[i]
			if fila[0] != Vector3.ZERO: continue
			var vec: PackedVector3Array = N[i - 1] if i > 0 else N[i + 1]
			var m := Vector3.ZERO
			for v in vec: m += v
			for j in nc: fila[j] = m.normalized()
			N[i] = fila
		for i in nf:
			pos.append_array(P[i]); nor.append_array(N[i])
			var ci: Color = cols[i] if i < cols.size() else c
			for j in nc: col.append(ci)
		for i in nf - 1:
			if _igual(P[i], P[i + 1]): continue
			for j in nc:
				var a := base + i * nc + j; var b := base + (i + 1) * nc + j
				var cc := base + (i + 1) * nc + (j + 1) % nc; var d := base + i * nc + (j + 1) % nc
				_tri(a, b, cc); _tri(a, cc, d)

	func _tri(a: int, b: int, c: int) -> void:
		var pa := pos[a]; var pb := pos[b]; var pc := pos[c]
		var fn := (pc - pa).cross(pb - pa)          # cara delantera de Godot (sentido horario)
		if fn.length_squared() < 1e-22: return
		if fn.dot(nor[a] + nor[b] + nor[c]) < 0.0: idx.append_array([a, c, b])
		else: idx.append_array([a, b, c])
