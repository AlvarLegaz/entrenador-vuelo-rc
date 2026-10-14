// Bipode de asalto HQ-07: vehiculo terrestre de dos patas, SECRETO (datos.oculto: solo sale en el hangar despues de
// teclear la combinacion; ver simulador.html, "vehiculo secreto"). No vuela: anda por el terreno.
//  - Palanca izquierda (W/S y A/D): adelante/atras y girar. Acelera y frena con inercia (7,5 t), gira mas despacio
//    cuanto mas deprisa anda y no sube pendientes de mas del 60 %; el cuerpo se inclina con el terreno.
//  - Palanca derecha (flechas): de lado gira la CINTURA sin tope (360 grados); adelante y atras sube y baja los brazos.
//  - Gatillo derecho (espacio): dispara el cañon rotativo (los 6 tubos tienen que coger vueltas antes de disparar). Los
//    disparos (trazadoras) y los drones diana los lleva el simulador; aqui solo se cuentan los disparos y se dice desde
//    donde y hacia donde salen (apuntado).
//  - Gatillo izquierdo (G): cierra el puño.
//  - El paso: la fase del ciclo avanza con lo andado y la tabla de DATOS.modelo3d.paso da los angulos de cada pierna
//    (cinematica inversa con el pie plano); parado, las piernas vuelven rectas.
// Estado como el resto de vehiculos (p NED, q, v en cuerpo...) para el HUD, la caja negra y la repeticion; el suelo lo
// pone el simulador (av.agl antes de cada paso y av.pendiente: dh/dN y dh/dE del terreno).
// simulador_godot/scripts/modelo_bipode.gd es la traduccion LITERAL de la clase ModeloBipode, y modelo_bipode_3d.gd la de
// construir3D. Los datos (con las mallas, que genera analisis/bipode/generar_bipode.py) estan al final, en JSON estricto.
const BIP_TAU = 2 * Math.PI;
window.ModeloBipode = window.ModeloBipode || class ModeloBipode {
  constructor(datos) {
    Object.assign(this, datos);
    this.esTerrestre = true; this.esBipode = true;
    this.bp = datos.bipode; this.rho = RHO; this.facil = false; this.dcg = 0;
    this.mandos = Object.assign({}, datos.mandos);
    const P = {}; for (const pz of datos.modelo3d.piezas) P[pz.nombre] = pz.pivote;
    this.piv = P;
  }
  configurar() {}
  bateriaPct() { return 100; }
  /** Parado y con el reactor apagado ("en mano" para el simulador: L o A lo arrancan). */
  estadoInicial() {
    return { p: [0, 0, 0], q: Cuat.desdeEuler(0, 0, 0), v: [0, 0, 0], w: [0, 0, 0], de: 0, dr: 0, da: 0, gases: 0, Wh: 0, asim: 0,
             estado: "en mano", t: 0, alfa: 0, beta: 0, V: 0, g_carga: 1, perdida: 0, T: 0, rpm: 0, motorRoto: false,
             rumbo: 0, vel: 0, giro: 0, alabeo: 0, cabeceo: 0, cintura: 0, brazos: 0, fase: 0, amp: 0, pisadas: 0,
             wCanones: 0, angCanones: 0, tDisparo: 0, disparos: 0, puno: 0, cmd: { avance: 0, giro: 0, cintura: 0, brazos: 0, fuego: 0, puno: 0 } };
  }
  /** Arrancar el reactor: ya puede andar. */
  lanzar(av) { av.estado = "volando"; av.rumbo = ((Cuat.euler(av.q)[2] % BIP_TAU) + BIP_TAU) % BIP_TAU; av.v = [0, 0, 0]; }
  desarmar() {}
  armarEnVuelo(av) { this.lanzar(av); }
  /** Mandos: palanca izquierda (mando.vz adelante, mando.guinada giro), derecha (mando.yaw cintura, mando.pitch brazos:
   *  palanca arriba = subir) y gatillos (mando.disparo, mando.puno). */
  servos(av, mando, dt) {
    const c = av.cmd;
    c.avance = mando.vz || 0; c.giro = mando.guinada || 0; c.cintura = mando.yaw || 0; c.brazos = -(mando.pitch || 0);   // palanca arriba: sube el brazo
    c.fuego = mando.disparo ? 1 : 0; c.puno = mando.puno ? 1 : 0;
  }
  paso(av, viento, dt) {
    const B = this.bp, c = av.cmd, suelo = av.agl === undefined ? 0 : -av.p[2] - av.agl;
    av.t += dt;
    // --- velocidad: la palanca pide una velocidad; la inercia de 7,5 t la alcanza con su aceleracion
    let vObj = c.avance >= 0 ? c.avance * B.vel_max_ms : c.avance * B.vel_atras_ms;
    const pend = av.pendiente || [0, 0], cr = Math.cos(av.rumbo), sr = Math.sin(av.rumbo);
    const gAd = pend[0] * cr + pend[1] * sr, gDe = -pend[0] * sr + pend[1] * cr;       // pendiente hacia delante y hacia la derecha
    const subida = vObj >= 0 ? gAd : -gAd;
    if (subida > 0) vObj *= Math.max(0, 1 - subida / B.pendiente_max);                // cuesta arriba, mas despacio; a partir del 60 %, no sube
    const dv = vObj - av.vel, a = Math.abs(vObj) > Math.abs(av.vel) && vObj * av.vel >= 0 ? B.acel_ms2 : B.frena_ms2;
    av.vel += Math.sign(dv) * Math.min(Math.abs(dv), a * dt);
    // --- giro: mas lento cuanto mas deprisa anda
    const k = Math.min(1, Math.abs(av.vel) / B.vel_max_ms), giroMax = (B.giro_max_gs + (B.giro_marcha_gs - B.giro_max_gs) * k) * D2R;
    av.giro += (c.giro * giroMax - av.giro) * Math.min(1, dt / 0.25);
    av.rumbo = ((av.rumbo + av.giro * dt) % BIP_TAU + BIP_TAU) % BIP_TAU;
    // --- cintura (sin tope) y brazos
    av.cintura = ((av.cintura + c.cintura * B.cintura_gs * D2R * dt) % BIP_TAU + BIP_TAU) % BIP_TAU;
    av.brazos = Math.max(B.brazos_min_grados * D2R, Math.min(B.brazos_max_grados * D2R, av.brazos + c.brazos * B.brazos_gs * D2R * dt));
    av.puno += (c.puno - av.puno) * Math.min(1, dt / 0.15);
    // --- posicion sobre el terreno (el simulador la ajusta a la altura del terreno donde quede)
    av.p[0] += cr * av.vel * dt; av.p[1] += sr * av.vel * dt; av.p[2] = -suelo;
    // --- el cuerpo se inclina con el terreno (cabeceo + = morro arriba cuesta arriba; alabeo + = cae a la derecha)
    const kt = Math.min(1, dt / B.inclina_tau_s);
    av.cabeceo += (Math.atan(gAd) - av.cabeceo) * kt; av.alabeo += (-Math.atan(gDe) - av.alabeo) * kt;
    av.q = Cuat.desdeEuler(av.alabeo, av.cabeceo, av.rumbo);
    av.v = [av.vel, 0, 0]; av.V = Math.abs(av.vel);
    // --- paso: la fase avanza con lo andado (girando sobre si mismo tambien da pasos); amplitud segun la marcha
    const ciclo = B.paso_m / B.apoyo, vPaso = Math.max(Math.abs(av.vel), Math.abs(av.giro) * 0.9);
    const ampObj = Math.min(1, vPaso / (0.35 * B.vel_max_ms));
    av.amp += (ampObj - av.amp) * Math.min(1, dt / 0.35);
    const f0 = av.fase;
    av.fase = ((av.fase + (av.vel < -0.01 ? -1 : 1) * vPaso / ciclo * dt) % 1 + 1) % 1;
    if (av.amp > 0.3 && Math.floor(f0 * 2) !== Math.floor(av.fase * 2)) av.pisadas++;          // pisada: empieza el apoyo de un pie
    // --- cañon rotativo: los tubos cogen vueltas con el gatillo; dispara a la cadencia cuando van al 80 %
    const wMax = B.cadencia_rpm / 60 / 6 * BIP_TAU;                                                 // 6 tubos: una vuelta cada 6 disparos
    av.wCanones += (c.fuego * wMax - av.wCanones) * Math.min(1, dt / B.giro_canones_tau_s);
    av.angCanones = (av.angCanones + av.wCanones * dt) % BIP_TAU;
    if (c.fuego && av.wCanones > 0.8 * wMax) {
      av.tDisparo += dt;
      const cada = 60 / B.cadencia_rpm;
      while (av.tDisparo >= cada) { av.tDisparo -= cada; av.disparos++; }
    } else av.tDisparo = 0;
    av.rpm = av.wCanones / BIP_TAU * 60; av.gases = Math.min(1, Math.abs(av.vel) / B.vel_max_ms);
    return [av.vel * cr, av.vel * sr, 0];
  }
  /** Desde donde y hacia donde sale el disparo (NED del mundo): la boca del cañon con la cintura y los brazos girados. */
  apuntado(av) {
    const P = this.piv, H = P.brazo_d, C = P.cintura, B = this.bp.boca, th = av.brazos, ps = av.cintura;
    // brazos: giro de cabeceo (+ = arriba) sobre el hombro; cintura: giro de rumbo sobre su eje
    const rb = v => [v[0] * Math.cos(th) + v[2] * Math.sin(th), v[1], -v[0] * Math.sin(th) + v[2] * Math.cos(th)];
    const rc = v => [v[0] * Math.cos(ps) - v[1] * Math.sin(ps), v[0] * Math.sin(ps) + v[1] * Math.cos(ps), v[2]];
    const b1 = rb([B[0] - H[0], B[1] - H[1], B[2] - H[2]]), b3 = rc([H[0] + b1[0] - C[0], H[1] + b1[1] - C[1], H[2] + b1[2] - C[2]]);
    const local = [C[0] + b3[0], C[1] + b3[1], C[2] + b3[2]], d = rc(rb([1, 0, 0]));
    const o = Cuat.rot(av.q, local), dm = Cuat.rot(av.q, d);
    return { o: [av.p[0] + o[0], av.p[1] + o[1], av.p[2] + o[2]], d: dm };
  }
};

