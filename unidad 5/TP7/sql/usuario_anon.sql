-- ============================================================================
-- USUARIO_ANON.SQL
-- TP — Unidad 5: Administración y seguridad de Food Store
-- PARTE D — Protección de datos personales: anonimización y equivalencia
--
-- QUÉ ES ESTO
--   Construye usuario_anon: una copia de usuario con datos sintéticos
--   DETERMINISTAS, y deja armado el control que demuestra que la copia no
--   distorsiona lo que la tabla tiene para decir en conjunto.
--
--   La frase anterior tiene dos mitades y las dos importan:
--     "determinista"     = correr el script dos veces produce exactamente la
--                          misma tabla (mismo hash, byte por byte).
--     "no distorsiona"   = los agregados que dependen de las columnas que se
--                          conservan dan idénticos contra la tabla real.
--   Una copia con nombres falsos pero con la distribución de altas destruida
--   no es una copia anónima: es una copia inútil. Y una copia que conserva todo
--   para no distorsionar nada es la tabla original con otro nombre.
--
-- QUÉ SE CONSERVA Y QUÉ SE REEMPLAZA (y por qué)
--
--   Conserved = la columna no identifica a una persona y hace falta para que un
--   agregado siga diciendo la verdad.
--
--   | Columna         | Destino            | Motivo                          |
--   |-----------------|--------------------|---------------------------------|
--   | id_usuario      | igual              | surrogate; no es PII y es la PK |
--   | id_rol          | igual              | es la dimensión del agregado    |
--   | activo          | igual              | se filtra en los reportes       |
--   | fecha_alta      | 1.er día del mes   | generalización: el día no hace  |
--   |                 |                    | falta para "por mes"            |
--   | ultimo_acceso   | 1.er día del mes   | idem (y es dato de conducta)    |
--   | email           | sintético único    | PII directa                     |
--   | nombre          | catálogo sintético | PII directa                     |
--   | apellido        | catálogo sintético | PII directa                     |
--   | telefono        | sintético con igual| PII directa (se conserva el     |
--   |                 | formato            | formato para que el tipo sirva) |
--   | password_hash   | hash de clave falsa| una credencial real, aunque sea |
--   |                 | determinista       | hash, no debe copiarse          |
--   | id_cliente      | surrogate          | preserva la cardinalidad        |
--   |                 | (id_cliente_anon)  | (usuarios por cliente) y rompe  |
--   |                 |                    | el join con cliente             |
--
--   Sobre id_cliente_anon: NO es cliente.id_cliente. Se reemplaza por un
--   dense_rank determinista que conserva "cuántos usuarios comparten cliente"
--   pero no permite volver al cliente comercial. Borrar la columna sería peor:
--   rompería cualquier agregado por cliente. (Hoy los 12 registros la tienen en
--   NULL; la regla queda escrita porque el esquema permite el vínculo.)
--
-- LA DECISIÓN QUE HACE POSIBLE LA PRUEBA DE EQUIVALENCIA
--   fecha_alta se trunca con date_trunc('month', fecha_alta) en la zona del
--   servidor, y se guarda como TIMESTAMPTZ a la medianoche LOCAL del día 1.
--   Con esa convención, tanto una consulta que agrupa en hora local como una
--   que normaliza a UTC obtienen el mismo mes: la medianoche local de -03 cae
--   a las 03:00 UTC del mismo día. Con la convención inversa (guardar la
--   medianoche UTC) las dos consultas discreparían en el mes. Ver
--   docs/verificacion_equivalencia.md § 4, donde está medido.
--
-- DETERMINISMO
--   Nada de random(): los nombres salen de un catálogo indexado por
--   id_usuario, y el hash sale de un bcrypt con sal derivada de md5(id). El
--   script imprime un checksum al final para poder comparar dos corridas.
--
-- USO
--   psql -U postgres -d foodstore_test -f TP7/sql/usuario_anon.sql
--   (idempotente: la tabla derivada se recrea en cada corrida)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- GUARDA DE ENTORNO
--   Mismo criterio que roles.sql y simulacro_incidente.sql: esto BORRA y
--   recrea una tabla, así que no corre sobre una base cuyo nombre no delate
--   test/dev/local. Override manual:
--     SET tp7.entorno_confirmado = 'si';
-- ----------------------------------------------------------------------------
\set ON_ERROR_STOP on
SET client_min_messages = warning;

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
-- 0. PRERREQUISITOS
--    pgcrypto hace falta para bcrypt; usuario y rol, para poder copiar.
-- ----------------------------------------------------------------------------
DO $pre$
BEGIN
    IF to_regclass('public.usuario') IS NULL OR to_regclass('public.rol') IS NULL THEN
        RAISE EXCEPTION 'Faltan las tablas usuario / rol. Ejecutar antes sql/00_reconstruccion_parte0.sql.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pgcrypto') THEN
        RAISE EXCEPTION 'Falta la extensión pgcrypto (la crea sql/00_reconstruccion_parte0.sql).';
    END IF;
