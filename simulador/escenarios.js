// Entrenamientos y vuelos libres del simulador: datos COMUNES de la version web (simulador.html) y de la de Godot
// (simulador_godot/scripts/escenarios.gd). Es JSON estricto dentro de una asignacion: Godot lee el objeto que va
// detras de "window.ESCENARIOS = ". La logica (evaluar los objetivos, la guia del aterrizaje) esta en el codigo de cada
// version. Campos: nombre, desc, objetivos [[id, texto]], sentido (circuito: 1 o -1), zona (2: detras del piloto;
// 3: mundo real), mundo (id del mundo real), viento fijo {vel, desde, rachas}, guia, enVuelo {N, E, h, rumbo, gas},
// dificultad (estrellas, 1-3), titulo_grupo (cabecera de su grupo en la pantalla de entrenamientos) y destacados
// (vuelo libre en un mundo real: puntos de despegue resaltados en el mapa de salida, con contorno lat/lon y rumbo, y
// sin_arboles: poligono [N, E] del plano del mundo donde no se ponen los arboles detectados en la ortofoto),
// vehiculos (en que vehiculos sale en la pantalla de entrenamientos: "avion", "dron" (el DJI) y "fpv") y pista_fpv (los
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
   "cliente": "CIFP Politécnico de Cartagena · departamento de mantenimiento",
   "lugar": "Calle Grecia, 56, Cartagena. Despegue desde el aparcamiento interior.",
   "trabajo": "Inspección visual de cubiertas y fachadas: una foto nítida de cada punto marcado con una placa naranja numerada.",
   "entrega": "6 fotos, una por punto, para el informe de mantenimiento.",
   "salida": {
    "n": 58.3,
    "e": 6651.4,
    "rumbo": 110
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
   "cliente": "Topografía Campo de Cartagena",
   "lugar": "El Jimenado (Torre-Pacheco). Despegue desde la pista del club Los Halcones de la Rambla.",
   "trabajo": "Vuelo fotogramétrico: pasadas paralelas a 40–60 m con el gimbal a −90° y una foto cada 20–25 m. La parcela está marcada con jalones rojos y blancos en las esquinas.",
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
   "cliente": "Explotación agrícola de El Jimenado",
   "lugar": "Campo de brócoli al sur de la pista de Los Halcones de la Rambla.",
   "trabajo": "Localizar los rodales con plaga (manchas amarillas en el cultivo) y fotografiarlos para el técnico: una foto vertical de cada uno.",
   "entrega": "5 fotos verticales, una por mancha.",
   "salida": {
    "n": 16476.3,
    "e": 3322.1,
    "rumbo": 160
   },
   "parcela": {
    "n0": 16230,
    "n1": 16390,
    "e0": 3220,
    "e1": 3400
   },
   "manchas": [
    [
     16360,
     3250,
     4
    ],
    [
     16300,
     3330,
     5
    ],
    [
     16255,
     3240,
     3.5
    ],
    [
     16340,
     3385,
     4
    ],
    [
     16245,
     3365,
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
  "desc": "La planta fotovoltaica de El Mingrano (20 filas de 150 m, unos 3.000 módulos) produce menos de lo que debería. Recorre las filas, encuentra los 8 módulos dañados (cristal roto o muy sucio) y fotografía cada uno desde arriba, sin bajar a menos de 3 m de los paneles.",
  "objetivos": [
   [
    "defectos",
    "Fotografiar los 8 módulos dañados: de 4 a 20 m, con la cámara hacia abajo (−45° o más)"
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
   "cliente": "Planta fotovoltaica de El Mingrano · mantenimiento",
   "lugar": "El Mingrano (Fuente Álamo, Campo de Cartagena). Despegue desde el camino junto a la planta.",
   "trabajo": "Inspección visual de los módulos fila por fila, con la cámara hacia abajo. En una inspección real se usa además una cámara térmica para ver los puntos calientes.",
   "entrega": "8 fotos, una por módulo dañado, para cambiarlos.",
   "salida": {
    "n": 3232,
    "e": -15115,
    "rumbo": 0
   },
   "planta": {
    "n0": 3262,
    "e0": -15190,
    "filas": 20,
    "largo": 150,
    "ancho": 4,
    "separacion": 8,
    "inclinacion": 30,
    "h0": 0.6
   },
   "defectos": [
    [
     1,
     23
    ],
    [
     3,
     118
    ],
    [
     6,
     61
    ],
    [
     8,
     140
    ],
    [
     11,
     9
    ],
    [
     13,
     87
    ],
    [
     16,
     44
    ],
    [
     19,
     131
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
     3248,
     -15200
    ],
    [
     3248,
     -15030
    ],
    [
     3424,
     -15030
    ],
    [
     3424,
     -15200
    ]
   ]
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
 "libre_cartagena": {
  "vehiculos": ["avion", "dron", "fpv"],
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
