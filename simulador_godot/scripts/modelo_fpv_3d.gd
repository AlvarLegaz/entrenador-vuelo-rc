class_name ModeloFPV3D
extends RefCounted
## Modelo 3D del dron FPV: un 5" tipo iFlight Nazgul / XING hecho con geometria procedural (sin ficheros de malla), el
## MISMO que construye ModeloFPV.construir3D en el navegador (simulador/aviones/FPV.js) con los mismos datos
## (datos.modelo3d) y el mismo algoritmo, paso a paso:
##  - piezas: placas extruidas con chaflan (brazos de carbono de 5,5 mm, placas inferior, intermedia y superior con
##    agujeros y ranuras, placas de la electronica, soportes de TPU de la camara), piezas de revolucion (motores 2306:
##    base, bobinado de cobre, campana ranurada, eje y tuerca; separadores de aluminio, tornillos, objetivo de la camara,
##    soportes de goma, condensador), secciones a lo largo de una linea (patas de TPU verde lima, cuerpo de la camara,
##    bateria, mastil y capsula de la antena), tubos (cables de los motores, cable XT60, cables de la bateria, correa de
##    velcro) y cajas redondeadas (componentes, conectores, hebilla, tiras de LED), con sus copias (4 brazos, 4 motores...);
##  - todo lo fijo en UNA malla (una sola llamada de dibujo) con el numero de material de cada vertice en UV2.y; el color,
##    la rugosidad, el metal y el barniz de cada material y los detalles finos (tejido de carbono con su brillo en
##    direccion de las fibras, ventanas de la campana, rotulo "2306", hilo del bobinado, capas de la impresion 3D,
##    componentes de las placas, etiqueta de la bateria) los pinta el codigo de sombreado comun (modelo3d.sombreador,
##    el mismo texto que usa Three);
##  - helices tripala de policarbonato gris translucido (perfil, cuerda, torsion por el paso de 4,3", flecha y buje) que
##    giran con las vueltas de CADA motor (av.motores) en su sentido (fc.motores: helices hacia dentro), con la inercia
##    que se ve al arrancar y al pararse; deprisa se funden en un disco translucido (opacidad = fraccion de la
##    circunferencia que tapan las palas) y desarmado se ven las palas quietas;
##  - luces de las tiras de LED (fijas armado, parpadean desarmado; 14 px fijos en pantalla).
## Con la camara FPV (camara 3, dentro del bastidor) el dron solo proyecta su sombra.
## Ejes cuerpo NED (x adelante, y derecha, z abajo; metros, origen en el CG; el suelo en z = +0,02).

const D2R := PI / 180.0
const DMAX := 0.0015

static var _cache := {}
static var _sh := {}

var raiz: Node3D
var rotores := []          # { nodo, palas, disco, s, rpm, fase }
var luces := []
var _geom: Array[GeometryInstance3D] = []
var _H: Dictionary
var _rpm_max := 30000.0
var _oculto := false
var _t := 0.0


func _init(r: Node3D, datos: Dictionary) -> void:
	raiz = r
	var K: Dictionary = datos["modelo3d"]
	_H = K["helice"]
	_rpm_max = float(datos.get("propulsion", {}).get("rpm_max", 30000.0))
	var C := mallas(K)
	if not C.has("am"):
		C["am"] = { "fija": _array_mesh(C["fija"]), "palas+1": _array_mesh(C["palas"][1]), "palas-1": _array_mesh(C["palas"][-1]), "disco": _array_mesh(C["disco"]) }
	var M: Dictionary = C["am"]
	var mats := _materiales(K)
	var fija := MeshInstance3D.new(); fija.mesh = M["fija"]; fija.material_override = mats["fija"]; raiz.add_child(fija); _geom.append(fija)
	for ro in K["rotores"]:
		var n := Node3D.new(); n.position = Vector3(ro[0], ro[1], ro[2]); raiz.add_child(n)
		var s := float(ro[3])
		var palas := MeshInstance3D.new(); palas.mesh = M["palas+1" if s > 0 else "palas-1"]; palas.material_override = mats["palas"]; n.add_child(palas)
		palas.set_instance_shader_parameter("alfa", float(_H["opacidad"]))
		var disco := MeshInstance3D.new(); disco.mesh = M["disco"]; disco.material_override = mats["disco"]
		disco.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; disco.visible = false; n.add_child(disco)
		var fase := randf() * TAU
		palas.basis = Basis(Vector3(0, 0, 1), fase)
		rotores.append({ "nodo": n, "palas": palas, "disco": disco, "s": s, "rpm": 0.0, "fase": fase })
	# luces (tiras de LED bajo los brazos): punto de tamano fijo en pantalla y una bolita, como las del dron comercial (Avion3D)
	for l in K["luces"]:
		var g := Node3D.new(); g.position = Vector3(l["p"][0], l["p"][1], l["p"][2])
		var color := Color.hex((int(l["color"]) << 8) | 0xff)
		var sp := Sprite3D.new(); sp.texture = Avion3D._textura_luz(); sp.modulate = color; sp.fixed_size = true
		sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED; sp.shaded = false; sp.transparent = true; sp.double_sided = true
		sp.pixel_size = 0.01 / 32; sp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		g.add_child(sp)
		var bola := MeshInstance3D.new(); var esf := SphereMesh.new(); esf.radius = 0.0022; esf.height = 0.0044; esf.radial_segments = 8; esf.rings = 6
		var mb := StandardMaterial3D.new(); mb.albedo_color = color; mb.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		bola.mesh = esf; bola.material_override = mb; bola.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; g.add_child(bola)
		raiz.add_child(g); luces.append(g)


