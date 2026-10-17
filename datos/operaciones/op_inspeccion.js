// Inspección de edificios. Datos comunes de los simuladores: ver datos/escenarios.js.
ESCENARIOS["op_inspeccion"] = {
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
};
