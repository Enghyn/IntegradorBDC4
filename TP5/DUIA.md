# DUIA — Bitácora de uso de IA
**Proyecto:** Food Store (TPI) — BDD II

---

## Herramientas utilizadas

- **Kiro** — especificación de las vistas (specs en `TP5/specs/`).
- **OpenCode** — generación del script SQL `TP5/views.sql` a partir de los specs.
- **psql** — ejecución y verificación de equivalencia (`EXCEPT` bidireccional).
- **Dbeaver** — (medición y profiling mediante `EXPLAIN (ANALYZE, BUFFERS, TIMING)`)

> Otras herramientas de IA: NO se utilizaron herramientas de IA fuera de las indicadas
> por la cátedra para esta parte.

---

## Bitácora de interacciones
## Parte A — Índices y Optimización de Consultas

**Herramientas utilizadas:** Kiro (especificación de specs en `TP5/specs/`), OpenCode (generación y edición del script DDL `TP5/indices.sql`) y DBeaver (medición y profiling mediante `EXPLAIN (ANALYZE, BUFFERS, TIMING)`).  
**Propósito:** Identificar cuellos de botella en las consultas analíticas del sistema, diseñar índices secundarios/parciales en base al workload real y validar técnicamente la aceleración de tiempos de respuesta y reducción de I/O.

---

### Interacción 1 — Spec de `SPEC-001` (Consulta 3.1: Top 10 Clientes por Gasto Total)

- **Prompt/spec entregado a la IA:** "Diseñar una estrategia de indexación sobre `cliente` y `detalle_pedido` para optimizar el JOIN y filtrado de la consulta de top clientes por gasto total."
- **Propuesta de la IA:** Crear un índice parcial sobre `cliente(id_cliente) WHERE activo = TRUE` (`idx_cliente_activo`) y un índice sobre `detalle_pedido(id_pedido)` (`idx_detalle_pedido_id_pedido`).
- **Aceptado:** Sí. Se confirmó que el índice parcial en `cliente` evita indexar filas inactivas y que el índice en `detalle_pedido` optimiza el acceso por clave foránea en la unión de pedidos.
- **Modificado:** Ninguno. Se adoptaron las sentencias DDL exactas garantizando idempotencia (`CREATE INDEX IF NOT EXISTS`).
- **Descartado:** Crear índices simples sobre columnas de agregación como `cantidad` o `precio_unitario_facturado`, por considerar que no aportan selectividad previa al agrupamiento y encarecen las operaciones de escritura.

---

### Interacción 2 — Spec de `SPEC-002` (Consulta 3.2: Productos sobre Promedio de Categoría)

- **Prompt/spec entregado a la IA:** "A partir de la especificación `SPEC-002` (`indice_productos_rango_precio.md`), proponer el índice adecuado (tipo, columnas y condición parcial) para optimizar la doble subconsulta correlacionada de precio promedio por categoría."
- **Propuesta de la IA:** Crear un índice B-tree compuesto y parcial `idx_producto_categoria_precio` sobre `producto (id_categoria, precio_lista) WHERE activo = TRUE`.
- **Aceptado:** Sí. La combinación de `id_categoria` (clave de correlación) con `precio_lista` (columna agregada) cubierta bajo la condición `activo = TRUE` habilita un Index-Only Scan con `Heap Fetches: 0`.
- **Modificado:** Se incorporó la cláusula `IF NOT EXISTS` a la sentencia propuesta en el spec para cumplir con el estándar de idempotencia del proyecto en `TP5/indices.sql`.
- **Descartado:**
  1. Índice B-tree completo sobre `producto(activo)`: Descartado por baja cardinalidad (columna booleana con ~95% en `TRUE`).
  2. Índice simple sobre `producto(precio_lista)` sin `id_categoria`: Descartado porque las subconsultas agrupan estrictamente por `id_categoria`, lo que impediría al optimizador filtrar eficientemente por categoría.

---

### Interacción 3 — Spec de `SPEC-003` (Consulta 3 / 3.3: Pedidos de Alto Volumen y Monto Elevado)

