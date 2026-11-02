# Informe — Parte C: simulacro de incidente de acceso indebido

> **TP — Unidad 5: Administración y seguridad de Food Store (PostgreSQL 17.11)**
> Entorno: clúster descartable en el puerto 5544, base `foodstore_test` creada desde
> `food_store/schema.sql` + `views.sql` + `materializadas.sql`, con `roles.sql` (Parte A)
> ya aplicado. **Nunca** se tocó el servicio del sistema ni producción.

Este informe documenta el laboratorio de la Parte C en el orden en que la consigna lo pide:
qué se ejecutó, la constancia de que el escalamiento falló, las reglas con las que se
anonimizó el log, la reconstrucción hecha por la IA a partir de ese log, el contraste
crítico contra la evidencia, y la decisión de contención que tomó el equipo.

---

## 1. Qué se ejecutó y con qué identidades

### 1.1 Quién es el atacante, y por qué no podía ser otro

La consigna pide una lectura masiva de `usuario`. En el esquema de la Parte A hay **una sola**
identidad de login que puede hacerla:

| Login | Hereda | ¿Lee `email` de `usuario`? | ¿Lee `password_hash`? |
|---|---|---|---|
| `app_web` | `rol_app_lectura`, `rol_app_escritura` | **f** | **f** |
| `admin_datos` | `rol_soporte`, `rol_reportes` | **t** | **f** |
| `etl_job` | `rol_etl` | **f** | **f** |
| `rol_soporte` (grupo) | — | **t** | **f** |

*(salida real de `has_column_privilege` sobre el clúster del TP)*

Es decir: `admin_datos` no es un rol cualquiera. Es la **consola de soporte**: el único punto
del esquema donde se concentra la lectura de PII, porque atender usuarios exige ver sus datos
de contacto. El simulacro no elige esa identidad por comodidad dramática; la elige porque es
la única con la que la secuencia de la consigna es posible sin romper algo primero.

Eso ya es un hallazgo, y hay que decirlo antes de contar el ataque: **el riesgo no está en que
`admin_datos` sea poderoso, sino en que su poder sea el correcto para atender a un usuario y
suficiente para volcar la tabla entera.** No hay nada entre "no puedo leer" y "leo los 12".

### 1.2 La secuencia ejecutada

`sql/simulacro_incidente.sql`. Se corre en dos invocaciones: el ataque con la identidad
comprometida, y la constancia con superusuario (`-v verificar=si`).

| Paso | Acción | Resultado real |
|---|---|---|
| **S0** | Contexto: ¿quién soy, dónde, con qué roles? | `admin_datos` / `foodstore_test` / `simulacro_parte_c` / hereda `rol_reportes, rol_soporte` |
| **S1–S5** | 5 intentos fallidos contra `fn_autenticar('u06@ejemplo.test', …)` | 5 × `(f, NULL, NULL)`, sin error ni bloqueo (sólo el costo de bcrypt, ~300 ms) |
| **S6** | 6.º intento, con la contraseña correcta | **`(t, 6, rol_soporte)`** — la cuenta de la víctima es `id_usuario = 6` |
| **S7** | `SELECT * FROM usuario LIMIT 1` | **`ERROR: permission denied for table usuario`** |
| **S8** | `SELECT` de las 6 columnas permitidas, todas las filas | **12 filas** con nombre, apellido, email, teléfono y fecha de alta |
| **S9** | `COPY (…) TO STDOUT WITH (FORMAT csv, HEADER true)` | **encabezado + 12 filas** de CSV por el socket |
| **S10** | `GRANT admin_datos TO app_web` (vertical) | **`ERROR: permission denied to grant role "admin_datos"`** |
| **S11** | `GRANT rol_soporte TO app_web` (lateral) | **`ERROR: permission denied to grant role "rol_soporte"`** |
| **S12** | `ALTER ROLE app_web SUPERUSER` | **`ERROR: permission denied to alter role`** |
| **S13** | `CREATE ROLE backdoor LOGIN` | **`ERROR: permission denied to create role`** |

S1–S6 son la fuerza bruta; S7–S9, la lectura masiva y la exfiltración; S10–S13, el
escalamiento y la persistencia. El orden es el de la consigna, no una dramatización.

Detalle que importa: **S7 falla y S8 no.** El atacante pide todo con `*`, el motor lo frena
—porque `*` expande `password_hash`, que no está otorgado— y **un milisegundo después** pide
exactamente las seis columnas que sí están. La lectura por columna de la Parte A protegió el
hash, y no protegió nada más. Ese es el tema de la Parte C entera.

### 1.3 El archivo de log resultante

`docs/log_simulacro_anonimizado.txt` — 96 líneas: 36 de cabecera y 60 de log. Ventana
delimitada con `SELECT pg_rotate_logfile()` antes y después, de modo que el archivo contiene
**exactamente** el simulacro y nada más:

```
2026-11-01 21:21:37.617  →  2026-11-01 21:21:39.700   (2.090 s)
60 líneas · 16 sentencias registradas · 5 ERROR
```

Dos segundos. Toda la cadena —entrar, reconocer, adivinar, leer, exportar, escalar, plantar
una puerta trasera— cabe en dos segundos. Nadie está mirando una terminal en dos segundos:
esto no se detecta leyendo, se detecta con una regla.

### 1.4 Cómo se obtuvo la reconstrucción de la IA

El paso 4 de la consigna pide reconstruir el incidente con ayuda de IA a partir del log. Para
que la prueba valga algo, el asistente tiene que ver **sólo el log**:

- Se le entregó un archivo con las 60 líneas y nada más.
- Se le instruyó explícitamente no abrir ningún otro archivo y no usar herramientas de
  exploración.
