-- ============================================================================
-- QUERIES.SQL — FUENTE DE CARGA DE TRABAJO (WORKLOAD) A INDEXAR
-- Trabajo Práctico: optimización con índices y vistas (sin alterar tablas base)
--
-- Contenido:
--   1. Consultas de negocio/analíticas (Semanas 3 y 4)
--      - 3.1 Top 10 clientes por gasto total (incluye verificación EXCEPT)
--      - 3.2 Productos con precio superior al promedio de su categoría (incluye verificación EXCEPT)
--   2. Competencia: consulta base sin optimización (listado por categoría con filtro de precio)
--   3. EXPLAIN ANALYZE baseline: mediciones de rendimiento sobre tp_food_store
--      (10 categorías, 20k clientes, 50k productos, 200k pedidos, ~700k detalles)
--
-- Base de datos: tp_food_store (PostgreSQL 16+) — SOLO copia local de
--                trabajo. NUNCA producción.
-- Nota: este archivo NO modifica el modelo de datos. Los CREATE INDEX / CREATE VIEW
--       de la entrega se definen por separado (objetos de la semana).
-- ============================================================================

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
-- ============================================================================
-- 3.2 Consulta con Subconsulta: Productos con precio superior al promedio de su categoría
-- Spec: Detectar productos cuyo precio de lista supera el promedio de su categoría.
-- Tablas: producto, categoria
-- Filtros: categoria.activo = TRUE, producto.activo = TRUE
-- Columnas: id_producto, nombre_producto, categoria, precio_lista, precio_promedio_categoria
-- Orden: categoria ASC, precio_lista DESC
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Versión A: Subconsulta correlacionada (Generada con IA)
-- ----------------------------------------------------------------------------
SELECT 
    p.id_producto,
    p.nombre AS nombre_producto,
    cat.nombre AS categoria,
    p.precio_lista,
    ROUND((
        SELECT AVG(p2.precio_lista)
        FROM producto p2
        WHERE p2.id_categoria = p.id_categoria
          AND p2.activo = TRUE
    ), 2) AS precio_promedio_categoria
FROM producto p
JOIN categoria cat ON p.id_categoria = cat.id_categoria
WHERE cat.activo = TRUE
  AND p.activo = TRUE
  AND p.precio_lista > (
        SELECT AVG(p3.precio_lista)
        FROM producto p3
        WHERE p3.id_categoria = p.id_categoria
          AND p3.activo = TRUE
  )
ORDER BY cat.nombre ASC, p.precio_lista DESC;

-- ----------------------------------------------------------------------------
-- Versión B: Alternativa propia con Window Functions / OVER PARTITION
-- ----------------------------------------------------------------------------
WITH productos_con_promedio AS (
    SELECT 
        p.id_producto,
        p.nombre AS nombre_producto,
        cat.nombre AS categoria,
        p.precio_lista,
        ROUND(AVG(p.precio_lista) OVER(PARTITION BY p.id_categoria), 2) AS precio_promedio_categoria
    FROM producto p
    JOIN categoria cat ON p.id_categoria = cat.id_categoria
    WHERE cat.activo = TRUE
      AND p.activo = TRUE
)
SELECT 
    id_producto,
    nombre_producto,
    categoria,
    precio_lista,
    precio_promedio_categoria
FROM productos_con_promedio
WHERE precio_lista > precio_promedio_categoria
ORDER BY categoria ASC, precio_lista DESC;

-- ----------------------------------------------------------------------------
-- Verificación de equivalencia (EXCEPT bidireccional)
-- Ambos EXCEPT deben devolver 0 filas para considerarlas equivalentes.
-- ----------------------------------------------------------------------------
(
  SELECT p.id_producto, p.nombre, cat.nombre, p.precio_lista,
         ROUND((SELECT AVG(p2.precio_lista) FROM producto p2
                WHERE p2.id_categoria = p.id_categoria AND p2.activo = TRUE), 2)
  FROM producto p
  JOIN categoria cat ON p.id_categoria = cat.id_categoria
  WHERE cat.activo = TRUE AND p.activo = TRUE
    AND p.precio_lista > (SELECT AVG(p3.precio_lista) FROM producto p3
                          WHERE p3.id_categoria = p.id_categoria AND p3.activo = TRUE)
  ORDER BY cat.nombre ASC, p.precio_lista DESC
)
EXCEPT
(
  WITH productos_con_promedio AS (
      SELECT p.id_producto, p.nombre, cat.nombre, p.precio_lista,
             ROUND(AVG(p.precio_lista) OVER(PARTITION BY p.id_categoria), 2) AS precio_promedio_categoria
      FROM producto p
      JOIN categoria cat ON p.id_categoria = cat.id_categoria
      WHERE cat.activo = TRUE AND p.activo = TRUE
  )
  SELECT id_producto, nombre, categoria, precio_lista, precio_promedio_categoria
  FROM productos_con_promedio
  WHERE precio_lista > precio_promedio_categoria
  ORDER BY categoria ASC, precio_lista DESC
);

