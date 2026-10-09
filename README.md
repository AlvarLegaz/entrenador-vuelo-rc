# Entrenador Vuelo RC

Simulador de vuelo RC para el aula (**Entrenador Vuelo RC**, `simulador/simulador.html`) y los dos aviones de aprendizaje impresos en 3D con los que se entrena, el **Entrenador E1** y el **Entrenador E2**. Repositorio: <https://github.com/AlvarLegaz/entrenador-vuelo-rc>.

Avión de aprendizaje impreso en 3D y simulador de vuelo para entrenar con él en clase. El avión es un ala alta con 8° de diedro por semiala y solo dos servos, timón y profundidad. El diedro hace que nivele las alas solo cuando se sueltan los mandos. El **Entrenador E2** (más abajo) es la variante con alerones y profundidad, para que los alumnos practiquen también con alerones.

![Vistas](ENTRENADOR_E1_vistas.png)

## Datos del avión

| | |
|---|---|
| Envergadura y cuerda | 1200 × 180 mm, rectangular, NACA 2412 (`NACA2412.dat`) |
| Superficie alar | 21,6 dm² |
| Masa en vuelo | 761 g (LW-PLA; F1 en PLA normal) |
| Carga alar | 35,2 g/dm² |
| Pérdida / crucero | 7,2 m/s / ≈ 9,5 m/s con la profundidad neutra |
| Motor | SunnySky X2212 KV980, APC 9×4,7, ESC 30 A, 3S 1300 mAh |
| Centro de gravedad | 234 mm desde la bancada del motor = **59 mm detrás del borde de ataque del ala** (33 % de la cuerda). Margen estático 22 % |
| Batería | Centrada a unos 47 mm de la bancada, contra el fondo del morro |

Todas las cifras salen de los scripts. Las masas se calculan sobre las mallas de las piezas y el VLM usa la geometría real. La pérdida, la resistencia parásita y el empuje en vuelo son estimaciones hasta calibrarlas con planeos del avión real.

## Piezas (carpeta `stl/`)

Todas se imprimen sin soportes. Las medidas son las de la orientación de impresión del STL.

| Pieza | Cuántas | Cómo se imprime |
|---|---|---|
| `ALA_C` | 1 | Pieza central en V. De pie sobre la cara exterior de una mitad |
| `ALA1a4_x8` | 8 | Tramos de ala de 135 mm, de pie. Son iguales para los dos lados |
| `F1` | 1 | Morro con la bancada. **PLA normal**, de pie sobre la bancada |
| `F2`–`F5` | 1 de cada | Fuselaje, de pie sobre la cara delantera. El cuello de unión queda arriba. F5 lleva la deriva |
| `ESTAB_x2` | 2 | Estabilizador. Tumbado; la segunda, en espejo |
| `PROF_x2` | 2 | Profundidad. Tumbada; las dos son iguales |
| `TIMON` | 1 | De pie sobre el canto de la bisagra |

Las piezas de ala se imprimen como cuerpos de pared única con celosía interior, igual que las del ALFA-T. Estabilizador, profundidad y timón van con 2 perímetros, 3 capas arriba y abajo y 10 % de relleno.

**Compras:** tubo de carbono 8×6 mm (2 × 600 mm), varilla de carbono de 3 mm (2 × 600 mm), varilla de carbono de 2 mm (unos 60 cm: uniones del estabilizador y de la profundidad), 2 transmisiones tipo Bowden de 550 mm, 2 servos de 9 g, 2 horns, cinta para las bisagras, gomas y 2 palillos de bambú de 3 mm.

**Montaje en breve:**
1. Pega los tramos del fuselaje F1 a F5 por sus cuellos.
2. Mete el tubo y la varilla de cada semiala en la pieza central y pega los tramos del ala.
3. Pasa las dos mitades del estabilizador por la ranura de F5, unidas con las varillas de 2 mm.
4. Une las dos mitades de la profundidad con la varilla de 2 mm de la bisagra.
5. Pega los servos al nervio central de F2.
6. Las transmisiones salen por las ranuras de F5: la de la profundidad por la izquierda abajo y la del timón por la derecha arriba.
7. El ala se sujeta con gomas sobre los dos palillos. Quitando el ala queda abierta la escotilla de la batería.

## Regenerar el diseño

Todos los números del diseño están en `scripts/parametros_e1.py`. Después de cambiarlos, ejecuta en orden:

```
python scripts/geom_e1.py          # piezas (scripts/out/stl) y mallas montadas
python scripts/masas_e1.py         # masa, CG, posicion de la bateria, inercias
python analisis/vlm_e1.py 0.761 0.0352 0.0681   # estabilidad y calado del estabilizador (masa, Ixx, Izz)
python scripts/modelo_aero_e1.py   # modelo de vuelo -> simulador/aviones/E1.js
python scripts/vistas_e1.py        # ENTRENADOR_E1_vistas.png
```