## Cada cuadro: helices (vueltas de cada motor con la inercia que se ve al arrancar y al pararse: palas nitidas paradas
## o despacio y disco de desenfoque deprisa), luces (fijas armado, parpadean desarmado) y, con la camara FPV
## (camara_fpv), el dron solo como sombra: la camara va dentro del bastidor (como animar() en el navegador).
func actualizar(av: Dictionary, dt: float, camara_fpv: bool) -> void:
	_t += dt
	if camara_fpv != _oculto:
		_oculto = camara_fpv
		for g in _geom:
			g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if _oculto else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var ms: Array = av.get("motores", [0.0, 0.0, 0.0, 0.0])
	var parado: bool = av.get("estado", "") == "en mano"
	var rp := float(_H["rpm_palas"]); var rd := float(_H["rpm_disco"])
	for i in rotores.size():
		var R: Dictionary = rotores[i]
		var obj := 0.0 if parado else (float(ms[i]) if i < ms.size() else 0.0) * _rpm_max
		var rpm: float = R["rpm"]
		rpm += (obj - rpm) * (1.0 - exp(-dt / (0.08 if obj > rpm else 0.35)))
		if obj <= 0.0: rpm = maxf(0.0, rpm - 400.0 * dt)
		R["rpm"] = rpm
		R["fase"] = fmod(float(R["fase"]) + float(R["s"]) * rpm / 60.0 * TAU * dt, TAU)
		var palas: MeshInstance3D = R["palas"]; var disco: MeshInstance3D = R["disco"]
		palas.basis = Basis(Vector3(0, 0, 1), R["fase"])
		var a_p := 1.0 - smoothstep(rp, 3.0 * rp, rpm); var k_d := smoothstep(rp, rd, rpm)
		palas.set_instance_shader_parameter("alfa", float(_H["opacidad"]) * a_p); palas.visible = a_p > 0.01 and not _oculto
		disco.set_instance_shader_parameter("intensidad", k_d); disco.set_instance_shader_parameter("giro", float(R["s"]) * _t * 1.7)
		disco.visible = k_d > 0.01 and not _oculto
	var tl := fmod(Time.get_ticks_msec() / 1000.0, 1.0)
	var cam: Camera3D = raiz.get_viewport().get_camera_3d() if raiz.is_inside_tree() else null
	var alto := raiz.get_viewport().get_visible_rect().size.y if raiz.is_inside_tree() else 900.0
	var sc := 14 * 2 * tan(deg_to_rad(cam.fov) / 2) / alto if cam else 0.01
	for l in luces:
		l.visible = not _oculto and (bool(av.get("armado", false)) or tl < 0.5)
		(l.get_child(0) as Sprite3D).pixel_size = sc / 32


# =====================================================================
#  MATERIALES: el codigo de sombreado comun (modelo3d.sombreador) dentro de un sombreador de Godot
# =====================================================================
func _materiales(K: Dictionary) -> Dictionary:
	if _sh.is_empty():
		var comun := codigo(K)
		var fija := Shader.new(); fija.code = "shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;
varying vec4 vDet;
varying vec3 vPl;
varying vec3 vNl;
" + comun + "
void vertex() { vDet = vec4(UV, UV2); vPl = VERTEX; vNl = NORMAL; }
void fragment() {
	float fM = floor(vDet.w + 0.5);
	vec4 fA = fpv_tabla_a(fM);
	vec4 fB = fpv_tabla_b(fM);
	vec3 fAlb = fpv_lineal(fA.rgb); float fRug = fA.a; float fMet = fB.x; float fCc = fB.y; float fAo = 1.0; float fHueco = 0.0; vec3 fPert = vec3(0.0);
	fpv_detalle(fM, vDet, vPl, normalize(vNl), fAlb, fRug, fMet, fCc, fAo, fHueco, fPert);
	if (fHueco > 0.5) discard;
	ALBEDO = fAlb; ROUGHNESS = clamp(fRug, 0.0, 1.0); METALLIC = fMet; CLEARCOAT = fCc; CLEARCOAT_ROUGHNESS = fB.z;
	AO = fAo; AO_LIGHT_AFFECT = 0.5;
	if (fPert.z > 0.5) NORMAL = fpv_perturbar(NORMAL, VERTEX, vDet.xy, fPert.xy);
}
"
		var palas := Shader.new(); palas.code = "shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;
uniform vec3 color : source_color;
uniform float rug = 0.22;
instance uniform float alfa = 1.0;
void fragment() { ALBEDO = color; ROUGHNESS = rug; CLEARCOAT = 0.5; CLEARCOAT_ROUGHNESS = 0.1; ALPHA = alfa; }
"
		var disco := Shader.new(); disco.code = "shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_burley, specular_schlick_ggx;
uniform vec3 color : source_color;
uniform float r_buje;
uniform float r_punta;
instance uniform float intensidad = 0.0;
instance uniform float giro = 0.0;
varying vec3 vPl;
" + comun + "
void vertex() { vPl = VERTEX; }
void fragment() { ALBEDO = color; ROUGHNESS = 0.45; ALPHA = intensidad * fpv_disco(vPl.xy, giro, r_buje, r_punta); }
"
		_sh = { "fija": fija, "palas": palas, "disco": disco }
	var H: Dictionary = K["helice"]
	var mf := ShaderMaterial.new(); mf.shader = _sh["fija"]
	var mp := ShaderMaterial.new(); mp.shader = _sh["palas"]
	mp.set_shader_parameter("color", Color.hex((int(H["col"]) << 8) | 0xff)); mp.set_shader_parameter("rug", float(H["rug"]))
	var md := ShaderMaterial.new(); md.shader = _sh["disco"]
	md.set_shader_parameter("color", Color.hex((int(H["disco_col"]) << 8) | 0xff))
	md.set_shader_parameter("r_buje", float(H["buje"][2][0])); md.set_shader_parameter("r_punta", float(H["R"]))
	return { "fija": mf, "palas": mp, "disco": md }


