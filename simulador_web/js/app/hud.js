// HUD: horizonte, anemometro y variometro, GPS y el resto de lo que se pinta en vuelo.
// Parte de la aplicacion de simulador_web/simulador.html: los modulos de js/app/ se cargan en orden y comparten el
// ambito global. En Godot: simulador_godot/scripts/app/hud.gd.
"use strict";
// =====================================================================
//  HUD Y BUCLE
// =====================================================================
let tToast = 0;
// ---- horizonte artificial con brujula (camaras 2 y 3): rosa de rumbos en el anillo exterior, que gira con el rumbo (el
// norte queda donde apunta el morro), y bola de actitud que gira con el alabeo y se desplaza con el cabeceo ----
const HZ_PX_GRADO = 3.2;
(function construirHorizonte() {
  const NS = "http://www.w3.org/2000/svg", mk = (t, a, tx) => { const e = document.createElementNS(NS, t); for (const k in a) e.setAttribute(k, a[k]); if (tx !== undefined) e.textContent = tx; return e; };
  const rosa = document.getElementById("hzRosa"), card = { 0: "N", 90: "E", 180: "S", 270: "W" };
  for (let a = 0; a < 360; a += 5) {
    const mayor = a % 30 === 0;
    rosa.appendChild(mk("line", { x1: 150, y1: 4, x2: 150, y2: mayor ? 18 : (a % 10 === 0 ? 13 : 10), stroke: "#e6edf3", "stroke-width": mayor ? 3 : 1.5, transform: `rotate(${a} 150 150)` }));
    if (mayor) rosa.appendChild(mk("text", { x: 150, y: a in card ? 40 : 34, "text-anchor": "middle", fill: a === 0 ? "#f85149" : "#e6edf3",
                                              "font-size": a in card ? 20 : 12, "font-weight": a in card ? 700 : 400, transform: `rotate(${a} 150 150)` }, a in card ? card[a] : String(a)));
  }
  const esc = document.getElementById("hzEscalera");
  for (let p = -40; p <= 40; p += 5) {
    if (p === 0) continue;
    const y = 150 - p * HZ_PX_GRADO, medio = p % 10 === 0 ? 34 : 12;
    esc.appendChild(mk("line", { x1: 150 - medio, y1: y, x2: 150 + medio, y2: y, stroke: "#fff", "stroke-width": 1.5 }));
    if (p % 10 === 0) for (const lado of [-1, 1]) esc.appendChild(mk("text", { x: 150 + lado * (medio + 6), y: y + 4, fill: "#fff", "font-size": 11, "text-anchor": lado < 0 ? "end" : "start" }, String(p)));
  }
  const banco = document.getElementById("hzBanco");          // marcas de alabeo fijas a 0, +-10, 20, 30, 45, 60 grados
  for (const a of [-60, -45, -30, -20, -10, 0, 10, 20, 30, 45, 60])
    banco.appendChild(mk("line", { x1: 150, y1: 52, x2: 150, y2: a % 30 === 0 ? 62 : 58, transform: `rotate(${a} 150 150)`, "stroke-width": a === 0 ? 3 : 1.5 }));
})();
// ---- anemometro y variometro. El anemometro se construye para cada avion: rojo por debajo de 1,1 veces la perdida,
// ambar hasta 1,3 (velocidad minima de aproximacion), verde hasta 2 (crucero), blanco por encima ----
const AN = { vs: 8, vmax: 20 }, VA_MAX = 6;
const anAng = v => -135 + 270 * Math.max(0, Math.min(1, v / AN.vmax));           // grados desde arriba, horario
const anPt = (v, r) => [75 + r * Math.sin(anAng(v) * D2R), 75 - r * Math.cos(anAng(v) * D2R)];
const vaAng = vz => -90 + 135 * Math.max(-1, Math.min(1, vz / VA_MAX));          // 0 a las 9, subir = horario
const vaPt = (vz, r) => [75 + r * Math.sin(vaAng(vz) * D2R), 75 - r * Math.cos(vaAng(vz) * D2R)];
function construirAnemometro(vs) {
  const NS = "http://www.w3.org/2000/svg", mk = (t, a, tx) => { const e = document.createElementNS(NS, t); for (const k in a) e.setAttribute(k, a[k]); if (tx !== undefined) e.textContent = tx; return e; };
  AN.vs = vs; AN.vmax = vs > 0 ? Math.ceil(2.6 * vs / 5) * 5 : 20;      // sin velocidad de perdida (dron): escala fija, sin bandas
  const bandas = document.getElementById("anBandas"), esc = document.getElementById("anEscala");
  bandas.innerHTML = ""; esc.innerHTML = "";
  const arco = (v0, v1, color) => {
    const [x0, y0] = anPt(v0, 62), [x1, y1] = anPt(v1, 62), grande = anAng(v1) - anAng(v0) > 180 ? 1 : 0;
    bandas.appendChild(mk("path", { d: `M ${x0} ${y0} A 62 62 0 ${grande} 1 ${x1} ${y1}`, stroke: color }));
  };
  if (vs > 0) { arco(0, 1.1 * vs, "#e53935"); arco(1.1 * vs, 1.3 * vs, "#ffb300"); arco(1.3 * vs, Math.min(2.0 * vs, AN.vmax), "#43a047"); }
  if (2.0 * vs < AN.vmax) arco(2.0 * vs, AN.vmax, "#e6edf3");
  for (let v = 0; v <= AN.vmax; v += 1) {
    const mayor = v % 5 === 0, [xa, ya] = anPt(v, 56), [xb, yb] = anPt(v, mayor ? 46 : 51);
    esc.appendChild(mk("line", { x1: xa, y1: ya, x2: xb, y2: yb, stroke: "#e6edf3", "stroke-width": mayor ? 2 : 1 }));
    if (mayor) { const [xt, yt] = anPt(v, 36); esc.appendChild(mk("text", { x: xt, y: yt + 4, "text-anchor": "middle", fill: "#e6edf3", "font-size": 11 }, String(v))); }
  }
  const va = document.getElementById("vaEscala"); va.innerHTML = "";
  for (let vz = -VA_MAX; vz <= VA_MAX; vz += 1) {
    const mayor = vz % 2 === 0, [xa, ya] = vaPt(vz, 62), [xb, yb] = vaPt(vz, mayor ? 50 : 56);
    va.appendChild(mk("line", { x1: xa, y1: ya, x2: xb, y2: yb, stroke: vz > 0 ? "#8be08f" : vz < 0 ? "#ff8a80" : "#fff", "stroke-width": mayor ? 2 : 1 }));
    if (mayor) { const [xt, yt] = vaPt(vz, 40); va.appendChild(mk("text", { x: xt, y: yt + 4, "text-anchor": "middle", fill: "#e6edf3", "font-size": 11 }, (vz > 0 ? "+" : "") + vz)); }
  }
}
function pintarInstrumentos(V, vz) {
  const [xa, ya] = anPt(V, 55);
  const ag = $h("anAguja"); ponerAttr(ag, "x2", xa); ponerAttr(ag, "y2", ya);
  const t = $h("anTxt"); ponerTxt(t, V.toFixed(1)); ponerAttr(t, "fill", V < 1.1 * AN.vs ? "#ff5252" : V < 1.3 * AN.vs ? "#ffb300" : "#e6edf3");
  const [xv, yv] = vaPt(vz, 55);
  const vg = $h("vaAguja"); ponerAttr(vg, "x2", xv); ponerAttr(vg, "y2", yv);
  ponerTxt($h("vaTxt"), (vz >= 0 ? "+" : "") + vz.toFixed(1));
}
// ---- GPS: mapa del campo visto desde arriba, norte arriba, centrado entre el piloto y el avion; la escala se abre
// para que siempre se vean los dos (minimo +-150 m). Pista, pilones de colores, zona 2 (pista 2, diana y puerta),
// el piloto (punto blanco), la estela del ultimo minuto y el avion (triangulo con su rumbo) ----
const GPS = { estela: [], tUlt: -1, zoom: 1 };     // zoom: con la rueda del raton sobre el GPS (1 = escala automatica)
document.getElementById("gps").addEventListener("click", e => {           // UAV: clic en el mapa = ir a ese punto
  if (!piloto || !GPS.vm || !entorno.mundo) return;
  const r = e.currentTarget.getBoundingClientRect(), V = GPS.vm, x = (e.clientX - r.left) * V.W / r.width, y = (e.clientY - r.top) * V.W / r.height;
  uavPoner("PUNTO", [V.N - (y - V.W / 2) / V.k, V.E + (x - V.W / 2) / V.k]);
});
document.getElementById("gps").addEventListener("wheel", e => { e.preventDefault(); GPS.zoom = Math.max(0.12, Math.min(8, GPS.zoom * (e.deltaY > 0 ? 1.25 : 0.8))); }, { passive: false });
/** Barra de escala: una longitud redonda de un tercio del semiancho del mapa. */
function escalaRedonda(semi) { const c = [50, 100, 200, 500, 1000, 2000, 5000, 10000]; return c.reduce((a, b) => Math.abs(b - semi / 3) < Math.abs(a - semi / 3) ? b : a, c[0]); }
function pintarGPS(rumbo) {
  const cv = document.getElementById("gps"), ver = true;                 // en todas las camaras (en la 1, a la derecha, en vez de los relojes)
  cv.style.display = ver ? "block" : "none";
  if (!ver) return;
  const N = av.p[0], E = av.p[1];
  if (av.estado === "volando" && av.t - GPS.tUlt >= 0.5) { GPS.estela.push([N, E, av.t]); GPS.tUlt = av.t; }
  if (av.t < GPS.tUlt) { GPS.estela = []; GPS.tUlt = -1; }                         // vuelo nuevo
  while (GPS.estela.length && av.t - GPS.estela[0][2] > 60) GPS.estela.shift();
  if (entorno.mundo) return pintarGPSMundo(cv, rumbo, N, E);
  const g = cv.getContext("2d"), W = cv.width, cN = N / 2, cE = E / 2;              // centro del mapa: entre piloto y avion
  const semi = Math.max(150, 0.62 * Math.max(Math.abs(N), Math.abs(E)) + 40) * GPS.zoom, k = W / 2 / semi;
  const X = e => W / 2 + (e - cE) * k, Y = n => W / 2 - (n - cN) * k;
  g.clearRect(0, 0, W, W);
  g.fillStyle = "rgba(11,15,20,0.85)"; g.fillRect(0, 0, W, W);
  const P = entorno.pista, Z = entorno.zona2;
  g.fillStyle = "#9e9e9e"; g.fillRect(X(-P.ancho / 2), Y(P.n1), P.ancho * k, (P.n1 - P.n0) * k);                     // pista 1
  g.fillStyle = "#8d6e63"; g.fillRect(X(Z.pista.e0), Y(Z.pista.n + Z.pista.ancho / 2), (Z.pista.e1 - Z.pista.e0) * k, Z.pista.ancho * k);   // pista 2
  g.strokeStyle = "#e0e0e0"; g.lineWidth = 1;
  for (const [r] of Z.diana.anillos) { g.beginPath(); g.arc(X(Z.diana.e), Y(Z.diana.n), Math.max(1.5, r * k), 0, 2 * Math.PI); g.stroke(); }
  for (const [P, cual] of [[Z.puerta, "naranja"], [Z.puertaVerde, "verde"]])           // las dos puertas
    for (const [n, e] of entorno.pilonesPuerta(cual)) { g.fillStyle = P.color.hex; g.beginPath(); g.arc(X(e), Y(n), 3, 0, 2 * Math.PI); g.fill(); }
  entorno.circuito.pilones.forEach(([n, e], i) => { g.fillStyle = entorno.circuito.colores[i].hex; g.beginPath(); g.arc(X(e), Y(n), 4, 0, 2 * Math.PI); g.fill(); g.strokeStyle = "#fff"; g.stroke(); });
  g.fillStyle = "#fff"; g.beginPath(); g.arc(X(0), Y(0), 3.5, 0, 2 * Math.PI); g.fill();                              // piloto
  if (GPS.estela.length > 1) { g.strokeStyle = "rgba(255,213,79,0.8)"; g.lineWidth = 1.5; g.beginPath(); GPS.estela.forEach(([n, e], i) => i ? g.lineTo(X(e), Y(n)) : g.moveTo(X(e), Y(n))); g.lineTo(X(E), Y(N)); g.stroke(); }
  if (esDJI()) casaDJI(g, X(E), Y(N), X(0), Y(0), W);
  pintarOtrosGPS(g, X, Y, W);
  g.save(); g.translate(X(E), Y(N)); g.rotate(rumbo * D2R);                                                          // avion
  g.fillStyle = "#ffd54f"; g.strokeStyle = "#000"; g.lineWidth = 1; g.beginPath(); g.moveTo(0, -9); g.lineTo(6, 7); g.lineTo(0, 4); g.lineTo(-6, 7); g.closePath(); g.fill(); g.stroke(); g.restore();
  const vto = entorno.viento;                                                                                         // viento: flecha hacia donde va
  if (vto.base > 0.3) { g.save(); g.translate(W - 18, 18); g.rotate(vto.rumbo); g.strokeStyle = "#4fc3f7"; g.lineWidth = 2; g.beginPath(); g.moveTo(0, 8); g.lineTo(0, -8); g.lineTo(-4, -3); g.moveTo(0, -8); g.lineTo(4, -3); g.stroke(); g.restore(); }
  g.fillStyle = "#e6edf3"; g.font = "bold 11px sans-serif"; g.fillText("N", 6, 14);
  g.font = "bold 12px sans-serif"; g.fillText(`alt ${Math.max(0, -av.p[2]).toFixed(0)} m`, 6, 30);
  if (av.motorRoto) { g.fillStyle = "#ff5252"; g.fillText("MOTOR PARADO", 6, 46); }
  const esc = escalaRedonda(semi); g.strokeStyle = "#e6edf3"; g.lineWidth = 2; g.beginPath(); g.moveTo(8, W - 10); g.lineTo(8 + esc * k, W - 10); g.stroke();
  g.font = "10px sans-serif"; g.fillText(esc >= 1000 ? esc / 1000 + " km" : esc + " m", 10, W - 14);
  g.fillText(`${Math.hypot(N, E).toFixed(0)} m`, W - 48, W - 14);
}
/** GPS en un mundo real: el mapa entero (terreno, carreteras, pueblos) se pinta una vez en un lienzo a 2 px por nodo
 *  de la malla y cada cuadro se recorta la zona de +-3 km alrededor del avion, con el origen marcado y, si queda
 *  fuera, una flecha hacia el. */
