#!/usr/bin/env bash
# Descarga las zonas de detalle que no van en el repositorio (La Manga, el Mar Menor y sus islas, la base aerea de San
# Javier, el CIFP Politecnico, Los Halcones de la Rambla, el Mingrano y las plantas fotovoltaicas y la fabrica de SABIC;
# unos 330 MB) para los dos simuladores. Lo mismo que DESCARGAR_ZONAS.bat en Windows: la version, el zip y su huella
# SHA-256 se leen de simulador/descargar_zonas.ps1 (un solo sitio que actualizar con cada release). Sale enseguida si ya
# estan; --forzar las baja otra vez. Necesita curl o wget y Python 3 (para descomprimir; no hace falta unzip).
cd "$(dirname "$0")" || exit 1
PS1=simulador/descargar_zonas.ps1
dato() { sed -n "s/^\$$1 *= *\"\(.*\)\".*/\1/p" "$PS1" | head -1; }
TAG="$(dato TAG)"; ZIP="$(dato ZIP)"; SHA256="$(dato SHA256)"
if [ -z "$TAG" ] || [ -z "$ZIP" ] || [ -z "$SHA256" ]; then echo "No entiendo $PS1 (version, zip o huella)"; exit 1; fi
URL="https://github.com/AlvarLegaz/uxs-trainer/releases/download/$TAG/$ZIP"
MARCA=simulador/zonas/version_zonas.txt
if [ -f "$MARCA" ] && [ "$(tr -d '[:space:]' < "$MARCA")" = "$TAG" ] && [ "$1" != "--forzar" ]; then
  echo "Las zonas de detalle ya estan en simulador/zonas"; exit 0
fi
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
echo "Descargando las zonas de detalle (unos 330 MB, solo la primera vez) de $URL ..."
if command -v curl >/dev/null 2>&1; then curl -fL --retry 3 -o "$TMP/$ZIP" "$URL" || { echo "ERROR: no se pudo descargar"; exit 1; }
elif command -v wget >/dev/null 2>&1; then wget -O "$TMP/$ZIP" "$URL" || { echo "ERROR: no se pudo descargar"; exit 1; }
else echo "Falta curl o wget. En Ubuntu: sudo apt install curl"; exit 1; fi
echo "Comprobando la huella SHA-256 ..."
REAL="$(sha256sum "$TMP/$ZIP" | cut -d' ' -f1)"
if [ "$REAL" != "$SHA256" ]; then echo "ERROR: la huella del zip descargado no coincide: no lo uso"; exit 1; fi
echo "Huella correcta. Descomprimiendo en simulador/zonas ..."
python3 -m zipfile -e "$TMP/$ZIP" simulador || { echo "ERROR: no se pudo descomprimir"; exit 1; }
if [ ! -f "$MARCA" ] || [ "$(tr -d '[:space:]' < "$MARCA")" != "$TAG" ]; then echo "ERROR: el zip no traia las zonas esperadas"; exit 1; fi
echo "Zonas de detalle listas."
