// 4 · Circuito de puertas. Datos comunes de los simuladores: ver datos/escenarios.js.
ESCENARIOS["fpv_circuito"] = {
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
};
