extends Node3D
class_name Principal
## UxS Trainer (entrenador de sistemas no tripulados), version 2 (Godot 4). Es la MISMA aplicacion que la version 1 (simulador_web/simulador.html): las
## mismas pantallas (inicio, pilotos, hangar, entrenamientos, vuelo libre, punto de lanzamiento, ajustes, resultado y
## progreso), el mismo HUD, las mismas misiones (datos/escenarios.js), el aula (pantalla de acceso: servidor, usuario y contrasena, o sin conexion), la caja
## negra, la repeticion, el sonido y el dron comercial con su app. Los aviones, el mundo y la fisica son comunes (modelo_avion.gd,
## modelo_cuadricoptero.gd y entorno.gd traducen modelos.js, DJI_MINI.js y entorno.js; ver Tests/). Este fichero es
## el estado de la aplicacion (sesion, avion, mando, vuelo...), lo que llama el motor (_ready, _process, _unhandled_input)
## y lo que se usa desde todas partes (es_dron, en_mundo, poner_toast, mostrar...), como js/app/estado.js de la web. Las
## funciones de cada parte estan en sus componentes, scripts/app/ (app_vuelo, app_mandos, app_camaras, app_hud...), con
## los mismos nombres que los modulos de la web (simulador_web/js/app/). Lo que se dibuja esta en las pantallas
## (pantalla_*.gd), hud_vuelo.gd, hud_dji.gd y capas.gd.
##
## Opciones de linea de ordenes (tras --), para pruebas: --auto (vuela sin menu), --escenario=ID (libre_cartagena),
## --avion=ID, --camara=N, --gases=0..1, --esperar=S, --captura=ruta.png (guarda la pantalla a los S segundos y sale),
## --pantalla=pInicio|pHangar|... (captura de una pantalla), --calidad=0..2, --dificultad=real|facil, --cenital=H, --traza,
## --terminar=S (termina el vuelo a los S s de vuelo: captura del resultado), --pausa=S y --ayuda=S (pausa o controles a los S s),
## --repeticion (con --terminar: abre la repeticion desde el resultado), --lat=G --lon=G [--rumbo=G] (punto de despegue en un mundo real), --destacado[=K] (el punto destacado K del mapa, 1 = el CIFP, 2 = Los Halcones).

const DT := 1.0 / 500
const D2R := PI / 180.0
const R2D := 180.0 / PI
const G0 := 9.81
const RHO := 1.225
const CN_CADA := 25
const LANZ := { "prueba_s": 5.0, "fallo_s": 6.0, "fallo_h": 5.0 }
const MUNDO := "cartagena"
const LANZ_DEFECTO := { "cartagena": { "lat": 37.648889, "lon": -1.193194, "rumbo": 90 } }   # 37°38'56.0"N 1°11'35.5"W, hacia el este
# recorrido mecanico (grados a palanca a tope sin dual rate) de cada avion: el mismo que en simulador.html
const RECORRIDO_MECANICO := { "E3": { "prof": 12, "aleron": 15 }, "T1": { "prof": 15, "aleron": 15 } }
const DIFICULTAD_INFO := {
	"real": "Par y estela de la hélice (el avión tiende a alabear y guiñar a la izquierda con gas), efecto P y giroscópico, pérdida por semiala (cae de un ala, puede entrar en barrena), efecto suelo, resistencia de perfil y de la hélice parada, viento más flojo junto al suelo, turbulencia que alabea, densidad según la temperatura, calibración con el avión real y lanzamiento con dispersión.",
	"facil": "Sin par ni estela de la hélice, sin efectos P ni giroscópico, pérdida simétrica, sin efecto suelo, el mismo viento a cualquier altura, rachas sin alabeo, aire estándar y lanzamiento perfecto. Para aprender; el avión real se parece más al modo real." }
const CN_COLUMNAS := ["t_s", "x_norte_m", "y_este_m", "z_altura_m", "vel_aire_ms", "vel_suelo_ms", "vel_vertical_ms",
	"alabeo_grados", "cabeceo_grados", "rumbo_grados", "alfa_grados", "resbale_grados", "carga_g",
	"gases_pct", "motor_rpm", "empuje_N", "energia_Wh", "bateria_pct", "palanca_profundidad", "palanca_timon",
	"compensador_grados", "profundidad_grados", "timon_grados", "aleron_grados", "viento_norte_ms", "viento_este_ms", "perdida"]
