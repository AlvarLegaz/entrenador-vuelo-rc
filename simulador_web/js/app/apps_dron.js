// La app del dron comercial (modos, foto, video, despegue, RTH) y el dron FPV (armar, modos de Betaflight y OSD).
// Parte de la aplicacion de simulador_web/simulador.html: los modulos de js/app/ se cargan en orden y comparten el
// ambito global. En Godot: simulador_godot/scripts/app/apps_dron.gd.
"use strict";
// =====================================================================
//  APP dron comercial FLY (cuadricoptero): modo de vuelo C/N/S, foto y video, despegue automatico, aterrizar y volver a casa.
//  La pantalla #dji imita lo que ve el piloto en el movil con el mando: solo eso, sin los instrumentos del avion.
// =====================================================================
const DJI = { grabando: false, tRec: 0, fotos: 0, video: false, tAnt: 0, zoomI: 0, termica: false };
/** La camara del dron de inspeccion (datos.camara: niveles de zoom y termica): el zoom actual y si esta la termica. */
function camDJI() { const C = modelo && modelo.camara; return { zoom: C ? C.zoom[DJI.zoomI] || 1 : 1, termica: !!(C && C.termica && DJI.termica) }; }
function djiZoom(paso) {
  const C = modelo && modelo.camara; if (!C || Repeticion.activa) return;
  DJI.zoomI = Math.max(0, Math.min(C.zoom.length - 1, DJI.zoomI + paso)); const z = C.zoom[DJI.zoomI];
  toast(`Zoom ${z}x` + (z === 1 ? " · gran angular" : z <= C.zoom_optico ? " · teleobjetivo" : " · digital"));
}
function djiTermica() { const C = modelo && modelo.camara; if (!C || !C.termica || Repeticion.activa) return; DJI.termica = !DJI.termica; toast(DJI.termica ? "Cámara térmica" : "Cámara normal"); }
const NOMBRES_MODO = { C: "Cine", N: "Normal", S: "Sport" };
function djiModo(m) {
  if (!modelo || !modelo.esCuadricoptero) return;
  modelo.modo = m || { N: "S", S: "C", C: "N" }[modelo.modo] || "N";
  toast(`Modo ${NOMBRES_MODO[modelo.modo]}` + (modelo.modo === "S" ? " · sin frenado suave" : ""));
}
function djiFoto() {
  if (!modelo || !modelo.esCuadricoptero) return;
  DJI.fotos++; const f = document.getElementById("djiFlash"); f.classList.add("on"); setTimeout(() => f.classList.remove("on"), 80);
  const T = ev && ev.op ? ev.op.foto(av, av.gimbal, camDJI()) : [];        // operaciones: lo que vale esa foto para el trabajo
  toast(T.length ? T.join(" · ") : `Foto ${DJI.fotos}`);
}
function djiVideo() {
  if (!modelo || !modelo.esCuadricoptero) return;
  DJI.video = true; DJI.grabando = !DJI.grabando; if (DJI.grabando) { DJI.tRec = 0; DJI.tAnt = av.t; }
  toast(DJI.grabando ? "Grabando" : "Vídeo guardado");
}
function djiDisparo() { DJI.video ? djiVideo() : djiFoto(); }
function djiCamModo() { DJI.video = !DJI.video; if (!DJI.video) DJI.grabando = false; }
/** Boton de despegue de la app: en el suelo arma y sube a 1,2 m; en vuelo, aterriza en el sitio. */
function djiDespegar() {
  if (!modelo || !modelo.esCuadricoptero || Repeticion.activa) return;
  if (av.estado === "en mano") { lanzar(); modelo.despegar(av); aviso(""); }
  else if (av.estado === "volando" && av.posado) modelo.despegar(av);
  else if (av.estado === "volando") { av.rth = { fase: "bajar" }; toast("Aterrizando"); }
}
function djiRTH() {
  if (!modelo || !modelo.esCuadricoptero || Repeticion.activa || av.estado !== "volando" || av.posado) return;
  if (av.batForzado) { toast("Aterrizaje forzoso por batería crítica: no se puede cancelar"); return; }
  if (av.rth && av.rth.fase !== "bajar") { av.rth = null; toast("Volver a casa cancelado"); return; }
  modelo.volverACasa(av); toast("Volviendo a casa");
}
document.getElementById("djiModo").onclick = () => djiModo();
document.getElementById("djiDisparo").onclick = djiDisparo;
document.getElementById("djiCamModo").onclick = djiCamModo;
document.getElementById("djiZoomMas").onclick = () => djiZoom(1);
document.getElementById("djiZoomMenos").onclick = () => djiZoom(-1);
document.getElementById("djiIR").onclick = djiTermica;
for (const b of document.querySelectorAll("#gcsDer button[data-modo]")) b.onclick = () => b.dataset.modo === "AUTO" ? uavPoner(av.enTierra ? "DESPEGUE" : "ATERRIZAJE") : uavPoner(b.dataset.modo);
document.getElementById("gcsZoomMas").onclick = () => djiZoom(1); document.getElementById("gcsZoomMenos").onclick = () => djiZoom(-1);
document.getElementById("gcsIR").onclick = djiTermica; document.getElementById("gcsFijar").onclick = () => uavFijar(); document.getElementById("gcsFoto").onclick = () => uavFoto();
document.getElementById("djiDespegar").onclick = djiDespegar;
document.getElementById("djiRTH").onclick = djiRTH;
/** Briefing de los trabajos: la misma imagen de la orden de trabajo (la zona y el despegue, sin las soluciones), encima del vuelo. */
function verBriefing(ver) {
  const op = !!ESCENARIOS[sesion.escenario].operacion, b = document.getElementById("briefing");
  verBriefing.abierto = op && (ver === undefined ? !verBriefing.abierto : ver);
  if (verBriefing.abierto) b.querySelector("img").src = `../datos/operaciones/${sesion.escenario}.jpg`;
  b.style.display = verBriefing.abierto ? "block" : "none";
  document.getElementById("djiBriefing").classList.toggle("activo", verBriefing.abierto);
}
document.getElementById("djiBriefing").onclick = () => verBriefing();
document.getElementById("briefing").onclick = () => verBriefing(false);
const fmtTiempo = s => `${Math.floor(s / 60)}:${String(Math.floor(s % 60)).padStart(2, "0")}`;
/** Pantalla de la app: barra de arriba (modo, estado, GPS, señal, batería), mapa, D/H/HS/VS, gimbal y botones. */
function hudDji(h, vn, vs, dist) {
  const $ = $h, M = modelo.modo || "N", me = $("djiModo");
  ponerTxt(me, M); ponerClase(me, "modo " + M);
  let est, cl = "";
  if (Repeticion.activa) est = "REPETICIÓN";
  else if (av.estado === "en mano") { est = "Motores parados · pulsa despegar o L"; cl = "aviso"; }
  else if (av.estado === "volando") {
    if (av.rth) { est = av.rth.fase === "bajar" ? "Aterrizando…" : av.rth.fase === "subir" ? "Volviendo a casa: subiendo…" : "Volviendo a casa…"; cl = "aviso"; }
    else if (av.despegueAuto) { est = "Despegando…"; cl = "aviso"; }
    else if (av.posado) est = av.despegado ? "Aterrizado · motores al ralentí" : "Listo para despegar";
    else est = M === "S" ? "En vuelo · modo Sport" : "En vuelo (GPS)";
  } else { est = av.estado.toUpperCase(); cl = av.estado === "aterrizado" ? "" : "rojo"; }
  if (pausado) est += " · PAUSA";
  ponerTxt($("djiEstado"), est); ponerClase($("djiEstado"), "estado " + cl);
  // grabacion y bateria (tiempo restante con el consumo medio del vuelo)
  if (DJI.grabando && !pausado) DJI.tRec += Math.max(0, av.t - DJI.tAnt);
  DJI.tAnt = av.t;
  ponerTxt($("djiRec"), DJI.grabando ? `● REC ${fmtTiempo(DJI.tRec)}` : "");
  const bat = modelo.bateriaPct(av), restWh = modelo.propulsion.masa_bateria_Wh * bat / 100, P = av.t > 5 && av.Wh > 0 ? av.Wh / av.t * 3600 : 35;
  const be = $("djiBat"); ponerClase(be, "bat" + (bat < 20 ? " rojo" : "")); const bi = be._i || (be._i = be.querySelector("i")), bw = (22 * bat / 100).toFixed(1) + "px";
  if (bi._w !== bw) { bi._w = bw; bi.style.setProperty("--w", bw); }
  ponerTxt(be.lastChild, `${bat.toFixed(0)} % · ${fmtTiempo(Math.min(5999, restWh / P * 3600))}`);
  // telemetria como la app: distancia y altura respecto al punto de despegue, velocidad horizontal y vertical
  const c = casa(), hCasa = entorno.altura ? entorno.altura(c.N, c.E) : 0, f1 = x => (Math.abs(x) < 0.05 ? 0 : x).toFixed(1).replace(".", ",");
  ponerTxt($("djiD"), dist >= 1000 ? f1(dist / 1000) + " km" : dist.toFixed(0) + " m");
  ponerTxt($("djiH"), Math.max(0, -av.p[2] - hCasa).toFixed(0) + " m");      // sobre el punto de despegue (h viene recortado a 0)
  ponerTxt($("djiHS"), f1(Math.hypot(vn[0], vn[1])) + " m/s"); ponerTxt($("djiVS"), f1(vs) + " m/s");
  // gimbal (+10 arriba, -90 abajo), botones
  const g = av.gimbal === undefined ? -10 : av.gimbal;
  const gt = ((10 - g) / 100 * 130).toFixed(0) + "px"; ponerEstilo($("djiGimbalMarca"), "top", gt); ponerEstilo($("djiGimbalTxt"), "top", gt);
  ponerTxt($("djiGimbalTxt"), (g < 0 ? "−" : "") + Math.abs(Math.round(g)) + "°");
  ponerTxt($("djiDespegar"), av.estado === "volando" && !av.posado ? "⇩" : "⇧");
  ponerAttr($("djiDespegar"), "title", av.estado === "volando" && !av.posado ? "Aterrizar aquí (botón A del mando)" : "Despegar: arma y sube a 1,2 m (botón A del mando)");
  $("djiRTH").classList.toggle("activo", !!(av.rth && av.rth.fase !== "bajar"));
  const d = $("djiDisparo"); d.classList.toggle("video", DJI.video); d.classList.toggle("rec", DJI.grabando);
  ponerTxt($("djiCamTxt"), DJI.video ? "VÍDEO" : "FOTO");
  // camara de inspeccion: zoom, termica, el medidor puntual del centro y la escala de temperaturas
  const Cm = modelo.camara, cm = camDJI(), verMed = cm.termica && visor.camara === 3;
  ponerEstilo($("djiZoomCaja"), "display", Cm ? "" : "none");
  if (Cm) { ponerTxt($("djiZoomTxt"), cm.zoom + "x"); ponerClase($("djiIR"), cm.termica ? "activo" : ""); ponerEstilo($("djiIR"), "display", Cm.termica ? "" : "none"); }
  ponerEstilo($("djiMedidor"), "display", verMed ? "block" : "none"); ponerEstilo($("djiPaleta"), "display", verMed ? "block" : "none");
  if (verMed) { const L = ev && ev.op ? ev.op.lectura : null, Tm = L ? L.T : OPS.AMBIENTE; ponerTxt($("djiTemp"), Tm > 150 ? ">150 °C" : Tm.toFixed(1).replace(".", ",") + " °C"); }
  visor.zoomCam = cm.zoom; visor.termica = cm.termica;
  const mapa = $("djiMapa"), gps = $("gps"); if (gps.parentNode !== mapa) mapa.appendChild(gps);
}
// =====================================================================
//  DRON FPV: armar / desarmar, modos de Betaflight y el OSD (#fpv: lo que se ve en las gafas, como el OSD de Betaflight)
// =====================================================================
const NOMBRES_FPV = { ANGLE: "ANGL", HORIZON: "HOR", ACRO: "ACRO" };
/** Armar (solo con el gas abajo, como un FPV de verdad) o desarmar (en el aire se cae; en el suelo tras volar, aterrizado). */
/** Gas del FPV con un mando de consola: su palanca izquierda tiene muelle y vuelve al centro, asi que el centro es el
 *  gas del estacionario (como thr_mid de Betaflight): suelta, se mantiene la altura; arriba del todo, todo el gas; abajo
 *  del todo, nada. Con una curva suave cerca del centro (un toque arriba sube unos pocos m/s, no sale disparado). En el
 *  suelo, con la palanca en reposo, gas cero: se arma sin despegar y para despegar hay que empujar. s: palanca (+1 arriba).
 *  La misma que gas_fpv_consola() de principal.gd. */
