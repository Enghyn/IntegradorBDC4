-- Benchmark reproducible para el informe (no es entregable del TP).
-- Ejecutar con: psql -d food_store_tp6 -f resultados/benchmark.sql
\pset pager off
\timing on

\echo ''
\echo '=============================================================='
\echo ' 1) ANTES - esquema natural (sin indice sobre la FK pedido_id)'
\echo '=============================================================='
DROP INDEX IF EXISTS ix_detalle_pedido_pedido;
ANALYZE detalle_pedido;

\echo '--- calentamiento (se descarta) ---'
SELECT c.nombre, SUM(dp.subtotal) AS total
FROM detalle_pedido dp
JOIN producto pr ON pr.id = dp.producto_id
JOIN categoria c ON c.id = pr.categoria_id
JOIN pedido ped  ON ped.id = dp.pedido_id
WHERE ped.fecha = CURRENT_DATE AND dp.eliminado = FALSE AND ped.eliminado = FALSE
GROUP BY c.nombre ORDER BY total DESC LIMIT 5;

\echo '--- 5 mediciones ---'
SELECT c.nombre, SUM(dp.subtotal) AS total
FROM detalle_pedido dp
JOIN producto pr ON pr.id = dp.producto_id
JOIN categoria c ON c.id = pr.categoria_id
JOIN pedido ped  ON ped.id = dp.pedido_id
WHERE ped.fecha = CURRENT_DATE AND dp.eliminado = FALSE AND ped.eliminado = FALSE
GROUP BY c.nombre ORDER BY total DESC LIMIT 5;
SELECT c.nombre, SUM(dp.subtotal) AS total
FROM detalle_pedido dp
JOIN producto pr ON pr.id = dp.producto_id
JOIN categoria c ON c.id = pr.categoria_id
JOIN pedido ped  ON ped.id = dp.pedido_id
WHERE ped.fecha = CURRENT_DATE AND dp.eliminado = FALSE AND ped.eliminado = FALSE
GROUP BY c.nombre ORDER BY total DESC LIMIT 5;
SELECT c.nombre, SUM(dp.subtotal) AS total
FROM detalle_pedido dp
JOIN producto pr ON pr.id = dp.producto_id
JOIN categoria c ON c.id = pr.categoria_id
JOIN pedido ped  ON ped.id = dp.pedido_id
WHERE ped.fecha = CURRENT_DATE AND dp.eliminado = FALSE AND ped.eliminado = FALSE
GROUP BY c.nombre ORDER BY total DESC LIMIT 5;
SELECT c.nombre, SUM(dp.subtotal) AS total
FROM detalle_pedido dp
JOIN producto pr ON pr.id = dp.producto_id
JOIN categoria c ON c.id = pr.categoria_id
JOIN pedido ped  ON ped.id = dp.pedido_id
WHERE ped.fecha = CURRENT_DATE AND dp.eliminado = FALSE AND ped.eliminado = FALSE
GROUP BY c.nombre ORDER BY total DESC LIMIT 5;
SELECT c.nombre, SUM(dp.subtotal) AS total
FROM detalle_pedido dp
JOIN producto pr ON pr.id = dp.producto_id
JOIN categoria c ON c.id = pr.categoria_id
JOIN pedido ped  ON ped.id = dp.pedido_id
WHERE ped.fecha = CURRENT_DATE AND dp.eliminado = FALSE AND ped.eliminado = FALSE
GROUP BY c.nombre ORDER BY total DESC LIMIT 5;

\echo ''
\echo '=============================================================='
\echo ' 2) ANTES OPTIMIZADO - con indice sobre detalle_pedido(pedido_id)'
\echo '=============================================================='
CREATE INDEX ix_detalle_pedido_pedido ON detalle_pedido (pedido_id);
ANALYZE detalle_pedido;

\echo '--- calentamiento (se descarta) ---'
SELECT c.nombre, SUM(dp.subtotal) AS total
FROM detalle_pedido dp
JOIN producto pr ON pr.id = dp.producto_id
JOIN categoria c ON c.id = pr.categoria_id
JOIN pedido ped  ON ped.id = dp.pedido_id
WHERE ped.fecha = CURRENT_DATE AND dp.eliminado = FALSE AND ped.eliminado = FALSE
GROUP BY c.nombre ORDER BY total DESC LIMIT 5;