const NOMBRES_MODO := { "C": "Cine", "N": "Normal", "S": "Sport" }

# ---- sesion y ajustes (se guardan en user://) ----
var sesion := { "alumno": null, "sin_registrar": false, "avion": "", "escenario": "libre", "viento": { "vel": 2.0, "desde": 0, "rachas": true },
				"dificultad": "facil", "lanz": {}, "lanz_real": true }
var aj := { "calidad_modo": "auto", "zoom_piloto": 0.03, "zoom_v": 0, "cn_auto": false, "cm": {}, "cfg_avion": {} }
var sitio_sel := "libre"
var ids_aviones := []

# ---- vuelo ----
var ent := Entorno.new()
var _ent_campo := Entorno.new()     # el campo del club (para las fichas de las misiones, aunque se este en un mundo real)
var modelo                          # ModeloAvion o ModeloCuadricoptero
var av := {}
var mando := { "pitch": 0.0, "yaw": 0.0, "pitchObj": 0.0, "yawObj": 0.0, "trim": 0.0, "guinada": 0.0, "vz": 0.0, "guinadaObj": 0.0, "vzObj": 0.0, "gimbal": 0.0 }
var vuelo = null                    # registro del vuelo en curso (de L al final)
var ultimo_vuelo = null
var ev: Escenarios.Evaluador = null
var piloto: PilotoUAV = null        # UAV: su piloto automatico (piloto_uav.gd)
var _piloto_visto := ""
var cn_contador := 0
var casa := { "N": 0.0, "E": 0.0 }
var vel_perdida := 8.0
var camara := 1
var era_dron := false
var sin_instrumentos := false
var mostrar_hud := false
var pausado := false
var salir_tras := false
var pantalla_actual := "pInicio"
var DJI := { "grabando": false, "tRec": 0.0, "fotos": 0, "video": false, "tAnt": 0.0, "zoomI": 0, "termica": false }
var REP := { "activa": false, "filas": [], "t": 0.0, "dur": 0.0, "pausa": false, "i": 0, "vuelo": null }
var rep_activa := false
var _acum := 0.0
var _t_obj := 0.0
var _vs := 0.0
var _fov1 := -1.0
var _mando_usado := false
var _gas_fpv_mando := false          # FPV con mando de consola: la palanca del gas manda (gasFpv de la web)
var _botones_antes := {}
var _cache_lanz := { "clave": null }
var _cache_gmin := {}

# ---- mundo y dibujo ----
var mundo_datos := {}
var indice_zonas := []
var zonas_cache := {}
var orto := []                      # [Image, ImageTexture] de la region
var mundo3d: Mundo3D
var campo3d: Campo3D
var vista: Node3D                   # el mundo puesto (mundo3d o campo3d)
var avion3d: Avion3D
var cam: Camera3D
var vr: ModoVR                     # gafas de realidad virtual (modo_vr.gd), si las hay

# ---- interfaz ----
var aula: Aula
var mando_cfg := MandoCfg.new()
var sonido: Sonido
var ui: CanvasLayer
var hud: HudVuelo
var hud_dji: HudDji
var hud_uav: HudUav                 # estacion de control del UAV (hud_uav.gd)
var hud_carrera: HudCarrera         # carrera de drones: barra de arriba e indicador del siguiente obstaculo (hud_carrera.gd)
var carrera_mejor = null            # carrera: el mejor tiempo de esta sesion { t, avion } (CARRERA_MEJOR de la web)
var destino_prueba = null           # pruebas: tras la fisica de cada paso, el dron se pone aqui (prueba_carrera.gd)
var mira_recon: Control             # reconocimiento con un avion: la mira de la camara de a bordo
var op_vehiculo := {}               # operaciones que dejan elegir el vehiculo (la carrera): el elegido por trabajo
var briefing: PanelContainer; var briefing_img: TextureRect
var hud_fpv: HudFPV                 # OSD de Betaflight del dron FPV
var pantallas := {}
var condiciones: PantallaMisiones.Condiciones
var pausa := {}
var carga := {}
var modal := {}
var dialogo: FileDialog
signal _modal_resp(si: bool)

