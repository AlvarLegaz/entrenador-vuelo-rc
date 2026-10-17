// El aula: la API del servidor, la cola de vuelos sin enviar y la pantalla de acceso (servidor, usuario y contrasena o sin conexion).
// Parte de la aplicacion de simulador_web/simulador.html: los modulos de js/app/ se cargan en orden y comparten el
// ambito global. En Godot: simulador_godot/scripts/aula.gd.
"use strict";
// =====================================================================
//  AULA: API del servidor y cola de vuelos sin enviar
// =====================================================================
/** El aula que sale si el alumno no ha escrito otra: la de config.js (Docker_web: la misma direccion, detras de su
 *  nginx) o, servido por SERVIDOR_WEB.bat (u otro servidor de ficheros), el mismo ordenador en el puerto 8080. */
function aulaPorDefecto() {
  if (typeof window.UXS_AULA === "string") return window.UXS_AULA.replace(/\/+$/, "");
  return location.protocol.startsWith("http") ? `${location.protocol}//${location.hostname}:8080` : "";
}
/** Direccion del servidor del aula (pantalla de acceso): el simulador se abre en cada ordenador y el aula solo
 *  administra. Sin direccion guardada, la de por defecto (aulaPorDefecto). */
function urlAula() {
  let u = ""; try { u = localStorage.getItem("evrc_url_aula") || ""; } catch (e) {}
  return (u || aulaPorDefecto()).replace(/\/+$/, "");
}
async function api(metodo, ruta, cuerpo, pase) {
  const h = cuerpo ? { "Content-Type": "application/json" } : {}, P = pase || sesion.pase;
  if (P) h["X-Alumno"] = P;                        // el pase del alumno: sin el, el servidor no acepta sus vuelos
  const r = await fetch(urlAula() + "/api/" + ruta, { method: metodo, headers: h, body: cuerpo ? JSON.stringify(cuerpo) : undefined });
  let d = null; try { d = await r.json(); } catch (e) {}
  if (!r.ok) { const e = new Error((d && d.error) || ("error " + r.status)); e.status = r.status; throw e; }
  return d;
}
const esDefinitivo = e => e.status >= 400 && e.status < 500 && e.status !== 401 && e.status !== 429;   // error del vuelo, no de la red ni de la clave: no reintentar
function cola() { try { return JSON.parse(localStorage.getItem("sim_cola_vuelos") || "[]"); } catch (e) { return []; } }
function guardarCola(c) { try { localStorage.setItem("sim_cola_vuelos", JSON.stringify(c)); } catch (e) {} }
async function vaciarCola() {
  RegistroDB.subirPendientes();                    // y los registros de vuelo (js/registro.js)
  if (!sesion.aula) return;
  const quedan = [];
  for (const v of cola()) { const { _pase, ...cuerpo } = v; try { await api("POST", "vuelos", cuerpo, _pase); } catch (e) { if (!esDefinitivo(e)) quedan.push(v); } }
  guardarCola(quedan);
  document.getElementById("pendientes").textContent = quedan.length ? `${quedan.length} vuelo(s) de este ordenador pendientes de enviar.` : "";
}
setInterval(vaciarCola, 30000);
async function enviarVuelo(v) {
  if (!sesion.aula || !sesion.alumno) return { estado: "sin_aula" };
  try { const r = await api("POST", "vuelos", v); vaciarCola(); return { estado: "ok", progreso: r.progreso }; }
  catch (e) {
    if (esDefinitivo(e)) return { estado: "error", msg: e.message };
    const c = cola(); c.push(Object.assign({ _pase: sesion.pase }, v)); guardarCola(c);   // sin red: se envia en cuanto vuelva (el id evita duplicados), con el pase de su alumno
    return { estado: "cola" };
  }
}

