// Avion y viento: centro de gravedad y peso, recorridos de la emisora, dificultad y la prueba del lanzamiento a mano.
// Parte de la aplicacion de simulador_web/simulador.html: los modulos de js/app/ se cargan en orden y comparten el
// ambito global. En Godot: simulador_godot/scripts/app/avion_ajustes.gd.
"use strict";
// =====================================================================
//  2. AVION Y VIENTO
// =====================================================================
function leerViento() {
  sesion.viento = { vel: +document.getElementById("vVel").value, desde: +document.getElementById("vDir").value,
                    rachas: document.getElementById("vRachas").checked };
  document.getElementById("vVelTxt").textContent = sesion.viento.vel + " m/s";
  try { localStorage.setItem("sim_viento", JSON.stringify(sesion.viento)); } catch (e) {}
}
for (const id of ["vVel", "vDir", "vRachas"]) document.getElementById(id).addEventListener("input", leerViento);
document.getElementById("btnVerProgreso").onclick = () => irProgreso("pHangar");

// ---- centro de gravedad y peso: por avion, por defecto los de diseno (para aprender sus efectos) ----
// cg en % de la cuerda desde el borde de ataque; masa en gramos. Se guardan en el navegador por avion.
let cmCfg = {};
try { cmCfg = JSON.parse(localStorage.getItem("sim_cm") || "{}"); } catch (e) {}
const BATERIA_G = 115;                                  // bateria 3S 1300 mAh: lo que se mueve para centrar el avion real
function cmDiseno(A) {
  return { cg: Math.round((A.cg_mm[0] - A.x_le_mm) / (A.c_m * 1000) * 100), masa: Math.round(A.masa_kg * 100) * 10 };
}
function cmActual(id) { const A = Modelos.datos(id); return cmCfg[id] || cmDiseno(A); }
function cmEsDiseno(id) { const a = cmActual(id), d = cmDiseno(Modelos.datos(id)); return a.cg === d.cg && a.masa === d.masa; }
function pintarCM() {
  pintarCfgAvion();
  const A = Modelos.datos(sesion.avion), caja = document.getElementById("secCM");
  if (A.x_le_mm === undefined || !A.punto_neutro_mm) { caja.style.display = "none"; return; }
  caja.style.display = "";
  const C = A.c_m * 1000, d = cmDiseno(A), c = cmActual(sesion.avion);
  const sCg = document.getElementById("cmCg"), sM = document.getElementById("cmMasa");
  // rango de la barra del CG: 15-60 % de la cuerda, salvo que el avion traiga el suyo (tandem: % de la cuerda media
  // desde el borde de ataque del ala delantera, que queda muy por encima del 100 %)
  [sCg.min, sCg.max] = A.cg_rango_pct || [15, 60];
  sM.min = Math.round(d.masa * 0.8 / 10) * 10; sM.max = Math.round(d.masa * 1.5 / 10) * 10;
  sCg.value = c.cg; sM.value = c.masa;
  const np = (A.punto_neutro_mm - A.x_le_mm) / C * 100, margen = np - c.cg;
  document.getElementById("cmCgTxt").textContent = `${c.cg} % de ${A.cg_ref_texto || "la cuerda"} (${(c.cg / 100 * C).toFixed(0)} mm tras el borde de ataque)` +
    (c.cg === d.cg ? " · diseño" : "");
  const vs = Math.sqrt(2 * c.masa / 1000 * 9.81 / (1.225 * A.S_m2 * 1.1));
  document.getElementById("cmMasaTxt").textContent = `${c.masa} g · carga alar ${(c.masa / (A.S_m2 * 100)).toFixed(1)} g/dm² · pérdida ${vs.toFixed(1)} m/s` +
    (c.masa === d.masa ? " · diseño" : "");
  let txt, color;
  if (margen < 0) { color = "#ff6e66"; txt = `⚠ El centro de gravedad está DETRÁS del punto neutro (${np.toFixed(0)} %): el avión es inestable en cabeceo, cada perturbación crece sola. No se puede volar; en el avión real acaba en accidente nada más lanzarlo.`; }
  else if (margen < 10) { color = "#ffb74d"; txt = `Cola pesada: margen estático ${margen.toFixed(0)} % (punto neutro al ${np.toFixed(0)} %). Muy sensible a la profundidad, le cuesta mantener la velocidad y entra en pérdida con facilidad.`; }
  else if (margen > 30) { color = "#ffb74d"; txt = `Morro pesado: margen estático ${margen.toFixed(0)} %. Muy estable, pero pide mucha profundidad arriba, vuela más rápido y puede no tener mando para recoger al aterrizar.`; }
  else { color = "#8be08f"; txt = `Margen estático ${margen.toFixed(0)} % (punto neutro al ${np.toFixed(0)} %): dentro de lo normal en un entrenador (10–30 %).`; }
  if (c.masa > d.masa * 1.15) txt += ` Con ${c.masa - d.masa} g más, pierde a ${vs.toFixed(1)} m/s: hay que lanzarlo más fuerte y aterrizar más rápido.`;
  else if (c.masa < d.masa * 0.9) txt += ` Más ligero: vuela más despacio, pero las rachas lo mueven más.`;
  const gmin = A.tren || A.lanzado_a_mano ? undefined : gasMinimoLanzamiento({});      // un avion de pista no se lanza a mano; el Grajo lo sube el automatico
  if (A.lanzado_a_mano) txt += " Se lanza a mano, de cara al viento, con el motor a tope: el piloto automático lo sube solo (modo Lanzamiento).";
  else if (gmin === undefined) txt += " Despega y aterriza en pista.";
  else if (gmin === null) { color = "#ff6e66"; txt += ` ⚠ Con ${c.masa} g no sale de la mano ni con todo el gas: demasiado peso para lanzarlo a mano.`; }
  else txt += ` Lanzado a mano (sin viento y sin tocar los mandos) sale con al menos el ${pctGas(gmin)} % de gas.`;
  const e = document.getElementById("cmEfecto"); e.textContent = txt; e.style.color = color;
  const dBat = (c.cg - d.cg) / 100 * C * c.masa / BATERIA_G;
  document.getElementById("cmBateria").textContent = c.cg === d.cg ? "En el avión real, el centro de gravedad se ajusta moviendo la batería." :
    `En el avión real equivale a mover la batería ${Math.abs(dBat).toFixed(0)} mm hacia ${dBat > 0 ? "la cola" : "el morro"}` +
    (Math.abs(dBat) > 60 ? " (no hay tanto sitio: haría falta lastre)." : ".");
}
function leerCM() {
  cmCfg[sesion.avion] = { cg: +document.getElementById("cmCg").value, masa: +document.getElementById("cmMasa").value };
  try { localStorage.setItem("sim_cm", JSON.stringify(cmCfg)); } catch (e) {}
  pintarCM();
}
for (const id of ["cmCg", "cmMasa"]) document.getElementById(id).addEventListener("input", leerCM);
setInterval(() => { if (pantallaActual === "pAjustes") pintarMandoCfg(); }, 1000);   // el mando aparece al pulsar un boton
document.getElementById("btnCmDiseno").onclick = () => {
  delete cmCfg[sesion.avion]; try { localStorage.setItem("sim_cm", JSON.stringify(cmCfg)); } catch (e) {} pintarCM();
};
// ---- recorridos de la emisora y calibracion, por avion (se guardan en el navegador) ----
// recorrido mecanico (grados a palanca a tope sin dual rate) de cada avion; si no esta, el del simulador
const RECORRIDO_MECANICO = { E3: { prof: 12, aleron: 15 }, T1: { prof: 15, aleron: 15 } };
let cfgAvion = {};
try { cfgAvion = JSON.parse(localStorage.getItem("sim_cfg_avion") || "{}"); } catch (e) {}
function cfgDe(id) { return Object.assign({ drAlabeo: 100, drProf: 100, empuje: "", res: 100, temp: 20, lanzReal: true }, cfgAvion[id] || {}); }
function guardarCfg() { try { localStorage.setItem("sim_cfg_avion", JSON.stringify(cfgAvion)); } catch (e) {} }
function pintarCfgAvion() {
  const c = cfgDe(sesion.avion), A = Modelos.datos(sesion.avion), mec = RECORRIDO_MECANICO[sesion.avion] || Modelos.datos(sesion.avion).mandos.mecanico || {};
  const lat = A.mandos.timon_max_grados > 0 && A.mandos.aleron_max_grados ? "alerones y timón" : A.mandos.timon_max_grados > 0 ? "timón" : "alerones", mLat = mec.aleron || mec.timon || A.mandos.aleron_max_grados || A.mandos.timon_max_grados;
  document.getElementById("drAlabeo").value = c.drAlabeo; document.getElementById("drProf").value = c.drProf;
  document.getElementById("drAlabeoTxt").textContent = `${c.drAlabeo} % · ${lat} ±${(mLat * c.drAlabeo / 100).toFixed(1)}° (mecánico ±${mLat}°)`;
  const mP = mec.prof || A.mandos.prof_max_grados;
  document.getElementById("drProfTxt").textContent = `${c.drProf} % · ±${(mP * c.drProf / 100).toFixed(1)}° (mecánico ±${mP}°)`;
  document.getElementById("lanzReal").checked = c.lanzReal;
  document.getElementById("calEmpuje").value = c.empuje; document.getElementById("calRes").value = c.res; document.getElementById("calTemp").value = c.temp;
  document.getElementById("calResTxt").textContent = `${c.res} % de la estimada`;
  document.getElementById("calTempTxt").textContent = `${c.temp} °C · densidad ${(101325 / (287.05 * (c.temp + 273.15))).toFixed(3)} kg/m³`;
  document.getElementById("calInfo").textContent = "La resistencia se ajusta con planeos a mano sin motor: si el avión real toca antes que en el simulador lanzado igual, súbela. " +
    "El calor baja la densidad: a 35 °C la pérdida sube un 3 % y el motor empuja un 6 % menos.";
}
function leerCfgAvion() {
  const c = cfgDe(sesion.avion);
  c.drAlabeo = +document.getElementById("drAlabeo").value; c.drProf = +document.getElementById("drProf").value;
  c.lanzReal = document.getElementById("lanzReal").checked; c.empuje = document.getElementById("calEmpuje").value;
  c.res = +document.getElementById("calRes").value; c.temp = +document.getElementById("calTemp").value;
  cfgAvion[sesion.avion] = c; guardarCfg(); pintarCfgAvion();
}
for (const id of ["drAlabeo", "drProf", "calRes", "calTemp"]) document.getElementById(id).addEventListener("input", leerCfgAvion);
for (const id of ["lanzReal", "calEmpuje"]) document.getElementById(id).addEventListener("change", leerCfgAvion);
// ---- dificultad: "real" (toda la fisica) o "facil" (la de antes de las mejoras de realismo; ModeloAvion.facil) ----
const DIFICULTAD_INFO = {
  real: "Par y estela de la hélice (el avión tiende a alabear y guiñar a la izquierda con gas), efecto P y giroscópico, pérdida por semiala (cae de un ala, puede entrar en barrena), efecto suelo, resistencia de perfil y de la hélice parada, viento más flojo junto al suelo, turbulencia que alabea, densidad según la temperatura, calibración con el avión real y lanzamiento con dispersión.",
  facil: "Sin par ni estela de la hélice, sin efectos P ni giroscópico, pérdida simétrica, sin efecto suelo, el mismo viento a cualquier altura, rachas sin alabeo, aire estándar y lanzamiento perfecto. Para aprender; el avión real se parece más al modo real." };
