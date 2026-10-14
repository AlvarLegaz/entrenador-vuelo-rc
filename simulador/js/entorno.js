"use strict";
// =====================================================================
//  ENTORNO: el campo de vuelo. Viento con rachas, pista, los 4 pilones tipo Red Bull que marcan el
//  circuito (se rodean siempre por fuera), la zona 2 de precision detras del piloto (pista 2 con la diana
//  y la puerta) y las reglas del suelo (aterrizaje o accidente).
//
//  Coordenadas NED en metros con origen en el piloto, que mira al norte. La pista va hacia el norte.
// =====================================================================
// Mundos reales (carpeta mundos/): cada fichero llama a Mundos.registrar({ id, nombre, origen, terreno, carreteras, urbano, lugares })
const Mundos = { _datos: {}, registrar(m) { Mundos._datos[m.id] = m; }, datos(id) { return Mundos._datos[id]; }, ids() { return Object.keys(Mundos._datos); } };
// Datos empaquetados en .js para abrir simulador.html con doble clic (file://): ortofotos de los mundos (mundos/<id>_orto.js)
// y zonas de detalle (zonas/indice.js, zonas/<id>/zona.js). Ver analisis/mundo_cartagena/empaquetar_fichero.py
Mundos._ortos = {}; Mundos.ortofoto = (id, url) => { Mundos._ortos[id] = url; };
const Zonas = { _indice: null, _datos: {}, indice(l) { Zonas._indice = l; }, registrar(id, d) { Zonas._datos[id] = d; } };
/** Carga un script y espera a que termine (o falle). */
function cargarScript(src) {
  return new Promise((ok, mal) => { const s = document.createElement("script"); s.src = src; s.onload = ok; s.onerror = () => mal(new Error("sin " + src)); document.head.appendChild(s); });
}
const ABIERTO_COMO_FICHERO = typeof location !== "undefined" && location.protocol === "file:";
function base64ABytes(b64) { const t = atob(b64), u = new Uint8Array(t.length); for (let i = 0; i < t.length; i++) u[i] = t.charCodeAt(i); return u.buffer; }

/** Copa solida de un arbol de las zonas de detalle de radio de copa rc sobre el suelo y: [radio, y0, y1] (lo que dibujan
 *  visor_real.js y mundo_3d.gd: tronco de 1 + 0,3 rc m en los almendros, 1,5 + 0,4 rc en los grandes, y la copa encima). */
function arbolZona(rc, y) { return rc < 2.5 ? [0.9 * rc, y, y + 1.0 + 0.3 * rc + 1.15 * rc] : [0.9 * rc, y, y + 1.5 + 0.4 * rc + 1.7 * rc]; }

