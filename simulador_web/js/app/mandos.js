// Teclado y mando (Gamepad API: mando de consola o emisora por USB, con su asistente).
// Parte de la aplicacion de simulador_web/simulador.html: los modulos de js/app/ se cargan en orden y comparten el
// ambito global. En Godot: simulador_godot/scripts/app/mandos.gd.
"use strict";
// =====================================================================
//  TECLADO
// =====================================================================
const teclas = {};
let mostrarHud = false, sinInstrumentos = false;   // H: datos en texto; I: quita horizonte, GPS y relojes (en el campo no los hay)
window.addEventListener("keydown", e => {
  if (pantallaActual !== null || document.getElementById("modal").classList.contains("activa")) return;
  Sonido.iniciar();
  if (Repeticion.activa) {        // repeticion: espacio pausa, flechas 5 s, 1/2/3 camara, Esc sale
    if (e.code === "Escape") salirRepeticion();
    if (e.code === "Space") { Repeticion.pausa = !Repeticion.pausa; e.preventDefault(); }
    if (e.code === "ArrowLeft") Repeticion.t = Math.max(0, Repeticion.t - 5);
    if (e.code === "ArrowRight") Repeticion.t = Math.min(Repeticion.dur, Repeticion.t + 5);
    if (e.code === "Digit1") visor.camara = 1; if (e.code === "Digit2") visor.camara = 2; if (e.code === "Digit3") visor.camara = 3;
    if (e.code.startsWith("Arrow")) e.preventDefault();
    return;
  }
  if (e.code === "Escape") {        // con la ventana de controles abierta, Esc la cierra (y sigue el vuelo); si no, pausa
    const a = document.getElementById("ayuda");
    if (verBriefing.abierto) verBriefing(false);
    else if (a.style.display === "block") { a.style.display = "none"; ponerPausa(false); } else ponerPausa(!pausado);
    return;
  }
  if (pausado) return;
  teclas[e.code] = true;
  const libre = !ESCENARIOS[sesion.escenario].objetivos.length, vto = entorno.viento, dron = !!modelo.esCuadricoptero;
  if (modelo.esBipode) {            // bipode: L arranca / aparca; espacio dispara y F cierra el puño (mientras se tienen pulsados)
    if (e.code === "KeyL") lanzar();
    if (e.code === "KeyR") reiniciar();
    if (e.code === "Digit1") visor.camara = 1; if (e.code === "Digit2") visor.camara = 2; if (e.code === "Digit3") visor.camara = 3;
    if (e.code === "KeyT") { const a = document.getElementById("ayuda"); a.style.display = a.style.display === "block" ? "none" : "block"; }
    if (e.code.startsWith("Arrow") || e.code === "Space") e.preventDefault();
    return;
  }
  if (modelo.esFPV) {               // dron FPV: L arma y desarma, M cambia de modo
    if (e.code === "KeyM") fpvModo();
    if (e.code === "KeyL") fpvArmar();
  } else if (dron) {                // teclas de la app y del mando del dron comercial
    if (e.code === "KeyM") djiModo();
    if (e.code === "KeyH") djiRTH();
    if (e.code === "KeyF") djiFoto();
    if (e.code === "KeyV") djiVideo();
    if (e.code === "KeyZ") djiZoom(1);
    if (e.code === "KeyX") djiZoom(-1);
    if (e.code === "KeyC") djiTermica();
  }
  if (e.code === "KeyL" && !modelo.esFPV) lanzar();
  if (e.code === "KeyR") reiniciar();
  if (e.code === "KeyB") verBriefing();
  if (e.code === "Space") { if (modelo.tren) quitarFrenoAparc(); else av.gases = 0; e.preventDefault(); }
  if (e.code === "Digit1") visor.camara = 1; if (e.code === "Digit2") visor.camara = 2; if (e.code === "Digit3") visor.camara = 3;
  if (modelo.uav) {                 // UAV: M modo del piloto automatico, H vuelta a base, P despegue o aterrizaje automatico
    if (e.code === "KeyM") uavModo();
    if (e.code === "KeyH") uavPoner("BASE");
    if (e.code === "KeyP") uavPoner(av.enTierra ? "DESPEGUE" : "ATERRIZAJE");
    if (e.code === "KeyZ") djiZoom(1);
    if (e.code === "KeyX") djiZoom(-1);
    if (e.code === "KeyC") djiTermica();
    if (e.code === "KeyK") uavFijar();
    if (e.code === "KeyV" && morroDe(sesion.avion) === "fijo") cambiarVistaFija();
    if (e.code === "KeyF") uavFoto();
  } else if (e.code === "KeyH" && !dron) mostrarHud = !mostrarHud;
  if (e.code === "KeyF" && !modelo.uav && !dron && ev && ev.op && ev.op.d.recon) avionFoto();      // reconocimiento con el Poli-1 o el Entrenador 1
  if (e.code === "KeyI") { sinInstrumentos = !sinInstrumentos; toast(modelo.esFPV ? (sinInstrumentos ? "Sin OSD" : "OSD") : dron ? (sinInstrumentos ? "Sin la pantalla de la app" : "Pantalla de la app") : sinInstrumentos ? "Sin instrumentos (como en el campo)" : "Instrumentos"); }
  if (e.code === "KeyT") { const a = document.getElementById("ayuda"); a.style.display = a.style.display === "block" ? "none" : "block"; }
  if (e.code === "KeyG" && libre) vto.rachas = !vto.rachas;
  if (e.code === "BracketLeft") mando.trim = Math.max(-6, mando.trim - 0.25);
  if (e.code === "BracketRight") mando.trim = Math.min(6, mando.trim + 0.25);
  if ((e.key === "+" || e.code === "NumpadAdd") && libre) vto.base = Math.min(10, vto.base + 1);
  if ((e.key === "-" || e.code === "NumpadSubtract") && libre) vto.base = Math.max(0, vto.base - 1);
  if (e.code.startsWith("Arrow")) e.preventDefault();
});
window.addEventListener("keyup", e => { teclas[e.code] = false; });
window.addEventListener("blur", () => { for (const k in teclas) teclas[k] = false; });
// =====================================================================
//  MANDO (Gamepad API): palanca derecha = avion (profundidad y alerones/timon), palanca izquierda = gas.
//  Proporcional, con zona muerta y exponencial propia. Sirve un mando de consola o una emisora RC por USB (que
//  el sistema ve como joystick). Si el mando se mueve, manda el mando; si no, el teclado.
// =====================================================================
// Orden de los ejes: para cada palanca (modo 2), el indice del eje en el Gamepad API y su signo, para llevarlo a la
// convencion interna: lx izquierda horizontal (+ derecha), ly izquierda vertical (- arriba), rx derecha horizontal
// (+ derecha), ry derecha vertical (- arriba = empujada). Un mando de consola sigue el orden "standard" del navegador;
// una emisora por USB manda sus canales en su orden (AETR en EdgeTX/OpenTX, TAER en Spektrum/Futaba) y con la
// palanca arriba en +1, por eso las verticales llevan signo -1. Si no coincide, el asistente lo detecta moviendo.
const PERFILES_MANDO = {
  consola: { lx: [0, 1], ly: [1, 1], rx: [2, 1], ry: [3, 1] },
  aetr: { rx: [0, 1], ry: [1, -1], ly: [2, -1], lx: [3, 1] },
  taer: { ly: [0, -1], rx: [1, 1], ry: [2, -1], lx: [3, 1] },
};
const PALANCAS = [["ly", "Gas (izquierda, vertical)"], ["lx", "Timón / guiñada (izquierda, horizontal)"], ["rx", "Alabeo (derecha, horizontal)"], ["ry", "Profundidad (derecha, vertical)"]];
const ejesDe = perfil => { const P = PERFILES_MANDO[perfil], e = {}; for (const k in P) e[k] = { i: P[k][0], s: P[k][1] }; return e; };
// exponencial: el centro de la palanca mueve poco y el extremo da todo el recorrido. Un mando de consola, de palancas cortas,
// necesita mas (60 %) que una emisora (30 %, que ademas suele llevar la suya)
const EXPO_DEFECTO = { consola: 0.6, emisora: 0.3 };
const MANDO = { gas: "incremental", expo: EXPO_DEFECTO.consola, zona: 0.06, botones: [], activo: false, id: "", perfil: "consola", ejes: ejesDe("consola") };
try {
  const g = JSON.parse(localStorage.getItem("sim_mando") || "{}");
  if (g.gas) MANDO.gas = g.gas; if (g.expo !== undefined) MANDO.expo = g.expo;
  if (g.perfil) MANDO.perfil = g.perfil;
  if (g.ejes && PALANCAS.every(([k]) => g.ejes[k] && Number.isInteger(g.ejes[k].i))) MANDO.ejes = g.ejes;
  // hasta el 2026-10-13 el defecto era 30 % para todo: con un mando de consola se queda en el defecto nuevo
  if (!g.v && MANDO.perfil === "consola" && MANDO.expo === 0.3) MANDO.expo = EXPO_DEFECTO.consola;
} catch (e) {}
function guardarMando() { try { localStorage.setItem("sim_mando", JSON.stringify({ v: 2, gas: MANDO.gas, expo: MANDO.expo, perfil: MANDO.perfil, ejes: MANDO.ejes })); } catch (e) {} }
/** Valor de una palanca (lx, ly, rx, ry) en la convencion interna, sin zona muerta. */
function ejeMando(ax, k) { const e = MANDO.ejes[k]; return Math.max(-1, Math.min(1, (ax[e.i] || 0) * e.s)); }
function pintarMandoCfg() {
  document.getElementById("mandoGas").value = MANDO.gas;
  document.getElementById("mandoExpo").value = Math.round(MANDO.expo * 100);
  const e = MANDO.expo, media = (1 - e) * 0.5 + e * 0.125;          // a media palanca (la misma curva que expo())
  document.getElementById("mandoExpoTxt").textContent = `${Math.round(e * 100)} % · a media palanca, el ${Math.round(media * 100)} % del recorrido`;
  document.getElementById("mandoPerfil").value = MANDO.perfil;
  const p = mandoConectado();
  document.getElementById("mandoEstado").innerHTML = p ? `<b style="color:#8be08f">Mando conectado:</b> ${esc(p.id)} · ${p.axes.length} ejes` :
    "Sin mando: se vuela con el teclado. Conecta un mando (o una emisora RC por USB) y pulsa cualquier botón.";
  // una emisora no se presenta como mando "standard": si sigue con el orden de consola, lo avisa
  document.getElementById("mandoAviso").textContent = p && p.mapping !== "standard" && MANDO.perfil === "consola"
    ? "Este dispositivo no es un mando de consola (parece una emisora): elige el orden de canales de tu emisora o usa el asistente; con el orden de consola el gas y el alabeo salen cambiados." : "";
  const mon = document.getElementById("mandoMonitor");
  if (!mon.children.length) mon.innerHTML = PALANCAS.map(([k, nom]) =>
    `<span class="nom">${nom}</span><span class="barra" id="monB_${k}"><i></i></span><span class="eje" id="monE_${k}"></span>` +
    `<label><input type="checkbox" id="monI_${k}"> invertir</label>`).join("");
  for (const [k] of PALANCAS) {
    document.getElementById("monE_" + k).textContent = "eje " + MANDO.ejes[k].i;
    const inv = document.getElementById("monI_" + k), base = (PERFILES_MANDO[MANDO.perfil] || {})[k];
    inv.checked = base ? MANDO.ejes[k].s !== base[1] : MANDO.ejes[k].s < 0;
    inv.onchange = () => { MANDO.ejes[k].s *= -1; guardarMando(); };
  }
  if (!MON.raf) MON.raf = requestAnimationFrame(monitorMando);
}
/** Monitor en vivo de las cuatro palancas (y el asistente) mientras se ven los ajustes. La barra va a la derecha al
 *  subir el gas, al mover a la derecha y al empujar la profundidad. */
