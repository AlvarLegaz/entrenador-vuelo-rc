// Entrenamientos y vuelos libres del simulador: datos COMUNES de la version web (simulador.html) y de la de Godot
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
window.ESCENARIOS = {
 "primer_vuelo": {
  "vehiculos": ["avion", "dron"],
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
  "vehiculos": ["avion", "dron"],
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
  "vehiculos": ["avion"],
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
  "vehiculos": ["avion"],
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
  "vehiculos": ["avion", "dron"],
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
  "vehiculos": ["avion", "dron"],
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
  "vehiculos": ["avion", "dron"],
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
  "vehiculos": ["avion", "dron"],
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
  "vehiculos": ["avion"],
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
 "fpv_estacionario": {
  "nombre": "1 · Despegue y estacionario",
  "vehiculos": [
   "fpv"
  ],
  "zona": 2,
  "dificultad": 1,
  "viento": {
   "vel": 0,
   "desde": 0,
   "rachas": false
  },
  "titulo_grupo": "Pista FPV, detrás del piloto (desde la misión 2, con las gafas)",
  "desc": "Arma con el gas abajo, despega de la plataforma y quédate quieto 20 s seguidos dentro del cilindro azul (entre 1,5 y 2,5 m de altura). Luego vuelve a la plataforma, aterriza y desarma. Modo ANGLE: se nivela solo.",
  "objetivos": [
   [
    "despegar",
    "Armar con el gas abajo y despegar"
   ],
   [
    "estacionario",
    "20 s seguidos dentro del cilindro (2 m de radio, entre 1,5 y 2,5 m)"
   ],
   [
    "plataforma",
    "Aterrizar en la plataforma de salida"
   ],
   [
    "desarmar",
    "Desarmar antes de 3 s después de posarlo"
   ],
   [
    "modo",
    "En modo ANGLE todo el vuelo"
   ],
   [
    "bateria",
    "Aterrizar antes del ¡ATERRIZA YA! de la batería"
   ],
   [
    "aterrizar",
    "Aterrizar sin daños"
   ]
  ],
  "pista_fpv": {
   "salida": [
    -20,
    0
   ],
   "modo": "ANGLE",
   "camara": "libre",
   "cilindro": {
    "n": -32,
    "e": 0,
    "r": 2,
    "h0": 1.5,
    "h1": 2.5,
    "t": 20
   }
  }
 },
 "fpv_caja": {
  "nombre": "2 · La caja",
  "vehiculos": [
   "fpv"
  ],
  "zona": 2,
  "dificultad": 1,
  "viento": {
   "vel": 0,
   "desde": 0,
   "rachas": false
  },
  "desc": "Cuatro conos en cuadrado: tócalos en orden (verde, amarillo, rojo, azul) con el morro siempre hacia el sur, solo con la palanca derecha. Después otra vez, girando el morro hacia cada cono. Sin pasar de 4 m, con las gafas.",
  "objetivos": [
   [
    "caja1",
    "Los 4 conos en orden con el morro siempre al sur"
   ],
   [
    "caja2",
    "Otra vez los 4, llegando a cada cono con el morro hacia él"
   ],
   [
    "bajo4",
    "Sin pasar de 4 m de altura"
   ],
   [
    "plataforma",
    "Aterrizar en la plataforma de salida"
   ],
   [
    "desarmar",
    "Desarmar antes de 3 s después de posarlo"
   ],
   [
    "modo",
    "En modo ANGLE todo el vuelo"
   ],
   [
    "bateria",
    "Aterrizar antes del ¡ATERRIZA YA! de la batería"
   ],
   [
    "aterrizar",
    "Aterrizar sin daños"
   ]
  ],
  "pista_fpv": {
   "salida": [
    -20,
    0
   ],
   "modo": "ANGLE",
   "camara": "gafas",
   "conos": [
    [
     -28,
     -10
    ],
    [
     -48,
     -10
    ],
    [
     -48,
     10
    ],
    [
     -28,
     10
    ]
   ],
   "techo": 4
  }
 },
 "fpv_slalom": {
  "nombre": "3 · Slalom y ocho",
  "vehiculos": [
   "fpv"
  ],
  "zona": 2,
  "dificultad": 2,
  "viento": {
   "vel": 2,
   "desde": 270,
   "rachas": true
  },
  "desc": "Slalom hacia el sur entre los 5 postes, alternando el lado, y al fondo un ocho alrededor del poste rojo y el azul (cada uno en un sentido). Giros coordinados (alabeo y guiñada a la vez), entre 1 y 3 m de altura. Modo HORIZON.",
  "objetivos": [
   [
    "slalom",
    "Slalom: los 5 postes en orden, alternando el lado"
   ],
   [
    "ocho",
    "Un ocho alrededor del poste rojo y el azul"
   ],
   [
    "altura13",
    "Entre 1 y 3 m de altura en el slalom y el ocho"
   ],
   [
    "plataforma",
    "Aterrizar en la plataforma de salida"
   ],
   [
    "desarmar",
    "Desarmar antes de 3 s después de posarlo"
   ],
   [
    "modo",
    "En modo HORIZON todo el vuelo"
   ],
   [
    "bateria",
    "Aterrizar antes del ¡ATERRIZA YA! de la batería"
   ],
   [
    "aterrizar",
    "Aterrizar sin daños"
   ]
  ],
  "pista_fpv": {
   "salida": [
    -20,
    0
   ],
   "modo": "HORIZON",
   "camara": "gafas",
   "postes": [
    [
     -55,
     0
    ],
    [
     -70,
     0
    ],
    [
     -85,
     0
    ],
    [
     -100,
     0
    ],
    [
     -115,
     0
    ]
   ],
   "ocho": [
    [
     -135,
     -12
    ],
    [
     -135,
     12
    ]
   ],
   "banda": [
    1,
    3
   ]
  }
 },
 "fpv_circuito": {
  "nombre": "4 · Circuito de puertas",
  "vehiculos": [
   "fpv"
  ],
  "zona": 2,
  "dificultad": 2,
  "viento": {
   "vel": 2,
   "desde": 270,
   "rachas": true
  },
  "desc": "Dos vueltas al circuito de 6 puertas numeradas, en orden y por delante (las flechas del suelo marcan el sentido). Si te saltas una, vuelve a por ella. Se cronometra cada vuelta; tocar una puerta es un choque. Modo HORIZON, con las gafas.",
  "objetivos": [
   [
    "vuelta1",
    "Primera vuelta: las 6 puertas en orden"
   ],
   [
    "vuelta2",
    "Segunda vuelta"
   ],
   [
    "plataforma",
    "Aterrizar en la plataforma de salida"
   ],
   [
    "desarmar",
    "Desarmar antes de 3 s después de posarlo"
   ],
   [
    "modo",
    "En modo HORIZON todo el vuelo"
   ],
   [
    "bateria",
    "Aterrizar antes del ¡ATERRIZA YA! de la batería"
   ],
   [
    "aterrizar",
    "Aterrizar sin daños"
   ]
  ],
  "pista_fpv": {
   "salida": [
    -20,
    0
   ],
   "modo": "HORIZON",
   "camara": "gafas",
   "puertas": [
    {
     "n": -60,
     "e": -25,
     "rumbo": 180
    },
    {
     "n": -95,
     "e": -35,
     "rumbo": 180
    },
    {
     "n": -130,
     "e": -10,
     "rumbo": 90
    },
    {
     "n": -120,
     "e": 30,
     "rumbo": 0
    },
    {
     "n": -85,
     "e": 35,
     "rumbo": 0
    },
    {
     "n": -60,
     "e": 15,
     "rumbo": 270
    }
   ],
   "vueltas": 2
  }
 },
 "fpv_acro": {
  "nombre": "5 · Paso a ACRO",
  "vehiculos": [
   "fpv"
  ],
  "zona": 2,
  "dificultad": 3,
  "viento": {
   "vel": 2,
   "desde": 270,
   "rachas": true
  },
  "desc": "En ACRO no se nivela solo: inclinas y se queda inclinado. Primero, la pista 2 de punta a punta hacia cada lado entre 1,5 y 4 m (la cámara va inclinada: para avanzar recto hay que llevar el morro abajo). Después, una vuelta al circuito de puertas.",
  "objetivos": [
   [
    "rectaO",
    "Recta por la pista 2 hacia el oeste, entre 1,5 y 4 m"
   ],
   [
    "rectaE",
    "Recta por la pista 2 hacia el este, entre 1,5 y 4 m"
   ],
   [
    "vuelta1",
    "Una vuelta al circuito de puertas"
   ],
   [
    "plataforma",
    "Aterrizar en la plataforma de salida"
   ],
   [
    "desarmar",
    "Desarmar antes de 3 s después de posarlo"
   ],
   [
    "modo",
    "En modo ACRO todo el vuelo"
   ],
   [
    "bateria",
    "Aterrizar antes del ¡ATERRIZA YA! de la batería"
   ],
   [
    "aterrizar",
    "Aterrizar sin daños"
   ]
  ],
  "pista_fpv": {
   "salida": [
    -20,
    0
   ],
   "modo": "ACRO",
   "camara": "gafas",
   "puertas": [
    {
     "n": -60,
     "e": -25,
     "rumbo": 180
    },
    {
     "n": -95,
     "e": -35,
     "rumbo": 180
    },
    {
     "n": -130,
     "e": -10,
     "rumbo": 90
    },
    {
     "n": -120,
     "e": 30,
     "rumbo": 0
    },
    {
     "n": -85,
     "e": 35,
     "rumbo": 0
    },
    {
     "n": -60,
     "e": 15,
     "rumbo": 270
    }
   ],
   "vueltas": 1,
   "recta": {
    "n": -45,
    "e0": -35,
    "e1": 35,
    "ancho": 10,
    "margen": 1,
    "hmin": 1.5,
    "hmax": 4
   }
  }
 },
 "fpv_tecnica": {
  "nombre": "6 · Técnica",
  "vehiculos": [
   "fpv"
  ],
  "zona": 2,
  "dificultad": 3,
  "desc": "En ACRO y con el viento que elijas: un power loop sobre la puerta alta (la cruzas, subes por encima y vuelves a cruzarla en el mismo sentido), un split-S (la cruzas y vuelves por ella en sentido contrario) y un picado desde lo alto de la torre de 25 m.",
  "objetivos": [
   [
    "powerloop",
    "Power loop: cruzar la puerta alta y volver a cruzarla en el mismo sentido, pasando por encima, en menos de 6 s"
   ],
   [
    "splits",
    "Split-S: cruzar la puerta alta y volver por ella en sentido contrario en menos de 5 s"
   ],
   [
    "picado",
    "Picado: desde encima de la torre (25 m) hasta menos de 5 m en menos de 4 s"
   ],
   [
    "plataforma",
    "Aterrizar en la plataforma de salida"
   ],
   [
    "desarmar",
    "Desarmar antes de 3 s después de posarlo"
   ],
   [
    "modo",
    "En modo ACRO todo el vuelo"
   ],
   [
    "bateria",
    "Aterrizar antes del ¡ATERRIZA YA! de la batería"
   ],
   [
    "aterrizar",
    "Aterrizar sin daños"
   ]
  ],
  "pista_fpv": {
   "salida": [
    -20,
    0
   ],
   "modo": "ACRO",
   "camara": "gafas",
   "puerta_alta": {
    "n": -80,
    "e": 15,
    "rumbo": 180,
    "ancho": 3,
    "alto": 3,
    "h0": 6
   },
   "torre": {
    "n": -100,
    "e": -30,
    "lado": 2,
    "alto": 25
   }
  }
 },
 "op_inspeccion": {
  "nombre": "Inspección de edificios",
  "vehiculos": [
   "dron"
  ],
  "mundo": "cartagena",
  "zona": 3,
  "dificultad": 2,
  "viento": {
   "vel": 3,
   "desde": 90,
   "rachas": true
  },
  "desc": "El CIFP Politécnico necesita fotos de seis puntos de sus cubiertas y fachadas para el plan de mantenimiento: lucernario, placas solares, extractor, una grieta, un canalón y una antena.",
  "objetivos": [
   [
    "puntos",
    "Fotografiar los 6 puntos de inspección: de 3 a 20 m, bien encuadrados (las cubiertas desde arriba, las fachadas de frente)"
   ],
   [
    "techo",
    "Sin pasar de 120 m de altura sobre el suelo"
   ],
   [
    "vlos",
    "Siempre a la vista: a menos de 500 m del piloto"
   ],
   [
    "zona",
    "Fuera de la zona del aeropuerto de San Javier (8 km)"
   ],
   [
    "casa",
    "Aterrizar a menos de 10 m del punto de despegue"
   ],
   [
    "reserva",
    "Aterrizar con más del 20 % de batería"
   ],
   [
    "aterrizar",
    "Aterrizar sin daños"
   ]
  ],
  "operacion": {
   "avion": "DJI_MINI",
   "cliente": "CIFP Politécnico de Cartagena · departamento de mantenimiento",
   "lugar": "Calle Grecia, 56, Cartagena. Despegue desde el aparcamiento interior.",
   "trabajo": "Inspección visual de cubiertas y fachadas: una foto nítida de cada punto marcado con una placa naranja numerada.",
   "entrega": "6 fotos, una por punto, para el informe de mantenimiento.",
   "salida": {
    "n": 58.3,
    "e": 6651.4,
    "rumbo": 110
   },
   "candidatos": {
    "cubiertas": [
     {
      "n": 109.5,
      "e": 6609.8,
      "cota": 15.45
     },
     {
      "n": 118.5,
      "e": 6630.8,
      "cota": 15.45
     },
     {
      "n": 103.5,
      "e": 6588.8,
      "cota": 15.45
     },
     {
      "n": 103.5,
      "e": 6624.8,
      "cota": 15.45
     },
     {
      "n": 138.6,
      "e": 6617.3,
      "cota": 15.65
     },
     {
      "n": 144.6,
      "e": 6629.3,
      "cota": 15.65
     },
     {
      "n": 214.3,
      "e": 6628.6,
      "cota": 14.15
     },
     {
      "n": 226.3,
      "e": 6619.6,
      "cota": 14.15
     },
     {
      "n": 226.3,
      "e": 6637.6,
      "cota": 14.15
     },
     {
      "n": 111.4,
      "e": 6638.6,
      "cota": 12.55
     },
     {
      "n": 111.6,
      "e": 6653.3,
      "cota": 15.55
     },
     {
      "n": 105.6,
      "e": 6647.3,
      "cota": 15.55
     },
     {
      "n": 193.9,
      "e": 6701.3,
      "cota": 14.55
     },
     {
      "n": 128.7,
      "e": 6699.1,
      "cota": 17.55
     },
     {
      "n": 179.7,
      "e": 6699.1,
      "cota": 17.55
     },
     {
      "n": 86.7,
      "e": 6702.1,
      "cota": 17.55
     },
     {
      "n": 152.7,
      "e": 6699.1,
      "cota": 17.55
     },
     {
      "n": 114.7,
      "e": 6709.2,
      "cota": 14.05
     },
     {
      "n": 135.9,
      "e": 6727.9,
      "cota": 14.25
     },
     {
      "n": 81.9,
      "e": 6718.9,
      "cota": 14.25
     },
     {
      "n": 174.9,
      "e": 6742.9,
      "cota": 14.25
     },
     {
      "n": 162.9,
      "e": 6715.9,
      "cota": 14.25
     }
    ],
    "fachadas": [
     {
      "n": 109.1,
      "e": 6583.2,
      "cota": 12.2,
      "normal": 268
     },
     {
      "n": 215.2,
      "e": 6641.6,
      "cota": 12.25,
      "normal": 88
     },
     {
      "n": 199.8,
      "e": 6628.4,
      "cota": 12.25,
      "normal": 178
     },
     {
      "n": 214.3,
      "e": 6614.1,
      "cota": 12.25,
      "normal": 268
     },
     {
      "n": 123.2,
      "e": 6652.6,
      "cota": 12.3,
      "normal": 358
     },
     {
      "n": 112.0,
      "e": 6664.4,
      "cota": 12.3,
      "normal": 88
     },
     {
      "n": 192.2,
      "e": 6692.7,
      "cota": 12.65,
      "normal": 268
     },
     {
      "n": 196.6,
      "e": 6707.8,
      "cota": 12.65,
      "normal": 34
     },
     {
      "n": 129.8,
      "e": 6695.1,
      "cota": 14.3,
      "normal": 268
     },
     {
      "n": 180.1,
      "e": 6728.2,
      "cota": 12.35,
      "normal": 358
     },
     {
      "n": 150.9,
      "e": 6747.7,
      "cota": 12.35,
      "normal": 88
     }
    ],
    "elegir": [
     4,
     2
    ]
   },
   "puntos": [
    {
     "n": 120,
     "e": 6729,
     "cota": 14.25,
     "nombre": "Lucernario de la nave de talleres"
    },
    {
     "n": 165,
     "e": 6738,
     "cota": 14.25,
     "nombre": "Placas solares de la nave"
    },
    {
     "n": 150,
     "e": 6700,
     "cota": 17.55,
     "nombre": "Extractor de la cubierta"
    },
    {
     "n": 125,
     "e": 6695.0,
     "cota": 14.2,
     "normal": 268,
     "nombre": "Grieta en la fachada oeste"
    },
    {
     "n": 98.3,
     "e": 6610,
     "cota": 14.9,
     "normal": 182,
     "nombre": "Canalón de la fachada sur"
    },
    {
     "n": 215,
     "e": 6628,
     "cota": 14.15,
     "nombre": "Antena del tejado"
    }
   ],
   "dist": [
    3,
    20
   ]
  }
 },
 "op_fotogrametria": {
  "nombre": "Fotogrametría de una parcela",
  "vehiculos": [
   "dron"
  ],
  "mundo": "cartagena",
  "zona": 3,
  "dificultad": 2,
  "viento": {
   "vel": 3,
   "desde": 70,
   "rachas": true
  },
  "desc": "Un estudio de topografía quiere el modelo 3D de una parcela de 160 × 120 m junto al campo del club: pasadas en paralelo a altura fija con la cámara mirando abajo y fotos que se solapen.",
  "objetivos": [
   [
    "cobertura",
    "Cubrir el 90 % de la parcela con solape (cada punto en 2 fotos o más), con la cámara hacia abajo y entre 40 y 60 m"
   ],
   [
    "techo",
    "Sin pasar de 120 m de altura sobre el suelo"
   ],
   [
    "vlos",
    "Siempre a la vista: a menos de 500 m del piloto"
   ],
   [
    "zona",
    "Fuera de la zona del aeropuerto de San Javier (8 km)"
   ],
   [
    "casa",
    "Aterrizar a menos de 10 m del punto de despegue"
   ],
   [
    "reserva",
    "Aterrizar con más del 20 % de batería"
   ],
   [
    "aterrizar",
    "Aterrizar sin daños"
   ]
  ],
  "operacion": {
   "avion": "DJI_MINI",
   "cliente": "Topografía Campo de Cartagena",
   "lugar": "El Jimenado (Torre-Pacheco). Despegue desde la pista del club Los Halcones de la Rambla.",
   "trabajo": "Vuelo fotogramétrico: pasadas paralelas a 40–60 m con el gimbal a −89° (mirando abajo) y una foto cada 20–25 m. La parcela está marcada con jalones rojos y blancos en las esquinas.",
   "entrega": "Fotos con solape para el modelo 3D y la ortofoto de la parcela.",
   "salida": {
    "n": 16476.3,
    "e": 3322.1,
    "rumbo": 250
   },
   "parcela": {
    "n0": 16560,
    "n1": 16680,
    "e0": 3000,
    "e1": 3160
   },
   "altura": [
    40,
    60
   ],
   "gimbal": -85,
   "solape": 2,
   "cubrir": 0.9
  }
 },
 "op_busqueda": {
  "nombre": "Búsqueda y rescate",
  "vehiculos": [
   "dron"
  ],
  "mundo": "cartagena",
  "zona": 3,
  "dificultad": 3,
  "viento": {
   "vel": 4,
   "desde": 300,
   "rachas": true
  },
  "desc": "Un senderista se ha perdido en el monte al sur de Fuente Álamo. Búscalo dentro de la zona marcada con jalones amarillos, hazle una foto centrada y envía su posición a los equipos de tierra. Tienes 8 minutos.",
  "objetivos": [
   [
    "localizar",
    "Encontrar al senderista y hacerle una foto con él en el centro, a menos de 60 m"
   ],
   [
    "posicion",
    "Enviar su posición con menos de 10 m de error"
   ],
   [
    "tiempo",
    "En menos de 8 minutos desde el despegue"
   ],
   [
    "techo",
    "Sin pasar de 120 m de altura sobre el suelo"
   ],
   [
    "vlos",
    "Siempre a la vista: a menos de 500 m del piloto"
   ],
   [
    "zona",
    "Fuera de la zona del aeropuerto de San Javier (8 km)"
   ],
   [
    "casa",
    "Aterrizar a menos de 10 m del punto de despegue"
   ],
   [
    "reserva",
    "Aterrizar con más del 20 % de batería"
   ],
   [
    "aterrizar",
    "Aterrizar sin daños"
   ]
  ],
  "operacion": {
   "avion": "DJI_MINI",
   "cliente": "Emergencias 112 Región de Murcia",
   "lugar": "Monte al sur de Fuente Álamo. Despegue desde el camino de tierra.",
   "trabajo": "Búsqueda de una persona: chaqueta roja y mochila naranja. Barre la zona con la cámara inclinada y, al verla, hazle una foto con ella en el centro de la imagen: la posición se calcula con el centro de la foto.",
   "entrega": "Foto de la persona y su posición.",
   "salida": {
    "n": 3368,
    "e": -12850,
    "rumbo": 180
   },
   "zona": {
    "n0": 3020,
    "n1": 3330,
    "e0": -13150,
    "e1": -12650
   },
   "limite_s": 480,
   "dist": 60
  }
 },
 "op_agricultura": {
  "nombre": "Agricultura: plaga en el cultivo",
  "vehiculos": [
   "dron"
  ],
  "mundo": "cartagena",
  "zona": 3,
  "dificultad": 2,
  "viento": {
   "vel": 3,
   "desde": 70,
   "rachas": true
  },
  "desc": "El agricultor ha visto rodales amarillos en su campo de brócoli. Encuentra las 5 manchas y fotografía cada una desde arriba, de 10 a 30 m, sin bajar de 5 m sobre el cultivo.",
  "objetivos": [
   [
    "manchas",
    "Fotografiar las 5 manchas: de 10 a 30 m de altura y con la cámara hacia abajo (−60° o más)"
   ],
   [
    "baja",
    "Nunca a menos de 5 m sobre el cultivo"
   ],
   [
    "techo",
    "Sin pasar de 120 m de altura sobre el suelo"
   ],
   [
    "vlos",
    "Siempre a la vista: a menos de 500 m del piloto"
   ],
   [
    "zona",
    "Fuera de la zona del aeropuerto de San Javier (8 km)"
   ],
   [
    "casa",
    "Aterrizar a menos de 10 m del punto de despegue"
   ],
   [
    "reserva",
    "Aterrizar con más del 20 % de batería"
   ],
   [
    "aterrizar",
    "Aterrizar sin daños"
   ]
  ],
  "operacion": {
   "avion": "DJI_MINI",
   "cliente": "Explotación agrícola de El Jimenado",
   "lugar": "El bancal de brócoli entero (unas 5 ha) al sur de la pista de Los Halcones de la Rambla; los jalones verdes marcan sus esquinas.",
   "trabajo": "Localizar los rodales con plaga (manchas amarillas en el cultivo) y fotografiarlos para el técnico: una foto vertical de cada uno.",
   "entrega": "5 fotos verticales, una por mancha.",
   "salida": {
    "n": 16476.3,
    "e": 3322.1,
    "rumbo": 160
   },
   "parcela": {
    "n0": 16195,
    "n1": 16449,
    "e0": 3182,
    "e1": 3527,
    "poligono": [[16349, 3182], [16449, 3454], [16273, 3527], [16195, 3386], [16263, 3352], [16251, 3300], [16300, 3281], [16277, 3204]]
   },
   "manchas": [
    [
     16400,
     3330,
     4
    ],
    [
     16330,
     3450,
     5
    ],
    [
     16300,
     3240,
     3.5
    ],
    [
     16250,
     3420,
     4
    ],
    [
     16360,
     3380,
     4.5
    ]
   ],
   "altura": [
    10,
    30
   ],
   "gimbal": -60,
   "minima": 5
  }
 },
 "op_paneles": {
  "nombre": "Inspección de paneles fotovoltaicos",
  "vehiculos": [
   "dron"
  ],
  "mundo": "cartagena",
  "zona": 3,
  "dificultad": 3,
  "viento": {
   "vel": 4,
   "desde": 300,
   "rachas": true
  },
  "desc": "La planta fotovoltaica de La Aljorra, junto a la fábrica de SABIC (83 filas de seguidores solares de 320 m, unos 24.000 módulos), produce menos de lo que debería. Con el dron de inspección recorre las filas y fotografía desde arriba, sin bajar a menos de 3 m de los paneles, tres averías: cristales rotos (solo se ven con la cámara normal), excrementos de aves (se ven con la normal, y en la térmica salen como un punto caliente) y diodos de bypass averiados (a simple vista no se nota nada; en la térmica, una franja caliente de un tercio del módulo). Son 6 módulos con el cristal roto o con excrementos y 3 con el diodo averiado.",
  "objetivos": [
   [
    "defectos",
    "Fotografiar los 6 módulos dañados a simple vista (cristal roto, con la cámara normal; excrementos de aves, con la normal o la térmica): de 4 a 20 m (más lejos con zoom), con la cámara hacia abajo (−45° o más)"
   ],
   [
    "calientes",
    "Encontrar con la cámara térmica los 3 módulos con un diodo de bypass averiado (franja caliente de un tercio del módulo) y fotografiarlos igual: de 4 a 20 m (más lejos con zoom), hacia abajo"
   ],
   [
    "baja",
    "Nunca a menos de 3 m sobre los paneles"
   ],
   [
    "techo",
    "Sin pasar de 120 m de altura sobre el suelo"
   ],
   [
    "vlos",
    "Siempre a la vista: a menos de 500 m del piloto"
   ],
   [
    "zona",
    "Fuera de la zona del aeropuerto de San Javier (8 km)"
   ],
   [
    "casa",
    "Aterrizar a menos de 10 m del punto de despegue"
   ],
   [
    "reserva",
    "Aterrizar con más del 20 % de batería"
   ],
   [
    "aterrizar",
    "Aterrizar sin daños"
   ]
  ],
  "operacion": {
   "avion": "HQ3T",
   "cliente": "Planta fotovoltaica de La Aljorra · mantenimiento",
   "lugar": "La Aljorra (Cartagena), junto a la fábrica de SABIC. Despegue desde el camino al norte del bloque de paneles.",
   "trabajo": "Inspección de los módulos fila por fila con la cámara hacia abajo. Con la cámara normal, los cristales rotos (grietas blancas) y los excrementos de aves (manchas blancas). Con la cámara térmica (C), los diodos de bypass averiados: una franja naranja de un tercio del módulo sobre el morado de los paneles; los excrementos salen como un punto caliente amarillo y el cristal roto apenas se distingue. Con el zoom (Z / X) se puede volar más alto y ver más filas.",
   "entrega": "9 fotos: una por módulo con el cristal roto o con excrementos (6) y una por diodo de bypass averiado (3, cámara térmica), para cambiarlos o limpiarlos.",
   "salida": {
    "n": 9539.4,
    "e": -5195.7,
    "rumbo": 180
   },
   "planta": {
    "n0": 9527.38,
    "e0": -5419.44,
    "rumbo": 181.157,
    "filas": 83,
    "largo": 323,
    "ancho": 2.2,
    "separacion": 5.5109,
    "inclinacion": 15,
    "h0": 1.0,
    "tramo": 30
   },
   "defectos": [
    [
     3,
     23
    ],
    [
     11,
     118
    ],
    [
     19,
     61
    ],
    [
     28,
     140
    ],
    [
     37,
     9
    ],
    [
     46,
     287
    ]
   ],
   "dist": [
    4,
    20
   ],
   "gimbal": -45,
   "minima": 3,
   "sin_arboles": [
    [
     9530.5,
     -5423.4
    ],
    [
     9201.5,
     -5430.0
    ],
    [
     9192.2,
     -4970.2
    ],
    [
     9521.2,
     -4963.6
    ]
   ],
   "calientes": 3
  }
 },
 "op_video": {
  "nombre": "Grabación de vídeo",
  "vehiculos": [
   "dron"
  ],
  "mundo": "cartagena",
  "zona": 3,
  "dificultad": 3,
  "viento": {
   "vel": 5,
   "desde": 60,
   "rachas": true
  },
  "desc": "Una productora quiere un plano en órbita del faro de Cabo de Palos para un anuncio: una vuelta completa grabando, a 30–70 m, con el faro siempre centrado, a altura constante y sin tirones.",
  "objetivos": [
   [
    "orbita",
    "Una órbita completa grabando: a 30–70 m del faro, con el faro centrado (±15°) y a altura constante (±5 m)"
   ],
   [
    "suave",
    "Plano estable: girar a menos de 60°/s mientras se graba"
   ],
   [
    "techo",
    "Sin pasar de 120 m de altura sobre el suelo"
   ],
   [
    "vlos",
    "Siempre a la vista: a menos de 500 m del piloto"
   ],
   [
    "zona",
    "Fuera de la zona del aeropuerto de San Javier (8 km)"
   ],
   [
    "casa",
    "Aterrizar a menos de 10 m del punto de despegue"
   ],
   [
    "reserva",
    "Aterrizar con más del 20 % de batería"
   ],
   [
    "aterrizar",
    "Aterrizar sin daños"
   ]
  ],
  "operacion": {
   "avion": "DJI_MINI",
   "cliente": "Productora audiovisual",
   "lugar": "Faro de Cabo de Palos (Cartagena). Despegue desde la explanada del faro.",
   "trabajo": "Órbita alrededor del faro: palanca derecha de lado y guiñada a la vez, para dar la vuelta mirándolo siempre. Graba con el botón de vídeo (V).",
   "entrega": "Un vídeo de una órbita completa, estable y centrada.",
   "salida": {
    "n": 2392,
    "e": 31720,
    "rumbo": 0
   },
   "faro": {
    "n": 2424.0,
    "e": 31713.7,
    "radio": 3.5,
    "alto": 51
   },
   "orbita": [
    30,
    70
   ],
   "centrado": 15,
   "variacion": 5,
   "giro_max": 60
  }
 },
 "op_sabic": {
  "nombre": "Inspección de la fábrica de SABIC",
  "vehiculos": [
   "dron"
  ],
  "mundo": "cartagena",
  "zona": 3,
  "dificultad": 3,
  "viento": {
   "vel": 6,
   "desde": 290,
   "rachas": true
  },
  "desc": "Trabajo largo (30 minutos) para pilotos con soltura: tres tareas de mantenimiento en la fábrica de SABIC de La Aljorra con el dron de inspección (zoom y cámara térmica). Prepara antes la estrategia: el orden de las tareas, la altura y por dónde vas a volar entre las unidades de proceso. Las pistas están en el GPS: los racks donde están los puntos calientes, la unidad con la alarma de gas y la antorcha.",
  "objetivos": [
   [
    "calientes",
    "Encontrar con la térmica los 4 puntos calientes de los racks: medidor puntual sobre cada uno 3 s, a menos de 15 m (o con zoom)"
   ],
   [
    "fuga",
    "Localizar la fuga de gas de la unidad con alarma y medir su temperatura con la térmica"
   ],
   [
    "atex",
    "No entrar en la zona ATEX: 30 m alrededor de la unidad con la fuga"
   ],
   [
    "placa",
    "Leer con el zoom (28x o más) la placa de la boca de la antorcha: foto desde más de 60 m de altura y a más de 50 m de ella"
   ],
   [
    "piloto",
    "Foto con la térmica del piloto de la antorcha (¿encendido o apagado?)"
   ],
   [
    "unidades",
    "Nunca a menos de 10 m por encima de las unidades de proceso"
   ],
   [
    "tiempo",
    "Las tres tareas en 30 minutos"
   ],
   [
    "techo",
    "Sin pasar de 120 m de altura sobre el suelo"
   ],
   [
    "vlos",
    "Siempre a la vista: a menos de 500 m del piloto"
   ],
   [
    "zona",
    "Fuera de la zona del aeropuerto de San Javier (8 km)"
   ],
   [
    "casa",
    "Aterrizar a menos de 10 m del punto de despegue"
   ],
   [
    "reserva",
    "Aterrizar con más del 20 % de batería"
   ],
   [
    "aterrizar",
    "Aterrizar sin daños"
   ]
  ],
  "operacion": {
   "avion": "HQ3T",
   "cliente": "Fábrica de policarbonato de La Aljorra · mantenimiento y seguridad",
   "lugar": "Fábrica de SABIC, La Aljorra (Cartagena). Despegue en el descampado entre las unidades de policarbonato y el rack principal.",
   "trabajo": "Tres tareas con el dron de inspección: 1) puntos calientes en los racks de tuberías (aislamiento roto: solo se ven con la térmica; las tuberías amarillas de vapor también están calientes y no son averías); 2) fuga de gas en la unidad con alarma: con la térmica el gas sale frío, y no se puede entrar en la zona ATEX de 30 m; 3) la antorcha: leer con el zoom la placa de su boca y comprobar con la térmica si su piloto está encendido. Pistas en el GPS: en naranja los racks con puntos calientes, en rojo la unidad con la alarma y su zona ATEX, y la antorcha.",
   "entrega": "La posición y temperatura de cada punto caliente y de la fuga, la foto de la placa y la foto térmica del piloto.",
   "salida": {
    "n": 10342.0,
    "e": -4490.8,
    "rumbo": 46
   },
   "racks": [
    {
     "e0": -4487.5,
     "n0": 10449.5,
     "e1": -4586.1,
     "n1": 10354.3,
     "alto": 7,
     "ancho": 5,
     "niveles": 2,
     "nombre": "R-1"
    },
    {
     "e0": -4455.1,
     "n0": 10319.5,
     "e1": -4386.4,
     "n1": 10248.3,
     "alto": 6,
     "ancho": 4,
     "niveles": 2,
     "nombre": "R-2"
    },
    {
     "e0": -4364.4,
     "n0": 10412.7,
     "e1": -4434.2,
     "n1": 10345.3,
     "alto": 7,
     "ancho": 5,
     "niveles": 2,
     "nombre": "R-3"
    },
    {
     "e0": -4543.7,
     "n0": 10513.4,
     "e1": -4409.6,
     "n1": 10374.6,
     "alto": 8,
     "ancho": 6,
     "niveles": 3,
     "nombre": "R-4"
    },
    {
     "e0": -4614.0,
     "n0": 10412.1,
     "e1": -4574.5,
     "n1": 10371.1,
     "alto": 6,
     "ancho": 4,
     "niveles": 2,
     "nombre": "R-5"
    },
    {
     "e0": -4487.3,
     "n0": 10540.0,
     "e1": -4631.2,
     "n1": 10401.1,
     "alto": 7,
     "ancho": 5,
     "niveles": 2,
     "nombre": "R-6"
    },
    {
     "e0": -4424.6,
     "n0": 10568.6,
     "e1": -4327.4,
     "n1": 10467.9,
     "alto": 7,
     "ancho": 5,
     "niveles": 2,
     "nombre": "R-7"
    },
    {
     "e0": -4369.7,
     "n0": 10189.3,
     "e1": -4319.0,
     "n1": 10136.8,
     "alto": 6,
     "ancho": 4,
     "niveles": 2,
     "nombre": "R-8"
    },
    {
     "e0": -4366.0,
     "n0": 10198.4,
     "e1": -4569.4,
     "n1": 10013.1,
     "alto": 9,
     "ancho": 7,
     "niveles": 3,
     "nombre": "R-9"
    },
    {
     "e0": -4232.5,
     "n0": 10553.9,
     "e1": -4342.6,
     "n1": 10447.7,
     "alto": 7,
     "ancho": 5,
     "niveles": 2,
     "nombre": "R-10"
    },
    {
     "e0": -4290.2,
     "n0": 10492.7,
     "e1": -4223.5,
     "n1": 10423.7,
     "alto": 6,
     "ancho": 4,
     "niveles": 2,
     "nombre": "R-11"
    },
    {
     "e0": -4077.7,
     "n0": 10468.5,
     "e1": -4366.0,
     "n1": 10198.4,
     "alto": 9,
     "ancho": 7,
     "niveles": 3,
     "nombre": "R-12"
    },
    {
     "e0": -4274.2,
     "n0": 10597.1,
     "e1": -4363.4,
     "n1": 10511.0,
     "alto": 6,
     "ancho": 4,
     "niveles": 2,
     "nombre": "R-13"
    },
    {
     "e0": -4335.3,
     "n0": 10660.4,
     "e1": -4457.6,
     "n1": 10542.3,
     "alto": 7,
     "ancho": 5,
     "niveles": 2,
     "nombre": "R-14"
    },
    {
     "e0": -4524.9,
     "n0": 10049.1,
     "e1": -4462.4,
     "n1": 9984.4,
     "alto": 6,
     "ancho": 4,
     "niveles": 2,
     "nombre": "R-15"
    },
    {
     "e0": -4272.1,
     "n0": 10593.5,
     "e1": -4236.0,
     "n1": 10556.1,
     "alto": 6,
     "ancho": 4,
     "niveles": 2,
     "nombre": "R-16"
    },
    {
     "e0": -4210.9,
     "n0": 10334.3,
     "e1": -4101.8,
     "n1": 10221.4,
     "alto": 7,
     "ancho": 5,
     "niveles": 2,
     "nombre": "R-17"
    },
    {
     "e0": -4569.4,
     "n0": 10013.1,
     "e1": -4515.2,
     "n1": 9957.0,
     "alto": 8,
     "ancho": 6,
     "niveles": 3,
     "nombre": "R-18"
    },
    {
     "e0": -4135.1,
     "n0": 10463.1,
     "e1": -4061.0,
     "n1": 10534.7,
     "alto": 6,
     "ancho": 4,
     "niveles": 2,
     "nombre": "R-19"
    }
   ],
   "calientes": 4,
   "unidades": [
    {
     "poligono": [
      [
       10390.2,
       -4574.8
      ],
      [
       10452.7,
       -4510.1
      ],
      [
       10412.4,
       -4471.2
      ],
      [
       10349.9,
       -4535.9
      ]
     ],
     "alto": 39.3,
     "valvulas": [
      [
       -4525.9,
       10399.9,
       9.2,
       10,
       8,
       46.0
      ],
      [
       -4513.2,
       10395.5,
       7.1,
       14,
       8,
       46.0
      ],
      [
       -4530.3,
       10387.3,
       7.2,
       8,
       6,
       46.0
      ],
      [
       -4538.7,
       10391.7,
       8.6,
       6,
       6,
       46.0
      ]
     ],
     "nombre": "U-1"
    },
    {
     "poligono": [
      [
       10317.1,
       -4401.4
      ],
      [
       10354.0,
       -4363.3
      ],
      [
       10310.8,
       -4321.6
      ],
      [
       10274.0,
       -4359.7
      ]
     ],
     "alto": 34.9,
     "valvulas": [
      [
       -4365.5,
       10310.1,
       7.6,
       8,
       7,
       46.0
      ],
      [
       -4348.3,
       10322.6,
       8.0,
       12,
       8,
       46.0
      ],
      [
       -4375.9,
       10320.9,
       7.4,
       6,
       7,
       46.0
      ],
      [
       -4365.7,
       10297.4,
       5.0,
       6,
       8,
       46.0
      ]
     ],
     "nombre": "U-2"
    },
    {
     "poligono": [
      [
       10441.2,
       -4618.5
      ],
      [
       10500.9,
       -4556.6
      ],
      [
       10489.4,
       -4545.5
      ],
      [
       10429.6,
       -4607.4
      ]
     ],
     "alto": 26.2,
     "valvulas": [
      [
       -4584.2,
       10461.8,
       4.1,
       14,
       7,
       46.0
      ],
      [
       -4590.7,
       10451.3,
       5.8,
       6,
       7,
       46.0
      ],
      [
       -4566.8,
       10486.9,
       4.4,
       10,
       6,
       46.0
      ],
      [
       -4599.4,
       10442.9,
       7.7,
       10,
       7,
       46.0
      ]
     ],
     "nombre": "U-3"
    },
    {
     "poligono": [
      [
       10531.5,
       -4525.0
      ],
      [
       10554.4,
       -4501.2
      ],
      [
       10518.4,
       -4466.5
      ],
      [
       10495.5,
       -4490.2
      ]
     ],
     "alto": 30.9,
     "valvulas": [
      [
       -4491.1,
       10526.6,
       6.8,
       8,
       7,
       46.0
      ],
      [
       -4499.7,
       10518.3,
       7.4,
       6,
       7,
       46.0
      ],
      [
       -4505.9,
       10533.2,
       4.4,
       8,
       7,
       46.0
      ],
      [
       -4484.6,
       10532.9,
       8.0,
       6,
       6,
       46.0
      ]
     ],
     "nombre": "U-4"
    },
    {
     "poligono": [
      [
       10303.8,
       -4328.8
      ],
      [
       10338.6,
       -4292.8
      ],
      [
       10306.2,
       -4261.6
      ],
      [
       10271.5,
       -4297.6
      ]
     ],
     "alto": 30.4,
     "valvulas": [
      [
       -4301.2,
       10305.5,
       6.6,
       12,
       6,
       46.0
      ],
      [
       -4297.2,
       10292.7,
       6.4,
       12,
       10,
       46.0
      ],
      [
       -4307.5,
       10312.0,
       8.4,
       14,
       8,
       46.0
      ],
      [
       -4282.4,
       10290.3,
       4.3,
       10,
       6,
       46.0
      ]
     ],
     "nombre": "U-5"
    },
    {
     "poligono": [
      [
       10236.4,
       -4315.1
      ],
      [
       10262.1,
       -4288.5
      ],
      [
       10226.9,
       -4254.5
      ],
      [
       10201.2,
       -4281.1
      ]
     ],
     "alto": 25.5,
     "valvulas": [
      [
       -4281.2,
       10235.8,
       9.0,
       8,
       7,
       46.0
      ],
      [
       -4277.1,
       10227.3,
       8.3,
       8,
       6,
       46.0
      ],
      [
       -4287.5,
       10242.3,
       6.4,
       8,
       7,
       46.0
      ],
      [
       -4290.0,
       10219.0,
       9.1,
       12,
       10,
       46.0
      ]
     ],
     "nombre": "U-6"
    },
    {
     "poligono": [
      [
       10106.0,
       -4461.7
      ],
      [
       10163.7,
       -4402.0
      ],
      [
       10129.9,
       -4369.3
      ],
      [
       10072.2,
       -4429.0
      ]
     ],
     "alto": 39.2,
     "valvulas": [
      [
       -4419.0,
       10118.0,
       9.2,
       8,
       7,
       46.0
      ],
      [
       -4408.5,
       10115.7,
       7.7,
       8,
       6,
       46.0
      ],
      [
       -4410.4,
       10126.3,
       8.6,
       8,
       7,
       46.0
      ],
      [
       -4425.2,
       10128.7,
       6.7,
       10,
       10,
       46.0
      ]
     ],
     "nombre": "U-7"
    },
    {
     "poligono": [
      [
       10075.5,
       -4493.3
      ],
      [
       10096.3,
       -4471.8
      ],
      [
       10079.8,
       -4455.8
      ],
      [
       10058.9,
       -4477.4
      ]
     ],
     "alto": 31.9,
     "valvulas": [
      [
       -4480.6,
       10075.2,
       7.0,
       12,
       8,
       46.0
      ],
      [
       -4465.7,
       10077.1,
       7.5,
       14,
       6,
       46.0
      ],
      [
       -4471.9,
       10087.8,
       8.5,
       10,
       7,
       46.0
      ]
     ],
     "nombre": "U-8"
    },
    {
     "poligono": [
      [
       10420.8,
       -4261.0
      ],
      [
       10457.6,
       -4222.9
      ],
      [
       10431.0,
       -4197.2
      ],
      [
       10394.2,
       -4235.3
      ]
     ],
     "alto": 22.7,
     "valvulas": [
      [
       -4229.2,
       10418.1,
       9.0,
       6,
       7,
       46.0
      ],
      [
       -4220.5,
       10430.7,
       8.8,
       8,
       7,
       46.0
      ],
      [
       -4239.6,
       10428.9,
       7.6,
       6,
       8,
       46.0
      ],
      [
       -4216.5,
       10417.9,
       6.6,
       8,
       7,
       46.0
      ]
     ],
     "nombre": "U-9"
    },
    {
     "poligono": [
      [
       10389.3,
       -4240.3
      ],
      [
       10435.8,
       -4192.1
      ],
      [
       10402.0,
       -4159.5
      ],
      [
       10355.5,
       -4207.7
      ]
     ],
     "alto": 38.4,
     "valvulas": [
      [
       -4202.1,
       10392.9,
       8.2,
       12,
       8,
       46.0
      ],
      [
       -4195.8,
       10386.4,
       5.8,
       8,
       6,
       46.0
      ],
      [
       -4206.1,
       10405.7,
       8.9,
       6,
       10,
       46.0
      ],
      [
       -4212.6,
       10399.4,
       7.1,
       6,
       10,
       46.0
      ]
     ],
     "nombre": "U-10"
    },
    {
     "poligono": [
      [
       10616.7,
       -4422.4
      ],
      [
       10681.3,
       -4355.5
      ],
      [
       10627.3,
       -4303.4
      ],
      [
       10562.7,
       -4370.3
      ]
     ],
     "alto": 40.6,
     "valvulas": [
      [
       -4354.3,
       10628.2,
       7.8,
       14,
       7,
       46.0
      ],
      [
       -4371.5,
       10615.8,
       4.5,
       6,
       8,
       46.0
      ],
      [
       -4348.0,
       10621.7,
       8.7,
       12,
       6,
       46.0
      ],
      [
       -4373.2,
       10634.9,
       4.4,
       6,
       10,
       46.0
      ]
     ],
     "nombre": "U-11"
    },
    {
     "poligono": [
      [
       10351.0,
       -4193.6
      ],
      [
       10399.6,
       -4143.3
      ],
      [
       10370.8,
       -4115.5
      ],
      [
       10322.2,
       -4165.8
      ]
     ],
     "alto": 34.5,
     "valvulas": [
      [
       -4155.3,
       10358.8,
       7.9,
       14,
       10,
       46.0
      ],
      [
       -4159.3,
       10371.6,
       7.0,
       12,
       6,
       46.0
      ],
      [
       -4151.3,
       10346.0,
       4.7,
       14,
       6,
       46.0
      ],
      [
       -4170.0,
       10365.4,
       8.5,
       6,
       6,
       46.0
      ]
     ],
     "nombre": "U-12"
    },
    {
     "poligono": [
      [
       10447.6,
       -4179.9
      ],
      [
       10477.5,
       -4149.0
      ],
      [
       10443.7,
       -4116.3
      ],
      [
       10413.8,
       -4147.3
      ]
     ],
     "alto": 39.0,
     "valvulas": [
      [
       -4150.2,
       10447.1,
       6.0,
       10,
       6,
       46.0
      ],
      [
       -4148.3,
       10436.5,
       6.5,
       6,
       8,
       46.0
      ],
      [
       -4154.3,
       10455.7,
       8.4,
       8,
       7,
       46.0
      ],
      [
       -4137.3,
       10455.4,
       7.7,
       8,
       6,
       46.0
      ]
     ],
     "nombre": "U-13"
    },
    {
     "poligono": [
      [
       10477.5,
       -4149.0
      ],
      [
       10505.3,
       -4120.2
      ],
      [
       10469.3,
       -4085.5
      ],
      [
       10441.5,
       -4114.2
      ]
     ],
     "alto": 27.2,
     "valvulas": [
      [
       -4119.4,
       10468.5,
       7.4,
       6,
       8,
       46.0
      ],
      [
       -4110.9,
       10472.6,
       8.8,
       6,
       8,
       46.0
      ],
      [
       -4129.8,
       10479.3,
       7.6,
       10,
       10,
       46.0
      ],
      [
       -4117.5,
       10457.9,
       7.7,
       12,
       6,
       46.0
      ]
     ],
     "nombre": "U-14"
    },
    {
     "poligono": [
      [
       10399.6,
       -4143.3
      ],
      [
       10434.4,
       -4107.3
      ],
      [
       10376.8,
       -4051.7
      ],
      [
       10342.1,
       -4087.7
      ]
     ],
     "alto": 35.5,
     "valvulas": [
      [
       -4098.8,
       10392.5,
       6.4,
       6,
       8,
       46.0
      ],
      [
       -4105.3,
       10386.2,
       6.9,
       8,
       10,
       46.0
      ],
      [
       -4086.2,
       10388.0,
       5.3,
       6,
       7,
       46.0
      ],
      [
       -4094.9,
       10375.4,
       6.3,
       14,
       6,
       46.0
      ]
     ],
     "nombre": "U-15"
    },
    {
     "poligono": [
      [
       9948.9,
       -4574.0
      ],
      [
       9971.8,
       -4550.3
      ],
      [
       9950.2,
       -4529.5
      ],
      [
       9927.3,
       -4553.2
      ]
     ],
     "alto": 26.2,
     "valvulas": [
      [
       -4540.1,
       9948.3,
       8.2,
       14,
       8,
       46.0
      ]
     ],
     "nombre": "U-16"
    },
    {
     "poligono": [
      [
       9916.0,
       -4514.5
      ],
      [
       9952.8,
       -4476.4
      ],
      [
       9926.2,
       -4450.7
      ],
      [
       9889.4,
       -4488.8
      ]
     ],
     "alto": 26.0,
     "valvulas": [
      [
       -4482.8,
       9909.1,
       6.4,
       10,
       6,
       46.0
      ],
      [
       -4495.5,
       9913.5,
       7.2,
       10,
       10,
       46.0
      ],
      [
       -4484.4,
       9936.7,
       4.7,
       6,
       10,
       46.0
      ],
      [
       -4467.5,
       9932.2,
       6.0,
       8,
       8,
       46.0
      ]
     ],
     "nombre": "U-17"
    }
   ],
   "antorcha": {
    "n": 10472.2,
    "e": -4574.8,
    "alto": 62,
    "radio": 1.8
   },
   "chimeneas": [
    {
     "n": 10404.7,
     "e": -4516.6,
     "alto": 55,
     "radio": 1.6
    },
    {
     "n": 9728.3,
     "e": -4662.8,
     "alto": 46,
     "radio": 1.5
    },
    {
     "n": 9869.2,
     "e": -4548.6,
     "alto": 38,
     "radio": 1.3
    }
   ],
   "atex": 30,
   "sobre_unidades": 10,
   "dist_caliente": 15,
   "dist_fuga": 45,
   "medir_s": 3,
   "placa": {
    "altura": 60,
    "distancia": 50,
    "zoom": 28
   },
   "limite_s": 1800,
   "sin_arboles": [
    [
     10317.0,
     -4515.8
    ],
    [
     10317.0,
     -4465.8
    ],
    [
     10367.0,
     -4465.8
    ],
    [
     10367.0,
     -4515.8
    ]
   ]
  }
 },
 "op_patrulla": {
  "nombre": "Patrulla del Mar Menor: vertidos",
  "vehiculos": [
   "uav"
  ],
  "mundo": "cartagena",
  "zona": 3,
  "dificultad": 3,
  "viento": {
   "vel": 5,
   "desde": 60,
   "rachas": true
  },
  "desc": "Un pesquero ha avisado de tres manchas de hidrocarburo en el Mar Menor. Con el UAV de vigilancia Cernícalo XM-7, despega de la pista 05R de la base aérea de San Javier, patrulla los tres sectores del aviso, encuentra cada vertido con la torreta EO/IR (zoom y cámara térmica), fotografíalo con la cruz sobre la mancha para enviar su posición a Salvamento Marítimo y vuelve a aterrizar en la pista.",
  "objetivos": [
   [
    "vertidos",
    "Localizar los 3 vertidos y fotografiarlos con la cruz de la torreta sobre la mancha (su posición se envía con la foto)"
   ],
   [
    "despegue",
    "Despegar de la pista 05R de San Javier"
   ],
   [
    "a_mano",
    "Despegar y aterrizar a mano (sin el despegue ni el aterrizaje automáticos)"
   ],
   [
    "altura",
    "Patrullar a 150 m o más sobre el agua (salvo a menos de 5 km de la pista)"
   ],
   [
    "techo",
    "Sin pasar de 900 m sobre el suelo"
   ],
   [
    "tiempo",
    "Los tres vertidos en 40 minutos desde el despegue"
   ],
   [
    "pista",
    "Aterrizar en la pista de San Javier y pararse en ella"
   ],
   [
    "aterrizar",
    "Aterrizar sin daños"
   ]
  ],
  "operacion": {
   "avion": "XM7",
   "cliente": "Capitanía Marítima de Cartagena · Salvamento Marítimo",
   "lugar": "Base aérea de San Javier (Murcia), pista 05R/23L de 2.311 m. Patrulla sobre el Mar Menor.",
   "trabajo": "Despegue de la 05R, vuelo a los sectores del aviso (círculos naranjas en el mapa) y búsqueda de las manchas con la torreta: en la cámara normal son manchas oscuras con brillos de colores; en la térmica, el hidrocarburo calentado por el sol sale más caliente que el agua. Con el piloto automático en «ir a punto» (clic en el mapa) el avión da vueltas sobre el sector y las flechas mueven la torreta; K la fija sobre un punto. Foto (F) con la cruz sobre la mancha, a una distancia razonable para su zoom.",
   "entrega": "Una foto de cada vertido con su posición, para enviar las embarcaciones de limpieza.",
   "salida": {
    "n": 17163.3,
    "e": 20176.3,
    "rumbo": 45.86
   },
   "pista": {
    "nombre": "San Javier 05R/23L",
    "n": 17121.5,
    "e": 20133.2,
    "rumbo": 45.86,
    "largo": 2311,
    "ancho": 45
   },
   "candidatos_vertido": [
    [
     2850.0,
     27450.0
    ],
    [
     3900.0,
     25950.0
    ],
    [
     3900.0,
     28050.0
    ],
    [
     4500.0,
     27000.0
    ],
    [
     4800.0,
     24300.0
    ],
    [
     5100.0,
     23100.0
    ],
    [
     5100.0,
     25650.0
    ],
    [
     5700.0,
     22050.0
    ],
    [
     6000.0,
     24000.0
    ],
    [
     6300.0,
     25200.0
    ],
    [
     6600.0,
     21150.0
    ],
    [
     6600.0,
     22950.0
    ],
    [
     6600.0,
     26400.0
    ],
    [
     7200.0,
     24000.0
    ],
    [
     7500.0,
     22050.0
    ],
    [
     7500.0,
     25200.0
    ],
    [
     7650.0,
     20400.0
    ],
    [
     7800.0,
     26400.0
    ],
    [
     8100.0,
     23100.0
    ],
    [
     8550.0,
     21300.0
    ],
    [
     8700.0,
     19650.0
    ],
    [
     9300.0,
     22950.0
    ],
    [
     9600.0,
     20550.0
    ],
    [
     9750.0,
     19050.0
    ],
    [
     9750.0,
     25650.0
    ],
    [
     10500.0,
     22650.0
    ],
    [
     10650.0,
     19950.0
    ],
    [
     10650.0,
     21150.0
    ],
    [
     10650.0,
     24600.0
    ],
    [
     10800.0,
     18150.0
    ],
    [
     10800.0,
     26250.0
    ],
    [
     11550.0,
     22050.0
    ],
    [
     11700.0,
     19050.0
    ],
    [
     11700.0,
     20550.0
    ],
    [
     11700.0,
     23250.0
    ],
    [
     11700.0,
     25200.0
    ],
    [
     12000.0,
     17850.0
    ],
    [
     12000.0,
     26400.0
    ],
    [
     12600.0,
     21450.0
    ],
    [
     12600.0,
     24150.0
    ],
    [
     12750.0,
     19650.0
    ],
    [
     12750.0,
     22650.0
    ],
    [
     12900.0,
     25350.0
    ],
    [
     13050.0,
     18450.0
    ],
    [
     13200.0,
     26550.0
    ],
    [
     13650.0,
     20550.0
    ],
    [
     13650.0,
     23550.0
    ],
    [
     13800.0,
     21750.0
    ],
    [
     13950.0,
     19350.0
    ],
    [
     13950.0,
     24750.0
    ],
    [
     14250.0,
     25950.0
    ],
    [
     14700.0,
     22650.0
    ],
    [
     14850.0,
     20250.0
    ],
    [
     14850.0,
     23850.0
    ],
    [
     15000.0,
     21450.0
    ],
    [
     15150.0,
     25050.0
    ],
    [
     15900.0,
     22350.0
    ],
    [
     16050.0,
     20700.0
    ],
    [
     16050.0,
     23550.0
    ],
    [
     16050.0,
     25950.0
    ],
    [
     16350.0,
     24750.0
    ],
    [
     16950.0,
     21600.0
    ],
    [
     17100.0,
     22800.0
    ],
    [
     17400.0,
     24000.0
    ],
    [
     18000.0,
     25200.0
    ],
    [
     18300.0,
     22500.0
    ],
    [
     19050.0,
     23550.0
    ],
    [
     19950.0,
     22650.0
    ],
    [
     19950.0,
     24450.0
    ],
    [
     20850.0,
     23550.0
    ]
   ],
   "vertidos": 3,
   "separacion": 3000,
   "radio_sector": 1000,
   "dist_foto": 450,
   "h_min": 150,
   "techo": 900,
   "radio_pista": 5000,
   "limite_s": 2400
  }
 },
 "libre_cartagena": {
  "vehiculos": ["avion", "dron", "fpv", "uav"],
  "pista": {"nombre": "San Javier 05R/23L", "n": 17121.5, "e": 20133.2, "rumbo": 45.86, "largo": 2311, "ancho": 45},
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
    "contorno": [[37.613164, -0.975122], [37.613178, -0.974609], [37.613191, -0.974021], [37.613200, -0.973826], [37.614295, -0.972974], [37.615252, -0.974800], [37.613979, -0.975854], [37.613164, -0.975122]],
    "sin_arboles": [[43, 6597], [43, 6702], [82, 6702], [82, 6597]]
   },
   {
    "nombre": "Los Halcones de la Rambla",
    "nota": "Campo del Club Deportivo de Aeromodelismo Los Halcones de la Rambla (El Jimenado, Torre-Pacheco): pista de asfalto orientada 250-70; despegue desde la cabecera este hacia el 250. Zona de detalle a 0,25 m (halcones_rambla).",
    "lat": 37.761795,
    "lon": -1.012243,
    "rumbo": 250,
    "contorno": [[37.761587, -1.013745], [37.762469, -1.011307], [37.761791, -1.010939], [37.760977, -1.013462]]
   },
   {
    "nombre": "SABIC (La Aljorra)",
    "nota": "Solar despejado junto a la fábrica de SABIC de La Aljorra, entre las plantas fotovoltaicas (las filas de paneles de la ortofoto son reales): despegue hacia el sudeste, sobre la fábrica. Zona de detalle a 0,25 m (fotovoltaica).",
    "lat": 37.711444,
    "lon": -1.105328,
    "rumbo": 125,
    "contorno": [[37.711758, -1.106264], [37.712185, -1.105356], [37.711219, -1.10425], [37.710635, -1.104988]]
   }
  ]
 },
 "libre": {
  "vehiculos": ["avion", "dron", "fpv"],
  "nombre": "Vuelo libre",
  "desc": "Sin objetivos. Cuenta para las horas de entrenamiento. Da vueltas al circuito por fuera de los pilones, en el sentido que quieras: se cronometra cada vuelta. También puedes darte la vuelta y practicar en la zona 2.",
  "objetivos": []
 }
};
