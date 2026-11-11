-- ============================================================================
-- INDICES.SQL — ÍNDICES DE LA SEMANA (SPEC-001 / SPEC-002 / SPEC-003)
-- Workload: Consulta 3.1 — Top 10 Clientes por Gasto Total (queries.sql)
--           Consulta 3.2 — Productos con Precio Superior al Promedio de su
--           Categoría (SPEC-002)
--           Consulta 3.3 — Pedidos con más de 3 productos y monto total
--           > $5000 (SPEC-003)
--           Lookups puntuales de queries.sql (Consulta Nueva 2 por id_producto)
-- Base de datos: tp_food_store (PostgreSQL 16+) — SOLO copia local de
--                trabajo. NUNCA producción.
--
-- Fuente: TP5/specs/indice_top_clientes_gasto.md,
--         TP5/specs/indice_productos_rango_precio.md,
--         TP5/specs/indice_pedidos_monto_volumen.md
-- Restricción: NO modifica el modelo de datos (sin ALTER TABLE, DROP ni
--              cambios de tipo). Los objetos de esta entrega se definen
--              aquí, no en schema.sql ni en queries.sql.
-- Estado de SPEC-001: el índice parcial idx_cliente_activo fue DESCARTADO tras
--              medición (ver bloque DESCARTADO más abajo); solo se crea el
--              índice idx_detalle_pedido_id_pedido de esa especificación.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- DESCARTADO tras medición (SPEC-001, Índice 1): Índice parcial sobre cliente
-- para el filtro WHERE activo = TRUE.
-- Tipo propuesto: B-tree parcial (condición del índice: activo = TRUE)
-- Columnas propuestas: id_cliente
-- Resultado de la medición (informe_mediciones.md → Consulta 3.1, sección 5):
--   el plan NO cambió (sigue Seq Scan sobre cliente) y el tiempo pasó de
--   3612.970 ms a 3478.948 ms (~3.7%, dentro del ruido). El costo real es la
--   agregación top-N sobre ~700k filas de detalle_pedido, no el filtro por
--   activo de una tabla de 20 000 filas.
-- MOTIVO: criterio de sobreindexación del TP — overhead de escritura sin
--         beneficio medible. NO se crea.
-- ----------------------------------------------------------------------------
-- CREATE INDEX idx_cliente_activo
--     ON cliente (id_cliente)
--     WHERE activo = TRUE;

-- ----------------------------------------------------------------------------
-- Objeto 1: Índice dedicado en detalle_pedido para agilizar el JOIN por id_pedido
-- Tipo: B-tree simple (una sola columna: sin orden compuesto)
-- Columnas: id_pedido
-- Justificación: desambigua el acceso por id_pedido respecto a la PK compuesta
--                (id_pedido, id_producto). Permite un Index Scan más eficiente
--                sobre las ~700 000 filas durante el JOIN de agregación.
--                Compartido con SPEC-001 (Consulta 3.1) y SPEC-003 (Consulta
--                3.3); IF NOT EXISTS garantiza idempotencia entre ambas specs.
-- ----------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_detalle_pedido_id_pedido
    ON detalle_pedido (id_pedido);

-- ----------------------------------------------------------------------------
-- Objeto 2: Índice compuesto parcial sobre producto para optimizar la subconsulta
--           correlacionada de precio promedio por categoría (SPEC-002)
-- Tipo: B-tree compuesto parcial (columnas: id_categoria, precio_lista;
--        condición del índice: activo = TRUE)
-- Columnas: id_categoria, precio_lista
-- Justificación: habilita Index-Only Scan para AVG(precio_lista) por categoría
--                en la subconsulta correlacionada (queries.sql 3.2),
--                eliminando el acceso al heap y el Seq Scan sobre producto.
--                Coexiste con idx_producto_categoria_activo (que no se modifica).
-- ----------------------------------------------------------------------------
-- SPEC-002: Índice compuesto parcial para optimizar la subconsulta correlacionada de precio promedio por categoría
CREATE INDEX IF NOT EXISTS idx_producto_categoria_precio
    ON producto (id_categoria, precio_lista)
    WHERE activo = TRUE;

-- ----------------------------------------------------------------------------
-- Objeto 3: Índice dedicado en pedido para agilizar el JOIN por id_cliente (SPEC-003)
-- Tipo: B-tree simple (una sola columna)
-- Columnas: id_cliente
-- Justificación: formaliza el acceso por FK id_cliente habilitando Nested Loop
--                con Memoize en el JOIN pedido→cliente, evitando Seq Scan sobre
--                las 200 000 filas de pedido en schemas base mínimos que no
--                incluyan idx_pedido_cliente (definido en schema.sql).
--                Funcionalmente equivalente a idx_pedido_cliente; IF NOT EXISTS
--                garantiza idempotencia en todos los entornos.
-- ----------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_pedido_id_cliente
    ON pedido (id_cliente);

-- ----------------------------------------------------------------------------
-- Objeto 4: Índice dedicado en detalle_pedido para la búsqueda por producto
--           (workload de queries.sql — Consulta Nueva 2: WHERE id_producto = n)
-- Tipo: B-tree simple (una sola columna)
-- Columnas: id_producto
-- Justificación: id_producto es la SEGUNDA columna de la PK compuesta
--                (id_pedido, id_producto), por lo que la PK no puede usarse en
--                búsquedas por producto sin saber el id_pedido asociado. El
--                índice dedicado convierte el Parallel Seq Scan sobre ~900k
--                filas en un Index Scan puntual (workload de queries.sql:
--                Consulta Nueva 2: 57.378 ms → 0.157 ms).
-- ----------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_detalle_pedido_id_producto
    ON detalle_pedido (id_producto);