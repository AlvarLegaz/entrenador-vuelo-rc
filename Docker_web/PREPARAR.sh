#!/usr/bin/env bash
# Prepara y arranca UxS Trainer en Docker (nginx con HTTPS + servidor del aula) en un servidor Ubuntu:
#   1. instala Docker y Docker Compose si faltan (paquetes de Ubuntu: docker.io, docker-compose-v2, docker-buildx)
#   2. escribe .env (IP o nombre del servidor y PIN inicial del profesor) si no existe
#   3. si estaba la instalacion de siempre (DESPLEGAR_UBUNTU.sh: servicios uxs-aula y uxs-web), la para y trae a Docker
#      los datos del aula (aula/datos: base de datos con el PIN, copias y registros), si el aula de Docker aun no tiene
#   4. baja las zonas de detalle (../DESCARGAR_ZONAS.sh, unos 330 MB, solo la primera vez)
#   5. construye las imagenes y arranca (docker compose up -d --build) y comprueba que responde
#
#   ./PREPARAR.sh                 pregunta lo que falte
#   UXS_HOST=192.168.1.20 UXS_PIN_PROFESOR=123456 ./PREPARAR.sh      sin preguntas
#   ./PREPARAR.sh --sin-zonas     no baja las zonas (el simulador va igual, sin el detalle de los mundos reales)
# Para actualizar despues de un git pull, otra vez ./PREPARAR.sh (no toca .env, ni la base de datos, ni el certificado).
set -e
cd "$(dirname "$0")"
SIN_ZONAS=0; [ "$1" = "--sin-zonas" ] && SIN_ZONAS=1
SUDO=""; [ "$(id -u)" = 0 ] || SUDO="sudo"

echo "== 1. Docker"
tiene_docker() { command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; }
if ! tiene_docker; then
  echo "Instalando Docker y Docker Compose (paquetes de Ubuntu) ..."
  $SUDO apt-get update -q
  $SUDO apt-get install -y -q docker.io docker-compose-v2 docker-buildx
  $SUDO systemctl enable --now docker
fi
D="docker"; docker info >/dev/null 2>&1 || D="$SUDO docker"     # sin estar en el grupo docker: con sudo
DC="$D compose"
$DC version
AULA_ANTES="$(cd .. && pwd)/aula/datos"              # los datos de la instalacion de siempre (SERVIDOR_AULA, DESPLEGAR_UBUNTU.sh)

echo "== 2. Configuracion (.env)"
if [ ! -f .env ]; then
  IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
  H="${UXS_HOST:-}"
  if [ -z "$H" ]; then read -r -p "IP o nombre de este servidor (va en el certificado) [${IP:-localhost}]: " H; H="${H:-${IP:-localhost}}"; fi
  P="${UXS_PIN_PROFESOR:-}"
  if [ -z "$P" ] && [ -f "$AULA_ANTES/aula.db" ]; then
    echo "Hay un aula anterior en aula/datos: se traen sus datos y su PIN (no hace falta otro)"; P="-"
  fi
  while [ "$P" != "-" ] && ! echo "$P" | grep -Eq '^[0-9]{4,12}$'; do
    read -r -s -p "PIN del profesor (4 a 12 cifras): " P; echo
    read -r -s -p "Repitelo: " P2; echo
    [ "$P" = "$P2" ] || { echo "  No coinciden."; P=""; continue; }
    echo "$P" | grep -Eq '^[0-9]{4,12}$' || echo "  Tiene que ser de 4 a 12 cifras."
  done
  [ "$P" = "-" ] && P=""
  umask 077
  cat > .env <<EOF
# Configuracion de Docker_web (la escribio PREPARAR.sh). No va en git.
# IP o nombre del servidor: va en el certificado autofirmado (si se cambia, borrad el volumen de certificados).
UXS_HOST=$H
# PIN del profesor SOLO para la primera vez (sin base de datos); luego se cambia en el panel del profesor.
UXS_PIN_PROFESOR=$P
# Puertos publicados en este servidor
PUERTO_HTTP=${PUERTO_HTTP:-80}
PUERTO_HTTPS=${PUERTO_HTTPS:-443}
PUERTO_AULA=${PUERTO_AULA:-8080}
TZ=Europe/Madrid
EOF
  echo ".env escrito"
else
  echo ".env ya existe: no lo toco"
fi
set -a; . ./.env; set +a

echo "== 3. Instalacion de siempre (DESPLEGAR_UBUNTU.sh)"
if systemctl list-unit-files uxs-aula.service uxs-web.service 2>/dev/null | grep -q "^uxs-"; then
  echo "Estan los servicios uxs-aula y uxs-web (en los mismos puertos): se paran y se quitan (los datos se quedan)"
  ../DESPLEGAR_UBUNTU.sh --quitar
fi
$DC build -q
$DC create >/dev/null 2>&1 || true                   # crea los volumenes (sin arrancar)
if [ -f "$AULA_ANTES/aula.db" ]; then
  $D run --rm --user root -v uxs-trainer_aula_datos:/datos -v "$AULA_ANTES":/antes:ro uxs-trainer/aula sh -c     'if [ -f /datos/aula.db ]; then echo "el aula de Docker ya tiene sus datos: no se tocan"; else cp -a /antes/. /datos/ && chown -R 1000:1000 /datos && echo "datos del aula traidos de aula/datos (alli quedan como copia)"; fi'
fi

echo "== 4. Zonas de detalle"
mkdir -p ../datos/escenarios/zonas
if [ "$SIN_ZONAS" = 1 ]; then echo "sin zonas (--sin-zonas)"; else ../DESCARGAR_ZONAS.sh; fi

echo "== 5. Construir y arrancar"
$DC up -d --build
echo "Esperando al aula ..."
for i in $(seq 1 30); do
  c=$(curl -sk -o /dev/null -w "%{http_code}" "https://127.0.0.1:${PUERTO_HTTPS}/api/estado" || true)
  [ "$c" = 200 ] && break; sleep 2
done
if [ "$c" != 200 ]; then echo "ERROR: el aula no responde. Lo ultimo que dijo:"; $DC logs --tail 20 aula; exit 1; fi
$DC ps
for u in "https://127.0.0.1:${PUERTO_HTTPS}/simulador.html" "https://127.0.0.1:${PUERTO_HTTPS}/datos/escenarios.js" \
         "https://127.0.0.1:${PUERTO_HTTPS}/api/estado" "https://127.0.0.1:${PUERTO_HTTPS}/profesor.html" "http://127.0.0.1:${PUERTO_AULA}/api/estado"; do
  echo "$(curl -sk -o /dev/null -w "%{http_code}" "$u") $u"
done
S=""; [ "$PUERTO_HTTPS" = 443 ] || S=":$PUERTO_HTTPS"
echo
echo "UxS Trainer en marcha:"
echo "   Alumnos (navegador):        https://${UXS_HOST}${S}/"
echo "   Panel del profesor:         https://${UXS_HOST}${S}/profesor.html"
echo "   Simulador de Godot y gafas: http://${UXS_HOST}:${PUERTO_AULA}"
echo "El certificado es autofirmado: la primera vez el navegador avisa (Avanzado > Continuar)."
echo "Registros: $DC logs -f    Parar: $DC down    (los datos del aula quedan en el volumen aula_datos)"