END
$pre$;

\echo ''
\echo '=== 1. RECREACIÓN DE usuario_anon (artefacto derivado: se regenera entero) ==='

DROP TABLE IF EXISTS usuario_anon CASCADE;

CREATE TABLE usuario_anon (
    -- El surrogate se conserva: no identifica a una persona y es la PK.
    id_usuario      BIGINT       PRIMARY KEY,

    -- Identificadores: sintéticos, deterministas y únicos.
    email           VARCHAR(150) NOT NULL,
    nombre          VARCHAR(80)  NOT NULL,
    apellido        VARCHAR(80)  NOT NULL,
    telefono        VARCHAR(30)  NULL,

    -- Una credencial real, aunque sea un hash, no se copia.
    password_hash   TEXT         NOT NULL,

    -- Dimensiones que el agregado necesita y que no son PII.
    id_rol          SMALLINT     NOT NULL,
    activo          BOOLEAN      NOT NULL,

    -- Generalizadas al mes (el día exacto no aporta al agregado).
    fecha_alta      TIMESTAMPTZ  NOT NULL,
    ultimo_acceso   TIMESTAMPTZ  NULL,

    -- Surrogate: conserva la cardinalidad, rompe el join con cliente.
    id_cliente_anon BIGINT       NULL,

    CONSTRAINT fk_usuario_anon_rol FOREIGN KEY (id_rol)
        REFERENCES rol (id_rol) ON DELETE RESTRICT,

    CONSTRAINT uq_usuario_anon_email UNIQUE (email),

    CONSTRAINT chk_usuario_anon_email_formato
        CHECK (email ~ '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$'),

    -- El mismo CHECK que usuario: si alguien escribe un hash a mano, no entra.
    CONSTRAINT chk_usuario_anon_hash_bcrypt
        CHECK (password_hash ~ '^\$2[aby]\$[0-9]{2}\$.{53}$'),

    -- La invariante de la generalización: fecha_alta cae siempre el día 1.
    CONSTRAINT chk_usuario_anon_fecha_dia_1
        CHECK (date_part('day', fecha_alta) = 1),

    CONSTRAINT chk_usuario_anon_nombres_no_vacios
        CHECK (btrim(nombre) <> '' AND btrim(apellido) <> '')
);

COMMENT ON TABLE usuario_anon IS
    'Copia anonimizada de usuario con datos sintéticos deterministas. '
    'Conserva id_usuario, id_rol, activo y el MES de fecha_alta/ultimo_acceso, '
    'que es lo que necesita el agregado por rol y por mes. No sirve para '
    'identificar personas ni para autenticar.';

\echo '    Tabla creada con 11 columnas y 6 constraints.'

-- ----------------------------------------------------------------------------
-- 2. POBLADO DETERMINISTA
--    Catálogos sintéticos disjuntos de los nombres reales del seed: si un
--    nombre de usuario_anon coincidiera con uno real, la copia podría
--    "confirmar" por parecido lo que justamente intenta ocultar.
-- ----------------------------------------------------------------------------
\echo ''
\echo '=== 2. POBLADO: sintético, sin random(), reproducible byte por byte ==='

INSERT INTO usuario_anon (
    id_usuario, email, nombre, apellido, telefono, password_hash,
    id_rol, activo, fecha_alta, ultimo_acceso, id_cliente_anon
)
SELECT
    u.id_usuario,

    -- Email: el número de fila conserva la unicidad sin decir quién es.
    'usuario' || lpad(u.id_usuario::text, 3, '0') || '@ejemplo.test',

    -- Nombre y apellido: catálogo indexado por id (módulo), sin azar.
    (ARRAY['Ariel','Brenda','Ciro','Dora','Elsa','Fabio','Greta','Hugo',
           'Irene','Jonás','Karina','Lautaro','Marta','Nicolás','Omar',
           'Paula','Ramiro','Silvina','Tomás','Verónica'])[1 + ((u.id_usuario - 1) % 20)],

    -- Offset distinto para que la pareja nombre/apellido no se repita en ciclo.
    (ARRAY['Almirón','Bustos','Cabrera','Duarte','Escobar','Figueroa','Guzmán',
           'Herrera','Ibarra','Juárez','Krauss','Leiva','Molina','Navarro',
           'Ojeda','Paredes','Quiroga','Ramírez','Silva','Valdez'])[1 + ((u.id_usuario + 6) % 20)],

    -- Teléfono: formato creíble, número ficticio y determinista (5555 es el
    -- prefijo que se usa para ficción; además acá no hay colisión).
    '+54 11 5555-' || lpad((((u.id_usuario * 137) % 10000))::text, 4, '0'),

    -- bcrypt de una clave falsa, con sal derivada del id: misma fila, mismo
    -- hash, siempre. Un hash real, aun sin la clave, es una credencial.
    crypt('clave-anonima-de-usuario_anon',
          '$2a$12$' || substr(md5('tp7-anon-' || u.id_usuario), 1, 22)),

    u.id_rol,
    u.activo,

    -- Generalización: el mes al que pertenece la fecha, a medianoche local.
    date_trunc('month', u.fecha_alta),

    -- Igual, preservando NULL (no toda cuenta se usó alguna vez).
    date_trunc('month', u.ultimo_acceso),

    -- Surrogate del cliente: mismo número para el mismo cliente, sin relación
    -- con cliente.id_cliente. dense_rank numera los clientes distintos en
    -- orden de id; como en un ORDER BY ascendente los NULL van al final, las
    -- filas sin cliente no desplazan la numeración de las que sí tienen, y el
    -- CASE las deja en NULL en la salida.
    CASE WHEN u.id_cliente IS NULL THEN NULL
         ELSE dense_rank() OVER (ORDER BY u.id_cliente)
    END
