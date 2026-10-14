"use strict";
// =====================================================================
//  VISOR: todo lo que se dibuja con Three.js. El campo (el sitio real: bancales de almendros, la
//  rambla, el cerro, el cortijo y la autopista; la pista y los pilones salen del Entorno), el avion
//  (a partir de la malla de su modelo), las camaras y la vista previa girando de la pantalla de eleccion.
//
//  Mundo Three: x = este, y = arriba, z = sur.  NED (n, e, d) -> (e, -d, -n).
// =====================================================================
function ned2three(p) { return [p[1], -p[2], -p[0]]; }
/** Textura de color de un lienzo, en sRGB (desde Three r152 las texturas de color tienen que decirlo). */
function texSRGB(c) { const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.SRGBColorSpace; return t; }

/** Grupo Three con el avion en ejes cuerpo NED (metros, origen en el CG) y sus partes moviles. */
function construirAvion(datos) {
  if (datos.tipo === "fpv" && window.ModeloFPV && ModeloFPV.construir3D) return ModeloFPV.construir3D(datos);     // dron FPV: su modelo, en aviones/FPV.js
  if (datos.tipo === "cuadricoptero" && window.ModeloDJI && ModeloDJI.construir3D) return ModeloDJI.construir3D(datos);   // DJI: el modelo detallado, en aviones/DJI_MINI.js (el de Godot)
  const grupo = new THREE.Group(), K = datos.malla;
  const geom = m => {
    const g = new THREE.BufferGeometry();
    g.setAttribute("position", new THREE.Float32BufferAttribute(m.v, 3)); g.setIndex(m.i);
    const n = g.toNonIndexed(); n.computeVertexNormals(); return n;
  };
  const mat = c => new THREE.MeshLambertMaterial({ color: c, side: THREE.DoubleSide });
  const col = Object.assign({ fuselaje: 0xf4f4f4, ala: 0xffc107, estab: 0xdddddd, moviles: 0xd32f2f }, datos.colores || {});
  for (const k of ["fuselaje", "ala", "estab"]) if (K[k]) grupo.add(new THREE.Mesh(geom(K[k]), mat(col[k])));
  for (const p of K.piezas || []) grupo.add(new THREE.Mesh(geom(p), mat(p.color)));     // piezas de otro color (franjas, ruedas, motor)
  const pivote = (malla, eje) => {      // superficie movil que gira sobre su bisagra (con su color, si lo trae)
    const p = new THREE.Group(); p.position.set(...eje);
    const mm = new THREE.Mesh(geom(malla), mat(malla.color !== undefined ? malla.color : col.moviles)); mm.position.set(-eje[0], -eje[1], -eje[2]);
    p.add(mm); grupo.add(p); return p;
  };
  const prof = K.prof ? pivote(K.prof, K.bisagra_prof) : new THREE.Group();
  const timon = K.timon ? pivote(K.timon, K.bisagra_timon) : new THREE.Group();
  // alerones (si la malla los trae): cada uno gira sobre su bisagra, cuyo eje lleva el diedro y el calado del ala.
  // Con prof: true es un elevon: ademas del alabeo (signo * da) gira con la profundidad (de)
  const alerones = (K.alerones || []).map(a => {
    const p = pivote(a, a.bisagra); p.eje = new THREE.Vector3(...a.eje).normalize(); p.signo = a.signo; p.prof = !!a.prof; return p;
  });
  const matHelice = () => new THREE.MeshBasicMaterial({ color: 0x333333, transparent: true, opacity: 0.25, side: THREE.DoubleSide });
  let helice;
  if (K.helices) {          // multicoptero: un disco horizontal por rotor (en ejes cuerpo el plano x-y ya es horizontal)
    helice = new THREE.Group();
    for (const hp of K.helices) { const d = new THREE.Mesh(new THREE.CircleGeometry(K.helice_r, 24), matHelice()); d.position.set(...hp); helice.add(d); }
    grupo.add(helice);
  } else {
    helice = new THREE.Mesh(new THREE.CircleGeometry(K.helice_r, 24), matHelice());
    helice.rotation.y = Math.PI / 2; helice.position.set(...K.helice); grupo.add(helice);
    const cono = new THREE.Mesh(new THREE.ConeGeometry(0.018, 0.04, 12), mat(0x333333));
    cono.rotation.z = -Math.PI / 2; cono.position.set(K.helice[0] + 0.02, 0, K.helice[2]); grupo.add(cono);
  }
  grupo.traverse(o => { if (o.isMesh && o !== helice && o.parent !== helice) o.castShadow = true; });
  // luces (K.luces: posicion en ejes cuerpo, color y patron de parpadeo): un punto brillante de tamano fijo en pantalla
  // (sprite sin atenuacion), para que un dron de 25 cm se vea desde el puesto del piloto, y una bolita para las camaras cercanas
  if (K.luces && K.luces.length && !construirAvion.texLuz) {       // punto redondo con halo, compartido
    const c = document.createElement("canvas"); c.width = c.height = 32; const g = c.getContext("2d");
    const gr = g.createRadialGradient(16, 16, 2, 16, 16, 16); gr.addColorStop(0, "rgba(255,255,255,1)"); gr.addColorStop(0.45, "rgba(255,255,255,0.95)"); gr.addColorStop(1, "rgba(255,255,255,0)");
    g.fillStyle = gr; g.fillRect(0, 0, 32, 32); construirAvion.texLuz = new THREE.CanvasTexture(c);
  }
  const luces = (K.luces || []).map(l => {
    const g = new THREE.Group(); g.position.set(...l.p); g.patron = l.patron || "fijo";
    const sp = new THREE.Sprite(new THREE.SpriteMaterial({ color: l.color, map: construirAvion.texLuz, sizeAttenuation: false, transparent: true, depthWrite: false }));
    sp.scale.set(0.01, 0.01, 1); g.add(sp);      // en el visor se reescala cada cuadro a un tamano fijo en pixeles
    g.add(new THREE.Mesh(new THREE.SphereGeometry(0.007, 8, 6), new THREE.MeshBasicMaterial({ color: l.color })));
    grupo.add(g); return g;
  });
  return { grupo, prof, timon, alerones, helice, luces, dron: !!K.helices };
}

// ---------------------------------------------------------------------
//  EL CAMPO. Modelado sobre la imagen de satelite del sitio real (bancales de almendros sobre tierra
//  rojiza, la Rambla del Palmeral al este, el cerro de monte bajo al oeste, el cortijo al norte y la
//  AP-7 al noreste). El piloto esta en el aparcamiento, en el origen, mirando al norte; la pista de
//  tierra va hacia el norte. Coordenadas del campo en metros (E = este, N = norte); Three: x = E,
//  y = arriba, z = -N. Todo es decorado: las reglas del suelo, la pista y los pilones siguen en Entorno.
// ---------------------------------------------------------------------
function semilla(s) {        // generador determinista (mulberry32): el campo es siempre el mismo
  return function () { s |= 0; s = s + 0x6D2B79F5 | 0; let t = Math.imul(s ^ s >>> 15, 1 | s); t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t; return ((t ^ t >>> 14) >>> 0) / 4294967296; };
}
const PERM = (() => { const r = semilla(7), p = new Uint8Array(512); for (let i = 0; i < 256; i++) p[i] = i;
  for (let i = 255; i > 0; i--) { const j = Math.floor(r() * (i + 1)); const t = p[i]; p[i] = p[j]; p[j] = t; }
  for (let i = 0; i < 256; i++) p[256 + i] = p[i]; return p; })();
function ruido(x, y) {        // ruido de valor suavizado, en [0, 1]
  const xi = Math.floor(x), yi = Math.floor(y), fx = x - xi, fy = y - yi, sx = fx * fx * (3 - 2 * fx), sy = fy * fy * (3 - 2 * fy);
  const h = (i, j) => PERM[(PERM[i & 255] + (j & 255)) & 511] / 255;
  const a = h(xi, yi), b = h(xi + 1, yi), c = h(xi, yi + 1), d = h(xi + 1, yi + 1);
  return a + (b - a) * sx + (c - a) * sy + (a - b - c + d) * sx * sy;
}
function fbm(x, y, oct = 4) { let s = 0, a = 0.5, f = 1, n = 0; for (let i = 0; i < oct; i++) { s += a * ruido(x * f + 31 * i, y * f - 17 * i); n += a; a *= 0.5; f *= 2.1; } return s / n; }
function lienzo(w, h) { const c = document.createElement("canvas"); c.width = w; c.height = h; return [c, c.getContext("2d")]; }

const CAMPO = {
  // bancales de almendros: centro (E, N), largo (a lo largo de su norte girado), ancho, giro en grados (+ hacia el este),
  // paso entre muros de bancal y paleta de tonos de la tierra
  bancales: [
    { c: [130, 230], l: 540, a: 430, giro: 20, paso: 38, tono: 0 },
    { c: [150, -270], l: 440, a: 540, giro: -12, paso: 32, tono: 1 },
    { c: [-38, 60], l: 440, a: 48, giro: 25, paso: 45, tono: 2 },
    { c: [640, 160], l: 780, a: 440, giro: 30, paso: 50, tono: 3 },
    { c: [90, 650], l: 440, a: 540, giro: -30, paso: 40, tono: 1 },
    { c: [-30, -660], l: 460, a: 620, giro: 8, paso: 36, tono: 0 },
    { c: [540, -540], l: 520, a: 520, giro: 15, paso: 42, tono: 3 },
    { c: [-150, -1100], l: 500, a: 700, giro: 0, paso: 40, tono: 2 },
    { c: [700, 800], l: 600, a: 600, giro: 35, paso: 48, tono: 3 },
  ],
  tonos: [["#b3673f", "#a85d38", "#c07a52", "#9c5431"], ["#a65c38", "#9a5230", "#b56b45", "#8f4a2b"],
          ["#bf7a55", "#b26c47", "#c98a66", "#a8633f"], ["#c8906a", "#bb8260", "#d19d78", "#b07655"]],
  pistas: [[[0, -6], [-9, 15], [-10, 120], [-4, 200], [20, 262], [60, 330], [150, 470], [330, 770]],   // al cortijo y a la autopista
           [[0, -6], [6, -40], [-20, -150], [-60, -300], [-70, -620]],
           [[-9, 100], [-130, 112]], [[-4, 190], [-210, 232]], [[10, -20], [200, -25], [372, -20]]],
  rambla: N => 385 + 30 * Math.sin(N / 170) + 15 * Math.sin(N / 61 + 1),                               // E del eje segun N
  autopista: { p0: [330, 790], p1: [1340, 300], ancho: 28, alto: 2.4 },
  cortijo: [[60, 205, 14, 9, 4.5], [78, 222, 9, 7, 3.5], [66, 233, 6, 5, 3], [690, 60, 40, 18, 7], [690, 20, 25, 12, 5]],   // E, N, ancho E, ancho N, alto
};

/** E donde el campo cultivado deja paso al monte bajo del cerro, segun N (borde irregular). */
function bordeMonte(N) { return -95 + 100 * (fbm(N / 150 + 5, 3) - 0.5); }

/** La isla: radio de la costa (m) segun el rumbo desde el piloto (el mundo es finito y lo rodea el mar). */
function costa(theta) {
  return 1700 + 520 * (fbm(2.2 * Math.cos(theta) + 20, 2.2 * Math.sin(theta) + 20) - 0.5) + 90 * Math.sin(3 * theta + 1);
}
function poligonoCosta(desfase, n = 240) {
  const pts = [];
  for (let i = 0; i < n; i++) { const th = i / n * Math.PI * 2, R = costa(th) + desfase; pts.push([R * Math.cos(th), R * Math.sin(th)]); }
  return pts;
}
function enIsla(E, N, margen = 0) { return Math.hypot(E, N) < costa(Math.atan2(N, E)) - margen; }

/** Altura del terreno (m) en (E, N): llano en el campo de vuelo, cerro al oeste que cae al mar en la costa. */
function alturaTerreno(E, N) {
  const dCosta = costa(Math.atan2(N, E)) - Math.hypot(E, N), k = Math.max(0, Math.min(1, dCosta / 160));
  if (E > -110) return 0 * k - 6 * (1 - k);
  const h = alturaTierraAdentro(E, N);
  return h * k - 6 * (1 - k);
}
function alturaTierraAdentro(E, N) {
  const t = Math.min(1, (-110 - E) / 450), t2 = Math.min(1, Math.max(0, (-560 - E) / 600));
  return 42 * Math.pow(t, 1.7) + 40 * fbm(E / 260, N / 260) * t * t + 12 * fbm(E / 110, N / 110) * t + 2.5 * fbm(E / 45, N / 45) * t + 30 * t2 * t2;
}

/** Pinta el campo en coordenadas del mundo (metros) sobre un canvas de k px/m cuya esquina superior
 *  izquierda es (E0, N1). Devuelve la lista de almendros [E, N, tamano] para los arboles en 3D. z2: la zona 2 del
 *  Entorno (pista 2, diana, puerta y el rectangulo despejado). */
