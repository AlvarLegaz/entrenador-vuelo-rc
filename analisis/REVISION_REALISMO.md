# Revisión del realismo de la simulación de vuelo (2026-10-11)

Revisión del modelo físico del simulador (`simulador/js/modelos.js`, `entorno.js`) y de los cuatro aviones (E1, E2, E3, T1), con pruebas numéricas ejecutadas en la misma física que usa el simulador, sin viento. Objetivo: que lo que se entrena en el simulador sea lo que va a pasar en el primer y único vuelo real.

## Qué está bien

- **Integración.** 6 grados de libertad con cuaterniones a 500 Hz. Al dividir el paso entre cuatro, el planeo cambia menos de 5 mm/s: el paso no introduce error apreciable.
- **Aerodinámica de base.** Coeficientes y derivadas de estabilidad salen de un VLM con la geometría real de cada avión, con correcciones de fuselaje de manual (Raymer/DATCOM). Las inercias salen de las mallas de las piezas.
- **Centro de gravedad y peso.** Cambiarlos en la pantalla del avión traslada los momentos al CG nuevo, como en el avión real.
- **Servos.** Retardo de 0,06 s y velocidad máxima de 300–400 °/s, valores de un servo de 9 g.

## Medidas de los cuatro aviones

| | E1 | E2 | E3 | T1 |
|---|---|---|---|---|
| Masa / carga alar | 895 g / 41 g/dm² | 903 g / 42 | 903 g / 42 | 680 g / 63 |
| Vuelo nivelado | 9,5 m/s al 57 % | 9,4 m/s al 56 % | 9,4 m/s al 56 % | 13,5 m/s al 72 % |
| Planeo sin motor | 9,4 m/s, −0,96 m/s, L/D 9,8 | 9,4 m/s, −0,76 m/s, L/D 12,4 | 9,3 m/s, −0,80 m/s, L/D 11,6 | 13,6 m/s, −2,4 m/s, L/D 5,6 |
| Velocidad máxima nivelado | 17 m/s | 17 m/s | 17 m/s | 18,5 m/s |
| Fugoide (periodo, amortiguamiento) | 5,6 s, **−0,03** | 5,4 s, 0,03 | — | 7,3 s, 0,15 |
| Balanceo holandés | 1,4 s, 0,14 | 1,8 s, 0,12 | 6,6 s, 0,13 | 2,1 s, 0,11 |
| Alabeo, 1 s a tope (recorrido del simulador) | 51° (timón 15°) | 35° (alerón 5°) | 61° (alerón 5°) | 82° (elevón 2,5°) |
| Espiral: 20° de alabeo, manos quietas, 20 s | 5° | 11° | 47° | 34° |
| Pérdida tirando sin motor | 8,8 m/s, ala nivelada | 8,5 m/s, ala nivelada | 8,6 m/s, ala nivelada | 10,3 m/s, ala nivelada |
| Pérdida en viraje (40°, tirar a tope) | sigue a 40°, sin barrena | sigue a 40° | 44° | 46° |

## Hallazgos, de más a menos grave

### Críticos: cambian lo que pasará en el primer vuelo