## Entrenador E2: alerones y profundidad

La misma célula que el E1 (fuselaje, ala, cola horizontal, motor y batería) con **alerones y profundidad** (2 canales) y la **deriva fija, sin timón**. Como alabean los alerones, lleva mucho menos diedro (5° por semiala) y una deriva más pequeña. Sus números están en `scripts/parametros_e2.py`, que solo redefine lo que cambia respecto a `parametros_e1.py`.

![Vistas del E2](ENTRENADOR_E2_vistas.png)

| | |
|---|---|
| Alerones | 25 % de la cuerda, del 40 al 95 % de la semienvergadura (de 240 a 570 mm del plano de simetría). Bisagra de cinta en el extradós, canto delantero en bisel a 45° por debajo. Recorrido mecánico ±15°; en el simulador ±5°, porque con teclado la palanca va siempre a tope (con 15° un segundo de alerón da la vuelta al avión) |
| Servos | 3 de 9 g: profundidad en F2 y uno por alerón dentro del ala (cajeado de 24 × 25 × 12,5 mm abierto por el intradós en `ALA2`, delante del larguero trasero; el brazo asoma por abajo y una varilla corta va al horn del alerón) |
| Diedro | 5° por semiala |
| Deriva | Fija, 120 × 145 mm (la parte fija de F5 con el borde de fuga afinado y cerrado) |
| Masa en vuelo | 762 g; carga alar 35,3 g/dm² |
| Centro de gravedad | 234 mm desde la bancada (33 % de la cuerda). Margen estático 19 % |
| Batería | Centrada a unos 120 mm de la bancada (los servos del ala pesan detrás del CG y la batería retrasa 7 cm respecto al E1) |
| Calado del estabilizador | −0,4° (vuela a ≈ 9,5 m/s con la profundidad neutra) |
| Pérdida / crucero | 7,2 m/s / ≈ 9,5 m/s |

**Por qué 5° y esa deriva.** El VLM (`analisis/vlm_e1.py` con `ENTRENADOR=E2`) barre el diedro de 0 a 5° y añade la deflexión diferencial de alerones: Cl_δa = 0,47/rad, Cn_δa = −0,015/rad (guiñada adversa del 3 % del momento de alabeo; se corrige sola con el diedro) y CY_δa = 0,11/rad. Con la deriva grande del E1 (170 × 175) la espiral es inestable con cualquier diedro hasta 4° (dobla en 4-12 s). Con la deriva de 120 × 125 y 4° la espiral queda neutra, pero Cn_β cae a 0,020 y el balanceo holandés casi no amortigua: en el banco de pruebas del simulador un segundo de alerón ponía el avión a 30° de resbale. Con 5° y la deriva de 120 × 145 (Cn_β 0,033, Cl_β −0,087) la espiral es neutra (se corrige a la mitad en ~170 s), el holandés amortigua (0,56 Hz, amortiguamiento 0,11) y el resbale al dar alerón baja a 22°. Es un avión que no vuelve solo al nivel: si se sueltan los mandos mantiene el alabeo que tenga, como un avión de alerones normal.

**Banco de pruebas del simulador** (física sola, sin viento, 65 % de gases): lanzado sin tocar los mandos sube como el E1 (9,8 m en 10 s a 9,4 m/s); planea con el motor parado a 9,8 m/s y 0,9 m/s de descenso; un segundo de alerón a tope lo deja a 40° de alabeo (el E1, con un segundo de timón, a 46°) y al soltar mantiene unos 35° mientras el holandés se apaga en 3 s. El E1 da exactamente lo mismo que antes.

**Piezas (carpeta `stl/E2/`).** `F1`, `F4`, `ESTAB_x2` y `PROF_x2` son idénticas a las del E1. Cambian `ALA_C`, `F2` y `F3` (el asiento del ala lleva los 5° de diedro) y `F5` (deriva fija cerrada). No hay `TIMON`.

| Pieza | Cuántas | Cómo se imprime |
|---|---|---|
| `ALA1_x2` | 2 | Tramo liso de 180 mm (de 60 a 240 mm), de pie. Igual para los dos lados |
| `ALA2_x2` | 2 | Tramo de 180 mm con el corte del alerón y el cajeado del servo, de pie. Igual para los dos lados |
| `ALA3_izq` | 2 | Tramo de punta: corte del alerón hasta 150 mm y los 30 mm de la punta enteros. De pie; la derecha, en espejo |
| `ALERON_A_x2` | 2 | Alerón de 180 mm con la ranura del horn, de pie. Igual para los dos lados |
| `ALERON_B_x2` | 2 | Alerón de 150 mm, de pie |

