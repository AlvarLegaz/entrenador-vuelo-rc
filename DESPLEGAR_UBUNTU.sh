#!/usr/bin/env bash
# Despliega UxS Trainer en un servidor Ubuntu (o Debian) del aula: deja en marcha, como servicios de systemd que
# arrancan solos con el ordenador y se reinician si fallan,
#   - uxs-aula: el servidor del aula (aula/servidor_aula.py, puerto 8080): perfiles, vuelos, panel del profesor y salas;
#   - uxs-web:  el simulador web (carpeta simulador_web y los datos de datos/, puerto 80): los alumnos lo abren con http://IP-del-servidor.
# Antes descarga las zonas de detalle (DESCARGAR_ZONAS.sh) y, si aun no hay PIN del profesor, lo pide aqui (el
# servicio no tiene consola). Los servicios corren con el usuario que lanza el script (no como root) y la base de datos
# se queda en aula/datos, como en Windows. Abre los puertos en el cortafuegos si ufw esta activo.
#   ./DESPLEGAR_UBUNTU.sh                               instala o actualiza (pide la contrasena de sudo)
#   ./DESPLEGAR_UBUNTU.sh --puerto-web 8000 --puerto-aula 8080
#   ./DESPLEGAR_UBUNTU.sh --sin-zonas                   sin descargar las zonas de detalle (unos 330 MB)
#   ./DESPLEGAR_UBUNTU.sh --quitar                      para y borra los dos servicios (no toca los datos)
#   ./DESPLEGAR_UBUNTU.sh --prueba DIR                  no toca el sistema: escribe los servicios en DIR y no usa sudo
# Despues de actualizar el repositorio (git pull), basta con: sudo systemctl restart uxs-aula uxs-web
# Ver lo que pasa: systemctl status uxs-aula  |  journalctl -u uxs-aula -f
set -e
cd "$(dirname "$0")"
DIR_REPO="$(pwd)"
PUERTO_WEB=80; PUERTO_AULA=8080; ZONAS=1; QUITAR=0; PRUEBA=""
while [ $# -gt 0 ]; do
  case "$1" in
    --puerto-web) PUERTO_WEB="$2"; shift 2;;
    --puerto-aula) PUERTO_AULA="$2"; shift 2;;
    --sin-zonas) ZONAS=0; shift;;
    --quitar) QUITAR=1; shift;;
    --prueba) PRUEBA="$2"; shift 2;;
    *) echo "No entiendo $1 (mira la cabecera de este fichero)"; exit 1;;
  esac
done
USUARIO="$(id -un)"
if [ "$(id -u)" -eq 0 ] && [ -z "$PRUEBA" ]; then
  echo "Lanzalo con tu usuario y sin sudo (./DESPLEGAR_UBUNTU.sh): ya pedira la contrasena cuando haga falta. Los"
  echo "servicios corren con ese usuario y la base de datos del aula tiene que ser suya, no de root."; exit 1
fi
if [ -n "$PRUEBA" ]; then SUDO=""; DEST="$PRUEBA"; mkdir -p "$DEST"; else SUDO="sudo"; DEST=/etc/systemd/system; fi
corre() { if [ -n "$PRUEBA" ]; then echo "  (prueba) $*"; else "$@"; fi; }

if [ "$QUITAR" = 1 ]; then
  corre $SUDO systemctl disable --now uxs-aula.service uxs-web.service || true
  corre $SUDO rm -f "$DEST/uxs-aula.service" "$DEST/uxs-web.service"
  corre $SUDO systemctl daemon-reload
  echo "Servicios quitados. Los datos del aula siguen en $DIR_REPO/aula/datos."; exit 0
fi

PY="$(command -v python3 || true)"
if [ -z "$PY" ]; then echo "Falta Python 3: sudo apt install python3"; exit 1; fi
if ! "$PY" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 8) else 1)'; then echo "Hace falta Python 3.8 o posterior"; exit 1; fi

# 1. zonas de detalle
if [ "$ZONAS" = 1 ]; then bash ./DESCARGAR_ZONAS.sh || echo "Sigo sin las zonas de detalle (el simulador funciona igual, con menos detalle)."; fi

# 2. PIN del profesor (con consola, una sola vez)
TIENE_PIN="$("$PY" - <<'FIN'
import sys; sys.path.insert(0, "aula"); import servidor_aula as sa
sa.crear_bd(); con = sa.conectar(); print("si" if sa.config(con, "pin") else "no")
FIN
)"
if [ "$TIENE_PIN" != "si" ]; then
  if [ -n "$PRUEBA" ]; then echo "  (prueba) falta el PIN del profesor: aqui se pediria con aula/servidor_aula.py --cambiar-pin"
  else "$PY" aula/servidor_aula.py --cambiar-pin; fi
fi

# 3. servicios de systemd
unidad() {   # nombre descripcion orden [extra]
  cat <<FIN | $SUDO tee "$DEST/$1.service" >/dev/null
[Unit]
Description=$2
After=network-online.target
Wants=network-online.target

[Service]
User=$USUARIO
WorkingDirectory=$DIR_REPO
ExecStart=$3
Restart=on-failure
RestartSec=3
Environment=PYTHONUNBUFFERED=1
$4

[Install]
WantedBy=multi-user.target
FIN
}
# el aula hace una copia de la base de datos al cerrar (con Ctrl+C): SIGINT en vez de SIGTERM para que la haga
unidad uxs-aula "UxS Trainer - servidor del aula (puerto $PUERTO_AULA)" "$PY $DIR_REPO/aula/servidor_aula.py --puerto $PUERTO_AULA" "KillSignal=SIGINT"
# la web en el puerto 80 sin ser root: solo el permiso de abrir puertos bajos
unidad uxs-web "UxS Trainer - simulador web (puerto $PUERTO_WEB)" "$PY $DIR_REPO/simulador_web/servidor_web.py $PUERTO_WEB" "AmbientCapabilities=CAP_NET_BIND_SERVICE"
corre $SUDO systemctl daemon-reload
corre $SUDO systemctl enable uxs-aula.service uxs-web.service
corre $SUDO systemctl restart uxs-aula.service uxs-web.service

# 4. cortafuegos
if command -v ufw >/dev/null 2>&1 && $SUDO ufw status 2>/dev/null | grep -q "Status: active"; then
  corre $SUDO ufw allow "$PUERTO_WEB/tcp"; corre $SUDO ufw allow "$PUERTO_AULA/tcp"
fi

DIRW=":$PUERTO_WEB"; [ "$PUERTO_WEB" = "80" ] && DIRW=""
echo
echo "UxS Trainer desplegado. Desde los ordenadores del aula:"
for ip in $(hostname -I 2>/dev/null); do case "$ip" in *:*) ;; *)
  echo "   Simulador:               http://$ip$DIRW"
  echo "   Aula (en la pantalla de acceso del simulador): http://$ip:$PUERTO_AULA"
  echo "   Panel del profesor:      http://$ip:$PUERTO_AULA/profesor.html";; esac; done
echo "Estado: systemctl status uxs-aula uxs-web   ·   Quitar: ./DESPLEGAR_UBUNTU.sh --quitar"
