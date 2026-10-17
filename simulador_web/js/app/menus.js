// Operaciones (orden de trabajo y comprobaciones), vuelo libre y ajustes.
// Parte de la aplicacion de simulador_web/simulador.html: los modulos de js/app/ se cargan en orden y comparten el
// ambito global. En Godot: las pantalla_*.gd de simulador_godot/scripts/.
"use strict";
// ---- operaciones: trabajos de operador de dron (escenarios.js, "operacion"); la orden de trabajo y las comprobaciones
// antes del vuelo, que hay que marcar todas para poder volar ----
const COMPROBACIONES_OP = ["Operador registrado en AESA y piloto con el certificado que pide el dron (A1/A3 o A2)", "Zona consultada en el mapa de ENAIRE Drones: no es zona prohibida ni restringida",
  "Viento previsto por debajo de 8 m/s", "Baterías del dron y del mando cargadas; hélices sin daños", "Permiso del cliente y del propietario del terreno",
  "Zona de despegue despejada y nadie debajo del vuelo"];
const COMPROBACIONES_UAV = ["NOTAM publicado y vuelo coordinado con la torre de San Javier (espacio aéreo controlado)", "Tripulación de la estación de control con la habilitación del UAS",
  "Combustible y aceite comprobados; hélice, tren y frenos sin daños", "Enlace de datos, GPS y estación de control probados; vuelta a base programada",
  "Viento en pista dentro de los límites del avión", "Pista libre y autorización de despegue de la torre"];   // UAV de pista (espacio aereo controlado)
const COMPROBACIONES_MANO = ["Zona consultada en el mapa de ENAIRE Drones y vuelo coordinado (NOTAM si es espacio aéreo controlado)", "Piloto y observador con la habilitación del sistema",
  "Baterías del avión y de la estación de control cargadas; hélice sin daños", "Montaje comprobado: ala, cola y morro asegurados",
  "Enlace de datos, GPS y estación de control probados; vuelta a base programada", "Viento dentro de los límites del lanzamiento a mano: se lanza de cara al viento",
  "Zona de lanzamiento y de toma despejadas, nadie delante"];      // aviones lanzados a mano (Grajo, Poli-1, Entrenador 1)
const RUMBOS_VIENTO = ["norte", "nordeste", "este", "sudeste", "sur", "sudoeste", "oeste", "noroeste"];
let opSel = null; const opVehiculo = {};
/** El vehiculo con el que se vuela el trabajo id: el que pide (operacion.avion) o, si deja elegir (operacion.elegir: clases
 *  de vehiculo), el que haya elegido el piloto en la orden de trabajo. */
/** Si el trabajo deja volarlo con el vehiculo a (operacion.elegir: clases de vehiculo o ids, como el reconocimiento). */
function opPermite(O, a) { return !!(O.elegir && (O.elegir.includes(vehiculoDe(a)) || O.elegir.includes(a))); }
function vehOp(id) { const O = ESCENARIOS[id].operacion, a = opVehiculo[id]; return O.elegir && a && Modelos.datos(a) && opPermite(O, a) ? a : O.avion; }
function operacionesLista() { return Object.keys(ESCENARIOS).filter(id => ESCENARIOS[id].operacion); }
function irOperaciones() {
  const lista = operacionesLista(), el = document.getElementById("listaOperaciones"); el.innerHTML = "";
  if (!lista.includes(opSel)) opSel = lista[0];
  const filas = {};                                                   // una fila por vehiculo, en el orden en que salen
  for (const id of lista) {
    const av = ESCENARIOS[id].operacion.avion || "";
    if (!filas[av]) {
      const D = Modelos.datos(av), h = document.createElement("div"); h.className = "grupoOp";
      h.innerHTML = `${esc(D ? D.nombre : av)}${D && D.categoria ? `<span>${esc(D.categoria)}</span>` : ""}`;
      filas[av] = document.createElement("div"); filas[av].className = "filaOp"; el.appendChild(h); el.appendChild(filas[av]);
    }
    const n = Math.max(...Object.values(lista.reduce((c, k) => (c[ESCENARIOS[k].operacion.avion || ""] = (c[ESCENARIOS[k].operacion.avion || ""] || 0) + 1, c), {})));
    filas[av].style.gridAutoColumns = `minmax(180px, calc((100% - ${(n - 1) * 12}px) / ${n}))`;    // todas las filas con el ancho de la mas larga
    const E = ESCENARIOS[id], dif = E.dificultad || 1, d = document.createElement("div");
    d.className = "mision" + (id === opSel ? " sel" : "");
    const dron = Modelos.datos(E.operacion.avion);
    d.innerHTML = `<div class="img">${iconoMision(id)}</div><div class="txt"><h3>${esc(E.nombre)}</h3><p>${esc(E.desc)}</p><div class="meta"><span class="estrellas">${"★".repeat(dif)}${"☆".repeat(3 - dif)}</span>${dron ? `<span>${esc(dron.nombre)}</span>` : ""}</div></div>`;
    d.onclick = () => { opSel = id; irOperaciones(); };
    filas[av].appendChild(d);
  }
  const E = ESCENARIOS[opSel], O = E.operacion, v = E.viento, fila = (a, b) => `<tr><td>${a}</td><td>${esc(b)}</td></tr>`;
  document.getElementById("fichaOperacion").innerHTML = `<img src="../datos/operaciones/${opSel}.jpg" alt="" style="width:100%;border-radius:8px;margin:0 0 10px;display:block" onerror="this.remove()">
    <h2>Orden de trabajo</h2><h3 style="margin:0 0 8px;font-size:18px">${esc(E.nombre)}</h3>
    <table class="ordenTrabajo">${fila("Cliente", O.cliente)}${fila("Lugar", O.lugar)}${fila("Trabajo", O.trabajo)}${fila("Entrega", O.entrega)}
    ${fila("Viento previsto", `${v.vel} m/s del ${RUMBOS_VIENTO[Math.round(v.desde / 45) % 8]}${v.rachas ? ", con rachas" : ""}`)}${fila(O.elegir ? "Vehículo" : "Dron", (D => D ? `${D.nombre} (${D.categoria})` : O.avion)(Modelos.datos(vehOp(opSel))))}</table>
    <b style="font-size:12px;color:var(--suave);text-transform:uppercase;letter-spacing:.08em">Se evalúa</b><ul>${E.objetivos.map(o => `<li>${esc(o[1])}</li>`).join("")}</ul>`;
  if (O.elegir) {                                                    // carrera, patrulla, reconocimiento: se elige el vehiculo (tambien al pulsar Volar)
    const ids = idsHangar().filter(a => opPermite(O, a)), sel = vehOp(opSel), div = document.createElement("div"); div.className = "elegirVeh";
    div.innerHTML = "<b>Vuela con</b>" + ids.map(a => `<button class="btn${a === sel ? " prim" : ""}" data-av="${esc(a)}">${esc(Modelos.datos(a).nombre)}</button>`).join("");
    div.querySelectorAll("button").forEach(b => b.onclick = () => { opVehiculo[opSel] = b.dataset.av; irOperaciones(); });
    document.getElementById("fichaOperacion").insertBefore(div, document.getElementById("fichaOperacion").querySelector("table"));
  }
  mostrar("pOperaciones");
}
/** Las comprobaciones antes de volar del trabajo id con el vehiculo con el que se vuela: las del dron, las del UAV de
 *  pista (con tren) o las de un avion lanzado a mano. */
