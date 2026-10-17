// Localizar un vehículo. Datos comunes de los simuladores: ver datos/escenarios.js.
ESCENARIOS["op_rec_busqueda"] = {
 "nombre": "Localizar un vehículo",
 "vehiculos": [
  "uav",
  "avion"
 ],
 "mundo": "cartagena",
 "zona": 3,
 "dificultad": 3,
 "viento": {
  "vel": 5,
  "desde": 270,
  "rachas": true
 },
 "desc": "Un camión se ha escondido entre los campos al suroeste de El Jimenado. Búscalo dentro de la zona marcada, hazle una foto centrada y envía su posición. Tienes 15 minutos.",
 "objetivos": [
  [
   "localizar",
   "Encontrar el camión y hacerle una foto con él en el centro, a menos de 300 m"
  ],
  [
   "posicion",
   "Enviar su posición con menos de 25 m de error"
  ],
  [
   "tiempo",
   "En menos de 15 minutos desde el lanzamiento"
  ],
  [
   "techo",
   "Sin pasar de 150 m sobre el suelo"
  ],
  [
   "minima",
   "Sin bajar de 30 m sobre el suelo lejos del lanzamiento (a más de 300 m)"
  ],
  [
   "casa",
   "Aterrizar a menos de 50 m del punto de lanzamiento"
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
  "avion": "GRAJO",
  "elegir": [
   "GRAJO",
   "G1",
   "E3"
  ],
  "cliente": "Unidad de reconocimiento · jefe de la sección",
  "lugar": "Campos al suroeste de El Jimenado: zona de 1,2 × 1,2 km marcada con jalones amarillos.",
  "trabajo": "Barre la zona en pasadas paralelas mirando al suelo. El camión va pintado de camuflaje: con el infrarrojo (C) el motor caliente se ve mejor. Al verlo, foto con el camión en el centro: la posición se calcula con el centro de la foto (cuanto más inclinada hacia abajo esté la cámara, mejor). Con el Grajo, la cámara 3 es la del morro (fija: V cambia de la frontal a la lateral; orientable: flechas con Mayúsculas) y F hace la foto con la cruz; con el Poli-1 o el Entrenador 1, la cámara 3 es la de a bordo, que mira al frente: apunta con el avión y F hace la foto.",
  "entrega": "La foto del camión y su posición.",
  "salida": {
   "n": 16428.0,
   "e": 3290.0,
   "rumbo": 0.0
  },
  "recon": {
   "techo": 150,
   "minima": 30,
   "radio_despegue": 300,
   "casa_m": 50,
   "dist_foto": 300,
   "limite_s": 900,
   "error": 25,
   "zona": {
    "n0": 14900,
    "n1": 16100,
    "e0": 1400,
    "e1": 2600
   }
  }
 }
};
