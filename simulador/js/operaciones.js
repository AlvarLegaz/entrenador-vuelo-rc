"use strict";
// =====================================================================
//  OPERACIONES: los trabajos de operador de dron (escenarios.js, "operacion") en el mapa real de Cartagena, con el DJI:
//  inspeccion de edificios, fotogrametria, busqueda y rescate, agricultura, inspeccion de una linea electrica y grabacion
//  de video. Evalua lo que pide cada orden de trabajo (las fotos, la cobertura, la posicion enviada, la orbita...) y las
//  normas del operador en todas (120 m, a la vista, fuera de la zona del aeropuerto, aterrizar en el punto de despegue y
//  con reserva de bateria), y detecta los choques con los cables, las torres y el faro. Lo dibuja js/visor_real.js
//  (ponerOperacion). simulador_godot/scripts/operaciones.gd es su traduccion literal: mismos datos, reglas y textos.
//
//  Uso: op = new Operacion(datos, marcar, anotar, {casa: [N, E], suelo(N, E), h0}); en cada paso de la fisica
//  op.paso(pAnt, av, dt, {gimbal, grabando}) devuelve los avisos (toasts) y deja op.choque si ha chocado; con cada foto
//  op.foto(av, gimbal) devuelve el aviso de esa foto; al acabar op.final(final, av, {bateria}); op.ahora(obj, av) es la
//  linea "Ahora: ..." del panel.
// =====================================================================
const OPS = {
  TECHO: 120,                                     // m sobre el suelo
  VLOS: 500,                                      // m del piloto (en horizontal)
  ARP: { nombre: "aeropuerto de San Javier", n: 17936.4, e: 20962.4, r: 8000 },   // zona de aerodromo (8 km)
  CAM_V: 29,                                      // semiangulo vertical de la camara del DJI (grados)
  CAM_H: Math.atan(Math.tan(29 * Math.PI / 180) * 4 / 3) * 180 / Math.PI,         // horizontal (foto 4:3)
  CASA: 10, RESERVA: 20,                          // aterrizar a menos de 10 m del despegue, con mas del 20 % de bateria
};
const opDesenrollar = d => d - 2 * Math.PI * Math.round(d / (2 * Math.PI));
const opMMSS = s => `${Math.floor(s / 60)}:${String(Math.floor(s % 60)).padStart(2, "0")}`;

class Operacion {
  constructor(d, marcar, anotar, mundo) {
    this.d = d; this.marcar = marcar; this.anotar = anotar; this.casa = mundo.casa; this.suelo = mundo.suelo; this.h0 = mundo.h0;
    this.choque = null; this.avisos = {}; this.t0 = null; this.fotos = 0;
    this.hechos = [];                                                           // inspeccion, manchas, torres
    if (d.parcela && d.solape) {                                                // fotogrametria: celdas de 5 m de la parcela
      const P = d.parcela; this.celdas = [];
      for (let n = P.n0 + 2.5; n < P.n1; n += 5) for (let e = P.e0 + 2.5; e < P.e1; e += 5) this.celdas.push([n, e, 0]);
    }
    if (d.torres) this._linea();
    this.encontrado = false; this.error = null;                                 // busqueda
    this.orb = null; this.yawAnt = null; this.giro = 0; this.dCables = Infinity; // video y linea
  }

  /** Punto (N, E, arriba) de un objetivo: con cota (m sobre el mar) o h (m sobre el suelo). */
  z(n, e, cota, h) { return cota !== undefined ? cota - this.h0 : this.suelo(n, e) + (h || 0); }

