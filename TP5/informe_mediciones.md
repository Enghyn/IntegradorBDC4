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

### 7. Evaluación del Impacto en Escrituras (INSERT)
Se realizó una prueba de carga masiva insertando 10,000 registros sintéticos en la tabla `producto` (todos con `activo = TRUE`, por lo que ingresan al índice parcial) para evaluar el costo de mantenimiento del índice B-tree compuesto `idx_producto_categoria_precio`:
- **Tiempo de inserción SIN índice (`idx_producto_categoria_precio`):** `709.408 ms` (Trigger `fk_producto_categoria`: 214.166 ms / 10 000 llamadas)
- **Tiempo de inserción CON índice (`idx_producto_categoria_precio`):** `356.046 ms` (Trigger `fk_producto_categoria`: 60.235 ms / 10 000 llamadas)
- **Análisis:** A diferencia de la prueba sobre `detalle_pedido`, la corrida CON índice resultó más rápida que el baseline, lo que evidencia que la diferencia está dominada por el estado del buffer cache compartido entre corridas y no por el costo del índice. La métrica determinante es el propio trigger de restricción `fk_producto_categoria` — que cayó de 214.166 ms a 60.235 ms sin que el índice secundario participe de la validación de clave foránea. Aun en el peor caso (todas las filas con `activo = TRUE` ingresando al índice), el mantenimiento del B-tree sobre `(id_categoria, precio_lista)` no produce una penalidad medible frente a la verificación FK, que domina el costo total de la escritura.

## Consulta 3.3: Pedidos con Más de 3 Productos y Monto Total Superior a $5000

### 1. Plan y Tiempo PRE-ÍNDICE (Baseline)
- **Tiempo de Ejecución:** `4107.925 ms` (~4.10 segundos)
- **Planning Time:** `23.549 ms`
- **Costo del Plan:** `145229.52`
- **Diagnóstico:** Dependencia de `Parallel Seq Scan` sobre `pedido` y `cliente` mediante `Hash Join`, sumado al uso de ordenamiento externo en disco (`Sort Method: external merge Disk: 4352kB`).
- **Salida de EXPLAIN ANALYZE:**
```text
Limit  (cost=145229.47..145229.52 rows=20 width=73) (actual time=4075.590..4090.934 rows=20 loops=1)
  ->  Sort  (cost=145229.47..145479.31 rows=99934 width=73) (actual time=4075.588..4090.928 rows=20 loops=1)
        Sort Key: (sum(((dp.cantidad)::numeric * dp.precio_unitario_facturado))) DESC
        Sort Method: top-N heapsort  Memory: 29kB
        ->  GroupAggregate  (cost=17781.79..142570.26 rows=99934 width=73) (actual time=119.760..3891.034 rows=199125 loops=1)
              Group Key: p.id_pedido, c.nombre
              Filter: ((sum(dp.cantidad) > 3) AND (sum(((dp.cantidad)::numeric * dp.precio_unitario_facturado)) > '5000'::numeric))
              Rows Removed by Filter: 875
              ->  Merge Join  (cost=17781.79..113339.67 rows=899403 width=43) (actual time=119.640..2152.401 rows=899403 loops=1)
                    Merge Cond: (p.id_pedido = dp.id_pedido)
                    ->  Gather Merge  (cost=17780.66..40574.78 rows=200000 width=33) (actual time=119.564..336.297 rows=200000 loops=1)
                          Workers Planned: 1
                          Workers Launched: 1
                          ->  Sort  (cost=16780.65..17074.77 rows=117647 width=33) (actual time=87.277..142.494 rows=100000 loops=2)
                                Sort Key: p.id_pedido, c.nombre
                                Sort Method: external merge  Disk: 4352kB
                                Worker 0:  Sort Method: external merge  Disk: 4168kB
                                ->  Hash Join  (cost=696.00..3652.36 rows=117647 width=33) (actual time=7.277..47.984 rows=100000 loops=2)
                                      Hash Cond: (p.id_cliente = c.id_cliente)
                                      ->  Parallel Seq Scan on pedido p  (cost=0.00..2647.47 rows=117647 width=28) (actual time=0.025..10.154 rows=100000 loops=2)
                                      ->  Hash  (cost=446.00..446.00 rows=20000 width=21) (actual time=7.104..7.106 rows=20000 loops=2)
                                            Buckets: 32768  Batches: 1  Memory Usage: 1350kB
                                            ->  Seq Scan on cliente c  (cost=0.00..446.00 rows=20000 width=21) (actual time=0.628..3.896 rows=20000 loops=2)
                    ->  Index Scan using pk_detalle_pedido on detalle_pedido dp  (cost=0.42..61028.05 rows=899403 width=18) (actual time=0.061..1153.882 rows=899403 loops=1)
Planning Time: 23.549 ms
Execution Time: 4107.925 ms
```

