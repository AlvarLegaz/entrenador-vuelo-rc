// Agricultura: plaga en el cultivo. Datos comunes de los simuladores: ver datos/escenarios.js.
ESCENARIOS["op_agricultura"] = {
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
   "poligono": [
    [
     16349,
     3182
    ],
    [
     16449,
     3454
    ],
    [
     16273,
     3527
    ],
    [
     16195,
     3386
    ],
    [
     16263,
     3352
    ],
    [
     16251,
     3300
    ],
    [
     16300,
     3281
    ],
    [
     16277,
     3204
    ]
   ]
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
};
