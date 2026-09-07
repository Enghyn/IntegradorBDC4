-- ============================================================================
-- COMPETENCIA — Equipo A
-- Estrategia: Índice B-tree simple sobre precio_lista (parcial, solo activos)
-- ============================================================================

-- ÍNDICE APLICADO:
-- CREATE INDEX idx_producto_precio_simple ON producto (precio_lista) WHERE activo = TRUE;

-- CONSULTA OPTIMIZADA (misma query, distinto plan por el índice)
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
 Sort  (cost=862.24..868.35 rows=2444 width=207) (actual time=5.434..5.719 rows=4955 loops=1)
   Sort Key: p.precio_lista DESC
   Sort Method: quicksort  Memory: 482kB
   Buffers: shared hit=520 read=15
   ->  Hash Join  (cost=122.40..724.70 rows=2444 width=207) (actual time=0.535..4.020 rows=4955 loops=1)
         Hash Cond: (p.id_categoria = cat.id_categoria)
         Buffers: shared hit=517 read=15
         ->  Bitmap Heap Scan on producto p  (cost=106.39..695.71 rows=4888 width=37) (actual time=0.494..3.014 rows=4955 loops=1)
               Recheck Cond: ((precio_lista >= '1500'::numeric) AND (precio_lista <= '2000'::numeric) AND activo)
               Heap Blocks: exact=516
               Buffers: shared hit=516 read=15
               ->  Bitmap Index Scan on idx_producto_precio_simple  (cost=0.00..105.17 rows=4888 width=0) (actual time=0.436..0.436 rows=4955 loops=1)
                     Index Cond: ((precio_lista >= '1500'::numeric) AND (precio_lista <= '2000'::numeric))
                     Buffers: shared read=15
         ->  Hash  (cost=13.70..13.70 rows=185 width=186) (actual time=0.024..0.025 rows=10 loops=1)
               Buckets: 1024  Batches: 1  Memory Usage: 9kB
               Buffers: shared hit=1
               ->  Seq Scan on categoria cat  (cost=0.00..13.70 rows=185 width=186) (actual time=0.014..0.015 rows=10 loops=1)
                     Filter: activo
               Buffers: shared hit=1
 Planning Time: 4.477 ms
 Execution Time: 6.001 ms
*/