- **Prompt/spec entregado a la IA:** "A partir de la especificación `SPEC-003` (`indice_pedidos_monto_volumen.md`), analizar la consulta de pedidos con más de 3 productos y monto total superior a $5000, formalizando los índices sobre claves foráneas."
- **Propuesta de la IA:** Definir explícitamente los índices sobre claves foráneas `detalle_pedido(id_pedido)` y `pedido(id_cliente)`.
- **Aceptado:** Sí. Aunque la consulta ya utilizaba de forma implícita la clave primaria compuesta de `detalle_pedido`, se formalizaron los índices dedicados para independizar el plan de acceso frente a cambios de estructura del modelo y garantizar estabilidad en los `Merge Join` sobre las ~900.000 filas de `detalle_pedido`.
- **Modificado:** Se utilizó `CREATE INDEX IF NOT EXISTS` para asegurar idempotencia y prevenir conflictos con `SPEC-001` y el esquema base.
- **Descartado:**
  1. *Índices sobre `cantidad` o `precio_unitario_facturado` en `detalle_pedido`:* Descartados porque las condiciones pertenecen a un filtro post-agrupamiento (`HAVING`), operando sobre el resultado agregado donde los índices B-tree no aportan selectividad previa al `GROUP BY`.
  2. *Índice compuesto sobre `pedido(fecha_pedido, forma_pago)`:* Descartado dado que ambas columnas participan únicamente en la proyección y el agrupamiento, sin actuar como predicados de filtrado previo de filas.

### Verificación y Profiling

- **Aislamiento de Pruebas:** Se ejecutaron sentencias `DROP INDEX` antes de cada profiling para asegurar mediciones de baseline puras e independientes por consulta.
- **Resultado de Optimización (Consulta 3.2):**
  - **PRE-ÍNDICE:** `251,402.102 ms` (~251.40 segundos) con `35,099,763` shared hits y escaneos de páginas de datos `Bitmap Heap Scan`.
  - **POST-ÍNDICE:** `149,374.371 ms` (~149.37 segundos) logrando transformar las subconsultas a **`Index Only Scan`** con **`Heap Fetches: 0`** y reduciendo las lecturas a memoria en más de un **96%** (`1,298,390` shared hits).

### Interacción 4 — Ajustes post-medición (descartes y alineación del workload)

- **Prompt/spec entregado a la IA:** "Revisar el conjunto de índices tras las mediciones del informe para descartar los que no aportan y alinear la presencia/ausencia de índices con el workload documentado en `TP5/queries.sql`."
- **Propuesta de la IA:** descartar el índice parcial `idx_cliente_activo` (impacto nulo documentado) y crear el índice `idx_detalle_pedido_id_producto` sobre la segunda columna de la PK compuesta para el lookup por producto.
- **Aceptado:**
  1. `idx_cliente_activo` → **descartado tras medición**: el plan no cambió (sigue `Seq Scan` sobre `cliente`) y el tiempo pasó de 3612.970 ms a 3478.948 ms (~3.7%, ruido). El costo real es la agregación top-N sobre ~700k filas, no el filtro por `activo`. Se documenta en `TP5/indices.sql` (bloque DESCARTADO) e `informe_mediciones.md` (Consulta 3.1, sección 5).
  2. `idx_detalle_pedido_id_producto` → **aceptado como Objeto 4 de `TP5/indices.sql`**: convierte el `Parallel Seq Scan` de ~900k filas en un `Index Scan` puntual (workload de `queries.sql`, Consulta Nueva 2: 57.378 ms → 0.157 ms).
- **Modificado:** rutas `food_store/` → `TP5/` y nombre de base normalizado a `tp_food_store` en toda la documentación.
- **Descartado:** nada adicional.

## Parte B
### Interacción 1 — Spec de `vista_productos_vigentes_categoria`

- **Prompt/spec entregado a la IA:** "Definir una vista que exponga los productos activos
  con el nombre de su categoría, aplicando filtro de vigencia sobre producto y categoria."
- **Propuesta de la IA:** crear la vista con `JOIN producto↔categoria` + `WHERE activo = TRUE`.
- **Aceptado:** sí (filtro de vigencia correcto, sin exponer datos sensibles).
- **Modificado:** se renombró la columna `nombre` a `nombre_producto` y `nombre_categoria`
  para evitar ambigüedad.
