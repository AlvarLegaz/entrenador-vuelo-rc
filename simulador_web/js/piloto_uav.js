// =====================================================================
//  PILOTO AUTOMATICO DE UN UAV DE ALA FIJA (Cernicalo XM-7 y Grajo MX-2, datos.uav y datos.piloto)
//  Como los de los UAV tacticos reales, por capas: el lazo interior lleva el alabeo y el cabeceo con los alerones y la
//  profundidad (y amortigua la guinada con los timones); encima, el rumbo, la altura y la velocidad (con el gas); y
//  encima de todo, la navegacion (ir a un punto y dar vueltas sobre el, volver a la base) y el despegue y el aterrizaje
//  en la pista. Devuelve las palancas (como las de la emisora: pitch +1 = tirar, yaw +1 = alerones a la derecha,
//  guinada +1 = timones a la derecha) y, si los lleva, el gas y el freno. Mismo codigo en
//  simulador_godot/scripts/piloto_uav.gd (simulador_godot/Tests/prueba_piloto_uav.gd compara los dos).
//  Modos: MANUAL (las palancas pasan tal cual), ESTAB (estabilizado: la palanca pide alabeo y cabeceo y al soltarla
//  nivela), CRUCERO (mantiene altura, rumbo y velocidad; las palancas cambian la altura y el rumbo pedidos y la del gas
//  la velocidad), PUNTO (va a un punto y da vueltas sobre el), BASE (vuelve sobre la pista o el despegue), DESPEGUE y
//  ATERRIZAJE (automaticos, en la pista). Sin pista (el Grajo, lanzado a mano): LANZAMIENTO (motor a tope, alas
//  niveladas y subida hasta h_fin_despegue; luego crucero) y ATERRIZAJE en perdida profunda en un punto (datos.piloto.toma):
//  contra el viento a un punto de entrada, alineado con el de toma bajando y, a la distancia justa, motor parado y
//  profundidad arriba del todo (av.profToma: el recorrido de prof_toma_grados): baja a ~45 grados hasta el suelo.
//  Angulos en radianes; posiciones NED (m) del simulador; altura = -p[2] (la del simulador, no sobre el mar).
// =====================================================================
const PUAV_MODOS = ["MANUAL", "ESTAB", "CRUCERO", "PUNTO", "BASE", "DESPEGUE", "ATERRIZAJE", "LANZAMIENTO"];
const PUAV_NOMBRE = { MANUAL: "Manual", ESTAB: "Estabilizado", CRUCERO: "Crucero", PUNTO: "Ir a punto", BASE: "Vuelta a base",
                      DESPEGUE: "Despegue automático", ATERRIZAJE: "Aterrizaje automático", LANZAMIENTO: "Lanzamiento" };

class PilotoUAV {
  /** P: datos.piloto del avion (velocidades y limites); pista: {n, e, rumbo (grados), largo, h (altura del suelo)} o null;
   *  casa: [N, E, h] del despegue (la base si no hay pista). */
  /** Los datos del piloto para el avion con masa k veces la de su ficha (el morro orientable del Grajo, otro peso en
   *  Ajustes): las velocidades escalan con la raiz de la masa (la misma sustentacion con el mismo angulo de ataque). */
  static paraMasa(P, k) {
    if (!(k > 0) || Math.abs(k - 1) < 1e-6) return P;
    const s = Math.sqrt(k), Q = Object.assign({}, P);
    for (const n of ["v_min", "v_alarma", "v_crucero", "v_aprox", "v_max"]) if (Q[n] !== undefined) Q[n] = Q[n] * s;
    return Q;
  }
  constructor(P, pista, casa) {
    this.P = P; this.pista = pista || null; this.casa = casa;
    this.modo = "MANUAL"; this.fase = ""; this.c = { alt: 0, rumbo: 0, vel: P.v_crucero, punto: null };
    this.iTh = 0; this.iV = 0; this.automatico = false;     // automatico: si se ha usado el despegue o el aterrizaje automatico
    this.Vf = null;                                           // con pitot, la velocidad del aire filtrada (1,5 s) para el gas: las rachas no lo mueven
    this.gasVisto = null;                                     // la palanca del gas: en crucero, al moverla cambia la velocidad pedida
    this.vientoDesde = 0;                                     // de donde viene el viento (rad): la toma sin pista se hace contra el
  }

  static envolver(a) { return a - 2 * Math.PI * Math.round(a / (2 * Math.PI)); }
  static lim(x, a, b) { return Math.max(a, Math.min(b, x)); }

