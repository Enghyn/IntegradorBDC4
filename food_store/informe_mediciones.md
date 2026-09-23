# Informe de Mediciones y Optimización de Consultas

## Consulta 3.1: Top 10 Clientes por Gasto Total

### 1. Plan y Tiempo PRE-ÍNDICE (Baseline)
- **Tiempo de Ejecución:** `3612.970 ms` (~3.61 segundos)
- **Nodos Principales:** Escaneos secuenciales (`Seq Scan`) en las tablas `detalle_pedido`, `pedido` y `cliente`, requiriendo uso de disco para el ordenamiento (`Sort Method: external merge Disk: 34568kB`).
- **Salida de EXPLAIN ANALYZE:**
Limit  (cost=125879.36..125879.38 rows=10 width=61) (actual time=3578.950..3578.960 rows=10 loops=1)
  Buffers: shared hit=6866, temp read=6632 written=6646
  ->  Sort  (cost=125879.36..125926.94 rows=19033 width=61) (actual time=3578.948..3578.955 rows=10 loops=1)
        Sort Key: (round(sum(((dp.cantidad)::numeric * dp.precio_unitario_facturado)), 2)) DESC
        Sort Method: top-N heapsort  Memory: 26kB
        Buffers: shared hit=6866, temp read=6632 written=6646
        ->  GroupAggregate  (cost=115198.48..125468.06 rows=19033 width=61) (actual time=2544.089..3565.127 rows=19033 loops=1)
              Group Key: c.id_cliente
              Buffers: shared hit=6863, temp read=6632 written=6646
              ->  Sort  (cost=115198.48..116862.49 rows=665606 width=39) (actual time=2544.049..2897.534 rows=665616 loops=1)
                    Sort Key: c.id_cliente, p.id_pedido
                    Sort Method: external merge  Disk: 34568kB
                    Buffers: shared hit=6863, temp read=6632 written=6646
                    ->  Hash Join  (cost=7631.91..32616.54 rows=665606 width=39) (actual time=120.646..1553.396 rows=665616 loops=1)
                          Hash Cond: (p.id_cliente = c.id_cliente)
                          Buffers: shared hit=6860, temp read=2311 written=2311
                          ->  Hash Join  (cost=6948.00..30096.25 rows=699423 width=26) (actual time=114.773..1195.922 rows=699423 loops=1)
                                Hash Cond: (dp.id_pedido = p.id_pedido)
                                Buffers: shared hit=6614, temp read=2311 written=2311
                                ->  Seq Scan on detalle_pedido dp  (cost=0.00..12137.23 rows=699423 width=18) (actual time=0.029..238.783 rows=699423 loops=1)
                                      Buffers: shared hit=5143
                                ->  Hash  (cost=3471.00..3471.00 rows=200000 width=16) (actual time=112.161..112.163 rows=200000 loops=1)
                                      Buckets: 262144  Batches: 2  Memory Usage: 6749kB
                                      Buffers: shared hit=1471, temp written=438
                                      ->  Seq Scan on pedido p  (cost=0.00..3471.00 rows=200000 width=16) (actual time=0.016..40.594 rows=200000 loops=1)
                                            Buffers: shared hit=1471
                          ->  Hash  (cost=446.00..446.00 rows=19033 width=21) (actual time=5.788..5.789 rows=19033 loops=1)
                                Buckets: 32768  Batches: 1  Memory Usage: 1250kB
                                Buffers: shared hit=246
                                ->  Seq Scan on cliente c  (cost=0.00..446.00 rows=19033 width=21) (actual time=0.015..3.011 rows=19033 loops=1)
                                      Filter: activo
                                      Rows Removed by Filter: 967
                                      Buffers: shared hit=246
Planning Time: 9.482 ms
Execution Time: 3612.970 ms

### 2. Indices creados:
- CREATE INDEX idx_cliente_activo
    ON cliente (id_cliente)
    WHERE activo = TRUE;
- CREATE INDEX idx_detalle_pedido_id_pedido
    ON detalle_pedido (id_pedido);
