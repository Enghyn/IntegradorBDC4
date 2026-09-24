# Spec: vista_productos_vigentes_categoria

**Archivo afectado:** `TP5/views.sql`
**Base de datos:** `tp_food_store` (PostgreSQL)
**Fecha:** 2026-09
**Estado:** Propuesta

---

## 1. Objetivo

Exponer un catálogo limpio de productos **vigentes** (no borrados lógicamente) con el nombre
de su categoría, para los reportes de listado de productos y la navegación del catálogo.

## 2. Reporte que cubre

Listado de productos del sistema filtrado por vigencia, mostrando la categoría de cada uno.
Es una consulta de lectura frecuente en el sistema (catálogo / stock).

## 3. Columnas a exponer

| Columna            | Origen            | Descripción                       |
|--------------------|-------------------|-----------------------------------|
| `id_producto`      | `producto`        | Identificador del producto        |
| `nombre_producto`  | `producto.nombre` | Nombre del producto               |
| `nombre_categoria` | `categoria.nombre`| Categoría a la que pertenece      |
| `precio_lista`     | `producto`        | Precio de lista actual            |
| `stock`            | `producto`        | Stock disponible actual           |

## 4. Filtro de vigencia

- `producto.activo = TRUE` → solo productos vigentes (borrado lógico).
- `categoria.activo = TRUE` → solo categorías vigentes.

## 5. Criterio de seguridad

Sin columnas excluidas: los datos expuestos no son sensibles (no hay datos de contacto ni
identificatorios del cliente). Se omite también el estado interno `activo`, que no aporta
valor al consumidor de la vista.

## 6. Consulta manual equivalente (para verificación)

```sql
SELECT p.id_producto, p.nombre, cat.nombre, p.precio_lista, p.stock
FROM producto p
JOIN categoria cat ON p.id_categoria = cat.id_categoria
WHERE p.activo = TRUE
  AND cat.activo = TRUE;
```

## 7. Criterios de aceptación

- **CA-1:** La vista expone solo las 5 columnas declaradas.
- **CA-2:** Los EXCEPT bidireccionales entre vista y consulta manual devuelven **0 filas**.
- **CA-3:** La vista no modifica el modelo de datos (no toca columnas ni restricciones base).

## 8. Objeto a crear

```sql
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
```