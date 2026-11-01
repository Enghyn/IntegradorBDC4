-- ============================================================================
-- 00_RECONSTRUCCION_PARTE0.SQL
-- TP — Unidad 5: Administración y seguridad de Food Store
-- PARTE 0 — Reconstrucción de los artefactos de Clase 1 y Clase 2
--
-- POR QUÉ EXISTE ESTE ARCHIVO
--   El TP asume que el equipo conserva de la Clase 1 el esquema de roles y de la
--   Clase 2 las funciones fn_autenticar / fn_resetear_password. En este
--   repositorio esos artefactos NO están (verificado: no aparecen en ningún .sql
--   del proyecto). El enunciado habilita reconstruirlos como paso previo a la
--   Parte A; esta reconstrucción queda registrada en BITACORA.md.
--
-- QUÉ CREA
--   1. Guarda de entorno (norma dura de AGENTS.md: sólo test/dev/local)
--   2. Extensión pgcrypto (bcrypt)
--   3. rol                  -> catálogo de roles de aplicación
--   4. usuario              -> identidad de aplicación. CONTIENE PII:
--                              email, nombre, apellido, telefono, fecha_alta
--   5. login_intento        -> traza de cada intento de autenticación
--   6. usuario_auditoria    -> traza de acciones administrativas (append-only)
--   7. vw_intentos_login_sospechosos -> detección de fuerza bruta
--   8. fn_autenticar / fn_resetear_password (SECURITY DEFINER, search_path fijo)
--   9. Datos sintéticos de arranque (deterministas, sin datos reales)
--
-- REQUISITOS
--   PostgreSQL 16+ ; rol con privilegios de DDL + capacidad de CREATE EXTENSION.
--   Ejecutar con psql (usa la variable :seed_password, ver más abajo).
--
-- IDEMPOTENTE: se puede re-ejecutar sin duplicar objetos ni filas.
--
-- USO
--   psql -U postgres -d foodstore_test -f TP7/sql/00_reconstruccion_parte0.sql
--   # con contraseña propia para los usuarios sintéticos:
--   psql -U postgres -d foodstore_test -v seed_password='MiClaveSintetica#2026' \
--        -f TP7/sql/00_reconstruccion_parte0.sql
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. GUARDA DE ENTORNO
--    Aborta si la base no parece de desarrollo. Override auditable (queda en el
--    historial de la sesión):  SET tp7.entorno_confirmado = 'si';
-- ----------------------------------------------------------------------------
DO $guard$
BEGIN
    IF current_database() !~* '(test|dev|local)'
       AND coalesce(current_setting('tp7.entorno_confirmado', true), '') <> 'si' THEN
        RAISE EXCEPTION
            'La base "%" no parece de desarrollo (debe contener test, dev o local). '
            'Si el equipo confirma que es una copia de trabajo, ejecutar antes: '
            'SET tp7.entorno_confirmado = ''si'';',
            current_database();
    END IF;
END
$guard$;

-- ----------------------------------------------------------------------------
-- 2. EXTENSIONES
--    pgcrypto aporta crypt() / gen_salt() para bcrypt.
-- ----------------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ----------------------------------------------------------------------------
-- 3. TABLA: ROL
--    Catálogo de roles de aplicación. "nombre" debe coincidir exactamente con el
--    nombre del rol de PostgreSQL que crea roles.sql: así la fila de usuario y el
--    privilegio efectivo del motor hablan el mismo idioma.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS rol (
    id_rol       SMALLINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre       VARCHAR(60)  NOT NULL,
    descripcion  VARCHAR(300) NOT NULL,
    activo       BOOLEAN      NOT NULL DEFAULT TRUE,

    CONSTRAINT uq_rol_nombre UNIQUE (nombre),
    CONSTRAINT chk_rol_nombre_formato CHECK (nombre ~ '^[a-z][a-z0-9_]{2,59}$'),
    CONSTRAINT chk_rol_descripcion_no_vacia CHECK (btrim(descripcion) <> '')
);

COMMENT ON TABLE  rol IS 'Catálogo de roles de aplicación de Food Store (Parte 0 del TP Unidad 5).';
COMMENT ON COLUMN rol.nombre IS 'Debe coincidir con el nombre del rol de PostgreSQL creado en roles.sql.';