function pintarCampo(ctx, k, E0, N1, arboles, z2) {
  const r = semilla(11);
  ctx.setTransform(k, 0, 0, -k, -E0 * k, N1 * k);
  const ancho = ctx.canvas.width / k, alto = ctx.canvas.height / k;
  ctx.fillStyle = "#b3673f"; ctx.fillRect(E0, N1 - alto, ancho, alto);
  // pie del cerro y monte bajo al oeste, con borde irregular
  for (const [desf, alfa] of [[0, 1], [22, 0.5], [45, 0.25]]) {     // el monte entra en el campo en tres franjas cada vez mas tenues
    ctx.fillStyle = "rgba(179,171,145," + alfa + ")"; ctx.beginPath(); ctx.moveTo(E0 - 10, N1 + 10);
    for (let N = N1 + 10; N >= N1 - alto - 10; N -= 20) ctx.lineTo(bordeMonte(N) + desf, N);
    ctx.lineTo(E0 - 10, N1 - alto - 10); ctx.closePath(); ctx.fill();
  }
  for (let i = 0; i < 11000; i++) {       // matas y piedras del monte bajo, que se van espaciando hacia el campo
    const E = -1600 + r() * 1620, N = -1600 + r() * 3200, d = E - bordeMonte(N);
    if (d > 0 && r() < d / 80) continue;
    const mata = r() < 0.7;
    ctx.fillStyle = mata ? (r() < 0.5 ? "#5b6a3c" : "#6f7a48") : "#c2bba5";
    ctx.beginPath(); ctx.ellipse(E, N, mata ? 1 + r() * 2.2 : 0.6 + r() * 1.5, mata ? 1 + r() * 1.8 : 0.5 + r(), 0, 0, 7); ctx.fill();
  }
  // bancales: tierra, muros, surcos y la sombra de cada almendro
  const Z = z2.despejado;
  const excluido = (E, N) => E < bordeMonte(N) + 8 || (E > Z.e0 && E < Z.e1 && N > Z.n0 && N < Z.n1) || (Math.abs(E) < 11 && N > -2 && N < 82) || (Math.abs(E) < 16 && N > -14 && N < 10)
    || Math.abs(E - CAMPO.rambla(N)) < 32 || (E > 40 && E < 130 && N > 195 && N < 250) || (E > 660 && E < 730 && N > 0 && N < 90)
    || CAMPO.pistas.some(p => { for (let i = 1; i < p.length; i++) { const [x0, y0] = p[i - 1], [x1, y1] = p[i], dx = x1 - x0, dy = y1 - y0;
      const t = Math.max(0, Math.min(1, ((E - x0) * dx + (N - y0) * dy) / (dx * dx + dy * dy))); if (Math.hypot(E - x0 - t * dx, N - y0 - t * dy) < 4.5) return true; } return false; });
  for (const b of CAMPO.bancales) {
    const g = b.giro * D2R, cs = Math.cos(g), sn = Math.sin(g), pal = CAMPO.tonos[b.tono];
    ctx.save(); ctx.translate(b.c[0], b.c[1]); ctx.rotate(-g);          // el eje v (norte local) gira hacia el este
    for (let v = -b.l / 2; v < b.l / 2; v += b.paso) {
      ctx.fillStyle = pal[Math.floor(r() * pal.length)]; ctx.fillRect(-b.a / 2, v, b.a, Math.min(b.paso, b.l / 2 - v));
      ctx.fillStyle = "rgba(110,58,34,0.55)"; ctx.fillRect(-b.a / 2, v, b.a, 1.2);          // sombra del muro
      ctx.fillStyle = "rgba(226,190,150,0.85)"; ctx.fillRect(-b.a / 2, v + 1.2, b.a, 1.4);   // muro de piedra seca
    }
    ctx.strokeStyle = "rgba(120,60,35,0.28)"; ctx.lineWidth = 0.45;                          // surcos
    for (let u = -b.a / 2; u < b.a / 2; u += 1.25) { ctx.beginPath(); ctx.moveTo(u, -b.l / 2); ctx.lineTo(u, b.l / 2); ctx.stroke(); }
    ctx.restore();
    for (let v = -b.l / 2 + 4; v < b.l / 2 - 3; v += 7.5) {
      for (let u = -b.a / 2 + 4; u < b.a / 2 - 3; u += 7.5) {
        if (r() < 0.08) continue;
        const uu = u + (r() - 0.5) * 1.2, vv = v + (r() - 0.5) * 1.2;
        const E = b.c[0] + uu * cs + vv * sn, N = b.c[1] - uu * sn + vv * cs;
        if (excluido(E, N)) continue;
        const s = 0.75 + r() * 0.5;
        if (arboles) arboles.push([E, N, s]);
        ctx.fillStyle = "rgba(70,38,22,0.55)"; ctx.beginPath(); ctx.ellipse(E + 1.4 * s, N - 1.1 * s, 1.9 * s, 1.3 * s, 0, 0, 7); ctx.fill();
        ctx.fillStyle = s > 1.05 ? "#4f6a2d" : "#5d7a36"; ctx.beginPath(); ctx.arc(E, N, 1.55 * s, 0, 7); ctx.fill();
      }
    }
  }
  // rambla: vegetacion de las orillas, cauce de arena y el canal
  ctx.lineCap = "round"; ctx.lineJoin = "round";
  const traza = w => { ctx.lineWidth = w; ctx.beginPath(); for (let N = -1600; N <= 1600; N += 15) { const E = CAMPO.rambla(N); N === -1600 ? ctx.moveTo(E, N) : ctx.lineTo(E, N); } ctx.stroke(); };
  ctx.strokeStyle = "#4b5f31"; traza(62); ctx.strokeStyle = "#cdbf9f"; traza(30); ctx.strokeStyle = "#b8a98a"; traza(5);
  for (let i = 0; i < 2600; i++) {
    const N = -1600 + r() * 3200, lado = r() < 0.5 ? -1 : 1, d = 14 + r() * 20, E = CAMPO.rambla(N) + lado * d;
    ctx.fillStyle = ["#3d5428", "#4f6b33", "#667a43", "#8a9a5a"][Math.floor(r() * 4)];
    ctx.beginPath(); ctx.ellipse(E, N, 2 + r() * 4, 1.5 + r() * 3, r() * 3, 0, 7); ctx.fill();
  }
  // pistas de tierra
  ctx.strokeStyle = "#dcc9a8"; ctx.lineWidth = 4.2;
  for (const p of CAMPO.pistas) { ctx.beginPath(); p.forEach(([E, N], i) => i ? ctx.lineTo(E, N) : ctx.moveTo(E, N)); ctx.stroke(); }
  ctx.strokeStyle = "rgba(170,140,105,0.55)"; ctx.lineWidth = 0.9;
  for (const p of CAMPO.pistas) { ctx.beginPath(); p.forEach(([E, N], i) => i ? ctx.lineTo(E, N) : ctx.moveTo(E, N)); ctx.stroke(); }
  // terraplen de la autopista (la calzada va en 3D encima)
  const A = CAMPO.autopista;
  ctx.strokeStyle = "#c2a98a"; ctx.lineWidth = 64; ctx.beginPath(); ctx.moveTo(...A.p0); ctx.lineTo(...A.p1); ctx.stroke();
  ctx.strokeStyle = "#5e5e5e"; ctx.lineWidth = A.ancho; ctx.beginPath(); ctx.moveTo(...A.p0); ctx.lineTo(...A.p1); ctx.stroke();
  // era del cortijo y las naves
  ctx.fillStyle = "#d8c6a7"; ctx.fillRect(45, 196, 80, 50); ctx.fillRect(662, 2, 66, 86);
  // aparcamiento de grava y pista de tierra compactada con sus marcas de cal
  ctx.fillStyle = "#ccbfa7"; ctx.beginPath(); ctx.ellipse(0, -2, 14, 9, 0, 0, 7); ctx.fill();
  ctx.fillStyle = "#d4bd98"; ctx.fillRect(-7, 7, 14, 67);
  ctx.fillStyle = "#c6ac86"; ctx.fillRect(-5, 9, 10, 62);
  ctx.strokeStyle = "rgba(140,110,80,0.5)"; ctx.lineWidth = 0.3;
  for (let E = -4.6; E < 5; E += 0.9) { ctx.beginPath(); ctx.moveTo(E, 9); ctx.lineTo(E, 71); ctx.stroke(); }
  ctx.fillStyle = "rgba(255,255,255,0.9)";
  for (const N of [10.5, 68.5]) ctx.fillRect(-4.5, N, 9, 1.0);
  for (let N = 15; N < 66; N += 5) ctx.fillRect(-0.18, N, 0.36, 2.2);
  // zona 2 (detras del piloto): pista 2 de este a oeste con la diana de cal en el centro y la linea de la puerta
  const P2 = z2.pista, D = z2.diana, Pu = z2.puerta;
  ctx.fillStyle = "#d4bd98"; ctx.fillRect(P2.e0 - 2, P2.n - P2.ancho / 2 - 2, P2.e1 - P2.e0 + 4, P2.ancho + 4);
  ctx.fillStyle = "#c6ac86"; ctx.fillRect(P2.e0, P2.n - P2.ancho / 2, P2.e1 - P2.e0, P2.ancho);
  ctx.strokeStyle = "rgba(140,110,80,0.5)"; ctx.lineWidth = 0.3;
  for (let N = P2.n - P2.ancho / 2 + 0.4; N < P2.n + P2.ancho / 2; N += 0.9) { ctx.beginPath(); ctx.moveTo(P2.e0, N); ctx.lineTo(P2.e1, N); ctx.stroke(); }
  ctx.fillStyle = "rgba(255,255,255,0.9)";
  for (const E of [P2.e0 + 0.5, P2.e1 - 1.5]) ctx.fillRect(E, P2.n - P2.ancho / 2 + 0.5, 1.0, P2.ancho - 1);   // umbrales
  ctx.strokeStyle = "rgba(255,255,255,0.92)"; ctx.lineWidth = 0.45;
  for (const [r] of D.anillos) { ctx.beginPath(); ctx.arc(D.e, D.n, r, 0, 7); ctx.stroke(); }
  ctx.fillStyle = "rgba(255,255,255,0.92)"; ctx.beginPath(); ctx.arc(D.e, D.n, 0.8, 0, 7); ctx.fill();
  for (let N = Pu.n0 + 2; N < Pu.n1 - 1.5; N += 2.4) ctx.fillRect(Pu.e - 0.2, N, 0.4, 1.4);                      // linea de la puerta
  // la costa (solo en la textura lejana): agua somera, playa y espuma
  if (!arboles) {
    const traza = (pts, w, estilo) => { ctx.strokeStyle = estilo; ctx.lineWidth = w; ctx.beginPath(); pts.forEach(([E, N], i) => i ? ctx.lineTo(E, N) : ctx.moveTo(E, N)); ctx.closePath(); ctx.stroke(); };
    traza(poligonoCosta(35), 70, "#4f9fb8"); traza(poligonoCosta(-42), 84, "#e3d5b2"); traza(poligonoCosta(0), 6, "rgba(255,255,255,0.75)");
  }
  // grano fino de la tierra
  const [tile, tg] = lienzo(256, 256), img = tg.createImageData(256, 256), rr = semilla(3);
  for (let i = 0; i < img.data.length; i += 4) { const v = 150 + rr() * 110; img.data[i] = img.data[i + 1] = img.data[i + 2] = v; img.data[i + 3] = 255; }
  tg.putImageData(img, 0, 0);
  ctx.setTransform(1, 0, 0, 1, 0, 0); ctx.globalCompositeOperation = "multiply"; ctx.globalAlpha = 0.28;
  ctx.fillStyle = ctx.createPattern(tile, "repeat"); ctx.fillRect(0, 0, ctx.canvas.width, ctx.canvas.height);
  ctx.globalCompositeOperation = "source-over"; ctx.globalAlpha = 1;
}

class Visor {
  constructor(lienzo, entorno) {
    this.entorno = entorno;
    this.renderer = new THREE.WebGLRenderer({ canvas: lienzo, antialias: true, logarithmicDepthBuffer: false });
    // exposicion 0,5 y luces x2: el cielo fisico de Three (Sky) esta calibrado para esa exposicion; con 1 sale blanco
    this.renderer.toneMapping = THREE.ACESFilmicToneMapping; this.renderer.toneMappingExposure = 0.5;
    this.renderer.shadowMap.enabled = true; this.renderer.shadowMap.type = THREE.PCFSoftShadowMap;
    this.aguas = [];                                  // superficies de agua (Water o plano simple, segun la calidad)
    this.escena = new THREE.Scene();
    this.escena.background = new THREE.Color(0xd3dfe9);
    // calidad 2 (todo), 1 (sin vegetacion lejana, 1 px por pixel) o 0 (ademas sin matas ni nubes, 3/4 de resolucion).
    // Baja sola si el ordenador no llega a 35 fps durante 3 s, y se recuerda en este navegador
    let q = 2; try { q = +localStorage.getItem("sim_calidad"); if (!(q >= 0 && q <= 2)) q = 2; } catch (e) {}
    this.calidad = q; this._frames = []; this.lejanos = []; this.prescindibles = [];
    this.escena.fog = new THREE.Fog(0xd3dfe9, 450, 2700);           // calima: el cerro y la autopista se difuminan
    this.cam = new THREE.PerspectiveCamera(50, 1, 0.1, 3000);        // mas lejos todo es calima; con mas alcance el mar parpadea sobre el suelo (z-fighting)
    this.camara = 1;                                  // 1 piloto, 2 persecucion, 3 a bordo
    this.avion = null;
    this.escena.add(new THREE.HemisphereLight(0xd9e8ff, 0x8a5a3a, 0.72 * 2 * Math.PI));     // cielo azul, rebote de la tierra rojiza
    const sol = new THREE.DirectionalLight(0xfff1dc, 1.05 * 2 * Math.PI); sol.position.set(-350, 520, 260); this.escena.add(sol);
    this._configurarSol(sol, this.escena);
    this._cielo(sol.position, this.escena, 2850);
    this._campo();
    this.escenaIsla = this.escena; this.mundoId = "isla"; this.mundo = null; this.mundos = {};
    this.sombra = new THREE.Mesh(new THREE.CircleGeometry(0.6, 20), new THREE.MeshBasicMaterial({ color: 0x000000, transparent: true, opacity: 0.35 }));
    this.sombra.rotation.x = -Math.PI / 2; this.sombra.position.y = 0.05; this.escena.add(this.sombra);
    this.escena.traverse(o => { if (o.isMesh) o.receiveShadow = true; });
    window.addEventListener("resize", () => this.redimensionar()); this.aplicarCalidad(this.calidad);
  }