var _args := {}
var _t_auto := 0.0
var _rend := []
var _us := []                      # pruebas: microsegundos de la fisica y de todo _process de esta escena

# ---- componentes (scripts/app/, como js/app/ de la web): las funciones de cada parte; el estado, aqui ----
var app_apps_dron := AppAppsDron.new(self)
var app_avion_ajustes := AppAvionAjustes.new(self)
var app_camaras := AppCamaras.new(self)
var app_evaluacion := AppEvaluacion.new(self)
var app_hud := AppHud.new(self)
var app_mandos := AppMandos.new(self)
var app_multijugador := AppMultijugador.new(self)
var app_pantallas := AppPantallas.new(self)
var app_repeticion := AppRepeticion.new(self)
var app_resultado := AppResultado.new(self)
var app_vuelo := AppVuelo.new(self)

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	get_window().title = "UxS Trainer"
	ids_aviones = DatosComunes.aviones()
	app_avion_ajustes._cargar()
	if _args.has("avion"): sesion["avion"] = _args["avion"]
	if _args.has("calidad"): aj["calidad_modo"] = "min" if _args["calidad"] == "min" else str(int(_args["calidad"]))
	if _args.has("dificultad"): sesion["dificultad"] = _args["dificultad"]
	if not app_avion_ajustes.ids_hangar().has(sesion["avion"]): sesion["avion"] = "DJI_MINI" if ids_aviones.has("DJI_MINI") else ids_aviones[0]   # por defecto, el dron comercial
	mundo_datos = DatosComunes.mundo(MUNDO)
	ent.poner_mundo(mundo_datos); ent.poner_mundo({})      # el terreno del mundo queda guardado (mapa, rumbo despejado)
	indice_zonas = DatosComunes.indice_zonas().filter(func(z): return z["mundo"] == MUNDO)
	orto = Mundo3D.cargar_orto_region(MUNDO)
	cam = Camera3D.new(); cam.near = 0.05; cam.far = 16000.0; cam.fov = 50; add_child(cam); cam.current = true
	aula = Aula.new(); add_child(aula)
	sonido = Sonido.new(); add_child(sonido); sonido.cargar_cfg()
	app_pantallas._construir_ui()
	vr = ModoVR.iniciar(self)
	if vr != null:                     # en unas gafas: directamente a volar el dron en el campo del club (sin menus en VR todavia)
		ui.visible = false; sesion["escenario"] = "libre"; sesion["sin_registrar"] = true
		sesion["avion"] = "DJI_MINI"
		app_vuelo.empezar.call_deferred()
		return
	if _args.has("auto"):
		sesion["escenario"] = _args.get("escenario", "libre_cartagena"); sesion["sin_registrar"] = true
		var O: Dictionary = Escenarios.datos()[sesion["escenario"]].get("operacion", {})       # pruebas: un trabajo, desde su punto de despegue
		if not O.is_empty(): sesion["lanz"] = { "mundo": mundo_datos["id"], "N": float(O["salida"]["n"]), "E": float(O["salida"]["e"]), "rumbo": float(O["salida"]["rumbo"]) }
		if Escenarios.es_mundo(sesion["escenario"]): app_evaluacion._lanz_por_defecto()
		if _args.has("destacado") and not app_evaluacion.destacados_lanz().is_empty(): app_evaluacion.elegir_destacado(app_evaluacion.destacados_lanz()[clampi(int(_args["destacado"]) - 1, 0, app_evaluacion.destacados_lanz().size() - 1)])      # pruebas: despegar del CIFP
		if _args.has("lat") and _args.has("lon"):      # pruebas: despegar desde (lat, lon) con el rumbo dado o el mas despejado
			var ne := app_evaluacion.lat_lon_a_ne(mundo_datos, float(_args["lat"]), float(_args["lon"]))
			sesion["lanz"] = { "mundo": mundo_datos["id"], "N": round(ne[0]), "E": round(ne[1]),
							   "rumbo": float(_args["rumbo"]) if _args.has("rumbo") else app_evaluacion.rumbo_despejado(ne[0], ne[1]) }
		app_vuelo.empezar.call_deferred()
		return
	if _args.has("pantalla") or _args.has("captura"): app_pantallas.ir_inicio()        # capturas: sin conexion
	else: app_pantallas.ir_acceso()                            # lo primero: la pantalla de acceso (aula o sin conexion)
	if _args.has("pantalla"):
		var id: String = _args["pantalla"]
		match id:
			"pHangar": app_pantallas.ir_hangar()
			"pEntrenamientos": app_pantallas.ir_entrenamientos()
			"pVolar": app_pantallas.ir_volar()
			"pOperaciones": app_pantallas.ir_operaciones()
			"pTaller": app_pantallas.ir_taller()
			"pAjustes": app_pantallas.ir_ajustes(_args.get("seccion", ""))
			"pAlumno": app_pantallas.ir_acceso()
			"pLanzamiento":
				sesion["escenario"] = "libre_cartagena"; app_pantallas.ir_lanzamiento()
				if _args.has("destacado") and not app_evaluacion.destacados_lanz().is_empty(): app_evaluacion.elegir_destacado(app_evaluacion.destacados_lanz()[clampi(int(_args["destacado"]) - 1, 0, app_evaluacion.destacados_lanz().size() - 1)]); pantallas["pLanzamiento"].pintar()
	if _args.has("captura"):
		await get_tree().create_timer(float(_args.get("esperar", "2"))).timeout
		get_viewport().get_texture().get_image().save_png(_args["captura"]); get_tree().quit()