function pintarDificultad() {
  document.getElementById("dificultad").value = sesion.dificultad;
  document.getElementById("dificultadInfo").textContent = DIFICULTAD_INFO[sesion.dificultad];
}
document.getElementById("dificultad").addEventListener("change", e => {
  sesion.dificultad = e.target.value === "facil" ? "facil" : "real";
  try { localStorage.setItem("sim_dificultad", sesion.dificultad); } catch (er) {}
  pintarDificultad();
});
pintarDificultad();
/** Pone la dificultad elegida en un modelo de vuelo (y en el entorno). */
function aplicarDificultad(m) { m.facil = sesion.dificultad === "facil"; entorno.facil = m.facil; }
/** Calibracion y aire al modelo (al empezar el vuelo). */
function aplicarCalibracion(m) {
  const c = cfgDe(sesion.avion);
  m.configurar({ temperatura: c.temp, empuje_gf: +c.empuje || 0, resistencia: c.res / 100 });
  sesion.lanzReal = c.lanzReal;
  m.mandosBase = Object.assign({}, m.mandos);
}
/** Con mando: recorridos mecanicos por el dual rate y sin la exponencial del simulador (la pone el mando).
 *  Con teclado: los recorridos reducidos del simulador. Se llama en cada paso (cambia al tocar mando o teclado). */