function comprobacionesDe(id) {
  const a = vehOp(id), D = Modelos.datos(a) || {}, v = vehiculoDe(a);
  return v === "dron" || v === "fpv" ? COMPROBACIONES_OP : D.tren && typeof D.tren === "object" ? COMPROBACIONES_UAV : COMPROBACIONES_MANO;
}
/** Volar: la ventana de las comprobaciones, todas sin marcar; Despegar solo cuando estan todas. */
function pedirComprobaciones(id) {
  const O = ESCENARIOS[id].operacion, v = document.getElementById("checkOp"), si = document.getElementById("checkOpSi");
  document.getElementById("checkOpSub").textContent = ESCENARIOS[id].nombre;
  // los trabajos que dejan elegir el vehiculo (la carrera, la patrulla, el reconocimiento): se elige aqui, antes de volar
  const ids = O.elegir ? idsHangar().filter(a => opPermite(O, a)) : [], ve = document.getElementById("checkOpVeh");
  ve.style.display = ids.length > 1 ? "" : "none";
  let L = [], marcas = [];
  const caja = document.getElementById("checkOpLista");
  const boton = () => { const ok = marcas.every(Boolean); si.disabled = !ok; si.textContent = ok ? `Despegar con el ${Modelos.datos(vehOp(id)).nombre} →` : `Marca todas las comprobaciones (${marcas.filter(Boolean).length}/${L.length})`; };
  const lista = () => {                       // las comprobaciones del vehiculo elegido (sin marcar)
    L = comprobacionesDe(id); marcas = L.map(() => false);
    caja.innerHTML = L.map((t, i) => `<label><input type="checkbox" data-i="${i}"> ${esc(t)}</label>`).join("");
    caja.querySelectorAll("input").forEach(x => x.onchange = () => { marcas[+x.dataset.i] = x.checked; boton(); });
    const sel = vehOp(id), b = document.getElementById("checkOpVehBotones");
    b.innerHTML = ids.map(a => `<button class="btn${a === sel ? " prim" : ""}" data-av="${esc(a)}">${esc(Modelos.datos(a).nombre)}<small>${esc(Modelos.datos(a).categoria || "")}</small></button>`).join("");
    b.querySelectorAll("button").forEach(x => x.onclick = () => { opVehiculo[id] = x.dataset.av; lista(); irOperaciones(); });
    boton();
  };
  lista();
  const cerrar = () => { v.classList.remove("activa"); si.onclick = document.getElementById("checkOpNo").onclick = null; };
  si.onclick = () => { if (!marcas.every(Boolean)) return; cerrar(); volarOperacion(id); };
  document.getElementById("checkOpNo").onclick = cerrar;
  boton(); v.classList.add("activa");
}
/** Empieza el trabajo elegido: con el dron que pide (operacion.avion), desde su punto de despegue. */
function volarOperacion(id) {
  const E = ESCENARIOS[id], S = E.operacion.salida;
  if (vehOp(id) && Modelos.datos(vehOp(id))) elegirAvion(vehOp(id));       // el dron que pide el trabajo (o el elegido, en la carrera)
  else if (vehiculoDe(sesion.avion) !== "dron") elegirAvion(Object.keys(Modelos._datos || {}).find(a => vehiculoDe(a) === "dron") || "DJI_MINI");
  sesion.escenario = id; sesion.lanz = { mundo: E.mundo, N: S.n, E: S.e, rumbo: S.rumbo }; empezar();
}
document.getElementById("btnOpVolver").onclick = irInicio;
document.getElementById("btnOpVolar").onclick = () => pedirComprobaciones(opSel);
document.getElementById("btnEntrenarVolver").onclick = irInicio;
document.getElementById("btnMisionVolar").onclick = () => { leerViento(); sesion.escenario = misionSel; empezar(); };
/** Icono esquematico de cada mision (SVG). */
function iconoMision(id) {
  const avion = (x, y, a, c = "#fff") => `<g transform="translate(${x} ${y}) rotate(${a})"><path d="M-9 0H9M-2 -7V7M6 -3V3" stroke="${c}" stroke-width="2.6" stroke-linecap="round" fill="none"/></g>`;
  const pil = (x, y, c) => `<circle cx="${x}" cy="${y}" r="5" fill="${c}" stroke="#000" stroke-width="1"/>`;
  const P = ["#4caf50", "#ffeb3b", "#f44336", "#42a5f5"], tr = "#ffc83d", pista = (x, y, w, h) => `<rect x="${x}" y="${y}" width="${w}" height="${h}" fill="#8a8a8a" rx="2"/>`;
  const flecha = (x, y, a) => `<g transform="translate(${x} ${y}) rotate(${a})"><path d="M-5 -4L2 0-5 4z" fill="${tr}"/></g>`;
  const ini = `<svg viewBox="0 0 200 110" xmlns="http://www.w3.org/2000/svg">`, fin = `</svg>`;
  switch (id) {
    case "primer_vuelo": return ini + pista(96, 70, 8, 30) + `<path d="M60 35 Q100 10 140 35 Q165 55 140 80 Q100 100 60 80 Q35 55 60 35z" fill="none" stroke="${tr}" stroke-width="2" stroke-dasharray="6 4"/>` +
      pil(60, 35, P[0]) + pil(140, 35, P[1]) + pil(140, 80, P[2]) + pil(60, 80, P[3]) + flecha(100, 21, 0) + avion(100, 55, -10) + fin;
    case "orientacion": return ini + `<path d="M100 55 C70 20 25 25 25 55 C25 85 70 90 100 55 C130 20 175 25 175 55 C175 85 130 90 100 55" fill="none" stroke="${tr}" stroke-width="2.5"/>` +
      pil(140, 35, P[2]) + pil(140, 75, P[3]) + pil(60, 35, P[1]) + pil(60, 75, P[0]) + flecha(173, 45, -80) + flecha(27, 65, 100) + avion(100, 55, 30) + fin;
    case "viento_cruzado": return ini + pista(92, 15, 16, 80) + `<g stroke="#4fc3f7" stroke-width="2.5" stroke-linecap="round" fill="none"><path d="M20 35h30M20 55h40M20 75h30"/><path d="M44 29l6 6-6 6M54 49l6 6-6 6M44 69l6 6-6 6"/></g>` +
      avion(140, 55, -70) + `<path d="M140 80 L140 100" stroke="${tr}" stroke-width="2" stroke-dasharray="4 3"/>` + fin;
    case "emergencia": return ini + `<path d="M40 25 C80 30 120 55 170 90" fill="none" stroke="${tr}" stroke-width="2" stroke-dasharray="6 4"/><path d="M10 92h180" stroke="#6b4a1e" stroke-width="3"/>` +
      avion(40, 25, 20) + `<g stroke="#ff5252" stroke-width="3" stroke-linecap="round"><path d="M58 12l10 10M68 12l-10 10"/></g>` + fin;
    case "puerta": return ini + `<rect x="70" y="20" width="6" height="70" fill="#ff8f00"/><rect x="124" y="20" width="6" height="70" fill="#ff8f00"/>` +
      `<path d="M20 60 H180" stroke="${tr}" stroke-width="2" stroke-dasharray="6 4"/>` + flecha(170, 60, 0) + flecha(30, 72, 180) + avion(100, 60, 0) + fin;
    case "pasada_baja": return ini + `<rect x="20" y="78" width="160" height="12" fill="#8d6e63" rx="2"/><path d="M15 60 H185" stroke="${tr}" stroke-width="2" stroke-dasharray="6 4"/>` +
      `<path d="M30 48 H60" stroke="#fff" stroke-width="1" stroke-dasharray="2 2"/><text x="64" y="51" fill="#fff" font-size="9">2–8 m</text>` + avion(100, 60, 0) + flecha(175, 60, 0) + fin;
    case "diana": return ini + `<g fill="none" stroke="#e0e0e0" stroke-width="1.5"><circle cx="100" cy="68" r="34"/><circle cx="100" cy="68" r="22"/><circle cx="100" cy="68" r="10"/></g><circle cx="100" cy="68" r="3" fill="#ff5252"/>` +
      `<path d="M30 15 Q70 30 96 62" fill="none" stroke="${tr}" stroke-width="2" stroke-dasharray="6 4"/>` + avion(36, 18, 35) + fin;
    case "recorrido": return ini + `<rect x="10" y="80" width="60" height="9" fill="#8d6e63" rx="2"/><rect x="92" y="30" width="4" height="40" fill="#ff8f00"/><rect x="118" y="30" width="4" height="40" fill="#ff8f00"/>` +
      `<g fill="none" stroke="#e0e0e0" stroke-width="1.5"><circle cx="165" cy="80" r="18"/><circle cx="165" cy="80" r="8"/></g>` +
      `<path d="M15 70 H70 Q90 60 105 50 L130 50 Q150 55 162 76" fill="none" stroke="${tr}" stroke-width="2" stroke-dasharray="6 4"/>` +
      `<g fill="${tr}" font-size="12" font-weight="700"><text x="36" y="72">1</text><text x="102" y="24">2</text><text x="148" y="106">3</text></g>` + fin;
    case "aterrizaje": return ini + pista(28, 20, 12, 70) + `<path d="M34 25 C34 10 170 10 170 25 L170 85 C170 100 34 100 34 90" fill="none" stroke="${tr}" stroke-width="2" stroke-dasharray="6 4"/>` +
      flecha(102, 15, 0) + flecha(170, 55, 90) + flecha(102, 95, 180) + avion(34, 60, -90) + `<text x="46" y="60" fill="#fff" font-size="9">final</text>` + fin;
    // operaciones y dron FPV: los mismos SVG que PantallaMisiones.icono de Godot
    case "op_inspeccion": return '<svg viewBox="0 0 200 110" xmlns="http://www.w3.org/2000/svg"><path d="M30 100V45H95V100M95 100V30H160V100" fill="#5d6b78" stroke="#cfd8dc" stroke-width="1.5"/><path d="M40 55h12v10H40zM60 55h12v10H60zM40 75h12v10H40zM105 40h12v10h-12zM125 40h12v10h-12zM105 60h12v10h-12z" fill="#90caf9"/><rect x="137" y="22" width="12" height="7" fill="#ff6d00" stroke="#fff" stroke-width="1"/><path d="M150 0L128 26L158 26z" fill="#4fc3f7" fill-opacity="0.25" stroke="#4fc3f7" stroke-width="1"/><g transform="translate(160 12) rotate(0) scale(1)"><path d="M-8 -8L8 8M8 -8L-8 8" stroke="#fff" stroke-width="2.4"/><g fill="none" stroke="#fff" stroke-width="1.6"><circle cx="-8" cy="-8" r="4.5"/><circle cx="8" cy="-8" r="4.5"/><circle cx="-8" cy="8" r="4.5"/><circle cx="8" cy="8" r="4.5"/></g><rect x="-3" y="-3" width="6" height="6" fill="#9e9e9e"/></g></svg>';
    case "op_fotogrametria": return '<svg viewBox="0 0 200 110" xmlns="http://www.w3.org/2000/svg"><rect x="25" y="40" width="150" height="60" fill="#8d6e63" stroke="#e53935" stroke-width="1.5" stroke-dasharray="5 3"/><rect x="30" y="45" width="40" height="30" fill="#fff" fill-opacity="0.12" stroke="#fff" stroke-opacity="0.7"/><rect x="60" y="67" width="40" height="30" fill="#fff" fill-opacity="0.12" stroke="#fff" stroke-opacity="0.7"/><rect x="90" y="45" width="40" height="30" fill="#fff" fill-opacity="0.12" stroke="#fff" stroke-opacity="0.7"/><rect x="120" y="67" width="40" height="30" fill="#fff" fill-opacity="0.12" stroke="#fff" stroke-opacity="0.7"/><rect x="150" y="45" width="40" height="30" fill="#fff" fill-opacity="0.12" stroke="#fff" stroke-opacity="0.7"/><path d="M30 25H170V35H30" fill="none" stroke="#ffc83d" stroke-width="2" stroke-dasharray="6 4"/><g transform="translate(100 25) rotate(0) scale(1)"><path d="M-8 -8L8 8M8 -8L-8 8" stroke="#fff" stroke-width="2.4"/><g fill="none" stroke="#fff" stroke-width="1.6"><circle cx="-8" cy="-8" r="4.5"/><circle cx="8" cy="-8" r="4.5"/><circle cx="-8" cy="8" r="4.5"/><circle cx="8" cy="8" r="4.5"/></g><rect x="-3" y="-3" width="6" height="6" fill="#9e9e9e"/></g></svg>';
    case "op_busqueda": return '<svg viewBox="0 0 200 110" xmlns="http://www.w3.org/2000/svg"><path d="M0 100L40 60L70 80L110 40L150 75L200 50V110H0z" fill="#5d4f3a"/><circle cx="128" cy="68" r="3.5" fill="#e53935"/><circle cx="128" cy="66" r="16" fill="none" stroke="#fff" stroke-width="2.5"/><path d="M140 78L152 90" stroke="#fff" stroke-width="4" stroke-linecap="round"/><g transform="translate(60 22) rotate(0) scale(1)"><path d="M-8 -8L8 8M8 -8L-8 8" stroke="#fff" stroke-width="2.4"/><g fill="none" stroke="#fff" stroke-width="1.6"><circle cx="-8" cy="-8" r="4.5"/><circle cx="8" cy="-8" r="4.5"/><circle cx="-8" cy="8" r="4.5"/><circle cx="8" cy="8" r="4.5"/></g><rect x="-3" y="-3" width="6" height="6" fill="#9e9e9e"/></g></svg>';
    case "op_agricultura": return '<svg viewBox="0 0 200 110" xmlns="http://www.w3.org/2000/svg"><path d="M15 50H185" stroke="#43a047" stroke-width="5"/><path d="M15 59H185" stroke="#43a047" stroke-width="5"/><path d="M15 68H185" stroke="#43a047" stroke-width="5"/><path d="M15 77H185" stroke="#43a047" stroke-width="5"/><path d="M15 86H185" stroke="#43a047" stroke-width="5"/><path d="M15 95H185" stroke="#43a047" stroke-width="5"/><ellipse cx="70" cy="68" rx="16" ry="9" fill="#d4c13a" fill-opacity="0.9"/><ellipse cx="140" cy="85" rx="12" ry="7" fill="#d4c13a" fill-opacity="0.9"/><path d="M110 18L52 66L90 70z" fill="#4fc3f7" fill-opacity="0.25" stroke="#4fc3f7" stroke-width="1"/><g transform="translate(110 18) rotate(0) scale(1)"><path d="M-8 -8L8 8M8 -8L-8 8" stroke="#fff" stroke-width="2.4"/><g fill="none" stroke="#fff" stroke-width="1.6"><circle cx="-8" cy="-8" r="4.5"/><circle cx="8" cy="-8" r="4.5"/><circle cx="-8" cy="8" r="4.5"/><circle cx="8" cy="8" r="4.5"/></g><rect x="-3" y="-3" width="6" height="6" fill="#9e9e9e"/></g></svg>';
    case "op_paneles": return '<svg viewBox="0 0 200 110" xmlns="http://www.w3.org/2000/svg"><path d="M20 48H180L172 58H28z" fill="#1d3f73" stroke="#9fb3c8" stroke-width="1"/><path d="M42 48l-4 10" stroke="#9fb3c8" stroke-width="0.6"/><path d="M58 48l-4 10" stroke="#9fb3c8" stroke-width="0.6"/><path d="M74 48l-4 10" stroke="#9fb3c8" stroke-width="0.6"/><path d="M90 48l-4 10" stroke="#9fb3c8" stroke-width="0.6"/><path d="M106 48l-4 10" stroke="#9fb3c8" stroke-width="0.6"/><path d="M122 48l-4 10" stroke="#9fb3c8" stroke-width="0.6"/><path d="M138 48l-4 10" stroke="#9fb3c8" stroke-width="0.6"/><path d="M154 48l-4 10" stroke="#9fb3c8" stroke-width="0.6"/><path d="M170 48l-4 10" stroke="#9fb3c8" stroke-width="0.6"/><path d="M28 63H172L164 73H36z" fill="#1d3f73" stroke="#9fb3c8" stroke-width="1"/><path d="M50 63l-4 10" stroke="#9fb3c8" stroke-width="0.6"/><path d="M66 63l-4 10" stroke="#9fb3c8" stroke-width="0.6"/><path d="M82 63l-4 10" stroke="#9fb3c8" stroke-width="0.6"/><path d="M98 63l-4 10" stroke="#9fb3c8" stroke-width="0.6"/><path d="M114 63l-4 10" stroke="#9fb3c8" stroke-width="0.6"/><path d="M130 63l-4 10" stroke="#9fb3c8" stroke-width="0.6"/><path d="M146 63l-4 10" stroke="#9fb3c8" stroke-width="0.6"/><path d="M162 63l-4 10" stroke="#9fb3c8" stroke-width="0.6"/><path d="M36 78H164L156 88H44z" fill="#1d3f73" stroke="#9fb3c8" stroke-width="1"/><path d="M58 78l-4 10" stroke="#9fb3c8" stroke-width="0.6"/><path d="M74 78l-4 10" stroke="#9fb3c8" stroke-width="0.6"/><path d="M90 78l-4 10" stroke="#9fb3c8" stroke-width="0.6"/><path d="M106 78l-4 10" stroke="#9fb3c8" stroke-width="0.6"/><path d="M122 78l-4 10" stroke="#9fb3c8" stroke-width="0.6"/><path d="M138 78l-4 10" stroke="#9fb3c8" stroke-width="0.6"/><path d="M154 78l-4 10" stroke="#9fb3c8" stroke-width="0.6"/><path d="M44 93H156L148 103H52z" fill="#1d3f73" stroke="#9fb3c8" stroke-width="1"/><path d="M66 93l-4 10" stroke="#9fb3c8" stroke-width="0.6"/><path d="M82 93l-4 10" stroke="#9fb3c8" stroke-width="0.6"/><path d="M98 93l-4 10" stroke="#9fb3c8" stroke-width="0.6"/><path d="M114 93l-4 10" stroke="#9fb3c8" stroke-width="0.6"/><path d="M130 93l-4 10" stroke="#9fb3c8" stroke-width="0.6"/><path d="M146 93l-4 10" stroke="#9fb3c8" stroke-width="0.6"/><path d="M84 64l8 8M92 64l-8 8M120 79l8 8M128 79l-8 8" stroke="#ff5252" stroke-width="2.4"/><g transform="translate(100 22)"><path d="M-8 -8L8 8M8 -8L-8 8" stroke="#fff" stroke-width="2.4"/><g fill="none" stroke="#fff" stroke-width="1.6"><circle cx="-8" cy="-8" r="4.5"/><circle cx="8" cy="-8" r="4.5"/><circle cx="-8" cy="8" r="4.5"/><circle cx="8" cy="8" r="4.5"/></g><rect x="-3" y="-3" width="6" height="6" fill="#9e9e9e"/></g><path d="M100 30L84 64H116z" fill="#4fc3f7" fill-opacity="0.2" stroke="#4fc3f7" stroke-width="1"/></svg>';
    case "op_sabic": return '<svg viewBox="0 0 200 110" xmlns="http://www.w3.org/2000/svg"><path d="M8 78H192M8 84H192" stroke="#b0bec5" stroke-width="2.5"/><path d="M20 84V104M60 84V104M100 84V104M140 84V104M180 84V104" stroke="#78909c" stroke-width="2"/><rect x="22" y="52" width="40" height="26" fill="#546e7a"/><rect x="70" y="40" width="11" height="38" rx="2" fill="#90a4ae"/><rect x="86" y="32" width="11" height="46" rx="2" fill="#90a4ae"/><circle cx="84" cy="58" r="27" fill="none" stroke="#ff5252" stroke-width="1.6" stroke-dasharray="4 3"/><path d="M156 104V24H164V104z" fill="#eceff1"/><path d="M156 24H164V34H156zM156 44H164V54H156z" fill="#e53935"/><path d="M160 24C153 16 158 10 160 4C163 10 167 16 160 24z" fill="#ff9800"/><path d="M160 22C157 18 159 14 160 11C161 14 163 18 160 22z" fill="#ffeb3b"/><path d="M122 30L110 76H134z" fill="#ff9800" fill-opacity="0.22" stroke="#ff9800" stroke-width="1"/><circle cx="122" cy="78" r="4.5" fill="#ffeb3b" stroke="#ff5722" stroke-width="2"/><g transform="translate(122 22)"><path d="M-8 -8L8 8M8 -8L-8 8" stroke="#fff" stroke-width="2.4"/><g fill="none" stroke="#fff" stroke-width="1.6"><circle cx="-8" cy="-8" r="4.5"/><circle cx="8" cy="-8" r="4.5"/><circle cx="-8" cy="8" r="4.5"/><circle cx="8" cy="8" r="4.5"/></g><rect x="-3" y="-3" width="6" height="6" fill="#9e9e9e"/></g></svg>';
    case "op_patrulla": return '<svg viewBox="0 0 200 110" xmlns="http://www.w3.org/2000/svg"><rect x="0" y="62" width="200" height="48" fill="#0d3b5c"/><path d="M10 74q8-4 16 0t16 0M120 70q8-4 16 0t16 0M150 98q8-4 16 0t16 0M14 100q8-4 16 0t16 0" fill="none" stroke="#4f8db8" stroke-width="1.4"/><path d="M70 86c4-10 26-14 42-10c14 3 22 8 14 15c-8 7-30 9-44 5c-10-3-14-5-12-10z" fill="#5d4e37" fill-opacity="0.85" stroke="#b39b6c" stroke-width="1.2"/><path d="M84 86c6-5 18-6 26-3c6 3 4 7-4 8c-9 1-20 0-22-5z" fill="#1e1a14"/><path d="M100 34L76 84H124z" fill="#4fc3f7" fill-opacity="0.18" stroke="#4fc3f7" stroke-width="1"/><circle cx="100" cy="86" r="5" fill="none" stroke="#ffeb3b" stroke-width="1.6"/><path d="M100 78v16M92 86h16" stroke="#ffeb3b" stroke-width="1"/><g transform="translate(100 22)" fill="#cfd8dc"><path d="M-44 -2H44V4H-44z"/><path d="M-3 -16H3V14H-3z"/><path d="M-13 -1H-10V20H-13zM10 -1H13V20H10z"/><path d="M-17 18H17V22H-17z"/><circle cx="0" cy="-14" r="2.4" fill="#37474f"/></g></svg>';
    case "op_carrera": return '<svg viewBox="0 0 200 110" xmlns="http://www.w3.org/2000/svg"><path d="M0 92H200V110H0z" fill="#5d4f3a"/><path d="M30 92V40H62V92" fill="none" stroke="#ff6d00" stroke-width="5"/><path d="M92 92V52H116V92" fill="none" stroke="#e53935" stroke-width="5"/><path d="M140 92V60H158V92" fill="none" stroke="#ff6d00" stroke-width="4"/><path d="M10 78C30 70 40 64 46 64C70 64 84 74 104 74C124 74 136 76 149 78C160 80 170 70 182 50" fill="none" stroke="#66bb6a" stroke-width="2.5" stroke-dasharray="6 4"/><g transform="translate(46 64)"><path d="M-9 -6L9 6M9 -6L-9 6" stroke="#fff" stroke-width="2.4"/><g fill="none" stroke="#fff" stroke-width="1.6"><circle cx="-9" cy="-6" r="4"/><circle cx="9" cy="-6" r="4"/><circle cx="-9" cy="6" r="4"/><circle cx="9" cy="6" r="4"/></g><rect x="-3" y="-3" width="6" height="6" fill="#e53935"/></g><path d="M182 92V22" stroke="#cfd8dc" stroke-width="2"/><path d="M182 22H198V34H182z" fill="#fff"/><path d="M182 22h4v4h-4zM190 22h4v4h-4zM186 26h4v4h-4zM194 26h4v4h-4zM182 30h4v4h-4zM190 30h4v4h-4z" fill="#000"/><g fill="#fff" font-size="11" font-weight="700"></g></svg>';
    case "op_video": return '<svg viewBox="0 0 200 110" xmlns="http://www.w3.org/2000/svg"><path d="M94 100L97 30H103L106 100z" fill="#cfd8dc"/><rect x="95" y="22" width="10" height="9" fill="#ffd54f"/><path d="M93 22H107L100 14z" fill="#b71c1c"/><ellipse cx="100" cy="60" rx="70" ry="22" fill="none" stroke="#ffc83d" stroke-width="2" stroke-dasharray="6 4"/><path d="M168 64l4 -8 4 8" fill="none" stroke="#ffc83d" stroke-width="2"/><circle cx="45" cy="74" r="4" fill="#e53935"/><g transform="translate(45 74) rotate(0) scale(0.8)"><path d="M-8 -8L8 8M8 -8L-8 8" stroke="#fff" stroke-width="2.4"/><g fill="none" stroke="#fff" stroke-width="1.6"><circle cx="-8" cy="-8" r="4.5"/><circle cx="8" cy="-8" r="4.5"/><circle cx="-8" cy="8" r="4.5"/><circle cx="8" cy="8" r="4.5"/></g><rect x="-3" y="-3" width="6" height="6" fill="#9e9e9e"/></g></svg>';
    case "fpv_estacionario": return '<svg viewBox="0 0 200 110" xmlns="http://www.w3.org/2000/svg"><rect x="91" y="91" width="18" height="10" fill="#2b2b2b" stroke="#ff6d00" stroke-width="1.5"/><path d="M96 93V99M104 93V99M96 96H104" stroke="#fff" stroke-width="1.2"/><g fill="none" stroke="#4fc3f7" stroke-width="1.6"><ellipse cx="100" cy="30" rx="34" ry="8"/><ellipse cx="100" cy="74" rx="34" ry="8"/><path d="M66 30V74M134 30V74"/></g><g transform="translate(100 52) rotate(0)"><path d="M-8 -8L8 8M8 -8L-8 8" stroke="#fff" stroke-width="2.4"/><g fill="none" stroke="#fff" stroke-width="1.6"><circle cx="-8" cy="-8" r="4.5"/><circle cx="8" cy="-8" r="4.5"/><circle cx="-8" cy="8" r="4.5"/><circle cx="8" cy="8" r="4.5"/></g><path d="M0 -4L3 1H-3z" fill="#ffc83d"/></g><path d="M150 80V24" stroke="#ffc83d" stroke-width="1.5"/><path d="M146 28L150 22 154 28M146 76L150 82 154 76" fill="none" stroke="#ffc83d" stroke-width="1.5"/><text x="156" y="56" fill="#fff" font-size="10">20 s</text></svg>';
    case "fpv_caja": return '<svg viewBox="0 0 200 110" xmlns="http://www.w3.org/2000/svg"><rect x="55" y="25" width="90" height="60" fill="none" stroke="#ffc83d" stroke-width="2" stroke-dasharray="6 4"/><path d="M55 19L60 31H50z" fill="#4caf50" stroke="#000" stroke-width="0.8"/><path d="M55 79L60 91H50z" fill="#ffeb3b" stroke="#000" stroke-width="0.8"/><path d="M145 79L150 91H140z" fill="#f44336" stroke="#000" stroke-width="0.8"/><path d="M145 19L150 31H140z" fill="#42a5f5" stroke="#000" stroke-width="0.8"/><g transform="translate(100 55) rotate(180)"><path d="M-8 -8L8 8M8 -8L-8 8" stroke="#fff" stroke-width="2.4"/><g fill="none" stroke="#fff" stroke-width="1.6"><circle cx="-8" cy="-8" r="4.5"/><circle cx="8" cy="-8" r="4.5"/><circle cx="-8" cy="8" r="4.5"/><circle cx="8" cy="8" r="4.5"/></g><path d="M0 -4L3 1H-3z" fill="#ffc83d"/></g></svg>';
    case "fpv_slalom": return '<svg viewBox="0 0 200 110" xmlns="http://www.w3.org/2000/svg"><path d="M30 56V80" stroke="#e53935" stroke-width="3"/><path d="M30 56V80" stroke="#fff" stroke-width="3" stroke-dasharray="4 4"/><path d="M52 56V80" stroke="#e53935" stroke-width="3"/><path d="M52 56V80" stroke="#fff" stroke-width="3" stroke-dasharray="4 4"/><path d="M74 56V80" stroke="#e53935" stroke-width="3"/><path d="M74 56V80" stroke="#fff" stroke-width="3" stroke-dasharray="4 4"/><path d="M96 56V80" stroke="#e53935" stroke-width="3"/><path d="M96 56V80" stroke="#fff" stroke-width="3" stroke-dasharray="4 4"/><path d="M118 56V80" stroke="#e53935" stroke-width="3"/><path d="M118 56V80" stroke="#fff" stroke-width="3" stroke-dasharray="4 4"/><path d="M15 66 C25 50 35 50 41 66 S57 82 63 66 S79 50 85 66 S101 82 107 66 S123 50 129 66" fill="none" stroke="#ffc83d" stroke-width="2" stroke-dasharray="5 3"/><path d="M158 26V50" stroke="#f44336" stroke-width="3"/><path d="M158 26V50" stroke="#fff" stroke-width="3" stroke-dasharray="4 4"/><path d="M182 26V50" stroke="#42a5f5" stroke-width="3"/><path d="M182 26V50" stroke="#fff" stroke-width="3" stroke-dasharray="4 4"/><path d="M170 38 C160 18 146 22 150 38 C154 54 186 22 190 38 C194 54 180 58 170 38" fill="none" stroke="#ffc83d" stroke-width="1.8"/><g transform="translate(129 66) rotate(0)"><path d="M-8 -8L8 8M8 -8L-8 8" stroke="#fff" stroke-width="2.4"/><g fill="none" stroke="#fff" stroke-width="1.6"><circle cx="-8" cy="-8" r="4.5"/><circle cx="8" cy="-8" r="4.5"/><circle cx="-8" cy="8" r="4.5"/><circle cx="8" cy="8" r="4.5"/></g><path d="M0 -4L3 1H-3z" fill="#ffc83d"/></g></svg>';
    case "fpv_circuito": return '<svg viewBox="0 0 200 110" xmlns="http://www.w3.org/2000/svg"><path d="M40 30 C20 55 30 90 70 92 L140 92 C180 90 185 55 165 32 C150 15 60 12 40 30z" fill="none" stroke="#ffc83d" stroke-width="2" stroke-dasharray="6 4"/><path d="M31 40V22H49V40" fill="none" stroke="#ff6d00" stroke-width="2.6"/><text x="37" y="19" fill="#fff" font-size="9" font-weight="700">1</text><path d="M36 88V70H54V88" fill="none" stroke="#ff6d00" stroke-width="2.6"/><text x="42" y="67" fill="#fff" font-size="9" font-weight="700">2</text><path d="M96 100V82H114V100" fill="none" stroke="#ff6d00" stroke-width="2.6"/><text x="102" y="79" fill="#fff" font-size="9" font-weight="700">3</text><path d="M156 88V70H174V88" fill="none" stroke="#ff6d00" stroke-width="2.6"/><text x="162" y="67" fill="#fff" font-size="9" font-weight="700">4</text><path d="M163 45V27H181V45" fill="none" stroke="#ff6d00" stroke-width="2.6"/><text x="169" y="24" fill="#fff" font-size="9" font-weight="700">5</text><path d="M96 26V8H114V26" fill="none" stroke="#ff6d00" stroke-width="2.6"/><text x="102" y="5" fill="#fff" font-size="9" font-weight="700">6</text><g transform="translate(75 25) rotate(-100)"><path d="M-8 -8L8 8M8 -8L-8 8" stroke="#fff" stroke-width="2.4"/><g fill="none" stroke="#fff" stroke-width="1.6"><circle cx="-8" cy="-8" r="4.5"/><circle cx="8" cy="-8" r="4.5"/><circle cx="-8" cy="8" r="4.5"/><circle cx="8" cy="8" r="4.5"/></g><path d="M0 -4L3 1H-3z" fill="#ffc83d"/></g></svg>';
    case "fpv_acro": return '<svg viewBox="0 0 200 110" xmlns="http://www.w3.org/2000/svg"><rect x="20" y="70" width="160" height="14" fill="#8d6e63" rx="2"/><path d="M15 55 H185" stroke="#ffc83d" stroke-width="2" stroke-dasharray="6 4"/><path d="M178 51l7 4-7 4" fill="#ffc83d"/><g transform="translate(90 55) rotate(0)"><path d="M-8 -8L8 8M8 -8L-8 8" stroke="#fff" stroke-width="2.4"/><g fill="none" stroke="#fff" stroke-width="1.6"><circle cx="-8" cy="-8" r="4.5"/><circle cx="8" cy="-8" r="4.5"/><circle cx="-8" cy="8" r="4.5"/><circle cx="8" cy="8" r="4.5"/></g><path d="M0 -4L3 1H-3z" fill="#ffc83d"/></g><path d="M90 55 L118 40" stroke="#4fc3f7" stroke-width="1.5"/><text x="122" y="40" fill="#4fc3f7" font-size="10" font-weight="700">ACRO</text><path d="M20 84L25 96H15z" fill="#ff6d00" stroke="#000" stroke-width="0.8"/><path d="M180 84L185 96H175z" fill="#ff6d00" stroke="#000" stroke-width="0.8"/></svg>';
    case "fpv_tecnica": return '<svg viewBox="0 0 200 110" xmlns="http://www.w3.org/2000/svg"><path d="M58 100V38H86V100" fill="none" stroke="#d81b60" stroke-width="3"/><path d="M58 70H86" stroke="#d81b60" stroke-width="3"/><path d="M30 56 H72 C112 56 112 12 72 12 C40 12 40 56 72 56" fill="none" stroke="#ffc83d" stroke-width="2" stroke-dasharray="5 3"/><g stroke="#b8bcc0" stroke-width="2"><path d="M150 100V20M168 100V20"/><path d="M150 40H168M150 60H168M150 80H168M150 20H168"/></g><circle cx="159" cy="15" r="3.5" fill="#ff1744"/><path d="M176 22 C186 50 184 80 178 98" fill="none" stroke="#ffc83d" stroke-width="2" stroke-dasharray="5 3"/><path d="M174 92l4 7 4-7" fill="none" stroke="#ffc83d" stroke-width="2"/><g transform="translate(30 56) rotate(90)"><path d="M-8 -8L8 8M8 -8L-8 8" stroke="#fff" stroke-width="2.4"/><g fill="none" stroke="#fff" stroke-width="1.6"><circle cx="-8" cy="-8" r="4.5"/><circle cx="8" cy="-8" r="4.5"/><circle cx="-8" cy="8" r="4.5"/><circle cx="8" cy="8" r="4.5"/></g><path d="M0 -4L3 1H-3z" fill="#ffc83d"/></g></svg>';
    case "campo": return ini + pista(96, 25, 8, 55) + pil(70, 30, P[0]) + pil(130, 30, P[1]) + pil(130, 75, P[2]) + pil(70, 75, P[3]) +
      `<circle cx="100" cy="95" r="4" fill="#fff"/><text x="108" y="98" fill="#fff" font-size="9">piloto</text>` + avion(150, 50, -30) + fin;
  }
  return ini + avion(100, 55, 0) + fin;
}

