# Design: Sistema de Carga Masiva de Datos

## 1. Visión General

El sistema consta de un script SQL autocontenido que utiliza funciones nativas de PostgreSQL para generar datos sintéticos a gran escala, garantizando integridad referencial y distribuciones realistas.

## 2. Arquitectura de Solución

### 2.1. Componentes

```
[Operador] 
    |
    v
[1. Script Validación] ---falla---> [Reporte de Errores]
    |
    aprueba
    |
    v
[2. Backup Script (pg_dump)]
    |
    v
[3. Script Principal SQL]
    |-- BEGIN TRANSACTION
    |-- Validación de Categorías
    |-- INSERT Clientes (generate_series)
    |-- INSERT Productos (generate_series + random)
    |-- INSERT Pedidos (generate_series + random)
    |-- INSERT Detalles (generate_series + random + JOIN)
    |-- COMMIT
    |
    v
[4. ANALYZE Script]
    |
    v
[Logs y Verificación]
```

### 2.2. Flujo de Ejecución

1. **Pre-validación** (Manual)
   - Revisar el script línea por línea
   - Verificar que no tiene comandos destructivos
   - Confirmar que apunta a base de datos de test

2. **Backup**
   ```bash
   pg_dump -U usuario -d foodstore_test > db/backups/foodstore_backup_$(date +%Y%m%d_%H%M%S).sql
   ```

3. **Ejecución del Script Principal**
   ```bash
   psql -U usuario -d foodstore_test -f db/seeds/load_massive_data.sql
   ```

4. **Post-análisis**
   ```bash
   psql -U usuario -d foodstore_test -c "ANALYZE cliente, producto, pedido, detalle_pedido;"
   ```

## 3. Diseño del Script SQL

### 3.1. Estructura General

```sql
-- ============================================
-- SCRIPT: Carga Masiva de Datos para Testing
-- Base de Datos: foodstore_test
-- ============================================

-- Configuración inicial
SET client_encoding = 'UTF8';
SET timezone = 'America/Argentina/Buenos_Aires';

-- Inicio de transacción
BEGIN;

-- Validación de prerrequisitos
DO $$
DECLARE
    v_cat_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_cat_count FROM categoria WHERE activo = TRUE;
    IF v_cat_count < 5 THEN
        RAISE EXCEPTION 'Se requieren al menos 5 categorías activas. Encontradas: %', v_cat_count;
    END IF;
    RAISE NOTICE 'Validación OK: % categorías activas encontradas', v_cat_count;
END $$;

-- [BLOQUE 1: Carga de Clientes]
-- [BLOQUE 2: Carga de Productos]
-- [BLOQUE 3: Carga de Pedidos]
-- [BLOQUE 4: Carga de Detalles de Pedido]

-- Verificación final
DO $$
DECLARE
    v_clientes INTEGER;
    v_productos INTEGER;
    v_pedidos INTEGER;
    v_detalles INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_clientes FROM cliente;
    SELECT COUNT(*) INTO v_productos FROM producto;
    SELECT COUNT(*) INTO v_pedidos FROM pedido;
    SELECT COUNT(*) INTO v_detalles FROM detalle_pedido;
    
    RAISE NOTICE 'Clientes insertados: %', v_clientes;
    RAISE NOTICE 'Productos insertados: %', v_productos;
    RAISE NOTICE 'Pedidos insertados: %', v_pedidos;
    RAISE NOTICE 'Detalles insertados: %', v_detalles;
END $$;

-- Commit de la transacción
COMMIT;

RAISE NOTICE 'Carga masiva completada exitosamente.';
```

### 3.2. Bloque 1: Generación de Clientes

**Estrategia**: Usar `generate_series` para crear 20,000 filas con datos calculados.

```sql
INSERT INTO cliente (nombre, email, telefono, activo, fecha_creacion)
SELECT 
    'Cliente ' || gs.n,
    'cliente_' || gs.n || '@foodstore.test',
    CASE 
        WHEN random() < 0.5 THEN '+54911' || LPAD(FLOOR(random() * 100000000)::TEXT, 8, '0')
        ELSE NULL
    END,
    CASE 
        WHEN random() < 0.95 THEN TRUE 
        ELSE FALSE 
    END,
    CURRENT_TIMESTAMP - (random() * INTERVAL '365 days')
FROM generate_series(1, 20000) AS gs(n);
```

**Puntos clave**:
- `generate_series(1, 20000)` genera secuencia 1..20000
- `random()` devuelve valor entre 0 y 1
- `LPAD` asegura 8 dígitos para el teléfono
- `INTERVAL '365 days'` distribuye fechas en el último año

### 3.3. Bloque 2: Generación de Productos

**Estrategia**: Distribuir productos equitativamente entre categorías usando módulo.

