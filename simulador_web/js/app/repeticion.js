// Pausa, carga, repeticion del vuelo y su resumen (cifras y traza).
// Parte de la aplicacion de simulador_web/simulador.html: los modulos de js/app/ se cargan en orden y comparten el
// ambito global. En Godot: simulador_godot/scripts/app/repeticion.gd.
"use strict";
// =====================================================================
//  PAUSA, CARGA Y REPETICION
// =====================================================================
let pausado = false, salirTras = false;
function ponerPausa(p) {
  if (p === pausado) return;
  pausado = p; document.getElementById("pausa").classList.toggle("activa", p);
  if (p) {
    document.getElementById("btnPausaCamara").textContent = "Cámara: " + nombreCamara(visor.camara);
    document.getElementById("btnPausaInstr").textContent = textoInstr();
    document.getElementById("pausaSonido").checked = Sonido.on;
    document.getElementById("pausaInfo").textContent = `${Modelos.datos(sesion.avion).nombre} · ${ESCENARIOS[sesion.escenario].nombre}`;
    Sonido.silenciar(true);
  } else { Sonido.silenciar(false); tAnterior = performance.now(); for (const k in teclas) teclas[k] = false; document.getElementById("ayuda").style.display = "none"; }
}
const nombreCamara = n => ["", "piloto", "persecución", modelo && modelo.esFPV ? "FPV (gafas)" : modelo && modelo.esCuadricoptero ? "del dron" : modelo && modelo.esBipode ? "puesto de tiro" : "a bordo"][n];
const textoInstr = () => (modelo.esFPV ? "OSD: " : modelo.esCuadricoptero ? "Pantalla de la app: " : "Instrumentos: ") + (sinInstrumentos ? "no" : "sí");
document.getElementById("btnPausaSeguir").onclick = () => ponerPausa(false);
document.getElementById("btnPausaReiniciar").onclick = () => { ponerPausa(false); reiniciar(); };
document.getElementById("btnPausaCamara").onclick = () => { visor.camara = visor.camara % 3 + 1; document.getElementById("btnPausaCamara").textContent = "Cámara: " + nombreCamara(visor.camara); };
document.getElementById("btnPausaInstr").onclick = () => { sinInstrumentos = !sinInstrumentos; document.getElementById("btnPausaInstr").textContent = textoInstr(); };
document.getElementById("btnPausaAyuda").onclick = () => { const a = document.getElementById("ayuda"); a.style.display = a.style.display === "block" ? "none" : "block"; };
document.getElementById("btnPausaTerminar").onclick = () => { ponerPausa(false); if (av.estado === "volando") terminarVuelo("abandonado"); else if (vuelo && vuelo.final) mostrarResultado(vuelo); else irInicio(); };
document.getElementById("btnPausaSalir").onclick = salirAlMenu;
/** Sale al menu principal: si habia un vuelo en marcha se guarda (si hay piloto) sin pasar por la pantalla de resultado. */
function salirAlMenu() {
  ponerPausa(false);
  if (av && av.estado === "volando" && vuelo) { salirTras = true; terminarVuelo("abandonado"); } else irInicio();
}
/** Pantalla de carga: titulo, texto del paso y fraccion; espera un cuadro para que se pinte antes del trabajo pesado. */
async function mostrarCarga(titulo, texto, frac) {
  const c = document.getElementById("carga"); c.classList.add("activa");
  document.getElementById("cargaTitulo").textContent = titulo; document.getElementById("cargaTexto").textContent = texto;
  document.getElementById("cargaBarra").style.width = (frac * 100) + "%";
  await new Promise(r => requestAnimationFrame(() => setTimeout(r, 40)));
}
function ocultarCarga() { document.getElementById("carga").classList.remove("activa"); }