- **Descartado:** nada.

### Interacción 2 — Spec de `vista_pedidos_usuario`

- **Prompt/spec entregado a la IA:** "Vista de pedidos con datos del usuario, ocultando
  datos de contacto."
- **Propuesta de la IA:** exponer email y teléfono del cliente.
- **ACEPTADO (criterio de seguridad):** se decidió **ocultar `email` y `telefono`**
  (principio de menor privilegio). El esquema no tiene columna contraseña; se protegen
  los datos de contacto personales. Justificación documentada en el spec y en el informe.
- **Descartado:** exponer email/telefono (se descartó por criterio de seguridad).

### Interacción 3 — Spec de `vista_detalle_pedido_producto`

- **Prompt/spec entregado a la IA:** "Vista de detalle de pedido con nombre del producto
  y subtotal."
- **Propuesta de la IA:** filtrar por `producto.activo = TRUE`.
- **MODIFICADO / DESCARTADO:** se **rechazó el filtro por `producto.activo`** porque es
  dato histórico facturado: las líneas ya vendidas no deben desaparecer si el producto se
  dio de baja lógica después. Decisión documentada en el spec.
- **Aceptado:** agregar columna `subtotal = cantidad * precio_unitario_facturado`.

---

## Verificación (Parte B)

- Se ejecutó `TP5/views.sql` sobre `tp_food_store` (corrida 2026-09-24).
- **Resultado:** los 6 bloques `EXCEPT` (3 vistas × 2 direcciones) devolvieron **0 filas**,
  confirmando la equivalencia de cada vista contra su consulta manual:
  - `vista_productos_vigentes_categoria`: 0 filas (ambos sentidos)
  - `vista_pedidos_usuario`: 0 filas (ambos sentidos)
  - `vista_detalle_pedido_producto`: 0 filas (ambos sentidos)

## Parte C: Vista Materializada

**Herramientas utilizadas:** Kiro (especificación) y OpenCode (agente de codificación en terminal).  
**Propósito:** Diseñar, generar y validar una vista materializada (`mv_facturacion_categoria_mes`) para optimizar un reporte agregado costoso de facturación por categoría de producto y mes sobre el esquema real de Food Store, incorporando un índice único para permitir actualizaciones concurrentes sin bloqueo.

---

### Interacción 1 — Spec de `vista_materializada_facturacion_categoria_mes`

- **Prompt/spec entregado a la IA:**
  ```markdown
  # spec: vista_materializada_facturacion_categoria_mes

  - **Objetivo:** Optimizar un reporte agregado costoso de facturación por categoría de producto y mes sobre el esquema real de Food Store, reduciendo el tiempo de respuesta frente a consultas analíticas.
  - **Consulta afectada:** Agregación de ventas uniendo `pedido`, `detalle_pedido`, `producto` y `categoria` agrupando por `DATE_TRUNC('month', fecha_pedido)` e `id_categoria`.
  - **Columnas candidatas para índice único:** `id_categoria` y `mes`.
  - **Criterio de aceptación:** Reducir drásticamente el tiempo de ejecución en comparación con la consulta en caliente sobre tablas base, permitiendo además la actualización concurrente (`REFRESH MATERIALIZED VIEW CONCURRENTLY`) gracias al índice único.
  ```
- **Propuesta de la IA:** bloque SQL adaptado estrictamente a las tablas del esquema
  (`pedido`, `detalle_pedido`, `producto`, `categoria`), con `DATE_TRUNC` para los meses,
  `COUNT(DISTINCT ...)` y `SUM` para los montos, acompañado del índice único correspondiente:
  ```sql
  CREATE MATERIALIZED VIEW mv_facturacion_categoria_mes AS
  SELECT
      c.id_categoria AS categoria_id,
      c.nombre AS categoria_nombre,
      DATE_TRUNC('month', p.fecha_pedido) AS mes,
      COUNT(DISTINCT p.id_pedido) AS total_pedidos,
      SUM(dp.cantidad) AS total_unidades_vendidas,
      SUM(dp.cantidad * dp.precio_unitario_facturado) AS facturacion_total
  FROM pedido p
  JOIN detalle_pedido dp ON p.id_pedido = dp.id_pedido
  JOIN producto pr ON dp.id_producto = pr.id_producto
  JOIN categoria c ON pr.id_categoria = c.id_categoria
  GROUP BY c.id_categoria, c.nombre, DATE_TRUNC('month', p.fecha_pedido)
  WITH DATA;

  CREATE UNIQUE INDEX idx_mv_facturacion_cat_mes_unq
      ON mv_facturacion_categoria_mes (categoria_id, mes);
  ```
