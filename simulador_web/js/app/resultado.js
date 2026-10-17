// Resultado y guardado del vuelo, progreso del piloto y caja negra (CSV a 20 Hz).
// Parte de la aplicacion de simulador_web/simulador.html: los modulos de js/app/ se cargan en orden y comparten el
// ambito global. En Godot: simulador_godot/scripts/app/resultado.gd.
"use strict";
// =====================================================================
//  4. RESULTADO Y GUARDADO
// =====================================================================
/** Entrenamiento del FPV que se vuela con las gafas (solo cuenta la camara 3). */
const conGafas = () => { const F = ESCENARIOS[sesion.escenario].pista_fpv; return !!(F && F.camara === "gafas" && modelo.esFPV); };
const camaraValida = () => !!ESCENARIOS[sesion.escenario].operacion || (conGafas() ? visor.camara === 3 : visor.camara === 1 || (!!modelo.esCuadricoptero && visor.camara === 3));   // en las operaciones vale cualquier camara
/** Texto de la pista FPV con los conos de colores: {cono:i} -> el pilon de color i (HTML o solo el nombre). */
const textoFpv = (s, html) => s.replace(/\{cono:(\d)\}/g, (_, i) => html ? pilonHTML(+i, true) : entorno.circuito.colores[+i].nombre);
/** Objetivos y veredicto de un vuelo (lo que se guarda). Ademas de los objetivos, la camara: solo cuenta visto desde el piloto. */
function datosResultado(v) {
  const E = ESCENARIOS[v.escenario], libre = !E.objetivos.length;
  const objs = Object.entries(ev.obj).map(([id, o]) => ({ id, texto: o.texto, ok: o.estado === "ok" }));
  if (!libre && !E.operacion) objs.push({ id: "camara", texto: conGafas() ? "Volar con las gafas FPV (cámara 3)" : modelo.esFPV ? "Volar mirando al dron o con las gafas FPV (cámaras 1 o 3)" : modelo.esCuadricoptero ? "Volar mirando al dron o la pantalla de la app (cámaras 1 o 3)" : "Volar desde el puesto del piloto (cámara 1)", ok: !v.otraCamara });
  const apto = !libre && v.final === "aterrizado" && objs.every(o => o.ok);
  return { E, libre, objs, apto, resultado: libre ? "LIBRE" : apto ? "APTO" : "NO APTO" };
}
async function guardarVuelo(v, d) {
  if (!sesion.alumno || v.guardado) return { estado: "sin_aula" };
  v.guardado = true;
  return enviarVuelo({ id: v.id, alumno_id: sesion.alumno.id, inicio: v.inicio.toISOString(), fin: new Date().toISOString(),
    avion: modelo.nombre, escenario: v.escenario, tiempo_vuelo_s: +v.tVuelo.toFixed(1),
    accidentes: v.final.startsWith("roto") ? 1 : 0, aterrizajes: v.final === "aterrizado" ? 1 : 0,
    objetivos: d.objs, resultado: d.resultado, final: v.final, marca: v.marca !== undefined ? +v.marca.toFixed(2) : null,
    viento: Object.assign({}, d.E.viento || sesion.viento, cmEsDiseno(sesion.avion) ? {} : { cg_pct: cmActual(sesion.avion).cg, masa_g: cmActual(sesion.avion).masa },
                         v.dificultad === "facil" ? { fisica: "facil" } : {}) });
}
async function mostrarResultado(v) {
  if (v.mostrado) { mostrar("pResultado"); return; }
  v.mostrado = true;
  const { E, libre, objs, apto, resultado } = datosResultado(v);
  document.getElementById("resTitulo").textContent = E.nombre;
  const ver = document.getElementById("resVeredicto");
  ver.textContent = libre ? "Vuelo libre" : resultado; ver.className = "grande " + (libre ? "libre" : apto ? "apto" : "noapto");
  const fin = v.lanzamiento ? `Lanzamiento fallido${v.final.startsWith("roto") ? " (se ha roto)" : ""}: ${v.lanzamiento.texto}`
    : v.final === "aparcado" ? `Bípode aparcado · ${juegoBip ? juegoBip.derribados : 0} drones derribados`
    : v.final === "aterrizado" ? "Aterrizaje correcto" : v.final.startsWith("roto") ? "Accidente: " + v.final.slice(6, -1)
    : v.final === "fuera de límites" ? `Fuera de límites: a más de ${entorno.limites.distancia_m} m el avión ya no se ve` : "Vuelo terminado sin aterrizar";
  document.getElementById("resFinal").textContent = `${fin} · tiempo de vuelo ${(v.tVuelo / 60).toFixed(1)} min` + (E.mundo ? "" : " · " + textoVueltas().replace(/<[^>]+>/g, ""));
  document.getElementById("resObjetivos").innerHTML = objs.length
    ? objs.map(o => `<tr><td class="${o.ok ? "ob-ok" : "ob-mal"}">${o.ok ? "✔" : "✘"}</td><td>${esc(o.texto)}</td></tr>`).join("")
    : `<tr><td>Sin objetivos: el tiempo cuenta para las horas de entrenamiento.</td></tr>`;
  document.getElementById("btnResProgreso").style.display = sesion.alumno ? "" : "none";
  document.getElementById("btnOtroEscenario").textContent = libre ? "Otro vuelo" : "Otro entrenamiento";
  pintarResumen(v);
  const g = document.getElementById("resGuardado");
  mostrar("pResultado");
  if (!sesion.alumno) { g.textContent = "Sin conexión con el aula: este vuelo no se ha guardado."; return; }
  g.textContent = "Guardando…";
  const r = await guardarVuelo(v, { E, objs, resultado });
  if (r.estado === "ok") {
    g.textContent = "✔ Guardado en el registro del aula.";
    const antes = sesion.alumno.progreso; sesion.alumno.progreso = r.progreso;
    const nuevos = logrosNuevos(antes, r.progreso);
    if (nuevos.length) { g.textContent += " " + nuevos.join(" · "); toast(nuevos[nuevos.length - 1]); }
  }
  else if (r.estado === "cola") g.textContent = "Sin conexión con el aula: se guardará solo en cuanto vuelva (no se perderá).";
  else g.textContent = "No se pudo guardar: " + (r.msg || "");
}
document.getElementById("btnRepetir").onclick = empezar;
document.getElementById("btnOtroEscenario").onclick = () => ESCENARIOS[sesion.escenario].objetivos.length ? irEntrenamientos() : irVolar();
document.getElementById("btnResProgreso").onclick = () => irProgreso("pResultado");
document.getElementById("btnResInicio").onclick = e => irInicio(e);
document.getElementById("btnRepeticion").onclick = () => verRepeticion(ultimoVuelo);

