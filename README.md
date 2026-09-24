# Trabajo Práctico Integrador — Food Store (Bases de Datos II)

Este repositorio contiene el trabajo práctico integrador de la materia **Bases de Datos II**: una base de datos PostgreSQL llamada `food_store` pensada para un comercio de alimentos, cargada con datos sintéticos a gran escala (10 categorías, 20.000 clientes, 50.000 productos, 200.000 pedidos y ~700.000 líneas de detalle).

A lo largo del TP trabajamos tres ejes:

1. **Modelado y carga masiva**: diseño del esquema relacional y generación de datos sintéticos que respetan todas las restricciones.
2. **Optimización con índices**: análisis de rendimiento de las consultas analíticas (3.1, 3.2 y 3.3), creación de índices secundarios/parciales y verificación de la aceleración con `EXPLAIN (ANALYZE, BUFFERS, TIMING)`.
3. **Medición y documentación**: registro de tiempos de ejecución, planes de ejecución y pruebas de impacto en escrituras, todo volcado en el informe de mediciones.

---

## 🚀 Requisitos e Instalación

### 1. Requisitos de software

- **PostgreSQL** (versión 13 o superior).
- Un cliente para ejecutar consultas: **DBeaver** o la consola **psql**.

### 2. Crear la base de datos local `tp_food_store`

Los scripts están pensados para correr sobre la base `tp_food_store` y, por defecto, utilizan el puerto **5433** (así lo dejamos configurado en nuestras conexiones). Si en tu máquina PostgreSQL usa el puerto estándar **5432**, simplemente ajustá el puerto en la conexión.

Desde **DBeaver**:

1. Creá una nueva conexión a tu servidor PostgreSQL.
2. Click derecho sobre la conexión → **Create → Database**.
3. Escribí el nombre `tp_food_store` y guardá.

Desde **psql** (alternativa):

```sql
CREATE DATABASE tp_food_store;
```

### 3. Importar el esquema base

Ejecutá el archivo `food_store/schema.sql` sobre `tp_food_store`. Este script crea:

- Los tipos enumerados (por ejemplo, `forma_pago_enum`).
- Las tablas `cliente`, `categoria`, `producto`, `pedido` y `detalle_pedido`, con sus claves primarias, claves foráneas y restricciones `CHECK`.
- Los índices de rendimiento básicos del esquema original.

### 4. Cargar los datos de prueba

Ejecutá después `food_store/data.sql`. Este script carga (todo dentro de transacciones, con `ANALYZE` al final):

- 10 categorías base.
- 20.000 clientes.
- 50.000 productos distribuidos entre categorías.
- 200.000 pedidos asociados a clientes.
- Las líneas de `detalle_pedido` (entre 2 y 5 productos por pedido).

### 5. Verificación rápida

Para confirmar que todo quedó bien cargado, podés correr:

```sql
SELECT COUNT(*) FROM producto;        -- ~50.000
SELECT COUNT(*) FROM pedido;          -- ~200.000
SELECT COUNT(*) FROM detalle_pedido;  -- ~700.000
```

---

## 🛠️ Estructura del Repositorio

Todo el material del TP está organizado dentro de la carpeta `food_store/`:

| Archivo / Carpeta | ¿Qué es? |
|---|---|
| `food_store/schema.sql` | Estructura inicial de las tablas (DDL). Es la única fuente estructural del esquema. |
| `food_store/data.sql` | Carga de datos sintéticos de prueba (categorías, clientes, productos, pedidos y detalles). |
| `food_store/queries.sql` | Consultas analíticas del workload (3.1 Top clientes, 3.2 Precio sobre promedio, 3.3 Pedidos grandes) junto con ejemplos de `EXPLAIN` comentados. |
| `food_store/indices.sql` | Creación de los índices de optimización para las consultas 3.1, 3.2 y 3.3. Los `CREATE INDEX IF NOT EXISTS` lo hacen idempotente (se puede correr varias veces sin romper nada). |
| `food_store/informe_mediciones.md` | Documento con todas las mediciones de rendimiento, planes de ejecución y análisis de impacto en escrituras. |
| `food_store/specs/` | Especificaciones técnicas por feature: diseño de las vistas e índices propuestos. |
| `food_store/DUIA.md` | Bitácora de uso de IA durante el desarrollo del TP. |
| `food_store/views.sql` | Creación de las vistas estándar (`vista_productos_vigentes_categoria`, `vista_pedidos_usuario`, `vista_detalle_pedido_producto`) y su verificación de equivalencia con `EXCEPT`. |
| `food_store/materializadas.sql` | Vista materializada de facturación por categoría y mes (`mv_facturacion_categoria_mes`, creada con `WITH DATA`) + índice único `(categoria_id, mes)` que habilita `REFRESH CONCURRENTLY` + verificación `EXCEPT` + módulo de medición (Parte C). |
| `food_store/specs/vista_materializada_facturacion_categoria_mes.md` | Especificación técnica de la vista materializada: objetivo, columnas, decisiones de diseño y criterios de aceptación. |

