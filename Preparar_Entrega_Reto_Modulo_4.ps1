# Preparar_Entrega_Reto_Modulo_4.ps1
# Reto Integrador - Programacion Avanzada para Ciencia de Datos
# Valida las evidencias existentes y genera un ZIP sin ejecutar notebooks ni
# modificar los artefactos originales.

param(
    [string]$RaizProyecto = 'C:\codigo\python\ambientes\ProgramacionAvanzada_Reto-Modulo-4'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$NombreZip = 'Entrega_Reto_Modulo_4.zip'
$RutaZip = Join-Path $RaizProyecto $NombreZip
$DocumentoComplementario = 'DECISION_TECNICA_SOBRESCRITURAS.md'

# Archivos indispensables para las dos corridas de la consigna.
$Archivos = @(
    'M4_Reto_Integrador_Observabilidad_Reproducible.ipynb',
    'ejecutado_web.ipynb',
    'ejecutado_tienda.ipynb',
    'requirements.txt',
    'Data\ventas_ejemplo.csv'
)

foreach ($RunId in @('web_bimestre', 'tienda_bimestre')) {
    foreach ($Nombre in @('detalle.csv', 'resumen.json', 'entorno.json', 'ejecucion.log')) {
        $Archivos += "resultados\reto_integrador\$RunId\$Nombre"
    }
}

Write-Host '=== 1. Comprobacion de archivos ==='
if (-not (Test-Path -LiteralPath $RaizProyecto -PathType Container)) {
    throw "No existe el proyecto: $RaizProyecto"
}
if (Test-Path -LiteralPath $RutaZip) {
    throw "El ZIP ya existe: $RutaZip. Cambia su nombre o guardalo antes de crear otro."
}

foreach ($Relativo in $Archivos) {
    $Completo = Join-Path $RaizProyecto $Relativo
    if (-not (Test-Path -LiteralPath $Completo -PathType Leaf)) {
        throw "Falta un archivo obligatorio: $Relativo"
    }
    if ((Get-Item -LiteralPath $Completo).Length -le 0) {
        throw "El archivo esta vacio: $Relativo"
    }
    Write-Host "OK: $Relativo"
}

Write-Host "`n=== 2. Comprobacion de hashes y resultados ==="
$HashCSV = (Get-FileHash -LiteralPath (Join-Path $RaizProyecto 'Data\ventas_ejemplo.csv') -Algorithm SHA256).Hash
$HashRequirements = (Get-FileHash -LiteralPath (Join-Path $RaizProyecto 'requirements.txt') -Algorithm SHA256).Hash

$Esperados = @{
    web_bimestre = @{ Canal = 'Web'; Inicio = '2026-01-01'; Fin = '2026-02-28'; Filas = 13; Total = 382500 }
    tienda_bimestre = @{ Canal = 'Tienda'; Inicio = '2026-03-01'; Fin = '2026-04-30'; Filas = 14; Total = 470000 }
}

foreach ($RunId in @('web_bimestre', 'tienda_bimestre')) {
    $Dir = Join-Path $RaizProyecto "resultados\reto_integrador\$RunId"
    $Entorno = Get-Content -LiteralPath (Join-Path $Dir 'entorno.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $Resumen = Get-Content -LiteralPath (Join-Path $Dir 'resumen.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $Esperado = $Esperados[$RunId]

    if ($Entorno.hash_datos_csv -ine $HashCSV) {
        throw "El SHA-256 del CSV no coincide con entorno.json para $RunId"
    }
    if ($Entorno.hash_requirements -ine $HashRequirements) {
        throw "El SHA-256 de requirements.txt no coincide con entorno.json para $RunId"
    }
    if ($Resumen.parametros.run_id -cne $RunId -or
        $Resumen.parametros.canal -cne $Esperado.Canal -or
        $Resumen.parametros.fecha_inicio -cne $Esperado.Inicio -or
        $Resumen.parametros.fecha_fin -cne $Esperado.Fin -or
        $Resumen.registros_finales -ne $Esperado.Filas -or
        [decimal]$Resumen.venta_total -ne [decimal]$Esperado.Total) {
        throw "Los parametros o indicadores de resumen.json son inesperados: $RunId"
    }

    # El detalle persistido debe coincidir con el resumen; se usa cultura invariante.
    $Detalle = @(Import-Csv -LiteralPath (Join-Path $Dir 'detalle.csv'))
    if ($Detalle.Count -ne $Resumen.registros_finales) {
        throw "Diferencia de cantidad entre detalle.csv y resumen.json: $RunId"
    }
    $Suma = [decimal]0
    foreach ($Fila in $Detalle) {
        $Suma += [decimal]::Parse($Fila.venta_total, [System.Globalization.CultureInfo]::InvariantCulture)
    }
    if ($Suma -ne [decimal]$Resumen.venta_total) {
        throw "Diferencia de total entre detalle.csv y resumen.json: $RunId"
    }
    Write-Host "OK: $RunId - hashes, parametros, cantidad y total consistentes"
}

Write-Host "`n=== 3. Preparacion del ZIP ==="
$Temporal = Join-Path $env:TEMP ('entrega_reto_' + [guid]::NewGuid().ToString('N'))
try {
    New-Item -ItemType Directory -Path $Temporal -Force | Out-Null
    foreach ($Relativo in $Archivos) {
        $Origen = Join-Path $RaizProyecto $Relativo
        $Destino = Join-Path $Temporal $Relativo
        $CarpetaDestino = Split-Path -Path $Destino -Parent
        New-Item -ItemType Directory -Path $CarpetaDestino -Force | Out-Null
        Copy-Item -LiteralPath $Origen -Destination $Destino
    }

    $RutaMD = Join-Path $RaizProyecto $DocumentoComplementario
    if (Test-Path -LiteralPath $RutaMD -PathType Leaf) {
        Copy-Item -LiteralPath $RutaMD -Destination (Join-Path $Temporal $DocumentoComplementario)
        Write-Host "OK: Documento complementario incluido: $DocumentoComplementario"
    } else {
        Write-Warning "No se encontro $DocumentoComplementario; el ZIP incluira los 13 archivos obligatorios."
    }

    Compress-Archive -Path (Join-Path $Temporal '*') -DestinationPath $RutaZip -CompressionLevel Optimal
    if (-not (Test-Path -LiteralPath $RutaZip -PathType Leaf)) {
        throw 'No se pudo generar el ZIP.'
    }

    # Auditar la estructura interna del ZIP sin modificarlo.
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $Zip = [System.IO.Compression.ZipFile]::OpenRead($RutaZip)
    try {
        $RutasEnZip = @($Zip.Entries | ForEach-Object { $_.FullName.Replace('/', '\') })
        foreach ($Relativo in $Archivos) {
            if ($RutasEnZip -notcontains $Relativo) {
                throw "El ZIP no contiene el archivo esperado: $Relativo"
            }
        }
    } finally {
        $Zip.Dispose()
    }

    Write-Host "`n=== ENTREGA LISTA ==="
    Write-Host "ZIP: $RutaZip"
    Write-Host 'Verificados 13 archivos obligatorios y ambos resultados de negocio.'
    Write-Host 'No se han incluido .venv, TestReto ni carpetas temporales.'
    Get-Item -LiteralPath $RutaZip | Select-Object FullName, Length
    Write-Host 'SHA-256 del ZIP:'
    (Get-FileHash -LiteralPath $RutaZip -Algorithm SHA256).Hash
} finally {
    if (Test-Path -LiteralPath $Temporal) {
        Remove-Item -LiteralPath $Temporal -Force -Recurse -ErrorAction SilentlyContinue
    }
}