# =====================================================================
#  GUARDADO (localStorage de la web)
# =====================================================================

# ---- centro de gravedad y peso (cmCfg), emisora y calibracion (cfgAvion) ----

# =====================================================================
#  MODELO DE VUELO: CG y peso, calibracion, recorridos de la emisora y dificultad
# =====================================================================
func es_dron() -> bool: return modelo is ModeloCuadricoptero or modelo is ModeloFPV
func es_fpv() -> bool: return modelo is ModeloFPV
func es_bipode() -> bool: return modelo is ModeloBipode

# ---- el robot (vehiculo oculto, datos.oculto): solo para el piloto con los tres logros del perfil (robotDesbloqueado de la web) ----

# =====================================================================
#  LANZAMIENTO A MANO (pruebaLanzamiento, gasMinimoLanzamiento...)
# =====================================================================
const RUMBOS_TXT := ["norte", "nordeste", "este", "sudeste", "sur", "sudoeste", "oeste", "noroeste"]

# =====================================================================
#  PUNTO DE LANZAMIENTO EN EL MUNDO REAL
# =====================================================================
func en_mundo() -> bool: return not ent.mundo.is_empty()
func es_uav() -> bool: return modelo is ModeloAvion and modelo.datos.get("uav", false)

# =====================================================================
#  INTERFAZ: pantallas, HUD y capas
# =====================================================================

## Muestra una pantalla ("" = el vuelo).
func mostrar(id: String) -> void:
	for k in pantallas: pantallas[k].visible = k == id
	pantalla_actual = id
	var en_vuelo := id == ""
	hud.visible = en_vuelo
	hud_dji.visible = en_vuelo and modelo != null and es_dron() and not es_fpv() and not sin_instrumentos
	hud_fpv.visible = en_vuelo and modelo != null and es_fpv() and not sin_instrumentos
	hud_uav.visible = en_vuelo and modelo != null and es_uav() and not sin_instrumentos
	if not en_vuelo: hud_carrera.visible = false
	get_viewport().disable_3d = not en_vuelo                  # en las pantallas no se dibuja el mundo
	if not en_vuelo: hud.ayuda.visible = false; app_repeticion.poner_pausa(false); sonido.silenciar(true)
	else: sonido.silenciar(not sonido.on); get_viewport().gui_release_focus()

var _t_toast := 0
var toasts_registro = null          # pruebas: si es una lista, cada aviso de poner_toast se apunta en ella
func poner_toast(txt: String) -> void:
	if toasts_registro != null: toasts_registro.append(txt)
	if vuelo != null and not av.is_empty() and av["estado"] == "volando": RegistroVuelo.evento(self, vuelo, txt)
	hud.toast.text = txt; _t_toast += 1; var n := _t_toast
	await get_tree().create_timer(1.5).timeout
	if n == _t_toast: hud.toast.text = ""

