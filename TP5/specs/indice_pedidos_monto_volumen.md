# SPEC-003 — Optimización de la Consulta de Pedidos con Volumen y Monto Elevado

**Archivo afectado:** `TP5/queries.sql` (Consulta 1 / 3.3)
**Base de datos:** `tp_food_store` (PostgreSQL)
**Fecha:** 2025-07
**Estado:** Propuesta

---

## 1. Objetivo

Reducir el costo de ejecución de la consulta que identifica pedidos con más de 3 productos
y monto total superior a $5.000, asegurando que el planificador de PostgreSQL disponga de
índices explícitos sobre las claves foráneas participantes en los JOINs —
`detalle_pedido.id_pedido` y `pedido.id_cliente` — para habilitar estrategias de Merge Join
e Index Scan sobre las tablas de mayor volumen, y evitar regresiones a Seq Scan si los
índices actuales fueran eliminados o el optimizador recalibra los estimados de costo con
crecimientos futuros del dataset.

### Consulta afectada

```sql
-- queries.sql — Consulta 1 / 3.3: Pedidos con más de 3 productos y monto total > $5000
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
```

---

## 2. Contexto del sistema

| Parámetro                       | Valor                                    |
|---------------------------------|------------------------------------------|
| Motor                           | PostgreSQL                               |
| Base de datos                   | `tp_food_store`                         |
| Volumen — `cliente`             | 20.000 filas                             |
| Volumen — `pedido`              | 200.000 filas                            |
| Volumen — `detalle_pedido`      | ~700.000 filas                           |
| Cardinalidad media del JOIN     | ~3,5 detalles por pedido                 |
| Filas post-HAVING               | ~198.199 pedidos (de 200.000 totales)    |

---

## 3. Frecuencia estimada de ejecución

**Alta.** La consulta alimenta reportes operativos de alto valor (pedidos relevantes por
volumen y facturación), ejecutada recurrentemente en paneles de gestión y análisis comercial.
Su latencia impacta directamente la experiencia del usuario en dashboards gerenciales.

---

## 4. Columnas participantes

| Tabla            | Columna                      | Rol en la consulta                                      |
|------------------|------------------------------|---------------------------------------------------------|
| `pedido`         | `id_pedido`                  | PK; clave JOIN con `detalle_pedido`; `GROUP BY`         |
| `pedido`         | `id_cliente`                 | Clave JOIN con `cliente`; FK                            |
| `pedido`         | `fecha_pedido`               | Proyección; `GROUP BY`                                  |
| `pedido`         | `forma_pago`                 | Proyección; `GROUP BY`                                  |
| `cliente`        | `id_cliente`                 | PK; clave JOIN con `pedido`                             |
| `cliente`        | `nombre`                     | Proyección; `GROUP BY`                                  |
| `detalle_pedido` | `id_pedido`                  | FK; clave JOIN con `pedido`                             |
| `detalle_pedido` | `cantidad`                   | Argumento de `SUM`; condición `HAVING`                  |
| `detalle_pedido` | `precio_unitario_facturado`  | Argumento de expresión `SUM`; condición `HAVING`        |

---

## 5. Diagnóstico del estado actual

### 5.1 Índices existentes relevantes

| Índice                  | Tabla            | Columna(s)                     | Tipo                  |
|-------------------------|------------------|--------------------------------|-----------------------|
| `pedido_pkey`           | `pedido`         | `id_pedido`                    | PK (btree)            |
| `idx_pedido_cliente`    | `pedido`         | `id_cliente`                   | btree                 |
| `cliente_pkey`          | `cliente`        | `id_cliente`                   | PK (btree)            |
| `pk_detalle_pedido`     | `detalle_pedido` | `(id_pedido, id_producto)`     | PK compuesta (btree)  |

### 5.2 Plan de ejecución baseline

El plan capturado con `EXPLAIN ANALYZE` sobre el dataset completo arroja:

