# Carpeta de aviones

Cada avión del simulador es un fichero `.js` de esta carpeta que se registra solo:

```js
Modelos.registrar({ id: "E1", nombre: "Entrenador E1", ... });
```

## Añadir un avión

1. Genera su fichero con el script de exportación de su proyecto (para el E1, `scripts/modelo_aero_e1.py`; para el E2, el mismo script con la variable de entorno `ENTRENADOR=E2`) o cópialo aquí.
2. **Con el servidor del aula**, no hace falta nada más: el servidor lee esta carpeta cada vez que se abre el simulador y el avión aparece en la pantalla de elegir avión.
3. **Sin servidor** (abriendo `simulador.html` con doble clic), añade el nombre del fichero a `indice.js`. El script de exportación ya lo hace.

## Qué tiene que traer el modelo

Son los mismos campos que `E1.js`. Todos salen del análisis del avión, no se escriben a mano:

| Campo | Qué es |
|---|---|
| `id`, `nombre`, `descripcion`, `caracteristicas` | Identificación y la ficha que se ve al elegirlo |
| `S_m2`, `b_m`, `c_m`, `masa_kg`, `cg_mm`, `inercia` | Superficie, envergadura, cuerda, masa, centro de gravedad e inercias (kg·m²) |
| `tabla_alfa` | CL, CDi y Cm según el ángulo de ataque (del VLM) |
| `derivadas` | Derivadas de estabilidad y de mando en varios ángulos de ataque, por radián: `CLq Cmq CYb Clb Cnb CYp Clp Cnp CYr Clr Cnr CLde Cmde CYdr Cldr Cndr` |
| `CD0`, `perdida` | Resistencia parásita y modelo de pérdida |
| `propulsion` | Hélice y motor: `T = CT0 (1 − J/J0) ρ n² D⁴` |
| `mandos` | Recorridos (`prof_max_grados`, `timon_max_grados` y, si tiene alerones, `aleron_max_grados`), exponencial, servos y `izq_der` (qué mueven las flechas ← →, para la ayuda) |
| `lanzamiento` | Velocidad y cabeceo del lanzamiento a mano |
| `malla` | Malla 3D ligera (ejes cuerpo, metros, origen en el CG) con las bisagras de los mandos. `timon` es opcional; `alerones` (opcional) es una lista de mallas con `bisagra`, `eje` y `signo`, y el visor las gira `signo · da` sobre su eje |
| `ayuda` (opcional) | Frase de la ayuda en vuelo sobre cómo se pilota |
| `colores` (opcional) | `{ fuselaje, ala, estab, moviles }` en hexadecimal |

## Un avión con otra física

Si un avión necesita mandos o efectos que `ModeloAvion` no tiene (alerones, flaps, cola en V…), su fichero puede traer una subclase y registrarla con los datos. Lo normal es redefinir `servos()` (palanca → superficies) y `mandosCoef()` (aportación de las superficies a CL, CY, Cl, Cm y Cn, que `paso()` suma al resto), y `paso()` entero solo si hace falta otra física:

```js
class ModeloConAlerones extends ModeloAvion {
  estadoInicial() { const av = super.estadoInicial(); av.da = 0; return av; }
  servos(av, mando, dt) { /* ... */ }
  mandosCoef(av, d, kman) { /* ... */ }
}
Modelos.registrar({ ... }, ModeloConAlerones);
```

Así está hecho el E2 (`E2.js`, con la clase `ModeloE2` que sale de `scripts/clase_e2.js`): las flechas ← → mueven los alerones (`da`, con `Clda`, `Cnda` y `CYda` del VLM) y el timón no existe.
