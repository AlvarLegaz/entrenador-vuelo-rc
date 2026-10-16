// Mini Dron HQ (cuadricoptero de 249 g) (249 g) para practicar los mandos del dron comercial antes de volar el de verdad.
// A diferencia de los aviones, aqui manda un CONTROLADOR DE VUELO como el del dron comercial (modo estabilizado con retencion
// de posicion y altura, como con GPS): la palanca derecha pide VELOCIDAD horizontal (adelante/atras, laterales), la
// izquierda velocidad vertical (arriba/abajo) y giro sobre si mismo (guinada). Con las palancas en el centro frena y se
// queda quieto en el sitio, tambien con viento (se inclina contra el). El controlador manda inclinaciones y pares a los
// motores con sus limites reales (inclinacion maxima, empuje maximo, par maximo) y el dron responde con su inercia,
// su resistencia aerodinamica y el viento: no es un "teleport", se nota el retardo al frenar y las rachas.
// Mandos del dron comercial (modo 2): palanca izquierda gas (velocidad vertical, con muelle) y guinada; derecha inclinacion.
// Modos de vuelo C / N / S (Cine, Normal, Sport) como el conmutador del mando: cambian velocidades, inclinacion y giro.
// Gimbal de 3 ejes: la camara va nivelada y su inclinacion (0 horizontal, -90 vertical) la mueve la rueda del mando.
// Despegue automatico (sube a 1,2 m y se queda), volver a casa (RTH: sube a 30 m, vuelve al punto de despegue y
// aterriza) y aterrizaje con la palanca abajo, como en la app del dron. Teclado: flechas inclinan (arriba = adelante),
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
    this.tempC = 15; this.B = Bateria.datos(this.propulsion);     // bateria Li-ion inteligente (js/bateria.js)
  }
  /** Masa, temperatura (densidad), empuje medido (gf, el maximo de los 4 motores) y factor de resistencia. */
  configurar({ masa_kg, cg_mm, temperatura, empuje_gf, resistencia }) {
    if (temperatura !== undefined) { this.rho = 101325 / (287.05 * (temperatura + 273.15)); this.tempC = temperatura; }
    if (empuje_gf) this.calib.empuje = empuje_gf / 1000 * G0 / this.propulsion.empuje_max_N;
    if (resistencia) this.calib.resistencia = resistencia;
    if (masa_kg) { this.masa_kg = masa_kg; const k = masa_kg / this.masa_diseno_kg; for (const n in this.inercia_diseno) this.inercia[n] = this.inercia_diseno[n] * k; }
  }
  /** En el suelo, motores parados ("en mano" para el simulador: L los arma). */
  estadoInicial() {
    return { p: [0, 0, -0.02], q: Cuat.desdeEuler(0, 0, 0), v: [0, 0, 0], w: [0, 0, 0], de: 0, dr: 0, da: 0, gases: 0, Wh: 0, asim: 0,
             estado: "en mano", t: 0, alfa: 0, beta: 0, V: 0, g_carga: 1, perdida: 0, T: 0, rpm: 0, motorRoto: false,
             posado: true, despegado: false, tParar: 0, cmd: { adelante: 0, derecha: 0, guinada: 0, vz: 0 },
             gimbal: -10, rth: null, despegueAuto: false, hold: null,
             bat: Bateria.nueva(this.B, this.tempC), sinBateria: false, avisoBat: "", batRth: false, batForzado: false };
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
    this._bateriaBaja(av);
    // cualquier palanca cancela el RTH y el despegue automatico (como en el dron comercial); el aterrizaje forzoso por
    // bateria critica no: se puede mover en horizontal para buscar sitio, pero sigue bajando
    if (av.batForzado) { av.rth = null; av.despegueAuto = false; obj.vz = Math.min(obj.vz, -0.6); }
    else if (Math.max(...Object.values(obj).map(Math.abs)) > 0.3) { av.rth = null; av.despegueAuto = false; }
    if (av.rth) this._rth(av, obj);
    else if (av.despegueAuto) { obj.adelante = obj.derecha = obj.guinada = 0; obj.vz = av.agl < 1.2 ? 0.5 : 0; if (av.agl >= 1.2) av.despegueAuto = false; }
    for (const k in obj) av.cmd[k] += Math.max(-10 * dt, Math.min(10 * dt, obj[k] - av.cmd[k]));
    av.gimbal = Math.max(-89, Math.min(10, av.gimbal + 45 * cl(mando.gimbal) * dt));      // rueda del gimbal: 45 grados/s, hasta -89 (a -90 la camara mira justo abajo y su "arriba" queda indefinido)
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
  /** Bateria baja como en el dron comercial (av.avisoBat lo cuenta al simulador): al 30 % avisa; cuando la carga justo
   *  alcanza para volver (la vuelta a 8 m/s con la subida y la bajada, un 30 % mas de lo que gasta ahora y un 15 % de reserva) vuelve
   *  a casa solo (una vez; con las palancas se cancela); al 10 % aterrizaje forzoso donde este. */
  _bateriaBaja(av) {
    if (av.estado !== "volando" || av.posado || !av.bat) return;
    const pct = this.bateriaPct(av);
    if (pct <= 10 && !av.batForzado) { av.batForzado = true; av.avisoBat = "critica"; return; }
    if (av.batForzado) return;
    const casa = this.casa || [0, 0], d = Math.hypot(casa[0] - av.p[0], casa[1] - av.p[1]), agl = av.agl === undefined ? 0 : av.agl, hR = this.fc.rth_altura_m;
    if (!av.batRth && d > 15) {
      const t = d / 8 + Math.max(0, hR - agl) / 3 + Math.max(agl, hR) / 1.5 + 10, Pw = av.bat.P > 1 ? av.bat.P : 40;
      const pctVuelta = 100 * 1.3 * Pw * t / 3600 / (Bateria.capacidad(this.B, av.bat) / 1000 * this.B.celdas * 3.7) + 15;   // volando gasta mas; llegar sobre el 10 % del forzoso
      if (pct <= pctVuelta) { av.batRth = true; av.avisoBat = "rth"; if (!av.rth) this.volverACasa(av); return; }
    }
    if (pct <= 30 && av.avisoBat === "") av.avisoBat = "baja";
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
    // bateria: el empuje maximo baja cuando la tension cae por debajo de la nominal (3,7 V por celda); agotada (una celda
    // por debajo de 2,9 V con carga), los motores se paran
    const Bt = this.B, eb = av.bat, Vb = Bateria.tension(Bt, eb), kV = Math.min(1, Vb / (Bt.celdas * 3.7));
    if (!av.sinBateria && av.estado === "volando" && Bateria.pct(Bt, eb) <= 0 && Bateria.celdaMin(Bt, eb) < 2.9) av.sinBateria = true;
    const parado = av.motorRoto || av.sinBateria;
    const Tmax = pr.empuje_max_N * this.calib.empuje * kV * kV, suelo = av.agl === undefined ? 0 : -av.p[2] - av.agl;
    const M = F.modos[this.modo] || F.modos.N, tilt = M.inclinacion_grados * D2R, c = av.cmd;
    if (parado) { c.vz = -1; }
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
    // proteccion de aterrizaje como la del dron comercial: cerca del suelo la bajada se limita (0,6 m/s por debajo de 3 m, 1,5 por debajo de 8)
    const agl = av.agl === undefined ? 100 : av.agl, bajaMax = Math.min(M.vzmax_baja, agl < 3 ? 0.6 : agl < 8 ? 1.5 : M.vzmax_baja);
    const vzObj = c.vz > 0 ? c.vz * M.vzmax_sube : c.vz * bajaMax;
    let T = parado ? 0 : m * (G0 + F.kz * (vzObj - vzUp)) / Math.max(0.5, Math.cos(roll) * Math.cos(pitch));
    T = Math.max(0, Math.min(Tmax, T));
    // en el suelo: los motores al ralenti hasta que se pide subir; con la palanca abajo un rato, se paran (aterrizado)
    if (av.posado) {
      if (c.vz <= 0.05 || parado) T = 0;
      if (T <= m * G0 * 1.02) {
        av.v = [0, 0, 0]; av.w = [0, 0, 0]; av.q = Cuat.desdeEuler(0, 0, yaw); av.p[2] = -(suelo + 0.02);
        av.T = T; av.gases = parado ? 0 : 0.08; av.rpm = parado ? 0 : 0.25 * pr.rpm_max; av.V = 0; av.g_carga = 1; av.alfa = 0; av.beta = 0; av.t += dt;
        Bateria.gastar(Bt, eb, parado ? 0 : 6, dt); av.Wh = eb.Wh;
        av.tParar = (c.vz < -0.3 || av.rth) && av.despegado ? av.tParar + dt : 0;   // RTH: al posarse para los motores
        if (av.tParar > 0.8 || (parado && av.despegado)) av.p[2] = -(suelo - 0.05);    // posado y motores parados: el simulador lo da por aterrizado
        return [0, 0, 0];
      }
      av.posado = false;    // despega
    }
    // --- pares: angulos objetivo -> velocidades angulares objetivo -> par, con los topes de los motores ---
    const pObj = F.ka * (rollObj - roll), qObj = F.ka * (pitchObj - pitch), rObj = c.guinada * M.rmax_grados_s * D2R;
    const lim = (x, L) => Math.max(-L, Math.min(L, x));
    let Mx = lim(I.Ixx * F.kr * (pObj - w[0]), F.tau_max), My = lim(I.Iyy * F.kr * (qObj - w[1]), F.tau_max), Mz = lim(I.Izz * F.kr * (rObj - w[2]), F.tau_guinada);
    if (parado) { Mx = My = Mz = 0; }
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
    Bateria.gastar(Bt, eb, P, dt); av.Wh = eb.Wh;
    av.T = T; av.gases = T / Tmax; av.rpm = Math.sqrt(T / Tmax) * pr.rpm_max;
    av.t += dt; av.V = Va; av.alfa = 0; av.beta = 0; av.perdida = 0; av.g_carga = T / (m * G0);
    return vn2;
  }
  bateriaPct(av) { return av.bat ? Bateria.pct(this.B, av.bat) : Math.max(0, 100 * (1 - av.Wh / this.propulsion.masa_bateria_Wh)); }
};

