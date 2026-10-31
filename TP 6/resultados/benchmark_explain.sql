-- Benchmark de tiempos de servidor: 5 EXPLAIN (ANALYZE) por estado.
\pset pager off

\echo '### ESTADO A: natural (sin indice FK)'
DROP INDEX IF EXISTS ix_detalle_pedido_pedido;
ANALYZE detalle_pedido;

EXPLAIN (ANALYZE) SELECT c.nombre, SUM(dp.subtotal) AS total FROM detalle_pedido dp JOIN producto pr ON pr.id = dp.producto_id JOIN categoria c ON c.id = pr.categoria_id JOIN pedido ped ON ped.id = dp.pedido_id WHERE ped.fecha = CURRENT_DATE AND dp.eliminado = FALSE AND ped.eliminado = FALSE GROUP BY c.nombre ORDER BY total DESC LIMIT 5;
EXPLAIN (ANALYZE) SELECT c.nombre, SUM(dp.subtotal) AS total FROM detalle_pedido dp JOIN producto pr ON pr.id = dp.producto_id JOIN categoria c ON c.id = pr.categoria_id JOIN pedido ped ON ped.id = dp.pedido_id WHERE ped.fecha = CURRENT_DATE AND dp.eliminado = FALSE AND ped.eliminado = FALSE GROUP BY c.nombre ORDER BY total DESC LIMIT 5;
EXPLAIN (ANALYZE) SELECT c.nombre, SUM(dp.subtotal) AS total FROM detalle_pedido dp JOIN producto pr ON pr.id = dp.producto_id JOIN categoria c ON c.id = pr.categoria_id JOIN pedido ped ON ped.id = dp.pedido_id WHERE ped.fecha = CURRENT_DATE AND dp.eliminado = FALSE AND ped.eliminado = FALSE GROUP BY c.nombre ORDER BY total DESC LIMIT 5;
EXPLAIN (ANALYZE) SELECT c.nombre, SUM(dp.subtotal) AS total FROM detalle_pedido dp JOIN producto pr ON pr.id = dp.producto_id JOIN categoria c ON c.id = pr.categoria_id JOIN pedido ped ON ped.id = dp.pedido_id WHERE ped.fecha = CURRENT_DATE AND dp.eliminado = FALSE AND ped.eliminado = FALSE GROUP BY c.nombre ORDER BY total DESC LIMIT 5;
EXPLAIN (ANALYZE) SELECT c.nombre, SUM(dp.subtotal) AS total FROM detalle_pedido dp JOIN producto pr ON pr.id = dp.producto_id JOIN categoria c ON c.id = pr.categoria_id JOIN pedido ped ON ped.id = dp.pedido_id WHERE ped.fecha = CURRENT_DATE AND dp.eliminado = FALSE AND ped.eliminado = FALSE GROUP BY c.nombre ORDER BY total DESC LIMIT 5;

\echo '### ESTADO B: optimizado (con indice FK)'
CREATE INDEX ix_detalle_pedido_pedido ON detalle_pedido (pedido_id);
ANALYZE detalle_pedido;

EXPLAIN (ANALYZE) SELECT c.nombre, SUM(dp.subtotal) AS total FROM detalle_pedido dp JOIN producto pr ON pr.id = dp.producto_id JOIN categoria c ON c.id = pr.categoria_id JOIN pedido ped ON ped.id = dp.pedido_id WHERE ped.fecha = CURRENT_DATE AND dp.eliminado = FALSE AND ped.eliminado = FALSE GROUP BY c.nombre ORDER BY total DESC LIMIT 5;
EXPLAIN (ANALYZE) SELECT c.nombre, SUM(dp.subtotal) AS total FROM detalle_pedido dp JOIN producto pr ON pr.id = dp.producto_id JOIN categoria c ON c.id = pr.categoria_id JOIN pedido ped ON ped.id = dp.pedido_id WHERE ped.fecha = CURRENT_DATE AND dp.eliminado = FALSE AND ped.eliminado = FALSE GROUP BY c.nombre ORDER BY total DESC LIMIT 5;
EXPLAIN (ANALYZE) SELECT c.nombre, SUM(dp.subtotal) AS total FROM detalle_pedido dp JOIN producto pr ON pr.id = dp.producto_id JOIN categoria c ON c.id = pr.categoria_id JOIN pedido ped ON ped.id = dp.pedido_id WHERE ped.fecha = CURRENT_DATE AND dp.eliminado = FALSE AND ped.eliminado = FALSE GROUP BY c.nombre ORDER BY total DESC LIMIT 5;
EXPLAIN (ANALYZE) SELECT c.nombre, SUM(dp.subtotal) AS total FROM detalle_pedido dp JOIN producto pr ON pr.id = dp.producto_id JOIN categoria c ON c.id = pr.categoria_id JOIN pedido ped ON ped.id = dp.pedido_id WHERE ped.fecha = CURRENT_DATE AND dp.eliminado = FALSE AND ped.eliminado = FALSE GROUP BY c.nombre ORDER BY total DESC LIMIT 5;
EXPLAIN (ANALYZE) SELECT c.nombre, SUM(dp.subtotal) AS total FROM detalle_pedido dp JOIN producto pr ON pr.id = dp.producto_id JOIN categoria c ON c.id = pr.categoria_id JOIN pedido ped ON ped.id = dp.pedido_id WHERE ped.fecha = CURRENT_DATE AND dp.eliminado = FALSE AND ped.eliminado = FALSE GROUP BY c.nombre ORDER BY total DESC LIMIT 5;

\echo '### ESTADO C: desnormalizado'
EXPLAIN (ANALYZE) SELECT c.nombre, r.total_vendido FROM resumen_venta_categoria_dia r JOIN categoria c ON c.id = r.categoria_id WHERE r.fecha = CURRENT_DATE ORDER BY r.total_vendido DESC LIMIT 5;
EXPLAIN (ANALYZE) SELECT c.nombre, r.total_vendido FROM resumen_venta_categoria_dia r JOIN categoria c ON c.id = r.categoria_id WHERE r.fecha = CURRENT_DATE ORDER BY r.total_vendido DESC LIMIT 5;
EXPLAIN (ANALYZE) SELECT c.nombre, r.total_vendido FROM resumen_venta_categoria_dia r JOIN categoria c ON c.id = r.categoria_id WHERE r.fecha = CURRENT_DATE ORDER BY r.total_vendido DESC LIMIT 5;
EXPLAIN (ANALYZE) SELECT c.nombre, r.total_vendido FROM resumen_venta_categoria_dia r JOIN categoria c ON c.id = r.categoria_id WHERE r.fecha = CURRENT_DATE ORDER BY r.total_vendido DESC LIMIT 5;
EXPLAIN (ANALYZE) SELECT c.nombre, r.total_vendido FROM resumen_venta_categoria_dia r JOIN categoria c ON c.id = r.categoria_id WHERE r.fecha = CURRENT_DATE ORDER BY r.total_vendido DESC LIMIT 5;