  /** Aplica un nivel de calidad (ver el constructor) y lo guarda. */
  aplicarCalidad(q) {
    this.calidad = q;
    for (const esc of [this.escenaIsla, ...Object.values(this.mundos || {})]) if (esc && esc.userData.sol) {
      const S = esc.userData.sol; S.castShadow = q >= 1; S.shadow.mapSize.set(q >= 2 ? 4096 : 2048, q >= 2 ? 4096 : 2048);
      if (S.shadow.map) { S.shadow.map.dispose(); S.shadow.map = null; }
    }
    for (const a of this.aguas) if (a.water !== a.plano) { a.water.visible = q >= 2; a.plano.visible = q < 2; }
    this._aguaCerca = undefined;
    this.renderer.setPixelRatio(Math.min(q === 2 ? 1.5 : q === 1 ? 1 : 0.75, window.devicePixelRatio));
    for (const m of this.lejanos) m.visible = q >= 2;
    for (const m of this.prescindibles) m.visible = q >= 1;
    try { localStorage.setItem("sim_calidad", String(q)); } catch (e) {}
    this.redimensionar();
  }

  /** Si dos tandas seguidas de 120 fotogramas van a menos de 35 fps, baja un nivel de calidad. No cuenta la
   *  pestana oculta, los parones ni los primeros 5 s (carga de texturas). */
  _vigilarCalidad(dt) {
    if (this.calidadFija) return;                  // el usuario ha fijado la calidad en Ajustes
    const f = this._frames, ahora = performance.now();
    if (!this._t0) this._t0 = ahora;
    if (document.hidden || dt > 0.2 || dt <= 0 || ahora - this._t0 < 5000) { f.length = 0; this._lentas = 0; return; }
    f.push(dt); if (f.length < 120) return;
    const media = f.reduce((a, b) => a + b, 0) / f.length; f.length = 0;
    this._lentas = media > 1 / 35 ? (this._lentas || 0) + 1 : 0;
    if (this._lentas >= 2 && this.calidad > 0) { this._lentas = 0; this.aplicarCalidad(this.calidad - 1); console.info("Simulador: calidad bajada a " + this.calidad + " (" + (1 / media).toFixed(0) + " fps)"); }
  }

  redimensionar() {
    const w = window.innerWidth, h = window.innerHeight;
    this.renderer.setSize(w, h, false); this.cam.aspect = w / h; this.cam.updateProjectionMatrix();
  }

  /** Sol con sombras: un mapa de 4096 px que cubre 180 x 180 m alrededor del avion (dibujar() lo mueve con el). */
  _configurarSol(sol, esc) {
    sol.castShadow = true; sol.shadow.mapSize.set(4096, 4096);
    const c = sol.shadow.camera; c.left = c.bottom = -90; c.right = c.top = 90; c.near = 10; c.far = 1500;
    sol.shadow.bias = -0.0003; sol.shadow.normalBias = 0.35;
    sol.userData.dir = sol.position.clone().normalize();
    esc.add(sol.target); esc.userData.sol = sol;
  }

  /** Opacidad del agua del Mar Menor (0-255), la misma que ALFA_LAGUNA de mundo_3d.gd en Godot. */
  static get ALFA_LAGUNA() { return 105; }

  /** Mar: el agua de Three (reflejos del cielo y del sol, oleaje con un mapa de normales procedural) y, para la
   *  calidad baja, un plano simple. y: altura de la superficie; lado: tamano del plano. */
  _mar(esc, y, lado, color = 0x1f5a86, conReflejos = true) {
    if (!Visor._normalesAgua) {                       // mapa de normales periodico (suma de ondas enteras: se repite sin costura)
      const N = 512, [c, g] = lienzo(N, N), img = g.createImageData(N, N), r = semilla(91), ondas = [];
      for (let k = 0; k < 24; k++) ondas.push([Math.round((r() - 0.5) * 24), Math.round((r() - 0.5) * 24), 0.6 / (1 + k * 0.25), r() * 6.28]);
      const h = (x, z) => ondas.reduce((s, [a, b, amp, f]) => s + amp * Math.sin(2 * Math.PI * (a * x + b * z) / N + f), 0);
      for (let z = 0; z < N; z++) for (let x = 0; x < N; x++) {
        const dx = h(x + 1, z) - h(x - 1, z), dz = h(x, z + 1) - h(x, z - 1), l = Math.hypot(dx, dz, 2), p = 4 * (z * N + x);
        img.data[p] = 128 - 127 * dx / l; img.data[p + 1] = 128 - 127 * dz / l; img.data[p + 2] = 128 + 127 * 2 / l; img.data[p + 3] = 255;
      }
      g.putImageData(img, 0, 0);
      const t = new THREE.CanvasTexture(c); t.wrapS = t.wrapT = THREE.RepeatWrapping; Visor._normalesAgua = t;
    }
    const geo = new THREE.PlaneGeometry(lado, lado);
    // sin reflejos: oleaje con el mismo mapa de normales (repetido cada 40 m) y el brillo del sol
    const nm = Visor._normalesAgua.clone(); nm.needsUpdate = true; nm.repeat.set(lado / 40, lado / 40);
    const plano = new THREE.Mesh(geo, new THREE.MeshPhongMaterial({ color, specular: 0x9fb8cc, shininess: 70, normalMap: nm, normalScale: new THREE.Vector2(0.35, 0.35) }));
    plano.rotation.x = -Math.PI / 2; plano.position.y = y; esc.add(plano);
    let water = plano;
    if (THREE.Water && conReflejos) {
      const sol = esc.userData.sol;
      water = new THREE.Water(geo, { textureWidth: 1024, textureHeight: 1024, waterNormals: Visor._normalesAgua, sunDirection: sol ? sol.userData.dir.clone() : new THREE.Vector3(0.4, 0.8, 0.3),
                                     sunColor: 0xfff4e0, waterColor: color, distortionScale: 2.2, fog: !!esc.fog, alpha: 1.0 });
      water.material.uniforms.size.value = 2.5;
      water.rotation.x = -Math.PI / 2; water.position.y = y; esc.add(water);
    }
    this.aguas.push({ water, plano });
    water.visible = this.calidad >= 2; plano.visible = !water.visible || water === plano;
  }

  /** (N, E) dentro de alguna zona de detalle puesta (con margen en m). */
  _enZonas(n, e, margen) {
    for (const Zb of this.zonasBBox || []) if (n > Zb[0] - margen && n < Zb[1] + margen && e > Zb[2] - margen && e < Zb[3] + margen) return true;
    return false;
  }

  /** Agua de la laguna (Mar Menor, Entorno.laguna) semitransparente: debajo esta la ortofoto, que trae el color real del
   *  agua somera y de su fondo (la region a 12 m y las zonas a 0,5 m); el mar abierto sigue opaco. Mascara en alphaMap,
   *  colocada sobre el plano con repeat/offset (la textura cubre el terreno del mundo; fuera, su borde: mar opaco). */
  _lagunaTransparente(plano, T) {
    const Lg = this.entorno.laguna; if (!Lg || !plano) return;
    const [c, g] = lienzo(T.nE, T.nN), img = g.createImageData(T.nE, T.nN);
    for (let r = 0; r < T.nN; r++) for (let j = 0; j < T.nE; j++) {                     // fila 0 de la imagen = norte
      const k = (T.nN - 1 - r) * T.nE + j, v = Lg[k] ? Visor.ALFA_LAGUNA : 255, q = 4 * (r * T.nE + j);
      img.data[q] = img.data[q + 1] = img.data[q + 2] = v; img.data[q + 3] = 255;
    }
    g.putImageData(img, 0, 0);
    const t = new THREE.CanvasTexture(c), lado = plano.geometry.parameters.width, W = (T.nE - 1) * T.paso, H = (T.nN - 1) * T.paso;
    t.wrapS = t.wrapT = THREE.ClampToEdgeWrapping; t.minFilter = THREE.LinearFilter; t.generateMipmaps = false;
    t.repeat.set(lado / W, lado / H); t.offset.set((-lado / 2 - T.E0) / W, (-lado / 2 - T.N0) / H);   // uv del plano (0..1 en lado) -> terreno
    plano.material.alphaMap = t; plano.material.transparent = true; plano.material.depthWrite = false; plano.material.needsUpdate = true;
  }

  /** Cupula de cielo con degradado, el sol y unas nubes lejanas. radio: el de la cupula (la isla, 2850 m; un mundo
   *  real, mucho mas, y las nubes se escalan con el). Con THREE.Sky, cielo fisico (dispersion de Rayleigh y Mie). */
  _cielo(posSol, esc, radio) {
    const k = radio / 2850;
    if (THREE.Sky) {
      const sky = new THREE.Sky(); sky.scale.setScalar(radio * 3); sky.frustumCulled = false;
      const u = sky.material.uniforms;
      u.turbidity.value = 3.5; u.rayleigh.value = 2.2; u.mieCoefficient.value = 0.003; u.mieDirectionalG.value = 0.8;
      u.sunPosition.value.copy(posSol).normalize();
      esc.add(sky);
    }
    const cielo = new THREE.Mesh(new THREE.SphereGeometry(radio, 32, 16), new THREE.ShaderMaterial({
      uniforms: { cima: { value: new THREE.Color(0x3f7fd0) }, horizonte: { value: new THREE.Color(0xd3dfe9) } },   // el horizonte, del color de la calima
      vertexShader: "varying vec3 vP; void main() { vP = position; gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0); }",
      fragmentShader: "uniform vec3 cima; uniform vec3 horizonte; varying vec3 vP; void main() { float t = pow(clamp(normalize(vP).y, 0.0, 1.0), 0.5); gl_FragColor = vec4(mix(horizonte, cima, t), 1.0); }",
      side: THREE.BackSide, depthWrite: false, fog: false }));
    if (!THREE.Sky) esc.add(cielo);
    const [cs, gs] = lienzo(256, 256), g = gs.createRadialGradient(128, 128, 0, 128, 128, 128);
    g.addColorStop(0, "rgba(255,252,240,1)"); g.addColorStop(0.18, "rgba(255,246,210,0.9)"); g.addColorStop(0.5, "rgba(255,235,190,0.25)"); g.addColorStop(1, "rgba(255,230,180,0)");
    gs.fillStyle = g; gs.fillRect(0, 0, 256, 256);
    const solSprite = new THREE.Sprite(new THREE.SpriteMaterial({ map: texSRGB(cs), fog: false, depthWrite: false }));
    solSprite.position.copy(posSol).normalize().multiplyScalar(2600 * k); solSprite.scale.set(520 * k, 520 * k, 1);
    if (!THREE.Sky) esc.add(solSprite);
    const [cn, gn] = lienzo(256, 128), r = semilla(5);
    for (let i = 0; i < 26; i++) {
      const x = 40 + r() * 176, y = 50 + r() * 40, rad = 18 + r() * 26, gg = gn.createRadialGradient(x, y, 0, x, y, rad);
      gg.addColorStop(0, "rgba(255,255,255,0.75)"); gg.addColorStop(0.6, "rgba(250,250,252,0.35)"); gg.addColorStop(1, "rgba(245,245,250,0)");
      gn.fillStyle = gg; gn.fillRect(0, 0, 256, 128);
    }
    const mn = new THREE.SpriteMaterial({ map: texSRGB(cn), transparent: true, depthWrite: false, opacity: 0.9 });
    for (let i = 0; i < 14; i++) {
      const a = r() * Math.PI * 2, d = (900 + r() * 1400) * k, s = (260 + r() * 420) * k, nube = new THREE.Sprite(mn);
      nube.position.set(d * Math.cos(a), (420 + r() * 380) * Math.min(k, 3), d * Math.sin(a)); nube.scale.set(s, s * 0.42, 1); esc.add(nube); this.prescindibles.push(nube);
    }
  }

  /** Mallas instanciadas por celdas de 300 m, cada una con su esfera envolvente (Three no la calcula para
   *  las instancias y, sin ella, recorta mal): lo que queda fuera de la camara no se dibuja. lista: [E, N, s, ...];
   *  colocar(item, M, C) rellena la matriz y el color. Las celdas a mas de lejos_m del campo van a this.lejanos. */
  _instanciar(geom, mat, lista, colocar, lejos_m = 520) {
    const celdas = new Map(), T = 300;
    for (const it of lista) { const k = Math.floor(it[0] / T) + "," + Math.floor(it[1] / T); if (!celdas.has(k)) celdas.set(k, []); celdas.get(k).push(it); }
    const M = new THREE.Matrix4(), C = new THREE.Color();
    for (const items of celdas.values()) {
      const g = geom.clone(), m = new THREE.InstancedMesh(g, mat, items.length);
      let cx = 0, cz = 0, smax = 0;
      items.forEach((it, i) => { colocar(it, M, C); m.setMatrixAt(i, M); m.setColorAt(i, C); cx += it[0]; cz -= it[1]; smax = Math.max(smax, it[2]); });
      cx /= items.length; cz /= items.length;
      let rad = 0; for (const it of items) rad = Math.max(rad, Math.hypot(it[0] - cx, -it[1] - cz));
      g.boundingSphere = new THREE.Sphere(new THREE.Vector3(cx, 20, cz), rad + 6 * smax + 60);
      this.escena.add(m);
      if (Math.hypot(cx, cz + 110) > lejos_m) this.lejanos.push(m);
    }
  }

