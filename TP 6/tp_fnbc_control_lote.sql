-- ============================================================================
--  TRABAJO PRÁCTICO - UNIDAD 4
--  Parte 1: Forma Normal de Boyce-Codd (FNBC) sobre ControlLoteAlmacen
--  Proyecto: Food Store (extensión mayorista: depósitos y control de lotes)
--  Motor: PostgreSQL 17
--
--  Contenido
--    0. Tablas maestras mínimas (para que el script sea autónomo)
--    1. Esquema original del enunciado + instancia de ejemplo
--    2. Dependencias funcionales y claves candidatas (verificación SQL)
--    3. Anomalías habilitadas por la violación de FNBC
--    4. Descomposición sin pérdida (algoritmo) + DDL de las tablas resultantes
--    5. Migración de datos, vista de compatibilidad y verificación
--
--  El script es idempotente: puede reejecutarse sobre la misma base.
--  En la base Food Store real las tablas maestras lote / deposito / usuario ya
--  existen; acá se crean en versión mínima sólo para que el TP se pueda
--  reproducir de forma autónoma en una base limpia.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 0. TABLAS MAESTRAS MÍNIMAS (referenciadas por el esquema del enunciado)
-- ----------------------------------------------------------------------------
DROP VIEW  IF EXISTS control_lote_almacen_v;
DROP TABLE IF EXISTS control_lote_almacen      CASCADE;
DROP TABLE IF EXISTS control_lote_almacen_orig CASCADE;
DROP TABLE IF EXISTS control_lote_responsable  CASCADE;
DROP TABLE IF EXISTS responsable_deposito      CASCADE;
DROP TABLE IF EXISTS lote                      CASCADE;
DROP TABLE IF EXISTS deposito                  CASCADE;
DROP TABLE IF EXISTS usuario                   CASCADE;

CREATE TABLE lote (
    id        BIGINT PRIMARY KEY,
    codigo    VARCHAR(30) NOT NULL UNIQUE,
    descripcion VARCHAR(200)
);

CREATE TABLE deposito (
    id        BIGINT PRIMARY KEY,
    nombre    VARCHAR(100) NOT NULL,
    direccion VARCHAR(200)
);

CREATE TABLE usuario (
    id        BIGINT PRIMARY KEY,
    nombre    VARCHAR(150) NOT NULL,
    rol       VARCHAR(50)  NOT NULL DEFAULT 'CONTROL_CALIDAD'
);

INSERT INTO deposito (id, nombre, direccion) VALUES
    (30, 'Depósito Central',   'Av. Industrial 1200'),
    (31, 'Depósito Norte',     'Ruta 9 Km 12'),
    (32, 'Depósito Sur',       'Calle 40 N° 850');

INSERT INTO lote (id, codigo, descripcion) VALUES
    (501, 'L-2026-0501', 'Lote de lácteos'),
    (502, 'L-2026-0502', 'Lote de bebidas'),
    (503, 'L-2026-0503', 'Lote de congelados');

INSERT INTO usuario (id, nombre, rol) VALUES
    (801, 'María Gómez',  'CONTROL_CALIDAD'),
    (802, 'Julián Pérez', 'CONTROL_CALIDAD'),
    (803, 'Lucía Sosa',   'CONTROL_CALIDAD');

-- ----------------------------------------------------------------------------
-- 1. ESQUEMA ORIGINAL DEL ENUNCIADO + INSTANCIA DE EJEMPLO
--    Regla de negocio relevada en logística:
--      - Para un (lote, depósito) dado, el responsable de control es único.
--      - Cada responsable pertenece a un único depósito.
-- ----------------------------------------------------------------------------
CREATE TABLE control_lote_almacen (
    lote_id                BIGINT NOT NULL REFERENCES lote(id),
    deposito_id            BIGINT NOT NULL REFERENCES deposito(id),
    responsable_control_id BIGINT NOT NULL REFERENCES usuario(id),
    PRIMARY KEY (lote_id, deposito_id)
);

INSERT INTO control_lote_almacen VALUES
    (501, 30, 801),
    (502, 30, 801),
    (503, 31, 802);