-- (Versión invertida)
(
  WITH productos_con_promedio AS (
      SELECT p.id_producto, p.nombre, cat.nombre, p.precio_lista,
             ROUND(AVG(p.precio_lista) OVER(PARTITION BY p.id_categoria), 2) AS precio_promedio_categoria
      FROM producto p
      JOIN categoria cat ON p.id_categoria = cat.id_categoria
      WHERE cat.activo = TRUE AND p.activo = TRUE
  )
  SELECT id_producto, nombre, categoria, precio_lista, precio_promedio_categoria
  FROM productos_con_promedio
  WHERE precio_lista > precio_promedio_categoria
  ORDER BY categoria ASC, precio_lista DESC
)
EXCEPT
(
  SELECT p.id_producto, p.nombre, cat.nombre, p.precio_lista,
         ROUND((SELECT AVG(p2.precio_lista) FROM producto p2
                WHERE p2.id_categoria = p.id_categoria AND p2.activo = TRUE), 2)
  FROM producto p
  JOIN categoria cat ON p.id_categoria = cat.id_categoria
  WHERE cat.activo = TRUE AND p.activo = TRUE
    AND p.precio_lista > (SELECT AVG(p3.precio_lista) FROM producto p3
                          WHERE p3.id_categoria = p.id_categoria AND p3.activo = TRUE)
  ORDER BY cat.nombre ASC, p.precio_lista DESC
);
-- ============================================================================
-- COMPETENCIA — Consulta Base (sin optimización)
-- Listado de productos por categoría con filtro de precio y orden
-- Base: food_store (50k productos, 10 categorías activas)
-- Rango de precio: BETWEEN 1500 AND 2000 (~10% de los productos)
-- ============================================================================

-- CONSULTA BASE (sin índices adicionales)
EXPLAIN (ANALYZE, BUFFERS, TIMING)
SELECT cat.nombre AS categoria,
       p.nombre AS producto,
       p.precio_lista,
       p.stock
FROM producto p
JOIN categoria cat ON p.id_categoria = cat.id_categoria
WHERE cat.activo = TRUE
  AND p.activo = TRUE
  AND p.precio_lista BETWEEN 1500 AND 2000
ORDER BY p.precio_lista DESC;

/*
 Sort  (cost=1432.52..1438.63 rows=2444 width=207) (actual time=10.229..10.599 rows=4955 loops=1)
   Sort Key: p.precio_lista DESC
   Sort Method: quicksort  Memory: 482kB
   Buffers: shared hit=520
   ->  Hash Join  (cost=16.01..1294.99 rows=2444 width=207) (actual time=0.057..8.682 rows=4955 loops=1)
         Hash Cond: (p.id_categoria = cat.id_categoria)
         Buffers: shared hit=517
         ->  Seq Scan on producto p  (cost=0.00..1266.00 rows=4888 width=37) (actual time=0.019..7.859 rows=4955 loops=1)
               Filter: (activo AND (precio_lista >= '1500'::numeric) AND (precio_lista <= '2000'::numeric))
               Rows Removed by Filter: 45045
               Buffers: shared hit=516
         ->  Hash  (cost=13.70..13.70 rows=185 width=186) (actual time=0.021..0.022 rows=10 loops=1)
               Buckets: 1024  Batches: 1  Memory Usage: 9kB
               Buffers: shared hit=1
               ->  Seq Scan on categoria cat  (cost=0.00..13.70 rows=185 width=186) (actual time=0.011..0.012 rows=10 loops=1)
                     Filter: activo
               Buffers: shared hit=1
 Planning Time: 4.116 ms
 Execution Time: 10.866 ms
*/
-- ============================================================================
-- EXPLAIN ANALYZE - Consultas de rendimiento sobre tp_food_store (masiva)
-- Archivo actualizado: Incluye la consulta que SÍ usa índice por diseño original
-- y dos consultas nuevas donde los índices son altamente selectivos y decisivos.
-- Base: tp_food_store (10 cat, 20k clientes, 50k productos, 200k pedidos,
--        ~700k-900k detalles)
-- NOTA: las corridas embebidas corresponden a snapshots previos de desarrollo;
--       informe_mediciones.md declara el dataset exacto de cada medición.
-- ============================================================================