// ---- datos del dron, en JSON estricto (claves entre comillas, colores en decimal, sin comentarios dentro): el
// simulador de Godot los lee tal cual de este fichero (simulador_godot/scripts/datos_comunes.gd busca la linea de la constante DATOS
// y saca el objeto que empieza ahi). Todo menos la malla calculada (cuerpo, brazos, patas y rotores), que se anade abajo.
// fc es el controlador de vuelo: modos C/N/S del Mini Dron HQ (velocidad horizontal, ascenso, descenso, inclinacion
// maxima, giro y ganancia de velocidad -> aceleracion), altura de RTH, ganancias (altura, angulo -> giro, giro -> par),
// pares maximos de los motores (N m) y resistencia aerodinamica (CdA, m2) horizontal y vertical.
// colores: fuselaje 0xdcdcdc, ala 0x3a3a3a, estab 0x2f2f2f, moviles 0xd32f2f.
// malla.luces, como las del Mini Dron HQ: en los brazos traseros verde (0x00e676) a la derecha y roja (0xff1744) a la
// izquierda (parpadeo lento) y un estrobo blanco (0xffffff) en la cola, para verlo desde el puesto del piloto.
(function () {
  const DATOS = {
    "id": "DJI_MINI", "nombre": "Mini Dron HQ", "tipo": "cuadricoptero", "categoria": "249 g, categoría abierta A1",
    "descripcion": "Dron de 249 g con controlador de vuelo estabilizado y retención de posición, como los drones comerciales de menos de 250 g: suelta las palancas y se queda quieto. Para practicar los mandos del dron comercial (modo 2) antes de volar el de verdad.",
    "ayuda": "Palanca izquierda: arriba y abajo sube y baja; izquierda y derecha gira sobre sí mismo. Palanca derecha: adelante, atrás y laterales. Con las palancas en el centro frena y se queda quieto. Conmutador C/N/S (tecla M) cambia el modo de vuelo; rueda del gimbal (Q/E) inclina la cámara. Botones de la app: despegar, volver a casa (H), foto y vídeo. Para aterrizar, pósalo despacio y mantén la palanca abajo (S) hasta que se paren los motores.",
    "caracteristicas": [["Masa en vuelo", "249 g"], ["Tamaño", "249 × 290 × 60 mm desplegado, hélices de 3 pulgadas"], ["Empuje máximo", "≈ 2 veces el peso (4,9 N)"],
                        ["Modos de vuelo", "C (Cine) 6 m/s · N (Normal) 10 m/s · S (Sport) 16 m/s"], ["Ascenso / descenso", "C 2 / 1,5 · N 3 / 3 · S 5 / 3,5 m/s"],
                        ["Inclinación máxima", "C 15° · N 25° · S 40°"], ["Giro", "C 60°/s · N 100°/s · S 200°/s"],
                        ["Cámara", "gimbal de 3 ejes, de −89° a +10°; foto y vídeo desde la app"], ["Volver a casa", "sube a 30 m, vuelve al punto de despegue y aterriza"],
                        ["Batería", "2S 2250 mAh, 17 Wh: unos 30 min de vuelo"], ["Mandos", "modo 2: izquierda gas y guiñada, derecha inclinación; conmutador C/N/S y rueda del gimbal"],
                        ["Controlador", "estabilizado con retención de posición y altura (como con GPS)"], ["Velocidad de pérdida", "0 m/s (no entra en pérdida)"]],
    "masa_kg": 0.249, "b_m": 0.25, "S_m2": 0.03, "c_m": 0.1, "inercia": { "Ixx": 0.0006, "Iyy": 0.0007, "Izz": 0.0012, "Ixz": 0 }, "cg_mm": [0, 0, 0],
    "propulsion": { "empuje_max_N": 4.9, "rpm_max": 16000, "D_m": 0.076, "masa_bateria_Wh": 17.3, "P_max_W": 110,
                    "bateria": { "quimica": "liion", "celdas": 2, "capacidad_mAh": 2250, "R_ohm": 0.06, "masa_kg": 0.086 } },
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

// =====================================================================
//  MODELO 3D DETALLADO del Mini Dron HQ para la web: traduccion LITERAL de simulador_godot/scripts/modelo_dji_3d.gd
//  (ModeloDJI3D): la misma geometria parametrica (carcasa, cuerpo, brazos y patas por secciones superelipticas con
//  tapas redondeadas; motores, objetivo, sensores y botones por revolucion; palas con perfil NACA, cuerda, torsion y
//  flecha), los mismos materiales PBR (plastico satinado con barniz, metal de las campanas, cristal del objetivo, goma
//  de los pies) y el mismo sombreado de la carcasa (rejillas de ventilacion, tomas de aire, juntas) y del disco de
//  desenfoque de las helices. Si se cambia alli, hay que cambiarlo aqui. construirAvion (js/visor.js) lo usa en lugar
//  de la malla de cajas cuando el avion es un cuadricoptero.
//  Ejes cuerpo NED (x adelante, y derecha, z abajo; metros; origen en el CG = centro de los motores).
// =====================================================================
(function () {
  const TAU = 2 * Math.PI, SUELO = 0.020;
  const MOTORES = [[0.064, 0.090, -0.0355, -1], [0.064, -0.090, -0.0355, 1], [-0.064, 0.085, -0.0170, 1], [-0.064, -0.085, -0.0170, -1]];
  const R_HELICE = 0.0595, R0_HELICE = 0.0055, PASO = 0.066, RPM_PALAS = 250, RPM_DISCO = 1100;
  const G_GUI = [0.0590, 0, -0.0080], G_ALA = [0.0592, 0, 0.0015], G_CAB = [0.0692, 0, 0.0015];
  const C_CARCASA = 0xe3e3e0, C_CUERPO = 0xc4c5c4, C_BRAZO = 0xcdcecc, C_HELICE = 0x3a3b3e, C_PUNTA = 0xf0782a;

  // ---- vectores como [x, y, z] ----
  const sum = (a, b) => [a[0] + b[0], a[1] + b[1], a[2] + b[2]], res = (a, b) => [a[0] - b[0], a[1] - b[1], a[2] - b[2]];
  const mul = (a, k) => [a[0] * k, a[1] * k, a[2] * k], dot = (a, b) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
  const cruz = (a, b) => [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]];
  const largo2 = a => dot(a, a), unit = a => { const l = Math.sqrt(dot(a, a)); return l > 0 ? mul(a, 1 / l) : [0, 0, 0]; };
  const lerp = (a, b, t) => a + (b - a) * t, clamp = (x, a, b) => Math.max(a, Math.min(b, x));
  const smooth = (a, b, x) => { const t = clamp((x - a) / (b - a), 0, 1); return t * t * (3 - 2 * t); };
  const lineal = hex => { const c = new THREE.Color(hex); return [c.r, c.g, c.b]; };      // sRGB -> lineal (ColorManagement)
  const casi = (a, b) => Math.abs(a[0] - b[0]) < 1e-7 && Math.abs(a[1] - b[1]) < 1e-7 && Math.abs(a[2] - b[2]) < 1e-7;

  /** Acumulador de una superficie (un material): vertices, normales, color (o marcas) de vertice e indices. */
  class Acum {
    constructor() { this.pos = []; this.nor = []; this.col = []; this.idx = []; }
    static igual(A, B) { return casi(A[0], B[0]) && casi(A[Math.floor(A.length / 2)], B[Math.floor(B.length / 2)]) && casi(A[Math.floor(A.length / 4)], B[Math.floor(B.length / 4)]); }
    static centro(A) { let c = [0, 0, 0]; for (const p of A) c = sum(c, p); return mul(c, 1 / A.length); }
    /** Rejilla de filas cerradas (anillos) del mismo numero de puntos. Normales por diferencias centrales (dos filas
     *  iguales seguidas = arista viva), hacia fuera; en los polos, la media de las de la fila vecina. */
    rejilla(P, c, cols = []) {
      const nf = P.length, nc = P[0].length, base = this.pos.length / 3, N = [];
      for (let i = 0; i < nf; i++) {
        const ip = i > 0 && !Acum.igual(P[i - 1], P[i]) ? i - 1 : i, inx = i < nf - 1 && !Acum.igual(P[i], P[i + 1]) ? i + 1 : i;
        const F = P[i], Fp = P[ip], Fn = P[inx], fila = [];
        for (let j = 0; j < nc; j++) fila.push(cruz(res(F[(j + 1) % nc], F[(j - 1 + nc) % nc]), res(Fn[j], Fp[j])));
        N.push(fila);
      }
      let suma = 0;
      for (let i = 0; i < nf; i++) { const F = P[i], cen = Acum.centro(F); for (let j = 0; j < nc; j++) suma += dot(unit(N[i][j]), res(F[j], cen)); }
      const signo = suma < 0 ? -1 : 1;
      for (let i = 0; i < nf; i++) for (let j = 0; j < nc; j++) N[i][j] = largo2(N[i][j]) > 1e-24 ? unit(mul(N[i][j], signo)) : [0, 0, 0];
      for (let i = 0; i < nf; i++) {                  // polos
        if (N[i][0][0] !== 0 || N[i][0][1] !== 0 || N[i][0][2] !== 0) continue;
        const vec = i > 0 ? N[i - 1] : N[i + 1]; let m = [0, 0, 0]; for (const v of vec) m = sum(m, v);
        m = unit(m); for (let j = 0; j < nc; j++) N[i][j] = m;
      }
      for (let i = 0; i < nf; i++) {
        const ci = i < cols.length ? cols[i] : c;
        for (let j = 0; j < nc; j++) { this.pos.push(...P[i][j]); this.nor.push(...N[i][j]); this.col.push(...ci); }
      }
      for (let i = 0; i < nf - 1; i++) {
        if (Acum.igual(P[i], P[i + 1])) continue;
        for (let j = 0; j < nc; j++) {
          const a = base + i * nc + j, b = base + (i + 1) * nc + j, cc = base + (i + 1) * nc + (j + 1) % nc, d = base + i * nc + (j + 1) % nc;
          this.tri(a, b, cc); this.tri(a, cc, d);
        }
      }
    }
    tri(a, b, c) {
      const p = k => [this.pos[3 * k], this.pos[3 * k + 1], this.pos[3 * k + 2]], n = k => [this.nor[3 * k], this.nor[3 * k + 1], this.nor[3 * k + 2]];
      const fn = cruz(res(p(b), p(a)), res(p(c), p(a)));          // cara delantera de Three (sentido antihorario)
      if (largo2(fn) < 1e-22) return;
      if (dot(fn, sum(sum(n(a), n(b)), n(c))) < 0) this.idx.push(a, c, b); else this.idx.push(a, b, c);
    }
  }

  // ---- geometria parametrica ----
  /** Seccion superelíptica (exponente n) en el plano (l, u) alrededor de o: semiancho w, hacia arriba hu, hacia abajo hd. */
  function seccion(o, l, u, w, hu, hd, n, nc) {
    const f = [], e = 2 / n;
    for (let j = 0; j < nc; j++) {
      const a = TAU * j / nc, c = Math.cos(a), s = Math.sin(a);
      f.push(sum(sum(o, mul(l, Math.sign(c) * Math.pow(Math.abs(c), e) * w)), mul(u, Math.sign(s) * Math.pow(Math.abs(s), e) * (s > 0 ? hu : hd))));
    }
    return f;
  }
  /** Pieza alargada: estaciones [punto, semiancho, alto arriba, alto abajo] a lo largo de una linea, con tapas redondeadas. */
  function loft(acum, est, n, tapa0, tapa1, arriba = [0, 0, -1], nc = 32, m0 = 2, m1 = 2, col = [0, 0, 0], nt = 6) {
    const k = est.length, filas = [], T = [];
    for (let i = 0; i < k; i++) T.push(unit(res(est[Math.min(i + 1, k - 1)][0], est[Math.max(i - 1, 0)][0])));
    const marco = t => { const l = unit(cruz(arriba, t)); return [l, cruz(t, l)]; };
    if (tapa0 > 0) {
      const fr = marco(T[0]);
      for (let q = nt; q > 0; q--) {
        const th = Math.PI / 2 * q / nt, esc = q === nt ? 0 : Math.pow(Math.max(Math.cos(th), 0), 2 / m0), dd = tapa0 * Math.pow(Math.sin(th), 2 / m0);
        filas.push(seccion(res(est[0][0], mul(T[0], dd)), fr[0], fr[1], est[0][1] * esc, est[0][2] * esc, est[0][3] * esc, n, nc));
      }
    }
    for (let i = 0; i < k; i++) { const fr = marco(T[i]); filas.push(seccion(est[i][0], fr[0], fr[1], est[i][1], est[i][2], est[i][3], n, nc)); }
    if (tapa1 > 0) {
      const fr = marco(T[k - 1]);
      for (let q = 1; q <= nt; q++) {
        const th = Math.PI / 2 * q / nt, esc = q === nt ? 0 : Math.pow(Math.max(Math.cos(th), 0), 2 / m1), dd = tapa1 * Math.pow(Math.sin(th), 2 / m1);
        filas.push(seccion(sum(est[k - 1][0], mul(T[k - 1], dd)), fr[0], fr[1], est[k - 1][1] * esc, est[k - 1][2] * esc, est[k - 1][3] * esc, n, nc));
      }
    }
    acum.rejilla(filas, col);
  }
  /** Pieza de revolucion alrededor de eje desde o: perfil [[radio, altura], ...]; un punto repetido = arista viva. */
  function torno(acum, o, eje, perfil, nc = 24, col = [0, 0, 0]) {
    eje = unit(eje);
    const ref = Math.abs(eje[0]) < 0.9 ? [1, 0, 0] : [0, 1, 0], u = unit(cruz(eje, ref)), v = cruz(eje, u), filas = [];
    for (const p of perfil) {
      const fila = [];
      for (let j = 0; j < nc; j++) { const a = TAU * j / nc; fila.push(sum(sum(o, mul(eje, p[1])), mul(sum(mul(u, Math.cos(a)), mul(v, Math.sin(a))), p[0]))); }
      filas.push(fila);
    }
    acum.rejilla(filas, col);
  }
  function interp(xs, tabla, x) {       // Catmull-Rom sobre una tabla
    const n = xs.length;
    if (x <= xs[0]) return tabla[0];
    if (x >= xs[n - 1]) return tabla[n - 1];
    let i = 0; while (x > xs[i + 1]) i++;
    const t = (x - xs[i]) / (xs[i + 1] - xs[i]), p0 = tabla[Math.max(i - 1, 0)], p1 = tabla[i], p2 = tabla[i + 1], p3 = tabla[Math.min(i + 2, n - 1)];
    return 0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t + (-p0 + 3 * p1 - 3 * p2 + p3) * t * t * t);
  }
  const bezier = (a, b, c, t) => { const ab = sum(a, mul(res(b, a), t)), bc = sum(b, mul(res(c, b), t)); return sum(ab, mul(res(bc, ab), t)); };

  // ---- carcasa superior y cuerpo inferior ----
  const CX = [-0.050, -0.040, -0.025, -0.005, 0.015, 0.035, 0.050, 0.062, 0.070];
  const C_ANCHO = [0.0228, 0.0250, 0.0275, 0.0300, 0.0311, 0.0313, 0.0311, 0.0304, 0.0294];
  const C_TECHO = [-0.0265, -0.0288, -0.0304, -0.0310, -0.0304, -0.0284, -0.0258, -0.0228, -0.0205];
  const C_LABIO = [-0.0180, -0.0177, -0.0174, -0.0171, -0.0168, -0.0165, -0.0162, -0.0159, -0.0156];
  const BX = [-0.047, -0.035, -0.015, 0.010, 0.030, 0.042, 0.052];
  const B_ANCHO = [0.0190, 0.0218, 0.0246, 0.0262, 0.0262, 0.0252, 0.0238];
  const B_PANZA = [0.0042, 0.0058, 0.0064, 0.0064, 0.0054, 0.0035, -0.0005];
  function cuerpo(f) {
    let est = [];
    for (let k = 0; k < 25; k++) {
      const x = lerp(CX[0], CX[CX.length - 1], k / 24), zc = interp(CX, C_LABIO, x);
      est.push([[x, 0, zc], interp(CX, C_ANCHO, x), zc - interp(CX, C_TECHO, x), 0.0034]);
    }
    loft(f.casco, est, 3.4, 0.0065, 0.0115, [0, 0, -1], 64, 3.2, 3.4, [1, 0, 0], 9);
    est = [];
    for (let k = 0; k < 17; k++) {
      const x = lerp(BX[0], BX[BX.length - 1], k / 16), bot = interp(BX, B_PANZA, x), top = -0.0225, zc = (top + bot) / 2;
      est.push([[x, 0, zc], interp(BX, B_ANCHO, x), zc - top, bot - zc]);
    }
    loft(f.casco, est, 4.0, 0.0060, 0.0060, [0, 0, -1], 56, 3.2, 3.0, [0, 1, 0], 8);
    // extremo de la bateria: boton y 4 luces de carga
    torno(f.oscuro, [-0.0528, -0.0105, -0.0060], [-1, 0, 0], [[0, 0], [0.0023, 0], [0.0023, 0], [0.0023, 0.0012], [0.0018, 0.0016], [0, 0.0017]], 16);
    for (let k = 0; k < 4; k++) torno(f.led, [-0.0531, -0.0030 + 0.0040 * k, -0.0060], [-1, 0, 0], [[0, 0], [0.0007, 0], [0.0007, 0.0009], [0, 0.0011]], 8);
    // lentes de las luces: en los motores traseros y en la cola
    for (const lado of [1, -1]) {
      const dir = [-0.6, 0.8 * lado, 0];
      torno(f.led, sum([-0.064, 0.085 * lado, -0.0050], mul(dir, 0.0068)), dir, [[0, 0], [0.0024, 0], [0.0024, 0.0012], [0, 0.0018]], 12);
    }
    torno(f.led, [-0.0535, 0, -0.0125], [-1, 0, 0], [[0, 0], [0.0034, 0], [0.0034, 0], [0.0034, 0.0010], [0, 0.0014]], 14);
    // panza: sensores de vision hacia abajo, ToF y luz auxiliar
    for (const y of [-0.0085, 0.0085]) {
      torno(f.oscuro, [0.022, y, 0.0058], [0, 0, 1], [[0, 0], [0.0040, 0], [0.0040, 0], [0.0040, 0.0010], [0.0032, 0.0012], [0.0032, 0.0012], [0, 0.0008]], 18);
      torno(f.sensor, [0.022, y, 0.0064], [0, 0, 1], [[0, 0], [0.0025, 0], [0.0017, 0.0007], [0, 0.0009]], 16);
    }
    torno(f.sensor, [0.006, 0, 0.0062], [0, 0, 1], [[0, 0], [0.0028, 0], [0.0028, 0], [0.0028, 0.0009], [0, 0.0010]], 14);
    torno(f.led, [-0.004, 0, 0.0062], [0, 0, 1], [[0, 0], [0.0022, 0], [0.0022, 0], [0.0022, 0.0009], [0, 0.0011]], 12);
    // puerto USB-C a un lado de la trasera
    loft(f.oscuro, [[[-0.0440, -0.0205, -0.0080], 0.0012, 0.0016, 0.0016], [[-0.0395, -0.0222, -0.0080], 0.0012, 0.0016, 0.0016]], 4.0, 0.0006, 0.0006, [0, 0, -1], 16, 2.0, 2.0, [0, 0, 0], 3);
  }

  // ---- brazos ----
  function brazoDelantero(f, lado) {
    const a = [0.042, 0.022 * lado, -0.0100], c = [0.064, 0.090 * lado, -0.0195], b = [0.056, 0.054 * lado, -0.0120], est = [];
    for (let k = 0; k < 10; k++) { const t = k / 9; est.push([bezier(a, b, c, t), lerp(0.0076, 0.0062, t), lerp(0.0036, 0.0033, t), lerp(0.0036, 0.0033, t)]); }
    loft(f.casco, est, 3.6, 0, 0, [0, 0, -1], 28);
    torno(f.casco, [0.0445, 0.0240 * lado, -0.0040], [0, 0, -1], [[0, 0], [0.0050, 0], [0.0064, 0.0009], [0.0068, 0.0030], [0.0068, 0.0092], [0.0060, 0.0106], [0, 0.0110]], 24);   // bisagra
    torno(f.casco, [0.064, 0.090 * lado, -0.0200], [0, 0, -1], [[0, 0], [0.0068, 0], [0.0078, 0.0030], [0.0084, 0.0062], [0.0085, 0.0075], [0.0085, 0.0075], [0.0076, 0.0080], [0, 0.0080]], 28);   // asiento del motor
    const pe = [];                // pata: de seccion ovalada, algo abierta hacia afuera
    for (let k = 0; k < 8; k++) {
      const t = k / 7, p = [lerp(0.0640, 0.0628, t), lado * lerp(0.0900, 0.0950, t * t), lerp(-0.0215, 0.0172, t)];
      pe.push([p, lerp(0.0050, 0.0036, t), lerp(0.0085, 0.0056, t), lerp(0.0085, 0.0056, t)]);
    }
    loft(f.casco, pe, 3.4, 0, 0, [1, 0, 0], 24);
    loft(f.goma, [[[0.0628, 0.0950 * lado, 0.0170], 0.0037, 0.0057, 0.0057], [[0.0628, 0.0950 * lado, 0.0186], 0.0036, 0.0055, 0.0055]], 3.4, 0, 0.0014, [1, 0, 0], 24, 2.0, 3.0, [0, 0, 0], 4);
  }
  function brazoTrasero(f, lado) {
    const a = [-0.026, 0.020 * lado, -0.0125], c = [-0.064, 0.085 * lado, -0.0040], b = [-0.044, 0.050 * lado, -0.0100], est = [];
    for (let k = 0; k < 10; k++) { const t = k / 9; est.push([bezier(a, b, c, t), lerp(0.0072, 0.0058, t), lerp(0.0035, 0.0032, t), lerp(0.0035, 0.0032, t)]); }
    loft(f.casco, est, 3.6, 0, 0, [0, 0, -1], 28);
    torno(f.casco, [-0.0262, 0.0215 * lado, -0.0070], [0, 0, -1], [[0, 0], [0.0050, 0], [0.0062, 0.0009], [0.0066, 0.0028], [0.0066, 0.0082], [0.0058, 0.0096], [0, 0.0100]], 24);
    torno(f.casco, [-0.064, 0.085 * lado, SUELO - 0.0016], [0, 0, -1],
      [[0, 0], [0.0050, 0], [0.0058, 0.0010], [0.0060, 0.0040], [0.0062, 0.0150], [0.0074, 0.0210], [0.0084, 0.0258], [0.0085, 0.0266], [0.0085, 0.0266], [0.0076, 0.0272], [0, 0.0272]], 28);
    torno(f.goma, [-0.064, 0.085 * lado, SUELO], [0, 0, -1], [[0, 0], [0.0040, 0], [0.0050, 0.0007], [0.0052, 0.0020], [0, 0.0020]], 20);
  }
  function motor(f, m) {
    const zp = m[2], o = [m[0], m[1], zp + 0.0080];
    torno(f.metal, o, [0, 0, -1], [[0, 0], [0.0064, 0], [0.0064, 0], [0.0069, 0.0006], [0.0070, 0.0040], [0.0067, 0.0058], [0.0061, 0.0064], [0.0061, 0.0064], [0, 0.0064]], 28);
    torno(f.goma, sum(o, [0, 0, -0.0010]), [0, 0, -1], [[0.00700, 0], [0.00706, 0.0004], [0.00706, 0.0016], [0.00700, 0.0020]], 28);
    torno(f.buje, [m[0], m[1], zp + 0.0016], [0, 0, -1], [[0, 0], [0.0062, 0], [0.0066, 0.0008], [0.0066, 0.0024], [0.0058, 0.0031], [0, 0.0032]], 24);
  }

  // ---- gimbal y camara ----
  function gimbal(g1, g2, g3) {
    torno(g1.casco, sum(G_GUI, [0, 0, -0.0030]), [0, 0, 1], [[0, 0], [0.0056, 0], [0.0060, 0.0010], [0.0060, 0.0040], [0.0054, 0.0050], [0, 0.0052]], 24);
    loft(g1.oscuro, [[sum(G_GUI, [-0.0012, 0, 0.0018]), 0.0040, 0.0024, 0.0024], [sum(G_ALA, [-0.0030, 0, -0.0010]), 0.0040, 0.0024, 0.0024]], 3.0, 0, 0.0016, [1, 0, 0], 20);
    torno(g2.oscuro, sum(G_ALA, [-0.0040, 0, 0]), [1, 0, 0], [[0, 0], [0.0046, 0], [0.0052, 0.0008], [0.0052, 0.0036], [0.0046, 0.0044], [0, 0.0046]], 24);
    const ra = [], pa = G_ALA, pb = [G_ALA[0], -0.0150, G_ALA[2]], pc = [G_CAB[0] - 0.0015, -0.0150, G_CAB[2]];
    for (let k = 0; k < 7; k++) ra.push([bezier(pa, pb, pc, k / 6), 0.0015, 0.0040, 0.0040]);
    loft(g2.oscuro, ra, 3.0, 0, 0.0012, [0, 0, -1], 20);
    torno(g2.oscuro, [G_CAB[0], -0.0174, G_CAB[2]], [0, 1, 0], [[0, 0], [0.0048, 0], [0.0055, 0.0008], [0.0055, 0.0040], [0.0050, 0.0050], [0, 0.0052]], 24);
    const cx = G_CAB[0], cz = G_CAB[2];
    loft(g3.camara, [[[cx - 0.0062, 0, cz], 0.0106, 0.0086, 0.0086], [[cx + 0.0068, 0, cz], 0.0106, 0.0086, 0.0086]], 4.5, 0.0018, 0.0008, [0, 0, -1], 44, 2.6, 3.0, [0, 0, 0], 6);
    loft(g3.frontal, [[[cx + 0.0068, 0, cz], 0.0088, 0.0076, 0.0076], [[cx + 0.0082, 0, cz], 0.0086, 0.0074, 0.0074]], 5.0, 0, 0.0006, [0, 0, -1], 44, 3.0, 3.0, [0, 0, 0], 4);
    torno(g3.camara, [cx, -0.0106, cz], [0, -1, 0], [[0, 0], [0.0040, 0], [0.0040, 0.0016], [0.0034, 0.0022], [0, 0.0024]], 20);
    const lo = [cx + 0.0087, 0, cz];
    torno(g3.aro, lo, [1, 0, 0], [[0.0062, -0.0006], [0.0062, 0.0006], [0.0058, 0.0012], [0.0058, 0.0012], [0.0049, 0.0012], [0.0049, 0.0012], [0.0047, 0.0004]], 44);
    torno(g3.oscuro, lo, [1, 0, 0], [[0.0047, 0.0004], [0.0042, 0.0002], [0.0042, 0.0002], [0.0042, 0.0005]], 44);
    torno(g3.vidrio, lo, [1, 0, 0], [[0.0042, 0.0005], [0.0032, 0.0009], [0.0016, 0.0011], [0, 0.0012]], 44);
  }

  // ---- pala de helice ----
  function cuerda(xi) {
    let c = 0.0072 + 0.0064 * smooth(0, 0.3, xi) - 0.0034 * smooth(0.3, 0.9, xi);
    if (xi > 0.8) c *= Math.sqrt(Math.max(0, 1 - Math.pow((xi - 0.8) / 0.2, 2)));
    return c;
  }
  const naca = u => 5 * (0.2969 * Math.sqrt(u) - 0.126 * u - 0.3516 * u * u + 0.2843 * u * u * u - 0.1036 * u * u * u * u);
  /** Una pala en ejes del rotor (z abajo), a lo largo de +x girada giro sobre z; s = sentido de giro. */
  function pala(acum, s, giro) {
    const filas = [], cols = [], nfil = 24, M = 10, cg = Math.cos(giro), sg = Math.sin(giro), rot = v => [v[0] * cg - v[1] * sg, v[0] * sg + v[1] * cg, v[2]];
    const cH = lineal(C_HELICE), cP = lineal(C_PUNTA);
    for (let k = 0; k <= nfil; k++) {
      const xi = 1 - Math.pow(1 - k / nfil, 1.5), r = R0_HELICE + (R_HELICE - R0_HELICE) * xi, c = cuerda(xi);
      const beta = Math.min(Math.atan(PASO / (TAU * r)), 30 * Math.PI / 180), esp = 0.12 - 0.065 * xi, flecha = 0.0060 * xi * xi;
      const d = [0, s * Math.cos(beta), -Math.sin(beta)], nn = [0, -s * Math.sin(beta), -Math.cos(beta)], centro = [r, -s * flecha, -0.0005 * xi], fila = [];
      for (let j = 0; j < M; j++) { const u = (1 - Math.cos(Math.PI * j / (M - 1))) / 2; fila.push(rot(sum(sum(centro, mul(d, (0.35 - u) * c)), mul(nn, c * (0.16 * u * (1 - u) + esp * naca(u)))))); }
      for (let j = M - 2; j > 0; j--) { const u = (1 - Math.cos(Math.PI * j / (M - 1))) / 2; fila.push(rot(sum(sum(centro, mul(d, (0.35 - u) * c)), mul(nn, c * (0.16 * u * (1 - u) - esp * naca(u)))))); }
      filas.push(fila); cols.push(xi > 0.895 ? cP : cH);
    }
    acum.rejilla(filas, [0, 0, 0], cols);
  }

  // ---- mallas (una vez, compartidas) ----
  function nuevo(ks) { const o = {}; for (const k of ks) o[k] = new Acum(); return o; }
  function mallas() {
    if (mallas.c) return mallas.c;
    const f = nuevo(["casco", "oscuro", "metal", "goma", "sensor", "led", "buje"]);
    cuerpo(f);
    for (const lado of [1, -1]) { brazoDelantero(f, lado); brazoTrasero(f, lado); }
    for (const m of MOTORES) motor(f, m);
    const g1 = nuevo(["casco", "oscuro"]), g2 = nuevo(["oscuro"]), g3 = nuevo(["camara", "frontal", "aro", "vidrio", "oscuro"]);
    gimbal(g1, g2, g3);
    const palas = {};
    for (const s of [1, -1]) {
      const p = nuevo(["palas", "tornillo"]);
      pala(p.palas, s, 0); pala(p.palas, s, Math.PI);
      for (let k = 0; k < 2; k++) {
        const a = Math.PI * k + 0.35 * s;
        torno(p.tornillo, [Math.cos(a) * 0.0040, Math.sin(a) * 0.0040, -0.0016], [0, 0, -1], [[0, 0], [0.0013, 0], [0.0013, 0], [0.0013, 0.0005], [0.0010, 0.0009], [0, 0.0010]], 10);
      }
      palas[s] = p;
    }
    // disco de desenfoque: anillo en el plano del rotor
    const dpos = [], didx = [], n = 64;
    for (let j = 0; j < n; j++) { const a = TAU * j / n; dpos.push(Math.cos(a) * R0_HELICE * 0.9, Math.sin(a) * R0_HELICE * 0.9, 0, Math.cos(a) * R_HELICE, Math.sin(a) * R_HELICE, 0); }
    for (let j = 0; j < n; j++) { const a = 2 * j, b = 2 * j + 1, c = 2 * ((j + 1) % n), d = c + 1; didx.push(a, b, c, b, d, c); }
    const disco = new THREE.BufferGeometry(); disco.setAttribute("position", new THREE.Float32BufferAttribute(dpos, 3));
    disco.setAttribute("normal", new THREE.Float32BufferAttribute(new Array(dpos.length).fill(0).map((_, i) => i % 3 === 2 ? -1 : 0), 3)); disco.setIndex(didx);
    const geo = A => { const g = new THREE.BufferGeometry(); g.setAttribute("position", new THREE.Float32BufferAttribute(A.pos, 3)); g.setAttribute("normal", new THREE.Float32BufferAttribute(A.nor, 3));
                       g.setAttribute("color", new THREE.Float32BufferAttribute(A.col, 3)); g.setIndex(A.idx); g.computeBoundingSphere(); return g; };
    const geos = o => Object.fromEntries(Object.entries(o).filter(([, a]) => a.idx.length).map(([k, a]) => [k, geo(a)]));
    return (mallas.c = { fijo: geos(f), g_guinada: geos(g1), g_alabeo: geos(g2), g_cabeceo: geos(g3), palas: { 1: geos(palas[1]), "-1": geos(palas[-1]) }, disco });
  }

  // ---- materiales ----
  function entorno() {          // reflejos (como el del FPV): cielo, horizonte y suelo
    if (entorno.tex) return entorno.tex;
    const cv = document.createElement("canvas"); cv.width = 256; cv.height = 128;
    const g = cv.getContext("2d"), gr = g.createLinearGradient(0, 0, 0, 128);
    gr.addColorStop(0, "#9fb9d6"); gr.addColorStop(0.47, "#eef2f6"); gr.addColorStop(0.53, "#8a8076"); gr.addColorStop(1, "#4a423b");
    g.fillStyle = gr; g.fillRect(0, 0, 256, 128); g.fillStyle = "#ffffff"; g.fillRect(40, 18, 46, 20); g.fillRect(170, 26, 20, 14);
    const t = new THREE.CanvasTexture(cv); t.mapping = THREE.EquirectangularReflectionMapping; t.colorSpace = THREE.SRGBColorSpace;
    return (entorno.tex = t);
  }
  const std = (c, rug, met, barniz, extra) => new THREE.MeshPhysicalMaterial(Object.assign({ color: c, roughness: rug, metalness: met, clearcoat: barniz, clearcoatRoughness: 0.3, envMap: entorno() }, extra || {}));
  /** Plastico gris satinado con barniz ligero (SHADER_CASCO de Godot). Marcas de vertice (atributo color): r = 1
   *  carcasa superior (rejillas de ventilacion detras y junta de la tapa de la bateria), g = 1 cuerpo inferior (tomas
   *  de aire, rejilla de la panza y extremo de la bateria), resto brazos. */
  function materialCasco(col) {
    const m = std(0xffffff, 0.42, 0, 0.25);
    const u = { uCarcasa: { value: new THREE.Color(col.carcasa) }, uCuerpo: { value: new THREE.Color(col.cuerpo) }, uBrazo: { value: new THREE.Color(col.brazo) }, uOscuro: { value: new THREE.Color(0.0222, 0.0234, 0.0247) } };
    m.onBeforeCompile = sh => {
      Object.assign(sh.uniforms, u);
      sh.vertexShader = sh.vertexShader.replace("#include <common>", "#include <common>\nattribute vec3 color;\nvarying vec3 vLp;\nvarying vec3 vLn;\nvarying vec2 vMarca;")
        .replace("#include <begin_vertex>", "#include <begin_vertex>\nvLp = position; vLn = normal; vMarca = color.rg;");
      sh.fragmentShader = sh.fragmentShader.replace("#include <common>", `#include <common>
uniform vec3 uCarcasa; uniform vec3 uCuerpo; uniform vec3 uBrazo; uniform vec3 uOscuro;
varying vec3 vLp; varying vec3 vLn; varying vec2 vMarca;
float dj_linea(float d, float ancho, float fw0) { float fw = max(fw0, 1e-7); return (1.0 - smoothstep(ancho * 0.5, ancho * 0.5 + fw, abs(d))) * clamp(ancho / fw, 0.0, 1.0); }
float dj_caja(vec2 p, vec2 b, float r) { vec2 q = abs(p) - b + vec2(r); return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - r; }
float dj_ranuras(float t, float periodo, float ancho) { float d = (fract(t / periodo) - 0.5) * periodo; return dj_linea(d, ancho, fwidth(t)); }
float dj_dentro(vec2 p, vec2 b, float r) { float d = dj_caja(p, b, r); return 1.0 - smoothstep(-0.0002, 0.0002, d); }`)
        .replace("#include <color_fragment>", `#include <color_fragment>
vec3 dCol = uBrazo; float dRug = 0.42; float dHueco = 0.0; float dJunta = 0.0; float dCc = 0.25;
vec3 lp = vLp; vec3 ln = normalize(vLn);
if (vMarca.r > 0.5) {
  dCol = uCarcasa; dRug = 0.36; dCc = 0.4;
  float zl = dj_dentro(vec2(lp.x + 0.0395, lp.z + 0.0215), vec2(0.0075, 0.0021), 0.0018) * smoothstep(0.45, 0.65, abs(ln.y));
  dHueco = max(dHueco, zl * dj_ranuras(lp.x, 0.0021, 0.0011));
  dJunta = dj_linea(lp.x + 0.031, 0.0005, fwidth(lp.x)) * smoothstep(0.2, 0.4, abs(ln.y) + max(-ln.z, 0.0));
} else if (vMarca.g > 0.5) {
  dCol = uCuerpo; dRug = 0.45;
  float tf = dj_dentro(vec2(abs(lp.y) - 0.0165, lp.z + 0.0105), vec2(0.0055, 0.0022), 0.0018) * smoothstep(0.3, 0.55, ln.x);
  dHueco = max(dHueco, tf * 0.92);
  float zb = dj_dentro(vec2(lp.x + 0.030, lp.y), vec2(0.0130, 0.0110), 0.003) * smoothstep(0.5, 0.75, ln.z);
  dHueco = max(dHueco, zb * dj_ranuras(lp.y, 0.0024, 0.0011));
  float bat = smoothstep(-0.3, -0.55, ln.x) * smoothstep(-0.0470, -0.0490, lp.x);
  dCol = mix(dCol, uOscuro, bat); dRug = mix(dRug, 0.62, bat);
  dJunta = dj_linea(lp.x + 0.0478, 0.0005, fwidth(lp.x)) * (1.0 - bat);
}
dCol *= 1.0 - 0.7 * dJunta;
dCol = mix(dCol, vec3(0.012), dHueco);
diffuseColor.rgb = dCol;
float dAo = 1.0 - 0.6 * max(dJunta, dHueco);`)
        .replace("#include <roughnessmap_fragment>", "#include <roughnessmap_fragment>\nroughnessFactor = mix(dRug, 0.9, dHueco);")
        .replace("#include <lights_physical_fragment>", "#include <lights_physical_fragment>\nmaterial.clearcoat = dCc * (1.0 - dHueco); material.clearcoatRoughness = 0.22;")
        .replace("#include <aomap_fragment>", "#include <aomap_fragment>\nreflectedLight.indirectDiffuse *= dAo; reflectedLight.indirectSpecular *= mix(1.0, dAo, 0.4);");
    };
    m.customProgramCacheKey = () => "dji3d_casco";
    return m;
  }
  /** Disco de desenfoque de la helice (SHADER_DISCO de Godot): opacidad = fraccion de la circunferencia que tapan las
   *  dos palas a ese radio, con la punta naranja y un fantasma tenue de las palas. */
  function materialDisco() {
    const m = new THREE.MeshStandardMaterial({ color: 0xffffff, roughness: 0.45, transparent: true, depthWrite: false, side: THREE.DoubleSide });
    const u = { uColor: { value: new THREE.Color(C_HELICE) }, uPunta: { value: new THREE.Color(C_PUNTA) }, uInt: { value: 1 }, uFase: { value: 0 } };
    m.userData.u = u;
    m.onBeforeCompile = sh => {
      Object.assign(sh.uniforms, u);
      sh.vertexShader = sh.vertexShader.replace("#include <common>", "#include <common>\nvarying vec2 vDp;").replace("#include <begin_vertex>", "#include <begin_vertex>\nvDp = position.xy;");
      sh.fragmentShader = sh.fragmentShader.replace("#include <common>", `#include <common>
uniform vec3 uColor; uniform vec3 uPunta; uniform float uInt; uniform float uFase; varying vec2 vDp;
float dj_cuerda(float xi) { float c = 0.0072 + 0.0064 * smoothstep(0.0, 0.3, xi) - 0.0034 * smoothstep(0.3, 0.9, xi); if (xi > 0.8) c *= sqrt(max(0.0, 1.0 - pow((xi - 0.8) / 0.2, 2.0))); return c; }`)
        .replace("#include <color_fragment>", `#include <color_fragment>
float r = length(vDp); float xi = clamp((r - ${R0_HELICE.toFixed(4)}) / (${(R_HELICE - R0_HELICE).toFixed(4)}), 0.0, 1.0);
float cob = clamp(2.0 * dj_cuerda(xi) / (6.2831853 * max(r, 1e-4)), 0.0, 1.0);
float fantasma = pow(abs(cos(atan(vDp.y, vDp.x) - uFase)), 16.0);
diffuseColor.rgb = mix(uColor, uPunta, smoothstep(0.885, 0.905, xi));
diffuseColor.a = uInt * clamp(cob * 1.6 * (0.75 + 0.6 * fantasma), 0.0, 1.0) * smoothstep(${R0_HELICE.toFixed(4)}, ${(R0_HELICE + 0.0015).toFixed(4)}, r);`);
    };
    m.customProgramCacheKey = () => "dji3d_disco";
    return m;
  }
  function materiales(col) {
    const vidrio = std(0x04060a, 0.02, 0, 1, { clearcoatRoughness: 0, specularIntensity: 1 });
    return {
      casco: materialCasco(col), oscuro: std(0x2b2c2f, 0.5, 0, 0.2), camara: std(0x232427, 0.42, 0, 0.35), frontal: std(0xb9bbbc, 0.35, 0, 0.4),
      metal: std(0x6a6e74, 0.32, 0.85, 0), aro: std(0x3c3e42, 0.25, 0.9, 0), goma: std(0x1b1b1c, 0.9, 0, 0), tornillo: std(0x8d9095, 0.3, 1, 0),
      vidrio, sensor: std(0x0a0b0d, 0.06, 0, 0.8), led: std(0xe6e9eb, 0.1, 0, 0.7), buje: std(0x47484c, 0.4, 0.2, 0.2),
      palas: std(0xffffff, 0.38, 0, 0.25, { vertexColors: true, side: THREE.DoubleSide, transparent: true, depthWrite: false }),
    };
  }

  /** Posicion de una luz de los datos (malla.luces) sobre este modelo: las de los brazos traseros, por fuera de la
   *  carcasa de sus motores; la de la cola, en la trasera del cuerpo (posicion_luz de Godot). */
  function posicionLuz(p) {
    const [x, y] = p;
    if (x < -0.05 && Math.abs(y) > 0.05) return [-0.0695, Math.sign(y) * 0.0924, -0.0050];
    if (x < 0 && Math.abs(y) < 0.01) return [-0.0548, 0, -0.0125];
    return p;
  }

  window.ModeloDJI = {
    construir3D(datos) {
      // datos.modelo3d (otros drones con este mismo modelo, como el Inspector HQ-3T): escala y colores de la carcasa
      const M3 = datos.modelo3d || {}, esc = M3.escala || 1;
      const col = { carcasa: M3.carcasa !== undefined ? M3.carcasa : C_CARCASA, cuerpo: M3.cuerpo !== undefined ? M3.cuerpo : C_CUERPO, brazo: M3.brazo !== undefined ? M3.brazo : C_BRAZO };
      const C = mallas(), M = materiales(col), grupo = new THREE.Group(), todos = Object.values(M);
      const instancia = (padre, geos, pos) => {
        const g = new THREE.Group(); g.position.set(...pos); padre.add(g);
        for (const [k, geo] of Object.entries(geos)) { const ms = new THREE.Mesh(geo, M[k]); ms.castShadow = k !== "palas"; ms.receiveShadow = true; g.add(ms); }
        return g;
      };
      instancia(grupo, C.fijo, [0, 0, 0]);
      // gimbal de 3 ejes: guinada -> alabeo -> cabeceo (camara); cada malla esta en ejes cuerpo y se desplaza a su eje
      const gGui = new THREE.Group(); gGui.position.set(...G_GUI); grupo.add(gGui); instancia(gGui, C.g_guinada, mul(G_GUI, -1));
      const gAla = new THREE.Group(); gAla.position.set(...res(G_ALA, G_GUI)); gGui.add(gAla); instancia(gAla, C.g_alabeo, mul(G_ALA, -1));
      const gCab = new THREE.Group(); gCab.position.set(...res(G_CAB, G_ALA)); gAla.add(gCab); instancia(gCab, C.g_cabeceo, mul(G_CAB, -1));
      // rotores: palas (giran) y disco de desenfoque (translucido, sin sombra)
      const rotores = MOTORES.map(m => {
        const r = new THREE.Group(); r.position.set(m[0], m[1], m[2]); grupo.add(r);
        const palas = instancia(r, C.palas[m[3]], [0, 0, 0]);
        const md = materialDisco(), disco = new THREE.Mesh(C.disco, md); disco.visible = false; disco.renderOrder = 1; r.add(disco); todos.push(md);
        return { palas, disco, md, s: m[3], fase: Math.random() * TAU };
      });
      // luces de los datos (las enciende y escala el visor, como en construirAvion)
      const K = datos.malla || {};
      if (!construirAvion.texLuz) {
        const cv = document.createElement("canvas"); cv.width = cv.height = 32; const g = cv.getContext("2d");
        const gr = g.createRadialGradient(16, 16, 2, 16, 16, 16); gr.addColorStop(0, "rgba(255,255,255,1)"); gr.addColorStop(0.45, "rgba(255,255,255,0.95)"); gr.addColorStop(1, "rgba(255,255,255,0)");
        g.fillStyle = gr; g.fillRect(0, 0, 32, 32); construirAvion.texLuz = new THREE.CanvasTexture(cv);
      }
      const luces = (K.luces || []).map(l => {
        const g = new THREE.Group(); g.position.set(...posicionLuz(l.p)); g.patron = l.patron || "fijo";
        const sp = new THREE.Sprite(new THREE.SpriteMaterial({ color: l.color, map: construirAvion.texLuz, sizeAttenuation: false, transparent: true, depthWrite: false }));
        sp.scale.set(0.01, 0.01, 1); g.add(sp);
        g.add(new THREE.Mesh(new THREE.SphereGeometry(0.0022, 8, 6), new THREE.MeshBasicMaterial({ color: l.color }))); grupo.add(g); return g;
      });
      const rpmMax = (datos.propulsion && datos.propulsion.rpm_max) || 16000;
      let rpm = 0, t = 0, oculto = false, enVisor = false;
      /** Orientacion de la camara respecto al cuerpo repartida entre los tres motores del gimbal (poner_gimbal de Godot). */
      const mx = new THREE.Matrix4(), mA = new THREE.Matrix4(), mB = new THREE.Matrix4(), ejeZ = new THREE.Vector3(0, 0, 1), ejeX = new THREE.Vector3(1, 0, 0), ejeY = new THREE.Vector3(0, 1, 0);
      function ponerGimbal(loc) {
        const e = loc.elements, y = [e[4], e[5], e[6]];             // segunda columna
        const b = clamp(Math.asin(clamp(y[2], -1, 1)), -0.7, 0.7), a = clamp(Math.atan2(-y[0], y[1]), -0.6, 0.6);
        mA.makeRotationAxis(ejeZ, a); mB.makeRotationAxis(ejeX, b);
        gGui.quaternion.setFromRotationMatrix(mA); gAla.quaternion.setFromRotationMatrix(mB);
        mx.multiplyMatrices(mA, mB).transpose().multiply(loc);
        gCab.quaternion.setFromRotationMatrix(mx).normalize();
      }
      ponerGimbal(new THREE.Matrix4());
      const rb = new THREE.Matrix4(), rz = new THREE.Matrix4(), ry = new THREE.Matrix4();
      /** Cada cuadro: helices (con la inercia de los motores: palas nitidas despacio, disco de desenfoque deprisa),
       *  camara del gimbal estabilizada y, con la camara del dron, el dron solo como sombra. */
      function animar(av, dt, visor) {
        t += dt;
        if (visor && !enVisor) { enVisor = true; for (const m of todos) if (m.envMap) m.envMapIntensity = 2; }      // la escena de vuelo va con exposicion 0,5
        const obj = av.estado === "en mano" ? 0 : (av.rpm !== undefined ? av.rpm : (av.gases || 0) * rpmMax);
        rpm += (obj - rpm) * (1 - Math.exp(-dt / (obj > rpm ? 0.12 : 0.45)));
        if (obj <= 0) rpm = Math.max(0, rpm - 300 * dt);
        const dentro = !!(visor && visor.camara === 3);
        if (dentro !== oculto) { oculto = dentro; for (const m of todos) { m.colorWrite = !oculto; m.depthWrite = !oculto && !m.transparent; } }
        const aP = 1 - smooth(RPM_PALAS, RPM_PALAS * 3, rpm), kD = smooth(RPM_PALAS, RPM_DISCO, rpm);
        M.palas.opacity = aP;
        for (const R of rotores) {
          R.fase = (R.fase + R.s * rpm / 60 * TAU * dt) % TAU;
          R.palas.rotation.z = R.fase; R.palas.visible = aP > 0.01;
          R.md.userData.u.uInt.value = kD; R.md.userData.u.uFase.value = R.s * t * 1.7; R.disco.visible = kD > 0.01 && !oculto;
        }
        // gimbal: nivelado y con el rumbo del dron, inclinado av.gimbal (grados, 0 horizontal, -90 abajo)
        const q = av.q, X = Cuat.rot(q, [1, 0, 0]), Y = Cuat.rot(q, [0, 1, 0]), Z = Cuat.rot(q, [0, 0, 1]);
        rb.set(X[0], Y[0], Z[0], 0, X[1], Y[1], Z[1], 0, X[2], Y[2], Z[2], 0, 0, 0, 0, 1);
        rz.makeRotationAxis(ejeZ, Cuat.euler(q)[2]); ry.makeRotationAxis(ejeY, (av.gimbal || 0) * Math.PI / 180);
        ponerGimbal(rb.transpose().multiply(rz.multiply(ry)));
        if (oculto) for (const l of luces) l.visible = false;
      }
      // a escala: el modelo dentro de un grupo escalado (el de fuera lo coloca el visor con su matriz) y levantado para
      // que las patas sigan en el suelo (el CG posado esta a 0,02 m del suelo en la fisica)
      let raiz = grupo;
      if (esc !== 1) { raiz = new THREE.Group(); grupo.scale.setScalar(esc); grupo.position.set(0, 0, -(esc - 1) * SUELO); raiz.add(grupo); }
      return { grupo: raiz, prof: new THREE.Group(), timon: new THREE.Group(), alerones: [], helice: new THREE.Group(), luces, dron: true, animar };
    },
  };
})();
