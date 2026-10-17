"use strict";
// =====================================================================
//  OPERACIONES: los trabajos de operador de dron (escenarios.js, "operacion") en el mapa real de Cartagena, con el dron comercial:
//  inspeccion de edificios, fotogrametria, busqueda y rescate, agricultura, inspeccion de paneles fotovoltaicos y
//  grabacion de video. Evalua lo que pide cada orden de trabajo (las fotos, la cobertura, la posicion enviada, la orbita...) y las
//  normas del operador en todas (120 m, a la vista, fuera de la zona del aeropuerto, aterrizar en el punto de despegue y
//  con reserva de bateria), y detecta los choques con los paneles y el faro. Lo dibuja js/visor_real.js
//  (ponerOperacion). simulador_godot/scripts/operaciones.gd es su traduccion literal: mismos datos, reglas y textos.
//
//  Uso: op = new Operacion(Operacion.sortear(datos), marcar, anotar, {casa: [N, E], suelo(N, E), h0}); en cada paso de la fisica
//  op.paso(pAnt, av, dt, {gimbal, grabando, zoom, termica}) devuelve los avisos (toasts) y deja op.choque si ha chocado; con cada foto
//  op.foto(av, gimbal, {zoom, termica}) devuelve el aviso de esa foto; al acabar op.final(final, av, {bateria}); op.ahora(obj, av) es la
//  linea "Ahora: ..." del panel. Con la camara termica (dron de inspeccion), op.lectura es lo que mide el medidor puntual
//  del centro de la imagen ({T, tipo, nombre} o null) y op.termicos lo que se ve caliente o frio en la termica (para dibujarlo).
// =====================================================================
const OPS = {
  TECHO: 120,                                     // m sobre el suelo
  VLOS: 500,                                      // m del piloto (en horizontal)
  ARP: { nombre: "aeropuerto de San Javier", n: 17936.4, e: 20962.4, r: 8000 },   // zona de aerodromo (8 km)
  CAM_V: 29,                                      // semiangulo vertical de la camara del dron comercial (grados)
  CAM_H: Math.atan(Math.tan(29 * Math.PI / 180) * 4 / 3) * 180 / Math.PI,         // horizontal (foto 4:3)
  CASA: 10, RESERVA: 20,                          // aterrizar a menos de 10 m del despegue, con mas del 20 % de bateria
  RETICULA: 0.6,                                  // radio de la cruz del medidor puntual de la termica (grados con zoom 1x)
  AMBIENTE: 29.5,                                 // lo que mide la termica en el suelo y lo que no esta caliente ni frio (grados C)
};
/** Un camion militar (el de los trabajos de reconocimiento): piezas [largo, ancho, alto, x, arriba, color] en ejes del
 *  camion (x hacia delante, desde el centro) y las ruedas [x, y]. Lo dibujan visor_real.js y mundo_3d.gd. */
const CAMION = {
  piezas: [[6.6, 2.3, 0.45, 0, 0.95, 0x2c2f22], [1.9, 2.3, 1.75, 2.25, 1.95, 0x4b5320], [0.08, 2.0, 0.7, 3.22, 2.3, 0x101418],
           [4.2, 2.4, 2.1, -1.05, 2.25, 0x5a5f3a], [4.3, 2.45, 0.12, -1.05, 3.35, 0x4a4e30]],
  ruedas: [[2.4, 1.05], [-0.6, 1.05], [-2.0, 1.05], [2.4, -1.05], [-0.6, -1.05], [-2.0, -1.05]], radio: 0.52,
};
/** Temperatura (grados C) -> "calor" de la imagen termica (0 frio, 1 lo mas caliente): la que usan visor.js y mundo_3d.gd
 *  para pintar lo caliente y lo frio de un trabajo encima de la imagen (el resto sale de la luz de la escena). */
const opCalor = T => T >= 40 ? 0.55 + 0.45 * Math.min(1, (T - 40) / 110) : T <= 10 ? 0.15 * Math.max(0, (T + 20) / 30) : 0.15 + 0.4 * (T - 10) / 30;
const opDesenrollar = d => d - 2 * Math.PI * Math.round(d / (2 * Math.PI));
const opMMSS = s => `${Math.floor(s / 60)}:${String(Math.floor(s % 60)).padStart(2, "0")}`;
/** Tiempo de carrera con decimas: 1:05,3. */
const opCrono = s => `${Math.floor(s / 60)}:${(s % 60).toFixed(1).padStart(4, "0").replace(".", ",")}`;
// carrera de drones: medidas de los obstaculos (ancho y alto, m; el picado: el lado del marco), grosor del marco o de los
// postes para los choques, radio del dron, patas del andamio del picado y cuanto se espera tras la meta (o la descalificacion)
const CARRERA = {
  MEDIDAS: { puerta: [3, 2.4], arco: [6, 4], banderas: [5, 5], picado: [4, 4] },
  GROSOR: { puerta: 0.1, arco: 0.45, banderas: 0.15, picado: 0.1 },
  NOMBRE: { puerta: "marco", arco: "arco", banderas: "banderas", picado: "picado, de arriba abajo" },
  R_DRON: 0.2, PATA: 0.08, FIN_S: 2,
};
// nombres de los desperfectos de la inspeccion: los sitios salen al azar de "candidatos" y cada uno lleva uno de estos
const OP_NOMBRES_CUBIERTA = ["Lucernario de la cubierta", "Placas solares de la cubierta", "Extractor de la cubierta", "Antena del tejado",
  "Impermeabilización levantada", "Claraboya rota", "Chimenea de ventilación", "Equipo de aire acondicionado"];
const OP_NOMBRES_FACHADA = ["Grieta en la fachada", "Canalón de la fachada", "Desconchado en la fachada", "Bajante roto en la fachada"];
const opOrientacion = g => ["norte", "este", "sur", "oeste"][Math.round(((g % 360) + 360) % 360 / 90) % 4];

class Operacion {
  /** Los datos de un trabajo con los objetivos en sitios al azar dentro de su zona, para que no sean siempre los mismos:
   *  la inspeccion elige cubiertas y fachadas de "candidatos" (con su nombre), los paneles los modulos danados, la
   *  agricultura las manchas (sin pisarse) y la busqueda al senderista. rnd: numeros al azar en [0, 1) (Math.random; las
   *  pruebas pasan uno con semilla para comparar con operaciones.gd). */
  /** (n, e) dentro del poligono [[n, e], ...]. */
  static dentro(P, n, e) {
    let d = false;
    for (let i = 0, j = P.length - 1; i < P.length; j = i++) { const [ni, ei] = P[i], [nj, ej] = P[j]; if ((ni > n) !== (nj > n) && e < (ej - ei) * (n - ni) / (nj - ni) + ei) d = !d; }
    return d;
  }
  /** Distancia de (n, e) al borde del poligono (m). */
  static aBorde(P, n, e) {
    let m = 1e9;
    for (let i = 0, j = P.length - 1; i < P.length; j = i++) {
      const [ni, ei] = P[i], [nj, ej] = P[j], dn = nj - ni, de = ej - ei, L2 = dn * dn + de * de, t = L2 > 0 ? Math.max(0, Math.min(1, ((n - ni) * dn + (e - ei) * de) / L2)) : 0;
      m = Math.min(m, Math.hypot(ni + t * dn - n, ei + t * de - e));
    }
    return m;
  }
  static sortear(O, rnd = Math.random) {
    const d = Object.assign({}, O), azar = n => Math.floor(rnd() * n);
    const tomar = (lista, k, lejos = 0) => {          // k elementos distintos, a ser posible a mas de "lejos" m entre si
      const L = lista.slice(), r = [];
      while (r.length < k && L.length) {
        const vale = L.filter(q => r.every(x => Math.hypot(q.n - x.n, q.e - x.e) >= lejos));
        const q = (vale.length ? vale : L)[azar((vale.length ? vale : L).length)]; r.push(q); L.splice(L.indexOf(q), 1);
      }
      return r;
    };
    if (O.candidatos) {                               // inspeccion: unas cubiertas y unas fachadas, en orden al azar
      const C = O.candidatos, nc = tomar(OP_NOMBRES_CUBIERTA.map(n => ({ n: 0, e: 0, nombre: n })), C.elegir[0]), nf = tomar(OP_NOMBRES_FACHADA.map(n => ({ n: 0, e: 0, nombre: n })), C.elegir[1]);
      const cub = tomar(C.cubiertas, C.elegir[0], 15).map((q, i) => Object.assign({}, q, { nombre: nc[i].nombre }));
      const fac = tomar(C.fachadas, C.elegir[1], 15).map((q, i) => Object.assign({}, q, { nombre: `${nf[i].nombre} ${opOrientacion(q.normal)}` }));
      d.puntos = tomar(cub.concat(fac), cub.length + fac.length);
    }
    if (O.planta && O.defectos) {                     // paneles: modulos danados de filas y posiciones al azar
      const P = O.planta, r = [];
      while (r.length < O.defectos.length) {
        const f = azar(P.filas), x = 3 + azar(P.largo - 6);
        if (P.huecos && P.huecos.includes(f)) continue;               // pasillo sin paneles
        if (r.every(([g, y]) => g !== f || Math.abs(y - x) >= 10)) r.push([f, x]);
      }
      d.defectos = r;
      if (O.calientes) {                              // y los modulos con punto caliente (solo se ven con la termica), en otros sitios
        const c = [];
        while (c.length < O.calientes) {
          const f = azar(P.filas), x = 3 + azar(P.largo - 6);
          if (P.huecos && P.huecos.includes(f)) continue;
          if (r.concat(c).every(([g, y]) => g !== f || Math.abs(y - x) >= 10)) c.push([f, x]);
        }
        d.calientes = c;
      }
    }
    if (O.racks) {                                    // fabrica: puntos calientes en tuberias de plata de racks distintos, la fuga y la antorcha
      const libres = O.racks.map((_, i) => i), c = [];
      while (c.length < O.calientes) {
        const k = azar(libres.length), ri = libres.length ? libres.splice(k, 1)[0] : azar(O.racks.length);
        const T = Industria.tuberias(O.racks[ri]).map((t, i) => [t, i]).filter(([t]) => t.color === 5);
        const ti = T[azar(T.length)][1];
        c.push([ri, ti, Math.round((0.15 + 0.7 * rnd()) * 1000) / 1000, Math.round(105 + 30 * rnd())]);
      }
      d.puntosCalientes = c;
      const ui = azar(O.unidades.length);
      d.fuga = [ui, azar(O.unidades[ui].valvulas.length), azar(4)];
      d.placaTxt = "A-" + (10 + azar(90)); d.piloto = rnd() < 0.7;
    }
    if (O.parcela && O.manchas) {                     // agricultura: las manchas en la parcela (o en su poligono), sin pisarse
      const P = O.parcela, r = [];
      for (const [, , rad] of O.manchas) {
        let m = null;
        for (let k = 0; k < 200 && !m; k++) {
          const n = P.n0 + rad + 8 + rnd() * (P.n1 - P.n0 - 2 * rad - 16), e = P.e0 + rad + 8 + rnd() * (P.e1 - P.e0 - 2 * rad - 16);
          if (P.poligono && !(Operacion.dentro(P.poligono, n, e) && Operacion.aBorde(P.poligono, n, e) >= rad + 8)) continue;
          if (r.every(([n2, e2, r2]) => Math.hypot(n - n2, e - e2) >= rad + r2 + 20)) m = [n, e, rad];
        }
        r.push(m || O.manchas[r.length]);
      }
      d.manchas = r;
    }
    if (O.zona) d.persona = [O.zona.n0 + 20 + rnd() * (O.zona.n1 - O.zona.n0 - 40), O.zona.e0 + 20 + rnd() * (O.zona.e1 - O.zona.e0 - 40)];   // busqueda
    if (O.recon) {                                    // reconocimiento (Grajo, Poli-1, Entrenador 1): los vehiculos al azar
      const R = O.recon, veh = (n, e, dist) => { const a = 2 * Math.PI * rnd(), r = dist * Math.sqrt(rnd()); return [Math.round(n + r * Math.cos(a)), Math.round(e + r * Math.sin(a)), Math.round(360 * rnd())]; };
      if (R.puntos) { d.conVehiculo = tomar(R.puntos.map((q, i) => ({ n: q.n, e: q.e, i })), R.con_vehiculo).map(q => q.i).sort((a, b) => a - b); d.vehiculos = d.conVehiculo.map(i => veh(R.puntos[i].n, R.puntos[i].e, 25)); }
      if (R.objetivo) d.vehiculos = [veh(R.objetivo.n, R.objetivo.e, 20)];
      if (R.zona) { const Z = R.zona; d.vehiculos = [[Math.round(Z.n0 + 60 + rnd() * (Z.n1 - Z.n0 - 120)), Math.round(Z.e0 + 60 + rnd() * (Z.e1 - Z.e0 - 120)), Math.round(360 * rnd())]]; }
    }
    if (O.candidatos_vertido) {                       // patrulla: los vertidos en sitios separados y su sector (el aviso), desplazado al azar
      const C = O.candidatos_vertido.map(([n, e]) => ({ n, e })), V = tomar(C, O.vertidos, O.separacion), R = O.radio_sector;
      d.vertidos = V.map(q => { const L = Math.round(90 + 110 * rnd()); return [q.n, q.e, L, Math.round(L * (0.35 + 0.25 * rnd())), Math.round(360 * rnd()), azar(1000)]; });
      d.sectores = V.map(q => { const a = 2 * Math.PI * rnd(), r = 0.6 * R * Math.sqrt(rnd()); return [Math.round(q.n + r * Math.cos(a)), Math.round(q.e + r * Math.sin(a))]; });
    }
    return d;
  }