class Entorno {
  constructor() {
    this.mundo = null;                 // mundo real activo (null = la isla del campo de pilones)
    this.altura = null;                // altura del suelo (m sobre el origen) en (N, E) cuando hay terreno real
    this.pista = { n0: 10, n1: 70, ancho: 10 };                       // N 10 a 70, centrada en E = 0
    // circuito: rectangulo de 120 x 180 m delante del piloto, con la pista dentro. Pilones en las esquinas
    // (N, E), ordenados por angulo alrededor del centro: los indices consecutivos son esquinas vecinas
    // Cada pilon tiene su color. Indices crecientes (verde -> amarillo -> rojo -> azul) = vuelta en sentido
    // horario visto desde arriba: subir por la izquierda, cruzar al fondo, bajar por la derecha y cruzar por
    // delante del piloto. Sentido -1 = al reves.
    this.circuito = { centro: [100, 0], pilones: [[40, -90], [160, -90], [160, 90], [40, 90]],
                      colores: [{ nombre: "verde", hex: "#2e7d32" }, { nombre: "amarillo", hex: "#f9a825" },
                                { nombre: "rojo", hex: "#c62828" }, { nombre: "azul", hex: "#1565c0" }] };
    this.pilon = { alto: 20, r0: 1.4, r1: 0.45 };                    // cono hinchable: radio abajo y arriba
    // ZONA 2, detras del piloto (al sur; el piloto se da la vuelta): entrenamiento de precision.
    //  - pista 2: franja de tierra de este a oeste, paralela a la linea del piloto, para la pasada baja (de
    //    punta a punta entre hmin y hmax, sin salirse por los lados) y con la diana de aterrizaje en el centro
    //  - diana: circulos de cal de 5, 10 y 20 m con sus puntos
    //  - puerta: dos pilones naranjas separados 16 m; se cruza de este a oeste o al reves, por debajo de lo alto
    //  - despejado: rectangulo sin almendros ni estacas
    this.zona2 = {
      pista: { n: -45, e0: -35, e1: 35, ancho: 10, margen: 5, hmin: 2, hmax: 8 },
      diana: { n: -45, e: 0, anillos: [[5, 100], [10, 50], [20, 20]] },
      puerta: { e: 60, n0: -123, n1: -107, color: { nombre: "naranja", hex: "#ef6c00" } },
      despejado: { n0: -150, n1: -14, e0: -60, e1: 95 },
    };
    this.viento = { base: 2, rumbo: Math.PI, rachas: true, r: [0, 0, 0], actual: [0, 0, 0] };   // rumbo: hacia donde va
    // limites de un aterrizaje sin daños, y del campo: a mas de aviso_m se avisa, a mas de distancia_m el
    // avion ya no se ve desde el piloto y el vuelo termina "fuera de limites" (asi nadie se queda atrapado
    // en una espiral lejos del campo: R y a empezar de nuevo)
    this.limites = { descenso_ms: 2.5, alabeo_grados: 30, vel_suelo_ms: 12, cabeceo_grados: 25, aviso_m: 400, distancia_m: 650 };
  }

  /** vel en m/s; desde = de donde viene el viento (grados: 0 norte, 90 este...). */
  configurarViento({ vel, desde, rachas }) {
    this.viento.base = vel; this.viento.rumbo = ((desde + 180) % 360) * Math.PI / 180; this.viento.rachas = rachas;
    this.viento.r = [0, 0, 0, 0];
  }

  /** Viento a la altura h sobre el suelo: el viento configurado es el de 10 m; mas abajo frena con el perfil
   *  logaritmico de un campo de cultivo (rugosidad 5 cm): a 2 m sopla un 70 % y a 0,5 m un 45 %. Las rachas, igual. */
  vientoA(vw, h) {
    if (this.facil) return vw.slice();               // dificultad facil: el mismo viento a cualquier altura
    const z0 = 0.05, k = Math.max(0, Math.log(Math.max(h, 0.2) / z0) / Math.log(10 / z0));
    return [vw[0] * Math.min(1.25, k), vw[1] * Math.min(1.25, k), vw[2] * Math.min(1, k)];
  }

  /** Velocidad de alabeo de la turbulencia (rad/s) para un avion de envergadura b a la altura h: la racha no es igual
   *  en las dos semialas y alabea el avion. Intensidad de la integral del espectro de Dryden (MIL-F-8785C):
   *  sigma_p^2 = sigma_w^2 (0,8 / L_w) (pi L_w / 4b)^(1/3) / (2 (4b / pi)), con L_w = h cerca del suelo. */
  rafagaAlabeo(b, h) {
    const v = this.viento;
    if (this.facil || !v.rachas || v.base < 0.01) return 0;
    const sw = 0.5 * (0.18 * v.base + 0.15), Lw = Math.max(3, Math.min(h, 300));
    return v.r[3] * sw * Math.sqrt(0.8 / Lw * Math.cbrt(Math.PI * Lw / (4 * b)) / (2 * 4 * b / Math.PI));
  }

