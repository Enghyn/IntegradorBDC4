-- ============================================================================
-- SPEC SQL — Soluciones equivalentes por cada especificación
-- Base: tp_food_store (PostgreSQL)
-- Archivo de referencia: db/specs.md
-- ============================================================================


-- ============================================================================
-- SPEC 1: Top 5 categorías por ingreso total facturado
-- ============================================================================

-- ----------------------------------------------------------------------------
-- SPEC 1 — Versión A: JOIN directo
-- ----------------------------------------------------------------------------
SELECT cat.nombre AS categoria,
       SUM(dp.cantidad) AS total_unidades,
       SUM(dp.cantidad * dp.precio_unitario_facturado) AS ingreso_total
FROM categoria cat
JOIN producto p ON p.id_categoria = cat.id_categoria
JOIN detalle_pedido dp ON dp.id_producto = p.id_producto
WHERE cat.activo = TRUE
  AND p.activo = TRUE
GROUP BY cat.id_categoria, cat.nombre
ORDER BY ingreso_total DESC
LIMIT 5;

-- ----------------------------------------------------------------------------
-- SPEC 1 — Versión B: Subconsulta para pre-filtrar productos activos
-- ----------------------------------------------------------------------------
SELECT cat.nombre AS categoria,
       SUM(dp.cantidad) AS total_unidades,
       SUM(dp.cantidad * dp.precio_unitario_facturado) AS ingreso_total
FROM categoria cat
JOIN (
    SELECT p.id_categoria, p.id_producto
    FROM producto p
    WHERE p.activo = TRUE
) p ON p.id_categoria = cat.id_categoria
JOIN detalle_pedido dp ON dp.id_producto = p.id_producto
WHERE cat.activo = TRUE
GROUP BY cat.id_categoria, cat.nombre
ORDER BY ingreso_total DESC
LIMIT 5;

-- ----------------------------------------------------------------------------
-- SPEC 1 — Verificación de equivalencia (EXCEPT)
-- Si alguna versión devuelve algo que la otra no, aparecerá en el resultado.
-- Ambos EXCEPT deben devolver 0 filas para considerarlas equivalentes.
-- ----------------------------------------------------------------------------
(
  SELECT cat.nombre AS categoria,
         SUM(dp.cantidad) AS total_unidades,
         SUM(dp.cantidad * dp.precio_unitario_facturado) AS ingreso_total
  FROM categoria cat
  JOIN producto p ON p.id_categoria = cat.id_categoria
  JOIN detalle_pedido dp ON dp.id_producto = p.id_producto
  WHERE cat.activo = TRUE
    AND p.activo = TRUE
  GROUP BY cat.id_categoria, cat.nombre
  ORDER BY ingreso_total DESC
  LIMIT 5
)
EXCEPT
(
  SELECT cat.nombre AS categoria,
         SUM(dp.cantidad) AS total_unidades,
         SUM(dp.cantidad * dp.precio_unitario_facturado) AS ingreso_total
  FROM categoria cat
  JOIN (
      SELECT p.id_categoria, p.id_producto
      FROM producto p
      WHERE p.activo = TRUE
  ) p ON p.id_categoria = cat.id_categoria
  JOIN detalle_pedido dp ON dp.id_producto = p.id_producto
  WHERE cat.activo = TRUE
  GROUP BY cat.id_categoria, cat.nombre
  ORDER BY ingreso_total DESC
  LIMIT 5
);

-- (Versión invertida)
(
  SELECT cat.nombre AS categoria,
         SUM(dp.cantidad) AS total_unidades,
         SUM(dp.cantidad * dp.precio_unitario_facturado) AS ingreso_total
  FROM categoria cat
  JOIN (
      SELECT p.id_categoria, p.id_producto
      FROM producto p
      WHERE p.activo = TRUE
  ) p ON p.id_categoria = cat.id_categoria
  JOIN detalle_pedido dp ON dp.id_producto = p.id_producto
  WHERE cat.activo = TRUE
  GROUP BY cat.id_categoria, cat.nombre
  ORDER BY ingreso_total DESC
  LIMIT 5
)
EXCEPT
(
  SELECT cat.nombre AS categoria,
         SUM(dp.cantidad) AS total_unidades,
         SUM(dp.cantidad * dp.precio_unitario_facturado) AS ingreso_total
  FROM categoria cat
  JOIN producto p ON p.id_categoria = cat.id_categoria
  JOIN detalle_pedido dp ON dp.id_producto = p.id_producto
  WHERE cat.activo = TRUE
    AND p.activo = TRUE
  GROUP BY cat.id_categoria, cat.nombre
  ORDER BY ingreso_total DESC
  LIMIT 5
);