static func _f(x: float) -> String: return "%.6f" % x

## Codigo de sombreado comun (el mismo texto que ModeloFPV.codigo3D en el navegador): materiales, cuerda de la pala y
## modelo3d.sombreador.
static func codigo(K: Dictionary) -> String:
	var H: Dictionary = K["helice"]; var c: Array = H["cuerda"]; var mats: Array = K["materiales"]
	var s := "#define PALAS " + _f(H["palas"]) + "\n"
	for i in mats.size(): s += "#define M_" + String(mats[i][0]).to_upper() + " " + _f(i) + "\n"
	for nom in ["a", "b"]:
		s += "vec4 fpv_tabla_" + nom + "(float m) {\n"
		for i in mats.size():
			var mt: Array = mats[i]; var col := int(mt[1]); var v: Array
			if nom == "a": v = [((col >> 16) & 255) / 255.0, ((col >> 8) & 255) / 255.0, (col & 255) / 255.0, float(mt[2])]
			else: v = [float(mt[3]), float(mt[4]), float(mt[5]), 0.0]
			var txt := []
			for x in v: txt.append(_f(x))
			s += "\tif (m < " + _f(i + 0.5) + ") return vec4(" + ", ".join(txt) + ");\n"
		s += "\treturn vec4(0.0);\n}\n"
	s += "float fpv_cuerda(float x) {\n"
	for i in range(1, c.size()):
		s += "\tif (x < " + _f(c[i][0]) + ") return mix(" + _f(c[i - 1][1]) + ", " + _f(c[i][1]) + ", (x - " + _f(c[i - 1][0]) + ") / " + _f(float(c[i][0]) - float(c[i - 1][0])) + ");\n"
	s += "\treturn " + _f(c[c.size() - 1][1]) + ";\n}\n"
	return s + "\n".join(K["sombreador"]) + "\n"


static func _array_mesh(A: Acum) -> ArrayMesh:
	var arr := []; arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = A.pos; arr[Mesh.ARRAY_NORMAL] = A.nor; arr[Mesh.ARRAY_TEX_UV] = A.uv; arr[Mesh.ARRAY_TEX_UV2] = A.uv2
	arr[Mesh.ARRAY_INDEX] = A.idx
	var am := ArrayMesh.new(); am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return am


# =====================================================================
#  MALLAS (se calculan una vez y se comparten): fija, palas+buje por sentido de giro y disco
# =====================================================================
static func mallas(K: Dictionary) -> Dictionary:
	if not _cache.is_empty(): return _cache
	var ids := {}
	for i in K["materiales"].size(): ids[K["materiales"][i][0]] = float(i)
	var fija := Acum.new()
	for P in K["piezas"]:
		var L := Acum.new(); var m: float = ids[P["m"]]
		match P["t"]:
			"placa": _placa(L, P, m)
			"torno": _torno(L, _v(P["o"]), _v(P["eje"]), P["p"], int(P.get("n", 24)), m, bool(P.get("dentro", false)))
			"loft": _loft(L, P["e"], float(P["n"]), float(P.get("t0", 0.0)), float(P.get("t1", 0.0)), _v(P.get("arriba", [0, 0, -1])), int(P.get("nc", 32)),
					float(P.get("m0", 2.0)), float(P.get("m1", 2.0)), int(P.get("nt", 6)), m, false)
			"tubo": _tubo(L, P, m)
			"cajas": _cajas(L, P, m)
		var cs: Array = K["copias"][P["copias"]] if P.has("copias") else [[0, 0, 0, 0]]
		for c in cs: _anadir(fija, L, c)
	var H: Dictionary = K["helice"]; var palas := {}
	for s in [1, -1]:
		var L := Acum.new()
		for k in int(H["palas"]): _pala(L, H, float(s), k * TAU / int(H["palas"]))
		_torno(L, Vector3.ZERO, Vector3(0, 0, -1), H["buje"], 32, 1.0, false)
		palas[s] = Acum.new(); _anadir(palas[s], L, [0, 0, 0, 0])
	var dl := Acum.new(); _disco(dl, H); var dsc := Acum.new(); _anadir(dsc, dl, [0, 0, 0, 0])
	_cache = { "fija": fija, "palas": palas, "disco": dsc }
	return _cache

## Resumen de una malla para comparar con el navegador: vertices, triangulos, area y suma de posiciones.
static func resumen(A: Acum) -> Dictionary:
	var area := 0.0; var sx := 0.0; var sy := 0.0; var sz := 0.0
	for k in range(0, A.idx.size(), 3):
		var a := A.pos[A.idx[k]]
		area += 0.5 * (A.pos[A.idx[k + 1]] - a).cross(A.pos[A.idx[k + 2]] - a).length()
	for p in A.pos:
		sx += p.x; sy += p.y; sz += p.z
	return { "vertices": A.pos.size(), "triangulos": A.idx.size() / 3, "area": area, "suma": sx + 2 * sy + 3 * sz }

static func _v(a: Array) -> Vector3: return Vector3(a[0], a[1], a[2])