  /** Rachas tipo Dryden simplificado: tres ruidos filtrados de 1,2 s. */
  actualizar(dt) {
    const v = this.viento, W = v.base, base = [W * Math.cos(v.rumbo), W * Math.sin(v.rumbo), 0];
    if (v.rachas && W > 0.01) {
      const sigma = 0.18 * W + 0.15, tau = 1.2;
      for (let i = 0; i < 3; i++) {
        const s = i === 2 ? 0.5 * sigma : sigma;
        v.r[i] += (-v.r[i] / tau + s * Math.sqrt(2 / tau) * (Math.random() * 2 - 1) * Math.sqrt(3) / Math.sqrt(dt)) * dt;
      }
      const tp = 0.15;                                 // componente de alabeo: ruido de varianza 1 (corte del espectro, ~pi V / 4b)
      v.r[3] = (v.r[3] || 0) + (-(v.r[3] || 0) / tp + Math.sqrt(2 / tp) * (Math.random() * 2 - 1) * Math.sqrt(3) / Math.sqrt(dt)) * dt;
    } else v.r = [0, 0, 0, 0];
    v.actual = [base[0] + v.r[0], base[1] + v.r[1], v.r[2]];
    return v.actual;
  }

  /** Contacto con el suelo: null si sigue en el aire; si no, "aterrizado" o "roto (motivo)". */
  contactoSuelo(av, vn) {
    const suelo = this.altura ? this.altura(av.p[0], av.p[1]) : 0;
    if (-av.p[2] > suelo) return null;
    av.p[2] = -suelo;
    if (this.enMar && this.enMar(av.p[0], av.p[1])) return "roto (ha caído al mar)";
    const [roll, pitch] = Cuat.euler(av.q), vz = -vn[2], vel = Math.hypot(vn[0], vn[1]), L = this.limites;
    if (vz < -L.descenso_ms) return "roto (demasiado descenso)";
    if (Math.abs(roll) > L.alabeo_grados * D2R) return "roto (ala en el suelo)";
    if (vel > L.vel_suelo_ms) return "roto (demasiada velocidad)";
    if (Math.abs(pitch) > L.cabeceo_grados * D2R) return "roto (morro en el suelo)";
    return "aterrizado";
  }

  pilones() { return this.circuito.pilones; }
  /** Los dos pilones de la puerta de la zona 2, (N, E). */
  pilonesPuerta() { const P = this.zona2.puerta; return [[P.n0, P.e], [P.n1, P.e]]; }

  /** Distancia horizontal al piloto (m) y si esta fuera del campo. En un mundo real no hay limite. */
  distancia(p) { return Math.hypot(p[0], p[1]); }
  fueraDeLimites(p) { return !this.mundo && this.distancia(p) > this.limites.distancia_m; }

  /** Activa un mundo real (datos de Mundos) o vuelve a la isla (null). El terreno viene como malla de alturas
   *  int16 (base64) sobre el nivel del mar; aqui se guarda relativo al suelo del origen (h0), que es el 0 del
   *  simulador. En el mar el suelo es la superficie del agua. */
  ponerMundo(mundo) {
    this.mundo = mundo || null; this._rejArb = null;
    this.zona = null; this.zonas = [];
    if (!mundo) { this.altura = null; this.enMar = null; return; }
    const T = mundo.terreno, bin = atob(T.alturas_b64), H = new Int16Array(bin.length / 2);
    for (let i = 0; i < H.length; i++) H[i] = (bin.charCodeAt(2 * i) | (bin.charCodeAt(2 * i + 1) << 8)) << 16 >> 16;
    this.terreno = { H, paso: T.paso, N0: T.N0, E0: T.E0, nN: T.nN, nE: T.nE, h0: T.h0 };
    const hMar = (N, E) => {                       // altura sobre el nivel del mar, bilineal
      let i = (N - T.N0) / T.paso, j = (E - T.E0) / T.paso;
      i = Math.max(0, Math.min(T.nN - 1.001, i)); j = Math.max(0, Math.min(T.nE - 1.001, j));
      const i0 = Math.floor(i), j0 = Math.floor(j), fi = i - i0, fj = j - j0, k = i0 * T.nE + j0;
      return H[k] * (1 - fi) * (1 - fj) + H[k + T.nE] * fi * (1 - fj) + H[k + 1] * (1 - fi) * fj + H[k + T.nE + 1] * fi * fj;
    };
    // agua: mascara de 1 bit por celda segun la linea de costa de OSM (agua_b64); si el mundo no la trae, h <= 0,5
    let A = null;
    if (T.agua_b64) {
      const ab = atob(T.agua_b64); A = new Uint8Array(T.nN * T.nE);
      for (let i = 0; i < A.length; i++) A[i] = (ab.charCodeAt(i >> 3) >> (7 - (i & 7))) & 1;
    }
    this.agua = A;
    let Lg = null;                                 // laguna (Mar Menor): solo para el color del agua
    if (T.laguna_b64) { const lb = atob(T.laguna_b64); Lg = new Uint8Array(T.nN * T.nE); for (let i = 0; i < Lg.length; i++) Lg[i] = (lb.charCodeAt(i >> 3) >> (7 - (i & 7))) & 1; }
    this.laguna = Lg;
    const fAgua = (N, E) => {                      // fraccion de agua, bilineal, para una costa suave
      if (!A) return hMar(N, E) <= 0.5 ? 1 : 0;
      let i = (N - T.N0) / T.paso, j = (E - T.E0) / T.paso;
      i = Math.max(0, Math.min(T.nN - 1.001, i)); j = Math.max(0, Math.min(T.nE - 1.001, j));
      const i0 = Math.floor(i), j0 = Math.floor(j), fi = i - i0, fj = j - j0, k = i0 * T.nE + j0;
      return A[k] * (1 - fi) * (1 - fj) + A[k + T.nE] * fi * (1 - fj) + A[k + 1] * (1 - fi) * fj + A[k + T.nE + 1] * fi * fj;
    };
    this.alturaMar = hMar; this.fraccionAgua = fAgua;
    // umbral 0,7: el mismo que usa la textura; con la orilla de la malla (tierra >= 1 m, agua a -1,5 m junto a la
    // costa) la superficie cruza el nivel del mar mas o menos ahi, asi el suelo fisico coincide con lo que se ve
    this.alturaMundo = (N, E) => (fAgua(N, E) > 0.7 ? 0 : Math.max(0, hMar(N, E))) - T.h0;
    this.enMarMundo = (N, E) => fAgua(N, E) > 0.7;
    this.altura = this.alturaMundo; this.enMar = this.enMarMundo; this.zona = null; this.zonas = [];
  }