  /** Los ajustes del profesor al crear la sala ({cubiertas, fachadas, defectos, manchas, minutos, cobertura}) sobre los
   *  datos de un trabajo (antes de sortear): cuantos desperfectos hay, el tiempo del rescate y la cobertura. */
  static ajustar(O, A) {
    if (!A) return O;
    const d = Object.assign({}, O), n = (v, a, b) => Math.max(a, Math.min(b, Math.round(+v)));
    if (O.candidatos && (A.cubiertas != null || A.fachadas != null)) {
      const C = O.candidatos, cu = n(A.cubiertas ?? C.elegir[0], 0, C.cubiertas.length), fa = n(A.fachadas ?? C.elegir[1], 0, C.fachadas.length);
      d.candidatos = Object.assign({}, C, { elegir: cu + fa ? [cu, fa] : [1, 0] });
    }
    if (O.defectos && A.defectos != null) { const k = n(A.defectos, 1, 30); d.defectos = Array.from({ length: k }, (_, i) => O.defectos[i % O.defectos.length]); }
    if (O.manchas && A.manchas != null) { const k = n(A.manchas, 1, 12); d.manchas = Array.from({ length: k }, (_, i) => O.manchas[i % O.manchas.length]); }
    if (O.limite_s && A.minutos != null) d.limite_s = n(A.minutos, 1, 60) * 60;
    if (O.cubrir && A.cobertura != null) d.cubrir = n(A.cobertura, 30, 100) / 100;
    return d;
  }
  /** El texto de un objetivo con los numeros del trabajo ajustado ("Fotografiar los 12 modulos..."). */
  static textoObjetivo(id, t, d) {
    if (id === "puntos" && d.candidatos) return t.replace(/los \d+ puntos/, `los ${d.candidatos.elegir[0] + d.candidatos.elegir[1]} puntos`);
    if (id === "defectos" && d.defectos) return t.replace(/los \d+ módulos/, `los ${d.defectos.length} módulos`);
    if (id === "manchas" && d.manchas) return t.replace(/las \d+ manchas/, `las ${d.manchas.length} manchas`);
    if (id === "tiempo" && d.limite_s) return t.replace(/\d+ minutos/, `${Math.round(d.limite_s / 60)} minutos`);
    if (id === "cobertura" && d.cubrir) return t.replace(/el \d+ %/, `el ${Math.round(d.cubrir * 100)} %`);
    return t;
  }

  constructor(d, marcar, anotar, mundo) {
    this.d = d; this.marcar = marcar; this.anotar = anotar; this.casa = mundo.casa; this.suelo = mundo.suelo; this.h0 = mundo.h0;
    this.solido = mundo.solido || null;               // (N, E, arriba) -> true si hay un edificio o una instalacion: tapa la vista de la termica
    this.nPaso = 0; this.visto = null;
    this.choque = null; this.avisos = {}; this.t0 = null; this.fotos = 0;
    this.hechos = [];                                                           // inspeccion, manchas, modulos
    if (d.parcela && d.solape) {                                                // fotogrametria: celdas de 5 m de la parcela
      const P = d.parcela; this.celdas = [];
      for (let n = P.n0 + 2.5; n < P.n1; n += 5) for (let e = P.e0 + 2.5; e < P.e1; e += 5) this.celdas.push([n, e, 0]);
    }
    this.termicos = []; this.lectura = null; this.medida = null; this.hechosC = [];   // termica: objetos, lo que mide y los puntos calientes medidos
    if (d.planta) this._planta();
    if (d.racks) this._fabrica();
    if (Array.isArray(d.vertidos)) this._patrulla();
    if (d.carrera) this._carrera();
    if (d.recon && d.vehiculos) d.vehiculos.forEach(([n, e, r], i) => {        // reconocimiento: el motor de cada camion, caliente
      const a = r * D2R, P = [n + 2.3 * Math.cos(a), e + 2.3 * Math.sin(a), this.suelo(n, e) + 1.3];
      this.termicos.push({ tipo: "motor", i, nombre: "motor del camión", T: 55, P0: P, P1: P.slice(), r: 0.9 });
    });
    this.encontrado = false; this.error = null;                                 // busqueda (y localizar el vehiculo)
    this.vig = 0; this.vigHecho = false; this.fotoObj = false;                  // reconocimiento: vigilancia
    this.orb = null; this.yawAnt = null; this.giro = 0;                         // video
  }

  /** Punto (N, E, arriba) de un objetivo: con cota (m sobre el mar) o h (m sobre el suelo). */
  z(n, e, cota, h) { return cota !== undefined ? cota - this.h0 : this.suelo(n, e) + (h || 0); }

  /** Un punto P (N, E, arriba) en la camara del dron (gimbal en grados): x hacia delante, y a la derecha, z hacia abajo
   *  de la imagen, d distancia. */
  static camara(av, gimbal, P, pan = 0) {
    const y = Cuat.euler(av.q)[2] + pan, g = gimbal * D2R, cy = Math.cos(y), sy = Math.sin(y), cg = Math.cos(g), sg = Math.sin(g);
    const v = [P[0] - av.p[0], P[1] - av.p[1], -(P[2] + av.p[2])];
    return { x: v[0] * cy * cg + v[1] * sy * cg - v[2] * sg, y: -v[0] * sy + v[1] * cy, z: v[0] * cy * sg + v[1] * sy * sg + v[2] * cg, d: Math.hypot(v[0], v[1], v[2]) };
  }
  /** Dentro de la imagen (k = 1 el borde; 0,8 bien encuadrado; 0,3 en el centro). */
  static enFoto(c, k, zoom = 1) { return c.x > 0 && Math.abs(c.y) <= k * Math.tan(OPS.CAM_H * D2R) / zoom * c.x && Math.abs(c.z) <= k * Math.tan(OPS.CAM_V * D2R) / zoom * c.x; }