-- ----------------------------------------------------------------------------
-- 4. TABLA: USUARIO  (identidad de aplicación — CONTIENE PII)
--    email, nombre, apellido, telefono y fecha_alta son datos personales: son
--    justamente los que la Parte D anonimiza en usuario_anon y los que la Parte C
--    nunca debe enviar a un asistente de IA sin anonimizar.
--
--    password_hash NUNCA se guarda en texto plano: el CHECK valida el formato
--    bcrypt ($2a$, $2b$ o $2y$ + costo + 53 caracteres).
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS usuario (
    id_usuario    BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    email         VARCHAR(150) NOT NULL,        -- PII
    nombre        VARCHAR(80)  NOT NULL,        -- PII
    apellido      VARCHAR(80)  NOT NULL,        -- PII
    telefono      VARCHAR(30)  NULL,            -- PII
    password_hash TEXT         NOT NULL,
    id_rol        SMALLINT     NOT NULL,
    fecha_alta    TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,  -- PII
    activo        BOOLEAN      NOT NULL DEFAULT TRUE,
    ultimo_acceso TIMESTAMPTZ  NULL,
    id_cliente    BIGINT       NULL,            -- vínculo opcional con el cliente comercial

    CONSTRAINT uq_usuario_email UNIQUE (email),

    CONSTRAINT fk_usuario_rol FOREIGN KEY (id_rol)
        REFERENCES rol (id_rol)
        ON DELETE RESTRICT,

    CONSTRAINT fk_usuario_cliente FOREIGN KEY (id_cliente)
        REFERENCES cliente (id_cliente)
        ON DELETE SET NULL,

    CONSTRAINT chk_usuario_email_formato
        CHECK (email ~ '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$'),

    CONSTRAINT chk_usuario_hash_bcrypt
        CHECK (password_hash ~ '^\$2[aby]\$[0-9]{2}\$.{53}$'),

    CONSTRAINT chk_usuario_nombres_no_vacios
        CHECK (btrim(nombre) <> '' AND btrim(apellido) <> '')
);

COMMENT ON TABLE  usuario IS 'Identidad de aplicación de Food Store. Contiene PII: no exponer sin anonimizar.';
COMMENT ON COLUMN usuario.password_hash IS 'Hash bcrypt generado con pgcrypto; el CHECK impide texto plano.';

CREATE INDEX IF NOT EXISTS idx_usuario_rol          ON usuario (id_rol);
CREATE INDEX IF NOT EXISTS idx_usuario_fecha_alta   ON usuario (fecha_alta);
CREATE INDEX IF NOT EXISTS idx_usuario_activo       ON usuario (activo) WHERE activo = TRUE;

-- ----------------------------------------------------------------------------
-- 5. TABLA: LOGIN_INTENTO
--    Traza consultable desde SQL de cada llamada a fn_autenticar.
--    Complementa (no reemplaza) el log del servidor de la Parte B.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS login_intento (
    id_intento      BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    email_intentado VARCHAR(150) NOT NULL,      -- PII: se anonimiza en la Parte C
    exito           BOOLEAN      NOT NULL,
    motivo          VARCHAR(40)  NOT NULL,
    origen          INET         NULL,
    ocurrido_en     TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT chk_login_motivo CHECK (motivo IN (
        'ok',
        'credenciales_invalidas',
        'parametros_invalidos'
    ))
);

COMMENT ON TABLE login_intento IS
    'Traza de intentos de autenticación. Append-only para los roles de aplicación.';

CREATE INDEX IF NOT EXISTS idx_login_intento_email_fecha
    ON login_intento (email_intentado, ocurrido_en DESC);

CREATE INDEX IF NOT EXISTS idx_login_intento_fallidos
    ON login_intento (ocurrido_en DESC) WHERE exito = FALSE;

-- ----------------------------------------------------------------------------
-- 6. TABLA: USUARIO_AUDITORIA
--    Rastro de acciones administrativas sensibles (reseteo de contraseña, etc.).
--    Append-only: los roles de aplicación no tienen UPDATE ni DELETE.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS usuario_auditoria (
    id_evento   BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_usuario  BIGINT       NULL,
    accion      VARCHAR(40)  NOT NULL,
    actor       VARCHAR(150) NOT NULL,          -- identidad del motor que ejecutó
    resultado   VARCHAR(12)  NOT NULL DEFAULT 'OK',
    ocurrido_en TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    detalle     JSONB        NULL,

    CONSTRAINT fk_usuario_auditoria_usuario FOREIGN KEY (id_usuario)
        REFERENCES usuario (id_usuario)
        ON DELETE SET NULL,

    CONSTRAINT chk_usuario_auditoria_resultado
        CHECK (resultado IN ('OK', 'RECHAZADO'))
);

