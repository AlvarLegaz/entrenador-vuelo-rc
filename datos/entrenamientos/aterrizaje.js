// 9 · Aterrizaje guiado. Datos comunes de los simuladores: ver datos/escenarios.js.
ESCENARIOS["aterrizaje"] = {
 "vehiculos": [
  "avion"
 ],
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
};
