// Multijugador: salas del aula, fantasmas, el bipode en sala y las ordenes del profesor.
// Parte de la aplicacion de simulador_web/simulador.html: los modulos de js/app/ se cargan en orden y comparten el
// ambito global. En Godot: simulador_godot/scripts/app/multijugador.gd.
"use strict";
// =====================================================================
//  MULTIJUGADOR: salas del servidor del aula (aula/servidor_aula.py, /api/salas; el mismo protocolo que la version de
//  Godot, asi que se puede volar mezclado). Cada simulador manda su estado 10 veces por segundo y recibe el de los demas
//  de su sala, que se dibujan como "fantasmas" (Visor.ponerFantasmas): sin choques entre ellos, cada uno con su fisica.
// =====================================================================
const MULTI = { sala: null, otros: new Map(), enCurso: false, timer: null, tSalas: null };
function multiId() {
  if (!MULTI.id) { try { MULTI.id = sessionStorage.getItem("sim_multi_id"); } catch (e) {}
    if (!MULTI.id) { MULTI.id = uuid4(); try { sessionStorage.setItem("sim_multi_id", MULTI.id); } catch (e) {} } }
  return MULTI.id;
}
const multiPosible = () => !!(sesion.aula && sesion.alumno);
const nombrePiloto = () => sesion.alumno ? sesion.alumno.nombre : "Invitado " + multiId().slice(0, 4);
/** Lo que se puede volar en una sala: vuelos libres, entrenamientos (de cada vehiculo) y operaciones. */
function irMulti() {
  const ok = multiPosible();
  document.getElementById("multiCrear").style.display = ok ? "" : "none"; document.getElementById("multiSinAula").style.display = ok ? "none" : "";
  mostrar("pMulti"); refrescarSalas();
  clearInterval(MULTI.tSalas); MULTI.tSalas = setInterval(() => { if (pantallaActual === "pMulti") refrescarSalas(); else clearInterval(MULTI.tSalas); }, 2000);
}
async function refrescarSalas() {
  const el = document.getElementById("listaSalas"), vacio = document.getElementById("multiVacio");
  if (!multiPosible()) { el.innerHTML = ""; vacio.textContent = ""; return; }
  let lista = []; try { lista = await api("GET", "salas"); } catch (e) { vacio.textContent = "No se puede hablar con el servidor del aula."; return; }
  vacio.textContent = lista.length ? "" : "No hay ninguna sala abierta: espera a que el profesor cree la de tu clase.";
  el.innerHTML = "";
  for (const s of lista) {
    const E = ESCENARIOS[s.escenario] || { nombre: s.escenario }, d = document.createElement("div"); d.className = "mision";
    d.innerHTML = `<div class="img">${iconoMision(s.escenario)}</div><div class="txt"><h3>${esc(s.nombre)} <span style="color:var(--suave);font-weight:400">· ${s.codigo}</span></h3>
      <p>${esc(E.nombre)}</p><div class="meta"><span>${s.jugadores.length ? s.jugadores.map(j => esc(j.nombre)).join(", ") : "nadie todavía"}</span></div></div>`;
    if (s.con_clave) d.querySelector("h3").insertAdjacentHTML("beforeend", ' <span title="Sala con clave">🔒</span>');
    d.onclick = () => pedirSala(s); el.appendChild(d);
  }
}
document.getElementById("btnMultiVolver").onclick = irInicio;
/** Pide entrar en una sala (con su clave, si la tiene; el servidor tambien mira si el profesor te ha expulsado). */
async function pedirSala(s) {
  let clave = "";
  if (s.con_clave) { const r = await pedirClave("Sala " + s.nombre, "Esta sala tiene clave: te la dice el profesor.", false); if (!r) return; clave = r[0]; }
  try { await api("POST", `salas/${s.codigo}/entrar`, { id: multiId(), clave, nombre: nombrePiloto(), alumno: sesion.alumno ? sesion.alumno.id : null }); entrarSala(s); }
  catch (e) { await confirmar("No puedes entrar", `<p>${esc(e.message)}</p>`, "Vale"); }
}
/** Entra en una sala: su escenario, su punto de salida y su viento, con un vehiculo que valga para el; y a volar. */
function entrarSala(s) {
  const E = ESCENARIOS[s.escenario]; if (!E) { toast("Esta sala es de algo que este simulador no tiene: actualízalo"); return; }
  MULTI.sala = s; MULTI.otros.clear(); ORDENES.reiniciar();
  const veh = (E.vehiculos || ["avion", "dron", "fpv"]).concat(E.objetivos.length || E.operacion ? [] : ["bipode"]);   // vuelo libre: tambien el bipode
  if (E.operacion && E.operacion.avion && Modelos.datos(E.operacion.avion)) elegirAvion(E.operacion.avion);       // trabajos: el dron que piden
  else if (!veh.includes(vehiculoDe(sesion.avion))) elegirAvion(Modelos.ids().find(a => veh.includes(vehiculoDe(a))) || sesion.avion);
  sesion.escenario = s.escenario;
  if (s.lanz && typeof s.lanz === "object" && numsFinitos([s.lanz.N, s.lanz.E, s.lanz.rumbo], 3)) sesion.lanz = s.lanz;         // solo si viene bien formado
  if (s.viento && typeof s.viento === "object" && numsFinitos([s.viento.vel, s.viento.desde], 2) && !E.viento) sesion.viento = s.viento;
  if (!s.lanz && E.operacion) sesion.lanz = { mundo: E.mundo, N: E.operacion.salida.n, E: E.operacion.salida.e, rumbo: E.operacion.salida.rumbo };   // trabajos: su despegue
  clearInterval(MULTI.timer); MULTI.timer = setInterval(enviarSala, 100);
  toast(`Sala ${s.codigo}: ${s.nombre}`); empezar();
}
function salirSala() {
  if (!MULTI.sala) return;
  const s = MULTI.sala; MULTI.sala = null; clearInterval(MULTI.timer); MULTI.otros.clear(); MULTI.golpesVistos = {}; MULTI.vida = undefined;
  if (visor && visor.ponerFantasmas) visor.ponerFantasmas([]);
  document.getElementById("salaInfo").style.display = "none";
  ORDENES.reiniciar(); pintarOrdenes(); if (visor && visor.ponerExclusiones) visor.ponerExclusiones([]);
  api("POST", `salas/${s.codigo}/salir`, { id: multiId() }).catch(() => {});
}
/** Un estado de otro jugador que se puede usar: posicion y orientacion con numeros finitos y un vehiculo que exista. */
const numsFinitos = (a, n) => Array.isArray(a) && a.length === n && a.every(x => typeof x === "number" && isFinite(x));
const numsFinitosMin = (a, n) => Array.isArray(a) && a.length >= n && a.slice(0, n).every(x => typeof x === "number" && isFinite(x));
function estadoValido(o) {
  if (!o || typeof o !== "object" || typeof o.id !== "string" || !numsFinitos(o.p, 3) || !numsFinitos(o.q, 4) || (o.vn != null && !numsFinitos(o.vn, 3))) return false;
  for (const k of ["estado", "nombre", "final", "ahora"]) if (o[k] != null && typeof o[k] !== "string") return false;
  for (const k of ["gas", "agl", "gimbal", "tvuelo"]) if (o[k] != null && !(typeof o[k] === "number" && isFinite(o[k]))) return false;
  if (o.objs != null && !numsFinitosMin(o.objs, 2)) return false;
  if (o.bip != null && !numsFinitosMin(o.bip, 7)) return false;
  if (o.golpes != null && (typeof o.golpes !== "object" || Array.isArray(o.golpes))) return false;
  return typeof o.avion === "string" && Object.prototype.hasOwnProperty.call(Modelos._datos, o.avion);
}
/** Manda el estado propio y recoge el de los demas (10 veces por segundo, sin solaparse). */
async function enviarSala() {
  if (!MULTI.sala || MULTI.enCurso || !av || !modelo) return;
  MULTI.enCurso = true;
  const r6 = x => Math.round(x * 1e3) / 1e3, est = ev && ev.obj ? Object.values(ev.obj).map(o => o.estado) : [];
  // objetivos: cumplidos, total y fallados (las normas siguen "en curso" hasta aterrizar); y lo que va haciendo en el trabajo
  const ahora = ev && (ev.op || ev.fpv) ? (ev.op || ev.fpv).ahora(ev.obj, av).replace(/<[^>]+>/g, "").slice(0, 160) : "";
  const e = { id: multiId(), nombre: nombrePiloto(), alumno: sesion.alumno ? sesion.alumno.id : null, avion: sesion.avion, p: av.p.map(r6), q: av.q.map(x => Math.round(x * 1e5) / 1e5), vn: Cuat.rot(av.q, av.v).map(r6),
              estado: av.estado, gas: r6(av.gases || 0), agl: r6(av.agl || 0), objs: ev && ev.obj ? [est.filter(x => x === "ok").length, est.length, est.filter(x => x === "mal").length] : null, ahora,
              tvuelo: vuelo ? r6(vuelo.tVuelo) : 0, final: vuelo ? vuelo.final : null, gimbal: av.gimbal };
  if (modelo.esBipode) { e.bip = [av.cintura, av.brazos, av.fase, av.amp, av.angCanones, av.disparos, av.puno].map(r6); if (juegoBip) e.golpes = juegoBip.golpes; }
  if (CARRERA_MEJOR && ev && ev.op && ev.op.carr) e.carrera = +CARRERA_MEJOR.t.toFixed(2);          // carrera: el mejor tiempo de la sesion
  const cmE = camDJI(); e.cam = visor.camara; e.zoom = cmE.zoom || 1; e.ter = !!cmE.termica;                      // lo que ve el piloto (vista del alumno del profesor)
  if (av.torreta) e.tor = [r6(av.torreta.pan), r6(av.torreta.tilt)];
  try {
    const r = await api("POST", `salas/${MULTI.sala.codigo}/estado`, e), t = performance.now(), vivos = new Set();
    for (const o of r.otros) { if (!estadoValido(o)) continue; vivos.add(o.id); MULTI.otros.set(o.id, Object.assign(o, { recibido: t })); impactosDe(o); }   // lo mal formado se ignora
    for (const k of [...MULTI.otros.keys()]) if (!vivos.has(k)) MULTI.otros.delete(k);
    aplicarOrdenes(r.ordenes);
    if (MULTI.sala) MULTI.sala.record = r.sala && r.sala.record && typeof r.sala.record.t === "number" ? r.sala.record : null;
  } catch (err) {
    if (/no existe/.test(err.message)) { toast("La sala se ha cerrado"); salirSala(); }
    else if (err.status === 403) { salirSala(); irInicio(); confirmar("Fuera de la sala", `<p>${esc(err.message)}</p>`, "Vale"); }   // expulsado por el profesor
  } finally { MULTI.enCurso = false; }
}
// ---- bipode en multijugador: sus disparos derriban los aviones y drones de los compañeros. Cada bipode manda en su
// estado los impactos que lleva dados a cada piloto (golpes: id -> cuantos); quien los recibe resta vidas (una: cae al
// primer impacto) y, sin vidas, cae derribado. Los bipodes de los demas se ven andando y disparando (sus trazadoras, solo de adorno).
const BIP_VIDAS = 1;                  // cae al primer impacto
function impactosDe(o) {
  if (!o.golpes || !av || !modelo || modelo.esTerrestre) return;
  const D = Modelos.datos(o.avion); if (!D || D.tipo !== "bipode") return;                 // solo dispara el bipode
  const n = +o.golpes[multiId()] || 0, vistos = MULTI.golpesVistos = MULTI.golpesVistos || {};
  if (vistos[o.id] === undefined) { vistos[o.id] = n; return; }                 // los de antes de entrar no cuentan
  if (n <= vistos[o.id]) return;
  const nuevos = n - vistos[o.id]; vistos[o.id] = n;
  if (av.estado !== "volando" || av.posado || MULTI.caida) return;
  MULTI.vida = (MULTI.vida === undefined ? BIP_VIDAS : MULTI.vida) - nuevos;
  Sonido.evento("roto");
  if (MULTI.vida > 0) { toast(`¡Impacto de ${o.nombre}! Te quedan ${MULTI.vida}`); return; }
  MULTI.vida = BIP_VIDAS; toast(`¡Derribado por ${o.nombre}!`);
  MULTI.caida = { v: Cuat.rot(av.q, av.v), w: 3 + 3 * Math.random(), nombre: o.nombre };     // cae dando vueltas hasta el suelo
}
/** Derribado: los motores se paran y cae con su velocidad, dando vueltas, hasta el suelo; ahi acaba el vuelo. */
function caidaDerribado(dt) {
  const c = MULTI.caida;
  c.v[2] += 9.81 * dt; c.v[0] *= 1 - 0.3 * dt; c.v[1] *= 1 - 0.3 * dt;
  av.p = [av.p[0] + c.v[0] * dt, av.p[1] + c.v[1] * dt, av.p[2] + c.v[2] * dt];
  const e = Cuat.euler(av.q); av.q = Cuat.desdeEuler(e[0] + c.w * dt, e[1] + 0.4 * c.w * dt, e[2] + 0.7 * c.w * dt);
  av.v = Cuat.rot(Cuat.inv(av.q), c.v); av.gases = 0; av.rpm = 0; av.motorRoto = true;
  const suelo = entorno.altura ? entorno.altura(av.p[0], av.p[1]) : 0;
  if (-av.p[2] <= suelo) { av.p[2] = -suelo; MULTI.caida = null; terminarVuelo(`roto (derribado por ${c.nombre})`, c.v); }
}
/** Los blancos del bipode (multijugador): los aviones y drones de los demas que estan en el aire. */
function blancosSala() {
  const lista = [];
  if (!MULTI.sala) return lista;
  for (const o of MULTI.otros.values()) {
    const D = Modelos.datos(o.avion); if (!D || D.tipo === "bipode" || o.estado !== "volando" || (o.agl || 0) < 0.3) continue;
    const g = visor.fantasmas && visor.fantasmas.get(o.id);
    lista.push({ id: o.id, p: g ? g.p.slice() : o.p.slice(), r: Math.max(0.8, (D.b_m || 1) / 2 + 0.25) });
  }
  return lista;
}
/** Trazadoras de los bipodes de los demas: por cada disparo nuevo que anuncian, una bala de adorno desde su cañon. */
let balasOtros = null;
function pasoBalasOtros(dt) {
  if (!MULTI.sala) { if (balasOtros) { balasOtros.ef.quitar(); balasOtros = null; } return; }
  for (const o of MULTI.otros.values()) {
    if (!o.bip || !Modelos.datos(o.avion)) continue;
    const D = Modelos.datos(o.avion);
    if (!balasOtros) balasOtros = { J: new JuegoBipode(D, 7), ef: ModeloBipode.efectos3D(visor.escena), vistos: {} };
    const n = o.bip[5], v = balasOtros.vistos[o.id];
    balasOtros.vistos[o.id] = n;
    if (v === undefined || n <= v) continue;
    const piv = {}; for (const pz of D.modelo3d.piezas) piv[pz.nombre] = pz.pivote;
    const g = visor.fantasmas && visor.fantasmas.get(o.id), est = { p: g ? g.p : o.p, q: o.q, cintura: o.bip[0], brazos: o.bip[1] };
    for (let k = 0; k < Math.min(4, n - v); k++) balasOtros.J.disparo(ModeloBipode.prototype.apuntado.call({ piv, bp: D.bipode }, est));
  }
  if (!balasOtros) return;
  balasOtros.J.paso(dt, { p: [0, 0, 0], disparos: balasOtros.J.disparos }, null, entorno.altura ? (N, E) => entorno.altura(N, E) : null);
  balasOtros.J.eventos = balasOtros.J.eventos.filter(e => e.tipo === "suelo");
  balasOtros.ef.pintar(balasOtros.J, dt, visor.cam);
}
/** Panel de la sala en vuelo: quien esta y como va. */
function pintarSalaInfo() {
  const el = document.getElementById("salaInfo");
  if (!MULTI.sala) { el.style.display = "none"; return; }
  el.style.display = "block";
  const fila = o => `<div>● ${esc(o.nombre)} · ${esc((Modelos.datos(o.avion) || {}).nombre || o.avion)} · ${o.estado === "volando" ? Math.max(0, o.agl || 0).toFixed(0) + " m" : esc(o.estado)}` +
    (o.objs && +o.objs[1] ? ` · ${+o.objs[0] || 0}✔${+o.objs[2] ? " " + (+o.objs[2] || 0) + "✘" : ""} de ${+o.objs[1] || 0}` : "") + `</div>`;
  el.innerHTML = `<b>Sala ${MULTI.sala.codigo}</b> · ${esc(MULTI.sala.nombre)}` + ([...MULTI.otros.values()].map(fila).join("") || "<div>Todavía no hay nadie más</div>");
}
// ---- ordenes del profesor a la sala (panel del profesor, POST /api/salas/<cod>/orden): viento, NOTAM, aterrizaje
// inmediato, zonas de exclusion, el desaparecido de la busqueda y la fuga de SABIC. Las mismas en simulador_godot (principal.gd).
const ORDENES = {
  reiniciar() { this.n = 0; this.viento = null; this.notam = []; this.aterrizar = false; this.zonas = []; this.persona = null; this.fuga = null; this.tAviso = 0; },
};
ORDENES.reiniciar();
const EXCLUSION_TXT = "Respetar las zonas de exclusión que marca el profesor";
function aplicarOrdenes(lista) {
  let cambio = false;
  for (const o of lista || []) {
    if (o.n <= ORDENES.n) continue;
    ORDENES.n = o.n; cambio = true;
    if (o.para && o.para !== "*" && o.para !== multiId()) continue;
    const nueva = (o.edad || 0) < 30;              // las de antes de entrar en la sala se aplican sin anunciarlas
    if (o.tipo === "viento") {
      ORDENES.viento = { vel: o.vel, desde: o.desde, rachas: !!o.rachas }; entorno.configurarViento(ORDENES.viento);
      if (nueva) toast(`Viento: ${o.vel} m/s del ${RUMBOS_VIENTO[Math.round(o.desde / 45) % 8]}${o.rachas ? ", con rachas" : ""}`);
    }
    if (o.tipo === "notam") { ORDENES.notam.push(o.texto || ""); if (nueva) toast("Nuevo NOTAM"); }
    if (o.tipo === "quitar_notam") ORDENES.notam = [];
    if (o.tipo === "aterrizar" && nueva) { ORDENES.aterrizar = performance.now(); ORDENES.enAire = false; }
    if (o.tipo === "exclusion") { ORDENES.zonas.push({ id: o.n, N: o.N, E: o.E, r: o.r }); if (nueva) toast("Nueva zona de exclusión: mírala en el mapa"); }
    if (o.tipo === "quitar_exclusion") ORDENES.zonas = ORDENES.zonas.filter(z => z.id !== o.id);
    if (o.tipo === "senderista") { ORDENES.persona = [o.N, o.E]; if (moverDesaparecido() && nueva) toast("Nueva posición del desaparecido: búscalo"); }
    if (o.tipo === "fuga") { ORDENES.fuga = [o.N, o.E]; if (moverFugaProfesor() && nueva) toast("La fuga de gas ahora está en otra unidad: localízala de nuevo"); }
    if (o.tipo === "averia" && nueva && modelo && av && vuelo && av.estado === "volando") {     // averia en vuelo: sin avisar (como en la realidad)
      const a = Desgaste.adaptar(Modelos.datos(sesion.avion), { c: o.c, tipo: o.averia, n: o.celda });
      if (a) { Desgaste.enVuelo(modelo, a); (vuelo.averiasSala = vuelo.averiasSala || []).push(a); const ap = Desgaste.avisosApp({ averias: [a], tipo: modelo.tipo }); if (ap.length) toast(ap.join(" · ")); }
    }
  }
  if (cambio) { ordenesAlEvaluador(); if (visor && visor.ponerExclusiones) visor.ponerExclusiones(ORDENES.zonas); }
  pintarOrdenes();
}
/** El desaparecido donde lo ha puesto el profesor (en la busqueda): hay que volver a encontrarlo. */
function moverDesaparecido() {
  if (!ORDENES.persona || !ev || !ev.op || !ev.op.d.zona) return false;
  const op = ev.op; op.d.persona = ORDENES.persona.slice(); op.encontrado = false; op.error = null;
  for (const k of ["localizar", "posicion"]) if (ev.obj[k] && ev.obj[k].estado !== "mal") ev.obj[k].estado = "pend";
  if (visor.ponerOperacion) { const c = casa(); visor.ponerOperacion(op.d, [c.N, c.E]); }
  return true;
}
/** La fuga de gas de SABIC en la unidad mas cercana a donde la ha puesto el profesor: hay que volver a localizarla. */
function moverFugaProfesor() {
  if (!ORDENES.fuga || !ev || !ev.op || !ev.op.d.racks) return false;
  ev.op.moverFuga(ORDENES.fuga[0], ORDENES.fuga[1]); ev.fugaProfesor = true;
  if (ev.obj.fuga && ev.obj.fuga.estado !== "mal") ev.obj.fuga.estado = "pend";
  if (visor.ponerOperacion) { const c = casa(); visor.ponerOperacion(ev.op.d, [c.N, c.E]); }
  return true;
}
/** Al empezar (o empezar de nuevo) un vuelo en la sala: el viento, el desaparecido y el objetivo de las zonas de exclusion. */
function ordenesAlEvaluador() {
  if (!MULTI.sala || !ev) return;
  if (ev.op && MULTI.sala.ajustes) for (const k in ev.obj) ev.obj[k].texto = Operacion.textoObjetivo(k, ev.obj[k].texto, ev.op.d);   // "los 12 modulos..."
  const V = ORDENES.viento || MULTI.sala.viento;                  // el viento de la sala (o el que haya mandado el profesor despues)
  if (V && !ev.vientoProfesor) { entorno.configurarViento(V); ev.vientoProfesor = true; }
  if (ORDENES.persona && ev.op && ev.op.d.zona && (ev.op.d.persona[0] !== ORDENES.persona[0] || ev.op.d.persona[1] !== ORDENES.persona[1])) moverDesaparecido();
  if (ORDENES.fuga && ev.op && ev.op.d.racks && !ev.fugaProfesor) moverFugaProfesor();
  if (ORDENES.zonas.length && !ev.obj.exclusion) ev.obj.exclusion = { texto: EXCLUSION_TXT, estado: "curso" };
}
/** En cada paso en vuelo: dentro de una zona de exclusion, aviso y objetivo suspendido. */
function vigilarExclusiones() {
  if (!MULTI.sala || !ORDENES.zonas.length || !ev || av.estado !== "volando" || av.posado) return;
  const z = ORDENES.zonas.find(z => Math.hypot(av.p[0] - z.N, av.p[1] - z.E) < z.r);
  if (!z) return;
  marcar("exclusion", "mal");
  if (performance.now() - ORDENES.tAviso > 4000) { ORDENES.tAviso = performance.now(); toast("¡Dentro de una zona de exclusión! Sal de ella"); }
}
function pintarOrdenes() {
  const el = document.getElementById("ordenesHud");
  if (ORDENES.aterrizar && av) {                  // hasta que aterrice (si ya estaba en el suelo, 8 s)
    const enSuelo = av.estado !== "volando" || av.posado;
    if (!enSuelo) ORDENES.enAire = true;
    else if (ORDENES.enAire || performance.now() - ORDENES.aterrizar > 8000) ORDENES.aterrizar = false;
  }
  el.innerHTML = (ORDENES.aterrizar ? '<div class="aterriza">ATERRIZA YA · orden del profesor</div>' : "") +
    ORDENES.notam.map(t => `<div class="notam">NOTAM · ${esc(t)}</div>`).join("");
}
/** Los demas en el GPS: triangulos azules con su rumbo (y las zonas de exclusion del profesor). */
function pintarOtrosGPS(g, X, Y, W) {
  if (juegoBip) for (const dr of juegoBip.drones) {            // bipode: los drones diana (rojos; gris, los derribados)
    const x = X(dr.p[1]), y = Y(dr.p[0]); if (x < 0 || y < 0 || x > W || y > W) continue;
    g.fillStyle = dr.estado === "vuela" ? "#ff5252" : "#777"; g.strokeStyle = "#000"; g.lineWidth = 1;
    g.beginPath(); g.moveTo(x, y - 5); g.lineTo(x + 5, y); g.lineTo(x, y + 5); g.lineTo(x - 5, y); g.closePath(); g.fill(); g.stroke();
  }
  if (!MULTI.sala) return;
  for (const z of ORDENES.zonas) {
    const k = Math.abs(X(z.E + 100) - X(z.E)) / 100;
    g.beginPath(); g.arc(X(z.E), Y(z.N), z.r * k, 0, 7); g.fillStyle = "rgba(229,57,53,.28)"; g.fill(); g.strokeStyle = "#e53935"; g.lineWidth = 2; g.stroke();
  }
  for (const o of MULTI.otros.values()) {
    const x = X(o.p[1]), y = Y(o.p[0]); if (x < 0 || y < 0 || x > W || y > W) continue;
    g.save(); g.translate(x, y); g.rotate(Cuat.euler(o.q)[2]); g.fillStyle = "#4fc3f7"; g.strokeStyle = "#000"; g.lineWidth = 1;
    g.beginPath(); g.moveTo(0, -7); g.lineTo(5, 5); g.lineTo(0, 3); g.lineTo(-5, 5); g.closePath(); g.fill(); g.stroke(); g.restore();
  }
}