  /** Un punto P (N, E, arriba) en la camara del dron (gimbal en grados): x hacia delante, y a la derecha, z hacia abajo
   *  de la imagen, d distancia. */
  static camara(av, gimbal, P) {
    const y = Cuat.euler(av.q)[2], g = gimbal * D2R, cy = Math.cos(y), sy = Math.sin(y), cg = Math.cos(g), sg = Math.sin(g);
    const v = [P[0] - av.p[0], P[1] - av.p[1], -(P[2] + av.p[2])];
    return { x: v[0] * cy * cg + v[1] * sy * cg - v[2] * sg, y: -v[0] * sy + v[1] * cy, z: v[0] * cy * sg + v[1] * sy * sg + v[2] * cg, d: Math.hypot(v[0], v[1], v[2]) };
  }
  /** Dentro de la imagen (k = 1 el borde; 0,8 bien encuadrado; 0,3 en el centro). */
  static enFoto(c, k) { return c.x > 0 && Math.abs(c.y) <= k * Math.tan(OPS.CAM_H * D2R) * c.x && Math.abs(c.z) <= k * Math.tan(OPS.CAM_V * D2R) * c.x; }

  _aviso(clave, texto, lista) { if (!this.avisos[clave]) { this.avisos[clave] = true; lista.push(texto); } }

  /** Linea electrica: postes de cada torre y vanos de los cables (3: dos fases en la cruceta y el de tierra arriba), con
   *  su flecha en el centro del vano. */
  _linea() {
    const d = this.d, T = d.torres, n = T.length;
    this.bases = T.map(([N, E]) => this.suelo(N, E));
    this.laterales = T.map((_, i) => {
      const a = T[Math.max(0, i - 1)], b = T[Math.min(n - 1, i + 1)], L = Math.hypot(b[0] - a[0], b[1] - a[1]);
      return [-(b[1] - a[1]) / L, (b[0] - a[0]) / L];
    });
    this.enganches = T.map(([N, E], i) => [-1, 1, 0].map(k => [N + this.laterales[i][0] * d.brazo * k, E + this.laterales[i][1] * d.brazo * k, this.bases[i] + (k === 0 ? d.alto : d.fases)]));
    this.cables = [];
    for (let i = 0; i + 1 < n; i++) for (let k = 0; k < 3; k++) {
      const A = this.enganches[i][k], B = this.enganches[i + 1][k], M = [(A[0] + B[0]) / 2, (A[1] + B[1]) / 2, (A[2] + B[2]) / 2 - d.flecha];
      this.cables.push([A, M], [M, B]);
    }
  }
  static distSegmento(P, A, B) {
    const ab = [B[0] - A[0], B[1] - A[1], B[2] - A[2]], ap = [P[0] - A[0], P[1] - A[1], P[2] - A[2]];
    const t = Math.max(0, Math.min(1, (ap[0] * ab[0] + ap[1] * ab[1] + ap[2] * ab[2]) / (ab[0] * ab[0] + ab[1] * ab[1] + ab[2] * ab[2])));
    return Math.hypot(ap[0] - t * ab[0], ap[1] - t * ab[1], ap[2] - t * ab[2]);
  }