  /** Distancia del rayo que sale del dron por el centro de la camara (rumbo y gimbal) a un segmento P0-P1 (N, E, arriba):
   *  {t: distancia a lo largo del rayo, d: distancia del rayo al segmento}. */
  static rayoSegmento(av, gimbal, P0, P1, pan = 0) {
    const y = Cuat.euler(av.q)[2] + pan, g = gimbal * D2R, u = [Math.cos(y) * Math.cos(g), Math.sin(y) * Math.cos(g), Math.sin(g)];
    const O = [av.p[0], av.p[1], -av.p[2]], v = [P1[0] - P0[0], P1[1] - P0[1], P1[2] - P0[2]], w0 = [O[0] - P0[0], O[1] - P0[1], O[2] - P0[2]];
    const b = u[0] * v[0] + u[1] * v[1] + u[2] * v[2], c = v[0] * v[0] + v[1] * v[1] + v[2] * v[2];
    const dd = u[0] * w0[0] + u[1] * w0[1] + u[2] * w0[2], e = v[0] * w0[0] + v[1] * w0[1] + v[2] * w0[2];
    let s = 0;
    if (c > 1e-9) { const den = c - b * b; s = den > 1e-12 ? Math.max(0, Math.min(1, (e - b * dd) / den)) : 0; }
    const t = Math.max(0, s * b - dd);
    if (c > 1e-9) s = Math.max(0, Math.min(1, (e + t * b) / c));
    const q = [w0[0] + t * u[0] - s * v[0], w0[1] + t * u[1] - s * v[1], w0[2] + t * u[2] - s * v[2]];
    return { t, d: Math.hypot(q[0], q[1], q[2]) };
  }
  /** Lo que mide el medidor puntual de la termica: el objeto termico mas cercano que cae dentro de la cruz del centro, o null. */
  medir(av, gimbal, zoom, pan = 0) {
    let mejor = null;
    for (const o of this.termicos) {
      const r = Operacion.rayoSegmento(av, gimbal, o.P0, o.P1, pan);
      if (r.t > 0.5 && r.d <= o.r + r.t * Math.tan(OPS.RETICULA * D2R) / zoom && (!mejor || r.t < mejor.t)) mejor = { o, t: r.t };
    }
    if (mejor && this.solido && this._tapado(av, gimbal, mejor.t, pan)) return null;
    return mejor ? { T: mejor.o.T, tipo: mejor.o.tipo, nombre: mejor.o.nombre, i: mejor.o.i, dist: mejor.t } : null;
  }
  /** Si un edificio o una instalacion tapa el rayo del centro de la camara antes de llegar a t m (los ultimos 6 m no
   *  cuentan: el objeto esta dentro del solido de su rack o de su unidad). Muestras cada 2,5 m. */
  _tapado(av, gimbal, t, pan = 0) {
    const y = Cuat.euler(av.q)[2] + pan, g = gimbal * D2R, u = [Math.cos(y) * Math.cos(g), Math.sin(y) * Math.cos(g), Math.sin(g)];
    for (let s = 2.5; s < t - 6; s += 2.5) if (this.solido(av.p[0] + s * u[0], av.p[1] + s * u[1], -av.p[2] + s * u[2])) return true;
    return false;
  }

  _aviso(clave, texto, lista) { if (!this.avisos[clave]) { this.avisos[clave] = true; lista.push(texto); } }

  /** Planta fotovoltaica: filas de mesas de paneles que salen de (n0, e0) hacia "rumbo" (grados; 90 = hacia el este, lo
   *  de siempre) y se apilan a su derecha cada "separacion" m, inclinadas con el borde alto hacia la fila siguiente (al
   *  norte con rumbo 90: miran al sur). Cada fila se parte en mesas de "tramo" m (si lo trae) que se asientan en el
   *  terreno; "huecos": filas que son pasillos. En coordenadas de la planta: l a lo largo de la fila, t a traves (t = fila
   *  x separacion). Cada mesa: {fila, t, l0, l1, fondo (en planta), y (suelo), alto (borde de arriba sobre el suelo)}; y
   *  los modulos danados (N, E, arriba). */
  _planta() {
    const P = this.d.planta, c = Math.cos(P.inclinacion * D2R), s = Math.sin(P.inclinacion * D2R), r = (P.rumbo === undefined ? 90 : P.rumbo) * D2R;
    this.pl = { cr: Math.cos(r), sr: Math.sin(r) };
    const tr = P.tramo || P.largo, hueco = P.tramo ? 0.4 : 0;
    this.mesas = []; this.mesasFila = [];
    for (let i = 0; i < P.filas; i++) {
      const t = i * P.separacion, fila = [];
      if (!(P.huecos && P.huecos.includes(i))) for (let l0 = 0; l0 < P.largo - 0.01; l0 += tr) {
        const l1 = Math.min(P.largo, l0 + tr - hueco), [n, e] = this.ne((l0 + l1) / 2, t);
        const M = { fila: i, t, l0, l1, fondo: P.ancho * c, y: this.suelo(n, e), alto: P.h0 + P.ancho * s }; this.mesas.push(M); fila.push(M);
      }
      this.mesasFila.push(fila);
    }
    // modulos danados a simple vista: los pares con el cristal roto y los impares con excrementos de aves, que en la
    // termica dan un punto caliente (la celula tapada se calienta) de 60 a 75 grados
    this.modulos = this.d.defectos.map(([f, x], k) => {
      const F = this.mesasFila[f], M = F.find(q => x >= q.l0 && x <= q.l1) || F[0], [n, e] = this.ne(x, f * P.separacion), y = M.y + P.h0 + P.ancho * s / 2;
      if (k % 2) this.termicos.push({ tipo: "modulo", i: k, nombre: "módulo con excrementos de aves", T: 60 + 5 * ((f * 3 + x) % 4), P0: [n, e, y], P1: [n, e, y], r: 0.3 });
      return [n, e, y];
    });
    // modulos con un diodo de bypass averiado: una de sus tres subcadenas de celulas (una franja de un tercio del modulo,
    // a lo largo de la pendiente) se calienta entera, de 48 a 54 grados; a simple vista no se nota nada
    this.modulosC = (Array.isArray(this.d.calientes) ? this.d.calientes : []).map(([f, x], i) => {
      const F = this.mesasFila[f], M = F.find(q => x >= q.l0 && x <= q.l1) || F[0], [n, e] = this.ne(x, f * P.separacion), y = M.y + P.h0 + P.ancho * s / 2;
      const dl = ((f + x) % 3 - 1) * 0.33, [n0, e0] = this.ne(x + dl, f * P.separacion - 0.9 * c), [n1, e1] = this.ne(x + dl, f * P.separacion + 0.9 * c);
      this.termicos.push({ tipo: "modulo", i, nombre: "módulo con un diodo de bypass averiado", T: 48 + 2 * ((f * 5 + x) % 4), P0: [n0, e0, y - 0.9 * s], P1: [n1, e1, y + 0.9 * s], r: 0.16 });
      return [n, e, y];
    });
  }

  /** Fabrica (trabajo de SABIC): los objetos de la termica (puntos calientes, tuberias de vapor de sus racks, la fuga,
   *  las chimeneas y la antorcha), la valvula de la fuga y su zona ATEX, y la placa de la antorcha. */
  _fabrica() {
    const d = this.d, T = this.termicos;
    this.racksPista = [];
    d.puntosCalientes.forEach(([ri, ti, f, Tc], i) => {
      const R = d.racks[ri], tb = Industria.tuberias(R)[ti], y = this.suelo((R.n0 + R.n1) / 2, (R.e0 + R.e1) / 2) + tb.yc;
      const L = Math.hypot(tb.n1 - tb.n0, tb.e1 - tb.e0), un = (tb.n1 - tb.n0) / L, ue = (tb.e1 - tb.e0) / L, n = tb.n0 + f * (tb.n1 - tb.n0), e = tb.e0 + f * (tb.e1 - tb.e0);
      T.push({ tipo: "caliente", i, nombre: `aislamiento roto en el rack ${R.nombre}`, T: Tc, P0: [n - 0.6 * un, e - 0.6 * ue, y], P1: [n + 0.6 * un, e + 0.6 * ue, y], r: tb.d / 2 + 0.05 });
      if (!this.racksPista.includes(ri)) {
        this.racksPista.push(ri);
        for (const v of Industria.tuberias(R)) if (v.color === 6)                  // las de vapor de ese rack: calientes de verdad
          T.push({ tipo: "vapor", i: -1, nombre: `tubería de vapor del rack ${R.nombre}`, T: 62, P0: [v.n0, v.e0, y - tb.yc + v.yc], P1: [v.n1, v.e1, y - tb.yc + v.yc], r: v.d / 2 + 0.03 });
      }
    });
    for (const C of d.chimeneas) {                                             // chimeneas: la parte de arriba templada
      const y = this.suelo(C.n, C.e); T.push({ tipo: "chimenea", i: -1, nombre: "chimenea", T: 85, P0: [C.n, C.e, y + 0.85 * C.alto], P1: [C.n, C.e, y + C.alto], r: C.radio + 0.3 });
    }
    const A = d.antorcha, ya = this.suelo(A.n, A.e);
    this.boca = [A.n, A.e, ya + A.alto];
    T.push({ tipo: "antorcha", i: -1, nombre: d.piloto ? "llama del piloto de la antorcha" : "boca de la antorcha (piloto apagado)", T: d.piloto ? 600 : 70,
             P0: [A.n, A.e, ya + A.alto - 1], P1: [A.n, A.e, ya + A.alto + (d.piloto ? 1.5 : 0)], r: A.radio });
    // la placa, en la boca de la antorcha, de cara al despegue
    const a = Math.atan2(this.casa[1] - A.e, this.casa[0] - A.n);
    this.placa = [A.n + (A.radio + 0.3) * Math.cos(a), A.e + (A.radio + 0.3) * Math.sin(a), ya + A.alto - 2.2, a * R2D];
    this._fuga();
  }
  /** La valvula de la fuga (d.fuga: unidad, estructura y cara), su objeto termico (gas frio) y la zona ATEX de su unidad. */
  _fuga() {
    const d = this.d, [ui, vi, lado] = d.fuga, U = d.unidades[ui], [e, n, h, largo, ancho, rumbo] = U.valvulas[vi], r = rumbo * D2R;
    const x = lado === 0 ? largo / 2 + 0.3 : lado === 1 ? -largo / 2 - 0.3 : 0, z = lado === 2 ? ancho / 2 + 0.3 : lado === 3 ? -ancho / 2 - 0.3 : 0;
    const N = n + x * Math.cos(r) - z * Math.sin(r), E = e + x * Math.sin(r) + z * Math.cos(r), up = this.suelo(n, e) + h;
    this.valvula = [N, E, up]; this.unidadFuga = U; this.hechoFuga = false;
    this.termicos = this.termicos.filter(o => o.tipo !== "fuga");
    this.termicos.push({ tipo: "fuga", i: -1, nombre: `fuga de gas en la unidad ${U.nombre}`, T: -15, P0: [N, E, up], P1: [N, E, up], r: 0.6 });
  }
  /** Orden del profesor: la fuga pasa a la unidad mas cercana a (N, E), en su estructura mas cercana. */
  moverFuga(N, E) {
    const d = this.d; if (!d.racks) return false;
    const cen = U => [U.poligono.reduce((s, p) => s + p[0], 0) / U.poligono.length, U.poligono.reduce((s, p) => s + p[1], 0) / U.poligono.length];
    let ui = 0; d.unidades.forEach((U, i) => { const c = cen(U), c0 = cen(d.unidades[ui]); if (Math.hypot(c[0] - N, c[1] - E) < Math.hypot(c0[0] - N, c0[1] - E)) ui = i; });
    const V = d.unidades[ui].valvulas; let vi = 0; V.forEach((v, i) => { if (Math.hypot(v[1] - N, v[0] - E) < Math.hypot(V[vi][1] - N, V[vi][0] - E)) vi = i; });
    d.fuga = [ui, vi, d.fuga[2]]; this._fuga(); return true;
  }
  /** De coordenadas de la planta (l a lo largo de la fila, t a traves) a (N, E), y al reves. */
  ne(l, t) { const P = this.d.planta, { cr, sr } = this.pl; return [P.n0 + l * cr + t * sr, P.e0 + l * sr - t * cr]; }
  lt(N, E) { const P = this.d.planta, { cr, sr } = this.pl, dn = N - P.n0, de = E - P.e0; return [dn * cr + de * sr, dn * sr - de * cr]; }