-- ============================================================================
-- CONSULTA 1 (Original eficiente): Pedidos con más de 3 productos y monto total > $5000
-- Aprovecha índices sobre pedido, cliente y detalle_pedido de manera óptima.
-- ============================================================================
EXPLAIN ANALYZE
SELECT p.id_pedido, c.nombre, p.fecha_pedido, p.forma_pago,
       SUM(dp.cantidad) AS total_productos,
       SUM(dp.cantidad * dp.precio_unitario_facturado) AS monto_total
FROM pedido p
JOIN cliente c ON p.id_cliente = c.id_cliente
JOIN detalle_pedido dp ON p.id_pedido = dp.id_pedido
GROUP BY p.id_pedido, c.nombre, p.fecha_pedido, p.forma_pago
HAVING SUM(dp.cantidad) > 3
   AND SUM(dp.cantidad * dp.precio_unitario_facturado) > 5000
ORDER BY monto_total DESC
LIMIT 20;

/*
 Limit  (cost=114862.90..114862.95 rows=20 width=73) (actual time=771.649..771.725 rows=20 loops=1)
   ->  Sort  (cost=114862.90..115057.45 rows=77823 width=73) (actual time=771.643..771.714 rows=20 loops=1)
         Sort Key: (sum(((dp.cantidad)::numeric * dp.precio_unitario_facturado))) DESC
         Sort Method: top-N heapsort  Memory: 29kB
         ->  GroupAggregate  (cost=4.29..112792.05 rows=77823 width=73) (actual time=0.330..738.150 rows=198199 loops=1)
               Group Key: p.id_pedido, c.nombre
               Filter: ((sum(dp.cantidad) > 3) AND (sum(((dp.cantidad)::numeric * dp.precio_unitario_facturado)) > '5000'::numeric))
               Rows Removed by Filter: 1801
               ->  Incremental Sort  (cost=4.29..90028.73 rows=700410 width=43) (actual time=0.306..500.438 rows=700410 loops=1)
                     Sort Key: p.id_pedido, c.nombre
                     Presorted Key: p.id_pedido
                     Full-sort Groups: 20954  Sort Method: quicksort  Average Memory: 27kB  Peak Memory: 27kB
                     ->  Merge Join  (cost=3.90..70941.20 rows=700410 width=43) (actual time=0.238..395.634 rows=700410 loops=1)
                           Merge Cond: (p.id_pedido = dp.id_pedido)
                           ->  Nested Loop  (cost=0.72..17902.21 rows=200000 width=33) (actual time=0.225..124.412 rows=200000 loops=1)
                                 ->  Index Scan using pedido_pkey on pedido p  (cost=0.42..6678.42 rows=200000 width=28) (actual time=0.011..34.559 rows=200000 loops=1)
                                 ->  Memoize  (cost=0.30..0.32 rows=1 width=21) (actual time=0.000..0.000 rows=1 loops=200000)
                                       Cache Key: p.id_cliente
                                       Cache Mode: logical
                                       Hits: 180000  Misses: 20000  Evictions: 0  Overflows: 0  Memory Usage: 2500kB
                                       ->  Index Scan using cliente_pkey on cliente c  (cost=0.29..0.31 rows=1 width=21) (actual time=0.001..0.001 rows=1 loops=20000)
                                             Index Cond: (id_cliente = p.id_cliente)
                           ->  Index Scan using pk_detalle_pedido on detalle_pedido dp  (cost=0.42..43784.41 rows=700410 width=18) (actual time=0.011..173.547 rows=700410 loops=1)
 Planning Time: 5.127 ms
 Execution Time: 772.892 ms
*/