// ---- vuelo libre: sitio y condiciones ----
let sitioSel = "libre";
function irVolar() {
  vehiculoPermitido();
  document.getElementById("sitioCampoImg").innerHTML = iconoMision("campo");
  document.getElementById("sitioCampo").classList.toggle("sel", sitioSel === "libre");
  document.getElementById("sitioCartagena").classList.toggle("sel", sitioSel === "libre_cartagena");
  document.getElementById("volarNota").textContent = sitioSel === "libre"
    ? "Lanzas desde el aparcamiento, de cara al norte; la pista va hacia delante. En vuelo, + y − cambian el viento y G las rachas."
    : "El siguiente paso es el mapa: eliges dónde lanzar y se despega hacia el lado más despejado. En la zona de detalle hay ortofoto a 0,5 m, edificios y árboles reales.";
  document.getElementById("btnVolarYa").textContent = sitioSel === "libre" ? "Volar →" : "Elegir el punto de lanzamiento →";
  montarCondiciones("condicionesSlotVolar", null);
  mostrar("pVolar");
}
document.getElementById("sitioCampo").onclick = () => { sitioSel = "libre"; irVolar(); };
document.getElementById("sitioCartagena").onclick = () => { sitioSel = "libre_cartagena"; irVolar(); };
document.getElementById("btnVolarVolver").onclick = irInicio;
document.getElementById("btnVolarYa").onclick = () => { leerViento(); sesion.escenario = sitioSel; if (sitioSel === "libre_cartagena") irLanzamiento(); else empezar(); };