## Malla en construccion: posiciones, normales, det (UV = det.xy, UV2 = det.zw: coordenadas de la pieza y el numero de
## material) y triangulos (sin orientar: se orientan con la normal al copiarlos).
class Acum:
	var pos := PackedVector3Array(); var nor := PackedVector3Array(); var uv := PackedVector2Array(); var uv2 := PackedVector2Array()
	var idx := PackedInt32Array()
	func vert(p: Vector3, nn: Vector3, d: Vector4) -> void:
		pos.append(p); nor.append(nn); uv.append(Vector2(d.x, d.y)); uv2.append(Vector2(d.z, d.w))


## Copia S en D girada c[3] grados sobre z, con y multiplicada por c[4] y desplazada (c[0], c[1], c[2]); cada triangulo
## con su cara delantera hacia la normal de sus vertices (Godot: sentido horario). Los degenerados se quitan.
static func _anadir(D: Acum, S: Acum, c: Array) -> void:
	var rz := float(c[3]) * D2R if c.size() > 3 else 0.0
	var sy := float(c[4]) if c.size() > 4 else 1.0
	var co := cos(rz); var si := sin(rz); var base := D.pos.size(); var t := Vector3(c[0], c[1], c[2])
	for i in S.pos.size():
		var p := S.pos[i]; var nn := S.nor[i]; var y := p.y * sy; var ny := nn.y * sy
		D.pos.append(Vector3(co * p.x - si * y + t.x, si * p.x + co * y + t.y, p.z + t.z))
		D.nor.append(Vector3(co * nn.x - si * ny, si * nn.x + co * ny, nn.z))
	D.uv.append_array(S.uv); D.uv2.append_array(S.uv2)
	for k in range(0, S.idx.size(), 3):
		var a := base + S.idx[k]; var b := base + S.idx[k + 1]; var e := base + S.idx[k + 2]
		var pa := D.pos[a]; var fn := (D.pos[b] - pa).cross(D.pos[e] - pa)
		if fn.length_squared() < 1e-28: continue
		if fn.dot(D.nor[a] + D.nor[b] + D.nor[e]) < 0.0: D.idx.append_array([a, b, e])
		else: D.idx.append_array([a, e, b])


static func _iguales(a: Vector3, b: Vector3) -> bool:
	return absf(a.x - b.x) < 1e-7 and absf(a.y - b.y) < 1e-7 and absf(a.z - b.z) < 1e-7

static func _ig(X: PackedVector3Array, Y: PackedVector3Array) -> bool:
	var K := X.size()
	return _iguales(X[0], Y[0]) and _iguales(X[K >> 1], Y[K >> 1]) and _iguales(X[K >> 2], Y[K >> 2])

## Rejilla de filas (anillos con el primer punto repetido al final, todas del mismo numero de puntos). Normales por
## diferencias centrales (dos filas iguales seguidas = arista viva), hacia fuera del centro de cada anillo (signo -1:
## hacia dentro); en los polos (fila de un solo punto), la media de las de la fila vecina.
static func _rejilla(A: Acum, P: Array, Dt: Array, signo := 1.0) -> void:
	var nf := P.size(); var K := (P[0] as PackedVector3Array).size(); var base := A.pos.size()
	var N := []; var suma := 0.0
	for i in nf:
		var ip := i - 1 if i > 0 and not _ig(P[i - 1], P[i]) else i
		var inx := i + 1 if i < nf - 1 and not _ig(P[i], P[i + 1]) else i
		var F: PackedVector3Array = P[i]; var Fp: PackedVector3Array = P[ip]; var Fn: PackedVector3Array = P[inx]
		var cen := Vector3.ZERO
		for j in K - 1: cen += F[j]
		cen /= float(K - 1)
		var fila := PackedVector3Array(); fila.resize(K)
		for j in K:
			var jp := j - 1 if j > 0 else K - 2; var jn := j + 1 if j < K - 1 else 1
			var v := (F[jn] - F[jp]).cross(Fn[j] - Fp[j])
			fila[j] = v
			if v.length_squared() > 0.0: suma += v.normalized().dot(F[j] - cen)
		N.append(fila)
	var s := (-1.0 if suma < 0.0 else 1.0) * signo
	var nula := []
	for i in nf:
		var fila: PackedVector3Array = N[i]; var nl := []
		for j in K:
			if fila[j].length_squared() > 1e-36:
				fila[j] = (fila[j] * s).normalized(); nl.append(false)
			else:
				fila[j] = Vector3.ZERO; nl.append(true)
		N[i] = fila; nula.append(nl)
	for i in nf:              # polos
		if not nula[i][0]: continue
		var vec: PackedVector3Array = N[i - 1] if i > 0 else N[i + 1]
		var vn: Array = nula[i - 1] if i > 0 else nula[i + 1]
		var m := Vector3.ZERO
		for j in K:
			if not vn[j]: m += vec[j]
		var fila := PackedVector3Array(); fila.resize(K); fila.fill(m.normalized())
		N[i] = fila; var nl := []; nl.resize(K); nl.fill(false); nula[i] = nl
	for i in nf:
		var F: PackedVector3Array = P[i]; var fila: PackedVector3Array = N[i]; var D: Array = Dt[i]; var nl: Array = nula[i]
		for j in K: A.vert(F[j], Vector3(0, 0, 1) if nl[j] else fila[j], D[j])
	for i in nf - 1:
		if _ig(P[i], P[i + 1]): continue
		for j in K - 1:
			var a := base + i * K + j; var b := base + (i + 1) * K + j
			A.idx.append_array([a, b, b + 1, a, b + 1, a + 1])