  /** Un paso de la fisica. info: {gimbal (grados), grabando (video)}. */
  paso(pAnt, av, dt, info) {
    const d = this.d, T = [], N = av.p[0], E = av.p[1], up = -av.p[2], agl = up - this.suelo(N, E), t = av.t, m = this.marcar;
    if (av.estado !== "volando") return T;
    if (this.t0 === null && !av.posado) this.t0 = t;                           // despegue: empieza a contar el tiempo
    // ---- choques: cables y torres de la linea, faro ----
    if (d.torres) {
      this.dCables = Math.min(...this.cables.map(([A, B]) => Operacion.distSegmento([N, E, up], A, B)));
      if (this.dCables < 0.6) this.choque = "choque con los cables";
      d.torres.forEach(([tn, te], i) => {
        const hb = up - this.bases[i], L = this.laterales[i], a = (N - tn) * L[0] + (E - te) * L[1], b = -(N - tn) * L[1] + (E - te) * L[0];
        if (hb < d.alto && Math.abs(N - tn) < 1.6 && Math.abs(E - te) < 1.6) this.choque = `choque con la torre ${i + 1}`;
        if (Math.abs(hb - d.fases - 1.2) < 0.6 && Math.abs(a) < d.brazo + 0.3 && Math.abs(b) < 0.6) this.choque = `choque con la cruceta de la torre ${i + 1}`;
      });
    }
    if (d.faro) {
      const F = d.faro;
      if (Math.hypot(N - F.n, E - F.e) < F.radio + 0.3 && up - this.suelo(F.n, F.e) < F.alto) this.choque = "choque con el faro";
    }
    if (this.choque) return T;
    // ---- normas del operador ----
    if (agl > OPS.TECHO) { m("techo", "mal"); this._aviso("techo", "¡Por encima de 120 m de altura! Baja", T); }
    if (Math.hypot(N - this.casa[0], E - this.casa[1]) > OPS.VLOS) { m("vlos", "mal"); this._aviso("vlos", "¡Más de 500 m del piloto! Ya no lo ves: vuelve", T); }
    if (Math.hypot(N - OPS.ARP.n, E - OPS.ARP.e) < OPS.ARP.r) { m("zona", "mal"); this._aviso("zona", `¡Dentro de la zona del ${OPS.ARP.nombre}!`, T); }
    // ---- agricultura: nunca a menos de 5 m sobre el cultivo ----
    if (d.manchas) {
      const P = d.parcela;
      if (N > P.n0 && N < P.n1 && E > P.e0 && E < P.e1 && agl < d.minima && !av.posado) { m("baja", "mal"); this._aviso("baja", `¡A ${agl.toFixed(1)} m del cultivo! No bajes de ${d.minima} m`, T); }
    }
    // ---- linea: distancia de seguridad a los cables ----
    if (d.torres && this.dCables < d.seguridad) { m("distancia", "mal"); this._aviso("distancia", `¡A ${this.dCables.toFixed(1)} m de los cables! La distancia de seguridad son ${d.seguridad} m`, T); }
    // ---- busqueda: el tiempo ----
    if (d.zona && !this.encontrado && this.t0 !== null && t - this.t0 > d.limite_s) { m("tiempo", "mal"); this._aviso("tiempo", "Se ha acabado el tiempo: el equipo de tierra sigue buscando", T); }
    // ---- video: giro suave y orbita ----
    if (d.faro) {
      const yaw = Cuat.euler(av.q)[2];
      if (this.yawAnt !== null && dt > 0) this.giro += (Math.abs(opDesenrollar(yaw - this.yawAnt)) / dt - this.giro) * Math.min(1, dt / 0.2);
      this.yawAnt = yaw;
      if (info.grabando && this.giro > d.giro_max * D2R) { m("suave", "mal"); this._aviso("suave", `Tirón en el vídeo: giro de ${(this.giro * R2D).toFixed(0)}°/s (máximo ${d.giro_max})`, T); }
      const F = d.faro, r = Math.hypot(N - F.n, E - F.e), c = Operacion.camara(av, info.gimbal, [F.n, F.e, this.suelo(F.n, F.e) + 0.6 * F.alto]);
      const centrado = c.x > 0 && Math.abs(c.y) <= Math.tan(d.centrado * D2R) * c.x && Math.abs(c.z) <= 0.9 * Math.tan(OPS.CAM_V * D2R) * c.x;
      const vale = info.grabando && r >= d.orbita[0] && r <= d.orbita[1] && centrado, a = Math.atan2(E - F.e, N - F.n);
      if (!this.avisos.orbita) {
        if (vale) {
          if (!this.orb) { this.orb = { acc: 0, prev: a, hmin: up, hmax: up, fuera: 0 }; T.push("Órbita: empieza"); }
          const O = this.orb; O.acc += opDesenrollar(a - O.prev); O.prev = a; O.hmin = Math.min(O.hmin, up); O.hmax = Math.max(O.hmax, up); O.fuera = 0;
          if (O.hmax - O.hmin > 2 * d.variacion) { this.orb = null; T.push(`Cambio de altura de más de ${2 * d.variacion} m: la órbita empieza de nuevo`); }
          else if (Math.abs(O.acc) >= 2 * Math.PI * 0.92) { m("orbita", "ok"); this._aviso("orbita", "¡Órbita completa! Vuelve al punto de despegue", T); this.orb = null; }
        } else if (this.orb) {
          this.orb.prev = a; this.orb.fuera += dt;
          if (this.orb.fuera > 1) {
            T.push("Órbita perdida: " + (!info.grabando ? "no estás grabando" : r < d.orbita[0] ? "demasiado cerca del faro" : r > d.orbita[1] ? "demasiado lejos del faro" : "el faro se ha salido del centro de la imagen"));
            this.orb = null;
          }
        }
      }
    }
    return T;
  }

