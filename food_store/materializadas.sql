-- ============================================================================
-- MATERIALIZADAS.SQL — VISTA MATERIALIZADA DE FACTURACIÓN (Parte C — TP Semana 5)
-- Base de datos: tp_food_store (PostgreSQL) — SOLO sobre la copia local de
--                trabajo (tp_food_store o tp_food_store_local). NUNCA producción.
--
-- Contenido:
--   1. mv_facturacion_categoria_mes (spec: specs/vista_materializada_facturacion_categoria_mes.md)
--      Reporte agregado: facturación total, pedidos únicos y unidades vendidas
--      por categoría de producto y mes calendario.
--   2. Índice único idx_mv_facturacion_cat_mes_unq sobre (categoria_id, mes).
--      Requisito de PostgreSQL para poder ejecutar REFRESH ... CONCURRENTLY.
--   3. Verificación de equivalencia (EXCEPT bidireccional) contra la consulta
--      analítica original SIN materializar (ambos EXCEPT deben devolver 0 filas).
--   4. Módulo de medición: EXPLAIN (ANALYZE, BUFFERS, TIMING) de la consulta
--      original, del SELECT sobre la MV y del REFRESH CONCURRENTLY.
--
-- Normas:
--   - NO modifica el modelo de datos (no hay ALTER, DROP ni cambios de tipo
--     sobre las tablas base).
--   - Las vistas materializadas NO soportan CREATE OR REPLACE en PostgreSQL;
--     el DROP MATERIALIZED VIEW IF EXISTS inicial hace idempotente la
--     re-ejecución durante el desarrollo.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 0. DROP PREVENTIVO (idempotencia: MV no soporta CREATE OR REPLACE)
-- ----------------------------------------------------------------------------
DROP MATERIALIZED VIEW IF EXISTS mv_facturacion_categoria_mes;

-- ----------------------------------------------------------------------------
-- 1. VISTA MATERIALIZADA: MV_FACTURACION_CATEGORIA_MES
--    Facturación por categoría de producto y mes calendario.
--    Fuente: consulta analítica de la Semana 4 — join
--    pedido -> detalle_pedido -> producto -> categoria, agrupando por
--    DATE_TRUNC('month', fecha_pedido) e id_categoria.
--    WITH DATA: materializa el snapshot en el momento de la creación.
-- ----------------------------------------------------------------------------
CREATE MATERIALIZED VIEW mv_facturacion_categoria_mes AS
SELECT
    c.id_categoria AS categoria_id,
    c.nombre AS categoria_nombre,
    DATE_TRUNC('month', p.fecha_pedido) AS mes,
    COUNT(DISTINCT p.id_pedido) AS total_pedidos,
    SUM(dp.cantidad) AS total_unidades_vendidas,
    SUM(dp.cantidad * dp.precio_unitario_facturado) AS facturacion_total
FROM pedido p
JOIN detalle_pedido dp ON p.id_pedido = dp.id_pedido
JOIN producto pr ON dp.id_producto = pr.id_producto
JOIN categoria c ON pr.id_categoria = c.id_categoria
GROUP BY c.id_categoria, c.nombre, DATE_TRUNC('month', p.fecha_pedido)
WITH DATA;

-- ----------------------------------------------------------------------------
-- 2. ÍNDICE ÚNICO: habilita REFRESH MATERIALIZED VIEW CONCURRENTLY
--    Sin un índice único, PostgreSQL rechaza el refresco concurrente.
-- ----------------------------------------------------------------------------
CREATE UNIQUE INDEX idx_mv_facturacion_cat_mes_unq
    ON mv_facturacion_categoria_mes (categoria_id, mes);

-- ----------------------------------------------------------------------------
-- 3. VERIFICACIÓN DE EQUIVALENCIA — MV vs consulta manual (deben dar 0 filas)
-- ----------------------------------------------------------------------------
(
  SELECT v.categoria_id, v.categoria_nombre, v.mes, v.total_pedidos,
         v.total_unidades_vendidas, v.facturacion_total
  FROM mv_facturacion_categoria_mes v
)
EXCEPT
(
  SELECT c.id_categoria, c.nombre,
         DATE_TRUNC('month', p.fecha_pedido),
         COUNT(DISTINCT p.id_pedido),
         SUM(dp.cantidad),
         SUM(dp.cantidad * dp.precio_unitario_facturado)
  FROM pedido p
  JOIN detalle_pedido dp ON p.id_pedido = dp.id_pedido
  JOIN producto pr ON dp.id_producto = pr.id_producto
  JOIN categoria c ON pr.id_categoria = c.id_categoria
  GROUP BY c.id_categoria, c.nombre, DATE_TRUNC('month', p.fecha_pedido)
);