-- Copia de seguridad de la instancia original: se usa al final para verificar
-- que la descomposición reconstruye exactamente la misma relación.
CREATE TABLE control_lote_almacen_orig AS
SELECT lote_id, deposito_id, responsable_control_id
FROM control_lote_almacen;

-- ----------------------------------------------------------------------------
-- 2. DEPENDENCIAS FUNCIONALES Y CLAVES CANDIDATAS
-- ----------------------------------------------------------------------------
-- Con L = LoteID, D = DepositoID, R = ResponsableControlID:
--
--   DF1 : (L, D) -> R        (un responsable por lote y depósito)
--   DF2 : R -> D             (un responsable pertenece a un solo depósito)
--
-- El conjunto F = { (L,D) -> R , R -> D } tiene dos claves candidatas:
--   * (L, D)   porque (L,D)+ = {L,D,R} y ni L+ ni D+ alcanzan todos los atributos
--   * (L, R)   porque (L,R)+ = {L,R,D} y ni L+ ni R+ alcanzan todos los atributos
-- Todos los atributos son primos; no hay atributos no primos.

-- 2.1 Verificación sobre la instancia de ejemplo: (L,D) es único
SELECT 'PK (lote, deposito) unica' AS verificacion,
       CASE WHEN COUNT(*) = 0 THEN 'OK' ELSE 'FALLA' END AS resultado
FROM (
    SELECT lote_id, deposito_id
    FROM control_lote_almacen
    GROUP BY lote_id, deposito_id
    HAVING COUNT(*) > 1
) duplicados;

-- 2.2 Verificación: (L,R) también es único (consecuencia de R -> D)
SELECT 'clave candidata (lote, responsable) unica' AS verificacion,
       CASE WHEN COUNT(*) = 0 THEN 'OK' ELSE 'FALLA' END AS resultado
FROM (
    SELECT lote_id, responsable_control_id
    FROM control_lote_almacen
    GROUP BY lote_id, responsable_control_id
    HAVING COUNT(*) > 1
) duplicados;

-- 2.3 Verificación: R no es clave (801 aparece en dos filas) y D tampoco lo es.
SELECT 'R no es superclave (801 se repite)' AS verificacion,
       CASE WHEN COUNT(*) > 1 THEN 'OK: R no es clave' ELSE 'FALLA' END AS resultado
FROM control_lote_almacen
WHERE responsable_control_id = 801;

SELECT 'D no es superclave (30 se repite)' AS verificacion,
       CASE WHEN COUNT(*) > 1 THEN 'OK: D no es clave' ELSE 'FALLA' END AS resultado
FROM control_lote_almacen
WHERE deposito_id = 30;

-- 2.4 Verificación: la instancia respeta R -> D
--     (ningún responsable asociado a más de un depósito)
SELECT 'instancia respeta R -> D' AS verificacion,
       CASE WHEN COUNT(*) = 0 THEN 'OK' ELSE 'FALLA' END AS resultado
FROM (
    SELECT responsable_control_id
    FROM control_lote_almacen
    GROUP BY responsable_control_id
    HAVING COUNT(DISTINCT deposito_id) > 1
) violaciones;

-- ----------------------------------------------------------------------------
-- 3. ANOMALÍAS QUE HABILITA LA VIOLACIÓN DE FNBC
--    Cada bloque se ejecuta dentro de una transacción que se revierte, de modo
--    que la instancia de ejemplo queda intacta.
-- ----------------------------------------------------------------------------

-- 3.1 ANOMALÍA DE INSERCIÓN
--     No existe lugar en el esquema para registrar un dato maestro del
--     responsable (a qué depósito pertenece) sin inventar un lote controlado.
BEGIN;
INSERT INTO lote (id, codigo, descripcion)
VALUES (504, 'L-2026-0504', 'Lote de nuevo ingreso');
-- El alta del dato maestro "el responsable 803 pertenece al depósito 32"
-- obliga a registrar, además, un control sobre un lote que todavía no controló:
INSERT INTO control_lote_almacen (lote_id, deposito_id, responsable_control_id)
VALUES (504, 32, 803);   -- hubo que inventar el control del lote 504
SELECT 'insercion: se invento el lote 504' AS anomalia,
       COUNT(*) AS filas_del_responsable_803
