// 5 · Paso a ACRO. Datos comunes de los simuladores: ver datos/escenarios.js.
ESCENARIOS["fpv_acro"] = {
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
};
