class_name PantallaMisiones
extends RefCounted
## Entrenamientos (#pEntrenamientos) y vuelo libre (#pVolar) de simulador/simulador.html, con el panel de condiciones
## (#condiciones) que comparten, y los iconos de las misiones (iconoMision, los mismos SVG).

## Icono esquematico de cada mision (SVG de 200 x 110), igual que iconoMision de la web.
static func icono(id: String) -> String:
	var avion := func(x: float, y: float, a: float, c := "#fff") -> String:
		return '<g transform="translate(%s %s) rotate(%s)"><path d="M-9 0H9M-2 -7V7M6 -3V3" stroke="%s" stroke-width="2.6" stroke-linecap="round" fill="none"/></g>' % [x, y, a, c]
	var pil := func(x: float, y: float, c: String) -> String: return '<circle cx="%s" cy="%s" r="5" fill="%s" stroke="#000" stroke-width="1"/>' % [x, y, c]
	var P := ["#4caf50", "#ffeb3b", "#f44336", "#42a5f5"]; var tr := "#ffc83d"
	var pista := func(x: float, y: float, w: float, h: float) -> String: return '<rect x="%s" y="%s" width="%s" height="%s" fill="#8a8a8a" rx="2"/>' % [x, y, w, h]
	var flecha := func(x: float, y: float, a: float) -> String: return '<g transform="translate(%s %s) rotate(%s)"><path d="M-5 -4L2 0-5 4z" fill="%s"/></g>' % [x, y, a, tr]
	var ini := '<svg viewBox="0 0 200 110" width="200" height="110" xmlns="http://www.w3.org/2000/svg">'; var fin := "</svg>"
	match id:
		"primer_vuelo": return ini + pista.call(96, 70, 8, 30) + '<path d="M60 35 Q100 10 140 35 Q165 55 140 80 Q100 100 60 80 Q35 55 60 35z" fill="none" stroke="%s" stroke-width="2" stroke-dasharray="6 4"/>' % tr + \
			pil.call(60, 35, P[0]) + pil.call(140, 35, P[1]) + pil.call(140, 80, P[2]) + pil.call(60, 80, P[3]) + flecha.call(100, 21, 0) + avion.call(100, 55, -10) + fin
		"orientacion": return ini + '<path d="M100 55 C70 20 25 25 25 55 C25 85 70 90 100 55 C130 20 175 25 175 55 C175 85 130 90 100 55" fill="none" stroke="%s" stroke-width="2.5"/>' % tr + \
			pil.call(140, 35, P[2]) + pil.call(140, 75, P[3]) + pil.call(60, 35, P[1]) + pil.call(60, 75, P[0]) + flecha.call(173, 45, -80) + flecha.call(27, 65, 100) + avion.call(100, 55, 30) + fin
		"viento_cruzado": return ini + pista.call(92, 15, 16, 80) + '<g stroke="#4fc3f7" stroke-width="2.5" stroke-linecap="round" fill="none"><path d="M20 35h30M20 55h40M20 75h30"/><path d="M44 29l6 6-6 6M54 49l6 6-6 6M44 69l6 6-6 6"/></g>' + \
			avion.call(140, 55, -70) + '<path d="M140 80 L140 100" stroke="%s" stroke-width="2" stroke-dasharray="4 3"/>' % tr + fin
		"emergencia": return ini + '<path d="M40 25 C80 30 120 55 170 90" fill="none" stroke="%s" stroke-width="2" stroke-dasharray="6 4"/><path d="M10 92h180" stroke="#6b4a1e" stroke-width="3"/>' % tr + \
			avion.call(40, 25, 20) + '<g stroke="#ff5252" stroke-width="3" stroke-linecap="round"><path d="M58 12l10 10M68 12l-10 10"/></g>' + fin
		"puerta": return ini + '<rect x="70" y="20" width="6" height="70" fill="#ff8f00"/><rect x="124" y="20" width="6" height="70" fill="#ff8f00"/>' + \
			'<path d="M20 60 H180" stroke="%s" stroke-width="2" stroke-dasharray="6 4"/>' % tr + flecha.call(170, 60, 0) + flecha.call(30, 72, 180) + avion.call(100, 60, 0) + fin
		"pasada_baja": return ini + '<rect x="20" y="78" width="160" height="12" fill="#8d6e63" rx="2"/><path d="M15 60 H185" stroke="%s" stroke-width="2" stroke-dasharray="6 4"/>' % tr + \
			'<path d="M30 48 H60" stroke="#fff" stroke-width="1" stroke-dasharray="2 2"/><text x="64" y="51" fill="#fff" font-size="9">2–8 m</text>' + avion.call(100, 60, 0) + flecha.call(175, 60, 0) + fin
		"diana": return ini + '<g fill="none" stroke="#e0e0e0" stroke-width="1.5"><circle cx="100" cy="68" r="34"/><circle cx="100" cy="68" r="22"/><circle cx="100" cy="68" r="10"/></g><circle cx="100" cy="68" r="3" fill="#ff5252"/>' + \
			'<path d="M30 15 Q70 30 96 62" fill="none" stroke="%s" stroke-width="2" stroke-dasharray="6 4"/>' % tr + avion.call(36, 18, 35) + fin
		"recorrido": return ini + '<rect x="10" y="80" width="60" height="9" fill="#8d6e63" rx="2"/><rect x="92" y="30" width="4" height="40" fill="#ff8f00"/><rect x="118" y="30" width="4" height="40" fill="#ff8f00"/>' + \
			'<g fill="none" stroke="#e0e0e0" stroke-width="1.5"><circle cx="165" cy="80" r="18"/><circle cx="165" cy="80" r="8"/></g>' + \
			'<path d="M15 70 H70 Q90 60 105 50 L130 50 Q150 55 162 76" fill="none" stroke="%s" stroke-width="2" stroke-dasharray="6 4"/>' % tr + \
			'<g fill="%s" font-size="12" font-weight="700"><text x="36" y="72">1</text><text x="102" y="24">2</text><text x="148" y="106">3</text></g>' % tr + fin
		"aterrizaje": return ini + pista.call(28, 20, 12, 70) + '<path d="M34 25 C34 10 170 10 170 25 L170 85 C170 100 34 100 34 90" fill="none" stroke="%s" stroke-width="2" stroke-dasharray="6 4"/>' % tr + \
			flecha.call(102, 15, 0) + flecha.call(170, 55, 90) + flecha.call(102, 95, 180) + avion.call(34, 60, -90) + '<text x="46" y="60" fill="#fff" font-size="9">final</text>' + fin
		# operaciones y dron FPV: los mismos SVG que iconoMision de la web
		"op_inspeccion": return '<svg viewBox="0 0 200 110" width="200" height="110" xmlns="http://www.w3.org/2000/svg"><path d="M30 100V45H95V100M95 100V30H160V100" fill="#5d6b78" stroke="#cfd8dc" stroke-width="1.5"/><path d="M40 55h12v10H40zM60 55h12v10H60zM40 75h12v10H40zM105 40h12v10h-12zM125 40h12v10h-12zM105 60h12v10h-12z" fill="#90caf9"/><rect x="137" y="22" width="12" height="7" fill="#ff6d00" stroke="#fff" stroke-width="1"/><path d="M150 0L128 26L158 26z" fill="#4fc3f7" fill-opacity="0.25" stroke="#4fc3f7" stroke-width="1"/><g transform="translate(160 12) rotate(0) scale(1)"><path d="M-8 -8L8 8M8 -8L-8 8" stroke="#fff" stroke-width="2.4"/><g fill="none" stroke="#fff" stroke-width="1.6"><circle cx="-8" cy="-8" r="4.5"/><circle cx="8" cy="-8" r="4.5"/><circle cx="-8" cy="8" r="4.5"/><circle cx="8" cy="8" r="4.5"/></g><rect x="-3" y="-3" width="6" height="6" fill="#9e9e9e"/></g></svg>'
		"op_fotogrametria": return '<svg viewBox="0 0 200 110" width="200" height="110" xmlns="http://www.w3.org/2000/svg"><rect x="25" y="40" width="150" height="60" fill="#8d6e63" stroke="#e53935" stroke-width="1.5" stroke-dasharray="5 3"/><rect x="30" y="45" width="40" height="30" fill="#fff" fill-opacity="0.12" stroke="#fff" stroke-opacity="0.7"/><rect x="60" y="67" width="40" height="30" fill="#fff" fill-opacity="0.12" stroke="#fff" stroke-opacity="0.7"/><rect x="90" y="45" width="40" height="30" fill="#fff" fill-opacity="0.12" stroke="#fff" stroke-opacity="0.7"/><rect x="120" y="67" width="40" height="30" fill="#fff" fill-opacity="0.12" stroke="#fff" stroke-opacity="0.7"/><rect x="150" y="45" width="40" height="30" fill="#fff" fill-opacity="0.12" stroke="#fff" stroke-opacity="0.7"/><path d="M30 25H170V35H30" fill="none" stroke="#ffc83d" stroke-width="2" stroke-dasharray="6 4"/><g transform="translate(100 25) rotate(0) scale(1)"><path d="M-8 -8L8 8M8 -8L-8 8" stroke="#fff" stroke-width="2.4"/><g fill="none" stroke="#fff" stroke-width="1.6"><circle cx="-8" cy="-8" r="4.5"/><circle cx="8" cy="-8" r="4.5"/><circle cx="-8" cy="8" r="4.5"/><circle cx="8" cy="8" r="4.5"/></g><rect x="-3" y="-3" width="6" height="6" fill="#9e9e9e"/></g></svg>'
		"op_busqueda": return '<svg viewBox="0 0 200 110" width="200" height="110" xmlns="http://www.w3.org/2000/svg"><path d="M0 100L40 60L70 80L110 40L150 75L200 50V110H0z" fill="#5d4f3a"/><circle cx="128" cy="68" r="3.5" fill="#e53935"/><circle cx="128" cy="66" r="16" fill="none" stroke="#fff" stroke-width="2.5"/><path d="M140 78L152 90" stroke="#fff" stroke-width="4" stroke-linecap="round"/><g transform="translate(60 22) rotate(0) scale(1)"><path d="M-8 -8L8 8M8 -8L-8 8" stroke="#fff" stroke-width="2.4"/><g fill="none" stroke="#fff" stroke-width="1.6"><circle cx="-8" cy="-8" r="4.5"/><circle cx="8" cy="-8" r="4.5"/><circle cx="-8" cy="8" r="4.5"/><circle cx="8" cy="8" r="4.5"/></g><rect x="-3" y="-3" width="6" height="6" fill="#9e9e9e"/></g></svg>'
		"op_agricultura": return '<svg viewBox="0 0 200 110" width="200" height="110" xmlns="http://www.w3.org/2000/svg"><path d="M15 50H185" stroke="#43a047" stroke-width="5"/><path d="M15 59H185" stroke="#43a047" stroke-width="5"/><path d="M15 68H185" stroke="#43a047" stroke-width="5"/><path d="M15 77H185" stroke="#43a047" stroke-width="5"/><path d="M15 86H185" stroke="#43a047" stroke-width="5"/><path d="M15 95H185" stroke="#43a047" stroke-width="5"/><ellipse cx="70" cy="68" rx="16" ry="9" fill="#d4c13a" fill-opacity="0.9"/><ellipse cx="140" cy="85" rx="12" ry="7" fill="#d4c13a" fill-opacity="0.9"/><path d="M110 18L52 66L90 70z" fill="#4fc3f7" fill-opacity="0.25" stroke="#4fc3f7" stroke-width="1"/><g transform="translate(110 18) rotate(0) scale(1)"><path d="M-8 -8L8 8M8 -8L-8 8" stroke="#fff" stroke-width="2.4"/><g fill="none" stroke="#fff" stroke-width="1.6"><circle cx="-8" cy="-8" r="4.5"/><circle cx="8" cy="-8" r="4.5"/><circle cx="-8" cy="8" r="4.5"/><circle cx="8" cy="8" r="4.5"/></g><rect x="-3" y="-3" width="6" height="6" fill="#9e9e9e"/></g></svg>'
		"op_paneles": return '<svg viewBox="0 0 200 110" width="200" height="110" xmlns="http://www.w3.org/2000/svg"><path d="M20 48H180L172 58H28z" fill="#1d3f73" stroke="#9fb3c8" stroke-width="1"/><path d="M42 48l-4 10" stroke="#9fb3c8" stroke-width="0.6"/><path d="M58 48l-4 10" stroke="#9fb3c8" stroke-width="0.6"/><path d="M74 48l-4 10" stroke="#9fb3c8" stroke-width="0.6"/><path d="M90 48l-4 10" stroke="#9fb3c8" stroke-width="0.6"/><path d="M106 48l-4 10" stroke="#9fb3c8" stroke-width="0.6"/><path d="M122 48l-4 10" stroke="#9fb3c8" stroke-width="0.6"/><path d="M138 48l-4 10" stroke="#9fb3c8" stroke-width="0.6"/><path d="M154 48l-4 10" stroke="#9fb3c8" stroke-width="0.6"/><path d="M170 48l-4 10" stroke="#9fb3c8" stroke-width="0.6"/><path d="M28 63H172L164 73H36z" fill="#1d3f73" stroke="#9fb3c8" stroke-width="1"/><path d="M50 63l-4 10" stroke="#9fb3c8" stroke-width="0.6"/><path d="M66 63l-4 10" stroke="#9fb3c8" stroke-width="0.6"/><path d="M82 63l-4 10" stroke="#9fb3c8" stroke-width="0.6"/><path d="M98 63l-4 10" stroke="#9fb3c8" stroke-width="0.6"/><path d="M114 63l-4 10" stroke="#9fb3c8" stroke-width="0.6"/><path d="M130 63l-4 10" stroke="#9fb3c8" stroke-width="0.6"/><path d="M146 63l-4 10" stroke="#9fb3c8" stroke-width="0.6"/><path d="M162 63l-4 10" stroke="#9fb3c8" stroke-width="0.6"/><path d="M36 78H164L156 88H44z" fill="#1d3f73" stroke="#9fb3c8" stroke-width="1"/><path d="M58 78l-4 10" stroke="#9fb3c8" stroke-width="0.6"/><path d="M74 78l-4 10" stroke="#9fb3c8" stroke-width="0.6"/><path d="M90 78l-4 10" stroke="#9fb3c8" stroke-width="0.6"/><path d="M106 78l-4 10" stroke="#9fb3c8" stroke-width="0.6"/><path d="M122 78l-4 10" stroke="#9fb3c8" stroke-width="0.6"/><path d="M138 78l-4 10" stroke="#9fb3c8" stroke-width="0.6"/><path d="M154 78l-4 10" stroke="#9fb3c8" stroke-width="0.6"/><path d="M44 93H156L148 103H52z" fill="#1d3f73" stroke="#9fb3c8" stroke-width="1"/><path d="M66 93l-4 10" stroke="#9fb3c8" stroke-width="0.6"/><path d="M82 93l-4 10" stroke="#9fb3c8" stroke-width="0.6"/><path d="M98 93l-4 10" stroke="#9fb3c8" stroke-width="0.6"/><path d="M114 93l-4 10" stroke="#9fb3c8" stroke-width="0.6"/><path d="M130 93l-4 10" stroke="#9fb3c8" stroke-width="0.6"/><path d="M146 93l-4 10" stroke="#9fb3c8" stroke-width="0.6"/><path d="M84 64l8 8M92 64l-8 8M120 79l8 8M128 79l-8 8" stroke="#ff5252" stroke-width="2.4"/><g transform="translate(100 22)"><path d="M-8 -8L8 8M8 -8L-8 8" stroke="#fff" stroke-width="2.4"/><g fill="none" stroke="#fff" stroke-width="1.6"><circle cx="-8" cy="-8" r="4.5"/><circle cx="8" cy="-8" r="4.5"/><circle cx="-8" cy="8" r="4.5"/><circle cx="8" cy="8" r="4.5"/></g><rect x="-3" y="-3" width="6" height="6" fill="#9e9e9e"/></g><path d="M100 30L84 64H116z" fill="#4fc3f7" fill-opacity="0.2" stroke="#4fc3f7" stroke-width="1"/></svg>'
		"op_sabic": return '<svg viewBox="0 0 200 110" width="200" height="110" xmlns="http://www.w3.org/2000/svg"><path d="M8 78H192M8 84H192" stroke="#b0bec5" stroke-width="2.5"/><path d="M20 84V104M60 84V104M100 84V104M140 84V104M180 84V104" stroke="#78909c" stroke-width="2"/><rect x="22" y="52" width="40" height="26" fill="#546e7a"/><rect x="70" y="40" width="11" height="38" rx="2" fill="#90a4ae"/><rect x="86" y="32" width="11" height="46" rx="2" fill="#90a4ae"/><circle cx="84" cy="58" r="27" fill="none" stroke="#ff5252" stroke-width="1.6" stroke-dasharray="4 3"/><path d="M156 104V24H164V104z" fill="#eceff1"/><path d="M156 24H164V34H156zM156 44H164V54H156z" fill="#e53935"/><path d="M160 24C153 16 158 10 160 4C163 10 167 16 160 24z" fill="#ff9800"/><path d="M160 22C157 18 159 14 160 11C161 14 163 18 160 22z" fill="#ffeb3b"/><path d="M122 30L110 76H134z" fill="#ff9800" fill-opacity="0.22" stroke="#ff9800" stroke-width="1"/><circle cx="122" cy="78" r="4.5" fill="#ffeb3b" stroke="#ff5722" stroke-width="2"/><g transform="translate(122 22)"><path d="M-8 -8L8 8M8 -8L-8 8" stroke="#fff" stroke-width="2.4"/><g fill="none" stroke="#fff" stroke-width="1.6"><circle cx="-8" cy="-8" r="4.5"/><circle cx="8" cy="-8" r="4.5"/><circle cx="-8" cy="8" r="4.5"/><circle cx="8" cy="8" r="4.5"/></g><rect x="-3" y="-3" width="6" height="6" fill="#9e9e9e"/></g></svg>'
		"op_patrulla": return '<svg viewBox="0 0 200 110" width="200" height="110" xmlns="http://www.w3.org/2000/svg"><rect x="0" y="62" width="200" height="48" fill="#0d3b5c"/><path d="M10 74q8-4 16 0t16 0M120 70q8-4 16 0t16 0M150 98q8-4 16 0t16 0M14 100q8-4 16 0t16 0" fill="none" stroke="#4f8db8" stroke-width="1.4"/><path d="M70 86c4-10 26-14 42-10c14 3 22 8 14 15c-8 7-30 9-44 5c-10-3-14-5-12-10z" fill="#5d4e37" fill-opacity="0.85" stroke="#b39b6c" stroke-width="1.2"/><path d="M84 86c6-5 18-6 26-3c6 3 4 7-4 8c-9 1-20 0-22-5z" fill="#1e1a14"/><path d="M100 34L76 84H124z" fill="#4fc3f7" fill-opacity="0.18" stroke="#4fc3f7" stroke-width="1"/><circle cx="100" cy="86" r="5" fill="none" stroke="#ffeb3b" stroke-width="1.6"/><path d="M100 78v16M92 86h16" stroke="#ffeb3b" stroke-width="1"/><g transform="translate(100 22)" fill="#cfd8dc"><path d="M-44 -2H44V4H-44z"/><path d="M-3 -16H3V14H-3z"/><path d="M-13 -1H-10V20H-13zM10 -1H13V20H10z"/><path d="M-17 18H17V22H-17z"/><circle cx="0" cy="-14" r="2.4" fill="#37474f"/></g></svg>'
		"op_video": return '<svg viewBox="0 0 200 110" width="200" height="110" xmlns="http://www.w3.org/2000/svg"><path d="M94 100L97 30H103L106 100z" fill="#cfd8dc"/><rect x="95" y="22" width="10" height="9" fill="#ffd54f"/><path d="M93 22H107L100 14z" fill="#b71c1c"/><ellipse cx="100" cy="60" rx="70" ry="22" fill="none" stroke="#ffc83d" stroke-width="2" stroke-dasharray="6 4"/><path d="M168 64l4 -8 4 8" fill="none" stroke="#ffc83d" stroke-width="2"/><circle cx="45" cy="74" r="4" fill="#e53935"/><g transform="translate(45 74) rotate(0) scale(0.8)"><path d="M-8 -8L8 8M8 -8L-8 8" stroke="#fff" stroke-width="2.4"/><g fill="none" stroke="#fff" stroke-width="1.6"><circle cx="-8" cy="-8" r="4.5"/><circle cx="8" cy="-8" r="4.5"/><circle cx="-8" cy="8" r="4.5"/><circle cx="8" cy="8" r="4.5"/></g><rect x="-3" y="-3" width="6" height="6" fill="#9e9e9e"/></g></svg>'
		"fpv_estacionario": return '<svg viewBox="0 0 200 110" width="200" height="110" xmlns="http://www.w3.org/2000/svg"><rect x="91" y="91" width="18" height="10" fill="#2b2b2b" stroke="#ff6d00" stroke-width="1.5"/><path d="M96 93V99M104 93V99M96 96H104" stroke="#fff" stroke-width="1.2"/><g fill="none" stroke="#4fc3f7" stroke-width="1.6"><ellipse cx="100" cy="30" rx="34" ry="8"/><ellipse cx="100" cy="74" rx="34" ry="8"/><path d="M66 30V74M134 30V74"/></g><g transform="translate(100 52) rotate(0)"><path d="M-8 -8L8 8M8 -8L-8 8" stroke="#fff" stroke-width="2.4"/><g fill="none" stroke="#fff" stroke-width="1.6"><circle cx="-8" cy="-8" r="4.5"/><circle cx="8" cy="-8" r="4.5"/><circle cx="-8" cy="8" r="4.5"/><circle cx="8" cy="8" r="4.5"/></g><path d="M0 -4L3 1H-3z" fill="#ffc83d"/></g><path d="M150 80V24" stroke="#ffc83d" stroke-width="1.5"/><path d="M146 28L150 22 154 28M146 76L150 82 154 76" fill="none" stroke="#ffc83d" stroke-width="1.5"/><text x="156" y="56" fill="#fff" font-size="10">20 s</text></svg>'
		"fpv_caja": return '<svg viewBox="0 0 200 110" width="200" height="110" xmlns="http://www.w3.org/2000/svg"><rect x="55" y="25" width="90" height="60" fill="none" stroke="#ffc83d" stroke-width="2" stroke-dasharray="6 4"/><path d="M55 19L60 31H50z" fill="#4caf50" stroke="#000" stroke-width="0.8"/><path d="M55 79L60 91H50z" fill="#ffeb3b" stroke="#000" stroke-width="0.8"/><path d="M145 79L150 91H140z" fill="#f44336" stroke="#000" stroke-width="0.8"/><path d="M145 19L150 31H140z" fill="#42a5f5" stroke="#000" stroke-width="0.8"/><g transform="translate(100 55) rotate(180)"><path d="M-8 -8L8 8M8 -8L-8 8" stroke="#fff" stroke-width="2.4"/><g fill="none" stroke="#fff" stroke-width="1.6"><circle cx="-8" cy="-8" r="4.5"/><circle cx="8" cy="-8" r="4.5"/><circle cx="-8" cy="8" r="4.5"/><circle cx="8" cy="8" r="4.5"/></g><path d="M0 -4L3 1H-3z" fill="#ffc83d"/></g></svg>'
		"fpv_slalom": return '<svg viewBox="0 0 200 110" width="200" height="110" xmlns="http://www.w3.org/2000/svg"><path d="M30 56V80" stroke="#e53935" stroke-width="3"/><path d="M30 56V80" stroke="#fff" stroke-width="3" stroke-dasharray="4 4"/><path d="M52 56V80" stroke="#e53935" stroke-width="3"/><path d="M52 56V80" stroke="#fff" stroke-width="3" stroke-dasharray="4 4"/><path d="M74 56V80" stroke="#e53935" stroke-width="3"/><path d="M74 56V80" stroke="#fff" stroke-width="3" stroke-dasharray="4 4"/><path d="M96 56V80" stroke="#e53935" stroke-width="3"/><path d="M96 56V80" stroke="#fff" stroke-width="3" stroke-dasharray="4 4"/><path d="M118 56V80" stroke="#e53935" stroke-width="3"/><path d="M118 56V80" stroke="#fff" stroke-width="3" stroke-dasharray="4 4"/><path d="M15 66 C25 50 35 50 41 66 S57 82 63 66 S79 50 85 66 S101 82 107 66 S123 50 129 66" fill="none" stroke="#ffc83d" stroke-width="2" stroke-dasharray="5 3"/><path d="M158 26V50" stroke="#f44336" stroke-width="3"/><path d="M158 26V50" stroke="#fff" stroke-width="3" stroke-dasharray="4 4"/><path d="M182 26V50" stroke="#42a5f5" stroke-width="3"/><path d="M182 26V50" stroke="#fff" stroke-width="3" stroke-dasharray="4 4"/><path d="M170 38 C160 18 146 22 150 38 C154 54 186 22 190 38 C194 54 180 58 170 38" fill="none" stroke="#ffc83d" stroke-width="1.8"/><g transform="translate(129 66) rotate(0)"><path d="M-8 -8L8 8M8 -8L-8 8" stroke="#fff" stroke-width="2.4"/><g fill="none" stroke="#fff" stroke-width="1.6"><circle cx="-8" cy="-8" r="4.5"/><circle cx="8" cy="-8" r="4.5"/><circle cx="-8" cy="8" r="4.5"/><circle cx="8" cy="8" r="4.5"/></g><path d="M0 -4L3 1H-3z" fill="#ffc83d"/></g></svg>'
		"fpv_circuito": return '<svg viewBox="0 0 200 110" width="200" height="110" xmlns="http://www.w3.org/2000/svg"><path d="M40 30 C20 55 30 90 70 92 L140 92 C180 90 185 55 165 32 C150 15 60 12 40 30z" fill="none" stroke="#ffc83d" stroke-width="2" stroke-dasharray="6 4"/><path d="M31 40V22H49V40" fill="none" stroke="#ff6d00" stroke-width="2.6"/><text x="37" y="19" fill="#fff" font-size="9" font-weight="700">1</text><path d="M36 88V70H54V88" fill="none" stroke="#ff6d00" stroke-width="2.6"/><text x="42" y="67" fill="#fff" font-size="9" font-weight="700">2</text><path d="M96 100V82H114V100" fill="none" stroke="#ff6d00" stroke-width="2.6"/><text x="102" y="79" fill="#fff" font-size="9" font-weight="700">3</text><path d="M156 88V70H174V88" fill="none" stroke="#ff6d00" stroke-width="2.6"/><text x="162" y="67" fill="#fff" font-size="9" font-weight="700">4</text><path d="M163 45V27H181V45" fill="none" stroke="#ff6d00" stroke-width="2.6"/><text x="169" y="24" fill="#fff" font-size="9" font-weight="700">5</text><path d="M96 26V8H114V26" fill="none" stroke="#ff6d00" stroke-width="2.6"/><text x="102" y="5" fill="#fff" font-size="9" font-weight="700">6</text><g transform="translate(75 25) rotate(-100)"><path d="M-8 -8L8 8M8 -8L-8 8" stroke="#fff" stroke-width="2.4"/><g fill="none" stroke="#fff" stroke-width="1.6"><circle cx="-8" cy="-8" r="4.5"/><circle cx="8" cy="-8" r="4.5"/><circle cx="-8" cy="8" r="4.5"/><circle cx="8" cy="8" r="4.5"/></g><path d="M0 -4L3 1H-3z" fill="#ffc83d"/></g></svg>'
		"fpv_acro": return '<svg viewBox="0 0 200 110" width="200" height="110" xmlns="http://www.w3.org/2000/svg"><rect x="20" y="70" width="160" height="14" fill="#8d6e63" rx="2"/><path d="M15 55 H185" stroke="#ffc83d" stroke-width="2" stroke-dasharray="6 4"/><path d="M178 51l7 4-7 4" fill="#ffc83d"/><g transform="translate(90 55) rotate(0)"><path d="M-8 -8L8 8M8 -8L-8 8" stroke="#fff" stroke-width="2.4"/><g fill="none" stroke="#fff" stroke-width="1.6"><circle cx="-8" cy="-8" r="4.5"/><circle cx="8" cy="-8" r="4.5"/><circle cx="-8" cy="8" r="4.5"/><circle cx="8" cy="8" r="4.5"/></g><path d="M0 -4L3 1H-3z" fill="#ffc83d"/></g><path d="M90 55 L118 40" stroke="#4fc3f7" stroke-width="1.5"/><text x="122" y="40" fill="#4fc3f7" font-size="10" font-weight="700">ACRO</text><path d="M20 84L25 96H15z" fill="#ff6d00" stroke="#000" stroke-width="0.8"/><path d="M180 84L185 96H175z" fill="#ff6d00" stroke="#000" stroke-width="0.8"/></svg>'
		"fpv_tecnica": return '<svg viewBox="0 0 200 110" width="200" height="110" xmlns="http://www.w3.org/2000/svg"><path d="M58 100V38H86V100" fill="none" stroke="#d81b60" stroke-width="3"/><path d="M58 70H86" stroke="#d81b60" stroke-width="3"/><path d="M30 56 H72 C112 56 112 12 72 12 C40 12 40 56 72 56" fill="none" stroke="#ffc83d" stroke-width="2" stroke-dasharray="5 3"/><g stroke="#b8bcc0" stroke-width="2"><path d="M150 100V20M168 100V20"/><path d="M150 40H168M150 60H168M150 80H168M150 20H168"/></g><circle cx="159" cy="15" r="3.5" fill="#ff1744"/><path d="M176 22 C186 50 184 80 178 98" fill="none" stroke="#ffc83d" stroke-width="2" stroke-dasharray="5 3"/><path d="M174 92l4 7 4-7" fill="none" stroke="#ffc83d" stroke-width="2"/><g transform="translate(30 56) rotate(90)"><path d="M-8 -8L8 8M8 -8L-8 8" stroke="#fff" stroke-width="2.4"/><g fill="none" stroke="#fff" stroke-width="1.6"><circle cx="-8" cy="-8" r="4.5"/><circle cx="8" cy="-8" r="4.5"/><circle cx="-8" cy="8" r="4.5"/><circle cx="8" cy="8" r="4.5"/></g><path d="M0 -4L3 1H-3z" fill="#ffc83d"/></g></svg>'
		"campo": return ini + pista.call(96, 25, 8, 55) + pil.call(70, 30, P[0]) + pil.call(130, 30, P[1]) + pil.call(130, 75, P[2]) + pil.call(70, 75, P[3]) + \
			'<circle cx="100" cy="95" r="4" fill="#fff"/><text x="108" y="98" fill="#fff" font-size="9">piloto</text>' + avion.call(150, 50, -30) + fin
	return ini + avion.call(100, 55, 0) + fin

