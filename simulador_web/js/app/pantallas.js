// Pantallas: inicio, hangar (con el robot y el morro de camaras), condiciones y entrenamientos.
// Parte de la aplicacion de simulador_web/simulador.html: los modulos de js/app/ se cargan en orden y comparten el
// ambito global. En Godot: simulador_godot/scripts/app/pantallas.gd.
"use strict";
// =====================================================================
//  PANTALLAS: inicio, pilotos, hangar, entrenamientos, vuelo libre y ajustes
// =====================================================================
function irInicio() {
  salirSala();                                  // al volver al inicio se sale de la sala multijugador
  Desgaste.cargar();                            // el estado de los vehiculos, al dia (el profesor puede haber puesto averias)
  const A = Modelos.datos(sesion.avion);
  document.getElementById("inicioAvionNombre").textContent = A.nombre;
  document.getElementById("inicioAvionDesc").textContent = (A.descripcion || "").split(". ")[0];
  document.getElementById("inicioPerfilNombre").textContent = sesion.alumno ? sesion.alumno.nombre : "Sin conexión";
  document.getElementById("inicioPerfilModo").textContent = sesion.alumno ? "online · aula " + sesion.nombreAula : "el progreso no se guarda";
  document.getElementById("chipAula").textContent = sesion.alumno ? "Aula: " + sesion.nombreAula : "Sin conexión: los vuelos no se guardan";
  previa.mostrar(datosVisor(sesion.avion), 1.75); mostrar("pInicio");
}
document.getElementById("mnVolar").onclick = e => irVolar(e);               // se vuela con el usuario del aula (o sin conexion)
document.getElementById("mnEntrenar").onclick = irEntrenamientos;
document.getElementById("mnOperaciones").onclick = e => irOperaciones(e);
document.getElementById("mnMulti").onclick = e => irMulti(e);
const irPerfil = () => sesion.alumno ? irProgreso("pInicio") : irAcceso();
document.getElementById("mnPerfil").onclick = irPerfil;
document.getElementById("mnHangar").onclick = irHangar;
document.getElementById("mnTaller").onclick = () => Taller.abrir();
document.getElementById("mnAjustes").onclick = () => irAjustes();
document.getElementById("inicioPerfil").onclick = irPerfil;

