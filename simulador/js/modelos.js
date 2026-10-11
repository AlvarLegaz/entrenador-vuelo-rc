"use strict";
// =====================================================================
//  MODELOS: los aviones del simulador y su fisica de 6 grados de libertad.
//
//  Cada avion es un fichero de la carpeta aviones/ que llama a Modelos.registrar({...}) con los
//  datos que genera scripts/modelo_aero_e1.py (tablas del VLM, derivadas, perdida, helice, mandos,
//  masa, inercias y malla 3D) y, si tiene otros mandos, con su subclase de ModeloAvion (el E2, con
//  alerones, redefine servos() y mandosCoef()). aviones/indice.js dice que ficheros cargar: con el servidor del aula
//  se genera solo leyendo la carpeta; sin servidor lo reescribe el script de exportacion.
//
//  Ejes: cuerpo (x adelante, y derecha, z abajo) y mundo NED (norte, este, abajo).
// =====================================================================
const D2R = Math.PI / 180, R2D = 180 / Math.PI, G0 = 9.81, RHO = 1.225;

// cuaterniones (w, x, y, z): rotacion cuerpo -> mundo
const Cuat = {
  mul(a, b) {
    return [a[0]*b[0]-a[1]*b[1]-a[2]*b[2]-a[3]*b[3], a[0]*b[1]+a[1]*b[0]+a[2]*b[3]-a[3]*b[2],
            a[0]*b[2]-a[1]*b[3]+a[2]*b[0]+a[3]*b[1], a[0]*b[3]+a[1]*b[2]-a[2]*b[1]+a[3]*b[0]];
  },
  norm(q) { const n = Math.hypot(...q); return q.map(v => v / n); },
  rot(q, v) {               // gira v (cuerpo) a mundo
    const [w, x, y, z] = q, t = [2*(y*v[2]-z*v[1]), 2*(z*v[0]-x*v[2]), 2*(x*v[1]-y*v[0])];
    return [v[0]+w*t[0]+y*t[2]-z*t[1], v[1]+w*t[1]+z*t[0]-x*t[2], v[2]+w*t[2]+x*t[1]-y*t[0]];
  },
  inv(q) { return [q[0], -q[1], -q[2], -q[3]]; },
  desdeEuler(roll, pitch, yaw) {
    const cr = Math.cos(roll/2), sr = Math.sin(roll/2), cp = Math.cos(pitch/2), sp = Math.sin(pitch/2),
          cy = Math.cos(yaw/2), sy = Math.sin(yaw/2);
    return [cr*cp*cy+sr*sp*sy, sr*cp*cy-cr*sp*sy, cr*sp*cy+sr*cp*sy, cr*cp*sy-sr*sp*cy];
  },
  euler(q) {                // [alabeo, cabeceo, rumbo] en radianes
    const [w, x, y, z] = q;
    return [Math.atan2(2*(w*x+y*z), 1-2*(x*x+y*y)), Math.asin(Math.max(-1, Math.min(1, 2*(w*y-z*x)))),
            Math.atan2(2*(w*z+x*y), 1-2*(y*y+z*z))];
  },
};

function interp(xs, ys, x) {
  if (x <= xs[0]) return ys[0];
  if (x >= xs[xs.length - 1]) return ys[ys.length - 1];
  let i = 1; while (xs[i] < x) i++;
  const t = (x - xs[i - 1]) / (xs[i] - xs[i - 1]);
  return ys[i - 1] + t * (ys[i] - ys[i - 1]);
}

