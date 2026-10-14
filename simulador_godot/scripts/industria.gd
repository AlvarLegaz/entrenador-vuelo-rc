class_name Industria
## Instalaciones industriales de singulares.js (tanques, esferas, balas, columnas, estructuras de proceso, racks de
## tuberias, chimeneas y torres de refrigeracion): traduccion LITERAL de simulador/js/industria.js. Cada pieza se
## descompone en primitivas [forma, e, n, y0, sx, sy, sz, rumbo, color] que mundo_3d.gd dibuja con MultiMesh
## (0 caja, 1 cilindro de pie, 2 cilindro tumbado hacia rumbo, 3 elipsoide; y0 su base sobre el suelo del punto).

const TIPOS := ["tanque", "esfera", "bala", "columna", "estructura", "rack", "chimenea", "refrigeracion"]
const COLORES := ["#7a8087", "#4d5257", "#e6e6e0", "#d8d2c0", "#a8704a", "#b9bec4", "#c9a83a", "#5f8a5a", "#5b5f63", "#2c3a3a", "#b8352e", "#a9a59c", "#3f6a95", "#d9b632"]

## El mismo pseudoazar que sabic_industria.py (h) y Industria.azar de la web.
static func azar(v: float, i: float) -> float:
	var x := sin((v * 1000 + i) * 12.9898) * 43758.5453
	return x - floor(x)

