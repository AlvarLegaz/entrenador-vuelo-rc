@echo off
rem Descarga las zonas de detalle que no van en el repositorio (La Manga, el Mar Menor y sus islas, la base aerea de San Javier,
rem el CIFP Politecnico, Los Halcones de la Rambla, el Mingrano y las plantas fotovoltaicas y la fabrica de SABIC; unos 330 MB) para los simuladores (en datos\escenarios\zonas). Doble clic. Ver datos\descargar_zonas.ps1.
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "datos\descargar_zonas.ps1" %*
pause
