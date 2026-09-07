-- ============================================================================
-- EXPLAIN ANALYZE - Consultas de rendimiento sobre tp_food_store (masiva)
-- Archivo actualizado: Incluye la consulta que SÍ usa índice por diseño original
-- y dos consultas nuevas donde los índices son altamente selectivos y decisivos.
-- Base: tp_food_store (10 cat, 20k clientes, 50k productos, 200k pedidos, 700k detalles)
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
-- APLICACIÓN DE ÍNDICES ESPECÍFICOS:
-- CREATE INDEX idx_detalle_pedido_id_pedido ON detalle_pedido (id_pedido);
-- CREATE INDEX idx_detalle_pedido_id_producto ON detalle_pedido (id_producto);
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