  /** Zona de detalle (simulador/zonas/<id>/, comun a los dos simuladores): terreno a 5 m y agua de la linea de costa.
   *  z = { meta: zona.json, dem: Int16Array (dm sobre el mar, -32768 = agua, fila 0 = sur) } o null para quitarla.
   *  Dentro de la zona el suelo es el de la zona; en los ultimos 100 m del borde se mezcla con el del mundo. */
  ponerZona(z) { this.ponerZonas(z ? [z] : []); }

  /** Varias zonas de detalle a la vez (las de cerca del punto de lanzamiento). Cada punto toma el suelo de la primera
   *  zona que lo contiene; la mezcla con el mundo en los ultimos 100 m solo se hace en los lados SIN otra zona pegada
   *  (zonas de una rejilla, como las de La Manga): entre dos zonas vecinas el suelo sigue el MDT de 5 m sin escalon. */
  ponerZonas(lista) {
    this.zonas = (lista || []).filter(Boolean); this.zona = this.zonas[0] || null;
    if (!this.zonas.length) { this.altura = this.alturaMundo; this.enMar = this.enMarMundo; this.muestraZona = () => null; return; }
    const h0 = this.mundo.terreno.h0;
    const Zs = this.zonas.map(z => {
      const Z = z.meta, D = z.dem, n = Z.dem.n, paso = Z.dem.paso_m, lado = (n - 1) * paso;
      const pegada = (dN, dE) => this.zonas.some(o => o !== z && Math.abs(o.meta.N0 - (Z.N0 + dN * lado)) < 0.5 && Math.abs(o.meta.E0 - (Z.E0 + dE * lado)) < 0.5);
      const libre = [!pegada(-1, 0), !pegada(1, 0), !pegada(0, -1), !pegada(0, 1)];      // sur, norte, oeste, este
      const muestra = (N, E) => {                  // [altura sobre el mar, fraccion de agua] bilineal, o null fuera de la zona
        let i = (N - Z.N0) / paso, j = (E - Z.E0) / paso;
        if (i < 0 || j < 0 || i > n - 1 || j > n - 1) return null;
        i = Math.min(n - 1.001, i); j = Math.min(n - 1.001, j);
        const i0 = Math.floor(i), j0 = Math.floor(j), fi = i - i0, fj = j - j0, k = i0 * n + j0;
        let h = 0, a = 0;
        for (const [kk, w] of [[k, (1 - fi) * (1 - fj)], [k + n, fi * (1 - fj)], [k + 1, (1 - fi) * fj], [k + n + 1, fi * fj]]) {
          const v = D[kk]; if (v === -32768) a += w; else h += w * v / 10;
        }
        return [a < 1 ? h / (1 - a) : 0, a];
      };
      const borde = (N, E) => Math.min(libre[0] ? N - Z.N0 : Infinity, libre[1] ? Z.N0 + lado - N : Infinity,
                                       libre[2] ? E - Z.E0 : Infinity, libre[3] ? Z.E0 + lado - E : Infinity);   // distancia al borde libre (m)
      return { muestra, borde };
    });
    const buscar = (N, E) => { for (const q of Zs) { const m = q.muestra(N, E); if (m) return [m, q]; } return null; };
    this.muestraZona = (N, E) => { const r = buscar(N, E); return r ? r[0] : null; };
    this.altura = (N, E) => {
      const r = buscar(N, E); if (!r) return this.alturaMundo(N, E);
      const m = r[0], q = r[1], hz = (m[1] > 0.7 ? 0 : Math.max(0, m[0])) - h0, d = q.borde(N, E);
      return d >= 100 ? hz : hz * d / 100 + this.alturaMundo(N, E) * (1 - d / 100);
    };
    this.enMar = (N, E) => { const r = buscar(N, E); return r ? r[0][1] > 0.7 : this.enMarMundo(N, E); };
  }