const FPV_GAS_ESTACIONARIO = 0.30;               // medido: el FPV de 650 g se sostiene con el 30,4 % (bateria llena)
function gasFpvConsola(s) {
  const f = x => 0.25 * x + 0.75 * x * x * x, h = FPV_GAS_ESTACIONARIO;
  if ((av.posado || av.estado === "en mano") && s <= 0.05) return 0;
  return s >= 0 ? h + (1 - h) * f(s) : h * (1 - f(-s));
}
function fpvArmar() {
  if (!modelo || !modelo.esFPV || Repeticion.activa) return;
  if (av.estado === "en mano") {
    if (av.gases > 0.05) { toast("Para armar, baja el gas del todo (S o palanca izquierda abajo)"); return; }
    lanzar();
  } else if (av.estado === "volando" && av.armado) {
    modelo.desarmar(av); toast("DESARMADO");
    if (av.estado === "en mano") aviso("Gas abajo del todo y L (o botón A) para armar");
  }
}
/** Modo de vuelo de Betaflight: ANGLE -> HORIZON -> ACRO -> ANGLE (tecla M, LB del mando o el que se pida). */
function fpvModo(m) {
  if (!modelo || !modelo.esFPV) return;
  modelo.modo = m || { ANGLE: "HORIZON", HORIZON: "ACRO", ACRO: "ANGLE" }[modelo.modo] || "ANGLE";
  toast(`Modo ${modelo.modo}` + (modelo.modo === "ACRO" ? " · sin autonivelado" : modelo.modo === "ANGLE" ? " · se nivela solo" : ""));
}
/** OSD de Betaflight: modo, tiempo armado, gas, altura, velocidad, bateria (total y por celda), corriente y mAh, ARMED /
 *  DISARMED y avisos (bateria baja, aterriza ya, desarma para terminar). Las cifras como las de Betaflight (punto decimal). */