  /** Una foto (boton de foto del DJI): lo que vale para el trabajo y el aviso. */
  foto(av, gimbal) {
    const d = this.d, T = [], N = av.p[0], E = av.p[1], up = -av.p[2], agl = up - this.suelo(N, E), m = this.marcar;
    this.fotos++;
    if (av.estado !== "volando" || av.posado) return T;
    if (d.puntos) {                                    // inspeccion: cada punto bien encuadrado, cerca, de frente o desde arriba
      let motivo = null;
      d.puntos.forEach((q, i) => {
        if (this.hechos[i]) return;
        const P = [q.n, q.e, this.z(q.n, q.e, q.cota, q.h)], c = Operacion.camara(av, gimbal, P);
        if (!Operacion.enFoto(c, 1)) return;
        const cara = q.normal !== undefined ? ((N - P[0]) * Math.cos(q.normal * D2R) + (E - P[1]) * Math.sin(q.normal * D2R)) / c.d : (up - P[2]) / c.d;
        if (c.d > d.dist[1]) motivo = motivo || `punto ${i + 1} demasiado lejos (${c.d.toFixed(0)} m; acércate a menos de ${d.dist[1]} m)`;
        else if (c.d < d.dist[0]) motivo = motivo || `punto ${i + 1} demasiado cerca`;
        else if (!Operacion.enFoto(c, 0.8)) motivo = motivo || `punto ${i + 1} en el borde de la foto: encuádralo`;
        else if (cara < 0.5) motivo = motivo || `punto ${i + 1}: ${q.normal !== undefined ? "la fachada se fotografía de frente" : "la cubierta se fotografía desde arriba"}`;
        else { this.hechos[i] = true; T.push(`Punto ${i + 1}: ${q.nombre} ✓ (${this.hechos.filter(Boolean).length}/${d.puntos.length})`); }
      });
      if (this.hechos.filter(Boolean).length === d.puntos.length) m("puntos", "ok");
      if (!T.length) T.push(motivo ? "Foto no válida: " + motivo : "Foto sin ningún punto de inspección");
    }
    if (d.solape) {                                    // fotogrametria: cobertura de cada foto vertical a la altura pedida
      if (gimbal > d.gimbal) T.push(`Foto no válida: la cámara no mira abajo (${gimbal.toFixed(0)}°; hace falta ${d.gimbal}° o más)`);
      else if (agl < d.altura[0] || agl > d.altura[1]) T.push(`Foto no válida: a ${agl.toFixed(0)} m (entre ${d.altura[0]} y ${d.altura[1]} m)`);
      else {
        const y = Cuat.euler(av.q)[2], cy = Math.cos(y), sy = Math.sin(y), lv = agl * Math.tan(OPS.CAM_V * D2R), lh = agl * Math.tan(OPS.CAM_H * D2R);
        let dentro = 0;
        for (const q of this.celdas) {
          const dn = q[0] - N, de = q[1] - E;
          if (Math.abs(dn * cy + de * sy) <= lv && Math.abs(-dn * sy + de * cy) <= lh) { q[2]++; dentro++; }
        }
        if (!dentro) T.push("La foto no cae en la parcela");
        else {
          const pct = this.cobertura();
          T.push(`Foto válida · parcela cubierta con solape: ${(pct * 100).toFixed(0)} %`);
          if (pct >= d.cubrir) { m("cobertura", "ok"); this._aviso("cobertura", "¡Parcela cubierta! Vuelve al punto de despegue", T); }
        }
      }
    }
    if (d.zona && d.persona && !this.encontrado) {     // busqueda: foto con la persona en el centro y la posicion enviada
      const sp = this.suelo(d.persona[0], d.persona[1]), c = Operacion.camara(av, gimbal, [d.persona[0], d.persona[1], sp + 0.9]);
      if (Operacion.enFoto(c, 0.3) && c.d <= d.dist) {
        const y = Cuat.euler(av.q)[2], g = gimbal * D2R;
        let est = [N, E];
        if (Math.sin(g) < -0.05) { const k = (sp - up) / Math.sin(g); est = [N + k * Math.cos(y) * Math.cos(g), E + k * Math.sin(y) * Math.cos(g)]; }
        this.error = Math.hypot(est[0] - d.persona[0], est[1] - d.persona[1]); this.encontrado = true;
        m("localizar", "ok"); m("posicion", this.error <= 10 ? "ok" : "mal");
        m("tiempo", this.t0 !== null && av.t - this.t0 <= d.limite_s ? "ok" : "mal");
        T.push(`¡Encontrado! Posición enviada a ${this.error.toFixed(1)} m de la real` + (this.error <= 10 ? "" : ": demasiado error (inclina la cámara hacia él)"));
      } else if (Operacion.enFoto(c, 1) && c.d <= 2 * d.dist) T.push("Sale en la foto, pero no en el centro: céntralo y acércate para enviar su posición");
      else T.push(`Foto ${this.fotos}: no se le ve`);
    }
    if (d.manchas) {                                   // agricultura: cada mancha desde arriba y a la altura pedida
      let motivo = null;
      d.manchas.forEach(([mn, me], i) => {
        if (this.hechos[i]) return;
        const sm = this.suelo(mn, me), c = Operacion.camara(av, gimbal, [mn, me, sm]);
        if (!Operacion.enFoto(c, 0.9)) return;
        const h = up - sm;
        if (gimbal > d.gimbal) motivo = motivo || `la cámara tiene que mirar abajo (${d.gimbal}° o más)`;
        else if (h < d.altura[0] || h > d.altura[1]) motivo = motivo || `a ${h.toFixed(0)} m de la mancha ${i + 1} (entre ${d.altura[0]} y ${d.altura[1]} m)`;
        else { this.hechos[i] = true; T.push(`Mancha ${i + 1} ✓ (${this.hechos.filter(Boolean).length}/${d.manchas.length})`); }
      });
      if (this.hechos.filter(Boolean).length === d.manchas.length) m("manchas", "ok");
      if (!T.length) T.push(motivo ? "Foto no válida: " + motivo : "Foto sin ninguna mancha");
    }
    if (d.torres) {                                    // linea: los aisladores de cada torre, de 8 a 25 m
      let motivo = null;
      d.torres.forEach(([tn, te], i) => {
        if (this.hechos[i]) return;
        const c = Operacion.camara(av, gimbal, [tn, te, this.bases[i] + d.fases]);
        if (!Operacion.enFoto(c, 0.8)) return;
        if (c.d > d.dist[1]) motivo = motivo || `torre ${i + 1} demasiado lejos (${c.d.toFixed(0)} m; a menos de ${d.dist[1]} m)`;
        else if (c.d < d.dist[0]) motivo = motivo || `torre ${i + 1} demasiado cerca`;
        else { this.hechos[i] = true; T.push(`Torre ${i + 1} ✓ (${this.hechos.filter(Boolean).length}/${d.torres.length})`); }
      });
      if (this.hechos.filter(Boolean).length === d.torres.length) m("torres", "ok");
      if (!T.length) T.push(motivo ? "Foto no válida: " + motivo : "Foto sin los aisladores de ninguna torre");
    }
    if (d.faro) T.push("Este trabajo es de vídeo: pulsa V para grabar");
    return T;
  }