// =====================================================================
//  5. PROGRESO
// =====================================================================
let volverDesde = "pAvion";
async function irProgreso(desde, al = sesion.alumno) {
  volverDesde = desde;
  document.getElementById("btnCerrarSesion").style.display = desde === "pInicio" ? "" : "none";
  const el = document.getElementById("progContenido");
  document.getElementById("progNombre").textContent = al.nombre;
  el.innerHTML = '<p class="sub">Cargando…</p>'; mostrar("pProgreso");
  let a;
  try { a = await api("GET", "alumnos/" + al.id); al.progreso = a.progreso; }
  catch (e) { el.innerHTML = `<p class="err">No se pudo leer el progreso: ${esc(e.message)}</p>`; return; }
  const g = a.progreso, pct = Math.min(100, 100 * g.horas / g.horas_minimas), faltan = [];
  if (g.horas < g.horas_minimas) faltan.push(`${fmtHoras(g.horas_minimas - g.horas)} de vuelo`);
  const nomEsc = k => (ESCENARIOS[k] || { nombre: k }).nombre, cert = g.certificado || "Certificado de pilotaje", total = g.escenarios_total ?? Object.keys(g.escenarios).length;
  const pend = Object.entries(g.escenarios).filter(([, s]) => !s.superado).map(([k]) => nomEsc(k).replace(/^\d · /, ""));
  if (pend.length) faltan.push("superar " + pend.join(", "));
  const estado = a.habilitado ? `<span class="chip ok">CONCEDIDO</span> ${esc(cert)} desde ${fmtFecha(a.habilitado_en)}.`
    : g.requisitos_cumplidos ? `<span class="chip">Requisitos cumplidos</span> Pide al profesor que te conceda el certificado.`
    : `<span class="chip mal">Todavía no</span> Te falta: ${faltan.join(" y ")}.`;
  el.innerHTML = `
    <div class="estadisticas">
      <div><b>${fmtHoras(g.horas)}</b><span>horas de vuelo</span></div><div><b>${g.vuelos}</b><span>vuelos</span></div>
      <div><b>${g.aterrizajes}</b><span>aterrizajes</span></div><div><b>${g.accidentes}</b><span>accidentes</span></div>
      <div><b>${g.escenarios_superados}/${total}</b><span>pruebas superadas</span></div></div>
    <h2>Logros</h2>${htmlLogros(g)}
    <h2>Carrera de drones del Politécnico</h2>
    <div class="tarjeta"><div class="fila" style="margin-top:0">${g.carrera ? `🏁 Tu mejor tiempo: <b style="font-size:20px">${opCrono(g.carrera.mejor)}</b>&nbsp; con ${esc(g.carrera.avion || "")}, el ${esc(fmtFecha(g.carrera.fecha))}` : "🏁 Todavía no has terminado la carrera (Operaciones → Carrera de drones del Politécnico)."}</div></div>
    <h2>Camino al certificado: ${esc(cert)}</h2>
    <div class="tarjeta"><div class="fila" style="margin-top:0"><b>${fmtHoras(g.horas)} de ${g.horas_minimas} h mínimas</b></div>
      <div class="progreso"><i style="width:${pct}%"></i></div>
      <table class="datos" style="margin-top:12px">${Object.entries(g.escenarios).map(([k, s]) =>
        `<tr><td class="${s.superado ? "ob-ok" : "ob-pend"}">${s.superado ? "✔" : "○"}</td><td>${esc(nomEsc(k))}</td><td>${s.intentos} intentos</td></tr>`).join("")}</table>
      <p style="margin:12px 0 0">${estado}</p></div>
    <h2>Historial</h2>
    <div class="tarjeta" style="overflow-x:auto"><table class="datos"><tr><th>Fecha</th><th>Avión</th><th>Entrenamiento</th><th>Tiempo</th><th>Objetivos</th><th>Final</th><th>Resultado</th></tr>
      ${a.vuelos.length ? a.vuelos.map(v => `<tr><td>${fmtFecha(v.inicio)}</td><td>${esc(v.avion)}</td><td>${esc(v.escenario_nombre)}</td>
        <td>${(+v.tiempo_vuelo_s / 60).toFixed(1)} min</td><td>${Array.isArray(v.objetivos) && v.objetivos.length ? v.objetivos.filter(o => o && o.ok).length + "/" + v.objetivos.length : "—"}</td>
        <td>${esc(v.final || "")}</td><td class="${v.resultado === "APTO" ? "ob-ok" : v.resultado === "NO APTO" ? "ob-mal" : ""}">${v.resultado}</td></tr>`).join("")
        : '<tr><td colspan="7">Todavía no hay vuelos.</td></tr>'}</table></div>`;
}
/** Insignia de un logro (ala_fija, dron, operaciones o robot), en color si esta conseguido y en gris si no; el robot
 *  bloqueado lleva un candado. El mismo SVG que PantallaResultado.insignia de Godot. */
