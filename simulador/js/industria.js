// Instalaciones industriales de singulares.js (tanques, esferas, balas, columnas, estructuras de proceso, racks de
// tuberias, chimeneas y torres de refrigeracion): cada pieza se descompone en primitivas que se dibujan con instancias
// (cuatro formas: caja, cilindro de pie, cilindro tumbado y elipsoide). Traduccion LITERAL en
// simulador_godot/scripts/industria.gd: mismas primitivas, mismos colores y mismos solidos para las colisiones.
//
// Primitiva: [forma, e, n, y0, sx, sy, sz, rumbo, color]
//   forma 0 caja         sx largo (hacia rumbo), sy alto, sz ancho; y0 su base
//   forma 1 cilindro     sx = sz diametro, sy alto; y0 su base
//   forma 2 tumbado      cilindro con el eje hacia rumbo: sx largo, sy = sz diametro; y0 su parte de abajo
//   forma 3 elipsoide    sx, sy, sz diametros (sx hacia rumbo); y0 su parte de abajo
// e, n en metros del mundo; y0 en metros sobre el suelo del punto de la pieza; rumbo en grados (0 norte, 90 este).
const Industria = {
  TIPOS: ["tanque", "esfera", "bala", "columna", "estructura", "rack", "chimenea", "refrigeracion"],
  COLORES: ["#7a8087", "#4d5257", "#e6e6e0", "#d8d2c0", "#a8704a", "#b9bec4", "#c9a83a", "#5f8a5a", "#5b5f63", "#2c3a3a", "#b8352e", "#a9a59c", "#3f6a95", "#d9b632"],

  /** El mismo pseudoazar que sabic_industria.py (h) y Industria.azar de Godot. */
  azar(v, i) { const x = Math.sin((v * 1000 + i) * 12.9898) * 43758.5453; return x - Math.floor(x); },

  /** Primitivas de una pieza (lista vacia si no es industrial). */
  primitivas(p) {
    const P = [], R = p.rumbo === undefined ? 0 : p.rumbo, sr = Math.sin(R * Math.PI / 180), cr = Math.cos(R * Math.PI / 180);
    const en = (x, z) => [p.e + x * sr + z * cr, p.n + x * cr - z * sr];            // (x hacia rumbo, z a su derecha)
    const caja = (x, z, y0, a, h, b, c) => { const [e, n] = en(x, z); P.push([0, e, n, y0, a, h, b, R, c]); };
    const cil = (x, z, y0, d, h, c) => { const [e, n] = en(x, z); P.push([1, e, n, y0, d, h, d, 0, c]); };
    if (p.tipo === "tanque") {
      const r = p.radio, H = p.alto, c = p.color === undefined ? 2 : p.color;
      cil(0, 0, 0, 2 * r, H, c);
      if (p.techo === "cupula") P.push([3, p.e, p.n, H - 0.25 * r, 2 * r, 0.5 * r, 2 * r, 0, c]);
      if (p.techo === "abierto") {                                                  // decantador: agua, puente y motor
        cil(0, 0, H - 0.45, 2 * r - 0.5, 0.3, 9); caja(0, 0, H, 2 * r + 1, 0.7, 1.2, 0); cil(0, 0, H, 1.6, 1.2, 1);
      } else {
        caja(-(r + 0.2), 0, 0, 0.3, H + 1, 0.7, 13);                                  // escalera de gato
      }
    } else if (p.tipo === "esfera") {
      const r = p.radio;
      for (const [x, z] of [[-0.7, -0.7], [0.7, -0.7], [0.7, 0.7], [-0.7, 0.7]]) cil(x * r, z * r, 0, 0.35, 1.4 + r, 0);
      P.push([3, p.e, p.n, 1.4, 2 * r, 2 * r, 2 * r, 0, 2]);
    } else if (p.tipo === "bala") {
      const r = p.radio, L = p.largo, y = 1.0, [e, n] = en(0, 0);
      P.push([2, e, n, y, L - r, 2 * r, 2 * r, R, 2]);
      for (const s of [-1, 1]) { const [e2, n2] = en(s * (L - r) / 2, 0); P.push([3, e2, n2, y, r, 2 * r, 2 * r, R, 2]); caja(s * L / 4, 0, 0, 0.6, y + 0.3 * r, 1.6 * r, 11); }
    } else if (p.tipo === "columna") {
      const r = p.radio, H = p.alto;
      cil(0, 0, 0, 2 * r + 0.4, 1.5, 11); cil(0, 0, 0, 2 * r, H, 3);
      P.push([3, p.e, p.n, H - 0.5 * r, 2 * r, r, 2 * r, 0, 3]);
      for (let y = 6; y < H - 2; y += 7) cil(0, 0, y, 2 * r + 1.6, 0.15, 8);     // plataformas
      caja(-(r + 0.35), 0, 0, 0.4, H - 1, 0.4, 5);                 // tuberia que sube por el costado
    } else if (p.tipo === "estructura") {
      const L = p.largo, A = p.ancho, H = p.alto, s = p.semilla, az = i => Industria.azar(s, i);
      const nx = Math.ceil(L / 6), nz = Math.ceil(A / 6);
      for (let i = 0; i <= nx; i++) for (let j = 0; j <= nz; j++) caja(-L / 2 + i * L / nx, -A / 2 + j * A / nz, 0, 0.35, H, 0.35, 0);
      for (let k = 1; k <= p.pisos; k++) {
        const y = k * H / p.pisos - 0.18;
        caja(0, 0, y, L, 0.18, A, 8);                                                // piso de rejilla
        caja(0, A / 2, y + 0.18, L, 1.0, 0.06, k % 2 ? 13 : 0);                         // barandilla del lado de la escalera
        if (k < p.pisos || az(30 + k) < 0.5) {                                        // equipos en el piso
          const a = 1.5 + 2 * az(20 + k), b = 1 + 1.2 * az(40 + k), h = 0.8 + 1.4 * az(50 + k);
          caja((az(60 + k) - 0.5) * (L - a - 1), (az(70 + k) - 0.5) * (A - b - 1), y + 0.18, a, h, b, az(80 + k) < 0.5 ? 12 : 1);
        }
      }
      const nv = 1 + Math.floor(az(1) * 3);
      for (let i = 0; i < nv; i++) {                                                  // recipientes de pie
        const r = 0.6 + az(8 + i) * 1.0, h = H * (0.6 + 0.5 * az(11 + i)), x = (az(2 + i) - 0.5) * (L - 2 * r - 1), z = (az(5 + i) - 0.5) * (A - 2 * r - 1), c = i % 2 ? 5 : 2;
        cil(x, z, 0, 2 * r, h, c); const [e, n] = en(x, z); P.push([3, e, n, h - 0.3 * r, 2 * r, 0.6 * r, 2 * r, 0, c]);
      }
      caja(L / 2 + 1.0, A / 2 - 1.2, 0, 2.0, H + 1.2, 2.4, 1);                        // escalera en torre
    } else if (p.tipo === "rack") {
      const de = p.e1 - p.e0, dn = p.n1 - p.n0, L = Math.hypot(de, dn), Rr = Math.atan2(de, dn) * 180 / Math.PI, s2 = de / L, c2 = dn / L;
      const en2 = (x, z) => [p.e0 + x * s2 + z * c2, p.n0 + x * c2 - z * s2], W = p.ancho, nb = Math.max(1, Math.ceil(L / 6));
      for (let k = 0; k <= nb; k++) {
        const x = k * L / nb;
        for (const z of [-W / 2, W / 2]) { const [e, n] = en2(x, z); P.push([0, e, n, 0, 0.35, p.alto, 0.35, Rr, 0]); }
        for (let j = 1; j <= p.niveles; j++) { const [e, n] = en2(x, 0); P.push([0, e, n, p.alto * j / p.niveles - 0.3, 0.3, 0.3, W + 0.35, Rr, 0]); }
      }
      for (let j = 1; j <= p.niveles; j++) {
        const nt = Math.max(3, Math.floor(W / 0.9));
        for (let i = 0; i < nt; i++) {
          const d = 0.25 + 0.45 * Industria.azar(j, i), a = Industria.azar(j, 50 + i), c = a < 0.7 ? 5 : a < 0.85 ? 6 : 7;
          const [e, n] = en2(L / 2, -W / 2 + 0.5 + i * (W - 1) / (nt - 1));
          P.push([2, e, n, p.alto * j / p.niveles, L, d, d, Rr, c]);
        }
      }
    } else if (p.tipo === "chimenea") {
      const r = p.radio, H = p.alto;
      cil(0, 0, 0, 2 * r + 0.6, 0.85 * H, 11);
      cil(0, 0, 0.85 * H, 2 * r, 0.05 * H, 10); cil(0, 0, 0.9 * H, 2 * r, 0.05 * H, 2); cil(0, 0, 0.95 * H, 2 * r, 0.05 * H, 10);
      cil(0, 0, H, 2 * r - 0.3, 0.1, 1);
    } else if (p.tipo === "refrigeracion") {
      const L = p.largo, A = p.ancho, H = p.alto, nc = p.celdas, d = Math.min(L / nc, A) * 0.8;
      caja(0, 0, 0, L, H, A, 11); caja(0, 0, 0.6, L - 0.4, H * 0.6, A + 0.12, 1);   // cuerpo y rejillas de entrada de aire
      for (let i = 0; i < nc; i++) { const x = (i + 0.5) * L / nc - L / 2; cil(x, 0, H, d, 2.6, 5); cil(x, 0, H + 2.6, d - 0.3, 0.05, 1); }
    }
    return P;
  },

  /** Solido para las colisiones: [planta (E, N, ...), alto]. Null si no es industrial. */
  solido(p) {
    const R = (p.rumbo || 0) * Math.PI / 180, sr = Math.sin(R), cr = Math.cos(R);
    const rect = (e, n, L, A, sr2, cr2) => [[-L / 2, -A / 2], [L / 2, -A / 2], [L / 2, A / 2], [-L / 2, A / 2]].flatMap(([x, z]) => [e + x * sr2 + z * cr2, n + x * cr2 - z * sr2]);
    if (p.tipo === "tanque") return [rect(p.e, p.n, 1.8 * p.radio, 1.8 * p.radio, 0, 1), p.alto + (p.techo === "cupula" ? 0.25 * p.radio : 1)];
    if (p.tipo === "esfera") return [rect(p.e, p.n, 2 * p.radio, 2 * p.radio, 0, 1), 1.4 + 2 * p.radio];
    if (p.tipo === "bala") return [rect(p.e, p.n, p.largo, 2 * p.radio, sr, cr), 1 + 2 * p.radio];
    if (p.tipo === "columna" || p.tipo === "chimenea") return [rect(p.e, p.n, 2 * p.radio, 2 * p.radio, 0, 1), p.alto];
    if (p.tipo === "estructura") return [rect(p.e, p.n, p.largo + 2, p.ancho, sr, cr), p.alto + 1.2];
    if (p.tipo === "refrigeracion") return [rect(p.e, p.n, p.largo, p.ancho, sr, cr), p.alto + 2.6];
    if (p.tipo === "rack") {
      const de = p.e1 - p.e0, dn = p.n1 - p.n0, L = Math.hypot(de, dn);
      return [rect((p.e0 + p.e1) / 2, (p.n0 + p.n1) / 2, L, p.ancho, de / L, dn / L), p.alto + 0.5];
    }
    return null;
  },
};
