class_name VistaPrevia
extends SubViewportContainer
## Vista previa del avion girando despacio y moviendo los mandos (VistaPrevia de js/visor.js): en el inicio (sobre la
## ortofoto) y en el hangar. Fondo transparente, luz de cielo y sol, camara de 35 grados a una distancia proporcional a
## la envergadura (factor: 1,75 en el inicio, 1,4 en el hangar).

var vp: SubViewport
var base: Node3D
var cam: Camera3D
var av3d: Avion3D
var _t := 0.0

func _init() -> void:
	stretch = true; mouse_filter = Control.MOUSE_FILTER_IGNORE
	vp = SubViewport.new(); vp.transparent_bg = true; vp.own_world_3d = true; vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE; add_child(vp)
	# luces de la VistaPrevia del navegador con la equivalencia medida en campo_3d.gd: HemisphereLight(blanco, 0x557755,
	# 0,95 pi) -> 0,95 x color en el mapa de radiancia; sol 0,8 pi -> 0,8; ACES de Three (exposicion 1,05) = ACES de Godot
	# con exposicion 1,05 / 0,6 / 1,8 y blanco 16
	var we := WorldEnvironment.new(); var env := Environment.new()
	var sky := Sky.new(); var sm := ShaderMaterial.new(); var sh := Shader.new()
	sh.code = "shader_type sky;
uniform vec3 arriba;
uniform vec3 abajo;
void sky() { COLOR = EYEDIR.y >= 0.0 ? arriba : abajo; }"
	sm.shader = sh; var g := Color.hex(0x557755ff).srgb_to_linear()
	sm.set_shader_parameter("arriba", Vector3(0.95, 0.95, 0.95)); sm.set_shader_parameter("abajo", Vector3(g.r, g.g, g.b) * 0.95)
	sky.sky_material = sm; sky.radiance_size = Sky.RADIANCE_SIZE_32; env.sky = sky
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY; env.ambient_light_sky_contribution = 1.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES; env.tonemap_exposure = 1.05 / 0.6 / 1.8; env.tonemap_white = 16.0
	we.environment = env; vp.add_child(we)
	var sol := DirectionalLight3D.new(); sol.light_energy = 0.8; sol.light_specular = 0.0
	vp.add_child(sol); sol.look_at_from_position(Vector3(3, 5, 4), Vector3.ZERO, Vector3.UP)
	cam = Camera3D.new(); cam.fov = 35; cam.near = 0.05; cam.far = 50; vp.add_child(cam)
	base = Node3D.new(); vp.add_child(base)

## Pone el avion de esos datos; factor: distancia de la camara respecto a la envergadura.
func mostrar(datos: Dictionary, factor := 1.0) -> void:
	if av3d: av3d.queue_free()
	av3d = Avion3D.new(datos); base.add_child(av3d)
	av3d.transform = Transform3D(Basis(Avion3D.ned([1.0, 0.0, 0.0]), Avion3D.ned([0.0, 1.0, 0.0]), Avion3D.ned([0.0, 0.0, 1.0])), Vector3.ZERO)
	var r: float = float(datos.get("b_m", 1.0)) * 0.9 * factor
	cam.position = Vector3(r * 0.9, r * 0.45, r * 1.1); cam.look_at(Vector3.ZERO, Vector3.UP)

func _process(dt: float) -> void:
	if not is_visible_in_tree() or av3d == null: return
	_t += dt * 1000.0
	base.rotation.y = _t * 0.0004
	av3d.timon.rotation = Vector3(0, 0, -0.3 * sin(_t * 0.002))
	av3d.prof.rotation = Vector3(0, 0.2 * sin(_t * 0.0017), 0)
	for p in av3d.alerones:
		var ang: float = p.get_meta("signo") * 0.25 * sin(_t * 0.0023) + (0.2 * sin(_t * 0.0017) if p.get_meta("prof") else 0.0)
		p.basis = Basis(p.get_meta("eje"), ang)
