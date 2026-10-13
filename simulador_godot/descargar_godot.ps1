# Descarga Godot 4.7.2 (estandar, sin .NET) para el simulador v2 y lo deja en herramientas\godot. Lo llama
# SIMULADOR_V2_GODOT.bat cuando falta; tambien se puede ejecutar a mano:
#     powershell -NoProfile -ExecutionPolicy Bypass -File simulador_godot\descargar_godot.ps1
# Fuente: las versiones oficiales de Godot en GitHub (github.com/godotengine/godot/releases). Comprueba la huella
# SHA-512 del zip con la lista que publica el propio Godot en esa version antes de descomprimir nada.
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"            # sin la barra de progreso, Invoke-WebRequest va mucho mas rapido
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$VERSION = "4.7.2-stable"
$ZIP     = "Godot_v$VERSION`_win64.exe.zip"
$BASE    = "https://github.com/godotengine/godot/releases/download/$VERSION"
$RAIZ    = Split-Path -Parent $PSScriptRoot        # carpeta del repositorio
$DESTINO = Join-Path $RAIZ "herramientas\godot"
$EXE     = Join-Path $DESTINO "Godot_v$VERSION`_win64.exe"

if (Test-Path $EXE) { Write-Host "Godot ya esta en $DESTINO"; exit 0 }
New-Item -ItemType Directory -Force $DESTINO | Out-Null
$zipLocal = Join-Path $DESTINO $ZIP
try {
    Write-Host "Descargando Godot $VERSION (unos 86 MB) de $BASE ..."
    Invoke-WebRequest -Uri "$BASE/$ZIP" -OutFile $zipLocal -UseBasicParsing
    Write-Host "Comprobando la huella SHA-512 ..."
    $sumas = (Invoke-WebRequest -Uri "$BASE/SHA512-SUMS.txt" -UseBasicParsing).Content
    if ($sumas -is [byte[]]) { $sumas = [Text.Encoding]::ASCII.GetString($sumas) }
    $linea = ($sumas -split "`n") | Where-Object { $_ -match ([regex]::Escape($ZIP) + "\s*$") } | Select-Object -First 1
    if (-not $linea) { throw "La lista de huellas de Godot no trae $ZIP" }
    $esperada = ($linea -split "\s+")[0].Trim().ToLower()
    $real = (Get-FileHash -Algorithm SHA512 $zipLocal).Hash.ToLower()
    if ($real -ne $esperada) { throw "La huella del zip descargado no coincide con la oficial: no lo uso" }
    Write-Host "Huella correcta. Descomprimiendo en $DESTINO ..."
    Expand-Archive -Path $zipLocal -DestinationPath $DESTINO -Force
    if (-not (Test-Path $EXE)) { throw "El zip no traia $EXE" }
    Write-Host "Godot $VERSION listo."
}
catch {
    Write-Host "ERROR: $($_.Exception.Message)"
    Write-Host "Descargalo a mano: $BASE/$ZIP y descomprimelo en $DESTINO"
    exit 1
}
finally {
    if (Test-Path $zipLocal) { Remove-Item $zipLocal -Force }
}