## Pieza de revolucion alrededor de eje desde o: perfil [[radio, altura], ...] (un punto repetido = arista viva).
## det = (fraccion de vuelta, radio, altura, material).
static func _torno(A: Acum, o: Vector3, eje: Vector3, perfil: Array, nc: int, m: float, dentro: bool) -> void:
	eje = eje.normalized()
	var ref := Vector3(1, 0, 0) if absf(eje.x) < 0.9 else Vector3(0, 1, 0)
	var u := eje.cross(ref).normalized(); var v := eje.cross(u)
	var P := []; var D := []
	for q in perfil:
		var r := float(q[0]); var h := float(q[1])
		var fila := PackedVector3Array(); var det := []
		for j in nc + 1:
			var a := TAU * (j % nc) / nc
			fila.append(o + eje * h + (u * cos(a) + v * sin(a)) * r); det.append(Vector4(float(j) / nc, r, h, m))
		P.append(fila); D.append(det)
	_rejilla(A, P, D, -1.0 if dentro else 1.0)


## Seccion superelíptica (exponente n) en el plano (l, u) alrededor de o: semiancho w, hacia arriba hu, hacia abajo hd.
static func _seccion(o: Vector3, l: Vector3, u: Vector3, w: float, hu: float, hd: float, n: float, nc: int) -> PackedVector3Array:
	var f := PackedVector3Array(); var e := 2.0 / n
	for j in nc:
		var a := TAU * j / nc; var c := cos(a); var s := sin(a)
		f.append(o + l * (signf(c) * pow(absf(c), e) * w) + u * (signf(s) * pow(absf(s), e) * (hu if s > 0 else hd)))
	f.append(f[0])
	return f

## Pieza alargada: estaciones [x, y, z, semiancho, alto hacia arriba, alto hacia abajo] a lo largo de una linea,
## secciones superelipticas de exponente n y tapas redondeadas (longitudes t0 y t1, exponentes m0 y m1; 0 = abierta), o
## cerrada sobre si misma. det = (fraccion de vuelta, posicion a lo largo, 0, material).
static func _loft(A: Acum, est: Array, n: float, t0: float, t1: float, arriba: Vector3, nc: int, m0: float, m1: float, nt: int, m: float, cerrado: bool) -> void:
	var k := est.size(); var filas := []; var T := []
	for i in k:
		var a: Array = est[(i - 1 + k) % k] if cerrado else est[maxi(i - 1, 0)]
		var b: Array = est[(i + 1) % k] if cerrado else est[mini(i + 1, k - 1)]
		T.append((_v(b) - _v(a)).normalized())
	var marco := func(t: Vector3) -> Array:
		var l := arriba.cross(t).normalized()
		return [l, t.cross(l)]
	var sec := func(E: Array, fr: Array, esc: float, d: Vector3) -> PackedVector3Array:
		return _seccion(_v(E) + d, fr[0], fr[1], float(E[3]) * esc, float(E[4]) * esc, float(E[5]) * esc, n, nc)
	if t0 > 0.0 and not cerrado:
		var fr: Array = marco.call(T[0])
		for q in range(nt, 0, -1):
			var th := PI / 2 * q / nt; var esc := 0.0 if q == nt else pow(maxf(cos(th), 0.0), 2.0 / m0)
			filas.append(sec.call(est[0], fr, esc, T[0] * (-t0 * pow(sin(th), 2.0 / m0))))
	for i in k: filas.append(sec.call(est[i], marco.call(T[i]), 1.0, Vector3.ZERO))
	if cerrado: filas.append(filas[0])
	if t1 > 0.0 and not cerrado:
		var fr: Array = marco.call(T[k - 1])
		for q in range(1, nt + 1):
			var th := PI / 2 * q / nt; var esc := 0.0 if q == nt else pow(maxf(cos(th), 0.0), 2.0 / m1)
			filas.append(sec.call(est[k - 1], fr, esc, T[k - 1] * (t1 * pow(sin(th), 2.0 / m1))))
	var D := []
	for i in filas.size():
		var det := []
		for j in nc + 1: det.append(Vector4(float(j) / nc, float(i) / (filas.size() - 1), 0.0, m))
		D.append(det)
	_rejilla(A, filas, D, 1.0)


## Redondea los vertices de una linea (puntos [x, y, z, radio]) con arcos de ese radio tangentes a sus dos aristas (como
## mucho hasta la mitad de cada arista), en pasos de 12 grados como mucho.
static func _redondear(pts: Array, cerrado: bool) -> Array:
	var n := pts.size(); var out := []
	for i in n:
		var P := _v(pts[i]); var r := float(pts[i][3]) if pts[i].size() > 3 else 0.0
		if r <= 0.0 or (not cerrado and (i == 0 or i == n - 1)):
			out.append(P); continue
		var A := _v(pts[(i - 1 + n) % n]); var B := _v(pts[(i + 1) % n])
		var d1 := (A - P).normalized(); var d2 := (B - P).normalized(); var th := acos(clampf(d1.dot(d2), -1.0, 1.0))
		if th > PI - 1e-3 or th < 1e-3:
			out.append(P); continue
		var phi := th / 2; var t := r / tan(phi); var rr := r
		var tmax := 0.5 * minf((A - P).length(), (B - P).length())
		if t > tmax:
			t = tmax; rr = t * tan(phi)
		var T1 := P + d1 * t; var T2 := P + d2 * t; var C := P + (d1 + d2).normalized() * (rr / sin(phi))
		var u1 := (T1 - C).normalized(); var u2 := (T2 - C).normalized(); var ang := acos(clampf(u1.dot(u2), -1.0, 1.0))
		var k := maxi(1, ceili(ang / (12 * D2R)))
		for j in k + 1:
			var s := float(j) / k
			out.append(C + (u1 * (sin((1 - s) * ang) / sin(ang)) + u2 * (sin(s * ang) / sin(ang))) * rr)
	# fuera los puntos casi repetidos (donde se tocan dos arcos)
	var limpio := []
	for i in out.size():
		if i == 0 or (out[i] - out[i - 1]).length() > 2e-5: limpio.append(out[i])
	return limpio

