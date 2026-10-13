extends SceneTree
## Suelo con VARIAS zonas de detalle igual que en el navegador (Entorno.poner_zonas frente a ponerZonas de entorno.js):
## referencia en pruebas/referencia_zonas_js.json (generar_referencia_zonas.py).
## Uso: herramientas/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path simulador_godot --script res://pruebas/prueba_zonas.gd

func _e(x: float) -> String:
	if x == 0: return "0"
	var ex := floori(log(x) / log(10.0))
	return "%.1fe%d" % [x / pow(10, ex), ex]

func _init() -> void:
	var ref: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://pruebas/referencia_zonas_js.json"))
	var ent := Entorno.new(); ent.poner_mundo(DatosComunes.mundo("cartagena"))
	var zs := []
	for id in ref["zonas"]:
		for meta in DatosComunes.indice_zonas():
			if meta["id"] == id: zs.append(DatosComunes.cargar_zona(meta))
	if zs.size() != 2: print("faltan zonas %s en simulador/zonas" % [ref["zonas"]]); quit(1); return
	ent.poner_zonas(zs)
	var dh := 0.0; var dm := 0; var salto := 0.0; var prev = null
	for q in ref["puntos"]:
		var h := ent.altura(q[0], q[1])
		dh = maxf(dh, absf(h - q[2]))
		if (1 if ent.en_mar(q[0], q[1]) else 0) != int(q[3]): dm += 1
	# continuidad en la costura: la linea fina (los ultimos 201 puntos, cada 2 m) no debe tener escalones
	var linea: Array = ref["puntos"].slice(ref["puntos"].size() - 201)
	for k in range(1, linea.size()): salto = maxf(salto, absf(ent.altura(linea[k][0], linea[k][1]) - ent.altura(linea[k - 1][0], linea[k - 1][1])))
	var ok := dh < 1e-6 and dm == 0
	print("  %d puntos con %s: altura %s m, agua distinta en %d puntos; mayor salto cada 2 m al cruzar la costura %.2f m  %s" % [
		ref["puntos"].size(), ref["zonas"], _e(dh), dm, salto, "OK" if ok else "MAL"])
	print("RESULTADO: " + ("todo igual" if ok else "distinto"))
	quit(0 if ok else 1)