## Imagen de una tarjeta: fondo degradado azul (#1d3a56 -> #0f2235) con el icono encima.
static func imagen(id: String, alto: float) -> Control:
	var c := Control.new(); c.custom_minimum_size.y = alto; c.clip_contents = true
	var g := Gradient.new(); g.colors = PackedColorArray([Color("#1d3a56"), Color("#0f2235")]); g.offsets = PackedFloat32Array([0, 1])
	var gt := GradientTexture2D.new(); gt.gradient = g; gt.fill_from = Vector2(0.5, 0); gt.fill_to = Vector2(0.5, 1)
	var f := TextureRect.new(); f.texture = gt; f.set_anchors_preset(Control.PRESET_FULL_RECT); f.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; f.stretch_mode = TextureRect.STRETCH_SCALE
	c.add_child(f)
	var ic := TextureRect.new(); ic.texture = Tema.svg(icono(id), 2.0); ic.set_anchors_preset(Control.PRESET_FULL_RECT)
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED; c.add_child(ic)
	# el lector de SVG de Godot no dibuja <text>: los textos ("piloto", "final", "2–8 m", 1 2 3) se pintan encima, con la
	# misma escala y centrado que el dibujo (viewBox 0 0 200 110)
	var textos := textos_svg(icono(id))
	if not textos.is_empty():
		var tx := Control.new(); tx.set_anchors_preset(Control.PRESET_FULL_RECT); tx.mouse_filter = Control.MOUSE_FILTER_IGNORE; c.add_child(tx)
		tx.draw.connect(func():
			var k := minf(tx.size.x / 200.0, tx.size.y / 110.0); var o := (tx.size - Vector2(200, 110) * k) / 2
			for t in textos:
				tx.draw_string(Tema.negrita if t["negrita"] else Tema.fuente, o + t["pos"] * k, t["texto"], HORIZONTAL_ALIGNMENT_LEFT, -1, int(round(t["tam"] * k)), t["color"]))
	return c

