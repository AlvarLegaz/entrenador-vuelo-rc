// 3 · Slalom y ocho. Datos comunes de los simuladores: ver datos/escenarios.js.
ESCENARIOS["fpv_slalom"] = {
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
};