function insigniaSvg(id, ok) {
  const COL = { ala_fija: ["#1e88e5", "#1565c0"], dron: ["#43a047", "#2e7d32"], operaciones: ["#ef6c00", "#bf360c"], robot: ["#8e24aa", "#5e35b1"] };
  const [c1, c2] = ok ? COL[id] : ["#38424d", "#29313a"], b = ok ? "#ffd54f" : "#5d6875", s = ok ? "#ffffff" : "#8a96a3";
  const forma = {
    ala_fija: `<circle cx="60" cy="50" r="42" fill="${c1}" stroke="${b}" stroke-width="5"/><circle cx="60" cy="50" r="33" fill="none" stroke="${b}" stroke-opacity="0.6" stroke-width="1.5"/>`,
    dron: `<path d="M60 6L98 28L98 72L60 94L22 72L22 28z" fill="${c1}" stroke="${b}" stroke-width="5"/><path d="M60 16L89 33L89 67L60 84L31 67L31 33z" fill="none" stroke="${b}" stroke-opacity="0.6" stroke-width="1.5"/>`,
    operaciones: `<path d="M60 6L98 18V48C98 72 81 88 60 96C39 88 22 72 22 48V18z" fill="${c1}" stroke="${b}" stroke-width="5"/><path d="M60 15L90 25V48C90 67 77 80 60 87C43 80 30 67 30 48V25z" fill="none" stroke="${b}" stroke-opacity="0.6" stroke-width="1.5"/>`,
    robot: `<path d="M60 4L68 19L84 13L82 30L98 34L87 46L98 58L82 62L84 79L68 73L60 88L52 73L36 79L38 62L22 58L33 46L22 34L38 30L36 13L52 19z" fill="${c1}" stroke="${b}" stroke-width="4" stroke-linejoin="round"/><circle cx="60" cy="46" r="28" fill="none" stroke="${b}" stroke-opacity="0.6" stroke-width="1.5"/>`,
  }[id];
  const simbolo = {
    ala_fija: `<path d="M60 22L64 40L86 48V54L64 50L63 66L71 72V76L60 73L49 76V72L57 66L56 50L34 54V48L56 40z" fill="${s}"/>`,
    dron: `<path d="M44 34L76 66M76 34L44 66" stroke="${s}" stroke-width="4" stroke-linecap="round"/><g fill="none" stroke="${s}" stroke-width="3"><circle cx="44" cy="34" r="9"/><circle cx="76" cy="34" r="9"/><circle cx="44" cy="66" r="9"/><circle cx="76" cy="66" r="9"/></g><rect x="53" y="43" width="14" height="14" rx="3" fill="${s}"/>`,
    operaciones: `<circle cx="60" cy="48" r="17" fill="none" stroke="${s}" stroke-width="4"/><path d="M60 22V36M60 60V74M34 48H48M72 48H86" stroke="${s}" stroke-width="4" stroke-linecap="round"/><circle cx="60" cy="48" r="5" fill="${s}"/>`,
    robot: ok ? `<rect x="45" y="27" width="30" height="19" rx="4" fill="${s}"/><rect x="62" y="32" width="9" height="5" fill="${c1}"/><path d="M45 33H36" stroke="${s}" stroke-width="4" stroke-linecap="round"/><path d="M52 46L46 57L51 68M68 46L74 57L69 68" fill="none" stroke="${s}" stroke-width="5" stroke-linecap="round" stroke-linejoin="round"/><path d="M45 68H56M64 68H75" stroke="${s}" stroke-width="4" stroke-linecap="round"/>`
      : `<path d="M50 36C50 26 70 26 70 36C70 44 60 44 60 52V55" fill="none" stroke="${s}" stroke-width="6" stroke-linecap="round"/><circle cx="60" cy="66" r="4" fill="${s}"/>`,     // bloqueado: un misterio
  }[id];
  const cintas = `<path d="M40 74L30 114L45 106L53 118L60 84z" fill="${c2}"/><path d="M80 74L90 114L75 106L67 118L60 84z" fill="${c2}"/>`;
  const candado = id === "robot" && !ok ? `<g transform="translate(86 84)"><path d="M-6 -6V-11A6 6 0 0 1 6 -11V-6" fill="none" stroke="#ffd54f" stroke-width="3.5"/><rect x="-11" y="-6" width="22" height="18" rx="3" fill="#ffd54f"/><circle cx="0" cy="3" r="3" fill="#29313a"/></g>` : "";
  return `<svg viewBox="0 0 120 120" xmlns="http://www.w3.org/2000/svg">${cintas}${forma}${simbolo}${candado}</svg>`;
}
/** Nombre corto de un escenario (sin el "1 · " de los entrenamientos del certificado). */
function nombreCorto(k) { return ((ESCENARIOS[k] || { nombre: k }).nombre).replace(/^\d · /, ""); }
/** Las tarjetas de los tres logros y la del robot (Mi progreso). */
function htmlLogros(g) {
  const L = g.logros || [], barra = (a, b) => `<div class="progreso"><i style="width:${Math.min(100, b ? 100 * a / b : 0)}%"></i></div>`;
  const tarjeta = x => `<div class="logro${x.ok ? " ok" : ""}"><div class="ins">${insigniaSvg(x.id, x.ok)}</div><h3>${esc(x.nombre)}</h3><p>${esc(x.desc)}</p>` +
    (x.horas_meta !== undefined ? `<div class="lin"><span>Horas de vuelo</span><b>${fmtHoras(Math.min(x.horas, x.horas_meta))} de ${x.horas_meta} h</b></div>${barra(x.horas, x.horas_meta)}` : "") +
    `<div class="lin"><span>${x.id === "operaciones" ? "Operaciones" : "Entrenamientos"}</span><b>${x.hechas} de ${x.total}</b></div>${barra(x.hechas, x.total)}` +
    (x.ok ? `<div class="estado" style="color:#ffd54f">✔ Conseguido</div>` : x.pendientes.length ? `<div class="falta">Te falta: ${esc(x.pendientes.map(nombreCorto).join(", "))}</div>` : "") + `</div>`;
  const n = L.filter(x => x.ok).length;                     // el robot, sin decir que es: un misterio hasta desbloquearlo
  return `<div class="logros">${L.map(tarjeta).join("")}<div class="logro${g.robot ? " ok" : ""}"><div class="ins">${insigniaSvg("robot", !!g.robot)}</div><h3>Vehículo secreto</h3>` +
    `<p>${g.robot ? "Desbloqueado: te espera en el Hangar." : "¿Qué se esconde en el Hangar? Consigue los tres logros para descubrirlo."}</p><div class="lin"><span>Logros</span><b>${n} de ${L.length}</b></div>${barra(n, L.length)}` +
    (g.robot ? `<div class="estado" style="color:#ffd54f">✔ Desbloqueado</div>` : "") + `</div></div>`;
}
/** Los avisos de lo conseguido con el ultimo vuelo (logros y el robot). */
function logrosNuevos(antes, ahora) {
  const ya = new Set(((antes && antes.logros) || []).filter(x => x.ok).map(x => x.id)), T = [];
  for (const x of (ahora && ahora.logros) || []) if (x.ok && !ya.has(x.id)) T.push(`🏅 ¡Logro conseguido: ${x.nombre}!`);
  if (ahora && ahora.robot && !(antes && antes.robot)) T.push("🔓 ¡Vehículo secreto desbloqueado! Te espera en el Hangar");
  return T;
}
document.getElementById("btnProgVolver").onclick = () => volverDesde === "pResultado" ? mostrar("pResultado") : volverDesde === "pInicio" ? irInicio() : irHangar();