(
  SELECT c.id_categoria, c.nombre,
         DATE_TRUNC('month', p.fecha_pedido),
         COUNT(DISTINCT p.id_pedido),
         SUM(dp.cantidad),
         SUM(dp.cantidad * dp.precio_unitario_facturado)
  FROM pedido p
  JOIN detalle_pedido dp ON p.id_pedido = dp.id_pedido
  JOIN producto pr ON dp.id_producto = pr.id_producto
  JOIN categoria c ON pr.id_categoria = c.id_categoria
  GROUP BY c.id_categoria, c.nombre, DATE_TRUNC('month', p.fecha_pedido)
)
EXCEPT
(
  SELECT v.categoria_id, v.categoria_nombre, v.mes, v.total_pedidos,
         v.total_unidades_vendidas, v.facturacion_total
  FROM mv_facturacion_categoria_mes v
);

-- ============================================================================
-- 4. MÓDULO DE MEDICIÓN
--    Ejecutar cada bloque (psql o DBeaver) y pegar la salida en
--    informe_mediciones.md → sección "Parte C" en el marcador [PEGAR SALIDA].
--    Recomendación: repetir cada medición 2-3 veces sobre la base local con
--    datos masivos y registrar el valor estable (evitar la primera corrida
--    "en frío" si se busca comparar contra el baseline).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Bloque A — CONSULTA ORIGINAL SIN MATERIALIZAR (baseline)
--    Costo esperado: escaneo completo de ~700k filas de detalle_pedido,
--    join con pedido, producto y categoria + GroupAggregate.
-- ----------------------------------------------------------------------------
EXPLAIN (ANALYZE, BUFFERS, TIMING)
SELECT
    c.id_categoria AS categoria_id,
    c.nombre AS categoria_nombre,
    DATE_TRUNC('month', p.fecha_pedido) AS mes,
    COUNT(DISTINCT p.id_pedido) AS total_pedidos,
    SUM(dp.cantidad) AS total_unidades_vendidas,
    SUM(dp.cantidad * dp.precio_unitario_facturado) AS facturacion_total
FROM pedido p
JOIN detalle_pedido dp ON p.id_pedido = dp.id_pedido
JOIN producto pr ON dp.id_producto = pr.id_producto
JOIN categoria c ON pr.id_categoria = c.id_categoria
GROUP BY c.id_categoria, c.nombre, DATE_TRUNC('month', p.fecha_pedido);
-- [MEDIDO] Execution Time (original): 2797.623 ms  (Planning 0.855 ms)

-- ----------------------------------------------------------------------------
-- Bloque B — CONSULTA SOBRE LA VISTA MATERIALIZADA
--    Costo esperado: lectura directa del snapshot precomputado (~pocas filas).
-- ----------------------------------------------------------------------------
EXPLAIN (ANALYZE, BUFFERS, TIMING)
SELECT *
FROM mv_facturacion_categoria_mes;
-- [MEDIDO] Execution Time (MV): 0.042 ms  (Planning 0.078 ms)

-- ----------------------------------------------------------------------------
-- Bloque C — REFRESH MATERIALIZED VIEW CONCURRENTLY
--    Mide el costo de actualizar el snapshot. CONCURRENTLY no bloquea las
--    lecturas durante la reconstrucción, pero requiere el índice único.
-- ----------------------------------------------------------------------------
EXPLAIN (ANALYZE, BUFFERS, TIMING)
REFRESH MATERIALIZED VIEW CONCURRENTLY mv_facturacion_categoria_mes;
-- Bloque A: EXPLAIN (ANALYZE, BUFFERS, TIMING) de la consulta original:
--   Execution Time = 2797.623 ms, Planning Time = 0.855 ms
--   (GroupAggregate + Merge Join + Gather Merge paralelo, 2 workers;
--    salida completa pegada en informe_mediciones.md → Parte C → Bloque A)
-- Bloque B: EXPLAIN (ANALYZE, BUFFERS, TIMING) SELECT * FROM la MV:
--   Execution Time = 0.042 ms, Planning Time = 0.078 ms
--   (Seq Scan sobre la MV, 70 filas → mejora ≈ 66.600×)
-- Bloque C: REFRESH MATERIALIZED VIEW CONCURRENTLY:
--   sin plan (utility statement); ~10 s, 70 filas actualizadas (DBeaver)

-- ============================================================================
-- RESULTADOS DE VERIFICACIÓN (medidos sobre tp_food_store local, 2026-09-24)
--   EXCEPT MV <-> consulta manual : 0 filas  (esperado 0) ✅
--   Execution Time original      : 2797.623 ms   (Planning 0.855 ms)
--   Execution Time MV            : 0.042 ms      (Planning 0.078 ms)
--   Execution Time REFRESH       : ~10 s (updated rows 70; sin plan por ser
--                                  utility statement — medido por DBeaver)
-- ============================================================================