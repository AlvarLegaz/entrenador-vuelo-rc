// Vuelo: zonas de detalle, empezar, lanzar, el paso de la simulacion (500 por segundo) y el final del vuelo.
// Parte de la aplicacion de simulador_web/simulador.html: los modulos de js/app/ se cargan en orden y comparten el
// ambito global. En Godot: simulador_godot/scripts/app/vuelo.gd.
"use strict";
// =====================================================================
//  VUELO
// =====================================================================
// ---- zonas de detalle de los mundos reales (zonas/indice.json; las mismas que usa el simulador de Godot) ----
const ZONAS = { indice: null, cache: {} };
async function indiceZonas() {
  if (ZONAS.indice) return ZONAS.indice;
  if (ABIERTO_COMO_FICHERO) {               // con doble clic no hay fetch: el indice va empaquetado en un .js
    try { await cargarScript("../datos/escenarios/zonas/indice.js?" + Date.now()); ZONAS.indice = Zonas._indice || []; } catch (e) { ZONAS.indice = []; }
    return ZONAS.indice;
  }
  try { const r = await fetch("../datos/escenarios/zonas/indice.json?" + Date.now()); ZONAS.indice = r.ok ? await r.json() : []; } catch (e) { ZONAS.indice = []; }
  return ZONAS.indice;
}
/** La zona del mundo que contiene (N, E) con 150 m de margen, o null. */
function zonaEn(mundoId, N, E) {
  return (ZONAS.indice || []).find(z => z.mundo === mundoId && N > z.N0 + 150 && N < z.N0 + z.lado_m - 150 && E > z.E0 + 150 && E < z.E0 + z.lado_m - 150) || null;
}
async function cargarZona(meta) {
  if (ZONAS.cache[meta.id]) return ZONAS.cache[meta.id];
  const base = "../datos/escenarios/zonas/" + meta.id + "/";
  if (ABIERTO_COMO_FICHERO) {                // con doble clic: la zona entera en zonas/<id>/zona.js (datos en base64)
    await cargarScript(base + "zona.js");
    const d = Zonas._datos[meta.id]; if (!d) throw new Error("sin " + base + "zona.js");
    const datos = { edificios: d.edificios, arboles: new Float32Array(base64ABytes(d.arboles)), orto: d.orto };
    return (ZONAS.cache[meta.id] = { meta, dem: new Int16Array(base64ABytes(d.dem)), base, datos });
  }
  const r = await fetch(base + meta.dem.archivo);
  if (!r.ok) throw new Error("sin " + base + meta.dem.archivo);
  return (ZONAS.cache[meta.id] = { meta, dem: new Int16Array(await r.arrayBuffer()), base });
}
/** Zonas de detalle a menos de RADIO_ZONAS m del punto (N, E), la que lo contiene primero (la misma regla en Godot,
 *  zonas_cerca de principal.gd). Con zonas pegadas, como las de La Manga y el Mar Menor, se vuela siempre en detalle
 *  hasta unos 2 km del piloto sin cargar todas (cada una son 36 fotos de 1024 px). */
const RADIO_ZONAS = 2000;
function zonasCerca(mundoId, N, E) {
  const dist = z => Math.hypot(Math.max(z.N0 - N, 0, N - z.N0 - z.lado_m), Math.max(z.E0 - E, 0, E - z.E0 - z.lado_m));
  const dentro = zonaEn(mundoId, N, E);
  return (ZONAS.indice || []).filter(z => z.mundo === mundoId && dist(z) <= RADIO_ZONAS)
    .sort((a, b) => (b === dentro) - (a === dentro) || dist(a) - dist(b));
}
/** Pone (o quita) las zonas de detalle de cerca del punto de lanzamiento, en el Entorno (suelo fisico) y en el Visor. */
async function ponerZonaDeLanzamiento(mundo) {
  const zs = [];
  if (mundo) {
    await indiceZonas();
    const c = casa();
    for (const meta of zonasCerca(mundo.id, c.N, c.E))
      try { zs.push(await cargarZona(meta)); } catch (e) { console.warn("No se pudo cargar la zona " + meta.id, e); }
  }
  entorno.ponerZonas(zs);
  if (!mundo) return;
  // las mismas zonas ya construidas en la escena de este mundo y desde el mismo punto de salida (sus arboles se
  // despejan alrededor): se reutilizan tal cual; empezar() las volvia a crear en cada vuelo (mallas, 36 ortofotos por zona)
  const c = casa(), clave = mundo.id + "|" + zs.map(z => z.meta.id).join(",") + "|" + Math.round(c.N) + "," + Math.round(c.E);
  if (visor.zonasClave === clave && visor.mundoId === mundo.id && (visor.escena.userData.zonaGrupos || []).length === zs.length) return true;
  visor.ponerZonas(zs); visor.zonasClave = clave; return false;
}

