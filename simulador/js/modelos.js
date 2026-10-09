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
  }

  deriv(nombre, alfa) { return this.DER[nombre] ? interp(this.DA, this.DER[nombre], alfa) : 0; }

  /** Estado inicial: en la mano del piloto, a 1,6 m del suelo. */
  estadoInicial() {
    return { p: [0, 0, -1.6], q: Cuat.desdeEuler(0, 2 * D2R, 0), v: [0, 0, 0], w: [0, 0, 0], de: 0, dr: 0, da: 0, gases: 0, Wh: 0,
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

  /** Un paso de integracion de 6 grados de libertad. viento: velocidad del aire en NED (m/s). */
  paso(av, viento, dt) {
    const q = av.q, v = av.v, w = av.w;
    const wb = Cuat.rot(Cuat.inv(q), viento);
    const va = [v[0] - wb[0], v[1] - wb[1], v[2] - wb[2]];
    const V = Math.max(0.3, Math.hypot(...va));
    const alfa = Math.atan2(va[2], va[0]), beta = Math.asin(Math.max(-1, Math.min(1, va[1] / V)));
    const ad = alfa * R2D;
    const qS = 0.5 * RHO * V * V * this.S_m2, b = this.b_m, c = this.c_m;
    const ph = w[0] * b / (2 * V), qh = w[1] * c / (2 * V), rh = w[2] * b / (2 * V);
    // perdida: mezcla sigmoide entre el VLM (lineal) y una placa plana
    const P = this.perdida;
    const fpos = 1 / (1 + Math.exp(-(ad - P.alfa_perdida_grados) / (P.anchura_grados / 2)));
    const fneg = 1 / (1 + Math.exp((ad - P.alfa_perdida_neg_grados) / (P.anchura_grados / 2)));
    const f = Math.max(fpos, fneg);
    const CLlin = interp(this.TA, this.TCL, ad), CDi = interp(this.TA, this.TCDI, ad), Cmlin = interp(this.TA, this.TCM, ad);
    const CL0 = (1 - f) * CLlin + f * P.CL_placa_factor * 2 * Math.sin(alfa) * Math.cos(alfa);
    const CD = this.CD0 + (1 - f) * CDi + f * 2 * Math.sin(alfa) ** 2;
    const aP = ad > 0 ? P.alfa_perdida_grados : P.alfa_perdida_neg_grados;
    const Cm0 = (1 - f) * Cmlin + f * (interp(this.TA, this.TCM, aP) - 0.5 * (alfa - aP * D2R));
    const kman = 1 - f * (1 - P.mando_post_perdida);      // eficacia de los mandos tras la perdida
    const aD = Math.max(this.DA[0], Math.min(this.DA[this.DA.length - 1], ad));
    const d = (n) => this.deriv(n, aD), M = this.mandosCoef(av, d, kman);
    const CL = CL0 + d("CLq") * qh + M.CL;
    const CY = d("CYb") * beta + d("CYp") * ph + d("CYr") * rh + M.CY;
    const Cl = d("Clb") * beta + d("Clp") * ph + d("Clr") * rh + M.Cl;
    const Cm = Cm0 + d("Cmq") * qh + M.Cm;
    const Cn = d("Cnb") * beta + d("Cnp") * ph + d("Cnr") * rh + M.Cn;
    const ca = Math.cos(alfa), sa = Math.sin(alfa);
    const Fa = [qS * (-CD * ca + CL * sa), qS * CY, qS * (-CD * sa - CL * ca)];
    const Ma = [qS * b * Cl, qS * c * Cm, qS * b * Cn];          // (el empuje suma su momento mas abajo)
    // motor y helice: T = CT0 (1 - J/J0) rho n^2 D^4, n = n_max * gases
    const pr = this.propulsion;
    if (av.motorRoto) av.gases = 0;
    const g = av.gases;
    let T = 0;
    if (g > 0.02) {
      const n = pr.n_max_rps * g, J = V / (n * pr.D_m);
      T = pr.CT0 * Math.max(0, 1 - J / pr.J0) * RHO * n * n * Math.pow(pr.D_m, 4);
      av.Wh += pr.P_max_W * g * g * g * dt / 3600;
    }
    av.T = T; av.rpm = g > 0.02 ? pr.n_max_rps * g * 60 : 0;
    // linea de empuje: la helice esta en malla.helice (ejes cuerpo desde el CG); si queda por debajo del CG, el
    // empuje encabrita. downthrust_grados (opcional, en propulsion) inclina el empuje hacia abajo para compensarlo
    const dth = (pr.downthrust_grados || 0) * D2R, hp = (this.malla && this.malla.helice) || [0, 0, 0];
    const Tx = T * Math.cos(dth), Tz = T * Math.sin(dth);
    Ma[1] += hp[2] * Tx - hp[0] * Tz;
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
    av.t += dt; av.alfa = ad; av.beta = beta * R2D; av.V = V; av.perdida = f;
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

  static ids() { return Object.keys(Modelos._datos); }
  static datos(id) { return Modelos._datos[id]; }
  static crear(id) { return new Modelos._clases[id](Modelos._datos[id]); }
}