class ModeloAvion {
  constructor(datos) {
    Object.assign(this, datos);
    this.TA = datos.tabla_alfa.map(t => t.alfa);
    this.TCL = datos.tabla_alfa.map(t => t.CL);
    this.TCDI = datos.tabla_alfa.map(t => t.CDi);
    this.TCM = datos.tabla_alfa.map(t => t.Cm);
    this.DA = datos.derivadas.map(d => d.alfa);
    this.DER = {};
    for (const k of Object.keys(datos.derivadas[0])) this.DER[k] = datos.derivadas.map(d => d[k]);
    // centro de gravedad y masa de diseno; configurar() los cambia (pantalla de eleccion del avion)
    this.masa_diseno_kg = datos.masa_kg;
    this.inercia_diseno = Object.assign({}, datos.inercia);
    this.dcg = 0;          // desplazamiento del CG respecto al de diseno, en ejes cuerpo (m, + = hacia el morro)
    // ---- realismo (valores por defecto razonados; un avion puede traer los suyos en sus datos) ----
    this.rho = RHO;                                       // densidad del aire (configurar({ temperatura }))
    this.calib = { empuje: 1, resistencia: 1 };           // calibracion con medidas del avion real (configurar)
    const pr = this.propulsion, Dm = pr.D_m;
    this.Qmax = pr.P_max_W / (2 * Math.PI * pr.n_max_rps);                         // par a tope (0,16 N m con el X2212 y la 9x4,7)
    this.Ihelice = datos.I_helice !== undefined ? datos.I_helice : 0.012 * (Dm / 0.2286) ** 3 * Dm * Dm / 12;   // helice de 12 g como varilla
    // helice parada: unos 27 cm2 de resistencia (palas de frente) para una 9", escalado con el diametro al cuadrado
    if (this.CD_helice_parada === undefined) this.CD_helice_parada = 0.0027 * (Dm / 0.2286) ** 2 / this.S_m2;
    this.k_perfil = datos.k_perfil !== undefined ? datos.k_perfil : 0.02;            // resistencia de perfil: k (CL - 0,3)^2, perfil a Re ~1e5
    // chorro de la helice: fraccion de la profundidad y del timon dentro de la estela, y fraccion del giro de la estela
    // que endereza la deriva (guinada a la izquierda a mucho gas). La deriva esta al final del fuselaje
    const ch = datos.chorro || {};
    this.chorro = { prof: ch.prof !== undefined ? ch.prof : (datos.malla && datos.malla.prof ? 0.3 : 0),
                    timon: ch.timon !== undefined ? ch.timon : 0.35, deriva: ch.deriva !== undefined ? ch.deriva : 0.1 };
    let xmin = 0; const fv = datos.malla && datos.malla.fuselaje && datos.malla.fuselaje.v;
    if (fv) for (let i = 0; i < fv.length; i += 3) xmin = Math.min(xmin, fv[i]);
    this.brazoDeriva = Math.max(0.1, -xmin - 0.06);
    this.brazoPerdida = datos.brazo_perdida !== undefined ? datos.brazo_perdida : 0.2;   // fraccion de b (ala rectangular)
  }

  /** Cambia la masa (kg) y la X del centro de gravedad (mm desde la bancada, como cg_mm). Las tablas y derivadas
   *  del VLM estan calculadas respecto al CG de diseno: paso() traslada sus momentos al CG nuevo, como en el
   *  avion real. Las inercias se escalan con la masa (no se sabe donde va el lastre). */
  configurar({ masa_kg, cg_mm, temperatura, empuje_gf, resistencia }) {
    if (temperatura !== undefined) this.rho = 101325 / (287.05 * (temperatura + 273.15));
    if (empuje_gf) { const pr = this.propulsion; this.calib.empuje = empuje_gf / 1000 * G0 / (pr.CT0 * RHO * pr.n_max_rps ** 2 * pr.D_m ** 4); }
    if (resistencia) this.calib.resistencia = resistencia;
    if (masa_kg) {
      this.masa_kg = masa_kg;
      const k = masa_kg / this.masa_diseno_kg;
      this.inercia = Object.fromEntries(Object.entries(this.inercia_diseno).map(([n, v]) => [n, v * k]));
    }
    if (cg_mm !== undefined) this.dcg = (this.cg_mm[0] - cg_mm) / 1000;
  }

  deriv(nombre, alfa) { return this.DER[nombre] ? interp(this.DA, this.DER[nombre], alfa) : 0; }

