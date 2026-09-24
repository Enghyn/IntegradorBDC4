# SPEC-001 — Optimización de la Consulta de Ranking de Clientes por Facturación Histórica

**Archivo afectado:** `food_store/queries.sql` (Consulta 3.1, Versión A)
**Base de datos:** `tp_food_store` (PostgreSQL)
**Fecha:** 2025-07
**Estado:** Propuesta

---

## 1. Objetivo

Reducir el costo de ejecución de la consulta que obtiene el **Top 10 de clientes con mayor
facturación histórica**, eliminando los escaneos secuenciales sobre las tablas `cliente`,
`pedido` y `detalle_pedido`, y agilizando el costo de las uniones (JOINs) mediante índices
específicos sobre las columnas participantes.

### Consulta afectada

```sql
-- queries.sql — 3.1 Versión A: Top 10 Clientes por Gasto Total
SELECT
    c.id_cliente,
    c.nombre AS nombre_cliente,
    COUNT(DISTINCT p.id_pedido) AS cantidad_pedidos,
    ROUND(SUM(dp.cantidad * dp.precio_unitario_facturado)::NUMERIC, 2) AS monto_total_gastado
FROM cliente c
JOIN pedido p ON c.id_cliente = p.id_cliente
JOIN detalle_pedido dp ON p.id_pedido = dp.id_pedido
WHERE c.activo = TRUE
GROUP BY c.id_cliente, c.nombre
ORDER BY monto_total_gastado DESC
LIMIT 10;
```

---

## 2. Contexto del sistema

| Parámetro                      | Valor                                     |
|--------------------------------|-------------------------------------------|
| Motor                          | PostgreSQL                                |
| Base de datos                  | `tp_food_store`                           |
| Volumen — `cliente`            | 20 000 filas                              |
| Volumen — `pedido`             | 200 000 filas                             |
| Volumen — `detalle_pedido`     | ~700 000 filas                            |
| Selectividad `activo`          | Alta (mayoría de clientes activos = TRUE) |

---

## 3. Frecuencia estimada de ejecución

**Media.** La consulta alimenta un reporte analítico/gerencial que se ejecuta de forma
periódica (panel de control gerencial). No es una consulta OLTP de tiempo real, pero su
latencia impacta directamente la experiencia del usuario en el dashboard.

---

## 4. Columnas participantes

| Tabla            | Columna                      | Rol en la consulta                      |
|------------------|------------------------------|-----------------------------------------|
| `cliente`        | `activo`                     | Filtro `WHERE c.activo = TRUE`          |
| `cliente`        | `id_cliente`                 | Clave JOIN con `pedido`; `GROUP BY`     |
| `cliente`        | `nombre`                     | Proyección; `GROUP BY`                  |
| `pedido`         | `id_cliente`                 | Clave JOIN con `cliente`                |
| `pedido`         | `id_pedido`                  | Clave JOIN con `detalle_pedido`         |
| `detalle_pedido` | `id_pedido`                  | Clave JOIN con `pedido`                 |
| `detalle_pedido` | `cantidad`                   | Expresión de agregación (`SUM`)         |
| `detalle_pedido` | `precio_unitario_facturado`  | Expresión de agregación (`SUM`)         |

---

## 5. Diagnóstico del estado actual

### 5.1 Índices existentes relevantes

| Índice                 | Tabla            | Columna(s)                  | Tipo               |
|------------------------|------------------|-----------------------------|--------------------|
| `cliente_pkey`         | `cliente`        | `id_cliente`                | PK (btree)         |
| `pedido_pkey`          | `pedido`         | `id_pedido`                 | PK (btree)         |
| `idx_pedido_cliente`   | `pedido`         | `id_cliente`                | btree              |
| `pk_detalle_pedido`    | `detalle_pedido` | `(id_pedido, id_producto)`  | PK compuesta (btree)|

### 5.2 Problemas identificados

1. **Seq Scan sobre `cliente`:** no existe un índice parcial sobre `activo = TRUE` en la
   tabla `cliente`. Con 20 000 filas, el planificador realiza un escaneo completo para
   filtrar los clientes activos antes del JOIN.

2. **Seq Scan potencial sobre `detalle_pedido` vía `id_pedido`:** aunque la PK compuesta
   `(id_pedido, id_producto)` cubre búsquedas por `id_pedido`, el planificador puede optar
   por un Bitmap Index Scan en lugar de un Index Scan directo al procesar 700 000 filas en
   el JOIN de agregación. Un índice dedicado sobre `id_pedido` mejora el plan de acceso.

3. **Ausencia de índice parcial en `cliente(activo)`:** el filtro `WHERE c.activo = TRUE`
   fuerza la lectura de todas las filas de `cliente` para descartar los inactivos.

---

## 6. Solución propuesta

Crear dos índices adicionales **sin modificar el modelo de datos ni las tablas base**,
consistente con la restricción del trabajo práctico.

### Índice 1 — Índice parcial sobre `cliente(activo)`

```sql
CREATE INDEX idx_cliente_activo
    ON cliente (id_cliente)
    WHERE activo = TRUE;
```

- **Justificación:** permite al planificador utilizar un Index Scan al aplicar el filtro
  `WHERE c.activo = TRUE`, evitando el Seq Scan sobre las 20 000 filas de `cliente`.
