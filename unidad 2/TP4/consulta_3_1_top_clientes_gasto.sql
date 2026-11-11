-- ============================================================================
-- 3.1 Consulta Resumen y Ranking: Top 10 Clientes por Gasto Total
-- Spec: Obtener el ranking de los 10 clientes con mayor facturación histórica.
-- Tablas: cliente, pedido, detalle_pedido
-- Filtro: cliente.activo = TRUE
-- Columnas: id_cliente, nombre_cliente, cantidad_pedidos, monto_total_gastado
-- Orden: monto_total_gastado DESC, LIMIT 10
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Versión A: Join con GROUP BY (Generada con IA)
-- ----------------------------------------------------------------------------
SELECT 
    c.id_cliente,
    c.nombre AS nombre_cliente,
    COUNT(DISTINCT p.id_pedido) AS cantidad_pedidos,
    ROUND(SUM(dp.cantidad * dp.precio_unitario_facturado)::NUMERIC, 2) AS monto_total_gastado
FROM cliente c
JOIN pedido p ON c.id_cliente = p.id_cliente
JOIN detalle_pedido dp ON p.id_pedido = dp.id_pedido
WHERE c.activo = TRUE
GROUP BY c.id_cliente, c.nombre
ORDER BY monto_total_gastado DESC
LIMIT 10;

-- ----------------------------------------------------------------------------
-- Versión B: Alternativa propia con CTE / Agregación previa
-- ----------------------------------------------------------------------------
WITH pedidos_totales AS (
    SELECT 
        p.id_cliente,
        p.id_pedido,
        SUM(dp.cantidad * dp.precio_unitario_facturado) AS total_pedido
    FROM pedido p
    JOIN detalle_pedido dp ON p.id_pedido = dp.id_pedido
    GROUP BY p.id_cliente, p.id_pedido
)
SELECT 
    c.id_cliente,
    c.nombre AS nombre_cliente,
    COUNT(pt.id_pedido) AS cantidad_pedidos,
    ROUND(SUM(pt.total_pedido)::NUMERIC, 2) AS monto_total_gastado
FROM cliente c
JOIN pedidos_totales pt ON c.id_cliente = pt.id_cliente
WHERE c.activo = TRUE
GROUP BY c.id_cliente, c.nombre
ORDER BY monto_total_gastado DESC
LIMIT 10;

-- ----------------------------------------------------------------------------
-- Verificación de equivalencia (EXCEPT bidireccional)
-- Ambos EXCEPT deben devolver 0 filas para considerarlas equivalentes.
-- ----------------------------------------------------------------------------
(
  SELECT c.id_cliente, c.nombre, COUNT(DISTINCT p.id_pedido),
         ROUND(SUM(dp.cantidad * dp.precio_unitario_facturado)::NUMERIC, 2)
  FROM cliente c
  JOIN pedido p ON c.id_cliente = p.id_cliente
  JOIN detalle_pedido dp ON p.id_pedido = dp.id_pedido
  WHERE c.activo = TRUE
  GROUP BY c.id_cliente, c.nombre
  ORDER BY 4 DESC LIMIT 10
)
EXCEPT
(
  WITH pedidos_totales AS (
      SELECT p.id_cliente, p.id_pedido,
             SUM(dp.cantidad * dp.precio_unitario_facturado) AS total_pedido
      FROM pedido p
      JOIN detalle_pedido dp ON p.id_pedido = dp.id_pedido
      GROUP BY p.id_cliente, p.id_pedido
  )
  SELECT c.id_cliente, c.nombre, COUNT(pt.id_pedido),
         ROUND(SUM(pt.total_pedido)::NUMERIC, 2)
  FROM cliente c
  JOIN pedidos_totales pt ON c.id_cliente = pt.id_cliente
  WHERE c.activo = TRUE
  GROUP BY c.id_cliente, c.nombre
  ORDER BY 4 DESC LIMIT 10
);

-- (Versión invertida)
(
  WITH pedidos_totales AS (
      SELECT p.id_cliente, p.id_pedido,
             SUM(dp.cantidad * dp.precio_unitario_facturado) AS total_pedido
      FROM pedido p
      JOIN detalle_pedido dp ON p.id_pedido = dp.id_pedido
      GROUP BY p.id_cliente, p.id_pedido
  )
  SELECT c.id_cliente, c.nombre, COUNT(pt.id_pedido),
         ROUND(SUM(pt.total_pedido)::NUMERIC, 2)
  FROM cliente c
  JOIN pedidos_totales pt ON c.id_cliente = pt.id_cliente
  WHERE c.activo = TRUE
  GROUP BY c.id_cliente, c.nombre
  ORDER BY 4 DESC LIMIT 10
)
EXCEPT
(
  SELECT c.id_cliente, c.nombre, COUNT(DISTINCT p.id_pedido),
         ROUND(SUM(dp.cantidad * dp.precio_unitario_facturado)::NUMERIC, 2)
  FROM cliente c
  JOIN pedido p ON c.id_cliente = p.id_cliente
  JOIN detalle_pedido dp ON p.id_pedido = dp.id_pedido
  WHERE c.activo = TRUE
  GROUP BY c.id_cliente, c.nombre
  ORDER BY 4 DESC LIMIT 10
);
