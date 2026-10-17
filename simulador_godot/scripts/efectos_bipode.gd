class_name EfectosBipode
extends Node3D
## Efectos del juego del bipode (ModeloBipode.efectos3D de simulador_web/js/bipode.js): los drones diana (cuadricoptero de
## 60 cm con sus discos de helice y luces), las trazadoras (estelas de 45 m que engordan con la distancia para verse
## siempre) y las particulas (polvo al dar en el suelo, chispas al dar en un dron, humo y fuego de los derribados).
## pintar(juego, dt, camara) cada cuadro, con el JuegoBipode (posiciones en NED del mundo).

const MAXB := 300
var _drones := {}
var _balas: MultiMeshInstance3D
var _parts := []
var _t_humo := 0.0
static var _tex: ImageTexture

static func ned(p: Array) -> Vector3: return Vector3(p[1], -p[2], -p[0])

func _init() -> void:
	var cil := CylinderMesh.new(); cil.top_radius = 0.06; cil.bottom_radius = 0.06; cil.height = 1.0; cil.radial_segments = 6; cil.rings = 1; cil.cap_top = false; cil.cap_bottom = false
	var mb := StandardMaterial3D.new(); mb.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; mb.albedo_color = Color(1.0, 0.54, 0.10, 0.9)
	mb.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; cil.material = mb
	var mm := MultiMesh.new(); mm.transform_format = MultiMesh.TRANSFORM_3D; mm.mesh = cil; mm.instance_count = MAXB; mm.visible_instance_count = 0
	_balas = MultiMeshInstance3D.new(); _balas.multimesh = mm; _balas.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_balas.custom_aabb = AABB(Vector3(-1e5, -1e5, -1e5), Vector3(2e5, 2e5, 2e5)); add_child(_balas)

static func _textura() -> ImageTexture:
	if _tex != null: return _tex
	var im := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var r := Vector2(x - 31.5, y - 31.5).length() / 32.0
			var a := 0.0 if r >= 1 else (0.9 - 0.9 * r / 0.5 * 0.5 if r < 0.5 else 0.45 * (1 - r) / 0.5)
			im.set_pixel(x, y, Color(1, 1, 1, a))
	_tex = ImageTexture.create_from_image(im); return _tex

## Dron diana: cuerpo, brazos, motores, discos de helice, patas y luces (ejes Godot; morro hacia -z).
static func dron_diana() -> Node3D:
	var g := Node3D.new()
	var mc := StandardMaterial3D.new(); mc.albedo_color = Color8(0x3a, 0x3d, 0x42); mc.roughness = 0.45; mc.metallic = 0.3
	var mo := StandardMaterial3D.new(); mo.albedo_color = Color8(0xd8, 0x46, 0x1b); mo.roughness = 0.5
	var mm := StandardMaterial3D.new(); mm.albedo_color = Color8(0x1a, 0x1a, 0x1a); mm.roughness = 0.35; mm.metallic = 0.7
	var caja := func(p: Array, s: Array, m: Material) -> MeshInstance3D:
		var b := MeshInstance3D.new(); var bm := BoxMesh.new(); bm.size = Vector3(s[1], s[2], s[0]); b.mesh = bm; b.material_override = m
		b.position = ned(p); g.add_child(b); return b
	caja.call([0.0, 0.0, 0.0], [0.26, 0.16, 0.08], mc); caja.call([0.02, 0.0, -0.05], [0.16, 0.12, 0.03], mo); caja.call([0.14, 0.0, 0.03], [0.05, 0.06, 0.05], mm)
	var discos := []
	var md := StandardMaterial3D.new(); md.albedo_color = Color(0.07, 0.07, 0.07, 0.35); md.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; md.cull_mode = BaseMaterial3D.CULL_DISABLED
	for xy in [[0.2, 0.2], [0.2, -0.2], [-0.2, 0.2], [-0.2, -0.2]]:
		var x: float = xy[0]; var y: float = xy[1]
		var br: MeshInstance3D = caja.call([x / 2, y / 2, 0.0], [Vector2(x, y).length(), 0.03, 0.02], mc); br.rotation = Vector3(0, -atan2(y, x), 0)
		var mot := MeshInstance3D.new(); var cm := CylinderMesh.new(); cm.top_radius = 0.025; cm.bottom_radius = 0.025; cm.height = 0.04; mot.mesh = cm; mot.material_override = mm
		mot.position = ned([x, y, -0.02]); g.add_child(mot)
		var d := MeshInstance3D.new(); var dm := CylinderMesh.new(); dm.top_radius = 0.12; dm.bottom_radius = 0.12; dm.height = 0.002; dm.radial_segments = 24; d.mesh = dm; d.material_override = md
		d.position = ned([x, y, -0.045]); g.add_child(d); discos.append(d)
		caja.call([x * 0.6, y * 0.6, 0.07], [0.015, 0.015, 0.1], mm)
	for l in [[-0.13, Color(1, 0.16, 0.1)], [0.13, Color(0.16, 1, 0.29)]]:
		var s := MeshInstance3D.new(); var sm := SphereMesh.new(); sm.radius = 0.012; sm.height = 0.024; s.mesh = sm
		var ml := StandardMaterial3D.new(); ml.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; ml.albedo_color = l[1]; s.material_override = ml
		s.position = ned([l[0], 0.0, 0.04]); g.add_child(s)
	g.set_meta("discos", discos)
	return g

