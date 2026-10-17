// Fotogrametría de una parcela. Datos comunes de los simuladores: ver datos/escenarios.js.
ESCENARIOS["op_fotogrametria"] = {
 "nombre": "Fotogrametría de una parcela",
 "vehiculos": [
  "dron"
 ],
 "mundo": "cartagena",
 "zona": 3,
 "dificultad": 2,
 "viento": {
  "vel": 3,
  "desde": 70,
  "rachas": true
 },
 "desc": "Un estudio de topografía quiere el modelo 3D de una parcela de 160 × 120 m junto al campo del club: pasadas en paralelo a altura fija con la cámara mirando abajo y fotos que se solapen.",
 "objetivos": [
  [
   "cobertura",
   "Cubrir el 90 % de la parcela con solape (cada punto en 2 fotos o más), con la cámara hacia abajo y entre 40 y 60 m"
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
  "cliente": "Topografía Campo de Cartagena",
  "lugar": "El Jimenado (Torre-Pacheco). Despegue desde la pista del club Los Halcones de la Rambla.",
  "trabajo": "Vuelo fotogramétrico: pasadas paralelas a 40–60 m con el gimbal a −89° (mirando abajo) y una foto cada 20–25 m. La parcela está marcada con jalones rojos y blancos en las esquinas.",
  "entrega": "Fotos con solape para el modelo 3D y la ortofoto de la parcela.",
  "salida": {
   "n": 16476.3,
   "e": 3322.1,
   "rumbo": 250
  },
  "parcela": {
   "n0": 16560,
   "n1": 16680,
   "e0": 3000,
   "e1": 3160
  },
  "altura": [
   40,
   60
  ],
  "gimbal": -85,
  "solape": 2,
  "cubrir": 0.9
 }
};
