// Estado comun de la aplicacion (sesion, avion, mando, vuelo) y utilidades de la interfaz (mostrar, confirmar, esc).
// Parte de la aplicacion de simulador_web/simulador.html: los modulos de js/app/ se cargan en orden y comparten el
// ambito global. En Godot: simulador_godot/scripts/principal.gd.
"use strict";
// =====================================================================
//  APLICACION: pantallas del aula, escenarios, caja negra, teclado y bucle. La fisica esta en
//  js/modelos.js (Modelos, ModeloAvion), el campo en js/entorno.js (Entorno) y el dibujo en
//  js/visor.js (Visor, VistaPrevia). Los aviones, en la carpeta aviones/.
// =====================================================================
const entorno = new Entorno();
let visor = null, previa = null;
let modelo = null, av = null;                 // ModeloAvion en uso y su estado
const mando = { pitch: 0, yaw: 0, pitchObj: 0, yawObj: 0, trim: 0, guinada: 0, vz: 0, guinadaObj: 0, vzObj: 0, gimbal: 0 };   // guinada y vz: cuadricoptero (A/D, W/S o palanca izquierda)
let vuelo = null;                             // registro del vuelo en curso (de L al final)
const sesion = { aula: false, alumno: null, avion: null, escenario: "libre", viento: { vel: 2, desde: 0, rachas: true }, dificultad: "facil" };
try { if (localStorage.getItem("sim_dificultad") === "real") sesion.dificultad = "real"; } catch (e) {}   // por defecto, fácil
try { const g = JSON.parse(localStorage.getItem("sim_viento") || "null"); if (g) sesion.viento = g; } catch (e) {}

let pantallaActual = null;
function mostrar(id) {
  document.querySelectorAll(".pantalla").forEach(p => p.classList.toggle("activa", p.id === id));
  pantallaActual = id;
  const enVuelo = id === null;
  document.body.classList.toggle("enVuelo", enVuelo);
  if (!enVuelo) { document.getElementById("ayuda").style.display = "none"; ponerPausa(false); Sonido.silenciar(true); }
  else Sonido.silenciar(false);
  if (enVuelo && document.activeElement && document.activeElement.blur) document.activeElement.blur();
  // la vista previa 3D del avion (un solo lienzo) vive en el inicio y en el hangar
  const slot = id === "pInicio" ? "previaSlotInicio" : id === "pHangar" ? "previaSlotHangar" : null;
  if (slot) { const c = document.getElementById("vistaPrevia"), sl = document.getElementById(slot); if (c.parentElement !== sl) sl.insertBefore(c, sl.firstChild); }
}
function esc(s) { return String(s).replace(/[&<>"']/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c])); }
function confirmar(titulo, html, textoSi) {
  return new Promise(res => {
    document.getElementById("modTitulo").textContent = titulo;
    document.getElementById("modTexto").innerHTML = html;
    document.getElementById("modSi").textContent = textoSi || "Sí";
    const m = document.getElementById("modal"), si = document.getElementById("modSi"), no = document.getElementById("modNo");
    m.classList.add("activa");
    const fin = v => { m.classList.remove("activa"); si.onclick = no.onclick = null; res(v); };
    si.onclick = () => fin(true); no.onclick = () => fin(false);
  });
}
function uuid4() {      // crypto.randomUUID solo existe en https/localhost; getRandomValues funciona en el http del aula
  const b = crypto.getRandomValues(new Uint8Array(16)); b[6] = (b[6] & 15) | 64; b[8] = (b[8] & 63) | 128;
  const h = [...b].map(x => x.toString(16).padStart(2, "0")).join("");
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20)}`;
}
function fmtHoras(h) { const m = Math.round(h * 60); return `${Math.floor(m / 60)} h ${String(m % 60).padStart(2, "0")} min`; }
function fmtFecha(iso) { const d = new Date(iso); return isNaN(d) ? iso : d.toLocaleString("es-ES", { dateStyle: "short", timeStyle: "short" }); }
