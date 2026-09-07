# Requirements: Carga Masiva de Datos para Testing

## 1. Introducción

Este documento especifica los requisitos para implementar un sistema de carga masiva de datos en la base de datos FoodStore, con el propósito de generar volúmenes realistas que permitan medir el impacto de optimizaciones de consultas y rendimiento.

## 2. Objetivos

- Generar datos de prueba a escala significativa (50k+ productos, 20k+ clientes, 200k+ pedidos)
- Garantizar que los datos generados cumplan todas las restricciones de integridad del esquema
- Ejecutar la carga de forma segura, transaccional y verificable
- Actualizar estadísticas del optimizador para reflejar el nuevo volumen de datos

## 3. Alcance

### Incluido
- Script SQL de generación de datos masivos usando `generate_series`
- Procedimiento de validación del script antes de ejecución
- Protocolo de respaldo y restauración
- Ejecución transaccional con rollback en caso de error
- Comando ANALYZE post-carga

### Excluido
- Modificación del esquema existente
- Carga de datos en ambiente de producción
- Generación de datos históricos (fechas anteriores a la ejecución)

## 4. Requisitos Funcionales

### RF-01: Generación de Clientes
**Prioridad**: Alta

**Descripción**: Generar al menos 20,000 registros de clientes con datos realistas.

**Criterios de Aceptación**:
- Generar exactamente 20,000 clientes
- Cada cliente debe tener:
  - `nombre`: Formato "Cliente N" donde N es un número secuencial
  - `email`: Único, formato "cliente_N@foodstore.test"
  - `telefono`: Aleatorio en formato "+54911XXXXXXXX" (50% de clientes con teléfono, 50% NULL)
  - `activo`: 95% TRUE, 5% FALSE (distribución realista)
  - `fecha_creacion`: Distribuida en los últimos 365 días
- No debe violar la restricción UNIQUE en `email`
- Debe respetar el tipo de dato de cada columna

### RF-02: Generación de Productos
**Prioridad**: Alta

**Descripción**: Generar al menos 50,000 productos distribuidos equitativamente entre las categorías existentes.

**Criterios de Aceptación**:
- Generar exactamente 50,000 productos
- Distribución: cantidad de productos por categoría debe ser pareja (±2%)
- Cada producto debe tener:
  - `nombre`: Único, formato "Producto [Categoría] N"
  - `precio_lista`: Aleatorio entre 500.00 y 5000.00 (2 decimales)
  - `stock`: Aleatorio entre 0 y 200
  - `activo`: 90% TRUE, 10% FALSE
  - `id_categoria`: FK válida a una categoría existente
- Debe cumplir CHECK `precio_lista >= 0`
- Debe cumplir CHECK `stock >= 0`
- No debe violar UNIQUE en `nombre`

### RF-03: Generación de Pedidos
**Prioridad**: Alta

**Descripción**: Generar al menos 200,000 pedidos asociados a clientes existentes.

**Criterios de Aceptación**:
- Generar exactamente 200,000 pedidos
- Cada pedido debe tener:
  - `id_cliente`: FK válida a un cliente existente (distribución: algunos clientes con muchos pedidos, otros con pocos)
  - `fecha_pedido`: Distribuida en los últimos 180 días
  - `forma_pago`: Distribución realista:
    - TARJETA: 60%
    - TRANSFERENCIA: 30%
    - EFECTIVO: 10%
- Debe respetar FK constraint con `cliente`

### RF-04: Generación de Detalles de Pedido
**Prioridad**: Alta

**Descripción**: Generar líneas de detalle para cada pedido, con 2 a 5 productos por pedido.

**Criterios de Aceptación**:
- Cada pedido debe tener entre 2 y 5 productos (aleatorio)
- Total estimado de detalles: 400,000 - 1,000,000 registros
- Cada detalle debe tener:
  - `id_pedido`: FK válida al pedido
  - `id_producto`: FK válida a un producto existente
  - `cantidad`: Aleatoria entre 1 y 10
  - `precio_unitario_facturado`: Igual al `precio_lista` del producto al momento de la carga
- No debe haber productos duplicados en el mismo pedido (PK compuesta)
- Debe cumplir CHECK `cantidad > 0`
- Debe cumplir CHECK `precio_unitario_facturado >= 0`

## 5. Requisitos No Funcionales

### RNF-01: Seguridad - Validación Previa
**Prioridad**: Crítica

**Descripción**: El script debe ser revisado línea por línea antes de su ejecución.

**Criterios de Aceptación**:
- Verificar que no contiene comandos DDL (ALTER, DROP, TRUNCATE) excepto sobre tablas temporales
- Verificar que solo realiza INSERT en las tablas permitidas: cliente, producto, pedido, detalle_pedido
- Verificar que no contiene UPDATE ni DELETE
- Verificar que respeta todas las restricciones CHECK, UNIQUE, FK
- Verificar que no referencia bases de datos de producción (nombre debe contener "test", "dev" o "local")

