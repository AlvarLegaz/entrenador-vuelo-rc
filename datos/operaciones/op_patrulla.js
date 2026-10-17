// Patrulla del Mar Menor: vertidos. Datos comunes de los simuladores: ver datos/escenarios.js.
ESCENARIOS["op_patrulla"] = {
 "nombre": "Patrulla del Mar Menor: vertidos",
 "vehiculos": [
  "uav"
 ],
 "mundo": "cartagena",
 "zona": 3,
 "dificultad": 3,
 "viento": {
  "vel": 5,
  "desde": 60,
  "rachas": true
 },
 "desc": "Un pesquero ha avisado de tres manchas de hidrocarburo en el Mar Menor. Con el UAV de vigilancia Cernícalo XM-7 (despega de la pista 05R) o con el Grajo MX-2 (se lanza a mano desde la cabecera de la 05R), sal de la base aérea de San Javier, patrulla los tres sectores del aviso, encuentra cada vertido con la cámara (zoom y térmica), fotografíalo con la cruz sobre la mancha para enviar su posición a Salvamento Marítimo y vuelve a aterrizar en la pista.",
 "objetivos": [
  [
   "vertidos",
   "Localizar los 3 vertidos y fotografiarlos con la cruz de la cámara sobre la mancha (su posición se envía con la foto)"
  ],
  [
   "despegue",
   "Despegar (el Grajo, lanzarlo) desde la pista 05R de San Javier"
  ],
  [
   "a_mano",
   "Despegar y aterrizar a mano, sin el despegue ni el aterrizaje automáticos (el lanzamiento del Grajo es a mano)"
  ],
  [
   "altura",
   "Patrullar a 150 m o más sobre el agua (salvo a menos de 5 km de la pista)"
  ],
  [
   "techo",
   "Sin pasar de 900 m sobre el suelo"
  ],
  [
   "tiempo",
   "Los tres vertidos en 40 minutos desde el despegue"
  ],
  [
   "pista",
   "Aterrizar en la pista de San Javier y pararse en ella"
  ],
  [
   "aterrizar",
   "Aterrizar sin daños"
  ]
 ],
 "operacion": {
  "avion": "XM7",
  "elegir": [
   "XM7",
   "GRAJO"
  ],
  "cliente": "Capitanía Marítima de Cartagena · Salvamento Marítimo",
  "lugar": "Base aérea de San Javier (Murcia), pista 05R/23L de 2.311 m. Patrulla sobre el Mar Menor.",
  "trabajo": "Salida de la 05R (el Cernícalo despega de la pista; el Grajo se lanza a mano desde la cabecera, de cara al viento), vuelo a los sectores del aviso (círculos naranjas en el mapa) y búsqueda de las manchas con la cámara: en la normal son manchas oscuras con brillos de colores; en la térmica, el hidrocarburo calentado por el sol sale más caliente que el agua. Con el piloto automático en «ir a punto» (clic en el mapa) el avión da vueltas sobre el sector; con la torreta, las flechas la mueven y K la fija sobre un punto (el morro fijo del Grajo se apunta con el avión). Foto (F) con la cruz sobre la mancha, a una distancia razonable para su zoom. El Grajo es más lento: cuenta con el tiempo, y aterriza en pérdida profunda junto al punto de lanzamiento.",
  "entrega": "Una foto de cada vertido con su posición, para enviar las embarcaciones de limpieza.",
  "salida": {
   "n": 17163.3,
   "e": 20176.3,
   "rumbo": 45.86
  },
  "pista": {
   "nombre": "San Javier 05R/23L",
   "n": 17121.5,
   "e": 20133.2,
   "rumbo": 45.86,
   "largo": 2311,
   "ancho": 45
  },
  "candidatos_vertido": [
   [
    2850.0,
    27450.0
   ],
   [
    3900.0,
    25950.0
   ],
   [
    3900.0,
    28050.0
   ],
   [
    4500.0,
    27000.0
   ],
   [
    4800.0,
    24300.0
   ],
   [
    5100.0,
    23100.0
   ],
   [
    5100.0,
    25650.0
   ],
   [
    5700.0,
    22050.0
   ],
   [
    6000.0,
    24000.0
   ],
   [
    6300.0,
    25200.0
   ],
   [
    6600.0,
    21150.0
   ],
   [
    6600.0,
    22950.0
   ],
   [
    6600.0,
    26400.0
   ],
   [
    7200.0,
    24000.0
   ],
   [
    7500.0,
    22050.0
   ],
   [
    7500.0,
    25200.0
   ],
   [
    7650.0,
    20400.0
   ],
   [
    7800.0,
    26400.0
   ],
   [
    8100.0,
    23100.0
   ],
   [
    8550.0,
    21300.0
   ],
   [
    8700.0,
    19650.0
   ],
   [
    9300.0,
    22950.0
   ],
   [
    9600.0,
    20550.0
   ],
   [
    9750.0,
    19050.0
   ],
   [
    9750.0,
    25650.0
   ],
   [
    10500.0,
    22650.0
   ],
   [
    10650.0,
    19950.0
   ],
   [
    10650.0,
    21150.0
   ],
   [
    10650.0,
    24600.0
   ],
   [
    10800.0,
    18150.0
   ],
   [
    10800.0,
    26250.0
   ],
   [
    11550.0,
    22050.0
   ],
   [
    11700.0,
    19050.0
   ],
   [
    11700.0,
    20550.0
   ],
   [
    11700.0,
    23250.0
   ],
   [
    11700.0,
    25200.0
   ],
   [
    12000.0,
    17850.0
   ],
   [
    12000.0,
    26400.0
   ],
   [
    12600.0,
    21450.0
   ],
   [
    12600.0,
    24150.0
   ],
   [
    12750.0,
    19650.0
   ],
   [
    12750.0,
    22650.0
   ],
   [
    12900.0,
    25350.0
   ],
   [
    13050.0,
    18450.0
   ],
   [
    13200.0,
    26550.0
   ],
   [
    13650.0,
    20550.0
   ],
   [
    13650.0,
    23550.0
   ],
   [
    13800.0,
    21750.0
   ],
   [
    13950.0,
    19350.0
   ],
   [
    13950.0,
    24750.0
   ],
   [
    14250.0,
    25950.0
   ],
   [
    14700.0,
    22650.0
   ],
   [
    14850.0,
    20250.0
   ],
   [
    14850.0,
    23850.0
   ],
   [
    15000.0,
    21450.0
   ],
   [
    15150.0,
    25050.0
   ],
   [
    15900.0,
    22350.0
   ],
   [
    16050.0,
    20700.0
   ],
   [
    16050.0,
    23550.0
   ],
   [
    16050.0,
    25950.0
   ],
   [
    16350.0,
    24750.0
   ],
   [
    16950.0,
    21600.0
   ],
   [
    17100.0,
    22800.0
   ],
   [
    17400.0,
    24000.0
   ],
   [
    18000.0,
    25200.0
   ],
   [
    18300.0,
    22500.0
   ],
   [
    19050.0,
    23550.0
   ],
   [
    19950.0,
    22650.0
   ],
   [
    19950.0,
    24450.0
   ],
   [
    20850.0,
    23550.0
   ]
  ],
  "vertidos": 3,
  "separacion": 3000,
  "radio_sector": 1000,
  "dist_foto": 450,
  "h_min": 150,
  "techo": 900,
  "radio_pista": 5000,
  "limite_s": 2400
 }
};
