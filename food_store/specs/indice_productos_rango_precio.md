# SPEC-002 — Optimización de la Consulta de Productos con Precio Superior al Promedio de su Categoría

**Archivo afectado:** `food_store/queries.sql` (Consulta 3.2, Versión A)
**Base de datos:** `tp_food_store` (PostgreSQL)
**Fecha:** 2025-07
**Estado:** Propuesta

---

## 1. Objetivo

Reducir el costo de ejecución de la consulta que detecta productos cuyo precio de lista supera
el promedio de su categoría, eliminando los escaneos completos que genera la doble subconsulta
correlacionada sobre `producto`, y habilitando un Index-Only Scan mediante un índice compuesto
y parcial que cubra simultáneamente las columnas de correlación, agregación y filtro de precio.

### Consulta afectada

```sql
-- queries.sql — 3.2 Versión A: Productos con Precio Superior al Promedio de su Categoría
SELECT 
    p.id_producto,
    p.nombre AS nombre_producto,
    cat.nombre AS categoria,
    p.precio_lista,
    ROUND((
        SELECT AVG(p2.precio_lista)
        FROM producto p2
        WHERE p2.id_categoria = p.id_categoria
          AND p2.activo = TRUE
    ), 2) AS precio_promedio_categoria
FROM producto p
JOIN categoria cat ON p.id_categoria = cat.id_categoria
WHERE cat.activo = TRUE
  AND p.activo = TRUE
  AND p.precio_lista > (
        SELECT AVG(p3.precio_lista)
        FROM producto p3
        WHERE p3.id_categoria = p.id_categoria
          AND p3.activo = TRUE
  )
ORDER BY cat.nombre ASC, p.precio_lista DESC;
```

---

## 2. Contexto del sistema

| Parámetro                              | Valor                                              |
|----------------------------------------|----------------------------------------------------|
| Motor                                  | PostgreSQL                                         |
| Base de datos                          | `tp_food_store`                                    |
| Volumen — `producto`                   | 50 000 filas                                       |
| Volumen — `categoria`                  | ~10 filas activas                                  |
| Selectividad `activo` en `producto`    | Alta (mayoría activos = TRUE)                      |
| Subconsultas correlacionadas           | 2 (`p2` para proyección AVG, `p3` para filtro WHERE) |

---

## 3. Frecuencia estimada de ejecución

**Alta.** La consulta alimenta reportes de análisis de precios y gestión de catálogo, ejecutada
con frecuencia en paneles de administración. Su latencia impacta directamente la experiencia
del usuario en las vistas de administración de productos.

---

## 4. Columnas participantes

| Tabla       | Columna        | Rol en la consulta                                                  |
|-------------|----------------|---------------------------------------------------------------------|
| `producto`  | `id_categoria` | Clave de correlación en ambas subconsultas; JOIN con `categoria`    |
| `producto`  | `precio_lista` | Argumento de `AVG` en subconsultas; comparación en `WHERE`; proyección y `ORDER BY` |
| `producto`  | `activo`       | Predicado de filtro en ambas subconsultas y en el `WHERE` externo   |
| `producto`  | `id_producto`  | PK; proyección                                                      |
| `producto`  | `nombre`       | Proyección                                                          |
| `categoria` | `id_categoria` | Clave JOIN con `producto`                                           |
| `categoria` | `nombre`       | Proyección y `ORDER BY`                                             |
| `categoria` | `activo`       | Filtro `WHERE` externo                                              |

---

## 5. Diagnóstico del estado actual

### 5.1 Índices existentes relevantes

| Índice                          | Tabla       | Columna(s)                              | Tipo                  |
|---------------------------------|-------------|-----------------------------------------|-----------------------|
| `producto_pkey`                 | `producto`  | `id_producto`                           | PK (btree)            |
| `idx_producto_categoria_activo` | `producto`  | `(id_categoria)` WHERE activo = TRUE    | btree parcial         |
| `categoria_pkey`                | `categoria` | `id_categoria`                          | PK (btree)            |

### 5.2 Problemas identificados