- **Tipo:** índice parcial B-tree (nativo de PostgreSQL, ya utilizado en el proyecto para
  `idx_producto_categoria_activo`).
- **Overhead de escritura:** mínimo; solo se actualiza cuando cambia la columna `activo`.

### Índice 2 — Índice dedicado sobre `detalle_pedido(id_pedido)`

```sql
CREATE INDEX idx_detalle_pedido_id_pedido
    ON detalle_pedido (id_pedido);
```

- **Justificación:** desambigua el acceso por `id_pedido` respecto a la PK compuesta
  `(id_pedido, id_producto)`. El planificador puede seleccionar un Index Scan más eficiente
  sobre las ~700 000 filas durante el JOIN de agregación, sin necesidad de leer la segunda
  columna de la PK.
- **Nota:** este índice ya fue evaluado en el archivo `queries.sql` para consultas puntuales
  (`WHERE id_pedido = 1`) con resultados confirmados. La presente spec extiende su
  justificación al contexto de la consulta de ranking.

---

## 7. Criterios de aceptación

### CA-1 — Eliminación de escaneos secuenciales en tablas grandes

El plan de ejecución (`EXPLAIN ANALYZE`) **no debe mostrar** `Seq Scan` sobre `cliente`
ni sobre `detalle_pedido` al ejecutar la consulta 3.1.

### CA-2 — Reducción del tiempo de ejecución demostrada con EXPLAIN ANALYZE

El tiempo de ejecución (`Execution Time`) registrado en `EXPLAIN ANALYZE` **debe ser menor**
al valor baseline medido antes de la creación de los índices. La mejora debe quedar
documentada comparando los planes pre/post-índice en el archivo de entrega.

```sql
-- Medición post-índice (ejecutar después de CREATE INDEX):
EXPLAIN (ANALYZE, BUFFERS, TIMING)
SELECT
    c.id_cliente,
    c.nombre AS nombre_cliente,
    COUNT(DISTINCT p.id_pedido) AS cantidad_pedidos,
    ROUND(SUM(dp.cantidad * dp.precio_unitario_facturado)::NUMERIC, 2) AS monto_total_gastado
FROM cliente c
JOIN pedido p ON c.id_cliente = p.id_cliente
JOIN detalle_pedido dp ON p.id_pedido = dp.id_pedido
WHERE c.activo = TRUE
GROUP BY c.id_cliente, c.nombre
ORDER BY monto_total_gastado DESC
LIMIT 10;
```

### CA-3 — Agilización del costo de las uniones (JOINs)

El plan post-índice debe mostrar al menos uno de los siguientes nodos de acceso en lugar
de Hash Join o Nested Loop sobre Seq Scan:

- `Index Scan using idx_cliente_activo`
- `Bitmap Index Scan on idx_detalle_pedido_id_pedido`
- `Index Scan using idx_detalle_pedido_id_pedido`

### CA-4 — Sin modificación del modelo de datos

La solución **no debe** incluir ningún `ALTER TABLE`, `DROP COLUMN`, ni cambio de tipo de
dato en las tablas `cliente`, `pedido` o `detalle_pedido`.

### CA-5 — Equivalencia funcional del resultado

La consulta optimizada debe retornar exactamente los mismos 10 registros que la versión
original. Verificar con el bloque `EXCEPT` bidireccional ya definido en `queries.sql`,
que debe devolver 0 filas en ambas direcciones.

---

## 8. Objetos a crear

```sql
-- Objeto 1: índice parcial en cliente para el filtro WHERE activo = TRUE
CREATE INDEX idx_cliente_activo
    ON cliente (id_cliente)
    WHERE activo = TRUE;

-- Objeto 2: índice en detalle_pedido para agilizar el JOIN por id_pedido
CREATE INDEX idx_detalle_pedido_id_pedido
    ON detalle_pedido (id_pedido);
```

> Estos objetos deben definirse en el archivo de índices/vistas de la semana,
> **no** en `queries.sql` ni en `schema.sql`.

---

## 9. Fuera de alcance

- Modificación de las tablas base (`ALTER TABLE`).
- Creación de tablas de resumen o vistas materializadas (fuera del alcance del TP).
- Optimización de la consulta 3.2 (productos sobre el promedio de categoría): objeto de
  una spec separada.
- Ajuste de parámetros de configuración de PostgreSQL (`work_mem`, `enable_seqscan`, etc.).

## 10. Propuestas alternativas descartadas

1. **Índice B-tree completo sobre `cliente(activo)`:**
   - *Descarte:* La columna `activo` posee baja cardinalidad (tipo `BOOLEAN` con ~95% en `TRUE`). Un índice tradicional completo sería ignorado por el optimizador. Se opta exclusivamente por el **índice parcial** (`WHERE activo = TRUE`).<br>

2. **Índice compuesto sobre `detalle_pedido(id_pedido, id_producto)`:**
   - *Descarte:* La tabla ya cuenta con la clave primaria compuesta `pk_detalle_pedido (id_pedido, id_producto)`. Crear un índice adicional idéntico representaría un caso directo de **sobreindexación y redundancia**.
