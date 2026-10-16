"use strict";
// =====================================================================
//  MODO TALLER (pantalla #pTaller; pantalla_taller.gd en Godot, igual): se elige un vehiculo, se "conecta" y se
//  descargan sus registros de vuelo (js/registro.js: los de este ordenador y, con el alumno en el aula, los suyos del
//  servidor), como los de un dron comercial. De cada vuelo: un resumen (duracion, alturas, velocidad, bateria usada,
//  tension minima y desequilibrio de las celdas, corriente y temperatura maximas, avisos), las graficas con el tiempo
//  (bateria y tension, cada celda, corriente y potencia, temperatura, altura y velocidad) con un cursor que da los
//  valores y las marcas de los avisos, la traza del vuelo coloreada por la bateria y la exportacion a CSV.
//  Y la pestana "Revision y reparacion" (js/desgaste.js): horas de vuelo, revisiones (lo que se ve: helices, motores,
//  bateria, autodiagnostico de la app, superficies), reparaciones y el libro de mantenimiento.
// =====================================================================
const Taller = {
  avion: null, lista: null, reg: null, cursor: null, pestana: "registros", vistos: {},

  abrir() {
    if (!Taller.avion || !Taller.ids().includes(Taller.avion)) Taller.avion = Taller.ids().includes(sesion.avion) ? sesion.avion : "DJI_MINI";
    Taller.lista = null; Taller.reg = null; Taller.pestana = "registros"; Taller.vistos = {};
    Taller.pintarVehiculos(); Taller.pintarCentro(); mostrar("pTaller");
  },
  /** Los vehiculos del hangar que llevan registro de vuelo (el bipode no). */
  ids() { return idsHangar().filter(id => !Modelos.crear(id).esTerrestre); },
  /** Los vehiculos, con cuantos registros hay de cada uno en este ordenador. */
  async pintarVehiculos() {
    const cont = document.getElementById("tallerLista"), ids = Taller.ids();
    let cuenta = {}; try { for (const r of await RegistroDB.listar()) cuenta[r.avion] = (cuenta[r.avion] || 0) + 1; } catch (e) {}
    cont.innerHTML = ids.map(id => `<button class="tallerVeh${id === Taller.avion ? " sel" : ""}" data-id="${id}"><b>${esc(Modelos.datos(id).nombre)}</b><span>${cuenta[id] ? cuenta[id] + " registro" + (cuenta[id] > 1 ? "s" : "") + " en este ordenador" : "sin registros en este ordenador"}</span></button>`).join("");
    cont.querySelectorAll("button").forEach(b => b.onclick = () => { Taller.avion = b.dataset.id; Taller.lista = null; Taller.reg = null; Taller.pestana = "registros"; Taller.vistos = {}; Taller.pintarVehiculos(); Taller.pintarCentro(); });
  },
  /** La ficha de la bateria del vehiculo (de sus datos). */
  bateriaTexto(id) {
    const m = Modelos.crear(id), B = m.B;
    if (!B) return "Motor de combustión: el registro da el combustible";
    return `Batería ${B.quimica === "liion" ? "Li-ion" : "LiPo"} ${B.celdas}S de ${Math.round(B.capacidad_mAh)} mAh (${(B.celdas * 3.7 * B.capacidad_mAh / 1000).toFixed(1).replace(".", ",")} Wh)`;
  },
  pintarCentro() {
    const c = document.getElementById("tallerCentro"), A = Modelos.datos(Taller.avion);
    if (Taller.reg) return Taller.pintarDetalle();
    let h = `<div class="capa"><h2>${esc(A.nombre)}</h2><p class="sub">${esc(Taller.bateriaTexto(Taller.avion))}</p>`;
    if (Taller.lista) h += `<div class="pestTaller">${[["registros", "Registros de vuelo"], ["revision", "Revisión y reparación"]].map(([k, t]) =>
      `<button class="btn${Taller.pestana === k ? " prim" : ""}" data-pest="${k}">${t}</button>`).join("")}</div>`;
    if (!Taller.lista) h += `<button class="btn prim grande" id="tallerConectar">🔌 Conectar y descargar los registros</button><div id="tallerProgreso"></div>`;
    else if (Taller.pestana === "revision") h += Taller.htmlRevision();
    else if (!Taller.lista.length) h += `<p>No hay registros de vuelo de este vehículo. Vuela con él y vuelve: cada vuelo guarda su registro al terminar.</p>`;
    else h += `<p class="sub">${Taller.lista.length} registro${Taller.lista.length > 1 ? "s" : ""}. Elige uno para ver sus gráficas.</p><div class="tablaTaller"><table><tr><th>Fecha</th><th>Vuelo</th><th>Duración</th><th>Final</th><th>Muestras</th><th>Dónde</th></tr>${Taller.lista.map((r, i) =>
      `<tr data-i="${i}"><td>${new Date(r.inicio).toLocaleString("es-ES", { dateStyle: "short", timeStyle: "short" })}</td><td>${esc(r.escenario_nombre || r.escenario)}</td><td>${((r.duracion_s || 0) / 60).toFixed(1).replace(".", ",")} min</td><td>${esc(r.final || "")}</td><td>${r.muestras}</td><td>${r._aula ? "☁ aula" : "este ordenador"}</td></tr>`).join("")}</table></div>`;
    c.innerHTML = h + "</div>";
    const b = document.getElementById("tallerConectar"); if (b) b.onclick = () => Taller.conectar();
    c.querySelectorAll("tr[data-i]").forEach(tr => tr.onclick = () => Taller.ver(Taller.lista[+tr.dataset.i]));
    c.querySelectorAll("button[data-pest]").forEach(b => b.onclick = () => { Taller.pestana = b.dataset.pest; Taller.pintarCentro(); });
    c.querySelectorAll("button[data-rev]").forEach(b => b.onclick = () => Taller.revisar(b.dataset.rev));
    c.querySelectorAll("button[data-rep]").forEach(b => b.onclick = () => Taller.reparar(b.dataset.rep));
  },
  /** La pestana de revision y reparacion: horas, revisiones (con lo que se ha visto), reparaciones y libro. */
  htmlRevision() {
    const A = Modelos.datos(Taller.avion), est = Desgaste.estado(Taller.avion), revs = Desgaste.revisiones(A);
    let h = `<p>Horas de vuelo: <b>${fmtHoras(est.horas)}</b>${Desgaste.clase(A) !== "comb" ? ` · Batería: <b>${est.bateria.ciclos} ciclos de carga</b>` : ""}</p>`;
    h += `<h3 class="tituloTaller">Revisar</h3><div class="botonesTaller">${revs.map(([id, t]) => `<button class="btn" data-rev="${id}">${esc(t)}</button>`).join("")}</div>`;
    for (const [id, t] of revs) if (Taller.vistos[id]) h += `<div class="revTaller"><b>${esc(t)}</b><ul>${Taller.vistos[id].map(l => `<li>${esc(l)}</li>`).join("")}</ul></div>`;
    h += `<h3 class="tituloTaller">Reparar</h3><div class="botonesTaller">${Desgaste.reparaciones(A).map(([id, t]) => `<button class="btn" data-rep="${id}">${esc(t)}</button>`).join("")}</div>`;
    h += `<h3 class="tituloTaller">Libro de mantenimiento</h3>` + (est.libro.length ? `<div class="tablaTaller"><table><tr><th>Fecha</th><th>Horas del vehículo</th><th>Trabajo</th></tr>${est.libro.slice().reverse().map(e =>
      `<tr><td>${fmtFecha(e.fecha)}</td><td>${fmtHoras(e.horas)}</td><td>${esc(e.texto)}</td></tr>`).join("")}</table></div>` : `<p class="sub">Sin trabajos todavía.</p>`);
    return h;
  },
  /** Una revision: lo que se ve (Desgaste.revisar), sin decir la averia. */
  revisar(id) { Taller.vistos[id] = Desgaste.revisar(Desgaste.estado(Taller.avion), Modelos.datos(Taller.avion), id); Taller.pintarCentro(); },
  /** Una reparacion: renueva la pieza y lo apunta en el libro de mantenimiento (en el aula, o en el ordenador). */
  async reparar(id) {
    const A = Modelos.datos(Taller.avion), R = Desgaste.reparaciones(A).find(r => r[0] === id);
    if (!R || !await confirmar(R[1], "Se cambia (o se calibra) y queda apuntado en el libro de mantenimiento. Vuela después para comprobar que el vehículo va bien.", "Hacerlo")) return;
    const e = await Desgaste.modificar(Taller.avion, est => Desgaste.reparar(est, A, id, new Date().toISOString()));
    if (!e) { toast("No se ha podido guardar: comprueba la conexión con el aula"); return; }
    Taller.vistos = {}; toast("Hecho: apuntado en el libro de mantenimiento"); Taller.pintarCentro();
  },
  /** "Conecta" con el vehiculo y descarga sus registros: los de este ordenador y, con el alumno en el aula, los suyos. */
  async conectar() {
    const p = document.getElementById("tallerProgreso"), A = Modelos.datos(Taller.avion), pasos = [`Conectando con el ${A.nombre}…`, "Leyendo la memoria de vuelo…", "Descargando los registros…"];
    document.getElementById("tallerConectar").disabled = true;
    for (let i = 0; i < pasos.length; i++) { p.innerHTML = `<div class="barraTaller"><i style="width:${(i + 1) * 33}%"></i></div><p class="sub">${pasos[i]}</p>`; await new Promise(r => setTimeout(r, 450)); }
    let L = []; try { L = await RegistroDB.listar(Taller.avion); } catch (e) {}
    await Desgaste.cargar();                        // y su estado: horas, averias y libro de mantenimiento
    if (sesion.aula && sesion.alumno) {
      try { for (const r of await api("GET", "registros?alumno=" + encodeURIComponent(sesion.alumno.id))) if (r.avion === Taller.avion && !L.some(x => x.id === r.id)) L.push(Object.assign(r, { _aula: true })); } catch (e) {}
    }
    Taller.lista = L.sort((a, b) => b.inicio.localeCompare(a.inicio)); Taller.pintarCentro();
  },
  async ver(meta) {
    let reg = null;
    try { reg = meta._aula ? await api("GET", "registros/" + encodeURIComponent(meta.id) + "?alumno=" + encodeURIComponent(sesion.alumno.id)) : await RegistroDB.leer(meta.id); } catch (e) { toast("No se pudo leer el registro: " + e.message); return; }
    if (!reg) return;
    Taller.reg = reg; Taller.cursor = null; Taller.pintarDetalle();
  },
  /** Columna de un registro como lista de numeros (o null). */
  col(reg, nombre) { const i = reg.columnas.indexOf(nombre); return i < 0 ? null : reg.filas.map(f => f[i]); },
  /** Resumen de un vuelo: [etiqueta, valor] con lo que interesa en el taller. */
  resumen(reg) {
    const C = n => (Taller.col(reg, n) || []).filter(x => typeof x === "number"), mx = a => a.length ? Math.max(...a) : null, mn = a => a.length ? Math.min(...a) : null;
    const f = (x, n, u) => x === null ? "—" : x.toFixed(n).replace(".", ",") + u;
    const celdas = reg.columnas.filter(c => /^celda\d+_V$/.test(c)), b = C("bateria_pct");
    let deseq = null;
    if (celdas.length > 1) { const cs = celdas.map(c => Taller.col(reg, c)); deseq = 0; for (let i = 0; i < reg.filas.length; i++) { const v = cs.map(x => x[i]).filter(x => typeof x === "number"); if (v.length > 1) deseq = Math.max(deseq, Math.max(...v) - Math.min(...v)); } }
    const minCelda = celdas.length ? mn(celdas.flatMap(c => C(c))) : null;
    return [["Duración", f((reg.duracion_s || 0) / 60, 1, " min")], ["Final", reg.final || "—"], ["Altura máxima", f(mx(C("altura_despegue_m")), 0, " m")], ["Distancia máxima", f(mx(C("distancia_m")), 0, " m")],
      ["Velocidad máxima", f(mx(C("velocidad_h_ms")), 1, " m/s")], [reg.bateria ? "Batería usada" : "Combustible usado", b.length ? f(b[0] - b[b.length - 1], 1, " %") + ` (${f(b[0], 0, "")} → ${f(b[b.length - 1], 0, " %")})` : "—"],
      ["Tensión mínima de celda", f(minCelda, 2, " V")], ["Desequilibrio de celdas", deseq === null ? "—" : f(deseq * 1000, 0, " mV")], ["Corriente máxima", f(mx(C("corriente_A")), 1, " A")],
      ["Temperatura máxima", f(mx(C("temperatura_bateria_C")), 1, " °C")], ["Avisos", String(reg.eventos.length)]];
  },
  /** Los paneles de graficas: [titulo, [[columna, color, eje (0 izquierda, 1 derecha)], ...], unidades]. */
  paneles(reg) {
    const celdas = reg.columnas.filter(c => /^celda\d+_V$/.test(c)), COL = ["#4fc3f7", "#ffb74d", "#81c784", "#e57373", "#ba68c8", "#fff176"];
    const P = [["Batería (%) y tensión (V)", [["bateria_pct", "#ffd54f", 0], ["tension_V", "#4fc3f7", 1]], ["%", "V"]],
      ["Celdas (V)", celdas.map((c, i) => [c, COL[i % 6], 0]), ["V", ""]],
      ["Corriente (A) y potencia (W)", [["corriente_A", "#e57373", 0], ["potencia_W", "#ba68c8", 1]], ["A", "W"]],
      ["Temperatura de la batería (°C)", [["temperatura_bateria_C", "#ff8a65", 0]], ["°C", ""]],
      ["Altura sobre el despegue (m) y velocidad (m/s)", [["altura_despegue_m", "#81c784", 0], ["velocidad_h_ms", "#4fc3f7", 1]], ["m", "m/s"]]];
    return P.filter(([, S]) => S.some(([c]) => (Taller.col(reg, c) || []).some(x => typeof x === "number")));
  },
  pintarDetalle() {
    const reg = Taller.reg, c = document.getElementById("tallerCentro");
    c.innerHTML = `<div class="capa"><div style="display:flex;gap:10px;align-items:center;flex-wrap:wrap"><h2 style="margin:0;flex:1">${esc(reg.avion_nombre || reg.avion)} · ${esc(reg.escenario_nombre || reg.escenario)} · ${new Date(reg.inicio).toLocaleString("es-ES", { dateStyle: "short", timeStyle: "short" })}</h2>
      <button class="btn" id="tallerCSV">⬇ Exportar CSV</button><button class="btn" id="tallerLista2">← Registros</button></div>
      <div class="resumenTaller">${Taller.resumen(reg).map(([k, v]) => `<div><span>${esc(k)}</span><b>${esc(v)}</b></div>`).join("")}</div>
      <div class="graficasTaller"><canvas id="tallerGraf"></canvas><div><canvas id="tallerTraza" width="260" height="260"></canvas><div id="tallerEventos" class="eventosTaller"></div></div></div>
      <p class="sub" id="tallerCursor">Pasa el ratón por las gráficas para ver los valores.</p></div>`;
    document.getElementById("tallerLista2").onclick = () => { Taller.reg = null; Taller.pintarCentro(); };
    document.getElementById("tallerCSV").onclick = () => {
      const a = document.createElement("a"), d = new Date(reg.inicio), z = n => String(n).padStart(2, "0");
      a.href = URL.createObjectURL(new Blob([registroCSV(reg)], { type: "text/csv" }));
      a.download = `registro_${reg.avion}_${d.getFullYear()}-${z(d.getMonth() + 1)}-${z(d.getDate())}_${z(d.getHours())}-${z(d.getMinutes())}.csv`;
      document.body.appendChild(a); a.click(); a.remove(); setTimeout(() => URL.revokeObjectURL(a.href), 5000);
    };
    document.getElementById("tallerEventos").innerHTML = reg.eventos.length ? reg.eventos.map(([t, m]) => `<div><b>${Math.floor(t / 60)}:${String(Math.floor(t % 60)).padStart(2, "0")}</b> ${esc(m)}</div>`).join("") : '<div class="sub">Sin avisos</div>';
    const cv = document.getElementById("tallerGraf");
    cv.onmousemove = e => { const r = cv.getBoundingClientRect(); Taller.cursor = (e.clientX - r.left) * cv.width / r.width; Taller.dibujar(); };
    cv.onmouseleave = () => { Taller.cursor = null; Taller.dibujar(); };
    Taller.dibujar(); Taller.traza();
  },
  /** Las graficas apiladas con el tiempo comun; con el cursor, la linea y los valores. */
  dibujar() {
    const reg = Taller.reg, cv = document.getElementById("tallerGraf"); if (!cv || !reg) return;
    const P = Taller.paneles(reg), W = Math.max(400, cv.parentElement.clientWidth - 290), HP = 118, H = P.length * HP + 22;
    if (cv.width !== W || cv.height !== H) { cv.width = W; cv.height = H; }
    const g = cv.getContext("2d"), t = Taller.col(reg, "tiempo_s"), t0 = t[0] || 0, t1 = Math.max(t0 + 1, t[t.length - 1] || 1), x0 = 54, x1 = W - 54;
    const X = s => x0 + (s - t0) / (t1 - t0) * (x1 - x0);
    g.fillStyle = "#0b1119"; g.fillRect(0, 0, W, H); g.font = "11px system-ui, sans-serif";
    let iCur = null;
    if (Taller.cursor !== null && Taller.cursor >= x0 && Taller.cursor <= x1) { const s = t0 + (Taller.cursor - x0) / (x1 - x0) * (t1 - t0); iCur = 0; for (let i = 0; i < t.length; i++) if (Math.abs(t[i] - s) < Math.abs(t[iCur] - s)) iCur = i; }
    const lectura = [];
    P.forEach(([titulo, S, U], k) => {
      const y0 = k * HP + 18, y1 = y0 + HP - 26;
      g.strokeStyle = "rgba(255,255,255,.12)"; g.strokeRect(x0, y0, x1 - x0, y1 - y0); g.fillStyle = "#9fb3c8"; g.fillText(titulo, x0, y0 - 5);
      for (const eje of [0, 1]) {
        const ser = S.filter(s => s[2] === eje); if (!ser.length) continue;
        const vals = ser.flatMap(([c]) => Taller.col(reg, c).filter(x => typeof x === "number")); if (!vals.length) continue;
        let lo = Math.min(...vals), hi = Math.max(...vals); const dec = hi - lo < 5 ? 2 : 0, vHi = hi, vLo = lo;      // las etiquetas, con los valores de verdad (sin el margen)
        if (hi - lo < 1e-6) { lo -= 1; hi += 1; } const m = (hi - lo) * 0.08; lo -= m; hi += m;
        const Y = v => y1 - (v - lo) / (hi - lo) * (y1 - y0);
        g.fillStyle = ser[0][1]; g.textAlign = eje ? "left" : "right";
        g.fillText(vHi.toFixed(dec).replace(".", ",") + (U[eje] ? " " + U[eje] : ""), eje ? x1 + 4 : x0 - 4, Y(vHi) + 4); g.fillText(vLo.toFixed(dec).replace(".", ","), eje ? x1 + 4 : x0 - 4, Y(vLo) + 4);
        g.textAlign = "left";
        for (const [c, color] of ser) {
          const v = Taller.col(reg, c); g.strokeStyle = color; g.lineWidth = 1.5; g.beginPath(); let empezado = false;
          for (let i = 0; i < v.length; i++) { if (typeof v[i] !== "number") { empezado = false; continue; } const x = X(t[i]), y = Y(v[i]); empezado ? g.lineTo(x, y) : g.moveTo(x, y); empezado = true; }
          g.stroke();
          if (iCur !== null && typeof v[iCur] === "number") lectura.push(`<span style="color:${color}">${c.replace(/_/g, " ")}: <b>${v[iCur].toFixed(Math.abs(v[iCur]) < 20 ? 2 : 1).replace(".", ",")}</b></span>`);
        }
      }
    });
    g.fillStyle = "#ffd54f";                                         // marcas de los avisos, arriba
    for (const [s] of reg.eventos) { const x = X(s); g.beginPath(); g.moveTo(x - 4, 2); g.lineTo(x + 4, 2); g.lineTo(x, 9); g.fill(); }
    g.fillStyle = "#9fb3c8"; g.textAlign = "center";
    for (let k = 0; k <= 6; k++) { const s = t0 + k * (t1 - t0) / 6; g.fillText(`${Math.floor(s / 60)}:${String(Math.floor(s % 60)).padStart(2, "0")}`, X(s), H - 4); }
    g.textAlign = "left";
    if (iCur !== null) {
      g.strokeStyle = "rgba(255,255,255,.6)"; g.lineWidth = 1; g.beginPath(); g.moveTo(X(t[iCur]), 12); g.lineTo(X(t[iCur]), H - 16); g.stroke();
      const s = t[iCur]; document.getElementById("tallerCursor").innerHTML = `<b>${Math.floor(s / 60)}:${(s % 60).toFixed(1).padStart(4, "0").replace(".", ",")}</b> · ${lectura.join(" · ")}`;
    }
  },
  /** La traza del vuelo vista desde arriba, coloreada por la bateria (verde llena, rojo vacia), con la casa. */
  traza() {
    const reg = Taller.reg, cv = document.getElementById("tallerTraza"); if (!cv) return;
    const g = cv.getContext("2d"), la = Taller.col(reg, "latitud"), lo = Taller.col(reg, "longitud"), b = Taller.col(reg, "bateria_pct"), W = cv.width;
    g.fillStyle = "#0b1119"; g.fillRect(0, 0, W, W);
    const D = Math.PI / 180, k = 111320 * Math.cos((la[0] || 37.6) * D), N = la.map(x => (x - la[0]) * 110574), E = lo.map(x => (x - lo[0]) * k);
    const R = Math.max(20, ...N.map(Math.abs), ...E.map(Math.abs)) * 1.1, X = e => W / 2 + e / R * (W / 2 - 10), Y = n => W / 2 - n / R * (W / 2 - 10);
    g.lineWidth = 2;
    for (let i = 1; i < N.length; i++) {
      const p = typeof b[i] === "number" ? Math.max(0, Math.min(1, b[i] / 100)) : 1;
      g.strokeStyle = `hsl(${Math.round(p * 120)},80%,55%)`; g.beginPath(); g.moveTo(X(E[i - 1]), Y(N[i - 1])); g.lineTo(X(E[i]), Y(N[i])); g.stroke();
    }
    g.fillStyle = "#fff"; g.beginPath(); g.arc(X(0), Y(0), 4, 0, 2 * Math.PI); g.fill(); g.fillText("casa", X(0) + 6, Y(0) + 4);
    g.fillStyle = "#9fb3c8"; g.fillText(`${Math.round(R)} m`, 6, W - 6); g.fillText("N ↑", W - 28, 14);
  },
};
document.getElementById("btnTallerVolver").onclick = () => irInicio();
window.addEventListener("resize", () => { if (pantallaActual === "pTaller" && Taller.reg) Taller.dibujar(); });
