class_name PantallaTaller
extends Control
## Modo Taller (#pTaller de simulador/simulador.html, js/taller.js, igual): se elige un vehiculo, se "conecta" y se
## descargan sus registros de vuelo (registro_vuelo.gd: los de este ordenador y, con el alumno en el aula, los suyos del
## servidor), como los de un dron comercial. De cada vuelo: un resumen (duracion, alturas, velocidad, bateria usada,
## tension minima y desequilibrio de las celdas, corriente y temperatura maximas, avisos), las graficas con el tiempo
## (bateria y tension, cada celda, corriente y potencia, temperatura, altura y velocidad) con un cursor que da los
## valores y las marcas de los avisos, la traza del vuelo coloreada por la bateria y la exportacion a CSV.

const COLORES_CELDA := ["#4fc3f7", "#ffb74d", "#81c784", "#e57373", "#ba68c8", "#fff176"]

var p: Node
var avion := ""
var lista = null                 # los registros descargados (sin las muestras), o null si aun no se ha conectado
var reg := {}                    # el registro que se mira
var lista_veh: VBoxContainer
var centro: VBoxContainer
var grafica: Grafica
var traza: TrazaBateria
var lectura: RichTextLabel

func _init(p_: Node) -> void:
	p = p_
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var d := Tema.pantalla("Taller", "Conecta el vehículo y descarga sus registros de vuelo: batería, celdas, corriente, temperatura, altura y velocidad")
	add_child(d["raiz"])
	d["botones"].add_child(Tema.boton("← Inicio", "", func(): p.ir_inicio()))
	var h := HBoxContainer.new(); h.add_theme_constant_override("separation", 16); d["cuerpo"].add_child(h)
	lista_veh = VBoxContainer.new(); lista_veh.add_theme_constant_override("separation", 8)
	var sl := Tema.desplazable(lista_veh); sl.size_flags_horizontal = Control.SIZE_FILL; sl.custom_minimum_size.x = 260; h.add_child(sl)
	centro = VBoxContainer.new(); centro.add_theme_constant_override("separation", 10)
	h.add_child(Tema.desplazable(centro))

## Los vehiculos del hangar que llevan registro de vuelo (el bipode no).
func ids() -> Array:
	return p.ids_hangar().filter(func(id): return DatosComunes.avion(id).get("tipo", "") != "bipode")

func abrir() -> void:
	if avion == "" or not ids().has(avion): avion = p.sesion["avion"] if ids().has(p.sesion["avion"]) else "DJI_MINI"
	lista = null; reg = {}
	pintar_vehiculos(); pintar_centro(); p.mostrar("pTaller")

func elegir(id: String) -> void:
	avion = id; lista = null; reg = {}; pintar_vehiculos(); pintar_centro()

## Los vehiculos, con cuantos registros hay de cada uno en este ordenador.
func pintar_vehiculos() -> void:
	for c in lista_veh.get_children(): c.queue_free()
	var cuenta := {}
	for r in RegistroVuelo.listar(): cuenta[r["avion"]] = int(cuenta.get(r["avion"], 0)) + 1
	for id in ids():
		var b := Button.new(); b.theme_type_variation = "TarjetaSel" if id == avion else "Tarjeta"; b.focus_mode = Control.FOCUS_NONE
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND; b.custom_minimum_size = Vector2(250, 58); b.pressed.connect(elegir.bind(id))
		var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 1); v.set_anchors_preset(Control.PRESET_FULL_RECT)
		v.offset_left = 14; v.offset_top = 9; v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var n: int = cuenta.get(id, 0)
		v.add_child(Tema.etiqueta(String(DatosComunes.avion(id).get("nombre", id)), 15, Tema.TEXTO, true))
		v.add_child(Tema.etiqueta(("%d registro%s en este ordenador" % [n, "s" if n > 1 else ""]) if n else "sin registros en este ordenador", 12, Tema.SUAVE))
		for c in v.get_children(): c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(v); lista_veh.add_child(b)

