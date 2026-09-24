-- ============================================================================
-- VIEWS.SQL — VISTAS DEL SISTEMA (Parte B — TP Unidad 3, Semana 5)
-- Base de datos: tp_food_store_local (PostgreSQL)
--
-- Contenido:
--   1. vista_productos_vigentes_categoria  (spec: specs/vista_productos_vigentes_categoria.md)
--   2. vista_pedidos_usuario               (spec: specs/vista_pedidos_usuario.md)
--   3. vista_detalle_pedido_producto       (spec: specs/vista_detalle_pedido_producto.md)
--
-- Normas:
--   - NO modifica el modelo de datos (no hay ALTER, DROP ni cambios de tipo).
--   - Cada vista va seguida de la verificación de equivalencia (EXCEPT bidireccional)
--     contra la consulta manual escrita por el estudiante. Ambos EXCEPT deben
--     devolver 0 filas.
--   - Nota: las vistas se crean con CREATE OR REPLACE VIEW para permitir
--     re-ejecución idempotente durante el desarrollo.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. VISTA: VISTA_PRODUCTOS_VIGENTES_CATEGORIA
--    Catálogo de productos vigentes con el nombre de su categoría.
--    Filtro de vigencia: producto.activo = TRUE AND categoria.activo = TRUE
--    Columnas: id_producto, nombre_producto, nombre_categoria, precio_lista, stock
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW vista_productos_vigentes_categoria AS
SELECT
    p.id_producto,
    p.nombre AS nombre_producto,
    cat.nombre AS nombre_categoria,
    p.precio_lista,
    p.stock
FROM producto p
JOIN categoria cat ON p.id_categoria = cat.id_categoria
WHERE p.activo = TRUE
  AND cat.activo = TRUE;

-- Verificación de equivalencia — Vista 1 vs consulta manual (deben dar 0 filas)
(
  SELECT v.id_producto, v.nombre_producto, v.nombre_categoria, v.precio_lista, v.stock
  FROM vista_productos_vigentes_categoria v
)
EXCEPT
(
  SELECT p.id_producto, p.nombre, cat.nombre, p.precio_lista, p.stock
  FROM producto p
  JOIN categoria cat ON p.id_categoria = cat.id_categoria
  WHERE p.activo = TRUE
    AND cat.activo = TRUE
);

(
  SELECT p.id_producto, p.nombre, cat.nombre, p.precio_lista, p.stock
  FROM producto p
  JOIN categoria cat ON p.id_categoria = cat.id_categoria
  WHERE p.activo = TRUE
    AND cat.activo = TRUE
)
EXCEPT
(
  SELECT v.id_producto, v.nombre_producto, v.nombre_categoria, v.precio_lista, v.stock
  FROM vista_productos_vigentes_categoria v
);

-- ----------------------------------------------------------------------------
-- 2. VISTA: VISTA_PEDIDOS_USUARIO
--    Pedidos con datos identificatorios del cliente.
--    CRITERIO DE SEGURIDAD: oculta email y telefono de cliente, permitiendo
--    otorgar SELECT sobre la vista sin dar acceso a la tabla base.
--    Filtro de vigencia: cliente.activo = TRUE
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW vista_pedidos_usuario AS
SELECT
    p.id_pedido,
    c.id_cliente,
    c.nombre AS nombre_cliente,
    p.fecha_pedido,
    p.forma_pago
FROM pedido p
JOIN cliente c ON p.id_cliente = c.id_cliente
WHERE c.activo = TRUE;

-- Verificación de equivalencia — Vista 2 vs consulta manual (deben dar 0 filas)
(
  SELECT v.id_pedido, v.id_cliente, v.nombre_cliente, v.fecha_pedido, v.forma_pago
  FROM vista_pedidos_usuario v
)
EXCEPT
(
  SELECT p.id_pedido, c.id_cliente, c.nombre, p.fecha_pedido, p.forma_pago
  FROM pedido p
  JOIN cliente c ON p.id_cliente = c.id_cliente
  WHERE c.activo = TRUE
);

(
  SELECT p.id_pedido, c.id_cliente, c.nombre, p.fecha_pedido, p.forma_pago
  FROM pedido p
  JOIN cliente c ON p.id_cliente = c.id_cliente
  WHERE c.activo = TRUE
)
EXCEPT
(
  SELECT v.id_pedido, v.id_cliente, v.nombre_cliente, v.fecha_pedido, v.forma_pago
  FROM vista_pedidos_usuario v
);

-- ----------------------------------------------------------------------------
-- 3. VISTA: VISTA_DETALLE_PEDIDO_PRODUCTO
--    Líneas de detalle con el nombre del producto y el subtotal facturado.
--    DECISIÓN DE DISEÑO: NO filtra por producto.activo (dato histórico: un pedido
--    ya facturado no debe desaparecer si el producto se dio de baja después).
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW vista_detalle_pedido_producto AS
SELECT
    d.id_pedido,
    d.id_producto,
    pr.nombre AS nombre_producto,
    d.cantidad,
    d.precio_unitario_facturado,
    (d.cantidad * d.precio_unitario_facturado) AS subtotal
FROM detalle_pedido d
JOIN producto pr ON d.id_producto = pr.id_producto;

-- Verificación de equivalencia — Vista 3 vs consulta manual (deben dar 0 filas)
(
  SELECT v.id_pedido, v.id_producto, v.nombre_producto, v.cantidad,
         v.precio_unitario_facturado, v.subtotal
  FROM vista_detalle_pedido_producto v
)
EXCEPT
(
  SELECT d.id_pedido, d.id_producto, pr.nombre, d.cantidad,
         d.precio_unitario_facturado,
         (d.cantidad * d.precio_unitario_facturado) AS subtotal
  FROM detalle_pedido d
  JOIN producto pr ON d.id_producto = pr.id_producto
);

(
  SELECT d.id_pedido, d.id_producto, pr.nombre, d.cantidad,
         d.precio_unitario_facturado,
         (d.cantidad * d.precio_unitario_facturado) AS subtotal
  FROM detalle_pedido d
  JOIN producto pr ON d.id_producto = pr.id_producto
)
EXCEPT
(
  SELECT v.id_pedido, v.id_producto, v.nombre_producto, v.cantidad,
         v.precio_unitario_facturado, v.subtotal
  FROM vista_detalle_pedido_producto v
);

-- ============================================================================
-- RESULTADOS DE VERIFICACIÓN (completar tras ejecutar)
--   Vista 1 (productos vigentes):          EXCEPT A<->B = __ filas  (esperado 0)
--   Vista 2 (pedidos usuario):             EXCEPT A<->B = __ filas  (esperado 0)
--   Vista 3 (detalle pedido producto):     EXCEPT A<->B = __ filas  (esperado 0)
-- ============================================================================