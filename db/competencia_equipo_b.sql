-- ============================================================================
-- COMPETENCIA — Equipo B
-- Estrategia: Índice covering (INCLUDE) para Index Only Scan
-- ============================================================================

-- ÍNDICE APLICADO:
-- CREATE INDEX idx_producto_precio_covering ON producto (precio_lista)
--   INCLUDE (id_categoria, nombre, stock)
--   WHERE activo = TRUE;

-- CONSULTA OPTIMIZADA (misma query, distinto plan por el índice covering)
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
 Nested Loop  (cost=0.57..366.10 rows=2444 width=207) (actual time=0.185..2.144 rows=4955 loops=1)
   Buffers: shared hit=21 read=39
   ->  Index Only Scan Backward using idx_producto_precio_covering on producto p  (cost=0.41..242.17 rows=4888 width=37) (actual time=0.152..0.911 rows=4955 loops=1)
         Index Cond: ((precio_lista >= '1500'::numeric) AND (precio_lista <= '2000'::numeric))
         Heap Fetches: 0
         Buffers: shared hit=1 read=39
   ->  Memoize  (cost=0.16..0.18 rows=1 width=186) (actual time=0.000..0.000 rows=1 loops=4955)
         Cache Key: p.id_categoria
         Cache Mode: logical
         Hits: 4945  Misses: 10  Evictions: 0  Overflows: 0  Memory Usage: 2kB
         Buffers: shared hit=20
         ->  Index Scan using categoria_pkey on categoria cat  (cost=0.15..0.17 rows=1 width=186) (actual time=0.003..0.003 rows=1 loops=10)
               Index Cond: (id_categoria = p.id_categoria)
               Filter: activo
               Buffers: shared hit=20
 Planning Time: 5.504 ms
 Execution Time: 2.327 ms
*/
