"use strict";
// =====================================================================
//  REGISTRO DE VUELO de cada vehiculo, como el que se descarga de un dron comercial (registro_vuelo.gd en Godot, con
//  las mismas columnas): 10 muestras por segundo con la posicion (latitud y longitud), alturas, velocidades, actitud,
//  la bateria (carga, tension, corriente, potencia, temperatura y cada celda), gas y vueltas, palancas, gimbal, modo y
//  estado, y los avisos del vuelo. Se guarda en el navegador (IndexedDB, los ultimos 30 de cada vehiculo) y, con el
//  alumno en el aula, tambien en el servidor (comprimido; si no hay red, se reintenta). Lo lee el modo Taller.
// =====================================================================
const RegistroVuelo = {
  CADA_S: 0.1,
  MAX_POR_VEHICULO: 30,
  /** Columnas del registro de un modelo (las celdas segun su bateria). */
  columnas(m) {
    const n = m && m.B ? m.B.celdas : 0, c = ["tiempo_s", "latitud", "longitud", "altura_despegue_m", "altura_suelo_m", "velocidad_h_ms", "velocidad_v_ms",
      "distancia_m", "rumbo_grados", "alabeo_grados", "cabeceo_grados", "bateria_pct", "tension_V", "corriente_A", "potencia_W", "temperatura_bateria_C"];
    for (let i = 1; i <= n; i++) c.push("celda" + i + "_V");
    return c.concat(["gas_pct", "rpm", "palanca_cabeceo", "palanca_alabeo", "palanca_guinada", "palanca_gas", "gimbal_grados", "modo", "estado"]);
  },
  /** Empieza el registro de un vuelo (vuelo.reg). */
  empezar(vuelo) {
    if (modelo.esTerrestre) return;                 // el bipode no lleva registro
    const M = entorno.mundo, o = M && M.origen ? M.origen : { lat: 37.612788, lon: -1.049916 };     // el campo del club: junto al origen de Cartagena
    vuelo.reg = { columnas: RegistroVuelo.columnas(modelo), filas: [], eventos: [], casa: [av.p[0], av.p[1], -av.p[2]], origen: o, tUlt: -1 };
  },
  /** Estado del vehiculo en palabras. */
  estado() {
    if (av.estado !== "volando") return av.estado;
    if (av.sinBateria) return "sin bateria";
    if (av.cortado) return "motor cortado";
    if (av.batForzado) return "aterrizaje forzoso";
    if (av.rth) return "volviendo a casa";
    if (av.posado || av.enTierra) return "en tierra";
    return "volando";
  },
  /** Una muestra (cada 0,1 s de vuelo, y la ultima al acabar). */
  muestra(vuelo, forzar) {
    const R = vuelo && vuelo.reg;
    if (!R || (!forzar && av.t - R.tUlt < RegistroVuelo.CADA_S - 1e-9)) return;
    R.tUlt = av.t;
    const r = (x, n) => x === null || x === undefined || !isFinite(x) ? null : +(+x).toFixed(n), o = R.origen, D = Math.PI / 180;
    const [rol, cab, rum] = Cuat.euler(av.q).map(a => a / D), vn = Cuat.rot(av.q, av.v), B = modelo.B, e = av.bat;
    const fila = [r(av.t, 2), r(o.lat + av.p[0] / 110574, 7), r(o.lon + av.p[1] / (111320 * Math.cos(o.lat * D)), 7), r(-av.p[2] - R.casa[2], 2),
      r(av.agl !== undefined ? av.agl : -av.p[2], 2), r(Math.hypot(vn[0], vn[1]), 2), r(-vn[2], 2), r(Math.hypot(av.p[0] - R.casa[0], av.p[1] - R.casa[1]), 1),
      r((rum + 360) % 360, 1), r(rol, 1), r(cab, 1), r(modelo.bateriaPct ? modelo.bateriaPct(av) : null, 1),
      r(e ? e.V : null, 3), r(e ? e.I : null, 2), r(e ? e.P : null, 1), r(e ? e.T : null, 2)];
    if (B) for (let i = 0; i < B.celdas; i++) fila.push(r(e ? e.celdas[i] : null, 3));
    const gas = modelo.esCuadricoptero && !modelo.esFPV ? mando.vz : av.gases;
    fila.push(r((av.gasMotor !== undefined ? av.gasMotor : av.gases) * 100, 1), r(av.rpm, 0), r(mando.pitch, 3), r(mando.yaw, 3), r(mando.guinada, 3), r(gas, 3),
      r(av.gimbal !== undefined ? av.gimbal : (av.torreta ? av.torreta.tilt / D : null), 1),
      typeof piloto !== "undefined" && piloto && modelo.uav ? piloto.modo : modelo.modo || "manual", RegistroVuelo.estado());
    R.filas.push(fila);
  },
  /** Un aviso del vuelo (lo que sale en pantalla), con su tiempo. */
  evento(vuelo, txt) { if (vuelo && vuelo.reg && txt) vuelo.reg.eventos.push([+(av.t || 0).toFixed(1), String(txt)]); },
  /** Al acabar el vuelo: el registro completo, guardado en el navegador y enviado al aula. */
  cerrar(vuelo) {
    if (!vuelo || !vuelo.reg || vuelo.reg.cerrado) return null;
    RegistroVuelo.muestra(vuelo, true);
    const R = vuelo.reg; R.cerrado = true;
    const E = ESCENARIOS[vuelo.escenario] || {}, B = modelo.B;
    const reg = { id: vuelo.id, avion: sesion.avion, avion_nombre: modelo.nombre, inicio: vuelo.inicio.toISOString(), escenario: vuelo.escenario,
                  escenario_nombre: E.nombre || vuelo.escenario, alumno: sesion.alumno ? sesion.alumno.nombre : null, final: vuelo.final,
                  duracion_s: +(av.t || 0).toFixed(1), bateria: B ? { quimica: B.quimica, celdas: B.celdas, capacidad_mAh: B.capacidad_mAh } : null,
                  columnas: R.columnas, filas: R.filas, eventos: R.eventos };
    RegistroDB.guardar(reg, sesion.aula && sesion.alumno ? { alumno_id: sesion.alumno.id, pase: sesion.pase } : null).then(() => RegistroDB.subirPendientes()).catch(e => console.warn("Registro de vuelo sin guardar:", e));
    return reg;
  },
};

