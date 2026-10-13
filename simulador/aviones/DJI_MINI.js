// Cuadricoptero tipo DJI Mini 4K (249 g) para practicar los mandos del DJI antes de volar el de verdad.
// A diferencia de los aviones, aqui manda un CONTROLADOR DE VUELO como el del DJI (modo estabilizado con retencion
// de posicion y altura, como con GPS): la palanca derecha pide VELOCIDAD horizontal (adelante/atras, laterales), la
// izquierda velocidad vertical (arriba/abajo) y giro sobre si mismo (guinada). Con las palancas en el centro frena y se
// queda quieto en el sitio, tambien con viento (se inclina contra el). El controlador manda inclinaciones y pares a los
// motores con sus limites reales (inclinacion maxima, empuje maximo, par maximo) y el dron responde con su inercia,
// su resistencia aerodinamica y el viento: no es un "teleport", se nota el retardo al frenar y las rachas.
// Mandos del DJI (modo 2): palanca izquierda gas (velocidad vertical, con muelle) y guinada; derecha inclinacion.
// Modos de vuelo C / N / S (Cine, Normal, Sport) como el conmutador del mando: cambian velocidades, inclinacion y giro.
// Gimbal de 3 ejes: la camara va nivelada y su inclinacion (0 horizontal, -90 vertical) la mueve la rueda del mando.
// Despegue automatico (sube a 1,2 m y se queda), volver a casa (RTH: sube a 30 m, vuelve al punto de despegue y
// aterriza) y aterrizaje con la palanca abajo, como en la app DJI Fly. Teclado: flechas inclinan (arriba = adelante),
// W/S suben y bajan, A/D giran, Q/E gimbal, M modo, H volver a casa, L arma los motores.
// Ejes y estado como en ModeloAvion (cuerpo x adelante, y derecha, z abajo; mundo NED), para que el simulador, el
// HUD, la caja negra y la repeticion funcionen igual. No tiene perdida (av.perdida = 0) ni angulo de ataque.
window.ModeloCuadricoptero = window.ModeloCuadricoptero || class ModeloCuadricoptero {
  constructor(datos) {
    Object.assign(this, datos);
    this.esCuadricoptero = true;
    this.modo = "N"; this.casa = null;                       // modo de vuelo (C/N/S) y punto de despegue [N, E] (para el RTH)
    this.masa_diseno_kg = datos.masa_kg; this.inercia_diseno = Object.assign({}, datos.inercia);
    this.dcg = 0; this.rho = RHO; this.calib = { empuje: 1, resistencia: 1 }; this.facil = false;
    this.mandos = Object.assign({}, datos.mandos);
  }
  /** Masa, temperatura (densidad), empuje medido (gf, el maximo de los 4 motores) y factor de resistencia. */
  configurar({ masa_kg, cg_mm, temperatura, empuje_gf, resistencia }) {
    if (temperatura !== undefined) this.rho = 101325 / (287.05 * (temperatura + 273.15));
    if (empuje_gf) this.calib.empuje = empuje_gf / 1000 * G0 / this.propulsion.empuje_max_N;
    if (resistencia) this.calib.resistencia = resistencia;
    if (masa_kg) { this.masa_kg = masa_kg; const k = masa_kg / this.masa_diseno_kg; for (const n in this.inercia_diseno) this.inercia[n] = this.inercia_diseno[n] * k; }
  }
  /** En el suelo, motores parados ("en mano" para el simulador: L los arma). */
  estadoInicial() {
    return { p: [0, 0, -0.02], q: Cuat.desdeEuler(0, 0, 0), v: [0, 0, 0], w: [0, 0, 0], de: 0, dr: 0, da: 0, gases: 0, Wh: 0, asim: 0,
             estado: "en mano", t: 0, alfa: 0, beta: 0, V: 0, g_carga: 1, perdida: 0, T: 0, rpm: 0, motorRoto: false,
             posado: true, despegado: false, tParar: 0, cmd: { adelante: 0, derecha: 0, guinada: 0, vz: 0 },
             gimbal: -10, rth: null, despegueAuto: false, hold: null };
  }
  /** Armar: motores al ralenti en el suelo; despega al pedir velocidad vertical. */
  lanzar(av) {
    av.v = [0, 0, 0]; av.w = [0, 0, 0]; av.estado = "volando"; av.posado = true; av.despegado = false; av.tParar = 0;
    av.q = Cuat.desdeEuler(0, 0, Cuat.euler(av.q)[2]);
    av.rth = null; av.despegueAuto = false; av.hold = null; this.casa = [av.p[0], av.p[1]];     // punto de casa: donde arranca
  }
  /** Palancas -> consignas (con la exponencial del simulador; con mando la pone el mando y expo vale 0), suavizadas
   *  como la respuesta de la emisora. mando: pitch (+ = palanca hacia ti = atras), yaw (+ = derecha), guinada, vz. */
  servos(av, mando, dt) {
    const e = this.mandos.expo || 0, ex = s => (1 - e) * s + e * s * s * s, cl = x => Math.max(-1, Math.min(1, x || 0));
    const obj = { adelante: ex(cl(-mando.pitch)), derecha: ex(cl(mando.yaw)), guinada: ex(cl(mando.guinada)), vz: cl(mando.vz) };
    // cualquier palanca cancela el RTH y el despegue automatico (como en el DJI)
    if (Math.max(...Object.values(obj).map(Math.abs)) > 0.3) { av.rth = null; av.despegueAuto = false; }
    if (av.rth) this._rth(av, obj);
    else if (av.despegueAuto) { obj.adelante = obj.derecha = obj.guinada = 0; obj.vz = av.agl < 1.2 ? 0.5 : 0; if (av.agl >= 1.2) av.despegueAuto = false; }
    for (const k in obj) av.cmd[k] += Math.max(-10 * dt, Math.min(10 * dt, obj[k] - av.cmd[k]));
    av.gimbal = Math.max(-90, Math.min(10, av.gimbal + 45 * cl(mando.gimbal) * dt));      // rueda del gimbal: 45 grados/s
  }
  /** Volver a casa: sube a la altura de RTH, va al punto de despegue a 8 m/s mirando hacia el, y aterriza. Escribe las consignas en obj. */
  _rth(av, obj) {
    const R = av.rth, casa = this.casa || [0, 0], dN = casa[0] - av.p[0], dE = casa[1] - av.p[1], d = Math.hypot(dN, dE);
    const vn = Cuat.rot(av.q, av.v), yaw = Cuat.euler(av.q)[2], M = this.fc.modos[this.modo] || this.fc.modos.N, cl = x => Math.max(-1, Math.min(1, x));
    obj.adelante = obj.derecha = obj.guinada = 0; obj.vz = 0;
    if (R.fase === "subir") { obj.vz = av.agl < this.fc.rth_altura_m - 0.5 ? 1 : 0; if (av.agl >= this.fc.rth_altura_m - 0.5 || d < 5) R.fase = "volver"; }
    if (R.fase === "volver") {
      const vObj = Math.min(8, d * 0.6), vN = dN / Math.max(d, 1e-3) * vObj, vE = dE / Math.max(d, 1e-3) * vObj;
      const cy = Math.cos(yaw), sy = Math.sin(yaw);     // velocidad objetivo en ejes de rumbo, como si fuera la palanca
      obj.adelante = cl((vN * cy + vE * sy) / M.vmax_ms); obj.derecha = cl((-vN * sy + vE * cy) / M.vmax_ms);
      const rumbo = Math.atan2(dE, dN), err = Math.atan2(Math.sin(rumbo - yaw), Math.cos(rumbo - yaw));
      obj.guinada = d > 3 ? cl(err * 2) : 0;
      if (d < 1.5 && Math.hypot(vn[0], vn[1]) < 0.8) R.fase = "bajar";
    }
    if (R.fase === "bajar") { obj.vz = -1; av.hold = [casa[0], casa[1]]; }      // baja sujetando la posicion sobre casa
  }
  /** Volver a casa (boton RTH de la app o tecla H). */
  volverACasa(av) {
    if (av.estado !== "volando" || av.posado) return;
    av.despegueAuto = false; av.rth = { fase: av.agl < this.fc.rth_altura_m - 0.5 ? "subir" : "volver" };
  }
  /** Despegue automatico (boton de la app): arma los motores y sube a 1,2 m. */
  despegar(av) { if (av.estado !== "volando") this.lanzar(av); if (av.posado) av.despegueAuto = true; }
  mandosCoef() { return { CL: 0, CY: 0, Cl: 0, Cm: 0, Cn: 0 }; }
  /** Un paso: controlador de vuelo -> empuje y pares -> dinamica de 6 grados de libertad. Devuelve la velocidad NED. */
  paso(av, viento, dt) {
    const m = this.masa_kg, I = this.inercia, F = this.fc, pr = this.propulsion, q = av.q, v = av.v, w = av.w, rho = this.rho;
    const Tmax = pr.empuje_max_N * this.calib.empuje, suelo = av.agl === undefined ? 0 : -av.p[2] - av.agl;
    const M = F.modos[this.modo] || F.modos.N, tilt = M.inclinacion_grados * D2R, c = av.cmd;
    if (av.motorRoto) { c.vz = -1; }
    // --- estado: velocidad respecto al suelo en NED y en ejes de rumbo (adelante, derecha), angulos ---
    const vn = Cuat.rot(q, v), [roll, pitch, yaw] = Cuat.euler(q), cy = Math.cos(yaw), sy = Math.sin(yaw);
    const vf = vn[0] * cy + vn[1] * sy, vr = -vn[0] * sy + vn[1] * cy, vzUp = -vn[2];
    // --- controlador de vuelo ---
    // velocidad horizontal objetivo (palanca derecha) -> aceleracion -> inclinacion objetivo (tope: inclinacion maxima)
    const amax = G0 * Math.tan(tilt);
    // retencion de posicion (GPS): con la palanca derecha en el centro y ya frenado, se sujeta el punto donde se paro
    // (sin esto, el viento lo iria arrastrando despacio, como un dron sin GPS)
    const quieto = Math.abs(c.adelante) < 0.02 && Math.abs(c.derecha) < 0.02;
    if (quieto && !av.posado) { if (!av.hold && Math.hypot(vf, vr) < 0.5) av.hold = [av.p[0], av.p[1]]; } else av.hold = null;
    let vfObj = c.adelante * M.vmax_ms, vrObj = c.derecha * M.vmax_ms;
    if (av.hold) {
      const lim2 = (x, L) => Math.max(-L, Math.min(L, x)), vN = lim2(0.7 * (av.hold[0] - av.p[0]), 2), vE = lim2(0.7 * (av.hold[1] - av.p[1]), 2);
      vfObj += vN * cy + vE * sy; vrObj += -vN * sy + vE * cy;
    }
    let af = M.kv * (vfObj - vf), ar = M.kv * (vrObj - vr);
    const an = Math.hypot(af, ar); if (an > amax) { af *= amax / an; ar *= amax / an; }
    const pitchObj = -Math.atan(af / G0), rollObj = Math.atan(ar / G0);
    // velocidad vertical objetivo (palanca izquierda): sube a vzmax_sube, baja a vzmax_baja; al centro mantiene la altura
    // proteccion de aterrizaje como la del DJI: cerca del suelo la bajada se limita (0,6 m/s por debajo de 3 m, 1,5 por debajo de 8)
    const agl = av.agl === undefined ? 100 : av.agl, bajaMax = Math.min(M.vzmax_baja, agl < 3 ? 0.6 : agl < 8 ? 1.5 : M.vzmax_baja);
    const vzObj = c.vz > 0 ? c.vz * M.vzmax_sube : c.vz * bajaMax;
    let T = av.motorRoto ? 0 : m * (G0 + F.kz * (vzObj - vzUp)) / Math.max(0.5, Math.cos(roll) * Math.cos(pitch));
    T = Math.max(0, Math.min(Tmax, T));
    // en el suelo: los motores al ralenti hasta que se pide subir; con la palanca abajo un rato, se paran (aterrizado)
    if (av.posado) {
      if (c.vz <= 0.05 || av.motorRoto) T = 0;
      if (T <= m * G0 * 1.02) {
        av.v = [0, 0, 0]; av.w = [0, 0, 0]; av.q = Cuat.desdeEuler(0, 0, yaw); av.p[2] = -(suelo + 0.02);
        av.T = T; av.gases = av.motorRoto ? 0 : 0.08; av.rpm = av.motorRoto ? 0 : 0.25 * pr.rpm_max; av.V = 0; av.g_carga = 1; av.alfa = 0; av.beta = 0; av.t += dt;
        av.Wh += (av.motorRoto ? 0 : 6) * dt / 3600;
        av.tParar = (c.vz < -0.3 || av.rth) && av.despegado ? av.tParar + dt : 0;   // RTH: al posarse para los motores
        if (av.tParar > 0.8 || (av.motorRoto && av.despegado)) av.p[2] = -(suelo - 0.05);    // posado y motores parados: el simulador lo da por aterrizado
        return [0, 0, 0];
      }
      av.posado = false;    // despega
    }
    // --- pares: angulos objetivo -> velocidades angulares objetivo -> par, con los topes de los motores ---
    const pObj = F.ka * (rollObj - roll), qObj = F.ka * (pitchObj - pitch), rObj = c.guinada * M.rmax_grados_s * D2R;
    const lim = (x, L) => Math.max(-L, Math.min(L, x));
    let Mx = lim(I.Ixx * F.kr * (pObj - w[0]), F.tau_max), My = lim(I.Iyy * F.kr * (qObj - w[1]), F.tau_max), Mz = lim(I.Izz * F.kr * (rObj - w[2]), F.tau_guinada);
    if (av.motorRoto) { Mx = My = Mz = 0; }
    // turbulencia que alabea (Entorno.rafagaAlabeo): el dron la nota y el controlador la corrige
    if (av.pg && !this.facil) Mx += I.Ixx * av.pg * 4;
    // --- fuerzas en ejes cuerpo: empuje hacia arriba, peso, resistencia con el viento (la mitad en fisica facil) ---
    const wb = Cuat.rot(Cuat.inv(q), this.facil ? viento.map(x => 0.5 * x) : viento);
    const va = [v[0] - wb[0], v[1] - wb[1], v[2] - wb[2]], Va = Math.hypot(...va), kd = 0.5 * rho * Va * this.calib.resistencia;
    const Fd = [-kd * F.cda_h * va[0], -kd * F.cda_h * va[1], -kd * F.cda_v * va[2]];
    const gb = Cuat.rot(Cuat.inv(q), [0, 0, G0]);
    const Fx = Fd[0] + m * gb[0], Fy = Fd[1] + m * gb[1], Fz = Fd[2] + m * gb[2] - T;
    // --- ecuaciones de Euler (sin producto de inercia) e integracion ---
    const dv = [Fx / m - (w[1] * v[2] - w[2] * v[1]), Fy / m - (w[2] * v[0] - w[0] * v[2]), Fz / m - (w[0] * v[1] - w[1] * v[0])];
    const Iw = [I.Ixx * w[0], I.Iyy * w[1], I.Izz * w[2]];
    const dw = [(Mx - (w[1] * Iw[2] - w[2] * Iw[1])) / I.Ixx, (My - (w[2] * Iw[0] - w[0] * Iw[2])) / I.Iyy, (Mz - (w[0] * Iw[1] - w[1] * Iw[0])) / I.Izz];
    for (let i = 0; i < 3; i++) { v[i] += dv[i] * dt; w[i] += dw[i] * dt; }
    const dq = Cuat.mul(q, [0, w[0], w[1], w[2]]);
    av.q = Cuat.norm([q[0] + 0.5 * dq[0] * dt, q[1] + 0.5 * dq[1] * dt, q[2] + 0.5 * dq[2] * dt, q[3] + 0.5 * dq[3] * dt]);
    const vn2 = Cuat.rot(av.q, v);
    for (let i = 0; i < 3; i++) av.p[i] += vn2[i] * dt;
    // --- suelo: toma suave (poco descenso, casi nivelado) -> posado; dura o inclinada -> la decide el simulador ---
    const agl2 = -av.p[2] - suelo;
    if (agl2 > 0.3) av.despegado = true;
    if (agl2 <= 0.02 && vn2[2] >= 0 && vn2[2] < 2.0 && Math.abs(roll) < 20 * D2R && Math.abs(pitch) < 20 * D2R && c.vz <= 0.05) {
      av.posado = true; av.v = [0, 0, 0]; av.w = [0, 0, 0]; av.q = Cuat.desdeEuler(0, 0, Cuat.euler(av.q)[2]); av.p[2] = -(suelo + 0.02);
    }
    // --- bateria (potencia inducida de los 4 rotores + electronica), revoluciones y lecturas ---
    const A4 = 4 * Math.PI * Math.pow(pr.D_m / 2, 2), P = Math.pow(T, 1.5) / Math.sqrt(2 * rho * A4) / 0.55 + 4;
    av.Wh += P * dt / 3600;
    av.T = T; av.gases = T / Tmax; av.rpm = Math.sqrt(T / Tmax) * pr.rpm_max;
    av.t += dt; av.V = Va; av.alfa = 0; av.beta = 0; av.perdida = 0; av.g_carga = T / (m * G0);
    return vn2;
  }
  bateriaPct(av) { return Math.max(0, 100 * (1 - av.Wh / this.propulsion.masa_bateria_Wh)); }
};