  /** Cambia de modo con las consignas de lo que esta haciendo ahora (altura, rumbo y velocidad actuales). Devuelve el
   *  texto para el aviso o "" si no se puede (p. ej. el despegue automatico en el aire). */
  poner(modo, av, punto) {
    const P = this.P, e = Cuat.euler(av.q), V = P.pitot && av.V !== undefined ? av.V : Math.hypot(...av.v), h = -av.p[2], L = PilotoUAV.lim;
    if (modo === "DESPEGUE" && !(this.pista && av.enTierra)) return "";
    if (modo === "ATERRIZAJE" && ((!this.pista && !P.toma) || av.enTierra)) return "";
    if (modo === "LANZAMIENTO" && this.pista) return "";
    if (["CRUCERO", "PUNTO", "BASE", "ESTAB"].includes(modo) && av.enTierra) return "";
    this.modo = modo; this.fase = ""; this.iTh = 0; this.iV = 0; this.gasVisto = null;
    this.c.alt = h; this.c.rumbo = e[2]; this.c.vel = L(V, P.v_min, P.v_max);
    if (modo === "CRUCERO") this.c.vel = P.v_crucero;
    if (modo === "PUNTO") { this.c.punto = punto ? punto.slice() : [av.p[0], av.p[1]]; this.c.alt = Math.max(h, this.suelo0() + P.h_min); this.c.vel = Math.max(this.c.vel, P.v_crucero); }
    if (modo === "BASE") { const b = this.puntoBase(); this.c.punto = b; this.c.alt = this.suelo0() + P.h_base; this.c.vel = P.v_crucero; }
    if (modo === "DESPEGUE") { this.fase = "carrera"; this.automatico = true; }
    if (modo === "ATERRIZAJE") { this.fase = "llegada"; this.trasEntrada = false; this.automatico = true; this.c.vel = P.v_aprox; if (!this.pista) this.c.punto = punto ? punto.slice() : [this.casa[0], this.casa[1]]; }
    if (modo === "LANZAMIENTO") this.fase = "subida";       // el lanzamiento a mano es el despegue normal del Grajo: no cuenta como automatico
    av.profToma = false;
    return PUAV_NOMBRE[modo];
  }

  suelo0() { return this.pista ? this.pista.h : this.casa[2]; }
  puntoBase() { return this.pista ? this.centroPista() : [this.casa[0], this.casa[1]]; }
  /** Punto de la pista a d m del umbral (a lo largo del eje) y t m a su derecha. */
  enPista(d, t) { const p = this.pista, r = p.rumbo * D2R; return [p.n + d * Math.cos(r) - t * Math.sin(r), p.e + d * Math.sin(r) + t * Math.cos(r)]; }
  centroPista() { return this.enPista(this.pista.largo / 2, 0); }
  /** (d, t): distancia a lo largo del eje de la pista desde el umbral y desvio lateral (+ a la derecha). */
  ejePista(N, E) { const p = this.pista, r = p.rumbo * D2R, dn = N - p.n, de = E - p.e; return [dn * Math.cos(r) + de * Math.sin(r), -dn * Math.sin(r) + de * Math.cos(r)]; }