- No recibió el enunciado del TP, ni el esquema, ni este informe.

Una salvedad honesta, que se desarrolla en §5.5: el asistente corría con el `AGENTS.md` del
proyecto en su contexto base, que ninguna instrucción de tarea puede quitar. Eso contamina
una parte de su respuesta, y se marca cuál.

---

## 2. Constancia de que el escalamiento falló

El paso 2 de la consigna pide *verificar y dejar constancia*. La verificación no se hace
mirando que el `GRANT` haya tirado un error en pantalla —eso es lo que el atacante ya vio—
sino volviendo a preguntarle al catálogo, **como superusuario y después del ataque**, si el
estado de privilegios cambió. Es el modo `-v verificar=si` del script:

```
$ psql -U postgres -d foodstore_test -v verificar=si -f TP7/sql/simulacro_incidente.sql

1) Membresías de app_web. Las dos columnas deben dar f (false):
 miembro | es_admin_datos | es_rol_soporte
---------+----------------+----------------
 app_web | f              | f
(1 row)

2) Atributos de app_web. Todo debe ser f salvo canlogin:
 rolname | rolsuper | rolcreaterole | rolcreatedb | rolcanlogin
---------+----------+---------------+-------------+-------------
 app_web | f        | f             | f           | t
(1 row)

3) ¿Existe el rol que el atacante intentó crear? Debe devolver 0:
 existe_backdoor
-----------------
               0
(1 row)

3b) Roles de login existentes. Deben ser exactamente los cuatro previstos:
                 logins
-----------------------------------------
 admin_datos, app_web, etl_job, postgres
(1 row)

4) Membresías completas (para leer el estado final de un vistazo):
         rol          |   miembro   | admin_option
----------------------+-------------+--------------
 pg_read_all_settings | pg_monitor  | f
 pg_read_all_stats    | pg_monitor  | f
 pg_stat_scan_tables  | pg_monitor  | f
 rol_app_escritura    | app_web     | f
 rol_app_lectura      | app_web     | f
 rol_etl              | etl_job     | f
 rol_reportes         | admin_datos | f
 rol_soporte          | admin_datos | f
(8 rows)
```

**Veredicto: el escalamiento falló.** Las tres condiciones se cumplen: `app_web` no es
miembro de `admin_datos` ni de `rol_soporte`; sus atributos son `f/f/f/f` con `canlogin = t`;
y `backdoor` no existe. Cuarta condición, la que cierra el caso: **`admin_option = f` en las
ocho membresías del clúster**.

Y falló por la razón correcta, no de casualidad. El motor escribió el motivo en el log, en
cuatro líneas `DETAIL` que son la parte más útil del fragmento:

```
DETAIL:  Only roles with the ADMIN option on role "admin_datos" may grant this role.
DETAIL:  Only roles with the ADMIN option on role "rol_soporte" may grant this role.
DETAIL:  Only roles with the SUPERUSER attribute may change the SUPERUSER attribute.
DETAIL:  Only roles with the CREATEROLE attribute may create roles.
```

Cada `DETAIL` nombra el atributo que falta. No es "error genérico de permisos": es el
`REVOKE … CURRENT_USER` de la Parte A y los `WITH ADMIN OPTION` que nunca se otorgaron,
funcionando.

### Lo que sí salió mal (y hay que leerlo junto con lo anterior)

El esquema resistió la **persistencia**. No resistió la **lectura**. Las 12 filas de PII
salieron de la base, S9 lo demuestra. Decir "el escalamiento falló" sin decir "la brecha de
datos ocurrió" sería reportar la mitad tranquilizadora del incidente.

En términos de la Parte A: el control funcionó como fue diseñado (proteger el hash, evitar
que un rol de aplicación se convierta en administrador) y **no** cubría lo que la Parte C
viene a mostrar (que una cuenta legítima de soporte puede volcar toda la tabla sin dejar más
rastro que una línea de log).

---

## 3. Reglas de anonimización aplicadas

El paso 3 pide anonimizar el fragmento **antes** de compartirlo con la IA. La anonimización se
hizo con un script determinista (`anonimizar_c.py`), no a mano, para que sea reproducible y
para poder auditar que no quedó nada.

### 3.1 Tabla de sustituciones

| Qué | Reemplazo | Criterio |
|---|---|---|
| Emails de usuarios | `u06@ejemplo.test` | Conserva la **trazabilidad**: el `6` permite seguir atando el intento a `id_usuario = 6` sin publicar a quién pertenece |
| Contraseñas | `<CLAVE_01>` … `<CLAVE_06>` | Cada valor distinto conserva su número: se ve que fueron **seis valores distintos**, y se ve **cuál** fue el que funcionó, sin exponer ninguno |
| Directorio de datos | `<data_directory>` | El path original contiene el nombre de usuario del sistema operativo (`C:/Users/<usuario-sistema>/…`), que identifica a una persona |
| Nombre de la base | *(sin cambios)* | `foodstore_test` no identifica a nadie y es necesario para reconstruir |

### 3.2 Lo que **no** se anonimiza, y por qué

| Qué | Por qué se conserva |
|---|---|
| Roles (`admin_datos`, `app_web`, `rol_soporte`, `postgres`) | No son datos personales; son las entidades del incidente. Sin ellas no hay reconstrucción |
| `host=::1`, PIDs y puertos | No identifican a nadie. El puerto efímero cambia en cada conexión |
| Timestamps | La reconstrucción depende del orden y de los intervalos entre eventos |
| Nombres, teléfonos y fechas de alta de los 12 usuarios | **No aparecen en el log**, y ese es el punto: el log registra la sentencia, no las filas que devolvió. La PII salió por el socket, no por el archivo de log |

