# Manejo de Errores: Carga Masiva de Datos

## 1. Filosofía de Manejo de Errores

El sistema sigue el principio **"Fail Fast, Fail Safe"**:
- Detectar errores lo antes posible
- Hacer rollback automático ante cualquier fallo
- Proveer mensajes de error descriptivos
- Mantener la integridad de la base de datos en todo momento

## 2. Tipos de Errores y Estrategias

### 2.1. Errores de Validación Previa (Antes de Ejecución)

#### Error: Script contiene comandos prohibidos
**Detección**: Script de validación (bash/PowerShell)
```bash
grep -iE "(DROP|TRUNCATE|ALTER)" script.sql
```
**Acción**:
- NO ejecutar el script
- Reportar líneas problemáticas al operador
- Solicitar corrección manual

**Mensaje**:
```
ERROR: Se encontraron comandos prohibidos en línea 45:
  DROP TABLE cliente;
Estos comandos no están permitidos en scripts de carga masiva.
```

#### Error: Base de datos de producción detectada
**Detección**: Verificar nombre de base de datos
```sql
SELECT current_database();
-- Si NO contiene 'test', 'dev', 'local' → ERROR
```
**Acción**:
- ABORTAR inmediatamente
- No permitir conexión a producción

**Mensaje**:
```
FATAL: Intento de ejecución sobre base de datos de producción detectado.
Base de datos actual: foodstore_prod
Este script solo puede ejecutarse sobre: foodstore_test, foodstore_dev, foodstore_local
```

#### Error: Backup fallido
**Detección**: Código de salida de `pg_dump != 0` o archivo vacío
```bash
if [ ! -s "$BACKUP_FILE" ]; then
    echo "ERROR: Backup falló o está vacío"
    exit 1
fi
```
**Acción**:
- NO proceder con la carga
- Verificar permisos, espacio en disco, conexión a BD

**Mensaje**:
```
ERROR: No se pudo crear el backup de la base de datos.
Verifica:
- Espacio en disco disponible en db/backups/
- Permisos de escritura
- Conexión a PostgreSQL
- Usuario tiene privilegios SELECT
```

### 2.2. Errores en Tiempo de Ejecución (Durante BEGIN...COMMIT)

#### Error: Categorías insuficientes
**Detección**: Validación con bloque `DO` al inicio del script
```sql
DO $$
DECLARE
    v_cat_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_cat_count FROM categoria WHERE activo = TRUE;
    IF v_cat_count < 5 THEN
        RAISE EXCEPTION 'Se requieren al menos 5 categorías activas. Encontradas: %', v_cat_count;
    END IF;
END $$;
```
**Acción**:
- Lanzar excepción
- PostgreSQL hace ROLLBACK automático
- Base de datos queda sin cambios

**Mensaje**:
```
EXCEPTION: Se requieren al menos 5 categorías activas. Encontradas: 2
HINT: Inserta más categorías antes de ejecutar este script.
```

#### Error: Violación de UNIQUE constraint (email duplicado)
**Contexto**: Raro, porque usamos formato único `cliente_N@...`
**Detección**: PostgreSQL lanza error automáticamente
```
ERROR:  duplicate key value violates unique constraint "cliente_email_key"
DETAIL:  Key (email)=(cliente_1234@foodstore.test) already exists.
```
**Acción**:
- PostgreSQL hace ROLLBACK automático
- Revisar si la tabla ya tenía datos
- Ajustar el rango de `generate_series` para evitar colisión

**Solución**:
```sql
-- Usar un offset basado en el máximo actual
WITH max_id AS (
    SELECT COALESCE(MAX(id_cliente), 0) AS ultimo_id FROM cliente
)
INSERT INTO cliente (nombre, email, ...)
SELECT 
    'Cliente ' || (mi.ultimo_id + gs.n),
    'cliente_' || (mi.ultimo_id + gs.n) || '@foodstore.test',
    ...
FROM generate_series(1, 20000) AS gs(n)
CROSS JOIN max_id mi;
```

#### Error: Violación de CHECK constraint (precio negativo)
**Contexto**: Bug en la generación aleatoria de precios
```
ERROR:  new row for relation "producto" violates check constraint "chk_producto_precio_positivo"
DETAIL:  Failing row contains (id=1234, precio_lista=-100.50, ...).
```
**Acción**:
- ROLLBACK automático
- Revisar fórmula de `random()` para precios
- Asegurar que `500 + (random() * 4500)` siempre es >= 0

**Prevención**:
```sql
-- Asegurar valores no negativos
GREATEST(0, 500 + (random() * 4500)::NUMERIC(10,2))
```

