#!/bin/sh
# Al arrancar el nginx (lo ejecuta el entrypoint de la imagen oficial): si no hay certificado en /certs, crea uno
# autofirmado de 10 anos para UXS_HOST (IP o nombre del servidor) y localhost. Para uno de verdad, copiad uxs.crt (con
# la cadena completa) y uxs.key en el volumen "certificados" y reiniciad (ver LEEME.md).
set -e
CRT=/certs/uxs.crt; KEY=/certs/uxs.key
[ -s "$CRT" ] && [ -s "$KEY" ] && { echo "certificado: $CRT"; exit 0; }
H="${UXS_HOST:-localhost}"
if echo "$H" | grep -Eq '^[0-9]+(\.[0-9]+){3}$'; then SAN="IP:$H,DNS:localhost,IP:127.0.0.1"; else SAN="DNS:$H,DNS:localhost,IP:127.0.0.1"; fi
mkdir -p /certs
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -keyout "$KEY" -out "$CRT" \
  -subj "/CN=$H/O=UxS Trainer" -addext "subjectAltName=$SAN" -addext "basicConstraints=critical,CA:FALSE" \
  -addext "extendedKeyUsage=serverAuth" 2>/dev/null
chmod 600 "$KEY"
echo "certificado autofirmado nuevo para $H ($SAN): el navegador avisara la primera vez"