  /** Un paso de la fisica. info: {gimbal (grados), grabando (video)}. */
  paso(pAnt, av, dt, info) {
    const d = this.d, T = [], N = av.p[0], E = av.p[1], up = -av.p[2], agl = up - this.suelo(N, E), t = av.t, m = this.marcar;
    if (av.estado !== "volando") return T;
    if (this.t0 === null && !av.posado && !av.enTierra) {                       // despegue: empieza a contar el tiempo
      this.t0 = t;
      if (d.pista) { const [dd, tt] = this.ejePista(N, E), ok = dd > -30 && dd < d.pista.largo + 30 && Math.abs(tt) < d.pista.ancho / 2 + 15; m("despegue", ok ? "ok" : "mal"); if (!ok) this._aviso("despegue", "No has despegado de la pista", T); }
    }
    // ---- choques: paneles de la planta, faro ----
    if (d.planta && !av.posado) {                    // solo las mesas de la fila mas cercana y sus vecinas
      const [l, tt] = this.lt(N, E), i0 = Math.round(tt / d.planta.separacion);
      for (let i = i0 - 1; i <= i0 + 1; i++) for (const M of this.mesasFila[i] || [])
        if (Math.abs(tt - M.t) < M.fondo / 2 + 0.15 && l > M.l0 - 0.15 && l < M.l1 + 0.15 && up - M.y < M.alto + 0.15) this.choque = "choque con los paneles";
    }
    if (d.faro) {
      const F = d.faro;
      if (Math.hypot(N - F.n, E - F.e) < F.radio + 0.3 && up - this.suelo(F.n, F.e) < F.alto) this.choque = "choque con el faro";
    }
    if (d.carrera && !av.posado) this._pasoCarrera(pAnt, av, T);
    if (this.choque) return T;
    // ---- normas del operador (el dron; el UAV de la patrulla lleva las suyas; la carrera, ninguna) ----
    if (Array.isArray(d.vertidos)) {
      if (this.t0 !== null && !av.enTierra && !av.posado) {
        const lejos = Math.hypot(N - this.centroPista()[0], E - this.centroPista()[1]) > d.radio_pista;
        if (lejos && agl < d.h_min) { m("altura", "mal"); this._aviso("altura", `¡Por debajo de ${d.h_min} m lejos de la pista! Sube`, T); }
        if (agl > d.techo) { m("techo", "mal"); this._aviso("techo", `¡Por encima de ${d.techo} m! Baja`, T); }
      }
    } else if (d.recon) {                            // reconocimiento: entre la minima y el techo (salvo junto al lanzamiento)
      if (this.t0 !== null && !av.posado && !av.enTierra) {
        const R = d.recon, lejos = Math.hypot(N - this.casa[0], E - this.casa[1]) > R.radio_despegue;
        if (agl > R.techo) { m("techo", "mal"); this._aviso("techo", `¡Por encima de ${R.techo} m! Baja`, T); }
        // en la toma automatica (el Grajo) baja a su altura de entrada: la minima no cuenta
        if (lejos && agl < R.minima && !info.aterrizando) { m("minima", "mal"); this._aviso("minima", `¡Por debajo de ${R.minima} m lejos del lanzamiento! Sube`, T); }
      }
    } else if (!d.carrera) {
    if (agl > OPS.TECHO) { m("techo", "mal"); this._aviso("techo", "¡Por encima de 120 m de altura! Baja", T); }
    if (Math.hypot(N - this.casa[0], E - this.casa[1]) > OPS.VLOS) { m("vlos", "mal"); this._aviso("vlos", "¡Más de 500 m del piloto! Ya no lo ves: vuelve", T); }
    if (Math.hypot(N - OPS.ARP.n, E - OPS.ARP.e) < OPS.ARP.r) { m("zona", "mal"); this._aviso("zona", `¡Dentro de la zona del ${OPS.ARP.nombre}!`, T); }
    }
    // ---- agricultura: nunca a menos de 5 m sobre el cultivo ----
    if (d.manchas) {
      const P = d.parcela;
      const enParcela = P.poligono ? Operacion.dentro(P.poligono, N, E) : N > P.n0 && N < P.n1 && E > P.e0 && E < P.e1;
      if (enParcela && agl < d.minima && !av.posado) { m("baja", "mal"); this._aviso("baja", `¡A ${agl.toFixed(1)} m del cultivo! No bajes de ${d.minima} m`, T); }
    }
    // ---- paneles: nunca a menos de 3 m sobre ellos ----
    if (d.planta && !av.posado) {
      const P = d.planta, [l, tt] = this.lt(N, E), M0 = this.mesas[0], f = M0.fondo;
      if (tt > -f && tt < (P.filas - 1) * P.separacion + f && l > 0 && l < P.largo && agl < M0.alto + d.minima) {
        m("baja", "mal"); this._aviso("baja", `¡A menos de ${d.minima} m de los paneles! Sube`, T);
      }
    }
    // ---- termica: lo que mide el medidor puntual (y, sostenido sobre un punto caliente o la fuga, se da por medido) ----
    const zoom = info.zoom || 1;
    this.lectura = info.termica && this.termicos.length ? this.medir(av, info.gimbal, zoom, info.pan || 0) : null;
    const L = this.lectura;
    if (L && (L.tipo === "caliente" || L.tipo === "fuga") && !(L.tipo === "fuga" ? this.hechoFuga : this.hechosC[L.i])) {
      const lim = L.tipo === "fuga" ? d.dist_fuga : d.dist_caliente, clave = L.tipo + L.i;
      if (L.dist / zoom > lim) { this.medida = null; this._aviso("lejos" + clave, `${L.tipo === "fuga" ? "La fuga" : "Un punto caliente"} está a ${L.dist.toFixed(0)} m: acércate a menos de ${lim} m o usa más zoom para medirlo`, T); }
      else {
        this.medida = this.medida && this.medida.clave === clave ? { clave, t: this.medida.t + dt } : { clave, t: dt };
        if (this.medida.t >= d.medir_s) {
          this.medida = null;
          if (L.tipo === "fuga") { this.hechoFuga = true; m("fuga", "ok"); T.push(`¡Fuga localizada! ${L.nombre}: gas a ${L.T} °C · posición enviada`); }
          else {
            this.hechosC[L.i] = true; const k = this.hechosC.filter(Boolean).length;
            T.push(`Punto caliente ${k}: ${L.nombre}, ${L.T} °C ✓ (${k}/${d.puntosCalientes.length})`);
            if (k === d.puntosCalientes.length) m("calientes", "ok");
          }
          this._todo(t);
        }
      }
    } else this.medida = null;
    if (L && L.tipo === "vapor") this._aviso("vapor", "Tubería de vapor a 62 °C: está caliente por diseño (va aislada), no es una avería", T);
    // ---- fabrica: zona ATEX alrededor de la unidad con la fuga y nunca a menos de 10 m sobre las unidades ----
    if (d.racks) {
      const A = this.unidadFuga.poligono;
      if (Operacion.dentro(A, N, E) || Operacion.aBorde(A, N, E) < d.atex) { m("atex", "mal"); this._aviso("atex", `¡Dentro de la zona ATEX de la unidad ${this.unidadFuga.nombre}! Sal: no se puede volar a menos de ${d.atex} m`, T); }
      for (const U of d.unidades)
        if (!av.posado && Operacion.dentro(U.poligono, N, E) && agl < U.alto + d.sobre_unidades) { m("unidades", "mal"); this._aviso("unidades", `¡A menos de ${d.sobre_unidades} m por encima de la unidad ${U.nombre}! Sube`, T); }
      if (this.t0 !== null && t - this.t0 > d.limite_s && !this.tTodo) { m("tiempo", "mal"); this._aviso("tiempo", "Se han acabado los 30 minutos: termina lo que puedas y vuelve", T); }
    }
    // ---- reconocimiento: la vigilancia (el objetivo en la imagen), el ruido y el tiempo ----
    if (d.recon) {
      const R = d.recon;
      if (R.objetivo && d.vehiculos) {
        const [vn, ve] = d.vehiculos[0], c = Operacion.camara(av, info.gimbal, [vn, ve, this.suelo(vn, ve) + 1.5], info.pan || 0);
        if (this.t0 !== null && !av.posado && Math.hypot(N - vn, E - ve) < R.ruido_r && agl < R.ruido_h) { m("ruido", "mal"); this._aviso("ruido", `¡Te pueden oír! A menos de ${R.ruido_r} m del objetivo no bajes de ${R.ruido_h} m`, T); }
        if (!this.vigHecho && Operacion.enFoto(c, 0.7, zoom) && c.d / zoom <= R.dist_vigilar) {
          const antes = Math.floor(this.vig / 30); this.vig += dt;
          if (this.vig >= R.vigilar_s) { this.vigHecho = true; m("vigilar", "ok"); T.push(`¡Vigilancia completa (${R.vigilar_s} s)! Haz una foto del vehículo con la cruz encima (F)`); }
          else if (Math.floor(this.vig / 30) > antes) T.push(`Vigilando: ${Math.floor(this.vig)} s de ${R.vigilar_s}`);
        }
      }
      if (R.limite_s && this.t0 !== null && t - this.t0 > R.limite_s && !this.tTodo && !this.encontrado) { m("tiempo", "mal"); this._aviso("tiempo", "Se ha acabado el tiempo: termina lo que puedas y vuelve", T); }
    }
    // ---- busqueda: el tiempo ----
    if (d.zona && !this.encontrado && this.t0 !== null && t - this.t0 > d.limite_s) { m("tiempo", "mal"); this._aviso("tiempo", "Se ha acabado el tiempo: el equipo de tierra sigue buscando", T); }
    // ---- video: giro suave y orbita ----
    if (d.faro) {
      const yaw = Cuat.euler(av.q)[2];
      if (this.yawAnt !== null && dt > 0) this.giro += (Math.abs(opDesenrollar(yaw - this.yawAnt)) / dt - this.giro) * Math.min(1, dt / 0.2);
      this.yawAnt = yaw;
      if (info.grabando && this.giro > d.giro_max * D2R) { m("suave", "mal"); this._aviso("suave", `Tirón en el vídeo: giro de ${(this.giro * R2D).toFixed(0)}°/s (máximo ${d.giro_max})`, T); }
      const F = d.faro, r = Math.hypot(N - F.n, E - F.e), c = Operacion.camara(av, info.gimbal, [F.n, F.e, this.suelo(F.n, F.e) + 0.6 * F.alto]);
      const centrado = c.x > 0 && Math.abs(c.y) <= Math.tan(d.centrado * D2R) * c.x && Math.abs(c.z) <= 0.9 * Math.tan(OPS.CAM_V * D2R) * c.x;
      const vale = info.grabando && r >= d.orbita[0] && r <= d.orbita[1] && centrado, a = Math.atan2(E - F.e, N - F.n);
      if (!this.avisos.orbita) {
        if (vale) {
          if (!this.orb) { this.orb = { acc: 0, prev: a, hmin: up, hmax: up, fuera: 0 }; T.push("Órbita: empieza"); }
          const O = this.orb; O.acc += opDesenrollar(a - O.prev); O.prev = a; O.hmin = Math.min(O.hmin, up); O.hmax = Math.max(O.hmax, up); O.fuera = 0;
          if (O.hmax - O.hmin > 2 * d.variacion) { this.orb = null; T.push(`Cambio de altura de más de ${2 * d.variacion} m: la órbita empieza de nuevo`); }
          else if (Math.abs(O.acc) >= 2 * Math.PI * 0.92) { m("orbita", "ok"); this._aviso("orbita", "¡Órbita completa! Vuelve al punto de despegue", T); this.orb = null; }
        } else if (this.orb) {
          this.orb.prev = a; this.orb.fuera += dt;
          if (this.orb.fuera > 1) {
            T.push("Órbita perdida: " + (!info.grabando ? "no estás grabando" : r < d.orbita[0] ? "demasiado cerca del faro" : r > d.orbita[1] ? "demasiado lejos del faro" : "el faro se ha salido del centro de la imagen"));
            this.orb = null;
          }
        }
      }
    }
    return T;
  }

