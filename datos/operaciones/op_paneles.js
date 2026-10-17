// Inspección de paneles fotovoltaicos. Datos comunes de los simuladores: ver datos/escenarios.js.
ESCENARIOS["op_paneles"] = {
 "nombre": "Inspección de paneles fotovoltaicos",
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
 "desc": "La planta fotovoltaica de La Aljorra, junto a la fábrica de SABIC (83 filas de seguidores solares de 320 m, unos 24.000 módulos), produce menos de lo que debería. Con el dron de inspección recorre las filas y fotografía desde arriba, sin bajar a menos de 3 m de los paneles, tres averías: cristales rotos (solo se ven con la cámara normal), excrementos de aves (se ven con la normal, y en la térmica salen como un punto caliente) y diodos de bypass averiados (a simple vista no se nota nada; en la térmica, una franja caliente de un tercio del módulo). Son 6 módulos con el cristal roto o con excrementos y 3 con el diodo averiado.",
 "objetivos": [
  [
   "defectos",
   "Fotografiar los 6 módulos dañados a simple vista (cristal roto, con la cámara normal; excrementos de aves, con la normal o la térmica): de 4 a 20 m (más lejos con zoom), con la cámara hacia abajo (−45° o más)"
  ],
  [
   "calientes",
   "Encontrar con la cámara térmica los 3 módulos con un diodo de bypass averiado (franja caliente de un tercio del módulo) y fotografiarlos igual: de 4 a 20 m (más lejos con zoom), hacia abajo"
  ],
  [
   "baja",
   "Nunca a menos de 3 m sobre los paneles"
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
  "avion": "HQ3T",
  "cliente": "Planta fotovoltaica de La Aljorra · mantenimiento",
  "lugar": "La Aljorra (Cartagena), junto a la fábrica de SABIC. Despegue desde el camino al norte del bloque de paneles.",
  "trabajo": "Inspección de los módulos fila por fila con la cámara hacia abajo. Con la cámara normal, los cristales rotos (grietas blancas) y los excrementos de aves (manchas blancas). Con la cámara térmica (C), los diodos de bypass averiados: una franja naranja de un tercio del módulo sobre el morado de los paneles; los excrementos salen como un punto caliente amarillo y el cristal roto apenas se distingue. Con el zoom (Z / X) se puede volar más alto y ver más filas.",
  "entrega": "9 fotos: una por módulo con el cristal roto o con excrementos (6) y una por diodo de bypass averiado (3, cámara térmica), para cambiarlos o limpiarlos.",
  "salida": {
   "n": 9539.4,
   "e": -5195.7,
   "rumbo": 180
  },
  "planta": {
   "n0": 9527.38,
   "e0": -5419.44,
   "rumbo": 181.157,
   "filas": 83,
   "largo": 323,
   "ancho": 2.2,
   "separacion": 5.5109,
   "inclinacion": 15,
   "h0": 1.0,
   "tramo": 30
  },
  "defectos": [
   [
    3,
    23
   ],
   [
    11,
    118
   ],
   [
    19,
    61
   ],
   [
    28,
    140
   ],
   [
    37,
    9
   ],
   [
    46,
    287
   ]
  ],
  "dist": [
   4,
   20
  ],
  "gimbal": -45,
  "minima": 3,
  "sin_arboles": [
   [
    9530.5,
    -5423.4
   ],
   [
    9201.5,
    -5430.0
   ],
   [
    9192.2,
    -4970.2
   ],
   [
    9521.2,
    -4963.6
   ]
  ],
  "calientes": 3
 }
};
