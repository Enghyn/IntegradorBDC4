-- ============================================================================
--  TRABAJO PRÁCTICO - UNIDAD 4
--  Parte 2: Desnormalización controlada
--  Reporte: top 5 de categorías por monto vendido en el día
--  Proyecto: Food Store
--  Motor: PostgreSQL 17
--
--  Contenido
--    1. Esquema base Food Store (categoría, producto, pedido, detalle_pedido)
--    2. Población de una instancia representativa (~250.000 pedidos)
--    3. Medición inicial con EXPLAIN ANALYZE (consulta del panel)
--    4. Experimento: ¿alcanza con indexar las claves foráneas?
--    5. Estructura desnormalizada + mecanismo de sincronización (triggers)
--    6. Carga inicial del resumen
--    7. Consulta del panel leyendo la estructura desnormalizada
--    8. Auditoría de sincronización (debe devolver 0 filas)
--    9. Demostración de que los triggers mantienen el resumen y de que la
--       auditoría detecta una desincronización provocada
--
--  IMPORTANTE
--    Este script está pensado para ejecutarse sobre una COPIA / RÉPLICA de la
--    base Food Store (o sobre una base vacía), no sobre producción: la sección
--    1 elimina y recrea las tablas del dominio.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. ESQUEMA BASE FOOD STORE (réplica)
-- ----------------------------------------------------------------------------
DROP VIEW  IF EXISTS v_auditoria_resumen CASCADE;
DROP TABLE IF EXISTS resumen_venta_categoria_dia CASCADE;
DROP TABLE IF EXISTS detalle_pedido CASCADE;
DROP TABLE IF EXISTS pedido CASCADE;
DROP TABLE IF EXISTS producto CASCADE;
DROP TABLE IF EXISTS categoria CASCADE;

CREATE TABLE categoria (
    id        BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre    VARCHAR(120) NOT NULL UNIQUE,
    eliminado BOOLEAN NOT NULL DEFAULT FALSE
);

CREATE TABLE producto (
    id           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    categoria_id BIGINT NOT NULL REFERENCES categoria(id),
    nombre       VARCHAR(150) NOT NULL,
    precio       NUMERIC(12,2) NOT NULL CHECK (precio >= 0),
    eliminado    BOOLEAN NOT NULL DEFAULT FALSE
);

CREATE TABLE pedido (
    id        BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    fecha     DATE NOT NULL DEFAULT CURRENT_DATE,
    estado    VARCHAR(20) NOT NULL DEFAULT 'CONFIRMADO',
    eliminado BOOLEAN NOT NULL DEFAULT FALSE
    -- Nota: el total del pedido se omite a propósito. Es un dato derivado de
    -- detalle_pedido y agregarlo sin control sería una redundancia no gestionada.
);

CREATE TABLE detalle_pedido (
    id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    pedido_id       BIGINT NOT NULL REFERENCES pedido(id) ON DELETE CASCADE,
    producto_id     BIGINT NOT NULL REFERENCES producto(id),
    cantidad        INT NOT NULL CHECK (cantidad > 0),
    precio_unitario NUMERIC(12,2) NOT NULL CHECK (precio_unitario >= 0),
    subtotal        NUMERIC(12,2) GENERATED ALWAYS AS (cantidad * precio_unitario) STORED,
    eliminado       BOOLEAN NOT NULL DEFAULT FALSE
);

-- Índices propios del esquema base (los que existirían en la réplica).
CREATE INDEX ix_pedido_fecha ON pedido (fecha);

-- ----------------------------------------------------------------------------
-- 2. POBLACIÓN
--    ~250.000 pedidos distribuidos en 730 días (~342 por día) y 5 líneas por
--    pedido (1.250.000 líneas de detalle).
-- ----------------------------------------------------------------------------
SELECT setseed(0.42);

INSERT INTO categoria (nombre) VALUES
    ('Almacén'), ('Bebidas'), ('Carnes'), ('Congelados'), ('Fiambres'),
    ('Frutas y Verduras'), ('Lácteos'), ('Panadería'), ('Perfumería'),
    ('Limpieza'), ('Mascotas'), ('Snacks');

INSERT INTO producto (categoria_id, nombre, precio)
SELECT 1 + (g % 12),
       'Producto ' || g,
       ROUND((10 + random() * 990)::numeric, 2)
