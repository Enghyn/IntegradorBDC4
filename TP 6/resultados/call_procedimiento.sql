-- ----------------------------------------------------------------------------
-- Evidencia: procedimiento fs_reconstruir_resumen invocado con CALL
-- Se ejecuta sobre la base ya poblada (tp_desnormalizacion_top_categorias.sql).
--   psql -h 127.0.0.1 -p 55432 -U postgres -d food_store_tp6 \
--        -f resultados/call_procedimiento.sql
-- ----------------------------------------------------------------------------
\timing on

-- 1) Reconstrucción del histórico completo, confirmando cada lote de 90 días.
--    Se ejecuta fuera de un bloque de transacción: el COMMIT interno es válido.
CALL fs_reconstruir_resumen(DATE '2024-10-29', CURRENT_DATE, true, 90);

-- 2) Después de reconstruir, la auditoría debe quedar vacía.
SELECT COUNT(*) AS diferencias
FROM v_auditoria_resumen;

SELECT COUNT(*) AS filas,
       MIN(fecha) AS desde,
       MAX(fecha) AS hasta
FROM resumen_venta_categoria_dia;

-- 3) p_commit = true dentro de una transacción explícita: el motor lo rechaza
--    con "invalid transaction termination". Es la razón por la que el valor
--    predeterminado es false.
BEGIN;
CALL fs_reconstruir_resumen(CURRENT_DATE, CURRENT_DATE, true, 1);
ROLLBACK;

-- 4) p_commit = false dentro de la misma transacción: funciona y se revierte.
BEGIN;
UPDATE resumen_venta_categoria_dia
   SET total_vendido = 0
 WHERE fecha = CURRENT_DATE;
SELECT COUNT(*) AS diferencias_antes
FROM v_auditoria_resumen;
CALL fs_reconstruir_resumen(CURRENT_DATE, CURRENT_DATE, false, 1);
SELECT COUNT(*) AS diferencias_despues
FROM v_auditoria_resumen;
ROLLBACK;