- **Validación línea por línea:** se verificó que los nombres de las claves foráneas y
  columnas (`id_pedido`, `id_producto`, `id_categoria`, `fecha_pedido`,
  `precio_unitario_facturado`) coincidieran exactamente con el `schema.sql` del repositorio.
- **Aceptado:** sí. Cumple la estructura requerida, incluye `WITH DATA` para poblar la vista
  desde el inicio y genera el índice único con la combinación exacta `(categoria_id, mes)`,
  lo cual habilita `REFRESH MATERIALIZED VIEW CONCURRENTLY` sin bloquear las lecturas del
  sistema.
- **Prueba de equivalencia:** se contrastaron los resultados de
  `SELECT * FROM mv_facturacion_categoria_mes` contra la consulta analítica sin materializar
  de la Semana 4 (EXCEPT bidireccional): los totales de facturación y unidades coinciden de
  forma exacta (0 filas).
- **Modificado:** se incorporaron los bloques `EXCEPT` y el módulo de medición
  `EXPLAIN (ANALYZE, BUFFERS, TIMING)` al script.
- **Descartado:** nada en esta interacción.

### Interacción 2 — Completado de la Parte C (entregables finales)

- **Prompt/spec entregado a la IA:** "Completar la Parte C del TP5: materializar la vista en un archivo SQL propio, dejar el módulo de medición de tiempos (consulta original vs. vista materializada) y documentar la frecuencia de refresco con sus implicancias de consistencia."
- **Propuesta de la IA:** crear el archivo `TP5/materializadas.sql` (MV con `WITH DATA` + índice único + verificación `EXCEPT` + bloques `EXPLAIN (ANALYZE, BUFFERS, TIMING)` con marcadores de salida), dejar la sección "Parte C" en `TP5/informe_mediciones.md` con la justificación de frecuencia de refresco y las implicancias de consistencia, y expandir la spec en `TP5/specs/vista_materializada_facturacion_categoria_mes.md`.
- **Aceptado:** sí. La frecuencia recomendada quedó en **refresco diario nocturno con `REFRESH ... CONCURRENTLY`** (celdas históricas no cambian; solo la del mes corriente; costo del refresh medido una vez por día fuera de horario pico; lecturas nunca bloqueadas gracias al índice único).
- **Modificado:** se documentaron los marcadores `[PEGAR SALIDA]` / `[PEGAR NÚMERO]` para que las mediciones se completen con la corrida local real del estudiante (Bloques A, B y C del script).
- **Descartado:** refresco con `REFRESH MATERIALIZED VIEW` simple (bloquea lecturas con `ACCESS EXCLUSIVE` durante la reconstrucción) y refresco sub-horario (costo diario multiplicado sin beneficio para un reporte mensual/categoría).

---

## Verificación (Parte C)

- Se generó `TP5/materializadas.sql`; la vista `mv_facturacion_categoria_mes` se crea con
  `WITH DATA`, el índice único `idx_mv_facturacion_cat_mes_unq (categoria_id, mes)` habilita
  el refresh concurrente, y los 2 bloques `EXCEPT` devolvieron **0 filas** (corrida local
  del 2026-09-24 sobre `tp_food_store`).
- Mediciones de tiempo (base local, datos masivos):
  - Consulta original sin materializar: `2797.623 ms` (Planning 0.855 ms).
  - `SELECT` desde la MV: `0.042 ms` (Planning 0.078 ms) → mejora ≈ **66.600×**.
  - `REFRESH MATERIALIZED VIEW CONCURRENTLY`: ~10 s (70 filas actualizadas; sin plan por
    ser utility statement, tiempo tomado de la estadística de DBeaver).
- Salidas completas de los bloques A, B y C pegadas en `TP5/informe_mediciones.md` → Parte C.