```sql
WITH categorias_activas AS (
    SELECT id_categoria, 
           ROW_NUMBER() OVER (ORDER BY id_categoria) AS cat_num
    FROM categoria 
    WHERE activo = TRUE
)
INSERT INTO producto (id_categoria, nombre, precio_lista, stock, activo)
SELECT 
    ca.id_categoria,
    'Producto ' || ca.cat_num || '-' || gs.n,
    500 + (random() * 4500)::NUMERIC(10,2),  -- Entre 500 y 5000
    FLOOR(random() * 201)::INTEGER,          -- Entre 0 y 200
    CASE 
        WHEN random() < 0.90 THEN TRUE 
        ELSE FALSE 
    END
FROM generate_series(1, 50000) AS gs(n)
CROSS JOIN categorias_activas ca
WHERE (gs.n - 1) % (SELECT COUNT(*) FROM categorias_activas) + 1 = ca.cat_num;
```

**Puntos clave**:
- CTE `categorias_activas` enumera las categorías disponibles
- `CROSS JOIN` + filtro con módulo distribuye productos equitativamente
- `::NUMERIC(10,2)` redondea a 2 decimales
- Nombre incluye categoría para evitar duplicados

### 3.4. Bloque 3: Generación de Pedidos

**Estrategia**: Asignar pedidos a clientes con distribución realista (algunos clientes compran más).

```sql
WITH clientes_activos AS (
    SELECT id_cliente, 
           ROW_NUMBER() OVER (ORDER BY id_cliente) AS cliente_num,
           COUNT(*) OVER () AS total_clientes
    FROM cliente
)
INSERT INTO pedido (id_cliente, fecha_pedido, forma_pago)
SELECT 
    ca.id_cliente,
    CURRENT_TIMESTAMP - (random() * INTERVAL '180 days'),
    CASE 
        WHEN rand_val < 0.60 THEN 'TARJETA'::forma_pago_enum
        WHEN rand_val < 0.90 THEN 'TRANSFERENCIA'::forma_pago_enum
        ELSE 'EFECTIVO'::forma_pago_enum
    END
FROM generate_series(1, 200000) AS gs(n)
CROSS JOIN LATERAL (SELECT random() AS rand_val) r
CROSS JOIN clientes_activos ca
WHERE ca.cliente_num = 1 + (ABS(hashtext(gs.n::TEXT)) % ca.total_clientes);
```

**Puntos clave**:
- `hashtext` + módulo distribuye pedidos pseudoaleatoriamente
- Algunos clientes tendrán múltiples pedidos, otros pocos
- Forma de pago según distribución 60/30/10
- Fechas en últimos 180 días

### 3.5. Bloque 4: Generación de Detalles de Pedido

**Estrategia**: Para cada pedido, insertar entre 2 y 5 productos únicos.

```sql
WITH pedidos_con_cantidad AS (
    SELECT 
        id_pedido,
        2 + FLOOR(random() * 4)::INTEGER AS num_productos  -- Entre 2 y 5
    FROM pedido
),
detalles_generados AS (
    SELECT 
        pc.id_pedido,
        gs.n AS item_num,
        pc.num_productos
    FROM pedidos_con_cantidad pc
    CROSS JOIN generate_series(1, 5) AS gs(n)  -- Máximo 5 productos
    WHERE gs.n <= pc.num_productos
),
productos_asignados AS (
    SELECT 
        dg.id_pedido,
        p.id_producto,
        p.precio_lista,
        ROW_NUMBER() OVER (PARTITION BY dg.id_pedido ORDER BY random()) AS rn
    FROM detalles_generados dg
    CROSS JOIN producto p
    WHERE p.activo = TRUE
)
INSERT INTO detalle_pedido (id_pedido, id_producto, cantidad, precio_unitario_facturado)
SELECT 
    pa.id_pedido,
    pa.id_producto,
    1 + FLOOR(random() * 10)::INTEGER,  -- Cantidad entre 1 y 10
    pa.precio_lista
FROM productos_asignados pa
WHERE pa.rn <= (SELECT num_productos FROM pedidos_con_cantidad WHERE id_pedido = pa.id_pedido);
```

**Puntos clave**:
- CTE `pedidos_con_cantidad` asigna 2-5 productos por pedido
- CTE `detalles_generados` expande cada pedido en N filas
- CTE `productos_asignados` selecciona productos aleatorios únicos
- `ROW_NUMBER() + WHERE rn <=` evita productos duplicados en el mismo pedido
- `precio_unitario_facturado` copia `precio_lista` actual

## 4. Consideraciones de Diseño

### 4.1. Unicidad de Nombres de Producto

Para garantizar unicidad en 50,000 productos:
- Formato: `Producto [id_categoria]-[numero_secuencial]`
- Ejemplo: "Producto 1-234", "Producto 2-567"

### 4.2. Distribución de Datos Realista

- **Clientes activos**: 95% (similar a churn rate real)
- **Productos activos**: 90% (productos descontinuados)
- **Forma de pago**: 60% tarjeta, 30% transferencia, 10% efectivo
- **Fechas**: distribuidas uniformemente en períodos especificados

### 4.3. Performance

**Optimizaciones aplicadas**:
- Uso de `generate_series` (set-based) en lugar de loops
- Inserción masiva con SELECT (batch insert)
- Evitar PL/pgSQL loops cuando no es necesario
- CTEs para claridad sin impacto en performance