FROM generate_series(1, 800) g;

INSERT INTO pedido (fecha, eliminado)
SELECT CURRENT_DATE - floor(random() * 730)::int,
       random() < 0.02
FROM generate_series(1, 250000);

-- 5 líneas por pedido. El producto, la cantidad y la marca de eliminado se
-- derivan de un hash determinista del pedido y del número de línea: así la
-- instancia es reproducible y la distribución entre categorías es uniforme
-- (usar random() dentro del ON de un JOIN lo evalúa una sola vez).
INSERT INTO detalle_pedido (pedido_id, producto_id, cantidad, precio_unitario, eliminado)
SELECT p.id,
       pr.id,
       1 + (abs(hashtext('cant:' || p.id)::bigint) % 4),
       pr.precio,
       (abs(hashtext('elim:' || p.id || ':' || g)::bigint) % 100) = 0
FROM pedido p
CROSS JOIN generate_series(1, 5) g
JOIN producto pr
  ON pr.id = 1 + (abs(hashtext('prod:' || p.id || ':' || g)::bigint) % 800);

ANALYZE categoria;
ANALYZE producto;
ANALYZE pedido;
ANALYZE detalle_pedido;

SELECT 'filas base' AS objeto,
       (SELECT COUNT(*) FROM pedido)          AS pedidos,
       (SELECT COUNT(*) FROM detalle_pedido)  AS detalles,
       (SELECT COUNT(*) FROM pedido WHERE fecha = CURRENT_DATE) AS pedidos_hoy,
       (SELECT COUNT(*) FROM detalle_pedido dp
          JOIN pedido p ON p.id = dp.pedido_id
         WHERE p.fecha = CURRENT_DATE)       AS detalles_hoy;

-- ----------------------------------------------------------------------------
-- 3. MEDICIÓN INICIAL (ANTES)
--    Consulta del panel tal como está en el enunciado.
-- ----------------------------------------------------------------------------
EXPLAIN (ANALYZE, BUFFERS)
SELECT c.nombre AS categoria,
       SUM(dp.subtotal) AS total_vendido
FROM detalle_pedido dp
JOIN producto pr  ON pr.id = dp.producto_id
JOIN categoria c  ON c.id = pr.categoria_id
JOIN pedido ped   ON ped.id = dp.pedido_id
WHERE ped.fecha = CURRENT_DATE
  AND dp.eliminado = FALSE
  AND ped.eliminado = FALSE
GROUP BY c.nombre
ORDER BY total_vendido DESC
LIMIT 5;

-- ----------------------------------------------------------------------------
-- 4. EXPERIMENTO: ¿ALCANZA CON INDEXAR LAS CLAVES FORÁNEAS?
--    Se agrega el índice sobre detalle_pedido(pedido_id) (que PostgreSQL no
--    crea automáticamente) y se vuelve a medir. El resultado queda en el
--    informe como "antes optimizado": es la línea base más exigente contra la
--    cual se compara la desnormalización.
-- ----------------------------------------------------------------------------
CREATE INDEX ix_detalle_pedido_pedido ON detalle_pedido (pedido_id);
ANALYZE detalle_pedido;

EXPLAIN (ANALYZE, BUFFERS)
SELECT c.nombre AS categoria,
       SUM(dp.subtotal) AS total_vendido
FROM detalle_pedido dp
JOIN producto pr  ON pr.id = dp.producto_id
JOIN categoria c  ON c.id = pr.categoria_id
JOIN pedido ped   ON ped.id = dp.pedido_id
WHERE ped.fecha = CURRENT_DATE
  AND dp.eliminado = FALSE
  AND ped.eliminado = FALSE
GROUP BY c.nombre
ORDER BY total_vendido DESC
LIMIT 5;

-- ----------------------------------------------------------------------------
-- 5. ESTRUCTURA DESNORMALIZADA + SINCRONIZACIÓN
--
--    Patrón elegido: tabla de agregación incremental mantenida por disparadores
--    (equivalente a una "columna precalculada", pero agregada al grano del
--    reporte: fecha x categoría).
--
--    Clave del diseño: el resumen NO guarda el nombre de la categoría, guarda
--    categoria_id. Así, un cambio de nombre no requiere sincronizar nada y el
--    reporte sigue haciendo un JOIN de 12 filas contra categoria.
-- ----------------------------------------------------------------------------
CREATE TABLE resumen_venta_categoria_dia (
    fecha          DATE   NOT NULL,
    categoria_id   BIGINT NOT NULL REFERENCES categoria(id),
    total_vendido  NUMERIC(14,2) NOT NULL DEFAULT 0,
    cantidad_items BIGINT NOT NULL DEFAULT 0,
    actualizado_en TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (fecha, categoria_id)
);

