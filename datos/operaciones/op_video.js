// Grabación de vídeo. Datos comunes de los simuladores: ver datos/escenarios.js.
ESCENARIOS["op_video"] = {
 "nombre": "Grabación de vídeo",
 "vehiculos": [
  "dron"
 ],
 "mundo": "cartagena",
 "zona": 3,
 "dificultad": 3,
 "viento": {
  "vel": 5,
  "desde": 60,
  "rachas": true
 },
 "desc": "Una productora quiere un plano en órbita del faro de Cabo de Palos para un anuncio: una vuelta completa grabando, a 30–70 m, con el faro siempre centrado, a altura constante y sin tirones.",
 "objetivos": [
  [
   "orbita",
   "Una órbita completa grabando: a 30–70 m del faro, con el faro centrado (±15°) y a altura constante (±5 m)"
  ],
  [
   "suave",
   "Plano estable: girar a menos de 60°/s mientras se graba"
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
  "cliente": "Productora audiovisual",
  "lugar": "Faro de Cabo de Palos (Cartagena). Despegue desde la explanada del faro.",
  "trabajo": "Órbita alrededor del faro: palanca derecha de lado y guiñada a la vez, para dar la vuelta mirándolo siempre. Graba con el botón de vídeo (V).",
  "entrega": "Un vídeo de una órbita completa, estable y centrada.",
  "salida": {
   "n": 2392,
   "e": 31720,
   "rumbo": 0
  },
  "faro": {
   "n": 2424.0,
   "e": 31713.7,
   "radio": 3.5,
   "alto": 51
  },
  "orbita": [
   30,
   70
  ],
  "centrado": 15,
  "variacion": 5,
  "giro_max": 60
 }
};
