@echo off
rem Servidor del aula (aula\servidor_aula.py) en este ordenador: perfiles online, vuelos de todos, panel del profesor y
rem salas del multijugador. Doble clic; se para cerrando la ventana o con Ctrl+C. Necesita Python 3.8 o posterior (sin
rem instalar nada mas). La primera vez pide el PIN del profesor. Otro puerto: SERVIDOR_AULA.bat --puerto 8000
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
title Servidor del aula - UxS Trainer
%PY% aula\servidor_aula.py %*
pause
