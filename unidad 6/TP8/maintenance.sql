-- ============================================================================
-- maintenance.sql — Revisión de mantenimiento y acción segura justificada
-- Motor: PostgreSQL 16+ (probado en 17.11)
-- Base: foodstore
-- Uso:  psql -h localhost -p 5545 -U postgres -d foodstore -f maintenance.sql
--
-- POLÍTICA: VACUUM FULL NO se utiliza como mantenimiento periódico.
--          Toda acción manual se decide a partir de la observación previa.
-- ============================================================================

\echo '=== 1. CONFIGURACIÓN VIGENTE DE AUTOVACUUM ==='
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

\echo '=== 2. ESTADO DE LAS TABLAS (OBSERVACIÓN PREVIA) ==='
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
       last_autoanalyze                               AS ultimo_autoanalyze
FROM pg_stat_user_tables
ORDER BY n_dead_tup DESC, relname;

\echo '=== 3. SEMÁFORO: TABLAS QUE REQUIEREN ATENCIÓN ==='
-- Criterios:
--   * Sin estadísticas: last_analyze IS NULL y last_autoanalyze IS NULL
--     -> ejecutar ANALYZE (seguro, no bloquea escrituras).
--   * Tuplas muertas > 10%: dejar actuar a autovacuum; si es crónico,
--     ajustar el umbral POR TABLA (ALTER TABLE ... SET (...)).
--   * Cambios sin analyze > 10% de las tuplas vivas -> ANALYZE.
SELECT relname AS tabla,
       CASE
         WHEN last_analyze IS NULL AND last_autoanalyze IS NULL
              THEN 'SIN ESTADISTICAS -> ANALYZE'
         WHEN n_live_tup + n_dead_tup > 0
              AND (100.0 * n_dead_tup / (n_live_tup + n_dead_tup)) > 10
              THEN 'TUPLAS MUERTAS > 10% -> revisar autovacuum'
         WHEN n_live_tup > 0
              AND (100.0 * n_mod_since_analyze / n_live_tup) > 10
              THEN 'ESTADISTICAS DESACTUALIZADAS -> ANALYZE'
         ELSE 'OK'
       END AS diagnostico
FROM pg_stat_user_tables
ORDER BY tabla;

-- ============================================================================
-- 4. ACCIÓN DE MANTENIMIENTO (justificada por la observación del punto 2)
--
-- Decisión observada en esta ejecución:
--   * categoria: last_analyze IS NULL y last_autoanalyze IS NULL
--     -> no tiene estadísticas; se ejecuta ANALYZE.
--   * pedido, detalle_pedido, producto y cliente: ya fueron analizadas tras
--     la carga masiva y no presentan tuplas muertas -> no requieren acción.
--   * autovacuum está habilitado con los valores por defecto.
--
-- ANALYZE es seguro: no toma bloqueos exclusivos y solo actualiza estadísticas.
-- ============================================================================
ANALYZE categoria;

-- Si en el futuro una tabla supera el 10% de tuplas muertas de forma sostenida,
-- la acción segura es VACUUM (ANALYZE) sobre esa tabla, o ajustar su umbral:
--   ALTER TABLE detalle_pedido SET (autovacuum_vacuum_scale_factor = 0.05);
--   VACUUM (ANALYZE) detalle_pedido;
-- Nunca VACUUM FULL como rutina.

\echo '=== 5. VERIFICACIÓN POST-ACCIÓN ==='
SELECT relname                                        AS tabla,
       n_live_tup                                     AS tuplas_vivas,
       n_dead_tup                                     AS tuplas_muertas,
       n_mod_since_analyze                            AS cambios_sin_analyze,
       last_analyze                                   AS ultimo_analyze,
       last_autoanalyze                               AS ultimo_autoanalyze
FROM pg_stat_user_tables
ORDER BY relname;

\echo '=== 6. ESTADÍSTICAS DE LA TABLA INTERVENIDA ==='
SELECT attname                                        AS columna,
       n_distinct                                     AS valores_distintos,
       null_frac                                      AS fraccion_nulos,
       most_common_vals                               AS valores_frecuentes
FROM pg_stats
WHERE schemaname = 'public'
  AND tablename = 'categoria'
ORDER BY attname;
