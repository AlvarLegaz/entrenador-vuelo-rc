# Descarga las zonas de detalle de los mundos reales que no van en el repositorio (La Manga, el Mar Menor y sus islas,
# el CIFP Politecnico, el club Los Halcones de la Rambla, el Mingrano y las plantas fotovoltaicas y la fabrica de SABIC; unos 340 MB) y las deja en simulador\zonas, junto con el
# indice de todas. Las usan los dos simuladores (la web y Godot). Lo llaman DESCARGAR_ZONAS.bat y SIMULADOR_V2_GODOT.bat
# cuando faltan; tambien se puede ejecutar a mano:
#     powershell -NoProfile -ExecutionPolicy Bypass -File simulador\descargar_zonas.ps1
# Fuente: la "release" del repositorio en GitHub. Comprueba la huella SHA-256 del zip antes de descomprimir nada.
# Sin internet, las zonas se pueden generar con analisis\mundo_cartagena\zonas_mar_menor.py, zona_cifp.py,
# zona_halcones.py, zona_mingrano.py y zona_fotovoltaica.py (necesitan Python con numpy, Pillow y scipy; unos 70 min).
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"            # sin la barra de progreso, Invoke-WebRequest va mucho mas rapido
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$TAG     = "zonas-2026-10-15"
$ZIP     = "zonas_detalle_2026-10-15.zip"
$SHA256  = "61d4b8ffa2f1d0498e0858c93591cbb3df3a48e423f983417fc98a65e7ea487c"
$URL     = "https://github.com/AlvarLegaz/entrenador-vuelo-rc/releases/download/$TAG/$ZIP"
$SIM     = $PSScriptRoot                            # carpeta simulador
$MARCA   = Join-Path $SIM "zonas\version_zonas.txt"          # la version de las zonas descargadas: si no es $TAG, se baja el zip nuevo

if ((Test-Path $MARCA) -and ((Get-Content $MARCA -Raw).Trim() -eq $TAG) -and -not ($args -contains "-forzar")) { Write-Host "Las zonas de detalle ya estan en $SIM\zonas"; exit 0 }
$zipLocal = Join-Path $env:TEMP $ZIP
try {
    Write-Host "Descargando las zonas de detalle (unos 340 MB, solo la primera vez) de $URL ..."
    Invoke-WebRequest -Uri $URL -OutFile $zipLocal -UseBasicParsing
    Write-Host "Comprobando la huella SHA-256 ..."
    $real = (Get-FileHash -Algorithm SHA256 $zipLocal).Hash.ToLower()
    if ($real -ne $SHA256) { throw "La huella del zip descargado no coincide: no lo uso" }
    Write-Host "Huella correcta. Descomprimiendo en $SIM\zonas ..."
    Expand-Archive -Path $zipLocal -DestinationPath $SIM -Force
    Remove-Item $zipLocal -Force
    if (-not (Test-Path $MARCA) -or (Get-Content $MARCA -Raw).Trim() -ne $TAG) { throw "El zip no traia las zonas esperadas" }
    Write-Host "Zonas de detalle listas."
}
catch {
    Write-Host "ERROR: $($_.Exception.Message)"
    Write-Host "Descargalo a mano: $URL y descomprimelo en $SIM (crea simulador\zonas\...)"
    exit 1
}
