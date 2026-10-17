"use strict";
// =====================================================================
//  PISTA FPV: los entrenamientos del dron FPV (escenarios.js, "pista_fpv"), en la zona despejada de detras del
//  piloto. Evalua los objetivos de cada mision (estacionario en el cilindro, la caja de conos, slalom y ocho, el
//  circuito de puertas, la recta en ACRO, power loop, split-S y picado; y en todas: modo, bateria, plataforma y
//  desarmar) y detecta los choques con los postes, las puertas y la torre. Lo dibuja js/visor.js (ponerPistaFpv).
//  simulador_godot/scripts/pista_fpv.gd es su traduccion literal: mismos datos, mismas reglas y mismos textos.
//
//  Uso: pf = new PistaFpv(datos, marcar); en cada paso de la fisica pf.paso(pAnt, av, dt, {modo, critica}) devuelve
//  los avisos (toasts) y deja pf.choque con el motivo si ha chocado; al acabar pf.final(final, av); pf.ahora() es la
//  linea "Ahora: ..." del panel ({cono:i} = el pilon de color i del circuito).
// =====================================================================
const FPV_PISTA = {
  R_DRON: 0.15,                  // radio del dron para los choques (m)
  GROSOR: 0.12,                  // tubo del marco de las puertas (m)
  PUERTA: { ancho: 2.4, alto: 2.0, h0: 0 },
  POSTE: { r: 0.05, alto: 4 },   // postes del slalom
  OCHO: { r: 0.05, alto: 5 },    // los dos postes del ocho (rojo y azul)
  CONO_R: 2, CONO_H: 3,          // un cono se toca a menos de 2 m y por debajo de 3 m
  RUMBO_TOL: 35,                 // grados
  COLOR_OCHO: [2, 3],            // colores del circuito de los postes del ocho: rojo y azul
};
const fpvDesenrollar = d => d - 2 * Math.PI * Math.round(d / (2 * Math.PI));

class PistaFpv {
  constructor(d, marcar) {
    this.d = d; this.marcar = marcar; this.choque = null;
    this.tPosado = null; this.tBat = 0; this.avisos = {};
    this.tIn = 0;                                                               // estacionario
    this.caja = { fase: 1, k: 0, dentro: -1 };                                  // la caja
    this.slalom = { k: 0, lado: 0, empezado: false, hecho: false };             // slalom
    this.ocho = { acc: [0, 0], prev: [null, null], hecho: false, vuelta: [false, false] };
    this.tFuera = 0;
    this.circ = { k: 0, n: 0, t0: null, ultima: null, mejor: null };            // circuito de puertas
    this.recta = d.recta ? new PasadaBaja(d.recta) : null;
    this.alta = { ult: null, hmax: 0 }; this.tAlto = null;                      // puerta alta y torre
  }

  /** Puertas del circuito con sus medidas. */
  puertas() { return (this.d.puertas || []).map(g => Object.assign({}, FPV_PISTA.PUERTA, g)); }

  /** Cruce del plano de una puerta entre dos posiciones: null, {tipo: "pasa", dir: 1 (de frente) | -1} o {tipo: "choque"}. */
  static cruce(pAnt, p, g) {
    const r = g.rumbo * D2R, dN = Math.cos(r), dE = Math.sin(r);
    const s0 = (pAnt[0] - g.n) * dN + (pAnt[1] - g.e) * dE, s1 = (p[0] - g.n) * dN + (p[1] - g.e) * dE;
    if ((s0 < 0) === (s1 < 0)) return null;
    const t = s0 / (s0 - s1), N = pAnt[0] + t * (p[0] - pAnt[0]), E = pAnt[1] + t * (p[1] - pAnt[1]), v = -(pAnt[2] + t * (p[2] - pAnt[2]));
    const u = Math.abs(-(N - g.n) * dE + (E - g.e) * dN), A = g.ancho / 2, H0 = g.h0, H1 = g.h0 + g.alto, gr = FPV_PISTA.GROSOR, R = FPV_PISTA.R_DRON;
    if (u < A - R && v > H0 + R && v < H1 - R) return { tipo: "pasa", dir: s1 > s0 ? 1 : -1 };
    if (u <= A + gr + R && v <= H1 + gr + R && (u >= A - R || v >= H1 - R || (H0 > 0 && v >= H0 - gr - R && v <= H0 + R))) return { tipo: "choque" };
    return null;
  }

  _aviso(clave, texto, lista) { if (!this.avisos[clave]) { this.avisos[clave] = true; lista.push(texto); } }