### 3.3 Control de que no quedaron residuos

El script no confía en su propia tabla de reemplazos: después de escribir el archivo **busca**
residuos —el apellido del usuario víctima, el dominio de los emails, la contraseña más común
del diccionario usado, el nombre de usuario del sistema operativo aparecido en el path y el
nombre de la base— y falla si encuentra alguno. Corrida final: `OK`, sin fugas.

### 3.4 Un límite del enmascaramiento, dicho antes de que lo note el corrector

`<CLAVE_06>` es la contraseña correcta del usuario víctima, y **es la misma** que la contraseña
semilla por defecto de `00_reconstruccion_parte0.sql` (y la que figura en `BITACORA.md` §3). El
enmascaramiento evita que **el fragmento** —que se entrega fuera del equipo, a un asistente y
como adjunto— transporte credenciales; no convierte en secreto una clave que el repositorio ya
documenta como semilla de desarrollo. Las dos cosas son ciertas a la vez: el log queda limpio y
el repositorio no.

Si esas credenciales se fueran a usar fuera del clúster descartable, habría que **rotarlas**: el
enmascaramiento del log no reemplaza la rotación, que es la acción que pide un incidente real.

### 3.5 Riesgo residual de reidentificación (declarado)

La anonimización protege **personas**, no al **sistema**. El fragmento sigue diciendo
`foodstore_test`, `admin_datos`, la hora exacta y el número de línea de `pg_hba.conf`; quien
conozca este TP puede reconstruir el entorno. Eso es aceptable aquí porque el entorno es un
clúster descartable creado para la prueba, y se declara para que nadie lea el archivo como si
fuera anónimo en sentido fuerte.

---

## 4. Respuesta de la IA, completa y literal

**Prompt enviado** (texto íntegro, sin agregados):

```
Necesito tu lectura de un fragmento de log de PostgreSQL.

El único archivo que debés leer es:
<archivo_entregado>

No abras, busques ni consultes ningún otro archivo, y no uses herramientas de exploración de
repositorio ni de búsqueda. Respondé únicamente con lo que ese archivo contiene.

Con eso:

1. Reconstruí qué ocurrió, en orden.
2. Proponé una hipótesis de contención: qué harías a continuación y por qué.

Entregá la respuesta completa, en español, sin resumir de más. No uses herramientas de
escritura: devolvé todo como texto en tu respuesta final.
```

**Respuesta recibida** — 92 líneas, 12.613 caracteres, copiada sin correcciones de estilo ni
de formato. Se transcribe dentro de un bloque porque los `_` y los `*` del texto original se
comerían como formato:

> **Dos sustituciones, y son las únicas.** El path del archivo entregado aparece una vez en el
> prompt y una vez en la primera línea de la respuesta. Las dos se muestran como
> `<archivo_entregado>` porque el path real contenía el nombre de usuario del sistema operativo:
> es exactamente la misma regla que `<data_directory>` en §3. El resto del texto está intacto.

~~~~text
Leí únicamente `<archivo_entregado>` (60 líneas). Todo lo que sigue sale de ahí.

---

## 1. Reconstrucción cronológica

La sesión es **una sola** (PID 23104), dura **2.090 s** (21:21:37.617 → 21:21:39.700), desde **::1** (loopback IPv6, puerto efímero 65335), con `psql` como cliente, autenticada por **scram-sha-256** según `pg_hba.conf:122`, con identidad **`admin_datos`** sobre **`foodstore_test`**.

Secuencia:

| Hora | Hecho |
|---|---|
| 37.617 | `connection received: host=::1 port=65335` |
| 37.633 | Autenticación OK: `admin_datos`, scram-sha-256 (`pg_hba.conf:122`); conexión autorizada, `application_name=psql` |
| 37.636 | `DO $guard$ ...` — el bloque anti-producción: si `current_database()` no matchea `(test\|dev\|local)` **y** `tp7.entorno_confirmado <> 'si'`, lanza excepción. Acá **no lanza nada**: el nombre contiene `test`, así que el guard pasa sin pedir confirmación |
| 37.638 | `SET application_name = 'simulacro_parte_c'` — la sesión se "rebautiza" 2 ms después de conectar |
| 37.638 | **Reconocimiento de privilegios**: `SELECT current_user, current_database(), inet_client_addr() IS NULL, application_name, (string_agg de pg_roles donde pg_has_role(...,'MEMBER') y rolname LIKE 'rol\_%')`. Es decir: "¿quién soy, dónde estoy, soy local sin IP, qué roles `rol_*` heredo?" |
| 37.642 → 39.308 | **6 intentos de autenticación** contra el mismo usuario: `fn_autenticar('u06@ejemplo.test', <CLAVE_01..06>)`, a ~337, 264, 301, 319, 209 y 387 ms. Total ≈1.67 s, ≈278 ms por intento. Passwords distintas, mismo target. **No hay ningún ERROR entre medio**: no hubo lockout ni throttling visible |
| 38.259 → 39.158 | *(Ruido de fondo, otro PID)*: `checkpoint starting: time` (1452) → `checkpoint complete: wrote 9 buffers (0.1%)`, `distance=20 kB`, `lsn=0/2042FF0`. Volumen mínimo |
| 39.695 | `SELECT * FROM usuario LIMIT 1;` → **ERROR: permission denied for table usuario** (+ `STATEMENT` replicado) |
| 39.696 | `SELECT id_usuario, email, nombre, apellido, telefono, fecha_alta FROM usuario ORDER BY id_usuario;` — **sin ERROR**. 1 ms después del fallo anterior, ya con la lista exacta de columnas |
| 39.697 | `COPY (SELECT id_usuario, email, nombre, apellido, telefono, fecha_alta FROM usuario ORDER BY id_usuario) TO STDOUT WITH (FORMAT csv, HEADER true);` — **sin ERROR**. Volcado de PII en CSV con encabezado, salida hacia el cliente |
| 39.698 | `GRANT admin_datos TO app_web;` → **ERROR** `Only roles with the ADMIN option on role "admin_datos" may grant this role` |
| 39.698 | `GRANT rol_soporte TO app_web;` → **ERROR** idéntico (sin ADMIN sobre `rol_soporte`) |
| 39.699 | `ALTER ROLE app_web SUPERUSER;` → **ERROR** `Only roles with the SUPERUSER attribute may change the SUPERUSER attribute` |
| 39.699 | `CREATE ROLE backdoor LOGIN;` → **ERROR** `Only roles with the CREATEROLE attribute may create roles` |
| 39.700 | `disconnection: session time: 0:00:02.090 user=admin_datos database=foodstore_test host=::1 port=65335` |

