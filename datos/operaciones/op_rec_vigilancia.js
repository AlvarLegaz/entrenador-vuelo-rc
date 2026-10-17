// Vigilancia de un punto. Datos comunes de los simuladores: ver datos/escenarios.js.
ESCENARIOS["op_rec_vigilancia"] = {
 "nombre": "Vigilancia de un punto",
 "vehiculos": [
  "uav",
  "avion"
 ],
 "mundo": "cartagena",
 "zona": 3,
 "dificultad": 2,
 "viento": {
  "vel": 4,
  "desde": 300,
  "rachas": true
 },
 "desc": "Hay un vehículo sospechoso junto a un cortijo, 1,7 km al este. Vigílalo durante 90 segundos con la cámara sin que te oigan (sin bajar de 80 m cerca de él), hazle una foto al acabar y vuelve.",
 "objetivos": [
  [
   "vigilar",
   "Tener el vehículo en la imagen 90 segundos (en total), a menos de 500 m"
  ],
  [
   "foto",
   "Hacerle una foto con la cruz encima al acabar la vigilancia"
  ],
  [
   "ruido",
   "Que no te oigan: a menos de 250 m de él, no bajar de 80 m sobre el suelo"
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
  "lugar": "Cortijo junto al cruce, 1,7 km al este de Los Halcones de la Rambla (círculo rojo en el mapa).",
  "trabajo": "Llega al cortijo, ponte en órbita (con el Grajo: clic en el mapa sobre el objetivo, y la cámara lateral o la torreta mirándolo) y mantenlo en la imagen. Cuenta el tiempo que está en la imagen a menos de 500 m. Cerca de él (250 m), no bajes de 80 m: un avión bajo se oye. Con el Grajo, la cámara 3 es la del morro (fija: V cambia de la frontal a la lateral; orientable: flechas con Mayúsculas) y F hace la foto con la cruz; con el Poli-1 o el Entrenador 1, la cámara 3 es la de a bordo, que mira al frente: apunta con el avión y F hace la foto.",
  "entrega": "Noventa segundos de vigilancia y una foto del vehículo.",
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
   "vigilar_s": 90,
   "dist_vigilar": 500,
   "ruido_r": 250,
   "ruido_h": 80,
   "objetivo": {
    "n": 16058,
    "e": 4935,
    "nombre": "cortijo del cruce"
   }
  }
 }
};
