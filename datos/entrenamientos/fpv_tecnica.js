// 6 · Técnica. Datos comunes de los simuladores: ver datos/escenarios.js.
ESCENARIOS["fpv_tecnica"] = {
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
};