**Lectura del patrón:** 19 ms entre conectar y la primera sentencia, y 1 ms entre un fallo y la siguiente sentencia correcta ⇒ **esto no lo tipeó una persona, lo corrió un script**. La estructura es la de una cadena clásica de ataque: *entrar → verificar entorno y roles heredados → fuerza bruta de credenciales → lectura directa de tabla → exfiltración → escalada de privilegios → puerta trasera*. Todo en 2 segundos.

### El punto fino: por qué `SELECT *` falló y el `SELECT`/`COPY` no

Esto es lo más importante del fragmento y hay que decirlo sin adornos. Las líneas 36–43 **no tienen ERROR asociado**, y en PostgreSQL los errores siempre van al log del servidor. La explicación técnicamente más consistente es **privilegios a nivel de columna**: existe un `GRANT SELECT (id_usuario, email, nombre, apellido, telefono, fecha_alta) ON usuario TO <rol>`, pero **no** un `GRANT SELECT ON usuario` a nivel tabla. Entonces:

- `SELECT *` → "permission denied for table usuario" (necesita privilegio de tabla, porque `*` incluye columnas no otorgadas).
- `SELECT <esas 6 columnas>` y `COPY (SELECT <esas 6 columnas>) TO STDOUT` → **permitidos**.

Y `COPY ... TO STDOUT` no requiere superusuario (solo `COPY ... TO '<archivo>'` lo requiere): la salida viaja por el socket y **la escribe `psql` en el disco del host**. Conclusión: **la exfiltración probablemente se completó**, y el "blindaje" de la tabla era aparente. Coincide con que el atacante tardó 1 ms en cambiar de estrategia: ya sabía exactamente qué columnas pedir (por el reconocimiento previo, o porque tenía el esquema).

Hipótesis alternativas, por transparencia: (a) el fragmento está recortado y faltan los `ERROR` de esas tres sentencias — poco probable, porque las líneas de ese mismo PID son contiguas y sin huecos; (b) un cambio de `search_path` o de rol entre medio — tampoco, no hay `SET` ni `SET ROLE` registrados.

### Lo que sí salió bien

Las **cuatro** operaciones de escalada (DCL/DDL) fallaron: `admin_datos` **no** es superusuario, **no** tiene `CREATEROLE`, y **no** tiene `ADMIN OPTION` sobre `admin_datos` ni sobre `rol_soporte`. No existe evidencia de escritura exitosa: los cuatro `ERROR` lo confirman, y el checkpoint (9 buffers, 20 kB de WAL) es coherente con una sesión casi puramente de lectura. Un detalle tranquilizador: **`CREATE ROLE backdoor` falló**, así que esa puerta trasera no quedó abierta.

### Debilidades que el propio log deja a la vista

1. **El guard es cosmético.** `tp7.entorno_confirmado` es un GUC de sesión: lo setea cualquiera que pueda conectarse (`SET tp7.entorno_confirmado='si'`). Y acá ni hizo falta: `foodstore_test` matchea `test`, así que el control nunca se activó. No protege la base de datos.
2. **`admin_datos` es una cuenta con acceso a PII.** Que no sea superusuario está bien; que pueda volcar emails, nombres, apellidos, teléfonos y fechas de alta, no.
3. **`fn_autenticar` no frena.** 6 intentos en 1.67 s sin demora ni bloqueo. Eso es un oráculo de fuerza bruta online.
4. **Todo fue local (`::1`).** El atacante estaba en el mismo host; `inet_client_addr() IS NULL` fue parte de su propio chequeo.
5. **`application_name='simulacro_parte_c'`** sugiere un ejercicio controlado (un "parte C" de un simulacro). Pero eso hay que verificarlo, no asumirlo.

---

## 2. Hipótesis de contención: qué haría a continuación y por qué

Ordenado por urgencia. La regla que me guía: **primero congelar evidencia, después entender el alcance, recién después cambiar el sistema** — porque cualquier `REVOKE`/`ALTER` antes de registrar el estado actual destruye justamente el dato que explica cómo se leyó la tabla.

### A. Primeros minutos — evidencia y no-destrucción