async function empezar() {
  const mundo = mundoDe(sesion.escenario), carga = !!mundo;      // los mundos reales tardan unos segundos: pantalla de carga
  Sonido.iniciar();
  if (carga) await mostrarCarga(mundo.nombre, "Avión y física…", 0.1);
  modelo = Modelos.crear(sesion.avion);
  aplicarCM(modelo); aplicarCalibracion(modelo); aplicarDificultad(modelo);
  Desgaste.aplicar(modelo, Desgaste.clase(modelo) ? Desgaste.estado(sesion.avion) : null);    // sus averias y el desgaste de la bateria
  visor.ponerAvion(datosVisor(sesion.avion));
  if (morroDe(sesion.avion) === "orientable") modelo.configurar({ masa_kg: modelo.masa_kg + (modelo.camara.masa_orientable_kg || 0) });   // la torreta pesa
  document.getElementById("ayudaLR").textContent = (modelo.mandos && modelo.mandos.izq_der) || "timón";
  if (modelo.ayuda) document.getElementById("ayudaAvion").textContent = modelo.ayuda;
  document.getElementById("ayudaTeclasDron").style.display = modelo.esCuadricoptero && !modelo.esFPV ? "" : "none";
  document.getElementById("ayudaTeclasFPV").style.display = modelo.esFPV ? "" : "none";
  document.getElementById("ayudaTeclasBip").style.display = modelo.esBipode ? "" : "none";
  document.getElementById("ayudaPar").style.display = modelo.esFPV || modelo.esBipode ? "none" : "";
  document.getElementById("ayudaTeclasAvion").style.display = modelo.esCuadricoptero || modelo.esBipode ? "none" : "";
  document.body.classList.toggle("bipode", !!modelo.esBipode);
  if (modelo.esBipode) visor.camara = 2;                   // el bipode se maneja desde detras
  // el dron se vuela mirando la pantalla de la app (su camara); al volver a un avion, vista del piloto
  if (!!modelo.esCuadricoptero !== !!visor.eraDron) visor.camara = modelo.esCuadricoptero ? 3 : 1;
  visor.eraDron = !!modelo.esCuadricoptero; document.body.classList.toggle("dron", !!modelo.esCuadricoptero && !modelo.esFPV); document.body.classList.toggle("uav", !!modelo.uav);
  document.body.classList.toggle("fpv", !!modelo.esFPV);
  document.body.classList.toggle("operacion", !!ESCENARIOS[sesion.escenario].operacion); verBriefing(false);   // trabajos: el briefing a mano (B)       // dron FPV: el OSD de Betaflight en vez de la app del dron comercial
  construirAnemometro(velPerdida());
  if (carga) await mostrarCarga(mundo.nombre, "Terreno, mar, carreteras y pueblos…", 0.3);
  entorno.ponerMundo(mundo); visor.ponerMundo(mundo); GPS.mapa = null;
  visor.ponerPistaFpv(!mundo && ESCENARIOS[sesion.escenario].pista_fpv || null);
  if (mundo) {
    await mostrarCarga(mundo.nombre, "Zonas de detalle: ortofoto, edificios y árboles…", 0.6);
    const c = casa(); visor.baseNE = [c.N, c.E];                 // antes de la zona: sus arboles se detallan alrededor del punto de salida
    const mismas = await ponerZonaDeLanzamiento(mundo);     // zonas reutilizadas y mismo punto de salida: los arboles de la region son los mismos (misma semilla), no se rehacen
    visor.ponerBase([c.N, c.E], !(mismas && visor.arbolesNE && visor.arbolesNE[0] === c.N && visor.arbolesNE[1] === c.E));
    await mostrarCarga(mundo.nombre, "Listo", 1);
  }
  ocultarCarga();
  reiniciar(); mostrar(null);
}
function reiniciar() {
  MANDO.gasFpv = false; MULTI.caida = null;
  av = modelo.estadoInicial(); colocarEnBase(av);
  piloto = modelo.uav ? (c => new PilotoUAV(PilotoUAV.paraMasa(modelo.piloto, modelo.masa_kg / Modelos.datos(sesion.avion).masa_kg), modelo.tren ? pistaActual() : null, [c.N, c.E, entorno.altura ? entorno.altura(c.N, c.E) : 0]))(casa()) : null;   // el lanzado a mano, sin pista
  if (modelo.uav) { av.torreta = { pan: 0, tilt: -20 * D2R }; UAV.fijo = null; UAV.cruz = null; UAV.fotos = 0; }
  if (morroDe(sesion.avion) === "fijo") { UAV.vista = "frontal"; ponerVistaFija(); }       // morro fijo: la camara frontal
  const F = ESCENARIOS[sesion.escenario].pista_fpv;
  if (F && modelo.esFPV && !mundoDe(sesion.escenario)) { av.p = [F.salida[0], F.salida[1], -0.02]; modelo.modo = F.modo; }   // en la plataforma y en el modo de la mision
  orientarLanzamiento();
  mando.pitch = mando.yaw = 0; mando.trim = modelo.compensador_grados || 0;
  entorno.configurarViento(ESCENARIOS[sesion.escenario].viento || sesion.viento);
  nuevoEvaluador(); vuelo = null; ponerPausa(false); ordenesAlEvaluador();
  if (visor.ponerOperacion) { const c = casa(); visor.ponerOperacion(ev.op ? ev.op.d : null, [c.N, c.E]); }
  if (visor.ponerPista) visor.ponerPista(pistaActual());
  DJI.grabando = false; DJI.tRec = 0; DJI.tAnt = 0; DJI.zoomI = 0; DJI.termica = false; mando.gimbal = 0;
  document.getElementById("guia").innerHTML = ""; ponerTxt($h("lejos"), "");
  iniciarJuegoBip();
  if (ESCENARIOS[sesion.escenario].enVuelo && !modelo.esTerrestre) { empezarEnVuelo(); return; }
  if (modelo.esBipode) { aviso("Pulsa L (o el botón A) para arrancar el bípode"); return; }
  if (modelo.tren) { av.frenoAparc = true; aviso("Pulsa L (o el botón A) para arrancar el motor"); return; }
  aviso(modelo.esFPV ? "Gas abajo del todo y L (o botón A) para armar" : modelo.esCuadricoptero ? "Pulsa el botón de despegue (⇧), L o la combinación de palancas para armar" : "Pulsa L para lanzar");
}
// en la zona 2 el piloto se da la vuelta: se lanza hacia el sur (la velocidad va en ejes cuerpo y no cambia)
function orientarLanzamiento() {
  const mundo = mundoDe(sesion.escenario);
  if (zonaDe(sesion.escenario) !== 2 && !mundo) return;
  const [roll, pitch] = Cuat.euler(av.q);
  const c = casa();
  av.q = Cuat.desdeEuler(roll, pitch, mundo ? (c.rumbo !== undefined ? c.rumbo : mundo.rumbo_despegue || 0) * D2R : Math.PI);
  // operaciones: el avion lanzado a mano (reconocimiento) sale de cara al viento, como se lanza de verdad
  if (ESCENARIOS[sesion.escenario].operacion && !modelo.tren && !modelo.esCuadricoptero && !modelo.esTerrestre && entorno.viento.base > 1) av.q = Cuat.desdeEuler(roll, pitch, entorno.viento.rumbo + Math.PI);
}
function lanzar() {
  if (modelo.esTerrestre && av.estado === "volando") {        // bipode en marcha: L lo aparca (si esta parado) y acaba
    if (Math.abs(av.vel) > 0.2) { toast("Para antes de aparcar"); return; }
    terminarVuelo("aparcado", [0, 0, 0]); return;
  }
  if (av.estado !== "en mano") return;
  modelo.lanzar(av); orientarLanzamiento(); if (modelo.esTerrestre) av.rumbo = ((Cuat.euler(av.q)[2] % (2 * Math.PI)) + 2 * Math.PI) % (2 * Math.PI);
  aviso(modelo.esCuadricoptero ? "Sube el gas (W o palanca izquierda arriba) para despegar" : modelo.tren ? "Motor en marcha: quita el freno (espacio) y acelera (W)" : "");
  if (modelo.esFPV) toast("ARMADO");
  if (modelo.esCuadricoptero) setTimeout(() => { if (av.estado === "volando" && av.posado) aviso(""); }, 3000);
  if (sesion.lanzReal && !modelo.facil && !modelo.esCuadricoptero && !modelo.esTerrestre && !modelo.tren) {          // un lanzamiento a mano nunca es perfecto: velocidad, cabeceo y alabeo al azar
    const gauss = () => (Math.random() + Math.random() + Math.random() - 1.5) / 0.5;    // ~N(0,1), acotada
    const [r, p, y] = Cuat.euler(av.q);
    av.v[0] *= 1 + 0.08 * gauss(); av.q = Cuat.desdeEuler(r + 4 * D2R * gauss(), p + 2.5 * D2R * gauss(), y + 3 * D2R * gauss());
  }
  vuelo = { id: uuid4(), inicio: new Date(), tVuelo: 0, filas: [], final: null, escenario: sesion.escenario, dificultad: sesion.dificultad, gasLanz: av.gases, hmax: 0 };
  cnContador = 0; RegistroVuelo.empezar(vuelo); grabarMuestra();
  const ap = Desgaste.avisosApp(modelo); if (ap.length) toast(ap.join(" · "));     // el autodiagnostico de la app al armar
  if (piloto && modelo.lanzado_a_mano) { piloto.c.rumbo = Cuat.euler(av.q)[2]; piloto.poner("LANZAMIENTO", av); piloto.c.rumbo = Cuat.euler(av.q)[2]; piloto.modoVisto = piloto.modo; }   // lanzado a mano: sube solo
}
function paso(dt) {
  aplicarRecorridos();
  let viento = entorno.actualizar(dt);
  let gasPalanca = null;
  if (piloto && av.estado === "volando" && piloto.modo !== "MANUAL") {      // UAV con el piloto automatico: las superficies, y el gas y el freno si los lleva
    piloto.vientoDesde = entorno.viento.rumbo - Math.PI; piloto.vientoVel = entorno.viento.base;     // la toma en perdida, contra el viento
    piloto.sens = modelo.sens || null;                                                                 // sensores averiados (el Grajo)
    const o = piloto.paso(av, dt, mando, av.gases);
    modelo.servos(av, Object.assign({}, mando, { pitch: o.pitch, yaw: o.yaw, guinada: o.guinada }), dt);
    if (o.gas !== null) { gasPalanca = av.gases; av.gases = o.gas; }
    if (o.freno !== null) av.freno = o.freno;
    if (piloto.modo !== piloto.modoVisto) { if (piloto.modoVisto) toast("Piloto automático: " + PUAV_NOMBRE[piloto.modo]); piloto.modoVisto = piloto.modo; }
  } else modelo.servos(av, mando, dt);
  av.agl = -av.p[2] - (entorno.altura ? entorno.altura(av.p[0], av.p[1]) : 0);
  if (modelo.tren && entorno.altura) {          // avion de pista: el suelo bajo cada rueda (el terreno no es plano)
    const g0 = -av.p[2] - av.agl; av.dSuelo = modelo.tren.ruedas.map(r => { const rw = Cuat.rot(av.q, r.p); return entorno.altura(av.p[0] + rw[0], av.p[1] + rw[1]) - g0; });
  }
  viento = entorno.vientoA(viento, av.agl);
  av.pg = entorno.rafagaAlabeo(modelo.b_m, av.agl);
  if (av.estado !== "volando") return;
  if (MULTI.caida) { caidaDerribado(dt); return; }          // multijugador: derribado por un bipode
  const pAnt = av.p.slice();
  if (modelo.esTerrestre) { pasoTerrestre(dt, viento, pAnt); return; }
  Desgaste.antesPaso(modelo, av);                // averias: superficies con holgura o bisagra floja (js/desgaste.js)
  const vn = modelo.paso(av, viento, dt);
  Desgaste.despuesPaso(modelo, av, dt);          // y vibraciones o el par de una helice danada
  if (av.roturaMontaje) { terminarVuelo("roto (" + av.roturaMontaje + ")", vn); return; }      // el Grajo con el ala sin asegurar
  avisosBateria();
  if (gasPalanca !== null) { av.gasMotor = av.gases; av.gases = gasPalanca; } else av.gasMotor = av.gases;   // la palanca del gas no se mueve: en crucero elige la velocidad
  if (vuelo) { vuelo.tVuelo += dt; vuelo.hmax = Math.max(vuelo.hmax, -av.p[2] - (entorno.altura ? entorno.altura(av.p[0], av.p[1]) : 0)); }
  if (modelo.tren) {                           // avion de pista: lo que rompe el tren o las alas en tierra y el final de la carrera
    let ft = modelo.finTren(av);
    if (!ft && av.enTierra && entorno.enMar && entorno.enMar(av.p[0], av.p[1])) ft = "roto (ha caído al mar)";
    if (ft) { terminarVuelo(ft, vn); return; }
  }
  // un entrenamiento solo se supera visto desde el piloto (camara 1); con el dron vale tambien la pantalla de la app (camara 3)
  if (vuelo && !vuelo.otraCamara && !camaraValida() && ESCENARIOS[sesion.escenario].objetivos.length) { vuelo.otraCamara = true; toast(conGafas() ? "Sin las gafas el entrenamiento no cuenta: vuelve a la cámara FPV (3)" : "Con esta cámara el entrenamiento no cuenta: vuelve a la del piloto (1)"); }
  if (++cnContador % CN_CADA === 0) { grabarMuestra(); evaluar(CN_CADA * DT); }
  if (av.estado !== "volando") return;
  if (entorno.chocaPilon(av.p, modelo.b_m / 2)) { terminarVuelo("roto (choque con un pilón)", vn); return; }
  if (entorno.chocaArbol(av.p, modelo.b_m / 2)) { terminarVuelo("roto (choque con un árbol)", vn); return; }
  if (entorno.chocaEdificio && entorno.chocaEdificio(av.p, modelo.b_m / 2)) { terminarVuelo("roto (choque con un edificio)", vn); return; }
  if (ev && ev.fpv) {                         // pista FPV: objetivos y choques con postes, puertas y torre
    for (const t of ev.fpv.paso(pAnt, av, dt, { modo: modelo.modo, critica: modelo.celda(av) < modelo.fc.critico_celda_V })) toast(textoFpv(t));
    if (ev.fpv.choque) { terminarVuelo("roto (" + ev.fpv.choque + ")", vn); return; }
  }
  if (ev && ev.op) {                          // operaciones: normas del operador, el trabajo y los choques con cables, torres y faro
    const camOp = (modelo.uav && av.torreta) || (!modelo.esCuadricoptero && ev.op.d.recon) ? Object.assign(camaraOp(), { grabando: false })   // UAV: la torreta o el morro fijo; avion: la camara de a bordo
      : { gimbal: av.gimbal, grabando: DJI.grabando };
    for (const t of ev.op.paso(pAnt, av, dt, Object.assign(camOp, camDJI(), { aterrizando: !!(piloto && piloto.modo === "ATERRIZAJE") }))) toast(t);
    if (ev.op.choque) { terminarVuelo("roto (" + ev.op.choque + ")", vn); return; }
    const C = ev.op.carr;
    if (C && C.tFin !== null && !C.anotado) {                         // carrera: la meta, el mejor de la sesion y la marca del vuelo
      C.anotado = true; const s = C.tFin - C.t0;
      if (!CARRERA_MEJOR || s < CARRERA_MEJOR.t) CARRERA_MEJOR = { t: s, avion: sesion.avion };
      if (vuelo) vuelo.marca = s;
    }
    const finC = ev.op.acabada ? ev.op.acabada(av.t) : null;
    if (finC) { terminarVuelo(finC, vn); return; }
  }
  if (entorno.fueraDeLimites(av.p)) { terminarVuelo("fuera de límites", vn); return; }
  const su = ev && ev.zona === 1 ? ev.contador.actualizar(pAnt, av.p, av.t) : null;
  if (ev && ev.zona <= 2 && !ev.fpv) zona2(pAnt);
  if (su) {
    const nom = entorno.circuito.colores[su.i].nombre, sen = ESCENARIOS[sesion.escenario].sentido;
    toast(su.tipo === "vuelta" ? `¡Vuelta ${su.n}!  ${su.tiempo.toFixed(1)} s` : su.tipo === "dentro" ? `¡Por dentro del pilón ${nom}! Vuelta anulada` :
          su.tipo === "sentido" ? `¡Sentido contrario en el ${nom}! El orden es ${entorno.ordenPilones(sen)}` :
          su.n === 1 ? `Pilón ${nom}: salida` : `Pilón ${nom} ${su.n - 1}/4`);
  }
  const suelo = entorno.contactoSuelo(av, vn, modelo.toma_perdida);
  if (suelo) terminarVuelo(suelo, vn);
}
/** Avisos de la bateria (js/bateria.js), una vez cada uno: el dron con poca bateria (av.avisoBat del modelo: baja, vuelta a
 *  casa por bateria, aterrizaje forzoso), el avion al 20 % y con el motor cortado por el regulador, y sin bateria. */
