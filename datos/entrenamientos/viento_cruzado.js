// 3 · Viento cruzado. Datos comunes de los simuladores: ver datos/escenarios.js.
ESCENARIOS["viento_cruzado"] = {
 "vehiculos": [
  "avion"
 ],
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
};