-- 5.1 Aplicación de un delta atómico sobre una fila del resumen
CREATE OR REPLACE FUNCTION fs_resumen_aplicar(
    p_fecha        DATE,
    p_categoria_id BIGINT,
    p_delta_total  NUMERIC,
    p_delta_items  BIGINT
) RETURNS void
LANGUAGE sql AS $$
    INSERT INTO resumen_venta_categoria_dia AS r
        (fecha, categoria_id, total_vendido, cantidad_items, actualizado_en)
    VALUES (p_fecha, p_categoria_id, p_delta_total, p_delta_items, now())
    ON CONFLICT (fecha, categoria_id) DO UPDATE
       SET total_vendido  = r.total_vendido  + EXCLUDED.total_vendido,
           cantidad_items = r.cantidad_items + EXCLUDED.cantidad_items,
           actualizado_en = now();
$$;

-- 5.2 Trigger sobre detalle_pedido: altas, bajas y modificaciones de líneas
CREATE OR REPLACE FUNCTION fs_trg_detalle_resumen()
RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    v_fecha_old   DATE;
    v_elim_old    BOOLEAN;
    v_cat_old     BIGINT;
    v_fecha_new   DATE;
    v_elim_new    BOOLEAN;
    v_cat_new     BIGINT;
    v_items_old   BIGINT := 0;
    v_total_old   NUMERIC := 0;
    v_items_new   BIGINT := 0;
    v_total_new   NUMERIC := 0;
BEGIN
    -- Estado anterior: sólo aporta si la línea y el pedido no estaban eliminados.
    IF TG_OP IN ('UPDATE', 'DELETE') THEN
        SELECT p.fecha, p.eliminado, pr.categoria_id
          INTO v_fecha_old, v_elim_old, v_cat_old
          FROM pedido p
          JOIN producto pr ON pr.id = OLD.producto_id
         WHERE p.id = OLD.pedido_id;

        -- Si el pedido ya no existe (borrado en cascada), el ajuste lo hizo el
        -- trigger BEFORE DELETE de pedido; acá no hay nada que restar.
        IF v_fecha_old IS NOT NULL
           AND NOT v_elim_old
           AND NOT OLD.eliminado THEN
            v_total_old := -OLD.subtotal;
            v_items_old := -OLD.cantidad;
        END IF;

        IF v_items_old <> 0 THEN
            PERFORM fs_resumen_aplicar(v_fecha_old, v_cat_old, v_total_old, v_items_old);
        END IF;
    END IF;

    -- Estado nuevo: sólo aporta si la línea y el pedido no están eliminados.
    IF TG_OP IN ('INSERT', 'UPDATE') THEN
        SELECT p.fecha, p.eliminado, pr.categoria_id
          INTO v_fecha_new, v_elim_new, v_cat_new
          FROM pedido p
          JOIN producto pr ON pr.id = NEW.producto_id
         WHERE p.id = NEW.pedido_id;

        IF v_fecha_new IS NOT NULL
           AND NOT v_elim_new
           AND NOT NEW.eliminado THEN
            v_total_new := NEW.subtotal;
            v_items_new := NEW.cantidad;
        END IF;

        IF v_items_new <> 0 THEN
            PERFORM fs_resumen_aplicar(v_fecha_new, v_cat_new, v_total_new, v_items_new);
        END IF;
    END IF;

    RETURN NULL;
END;
$$;

CREATE TRIGGER trg_detalle_resumen
AFTER INSERT OR UPDATE OR DELETE ON detalle_pedido
FOR EACH ROW EXECUTE FUNCTION fs_trg_detalle_resumen();