// ---- datos del dron, en JSON estricto (claves entre comillas, colores en decimal, sin comentarios dentro): el
// simulador de Godot los lee tal cual de este fichero (simulador_godot/scripts/datos_comunes.gd busca la linea de la constante DATOS
// y saca el objeto que empieza ahi). Todo menos la malla calculada (cuerpo, brazos, patas y rotores), que se anade abajo.
// fc es el controlador de vuelo: modos C/N/S del DJI Mini 4K (velocidad horizontal, ascenso, descenso, inclinacion
// maxima, giro y ganancia de velocidad -> aceleracion), altura de RTH, ganancias (altura, angulo -> giro, giro -> par),
// pares maximos de los motores (N m) y resistencia aerodinamica (CdA, m2) horizontal y vertical.
// colores: fuselaje 0xdcdcdc, ala 0x3a3a3a, estab 0x2f2f2f, moviles 0xd32f2f.
// malla.luces, como las del DJI Mini: en los brazos traseros verde (0x00e676) a la derecha y roja (0xff1744) a la
// izquierda (parpadeo lento) y un estrobo blanco (0xffffff) en la cola, para verlo desde el puesto del piloto.
(function () {
  const DATOS = {
    "id": "DJI_MINI", "nombre": "Cuadricóptero DJI Mini 4K", "tipo": "cuadricoptero",
    "descripcion": "Dron de 249 g con controlador de vuelo estabilizado y retención de posición, como el DJI Mini 4K: suelta las palancas y se queda quieto. Para practicar los mandos del DJI (modo 2) antes de volar el de verdad.",
    "ayuda": "Palanca izquierda: arriba y abajo sube y baja; izquierda y derecha gira sobre sí mismo. Palanca derecha: adelante, atrás y laterales. Con las palancas en el centro frena y se queda quieto. Conmutador C/N/S (tecla M) cambia el modo de vuelo; rueda del gimbal (Q/E) inclina la cámara. Botones de la app: despegar, volver a casa (H), foto y vídeo. Para aterrizar, pósalo despacio y mantén la palanca abajo (S) hasta que se paren los motores.",
    "caracteristicas": [["Masa en vuelo", "249 g"], ["Tamaño", "249 × 290 × 60 mm desplegado, hélices de 3 pulgadas"], ["Empuje máximo", "≈ 2 veces el peso (4,9 N)"],
                        ["Modos de vuelo", "C (Cine) 6 m/s · N (Normal) 10 m/s · S (Sport) 16 m/s"], ["Ascenso / descenso", "C 2 / 1,5 · N 3 / 3 · S 5 / 3,5 m/s"],
                        ["Inclinación máxima", "C 15° · N 25° · S 40°"], ["Giro", "C 60°/s · N 100°/s · S 200°/s"],
                        ["Cámara", "gimbal de 3 ejes, de −90° a +10°; foto y vídeo desde la app"], ["Volver a casa", "sube a 30 m, vuelve al punto de despegue y aterriza"],
                        ["Batería", "2S 2250 mAh, 17 Wh: unos 30 min de vuelo"], ["Mandos", "modo 2: izquierda gas y guiñada, derecha inclinación; conmutador C/N/S y rueda del gimbal"],
                        ["Controlador", "estabilizado con retención de posición y altura (como con GPS)"], ["Velocidad de pérdida", "0 m/s (no entra en pérdida)"]],
    "masa_kg": 0.249, "b_m": 0.25, "S_m2": 0.03, "c_m": 0.1, "inercia": { "Ixx": 0.0006, "Iyy": 0.0007, "Izz": 0.0012, "Ixz": 0 }, "cg_mm": [0, 0, 0],
    "propulsion": { "empuje_max_N": 4.9, "rpm_max": 16000, "D_m": 0.076, "masa_bateria_Wh": 17.3, "P_max_W": 110 },
    "fc": { "modos": { "C": { "vmax_ms": 6, "vzmax_sube": 2, "vzmax_baja": 1.5, "inclinacion_grados": 15, "rmax_grados_s": 60, "kv": 0.9 },
                       "N": { "vmax_ms": 10, "vzmax_sube": 3, "vzmax_baja": 3, "inclinacion_grados": 25, "rmax_grados_s": 100, "kv": 1.2 },
                       "S": { "vmax_ms": 16, "vzmax_sube": 5, "vzmax_baja": 3.5, "inclinacion_grados": 40, "rmax_grados_s": 200, "kv": 1.5 } },
            "rth_altura_m": 30, "kz": 3.5, "ka": 6, "kr": 25, "tau_max": 0.22, "tau_guinada": 0.03, "cda_h": 0.012, "cda_v": 0.03 },
    "mandos": { "expo": 0.3, "prof_max_grados": 25, "aleron_max_grados": 25, "timon_max_grados": 0, "servo_vel_grados_s": 400, "servo_tau_s": 0.02, "izq_der": "inclinación lateral (A/D: giro)" },
    "lanzamiento": { "vel_ms": 0, "cabeceo_grados": 0 }, "compensador_grados": 0,
    "colores": { "fuselaje": 14474460, "ala": 3815994, "estab": 3092271, "moviles": 13840175 },
    "malla": { "helice_r": 0.038, "helice": [0.095, 0.09, -0.018],
               "luces": [{ "p": [-0.095, 0.09, -0.012], "color": 58998, "patron": "lento" }, { "p": [-0.095, -0.09, -0.012], "color": 16717636, "patron": "lento" },
                         { "p": [-0.07, 0, -0.03], "color": 16777215, "patron": "estrobo" }] }
  };

  // ---- malla: cuerpo, brazos y patas (fuselaje, gris claro), motores y camara (estab, oscuro) y 4 rotores (helices) ----
  // (simulador_godot/scripts/datos_comunes.gd la construye igual: si se cambia aqui, hay que cambiarla alli)
  const V = { fuselaje: { v: [], i: [] }, estab: { v: [], i: [] } };
  /** Caja centrada en (cx, cy, cz), de lados sx, sy, sz, girada ang radianes sobre z. */
  function caja(parte, cx, cy, cz, sx, sy, sz, ang = 0) {
    const M = V[parte], b = M.v.length / 3, c = Math.cos(ang), s = Math.sin(ang);
    for (const [ix, iy, iz] of [[-1, -1, -1], [1, -1, -1], [1, 1, -1], [-1, 1, -1], [-1, -1, 1], [1, -1, 1], [1, 1, 1], [-1, 1, 1]]) {
      const x = ix * sx / 2, y = iy * sy / 2;
      M.v.push(cx + x * c - y * s, cy + x * s + y * c, cz + iz * sz / 2);
    }
    for (const f of [[0, 1, 2, 3], [4, 7, 6, 5], [0, 4, 5, 1], [1, 5, 6, 2], [2, 6, 7, 3], [3, 7, 4, 0]]) M.i.push(b + f[0], b + f[1], b + f[2], b + f[0], b + f[2], b + f[3]);
  }
  caja("fuselaje", 0, 0, 0, 0.14, 0.08, 0.05);                       // cuerpo
  caja("estab", 0.078, 0, 0.012, 0.025, 0.032, 0.03);                 // camara con su cardan, delante y abajo
  const brazos = [[0.095, 0.09], [0.095, -0.09], [-0.095, 0.09], [-0.095, -0.09]];
  for (const [x, y] of brazos) {
    caja("fuselaje", x * 0.62, y * 0.62, -0.004, 0.11, 0.012, 0.008, Math.atan2(y, x));   // brazo
    caja("estab", x, y, -0.008, 0.02, 0.02, 0.016);                                        // motor
    caja("estab", x * 0.5, y * 0.4, 0.03, 0.01, 0.01, 0.02);                               // pata
  }
  Object.assign(DATOS.malla, { fuselaje: V.fuselaje, estab: V.estab, helices: brazos.map(([x, y]) => [x, y, -0.018]) });
  Modelos.registrar(DATOS, ModeloCuadricoptero);
})();
