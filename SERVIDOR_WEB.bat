@echo off
rem Sirve el simulador web (carpeta simulador) para que los alumnos lo abran en su navegador desde otro ordenador:
rem   http://IP-de-este-ordenador  (puerto 80, el de la web: no hace falta escribirlo; index.html lleva a simulador.html)
rem El servidor solo entrega los ficheros: la fisica, el 3D y la evaluacion las hace el navegador de cada alumno, en su
rem PC. Es aparte del servidor del aula (SERVIDOR_AULA.bat, puerto 8080), que guarda perfiles, vuelos y salas: el
rem simulador servido asi busca el aula en este mismo ordenador, puerto 8080, si el alumno no ha escrito otra direccion.
rem Necesita Python 3. Se para cerrando la ventana o con Ctrl+C. Otro puerto: SERVIDOR_WEB.bat 8000 (y se abre con
rem http://IP-de-este-ordenador:8000).
chcp 65001 >nul
cd /d "%~dp0"
set "PY="
where py >nul 2>&1 && set "PY=py -3"
if not defined PY where python >nul 2>&1 && set "PY=python"
if not defined PY (
  echo No encuentro Python. Instala Python 3 desde https://www.python.org/downloads/ marcando "Add python.exe to PATH"
  echo y vuelve a abrir este archivo.
  pause
  exit /b 1
)
set "PUERTO=%~1"
if "%PUERTO%"=="" set "PUERTO=80"
set "DIR=:%PUERTO%"
if "%PUERTO%"=="80" set "DIR="
title Simulador web - UxS Trainer (puerto %PUERTO%)
echo Simulador web en http://localhost%DIR% y, desde los demas ordenadores, http://IP-de-este%DIR% con esta IP:
ipconfig | findstr /i "IPv4"
%PY% -m http.server %PUERTO% --bind 0.0.0.0 --directory simulador
if errorlevel 1 (
  echo.
  echo No se pudo abrir el puerto %PUERTO%: suele ser que otro programa ya lo usa ^(en el 80, IIS, Skype o el servidor
  echo web de otro programa^). Cierra ese programa o usa otro puerto: SERVIDOR_WEB.bat 8000
)
pause