### RNF-02: Seguridad - Protocolo de Respaldo
**Prioridad**: Crítica

**Descripción**: Debe existir un backup antes de ejecutar el script.

**Criterios de Aceptación**:
- Crear backup con `pg_dump` antes de la ejecución
- Nombre del backup: `foodstore_backup_YYYYMMDD_HHMMSS.sql`
- Ubicación: `db/backups/`
- Verificar que el archivo de backup fue creado exitosamente (tamaño > 0)
- Documentar el comando de restauración en caso de error

### RNF-03: Atomicidad - Ejecución Transaccional
**Prioridad**: Crítica

**Descripción**: Todo el script debe ejecutarse dentro de una transacción explícita.

**Criterios de Aceptación**:
- El script debe comenzar con `BEGIN;`
- El script debe terminar con `COMMIT;`
- En caso de error, debe ejecutarse `ROLLBACK;` automáticamente
- No debe haber commits intermedios (todo o nada)
- Logs deben indicar si la transacción fue committed o rolled back

### RNF-04: Performance - Tiempo de Ejecución
**Prioridad**: Media

**Descripción**: El script debe ejecutarse en un tiempo razonable.

**Criterios de Aceptación**:
- Tiempo total de ejecución: < 5 minutos en hardware moderno
- Usar `generate_series` en lugar de loops explícitos
- Evitar PL/pgSQL si no es estrictamente necesario
- Inserción en lotes (batch inserts) cuando sea posible

### RNF-05: Mantenibilidad - Actualización de Estadísticas
**Prioridad**: Alta

**Descripción**: Después de la carga, actualizar estadísticas del optimizador.

**Criterios de Aceptación**:
- Ejecutar `ANALYZE` sobre las tablas: cliente, producto, pedido, detalle_pedido
- Debe ejecutarse después del COMMIT exitoso
- Logs deben confirmar que ANALYZE fue ejecutado
- Verificar que `pg_stat_user_tables` refleja el nuevo número de filas

## 6. Restricciones Técnicas

### RT-01: Tecnología
- PostgreSQL 14+
- SQL estándar, evitar extensiones propietarias cuando sea posible
- Encoding UTF-8

### RT-02: Ambiente
- Base de datos: copia local o de desarrollo, NUNCA producción
- Permisos: usuario con permisos de INSERT, no requiere permisos DDL
- Conexión: local o red interna, no remota sin VPN

### RT-03: Categorías Preexistentes
- El script asume que la tabla `categoria` ya tiene al menos 5 categorías cargadas
- Si no existen categorías, debe fallar con error descriptivo
- No debe crear ni modificar categorías

## 7. Casos de Uso

### CU-01: Ejecución Exitosa Completa
1. Operador valida el script manualmente
2. Operador crea backup de la base de datos
3. Operador ejecuta el script en transacción
4. Script inserta 20k clientes, 50k productos, 200k pedidos, ~600k detalles
5. Script hace COMMIT
6. Operador ejecuta ANALYZE
7. Sistema actualiza estadísticas

### CU-02: Detección de Error - Rollback
1. Operador ejecuta el script
2. Script encuentra violación de UNIQUE en producto (nombre duplicado)
3. PostgreSQL lanza excepción
4. Transacción hace ROLLBACK automático
5. Base de datos vuelve al estado anterior (sin cambios)
6. Operador revisa logs de error y corrige el script

### CU-03: Restauración desde Backup
1. Script se ejecutó pero los datos no son los esperados
2. Operador decide restaurar el backup
3. Operador ejecuta: `psql -U usuario -d foodstore_test < db/backups/foodstore_backup_YYYYMMDD_HHMMSS.sql`
4. Base de datos vuelve al estado previo a la carga

## 8. Dependencias

- Tabla `categoria` debe tener al menos 5 registros
- PostgreSQL debe tener suficiente espacio en disco (estimado: 500MB - 1GB adicional)
- Usuario de base de datos debe tener privilegios: INSERT, SELECT en las tablas objetivo

## 9. Supuestos

- Los IDs generados automáticamente (IDENTITY) no se reutilizan
- No hay carga concurrente durante la ejecución del script
- El hardware tiene al menos 4GB RAM disponible para PostgreSQL
- No existen triggers que interfieran con las inserciones

## 10. Criterios de Aceptación Global

- [ ] Script genera exactamente 20,000 clientes
- [ ] Script genera exactamente 50,000 productos
- [ ] Script genera exactamente 200,000 pedidos
- [ ] Script genera entre 400,000 y 1,000,000 detalles
- [ ] Todas las restricciones FK, CHECK, UNIQUE son respetadas
- [ ] Ejecución completa en menos de 5 minutos
- [ ] Backup creado antes de ejecución
- [ ] Transacción con BEGIN/COMMIT exitoso
- [ ] ANALYZE ejecutado sobre las 4 tablas
- [ ] Sin errores en logs de PostgreSQL
