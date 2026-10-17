extends RefCounted
## Ayuda de las pruebas que se lanzan contra un aula en marcha: lo que hace el profesor en su panel (con el PIN), que la
## aplicacion no necesita (el cliente del aula, aula.gd, no manda el token del profesor). Uso:
##   const UtilAula = preload("res://Tests/util_aula.gd")
##   await UtilAula.alta(nodo, url, pin, usuario, clave)     # el alumno, dado de alta por el profesor (ya aprobado)
##   await UtilAula.aprobar(nodo, url, pin, usuario)          # aprueba la solicitud de registro de usuario

## [codigo, json] de una peticion a la API del aula (token: el del profesor, o "").
static func pedir(nodo: Node, url: String, metodo: String, ruta: String, cuerpo = null, token := "") -> Array:
	var req := HTTPRequest.new(); req.timeout = 8; nodo.add_child(req)
	var cab := PackedStringArray(["Content-Type: application/json"])
	if token != "": cab.append("Authorization: Bearer " + token)
	var m: int = HTTPClient.METHOD_POST if metodo == "POST" else HTTPClient.METHOD_GET
	req.request(url.trim_suffix("/") + "/api/" + ruta, cab, m, JSON.stringify(cuerpo) if cuerpo != null else "")
	var res: Array = await req.request_completed
	req.queue_free()
	var b: PackedByteArray = res[3]
	return [int(res[1]), JSON.parse_string(b.get_string_from_utf8()) if b.size() else null]

static func token(nodo: Node, url: String, pin: String) -> String:
	var r := await pedir(nodo, url, "POST", "profesor/entrar", { "pin": pin })
	return String(r[1]["token"]) if r[0] < 300 and r[1] is Dictionary else ""

## El alumno, dado de alta por el profesor (ya aprobado). true si queda (o ya estaba).
static func alta(nodo: Node, url: String, pin: String, usuario: String, clave: String) -> bool:
	var t := await token(nodo, url, pin)
	var r := await pedir(nodo, url, "POST", "profesor/alumnos", { "nombre": usuario, "clave": clave }, t)
	return r[0] < 300 or r[0] == 409

## Aprueba la solicitud de registro del alumno usuario. true si estaba pendiente y queda aprobado.
static func aprobar(nodo: Node, url: String, pin: String, usuario: String) -> bool:
	var t := await token(nodo, url, pin)
	var l := await pedir(nodo, url, "GET", "profesor/alumnos", null, t)
	if not l[1] is Array: return false
	for a in l[1]:
		if a["nombre"] == usuario and a.get("pendiente", false):
			var r := await pedir(nodo, url, "POST", "profesor/alumnos/%s/aprobar" % a["id"], {}, t)
			return r[0] < 300
	return false
