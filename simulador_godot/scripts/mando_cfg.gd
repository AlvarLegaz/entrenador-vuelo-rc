class_name MandoCfg
extends RefCounted
## Mando o emisora por USB, como MANDO en simulador/simulador.html: orden de los ejes (mando de consola, emisora AETR o
## TAER, o asignado con el asistente), invertir cada eje, gas con muelle (incremental) o sin muelle (absoluto) y
## exponencial. Convencion interna de las palancas (modo 2): lx izquierda horizontal (+ derecha), ly izquierda vertical
## (- arriba), rx derecha horizontal (+ derecha), ry derecha vertical (- arriba = empujada).
## En Godot un mando conocido (Input.is_joy_known) ya viene en el orden estandar (0 LX, 1 LY, 2 RX, 3 RY, 4 y 5 los
## gatillos); una emisora no es conocida y sus ejes llegan en crudo, en el orden de sus canales, como en el navegador.

const F_CFG := "user://mando.cfg"
const PERFILES := {
	"consola": { "lx": [0, 1], "ly": [1, 1], "rx": [2, 1], "ry": [3, 1] },
	"aetr": { "rx": [0, 1], "ry": [1, -1], "ly": [2, -1], "lx": [3, 1] },
	"taer": { "ly": [0, -1], "rx": [1, 1], "ry": [2, -1], "lx": [3, 1] },
}
const PALANCAS := [["ly", "Gas (izquierda, vertical)"], ["lx", "Timón / guiñada (izquierda, horizontal)"], ["rx", "Alabeo (derecha, horizontal)"], ["ry", "Profundidad (derecha, vertical)"]]
const N_EJES := 10
const PASOS_ASIST := [
	["ly", -1, "Mueve la palanca de [b]gas[/b] (izquierda) arriba y abajo y déjala [b]arriba del todo[/b]."],
	["lx", 1, "Mueve la palanca [b]izquierda[/b] a los lados y mantenla a la [b]derecha[/b] del todo (timón)."],
	["rx", 1, "Mueve la palanca [b]derecha[/b] a los lados y mantenla a la [b]derecha[/b] del todo (alabeo)."],
	["ry", -1, "Mueve la palanca [b]derecha[/b] arriba y abajo y mantenla [b]arriba[/b], empujada del todo (profundidad)."],
]

var gas := "incremental"
## exponencial: el centro de la palanca mueve poco y el extremo da todo el recorrido. Un mando de consola, de palancas
## cortas, necesita mas (60 %) que una emisora (30 %, que ademas suele llevar la suya). Como EXPO_DEFECTO de la web
const EXPO_DEFECTO := { "consola": 0.6, "emisora": 0.3 }
var expo := 0.6
var zona := 0.06
var perfil := "consola"
var ejes := {}
var asist := { "activo": false }
var gimbal := 0.0                 # rueda del gimbal del dron comercial con los gatillos (MANDO.gimbal): la escribe principal en cada cuadro

func _init() -> void:
	ejes = ejes_de("consola")
	var cf := ConfigFile.new()
	if cf.load(F_CFG) != OK: return
	gas = cf.get_value("mando", "gas", gas); expo = cf.get_value("mando", "expo", expo); perfil = cf.get_value("mando", "perfil", perfil)
	var e = cf.get_value("mando", "ejes", {})
	if e is Dictionary and PALANCAS.all(func(par): return e.has(par[0])): ejes = e
	# hasta el 2026-10-13 el defecto era 30 % para todo: con un mando de consola se queda en el defecto nuevo
	if int(cf.get_value("mando", "v", 1)) < 2 and perfil == "consola" and is_equal_approx(expo, 0.3): expo = EXPO_DEFECTO["consola"]

static func ejes_de(p: String) -> Dictionary:
	var P: Dictionary = PERFILES[p]; var e := {}
	for k in P: e[k] = { "i": P[k][0], "s": P[k][1] }
	return e