## Primitivas de una pieza (lista vacia si no es industrial).
static func primitivas(p: Dictionary) -> Array:
	var P := []; var R: float = float(p.get("rumbo", 0.0)); var sr := sin(deg_to_rad(R)); var cr := cos(deg_to_rad(R))
	var pe: float = p.get("e", 0.0); var pn: float = p.get("n", 0.0)
	var en := func(x: float, z: float) -> Array: return [pe + x * sr + z * cr, pn + x * cr - z * sr]     # (x hacia rumbo, z a su derecha)
	var caja := func(x: float, z: float, y0: float, a: float, h: float, b: float, c: int) -> void:
		var q: Array = en.call(x, z); P.append([0, q[0], q[1], y0, a, h, b, R, c])
	var cil := func(x: float, z: float, y0: float, d: float, h: float, c: int) -> void:
		var q: Array = en.call(x, z); P.append([1, q[0], q[1], y0, d, h, d, 0.0, c])
	match String(p["tipo"]):
		"tanque":
			var r: float = p["radio"]; var H: float = p["alto"]; var c: int = int(p.get("color", 2))
			cil.call(0, 0, 0, 2 * r, H, c)
			if p.get("techo") == "cupula": P.append([3, pe, pn, H - 0.25 * r, 2 * r, 0.5 * r, 2 * r, 0.0, c])
			if p.get("techo") == "abierto":                                      # decantador: agua, puente y motor
				cil.call(0, 0, H - 0.45, 2 * r - 0.5, 0.3, 9); caja.call(0, 0, H, 2 * r + 1, 0.7, 1.2, 0); cil.call(0, 0, H, 1.6, 1.2, 1)
			else:
				caja.call(-(r + 0.2), 0, 0, 0.3, H + 1, 0.7, 13)                   # escalera de gato
		"esfera":
			var r: float = p["radio"]
			for xz in [[-0.7, -0.7], [0.7, -0.7], [0.7, 0.7], [-0.7, 0.7]]: cil.call(xz[0] * r, xz[1] * r, 0, 0.35, 1.4 + r, 0)
			P.append([3, pe, pn, 1.4, 2 * r, 2 * r, 2 * r, 0.0, 2])
		"bala":
			var r: float = p["radio"]; var L: float = p["largo"]; var y := 1.0; var q: Array = en.call(0, 0)
			P.append([2, q[0], q[1], y, L - r, 2 * r, 2 * r, R, 2])
			for s in [-1, 1]:
				var q2: Array = en.call(s * (L - r) / 2, 0); P.append([3, q2[0], q2[1], y, r, 2 * r, 2 * r, R, 2]); caja.call(s * L / 4, 0, 0, 0.6, y + 0.3 * r, 1.6 * r, 11)
		"columna":
			var r: float = p["radio"]; var H: float = p["alto"]
			cil.call(0, 0, 0, 2 * r + 0.4, 1.5, 11); cil.call(0, 0, 0, 2 * r, H, 3)
			P.append([3, pe, pn, H - 0.5 * r, 2 * r, r, 2 * r, 0.0, 3])
			var y := 6.0
			while y < H - 2: cil.call(0, 0, y, 2 * r + 1.6, 0.15, 8); y += 7          # plataformas
			caja.call(-(r + 0.35), 0, 0, 0.4, H - 1, 0.4, 5)                          # tuberia que sube por el costado
		"estructura":
			var L: float = p["largo"]; var A: float = p["ancho"]; var H: float = p["alto"]; var s: float = p["semilla"]; var pisos: int = int(p["pisos"])
			var az := func(i: float) -> float: return Industria.azar(s, i)
			var nx := ceili(L / 6); var nz := ceili(A / 6)
			for i in nx + 1:
				for j in nz + 1: caja.call(-L / 2 + i * L / nx, -A / 2 + j * A / nz, 0, 0.35, H, 0.35, 0)
			for k in range(1, pisos + 1):
				var y := k * H / pisos - 0.18
				caja.call(0, 0, y, L, 0.18, A, 8)                                          # piso de rejilla
				caja.call(0, A / 2, y + 0.18, L, 1.0, 0.06, 13 if k % 2 else 0)            # barandilla del lado de la escalera
				if k < pisos or az.call(30 + k) < 0.5:                                    # equipos en el piso
					var a: float = 1.5 + 2 * az.call(20 + k); var b: float = 1 + 1.2 * az.call(40 + k); var h: float = 0.8 + 1.4 * az.call(50 + k)
					caja.call((az.call(60 + k) - 0.5) * (L - a - 1), (az.call(70 + k) - 0.5) * (A - b - 1), y + 0.18, a, h, b, 12 if az.call(80 + k) < 0.5 else 1)
			var nv := 1 + int(floor(az.call(1) * 3))
			for i in nv:                                                                  # recipientes de pie
				var r: float = 0.6 + az.call(8 + i) * 1.0; var h: float = H * (0.6 + 0.5 * az.call(11 + i))
				var x: float = (az.call(2 + i) - 0.5) * (L - 2 * r - 1); var z: float = (az.call(5 + i) - 0.5) * (A - 2 * r - 1); var c := 5 if i % 2 else 2
				cil.call(x, z, 0, 2 * r, h, c); var q: Array = en.call(x, z); P.append([3, q[0], q[1], h - 0.3 * r, 2 * r, 0.6 * r, 2 * r, 0.0, c])
			caja.call(L / 2 + 1.0, A / 2 - 1.2, 0, 2.0, H + 1.2, 2.4, 1)                  # escalera en torre
		"rack":
			var de: float = p["e1"] - p["e0"]; var dn: float = p["n1"] - p["n0"]; var L := Vector2(de, dn).length(); var Rr := rad_to_deg(atan2(de, dn)); var s2 := de / L; var c2 := dn / L
			var e0: float = p["e0"]; var n0: float = p["n0"]; var W: float = p["ancho"]; var alto: float = p["alto"]; var niv: int = int(p["niveles"]); var nb := maxi(1, ceili(L / 6))
			var en2 := func(x: float, z: float) -> Array: return [e0 + x * s2 + z * c2, n0 + x * c2 - z * s2]
			for k in nb + 1:
				var x := k * L / nb
				for z in [-W / 2, W / 2]: var q: Array = en2.call(x, z); P.append([0, q[0], q[1], 0.0, 0.35, alto, 0.35, Rr, 0])
				for j in range(1, niv + 1): var q: Array = en2.call(x, 0); P.append([0, q[0], q[1], alto * j / niv - 0.3, 0.3, 0.3, W + 0.35, Rr, 0])
			for j in range(1, niv + 1):
				var nt := maxi(3, int(floor(W / 0.9)))
				for i in nt:
					var d := 0.25 + 0.45 * Industria.azar(j, i); var a := Industria.azar(j, 50 + i); var c := 5 if a < 0.7 else (6 if a < 0.85 else 7)
					var q: Array = en2.call(L / 2, -W / 2 + 0.5 + i * (W - 1) / (nt - 1))
					P.append([2, q[0], q[1], alto * j / niv, L, d, d, Rr, c])
		"chimenea":
			var r: float = p["radio"]; var H: float = p["alto"]
			cil.call(0, 0, 0, 2 * r + 0.6, 0.85 * H, 11)
			cil.call(0, 0, 0.85 * H, 2 * r, 0.05 * H, 10); cil.call(0, 0, 0.9 * H, 2 * r, 0.05 * H, 2); cil.call(0, 0, 0.95 * H, 2 * r, 0.05 * H, 10)
			cil.call(0, 0, H, 2 * r - 0.3, 0.1, 1)
		"refrigeracion":
			var L: float = p["largo"]; var A: float = p["ancho"]; var H: float = p["alto"]; var nc: int = int(p["celdas"]); var d := minf(L / nc, A) * 0.8
			caja.call(0, 0, 0, L, H, A, 11); caja.call(0, 0, 0.6, L - 0.4, H * 0.6, A + 0.12, 1)   # cuerpo y rejillas de entrada de aire
			for i in nc:
				var x := (i + 0.5) * L / nc - L / 2; cil.call(x, 0, H, d, 2.6, 5); cil.call(x, 0, H + 2.6, d - 0.3, 0.05, 1)
	return P

