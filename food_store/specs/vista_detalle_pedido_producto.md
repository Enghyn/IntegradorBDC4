# Spec: vista_detalle_pedido_producto

**Archivo afectado:** `TP5/views.sql`
**Base de datos:** `tp_food_store` (PostgreSQL)
**Fecha:** 2026-09
**Estado:** Propuesta

---

## 1. Objetivo

Exponer las líneas de detalle de los pedidos con el nombre del producto asociado y el
subtotal de cada línea, para los reportes de detalle de pedido y facturación.

## 2. Reporte que cubre

Detalle de un pedido: qué productos se compraron, en qué cantidad, a qué precio facturado y
cuánto suma cada línea.

## 3. Columnas a exponer

| Columna                       | Origen                     | Descripción                              |
|-------------------------------|----------------------------|------------------------------------------|
| `id_pedido`                   | `detalle_pedido`           | Identificador del pedido (FK)            |
| `id_producto`                 | `detalle_pedido`           | Identificador del producto (FK)          |
| `nombre_producto`             | `producto.nombre`          | Nombre del producto                      |
| `cantidad`                    | `detalle_pedido`           | Cantidad vendida                         |
| `precio_unitario_facturado`   | `detalle_pedido`           | Precio facturado por unidad              |
| `subtotal`                    | derivada: `cantidad * precio_unitario_facturado` | Importe de la línea |

## 4. Decisión de vigencia (decisión de diseño documentada)

**No se filtra por `producto.activo`.** El detalle de un pedido es un **dato histórico**: el
pedido se facturó con el producto vigente en ese momento, y el producto puede haberse
desactivado (baja lógica) con posterioridad. Filtrar por vigencia actual distorsionaría los
reportes históricos. Solo se hace JOIN para traer el `nombre`, sin aplicar filtro de estado.

## 5. Criterio de seguridad

Sin columnas excluidas: los datos expuestos corresponden a operaciones comerciales (no hay
datos personales del cliente).

## 6. Consulta manual equivalente (para verificación)

```sql
SELECT d.id_pedido, d.id_producto, pr.nombre, d.cantidad,
       d.precio_unitario_facturado,
       (d.cantidad * d.precio_unitario_facturado) AS subtotal
FROM detalle_pedido d
JOIN producto pr ON d.id_producto = pr.id_producto;
```

## 7. Criterios de aceptación

- **CA-1:** La vista incluye la columna derivada `subtotal`.
- **CA-2:** Los EXCEPT bidireccionales entre vista y consulta manual devuelven **0 filas**.
- **CA-3:** La vista no aplica filtro de producto activo (no distorsiona historial).

## 8. Objeto a crear

```sql
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
```