  _campo() {
    const E = this.entorno, esc = this.escena, r = semilla(23);
    const lam = (c, extra) => new THREE.MeshLambertMaterial(Object.assign({ color: c }, extra || {}));
    const aniso = this.renderer.capabilities.getMaxAnisotropy();
    const tex = c => { const t = texSRGB(c); t.anisotropy = aniso; return t; };
    // suelo: una textura de detalle de 1400 m alrededor del campo de vuelo y otra lejana de 6000 m
    const arboles = [];
    const [cc, gc] = lienzo(4096, 4096); pintarCampo(gc, 4096 / 1400, -700, 900, arboles, E.zona2);
    const cerca = new THREE.Mesh(new THREE.PlaneGeometry(1400, 1400), lam(0xffffff, { map: tex(cc) }));
    cerca.rotation.x = -Math.PI / 2; cerca.position.set(0, 0.01, -200); esc.add(cerca);
    const [cl, gl] = lienzo(2048, 2048); pintarCampo(gl, 2048 / 6000, -3000, 3000, null, E.zona2);
    const forma = new THREE.Shape(poligonoCosta(70).map(p => new THREE.Vector2(...p)));
    forma.holes.push(new THREE.Path([[-700, -500], [700, -500], [700, 900], [-700, 900]].map(p => new THREE.Vector2(...p))));   // hueco bajo la textura cercana
    const tl = tex(cl); tl.repeat.set(1 / 6000, 1 / 6000); tl.offset.set(0.5, 0.5);
    const lejos = new THREE.Mesh(new THREE.ShapeGeometry(forma), lam(0xffffff, { map: tl }));
    lejos.rotation.x = -Math.PI / 2; esc.add(lejos);
    this._mar(esc, -1.2, 40000, 0x245f88);                                        // bajo el suelo: nunca parpadea sobre la isla
    // cerro del oeste: malla elevada con bandas de roca (colores por vertice) y una textura de matas repetida
    const gh = new THREE.PlaneGeometry(1540, 3200, 154, 320), ph = gh.getAttribute("position"), col = [];
    const cRoca = new THREE.Color(0xcfc5a8), cMonte = new THREE.Color(0xa69e84), cVerde = new THREE.Color(0x737a56), cPie = new THREE.Color(0xb3ab91);
    for (let i = 0; i < ph.count; i++) {
      const Ex = ph.getX(i) - 830, Nn = ph.getY(i);               // la malla se tumba: su y es el norte
      const db = bordeMonte(Nn) - Ex, kb = Math.max(0, Math.min(1, db / 90));           // 0 en el borde del monte, 1 a 90 m
      const h = db < 0 ? -1.5 : alturaTerreno(Ex, Nn) * kb * kb; ph.setZ(i, h);          // al este del borde queda bajo el suelo
      const banda = Math.max(0, 1 - Math.abs(((h + 3 * fbm(Ex / 90, Nn / 90)) % 9) - 4.5) / 1.3) * Math.min(1, h / 10);
      const sombra = 0.62 + 0.75 * fbm(Ex / 70 + 3, Nn / 70) + 0.25 * (ruido(Ex / 11, Nn / 11) - 0.5);   // barrancos, lomas y grano
      const c = cMonte.clone().lerp(cVerde, 0.7 * fbm(Ex / 300 + 9, Nn / 300)).lerp(cRoca, 0.9 * banda).multiplyScalar(sombra);
      c.lerp(cPie, 1 - Math.min(1, db / 150));                                           // en el pie, el color del suelo pintado
      col.push(c.r, c.g, c.b);
    }
    gh.setAttribute("color", new THREE.Float32BufferAttribute(col, 3)); gh.computeVertexNormals();
    const cerro = new THREE.Mesh(gh, lam(0xffffff, { vertexColors: true }));
    cerro.rotation.x = -Math.PI / 2; cerro.position.set(-830, 0.3, 0); esc.add(cerro);
    // almendros en reticula (instancias): tronco y copa; los de cerca con mas detalle que los lejanos
    const Q = new THREE.Quaternion(), S = new THREE.Vector3(), P = new THREE.Vector3();
    const ejeY = new THREE.Vector3(0, 1, 0), mTronco = lam(0x5b4330), mCopa = lam(0xffffff);
    for (const [dMin, dMax, detalle] of [[0, 150, 1], [150, 680, 0]]) {      // solo cerca del campo las copas llevan mas caras
      const lista = arboles.filter(a => { const d = Math.hypot(a[0], a[1] - 110); return d >= dMin && d < dMax; });
      this._instanciar(new THREE.CylinderGeometry(0.08, 0.14, 1.0, 5), mTronco, lista, ([Ex, Nn, s], M, C) => {
        P.set(Ex, 0.5 * s, -Nn); S.set(s, s, s); Q.setFromAxisAngle(ejeY, r() * 6.28); M.compose(P, Q, S); C.setHex(0xffffff);
      });
      this._instanciar(new THREE.IcosahedronGeometry(1.3, detalle), mCopa, lista, ([Ex, Nn, s], M, C) => {
        P.set(Ex, 1.55 * s, -Nn); S.set(s * (0.85 + 0.35 * r()), s * 0.68, s * (0.85 + 0.35 * r())); Q.setFromAxisAngle(ejeY, r() * 6.28);
        M.compose(P, Q, S); C.setHSL(0.22 + 0.06 * r(), 0.26 + 0.16 * r(), 0.2 + 0.09 * r());
      });
    }
    // arboles grandes (algarrobos y pinos) sueltos, matorral de la rambla y matas del cerro
    const grandes = [];
    for (let i = 0; i < 70; i++) {
      const Ex = -300 + r() * 1100, Nn = -700 + r() * 1500;
      const Z = E.zona2.despejado;
      if (Math.hypot(Ex, Nn - 40) < 95 || (Ex > Z.e0 - 10 && Ex < Z.e1 + 10 && Nn > Z.n0 - 10 && Nn < Z.n1 + 10) || Math.abs(Ex - CAMPO.rambla(Nn)) < 36 || !enIsla(Ex, Nn, 80)) continue;
      grandes.push([Ex, Nn, 2.2 + r() * 2.2, r() < 0.4]);
    }
    for (let i = 0; i < 36; i++) { const Nn = -600 + r() * 1300; grandes.push([CAMPO.rambla(Nn) + (r() < 0.5 ? -1 : 1) * (18 + r() * 12), Nn, 2.6 + r() * 2.4, false]); }
    [[52, 240, 4.2, false], [100, 198, 3.6, false], [-18, 207, 3.4, true], [120, 240, 3.8, false]].forEach(a => grandes.push(a));
    this._instanciar(new THREE.CylinderGeometry(0.2, 0.32, 1, 6), lam(0x5a4634), grandes, ([Ex, Nn, s, pino], M, C) => {
      const ht = pino ? 3.2 * s / 2.5 : 1.1 * s / 2.5, h = alturaTerreno(Ex, Nn);
      P.set(Ex, h + ht / 2, -Nn); S.set(s / 2.5, ht, s / 2.5); Q.identity(); M.compose(P, Q, S); C.setHex(0xffffff);
    }, 1e9);
    this._instanciar(new THREE.IcosahedronGeometry(1, 2), lam(0xffffff), grandes, ([Ex, Nn, s, pino], M, C) => {
      const ht = pino ? 3.2 * s / 2.5 : 1.1 * s / 2.5, h = alturaTerreno(Ex, Nn);
      P.set(Ex, h + ht + s * (pino ? 0.95 : 0.6), -Nn); S.set(s, s * (pino ? 1.25 : 0.8), s * (0.9 + 0.2 * r())); Q.identity(); M.compose(P, Q, S);
      if (pino) C.setHSL(0.27, 0.35, 0.2 + 0.05 * r()); else C.setHSL(0.22 + 0.04 * r(), 0.3, 0.25 + 0.06 * r());
    }, 1e9);
    const matas = [];
    for (let i = 0; i < 4600; i++) { const Ex = -900 + r() * 900, Nn = -800 + r() * 1600, d = Ex - bordeMonte(Nn); if ((d > 0 && r() < d / 70) || !enIsla(Ex, Nn, 100)) continue; matas.push([Ex, Nn, 0.8 + r() * 1.8, 0]); }
    for (let i = 0; i < 700; i++) { const Nn = -1000 + r() * 2000; matas.push([CAMPO.rambla(Nn) + (r() < 0.5 ? -1 : 1) * (16 + r() * 15), Nn, 1.2 + r() * 2.2, 1]); }
    const antes = this.escena.children.length;
    this._instanciar(new THREE.IcosahedronGeometry(1, 0), lam(0xffffff), matas, ([Ex, Nn, s, tipo], M, C) => {
      P.set(Ex, alturaTerreno(Ex, Nn) + s * 0.45, -Nn); S.set(s, s * 0.6, s * (0.8 + 0.4 * r())); Q.setFromAxisAngle(ejeY, r() * 6.28); M.compose(P, Q, S);
      if (tipo) C.setHSL(0.25 + 0.05 * r(), 0.3 + 0.2 * r(), 0.22 + 0.1 * r()); else C.setHSL(0.2 + 0.05 * r(), 0.22, 0.3 + 0.08 * r());
    }, 1e9);
    this.prescindibles.push(...this.escena.children.slice(antes));          // las matas sobran en calidad 0
    // arboles solidos de la isla (Entorno.chocaArbol): almendros (copa de 1,1 s de radio hasta 2,4 s) y los grandes
    E.ponerArboles("campo", arboles.map(([Ex, Nn, s]) => [Ex, Nn, 1.1 * s, 0, 2.4 * s]).concat(grandes.map(([Ex, Nn, s, pino]) => {
      const h = alturaTerreno(Ex, Nn); return [Ex, Nn, 0.9 * s, h, h + (pino ? 3.2 * s / 2.5 + 2.2 * s : 1.1 * s / 2.5 + 1.4 * s)];
    })));
    // cortijo y naves: cajas blancas con azotea; una con tejado
    for (const [Ex, Nn, a, b, h] of CAMPO.cortijo) {
      const nave = a > 20, caja = new THREE.Mesh(new THREE.BoxGeometry(a, h, b), lam(nave ? 0xd9d6cf : 0xeae4d8));
      caja.position.set(Ex, h / 2, -Nn); esc.add(caja);
      if (!nave && a > 10) { const tej = new THREE.Mesh(new THREE.ConeGeometry(a * 0.75, 2.2, 4), lam(0xb0563b)); tej.rotation.y = Math.PI / 4; tej.scale.z = b / a; tej.position.set(Ex, h + 1.1, -Nn); esc.add(tej); }
      else { const az = new THREE.Mesh(new THREE.BoxGeometry(a + 0.4, 0.3, b + 0.4), lam(nave ? 0x9a9a98 : 0xc7b9a1)); az.position.set(Ex, h, -Nn); esc.add(az); }
    }
    const tapia = new THREE.Mesh(new THREE.BoxGeometry(70, 1.6, 0.4), lam(0xe0d7c6)); tapia.position.set(85, 0.8, -248); esc.add(tapia);
    // autopista AP-7 sobre terraplen, con sus marcas y trafico
    const A = CAMPO.autopista, dx = A.p1[0] - A.p0[0], dz = -(A.p1[1] - A.p0[1]), L = Math.hypot(dx, dz), ang = Math.atan2(-dz, dx);
    const [ca, ga] = lienzo(1024, 64); ga.fillStyle = "#585858"; ga.fillRect(0, 0, 1024, 64);
    ga.fillStyle = "#7a8a5a"; ga.fillRect(0, 28, 1024, 8); ga.fillStyle = "#e8e8e8";
    for (const y of [3, 25, 37, 59]) ga.fillRect(0, y, 1024, 1.5);
    for (let x = 0; x < 1024; x += 24) { ga.fillRect(x, 14, 12, 1.2); ga.fillRect(x, 48, 12, 1.2); }
    const ta = tex(ca); ta.wrapS = THREE.RepeatWrapping; ta.repeat.set(L / 60, 1);
    const tierra = lam(0xb9a486), terraplen = new THREE.Mesh(new THREE.BoxGeometry(L, A.alto, A.ancho), [tierra, tierra, lam(0xffffff, { map: ta }), tierra, tierra, tierra]);   // la calzada es la cara de arriba
    terraplen.position.set((A.p0[0] + A.p1[0]) / 2, A.alto / 2, -(A.p0[1] + A.p1[1]) / 2); terraplen.rotation.y = ang; esc.add(terraplen);
    const C = new THREE.Color(), coches = new THREE.InstancedMesh(new THREE.BoxGeometry(4.4, 1.6, 1.9), lam(0xffffff), 44);
    coches.frustumCulled = false;
    this.trafico = { malla: coches, s: [], ang, A, L };
    for (let i = 0; i < 44; i++) {
      const carril = Math.floor(r() * 4), camion = r() < 0.2;
      this.trafico.s.push({ u: r() * L, carril, v: (carril < 2 ? -1 : 1) * (camion ? 23 : 30 + r() * 8), camion });
      coches.setColorAt(i, C.setHex([0xf0f0f0, 0xd8d8d8, 0x333333, 0xb0261b, 0x1f4e9a, 0x8c8c8c, 0xe6c84a][Math.floor(r() * 7)]));
    }
    esc.add(coches); this._trafico(0);
    // estacas blancas cada 50 m para juzgar distancias
    const estaca = new THREE.CylinderGeometry(0.05, 0.05, 1.5, 5), mEst = lam(0xf2f2f2);
    for (let x = -200; x <= 200; x += 50) for (let z = -200; z <= 200; z += 50) {
      const Z = E.zona2.despejado;
      if ((x === 0 && z === 0) || (x > Z.e0 && x < Z.e1 && -z > Z.n0 && -z < Z.n1)) continue;
      const p = new THREE.Mesh(estaca, mEst); p.position.set(x, 0.75, z); esc.add(p);
    }
    // pilones hinchables tipo Red Bull, cada uno de su color (Entorno.circuito.colores; la puerta de la zona 2,
    // naranja): banda de cuadros arriba y franja blanca abajo
    const Pi = E.pilon, colores = E.circuito.colores;
    const gpil = new THREE.CylinderGeometry(Pi.r1, Pi.r0, Pi.alto, 20, 1, true), gtapa = new THREE.SphereGeometry(Pi.r1, 12, 8);
    const pilones = E.pilones().map((s, i) => [s, colores[i % colores.length].hex])
      .concat(E.pilonesPuerta().map(s => [s, E.zona2.puerta.color.hex]));
    pilones.forEach(([s, hex]) => {
      const ct = document.createElement("canvas"); ct.width = 64; ct.height = 512;
      const gt = ct.getContext("2d");
      gt.fillStyle = hex; gt.fillRect(0, 0, 64, 512);
      for (let y = 0; y < 3; y++) for (let x = 0; x < 8; x++) { gt.fillStyle = (x + y) % 2 ? "#fff" : "#111"; gt.fillRect(x * 8, 40 + y * 8, 8, 8); }
      gt.fillStyle = "#fff"; gt.fillRect(0, 430, 64, 14);
      const p = new THREE.Mesh(gpil, new THREE.MeshLambertMaterial({ map: texSRGB(ct) }));
      p.position.set(s[1], Pi.alto / 2, -s[0]); esc.add(p);
      const t = new THREE.Mesh(gtapa, new THREE.MeshLambertMaterial({ color: new THREE.Color(hex) }));
      t.position.set(s[1], Pi.alto, -s[0]); esc.add(t);
    });
    // el aparcamiento: la furgoneta, la mesa del piloto y la manga de viento a rayas (sin carpa: tapaba la vista)
    const furgo = new THREE.Mesh(new THREE.BoxGeometry(2.0, 2.1, 4.8), lam(0xececec)); furgo.position.set(8, 1.05, 9); esc.add(furgo);
    const vent = new THREE.Mesh(new THREE.BoxGeometry(2.04, 0.7, 3.2), lam(0x2b3a48)); vent.position.set(8, 1.5, 9.3); esc.add(vent);
    const mesa = new THREE.Mesh(new THREE.BoxGeometry(1.6, 0.05, 0.7), lam(0xcfcfcf)); mesa.position.set(-7, 0.78, 7); esc.add(mesa);
    const mastil = new THREE.Mesh(new THREE.CylinderGeometry(0.03, 0.03, 4, 6), mEst); mastil.position.set(-14, 2, -10); esc.add(mastil);
    const [cmg, gmg] = lienzo(32, 128); for (let i = 0; i < 5; i++) { gmg.fillStyle = i % 2 ? "#ffffff" : "#ff6d00"; gmg.fillRect(0, i * 25.6, 32, 25.6); }
    this.manga = new THREE.Mesh(new THREE.ConeGeometry(0.25, 1.4, 12, 1, true), new THREE.MeshLambertMaterial({ map: texSRGB(cmg), side: THREE.DoubleSide }));
    this.manga.position.set(-14, 3.8, -10); esc.add(this.manga);
  }

