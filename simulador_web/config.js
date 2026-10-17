// Configuracion del despliegue del simulador web. La carga simulador.html antes que los modulos de js/app/.
// UXS_AULA: la direccion del servidor del aula que sale escrita en la pantalla de acceso si el alumno no ha puesto otra.
//   null: el mismo ordenador que sirve el simulador, en el puerto 8080 (SERVIDOR_WEB + SERVIDOR_AULA, DESPLEGAR_UBUNTU.sh).
// Docker_web sirve en su lugar Docker_web/nginx/config.js: el aula detras del mismo nginx (la misma direccion, con HTTPS).
window.UXS_AULA = null;
