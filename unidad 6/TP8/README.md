# TP8 — Mantenimiento, respaldo y recuperación (Food Store)

Trabajo práctico de la Unidad 6. Todos los resultados de este directorio provienen de
ejecuciones reales sobre PostgreSQL 17.11; no hay valores simulados.

## Integrantes

- Enzo Giaquinta
- Agustin Contardi
- Fernando Torrez
- Ramiro Salcedo
- Ignacio Sánchez

## Entregables

| Archivo | Contenido |
|---|---|
| `SPEC_U6.md` | Especificación del plan, frecuencias, criterios de éxito y reglas de seguridad (1 página). |
| `backup_foodstore.ps1` | Respaldo custom (`pg_dump -Fc`) con fecha/hora, log y salida con error si falla. |
| `health_check.sql` | 8 controles de monitoreo (tamaño, conexiones, tablas, consultas activas, bloqueos, autovacuum, transacciones largas, configuración). |
| `maintenance.sql` | Revisión de autovacuum/estadísticas y `ANALYZE` justificado por observación previa. |
| `restore_test.ps1` | Simulacro completo: `createdb`, `pg_restore`, validaciones, RTO y RPO. |
| `informe_u6.pdf` | Informe post-incidente de una página con evidencias y métricas reales. |
| `informe_u6.md` / `.html` | Fuente del informe. |

## Evidencias de la ejecución

| Evidencia | Resultado real |
|---|---|
| `logs/backup_20261103_095841.log` | Respaldo OK: `foodstore_20261103_095841.dump`, 6,69 MB, 3,68 s. |
| `logs/baseline_20261103_095841.txt` | Conteos previos al respaldo: 10 / 20.000 / 50.000 / 200.000 / 700.140. |
| `evidencias/health_check_20261103_095718.txt` | Salida real del chequeo de salud. |
| `evidencias/maintenance_20261103_095723.txt` | Diagnóstico, `ANALYZE categoria` y verificación posterior. |
| `logs/restore_test_20261103_095849.log` | Restauración OK: conteos idénticos, 0 inválidos, RTO 5,23 s, RPO 4,92 s. |
| `evidencias/restore_test_20261103_095849.txt` | Resumen del simulacro. |
| `logs/restore_test_20261103_095728.log` | Primera ejecución fallida: evidencia del bug de PowerShell corregido. |

## Entorno de laboratorio

- Clúster PostgreSQL 17.11 aislado en `localhost:5545`, autenticación local `trust`.
- Base principal: `foodstore` (103 MB; 200.000 pedidos; 700.140 líneas).
- Base de restauración: `foodstore_restore_test`.
- El clúster del puerto 5433 pertenece a otro trabajo y **no** se modificó.
- Los scripts aceptan `-PgHost`, `-PgPort`, `-PgUser`, `-DbName`; en entornos con
  contraseña se usa `PGPASSWORD` del entorno o `pgpass.conf`. **No hay credenciales
  escritas en ningún archivo.**

### Recrear el entorno (si el clúster temporal no existe)

```powershell
$base = "$env:TEMP\opencode\tp8pg"
& "C:\Program Files\PostgreSQL\17\bin\initdb.exe" -D $base -U postgres -A trust -E UTF8 --locale=C
Add-Content "$base\postgresql.conf" "`nport = 5545`nlisten_addresses = 'localhost'`n"
& "C:\Program Files\PostgreSQL\17\bin\pg_ctl.exe" start -D $base -l "$base\server.log"
& "C:\Program Files\PostgreSQL\17\bin\createdb.exe" -h localhost -p 5545 -U postgres foodstore
& "C:\Program Files\PostgreSQL\17\bin\psql.exe" -h localhost -p 5545 -U postgres -d foodstore -f ..\food_store\schema.sql
& "C:\Program Files\PostgreSQL\17\bin\psql.exe" -h localhost -p 5545 -U postgres -d foodstore -f ..\food_store\data.sql
```

## Reproducir el procedimiento

```powershell
# 1. Respaldo
.\backup_foodstore.ps1

# 2. Monitoreo
psql -h localhost -p 5545 -U postgres -d foodstore -f health_check.sql

# 3. Mantenimiento justificado
psql -h localhost -p 5545 -U postgres -d foodstore -f maintenance.sql

# 4. Simulacro de restauración
.\restore_test.ps1
```

## Nota sobre la consigna

Las consultas de validación de la consigna usan `precio` y `precio_unitario`. El
esquema real del proyecto define `precio_lista` y `precio_unitario_facturado`, por lo
que las validaciones se adaptaron a esos nombres. La equivalencia lógica se mantiene:
se controlan valores negativos de precio/stock y cantidades/precios unitarios no positivos.