# ---- navegacion ----
# =====================================================================
#  MULTIJUGADOR: salas del servidor del aula (MULTI de la web; el mismo protocolo, se puede volar mezclado). Cada
#  simulador manda su estado 10 veces por segundo y recibe el de los demas de su sala, que se dibujan como "fantasmas"
#  (sin choques entre ellos, cada uno con su fisica).
# =====================================================================
var sala := {}                  # la sala en la que se esta ({} = ninguna)
var multi_otros := {}           # id -> el ultimo estado recibido de cada uno, con "recibido" (s)
var _multi_id := ""
var _multi_enviando := false
var _t_csc := 0.0               # dron comercial: tiempo con las palancas en la combinacion de arranque (CSC)
var _multi_t := 0.0
var _fantasmas := {}            # id -> { nodo: Avion3D, et: Label3D, p: Array (NED), avion, nombre }
var sala_info: PanelContainer
var ordenes_hud: VBoxContainer
var _ordenes_firma := ""
var _exclusiones: Node3D
# ordenes del profesor a la sala (ORDENES de la web): viento, NOTAM, aterrizaje inmediato, zonas de exclusion y el
# desaparecido de la busqueda
var ordenes := {}
const EXCLUSION_TXT := "Respetar las zonas de exclusión que marca el profesor"
var sala_info_rt: RichTextLabel

# =====================================================================
#  EMPEZAR, REINICIAR, LANZAR
# =====================================================================

## Zonas de detalle a menos de RADIO_ZONAS m del punto (N, E), primero la que lo contiene (zonasCerca de
## simulador.html): con zonas pegadas, como las de La Manga y el Mar Menor, se vuela en detalle hasta ~2 km del piloto.
const RADIO_ZONAS := 2000.0

# =====================================================================
#  PASO DE LA SIMULACION (paso() de simulador.html)
# =====================================================================

var _aviso_choque := false

# ---- juego del bipode: drones diana y disparos (JuegoBipode y EfectosBipode), sonido y marcador ----
var juego_bip: JuegoBipode = null
var efectos_bip: EfectosBipode = null
var _bip_oido := { "pisadas": 0, "disparos": 0, "derribados": 0 }

# ---- bipode en multijugador (como en la web): sus disparos derriban los aviones y drones de los compañeros. Cada
# bipode manda en su estado los impactos que lleva dados a cada piloto (golpes: id -> cuantos); quien los recibe cae al
# primer impacto. Los bipodes de los demas se ven andando y disparando (sus trazadoras, solo de adorno).
const BIP_VIDAS := 1
var _golpes_vistos := {}
var _vida_multi := BIP_VIDAS
var _caida := {}
## Trazadoras de los bipodes de los demas: por cada disparo nuevo que anuncian, una bala de adorno desde su cañon.
var _balas_otros := {}

# =====================================================================
#  RESULTADO Y GUARDADO
# =====================================================================

# =====================================================================
#  CAJA NEGRA (CSV de cada vuelo, a 20 Hz)
# =====================================================================

# =====================================================================
#  REPETICION: el vuelo grabado en la caja negra (20 Hz), interpolado
# =====================================================================

# =====================================================================
#  PAUSA
# =====================================================================

# =====================================================================
#  APP dron comercial FLY (cuadricoptero)
# =====================================================================

# =====================================================================
#  DRON FPV: armar / desarmar y modos de Betaflight (el OSD esta en hud_fpv.gd)
# =====================================================================
## Armar (solo con el gas abajo, como un FPV de verdad) o desarmar (en el aire se cae; en el suelo tras volar, aterrizado).
## Gas del FPV con un mando de consola (gasFpvConsola de la web): el centro de la palanca con muelle es el gas del
## estacionario (thr_mid de Betaflight), arriba del todo todo el gas, abajo nada, con curva suave cerca del centro; en
## el suelo con la palanca en reposo, cero (se arma sin despegar). s: palanca (+1 arriba).
const FPV_GAS_ESTACIONARIO := 0.30               # medido: el FPV de 650 g se sostiene con el 30,4 % (bateria llena)