  /** Estado inicial: en la mano del piloto, a 1,6 m del suelo. */
  estadoInicial() {
    return { p: [0, 0, -1.6], q: Cuat.desdeEuler(0, 2 * D2R, 0), v: [0, 0, 0], w: [0, 0, 0], de: 0, dr: 0, da: 0, gases: 0, Wh: 0,
             asim: (Math.random() < 0.5 ? -1 : 1) * (0.2 + 0.4 * Math.random()),   // grados: ninguna ala es perfecta
             estado: "en mano", t: 0, alfa: 0, beta: 0, V: 0, g_carga: 1, perdida: 0, T: 0, rpm: 0, motorRoto: false };
  }

  lanzar(av) {
    av.q = Cuat.desdeEuler(0, this.lanzamiento.cabeceo_grados * D2R, 0);
    av.v = [this.lanzamiento.vel_ms, 0, 0]; av.w = [0, 0, 0];
    av.estado = "volando";
  }

  /** Palanca (-1..1, con exponencial) -> consigna de las superficies -> servo con retardo y velocidad maxima. */
  servos(av, mando, dt) {
    const m = this.mandos, e = m.expo, ex = s => (1 - e) * s + e * s * s * s;
    const deObj = -ex(mando.pitch) * m.prof_max_grados * D2R + mando.trim * D2R;   // tirar -> profundidad arriba
    const drObj = ex(mando.yaw) * m.timon_max_grados * D2R;                         // derecha -> timon a la derecha
    const vmax = m.servo_vel_grados_s * D2R;
    for (const [k, obj] of [["de", deObj], ["dr", drObj]])
      av[k] += Math.max(-vmax * dt, Math.min(vmax * dt, (obj - av[k]) * dt / m.servo_tau_s));
  }

  /** Aportacion de las superficies de mando a los coeficientes: profundidad (de) y timon (dr). d(nombre) es la
   *  derivada en el alfa actual y kman la eficacia tras la perdida. Un avion con otros mandos la redefine. */
  mandosCoef(av, d, kman) {
    const de = av.de * kman, dr = av.dr * kman;
    return { CL: d("CLde") * de, CY: d("CYdr") * dr, Cl: d("Cldr") * dr, Cm: d("Cmde") * de, Cn: d("Cndr") * dr };
  }

