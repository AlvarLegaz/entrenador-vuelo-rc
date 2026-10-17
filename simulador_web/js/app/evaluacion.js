// Escenarios: el punto de lanzamiento en el mundo real, los objetivos y su evaluacion, y el aterrizaje guiado.
// Parte de la aplicacion de simulador_web/simulador.html: los modulos de js/app/ se cargan en orden y comparten el
// ambito global. En Godot: simulador_godot/scripts/app/evaluacion.gd.
"use strict";
// =====================================================================
//  3. ESCENARIOS: objetivos y evaluacion automatica
// =====================================================================
const ESCENARIOS = window.ESCENARIOS;          // datos/escenarios.js y sus ficheros (comunes con la version de Godot)
const zonaDe = id => ESCENARIOS[id].zona || 1;
const mundoDe = id => ESCENARIOS[id].mundo ? Mundos.datos(ESCENARIOS[id].mundo) : null;
// ---- punto de lanzamiento en un mundo real: se elige en un mapa (textura del terreno + carreteras + pueblos) ----
const LANZ_MAPA = { k: 1, x0: 0, y0: 0 };
function casa() {
  if (modelo && modelo.uav && modelo.tren) { const P = pistaActual(); if (P) { const r = P.rumbo * D2R; return { N: P.n + 60 * Math.cos(r), E: P.e + 60 * Math.sin(r), rumbo: P.rumbo }; } }   // UAV de pista: en la cabecera
  return entorno.mundo && sesion.lanz ? sesion.lanz : { N: 0, E: 0 };
}
/** La pista del escenario (escenarios.js "pista" o la de su trabajo), con la altura del suelo en el umbral, o null. */
function pistaActual() {
  const E = ESCENARIOS[sesion.escenario] || {}, P = E.pista || (E.operacion && E.operacion.pista);
  return P && entorno.mundo && entorno.altura ? Object.assign({}, P, { h: entorno.altura(P.n, P.e) }) : null;
}
/** Rumbo de despegue (grados) mas despejado desde (N, E): el de 16 con menos terreno por delante en 1,5 km. */
function rumboDespejado(N, E) {
  let mejor = 0, menos = Infinity;
  for (let r = 0; r < 360; r += 22.5) {
    let sube = -Infinity;
    for (let d = 100; d <= 1500; d += 50) sube = Math.max(sube, entorno.alturaMar(N + d * Math.cos(r * D2R), E + d * Math.sin(r * D2R)));
    if (sube < menos) { menos = sube; mejor = r; }
  }
  return mejor;
}
// punto de lanzamiento por defecto de cada mundo real (si no, el centro de la primera zona de detalle)
const LANZ_DEFECTO = { cartagena: { lat: 37.648889, lon: -1.193194, rumbo: 90 } };     // 37°38'56.0"N 1°11'35.5"W, despegue hacia el este
/** (lat, lon) -> (N, E) en metros desde el origen del mundo, con la misma formula que los scripts de mundo_cartagena. */
function latLonANE(mundo, lat, lon) { const o = mundo.origen; return [(lat - o.lat) * 110574, (lon - o.lon) * 111320 * Math.cos(o.lat * D2R)]; }
async function irLanzamiento() {
  const mundo = mundoDe(sesion.escenario);
  entorno.ponerMundo(mundo); visor.ponerMundo(mundo);              // construye el mundo (y su textura) si hace falta
  await indiceZonas();
  if (!sesion.lanz || sesion.lanz.mundo !== mundo.id) {
    const d = LANZ_DEFECTO[mundo.id], z0 = (ZONAS.indice || []).find(z => z.mundo === mundo.id);
    if (d) { const [N, E] = latLonANE(mundo, d.lat, d.lon); sesion.lanz = { mundo: mundo.id, N: Math.round(N), E: Math.round(E), rumbo: d.rumbo, defecto: true }; }
    else sesion.lanz = z0 ? { mundo: mundo.id, N: Math.round(z0.centro.N), E: Math.round(z0.centro.E), rumbo: rumboDespejado(z0.centro.N, z0.centro.E) }
                          : { mundo: mundo.id, N: 0, E: 0, rumbo: mundo.rumbo_despegue || 0 };
  }
  const cont = document.getElementById("lanzDestacados"); cont.innerHTML = "";
  for (const d of destacadosLanz()) {
    const b = document.createElement("button"); b.className = "btn destacado"; b.textContent = "📍 " + d.nombre; b.title = "Despegar desde " + d.nombre;
    b.onclick = () => elegirDestacado(d); cont.appendChild(b);
  }
  if (necesitaPista() && destacadoConPista() && sesion.lanz.destacado !== destacadoConPista().nombre) { const dp = destacadoConPista(), [N, E] = latLonANE(mundo, dp.lat, dp.lon); sesion.lanz = { mundo: mundo.id, N: Math.round(N), E: Math.round(E), rumbo: dp.rumbo, destacado: dp.nombre }; }
  mostrar("pLanzamiento"); pintarMapaLanz();
}
window.addEventListener("resize", () => { if (pantallaActual === "pLanzamiento") pintarMapaLanz(); });
function pintarMapaLanz() {
  const cv = document.getElementById("mapaLanz"), g = cv.getContext("2d"), M = entorno.mundo, T = M.terreno, L = sesion.lanz;
  const caja = cv.parentElement;          // el lienzo llena su caja sin deformar el mapa (se dibuja a su tamano real)
  if (caja.clientWidth > 50 && (cv.width !== caja.clientWidth || cv.height !== caja.clientHeight)) { cv.width = caja.clientWidth; cv.height = caja.clientHeight; }
  const anchoM = (T.nE - 1) * T.paso, altoM = (T.nN - 1) * T.paso, k = Math.min(cv.width / anchoM, cv.height / altoM);
  LANZ_MAPA.k = k; LANZ_MAPA.x0 = (cv.width - anchoM * k) / 2; LANZ_MAPA.y0 = (cv.height - altoM * k) / 2;
  const X = e => LANZ_MAPA.x0 + (e - T.E0) * k, Y = n => LANZ_MAPA.y0 + (T.N0 + altoM - n) * k;
  g.fillStyle = "#0b0f14"; g.fillRect(0, 0, cv.width, cv.height);
  if (visor.lienzoMundo) g.drawImage(visor.lienzoMundo, X(T.E0), Y(T.N0 + altoM), anchoM * k, altoM * k);
  for (const t of [4, 3, 2, 1]) {
    g.strokeStyle = { 1: "#ffb74d", 2: "#fff176", 3: "#f5f5f5", 4: "#cfd8dc" }[t]; g.lineWidth = { 1: 2, 2: 1.4, 3: 0.9, 4: 0.6 }[t]; g.beginPath();
    for (const c of M.carreteras) { if (c[0] !== t) continue; for (let i = 1; i < c.length; i += 2) i === 1 ? g.moveTo(X(c[i]), Y(c[i + 1])) : g.lineTo(X(c[i]), Y(c[i + 1])); }
    g.stroke();
  }
  g.font = "bold 11px sans-serif"; g.fillStyle = "#fff"; g.strokeStyle = "rgba(0,0,0,0.7)"; g.lineWidth = 3;
  for (const [nombre, rango, e, n] of M.lugares) if (rango <= 4) { g.strokeText(nombre, X(e) + 4, Y(n) - 3); g.fillText(nombre, X(e) + 4, Y(n) - 3); g.fillRect(X(e) - 2, Y(n) - 2, 4, 4); }
  for (const zz of (ZONAS.indice || []).filter(q => q.mundo === M.id)) {                                   // zonas de detalle
    g.strokeStyle = "#ffd54f"; g.lineWidth = 1.5; g.setLineDash([4, 3]); g.strokeRect(X(zz.E0), Y(zz.N0 + zz.lado_m), zz.lado_m * k, zz.lado_m * k); g.setLineDash([]);
    g.fillStyle = "#ffd54f"; g.font = "bold 10px sans-serif"; g.fillText("detalle", X(zz.E0) + 2, Y(zz.N0 + zz.lado_m) - 3);
  }
  for (const d of destacadosLanz()) {                                                                 // puntos destacados (CIFP...)
    const [dN, dE] = latLonANE(M, d.lat, d.lon), x = X(dE), y = Y(dN), sel = L.destacado === d.nombre;
    if (d.contorno) {
      g.beginPath(); d.contorno.forEach(([la, lo], i) => { const [n, e] = latLonANE(M, la, lo); i ? g.lineTo(X(e), Y(n)) : g.moveTo(X(e), Y(n)); }); g.closePath();
      g.fillStyle = "rgba(255,140,0,0.35)"; g.fill(); g.strokeStyle = "#ff8c00"; g.lineWidth = 2; g.stroke();
    }
    g.strokeStyle = "rgba(255,140,0,0.9)"; g.lineWidth = 3; g.beginPath(); g.arc(x, y, 14, 0, 2 * Math.PI); g.stroke();       // anillo
    g.fillStyle = "#ff8c00"; g.beginPath(); g.moveTo(x, y); g.arc(x, y - 26, 9, Math.PI * 0.8, Math.PI * 2.2); g.closePath(); g.fill();   // chincheta
    g.fillStyle = "#fff"; g.beginPath(); g.arc(x, y - 26, 3.5, 0, 2 * Math.PI); g.fill();
    g.font = "bold 14px sans-serif"; const tw = g.measureText(d.nombre).width;
    g.fillStyle = sel ? "#ff8c00" : "rgba(8,14,22,0.88)"; g.beginPath(); g.roundRect(x + 14, y - 46, tw + 16, 24, 6); g.fill();
    g.strokeStyle = "#ff8c00"; g.lineWidth = 1.5; g.stroke(); g.fillStyle = sel ? "#111" : "#fff"; g.fillText(d.nombre, x + 22, y - 29);
    d._xy = [x, y];
  }
  g.fillStyle = "#ff5252"; g.beginPath(); g.arc(X(0), Y(0), 4, 0, 2 * Math.PI); g.fill();              // origen del mundo (el corazon)
  g.fillStyle = "#fff"; g.font = "10px sans-serif"; g.fillText("origen", X(0) + 6, Y(0) + 4);
  const x = X(L.E), y = Y(L.N);                                                                         // punto elegido y rumbo de despegue
  g.strokeStyle = "#ffd54f"; g.lineWidth = 2; g.beginPath(); g.arc(x, y, 9, 0, 2 * Math.PI); g.stroke();
  g.beginPath(); g.moveTo(x, y); g.lineTo(x + 26 * Math.sin(L.rumbo * D2R), y - 26 * Math.cos(L.rumbo * D2R)); g.stroke();
  g.fillStyle = "#ffd54f"; g.beginPath(); g.arc(x, y, 3, 0, 2 * Math.PI); g.fill();
  const M_LAT = 110574, M_LON = 111320 * Math.cos(M.origen.lat * D2R), lat = M.origen.lat + L.N / M_LAT, lon = M.origen.lon + L.E / M_LON;
  const hMar = entorno.alturaMar(L.N, L.E), mar = entorno.enMar(L.N, L.E);
  const dsel = destacadosLanz().find(d => d.nombre === L.destacado);
  document.getElementById("lanzInfo").innerHTML = dsel ? `<b style="color:#ff8c00">${esc(dsel.nombre)}</b> · ${esc(dsel.nota || "")} · despegue con rumbo <b>${L.rumbo.toFixed(0)}°</b>` + (zonaEn(M.id, L.N, L.E) ? "" : ` · <b style="color:#ff6e66">falta su zona de detalle en simulador/zonas</b>`) : mar ? `<b style="color:#ff6e66">Eso es mar: elige un punto en tierra.</b>` :
    `Punto elegido: <b>${lat.toFixed(5)} N, ${(-lon).toFixed(5)} O</b> · ${hMar.toFixed(0)} m sobre el mar · a ${(Math.hypot(L.N, L.E) / 1000).toFixed(1)} km del origen · despegue con rumbo <b>${L.rumbo.toFixed(0)}°</b> (${L.defecto ? "punto de salida por defecto, hacia el este" : "el más despejado"}) · escala: ${(anchoM / 1000).toFixed(0)} km de ancho` +
    (zonaEn(M.id, L.N, L.E) ? ` · <b style="color:#ffd54f">dentro de una zona de detalle</b> (foto a 0,5 m, terreno a 5 m, edificios y árboles reales)` : ` · fuera de las zonas de detalle (recuadros amarillos): terreno a 150 m y foto a 12 m`);
  document.getElementById("btnLanzAqui").disabled = mar;
}
document.getElementById("mapaLanz").addEventListener("click", e => {
  const cv = e.currentTarget, r = cv.getBoundingClientRect(), x = (e.clientX - r.left) * cv.width / r.width, y = (e.clientY - r.top) * cv.height / r.height;
  const T = entorno.mundo.terreno, altoM = (T.nN - 1) * T.paso, E = T.E0 + (x - LANZ_MAPA.x0) / LANZ_MAPA.k, N = T.N0 + altoM - (y - LANZ_MAPA.y0) / LANZ_MAPA.k;
  if (E < T.E0 || E > T.E0 + (T.nE - 1) * T.paso || N < T.N0 || N > T.N0 + altoM) return;
  const d = destacadosLanz().find(q => q._xy && (Math.hypot(x - q._xy[0], y - q._xy[1]) < 18 || Math.hypot(x - q._xy[0], y - q._xy[1] + 26) < 14));
  if (d) { elegirDestacado(d); return; }
  if (necesitaPista() && destacadoConPista()) { elegirDestacado(destacadoConPista()); return; }    // un avion de pista no sale del campo
  sesion.lanz = { mundo: entorno.mundo.id, N: Math.round(N), E: Math.round(E), rumbo: rumboDespejado(N, E) };
  pintarMapaLanz();
});
/** Puntos de despegue destacados del vuelo libre en el mundo real (escenarios.js: "destacados"). */
function destacadosLanz() { return (ESCENARIOS[sesion.escenario] || {}).destacados || []; }
/** El vehiculo elegido despega de pista (el Cernicalo XM-7): solo sale de un destacado con "pista" (la base de San Javier). */
const necesitaPista = () => !!(Modelos.datos(sesion.avion) || {}).tren;     // los de tren (el Cernicalo) despegan de pista; el Grajo, a mano
const destacadoConPista = () => destacadosLanz().find(d => d.pista);
function elegirDestacado(d) {
  if (necesitaPista() && !d.pista && destacadoConPista()) { d = destacadoConPista(); toast(Modelos.datos(sesion.avion).nombre + " despega de pista: sale de " + d.nombre); }
  const M = entorno.mundo, [N, E] = latLonANE(M, d.lat, d.lon);
  sesion.lanz = { mundo: M.id, N: Math.round(N), E: Math.round(E), rumbo: d.rumbo, destacado: d.nombre };
  pintarMapaLanz();
}
document.getElementById("btnLanzVolver").onclick = () => irVolar();
document.getElementById("btnLanzAqui").onclick = () => empezar();
/** Coloca un estado recien creado en el punto de lanzamiento del mundo real (en la isla, en el origen). */
function colocarEnBase(a, m = modelo) {
  if (m && m.esTerrestre) {            // el bipode, de pie en el suelo, delante del piloto (en el campo, 10 m al norte)
    if (!entorno.mundo) { a.p = [10, 0, 0]; return; }
    const c = casa(); a.p = [c.N, c.E, -entorno.altura(c.N, c.E)]; return;
  }
  if (m && m.tren) {                   // avion de pista: sobre sus ruedas
    const c = entorno.mundo ? casa() : { N: 0, E: 0 }; a.p = [c.N, c.E, -((entorno.mundo ? entorno.altura(c.N, c.E) : 0) + m.alturaEnTierra())]; return;
  }
  if (!entorno.mundo) return;
  const c = casa(); a.p = [c.N, c.E, -(entorno.altura(c.N, c.E) + (m && m.esCuadricoptero ? 0.02 : 1.6))];   // en la mano (avion) o en el suelo (dron)
}

