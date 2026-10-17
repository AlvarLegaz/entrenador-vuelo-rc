// Camaras de trabajo: la torreta EO/IR y el morro fijo del UAV, la camara de a bordo de los aviones y sus fotos.
// Parte de la aplicacion de simulador_web/simulador.html: los modulos de js/app/ se cargan en orden y comparten el
// ambito global. En Godot: simulador_godot/scripts/app/camaras.gd.
"use strict";
// ---- torreta EO/IR del UAV: av.torreta {pan (rad, + a la derecha del morro), tilt (rad, - hacia abajo)}, su punto fijo
// (K: la torreta sigue ese punto del terreno mientras el avion vuela) y el punto de la cruz (donde el eje de la camara
// corta el terreno o el agua)
const UAV = { fijo: null, cruz: null, fotos: 0 };
const TORRETA = { vel: 45 * D2R, tiltMin: -90 * D2R, tiltMax: 10 * D2R };
/** Las flechas mueven la torreta (y no el avion) con el piloto automatico navegando, o con Mayusculas. */
function torretaConFlechas() { return !!(piloto && (teclas["ShiftLeft"] || teclas["ShiftRight"] || ["PUNTO", "BASE", "DESPEGUE", "ATERRIZAJE"].includes(piloto.modo))); }
/** Donde esta la torreta (NED) y hacia donde mira (vector unitario NED). */
function ejeTorreta() {
  const CF = visor.avion && visor.avion.camFija;
  if (CF) {                                     // morro fijo: sujeta al avion
    const tr = av.torreta, ct = Math.cos(tr.tilt), st = Math.sin(tr.tilt), c = Cuat.rot(av.q, CF.pos);
    return [[av.p[0] + c[0], av.p[1] + c[1], av.p[2] + c[2]], Cuat.rot(av.q, [ct * Math.cos(tr.pan), ct * Math.sin(tr.pan), -st])];
  }
  const tr = av.torreta, yaw = Cuat.euler(av.q)[2] + tr.pan, c = visor.avion && visor.avion.centroTorreta ? Cuat.rot(av.q, visor.avion.centroTorreta) : [0, 0, 0];
  return [[av.p[0] + c[0], av.p[1] + c[1], av.p[2] + c[2]], [Math.cos(yaw) * Math.cos(tr.tilt), Math.sin(yaw) * Math.cos(tr.tilt), -Math.sin(tr.tilt)]];
}
/** El punto de la cruz: [N, E, altura del suelo, distancia] donde el eje de la torreta corta el terreno (o el agua), o null. */
function puntoCruz() {
  const [o, d] = ejeTorreta(), H = (N, E) => entorno.altura ? entorno.altura(N, E) : 0;
  if (d[2] <= 0.002) return null;                                    // mirando al horizonte o hacia arriba
  for (let s = 5, ant = 0; s < 20000; ant = s, s += Math.max(5, s * 0.02)) {
    const p = [o[0] + s * d[0], o[1] + s * d[1], o[2] + s * d[2]];
    if (-p[2] <= H(p[0], p[1])) {                                     // ya por debajo del suelo: afina entre el paso anterior y este
      let a = ant, b = s;
      for (let k = 0; k < 12; k++) { const m = (a + b) / 2, q = [o[0] + m * d[0], o[1] + m * d[1], o[2] + m * d[2]]; if (-q[2] <= H(q[0], q[1])) b = m; else a = m; }
      return [o[0] + b * d[0], o[1] + b * d[1], H(o[0] + b * d[0], o[1] + b * d[1]), b];
    }
  }
  return null;
}
/** Cada cuadro: mueve la torreta con las flechas, Q/E y el mando (mas despacio cuanto mas zoom) o la apunta al punto fijo. */
/** Morro fijo: la camara de la ventana elegida (frontal o lateral), con su inclinacion fija respecto al avion. */
function ponerVistaFija() { const F = Modelos.datos(sesion.avion).malla.cam_fija[UAV.vista || "frontal"]; av.torreta = { pan: F[0] * D2R, tilt: F[1] * D2R }; }
function cambiarVistaFija() { UAV.vista = UAV.vista === "lateral" ? "frontal" : "lateral"; ponerVistaFija(); toast(UAV.vista === "lateral" ? "Cámara lateral (izquierda)" : "Cámara frontal"); }
function moverTorreta(dt) {
  if (!modelo || !modelo.uav || !av.torreta || av.estado === "roto") return;
  if (morroDe(sesion.avion) === "fijo") { UAV.cruz = puntoCruz(); return; }       // el morro fijo no se mueve: la cruz, donde mire el avion
  const tr = av.torreta, z = camDJI().zoom, k = TORRETA.vel / Math.pow(z, 0.7) * dt, fl = torretaConFlechas();
  const dp = (fl ? (teclas["ArrowRight"] ? 1 : 0) - (teclas["ArrowLeft"] ? 1 : 0) : 0) + (MANDO.torreta ? MANDO.torreta[0] : 0);
  const dtl = (fl ? (teclas["ArrowUp"] ? 1 : 0) - (teclas["ArrowDown"] ? 1 : 0) : 0) + (teclas["KeyE"] ? 1 : 0) - (teclas["KeyQ"] ? 1 : 0) + (MANDO.torreta ? -MANDO.torreta[1] : 0) + (MANDO.gimbal || 0);
  if (dp || dtl) { if (UAV.fijo) { UAV.fijo = null; toast("Torreta: punto suelto"); } tr.pan = PilotoUAV.envolver(tr.pan + dp * k); tr.tilt = Math.max(TORRETA.tiltMin, Math.min(TORRETA.tiltMax, tr.tilt + dtl * k)); }
  else if (UAV.fijo) {                                                // apunta al punto fijo
    const [o] = ejeTorreta(), dn = UAV.fijo[0] - o[0], de = UAV.fijo[1] - o[1], dz = -UAV.fijo[2] - o[2];
    tr.pan = PilotoUAV.envolver(Math.atan2(de, dn) - Cuat.euler(av.q)[2]); tr.tilt = Math.max(TORRETA.tiltMin, Math.min(TORRETA.tiltMax, -Math.atan2(dz, Math.hypot(dn, de))));
  }
  UAV.cruz = puntoCruz();
}
/** K: fija la torreta en el punto de la cruz (o la suelta). */
/** Foto con la camara de a bordo de un avion (reconocimiento): mira al frente, con el cabeceo del avion. */
function avionFoto() {
  if (av.estado !== "volando" || Repeticion.activa) return;
  const co = camaraOp(), T = ev.op.foto(av, co.gimbal, { pan: co.pan, zoom: 1 }); toast(T.join(" · "));
}
/** La camara de las operaciones como gimbal (grados) y giro respecto al rumbo del avion (rad): la torreta, tal cual; el
 *  morro fijo del UAV y la camara de a bordo de los aviones (al frente), con su direccion real: se inclinan con el avion. */
