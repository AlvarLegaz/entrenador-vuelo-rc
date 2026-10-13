// Elementos singulares de los mundos reales que no salen de los datos abiertos (Catastro, ortofoto): modelados a mano a
// partir de fotos y de la ortofoto a 0,25 m, COMUNES a la version web (visor_real.js, _singulares) y a la de Godot
// (mundo_3d.gd, _singulares). JSON estricto dentro de una asignacion: Godot lee lo que va detras de la asignacion de
// abajo. Coordenadas N, E en metros del plano del mundo (las de sus zonas); alturas en metros sobre el suelo del punto.
// Piezas:
//   muro       {e0, n0, e1, n1, alto, grosor, textura: "bloque"|"hormigon"}  pared recta de (e0, n0) a (e1, n1)
//   cilindro   {e, n, radio, alto, textura: "bloque"|"hormigon"|"sillar"|"linterna"}
//   disco      {e, n, h, radio, rumbo, textura: "rejilla"}                    disco vertical cuya cara mira a "rumbo"
//   cartel     {e, n, h, ancho, alto, rumbo, lineas: [[texto, color, tam]], icono}   panel vertical (cara hacia "rumbo")
//   marquesina {e0, n0, e1, n1, h, vuelo}                                     cubierta metalica sobre pilares
//   submarino  {e, n, largo, radio, rumbo, peana}                              replica del submarino Peral sobre peana
//   mastil     {e, n, alto, bandera: "es"|"ue"|"murcia"}
// El rumbo es el de la direccion hacia la que mira la cara (0 norte, 90 este, 270 oeste).
window.SINGULARES = [
 {
  "mundo": "cartagena",
  "nombre": "Entrada del CIFP Politécnico",
  "nota": "Fachada de la calle Grecia, 56: muro de bloque de hormigón con el cartel, el cilindro de la esquina, la ventana redonda, la marquesina metálica, la réplica del submarino Peral y las banderas (fotos del centro y ortofoto PNOA a 0,25 m).",
  "piezas": [
   {"tipo": "muro", "e0": 6706.4, "n0": 61.6, "e1": 6706.4, "n1": 73.6, "alto": 8.6, "grosor": 0.5, "textura": "bloque"},
   {"tipo": "muro", "e0": 6706.4, "n0": 73.6, "e1": 6717.9, "n1": 74.0, "alto": 8.6, "grosor": 0.5, "textura": "bloque"},
   {"tipo": "cilindro", "e": 6707.9, "n": 60.6, "radio": 1.7, "alto": 10.4, "textura": "hormigon"},
   {"tipo": "disco", "e": 6706.1, "n": 70.9, "h": 3.9, "radio": 1.15, "rumbo": 270, "textura": "rejilla"},
   {"tipo": "cartel", "e": 6706.05, "n": 66.4, "h": 6.25, "ancho": 7.6, "alto": 3.0, "rumbo": 270,
    "lineas": [["CIFP", "#ffffff", 0.62], ["POLITÉCNICO", "#f28a2e", 0.62], ["c a r t a g e n a", "#ffffff", 0.36]], "icono": "engranaje"},
   {"tipo": "marquesina", "e0": 6702.6, "n0": 73.8, "e1": 6713.0, "n1": 78.6, "h": 7.9, "vuelo": 1.5},
   {"tipo": "submarino", "e": 6699.6, "n": 66.0, "largo": 6.2, "radio": 0.55, "rumbo": 0, "peana": 0.75},
   {"tipo": "mastil", "e": 6704.0, "n": 64.6, "alto": 7.0, "bandera": "ue"},
   {"tipo": "mastil", "e": 6704.2, "n": 61.4, "alto": 7.0, "bandera": "es"},
   {"tipo": "mastil", "e": 6704.4, "n": 58.4, "alto": 7.0, "bandera": "murcia"}
  ]
 },
 {
  "mundo": "cartagena",
  "nombre": "Faro de Cabo de Palos",
  "nota": "Torre de piedra de 51 m sobre el cabo (1865), en el centro de la casa del farero: es la planta redonda de 3,5 m de radio del Catastro, que solo trae la casa, de 3 plantas.",
  "piezas": [
   {"tipo": "cilindro", "e": 31713.7, "n": 2424.0, "radio": 3.4, "alto": 45.5, "textura": "sillar"},
   {"tipo": "cilindro", "e": 31713.7, "n": 2424.0, "radio": 3.7, "alto": 46.2, "textura": "sillar"},
   {"tipo": "cilindro", "e": 31713.7, "n": 2424.0, "radio": 2.1, "alto": 50, "textura": "linterna"},
   {"tipo": "cilindro", "e": 31713.7, "n": 2424.0, "radio": 1.1, "alto": 51, "textura": "hormigon"}
  ]
 }
];