  /** Un paso de integracion de 6 grados de libertad. viento: velocidad del aire en NED (m/s).
   *  Opcionales en av, que pone el simulador antes de llamar: av.agl (altura sobre el suelo, m: efecto suelo) y av.pg
   *  (velocidad de alabeo de la turbulencia, rad/s: la rafaga que no es igual en las dos semialas).
   *  Ademas del modelo lineal del VLM: perdida por semiala (caida de ala y barrena), resistencia de perfil con el CL,
   *  helice parada, efecto suelo, par del motor, giroscopico, efecto P, chorro de la helice sobre la cola y la deriva,
   *  caida de tension de la bateria y densidad del aire (configurar). */
  paso(av, viento, dt) {
    const q = av.q, v = av.v, w = av.w, rho = this.rho;
    const wb = Cuat.rot(Cuat.inv(q), viento);
    const va = [v[0] - wb[0], v[1] - wb[1], v[2] - wb[2]];
    const V = Math.max(0.3, Math.hypot(...va));
    const alfa = Math.atan2(va[2], va[0]), beta = Math.asin(Math.max(-1, Math.min(1, va[1] / V)));
    const ad = alfa * R2D;
    const qS = 0.5 * rho * V * V * this.S_m2, b = this.b_m, c = this.c_m;
    const ph = (w[0] - (av.pg || 0)) * b / (2 * V), qh = w[1] * c / (2 * V), rh = w[2] * b / (2 * V);
    // ---- perdida POR SEMIALA: el angulo de ataque de cada semiala (a un 35 % de la envergadura) cambia con el
    // alabeo (la que baja ve mas alfa) y con una pequena asimetria de construccion (av.asim, grados, al azar en cada
    // vuelo). Si una entra antes, pierde sustentacion y el avion cae hacia ese lado; la que baja sigue en perdida:
    // autorrotacion (barrena). En perdida se pierde casi todo el amortiguamiento de alabeo ----
    const P = this.perdida, an = P.anchura_grados / 2;
    const fPerd = a => Math.max(1 / (1 + Math.exp(-(a - P.alfa_perdida_grados) / an)), 1 / (1 + Math.exp((a - P.alfa_perdida_neg_grados) / an)));
    // la seccion que manda es donde empieza la perdida: en un ala rectangular, cerca de la raiz (brazoPerdida, 20 % de b)
    const yc = this.brazoPerdida * b, dAp = w[0] * yc / V * R2D, asim = av.asim || 0;
    const fR = fPerd(ad + dAp + asim / 2), fL = fPerd(ad - dAp - asim / 2), f = 0.5 * (fR + fL);
    const CLlin = interp(this.TA, this.TCL, ad), Cmlin = interp(this.TA, this.TCM, ad);
    let CDi = interp(this.TA, this.TCDI, ad);
    const CLplaca = P.CL_placa_factor * 2 * Math.sin(alfa) * Math.cos(alfa);
    // efecto suelo (Wieselsberger): menos resistencia inducida y algo mas de sustentacion a menos de media envergadura
    const x16 = av.agl === undefined ? Infinity : (16 * Math.max(0.05, av.agl) / b) ** 2, fiS = isFinite(x16) ? x16 / (1 + x16) : 1;
    CDi *= fiS;
    const CL0 = ((1 - f) * CLlin + f * CLplaca) * (1 + 0.06 * (1 - fiS));
    // resistencia: parasita (por el factor de calibracion), de perfil creciente con el CL, inducida, de la perdida y,
    // con el motor parado, la de la helice quieta
    const pr = this.propulsion, g = av.motorRoto ? 0 : av.gases;
    const CDhel = g < 0.05 ? this.CD_helice_parada : 0;
    const CD = this.CD0 * this.calib.resistencia + this.k_perfil * (CL0 - 0.3) ** 2 + (1 - f) * CDi + f * 2 * Math.sin(alfa) ** 2 + CDhel;
    const aP = ad > 0 ? P.alfa_perdida_grados : P.alfa_perdida_neg_grados;
    const Cm0 = (1 - f) * Cmlin + f * (interp(this.TA, this.TCM, aP) - 0.5 * (alfa - aP * D2R));
    const kman = 1 - f * (1 - P.mando_post_perdida);      // eficacia de los mandos tras la perdida
    const aD = Math.max(this.DA[0], Math.min(this.DA[this.DA.length - 1], ad));
    const d = (n) => this.deriv(n, aD), M = this.mandosCoef(av, d, kman);
    // ---- motor y helice: T = CT0 (1 - J/J0) rho n^2 D^4, n = n_max * gas * tension (la bateria cae ~10 % al vaciarse) ----
    if (av.motorRoto) av.gases = 0;
    const bat = Math.max(0, 1 - av.Wh / pr.masa_bateria_Wh), n = pr.n_max_rps * g * (1 - 0.10 * (1 - bat));
    let T = 0, Q = 0, J = 0;
    if (g > 0.02) {
      J = V / (n * pr.D_m);
      T = pr.CT0 * this.calib.empuje * Math.max(0, 1 - J / pr.J0) * rho * n * n * Math.pow(pr.D_m, 4);
      Q = this.Qmax * (n / pr.n_max_rps) ** 2 * (0.6 + 0.4 * Math.max(0, 1 - J / pr.J0));   // par que absorbe la helice
      av.Wh += pr.P_max_W * g * g * g * dt / 3600;
    }
    av.T = T; av.Q = Q; av.rpm = g > 0.02 ? n * 60 : 0;
    // chorro de la helice sobre la cola (momento: velocidad en la estela V^2 + 2T/(rho A), ~80 % desarrollada en la
    // cola): da mando de profundidad y timon aunque el avion vaya despacio, como al lanzarlo a mano
    const Adisco = Math.PI * pr.D_m * pr.D_m / 4, rq = Math.min(6, 1 + 0.8 * 2 * T / (rho * Adisco) / (V * V));
    const kProf = 1 + this.chorro.prof * (rq - 1), kTimon = 1 + this.chorro.timon * (rq - 1);
    M.CL *= kProf; M.Cm *= kProf;
    if (this.mandos.timon_max_grados > 0) { M.CY *= kTimon; M.Cl *= kTimon; M.Cn *= kTimon; }
    const ClpEf = d("Clp") * (1 - 0.6 * f);                 // en perdida se pierde buena parte del amortiguamiento de alabeo
    const CL = CL0 + d("CLq") * qh + M.CL;
    const CY = d("CYb") * beta + d("CYp") * ph + d("CYr") * rh + M.CY;
    // lo que pierde una semiala al entrar en perdida: del CL maximo (el de la tabla en el alfa de perdida) al de placa
    // plana. En un ala rectangular la perdida empieza en la raiz: el brazo de esa sustentacion perdida es un 20 % de
    // la envergadura (en un ala con estrechamiento o flecha seria mayor y la caida de ala, mas brusca)
    const dCLside = Math.max(0, Math.min(CLlin, interp(this.TA, this.TCL, P.alfa_perdida_grados)) - CLplaca), yP = this.brazoPerdida * b;
    const Cl = d("Clb") * beta + ClpEf * ph + d("Clr") * rh + M.Cl + (fR - fL) * dCLside * yP / (2 * b);
    const Cm = Cm0 + d("Cmq") * qh + M.Cm;
    const Cn = d("Cnb") * beta + d("Cnp") * ph + d("Cnr") * rh + M.Cn + (fR - fL) * Math.max(0, 2 * Math.sin(alfa) ** 2 - CDi) * yP / (2 * b);
    const ca = Math.cos(alfa), sa = Math.sin(alfa);
    const Fa = [qS * (-CD * ca + CL * sa), qS * CY, qS * (-CD * sa - CL * ca)];
    const Ma = [qS * b * Cl, qS * c * Cm, qS * b * Cn];
    // momentos respecto al CG real: M_nuevo = M_diseno + (r_diseno - r_nuevo) x F, con r_diseno - r_nuevo = (-dcg, 0, 0).
    const dx = this.dcg;
    Ma[1] += dx * Fa[2]; Ma[2] -= dx * Fa[1];
    // linea de empuje (downthrust) y brazo de la helice desde el CG real
    const dth = (pr.downthrust_grados || 0) * D2R, hp = (this.malla && this.malla.helice) || [0, 0, 0];
    const Tx = T * Math.cos(dth), Tz = T * Math.sin(dth);
    Ma[1] += hp[2] * Tx - (hp[0] - dx) * Tz;
    // ---- efectos de la helice que giran el avion (helice que gira en sentido horario vista desde atras, s = +1):
    //  par de reaccion: alabea a la izquierda; la estela que gira golpea la deriva por la izquierda: guinada a la
    //  izquierda y algo de alabeo a la derecha (recupera una fraccion del par); efecto P con alfa: guinada a la
    //  izquierda; giroscopico: al encabritar, guinada a la derecha ----
    const s = pr.sentido || 1, sw = this.chorro.deriva, hFin = 0.05;
    Ma[0] += -s * Q + s * sw * Q;
    const Fsw = s * sw * Q / hFin;
    Fa[1] += Fsw; Ma[2] += -this.brazoDeriva * Fsw;
    if (T > 0) { const e = 0.5 * (pr.D_m / 2) * V * Math.sin(alfa) / (2 * Math.PI * n * 0.75 * pr.D_m / 2 + 1e-3); Ma[2] += -s * T * e; }
    const Hx = s * this.Ihelice * 2 * Math.PI * n;
    Ma[1] += -w[2] * Hx; Ma[2] += w[1] * Hx;
    const gb = Cuat.rot(Cuat.inv(q), [0, 0, G0]), m = this.masa_kg;
    const F = [Fa[0] + Tx + m * gb[0], Fa[1] + m * gb[1], Fa[2] + Tz + m * gb[2]];
    // ecuaciones de Euler: m(dv + w x v) = F ; I dw + w x (I w) = M
    const dv = [F[0] / m - (w[1] * v[2] - w[2] * v[1]), F[1] / m - (w[2] * v[0] - w[0] * v[2]), F[2] / m - (w[0] * v[1] - w[1] * v[0])];
    const I = this.inercia, Ixx = I.Ixx, Iyy = I.Iyy, Izz = I.Izz, Ixz = I.Ixz;
    const Iw = [Ixx * w[0] - Ixz * w[2], Iyy * w[1], Izz * w[2] - Ixz * w[0]];
    const wxIw = [w[1] * Iw[2] - w[2] * Iw[1], w[2] * Iw[0] - w[0] * Iw[2], w[0] * Iw[1] - w[1] * Iw[0]];
    const Mx = Ma[0] - wxIw[0], My = Ma[1] - wxIw[1], Mz = Ma[2] - wxIw[2], det = Ixx * Izz - Ixz * Ixz;
    const dw = [(Mx * Izz + Mz * Ixz) / det, My / Iyy, (Mz * Ixx + Mx * Ixz) / det];
    for (let i = 0; i < 3; i++) { v[i] += dv[i] * dt; w[i] += dw[i] * dt; }
    const dq = Cuat.mul(q, [0, w[0], w[1], w[2]]);
    av.q = Cuat.norm([q[0] + 0.5 * dq[0] * dt, q[1] + 0.5 * dq[1] * dt, q[2] + 0.5 * dq[2] * dt, q[3] + 0.5 * dq[3] * dt]);
    const vn = Cuat.rot(av.q, v);
    for (let i = 0; i < 3; i++) av.p[i] += vn[i] * dt;
    av.t += dt; av.alfa = ad; av.beta = beta * R2D; av.V = V; av.perdida = f; av.perdidaLados = [fL, fR];
    av.g_carga = -Fa[2] / (m * G0);
    return vn;
  }