1. **Se pilotaba solo con teclado, a todo o nada.** Ya resuelto en esta revisión: hay control con mando o emisora RC por USB, proporcional, con palanca derecha para el avión y la izquierda para el gas. Lo que falta es que **los recorridos del simulador sean los mismos que se programen en la emisora**. Ahora el simulador limita los alerones del E2 a 5° y los elevones del T1 a 2,5° de alabeo, pero mecánicamente el avión va a ±15°: en el aire el E2 será unas 3 veces más sensible y el T1 unas 6 veces, salvo que se baje el recorrido con el dual rate. Con mando, el simulador debería usar el recorrido real y la exponencial real.
2. **No hay par del motor.** Con la hélice de 9" a tope, el par de reacción es de 0,16 N·m. En el E2 eso alabea el avión unos 24 °/s si no se corrige (1,6° de alerón para anularlo al lanzar). En el **T1**, con 0,6 m de envergadura e inercia pequeña, son **135–160 °/s**: hacen falta unos 6° de elevón al lanzarlo a tope solo para ir recto. En el simulador sale recto; en la realidad, sin esa corrección, alabea hacia la izquierda nada más soltarlo. Tampoco están el efecto P ni el chorro de la hélice sobre la cola.
3. **La pérdida es siempre simétrica.** Al tirar a tope, el avión baja el morro con las alas niveladas, incluso en un viraje de 40°. Nunca deja caer un ala ni entra en barrena. La causa clásica de accidente en un primer vuelo es justo esa: viraje lento cerca del suelo, se tira, cae un ala. El simulador no lo enseña.
4. **Ayudas que en la realidad no existen.** El zoom automático de la cámara del piloto hace que el avión se vea siempre del mismo tamaño. En la realidad, a 150 m el E2 ocupa medio grado y el T1 un cuarto de grado. Tampoco hay horizonte artificial, GPS ni rótulos. Para entrenar el vuelo real hace falta un modo examen: cámara 1, sin zoom y sin instrumentos.

### Importantes: el simulador es más fácil que la realidad

5. **Planea demasiado.** L/D de 10 a 12 y descensos de 0,8–1 m/s en los entrenadores. Un avión impreso con fuselaje de 60 × 72 mm, horns y bisagras a la vista y Re de 1·10⁵ debería estar más cerca de L/D 6–9, con descensos de 1,1–1,6 m/s. Falta la resistencia de perfil que crece con el CL; solo hay CD0 constante más la inducida. Consecuencia: en el simulador las tomas son más largas y un fallo de motor da para llegar más lejos.
6. **Hélice optimista a alta velocidad.** El modelo deja de empujar a 23,9 m/s. Para una APC 9×4,7, cuya velocidad de paso es 17,4 m/s, lo normal es hacia 20 m/s. La velocidad máxima real será algo menor.
7. **Viento simplificado.** Las rachas son iguales en todo el avión, así que la turbulencia nunca lo alabea, que es lo que más se nota en un avión pequeño. No hay gradiente cerca del suelo: a 2 m sopla mucho menos que a 20, y eso cambia la toma. No hay térmicas ni rebufos detrás de árboles y casas.
8. **El lanzamiento a mano es siempre perfecto**: misma velocidad, mismo cabeceo y alas niveladas. Un lanzamiento real varía ±1,5 m/s, ±5° de cabeceo y algo de alabeo.
9. **No hay efecto suelo**, que hace flotar el avión en la recogida.
10. **La fugoide del E1 sale ligeramente inestable** (amortiguamiento −0,03): las oscilaciones de velocidad con las manos quietas crecen despacio. En un entrenador real suele estar algo amortiguada. Se debe en parte a la poca resistencia del punto 5.

### Menores

11. **Densidad del aire fija** (15 °C). En Cartagena, a 30–35 °C, la pérdida sube un 2–3 %.
12. **Batería sin caída de tensión.** Los 840 gf son con la batería cargada; al final del vuelo hay del orden de un 15 % menos.
13. **La masa es una estimación.** La densidad del LW-PLA depende de la temperatura de impresión, entre 0,5 y 0,9 g/cm³, lo que da ±20 % de masa. Hay que pesar las piezas impresas.

Con gas a tope y las manos quietas, el E1 y el E2 hacen rizos seguidos (empuje/peso 0,93 compensado para 9,5 m/s). Es coherente con un entrenador con motor de sobra, pero conviene saberlo: a tope hay que empujar la palanca.

## Estado tras las mejoras (mismo día)

Implementado todo el orden propuesto, salvo cambiar el zoom automático, que se mantiene por decisión del usuario (se puede quitar el horizonte, el GPS y los relojes con la tecla **I**). Detalle de lo que tiene en cuenta la física en el README, sección "Física del simulador".