// ---- repeticion: el vuelo grabado en la caja negra (20 Hz), interpolado, con las mismas camaras e instrumentos ----
const Repeticion = { activa: false, filas: null, t: 0, dur: 0, pausa: false, i: 0, vuelo: null };
function verRepeticion(v) {
  if (!v || !v.filas || v.filas.length < 2) return;
  Object.assign(Repeticion, { activa: true, filas: v.filas, t: 0, dur: v.filas[v.filas.length - 1][0], pausa: false, i: 0, vuelo: v });
  av = modelo.estadoInicial(); av.estado = "repetición"; colocarEnBase(av);
  document.getElementById("repBarra").style.display = "block";
  mostrar(null); document.getElementById("objetivos").innerHTML = ""; aviso("");
}
function pasoRepeticion(dt) {
  const R = Repeticion, f = R.filas;
  if (!R.pausa) R.t = Math.min(R.dur, R.t + dt);
  let i = R.i; while (i < f.length - 2 && f[i + 1][0] <= R.t) i++; while (i > 0 && f[i][0] > R.t) i--; R.i = i;
  const a = f[i], b = f[Math.min(f.length - 1, i + 1)], u = b[0] > a[0] ? Math.min(1, Math.max(0, (R.t - a[0]) / (b[0] - a[0]))) : 0;
  const L = j => a[j] + (b[j] - a[j]) * u, ang = j => { let d = b[j] - a[j]; if (d > 180) d -= 360; if (d < -180) d += 360; return a[j] + d * u; };
  av.p = [L(1), L(2), -L(3)]; av.q = Cuat.desdeEuler(ang(7) * D2R, ang(8) * D2R, ang(9) * D2R);
  av.V = L(4); av.alfa = L(10); av.g_carga = L(12); av.gases = L(13) / 100; av.rpm = L(14); av.Wh = L(16); av.perdida = L(26); av.t = R.t;
  av.de = L(21) * D2R; av.dr = L(22) * D2R; av.da = L(23) * D2R; av.v = [av.V, 0, 0];
  mando.pitch = L(18); mando.yaw = L(19);
  document.getElementById("repTiempo").textContent = `${R.t.toFixed(1)} s de ${R.dur.toFixed(1)}` + (R.pausa ? " · pausa" : "");
  document.getElementById("repProgreso").style.width = (100 * R.t / Math.max(0.1, R.dur)) + "%";
  if (R.t >= R.dur) R.pausa = true;
}
function salirRepeticion() { Repeticion.activa = false; document.getElementById("repBarra").style.display = "none"; mostrarResultado(Repeticion.vuelo); }

