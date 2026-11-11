-- ============================================================================
-- health_check.sql — Chequeo de salud de Food Store
-- Motor: PostgreSQL 16+ (probado en 17.11)
-- Base: foodstore
-- Uso:  psql -h localhost -p 5545 -U postgres -d foodstore -f health_check.sql
-- No contiene contraseñas.
-- ============================================================================

\echo '=== 1. TAMAÑO DE LA BASE Y DE LAS TABLAS PRINCIPALES ==='
SELECT current_database()                              AS base,
       pg_size_pretty(pg_database_size(current_database())) AS tamano_total;

SELECT relname                                            AS tabla,
       pg_size_pretty(pg_total_relation_size(relid))      AS tamano_total,
       pg_size_pretty(pg_relation_size(relid))            AS solo_tabla,
       pg_size_pretty(pg_total_relation_size(relid)
                      - pg_relation_size(relid))          AS indices_y_toast
FROM pg_catalog.pg_statio_user_tables
ORDER BY pg_total_relation_size(relid) DESC;

\echo '=== 2. ACTIVIDAD DE CONEXIONES Y TRANSACCIONES ==='
SELECT datname                                   AS base,
       numbackends                               AS conexiones_actuales,
       xact_commit                               AS commits,
       xact_rollback                             AS rollbacks,
       CASE WHEN (xact_commit + xact_rollback) > 0
            THEN ROUND(100.0 * xact_rollback
                       / (xact_commit + xact_rollback), 2)
            ELSE 0 END                           AS pct_rollback,
       blks_read                                 AS bloques_leidos,
       blks_hit                                  AS bloques_cache,
       CASE WHEN (blks_read + blks_hit) > 0
            THEN ROUND(100.0 * blks_hit / (blks_read + blks_hit), 2)
            ELSE 0 END                           AS cache_hit_pct,
       deadlocks                                 AS deadlocks,
       temp_files                                AS archivos_temp,
       pg_size_pretty(temp_bytes)                 AS bytes_temp,
       stats_reset                               AS stats_desde
FROM pg_stat_database
WHERE datname = current_database();

SELECT state, COUNT(*) AS conexiones
FROM pg_stat_activity
WHERE datname = current_database()
GROUP BY state
ORDER BY conexiones DESC;

\echo '=== 3. ESTADO DE TABLAS: TUPLAS, AUTOVACUUM Y ESTADÍSTICAS ==='
SELECT relname                                        AS tabla,
       n_live_tup                                     AS tuplas_vivas,
       n_dead_tup                                     AS tuplas_muertas,
       CASE WHEN n_live_tup + n_dead_tup > 0
            THEN ROUND(100.0 * n_dead_tup / (n_live_tup + n_dead_tup), 2)
            ELSE 0 END                                 AS pct_muertas,
       n_mod_since_analyze                            AS cambios_sin_analyze,
       last_vacuum                                    AS ultimo_vacuum,
       last_autovacuum                                AS ultimo_autovacuum,
       last_analyze                                   AS ultimo_analyze,
       last_autoanalyze                               AS ultimo_autoanalyze,
       seq_scan                                       AS scans_secuenciales,
       idx_scan                                       AS scans_indice
FROM pg_stat_user_tables
ORDER BY n_dead_tup DESC, relname;

\echo '=== 4. CONSULTAS ACTIVAS (EXCLUYE IDLE) ==='
SELECT pid,
       usename                                        AS usuario,
       state                                          AS estado,
       wait_event_type                                AS espera_tipo,
       wait_event                                     AS espera_evento,
       now() - query_start                            AS duracion,
       left(query, 120)                               AS consulta
FROM pg_stat_activity
WHERE datname = current_database()
  AND state <> 'idle'
  AND pid <> pg_backend_pid()
ORDER BY query_start;

\echo '=== 5. BLOQUEOS: QUIÉN BLOQUEA A QUIÉN ==='
SELECT a.pid,
       a.usename,
       a.state,
       now() - a.query_start                          AS duracion,
       pg_blocking_pids(a.pid)                        AS pids_bloqueantes,
       left(a.query, 120)                             AS consulta
FROM pg_stat_activity a
WHERE a.datname = current_database()
  AND cardinality(pg_blocking_pids(a.pid)) > 0;

\echo '=== 6. AUTOVACUUM EN CURSO ==='
SELECT pid,
       datname,
       relid::regclass                                AS tabla,
       phase,
       heap_blks_total,
       heap_blks_scanned,
       heap_blks_vacuumed,
       index_vacuum_count,
       max_dead_tuples,
       num_dead_tuples
FROM pg_stat_progress_vacuum;

\echo '=== 7. TRANSACCIONES LARGAS (> 5 MINUTOS) ==='
SELECT pid,
       usename,
       state,
       now() - xact_start                             AS duracion_transaccion,
       left(query, 120)                               AS consulta
FROM pg_stat_activity
WHERE datname = current_database()
  AND xact_start IS NOT NULL
  AND now() - xact_start > interval '5 minutes'
ORDER BY xact_start;

\echo '=== 8. CONFIGURACIÓN DE AUTOVACUUM ==='
SELECT name, setting, unit
FROM pg_settings
WHERE name IN ('autovacuum',
               'autovacuum_naptime',
               'autovacuum_vacuum_scale_factor',
               'autovacuum_analyze_scale_factor',
               'autovacuum_vacuum_threshold',
               'autovacuum_analyze_threshold',
               'autovacuum_max_workers')
ORDER BY name;