## Textos de un SVG: [{ pos (x, y de la linea base), texto, tam, color, negrita }], con lo que heredan de su <g>.
static func textos_svg(svg: String) -> Array:
	var re := RegEx.new(); re.compile("<g ([^>]*)>|</g>|<text ([^>]*)>([^<]*)</text>")
	var at := RegEx.new(); at.compile("([a-z-]+)=\"([^\"]*)\"")
	var pila := [{}]; var out := []
	for m in re.search_all(svg):
		var s := m.get_string()
		if s.begins_with("</g"): pila.pop_back(); continue
		var d: Dictionary = (pila[-1] as Dictionary).duplicate()
		for a in at.search_all(m.get_string(1) if s.begins_with("<g") else m.get_string(2)): d[a.get_string(1)] = a.get_string(2)
		if s.begins_with("<g"): pila.append(d); continue
		out.append({ "pos": Vector2(float(d.get("x", "0")), float(d.get("y", "0"))), "texto": m.get_string(3), "tam": float(d.get("font-size", "10")),
					 "color": Color(d.get("fill", "#ffffff")), "negrita": d.get("font-weight", "") == "700" })
	return out


## Panel de condiciones (viento): velocidad, de donde viene y rachas. Uno solo, que se mueve a la pantalla que lo usa.
class Condiciones extends PanelContainer:
	var p: Node
	var s_vel: HSlider; var t_vel: Label; var o_dir: OptionButton; var c_rachas: CheckBox; var nota: Label
	const DIRS := [0, 45, 90, 135, 180, 225, 270, 315]
	func _init(p_: Node) -> void:
		p = p_; theme_type_variation = "Capa"
		var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 8); add_child(v)
		v.add_child(Tema.h2("Condiciones"))
		s_vel = Tema.deslizador(0, 10, 0.5, 2); t_vel = Tema.etiqueta("2 m/s", 14, Tema.TEXTO, true)
		var f := HBoxContainer.new(); f.add_theme_constant_override("separation", 10); f.size_flags_horizontal = Control.SIZE_EXPAND_FILL; f.add_child(s_vel); f.add_child(t_vel)
		v.add_child(Tema.fila("Viento", f, 110))
		o_dir = Tema.desplegable(["norte (de cara al piloto)", "nordeste", "este (cruzado)", "sudeste", "sur (de cola en la pista)", "sudoeste", "oeste (cruzado)", "noroeste"])
		v.add_child(Tema.fila("Viene del", o_dir, 110))
		c_rachas = Tema.casilla("y turbulencia", true); v.add_child(Tema.fila("Rachas", c_rachas, 110))
		nota = Tema.sub("", 13); v.add_child(nota)
		s_vel.value_changed.connect(func(_x): leer()); o_dir.item_selected.connect(func(_i): leer()); c_rachas.toggled.connect(func(_b): leer())
	var _montando := false
	func montar(E) -> void:
		_montando = true
		var fijo: bool = E != null and (E as Dictionary).has("viento")
		var vv: Dictionary = E["viento"] if fijo else p.sesion["viento"]
		s_vel.value = vv["vel"]; o_dir.selected = maxi(0, DIRS.find(int(vv["desde"]))); c_rachas.button_pressed = vv["rachas"]
		t_vel.text = _vel(vv["vel"])
		s_vel.editable = not fijo; o_dir.disabled = fijo; c_rachas.disabled = fijo
		nota.text = "Este entrenamiento fija su propio viento." if fijo else ("Para empezar, menos de 3 m/s. Física %s (se cambia en Ajustes)." % ("fácil" if p.sesion["dificultad"] == "facil" else "real"))
		_montando = false
	static func _vel(x: float) -> String: return (str(int(x)) if x == int(x) else ("%.1f" % x)) + " m/s"
	func leer() -> void:
		if _montando or not s_vel.editable: return
		p.sesion["viento"] = { "vel": s_vel.value, "desde": DIRS[o_dir.selected], "rachas": c_rachas.button_pressed }
		t_vel.text = _vel(s_vel.value); p.guardar_sesion()
	func mover_a(destino: Control) -> void:
		if get_parent() != destino:
			if get_parent(): get_parent().remove_child(self)
			destino.add_child(self); destino.move_child(self, 0)


