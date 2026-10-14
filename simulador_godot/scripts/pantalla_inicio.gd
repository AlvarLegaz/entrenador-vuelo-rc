class_name PantallaInicio
extends Control
## Pantalla de inicio (#pInicio de simulador/simulador.html): la ortofoto de Cartagena de fondo con el degradado, el
## titulo, el menu (Vuelo libre, Entrenamientos, Hangar, Ajustes), el avion elegido girando a la derecha y el pie con
## el piloto y el aula.

const ICONOS := {
	"perfil": '<svg viewBox="0 0 24 24" fill="none" stroke="#ffc83d" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="8" r="4"/><path d="M4 21c0-4.4 3.6-8 8-8s8 3.6 8 8"/></svg>',
	"multi": '<svg viewBox="0 0 24 24" fill="none" stroke="#ffc83d" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><circle cx="9" cy="8" r="3.2"/><path d="M3 20c0-3.3 2.7-6 6-6s6 2.7 6 6"/><circle cx="17" cy="9" r="2.6"/><path d="M15.5 14.2c3 .2 5.5 2.6 5.5 5.8"/></svg>',
	"operaciones": '<svg viewBox="0 0 24 24" fill="none" stroke="#ffc83d" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="7" width="18" height="13" rx="2"/><path d="M8 7V5a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"/><path d="M3 13h18"/></svg>',
	"volar": '<svg viewBox="0 0 24 24" fill="none" stroke="#ffc83d" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><path d="M2.5 19l19-7-19-7 4 7-4 7z"/><path d="M6.5 12h15"/></svg>',
	"entrenar": '<svg viewBox="0 0 24 24" fill="none" stroke="#ffc83d" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="9"/><circle cx="12" cy="12" r="5"/><circle cx="12" cy="12" r="1.2" fill="#ffc83d"/></svg>',
	"hangar": '<svg viewBox="0 0 24 24" fill="none" stroke="#ffc83d" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><path d="M3 20V9l9-5 9 5v11"/><path d="M7 20v-7h10v7"/><path d="M3 20h18"/></svg>',
	"ajustes": '<svg viewBox="0 0 24 24" fill="none" stroke="#ffc83d" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z"/></svg>',
}

var p: Node
var previa: VistaPrevia
var nombre_avion: Label
var desc_avion: Label
var perfil: Button; var perfil_nombre: Label; var perfil_modo: Label
var chip_aula: Label

