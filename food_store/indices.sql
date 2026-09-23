-- ============================================================================
-- INDICES.SQL — ÍNDICES DE LA SEMANA (SPEC-001 / SPEC-002)
-- Workload: Consulta 3.1 — Top 10 Clientes por Gasto Total (queries.sql)
--           Consulta 3.2 — Productos con Precio Superior al Promedio de su
--           Categoría (SPEC-002)
-- Base de datos: tp_food_store (PostgreSQL)
--
-- Fuente: food_store/specs/indice_top_clientes_gasto.md,
--         food_store/specs/indice_productos_rango_precio.md
-- Restricción: NO modifica el modelo de datos (sin ALTER TABLE, DROP ni
--              cambios de tipo). Los objetos de esta entrega se definen
--              aquí, no en schema.sql ni en queries.sql.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Objeto 1: Índice parcial sobre cliente para el filtro WHERE activo = TRUE
-- Tipo: B-tree parcial (condición del índice: activo = TRUE)
-- Columnas: id_cliente
-- Justificación: permite al planificador usar un Index Scan al aplicar el
--                filtro, evitando el Seq Scan sobre las 20 000 filas de
--                cliente. La condición activo = TRUE es el predicado del
--                índice parcial, no una columna del índice.
-- ----------------------------------------------------------------------------
CREATE INDEX idx_cliente_activo
    ON cliente (id_cliente)
    WHERE activo = TRUE;

-- ----------------------------------------------------------------------------
-- Objeto 2: Índice dedicado en detalle_pedido para agilizar el JOIN por id_pedido
-- Tipo: B-tree simple (una sola columna: sin orden compuesto)
-- Columnas: id_pedido
-- Justificación: desambigua el acceso por id_pedido respecto a la PK compuesta
--                (id_pedido, id_producto). Permite un Index Scan más eficiente
--                sobre las ~700 000 filas durante el JOIN de agregación.
-- ----------------------------------------------------------------------------
CREATE INDEX idx_detalle_pedido_id_pedido
    ON detalle_pedido (id_pedido);

-- ----------------------------------------------------------------------------
-- Objeto 3: Índice compuesto parcial sobre producto para optimizar la subconsulta
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