  /** Arboles solidos (los que se dibujan): listas [E, N, radio, y0, y1] (y0 y1: pie y copa, m hacia arriba como -p[2])
   *  por clave: "campo" (la isla) y en un mundo real "region" y "zona:<id>". Las mismas medidas en los dos simuladores
   *  (Entorno.arbol: la copa de un arbol de radio de copa rc). Los de la isla solo cuentan en la isla y los demas solo en
   *  el mundo real. Rejilla de 25 m para buscar los de cerca. */
  ponerArboles(clave, lista) {
    this._arboles = this._arboles || {};
    if (lista && lista.length) this._arboles[clave] = lista; else delete this._arboles[clave];
    this._rejArb = null;
  }
  quitarArboles(prefijo) { for (const k of Object.keys(this._arboles || {})) if (k.startsWith(prefijo)) delete this._arboles[k]; this._rejArb = null; }
  /** true si el avion (posicion NED, semienvergadura en m) toca un arbol. */
  chocaArbol(p, semi) {
    if (!this._rejArb) {
      const C = 25, R = this._rejArb = new Map();
      for (const [k, lista] of Object.entries(this._arboles || {})) {
        if ((k === "campo") !== !this.mundo) continue;
        for (const t of lista) for (let i = Math.floor((t[0] - t[2]) / C); i <= Math.floor((t[0] + t[2]) / C); i++)
          for (let j = Math.floor((t[1] - t[2]) / C); j <= Math.floor((t[1] + t[2]) / C); j++) { const q = i * 100003 + j; if (!R.has(q)) R.set(q, []); R.get(q).push(t); }
      }
    }
    const up = -p[2], c = this._rejArb.get(Math.floor(p[1] / 25) * 100003 + Math.floor(p[0] / 25));
    if (c) for (const t of c) if (up < t[4] && up > t[3] - 0.3 && Math.hypot(p[1] - t[0], p[0] - t[1]) < t[2] + 0.8 * semi) return true;
    return false;
  }

  /** true si el avion (posicion NED, semienvergadura en m) toca un pilon. */
  chocaPilon(p, semi) {
    if (this.mundo) return false;
    const h = -p[2], P = this.pilon;
    if (h > P.alto + 0.3) return false;
    const r = P.r0 + (P.r1 - P.r0) * Math.max(0, h) / P.alto;
    return this.pilones().concat(this.pilonesPuerta()).some(s => Math.hypot(p[0] - s[0], p[1] - s[1]) < r + semi * 0.8);
  }