// =====================================================================
//  1. ACCESO: servidor del aula, usuario y contrasena, o sin conexion (se vuela igual, sin guardar el progreso)
// =====================================================================
// la sesion dura lo que esta pestana del navegador: al recargar no se vuelve a pedir la contrasena
function sesionGuardada() { try { return JSON.parse(sessionStorage.getItem("evrc_sesion") || "null"); } catch (e) { return null; } }
function guardarSesion(x) { try { if (x) sessionStorage.setItem("evrc_sesion", JSON.stringify(x)); else sessionStorage.removeItem("evrc_sesion"); } catch (e) {} }
function usuarioGuardado() { try { return localStorage.getItem("evrc_usuario") || ""; } catch (e) { return ""; } }
function irAcceso(msg) {
  document.getElementById("urlAula").value = urlAula();          // servido por SERVIDOR_WEB.bat o Docker_web: ya viene puesta
  document.getElementById("accUsuario").value = usuarioGuardado();
  document.getElementById("accClave").value = "";
  document.getElementById("errAlumno").textContent = msg || "";
  const n = cola().length; document.getElementById("pendientes").textContent = n ? `${n} vuelo(s) de este ordenador pendientes de enviar al aula.` : "";
  mostrar("pAlumno");
  setTimeout(() => document.getElementById(document.getElementById("accUsuario").value ? "accClave" : "accUsuario").focus(), 30);
}
/** Guarda la direccion escrita (sin cambios si es la de por defecto) y la devuelve normalizada. */
function guardarUrl(u) {
  u = (u || "").trim().replace(/\/+$/, ""); if (u && !/^https?:\/\//.test(u)) u = "http://" + u;
  const defecto = aulaPorDefecto();
  try { if (u === defecto) localStorage.removeItem("evrc_url_aula"); else localStorage.setItem("evrc_url_aula", u); } catch (e) {}
  return u;
}
/** Dentro del aula: el perfil del alumno y su pase (sin el, el servidor no acepta sus vuelos). */
async function dentroDelAula(alumno, pase) {
  sesion.alumno = alumno; sesion.pase = pase; sesion.aula = true; sesion.nombreAula = urlAula();
  try { sesion.nombreAula = (await api("GET", "estado")).aula; } catch (e) {}
  guardarSesion({ url: urlAula(), alumno, pase });
  vaciarCola(); Desgaste.cargar();                 // el estado de sus vehiculos (horas, averias): js/desgaste.js
}
/** Registro de alumno nuevo (pagina aparte): usuario, correo del centro, nombre, apellidos y contrasena. La cuenta queda
 *  pendiente hasta que la aprueba el profesor en su panel. Como pantalla_registro.gd. */
const DOMINIOS_REGISTRO = ["alu.murciaeduca.es", "murciaeduca.es"];     // los correos de la Consejeria de la Region de Murcia
function irRegistro(usuario) {
  const u = guardarUrl(document.getElementById("urlAula").value);
  if (!u) { document.getElementById("errAlumno").textContent = "Escribe la dirección del servidor del aula"; return; }
  document.getElementById("regAula").textContent = u;
  for (const id of ["regNombre", "regApellidos", "regCorreo", "regClave", "regClave2"]) document.getElementById(id).value = "";
  document.getElementById("regUsuario").value = usuario || "";
  document.getElementById("errRegistro").textContent = "";
  mostrar("pRegistro"); setTimeout(() => document.getElementById("regNombre").focus(), 30);
}
/** Lo que falta o esta mal en el formulario de registro (el aula lo vuelve a comprobar), o "". */
function errorRegistro(d) {
  if (!d.nombre) return "Escribe tu nombre";
  if (!d.apellidos) return "Escribe tus apellidos";
  if (!new RegExp("^[a-z0-9._%+-]+@(" + DOMINIOS_REGISTRO.map(x => x.replace(/\./g, "\\.")).join("|") + ")$").test(d.correo))
    return "El correo tiene que ser el del centro: …@" + DOMINIOS_REGISTRO.join(" o …@");
  if (d.usuario.length < 2) return "Elige un usuario (2 letras como mínimo)";
  if (d.clave.length < 4 || d.clave.length > 20) return "La contraseña tiene que tener de 4 a 20 caracteres";
  if (d.clave !== d.clave2) return "Las dos contraseñas no coinciden";
  return "";
}
async function enviarRegistro() {
  const v = id => document.getElementById(id).value, err = document.getElementById("errRegistro");
  const d = { nombre: v("regNombre").trim(), apellidos: v("regApellidos").trim(), correo: v("regCorreo").trim().toLowerCase(),
              usuario: v("regUsuario").replace(/\s+/g, " ").trim(), clave: v("regClave"), clave2: v("regClave2") };
  const e = errorRegistro(d); if (e) { err.textContent = e; return; }
  err.textContent = "Enviando…";
  try {
    const r = await api("POST", "registro", { usuario: d.usuario, correo: d.correo, nombre: d.nombre, apellidos: d.apellidos, clave: d.clave }, "-");
    try { localStorage.setItem("evrc_usuario", d.usuario); } catch (x) {}
    irAcceso(r.mensaje || "Solicitud enviada: el profesor tiene que aprobarla.");
  } catch (x) { err.textContent = x.status ? x.message : `No se puede conectar con el aula en ${urlAula()}.`; }
}
document.getElementById("btnIrRegistro").onclick = () => irRegistro(document.getElementById("accUsuario").value.trim());
document.getElementById("btnRegistrar").onclick = () => enviarRegistro();
document.getElementById("btnRegVolver").onclick = () => irAcceso();
for (const id of ["regNombre", "regApellidos", "regCorreo", "regUsuario", "regClave", "regClave2"])
  document.getElementById(id).addEventListener("keydown", e => { if (e.key === "Enter") enviarRegistro(); });
async function entrarAula() {
  const err = document.getElementById("errAlumno"), u = guardarUrl(document.getElementById("urlAula").value);
  const usuario = document.getElementById("accUsuario").value.replace(/\s+/g, " ").trim(), clave = document.getElementById("accClave").value;
  if (!u) { err.textContent = "Escribe la dirección del servidor del aula"; return; }
  if (!usuario) { err.textContent = "Escribe tu usuario"; return; }
  if (!clave) { err.textContent = "Escribe tu contraseña"; return; }
  try { localStorage.setItem("evrc_usuario", usuario); } catch (e) {}
  err.textContent = "Conectando…";
  try {
    const r = await api("POST", "entrar", { usuario, clave }, "-");
    err.textContent = ""; await dentroDelAula(r.alumno, r.pase); irInicio();
  } catch (e) {
    if (e.status === 404) {                         // no existe: los alumnos nuevos se registran (y los aprueba el profesor)
      err.textContent = e.message;
      if (await confirmar(`¿Registrarte como «${usuario}»?`,
                          "<p>No hay ningún alumno con ese usuario en el aula. Si eres nuevo, regístrate: el profesor tiene que aprobar tu cuenta.</p>", "Registrarme"))
        irRegistro(usuario);
      return;
    }
    err.textContent = e.status ? e.message : `No se puede conectar con el aula en ${u}. Comprueba la dirección y que el profesor tenga abierto SERVIDOR_AULA.bat.`;
  }
}
function salirDelAula() { sesion.aula = false; sesion.alumno = null; sesion.pase = null; guardarSesion(null); Desgaste.cargar(); }
function cerrarSesion() { const n = sesion.alumno && sesion.alumno.nombre; salirDelAula(); irAcceso(n ? `Sesión de ${n} cerrada.` : ""); }
/** Al arrancar (o al recargar la pestana): si ya habia entrado en esta pestana, sigue dentro sin pedir la contrasena. */
async function retomarSesion() {
  const x = sesionGuardada();
  if (!x || !x.alumno || x.url !== urlAula()) return false;
  try { const a = await api("GET", "alumnos/" + x.alumno.id); delete a.vuelos; await dentroDelAula(a, x.pase); return true; } catch (e) { return false; }
}
document.getElementById("btnEntrar").onclick = () => entrarAula(false);
for (const id of ["urlAula", "accUsuario", "accClave"]) document.getElementById(id).addEventListener("keydown", e => { if (e.key === "Enter") entrarAula(false); });
document.getElementById("btnSinConexion").onclick = () => { salirDelAula(); irInicio(); };
document.getElementById("btnProfesor").onclick = () => {
  const u = guardarUrl(document.getElementById("urlAula").value);
  if (u) window.open(u + "/profesor.html", "_blank"); else document.getElementById("errAlumno").textContent = "Escribe la dirección del servidor del aula";
};
document.getElementById("btnCerrarSesion").onclick = cerrarSesion;
/** Una clave en el modal (la de una sala con clave): [clave, repetida o null], o null si cancela. */
function pedirClave(titulo, texto, nueva) {
  const html = `<p>${esc(texto)}</p><input type="password" id="modClave" maxlength="20" autocomplete="off" style="width:100%">` +
    (nueva ? '<input type="password" id="modClave2" maxlength="20" autocomplete="off" placeholder="Repítela" style="width:100%;margin-top:8px">' : "");
  setTimeout(() => { const i = document.getElementById("modClave"); if (i) i.focus();
    document.querySelectorAll("#modClave, #modClave2").forEach(x => x.onkeydown = e => { if (e.key === "Enter") document.getElementById("modSi").click(); }); }, 30);
  return confirmar(titulo, html, nueva ? "Guardar" : "Entrar").then(ok => ok ? [document.getElementById("modClave").value, nueva ? document.getElementById("modClave2").value : null] : null);
}