function avisosBateria() {
  if (!av.bat) return;
  const pct = modelo.bateriaPct(av), k = (av.avisoBat || (!modelo.esCuadricoptero && pct <= 20 ? "baja" : "")) + (av.cortado ? "+cortado" : "") + (av.sinBateria ? "+agotada" : "");
  if (k === (av._batVisto || "")) return;
  const ant = av._batVisto || ""; av._batVisto = k;
  if (av.sinBateria && !ant.includes("+agotada")) { toast("Batería agotada: los motores se paran"); return; }
  if (av.cortado && !ant.includes("+cortado")) { toast("El regulador ha cortado el motor: batería agotada. Planea y aterriza"); aviso("Motor cortado: batería agotada"); return; }
  if (k.startsWith("baja") && !ant.startsWith("baja")) toast(modelo.esCuadricoptero ? "Batería baja (30 %): vuelve pronto" : "Batería baja (20 %): aterriza pronto");
  if (k.startsWith("rth") && !ant.startsWith("rth")) toast("Batería justa para volver: volviendo a casa (mueve las palancas para cancelar)");
  if (k.startsWith("critica") && !ant.startsWith("critica")) { toast("¡Batería crítica! Aterrizaje forzoso: busca dónde posarlo"); aviso("Aterrizaje forzoso: batería crítica"); }
  if (k.startsWith("celda") && !ant.startsWith("celda")) { toast("¡Tensión de celda muy baja! Aterrizaje forzoso"); aviso("Aterrizaje forzoso: una celda de la batería se ha hundido"); }
}
/** Un paso del bipode: la pendiente del terreno (a 1,5 m delante/detras y a los lados), el paso del modelo, la altura del
 *  terreno donde queda y los choques: arboles, pilones y edificios lo paran (no lo rompen); en el mar se hunde. */
