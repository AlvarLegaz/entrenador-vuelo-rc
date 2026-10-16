#!/usr/bin/env bash
# Sirve el simulador web (carpeta simulador) para que los alumnos lo abran en su navegador desde otro ordenador:
#   http://IP-de-este-ordenador  (puerto 80, el de la web: no hace falta escribirlo; index.html lleva a simulador.html)
# Lo mismo que SERVIDOR_WEB.bat en Windows. El servidor solo entrega los ficheros: la fisica, el 3D y la evaluacion las
# hace el navegador de cada alumno, en su PC. Es aparte del servidor del aula (SERVIDOR_AULA.sh, puerto 8080), que
# guarda perfiles, vuelos y salas: el simulador servido asi busca el aula en este mismo ordenador, puerto 8080, si el
# alumno no ha escrito otra direccion. Se para con Ctrl+C.
#   sudo ./SERVIDOR_WEB.sh        puerto 80 (en Linux, los puertos por debajo del 1024 piden sudo)
#   ./SERVIDOR_WEB.sh 8000        otro puerto, sin sudo (y se abre con http://IP-de-este-ordenador:8000)
# Para dejarlo siempre en marcha (arranca solo con el ordenador, sin sudo cada vez): DESPLEGAR_UBUNTU.sh
cd "$(dirname "$0")" || exit 1
if ! command -v python3 >/dev/null 2>&1; then
  echo "No encuentro Python 3. En Ubuntu: sudo apt install python3"
  exit 1
fi
PUERTO="${1:-80}"
if [ "$PUERTO" -lt 1024 ] && [ "$(id -u)" -ne 0 ]; then
  echo "En Linux el puerto $PUERTO necesita permisos de administrador: sudo $0 $PUERTO"
  echo "o usa otro puerto sin sudo: $0 8000"
  exit 1
fi
DIR=":$PUERTO"; [ "$PUERTO" = "80" ] && DIR=""
echo "Simulador web en http://localhost$DIR y, desde los demas ordenadores, http://IP-de-este$DIR con esta IP:"
for ip in $(hostname -I 2>/dev/null); do case "$ip" in *:*) ;; *) echo "   http://$ip$DIR";; esac; done
if ! python3 -m http.server "$PUERTO" --bind 0.0.0.0 --directory simulador; then
  echo
  echo "No se pudo abrir el puerto $PUERTO: suele ser que otro programa ya lo usa (en el 80, apache2 o nginx)."
  echo "Cierra ese programa o usa otro puerto: $0 8000"
  exit 1
fi