1. **Doble subconsulta correlacionada sin cobertura completa en el índice:** la consulta
   contiene dos subconsultas correlacionadas lógicamente idénticas (`p2` para la proyección
   del promedio y `p3` para el filtro `WHERE precio_lista >`). Para cada fila del outer scan
   sobre `producto`, el planificador ejecuta al menos un Bitmap Index Scan sobre
   `idx_producto_categoria_activo` seguido de un Bitmap Heap Scan para recuperar `precio_lista`
   desde el heap, dado que esa columna no está en el índice. Con 50 000 productos distribuidos
   en ~10 categorías, esto puede acumularse en miles de accesos al heap por ejecución.

2. **Índice existente insuficiente para Index-Only Scan:** `idx_producto_categoria_activo`
   cubre `id_categoria WHERE activo = TRUE` pero no incluye `precio_lista`. Esto impide que
   el planificador resuelva `AVG(precio_lista)` directamente desde el índice — debe acceder
   al heap por cada fila activa de la categoría para leer el precio, generando I/O adicional
   que escala con el volumen de la tabla.

3. **Ausencia de `precio_lista` en cualquier índice útil para esta consulta:** el filtro
   `p.precio_lista > AVG(...)` y la proyección del promedio en el `SELECT` requieren leer
   `precio_lista` de cada fila activa de la categoría. Sin un índice que cubra
   `(id_categoria, precio_lista)` con el predicado `activo = TRUE`, el planificador no puede
   construir un plan de Index-Only Scan y debe recurrir a accesos al heap para todas las
   invocaciones de las subconsultas correlacionadas.

---

## 6. Solución propuesta

Crear un índice adicional **sin modificar el modelo de datos ni las tablas base**, consistente
con la restricción del trabajo práctico.

### Índice — Índice compuesto y parcial sobre `producto(id_categoria, precio_lista)`

```sql
CREATE INDEX idx_producto_categoria_precio
    ON producto (id_categoria, precio_lista)
    WHERE activo = TRUE;
```

**Justificación:**

1. **Orden de columnas — `id_categoria` primero:** las subconsultas correlacionadas filtran
   con igualdad exacta (`WHERE p2.id_categoria = p.id_categoria`). Colocar `id_categoria`
   como primera columna del índice permite al planificador localizar directamente el subárbol
   de la categoría relevante, reduciendo el escaneo al subconjunto mínimo sin recorrer el
   árbol completo.

2. **`precio_lista` como segunda columna:** incluir `precio_lista` en el índice habilita el
   cálculo de `AVG(precio_lista)` y la comparación `precio_lista > AVG(...)` directamente
   desde la estructura del índice, sin necesidad de acceder al heap (Index-Only Scan). El
   índice actúa como una copia ordenada de los precios activos por categoría, disponible para
   el planificador sin I/O adicional al heap.

3. **Predicado parcial `WHERE activo = TRUE`:** excluye los productos inactivos del índice,
   reduciendo su tamaño en disco y focalizando el escaneo en el subconjunto exacto que usan
   las subconsultas. Esto alinea el índice propuesto con la convención ya utilizada en el
   proyecto (`idx_producto_categoria_activo`) y minimiza el overhead de mantenimiento en
   operaciones de escritura sobre productos inactivos.

**Nota de coexistencia:** `idx_producto_categoria_activo` se mantiene sin modificación, ya
que cubre otros patrones de acceso (listados de productos activos por categoría sin necesidad
de precio) y no es redundante respecto al índice propuesto, dado que este último agrega
`precio_lista` como segunda columna cubierta.

---

## 7. Propuestas alternativas descartadas

1. **Índice B-tree completo sobre `producto(activo)`:**
   La columna `activo` es de tipo `BOOLEAN` con baja cardinalidad (~mayoría de filas en
   `TRUE`). Un índice tradicional completo sobre esta columna sería descartado por el
   optimizador de PostgreSQL debido a su baja selectividad: con la mayoría de filas siendo
   `TRUE`, un Index Scan resulta más costoso que un Seq Scan. Adicionalmente, no aporta
   ningún orden útil para las subconsultas que necesitan localizar y agregar `precio_lista`
   por `id_categoria`.

2. **Índice simple sobre `producto(precio_lista)` sin `id_categoria`:**
   Las subconsultas correlacionadas agrupan explícitamente por `id_categoria`
   (`WHERE p2.id_categoria = p.id_categoria`). Un índice únicamente sobre `precio_lista` no
   permite localizar eficientemente los precios de una categoría específica, ya que los
   valores de precio están intercalados entre categorías en el árbol B-tree. El planificador
   necesitaría recorrer el índice completo de precios para filtrar luego por categoría,
   resultando en una eficiencia similar o inferior a un Seq Scan para este patrón de acceso
   de tipo grouping/aggregation.

