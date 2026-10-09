"use strict";
// =====================================================================
//  ENTORNO: el campo de vuelo. Viento con rachas, pista, los 4 pilones tipo Red Bull que marcan el
//  circuito (se rodean siempre por fuera) y las reglas del suelo (aterrizaje o accidente).
//
//  Coordenadas NED en metros con origen en el piloto, que mira al norte. La pista va hacia el norte.
// =====================================================================
class Entorno {
  constructor() {
    this.pista = { n0: 10, n1: 70, ancho: 10 };                       // N 10 a 70, centrada en E = 0
    // circuito: rectangulo de 120 x 180 m delante del piloto, con la pista dentro. Pilones en las esquinas
    // (N, E), ordenados por angulo alrededor del centro: los indices consecutivos son esquinas vecinas
    this.circuito = { centro: [100, 0], pilones: [[40, -90], [160, -90], [160, 90], [40, 90]] };
    this.pilon = { alto: 20, r0: 1.4, r1: 0.45 };                    // cono hinchable: radio abajo y arriba
    this.viento = { base: 2, rumbo: Math.PI, rachas: true, r: [0, 0, 0], actual: [0, 0, 0] };   // rumbo: hacia donde va
    // limites de un aterrizaje sin daños, y del campo: a mas de aviso_m se avisa, a mas de distancia_m el
    // avion ya no se ve desde el piloto y el vuelo termina "fuera de limites" (asi nadie se queda atrapado
    // en una espiral lejos del campo: R y a empezar de nuevo)
    this.limites = { descenso_ms: 2.5, alabeo_grados: 30, vel_suelo_ms: 12, cabeceo_grados: 25, aviso_m: 400, distancia_m: 650 };
  }

  /** vel en m/s; desde = de donde viene el viento (grados: 0 norte, 90 este...). */
  configurarViento({ vel, desde, rachas }) {
    this.viento.base = vel; this.viento.rumbo = ((desde + 180) % 360) * Math.PI / 180; this.viento.rachas = rachas;
    this.viento.r = [0, 0, 0];
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
    } else v.r = [0, 0, 0];
    v.actual = [base[0] + v.r[0], base[1] + v.r[1], v.r[2]];
    return v.actual;
  }

  /** Contacto con el suelo: null si sigue en el aire; si no, "aterrizado" o "roto (motivo)". */
  contactoSuelo(av, vn) {
    if (av.p[2] < 0) return null;
    av.p[2] = 0;
    const [roll, pitch] = Cuat.euler(av.q), vz = -vn[2], vel = Math.hypot(vn[0], vn[1]), L = this.limites;
    if (vz < -L.descenso_ms) return "roto (demasiado descenso)";
    if (Math.abs(roll) > L.alabeo_grados * D2R) return "roto (ala en el suelo)";
    if (vel > L.vel_suelo_ms) return "roto (demasiada velocidad)";
    if (Math.abs(pitch) > L.cabeceo_grados * D2R) return "roto (morro en el suelo)";
    return "aterrizado";
  }

  pilones() { return this.circuito.pilones; }

  /** Distancia horizontal al piloto (m) y si esta fuera del campo. */
  distancia(p) { return Math.hypot(p[0], p[1]); }
  fueraDeLimites(p) { return this.distancia(p) > this.limites.distancia_m; }

  /** true si el avion (posicion NED, semienvergadura en m) toca un pilon. */
  chocaPilon(p, semi) {
    const h = -p[2], P = this.pilon;
    if (h > P.alto + 0.3) return false;
    const r = P.r0 + (P.r1 - P.r0) * Math.max(0, h) / P.alto;
    return this.pilones().some(s => Math.hypot(p[0] - s[0], p[1] - s[1]) < r + semi * 0.8);
  }

  /** Cuenta vueltas al circuito: un objeto por vuelo, con actualizar(pAnt, p, t) en cada paso. */
  contadorVueltas() { return new ContadorVueltas(this.circuito); }

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
//  de salida. Cortar uno por dentro anula la vuelta en curso.
// =====================================================================
class ContadorVueltas {
  constructor(circuito) {
    this.c = circuito.centro;
    this.pil = circuito.pilones.map(([n, e]) => ({ ang: Math.atan2(e - this.c[1], n - this.c[0]), r: Math.hypot(n - this.c[0], e - this.c[1]) }));
    this.serie = [];            // pilones pasados por fuera en la vuelta en curso: {i, sentido}
    this.vueltas = 0; this.tInicio = null; this.mejor = null; this.ultima = null;
  }

  /** Devuelve null o un suceso: {tipo: "pilon" | "dentro" | "vuelta", i, n, tiempo}. */
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
