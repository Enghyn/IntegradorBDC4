# Especificaciones de Consultas — Food Store

Base de datos: `food_store_test` (PostgreSQL)
Esquema de referencia: `db/schema.sql`

---

## SPEC 1: Consulta de Resumen (Agregación)

### Top 5 categorías por ingreso total facturado

**Objetivo:** Listar las 5 categorías con mayor ingreso total generado por ventas, considerando solo datos vigentes (productos activos y categorías activas).

### Tablas involucradas

| Tabla               | Alias | Rol                                           |
|---------------------|-------|-----------------------------------------------|
| `categoria`         | `cat` | Origen del nombre de categoría                |
| `producto`          | `p`   | Join con categoría, filtro de borrado lógico  |
| `detalle_pedido`    | `dp`  | Origen de cantidades y precios facturados     |

### Joins

```
categoria cat
  JOIN producto p ON p.id_categoria = cat.id_categoria
  JOIN detalle_pedido dp ON dp.id_producto = p.id_producto
```

### Filtros de borrado lógico (WHERE)

- `cat.activo = TRUE` → solo categorías vigentes
- `p.activo = TRUE` → solo productos vigentes

### Agrupación (GROUP BY)

- `cat.id_categoria`
- `cat.nombre`

### Columnas de salida

| # | Expresión                                             | Alias            | Descripción                      |
|---|-------------------------------------------------------|------------------|----------------------------------|
| 1 | `cat.nombre`                                          | `categoria`      | Nombre de la categoría           |
| 2 | `SUM(dp.cantidad)`                                    | `total_unidades` | Suma de unidades vendidas        |
| 3 | `SUM(dp.cantidad * dp.precio_unitario_facturado)`     | `ingreso_total`  | Ingreso total facturado          |

### Orden (ORDER BY)

- `ingreso_total DESC` (mayor ingreso primero)

### Corte (LIMIT)

- `LIMIT 5`

### Resultado esperado

5 filas, una por categoría, ordenadas de mayor a menor ingreso.

---

## SPEC 2: Consulta con Subconsulta

### Productos que nunca fueron vendidos

**Objetivo:** Listar todos los productos activos que no aparecen en ningún pedido registrado en el sistema.

### Tablas involucradas


| Tabla            | Alias | Rol                                                     |
|------------------|-------|---------------------------------------------------------|
| `producto`       | `p`   | Origen de productos a listar                            |
| `categoria`      | `cat` | Join para mostrar el nombre de categoría                |
| `detalle_pedido` | `dp`  | Subconsulta: fuente de productos que sí se vendieron    |

### Joins (consulta principal)

```
producto p
  JOIN categoria cat ON p.id_categoria = cat.id_categoria
```

### Subconsulta (NOT IN)

```sql
SELECT dp.id_producto
FROM detalle_pedido dp
```

La subconsulta retorna todos los `id_producto` que aparecen en al menos un pedido. La consulta principal filtra con `p.id_producto NOT IN (...)`.

### Filtros de borrado lógico (WHERE)

- `p.activo = TRUE` → solo productos vigentes
- `cat.activo = TRUE` → solo categorías vigentes

### Columnas de salida

| # | Expresión       | Alias          | Descripción                  |
|---|-----------------|----------------|------------------------------|
| 1 | `p.id_producto` | `id_producto`  | Identificador del producto   |
| 2 | `p.nombre`      | `producto`     | Nombre del producto          |
| 3 | `cat.nombre`    | `categoria`    | Categoría a la que pertenece |
| 4 | `p.stock`       | `stock_actual` | Stock disponible actual      |

### Orden (ORDER BY)

- `p.nombre ASC` (orden alfabético)

### Corte

Ninguno (devuelve todos los productos sin ventas).

### Resultado esperado

N filas (todas las filas donde el producto nunca fue incluido en ningún `detalle_pedido`).

---

## Observaciones comunes

- Ambas consultas aplican filtro `activo = TRUE` sobre las tablas que lo soportan (`cliente`, `producto`, `categoria`). Las tablas `pedido` y `detalle_pedido` no tienen columna `activo`, por lo que no aplica borrado lógico sobre ellas.
- Los nombres de columnas y tipos están tomados directamente de `db/schema.sql`.
- Ninguna consulta usa columnas que no existan en el esquema.