// =====================================================================
//  CAJA NEGRA (CSV de cada vuelo, a 20 Hz)
// =====================================================================
const DT = 1 / 500, CN_CADA = 25;
const CN_COLUMNAS = ["t_s", "x_norte_m", "y_este_m", "z_altura_m", "vel_aire_ms", "vel_suelo_ms", "vel_vertical_ms",
  "alabeo_grados", "cabeceo_grados", "rumbo_grados", "alfa_grados", "resbale_grados", "carga_g",
  "gases_pct", "motor_rpm", "empuje_N", "energia_Wh", "bateria_pct", "palanca_profundidad", "palanca_timon",
  "compensador_grados", "profundidad_grados", "timon_grados", "aleron_grados", "viento_norte_ms", "viento_este_ms", "perdida"];
let cnContador = 0, ultimoVuelo = null;
function grabarMuestra() {
  if (!vuelo) return;
  const [roll, pitch, yaw] = Cuat.euler(av.q).map(a => a * R2D), vn = Cuat.rot(av.q, av.v), r = (x, n) => +(+x).toFixed(n), w = entorno.viento.actual;
  vuelo.filas.push([r(av.t, 2), r(av.p[0], 2), r(av.p[1], 2), r(-av.p[2], 2), r(av.V, 2), r(Math.hypot(vn[0], vn[1]), 2),
    r(-vn[2], 2), r(roll, 1), r(pitch, 1), r((yaw + 360) % 360, 1), r(av.alfa, 2), r(av.beta, 2), r(av.g_carga, 2),
    r(av.gases * 100, 1), r(av.rpm, 0), r(av.T, 3), r(av.Wh, 4), r(modelo.bateriaPct(av), 1),
    r(mando.pitch, 3), r(mando.yaw, 3), r(mando.trim, 2), r(av.de * R2D, 2), r(av.dr * R2D, 2), r((av.da || 0) * R2D, 2), r(w[0], 2), r(w[1], 2), r(av.perdida, 2)]);
  RegistroVuelo.muestra(vuelo);                     // el registro de vuelo del vehiculo (js/registro.js), a 10 Hz
}
function descargarVuelo(v) {
  const d = v.inicio, z = n => String(n).padStart(2, "0"), f = v.filas;
  const cab = [`# ${modelo.nombre} · vuelo del ${d.toLocaleString("es-ES")} · ${ESCENARIOS[v.escenario].nombre}` + (sesion.alumno ? ` · ${sesion.alumno.nombre}` : ""),
    `# masa ${(modelo.masa_kg * 1000).toFixed(0)} g · ${textoCM()} · viento ${entorno.viento.base} m/s ${entorno.viento.rachas ? "con" : "sin"} rachas · final: ${v.final} · ${f.length} muestras a 20 Hz`,
    `# ruta: x al norte, y al este, z altura (m, desde el lanzamiento) · profundidad: + = abajo · timon: + = a la derecha · aleron: + = alabeo a la derecha`];
  const a = document.createElement("a");
  a.href = URL.createObjectURL(new Blob([cab.join("\n") + "\n" + CN_COLUMNAS.join(",") + "\n" + f.map(x => x.join(",")).join("\n") + "\n"], { type: "text/csv" }));
  a.download = `vuelo_${d.getFullYear()}-${z(d.getMonth() + 1)}-${z(d.getDate())}_${z(d.getHours())}-${z(d.getMinutes())}-${z(d.getSeconds())}_${v.escenario}_${(v.final || "").split(" ")[0]}.csv`;
  document.body.appendChild(a); a.click(); a.remove(); setTimeout(() => URL.revokeObjectURL(a.href), 5000);
}
document.getElementById("cnUltimo").addEventListener("click", e => { if (ultimoVuelo) descargarVuelo(ultimoVuelo); e.target.blur(); });
document.getElementById("cnAuto").addEventListener("change", e => e.target.blur());