## Entrenamientos: tarjetas por grupo a la izquierda; ficha, condiciones y Volar a la derecha.
class Entrenamientos extends Control:
	var p: Node; var d: Dictionary
	var lista: VBoxContainer; var ficha_rt: RichTextLabel; var hueco: VBoxContainer
	var sel := "primer_vuelo"
	var b_volar: Button
	func _init(p_: Node) -> void:
		p = p_; set_anchors_preset(Control.PRESET_FULL_RECT)
		d = Tema.pantalla("Entrenamientos", " "); add_child(d["raiz"])
		d["botones"].add_child(Tema.boton("← Inicio", "", func(): p.ir_inicio()))
		var dos := HBoxContainer.new(); dos.add_theme_constant_override("separation", 16); d["cuerpo"].add_child(dos)
		lista = VBoxContainer.new(); lista.add_theme_constant_override("separation", 10)
		var sc := Tema.desplazable(lista); dos.add_child(sc)
		var der := VBoxContainer.new(); der.custom_minimum_size.x = 380; der.add_theme_constant_override("separation", 12)
		var sd := Tema.desplazable(der); sd.size_flags_horizontal = Control.SIZE_FILL; dos.add_child(sd)       # .dos: 1fr 380px
		var cf := Tema.capa(6); der.add_child(cf[0])
		ficha_rt = Tema.rico("", 14); (cf[1] as VBoxContainer).add_child(ficha_rt)
		hueco = VBoxContainer.new(); der.add_child(hueco)
		var bv := Tema.boton("Volar →", "BotonPrimGrande", func(): p.sesion["escenario"] = sel; p.guardar_sesion(); p.empezar())
		bv.size_flags_horizontal = Control.SIZE_FILL; der.add_child(bv); b_volar = bv
	func refrescar() -> void:
		var E := Escenarios.datos(); var al = p.sesion["alumno"]
		var g = al["progreso"] if al != null and al.has("progreso") else null
		var veh := Escenarios.vehiculo_de(p.sesion["avion"]); var ids := Escenarios.misiones_de(veh)
		d["subtitulo"].text = String(DatosComunes.avion(p.sesion["avion"]).get("nombre", "")) + " · %d entrenamientos" % ids.size() + 			((" · %d/%d pruebas del certificado superadas" % [int(g["escenarios_superados"]), int(g.get("escenarios_total", (g["escenarios"] as Dictionary).size()))]) if g != null else " · sin registro")
		for x in lista.get_children(): x.queue_free()
		b_volar.disabled = ids.is_empty()
		if ids.is_empty():                 # el bipode no tiene entrenamientos: es para el vuelo libre
			lista.add_child(Tema.sub("Este vehículo no tiene entrenamientos: llévalo al vuelo libre.", 14)); ficha_rt.text = ""; return
		if not sel in ids: sel = ids[0]
		var rejilla: GridAdaptable = null
		for id in ids:
			var M: Dictionary = E[id]
			if M.has("titulo_grupo") or rejilla == null:
				if M.has("titulo_grupo"):
					var t := Tema.etiqueta(String(M["titulo_grupo"]).to_upper(), 13, Tema.SUAVE, true)
					var fv := FontVariation.new(); fv.base_font = Tema.negrita; fv.spacing_glyph = 1; t.add_theme_font_override("font", fv)
					lista.add_child(Tema.margen(t, 0, 10 if lista.get_child_count() else 0, 0, 2))
				rejilla = Tema.rejilla(230, 12); lista.add_child(rejilla)
			var st = g["escenarios"].get(id) if g != null else null
			rejilla.add_child(_tarjeta(id, M, st))
		var M: Dictionary = E[sel]
		var bb := "[font_size=20][b]%s[/b][/font_size]\n[color=#9fb3c8]%s[/color]\n" % [M["nombre"], M["desc"]]
		if M.has("sentido"): bb += "Orden de los pilones: %s\n" % Escenarios.orden_bb(p.ent_campo(), int(M["sentido"]))
		bb += "\n[font_size=12][color=#9fb3c8][b]OBJETIVOS[/b][/color][/font_size]\n"
		for o in M["objetivos"]: bb += "  •  %s\n" % o[1]
		ficha_rt.text = bb
		p.condiciones.mover_a(hueco); p.condiciones.montar(M)
	func _tarjeta(id: String, M: Dictionary, st) -> Tarjeta:
		var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 0)
		v.add_child(PantallaMisiones.imagen(id, 110))
		var tx := VBoxContainer.new(); tx.add_theme_constant_override("separation", 4)
		var h := HBoxContainer.new(); h.add_theme_constant_override("separation", 6)
		h.add_child(Tema.etiqueta(String(M["nombre"]).substr(4) if String(M["nombre"]).substr(1, 3) == " · " else String(M["nombre"]), 15, Tema.TEXTO, true))
		if st != null and st["superado"]: h.add_child(Tema.etiqueta("✓", 15, Tema.OK, true))
		tx.add_child(h)
		var dsc := Tema.etiqueta(String(M["desc"]), 12, Tema.SUAVE, false, true); dsc.max_lines_visible = 2; dsc.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		tx.add_child(dsc)
		var dif := int(M.get("dificultad", 1))
		var meta := "[color=#ffc83d]%s%s[/color]" % ["★".repeat(dif), "☆".repeat(3 - dif)]
		if st != null and int(st["intentos"]) > 0: meta += "[color=#9fb3c8] · %d intento%s[/color]" % [int(st["intentos"]), "s" if int(st["intentos"]) > 1 else ""]
		tx.add_child(Tema.rico(meta, 12))
		v.add_child(Tema.margen(tx, 12, 10, 12, 12))
		var t := Tarjeta.new(v, 14, Vector2(0, 0)); t.elegida = id == sel
		t.pulsada.connect(func(): sel = id; refrescar())
		return t