## La ficha de la bateria del vehiculo (de sus datos).
func bateria_texto(id: String) -> String:
	var B = p.crear_modelo(id).get("B")
	if not B is Dictionary or B.is_empty(): return "Motor de combustión: el registro da el combustible"
	return "Batería %s %dS de %d mAh (%s Wh)" % ["Li-ion" if B["quimica"] == "liion" else "LiPo", int(B["celdas"]), int(round(float(B["capacidad_mAh"]))),
		("%.1f" % (int(B["celdas"]) * 3.7 * float(B["capacidad_mAh"]) / 1000)).replace(".", ",")]

static func fecha(iso: String) -> String:
	var u := Time.get_unix_time_from_datetime_string(iso.substr(0, 19)) + int(Time.get_time_zone_from_system()["bias"]) * 60
	var d := Time.get_datetime_dict_from_unix_time(u)
	return "%d/%d/%02d, %02d:%02d" % [d["day"], d["month"], d["year"] % 100, d["hour"], d["minute"]]

static func coma(x: float, n: int) -> String: return (("%." + str(n) + "f") % x).replace(".", ",")

func pintar_centro() -> void:
	for c in centro.get_children(): c.queue_free()
	grafica = null; traza = null; lectura = null
	if not reg.is_empty(): pintar_detalle(); return
	var cp: Array = Tema.capa(10); centro.add_child(cp[0]); var v: VBoxContainer = cp[1]
	v.add_child(Tema.h2(String(DatosComunes.avion(avion).get("nombre", avion))))
	v.add_child(Tema.sub(bateria_texto(avion)))
	if lista == null:
		var b := Tema.boton("🔌 Conectar y descargar los registros", "BotonPrimGrande", func(): conectar()); b.name = "Conectar"
		b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN; v.add_child(b)
		var pr := VBoxContainer.new(); pr.name = "Progreso"; v.add_child(pr)
	elif (lista as Array).is_empty():
		v.add_child(Tema.etiqueta("No hay registros de vuelo de este vehículo. Vuela con él y vuelve: cada vuelo guarda su registro al terminar.", 15, Tema.TEXTO, false, true))
	else:
		var n: int = lista.size()
		v.add_child(Tema.sub("%d registro%s. Elige uno para ver sus gráficas." % [n, "s" if n > 1 else ""]))
		var g := GridContainer.new(); g.columns = 6; g.add_theme_constant_override("h_separation", 0); g.add_theme_constant_override("v_separation", 0); v.add_child(g)
		for t in ["Fecha", "Vuelo", "Duración", "Final", "Muestras", "Dónde"]: g.add_child(_celda(Tema.etiqueta(t, 14, Tema.SUAVE, true)))
		for r in lista:
			var txt := [fecha(String(r["inicio"])), String(r.get("escenario_nombre", r["escenario"])), coma(float(r.get("duracion_s", 0)) / 60, 1) + " min",
						String(r.get("final", "")), str(int(r.get("muestras", 0))), "☁ aula" if r.get("_aula", false) else "este ordenador"]
			for t in txt:
				var b := Button.new(); b.text = t; b.theme_type_variation = "BotonPlano"; b.alignment = HORIZONTAL_ALIGNMENT_LEFT; b.focus_mode = Control.FOCUS_NONE
				b.size_flags_horizontal = Control.SIZE_EXPAND_FILL; b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND; b.pressed.connect(ver.bind(r)); g.add_child(b)

func _celda(c: Control) -> Control:
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return Tema.margen(c, 8, 6, 8, 6)

## "Conecta" con el vehiculo y descarga sus registros: los de este ordenador y, con el alumno en el aula, los suyos.
func conectar() -> void:
	var v: Node = centro.find_child("Progreso", true, false); var b: Node = centro.find_child("Conectar", true, false)
	if b: b.disabled = true
	var nombre := String(DatosComunes.avion(avion).get("nombre", avion))
	for i in 3:
		if not is_instance_valid(v): return
		for c in v.get_children(): c.queue_free()
		var barra := ProgressBar.new(); barra.max_value = 99; barra.value = (i + 1) * 33; barra.show_percentage = false; barra.custom_minimum_size.y = 8; v.add_child(barra)
		v.add_child(Tema.sub(["Conectando con el %s…" % nombre, "Leyendo la memoria de vuelo…", "Descargando los registros…"][i]))
		await get_tree().create_timer(0.45).timeout
	var L := RegistroVuelo.listar(avion)
	if p.aula.activo and p.sesion["alumno"] != null:
		var r: Dictionary = await p.aula.api("GET", "registros?alumno=" + String(p.sesion["alumno"]["id"]).uri_encode())
		if r["ok"] and r["datos"] is Array:
			for x in r["datos"]:
				if x["avion"] == avion and not L.any(func(y): return y["id"] == x["id"]): x["_aula"] = true; L.append(x)
	L.sort_custom(func(a, c): return String(a["inicio"]) > String(c["inicio"]))
	lista = L; pintar_centro()

