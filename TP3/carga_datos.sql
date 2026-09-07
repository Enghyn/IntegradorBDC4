-- ============================================================================
-- SCRIPT: Carga de Categorías, Clientes, Productos y Pedidos
-- Archivo: db/seeds/carga_datos.sql
-- Base de datos: tp_food_store (puerto 5433)
--
-- Genera:
-- 1. Categorías base (10) si la tabla está vacía
-- 2. 20.000 clientes
-- 3. 50.000 productos distribuidos equitativamente entre categorías
-- 4. 200.000 pedidos asociados a clientes
--
-- Dependencias: esquema creado por db/schema.sql + respaldo respaldo.dump
-- Post-ejecución: correr carga_detalle_pedido.sql
-- ============================================================================

SET client_encoding = 'UTF8';
SET timezone = 'America/Argentina/Buenos_Aires';

BEGIN;

-- ----------------------------------------------------------------------------
-- 0. CATEGORÍAS BASE (si la tabla está vacía)
-- ----------------------------------------------------------------------------
DO $$
BEGIN
    IF (SELECT COUNT(*) FROM categoria) = 0 THEN
        INSERT INTO categoria (nombre, activo) VALUES
            ('Bebidas', TRUE), ('Lacteos', TRUE), ('Panaderia', TRUE),
            ('Carnes', TRUE), ('Frutas y Verduras', TRUE), ('Snacks', TRUE),
            ('Congelados', TRUE), ('Limpieza', TRUE), ('Electronica', TRUE), ('Ropa', TRUE);
        RAISE NOTICE 'Se insertaron 10 categorias base.';
    ELSE
        RAISE NOTICE 'La tabla categoria ya tiene datos, se conservan existentes.';
    END IF;
END $$;

-- ----------------------------------------------------------------------------
-- 1. CLIENTES (20.000 registros)
-- ----------------------------------------------------------------------------
INSERT INTO cliente (nombre, email, telefono, activo, fecha_creacion)
SELECT 
    'Cliente ' || gs.n,
    'cliente_' || gs.n || '@foodstore.test',
    CASE 
        WHEN random() < 0.5 THEN '+54911' || LPAD(FLOOR(random() * 100000000)::TEXT, 8, '0')
        ELSE NULL
    END,
    CASE 
        WHEN random() < 0.95 THEN TRUE 
        ELSE FALSE 
    END,
    CURRENT_TIMESTAMP - (random() * INTERVAL '365 days')
FROM generate_series(1, 20000) AS gs(n);

-- ----------------------------------------------------------------------------
-- 2. PRODUCTOS (50.000 registros distribuidos equitativamente)
-- ----------------------------------------------------------------------------
WITH categorias_activas AS (
    SELECT id_categoria, 
           ROW_NUMBER() OVER (ORDER BY id_categoria) AS cat_num,
           COUNT(*) OVER () AS total_cats
    FROM categoria 
    WHERE activo = TRUE
)
INSERT INTO producto (id_categoria, nombre, precio_lista, stock, activo)
SELECT 
    ca.id_categoria,
    'Producto Cat' || ca.id_categoria || '-' || gs.n AS nombre,
    ROUND((500 + (random() * 4500))::NUMERIC, 2) AS precio_lista,
    FLOOR(random() * 201)::INTEGER AS stock,
    CASE 
        WHEN random() < 0.90 THEN TRUE 
        ELSE FALSE 
    END AS activo
FROM generate_series(1, 50000) AS gs(n)
CROSS JOIN categorias_activas ca
WHERE (gs.n - 1) % ca.total_cats + 1 = ca.cat_num;

-- ----------------------------------------------------------------------------
-- 3. PEDIDOS (200.000 registros)
-- ----------------------------------------------------------------------------
WITH cliente_ids AS (
    SELECT id_cliente, ROW_NUMBER() OVER (ORDER BY id_cliente) AS rn FROM cliente
),
total_clientes AS (
    SELECT COUNT(*) AS cnt FROM cliente
)
INSERT INTO pedido (id_cliente, fecha_pedido, forma_pago)
SELECT 
    ci.id_cliente,
    CURRENT_TIMESTAMP - (random() * INTERVAL '180 days'),
    CASE 
        WHEN random() < 0.60 THEN 'TARJETA'::forma_pago_enum
        WHEN random() < 0.90 THEN 'TRANSFERENCIA'::forma_pago_enum
        ELSE 'EFECTIVO'::forma_pago_enum
    END
FROM generate_series(1, 200000) AS gs(n)
JOIN cliente_ids ci ON ci.rn = ((gs.n - 1) % (SELECT cnt FROM total_clientes)) + 1;

COMMIT;

DO $$
BEGIN
    RAISE NOTICE '============================================================';
    RAISE NOTICE '  CARGA DE DATOS COMPLETADA: 10 cat, 20k clientes, 50k productos, 200k pedidos';
    RAISE NOTICE '============================================================';
END $$;