```
Limit  (cost=114862.90..114862.95 rows=20 width=73)
       (actual time=771.649..771.725 rows=20 loops=1)
  →  Sort  [top-N heapsort  Memory: 29kB]
       →  GroupAggregate  [rows=198.199; Rows Removed by Filter: 1801]
            →  Incremental Sort  [Presorted Key: p.id_pedido]
                 →  Merge Join  (Merge Cond: p.id_pedido = dp.id_pedido)
                      →  Nested Loop  [rows=200.000]
                           →  Index Scan using pedido_pkey on pedido p
                           →  Memoize → Index Scan using cliente_pkey on cliente c
                      →  Index Scan using pk_detalle_pedido on detalle_pedido dp
Execution Time: 772.892 ms
```

### 5.3 Problemas identificados

1. **Dependencia implícita en la PK compuesta para el JOIN de `detalle_pedido`:**
   El JOIN `pedido.id_pedido = detalle_pedido.id_pedido` se resuelve mediante
   `Index Scan using pk_detalle_pedido`, aprovechando que `id_pedido` es la primera columna
   de la PK compuesta `(id_pedido, id_producto)`. Este comportamiento es correcto en el
   estado actual, pero un índice dedicado sobre `detalle_pedido(id_pedido)` hace explícita
   y documentada esta dependencia de acceso, garantizando que el planificador siempre
   disponga de un índice simple para este patrón de JOIN sin depender de la semántica de la
   PK compuesta.

2. **Ausencia de índice explícito sobre `detalle_pedido(id_pedido)` dedicado a esta FK:**
   PostgreSQL no crea automáticamente índices sobre columnas de clave foránea — sólo sobre
   PK y UNIQUE. La PK compuesta `(id_pedido, id_producto)` actualmente cubre el acceso por
   `id_pedido` dado que es la columna líder del árbol B-tree, pero si la PK fuera redefinida
   con otro orden de columnas, o si el optimizador eligiera un plan alternativo ante un
   crecimiento significativo del volumen, el Merge Join sobre `id_pedido` podría degradarse
   a un Seq Scan costoso sobre las ~700.000 filas.

3. **Resolución del JOIN `pedido → cliente` con dependencia del índice de schema:**
   El índice `idx_pedido_cliente` (definido en `schema.sql`) habilita el acceso a `pedido`
   ordenado por `id_cliente`, utilizado en el Nested Loop con Memoize sobre `cliente_pkey`.
   El índice propuesto `idx_pedido_id_cliente` es funcionalmente equivalente; su creación
   con `IF NOT EXISTS` lo hace idempotente. En entornos donde `schema.sql` no incluyera
   `idx_pedido_cliente` — por ejemplo, una instancia de prueba creada a partir de un schema
   base mínimo — la ausencia de este índice forzaría un Seq Scan sobre las 200.000 filas de
   `pedido` para resolver el JOIN con `cliente`.

---

## 6. Solución propuesta

Crear dos índices secundarios explícitos sobre las claves foráneas participantes en los
JOINs, **sin modificar el modelo de datos ni las tablas base**.

### Índice 1 — Índice sobre `detalle_pedido(id_pedido)`

```sql
CREATE INDEX IF NOT EXISTS idx_detalle_pedido_id_pedido
    ON detalle_pedido (id_pedido);
```

**Justificación:**

1. **Independencia respecto a la PK compuesta:** desambigua el acceso por FK de la
   semántica de la clave primaria `(id_pedido, id_producto)`. El planificador puede
   seleccionar un Index Scan más directo sobre las ~700.000 filas durante el Merge Join,
   sin necesidad de considerar la segunda columna de la PK.

2. **Habilitación de Merge Join estable:** al tener un índice ordenado por `id_pedido`,
   el planificador puede ejecutar un Merge Join eficiente entre `pedido` (ordenado por
   `pedido_pkey`) y `detalle_pedido` (ordenado por `idx_detalle_pedido_id_pedido`),
   evitando un Hash Join con uso de disco ante crecimientos de volumen.

3. **Idempotencia con SPEC-001:** este índice fue propuesto también por SPEC-001 para la
   consulta 3.1. La cláusula `IF NOT EXISTS` garantiza que ambas specs coexistan sin
   conflicto ni duplicación de objetos.

### Índice 2 — Índice sobre `pedido(id_cliente)`

```sql
CREATE INDEX IF NOT EXISTS idx_pedido_id_cliente
    ON pedido (id_cliente);
```

**Justificación:**