func _init(p_: Node) -> void:
	p = p_
	set_anchors_preset(Control.PRESET_FULL_RECT); mouse_filter = Control.MOUSE_FILTER_STOP
	# fondo: color, ortofoto de la region a pantalla completa (cover) y el degradado que oscurece la izquierda y abajo
	var fondo := ColorRect.new(); fondo.color = Tema.FONDO; fondo.set_anchors_preset(Control.PRESET_FULL_RECT); add_child(fondo)
	if p.orto.size() > 1:
		var foto := TextureRect.new(); foto.texture = p.orto[1]; foto.set_anchors_preset(Control.PRESET_FULL_RECT)
		foto.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; foto.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED; add_child(foto)
	add_child(_degradado(true)); add_child(_degradado(false))
	var v := VBoxContainer.new(); v.set_anchors_preset(Control.PRESET_FULL_RECT); v.add_theme_constant_override("separation", 0); add_child(v)
	var cuerpo := HBoxContainer.new(); cuerpo.size_flags_vertical = Control.SIZE_EXPAND_FILL; cuerpo.add_theme_constant_override("separation", 0); v.add_child(cuerpo)
	# columna izquierda: titulo y menu
	var izq := VBoxContainer.new(); izq.add_theme_constant_override("separation", 10); izq.custom_minimum_size.x = 460
	cuerpo.add_child(Tema.margen(izq, 48, 48, 40, 24))
	var pre := Tema.etiqueta("SIMULADOR DE VUELO RC", 12, Tema.ACENTO, true)
	var fv := FontVariation.new(); fv.base_font = Tema.negrita; fv.spacing_glyph = 4; pre.add_theme_font_override("font", fv); izq.add_child(pre)
	izq.add_child(Tema.etiqueta("Entrenador de vuelo", 44, Tema.TEXTO, true))
	var lp := Tema.sub("Aprende a volar antes de lanzar el avión de verdad: misma física, mismos aviones.", 15); lp.custom_minimum_size.x = 372; izq.add_child(lp)
	izq.add_child(Tema.margen(Control.new(), 0, 0, 0, 16))
	izq.add_child(_boton_menu("volar", "Vuelo libre", "El campo de vuelo del club o el Campo de Cartagena con mapa real", func(): p.ir_volar()))   # se vuela con el perfil activo (o sin perfil)
	izq.add_child(_boton_menu("entrenar", "Entrenamientos", "Misiones con objetivos para cada vehículo: el avión, el DJI y el dron FPV", func(): p.ir_entrenamientos()))
	izq.add_child(_boton_menu("multi", "Multijugador", "Vuela con tus compañeros en la misma sala del aula: os veis unos a otros", func(): p.ir_multi()))
	izq.add_child(_boton_menu("operaciones", "Operaciones", "Trabajos de operador de dron: inspección, fotogrametría, rescate, agricultura, paneles solares y vídeo", func(): p.ir_operaciones()))
	izq.add_child(_boton_menu("hangar", "Hangar", "Elige el avión, mira su ficha y ajusta el centro de gravedad y la emisora", func(): p.ir_hangar()))
	izq.add_child(_boton_menu("perfil", "Perfil", "Elige tu perfil, local u online, y mira tu progreso", func(): p.ir_pilotos(p.ir_inicio)))
	izq.add_child(_boton_menu("ajustes", "Ajustes", "Mando, gráficos, sonido, dificultad y registro de vuelos", func(): p.ir_ajustes("")))
	# derecha: el avion girando y su nombre
	var der := Control.new(); der.size_flags_horizontal = Control.SIZE_EXPAND_FILL; cuerpo.add_child(der)
	previa = VistaPrevia.new(); previa.set_anchors_preset(Control.PRESET_FULL_RECT); der.add_child(previa)
	var na := VBoxContainer.new(); na.anchor_left = 1; na.anchor_right = 1; na.anchor_top = 1; na.anchor_bottom = 1
	na.offset_right = -36; na.offset_bottom = -90; na.grow_horizontal = Control.GROW_DIRECTION_BEGIN; na.grow_vertical = Control.GROW_DIRECTION_BEGIN
	nombre_avion = Tema.etiqueta("", 26, Tema.TEXTO, true); nombre_avion.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT; na.add_child(nombre_avion)
	desc_avion = Tema.etiqueta("", 14, Tema.SUAVE); desc_avion.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT; na.add_child(desc_avion)
	der.add_child(na)
	# encima del dron: el perfil elegido (#inicioPerfil de la web); pulsandolo se cambia
	perfil = Button.new(); perfil.focus_mode = Control.FOCUS_NONE; perfil.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND; perfil.tooltip_text = "Cambiar de perfil"
	perfil.add_theme_stylebox_override("normal", Tema.caja(Color(0, 0, 0, 0.35), Color(1, 1, 1, 0.12), 14, 1, 22, 8))
	perfil.add_theme_stylebox_override("hover", Tema.caja(Color(1, 0.78, 0.24, 0.14), Color(1, 0.78, 0.24, 0.5), 14, 1, 22, 8))
	perfil.add_theme_stylebox_override("pressed", Tema.caja(Color(1, 0.78, 0.24, 0.14), Color(1, 0.78, 0.24, 0.5), 14, 1, 22, 8))
	perfil.anchor_left = 0.5; perfil.anchor_right = 0.5; perfil.offset_top = 36; perfil.grow_horizontal = Control.GROW_DIRECTION_BOTH
	perfil.pressed.connect(func(): p.ir_pilotos(p.ir_inicio))
	var pv := VBoxContainer.new(); pv.add_theme_constant_override("separation", 0); pv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pt := Tema.etiqueta("PERFIL", 11, Tema.ACENTO, true); var fv2 := FontVariation.new(); fv2.base_font = Tema.negrita; fv2.spacing_glyph = 2; pt.add_theme_font_override("font", fv2)
	perfil_nombre = Tema.etiqueta("", 26, Tema.TEXTO, true); perfil_modo = Tema.etiqueta("", 13, Tema.SUAVE)
	for l in [pt, perfil_nombre, perfil_modo]: l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; l.mouse_filter = Control.MOUSE_FILTER_IGNORE; pv.add_child(l)
	perfil.add_child(pv); pv.set_anchors_preset(Control.PRESET_FULL_RECT); pv.offset_left = 22; pv.offset_right = -22; pv.offset_top = 8; pv.offset_bottom = -8
	der.add_child(perfil)
	# pie: piloto, aula y version
	var pie := HBoxContainer.new(); pie.add_theme_constant_override("separation", 10)
	chip_aula = Tema.etiqueta("", 13, Tema.SUAVE); pie.add_child(chip_aula)
	pie.add_child(Tema.espacio()); pie.add_child(Tema.etiqueta("Entrenador de vuelo RC · v2 Godot · © 2026 Álvar Legaz Aparicio · todos los derechos reservados", 13, Tema.SUAVE))
	v.add_child(Tema.margen(pie, 48, 12, 48, 18))

