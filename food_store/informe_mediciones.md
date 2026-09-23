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

## Consulta 3.2: Productos con Precio Superior al Promedio de su Categoría

### 1. Plan y Tiempo PRE-ÍNDICE (Baseline Aislado)
- **Tiempo de Ejecución:** `251402.102 ms` (~251.40 segundos / ~4.19 minutos)
- **Planning Time:** `2.305 ms`
- **Nodos Principales:** `Incremental Sort` -> `Nested Loop` -> `Materialize` -> `Index Scan using idx_producto_categoria_activo on producto`. Reevaluación repetida de subconsultas correlacionadas (`SubPlan 1` y `SubPlan 2`) mediante `Bitmap Heap Scan` sobre `p2` y `p3`.
- **Salida de EXPLAIN ANALYZE:**
Incremental Sort  (cost=181047.98..33493893.77 rows=7484 width=243) (actual time=181461.196..251399.468 rows=22425 loops=1)
  Sort Key: cat.nombre, p.precio_lista DESC
  Presorted Key: cat.nombre
  Full-sort Groups: 10  Sort Method: quicksort  Average Memory: 29kB  Peak Memory: 29kB
  Pre-sorted Groups: 10  Sort Method: quicksort  Average Memory: 265kB  Peak Memory: 272kB
  Buffers: shared hit=35099763
  ->  Nested Loop  (cost=0.44..33493596.77 rows=7484 width=243) (actual time=2.990..251198.060 rows=22425 loops=1)
        Join Filter: (cat.id_categoria = p.id_categoria)
        Rows Removed by Join Filter: 201825
        Buffers: shared hit=35099763
        ->  Index Scan using categoria_nombre_key on categoria cat  (cost=0.15..53.70 rows=185 width=186) (actual time=0.046..0.134 rows=10 loops=1)
              Filter: activo
              Buffers: shared hit=2
        ->  Materialize  (cost=0.29..28673695.52 rows=14968 width=41) (actual time=0.160..17266.823 rows=22425 loops=10)
              Buffers: shared hit=23416336
              ->  Index Scan using idx_producto_categoria_activo on producto p  (cost=0.29..28673620.68 rows=14968 width=41) (actual time=1.578..172500.306 rows=22425 loops=1)
                    Filter: (precio_lista > (SubPlan 2))
                    Rows Removed by Filter: 22510
                    Buffers: shared hit=23416336
                    SubPlan 2
                      ->  Aggregate  (cost=638.46..638.47 rows=1 width=32) (actual time=3.821..3.821 rows=1 loops=44935)
                            Buffers: shared hit=23411135
                            ->  Bitmap Heap Scan on producto p3  (cost=55.10..627.23 rows=4491 width=6) (actual time=0.515..2.355 rows=4494 loops=44935)
                                  Recheck Cond: ((id_categoria = p.id_categoria) AND activo)
                                  Heap Blocks: exact=23186460
                                  Buffers: shared hit=23411135
                                  ->  Bitmap Index Scan on idx_producto_categoria_activo  (cost=0.00..53.97 rows=4491 width=0) (actual time=0.374..0.374 rows=4494 loops=44935)
                                        Index Cond: (id_categoria = p.id_categoria)
                                        Buffers: shared hit=224675
        SubPlan 1
          ->  Aggregate  (cost=638.46..638.47 rows=1 width=32) (actual time=3.483..3.483 rows=1 loops=22425)
                Buffers: shared hit=11683425
                ->  Bitmap Heap Scan on producto p2  (cost=55.10..627.23 rows=4491 width=6) (actual time=0.471..2.157 rows=4494 loops=22425)
                      Recheck Cond: ((id_categoria = p.id_categoria) AND activo)
                      Heap Blocks: exact=11571300
                      Buffers: shared hit=11683425
                      ->  Bitmap Index Scan on idx_producto_categoria_activo  (cost=0.00..53.97 rows=4491 width=0) (actual time=0.342..0.342 rows=4494 loops=22425)
                            Index Cond: (id_categoria = p.id_categoria)
                            Buffers: shared hit=112125
Planning Time: 2.305 ms
Execution Time: 251402.102 ms

### 2. Análisis del Impacto y Causa Raíz del Costo de Ejecución (PRE-ÍNDICE)

El tiempo de ejecución baseline (**~251.40 segundos / 4.19 minutos**) confirma una degradación crítica causada por la reevaluación repetitiva de las subconsultas correlacionadas sobre el modelo base:

* **Incapacidad de Index-Only Scan:** El único índice disponible en `producto` para este patrón (`idx_producto_categoria_activo`) incluye únicamente `id_categoria`. Para calcular la función de agregación `AVG(precio_lista)`, el optimizador utiliza el índice para ubicar las filas activas de cada categoría, pero se ve obligado a realizar un **`Bitmap Heap Scan`** para acceder a las páginas de datos (*Heap*) de la tabla y extraer el valor de `precio_lista` en cada iteración.
* **Reevaluación N × M de Subconsultas:** Como `SubPlan 1` (proyección) y `SubPlan 2` (filtro `WHERE`) se evalúan independientemente, la reevaluación acumulada ejecuta **44,935 iteraciones para SubPlan 2** y **22,425 iteraciones para SubPlan 1**, resultando en **34,757,760 lecturas de bloques exactos de heap** (`Heap Blocks: exact`).
* **Saturación de Buffer:** Toda esta operación fuerza un total de **`shared hit=35,099,763`**, sobrecargando la memoria RAM intermedia del motor.