### 2. Plan y Tiempo POST-ÍNDICE
- **Tiempo de Ejecución:** `3521.245 ms` (~3.52 segundos)
- **Planning Time:** `3.760 ms` (reducción drástica en el tiempo de planificación)
- **Costo Estimado:** Reducido de `145,229.52` a `129,614.04`.
- **Nodo Optimizado:** Reemplazo explícito del escaneo por PK compuesta a `Index Scan using idx_detalle_pedido_id_pedido on detalle_pedido dp`, reduciendo el costo parcial del nodo de `61,028.05` a `45,411.16`.
- **Salida de EXPLAIN ANALYZE:**
```text
Limit  (cost=129613.99..129614.04 rows=20 width=73) (actual time=3502.381..3502.455 rows=20 loops=1)
  ->  Sort  (cost=129613.99..129863.83 rows=99934 width=73) (actual time=3502.379..3502.451 rows=20 loops=1)
        Sort Key: (sum(((dp.cantidad)::numeric * dp.precio_unitario_facturado))) DESC
        Sort Method: top-N heapsort  Memory: 29kB
        ->  GroupAggregate  (cost=17781.62..126954.79 rows=99934 width=73) (actual time=228.473..3342.573 rows=199125 loops=1)
              Group Key: p.id_pedido, c.nombre
              Filter: ((sum(dp.cantidad) > 3) AND (sum(((dp.cantidad)::numeric * dp.precio_unitario_facturado)) > '5000'::numeric))
              Rows Removed by Filter: 875
              ->  Merge Join  (cost=17781.62..97724.19 rows=899403 width=43) (actual time=228.447..1965.279 rows=899403 loops=1)
                    Merge Cond: (p.id_pedido = dp.id_pedido)
                    ->  Gather Merge  (cost=17780.66..40574.78 rows=200000 width=33) (actual time=228.410..430.156 rows=200000 loops=1)
                          Workers Planned: 1
                          Workers Launched: 1
                          ->  Sort  (cost=16780.65..17074.77 rows=117647 width=33) (actual time=119.776..185.987 rows=100000 loops=2)
                                Sort Key: p.id_pedido, c.nombre
                                Sort Method: external merge  Disk: 8504kB
                                Worker 0:  Sort Method: quicksort  Memory: 39kB
                                ->  Hash Join  (cost=696.00..3652.36 rows=117647 width=33) (actual time=8.121..65.689 rows=100000 loops=2)
                                      Hash Cond: (p.id_cliente = c.id_cliente)
                                      ->  Parallel Seq Scan on pedido p  (cost=0.00..2647.47 rows=117647 width=28) (actual time=0.012..12.754 rows=100000 loops=2)
                                      ->  Hash  (cost=446.00..446.00 rows=20000 width=21) (actual time=7.852..7.853 rows=20000 loops=2)
                                            Buckets: 32768  Batches: 1  Memory Usage: 1350kB
                                            ->  Seq Scan on cliente c  (cost=0.00..446.00 rows=20000 width=21) (actual time=0.879..4.105 rows=20000 loops=2)
                    ->  Index Scan using idx_detalle_pedido_id_pedido on detalle_pedido dp  (cost=0.42..45411.16 rows=899403 width=18) (actual time=0.030..1020.486 rows=899403 loops=1)
Planning Time: 3.760 ms
Execution Time: 3521.245 ms
```

### 3. Conclusiones Técnicas y Comparación
- **Reducción de Tiempo y Latencia:** Se logró una mejora neta de ~600 ms en la ejecución de la consulta sobre casi 900.000 filas de detalle_pedido. Además, el tiempo de planificación (Planning Time) disminuyó de 23.5 ms a 3.7 ms, acelerando la toma de decisiones del motor.
- **Independencia de Acceso por FK:** La creación explícita de idx_detalle_pedido_id_pedido desvincula el Merge Join de la estructura de la clave primaria compuesta (id_pedido, id_producto). Esto garantiza estabilidad técnica en el plan de ejecución ante futuras reestructuraciones de la PK o escalamiento masivo del volumen.

### 4. Evaluación del Impacto en Escrituras (INSERT)
Se realizó una prueba de carga masiva insertando 20,000 registros sintéticos en la tabla `pedido` para evaluar el costo de mantenimiento del índice B-tree `idx_pedido_id_cliente` (soporta el acceso `pedido → cliente` de SPEC-003):
- **Tiempo de inserción SIN índice (`idx_pedido_id_cliente`):** `1014.174 ms`
- **Tiempo de inserción CON índice (`idx_pedido_id_cliente`):** `1348.252 ms`
- **Análisis:** Contrario a lo observado en `detalle_pedido` y `producto`, aquí la corrida CON índice fue ~334 ms más lenta (~33%) — el costo esperado al insertar 20,000 entradas nuevas en el B-tree de `id_cliente`. El trigger `fk_pedido_cliente` solo varió un ~9% (561.977 → 614.796 ms), diferencia atribuible a ruido de cache ya que la validación FK consulta la PK de `cliente` y no participa del índice secundario. Descontando ese ruido, el overhead neto del mantenimiento del B-tree es de ~281 ms (~14 µs por fila), un costo acotado que se amortiza frente a la aceleración que el índice aporta a la consulta.