FROM usuario u
ORDER BY u.id_usuario;

\echo '    Filas insertadas (debe coincidir con usuario):'

SELECT (SELECT count(*) FROM usuario)      AS filas_usuario,
       (SELECT count(*) FROM usuario_anon) AS filas_anon,
       CASE WHEN (SELECT count(*) FROM usuario) = (SELECT count(*) FROM usuario_anon)
            THEN 'IGUAL' ELSE 'DIFIERE' END AS conteo;

-- ----------------------------------------------------------------------------
-- 3. AUTOCONTROLES DE LA COPIA
--    Lo que tiene que ser cierto para que la copia sirva, verificado acá y no
--    "a ojo" en el informe.
-- ----------------------------------------------------------------------------
\echo ''
\echo '=== 3. AUTOCONTROLES ==='

\echo '3.a) PII: ningún valor de la tabla original sobrevive en la copia.'
\echo '     (los cuatro conteos deben dar 0)'
SELECT count(*) FILTER (WHERE a.email    = u.email)    AS emails_reales,
       count(*) FILTER (WHERE a.nombre   = u.nombre)   AS nombres_reales,
       count(*) FILTER (WHERE a.apellido = u.apellido) AS apellidos_reales,
       count(*) FILTER (WHERE a.telefono = u.telefono) AS telefonos_reales
FROM usuario_anon a JOIN usuario u USING (id_usuario);

\echo ''
\echo '3.b) Unicidad: email único y un hash por fila (12 distintos).'
SELECT count(*)                          AS filas,
       count(DISTINCT email)             AS emails_distintos,
       count(DISTINCT password_hash)     AS hashes_distintos
FROM usuario_anon;

\echo ''
\echo '3.c) Formato y determinismo: todos los hashes son bcrypt costo 12 y el'
\echo '     checksum de la tabla debe ser idéntico entre dos corridas.'
SELECT count(*) FILTER (WHERE password_hash ~ '^\$2a\$12\$') AS hashes_bcrypt_12,
       md5(string_agg(id_usuario::text || '|' || email || '|' || nombre || '|' ||
                      apellido || '|' || telefono || '|' || password_hash || '|' ||
                      id_rol::text || '|' || activo::text || '|' ||
                      fecha_alta::text || '|' ||
                      coalesce(ultimo_acceso::text, '-') || '|' ||
                      coalesce(id_cliente_anon::text, '-'),
                      E'\n' ORDER BY id_usuario)) AS checksum_tabla
FROM usuario_anon;

\echo ''
\echo '3.d) Generalización: toda fecha_alta está el día 1 de su mes.'
SELECT count(*) AS filas_con_dia_distinto_de_1
FROM usuario_anon
WHERE date_part('day', fecha_alta) <> 1;

\echo ''
\echo '3.e) Dimensiones conservadas (id_rol / activo / mes): 0 diferencias.'
\echo '     Si esto no da 0, la copia ya no sirve para el agregado.'
SELECT count(*) AS diferencias_dimensiones
FROM usuario_anon a JOIN usuario u USING (id_usuario)
WHERE a.id_rol <> u.id_rol
   OR a.activo <> u.activo
   OR to_char(date_trunc('month', a.fecha_alta), 'YYYY-MM')
      <> to_char(date_trunc('month', u.fecha_alta), 'YYYY-MM');

\echo ''
\echo 'LISTO. La equivalencia de los agregados se demuestra en'
\echo 'docs/verificacion_equivalencia.sql y se documenta en'
\echo 'docs/verificacion_equivalencia.md.'