#### Error: Violación de FK constraint
**Ejemplo**: Producto referencia categoría inexistente
```
ERROR:  insert or update on table "producto" violates foreign key constraint "fk_producto_categoria"
DETAIL:  Key (id_categoria)=(999) is not present in table "categoria".
```
**Acción**:
- ROLLBACK automático
- Revisar CTE `categorias_activas` para asegurar que solo usa IDs existentes

**Prevención**:
```sql
-- Siempre hacer JOIN con la tabla padre, nunca IDs hardcodeados
INSERT INTO producto (id_categoria, ...)
SELECT ca.id_categoria, ...
FROM generate_series(...) gs
CROSS JOIN categoria ca  -- JOIN garantiza FK válida
WHERE ca.activo = TRUE;
```

#### Error: Out of Memory (OOM)
**Contexto**: Script intenta generar demasiadas filas en memoria
```
ERROR:  out of memory
DETAIL:  Failed on request of size 1048576.
```
**Acción**:
- ROLLBACK automático
- Reducir el número de filas generadas
- Dividir en lotes (múltiples INSERT)

**Solución**:
```sql
-- Opción 1: Reducir escala
-- generate_series(1, 50000) → generate_series(1, 25000)

-- Opción 2: Dividir en lotes
INSERT INTO producto (...) SELECT ... FROM generate_series(1, 10000) ...;
INSERT INTO producto (...) SELECT ... FROM generate_series(10001, 20000) ...;
-- ... etc
```

#### Error: Deadlock (poco probable en carga masiva sin concurrencia)
```
ERROR:  deadlock detected
DETAIL:  Process 1234 waits for ShareLock on transaction 5678.
```
**Acción**:
- PostgreSQL hace ROLLBACK de una transacción automáticamente
- Reintentar la carga asegurando que no hay otras sesiones activas

**Prevención**:
- Ejecutar en horario de baja actividad
- Verificar que no hay otras transacciones abiertas: `SELECT * FROM pg_stat_activity WHERE datname = 'foodstore_test';`

### 2.3. Errores Post-Commit (Después de COMMIT exitoso)

#### Error: ANALYZE falla
**Contexto**: Carga exitosa pero ANALYZE no se ejecutó
```
ERROR:  permission denied for table producto
```
**Acción**:
- La carga está completa (datos insertados)
- Ejecutar ANALYZE manualmente con usuario con permisos adecuados

**Solución**:
```bash
psql -U postgres -d foodstore_test -c "ANALYZE cliente, producto, pedido, detalle_pedido;"
```

#### Error: Datos incorrectos después de la carga
**Contexto**: Carga exitosa pero distribución no es la esperada
**Detección**: Consultas de verificación
```sql
-- Verificar distribución por categoría
SELECT c.nombre, COUNT(p.id_producto) AS productos
FROM categoria c
LEFT JOIN producto p ON c.id_categoria = p.id_categoria
GROUP BY c.nombre;

-- Si una categoría tiene 0 productos → problema
```
**Acción**:
- Restaurar desde backup
- Corregir lógica de distribución en el script
- Volver a ejecutar

**Restauración**:
```bash
psql -U postgres -d foodstore_test < db/backups/foodstore_backup_20260827_120000.sql
```

## 3. Implementación de Try-Catch en PostgreSQL

Para errores específicos, usar bloques `DO` con `EXCEPTION`:

```sql
DO $$
DECLARE
    v_errores INTEGER := 0;
BEGIN
    -- Intentar inserción
    INSERT INTO cliente (nombre, email, ...)
    SELECT ...
    FROM generate_series(1, 20000) gs;
    
    RAISE NOTICE 'Clientes insertados exitosamente';
    
EXCEPTION
    WHEN unique_violation THEN
        v_errores := 1;
        RAISE EXCEPTION 'Error: Email duplicado detectado. Detalles: %', SQLERRM;
        
    WHEN foreign_key_violation THEN
        v_errores := 1;
        RAISE EXCEPTION 'Error: Violación de clave foránea. Detalles: %', SQLERRM;
        
    WHEN check_violation THEN
        v_errores := 1;
        RAISE EXCEPTION 'Error: Violación de restricción CHECK. Detalles: %', SQLERRM;
        
    WHEN OTHERS THEN
        v_errores := 1;
        RAISE EXCEPTION 'Error inesperado: % - %', SQLSTATE, SQLERRM;
END $$;
```

## 4. Logging y Trazabilidad

### 4.1. Activar Logging Detallado

Antes de ejecutar el script:
```sql
SET client_min_messages = NOTICE;
\timing on
```

### 4.2. Mensajes de Progreso