  /** Parte de la parcela cubierta con solape (0-1). */
  cobertura() { return this.celdas.filter(q => q[2] >= this.d.solape).length / this.celdas.length; }

  /** Al acabar el vuelo: aterrizar en el punto de despegue y con reserva de bateria; y el resumen en los objetivos. */
  final(final, av, info) {
    const d = this.d, a = this.anotar, n = this.hechos.filter(Boolean).length;
    if (final === "aterrizado") {
      const dc = Math.hypot(av.p[0] - this.casa[0], av.p[1] - this.casa[1]);
      this.marcar("casa", dc <= OPS.CASA ? "ok" : "mal"); a("casa", `a ${dc.toFixed(1)} m`);
      this.marcar("reserva", info.bateria >= OPS.RESERVA ? "ok" : "mal"); a("reserva", `${info.bateria.toFixed(0)} %`);
    }
    if (d.puntos) a("puntos", `${n} de ${d.puntos.length}`);
    if (d.solape) a("cobertura", `${(this.cobertura() * 100).toFixed(0)} %`);
    if (d.zona && this.error !== null) a("posicion", `error ${this.error.toFixed(1)} m`);
    if (d.manchas) a("manchas", `${n} de ${d.manchas.length}`);
    if (d.torres) a("torres", `${n} de ${d.torres.length}`);
  }

