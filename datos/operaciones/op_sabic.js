// Inspección de la fábrica de SABIC. Datos comunes de los simuladores: ver datos/escenarios.js.
ESCENARIOS["op_sabic"] = {
 "nombre": "Inspección de la fábrica de SABIC",
 "vehiculos": [
  "dron"
 ],
 "mundo": "cartagena",
 "zona": 3,
 "dificultad": 3,
 "viento": {
  "vel": 6,
  "desde": 290,
  "rachas": true
 },
 "desc": "Trabajo largo (30 minutos) para pilotos con soltura: tres tareas de mantenimiento en la fábrica de SABIC de La Aljorra con el dron de inspección (zoom y cámara térmica). Prepara antes la estrategia: el orden de las tareas, la altura y por dónde vas a volar entre las unidades de proceso. Las pistas están en el GPS: los racks donde están los puntos calientes, la unidad con la alarma de gas y la antorcha.",
 "objetivos": [
  [
   "calientes",
   "Encontrar con la térmica los 4 puntos calientes de los racks: medidor puntual sobre cada uno 3 s, a menos de 15 m (o con zoom)"
  ],
  [
   "fuga",
   "Localizar la fuga de gas de la unidad con alarma y medir su temperatura con la térmica"
  ],
  [
   "atex",
   "No entrar en la zona ATEX: 30 m alrededor de la unidad con la fuga"
  ],
  [
   "placa",
   "Leer con el zoom (28x o más) la placa de la boca de la antorcha: foto desde más de 60 m de altura y a más de 50 m de ella"
  ],
  [
   "piloto",
   "Foto con la térmica del piloto de la antorcha (¿encendido o apagado?)"
  ],
  [
   "unidades",
   "Nunca a menos de 10 m por encima de las unidades de proceso"
  ],
  [
   "tiempo",
   "Las tres tareas en 30 minutos"
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
  "cliente": "Fábrica de policarbonato de La Aljorra · mantenimiento y seguridad",
  "lugar": "Fábrica de SABIC, La Aljorra (Cartagena). Despegue en el descampado entre las unidades de policarbonato y el rack principal.",
  "trabajo": "Tres tareas con el dron de inspección: 1) puntos calientes en los racks de tuberías (aislamiento roto: solo se ven con la térmica; las tuberías amarillas de vapor también están calientes y no son averías); 2) fuga de gas en la unidad con alarma: con la térmica el gas sale frío, y no se puede entrar en la zona ATEX de 30 m; 3) la antorcha: leer con el zoom la placa de su boca y comprobar con la térmica si su piloto está encendido. Pistas en el GPS: en naranja los racks con puntos calientes, en rojo la unidad con la alarma y su zona ATEX, y la antorcha.",
  "entrega": "La posición y temperatura de cada punto caliente y de la fuga, la foto de la placa y la foto térmica del piloto.",
  "salida": {
   "n": 10342.0,
   "e": -4490.8,
   "rumbo": 46
  },
  "racks": [
   {
    "e0": -4487.5,
    "n0": 10449.5,
    "e1": -4586.1,
    "n1": 10354.3,
    "alto": 7,
    "ancho": 5,
    "niveles": 2,
    "nombre": "R-1"
   },
   {
    "e0": -4455.1,
    "n0": 10319.5,
    "e1": -4386.4,
    "n1": 10248.3,
    "alto": 6,
    "ancho": 4,
    "niveles": 2,
    "nombre": "R-2"
   },
   {
    "e0": -4364.4,
    "n0": 10412.7,
    "e1": -4434.2,
    "n1": 10345.3,
    "alto": 7,
    "ancho": 5,
    "niveles": 2,
    "nombre": "R-3"
   },
   {
    "e0": -4543.7,
    "n0": 10513.4,
    "e1": -4409.6,
    "n1": 10374.6,
    "alto": 8,
    "ancho": 6,
    "niveles": 3,
    "nombre": "R-4"
   },
   {
    "e0": -4614.0,
    "n0": 10412.1,
    "e1": -4574.5,
    "n1": 10371.1,
    "alto": 6,
    "ancho": 4,
    "niveles": 2,
    "nombre": "R-5"
   },
   {
    "e0": -4487.3,
    "n0": 10540.0,
    "e1": -4631.2,
    "n1": 10401.1,
    "alto": 7,
    "ancho": 5,
    "niveles": 2,
    "nombre": "R-6"
   },
   {
    "e0": -4424.6,
    "n0": 10568.6,
    "e1": -4327.4,
    "n1": 10467.9,
    "alto": 7,
    "ancho": 5,
    "niveles": 2,
    "nombre": "R-7"
   },
   {
    "e0": -4369.7,
    "n0": 10189.3,
    "e1": -4319.0,
    "n1": 10136.8,
    "alto": 6,
    "ancho": 4,
    "niveles": 2,
    "nombre": "R-8"
   },
   {
    "e0": -4366.0,
    "n0": 10198.4,
    "e1": -4569.4,
    "n1": 10013.1,
    "alto": 9,
    "ancho": 7,
    "niveles": 3,
    "nombre": "R-9"
   },
   {
    "e0": -4232.5,
    "n0": 10553.9,
    "e1": -4342.6,
    "n1": 10447.7,
    "alto": 7,
    "ancho": 5,
    "niveles": 2,
    "nombre": "R-10"
   },
   {
    "e0": -4290.2,
    "n0": 10492.7,
    "e1": -4223.5,
    "n1": 10423.7,
    "alto": 6,
    "ancho": 4,
    "niveles": 2,
    "nombre": "R-11"
   },
   {
    "e0": -4077.7,
    "n0": 10468.5,
    "e1": -4366.0,
    "n1": 10198.4,
    "alto": 9,
    "ancho": 7,
    "niveles": 3,
    "nombre": "R-12"
   },
   {
    "e0": -4274.2,
    "n0": 10597.1,
    "e1": -4363.4,
    "n1": 10511.0,
    "alto": 6,
    "ancho": 4,
    "niveles": 2,
    "nombre": "R-13"
   },
   {
    "e0": -4335.3,
    "n0": 10660.4,
    "e1": -4457.6,
    "n1": 10542.3,
    "alto": 7,
    "ancho": 5,
    "niveles": 2,
    "nombre": "R-14"
   },
   {
    "e0": -4524.9,
    "n0": 10049.1,
    "e1": -4462.4,
    "n1": 9984.4,
    "alto": 6,
    "ancho": 4,
    "niveles": 2,
    "nombre": "R-15"
   },
   {
    "e0": -4272.1,
    "n0": 10593.5,
    "e1": -4236.0,
    "n1": 10556.1,
    "alto": 6,
    "ancho": 4,
    "niveles": 2,
    "nombre": "R-16"
   },
   {
    "e0": -4210.9,
    "n0": 10334.3,
    "e1": -4101.8,
    "n1": 10221.4,
    "alto": 7,
    "ancho": 5,
    "niveles": 2,
    "nombre": "R-17"
   },
   {
    "e0": -4569.4,
    "n0": 10013.1,
    "e1": -4515.2,
    "n1": 9957.0,
    "alto": 8,
    "ancho": 6,
    "niveles": 3,
    "nombre": "R-18"
   },
   {
    "e0": -4135.1,
    "n0": 10463.1,
    "e1": -4061.0,
    "n1": 10534.7,
    "alto": 6,
    "ancho": 4,
    "niveles": 2,
    "nombre": "R-19"
   }
  ],
  "calientes": 4,
  "unidades": [
   {
    "poligono": [
     [
      10390.2,
      -4574.8
     ],
     [
      10452.7,
      -4510.1
     ],
     [
      10412.4,
      -4471.2
     ],
     [
      10349.9,
      -4535.9
     ]
    ],
    "alto": 39.3,
    "valvulas": [
     [
      -4525.9,
      10399.9,
      9.2,
      10,
      8,
      46.0
     ],
     [
      -4513.2,
      10395.5,
      7.1,
      14,
      8,
      46.0
     ],
     [
      -4530.3,
      10387.3,
      7.2,
      8,
      6,
      46.0
     ],
     [
      -4538.7,
      10391.7,
      8.6,
      6,
      6,
      46.0
     ]
    ],
    "nombre": "U-1"
   },
   {
    "poligono": [
     [
      10317.1,
      -4401.4
     ],
     [
      10354.0,
      -4363.3
     ],
     [
      10310.8,
      -4321.6
     ],
     [
      10274.0,
      -4359.7
     ]
    ],
    "alto": 34.9,
    "valvulas": [
     [
      -4365.5,
      10310.1,
      7.6,
      8,
      7,
      46.0
     ],
     [
      -4348.3,
      10322.6,
      8.0,
      12,
      8,
      46.0
     ],
     [
      -4375.9,
      10320.9,
      7.4,
      6,
      7,
      46.0
     ],
     [
      -4365.7,
      10297.4,
      5.0,
      6,
      8,
      46.0
     ]
    ],
    "nombre": "U-2"
   },
   {
    "poligono": [
     [
      10441.2,
      -4618.5
     ],
     [
      10500.9,
      -4556.6
     ],
     [
      10489.4,
      -4545.5
     ],
     [
      10429.6,
      -4607.4
     ]
    ],
    "alto": 26.2,
    "valvulas": [
     [
      -4584.2,
      10461.8,
      4.1,
      14,
      7,
      46.0
     ],
     [
      -4590.7,
      10451.3,
      5.8,
      6,
      7,
      46.0
     ],
     [
      -4566.8,
      10486.9,
      4.4,
      10,
      6,
      46.0
     ],
     [
      -4599.4,
      10442.9,
      7.7,
      10,
      7,
      46.0
     ]
    ],
    "nombre": "U-3"
   },
   {
    "poligono": [
     [
      10531.5,
      -4525.0
     ],
     [
      10554.4,
      -4501.2
     ],
     [
      10518.4,
      -4466.5
     ],
     [
      10495.5,
      -4490.2
     ]
    ],
    "alto": 30.9,
    "valvulas": [
     [
      -4491.1,
      10526.6,
      6.8,
      8,
      7,
      46.0
     ],
     [
      -4499.7,
      10518.3,
      7.4,
      6,
      7,
      46.0
     ],
     [
      -4505.9,
      10533.2,
      4.4,
      8,
      7,
      46.0
     ],
     [
      -4484.6,
      10532.9,
      8.0,
      6,
      6,
      46.0
     ]
    ],
    "nombre": "U-4"
   },
   {
    "poligono": [
     [
      10303.8,
      -4328.8
     ],
     [
      10338.6,
      -4292.8
     ],
     [
      10306.2,
      -4261.6
     ],
     [
      10271.5,
      -4297.6
     ]
    ],
    "alto": 30.4,
    "valvulas": [
     [
      -4301.2,
      10305.5,
      6.6,
      12,
      6,
      46.0
     ],
     [
      -4297.2,
      10292.7,
      6.4,
      12,
      10,
      46.0
     ],
     [
      -4307.5,
      10312.0,
      8.4,
      14,
      8,
      46.0
     ],
     [
      -4282.4,
      10290.3,
      4.3,
      10,
      6,
      46.0
     ]
    ],
    "nombre": "U-5"
   },
   {
    "poligono": [
     [
      10236.4,
      -4315.1
     ],
     [
      10262.1,
      -4288.5
     ],
     [
      10226.9,
      -4254.5
     ],
     [
      10201.2,
      -4281.1
     ]
    ],
    "alto": 25.5,
    "valvulas": [
     [
      -4281.2,
      10235.8,
      9.0,
      8,
      7,
      46.0
     ],
     [
      -4277.1,
      10227.3,
      8.3,
      8,
      6,
      46.0
     ],
     [
      -4287.5,
      10242.3,
      6.4,
      8,
      7,
      46.0
     ],
     [
      -4290.0,
      10219.0,
      9.1,
      12,
      10,
      46.0
     ]
    ],
    "nombre": "U-6"
   },
   {
    "poligono": [
     [
      10106.0,
      -4461.7
     ],
     [
      10163.7,
      -4402.0
     ],
     [
      10129.9,
      -4369.3
     ],
     [
      10072.2,
      -4429.0
     ]
    ],
    "alto": 39.2,
    "valvulas": [
     [
      -4419.0,
      10118.0,
      9.2,
      8,
      7,
      46.0
     ],
     [
      -4408.5,
      10115.7,
      7.7,
      8,
      6,
      46.0
     ],
     [
      -4410.4,
      10126.3,
      8.6,
      8,
      7,
      46.0
     ],
     [
      -4425.2,
      10128.7,
      6.7,
      10,
      10,
      46.0
     ]
    ],
    "nombre": "U-7"
   },
   {
    "poligono": [
     [
      10075.5,
      -4493.3
     ],
     [
      10096.3,
      -4471.8
     ],
     [
      10079.8,
      -4455.8
     ],
     [
      10058.9,
      -4477.4
     ]
    ],
    "alto": 31.9,
    "valvulas": [
     [
      -4480.6,
      10075.2,
      7.0,
      12,
      8,
      46.0
     ],
     [
      -4465.7,
      10077.1,
      7.5,
      14,
      6,
      46.0
     ],
     [
      -4471.9,
      10087.8,
      8.5,
      10,
      7,
      46.0
     ]
    ],
    "nombre": "U-8"
   },
   {
    "poligono": [
     [
      10420.8,
      -4261.0
     ],
     [
      10457.6,
      -4222.9
     ],
     [
      10431.0,
      -4197.2
     ],
     [
      10394.2,
      -4235.3
     ]
    ],
    "alto": 22.7,
    "valvulas": [
     [
      -4229.2,
      10418.1,
      9.0,
      6,
      7,
      46.0
     ],
     [
      -4220.5,
      10430.7,
      8.8,
      8,
      7,
      46.0
     ],
     [
      -4239.6,
      10428.9,
      7.6,
      6,
      8,
      46.0
     ],
     [
      -4216.5,
      10417.9,
      6.6,
      8,
      7,
      46.0
     ]
    ],
    "nombre": "U-9"
   },
   {
    "poligono": [
     [
      10389.3,
      -4240.3
     ],
     [
      10435.8,
      -4192.1
     ],
     [
      10402.0,
      -4159.5
     ],
     [
      10355.5,
      -4207.7
     ]
    ],
    "alto": 38.4,
    "valvulas": [
     [
      -4202.1,
      10392.9,
      8.2,
      12,
      8,
      46.0
     ],
     [
      -4195.8,
      10386.4,
      5.8,
      8,
      6,
      46.0
     ],
     [
      -4206.1,
      10405.7,
      8.9,
      6,
      10,
      46.0
     ],
     [
      -4212.6,
      10399.4,
      7.1,
      6,
      10,
      46.0
     ]
    ],
    "nombre": "U-10"
   },
   {
    "poligono": [
     [
      10616.7,
      -4422.4
     ],
     [
      10681.3,
      -4355.5
     ],
     [
      10627.3,
      -4303.4
     ],
     [
      10562.7,
      -4370.3
     ]
    ],
    "alto": 40.6,
    "valvulas": [
     [
      -4354.3,
      10628.2,
      7.8,
      14,
      7,
      46.0
     ],
     [
      -4371.5,
      10615.8,
      4.5,
      6,
      8,
      46.0
     ],
     [
      -4348.0,
      10621.7,
      8.7,
      12,
      6,
      46.0
     ],
     [
      -4373.2,
      10634.9,
      4.4,
      6,
      10,
      46.0
     ]
    ],
    "nombre": "U-11"
   },
   {
    "poligono": [
     [
      10351.0,
      -4193.6
     ],
     [
      10399.6,
      -4143.3
     ],
     [
      10370.8,
      -4115.5
     ],
     [
      10322.2,
      -4165.8
     ]
    ],
    "alto": 34.5,
    "valvulas": [
     [
      -4155.3,
      10358.8,
      7.9,
      14,
      10,
      46.0
     ],
     [
      -4159.3,
      10371.6,
      7.0,
      12,
      6,
      46.0
     ],
     [
      -4151.3,
      10346.0,
      4.7,
      14,
      6,
      46.0
     ],
     [
      -4170.0,
      10365.4,
      8.5,
      6,
      6,
      46.0
     ]
    ],
    "nombre": "U-12"
   },
   {
    "poligono": [
     [
      10447.6,
      -4179.9
     ],
     [
      10477.5,
      -4149.0
     ],
     [
      10443.7,
      -4116.3
     ],
     [
      10413.8,
      -4147.3
     ]
    ],
    "alto": 39.0,
    "valvulas": [
     [
      -4150.2,
      10447.1,
      6.0,
      10,
      6,
      46.0
     ],
     [
      -4148.3,
      10436.5,
      6.5,
      6,
      8,
      46.0
     ],
     [
      -4154.3,
      10455.7,
      8.4,
      8,
      7,
      46.0
     ],
     [
      -4137.3,
      10455.4,
      7.7,
      8,
      6,
      46.0
     ]
    ],
    "nombre": "U-13"
   },
   {
    "poligono": [
     [
      10477.5,
      -4149.0
     ],
     [
      10505.3,
      -4120.2
     ],
     [
      10469.3,
      -4085.5
     ],
     [
      10441.5,
      -4114.2
     ]
    ],
    "alto": 27.2,
    "valvulas": [
     [
      -4119.4,
      10468.5,
      7.4,
      6,
      8,
      46.0
     ],
     [
      -4110.9,
      10472.6,
      8.8,
      6,
      8,
      46.0
     ],
     [
      -4129.8,
      10479.3,
      7.6,
      10,
      10,
      46.0
     ],
     [
      -4117.5,
      10457.9,
      7.7,
      12,
      6,
      46.0
     ]
    ],
    "nombre": "U-14"
   },
   {
    "poligono": [
     [
      10399.6,
      -4143.3
     ],
     [
      10434.4,
      -4107.3
     ],
     [
      10376.8,
      -4051.7
     ],
     [
      10342.1,
      -4087.7
     ]
    ],
    "alto": 35.5,
    "valvulas": [
     [
      -4098.8,
      10392.5,
      6.4,
      6,
      8,
      46.0
     ],
     [
      -4105.3,
      10386.2,
      6.9,
      8,
      10,
      46.0
     ],
     [
      -4086.2,
      10388.0,
      5.3,
      6,
      7,
      46.0
     ],
     [
      -4094.9,
      10375.4,
      6.3,
      14,
      6,
      46.0
     ]
    ],
    "nombre": "U-15"
   },
   {
    "poligono": [
     [
      9948.9,
      -4574.0
     ],
     [
      9971.8,
      -4550.3
     ],
     [
      9950.2,
      -4529.5
     ],
     [
      9927.3,
      -4553.2
     ]
    ],
    "alto": 26.2,
    "valvulas": [
     [
      -4540.1,
      9948.3,
      8.2,
      14,
      8,
      46.0
     ]
    ],
    "nombre": "U-16"
   },
   {
    "poligono": [
     [
      9916.0,
      -4514.5
     ],
     [
      9952.8,
      -4476.4
     ],
     [
      9926.2,
      -4450.7
     ],
     [
      9889.4,
      -4488.8
     ]
    ],
    "alto": 26.0,
    "valvulas": [
     [
      -4482.8,
      9909.1,
      6.4,
      10,
      6,
      46.0
     ],
     [
      -4495.5,
      9913.5,
      7.2,
      10,
      10,
      46.0
     ],
     [
      -4484.4,
      9936.7,
      4.7,
      6,
      10,
      46.0
     ],
     [
      -4467.5,
      9932.2,
      6.0,
      8,
      8,
      46.0
     ]
    ],
    "nombre": "U-17"
   }
  ],
  "antorcha": {
   "n": 10472.2,
   "e": -4574.8,
   "alto": 62,
   "radio": 1.8
  },
  "chimeneas": [
   {
    "n": 10404.7,
    "e": -4516.6,
    "alto": 55,
    "radio": 1.6
   },
   {
    "n": 9728.3,
    "e": -4662.8,
    "alto": 46,
    "radio": 1.5
   },
   {
    "n": 9869.2,
    "e": -4548.6,
    "alto": 38,
    "radio": 1.3
   }
  ],
  "atex": 30,
  "sobre_unidades": 10,
  "dist_caliente": 15,
  "dist_fuga": 45,
  "medir_s": 3,
  "placa": {
   "altura": 60,
   "distancia": 50,
   "zoom": 28
  },
  "limite_s": 1800,
  "sin_arboles": [
   [
    10317.0,
    -4515.8
   ],
   [
    10317.0,
    -4465.8
   ],
   [
    10367.0,
    -4465.8
   ],
   [
    10367.0,
    -4515.8
   ]
  ]
 }
};