-- 5.3 Trigger sobre pedido: cambios de fecha o de la marca de eliminado
CREATE OR REPLACE FUNCTION fs_trg_pedido_resumen()
RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF OLD.fecha IS NOT DISTINCT FROM NEW.fecha
       AND OLD.eliminado IS NOT DISTINCT FROM NEW.eliminado THEN
        RETURN NULL;
    END IF;

    -- Se retira el aporte del pedido en su estado anterior
    IF NOT OLD.eliminado THEN
        INSERT INTO resumen_venta_categoria_dia AS r
            (fecha, categoria_id, total_vendido, cantidad_items, actualizado_en)
        SELECT OLD.fecha,
               pr.categoria_id,
               -SUM(dp.subtotal),
               -SUM(dp.cantidad),
               now()
          FROM detalle_pedido dp
          JOIN producto pr ON pr.id = dp.producto_id
         WHERE dp.pedido_id = OLD.id
           AND NOT dp.eliminado
         GROUP BY pr.categoria_id
        ON CONFLICT (fecha, categoria_id) DO UPDATE
           SET total_vendido  = r.total_vendido  + EXCLUDED.total_vendido,
               cantidad_items = r.cantidad_items + EXCLUDED.cantidad_items,
               actualizado_en = now();
    END IF;

    -- Se agrega el aporte del pedido en su estado nuevo
    IF NOT NEW.eliminado THEN
        INSERT INTO resumen_venta_categoria_dia AS r
            (fecha, categoria_id, total_vendido, cantidad_items, actualizado_en)
        SELECT NEW.fecha,
               pr.categoria_id,
               SUM(dp.subtotal),
               SUM(dp.cantidad),
               now()
          FROM detalle_pedido dp
          JOIN producto pr ON pr.id = dp.producto_id
         WHERE dp.pedido_id = NEW.id
           AND NOT dp.eliminado
         GROUP BY pr.categoria_id
        ON CONFLICT (fecha, categoria_id) DO UPDATE
           SET total_vendido  = r.total_vendido  + EXCLUDED.total_vendido,
               cantidad_items = r.cantidad_items + EXCLUDED.cantidad_items,
               actualizado_en = now();
    END IF;

    RETURN NULL;
END;
$$;

CREATE TRIGGER trg_pedido_resumen
AFTER UPDATE OF fecha, eliminado ON pedido
FOR EACH ROW EXECUTE FUNCTION fs_trg_pedido_resumen();

-- 5.4 Trigger sobre pedido: borrado físico (la cascada de detalle_pedido no
--     puede resolver la fecha porque el pedido ya no existe cuando corre)
CREATE OR REPLACE FUNCTION fs_trg_pedido_borrado()
RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF NOT OLD.eliminado THEN
        INSERT INTO resumen_venta_categoria_dia AS r
            (fecha, categoria_id, total_vendido, cantidad_items, actualizado_en)
        SELECT OLD.fecha,
               pr.categoria_id,
               -SUM(dp.subtotal),
               -SUM(dp.cantidad),
               now()
          FROM detalle_pedido dp
          JOIN producto pr ON pr.id = dp.producto_id
         WHERE dp.pedido_id = OLD.id
           AND NOT dp.eliminado
         GROUP BY pr.categoria_id
        ON CONFLICT (fecha, categoria_id) DO UPDATE
           SET total_vendido  = r.total_vendido  + EXCLUDED.total_vendido,
               cantidad_items = r.cantidad_items + EXCLUDED.cantidad_items,
               actualizado_en = now();
    END IF;

    RETURN OLD;
END;
$$;

CREATE TRIGGER trg_pedido_borrado
BEFORE DELETE ON pedido
FOR EACH ROW EXECUTE FUNCTION fs_trg_pedido_borrado();

