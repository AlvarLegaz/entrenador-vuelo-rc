class_name Sonido
extends Node
## Sonido procedural del vuelo: el mismo que el objeto Sonido de simulador_web/simulador.html (Web Audio), con los mismos
## parametros. Motor = diente de sierra a rpm/60 Hz (ganancia 0,7) + cuadrada al doble (0,22, paso de pala de 2 palas) por un
## paso bajo de 500 + 2600*gas Hz, con ganancia (0,06 + 0,3*gas^1,3)*lejos si rpm > 0; viento = ruido blanco en bucle por un
## paso banda de 250 + 30*V Hz (Q 0,5) con ganancia min(0,45; 0,0011*V^2) (por 0,35*lejos en la camara del piloto); aviso de
## perdida = seno de 880 Hz con ganancia 0,1 encendido y apagado a 2 Hz; eventos "toque" (ruido por paso bajo de 900 Hz,
## 0,3 -> 0,001 en 0,18 s) y "roto" (paso bajo de 350 Hz, 0,9 -> 0,001 en 0,7 s); volumen general con on/off y silenciar.
## Los cambios se suavizan como setTargetAtTime (constante 0,08 s; 0,015 s el pitido y 0,05 s el volumen general).
##
## Para gastar poco en GDScript no se calcula nada muestra a muestra durante el vuelo: las formas de onda se generan una vez
## (tabla de onda del motor con armonicos limitados en banda, ruido de 2 s, patron del pitido, rafagas de los eventos ya
## filtradas) en AudioStreamWAV en bucle; la frecuencia del motor es pitch_scale y los filtros que cambian con el vuelo son
## AudioEffectLowPassFilter/BandPassFilter en dos buses propios ("SonidoMotor" y "SonidoViento") a los que se les cambia el
## corte en cada cuadro. Si no hay dispositivo de audio Godot usa el driver Dummy y todo funciona igual (sin oirse).
##
## Uso: anadir como hijo (se suaviza en _process), llamar cargar_cfg() e iniciar(), y en cada cuadro
## actualizar(av, lejos, camara_piloto) con lejos = Sonido.lejos_de(distancia del piloto al avion en m).

const FS := 44100                    # frecuencia de muestreo de las formas de onda generadas
const K := 0.08                      # constante de tiempo de actualizar() (setTargetAtTime de la web)
const K_PITIDO := 0.015
const K_GENERAL := 0.05
const F0_MOTOR := 100.0              # la tabla del motor es un ciclo de 441 muestras a 100 Hz; pitch_scale = f / 100
const ARM_MAX_HZ := 5500.0           # armonicos de la tabla hasta 5,5 kHz: sin aliasing hasta pitch_scale 4 (240 Hz = 14.400 rpm)
const BUS_MOTOR := "SonidoMotor"
const BUS_VIENTO := "SonidoViento"
const Q_LP_WEB := 1.1220184543       # Q por defecto (1 dB) de un BiquadFilter "lowpass" de Web Audio, en lineal: 10^(1/20)
const Q_MOTOR_WEB := 1.1091748152    # Q 0,9 dB del paso bajo del motor: 10^(0,9/20)
const GANANCIA_BP_GODOT := 1.2247448714  # el paso banda de Godot tiene ganancia sqrt(Q+1) en el pico (Q = 0,5); Web Audio, 1
const ESCALA_MOTOR := 0.5            # la tabla del motor se guarda a la mitad (el Gibbs de la sierra pasaria de 1) y se compensa

var on := true                       ## sonido activado (se guarda)
var vol := 0.6                       ## volumen general 0..1 (se guarda)
var ruta_cfg := "user://sonido.cfg"
var iniciado := false
var _silencio := false

# objetivos (los fija actualizar) y valores actuales que se les acercan en _process, como setTargetAtTime
var _f_obj := 25.0; var _f := 25.0
var _corte_obj := 500.0; var _corte := 500.0
var _gm_obj := 0.0; var _gm := 0.0
var _fv_obj := 250.0; var _fv := 250.0
var _gv_obj := 0.0; var _gv := 0.0
var _gp_obj := 0.0; var _gp := 0.0
var _gen := 0.0
var _parado := false
var _pendiente := false