  /** Cuenta vueltas al circuito: un objeto por vuelo, con actualizar(pAnt, p, t) en cada paso. sentido: +1 (verde,
   *  amarillo, rojo, azul), -1 (al reves) o 0 (cualquiera). */
  contadorVueltas(sentido = 0) { return new ContadorVueltas(this.circuito, sentido); }

  /** Texto del orden de paso de un sentido: "verde → amarillo → rojo → azul". */
  ordenPilones(sentido) {
    const n = this.circuito.colores.map(c => c.nombre);
    return sentido ? (sentido > 0 ? n : n.slice().reverse()).join(" → ") : "en cualquier sentido";
  }

  /** Cruce de la linea de la puerta entre dos pasos: null, {tipo: "puerta", sentido: "este" | "oeste", h},
   *  {tipo: "alta", h} (por encima de los pilones: no cuenta) o {tipo: "fuera"} (por el lado de un pilon). */
  cruzaPuerta(pAnt, p) {
    const P = this.zona2.puerta, a = pAnt[1] - P.e, b = p[1] - P.e;
    if ((a < 0) === (b < 0)) return null;
    const t = a / (a - b), n = pAnt[0] + t * (p[0] - pAnt[0]), h = -(pAnt[2] + t * (p[2] - pAnt[2]));
    if (n > P.n0 && n < P.n1) return h < this.pilon.alto ? { tipo: "puerta", sentido: b > a ? "este" : "oeste", h } : { tipo: "alta", h };
    if (n > P.n0 - 30 && n < P.n1 + 30 && h < 40) return { tipo: "fuera" };
    return null;
  }

  /** Pasadas bajas por la pista 2: un objeto por vuelo, con actualizar(p) en cada paso. */
  pasadaBaja() { return new PasadaBaja(this.zona2.pista); }

  /** Distancia horizontal (m) de (N, E) al centro de la diana y los puntos de esa toma. */
  diana(N, E) {
    const D = this.zona2.diana, d = Math.hypot(N - D.n, E - D.e), a = D.anillos.find(([r]) => d <= r);
    return { d, puntos: a ? a[1] : 0 };
  }

  /** true si (N, E) esta sobre la pista, con margen. */
  enPista(N, E, margen = 3) {
    const P = this.pista;
    return Math.abs(E) <= P.ancho / 2 + margen && N >= P.n0 - 5 && N <= P.n1 + 15;
  }
}

// =====================================================================
//  VUELTAS AL CIRCUITO. Se mira el angulo del avion alrededor del centro del rectangulo: cuando cruza
//  la direccion de un pilon, ese pilon esta pasado; por fuera si el avion esta mas lejos del centro que
//  el pilon. Una vuelta = rodear las 4 esquinas por fuera, en el mismo sentido, hasta volver al pilon
//  de salida. Cortar uno por dentro anula la vuelta en curso. Si el circuito tiene sentido obligatorio,
//  pasar un pilon en el sentido contrario tampoco cuenta y anula la vuelta en curso.
// =====================================================================
class ContadorVueltas {
  constructor(circuito, sentido = 0) {
    this.c = circuito.centro;
    this.pil = circuito.pilones.map(([n, e]) => ({ ang: Math.atan2(e - this.c[1], n - this.c[0]), r: Math.hypot(n - this.c[0], e - this.c[1]) }));
    this.sentido = sentido;     // +1, -1 o 0 (cualquiera)
    this.serie = [];            // pilones pasados por fuera en la vuelta en curso: {i, sentido}
    this.vueltas = 0; this.tInicio = null; this.mejor = null; this.ultima = null;
  }

  /** Indice del siguiente pilon que toca rodear, o null si aun no se ha pasado ninguno (se puede salir de
   *  cualquiera) y el sentido es libre. */
  siguiente() {
    const ult = this.serie[this.serie.length - 1];
    if (!ult) return null;
    return (ult.i + (this.sentido || ult.sentido) + 4) % 4;
  }

