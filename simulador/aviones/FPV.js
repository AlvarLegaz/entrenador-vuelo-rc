// Dron FPV de 5 pulgadas como los de las escuelas de FPV (unos 650 g con una 4S de 1500 mAh, motores 2306 de 2450 KV,
// helices de 5" de 3 palas, bastidor X de 220 mm): se vuela con gafas, mirando la camara de a bordo.
// A diferencia del DJI, NO hay GPS ni retencion de posicion ni de altura: manda un controlador de vuelo tipo Betaflight.
//  - Modos de Betaflight: ANGLE (la palanca derecha pide una INCLINACION, hasta 55 grados, y al soltarla se nivela solo),
//    HORIZON (cerca del centro como ANGLE y a fondo como ACRO: puede dar vueltas) y ACRO (la palanca pide VELOCIDAD DE
//    GIRO con las tasas de Betaflight: RC rate, super rate y expo; si se suelta, se queda con la inclinacion que tenga).
//    La guinada (palanca izquierda de lado) siempre pide velocidad de giro.
//  - El gas va directo a los motores (palanca izquierda SIN muelle): no mantiene la altura, la mantiene el piloto.
//  - Controlador de velocidades de giro (PI) -> mezclador de cuadricoptero en X con "airmode" (aun con el gas a cero
//    conserva el mando) -> 4 motores con su respuesta (no cambian de vueltas al instante), empuje con la entrada de aire
//    (sube menos de lo que empuja en estatico), par de reaccion y de aceleracion de los rotores (asi gira en guinada),
//    efecto suelo, resistencia del cuerpo y de los rotores con el viento, "propwash" (bajando por su propia estela se
//    sacude y empuja menos) y bateria 4S que cae de tension con la corriente (sag) y al gastarse.
//  - Armado como un FPV de verdad: se arma (L o boton A) con el gas abajo del todo; armado y con el gas a cero los
//    motores giran al ralenti. Desarmado en el aire, cae. Al posarse suave queda en el suelo; desarmado en el suelo, el
//    vuelo acaba "aterrizado". Si toca el suelo rapido o inclinado, lo decide el simulador (roto).
// Ejes y estado como ModeloAvion y ModeloCuadricoptero (cuerpo x adelante, y derecha, z abajo; mundo NED). Mandos:
// mando.yaw = alabeo (palanca derecha de lado), mando.pitch = cabeceo (+ = hacia ti = morro arriba), mando.guinada =
// guinada; el gas es av.gases (0-1), que pone el simulador como en los aviones (teclado W/S, emisora o mando).
// simulador_godot/scripts/modelo_fpv.gd es su traduccion LITERAL (pruebas/prueba_fpv.gd la compara con trazas de esta).
window.ModeloFPV = window.ModeloFPV || class ModeloFPV {
  constructor(datos) {
    Object.assign(this, datos);
    this.esCuadricoptero = true; this.esFPV = true;
    this.modo = "ANGLE";                                      // modo de vuelo de Betaflight: "ANGLE", "HORIZON" o "ACRO"
    this.masa_diseno_kg = datos.masa_kg; this.inercia = Object.assign({}, datos.inercia); this.inercia_diseno = Object.assign({}, datos.inercia);
    this.dcg = 0; this.rho = RHO; this.calib = { empuje: 1, resistencia: 1 }; this.facil = false;
    this.mandos = Object.assign({}, datos.mandos);
  }
  /** Masa, temperatura (densidad), empuje estatico medido (gf, el de los 4 motores) y factor de resistencia. */
  configurar({ masa_kg, temperatura, empuje_gf, resistencia }) {
    if (temperatura !== undefined) this.rho = 101325 / (287.05 * (temperatura + 273.15));
    if (empuje_gf) this.calib.empuje = empuje_gf / 1000 * G0 / (4 * this.propulsion.empuje_motor_N);
    if (resistencia) this.calib.resistencia = resistencia;
    if (masa_kg) { this.masa_kg = masa_kg; const k = masa_kg / this.masa_diseno_kg; for (const n in this.inercia_diseno) this.inercia[n] = this.inercia_diseno[n] * k; }
  }
  /** Tension en vacio de la bateria (V) con la carga gastada (mAh). */
  _voc(mAh) {
    const pr = this.propulsion, soc = Math.max(0, 1 - mAh / pr.capacidad_mAh);
    return pr.celdas * interp(pr.curva_soc, pr.curva_v, soc);
  }
  /** En el suelo y desarmado ("en mano" para el simulador: L lo arma). */
  estadoInicial() {
    return { p: [0, 0, -0.02], q: Cuat.desdeEuler(0, 0, 0), v: [0, 0, 0], w: [0, 0, 0], de: 0, dr: 0, da: 0, gases: 0, Wh: 0, asim: 0,
             estado: "en mano", t: 0, alfa: 0, beta: 0, V: 0, g_carga: 1, perdida: 0, T: 0, rpm: 0, motorRoto: false,
             posado: true, despegado: false, armado: false, tArmado: 0, cmd: { alabeo: 0, cabeceo: 0, guinada: 0 }, integ: [0, 0, 0],
             motores: [0, 0, 0, 0], mAh: 0, Vbat: this._voc(0), I: 0, P: 0, propwash: 0 };
  }
  /** Armar (el simulador comprueba antes que el gas este abajo): motores al ralenti en el suelo. */
  lanzar(av) {
    av.v = [0, 0, 0]; av.w = [0, 0, 0]; av.estado = "volando"; av.armado = true; av.integ = [0, 0, 0];
    av.posado = true; av.despegado = false; av.q = Cuat.desdeEuler(0, 0, Cuat.euler(av.q)[2]);
  }
  /** Desarmar: los motores se paran. En el suelo antes de despegar vuelve a "en mano" (se puede armar otra vez). */
  desarmar(av) {
    av.armado = false;
    if (av.posado && !av.despegado) av.estado = "en mano";
  }
  /** Para los escenarios que empiezan en el aire: armado, en vuelo y con el gas que lo sostiene. */
  armarEnVuelo(av) {
    av.armado = true; av.posado = false; av.despegado = true; av.integ = [0, 0, 0];
    const F = this.fc, kV = this._voc(av.mAh) / this.propulsion.V_ref, Tm = this.propulsion.empuje_motor_N * this.calib.empuje * kV * kV;
    const u = Math.sqrt(this.masa_kg * G0 / 4 / Tm);
    av.gases = Math.max(0, Math.min(1, (u - F.ralenti) / (1 - F.ralenti))); av.motores = [u * kV, u * kV, u * kV, u * kV];
  }
  /** Palancas -> consignas (con la exponencial del simulador: con mando la pone el mando y expo vale 0), con el suavizado
   *  de la emisora (rc smoothing). mando: yaw = alabeo, pitch = cabeceo (+ = palanca hacia ti), guinada. */
  servos(av, mando, dt) {
    const e = this.mandos.expo || 0, ex = s => (1 - e) * s + e * s * s * s, cl = x => Math.max(-1, Math.min(1, x || 0));
    const obj = { alabeo: ex(cl(mando.yaw)), cabeceo: ex(cl(-mando.pitch)), guinada: ex(cl(mando.guinada)) };
    const k = Math.min(1, dt / this.fc.rc_suavizado_s);
    for (const n in obj) av.cmd[n] += (obj[n] - av.cmd[n]) * k;
  }
  mandosCoef() { return { CL: 0, CY: 0, Cl: 0, Cm: 0, Cn: 0 }; }
  /** Tasa de Betaflight (grados/s) de una palanca s (-1..1): RC rate, super rate y expo (formula "Betaflight" de 4.x). */
  tasa(s, R) {
    const a = Math.abs(s), x = s * a * a * a * R.expo + s * (1 - R.expo);
    let rc = R.rc; if (rc > 2) rc += 14.54 * (rc - 2);
    let t = 200 * rc * x;
    if (R.super) t *= 1 / Math.max(0.01, Math.min(1, 1 - a * R.super));
    return Math.max(-1998, Math.min(1998, t));
  }
  /** Curva de gas de Betaflight (thr_mid, thr_expo): con expo 0 es lineal. */
  curvaGas(g) {
    const F = this.fc, d = g - F.gas_medio, y = d > 0 ? 1 - F.gas_medio : d < 0 ? F.gas_medio : 1;
    return F.gas_medio + d * (1 - F.gas_expo + F.gas_expo * d * d / (y * y));
  }
  /** Un paso: bateria -> controlador (tasas, PI, mezclador con airmode) -> motores -> empuje y pares -> 6 grados de libertad. */
  paso(av, viento, dt) {
    const m = this.masa_kg, I = this.inercia, F = this.fc, pr = this.propulsion, q = av.q, v = av.v, w = av.w, rho = this.rho, FAC = this.facil;
    const suelo = av.agl === undefined ? 0 : -av.p[2] - av.agl, agl = av.agl === undefined ? 100 : av.agl;
    const [roll, pitch, yaw] = Cuat.euler(q);
    // --- bateria: tension en vacio segun lo gastado y caida por la resistencia interna con la potencia del paso anterior ---
    const Voc = this._voc(av.mAh), disc = Voc * Voc - 4 * pr.R_ohm * av.P;
    const V = disc > 0 ? 0.5 * (Voc + Math.sqrt(disc)) : 0.5 * Voc;
    av.Vbat = V;
    const kV = V / pr.V_ref, Tref = pr.empuje_motor_N * this.calib.empuje, TmaxV = Tref * kV * kV, idle = F.ralenti;
    // --- controlador de vuelo: consignas de velocidad de giro segun el modo ---
    const c = av.cmd, T3 = F.tasas, lim = F.angulo_max_grados * D2R, kn = F.k_nivel;
    const acroP = this.tasa(c.alabeo, T3.alabeo) * D2R, acroQ = -this.tasa(c.cabeceo, T3.cabeceo) * D2R, rSet = this.tasa(c.guinada, T3.guinada) * D2R;
    const nivP = kn * (c.alabeo * lim - roll), nivQ = kn * (-c.cabeceo * lim - pitch);
    let pSet, qSet;
    if (this.modo === "ACRO") { pSet = acroP; qSet = acroQ; }
    else if (this.modo === "HORIZON") {
      const lv = Math.max(0, 1 - Math.max(Math.abs(c.alabeo), Math.abs(c.cabeceo)) / F.horizon_transicion);
      pSet = lv * nivP + (1 - lv) * acroP; qSet = lv * nivQ + (1 - lv) * acroQ;
    } else { pSet = nivP; qSet = nivQ; }
    // PI de velocidades de giro (en el suelo, apagado y sin integral: no se pone a corregir contra el suelo)
    const armado = av.armado && !av.motorRoto;
    let L = 0, Mm = 0, N = 0;
    if (armado && !av.posado) {
      const e = [pSet - w[0], qSet - w[1], rSet - w[2]];
      for (let i = 0; i < 3; i++) av.integ[i] = Math.max(-F.i_max, Math.min(F.i_max, av.integ[i] + e[i] * dt));
      L = I.Ixx * (F.kp[0] * e[0] + F.ki[0] * av.integ[0]);
      Mm = I.Iyy * (F.kp[1] * e[1] + F.ki[1] * av.integ[1]);
      N = Math.max(-F.tau_guinada, Math.min(F.tau_guinada, I.Izz * (F.kp[2] * e[2] + F.ki[2] * av.integ[2])));
    } else av.integ = [0, 0, 0];
    // mezclador en X: empuje de cada motor = colectivo (gas) + diferencias para los pares; con airmode, si no cabe entre
    // el ralenti y el maximo, se reducen las diferencias y se desplaza el colectivo (se pierde gas, no mando)
    const uc = idle + (1 - idle) * this.curvaGas(Math.max(0, Math.min(1, av.gases || 0)));
    let Tc = TmaxV * uc * uc;
    const a = F.brazo_m, kq = pr.k_par_m, Mot = F.motores, dT = [0, 0, 0, 0];
    for (let i = 0; i < 4; i++) {
      const [x, y, s] = Mot[i];
      dT[i] = -(y > 0 ? 1 : -1) * L / (4 * a) + (x > 0 ? 1 : -1) * Mm / (4 * a) - s * N / (4 * kq);
    }
    let dmin = Math.min(dT[0], dT[1], dT[2], dT[3]), dmax = Math.max(dT[0], dT[1], dT[2], dT[3]);
    const Tmin = TmaxV * idle * idle, rango = TmaxV - Tmin;
    if (dmax - dmin > rango) { const k = rango / (dmax - dmin); for (let i = 0; i < 4; i++) dT[i] *= k; dmin *= k; dmax *= k; }
    if (Tc + dmax > TmaxV) Tc = TmaxV - dmax;
    if (Tc + dmin < Tmin) Tc = Tmin - dmin;
    // --- motores: orden (0-1, con la tension de ahora) -> vueltas con su retardo; empuje con la entrada de aire, el efecto
    // suelo y el propwash; par de reaccion y de aceleracion de cada rotor ---
    const wb = Cuat.rot(Cuat.inv(q), FAC ? [0.5 * viento[0], 0.5 * viento[1], 0.5 * viento[2]] : viento);
    const va = [v[0] - wb[0], v[1] - wb[1], v[2] - wb[2]], Va = Math.sqrt(va[0] * va[0] + va[1] * va[1] + va[2] * va[2]);
    const D = pr.D_m, A = Math.PI * D * D / 4, Wmax = pr.rpm_max * 2 * Math.PI / 60, km = Math.min(1, dt / F.tau_motor_s);
    const zs = Math.max(agl, 0.06), kGE = FAC ? 1 : 1 / (1 - Math.pow(D / 2 / (4 * zs), 2));
    // propwash: bajando (aire que sube por el disco) a una velocidad parecida a la de su estela, con poca velocidad
    // horizontal, el aire revuelto sacude el dron y empuja menos. La estela, la del empuje que lleva
    let T0 = 0;
    for (let i = 0; i < 4; i++) T0 += Tref * av.motores[i] * av.motores[i];
    const vh = Math.sqrt(Math.max(T0, 0.05) / (2 * rho * 4 * A)), vd = va[2], vlat2 = va[0] * va[0] + va[1] * va[1];
    const ipw = FAC || !armado ? 0 : Math.exp(-Math.pow((vd - 0.8 * vh) / (0.5 * vh), 2)) * Math.exp(-vlat2 / 16);
    av.propwash = ipw;
    let Tt = 0, Lr = 0, Mr = 0, Nr = 0, P = pr.P_electronica_W;
    for (let i = 0; i < 4; i++) {
      const [x, y, s] = Mot[i];
      const u = armado ? Math.max(idle, Math.min(1, Math.sqrt(Math.max(0, (Tc + dT[i]) / TmaxV)))) : 0;
      const f0 = av.motores[i], f = f0 + (u * kV - f0) * km;
      av.motores[i] = f;
      const n = f * pr.rpm_max / 60, kJ = FAC ? 1 : Math.max(0, Math.min(1.15, 1 - -va[2] / (pr.J0 * Math.max(n, 1) * D)));
      const T = Tref * f * f * kJ * kGE * (1 - F.propwash_perdida * ipw);
      Tt += T;
      Lr += -y * T; Mr += x * T; Nr += -s * (kq * T + pr.I_rotor * (f - f0) * Wmax / dt);
      P += kq * T * f * Wmax / pr.rendimiento;
    }
    // sacudidas del propwash (deterministas: dos senos de 7 y 13 Hz) y turbulencia que alabea (Entorno.rafagaAlabeo)
    const t = av.t;
    Lr += ipw * F.propwash_par * (0.6 * Math.sin(2 * Math.PI * 7.3 * t) + 0.4 * Math.sin(2 * Math.PI * 12.9 * t + 1.3));
    Mr += ipw * F.propwash_par * (0.6 * Math.sin(2 * Math.PI * 8.1 * t + 0.7) + 0.4 * Math.sin(2 * Math.PI * 11.7 * t + 2.1));
    if (av.pg && !FAC) Lr += I.Ixx * av.pg * 4;
    // --- bateria: potencia de los motores (par x vueltas / rendimiento) y de la electronica; corriente con la tension ---
    av.P = P; av.I = P / V; av.mAh += av.I * dt / 3.6; av.Wh += P * dt / 3600;
    av.T = Tt; av.rpm = 0.25 * (av.motores[0] + av.motores[1] + av.motores[2] + av.motores[3]) * pr.rpm_max;
    av.alfa = 0; av.beta = 0; av.perdida = 0; av.g_carga = Tt / (m * G0);
    if (armado) av.tArmado += dt;
    // --- en el suelo: quieto hasta que el empuje supera el peso; desarmado despues de volar, aterrizado ---
    if (av.posado) {
      if (Tt <= m * G0 * 1.02 || !armado) {
        av.v = [0, 0, 0]; av.w = [0, 0, 0]; av.q = Cuat.desdeEuler(0, 0, yaw); av.p[2] = -(suelo + 0.02); av.V = 0; av.t += dt;
        if (!av.armado && av.despegado) av.p[2] = -(suelo - 0.05);        // desarmado tras volar: el simulador lo da por aterrizado
        return [0, 0, 0];
      }
      av.posado = false;    // despega
    }
    // --- fuerzas en ejes cuerpo: empuje, peso, resistencia del cuerpo (cuadratica) y de los rotores (lineal con el empuje) ---
    const kd = 0.5 * rho * Va * this.calib.resistencia;
    const Fx = -kd * F.cda_h * va[0] - F.k_rotor * Tt * va[0], Fy = -kd * F.cda_h * va[1] - F.k_rotor * Tt * va[1], Fz0 = -kd * F.cda_v * va[2];
    const gb = Cuat.rot(Cuat.inv(q), [0, 0, G0]);
    const Fb = [Fx + m * gb[0], Fy + m * gb[1], Fz0 + m * gb[2] - Tt];
    // --- ecuaciones de Euler (sin producto de inercia) e integracion ---
    const dv = [Fb[0] / m - (w[1] * v[2] - w[2] * v[1]), Fb[1] / m - (w[2] * v[0] - w[0] * v[2]), Fb[2] / m - (w[0] * v[1] - w[1] * v[0])];
    const Iw = [I.Ixx * w[0], I.Iyy * w[1], I.Izz * w[2]];
    const dw = [(Lr - (w[1] * Iw[2] - w[2] * Iw[1])) / I.Ixx, (Mr - (w[2] * Iw[0] - w[0] * Iw[2])) / I.Iyy, (Nr - (w[0] * Iw[1] - w[1] * Iw[0])) / I.Izz];
    for (let i = 0; i < 3; i++) { v[i] += dv[i] * dt; w[i] += dw[i] * dt; }
    const dq = Cuat.mul(q, [0, w[0], w[1], w[2]]);
    av.q = Cuat.norm([q[0] + 0.5 * dq[0] * dt, q[1] + 0.5 * dq[1] * dt, q[2] + 0.5 * dq[2] * dt, q[3] + 0.5 * dq[3] * dt]);
    const vn2 = Cuat.rot(av.q, v);
    for (let i = 0; i < 3; i++) av.p[i] += vn2[i] * dt;
    av.t += dt; av.V = Va;
    // --- suelo: toma suave (poco descenso, poca velocidad, casi nivelado y sin mucho gas) -> posado; si no, la
    // decide el simulador (Entorno.contactoSuelo: aterrizado o roto) ---
    const agl2 = -av.p[2] - suelo;
    if (agl2 > 0.3) av.despegado = true;
    if (agl2 <= 0.02 && vn2[2] >= 0 && vn2[2] < F.toma_vz && vn2[0] * vn2[0] + vn2[1] * vn2[1] < F.toma_vh * F.toma_vh &&
        Math.abs(roll) < 25 * D2R && Math.abs(pitch) < 25 * D2R && Tt < 1.3 * m * G0) {
      av.posado = true; av.v = [0, 0, 0]; av.w = [0, 0, 0]; av.q = Cuat.desdeEuler(0, 0, Cuat.euler(av.q)[2]); av.p[2] = -(suelo + 0.02);
    }
    return vn2;
  }
  bateriaPct(av) { return Math.max(0, 100 * (1 - av.mAh / this.propulsion.capacidad_mAh)); }
  /** Tension por celda (V) con la carga de ahora. */
  celda(av) { return av.Vbat / this.propulsion.celdas; }
};

