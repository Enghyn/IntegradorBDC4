#Requires -Version 5.1
<#
.SYNOPSIS
    Respaldo custom de la base Food Store con registro en logs.

.DESCRIPTION
    Genera un respaldo en formato custom (-Fc) de la base indicada, con fecha y
    hora en el nombre. Registra inicio, fin, duración, tamaño y código de salida
    en un archivo de log. Si pg_dump falla o el archivo queda vacío, termina con
    código de error.

    No contiene contraseñas: la autenticación se resuelve con PGPASSWORD del
    entorno, pgpass.conf o el método configurado en el servidor.

.PARAMETER PgHost
    Host de PostgreSQL. Por defecto: localhost.

.PARAMETER PgPort
    Puerto. Por defecto: 5545 (clúster de laboratorio del TP8).

.PARAMETER PgUser
    Usuario. Por defecto: postgres.

.PARAMETER DbName
    Base a respaldar. Por defecto: foodstore.

.EXAMPLE
    .\backup_foodstore.ps1

.EXAMPLE
    # Definir PGPASSWORD en la sesión actual (nunca dentro del script)
    .\backup_foodstore.ps1 -PgPort 5432 -DbName foodstore
#>
[CmdletBinding()]
param(
    [string]$PgHost = 'localhost',
    [int]$PgPort = 5545,
    [string]$PgUser = 'postgres',
    [string]$DbName = 'foodstore',
    [string]$BackupDir,
    [string]$LogDir
)

$ErrorActionPreference = 'Stop'

if (-not $BackupDir) { $BackupDir = Join-Path $PSScriptRoot 'backups' }
if (-not $LogDir)    { $LogDir    = Join-Path $PSScriptRoot 'logs' }
New-Item -ItemType Directory -Force -Path $BackupDir, $LogDir | Out-Null

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
$dumpName  = "foodstore_$timestamp.dump"
$dumpPath  = Join-Path $BackupDir $dumpName
$script:LogFile = Join-Path $LogDir "backup_$timestamp.log"

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

$exitCode = 0
$sw = [System.Diagnostics.Stopwatch]::StartNew()

try {
    Write-Log "INICIO respaldo db=$DbName host=$PgHost port=$PgPort user=$PgUser"
    Write-Log "Archivo destino: $dumpPath"

    $bin     = Resolve-PgBin -Exe 'pg_dump.exe'
    $pgDump  = Join-Path $bin 'pg_dump.exe'
    $psql    = Join-Path $bin 'psql.exe'
    Write-Log "Binarios: $bin"

    $dumpArgs = @(
        '-Fc',
        '-f', $dumpPath,
        '-h', $PgHost,
        '-p', "$PgPort",
        '-U', $PgUser,
        '-d', $DbName,
        '--no-password'
    )

    Write-Log 'Ejecutando pg_dump -Fc ...'
    $dumpResult = Invoke-Native -Exe $pgDump -Arguments $dumpArgs
    $pgDumpExit = $dumpResult.ExitCode
    foreach ($line in $dumpResult.Output) { if ($line) { Write-Log ("pg_dump: " + $line) } }

    if ($pgDumpExit -ne 0) {
        throw "pg_dump finalizó con código $pgDumpExit."
    }

    $file = Get-Item -LiteralPath $dumpPath -ErrorAction SilentlyContinue
    if (-not $file) {
        throw "pg_dump devolvió 0 pero el archivo no existe: $dumpPath"
    }
    if ($file.Length -le 0) {
        throw "El archivo de respaldo está vacío: $dumpPath"
    }

    $sizeMb = [math]::Round($file.Length / 1MB, 2)
    Write-Log "Respaldo OK: $dumpName ($sizeMb MB)"

    # Línea base de conteos al momento del respaldo (para validar la restauración).
    $baselinePath = Join-Path $LogDir "baseline_$timestamp.txt"
    $countSql = @"
SELECT 'categoria', COUNT(*) FROM categoria
UNION ALL SELECT 'cliente', COUNT(*) FROM cliente
UNION ALL SELECT 'producto', COUNT(*) FROM producto
UNION ALL SELECT 'pedido', COUNT(*) FROM pedido
UNION ALL SELECT 'detalle_pedido', COUNT(*) FROM detalle_pedido
ORDER BY 1;
"@
    $countResult = Invoke-Native -Exe $psql -Arguments @(
        '-h', $PgHost, '-p', "$PgPort", '-U', $PgUser, '-d', $DbName,
        '-At', '-F', '|', '--no-password', '-c', $countSql
    )
    if ($countResult.ExitCode -ne 0) {
        throw "No se pudieron registrar los conteos de la línea base: $($countResult.Output -join ' ')"
    }
    $counts = $countResult.Output

    $baseline = @("# backup=$dumpName", "# timestamp=$timestamp") + $counts
    Set-Content -LiteralPath $baselinePath -Value $baseline -Encoding UTF8
    Write-Log "Línea base de conteos: $baselinePath"

    $sw.Stop()
    $seconds = [math]::Round($sw.Elapsed.TotalSeconds, 2)
    Write-Log "FIN OK duracion=${seconds}s tamano=${sizeMb}MB codigo=0"
    Write-Host ''
    Write-Host '============================================='
    Write-Host ' RESPALDO COMPLETADO'
    Write-Host " Archivo : $dumpPath"
    Write-Host " Tamaño  : $sizeMb MB"
    Write-Host " Duración: $seconds s"
    Write-Host " Log     : $script:LogFile"
    Write-Host '============================================='
}
catch {
    $sw.Stop()
    $seconds = [math]::Round($sw.Elapsed.TotalSeconds, 2)
    Write-Log "FIN ERROR duracion=${seconds}s codigo=1 detalle=$($_.Exception.Message)" 'ERROR'
    if (Test-Path -LiteralPath $dumpPath) {
        Remove-Item -LiteralPath $dumpPath -Force -ErrorAction SilentlyContinue
        Write-Log 'Se eliminó el archivo parcial para no dejarlo como respaldo válido.' 'WARN'
    }
    Write-Host ''
    Write-Host '============================================='
    Write-Host ' RESPALDO FALLIDO'
    Write-Host " Detalle: $($_.Exception.Message)"
    Write-Host " Log    : $script:LogFile"
    Write-Host '============================================='
    $exitCode = 1
}

exit $exitCode