var _p_motor: AudioStreamPlayer
var _p_viento: AudioStreamPlayer
var _p_pitido: AudioStreamPlayer
var _p_toque: AudioStreamPlayer
var _p_roto: AudioStreamPlayer
var _p_pisada: AudioStreamPlayer; var _p_disparo: AudioStreamPlayer; var _p_explosion: AudioStreamPlayer
var _lp_motor: AudioEffectLowPassFilter
var _bp_viento: AudioEffectBandPassFilter

var _ondas := {}                     # formas de onda generadas (en el primer iniciar, ~18 ms)

## Factor de distancia de la camara del piloto (el motor llega de lejos): 1 / (1 + d/45), d en metros.
static func lejos_de(d: float) -> float:
	return 1.0 / (1.0 + d / 45.0)

func cargar_cfg() -> void:
	var c := ConfigFile.new()
	if c.load(ruta_cfg) != OK: return
	on = bool(c.get_value("sonido", "on", on)); vol = clampf(float(c.get_value("sonido", "vol", vol)), 0.0, 1.0)

func guardar_cfg() -> void:
	var c := ConfigFile.new()
	c.set_value("sonido", "on", on); c.set_value("sonido", "vol", vol)
	c.save(ruta_cfg)

## Crea los buses, los filtros y los reproductores (no hace nada si on es false). Se puede llamar varias veces.
func iniciar() -> void:
	if not on or iniciado: return
	if not is_inside_tree():          # los reproductores necesitan estar en el arbol: se inicia al entrar
		_pendiente = true; return
	if _ondas.is_empty(): _generar_ondas()
	var bm := _bus(BUS_MOTOR); var bv := _bus(BUS_VIENTO)
	_lp_motor = AudioServer.get_bus_effect(bm, 0); _bp_viento = AudioServer.get_bus_effect(bv, 0)
	_p_motor = _reproductor(_ondas["motor"], BUS_MOTOR)
	_p_viento = _reproductor(_ondas["ruido"], BUS_VIENTO)
	_p_pitido = _reproductor(_ondas["pitido"], "Master")
	_p_toque = _reproductor(_ondas["toque"], "Master", false)
	_p_roto = _reproductor(_ondas["roto"], "Master", false)
	_p_pisada = _reproductor(_ondas["pisada"], "Master", false); _p_disparo = _reproductor(_ondas["disparo"], "Master", false); _p_explosion = _reproductor(_ondas["explosion"], "Master", false)
	iniciado = true; _parado = false
	_aplicar()

func silenciar(s: bool) -> void:
	_silencio = s

## av: rpm, gases, estado, V, perdida, p (NED, m). lejos: factor de distancia (solo cuenta con camara_piloto).
func actualizar(av: Dictionary, lejos: float, camara_piloto: bool) -> void:
	if not iniciado: return
	var l := lejos if camara_piloto else 1.0
	var rpm := float(av.get("rpm", 0.0)); var gas := float(av.get("gases", 0.0))
	var volando: bool = av.get("estado", "") == "volando"
	_f_obj = maxf(25.0, rpm / 60.0)
	_corte_obj = 500.0 + 2600.0 * gas
	_gm_obj = (0.06 + 0.3 * pow(gas, 1.3)) * l if rpm > 0 else 0.0
	var V := float(av.get("V", 0.0)) if volando else 0.0
	_fv_obj = 250.0 + 30.0 * V
	_gv_obj = minf(0.45, 0.0011 * V * V) * (0.35 * l if camara_piloto else 1.0)
	var p = av.get("p", [0.0, 0.0, 0.0])
	_gp_obj = 1.0 if volando and float(av.get("perdida", 0.0)) > 0.5 and -float(p[2]) > 2.0 else 0.0

## "toque" (aterrizaje) o "roto" (accidente): rafaga de ruido filtrada que decae (vuelve a empezar si ya sonaba).
func evento(tipo: String) -> void:
	if not iniciado or _parado: return     # en silencio no suena (y no debe sonar tarde al quitar la pausa)
	var r := { "roto": _p_roto, "pisada": _p_pisada, "disparo": _p_disparo, "explosion": _p_explosion }.get(tipo, _p_toque) as AudioStreamPlayer
	r.stop(); r.play()