### 3. Indices creados:
- CREATE INDEX IF NOT EXISTS idx_producto_categoria_precio
    ON producto (id_categoria, precio_lista)
    WHERE activo = TRUE;

### 4. Plan y Tiempo POST-ÍNDICE
- **Tiempo de Ejecución:** `149374.371 ms` (~149.37 segundos)
- **Planning Time:** `3.734 ms`
- **Costo Estimado:** Reducido de `33,493,893.77` a `8,540,012.90` (reducción de casi un 75% en el costo del motor).
- **Nodos Optimizado:** Transformación de `Bitmap Heap Scan` a **`Index Only Scan using idx_producto_categoria_precio`** en `SubPlan 1` y `SubPlan 2` con **`Heap Fetches: 0`**.
- **Salida de EXPLAIN ANALYZE:**
```text
Incremental Sort  (cost=46162.14..8540012.90 rows=7486 width=243) (actual time=104979.910..149371.809 rows=22425 loops=1)
  Sort Key: cat.nombre, p.precio_lista DESC
  Presorted Key: cat.nombre
  Full-sort Groups: 10  Sort Method: quicksort  Average Memory: 29kB  Peak Memory: 29kB
  Pre-sorted Groups: 10  Sort Method: quicksort  Average Memory: 265kB  Peak Memory: 272kB
  Buffers: shared hit=1298390 read=174
  ->  Nested Loop  (cost=0.44..8539715.80 rows=7486 width=243) (actual time=1.624..149219.877 rows=22425 loops=1)
        Join Filter: (cat.id_categoria = p.id_categoria)
        Rows Removed by Join Filter: 201825
        Buffers: shared hit=1298390 read=174
        ->  Index Scan using categoria_nombre_key on categoria cat  (cost=0.15..53.70 rows=185 width=186) (actual time=0.010..0.112 rows=10 loops=1)
              Filter: activo
              Buffers: shared hit=2
        ->  Materialize  (cost=0.29..7284487.25 rows=14971 width=41) (actual time=0.094..9997.625 rows=22425 loops=10)
              Buffers: shared hit=867794 read=174
              ->  Index Scan using idx_producto_categoria_activo on producto p  (cost=0.29..7284412.40 rows=14971 width=41) (actual time=0.930..99794.525 rows=22425 loops=1)
                    Filter: (precio_lista > (SubPlan 2))
                    Rows Removed by Filter: 22510
                    Buffers: shared hit=867794 read=174
                    SubPlan 2
                      ->  Aggregate  (cost=162.11..162.12 rows=1 width=32) (actual time=2.205..2.206 rows=1 loops=44935)
                            Buffers: shared hit=862593 read=174
                            ->  Index Only Scan using idx_producto_categoria_precio on producto p3  (cost=0.29..150.88 rows=4491 width=6) (actual time=0.020..1.142 rows=4494 loops=44935)
                                  Index Cond: (id_categoria = p.id_categoria)
                                  Heap Fetches: 0
                                  Buffers: shared hit=862593 read=174
        SubPlan 1
          ->  Aggregate  (cost=162.11..162.12 rows=1 width=32) (actual time=2.181..2.181 rows=1 loops=22425)
                Buffers: shared hit=430594
                ->  Index Only Scan using idx_producto_categoria_precio on producto p2  (cost=0.29..150.88 rows=4491 width=6) (actual time=0.022..1.133 rows=4494 loops=22425)
                      Index Cond: (id_categoria = p.id_categoria)
                      Heap Fetches: 0
                      Buffers: shared hit=430594
Planning Time: 3.734 ms
Execution Time: 149374.371 ms
```

### 5. Conclusiones y Comparación Técnica

**Aceleración y Reducción de I/O:** El tiempo total de ejecución se redujo de 251.40 segundos a 149.37 segundos (~102 segundos ganados), mientras que los accesos a memoria intermediarios (shared hits) cayeron de 35,099,763 a solo 1,298,390 (una reducción drástica de más del 96% de lecturas).

**Eliminación del Acceso al Heap:** La métrica `Heap Fetches: 0` en las subconsultas demuestra que PostgreSQL resolvió la función de agregación `AVG(precio_lista)` leyendo únicamente las páginas del índice B-Tree, omitiendo por completo los accesos al Heap de la tabla base.

### 6. Justificación de Propuestas Descartadas (Punto 6)

**Índice B-Tree completo sobre producto(activo):** Descartado por baja cardinalidad (tipo BOOLEAN con ~95% en TRUE). Un índice completo no ofrece selectividad útil y sería ignorado por el motor. Se utilizó exitosamente la condición parcial `WHERE activo = TRUE`.

**Índice simple sobre producto(precio_lista) sin id_categoria:** Descartado porque las subconsultas agrupan estrictamente por `id_categoria`. Un índice sin la clave de correlación no permite localizar eficientemente los precios por categoría, resultando ineficaz frente a las subconsultas.
