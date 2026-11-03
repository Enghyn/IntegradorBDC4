#Requires -Version 5.1
<#
.SYNOPSIS
    Simulacro de restauración de Food Store en una base descartable.

.DESCRIPTION
    Restaura el último respaldo custom en foodstore_restore_test, ejecuta las
    validaciones mínimas, compara los conteos contra la línea base registrada
    al momento del respaldo y calcula RTO (tiempo de restauración + validación)
    y RPO (antigüedad del respaldo usado).

    La base principal foodstore NUNCA se elimina ni se reemplaza.

    No contiene contraseñas: usa PGPASSWORD del entorno, pgpass.conf o el
    método configurado en el servidor.

.PARAMETER PgPort
    Puerto. Por defecto: 5545.

.PARAMETER RestoreDb
    Base de restauración. Por defecto: foodstore_restore_test.

.EXAMPLE
    .\restore_test.ps1

.EXAMPLE
    .\restore_test.ps1 -PgPort 5432 -BackupFile .\backups\foodstore_20261103_101500.dump
#>
[CmdletBinding()]
param(
    [string]$PgHost = 'localhost',
    [int]$PgPort = 5545,
    [string]$PgUser = 'postgres',
    [string]$SourceDb = 'foodstore',
    [string]$RestoreDb = 'foodstore_restore_test',
    [string]$BackupFile,
    [string]$BaselineFile,
    [string]$BackupDir,
    [string]$LogDir,
    [string]$EvidenceDir
)

$ErrorActionPreference = 'Stop'

if (-not $BackupDir)   { $BackupDir   = Join-Path $PSScriptRoot 'backups' }
if (-not $LogDir)      { $LogDir      = Join-Path $PSScriptRoot 'logs' }
if (-not $EvidenceDir) { $EvidenceDir = Join-Path $PSScriptRoot 'evidencias' }
New-Item -ItemType Directory -Force -Path $LogDir, $EvidenceDir | Out-Null

# Guarda de seguridad: nunca restaurar sobre la base principal.
if ($RestoreDb -eq $SourceDb) {
    throw "RestoreDb no puede ser igual a SourceDb ($SourceDb). El simulacro debe usar una base descartable."
}

function Resolve-PgBin {
    param([string]$Exe)

    if ($env:PG_BIN) {
        $candidate = Join-Path $env:PG_BIN $Exe
        if (Test-Path -LiteralPath $candidate) { return $env:PG_BIN }
    }

    $cmd = Get-Command $Exe -ErrorAction SilentlyContinue
    if ($cmd) { return (Split-Path -Path $cmd.Source -Parent) }

    $roots = @('C:\Program Files\PostgreSQL', 'C:\Program Files (x86)\PostgreSQL')
    foreach ($root in $roots) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        $dirs = Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue |
                Sort-Object Name -Descending
        foreach ($dir in $dirs) {
            $bin = Join-Path $dir.FullName 'bin'
            if (Test-Path -LiteralPath (Join-Path $bin $Exe)) { return $bin }
        }
    }

    throw "No se encontró '$Exe'. Instalá PostgreSQL o definí la variable PG_BIN."
}

function Invoke-Native {
    # Ejecuta un binario y captura salida y código sin que un mensaje por
    # stderr (por ejemplo un NOTICE) se convierta en error terminante.
    param(
        [Parameter(Mandatory)][string]$Exe,
        [Parameter(Mandatory)][string[]]$Arguments
    )
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & $Exe @Arguments 2>&1
        $code = $LASTEXITCODE
        return [pscustomobject]@{ ExitCode = $code; Output = @($output) }
    }
    finally {
        $ErrorActionPreference = $previous
    }
}

$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$script:LogFile = Join-Path $LogDir "restore_test_$timestamp.log"

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]$Level = 'INFO'
    )
    $line = '[{0}] [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Add-Content -LiteralPath $script:LogFile -Value $line -Encoding UTF8
    Write-Host $line
}