// ---- modelo 3D del dron FPV: un 5" tipo iFlight Nazgul / XING hecho con geometria procedural (sin ficheros de malla).
// Bastidor en X de carbono (brazos de 5,5 mm con chaflanes, placas inferior, intermedia y superior con agujeros y
// ranuras), separadores de aluminio y tornillos, ESC, controlador y VTX con sus componentes y soportes de goma, cables de
// los motores por los brazos, condensador y cable XT60, camara de 19 mm inclinada 28 grados en su soporte de TPU con el
// objetivo de aro cromado, antena del VTX en un mastil de TPU hacia atras, motores 2306 (base, bobinado de cobre a la
// vista, campana ranurada con el rotulo, eje y tuerca), patas de TPU verde lima, bateria 4S con su funda, cable, conector
// de balance, correa de velcro con hebilla, tiras de LED y helices tripala de policarbonato gris translucido (perfil,
// cuerda, torsion por el paso y flecha) que giran con las vueltas de cada motor y se funden en un disco translucido.
// Todo lo describe datos.modelo3d (piezas: placas extruidas con chaflan, piezas de revolucion, secciones a lo largo de
// una linea, tubos y cajas redondeadas, con sus copias), y simulador_godot/scripts/modelo_fpv_3d.gd construye EXACTAMENTE
// la misma malla con el mismo algoritmo; los detalles finos (tejido de carbono, ranuras de la campana, rotulos, capas de
// la impresion 3D, componentes de las placas, etiqueta de la bateria) los pinta el mismo codigo de sombreado
// (modelo3d.sombreador) en los dos simuladores. Ejes cuerpo (x adelante, y derecha, z abajo; metros, origen en el CG; el
// suelo en z = +0,02).
(function () {
  const TAU = 2 * Math.PI, RAD = Math.PI / 180, DMAX = 0.0015;
  const sub = (a, b) => [a[0] - b[0], a[1] - b[1], a[2] - b[2]], add = (a, b) => [a[0] + b[0], a[1] + b[1], a[2] + b[2]];
  const mul = (a, k) => [a[0] * k, a[1] * k, a[2] * k], dot = (a, b) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
  const cross = (a, b) => [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]];
  const len = a => Math.sqrt(dot(a, a)), norm = a => { const l = len(a); return l > 0 ? mul(a, 1 / l) : [0, 0, 0]; };
  const clamp = (x, a, b) => Math.max(a, Math.min(b, x));
  const smooth = (a, b, x) => { const t = clamp((x - a) / (b - a), 0, 1); return t * t * (3 - 2 * t); };
  const iguales = (a, b) => Math.abs(a[0] - b[0]) < 1e-7 && Math.abs(a[1] - b[1]) < 1e-7 && Math.abs(a[2] - b[2]) < 1e-7;

  /** Malla en construccion: posiciones, normales, "det" (4 valores por vertice para el sombreado: coordenadas de la
   *  pieza y el numero de material) y triangulos (sin orientar: se orientan con la normal al copiarlos). */
  class Acum {
    constructor() { this.pos = []; this.nor = []; this.det = []; this.idx = []; }
    get n() { return this.pos.length / 3; }
    vert(p, nn, d) { this.pos.push(p[0], p[1], p[2]); this.nor.push(nn[0], nn[1], nn[2]); this.det.push(d[0], d[1], d[2], d[3]); return this.n - 1; }
    p(i) { return [this.pos[3 * i], this.pos[3 * i + 1], this.pos[3 * i + 2]]; }
    nr(i) { return [this.nor[3 * i], this.nor[3 * i + 1], this.nor[3 * i + 2]]; }
  }

  /** Copia S en D girada rz grados sobre z, con y multiplicada por sy y desplazada (dx, dy, dz); cada triangulo con su
   *  cara delantera hacia la normal de sus vertices (en Three, sentido antihorario). Los degenerados se quitan. */
  function anadir(D, S, c) {
    const rz = (c[3] || 0) * RAD, sy = c[4] === undefined ? 1 : c[4], co = Math.cos(rz), si = Math.sin(rz), base = D.n;
    for (let i = 0; i < S.n; i++) {
      const x = S.pos[3 * i], y = S.pos[3 * i + 1] * sy, z = S.pos[3 * i + 2], nx = S.nor[3 * i], ny = S.nor[3 * i + 1] * sy;
      D.vert([co * x - si * y + c[0], si * x + co * y + c[1], z + c[2]], [co * nx - si * ny, si * nx + co * ny, S.nor[3 * i + 2]], S.det.slice(4 * i, 4 * i + 4));
    }
    for (let k = 0; k < S.idx.length; k += 3) {
      const a = base + S.idx[k], b = base + S.idx[k + 1], e = base + S.idx[k + 2];
      const pa = D.p(a), fn = cross(sub(D.p(b), pa), sub(D.p(e), pa));
      if (dot(fn, fn) < 1e-28) continue;
      if (dot(fn, add(add(D.nr(a), D.nr(b)), D.nr(e))) < 0) D.idx.push(a, e, b); else D.idx.push(a, b, e);
    }
  }

  /** Rejilla de filas (anillos con el primer punto repetido al final, todas del mismo numero de puntos). Normales por
   *  diferencias centrales (dos filas iguales seguidas = arista viva), hacia fuera del centro de cada anillo (signo -1:
   *  hacia dentro); en los polos (fila de un solo punto), la media de las de la fila vecina. */
  function rejilla(A, P, Dt, signo = 1) {
    const nf = P.length, K = P[0].length, base = A.n;
    const ig = (X, Y) => iguales(X[0], Y[0]) && iguales(X[K >> 1], Y[K >> 1]) && iguales(X[K >> 2], Y[K >> 2]);
    const prev = j => j > 0 ? j - 1 : K - 2, next = j => j < K - 1 ? j + 1 : 1;
    const N = [];
    let suma = 0;
    for (let i = 0; i < nf; i++) {
      const ip = i > 0 && !ig(P[i - 1], P[i]) ? i - 1 : i, inx = i < nf - 1 && !ig(P[i], P[i + 1]) ? i + 1 : i;
      const F = P[i], Fp = P[ip], Fn = P[inx], fila = [];
      let cen = [0, 0, 0];
      for (let j = 0; j < K - 1; j++) cen = add(cen, F[j]);
      cen = mul(cen, 1 / (K - 1));
      for (let j = 0; j < K; j++) {
        const v = cross(sub(F[next(j)], F[prev(j)]), sub(Fn[j], Fp[j]));
        fila.push(v); suma += dot(norm(v), sub(F[j], cen));
      }
      N.push(fila);
    }
    const s = (suma < 0 ? -1 : 1) * signo;
    for (let i = 0; i < nf; i++) N[i] = N[i].map(v => dot(v, v) > 1e-36 ? norm(mul(v, s)) : null);
    for (let i = 0; i < nf; i++) {          // polos
      if (N[i][0] !== null) continue;
      const vec = i > 0 ? N[i - 1] : N[i + 1];
      let m = [0, 0, 0];
      for (const v of vec) if (v) m = add(m, v);
      N[i] = N[i].map(() => norm(m));
    }
    for (let i = 0; i < nf; i++) for (let j = 0; j < K; j++) A.vert(P[i][j], N[i][j] || [0, 0, 1], Dt[i][j]);
    for (let i = 0; i < nf - 1; i++) {
      if (ig(P[i], P[i + 1])) continue;
      for (let j = 0; j < K - 1; j++) {
        const a = base + i * K + j, b = base + (i + 1) * K + j, c = b + 1, d = a + 1;
        A.idx.push(a, b, c, a, c, d);
      }
    }
  }

  /** Pieza de revolucion alrededor de eje desde o: perfil [[radio, altura], ...] (un punto repetido = arista viva).
   *  det = (fraccion de vuelta, radio, altura, material). */
  function torno(A, o, eje, perfil, nc, m, dentro) {
    eje = norm(eje);
    const ref = Math.abs(eje[0]) < 0.9 ? [1, 0, 0] : [0, 1, 0], u = norm(cross(eje, ref)), v = cross(eje, u);
    const P = [], D = [];
    for (const [r, h] of perfil) {
      const fila = [], det = [];
      for (let j = 0; j <= nc; j++) {
        const a = TAU * (j % nc) / nc;
        fila.push(add(add(o, mul(eje, h)), mul(add(mul(u, Math.cos(a)), mul(v, Math.sin(a))), r))); det.push([j / nc, r, h, m]);
      }
      P.push(fila); D.push(det);
    }
    rejilla(A, P, D, dentro ? -1 : 1);
  }

  /** Seccion superelíptica (exponente n) en el plano (l, u) alrededor de o: semiancho w, hacia arriba hu, hacia abajo hd. */
  function seccion(o, l, u, w, hu, hd, n, nc) {
    const f = [], e = 2 / n;
    for (let j = 0; j < nc; j++) {
      const a = TAU * j / nc, c = Math.cos(a), s = Math.sin(a);
      f.push(add(add(o, mul(l, Math.sign(c) * Math.pow(Math.abs(c), e) * w)), mul(u, Math.sign(s) * Math.pow(Math.abs(s), e) * (s > 0 ? hu : hd))));
    }
    f.push(f[0]);
    return f;
  }

  /** Pieza alargada: estaciones [x, y, z, semiancho, alto hacia arriba, alto hacia abajo] a lo largo de una linea,
   *  secciones superelipticas de exponente n y tapas redondeadas (longitudes t0 y t1, exponentes m0 y m1; 0 = abierta),
   *  o cerrada sobre si misma. det = (fraccion de vuelta, posicion a lo largo, 0, material). */
  function loft(A, est, n, t0, t1, arriba, nc, m0, m1, nt, m, cerrado) {
    const k = est.length, filas = [], T = [];
    for (let i = 0; i < k; i++) {
      const a = cerrado ? est[(i - 1 + k) % k] : est[Math.max(i - 1, 0)], b = cerrado ? est[(i + 1) % k] : est[Math.min(i + 1, k - 1)];
      T.push(norm(sub(b, a)));
    }
    const marco = t => { const l = norm(cross(arriba, t)); return [l, cross(t, l)]; };
    const sec = (E, fr, esc, d) => seccion(add(E.slice(0, 3), d), fr[0], fr[1], E[3] * esc, E[4] * esc, E[5] * esc, n, nc);
    if (t0 > 0 && !cerrado) {
      const fr = marco(T[0]);
      for (let q = nt; q > 0; q--) {
        const th = Math.PI / 2 * q / nt, esc = q === nt ? 0 : Math.pow(Math.max(Math.cos(th), 0), 2 / m0);
        filas.push(sec(est[0], fr, esc, mul(T[0], -t0 * Math.pow(Math.sin(th), 2 / m0))));
      }
    }
    for (let i = 0; i < k; i++) filas.push(sec(est[i], marco(T[i]), 1, [0, 0, 0]));
    if (cerrado) filas.push(filas[0]);
    if (t1 > 0 && !cerrado) {
      const fr = marco(T[k - 1]);
      for (let q = 1; q <= nt; q++) {
        const th = Math.PI / 2 * q / nt, esc = q === nt ? 0 : Math.pow(Math.max(Math.cos(th), 0), 2 / m1);
        filas.push(sec(est[k - 1], fr, esc, mul(T[k - 1], t1 * Math.pow(Math.sin(th), 2 / m1))));
      }
    }
    const D = filas.map((f, i) => f.map((q, j) => [j / nc, i / (filas.length - 1), 0, m]));
    rejilla(A, filas, D, 1);
  }

  /** Redondea los vertices de una linea (puntos [x, y, z, radio]) con arcos de ese radio tangentes a sus dos aristas
   *  (como mucho hasta la mitad de cada arista), en pasos de 12 grados como mucho. */
  function redondear(pts, cerrado) {
    const n = pts.length, out = [];
    for (let i = 0; i < n; i++) {
      const P = pts[i].slice(0, 3), r = pts[i][3] || 0;
      if (r <= 0 || (!cerrado && (i === 0 || i === n - 1))) { out.push(P); continue; }
      const A = pts[(i - 1 + n) % n].slice(0, 3), B = pts[(i + 1) % n].slice(0, 3);
      const d1 = norm(sub(A, P)), d2 = norm(sub(B, P)), th = Math.acos(clamp(dot(d1, d2), -1, 1));
      if (th > Math.PI - 1e-3 || th < 1e-3) { out.push(P); continue; }
      const phi = th / 2;
      let t = r / Math.tan(phi), rr = r;
      const tmax = 0.5 * Math.min(len(sub(A, P)), len(sub(B, P)));
      if (t > tmax) { t = tmax; rr = t * Math.tan(phi); }
      const T1 = add(P, mul(d1, t)), T2 = add(P, mul(d2, t)), C = add(P, mul(norm(add(d1, d2)), rr / Math.sin(phi)));
      const u1 = norm(sub(T1, C)), u2 = norm(sub(T2, C)), ang = Math.acos(clamp(dot(u1, u2), -1, 1));
      const k = Math.max(1, Math.ceil(ang / (12 * RAD)));
      for (let j = 0; j <= k; j++) {
        const s = j / k, w1 = Math.sin((1 - s) * ang) / Math.sin(ang), w2 = Math.sin(s * ang) / Math.sin(ang);
        out.push(add(C, mul(add(mul(u1, w1), mul(u2, w2)), rr)));
      }
    }
    // fuera los puntos casi repetidos (donde se tocan dos arcos)
    return out.filter((q, i) => i === 0 || len(sub(q, out[i - 1])) > 2e-5);
  }

  /** Parte los tramos mas largos que dmax en tramos iguales. */
  function densificar(pts, cerrado, dmax) {
    const n = pts.length, out = [];
    for (let i = 0; i < n; i++) {
      out.push(pts[i]);
      if (!cerrado && i === n - 1) break;
      const a = pts[i], b = pts[(i + 1) % n], k = Math.ceil(len(sub(b, a)) / dmax);
      for (let j = 1; j < k; j++) out.push(add(a, mul(sub(b, a), j / k)));
    }
    return out;
  }

  /** Quita los puntos de un lazo alineados con sus vecinos (los de densificar): las caras se triangulan sin ellos. */
  function simplificar(L) {
    const n = L.length, out = [];
    for (let i = 0; i < n; i++) {
      const a = out.length ? out[out.length - 1] : L[n - 1], b = L[i], c = L[(i + 1) % n];
      if (Math.abs((b[0] - a[0]) * (c[1] - b[1]) - (b[1] - a[1]) * (c[0] - b[0])) >= 1e-10) out.push(b);
    }
    return out;
  }
  const area2 = L => { let s = 0; for (let i = 0; i < L.length; i++) { const a = L[i], b = L[(i + 1) % L.length]; s += a[0] * b[1] - b[0] * a[1]; } return s; };
  function circulo(h) {
    const n = Math.max(12, Math.ceil(TAU * h[2] / 0.0007)), L = [];
    for (let j = 0; j < n; j++) L.push([h[0] + h[2] * Math.cos(TAU * j / n), h[1] + h[2] * Math.sin(TAU * j / n), 0]);
    return L;
  }
  function ranura(h) {              // [x1, y1, x2, y2, r]: dos semicirculos unidos
    const a = [h[0], h[1], 0], b = [h[2], h[3], 0], r = h[4], d = norm(sub(b, a)), ang = Math.atan2(d[1], d[0]);
    const n = Math.max(6, Math.ceil(Math.PI * r / 0.0007)), L = [];
    for (let j = 0; j <= n; j++) { const t = ang - Math.PI / 2 + Math.PI * j / n; L.push([b[0] + r * Math.cos(t), b[1] + r * Math.sin(t), 0]); }
    for (let j = 0; j <= n; j++) { const t = ang + Math.PI / 2 + Math.PI * j / n; L.push([a[0] + r * Math.cos(t), a[1] + r * Math.sin(t), 0]); }
    return densificar(L, true, DMAX);
  }

  /** Placa extruida: contorno [[a, b, radio de redondeo]] en el plano ejes ("xy": a = x, b = y; "xz": a = x, b = z),
   *  agujeros (circulos [a, b, r] y ranuras [a1, b1, a2, b2, r]), desde s0 con espesor e a lo largo del eje que falta y
   *  todos los cantos con un chaflan ch. det = (a, b, fraccion del espesor, material). */
  function placa(A, P, m) {
    const E = P.e, ch = P.ch, s0 = P.s0, xz = P.ejes === "xz";
    const pt = (a, b, s) => xz ? [a, s0 + s, b] : [a, b, s0 + s], eje = xz ? [0, 1, 0] : [0, 0, 1];
    let ext = densificar(redondear(P.contorno.map(q => [q[0], q[1], 0, q[2] || 0]), true), true, DMAX);
    if (area2(ext) < 0) ext.reverse();
    const lazos = [ext];
    for (const h of P.agujeros || []) { const L = h.length === 3 ? circulo(h) : ranura(h); if (area2(L) > 0) L.reverse(); lazos.push(L); }
    const caras = [];
    lazos.forEach((L, li) => {
      const K = L.length, N = L.map((q, j) => { const a = L[(j - 1 + K) % K], b = L[(j + 1) % K], t = norm([b[0] - a[0], b[1] - a[1], 0]); return [t[1], -t[0]]; });
      const fila = (s, dentro) => { const r = []; for (let j = 0; j <= K; j++) { const q = L[j % K], k = dentro ? ch : 0; r.push(pt(q[0] - k * N[j % K][0], q[1] - k * N[j % K][1], s)); } return r; };
      const det = s => { const r = []; for (let j = 0; j <= K; j++) r.push([L[j % K][0], L[j % K][1], s / E, m]); return r; };
      rejilla(A, [fila(0, true), fila(ch, false), fila(ch, false), fila(E - ch, false), fila(E - ch, false), fila(E, true)],
        [det(0), det(ch), det(ch), det(E - ch), det(E - ch), det(E)], li === 0 ? 1 : -1);
      caras.push(simplificar(L.map((q, j) => [q[0] - ch * N[j][0], q[1] - ch * N[j][1]])));
    });
    const tri = THREE.ShapeUtils.triangulateShape(caras[0].map(q => new THREE.Vector2(q[0], q[1])), caras.slice(1).map(L => L.map(q => new THREE.Vector2(q[0], q[1]))));
    const pts = [].concat(...caras);
    for (const [s, sg] of [[0, -1], [E, 1]]) {
      const base = A.n;
      for (const q of pts) A.vert(pt(q[0], q[1], s), mul(eje, sg), [q[0], q[1], s / E, m]);
      for (const t of tri) A.idx.push(base + t[0], base + t[1], base + t[2]);
    }
  }

  /** Tubo (cables, mastil, correa): linea [[x, y, z, radio de redondeo]] con seccion circular de radio r o
   *  superelíptica sec = [semiancho, arriba, abajo, exponente]; abierto con las puntas redondeadas o cerrado. */
  function tubo(A, P, m) {
    const c = P.cerrado, L = redondear(P.c, !!c), s = P.sec || [P.r, P.r, P.r, 2];
    const est = L.map(q => [q[0], q[1], q[2], s[0], s[1], s[2]]);
    loft(A, est, s[3], c ? 0 : s[0], c ? 0 : s[0], P.arriba || [0, 1, 0], P.nc || (s[0] < 0.001 ? 8 : 12), 2, 2, 3, m, !!c);
  }

  /** Cajas redondeadas [cx, cy, cz, lx, ly, lz] alineadas con los ejes. */
  function cajas(A, P, m) {
    for (const [cx, cy, cz, lx, ly, lz] of P.l) {
      const rr = 0.2 * Math.min(lx, ly, lz);
      loft(A, [[cx - lx / 2 + rr, cy, cz, ly / 2, lz / 2, lz / 2], [cx + lx / 2 - rr, cy, cz, ly / 2, lz / 2, lz / 2]], 6, rr, rr, [0, 0, -1], 16, 3.5, 3.5, 3, m, false);
    }
  }

  /** Cuerda de la pala (m) en xi = 0 (raiz) ... 1 (punta): la tabla de la helice, interpolada. */
  function cuerda(H, xi) {
    const t = H.cuerda;
    for (let i = 1; i < t.length; i++) if (xi < t[i][0]) return t[i - 1][1] + (t[i][1] - t[i - 1][1]) * (xi - t[i - 1][0]) / (t[i][0] - t[i - 1][0]);
    return t[t.length - 1][1];
  }
  const naca = u => 5 * (0.2969 * Math.sqrt(u) - 0.126 * u - 0.3516 * u * u + 0.2843 * u * u * u - 0.1036 * u * u * u * u);

  /** Una pala en ejes del rotor (z abajo) a lo largo de +x girada giro sobre z: cuerda, torsion (paso geometrico, como
   *  mucho beta_max), espesor, curvatura del perfil, flecha hacia atras y algo de conicidad; s = sentido de giro (+1
   *  horario visto desde arriba: el borde de ataque mira a +y). */
  function pala(A, H, s, giro) {
    const nfil = H.filas, M = H.puntos, co = Math.cos(giro), si = Math.sin(giro), rot = q => [co * q[0] - si * q[1], si * q[0] + co * q[1], q[2]];
    const filas = [], dets = [], K = 2 * M - 1;
    const anillo = (centro, d, nn, c, esp, xi) => {
      const f = [], dt = [];
      for (let j = 0; j < M; j++) { const u = (1 - Math.cos(Math.PI * j / (M - 1))) / 2; f.push(rot(add(add(centro, mul(d, (0.35 - u) * c)), mul(nn, c * (H.curvatura * 4 * u * (1 - u) + esp * naca(u)))))); }
      for (let j = M - 2; j > 0; j--) { const u = (1 - Math.cos(Math.PI * j / (M - 1))) / 2; f.push(rot(add(add(centro, mul(d, (0.35 - u) * c)), mul(nn, c * (H.curvatura * 4 * u * (1 - u) - esp * naca(u)))))); }
      f.push(f[0]);
      for (let j = 0; j < K; j++) dt.push([xi, j / (K - 1), 0, 0]);
      filas.push(f); dets.push(dt);
    };
    const polo = (q, xi) => { const p = rot(q), f = [], dt = []; for (let j = 0; j < K; j++) { f.push(p); dt.push([xi, j / (K - 1), 0, 0]); } filas.push(f); dets.push(dt); };
    polo([H.r0 - 0.0004, 0, 0], 0);
    for (let k = 0; k <= nfil; k++) {
      const xi = 1 - Math.pow(1 - k / nfil, 1.5), r = H.r0 + (H.R - H.r0) * xi, c = cuerda(H, xi);
      const beta = Math.min(Math.atan(H.paso / (TAU * r)), H.beta_max * RAD), esp = H.espesor[0] + (H.espesor[1] - H.espesor[0]) * xi;
      const d = [0, s * Math.cos(beta), -Math.sin(beta)], nn = [0, -s * Math.sin(beta), -Math.cos(beta)];
      anillo([r, -s * H.flecha * xi * xi, -H.conicidad * xi], d, nn, c, esp, xi);
    }
    polo([H.R + 0.0006, -s * H.flecha, -H.conicidad], 1);
    rejilla(A, filas, dets, 1);
  }

  /** Disco de desenfoque de un rotor: corona plana del buje a la punta. */
  function disco(A, H) {
    const n = 72, r0 = H.buje[2][0];
    for (let j = 0; j < n; j++) {
      const a = TAU * j / n, c = Math.cos(a), s = Math.sin(a);
      A.vert([c * r0, s * r0, 0], [0, 0, -1], [0, 0, 0, 0]); A.vert([c * H.R, s * H.R, 0], [0, 0, -1], [0, 0, 0, 0]);
    }
    for (let j = 0; j < n; j++) { const a = 2 * j, b = a + 1, c = 2 * ((j + 1) % n), d = c + 1; A.idx.push(a, c, b, b, c, d); }
  }

  /** Mallas del modelo (se calculan una vez): fija (todas las piezas, una sola malla con el numero de material en det),
   *  palas+buje por sentido de giro y disco. Las usa construir3D y la prueba de que Godot hace lo mismo. */
  function mallas(K) {
    if (mallas.cache && mallas.cache.K === K) return mallas.cache;
    const ids = {}; K.materiales.forEach((mt, i) => { ids[mt[0]] = i; });
    const fija = new Acum();
    for (const P of K.piezas) {
      const L = new Acum(), m = ids[P.m];
      if (P.t === "placa") placa(L, P, m);
      else if (P.t === "torno") torno(L, P.o, P.eje, P.p, P.n || 24, m, !!P.dentro);
      else if (P.t === "loft") loft(L, P.e, P.n, P.t0 || 0, P.t1 || 0, P.arriba || [0, 0, -1], P.nc || 32, P.m0 || 2, P.m1 || 2, P.nt || 6, m, false);
      else if (P.t === "tubo") tubo(L, P, m);
      else if (P.t === "cajas") cajas(L, P, m);
      const cs = typeof P.copias === "string" ? K.copias[P.copias] : [[0, 0, 0, 0]];
      for (const c of cs) anadir(fija, L, c);
    }
    const H = K.helice, palas = {};
    for (const s of [1, -1]) {
      const L = new Acum();
      for (let k = 0; k < H.palas; k++) pala(L, H, s, k * TAU / H.palas);
      torno(L, [0, 0, 0], [0, 0, -1], H.buje, 32, 1, false);
      palas[s] = new Acum(); anadir(palas[s], L, [0, 0, 0, 0]);
    }
    const dl = new Acum(); disco(dl, H); const dsc = new Acum(); anadir(dsc, dl, [0, 0, 0, 0]);
    return (mallas.cache = { K, fija, palas, disco: dsc });
  }

  /** Resumen de una malla para comparar con Godot: vertices, triangulos, area y suma de posiciones. */
  function resumen(A) {
    let area = 0, sx = 0, sy = 0, sz = 0;
    for (let k = 0; k < A.idx.length; k += 3) { const a = A.p(A.idx[k]); area += 0.5 * len(cross(sub(A.p(A.idx[k + 1]), a), sub(A.p(A.idx[k + 2]), a))); }
    for (let i = 0; i < A.n; i++) { sx += A.pos[3 * i]; sy += A.pos[3 * i + 1]; sz += A.pos[3 * i + 2]; }
    return { vertices: A.n, triangulos: A.idx.length / 3, area, suma: sx + 2 * sy + 3 * sz };
  }

  /** Codigo de sombreado comun (el mismo texto en Godot): materiales, cuerda de la pala y modelo3d.sombreador. */
  function codigo(K) {
    const f = x => x.toFixed(6), H = K.helice, c = H.cuerda;
    let s = "#define PALAS " + f(H.palas) + "\n";
    K.materiales.forEach((mt, i) => { s += "#define M_" + mt[0].toUpperCase() + " " + f(i) + "\n"; });
    for (const [nom, fn] of [["a", mt => [((mt[1] >> 16) & 255) / 255, ((mt[1] >> 8) & 255) / 255, (mt[1] & 255) / 255, mt[2]]], ["b", mt => [mt[3], mt[4], mt[5], 0]]]) {
      s += "vec4 fpv_tabla_" + nom + "(float m) {\n";
      K.materiales.forEach((mt, i) => { s += "\tif (m < " + f(i + 0.5) + ") return vec4(" + fn(mt).map(f).join(", ") + ");\n"; });
      s += "\treturn vec4(0.0);\n}\n";
    }
    s += "float fpv_cuerda(float x) {\n";
    for (let i = 1; i < c.length; i++) s += "\tif (x < " + f(c[i][0]) + ") return mix(" + f(c[i - 1][1]) + ", " + f(c[i][1]) + ", (x - " + f(c[i - 1][0]) + ") / " + f(c[i][0] - c[i - 1][0]) + ");\n";
    s += "\treturn " + f(c[c.length - 1][1]) + ";\n}\n";
    return s + K.sombreador.join("\n") + "\n";
  }

  /** Reflejos para los metales y el barniz (en el navegador no hay mapa de entorno en la escena): cielo, horizonte claro,
   *  suelo y una ventana de luz, en un panorama de 256 x 128. */
  function entorno() {
    if (entorno.tex) return entorno.tex;
    const cv = document.createElement("canvas"); cv.width = 256; cv.height = 128;
    const g = cv.getContext("2d"), gr = g.createLinearGradient(0, 0, 0, 128);
    gr.addColorStop(0, "#9fb9d6"); gr.addColorStop(0.47, "#eef2f6"); gr.addColorStop(0.53, "#8a8076"); gr.addColorStop(1, "#4a423b");
    g.fillStyle = gr; g.fillRect(0, 0, 256, 128);
    g.fillStyle = "#ffffff"; g.fillRect(40, 18, 46, 20); g.fillRect(170, 26, 20, 14);
    const t = new THREE.CanvasTexture(cv); t.mapping = THREE.EquirectangularReflectionMapping; t.colorSpace = THREE.SRGBColorSpace;
    return (entorno.tex = t);
  }

  const VERT_DECL = "#include <common>\nattribute vec4 det;\nvarying vec4 vDet;\nvarying vec3 vPl;\nvarying vec3 vNl;";
  const VERT_MAIN = "#include <begin_vertex>\nvDet = det; vPl = position; vNl = normal;";
  /** Material de las piezas fijas: PBR de Three con el color, la rugosidad, el metal y el barniz de su material
   *  (modelo3d.materiales) y los detalles del codigo comun; el mapa de entorno solo da reflejos (la luz difusa la dan las
   *  luces de la escena). */
  function materialFijo(K) {
    const m = new THREE.MeshPhysicalMaterial({ color: 0xffffff, roughness: 0.5, metalness: 0, clearcoat: 1, clearcoatRoughness: 0.2, envMap: entorno(), envMapIntensity: 1 });
    const glsl = codigo(K);
    m.onBeforeCompile = sh => {
      sh.vertexShader = sh.vertexShader.replace("#include <common>", VERT_DECL).replace("#include <begin_vertex>", VERT_MAIN);
      sh.fragmentShader = sh.fragmentShader.replace("#include <common>", "#include <common>\nvarying vec4 vDet;\nvarying vec3 vPl;\nvarying vec3 vNl;\n" + glsl)
        .replace("#include <color_fragment>", "#include <color_fragment>\n" +
          "float fM = floor(vDet.w + 0.5); vec4 fA = fpv_tabla_a(fM); vec4 fB = fpv_tabla_b(fM);\n" +
          "vec3 fAlb = fpv_lineal(fA.rgb); float fRug = fA.a; float fMet = fB.x; float fCc = fB.y; float fAo = 1.0; float fHueco = 0.0; vec3 fPert = vec3(0.0);\n" +
          "fpv_detalle(fM, vDet, vPl, normalize(vNl), fAlb, fRug, fMet, fCc, fAo, fHueco, fPert);\n" +
          "if (fHueco > 0.5) discard;\ndiffuseColor.rgb = fAlb;")
        .replace("#include <roughnessmap_fragment>", "#include <roughnessmap_fragment>\nroughnessFactor = clamp(fRug, 0.0, 1.0);")
        .replace("#include <metalnessmap_fragment>", "#include <metalnessmap_fragment>\nmetalnessFactor = fMet;")
        .replace("#include <normal_fragment_maps>", "#include <normal_fragment_maps>\nif (fPert.z > 0.5) normal = fpv_perturbar(normal, -vViewPosition, vDet.xy, fPert.xy);")
        .replace("#include <lights_physical_fragment>", "#include <lights_physical_fragment>\nmaterial.clearcoat = fCc; material.clearcoatRoughness = clamp(fB.z + geometryRoughness, 0.0525, 1.0);")
        .replace("#include <lights_fragment_maps>", "#include <lights_fragment_maps>\niblIrradiance *= 0.0;")
        .replace("#include <aomap_fragment>", "#include <aomap_fragment>\nreflectedLight.indirectDiffuse *= fAo;");
    };
    m.customProgramCacheKey = () => "fpv3d_fijo";
    return m;
  }

  /** Disco de desenfoque: opacidad = fraccion de la circunferencia que tapan las palas a cada radio (fpv_disco). */
  function materialDisco(K) {
    const H = K.helice, m = new THREE.MeshStandardMaterial({ color: H.disco_col, roughness: 0.45, transparent: true, depthWrite: false, side: THREE.DoubleSide, envMap: entorno() });
    m.userData.u = { uFase: { value: 0 }, uInt: { value: 0 } };
    const glsl = codigo(K);
    m.onBeforeCompile = sh => {
      Object.assign(sh.uniforms, m.userData.u);
      sh.vertexShader = sh.vertexShader.replace("#include <common>", VERT_DECL).replace("#include <begin_vertex>", VERT_MAIN);
      sh.fragmentShader = sh.fragmentShader.replace("#include <common>", "#include <common>\nvarying vec4 vDet;\nvarying vec3 vPl;\nvarying vec3 vNl;\nuniform float uFase;\nuniform float uInt;\n" + glsl)
        .replace("#include <color_fragment>", "#include <color_fragment>\ndiffuseColor.a *= uInt * fpv_disco(vPl.xy, uFase, " + H.buje[2][0].toFixed(6) + ", " + H.R.toFixed(6) + ");");
    };
    m.customProgramCacheKey = () => "fpv3d_disco";
    return m;
  }

  function geometria(A) {
    const g = new THREE.BufferGeometry();
    g.setAttribute("position", new THREE.Float32BufferAttribute(A.pos, 3)); g.setAttribute("normal", new THREE.Float32BufferAttribute(A.nor, 3));
    g.setAttribute("det", new THREE.Float32BufferAttribute(A.det, 4)); g.setIndex(A.idx); g.computeBoundingSphere();
    return g;
  }

  window.ModeloFPV.mallas3D = datos => { const C = mallas(datos.modelo3d); return { fija: resumen(C.fija), palas: resumen(C.palas[1]), palas_inv: resumen(C.palas[-1]), disco: resumen(C.disco) }; };
  window.ModeloFPV.codigo3D = datos => codigo(datos.modelo3d);

  window.ModeloFPV.construir3D = window.ModeloFPV.construir3D || function (datos) {
    const K = datos.modelo3d, H = K.helice, C = mallas(K), grupo = new THREE.Group();
    if (!mallas.geo) mallas.geo = { fija: geometria(C.fija), palas: { 1: geometria(C.palas[1]), "-1": geometria(C.palas[-1]) }, disco: geometria(C.disco) };
    const G = mallas.geo, mFija = materialFijo(K);
    const fija = new THREE.Mesh(G.fija, mFija); fija.castShadow = true; fija.receiveShadow = true; grupo.add(fija);
    const rotores = K.rotores.map(([x, y, z, s]) => {
      const r = new THREE.Group(); r.position.set(x, y, z); grupo.add(r);
      const mp = new THREE.MeshPhysicalMaterial({ color: H.col, roughness: H.rug, transparent: true, opacity: H.opacidad, side: THREE.DoubleSide, depthWrite: false,
                                                  clearcoat: 0.5, clearcoatRoughness: 0.1, envMap: entorno() });
      const palas = new THREE.Mesh(G.palas[s], mp); palas.castShadow = true; r.add(palas);
      const md = materialDisco(K), dsc = new THREE.Mesh(G.disco, md); dsc.visible = false; dsc.renderOrder = 1; r.add(dsc);
      return { r, palas, mp, dsc, md, s, rpm: 0, fase: Math.random() * TAU };
    });
    // luces (tiras de LED bajo los brazos): punto de tamano fijo en pantalla, como las del DJI (construirAvion)
    if (!construirAvion.texLuz) {
      const cv = document.createElement("canvas"); cv.width = cv.height = 32; const g = cv.getContext("2d");
      const gr = g.createRadialGradient(16, 16, 2, 16, 16, 16); gr.addColorStop(0, "rgba(255,255,255,1)"); gr.addColorStop(0.45, "rgba(255,255,255,0.95)"); gr.addColorStop(1, "rgba(255,255,255,0)");
      g.fillStyle = gr; g.fillRect(0, 0, 32, 32); construirAvion.texLuz = new THREE.CanvasTexture(cv);
    }
    const luces = K.luces.map(l => {
      const g = new THREE.Group(); g.position.set(...l.p);
      const sp = new THREE.Sprite(new THREE.SpriteMaterial({ color: l.color, map: construirAvion.texLuz, sizeAttenuation: false, transparent: true, depthWrite: false }));
      sp.scale.set(0.01, 0.01, 1); g.add(sp);
      g.add(new THREE.Mesh(new THREE.SphereGeometry(0.0022, 8, 6), new THREE.MeshBasicMaterial({ color: l.color }))); grupo.add(g); return g;
    });
    const rpmMax = datos.propulsion.rpm_max;
    let oculto = false, t = 0;
    /** Cada cuadro: helices (vueltas de cada motor, con la inercia que se ve al arrancar y al pararse: palas nitidas
     *  paradas o despacio y disco de desenfoque deprisa), luces (fijas armado, parpadean desarmado) y, con la camara FPV,
     *  el dron solo como sombra (la camara va dentro del bastidor). */
    function animar(av, dt, visor) {
      t += dt;
      const ms = av.motores || [0, 0, 0, 0], camFPV = !!(visor && visor.camara === 3);
      if (visor && mFija.envMapIntensity !== 2) mFija.envMapIntensity = 2;           // la escena de vuelo va con exposicion 0,5
      if (camFPV !== oculto) { oculto = camFPV; mFija.colorWrite = !oculto; mFija.depthWrite = !oculto; }
      rotores.forEach((R, i) => {
        const obj = av.estado === "en mano" ? 0 : (ms[i] || 0) * rpmMax;
        R.rpm += (obj - R.rpm) * (1 - Math.exp(-dt / (obj > R.rpm ? 0.08 : 0.35)));
        if (obj <= 0) R.rpm = Math.max(0, R.rpm - 400 * dt);
        R.fase = (R.fase + R.s * R.rpm / 60 * TAU * dt) % TAU;
        R.palas.rotation.z = R.fase;
        const aP = 1 - smooth(H.rpm_palas, 3 * H.rpm_palas, R.rpm), kD = smooth(H.rpm_palas, H.rpm_disco, R.rpm);
        R.mp.opacity = H.opacidad * aP; R.palas.visible = aP > 0.01 && !oculto;
        R.md.userData.u.uInt.value = kD; R.md.userData.u.uFase.value = R.s * t * 1.7; R.dsc.visible = kD > 0.01 && !oculto;
      });
      const tl = (performance.now() / 1000) % 1, sc = visor ? 14 * 2 * Math.tan(visor.cam.fov / 2 * Math.PI / 180) / visor.renderer.domElement.height : 0.01;
      for (const l of luces) { l.visible = !oculto && (av.armado || tl < 0.5); l.children[0].scale.set(sc, sc, 1); }
    }
    const F = datos.fc, cam = { incl: F.camara_inclinacion_grados, fovH: F.camara_fov_h_grados, pos: F.camara_pos };     // para Visor._camara
    return { grupo, prof: new THREE.Group(), timon: new THREE.Group(), alerones: [], helice: new THREE.Group(), luces: [], dron: true, fpv: true, animar, cam };
  };
})();

