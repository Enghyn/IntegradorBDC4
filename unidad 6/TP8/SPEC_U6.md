# SPEC_U6 — Plan de mantenimiento, respaldo y recuperación

**Proyecto:** Food Store · **Motor:** PostgreSQL 17.11 · **Semana 10**

## 1. Alcance

Automatizar el ciclo mínimo sobre `foodstore`: respaldo, chequeo de salud, mantenimiento y simulacro de restauración en una base descartable. La base principal **nunca** se elimina ni se reemplaza.

## 2. Entorno de laboratorio

| Elemento | Valor |
|---|---|
| Clúster | PostgreSQL 17.11 aislado, `localhost:5545` (el 5433 es de otro trabajo y no se modifica) |
| Base principal | `foodstore` (103 MB; 200.000 pedidos; 700.140 líneas) |
| Base de restauración | `foodstore_restore_test` |
| Formato de respaldo | Custom (`pg_dump -Fc`), restaurable con `pg_restore` |

**Objetivos:** RPO ≤ 24 h (respaldo diario) y RTO ≤ 15 min (restauración + validación). Los scripts reciben host/puerto por parámetro.

## 3. Tareas, frecuencia y condición de finalización

| Tarea | Frecuencia | Script | Condición de finalización |
|---|---|---|---|
| Respaldo de `foodstore` | Diaria | `backup_foodstore.ps1` | Existe `backups/foodstore_<fecha>_<hora>.dump` con tamaño > 0, `pg_dump` devolvió 0 y el log registra inicio, fin, duración y tamaño. |
| Chequeo de salud | Diaria | `health_check.sql` | Devuelve filas en los 4 controles mínimos: tamaño, conexiones, estado de tablas y consultas activas. |
| Revisión de mantenimiento | Semanal | `maintenance.sql` | Se revisan tuplas muertas, autovacuum y estadísticas; la acción (`ANALYZE`) queda justificada por la observación previa. |
| Restauración de prueba | Semanal | `restore_test.ps1` | `foodstore_restore_test` existe, los conteos coinciden con la línea base, los controles de invalidez dan 0 y se registran RTO y RPO. |

**Evidencia:** `logs/backup_<fecha>.log` + `.dump` · `evidencias/health_check_<fecha>.txt` · `evidencias/maintenance_<fecha>.txt` · `logs/restore_test_<fecha>.log` · `informe_u6.pdf`

## 4. Reglas de seguridad

1. **Sin contraseñas** en scripts, logs ni repositorio: se usa `PGPASSWORD` del entorno, `pgpass.conf` o el método del servidor.
2. Las pruebas destructivas (`dropdb`, restauración) se ejecutan **solo** sobre `foodstore_restore_test`.
3. `foodstore` no se elimina, no se reemplaza y no se restaura encima; el respaldo se valida (existencia y tamaño) antes de considerarlo apto.
4. `VACUUM FULL` **no** se usa como mantenimiento periódico; todo `VACUUM`/`ANALYZE` manual se justifica con la observación previa de `pg_stat_user_tables`.
5. Todo comando asistido con IA se revisa y se prueba antes de aceptarlo.