-- 5.5 Trigger sobre producto: recategorización de un producto
--     Mueve el histórico del producto de una categoría a otra, por fecha.
CREATE OR REPLACE FUNCTION fs_trg_producto_categoria()
RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF OLD.categoria_id IS DISTINCT FROM NEW.categoria_id THEN
        INSERT INTO resumen_venta_categoria_dia AS r
            (fecha, categoria_id, total_vendido, cantidad_items, actualizado_en)
        SELECT p.fecha, OLD.categoria_id, -SUM(dp.subtotal), -SUM(dp.cantidad), now()
          FROM detalle_pedido dp
          JOIN pedido p ON p.id = dp.pedido_id
         WHERE dp.producto_id = NEW.id
           AND NOT dp.eliminado
           AND NOT p.eliminado
         GROUP BY p.fecha
        ON CONFLICT (fecha, categoria_id) DO UPDATE
           SET total_vendido  = r.total_vendido  + EXCLUDED.total_vendido,
               cantidad_items = r.cantidad_items + EXCLUDED.cantidad_items,
               actualizado_en = now();

        INSERT INTO resumen_venta_categoria_dia AS r
            (fecha, categoria_id, total_vendido, cantidad_items, actualizado_en)
        SELECT p.fecha, NEW.categoria_id, SUM(dp.subtotal), SUM(dp.cantidad), now()
          FROM detalle_pedido dp
          JOIN pedido p ON p.id = dp.pedido_id
         WHERE dp.producto_id = NEW.id
           AND NOT dp.eliminado
           AND NOT p.eliminado
         GROUP BY p.fecha
        ON CONFLICT (fecha, categoria_id) DO UPDATE
           SET total_vendido  = r.total_vendido  + EXCLUDED.total_vendido,
               cantidad_items = r.cantidad_items + EXCLUDED.cantidad_items,
               actualizado_en = now();
    END IF;

    RETURN NULL;
END;
$$;

CREATE TRIGGER trg_producto_categoria
AFTER UPDATE OF categoria_id ON producto
FOR EACH ROW EXECUTE FUNCTION fs_trg_producto_categoria();

-- ----------------------------------------------------------------------------
-- 6. CARGA INICIAL DEL RESUMEN
--    Reconstrucción completa desde la fuente de verdad. Se usa también como
--    mecanismo de reconciliación ante una carga masiva (COPY/TRUNCATE no
--    disparan triggers de fila).
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fs_resumen_reconstruir()
RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
    TRUNCATE resumen_venta_categoria_dia;

    INSERT INTO resumen_venta_categoria_dia
        (fecha, categoria_id, total_vendido, cantidad_items)
    SELECT p.fecha,
           pr.categoria_id,
           SUM(dp.subtotal),
           SUM(dp.cantidad)
      FROM detalle_pedido dp
      JOIN producto pr ON pr.id = dp.producto_id
      JOIN pedido p    ON p.id  = dp.pedido_id
     WHERE NOT dp.eliminado
       AND NOT p.eliminado
     GROUP BY p.fecha, pr.categoria_id;
END;
$$;

SELECT fs_resumen_reconstruir();

ANALYZE resumen_venta_categoria_dia;

SELECT 'filas resumen' AS objeto,
       COUNT(*) AS filas,
       MIN(fecha) AS desde,
       MAX(fecha) AS hasta
FROM resumen_venta_categoria_dia;

-- ----------------------------------------------------------------------------
-- 6.1 RECONSTRUCCIÓN POR LOTES: PROCEDIMIENTO INVOCADO CON CALL
--     fs_resumen_reconstruir() es una FUNCIÓN: se evalúa dentro de la
--     transacción del llamador y no puede confirmar por sí misma. Para el
--     mantenimiento del histórico conviene un PROCEDIMIENTO, que no devuelve
--     valor, se invoca con CALL y puede confirmar entre lotes: si la carga
--     falla a mitad de camino no se pierde lo ya reconstruido.
--
--     p_commit = false (predeterminado) lo mantiene seguro dentro de una
--     transacción explícita o de un script ejecutado con psql -1. Con true,
--     cada lote se confirma y por eso el CALL debe ejecutarse FUERA de un
--     bloque BEGIN: PostgreSQL rechaza un COMMIT dentro de una transacción
--     ajena con "invalid transaction termination".
-- ----------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE fs_reconstruir_resumen(
    p_desde     date,
    p_hasta     date,
    p_commit    boolean DEFAULT false,
    p_lote_dias integer DEFAULT 90
)
LANGUAGE plpgsql AS $$
DECLARE
    v_desde date := p_desde;
    v_fin   date;