// ---- datos del dron, en JSON estricto (claves entre comillas, colores en decimal, sin comentarios dentro): el simulador
// de Godot los lee tal cual de este fichero (simulador_godot/scripts/datos_comunes.gd busca la linea de la constante DATOS).
// propulsion: empuje estatico de un motor a tope con la bateria llena (V_ref = 4 x 4,2 V), vueltas a tope, diametro de la
// helice, par/empuje (m), J0 (avance con empuje nulo), inercia de un rotor (helice + campana), rendimiento del motor,
// bateria (celdas, mAh, resistencia interna del pack, curva de tension en vacio por celda segun la carga) y la
// electronica (controlador, VTX y camara, W).
// fc: motores [x, y, sentido (+1 horario visto desde arriba)] en el orden de Betaflight (1 trasero derecho, 2 delantero
// derecho, 3 trasero izquierdo, 4 delantero izquierdo; helices hacia dentro), ralenti (5,5 %), curva de gas, tasas
// (RC rate, super rate, expo: los de fabrica de Betaflight, 667 grados/s a fondo), angulo maximo y fuerza de nivelado de
// ANGLE, transicion de HORIZON, ganancias del PI (1/s, 1/s2), limites, respuesta de los motores, suavizado de la emisora,
// resistencias (CdA horizontal y vertical, m2; rotores, s/m), propwash, toma suave y la camara (inclinacion y campo de
// vision horizontal).
(function () {
  const DATOS = {
    "id": "FPV", "nombre": "Dron FPV de 5 pulgadas", "tipo": "fpv",
    "descripcion": "Dron de carreras y acrobacias de 650 g que se vuela con gafas, viendo lo que ve su cámara. No tiene GPS ni mantiene la altura: el gas va directo a los motores y hay que sostenerlo con la palanca izquierda. Empieza en modo ANGLE, que se nivela solo, y cuando lo domines pasa a ACRO, el modo de los pilotos de FPV.",
    "ayuda": "En ANGLE la palanca derecha inclina el dron y al soltarla se pone horizontal; en ACRO la palanca pide velocidad de giro y si la sueltas se queda con la inclinación que tenga (para nivelarlo hay que contrarrestar). El gas no se centra solo: el dron se sostiene con un 30–35 % de gas. Para aterrizar, baja despacio, pósalo y desarma (L).",
    "caracteristicas": [["Masa en vuelo", "650 g con la batería"], ["Bastidor", "X de 220 mm de fibra de carbono, hélices de 5 pulgadas de 3 palas"],
                        ["Motores", "2306 de 2450 KV: unos 1430 g de empuje cada uno con la batería llena"], ["Empuje / peso", "≈ 7 (se sostiene con un 30–35 % de gas)"],
                        ["Velocidad máxima", "unos 120 km/h"], ["Batería", "4S 1500 mAh (16,8 V llena, 14,8 V nominal): 4–8 min de vuelo; cae de tensión al acelerar"],
                        ["Modos (Betaflight)", "ANGLE (autonivelado, hasta 55°) · HORIZON · ACRO (sin autonivelado)"], ["Tasas", "RC rate 1,0 · super rate 0,70 · expo 0: 667 °/s a fondo"],
                        ["Cámara FPV", "inclinada 28° hacia arriba, 120° de campo de visión, con OSD de Betaflight"],
                        ["Mandos", "modo 2: izquierda gas (sin muelle) y guiñada, derecha alabeo y cabeceo"],
                        ["Armado", "con el gas abajo del todo (L o botón A); armado, los motores giran al ralentí"],
                        ["Controlador", "Betaflight: sin GPS ni retención de posición ni de altura"], ["Velocidad de pérdida", "0 m/s (no entra en pérdida)"]],
    "masa_kg": 0.65, "b_m": 0.3, "S_m2": 0.03, "inercia": { "Ixx": 0.0011, "Iyy": 0.0013, "Izz": 0.0021, "Ixz": 0 }, "cg_mm": [0, 0, 0],
    "propulsion": { "empuje_motor_N": 14.0, "rpm_max": 30000, "D_m": 0.127, "k_par_m": 0.0105, "J0": 0.9, "I_rotor": 0.000009, "rendimiento": 0.65,
                    "celdas": 4, "capacidad_mAh": 1500, "R_ohm": 0.015, "V_ref": 16.8, "masa_bateria_Wh": 22.2, "P_electronica_W": 5,
                    "curva_soc": [0, 0.05, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1], "curva_v": [3.27, 3.5, 3.62, 3.7, 3.75, 3.79, 3.83, 3.87, 3.92, 4.0, 4.08, 4.2] },
    "fc": { "motores": [[-0.078, 0.078, 1], [0.078, 0.078, -1], [-0.078, -0.078, -1], [0.078, -0.078, 1]], "brazo_m": 0.078,
            "ralenti": 0.055, "gas_medio": 0.5, "gas_expo": 0,
            "tasas": { "alabeo": { "rc": 1.0, "super": 0.7, "expo": 0 }, "cabeceo": { "rc": 1.0, "super": 0.7, "expo": 0 }, "guinada": { "rc": 1.0, "super": 0.7, "expo": 0 } },
            "angulo_max_grados": 55, "k_nivel": 7, "horizon_transicion": 0.75,
            "kp": [30, 30, 15], "ki": [25, 25, 15], "i_max": 0.5, "tau_guinada": 0.12, "tau_motor_s": 0.03, "rc_suavizado_s": 0.02,
            "cda_h": 0.015, "cda_v": 0.02, "k_rotor": 0.004, "propwash_par": 0.04, "propwash_perdida": 0.2, "toma_vz": 1.5, "toma_vh": 3,
            "camara_inclinacion_grados": 28, "camara_fov_h_grados": 120, "camara_pos": [0.075, 0, -0.035], "aviso_celda_V": 3.5, "critico_celda_V": 3.3 },
    "mandos": { "expo": 0.3, "prof_max_grados": 25, "aleron_max_grados": 25, "timon_max_grados": 0, "servo_vel_grados_s": 400, "servo_tau_s": 0.02, "izq_der": "alabeo (A/D: guiñada)" },
    "lanzamiento": { "vel_ms": 0, "cabeceo_grados": 0 }, "compensador_grados": 0,
    "colores": { "fuselaje": 1974050, "ala": 2829617, "estab": 1118481, "moviles": 16733986 },
    "modelo3d": {
      "materiales": [
        ["carbono", 1842463, 0.4, 0.0, 0.0, 0.0],
        ["metal_negro", 1776670, 0.3, 0.7, 0.0, 0.0],
        ["campana", 1710877, 0.3, 0.75, 0.0, 0.0],
        ["anodizado", 6119526, 0.3, 1.0, 0.0, 0.0],
        ["tornillo", 2829359, 0.38, 0.85, 0.0, 0.0],
        ["acero", 11843774, 0.22, 1.0, 0.0, 0.0],
        ["cromo", 14738407, 0.08, 1.0, 0.0, 0.0],
        ["vidrio", 395275, 0.03, 0.0, 1.0, 0.02],
        ["cobre", 12745541, 0.32, 1.0, 0.0, 0.0],
        ["tpu_verde", 8839197, 0.55, 0.0, 0.0, 0.0],
        ["tpu_negro", 2105635, 0.62, 0.0, 0.0, 0.0],
        ["pcb", 1184532, 0.32, 0.0, 0.5, 0.2],
        ["chip", 986897, 0.45, 0.0, 0.0, 0.0],
        ["funda", 2369322, 0.4, 0.0, 0.35, 0.25],
        ["velcro", 11738921, 0.9, 0.0, 0.0, 0.0],
        ["hebilla", 1447448, 0.4, 0.0, 0.2, 0.3],
        ["cable_negro", 1250067, 0.52, 0.0, 0.0, 0.0],
        ["cable_rojo", 10818587, 0.48, 0.0, 0.0, 0.0],
        ["xt60", 14723861, 0.48, 0.0, 0.2, 0.35],
        ["plastico_negro", 1513240, 0.55, 0.0, 0.0, 0.0],
        ["blanco", 15724522, 0.4, 0.0, 0.0, 0.0]
      ],
      "copias": {
        "brazos": [[0, 0, 0, 45], [0, 0, 0, -45], [0, 0, 0, 135], [0, 0, 0, -135]],
        "motores": [[0.078, 0.078, 0, 0], [0.078, -0.078, 0, 0], [-0.078, 0.078, 0, 0], [-0.078, -0.078, 0, 0]],
        "postes": [[0.044, 0.0172, 0, 0], [0.044, -0.0172, 0, 0], [-0.054, 0.0172, 0, 0], [-0.054, -0.0172, 0, 0]],
        "stack": [[0.01525, 0.01525, 0, 0], [0.01525, -0.01525, 0, 0], [-0.01525, 0.01525, 0, 0], [-0.01525, -0.01525, 0, 0]],
        "vtx": [[0.0085, 0.0085, 0, 0], [0.0085, -0.0085, 0, 0], [-0.0085, 0.0085, 0, 0], [-0.0085, -0.0085, 0, 0]],
        "cuadrantes": [[0, 0, 0, 0], [0, 0, 0, 90], [0, 0, 0, 180], [0, 0, 0, 270]],
        "lados": [[0, 0, 0, 0, 1], [0, 0, 0, 0, -1]]
      },
      "piezas": [
        {"t": "placa", "m": "carbono", "ejes": "xy", "s0": 0.006, "e": 0.0055, "ch": 0.0006, "copias": "brazos", "contorno": [[-0.012, -0.0066, 0.0015], [0.086, -0.0056, 0.01], [0.10326, -0.0122, 0.0122], [0.11734, -0.0122, 0.0122], [0.12439, 0, 0.0122], [0.11734, 0.0122, 0.0122], [0.10326, 0.0122, 0.0122], [0.086, 0.0056, 0.01], [-0.012, 0.0066, 0.0015]]},
        {"t": "placa", "m": "carbono", "ejes": "xy", "s0": 0.0115, "e": 0.002, "ch": 0.0004, "contorno": [[-0.06, -0.0205, 0.004], [0.052, -0.0205, 0.004], [0.052, 0.0205, 0.004], [-0.06, 0.0205, 0.004]], "agujeros": [[-0.036, 0, -0.014, 0, 0.004], [0.03, -0.01, 0.0025], [0.03, 0.01, 0.0025]]},
        {"t": "placa", "m": "carbono", "ejes": "xy", "s0": 0.004, "e": 0.002, "ch": 0.0004, "contorno": [[-0.06, -0.0205, 0.004], [0.052, -0.0205, 0.004], [0.052, 0.0205, 0.004], [-0.06, 0.0205, 0.004]]},
        {"t": "placa", "m": "carbono", "ejes": "xy", "s0": -0.0235, "e": 0.0025, "ch": 0.0004, "contorno": [[-0.066, -0.0165, 0.003], [-0.061, -0.0205, 0.003], [0.05, -0.0205, 0.006], [0.064, -0.014, 0.004], [0.064, 0.014, 0.004], [0.05, 0.0205, 0.006], [-0.061, 0.0205, 0.003], [-0.066, 0.0165, 0.003]], "agujeros": [[-0.0167, -0.0172, 0.0027, -0.0172, 0.0012], [-0.0167, 0.0172, 0.0027, 0.0172, 0.0012], [0.036, -0.0085, 0.052, -0.0085, 0.0022], [0.036, 0.0085, 0.052, 0.0085, 0.0022], [-0.05, -0.0095, 0.0022], [-0.05, 0.0095, 0.0022]]},
        {"t": "torno", "m": "anodizado", "copias": "postes", "o": [0, 0, 0.004], "eje": [0, 0, -1], "n": 16, "p": [[0, 0], [0.0022, 0], [0.0025, 0.0003], [0.0025, 0.0247], [0.0022, 0.025], [0, 0.025]]},
        {"t": "torno", "m": "tornillo", "copias": "postes", "o": [0, 0, -0.0235], "eje": [0, 0, -1], "n": 16, "p": [[0, 0], [0.0028, 0], [0.0028, 0.0004], [0.0023, 0.0013], [0.0012, 0.0017], [0, 0.0017]]},
        {"t": "torno", "m": "tornillo", "copias": "postes", "o": [0, 0, 0.0135], "eje": [0, 0, 1], "n": 16, "p": [[0, 0], [0.0028, 0], [0.0028, 0.0004], [0.0023, 0.0013], [0.0012, 0.0017], [0, 0.0017]]},
        {"t": "torno", "m": "tornillo", "copias": "brazos", "o": [0.024, 0, 0.0135], "eje": [0, 0, 1], "n": 16, "p": [[0, 0], [0.0028, 0], [0.0028, 0.0004], [0.0023, 0.0013], [0.0012, 0.0017], [0, 0.0017]]},
        {"t": "torno", "m": "tornillo", "copias": "brazos", "o": [0.008, 0, 0.0135], "eje": [0, 0, 1], "n": 16, "p": [[0, 0], [0.0028, 0], [0.0028, 0.0004], [0.0023, 0.0013], [0.0012, 0.0017], [0, 0.0017]]},
        {"t": "torno", "m": "metal_negro", "copias": "motores", "o": [0, 0, 0.006], "eje": [0, 0, -1], "n": 40, "p": [[0, 0], [0.0125, 0], [0.013, 0.0005], [0.013, 0.0024], [0.0124, 0.003], [0.0112, 0.0032], [0, 0.0032]]},
        {"t": "torno", "m": "cobre", "copias": "motores", "o": [0, 0, 0.006], "eje": [0, 0, -1], "n": 48, "p": [[0, 0.003], [0.0116, 0.003], [0.0121, 0.0034], [0.0121, 0.0108], [0.0116, 0.0112], [0, 0.0112]]},
        {"t": "torno", "m": "campana", "copias": "motores", "o": [0, 0, 0.006], "eje": [0, 0, -1], "n": 48, "p": [[0.0133, 0.0058], [0.0139, 0.006], [0.0141, 0.0066], [0.0141, 0.0074], [0.0138, 0.0076], [0.0138, 0.008], [0.0141, 0.0082], [0.0141, 0.016], [0.0137, 0.017], [0.0129, 0.0176], [0.0129, 0.0176], [0.0066, 0.0177], [0.0066, 0.0177], [0.0058, 0.0185], [0.0048, 0.019], [0.0048, 0.019], [0, 0.019]]},
        {"t": "torno", "m": "campana", "copias": "motores", "o": [0, 0, 0.006], "eje": [0, 0, -1], "n": 48, "dentro": true, "p": [[0.0133, 0.0058], [0.0133, 0.0176]]},
        {"t": "torno", "m": "acero", "copias": "motores", "o": [0, 0, 0.006], "eje": [0, 0, -1], "n": 16, "p": [[0, 0.019], [0.0025, 0.019], [0.0025, 0.0258], [0, 0.0258]]},
        {"t": "torno", "m": "anodizado", "copias": "motores", "o": [0, 0, -0.0197], "eje": [0, 0, -1], "n": 28, "p": [[0, 0], [0.0052, 0], [0.0052, 0], [0.0052, 0.0034], [0.0048, 0.004], [0.004, 0.0043], [0.0034, 0.006], [0.0022, 0.0068], [0, 0.007]]},
        {"t": "loft", "m": "tpu_verde", "copias": "brazos", "n": 3.2, "t0": 0.003, "t1": 0.0045, "nc": 32, "nt": 4, "e": [[0.094, 0, 0.0138, 0.008, 0.0063, 0.0062], [0.1, 0, 0.0138, 0.0112, 0.0063, 0.0062], [0.111, 0, 0.0138, 0.0124, 0.0063, 0.0062], [0.119, 0, 0.0138, 0.0114, 0.0063, 0.0062]]},
        {"t": "cajas", "m": "blanco", "copias": "brazos", "l": [[0.084, 0, 0.0119, 0.012, 0.0045, 0.0009]]},
        {"t": "tubo", "m": "cable_negro", "copias": "brazos", "r": 0.00055, "c": [[0.098, -0.0011, 0.0054, 0], [0.06, -0.0011, 0.0054, 0.01], [0.036, -0.0011, 0.0054, 0.004], [0.03, -0.0011, 0.0032, 0.004], [0.022, -0.0011, -0.0006, 0]]},
        {"t": "tubo", "m": "cable_negro", "copias": "brazos", "r": 0.00055, "c": [[0.098, 0, 0.0054, 0], [0.06, 0, 0.0054, 0.01], [0.036, 0, 0.0054, 0.004], [0.03, 0, 0.0032, 0.004], [0.022, 0, -0.0006, 0]]},
        {"t": "tubo", "m": "cable_negro", "copias": "brazos", "r": 0.00055, "c": [[0.098, 0.0011, 0.0054, 0], [0.06, 0.0011, 0.0054, 0.01], [0.036, 0.0011, 0.0054, 0.004], [0.03, 0.0011, 0.0032, 0.004], [0.022, 0.0011, -0.0006, 0]]},
        {"t": "placa", "m": "pcb", "ejes": "xy", "s0": -0.0004, "e": 0.0016, "ch": 0.0002, "contorno": [[-0.018, -0.018, 0.002], [0.018, -0.018, 0.002], [0.018, 0.018, 0.002], [-0.018, 0.018, 0.002]]},
        {"t": "placa", "m": "pcb", "ejes": "xy", "s0": -0.0112, "e": 0.0016, "ch": 0.0002, "contorno": [[-0.018, -0.018, 0.002], [0.018, -0.018, 0.002], [0.018, 0.018, 0.002], [-0.018, 0.018, 0.002]]},
        {"t": "placa", "m": "pcb", "ejes": "xy", "s0": -0.0172, "e": 0.0012, "ch": 0.0002, "contorno": [[-0.01, -0.01, 0.0015], [0.01, -0.01, 0.0015], [0.01, 0.01, 0.0015], [-0.01, 0.01, 0.0015]]},
        {"t": "cajas", "m": "chip", "copias": "cuadrantes", "l": [[0.0085, 0.0105, -0.0009, 0.005, 0.006, 0.001], [0.011, 0.004, -0.0009, 0.006, 0.005, 0.001]]},
        {"t": "cajas", "m": "chip", "l": [[0, 0, -0.0008, 0.005, 0.005, 0.0008], [0, 0, -0.0117, 0.007, 0.007, 0.001], [0.0065, -0.006, -0.01165, 0.003, 0.003, 0.0009], [0.008, 0.012, -0.0116, 0.003, 0.002, 0.0008]]},
        {"t": "cajas", "m": "acero", "l": [[-0.003, -0.0145, -0.0128, 0.009, 0.007, 0.0032], [0, 0, -0.0179, 0.015, 0.015, 0.0014]]},
        {"t": "torno", "m": "plastico_negro", "copias": "stack", "o": [0, 0, 0.004], "eje": [0, 0, -1], "n": 14, "p": [[0, 0], [0.0016, 0], [0.0016, 0.0006], [0.0029, 0.0006], [0.0029, 0.0026], [0.0016, 0.0026], [0.0016, 0.0044], [0.0029, 0.0044], [0.0029, 0.0062], [0.0016, 0.0062], [0.0016, 0.0118], [0.0029, 0.0118], [0.0029, 0.0136], [0.0016, 0.0136], [0.0016, 0.0152], [0.0029, 0.0152], [0.0029, 0.0168], [0.0027, 0.017], [0.0027, 0.0182], [0.0016, 0.0184], [0, 0.0185]]},
        {"t": "torno", "m": "plastico_negro", "copias": "vtx", "o": [0, 0, -0.0112], "eje": [0, 0, -1], "n": 10, "p": [[0, 0], [0.0012, 0], [0.0012, 0.0048], [0, 0.0048]]},
        {"t": "torno", "m": "plastico_negro", "o": [-0.0215, -0.01, -0.0005], "eje": [-1, 0, 0], "n": 24, "p": [[0, 0], [0.0045, 0], [0.0045, 0.0195], [0.0041, 0.02], [0, 0.0201]]},
        {"t": "tubo", "m": "cable_rojo", "r": 0.0013, "c": [[-0.017, 0.004, -0.0004, 0], [-0.03, 0.0045, -0.004, 0.006], [-0.056, 0.009, -0.0085, 0.008], [-0.066, 0.0126, -0.017, 0.004], [-0.07, 0.0126, -0.02, 0]]},
        {"t": "tubo", "m": "cable_negro", "r": 0.0013, "c": [[-0.017, -0.004, -0.0004, 0], [-0.03, -0.003, -0.004, 0.006], [-0.056, 0.003, -0.0085, 0.008], [-0.066, 0.0054, -0.017, 0.004], [-0.07, 0.0054, -0.02, 0]]},
        {"t": "cajas", "m": "xt60", "l": [[-0.0823, 0.009, -0.02, 0.0265, 0.0155, 0.0081]]},
        {"t": "loft", "m": "metal_negro", "n": 8, "t0": 0.0006, "t1": 0.0006, "nc": 48, "arriba": [-0.469472, 0.0, -0.882948], "e": [[0.048495, 0.0, -0.004509, 0.0095, 0.0095, 0.0095], [0.062622, 0.0, -0.012021, 0.0095, 0.0095, 0.0095]]},
        {"t": "torno", "m": "cromo", "o": [0.063152, 0.0, -0.012303], "eje": [0.882948, 0.0, -0.469472], "n": 48, "p": [[0.0076, -0.0004], [0.0076, 0.0028], [0.0072, 0.0034], [0.0063, 0.0034]]},
        {"t": "torno", "m": "metal_negro", "o": [0.063152, 0.0, -0.012303], "eje": [0.882948, 0.0, -0.469472], "n": 48, "p": [[0.0063, 0.0034], [0.0061, 0.0034], [0.0061, 0.0086], [0.0057, 0.009]]},
        {"t": "torno", "m": "cromo", "o": [0.063152, 0.0, -0.012303], "eje": [0.882948, 0.0, -0.469472], "n": 48, "p": [[0.0057, 0.009], [0.0057, 0.0096], [0.0051, 0.0099], [0.0046, 0.0097]]},
        {"t": "torno", "m": "vidrio", "o": [0.063152, 0.0, -0.012303], "eje": [0.882948, 0.0, -0.469472], "n": 48, "p": [[0.0046, 0.0097], [0.004, 0.0101], [0.0025, 0.0106], [0, 0.0108]]},
        {"t": "placa", "m": "tpu_negro", "ejes": "xz", "s0": 0.0098, "e": 0.003, "ch": 0.0004, "copias": "lados", "contorno": [[0.038, 0.004, 0.002], [0.058, 0.004, 0.004], [0.07, -0.001, 0.005], [0.071, -0.015, 0.005], [0.063, -0.021, 0.003], [0.038, -0.021, 0.002]]},
        {"t": "torno", "m": "tornillo", "copias": "lados", "o": [0.056, 0.0128, -0.0085], "eje": [0, 1, 0], "n": 16, "p": [[0, 0], [0.0019, 0], [0.0019, 0.0005], [0.0015, 0.0011], [0, 0.0012]]},
        {"t": "loft", "m": "tpu_negro", "n": 3, "t0": 0.0012, "t1": 0.0012, "nc": 32, "e": [[-0.0675, 0, -0.0275, 0.007, 0.004, 0.004], [-0.0545, 0, -0.0275, 0.007, 0.004, 0.004]]},
        {"t": "loft", "m": "tpu_negro", "n": 2, "t0": 0, "t1": 0.0008, "nc": 24, "arriba": [0, 1, 0], "e": [[-0.061, 0, -0.0305, 0.0034, 0.0034, 0.0034], [-0.0637, 0, -0.038, 0.0026, 0.0026, 0.0026]]},
        {"t": "tubo", "m": "plastico_negro", "r": 0.0016, "c": [[-0.061, 0, -0.03, 0], [-0.0808, 0, -0.0845, 0]]},
        {"t": "loft", "m": "plastico_negro", "n": 2, "t0": 0.0022, "t1": 0.003, "nc": 32, "arriba": [0, 1, 0], "e": [[-0.0808, 0, -0.0845, 0.0058, 0.0058, 0.0058], [-0.08655, 0, -0.10029, 0.0058, 0.0058, 0.0058]]},
        {"t": "loft", "m": "funda", "n": 9, "t0": 0.0022, "t1": 0.0022, "m0": 3, "m1": 3, "nc": 64, "e": [[-0.044, 0, -0.041, 0.017, 0.017, 0.017], [0.03, 0, -0.041, 0.017, 0.017, 0.017]]},
        {"t": "tubo", "m": "cable_rojo", "r": 0.0013, "c": [[-0.0455, 0.0126, -0.05, 0], [-0.06, 0.0126, -0.053, 0.006], [-0.09, 0.0126, -0.05, 0.01], [-0.108, 0.0126, -0.034, 0.008], [-0.105, 0.0126, -0.021, 0.004], [-0.096, 0.0126, -0.02, 0]]},
        {"t": "tubo", "m": "cable_negro", "r": 0.0013, "c": [[-0.0455, 0.0054, -0.05, 0], [-0.06, 0.0054, -0.053, 0.006], [-0.09, 0.0054, -0.05, 0.01], [-0.108, 0.0054, -0.034, 0.008], [-0.105, 0.0054, -0.021, 0.004], [-0.096, 0.0054, -0.02, 0]]},
        {"t": "tubo", "m": "cable_negro", "r": 0.001, "c": [[-0.0455, -0.01, -0.054, 0], [-0.0475, -0.01, -0.0595, 0.002], [-0.04, -0.01, -0.0592, 0.003], [-0.033, -0.01, -0.0602, 0]]},
        {"t": "cajas", "m": "blanco", "l": [[-0.0265, -0.01, -0.0602, 0.013, 0.0052, 0.004]]},
        {"t": "tubo", "m": "velcro", "cerrado": true, "arriba": [1, 0, 0], "sec": [0.0006, 0.01, 0.01, 6], "c": [[-0.007, 0, -0.0587, 0], [-0.007, 0.0178, -0.0587, 0.003], [-0.007, 0.0178, -0.0204, 0.0012], [-0.007, -0.0178, -0.0204, 0.0012], [-0.007, -0.0178, -0.0587, 0.003]]},
        {"t": "cajas", "m": "velcro", "l": [[-0.007, -0.001, -0.0597, 0.02, 0.024, 0.0011]]},
        {"t": "cajas", "m": "hebilla", "l": [[-0.007, 0.0118, -0.0601, 0.023, 0.007, 0.002]]}
      ],
      "rotores": [[-0.078, 0.078, -0.0162, 1], [0.078, 0.078, -0.0162, -1], [-0.078, -0.078, -0.0162, -1], [0.078, -0.078, -0.0162, 1]],
      "helice": {"palas": 3, "R": 0.0635, "r0": 0.0058, "paso": 0.109, "beta_max": 32, "filas": 30, "puntos": 12, "cuerda": [[0, 0.0085], [0.1, 0.0125], [0.28, 0.0148], [0.5, 0.0142], [0.7, 0.0122], [0.85, 0.0098], [0.94, 0.0074], [1.0, 0.0035]], "espesor": [0.12, 0.05], "curvatura": 0.04, "flecha": 0.008, "conicidad": 0.001, "buje": [[0.0026, -0.0032], [0.0064, -0.0032], [0.0069, -0.0027], [0.0069, 0.003], [0.0064, 0.0035], [0.0026, 0.0035]], "col": 9212827, "rug": 0.22, "opacidad": 0.62, "disco_col": 5922919, "rpm_palas": 250, "rpm_disco": 1100},
      "luces": [{"p": [-0.0594, 0.0594, 0.0124], "color": 16717636}, {"p": [-0.0594, -0.0594, 0.0124], "color": 16717636}, {"p": [0.0594, 0.0594, 0.0124], "color": 16777215}, {"p": [0.0594, -0.0594, 0.0124], "color": 16777215}],
      "sombreador": [
        "vec3 fpv_lineal(vec3 c) { return mix(c / 12.92, pow((c + vec3(0.055)) / 1.055, vec3(2.4)), step(vec3(0.04045), c)); }",
        "float fpv_hash(vec2 c) { return fract(sin(dot(c, vec2(12.9898, 78.233))) * 43758.5453); }",
        "float fpv_seg(vec2 p, vec2 a, vec2 b) { vec2 pa = p - a; vec2 ba = b - a; float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0); return length(pa - ba * h); }",
        "float fpv_bit(float c, float k) { return mod(floor(c / exp2(k) + 0.001), 2.0); }",
        "float fpv_digito(vec2 p, float c) {",
        "  float d = 1000.0;",
        "  if (fpv_bit(c, 0.0) > 0.5) d = min(d, fpv_seg(p, vec2(0.18, 1.82), vec2(0.82, 1.82)));",
        "  if (fpv_bit(c, 1.0) > 0.5) d = min(d, fpv_seg(p, vec2(0.82, 1.82), vec2(0.82, 1.0)));",
        "  if (fpv_bit(c, 2.0) > 0.5) d = min(d, fpv_seg(p, vec2(0.82, 1.0), vec2(0.82, 0.18)));",
        "  if (fpv_bit(c, 3.0) > 0.5) d = min(d, fpv_seg(p, vec2(0.18, 0.18), vec2(0.82, 0.18)));",
        "  if (fpv_bit(c, 4.0) > 0.5) d = min(d, fpv_seg(p, vec2(0.18, 0.18), vec2(0.18, 1.0)));",
        "  if (fpv_bit(c, 5.0) > 0.5) d = min(d, fpv_seg(p, vec2(0.18, 1.0), vec2(0.18, 1.82)));",
        "  if (fpv_bit(c, 6.0) > 0.5) d = min(d, fpv_seg(p, vec2(0.18, 1.0), vec2(0.82, 1.0)));",
        "  return d;",
        "}",
        "float fpv_texto(vec2 p, vec4 c) {",
        "  vec2 q = vec2(p.x - p.y * 0.2, p.y);",
        "  float i = floor(q.x / 0.64);",
        "  if (i < 0.0 || i > 3.0 || q.y < -0.2 || q.y > 1.2) return 1000.0;",
        "  float k = i < 0.5 ? c.x : (i < 1.5 ? c.y : (i < 2.5 ? c.z : c.w));",
        "  return 0.5 * fpv_digito(vec2((q.x - i * 0.64) * 2.0, q.y * 2.0), k);",
        "}",
        "float fpv_tinta(float d, float w, float fw) { return 1.0 - smoothstep(w - fw, w + fw, d); }",
        "vec3 fpv_perturbar(vec3 N, vec3 P, vec2 uv, vec2 g) {",
        "  vec3 dp1 = dFdx(P);",
        "  vec3 dp2 = dFdy(P);",
        "  vec2 du1 = dFdx(uv);",
        "  vec2 du2 = dFdy(uv);",
        "  vec3 dp2p = cross(dp2, N);",
        "  vec3 dp1p = cross(N, dp1);",
        "  vec3 T = dp2p * du1.x + dp1p * du2.x;",
        "  vec3 B = dp2p * du1.y + dp1p * du2.y;",
        "  float im = inversesqrt(max(max(dot(T, T), dot(B, B)), 1e-30));",
        "  return normalize(N - (T * g.x + B * g.y) * im);",
        "}",
        "float fpv_disco(vec2 lp, float fase, float r0, float R) {",
        "  float r = length(lp);",
        "  float xi = clamp((r - r0) / (R - r0), 0.0, 1.0);",
        "  float cob = clamp(PALAS * fpv_cuerda(xi) / (6.2831853 * max(r, 0.0001)), 0.0, 1.0);",
        "  float a = atan(lp.y, lp.x) - fase;",
        "  float fantasma = pow(abs(cos(a * PALAS * 0.5)), 16.0);",
        "  return clamp(cob * 2.2 * (0.75 + 0.6 * fantasma), 0.0, 0.85) * smoothstep(r0, r0 + 0.0015, r) * (1.0 - smoothstep(R - 0.0008, R, r));",
        "}",
        "void fpv_detalle(float m, vec4 d, vec3 p, vec3 n, inout vec3 alb, inout float rug, inout float met, inout float cc, inout float ao, inout float hueco, inout vec3 pert) {",
        "  if (abs(m - M_CARBONO) < 0.5) {",
        "    if (abs(n.z) > 0.9) {",
        "      vec2 q = d.xy / 0.0017;",
        "      vec2 fq = fwidth(q);",
        "      float lejos = smoothstep(0.2, 0.6, max(fq.x, fq.y));",
        "      vec2 c = floor(q);",
        "      vec2 f = fract(q);",
        "      float sx = step(mod(c.x + c.y, 4.0), 1.5);",
        "      float t = mix(f.x, f.y, sx);",
        "      float perfil = sin(3.14159265 * t);",
        "      float g = cos(3.14159265 * t) * 0.35 * (1.0 - lejos);",
        "      pert = vec3(mix(vec2(g, 0.0), vec2(0.0, g), sx), 1.0);",
        "      alb *= mix(0.84 + 0.24 * perfil + 0.06 * sx, 1.04, lejos);",
        "      rug = mix(rug + 0.12 * (1.0 - perfil), rug + 0.04, lejos);",
        "    } else {",
        "      float k = d.z * 9.0;",
        "      float vis = 1.0 - smoothstep(0.3, 0.6, fwidth(k));",
        "      alb = alb * 1.7 * (0.85 + 0.3 * (0.5 + 0.5 * cos(6.2831853 * k)) * vis);",
        "      rug = 0.8;",
        "    }",
        "    return;",
        "  }",
        "  if (abs(m - M_CAMPANA) < 0.5) {",
        "    float r = d.y;",
        "    float h = d.z;",
        "    if (h > 0.0172 && r > 0.0067 && r < 0.0129) {",
        "      float a = d.x * 7.0 + (r - 0.0067) * 40.0;",
        "      float fa = fract(a);",
        "      if (fa > 0.22 && fa < 0.78 && r > 0.0073 && r < 0.0123) hueco = 1.0;",
        "      float k = r / 0.00012;",
        "      alb *= 1.0 + 0.3 * (0.5 + 0.5 * cos(6.2831853 * k)) * (1.0 - smoothstep(0.3, 0.6, fwidth(k)));",
        "    } else if (r > 0.0137 && h > 0.0082 && h < 0.0157) {",
        "      float s = fract(d.x * 2.0) * 3.14159265 * 0.0141;",
        "      vec2 pt = vec2((s - 0.0140) / 0.0036, (h - 0.0101) / 0.0036);",
        "      float tinta = fpv_tinta(fpv_texto(pt, vec4(91.0, 79.0, 63.0, 125.0)), 0.06, max(fwidth(pt.y), 0.0001));",
        "      float raya = fpv_tinta(abs(h - 0.0088), 0.00018, max(fwidth(h), 0.000001)) * step(0.5, fract(d.x * 2.0));",
        "      tinta = max(tinta, raya);",
        "      alb = mix(alb, vec3(0.75), tinta);",
        "      met = mix(met, 0.0, tinta);",
        "      rug = mix(rug, 0.55, tinta);",
        "    }",
        "    return;",
        "  }",
        "  if (abs(m - M_COBRE) < 0.5) {",
        "    float w = fract(d.x * 12.0);",
        "    float gap = 1.0 - smoothstep(0.05, 0.12, min(w, 1.0 - w));",
        "    float k = (d.z + d.y) / 0.0003;",
        "    float vis = 1.0 - smoothstep(0.3, 0.6, fwidth(k));",
        "    float hilo = 0.5 + 0.5 * cos(6.2831853 * k);",
        "    alb *= mix(1.0, 0.7 + 0.4 * hilo, vis);",
        "    rug += 0.12 * (1.0 - hilo) * vis;",
        "    alb = mix(alb, vec3(0.015), gap);",
        "    met = mix(met, 0.2, gap);",
        "    ao = 1.0 - 0.6 * gap;",
        "    return;",
        "  }",
        "  if (abs(m - M_TORNILLO) < 0.5) {",
        "    float a6 = (fract(d.x * 6.0) - 0.5) * 1.0471976;",
        "    float rh = d.y * cos(a6);",
        "    float s = (1.0 - smoothstep(0.00085, 0.00095, rh)) * step(0.0009, d.z);",
        "    alb = mix(alb, vec3(0.004), s);",
        "    rug = mix(rug, 0.9, s);",
        "    ao = 1.0 - 0.8 * s;",
        "    return;",
        "  }",
        "  if (abs(m - M_TPU_VERDE) < 0.5 || abs(m - M_TPU_NEGRO) < 0.5) {",
        "    float lat = 1.0 - smoothstep(0.8, 0.95, abs(n.z));",
        "    float k = p.z / 0.0002;",
        "    float v1 = (1.0 - smoothstep(0.25, 0.6, fwidth(k))) * lat;",
        "    float capa = 0.5 + 0.5 * cos(6.2831853 * k);",
        "    float k2 = (p.x + p.y) / 0.0004;",
        "    float v2 = (1.0 - smoothstep(0.25, 0.6, fwidth(k2))) * (1.0 - lat);",
        "    float relleno = 0.5 + 0.5 * cos(6.2831853 * k2);",
        "    alb *= 1.0 - 0.14 * capa * v1 - 0.08 * relleno * v2;",
        "    rug += 0.12 * capa * v1 + 0.06 * relleno * v2;",
        "    return;",
        "  }",
        "  if (abs(m - M_PCB) < 0.5) {",
        "    if (abs(n.z) > 0.9) {",
        "      vec2 q = d.xy / 0.0015;",
        "      vec2 c = floor(q);",
        "      vec2 f = fract(q) - 0.5;",
        "      float hs = fpv_hash(c + vec2(d.z * 7.0, 0.0));",
        "      vec2 tam = vec2(0.18 + 0.2 * fract(hs * 7.3), 0.12 + 0.14 * fract(hs * 3.7));",
        "      float comp = step(0.62, hs) * step(abs(f.x), tam.x) * step(abs(f.y), tam.y);",
        "      float term = comp * step(tam.x - 0.09, abs(f.x));",
        "      vec2 e = abs(d.xy) - vec2(0.0118);",
        "      float pad = step(0.0, e.x) * step(0.0, e.y) * step(abs(d.x), 0.0168) * step(abs(d.y), 0.0168);",
        "      float vis = 1.0 - smoothstep(0.25, 0.6, max(fwidth(q.x), fwidth(q.y)));",
        "      vec3 col = mix(vec3(0.07, 0.06, 0.05), vec3(0.72, 0.70, 0.66), term);",
        "      alb = mix(alb, col, comp * vis);",
        "      alb = mix(alb, vec3(0.62, 0.45, 0.16), pad);",
        "      met = mix(met, 1.0, max(pad, term * vis));",
        "      rug = mix(rug, 0.3, pad);",
        "    }",
        "    return;",
        "  }",
        "  if (abs(m - M_FUNDA) < 0.5) {",
        "    float extremo = smoothstep(0.024, 0.031, abs(p.x + 0.007));",
        "    rug += 0.2 * extremo * (0.5 + 0.5 * sin(p.y * 4000.0 + p.z * 3000.0));",
        "    if (n.z < -0.85) {",
        "      float banda = 1.0 - smoothstep(0.0028, 0.0032, abs(p.x + 0.0315 - 0.35 * p.y));",
        "      alb = mix(alb, vec3(0.62, 0.035, 0.02), banda);",
        "      vec2 pt = (vec2(p.x, -p.y) - vec2(0.0055, -0.0060)) / 0.0080;",
        "      float t1 = fpv_tinta(fpv_texto(pt, vec4(6.0, 109.0, 63.0, 63.0)), 0.06, max(fwidth(pt.y), 0.0001));",
        "      vec2 pt2 = (vec2(p.x, -p.y) - vec2(0.0058, 0.0048)) / 0.0045;",
        "      float t2 = fpv_tinta(fpv_texto(pt2, vec4(102.0, 109.0, 0.0, 0.0)), 0.07, max(fwidth(pt2.y), 0.0001));",
        "      alb = mix(alb, vec3(0.8), max(t1, t2));",
        "    } else if (abs(n.y) > 0.85) {",
        "      vec2 q = vec2(p.x * sign(n.y), -p.z);",
        "      float et = step(abs(q.x + 0.007), 0.026) * step(abs(q.y - 0.041), 0.0085);",
        "      alb = mix(alb, vec3(0.16, 0.17, 0.18), et);",
        "      float filete = et * (1.0 - step(abs(q.y - 0.041), 0.0072));",
        "      alb = mix(alb, vec3(0.62, 0.035, 0.02), filete);",
        "      vec2 pt = (q - vec2(-0.0165, 0.0378)) / 0.0062;",
        "      float t1 = fpv_tinta(fpv_texto(pt, vec4(6.0, 91.0, 63.0, 57.0)), 0.07, max(fwidth(pt.y), 0.0001));",
        "      alb = mix(alb, vec3(0.75), t1 * et);",
        "    }",
        "    return;",
        "  }",
        "  if (abs(m - M_VELCRO) < 0.5) {",
        "    float k = p.x / 0.0006;",
        "    float vis = 1.0 - smoothstep(0.25, 0.6, fwidth(k));",
        "    alb *= 1.0 - 0.2 * (0.5 + 0.5 * cos(6.2831853 * k)) * vis;",
        "    alb *= 1.0 - 0.35 * smoothstep(0.0085, 0.0095, abs(p.x + 0.007));",
        "    return;",
        "  }",
        "  if (abs(m - M_XT60) < 0.5) {",
        "    alb *= 1.0 - 0.8 * (1.0 - smoothstep(0.00015, 0.0003, abs(p.x + 0.0823)));",
        "    return;",
        "  }",
        "}"
      ]
    }
  };
  Modelos.registrar(DATOS, ModeloFPV);
})();
