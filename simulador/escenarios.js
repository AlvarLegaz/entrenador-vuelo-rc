// Entrenamientos y vuelos libres del simulador: datos COMUNES de la version web (simulador.html) y de la de Godot
// (simulador_godot/scripts/escenarios.gd). Es JSON estricto dentro de una asignacion: Godot lee el objeto que va
// detras de "window.ESCENARIOS = ". La logica (evaluar los objetivos, la guia del aterrizaje) esta en el codigo de cada
// version. Campos: nombre, desc, objetivos [[id, texto]], sentido (circuito: 1 o -1), zona (2: detras del piloto;
// 3: mundo real), mundo (id del mundo real), viento fijo {vel, desde, rachas}, guia, enVuelo {N, E, h, rumbo, gas},
// dificultad (estrellas, 1-3), titulo_grupo (cabecera de su grupo en la pantalla de entrenamientos) y destacados
// (vuelo libre en un mundo real: puntos de despegue resaltados en el mapa de salida, con contorno lat/lon y rumbo).
window.ESCENARIOS = {
 "primer_vuelo": {
  "nombre": "1 · Primer vuelo",
  "sentido": 1,
  "desc": "Lanza el avión, da dos vueltas al circuito rodeando por fuera los 4 pilones en el orden indicado (subes por la izquierda y vuelves por la derecha) y aterriza.",
  "objetivos": [
   [
    "subir",
    "Lanzar y subir a 20 m"
   ],
   [
    "circ1",
    "Primera vuelta por fuera de los 4 pilones, en orden"
   ],
   [
    "circ2",
    "Segunda vuelta por fuera de los 4 pilones, en orden"
   ],
   [
    "aterrizar",
    "Aterrizar sin daños"
   ]
  ],
  "dificultad": 1,
  "titulo_grupo": "Zona 1 · Circuito de pilones (cuentan para el avión real)"
 },
 "orientacion": {
  "nombre": "2 · Orientación",
  "desc": "Dos ochos alrededor de los pilones: por fuera del rojo y el azul, cruzas el centro, por fuera del amarillo y el verde, y vuelta al rojo. Sin alejarte y sin entrar en pérdida.",
  "objetivos": [
   [
    "subir",
    "Subir a 20 m"
   ],
   [
    "ocho1",
    "Primer ocho: por fuera del rojo y el azul, por fuera del amarillo y el verde, vuelta al rojo"
   ],
   [
    "ocho2",
    "Segundo ocho igual"
   ],
   [
    "cerca",
    "No alejarse más de 200 m"
   ],
   [
    "sinPerdida",
    "Sin entrar en pérdida"
   ],
   [
    "aterrizar",
    "Aterrizar sin daños"
   ]
  ],
  "dificultad": 1
 },
 "viento_cruzado": {
  "nombre": "3 · Viento cruzado",
  "sentido": -1,
  "desc": "Viento de 4 m/s del oeste, de lado a la pista. Una vuelta al circuito en el orden indicado (al revés que en el primer vuelo: subes por la derecha), corrige la deriva y aterriza en la pista.",
  "viento": {
   "vel": 4,
   "desde": 270,
   "rachas": true
  },
  "objetivos": [
   [
    "subir",
    "Subir a 20 m"
   ],
   [
    "circ1",
    "Una vuelta por fuera de los 4 pilones, en orden"
   ],
   [
    "enPista",
    "Tocar tierra en la pista"
   ],
   [
    "alineado",
    "Toma alineada con la pista (±25°)"
   ],
   [
    "aterrizar",
    "Aterrizar sin daños"
   ]
  ],
  "dificultad": 2
 },
 "emergencia": {
  "nombre": "4 · Emergencia",
  "desc": "Sube a 40 m. En algún momento el motor se para: planea y aterriza cerca de ti.",
  "objetivos": [
   [
    "subir40",
    "Subir a 40 m"
   ],
   [
    "fallo",
    "Fallo de motor: mantener el control (sin pérdida)"
   ],
   [
    "aterrizar",
    "Aterrizar sin daños"
   ],
   [
    "cerca100",
    "Aterrizar a menos de 100 m del piloto"
   ]
  ],
  "dificultad": 3
 },
 "puerta": {
  "nombre": "5 · Puerta",
  "zona": 2,
  "desc": "Cruza la puerta de pilones naranjas tres veces, de lado a lado (de este a oeste o al revés), por debajo de lo alto de los pilones (20 m), y aterriza.",
  "objetivos": [
   [
    "subir",
    "Subir a 20 m"
   ],
   [
    "puerta1",
    "Primer paso por la puerta"
   ],
   [
    "puerta2",
    "Segundo paso por la puerta"
   ],
   [
    "puerta3",
    "Tercer paso por la puerta"
   ],
   [
    "aterrizar",
    "Aterrizar sin daños"
   ]
  ],
  "dificultad": 2,
  "titulo_grupo": "Zona 2 · Precisión, detrás del piloto (práctica)"
 },
 "pasada_baja": {
  "nombre": "6 · Pasada baja",
  "zona": 2,
  "desc": "Recorre la pista 2 de punta a punta entre 2 y 8 m de altura sin tocar el suelo ni salirte por los lados: una pasada hacia cada lado.",
  "objetivos": [
   [
    "subir",
    "Subir a 20 m"
   ],
   [
    "pasadaO",
    "Pasada baja hacia el oeste (de izquierda a derecha, mirando a la zona 2)"
   ],
   [
    "pasadaE",
    "Pasada baja hacia el este (de derecha a izquierda)"
   ],
   [
    "aterrizar",
    "Aterrizar sin daños"
   ]
  ],
  "dificultad": 3
 },
 "diana": {
  "nombre": "7 · Diana",
  "zona": 2,
  "desc": "Aterriza en la diana del centro de la pista 2: 100 puntos dentro del círculo de 5 m, 50 en el de 10 m y 20 en el de 20 m.",
  "objetivos": [
   [
    "subir",
    "Subir a 20 m"
   ],
   [
    "aterrizar",
    "Aterrizar sin daños"
   ],
   [
    "diana10",
    "Tomar a menos de 10 m del centro de la diana"
   ]
  ],
  "dificultad": 3
 },
 "recorrido": {
  "nombre": "8 · Recorrido de precisión",
  "zona": 2,
  "desc": "Todo seguido y en este orden: una pasada baja por la pista 2, un paso por la puerta y el aterrizaje en la diana.",
  "objetivos": [
   [
    "subir",
    "Subir a 20 m"
   ],
   [
    "pasada",
    "1. Pasada baja válida por la pista 2"
   ],
   [
    "puertaR",
    "2. Después, un paso por la puerta"
   ],
   [
    "dianaR",
    "3. Después, aterrizar a menos de 10 m del centro de la diana"
   ],
   [
    "aterrizar",
    "Aterrizar sin daños"
   ]
  ],
  "dificultad": 3
 },
 "aterrizaje": {
  "nombre": "9 · Aterrizaje guiado",
  "guia": true,
  "enVuelo": {
   "N": 60,
   "E": 0,
   "h": 35,
   "rumbo": 0,
   "gas": 0.55
  },
  "desc": "Empiezas ya volando, a 35 m sobre la pista y rumbo norte. La pantalla te va guiando por el circuito de aterrizaje: viraje a la derecha, tramo con el viento en cola por tu derecha, base, final alineado con la pista y toma suave.",
  "objetivos": [
   [
    "viraje1",
    "1. Viraje a la derecha hasta rumbo sur (180°)"
   ],
   [
    "viento_cola",
    "2. Tramo de viento en cola por tu derecha, bajando a 20 m"
   ],
   [
    "base",
    "3. Base: viraje a rumbo oeste (270°), bajando a 10–15 m"
   ],
   [
    "final",
    "4. Final: rumbo norte, alineado con la pista, con poco gas"
   ],
   [
    "enPista",
    "Tocar tierra en la pista"
   ],
   [
    "alineado",
    "Toma alineada con la pista (±25°)"
   ],
   [
    "suave",
    "Toma suave (menos de 1,5 m/s de descenso)"
   ],
   [
    "aterrizar",
    "Aterrizar sin daños"
   ]
  ],
  "dificultad": 2,
  "titulo_grupo": "Guiado (práctica)"
 },
 "libre_cartagena": {
  "nombre": "Vuelo libre · Campo de Cartagena (mapa real)",
  "mundo": "cartagena",
  "zona": 3,
  "desc": "Mapa real de 78 × 38 km: Cartagena, el Mar Menor, La Manga, la sierra de la Muela, Cabo de Palos, Mazarrón y el Campo de Cartagena, con el relieve de verdad, las carreteras, los pueblos y los almendros. Sales desde el corazón del mapa (al oeste de Cartagena) y no hay límite de alcance. Sin objetivos: cuenta como horas de entrenamiento.",
  "objetivos": [],
  "destacados": [
   {
    "nombre": "CIFP Politécnico",
    "nota": "Aparcamiento interior del CIFP Politécnico (calle Grecia, 56): despegue hacia el este-sudeste, sobre el campo abierto. Zona de detalle a 0,25 m (cifp_politecnico).",
    "lat": 37.613315,
    "lon": -0.974488,
    "rumbo": 110,
    "contorno": [[37.613164, -0.975122], [37.613178, -0.974609], [37.613191, -0.974021], [37.613200, -0.973826], [37.614295, -0.972974], [37.615252, -0.974800], [37.613979, -0.975854], [37.613164, -0.975122]]
   },
   {
    "nombre": "Los Halcones de la Rambla",
    "nota": "Campo del Club Deportivo de Aeromodelismo Los Halcones de la Rambla (El Jimenado, Torre-Pacheco): pista de asfalto orientada 250-70; despegue desde la cabecera este hacia el 250. Zona de detalle a 0,25 m (halcones_rambla).",
    "lat": 37.761795,
    "lon": -1.012243,
    "rumbo": 250,
    "contorno": [[37.761587, -1.013745], [37.762469, -1.011307], [37.761791, -1.010939], [37.760977, -1.013462]]
   }
  ]
 },
 "libre": {
  "nombre": "Vuelo libre",
  "desc": "Sin objetivos. Cuenta para las horas de entrenamiento. Da vueltas al circuito por fuera de los pilones, en el sentido que quieras: se cronometra cada vuelta. También puedes darte la vuelta y practicar en la zona 2.",
  "objetivos": []
 }
};