function Format-Duration {
    param([double]$Seconds)
    $ts = [TimeSpan]::FromSeconds($Seconds)
    return ('{0:00}h {1:00}m {2:00}.{3:000}s' -f [int]$ts.TotalHours, $ts.Minutes, $ts.Seconds, $ts.Milliseconds)
}

$countSql = @"
SELECT 'categoria', COUNT(*) FROM categoria
UNION ALL SELECT 'cliente', COUNT(*) FROM cliente
UNION ALL SELECT 'producto', COUNT(*) FROM producto
UNION ALL SELECT 'pedido', COUNT(*) FROM pedido
UNION ALL SELECT 'detalle_pedido', COUNT(*) FROM detalle_pedido
ORDER BY 1;
"@

$invalidProductsSql = "SELECT COUNT(*) FROM producto WHERE precio_lista < 0 OR stock < 0;"
$invalidDetailsSql  = "SELECT COUNT(*) FROM detalle_pedido WHERE cantidad <= 0 OR precio_unitario_facturado < 0;"

$exitCode = 0

try {
    $bin        = Resolve-PgBin -Exe 'pg_restore.exe'
    $pgRestore  = Join-Path $bin 'pg_restore.exe'
    $createdb   = Join-Path $bin 'createdb.exe'
    $dropdb     = Join-Path $bin 'dropdb.exe'
    $psql       = Join-Path $bin 'psql.exe'

    # ------------------------------------------------------------------
    # Resolver respaldo y línea base
    # ------------------------------------------------------------------
    if (-not $BackupFile) {
        $BackupFile = Get-ChildItem -LiteralPath $BackupDir -Filter 'foodstore_*.dump' -File -ErrorAction SilentlyContinue |
                      Sort-Object LastWriteTime -Descending |
                      Select-Object -First 1 -ExpandProperty FullName
    }
    if (-not $BackupFile -or -not (Test-Path -LiteralPath $BackupFile)) {
        throw "No se encontró ningún respaldo en $BackupDir. Ejecutá backup_foodstore.ps1 primero."
    }
    $backupItem = Get-Item -LiteralPath $BackupFile

    if (-not $BaselineFile) {
        $BaselineFile = Get-ChildItem -LiteralPath $LogDir -Filter 'baseline_*.txt' -File -ErrorAction SilentlyContinue |
                        Sort-Object LastWriteTime -Descending |
                        Select-Object -First 1 -ExpandProperty FullName
    }
    if (-not $BaselineFile -or -not (Test-Path -LiteralPath $BaselineFile)) {
        throw "No se encontró la línea base de conteos en $LogDir. Debe generarla el script de respaldo."
    }

    $baseline = @{}
    foreach ($line in (Get-Content -LiteralPath $BaselineFile -Encoding UTF8)) {
        if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith('#')) { continue }
        $parts = $line -split '\|'
        if ($parts.Count -ge 2) {
            $baseline[$parts[0].Trim()] = [int64]$parts[1].Trim()
        }
    }
    if ($baseline.Count -eq 0) {
        throw "La línea base $BaselineFile no contiene conteos válidos."
    }

    $rpoSeconds = ((Get-Date) - $backupItem.LastWriteTime).TotalSeconds

    Write-Log "INICIO simulacro restauracion"
    Write-Log "Respaldo usado : $($backupItem.FullName)"
    Write-Log "Fecha respaldo : $($backupItem.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))"
    Write-Log "Tamano respaldo: $([math]::Round($backupItem.Length / 1MB, 2)) MB"
    Write-Log "Linea base     : $BaselineFile"
    Write-Log "Base destino   : $RestoreDb"
    Write-Log ("RPO observado  : {0} ({1:N2} s de antiguedad)" -f (Format-Duration $rpoSeconds), $rpoSeconds)

    # ------------------------------------------------------------------
    # Preparación: eliminar una corrida anterior de la base descartable.
    # (Fuera del cronómetro: no forma parte del RTO.)
    # ------------------------------------------------------------------
    Write-Log "Preparacion: eliminando $RestoreDb si existe..."
    $dropResult = Invoke-Native -Exe $dropdb -Arguments @(
        '-h', $PgHost, '-p', "$PgPort", '-U', $PgUser,
        '--if-exists', '--no-password', $RestoreDb
    )
    if ($dropResult.ExitCode -ne 0) { throw "dropdb fallo: $($dropResult.Output -join ' ')" }
    foreach ($line in $dropResult.Output) { if ($line) { Write-Log ("dropdb: " + $line) } }

    # ------------------------------------------------------------------
    # Cronómetro: comienza inmediatamente antes de crear la base de prueba.
    # ------------------------------------------------------------------
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    Write-Log 'CRONOMETRO INICIADO (RTO)'

    Write-Log "Creando base $RestoreDb ..."
    $createResult = Invoke-Native -Exe $createdb -Arguments @(
        '-h', $PgHost, '-p', "$PgPort", '-U', $PgUser, '--no-password', $RestoreDb
    )
    if ($createResult.ExitCode -ne 0) { throw "createdb fallo: $($createResult.Output -join ' ')" }
    foreach ($line in $createResult.Output) { if ($line) { Write-Log ("createdb: " + $line) } }

    Write-Log "Restaurando $($backupItem.Name) con pg_restore ..."
    $restoreResult = Invoke-Native -Exe $pgRestore -Arguments @(
        '-h', $PgHost, '-p', "$PgPort", '-U', $PgUser, '-d', $RestoreDb,
        '--no-owner', '--no-privileges', '--no-password', $backupItem.FullName
    )
    foreach ($line in $restoreResult.Output) { if ($line) { Write-Log ("pg_restore: " + $line) 'WARN' } }
    if ($restoreResult.ExitCode -ne 0) { throw "pg_restore finalizo con codigo $($restoreResult.ExitCode)." }

    # ------------------------------------------------------------------
    # Validaciones mínimas
    # ------------------------------------------------------------------
    Write-Log 'Validando conteos de filas...'
    $countResult = Invoke-Native -Exe $psql -Arguments @(
        '-h', $PgHost, '-p', "$PgPort", '-U', $PgUser, '-d', $RestoreDb,
        '-At', '-F', '|', '--no-password', '-c', $countSql
    )
    if ($countResult.ExitCode -ne 0) { throw "Fallo la consulta de conteos: $($countResult.Output -join ' ')" }
    $restoredRaw = $countResult.Output

    $restored = @{}
    foreach ($line in $restoredRaw) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $parts = $line -split '\|'
        if ($parts.Count -ge 2) { $restored[$parts[0].Trim()] = [int64]$parts[1].Trim() }
    }

    $mismatches = @()
    $rows = @()
    foreach ($tabla in ($baseline.Keys | Sort-Object)) {
        $esperado  = $baseline[$tabla]
        $obtenido  = if ($restored.ContainsKey($tabla)) { $restored[$tabla] } else { -1 }
        $ok        = ($esperado -eq $obtenido)
        if (-not $ok) { $mismatches += "$tabla (esperado=$esperado, restaurado=$obtenido)" }
        $rows += [pscustomobject]@{
            tabla     = $tabla
            esperado  = $esperado
            restaurado = $obtenido
            ok        = $ok
        }
        Write-Log ("Conteo {0}: esperado={1} restaurado={2} {3}" -f $tabla, $esperado, $obtenido, $(if ($ok) { 'OK' } else { 'MISMATCH' })) $(if ($ok) { 'INFO' } else { 'ERROR' })
    }

    Write-Log 'Validando restricciones logicas...'
    $invalidProductsResult = Invoke-Native -Exe $psql -Arguments @(
        '-h', $PgHost, '-p', "$PgPort", '-U', $PgUser, '-d', $RestoreDb,
        '-At', '--no-password', '-c', $invalidProductsSql
    )
    if ($invalidProductsResult.ExitCode -ne 0) { throw "Fallo la validacion de productos: $($invalidProductsResult.Output -join ' ')" }
    $invalidProducts = [int64]($invalidProductsResult.Output | Select-Object -First 1)

    $invalidDetailsResult = Invoke-Native -Exe $psql -Arguments @(
        '-h', $PgHost, '-p', "$PgPort", '-U', $PgUser, '-d', $RestoreDb,
        '-At', '--no-password', '-c', $invalidDetailsSql
    )
    if ($invalidDetailsResult.ExitCode -ne 0) { throw "Fallo la validacion de detalles: $($invalidDetailsResult.Output -join ' ')" }
    $invalidDetails = [int64]($invalidDetailsResult.Output | Select-Object -First 1)

    Write-Log "productos_invalidos=$invalidProducts (esperado 0)"
    Write-Log "detalles_invalidos=$invalidDetails (esperado 0)"

    $sw.Stop()
    $rtoSeconds = $sw.Elapsed.TotalSeconds

    $sizeResult = Invoke-Native -Exe $psql -Arguments @(
        '-h', $PgHost, '-p', "$PgPort", '-U', $PgUser, '-d', $RestoreDb,
        '-At', '--no-password', '-c', "SELECT pg_size_pretty(pg_database_size(current_database()));"
    )
    $restoredSize = ($sizeResult.Output | Select-Object -First 1)

    $ok = ($mismatches.Count -eq 0) -and ($invalidProducts -eq 0) -and ($invalidDetails -eq 0)

    Write-Log ("CRONOMETRO DETENIDO: RTO = {0} ({1:N2} s)" -f (Format-Duration $rtoSeconds), $rtoSeconds)
    Write-Log "Tamano base restaurada: $restoredSize"

    # ------------------------------------------------------------------
    # Evidencia resumida
    # ------------------------------------------------------------------
    $evidencePath = Join-Path $EvidenceDir "restore_test_$timestamp.txt"
    $evidence = @()
    $evidence += 'SIMULACRO DE RESTAURACION - FOOD STORE'
    $evidence += "Fecha de ejecucion : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    $evidence += "Respaldo usado     : $($backupItem.Name)"
    $evidence += "Fecha del respaldo : $($backupItem.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))"
    $evidence += "Tamano del respaldo: $([math]::Round($backupItem.Length / 1MB, 2)) MB"
    $evidence += "Base restaurada    : $RestoreDb ($restoredSize)"
    $evidence += "RPO observado      : $([math]::Round($rpoSeconds, 2)) s"
    $evidence += "RTO observado      : $([math]::Round($rtoSeconds, 2)) s"
    $evidence += ''
    $evidence += 'TABLA|ESPERADO|RESTAURADO|OK'
    foreach ($r in $rows) { $evidence += ('{0}|{1}|{2}|{3}' -f $r.tabla, $r.esperado, $r.restaurado, $r.ok) }
    $evidence += ''
    $evidence += "productos_invalidos=$invalidProducts"
    $evidence += "detalles_invalidos=$invalidDetails"
    $evidence += "resultado=$(if ($ok) { 'OK' } else { 'FALLIDO' })"
    Set-Content -LiteralPath $evidencePath -Value $evidence -Encoding UTF8
    Write-Log "Evidencia: $evidencePath"

    if (-not $ok) {
        if ($mismatches.Count -gt 0) { throw ("Conteos no coinciden: " + ($mismatches -join '; ')) }
        throw "Las validaciones de restricciones logicas fallaron."
    }

    Write-Log 'FIN OK: restauracion y validaciones correctas.'
    Write-Host ''
    Write-Host '============================================='
    Write-Host ' SIMULACRO COMPLETADO'
    Write-Host " Respaldo : $($backupItem.Name)"
    Write-Host " RPO      : $([math]::Round($rpoSeconds, 2)) s"
    Write-Host " RTO      : $([math]::Round($rtoSeconds, 2)) s"
    Write-Host " Log      : $script:LogFile"
    Write-Host " Evidencia: $evidencePath"
    Write-Host '============================================='
}
catch {
    if ($sw) { $sw.Stop() }
    Write-Log "FIN ERROR: $($_.Exception.Message)" 'ERROR'
    Write-Host ''
    Write-Host '============================================='
    Write-Host ' SIMULACRO FALLIDO'
    Write-Host " Detalle: $($_.Exception.Message)"
    Write-Host " Log    : $script:LogFile"
    Write-Host '============================================='
    $exitCode = 1
}

exit $exitCode