# =====================================================================
#  TECLADO
# =====================================================================
func _unhandled_input(e: InputEvent) -> void:
	if pantalla_actual != "" or modal["raiz"].visible: return
	if e is InputEventMouseButton and e.pressed and (e.button_index == MOUSE_BUTTON_WHEEL_UP or e.button_index == MOUSE_BUTTON_WHEEL_DOWN) and camara == 1:
		# con la camara del piloto, la rueda del raton cambia el zoom (fuera del GPS, que tiene su propia rueda)
		var abajo: bool = e.button_index == MOUSE_BUTTON_WHEEL_DOWN; var z0: float = aj.get("zoom_piloto", 0.03)
		var z := clampf(z0 * (0.85 if abajo else 1 / 0.85) if z0 > 0 else (0.03 if not abajo else 0.0), 0, 0.3)
		app_avion_ajustes.poner_zoom_piloto(0.0 if (z < 0.025 and abajo) else snappedf(z, 0.001))
		poner_toast(("Zoom del piloto: el avión ocupa un %d %% de la pantalla" % int(round(aj["zoom_piloto"] * 100))) if aj["zoom_piloto"] > 0 else "Sin zoom: como lo ve el ojo")
		return
	if not (e is InputEventKey and e.pressed and not e.echo): return
	var k: int = e.physical_keycode
	if rep_activa:          # repeticion: espacio pausa, flechas 5 s, 1/2/3 camara, Esc sale
		match k:
			KEY_ESCAPE: app_repeticion._salir_repeticion()
			KEY_SPACE: REP["pausa"] = not REP["pausa"]
			KEY_LEFT: REP["t"] = maxf(0, REP["t"] - 5)
			KEY_RIGHT: REP["t"] = minf(REP["dur"], REP["t"] + 5)
			KEY_1: camara = 1
			KEY_2: camara = 2
			KEY_3: camara = 3
		get_viewport().set_input_as_handled(); return
	if k == KEY_ESCAPE:     # con la ventana de controles abierta, Esc la cierra (y sigue el vuelo); si no, pausa
		if briefing.visible: app_vuelo.ver_briefing(false)
		elif hud.ayuda.visible: hud.ayuda.visible = false; app_repeticion.poner_pausa(false)
		else: app_repeticion.poner_pausa(not pausado)
		get_viewport().set_input_as_handled(); return
	if pausado: return
	var libre := Escenarios.libre(sesion["escenario"]); var vto: Dictionary = ent.viento; var dron := es_dron()
	if es_bipode():         # bipode: L arranca / aparca; espacio dispara y F cierra el puño (mientras se tienen pulsados)
		match k:
			KEY_L: app_vuelo.lanzar()
			KEY_R: app_vuelo.reiniciar()
			KEY_1: camara = 1
			KEY_2: camara = 2
			KEY_3: camara = 3
			KEY_T: hud.ayuda.visible = not hud.ayuda.visible
		get_viewport().set_input_as_handled(); return
	if es_fpv():            # dron FPV: L arma y desarma, M cambia de modo
		match k:
			KEY_M: app_apps_dron.fpv_modo()
			KEY_L: app_apps_dron.fpv_armar()
	elif dron:
		match k:
			KEY_M: app_apps_dron.dji_modo()
			KEY_H: app_apps_dron.dji_rth()
			KEY_F: app_apps_dron.dji_foto()
			KEY_V: app_apps_dron.dji_video()
			KEY_Z: app_apps_dron.dji_zoom(1)
			KEY_X: app_apps_dron.dji_zoom(-1)
			KEY_C: app_apps_dron.dji_termica()
	match k:
		KEY_L:
			if not es_fpv(): app_vuelo.lanzar()
		KEY_R: app_vuelo.reiniciar()
		KEY_B: app_vuelo.ver_briefing()
		KEY_SPACE:
			if con_tren(): app_mandos.quitar_freno_aparc()
			else: av["gases"] = 0.0
		KEY_1: camara = 1
		KEY_2: camara = 2
		KEY_3: camara = 3
		KEY_I:
			sin_instrumentos = not sin_instrumentos
			poner_toast(("Sin OSD" if sin_instrumentos else "OSD") if es_fpv() else ("Sin la pantalla de la app" if sin_instrumentos else "Pantalla de la app") if dron else ("Sin instrumentos (como en el campo)" if sin_instrumentos else "Instrumentos"))
		KEY_T: hud.ayuda.visible = not hud.ayuda.visible
		KEY_BRACKETLEFT: mando["trim"] = maxf(-6, mando["trim"] - 0.25)
		KEY_BRACKETRIGHT: mando["trim"] = minf(6, mando["trim"] + 0.25)
	if es_uav():                          # UAV: M modo del piloto automatico, H vuelta a base, P despegue o aterrizaje automatico
		if k == KEY_M: app_mandos.uav_modo()
		if k == KEY_H: app_mandos.uav_poner("BASE")
		if k == KEY_P: app_mandos.uav_poner("DESPEGUE" if av.get("enTierra", false) else "ATERRIZAJE")
		if k == KEY_Z: app_apps_dron.dji_zoom(1)
		if k == KEY_X: app_apps_dron.dji_zoom(-1)
		if k == KEY_C: app_apps_dron.dji_termica()
		if k == KEY_K: app_camaras.uav_fijar()
		if k == KEY_V and app_evaluacion.morro_de(sesion["avion"]) == "fijo": app_camaras.cambiar_vista_fija()
		if k == KEY_F: app_camaras.uav_foto()
	elif k == KEY_H and not dron: mostrar_hud = not mostrar_hud
	if k == KEY_F and not es_uav() and not dron and ev != null and ev.op != null and ev.op.d.has("recon"): app_camaras.avion_foto()     # reconocimiento con el Poli-1 o el Entrenador 1
	if k == KEY_G and libre: vto["rachas"] = not vto["rachas"]
	var tecla: int = e.keycode
	if libre and (tecla == KEY_PLUS or tecla == KEY_KP_ADD or (e.unicode == 43)): vto["base"] = minf(10, vto["base"] + 1)
	if libre and (tecla == KEY_MINUS or tecla == KEY_KP_SUBTRACT or (e.unicode == 45)): vto["base"] = maxf(0, vto["base"] - 1)
	get_viewport().set_input_as_handled()

