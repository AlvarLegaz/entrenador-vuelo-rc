# El servidor del aula (solo la biblioteca estandar de Python). Se construye desde la raiz del repositorio (ver
# docker-compose.yml): lleva aula/servidor_aula.py y el panel, los datos comunes (sin las zonas de detalle, que no usa)
# y el simulador web (la vista del alumno del panel del profesor, espectador.html).
FROM python:3.12-slim
ENV PYTHONUNBUFFERED=1 PYTHONDONTWRITEBYTECODE=1
RUN useradd --uid 1000 --create-home uxs && mkdir /datos && chown uxs:uxs /datos
WORKDIR /app
COPY aula/servidor_aula.py aula/profesor.html aula/
COPY datos datos
COPY simulador_web simulador_web
USER uxs
VOLUME /datos
EXPOSE 8080
# --detras-de-proxy: la IP de cada alumno la da el nginx (X-Real-IP); el puerto 8080 no se publica fuera
CMD ["python", "aula/servidor_aula.py", "--puerto", "8080", "--datos", "/datos", "--detras-de-proxy"]