## Parte los tramos mas largos que dmax en tramos iguales.
static func _densificar(pts: Array, cerrado: bool, dmax: float) -> Array:
	var n := pts.size(); var out := []
	for i in n:
		out.append(pts[i])
		if not cerrado and i == n - 1: break
		var a: Vector3 = pts[i]; var b: Vector3 = pts[(i + 1) % n]; var k := ceili((b - a).length() / dmax)
		for j in range(1, k): out.append(a + (b - a) * (float(j) / k))
	return out

## Quita los puntos de un lazo alineados con sus vecinos (los de _densificar): las caras se triangulan sin ellos.
static func _simplificar(L: Array) -> Array:
	var n := L.size(); var out := []
	for i in n:
		var a: Vector2 = out[out.size() - 1] if not out.is_empty() else L[n - 1]
		var b: Vector2 = L[i]; var c: Vector2 = L[(i + 1) % n]
		if absf((b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x)) >= 1e-10: out.append(b)
	return out

static func _area2(L: Array) -> float:
	var s := 0.0
	for i in L.size():
		var a: Vector3 = L[i]; var b: Vector3 = L[(i + 1) % L.size()]
		s += a.x * b.y - b.x * a.y
	return s

static func _circulo(h: Array) -> Array:
	var r := float(h[2]); var n := maxi(12, ceili(TAU * r / 0.0007)); var L := []
	for j in n: L.append(Vector3(h[0] + r * cos(TAU * j / n), h[1] + r * sin(TAU * j / n), 0))
	return L

static func _ranura(h: Array) -> Array:      # [x1, y1, x2, y2, r]: dos semicirculos unidos
	var a := Vector3(h[0], h[1], 0); var b := Vector3(h[2], h[3], 0); var r := float(h[4])
	var d := (b - a).normalized(); var ang := atan2(d.y, d.x); var n := maxi(6, ceili(PI * r / 0.0007)); var L := []
	for j in n + 1:
		var t := ang - PI / 2 + PI * j / n; L.append(Vector3(b.x + r * cos(t), b.y + r * sin(t), 0))
	for j in n + 1:
		var t := ang + PI / 2 + PI * j / n; L.append(Vector3(a.x + r * cos(t), a.y + r * sin(t), 0))
	return _densificar(L, true, DMAX)


## Placa extruida: contorno [[a, b, radio de redondeo]] en el plano ejes ("xy": a = x, b = y; "xz": a = x, b = z),
## agujeros (circulos [a, b, r] y ranuras [a1, b1, a2, b2, r]), desde s0 con espesor e a lo largo del eje que falta y
## todos los cantos con un chaflan ch. det = (a, b, fraccion del espesor, material).
static func _placa(A: Acum, P: Dictionary, m: float) -> void:
	var E := float(P["e"]); var ch := float(P["ch"]); var s0 := float(P["s0"]); var xz: bool = P.get("ejes", "xy") == "xz"
	var pt := func(a: float, b: float, s: float) -> Vector3: return Vector3(a, s0 + s, b) if xz else Vector3(a, b, s0 + s)
	var eje := Vector3(0, 1, 0) if xz else Vector3(0, 0, 1)
	var cont := []
	for q in P["contorno"]: cont.append([q[0], q[1], 0.0, q[2] if q.size() > 2 else 0.0])
	var ext := _densificar(_redondear(cont, true), true, DMAX)
	if _area2(ext) < 0: ext.reverse()
	var lazos := [ext]
	for h in P.get("agujeros", []):
		var L := _circulo(h) if h.size() == 3 else _ranura(h)
		if _area2(L) > 0: L.reverse()
		lazos.append(L)
	var caras := []
	for li in lazos.size():
		var L: Array = lazos[li]; var K := L.size(); var N := []
		for j in K:
			var a: Vector3 = L[(j - 1 + K) % K]; var b: Vector3 = L[(j + 1) % K]
			var t := Vector3(b.x - a.x, b.y - a.y, 0).normalized(); N.append(Vector2(t.y, -t.x))
		var filas := []; var dets := []
		for fs in [[0.0, true], [ch, false], [ch, false], [E - ch, false], [E - ch, false], [E, true]]:
			var s: float = fs[0]; var k := ch if fs[1] else 0.0
			var fila := PackedVector3Array(); var det := []
			for j in K + 1:
				var q: Vector3 = L[j % K]; var nn: Vector2 = N[j % K]
				fila.append(pt.call(q.x - k * nn.x, q.y - k * nn.y, s)); det.append(Vector4(q.x, q.y, s / E, m))
			filas.append(fila); dets.append(det)
		_rejilla(A, filas, dets, 1.0 if li == 0 else -1.0)
		var cara := []
		for j in K:
			var q: Vector3 = L[j]; var nn: Vector2 = N[j]
			cara.append(Vector2(q.x - ch * nn.x, q.y - ch * nn.y))
		caras.append(_simplificar(cara))
	var pts := PackedVector2Array()
	for c in caras: pts.append_array(PackedVector2Array(c))
	var tri := _triangular(caras)
	for sg in [[0.0, -1.0], [E, 1.0]]:
		var s: float = sg[0]; var nrm := eje * float(sg[1]); var base := A.pos.size()
		for q in pts: A.vert(pt.call(q.x, q.y, s), nrm, Vector4(q.x, q.y, s / E, m))
		for t in tri: A.idx.append(base + t)