  bateriaPct(av) { return Math.max(0, 100 * (1 - av.Wh / this.propulsion.masa_bateria_Wh)); }
}

class Modelos {
  static _datos = {};
  static _clases = {};
  static _indice = [];

  /** Lo llama cada fichero de aviones/. Clase (opcional): una subclase de ModeloAvion para un avion
   *  con otra fisica (alerones, flaps, cola en V...); si no se da, se usa ModeloAvion. */
  static registrar(datos, Clase) {
    if (!datos || !datos.id) { console.error("Modelo sin id", datos); return; }
    Modelos._datos[datos.id] = datos;
    Modelos._clases[datos.id] = Clase || ModeloAvion;
  }

  /** Lo llama aviones/indice.js con la lista de ficheros de la carpeta. */
  static indice(ficheros) { Modelos._indice = ficheros; }

  static _script(src) {
    return new Promise(res => {
      const s = document.createElement("script");
      s.src = src; s.onload = () => res(true);
      s.onerror = () => { console.error("No se pudo cargar " + src); res(false); };
      document.head.appendChild(s);
    });
  }

  /** Carga aviones/indice.js y despues cada avion que lista (funciona tambien abriendo el fichero sin servidor). */
  static async cargar(carpeta = "aviones/") {
    await Modelos._script(carpeta + "indice.js?" + Date.now());
    await Promise.all(Modelos._indice.map(f => Modelos._script(carpeta + f)));
    return Modelos.ids();
  }

  /** Ids de los aviones en el orden de aviones/indice.js (alfabetico: E1, E2, E3...), no en el que acaban de cargar. */
  static ids() {
    const orden = Modelos._indice.map(f => f.replace(/\.js$/i, "")), pos = id => { const i = orden.indexOf(id); return i < 0 ? 1e9 : i; };
    return Object.keys(Modelos._datos).sort((a, b) => pos(a) - pos(b) || a.localeCompare(b));
  }
  static datos(id) { return Modelos._datos[id]; }
  static crear(id) { return new Modelos._clases[id](Modelos._datos[id]); }
}
