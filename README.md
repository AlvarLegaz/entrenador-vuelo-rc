# Entrenador Vuelo RC

Simulador de vuelo RC para el aula (**Entrenador Vuelo RC**, `simulador/simulador.html`) y los dos aviones de aprendizaje impresos en 3D con los que se entrena, el **Entrenador E1** y el **Entrenador E2**. Repositorio: <https://github.com/AlvarLegaz/entrenador-vuelo-rc>.

Avión de aprendizaje impreso en 3D y simulador de vuelo para entrenar con él en clase. El **Entrenador E1** es un ala alta con poliedro (centro plano y 12° de diedro en las puntas) y solo dos servos, timón y profundidad: el diedro hace que nivele las alas solo cuando se sueltan los mandos. El **Entrenador E2** (más abajo) es la variante con alerones y profundidad, para que los alumnos practiquen también con alerones, y el **Entrenador E3**, el E2 con el ala plana.

![Vistas](ENTRENADOR_E1_vistas.png)

## Datos del E1

| | |
|---|---|
| Envergadura y cuerda | 1200 × 180 mm, rectangular, NACA 2412 (`NACA2412.dat`) |
| Superficie alar | 21,6 dm² |
| Ala | **Poliedro:** plana hasta 300 mm del centro, con un tubo de carbono recto que la atraviesa; las puntas suben 12° desde ese quiebro |
| Masa en vuelo | 895 g (LW-PLA; F1 en PLA normal) |
| Carga alar | 41,4 g/dm² |
| Pérdida / crucero | 7,8 m/s / ≈ 9,5 m/s con la profundidad neutra (calado del estabilizador −1,2°) |
| Motor | SunnySky X2212 KV980, APC 9×4,7, ESC 30 A, 3S 1300 mAh. **Inclinado 2° hacia abajo** (downthrust) con la cuña impresa `CUNA_MOTOR` entre la cruz del motor y la bancada vertical de F1 |
| Centro de gravedad | 248 mm desde la bancada del motor = **63 mm detrás del borde de ataque del ala** (35 % de la cuerda). Margen estático 18 %. El ala va en X 185: con el fuselaje reforzado (pared de 1,6 mm, 4 larguerillos y cuadernas) la cola pesa bastante más, y con el ala en 175 el CG no bajaba del 38 %, donde el simulador entra en pérdidas cada vez más fuertes al cortar gas subiendo |
| Batería | Centrada a unos 56 mm de la bancada, cerca del fondo del morro, entre los dos carriles del suelo de F1 y sujeta con una cinta de velcro de 20 mm que pasa por las ranuras del suelo; el ESC va detrás de ella, en el mismo canal |

Todas las cifras salen de los scripts. Las masas se calculan sobre las mallas de las piezas y el VLM usa la geometría real. La pérdida, la resistencia parásita y el empuje en vuelo son estimaciones hasta calibrarlas con planeos del avión real.

**Motor inclinado y gas.** La línea de empuje pasa 22 mm por debajo del centro de gravedad y la hélice está 259 mm por delante, así que con motor el avión tiende a encabritar. Anularlo del todo pediría unos 5°. Se ha dejado en 2° (la cuña `CUNA_MOTOR`): compensa menos de la mitad del momento del motor y queda una tendencia clara a subir al dar gas, que en un entrenador es lo que se busca: el gas controla la altura. Si se quiere más o menos, basta con reimprimir la cuña con otro ángulo (`DOWNTHRUST` en `parametros_e1.py`) y regenerar. En el simulador, desde un planeo compensado a 9,5 m/s y sin tocar la profundidad, el 60 % de gas da una subida suave de unos 10° de cabeceo. El 100 % sube muy empinado, porque sobra motor (empuje máximo 1,07 veces el peso): se vuela con 50–70 % de gas y el 100 % se deja para el lanzamiento y las subidas.

**Por qué poliedro y no una V en la raíz.** Cada semiala hace palanca en el centro del ala: unos 3,8 N·m a 4 g (lanzamiento fuerte, recogida, ráfaga). Con la V en la raíz, los dos tubos de carbono terminaban en la pieza central y esa palanca la tenía que pasar la pieza impresa. Con el poliedro, el centro lleva un solo tubo recto y el quiebro está donde la palanca es 5 veces menor (0,8 N·m a 4 g). Allí la pasa una llave de tubo de aluminio de 6×4 mm doblada al ángulo del diedro, que aguanta unos 4,2 N·m. Para que el avión se comporte igual que con la V de 8° hacen falta 12° en las puntas: el VLM da el mismo efecto diedro (Cl_β −0,146 frente a −0,138) y la espiral se corrige a la mitad en unos 10 s.