  /** Un paso de la fisica. info: {modo: modo de Betaflight, critica: bateria por debajo del aviso de aterrizar}. */
  paso(pAnt, av, dt, info) {
    const d = this.d, P = FPV_PISTA, T = [], p = av.p, N = p[0], E = p[1], h = -p[2], t = av.t, yaw = Cuat.euler(av.q)[2];
    const m = this.marcar;
    if (av.estado !== "volando") return T;
    // ---- choques: postes, postes del ocho, puertas, puerta alta y torre ----
    const poste = (q, c, nombre) => { if (h < c.alto && Math.hypot(N - q[0], E - q[1]) < c.r + P.R_DRON) this.choque = "choque con " + nombre; };
    (d.postes || []).forEach((q, i) => poste(q, P.POSTE, `el poste ${i + 1}`));
    (d.ocho || []).forEach((q, i) => poste(q, P.OCHO, "el poste " + ["rojo", "azul"][i]));
    if (d.torre) { const q = d.torre, l = q.lado / 2 + P.R_DRON; if (h < q.alto + P.R_DRON && Math.abs(N - q.n) < l && Math.abs(E - q.e) < l) this.choque = "choque con la torre"; }
    const gs = this.puertas(), cruces = gs.map(g => PistaFpv.cruce(pAnt, p, g));
    cruces.forEach((c, i) => { if (c && c.tipo === "choque") this.choque = `choque con la puerta ${i + 1}`; });
    const ca = d.puerta_alta ? PistaFpv.cruce(pAnt, p, d.puerta_alta) : null;
    if (ca && ca.tipo === "choque") this.choque = "choque con la puerta alta";
    if (this.choque) return T;
    // ---- en todas: despegar, modo, bateria y el momento de posarse (para desarmar a tiempo) ----
    if (av.despegado) m("despegar", "ok");
    if (av.armado && info.modo !== d.modo) { m("modo", "mal"); this._aviso("modo", `Has cambiado a ${info.modo}: este entrenamiento es en ${d.modo}`, T); }
    this.tBat = info.critica && !av.posado ? this.tBat + dt : 0;
    if (this.tBat > 3) { m("bateria", "mal"); this._aviso("bateria", "Sigues volando con la batería agotada: aterriza ya", T); }
    if (av.posado && av.despegado) { if (this.tPosado === null) this.tPosado = t; } else this.tPosado = null;
    // ---- 1. estacionario en el cilindro ----
    if (d.cilindro) {
      const c = d.cilindro, dentro = Math.hypot(N - c.n, E - c.e) <= c.r && h >= c.h0 && h <= c.h1;
      if (dentro) {
        this.tIn += dt;
        if (this.tIn >= c.t && !this.avisos.estacionario) { m("estacionario", "ok"); this._aviso("estacionario", `¡${c.t} s en el cilindro! Vuelve a la plataforma`, T); }
      } else {
        if (this.tIn > 2 && !this.avisos.estacionario) T.push(`Fuera del cilindro a los ${this.tIn.toFixed(1)} s: vuelve a entrar`);
        this.tIn = 0;
      }
    }
    // ---- 2. la caja: los 4 conos en orden, primero con el morro al sur y luego con el morro hacia cada cono ----
    if (d.conos) {
      const C = this.caja, K = d.conos.length;
      if (d.techo && av.despegado && h > d.techo) { m("bajo4", "mal"); this._aviso("techo", `Por encima de ${d.techo} m`, T); }
      if (C.fase === 1 && C.k > 0 && Math.abs(fpvDesenrollar(yaw - Math.PI)) > P.RUMBO_TOL * D2R) {
        C.k = 0; T.push("El morro ha dejado de mirar al sur: empieza otra vez por el cono {cono:0}");
      }
      let toca = -1;
      d.conos.forEach((q, i) => { if (Math.hypot(N - q[0], E - q[1]) <= P.CONO_R && h <= P.CONO_H) toca = i; });
      if (toca !== C.dentro && toca >= 0 && C.fase <= 2) {          // acaba de llegar a un cono
        if (toca !== C.k) T.push(`Ese no toca: ahora el cono {cono:${C.k}}`);
        else {
          let vale = true;
          if (C.fase === 2 && C.k > 0) {
            const a = d.conos[C.k - 1], b = d.conos[C.k], rumbo = Math.atan2(b[1] - a[1], b[0] - a[0]);
            vale = Math.abs(fpvDesenrollar(yaw - rumbo)) <= P.RUMBO_TOL * D2R;
          }
          if (!vale) T.push("Llega al cono con el morro hacia él: gira con la guiñada (palanca izquierda de lado)");
          else if (++C.k === K) {
            m(C.fase === 1 ? "caja1" : "caja2", "ok");
            T.push(C.fase === 1 ? "¡Caja hecha! Ahora otra vez, girando el morro hacia cada cono" : "¡Caja hecha girando el morro! Vuelve a la plataforma");
            C.fase++; C.k = 0;
          } else T.push(`Cono ${C.k}/${K}`);
        }
      }
      C.dentro = toca;
    }
    // ---- 3. slalom (hacia el sur, alternando el lado de cada poste) y ocho alrededor de los postes rojo y azul ----
    if (d.postes) {
      const S = this.slalom;
      d.postes.forEach((q, i) => {
        if (S.hecho || !(pAnt[0] > q[0] && N <= q[0]) || Math.abs(E - q[1]) >= 10 || h >= 6) return;
        const lado = E > q[1] ? 1 : -1;
        if (i === 0) { S.k = 1; S.lado = lado; S.empezado = true; T.push("Poste 1/5"); return; }
        if (i !== S.k) { if (S.k > 0) T.push(`Te has saltado el poste ${S.k + 1}: empieza otra vez por el primero`); S.k = 0; return; }
        if (lado === S.lado) { T.push(`Poste ${i + 1} por el mismo lado que el ${i}: empieza otra vez por el primero`); S.k = 0; return; }
        S.k++; S.lado = lado;
        if (S.k === d.postes.length) { S.hecho = true; m("slalom", "ok"); T.push("¡Slalom hecho! Ahora el ocho al fondo"); }
        else T.push(`Poste ${S.k}/${d.postes.length}`);
      });
    }
    if (d.ocho) {
      const O = this.ocho, ds = d.ocho.map(q => Math.hypot(N - q[0], E - q[1])), VUELTA = 0.9 * 2 * Math.PI;
      if (ds.every(x => x > 25)) { O.acc = [0, 0]; O.prev = [null, null]; O.vuelta = [false, false]; }
      d.ocho.forEach((q, i) => {
        if (ds[i] < 1 || ds[i] > 15) { O.prev[i] = null; return; }
        const a = Math.atan2(E - q[1], N - q[0]);
        if (O.prev[i] !== null) O.acc[i] += fpvDesenrollar(a - O.prev[i]);
        O.prev[i] = a;
        if (!O.vuelta[i] && Math.abs(O.acc[i]) >= VUELTA) {
          const j = 1 - i, nombre = ["rojo", "azul"][i];
          if (O.vuelta[j] && Math.sign(O.acc[j]) === Math.sign(O.acc[i])) { O.acc[i] = 0; O.prev[i] = null; T.push(`Vuelta al poste ${nombre} en el mismo sentido que al otro: en un ocho, cada uno en un sentido`); return; }
          O.vuelta[i] = true; T.push(`Vuelta al poste ${nombre}`);
          if (O.vuelta[j] && !O.hecho) { O.hecho = true; m("ocho", "ok"); T.push("¡Ocho hecho! Vuelve a la plataforma"); }
        }
      });
    }
    if (d.banda) {
      const activa = this.slalom.empezado && !this.ocho.hecho;
      this.tFuera = activa && (h < d.banda[0] || h > d.banda[1]) ? this.tFuera + dt : 0;
      if (this.tFuera > 1) { m("altura13", "mal"); this._aviso("banda", `Fuera de la franja de ${d.banda[0]} a ${d.banda[1]} m`, T); }
    }
    // ---- 4. circuito de puertas, en orden y de frente ----
    if (gs.length) {
      const C = this.circ;
      cruces.forEach((c, i) => {
        if (!c || c.tipo !== "pasa") return;
        if (c.dir < 0) { T.push(`Puerta ${i + 1} al revés: no cuenta`); return; }
        if (i !== C.k) { T.push(`Esa no toca: ahora la puerta ${C.k + 1}`); return; }
        if (i === 0) C.t0 = t;
        if (++C.k < gs.length) { T.push(`Puerta ${C.k}/${gs.length}`); return; }
        C.k = 0; C.n++; C.ultima = t - C.t0; C.mejor = C.mejor === null ? C.ultima : Math.min(C.mejor, C.ultima);
        if (C.n <= (d.vueltas || 1)) m("vuelta" + C.n, "ok");
        T.push(`¡Vuelta ${C.n}!  ${C.ultima.toFixed(1)} s`);
      });
    }
    // ---- 5. recta por la pista 2 entre 1,5 y 4 m ----
    if (this.recta && av.despegado) {
      const r = this.recta.actualizar(p);
      if (r) {
        if (r.ok) { m(r.sentido === "oeste" ? "rectaO" : "rectaE", "ok"); T.push(`¡Recta hacia el ${r.sentido}!  (${r.hmin.toFixed(1)}–${r.hmax.toFixed(1)} m)`); }
        else T.push("Recta no válida: " + r.motivo);
      }
    }
    // ---- 6. power loop y split-S por la puerta alta; picado desde la torre ----
    if (d.puerta_alta) {
      const A = this.alta, g = d.puerta_alta;
      A.hmax = Math.max(A.hmax, h);
      if (ca && ca.tipo === "pasa") {
        const u = A.ult;
        if (u && ca.dir === u.dir && t - u.t <= 6 && A.hmax >= g.h0 + g.alto + 1) { m("powerloop", "ok"); T.push("¡Power loop!"); }
        else if (u && ca.dir !== u.dir && t - u.t <= 5) { m("splits", "ok"); T.push("¡Split-S!"); }
        else T.push("Puerta alta");
        A.ult = { t, dir: ca.dir }; A.hmax = h;
      }
    }
    if (d.torre) {
      const q = d.torre;
      if (h >= q.alto && Math.hypot(N - q.n, E - q.e) <= 10) this.tAlto = t;
      if (this.tAlto !== null && h < 5) {
        if (t - this.tAlto <= 4) { m("picado", "ok"); this._aviso("picado", `¡Picado! ${(t - this.tAlto).toFixed(1)} s`, T); }
        this.tAlto = null;
      }
    }
    return T;
  }

