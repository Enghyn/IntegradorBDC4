-- Costo de escritura: 5.000 líneas con y sin el trigger de sincronización.
-- Se alterna el orden y se repite 3 veces; todo se revierte.
\timing on
\pset pager off

\echo '--- R1 con trigger ---'
BEGIN;
INSERT INTO detalle_pedido (pedido_id, producto_id, cantidad, precio_unitario)
SELECT p.id, 1, 1, 10.00 FROM (SELECT id FROM pedido WHERE fecha = CURRENT_DATE LIMIT 1000) p CROSS JOIN generate_series(1,5) g;
ROLLBACK;

\echo '--- R1 sin trigger ---'
BEGIN;
ALTER TABLE detalle_pedido DISABLE TRIGGER trg_detalle_resumen;
INSERT INTO detalle_pedido (pedido_id, producto_id, cantidad, precio_unitario)
SELECT p.id, 1, 1, 10.00 FROM (SELECT id FROM pedido WHERE fecha = CURRENT_DATE LIMIT 1000) p CROSS JOIN generate_series(1,5) g;
ALTER TABLE detalle_pedido ENABLE TRIGGER trg_detalle_resumen;
ROLLBACK;

\echo '--- R2 sin trigger ---'
BEGIN;
ALTER TABLE detalle_pedido DISABLE TRIGGER trg_detalle_resumen;
INSERT INTO detalle_pedido (pedido_id, producto_id, cantidad, precio_unitario)
SELECT p.id, 1, 1, 10.00 FROM (SELECT id FROM pedido WHERE fecha = CURRENT_DATE LIMIT 1000) p CROSS JOIN generate_series(1,5) g;
ALTER TABLE detalle_pedido ENABLE TRIGGER trg_detalle_resumen;
ROLLBACK;

\echo '--- R2 con trigger ---'
BEGIN;
INSERT INTO detalle_pedido (pedido_id, producto_id, cantidad, precio_unitario)
SELECT p.id, 1, 1, 10.00 FROM (SELECT id FROM pedido WHERE fecha = CURRENT_DATE LIMIT 1000) p CROSS JOIN generate_series(1,5) g;
ROLLBACK;

\echo '--- R3 con trigger ---'
BEGIN;
INSERT INTO detalle_pedido (pedido_id, producto_id, cantidad, precio_unitario)
SELECT p.id, 1, 1, 10.00 FROM (SELECT id FROM pedido WHERE fecha = CURRENT_DATE LIMIT 1000) p CROSS JOIN generate_series(1,5) g;
ROLLBACK;

\echo '--- R3 sin trigger ---'
BEGIN;
ALTER TABLE detalle_pedido DISABLE TRIGGER trg_detalle_resumen;
INSERT INTO detalle_pedido (pedido_id, producto_id, cantidad, precio_unitario)
SELECT p.id, 1, 1, 10.00 FROM (SELECT id FROM pedido WHERE fecha = CURRENT_DATE LIMIT 1000) p CROSS JOIN generate_series(1,5) g;
ALTER TABLE detalle_pedido ENABLE TRIGGER trg_detalle_resumen;
ROLLBACK;

\echo '--- auditoria final ---'
SELECT COUNT(*) AS diferencias FROM v_auditoria_resumen;