**Tiempo estimado**:
- Clientes (20k): ~2 segundos
- Productos (50k): ~5 segundos
- Pedidos (200k): ~15 segundos
- Detalles (600k promedio): ~30 segundos
- **Total**: ~1 minuto

### 4.4. Integridad Referencial

**Orden de inserción** (respeta dependencias FK):
1. Cliente (sin dependencias)
2. Producto (depende de Categoría, ya existente)
3. Pedido (depende de Cliente)
4. Detalle_Pedido (depende de Pedido y Producto)

**Validación de FKs**:
- Se usa `CROSS JOIN` con tablas existentes para garantizar FKs válidas
- No se usan IDs hardcodeados, todo dinámico

## 5. Scripts Auxiliares

### 5.1. Script de Validación (Bash/PowerShell)

```bash
#!/bin/bash
# validate_script.sh

SCRIPT_FILE=$1

echo "Validando script SQL: $SCRIPT_FILE"

# Verificar comandos prohibidos
if grep -iE "(DROP|TRUNCATE|ALTER|DELETE|UPDATE)" "$SCRIPT_FILE" | grep -v "^--"; then
    echo "ERROR: Se encontraron comandos prohibidos (DROP, TRUNCATE, ALTER, DELETE, UPDATE)"
    exit 1
fi

# Verificar que solo inserta en tablas permitidas
if grep -iE "INSERT INTO" "$SCRIPT_FILE" | grep -viE "(cliente|producto|pedido|detalle_pedido)" | grep -v "^--"; then
    echo "ERROR: Se encontraron INSERT en tablas no permitidas"
    exit 1
fi

# Verificar transacción
if ! grep -q "BEGIN" "$SCRIPT_FILE"; then
    echo "ERROR: Falta BEGIN para iniciar transacción"
    exit 1
fi

if ! grep -q "COMMIT" "$SCRIPT_FILE"; then
    echo "ERROR: Falta COMMIT para confirmar transacción"
    exit 1
fi

echo "Validación OK"
exit 0
```

### 5.2. Script de Backup (Bash)

```bash
#!/bin/bash
# backup_db.sh

DB_NAME="foodstore_test"
DB_USER="postgres"
BACKUP_DIR="db/backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/foodstore_backup_$TIMESTAMP.sql"

echo "Creando backup de $DB_NAME..."

pg_dump -U $DB_USER -d $DB_NAME -F p -f "$BACKUP_FILE"

if [ $? -eq 0 ] && [ -s "$BACKUP_FILE" ]; then
    echo "Backup creado exitosamente: $BACKUP_FILE"
    ls -lh "$BACKUP_FILE"
    exit 0
else
    echo "ERROR: Fallo al crear backup"
    exit 1
fi
```

### 5.3. Script de ANALYZE (SQL)

```sql
-- analyze_tables.sql
\timing on

ANALYZE cliente;
ANALYZE producto;
ANALYZE pedido;
ANALYZE detalle_pedido;

-- Verificar estadísticas actualizadas
SELECT schemaname, tablename, n_live_tup, last_analyze
FROM pg_stat_user_tables
WHERE tablename IN ('cliente', 'producto', 'pedido', 'detalle_pedido')
ORDER BY tablename;
```

## 6. Manejo de Errores (Ver error-handling.md)

El script incluye bloques `DO` con `EXCEPTION` para capturar errores comunes y hacer rollback automático. Ver documento dedicado de manejo de errores.

## 7. Verificación Post-Carga

```sql
-- Verificar conteos
SELECT 'Clientes' AS tabla, COUNT(*) AS filas FROM cliente
UNION ALL
SELECT 'Productos', COUNT(*) FROM producto
UNION ALL
SELECT 'Pedidos', COUNT(*) FROM pedido
UNION ALL
SELECT 'Detalles', COUNT(*) FROM detalle_pedido;

-- Verificar distribución de productos por categoría
SELECT c.nombre AS categoria, COUNT(p.id_producto) AS cantidad_productos
FROM categoria c
LEFT JOIN producto p ON c.id_categoria = p.id_categoria
WHERE c.activo = TRUE
GROUP BY c.nombre
ORDER BY cantidad_productos DESC;

-- Verificar estadísticas de PostgreSQL
SELECT tablename, n_live_tup, n_dead_tup, last_analyze
FROM pg_stat_user_tables
WHERE tablename IN ('cliente', 'producto', 'pedido', 'detalle_pedido');
```

## 8. Limpieza (Rollback Manual)

Si se necesita revertir la carga después del COMMIT:

```sql
-- PRECAUCIÓN: Esto eliminará TODOS los datos, no solo los generados
BEGIN;

DELETE FROM detalle_pedido;
DELETE FROM pedido;
DELETE FROM producto;
DELETE FROM cliente;

-- Resetear secuencias
ALTER SEQUENCE cliente_id_cliente_seq RESTART WITH 1;
ALTER SEQUENCE producto_id_producto_seq RESTART WITH 1;
ALTER SEQUENCE pedido_id_pedido_seq RESTART WITH 1;

COMMIT;
```

**Mejor opción**: Restaurar desde backup usando `psql`.