## Piezas del E1 (carpeta `stl/E1/`)

Todas se imprimen sin soportes. Las medidas son las de la orientación de impresión del STL.

| Pieza | Cuántas | Cómo se imprime |
|---|---|---|
| `ALA_C` | 1 | Centro del ala, plano, de −75 a +75 mm, con los **topes** del intradós (ver montaje). De pie |
| `ALA_I_x2` | 2 | Tramo interior de 185 mm (de 75 a 260 mm), de pie. Igual para los dos lados |
| `ALA_Q_izq` | 2 | Pieza del quiebro (de 260 a 340 mm), con el ángulo de 12° y el nervio donde hacen tope los tubos. De pie sobre la cara del lado del centro; **la segunda, en espejo** |
| `ALA_E_x4` | 4 | Tramos exteriores de 130 mm, de pie. Todos iguales |
| `F1` | 1 | Morro con la bancada vertical, los carriles y las ranuras de la batería en el suelo y el agujero del palillo delantero. **PLA normal**, de pie sobre la bancada |
| `CUNA_MOTOR` | 1 | Cuña de 34 × 34 mm (2 → 3,2 mm) que da los 2° de downthrust. **PLA normal**, tumbada sobre su cara plana |
| `F2`–`F5` | 1 de cada | Fuselaje, de pie sobre la cara delantera. El cuello de unión queda arriba. F2 lleva la bandeja de los servos; F3 a F5, las guías de las transmisiones; F5, la deriva con los nudillos de la bisagra del timón |

**Fuselaje reforzado.** Pared de **1,6 mm** (4 líneas de 0,4; con 1 mm salía flojo), **vainas de varilla de carbono en las 4 esquinas** y una **cuaderna a mitad de cada tramo**: un marco de 5 mm de ancho y 2,5 de grueso pegado por dentro a la pared, que ata las cuatro paredes y abraza las vainas (en la cola, más estrecho). Tiene la cara de abajo a 45°, así que se imprime de pie sin soportes. La de F1 no tiene travesaño entre los carriles, para que pase la batería; la de F2 es una U abierta por arriba, porque el techo bajo el ala es la escotilla; las fundas de las transmisiones atraviesan las de F4 y F5 y les sirven de guía. Los cortes están en `E1_fuselaje_secciones.png`.

![Cortes del fuselaje](E1_fuselaje_secciones.png)
| `ESTAB_izq`, `ESTAB_der` | 1 de cada | Estabilizador con los nudillos de la bisagra y el solape a media madera del centro (20 mm: la izquierda lleva la media placa de arriba y la derecha la de abajo). Tumbados |
| `PROF_izq` | 1 | Mitad izquierda de la profundidad, con el horn impreso. Tumbada |
| `PROF_der` | 1 | Mitad derecha de la profundidad. Tumbada |
| `TIMON` | 1 | De pie sobre su canto de abajo, con el horn apoyado en la cama (ponle borde de adherencia) |

Las piezas de ala son cuerpos de pared única con celosía interior. Estabilizador, profundidad y timón van con 2 perímetros, 3 capas arriba y abajo y 10 % de relleno.

**Compras:**
- Tubo de carbono 8×6 mm: 1 de 600 mm (centro) y 2 de 300 mm (puntas).
- Varilla de carbono de 3 mm: 2 de 600 mm (largueros traseros).
- **Varilla de carbono maciza de 4 mm:** 2 trozos de 80 mm, para los palillos de las gomas.
- **Tubo de aluminio de 6×4 mm:** 2 trozos de 100 mm, para las llaves del quiebro. Si no entra en el tubo de carbono, lija un poco.
- Varilla de carbono de 2 mm, unos 80 cm: 2 de 100 mm para unir el estabilizador, 1 de 420 mm de pasador de la profundidad y 1 de 180 mm de pasador del timón.
- **Larguerillos del fuselaje:** varilla de carbono de 2 mm, 6 trozos: abajo, 2 de 154 mm (parte recta, X 215–369) y 2 de 314 mm (parte que se estrecha, X 371–685); arriba, 2 de 296 mm (X 389–685). Unos 7,5 g.
- 2 transmisiones tipo Bowden de 550 mm (funda de 2–3 mm y alambre de 0,8 mm), 2 servos de 9 g y gomas.