// ---- ajustes ----
function irAjustes(seccion) {
  pintarMandoCfg(); pintarDificultad(); pintarCalidad(); pintarZoomPiloto(); pintarSonidoCfg();
  document.getElementById("datosAula").textContent = sesion.alumno
    ? `Conectado al aula «${sesion.nombreAula}» (${urlAula()}) como ${sesion.alumno.nombre}: los vuelos y el progreso se guardan en el servidor.`
    : "Sin conexión: se vuela igual, pero los vuelos y el progreso no se guardan.";
  if (seccion) seleccionarAjuste(seccion);
  mostrar("pAjustes");
}
function seleccionarAjuste(a) {
  document.querySelectorAll("#ajustesMenu button").forEach(b => b.classList.toggle("sel", b.dataset.a === a));
  document.querySelectorAll("#pAjustes .panelPestana").forEach(p => p.classList.toggle("sel", p.dataset.a === a));
}
document.querySelectorAll("#ajustesMenu button").forEach(b => b.onclick = () => seleccionarAjuste(b.dataset.a));
document.getElementById("btnAjustesVolver").onclick = irInicio;
document.getElementById("btnDatosAcceso").onclick = () => irAcceso();
document.getElementById("btnDatosProfesor").onclick = () => { if (urlAula()) window.open(urlAula() + "/profesor.html", "_blank"); else toast("Primero escribe la dirección del servidor del aula"); };
// calidad grafica: automatica (baja sola si no llega a 35 fps) o fija
function pintarCalidad() {
  let m = "auto"; try { m = localStorage.getItem("sim_calidad_modo") || "auto"; } catch (e) {}
  document.getElementById("calidad").value = m;
  document.getElementById("calidadInfo").textContent = `Ahora: ${visor.minimo ? "rendimiento máximo" : ["baja", "media", "alta"][visor.calidad]}${m === "auto" ? " (automática" + (visor.minimo ? ": tableta o móvil)" : ")") : ""}. La alta necesita una tarjeta gráfica decente; si el vuelo va a tirones, baja un nivel. Con «Rendimiento máximo» (y al quitarlo) la página se recarga.`;
}
// zoom de la camara del piloto: fraccion del alto de la pantalla que ocupa la envergadura (0 = sin zoom)
try {
  const z = localStorage.getItem("sim_zoom_piloto"); if (z !== null && isFinite(+z)) visor.zoomPiloto = +z;
  if (localStorage.getItem("sim_zoom_v") !== "2") { visor.zoomPiloto = 0.03; localStorage.setItem("sim_zoom_piloto", "0.03"); localStorage.setItem("sim_zoom_v", "2"); }   // nuevo por defecto: 3 %
} catch (e) {}
function pintarZoomPiloto() {
  const z = visor.zoomPiloto === undefined ? 0.03 : visor.zoomPiloto, sel = document.getElementById("zoomPiloto");
  const op = [...sel.options].find(o => o.value !== "otro" && Math.abs(+o.value - z) < 0.004);
  sel.value = op ? op.value : "otro";
  sel.querySelector('option[value="otro"]').textContent = `Ajustado con la rueda del ratón: un ${(z * 100).toFixed(0)} % de la pantalla`;
}
function ponerZoomPiloto(z) { visor.zoomPiloto = z; try { localStorage.setItem("sim_zoom_piloto", String(z)); } catch (e) {} pintarZoomPiloto(); }
document.getElementById("zoomPiloto").addEventListener("change", e => { if (e.target.value !== "otro") ponerZoomPiloto(+e.target.value); });
// en vuelo, con la camara del piloto, la rueda del raton cambia el zoom (fuera del GPS, que tiene su propia rueda)
window.addEventListener("wheel", e => {
  if (pantallaActual !== null || visor.camara !== 1 || e.target.closest && e.target.closest("#gps")) return;
  const z0 = visor.zoomPiloto === undefined ? 0.03 : visor.zoomPiloto;
  const z = Math.max(0, Math.min(0.3, z0 > 0 ? z0 * (e.deltaY > 0 ? 0.85 : 1 / 0.85) : (e.deltaY < 0 ? 0.03 : 0)));
  ponerZoomPiloto(z < 0.025 && e.deltaY > 0 ? 0 : +z.toFixed(3));
  toast(visor.zoomPiloto > 0 ? `Zoom del piloto: el avión ocupa un ${(visor.zoomPiloto * 100).toFixed(0)} % de la pantalla` : "Sin zoom: como lo ve el ojo");
}, { passive: true });
function aplicarModoCalidad(m) {
  if ((m === "min" || (m === "auto" && Visor.esTableta())) !== visor.minimo) { location.reload(); return; }   // rendimiento maximo: los materiales del mundo se rehacen al cargar
  if (m === "auto") { visor.calidadFija = false; visor.aplicarCalidad(visor.minimo ? 0 : 2); }
  else { visor.calidadFija = true; visor.aplicarCalidad(m === "min" ? 0 : +m); }
}
document.getElementById("calidad").addEventListener("change", e => { const m = e.target.value; try { localStorage.setItem("sim_calidad_modo", m); } catch (er) {} aplicarModoCalidad(m); pintarCalidad(); });
