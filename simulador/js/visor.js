"use strict";
// =====================================================================
//  VISOR: todo lo que se dibuja con Three.js. El campo (el sitio real: bancales de almendros, la
//  rambla, el cerro, el cortijo y la autopista; la pista y los pilones salen del Entorno), el avion
//  (a partir de la malla de su modelo), las camaras y la vista previa girando de la pantalla de eleccion.
//
//  Mundo Three: x = este, y = arriba, z = sur.  NED (n, e, d) -> (e, -d, -n).
// =====================================================================
function ned2three(p) { return [p[1], -p[2], -p[0]]; }

/** Grupo Three con el avion en ejes cuerpo NED (metros, origen en el CG) y sus partes moviles. */
function construirAvion(datos) {
  const grupo = new THREE.Group(), K = datos.malla;
  const geom = m => {
    const g = new THREE.BufferGeometry();
    g.setAttribute("position", new THREE.Float32BufferAttribute(m.v, 3)); g.setIndex(m.i);
    const n = g.toNonIndexed(); n.computeVertexNormals(); return n;
  };
  const mat = c => new THREE.MeshLambertMaterial({ color: c, side: THREE.DoubleSide });
  const col = Object.assign({ fuselaje: 0xf4f4f4, ala: 0xffc107, estab: 0xdddddd, moviles: 0xd32f2f }, datos.colores || {});
  for (const k of ["fuselaje", "ala", "estab"]) if (K[k]) grupo.add(new THREE.Mesh(geom(K[k]), mat(col[k])));
  const pivote = (malla, eje) => {      // superficie movil que gira sobre su bisagra
    const p = new THREE.Group(); p.position.set(...eje);
    const mm = new THREE.Mesh(geom(malla), mat(col.moviles)); mm.position.set(-eje[0], -eje[1], -eje[2]);
    p.add(mm); grupo.add(p); return p;
  };
  const prof = K.prof ? pivote(K.prof, K.bisagra_prof) : new THREE.Group();
  const timon = K.timon ? pivote(K.timon, K.bisagra_timon) : new THREE.Group();
  // alerones (si la malla los trae): cada uno gira sobre su bisagra, cuyo eje lleva el diedro y el calado del ala
  const alerones = (K.alerones || []).map(a => {
    const p = pivote(a, a.bisagra); p.eje = new THREE.Vector3(...a.eje).normalize(); p.signo = a.signo; return p;
  });
  const helice = new THREE.Mesh(new THREE.CircleGeometry(K.helice_r, 24),
    new THREE.MeshBasicMaterial({ color: 0x333333, transparent: true, opacity: 0.25, side: THREE.DoubleSide }));
  helice.rotation.y = Math.PI / 2; helice.position.set(...K.helice); grupo.add(helice);
  const cono = new THREE.Mesh(new THREE.ConeGeometry(0.018, 0.04, 12), mat(0x333333));
  cono.rotation.z = -Math.PI / 2; cono.position.set(K.helice[0] + 0.02, 0, K.helice[2]); grupo.add(cono);
  return { grupo, prof, timon, alerones, helice };
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
    this.renderer = new THREE.WebGLRenderer({ canvas: lienzo, antialias: true });
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
    this.escena.add(new THREE.HemisphereLight(0xd9e8ff, 0x8a5a3a, 0.72));     // cielo azul, rebote de la tierra rojiza
    const sol = new THREE.DirectionalLight(0xfff1dc, 1.05); sol.position.set(-350, 520, 260); this.escena.add(sol);
    this._cielo(sol.position);
    this._campo();
    this.sombra = new THREE.Mesh(new THREE.CircleGeometry(0.6, 20), new THREE.MeshBasicMaterial({ color: 0x000000, transparent: true, opacity: 0.35 }));
    this.sombra.rotation.x = -Math.PI / 2; this.sombra.position.y = 0.05; this.escena.add(this.sombra);
    window.addEventListener("resize", () => this.redimensionar()); this.aplicarCalidad(this.calidad);
  }

  /** Aplica un nivel de calidad (ver el constructor) y lo guarda. */
  aplicarCalidad(q) {
    this.calidad = q;
    this.renderer.setPixelRatio(Math.min(q === 2 ? 1.5 : q === 1 ? 1 : 0.75, window.devicePixelRatio));
    for (const m of this.lejanos) m.visible = q >= 2;
    for (const m of this.prescindibles) m.visible = q >= 1;
    try { localStorage.setItem("sim_calidad", String(q)); } catch (e) {}
    this.redimensionar();
  }

  /** Si dos tandas seguidas de 120 fotogramas van a menos de 35 fps, baja un nivel de calidad. No cuenta la
   *  pestana oculta, los parones ni los primeros 5 s (carga de texturas). */
  _vigilarCalidad(dt) {
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

  /** Cupula de cielo con degradado, el sol y unas nubes lejanas. */
  _cielo(posSol) {
    const esc = this.escena;
    const cielo = new THREE.Mesh(new THREE.SphereGeometry(2850, 32, 16), new THREE.ShaderMaterial({
      uniforms: { cima: { value: new THREE.Color(0x3f7fd0) }, horizonte: { value: new THREE.Color(0xd3dfe9) } },   // el horizonte, del color de la calima
      vertexShader: "varying vec3 vP; void main() { vP = position; gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0); }",
      fragmentShader: "uniform vec3 cima; uniform vec3 horizonte; varying vec3 vP; void main() { float t = pow(clamp(normalize(vP).y, 0.0, 1.0), 0.5); gl_FragColor = vec4(mix(horizonte, cima, t), 1.0); }",
      side: THREE.BackSide, depthWrite: false, fog: false }));
    esc.add(cielo);
    const [cs, gs] = lienzo(256, 256), g = gs.createRadialGradient(128, 128, 0, 128, 128, 128);
    g.addColorStop(0, "rgba(255,252,240,1)"); g.addColorStop(0.18, "rgba(255,246,210,0.9)"); g.addColorStop(0.5, "rgba(255,235,190,0.25)"); g.addColorStop(1, "rgba(255,230,180,0)");
    gs.fillStyle = g; gs.fillRect(0, 0, 256, 256);
    const solSprite = new THREE.Sprite(new THREE.SpriteMaterial({ map: new THREE.CanvasTexture(cs), fog: false, depthWrite: false }));
    solSprite.position.copy(posSol).normalize().multiplyScalar(2600); solSprite.scale.set(520, 520, 1); esc.add(solSprite);
    const [cn, gn] = lienzo(256, 128), r = semilla(5);
    for (let i = 0; i < 26; i++) {
      const x = 40 + r() * 176, y = 50 + r() * 40, rad = 18 + r() * 26, gg = gn.createRadialGradient(x, y, 0, x, y, rad);
      gg.addColorStop(0, "rgba(255,255,255,0.75)"); gg.addColorStop(0.6, "rgba(250,250,252,0.35)"); gg.addColorStop(1, "rgba(245,245,250,0)");
      gn.fillStyle = gg; gn.fillRect(0, 0, 256, 128);
    }
    const mn = new THREE.SpriteMaterial({ map: new THREE.CanvasTexture(cn), transparent: true, depthWrite: false, opacity: 0.9 });
    for (let i = 0; i < 14; i++) {
      const a = r() * Math.PI * 2, d = 900 + r() * 1400, s = 260 + r() * 420, nube = new THREE.Sprite(mn);
      nube.position.set(d * Math.cos(a), 420 + r() * 380, d * Math.sin(a)); nube.scale.set(s, s * 0.42, 1); esc.add(nube); this.prescindibles.push(nube);
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
    const tex = c => { const t = new THREE.CanvasTexture(c); t.anisotropy = aniso; return t; };
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
    const mar = new THREE.Mesh(new THREE.PlaneGeometry(40000, 40000), lam(0x2f6f99, { polygonOffset: true, polygonOffsetFactor: 4, polygonOffsetUnits: 4 }));
    mar.rotation.x = -Math.PI / 2; mar.position.y = -1.2; esc.add(mar);          // bajo el suelo y empujado atras en profundidad: nunca parpadea sobre la isla
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
      const p = new THREE.Mesh(gpil, new THREE.MeshLambertMaterial({ map: new THREE.CanvasTexture(ct) }));
      p.position.set(s[1], Pi.alto / 2, -s[0]); esc.add(p);
      const t = new THREE.Mesh(gtapa, new THREE.MeshLambertMaterial({ color: new THREE.Color(hex) }));
      t.position.set(s[1], Pi.alto, -s[0]); esc.add(t);
    });
    // el aparcamiento: la furgoneta, la carpa del piloto y la manga de viento a rayas
    const furgo = new THREE.Mesh(new THREE.BoxGeometry(2.0, 2.1, 4.8), lam(0xececec)); furgo.position.set(8, 1.05, 9); esc.add(furgo);
    const vent = new THREE.Mesh(new THREE.BoxGeometry(2.04, 0.7, 3.2), lam(0x2b3a48)); vent.position.set(8, 1.5, 9.3); esc.add(vent);
    const mCarpa = lam(0x2f5aa8);
    for (const [x, z] of [[-9, 5], [-5, 5], [-9, 9], [-5, 9]]) { const pie = new THREE.Mesh(new THREE.CylinderGeometry(0.03, 0.03, 2.3, 5), mEst); pie.position.set(x, 1.15, z); esc.add(pie); }
    const techo = new THREE.Mesh(new THREE.ConeGeometry(3.1, 1.2, 4), mCarpa); techo.rotation.y = Math.PI / 4; techo.position.set(-7, 2.9, 7); esc.add(techo);
    const mesa = new THREE.Mesh(new THREE.BoxGeometry(1.6, 0.05, 0.7), lam(0xcfcfcf)); mesa.position.set(-7, 0.78, 7); esc.add(mesa);
    const mastil = new THREE.Mesh(new THREE.CylinderGeometry(0.03, 0.03, 4, 6), mEst); mastil.position.set(-14, 2, -10); esc.add(mastil);
    const [cmg, gmg] = lienzo(32, 128); for (let i = 0; i < 5; i++) { gmg.fillStyle = i % 2 ? "#ffffff" : "#ff6d00"; gmg.fillRect(0, i * 25.6, 32, 25.6); }
    this.manga = new THREE.Mesh(new THREE.ConeGeometry(0.25, 1.4, 12, 1, true), new THREE.MeshLambertMaterial({ map: new THREE.CanvasTexture(cmg), side: THREE.DoubleSide }));
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

  /** Pone en la escena el avion de un modelo (quita el anterior). */
  ponerAvion(datos) {
    if (this.avion) this.escena.remove(this.avion.grupo);
    this.avion = construirAvion(datos);
    this.avion.grupo.matrixAutoUpdate = false;
    this.escena.add(this.avion.grupo);
  }

  /** Coloca el avion, sus mandos, la sombra, la manga y la camara segun el estado, y dibuja. */
  dibujar(av) {
    const ahora = performance.now(), dtReal = (ahora - (this._tAnt || ahora)) / 1000, dt = Math.min(0.1, dtReal); this._tAnt = ahora;
    this._trafico(dt); this._vigilarCalidad(dtReal);
    const a = this.avion;
    if (a) {
      const q = av.q, ex = ned2three(Cuat.rot(q, [1, 0, 0])), ey = ned2three(Cuat.rot(q, [0, 1, 0])), ez = ned2three(Cuat.rot(q, [0, 0, 1]));
      const t = ned2three(av.p);
      a.grupo.matrix.set(ex[0], ey[0], ez[0], t[0], ex[1], ey[1], ez[1], t[1], ex[2], ey[2], ez[2], t[2], 0, 0, 0, 1);
      a.prof.rotation.y = av.de;           // + = borde de fuga abajo
      a.timon.rotation.z = -av.dr;         // + = borde de fuga a la derecha
      for (const al of a.alerones) al.setRotationFromAxisAngle(al.eje, al.signo * (av.da || 0));   // + = aleron derecho arriba
      a.helice.visible = av.gases > 0.05;
      this.sombra.position.set(t[0], 0.06, t[2]);
      const s = Math.max(0.2, 1 - Math.max(0, -av.p[2]) / 60);
      this.sombra.scale.set(s, s, s); this.sombra.material.opacity = 0.35 * s;
    }
    const v = this.entorno.viento, m = this.manga;
    if (v.base > 0.2) {
      const vw = ned2three([v.actual[0], v.actual[1], 0]);
      m.rotation.set(0, 0, 0); m.lookAt(m.position.x + vw[0], m.position.y, m.position.z + vw[2]); m.rotateX(Math.PI / 2);
    }
    this._camara(av);
    this.renderer.render(this.escena, this.cam);
  }

  _camara(av) {
    const cam = this.cam, t = ned2three(av.p);
    if (this.camara === 1) { cam.position.set(1.5, 1.7, 2); cam.fov = 50; cam.lookAt(t[0], t[1], t[2]); }
    else if (this.camara === 2) {
      const yaw = Cuat.euler(av.q)[2], back = ned2three([-Math.cos(yaw) * 5, -Math.sin(yaw) * 5, -1.5]);
      cam.position.set(t[0] + back[0], t[1] + back[1], t[2] + back[2]); cam.fov = 60; cam.lookAt(t[0], t[1], t[2]);
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
  constructor(lienzo) {
    this.lienzo = lienzo;
    this.renderer = new THREE.WebGLRenderer({ canvas: lienzo, antialias: true });
    this.renderer.setPixelRatio(Math.min(2, window.devicePixelRatio));
    this.escena = new THREE.Scene(); this.escena.background = new THREE.Color(0x9fc8ea);
    this.escena.add(new THREE.HemisphereLight(0xffffff, 0x557755, 0.95));
    const sol = new THREE.DirectionalLight(0xffffff, 0.8); sol.position.set(3, 5, 4); this.escena.add(sol);
    this.cam = new THREE.PerspectiveCamera(35, 1, 0.05, 50);
    this.actual = null;
  }

  mostrar(datos) {
    if (this.actual) this.escena.remove(this.actual.base);
    const av = construirAvion(datos), base = new THREE.Group();
    av.grupo.matrixAutoUpdate = false;
    av.grupo.matrix.set(0, 1, 0, 0, 0, 0, -1, 0, -1, 0, 0, 0, 0, 0, 0, 1);     // cuerpo NED -> Three (morro hacia -z)
    base.add(av.grupo); this.escena.add(base); this.actual = { base, av };
    const r = datos.b_m * 0.9; this.cam.position.set(r * 0.9, r * 0.5, r * 1.1); this.cam.lookAt(0, 0, 0);
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
    for (const al of this.actual.av.alerones) al.setRotationFromAxisAngle(al.eje, al.signo * 0.25 * Math.sin(t * 0.0023));
    this.renderer.render(this.escena, this.cam);
  }
}