// ---------------------------------------------------------------- juego: drones diana y disparos
// Drones diana que patrullan alrededor del bipode (de un punto a otro, a 15-55 m sobre el suelo) y las balas del cañon
// (con su caida; una de cada tres, trazadora). Una bala que pasa a menos de radio_impacto_m de un dron le quita una vida;
// sin vidas cae dando vueltas, echando humo, y al llegar al suelo explota; a los 6 s sale otro lejos. Todo en NED del
// mundo; el suelo es la funcion altura(N, E) del terreno (m sobre el origen; null = llano). Azar con semilla
// (Park-Miller): Godot (modelo_bipode.gd, JuegoBipode) hace lo mismo con la misma semilla.
window.JuegoBipode = window.JuegoBipode || class JuegoBipode {
  constructor(datos, semilla) {
    this.B = datos.bipode; this.D = datos.bipode.drones; this.s = (semilla % 2147483646) + 1;
    this.drones = []; this.balas = []; this.eventos = []; this.derribados = 0; this.disparos = 0; this.t = 0; this.nId = 0;
    this.blancos = [];     // multijugador: los otros pilotos en el aire [{id, p, r}] (los pone el simulador cada cuadro)
    this.golpes = {};      // multijugador: impactos dados a cada uno (id -> cuantos); van en el estado que se manda a la sala
  }
  azar() { this.s = (this.s * 16807) % 2147483647; return (this.s - 1) / 2147483646; }
  /** Punto de patrulla al azar a radio_m (como mucho) del centro y a su altura sobre el suelo. */
  _punto(c, altura, lejos) {
    const D = this.D, a = this.azar() * BIP_TAU, r = D.radio_m * (lejos ? 0.7 + 0.3 * this.azar() : 0.25 + 0.75 * Math.sqrt(this.azar()));
    const N = c[0] + r * Math.cos(a), E = c[1] + r * Math.sin(a), h = D.alt_min_m + (D.alt_max_m - D.alt_min_m) * this.azar();
    return [N, E, -((altura ? altura(N, E) : 0) + h)];
  }
  nuevoDron(c, altura, lejos) {
    const p = this._punto(c, altura, lejos), o = this._punto(c, altura, false);
    this.drones.push({ id: ++this.nId, p, v: [0, 0, 0], obj: o, estado: "vuela", vida: this.D.vida, rumbo: 0, giro: 0, tFin: 0, inclina: [0, 0] });
  }
  iniciar(c, altura) { this.drones = []; this.balas = []; this.eventos = []; for (let k = 0; k < this.D.n; k++) this.nuevoDron(c, altura, true); }
  /** Una bala desde a = {o, d} (apuntado), con la dispersion del cañon. */
  disparo(a) {
    const B = this.B, ds = B.dispersion_grados * D2R, u = (this.azar() - 0.5) * 2 * ds, w = (this.azar() - 0.5) * 2 * ds;
    const d = a.d, h = Math.hypot(d[0], d[1]), e1 = h > 1e-6 ? [-d[1] / h, d[0] / h, 0] : [0, 1, 0];
    const e2 = [d[1] * e1[2] - d[2] * e1[1], d[2] * e1[0] - d[0] * e1[2], d[0] * e1[1] - d[1] * e1[0]];
    const dir = [d[0] + u * e1[0] + w * e2[0], d[1] + u * e1[1] + w * e2[1], d[2] + u * e1[2] + w * e2[2]], n = Math.hypot(dir[0], dir[1], dir[2]);
    this.balas.push({ p: a.o.slice(), v: [dir[0] / n * B.bala_ms, dir[1] / n * B.bala_ms, dir[2] / n * B.bala_ms], t: 0, traza: true });
  }
  /** dt en s; av y modelo del bipode (los disparos nuevos salen de modelo.apuntado). */
  paso(dt, av, modelo, altura) {
    this.t += dt;
    const B = this.B, D = this.D, g = 9.81, suelo = (N, E) => -(altura ? altura(N, E) : 0), c = [av.p[0], av.p[1]];
    // disparos nuevos: desde la boca, con dispersion (un cono de dispersion_grados)
    while (this.disparos < av.disparos) { this.disparos++; this.disparo(modelo.apuntado(av)); this.balas[this.balas.length - 1].traza = this.disparos % 3 === 0; }
    // balas: vuelo con gravedad; choque con los drones (segmento contra esfera) y con el suelo
    const quedan = [];
    for (const b of this.balas) {
      const p0 = b.p.slice();
      b.v[2] += g * dt; b.p = [b.p[0] + b.v[0] * dt, b.p[1] + b.v[1] * dt, b.p[2] + b.v[2] * dt]; b.t += dt;
      let fuera = b.t * B.bala_ms > B.alcance_m;
      for (const dr of this.drones) {
        if (dr.estado !== "vuela" || fuera) continue;
        const s = [b.p[0] - p0[0], b.p[1] - p0[1], b.p[2] - p0[2]], q = [dr.p[0] - p0[0], dr.p[1] - p0[1], dr.p[2] - p0[2]];
        const L2 = s[0] * s[0] + s[1] * s[1] + s[2] * s[2], k = Math.max(0, Math.min(1, (q[0] * s[0] + q[1] * s[1] + q[2] * s[2]) / Math.max(L2, 1e-9)));
        const dx = q[0] - k * s[0], dy = q[1] - k * s[1], dz = q[2] - k * s[2];
        if (dx * dx + dy * dy + dz * dz < D.radio_impacto_m * D.radio_impacto_m) {
          fuera = true; dr.vida--;
          this.eventos.push({ tipo: "impacto", p: dr.p.slice() });
          if (dr.vida <= 0) {
            dr.estado = "cae"; dr.giro = (this.azar() < 0.5 ? -1 : 1) * (6 + 6 * this.azar()); this.derribados++;
            dr.v = [dr.v[0] + b.v[0] * 0.004, dr.v[1] + b.v[1] * 0.004, dr.v[2] - 2];
            this.eventos.push({ tipo: "derribado", p: dr.p.slice() });
          }
        }
      }
      for (const o of this.blancos) {                          // multijugador: los aviones y drones de los compañeros
        if (fuera) break;
        const s = [b.p[0] - p0[0], b.p[1] - p0[1], b.p[2] - p0[2]], q = [o.p[0] - p0[0], o.p[1] - p0[1], o.p[2] - p0[2]];
        const L2 = s[0] * s[0] + s[1] * s[1] + s[2] * s[2], k = Math.max(0, Math.min(1, (q[0] * s[0] + q[1] * s[1] + q[2] * s[2]) / Math.max(L2, 1e-9)));
        const dx = q[0] - k * s[0], dy = q[1] - k * s[1], dz = q[2] - k * s[2];
        if (dx * dx + dy * dy + dz * dz < o.r * o.r) { fuera = true; this.golpes[o.id] = (this.golpes[o.id] || 0) + 1; this.eventos.push({ tipo: "impacto", p: o.p.slice() }); }
      }
      if (!fuera && b.p[2] > suelo(b.p[0], b.p[1])) { fuera = true; this.eventos.push({ tipo: "suelo", p: [b.p[0], b.p[1], suelo(b.p[0], b.p[1])] }); }
      if (!fuera) quedan.push(b);
    }
    this.balas = quedan;
    // drones: patrulla de punto en punto; derribados, caen con su giro hasta el suelo
    for (const dr of this.drones) {
      if (dr.estado === "vuela") {
        const d = [dr.obj[0] - dr.p[0], dr.obj[1] - dr.p[1], dr.obj[2] - dr.p[2]], L = Math.hypot(d[0], d[1], d[2]);
        if (L < 4) dr.obj = this._punto(c, altura, false);
        const vo = L > 1e-6 ? [d[0] / L * D.vel_ms, d[1] / L * D.vel_ms, d[2] / L * D.vel_ms] : [0, 0, 0], kk = Math.min(1, dt * 0.8);
        const ax = (vo[0] - dr.v[0]) * kk, ay = (vo[1] - dr.v[1]) * kk;
        dr.v = [dr.v[0] + ax, dr.v[1] + ay, dr.v[2] + (vo[2] - dr.v[2]) * kk];
        // se inclina hacia donde acelera (en ejes de su rumbo: cabeceo y alabeo)
        const ca = Math.cos(dr.rumbo), sa = Math.sin(dr.rumbo), aN = ax / Math.max(dt, 1e-6) / g, aE = ay / Math.max(dt, 1e-6) / g;
        dr.inclina = [Math.max(-0.4, Math.min(0.4, -(aN * ca + aE * sa) - 0.12)), Math.max(-0.4, Math.min(0.4, -aN * sa + aE * ca))];
        if (Math.hypot(dr.v[0], dr.v[1]) > 0.5) dr.rumbo = Math.atan2(dr.v[1], dr.v[0]);
      } else if (dr.estado === "cae") {
        dr.v[2] += g * dt; dr.rumbo += dr.giro * dt; dr.inclina = [0.6 * Math.sin(this.t * 7), 0.6 * Math.cos(this.t * 5)];
        if (dr.p[2] + dr.v[2] * dt > suelo(dr.p[0], dr.p[1])) {
          dr.estado = "roto"; dr.tFin = 0; dr.p[2] = suelo(dr.p[0], dr.p[1]); dr.v = [0, 0, 0];
          this.eventos.push({ tipo: "explosion", p: dr.p.slice() });
        }
      } else dr.tFin += dt;
      if (dr.estado !== "roto") dr.p = [dr.p[0] + dr.v[0] * dt, dr.p[1] + dr.v[1] * dt, dr.p[2] + dr.v[2] * dt];
    }
    const vivos = this.drones.filter(dr => !(dr.estado === "roto" && dr.tFin > 6)), faltan = this.drones.length - vivos.length;
    this.drones = vivos;
    for (let k = 0; k < faltan; k++) this.nuevoDron(c, altura, true);
  }
};

