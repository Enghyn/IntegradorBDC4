-- Pruebas de reglas de negocio (Limpias y con datos unicos)

-- Prueba 1: Email invalido (debe fallar por el CHECK constraint)
BEGIN;
INSERT INTO cliente (nombre, email, telefono) VALUES ('Test Usuario 1', 'correo_invalido_sin_arroba', '12345678');
ROLLBACK;

-- Prueba 2: Email valido (debe pasar)
BEGIN;
INSERT INTO cliente (nombre, email, telefono) VALUES ('Test Usuario Valido', 'test_valido_' || gen_random_uuid() || '@example.com', '12345678');
COMMIT;

-- Prueba 3: Producto con categoria inactiva (debe fallar por el trigger de producto)
BEGIN;
INSERT INTO categoria (nombre, activo) VALUES ('Cat Inactiva ' || gen_random_uuid(), FALSE);
INSERT INTO producto (id_categoria, nombre, precio_lista, stock, activo) 
VALUES ((SELECT id_categoria FROM categoria WHERE nombre LIKE 'Cat Inactiva %' ORDER BY id_categoria DESC LIMIT 1), 'Prod Test 1', 100.00, 10, TRUE);
ROLLBACK;

-- Prueba 4: Producto con categoria activa (debe pasar)
BEGIN;
INSERT INTO categoria (nombre, activo) VALUES ('Cat Activa ' || gen_random_uuid(), TRUE);
INSERT INTO producto (id_categoria, nombre, precio_lista, stock, activo) 
VALUES ((SELECT id_categoria FROM categoria WHERE nombre LIKE 'Cat Activa %' ORDER BY id_categoria DESC LIMIT 1), 'Prod Valido 1', 100.00, 10, TRUE);
COMMIT;

-- Prueba 5: Intentar desactivar categoria con productos activos (Regla 3 - debe fallar)
BEGIN;
INSERT INTO categoria (nombre, activo) VALUES ('Cat Con Prod ' || gen_random_uuid(), TRUE);
INSERT INTO producto (id_categoria, nombre, precio_lista, stock, activo) 
VALUES ((SELECT id_categoria FROM categoria WHERE nombre LIKE 'Cat Con Prod %' ORDER BY id_categoria DESC LIMIT 1), 'Prod Asociado 1', 50.00, 5, TRUE);
-- Intentar desactivar la categoria (Debe fallar)
UPDATE categoria SET activo = FALSE WHERE nombre LIKE 'Cat Con Prod %';
ROLLBACK;

-- Prueba 6: Desactivar categoria SIN productos activos (Regla 3 - debe pasar)
BEGIN;
INSERT INTO categoria (nombre, activo) VALUES ('Cat Sin Prod ' || gen_random_uuid(), TRUE);
-- Desactivar la categoria sin productos (Debe pasar)
UPDATE categoria SET activo = FALSE WHERE nombre LIKE 'Cat Sin Prod %';
COMMIT;