// =====================================================================
//  RESUMEN DEL VUELO: cifras y traza (planta coloreada por altura y perfil de altura)
// =====================================================================
function fmtMin(s) { return `${Math.floor(s / 60)}:${String(Math.round(s % 60)).padStart(2, "0")}`; }
function pintarResumen(v) {
  const f = v.filas, st = document.getElementById("resStats"), cv = document.getElementById("resTraza"), g = cv.getContext("2d"), W = cv.width, H = cv.height;
  g.fillStyle = "#0b0f14"; g.fillRect(0, 0, W, H);
  document.getElementById("btnRepeticion").disabled = f.length < 2;
  if (f.length < 2) { st.innerHTML = ""; return; }
  const col = i => f.map(r => r[i]), C = casa(), ult = f[f.length - 1];
  const hs = col(3), vs = col(4), gs = col(12), ns = col(1).map(x => x - C.N), es = col(2).map(x => x - C.E), ds = ns.map((n, i) => Math.hypot(n, es[i]));
  const toma = v.final === "aterrizado" ? `${Math.max(0, -ult[6]).toFixed(1)} m/s` : "—";
  st.innerHTML = [[fmtMin(v.tVuelo), "tiempo de vuelo"], [(v.hmax || 0).toFixed(0) + " m", "altura máxima"], [Math.max(...vs).toFixed(1) + " m/s", "velocidad máxima"],
    [Math.max(...ds).toFixed(0) + " m", "distancia máxima"], [Math.max(...gs).toFixed(1) + " g", "carga máxima"], [toma, "descenso en la toma"]]
    .map(([b, s]) => `<div><b>${b}</b><span>${s}</span></div>`).join("");
  // planta: norte arriba, cuadrada, a la izquierda; traza coloreada por altura (azul bajo, amarillo alto)
  const S = H, semi = Math.max(60, ...ds) * 1.15, k = (S - 30) / (2 * semi), X = e => S / 2 + e * k, Y = n => S / 2 - n * k;
  const hmax = Math.max(1, ...hs), color = h => `hsl(${210 - 160 * Math.min(1, Math.max(0, h) / hmax)} 90% 60%)`;
  g.lineWidth = 1; g.font = "10px sans-serif";
  for (const r of [50, 100, 200, 500, 1000, 2000, 5000]) if (r < semi && r * k > 18) {
    g.strokeStyle = "rgba(255,255,255,.12)"; g.beginPath(); g.arc(X(0), Y(0), r * k, 0, 2 * Math.PI); g.stroke();
    g.fillStyle = "rgba(255,255,255,.4)"; g.fillText(r >= 1000 ? r / 1000 + " km" : r + " m", X(0) + r * k * 0.71 + 3, Y(0) - r * k * 0.71 - 2);
  }
  if (!entorno.mundo) {
    const P = entorno.pista; g.fillStyle = "#777"; g.fillRect(X(-P.ancho / 2), Y(P.n1), P.ancho * k, (P.n1 - P.n0) * k);
    entorno.circuito.pilones.forEach(([n, e], i) => { g.fillStyle = entorno.circuito.colores[i].hex; g.beginPath(); g.arc(X(e), Y(n), 3.5, 0, 2 * Math.PI); g.fill(); });
  }
  g.lineWidth = 2;
  for (let i = 1; i < f.length; i++) { g.strokeStyle = color(hs[i]); g.beginPath(); g.moveTo(X(es[i - 1]), Y(ns[i - 1])); g.lineTo(X(es[i]), Y(ns[i])); g.stroke(); }
  g.fillStyle = "#fff"; g.beginPath(); g.arc(X(0), Y(0), 4, 0, 2 * Math.PI); g.fill();
  g.fillStyle = "#e6edf3"; g.font = "bold 11px sans-serif"; g.fillText("N ↑", 8, 14); g.fillText("piloto", X(0) + 6, Y(0) + 12);
  const fin = v.final || ""; g.fillStyle = fin.startsWith("roto") ? "#ff5252" : "#8be08f"; g.beginPath(); g.arc(X(es[es.length - 1]), Y(ns[ns.length - 1]), 4, 0, 2 * Math.PI); g.fill();
  // perfil de altura
  const x0 = S + 44, x1 = W - 14, y0 = H - 26, y1 = 18, T = Math.max(0.1, ult[0]);
  g.strokeStyle = "rgba(255,255,255,.25)"; g.lineWidth = 1; g.beginPath(); g.moveTo(x0, y1); g.lineTo(x0, y0); g.lineTo(x1, y0); g.stroke();
  g.fillStyle = "rgba(255,255,255,.5)"; g.font = "10px sans-serif";
  g.fillText(hmax.toFixed(0) + " m", x0 + 4, y1 + 10); g.fillText("0", x0 - 10, y0 + 4); g.fillText(fmtMin(T), x1 - 30, y0 + 14); g.fillText("altura · tiempo", x0 + 4, y0 + 14);
  g.beginPath();
  for (let i = 0; i < f.length; i++) { const x = x0 + (x1 - x0) * f[i][0] / T, y = y0 - (y0 - y1) * Math.max(0, hs[i]) / hmax; i ? g.lineTo(x, y) : g.moveTo(x, y); }
  g.strokeStyle = "#ffc83d"; g.lineWidth = 2; g.stroke();
}