## Degradados del fondo: de izquierda a derecha (94 % -> 78 % -> 35 %) y de abajo arriba (90 % -> 0 en el 40 %).
static func _degradado(horizontal: bool) -> TextureRect:
	var g := Gradient.new(); var base := Color(8 / 255.0, 14 / 255.0, 22 / 255.0)
	if horizontal:
		g.offsets = PackedFloat32Array([0.0, 0.45, 1.0]); g.colors = PackedColorArray([Color(base, 0.94), Color(base, 0.78), Color(base, 0.35)])
	else:
		g.offsets = PackedFloat32Array([0.0, 0.6, 1.0]); g.colors = PackedColorArray([Color(base, 0.0), Color(base, 0.0), Color(base, 0.9)])
	var gt := GradientTexture2D.new(); gt.gradient = g; gt.width = 256; gt.height = 256
	if horizontal: gt.fill_from = Vector2(0, 0.5); gt.fill_to = Vector2(1, 0.5)
	else: gt.fill_from = Vector2(0.5, 0); gt.fill_to = Vector2(0.5, 1)
	var t := TextureRect.new(); t.texture = gt; t.set_anchors_preset(Control.PRESET_FULL_RECT); t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_SCALE; t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t

func _boton_menu(icono: String, titulo: String, texto: String, f: Callable) -> Button:
	var b := Button.new(); b.theme_type_variation = "BotonMenu"; b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND; b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(372, 76); b.pressed.connect(f)
	var h := HBoxContainer.new(); h.add_theme_constant_override("separation", 16); h.set_anchors_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 18; h.offset_right = -18; h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ic := TextureRect.new(); ic.texture = Tema.svg(ICONOS[icono], 3.0); ic.custom_minimum_size = Vector2(34, 34)
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED; ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE; h.add_child(ic)
	var tv := VBoxContainer.new(); tv.add_theme_constant_override("separation", 2); tv.alignment = BoxContainer.ALIGNMENT_CENTER; tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tv.add_child(Tema.etiqueta(titulo, 19, Tema.TEXTO, true))
	var s := Tema.etiqueta(texto, 13, Tema.SUAVE, false, true); s.mouse_filter = Control.MOUSE_FILTER_IGNORE; tv.add_child(s)
	for c in tv.get_children(): c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(tv); b.add_child(h)
	b.mouse_entered.connect(func(): var tw := b.create_tween(); tw.tween_property(h, "position:x", 22.0, 0.12))
	b.mouse_exited.connect(func(): var tw := b.create_tween(); tw.tween_property(h, "position:x", 18.0, 0.12))
	return b

func refrescar() -> void:
	var A := DatosComunes.avion(p.sesion["avion"])
	nombre_avion.text = String(A.get("nombre", ""))
	desc_avion.text = String(A.get("descripcion", "")).split(". ")[0]
	var al = p.sesion["alumno"]; var A_: Aula = p.aula
	perfil_nombre.text = String(al["nombre"]) if al != null else "Sin perfil"
	perfil_modo.text = "los vuelos no se guardan" if not A_.activo else ("elige tu perfil para guardar los vuelos" if al == null
		else ("local · este ordenador" if A_.modo == "local" else "online · aula " + A_.nombre_aula))
	perfil.custom_minimum_size = Vector2.ZERO; perfil.reset_size()
	var w := maxf(perfil_nombre.get_minimum_size().x, perfil_modo.get_minimum_size().x) + 44
	perfil.custom_minimum_size = Vector2(w, 84); perfil.offset_left = -w / 2; perfil.offset_right = w / 2
	chip_aula.text = p.aula.texto_estado()
	previa.mostrar(A, 1.75)