## Operaciones: los trabajos (escenarios.js, "operacion") en una fila de tarjetas por vehiculo; a la derecha la orden de
## trabajo y Volar, que abre la ventana de las comprobaciones antes del vuelo (hay que marcarlas todas cada vez para
## despegar) (#pOperaciones y #checkOp de la web).
const COMPROBACIONES_OP := ["Operador registrado en AESA y piloto con el certificado que pide el dron (A1/A3 o A2)", "Zona consultada en el mapa de ENAIRE Drones: no es zona prohibida ni restringida",
	"Viento previsto por debajo de 8 m/s", "Baterías del dron y del mando cargadas; hélices sin daños", "Permiso del cliente y del propietario del terreno",
	"Zona de despegue despejada y nadie debajo del vuelo"]
const COMPROBACIONES_UAV := ["NOTAM publicado y vuelo coordinado con la torre de San Javier (espacio aéreo controlado)", "Tripulación de la estación de control con la habilitación del UAS",
	"Combustible y aceite comprobados; hélice, tren y frenos sin daños", "Enlace de datos, GPS y estación de control probados; vuelta a base programada",
	"Viento en pista dentro de los límites del avión", "Pista libre y autorización de despegue de la torre"]     # UAV de pista (espacio aereo controlado)
const RUMBOS_VIENTO := ["norte", "nordeste", "este", "sudeste", "sur", "sudoeste", "oeste", "noroeste"]
class Operaciones extends Control:
	var p: Node; var d: Dictionary
	var lista: VBoxContainer; var ficha_rt: RichTextLabel; var b_volar: Button; var briefing: TextureRect
	var sel := ""
	var check: Control; var check_sub: Label; var check_lista: VBoxContainer; var check_si: Button; var marcas := []
	func _init(p_: Node) -> void:
		p = p_; set_anchors_preset(Control.PRESET_FULL_RECT)
		d = Tema.pantalla("Operaciones", "Trabajos en el mapa real de Cartagena, en una fila por vehículo: cada trabajo se vuela con el suyo"); add_child(d["raiz"])
		d["botones"].add_child(Tema.boton("← Inicio", "", func(): p.ir_inicio()))
		var dos := HBoxContainer.new(); dos.add_theme_constant_override("separation", 16); d["cuerpo"].add_child(dos)
		lista = VBoxContainer.new(); lista.add_theme_constant_override("separation", 10)
		var sc := Tema.desplazable(lista); dos.add_child(sc)
		var der := VBoxContainer.new(); der.custom_minimum_size.x = 380; der.add_theme_constant_override("separation", 12)
		var sd := Tema.desplazable(der); sd.size_flags_horizontal = Control.SIZE_FILL; dos.add_child(sd)
		var cf := Tema.capa(6); der.add_child(cf[0])
		briefing = TextureRect.new(); briefing.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; briefing.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED; briefing.custom_minimum_size = Vector2(0, 228)
		(cf[1] as VBoxContainer).add_child(briefing)                       # el mapa del briefing (simulador/operaciones/<id>.jpg)
		ficha_rt = Tema.rico("", 14); (cf[1] as VBoxContainer).add_child(ficha_rt)
		b_volar = Tema.boton("Volar →", "BotonPrimGrande", func(): pedir_comprobaciones())
		b_volar.size_flags_horizontal = Control.SIZE_FILL; der.add_child(b_volar)
		# la ventana de las comprobaciones (#checkOp)
		check = Capas._velo(); add_child(check)
		var cp := Tema.capa(8); var panel: PanelContainer = cp[0]; var caja: VBoxContainer = cp[1]
		panel.custom_minimum_size.x = 520; check.get_node("Centro").add_child(panel)
		caja.add_child(Tema.etiqueta("Antes de volar", 18, Tema.TEXTO, true))
		check_sub = Tema.etiqueta("", 14, Tema.SUAVE); caja.add_child(check_sub)
		check_lista = VBoxContainer.new(); check_lista.add_theme_constant_override("separation", 6); caja.add_child(check_lista)
		var bb := HBoxContainer.new(); bb.add_theme_constant_override("separation", 10); bb.alignment = BoxContainer.ALIGNMENT_END
		bb.add_child(Tema.boton("Cancelar", "", func(): check.visible = false))
		check_si = Tema.boton("Despegar →", "BotonPrim", _despegar)
		bb.add_child(check_si); caja.add_child(Tema.margen(bb, 0, 8, 0, 0))
	func refrescar() -> void:
		var E := Escenarios.datos(); var ids := Escenarios.operaciones()
		if not sel in ids: sel = ids[0]
		for x in lista.get_children(): x.queue_free()
		var filas := {}                                                 # una fila por vehiculo, en el orden en que salen
		var cuenta := {}
		for id in ids: var a0 := String(E[id]["operacion"].get("avion", "")); cuenta[a0] = int(cuenta.get(a0, 0)) + 1
		var n_max: int = cuenta.values().max()                          # todas las filas con el ancho de la mas larga
		for id in ids:
			var av := String(E[id]["operacion"].get("avion", ""))
			if not filas.has(av):
				var Dv: Dictionary = DatosComunes.avion(av) if p.ids_aviones.has(av) else {}
				var t := Tema.rico("[b]%s[/b]%s" % [String(Dv.get("nombre", av)).to_upper(), ("   [color=#9fb3c8]%s[/color]" % Dv["categoria"]) if Dv.has("categoria") else ""], 13)
				t.add_theme_color_override("default_color", Tema.SUAVE)
				lista.add_child(Tema.margen(t, 0, 10 if lista.get_child_count() else 0, 0, 2))
				var fila := HBoxContainer.new(); fila.add_theme_constant_override("separation", 12)
				var sf := ScrollContainer.new(); sf.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; sf.add_child(fila)
				fila.size_flags_horizontal = Control.SIZE_EXPAND_FILL; lista.add_child(sf); filas[av] = fila
			var tj := _tarjeta(id, E[id]); tj.custom_minimum_size.x = 180; tj.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			(filas[av] as HBoxContainer).add_child(tj)
		for av in filas:                                                # huecos hasta n_max tarjetas
			for k in n_max - (filas[av] as HBoxContainer).get_child_count():
				var h := Control.new(); h.custom_minimum_size.x = 180; h.size_flags_horizontal = Control.SIZE_EXPAND_FILL; h.mouse_filter = Control.MOUSE_FILTER_IGNORE
				(filas[av] as HBoxContainer).add_child(h)
		var M: Dictionary = E[sel]; var O: Dictionary = M["operacion"]; var v: Dictionary = M["viento"]
		var fila := func(a: String, b: String) -> String: return "[cell][color=#9fb3c8]%s[/color]   [/cell][cell]%s[/cell]" % [a, b]
		var bb := "[font_size=15][color=#ffc83d][b]ORDEN DE TRABAJO[/b][/color][/font_size]\n[font_size=18][b]%s[/b][/font_size]\n[font_size=13][table=2]" % M["nombre"]
		bb += fila.call("Cliente", O["cliente"]) + fila.call("Lugar", O["lugar"]) + fila.call("Trabajo", O["trabajo"]) + fila.call("Entrega", O["entrega"])
		bb += fila.call("Viento previsto", "%s m/s del %s%s" % [PasadaBaja._num(v["vel"]), RUMBOS_VIENTO[int(round(v["desde"] / 45.0)) % 8], ", con rachas" if v["rachas"] else ""])
		var Dd: Dictionary = DatosComunes.avion(String(O["avion"])) if p.ids_aviones.has(String(O.get("avion", ""))) else {}
		bb += fila.call("Dron", ("%s (%s)" % [Dd["nombre"], Dd.get("categoria", "")]) if not Dd.is_empty() else String(O.get("avion", ""))) + "[/table][/font_size]\n\n[font_size=12][color=#9fb3c8][b]SE EVALÚA[/b][/color][/font_size]\n"
		for o in M["objetivos"]: bb += "  •  %s\n" % o[1]
		ficha_rt.text = bb
		var img := Image.load_from_file(DatosComunes.carpeta().path_join("operaciones/%s.jpg" % sel)) if FileAccess.file_exists(DatosComunes.carpeta().path_join("operaciones/%s.jpg" % sel)) else null
		briefing.texture = ImageTexture.create_from_image(img) if img != null else null
	## Las comprobaciones antes de volar del trabajo id (las del UAV de pista o las del dron).
	static func comprobaciones_de(id: String) -> Array:
		return COMPROBACIONES_UAV if Escenarios.vehiculo_de(String(Escenarios.datos()[id]["operacion"].get("avion", ""))) == "uav" else COMPROBACIONES_OP
	## Volar: la ventana de las comprobaciones, todas sin marcar; Despegar solo cuando estan todas.
	func pedir_comprobaciones() -> void:
		var L := comprobaciones_de(sel); marcas = []
		for x in check_lista.get_children(): x.queue_free()
		for i in L.size():
			marcas.append(false)
			var cb := CheckBox.new(); cb.text = L[i]; cb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; cb.custom_minimum_size.x = 480
			cb.add_theme_font_size_override("font_size", 14); cb.focus_mode = Control.FOCUS_NONE
			cb.toggled.connect(func(si: bool): marcas[i] = si; _boton())
			check_lista.add_child(cb)
		check_sub.text = String(Escenarios.datos()[sel]["nombre"]); _boton(); check.visible = true
	func _despegar() -> void:
		if not marcas.all(func(x): return x): return
		check.visible = false; p.volar_operacion(sel)
	func _boton() -> void:
		var ok: bool = marcas.all(func(x): return x); var n := marcas.filter(func(x): return x).size()
		check_si.disabled = not ok; check_si.text = "Despegar →" if ok else "Marca todas las comprobaciones (%d/%d)" % [n, marcas.size()]
	func _tarjeta(id: String, M: Dictionary) -> Tarjeta:
		var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 0)
		v.add_child(PantallaMisiones.imagen(id, 110))
		var tx := VBoxContainer.new(); tx.add_theme_constant_override("separation", 4)
		tx.add_child(Tema.etiqueta(String(M["nombre"]), 15, Tema.TEXTO, true, true))          # el titulo se parte, como en la web
		var dsc := Tema.etiqueta(String(M["desc"]), 12, Tema.SUAVE, false, true); dsc.max_lines_visible = 2; dsc.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		tx.add_child(dsc)
		var dif := int(M.get("dificultad", 1))
		var av_op := String(M["operacion"].get("avion", ""))
		var nom_dron: String = ("   [color=#9fb3c8]%s[/color]" % DatosComunes.avion(av_op)["nombre"]) if p.ids_aviones.has(av_op) else ""
		tx.add_child(Tema.rico("[color=#ffc83d]%s%s[/color]%s" % ["★".repeat(dif), "☆".repeat(3 - dif), nom_dron], 12))
		v.add_child(Tema.margen(tx, 12, 10, 12, 12))
		var t := Tarjeta.new(v, 14, Vector2(0, 0)); t.elegida = id == sel
		t.pulsada.connect(func(): sel = id; refrescar())
		return t