COMMENT ON TABLE usuario_auditoria IS
    'Traza de acciones administrativas sobre identidades. Append-only.';

CREATE INDEX IF NOT EXISTS idx_usuario_auditoria_usuario
    ON usuario_auditoria (id_usuario, ocurrido_en DESC);

-- ----------------------------------------------------------------------------
-- 7. VISTA: VW_INTENTOS_LOGIN_SOSPECHOSOS
--    Detección (no bloqueo): cuentas con 3 o más fallos en los últimos 15 min.
--    Decisión de diseño D5: el bloqueo automático requiere un umbral acordado con
--    negocio y queda fuera del alcance de esta entrega.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_intentos_login_sospechosos AS
SELECT
    li.email_intentado,
    count(*) FILTER (WHERE li.exito = FALSE) AS intentos_fallidos,
    count(*) FILTER (WHERE li.exito = TRUE)  AS intentos_exitosos,
    min(li.ocurrido_en)                      AS primer_intento,
    max(li.ocurrido_en)                      AS ultimo_intento,
    count(DISTINCT li.origen)                AS origenes_distintos
FROM login_intento AS li
WHERE li.ocurrido_en >= CURRENT_TIMESTAMP - INTERVAL '15 minutes'
GROUP BY li.email_intentado
HAVING count(*) FILTER (WHERE li.exito = FALSE) >= 3;

COMMENT ON VIEW vw_intentos_login_sospechosos IS
    'Cuentas con 3+ intentos fallidos en 15 minutos. Insumo de detección para la Parte C.';