| | E1 | E2 | E3 | T1 |
|---|---|---|---|---|
| Planeo sin motor | 9,5 m/s, −1,10 m/s, **L/D 8,7** | 9,5 m/s, −1,07 m/s, **L/D 8,9** | 9,5 m/s, −1,07 m/s, **L/D 8,9** | 13,6 m/s, −2,48 m/s, L/D 5,5 |
| Vuelo nivelado | 9,5 m/s al 57 % | 9,5 m/s al 58 % | 9,4 m/s al 57 % | 13,6 m/s al 73 % |
| Lanzado a tope, sin corregir, 1 s | **29° a la izquierda** | **32° a la izquierda** | **22° a la izquierda** | **106° a la izquierda** |
| Gas mínimo para lanzarlo (corrigiendo el alabeo) | 75 % | 55 % | 55 % | 88 % |
| Pérdida recta: caída de ala máxima | 12° | 14° | 122° (espiral) | 114° (espiral) |
| Pérdida en viraje de 40°: alabeo máximo | 40° | 40° | 102° | 137° |
| Fugoide (periodo, amortiguamiento) | — | 5,4 s, 0,06 | 5,4 s, 0,05 | 7,3 s, 0,15 |
| Balanceo holandés | 1,5 s, 0,07 | 1,7 s, 0,08 | 3,3 s, 0,17 | 2,1 s, 0,10 |

- Con diedro (E1, E2), la pérdida recta deja caer el ala 12–14° y se recupera en unos 19 m soltando la profundidad. Sin diedro (E3, T1), el ala cae con fuerza y el avión entra en espiral; el E3 recupera en unos 25 m nivelando y soltando la profundidad.
- El T1 necesita unos 6° de elevón a la derecha al lanzarlo a tope. Con teclado (2,5° de alabeo) no hay recorrido para corregirlo: hay que volarlo con mando o emisora.
- Con viento de 4 m/s con rachas, la turbulencia de alabeo es de unos 4 °/s eficaces en el E2 y 7 °/s en el T1, que es más pequeño.
- La fugoide del E1 ya no es inestable: con la resistencia de perfil y la de la hélice parada queda amortiguada como en los demás.

Sigue pendiente lo que solo se puede saber con el avión construido: masa y CG reales, empuje medido y planeo medido. Hay que meterlos en la pantalla del avión.

## Lo que hay que hacer antes del vuelo real (calibración)

Con un solo intento, el simulador solo puede ser fiel si se alimenta con medidas del avión construido:

1. **Pesar** el avión listo para volar y **medir el CG**. Meter los dos en las barras de la pantalla del avión.
2. **Medir el empuje estático** con una báscula de cocina, con la batería cargada y a media carga. Corregir el empuje del modelo.
3. **Medir los recorridos** de las superficies con un transportador, con el dual rate que se vaya a usar, y poner esos mismos en el simulador.
4. **Hacer planeos a mano sin motor** sobre hierba alta: lanzar con las alas niveladas y medir dónde toca. Sirve para comprobar CG y compensado sin arriesgar el avión, y para ajustar la resistencia del modelo con la distancia de planeo.
5. **Entrenar con la misma emisora** conectada por USB, en modo examen, hasta que el lanzamiento y la toma salgan siempre.

## Orden propuesto de mejoras del modelo

1. Par del motor, efecto P y chorro de la hélice sobre la cola.
2. Pérdida asimétrica por semiala: caída de ala y barrena.
3. Recorridos y exponencial iguales a los de la emisora, y modo examen (sin zoom, sin instrumentos, lanzamiento con dispersión).
4. Resistencia de perfil en función del CL y parámetros de calibración: empuje medido y planeo medido.
5. Gradiente de viento cerca del suelo y turbulencia que alabea.
6. Efecto suelo y densidad del aire según la temperatura.
