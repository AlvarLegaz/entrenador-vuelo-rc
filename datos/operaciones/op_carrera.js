// Carrera de drones del Politécnico. Datos comunes de los simuladores: ver datos/escenarios.js.
ESCENARIOS["op_carrera"] = {
 "nombre": "Carrera de drones del Politécnico",
 "vehiculos": [
  "fpv",
  "dron"
 ],
 "mundo": "cartagena",
 "zona": 3,
 "dificultad": 3,
 "viento": {
  "vel": 3,
  "desde": 90,
  "rachas": false
 },
 "desc": "Carrera de drones por el CIFP Politécnico y el barrio de al lado: 19 obstáculos (puertas, arcos hinchables, banderas y un picado desde un andamio) que hay que pasar en orden. El cronómetro empieza al cruzar el primero y para en la meta; si te saltas uno, quedas descalificado. Vale cualquier dron del hangar.",
 "objetivos": [
  [
   "secuencia",
   "Pasar los 19 obstáculos en orden, sin saltarse ninguno"
  ],
  [
   "meta",
   "Cruzar la meta (el obstáculo 19)"
  ],
  [
   "tiempo",
   "Terminar la carrera en menos de 4 minutos"
  ],
  [
   "choques",
   "Sin chocar con los obstáculos, los edificios ni los árboles"
  ]
 ],
 "operacion": {
  "avion": "FPV",
  "elegir": [
   "fpv",
   "dron"
  ],
  "cliente": "Club de drones del CIFP Politécnico · liga escolar de carreras",
  "lugar": "CIFP Politécnico de Cartagena (calle Grecia, 56), el descampado, el campo de al lado de la vía y las calles del barrio. Salida desde el aparcamiento interior.",
  "trabajo": "Despega y pasa los 19 obstáculos en su orden: los marcos y los arcos por dentro y de frente, entre las dos banderas y el picado del andamio de arriba abajo. Una marca en la pantalla señala el siguiente (con una flecha en el borde si no está a la vista) y se ilumina de verde. El cronómetro empieza en el primero y para en la meta. Si cruzas uno que no toca, quedas descalificado.",
  "entrega": "El tiempo de la carrera: el mejor de la sala sale arriba de la pantalla y el mejor de cada piloto se guarda en su perfil.",
  "salida": {
   "n": 58.0,
   "e": 6653.0,
   "rumbo": 95.0
  },
  "carrera": {
   "obstaculos": [
    {
     "tipo": "puerta",
     "n": 54,
     "e": 6722,
     "rumbo": 100,
     "h": 1.5
    },
    {
     "tipo": "arco",
     "n": 60,
     "e": 6860,
     "rumbo": 80,
     "h": 0
    },
    {
     "tipo": "banderas",
     "n": 150,
     "e": 6900,
     "rumbo": 20,
     "h": 0
    },
    {
     "tipo": "picado",
     "n": 300,
     "e": 6880,
     "rumbo": 312,
     "h": 12
    },
    {
     "tipo": "arco",
     "n": 419.5,
     "e": 6747.4,
     "rumbo": 300,
     "h": 0
    },
    {
     "tipo": "banderas",
     "n": 330,
     "e": 6640,
     "rumbo": 220,
     "h": 0
    },
    {
     "tipo": "puerta",
     "n": 239.4,
     "e": 6736,
     "rumbo": 150,
     "h": 2
    },
    {
     "tipo": "arco",
     "n": 130,
     "e": 6790,
     "rumbo": 160,
     "h": 0
    },
    {
     "tipo": "banderas",
     "n": -9,
     "e": 6730.1,
     "rumbo": 210,
     "h": 0
    },
    {
     "tipo": "arco",
     "n": -60,
     "e": 6646,
     "rumbo": 180,
     "h": 0
    },
    {
     "tipo": "puerta",
     "n": -150,
     "e": 6646,
     "rumbo": 180,
     "h": 1.5
    },
    {
     "tipo": "puerta",
     "n": -200,
     "e": 6650,
     "rumbo": 180,
     "h": 1.5
    },
    {
     "tipo": "banderas",
     "n": -202.9,
     "e": 6722.7,
     "rumbo": 90,
     "h": 0
    },
    {
     "tipo": "puerta",
     "n": -200,
     "e": 6788,
     "rumbo": 90,
     "h": 1.5
    },
    {
     "tipo": "puerta",
     "n": -144,
     "e": 6793,
     "rumbo": 0,
     "h": 1.5
    },
    {
     "tipo": "puerta",
     "n": -144,
     "e": 6876,
     "rumbo": 90,
     "h": 1.5
    },
    {
     "tipo": "arco",
     "n": -100,
     "e": 6884,
     "rumbo": 0,
     "h": 0
    },
    {
     "tipo": "puerta",
     "n": -86.1,
     "e": 6780.5,
     "rumbo": 270,
     "h": 1.5
    },
    {
     "tipo": "arco",
     "n": 18.5,
     "e": 6704.3,
     "rumbo": 330,
     "h": 0
    }
   ],
   "limite_s": 240
  }
 }
};