/** Los registros en el navegador (IndexedDB "uxs_registros"): los ultimos MAX_POR_VEHICULO de cada vehiculo; los que hay
 *  que enviar al aula llevan "subir" (el alumno y su pase) hasta que el servidor los acepta. */
const RegistroDB = {
  _db: null,
  abrir() {
    return RegistroDB._db || (RegistroDB._db = new Promise((ok, mal) => {
      const q = indexedDB.open("uxs_registros", 1);
      q.onupgradeneeded = () => { const s = q.result.createObjectStore("registros", { keyPath: "id" }); s.createIndex("avion", "avion"); };
      q.onsuccess = () => ok(q.result); q.onerror = () => mal(q.error);
    }));
  },
  async _tx(modo, f) {
    const db = await RegistroDB.abrir();
    return new Promise((ok, mal) => { const t = db.transaction("registros", modo), s = t.objectStore("registros"); let r; f(s, x => r = x); t.oncomplete = () => ok(r); t.onerror = () => mal(t.error); });
  },
  async guardar(reg, subir) {
    if (subir) reg.subir = subir;
    await RegistroDB._tx("readwrite", s => s.put(reg));
    const todos = (await RegistroDB.listar(reg.avion)).filter(x => !x.subir);             // los mas viejos fuera (nunca uno pendiente de enviar)
    for (const x of todos.slice(RegistroVuelo.MAX_POR_VEHICULO)) await RegistroDB._tx("readwrite", s => s.delete(x.id));
  },
  /** Los registros (sin las muestras) de un vehiculo, o de todos, del mas nuevo al mas viejo. */
  async listar(avion) {
    const todos = await RegistroDB._tx("readonly", (s, fin) => { const q = avion ? s.index("avion").getAll(avion) : s.getAll(); q.onsuccess = () => fin(q.result); });
    return (todos || []).map(({ filas, columnas, eventos, ...meta }) => Object.assign(meta, { muestras: filas.length, n_eventos: eventos.length }))
      .sort((a, b) => b.inicio.localeCompare(a.inicio));
  },
  async leer(id) { return RegistroDB._tx("readonly", (s, fin) => { const q = s.get(id); q.onsuccess = () => fin(q.result); }); },
  /** Envia al aula los registros pendientes (comprimidos con gzip, a /api/registros, con el pase de su alumno). */
  async subirPendientes() {
    if (typeof urlAula !== "function" || !urlAula()) return;
    let pend; try { pend = (await RegistroDB._tx("readonly", (s, fin) => { const q = s.getAll(); q.onsuccess = () => fin(q.result); })).filter(x => x.subir); } catch (e) { return; }
    for (const reg of pend) {
      const { subir, ...cuerpo } = reg; cuerpo.alumno_id = subir.alumno_id;
      try {
        const gz = await new Response(new Blob([JSON.stringify(cuerpo)]).stream().pipeThrough(new CompressionStream("gzip"))).arrayBuffer();
        const r = await fetch(urlAula() + "/api/registros", { method: "POST", headers: { "Content-Type": "application/gzip", "X-Alumno": subir.pase || "" }, body: gz });
        if (r.ok || (r.status >= 400 && r.status < 500 && r.status !== 401 && r.status !== 429)) { delete reg.subir; await RegistroDB._tx("readwrite", s => s.put(reg)); }
      } catch (e) { return; }                       // sin red: otra vez mas tarde
    }
  },
};

/** CSV de un registro (columnas en la primera linea; los avisos, en una columna mas, en su momento). */
function registroCSV(reg) {
  const ev = reg.eventos.slice(), filas = [reg.columnas.concat(["aviso"]).join(",")];
  for (const f of reg.filas) {
    const avisos = []; while (ev.length && ev[0][0] <= f[0] + 1e-9) avisos.push(ev.shift()[1]);
    filas.push(f.map(x => x === null ? "" : typeof x === "string" ? '"' + x + '"' : x).concat(['"' + avisos.join(" | ").replace(/"/g, "'") + '"']).join(","));
  }
  return "﻿" + filas.join("\n") + "\n";
}