BEGIN
    IF p_desde IS NULL OR p_hasta IS NULL THEN
        RAISE EXCEPTION 'fs_reconstruir_resumen: p_desde y p_hasta son obligatorios';
    END IF;
    IF p_desde > p_hasta THEN
        RAISE EXCEPTION 'fs_reconstruir_resumen: rango invertido (% > %)', p_desde, p_hasta;
    END IF;
    IF p_lote_dias IS NULL OR p_lote_dias < 1 THEN
        RAISE EXCEPTION 'fs_reconstruir_resumen: p_lote_dias debe ser >= 1';
    END IF;

    WHILE v_desde <= p_hasta LOOP
        v_fin := LEAST(v_desde + (p_lote_dias - 1), p_hasta);

        DELETE FROM resumen_venta_categoria_dia
         WHERE fecha BETWEEN v_desde AND v_fin;

        INSERT INTO resumen_venta_categoria_dia
            (fecha, categoria_id, total_vendido, cantidad_items)
        SELECT p.fecha,
               pr.categoria_id,
               SUM(dp.subtotal),
               SUM(dp.cantidad)
          FROM detalle_pedido dp
          JOIN producto pr ON pr.id = dp.producto_id
          JOIN pedido p    ON p.id  = dp.pedido_id
         WHERE p.fecha BETWEEN v_desde AND v_fin
           AND NOT dp.eliminado
           AND NOT p.eliminado
         GROUP BY p.fecha, pr.categoria_id;

        RAISE NOTICE 'fs_reconstruir_resumen: rango % .. % reconstruido', v_desde, v_fin;

        IF p_commit THEN
            COMMIT;
        END IF;

        v_desde := v_fin + 1;
    END LOOP;
END;
$$;

-- Uso sobre el histórico completo, confirmando cada lote de 90 días. Debe
-- ejecutarse fuera de un bloque de transacción (ver nota anterior):
--   CALL fs_reconstruir_resumen(DATE '2024-10-29', CURRENT_DATE, true, 90);

-- ----------------------------------------------------------------------------
-- 7. CONSULTA DEL PANEL SOBRE LA ESTRUCTURA DESNORMALIZADA (DESPUÉS)
--    Ya no recorre detalle_pedido / producto / pedido: lee el agregado del día
--    (una fila por categoría) y sólo une con categoria para obtener el nombre.
-- ----------------------------------------------------------------------------
EXPLAIN (ANALYZE, BUFFERS)
SELECT c.nombre AS categoria,
       r.total_vendido
FROM resumen_venta_categoria_dia r
JOIN categoria c ON c.id = r.categoria_id
WHERE r.fecha = CURRENT_DATE
ORDER BY r.total_vendido DESC
LIMIT 5;

-- Resultado funcional (debe coincidir con la consulta original)
SELECT c.nombre AS categoria,
       r.total_vendido
FROM resumen_venta_categoria_dia r
JOIN categoria c ON c.id = r.categoria_id
WHERE r.fecha = CURRENT_DATE
ORDER BY r.total_vendido DESC
LIMIT 5;

-- ----------------------------------------------------------------------------
-- 8. AUDITORÍA DE SINCRONIZACIÓN
--    Recalcula desde la fuente de verdad y compara con el resumen. El
--    resultado debe ser vacío (0 filas).
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_auditoria_resumen AS
WITH esperado AS (
    SELECT p.fecha,
           pr.categoria_id,
           SUM(dp.subtotal) AS total_vendido,
           SUM(dp.cantidad) AS cantidad_items
      FROM detalle_pedido dp
      JOIN producto pr ON pr.id = dp.producto_id
      JOIN pedido p    ON p.id  = dp.pedido_id
     WHERE NOT dp.eliminado
       AND NOT p.eliminado
     GROUP BY p.fecha, pr.categoria_id
)
SELECT COALESCE(e.fecha, r.fecha)               AS fecha,
       COALESCE(e.categoria_id, r.categoria_id) AS categoria_id,
       COALESCE(e.total_vendido, 0)             AS total_esperado,
       COALESCE(r.total_vendido, 0)             AS total_resumen,
       COALESCE(e.total_vendido, 0) - COALESCE(r.total_vendido, 0) AS diferencia,
       COALESCE(e.cantidad_items, 0)            AS items_esperados,
       COALESCE(r.cantidad_items, 0)            AS items_resumen
  FROM esperado e
  FULL OUTER JOIN resumen_venta_categoria_dia r
    ON r.fecha = e.fecha
   AND r.categoria_id = e.categoria_id
 WHERE COALESCE(e.total_vendido, 0) <> COALESCE(r.total_vendido, 0)
    OR COALESCE(e.cantidad_items, 0) <> COALESCE(r.cantidad_items, 0);

-- Ejecución de la auditoría: debe devolver 0 filas.
SELECT * FROM v_auditoria_resumen;