-- ----------------------------------------------------------------------------
-- 8. FUNCIÓN: FN_AUTENTICAR
--    Devuelve (autenticado, id_usuario, nombre_rol). Nunca lanza el error interno
--    ni distingue "usuario inexistente" de "contraseña incorrecta" (evita
--    enumeración de cuentas). Registra todo intento en login_intento.
--    SECURITY DEFINER + search_path fijo: puede leer password_hash sin que los
--    roles de aplicación tengan ese privilegio.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_autenticar(
    p_email    TEXT,
    p_password TEXT
)
RETURNS TABLE (
    autenticado BOOLEAN,
    id_usuario  BIGINT,
    nombre_rol  VARCHAR
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $fn$
DECLARE
    v_usuario usuario%ROWTYPE;
    v_rol     VARCHAR(60);
BEGIN
    autenticado := FALSE;
    id_usuario  := NULL;
    nombre_rol  := NULL;

    -- Validación de entrada: no se propaga ningún error al llamador.
    IF p_email IS NULL OR p_password IS NULL
       OR btrim(p_email) = '' OR p_password = '' THEN
        INSERT INTO public.login_intento (email_intentado, exito, motivo, origen)
        VALUES (left(coalesce(p_email, '(vacio)'), 150), FALSE, 'parametros_invalidos',
                inet_client_addr());
        RETURN NEXT;   -- RETURNS TABLE: sin RETURN NEXT no se emite ninguna fila
        RETURN;
    END IF;

    SELECT u.*
      INTO v_usuario
      FROM public.usuario AS u
     WHERE lower(u.email) = lower(btrim(p_email))
     LIMIT 1;

    -- Usuario inexistente o inactivo: mismo motivo, sin filtrar información.
    IF v_usuario.id_usuario IS NULL OR v_usuario.activo IS NOT TRUE THEN
        INSERT INTO public.login_intento (email_intentado, exito, motivo, origen)
        VALUES (left(btrim(p_email), 150), FALSE, 'credenciales_invalidas',
                inet_client_addr());
        RETURN NEXT;
        RETURN;
    END IF;

    IF v_usuario.password_hash = crypt(p_password, v_usuario.password_hash) THEN
        UPDATE public.usuario AS u
           SET ultimo_acceso = CURRENT_TIMESTAMP
         WHERE u.id_usuario = v_usuario.id_usuario;

        SELECT r.nombre INTO v_rol
          FROM public.rol AS r
         WHERE r.id_rol = v_usuario.id_rol;

        INSERT INTO public.login_intento (email_intentado, exito, motivo, origen)
        VALUES (v_usuario.email, TRUE, 'ok', inet_client_addr());

        autenticado := TRUE;
        id_usuario  := v_usuario.id_usuario;
        nombre_rol  := v_rol;
    ELSE
        INSERT INTO public.login_intento (email_intentado, exito, motivo, origen)
        VALUES (v_usuario.email, FALSE, 'credenciales_invalidas', inet_client_addr());
    END IF;

    RETURN NEXT;
    RETURN;
END;
$fn$;

COMMENT ON FUNCTION fn_autenticar(TEXT, TEXT) IS
    'Autentica un usuario de aplicación. Registra todo intento en login_intento. '
    'No distingue usuario inexistente de contraseña incorrecta.';

-- ----------------------------------------------------------------------------
-- 9. FUNCIÓN: FN_RESETEAR_PASSWORD
--    Reseteo administrativo. Valida largo mínimo, hashea con bcrypt y deja traza
--    en usuario_auditoria. Devuelve (actualizado, motivo) en lugar de lanzar
--    excepciones: el error SQL nunca llega al usuario final (norma AGENTS.md).
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_resetear_password(
    p_email          TEXT,
    p_password_nueva TEXT,
    p_actor          TEXT DEFAULT NULL
)
RETURNS TABLE (
    actualizado BOOLEAN,
    motivo      TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $fn$
DECLARE
    v_id_usuario BIGINT;
    v_actor      TEXT := coalesce(nullif(btrim(p_actor), ''), session_user);
BEGIN
    actualizado := FALSE;
    motivo      := 'no_aplicable';

    IF p_email IS NULL OR p_password_nueva IS NULL
       OR btrim(p_email) = '' OR length(p_password_nueva) < 12 THEN
        INSERT INTO public.usuario_auditoria
               (id_usuario, accion, actor, resultado, detalle)
        VALUES (NULL, 'RESET_PASSWORD', v_actor, 'RECHAZADO',
                jsonb_build_object('motivo', 'parametros_invalidos',
                                   'largo_minimo', 12));
        motivo := 'parametros_invalidos';
        RETURN NEXT;
        RETURN;
    END IF;

    SELECT u.id_usuario
      INTO v_id_usuario
      FROM public.usuario AS u
     WHERE lower(u.email) = lower(btrim(p_email))
       AND u.activo = TRUE;

    IF v_id_usuario IS NULL THEN
        INSERT INTO public.usuario_auditoria
               (id_usuario, accion, actor, resultado, detalle)
        VALUES (NULL, 'RESET_PASSWORD', v_actor, 'RECHAZADO',
                jsonb_build_object('motivo', 'usuario_no_encontrado'));
        -- Respuesta genérica: no confirma si el email existe.
        motivo := 'no_aplicable';
        RETURN NEXT;
        RETURN;
    END IF;

    UPDATE public.usuario AS u
       SET password_hash = crypt(p_password_nueva, gen_salt('bf', 12))
     WHERE u.id_usuario = v_id_usuario;

    INSERT INTO public.usuario_auditoria
           (id_usuario, accion, actor, resultado, detalle)
    VALUES (v_id_usuario, 'RESET_PASSWORD', v_actor, 'OK',
            jsonb_build_object('costo_bcrypt', 12));

    actualizado := TRUE;
    motivo      := 'ok';
    RETURN NEXT;
    RETURN;
END;
$fn$;

COMMENT ON FUNCTION fn_resetear_password(TEXT, TEXT, TEXT) IS
    'Reseteo administrativo de contraseña con bcrypt y traza en usuario_auditoria. '
    'Devuelve (actualizado, motivo); nunca expone el error SQL.';

-- ----------------------------------------------------------------------------
-- 10. DATOS SINTÉTICOS DE ARRANQUE
--     Catálogo de roles + 12 usuarios con PII SINTÉTICA (nombres, emails y
--     teléfonos inventados; dominio .test). Repartidos en 6 meses y 6 roles para
--     que la agregación de la Parte D tenga señal real.
--
--     La contraseña es sintética y de desarrollo. Se puede pasar por variable:
--       psql -v seed_password='...' -f ...
--     NUNCA usar esta clave fuera del entorno local.
-- ----------------------------------------------------------------------------
\if :{?seed_password}
\else
  \set seed_password 'FoodStore.Dev#2026'
\endif

INSERT INTO rol (nombre, descripcion) VALUES
    ('rol_app_lectura',   'Lectura de catálogo y pedidos para la aplicación web, sin PII de clientes.'),
    ('rol_app_escritura', 'Registro de pedidos y descuento de stock; sin borrados ni cambios de precio.'),
    ('rol_soporte',       'Atención al usuario: contacto y reseteo de credenciales, sin pedidos.'),
    ('rol_reportes',      'Consulta de reportes agregados a través de vistas y vista materializada.'),
    ('rol_auditoria',     'Lectura de trazas de login y auditoría; no puede modificarlas.'),
    ('rol_etl',           'Carga masiva de pedidos y detalle; sin UPDATE ni DELETE.')
ON CONFLICT (nombre) DO NOTHING;

INSERT INTO usuario (email, nombre, apellido, telefono, password_hash,
                     id_rol, fecha_alta, activo, id_cliente)
SELECT
    s.email,
    s.nombre,
    s.apellido,
    s.telefono,
    crypt(:'seed_password', gen_salt('bf', 12)),
    r.id_rol,
    s.fecha_alta::TIMESTAMPTZ,
    s.activo,
    NULL
FROM (VALUES
    ('maria.gonzalez@foodstore.test',   'María',    'González',  '+54 11 4555-0101', 'rol_soporte',       '2024-02-19 09:15:00-03', TRUE),
    ('juan.perez@foodstore.test',       'Juan',     'Pérez',     '+54 11 4555-0102', 'rol_soporte',       '2024-03-05 11:40:00-03', TRUE),
    ('lucia.fernandez@foodstore.test',  'Lucía',    'Fernández', '+54 11 4555-0103', 'rol_reportes',      '2024-05-21 08:05:00-03', TRUE),
    ('carlos.rodriguez@foodstore.test', 'Carlos',   'Rodríguez', '+54 11 4555-0104', 'rol_app_lectura',   '2024-07-02 16:30:00-03', TRUE),
    ('sofia.martinez@foodstore.test',   'Sofía',    'Martínez',  '+54 11 4555-0105', 'rol_app_escritura', '2024-09-14 10:00:00-03', TRUE),
    ('diego.lopez@foodstore.test',      'Diego',    'López',     '+54 11 4555-0106', 'rol_etl',           '2024-11-27 14:45:00-03', TRUE),
    ('valentina.sosa@foodstore.test',   'Valentina','Sosa',      '+54 11 4555-0107', 'rol_auditoria',     '2025-01-16 09:50:00-03', TRUE),
    ('martin.romero@foodstore.test',    'Martín',   'Romero',    '+54 11 4555-0108', 'rol_soporte',       '2025-03-08 12:20:00-03', TRUE),
    ('camila.torres@foodstore.test',    'Camila',   'Torres',    '+54 11 4555-0109', 'rol_reportes',      '2025-06-30 15:10:00-03', TRUE),
    ('nicolas.benitez@foodstore.test',  'Nicolás',  'Benítez',   '+54 11 4555-0110', 'rol_app_lectura',   '2025-09-11 08:35:00-03', TRUE),
    ('florencia.acosta@foodstore.test', 'Florencia','Acosta',    '+54 11 4555-0111', 'rol_app_escritura', '2026-01-22 17:00:00-03', FALSE),
    ('emiliano.castro@foodstore.test',  'Emiliano', 'Castro',    '+54 11 4555-0112', 'rol_etl',           '2026-03-04 10:25:00-03', FALSE)
) AS s(email, nombre, apellido, telefono, rol_nombre, fecha_alta, activo)
JOIN rol AS r ON r.nombre = s.rol_nombre
ON CONFLICT (email) DO NOTHING;

-- ----------------------------------------------------------------------------
-- 11. VERIFICACIÓN RÁPIDA DE LA RECONSTRUCCIÓN
-- ----------------------------------------------------------------------------
SELECT 'rol'              AS objeto, count(*) AS filas FROM rol
UNION ALL
SELECT 'usuario',           count(*) FROM usuario
UNION ALL
SELECT 'usuarios activos',  count(*) FROM usuario WHERE activo = TRUE
UNION ALL
SELECT 'roles distintos en uso', count(DISTINCT id_rol) FROM usuario
UNION ALL
SELECT 'hashes bcrypt',     count(*) FROM usuario WHERE password_hash ~ '^\$2[aby]\$'
ORDER BY objeto;

-- ============================================================================
-- RESULTADO ESPERADO (base dev recién inicializada)
--   rol                     6
--   usuario                12
--   usuarios activos       10
--   roles distintos en uso  6
--   hashes bcrypt          12
-- ============================================================================