let ev = null;     // evaluador del vuelo en curso
let piloto = null; // UAV: su piloto automatico (js/piloto_uav.js)
function nuevoEvaluador() {
  ev = { obj: Object.fromEntries(ESCENARIOS[sesion.escenario].objetivos.map(([id, t]) => [id, { texto: t, estado: "pend" }])),
         contador: entorno.contadorVueltas(ESCENARIOS[sesion.escenario].sentido || 0), zona: zonaDe(sesion.escenario),
         pasada: entorno.pasadaBaja(), pasadas: { este: 0, oeste: 0 }, puertas: 0, pasoPuerta: 0, subido: false, toma: null, acumRumbo: 0, rumboPrev: null, giros: [], perdidaT: 0,
         t40: null, tFallo: null, falloHecho: false };
  for (const k of ["cerca", "sinPerdida", "modo", "bateria", "bajo4", "altura13", "techo", "vlos", "zona", "baja", "distancia", "suave", "atex", "unidades", "altura", "minima", "ruido"]) if (ev.obj[k]) ev.obj[k].estado = "curso";
  const O = ESCENARIOS[sesion.escenario].operacion;
  ev.op = null;
  if (O && entorno.mundo) {                    // operaciones: el trabajo, con los desperfectos, las manchas o el senderista en sitios al azar de la zona
    const d = Operacion.sortear(Operacion.ajustar(O, MULTI.sala && MULTI.sala.ajustes)), c = casa();
    ev.op = new Operacion(d, (k, e) => marcar(k, e), (k, t) => { if (ev.obj[k]) ev.obj[k].texto += ` (${t})`; }, { casa: [c.N, c.E], suelo: (N, E) => entorno.altura(N, E), h0: entorno.terreno.h0, solido: (N, E, up) => !!(entorno.chocaEdificio && entorno.chocaEdificio([N, E, -up], 0)) });
  }
  const F = ESCENARIOS[sesion.escenario].pista_fpv;
  ev.fpv = F && !mundoDe(sesion.escenario) ? new PistaFpv(F, (k, e) => marcar(k, e)) : null;   // entrenamientos del dron FPV
}
function marcar(id, estado) { if (ev.obj[id] && ev.obj[id].estado !== "mal") ev.obj[id].estado = estado; }
const desenrollar = d => d - 2 * Math.PI * Math.round(d / (2 * Math.PI));
function evaluar(dt) {
  if (!ev || av.estado !== "volando") return;
  vigilarExclusiones();
  const h = -av.p[2], N = av.p[0], E = av.p[1], dist = Math.hypot(N, E), t = av.t;
  if (h >= 20) { marcar("subir", "ok"); ev.subido = true; }
  if (h >= 40) { marcar("subir40", "ok"); if (ev.t40 === null) { ev.t40 = t; ev.tFallo = t + 8 + 12 * Math.random(); } }
  // vueltas al circuito por fuera de los 4 pilones (las cuenta el Entorno en cada paso)
  if (ev.contador.vueltas >= 1) marcar("circ1", "ok"); if (ev.contador.vueltas >= 2) marcar("circ2", "ok");
  // zona 2: puertas y pasadas bajas (las cuentan paso() y el Entorno: zona2(), que marca tambien las puertas de su mision,
  // en orden); en el recorrido, cada cosa despues de la anterior
  if (ev.pasadas.oeste) marcar("pasadaO", "ok"); if (ev.pasadas.este) marcar("pasadaE", "ok");
  if (ev.pasadas.oeste + ev.pasadas.este) marcar("pasada", "ok");
  // ochos alrededor de los pilones: por fuera del par derecho (rojo y azul), por el centro, por fuera del par izquierdo
  // (amarillo y verde), por el centro y vuelta al rojo. Se sigue por pasos con la posicion (N, E)
  if (ev.obj.ocho1) { const o = pasoOcho(N, E); if (o >= 1) marcar("ocho1", "ok"); if (o >= 2) marcar("ocho2", "ok"); }
  if (dist > 500) marcar("cerca", "mal");
  // perdida: mas de 0,3 s seguidos con perdida > 0,6 (despues del lanzamiento)
  ev.perdidaT = av.perdida > 0.6 && t > 3 ? ev.perdidaT + dt : 0;
  if (ev.perdidaT > 0.3) { marcar("sinPerdida", "mal"); if (ev.falloHecho) marcar("fallo", "mal"); }
  // emergencia: el motor se para a los 8-20 s de llegar a 40 m
  if (sesion.escenario === "emergencia" && ev.tFallo !== null && !ev.falloHecho && t >= ev.tFallo) {
    ev.falloHecho = true; av.motorRoto = true; av.gases = 0; marcar("fallo", "curso");
    aviso("¡FALLO DE MOTOR!"); setTimeout(() => { if (av.estado === "volando") aviso(""); }, 2500);
  }
  if (ev.guia) guiar();
}