## Multijugador (#pMulti de la web): las salas abiertas del servidor del aula a la izquierda (se refrescan cada 2 s) y, a la
## derecha, crear una sala (nombre y que se vuela) o el aviso de que hace falta el aula.
class Multijugador extends Control:
	var p: Node; var d: Dictionary
	var lista: VBoxContainer; var vacio: Label; var crear: PanelContainer; var sin_aula: PanelContainer
	var reloj: Timer
	func _init(p_: Node) -> void:
		p = p_; set_anchors_preset(Control.PRESET_FULL_RECT)
		d = Tema.pantalla("Multijugador", "Vuela con tus compañeros en la misma sala: cada uno con su avión, os veis unos a otros"); add_child(d["raiz"])
		d["botones"].add_child(Tema.boton("← Inicio", "", func(): p.ir_inicio()))
		var dos := HBoxContainer.new(); dos.add_theme_constant_override("separation", 16); d["cuerpo"].add_child(dos)
		lista = VBoxContainer.new(); lista.add_theme_constant_override("separation", 10)
		var sc := Tema.desplazable(lista); dos.add_child(sc)
		var der := VBoxContainer.new(); der.custom_minimum_size.x = 380; der.add_theme_constant_override("separation", 12); dos.add_child(der)
		var c := Tema.capa(8); crear = c[0]; der.add_child(crear)      # las salas las crea el profesor (#multiCrear de la web)
		c[1].add_child(Tema.h2("¿Y crear una sala?")); c[1].add_child(Tema.etiqueta("Las salas las crea el profesor en su panel del aula, con lo que se vuela, el punto de salida y el viento. Entra en la de tu clase: verás a tus compañeros y el profesor te verá a ti.", 14, Tema.TEXTO, false, true))
		var c2 := Tema.capa(8); sin_aula = c2[0]; der.add_child(sin_aula)
		c2[1].add_child(Tema.h2("Hace falta el aula"))
		var t := Tema.etiqueta("El multijugador va por el servidor del aula (el PC del profesor): entra en el aula con tu usuario y tu contraseña (Perfil › Cerrar sesión, o al abrir el simulador).", 14, Tema.TEXTO, false, true)
		c2[1].add_child(t)
		reloj = Timer.new(); reloj.wait_time = 2.0; add_child(reloj); reloj.timeout.connect(func(): if visible: _salas())
	## Pedir entrar en una sala (pedirSala de la web): con su clave, si la tiene; el servidor mira tambien las expulsiones.
	func _pedir_sala(sala: Dictionary) -> void:
		var clave := ""
		if sala.get("con_clave", false):
			var c = await p.pedir_clave("Sala " + String(sala["nombre"]), "Esta sala tiene clave: te la dice el profesor.", false)
			if c == null: return
			clave = c[0]
		var al = p.sesion["alumno"]
		var r: Dictionary = await p.aula.api("POST", "salas/%s/entrar" % String(sala["codigo"]).uri_encode(), { "id": p.multi_id(), "clave": clave, "nombre": p.nombre_piloto(), "alumno": al["id"] if al != null else null })
		if r["ok"]: p.entrar_sala(sala)
		else: await p.confirmar("No puedes entrar", Tema.bb(String(r["error"])), "Vale")
	func refrescar() -> void:
		var ok: bool = p.multi_posible(); crear.visible = ok; sin_aula.visible = not ok
		_salas(); reloj.start()
	func _salas() -> void:
		if not p.multi_posible():
			for x in lista.get_children(): x.queue_free()
			return
		var r: Dictionary = await p.aula.api("GET", "salas")
		for x in lista.get_children(): x.queue_free()
		lista.add_child(Tema.etiqueta("SALAS ABIERTAS", 13, Tema.SUAVE, true))
		if not r["ok"]: lista.add_child(Tema.sub("No se puede hablar con el servidor del aula.", 14)); return
		if not (r["datos"] is Array): lista.add_child(Tema.sub("No se puede hablar con el servidor del aula.", 14)); return
		var salas: Array = (r["datos"] as Array).filter(func(s): return s is Dictionary and s.get("codigo") != null and s.get("escenario") is String)
		if salas.is_empty(): lista.add_child(Tema.sub("No hay ninguna sala abierta: espera a que el profesor cree la de tu clase.", 14)); return
		var rej := Tema.rejilla(230, 12); lista.add_child(rej)
		for s in salas:
			var E: Dictionary = Escenarios.datos().get(s["escenario"], { "nombre": s["escenario"] })
			var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 0)
			v.add_child(PantallaMisiones.imagen(String(s["escenario"]), 110))
			var tx := VBoxContainer.new(); tx.add_theme_constant_override("separation", 4)
			tx.add_child(Tema.rico("[b]%s[/b] [color=#9fb3c8]· %s[/color]%s" % [Tema.bb(String(s.get("nombre", ""))), Tema.bb(String(s["codigo"])), " 🔒" if s.get("con_clave", false) else ""], 15))
			tx.add_child(Tema.etiqueta(String(E["nombre"]), 12, Tema.SUAVE, false, true))
			var nombres := []
			for j in (s.get("jugadores", []) if s.get("jugadores") is Array else []):
				if j is Dictionary and j.get("nombre") is String: nombres.append(String(j["nombre"]))
			tx.add_child(Tema.etiqueta(", ".join(nombres) if not nombres.is_empty() else "nadie todavía", 12, Tema.SUAVE, false, true))
			v.add_child(Tema.margen(tx, 12, 10, 12, 12))
			var t := Tarjeta.new(v, 14, Vector2(0, 0)); var sala: Dictionary = s
			t.pulsada.connect(func(): _pedir_sala(sala))
			rej.add_child(t)