FROM control_lote_almacen
WHERE responsable_control_id = 803;
ROLLBACK;

-- 3.2 ANOMALÍA DE ACTUALIZACIÓN
--     Si el responsable 801 pasa al depósito 31 hay que actualizar TODAS las
--     filas donde aparece. Actualizar una sola deja a 801 en dos depósitos y
--     rompe la regla R -> D sin que el motor lo impida.
BEGIN;
UPDATE control_lote_almacen
   SET deposito_id = 31
 WHERE lote_id = 501 AND deposito_id = 30;

SELECT 'actualizacion parcial: 801 quedo en N depositos' AS anomalia,
       COUNT(DISTINCT deposito_id) AS depositos,
       STRING_AGG(DISTINCT deposito_id::text, ', ' ORDER BY deposito_id::text) AS cuales
FROM control_lote_almacen
WHERE responsable_control_id = 801;
ROLLBACK;

-- 3.3 ANOMALÍA DE BORRADO
--     Al dar de baja el control del lote 503 en el depósito 31 desaparece el
--     único registro que afirmaba que el responsable 802 pertenece al depósito
--     31: se pierde un dato maestro por borrar un hecho transitorio.
BEGIN;
DELETE FROM control_lote_almacen
 WHERE lote_id = 503 AND deposito_id = 31;

SELECT 'borrado: filas que afirman que 802 pertenece al deposito 31' AS anomalia,
       COUNT(*) AS filas
FROM control_lote_almacen
WHERE responsable_control_id = 802;
ROLLBACK;

-- 3.4 La propia definición de FNBC, comprobada con el motor: el esquema acepta
--     una violación de R -> D (el determinante R no es superclave).
BEGIN;
INSERT INTO lote (id, codigo, descripcion)
VALUES (504, 'L-2026-0504', 'Lote de nuevo ingreso');
INSERT INTO control_lote_almacen (lote_id, deposito_id, responsable_control_id)
VALUES (504, 32, 801);   -- 801 ya pertenecía al depósito 30 según (501,30,801)
SELECT 'FNBC violada: 801 en dos depositos' AS comprobacion,
       COUNT(DISTINCT deposito_id) AS depositos
FROM control_lote_almacen
WHERE responsable_control_id = 801;
ROLLBACK;

-- ----------------------------------------------------------------------------
-- 4. DESCOMPOSICIÓN SIN PÉRDIDA
--    La DF violatoria es R -> D, con determinante R que no es superclave.
--    Algoritmo de descomposición:
--      R1 = R+ = {R, D}                 -> responsable_deposito
--      R2 = U - (R+ - R) = {L, R}       -> control_lote_responsable
--    El atributo común es R (responsable_control_id).
-- ----------------------------------------------------------------------------
CREATE TABLE responsable_deposito (
    responsable_control_id BIGINT PRIMARY KEY
        REFERENCES usuario(id),
    deposito_id            BIGINT NOT NULL
        REFERENCES deposito(id)
);

CREATE TABLE control_lote_responsable (
    lote_id                BIGINT NOT NULL
        REFERENCES lote(id),
    responsable_control_id BIGINT NOT NULL
        REFERENCES responsable_deposito(responsable_control_id),
    PRIMARY KEY (lote_id, responsable_control_id)
);

-- ----------------------------------------------------------------------------
-- 5. MIGRACIÓN Y VERIFICACIÓN
-- ----------------------------------------------------------------------------

-- 5.1 Migración de R1 = {R, D}: se proyecta y se eliminan duplicados, que es
--     precisamente la redundancia que el esquema original almacenaba.
INSERT INTO responsable_deposito (responsable_control_id, deposito_id)
SELECT DISTINCT responsable_control_id, deposito_id
FROM control_lote_almacen;

-- 5.2 Migración de R2 = {L, R}
INSERT INTO control_lote_responsable (lote_id, responsable_control_id)
SELECT lote_id, responsable_control_id
FROM control_lote_almacen;

-- 5.3 Vista de compatibilidad: reconstruye la relación original mediante una
--     reunión natural por el atributo común responsable_control_id.
CREATE VIEW control_lote_almacen_v AS
SELECT clr.lote_id,
       rd.deposito_id,
       rd.responsable_control_id
