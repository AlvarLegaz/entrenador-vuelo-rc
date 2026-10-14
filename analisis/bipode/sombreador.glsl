// Sombreado comun del bipode (web: MeshStandardMaterial con onBeforeCompile; Godot: shader spatial). Mismo texto en los
// dos: p = posicion en la pieza (m, NED), n = normal en la pieza, m = material, k = curvatura (+ canto, - rincon),
// alt = altura sobre el suelo en reposo (0..1 = 0..3,6 m). Colores en lineal.
float bip_hash(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.x + p.y) * p.z);
}
float bip_ruido(vec3 x) {
	vec3 i = floor(x); vec3 f = fract(x); f = f * f * (3.0 - 2.0 * f);
	float a = bip_hash(i); float b = bip_hash(i + vec3(1.0, 0.0, 0.0));
	float c = bip_hash(i + vec3(0.0, 1.0, 0.0)); float d = bip_hash(i + vec3(1.0, 1.0, 0.0));
	float e = bip_hash(i + vec3(0.0, 0.0, 1.0)); float g = bip_hash(i + vec3(1.0, 0.0, 1.0));
	float h = bip_hash(i + vec3(0.0, 1.0, 1.0)); float k = bip_hash(i + vec3(1.0, 1.0, 1.0));
	return mix(mix(mix(a, b, f.x), mix(c, d, f.x), f.y), mix(mix(e, g, f.x), mix(h, k, f.x), f.y), f.z);
}
float bip_fbm(vec3 p) {
	float s = 0.0; float a = 0.5;
	for (int k = 0; k < 4; k++) { s += a * bip_ruido(p); p = p * 2.03 + vec3(1.7, 9.2, 3.1); a *= 0.5; }
	return s;
}
// las calcomanias tambien se desconchan: donde salta la pintura no hay calcomania
float bip_calca_saltada(vec3 p) {
	return step(0.69, bip_fbm(p * 17.0) * 0.7 + bip_ruido(p * 60.0) * 0.3);
}
void bip_superficie(vec3 p, vec3 n, float m, float k, float alt, inout vec3 alb, inout float rug, inout float met, inout vec3 emi) {
	float h = alt * 3.6;
	float vari = bip_fbm(p * 3.1);
	float fino = bip_ruido(p * 47.0);
	bool pintura = m < 0.5 || abs(m - 2.0) < 0.5;
	bool metal = abs(m - 1.0) < 0.5 || abs(m - 5.0) < 0.5 || abs(m - 3.0) < 0.5;
	// churretones: ruido estirado en la vertical de la pieza (z)
	float churre = smoothstep(0.55, 0.85, bip_fbm(vec3(p.x * 6.0, p.y * 6.0, p.z * 0.7)));
	if (pintura) {
		alb *= 0.85 + 0.25 * vari;
		float arriba = clamp(-n.z, 0.0, 1.0);                        // lo que mira al cielo: descolorido por el sol
		alb = mix(alb, vec3(dot(alb, vec3(0.3333))) * 1.12, arriba * 0.18);
		alb *= 1.0 + 0.12 * clamp(k * 2.0, 0.0, 1.0);                 // cantos gastados: mas claros
		float lluvia = smoothstep(0.45, 0.8, bip_ruido(vec3(p.x * 30.0, p.y * 30.0, p.z * 1.5)));
		rug = mix(rug, rug + 0.15, lluvia); alb *= 1.0 - 0.06 * lluvia;  // marcas de lluvia (mate y algo mas oscuro)
		float canto = clamp(k * 1.8 - 0.25, 0.0, 1.0);
		float d = bip_fbm(p * 17.0) * 0.7 + bip_ruido(p * 60.0) * 0.3;
		float desc = smoothstep(0.672, 0.69, d + canto * 0.42);
		float imprim = smoothstep(0.69, 0.71, d + canto * 0.42);
		vec3 imp = vec3(0.115, 0.12, 0.10);
		vec3 met_c = vec3(0.26, 0.25, 0.24) * (0.8 + 0.4 * fino);
		alb = mix(alb, imp, desc); alb = mix(alb, met_c, imprim);
		rug = mix(rug, 0.72, desc); rug = mix(rug, 0.34, imprim); met = mix(met, 0.85, imprim);
		float oxido = smoothstep(0.6, 0.9, bip_fbm(p * 5.0 + 7.0)) * churre;
		alb = mix(alb, vec3(0.20, 0.08, 0.025), oxido * 0.55);
		// capa de mugre irregular (polvo y grasa) que apaga el amarillo a manchas grandes
		float capa = smoothstep(0.35, 0.8, bip_fbm(p * 1.7 + 5.0));
		alb = mix(alb, alb * vec3(0.74, 0.66, 0.52), capa * 0.45); rug = mix(rug, 0.75, capa * 0.4);
		float ar = smoothstep(0.93, 0.97, bip_ruido(vec3(p.x * 90.0 + p.z * 40.0, p.y * 3.0, p.z * 90.0 - p.x * 30.0)));
		alb = mix(alb, met_c * 1.4, ar * 0.6); rug = mix(rug, 0.3, ar * 0.5); met = mix(met, 0.7, ar * 0.5);
	} else if (metal) {
		alb *= 0.75 + 0.45 * vari;
		rug = clamp(rug + (vari - 0.5) * 0.3 + (fino - 0.5) * 0.1, 0.12, 0.95);
		float pul = clamp(k * 2.0, 0.0, 1.0);
		alb = mix(alb, alb * 1.6 + 0.05, pul * 0.5); rug = mix(rug, 0.18, pul * 0.7);
		float oxido = smoothstep(0.55, 0.85, bip_fbm(p * 4.0 + 3.0)) * (1.0 - pul);
		if (abs(m - 3.0) > 0.5) { alb = mix(alb, vec3(0.18, 0.07, 0.025), oxido * 0.4); rug = mix(rug, 0.85, oxido * 0.5); met = mix(met, 0.3, oxido * 0.6); }
		else { alb = mix(alb, vec3(0.10, 0.18, 0.13), oxido * 0.35); }
	} else if (abs(m - 10.0) < 0.5) {
		// metal requemado de los escapes: pavonado azul-violeta abajo y dorado-pardo arriba, con hollin en la boca
		float tq = clamp((h - 2.2) / 1.2, 0.0, 1.0) + (vari - 0.5) * 0.35;
		vec3 c1 = vec3(0.10, 0.09, 0.13); vec3 c2 = vec3(0.17, 0.12, 0.22); vec3 c3 = vec3(0.28, 0.20, 0.08); vec3 c4 = vec3(0.05, 0.04, 0.035);
		alb = tq < 0.33 ? mix(c1, c2, tq / 0.33) : (tq < 0.66 ? mix(c2, c3, (tq - 0.33) / 0.33) : mix(c3, c4, clamp((tq - 0.66) / 0.34, 0.0, 1.0)));
		alb *= 0.8 + 0.4 * fino; rug = clamp(0.35 + vari * 0.35, 0.2, 0.9); met = 0.85;
	} else if (abs(m - 4.0) < 0.5 || abs(m - 9.0) < 0.5) {
		alb *= 0.8 + 0.4 * vari; rug = clamp(rug + (fino - 0.5) * 0.15, 0.4, 1.0);
	}
	// barro de abajo arriba, mugre en los rincones y en los churretones
	float barro = clamp((0.75 - h) * 1.5, 0.0, 1.0) * (0.5 + 0.5 * bip_fbm(p * 2.3 + 11.0));
	float rincon = clamp(-k * 2.5, 0.0, 1.0);
	float mugre = clamp(max(barro, rincon * 0.7) + churre * 0.22, 0.0, 1.0) * (abs(m - 7.0) < 0.5 ? 0.6 : 1.0);
	vec3 col_barro = mix(vec3(0.17, 0.13, 0.09), vec3(0.27, 0.22, 0.15), bip_ruido(p * 13.0));
	alb = mix(alb, col_barro, mugre * 0.8);
	rug = mix(rug, 0.95, mugre * 0.7); met = mix(met, 0.0, mugre);
	if (abs(m - 6.0) < 0.5) emi = vec3(1.0, 0.1, 0.04) * 4.0;
	if (abs(m - 8.0) < 0.5) { alb = vec3(0.02); rug = 1.0; met = 0.0; }
}