## Solido para las colisiones: [planta (E, N, ...), alto]. [] si no es industrial.
static func solido(p: Dictionary) -> Array:
	var R := deg_to_rad(float(p.get("rumbo", 0.0))); var sr := sin(R); var cr := cos(R)
	var rect := func(e: float, n: float, L: float, A: float, sr2: float, cr2: float) -> Array:
		var o := []
		for xz in [[-L / 2, -A / 2], [L / 2, -A / 2], [L / 2, A / 2], [-L / 2, A / 2]]: o.append_array([e + xz[0] * sr2 + xz[1] * cr2, n + xz[0] * cr2 - xz[1] * sr2])
		return o
	match String(p["tipo"]):
		"tanque": return [rect.call(p["e"], p["n"], 1.8 * p["radio"], 1.8 * p["radio"], 0.0, 1.0), p["alto"] + (0.25 * p["radio"] if p.get("techo") == "cupula" else 1.0)]
		"esfera": return [rect.call(p["e"], p["n"], 2 * p["radio"], 2 * p["radio"], 0.0, 1.0), 1.4 + 2 * p["radio"]]
		"bala": return [rect.call(p["e"], p["n"], p["largo"], 2 * p["radio"], sr, cr), 1 + 2 * p["radio"]]
		"columna", "chimenea": return [rect.call(p["e"], p["n"], 2 * p["radio"], 2 * p["radio"], 0.0, 1.0), p["alto"]]
		"estructura": return [rect.call(p["e"], p["n"], p["largo"] + 2, p["ancho"], sr, cr), p["alto"] + 1.2]
		"refrigeracion": return [rect.call(p["e"], p["n"], p["largo"], p["ancho"], sr, cr), p["alto"] + 2.6]
		"rack":
			var de: float = p["e1"] - p["e0"]; var dn: float = p["n1"] - p["n0"]; var L := Vector2(de, dn).length()
			return [rect.call((p["e0"] + p["e1"]) / 2, (p["n0"] + p["n1"]) / 2, L, p["ancho"], de / L, dn / L), p["alto"] + 0.5]
	return []
