// Configuracion del simulador web en Docker_web (sustituye a simulador_web/config.js): el aula esta detras del mismo
// nginx, en la misma direccion y con HTTPS, asi que la pantalla de acceso ya la trae puesta.
window.UXS_AULA = location.protocol.startsWith("http") ? location.origin : null;