  /** Lo que toca ahora (texto del panel, con <b>). */
  ahora(obj, av) {
    const d = this.d, hecho = k => obj[k] && obj[k].estado === "ok", N = av.p[0], E = av.p[1], n = this.hechos.filter(Boolean).length;
    const volver = `Ahora: <b>vuelve al punto de despegue y aterriza</b> (a ${Math.hypot(N - this.casa[0], E - this.casa[1]).toFixed(0)} m)`;
    if (this.t0 === null) return "Ahora: <b>despega</b> (botón de despegue o L) y ve a la zona de trabajo";
    if (d.puntos) {
      const i = d.puntos.findIndex((_, k) => !this.hechos[k]);
      return i < 0 ? volver : `Puntos fotografiados: <b>${n} de ${d.puntos.length}</b> · siguiente: ${d.puntos[i].nombre} (punto ${i + 1}, a ${Math.hypot(N - d.puntos[i].n, E - d.puntos[i].e).toFixed(0)} m)`;
    }
    if (d.solape) return hecho("cobertura") ? volver : `Parcela cubierta con solape: <b>${(this.cobertura() * 100).toFixed(0)} %</b> (hace falta ${(d.cubrir * 100).toFixed(0)} %) · altura ${Math.max(0, -av.p[2] - this.suelo(N, E)).toFixed(0)} m`;
    if (d.zona) return this.encontrado ? volver : `Tiempo: <b>${opMMSS(Math.max(0, d.limite_s - (av.t - this.t0)))}</b> · busca la chaqueta roja dentro de los jalones amarillos`;
    if (d.manchas) return n === d.manchas.length ? volver : `Manchas fotografiadas: <b>${n} de ${d.manchas.length}</b> · fotos verticales de 10 a 30 m`;
    if (d.torres) return n === d.torres.length ? volver : `Torres: <b>${n} de ${d.torres.length}</b> · a ${this.dCables.toFixed(0)} m de los cables`;
    if (d.faro) return hecho("orbita") ? volver : `Órbita: <b>${this.orb ? Math.abs(this.orb.acc * R2D).toFixed(0) : 0}°</b> de 330° · a ${Math.hypot(N - d.faro.n, E - d.faro.e).toFixed(0)} m del faro`;
    return volver;
  }
}