\echo '--- 5 mediciones ---'
SELECT c.nombre, SUM(dp.subtotal) AS total
FROM detalle_pedido dp
JOIN producto pr ON pr.id = dp.producto_id
JOIN categoria c ON c.id = pr.categoria_id
JOIN pedido ped  ON ped.id = dp.pedido_id
WHERE ped.fecha = CURRENT_DATE AND dp.eliminado = FALSE AND ped.eliminado = FALSE
GROUP BY c.nombre ORDER BY total DESC LIMIT 5;
SELECT c.nombre, SUM(dp.subtotal) AS total
FROM detalle_pedido dp
JOIN producto pr ON pr.id = dp.producto_id
JOIN categoria c ON c.id = pr.categoria_id
JOIN pedido ped  ON ped.id = dp.pedido_id
WHERE ped.fecha = CURRENT_DATE AND dp.eliminado = FALSE AND ped.eliminado = FALSE
GROUP BY c.nombre ORDER BY total DESC LIMIT 5;
SELECT c.nombre, SUM(dp.subtotal) AS total
FROM detalle_pedido dp
JOIN producto pr ON pr.id = dp.producto_id
JOIN categoria c ON c.id = pr.categoria_id
JOIN pedido ped  ON ped.id = dp.pedido_id
WHERE ped.fecha = CURRENT_DATE AND dp.eliminado = FALSE AND ped.eliminado = FALSE
GROUP BY c.nombre ORDER BY total DESC LIMIT 5;
SELECT c.nombre, SUM(dp.subtotal) AS total
FROM detalle_pedido dp
JOIN producto pr ON pr.id = dp.producto_id
JOIN categoria c ON c.id = pr.categoria_id
JOIN pedido ped  ON ped.id = dp.pedido_id
WHERE ped.fecha = CURRENT_DATE AND dp.eliminado = FALSE AND ped.eliminado = FALSE
GROUP BY c.nombre ORDER BY total DESC LIMIT 5;
SELECT c.nombre, SUM(dp.subtotal) AS total
FROM detalle_pedido dp
JOIN producto pr ON pr.id = dp.producto_id
JOIN categoria c ON c.id = pr.categoria_id
JOIN pedido ped  ON ped.id = dp.pedido_id
WHERE ped.fecha = CURRENT_DATE AND dp.eliminado = FALSE AND ped.eliminado = FALSE
GROUP BY c.nombre ORDER BY total DESC LIMIT 5;

\echo ''
\echo '=============================================================='
\echo ' 3) DESPUES - estructura desnormalizada'
\echo '=============================================================='
\echo '--- calentamiento (se descarta) ---'
SELECT c.nombre, r.total_vendido
FROM resumen_venta_categoria_dia r
JOIN categoria c ON c.id = r.categoria_id
WHERE r.fecha = CURRENT_DATE
ORDER BY r.total_vendido DESC LIMIT 5;

\echo '--- 5 mediciones ---'
SELECT c.nombre, r.total_vendido
FROM resumen_venta_categoria_dia r
JOIN categoria c ON c.id = r.categoria_id
WHERE r.fecha = CURRENT_DATE
ORDER BY r.total_vendido DESC LIMIT 5;
SELECT c.nombre, r.total_vendido
FROM resumen_venta_categoria_dia r
JOIN categoria c ON c.id = r.categoria_id
WHERE r.fecha = CURRENT_DATE
ORDER BY r.total_vendido DESC LIMIT 5;
SELECT c.nombre, r.total_vendido
FROM resumen_venta_categoria_dia r
JOIN categoria c ON c.id = r.categoria_id
WHERE r.fecha = CURRENT_DATE
ORDER BY r.total_vendido DESC LIMIT 5;
SELECT c.nombre, r.total_vendido
FROM resumen_venta_categoria_dia r
JOIN categoria c ON c.id = r.categoria_id
WHERE r.fecha = CURRENT_DATE
ORDER BY r.total_vendido DESC LIMIT 5;
SELECT c.nombre, r.total_vendido
FROM resumen_venta_categoria_dia r
JOIN categoria c ON c.id = r.categoria_id
WHERE r.fecha = CURRENT_DATE
ORDER BY r.total_vendido DESC LIMIT 5;

\echo ''
\echo '=============================================================='
\echo ' 4) COSTO DE ESCRITURA: 5.000 lineas con y sin trigger'
\echo '=============================================================='
BEGIN;
\echo '--- con trigger de sincronizacion ---'
INSERT INTO detalle_pedido (pedido_id, producto_id, cantidad, precio_unitario)
SELECT p.id, 1, 1, 10.00
FROM (SELECT id FROM pedido WHERE fecha = CURRENT_DATE LIMIT 1000) p
CROSS JOIN generate_series(1, 5) g;
ROLLBACK;

BEGIN;
ALTER TABLE detalle_pedido DISABLE TRIGGER trg_detalle_resumen;
\echo '--- sin trigger de sincronizacion ---'
INSERT INTO detalle_pedido (pedido_id, producto_id, cantidad, precio_unitario)
SELECT p.id, 1, 1, 10.00
FROM (SELECT id FROM pedido WHERE fecha = CURRENT_DATE LIMIT 1000) p
CROSS JOIN generate_series(1, 5) g;
ALTER TABLE detalle_pedido ENABLE TRIGGER trg_detalle_resumen;
ROLLBACK;

\echo ''
\echo '=============================================================='
\echo ' 5) AUDITORIA (debe devolver 0 filas)'
\echo '=============================================================='
SELECT * FROM v_auditoria_resumen;
