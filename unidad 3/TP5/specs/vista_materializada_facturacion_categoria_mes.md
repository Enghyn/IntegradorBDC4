# Spec: vista_materializada_facturacion_categoria_mes

**Archivo afectado:** `TP5/materializadas.sql`
**Base de datos:** `tp_food_store` (PostgreSQL)
**Fecha:** 2026-09
**Estado:** Propuesta

---

## 1. Objetivo

Optimizar el reporte agregado de **facturación por categoría de producto y mes**, uno de los
reportes analíticos más costosos del sistema: para responderlo el motor recorre la totalidad de
las líneas de `detalle_pedido` (~700.000) y las une con `pedido`, `producto` y `categoria`
antes de agregar. La vista materializada precomputa ese snapshot y reduce drásticamente el
tiempo de la consulta en caliente, mientras que su índice único habilita el refresco
concurrente (`REFRESH MATERIALIZED VIEW CONCURRENTLY`) sin bloquear las lecturas.

## 2. Reporte que cubre

Facturación histórica por categoría y mes: qué categoría facturó cuánto, con cuántos pedidos
únicos y cuántas unidades vendidas, mes a mes. Es la consulta analítica de la Semana 4 que
agrega `pedido → detalle_pedido → producto → categoria` agrupando por
`DATE_TRUNC('month', fecha_pedido)` e `id_categoria`.

## 3. Columnas a exponer

| Columna                 | Origen                                                          | Descripción                                   |
|-------------------------|-----------------------------------------------------------------|-----------------------------------------------|
| `categoria_id`          | `categoria.id_categoria`                                        | Identificador de la categoría                 |
| `categoria_nombre`      | `categoria.nombre`                                              | Nombre de la categoría                        |
| `mes`                   | derivada: `DATE_TRUNC('month', pedido.fecha_pedido)`            | Mes calendario (timestamptz truncado)         |
| `total_pedidos`         | derivada: `COUNT(DISTINCT pedido.id_pedido)`                    | Pedidos únicos del mes y categoría            |
| `total_unidades_vendidas` | derivada: `SUM(detalle_pedido.cantidad)`                      | Unidades vendidas                             |
| `facturacion_total`     | derivada: `SUM(cantidad * precio_unitario_facturado)`           | Importe facturado                             |

## 4. Decisiones de diseño

- **`WITH DATA`:** la MV se puebla en el momento de la creación; no queda vacía esperando un
  refresco inicial manual.
- **Índice único sobre `(categoria_id, mes)`:** requisito de PostgreSQL para
  `REFRESH MATERIALIZED VIEW CONCURRENTLY`. La combinación es única porque el `GROUP BY`
  agrupa exactamente por esas dos claves.
- **Sin `CREATE OR REPLACE`:** PostgreSQL no lo soporta para vistas materializadas; la
  re-ejecución se resuelve con `DROP MATERIALIZED VIEW IF EXISTS` (idempotencia en desarrollo).
- **Refresco concurrente:** se usa `REFRESH MATERIALIZED VIEW CONCURRENTLY` para que la
  actualización programada no bloquee las lecturas del reporte.

## 5. Datos / criterio de seguridad

Sin columnas excluidas: el reporte expone **agregados comerciales** (importes, unidades y
cantidad de pedidos por categoría y mes). La MV no consulta `cliente`, `email` ni `telefono`,
por lo que no expone datos personales de contacto.

## 6. Consulta manual equivalente (para verificación)

```sql
SELECT c.id_categoria, c.nombre,
       DATE_TRUNC('month', p.fecha_pedido),
       COUNT(DISTINCT p.id_pedido),
       SUM(dp.cantidad),
       SUM(dp.cantidad * dp.precio_unitario_facturado)
FROM pedido p
JOIN detalle_pedido dp ON p.id_pedido = dp.id_pedido
JOIN producto pr ON dp.id_producto = pr.id_producto
JOIN categoria c ON pr.id_categoria = c.id_categoria
GROUP BY c.id_categoria, c.nombre, DATE_TRUNC('month', p.fecha_pedido);
```

## 7. Criterios de aceptación

- **CA-1:** La MV se crea con `WITH DATA` (poblada al crearse).
- **CA-2:** Existe un índice único sobre `(categoria_id, mes)`.
- **CA-3:** Los EXCEPT bidireccionales entre la MV y la consulta manual devuelven **0 filas**.
- **CA-4:** El tiempo de respuesta de la consulta sobre la MV es menor que el de la consulta
  original sin materializar (evidencia: `EXPLAIN (ANALYZE, BUFFERS, TIMING)` pegado en el informe).
- **CA-5:** `REFRESH MATERIALIZED VIEW CONCURRENTLY mv_facturacion_categoria_mes` se ejecuta sin error.

## 8. Objeto a crear

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