# =====================================================================
#  MANDO: palanca derecha = avion, izquierda = gas (o el mando del dron comercial). Ejes segun Ajustes › Controles (MandoCfg).
# =====================================================================

var _mando_disparo := false; var _mando_puno := false; var _mando_freno := false
## ---- torreta EO/IR del UAV (como en la web): av.torreta {pan, tilt}, su punto fijo (K) y el punto de la cruz ----
var UAV := { "fijo": null, "cruz": null, "fotos": 0 }
var _mando_torreta := []
const TORRETA_VEL := 45 * PI / 180
## Avion de pista (con tren): el freno de aparcamiento se quita con el primer espacio (o B); despues frenan mientras se pulsan.
func con_tren() -> bool: return modelo is ModeloAvion and modelo.tren != null

# =====================================================================
#  BUCLE, CAMARAS Y HUD
# =====================================================================
func _process(dt_real: float) -> void:
	var dt := minf(0.1, dt_real)
	if not sala.is_empty():                           # multijugador: 10 veces por segundo
		_multi_t += dt_real
		if _multi_t >= 0.1: _multi_t = 0.0; app_multijugador._enviar_sala()
	if pantalla_actual != "" or av.is_empty() or modelo == null:
		_acum = 0.0
		if pantalla_actual != "": app_hud._leer_mando_en_menu()
		if vr != null and pantalla_actual != "": vr.en_pantalla(dt_real)
		if _args.has("auto") and modelo != null and not av.is_empty(): app_hud._auto(dt_real)      # pruebas: la captura puede ser del resultado
		return
	var t_us := Time.get_ticks_usec()
	if rep_activa: app_repeticion._paso_repeticion(dt)
	elif pausado: app_mandos._leer_mando(dt)
	else:
		if _args.has("auto"): app_hud._piloto_auto()
		else: app_mandos._leer_teclado(dt); app_camaras.mover_torreta(dt)
		_acum += dt
		while _acum >= DT: app_vuelo.paso(DT); _acum -= DT
		app_vuelo._paso_juego_bip(dt)
		var b: Vector3 = vista.base + Vector3(1.5, 1.7, 2)
		sonido.actualizar(av, Sonido.lejos_de(b.distance_to(Avion3D.ned(av["p"]))), camara == 1)
		_t_obj += dt
		if _t_obj > 0.2: _t_obj = 0; app_hud._pintar_objetivos(); app_multijugador._pintar_sala_info()
	var t_fis := Time.get_ticks_usec() - t_us
	avion3d.camara_fpv = es_fpv() and camara == 3     # con la camara FPV el dron no se dibuja
	avion3d.actualizar(av)
	if not sala.is_empty() or not _fantasmas.is_empty(): app_multijugador._poner_fantasmas()
	vista.actualizar_manga(ent.viento["actual"])
	app_hud._camara()
	if vr != null: vr.actualizar(dt_real)
	app_hud._termica(app_apps_dron.cam_dji()["termica"] and camara == 3 and ((es_dron() and not es_fpv()) or es_uav()))
	app_hud._hud()
	if _args.has("auto") and _t_auto > 1.5: _us.append([t_fis, Time.get_ticks_usec() - t_us])
	app_hud._auto(dt_real)

