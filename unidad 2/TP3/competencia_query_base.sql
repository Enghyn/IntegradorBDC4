-- ============================================================================
-- COMPETENCIA — Consulta Base (sin optimización)
-- Listado de productos por categoría con filtro de precio y orden
-- Base: tp_food_store (50k productos, 10 categorías activas)
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