## Vuelo libre: los dos sitios (campo del club y Campo de Cartagena), la nota, condiciones y Volar.
class Volar extends Control:
	var p: Node; var d: Dictionary
	var t_campo: Tarjeta; var t_cartagena: Tarjeta; var nota: Label; var hueco: VBoxContainer; var b_volar: Button
	func _init(p_: Node) -> void:
		p = p_; set_anchors_preset(Control.PRESET_FULL_RECT)
		d = Tema.pantalla("Vuelo libre", "Sin objetivos: cuenta como horas de entrenamiento."); add_child(d["raiz"])
		d["botones"].add_child(Tema.boton("← Inicio", "", func(): p.ir_inicio()))
		var dos := HBoxContainer.new(); dos.add_theme_constant_override("separation", 16); d["cuerpo"].add_child(dos)
		var izq := VBoxContainer.new(); izq.size_flags_horizontal = Control.SIZE_EXPAND_FILL; izq.add_theme_constant_override("separation", 14); dos.add_child(izq)
		var sitios := HBoxContainer.new(); sitios.add_theme_constant_override("separation", 12); izq.add_child(sitios)
		t_campo = _sitio(PantallaMisiones.imagen("campo", 160), "Campo de vuelo", "El campo del club: pista, circuito de pilones, zona de precisión detrás del piloto y límite de alcance de 400 m. Se cronometra cada vuelta.")
		var foto := TextureRect.new(); foto.custom_minimum_size.y = 160; foto.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; foto.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED; foto.clip_contents = true
		if p.orto.size() > 1: foto.texture = p.orto[1]
		t_cartagena = _sitio(foto, "Campo de Cartagena · mapa real", "78 × 38 km reales: Cartagena, el Mar Menor, La Manga, la sierra y los pueblos. Eliges el punto de lanzamiento en el mapa. Sin límite de alcance.")
		for t in [t_campo, t_cartagena]: t.size_flags_horizontal = Control.SIZE_EXPAND_FILL; sitios.add_child(t)
		t_campo.pulsada.connect(func(): p.sitio_sel = "libre"; refrescar()); t_cartagena.pulsada.connect(func(): p.sitio_sel = "libre_cartagena"; refrescar())
		nota = Tema.sub("", 13); izq.add_child(nota)
		var der := VBoxContainer.new(); der.custom_minimum_size.x = 380; der.add_theme_constant_override("separation", 12); dos.add_child(der)
		hueco = VBoxContainer.new(); der.add_child(hueco)
		b_volar = Tema.boton("Volar →", "BotonPrimGrande", func():
			p.sesion["escenario"] = p.sitio_sel; p.guardar_sesion()
			if p.sitio_sel == "libre_cartagena": p.ir_lanzamiento()
			else: p.empezar())
		der.add_child(b_volar)
	func _sitio(img: Control, titulo: String, texto: String) -> Tarjeta:
		var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 0)
		var marco := Control.new(); marco.custom_minimum_size.y = 160; marco.clip_contents = true; img.set_anchors_preset(Control.PRESET_FULL_RECT); marco.add_child(img); v.add_child(marco)
		var tx := VBoxContainer.new(); tx.add_theme_constant_override("separation", 4)
		tx.add_child(Tema.etiqueta(titulo, 17, Tema.TEXTO, true)); tx.add_child(Tema.etiqueta(texto, 13, Tema.SUAVE, false, true))
		v.add_child(Tema.margen(tx, 14, 12, 14, 12))
		return Tarjeta.new(v, 14, Vector2(0, 0))
	func refrescar() -> void:
		t_campo.elegida = p.sitio_sel == "libre"; t_cartagena.elegida = p.sitio_sel == "libre_cartagena"
		nota.text = "Lanzas desde el aparcamiento, de cara al norte; la pista va hacia delante. En vuelo, + y − cambian el viento y G las rachas." if p.sitio_sel == "libre" \
			else "El siguiente paso es el mapa: eliges dónde lanzar y se despega hacia el lado más despejado. En la zona de detalle hay ortofoto a 0,5 m, edificios y árboles reales."
		b_volar.text = "Volar →" if p.sitio_sel == "libre" else "Elegir el punto de lanzamiento →"
		p.condiciones.mover_a(hueco); p.condiciones.montar(null)