**Montaje:**
1. **Fuselaje.** Pega F1 a F5 por sus cuellos (entran 15 mm en el tramo siguiente). Lija el cuello, usa epoxi de 5 min (rellena la holgura mejor que el cianocrilato) y limpia el sobrante. Después da **una vuelta de cinta de fibra de vidrio o kevlar de 20 mm alrededor de cada unión**, pegada con el mismo epoxi: el pegamento del cuello sobra, pero los tramos se imprimen de pie y la pared junto al escalón del cuello es por donde rompería el LW-PLA en un golpe; la cinta lo evita por 2-3 g. Las uniones que más lo agradecen son F1|F2 (el morro, PLA contra LW-PLA) y F2|F3 (bajo el ala, donde el cuello no tiene techo). **Larguerillos:** con los tramos ya pegados y antes de poner los palillos, mete las seis varillas de carbono de 2 mm desde dentro, por la escotilla del ala. Abajo van dos por lado: la de 154 mm en la parte recta y la de 314 mm en la que se estrecha, empujándola hasta F5. Arriba, la de 296 mm de cada lado, que empieza detrás del palillo trasero (X 389): entra en ángulo por la escotilla y se dobla un poco para meterla en su vaina. Fíjalas con unas gotas de cianocrilato fluido en cada extremo y en cada unión. Llevan la tracción en un golpe: el fuselaje se imprime de pie y, al flexionarse, intenta despegar capa de capa, que es como peor aguanta una pieza impresa; con las varillas, para partirlo hay que romper el carbono.
2. **Llaves del quiebro.** Dobla cada tubo de aluminio 12° por el centro, en un tornillo de banco o sobre el canto de una mesa.
3. **Centro del ala.** Mete el tubo de 600 mm por `ALA_C` y los dos `ALA_I`, y una pieza `ALA_Q` en cada extremo, hasta que el tubo haga tope en su nervio. Debajo de `ALA_C` hay cuatro **topes** en cuña, dos por lado (de X 205 a 245 y de 290 a 330), que entran justo por dentro de las pestañas del asiento del fuselaje con 0,3 mm de holgura: el ala no se desliza de lado y, al apoyarla, se centra sola.
4. **Puntas.** Mete la llave de aluminio por el agujero del nervio de `ALA_Q`, 50 mm dentro de cada tubo, y pégala con epoxi. Desliza el tubo de punta de 300 mm sobre la otra mitad de la llave, hasta el nervio. Después monta los dos `ALA_E` de cada lado.
5. **Varillas de 3 mm.** Van partidas en el quiebro: cada trozo hace tope en el nervio de `ALA_Q`.
6. **Pegado del ala.** Pega todos los tramos entre sí por sus caras, del centro hacia las puntas, sobre una mesa plana. Comprueba con una regla que el borde de fuga queda recto.
7. **Estabilizador.** Pasa las dos mitades por la ranura de F5, cada una desde su lado: en el centro encajan por el solape a media madera (la izquierda por encima de la derecha) y las dos varillas de 100 mm atraviesan el solape. Alinéalo con el ala (visto desde atrás y desde arriba) y pega el solape, las varillas y la ranura.
8. **Profundidad.** Pega las dos mitades a tope por el centro. Mete el pasador de 420 mm por los nudillos del estabilizador y el canto de la profundidad, y pégalo **solo a la profundidad**: debe girar libre en los nudillos del estabilizador.
9. **Timón.** Igual, con el pasador vertical de 180 mm: pegado al timón y libre en los nudillos de la deriva.
10. **Servos.** Van de pie en la bandeja de F2, atornillados por sus orejetas: el de la profundidad delante y el del timón detrás.
11. **Motor.** La cruz del X2212 se atornilla a la bancada de F1 con 4 tornillos M3 × 14 y tuercas por dentro (cruz 1,5 + cuña 2-3,2 + placa 4 + tuerca 2,4 mm), con la cuña `CUNA_MOTOR` entre medias (la parte gruesa arriba: así el eje apunta 2° hacia abajo). Los agujeros de la cuña son perpendiculares a su cara inclinada; los de F1, a la placa.
12. **Batería y ESC.** Van en el canal entre los dos carriles del suelo de F1 (37 mm de ancho, de X 8 a 160). La batería se coloca donde diga la tabla de datos de su avión (E1: a unos 56 mm; E2/E3: a unos 94 mm) y se sujeta con una **cinta de velcro de 20 mm** que pasa por dos de las ranuras del suelo (hay una cada 15 mm) y la rodea; el ESC va en el mismo canal (delante de la batería en E2/E3, detrás en E1) sujeto igual o con velcro adhesivo, y las ranuras bajo él hacen de rejilla de ventilación.
11. **Transmisiones.** Las fundas pasan por los anillos guía de F3 a F5:
    - **Profundidad:** sale por el costado izquierdo de F5, por encima del estabilizador, y va al horn de encima de la profundidad.
    - **Timón:** sale por el lomo, a la derecha de la deriva, y va al horn del timón.
    - El horn tiene 3 agujeros para el doblez en Z del alambre: el de abajo da más recorrido.
