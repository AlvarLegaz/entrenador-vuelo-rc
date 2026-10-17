# Datos comunes (`datos/`)

Los datos que comparten todas las partes: el simulador web, el de Godot, las gafas (van dentro del APK) y el servidor del
aula (logros y panel del profesor). La lógica que los usa está en el código de cada una.

| Carpeta o fichero | Qué hay |
|---|---|
| `vehiculos/` | Un fichero por vehículo e `indice.js` (ver `vehiculos/LEEME.md`). |
| `escenarios/` | Dónde se vuela: `mundos/` (mundo real del Campo de Cartagena y su ortofoto), `zonas/` (zonas de detalle; no van en git, las baja `descargar_zonas.ps1`), `singulares.js` (edificios e instalaciones hechos a mano) y los vuelos libres (`libre.js`, `libre_cartagena.js`). |
| `entrenamientos/` | Un fichero por entrenamiento (`<id>.js`). |
| `operaciones/` | Un fichero por trabajo del modo Operaciones (`<id>.js`) y la imagen de su briefing (`<id>.jpg`). |
| `escenarios.js` | El índice: la lista de los ficheros de entrenamientos, operaciones y vuelos libres, en el orden en el que salen en la app, y qué campos lleva cada escenario. |
| `leer_datos.py` | Para leerlos (y escribirlos, en los generadores de `analisis/`) desde Python. |
| `descargar_zonas.ps1` | Descarga las zonas de detalle de la release del repositorio (lo llaman los `.bat` y `DESCARGAR_ZONAS.sh`). |

Cada escenario es `ESCENARIOS["<id>"] = {...};` con JSON estricto. Para añadir uno: su fichero en `entrenamientos/` u
`operaciones/` y su ruta en la lista de `escenarios.js`, en el sitio donde tiene que salir (o `leer_datos.escribir`).