-- ----------------------------------------------------------------------------
-- 9. PRUEBAS DEL MECANISMO DE SINCRONIZACIÓN
--    Todo se ejecuta en transacciones que se revierten.
-- ----------------------------------------------------------------------------

-- 9.1 Una venta nueva actualiza el resumen del día sin recalcular el histórico
BEGIN;
WITH nuevo_pedido AS (
    INSERT INTO pedido (fecha) VALUES (CURRENT_DATE) RETURNING id
), linea AS (
    INSERT INTO detalle_pedido (pedido_id, producto_id, cantidad, precio_unitario)
    SELECT id, (SELECT id FROM producto WHERE categoria_id = 1 ORDER BY id LIMIT 1), 10, 100.00
    FROM nuevo_pedido
    RETURNING 1
)
SELECT 'tras alta de linea' AS paso,
       total_vendido AS categoria_almacen_hoy,
       cantidad_items
FROM resumen_venta_categoria_dia
WHERE fecha = CURRENT_DATE
  AND categoria_id = 1;
SELECT 'auditoria tras alta' AS paso, COUNT(*) AS diferencias FROM v_auditoria_resumen;
ROLLBACK;

-- 9.2 El borrado lógico de un pedido descuenta su aporte
BEGIN;
UPDATE pedido
   SET eliminado = TRUE
 WHERE id = (SELECT id FROM pedido
              WHERE fecha = CURRENT_DATE AND NOT eliminado
              ORDER BY id LIMIT 1);
SELECT 'auditoria tras borrado logico' AS paso, COUNT(*) AS diferencias FROM v_auditoria_resumen;
ROLLBACK;

-- 9.3 La recategorización de un producto mueve su histórico
BEGIN;
UPDATE producto
   SET categoria_id = 2
 WHERE id = (SELECT id FROM producto WHERE categoria_id = 1 ORDER BY id LIMIT 1);
SELECT 'auditoria tras recategorizacion' AS paso, COUNT(*) AS diferencias FROM v_auditoria_resumen;
ROLLBACK;

-- 9.4 La auditoría NO es vacua: si se corrompe el resumen a mano, lo detecta
BEGIN;
UPDATE resumen_venta_categoria_dia
   SET total_vendido = total_vendido + 1
 WHERE fecha = CURRENT_DATE
   AND categoria_id = 1;
SELECT 'auditoria con desincronizacion provocada' AS paso,
       COUNT(*) AS diferencias_detectadas
FROM v_auditoria_resumen;
ROLLBACK;

-- 9.5 El procedimiento de reconstrucción por lotes repara una desincronización
--     (se llama con p_commit = false para poder revertir la prueba)
BEGIN;
UPDATE resumen_venta_categoria_dia
   SET total_vendido = 0
 WHERE fecha = CURRENT_DATE;

SELECT 'antes del CALL' AS paso,
       COUNT(*) AS diferencias
FROM v_auditoria_resumen;

CALL fs_reconstruir_resumen(CURRENT_DATE, CURRENT_DATE, false, 1);

SELECT 'despues del CALL' AS paso,
       COUNT(*) AS diferencias
FROM v_auditoria_resumen;

SELECT 'filas del dia tras el CALL' AS paso,
       COUNT(*) AS filas
FROM resumen_venta_categoria_dia
WHERE fecha = CURRENT_DATE;

ROLLBACK;

-- ----------------------------------------------------------------------------
-- RESPUESTAS RESUMIDAS
--
-- a) La consulta original se midió con EXPLAIN (ANALYZE, BUFFERS) sobre
--    ~250.000 pedidos / 1.250.000 líneas de detalle. El nodo dominante es el
--    recorrido/secuenciado de detalle_pedido unido por hash (ver capturas en
--    resultados/explain_antes.txt).
-- b) Patrón: tabla de agregación incremental fecha x categoría mantenida por
--    triggers. Justificación en el informe (sección 2.2).
-- c) Ver sección 5: cuatro disparadores y una función de apoyo en el camino
--    caliente, más el procedimiento fs_reconstruir_resumen, invocado con CALL,
--    para el mantenimiento por lotes del histórico.
-- d) Ver sección 7 y la tabla antes/después del informe.
-- e) Ver sección 8 (v_auditoria_resumen).
-- ----------------------------------------------------------------------------