  /** Mueve los coches de la autopista (dt en segundos). */
  _trafico(dt) {
    const T = this.trafico, M = new THREE.Matrix4(), Q = new THREE.Quaternion().setFromAxisAngle(new THREE.Vector3(0, 1, 0), T.ang), P = new THREE.Vector3(), S = new THREE.Vector3();
    const cx = (T.A.p0[0] + T.A.p1[0]) / 2, cz = -(T.A.p0[1] + T.A.p1[1]) / 2, c = Math.cos(T.ang), s = Math.sin(T.ang);
    T.s.forEach((v, i) => {
      v.u = (v.u + v.v * dt + T.L) % T.L;
      const a = v.u - T.L / 2, b = [-10.5, -4, 4, 10.5][v.carril];
      P.set(cx + a * c + b * s, T.A.alto + (v.camion ? 1.6 : 0.8), cz - a * s + b * c); S.set(v.camion ? 2.6 : 1, v.camion ? 2 : 1, v.camion ? 1.3 : 1);   // eje x girado: (c, 0, -s); lateral: (s, 0, c)
      T.malla.setMatrixAt(i, M.compose(P, Q, S));
    });
    T.malla.instanceMatrix.needsUpdate = true;
  }

  // =================== MUNDOS REALES (terreno SRTM + OpenStreetMap, carpeta mundos/) ===================
  /** Cambia al mundo real (datos de Mundos, ya activado en el Entorno) o vuelve a la isla (null). Cada mundo se
   *  construye una sola vez; el avion, su sombra y la manga pasan a la escena activa. */
  ponerMundo(mundo) {
    const id = mundo ? mundo.id : "isla";
    if (this.mundoId === id) return;
    if (!this.mundos[id]) this.mundos[id] = id === "isla" ? this.escenaIsla : this._construirMundo(mundo);
    const vieja = this.escena, nueva = this.mundos[id];
    for (const o of [this.avion && this.avion.grupo, this.sombra, this.manga]) if (o) { vieja.remove(o); nueva.add(o); }
    this.escena = nueva; this.mundoId = id; this.mundo = mundo;
    this.cam.far = mundo ? 16000 : 3000; this.cam.updateProjectionMatrix();
    this.ponerBase(mundo ? (this.baseNE || [0, 0]) : [0, 0], true);
  }

  /** Pista FPV de un entrenamiento del dron FPV (escenarios.js, "pista_fpv"; las reglas en js/pista_fpv.js), o null para
   *  quitarla: plataforma de salida, cilindro del estacionario, conos de colores, postes del slalom y del ocho, puertas
   *  numeradas con su flecha en el suelo, puerta alta y torre. Va en la isla, en la zona despejada de detras del piloto. */
  ponerPistaFpv(d) {
    if (this.pistaFpv) { this.escenaIsla.remove(this.pistaFpv); this.pistaFpv = null; }
    if (!d) return;
    const G = new THREE.Group(), P = FPV_PISTA, col = this.entorno.circuito.colores, lam = c => new THREE.MeshLambertMaterial({ color: c });
    const en = (o, N, E, y = 0) => { o.position.set(E, y, -N); G.add(o); return o; };
    const rayas = (c1, c2, n) => { const [c, g] = lienzo(8, 64); for (let i = 0; i < n; i++) { g.fillStyle = i % 2 ? c2 : c1; g.fillRect(0, i * 64 / n, 8, 64 / n); } return new THREE.MeshLambertMaterial({ map: texSRGB(c) }); };
    // plataforma de salida: chapa oscura con el borde naranja y una H blanca
    const [cp, gp] = lienzo(128, 128); gp.fillStyle = "#ff6d00"; gp.fillRect(0, 0, 128, 128); gp.fillStyle = "#2b2b2b"; gp.fillRect(8, 8, 112, 112);
    gp.fillStyle = "#fff"; gp.fillRect(38, 30, 12, 68); gp.fillRect(78, 30, 12, 68); gp.fillRect(38, 58, 52, 12);
    const pad = en(new THREE.Mesh(new THREE.BoxGeometry(2.4, 0.06, 2.4), [lam(0x2b2b2b), lam(0x2b2b2b), new THREE.MeshLambertMaterial({ map: texSRGB(cp) }), lam(0x2b2b2b), lam(0x2b2b2b), lam(0x2b2b2b)]), d.salida[0], d.salida[1], 0.03);
    pad.rotation.y = Math.PI;                                        // la H se lee mirando al sur, como el piloto
    const anillo = (N, E, r, c, y = 0.04) => { const m = new THREE.Mesh(new THREE.RingGeometry(r - 0.07, r + 0.07, 48), new THREE.MeshBasicMaterial({ color: c, side: THREE.DoubleSide })); m.rotation.x = -Math.PI / 2; return en(m, N, E, y); };
    if (d.cilindro) {                                                 // cilindro translucido del estacionario, con sus circulos
      const c = d.cilindro, m = new THREE.Mesh(new THREE.CylinderGeometry(c.r, c.r, c.h1 - c.h0, 40, 1, true),
        new THREE.MeshBasicMaterial({ color: 0x29b6f6, transparent: true, opacity: 0.22, side: THREE.DoubleSide, depthWrite: false }));
      en(m, c.n, c.e, (c.h0 + c.h1) / 2); anillo(c.n, c.e, c.r, 0x29b6f6); anillo(c.n, c.e, c.r, 0x29b6f6, c.h0); anillo(c.n, c.e, c.r, 0x29b6f6, c.h1);
    }
    (d.conos || []).forEach((q, i) => {                               // conos de los colores del circuito, con el circulo donde se tocan
      const hex = col[i % col.length].hex;
      en(new THREE.Mesh(new THREE.ConeGeometry(0.28, 0.7, 20), lam(new THREE.Color(hex))), q[0], q[1], 0.35);
      en(new THREE.Mesh(new THREE.CylinderGeometry(0.2, 0.235, 0.12, 20), lam(0xffffff)), q[0], q[1], 0.33);
      anillo(q[0], q[1], P.CONO_R, new THREE.Color(hex));
    });
    (d.postes || []).forEach(q => en(new THREE.Mesh(new THREE.CylinderGeometry(P.POSTE.r, P.POSTE.r, P.POSTE.alto, 10), rayas("#e53935", "#ffffff", 8)), q[0], q[1], P.POSTE.alto / 2));
    (d.ocho || []).forEach((q, i) => {                                // postes del ocho: rojo y azul, con banderin
      const hex = col[P.COLOR_OCHO[i]].hex;
      en(new THREE.Mesh(new THREE.CylinderGeometry(P.OCHO.r, P.OCHO.r, P.OCHO.alto, 10), rayas(hex, "#ffffff", 10)), q[0], q[1], P.OCHO.alto / 2);
      en(new THREE.Mesh(new THREE.PlaneGeometry(0.8, 0.5), new THREE.MeshLambertMaterial({ color: new THREE.Color(hex), side: THREE.DoubleSide })), q[0], q[1], P.OCHO.alto - 0.3).position.x += 0.4;
    });
    // puertas: marco de tubo, numero arriba (por las dos caras) y flecha en el suelo antes de la puerta
    const puerta = (g, color, texto) => {
      const gr = P.GROSOR, H1 = g.h0 + g.alto, A = g.ancho / 2, P0 = new THREE.Group(), m = lam(color);
      for (const s of [-1, 1]) { const pie = new THREE.Mesh(new THREE.BoxGeometry(gr, H1 + gr, gr), m); pie.position.set(s * (A + gr / 2), (H1 + gr) / 2, 0); P0.add(pie); }
      const arriba = new THREE.Mesh(new THREE.BoxGeometry(g.ancho + 2 * gr, gr, gr), m); arriba.position.y = H1 + gr / 2; P0.add(arriba);
      if (g.h0 > 0) { const abajo = new THREE.Mesh(new THREE.BoxGeometry(g.ancho + 2 * gr, gr, gr), m); abajo.position.y = g.h0 - gr / 2; P0.add(abajo); }
      const [cn, gn] = lienzo(128, 96); gn.fillStyle = "#111"; gn.fillRect(0, 0, 128, 96); gn.fillStyle = "#fff"; gn.font = "bold 76px sans-serif"; gn.textAlign = "center"; gn.textBaseline = "middle"; gn.fillText(texto, 64, 52);
      for (const lado of [0, Math.PI]) { const pl = new THREE.Mesh(new THREE.PlaneGeometry(0.8, 0.6), new THREE.MeshBasicMaterial({ map: texSRGB(cn) })); pl.position.y = H1 + gr + 0.32; pl.rotation.y = lado; P0.add(pl); }
      const fl = new THREE.Mesh(new THREE.ShapeGeometry(new THREE.Shape([new THREE.Vector2(-0.5, 0), new THREE.Vector2(0.5, 0), new THREE.Vector2(0, 1.1)])), new THREE.MeshBasicMaterial({ color: 0xffffff, side: THREE.DoubleSide }));
      fl.rotation.x = -Math.PI / 2; fl.position.set(0, 0.03, 2.6); P0.add(fl);   // la punta hacia la puerta (-z local = sentido de paso)
      P0.rotation.y = -g.rumbo * D2R; en(P0, g.n, g.e);
    };
    new PistaFpv(d, () => {}).puertas().forEach((g, i) => puerta(g, 0xff6d00, String(i + 1)));
    if (d.puerta_alta) puerta(d.puerta_alta, 0xd81b60, "▲");
    if (d.torre) {                                                    // torre de andamio galvanizado con baliza arriba
      const q = d.torre, l = q.lado / 2, mt = lam(0xb8bcc0);
      for (const [a, b] of [[-l, -l], [-l, l], [l, -l], [l, l]]) en(new THREE.Mesh(new THREE.CylinderGeometry(0.05, 0.05, q.alto, 8), mt), q.n + a, q.e + b, q.alto / 2);
      for (let y = 2.5; y <= q.alto; y += 2.5) {
        for (const a of [-l, l]) { en(new THREE.Mesh(new THREE.BoxGeometry(0.05, 0.05, q.lado), mt), q.n + a, q.e, y); en(new THREE.Mesh(new THREE.BoxGeometry(q.lado, 0.05, 0.05), mt), q.n, q.e + a, y); }
      }
      en(new THREE.Mesh(new THREE.BoxGeometry(q.lado, 0.1, q.lado), lam(0x8d6e63)), q.n, q.e, q.alto);
      en(new THREE.Mesh(new THREE.SphereGeometry(0.18, 12, 8), new THREE.MeshBasicMaterial({ color: 0xff1744 })), q.n, q.e, q.alto + 0.3);
    }
    if (d.recta) {                                                    // conos naranjas en las cuatro esquinas del pasillo de la recta
      const R = d.recta, w = R.ancho / 2 + R.margen;
      for (const e of [R.e0, R.e1]) for (const s of [-1, 1]) en(new THREE.Mesh(new THREE.ConeGeometry(0.25, 0.6, 16), lam(0xff6d00)), R.n + s * w, e, 0.3);
    }
    G.traverse(o => { if (o.isMesh) { o.castShadow = true; o.receiveShadow = true; } });
    this.pistaFpv = G; this.escenaIsla.add(G);
  }