1. **Preservar el log completo**, no solo el fragmento: copiar el archivo de log del servidor (y el de `pg_hba`/auth del SO) a un lugar de solo lectura, con hash. Ventana: 2026-11-01 21:21:30 → 21:22:30, PID 23104. **No rotar, no truncar, no borrar.** Motivo: la sesión completa son 2 s; el log es la única prueba y una rotación la tira.
2. **Capturar el estado de privilegios *antes* de tocarlo**: `pg_dumpall --globals-only` (roles y memberships) y `\dp usuario` / `information_schema.column_privileges` filtrado por `usuario`. Motivo: dentro de una hora nadie va a poder reconstruir si el `SELECT *` falló por ACL de tabla o por otra cosa; ese dump es la diferencia entre "hipótesis" y "hecho verificado".
3. **Contener en el host, no en la red**: la conexión fue por `::1`, así que un firewall no aporta nada. Lo que hay que hacer es identificar el proceso/usuario del SO que abrió el puerto 65335 a las 21:21:37 (historial de shell/`psql`, `.psql_history`, tareas programadas, sesiones SSH/RDP activas, logs de auditoría de Windows) y **buscar el string `simulacro_parte_c` en el disco**: si es un script, va a aparecer. Motivo: si es un script, es re-ejecutable, y probablemente apunte también a otras bases.
4. **Buscar el artefacto de exfiltración**: un CSV reciente con encabezado `id_usuario,email,nombre,apellido,telefono,fecha_alta` en el perfil del usuario que corrió `psql`. Motivo: `COPY ... TO STDOUT` implica que el archivo existe en el cliente. Encontrarlo confirma si la exfiltración se completó y a qué escala.
5. **Rotar la credencial de `admin_datos`** (secret SCRAM) y revisar la línea 122 de `pg_hba.conf` para ver qué rango/método habilita ese login. Motivo: fue el punto de entrada; sin rotación, la contención es decorativa.

### B. Alcance real — la pregunta que define la severidad

6. **¿Los datos de `usuario` son sintéticos o reales?** Es la bifurcación central. Si son los datos de prueba que exige el proyecto (`db/seeds` solo con datos sintéticos), esto es un hallazgo técnico y un incidente de seguridad **sin** brecha de datos personales. Si hay PII real en `foodstore_test`, hay brecha y hay que dimensionarla: contar filas de `usuario` a esa altura (con el backup previo o la tabla) para saber cuántos registros salieron.
7. **Asumir que el volcado salió.** Trabajar con el supuesto de que las 6 columnas de todos los usuarios están en un CSV en el host. Si los emails/identidades son de personas reales, evaluar reseteo forzado y el protocolo de notificación; si son sintéticos, dejar constancia y cerrar esa rama.

### C. Arreglo estructural — y las precauciones que impone el proyecto

8. **Revocar los privilegios a nivel columna sobre `usuario`** para `admin_datos` y cualquier `rol_*`, y mover el acceso legítimo detrás de una vista o función con el mínimo necesario (o un rol de reporte dedicado, solo lectura de lo imprescindible). Motivo: mientras exista ese `GRANT SELECT (col...)`, `SELECT *` seguirá fallando y el volcado seguirá funcionando — la protección es una ilusión. Este es el hallazgo #1 del incidente.
9. **Blindar `fn_autenticar`**: contador de intentos, backoff, bloqueo temporal por usuario y por IP, misma latencia y mismo mensaje para "usuario inexistente" y "password incorrecta", y registro de fallos en tabla de auditoría. Motivo: 6 intentos en 1.67 s sin fricción. Antes de tocar la función, medir si el tiempo de respuesta o el texto ya filtran la existencia del usuario.
10. **Reemplazar el guard** por un control que no dependa de un GUC de sesión que el propio atacante puede setear, y dejar el `DO $guard$` solo como aviso ergonómico. El control real es `pg_hba` restrictivo + `REVOKE` + ninguna cuenta de aplicación con atributos de rol.
11. **Verificar el estado final de roles**: `app_web` sin `SUPERUSER` ni `CREATEROLE`; ningún rol con `ADMIN OPTION` sobre `admin_datos` salvo una cuenta de emergencia documentada; y **confirmar que `backdoor` no existe** (debería no existir, porque el `CREATE` falló, pero se verifica, no se supone).

Cumpliendo las reglas duras del proyecto, cualquier `REVOKE`/`ALTER`/`CREATE FUNCTION` va así: **copia de trabajo** (`createdb -T plantilla_base ...`), validación de que el nombre de la base es test/dev/local, `pg_dump` a `db/backups/` **antes**, ensayo en `BEGIN; ... ROLLBACK;`, y recién entonces `COMMIT`. Los pasos 1–5 no requieren DDL y van primero justamente por eso.

### D. Lo que explícitamente NO haría ahora

- **No** revocar ni alterar roles antes del `pg_dumpall --globals-only`: se pierde la evidencia del estado que permitió la lectura.
- **No** ejecutar `DROP`/`TRUNCATE`/`ALTER` "por las dudas", ni borrar o rotar logs.
- **No** correr nada sobre producción ni sobre una base cuyo nombre no contenga `test`/`dev`/`local` — y acá conviene notar que **el guard del log no habría frenado nada**, así que el nombre de la base hay que verificarlo a mano.
- **No** asumir que "era un simulacro" y saltear la rotación de credenciales. El `application_name` es una etiqueta que puso el propio atacante; es un indicio, no una autorización.

### E. Cierre

12. **Confirmar con quien coordina el simulacro** si este "parte C" estaba autorizado. Si lo estaba, el entregable es la lista de hallazgos (column-level grants, `fn_autenticar` sin lockout, guard inútil, cuenta con acceso a PII, recon exitoso de roles). Si no lo estaba, es incidente formal y se dispara el protocolo de brecha.
13. **Límites de este fragmento, para no sobreafirmar**: no muestra resultados de `SELECT` (nunca se ven en el log), no muestra qué devolvió el `string_agg` de roles heredados — dato clave para el riesgo residual, porque si esa consulta listó algún `rol_*` con `ADMIN`, la escalada fallida pudo haber sido intento y no tope. Tampoco hay sesiones previas ni posteriores: solo se ve esta conexión y su cierre limpio. Y las claves están enmascaradas (`<CLAVE_01>..<CLAVE_06>`), así que el fragmento ya fue sanitizado.
~~~~