---

## 8. Criterios de aceptación

### CA-1 — Uso del nuevo índice en las subconsultas correlacionadas

El plan de ejecución (`EXPLAIN ANALYZE`) debe mostrar
`Index Only Scan using idx_producto_categoria_precio` o
`Bitmap Index Scan on idx_producto_categoria_precio` en los nodos correspondientes a las
subconsultas correlacionadas, en lugar de `Seq Scan on producto` o
`Bitmap Heap Scan on producto`.

### CA-2 — Reducción del tiempo de ejecución demostrada con EXPLAIN ANALYZE

El tiempo de ejecución (`Execution Time`) registrado en `EXPLAIN (ANALYZE, BUFFERS, TIMING)`
debe ser menor al valor baseline medido antes de la creación del índice. La mejora debe quedar
documentada comparando los planes pre/post-índice en el archivo de entrega.

```sql
-- Medición post-índice (ejecutar después de CREATE INDEX):
EXPLAIN (ANALYZE, BUFFERS, TIMING)
SELECT 
    p.id_producto,
    p.nombre AS nombre_producto,
    cat.nombre AS categoria,
    p.precio_lista,
    ROUND((
        SELECT AVG(p2.precio_lista)
        FROM producto p2
        WHERE p2.id_categoria = p.id_categoria
          AND p2.activo = TRUE
    ), 2) AS precio_promedio_categoria
FROM producto p
JOIN categoria cat ON p.id_categoria = cat.id_categoria
WHERE cat.activo = TRUE
  AND p.activo = TRUE
  AND p.precio_lista > (
        SELECT AVG(p3.precio_lista)
        FROM producto p3
        WHERE p3.id_categoria = p.id_categoria
          AND p3.activo = TRUE
  )
ORDER BY cat.nombre ASC, p.precio_lista DESC;
```

### CA-3 — Eliminación o reducción de Bitmap Heap Scans sobre `producto`

El plan post-índice no debe mostrar `Seq Scan on producto` ni `Bitmap Heap Scan on producto`
en los nodos de las subconsultas correlacionadas. Se acepta `Bitmap Heap Scan` únicamente si
las `Heap Blocks` reportadas son significativamente inferiores al baseline, evidenciando una
reducción real del acceso al heap.

### CA-4 — Sin modificación del modelo de datos

La solución no debe incluir ningún `ALTER TABLE`, `DROP COLUMN`, ni cambio de tipo de dato
en las tablas `producto` o `categoria`.

### CA-5 — Equivalencia funcional del resultado

La consulta Versión A (subconsultas correlacionadas) debe retornar exactamente los mismos
registros que la Versión B (window functions). Verificar con el bloque `EXCEPT` bidireccional
ya definido en `queries.sql`, que debe devolver 0 filas en ambas direcciones.

---

## 9. Objetos a crear

```sql
-- Objeto 1: índice compuesto y parcial sobre producto para subconsultas correlacionadas
-- Tipo: B-tree compuesto parcial (columnas: id_categoria, precio_lista; condición: activo = TRUE)
-- Justificación: habilita Index-Only Scan para AVG(precio_lista) por categoría en las
--                subconsultas, eliminando accesos al heap y reduciendo el costo de la
--                doble subconsulta correlacionada.
CREATE INDEX idx_producto_categoria_precio
    ON producto (id_categoria, precio_lista)
    WHERE activo = TRUE;
```

> Este objeto debe definirse en el archivo de índices/vistas de la semana (`indices.sql`),
> **no** en `schema.sql` ni en `queries.sql`.

---

## 10. Fuera de alcance

- Modificación de las tablas base (`ALTER TABLE`).
- Creación de tablas de resumen o vistas materializadas.
- Reescritura de la Versión A a Versión B (window functions): la comparación entre ambas
  versiones es objeto de análisis en `queries.sql`, no de esta spec.
- Eliminación o modificación del índice existente `idx_producto_categoria_activo`.
- Ajuste de parámetros de configuración de PostgreSQL (`work_mem`, `enable_seqscan`, etc.).
- Optimización de la consulta 3.1 (ranking de clientes): cubierta en SPEC-001.