  /** Una foto (boton de foto del dron comercial): lo que vale para el trabajo y el aviso. */
  foto(av, gimbal, cam = {}) {
    const d = this.d, T = [], N = av.p[0], E = av.p[1], up = -av.p[2], agl = up - this.suelo(N, E), m = this.marcar, zoom = cam.zoom || 1, ter = !!cam.termica;
    this.fotos++;
    if (av.estado !== "volando" || av.posado) return T;
    if (d.recon) {                                     // reconocimiento: con la cruz encima y no demasiado lejos para su zoom
      const R = d.recon, pan = cam.pan || 0, y = Cuat.euler(av.q)[2] + pan, g = gimbal * D2R;
      const cruz = () => { if (Math.sin(g) > -0.02) return null; const s = (up - this.suelo(N, E)) / -Math.sin(g); return [N + s * Math.cos(g) * Math.cos(y), E + s * Math.cos(g) * Math.sin(y)]; };
      let motivo = null;
      if (R.puntos) {
        R.puntos.forEach((q, i) => {
          if (this.hechos[i]) return;
          const c = Operacion.camara(av, gimbal, [q.n, q.e, this.suelo(q.n, q.e) + 1], pan);
          if (!Operacion.enFoto(c, 1, zoom)) return;
          if (c.d / zoom > R.dist_foto) { motivo = motivo || `el punto ${i + 1} está demasiado lejos (${c.d.toFixed(0)} m): acércate o usa más zoom`; return; }
          if (!Operacion.enFoto(c, 0.5, zoom)) { motivo = motivo || `el punto ${i + 1} sale en el borde: ponle la cruz encima`; return; }
          this.hechos[i] = true; const k = this.hechos.filter(Boolean).length, hay = (d.conVehiculo || []).includes(i);
          T.push(`Punto ${i + 1} (${q.nombre}) ✓ ${hay ? "· HAY UN VEHÍCULO en el punto" : "· sin vehículos"} (${k}/${R.puntos.length})`);
          if (k === R.puntos.length) { m("puntos", "ok"); m("vehiculos", "ok"); this.tTodo = this.tTodo || av.t; m("tiempo", this.tTodo - this.t0 <= R.limite_s ? "ok" : "mal"); T.push("¡Itinerario reconocido! Vuelve al punto de lanzamiento"); }
        });
      }
      if (R.objetivo && d.vehiculos && !this.fotoObj) {
        const [vn, ve] = d.vehiculos[0], c = Operacion.camara(av, gimbal, [vn, ve, this.suelo(vn, ve) + 1.5], pan);
        if (Operacion.enFoto(c, 0.5, zoom) && c.d / zoom <= R.dist_foto) {
          if (this.vigHecho) { this.fotoObj = true; m("foto", "ok"); T.push("Foto del vehículo ✓ · vuelve al punto de lanzamiento"); }
          else T.push(`Foto del vehículo; la vigilancia sigue: ${Math.floor(this.vig)} s de ${R.vigilar_s}`);
        } else if (Operacion.enFoto(c, 1, zoom)) motivo = motivo || (c.d / zoom > R.dist_foto ? "el vehículo está demasiado lejos para la foto" : "el vehículo sale en el borde: ponle la cruz encima");
      }
      if (R.zona && d.vehiculos && !this.encontrado) {
        const [vn, ve] = d.vehiculos[0], c = Operacion.camara(av, gimbal, [vn, ve, this.suelo(vn, ve) + 1.5], pan);
        if (Operacion.enFoto(c, 0.3, zoom) && c.d / zoom <= R.dist_foto) {
          const est = cruz() || [N, E]; this.error = Math.hypot(est[0] - vn, est[1] - ve); this.encontrado = true; this.tTodo = this.tTodo || av.t;
          m("localizar", "ok"); m("posicion", this.error <= R.error ? "ok" : "mal"); m("tiempo", this.t0 !== null && av.t - this.t0 <= R.limite_s ? "ok" : "mal");
          T.push(`¡Camión localizado! Posición enviada a ${this.error.toFixed(0)} m de la real` + (this.error <= R.error ? "" : ": demasiado error (con la cámara más inclinada hacia abajo sale mejor)"));
        } else if (Operacion.enFoto(c, 1, zoom) && c.d / zoom <= 2 * R.dist_foto) motivo = motivo || "el camión sale en la foto, pero no en el centro: céntralo y acércate";
      }
      if (!T.length) T.push(motivo ? "Foto no válida: " + motivo : `Foto ${this.fotos}`);
      return T;
    }
    if (Array.isArray(d.vertidos)) {                   // patrulla: la cruz de la torreta sobre la mancha, no demasiado lejos para su zoom
      const pan = cam.pan || 0, y = Cuat.euler(av.q)[2] + pan, g = gimbal * D2R;
      let motivo = null;
      d.vertidos.forEach(([vn, ve, L, A, rv], i) => {
        if (this.hechos[i]) return;
        const h = this.suelo(vn, ve), c = Operacion.camara(av, gimbal, [vn, ve, h], pan);
        if (!Operacion.enFoto(c, 1, zoom)) return;
        if (c.d / zoom > d.dist_foto) { motivo = motivo || `el vertido ${i + 1} está demasiado lejos para identificarlo (${(c.d / 1000).toFixed(1).replace(".", ",")} km): acércate o usa más zoom`; return; }
        if (Math.sin(g) > -0.01) { motivo = motivo || "la cruz no apunta al agua: baja la torreta"; return; }
        const s = (up - h) / -Math.sin(g), hn = N + s * Math.cos(g) * Math.cos(y), he = E + s * Math.cos(g) * Math.sin(y);    // la cruz en el agua
        const r = rv * D2R, dn = hn - vn, de = he - ve, a = dn * Math.cos(r) + de * Math.sin(r), b = -dn * Math.sin(r) + de * Math.cos(r);
        if ((a / (L / 2)) ** 2 + (b / (A / 2)) ** 2 > 1.4) { motivo = motivo || `el vertido ${i + 1} sale en la foto, pero la cruz no está sobre la mancha: céntrala`; return; }
        this.hechos[i] = true; const k = this.hechos.filter(Boolean).length, err = Math.hypot(dn, de); this.errores[i] = err;
        T.push(`Vertido ${i + 1} ✓ (${k}/${d.vertidos.length}) · posición enviada, a ${err.toFixed(0)} m del centro de la mancha`);
        if (k === d.vertidos.length) { m("vertidos", "ok"); this._todo(av.t); T.push("¡Los tres vertidos localizados! Vuelve a San Javier"); }
      });
      if (!T.length) T.push(motivo ? "Foto no válida: " + motivo : "Foto sin ningún vertido");
      return T;
    }
    if (d.puntos) {                                    // inspeccion: cada punto bien encuadrado, cerca, de frente o desde arriba
      let motivo = null;
      d.puntos.forEach((q, i) => {
        if (this.hechos[i]) return;
        const P = [q.n, q.e, this.z(q.n, q.e, q.cota, q.h)], c = Operacion.camara(av, gimbal, P);
        if (!Operacion.enFoto(c, 1)) return;
        const cara = q.normal !== undefined ? ((N - P[0]) * Math.cos(q.normal * D2R) + (E - P[1]) * Math.sin(q.normal * D2R)) / c.d : (up - P[2]) / c.d;
        if (c.d > d.dist[1]) motivo = motivo || `punto ${i + 1} demasiado lejos (${c.d.toFixed(0)} m; acércate a menos de ${d.dist[1]} m)`;
        else if (c.d < d.dist[0]) motivo = motivo || `punto ${i + 1} demasiado cerca`;
        else if (!Operacion.enFoto(c, 0.8)) motivo = motivo || `punto ${i + 1} en el borde de la foto: encuádralo`;
        else if (cara < 0.5) motivo = motivo || `punto ${i + 1}: ${q.normal !== undefined ? "la fachada se fotografía de frente" : "la cubierta se fotografía desde arriba"}`;
        else { this.hechos[i] = true; T.push(`Punto ${i + 1}: ${q.nombre} ✓ (${this.hechos.filter(Boolean).length}/${d.puntos.length})`); }
      });
      if (this.hechos.filter(Boolean).length === d.puntos.length) m("puntos", "ok");
      if (!T.length) T.push(motivo ? "Foto no válida: " + motivo : "Foto sin ningún punto de inspección");
    }
    if (d.solape) {                                    // fotogrametria: cobertura de cada foto vertical a la altura pedida
      if (gimbal > d.gimbal) T.push(`Foto no válida: la cámara no mira abajo (${gimbal.toFixed(0)}°; hace falta ${d.gimbal}° o más)`);
      else if (agl < d.altura[0] || agl > d.altura[1]) T.push(`Foto no válida: a ${agl.toFixed(0)} m (entre ${d.altura[0]} y ${d.altura[1]} m)`);
      else {
        const y = Cuat.euler(av.q)[2], cy = Math.cos(y), sy = Math.sin(y), lv = agl * Math.tan(OPS.CAM_V * D2R), lh = agl * Math.tan(OPS.CAM_H * D2R);
        let dentro = 0;
        for (const q of this.celdas) {
          const dn = q[0] - N, de = q[1] - E;
          if (Math.abs(dn * cy + de * sy) <= lv && Math.abs(-dn * sy + de * cy) <= lh) { q[2]++; dentro++; }
        }
        if (!dentro) T.push("La foto no cae en la parcela");
        else {
          const pct = this.cobertura();
          T.push(`Foto válida · parcela cubierta con solape: ${(pct * 100).toFixed(0)} %`);
          if (pct >= d.cubrir) { m("cobertura", "ok"); this._aviso("cobertura", "¡Parcela cubierta! Vuelve al punto de despegue", T); }
        }
      }
    }
    if (d.zona && d.persona && !this.encontrado) {     // busqueda: foto con la persona en el centro y la posicion enviada
      const sp = this.suelo(d.persona[0], d.persona[1]), c = Operacion.camara(av, gimbal, [d.persona[0], d.persona[1], sp + 0.9]);
      if (Operacion.enFoto(c, 0.3) && c.d <= d.dist) {
        const y = Cuat.euler(av.q)[2], g = gimbal * D2R;
        let est = [N, E];
        if (Math.sin(g) < -0.05) { const k = (sp - up) / Math.sin(g); est = [N + k * Math.cos(y) * Math.cos(g), E + k * Math.sin(y) * Math.cos(g)]; }
        this.error = Math.hypot(est[0] - d.persona[0], est[1] - d.persona[1]); this.encontrado = true;
        m("localizar", "ok"); m("posicion", this.error <= 10 ? "ok" : "mal");
        m("tiempo", this.t0 !== null && av.t - this.t0 <= d.limite_s ? "ok" : "mal");
        T.push(`¡Encontrado! Posición enviada a ${this.error.toFixed(1)} m de la real` + (this.error <= 10 ? "" : ": demasiado error (inclina la cámara hacia él)"));
      } else if (Operacion.enFoto(c, 1) && c.d <= 2 * d.dist) T.push("Sale en la foto, pero no en el centro: céntralo y acércate para enviar su posición");
      else T.push(`Foto ${this.fotos}: no se le ve`);
    }
    if (d.manchas) {                                   // agricultura: cada mancha desde arriba y a la altura pedida
      let motivo = null;
      d.manchas.forEach(([mn, me], i) => {
        if (this.hechos[i]) return;
        const sm = this.suelo(mn, me), c = Operacion.camara(av, gimbal, [mn, me, sm]);
        if (!Operacion.enFoto(c, 0.9)) return;
        const h = up - sm;
        if (gimbal > d.gimbal) motivo = motivo || `la cámara tiene que mirar abajo (${d.gimbal}° o más)`;
        else if (h < d.altura[0] || h > d.altura[1]) motivo = motivo || `a ${h.toFixed(0)} m de la mancha ${i + 1} (entre ${d.altura[0]} y ${d.altura[1]} m)`;
        else { this.hechos[i] = true; T.push(`Mancha ${i + 1} ✓ (${this.hechos.filter(Boolean).length}/${d.manchas.length})`); }
      });
      if (this.hechos.filter(Boolean).length === d.manchas.length) m("manchas", "ok");
      if (!T.length) T.push(motivo ? "Foto no válida: " + motivo : "Foto sin ninguna mancha");
    }
    if (d.planta) {                                    // paneles: cada modulo danado, desde arriba y de 4 a 20 m (con zoom, la distancia equivalente)
      let motivo = null;
      // vale(i): null si esa averia se ve con la camara puesta, o por que no; ok(i): el texto de la foto buena
      const revisar = (lista, hechos, vale, nombre, ok, id) => lista.forEach((P, i) => {
        if (hechos[i]) return;
        const c = Operacion.camara(av, gimbal, P), de = c.d / zoom;
        if (!Operacion.enFoto(c, 1, zoom)) return;
        const no = vale(i);
        if (no) motivo = motivo || no;
        else if (gimbal > d.gimbal) motivo = motivo || `los paneles se fotografían desde arriba (cámara a ${d.gimbal}° o más)`;
        else if (de > d.dist[1]) motivo = motivo || `${nombre} ${i + 1} demasiado lejos (${c.d.toFixed(0)} m; a menos de ${d.dist[1]} m${zoom > 1 ? " con este zoom" : ""})`;
        else if (de < d.dist[0]) motivo = motivo || `${nombre} ${i + 1} demasiado cerca`;
        else if (!Operacion.enFoto(c, 0.8, zoom)) motivo = motivo || `${nombre} ${i + 1} en el borde de la foto: encuádralo`;
        else {
          hechos[i] = true;
          T.push(`${ok(i)} ✓ (${hechos.filter(Boolean).length}/${lista.length})`);
          if (hechos.filter(Boolean).length === lista.length) m(id, "ok");
        }
      });
      revisar(this.modulos, this.hechos, i => i % 2 === 0 && ter ? "con la térmica el cristal roto apenas se distingue: cambia a la cámara normal (C)" : null, "módulo",
        i => i % 2 === 0 ? `Cristal roto (módulo ${i + 1})` : `Excrementos de aves (módulo ${i + 1})` + (ter ? ", punto caliente en la térmica" : ""), "defectos");
      revisar(this.modulosC, this.hechosC, i => ter ? null : `el diodo averiado ${i + 1} solo se ve con la cámara térmica (C)`, "diodo", i => `Diodo de bypass averiado ${i + 1}`, "calientes");
      if (!T.length) T.push(motivo ? "Foto no válida: " + motivo : "Foto sin ningún módulo dañado");
    }
    if (d.racks) {                                     // fabrica: la placa de la antorcha (zoom) y su piloto (termica)
      const A = d.antorcha, P = d.placa, h = Math.hypot(N - A.n, E - A.e);
      if (!this.hechoPlaca) {
        const c = Operacion.camara(av, gimbal, this.placa);
        const frente = Math.cos(opDesenrollar(Math.atan2(E - this.placa[1], N - this.placa[0]) - this.placa[3] * D2R));   // 1 de frente, 0 de lado
        if (Operacion.enFoto(c, 0.5, zoom)) {
          if (frente < 0.5) T.push("La placa no se ve desde este lado: está en la cara de la antorcha que da al despegue");
          else if (ter) T.push("Con la térmica no se lee la placa: cambia a la cámara normal (C)");
          else if (zoom < P.zoom) T.push(`La placa no se lee: hace falta un zoom de ${P.zoom}x o más (ahora ${zoom}x)`);
          else if (agl < P.altura) T.push(`Foto no válida: a ${agl.toFixed(0)} m de altura (desde más de ${P.altura} m)`);
          else if (h < P.distancia) T.push(`Foto no válida: a ${h.toFixed(0)} m de la antorcha (desde más de ${P.distancia} m)`);
          else { this.hechoPlaca = true; m("placa", "ok"); T.push(`Placa de la antorcha: «${d.placaTxt}» ✓`); this._todo(av.t); }
        }
      }
      if (!this.hechoPiloto) {
        const c = Operacion.camara(av, gimbal, this.boca);
        if (Operacion.enFoto(c, 0.5, zoom)) {
          if (!ter) T.push("Para ver el piloto de la antorcha hace falta la cámara térmica (C)");
          else if (c.d / zoom > 60) T.push(`La boca de la antorcha sale muy pequeña (a ${c.d.toFixed(0)} m): acércate o usa más zoom`);
          else { this.hechoPiloto = true; m("piloto", "ok"); T.push(d.piloto ? "Piloto de la antorcha: ENCENDIDO (la llama, a más de 150 °C) ✓" : "Piloto de la antorcha: APAGADO (la boca, a 70 °C): hay que avisar a la sala de control ✓"); this._todo(av.t); }
        }
      }
      if (!T.length) T.push(`Foto ${this.fotos}${ter ? " (térmica)" : ""}`);
    }
    if (d.faro) T.push("Este trabajo es de vídeo: pulsa V para grabar");
    return T;
  }