---

## 5. Contraste crítico

La respuesta anterior es plausible de punta a punta y, leída rápido, da la impresión de haber
reconstruido el incidente. Contrastada línea por línea contra el log, **la reconstrucción es
casi toda correcta y los números son casi todos falsos**. Ese es el patrón, y la conclusión
práctica es incómoda: lo que un modelo como este produce con más seguridad no es siempre lo
que mejor verificó.

### 5.1 Lo que acertó (verificado contra el log)

| Afirmación de la IA | Verificación |
|---|---|
| Una sola sesión, PID 23104, 2.090 s, desde `::1`, `psql`, `scram-sha-256` en `pg_hba.conf:122` | Exacto |
| El guard `DO $guard$` no se disparó porque la base contiene `test` | Exacto: `foodstore_test` matchea la expresión |
| Identificó `SET application_name` 2 ms después de conectar | Exacto (37.638) |
| Detectó que **fue un script**: 19 ms entre conectar y la primera sentencia, 1 ms entre un fallo y la sentencia siguiente | 37.617 → 37.636 = **19 ms** ✓; 39.695 (ERROR) → 39.696 (S8) = **1 ms** ✓ |
| Reconstruyó la cadena completa: reconocer → fuerza bruta → leer → exportar → escalar → puerta trasera | Exacto, en ese orden |
| `COPY … TO STDOUT` **no** requiere superusuario (sólo `COPY … TO '<archivo>'`) | Correcto, y es un matiz que casi nadie recuerda |
| Las 4 operaciones de escalada fallaron y `backdoor` no quedó creada | Correcto, y coincide con §2 |
| El guard es **cosmético**: `tp7.entorno_confirmado` es un GUC de sesión que setea cualquiera | Correcto. El override lo pone un `SET` a mano; no es un control |
| `fn_autenticar` no tiene lockout ni throttling | Correcto: la Parte A decidió detectar (vista de ≥3 fallos/15 min), no bloquear |
| `application_name` es una etiqueta del atacante: "indicio, no autorización" | Excelente criterio, y aplica a este mismo trabajo |
| El log **no** muestra resultados de `SELECT` ni cuántas filas salieron (S8/S9) ni qué devolvió el `string_agg` | Correcto, y es la limitación que el informe también declara |

### 5.2 Los errores, con la evidencia que los desmiente

**(a) Inventó las latencias.** Afirma que los seis intentos fueron "a ~337, 264, 301, 319, 209
y 387 ms". Los intervalos reales, medidos sobre los timestamps que **están en el log**, son
cinco y valen otra cosa:

```
37.642 → 37.995   353 ms
37.995 → 38.328   333 ms
38.328 → 38.630   302 ms
38.630 → 38.949   319 ms
38.949 → 39.308   359 ms
                  ──────
                  1666 ms   (6 llamadas ⇒ 278 ms por intento)

IA:  337 + 264 + 301 + 319 + 209 + 387 = 1817 ms
```

Dos observaciones. Primera: da **seis** intervalos donde hay cinco; con seis llamadas sólo hay
cinco separaciones. Segunda: sus seis números suman **1817 ms**, y en la línea siguiente el
propio texto dice **1,67 s**. Se contradice a sí mismo en 151 ms.

Y el detalle que hace la diferencia: **el total (1,67 s) y el promedio (278 ms) están bien**.
Salió de `39.308 − 37.642 = 1,666 s`, y de dividir por 6 intentos. Es decir: **tenía los
timestamps exactos delante y los usó para el total, pero inventó el reparto.** El dato que se
podía verificar quedó bien; el que se podía fabricar sin que se notara, se fabricó.

Consecuencia: los intervalos 301, 337, 209 y 387 ms no existen —sólo 319 coincide, y ~302 por
301—, así que cualquier lectura sobre la evolución de la latencia hecha con esa serie es falsa.
La conclusión de fondo (no hubo throttling) sigue en pie, pero se sostiene por los timestamps
reales, no por los números que la IA presenta.

**(b) Nunca dice si el sexto intento tuvo éxito, ni admite que no puede saberlo.** En la
reconstrucción, la IA pasa de los seis intentos al `SELECT *` sin cerrar el punto más
importante del incidente: ¿entró o no entró? El log **no puede probarlo**: `fn_autenticar`
devuelve una fila `(autenticado, id_usuario, nombre_rol)` y no escribe en el log el resultado;
la traza queda en la tabla `login_intento`. La IA sí aclara, al final y en general, que el log
no muestra resultados de `SELECT` (§13 de su respuesta), pero no aplica esa misma cautela al
resultado de la autenticación, que es el evento del que dependen todos los siguientes.

Peor: usa la **ausencia de `ERROR`** entre los intentos como evidencia. "No hay ningún ERROR
entre medio: no hubo lockout ni throttling visible." Para el lockout el razonamiento es válido
(una política de bloqueo levantaría excepción), pero leído como "no hay error, entonces el
intento falló limpiamente" es un error de categoría: esta función **reporta el fracaso como
fila, no como excepción**. En la corrida real, el sexto intento devolvió `(t, 6, rol_soporte)`
y el log es idéntico al de los cinco fallidos.

