-- ============================================================================
-- SCRIPT: Carga de Detalles de Pedido
-- Archivo: db/seeds/carga_detalle_pedido.sql
-- Base de datos: tp_food_store (puerto 5433)
--
-- Genera:
-- 1. Entre 2 y 5 productos por pedido (total estimado: ~600k-1M detalles)
-- 2. Cantidad aleatoria entre 1 y 10 por línea
-- 3. Precio unitario facturado = precio_lista actual del producto
--
-- Dependencias: carga_datos.sql ejecutado exitosamente
--               (necesita tablas cliente, producto, pedido con datos)
-- Post-ejecución: ANALYZE ya incluido en este script
-- ============================================================================

SET client_encoding = 'UTF8';

BEGIN;

-- Prepara tabla temporal con IDs de productos activos
CREATE TEMPORARY TABLE tmp_productos_activos AS
SELECT id_producto, precio_lista, ROW_NUMBER() OVER (ORDER BY id_producto) AS rn
FROM producto WHERE activo = TRUE;

-- ----------------------------------------------------------------------------
-- DETALLES DE PEDIDO (2 a 5 productos por pedido)
-- ----------------------------------------------------------------------------
WITH pedidos_con_cantidad AS (
    SELECT 
        id_pedido,
        2 + FLOOR(random() * 4)::INTEGER AS num_productos
    FROM pedido
),
detalles_expandidos AS (
    SELECT 
        pc.id_pedido,
        gs.n AS item_num,
        pc.num_productos
    FROM pedidos_con_cantidad pc
    CROSS JOIN generate_series(1, 5) AS gs(n)
    WHERE gs.n <= pc.num_productos
)
INSERT INTO detalle_pedido (id_pedido, id_producto, cantidad, precio_unitario_facturado)
SELECT 
    de.id_pedido,
    tpa.id_producto,
    1 + FLOOR(random() * 10)::INTEGER,
    tpa.precio_lista
FROM detalles_expandidos de
JOIN tmp_productos_activos tpa 
    ON tpa.rn = ((de.id_pedido + de.item_num) % (SELECT COUNT(*) FROM tmp_productos_activos)) + 1;

DROP TABLE tmp_productos_activos;

-- ----------------------------------------------------------------------------
-- ACTUALIZACIÓN DE ESTADÍSTICAS (ANALYZE)
-- ----------------------------------------------------------------------------
ANALYZE cliente;
ANALYZE producto;
ANALYZE pedido;
ANALYZE detalle_pedido;

COMMIT;

DO $$
BEGIN
    RAISE NOTICE '============================================================';
    RAISE NOTICE '  DETALLES DE PEDIDO CARGADOS + ANALYZE COMPLETADO';
    RAISE NOTICE '============================================================';
END $$;