1. **Formalización del índice de apoyo para la FK:** el schema base define `idx_pedido_cliente`
   con el mismo propósito. El índice aquí propuesto es funcionalmente equivalente; la cláusula
   `IF NOT EXISTS` garantiza idempotencia si `idx_pedido_cliente` ya existe.

2. **Habilitación del Nested Loop con Memoize:** el índice permite localizar eficientemente
   los pedidos agrupados por `id_cliente` durante el Nested Loop, combinado con el
   Memoize sobre `cliente_pkey` para cachear las 20.000 filas de `cliente` sin repetir
   accesos al heap por cada uno de los 200.000 pedidos.

3. **Cobertura ante schema base mínimo:** en entornos donde `idx_pedido_cliente` no existiera,
   este índice evita el Seq Scan sobre `pedido` en el paso del JOIN con `cliente`.

---

## 7. Propuestas alternativas descartadas

### 7.1 Índice sobre columnas de agregación `cantidad` o `precio_unitario_facturado` en `detalle_pedido`

```sql
-- DESCARTADO
CREATE INDEX idx_detalle_cantidad ON detalle_pedido (cantidad);
CREATE INDEX idx_detalle_precio   ON detalle_pedido (precio_unitario_facturado);
```

**Justificación del descarte:** Las condiciones `HAVING SUM(dp.cantidad) > 3` y
`HAVING SUM(dp.cantidad * dp.precio_unitario_facturado) > 5000` son **filtros post-agrupamiento**
que operan sobre el resultado agregado por pedido, no sobre filas individuales de
`detalle_pedido`. PostgreSQL no puede usar un índice B-tree para evaluar un predicado sobre
el resultado de una función de agregación (`SUM`). El motor debe materializar todos los
grupos y calcular los agregados antes de aplicar el filtro `HAVING`; un índice sobre
`cantidad` o `precio_unitario_facturado` no aporta selectividad previa al agrupamiento y
sólo encarecería las operaciones de escritura (`INSERT`, `UPDATE`) sobre `detalle_pedido`.

### 7.2 Índice compuesto sobre `pedido(fecha_pedido, forma_pago)`

```sql
-- DESCARTADO
CREATE INDEX idx_pedido_fecha_pago ON pedido (fecha_pedido, forma_pago);
```

**Justificación del descarte:** Las columnas `fecha_pedido` y `forma_pago` participan
únicamente en la **proyección** (`SELECT`) y en el **`GROUP BY`**, no en ningún predicado
de filtrado de filas previo al agrupamiento (`WHERE` o condición de JOIN). El planificador
no puede usar un índice B-tree para acelerar la agregación de grupos cuando no hay un filtro
de igualdad o rango sobre esas columnas antes del `GROUP BY`. Un índice sobre
`(fecha_pedido, forma_pago)` no reduciría el número de filas leídas ni aceleraría el Merge
Join; sólo incrementaría el overhead de mantenimiento en cada `INSERT` en `pedido`,
encareciendo las escrituras de la carga masiva sin beneficio para esta consulta.

---

## 8. Criterios de aceptación

### CA-1 — Uso de índices en los nodos de JOIN

El plan de ejecución (`EXPLAIN ANALYZE`) debe mostrar al menos uno de los siguientes
nodos en reemplazo de `Seq Scan` sobre las tablas de mayor volumen:

- `Index Scan using idx_detalle_pedido_id_pedido on detalle_pedido`
- `Bitmap Index Scan on idx_detalle_pedido_id_pedido`
- `Index Scan using idx_pedido_id_cliente on pedido` o su equivalente `idx_pedido_cliente`

### CA-2 — Reducción o estabilidad del tiempo de ejecución demostrada con EXPLAIN (ANALYZE, BUFFERS, TIMING)

El tiempo de ejecución post-índice medido con `EXPLAIN (ANALYZE, BUFFERS, TIMING)` debe ser
menor o igual al baseline de **772 ms**. La mejora o equivalencia debe quedar documentada
comparando los planes pre/post-índice en el archivo de informe de mediciones.

```sql
-- Medición post-índice (ejecutar después de CREATE INDEX):
EXPLAIN (ANALYZE, BUFFERS, TIMING)
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
```

### CA-3 — Transformación de Seq Scan a Index Scan o Bitmap Index Scan