  /** Multijugador: los demas de la sala como "fantasmas", con su modelo y su nombre encima. lista: [{id, avion, nombre,
   *  p, q, vn, recibido (performance.now() al llegar)}]. La posicion es la ultima recibida avanzada con su velocidad (como
   *  mucho 0,3 s) y suavizada; la actitud, la recibida. */
  ponerFantasmas(lista) {
    this.fantasmas = this.fantasmas || new Map();
    const vivos = new Set(), ahora = performance.now();
    for (const f of lista || []) {
      vivos.add(f.id);
      let g = this.fantasmas.get(f.id);
      if (!g || g.avion !== f.avion || g.nombre !== f.nombre) {
        if (g) g.obj.grupo.parent && g.obj.grupo.parent.remove(g.obj.grupo);
        const datos = Modelos.datos(f.avion); if (!datos) continue;
        const obj = construirAvion(datos); obj.grupo.matrixAutoUpdate = false;
        const [c, x] = lienzo(256, 48); x.font = "bold 26px sans-serif"; x.textAlign = "center"; x.textBaseline = "middle";
        x.lineWidth = 6; x.strokeStyle = "rgba(0,0,0,0.75)"; x.strokeText(f.nombre, 128, 24); x.fillStyle = "#4fc3f7"; x.fillText(f.nombre, 128, 24);
        const et = new THREE.Sprite(new THREE.SpriteMaterial({ map: texSRGB(c), sizeAttenuation: false, depthTest: false, transparent: true }));
        et.scale.set(0.16, 0.03, 1);
        g = { obj, avion: f.avion, nombre: f.nombre, p: f.p.slice(), et };
        this.fantasmas.set(f.id, g);
      }
      if (g.obj.grupo.parent !== this.escena) { this.escena.add(g.obj.grupo); this.escena.add(g.et); }
      const dt = Math.min(0.3, (ahora - f.recibido) / 1000), obj = [0, 1, 2].map(i => f.p[i] + (f.vn ? f.vn[i] : 0) * dt);
      const lejos = Math.hypot(obj[0] - g.p[0], obj[1] - g.p[1], obj[2] - g.p[2]) > 30;
      for (let i = 0; i < 3; i++) g.p[i] = lejos ? obj[i] : g.p[i] + (obj[i] - g.p[i]) * 0.35;
      const q = f.q, ex = ned2three(Cuat.rot(q, [1, 0, 0])), ey = ned2three(Cuat.rot(q, [0, 1, 0])), ez = ned2three(Cuat.rot(q, [0, 0, 1])), t = ned2three(g.p);
      g.obj.grupo.matrix.set(ex[0], ey[0], ez[0], t[0], ex[1], ey[1], ez[1], t[1], ex[2], ey[2], ez[2], t[2], 0, 0, 0, 1);
      if (g.obj.helice) g.obj.helice.visible = (f.gas || 0) > 0.05;
      g.et.position.set(t[0], t[1] + 1.2, t[2]);
    }
    for (const [id, g] of [...this.fantasmas]) if (!vivos.has(id)) { g.obj.grupo.parent && g.obj.grupo.parent.remove(g.obj.grupo); g.et.parent && g.et.parent.remove(g.et); this.fantasmas.delete(id); }
  }

  /** Multijugador: zonas de exclusion que marca el profesor ([{N, E, r}]): cilindros rojos translucidos del suelo a 120 m. */
  ponerExclusiones(zonas) {
    if (this.exclusiones) { this.exclusiones.parent && this.exclusiones.parent.remove(this.exclusiones); this.exclusiones = null; }
    if (!zonas || !zonas.length) return;
    const G = new THREE.Group(), mat = new THREE.MeshBasicMaterial({ color: 0xe53935, transparent: true, opacity: 0.18, side: THREE.DoubleSide, depthWrite: false });
    const borde = new THREE.MeshBasicMaterial({ color: 0xe53935, transparent: true, opacity: 0.7, side: THREE.DoubleSide, depthWrite: false });
    for (const z of zonas) {
      const y = this.mundo ? this.entorno.altura(z.N, z.E) : 0, c = new THREE.Mesh(new THREE.CylinderGeometry(z.r, z.r, 120, 48, 1, true), mat);
      c.position.set(z.E, y + 60, -z.N); c.renderOrder = 5; G.add(c);
      for (const h of [0.5, 120]) { const a = new THREE.Mesh(new THREE.RingGeometry(z.r - 0.6, z.r + 0.6, 64), borde); a.rotation.x = -Math.PI / 2; a.position.set(z.E, y + h, -z.N); G.add(a); }
    }
    this.exclusiones = G; this.escena.add(G);
  }

  /** Punto de lanzamiento (N, E) en un mundo real: ahi van el piloto (camara 1), la manga y los arboles cercanos.
   *  En la isla siempre es el origen. */
  ponerBase(NE, forzar) {
    const [N, E] = NE, mundo = this.mundo;
    this.baseNE = NE;
    const h = mundo ? this.entorno.altura(N, E) : 0;
    this.base = [E, h, -N];
    this.manga.position.set(E - 14, h + 3.8, -N - 10);
    if (mundo && (forzar || !this.arbolesNE || Math.hypot(this.arbolesNE[0] - N, this.arbolesNE[1] - E) > 1500)) this._arbolesMundo(this.escena, mundo, N, E);
  }

  /** Parcela agricola en (E, N): el campo es un mosaico de parcelas rectangulares giradas 12 grados, de 220 m, cada
   *  una con su uso (0 almendros en hileras, 1 secano, 2 regadio, 3 barbecho, 4 erial) y su tono, deterministas. */
  static parcela(E, N) {
    const S = 220, c = 0.978, s = 0.208, u = E * c + N * s, v = -E * s + N * c, i = Math.floor(u / S), j = Math.floor(v / S);
    let h = (i * 73856093) ^ (j * 19349663); h = (h ^ (h >>> 13)) * 1274126177; h = (h ^ (h >>> 16)) >>> 0;
    const r = (h % 1000) / 1000, r2 = ((h >>> 10) % 1000) / 1000;
    return { tipo: r < 0.34 ? 0 : r < 0.62 ? 1 : r < 0.78 ? 2 : r < 0.9 ? 3 : 4, tono: r2, u: u - i * S, v: v - j * S, S };
  }

  /** Textura del suelo de un mundo real, pintada pixel a pixel (26 m por pixel) como una foto de satelite: mar (y el
   *  Mar Menor mas claro), playas, parcelas en la llanura, monte bajo y roca con la altura y la pendiente, y las
   *  zonas urbanas de OSM encima. Tambien es el fondo del GPS. */
  _texturaMundo(m) {
    const T = m.terreno, H = this.entorno.terreno.H, W = 3072, Hh = Math.round(W * (T.nN - 1) / (T.nE - 1));
    const [c, g] = lienzo(W, Hh), img = g.createImageData(W, Hh), D = img.data, mpx = (T.nE - 1) * T.paso / W;
    const hash = (x, y) => { let h = (x * 374761393) ^ (y * 668265263); h = (h ^ (h >>> 13)) * 1274126177; return ((h ^ (h >>> 16)) >>> 0) / 4294967296; };
    const ruido = (E, N, esc) => { const x = E / esc, y = N / esc, x0 = Math.floor(x), y0 = Math.floor(y), fx = x - x0, fy = y - y0;   // ruido de valor bilineal
      return hash(x0, y0) * (1 - fx) * (1 - fy) + hash(x0 + 1, y0) * fx * (1 - fy) + hash(x0, y0 + 1) * (1 - fx) * fy + hash(x0 + 1, y0 + 1) * fx * fy; };
    const USOS = [[0x7f, 0x8e, 0x4a], [0xc8, 0xa0, 0x66], [0x6f, 0x96, 0x44], [0xb9, 0x8a, 0x5c], [0xc7, 0xb4, 0x8e]];   // almendros, secano, regadio, barbecho, erial
    for (let y = 0; y < Hh; y++) {
      const N = T.N0 + (Hh - 1 - y) * mpx, i = Math.min(T.nN - 1.001, (N - T.N0) / T.paso), i0 = Math.floor(i), fi = i - i0;
      for (let x = 0; x < W; x++) {
        const E = T.E0 + x * mpx, j = Math.min(T.nE - 1.001, (E - T.E0) / T.paso), j0 = Math.floor(j), fj = j - j0, k = i0 * T.nE + j0;
        const h = H[k] * (1 - fi) * (1 - fj) + H[k + T.nE] * fi * (1 - fj) + H[k + 1] * (1 - fi) * fj + H[k + T.nE + 1] * fi * fj;
        const pend = Math.min(1, (Math.abs(H[k + 1] - H[k]) + Math.abs(H[k + T.nE] - H[k])) / T.paso * 2.5);
        let r, gg, b;
        const fAgua = this.entorno.agua ? (this.entorno.agua[k] * (1 - fi) * (1 - fj) + this.entorno.agua[k + T.nE] * fi * (1 - fj) + this.entorno.agua[k + 1] * (1 - fi) * fj + this.entorno.agua[k + T.nE + 1] * fi * fj) : (h <= 0.2 ? 1 : 0);
        const agua = fAgua > 0.7;                                          // mismo umbral que Entorno.enMar
        if (agua) {                                                          // mar (segun la costa de OSM); el Mar Menor (laguna), mas claro y verdoso
          const Lg = this.entorno.laguna, n = ruido(E, N, 900) * 0.12;
          const fl = Lg ? Lg[k] * (1 - fi) * (1 - fj) + Lg[k + T.nE] * fi * (1 - fj) + Lg[k + 1] * (1 - fi) * fj + Lg[k + T.nE + 1] * fi * fj : 0;   // mezcla suave en las golas
          r = (24 + n * 40) * (1 - fl) + (60 + n * 80) * fl; gg = (70 + n * 50) * (1 - fl) + (150 + n * 60) * fl; b = (125 + n * 30) * (1 - fl) + 170 * fl;
        } else if (h < 4 && fAgua > 0.04) { r = 215; gg = 200; b = 160; }   // playas y saladares: solo junto al agua
        else {
          const n1 = ruido(E, N, 140), n2 = ruido(E, N, 35), llano = h < 110 && pend < 0.35;
          if (llano) {
            const P = Visor.parcela(E, N), base = USOS[P.tipo], t = 0.82 + P.tono * 0.36;
            r = base[0] * t; gg = base[1] * t; b = base[2] * t;
            if (P.tipo === 0 && Math.floor(P.u / 14) % 2 === 0) { r *= 0.86; gg *= 0.86; b *= 0.86; }   // hileras de almendros
            if (P.u < 12 || P.v < 12) { r *= 0.8; gg *= 0.8; b *= 0.8; }                           // lindes y caminos
            const mezcla = Math.min(1, Math.max(0, (h - 70) / 40 + pend * 2));                      // hacia el monte en los bordes
            r = r * (1 - mezcla) + 150 * mezcla; gg = gg * (1 - mezcla) + 135 * mezcla; b = b * (1 - mezcla) + 95 * mezcla;
          } else {
            const alto = Math.min(1, Math.max(0, (h - 250) / 350));                                 // monte bajo -> roca
            r = 140 + alto * 30 - n1 * 40; gg = 128 - alto * 10 - n1 * 35; b = 85 + alto * 25 - n1 * 20;
            if (n2 > 0.72 && alto < 0.6) { r -= 35; gg -= 15; b -= 20; }                           // manchas de pinar y matorral
            const sombra = 1 - pend * 0.35; r *= sombra; gg *= sombra; b *= sombra;
          }
          const grano = 0.92 + n2 * 0.16; r *= grano; gg *= grano; b *= grano;
        }
        const p = 4 * (y * W + x); D[p] = r; D[p + 1] = gg; D[p + 2] = b; D[p + 3] = 255;
      }
    }
    g.putImageData(img, 0, 0);
    const X = e => (e - T.E0) / mpx, Y = n => Hh - 1 - (n - T.N0) / mpx;
    g.fillStyle = "rgb(58,110,150)";                                                                  // balsas de riego, lagunas, embalses (OSM)
    for (const a of m.agua || []) { g.beginPath(); for (let i = 0; i < a.length; i += 2) i === 0 ? g.moveTo(X(a[i]), Y(a[i + 1])) : g.lineTo(X(a[i]), Y(a[i + 1])); g.closePath(); g.fill(); }
    for (const u of m.urbano) {                                                                       // zonas urbanas
      g.fillStyle = u[0] === 1 ? "rgba(206,198,186,0.92)" : "rgba(190,190,188,0.92)"; g.beginPath();
      for (let i = 1; i < u.length; i += 2) i === 1 ? g.moveTo(X(u[i]), Y(u[i + 1])) : g.lineTo(X(u[i]), Y(u[i + 1]));
      g.closePath(); g.fill();
    }
    this.lienzoMundo = c; this.lienzoMundoX = X; this.lienzoMundoY = Y;
    const tex = texSRGB(c); tex.anisotropy = Math.min(8, this.renderer.capabilities.getMaxAnisotropy()); tex.minFilter = THREE.LinearMipmapLinearFilter;
    return tex;
  }