/** Pasos del ocho de la mision de orientacion con la posicion del avion; devuelve los ochos completos. */
const OCHO_PASOS = ["por fuera del rojo y el azul", "cruzar el centro", "por fuera del amarillo y el verde", "cruzar el centro", "volver al pilón rojo"];
function pasoOcho(N, E) {
  const P = entorno.circuito.pilones, es = P.map(p => p[1]), ns = P.map(p => p[0]);
  const eDer = Math.max(...es), eIzq = Math.min(...es), nMin = Math.min(...ns) - 15, nMax = Math.max(...ns) + 15, rojo = P[2];
  const enFranja = N > nMin && N < nMax;
  if (ev.ochoFase === undefined) { ev.ochoFase = 0; ev.ochos = 0; }
  const f = ev.ochoFase;
  if (f === 0 && enFranja && E > eDer + 5) ev.ochoFase = 1;                                   // por fuera del par derecho
  else if (f === 1 && Math.abs(E) < 15) ev.ochoFase = 2;                                      // cruza el centro
  else if (f === 2 && enFranja && E < eIzq - 5) ev.ochoFase = 3;                              // por fuera del par izquierdo
  else if (f === 3 && Math.abs(E) < 15) ev.ochoFase = 4;                                      // cruza el centro
  else if (f === 4 && Math.hypot(N - rojo[0], E - rojo[1]) < 45) { ev.ochoFase = 0; ev.ochos++; toast(`¡Ocho ${ev.ochos}!`); }   // vuelta al rojo
  if (ev.ochoFase !== f && ev.ochoFase) toast(OCHO_PASOS[ev.ochoFase].replace(/^./, c => c.toUpperCase()));
  return ev.ochos;
}
function textoOcho() {
  if (ev.ochoFase === undefined) return "";
  if (ev.ochos >= 2) return `<div style="margin:4px 0">Los dos ochos hechos · Ahora: <b>aterrizar</b></div>`;
  return `<div style="margin:4px 0">Ocho ${ev.ochos + 1} de 2 · Ahora: <b>${OCHO_PASOS[ev.ochoFase]}</b></div>`;
}