FROM control_lote_responsable clr
NATURAL JOIN responsable_deposito rd;

-- 5.4 Verificación de equivalencia: la diferencia simétrica entre la instancia
--     original y la reconstruida por la vista debe ser vacía.
WITH diferencias AS (
    (SELECT lote_id, deposito_id, responsable_control_id
       FROM control_lote_almacen_orig
     EXCEPT
     SELECT lote_id, deposito_id, responsable_control_id
       FROM control_lote_almacen_v)
    UNION ALL
    (SELECT lote_id, deposito_id, responsable_control_id
       FROM control_lote_almacen_v
     EXCEPT
     SELECT lote_id, deposito_id, responsable_control_id
       FROM control_lote_almacen_orig)
)
SELECT 'equivalencia vista vs. original' AS verificacion,
       CASE WHEN COUNT(*) = 0 THEN 'OK: 0 diferencias' ELSE 'FALLA' END AS resultado,
       COUNT(*) AS diferencias
FROM diferencias;

-- 5.5 Conteos: 3 filas en el original, 2 en R1 y 3 en R2.
SELECT 'control_lote_almacen_orig' AS objeto, COUNT(*) AS filas FROM control_lote_almacen_orig
UNION ALL
SELECT 'responsable_deposito',      COUNT(*) FROM responsable_deposito
UNION ALL
SELECT 'control_lote_responsable',  COUNT(*) FROM control_lote_responsable
UNION ALL
SELECT 'vista control_lote_almacen_v', COUNT(*) FROM control_lote_almacen_v;

-- 5.6 La vista reconstruye exactamente el ejemplo del enunciado.
SELECT lote_id, deposito_id, responsable_control_id
FROM control_lote_almacen_v
ORDER BY lote_id, deposito_id;

-- ----------------------------------------------------------------------------
-- 5.7 (Opcional) La DF (L,D) -> R no se preserva en ninguna de las dos tablas:
--     es el precio conocido de la descomposición en FNBC. Si se quiere seguir
--     garantizando la regla de negocio a nivel de motor, se agrega un trigger
--     de restricción. Se deja implementado y activo porque la regla es parte
--     del dominio, no del esquema original.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_control_unico_por_lote_deposito()
RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    v_deposito BIGINT;
    v_cantidad INT;
BEGIN
    SELECT deposito_id INTO v_deposito
    FROM responsable_deposito
    WHERE responsable_control_id = NEW.responsable_control_id;

    SELECT COUNT(*) INTO v_cantidad
    FROM control_lote_responsable clr
    JOIN responsable_deposito rd
      ON rd.responsable_control_id = clr.responsable_control_id
    WHERE clr.lote_id = NEW.lote_id
      AND rd.deposito_id = v_deposito;

    IF v_cantidad > 1 THEN
        RAISE EXCEPTION
            'El lote % ya tiene un responsable de control en el deposito %',
            NEW.lote_id, v_deposito;
    END IF;

    RETURN NEW;
END;
$$;

CREATE CONSTRAINT TRIGGER trg_control_unico_por_lote_deposito
AFTER INSERT OR UPDATE ON control_lote_responsable
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW
EXECUTE FUNCTION fn_control_unico_por_lote_deposito();

-- ----------------------------------------------------------------------------
-- RESPUESTAS RESUMIDAS
--
-- a) DF: (LoteID, DepositoID) -> ResponsableControlID
--        ResponsableControlID -> DepositoID
-- b) Claves candidatas: {LoteID, DepositoID} y {LoteID, ResponsableControlID}.
--    Primos: LoteID, DepositoID, ResponsableControlID. No primos: ninguno.
-- c) NO cumple FNBC: ResponsableControlID -> DepositoID es no trivial y su
--    determinante no es superclave ({R}+ = {R, D} != {L, D, R}). Sí cumple 3FN,
--    porque DepositoID es primo (por eso el caso es interesante).
-- d) Ver sección 3 (inserción / actualización / borrado).
-- e) Ver sección 4 y 5.1-5.3.
-- f) R1 ∩ R2 = {ResponsableControlID}; R -> D pertenece a F+, por lo tanto el
--    atributo común es superclave de R1 y la reunión es sin pérdida.
-- ----------------------------------------------------------------------------
