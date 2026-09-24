-- ----------------------------------------------------------------------------
-- 1. TIPOS ENUMERADOS (DOMINIOS CERRADOS)
-- ----------------------------------------------------------------------------
CREATE TYPE forma_pago_enum AS ENUM (
    'EFECTIVO',
    'TARJETA',
    'TRANSFERENCIA'
);

-- ----------------------------------------------------------------------------
-- 2. TABLA: CLIENTE
-- ----------------------------------------------------------------------------
CREATE TABLE cliente (
    id_cliente BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL,
    email VARCHAR(150) NOT NULL UNIQUE,
    telefono VARCHAR(30) NULL,
    activo BOOLEAN NOT NULL DEFAULT TRUE,
    fecha_creacion TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- ----------------------------------------------------------------------------
-- 3. TABLA: CATEGORIA
-- ----------------------------------------------------------------------------
CREATE TABLE categoria (
    id_categoria BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre VARCHAR(80) NOT NULL UNIQUE,
    activo BOOLEAN NOT NULL DEFAULT TRUE
);

-- ----------------------------------------------------------------------------
-- 4. TABLA: PRODUCTO
-- ----------------------------------------------------------------------------
CREATE TABLE producto (
    id_producto BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_categoria BIGINT NOT NULL,
    nombre VARCHAR(100) NOT NULL UNIQUE,
    precio_lista NUMERIC(10, 2) NOT NULL,
    stock INTEGER NOT NULL,
    activo BOOLEAN NOT NULL DEFAULT TRUE,
    
    -- Claves foráneas:
    CONSTRAINT fk_producto_categoria FOREIGN KEY (id_categoria)
        REFERENCES categoria (id_categoria)
        ON DELETE RESTRICT,

    -- Restricciones CHECK:
    CONSTRAINT chk_producto_precio_positivo CHECK (precio_lista >= 0),
    CONSTRAINT chk_producto_stock_no_negativo CHECK (stock >= 0)
);

-- ----------------------------------------------------------------------------
-- 5. TABLA: PEDIDO
-- ----------------------------------------------------------------------------
CREATE TABLE pedido (
    id_pedido BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_cliente BIGINT NOT NULL,
    fecha_pedido TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    forma_pago forma_pago_enum NOT NULL,

    -- Claves foráneas:
    CONSTRAINT fk_pedido_cliente FOREIGN KEY (id_cliente)
        REFERENCES cliente (id_cliente)
        ON DELETE RESTRICT
);

-- ----------------------------------------------------------------------------
-- 6. TABLA INTERMEDIA N:M: DETALLE_PEDIDO
-- ----------------------------------------------------------------------------
CREATE TABLE detalle_pedido (
    id_pedido BIGINT NOT NULL,
    id_producto BIGINT NOT NULL,
    cantidad INTEGER NOT NULL,
    precio_unitario_facturado NUMERIC(10, 2) NOT NULL,

    -- Clave Primaria Compuesta ({id_pedido, id_producto}):
    CONSTRAINT pk_detalle_pedido PRIMARY KEY (id_pedido, id_producto),

    -- Claves foráneas:
    CONSTRAINT fk_detalle_pedido_pedido FOREIGN KEY (id_pedido)
        REFERENCES pedido (id_pedido)
        ON DELETE RESTRICT,
        
    CONSTRAINT fk_detalle_pedido_producto FOREIGN KEY (id_producto)
        REFERENCES producto (id_producto)
        ON DELETE RESTRICT,

    -- Restricciones CHECK:
    CONSTRAINT chk_detalle_cantidad_positiva CHECK (cantidad > 0),
    CONSTRAINT chk_detalle_precio_facturado_positivo CHECK (precio_unitario_facturado >= 0)
);

-- ----------------------------------------------------------------------------
-- 7. ÍNDICES DE RENDIMIENTO
-- ----------------------------------------------------------------------------

-- Acelera la búsqueda e historial de pedidos de un cliente
CREATE INDEX idx_pedido_cliente ON pedido(id_cliente);

-- Acelera el listado de productos activos de una categoría (Índice parcial nativo de PostgreSQL)
CREATE INDEX idx_producto_categoria_activo ON producto(id_categoria) WHERE activo = TRUE;