---

## 📊 Cómo Reproducir las Pruebas

Las mediciones que aparecen en el informe se obtuvieron siguiendo este flujo. Acá te dejamos el paso a paso para reproducirlas.

### 1. Vistas estándar

Ejecutá el archivo `food_store/views.sql` sobre `tp_food_store`. Crea las tres vistas estándar (usa `CREATE OR REPLACE VIEW`, así que se puede re-ejecutar sin problemas):

- `vista_productos_vigentes_categoria` → catálogo de productos vigentes con el nombre de su categoría.
- `vista_pedidos_usuario` → pedidos con los datos identificatorios del cliente (sin exponer email ni teléfono).
- `vista_detalle_pedido_producto` → líneas de detalle con el nombre del producto y el subtotal facturado.

Cada vista viene acompañada de su verificación de equivalencia con `EXCEPT` bidireccional contra la consulta manual equivalente: si ambas versiones devuelven el mismo resultado, el `EXCEPT` devuelve **0 filas** (el valor esperado para las tres).

### 2. Probar las consultas en frío (sin índices)

Con la base recién cargada (todavía sin los índices de `indices.sql`), corré las consultas analíticas usando `EXPLAIN (ANALYZE, BUFFERS, TIMING)` para capturar el plan y los tiempos base:

```sql
EXPLAIN (ANALYZE, BUFFERS, TIMING)
SELECT c.id_cliente, c.nombre,
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

Las consultas completas (3.1, 3.2 y sus verificaciones) están en `food_store/queries.sql`. En esta etapa lo normal es ver escaneos secuenciales (`Seq Scan`) y tiempos altos: es el **baseline** con el que vamos a comparar.

### 3. Crear los índices

Ejecutá el archivo `food_store/indices.sql` sobre `tp_food_store`. Crea los cuatro índices de optimización:

- `idx_cliente_activo` → índice parcial sobre `cliente(id_cliente)` para el filtro `activo = TRUE`.
- `idx_detalle_pedido_id_pedido` → acceso por FK en `detalle_pedido(id_pedido)`.
- `idx_producto_categoria_precio` → índice compuesto y parcial sobre `producto(id_categoria, precio_lista)`.
- `idx_pedido_id_cliente` → acceso por FK en `pedido(id_cliente)`.

Como usan `IF NOT EXISTS`, correrlo de nuevo no da error.

### 4. Volver a correr las consultas (post-índices)

Repetí exactamente los mismos `EXPLAIN (ANALYZE, BUFFERS, TIMING)` del paso 1. Ahora deberías ver:

- Cambios en el plan de ejecución (por ejemplo, `Index Scan`/`Index Only Scan` en lugar de `Seq Scan` en los puntos críticos).
- Reducción de buffers de lectura/escritura y de `tuplas` procesadas.
- Tiempos de ejecución menores.

Resultados resumidos que registramos en `informe_mediciones.md`:

| Consulta | Antes | Después | Mejora |
|---|---|---|---|
| 3.1 Top 10 clientes | 3612.970 ms | 3478.948 ms | ~134 ms |
| 3.2 Precio sobre promedio | 251402.102 ms | 149374.371 ms | ~102 s |
| 3.3 Pedidos > 3 productos y > $5000 | 4107.925 ms | 3521.245 ms | ~586 ms |

### 5. Prueba de impacto en escrituras (`INSERT`)

Para comprobar que mantener un índice B-tree no encarece de forma preocupante las escrituras, hicimos pruebas de inserción masiva antes y después de crear los índices:

- 100.000 registros en `detalle_pedido`.
- 10.000 registros en `producto`.
- 20.000 registros en `pedido`.

La idea es comparar el `Execution Time` del `INSERT ... SELECT` con y sin el índice secundario presente y mirar cuánto tarda el trigger de validación de clave foránea. La conclusión general fue que el costo de mantenimiento del B-tree es **marginal frente a la validación de las claves foráneas**, que domina el tiempo total de inserción (el detalle numérico de cada prueba está en las secciones de evaluación de escrituras del informe).

### 6. (Opcional) Verificar equivalencia de consultas con `EXCEPT`

En `food_store/queries.sql` incluimos las verificaciones de equivalencia con `EXCEPT` bidireccional entre dos versiones de cada consulta analítica (una generada con IA y otra resuelta con CTE / funciones de ventana). A diferencia del `EXCEPT` de las vistas (paso 1), acá se valida que las dos implementaciones de las consultas 3.1 y 3.2 devuelvan el mismo resultado: si ambas versiones coinciden, ambos `EXCEPT` devuelven **0 filas**, lo que confirma que las reescrituras son equivalentes.

### 7. Vista materializada (Parte C)

**Qué es y por qué existe.** El reporte de **facturación por categoría de producto y mes** es el agregado más costoso del sistema: para responderlo el motor debe recorrer la totalidad de las ~700.000 líneas de `detalle_pedido`, unirlas con `pedido`, `producto` y `categoria`, y agregar todo por categoría y mes — sin ningún filtro que recorte las filas a procesar. Una **vista materializada** precomputa ese agregado y lo persiste como una tabla física, de modo que la consulta deja de pagar el costo del join y la agregación en caliente.

**Objetos creados** (archivo `food_store/materializadas.sql`):

- `mv_facturacion_categoria_mes` — vista materializada creada con **`WITH DATA`** (poblada al momento de la creación). Columnas: `categoria_id`, `categoria_nombre`, `mes`, `total_pedidos`, `total_unidades_vendidas`, `facturacion_total`.
- `idx_mv_facturacion_cat_mes_unq` — **índice único** sobre `(categoria_id, mes)`. Es el requisito de PostgreSQL para poder ejecutar `REFRESH MATERIALIZED VIEW CONCURRENTLY` a futuro.
- Verificación de equivalencia con `EXCEPT` bidireccional contra la consulta original sin materializar (ambos sentidos deben devolver **0 filas**).

**Cómo crearla:** ejecutá `food_store/materializadas.sql` sobre `tp_food_store`. El script incluye un `DROP MATERIALIZED VIEW IF EXISTS` inicial (las vistas materializadas no soportan `CREATE OR REPLACE` en PostgreSQL), por lo que se puede re-ejecutar sin errores.

**Cómo reproducir las mediciones:** al final del mismo script están los bloques `EXPLAIN (ANALYZE, BUFFERS, TIMING)`:

- **Bloque A** — consulta original sin materializar (baseline).
- **Bloque B** — `SELECT` desde la vista materializada.
- **Bloque C** — `REFRESH MATERIALIZED VIEW CONCURRENTLY`. *Nota:* el refresh es una *utility statement*, por lo que PostgreSQL no genera plan de ejecución; el tiempo se toma de la estadística de ejecución de DBeaver (Execute time).

**Resultados reales** (medidos el 2026-09-24 sobre la base local con datos masivos):

| Medición | Tiempo |
|---|---|
| Consulta original (sin materializar) | `2797.623 ms` |
| `SELECT` desde `mv_facturacion_categoria_mes` | `0.042 ms` |
| `REFRESH MATERIALIZED VIEW CONCURRENTLY` | ~10 s (70 filas actualizadas) |
| **Mejora original → MV** | **≈ 66.600×** (~4 órdenes de magnitud) |

**Frecuencia de refresco recomendada:** `REFRESH MATERIALIZED VIEW CONCURRENTLY` con frecuencia **diaria (nocturna, p. ej. 03:00)** programado por un job externo (cron / pg_cron). Justificación: las celdas de meses ya cerrados no cambian (histórico de facturación), solo se actualiza la celda del mes en curso; el costo del refresh (~10 s) se paga una sola vez fuera de horario pico; y `CONCURRENTLY` permite actualizar el snapshot **sin bloquear las lecturas** del reporte.

**Implicancia para los usuarios (consistencia):** la vista materializada es un **snapshot**, no las tablas base. Entre un refresco y el siguiente, los pedidos ingresados después no aparecen hasta la próxima corrida: el dato puede estar desactualizado hasta 24 h (retraso máximo = frecuencia del refresh). Para meses cerrados esto es irrelevante; solo afecta la celda del mes corriente. Si una decisión exige el dato exacto al minuto, debe consultarse la consulta original sobre tablas base (con su costo) o reducir la frecuencia de refresh. El detalle completo de esta sección está en `food_store/informe_mediciones.md` → Parte C.

---

## ✒️ Autores / Integrantes
- **[Nombre y apellido]** — Enzo Giaquinta
- **[Nombre y apellido]** — Ramiro Salcedo
- **[Nombre y apellido]** — Ignacio Sanchez
- **[Nombre y apellido]** — Fernando Torrez
- **[Nombre y apellido]** — Agustin Contardi

**Comisión:** 4

---

*Base de datos FoodStore — PostgreSQL. Trabajo Práctico Integrador de Bases de Datos II.*