El plan post-índice **no debe mostrar** `Seq Scan` sobre `detalle_pedido` ni sobre `pedido`.
Se acepta que el planificador mantenga el plan de Merge Join + Index Scan ya observado en el
baseline (lo que confirma que los índices son utilizados correctamente desde el principio).

En entornos donde los índices propuestos no existieran previamente, la creación de estos
índices debe producir la transición:

```
Seq Scan on pedido          →  Index Scan using idx_pedido_id_cliente on pedido
Seq Scan on detalle_pedido  →  Index Scan using idx_detalle_pedido_id_pedido on detalle_pedido
```

### CA-4 — Sin modificación del modelo de datos

La solución no debe incluir ningún `ALTER TABLE`, `DROP COLUMN`, ni cambio de tipo de dato
en las tablas `pedido`, `cliente` o `detalle_pedido`.

### CA-5 — Equivalencia funcional del resultado

La consulta debe retornar exactamente el mismo conjunto de filas antes y después de la
creación de los índices. Verificar ejecutando la consulta con y sin los índices y comparando
los 20 registros del `LIMIT` (mismo `id_pedido`, mismo `monto_total`, mismo orden descendente).

---

## 9. Objetos a crear

```sql
-- Objeto 1: índice sobre detalle_pedido para agilizar el JOIN por id_pedido
-- Tipo: B-tree simple (una columna)
-- Justificación: habilita Merge Join eficiente entre pedido y detalle_pedido,
--                independizando el plan de acceso de la PK compuesta.
--                Compartido con SPEC-001; IF NOT EXISTS garantiza idempotencia.
CREATE INDEX IF NOT EXISTS idx_detalle_pedido_id_pedido
    ON detalle_pedido (id_pedido);

-- Objeto 2: índice sobre pedido para agilizar el JOIN por id_cliente
-- Tipo: B-tree simple (una columna)
-- Justificación: habilita el Nested Loop con Memoize entre pedido y cliente,
--                evitando Seq Scan sobre las 200.000 filas de pedido en schemas
--                base que no incluyan idx_pedido_cliente.
CREATE INDEX IF NOT EXISTS idx_pedido_id_cliente
    ON pedido (id_cliente);
```

> Estos objetos deben definirse en `TP5/indices.sql`, **no** en `schema.sql`
> ni en `queries.sql`. Dado que `idx_detalle_pedido_id_pedido` ya fue propuesto por SPEC-001
> y `idx_pedido_cliente` ya existe en `schema.sql`, las cláusulas `IF NOT EXISTS` garantizan
> idempotencia en todos los entornos.

---

## 10. Cobertura adicional — índice de búsqueda por producto (Objeto 4 de `indices.sql`)

El workload de `TP5/queries.sql` incluye además una consulta puntual de negocio
(`Consulta Nueva 2: WHERE id_producto = n`) que no puede usar la PK compuesta
`(id_pedido, id_producto)` porque `id_producto` es la **segunda** columna del árbol.
Para ese patrón se crea:

```sql
CREATE INDEX IF NOT EXISTS idx_detalle_pedido_id_producto
    ON detalle_pedido (id_producto);
```

- **Evidencia (queries.sql, Consulta Nueva 2):** el plan pasa de
  `Parallel Seq Scan on detalle_pedido` (57.378 ms) a
  `Index Scan using idx_detalle_pedido_id_producto` (0.157 ms).
- **Justificación del descarte implícito:** no se propone también `(id_producto, cantidad)`
  ni índices sobre las columnas de agregación ya descartadas en la sección 7.

---

## 11. Fuera de alcance

- Modificación de las tablas base (`ALTER TABLE`).
- Creación de vistas materializadas o tablas de resumen.
- Reescritura de la consulta a una forma alternativa (CTE, window functions).
- Ajuste de parámetros de configuración de PostgreSQL (`work_mem`, `enable_seqscan`, etc.).
- Optimización de la consulta 3.1 (ranking de clientes): cubierta en SPEC-001.
- Optimización de la consulta 3.2 (productos sobre el promedio de categoría): cubierta en SPEC-002.
- Eliminación o modificación de `idx_pedido_cliente` definido en `schema.sql`.