/** dron comercial: como en las apps de los drones comerciales, el punto de despegue con su H amarilla y una linea del dron hasta el (recortada al mapa). */
const esDJI = () => !!(modelo && modelo.esCuadricoptero && !modelo.esFPV);
function casaDJI(g, x0, y0, xh, yh, W) {
  let dx = xh - x0, dy = yh - y0; const m = Math.max(Math.abs(xh - W / 2), Math.abs(yh - W / 2)), dentro = m <= W / 2 - 8;
  if (!dentro) { const k = Math.min(1, ...[dx > 0 ? (W - 3 - x0) / dx : dx < 0 ? (3 - x0) / dx : 1, dy > 0 ? (W - 3 - y0) / dy : dy < 0 ? (3 - y0) / dy : 1]); dx *= k; dy *= k; }
  g.save(); g.strokeStyle = "rgba(255,255,255,0.9)"; g.lineWidth = 1.5; g.setLineDash([4, 3]);
  g.beginPath(); g.moveTo(x0, y0); g.lineTo(x0 + dx, y0 + dy); g.stroke(); g.setLineDash([]);
  if (dentro) {
    g.fillStyle = "#ffc83d"; g.strokeStyle = "#000"; g.lineWidth = 1; g.beginPath(); g.arc(xh, yh, 7, 0, 2 * Math.PI); g.fill(); g.stroke();
    g.fillStyle = "#111"; g.font = "bold 10px sans-serif"; g.textAlign = "center"; g.fillText("H", xh, yh + 3.5);
  }
  g.restore();
}
function pintarGPSMundo(cv, rumbo, N, E) {
  const M = entorno.mundo, T = M.terreno, PX = 2, g = cv.getContext("2d"), W = cv.width;
  if (!GPS.mapa) {
    const c = document.createElement("canvas"); c.width = T.nE * PX; c.height = T.nN * PX; const m = c.getContext("2d");
    const X = e => (e - T.E0) / T.paso * PX, Y = n => (T.nN - 1 - (n - T.N0) / T.paso) * PX;
    if (visor.lienzoMundo) m.drawImage(visor.lienzoMundo, 0, 0, visor.lienzoMundo.width, visor.lienzoMundo.height, 0, Y(T.N0 + (T.nN - 1) * T.paso), (T.nE - 1) * PX, (T.nN - 1) * PX);
    else { m.fillStyle = "#8a8a7a"; m.fillRect(0, 0, c.width, c.height); }
    for (const t of [4, 3, 2, 1]) {
      m.strokeStyle = { 1: "#ffb74d", 2: "#fff176", 3: "#f5f5f5", 4: "#cfd8dc" }[t]; m.lineWidth = { 1: 2.2, 2: 1.6, 3: 1.1, 4: 0.8 }[t]; m.beginPath();
      for (const cc of M.carreteras) { if (cc[0] !== t) continue; for (let i = 1; i < cc.length; i += 2) i === 1 ? m.moveTo(X(cc[i]), Y(cc[i + 1])) : m.lineTo(X(cc[i]), Y(cc[i + 1])); }
      m.stroke();
    }
    GPS.mapa = c; GPS.X = X; GPS.Y = Y;
  }
  // un dron trabaja a unos cientos de metros: su mapa abre a +-400 m; un avion, a +-3 km
  const semi = (modelo && modelo.esCuadricoptero && !modelo.esFPV ? 400 : 3000) * GPS.zoom, k = W / (2 * semi), mpx = PX / T.paso;   // m -> px del mapa; la rueda cambia el zoom
  g.clearRect(0, 0, W, W); g.fillStyle = "#0b0f14"; g.fillRect(0, 0, W, W);
  const sx = GPS.X(E) - semi * mpx, sy = GPS.Y(N) - semi * mpx, sw = 2 * semi * mpx;
  g.imageSmoothingEnabled = true; g.drawImage(GPS.mapa, sx, sy, sw, sw, 0, 0, W, W);
  const X = e => W / 2 + (e - E) * k, Y = n => W / 2 - (n - N) * k;
  GPS.vm = { N, E, k, W };
  for (const t of visor.mapaZonas || []) {           // dentro de las zonas de detalle, su ortofoto (0,25-0,5 m) encima
    const img = t.tex.image;
    if (!img || !(img.naturalWidth || img.width) || t.E0 > E + semi || t.E0 + t.lado < E - semi || t.N0 > N + semi || t.N0 + t.lado < N - semi) continue;
    g.drawImage(img, X(t.E0), Y(t.N0 + t.lado), t.lado * k, t.lado * k);       // la fila de arriba de la foto es el norte
  }
  const PL = (ESCENARIOS[sesion.escenario].operacion || {}).planta;   // paneles: las filas de la planta, que no estan en la ortofoto
  if (PL && PL.rumbo === undefined) {                                  // con rumbo (SABIC) las filas ya estan en la ortofoto
    const fondo = PL.ancho * Math.cos(PL.inclinacion * D2R); g.fillStyle = "#182c52";
    for (let i = 0; i < PL.filas; i++) { const n = PL.n0 + i * PL.separacion; g.fillRect(X(PL.e0), Y(n + fondo / 2), PL.largo * k, Math.max(1, fondo * k)); }
  }
  const OPv = ev && ev.op && Array.isArray(ev.op.d.vertidos) ? ev.op : null;
  if (OPv) {                                                          // patrulla: los sectores del aviso (verdes los ya fotografiados)
    g.save(); g.setLineDash([6, 4]); g.lineWidth = 2; g.font = "bold 11px sans-serif"; g.textAlign = "center";
    OPv.d.sectores.forEach(([sn, se], i) => {
      const col = OPv.hechos[i] ? "#66bb6a" : "#ff9800"; g.strokeStyle = col; g.fillStyle = col;
      g.beginPath(); g.arc(X(se), Y(sn), Math.max(6, OPv.d.radio_sector * k), 0, 2 * Math.PI); g.stroke(); g.fillText(String(i + 1), X(se), Y(sn) + 4);
    });
    g.restore();
  }
  const OPr = ev && ev.op && ev.op.d.recon ? ev.op : null;
  if (OPr) {                                                          // reconocimiento: puntos de control (verdes los hechos), objetivo y zona
    const R = OPr.d.recon; g.save(); g.lineWidth = 2; g.font = "bold 11px sans-serif"; g.textAlign = "center";
    (R.puntos || []).forEach((q, i) => { const col = OPr.hechos[i] ? "#66bb6a" : "#ff9800"; g.strokeStyle = col; g.fillStyle = col; g.beginPath(); g.arc(X(q.e), Y(q.n), Math.max(6, 60 * k), 0, 2 * Math.PI); g.stroke(); g.fillText(String(i + 1), X(q.e), Y(q.n) + 4); });
    if (R.objetivo) { g.strokeStyle = OPr.fotoObj ? "#66bb6a" : "#e53935"; g.setLineDash([6, 4]); g.beginPath(); g.arc(X(R.objetivo.e), Y(R.objetivo.n), Math.max(6, R.ruido_r * k), 0, 2 * Math.PI); g.stroke(); g.setLineDash([]); }
    if (R.zona) { const Z = R.zona; g.strokeStyle = "#fdd835"; g.setLineDash([6, 4]); g.strokeRect(X(Z.e0), Y(Z.n1), (Z.e1 - Z.e0) * k, (Z.n1 - Z.n0) * k); g.setLineDash([]); }
    g.restore();
  }
  if (piloto) {                                                       // UAV: la pista y lo que pide el piloto automatico
    const P = piloto.pista;
    if (P) { const r = P.rumbo * D2R, a = P.ancho / 2, c = [[0, -a], [P.largo, -a], [P.largo, a], [0, a]].map(([d, t]) => [P.n + d * Math.cos(r) - t * Math.sin(r), P.e + d * Math.sin(r) + t * Math.cos(r)]);
             g.fillStyle = "#3a3f44"; g.strokeStyle = "#fff"; g.lineWidth = 1; g.beginPath(); c.forEach(([n, e], i) => i ? g.lineTo(X(e), Y(n)) : g.moveTo(X(e), Y(n))); g.closePath(); g.fill(); g.stroke(); }
    if ((piloto.modo === "PUNTO" || piloto.modo === "BASE") && piloto.c.punto) {
      const [pn, pe] = piloto.c.punto; g.strokeStyle = "#4dd0e1"; g.lineWidth = 2; g.setLineDash([5, 4]);
      g.beginPath(); g.arc(X(pe), Y(pn), Math.max(4, piloto.P.radio_orbita * k), 0, 2 * Math.PI); g.stroke(); g.setLineDash([]);
      g.beginPath(); g.moveTo(X(pe) - 5, Y(pn)); g.lineTo(X(pe) + 5, Y(pn)); g.moveTo(X(pe), Y(pn) - 5); g.lineTo(X(pe), Y(pn) + 5); g.stroke();
    }
  }
  const OPf = ev && ev.op && ev.op.d.racks ? ev.op : null;
  if (OPf) {                                                          // fabrica: las pistas (racks con puntos calientes, unidad con la fuga y su ATEX, antorcha)
    g.save(); g.lineCap = "round"; g.lineJoin = "round";
    const U = OPf.unidadFuga.poligono, contorno = () => { g.beginPath(); U.forEach(([n, e], i) => i ? g.lineTo(X(e), Y(n)) : g.moveTo(X(e), Y(n))); g.closePath(); };
    contorno(); g.strokeStyle = "rgba(229,57,53,0.35)"; g.lineWidth = Math.max(3, 2 * OPf.d.atex * k); g.stroke();
    contorno(); g.fillStyle = "rgba(229,57,53,0.55)"; g.fill(); g.strokeStyle = "#e53935"; g.lineWidth = 2; g.stroke();
    g.strokeStyle = "#ff9800"; g.lineWidth = 3; g.setLineDash([6, 4]);
    for (const ri of OPf.racksPista) { const R = OPf.d.racks[ri]; g.beginPath(); g.moveTo(X(R.e0), Y(R.n0)); g.lineTo(X(R.e1), Y(R.n1)); g.stroke(); }
    g.setLineDash([]); const A = OPf.d.antorcha;
    g.fillStyle = "#ffb300"; g.strokeStyle = "#000"; g.lineWidth = 1; g.beginPath(); g.arc(X(A.e), Y(A.n), 6, 0, 2 * Math.PI); g.fill(); g.stroke();
    g.fillStyle = "#000"; g.font = "bold 9px sans-serif"; g.textAlign = "center"; g.fillText("A", X(A.e), Y(A.n) + 3); g.textAlign = "start";
    g.restore();
  }
  g.fillStyle = "#fff"; g.font = "bold 10px sans-serif";
  for (const [nombre, rango, e, n] of M.lugares) if (rango <= (semi < 5000 ? 5 : 3) && Math.abs(e - E) < semi && Math.abs(n - N) < semi) { g.fillText(nombre, X(e) + 3, Y(n) - 3); g.fillRect(X(e) - 1.5, Y(n) - 1.5, 3, 3); }
  if (GPS.estela.length > 1) { g.strokeStyle = "rgba(255,213,79,0.8)"; g.lineWidth = 1.5; g.beginPath(); GPS.estela.forEach(([n, e], i) => i ? g.lineTo(X(e), Y(n)) : g.moveTo(X(e), Y(n))); g.lineTo(W / 2, W / 2); g.stroke(); }
  const C = casa(), d = Math.hypot(N - C.N, E - C.E);                                 // casa = punto de lanzamiento
  if (esDJI()) casaDJI(g, W / 2, W / 2, X(C.E), Y(C.N), W);
  if (Math.abs(E - C.E) < semi && Math.abs(N - C.N) < semi) { g.fillStyle = "#fff"; g.beginPath(); g.arc(X(C.E), Y(C.N), 3.5, 0, 2 * Math.PI); g.fill(); }
  else { const a = Math.atan2(C.E - E, C.N - N); g.save(); g.translate(W / 2 + Math.sin(a) * (W / 2 - 14), W / 2 - Math.cos(a) * (W / 2 - 14)); g.rotate(a); g.fillStyle = "#fff"; g.beginPath(); g.moveTo(0, -7); g.lineTo(5, 5); g.lineTo(-5, 5); g.closePath(); g.fill(); g.restore(); }
  pintarOtrosGPS(g, X, Y, W);
  g.save(); g.translate(W / 2, W / 2); g.rotate(rumbo * D2R);
  g.fillStyle = "#ffd54f"; g.strokeStyle = "#000"; g.lineWidth = 1; g.beginPath(); g.moveTo(0, -9); g.lineTo(6, 7); g.lineTo(0, 4); g.lineTo(-6, 7); g.closePath(); g.fill(); g.stroke(); g.restore();
  const vto = entorno.viento;
  if (vto.base > 0.3) { g.save(); g.translate(W - 18, 18); g.rotate(vto.rumbo); g.strokeStyle = "#4fc3f7"; g.lineWidth = 2; g.beginPath(); g.moveTo(0, 8); g.lineTo(0, -8); g.lineTo(-4, -3); g.moveTo(0, -8); g.lineTo(4, -3); g.stroke(); g.restore(); }
  g.fillStyle = "#e6edf3"; g.font = "bold 11px sans-serif"; g.fillText("N", 6, 14);
  const suelo = entorno.altura(N, E);
  g.font = "bold 12px sans-serif"; g.fillText(`alt ${Math.max(0, -av.p[2] - suelo).toFixed(0)} m`, 6, 30);
  if (av.motorRoto) { g.fillStyle = "#ff5252"; g.fillText("MOTOR PARADO", 6, 46); }
  const esc = escalaRedonda(semi); g.strokeStyle = "#e6edf3"; g.lineWidth = 2; g.beginPath(); g.moveTo(8, W - 10); g.lineTo(8 + esc * k, W - 10); g.stroke();
  g.font = "10px sans-serif"; g.fillText(esc >= 1000 ? esc / 1000 + " km" : esc + " m", 10, W - 14); g.fillText(`casa ${d >= 1000 ? (d / 1000).toFixed(1) + " km" : d.toFixed(0) + " m"}`, W - 62, W - 14);
}
// ---- escrituras al HUD solo cuando cambia lo escrito: asignar innerHTML, textContent, className o un atributo rehace
// nodos y maquetacion aunque sea lo mismo, y el HUD se repinta en cada cuadro. Los elementos se buscan una sola vez.
// Todo lo que escribe en estos elementos pasa por aqui (si no, la copia guardada se quedaria vieja).
const HUD_EL = {};
const $h = id => HUD_EL[id] || (HUD_EL[id] = document.getElementById(id));
function ponerHTML(el, s) { if (el._html !== s) { el._html = s; el.innerHTML = s; } }
function ponerTxt(el, s) { if (el._txt !== s) { el._txt = s; el.textContent = s; } }
function ponerClase(el, s) { if (el._clase !== s) { el._clase = s; el.className = s; } }
function ponerAttr(el, k, s) { if (el["_a_" + k] !== s) { el["_a_" + k] = s; el.setAttribute(k, s); } }
function ponerEstilo(el, k, s) { if (el["_s_" + k] !== s) { el["_s_" + k] = s; el.style[k] = s; } }
function pintarHorizonte(roll, pitch, rumbo) {
  const el = $h("horizonte"), ver = visor.camara === 2 || visor.camara === 3;
  ponerEstilo(el, "display", ver ? "block" : "none");
  document.body.classList.toggle("cam1", !ver);
  // relojes solo en las camaras 2 y 3: en la del piloto su sitio lo ocupa el GPS (en el campo no hay relojes, pero si movil con mapa)
  for (const id of ["anemometro", "variometro"]) ponerEstilo($h(id), "display", (av.estado === "en mano" && !vuelo) || !ver ? "none" : "block");
  if (!ver) return;
  ponerAttr($h("hzRosa"), "transform", `rotate(${-rumbo} 150 150)`);
  // marcas sobre la rosa (giran con ella): casa = hacia el piloto, pista = eje de la pista, viento = de donde viene
  const casa = Math.atan2(-av.p[1], -av.p[0]) * R2D, vto = entorno.viento, desde = (vto.rumbo * R2D + 180) % 360;
  ponerAttr($h("hzCasa"), "transform", `rotate(${casa - rumbo} 150 150)`);
  ponerAttr($h("hzPista"), "transform", `rotate(${(ev && ev.zona === 2 ? 180 : 0) - rumbo} 150 150)`);
  ponerAttr($h("hzViento"), "transform", `rotate(${desde - rumbo} 150 150)`);
  ponerEstilo($h("hzViento"), "display", vto.base > 0.3 ? "" : "none");
  ponerAttr($h("hzActitud"), "transform", `rotate(${-roll} 150 150) translate(0 ${pitch * HZ_PX_GRADO})`);
  ponerTxt($h("hzRumbo"), `${String(Math.round((rumbo + 360) % 360) % 360).padStart(3, "0")}°`);
}
function aviso(txt) { document.getElementById("aviso").textContent = txt; }
function toast(txt) { if (typeof RegistroVuelo !== "undefined" && typeof vuelo !== "undefined" && av && av.estado === "volando") RegistroVuelo.evento(vuelo, txt); const el = document.getElementById("toast"); el.textContent = txt; clearTimeout(tToast); tToast = setTimeout(() => el.textContent = "", 1500); }
let CARRERA_MEJOR = null;                                            // carrera: el mejor tiempo de esta sesion {t, avion}
/** Carrera: la barra de arriba (el mejor de la sala o de la sesion, el cronometro y el obstaculo que toca) y el
 *  indicador del siguiente obstaculo: un rombo con su numero y la distancia encima de el o, si no esta a la vista, una
 *  flecha en el borde de la pantalla hacia donde esta. Como hudCarrera de principal.gd. */