function aplicarRecorridos(mod, forzarMando) {
  mod = mod || modelo;
  if (!mod || !mod.mandosBase) return;
  const fuente = MANDO.usado || forzarMando ? "mando" : "teclado";
  if (mod._fuente === fuente) return;
  mod._fuente = fuente;
  const B = mod.mandosBase, m = Object.assign({}, B);
  if (fuente === "mando") {
    const c = cfgDe(sesion.avion), mec = RECORRIDO_MECANICO[sesion.avion] || Modelos.datos(sesion.avion).mandos.mecanico || {};
    m.expo = 0;
    m.prof_max_grados = (mec.prof || B.prof_max_grados) * c.drProf / 100;
    if (B.aleron_max_grados) m.aleron_max_grados = (mec.aleron || B.aleron_max_grados) * c.drAlabeo / 100;
    if (B.timon_max_grados) m.timon_max_grados = (mec.timon || B.timon_max_grados) * c.drAlabeo / 100;
  }
  mod.mandos = m;
}

/** Aplica al modelo de vuelo el centro de gravedad y el peso elegidos. */
function aplicarCM(m) {
  const A = Modelos.datos(sesion.avion);
  if (A.x_le_mm === undefined) return;
  if (cmEsDiseno(sesion.avion)) return;             // los valores de diseno exactos (sin redondear a 1 % y 10 g)
  const c = cmActual(sesion.avion);
  m.configurar({ masa_kg: c.masa / 1000, cg_mm: A.x_le_mm + c.cg / 100 * A.c_m * 1000 });
}
function textoCM() {
  const c = cmActual(sesion.avion);
  return cmEsDiseno(sesion.avion) ? "CG y peso de diseño" : `CG ${c.cg} % de la cuerda · ${c.masa} g`;
}