12. **Ala al fuselaje.** Se sujeta con 4–6 gomas sobre los dos palillos de carbono. Quitando el ala queda abierta la escotilla.
13. **Prueba de los palillos.** Con el ala puesta, tira hacia arriba de un extremo de un palillo con una báscula de equipaje hasta unos 3 kg. No debe crujir nada.

## Regenerar el diseño

Todos los números del diseño están en `scripts/parametros_e1.py`. Después de cambiarlos, ejecuta en orden:

```
python scripts/geom_e1.py          # piezas (scripts/out/stl) y mallas montadas
python scripts/masas_e1.py         # masa, CG, posicion de la bateria, inercias
python analisis/vlm_e1.py 0.895 0.0361 0.0746   # estabilidad y calado del estabilizador (masa, Ixx, Izz)
python scripts/modelo_aero_e1.py   # modelo de vuelo -> simulador/aviones/E1.js
python scripts/vistas_e1.py        # ENTRENADOR_E1_vistas.png
```

## Entrenador E2: alerones y profundidad

La misma célula que el E1 (fuselaje, cola horizontal, motor y batería) con **alerones y profundidad** (2 canales) y la **deriva fija, sin timón**. Sus números están en `scripts/parametros_e2.py`, que solo redefine lo que cambia respecto a `parametros_e1.py`.

![Vistas del E2](ENTRENADOR_E2_vistas.png)

| | |
|---|---|
| Ala | Poliedro: plana hasta 240 mm del centro y **7° de diedro** en las puntas. El quiebro va justo antes del alerón, que queda entero en el panel exterior |
| Alerones | 25 % de la cuerda, de 280 a 570 mm del plano de simetría. **Bisagra de nudillos** con pasador de carbono de 2 mm, que también une los dos tramos de cada alerón. Recorrido mecánico ±15° (comprobado: a ±20° no tocan el ala); en el simulador ±5°, porque con teclado la palanca va siempre a tope |
| Servos | 3 de 9 g: profundidad en la bandeja de F2 y uno por alerón dentro del ala (cajeado abierto por el intradós en el centro de `ALA_E1`) |
| Deriva | Fija, 120 × 145 mm (la parte fija de F5 con el borde de fuga afinado) |
| Masa en vuelo | 903 g; carga alar 41,8 g/dm² |
| Centro de gravedad | 244 mm desde la bancada (33 % de la cuerda). Margen estático 18 % |
| Batería | Centrada a unos 94 mm de la bancada (los servos del ala pesan detrás del CG), entre los carriles del suelo de F1 y con cinta de velcro por las ranuras; el ESC va delante de ella, en el mismo canal, sobre las ranuras que lo ventilan |
| Calado del estabilizador | −0,9° (vuela a ≈ 9,5 m/s con la profundidad neutra) |

**Por qué 7°.** Con poliedro a 240 mm el VLM da: con 6° la espiral se duplica en ~40 s, con 7° se corrige a la mitad en ~90 s (casi neutra, como debe ser un avión de alerones: no vuelve solo al nivel, pero tampoco se cierra en espiral) y con 8° en ~20 s. La guiñada adversa de los alerones es pequeña (Cn_δa / Cl_δa ≈ −0,03). La V de 2,5° en la raíz que tenía antes se cerraba en espiral (doblaba en ~8 s).