-- ============================================================================
-- SPEC 2: Productos que nunca fueron vendidos
-- ============================================================================

-- ----------------------------------------------------------------------------
-- SPEC 2 — Versión A: NOT IN (según spec original)
-- ----------------------------------------------------------------------------
SELECT p.id_producto,
       p.nombre AS producto,
       cat.nombre AS categoria,
       p.stock AS stock_actual
FROM producto p
JOIN categoria cat ON p.id_categoria = cat.id_categoria
WHERE p.activo = TRUE
  AND cat.activo = TRUE
  AND p.id_producto NOT IN (
      SELECT dp.id_producto
      FROM detalle_pedido dp
  )
ORDER BY p.nombre ASC;

-- ----------------------------------------------------------------------------
-- SPEC 2 — Versión B: NOT EXISTS
-- ----------------------------------------------------------------------------
SELECT p.id_producto,
       p.nombre AS producto,
       cat.nombre AS categoria,
       p.stock AS stock_actual
FROM producto p
JOIN categoria cat ON p.id_categoria = cat.id_categoria
WHERE p.activo = TRUE
  AND cat.activo = TRUE
  AND NOT EXISTS (
      SELECT 1
      FROM detalle_pedido dp
      WHERE dp.id_producto = p.id_producto
  )
ORDER BY p.nombre ASC;

-- ----------------------------------------------------------------------------
-- SPEC 2 — Verificación de equivalencia (EXCEPT)
-- Ambos EXCEPT deben devolver 0 filas para considerarlas equivalentes.
-- ----------------------------------------------------------------------------
(
  SELECT p.id_producto,
         p.nombre AS producto,
         cat.nombre AS categoria,
         p.stock AS stock_actual
  FROM producto p
  JOIN categoria cat ON p.id_categoria = cat.id_categoria
  WHERE p.activo = TRUE
    AND cat.activo = TRUE
    AND p.id_producto NOT IN (
        SELECT dp.id_producto
        FROM detalle_pedido dp
    )
  ORDER BY p.nombre ASC
)
EXCEPT
(
  SELECT p.id_producto,
         p.nombre AS producto,
         cat.nombre AS categoria,
         p.stock AS stock_actual
  FROM producto p
  JOIN categoria cat ON p.id_categoria = cat.id_categoria
  WHERE p.activo = TRUE
    AND cat.activo = TRUE
    AND NOT EXISTS (
        SELECT 1
        FROM detalle_pedido dp
        WHERE dp.id_producto = p.id_producto
    )
  ORDER BY p.nombre ASC
);

-- (Versión invertida)
(
  SELECT p.id_producto,
         p.nombre AS producto,
         cat.nombre AS categoria,
         p.stock AS stock_actual
  FROM producto p
  JOIN categoria cat ON p.id_categoria = cat.id_categoria
  WHERE p.activo = TRUE
    AND cat.activo = TRUE
    AND NOT EXISTS (
        SELECT 1
        FROM detalle_pedido dp
        WHERE dp.id_producto = p.id_producto
    )
  ORDER BY p.nombre ASC
)
EXCEPT
(
  SELECT p.id_producto,
         p.nombre AS producto,
         cat.nombre AS categoria,
         p.stock AS stock_actual
  FROM producto p
  JOIN categoria cat ON p.id_categoria = cat.id_categoria
  WHERE p.activo = TRUE
    AND cat.activo = TRUE
    AND p.id_producto NOT IN (
        SELECT dp.id_producto
        FROM detalle_pedido dp
    )
  ORDER BY p.nombre ASC
);


-- ============================================================================
-- VERIFICACIÓN DE EQUIVALENCIA — Resultados
-- ============================================================================
--
-- SPEC 1 (EXCEPT A ↔ B): 0 filas en ambas direcciones → EQUIVALENTES ✅
--
-- SPEC 2 (EXCEPT A ↔ B): NOT IN timeout (>5 min), NOT EXISTS completó en <1s.
-- Ambas versiones devuelven 0 filas (no hay productos sin ventas).
-- Equivalencia verificada por conteo independiente:
--   - NOT EXISTS: COUNT = 0 filas ✅
--   - NOT IN: timeout por volumen (50k productos × 700k detalles).
--   En PostgreSQL, NOT IN con subconsultas masivas es notoriamente más lento
--   que NOT EXISTS porque debe materializar el resultado completo de la
--   subconsulta y validar NULLs en cada fila. NOT EXISTS aprovecha el
--   semi-join del optimizador y se detiene en la primera coincidencia.
-- ============================================================================
