class_name Cuat
## Cuaterniones [w, x, y, z]: rotacion cuerpo -> mundo NED. Traduccion literal de Cuat en simulador/js/modelos.js
## (mismas formulas y mismo orden de operaciones, para que la fisica de los dos simuladores coincida).

static func mul(a: Array, b: Array) -> Array:
	return [a[0]*b[0]-a[1]*b[1]-a[2]*b[2]-a[3]*b[3], a[0]*b[1]+a[1]*b[0]+a[2]*b[3]-a[3]*b[2],
			a[0]*b[2]-a[1]*b[3]+a[2]*b[0]+a[3]*b[1], a[0]*b[3]+a[1]*b[2]-a[2]*b[1]+a[3]*b[0]]

static func norm(q: Array) -> Array:
	var n := sqrt(q[0]*q[0] + q[1]*q[1] + q[2]*q[2] + q[3]*q[3])
	return [q[0] / n, q[1] / n, q[2] / n, q[3] / n]

## Gira v (cuerpo) a mundo.
static func rot(q: Array, v: Array) -> Array:
	var w: float = q[0]; var x: float = q[1]; var y: float = q[2]; var z: float = q[3]
	var t := [2*(y*v[2]-z*v[1]), 2*(z*v[0]-x*v[2]), 2*(x*v[1]-y*v[0])]
	return [v[0]+w*t[0]+y*t[2]-z*t[1], v[1]+w*t[1]+z*t[0]-x*t[2], v[2]+w*t[2]+x*t[1]-y*t[0]]

static func inv(q: Array) -> Array:
	return [q[0], -q[1], -q[2], -q[3]]

static func desde_euler(roll: float, pitch: float, yaw: float) -> Array:
	var cr := cos(roll/2); var sr := sin(roll/2); var cp := cos(pitch/2); var sp := sin(pitch/2)
	var cy := cos(yaw/2); var sy := sin(yaw/2)
	return [cr*cp*cy+sr*sp*sy, sr*cp*cy-cr*sp*sy, cr*sp*cy+sr*cp*sy, cr*cp*sy-sr*sp*cy]

## [alabeo, cabeceo, rumbo] en radianes.
static func euler(q: Array) -> Array:
	var w: float = q[0]; var x: float = q[1]; var y: float = q[2]; var z: float = q[3]
	return [atan2(2*(w*x+y*z), 1-2*(x*x+y*y)), asin(clampf(2*(w*y-z*x), -1.0, 1.0)), atan2(2*(w*z+x*y), 1-2*(y*y+z*z))]