**Banco de pruebas del simulador** (física sola, sin viento): lanzado al 75 % de gas sin tocar los mandos sube a 1,6 m/s; planea a 9,9 m/s con 1,1 m/s de descenso; inclinado 30° y soltando los mandos sigue a 12° a los 25 s; un segundo de alerón lo deja a ~21° y se mantiene inclinado.

**Piezas (carpeta `stl/E2/`).** `F1`, `F4`, `ESTAB_izq`/`ESTAB_der` y `PROF_izq`/`PROF_der` son idénticas a las del E1; `F2` (bandeja con un solo servo útil), `F3` y `F5` (deriva fija, solo la salida de la profundidad) cambian. No hay `TIMON`.

| Pieza | Cuántas | Cómo se imprime |
|---|---|---|
| `ALA_C` | 1 | Centro plano, de −75 a +75 mm |
| `ALA_I_x2` | 2 | Tramo interior de 125 mm (de 75 a 200 mm). Igual para los dos lados |
| `ALA_Q_izq` | 2 | Quiebro de 7° (de 200 a 280 mm). **La segunda, en espejo** |
| `ALA_E1_x2` | 2 | Tramo de 140 mm (de 280 a 420) con el corte del alerón, sus nudillos y el cajeado del servo en el centro. Igual para los dos lados |
| `ALA_E2_izq` | 2 | Tramo de punta (de 420 a 600) con el corte del alerón hasta 570. **La segunda, en espejo** |
| `ALERON_A_x2` | 2 | Alerón de 140 mm con la ranura del horn, de pie |
| `ALERON_B_x2` | 2 | Alerón de 150 mm, de pie |

**Compras respecto al E1:**
- 3 servos de 9 g en vez de 2.
- Una sola transmisión Bowden.
- 2 alargadores de cable de servo de 300 mm y un cable en Y: los dos servos de alerón llegan por dentro del ala a la boca de `ALA_C` y se unen en la escotilla; el Y va al receptor, así que al quitar o poner el ala solo hay un conector.
- 2 varillas de empuje cortas con sus horns para los alerones.
- Varilla de carbono de 2 mm: 2 pasadores de 290 mm para los alerones, en vez del pasador del timón.
- Tubo central de 480 mm y 2 tubos de punta de 360 mm, en vez de 600 + 2 × 300 (el quiebro está a 240 mm).

**Montaje (lo que cambia):**
1. **Llaves:** se doblan 7°.
2. **Servos de los alerones:** entran de costado por el intradós de `ALA_E1`, con el brazo hacia abajo y el eje hacia el alerón (varilla corta y recta). El cable va **por dentro del ala**: por la abertura del cajeado entra en el canal de 8 mm (a 69 mm del borde de ataque, entre el tubo y el larguero trasero) que recorre `ALA_E1`, `ALA_Q` (por su nervio), `ALA_I` y `ALA_C`, y sale por la boca del intradós de `ALA_C`, encima de la escotilla. Se enhebra al montar: pasa el cable (o un hilo guía) por cada tramo antes de pegarlo al siguiente.
3. **Alerones:** cada uno se monta con sus dos tramos sobre el pasador de 2 mm, que entra por los nudillos del ala y se pega solo al alerón.
4. **F5:** solo se usa la salida de la profundidad.

**Regenerar el E2:** los mismos scripts, con la variable de entorno `ENTRENADOR=E2` (escriben en `scripts/out_E2/` y en `simulador/aviones/E2.js`):

```
$env:ENTRENADOR = "E2"             # PowerShell (en cmd: set ENTRENADOR=E2)
python scripts/geom_e1.py          # piezas (scripts/out_E2/stl) y mallas montadas
python scripts/masas_e1.py
python analisis/vlm_e1.py 0.903 0.0395 0.0727
python scripts/modelo_aero_e1.py   # -> simulador/aviones/E2.js, con la clase ModeloE2 de scripts/clase_e2.js
python scripts/vistas_e1.py        # ENTRENADOR_E2_vistas.png
```

## Entrenador E3: alerones y profundidad, ala plana

El E2 con el ala **totalmente plana, sin diedro**. Es el paso siguiente para quien ya vuela con alerones: sin diedro el avión no tiende a nivelar las alas y hay que llevarlo siempre con los alerones. Sus números están en `scripts/parametros_e3.py` (solo cambia el diedro respecto al E2).

![Vistas del E3](ENTRENADOR_E3_vistas.png)