func ver(meta: Dictionary) -> void:
	var r := {}
	if meta.get("_aula", false):
		var q: Dictionary = await p.aula.api("GET", "registros/" + String(meta["id"]).uri_encode() + "?alumno=" + String(p.sesion["alumno"]["id"]).uri_encode())
		if not q["ok"]: p.poner_toast_menu("No se pudo leer el registro: " + String(q["error"])); return
		r = q["datos"]
	else: r = RegistroVuelo.leer(String(meta["avion"]), String(meta["id"]))
	if r.is_empty(): return
	reg = r; pintar_centro()

## Columna de un registro como lista (numeros o null).
static func col(R: Dictionary, nombre: String):
	var i: int = (R["columnas"] as Array).find(nombre)
	if i < 0: return null
	return (R["filas"] as Array).map(func(f): return f[i])

static func _nums(R: Dictionary, nombre: String) -> Array:
	var c = col(R, nombre)
	return [] if c == null else (c as Array).filter(func(x): return x is float or x is int).map(func(x): return float(x))

static func _celdas(R: Dictionary) -> Array:
	var re := RegEx.create_from_string("^celda\\d+_V$")
	return (R["columnas"] as Array).filter(func(c): return re.search(String(c)) != null)

## Resumen de un vuelo: [etiqueta, valor] con lo que interesa en el taller (Taller.resumen de la web).
static func resumen(R: Dictionary) -> Array:
	var f := func(x, n: int, u: String) -> String: return "—" if x == null else coma(float(x), n) + u
	var mx := func(a: Array): return null if a.is_empty() else a.max()
	var mn := func(a: Array): return null if a.is_empty() else a.min()
	var celdas := _celdas(R); var b := _nums(R, "bateria_pct")
	var deseq = null
	if celdas.size() > 1:
		var cs := celdas.map(func(c): return col(R, c)); deseq = 0.0
		for i in (R["filas"] as Array).size():
			var v := cs.map(func(x): return x[i]).filter(func(x): return x is float or x is int)
			if v.size() > 1: deseq = maxf(deseq, float(v.max()) - float(v.min()))
	var todas := []
	for c in celdas: todas += _nums(R, c)
	var min_celda = mn.call(todas) if not celdas.is_empty() else null
	var usada := "—"
	if not b.is_empty(): usada = f.call(b[0] - b[-1], 1, " %") + " (%s → %s)" % [f.call(b[0], 0, ""), f.call(b[-1], 0, " %")]
	return [["Duración", f.call(float(R.get("duracion_s", 0)) / 60, 1, " min")], ["Final", String(R.get("final", "—")) if R.get("final") else "—"],
		["Altura máxima", f.call(mx.call(_nums(R, "altura_despegue_m")), 0, " m")], ["Distancia máxima", f.call(mx.call(_nums(R, "distancia_m")), 0, " m")],
		["Velocidad máxima", f.call(mx.call(_nums(R, "velocidad_h_ms")), 1, " m/s")], ["Batería usada" if R.get("bateria") else "Combustible usado", usada],
		["Tensión mínima de celda", f.call(min_celda, 2, " V")], ["Desequilibrio de celdas", "—" if deseq == null else f.call(deseq * 1000, 0, " mV")],
		["Corriente máxima", f.call(mx.call(_nums(R, "corriente_A")), 1, " A")], ["Temperatura máxima", f.call(mx.call(_nums(R, "temperatura_bateria_C")), 1, " °C")],
		["Avisos", str((R.get("eventos", []) as Array).size())]]