function hudCarrera() {
  const bar = document.getElementById("carreraBar"), cv = document.getElementById("carreraMarca"), op = ev && ev.op, C = op && op.carr;
  if (!C) { ponerEstilo(bar, "display", "none"); ponerEstilo(cv, "display", "none"); return; }
  ponerEstilo(bar, "display", "block"); ponerEstilo(cv, "display", "block");
  const nom = id => (Modelos.datos(id) || { nombre: id }).nombre, R = MULTI.sala ? MULTI.sala.record : null;
  ponerHTML(document.getElementById("carreraRecord"), MULTI.sala
    ? (R ? `🏆 Mejor de la sala: ${esc(String(R.nombre).slice(0, 30))} · ${opCrono(R.t)} (${esc(nom(R.avion))})` : "🏆 Sala: nadie ha terminado todavía")
    : CARRERA_MEJOR ? `🏆 Tu mejor de la sesión: ${opCrono(CARRERA_MEJOR.t)} (${esc(nom(CARRERA_MEJOR.avion))})` : "🏆 Sin tiempo todavía en esta sesión");
  const n = op.obst.length, t = C.tFin !== null ? C.tFin - C.t0 : C.t0 !== null ? av.t - C.t0 : 0;
  bar.classList.toggle("fuera", C.fuera !== null);
  ponerHTML(document.getElementById("carreraCrono"), C.fuera !== null ? `DESCALIFICADO<small>te saltaste el ${C.fuera + 1}</small>`
    : `${opCrono(t)}<small>${C.tFin !== null ? "¡META!" : `${C.k + 1}/${n}`}</small>`);
  if (visor.resaltarCarrera) visor.resaltarCarrera(C.fuera !== null || C.tFin !== null ? -1 : C.k);
  // el indicador
  const W = innerWidth, H = innerHeight;
  if (cv.width !== W || cv.height !== H) { cv.width = W; cv.height = H; }
  const g = cv.getContext("2d"); g.clearRect(0, 0, W, H);
  const s = op.siguiente(av); if (!s || av.estado === "roto") return;
  const yc = s.o.tipo === "picado" ? s.o.y0 : s.o.y0 + s.o.alto / 2, q = ned2three([s.o.n, s.o.e, -yc]), v = new THREE.Vector3(q[0], q[1], q[2]).project(visor.cam);
  const detras = v.z > 1, x = (v.x + 1) / 2 * W, y = (1 - v.y) / 2 * H, m = 46, txt = `${s.i + 1} · ${s.d < 1000 ? s.d.toFixed(0) + " m" : (s.d / 1000).toFixed(1).replace(".", ",") + " km"}`;
  g.font = "bold 15px sans-serif"; g.textAlign = "center"; g.lineWidth = 3; g.strokeStyle = "rgba(0,0,0,.75)";
  if (!detras && x > m && x < W - m && y > m && y < H - m) {               // a la vista: un rombo encima
    g.fillStyle = "rgba(102,187,106,.25)"; g.strokeStyle = "#66bb6a"; g.lineWidth = 3;
    g.beginPath(); g.moveTo(x, y - 18); g.lineTo(x + 18, y); g.lineTo(x, y + 18); g.lineTo(x - 18, y); g.closePath(); g.fill(); g.stroke();
    g.lineWidth = 3; g.strokeStyle = "rgba(0,0,0,.75)"; g.fillStyle = "#fff"; g.strokeText(txt, x, y - 26); g.fillText(txt, x, y - 26);
    return;
  }
  let dx = x - W / 2, dy = y - H / 2; if (detras) { dx = -dx; dy = -dy; }  // fuera de la vista: una flecha en el borde
  if (Math.hypot(dx, dy) < 1) dy = 1;
  const mv = dy < 0 ? H * 0.26 + 80 : m;                               // arriba, por debajo de la barra de la carrera
  const k = Math.min((W / 2 - m) / Math.abs(dx || 1e-9), (H / 2 - mv) / Math.abs(dy || 1e-9)), ax = W / 2 + dx * k, ay = H / 2 + dy * k, a = Math.atan2(dy, dx);
  g.save(); g.translate(ax, ay); g.rotate(a); g.fillStyle = "#66bb6a"; g.strokeStyle = "rgba(0,0,0,.75)"; g.lineWidth = 2;
  g.beginPath(); g.moveTo(22, 0); g.lineTo(-10, -16); g.lineTo(-4, 0); g.lineTo(-10, 16); g.closePath(); g.fill(); g.stroke(); g.restore();
  g.lineWidth = 3; g.fillStyle = "#fff"; const tx = ax - Math.cos(a) * 34, ty = ay - Math.sin(a) * 34 + 5; g.strokeText(txt, tx, ty); g.fillText(txt, tx, ty);
}
function hud() {
  hudCarrera();
  const el = $h("hud");
  const [roll, pitch, yaw] = Cuat.euler(av.q).map(a => a * R2D), h = Math.max(0, -av.p[2]), dist = Math.hypot(av.p[0] - casa().N, av.p[1] - casa().E);
  const vn = Cuat.rot(av.q, av.v), vs = -vn[2], vto = entorno.viento, suelo = entorno.altura ? entorno.altura(av.p[0], av.p[1]) : 0;
  // estado (arriba a la izquierda) y lecturas (abajo, en el centro): lo que importa en un vuelo RC
  const estadoTxt = Repeticion.activa ? "REPETICIÓN" : av.estado === "en mano" && modelo.esCuadricoptero ? "EN EL SUELO" : av.estado === "en mano" && modelo.tren ? "MOTOR PARADO" : av.estado.toUpperCase();
  ponerHTML($h("estado"), `<span class="pill">${esc(estadoTxt)} · ${av.t.toFixed(0)} s</span>` +
    (vuelo && av.estado === "volando" ? '<span class="pill rec">● REC</span>' : "") + (av.motorRoto ? '<span class="pill rec">MOTOR PARADO</span>' : "") +
    (modelo.facil ? '<span class="pill">física fácil</span>' : "") + (pausado ? '<span class="pill">PAUSA</span>' : ""));
  if (modelo.esCuadricoptero && av.estado === "volando" && !av.posado && document.getElementById("aviso").textContent.startsWith("Sube el gas")) aviso("");
  if (modelo.esBipode) { hudBip(dist, yaw); pintarGPS(yaw); return; }
  const bat = modelo.bateriaPct(av), vClase = AN.vs > 0 && av.V < 1.1 * AN.vs ? "rojo" : AN.vs > 0 && av.V < 1.3 * AN.vs ? "ambar" : "";
  ponerHTML($h("lecturas"), ((av.estado === "en mano" && !vuelo) || sinInstrumentos) ? "" :
    `<div class="lect ${vClase}"><b>${av.V.toFixed(1)}</b><span>vel. aire m/s</span></div><div class="lect"><b>${(-av.p[2] - suelo).toFixed(0)}</b><span>altura m</span></div>` +
    `<div class="lect"><b>${vs >= 0 ? "+" : ""}${vs.toFixed(1)}</b><span>asc. m/s</span></div><div class="lect"><b>${((yaw + 360) % 360).toFixed(0).padStart(3, "0")}°</b><span>rumbo</span></div>` +
    `<div class="lect"><b>${dist.toFixed(0)}</b><span>dist. m</span></div><div class="lect ${bat < 20 ? "rojo" : ""}"><b>${bat.toFixed(0)}%</b><span>${modelo.propulsion.combustible ? "combustible" : "batería"}</span></div>` +
    (av.perdida > 0.5 && !av.enTierra ? `<div class="lect rojo"><b>¡PÉRDIDA!</b><span>alfa ${av.alfa.toFixed(0)}°</span></div>` : ""));
  // datos completos en texto (tecla H)
  ponerEstilo(el, "display", mostrarHud ? "block" : "none");
  if (mostrarHud) ponerHTML(el,
    `vel. aire <b>${av.V.toFixed(1)}</b> m/s · suelo ${Math.hypot(vn[0], vn[1]).toFixed(1)} m/s · asc. ${vs >= 0 ? "+" : ""}${vs.toFixed(1)} m/s<br>` +
    `altura <b>${h.toFixed(1)}</b> m${entorno.altura ? ` (sobre el terreno ${(h - entorno.altura(av.p[0], av.p[1])).toFixed(0)} m)` : ""} · distancia ${dist.toFixed(0)} m<br>` +
    `alabeo ${roll.toFixed(0)}° · cabeceo ${pitch.toFixed(0)}° · rumbo ${((yaw + 360) % 360).toFixed(0)}°<br>` +
    `alfa ${av.alfa.toFixed(1)}° ${av.perdida > 0.5 ? "<b>¡PÉRDIDA!</b>" : ""} · carga ${av.g_carga.toFixed(1)} g<br>` +
    `gases <b>${(av.gases * 100).toFixed(0)} %</b> · batería ${modelo.bateriaPct(av).toFixed(0)} %<br>` +
    `viento ${vto.base.toFixed(0)} m/s${vto.rachas ? " con rachas" : ""} · compensador ${mando.trim.toFixed(2)}° · cámara ${visor.camara}` +
    (cmEsDiseno(sesion.avion) ? "" : `<br><b style="color:#ffb74d">${textoCM()}</b>`));
  const L = entorno.limites, lejos = $h("lejos");
  if (av.estado === "volando" && !entorno.mundo && dist > L.aviso_m) {
    const haciaCasa = ((Math.atan2(-av.p[1], -av.p[0]) * R2D + 360) % 360).toFixed(0);
    ponerTxt(lejos, `¡Demasiado lejos! (${dist.toFixed(0)} m) Da la vuelta: el campo está al rumbo ${haciaCasa}°. A ${L.distancia_m} m se pierde el avión.`);
  } else ponerTxt(lejos, av.estado === "en mano" ? avisoLanzamiento() : "");
  ponerEstilo($h("gasesBarra"), "height", (av.gases * 100) + "%");
  pintarHorizonte(roll, pitch, yaw); pintarInstrumentos(av.V, vs); pintarGPS(yaw);
  ponerEstilo($h("reconMira"), "display", visor.camara === 3 && !modelo.esCuadricoptero && !modelo.uav && ev && ev.op && ev.op.d.recon ? "block" : "none");   // reconocimiento con un avion: la mira de la camara de a bordo
  if (modelo.esFPV) { hudFpv(h, vn); ponerEstilo($h("fpv"), "display", sinInstrumentos ? "none" : ""); }
  else if (modelo.esCuadricoptero) { hudDji(h, vn, vs, dist); ponerEstilo($h("dji"), "display", sinInstrumentos ? "none" : ""); }
  else if (modelo.uav) { hudUav(h, vn, vs, dist, yaw); ponerEstilo($h("gcs"), "display", sinInstrumentos ? "none" : ""); }
  if (sinInstrumentos) for (const id of ["horizonte", "gps", "anemometro", "variometro"]) ponerEstilo($h(id), "display", "none");
  ponerEstilo($h("barra"), "display", sinInstrumentos ? "none" : "");       // sin instrumentos: tampoco gas ni palanca (como en el campo)
  ponerEstilo($h("punto"), "left", (50 + 45 * mando.yaw) + "%");
  ponerEstilo($h("punto"), "top", (50 + 45 * mando.pitch) + "%");
}
/** Estacion de control del UAV (#gcs): modo y estado, enlace y combustible, consignas del piloto automatico, botones y
 *  la mira de la torreta (en la camara 3) con lo que ve: sensor, zoom, giro e inclinacion, el punto de la cruz y su
 *  distancia; y la escala de temperaturas con la termica. */
