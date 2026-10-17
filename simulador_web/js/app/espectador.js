// Espectador (la vista del alumno del panel del profesor) y el bucle de la aplicacion.
// Parte de la aplicacion de simulador_web/simulador.html: los modulos de js/app/ se cargan en orden y comparten el
// ambito global. En Godot: no tiene: el espectador solo esta en la web.
"use strict";
// =====================================================================
//  ESPECTADOR (vista del alumno del panel del profesor): espectador.html es este mismo simulador servido por el aula; sigue
//  a un piloto de una sala con lo que manda su simulador 10 veces por segundo (posicion, orientacion, camara, zoom,
//  termica, torreta, objetivos y la linea "Ahora") y lo dibuja desde su camara, con los demas pilotos. No simula ni manda
//  nada. Necesita el pase del profesor (el que guarda el panel en sessionStorage). Lo que cada simulador sortea en un
//  trabajo (manchas, defectos...) no se sabe: de los trabajos solo se dibuja la carrera, que es fija.
// =====================================================================
const ESPECTADOR = /espectador\.html$/.test(location.pathname) ? new URLSearchParams(location.search) : null;
const ESP = { cod: null, piloto: null, est: null, otros: [], avion: null, pidiendo: false, error: "" };
async function apiProf(metodo, ruta) {
  let tk = ""; try { tk = sessionStorage.getItem("prof_token") || ""; } catch (e) {}
  const r = await fetch("/api/" + ruta, { method: metodo, headers: { Authorization: "Bearer " + tk } });
  const d = await r.json().catch(() => ({}));
  if (!r.ok) throw new Error(d.error || r.statusText);
  return d;
}
/** Los estados de la sala: el del piloto que se sigue y los demas (con su hora de llegada, para los fantasmas). */
function espRecibir(lista) {
  const t = performance.now(), L = (lista || []).filter(o => o && typeof o.id === "string" && numsFinitos(o.p, 3) && numsFinitos(o.q, 4));
  const e = L.find(o => o.id === ESP.piloto);
  if (e) { ESP.est = Object.assign(e, { recibido: t }); ESP.error = ""; } else ESP.error = "Ese piloto ya no está en la sala";
  ESP.otros = L.filter(o => o.id !== ESP.piloto && Modelos.datos(o.avion)).map(o => Object.assign(o, { recibido: t }));
}
async function espPedir() {
  if (ESP.pidiendo) return; ESP.pidiendo = true;
  try { const s = await apiProf("GET", "salas/" + encodeURIComponent(ESP.cod)); espRecibir(s.jugadores); }
  catch (e) { ESP.error = /no existe/.test(e.message) ? "La sala se ha cerrado" : "Sin conexión con el aula: " + e.message; }
  finally { ESP.pidiendo = false; }
}
function espMensaje(t) { document.body.classList.add("espectador"); ESP.error = t; espBarra(); }
async function iniciarEspectador() {
  document.body.classList.add("espectador");
  window.addEventListener("keydown", e => e.stopImmediatePropagation(), true);            // el profesor solo mira
  ESP.cod = ESPECTADOR.get("sala") || ""; ESP.piloto = ESPECTADOR.get("piloto") || "";
  let s;
  try { s = await apiProf("GET", "salas/" + encodeURIComponent(ESP.cod)); }
  catch (e) { espMensaje("No se puede ver la sala: " + e.message); return; }
  if (!Array.isArray(s.jugadores) || !s.jugadores.some(j => j && j.id && Array.isArray(j.p))) { espMensaje("Solo el profesor puede ver lo que ve cada alumno"); return; }
  espRecibir(s.jugadores);
  if (!ESP.est) { espMensaje("Ese piloto ya no está en la sala"); return; }
  const E = ESCENARIOS[s.escenario] ? ESCENARIOS[s.escenario] : ESCENARIOS.libre;
  sesion.escenario = ESCENARIOS[s.escenario] ? s.escenario : "libre";
  if (s.lanz && numsFinitos([s.lanz.N, s.lanz.E, s.lanz.rumbo], 3)) sesion.lanz = s.lanz;
  else if (E.operacion) sesion.lanz = { mundo: E.mundo, N: E.operacion.salida.n, E: E.operacion.salida.e, rumbo: E.operacion.salida.rumbo };
  if (Modelos.datos(ESP.est.avion)) sesion.avion = ESP.est.avion;
  ESP.avion = sesion.avion;
  await empezar();
  if (ev && ev.op && !ev.op.d.carrera && visor.ponerOperacion) visor.ponerOperacion(null, null);
  av.p = ESP.est.p.slice(); av.q = ESP.est.q.slice();
  setInterval(espPedir, 100);
}
/** Cada cuadro: el dron (o avion) del piloto donde dice su ultimo estado (adelantado con su velocidad y suavizado), su
 *  camara, zoom, termica y torreta, y los demas pilotos. */
