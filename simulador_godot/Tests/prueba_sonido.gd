extends SceneTree
## Prueba del sonido procedural (scripts/sonido.gd): conduce una secuencia guionizada (ralenti, gas a fondo a 15.000 rpm, medio
## gas, camara del piloto lejos, planeo a 8/15/25 m/s, pitido de perdida, toque, rotura, silenciar y apagar), graba la salida
## del bus Master con un AudioEffectCapture (con --headless Godot usa el driver Dummy, que mezcla igual pero no suena) y la guarda
## en WAV (float 32, estereo) junto a un JSON con los tramos. El reloj de la secuencia son las muestras grabadas, asi los tramos
## del JSON caen donde estan en el WAV. Despues mide el coste por cuadro de Sonido en el hilo principal.
## Uso (desde la carpeta del repositorio):
##   herramientas/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path simulador_godot --script res://Tests/prueba_sonido.gd -- --salida=CARPETA
## y luego  python simulador_godot/Tests/analizar_sonido.py CARPETA

const VOL := 0.8
# tramos: [inicio, fin, nombre, av, lejos, camara_piloto, accion al empezar]
var tramos := [
	[0.0, 0.5, "arranque", { "rpm": 0.0, "gases": 0.0, "estado": "suelo", "V": 0.0 }, 1.0, false, ""],
	[0.5, 2.5, "ralenti", { "rpm": 3000.0, "gases": 0.0, "estado": "suelo", "V": 0.0 }, 1.0, false, ""],
	[2.5, 5.0, "gas_fondo", { "rpm": 15000.0, "gases": 1.0, "estado": "volando", "V": 12.0 }, 1.0, false, ""],
	[5.0, 7.0, "medio_gas", { "rpm": 9000.0, "gases": 0.5, "estado": "volando", "V": 12.0 }, 1.0, false, ""],
	[7.0, 9.0, "piloto_lejos", { "rpm": 15000.0, "gases": 1.0, "estado": "volando", "V": 12.0 }, Sonido.lejos_de(135.0), true, ""],
	[9.0, 11.0, "planeo_8", { "rpm": 0.0, "gases": 0.0, "estado": "volando", "V": 8.0 }, 1.0, false, ""],
	[11.0, 13.0, "planeo_15", { "rpm": 0.0, "gases": 0.0, "estado": "volando", "V": 15.0 }, 1.0, false, ""],
	[13.0, 15.0, "planeo_25", { "rpm": 0.0, "gases": 0.0, "estado": "volando", "V": 25.0 }, 1.0, false, ""],
	[15.0, 18.0, "perdida", { "rpm": 0.0, "gases": 0.0, "estado": "volando", "V": 9.0, "perdida": 1.0, "p": [0.0, 0.0, -50.0] }, 1.0, false, ""],
	[18.0, 19.0, "perdida_suelo", { "rpm": 0.0, "gases": 0.0, "estado": "volando", "V": 9.0, "perdida": 1.0, "p": [0.0, 0.0, -1.0] }, 1.0, false, ""],
	[19.0, 19.6, "quieto", { "rpm": 0.0, "gases": 0.0, "estado": "suelo", "V": 0.0 }, 1.0, false, ""],
	[19.6, 21.0, "toque", { "rpm": 0.0, "gases": 0.0, "estado": "suelo", "V": 0.0 }, 1.0, false, "toque"],
	[21.0, 22.5, "roto", { "rpm": 0.0, "gases": 0.0, "estado": "roto", "V": 0.0 }, 1.0, false, "roto"],
	[22.5, 23.5, "motor_suelo", { "rpm": 15000.0, "gases": 1.0, "estado": "suelo", "V": 0.0 }, 1.0, false, ""],
	[23.5, 25.0, "silenciado", { "rpm": 15000.0, "gases": 1.0, "estado": "suelo", "V": 0.0 }, 1.0, false, "silenciar"],
	[25.0, 26.5, "sin_silenciar", { "rpm": 15000.0, "gases": 1.0, "estado": "suelo", "V": 0.0 }, 1.0, false, "no_silenciar"],
	[26.5, 28.0, "apagado", { "rpm": 15000.0, "gases": 1.0, "estado": "suelo", "V": 0.0 }, 1.0, false, "apagar"],
]

var snd: Sonido
var cap: AudioEffectCapture
var grabado := PackedVector2Array()
var tramo := -1
var eventos := []
var salida := ""
var fs := 44100.0
var us_actualizar := 0
var n_actualizar := 0
var t_reloj := 0
var us_max := 0
var fin := 0
var traza := []                   # por cuadro: reloj (s), volumen general, ganancia y frecuencia del motor