func _process(dt: float) -> void:
	if not iniciado: return
	var a := 1.0 - exp(-dt / K)
	_f += (_f_obj - _f) * a; _corte += (_corte_obj - _corte) * a; _gm += (_gm_obj - _gm) * a
	_fv += (_fv_obj - _fv) * a; _gv += (_gv_obj - _gv) * a
	_gp += (_gp_obj - _gp) * (1.0 - exp(-dt / K_PITIDO))
	var obj := vol if on and not _silencio else 0.0
	_gen += (obj - _gen) * (1.0 - exp(-dt / K_GENERAL))
	if obj == 0.0 and _gen < 1e-4:
		if not _parado: _pausar(true)
		return
	if _parado: _pausar(false)
	_aplicar()

func _aplicar() -> void:
	_p_motor.pitch_scale = _f / F0_MOTOR
	_lp_motor.cutoff_hz = _corte
	_p_motor.volume_db = _db(_gm * _gen / ESCALA_MOTOR)
	_bp_viento.cutoff_hz = _fv
	_p_viento.volume_db = _db(_gv * _gen / GANANCIA_BP_GODOT)
	_p_pitido.volume_db = _db(_gp * _gen)
	var dg := _db(_gen)
	_p_toque.volume_db = dg; _p_roto.volume_db = dg
	for x in [_p_pisada, _p_disparo, _p_explosion]: x.volume_db = dg

func _pausar(s: bool) -> void:
	_parado = s
	for r in [_p_motor, _p_viento, _p_pitido, _p_toque, _p_roto, _p_pisada, _p_disparo, _p_explosion]: r.stream_paused = s

static func _db(g: float) -> float:
	return linear_to_db(g) if g > 1e-6 else -120.0

func _ready() -> void:
	if _pendiente: _pendiente = false; iniciar()

func _exit_tree() -> void:
	if not iniciado: return
	for n in [BUS_VIENTO, BUS_MOTOR]:
		var i := AudioServer.get_bus_index(n)
		if i >= 0: AudioServer.remove_bus(i)
	for r in [_p_motor, _p_viento, _p_pitido, _p_toque, _p_roto, _p_pisada, _p_disparo, _p_explosion]:
		r.stop(); r.queue_free()
	iniciado = false

func _bus(nombre: String) -> int:
	var i := AudioServer.get_bus_index(nombre)
	if i < 0:
		i = AudioServer.bus_count; AudioServer.add_bus(i); AudioServer.set_bus_name(i, nombre)
		AudioServer.set_bus_send(i, "Master")
		var fx: AudioEffectFilter
		if nombre == BUS_MOTOR:
			fx = AudioEffectLowPassFilter.new(); fx.resonance = Q_MOTOR_WEB
		else:
			fx = AudioEffectBandPassFilter.new(); fx.resonance = 0.25   # Godot dobla la Q del paso banda: Q = 0,5
		fx.db = AudioEffectFilter.FILTER_6DB   # una sola biquad, como el BiquadFilter de la web
		AudioServer.add_bus_effect(i, fx, 0)
	return i

func _reproductor(s: AudioStreamWAV, bus: String, sonando := true) -> AudioStreamPlayer:
	var r := AudioStreamPlayer.new(); r.stream = s; r.bus = bus; r.volume_db = -120.0
	add_child(r)
	if sonando: r.play()
	return r

# ----------------------------------------------------------------------------------------------- formas de onda (una vez)

