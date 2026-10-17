// Indice de los escenarios (entrenamientos, operaciones y vuelos libres): datos COMUNES de la version web (simulador.html) y de la de Godot
// (simulador_godot/scripts/escenarios.gd). Es JSON estricto dentro de una asignacion: Godot lee el objeto que va
// detras de "window.ESCENARIOS = ". La logica (evaluar los objetivos, la guia del aterrizaje) esta en el codigo de cada
// version. Campos: nombre, desc, objetivos [[id, texto]], sentido (circuito: 1 o -1), zona (2: detras del piloto;
// 3: mundo real), mundo (id del mundo real), viento fijo {vel, desde, rachas}, guia, enVuelo {N, E, h, rumbo, gas},
// dificultad (estrellas, 1-3), titulo_grupo (cabecera de su grupo en la pantalla de entrenamientos) y destacados
// (vuelo libre en un mundo real: puntos de despegue resaltados en el mapa de salida, con contorno lat/lon y rumbo, y
// sin_arboles: poligono [N, E] del plano del mundo donde no se ponen los arboles detectados en la ortofoto),
// vehiculos (en que vehiculos sale en la pantalla de entrenamientos: "avion", "dron" (el dron comercial) y "fpv") y pista_fpv (los
// entrenamientos del dron FPV: plataforma de salida, modo de Betaflight, camara, y los conos, postes, puertas y torre de
// cada uno, en (N, E) metros desde el piloto; los evaluan js/pista_fpv.js y simulador_godot/scripts/pista_fpv.gd) y
// operacion (los trabajos de operador de dron del modo Operaciones: orden de trabajo, punto de despegue y lo que hay que
// fotografiar, cubrir, buscar o grabar, en (N, E) metros del plano del mundo real; los evaluan js/operaciones.js y
// simulador_godot/scripts/operaciones.gd). Las operaciones no salen en la pantalla de entrenamientos.
//
// Cada escenario va en su fichero (entrenamientos/<id>.js, operaciones/<id>.js y los vuelos libres en escenarios/<id>.js),
// que hace ESCENARIOS["<id>"] = {...} con JSON estricto. Esta lista da el orden en el que salen en la app: la web los
// carga en este orden (simulador_web/simulador.html) y Godot (scripts/escenarios.gd) y Python (datos/leer_datos.py) leen
// la lista y despues cada fichero.
window.ESCENARIOS = {};
window.ESCENARIOS_FICHEROS = [
 "entrenamientos/primer_vuelo.js",
 "entrenamientos/orientacion.js",
 "entrenamientos/viento_cruzado.js",
 "entrenamientos/emergencia.js",
 "entrenamientos/puerta.js",
 "entrenamientos/pasada_baja.js",
 "entrenamientos/diana.js",
 "entrenamientos/recorrido.js",
 "entrenamientos/aterrizaje.js",
 "entrenamientos/fpv_estacionario.js",
 "entrenamientos/fpv_caja.js",
 "entrenamientos/fpv_slalom.js",
 "entrenamientos/fpv_circuito.js",
 "entrenamientos/fpv_acro.js",
 "entrenamientos/fpv_tecnica.js",
 "operaciones/op_inspeccion.js",
 "operaciones/op_fotogrametria.js",
 "operaciones/op_busqueda.js",
 "operaciones/op_agricultura.js",
 "operaciones/op_paneles.js",
 "operaciones/op_video.js",
 "operaciones/op_sabic.js",
 "operaciones/op_rec_itinerario.js",
 "operaciones/op_rec_vigilancia.js",
 "operaciones/op_rec_busqueda.js",
 "operaciones/op_patrulla.js",
 "operaciones/op_carrera.js",
 "escenarios/libre_cartagena.js",
 "escenarios/libre.js"
];
