# UxS Trainer en Docker (nginx con HTTPS + aula)

Despliegue del simulador web y del servidor del aula en dos contenedores, para un servidor Ubuntu del centro. Es la
alternativa a `DESPLEGAR_UBUNTU.sh`, que los instala como servicios de systemd sin cifrar en los puertos 80 y 8080.

| Contenedor | Imagen | Qué hace |
|---|---|---|
| `web` | `nginx:1.27-alpine` + `nginx/` | HTTPS en el 443 (el 80 redirige). Sirve el simulador web (`simulador_web/`) y los datos comunes (`datos/`, con las zonas de detalle montadas desde `../datos/escenarios/zonas`). Pasa al aula `/api/`, `/profesor.html` y `/espectador.html`. En el 8080, el aula sin cifrar para Godot y las gafas. |
| `aula` | `python:3.12-slim` + `aula/` | `aula/servidor_aula.py --detras-de-proxy`. No se publica: solo lo ve el nginx. Base de datos, copias y registros en el volumen `aula_datos`. |

## Preparar

En el servidor, con el repositorio clonado:

```bash
cd uxs-trainer/Docker_web
./PREPARAR.sh
```

Instala Docker si falta, pregunta la IP o nombre del servidor y el PIN del profesor (los guarda en `.env`, que no va a
git), baja las zonas de detalle y arranca. Sin preguntas:
`UXS_HOST=192.168.1.20 UXS_PIN_PROFESOR=123456 ./PREPARAR.sh`.

Después:

- Alumnos: `https://IP/` (la pantalla de acceso ya trae puesta el aula; el registro de alumnos nuevos, igual).
- Profesor: `https://IP/profesor.html`.
- Simulador de Godot y gafas: `http://IP:8080` en «Servidor del aula».

## Actualizar

```bash
git pull
./Docker_web/PREPARAR.sh
```

Reconstruye las imágenes y reinicia. No toca `.env`, la base de datos ni el certificado.

## El certificado

La primera vez el nginx crea uno autofirmado para `UXS_HOST`, válido 10 años. El navegador avisa la primera vez en
cada ordenador: Avanzado, y luego Continuar.

Para uno de verdad (de la Consejería o de Let's Encrypt, con un nombre DNS), copiadlo al volumen y reiniciad:

```bash
docker compose cp mi.crt web:/certs/uxs.crt
docker compose cp mi.key web:/certs/uxs.key
docker compose restart web
```

`uxs.crt` lleva la cadena completa. Con un certificado de verdad, Godot y las gafas también pueden usar `https://`, y
se puede quitar el puerto 8080 de `docker-compose.yml`.

Si cambia la IP del servidor, borrad el certificado autofirmado para que se cree otro:

```bash
docker compose exec web rm /certs/uxs.crt
docker compose restart web
```

## Por qué el 8080 sin cifrar

El simulador de Godot y las gafas no aceptan un certificado autofirmado, así que hablan con el aula por HTTP, como con
`SERVIDOR_AULA`. El navegador no puede usarlo desde la página HTTPS, y no hace falta: usa `https://IP/api/`. Si no hay
Godot ni gafas en el aula, quitad la línea `"${PUERTO_AULA:-8080}:8080"`.

## Tareas habituales

Todas desde `Docker_web/`. Sin estar en el grupo `docker`, anteponed `sudo`.

| Qué | Cómo |
|---|---|
| Ver registros | `docker compose logs -f` |
| Parar o arrancar | `docker compose down` / `docker compose up -d` |
| Cambiar el PIN | En el panel del profesor, o `docker compose exec -it aula python aula/servidor_aula.py --datos /datos --cambiar-pin` |
| Copia de la base de datos | `docker compose cp aula:/datos/aula.db ./aula_copia.db` (además, el aula hace sus copias en `/datos/copias`) |
| Otros puertos | `PUERTO_HTTP`, `PUERTO_HTTPS` y `PUERTO_AULA` en `.env` |

`UXS_PIN_PROFESOR` solo vale la primera vez, con la base de datos vacía. Después manda el que se ponga en el panel.

## Venir de la instalación de siempre

Si en el servidor estaba el aula con `DESPLEGAR_UBUNTU.sh` (servicios `uxs-aula` y `uxs-web`, en los mismos puertos),
`PREPARAR.sh` lo hace solo:

- para y quita esos servicios;
- trae a Docker los datos de `aula/datos`: alumnos, vuelos, el PIN, el certificado, copias y registros (allí quedan
  como copia);
- no pregunta el PIN, porque ya viene en esos datos.

Si el aula de Docker ya tiene datos, no los toca.
