// 2 · La caja. Datos comunes de los simuladores: ver datos/escenarios.js.
ESCENARIOS["fpv_caja"] = {
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
};