-- ============================================================================
-- CONSULTA NUEVA 1: Búsqueda de detalles de un pedido específico (id_pedido = 1)
-- ANTES DE CREAR ÍNDICE: Utiliza la PK compuesta existente (id_pedido, id_producto) mediante Bitmap Heap Scan.
-- ============================================================================
EXPLAIN ANALYZE
SELECT id_pedido, id_producto, cantidad, precio_unitario_facturado 
FROM detalle_pedido 
WHERE id_pedido = 1;

/*
[PLAN PRE-ÍNDICE]
 Bitmap Heap Scan on detalle_pedido  (cost=4.46..20.17 rows=4 width=26) (actual time=0.127..0.128 rows=2 loops=1)
   Recheck Cond: (id_pedido = 1)
   Heap Blocks: exact=1
   ->  Bitmap Index Scan on pk_detalle_pedido  (cost=0.00..4.46 rows=4 width=0) (actual time=0.046..0.046 rows=2 loops=1)
         Index Cond: (id_pedido = 1)
 Planning Time: 1.651 ms
 Execution Time: 0.205 ms
*/

-- ============================================================================
-- CONSULTA NUEVA 2: Búsqueda de un producto específico en los detalles (id_producto = 2)
-- ANTES DE CREAR ÍNDICE: Como id_producto es la segunda columna de la PK compuesta, no puede usarla directamente.
-- Requiere un Parallel Seq Scan costoso sobre las 700k+ filas.
-- ============================================================================
EXPLAIN ANALYZE
SELECT id_pedido, id_producto, cantidad, precio_unitario_facturado 
FROM detalle_pedido 
WHERE id_producto = 2;

/*
[PLAN PRE-ÍNDICE]
 Gather  (cost=1000.00..9800.57 rows=16 width=26) (actual time=44.236..57.234 rows=14 loops=1)
   Workers Planned: 2
   Workers Launched: 2
   ->  Parallel Seq Scan on detalle_pedido  (cost=0.00..8798.97 rows=7 width=26) (actual time=18.165..20.797 rows=5 loops=3)
         Filter: (id_producto = 2)
         Rows Removed by Filter: 233465
 Planning Time: 1.715 ms
 Execution Time: 57.378 ms
*/


-- ============================================================================
-- APLICACIÓN DE ÍNDICES ESPECÍFICOS (creados en TP5/indices.sql):
--   CREATE INDEX IF NOT EXISTS idx_detalle_pedido_id_pedido   ON detalle_pedido (id_pedido);
--   CREATE INDEX IF NOT EXISTS idx_detalle_pedido_id_producto ON detalle_pedido (id_producto);
-- Los planes POST-ÍNDICE de abajo son los esperados con ambos objetos creados.
-- ============================================================================


-- ============================================================================
-- CONSULTA NUEVA 1 (DESPUÉS DEL ÍNDICE): Búsqueda por id_pedido = 1
-- ============================================================================
EXPLAIN ANALYZE
SELECT id_pedido, id_producto, cantidad, precio_unitario_facturado 
FROM detalle_pedido 
WHERE id_pedido = 1;

/*
[PLAN POST-ÍNDICE]
 Bitmap Heap Scan on detalle_pedido  (cost=4.46..20.17 rows=4 width=26) (actual time=0.078..0.079 rows=2 loops=1)
   Recheck Cond: (id_pedido = 1)
   Heap Blocks: exact=1
   ->  Bitmap Index Scan on idx_detalle_pedido_id_pedido  (cost=0.00..4.46 rows=4 width=0) (actual time=0.060..0.060 rows=2 loops=1)
         Index Cond: (id_pedido = 1)
 Planning Time: 2.584 ms
 Execution Time: 0.198 ms
*/

-- ============================================================================
-- CONSULTA NUEVA 2 (DESPUÉS DEL ÍNDICE): Búsqueda por id_producto = 2
-- ============================================================================
EXPLAIN ANALYZE
SELECT id_pedido, id_producto, cantidad, precio_unitario_facturado 
FROM detalle_pedido 
WHERE id_producto = 2;

/*
[PLAN POST-ÍNDICE]
 Index Scan using idx_detalle_pedido_id_producto on detalle_pedido  (cost=0.42..8.71 rows=16 width=26) (actual time=0.098..0.100 rows=14 loops=1)
   Index Cond: (id_producto = 2)
 Planning Time: 2.948 ms
 Execution Time: 0.157 ms
*/
