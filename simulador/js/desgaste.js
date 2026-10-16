"use strict";
// =====================================================================
//  DESGASTE Y AVERIAS de los vehiculos (scripts/desgaste.gd en Godot: los mismos datos, el mismo azar y los mismos
//  efectos, para que los dos simuladores vuelen igual). Cada vehiculo de cada alumno lleva su estado (en el aula y, sin
//  conexion, en el ordenador): horas de vuelo, horas de cada componente, salud y ciclos de la bateria, averias y libro
//  de mantenimiento. Durante la primera hora de vuelo del vehiculo no pasa nada; despues, cada vuelo puede estropear
//  algo (mas cuanto mas usado esta), y tambien un golpe, una descarga por debajo del 10 % o calentar la bateria. El
//  profesor puede poner averias (en vuelo, solo en una sala de multijugador). Nada se bloquea: se vuela con la averia,
//  con los avisos de la app como en el dron real y los sintomas en el vuelo y en el registro; en el Taller se
//  inspecciona, se repara y se apunta en el libro.
//  Efectos (aplicar): empuje y consumo (kEmp, kPot y, en el FPV, por motor), vibraciones y par de una helice danada
//  (antesPaso/despuesPaso, alrededor de modelo.paso), sensores del dron comercial (modelo.sens: brujula, IMU, GPS y
//  barometro), bateria (capacidad y resistencia con la salud, celda debil) y superficies (holgura del servo, bisagra).
// =====================================================================
const Desgaste = {
  HORAS_SIN_AVERIAS: 1,
  // motores del cuadricoptero (como el dron comercial): 1 delantero derecho, 2 delantero izquierdo, 3 trasero izquierdo,
  // 4 trasero derecho; [x (+ delante), y (+ derecha), giro (+1 horario visto desde arriba)]
  MOTORES: [[1, 1, -1], [1, -1, 1], [-1, -1, -1], [-1, 1, 1]],
  NOMBRE_MOTOR: ["delantero derecho", "delantero izquierdo", "trasero izquierdo", "trasero derecho"],
  NOMBRE_HELICE: ["delantera derecha", "delantera izquierda", "trasera izquierda", "trasera derecha"],
  SUPERFICIES: { alerones: "los alerones", profundidad: "la profundidad", timon: "el timón", elevon_izq: "el elevón izquierdo", elevon_der: "el elevón derecho" },
  CLAVE_SUP: { alerones: "da", profundidad: "de", timon: "dr", elevon_izq: "elevon_izq", elevon_der: "elevon_der" },
  // por cada hora de uso del componente (tasa x horas, por hora de vuelo) o fija (por hora de vuelo)
  TASAS: { helice: [0.06, 1], motor: [0.02, 1], servo: [0.04, 1], bisagra: [0.03, 1], celda: [0.02, 1], brujula: [0.05, 0], imu: [0.03, 0], gps: [0.02, 0], barometro: [0.02, 0] },
  VIB: { cuad: 45, fpv: 250, avion: 120, comb: 120 },        // aceleracion angular de la vibracion a tope de gas (rad/s2)

  /** Clase del vehiculo para las averias: "cuad" (dron comercial), "fpv", "avion" (electrico), "comb" (de combustion)
   *  o null (el bipode no tiene). */
  clase(A) {
    if (!A || A.tipo === "bipode") return null;
    if (A.tipo === "cuadricoptero") return "cuad";
    if (A.tipo === "fpv") return "fpv";
    return A.propulsion && A.propulsion.combustible ? "comb" : "avion";
  },
  /** Superficies de mando de un avion (las que tienen servo y bisagra). */
  superficies(A) {
    const m = A.mandos || {}, s = [];
    if (m.elevon_max_grados) s.push("elevon_izq", "elevon_der");
    else { if (m.aleron_max_grados > 0) s.push("alerones"); if (m.prof_max_grados > 0) s.push("profundidad"); }
    if (m.timon_max_grados > 0) s.push("timon");
    return s;
  },
  /** Componentes del vehiculo: [id, nombre]. */
  componentes(A) {
    const k = Desgaste.clase(A), c = [];
    if (!k) return c;
    if (k === "cuad" || k === "fpv") {
      for (let i = 1; i <= 4; i++) c.push(["helice" + i, `Hélice ${i} (${Desgaste.NOMBRE_HELICE[i - 1]})`]);
      for (let i = 1; i <= 4; i++) c.push(["motor" + i, `Motor ${i} (${Desgaste.NOMBRE_MOTOR[i - 1]})`]);
    } else c.push(["helice", "Hélice"], ["motor", "Motor"]);
    if (k !== "comb") c.push(["bateria", "Batería"]);
    if (k === "cuad") c.push(["brujula", "Brújula"], ["imu", "IMU"], ["gps", "GPS"], ["barometro", "Barómetro"]);
    for (const s of Desgaste.superficies(k === "avion" || k === "comb" ? A : {}))
      c.push(["servo_" + s, "Servo " + Desgaste.de(Desgaste.SUPERFICIES[s])], ["bisagra_" + s, "Bisagra " + Desgaste.de(Desgaste.SUPERFICIES[s])]);
    return c;
  },
  /** "de los alerones", "de la profundidad", "del timon". */
  de(t) { return t.startsWith("el ") ? "del " + t.slice(3) : "de " + t; },
  /** Estado de un vehiculo nuevo. */
  nuevo() { return { version: 0, horas: 0, h: {}, bateria: { salud: 1, ciclos: 0 }, averias: [], libro: [] }; },
  /** Familia de una averia (la del componente: helice, motor, bateria, servo...). */
  familia(c) { return c.replace(/\d+$/, "").replace(/_.*$/, ""); },
  /** Nombre de una averia (para el profesor y el libro de mantenimiento). */
  nombre(a) {
    const f = Desgaste.familia(a.c), n = a.c.replace(/\D/g, ""), s = a.c.replace(/^[a-z]+_/, "");
    if (f === "helice") return n ? `Hélice ${n} dañada` : "Hélice dañada";
    if (f === "motor") return n ? `Rodamiento del motor ${n} gastado` : "Rodamiento del motor gastado";
    if (f === "bateria") return a.tipo === "hinchada" ? "Batería hinchada" : a.tipo === "celda" ? `Celda ${(a.n || 0) + 1} de la batería débil` : "Batería envejecida";
    if (f === "brujula") return "Brújula descalibrada";
    if (f === "imu") return "IMU descalibrada";
    if (f === "gps") return "Antena del GPS dañada";
    if (f === "barometro") return "Barómetro con deriva";
    if (f === "servo") return "Holgura en el servo " + Desgaste.de(Desgaste.SUPERFICIES[s] || s);
    if (f === "bisagra") return "Bisagra floja en " + (Desgaste.SUPERFICIES[s] || s);
    return a.c;
  },
  /** Las averias que se pueden poner (panel del profesor y salas): [{c, tipo, n}] con su nombre. */
  posibles(A) {
    const L = [];
    for (const [c] of Desgaste.componentes(A)) {
      const f = Desgaste.familia(c);
      if (f === "bateria") {
        L.push({ c, tipo: "envejecida" });
        const B = Bateria.datos(A.propulsion || {});
        for (let i = 0; i < B.celdas; i++) L.push({ c, tipo: "celda", n: i });
        L.push({ c, tipo: "hinchada" });
      } else L.push({ c, tipo: { helice: "mella", motor: "rodamiento", brujula: "descalibrada", imu: "descalibrada", gps: "antena", barometro: "deriva", servo: "holgura", bisagra: "floja" }[f] });
    }
    return L.map(a => Object.assign(a, { nombre: Desgaste.nombre(a) }));
  },
  /** Anade una averia (si no esta ya) con su origen (desgaste, golpe, descarga, calor, profesor). */
  anadir(est, a, origen, fecha) {
    if (est.averias.some(x => x.c === a.c && x.tipo === a.tipo && (x.n || 0) === (a.n || 0))) return null;
    const x = { c: a.c, tipo: a.tipo, origen, fecha };
    if (a.n !== undefined) x.n = a.n;
    est.averias.push(x);
    if (a.c === "bateria" && a.tipo === "envejecida") est.bateria.salud = Math.min(est.bateria.salud, 0.78);
    if (a.c === "bateria" && a.tipo === "hinchada") est.bateria.salud = Math.min(est.bateria.salud, 0.6);
    return x;
  },

  // ---------------------------------------------------------------- efectos en el vuelo
  /** Pone en el modelo (recien creado y configurado) los efectos de las averias y de la salud de la bateria. */
  aplicar(m, est) {
    m.averias = est ? est.averias : []; m.sens = null; m.kT = null; m.kP = null; m.kEmp = 1; m.kPot = 1; m._est = est;
    m.efe = { vib: 0, par: [0, 0, 0], sup: {}, clase: Desgaste.clase(m) };
    if (!est) return;
    const E = m.efe, k = E.clase, B = m.B;
    if (B) {                                              // la salud de la bateria: menos capacidad y mas resistencia
      if (!m._Bbase) m._Bbase = { cap: B.capacidad_mAh, R: B.R_ohm };
      let s = est.bateria.salud;
      if (est.averias.some(a => a.c === "bateria" && a.tipo === "hinchada")) s = Math.min(s, 0.6);
      B.capacidad_mAh = m._Bbase.cap; B.R_ohm = m._Bbase.R; delete B.debil;
      if (s < 1) { B.capacidad_mAh *= s; B.R_ohm *= 1 + 3 * (1 - s); }
    }
    for (const a of est.averias) {
      const f = Desgaste.familia(a.c), i = +(a.c.replace(/\D/g, "") || 1) - 1;
      if (f === "bateria" && a.tipo === "celda" && B) B.debil = { i: Math.min(a.n || 0, B.celdas - 1), k: 0.75 };
      if (f === "helice" || f === "motor") {
        const h = f === "helice";
        E.vib += h ? 1 : 0.4;
        if (k === "fpv") { m.kT = m.kT || [1, 1, 1, 1]; m.kP = m.kP || [1, 1, 1, 1]; m.kT[i] *= h ? 0.75 : 0.93; m.kP[i] *= h ? 1.1 : 1.15; }
        else if (k === "cuad") {
          m.kEmp *= h ? 0.95 : 0.98; m.kPot *= h ? 1.06 : 1.08;
          if (h) { const [x, y, g] = Desgaste.MOTORES[i], t = m.fc.tau_max, tg = m.fc.tau_guinada; E.par[0] += 0.01 * y * t; E.par[1] -= 0.01 * x * t; E.par[2] -= 0.05 * g * tg; }
        } else { m.kEmp *= h ? 0.85 : 0.95; m.kPot *= h ? 1.05 : 1.12; }
      }
      if (k === "cuad" && (f === "brujula" || f === "imu" || f === "gps" || f === "barometro")) {
        const S = m.sens || (m.sens = { rumbo: 0, alabeo: 0, cabeceo: 0, gps: 0, vz: 0 });
        if (f === "brujula") S.rumbo = 50 * D2R;
        if (f === "imu") { S.alabeo = 3 * D2R; S.cabeceo = -2 * D2R; }
        if (f === "gps") S.gps = 3.5;
        if (f === "barometro") S.vz = 0.15;
      }
      if (f === "servo" || f === "bisagra") {
        const s = a.c.replace(/^[a-z]+_/, ""), key = Desgaste.CLAVE_SUP[s];
        if (!key) continue;
        const P = E.sup[key] || (E.sup[key] = { h: 0, ef: 1, fl: 0 });
        if (f === "servo") P.h = 3 * D2R; else { P.ef = 0.6; P.fl = 1.2 * D2R; }
      }
    }
  },
  /** Antes de modelo.paso: la superficie que de verdad mueve el aire (holgura del servo, bisagra floja que cede y
   *  flamea). Se deshace en despuesPaso: el servo sigue donde estaba. */
  antesPaso(m, av) {
    const S = m.efe && m.efe.sup, ks = S ? Object.keys(S) : [];
    if (!ks.length) return;
    av._sup = { de: av.de, da: av.da, dr: av.dr };
    const ho = av._holg || (av._holg = {}), t = av.t || 0, fl = Math.min(1, (av.V || 0) / 10);
    let elev = false;
    for (const k of ks) {
      const P = S[k], x = av[k] || 0;
      if (!(k in av._sup)) av._sup[k] = x;
      let y = ho[k] === undefined ? x : ho[k];
      if (x - y > P.h) y = x - P.h; else if (y - x > P.h) y = x + P.h;
      ho[k] = y;
      av[k] = y * P.ef + P.fl * fl * Math.sin(2 * Math.PI * 6.7 * t + k.length);
      if (k.startsWith("elevon")) elev = true;
    }
    if (elev) { av.de = 0.5 * (av.elevon_izq + av.elevon_der); av.da = 0.5 * (av.elevon_izq - av.elevon_der); }
  },
  /** Despues de modelo.paso: las superficies como estaban; vibracion (helice o motor) y par de la helice danada. */
  despuesPaso(m, av, dt) {
    if (av._sup) { for (const k in av._sup) av[k] = av._sup[k]; av._sup = null; }
    const E = m.efe;
    if (!E || av.estado !== "volando" || av.posado || av.armado === false) return;
    const t = av.t, g = Math.max(0, Math.min(1, av.gases || 0)), w = av.w, I = m.inercia;
    if (E.vib) {
      const A = E.vib * Desgaste.VIB[E.clase] * g, TAU = 2 * Math.PI;
      w[0] += A * (0.6 * Math.sin(TAU * 11.3 * t) + 0.4 * Math.sin(TAU * 17.9 * t + 1.1)) * dt;
      w[1] += A * (0.6 * Math.sin(TAU * 12.7 * t + 0.5) + 0.4 * Math.sin(TAU * 16.3 * t + 2.3)) * dt;
      w[2] += 0.3 * A * Math.sin(TAU * 9.1 * t + 0.9) * dt;
    }
    if (E.par[0] || E.par[1] || E.par[2]) {
      const kT = Math.min(1.5, (av.T || 0) / (m.masa_kg * G0));
      w[0] += E.par[0] / I.Ixx * kT * dt; w[1] += E.par[1] / I.Iyy * kT * dt; w[2] += E.par[2] / I.Izz * kT * dt;
    }
  },
  /** Una averia que llega en vuelo (sala multijugador): se suma a las del modelo y se vuelven a poner sus efectos. */
  enVuelo(m, a) {
    const est = m._est || Desgaste.nuevo(), e2 = Object.assign({}, est, { averias: (m.averias || []).concat([a]), bateria: Object.assign({}, est.bateria) });
    if (a.c === "bateria" && a.tipo === "envejecida") e2.bateria.salud = Math.min(e2.bateria.salud, 0.78);
    Desgaste.aplicar(m, e2);
  },
  /** La averia que pide el profesor, en los componentes de este vehiculo: la misma o, si es de una familia (helice,
   *  motor, servo...), la del primero de esa familia. null si este vehiculo no la tiene. */
  adaptar(A, a) {
    const P = Desgaste.posibles(A), igual = x => x.c === a.c && x.tipo === a.tipo && (x.n || 0) === (a.n || 0);
    const x = P.find(igual) || P.find(x => Desgaste.familia(x.c) === Desgaste.familia(a.c) && x.tipo === a.tipo && (x.n || 0) === (a.n || 0));
    if (!x) return null;
    const r = { c: x.c, tipo: x.tipo }; if (x.n !== undefined) r.n = x.n;
    return r;
  },
  /** Avisos de la app al armar (el autodiagnostico del dron comercial): lo que el dron real dice de sus sensores. */
  avisosApp(m) {
    if (!m.averias || Desgaste.clase(m) !== "cuad") return [];
    const L = [];
    for (const a of m.averias) {
      if (a.c === "brujula") L.push("Error de brújula: calibra la brújula");
      if (a.c === "imu") L.push("Es necesario calibrar la IMU");
      if (a.c === "gps") L.push("Señal GPS débil: el posicionamiento puede ser impreciso");
    }
    return L;
  },

  // ---------------------------------------------------------------- desgaste de cada vuelo
  /** Azar con semilla (Park-Miller, el de los sorteos de las operaciones): igual en GDScript. */
  azar(texto) {
    let h = 7; for (let i = 0; i < texto.length; i++) h = (h * 31 + texto.charCodeAt(i)) % 2147483647;
    let x = h || 1;
    return () => (x = (x * 48271) % 2147483647) / 2147483647;
  },
  /** Despues de un vuelo: suma las horas y decide lo que se estropea. info: { s (segundos de vuelo), roto (golpe),
   *  bat0 y bat1 (% al empezar y al acabar, o null), tempMax (grados de la bateria, o null), semilla, fecha }.
   *  Devuelve las averias nuevas. */
  trasVuelo(est, A, info) {
    const dh = Math.max(0, info.s) / 3600, comp = Desgaste.componentes(A), nuevas = [];
    if (dh <= 0) return nuevas;
    est.horas = +(est.horas + dh).toFixed(6);
    for (const [c] of comp) est.h[c] = +((est.h[c] || 0) + dh).toFixed(6);
    const conBat = comp.some(([c]) => c === "bateria") && info.bat0 !== null && info.bat1 !== null;
    if (conBat && info.bat0 - info.bat1 > 25) est.bateria.ciclos += 1;
    if (est.horas <= Desgaste.HORAS_SIN_AVERIAS) return nuevas;            // la primera hora no pasa nada
    const rnd = Desgaste.azar(info.semilla), F = info.fecha, poner = (a, o) => { const x = Desgaste.anadir(est, a, o, F); if (x) nuevas.push(x); };
    if (conBat) {                                                       // la bateria: ciclos, descargas profundas y calor
      let s = est.bateria.salud;
      if (info.bat0 - info.bat1 > 25) s -= 0.004;
      if (info.bat1 < 10) { s -= 0.03; if (rnd() < 0.15) poner({ c: "bateria", tipo: "hinchada" }, "descarga"); }
      if (info.tempMax !== null && info.tempMax > 55) s -= 0.01;
      est.bateria.salud = +Math.max(0.5, Math.min(est.bateria.salud, s)).toFixed(4);
      if (est.bateria.salud < 0.8) poner({ c: "bateria", tipo: "envejecida" }, "desgaste");
    }
    for (const [c] of comp) {                                           // cada componente, con su tasa y sus horas
      const f = Desgaste.familia(c), T = Desgaste.TASAS[f === "bateria" ? "celda" : f];
      if (!T) continue;
      const lam = T[0] * (T[1] ? Math.max(0.5, est.h[c]) : 1), p = 1 - Math.exp(-lam * dh), r = rnd();
      if (r >= p) continue;
      if (f === "bateria") { const nB = Bateria.datos(A.propulsion || {}).celdas; poner({ c, tipo: "celda", n: Math.floor(rnd() * nB) }, "desgaste"); }
      else poner(Desgaste.posibles(A).find(a => a.c === c), "desgaste");
    }
    if (info.roto) {                                                    // un golpe: una helice y, a veces, la IMU
      const hs = comp.filter(([c]) => c.startsWith("helice"));
      if (hs.length && rnd() < 0.8) poner({ c: hs[Math.floor(rnd() * hs.length)][0], tipo: "mella" }, "golpe");
      if (comp.some(([c]) => c === "imu") && rnd() < 0.2) poner({ c: "imu", tipo: "descalibrada" }, "golpe");
    }
    return nuevas;
  },

  // ---------------------------------------------------------------- taller: inspeccion y reparacion
  /** Lo que se puede revisar en el taller: [id, texto]. */
  revisiones(A) {
    const k = Desgaste.clase(A), r = [["helices", "Inspeccionar las hélices"], ["motores", "Girar los motores a mano"]];
    if (k !== "comb") r.push(["bateria", "Revisar la batería"]);
    if (k === "cuad") r.push(["app", "Autodiagnóstico de la app"]);
    if (k === "avion" || k === "comb") r.push(["superficies", "Mover las superficies a mano"]);
    return r;
  },
  /** El resultado de una revision: lineas de texto (lo que se ve, no el nombre de la averia). */
  revisar(est, A, id) {
    const comp = Desgaste.componentes(A), tiene = (c, t) => est.averias.some(a => a.c === c && (!t || a.tipo === t)), L = [];
    if (id === "helices") for (const [c, n] of comp.filter(([c]) => c.startsWith("helice")))
      L.push(n + ": " + (tiene(c) ? "mella en el borde de ataque y una grieta junto al buje" : "sin daños, bien apretada"));
    if (id === "motores") for (const [c, n] of comp.filter(([c]) => c.startsWith("motor")))
      L.push(n + ": " + (tiene(c) ? "gira áspero, con ruido de rodamiento y algo de juego en el eje" : "gira suave y sin ruido"));
    if (id === "bateria") {
      const B = Bateria.datos(A.propulsion || {}), s = tiene("bateria", "hinchada") ? Math.min(est.bateria.salud, 0.6) : est.bateria.salud, deb = est.averias.find(a => a.c === "bateria" && a.tipo === "celda");
      L.push(tiene("bateria", "hinchada") ? "Aspecto: la batería está hinchada (abombada). No se debe usar" : "Aspecto: normal, sin golpes ni hinchazón");
      L.push(`Ciclos de carga: ${est.bateria.ciclos}`);
      L.push(`Capacidad a plena carga: ${Math.round(B.capacidad_mAh * s)} mAh de ${Math.round(B.capacidad_mAh)} (${Math.round(100 * s)} %)`);
      L.push("Celdas en reposo: " + Array.from({ length: B.celdas }, (_, i) => (3.85 + [0, -0.006, 0.003, -0.004, 0.005, -0.002][i % 6] - (deb && deb.n === i ? 0.09 : 0)).toFixed(2).replace(".", ",") + " V").join(" · "));
    }
    if (id === "app") {
      const m = { averias: est.averias, tipo: A.tipo }, av = Desgaste.avisosApp(m);
      L.push(...(av.length ? av : ["Sin errores: brújula, IMU y GPS correctos"]));
    }
    if (id === "superficies") for (const s of Desgaste.superficies(A)) {
      const nom = Desgaste.SUPERFICIES[s], N = nom[0].toUpperCase() + nom.slice(1);
      if (tiene("servo_" + s)) L.push(N + (s === "alerones" ? ": tienen" : ": tiene") + " juego con el servo quieto (holgura en los engranajes del servo)");
      else if (tiene("bisagra_" + s)) L.push(N + ": la bisagra está despegada y la superficie se mueve de más");
      else L.push(N + ": firme, sin holgura");
    }
    return L;
  },
  /** Las reparaciones posibles: [id, texto, componentes que renueva]. */
  reparaciones(A) {
    const comp = Desgaste.componentes(A), k = Desgaste.clase(A), r = [];
    const hs = comp.filter(([c]) => c.startsWith("helice"));
    if (hs.length > 1) r.push(["helices", "Cambiar todas las hélices", hs.map(([c]) => c)]);
    for (const [c, n] of comp) {
      const f = Desgaste.familia(c);
      if (f === "helice") r.push([c, "Cambiar la " + n[0].toLowerCase() + n.slice(1), [c]]);
      else if (f === "motor") r.push([c, "Cambiar el " + n[0].toLowerCase() + n.slice(1), [c]]);
      else if (f === "bateria") r.push([c, "Cambiar la batería", [c]]);
      else if (f === "brujula") r.push([c, "Calibrar la brújula", [c]]);
      else if (f === "imu") r.push([c, "Calibrar la IMU", [c]]);
      else if (f === "gps") r.push([c, "Cambiar el módulo GPS", [c]]);
      else if (f === "barometro") r.push([c, "Cambiar el barómetro", [c]]);
      else if (f === "servo" || f === "bisagra") r.push([c, (f === "servo" ? "Cambiar el " : "Cambiar la ") + n[0].toLowerCase() + n.slice(1), [c]]);
    }
    return k ? r : [];
  },
  /** Hace una reparacion: renueva los componentes (sus horas a 0; la bateria, nueva), quita sus averias y lo apunta en
   *  el libro de mantenimiento (con lo que de verdad arreglo, que ve el profesor). Devuelve la entrada del libro. */
  reparar(est, A, id, fecha) {
    const R = Desgaste.reparaciones(A).find(r => r[0] === id);
    if (!R) return null;
    const arr = est.averias.filter(a => R[2].includes(a.c));
    est.averias = est.averias.filter(a => !R[2].includes(a.c));
    for (const c of R[2]) est.h[c] = 0;
    if (R[2].includes("bateria")) est.bateria = { salud: 1, ciclos: 0 };
    const e = { fecha, accion: id, texto: R[1], arreglo: arr.map(Desgaste.nombre), horas: +est.horas.toFixed(3) };
    est.libro.push(e);
    if (est.libro.length > 200) est.libro.splice(0, est.libro.length - 200);
    return e;
  },

  // ---------------------------------------------------------------- guardar: el aula (por alumno) o el ordenador
  cache: {},
  _local() { try { return JSON.parse(localStorage.getItem("uxs_vehiculos") || "{}") || {}; } catch (e) { return {}; } },
  /** Estado de un vehiculo (de lo ultimo cargado). */
  estado(avion) { return Desgaste.cache[avion] || Desgaste.nuevo(); },
  /** Carga los estados: los del alumno en el aula o, sin conexion, los de este ordenador. */
  async cargar() {
    if (sesion.aula && sesion.alumno) {
      try { Desgaste.cache = await api("GET", "vehiculos?alumno=" + encodeURIComponent(sesion.alumno.id)) || {}; return true; } catch (e) { return false; }
    }
    Desgaste.cache = Desgaste._local(); return true;
  },
  /** Cambia el estado de un vehiculo con f(estado) (en el aula, sobre el ultimo del servidor: si el profesor lo ha
   *  cambiado mientras, se repite con el nuevo). Devuelve lo que devuelve f. */
  async modificar(avion, f) {
    if (sesion.aula && sesion.alumno) {
      for (let k = 0; k < 4; k++) {
        let todos; try { todos = await api("GET", "vehiculos?alumno=" + encodeURIComponent(sesion.alumno.id)); } catch (e) { break; }
        const est = (todos && todos[avion]) || Desgaste.nuevo(), r = f(est);
        try { const g = await api("POST", "vehiculos", { alumno_id: sesion.alumno.id, avion, version: est.version, estado: est }); todos[avion] = g; Desgaste.cache = todos; return r; }
        catch (e) { if (e.status !== 409) break; }
      }
      return null;
    }
    const L = Desgaste._local(), est = L[avion] || Desgaste.nuevo(), r = f(est);
    est.version = (est.version || 0) + 1; L[avion] = est;
    try { localStorage.setItem("uxs_vehiculos", JSON.stringify(L)); } catch (e) {}
    Desgaste.cache = L; return r;
  },
};
