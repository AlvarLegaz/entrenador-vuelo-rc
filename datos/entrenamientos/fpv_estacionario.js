// 1 · Despegue y estacionario. Datos comunes de los simuladores: ver datos/escenarios.js.
ESCENARIOS["fpv_estacionario"] = {
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
};
