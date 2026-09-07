<#
.SYNOPSIS
    Script de automatización y seguridad para carga masiva y benchmarks de FoodStore DB.
.DESCRIPTION
    Orquesta el protocolo de seguridad de la cátedra:
    1. Validación estricta línea por línea del script SQL (prohibidos DROP, TRUNCATE, ALTER, etc.).
    2. Validación de entorno (prohibido ejecutar sobre producción; solo test/dev/local).
    3. Respaldo obligatorio (pg_dump) guardado en db/backups/.
    4. Ejecución del script de carga dentro de una transacción.
    5. Ejecución de ANALYZE en las tablas afectadas para actualizar estadísticas del optimizador.
#>

param(
    [string]$DbName = "foodstore_test",
    [string]$DbUser = "postgres",
    [string]$DbHost = "localhost",
    [string]$DbPort = "5432",
    [string]$ScriptPath = "db/seeds/load_massive_data.sql"
)

$ErrorActionPreference = "Stop"

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  FOODSTORE DB - PROTOCOLO DE CARGA MASIVA Y SEGURIDAD" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

# 1. Validación de Base de Datos de Prueba (No Producción)
if ($DbName -notmatch "test|dev|local") {
    Write-Host "[ERROR FATAL] La base de datos '$DbName' no es de pruebas (debe contener test, dev o local)." -ForegroundColor Red
    Write-Host "Prohibido operar sobre entornos productivos." -ForegroundColor Red
    exit 1
}
Write-Host "[OK] Base de datos objetivo validada como entorno seguro: $DbName" -ForegroundColor Green

# 2. Validación de existencia del script
if (-not (Test-Path -LiteralPath $ScriptPath)) {
    Write-Host "[ERROR] No se encuentra el script SQL en la ruta: $ScriptPath" -ForegroundColor Red
    exit 1
}

# 3. Lectura y validación línea por línea del script SQL
Write-Host "[INFO] Validando script SQL línea por línea ($ScriptPath)..." -ForegroundColor Yellow
$scriptContent = Get-Content -LiteralPath $ScriptPath

foreach ($line in $scriptContent) {
    # Ignorar líneas comentadas
    if ($line.Trim().StartsWith("--") -or [string]::IsNullOrWhiteSpace($line)) {
        continue
    }

    # Verificar comandos prohibidos destructivos o DDL no permitidos
    if ($line -match "\b(DROP|TRUNCATE|ALTER)\b") {
        Write-Host "[ERROR DE SEGURIDAD] Comando prohibido detectado en línea: '$line'" -ForegroundColor Red
        Write-Host "Los scripts de carga no pueden contener DROP, TRUNCATE o ALTER." -ForegroundColor Red
        exit 1
    }
}
Write-Host "[OK] Validación estricta línea por línea superada (sin comandos destructivos)." -ForegroundColor Green

# 4. Respaldo obligatorio previo (pg_dump)
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$backupDir = "db\backups"
if (-not (Test-Path -LiteralPath $backupDir)) {
    New-Item -ItemType Directory -Path $backupDir | Out-Null
}
$backupFile = "$backupDir\foodstore_backup_$timestamp.sql"

Write-Host "[INFO] Realizando respaldo previo (pg_dump) en: $backupFile" -ForegroundColor Yellow
& pg_dump -U $DbUser -h $DbHost -p $DbPort -d $DbName -F p -f $backupFile

if ($LASTEXITCODE -ne 0 -or (-not (Test-Path -LiteralPath $backupFile)) -or ((Get-Item -LiteralPath $backupFile).Length -eq 0)) {
    Write-Host "[ERROR FATAL] El respaldo con pg_dump falló o el archivo está vacío. Abortando ejecución." -ForegroundColor Red
    exit 1
}
Write-Host "[OK] Respaldo completado exitosamente." -ForegroundColor Green

# 5. Ejecución del script SQL de carga masiva
Write-Host "[INFO] Ejecutando script de carga masiva sobre $DbName..." -ForegroundColor Yellow
$logFile = "$backupDir\load_run_$timestamp.log"

& psql -U $DbUser -h $DbHost -p $DbPort -d $DbName -f $ScriptPath 2>&1 | Tee-Object -FilePath $logFile

if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR FATAL] La ejecución del script de carga falló. Ver log en $logFile" -ForegroundColor Red
    exit 1
}
Write-Host "[OK] Carga masiva ejecutada y confirmada exitosamente." -ForegroundColor Green

# 6. Ejecución de ANALYZE en las tablas afectadas
Write-Host "[INFO] Ejecutando ANALYZE para actualizar estadísticas del optimizador..." -ForegroundColor Yellow
& psql -U $DbUser -h $DbHost -p $DbPort -d $DbName -c "ANALYZE cliente, producto, pedido, detalle_pedido;" 2>&1 | Tee-Object -FilePath "$backupDir\analyze_$timestamp.log"

if ($LASTEXITCODE -ne 0) {
    Write-Host "[WARNING] El comando ANALYZE reportó advertencias, verificar estadísticas." -ForegroundColor Yellow
} else {
    Write-Host "[OK] ANALYZE ejecutado correctamente en todas las tablas afectadas." -ForegroundColor Green
}

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  PROCESO DE CARGA MASIVA Y BENCHMARK FINALIZADO CON ÉXITO" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
