# Spec: vista_pedidos_usuario

**Archivo afectado:** `TP5/views.sql`
**Base de datos:** `tp_food_store` (PostgreSQL)
**Fecha:** 2026-09
**Estado:** Propuesta

---

## 1. Objetivo

Exponer los pedidos del sistema con los datos identificatorios del cliente que los realizó,
sin revelar datos de contacto (email y teléfono), de modo que pueda otorgarse `SELECT` sobre
la vista sin dar acceso a la tabla base `cliente`.

## 2. Reporte que cubre

Historial de pedidos con el comprador (reporte de ventas, seguimiento de pedidos por cliente).

## 3. Columnas a exponer

| Columna           | Origen           | Descripción                          |
|-------------------|------------------|--------------------------------------|
| `id_pedido`       | `pedido`         | Identificador del pedido             |
| `id_cliente`      | `cliente`        | Identificador del cliente (FK)       |
| `nombre_cliente`  | `cliente.nombre` | Nombre del cliente (identificación)  |
| `fecha_pedido`    | `pedido`         | Fecha y hora del pedido (TIMESTAMPTZ)|
| `forma_pago`      | `pedido`         | Forma de pago (ENUM)                 |

## 4. Criterio de seguridad (columna oculta)

**Se ocultan las columnas `email` y `telefono` de `cliente`.** Son datos de contacto
personales. Esta vista permite otorgar `SELECT` a perfiles de ventas/estadística sin que
tengan acceso a la tabla `cliente` base ni a sus datos sensibles.

## 5. Filtro de vigencia

- `cliente.activo = TRUE` → solo clientes vigentes (borrado lógico), evitando reportar
  operaciones de clientes dados de baja.

## 6. Consulta manual equivalente (para verificación)

```sql
SELECT p.id_pedido, c.id_cliente, c.nombre, p.fecha_pedido, p.forma_pago
FROM pedido p
JOIN cliente c ON p.id_cliente = c.id_cliente
WHERE c.activo = TRUE;
```

## 7. Criterios de aceptación

- **CA-1:** La vista no incluye `email` ni `telefono`.
- **CA-2:** Los EXCEPT bidireccionales entre vista y consulta manual devuelven **0 filas**.
- **CA-3:** La vista no modifica el modelo de datos.

## 8. Objeto a crear

```sql
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
```