  /** Parte de la parcela cubierta con solape (0-1). */
  cobertura() { return this.celdas.filter(q => q[2] >= this.d.solape).length / this.celdas.length; }

  /** Al acabar el vuelo: aterrizar en el punto de despegue y con reserva de bateria; y el resumen en los objetivos. */
  final(final, av, info) {
    const d = this.d, a = this.anotar, n = this.hechos.filter(Boolean).length;
    if (final === "aterrizado") {
      const dc = Math.hypot(av.p[0] - this.casa[0], av.p[1] - this.casa[1]);
      this.marcar("casa", dc <= (d.recon ? d.recon.casa_m : OPS.CASA) ? "ok" : "mal"); a("casa", `a ${dc.toFixed(1)} m`);
      this.marcar("reserva", info.bateria >= OPS.RESERVA ? "ok" : "mal"); a("reserva", `${info.bateria.toFixed(0)} %`);
    }
    if (d.puntos) a("puntos", `${n} de ${d.puntos.length}`);
    if (d.recon) {
      const R = d.recon;
      if (R.puntos) { a("puntos", `${n} de ${R.puntos.length}`); if (this.tTodo) a("tiempo", opMMSS(this.tTodo - this.t0)); }
      if (R.objetivo) a("vigilar", `${Math.floor(Math.min(this.vig, R.vigilar_s))} s de ${R.vigilar_s}`);
      if (R.zona && this.error !== null) a("posicion", `error ${this.error.toFixed(0)} m`);
    }
    if (d.solape) a("cobertura", `${(this.cobertura() * 100).toFixed(0)} %`);
    if (d.zona && this.error !== null) a("posicion", `error ${this.error.toFixed(1)} m`);
    if (d.manchas) a("manchas", `${n} de ${d.manchas.length}`);
    if (d.planta) a("defectos", `${n} de ${this.modulos.length}`);
    if (d.planta && this.modulosC.length) a("calientes", `${this.hechosC.filter(Boolean).length} de ${this.modulosC.length}`);
    if (d.racks) {
      a("calientes", `${this.hechosC.filter(Boolean).length} de ${d.puntosCalientes.length}`);
      if (this.tTodo) { this.marcar("tiempo", "ok"); a("tiempo", opMMSS(this.tTodo - this.t0)); }
    }
    if (d.carrera) {
      const c = this.carr; a("secuencia", c.fuera !== null ? `descalificado: te saltaste el ${c.fuera + 1}` : `${c.k} de ${this.obst.length}`);
      if (c.tFin !== null) a("tiempo", opCrono(c.tFin - c.t0));
      this.marcar("choques", final.startsWith("roto") ? "mal" : "ok");
    }
    if (Array.isArray(d.vertidos)) {
      a("vertidos", `${n} de ${d.vertidos.length}`);
      if (this.tTodo) { this.marcar("tiempo", "ok"); a("tiempo", opMMSS(this.tTodo - this.t0)); }
      if (final === "aterrizado") {
        const [dd, tt] = this.ejePista(av.p[0], av.p[1]), ok = dd >= 0 && dd <= d.pista.largo && Math.abs(tt) <= d.pista.ancho / 2;
        this.marcar("pista", ok ? "ok" : "mal"); a("pista", ok ? `a ${Math.abs(tt).toFixed(1)} m del eje` : "fuera de la pista");
        this.marcar("a_mano", info.automatico ? "mal" : "ok"); if (info.automatico) a("a_mano", "con el automático");
      }
    }
  }
  /** Patrulla: los vertidos (manchas en el agua) y lo que se ve de ellos en la termica (el hidrocarburo calentado por el sol). */
  _patrulla() {
    const d = this.d; this.hechos = d.vertidos.map(() => false); this.errores = d.vertidos.map(() => null);
    d.vertidos.forEach(([n, e, L], i) => {
      const P = [n, e, this.suelo(n, e)];
      this.termicos.push({ tipo: "vertido", i, nombre: `vertido ${i + 1}`, T: 41, P0: P, P1: P.slice(), r: L / 2 });
    });
  }
  /** Carrera: los obstaculos con sus medidas, el suelo (ys) y su borde de abajo (y0, m hacia arriba), y el estado: el
   *  siguiente (k), la salida (t0), la meta (tFin), la descalificacion (fuera: el que se salto) y cuando acabo (tAcabo). */
  _carrera() {
    this.obst = this.d.carrera.obstaculos.map(o => {
      const [a, al] = CARRERA.MEDIDAS[o.tipo], ys = this.suelo(o.n, o.e);
      return Object.assign({}, o, { ancho: a, alto: al, ys, y0: ys + o.h });
    });
    this.carr = { k: 0, t0: null, tFin: null, fuera: null, tAcabo: null };
  }
  /** Cruce de un obstaculo entre dos posiciones (NED): null, {tipo: "pasa"} (por dentro y en su sentido), {tipo: "reves"}
   *  o {tipo: "choque"} (por el marco, los postes o los travesanos). Los marcos, arcos y banderas se cruzan en horizontal
   *  (rumbo: hacia donde); el picado, de arriba abajo por su marco horizontal. */
  static cruceObst(pAnt, p, o) {
    const R = CARRERA.R_DRON, g = CARRERA.GROSOR[o.tipo], r = o.rumbo * D2R;
    if (o.tipo === "picado") {
      const v0 = -pAnt[2] - o.y0, v1 = -p[2] - o.y0;
      if ((v0 < 0) === (v1 < 0)) return null;
      const f = v0 / (v0 - v1), N = pAnt[0] + f * (p[0] - pAnt[0]), E = pAnt[1] + f * (p[1] - pAnt[1]), L = o.ancho / 2;
      const a = Math.abs((N - o.n) * Math.cos(r) + (E - o.e) * Math.sin(r)), b = Math.abs(-(N - o.n) * Math.sin(r) + (E - o.e) * Math.cos(r));
      if (a < L - g - R && b < L - g - R) return { tipo: v1 < v0 ? "pasa" : "reves" };
      if (a < L + g + R && b < L + g + R) return { tipo: "choque" };
      return null;
    }
    const dN = Math.cos(r), dE = Math.sin(r);
    const s0 = (pAnt[0] - o.n) * dN + (pAnt[1] - o.e) * dE, s1 = (p[0] - o.n) * dN + (p[1] - o.e) * dE;
    if ((s0 < 0) === (s1 < 0)) return null;
    const f = s0 / (s0 - s1), N = pAnt[0] + f * (p[0] - pAnt[0]), E = pAnt[1] + f * (p[1] - pAnt[1]), v = -(pAnt[2] + f * (p[2] - pAnt[2]));
    const u = Math.abs(-(N - o.n) * dE + (E - o.e) * dN), A = o.ancho / 2, H0 = o.y0, H1 = o.y0 + o.alto;
    const lado = u > A - g - R && u < A + g + R && v < H1 + g + R && v > o.ys - R;              // los postes
    const arriba = o.tipo !== "banderas" && u < A + g + R && Math.abs(v - H1) < g + R;         // el travesano de arriba
    const abajo = o.h > 0 && u < A + g + R && Math.abs(v - H0) < g + R;                         // el de abajo (marco en alto)
    if (lado || arriba || abajo) return { tipo: "choque" };
    if (u < A - g - R && v > H0 && v < H1) return { tipo: s1 > s0 ? "pasa" : "reves" };
    return null;
  }
  /** true si el dron (posicion NED) toca un poste del obstaculo (o una pata del andamio del picado) sin cruzarlo. */
  static tocaPostes(p, o) {
    const g = CARRERA.GROSOR[o.tipo], R = CARRERA.R_DRON, up = -p[2], r = o.rumbo * D2R;
    if (o.tipo === "picado") {
      if (up > o.y0 || up < o.ys) return false;
      const L = o.ancho / 2;
      for (const [a, b] of [[L, L], [L, -L], [-L, L], [-L, -L]]) {
        const pn = o.n + a * Math.cos(r) - b * Math.sin(r), pe = o.e + a * Math.sin(r) + b * Math.cos(r);
        if (Math.hypot(p[0] - pn, p[1] - pe) < CARRERA.PATA + R) return true;
      }
      return false;
    }
    if (up > o.y0 + o.alto + g || up < o.ys) return false;
    for (const s of [-1, 1]) {
      const pn = o.n - s * o.ancho / 2 * Math.sin(r), pe = o.e + s * o.ancho / 2 * Math.cos(r);
      if (Math.hypot(p[0] - pn, p[1] - pe) < g + R) return true;
    }
    return false;
  }
  /** Un paso de la carrera: choques con los obstaculos y su cruce en orden (saltarse uno descalifica). */
  _pasoCarrera(pAnt, av, T) {
    const c = this.carr, p = av.p, t = av.t, n = this.obst.length, m = this.marcar;
    for (let j = 0; j < n; j++) {
      const o = this.obst[j];
      if (Math.abs(p[0] - o.n) > 15 || Math.abs(p[1] - o.e) > 15) continue;
      if (Operacion.tocaPostes(p, o)) { this.choque = `choque con el obstáculo ${j + 1}`; return; }
      const x = pAnt ? Operacion.cruceObst(pAnt, p, o) : null;
      if (!x) continue;
      if (x.tipo === "choque") { this.choque = `choque con el obstáculo ${j + 1}`; return; }
      if (x.tipo !== "pasa" || c.fuera !== null || c.tFin !== null || j < c.k) continue;
      if (j > c.k) { c.fuera = c.k; c.tAcabo = t; m("secuencia", "mal"); T.push(`¡Descalificado! Te has saltado el obstáculo ${c.k + 1}`); continue; }
      c.k++;
      if (j === 0) { c.t0 = t; T.push(`¡Salida! El cronómetro está en marcha · 1/${n}`); }
      else if (c.k === n) {
        c.tFin = t; c.tAcabo = t; const s = t - c.t0;
        m("secuencia", "ok"); m("meta", "ok"); m("tiempo", s <= this.d.carrera.limite_s ? "ok" : "mal");
        T.push(`¡Meta! ${opCrono(s)}`);
      } else T.push(`${c.k}/${n}`);
    }
  }
  /** El siguiente obstaculo de la carrera {i, o, d (m)} o null (terminada o descalificado). */
  siguiente(av) {
    const c = this.carr;
    if (!c || c.fuera !== null || c.tFin !== null) return null;
    const o = this.obst[c.k];
    return { i: c.k, o, d: Math.hypot(av.p[0] - o.n, av.p[1] - o.e, -av.p[2] - (o.tipo === "picado" ? o.y0 : o.y0 + o.alto / 2)) };
  }
  /** El final de la carrera para el simulador ("carrera terminada" o "descalificado") cuando ya han pasado unos segundos, o null. */
  acabada(t) {
    const c = this.carr;
    if (!c || c.tAcabo === null || t - c.tAcabo < CARRERA.FIN_S) return null;
    return c.tFin !== null ? "carrera terminada" : "descalificado";
  }
  /** La pista del trabajo: (d, t) a lo largo de su eje desde el umbral y a su derecha; y su centro (N, E). */
  ejePista(N, E) { const p = this.d.pista, r = p.rumbo * D2R, dn = N - p.n, de = E - p.e; return [dn * Math.cos(r) + de * Math.sin(r), -dn * Math.sin(r) + de * Math.cos(r)]; }
  centroPista() { const p = this.d.pista, r = p.rumbo * D2R; return [p.n + p.largo / 2 * Math.cos(r), p.e + p.largo / 2 * Math.sin(r)]; }
  /** Fabrica: cuando estan las tres tareas (con el tiempo, si no se ha pasado), apunta cuando se acabaron. */
  _todo(t) {
    const d = this.d;
    if ((!d.racks && !Array.isArray(d.vertidos)) || this.tTodo) return;
    if (Array.isArray(d.vertidos)) { if (this.hechos.every(Boolean) && this.t0 !== null && t - this.t0 <= d.limite_s) this.tTodo = t; return; }
    if (this.hechosC.filter(Boolean).length === d.puntosCalientes.length && this.hechoFuga && this.hechoPlaca && this.hechoPiloto && this.t0 !== null && t - this.t0 <= d.limite_s) this.tTodo = t;
  }

