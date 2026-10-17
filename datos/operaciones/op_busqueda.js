// Búsqueda y rescate. Datos comunes de los simuladores: ver datos/escenarios.js.
ESCENARIOS["op_busqueda"] = {
 "nombre": "Búsqueda y rescate",
 "vehiculos": [
  "dron"
 ],
 "mundo": "cartagena",
 "zona": 3,
 "dificultad": 3,
 "viento": {
  "vel": 4,
  "desde": 300,
  "rachas": true
 },
 "desc": "Un senderista se ha perdido en el monte al sur de Fuente Álamo. Búscalo dentro de la zona marcada con jalones amarillos, hazle una foto centrada y envía su posición a los equipos de tierra. Tienes 8 minutos.",
 "objetivos": [
  [
   "localizar",
   "Encontrar al senderista y hacerle una foto con él en el centro, a menos de 60 m"
  ],
  [
   "posicion",
   "Enviar su posición con menos de 10 m de error"
  ],
  [
   "tiempo",
   "En menos de 8 minutos desde el despegue"
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
  "cliente": "Emergencias 112 Región de Murcia",
  "lugar": "Monte al sur de Fuente Álamo. Despegue desde el camino de tierra.",
  "trabajo": "Búsqueda de una persona: chaqueta roja y mochila naranja. Barre la zona con la cámara inclinada y, al verla, hazle una foto con ella en el centro de la imagen: la posición se calcula con el centro de la foto.",
  "entrega": "Foto de la persona y su posición.",
  "salida": {
   "n": 3368,
   "e": -12850,
   "rumbo": 180
  },
  "zona": {
   "n0": 3020,
   "n1": 3330,
   "e0": -13150,
   "e1": -12650
  },
  "limite_s": 480,
  "dist": 60
 }
};