**Compras respecto al E1:** 3 servos de 9 g en vez de 2, una sola transmisión Bowden, 2 alargadores de cable de servo, 2 varillas de empuje cortas con sus horns (3 horns en total) y unos 70 cm más de varilla de carbono de 2 mm (une los dos tramos de cada alerón por el agujero del canto delantero).

**Montaje (lo que cambia):** los tramos del ala van `ALA1`, `ALA2` y `ALA3` desde la pieza central; los servos de los alerones entran de costado por el intradós de `ALA2` con el brazo hacia abajo (cola caliente o cinta) y el cable sale por el cajeado hasta la raíz; cada alerón se monta con los dos tramos sobre la varilla de 2 mm, se articula con cinta por el extradós (el bisel queda abajo) y lleva el horn en la ranura de `ALERON_A`; en F5 solo se usa la ranura de la profundidad (izquierda abajo).

**Regenerar el E2:** los mismos scripts, con la variable de entorno `ENTRENADOR=E2` (escriben en `scripts/out_E2/` y en `simulador/aviones/E2.js`):

```
$env:ENTRENADOR = "E2"             # PowerShell (en cmd: set ENTRENADOR=E2)
python scripts/geom_e1.py          # piezas (scripts/out_E2/stl) y mallas montadas
python scripts/masas_e1.py
python analisis/vlm_e1.py 0.762 0.0373 0.0642
python scripts/modelo_aero_e1.py   # -> simulador/aviones/E2.js, con la clase ModeloE2 de scripts/clase_e2.js
python scripts/vistas_e1.py        # ENTRENADOR_E2_vistas.png
```

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
| Flechas ← → | Timón (E1) o alerones (E2) |
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
| 1 · Primer vuelo | Subir a 20 m, dos vueltas al circuito por fuera de los 4 pilones y aterrizar sin daños |
| 2 · Orientación | Subir a 20 m y hacer dos ochos (vuelta completa a un lado y luego al otro), sin pasar de 200 m de distancia ni entrar en pérdida, y aterrizar |
| 3 · Viento cruzado | Con 4 m/s del oeste: una vuelta por fuera de los pilones y una toma en la pista, alineada con ella (±25°), sin daños |
| 4 · Emergencia | Subir a 40 m. El motor se para entre 8 y 20 s después: mantener el control sin pérdida y aterrizar a menos de 100 m del piloto |
| Vuelo libre | Sin objetivos; cuenta horas y cronometra las vueltas al circuito |

**El circuito:** 4 pilones hinchables tipo Red Bull en las esquinas de un rectángulo de 120 × 180 m delante del piloto, con la pista dentro (de 40 a 160 m hacia el frente y 90 m a cada lado). Una vuelta vale cuando se rodean las 4 esquinas **por fuera**, en el mismo sentido, hasta volver al pilón de salida. Cortar una esquina por dentro anula la vuelta en curso, y tocar un pilón rompe el avión.

Un aterrizaje es "sin daños" si desciende a menos de 2,5 m/s, con menos de 30° de alabeo, menos de 25° de cabeceo y menos de 12 m/s respecto al suelo.

**Límites del campo:** a más de 400 m del piloto aparece un aviso en rojo con el rumbo de vuelta; a más de 650 m el avión ya no se distingue y el vuelo termina "fuera de límites" (se guarda como vuelo sin aterrizar; R para empezar de nuevo). Los dos valores están en `Entorno.limites` (`aviso_m`, `distancia_m`). El campo es una isla de ~1,7 km rodeada de mar, solo de decorado.

**Rendimiento:** el visor recorta la vegetación que no está en pantalla y tiene tres niveles de calidad (2: todo; 1: sin vegetación lejana y a 1 píxel por píxel; 0: además sin matas ni nubes, a 3/4 de resolución). Baja solo un nivel si el ordenador no llega a 35 fps durante 3 s, y recuerda el nivel en el navegador (`localStorage` `sim_calidad`; borrarlo o poner `2` para volver a probar el máximo).

**Código:**

| Fichero | Contenido |
|---|---|
| `js/modelos.js` | `Modelos` (carga los aviones de `aviones/`) y `ModeloAvion` (física de 6 grados de libertad; un avión con otros mandos, como el E2, redefine `servos()` y `mandosCoef()`) |
| `js/entorno.js` | `Entorno` (viento y rachas, pista, pilones, reglas del suelo) y `ContadorVueltas` (vueltas al circuito por fuera de los pilones) |
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