  /** Al acabar el vuelo: aterrizaje en la plataforma y desarmado a tiempo. */
  final(final, av) {
    if (final !== "aterrizado") return;
    const s = this.d.salida;
    this.marcar("plataforma", Math.hypot(av.p[0] - s[0], av.p[1] - s[1]) <= 1.5 ? "ok" : "mal");
    this.marcar("desarmar", this.tPosado !== null && av.t - this.tPosado <= 3 ? "ok" : "mal");
  }

  /** Lo que toca ahora (texto del panel, con <b> y {cono:i}). obj: los objetivos del evaluador. */
  ahora(obj, av) {
    const d = this.d, hecho = k => obj[k] && obj[k].estado === "ok", volver = "vuelve a la plataforma, aterriza y desarma (L)";
    if (!av.despegado) return "Ahora: <b>arma con el gas abajo (L) y despega despacio</b>";
    if (d.cilindro && !hecho("estacionario"))
      return `Ahora: <b>quieto en el cilindro azul</b> · ${this.tIn.toFixed(1)} s de ${d.cilindro.t}`;
    if (d.conos && this.caja.fase <= 2)
      return `Ahora: cono <b>{cono:${this.caja.k}}</b> (${this.caja.k + 1}/${d.conos.length}) · ` + (this.caja.fase === 1 ? "<b>con el morro al sur</b>" : "<b>con el morro hacia él</b>");
    if (d.postes && !this.slalom.hecho) return `Ahora: <b>slalom</b>, poste ${this.slalom.k + 1} de ${d.postes.length} (alterna el lado)`;
    if (d.ocho && !this.ocho.hecho) return "Ahora: <b>ocho</b> alrededor del poste {cono:2} y el {cono:3} (cada uno en un sentido)";
    if (d.recta && !(hecho("rectaO") && hecho("rectaE"))) return `Ahora: <b>recta por la pista 2 hacia el ${hecho("rectaO") ? "este" : "oeste"}</b>, entre 1,5 y 4 m`;
    const C = this.circ, V = d.vueltas || 1;
    const tiempos = C.ultima !== null ? ` · última ${C.ultima.toFixed(1)} s · mejor ${C.mejor.toFixed(1)} s` : "";
    if (d.puertas && C.n < V) return `Ahora: vuelta ${C.n + 1} de ${V} · <b>puerta ${C.k + 1}</b> de ${d.puertas.length}` + tiempos;
    if (d.puerta_alta) {
      const falta = [["powerloop", "power loop"], ["splits", "split-S"], ["picado", "picado desde la torre"]].filter(([k]) => !hecho(k)).map(x => x[1]);
      if (falta.length) return "Ahora: <b>" + falta.join(" · ") + "</b>";
    }
    return "Ahora: <b>" + volver + "</b>" + tiempos;
  }
}