// ---------------------------------------------------------------- 3D (Three.js)
(function () {
  if (typeof THREE === "undefined") return;
  const lin = c => { const f = x => (x /= 255) <= 0.04045 ? x / 12.92 : Math.pow((x + 0.055) / 1.055, 2.4); return [f((c >> 16) & 255), f((c >> 8) & 255), f(c & 255)]; };
  const n6 = x => x.toFixed(6);
  /** Codigo comun del sombreado: tabla de materiales (colores lineales, rugosidad, metalico) + DATOS.modelo3d.sombreador. */
  function codigo(K) {
    let s = "vec3 bip_color(float m) {\n";
    K.materiales.forEach((mt, i) => { const c = lin(mt[1]); s += `\tif (m < ${n6(i + 0.5)}) return vec3(${c.map(n6).join(", ")});\n`; });
    s += "\treturn vec3(1.0);\n}\nvec2 bip_rm(float m) {\n";
    K.materiales.forEach((mt, i) => { s += `\tif (m < ${n6(i + 0.5)}) return vec2(${n6(mt[2])}, ${n6(mt[3])});\n`; });
    return s + "\treturn vec2(0.5, 0.0);\n}\n" + K.sombreador.join("\n") + "\n";
  }
  /** Las mallas de cada pieza (una vez). Por vertice 18 bytes (DATOS.modelo3d.formato): posicion int16 x3 (0,1 mm, NED
   *  desde su pivote), normal int8 x3, material, curvatura (int8), oclusion, altura, relleno y uv uint16 x2. */
  function mallas(K) {
    if (mallas.geo) return mallas.geo;
    const geo = {};
    for (const pz of K.piezas) {
      const bin = atob(pz.v), u8 = new Uint8Array(bin.length); for (let i = 0; i < bin.length; i++) u8[i] = bin.charCodeAt(i);
      const dv = new DataView(u8.buffer), n = pz.vertices;
      const pos = new Float32Array(3 * n), nor = new Float32Array(3 * n), uv = new Float32Array(2 * n), bip = new Uint8Array(4 * n);
      for (let k = 0; k < n; k++) {
        const o = 18 * k;
        for (let j = 0; j < 3; j++) { pos[3 * k + j] = dv.getInt16(o + 2 * j, true) / 10000; nor[3 * k + j] = dv.getInt8(o + 6 + j) / 127; }
        bip[4 * k] = u8[o + 9]; bip[4 * k + 1] = dv.getInt8(o + 10) + 128; bip[4 * k + 2] = u8[o + 11]; bip[4 * k + 3] = u8[o + 12];
        uv[2 * k] = dv.getUint16(o + 14, true) / 65535; uv[2 * k + 1] = dv.getUint16(o + 16, true) / 65535;
      }
      const ib = atob(pz.i), idx = new Uint16Array(ib.length / 2); for (let i = 0; i < idx.length; i++) idx[i] = ib.charCodeAt(2 * i) | (ib.charCodeAt(2 * i + 1) << 8);
      const g = new THREE.BufferGeometry();
      g.setAttribute("position", new THREE.BufferAttribute(pos, 3)); g.setAttribute("normal", new THREE.BufferAttribute(nor, 3));
      g.setAttribute("uv", new THREE.BufferAttribute(uv, 2)); g.setAttribute("bip", new THREE.BufferAttribute(bip, 4, true));
      g.setIndex(new THREE.BufferAttribute(idx, 1)); g.computeBoundingSphere();
      geo[pz.nombre] = g;
    }
    return (mallas.geo = geo);
  }
  function material(K) {
    const tex = new THREE.TextureLoader().load("aviones/" + K.calcas); tex.colorSpace = THREE.SRGBColorSpace; tex.anisotropy = 8; tex.flipY = false;
    const m = new THREE.MeshStandardMaterial({ color: 0xffffff, roughness: 1, metalness: 1 });
    m.userData.u = { uCalcas: { value: tex } };
    m.onBeforeCompile = sh => {
      Object.assign(sh.uniforms, m.userData.u);
      sh.vertexShader = sh.vertexShader.replace("#include <common>", "#include <common>\nattribute vec4 bip;\nvarying vec4 vBip;\nvarying vec3 vPl;\nvarying vec3 vNl;\nvarying vec2 vUvC;")
        .replace("#include <begin_vertex>", "#include <begin_vertex>\nvBip = bip; vPl = position; vNl = normal; vUvC = uv;");
      sh.fragmentShader = sh.fragmentShader.replace("#include <common>", "#include <common>\nuniform sampler2D uCalcas;\nvarying vec4 vBip;\nvarying vec3 vPl;\nvarying vec3 vNl;\nvarying vec2 vUvC;\n" + codigo(K))
        .replace("#include <color_fragment>", `#include <color_fragment>
  float bM = floor(vBip.x * 255.0 + 0.5), bK = (vBip.y * 255.0 - 128.0) / 127.0, bAo = vBip.z, bH = vBip.w;
  vec3 bAlb = bip_color(bM); vec2 bRm = bip_rm(bM); vec3 bEmi = vec3(0.0);
  if (abs(bM - 7.0) < 0.5) { vec4 tc = texture2D(uCalcas, vUvC); if (tc.a < 0.5 || bip_calca_saltada(vPl) > 0.5) discard; bAlb = tc.rgb; }
  float bRug = bRm.x, bMet = bRm.y;
  bip_superficie(vPl, vNl, bM, bK, bH, bAlb, bRug, bMet, bEmi);
  diffuseColor.rgb = bAlb;`)
        .replace("#include <roughnessmap_fragment>", "#include <roughnessmap_fragment>\n  roughnessFactor = bRug;")
        .replace("#include <metalnessmap_fragment>", "#include <metalnessmap_fragment>\n  metalnessFactor = bMet;")
        .replace("#include <emissivemap_fragment>", "#include <emissivemap_fragment>\n  totalEmissiveRadiance = bEmi;")
        .replace("#include <lights_fragment_end>", "#include <lights_fragment_end>\n  reflectedLight.indirectDiffuse *= bAo; reflectedLight.indirectSpecular *= mix(1.0, bAo, 0.8);\n  reflectedLight.directDiffuse *= mix(1.0, bAo, 0.35);");
    };
    return m;
  }
  function entorno() {          // reflejos: cielo, horizonte y suelo, para que el metal tenga algo que reflejar
    if (entorno.t) return entorno.t;
    const c = document.createElement("canvas"); c.width = 256; c.height = 128; const g = c.getContext("2d");
    const gr = g.createLinearGradient(0, 0, 0, 128);
    gr.addColorStop(0, "#5f86b8"); gr.addColorStop(0.48, "#cfdde9"); gr.addColorStop(0.52, "#7a7464"); gr.addColorStop(1, "#3b3529");
    g.fillStyle = gr; g.fillRect(0, 0, 256, 128);
    const t = new THREE.CanvasTexture(c); t.mapping = THREE.EquirectangularReflectionMapping; t.colorSpace = THREE.SRGBColorSpace;
    return (entorno.t = t);
  }
  window.ModeloBipode.codigo3D = codigo;
  /** Grupo con el bipode (cuerpo NED, origen en el suelo bajo la cadera) y animar(): paso, cintura, brazos, cañones y puño. */
  window.ModeloBipode.construir3D = function (datos) {
    const K = datos.modelo3d, G = mallas(K), mat = material(K), grupo = new THREE.Group(), nodos = {}, piv = {};
    mat.envMap = entorno();
    for (const pz of K.piezas) piv[pz.nombre] = pz.pivote;
    for (const pz of K.piezas) {
      const n = new THREE.Group(), pp = pz.padre ? piv[pz.padre] : [0, 0, 0];
      n.position.set(pz.pivote[0] - pp[0], pz.pivote[1] - pp[1], pz.pivote[2] - pp[2]);
      const me = new THREE.Mesh(G[pz.nombre], mat); me.castShadow = true; me.receiveShadow = true; n.add(me);
      (pz.padre ? nodos[pz.padre] : grupo).add(n); nodos[pz.nombre] = n;
    }
    // fogonazo en la boca del cañon: destello y luz que parpadean al disparar
    const B = datos.bipode, fogo = new THREE.Group();
    fogo.position.set(B.boca[0] - piv.brazo_d[0] + 0.1, B.boca[1] - piv.brazo_d[1], B.boca[2] - piv.brazo_d[2]); nodos.brazo_d.add(fogo);
    const fm = new THREE.MeshBasicMaterial({ color: 0xffb347, transparent: true, opacity: 0.9, blending: THREE.AdditiveBlending, depthWrite: false, side: THREE.DoubleSide });
    for (let k = 0; k < 3; k++) { const pl = new THREE.Mesh(new THREE.PlaneGeometry(0.8, 0.36), fm); pl.position.x = 0.3; pl.rotation.x = k * Math.PI / 3; fogo.add(pl); }
    const luzFogo = new THREE.PointLight(0xffa040, 0, 14, 2); luzFogo.position.x = 0.3; fogo.add(luzFogo); fogo.visible = false;
    const T = K.paso.tabla, NT = T.length;
    const fila = f => { const x = f * NT, i = Math.floor(x) % NT, j = (i + 1) % NT, a = x - Math.floor(x); return T[i].map((v, k) => v + (T[j][k] - v) * a); };
    let nDisp = -1, tFogo = 0;
    const apunta = { piv, bp: B };
    function animar(av, dt, visor) {
      const a = av.amp || 0, r = fila(av.fase || 0);
      nodos.cadera_d.rotation.y = a * r[0]; nodos.rodilla_d.rotation.y = a * r[1]; nodos.tobillo_d.rotation.y = a * r[2];
      nodos.cadera_i.rotation.y = a * r[3]; nodos.rodilla_i.rotation.y = a * r[4]; nodos.tobillo_i.rotation.y = a * r[5];
      nodos.pelvis.position.z = piv.pelvis[2] - a * r[6]; nodos.pelvis.rotation.x = a * r[7];
      nodos.cintura.rotation.z = av.cintura || 0;
      nodos.brazo_d.rotation.y = av.brazos || 0; nodos.brazo_i.rotation.y = 0.6 * (av.brazos || 0);
      nodos.canones.rotation.x = av.angCanones || 0;
      nodos.dedos.rotation.y = -1.1 * (av.puno || 0);
      if (av.disparos !== nDisp) { if (nDisp >= 0 && av.disparos > nDisp) tFogo = 0.05; nDisp = av.disparos; }
      tFogo -= dt; fogo.visible = tFogo > 0; luzFogo.intensity = tFogo > 0 ? 40 : 0;
      if (fogo.visible) fogo.rotation.x = Math.random() * Math.PI;
    }
    /** Camaras propias: 2 detras del torso, mirando hacia donde apunta la cintura; 3 puesto de tiro sobre el hombro. */
    function camara(visor, av, cam, t) {
      const yaw = Cuat.euler(av.q)[2] + (av.cintura || 0);
      if (visor.camara === 2) {
        const back = ned2three([-Math.cos(yaw) * 7.5, -Math.sin(yaw) * 7.5, -4.6]), fw = ned2three([Math.cos(yaw) * 5, Math.sin(yaw) * 5, -2.2]);
        cam.position.set(t[0] + back[0], t[1] + back[1], t[2] + back[2]); cam.fov = 60; cam.up.set(0, 1, 0); cam.lookAt(t[0] + fw[0], t[1] + fw[1], t[2] + fw[2]);
        return true;
      }
      if (visor.camara === 3) {
        const ap = window.ModeloBipode.prototype.apuntado.call(apunta, av);
        const ojo = ned2three([av.p[0] - Math.cos(yaw) * 3.6 - Math.sin(yaw) * 2.3, av.p[1] - Math.sin(yaw) * 3.6 + Math.cos(yaw) * 2.3, av.p[2] - 2.7]);   // detras del hombro del cañon
        const mira = ned2three([ap.o[0] + ap.d[0] * 80, ap.o[1] + ap.d[1] * 80, ap.o[2] + ap.d[2] * 80]);
        cam.position.set(ojo[0], ojo[1], ojo[2]); cam.fov = 55; cam.up.set(0, 1, 0); cam.lookAt(mira[0], mira[1], mira[2]);
        return true;
      }
      return false;
    }
    return { grupo, prof: new THREE.Group(), timon: new THREE.Group(), alerones: [], helice: new THREE.Group(), luces: [], bipode: true, animar, camara, nodos };
  };
})();