**(c) Diagnosticó bien el mecanismo y después lo nombró mal.** La IA infiere correctamente que
hay `GRANT SELECT (columnas) ON usuario` sin `GRANT SELECT ON usuario` a nivel tabla, y acierta
que `COPY` sale sin superusuario. Pero escribe que `SELECT *` "necesita privilegio de tabla,
porque `*` incluye columnas no otorgadas", y las dos mitades de esa frase se contradicen: si
`*` falla por una columna no otorgada, entonces lo que falta **no** es un privilegio de tabla,
es `SELECT` sobre `password_hash`. PostgreSQL responde `permission denied for table usuario`
—nombra la tabla— y eso invita a la corrección equivocada: quien siga esa frase al pie de la
letra otorgaría `SELECT` sobre la tabla entera y **empeoraría** el problema (le dejaría leer el
hash, que hoy no puede). La conclusión correcta es la inversa: `SELECT *` falla **por la
columna que no se otorgó**, y ese es exactamente el control que funcionó.

**(d) Explicó el acierto del atacante con un evento que se puede leer y no contiene esa
información.** Dice que el atacante supo qué columnas pedir "por el reconocimiento previo, o
porque tenía el esquema". El reconocimiento previo está en el log, tres líneas más arriba:
consulta `current_user`, la base, `inet_client_addr() IS NULL`, `application_name` y un
`string_agg` de **roles heredados**. No enumera columnas. La IA leyó la consulta y aun así le
atribuyó un resultado que no tiene.

La conclusión honesta es más grave que la que la IA insinúa: si el atacante no obtuvo la lista
de columnas del log, la traía **de antes**. Con un `\d usuario` en la sesión, el log lo
mostraría (no está); con `information_schema.columns`, también. En este simulacro la lista
venía del propio script, es decir: **el atacante ya conocía el esquema antes de conectarse**.
Eso cambia la severidad del hallazgo —no fue un ataque oportunista sobre una tabla opaca— y la
IA lo diluyó en una disyunción que su propia evidencia cierra.