## Imagen de la camara termica (dron de inspeccion, camara 3): _renderTermico de visor.js. La camara ve tambien la capa 2
## (lo que solo se ve en la termica, en colores clave: mundo_3d.gd, _termicos), el entorno pasa a tonemap lineal sin
## brillo, ajustes ni SSAO, y un cuadro a toda pantalla pasa la imagen (a 640 px de ancho) por la paleta Ironbow.
var _ter: MeshInstance3D; var _ter_env: Environment; var _ter_de: Environment
const SOMBREADOR_TERMICA := """shader_type spatial;
render_mode unshaded, depth_draw_never, depth_test_disabled, cull_disabled, fog_disabled, shadows_disabled;
uniform sampler2D pantalla : hint_screen_texture, filter_nearest;
uniform sampler2D prof : hint_depth_texture, filter_nearest;
uniform vec2 res = vec2(640.0, 360.0);
vec3 ironbow(float t) {
	vec3 c0 = vec3(0.0, 0.0, 0.05), c1 = vec3(0.12, 0.0, 0.36), c2 = vec3(0.55, 0.0, 0.55), c3 = vec3(0.86, 0.16, 0.2), c4 = vec3(1.0, 0.5, 0.0), c5 = vec3(1.0, 0.86, 0.2), c6 = vec3(1.0, 1.0, 0.93);
	if (t < 0.15) return mix(c0, c1, t / 0.15);
	if (t < 0.35) return mix(c1, c2, (t - 0.15) / 0.2);
	if (t < 0.55) return mix(c2, c3, (t - 0.35) / 0.2);
	if (t < 0.72) return mix(c3, c4, (t - 0.55) / 0.17);
	if (t < 0.88) return mix(c4, c5, (t - 0.72) / 0.16);
	return mix(c5, c6, (t - 0.88) / 0.12);
}
void vertex() { POSITION = vec4(VERTEX.xy, 1.0, 1.0); }
void fragment() {
	vec2 uv = (floor(SCREEN_UV * res) + 0.5) / res;
	vec3 c = texture(pantalla, uv).rgb; float dp = texture(prof, uv).x; float heat;
	if (c.r > 0.97 && c.g < 0.03) heat = 0.55 + 0.45 * c.b;
	else if (c.r < 0.03 && c.g > 0.97) heat = 0.15 * c.b;
	else if (dp <= 0.000001) heat = 0.05;
	else heat = 0.16 + 0.3 * clamp(dot(c, vec3(0.299, 0.587, 0.114)), 0.0, 1.0);
	vec3 s = ironbow(clamp(heat, 0.0, 1.0));
	ALBEDO = mix(pow((s + 0.055) / 1.055, vec3(2.4)), s / 12.92, lessThan(s, vec3(0.04045)));
}"""