func _generar_ondas() -> void:
	var rng := RandomNumberGenerator.new(); rng.seed = 12345
	# motor: un ciclo a 100 Hz de 0,7*sierra(f) + 0,22*cuadrada(2f), con las series de Fourier de los osciladores de Web Audio
	var n := int(FS / F0_MOTOR); var m := PackedFloat32Array(); m.resize(n)
	for k in range(1, int(ARM_MAX_HZ / F0_MOTOR) + 1):
		var a := 0.7 * 2.0 / (PI * k) * (1.0 if k % 2 == 1 else -1.0)             # sierra: (2/(k pi)) (-1)^(k+1)
		if k % 4 == 2: a += 0.22 * 4.0 / (PI * k / 2.0)                           # cuadrada al doble: 4/(j pi), j impar
		var w := TAU * k / n
		a *= ESCALA_MOTOR
		for i in n: m[i] += a * sin(w * i)
	_ondas["motor"] = _wav(m, true)
	# ruido blanco de 2 s (el buffer de la web); el viento lo pasa por el paso banda del bus
	var r := PackedFloat32Array(); r.resize(2 * FS)
	for i in r.size(): r[i] = rng.randf() * 2.0 - 1.0
	_ondas["ruido"] = _wav(r, true)
	# pitido: patron de 0,5 s (0,25 s encendido, 0,25 s apagado) con la subida/bajada de setTargetAtTime(0,1 / 0, 0,015)
	var np := 22050; var pi_ := PackedFloat32Array(); pi_.resize(np); var e := 0.0
	var ce := exp(-1.0 / (K_PITIDO * FS))
	for vuelta in 2:                   # dos vueltas para que el final enlace con el principio
		for i in np:
			e = (0.1 if i < 11025 else 0.0) + (e - (0.1 if i < 11025 else 0.0)) * ce
			pi_[i] = e * sin(TAU * 880.0 * i / FS)          # 440 ciclos exactos en 0,5 s
	_ondas["pitido"] = _wav(pi_, true)
	_ondas["toque"] = _wav(_rafaga(r, 900.0, 0.3, 0.18), false)
	_ondas["roto"] = _wav(_rafaga(r, 350.0, 0.9, 0.7), false)
	# bipode: pisada (ruido grave + un seno que cae de 70 a 32 Hz), disparo (rafaga corta) y explosion
	var pis := _rafaga(r, 140.0, 0.9, 0.35); var fase := 0.0
	for i in int(0.32 * FS):
		var tt := float(i) / FS; var f := 70.0 * pow(32.0 / 70.0, minf(1.0, tt / 0.25)); fase += TAU * f / FS
		pis[i] += 0.7 * pow(0.001 / 0.7, tt / 0.3) * sin(fase)
	_ondas["pisada"] = _wav(pis, false)
	_ondas["disparo"] = _wav(_rafaga(r, 1400.0, 0.22, 0.07), false)
	_ondas["explosion"] = _wav(_rafaga(r, 260.0, 0.8, 1.2), false)

## Rafaga de 0,8 s: ruido por un paso bajo (biquad de Web Audio, Q 1 dB) con exponentialRampToValueAtTime(0,001, T).
static func _rafaga(ruido: PackedFloat32Array, fc: float, g0: float, T: float) -> PackedFloat32Array:
	var n := int(0.8 * FS); var o := PackedFloat32Array(); o.resize(n)
	var w := TAU * fc / FS; var al := sin(w) / (2.0 * Q_LP_WEB); var c := cos(w); var a0 := 1.0 + al
	var b0 := (1.0 - c) / 2.0 / a0; var b1 := (1.0 - c) / a0; var a1 := -2.0 * c / a0; var a2 := (1.0 - al) / a0
	var x1 := 0.0; var x2 := 0.0; var y1 := 0.0; var y2 := 0.0
	var tn := int(T * FS); var r := pow(0.001 / g0, 1.0 / tn); var g := g0
	for i in n:
		var x := ruido[i]
		var y := b0 * x + b1 * x1 + b0 * x2 - a1 * y1 - a2 * y2
		x2 = x1; x1 = x; y2 = y1; y1 = y
		o[i] = y * g
		if i < tn: g *= r
	return o

## AudioStreamWAV de 16 bits. En bucle se anaden 16 muestras de la propia onda antes y despues del tramo del bucle para que
## la interpolacion del remuestreo no lea ceros en el punto de vuelta (pitch_scale distinto de 1).
static func _wav(x: PackedFloat32Array, bucle: bool) -> AudioStreamWAV:
	var pad := 16 if bucle else 0; var n := x.size(); var total := n + 2 * pad
	var b := PackedByteArray(); b.resize(2 * total)
	for i in total:
		b.encode_s16(2 * i, int(clampf(x[posmod(i - pad, n)], -1.0, 1.0) * 32767.0))
	var s := AudioStreamWAV.new(); s.format = AudioStreamWAV.FORMAT_16_BITS; s.mix_rate = FS; s.stereo = false; s.data = b
	if bucle:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD; s.loop_begin = pad; s.loop_end = pad + n
	return s