**Cómo vuela (VLM y simulador).** Con el ala plana la espiral es inestable: si se inclina el avión y se sueltan los mandos, la inclinación se duplica en unos 4 s según el modelo lineal. En el banco de pruebas del simulador, 10° de inclinación con las manos quietas pasan a 40° en 20 s, mientras el avión baja ganando velocidad. Es lo normal en un avión sin diedro con una deriva grande; el E2, con 7°, es casi neutro. El resto (lanzamiento, planeo a 9,4 m/s con 1,0 m/s de descenso, pérdida a 7,3 m/s, margen estático 18 %, 792 g) es igual que en el E2.

**Piezas (carpeta `stl/E3/`).** Todas son idénticas a las del E2 salvo `ALA_Q_izq`, que sale recta (sin ángulo en el quiebro). La llave de aluminio del quiebro va **sin doblar**. El resto del montaje y las compras, como el E2.

**Regenerar el E3:** los mismos scripts con `ENTRENADOR=E3` (escriben en `scripts/out_E3/` y en `simulador/aviones/E3.js`; el VLM con `python analisis/vlm_e1.py 0.903 0.0394 0.0729`).

## Simulador

`simulador/simulador.html` (Entrenador Vuelo RC). Funciona de tres formas, a elección del usuario:

- **Con el servidor del aula** (lo normal en clase, varios ordenadores). Se eligen alumnos, se guardan todos los vuelos en la base de datos común y el profesor tiene su panel.
- **Registro local**, abriendo `simulador.html` con doble clic y pulsando "Registro local en este ordenador". Alumnos, vuelos y progreso se guardan en el navegador de ese ordenador y, si se quiere, en un **archivo JSON** ("Guardar en un archivo…": en Chrome y Edge el archivo se reescribe solo tras cada vuelo; "Exportar copia" / "Importar copia" valen en cualquier navegador y para llevar el registro a otro ordenador). El progreso se calcula igual que en el servidor; no hay panel del profesor ni autorización de la maqueta real.
- **Volar sin registrar**: sin servidor y sin registro local. Se vuela igual, pero los vuelos no se guardan.

Flujo: elegir alumno → avión y viento (con vista 3D y ficha del avión) → escenario o vuelo libre → volar → resultado APTO / NO APTO guardado → progreso.

**Teclas:**

| Tecla | Qué hace |
|---|---|
| Flechas ↑ ↓ | Profundidad (↓ tira, morro arriba) |
| Flechas ← → | Timón (E1) o alerones (E2 y E3) |
| W / S | Gases |
| Espacio | Cortar gases |
| L | Lanzar |
| R | Empezar de nuevo |
| Esc | Terminar el vuelo |
| 1 / 2 / 3 | Cámaras |
| [ / ] | Compensador |
| T | Ayuda |

**Escenarios** (se evalúan solos):

| Escenario | Para ser APTO |
|---|---|
| 1 · Primer vuelo | Subir a 20 m, dos vueltas al circuito por fuera de los 4 pilones en orden verde → amarillo → rojo → azul y aterrizar sin daños |
| 2 · Orientación | Subir a 20 m y hacer dos ochos (vuelta completa a un lado y luego al otro), sin pasar de 200 m de distancia ni entrar en pérdida, y aterrizar |
| 3 · Viento cruzado | Con 4 m/s del oeste: una vuelta por fuera de los pilones en orden azul → rojo → amarillo → verde (al revés que el primer vuelo) y una toma en la pista, alineada con ella (±25°), sin daños |
| 4 · Emergencia | Subir a 40 m. El motor se para entre 8 y 20 s después: mantener el control sin pérdida y aterrizar a menos de 100 m del piloto |
| 5 · Puerta (zona 2) | Cruzar la puerta naranja 3 veces de lado a lado, por debajo de lo alto de los pilones (20 m), y aterrizar |
| 6 · Pasada baja (zona 2) | Recorrer la pista 2 de punta a punta entre 2 y 8 m, sin tocar ni salirse por los lados: una pasada hacia cada lado |
| 7 · Diana (zona 2) | Aterrizar a menos de 10 m del centro de la diana |
| 8 · Recorrido de precisión (zona 2) | En este orden: pasada baja válida, paso por la puerta y toma a menos de 10 m de la diana |
| Vuelo libre | Sin objetivos; cuenta horas, cronometra las vueltas al circuito y cuenta puertas, pasadas bajas y la toma en la diana |

