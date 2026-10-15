// =====================================================================
//  PILOTO AUTOMATICO DE UN UAV DE ALA FIJA (Cernicalo XM-7, datos.uav y datos.piloto)
//  Como los de los UAV tacticos reales, por capas: el lazo interior lleva el alabeo y el cabeceo con los alerones y la
//  profundidad (y amortigua la guinada con los timones); encima, el rumbo, la altura y la velocidad (con el gas); y
//  encima de todo, la navegacion (ir a un punto y dar vueltas sobre el, volver a la base) y el despegue y el aterrizaje
//  en la pista. Devuelve las palancas (como las de la emisora: pitch +1 = tirar, yaw +1 = alerones a la derecha,
//  guinada +1 = timones a la derecha) y, si los lleva, el gas y el freno. Mismo codigo en
//  simulador_godot/scripts/piloto_uav.gd (pruebas/prueba_piloto_uav.gd compara los dos).
//  Modos: MANUAL (las palancas pasan tal cual), ESTAB (estabilizado: la palanca pide alabeo y cabeceo y al soltarla
//  nivela), CRUCERO (mantiene altura, rumbo y velocidad; las palancas cambian la altura y el rumbo pedidos y la del gas
//  la velocidad), PUNTO (va a un punto y da vueltas sobre el), BASE (vuelve sobre la pista o el despegue), DESPEGUE y
//  ATERRIZAJE (automaticos, en la pista).
//  Angulos en radianes; posiciones NED (m) del simulador; altura = -p[2] (la del simulador, no sobre el mar).
// =====================================================================
const PUAV_MODOS = ["MANUAL", "ESTAB", "CRUCERO", "PUNTO", "BASE", "DESPEGUE", "ATERRIZAJE"];
const PUAV_NOMBRE = { MANUAL: "Manual", ESTAB: "Estabilizado", CRUCERO: "Crucero", PUNTO: "Ir a punto", BASE: "Vuelta a base",
                      DESPEGUE: "Despegue automático", ATERRIZAJE: "Aterrizaje automático" };

class PilotoUAV {
  /** P: datos.piloto del avion (velocidades y limites); pista: {n, e, rumbo (grados), largo, h (altura del suelo)} o null;
   *  casa: [N, E, h] del despegue (la base si no hay pista). */
  constructor(P, pista, casa) {
    this.P = P; this.pista = pista || null; this.casa = casa;
    this.modo = "MANUAL"; this.fase = ""; this.c = { alt: 0, rumbo: 0, vel: P.v_crucero, punto: null };
    this.iTh = 0; this.iV = 0; this.automatico = false;     // automatico: si se ha usado el despegue o el aterrizaje automatico
    this.gasVisto = null;                                     // la palanca del gas: en crucero, al moverla cambia la velocidad pedida
  }

  static envolver(a) { return a - 2 * Math.PI * Math.round(a / (2 * Math.PI)); }
  static lim(x, a, b) { return Math.max(a, Math.min(b, x)); }

  /** Cambia de modo con las consignas de lo que esta haciendo ahora (altura, rumbo y velocidad actuales). Devuelve el
   *  texto para el aviso o "" si no se puede (p. ej. el despegue automatico en el aire). */
  poner(modo, av, punto) {
    const e = Cuat.euler(av.q), V = Math.hypot(...av.v), h = -av.p[2], P = this.P, L = PilotoUAV.lim;
    if (modo === "DESPEGUE" && !(this.pista && av.enTierra)) return "";
    if (modo === "ATERRIZAJE" && (!this.pista || av.enTierra)) return "";
    if (["CRUCERO", "PUNTO", "BASE", "ESTAB"].includes(modo) && av.enTierra) return "";
    this.modo = modo; this.fase = ""; this.iTh = 0; this.iV = 0; this.gasVisto = null;
    this.c.alt = h; this.c.rumbo = e[2]; this.c.vel = L(V, P.v_min, P.v_max);
    if (modo === "CRUCERO") this.c.vel = P.v_crucero;
    if (modo === "PUNTO") { this.c.punto = punto ? punto.slice() : [av.p[0], av.p[1]]; this.c.alt = Math.max(h, this.suelo0() + P.h_min); this.c.vel = Math.max(this.c.vel, P.v_crucero); }
    if (modo === "BASE") { const b = this.puntoBase(); this.c.punto = b; this.c.alt = this.suelo0() + P.h_base; this.c.vel = P.v_crucero; }
    if (modo === "DESPEGUE") { this.fase = "carrera"; this.automatico = true; }
    if (modo === "ATERRIZAJE") { this.fase = "llegada"; this.automatico = true; this.c.vel = P.v_aprox; }
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
    const P = this.P, L = PilotoUAV.lim, W = PilotoUAV.envolver, e = Cuat.euler(av.q), V = Math.max(1, Math.hypot(...av.v));
    const vn = Cuat.rot(av.q, av.v), vz = -vn[2], h = -av.p[2], m = this.modo;
    this.vzc = vz;                                       // la subida pedida (la pone altura(); si no, la que lleva)
    const out = { pitch: pal.pitch, yaw: pal.yaw, guinada: pal.guinada, gas: null, freno: null };
    if (m === "MANUAL") return out;
    // ---- lazo interior: alabeo y cabeceo pedidos -> alerones y profundidad; los timones quitan el derrape ----
    const actitud = (phi, th) => {
      out.yaw = L(P.k_alabeo * (phi - e[0]) - P.k_p * av.w[0], -1, 1);
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
    const velocidad = vc => { this.iV = L(this.iV + P.k_i_gas * (vc - V) * dt, -0.4, 0.4); return V < P.v_alarma ? 1 : L(P.gas_crucero + P.k_gas * (vc - V) + P.k_gas_vz * (this.vzc - vz) + this.iV, 0, 1); };   // y mas gas si tiene que subir
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
    if (this.fase === "recogida") {                      // cerca del suelo: gas fuera, morro arriba, alas niveladas y el morro con la pista (sin deriva)
      actitud(0, P.cabeceo_recogida * D2R); out.gas = 0;
      out.guinada = L(P.k_rumbo_tierra * W(rp - e[2]) - P.k_r_tierra * av.w[2], -1, 1);
      if (av.enTierra) this.fase = "rodadura";
      return out;
    }
    out.gas = 0; out.freno = V > 2 ? 0.7 : 1; out.pitch = -0.2;               // en la pista: frenar por el eje
    out.yaw = L(-P.k_alabeo * e[0] - P.k_p * av.w[0], -1, 1);
    out.guinada = L(P.k_rumbo_tierra * W(rp - e[2]) - P.k_eje * tEje - P.k_r_tierra * av.w[2], -1, 1);
    return out;
  }
}