function hudUav(h, vn, vs, dist, yaw) {
  const m = piloto ? piloto.modo : "MANUAL", auto = !["MANUAL", "ESTAB"].includes(m), pistaM = m === "DESPEGUE" || m === "ATERRIZAJE" || m === "LANZAMIENTO";
  ponerTxt($h("gcsModo"), piloto ? PUAV_NOMBRE[m].toUpperCase() : "MANUAL"); ponerClase($h("gcsModo"), "modo" + (pistaM ? " pista" : auto ? " auto" : ""));
  const suelo = entorno.altura ? entorno.altura(av.p[0], av.p[1]) : 0, agl = -av.p[2] - suelo;
  const est = Repeticion.activa ? "REPETICIÓN" : av.estado === "en mano" ? "MOTOR PARADO · L arranca" : av.estado === "volando" ? (av.enTierra ? (av.frenoAparc ? "EN TIERRA · FRENO DE APARCAMIENTO (espacio)" : "EN TIERRA") : "EN VUELO")
            : av.estado.toUpperCase();
  ponerTxt($h("gcsEstado"), `${est} · ${(av.V * 3.6).toFixed(0)} km/h · ${agl.toFixed(0)} m · rumbo ${((yaw + 360) % 360).toFixed(0).padStart(3, "0")}°` + (pausado ? " · PAUSA" : ""));
  const comb = modelo.bateriaPct(av), P = modelo.propulsion, gm = av.gasMotor !== undefined ? av.gasMotor : av.gases;
  const h_rest = comb / 100 * P.masa_bateria_Wh / Math.max(500, P.P_max_W * gm * gm * gm), dLink = dist / 1000;
  ponerTxt($h("gcsEnlace"), `ENLACE ${dLink < 60 ? "▮▮▮▮" : dLink < 100 ? "▮▮▮" : "▮"} ${dLink.toFixed(1).replace(".", ",")} km`);
  ponerTxt($h("gcsComb"), `COMB ${comb.toFixed(0)} %` + (av.estado === "volando" && gm > 0.05 ? ` · ${Math.floor(h_rest)}:${String(Math.floor((h_rest % 1) * 60)).padStart(2, "0")} h` : ""));
  const c = piloto && piloto.c;
  ponerHTML($h("gcsConsignas"), !piloto || !auto ? "" : pistaM ? `${PUAV_NOMBRE[m]} · fase ${piloto.fase}` :
    `ALT ${(c.alt - suelo).toFixed(0)} m s/t · VEL ${(c.vel * 3.6).toFixed(0)} km/h` + (m === "CRUCERO" ? ` · RUMBO ${(((c.rumbo * R2D) % 360 + 360) % 360).toFixed(0).padStart(3, "0")}°` : ` · PUNTO a ${(Math.hypot(av.p[0] - c.punto[0], av.p[1] - c.punto[1]) / 1000).toFixed(1).replace(".", ",")} km`));
  for (const b of document.querySelectorAll("#gcsDer button[data-modo]")) ponerClase(b, (b.dataset.modo === m || (b.dataset.modo === "AUTO" && pistaM)) ? "activo" : "");
  ponerTxt(document.querySelector('#gcsDer button[data-modo="AUTO"]'), av.enTierra ? "ATO" : "ATL");
  // torreta
  const cm = camDJI(), cam3 = visor.camara === 3, tr = av.torreta || { pan: 0, tilt: 0 };
  ponerTxt($h("gcsZoomTxt"), cm.zoom + "x"); ponerClase($h("gcsIR"), cm.termica ? "activo" : ""); ponerClase($h("gcsFijar"), UAV.fijo ? "activo" : "");
  visor.zoomCam = cam3 ? cm.zoom : 1; visor.termica = cam3 && cm.termica;
  ponerEstilo($h("gcsMira"), "display", cam3 ? "block" : "none");
  ponerEstilo($h("gcsSinVideo"), "display", cam3 && modelo.efe && modelo.efe.sinVideo ? "flex" : "none");     // el Grajo con el morro sin asegurar
  ponerEstilo($h("gcsPaleta"), "display", cam3 && cm.termica ? "block" : "none");
  ponerEstilo($h("gcsSensor"), "display", cam3 ? "block" : "none");
  if (cam3) {
    const X = UAV.cruz, L = ev && ev.op ? ev.op.lectura : null;
    ponerHTML($h("gcsObj"), (UAV.fijo ? '<span class="fijo">FIJADO</span><br>' : "") +
      (X && entorno.mundo ? `${coordTxt(X[0], X[1])}<br>${X[3] < 1000 ? X[3].toFixed(0) + " m" : (X[3] / 1000).toFixed(2).replace(".", ",") + " km"}` : "sin punto en el suelo") +
      (cm.termica && L ? `<br><span class="temp">${L.T.toFixed(1).replace(".", ",")} °C</span>` : ""));
    ponerHTML($h("gcsSensor"), `${cm.termica ? "IR" : "EO"} ${cm.zoom}×<br>AZ ${(((tr.pan * R2D) % 360 + 360) % 360).toFixed(0).padStart(3, "0")}° EL ${(tr.tilt * R2D).toFixed(0)}°<br>FOV ${visor.cam.fov.toFixed(1)}°`);
  }
}
/** Lecturas del bipode (abajo): velocidad, rumbo, cintura, brazos, pendiente y distancia. */
function hudBip(dist, yaw) {
  const pend = av.pendiente ? (av.pendiente[0] * Math.cos(av.rumbo) + av.pendiente[1] * Math.sin(av.rumbo)) * 100 : 0;
  const cint = ((av.cintura * R2D + 180) % 360 + 360) % 360 - 180;
  ponerHTML($h("lecturas"), (av.estado === "en mano" && !vuelo) || sinInstrumentos ? "" :
    `<div class="lect"><b>${(av.vel * 3.6).toFixed(1)}</b><span>km/h</span></div><div class="lect"><b>${((yaw + 360) % 360).toFixed(0).padStart(3, "0")}°</b><span>rumbo</span></div>` +
    `<div class="lect"><b>${cint >= 0 ? "+" : ""}${cint.toFixed(0)}°</b><span>cintura</span></div><div class="lect"><b>${(av.brazos * R2D).toFixed(0)}°</b><span>brazos</span></div>` +
    `<div class="lect ${Math.abs(pend) > 45 ? "ambar" : ""}"><b>${pend >= 0 ? "+" : ""}${pend.toFixed(0)} %</b><span>pendiente</span></div><div class="lect"><b>${dist.toFixed(0)}</b><span>dist. m</span></div>`);
  ponerHTML($h("estado"), `<span class="pill">${Repeticion.activa ? "REPETICIÓN" : av.estado === "en mano" ? "PARADO" : "EN MARCHA"} · ${av.t.toFixed(0)} s</span>` + (pausado ? '<span class="pill">PAUSA</span>' : ""));
  if (av.estado === "en mano") ponerTxt($h("lejos"), "");
}