function hudFpv(h, vn) {
  const $ = $h, F = modelo.fc, celda = av.Vbat / modelo.propulsion.celdas;
  const c = casa(), hCasa = entorno.altura ? entorno.altura(c.N, c.E) : 0, V = Math.sqrt(vn[0] * vn[0] + vn[1] * vn[1] + vn[2] * vn[2]);
  ponerEstilo($("fpvMira"), "display", visor.camara === 3 ? "" : "none");          // la mira, solo en las gafas
  ponerTxt($("fpvModo"), NOMBRES_FPV[modelo.modo] || modelo.modo);
  ponerTxt($("fpvTiempo"), "TIME " + fmtTiempo(av.tArmado || 0));
  ponerTxt($("fpvGas"), "THR " + Math.round(av.gases * 100));
  ponerTxt($("fpvAlt"), `ALT ${(-av.p[2] - hCasa).toFixed(1)}m`);      // sobre el punto de despegue, como Betaflight (h viene recortado a 0)
  ponerTxt($("fpvVel"), `${Math.round(V * 3.6)}km/h`);
  const be = $("fpvBat"); ponerTxt(be, `${av.Vbat.toFixed(1)}V ${celda.toFixed(2)}V`);
  ponerClase(be, "osd" + (celda < F.critico_celda_V ? " rojo" : celda < F.aviso_celda_V ? " ambar" : ""));
  ponerTxt($("fpvAmp"), `${av.I.toFixed(1)}A ${Math.round(av.mAh)}mAh`);
  const armado = av.estado === "volando" && av.armado, parpadeo = (performance.now() / 1000) % 1 < 0.6;
  const ae = $("fpvArm");
  ponerTxt(ae, Repeticion.activa ? "REPETICIÓN" : armado ? (av.tArmado < 1.5 ? "ARMED" : "") : av.estado === "volando" || av.estado === "en mano" ? "DISARMED" : av.estado.toUpperCase());
  ponerClase(ae, "osd c" + (armado ? "" : " rojo"));
  let avs = "", cl = "rojo";
  if (armado) {
    if (celda < F.critico_celda_V) avs = parpadeo ? "¡ATERRIZA YA!" : "";
    else if (celda < F.aviso_celda_V) { avs = parpadeo ? "BATERÍA BAJA" : ""; cl = "ambar"; }
    else if (av.posado && av.despegado) { avs = "DESARMA (L) PARA TERMINAR"; cl = ""; }
  }
  if (pausado) { avs = "PAUSA"; cl = ""; }
  const ve = $("fpvAviso"); ponerTxt(ve, avs); ponerClase(ve, "osd c grande" + (cl ? " " + cl : ""));
}