Insertar `RAISE NOTICE` en puntos clave:
```sql
RAISE NOTICE '[%] Iniciando carga de clientes...', clock_timestamp();
-- INSERT clientes
RAISE NOTICE '[%] Clientes cargados: %', clock_timestamp(), (SELECT COUNT(*) FROM cliente);

RAISE NOTICE '[%] Iniciando carga de productos...', clock_timestamp();
-- INSERT productos
RAISE NOTICE '[%] Productos cargados: %', clock_timestamp(), (SELECT COUNT(*) FROM producto);
```

### 4.3. Log File

Redirigir salida a archivo:
```bash
psql -U postgres -d foodstore_test -f db/seeds/load_massive_data.sql > logs/load_$(date +%Y%m%d_%H%M%S).log 2>&1
```

Analizar log después de la ejecución:
```bash
grep -i "error\|exception\|warning" logs/load_20260827_120000.log
```

## 5. Checklist de Ejecución Segura

### Pre-ejecución
- [ ] Base de datos es de test/dev/local (NO producción)
- [ ] Script validado línea por línea (sin comandos prohibidos)
- [ ] Backup creado exitosamente y verificado (tamaño > 0)
- [ ] No hay otras sesiones activas en la base de datos
- [ ] Usuario tiene permisos: SELECT, INSERT en tablas objetivo
- [ ] Espacio en disco suficiente (al menos 2GB libres)

### Durante ejecución
- [ ] Monitorear salida de NOTICE para ver progreso
- [ ] Verificar que no aparecen mensajes de ERROR
- [ ] Si aparece error, confirmar que se hizo ROLLBACK
- [ ] Esperar hasta ver "COMMIT" en la salida

### Post-ejecución
- [ ] Verificar mensaje "COMMIT" (no "ROLLBACK")
- [ ] Ejecutar ANALYZE sobre las 4 tablas
- [ ] Correr consultas de verificación (conteos, distribución)
- [ ] Revisar `pg_stat_user_tables` para confirmar estadísticas actualizadas
- [ ] Guardar log de ejecución para auditoría

### En caso de fallo
- [ ] Verificar que la base está en estado previo (ROLLBACK funcionó)
- [ ] Revisar log de error detallado
- [ ] Identificar causa raíz
- [ ] Corregir script
- [ ] Restaurar desde backup si es necesario
- [ ] Reintentar

## 6. Escenarios de Recuperación

### Escenario 1: Fallo durante la carga de clientes
**Estado**: 0 clientes, 0 productos, 0 pedidos
**Acción**: ROLLBACK automático, base de datos sin cambios
**Recuperación**: Corregir script y reintentar

### Escenario 2: Fallo durante la carga de productos
**Estado**: Transacción abortada
**Acción**: ROLLBACK automático, incluso los clientes se revierten
**Recuperación**: Corregir script y reintentar

### Escenario 3: Fallo durante la carga de detalles
**Estado**: Transacción abortada
**Acción**: ROLLBACK automático, todo se revierte
**Recuperación**: Corregir script y reintentar

### Escenario 4: COMMIT exitoso pero datos incorrectos
**Estado**: Datos insertados pero distribución errónea
**Acción**: Restaurar desde backup
```bash
psql -U postgres -d foodstore_test < db/backups/foodstore_backup_YYYYMMDD_HHMMSS.sql
```
**Recuperación**: Corregir lógica del script y reintentar

### Escenario 5: PostgreSQL crasheó durante la carga
**Estado**: Indeterminado
**Acción**: PostgreSQL hace ROLLBACK automático al reiniciar (WAL recovery)
**Verificación**:
```sql
SELECT COUNT(*) FROM cliente;
SELECT COUNT(*) FROM producto;
-- Si los conteos son los mismos que antes → ROLLBACK exitoso
```

## 7. Matriz de Errores Comunes

| Error Code | Descripción | Causa Común | Solución |
|------------|-------------|-------------|----------|
| 23505 | unique_violation | Email duplicado | Usar offset basado en MAX(id) |
| 23503 | foreign_key_violation | FK a categoría inexistente | Verificar JOIN con tabla padre |
| 23514 | check_violation | Precio o stock negativo | Validar fórmulas de random() |
| 53200 | out_of_memory | Script muy grande | Dividir en lotes |
| 08P01 | protocol_violation | Conexión interrumpida | Verificar red, reintentar |
| 42P01 | undefined_table | Tabla no existe | Verificar esquema, crear tablas |
| 42501 | insufficient_privilege | Sin permisos INSERT | Otorgar permisos al usuario |

## 8. Contacto y Escalamiento

En caso de errores no resueltos con este documento:
1. Revisar logs de PostgreSQL: `/var/log/postgresql/postgresql-XX-main.log`
2. Consultar documentación oficial de PostgreSQL sobre el código de error específico
3. Verificar versión de PostgreSQL: `SELECT version();`
4. Consultar con DBA o instructor de la cátedra