func _initialize() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1); args[kv[0]] = kv[1] if kv.size() > 1 else ""
	salida = args.get("salida", OS.get_user_data_dir() + "/prueba_sonido")
	DirAccess.make_dir_recursive_absolute(salida)
	Engine.max_fps = 60
	fs = AudioServer.get_mix_rate()
	print("driver de audio: %s, mezcla %d Hz, pantalla: %s" % [AudioServer.get_driver_name(), fs, DisplayServer.get_name()])
	# configuracion: ida y vuelta por un fichero de prueba (no se toca user://sonido.cfg)
	var c := Sonido.new(); c.ruta_cfg = salida + "/sonido_prueba.cfg"; c.on = false; c.vol = 0.37; c.guardar_cfg()
	var d := Sonido.new(); d.ruta_cfg = c.ruta_cfg; d.cargar_cfg()
	print("cfg ida y vuelta: on=%s vol=%.2f -> %s" % [d.on, d.vol, "OK" if d.on == false and absf(d.vol - 0.37) < 1e-6 else "FALLO"])
	c.free(); d.free()
	cap = AudioEffectCapture.new(); cap.buffer_length = 2.0
	AudioServer.add_bus_effect(0, cap)
	snd = Sonido.new(); snd.vol = VOL; snd.on = true
	root.add_child(snd)
	snd.ready.connect(snd.set_process.bind(false))   # su _process se llama desde aqui para medir lo que cuesta cada cuadro
	var t0 := Time.get_ticks_usec(); snd._generar_ondas()
	print("formas de onda generadas en %.1f ms (una vez, en el primer iniciar)" % ((Time.get_ticks_usec() - t0) / 1000.0))
	t_reloj = Time.get_ticks_msec()

func _process(dt: float) -> bool:
	if fin > 0:                         # unos cuadros para que el servidor de audio suelte lo que reproducia
		fin -= 1; return fin == 0
	if not snd.iniciado:                # ya esta en el arbol (iniciar necesita que lo este)
		var t0 := Time.get_ticks_usec(); snd.iniciar()
		print("iniciar (buses, filtros y reproductores): %.1f ms" % ((Time.get_ticks_usec() - t0) / 1000.0))
	var n := cap.get_frames_available()
	if n > 0: grabado.append_array(cap.get_buffer(n))
	var t := grabado.size() / fs
	var i := 0
	while i < tramos.size() - 1 and t >= tramos[i + 1][0]: i += 1
	if t >= tramos[-1][1]:
		_terminar(); fin = 10; return false
	if i != tramo:
		tramo = i; var acc: String = tramos[i][6]
		match acc:
			"toque", "roto": snd.evento(acc)
			"silenciar": snd.silenciar(true)
			"no_silenciar": snd.silenciar(false)
			"apagar": snd.on = false
		eventos.append({ "tramo": tramos[i][2], "t": t, "accion": acc, "cuadro": n_actualizar })
	var av: Dictionary = tramos[i][3].duplicate()
	if not av.has("p"): av["p"] = [0.0, 0.0, -20.0]
	if not av.has("perdida"): av["perdida"] = 0.0
	var t1 := Time.get_ticks_usec()
	snd.actualizar(av, tramos[i][4], tramos[i][5])
	snd._process(dt)
	var us := Time.get_ticks_usec() - t1
	us_actualizar += us; n_actualizar += 1; us_max = maxi(us_max, us)
	traza.append([Time.get_ticks_usec() / 1e6, snd._gen, snd._gm, snd._f])
	return false

func _terminar() -> void:
	var wav := salida + "/sonido_prueba.wav"
	_guardar_wav(wav, grabado, int(fs))
	var meta := { "fs": fs, "vol": VOL, "tramos": [], "eventos": eventos }
	for tr in tramos:
		meta["tramos"].append({ "ini": tr[0], "fin": tr[1], "nombre": tr[2], "av": tr[3], "lejos": tr[4], "camara_piloto": tr[5] })
	# coste en el hilo principal: actualizar() + _process() de Sonido en cada cuadro de la secuencia (no en un bucle cerrado:
	# miles de cambios de volumen seguidos atascan la cola del servidor de audio y la salida tarda medio minuto)
	var reloj := (Time.get_ticks_msec() - t_reloj) / 1000.0
	meta["us_por_cuadro"] = float(us_actualizar) / maxi(1, n_actualizar)
	meta["traza"] = traza; meta["us_max"] = us_max; meta["cuadros"] = n_actualizar; meta["fps"] = n_actualizar / reloj
	var f := FileAccess.open(salida + "/sonido_prueba.json", FileAccess.WRITE); f.store_string(JSON.stringify(meta, "  ")); f.close()
	print("grabado %.2f s de audio en %.2f s de reloj (%d cuadros, %.1f fps) en %s" % [grabado.size() / fs, reloj, n_actualizar, meta["fps"], wav])
	print("coste en el hilo principal: %.1f us por cuadro de media (actualizar + _process), maximo %d us" % [meta["us_por_cuadro"], us_max])
	snd.free()

static func _guardar_wav(ruta: String, x: PackedVector2Array, sr: int) -> void:
	var datos := x.to_byte_array()        # float32 intercalado L, R
	var f := FileAccess.open(ruta, FileAccess.WRITE)
	f.store_buffer("RIFF".to_ascii_buffer()); f.store_32(36 + datos.size()); f.store_buffer("WAVE".to_ascii_buffer())
	f.store_buffer("fmt ".to_ascii_buffer()); f.store_32(16); f.store_16(3); f.store_16(2); f.store_32(sr)
	f.store_32(sr * 8); f.store_16(8); f.store_16(32)
	f.store_buffer("data".to_ascii_buffer()); f.store_32(datos.size()); f.store_buffer(datos)
	f.close()
