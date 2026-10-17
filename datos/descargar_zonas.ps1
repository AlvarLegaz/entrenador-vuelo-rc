# Descarga las zonas de detalle de los mundos reales que no van en el repositorio (La Manga, el Mar Menor y sus islas,
# la base aerea de San Javier, el CIFP Politecnico, el club Los Halcones de la Rambla, el Mingrano y las plantas fotovoltaicas y la fabrica de SABIC; unos 330 MB) y las deja en datos\escenarios\zonas, junto con el
# indice de todas. Las usan los simuladores (la web, Godot y las gafas). Lo llaman DESCARGAR_ZONAS.bat, SERVIDOR_WEB.bat
# y SIMULADOR_V2_GODOT.bat cuando faltan; tambien se puede ejecutar a mano:
#     powershell -NoProfile -ExecutionPolicy Bypass -File datos\descargar_zonas.ps1
# Fuente: la "release" del repositorio en GitHub. Comprueba la huella SHA-256 del zip antes de descomprimir nada.
# Sin internet, las zonas se pueden generar con analisis\mundo_cartagena\zonas_mar_menor.py, zona_cifp.py,
# zona_halcones.py, zona_mingrano.py y zona_fotovoltaica.py (necesitan Python con numpy, Pillow y scipy; unos 70 min).
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"            # sin la barra de progreso, Invoke-WebRequest va mucho mas rapido
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$TAG     = "zonas-2026-10-15b"
$ZIP     = "zonas_detalle_2026-10-15b.zip"
$SHA256  = "9b50f6cf765f9f9b6e270d2c72b536f774ead7f1c00cae55c0b0068b0e608288"
$URL     = "https://github.com/AlvarLegaz/uxs-trainer/releases/download/$TAG/$ZIP"
$SIM     = Join-Path $PSScriptRoot "escenarios"     # datos\escenarios: el zip trae la carpeta zonas\
$MARCA   = Join-Path $SIM "zonas\version_zonas.txt"          # la version de las zonas descargadas: si no es $TAG, se baja el zip nuevo

# antes de reorganizar el repositorio (2026-10-17) estaban en simulador\zonas: si ya se bajaron, se mueven sin bajarlas otra vez
$VIEJA   = Join-Path $PSScriptRoot "..\simulador\zonas"
if ((Test-Path $VIEJA) -and -not (Test-Path (Join-Path $SIM "zonas\cifp_politecnico"))) {
    Write-Host "Moviendo las zonas de detalle de simulador\zonas a datos\escenarios\zonas ..."
    $nueva = Join-Path $SIM "zonas"
    if (-not (Test-Path $nueva)) { New-Item -ItemType Directory -Force $nueva | Out-Null }
    Get-ChildItem $VIEJA | ForEach-Object { Move-Item $_.FullName $nueva -Force }
    Remove-Item $VIEJA -Recurse -Force
}

if ((Test-Path $MARCA) -and ((Get-Content $MARCA -Raw).Trim() -eq $TAG) -and -not ($args -contains "-forzar")) { Write-Host "Las zonas de detalle ya estan en $SIM\zonas"; exit 0 }
$zipLocal = Join-Path $env:TEMP $ZIP
try {
    Write-Host "Descargando las zonas de detalle (unos 330 MB, solo la primera vez) de $URL ..."
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
    Write-Host "Descargalo a mano: $URL y descomprimelo en $SIM (crea datos\escenarios\zonas\...)"
    exit 1
}