function pasoTerrestre(dt, viento, pAnt) {
  const H = entorno.altura ? (N, E) => entorno.altura(N, E) : () => 0, p = av.p, d = 1.5;
  av.pendiente = [(H(p[0] + d, p[1]) - H(p[0] - d, p[1])) / (2 * d), (H(p[0], p[1] + d) - H(p[0], p[1] - d)) / (2 * d)];
  const vn = modelo.paso(av, viento, dt);
  if (vuelo) vuelo.tVuelo += dt;
  if (entorno.chocaArbol(av.p, 1.1) || entorno.chocaPilon(av.p, 1.1) || entorno.chocaEdificio(av.p, 1.6)) { av.p = pAnt.slice(); av.vel = 0; if (!pasoTerrestre.aviso) { pasoTerrestre.aviso = true; toast("¡Choque! Da la vuelta"); setTimeout(() => pasoTerrestre.aviso = false, 1500); } }
  av.p[2] = -H(av.p[0], av.p[1]);
  if (++cnContador % CN_CADA === 0) { grabarMuestra(); evaluar(CN_CADA * DT); }
  if (entorno.enMar && entorno.enMar(av.p[0], av.p[1])) { terminarVuelo("roto (se ha hundido en el mar)", vn); return; }
  if (entorno.fueraDeLimites(av.p)) { terminarVuelo("fuera de límites", vn); return; }
}
/** El juego del bipode: drones diana y disparos (js/bipode.js, JuegoBipode), con sus efectos en el visor. */
let juegoBip = null;
function iniciarJuegoBip() {
  if (visor.efectosBip) { visor.efectosBip.quitar(); visor.efectosBip = null; }
  juegoBip = null;
  if (!modelo.esBipode) return;
  juegoBip = new JuegoBipode(Modelos.datos(sesion.avion), (Date.now() % 100000) + 1);
  juegoBip.iniciar([av.p[0], av.p[1]], entorno.altura ? (N, E) => entorno.altura(N, E) : null);
  visor.efectosBip = ModeloBipode.efectos3D(visor.escena);
  juegoBip.pisadas = av.pisadas; juegoBip.disparosOido = av.disparos; juegoBip.derribadosOido = 0;
}
function pasoJuegoBip(dt) {
  pasoBalasOtros(dt);
  const J = juegoBip; if (!J) return;
  J.blancos = blancosSala();
  if (av.estado === "volando") J.paso(dt, av, modelo, entorno.altura ? (N, E) => entorno.altura(N, E) : null);
  // sonido: pisadas, disparos, explosiones
  if (av.pisadas !== J.pisadas) { J.pisadas = av.pisadas; Sonido.evento("pisada"); }
  if (av.disparos !== J.disparosOido) { J.disparosOido = av.disparos; Sonido.evento("disparo"); }
  for (const e of J.eventos) if (e.tipo === "explosion") Sonido.evento("explosion");
  if (J.derribados !== J.derribadosOido) { J.derribadosOido = J.derribados; toast(`¡Dron derribado! (${J.derribados})`); }
  if (visor.efectosBip) visor.efectosBip.pintar(J, dt, visor.cam); else J.eventos.length = 0;
  document.getElementById("bipDrones").textContent = "DRONES DERRIBADOS " + J.derribados;
  const B = modelo.bp, w = av.wCanones / (B.cadencia_rpm / 60 / 6 * 2 * Math.PI);
  document.getElementById("bipCanon").textContent = av.cmd.fuego ? (w > 0.8 ? "FUEGO" : "CAÑÓN ACELERANDO " + Math.round(w * 100) + " %") : "CAÑÓN LISTO";
  // mira (camaras 2 y 3): donde apunta de verdad el cañon, el punto a 120 m sobre su linea de tiro proyectado en la pantalla
  const ap = modelo.apuntado(av), P = ned2three([ap.o[0] + ap.d[0] * 120, ap.o[1] + ap.d[1] * 120, ap.o[2] + ap.d[2] * 120]);
  const v = new THREE.Vector3(P[0], P[1], P[2]).project(visor.cam), mira = document.getElementById("miraBip");
  const dentro = v.z < 1 && Math.abs(v.x) < 1.05 && Math.abs(v.y) < 1.05;
  mira.style.left = ((v.x + 1) / 2 * 100) + "%"; mira.style.top = ((1 - v.y) / 2 * 100) + "%";
  document.body.classList.toggle("miraBip", (visor.camara === 2 || visor.camara === 3) && dentro);
}
/** Puerta y pasadas bajas de la zona 2 (en sus misiones y en vuelo libre), con su aviso. */
function zona2(pAnt) {
  const pu = entorno.cruzaPuerta(pAnt, av.p);
  if (pu) {
    if (pu.tipo === "puerta") {
      ev.puertas++;
      if (ev.obj.puertaR && ev.obj.pasada && ev.obj.pasada.estado === "ok") marcar("puertaR", "ok");
      toast(`¡Puerta ${ev.puertas}!  (hacia el ${pu.sentido}, a ${pu.h.toFixed(0)} m)`);
    } else toast(pu.tipo === "alta" ? `Por encima de la puerta (${pu.h.toFixed(0)} m): no cuenta` : "Por fuera de la puerta: no cuenta");
  }
  if (!ev.subido) return;          // el lanzamiento cruza la pista 2: las pasadas cuentan despues de subir
  const pb = ev.pasada.actualizar(av.p);
  if (pb) {
    if (pb.ok) { ev.pasadas[pb.sentido]++; toast(`¡Pasada baja hacia el ${pb.sentido}!  (${pb.hmin.toFixed(1)}–${pb.hmax.toFixed(1)} m)`); }
    else toast("Pasada baja no válida: " + pb.motivo);
  }
}
function terminarVuelo(final, vn) {
  if (av.estado !== "volando") return;
  // lanzamiento fallido: acaba en el suelo antes de LANZ.fallo_s sin haber subido de LANZ.fallo_h. No cuenta como
  // aterrizaje; si se ha roto, si como accidente
  if (vuelo && !modelo.esCuadricoptero && !modelo.esTerrestre && !modelo.tren && !modelo.lanzado_a_mano && av.t < LANZ.fallo_s && vuelo.hmax < LANZ.fallo_h && (final === "aterrizado" || final.startsWith("roto"))) {
    vuelo.lanzamiento = causaLanzamientoFallido(vuelo.gasLanz);
    final = (final.startsWith("roto") ? "roto (" : "") + "lanzamiento fallido: " + vuelo.lanzamiento.corto + (final.startsWith("roto") ? ")" : "");
  }
  av.estado = final.startsWith("roto") ? "roto" : final === "aterrizado" ? "aterrizado" : "terminado";
  av.v = [0, 0, 0]; av.w = [0, 0, 0]; av.rpm = 0;
  document.getElementById("guia").innerHTML = "";
  if (!vuelo) return;
  vuelo.final = final; grabarMuestra(); RegistroVuelo.cerrar(vuelo); desgasteTrasVuelo(vuelo, final);
  evaluarFinal(final, vn || [0, 0, 0]);
  aviso(vuelo.lanzamiento ? "LANZAMIENTO FALLIDO: " + vuelo.lanzamiento.corto
        : final.startsWith("roto") ? "¡ROTO!  (" + final.slice(6, -1) + ")" : final === "aterrizado" ? "Aterrizado"
        : final === "fuera de límites" ? "FUERA DE LÍMITES: el avión se ha perdido de vista" : "");
  ponerTxt($h("lejos"), "");
  ultimoVuelo = vuelo;
  document.getElementById("cnUltimo").disabled = false;
  if (document.getElementById("cnAuto").checked) descargarVuelo(vuelo);
  if (final === "aterrizado" || final.startsWith("roto")) Sonido.evento(final.startsWith("roto") ? "roto" : "toque");
  const v = vuelo;
  if (salirTras) { salirTras = false; guardarVuelo(v, datosResultado(v)); irInicio(); return; }
  // solo si sigue siendo el vuelo en curso: si en esos 1,8 s se ha pulsado R o se ha salido, el resultado ya no toca
  setTimeout(() => { if (vuelo === v && pantallaActual === null && !Repeticion.activa) mostrarResultado(v); }, final === "abandonado" ? 0 : 1800);
}

/** Despues de cada vuelo, el desgaste del vehiculo (js/desgaste.js): horas, bateria y lo que se estropea; y las averias
 *  que el profesor ha puesto en vuelo (sala multijugador). Se guarda en el aula (o en el ordenador). */
function desgasteTrasVuelo(v, final) {
  if (!Desgaste.clase(modelo)) return;
  const R = v.reg, col = n => { const i = R ? R.columnas.indexOf(n) : -1; return i < 0 ? [] : R.filas.map(f => f[i]).filter(x => typeof x === "number"); };
  const T = col("temperatura_bateria_C"), B = modelo.B ? col("bateria_pct") : [], A = Modelos.datos(sesion.avion), extra = (v.averiasSala || []).slice();
  const info = { s: av.t, roto: final.startsWith("roto"), bat0: B.length ? B[0] : null, bat1: B.length ? B[B.length - 1] : null,
                 tempMax: T.length ? Math.max(...T) : null, semilla: v.id, fecha: new Date().toISOString(), tomaPerdida: !!av.tomaPerdida };
  Desgaste.modificar(sesion.avion, est => { for (const a of extra) Desgaste.anadir(est, a, "profesor", info.fecha); return Desgaste.trasVuelo(est, A, info); });
}