Los escenarios 1 a 4 (zona 1) son los que cuentan para autorizar la maqueta real; los de la zona 2 son práctica de precisión: se guardan en el historial pero no son requisito.

**El circuito:** 4 pilones hinchables tipo Red Bull en las esquinas de un rectángulo de 120 × 180 m delante del piloto, con la pista dentro (de 40 a 160 m hacia el frente y 90 m a cada lado). Cada pilón es de un color: **verde** delante a la izquierda, **amarillo** al fondo a la izquierda, **rojo** al fondo a la derecha y **azul** delante a la derecha. Una vuelta vale cuando se rodean las 4 esquinas **por fuera**, en el mismo sentido, hasta volver al pilón de salida (se puede salir de cualquiera). Los escenarios fijan el orden de paso (verde → amarillo → rojo → azul es subir por la izquierda y volver por la derecha), y el panel de objetivos muestra el orden y el siguiente pilón; pasar un pilón en sentido contrario no cuenta y anula la vuelta en curso. En vuelo libre vale cualquier sentido. Cortar una esquina por dentro anula la vuelta en curso, y tocar un pilón rompe el avión.

**La zona 2, detrás del piloto:** en sus escenarios el piloto se da la vuelta y se lanza hacia el sur (mejor con viento del sur, para lanzar de cara al viento). Todo va paralelo a la línea del piloto, como en un campo real:
- **Pista 2**: franja de tierra de este a oeste, de 70 × 10 m, a 45 m detrás del piloto. Una pasada baja vale si se entra por una punta, se sale por la otra sin salirse por los lados (5 m de margen) y se mantiene siempre entre 2 y 8 m de altura; cuenta a partir de haber subido a 20 m (el lanzamiento la cruza).
- **Diana**: círculos de cal de 5, 10 y 20 m en el centro de la pista 2, que dan 100, 50 y 20 puntos según dónde toque tierra el avión.
- **Puerta**: dos pilones naranjas separados 16 m, a 130 m del piloto (60 m al este de la pista 2). Se cruza de este a oeste o al revés, por debajo de lo alto de los pilones; por encima o por fuera no cuenta, y tocarlos rompe el avión.
- Alrededor no hay almendros ni estacas, para ver bien la altura.

Un aterrizaje es "sin daños" si desciende a menos de 2,5 m/s, con menos de 30° de alabeo, menos de 25° de cabeceo y menos de 12 m/s respecto al suelo.

**Centro de gravedad y peso.** En la pantalla de elegir avión hay dos barras para mover el centro de gravedad (del 15 al 60 % de la cuerda) y el peso (del 80 al 150 % del de diseño), para aprender sus efectos. Por defecto están en los valores de diseño y el botón "Volver a los valores de diseño" los restaura. Se guardan por avión en el navegador. Debajo se explica el efecto: margen estático y punto neutro, carga alar, velocidad de pérdida y cuánto habría que mover la batería en el avión real. En vuelo, el HUD avisa si no son los de diseño, y el vuelo guardado y la caja negra los anotan. La física traslada los momentos aerodinámicos y los de la hélice al centro de gravedad elegido, y escala las inercias con la masa. Con el E1, en el banco de pruebas: con el CG al 20 % baja el morro y planea a 12–14 m/s; al 45 % sube y baja a tirones entrando en pérdida; detrás del punto neutro (58 %) se estrella 2 s después de lanzarlo.

**Lanzamiento a mano.** Con el avión en la mano, el simulador repite el lanzamiento aparte con la misma física (5 s, sin tocar los mandos, con el viento sin rachas) y, si no saldría, avisa en rojo con el gas mínimo para lanzarlo y, si es por el peso, cuánto lleva de más. Si un lanzamiento acaba en el suelo antes de 6 s sin pasar de 5 m, el vuelo termina como **LANZAMIENTO FALLIDO** con la causa, que se averigua repitiendo la prueba: **poco gas** (con más gas salía; si lleva peso de más, «poco gas para su peso»), **demasiado peso** (no sale ni con todo el gas) o **mandos** (con ese gas salía sin tocarlos: se tiró o se empujó de más, o hubo una racha). No cuenta como aterrizaje; si se rompe, sí como accidente. La tarjeta del centro de gravedad y el peso dice también con cuánto gas sale lanzado a mano. Con los valores de diseño, el E1 y el E2 salen con al menos el 55 % de gas; con 300 g de más, con el 75 %; con el máximo de la barra (150 % del peso), con el 95 %.

