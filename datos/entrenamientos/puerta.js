// 5 · Puerta. Datos comunes de los simuladores: ver datos/escenarios.js.
ESCENARIOS["puerta"] = {
 "vehiculos": [
  "avion",
  "dron"
 ],
 "nombre": "5 · Puerta",
 "zona": 2,
 "desc": "Cruza las dos puertas de pilones, una después de la otra y dos veces: naranja, verde, naranja, verde. La naranja se cruza de este a oeste o al revés y la verde, girada, de norte a sur o al revés; siempre por debajo de lo alto de los pilones (20 m). Luego aterriza.",
 "objetivos": [
  [
   "subir",
   "Subir a 20 m"
  ],
  [
   "puerta1",
   "Cruzar la puerta naranja"
  ],
  [
   "puerta2",
   "Después, la puerta verde"
  ],
  [
   "puerta3",
   "Otra vez la naranja"
  ],
  [
   "puerta4",
   "Y otra vez la verde"
  ],
  [
   "aterrizar",
   "Aterrizar sin daños"
  ]
 ],
 "dificultad": 2,
 "titulo_grupo": "Zona 2 · Precisión, detrás del piloto (práctica)"
};