## Triangulos de un poligono con agujeros (caras[0] el contorno en sentido antihorario, el resto agujeros en sentido
## horario), con indices sobre todos sus puntos seguidos. Los agujeros se unen al contorno con un puente (de su punto
## mas a la derecha al vertice visible del contorno, como el triangulador del navegador) y el poligono resultante se
## triangula con Geometry2D (en milimetros: su tolerancia es absoluta).
static func _triangular(caras: Array) -> PackedInt32Array:
	var base := [0]
	for c in caras: base.append(base[base.size() - 1] + c.size())
	var poli := []          # [punto, indice]
	for j in caras[0].size(): poli.append([caras[0][j], j])
	var orden := range(1, caras.size())
	orden.sort_custom(func(a, b): return _xmax(caras[a]) > _xmax(caras[b]))
	for hi in orden:
		var H: Array = caras[hi]; var im := 0
		for j in H.size():
			if H[j].x > H[im].x: im = j
		var M: Vector2 = H[im]
		var mejor := -1; var xmin := INF
		for j in poli.size():
			var a: Vector2 = poli[j][0]; var b: Vector2 = poli[(j + 1) % poli.size()][0]
			if (a.y > M.y) == (b.y > M.y): continue
			var x := a.x + (M.y - a.y) * (b.x - a.x) / (b.y - a.y)
			if x >= M.x and x < xmin:
				xmin = x
				if absf(a.x - b.x) < 1e-9: mejor = j if absf(a.y - M.y) < absf(b.y - M.y) else (j + 1) % poli.size()
				else: mejor = j if a.x > b.x else (j + 1) % poli.size()
		# vertices del contorno dentro del triangulo M - I - P: el de menor angulo con el rayo
		var I := Vector2(xmin, M.y); var Pp: Vector2 = poli[mejor][0]; var amin := INF
		for j in poli.size():
			var q: Vector2 = poli[j][0]
			if j == mejor or q.x < M.x: continue
			if Geometry2D.point_is_inside_triangle(q, M, I, Pp):
				var ang := absf(atan2(q.y - M.y, q.x - M.x))
				if ang < amin:
					amin = ang; mejor = j
		# si el vertice elegido ya tiene puentes (esta repetido), la copia en cuyo angulo interior cae el agujero
		var V: Vector2 = poli[mejor][0]
		for j in poli.size():
			if not (poli[j][0] as Vector2).is_equal_approx(V): continue
			var a: Vector2 = poli[(j - 1 + poli.size()) % poli.size()][0]; var b: Vector2 = poli[(j + 1) % poli.size()][0]; var d := M - V
			var convexo := (V - a).cross(b - V) > 0.0
			var dentro := ((V - a).cross(d) > 0.0 and (b - V).cross(d) > 0.0) if convexo else ((V - a).cross(d) > 0.0 or (b - V).cross(d) > 0.0)
			if dentro:
				mejor = j; break
		var nuevo := []
		for j in mejor + 1: nuevo.append(poli[j])
		for k in H.size() + 1:
			var jj := (im + k) % H.size(); nuevo.append([H[jj], base[hi] + jj])
		nuevo.append(poli[mejor])
		for j in range(mejor + 1, poli.size()): nuevo.append(poli[j])
		poli = nuevo
	var pp := PackedVector2Array()
	for q in poli: pp.append(q[0] * 1000.0)
	var t := _orejas(pp)
	var out := PackedInt32Array()
	for k in t: out.append(poli[k][1])
	var n_esp: int = base[base.size() - 1] - 2 + 2 * (caras.size() - 1)
	if out.size() != 3 * n_esp: push_error("ModeloFPV3D: triangulacion de una placa con %d triangulos en vez de %d" % [out.size() / 3, n_esp])
	return out

## Recorte de orejas de un poligono simple en sentido antihorario (puede tener los puentes de los agujeros: puntos
## repetidos): una oreja es un vertice convexo cuyo triangulo no contiene ningun otro vertice (los que coinciden con sus
## esquinas no cuentan).
static func _orejas(P: PackedVector2Array) -> PackedInt32Array:
	var v := []
	for i in P.size(): v.append(i)
	var out := PackedInt32Array(); var i := 0; var fallos := 0
	while v.size() > 3:
		var n := v.size(); var ia: int = v[(i - 1 + n) % n]; var ib: int = v[i % n]; var ic: int = v[(i + 1) % n]
		var a := P[ia]; var b := P[ib]; var c := P[ic]
		var oreja := (b - a).cross(c - b) > 1e-9
		if oreja:
			for k in v:
				var q := P[k]
				if q.is_equal_approx(a) or q.is_equal_approx(b) or q.is_equal_approx(c): continue
				if (b - a).cross(q - a) >= -1e-9 and (c - b).cross(q - b) >= -1e-9 and (a - c).cross(q - c) >= -1e-9:
					oreja = false; break
		if oreja or fallos > n:
			out.append_array([ia, ib, ic]); v.remove_at(i % n); fallos = 0
			i = maxi(i % n - 1, 0)
		else:
			i = (i + 1) % n; fallos += 1
	out.append_array([v[0], v[1], v[2]])
	return out

static func _xmax(L: Array) -> float:
	var x := -INF
	for q in L: x = maxf(x, q.x)
	return x