  /** Un paso. pal: palancas {pitch, yaw, guinada} y gasPalanca (0..1, la del gas: en crucero elige la velocidad).
   *  Devuelve {pitch, yaw, guinada, gas, freno}: gas y freno null si no los lleva (los manda el piloto). */
  paso(av, dt, pal, gasPalanca) {
    // con un sensor averiado (this.sens, js/desgaste.js: el Grajo) el piloto trabaja con lo que creen los sensores: el
    // GPS (la posicion se le va moviendo), la brujula (rumbo), la IMU (actitud) y el barometro (altura que se va)
    const S = this.sens;
    if (S && !this._conSens) {
      const e0 = Cuat.euler(av.q), dz = S.vz * av.t, ae = Object.assign({}, av, {
        p: [av.p[0] + (S.gps ? S.gps * Math.cos(2 * Math.PI * av.t / 25) : 0), av.p[1] + (S.gps ? S.gps * Math.sin(2 * Math.PI * av.t / 31) : 0), av.p[2] + dz],
        q: Cuat.desdeEuler(e0[0] + S.alabeo, e0[1] + S.cabeceo, e0[2] + S.rumbo) });
      if (av.agl !== undefined) ae.agl = av.agl - dz;
      this._conSens = true; const r = this.paso(ae, dt, pal, gasPalanca); this._conSens = false;
      av.profToma = ae.profToma; return r;
    }
    const P = this.P, L = PilotoUAV.lim, W = PilotoUAV.envolver, e = Cuat.euler(av.q), V = Math.max(1, P.pitot && av.V !== undefined ? av.V : Math.hypot(...av.v));   // con datos.piloto.pitot (el Grajo), la del aire
    const vn = Cuat.rot(av.q, av.v), vz = -vn[2], h = -av.p[2], m = this.modo;
    this.vzc = vz;                                       // la subida pedida (la pone altura(); si no, la que lleva)
    const out = { pitch: pal.pitch, yaw: pal.yaw, guinada: pal.guinada, gas: null, freno: null };
    if (m === "MANUAL") return out;
    // ---- lazo interior: alabeo y cabeceo pedidos -> alerones y profundidad; los timones quitan el derrape ----
    const actitud = (phi, th) => {
      out.yaw = L(P.k_alabeo * (phi - e[0]) - P.k_p * av.w[0], -1, 1);
      // sin alerones (el Grajo: datos.piloto.timon_alabeo): el timon hace alabear (con el poliedro) y amortigua la guinada a la vez
      if (P.timon_alabeo) out.yaw = L(P.k_alabeo * (phi - e[0]) - P.k_p * av.w[0] - P.k_r * (av.w[2] - G0 * Math.sin(e[0]) / V), -1, 1);
      // proteccion contra la perdida: con mucho angulo de ataque (o muy despacio) no deja tirar mas y baja el morro
      const sobra = av.alfa - P.alfa_max, lento = P.v_alarma - V;
      if (sobra > 0 || lento > 0) th = Math.min(th, e[1] - P.k_alfa * Math.max(sobra, 0) * D2R - 0.02 * Math.max(lento, 0));
      if (sobra <= 0 && lento <= 0) this.iTh = L(this.iTh + P.k_i_cabeceo * (th - e[1]) * dt, -0.5, 0.5);     // con la proteccion actuando, el integrador quieto
      out.pitch = L(P.k_cabeceo * (th - e[1]) - P.k_q * av.w[1] + this.iTh, -1, 1);
      out.guinada = L(-P.k_derrape * av.beta * D2R - P.k_r * (av.w[2] - G0 * Math.sin(e[0]) / V), -1, 1);
    };
    // ---- rumbo, altura y velocidad ----
    const fMax = L((V - P.v_alarma) / (P.v_crucero - P.v_alarma), 0.3, 1), aMax = P.alabeo_max * D2R * fMax;   // despacio, menos alabeo
    const rumbo = psi => L(P.k_rumbo * W(psi - e[2]), -aMax, aMax);
    const altura = (hc, vzMax) => {
      const vzc = L(P.k_altura * (hc - h), -vzMax, vzMax); this.vzc = vzc;
      return L(Math.atan2(vzc, V) + P.k_vz * (vzc - vz) + P.cabeceo_crucero * D2R, P.cabeceo_min * D2R, P.cabeceo_max * D2R);
    };
    if (P.pitot) this.Vf = this.Vf === null ? V : this.Vf + (V - this.Vf) * Math.min(1, dt / 1.5);
    const Vg = P.pitot ? this.Vf : V;                       // la del gas: con pitot, filtrada (una racha no lo pone a 0 o a 1)
    const velocidad = vc => { this.iV = L(this.iV + P.k_i_gas * (vc - Vg) * dt, -0.4, 0.4); return Vg < P.v_alarma ? 1 : L(P.gas_crucero + P.k_gas * (vc - Vg) + P.k_gas_vz * (this.vzc - vz) + this.iV, 0, 1); };   // y mas gas si tiene que subir
    if (m === "ESTAB") {                                // la palanca pide alabeo y cabeceo; suelta, nivela
      actitud(pal.yaw * P.alabeo_max * D2R, (pal.pitch * P.cabeceo_max + (1 - Math.abs(pal.pitch)) * P.cabeceo_crucero) * D2R);
      return out;
    }
    if (m === "CRUCERO") {                              // las palancas cambian lo pedido y el gas elige la velocidad
      this.c.rumbo = W(this.c.rumbo + pal.yaw * P.giro_consigna * D2R * dt);
      this.c.alt = Math.max(this.suelo0() + P.h_min * 0.5, this.c.alt + pal.pitch * P.subida_consigna * dt);
      if (this.gasVisto !== null && Math.abs(gasPalanca - this.gasVisto) > 1e-3) this.c.vel = P.v_min + L(gasPalanca, 0, 1) * (P.v_max - P.v_min);
      this.gasVisto = gasPalanca;
      actitud(rumbo(this.c.rumbo), altura(this.c.alt, P.vz_max)); out.gas = velocidad(this.c.vel);
      return out;
    }
    if (m === "PUNTO" || m === "BASE") {                // ir al punto y dar vueltas sobre el (en el sentido de las agujas del reloj)
      const [cN, cE] = this.c.punto, dn = av.p[0] - cN, de = av.p[1] - cE, d = Math.hypot(dn, de), a = Math.atan2(de, dn), R = P.radio_orbita;
      this.c.rumbo = d > 3 * R ? Math.atan2(-de, -dn) : W(a + Math.PI / 2 + Math.atan((d - R) / P.k_orbita));
      this.c.alt += pal.pitch * P.subida_consigna * dt;
      actitud(rumbo(this.c.rumbo), altura(this.c.alt, P.vz_max)); out.gas = velocidad(this.c.vel);
      return out;
    }
    if (m === "LANZAMIENTO") {                          // lanzado a mano: motor a tope, alas niveladas y a subir; arriba, crucero
      out.gas = 1; actitud(0, P.cabeceo_subida * D2R);
      const agl = av.agl === undefined ? h - this.suelo0() : av.agl;
      if (agl > P.h_fin_despegue) { const r = this.c.rumbo; this.poner("CRUCERO", av); this.c.alt = this.suelo0() + P.h_base; this.c.rumbo = r; this.c.vel = P.v_crucero; return this.paso(av, 0, { pitch: 0, yaw: 0, guinada: 0 }, gasPalanca); }
      return out;
    }
    if (m === "ATERRIZAJE" && !this.pista) return this.tomaPerdida(av, out, actitud, rumbo, altura, velocidad, e, V, vz, h);
    const ps = this.pista, rp = ps.rumbo * D2R, [dEje, tEje] = this.ejePista(av.p[0], av.p[1]), agl = av.agl === undefined ? h - ps.h : av.agl;
    if (m === "DESPEGUE") {
      out.freno = 0; out.gas = 1;
      if (this.fase === "carrera") {                    // en la pista: recto por el eje con la rueda de morro y los timones
        out.yaw = L(-P.k_alabeo * e[0] - P.k_p * av.w[0], -1, 1);
        out.guinada = L(P.k_rumbo_tierra * W(rp - e[2]) - P.k_eje * tEje - P.k_r_tierra * av.w[2], -1, 1);
        out.pitch = V > P.v_rotacion ? L(P.k_cabeceo * (P.cabeceo_rotacion * D2R - e[1]) - P.k_q * av.w[1], -1, 1) : 0;
        if (!av.enTierra && agl > 2) this.fase = "subida";
        return out;
      }
      actitud(rumbo(W(rp - Math.atan(tEje / 200))), P.cabeceo_subida * D2R);       // subida por el eje de la pista
      if (agl > P.h_fin_despegue) { this.poner("CRUCERO", av); this.c.alt = ps.h + P.h_base; this.c.rumbo = rp; this.c.vel = P.v_crucero; return this.paso(av, 0, { pitch: 0, yaw: 0, guinada: 0 }, gasPalanca); }
      return out;
    }
    // ---- ATERRIZAJE: a la entrada (en el eje, "final" + 1500 m antes del umbral), luego por el eje y la senda y la toma ----
    const dEntrada = P.final_m + 1500, hFinal = ps.h + P.final_m * Math.tan(P.senda_grados * D2R);
    if (this.fase === "llegada") {
      const [fN, fE] = this.enPista(-dEntrada, 0), d = Math.hypot(av.p[0] - fN, av.p[1] - fE);
      actitud(rumbo(Math.atan2(fE - av.p[1], fN - av.p[0])), altura(Math.max(hFinal, Math.min(h, ps.h + P.h_base)), P.vz_max)); out.gas = velocidad(P.v_crucero);
      if (d < 500 || (dEje < -P.final_m && Math.abs(tEje) < 300 && Math.abs(W(rp - e[2])) < 45 * D2R)) this.fase = "final";   // en la entrada (o ya en el eje y hacia la pista)
      return out;
    }
    if (this.fase === "final") {                         // por el eje y la senda de planeo hacia el umbral
      const hs = ps.h + Math.min(P.final_m, -dEje) * Math.tan(P.senda_grados * D2R) + P.h_umbral;     // la senda sigue tras el umbral: toca a ~h_umbral / tan(senda) de el
      actitud(rumbo(W(rp - Math.atan(tEje / P.k_eje_aire))), altura(hs, P.vz_max)); out.gas = velocidad(-dEje > P.final_m ? P.v_crucero : P.v_aprox);
      if (agl < P.h_recogida) this.fase = "recogida";
      return out;
    }
    if (this.fase === "recogida") {                      // cerca del suelo: gas fuera, alas niveladas, el morro con la pista (sin deriva) y
      const vzc = -(P.vz_toma + P.k_recogida * agl); this.vzc = vzc;     // bajando cada vez mas despacio (sin flotar con el efecto suelo)
      actitud(0, L(Math.atan2(vzc, V) + P.k_vz * (vzc - vz) + P.cabeceo_crucero * D2R, 0, P.cabeceo_recogida * D2R)); out.gas = 0;
      out.guinada = L(P.k_rumbo_tierra * W(rp - e[2]) - P.k_r_tierra * av.w[2], -1, 1);
      if (av.enTierra) this.fase = "rodadura";
      return out;
    }
    out.gas = 0; out.freno = V > 2 ? 0.7 : 1; out.pitch = -0.2;               // en la pista: frenar por el eje
    out.yaw = L(-P.k_alabeo * e[0] - P.k_p * av.w[0], -1, 1);
    out.guinada = L(P.k_rumbo_tierra * W(rp - e[2]) - P.k_eje * tEje - P.k_r_tierra * av.w[2], -1, 1);
    return out;
  }