func guardar() -> void:
	var cf := ConfigFile.new()
	cf.set_value("mando", "v", 2); cf.set_value("mando", "gas", gas); cf.set_value("mando", "expo", expo); cf.set_value("mando", "perfil", perfil); cf.set_value("mando", "ejes", ejes)
	cf.save(F_CFG)

func poner_perfil(p: String) -> void:
	perfil = p
	if PERFILES.has(p): ejes = ejes_de(p)
	if p == "aetr" or p == "taer": gas = "absoluto"          # la palanca de gas de una emisora no tiene muelle
	if p == "consola": gas = "incremental"                    # la de un mando de consola, si
	if PERFILES.has(p): expo = EXPO_DEFECTO["consola"] if p == "consola" else EXPO_DEFECTO["emisora"]
	guardar()

## El primer mando conectado (o -1).
static func conectado() -> int:
	var js := Input.get_connected_joypads()
	return js[0] if not js.is_empty() else -1

## Recorrido (0-1) a media palanca con la exponencial puesta (el texto de Ajustes).
func media_palanca() -> float: return (1 - expo) * 0.5 + expo * 0.125

## Valor de una palanca (lx, ly, rx, ry) en la convencion interna, sin zona muerta (ejeMando).
func eje(dev: int, k: String) -> float:
	var e: Dictionary = ejes[k]
	return clampf(Input.get_joy_axis(dev, int(e["i"])) * float(e["s"]), -1, 1)

func ejes_crudos(dev: int) -> Array:
	var a := []
	for i in N_EJES: a.append(Input.get_joy_axis(dev, i))
	return a

## Aviso de la web: un dispositivo que no es un mando estandar y sigue con el orden de consola.
func aviso(dev: int) -> String:
	if dev >= 0 and not Input.is_joy_known(dev) and perfil == "consola":
		return "Este dispositivo no es un mando de consola (parece una emisora): elige el orden de canales de tu emisora o usa el asistente; con el orden de consola el gas y el alabeo salen cambiados."
	return ""

# ---- asistente: cada palanca se mueve y se deja en un extremo; el eje que mas ha recorrido y esta en ese extremo es el
# suyo, y el signo sale de hacia donde esta ----
func empezar_asistente(dev: int) -> void:
	asist = { "activo": true, "paso": 0, "nuevos": {}, "usados": {} }
	_reiniciar_paso(dev)

func _reiniciar_paso(dev: int) -> void:
	var a := ejes_crudos(dev)
	asist["min"] = a.duplicate(); asist["max"] = a.duplicate(); asist["cand"] = -1; asist["t"] = 0.0

func texto_asistente() -> String:
	if not asist["activo"]: return ""
	return "Paso %d de 4. %s" % [asist["paso"] + 1, PASOS_ASIST[asist["paso"]][2]]

## Un cuadro del asistente; devuelve true al terminar.
func paso_asistente(dev: int) -> bool:
	if not asist["activo"]: return false
	var a := ejes_crudos(dev)
	for i in a.size():
		asist["min"][i] = minf(asist["min"][i], a[i]); asist["max"][i] = maxf(asist["max"][i], a[i])
	var mejor := -1; var rec := 0.9
	for i in a.size():
		if not asist["usados"].has(i) and asist["max"][i] - asist["min"][i] > rec and absf(a[i]) > 0.7: mejor = i; rec = asist["max"][i] - asist["min"][i]
	var ahora := Time.get_ticks_msec() / 1000.0
	if mejor != asist["cand"]: asist["cand"] = mejor; asist["t"] = ahora; return false
	if mejor < 0 or ahora - asist["t"] < 0.5: return false          # medio segundo quieta en el extremo
	var k: String = PASOS_ASIST[asist["paso"]][0]; var objetivo: int = PASOS_ASIST[asist["paso"]][1]
	asist["nuevos"][k] = { "i": mejor, "s": 1 if signf(a[mejor]) == objetivo else -1 }; asist["usados"][mejor] = true
	asist["paso"] += 1
	if asist["paso"] < PASOS_ASIST.size(): _reiniciar_paso(dev); return false
	ejes = asist["nuevos"]; perfil = "propio"; asist["activo"] = false; guardar()
	return true