**Límites del campo:** a más de 400 m del piloto aparece un aviso en rojo con el rumbo de vuelta; a más de 650 m el avión ya no se distingue y el vuelo termina "fuera de límites" (se guarda como vuelo sin aterrizar; R para empezar de nuevo). Los dos valores están en `Entorno.limites` (`aviso_m`, `distancia_m`). El campo es una isla de ~1,7 km rodeada de mar, solo de decorado.

**Rendimiento:** el visor recorta la vegetación que no está en pantalla y tiene tres niveles de calidad (2: todo; 1: sin vegetación lejana y a 1 píxel por píxel; 0: además sin matas ni nubes, a 3/4 de resolución). Baja solo un nivel si el ordenador no llega a 35 fps durante 3 s, y recuerda el nivel en el navegador (`localStorage` `sim_calidad`; borrarlo o poner `2` para volver a probar el máximo).

**Código:**

| Fichero | Contenido |
|---|---|
| `js/modelos.js` | `Modelos` (carga los aviones de `aviones/`) y `ModeloAvion` (física de 6 grados de libertad; un avión con otros mandos, como el E2, redefine `servos()` y `mandosCoef()`) |
| `js/entorno.js` | `Entorno` (viento y rachas, pista, pilones, zona 2 con su puerta y su diana, reglas del suelo), `ContadorVueltas` (vueltas al circuito por fuera de los pilones) y `PasadaBaja` (pasadas bajas por la pista 2) |
| `js/visor.js` | `Visor` (escena 3D y cámaras) y `VistaPrevia` (el avión girando en la pantalla de elección). El campo está modelado sobre el sitio real (imagen de satélite): bancales de tierra rojiza con almendros, pista de tierra compactada y aparcamiento de grava, la Rambla del Palmeral al este, el cerro de monte bajo al oeste, el cortijo al norte y la AP-7 al noreste; todo ello en una isla de ~1,7 km de radio rodeada de mar (el mundo es finito). Es decorado generado por código (`CAMPO` y `pintarCampo`): la pista, los pilones y las reglas del suelo siguen en `Entorno` |
| `simulador.html` | Pantallas, escenarios, caja negra y bucle |

**Aviones nuevos:** se dejan en `simulador/aviones/` (ver `aviones/LEEME.md`). Con el servidor aparecen solos.

## Servidor del aula

En el ordenador del profesor (Python 3.9 o posterior, sin instalar nada):

```
python aula/servidor_aula.py
```

- **Primera vez:** pide el PIN del profesor. Para cambiarlo después, `python aula/servidor_aula.py --cambiar-pin`.
- **Resto del aula:** el servidor escribe al arrancar la dirección que tienen que abrir los demás ordenadores, por ejemplo `http://192.168.1.20:8080`.
- **Firewall de Windows:** puede pedir permiso para Python la primera vez. Hay que permitirlo en redes privadas.
- **Datos:** `aula/datos/aula.db`, una base de datos SQLite común a todos los ordenadores.
- **Copias de seguridad:** en `aula/datos/copias/`. Se hacen al arrancar, cada hora si hubo cambios, al cerrar y antes de cada borrado definitivo, y se guardan las 60 últimas. Para restaurar una, para el servidor y cópiala encima de `aula.db`.
- **Sin duplicados:** cada vuelo lleva un identificador único. Si se envía dos veces, se guarda una.
- **Sin pérdidas:** si un ordenador pierde la conexión, guarda el vuelo y lo reenvía solo cuando vuelve.

**Lo que puede hacer cada uno:**

- **Alumnos, sin contraseña:** elegirse, darse de alta, quitarse de la lista (con confirmación; solo se archiva y se puede restaurar) y guardar sus vuelos.
- **Profesor, con el botón "Profesor" y el PIN:** editar y borrar alumnos, ver estadísticas e historial completo, exportar a CSV (se abre en Excel), hacer copias y **autorizar la maqueta real**. Solo se puede autorizar con 10 h de vuelo y los 4 escenarios superados. La sesión dura 8 h, y 5 PIN fallidos seguidos bloquean el acceso 2 minutos.

El PIN viaja sin cifrar por la red local del aula: protege frente a los alumnos, no frente a alguien que espíe la red.