  /** Lo que toca ahora (texto del panel, con <b>). */
  ahora(obj, av) {
    const d = this.d, hecho = k => obj[k] && obj[k].estado === "ok", N = av.p[0], E = av.p[1], n = this.hechos.filter(Boolean).length;
    const volver = `Ahora: <b>vuelve al punto de despegue y aterriza</b> (a ${Math.hypot(N - this.casa[0], E - this.casa[1]).toFixed(0)} m)`;
    if (Array.isArray(d.vertidos)) {
      if (this.t0 === null) return "Ahora: <b>despega de la pista 05R</b> (L arranca el motor, espacio quita el freno; P despegue automático)";
      const [cn, ce] = this.centroPista(), i = d.vertidos.findIndex((_, k) => !this.hechos[k]);
      if (i < 0) return `Ahora: <b>vuelve a San Javier y aterriza en la pista</b> (a ${(Math.hypot(N - cn, E - ce) / 1000).toFixed(1).replace(".", ",")} km)`;
      const [sn, se] = d.sectores[i], rumbo = ((Math.atan2(se - E, sn - N) * R2D) + 360) % 360;
      return `Tiempo: <b>${opMMSS(Math.max(0, d.limite_s - (av.t - this.t0)))}</b> · vertidos <b>${n} de ${d.vertidos.length}</b> · siguiente: sector ${i + 1} a ${(Math.hypot(N - sn, E - se) / 1000).toFixed(1).replace(".", ",")} km, rumbo ${String(Math.round(rumbo) % 360).padStart(3, "0")}°`;
    }
    if (d.carrera) {
      const c = this.carr, s = this.siguiente(av);
      if (c.fuera !== null) return `<b>Descalificado</b>: te has saltado el obstáculo ${c.fuera + 1}`;
      if (c.tFin !== null) return `<b>¡Carrera terminada!</b> Tiempo: <b>${opCrono(c.tFin - c.t0)}</b>`;
      const sig = `obstáculo <b>${s.i + 1} de ${this.obst.length}</b> (${CARRERA.NOMBRE[s.o.tipo]}) a ${s.d.toFixed(0)} m`;
      return c.t0 === null ? `Ahora: <b>despega y cruza el obstáculo 1</b> (${CARRERA.NOMBRE[s.o.tipo]}, a ${s.d.toFixed(0)} m): ahí empieza el cronómetro`
        : `Tiempo: <b>${opCrono(av.t - c.t0)}</b> · siguiente: ${sig}`;
    }
    if (d.recon) {
      const R = d.recon;
      if (this.t0 === null) return "Ahora: <b>lánzalo</b> (L), de cara al viento";
      if (R.puntos) {
        const i = R.puntos.findIndex((_, k) => !this.hechos[k]);
        if (i < 0) return volver;
        const q = R.puntos[i], rumbo = ((Math.atan2(q.e - E, q.n - N) * R2D) + 360) % 360;
        return `Tiempo: <b>${opMMSS(Math.max(0, R.limite_s - (av.t - this.t0)))}</b> · puntos <b>${n} de ${R.puntos.length}</b> · siguiente: punto ${i + 1} (${q.nombre}) a ${(Math.hypot(N - q.n, E - q.e) / 1000).toFixed(1).replace(".", ",")} km, rumbo ${String(Math.round(rumbo) % 360).padStart(3, "0")}°`;
      }
      if (R.objetivo) {
        if (this.fotoObj) return volver;
        const o = R.objetivo, dd = Math.hypot(N - o.n, E - o.e);
        return this.vigHecho ? "Ahora: <b>foto del vehículo con la cruz encima</b> (F)" : `Vigilancia: <b>${Math.floor(this.vig)} s de ${R.vigilar_s}</b> · objetivo a ${dd < 1000 ? dd.toFixed(0) + " m" : (dd / 1000).toFixed(1).replace(".", ",") + " km"}`;
      }
      if (R.zona) return this.encontrado ? volver : `Tiempo: <b>${opMMSS(Math.max(0, R.limite_s - (av.t - this.t0)))}</b> · busca el camión dentro de los jalones amarillos`;
    }
    if (this.t0 === null) return "Ahora: <b>despega</b> (botón de despegue o L) y ve a la zona de trabajo";
    if (d.puntos) {
      const i = d.puntos.findIndex((_, k) => !this.hechos[k]);
      return i < 0 ? volver : `Puntos fotografiados: <b>${n} de ${d.puntos.length}</b> · siguiente: ${d.puntos[i].nombre} (punto ${i + 1}, a ${Math.hypot(N - d.puntos[i].n, E - d.puntos[i].e).toFixed(0)} m)`;
    }
    if (d.solape) return hecho("cobertura") ? volver : `Parcela cubierta con solape: <b>${(this.cobertura() * 100).toFixed(0)} %</b> (hace falta ${(d.cubrir * 100).toFixed(0)} %) · altura ${Math.max(0, -av.p[2] - this.suelo(N, E)).toFixed(0)} m`;
    if (d.zona) return this.encontrado ? volver : `Tiempo: <b>${opMMSS(Math.max(0, d.limite_s - (av.t - this.t0)))}</b> · busca la chaqueta roja dentro de los jalones amarillos`;
    if (d.manchas) return n === d.manchas.length ? volver : `Manchas fotografiadas: <b>${n} de ${d.manchas.length}</b> · fotos verticales de 10 a 30 m`;
    if (d.planta) {
      const nc = this.hechosC.filter(Boolean).length, tc = this.modulosC.length;
      if (n === this.modulos.length && nc === tc) return volver;
      return `Módulos dañados: <b>${n} de ${this.modulos.length}</b>` + (tc ? ` · diodos averiados (térmica): <b>${nc} de ${tc}</b>` : "") + " · recorre las filas con la cámara hacia abajo";
    }
    if (d.racks) {
      const nc = this.hechosC.filter(Boolean).length, tc = d.puntosCalientes.length, ok = x => x ? "✓" : "pendiente";
      if (nc === tc && this.hechoFuga && this.hechoPlaca && this.hechoPiloto) return volver;
      return `Tiempo: <b>${opMMSS(Math.max(0, d.limite_s - (av.t - this.t0)))}</b> · puntos calientes <b>${nc} de ${tc}</b> · fuga ${ok(this.hechoFuga)} · placa ${ok(this.hechoPlaca)} · piloto ${ok(this.hechoPiloto)}`;
    }
    if (d.faro) return hecho("orbita") ? volver : `Órbita: <b>${this.orb ? Math.abs(this.orb.acc * R2D).toFixed(0) : 0}°</b> de 330° · a ${Math.hypot(N - d.faro.n, E - d.faro.e).toFixed(0)} m del faro`;
    return volver;
  }
}
