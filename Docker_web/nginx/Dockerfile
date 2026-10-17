# nginx con HTTPS: sirve el simulador web y los datos comunes y pasa al aula /api/, el panel del profesor y la vista
# del alumno. Se construye desde la raiz del repositorio (ver docker-compose.yml). Las zonas de detalle no van en la
# imagen: se montan de ../datos/escenarios/zonas.
FROM nginx:1.27-alpine
RUN apk add --no-cache openssl
COPY Docker_web/nginx/uxs.conf /etc/nginx/templates/default.conf.template
COPY Docker_web/nginx/config.js /etc/nginx/uxs/config.js
COPY Docker_web/nginx/40-certificado.sh /docker-entrypoint.d/40-certificado.sh
RUN chmod 755 /docker-entrypoint.d/40-certificado.sh
COPY simulador_web /srv/uxs/simulador_web
COPY datos /srv/uxs/datos
EXPOSE 80 443 8080
