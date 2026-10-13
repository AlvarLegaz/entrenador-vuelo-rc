@echo off
rem Simulador de vuelo RC v2 (Godot). Doble clic para abrirlo.
rem Si falta Godot 4.7.2, lo descarga de la pagina oficial de Godot en GitHub (unos 86 MB, solo la primera vez),
rem comprueba su huella SHA-512 y lo deja en herramientas\godot (simulador_godot\descargar_godot.ps1).
cd /d "%~dp0"
if not exist "herramientas\godot\Godot_v4.7.2-stable_win64.exe" (
  echo Falta Godot 4.7.2: lo descargo ahora ^(solo la primera vez^).
  powershell -NoProfile -ExecutionPolicy Bypass -File "simulador_godot\descargar_godot.ps1"
  if errorlevel 1 (
    pause
    exit /b 1
  )
)
start "" "herramientas\godot\Godot_v4.7.2-stable_win64.exe" --path simulador_godot
