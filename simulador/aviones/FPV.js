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

// ---- modelo 3D del dron FPV (un 5" tipo iFlight Nazgul / XING: carbono negro mate, brazos largos y finos, camara en soporte de
// TPU negro con la lente plateada, antena en un mastil hacia atras, motores negros, patas de TPU verde lima y helices
// tripala gris translucido; la bateria encima con su correa), en ejes cuerpo (x adelante, y derecha, z abajo; metros, origen en el CG): piezas (cajas y
// cilindros con su color), rotores de 3 palas (con un disco translucido cuando giran deprisa), camara inclinada y luces.
// Lo usa construirAvion() de js/visor.js; simulador_godot/scripts/modelo_fpv_3d.gd construye lo mismo con los mismos datos.
window.ModeloFPV.construir3D = window.ModeloFPV.construir3D || function (datos) {
  const K = datos.modelo3d, grupo = new THREE.Group();
  const mat = (c, op) => new THREE.MeshLambertMaterial(op === undefined ? { color: c } : { color: c, transparent: true, opacity: op, side: THREE.DoubleSide, depthWrite: false });
  const colocar = (mm, P) => { mm.position.set(...P.c); mm.rotation.order = "ZYX"; mm.rotation.set(0, (P.ry || 0) * D2R, (P.rz || 0) * D2R); return mm; };
  const geometria = P => P.f === "caja" ? new THREE.BoxGeometry(...P.l) : new THREE.CylinderGeometry(P.r, P.r, P.h, 18).rotateX(Math.PI / 2);   // cilindro: eje z del cuerpo
  for (const P of K.piezas) { const mm = colocar(new THREE.Mesh(geometria(P), mat(P.col)), P); mm.castShadow = true; grupo.add(mm); }
  const R = K.rotor, rotores = [];
  for (const [x, y, z, s] of K.rotores) {
    const r = new THREE.Group(); r.position.set(x, y, z); r.s = s;
    const palas = new THREE.Group();
    for (let k = 0; k < R.palas; k++) {                      // pala: de r0 a r1, girada su paso sobre su eje largo
      const pg = new THREE.Group(); pg.rotation.z = k * 2 * Math.PI / R.palas;
      const pm = new THREE.Mesh(new THREE.BoxGeometry(R.r1 - R.r0, R.ancho, R.grueso), mat(R.col, 0.8));
      pm.position.x = 0.5 * (R.r0 + R.r1); pm.rotation.x = s * R.paso_grados * D2R; pg.add(pm); palas.add(pg);
    }
    const disco = new THREE.Mesh(new THREE.CircleGeometry(R.r1, 32), mat(R.col, R.disco_opacidad));
    r.add(palas); r.add(disco); r.palas = palas; r.disco = disco; disco.visible = false; grupo.add(r); rotores.push(r);
  }
  // luces (tira de LED bajo los brazos): punto de tamano fijo en pantalla, como las del DJI (construirAvion)
  if (!construirAvion.texLuz) {
    const cv = document.createElement("canvas"); cv.width = cv.height = 32; const g = cv.getContext("2d");
    const gr = g.createRadialGradient(16, 16, 2, 16, 16, 16); gr.addColorStop(0, "rgba(255,255,255,1)"); gr.addColorStop(0.45, "rgba(255,255,255,0.95)"); gr.addColorStop(1, "rgba(255,255,255,0)");
    g.fillStyle = gr; g.fillRect(0, 0, 32, 32); construirAvion.texLuz = new THREE.CanvasTexture(cv);
  }
  const luces = K.luces.map(l => {
    const g = new THREE.Group(); g.position.set(...l.p);
    const sp = new THREE.Sprite(new THREE.SpriteMaterial({ color: l.color, map: construirAvion.texLuz, sizeAttenuation: false, transparent: true, depthWrite: false }));
    sp.scale.set(0.01, 0.01, 1); g.add(sp);
    g.add(new THREE.Mesh(new THREE.SphereGeometry(0.004, 8, 6), new THREE.MeshBasicMaterial({ color: l.color }))); grupo.add(g); return g;
  });
  /** Cada cuadro: rotores (palas quietas o disco girando), luces (fijas armado, parpadean desarmado) y, con la camara
   *  FPV, el dron oculto (la camara va dentro del bastidor). */
  function animar(av, dt, visor) {
    const ms = av.motores || [0, 0, 0, 0];
    rotores.forEach((r, i) => {
      const f = ms[i] || 0, rapido = f > 0.03;
      r.disco.visible = rapido; r.palas.visible = !rapido;
      if (f > 0) r.palas.rotation.z += r.s * f * 40 * dt;    // girando despacio al pararse
    });
    const tl = (performance.now() / 1000) % 1, sc = visor ? 14 * 2 * Math.tan(visor.cam.fov / 2 * Math.PI / 180) / visor.renderer.domElement.height : 0.01;
    for (const l of luces) { l.visible = av.armado || tl < 0.5; l.children[0].scale.set(sc, sc, 1); }
    grupo.visible = !(visor && visor.camara === 3);
  }
  const F = datos.fc, cam = { incl: F.camara_inclinacion_grados, fovH: F.camara_fov_h_grados, pos: F.camara_pos };     // para Visor._camara
  return { grupo, prof: new THREE.Group(), timon: new THREE.Group(), alerones: [], helice: new THREE.Group(), luces: [], dron: true, fpv: true, animar, cam };
};

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
      "piezas": [
        { "f": "caja", "c": [0.042, 0.042, 0.013], "l": [0.125, 0.013, 0.005], "rz": 45, "col": 1710618 },
        { "f": "caja", "c": [0.042, -0.042, 0.013], "l": [0.125, 0.013, 0.005], "rz": -45, "col": 1710618 },
        { "f": "caja", "c": [-0.042, 0.042, 0.013], "l": [0.125, 0.013, 0.005], "rz": 135, "col": 1710618 },
        { "f": "caja", "c": [-0.042, -0.042, 0.013], "l": [0.125, 0.013, 0.005], "rz": -135, "col": 1710618 },
        { "f": "caja", "c": [0, 0, 0.0135], "l": [0.12, 0.034, 0.004], "col": 2500134 },
        { "f": "caja", "c": [-0.006, 0, -0.0175], "l": [0.11, 0.034, 0.003], "col": 2500134 },
        { "f": "caja", "c": [-0.008, 0, -0.002], "l": [0.072, 0.03, 0.026], "col": 2039583 },
        { "f": "caja", "c": [0.012, 0.0155, -0.002], "l": [0.02, 0.002, 0.024], "col": 855309 },
        { "f": "caja", "c": [0.012, -0.0155, -0.002], "l": [0.02, 0.002, 0.024], "col": 855309 },
        { "f": "cil", "c": [0.078, 0.078, 0.0195], "r": 0.0135, "h": 0.008, "col": 7798531 },
        { "f": "cil", "c": [0.078, 0.078, 0.007], "r": 0.0145, "h": 0.006, "col": 1447446 },
        { "f": "cil", "c": [0.078, 0.078, -0.003], "r": 0.0145, "h": 0.014, "col": 1447446 },
        { "f": "cil", "c": [0.078, 0.078, -0.0005], "r": 0.0147, "h": 0.0015, "col": 13158600 },
        { "f": "cil", "c": [0.078, 0.078, -0.0115], "r": 0.005, "h": 0.004, "col": 11583173 },
        { "f": "cil", "c": [0.078, -0.078, 0.0195], "r": 0.0135, "h": 0.008, "col": 7798531 },
        { "f": "cil", "c": [0.078, -0.078, 0.007], "r": 0.0145, "h": 0.006, "col": 1447446 },
        { "f": "cil", "c": [0.078, -0.078, -0.003], "r": 0.0145, "h": 0.014, "col": 1447446 },
        { "f": "cil", "c": [0.078, -0.078, -0.0005], "r": 0.0147, "h": 0.0015, "col": 13158600 },
        { "f": "cil", "c": [0.078, -0.078, -0.0115], "r": 0.005, "h": 0.004, "col": 11583173 },
        { "f": "cil", "c": [-0.078, 0.078, 0.0195], "r": 0.0135, "h": 0.008, "col": 7798531 },
        { "f": "cil", "c": [-0.078, 0.078, 0.007], "r": 0.0145, "h": 0.006, "col": 1447446 },
        { "f": "cil", "c": [-0.078, 0.078, -0.003], "r": 0.0145, "h": 0.014, "col": 1447446 },
        { "f": "cil", "c": [-0.078, 0.078, -0.0005], "r": 0.0147, "h": 0.0015, "col": 13158600 },
        { "f": "cil", "c": [-0.078, 0.078, -0.0115], "r": 0.005, "h": 0.004, "col": 11583173 },
        { "f": "cil", "c": [-0.078, -0.078, 0.0195], "r": 0.0135, "h": 0.008, "col": 7798531 },
        { "f": "cil", "c": [-0.078, -0.078, 0.007], "r": 0.0145, "h": 0.006, "col": 1447446 },
        { "f": "cil", "c": [-0.078, -0.078, -0.003], "r": 0.0145, "h": 0.014, "col": 1447446 },
        { "f": "cil", "c": [-0.078, -0.078, -0.0005], "r": 0.0147, "h": 0.0015, "col": 13158600 },
        { "f": "cil", "c": [-0.078, -0.078, -0.0115], "r": 0.005, "h": 0.004, "col": 11583173 },
        { "f": "caja", "c": [0.052, 0.0125, -0.002], "l": [0.026, 0.004, 0.028], "col": 1315860 },
        { "f": "caja", "c": [0.052, -0.0125, -0.002], "l": [0.026, 0.004, 0.028], "col": 1315860 },
        { "f": "caja", "c": [0.056, 0, 0.011], "l": [0.012, 0.029, 0.004], "col": 1315860 },
        { "f": "caja", "c": [0.055, 0, -0.004], "l": [0.019, 0.019, 0.019], "ry": 28, "col": 855309 },
        { "f": "cil", "c": [0.0678, 0, -0.0108], "r": 0.0072, "h": 0.01, "ry": 118, "col": 11583173 },
        { "f": "cil", "c": [0.0731, 0, -0.0136], "r": 0.0052, "h": 0.002, "ry": 118, "col": 1845811 },
        { "f": "caja", "c": [-0.058, 0, -0.016], "l": [0.016, 0.014, 0.014], "col": 1315860 },
        { "f": "cil", "c": [-0.074, 0, -0.0549], "r": 0.003, "h": 0.07, "ry": 20, "col": 855309 },
        { "f": "cil", "c": [-0.0887, 0, -0.0953], "r": 0.0065, "h": 0.02, "ry": 20, "col": 1842204 },
        { "f": "caja", "c": [0, 0, -0.0355], "l": [0.075, 0.035, 0.034], "col": 2503224 },
        { "f": "caja", "c": [0.016, 0, -0.0355], "l": [0.026, 0.0354, 0.0344], "col": 16635957 },
        { "f": "caja", "c": [-0.017, 0, -0.0355], "l": [0.014, 0.0372, 0.0364], "col": 13959168 },
        { "f": "caja", "c": [-0.046, 0.014, -0.026], "l": [0.012, 0.008, 0.012], "col": 16766464 }
      ],
      "rotores": [[-0.078, 0.078, -0.015, 1], [0.078, 0.078, -0.015, -1], [-0.078, -0.078, -0.015, -1], [0.078, -0.078, -0.015, 1]],
      "rotor": {"palas": 3, "r0": 0.006, "r1": 0.0635, "ancho": 0.013, "grueso": 0.0015, "paso_grados": 14, "col": 10134955, "disco_opacidad": 0.2},
      "luces": [{"p": [-0.06, 0.06, 0.017], "color": 16717636}, {"p": [-0.06, -0.06, 0.017], "color": 16717636}, {"p": [0.06, 0.06, 0.017], "color": 16777215}, {"p": [0.06, -0.06, 0.017], "color": 16777215}]
    }
  };
  Modelos.registrar(DATOS, ModeloFPV);
})();