// =====================================================================
//  LANZAMIENTO A MANO. pruebaLanzamiento repite el lanzamiento aparte con la misma fisica (5 s, sin tocar los
//  mandos, viento sin rachas): sale bien si no toca el suelo. Con ella se calcula el gas minimo para lanzarlo
//  (avisa antes de lanzar) y, si un lanzamiento falla de verdad, por que: poco gas, demasiado peso o los mandos.
// =====================================================================
const LANZ = { prueba_s: 5, fallo_s: 6, fallo_h: 5 };   // un vuelo que acaba antes de 6 s sin pasar de 5 m es un lanzamiento fallido
function pruebaLanzamiento(gas, { masa_kg, viento = [0, 0, 0], rumbo = 0, trim } = {}) {
  // con el recorrido de la emisora (el del teclado no basta en un avion pequeno para corregir el par del motor al lanzarlo)
  const m = Modelos.crear(sesion.avion); aplicarCM(m); aplicarCalibracion(m); aplicarRecorridos(m, true); aplicarDificultad(m);
  if (masa_kg) m.configurar({ masa_kg });
  const a = m.estadoInicial(); colocarEnBase(a, m); a.gases = gas; m.lanzar(a);
  if (entorno.mundo) rumbo = (sesion.lanz ? sesion.lanz.rumbo : 0) * D2R;
  if (rumbo) { const [r, p] = Cuat.euler(a.q); a.q = Cuat.desdeEuler(r, p, rumbo); }
  const mm = { pitch: 0, yaw: 0, trim: trim !== undefined ? trim : (m.compensador_grados || 0) };
  for (let i = 0; i < LANZ.prueba_s / DT; i++) {
    // el piloto no toca la profundidad pero si mantiene las alas niveladas (el par del motor alabea el avion al soltarlo)
    const roll = Cuat.euler(a.q)[0]; mm.yaw = Math.max(-1, Math.min(1, -roll * 3 - a.w[0] * 0.4));
    m.servos(a, mm, DT);
    if (entorno.contactoSuelo(a, m.paso(a, viento, DT))) return false;
  }
  return true;
}
/** Gas minimo (0-1) para que salga de la mano, o null si no sale ni con todo el gas. */
function gasMinimoLanzamiento(op) {
  if (modelo && modelo.esCuadricoptero) return 0;          // el dron despega desde el suelo con el gas que haga falta
  if (!pruebaLanzamiento(1, op)) return null;
  let lo = 0, hi = 1;
  for (let i = 0; i < 7; i++) { const g = (lo + hi) / 2; if (pruebaLanzamiento(g, op)) hi = g; else lo = g; }
  return hi;
}
/** Masa maxima (kg) con la que sale de la mano con todo el gas (entre el 50 y el 150 % de la de diseno). */
function masaMaximaLanzamiento(op) {
  const d = Modelos.datos(sesion.avion).masa_kg;
  let lo = 0.5 * d, hi = 1.5 * d;
  if (!pruebaLanzamiento(1, Object.assign({}, op, { masa_kg: lo }))) return null;
  for (let i = 0; i < 7; i++) { const mk = (lo + hi) / 2; if (pruebaLanzamiento(1, Object.assign({}, op, { masa_kg: mk }))) lo = mk; else hi = mk; }
  return lo;
}
const pctGas = g => Math.ceil(g * 100 / 5) * 5;          // el gas minimo, redondeado hacia arriba al 5 %
/** El lanzamiento con el avion, el CG, el peso, el viento y el compensador del vuelo en curso (en cache). */
let cacheLanz = { clave: null };
function lanzamientoActual() {
  const vto = entorno.viento, rumbo = zonaDe(sesion.escenario) === 2 ? Math.PI : 0;
  const op = { viento: [vto.base * Math.cos(vto.rumbo), vto.base * Math.sin(vto.rumbo), 0], rumbo, trim: mando.trim };
  const clave = JSON.stringify([sesion.avion, modelo.masa_kg, modelo.dcg, op]);
  if (cacheLanz.clave !== clave) cacheLanz = { clave, op, gmin: gasMinimoLanzamiento(op), mmax: undefined, gminDiseno: undefined, sinViento: undefined };
  return cacheLanz;
}
/** Si lleva peso de mas (5 %): el texto que compara con el gas que bastaria con el peso de diseno. */
function textoPesoLanz(L) {
  const d = Modelos.datos(sesion.avion).masa_kg, extra = Math.round((modelo.masa_kg - d) * 1000);
  if (modelo.masa_kg < d * 1.05) return "";
  if (L.gminDiseno === undefined) L.gminDiseno = gasMinimoLanzamiento(Object.assign({}, L.op, { masa_kg: d }));
  return ` Es por el peso: lleva ${extra} g de más${L.gminDiseno !== null ? ` (con el peso de diseño bastaría el ${pctGas(L.gminDiseno)} %)` : ""}.`;
}
/** Aviso antes de lanzar ("" si sale bien con el gas puesto). */
/** Si no sale con todo el gas pero SIN viento si: el viento (de costado o de cola) es el que lo tira, no el peso. Gas
 *  minimo sin viento, o null. */
