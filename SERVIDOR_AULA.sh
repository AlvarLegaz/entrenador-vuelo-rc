#!/usr/bin/env bash
# Servidor del aula (aula/servidor_aula.py) en este ordenador (Linux, p. ej. Ubuntu): perfiles online, vuelos de todos,
# panel del profesor y salas del multijugador. Lo mismo que SERVIDOR_AULA.bat en Windows. Se para con Ctrl+C.
# Necesita Python 3.9 o posterior (en Ubuntu ya viene: python3). La primera vez pide el PIN del profesor.
#   ./SERVIDOR_AULA.sh                 puerto 8080
#   ./SERVIDOR_AULA.sh --puerto 8000   otro puerto
#   ./SERVIDOR_AULA.sh --cambiar-pin   cambia el PIN del profesor y sale
# Para dejarlo siempre en marcha (arranca solo con el ordenador): DESPLEGAR_UBUNTU.sh
cd "$(dirname "$0")" || exit 1
if ! command -v python3 >/dev/null 2>&1; then
  echo "No encuentro Python 3. En Ubuntu: sudo apt install python3"
  exit 1
fi
exec python3 aula/servidor_aula.py "$@"
