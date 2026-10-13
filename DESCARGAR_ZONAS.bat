@echo off
rem Descarga las zonas de detalle que no van en el repositorio (La Manga, el Mar Menor y sus islas, el CIFP Politecnico
rem y Los Halcones de la Rambla; unos 300 MB) para los dos simuladores. Doble clic. Ver simulador\descargar_zonas.ps1.
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "simulador\descargar_zonas.ps1" %*
pause