function camaraOp() {
  if (modelo.uav && av.torreta && !(visor.avion && visor.avion.camFija)) return { gimbal: av.torreta.tilt * R2D, pan: av.torreta.pan };
  const d = modelo.uav && av.torreta ? ejeTorreta()[1] : Cuat.rot(av.q, [1, 0, 0]);
  return { gimbal: -Math.asin(Math.max(-1, Math.min(1, d[2]))) * R2D, pan: PilotoUAV.envolver(Math.atan2(d[1], d[0]) - Cuat.euler(av.q)[2]) };
}
function uavFijar() {
  if (!modelo.uav) return;
  if (morroDe(sesion.avion) === "fijo") { toast("Con el morro fijo no hay torreta: apunta con el avión"); return; }
  if (UAV.fijo) { UAV.fijo = null; toast("Torreta: punto suelto"); return; }
  const c = puntoCruz(); if (!c) { toast("La cruz no apunta al suelo: baja la torreta"); return; }
  UAV.fijo = [c[0], c[1], c[2]]; toast("Torreta fijada en " + coordTxt(c[0], c[1]));
}
/** Latitud y longitud (grados y minutos decimales, como las de un GPS) de un punto N, E del mapa. */
function coordTxt(N, E) {
  const M = entorno.mundo, lat = M.origen.lat + N / 110574, lon = M.origen.lon + E / (111320 * Math.cos(M.origen.lat * D2R));
  const gm = (x, p, n) => `${Math.floor(Math.abs(x))}°${((Math.abs(x) % 1) * 60).toFixed(3).padStart(6, "0")}' ${x >= 0 ? p : n}`;
  return `${gm(lat, "N", "S")} ${gm(lon, "E", "W")}`;
}
/** F: foto de la torreta (en un trabajo, lo que vale para el; si no, la foto con las coordenadas del punto de la cruz). */
function uavFoto() {
  if (!modelo.uav || av.estado !== "volando") return;
  UAV.fotos++;
  const co = camaraOp(), cm = Object.assign(camDJI(), { pan: co.pan }), T = ev && ev.op ? ev.op.foto(av, co.gimbal, cm) : [];
  const c = UAV.cruz;
  toast(T.length ? T.join(" · ") : `Foto ${UAV.fotos}` + (c && entorno.mundo ? ` · ${coordTxt(c[0], c[1])} · a ${c[3] < 1000 ? c[3].toFixed(0) + " m" : (c[3] / 1000).toFixed(1).replace(".", ",") + " km"}` : ""));
}
/** UAV: pone un modo del piloto automatico (con su aviso, o por que no se puede). */
function uavPoner(modo, punto) {
  if (!piloto || av.estado !== "volando" || Repeticion.activa) { if (piloto && av.estado === "en mano") toast("Primero arranca el motor (L)"); return; }
  const t = piloto.poner(modo, av, punto);
  if (t) { piloto.modoVisto = piloto.modo; toast("Piloto automático: " + t); if (modo === "DESPEGUE") aviso(""); return; }
  toast(modo === "DESPEGUE" ? "El despegue automático se pide parado en la pista" : modo === "ATERRIZAJE" ? (piloto.pista ? "En tierra no hay aterrizaje automático" : "Sin pista no hay aterrizaje automático")
        : "En tierra: manual o despegue automático (P)");
}
/** UAV: M pasa de manual a estabilizado, a crucero y otra vez a manual. */
function uavModo() {
  if (!piloto) return;
  const ciclo = ["MANUAL", "ESTAB", "CRUCERO"], i = ciclo.indexOf(piloto.modo);
  uavPoner(i < 0 ? "MANUAL" : ciclo[(i + 1) % 3]);
}
/** Avion de pista: el freno de aparcamiento se quita con el primer espacio (o B); despues frenan mientras se pulsan. */
function quitarFrenoAparc() { if (av && av.frenoAparc) { av.frenoAparc = false; aviso(""); toast("Freno de aparcamiento quitado: espacio (o B) frena"); } }
/** UAV con las flechas en la torreta: el avion no las ve (las mueve moverTorreta). */
function leerTeclado(dt) {
  if (!(modelo && modelo.uav && torretaConFlechas())) { const r = leerTecladoAvion(dt); moverTorreta(dt); return r; }
  const fl = ["ArrowUp", "ArrowDown", "ArrowLeft", "ArrowRight"], g = fl.map(k => teclas[k]);
  fl.forEach(k => teclas[k] = false);
  try { return leerTecladoAvion(dt); } finally { fl.forEach((k, i) => teclas[k] = g[i]); moverTorreta(dt); }
}
function leerTecladoAvion(dt) {
  if (modelo && modelo.tren && av) av.freno = av.frenoAparc || teclas["Space"] || MANDO.freno ? 1 : 0;
  const cuad = modelo && ((modelo.esCuadricoptero && !modelo.esFPV) || modelo.esTerrestre);     // en el FPV W/S son el gas, como en los aviones; el bipode anda con W/S y A/D
  if (modelo && modelo.esBipode) { mando.disparo = !!teclas["Space"] || !!MANDO.disparo; mando.puno = !!teclas["KeyF"] || !!MANDO.puno; }
  const teclaPalanca = teclas["ArrowDown"] || teclas["ArrowUp"] || teclas["ArrowRight"] || teclas["ArrowLeft"] || teclas["KeyA"] || teclas["KeyD"] || ((cuad || (modelo && modelo.esFPV)) && (teclas["KeyW"] || teclas["KeyS"]));   // en el FPV, W/S tambien devuelven el gas al teclado
  if (teclaPalanca) MANDO.usado = false;                       // si se tocan las flechas, vuelve a mandar el teclado
  if (modelo && modelo.esFPV && (teclas["KeyW"] || teclas["KeyS"])) MANDO.gasFpv = false;   // W/S: el gas vuelve al teclado
  const gimbalTeclas = cuad && !modelo.esTerrestre ? (teclas["KeyE"] ? 1 : 0) - (teclas["KeyQ"] ? 1 : 0) : 0;      // Q/E: rueda del gimbal
  if (leerMando(dt) && !teclaPalanca) { mando.gimbal = gimbalTeclas || MANDO.gimbal; leerGasTeclado(dt); return; }
  mando.gimbal = gimbalTeclas || MANDO.gimbal;
  mando.pitchObj = (teclas["ArrowDown"] ? 1 : 0) - (teclas["ArrowUp"] ? 1 : 0);    // +1 = tirar
  mando.yawObj = (teclas["ArrowRight"] ? 1 : 0) - (teclas["ArrowLeft"] ? 1 : 0);
  mando.guinadaObj = (teclas["KeyD"] ? 1 : 0) - (teclas["KeyA"] ? 1 : 0);                 // cuadricoptero: giro sobre si mismo
  mando.vzObj = (teclas["KeyW"] ? 1 : 0) - (teclas["KeyS"] ? 1 : 0);                      // cuadricoptero: subir / bajar
  for (const k of ["pitch", "yaw", "guinada", "vz"]) {         // la palanca va al tope a 5/s y vuelve al centro a 8/s
    const obj = mando[k + "Obj"], vel = obj === 0 ? 8 : 5, d = obj - mando[k];
    mando[k] += Math.sign(d) * Math.min(Math.abs(d), vel * dt);
  }
  leerGasTeclado(dt);
}
function leerGasTeclado(dt) {
  if (av.motorRoto || (modelo && ((modelo.esCuadricoptero && !modelo.esFPV) || modelo.esTerrestre))) return;      // en el dron comercial W/S son velocidad vertical (leerTeclado); en el bipode, andar
  const k = modelo && modelo.esFPV ? 0.4 : 0.8;                      // FPV: mas despacio (se sostiene con un 30 % de gas)
  if (teclas["KeyW"]) av.gases = Math.min(1, av.gases + k * dt);
  if (teclas["KeyS"]) av.gases = Math.max(0, av.gases - k * dt);
}