### 3. Plan y Tiempo POST-ÍNDICE
- **Tiempo de Ejecución:** `3478.948 ms`
- **Estrategia de Planificación:** `Seq Scan` secuencial sobre `detalle_pedido`, `pedido` y `cliente`, con ordenamiento externo en disco (`external merge Disk: 34568kB`)[cite: 1].
- **Análisis de Impacto / Conclusión:** Se evidencia que el motor mantiene la estrategia de `Seq Scan` ya que la consulta requiere procesar y agregar la totalidad de las 699,423 filas de `detalle_pedido` (alta Selectividad/Scan Completo) para computar el `SUM` antes del `LIMIT 10`[cite: 1]. El optimizador determina de manera correcta que el escaneo secuencial por páginas reduce el costo total de I/O frente a accesos por árbol B-tree[cite: 1].
- **Salida de EXPLAIN ANALYZE:**
Limit  (cost=125879.36..125879.38 rows=10 width=61) (actual time=3442.344..3442.353 rows=10 loops=1)
  Buffers: shared hit=6860, temp read=6632 written=6646
  ->  Sort  (cost=125879.36..125926.94 rows=19033 width=61) (actual time=3442.342..3442.349 rows=10 loops=1)
        Sort Key: (round(sum(((dp.cantidad)::numeric * dp.precio_unitario_facturado)), 2)) DESC
        Sort Method: top-N heapsort  Memory: 26kB
        Buffers: shared hit=6860, temp read=6632 written=6646
        ->  GroupAggregate  (cost=115198.48..125468.06 rows=19033 width=61) (actual time=2520.674..3427.040 rows=19033 loops=1)
              Group Key: c.id_cliente
              Buffers: shared hit=6860, temp read=6632 written=6646
              ->  Sort  (cost=115198.48..116862.49 rows=665606 width=39) (actual time=2520.608..2824.312 rows=665616 loops=1)
                    Sort Key: c.id_cliente, p.id_pedido
                    Sort Method: external merge  Disk: 34568kB
                    Buffers: shared hit=6860, temp read=6632 written=6646
                    ->  Hash Join  (cost=7631.91..32616.54 rows=665606 width=39) (actual time=122.786..1530.118 rows=665616 loops=1)
                          Hash Cond: (p.id_cliente = c.id_cliente)
                          Buffers: shared hit=6860, temp read=2311 written=2311
                          ->  Hash Join  (cost=6948.00..30096.25 rows=699423 width=26) (actual time=116.850..1159.896 rows=699423 loops=1)
                                Hash Cond: (dp.id_pedido = p.id_pedido)
                                Buffers: shared hit=6614, temp read=2311 written=2311
                                ->  Seq Scan on detalle_pedido dp  (cost=0.00..12137.23 rows=699423 width=18) (actual time=0.023..192.111 rows=699423 loops=1)
                                      Buffers: shared hit=5143
                                ->  Hash  (cost=3471.00..3471.00 rows=200000 width=16) (actual time=113.664..113.665 rows=200000 loops=1)
                                      Buckets: 262144  Batches: 2  Memory Usage: 6749kB
                                      Buffers: shared hit=1471, temp written=438
                                      ->  Seq Scan on pedido p  (cost=0.00..3471.00 rows=200000 width=16) (actual time=0.016..30.043 rows=200000 loops=1)
                                            Buffers: shared hit=1471
                          ->  Hash  (cost=446.00..446.00 rows=19033 width=21) (actual time=5.816..5.817 rows=19033 loops=1)
                                Buckets: 32768  Batches: 1  Memory Usage: 1250kB
                                Buffers: shared hit=246
                                ->  Seq Scan on cliente c  (cost=0.00..446.00 rows=19033 width=21) (actual time=0.015..2.609 rows=19033 loops=1)
                                      Filter: activo
                                      Rows Removed by Filter: 967
                                      Buffers: shared hit=246
Planning Time: 0.494 ms
Execution Time: 3478.948 ms
### 4. Evaluación del Impacto en Escrituras (INSERT)
Se realizó una prueba de carga masiva insertando 100,000 registros aleatorios en la tabla `detalle_pedido` para evaluar el costo de mantenimiento del índice B-tree:
- **Tiempo de inserción SIN índice (`idx_detalle_pedido_id_pedido`):** `9994.689 ms`
- **Tiempo de inserción CON índice (`idx_detalle_pedido_id_pedido`):** `9672.286 ms`
- **Análisis:** En este escenario, el tiempo de inserción está fuertemente dominado por la verificación de restricciones de clave foránea (`fk_detalle_pedido_pedido` y `fk_detalle_pedido_producto`, que consumen ~6 segundos del tiempo total). La presencia del índice secundario sobre `id_pedido` presenta una variación de tiempo despreciable (~3%), lo que demuestra que el costo de actualización del B-tree en memoria/disco es marginal frente a los triggers de validación FK.

### 5. Descarte Explícito de Propuestas por Sobreindexación
- **Propuesta Descartada 1:** Creación de un índice B-tree completo sobre la columna `cliente.activo` (`CREATE INDEX idx_cliente_activo_full ON cliente (activo)`).
  - **Justificación Técnica:** La columna `activo` es de tipo `BOOLEAN` (baja cardinalidad, donde el ~95% de los clientes están en estado `TRUE`). Un índice tradicional completo sería descartado por el optimizador debido a la baja selectividad. En su lugar, se eligió un **Índice Parcial** (`WHERE activo = TRUE`), reduciendo el tamaño en disco y eliminando sobrecostos para registros inactivos.
- **Propuesta Descartada 2:** Creación de un índice compuesto sobre `(id_pedido, id_producto)` en `detalle_pedido`.
  - **Justificación Técnica:** La tabla ya cuenta con una Clave Primaria compuesta sobre `(id_pedido, id_producto)`. PostgreSQL crea automáticamente un índice B-tree único para soportarla, por lo que agregar una propuesta idéntica por parte de la IA representaba un caso directo de **sobreindexación y redundancia**.                                                                                       