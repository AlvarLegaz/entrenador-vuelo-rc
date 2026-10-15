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
rem Las zonas de detalle (La Manga, Mar Menor, CIFP Politecnico, Los Halcones, el Mingrano, las plantas fotovoltaicas y
rem SABIC) no van en git: si faltan o hay una version nueva, se descargan de la release del repositorio (unos 340 MB;
rem simulador\descargar_zonas.ps1 mira zonas\version_zonas.txt y sale enseguida si ya estan). Sin ellas el simulador
rem funciona igual, con menos detalle en esos sitios.
powershell -NoProfile -ExecutionPolicy Bypass -File "simulador\descargar_zonas.ps1"
rem La cache de Godot (simulador_godot\.godot: registro de clases de los scripts e imports) no va en git. Sin ella el
rem simulador abre una ventana en blanco (no encuentra las clases), asi que se regenera en cada arranque (~2 s): asi
rem vale tambien despues de actualizar el repositorio con scripts nuevos.
echo Preparando el simulador...
if exist "herramientas\godot\Godot_v4.7.2-stable_win64_console.exe" (
  "herramientas\godot\Godot_v4.7.2-stable_win64_console.exe" --headless --path simulador_godot --import >nul 2>&1
) else (
  start "" /wait "herramientas\godot\Godot_v4.7.2-stable_win64.exe" --headless --path simulador_godot --import
)
start "" "herramientas\godot\Godot_v4.7.2-stable_win64.exe" --path simulador_godot
