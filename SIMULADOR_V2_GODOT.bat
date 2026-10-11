@echo off
rem Simulador de vuelo RC v2 (Godot). Doble clic para abrirlo.
cd /d "%~dp0"
if not exist "herramientas\godot\Godot_v4.7.2-stable_win64.exe" (
  echo Falta Godot: descarga Godot 4.7.2 estandar ^(sin .NET^) de godotengine.org y dejalo en la carpeta herramientas\godot
  pause
  exit /b 1
)
start "" "herramientas\godot\Godot_v4.7.2-stable_win64.exe" --path simulador_godot