  /** Toma en perdida profunda en el punto c.punto (sin pista: el Grajo). La senda final va contra el viento: entrada a
   *  d_final m a sotavento del punto, a h_entrada sobre el; por la final bajando hasta h_perdida; y donde, con lo que
   *  baja en perdida (~45 grados respecto al aire) y lo que lo empuja el viento, va a caer en el punto: motor parado,
   *  profundidad arriba del todo (av.profToma) y alas niveladas hasta el suelo. */
  tomaPerdida(av, out, actitud, rumbo, altura, velocidad, e, V, vz, h) {
    const P = this.P, T = P.toma, L = PilotoUAV.lim, W = PilotoUAV.envolver, [tN, tE] = this.c.punto, hT = this.casa[2];
    const rf = this.vientoDesde, cf = Math.cos(rf), sf = Math.sin(rf);            // rumbo de la final: hacia donde viene el viento
    const dn = av.p[0] - tN, de = av.p[1] - tE, a = -(dn * cf + de * sf), t = -dn * sf + de * cf;     // a: lo que falta hasta el punto por la final; t: desvio
    const agl = av.agl === undefined ? h - hT : av.agl;
    av.profToma = false;
    if (this.fase === "llegada") {                       // a la entrada, a sotavento, ya contra el viento (como un piloto): si aun no esta a
      // sotavento de ella, antes a un punto mas alejado (2 d_final), para girar a la altura de entrada y no en la final
      if (a > 1.1 * T.d_final) this.trasEntrada = true;
      else if (a < 0.6 * T.d_final) this.trasEntrada = false;          // ha pasado la entrada sin alinearse: otra vuelta
      const k = this.trasEntrada ? 1 : 2, eN = tN - k * T.d_final * cf, eE = tE - k * T.d_final * sf;
      actitud(rumbo(Math.atan2(eE - av.p[1], eN - av.p[0])), altura(Math.max(hT, h - agl) + T.h_entrada, P.vz_max)); out.gas = velocidad(P.v_crucero);   // sobre el suelo que tiene debajo
      if (this.trasEntrada && a > 0.6 * T.d_final && a < 1.3 * T.d_final && Math.abs(t) < 25 && Math.abs(W(rf - e[2])) < 30 * D2R) this.fase = "final";
      return out;
    }
    if (this.fase === "final") {                         // por la final, bajando hasta h_perdida, hasta el punto de entrar en perdida
      actitud(rumbo(W(rf - Math.atan(t / 30))), altura(Math.max(hT + T.h_perdida + Math.max(0, a - this.dPerdida(av, agl)) * (T.h_entrada - T.h_perdida) / T.d_final, h - agl + 0.8 * T.h_perdida), P.vz_max));
      out.gas = velocidad(P.v_aprox);
      if (a <= this.dPerdida(av, agl)) this.fase = "perdida";
      if (a < -40) { this.fase = "llegada"; this.trasEntrada = false; }    // se ha pasado: otra vuelta
      return out;
    }
    actitud(0, 0); out.gas = 0; out.pitch = T.prof; av.profToma = true;       // perdida profunda: alas niveladas con el timon
    return out;
  }
  /** Lo que avanza sobre el suelo desde que entra en perdida a agl m de altura: ~45 grados respecto al aire (lo que baja,
   *  lo avanza) menos el viento de cara, mas lo que tarda en frenar. */
  dPerdida(av, agl) { const w = Math.max(0, this.vientoVel || 0), vb = 6.0; return Math.max(0, agl * (vb - w) / vb) + 8; }
}