// ---- hangar ----
function elegirAvion(id) { sesion.avion = id; try { localStorage.setItem("sim_avion", id); } catch (e) {} }
// ---- el robot (vehiculo oculto, datos.oculto): solo para el piloto con los tres logros del perfil (servidor del aula) ----
function robotDesbloqueado() { return !!(sesion.alumno && sesion.alumno.progreso && sesion.alumno.progreso.robot); }
/** Los vehiculos del hangar: el robot, solo con los logros. */
function idsHangar() { return Modelos.ids().filter(id => !Modelos.datos(id).oculto || robotDesbloqueado()); }
// ---- morro de camaras (datos.camara.morros: el Grajo): fijo (camaras frontal y lateral sujetas al avion) u orientable
// (torreta estabilizada, con su peso); se elige en el Hangar y se guarda por vehiculo ----
function morroDe(id) {
  const C = (Modelos.datos(id) || {}).camara; if (!C || !C.morros) return null;
  let m = null; try { m = localStorage.getItem("sim_morro_" + id); } catch (e) {}
  return C.morros.includes(m) ? m : C.morros[0];
}
function ponerMorro(id, m) { try { localStorage.setItem("sim_morro_" + id, m); } catch (e) {} }
/** Los datos del vehiculo para dibujarlo: con el morro elegido (sin la torreta si es el fijo; sin las camaras fijas si no). */
function datosVisor(id) {
  const A = Modelos.datos(id), m = morroDe(id);
  if (!m || !A.malla) return A;
  const K = Object.assign({}, A.malla);
  if (m === "fijo") delete K.torreta; else delete K.cam_fija;
  return Object.assign({}, A, { malla: K });
}
/** Si el vehiculo elegido es el robot y este piloto no lo tiene, vuelve al dron comercial. */
function vehiculoPermitido() { if (Modelos.datos(sesion.avion) && Modelos.datos(sesion.avion).oculto && !robotDesbloqueado()) elegirAvion(Modelos.ids().includes("DJI_MINI") ? "DJI_MINI" : idsHangar()[0]); }
function irHangar() {
  vehiculoPermitido();
  document.getElementById("saludo").textContent = sesion.alumno ? `Piloto: ${sesion.alumno.nombre}` : "Elige el avión y, si quieres, ajústalo como el tuyo.";
  document.getElementById("btnVerProgreso").style.display = sesion.alumno ? "" : "none";
  const sel = document.getElementById("selAviones"); sel.innerHTML = "";
  for (const id of idsHangar()) {
    const A = Modelos.datos(id), b = document.createElement("button"); b.className = "avCarta" + (id === sesion.avion ? " sel" : "");
    const masa = (A.caracteristicas || []).find(r => r[0].toLowerCase().startsWith("masa"));
    const mandosTxt = ((A.caracteristicas || []).find(c => c[0] === "Mandos") || [])[1];   // la linea "Mandos" de la ficha, si la trae
    b.innerHTML = `<b>${esc(A.nombre)}</b><span>${A.tipo === "cuadricoptero" ? "cuadricóptero, mandos de dron comercial" : A.tipo === "fpv" ? "dron FPV, modos de Betaflight" : A.tipo === "bipode" ? "vehículo terrestre de dos patas" : esc(mandosTxt || ((A.mandos && A.mandos.izq_der) || "timón") + " y profundidad")}${masa ? " · " + esc(String(masa[1]).split(" (")[0]) : ""}</span>`;
    b.onclick = () => { elegirAvion(id); irHangar(); };
    sel.appendChild(b);
  }
  pintarFichaAvion(); previa.mostrar(datosVisor(sesion.avion), 1.4); pintarCM(); pintarMorro();
  mostrar("pHangar");
}
const irAvion = irHangar;
/** Hangar: el morro de camaras (solo los vehiculos que lo cambian). */
function pintarMorro() {
  const C = Modelos.datos(sesion.avion).camara, sec = document.getElementById("secMorro");
  sec.style.display = C && C.morros ? "" : "none";
  if (!C || !C.morros) return;
  const m = morroDe(sesion.avion);
  for (const r of document.querySelectorAll("#secMorro input[name=morro]")) { r.checked = r.value === m; r.onchange = () => { ponerMorro(sesion.avion, r.value); previa.mostrar(datosVisor(sesion.avion), 1.4); }; }
}
function pintarFichaAvion() {
  const A = Modelos.datos(sesion.avion);
  document.getElementById("avNombre").textContent = A.nombre;
  document.getElementById("avDesc").textContent = A.descripcion || "";
  // ficha: lo que trae el fichero del avion y, si no lo trae ya, la cuerda (de c_m) y el perfil alar (campo perfil)
  const filas = (A.caracteristicas || []).slice(), tiene = n => filas.some(([k]) => k.toLowerCase().startsWith(n));
  if (A.c_m && !tiene("cuerda")) filas.splice(1, 0, ["Cuerda", `${(A.c_m * 1000).toFixed(0)} mm`]);
  if (A.perfil && !tiene("perfil")) filas.splice(2, 0, ["Perfil alar", A.perfil]);
  document.getElementById("avDatos").innerHTML = filas.map(([k, v]) => `<tr><th>${esc(k)}</th><td>${esc(v)}</td></tr>`).join("");
}
document.querySelectorAll("#hangarFicha .pestanas button").forEach(b => b.onclick = () => {
  document.querySelectorAll("#hangarFicha .pestanas button").forEach(x => x.classList.toggle("sel", x === b));
  document.querySelectorAll("#hangarFicha .panelPestana").forEach(p => p.classList.toggle("sel", p.dataset.p === b.dataset.p));
});
document.getElementById("btnHangarVolver").onclick = irInicio;
document.getElementById("btnHangarVolar").onclick = irInicio;      // el vehiculo queda elegido: en el inicio se elige que volar

// ---- condiciones (viento): un solo panel que se mueve a la pantalla que lo use ----
function montarCondiciones(slotId, E) {
  const c = document.getElementById("condiciones"), s = document.getElementById(slotId);
  if (c.parentElement !== s) s.appendChild(c);
  c.style.display = "";
  const fijo = E && E.viento, v = fijo || sesion.viento;
  document.getElementById("vVel").value = v.vel; document.getElementById("vDir").value = String(v.desde);
  document.getElementById("vRachas").checked = v.rachas; document.getElementById("vVelTxt").textContent = v.vel + " m/s";
  for (const id of ["vVel", "vDir", "vRachas"]) document.getElementById(id).disabled = !!fijo;
  document.getElementById("condNota").textContent = fijo ? "Este entrenamiento fija su propio viento." :
    `Para empezar, menos de 3 m/s. Física ${sesion.dificultad === "facil" ? "fácil" : "real"} (se cambia en Ajustes).`;
}

