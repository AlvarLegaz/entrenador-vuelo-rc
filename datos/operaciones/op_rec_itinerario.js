// Reconocimiento de itinerario. Datos comunes de los simuladores: ver datos/escenarios.js.
ESCENARIOS["op_rec_itinerario"] = {
 "nombre": "Reconocimiento de itinerario",
 "vehiculos": [
  "uav",
  "avion"
 ],
 "mundo": "cartagena",
 "zona": 3,
 "dificultad": 2,
 "viento": {
  "vel": 3,
  "desde": 0,
  "rachas": true
 },
 "desc": "Antes de que pase un convoy, reconoce el itinerario: fotografía los 4 puntos de control (cruces de caminos) con la cruz de la cámara y avisa de si hay vehículos en ellos. Lanzamiento a mano desde Los Halcones.",
 "objetivos": [
  [
   "puntos",
   "Fotografiar los 4 puntos de control con la cruz sobre el cruce, a menos de 300 m"
  ],
  [
   "vehiculos",
   "Informar de los vehículos que hay en los puntos (se ve en la foto)"
  ],
  [
   "tiempo",
   "Los 4 puntos en 20 minutos desde el lanzamiento"
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
  "lugar": "Campo de Cartagena, al norte y al oeste de El Jimenado. Lanzamiento desde el campo de Los Halcones de la Rambla.",
  "trabajo": "Recorre el itinerario de los puntos de control 1 a 4 (círculos en el mapa) y fotografía cada cruce con la cruz de la cámara encima, desde menos de 300 m. En la foto se ve si hay vehículos en el punto: se informa solo. Vuela entre 30 y 150 m sobre el suelo. Con el Grajo, la cámara 3 es la del morro (fija: V cambia de la frontal a la lateral; orientable: flechas con Mayúsculas) y F hace la foto con la cruz; con el Poli-1 o el Entrenador 1, la cámara 3 es la de a bordo, que mira al frente: apunta con el avión y F hace la foto.",
  "entrega": "Una foto de cada punto de control y los vehículos que hay en ellos.",
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
   "limite_s": 1200,
   "con_vehiculo": 2,
   "puntos": [
    {
     "n": 16900,
     "e": 3191,
     "nombre": "cruce de caminos al norte"
    },
    {
     "n": 17697,
     "e": 3183,
     "nombre": "cruce con la carretera"
    },
    {
     "n": 17702,
     "e": 1511,
     "nombre": "cruce del noroeste"
    },
    {
     "n": 15460,
     "e": 1756,
     "nombre": "cruce del suroeste"
    }
   ]
  }
 }
};