  /** Devuelve null o un suceso: {tipo: "pilon" | "dentro" | "sentido" | "vuelta", i, n, tiempo}. */
  actualizar(pAnt, p, t) {
    const c = this.c, a0 = Math.atan2(pAnt[1] - c[1], pAnt[0] - c[0]), a1 = Math.atan2(p[1] - c[1], p[0] - c[0]);
    const r = Math.hypot(p[0] - c[0], p[1] - c[1]);
    if (r < 15) return null;
    const vuelta = x => x - 2 * Math.PI * Math.round(x / (2 * Math.PI));
    const d = vuelta(a1 - a0);
    if (d === 0) return null;
    for (let i = 0; i < this.pil.length; i++) {
      const hasta = vuelta(this.pil[i].ang - a0);
      if (Math.sign(hasta) !== Math.sign(d) || Math.abs(hasta) > Math.abs(d)) continue;     // no cruza este pilon
      const sentido = Math.sign(d);
      if (r <= this.pil[i].r) { this.serie = []; this.tInicio = null; return { tipo: "dentro", i }; }
      if (this.sentido && sentido !== this.sentido) { this.serie = []; this.tInicio = null; return { tipo: "sentido", i }; }
      const ult = this.serie[this.serie.length - 1];
      if (ult && (ult.sentido !== sentido || i !== (ult.i + sentido + 4) % 4)) this.serie = [];
      if (!this.serie.length) this.tInicio = t;
      this.serie.push({ i, sentido });
      if (this.serie.length === 5) {       // de vuelta al pilon de salida: las 4 esquinas rodeadas
        this.vueltas++; this.ultima = t - this.tInicio;
        if (this.mejor === null || this.ultima < this.mejor) this.mejor = this.ultima;
        this.serie = [{ i, sentido }]; this.tInicio = t;      // este pilon abre la vuelta siguiente
        return { tipo: "vuelta", i, n: this.vueltas, tiempo: this.ultima };
      }
      return { tipo: "pilon", i, n: this.serie.length };
    }
    return null;
  }
}

// =====================================================================
//  PASADA BAJA por la pista 2: entrar por una punta de la pista (de este a oeste o al reves), recorrerla
//  entera sin salirse por los lados (ancho/2 + margen a cada lado del eje) y salir por la otra punta,
//  siempre entre hmin y hmax de altura. Tocar el suelo ya termina el vuelo (lo mira el Entorno).
// =====================================================================
class PasadaBaja {
  constructor(pista) { this.P = pista; this.en = null; this.validas = 0; }

  /** Devuelve null o, al salir de la pista, {ok, sentido: "este" | "oeste", hmin, hmax, motivo}. */
  actualizar(p) {
    const P = this.P, h = -p[2];
    const dentro = Math.abs(p[0] - P.n) <= P.ancho / 2 + P.margen && p[1] >= P.e0 && p[1] <= P.e1;
    if (dentro) {
      if (!this.en) this.en = { desde: p[1] < (P.e0 + P.e1) / 2 ? "oeste" : "este", e: p[1], hmin: h, hmax: h };
      else { this.en.hmin = Math.min(this.en.hmin, h); this.en.hmax = Math.max(this.en.hmax, h); }
      return null;
    }
    if (!this.en) return null;
    const e = this.en; this.en = null;
    const sale = p[1] > P.e1 ? "este" : p[1] < P.e0 ? "oeste" : "lado";
    const r = { ok: false, sentido: sale, hmin: e.hmin, hmax: e.hmax };
    if (sale === "lado") r.motivo = "te has salido de la pista por un lado";
    else if (sale === e.desde) r.motivo = "no la has recorrido de punta a punta";
    else if (e.hmax > P.hmax) r.motivo = `demasiado alta (${e.hmax.toFixed(1)} m; máximo ${P.hmax} m)`;
    else if (e.hmin < P.hmin) r.motivo = `demasiado baja (${e.hmin.toFixed(1)} m; mínimo ${P.hmin} m)`;
    else { r.ok = true; this.validas++; }
    // solo avisa de las que de verdad intentan ser una pasada: bajas y siguiendo la pista al menos 20 m (cruzarla
    // alta o de lado, como al lanzar, no es nada)
    return e.hmin <= P.hmax + 7 && (sale !== "lado" || Math.abs(p[1] - e.e) > 20) ? r : null;
  }
}
