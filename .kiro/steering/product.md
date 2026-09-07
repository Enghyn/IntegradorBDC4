---
inclusion: always
---
# Descripción del Proyecto FoodStore DB

## Objetivo
Sistema de base de datos PostgreSQL para una tienda de alimentos, diseñado para evaluar optimizaciones de rendimiento con volúmenes realistas de datos.

## Modelo de Datos

### Cliente
- `id_cliente` BIGINT (PK, IDENTITY)
- `nombre` VARCHAR(100) NOT NULL
- `email` VARCHAR(150) NOT NULL UNIQUE
- `telefono` VARCHAR(30)
- `activo` BOOLEAN DEFAULT TRUE
- `fecha_creacion` TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP

### Categoría
- `id_categoria` BIGINT (PK, IDENTITY)
- `nombre` VARCHAR(80) NOT NULL UNIQUE
- `activo` BOOLEAN DEFAULT TRUE

### Producto
- `id_producto` BIGINT (PK, IDENTITY)
- `id_categoria` BIGINT NOT NULL (FK → categoria)
- `nombre` VARCHAR(100) NOT NULL UNIQUE
- `precio_lista` NUMERIC(10,2) NOT NULL
- `stock` INTEGER NOT NULL
- `activo` BOOLEAN DEFAULT TRUE
- **Restricciones**: precio_lista >= 0, stock >= 0

### Pedido
- `id_pedido` BIGINT (PK, IDENTITY)
- `id_cliente` BIGINT NOT NULL (FK → cliente)
- `fecha_pedido` TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
- `forma_pago` forma_pago_enum NOT NULL

### Detalle Pedido
- `id_pedido` BIGINT (PK compuesta, FK → pedido)
- `id_producto` BIGINT (PK compuesta, FK → producto)
- `cantidad` INTEGER NOT NULL
- `precio_unitario_facturado` NUMERIC(10,2) NOT NULL
- **Restricciones**: cantidad > 0, precio_unitario_facturado >= 0

## Tipos Enumerados
- `forma_pago_enum`: EFECTIVO, TARJETA, TRANSFERENCIA

## Índices Existentes
1. `idx_pedido_cliente` ON pedido(id_cliente)
2. `idx_producto_categoria_activo` ON producto(id_categoria) WHERE activo = TRUE

## Escala de Datos para Testing
- Productos: ≥ 50,000
- Clientes: ≥ 20,000
- Pedidos: ≥ 200,000
- Detalles: ~400k-1M (2-5 productos/pedido)