## Tubo (cables, mastil, correa): linea [[x, y, z, radio de redondeo]] con seccion circular de radio r o superelíptica
## sec = [semiancho, arriba, abajo, exponente]; abierto con las puntas redondeadas o cerrado.
static func _tubo(A: Acum, P: Dictionary, m: float) -> void:
	var c := bool(P.get("cerrado", false)); var L := _redondear(P["c"], c)
	var s: Array = P["sec"] if P.has("sec") else [P["r"], P["r"], P["r"], 2]
	var est := []
	for q in L: est.append([q.x, q.y, q.z, s[0], s[1], s[2]])
	var nc := int(P.get("nc", 8 if float(s[0]) < 0.001 else 12))
	_loft(A, est, float(s[3]), 0.0 if c else float(s[0]), 0.0 if c else float(s[0]), _v(P.get("arriba", [0, 1, 0])), nc, 2.0, 2.0, 3, m, c)

## Cajas redondeadas [cx, cy, cz, lx, ly, lz] alineadas con los ejes.
static func _cajas(A: Acum, P: Dictionary, m: float) -> void:
	for b in P["l"]:
		var cx := float(b[0]); var cy := float(b[1]); var cz := float(b[2]); var lx := float(b[3]); var ly := float(b[4]); var lz := float(b[5])
		var rr := 0.2 * minf(lx, minf(ly, lz))
		_loft(A, [[cx - lx / 2 + rr, cy, cz, ly / 2, lz / 2, lz / 2], [cx + lx / 2 - rr, cy, cz, ly / 2, lz / 2, lz / 2]], 6.0, rr, rr, Vector3(0, 0, -1), 16, 3.5, 3.5, 3, m, false)


## Cuerda de la pala (m) en xi = 0 (raiz) ... 1 (punta): la tabla de la helice, interpolada.
static func _cuerda(H: Dictionary, xi: float) -> float:
	var t: Array = H["cuerda"]
	for i in range(1, t.size()):
		if xi < t[i][0]: return t[i - 1][1] + (t[i][1] - t[i - 1][1]) * (xi - t[i - 1][0]) / (t[i][0] - t[i - 1][0])
	return t[t.size() - 1][1]

static func _naca(u: float) -> float:
	return 5.0 * (0.2969 * sqrt(u) - 0.126 * u - 0.3516 * u * u + 0.2843 * u * u * u - 0.1036 * u * u * u * u)

## Una pala en ejes del rotor (z abajo) a lo largo de +x girada giro sobre z: cuerda, torsion (paso geometrico, como
## mucho beta_max), espesor, curvatura del perfil, flecha hacia atras y algo de conicidad; s = sentido de giro (+1
## horario visto desde arriba: el borde de ataque mira a +y).
static func _pala(A: Acum, H: Dictionary, s: float, giro: float) -> void:
	var nfil := int(H["filas"]); var M := int(H["puntos"]); var K := 2 * M - 1; var rot := Basis(Vector3(0, 0, 1), giro)
	var R := float(H["R"]); var r0 := float(H["r0"]); var curv := float(H["curvatura"]); var esp: Array = H["espesor"]
	var filas := []; var dets := []
	var polo := func(q: Vector3, xi: float) -> void:
		var f := PackedVector3Array(); var dt := []
		for j in K:
			f.append(rot * q); dt.append(Vector4(xi, float(j) / (K - 1), 0.0, 0.0))
		filas.append(f); dets.append(dt)
	polo.call(Vector3(r0 - 0.0004, 0, 0), 0.0)
	for k in nfil + 1:
		var xi := 1.0 - pow(1.0 - float(k) / nfil, 1.5); var r := r0 + (R - r0) * xi; var c := _cuerda(H, xi)
		var beta := minf(atan(float(H["paso"]) / (TAU * r)), float(H["beta_max"]) * D2R)
		var e := float(esp[0]) + (float(esp[1]) - float(esp[0])) * xi
		var d := Vector3(0, s * cos(beta), -sin(beta)); var nn := Vector3(0, -s * sin(beta), -cos(beta))
		var centro := Vector3(r, -s * float(H["flecha"]) * xi * xi, -float(H["conicidad"]) * xi)
		var f := PackedVector3Array(); var dt := []
		for j in M:
			var u := (1.0 - cos(PI * j / (M - 1))) / 2.0
			f.append(rot * (centro + d * ((0.35 - u) * c) + nn * (c * (curv * 4.0 * u * (1.0 - u) + e * _naca(u)))))
		for j in range(M - 2, 0, -1):
			var u := (1.0 - cos(PI * j / (M - 1))) / 2.0
			f.append(rot * (centro + d * ((0.35 - u) * c) + nn * (c * (curv * 4.0 * u * (1.0 - u) - e * _naca(u)))))
		f.append(f[0])
		for j in K: dt.append(Vector4(xi, float(j) / (K - 1), 0.0, 0.0))
		filas.append(f); dets.append(dt)
	polo.call(Vector3(R + 0.0006, -s * float(H["flecha"]), -float(H["conicidad"])), 1.0)
	_rejilla(A, filas, dets, 1.0)

## Disco de desenfoque de un rotor: corona plana del buje a la punta.
static func _disco(A: Acum, H: Dictionary) -> void:
	var n := 72; var r0 := float(H["buje"][2][0]); var R := float(H["R"])
	for j in n:
		var a := TAU * j / n; var c := cos(a); var s := sin(a)
		A.vert(Vector3(c * r0, s * r0, 0), Vector3(0, 0, -1), Vector4.ZERO); A.vert(Vector3(c * R, s * R, 0), Vector3(0, 0, -1), Vector4.ZERO)
	for j in n:
		var a := 2 * j; var b := a + 1; var c := 2 * ((j + 1) % n); var d := c + 1
		A.idx.append_array([a, c, b, b, c, d])