## Los paneles de graficas: [titulo, [[columna, color, eje (0 izquierda, 1 derecha)], ...], unidades] (Taller.paneles).
static func paneles(R: Dictionary) -> Array:
	var celdas := _celdas(R); var sc := []
	for i in celdas.size(): sc.append([celdas[i], COLORES_CELDA[i % 6], 0])
	var P := [["Batería (%) y tensión (V)", [["bateria_pct", "#ffd54f", 0], ["tension_V", "#4fc3f7", 1]], ["%", "V"]],
		["Celdas (V)", sc, ["V", ""]],
		["Corriente (A) y potencia (W)", [["corriente_A", "#e57373", 0], ["potencia_W", "#ba68c8", 1]], ["A", "W"]],
		["Temperatura de la batería (°C)", [["temperatura_bateria_C", "#ff8a65", 0]], ["°C", ""]],
		["Altura sobre el despegue (m) y velocidad (m/s)", [["altura_despegue_m", "#81c784", 0], ["velocidad_h_ms", "#4fc3f7", 1]], ["m", "m/s"]]]
	return P.filter(func(x): return (x[1] as Array).any(func(s): return not _nums(R, s[0]).is_empty()))

static func fmt_t(s: float) -> String: return "%d:%02d" % [int(s / 60), int(fmod(s, 60))]

func pintar_detalle() -> void:
	var cp: Array = Tema.capa(10); centro.add_child(cp[0]); var v: VBoxContainer = cp[1]
	var cab := HBoxContainer.new(); cab.add_theme_constant_override("separation", 10); v.add_child(cab)
	var t := Tema.h2("%s · %s · %s" % [reg.get("avion_nombre", reg["avion"]), reg.get("escenario_nombre", reg["escenario"]), fecha(String(reg["inicio"]))])
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL; t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; cab.add_child(t)
	cab.add_child(Tema.boton("⬇ Exportar CSV", "", func(): exportar_dialogo()))
	cab.add_child(Tema.boton("← Registros", "", func(): reg = {}; pintar_centro()))
	var rj := Tema.rejilla(170, 8); v.add_child(rj)
	for kv in resumen(reg):
		var pc := PanelContainer.new(); pc.add_theme_stylebox_override("panel", Tema.caja(Color(1, 1, 1, 0.05), Color(0, 0, 0, 0), 8, 0, 10, 7))
		var c := VBoxContainer.new(); c.add_theme_constant_override("separation", 0); pc.add_child(c)
		c.add_child(Tema.etiqueta(kv[0], 12, Tema.SUAVE)); c.add_child(Tema.etiqueta(kv[1], 15, Tema.TEXTO, true)); rj.add_child(pc)
	var h := HBoxContainer.new(); h.add_theme_constant_override("separation", 12); v.add_child(h)
	grafica = Grafica.new(self); h.add_child(grafica)
	var der := VBoxContainer.new(); der.custom_minimum_size.x = 260; der.add_theme_constant_override("separation", 8); h.add_child(der)
	traza = TrazaBateria.new(reg); der.add_child(traza)
	var ev: Array = reg.get("eventos", [])
	if ev.is_empty(): der.add_child(Tema.sub("Sin avisos"))
	for e in ev: der.add_child(Tema.rico("[b]%s[/b] %s" % [fmt_t(float(e[0])), Tema.bb(String(e[1]))], 13))
	lectura = Tema.rico("[color=#9fb3c8]Pasa el ratón por las gráficas para ver los valores.[/color]", 14); v.add_child(lectura)

func nombre_csv(R: Dictionary) -> String:
	var u := Time.get_unix_time_from_datetime_string(String(R["inicio"]).substr(0, 19)) + int(Time.get_time_zone_from_system()["bias"]) * 60
	var d := Time.get_datetime_dict_from_unix_time(u)
	return "registro_%s_%04d-%02d-%02d_%02d-%02d.csv" % [R["avion"], d["year"], d["month"], d["day"], d["hour"], d["minute"]]

func exportar(ruta: String) -> bool:
	var fa := FileAccess.open(ruta, FileAccess.WRITE)
	if fa == null: p.poner_toast_menu("No se pudo guardar el CSV"); return false
	fa.store_string(RegistroVuelo.csv(reg)); fa.close(); return true