const MON = { raf: 0 };
function monitorMando() {
  if (pantallaActual !== "pAjustes") { MON.raf = 0; return; }
  MON.raf = requestAnimationFrame(monitorMando);
  const p = mandoConectado(), mon = document.getElementById("mandoMonitor");
  mon.classList.toggle("inactivo", !p);
  if (!p) return;
  for (const [k] of PALANCAS) {
    const v = ejeMando(p.axes, k), d = k === "ly" || k === "ry" ? -v : v, i = document.querySelector(`#monB_${k} i`);
    i.style.left = (50 + 50 * Math.min(0, d)) + "%"; i.style.width = (50 * Math.abs(d)) + "%";
  }
  if (ASIST.activo) pasoAsistente(p);
}
// ---- asistente: cada palanca se mueve y se deja en un extremo; el eje que mas ha recorrido y esta en ese extremo es
// el suyo, y el signo sale de hacia donde esta ----
const PASOS_ASIST = [
  ["ly", -1, "Mueve la palanca de <b>gas</b> (izquierda) arriba y abajo y déjala <b>arriba del todo</b>."],
  ["lx", 1, "Mueve la palanca <b>izquierda</b> a los lados y mantenla a la <b>derecha</b> del todo (timón)."],
  ["rx", 1, "Mueve la palanca <b>derecha</b> a los lados y mantenla a la <b>derecha</b> del todo (alabeo)."],
  ["ry", -1, "Mueve la palanca <b>derecha</b> arriba y abajo y mantenla <b>arriba</b>, empujada del todo (profundidad)."],
];
const ASIST = { activo: false };
function empezarAsistente() {
  const p = mandoConectado();
  if (!p) { document.getElementById("mandoAviso").textContent = "Conecta la emisora por USB y mueve una palanca para que el navegador la vea."; return; }
  Object.assign(ASIST, { activo: true, paso: 0, nuevos: {}, usados: new Set() });
  reiniciarPasoAsistente(p); document.getElementById("mandoAsist").classList.add("activo");
}
function reiniciarPasoAsistente(p) {
  ASIST.min = p.axes.slice(); ASIST.max = p.axes.slice(); ASIST.cand = -1; ASIST.t = 0;
  document.getElementById("mandoAsistTxt").innerHTML = `Paso ${ASIST.paso + 1} de 4. ` + PASOS_ASIST[ASIST.paso][2];
}
function pasoAsistente(p) {
  const ax = p.axes;
  for (let i = 0; i < ax.length; i++) { ASIST.min[i] = Math.min(ASIST.min[i], ax[i]); ASIST.max[i] = Math.max(ASIST.max[i], ax[i]); }
  let mejor = -1, rec = 0.9;
  for (let i = 0; i < ax.length; i++) if (!ASIST.usados.has(i) && ASIST.max[i] - ASIST.min[i] > rec && Math.abs(ax[i]) > 0.7) { mejor = i; rec = ASIST.max[i] - ASIST.min[i]; }
  const ahora = performance.now();
  if (mejor !== ASIST.cand) { ASIST.cand = mejor; ASIST.t = ahora; return; }
  if (mejor < 0 || ahora - ASIST.t < 500) return;                 // medio segundo quieta en el extremo
  const [k, objetivo] = PASOS_ASIST[ASIST.paso];
  ASIST.nuevos[k] = { i: mejor, s: Math.sign(ax[mejor]) === objetivo ? 1 : -1 }; ASIST.usados.add(mejor);
  if (++ASIST.paso < PASOS_ASIST.length) { reiniciarPasoAsistente(p); return; }
  MANDO.ejes = ASIST.nuevos; MANDO.perfil = "propio"; ASIST.activo = false; guardarMando();
  document.getElementById("mandoAsistTxt").innerHTML = "<b>Listo.</b> Comprueba en el monitor que cada barra va hacia la derecha al subir el gas, mover a la derecha y empujar la profundidad." +
    (MANDO.gas === "incremental" ? " Si es una emisora, elige arriba <b>Gas: palanca sin muelle</b>." : "");
  document.getElementById("btnMandoAsistNo").textContent = "Cerrar";
  pintarMandoCfg();
}
document.getElementById("btnMandoAsist").onclick = () => { document.getElementById("btnMandoAsistNo").textContent = "Cancelar"; empezarAsistente(); };
document.getElementById("btnMandoAsistNo").onclick = () => { ASIST.activo = false; document.getElementById("mandoAsist").classList.remove("activo"); };
document.getElementById("mandoPerfil").addEventListener("change", e => {
  MANDO.perfil = e.target.value;
  if (PERFILES_MANDO[MANDO.perfil]) MANDO.ejes = ejesDe(MANDO.perfil);
  else if (!ASIST.nuevos) empezarAsistente();                     // "asignado con el asistente" sin haberlo pasado: lo abre
  if (MANDO.perfil === "aetr" || MANDO.perfil === "taer") MANDO.gas = "absoluto";      // la palanca de gas de una emisora no tiene muelle
  if (MANDO.perfil === "consola") MANDO.gas = "incremental";                          // la de un mando de consola, si
  if (PERFILES_MANDO[MANDO.perfil]) MANDO.expo = MANDO.perfil === "consola" ? EXPO_DEFECTO.consola : EXPO_DEFECTO.emisora;
  guardarMando(); pintarMandoCfg();
});
document.getElementById("mandoGas").addEventListener("change", e => { MANDO.gas = e.target.value; guardarMando(); });
document.getElementById("mandoExpo").addEventListener("input", e => { MANDO.expo = +e.target.value / 100; guardarMando(); pintarMandoCfg(); });
window.addEventListener("gamepadconnected", () => pintarMandoCfg());
window.addEventListener("gamepaddisconnected", () => pintarMandoCfg());
function mandoConectado() {
  const gp = navigator.getGamepads ? navigator.getGamepads() : [];
  for (const p of gp) if (p && p.connected && p.axes.length >= 4) return p;
  return null;
}
const zonaMuerta = (x, z) => Math.abs(x) < z ? 0 : Math.sign(x) * (Math.abs(x) - z) / (1 - z);
const expo = (x, e) => (1 - e) * x + e * x * x * x;
/** Lee el mando en cada cuadro. Devuelve true si el mando manda (alguna palanca fuera de la zona muerta o gas absoluto). */
function leerMando(dt) {
  const p = mandoConectado();
  MANDO.activo = !!p; MANDO.gimbal = 0; if (!p) return false;
  MANDO.id = p.id;
  const ax = p.axes, E = k => ejeMando(ax, k);                     // ejes segun el orden configurado (consola o emisora)
  let rx = zonaMuerta(E("rx"), MANDO.zona), ry = zonaMuerta(E("ry"), MANDO.zona), ly = zonaMuerta(E("ly"), MANDO.zona), lx = zonaMuerta(E("lx"), MANDO.zona);
  MANDO.torreta = null;
  if (modelo && modelo.uav && torretaConFlechas()) { MANDO.torreta = [rx, ry]; rx = 0; ry = 0; }      // UAV con el automatico navegando: la palanca derecha mueve la torreta
  const cuad = modelo && ((modelo.esCuadricoptero && !modelo.esFPV) || modelo.esTerrestre), fpv = modelo && modelo.esFPV;   // el FPV lleva el gas como un avion; el bipode, la izquierda como el dron
  const bip = modelo && modelo.esBipode;
  MANDO.disparo = false; MANDO.puno = false;
  // botones: flanco de subida
  const b = i => !!(p.buttons[i] && p.buttons[i].pressed), antes = MANDO.botones;
  const pulsado = i => b(i) && !antes[i];
  if (pantallaActual === null && pulsado(9)) ponerPausa(!pausado);
  if (pantallaActual === null && !pausado && bip) {      // bipode: A arrancar / aparcar, RB camara, Back reiniciar; gatillos: disparar (RT) y puño (LT)
    if (pulsado(0)) lanzar();
    if (pulsado(5)) visor.camara = visor.camara % 3 + 1;
    if (pulsado(8)) reiniciar();
    const tr = i => p.buttons[i] ? (p.buttons[i].value || (p.buttons[i].pressed ? 1 : 0)) : 0;
    MANDO.disparo = tr(7) > 0.4; MANDO.puno = tr(6) > 0.4;
  } else if (pantallaActual === null && !pausado && fpv) {      // dron FPV: A armar/desarmar, LB modo, RB camara, Back reiniciar
    if (pulsado(0)) fpvArmar();
    if (pulsado(4)) fpvModo();
    if (pulsado(5)) visor.camara = visor.camara % 3 + 1;
    if (pulsado(8)) reiniciar();
  } else if (pantallaActual === null && !pausado && cuad) {     // mando del dron comercial: A despegar/aterrizar, B volver a casa, X video, Y foto, LB modo, RB camara, Back reiniciar
    if (pulsado(0)) djiDespegar();
    if (pulsado(1)) djiRTH();
    if (pulsado(2)) djiVideo();
    if (pulsado(3)) djiFoto();
    if (pulsado(4)) djiModo();
    if (pulsado(5)) visor.camara = visor.camara % 3 + 1;
    if (pulsado(8)) reiniciar();
    if (pulsado(12)) djiZoom(1);                            // cruceta: arriba y abajo el zoom, a la derecha la termica
    if (pulsado(13)) djiZoom(-1);
    if (pulsado(15)) djiTermica();
    const tr = i => p.buttons[i] ? (p.buttons[i].value || (p.buttons[i].pressed ? 1 : 0)) : 0;
    MANDO.gimbal = tr(7) - tr(6);                           // gatillos: rueda del gimbal (RT sube, LT baja)
    // CSC (combinacion de palancas de los drones comerciales): las dos abajo y hacia dentro (o hacia fuera) medio segundo arranca los motores
    const csc = ly > 0.8 && ry > 0.8 && ((lx > 0.6 && rx < -0.6) || (lx < -0.6 && rx > 0.6));
    MANDO.tCsc = csc ? (MANDO.tCsc || 0) + dt : 0;
    if (MANDO.tCsc > 0.5 && av.estado === "en mano") { MANDO.tCsc = -1e9; lanzar(); toast("Motores en marcha (CSC): sube la palanca izquierda para despegar"); }
  } else if (pantallaActual === null && !pausado) {
    if (pulsado(0)) lanzar();
    if (modelo.tren) { MANDO.freno = !!(p.buttons[1] && p.buttons[1].pressed); if (pulsado(1)) quitarFrenoAparc(); }   // avion de pista: B frena
    if (modelo.uav) {          // LB modo, Y base, cruceta izquierda: P; cruceta arriba y abajo zoom, derecha termica; X foto; gatillos: torreta arriba y abajo
      if (pulsado(4)) uavModo(); if (pulsado(3)) uavPoner("BASE"); if (pulsado(14)) uavPoner(av.enTierra ? "DESPEGUE" : "ATERRIZAJE");
      if (pulsado(12)) djiZoom(1); if (pulsado(13)) djiZoom(-1); if (pulsado(15)) djiTermica(); if (pulsado(2)) uavFoto();
      const tr = i => p.buttons[i] ? (p.buttons[i].value || (p.buttons[i].pressed ? 1 : 0)) : 0; MANDO.gimbal = tr(7) - tr(6);
    }
    else if (pulsado(1)) av.gases = 0;
    if (pulsado(5)) visor.camara = visor.camara % 3 + 1;        // RB: el mismo boton que en el dron, el FPV y el bipode
    if (pulsado(2) && !modelo.uav) reiniciar();
    if (pulsado(12) && !modelo.uav) mando.trim = Math.min(6, mando.trim + 0.25);
    if (pulsado(13) && !modelo.uav) mando.trim = Math.max(-6, mando.trim - 0.25);
  }
  MANDO.botones = p.buttons.map(x => x.pressed);
  if (pausado) return false;
  // palanca derecha: hacia ti (eje Y positivo, abajo) = tirar = morro arriba; a la derecha = alabeo/timon a la derecha
  const moviendo = rx !== 0 || ry !== 0 || lx !== 0 || (cuad && ly !== 0);   // la izquierda de lado: guinada del dron o timon (4 canales)
  if (moviendo || MANDO.usado) {
    mando.pitch = expo(ry, MANDO.expo); mando.yaw = expo(rx, MANDO.expo);
    mando.pitchObj = mando.pitch; mando.yawObj = mando.yaw;
    mando.guinada = expo(lx, MANDO.expo); mando.guinadaObj = mando.guinada;     // izquierda de lado: guinada del dron o timon de un avion de 4 canales
    if (cuad) { mando.vz = -ly; mando.vzObj = mando.vz; }   // dron comercial modo 2: izquierda gas (con muelle) y guinada
  }
  if (moviendo) MANDO.usado = true;
  // palanca izquierda: gas (eje Y negativo = arriba)
  if (!av.motorRoto && fpv && MANDO.perfil === "consola") {        // FPV con mando de consola (palanca con muelle): ver gasFpvConsola
    if (ly !== 0) MANDO.gasFpv = true;                              // desde que se toca la palanca del gas en este vuelo
    if (MANDO.gasFpv) av.gases = gasFpvConsola(-ly);
  } else if (!av.motorRoto && !cuad) {
    if (MANDO.gas === "absoluto") { if (MANDO.usado || ly !== 0) av.gases = Math.max(0, Math.min(1, (1 - E("ly")) / 2)); }
    else if (ly !== 0) av.gases = Math.max(0, Math.min(1, av.gases - ly * 0.7 * dt));
  }
  return moviendo || MANDO.usado;
}