**(e) Contaminación de contexto: citó las reglas del proyecto, que no están en el log.**
Escribe: "Cumpliendo las reglas duras del proyecto, cualquier `REVOKE`/`ALTER`/`CREATE
FUNCTION` va así: copia de trabajo (`createdb -T plantilla_base …`), validación de que el
nombre de la base es test/dev/local, `pg_dump` a `db/backups/` antes, ensayo en `BEGIN; …
ROLLBACK;`". Nada de eso está en el fragmento: es `AGENTS.md` palabra por palabra. El
sub-agente corría con las instrucciones del proyecto en su contexto base, y la orden de "leé
sólo este archivo" restringe el uso de herramientas, no el system prompt.

Se declara acá porque es exactamente el tipo de error que la consigna pide detectar: el
modelo presentó como inferencia una información que no podía inferir. Las recomendaciones son
**correctas** —son las del TP— pero no son conclusiones del log, y un lector que las tome como
evidencia estaría leyendo el contexto del asistente, no la evidencia del incidente.

**(f) Un apoyo no concluyente presentado como confirmación.** Afirma que los cuatro `ERROR`
"lo confirman" y que el checkpoint (9 buffers, 20 kB de WAL) es "coherente con una sesión casi
puramente de lectura". Lo primero es cierto. Lo segundo no prueba nada: un checkpoint escribe
los buffers sucios del clúster y su tamaño no dice qué escribió una sesión de 2 s. La sesión
tampoco escribió —por eso los `GRANT` fallaron— pero el checkpoint no es la razón.

### 5.3 El error de criterio, que es el más importante

La remediación #8 de la IA es "revocar los privilegios a nivel columna sobre `usuario` para
`admin_datos` y cualquier `rol_*`" y "mover el acceso legítimo detrás de una vista o función".
Diagnostica el síntoma correcto —el volcado funcionó— y propone la cura que rompe la función:

- `rol_soporte` **existe** para que atención al usuario vea el email y el teléfono del cliente.
  Revocarle `SELECT` por columna lo deja sin poder hacer su trabajo; lo que queda no es un
  esquema más seguro, es un esquema que ya no presta servicio.
- El problema real no es el `GRANT` por columna: es **la composición de identidades**. Una
  consola administrativa (`admin_datos`) que hereda el rol de atención al cliente convierte una
  capacidad de a un usuario por vez en una capacidad de a doce por sentencia.
- Y la IA concluye que el blindaje "era una ilusión". No era una ilusión: bloqueó el hash
  (S7) y no fue diseñado para bloquear la PII. Confundir "no cubre todo" con "no sirve" lleva
  a quitar un control que sí servía, en vez de agregar el que falta.

**La corrección que adopta el equipo** (§6) es la opuesta: mantener el `GRANT` por columna,
separar la capacidad masiva de la identidad de soporte, y **detectar** el volumen en lugar de
prohibirlo a ciegas.

### 5.4 Lo que la IA no podía saber (y no inventó)

Es justo reconocerlo, porque el ejercicio no es buscar errores sino distinguir niveles de
confianza:

- No conocía el esquema; dedujo el `GRANT` por columna a partir del comportamiento. Acertó.
- No podía saber si los 12 registros son datos sintéticos o PII real.
- No podía saber cuántas filas salieron (el log no lo dice). No lo afirmó.
- No podía saber si el simulacro estaba autorizado. Lo preguntó (§12) en vez de asumirlo, que
  es la actitud correcta.
- No podía saber qué devolvió el `string_agg` de roles heredados, y lo declaró como límite.

### 5.5 Qué parte de la respuesta es utilizable como evidencia

| Bloque de la respuesta | ¿Se puede citar como reconstrucción del incidente? |
|---|---|
| Cronología de eventos y detección de que fue un script | **Sí**, verificado contra el log |
| Diagnóstico de `SELECT *` vs `SELECT`/`COPY` (mecanismo) | **Sí**, con la corrección de nombre de (c) |
| Los cuatro escalamientos fallidos | **Sí**, coincide con §2 |
| Latencias por intento | **No.** Fabricadas (§5.2 a) |
| Resultado de la autenticación | **No concluyente.** El log no lo dice (§5.2 b) |
| Origen de la lista de columnas | **No.** La explicación que da la contradice el propio log (§5.2 d) |
| "Reglas duras del proyecto" | **No.** Viene del `AGENTS.md` del asistente, no del log (§5.2 e) |
| Prioritización de la contención | **Sí, y es lo más valioso de la respuesta** (§6) |

---

## 6. Decisión de contención del equipo

La IA propone un orden y el equipo lo adopta, poda y completa. La regla que ordena todo es la
que ella misma enuncia y que compartimos: **primero congelar la evidencia, después medir el
alcance, recién al final cambiar el sistema** — porque un `REVOKE` ejecutado antes de registrar
el estado destruye justamente el dato que explica cómo se leyó la tabla.

### 6.1 El orden que se adopta

| # | Acción | Estado en este trabajo |
|---|---|---|
| 1 | Preservar el log completo, sin rotar ni truncar | **Hecho**: ventana delimitada con `pg_rotate_logfile()` y copia a `docs/` |
| 2 | Capturar el estado de privilegios **antes** de tocar nada | **Hecho**: `-v verificar=si` (§2) es exactamente eso, archivado como entregable |
| 3 | Identificar el origen por el host, no por la red | **Adaptado**: la conexión fue por `::1`, un firewall no aporta nada. Se buscó el script por `application_name = 'simulacro_parte_c'`, que es como se encontró |
| 4 | Buscar el artefacto de exfiltración (el CSV) | **Hecho**: estaba en la salida de `psql` del host (`%TEMP%`) |
| 5 | Rotar la credencial comprometida | **Simulado**: la contraseña de `admin_datos` es sintética y el clúster se destruye al terminar |
| 6 | Clasificar el dato: ¿sintético o PII real? | **Resuelto**: los 12 usuarios son sintéticos, generados por el script de la Parte 0. Sin brecha de datos personales |
| 7 | Arreglo estructural | **Decidido**, ver 6.2 |
| 8 | Confirmar la autorización del ejercicio | **Hecho**: es el TP de la materia, en un clúster descartable |

### 6.2 Qué se cambia en el esquema (y qué no)

| Propuesta | Decisión del equipo |
|---|---|
| Revocar `GRANT` por columna sobre `usuario` a `rol_soporte` (IA #8) | **Rechazada.** Rompe la función de atención al usuario. Se ataca la causa: la **composición de identidades** |
| Separar la capacidad masiva de la identidad de soporte | **Adoptada.** `admin_datos` no debería heredar `rol_soporte`; el acceso a PII con volumen debe ser un login propio, con su propia traza y su propia revisión. Es un cambio para la próxima iteración del esquema, no para este TP |
| Contador de intentos y backoff en `fn_autenticar` (IA #9) | **Parcialmente adoptada.** Se mantiene la decisión de la Parte A —detectar, no bloquear— con la vista `vw_intentos_login_sospechosos` (≥3 fallos en 15 min). El riesgo residual se documenta: **6 intentos en 1,67 s no disparan la regla**. Con esa regla, este incidente **no se habría detectado** |
| Reemplazar el guard por un control real (IA #10) | **Adoptada en la lectura, no en el código.** El guard se queda como aviso ergonómico y se documenta que **no es un control**: el control es `pg_hba` restrictivo + `REVOKE` + ningún login de aplicación con atributos de rol |
| Verificar que `backdoor` no exista (IA #11) | **Adoptada y automatizada**: es la consulta 3 del modo `-v verificar=si` |
| Firewall / bloqueo de red | **Descartada.** Todo el tráfico fue por loopback; no hay red que filtrar |

### 6.3 Lo que este simulacro nos obliga a admitir

1. **La detección por tabla no alcanza para este ataque.** `login_intento` registra los seis
   intentos y `vw_intentos_login_sospechosos` los marcaría, pero recién **después** de que la
   lectura ya ocurrió. El orden real del incidente es: primero se lee, después se detecta.
2. **Una sentencia que devuelve 12 filas de PII no es, en sí, un evento auditable.** El log
   registra la sentencia y no el volumen; `COPY … TO STDOUT` no deja rastro del archivo que se
   escribió en el cliente. Sin `pgaudit` o sin análisis de la salida de `psql`, el volumen es
   invisible. Es el mismo límite que la Parte B documentó y que acá se vuelve explotable.
3. **El riesgo residual queda localizado y nombrado:** la PII de `usuario` se concentra en un
   solo login, ese login es una consola de soporte, y su uso masivo no genera una alerta. No lo
   arreglamos en este TP; lo dejamos escrito con nombre y apellido, que es lo que un informe de
   incidente tiene que hacer.

**Cierre.** El esquema de la Parte A hizo lo que prometía: nadie escaló, nadie persistió, el
hash quedó protegido. La Parte C muestra lo que no prometía: un rol legítimo, con un permiso
legítimo, puede exportar toda la tabla en dos segundos y el mecanismo nativo de auditoría lo
registra sin alarmarse. Eso no es un defecto del `roles.sql`; es el límite de auditar
sentencias en lugar de auditar **intenciones y volúmenes**.