func exportar_dialogo() -> void:
	var dl: FileDialog = p.dialogo; var R := reg
	dl.title = "Exportar el registro de vuelo"; dl.current_dir = OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS); dl.current_file = nombre_csv(R)
	for c in dl.file_selected.get_connections(): dl.file_selected.disconnect(c["callable"])
	dl.file_selected.connect(func(ruta): exportar(ruta), CONNECT_ONE_SHOT)
	dl.popup_centered_ratio(0.6)


## Las graficas apiladas con el tiempo comun; con el cursor, la linea y los valores (Taller.dibujar de la web).
class Grafica extends Control:
	const HP := 118.0
	var T: PantallaTaller
	var P: Array
	var cursor = null
	func _init(t: PantallaTaller) -> void:
		T = t; P = PantallaTaller.paneles(T.reg); size_flags_horizontal = Control.SIZE_EXPAND_FILL
		custom_minimum_size = Vector2(400, P.size() * HP + 22); mouse_filter = Control.MOUSE_FILTER_STOP
	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseMotion: cursor = e.position.x; queue_redraw()
	func _notification(what: int) -> void:
		if what == NOTIFICATION_MOUSE_EXIT: cursor = null; queue_redraw()
	## El indice de la muestra mas cercana a la x del cursor (o -1).
	func indice(x: float) -> int:
		var t: Array = PantallaTaller.col(T.reg, "tiempo_s"); var x0 := 54.0; var x1 := size.x - 54
		if x < x0 or x > x1 or t.is_empty(): return -1
		var t0: float = t[0]; var t1: float = maxf(t0 + 1, t[-1]); var s := t0 + (x - x0) / (x1 - x0) * (t1 - t0); var k := 0
		for i in t.size(): if absf(t[i] - s) < absf(t[k] - s): k = i
		return k
	func _draw() -> void:
		var R: Dictionary = T.reg; var W := size.x; var H := size.y; var f: Font = Tema.fuente
		if R.is_empty(): return                       # ya se ha vuelto a la lista
		draw_style_box(Tema.caja(Color("#0b1119"), Color(0, 0, 0, 0), 8), Rect2(Vector2.ZERO, size))
		var t: Array = PantallaTaller.col(R, "tiempo_s"); var t0: float = t[0] if not t.is_empty() else 0.0; var t1: float = maxf(t0 + 1, t[-1] if not t.is_empty() else 1.0)
		var x0 := 54.0; var x1 := W - 54
		var X := func(s: float) -> float: return x0 + (s - t0) / (t1 - t0) * (x1 - x0)
		var i_cur := indice(cursor) if cursor != null else -1
		var lec := []; var suave := Color("#9fb3c8")
		for k in P.size():
			var titulo: String = P[k][0]; var S: Array = P[k][1]; var U: Array = P[k][2]
			var y0 := k * HP + 18; var y1 := y0 + HP - 26
			draw_rect(Rect2(x0, y0, x1 - x0, y1 - y0), Color(1, 1, 1, 0.12), false, 1)
			draw_string(f, Vector2(x0, y0 - 5), titulo, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, suave)
			for eje in [0, 1]:
				var ser := S.filter(func(s): return s[2] == eje)
				if ser.is_empty(): continue
				var vals := []
				for s in ser: vals += PantallaTaller._nums(R, s[0])
				if vals.is_empty(): continue
				var lo: float = vals.min(); var hi: float = vals.max(); var dec := 2 if hi - lo < 5 else 0; var v_hi := hi; var v_lo := lo   # las etiquetas, con los valores de verdad (sin el margen)
				if hi - lo < 1e-6: lo -= 1; hi += 1
				var m := (hi - lo) * 0.08; lo -= m; hi += m
				var Y := func(v: float) -> float: return y1 - (v - lo) / (hi - lo) * (y1 - y0)
				var c0 := Color(ser[0][1])
				var et_hi: String = PantallaTaller.coma(v_hi, dec) + (" " + String(U[eje]) if String(U[eje]) != "" else ""); var et_lo: String = PantallaTaller.coma(v_lo, dec)
				if eje == 0:
					draw_string(f, Vector2(x0 - 4 - f.get_string_size(et_hi, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x, Y.call(v_hi) + 4), et_hi, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, c0)
					draw_string(f, Vector2(x0 - 4 - f.get_string_size(et_lo, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x, Y.call(v_lo) + 4), et_lo, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, c0)
				else:
					draw_string(f, Vector2(x1 + 4, Y.call(v_hi) + 4), et_hi, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, c0)
					draw_string(f, Vector2(x1 + 4, Y.call(v_lo) + 4), et_lo, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, c0)
				for s in ser:
					var v: Array = PantallaTaller.col(R, s[0]); var pts := PackedVector2Array(); var color := Color(s[1])
					for i in v.size():
						if not (v[i] is float or v[i] is int):
							if pts.size() > 1: draw_polyline(pts, color, 1.5, true)
							pts = PackedVector2Array(); continue
						pts.append(Vector2(X.call(t[i]), Y.call(float(v[i]))))
					if pts.size() > 1: draw_polyline(pts, color, 1.5, true)
					if i_cur >= 0 and (v[i_cur] is float or v[i_cur] is int):
						var x := float(v[i_cur])
						lec.append("[color=%s]%s: [b]%s[/b][/color]" % [s[1], String(s[0]).replace("_", " "), PantallaTaller.coma(x, 2 if absf(x) < 20 else 1)])
		for e in R.get("eventos", []):                # marcas de los avisos, arriba
			var x: float = X.call(float(e[0]))
			draw_colored_polygon(PackedVector2Array([Vector2(x - 4, 2), Vector2(x + 4, 2), Vector2(x, 9)]), Color("#ffd54f"))
		for k in 7:
			var s := t0 + k * (t1 - t0) / 6; var et := PantallaTaller.fmt_t(s)
			draw_string(f, Vector2(X.call(s) - f.get_string_size(et, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x / 2, H - 4), et, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, suave)
		if i_cur >= 0:
			var xc: float = X.call(t[i_cur])
			draw_line(Vector2(xc, 12), Vector2(xc, H - 16), Color(1, 1, 1, 0.6), 1)
			var s: float = t[i_cur]
			if T.lectura: T.lectura.text = "[b]%d:%s[/b] · %s" % [int(s / 60), ("%04.1f" % fmod(s, 60)).replace(".", ","), " · ".join(PackedStringArray(lec))]


## La traza del vuelo vista desde arriba, coloreada por la bateria (verde llena, rojo vacia), con la casa (Taller.traza).
class TrazaBateria extends Control:
	var R: Dictionary
	func _init(r: Dictionary) -> void: R = r; custom_minimum_size = Vector2(260, 260)
	func _draw() -> void:
		var W := 260.0; var f: Font = Tema.fuente
		draw_style_box(Tema.caja(Color("#0b1119"), Color(0, 0, 0, 0), 8), Rect2(Vector2.ZERO, Vector2(W, W)))
		var la: Array = PantallaTaller.col(R, "latitud"); var lo: Array = PantallaTaller.col(R, "longitud"); var b: Array = PantallaTaller.col(R, "bateria_pct")
		if la.is_empty(): return
		var k := 111320 * cos(deg_to_rad(float(la[0]))); var N := []; var E := []; var Rm := 20.0
		for i in la.size():
			N.append((float(la[i]) - float(la[0])) * 110574); E.append((float(lo[i]) - float(lo[0])) * k)
			Rm = maxf(Rm, maxf(absf(N[i]), absf(E[i])))
		Rm *= 1.1
		var X := func(e: float) -> float: return W / 2 + e / Rm * (W / 2 - 10)
		var Y := func(n: float) -> float: return W / 2 - n / Rm * (W / 2 - 10)
		for i in range(1, N.size()):
			var q := clampf(float(b[i]) / 100, 0, 1) if (b[i] is float or b[i] is int) else 1.0
			draw_line(Vector2(X.call(E[i - 1]), Y.call(N[i - 1])), Vector2(X.call(E[i]), Y.call(N[i])), Color.from_hsv(q * 120 / 360.0, 0.8, 0.85), 2, true)
		draw_circle(Vector2(X.call(0), Y.call(0)), 4, Color.WHITE)
		draw_string(f, Vector2(X.call(0) + 6, Y.call(0) + 4), "casa", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.WHITE)
		draw_string(f, Vector2(6, W - 6), "%d m" % int(round(Rm)), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#9fb3c8"))
		draw_string(f, Vector2(W - 28, 14), "N ↑", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#9fb3c8"))