  /** Escena de un mundo real: cielo grande con niebla (calima a 2,5-10 km: asi no hay que dibujar 80 km), malla
   *  del terreno con color por altura y pendiente, mar, carreteras en cinta, edificios en las zonas urbanas de OSM,
   *  arboles en el campo hasta 9 km del origen y rotulos de los pueblos. Todo instanciado por celdas. */
  _construirMundo(m) {
    const esc = new THREE.Scene(), alt = this.entorno.altura, ent = this.entorno, h0 = m.terreno.h0;
    esc.background = new THREE.Color(0xcfdbe6); esc.fog = new THREE.Fog(0xcfdbe6, 2500, 10500);
    esc.add(new THREE.HemisphereLight(0xd9e8ff, 0x8a6a4a, 0.75 * 2 * Math.PI));
    const sol = new THREE.DirectionalLight(0xfff1dc, 1.0 * 2 * Math.PI); sol.position.set(-3500, 5200, 2600); esc.add(sol);
    this._configurarSol(sol, esc);
    this._cielo(sol.position, esc, 15000);
    const T = m.terreno, HT = ent.terreno.H, r = semilla(11);
    // --- terreno: una malla con color por vertice ---
    // --- terreno: una malla con la textura de satelite sintetica y un sombreado por pendiente en los vertices ---
    const nN = T.nN, nE = T.nE, pos = new Float32Array(nN * nE * 3), col = new Float32Array(nN * nE * 3), uv = new Float32Array(nN * nE * 2);
    for (let i = 0; i < nN; i++) for (let j = 0; j < nE; j++) {
      const k = i * nE + j, h = HT[k], N = T.N0 + i * T.paso, E = T.E0 + j * T.paso;
      // agua: junto a la costa a -1,5 m (la superficie cruza el nivel del mar dentro de la celda y una franja de tierra
      // de una sola celda, como La Manga, sigue viendose); mar adentro, -7 m
      const agua = ent.agua ? ent.agua[k] : h <= 0;
      let y = Math.max(h, 1);
      if (agua) {
        let orilla = false;
        for (let di = -1; di <= 1 && !orilla; di++) for (let dj = -1; dj <= 1; dj++) { const ii = i + di, jj = j + dj; if (ii >= 0 && ii < nN && jj >= 0 && jj < nE && !(ent.agua ? ent.agua[ii * nE + jj] : HT[ii * nE + jj] <= 0)) { orilla = true; break; } }
        y = orilla ? -1.5 : -7;
      }
      pos[3 * k] = E; pos[3 * k + 1] = y - h0; pos[3 * k + 2] = -N;
      uv[2 * k] = j / (nE - 1); uv[2 * k + 1] = i / (nN - 1);
      const hx = (HT[k + (j < nE - 1 ? 1 : 0)] - HT[k - (j > 0 ? 1 : 0)]) / (2 * T.paso), hy = (HT[k + (i < nN - 1 ? nE : 0)] - HT[k - (i > 0 ? nE : 0)]) / (2 * T.paso);
      const pend = Math.min(1, Math.hypot(hx, hy) * 2.2), s = (1 - pend * 0.3) * (0.96 + 0.08 * r());
      col[3 * k] = s; col[3 * k + 1] = s; col[3 * k + 2] = s;
    }
    const idx = new Uint32Array((nN - 1) * (nE - 1) * 6); let q = 0;
    for (let i = 0; i < nN - 1; i++) for (let j = 0; j < nE - 1; j++) { const a = i * nE + j, b = a + 1, c = a + nE, d = c + 1; idx[q++] = a; idx[q++] = b; idx[q++] = c; idx[q++] = b; idx[q++] = d; idx[q++] = c; }
    const gt = new THREE.BufferGeometry(); gt.setAttribute("position", new THREE.BufferAttribute(pos, 3)); gt.setAttribute("color", new THREE.BufferAttribute(col, 3));
    gt.setAttribute("uv", new THREE.BufferAttribute(uv, 2)); gt.setIndex(new THREE.BufferAttribute(idx, 1)); gt.computeVertexNormals();
    esc.add(new THREE.Mesh(gt, new THREE.MeshLambertMaterial({ map: this._texturaMundo(m), vertexColors: true })));
    // --- mar: plano al nivel del mar, con el brillo del sol ---
    // sin agua de espejo: en costas bajas como La Manga tapaba la tierra a ratos (redibuja la escena y alternaba cada
    // segundo con el plano). El agua, 0,3 m bajo el nivel del mar: la tierra va a 1 m como minimo, sin pelearse con ella
    this._mar(esc, -h0 - 0.3, 300000, 0x1d5580, false);
    this._lagunaTransparente(this.aguas[this.aguas.length - 1].plano, T);
    // --- carreteras (cintas) y edificios genericos de las zonas urbanas de OSM: visor_real.js los rehace sin la
    // zona de detalle, donde ya estan los de verdad ---
    this.zonaBBox = null; this.zonasBBox = [];
    if (this._carreterasMundo) { this._carreterasMundo(esc, m); this._edificiosSinteticos(esc, m); }
    else this._cintas(esc, m.carreteras, alt);
    this._arbolesMundo(esc, m, 0, 0);
    // --- rotulos de los pueblos (ciudades y pueblos, no aldeas): tamano fijo en pantalla (se reescalan en dibujar), texto con borde ---
    this.rotulos = [];
    for (const [nombre, rango, e, n] of m.lugares) {
      if (rango > 3) continue;
      const [c, g] = lienzo(1024, 256); g.font = "bold 84px sans-serif"; g.textAlign = "center"; g.textBaseline = "middle";
      g.lineWidth = 14; g.strokeStyle = "rgba(0,0,0,0.8)"; g.lineJoin = "round"; g.strokeText(nombre, 512, 128); g.fillStyle = "#fff"; g.fillText(nombre, 512, 128);
      const sp = new THREE.Sprite(new THREE.SpriteMaterial({ map: texSRGB(c), transparent: true, depthTest: false, fog: false, sizeAttenuation: false }));
      sp.userData.px = rango === 1 ? 64 : rango === 2 ? 52 : 44;               // alto en pixeles (ciudad, pueblo, pedania)
      sp.position.set(e, alt(n, e) + (rango === 1 ? 300 : 120), -n); esc.add(sp); this.rotulos.push(sp);
    }
    esc.traverse(o => { if (o.isMesh && !o.isSprite) o.receiveShadow = true; });
    if (this._despuesDeConstruirMundo) this._despuesDeConstruirMundo(esc, m);    // visor_real.js: ortofoto de la region
    return esc;
  }

  /** Arboles de un mundo real alrededor de (cN, cE): almendros en hileras en las parcelas de almendros hasta 2,2 km y
   *  sueltos (pinos en el monte) hasta 9 km (mas lejos lo tapa la calima). Se rehacen al cambiar el punto de lanzamiento. */
  _arbolesMundo(esc, m, cN, cE) {
    for (const o of esc.userData.arboles || []) { esc.remove(o); o.geometry.dispose(); const i = this.lejanos.indexOf(o); if (i >= 0) this.lejanos.splice(i, 1); }
    esc.userData.arboles = []; this.arbolesNE = [cN, cE];
    const ent = this.entorno, alt = ent.altura, r = semilla(11 + Math.round(cN / 97) + Math.round(cE / 89)), antes = new Set(esc.children);
    const lam = (c, extra) => new THREE.MeshLambertMaterial(Object.assign({ color: c }, extra || {}));
    const arboles = [], apto = (nn, ee) => {
      if (this._enZonas(nn, ee, 20)) return 0;
      const h = ent.alturaMar(nn, ee); if (h <= 1 || h > 450 || ent.enMar(nn, ee)) return 0;
      const pend = Math.abs(ent.alturaMar(nn + 60, ee) - ent.alturaMar(nn - 60, ee)) + Math.abs(ent.alturaMar(nn, ee + 60) - ent.alturaMar(nn, ee - 60));
      return pend > 40 ? 0 : h;
    };
    // hasta 2,2 km: almendros en hileras (14 m) dentro de las parcelas de almendros de la textura
    const c12 = 0.978, s12 = 0.208;
    for (let n = -2200; n <= 2200; n += 14) for (let e = -2200; e <= 2200; e += 14) {
      const ee = cE + e * c12 - n * s12, nn = cN + e * s12 + n * c12;       // la malla de plantacion va girada como las parcelas
      if (Math.hypot(ee - cE, nn - cN) > 2200) continue;
      const P = Visor.parcela(ee, nn); if (P.tipo !== 0 || P.u < 12 || P.v < 12) continue;
      const h = apto(nn, ee); if (!h || h > 110) continue;
      const a = [ee + (r() - 0.5) * 2, nn + (r() - 0.5) * 2, 0.75 + r() * 0.35, 0];
      if (Math.hypot(a[0] - cE, a[1] - cN) >= 25) arboles.push(a);          // claro de 25 m en el punto de salida
    }
    // mas lejos: sueltos (almendros en la llanura, pinos en el monte), hasta 9 km (mas alla lo tapa la calima)
    for (let n = -9000; n <= 9000; n += 70) for (let e = -9000; e <= 9000; e += 70) {
      const ee = cE + e + (r() - 0.5) * 60, nn = cN + n + (r() - 0.5) * 60, d = Math.hypot(e, n);
      if (d > 9000 || d < 2200 || arboles.length >= 34000) continue;
      const h = apto(nn, ee); if (!h) continue;
      const P = Visor.parcela(ee, nn), monte = h > 110, prob = monte ? 0.3 : P.tipo === 0 ? 0.6 : 0.08;
      if (r() < prob * (d < 6000 ? 1 : 0.55)) arboles.push([ee, nn, 0.6 + r() * 0.8, monte && r() < 0.7 ? 1 : 0]);
    }
    const copa = new THREE.ConeGeometry(2.4, 3.6, 6, 1, true); copa.translate(0, 1.8, 0);     // sin base: 6 triangulos por arbol
    this._instanciarEn(esc, copa, lam(0xffffff), arboles, (it, M, Cc) => {
      const [e, n, s, pino] = it;
      M.compose(new THREE.Vector3(e, alt(n, e), -n), new THREE.Quaternion(), new THREE.Vector3(s * (pino ? 0.8 : 1), s * (pino ? 2.2 : 1), s * (pino ? 0.8 : 1)));
      Cc.setHex(pino ? 0x3b5f34 : [0x6e8a44, 0x76924a, 0x66823e][Math.floor(s * 7) % 3]);
    }, 1000, 4000, [cE, -cN]);
    for (const o of esc.children) if (!antes.has(o)) esc.userData.arboles.push(o);
    // solidos (Entorno.chocaArbol): el cono de la copa, de 2,4 s de radio abajo (1,9 s en los pinos) y 3,6 s de alto (7,9 s)
    ent.ponerArboles("region", arboles.map(([e, n, s, pino]) => { const y = alt(n, e); return [e, n, (pino ? 1.3 : 1.6) * s, y, y + (pino ? 7.9 : 3.6) * s]; }));
  }

  /** Cintas de carretera: dos vertices por punto, a 1 m sobre el terreno, subdivididas a 120 m para seguirlo. */
  _cintas(esc, carreteras, alt) {
    const W = { 1: 11, 2: 6.5, 3: 5, 4: 4 }, CL = { 1: new THREE.Color(0xe6dfca), 2: new THREE.Color(0xd8d0b3), 3: new THREE.Color(0xc7c2ad), 4: new THREE.Color(0xb6b2a0) };
    const pos = [], col = [], idx = [];
    for (const c of carreteras) {
      const t = c[0], w = W[t], color = CL[t], pts = [];
      for (let i = 1; i < c.length; i += 2) pts.push([c[i], c[i + 1]]);
      const P = [];
      for (let i = 0; i < pts.length; i++) {
        if (i) { const [e0, n0] = pts[i - 1], [e1, n1] = pts[i], k = Math.ceil(Math.hypot(e1 - e0, n1 - n0) / 120); for (let j = 1; j < k; j++) P.push([e0 + (e1 - e0) * j / k, n0 + (n1 - n0) * j / k]); }
        P.push(pts[i]);
      }
      const base = pos.length / 3;
      for (let i = 0; i < P.length; i++) {
        const [e, n] = P[i], [ea, na] = P[Math.max(0, i - 1)], [eb, nb] = P[Math.min(P.length - 1, i + 1)];
        let dx = eb - ea, dz = -(nb - na); const L = Math.hypot(dx, dz) || 1; dx /= L; dz /= L;
        const nx = -dz, nz = dx, y = alt(n, e) + 1.0;
        pos.push(e + nx * w, y, -n + nz * w, e - nx * w, y, -n - nz * w);
        col.push(color.r, color.g, color.b, color.r, color.g, color.b);
        if (i) { const b = base + 2 * i; idx.push(b - 2, b, b - 1, b - 1, b, b + 1); }
      }
    }
    const g = new THREE.BufferGeometry();
    g.setAttribute("position", new THREE.Float32BufferAttribute(pos, 3)); g.setAttribute("color", new THREE.Float32BufferAttribute(col, 3)); g.setIndex(idx);
    const nor = new Float32Array(pos.length); for (let i = 1; i < nor.length; i += 3) nor[i] = 1;      // hacia arriba: sin normales la luz las pinta negras
    g.setAttribute("normal", new THREE.BufferAttribute(nor, 3));
    const malla = new THREE.Mesh(g, new THREE.MeshLambertMaterial({ vertexColors: true, side: THREE.DoubleSide, polygonOffset: true, polygonOffsetFactor: -2, polygonOffsetUnits: -2 }));
    malla.receiveShadow = true; esc.add(malla); return malla;
  }