function pasoEspectador(dt) {
  const e = ESP.est;
  if (!e || !av) { espBarra(); return; }
  if (e.avion !== ESP.avion && Modelos.datos(e.avion)) { location.reload(); return; }      // ha cambiado de vehiculo
  const tr = Math.min(0.3, (performance.now() - e.recibido) / 1000), obj = [0, 1, 2].map(i => e.p[i] + (e.vn ? e.vn[i] : 0) * tr);
  const k = 1 - Math.exp(-dt * 10), lejos = Math.hypot(obj[0] - av.p[0], obj[1] - av.p[1], obj[2] - av.p[2]) > 50;
  for (let i = 0; i < 3; i++) av.p[i] = lejos ? obj[i] : av.p[i] + (obj[i] - av.p[i]) * k;
  let q = e.q; if (q[0] * av.q[0] + q[1] * av.q[1] + q[2] * av.q[2] + q[3] * av.q[3] < 0) q = q.map(x => -x);
  const qq = lejos ? q.slice() : av.q.map((x, i) => x + (q[i] - x) * k), nq = Math.hypot(...qq) || 1; av.q = qq.map(x => x / nq);
  if (typeof e.gimbal === "number") av.gimbal = e.gimbal;
  if (Array.isArray(e.tor) && av.torreta) { av.torreta.pan = e.tor[0]; av.torreta.tilt = e.tor[1]; }
  av.gases = e.gas || 0; av.estado = e.estado === "roto" ? "roto" : "volando"; av.t += dt;
  if (modelo.esBipode && Array.isArray(e.bip)) [av.cintura, av.brazos, av.fase, av.amp, av.angCanones, av.disparos, av.puno] = e.bip;
  if ([1, 2, 3].includes(e.cam)) visor.camara = e.cam;
  const C = modelo.camara, cam3 = visor.camara === 3;
  if (C && Array.isArray(C.zoom)) { const z = e.zoom || 1; DJI.zoomI = C.zoom.reduce((m, x, i) => Math.abs(x - z) < Math.abs(C.zoom[m] - z) ? i : m, 0); DJI.termica = !!e.ter && !!C.termica; }
  visor.zoomCam = cam3 && C ? (e.zoom || 1) : 1; visor.termica = cam3 && !!e.ter && !!(C && C.termica);
  try { visor.ponerFantasmas(ESP.otros); } catch (er) {}
  espBarra();
}
/** La barra de arriba: a quien se ve, con que, desde que camara, como va y lo que esta haciendo. */
function espBarra() {
  const el = document.getElementById("espBar"), e = ESP.est;
  el.classList.toggle("perdido", !!ESP.error);
  if (!e) { ponerHTML(el, `👁 ${esc(ESP.error || "Conectando…")}`); return; }
  const C = ["", "piloto / a bordo", "persecución", "cámara del dron"][e.cam] || "", ob = Array.isArray(e.objs) && e.objs[1] ? ` · objetivos <b>${e.objs[0]}/${e.objs[1]}</b>${e.objs[2] ? ` (${e.objs[2]} ✘)` : ""}` : "";
  ponerHTML(el, `👁 <b>${esc(e.nombre)}</b> · ${esc((Modelos.datos(e.avion) || { nombre: e.avion }).nombre)} · ${esc(C)}${e.zoom > 1 ? ` · ${e.zoom}x` : ""}${e.ter ? " · térmica" : ""} · ${esc(e.estado || "")}${ob}` +
    (e.ahora ? `<br><span class="sub2">${esc(e.ahora)}</span>` : "") + (ESP.error ? `<br><b>${esc(ESP.error)}</b>` : ""));
}
let tAnterior = performance.now(), acumulado = 0, tObj = 0;
function bucle(ahora) {
  const dtReal = Math.min(0.1, (ahora - tAnterior) / 1000); tAnterior = ahora;
  if (ESPECTADOR) { if (pantallaActual === null && av) { pasoEspectador(dtReal); visor.dibujar(av); } requestAnimationFrame(bucle); return; }
  if (pantallaActual === null) {
    if (Repeticion.activa) { pasoRepeticion(dtReal); visor.dibujar(av); hud(); }
    else if (pausado) { leerMando(dtReal); visor.dibujar(av); hud(); }        // en pausa se sigue dibujando (la camara puede cambiar)
    else {
      leerTeclado(dtReal);
      acumulado += dtReal;
      while (acumulado >= DT) { paso(DT); acumulado -= DT; }
      pasoJuegoBip(dtReal);
      visor.dibujar(av); hud(); Sonido.actualizar(av);
      if (MULTI.sala) { try { visor.ponerFantasmas([...MULTI.otros.values()]); } catch (e) { console.error("fantasmas:", e); } }   // un fallo con los demas nunca para el vuelo propio
      if ((tObj += dtReal) > 0.2) { tObj = 0; pintarObjetivos(); pintarSalaInfo(); }
    }
  } else {
    acumulado = 0;
    if (pantallaActual === "pInicio" || pantallaActual === "pHangar") previa.pintar(ahora);
  }
  requestAnimationFrame(bucle);
}