// ---- aterrizaje guiado: tramos del circuito, con lo que hay que hacer en cada uno y las pistas en vivo ----
// rumbo: el objetivo del tramo; giro: 1 si el tramo es un viraje a la derecha (el rumbo que falta se mide en sentido
// horario: si no, con el objetivo a 180 grados cualquier bandazo cambia "el camino mas corto" de lado); h, gas, e:
// bandas (altura m, gas 0-1, posicion este m) fuera de las que se avisa; fin(s): cuando se da por hecho el tramo (s =
// lo que ve el piloto). Los virajes son todos a la derecha: el circuito pasa por la derecha del piloto (este) y la
// toma es rumbo norte, hacia la pista que tiene delante.
const GUIA_TRAMOS = [
  { id: "nivelar", texto: "Vuelas a 35 m sobre la pista, rumbo norte. Pon el gas al 50 % (S) y mantén el avión recto y nivelado hasta pasar el final de la pista.",
    rumbo: 0, h: [28, 42], gas: [0.4, 0.65], fin: s => s.N > 110 },
  { id: "viraje1", texto: "Vira a la DERECHA (→) hasta rumbo 180° (sur): inclina unos 30° y tira un poco para no perder altura. Suelta el alabeo antes de llegar al rumbo.",
    rumbo: 180, giro: 1, h: [24, 42], gas: [0.4, 0.65], fin: s => Math.abs(s.err) < 25 && s.E > 20 },
  { id: "viento_cola", texto: "Tramo con el viento en cola: recto rumbo 180°, pasando por tu derecha a 60–100 m. Baja el gas al 40 % (S) y deja que descienda a 20 m. Sigue hasta pasar por detrás de ti.",
    rumbo: 180, h: [15, 30], gas: [0.3, 0.5], e: [30, 130], fin: s => s.N < -50 },
  { id: "base", texto: "Base: vira a la DERECHA a rumbo 270° (oeste), gas al 30 %, y baja a 10–15 m. Cuando tengas la pista delante a la derecha, prepara el último viraje.",
    rumbo: 270, giro: 1, h: [8, 20], gas: [0.2, 0.4], fin: s => s.E < 35 && Math.abs(s.err) < 30 },
  { id: "final", texto: "Final: vira a la DERECHA a rumbo 0° (norte) y alinéate con la pista. Gas al 20–30 %, morro un poco abajo, velocidad por encima de VMIN m/s. No tires de la profundidad hasta estar a 2 m.",
    rumbo: 0, giro: 1, h: [0, 14], gas: [0.1, 0.35], e: [-15, 15], fin: s => s.h < 2.5 && Math.abs(s.err) < 35 },
  { id: "toma", texto: "¡Ahora! Corta el gas (espacio) y tira un poquito (↓) para aplanar: deja que se pose solo, sin inclinar las alas.",
    rumbo: 0, h: [0, 3], gas: [0, 0.08], fin: () => false },
];
/** Velocidad de perdida del avion (la de su ficha; si no, la formula con CLmax 1,1). */
function velPerdida() {
  const A = Modelos.datos(sesion.avion), fila = (A.caracteristicas || []).find(r => r[0].toLowerCase().startsWith("velocidad de p"));
  const v = fila ? parseFloat(String(fila[1]).replace(",", ".")) : NaN;
  return isNaN(v) ? Math.sqrt(2 * modelo.masa_kg * G0 / (RHO * modelo.S_m2 * 1.1)) : v;
}
/** Coloca el avion en vuelo (escenarios con enVuelo), como si acabara de lanzarse y subir: empieza el registro del vuelo. */
function empezarEnVuelo() {
  const C = ESCENARIOS[sesion.escenario].enVuelo, vs = velPerdida();
  const V0 = Math.max(modelo.lanzamiento.vel_ms + 1, 1.35 * vs);
  av.p = [C.N, C.E, -C.h]; av.q = Cuat.desdeEuler(0, 3 * D2R, C.rumbo * D2R); av.v = [V0, 0, 0]; av.w = [0, 0, 0];
  av.gases = C.gas; av.estado = "volando";
  if (modelo.armarEnVuelo) modelo.armarEnVuelo(av);           // dron FPV: armado y con el gas que lo sostiene
  vuelo = { id: uuid4(), inicio: new Date(), tVuelo: 0, filas: [], final: null, escenario: sesion.escenario, dificultad: sesion.dificultad, gasLanz: av.gases, hmax: C.h };
  cnContador = 0; RegistroVuelo.empezar(vuelo); grabarMuestra();
  ev.guia = { i: 0, vs, vmin: Math.round(1.3 * vs * 10) / 10, avisado: false };
  aviso(""); guiar();
}
const errRumbo = (rumbo, obj) => desenrollar((obj - rumbo) * D2R) * R2D;   // > 0: el objetivo queda a la derecha
/** Rumbo que falta hasta obj girando a la derecha (0-340); si ya se ha pasado un poco, negativo (pequena correccion a la izquierda). */
function errRumboDerecha(rumbo, obj) { const e = (obj - rumbo + 360) % 360; return e > 340 ? e - 360 : e; }
/** Un paso de la guia: comprueba si el tramo esta hecho, pasa al siguiente y escribe la instruccion y las pistas. */
function guiar() {
  const g = ev.guia, F = GUIA_TRAMOS[g.i];
  const [roll, pitch, yaw] = Cuat.euler(av.q), h = -av.p[2];
  const s = { N: av.p[0], E: av.p[1], h, V: av.V || Math.hypot(...av.v), gas: av.gases, rumbo: (yaw * R2D + 360) % 360, roll: roll * R2D };
  s.err = F.giro ? errRumboDerecha(s.rumbo, F.rumbo) : errRumbo(s.rumbo, F.rumbo);
  if (F.fin(s) && g.i < GUIA_TRAMOS.length - 1) {
    marcar(F.id, "ok"); g.i++;
    const sig = GUIA_TRAMOS[g.i];
    marcar(sig.id, "curso");
    toast(sig.id === "toma" ? "¡Corta gas y aplana!" : "Tramo " + g.i + " de 5: " + (ev.obj[sig.id] ? ev.obj[sig.id].texto.replace(/^\d\. /, "") : sig.id));
    return guiar();
  }
  // pistas en vivo, por orden de importancia: velocidad, rumbo, posicion, altura, gas (se muestran dos como mucho)
  const P = [];
  let peligro = false;
  if (s.V < 1.1 * g.vs && h > 1) { P.push(`¡VELOCIDAD ${s.V.toFixed(1)} m/s! Baja el morro (↑) o da gas (W)`); peligro = true; }
  if (F.id === "base" && s.E > 35 && Math.abs(s.err) < 30) P.push(`Sigue recto al oeste hasta tener la pista casi delante (te faltan ${(s.E - 20).toFixed(0)} m)`);
  if (Math.abs(s.roll) > 45) P.push(`¡Alabeo ${Math.abs(s.roll).toFixed(0)}°! Nivela las alas (${s.roll > 0 ? "←" : "→"})`);
  if (Math.abs(s.err) > 20) P.push(`Rumbo ${s.rumbo.toFixed(0)}° → ${F.rumbo}°: gira a la ${s.err > 0 ? "derecha (→)" : "izquierda (←)"}`);
  if (F.e && (s.E < F.e[0] || s.E > F.e[1]))
    P.push(F.id === "final" ? `Estás ${Math.abs(s.E).toFixed(0)} m a la ${s.E > 0 ? "derecha" : "izquierda"} de la pista: corrige con un poco de ${s.E > 0 ? "←" : "→"}`
                            : `Vas a ${s.E.toFixed(0)} m al este: el tramo va a 60–100 m de ti`);
  if (h < F.h[0]) P.push(`Altura ${h.toFixed(0)} m: demasiado bajo, un poco de gas (W)`);
  else if (h > F.h[1]) P.push(`Altura ${h.toFixed(0)} m: demasiado alto, quita gas (S) y baja el morro`);
  const gm = Math.round((F.gas[0] + F.gas[1]) * 50);
  if (s.gas < F.gas[0] - 0.02) P.push(`Gas ${(s.gas * 100).toFixed(0)} %: súbelo al ${gm} % (W)`);
  else if (s.gas > F.gas[1] + 0.02) P.push(`Gas ${(s.gas * 100).toFixed(0)} %: bájalo al ${gm} % (S)`);
  const el = document.getElementById("guia");
  el.innerHTML = `<b>${g.i + 1}/6</b> · ${esc(F.texto.replace("VMIN", String(g.vmin)))}` +
    (P.length ? `<small class="${peligro ? "peligro" : ""}">${esc(P.slice(0, 2).join("  ·  "))}</small>` : `<small>Vas bien: sigue así</small>`);
}
function evaluarFinal(final, vn) {
  const N = av.p[0], E = av.p[1], ok = final === "aterrizado";
  if (ok) {
    marcar("aterrizar", sesion.escenario === "emergencia" && !ev.falloHecho ? "mal" : "ok");
    const enPista = entorno.enPista(N, E);
    marcar("enPista", enPista ? "ok" : "mal");
    const tr = Math.atan2(vn[1], vn[0]) * R2D, desv = Math.min(Math.abs(tr), 180 - Math.abs(tr));
    marcar("alineado", enPista && desv <= 25 ? "ok" : "mal");
    marcar("cerca100", ev.falloHecho && Math.hypot(N, E) <= 100 ? "ok" : "mal");
    ev.toma = entorno.diana(N, E);
    marcar("suave", vn[2] < 1.5 ? "ok" : "mal");            // vn[2] > 0 es hacia abajo (NED): descenso en la toma
    marcar("diana10", ev.toma.d <= 10 ? "ok" : "mal");
    marcar("dianaR", ev.toma.d <= 10 && ev.obj.puertaR && ev.obj.puertaR.estado === "ok" ? "ok" : "mal");
  }
  if (ev.fpv) ev.fpv.final(final, av);
  if (ev.op) ev.op.final(final, av, { bateria: modelo.bateriaPct(av), automatico: !!(piloto && piloto.automatico) });
  // lo que seguia "en curso" solo cuenta si el vuelo acabo en un aterrizaje; lo pendiente, no se hizo
  for (const o of Object.values(ev.obj)) if (o.estado === "curso") o.estado = ok ? "ok" : "mal";
  for (const o of Object.values(ev.obj)) if (o.estado === "pend") o.estado = "mal";
}
function textoVueltas() {
  const c = ev && ev.contador;
  if (!c) return "";
  const z2 = `Pasos por la puerta: <b>${ev.puertas}</b> · pasadas bajas válidas: <b>${ev.pasadas.este + ev.pasadas.oeste}</b>` +
    (ev.toma && ev.toma.d <= 40 ? ` · toma a <b>${ev.toma.d.toFixed(1)} m</b> de la diana: <b>${ev.toma.puntos} puntos</b>` : "");
  const z1 = `Vueltas por fuera de los pilones: <b>${c.vueltas}</b>` + (c.mejor !== null ? ` · mejor ${c.mejor.toFixed(1)} s` : "");
  if (ev.zona === 2) return z2;
  return sesion.escenario === "libre" && (ev.puertas || ev.pasadas.este + ev.pasadas.oeste || (ev.toma && ev.toma.d <= 40)) ? z1 + "<br>" + z2 : z1;
}
// la mision de la puerta: las dos puertas de la zona 2, una despues de la otra, dos veces
const PUERTAS_ORDEN = ["naranja", "verde", "naranja", "verde"];
// zona 2: que toca ahora
function textoZona2() {
  const id = sesion.escenario, o = ev.obj, hecho = k => o[k] && o[k].estado === "ok";
  let sig = "";
  if (!ev.subido) sig = "sube a 20 m";
  else if (id === "puerta") sig = ev.pasoPuerta < PUERTAS_ORDEN.length ? `cruzar la puerta ${PUERTAS_ORDEN[ev.pasoPuerta]} (${ev.pasoPuerta}/${PUERTAS_ORDEN.length})` : "aterrizar";
  else if (id === "pasada_baja") sig = !hecho("pasadaO") ? "pasada baja hacia el oeste (de izquierda a derecha)" : !hecho("pasadaE") ? "pasada baja hacia el este (de derecha a izquierda)" : "aterrizar";
  else if (id === "diana") sig = "aterrizar en la diana";
  else if (id === "recorrido") sig = !hecho("pasada") ? "1. pasada baja por la pista 2 (2 a 8 m)" : !hecho("puertaR") ? "2. cruzar la puerta naranja" : "3. aterrizar en la diana";
  return `<div style="margin:4px 0">Zona 2, detrás de ti · Ahora: <b>${sig}</b></div>`;
}
// pilones de colores (Entorno.circuito.colores): orden de paso de un sentido y el pilon que toca ahora
function pilonHTML(i, mayus) {
  const c = entorno.circuito.colores[i];
  return `<span style="white-space:nowrap"><span style="display:inline-block;width:10px;height:10px;border-radius:50%;background:${c.hex};border:1px solid #fff8;margin-right:3px"></span>${mayus ? c.nombre.toUpperCase() : c.nombre}</span>`;
}
function ordenHTML(sentido) {
  const idx = [0, 1, 2, 3];
  return (sentido > 0 ? idx : idx.reverse()).map(i => pilonHTML(i)).join(" → ");
}
function textoOrden() {
  const E = ESCENARIOS[sesion.escenario], c = ev && ev.contador;
  if (!c) return "";
  const sig = c.siguiente();
  return `<div style="margin:4px 0">${E.sentido ? "Orden: " + ordenHTML(E.sentido) : "Pilones en cualquier sentido"}</div>` +
    `<div style="margin-bottom:4px">Siguiente pilón: <b>${sig === null ? (E.sentido ? "el que quieras para salir" : "el que quieras") : pilonHTML(sig, true)}</b></div>`;
}
function pintarObjetivos() {
  const el = document.getElementById("objetivos"), E = ESCENARIOS[sesion.escenario];
  if (E.mundo && ev && ev.op) {                // operacion: lo que toca ahora y la orden de trabajo
    const icono = { ok: "✔", mal: "✘", pend: "○", curso: "◔" }, clase = { ok: "ob-ok", mal: "ob-mal", pend: "ob-pend", curso: "ob-curso" };
    el.innerHTML = `<h3>${esc(E.nombre)}</h3><div style="margin:4px 0">${ev.op.ahora(ev.obj, av)}</div>` + Object.values(ev.obj).map(o => `<div class="${clase[o.estado]}">${icono[o.estado]} ${esc(o.texto)}</div>`).join("") +
      (sesion.alumno ? `<div style="margin-top:6px;color:#aaa;font-size:12px">${esc(sesion.alumno.nombre)}</div>` : "");
    return;
  }
  if (E.mundo) {
    const h = -av.p[2], suelo = entorno.altura ? entorno.altura(av.p[0], av.p[1]) : 0;
    el.innerHTML = `<h3>${esc(E.nombre)}</h3><div>Terreno a ${(suelo + mundoDe(sesion.escenario).terreno.h0).toFixed(0)} m sobre el mar · casa a <b>${Math.hypot(av.p[0] - casa().N, av.p[1] - casa().E).toFixed(0)} m</b></div>`;
    return;
  }
  if (!E.objetivos.length) { el.innerHTML = `<h3>${esc(E.nombre)}</h3>${textoOrden()}${textoVueltas()}`; return; }
  const icono = { ok: "✔", mal: "✘", pend: "○", curso: "◔" }, clase = { ok: "ob-ok", mal: "ob-mal", pend: "ob-pend", curso: "ob-curso" };
  el.innerHTML = `<h3>${esc(E.nombre)}</h3>` + (ev.obj.circ1 ? textoOrden() : "") + (ev.obj.ocho1 ? textoOcho() : "") + (ev.zona === 2 && !ev.fpv ? textoZona2() : "") + (ev.fpv ? `<div style="margin:4px 0">${textoFpv(ev.fpv.ahora(ev.obj, av), true)}</div>` : "") + Object.values(ev.obj).map(o => `<div class="${clase[o.estado]}">${icono[o.estado]} ${esc(o.texto)}</div>`).join("") +
    (sesion.alumno ? `<div style="margin-top:6px;color:#aaa;font-size:12px">${esc(sesion.alumno.nombre)}</div>` : "");
}