func _particula(p: Array, tipo: String) -> void:
	var col := Color8(0xff, 0xa0, 0x40) if tipo == "fuego" else (Color8(0x2b, 0x26, 0x22) if tipo == "humo" else (Color8(0xff, 0xe0, 0xa0) if tipo == "chispa" else Color8(0x8a, 0x7a, 0x62)))
	var s := Sprite3D.new(); s.texture = _textura(); s.billboard = BaseMaterial3D.BILLBOARD_ENABLED; s.shaded = false; s.modulate = col
	s.pixel_size = 1.0 / 64.0; s.position = ned(p); s.transparent = true
	if tipo == "fuego" or tipo == "chispa": s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED; s.render_priority = 1
	add_child(s)
	var vida := 2.6 if tipo == "humo" else (0.6 if tipo == "fuego" else (0.18 if tipo == "chispa" else 1.4))
	var t0 := 0.5 if tipo == "humo" else (1.2 if tipo == "fuego" else (0.5 if tipo == "chispa" else 0.6))
	var crece := 2.2 if tipo == "humo" else (3.0 if tipo == "fuego" else (1.0 if tipo == "chispa" else 2.2))
	_parts.append({ "s": s, "t": 0.0, "vida": vida, "t0": t0, "crece": crece, "sube": 1.2 if tipo == "humo" else (0.4 if tipo == "polvo" else 0.6), "col": col })

func pintar(J: JuegoBipode, dt: float, cam: Camera3D) -> void:
	if J == null: visible = false; return
	visible = true
	var vistos := {}
	for dr in J.drones:
		var g = _drones.get(dr["id"])
		if g == null: g = dron_diana(); add_child(g); _drones[dr["id"]] = g
		vistos[dr["id"]] = true
		var q := Cuat.desde_euler(dr["inclina"][1], dr["inclina"][0], dr["rumbo"])
		var p: Array = [dr["p"][0], dr["p"][1], dr["p"][2] - 0.08] if dr["estado"] == "roto" else dr["p"]
		g.transform = Transform3D(Basis(ned(Cuat.rot(q, [1.0, 0.0, 0.0])), ned(Cuat.rot(q, [0.0, 1.0, 0.0])), ned(Cuat.rot(q, [0.0, 0.0, 1.0]))), ned(p))
		for d in g.get_meta("discos"): d.visible = dr["estado"] == "vuela"
		if dr["estado"] == "roto" and not g.has_meta("quemado"):
			g.set_meta("quemado", true)
			for c in g.get_children():
				if c is MeshInstance3D and c.material_override is StandardMaterial3D:
					var m: StandardMaterial3D = c.material_override.duplicate(); m.albedo_color = m.albedo_color * 0.25; m.albedo_color.a = 1.0; c.material_override = m
	for id in _drones.keys():
		if not vistos.has(id): _drones[id].queue_free(); _drones.erase(id)
	_t_humo += dt
	if _t_humo > 0.06:
		_t_humo = 0.0
		for dr in J.drones:
			if dr["estado"] == "cae" or (dr["estado"] == "roto" and dr["tFin"] < 4):
				_particula(dr["p"], "humo")
				if dr["estado"] == "cae": _particula(dr["p"], "fuego")
	# trazadoras: estela de 45 m (lo que recorren en 1/20 s) que engorda con la distancia
	var n := 0; var mm := _balas.multimesh
	for b in J.balas:
		if not b["traza"] or n >= MAXB: continue
		var v := Vector3(b["v"][0], b["v"][1], b["v"][2]).length(); var L := minf(45.0, b["t"] * v)
		var t := ned(b["p"]); var d := ned([b["v"][0] / v, b["v"][1] / v, b["v"][2] / v])
		var dc := t.distance_to(cam.global_position) if cam else 50.0; var r := clampf(dc * 0.025, 1.0, 8.0)
		var y := d; var x := y.cross(Vector3.UP if absf(y.y) < 0.99 else Vector3.RIGHT).normalized(); var z := x.cross(y)
		mm.set_instance_transform(n, Transform3D(Basis(x * r, y * L, z * r), t - d * L / 2)); n += 1
	mm.visible_instance_count = n
	for e in J.eventos:
		match String(e["tipo"]):
			"suelo": _particula(e["p"], "polvo")
			"impacto": _particula(e["p"], "chispa"); _particula(e["p"], "chispa")
			"derribado": _particula(e["p"], "fuego"); _particula(e["p"], "humo")
			"explosion":
				for k in 6: _particula([e["p"][0] + randf() - 0.5, e["p"][1] + randf() - 0.5, e["p"][2] - randf()], "fuego" if k < 3 else "humo")
	J.eventos.clear()
	var i := _parts.size() - 1
	while i >= 0:
		var q: Dictionary = _parts[i]; q["t"] += dt; var f: float = q["t"] / q["vida"]
		if f >= 1: q["s"].queue_free(); _parts.remove_at(i); i -= 1; continue
		var sz: float = q["t0"] + q["crece"] * f; var s: Sprite3D = q["s"]
		s.pixel_size = sz / 64.0; s.position.y += q["sube"] * dt; var c: Color = q["col"]; c.a = (1 - f) * 0.85; s.modulate = c
		i -= 1
	while _parts.size() > 600: _parts[0]["s"].queue_free(); _parts.remove_at(0)