// ---- entrenamientos: tarjetas con icono, dificultad y estado; la ficha de la elegida a la derecha ----
let misionSel = null;

/** Tipo de vehiculo de un avion de la carpeta aviones/: "avion", "dron" (el dron comercial) o "fpv" (escenarios.js: "vehiculos"). */
function vehiculoDe(id) { const D = Modelos.datos(id) || {}, t = D.tipo; return D.uav ? "uav" : t === "fpv" ? "fpv" : t === "cuadricoptero" ? "dron" : t === "bipode" ? "bipode" : "avion"; }
/** Los entrenamientos (con objetivos) de un vehiculo, en el orden de escenarios.js. */
function misionesDe(veh) { return Object.keys(ESCENARIOS).filter(id => ESCENARIOS[id].objetivos.length && !ESCENARIOS[id].operacion && (ESCENARIOS[id].vehiculos || ["avion"]).includes(veh)); }
function irEntrenamientos() {
  const g = sesion.alumno && sesion.alumno.progreso, veh = vehiculoDe(sesion.avion), lista = misionesDe(veh);
  document.getElementById("escSub").textContent = Modelos.datos(sesion.avion).nombre + " · " + lista.length + " entrenamientos" +
    (g ? ` · ${g.escenarios_superados}/${g.escenarios_total ?? Object.keys(g.escenarios).length} pruebas del certificado superadas` : " · sin registro");
  const el = document.getElementById("listaEscenarios"); el.innerHTML = "";
  if (!lista.length) {               // el bipode no tiene entrenamientos: es para el vuelo libre
    el.innerHTML = '<p class="sub">Este vehículo no tiene entrenamientos: llévalo al vuelo libre.</p>';
    document.getElementById("fichaMision").innerHTML = ""; document.getElementById("btnMisionVolar").disabled = true;
    mostrar("pEntrenamientos"); return;
  }
  document.getElementById("btnMisionVolar").disabled = false;
  if (!lista.includes(misionSel)) misionSel = lista[0];
  for (const id of lista) {
    const E = ESCENARIOS[id];
    if (E.titulo_grupo) { const t = document.createElement("div"); t.className = "zonaTitulo"; t.textContent = E.titulo_grupo; el.appendChild(t); }
    const st = g && ((g.entrenamientos || {})[id] || g.escenarios[id]), dif = E.dificultad || 1;     // cuente o no para el certificado
    const d = document.createElement("div"); d.className = "mision" + (id === misionSel ? " sel" : "");
    d.innerHTML = `<div class="img">${iconoMision(id)}</div><div class="txt"><h3>${esc(E.nombre.replace(/^\d · /, ""))}${st && st.superado ? ' <span class="hecha" title="superado">✔</span>' : ""}</h3>
      <p>${esc(E.desc)}</p><div class="meta"><span class="estrellas">${"★".repeat(dif)}${"☆".repeat(3 - dif)}</span>${st && st.intentos ? `<span>· ${st.intentos} intento${st.intentos > 1 ? "s" : ""}</span>` : ""}</div></div>`;
    d.onclick = () => { misionSel = id; irEntrenamientos(); };
    el.appendChild(d);
  }
  const E = ESCENARIOS[misionSel];
  document.getElementById("fichaMision").innerHTML = `<h2>${esc(E.nombre)}</h2><p class="sub" style="font-size:14px;margin:0 0 8px">${esc(E.desc)}</p>` +
    (E.sentido ? `<p style="font-size:14px;margin:0 0 8px">Orden de los pilones: ${ordenHTML(E.sentido)}</p>` : "") +
    `<b style="font-size:12px;color:var(--suave);text-transform:uppercase;letter-spacing:.08em">Objetivos</b><ul>${E.objetivos.map(o => `<li>${esc(o[1])}</li>`).join("")}</ul>`;
  montarCondiciones("condicionesSlotEntrenar", E);
  mostrar("pEntrenamientos");
}
const irEscenario = irEntrenamientos;