  /** Como _instanciar, pero en la escena que se diga, con celdas de `celda` m, y las celdas a mas de lejos_m del
   *  origen van a this.lejanos (solo con calidad 2). */
  _instanciarEn(esc, geom, mat, lista, colocar, celda, lejos_m = Infinity, centro = [0, 0]) {
    const celdas = new Map();
    for (const it of lista) { const k = Math.floor(it[0] / celda) + "," + Math.floor(it[1] / celda); if (!celdas.has(k)) celdas.set(k, []); celdas.get(k).push(it); }
    const M = new THREE.Matrix4(), C = new THREE.Color();
    for (const items of celdas.values()) {
      const g = geom.clone(), m = new THREE.InstancedMesh(g, mat, items.length);
      let cx = 0, cz = 0, ymin = Infinity, ymax = -Infinity;
      items.forEach((it, i) => { colocar(it, M, C); m.setMatrixAt(i, M); m.setColorAt(i, C); cx += it[0]; cz -= it[1]; ymin = Math.min(ymin, M.elements[13]); ymax = Math.max(ymax, M.elements[13]); });
      cx /= items.length; cz /= items.length;
      let rad = 0; for (const it of items) rad = Math.max(rad, Math.hypot(it[0] - cx, -it[1] - cz));
      // esfera envolvente de la celda en el propio InstancedMesh (coordenadas del objeto = mundo, el padre no se mueve).
      // OJO: no ponerla en la geometria: Three la multiplica por cada matriz de instancia y sale una esfera absurda, y
      // segun la escala de las instancias el recorte de camara (frustum) oculta la malla entera (los troncos no se veian)
      m.boundingSphere = new THREE.Sphere(new THREE.Vector3(cx, (ymin + ymax) / 2, cz), Math.hypot(rad, (ymax - ymin) / 2) + 120);
      esc.add(m);
      if (Math.hypot(cx - centro[0], cz - centro[1]) > lejos_m) this.lejanos.push(m);
    }
  }

  /** Pone en la escena el avion de un modelo (quita el anterior). */
  ponerAvion(datos) {
    if (this.avion) this.escena.remove(this.avion.grupo);
    this.avion = construirAvion(datos);
    this.avion.envergadura = datos.b_m || 1;           // para el zoom de la camara del piloto
    this.avion.grupo.matrixAutoUpdate = false;
    this.escena.add(this.avion.grupo);
  }

  /** Coloca el avion, sus mandos, la sombra, la manga y la camara segun el estado, y dibuja. */
  dibujar(av) {
    const ahora = performance.now(), dtReal = (ahora - (this._tAnt || ahora)) / 1000, dt = Math.min(0.1, dtReal); this._tAnt = ahora;
    if (!this.mundo) this._trafico(dt);
    this._vigilarCalidad(dtReal);
    const a = this.avion;
    if (a) {
      const q = av.q, ex = ned2three(Cuat.rot(q, [1, 0, 0])), ey = ned2three(Cuat.rot(q, [0, 1, 0])), ez = ned2three(Cuat.rot(q, [0, 0, 1]));
      const t = ned2three(av.p);
      a.grupo.matrix.set(ex[0], ey[0], ez[0], t[0], ex[1], ey[1], ez[1], t[1], ex[2], ey[2], ez[2], t[2], 0, 0, 0, 1);
      a.prof.rotation.y = av.de;           // + = borde de fuga abajo
      a.timon.rotation.z = -av.dr;         // + = borde de fuga a la derecha
      for (const al of a.alerones) al.setRotationFromAxisAngle(al.eje, al.signo * (av.da || 0) + (al.prof ? av.de : 0));   // + = aleron derecho arriba
      a.helice.visible = av.gases > 0.05;
      // luces: en el suelo con los motores parados, apagadas; "lento" (navegacion) 1 Hz, "estrobo" dos destellos por segundo
      // el sprite sin atenuacion se proyecta a scale / tan(fov/2) del semialto de la pantalla: se reescala a unos 12 px sea cual sea el zoom
      const tl = (ahora / 1000) % 1, enc = av.estado !== "en mano", sc = 16 * 2 * Math.tan(this.cam.fov / 2 * Math.PI / 180) / this.renderer.domElement.height;
      for (const l of a.luces) { l.visible = enc && (l.patron === "lento" ? tl < 0.5 : l.patron === "estrobo" ? tl < 0.06 || (tl > 0.15 && tl < 0.21) : true); l.children[0].scale.set(sc, sc, 1); }
      if (a.animar) a.animar(av, dt, this);           // dron FPV: rotores, luces y oculto con su camara
      const suelo = this.entorno.altura ? this.entorno.altura(av.p[0], av.p[1]) : 0;
      this.sombra.position.set(t[0], suelo + 0.06, t[2]);
      const s = Math.max(0.2, 1 - Math.max(0, -av.p[2] - suelo) / 60);
      this.sombra.scale.set(s, s, s); this.sombra.material.opacity = 0.35 * s;
    }
    const S = this.escena.userData.sol;
    if (S && a) {
      const p = a.grupo.matrix.elements, d = S.userData.dir;
      S.target.position.set(p[12], p[13], p[14]); S.position.set(p[12] + d.x * 700, p[13] + d.y * 700, p[14] + d.z * 700);
      S.target.updateMatrixWorld();
    }
    if (this.sombra) this.sombra.visible = !(S && S.castShadow);
    // el agua con reflejos vuelve a dibujar toda la escena: solo si hay agua a menos de 2 km del avion (se mira cada segundo)
    if ((this._tAgua = (this._tAgua || 0) + dt) > 1 || this._aguaCerca === undefined) {
      this._tAgua = 0; const ent = this.entorno; let cerca = !this.mundo;           // en la isla el mar siempre esta cerca
      if (this.mundo && a) { const p = av.p; for (let k = 0; k < 16 && !cerca; k++) { const ang = k * Math.PI / 8; cerca = ent.enMar(p[0] + 2000 * Math.cos(ang), p[1] + 2000 * Math.sin(ang)) || ent.enMar(p[0] + 700 * Math.cos(ang), p[1] + 700 * Math.sin(ang)); } }
      this._aguaCerca = cerca;
      for (const ag of this.aguas) if (ag.water !== ag.plano) { ag.water.visible = this.calidad >= 2 && cerca; ag.plano.visible = !ag.water.visible; }
    }
    for (const ag of this.aguas) if (ag.water.material.uniforms && ag.water.visible) ag.water.material.uniforms.time.value += dt * 0.6;
    const v = this.entorno.viento, m = this.manga;
    if (v.base > 0.2) {
      const vw = ned2three([v.actual[0], v.actual[1], 0]);
      m.rotation.set(0, 0, 0); m.lookAt(m.position.x + vw[0], m.position.y, m.position.z + vw[2]); m.rotateX(Math.PI / 2);
    }
    this._camara(av);
    if (this.rotulos) {           // rotulos de los pueblos: alto fijo en pixeles sea cual sea el zoom (ver las luces del avion)
      const k = 2 * Math.tan(this.cam.fov / 2 * Math.PI / 180) / this.renderer.domElement.height;
      for (const sp of this.rotulos) { const h = sp.userData.px * k; sp.scale.set(h * 4, h, 1); }
    }
    this.renderer.render(this.escena, this.cam);
  }

  _camara(av) {
    const cam = this.cam, t = ned2three(av.p);
    if (this.camara === 1) {
      // vista del piloto con ZOOM AUTOMATICO, como en los simuladores RC: el campo de vision se cierra con la distancia
      // para que la envergadura ocupe siempre la fraccion zoomPiloto del alto de la pantalla (3 % por defecto; 0 = sin
      // zoom, como lo ve el ojo), entre 50 y 1,5 grados. Asi el avion no se pierde de vista y cada avion se ve segun su
      // tamano (el dron de 25 cm cierra antes). Suavizado para que no de saltos al cambiar de camara
      const b = this.base || [0, 0, 0];
      cam.position.set(b[0] + 1.5, b[1] + 1.7, b[2] + 2);
      const env = (this.avion && this.avion.envergadura) || 1, zp = this.zoomPiloto === undefined ? 0.03 : this.zoomPiloto;
      const d = Math.hypot(t[0] - b[0] - 1.5, t[1] - b[1] - 1.7, t[2] - b[2] - 2);
      const fovObj = zp > 0 ? Math.max(1.5, Math.min(50, env / (zp * Math.max(d, 0.5)) * 180 / Math.PI)) : 50;
      this._fov1 = this._fov1 === undefined ? fovObj : this._fov1 + (fovObj - this._fov1) * 0.08;
      cam.fov = this._fov1; cam.lookAt(t[0], t[1], t[2]);
    }
    else if (this.camara === 2) {
      const yaw = Cuat.euler(av.q)[2], back = ned2three([-Math.cos(yaw) * 5, -Math.sin(yaw) * 5, -1.5]);
      cam.position.set(t[0] + back[0], t[1] + back[1], t[2] + back[2]); cam.fov = 60; cam.lookAt(t[0], t[1], t[2]);
    } else if (this.avion && this.avion.fpv) {
      // camara FPV: fija al bastidor, inclinada hacia arriba (uptilt) y gran angular (campo de vision HORIZONTAL fijo)
      const C = this.avion.cam, ti = C.incl * Math.PI / 180, q = av.q;
      const pos = ned2three(Cuat.rot(q, C.pos)), fw = ned2three(Cuat.rot(q, [Math.cos(ti), 0, -Math.sin(ti)])), up = ned2three(Cuat.rot(q, [-Math.sin(ti), 0, -Math.cos(ti)]));
      cam.position.set(t[0] + pos[0], t[1] + pos[1], t[2] + pos[2]); cam.fov = 2 * Math.atan(Math.tan(C.fovH / 2 * Math.PI / 180) / cam.aspect) * 180 / Math.PI;
      cam.up.set(up[0], up[1], up[2]); cam.lookAt(t[0] + pos[0] + fw[0], t[1] + pos[1] + fw[1], t[2] + pos[2] + fw[2]);
    } else if (this.avion && this.avion.dron) {
      // camara del dron en su gimbal de 3 ejes: nivelada (sin alabeo ni cabeceo del dron), con el rumbo del dron y la
      // inclinacion de la rueda (av.gimbal: 0 horizontal, -90 vertical). Campo de vision como el del DJI Mini (83 grados en diagonal)
      const yaw = Cuat.euler(av.q)[2], g = (av.gimbal === undefined ? -10 : av.gimbal) * Math.PI / 180;
      const pos = ned2three(Cuat.rot(av.q, [0.1, 0, -0.1])), fw = ned2three([Math.cos(yaw) * Math.cos(g), Math.sin(yaw) * Math.cos(g), -Math.sin(g)]);   // 10 cm sobre el dron: en el suelo el plano cercano (0,1 m) no corta el terreno
      cam.position.set(t[0] + pos[0], t[1] + pos[1], t[2] + pos[2]); cam.fov = 58;
      cam.up.set(0, 1, 0); cam.lookAt(t[0] + pos[0] + fw[0], t[1] + pos[1] + fw[1], t[2] + pos[2] + fw[2]);
    } else {
      const q = av.q, pos = ned2three(Cuat.rot(q, [0.3, 0, -0.1])), fw = ned2three(Cuat.rot(q, [1, 0, 0])), up = ned2three(Cuat.rot(q, [0, 0, -1]));
      cam.position.set(t[0] + pos[0], t[1] + pos[1], t[2] + pos[2]); cam.fov = 80;
      cam.up.set(up[0], up[1], up[2]); cam.lookAt(t[0] + pos[0] + fw[0], t[1] + pos[1] + fw[1], t[2] + pos[2] + fw[2]);
    }
    if (this.camara !== 3) cam.up.set(0, 1, 0);
    cam.updateProjectionMatrix();
  }
}

/** Vista previa de la pantalla de eleccion: el avion girando despacio y moviendo los mandos. */
class VistaPrevia {
  /** opciones.transparente: fondo transparente (el avion flota sobre la pantalla de inicio y el hangar). */
  constructor(lienzo, opciones = {}) {
    this.lienzo = lienzo;
    this.renderer = new THREE.WebGLRenderer({ canvas: lienzo, antialias: true, alpha: !!opciones.transparente });
    this.renderer.setPixelRatio(Math.min(2, window.devicePixelRatio));
    this.escena = new THREE.Scene(); this.escena.background = opciones.transparente ? null : new THREE.Color(0x9fc8ea);
    if (opciones.transparente) this.renderer.setClearColor(0x000000, 0);
    this.renderer.toneMapping = THREE.ACESFilmicToneMapping; this.renderer.toneMappingExposure = 1.05;
    this.escena.add(new THREE.HemisphereLight(0xffffff, 0x557755, 0.95 * Math.PI));
    const sol = new THREE.DirectionalLight(0xffffff, 0.8 * Math.PI); sol.position.set(3, 5, 4); this.escena.add(sol);
    this.cam = new THREE.PerspectiveCamera(35, 1, 0.05, 50);
    this.actual = null;
  }

  /** factor: distancia de la camara respecto a la envergadura (1 = la pantalla de eleccion antigua; mas = avion mas pequeno). */
  mostrar(datos, factor = 1) {
    if (this.actual) this.escena.remove(this.actual.base);
    const av = construirAvion(datos), base = new THREE.Group();
    av.grupo.matrixAutoUpdate = false;
    av.grupo.matrix.set(0, 1, 0, 0, 0, 0, -1, 0, -1, 0, 0, 0, 0, 0, 0, 1);     // cuerpo NED -> Three (morro hacia -z)
    base.add(av.grupo); this.escena.add(base); this.actual = { base, av };
    const r = datos.b_m * 0.9 * factor; this.cam.position.set(r * 0.9, r * 0.45, r * 1.1); this.cam.lookAt(0, 0, 0);
  }

  pintar(t) {
    if (!this.actual) return;
    const w = this.lienzo.clientWidth, h = this.lienzo.clientHeight;
    if (!w || !h) return;
    if (this.lienzo.width !== Math.round(w * this.renderer.getPixelRatio())) {
      this.renderer.setSize(w, h, false); this.cam.aspect = w / h; this.cam.updateProjectionMatrix();
    }
    this.actual.base.rotation.y = t * 0.0004;
    this.actual.av.timon.rotation.z = 0.3 * Math.sin(t * 0.002); this.actual.av.prof.rotation.y = 0.2 * Math.sin(t * 0.0017);
    for (const al of this.actual.av.alerones) al.setRotationFromAxisAngle(al.eje, al.signo * 0.25 * Math.sin(t * 0.0023) + (al.prof ? 0.2 * Math.sin(t * 0.0017) : 0));
    this.renderer.render(this.escena, this.cam);
  }
}
