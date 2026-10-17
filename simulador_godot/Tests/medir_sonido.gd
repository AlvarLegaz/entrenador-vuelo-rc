extends SceneTree
## Coste total del sonido (hilo principal + mezcla en el hilo de audio): 20 s (--duracion=S) a 60 cuadros/s con el motor, el viento y el
## pitido sonando a la vez (--modo=con) o sin crear Sonido (--modo=sin). El tiempo de CPU del proceso se lee desde fuera:
##   $p = Start-Process herramientas/godot/Godot_v4.7.2-stable_win64.exe -ArgumentList '--headless','--path',
##        'simulador_godot','--script','res://Tests/medir_sonido.gd','--','--modo=con' -PassThru -NoNewWindow
##   $p.WaitForExit(); $p.TotalProcessorTime.TotalMilliseconds
## (el ejecutable sin _console: el _console lanza el otro como hijo y su tiempo de CPU no cuenta la mezcla)
## y la diferencia entre los dos modos, dividida por los cuadros, es lo que cuesta el sonido por cuadro.

var duracion := 20.0
var snd: Sonido
var t := 0.0
var cuadros := 0

func _initialize() -> void:
	Engine.max_fps = 60
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--duracion="): duracion = float(a.split("=")[1])
	if "--modo=con" in OS.get_cmdline_user_args():
		snd = Sonido.new(); snd.vol = 0.8; root.add_child(snd)

func _process(dt: float) -> bool:
	t += dt; cuadros += 1
	if snd:
		if not snd.iniciado: snd.iniciar()
		var av := { "rpm": 12000.0 + 2000.0 * sin(t), "gases": 0.7 + 0.3 * sin(0.7 * t), "estado": "volando",
					"V": 14.0 + 4.0 * sin(0.3 * t), "perdida": 1.0, "p": [0.0, 0.0, -30.0] }
		snd.actualizar(av, Sonido.lejos_de(60.0), false)
	if t >= duracion:
		print("cuadros=%d" % cuadros)
		return true
	return false