function gasSinViento(L) {
  if (L.sinViento === undefined) L.sinViento = gasMinimoLanzamiento(Object.assign({}, L.op, { viento: [0, 0, 0] }));
  return L.sinViento;
}
const RUMBOS_TXT = ["norte", "nordeste", "este", "sudeste", "sur", "sudoeste", "oeste", "noroeste"];
function textoVientoLanz() {
  const v = entorno.viento, desde = ((v.rumbo * R2D + 180) % 360 + 360) % 360;
  return `${v.base.toFixed(0)} m/s del ${RUMBOS_TXT[Math.round(desde / 45) % 8]}`;
}
function avisoLanzamiento() {
  if (modelo.tren) return "";                    // avion de pista: no se lanza a mano
  const L = lanzamientoActual();
  if (L.gmin === null && gasSinViento(L) !== null)
    return `⚠ Con este viento (${textoVientoLanz()}) no saldría de la mano sin tocar los mandos: lánzalo de cara al viento o prepárate para corregir con la profundidad nada más soltarlo.`;
  if (L.gmin === null) return `⚠ Pesa demasiado para lanzarlo a mano (${Math.round(modelo.masa_kg * 1000)} g): no saldría ni con todo el gas. Quítale peso en la pantalla del avión.`;
  if (av.gases < L.gmin) return `⚠ Con el ${Math.round(av.gases * 100)} % de gas no saldría de la mano: sube el gas al menos al ${pctGas(L.gmin)} % (W).` + textoPesoLanz(L);
  return "";
}
/** Por que fallo un lanzamiento: { corto, texto }. */
function causaLanzamientoFallido(gas) {
  const L = lanzamientoActual(), masa = Math.round(modelo.masa_kg * 1000);
  if (L.gmin === null && gasSinViento(L) !== null)
    return { corto: "viento", texto: `con este viento (${textoVientoLanz()}) no sale de la mano sin tocar los mandos: se encabrita, entra en pérdida y cae. Lánzalo de cara al viento y, al soltarlo, baja un poco el morro.` };
  if (L.gmin === null) {
    if (L.mmax === undefined) L.mmax = masaMaximaLanzamiento(L.op);
    return L.mmax ? { corto: "demasiado peso", texto: `pesa demasiado para lanzarlo a mano (${masa} g): no sale ni con todo el gas. Con el 100 % sale hasta unos ${Math.floor(L.mmax * 100) * 10} g.` }
                  : { corto: "centro de gravedad", texto: "no sale de la mano ni con todo el gas ni con poco peso: revisa el centro de gravedad." };
  }
  if (gas < L.gmin) { const pp = textoPesoLanz(L);
    return { corto: pp ? "poco gas para su peso" : "poco gas", texto: `con el ${Math.round(gas * 100)} % de gas no tiene empuje para salir de la mano con ${masa} g: lánzalo con al menos el ${pctGas(L.gmin)} %.` + pp }; }
  return { corto: "mandos", texto: `con el ${Math.round(gas * 100)} % de gas salía bien sin tocar los mandos: el fallo fue de los mandos (tirar o empujar de más nada más lanzarlo) o una racha.` };
}