// ---------------------------------------------------------------- efectos del juego (Three.js): drones, balas, polvo, humo
(function () {
  if (typeof THREE === "undefined") return;
  function texHumo() {
    if (texHumo.t) return texHumo.t;
    const c = document.createElement("canvas"); c.width = c.height = 64; const g = c.getContext("2d");
    const gr = g.createRadialGradient(32, 32, 2, 32, 32, 32); gr.addColorStop(0, "rgba(255,255,255,0.9)"); gr.addColorStop(0.5, "rgba(255,255,255,0.45)"); gr.addColorStop(1, "rgba(255,255,255,0)");
    g.fillStyle = gr; g.fillRect(0, 0, 64, 64);
    return (texHumo.t = new THREE.CanvasTexture(c));
  }
  /** Dron diana: cuadricoptero de 60 cm (cuerpo, brazos, motores, helices como discos, patas y luces). Ejes NED. */
  function dronDiana() {
    const g = new THREE.Group(), mc = new THREE.MeshStandardMaterial({ color: 0x3a3d42, roughness: 0.45, metalness: 0.3 });
    const mo = new THREE.MeshStandardMaterial({ color: 0xd8461b, roughness: 0.5 }), mm = new THREE.MeshStandardMaterial({ color: 0x1a1a1a, roughness: 0.35, metalness: 0.7 });
    const caja = (x, y, z, sx, sy, sz, m) => { const b = new THREE.Mesh(new THREE.BoxGeometry(sx, sy, sz), m); b.position.set(x, y, z); b.castShadow = true; g.add(b); return b; };
    caja(0, 0, 0, 0.26, 0.16, 0.08, mc); caja(0.02, 0, -0.05, 0.16, 0.12, 0.03, mo); caja(0.14, 0, 0.03, 0.05, 0.06, 0.05, mm);
    const discos = [];
    for (const [x, y] of [[0.2, 0.2], [0.2, -0.2], [-0.2, 0.2], [-0.2, -0.2]]) {
      const br = caja(x / 2, y / 2, 0, Math.hypot(x, y), 0.03, 0.02, mc); br.rotation.z = Math.atan2(y, x);
      const mot = new THREE.Mesh(new THREE.CylinderGeometry(0.025, 0.025, 0.04, 12), mm); mot.rotation.x = Math.PI / 2; mot.position.set(x, y, -0.02); g.add(mot);
      const d = new THREE.Mesh(new THREE.CircleGeometry(0.12, 24), new THREE.MeshBasicMaterial({ color: 0x111111, transparent: true, opacity: 0.35, side: THREE.DoubleSide, depthWrite: false }));
      d.position.set(x, y, -0.045); g.add(d); discos.push(d);
      caja(x * 0.6, y * 0.6, 0.07, 0.015, 0.015, 0.1, mm);
    }
    const led = (x, c) => { const l = new THREE.Mesh(new THREE.SphereGeometry(0.012, 8, 6), new THREE.MeshBasicMaterial({ color: c })); l.position.set(x, 0, 0.04); g.add(l); return l; };
    led(-0.13, 0xff2a1a); led(0.13, 0x2aff4a);
    g.userData.discos = discos;
    return g;
  }
  /** Efectos del juego en la escena: pintar(juego, dt, camara) cada cuadro; quitar() al acabar. */
  window.ModeloBipode.efectos3D = function (escena) {
    const raiz = new THREE.Group(); escena.add(raiz);
    const dronesG = new Map();
    // balas trazadoras: cilindros finos y luminosos (InstancedMesh, hasta 300)
    const MAXB = 300, geoB = new THREE.CylinderGeometry(0.06, 0.06, 1, 6, 1, true);
    const matB = new THREE.MeshBasicMaterial({ color: 0xff8a1a, transparent: true, opacity: 0.9, depthWrite: false });
    const balas = new THREE.InstancedMesh(geoB, matB, MAXB); balas.frustumCulled = false; raiz.add(balas);
    // particulas: polvo, humo, fuego (sprites de un fondo comun)
    const parts = [];
    function particula(p, tipo) {
      const col = tipo === "fuego" ? 0xffa040 : tipo === "humo" ? 0x2b2622 : tipo === "chispa" ? 0xffe0a0 : 0x8a7a62;
      const m = new THREE.SpriteMaterial({ map: texHumo(), color: col, transparent: true, depthWrite: false, blending: tipo === "fuego" || tipo === "chispa" ? THREE.AdditiveBlending : THREE.NormalBlending });
      const s = new THREE.Sprite(m), t = ned2three(p); s.position.set(t[0], t[1], t[2]); raiz.add(s);
      const vida = tipo === "humo" ? 2.6 : tipo === "fuego" ? 0.6 : tipo === "chispa" ? 0.18 : 1.4, t0 = tipo === "humo" ? 0.5 : tipo === "fuego" ? 1.2 : tipo === "chispa" ? 0.5 : 0.6;
      const crece = tipo === "humo" ? 2.2 : tipo === "fuego" ? 3 : tipo === "chispa" ? 1 : 2.2;
      parts.push({ s, t: 0, vida, t0, crece, sube: tipo === "humo" ? 1.2 : tipo === "polvo" ? 0.4 : 0.6 });
    }
    function quitarParticulas() { for (const q of parts) { raiz.remove(q.s); q.s.material.dispose(); } parts.length = 0; }
    let tHumo = 0;
    const M = new THREE.Matrix4(), Q = new THREE.Quaternion(), Y = new THREE.Vector3(0, 1, 0), D = new THREE.Vector3(), S = new THREE.Vector3(), P = new THREE.Vector3();
    function pintar(J, dt, cam) {
      if (!J) { raiz.visible = false; return; }
      raiz.visible = true;
      // drones
      const vistos = new Set();
      for (const dr of J.drones) {
        let g = dronesG.get(dr.id);
        if (!g) { g = dronDiana(); g.matrixAutoUpdate = false; raiz.add(g); dronesG.set(dr.id, g); }
        vistos.add(dr.id);
        const q = Cuat.desdeEuler(dr.inclina[1], dr.inclina[0], dr.rumbo), ex = ned2three(Cuat.rot(q, [1, 0, 0])), ey = ned2three(Cuat.rot(q, [0, 1, 0])), ez = ned2three(Cuat.rot(q, [0, 0, 1]));
        const t = ned2three(dr.estado === "roto" ? [dr.p[0], dr.p[1], dr.p[2] - 0.08] : dr.p);
        g.matrix.set(ex[0], ey[0], ez[0], t[0], ex[1], ey[1], ez[1], t[1], ex[2], ey[2], ez[2], t[2], 0, 0, 0, 1);
        for (const d of g.userData.discos) d.visible = dr.estado === "vuela";
        if (dr.estado === "roto") g.traverse(o => { if (o.material && o.material.color && !o.userData.quemado) { o.material = o.material.clone(); o.material.color.multiplyScalar(0.25); o.userData.quemado = true; } });
      }
      for (const [id, g] of dronesG) if (!vistos.has(id)) { raiz.remove(g); dronesG.delete(id); }
      // humo de los que caen y de los rotos (los primeros segundos)
      tHumo += dt;
      if (tHumo > 0.06) {
        tHumo = 0;
        for (const dr of J.drones) if (dr.estado === "cae" || (dr.estado === "roto" && dr.tFin < 4)) { particula(dr.p, "humo"); if (dr.estado === "cae") particula(dr.p, "fuego"); }
      }
      // balas: solo las trazadoras se ven, como una estela de 45 m (lo que recorren en 1/20 s) que engorda con la distancia
      let n = 0;
      for (const b of J.balas) {
        if (!b.traza || n >= MAXB) continue;
        const v = Math.hypot(b.v[0], b.v[1], b.v[2]), L = Math.min(45, b.t * v), t = ned2three(b.p), d = ned2three([b.v[0] / v, b.v[1] / v, b.v[2] / v]);
        const dc = cam ? Math.hypot(t[0] - cam.position.x, t[1] - cam.position.y, t[2] - cam.position.z) : 50, r = Math.max(1, Math.min(8, dc * 0.025));
        D.set(d[0], d[1], d[2]); Q.setFromUnitVectors(Y, D); P.set(t[0] - d[0] * L / 2, t[1] - d[1] * L / 2, t[2] - d[2] * L / 2); S.set(r, L, r);
        M.compose(P, Q, S); balas.setMatrixAt(n++, M);
      }
      balas.count = n; balas.instanceMatrix.needsUpdate = true;
      // eventos: polvo al dar en el suelo, chispas al dar en un dron, explosion al caer
      for (const e of J.eventos) {
        if (e.tipo === "suelo") particula(e.p, "polvo");
        else if (e.tipo === "impacto") { particula(e.p, "chispa"); particula(e.p, "chispa"); }
        else if (e.tipo === "derribado") { particula(e.p, "fuego"); particula(e.p, "humo"); }
        else if (e.tipo === "explosion") { for (let k = 0; k < 6; k++) particula([e.p[0] + (Math.random() - 0.5), e.p[1] + (Math.random() - 0.5), e.p[2] - Math.random()], k < 3 ? "fuego" : "humo"); }
      }
      J.eventos.length = 0;
      for (let i = parts.length - 1; i >= 0; i--) {
        const q = parts[i]; q.t += dt; const f = q.t / q.vida;
        if (f >= 1) { raiz.remove(q.s); q.s.material.dispose(); parts.splice(i, 1); continue; }
        const sz = q.t0 + q.crece * f; q.s.scale.set(sz, sz, 1); q.s.position.y += q.sube * dt; q.s.material.opacity = (1 - f) * 0.85;
      }
      if (parts.length > 600) { const sobran = parts.splice(0, parts.length - 600); for (const q of sobran) { raiz.remove(q.s); q.s.material.dispose(); } }
    }
    function quitar() { quitarParticulas(); escena.remove(raiz); }
    return { pintar, quitar };
  };
})();
