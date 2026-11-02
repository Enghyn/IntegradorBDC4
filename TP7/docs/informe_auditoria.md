# Informe de auditoría de servidor — Parte B

> **TP — Unidad 5: Administración y seguridad de Food Store**
> PostgreSQL 17.11 · base `foodstore_test` · **entorno de desarrollo**
>
> Archivos de esta parte:
> - `sql/auditoria_test.sql` — secuencia de prueba ejecutada.
> - `docs/log_auditoria_prueba.txt` — fragmento de log capturado.
> - `docs/informe_auditoria.md` — este informe.

---

## 1. Configuración aplicada

Los cambios se aplicaron con `ALTER SYSTEM` (escriben `postgresql.auto.conf`), no editando
`postgresql.conf` a mano. La razón es de auditoría: `ALTER SYSTEM` queda en el historial de
la sesión y es consultable desde SQL, mientras que una edición manual del archivo no deja
rastro de quién la hizo.

```sql
ALTER SYSTEM SET logging_collector          = on;
ALTER SYSTEM SET log_destination            = 'csvlog,stderr';
ALTER SYSTEM SET log_directory              = 'log';
ALTER SYSTEM SET log_filename               = 'postgresql-%Y-%m-%d_%H%M%S.log';
ALTER SYSTEM SET log_rotation_age           = '1d';
ALTER SYSTEM SET log_rotation_size          = '10MB';
ALTER SYSTEM SET log_file_mode              = '0640';
ALTER SYSTEM SET log_line_prefix            = '%m [%p] %q%u@%d/%a host=%h ';
ALTER SYSTEM SET log_connections            = on;
ALTER SYSTEM SET log_disconnections         = on;
ALTER SYSTEM SET log_statement              = 'all';
ALTER SYSTEM SET log_min_duration_statement = -1;
ALTER SYSTEM SET log_error_verbosity        = 'default';
ALTER SYSTEM SET log_timezone               = 'America/Argentina/Buenos_Aires';
ALTER SYSTEM SET log_parameter_max_length   = 0;   -- hallazgo H2, ver § 4
```

`logging_collector` exige **reinicio** del servidor; el resto se aplica con
`SELECT pg_reload_conf();`.

El mismo bloque está en `sql/auditoria_test.sql` § 0, detrás de una guarda
(`-v aplicar_config=si`) para que el script sea autocontenido sin permitir que un rol de
aplicación reconfigura el motor: sin esa variable, el script sólo verifica y prueba.

### 1.1 Por qué cada parámetro

| Parámetro | Valor previo | Valor nuevo | Para qué |
|---|---|---|---|
| `logging_collector` | `off` | `on` | Sin esto el servidor escribe a la consola del servicio y no hay archivo. Además **`csvlog` lo exige**: la consigna pedía explícitamente tenerlo en cuenta. |
| `log_destination` | `stderr` | `csvlog,stderr` | `csvlog` da un archivo estructurado (una fila por evento, campos fijos) que se puede cargar con `COPY` y consultar con SQL. `stderr` es el texto legible para el fragmento del informe. Los dos, no uno. |
| `log_directory` / `log_filename` | `log` / `postgresql-%Y-%m-%d_%H%M%S.log` | igual | Con el patrón con segundos, cada rotación produce un nombre distinto y la ventana de captura queda delimitada por archivo. |
| `log_rotation_age` / `_size` | `1d` / `10MB` | igual | La rotación acota el daño de un disco lleno y hace manejable la retención. |
| `log_file_mode` | `0640` | `0640` | En Unix, los logs no deben ser legibles por cualquiera (ver § 5). **En Windows este parámetro se ignora**: ahí manda la ACL NTFS del directorio. |
| `log_line_prefix` | `%m [%p]` | `%m [%p] %q%u@%d/%a host=%h ` | Es el cambio más importante. Con el prefijo por defecto, una línea de log **no dice quién** la generó: hay que reconstruirlo cruzando el PID con otras líneas. Con `%u@%d/%a host=%h` cada línea se explica sola (§ 3). |
| `log_connections` | `off` | `on` | Registra el establecimiento de sesión: es la única evidencia de *desde dónde* y de los intentos **rechazados**. |
| `log_disconnections` | `off` | `on` | Cierra el par: permite saber cuánto duró una sesión y detectar una conexión que quedó abierta (posible sesión olvidada o robada). |
| `log_statement` | `none` | `all` | Es el mínimo que registra modificaciones (`mod`), pero la consigna también pide **una lectura**, y la Parte C necesita ver una lectura masiva. `all` cubre las dos. El costo se analiza en § 6. |
| `log_min_duration_statement` | `-1` | `-1` | Ya se registra toda sentencia; activarlo duplicaría cada línea. |
| `log_error_verbosity` | `default` | `default` | Suficiente: incluye `DETAIL` y `STATEMENT`. |
| `log_timezone` | `America/Buenos_Aires` | igual | Se fija explícitamente para que la hora del log sea la del equipo y no dependa del `timezone` de configuración. |
| `log_parameter_max_length` | `-1` | `0` | **No** es de la Clase 1: se agregó por el hallazgo H2 (§ 4). Con `0` no se escriben los valores de los parámetros; la sentencia sí queda registrada. |

### 1.2 Verificación de que quedó aplicado

`pg_settings.source` debe decir `configuration file`; si sigue en `default`, el cambio no
se aplicó (o falta el reinicio). Salida real, como superusuario (14 de 14):

```
            name            |            setting             | unit |       source
----------------------------+--------------------------------+------+------------------
 log_connections            | on                             |      | configuration file
 log_destination            | csvlog,stderr                  |      | configuration file
 log_directory              | log                            |      | configuration file
 log_disconnections         | on                             |      | configuration file
 log_file_mode              | 0640                           |      | configuration file
 log_filename               | postgresql-%Y-%m-%d_%H%M%S.log |      | configuration file
 log_line_prefix            | %m [%p] %q%u@%d/%a host=%h     |      | configuration file
 log_min_duration_statement | -1                             | ms   | configuration file
 log_parameter_max_length   | 0                              | B    | configuration file
 log_rotation_age           | 1440                           | min  | configuration file
 log_rotation_size          | 10240                          | kB   | configuration file
 log_statement              | all                            |      | configuration file
 log_timezone               | America/Argentina/Buenos_Aires |      | configuration file
 logging_collector          | on                             |      | configuration file
(14 rows)
```

Dos advertencias de método, porque las dos se prestan a confusión:

1. **Corriendo como rol no superusuario se ven 12, no 14.** `pg_settings` oculta los
   parámetros `SUSET`, y `log_directory` / `log_filename` lo son. `sql/auditoria_test.sql` se
   ejecuta como `app_web`, así que su bloque de verificación muestra 12 filas: es correcto, no
   es un fallo de configuración.
2. **`pg_file_settings` puede devolver filas con `applied = false` sin que haya error.** El
   `postgresql.conf` del clúster ya traía `log_file_mode` y `log_timezone` descomentados, y
   además se fijaron por `ALTER SYSTEM`. Al quedar duplicados, PostgreSQL aplica el **último**
   archivo leído (`postgresql.auto.conf`) y marca la copia anterior como no aplicada, con
   `error` vacío. La consulta correcta es la que distingue los dos casos:
   `SELECT count(*) FROM pg_file_settings WHERE applied = false AND error IS NOT NULL;` → `0`.
   Antes del reinicio devolvía `1` (`logging_collector`: *setting could not be applied*), lo
   que confirma que ese cambio exigía reinicio y no sólo recarga.

---

## 2. Secuencia de prueba y captura

**Datos de prueba.** El esquema del proyecto no trae datos (los carga el benchmark del TP3).
Para que la inserción y la actualización tuvieran sobre qué operar se cargó, como `postgres`,
un fixture mínimo y sintético:

```sql
INSERT INTO cliente (nombre, email, telefono)
VALUES ('Cliente Prueba Auditoria', 'cliente.prueba@foodstore.test', '+54 11 4555-0199');

INSERT INTO categoria (nombre) VALUES ('Almacen');

INSERT INTO producto (id_categoria, nombre, precio_lista, stock)
SELECT c.id_categoria, v.nombre, v.precio, v.stock
FROM (VALUES ('Yerba Mate 1kg', 1500.00, 50),
             ('Cafe Molido 500g', 3200.00, 30)) AS v(nombre, precio, stock)
JOIN categoria c ON c.nombre = 'Almacen';
```

**Ejecución.** La secuencia (`sql/auditoria_test.sql`) se corrió con la identidad de la
aplicación:

```
psql "host=localhost port=5544 dbname=foodstore_test user=app_web" -f TP7/sql/auditoria_test.sql
```

Se eligió `app_web` y no `postgres` con `SET ROLE` por una razón concreta: el log registra
en `%u` al usuario de la **sesión**, no al rol efectivo. Corriendo como `postgres`, el
fragmento diría `postgres` en todas las líneas y no probaría nada sobre "quién".

Para que el rechazo del motor fuera real (y no simulado en la aplicación) se agregó en
`pg_hba.conf`, **antes** de las líneas `trust`, la exigencia de SCRAM para `app_web`, y una
contraseña sintética asignada a mano — fuera del repositorio, según el requisito 9 de la
Parte A:

```
host    all    app_web    127.0.0.1/32    scram-sha-256
host    all    app_web    ::1/128         scram-sha-256
```

**Captura.** La ventana se delimitó con dos rotaciones:

```sql
SELECT pg_rotate_logfile();   -- abre la ventana
-- ... prueba ...
SELECT pg_rotate_logfile();   -- la cierra
```

Así el archivo capturado contiene exactamente la prueba. El fragmento está en
`docs/log_auditoria_prueba.txt` (61 líneas de log —93 con la cabecera explicativa—,
20:47:04.460 → 20:47:10.295 -03), con una cabecera que explica qué se omitió: solo las dos
sesiones de DBA que rotaron el log.

**Resultado.** La secuencia se comportó como estaba previsto:

| Paso | Operación | Resultado |
|---|---|---|
| B1 | lectura de catálogo | 2 filas |
| B2 | `INSERT` en `pedido` + `detalle_pedido` | `INSERT 0 1` / `INSERT 0 1` |
| B3 | `UPDATE producto SET stock = stock - 2` | `UPDATE 1` (stock 50 → 48) |
| B4 | `fn_autenticar` × 3 con clave incorrecta | 3 × `(f, NULL, NULL)` y 3 filas en `login_intento` |
| B5 | `SELECT * FROM usuario` | `ERROR: permission denied for table usuario` |
| B6 | `GRANT admin_datos TO app_web` | `ERROR: permission denied to grant role "admin_datos"` |
| B8/B9 | leer `login_intento` / la vista | `ERROR: permission denied` (la app no lee trazas) |

`vw_intentos_login_sospechosos` devolvió exactamente una fila:
`maria.gonzalez@foodstore.test | 3 fallos | 0 éxitos | 0.65 s entre el primero y el último`
(20:47:09.308 → 20:47:09.955).
Es decir: **la Parte C ya tiene su evidencia lista para ser detectada.**

---

## 3. Qué información del fragmento sirve para auditar

Cada línea del fragmento responde, por sí sola, a las cuatro preguntas clásicas:

| Pregunta | De dónde sale | Ejemplo del fragmento |
|---|---|---|
| **Quién** | `%u` + `%d` | `app_web@foodstore_test`; `[unknown]` en un intento que nunca llegó a autenticarse |
| **Qué** | texto del `statement` / `execute` y del `ERROR` | `statement: UPDATE producto SET stock = stock - 2 WHERE id_producto = 1;` |
| **Cuándo** | `%m` (milisegundos) | `2026-11-01 20:47:09.304 -03` |
| **Desde dónde** | `host=%h` | `host=::1` (y `port=` en la línea de conexión) |

Además, `%a` y `%p` agregan **en qué contexto**: `%a = tp7_parte_b` aísla la prueba del
resto de la actividad sin depender de la hora, y `%p` agrupa todas las líneas de una misma
sesión aunque se intercalen con otras.

### Lo que el mecanismo nativo **no** da

1. **Filas afectadas.** El log dice que se ejecutó `SELECT * FROM usuario` o
   `UPDATE producto ...`, pero **no** cuántas filas devolvió ni cuáles. Para la Parte C eso
   es justo lo que importa: la evidencia dice "hubo una lectura a `usuario`", no "se
   exfiltraron 12 usuarios". Ese detalle lo daría `pgaudit` con `pgaudit.log = 'read, write'`
   (una entrada por sentencia, con el objeto), y ni siquiera pgaudit da los valores fila por
   fila: para eso hace falta un trigger de auditoría o CDC.
2. **Rol efectivo.** `%u` es el usuario de la sesión. Si la aplicación hace `SET ROLE`,
   el log sigue mostrando la identidad de conexión. Se mitiga con una identidad de sesión
   por función (como se hizo acá) o con `pgaudit`.
3. **Resultado de la autorización a nivel fila.** Con RLS, una sentencia puede correr
   "bien" devolviendo cero filas por política; el log no distingue eso de una tabla vacía.
4. **Integridad de la evidencia.** El log es un archivo de texto: quien tenga permiso de
   escritura sobre el directorio lo edita y no queda rastro. No es *tamper-evident*; por eso
   se complementa con la traza en tabla (`login_intento`, `usuario_auditoria`) y se recomienda
   enviarlo fuera del servidor (§ 6).
5. **Consultabilidad.** El log no se consulta con `WHERE` a menos que se cargue el CSV.
   Nuestra traza en tabla existe precisamente para eso: la Parte C se resuelve con una
   consulta, y el log queda como evidencia de respaldo.

---

## 4. Hallazgos de la prueba (lo que no estaba en la consigna)

**H1 — `log_statement = all` escribe credenciales en claro en el log.**
En el fragmento (líneas 64–66) se leen las tres contraseñas fallidas completas:
`fn_autenticar('maria.gonzalez@foodstore.test', 'clave_incorrecta_auditoria')`. No es un
error de la prueba: es lo que hace el parámetro. Con `log_statement = 'all'` (o `'mod'`), un
`ALTER ROLE ... PASSWORD '...'` ejecutado por el DBA también queda escrito tal cual. Es la
primera razón por la que el log es un activo sensible (§ 5).

**H2 — Parametrizar la consulta *no* evita H1.** Se probó con protocolo extendido
(`\bind`), que es lo que hace un driver real:

```
LOG:  execute <unnamed>: SELECT * FROM fn_autenticar($1, $2)
DETAIL:  Parameters: $1 = 'maria.gonzalez@foodstore.test', $2 = 'ClaveSecretaParametrizada#2026'
```

El valor viaja en el `DETAIL`, igual que antes. La mitigación real es
`log_parameter_max_length = 0`, que se aplicó y se verificó: la línea `DETAIL` desaparece y
la sentencia sigue registrada. Es una buena noticia para la norma de `AGENTS.md` de usar
siempre consultas preparadas —pero por *inyección*, no por *auditoría*—: son dos problemas
distintos que se arreglan con dos medidas distintas.

> El valor que aparece arriba es una cadena descartable usada una sola vez contra el clúster
> temporal de este TP, que se destruyó al terminar. No es la contraseña de ningún usuario ni
> de ningún sistema que sobreviva; se muestra porque es exactamente lo que el log escribió.

**H3 — El prefijo por defecto no identifica al usuario.** Con `%m [%p]` (valor de fábrica),
saber quién ejecutó algo obliga a correlacionar el PID con la línea de conexión. Si la
conexión se recicla (pooling), esa correlación se vuelve ambigua. `%u@%d` lo resuelve en la
misma línea.

**H4 — `csvlog` no reemplaza al texto.** El CSV es el que se puede cargar y consultar, pero
la consigna pide "capturar el fragmento" y un CSV de 40 columnas no se lee. Se configuraron
los dos destinos a propósito.

**H5 — Un valor duplicado entre `postgresql.conf` y `postgresql.auto.conf` parece "no
aplicado".** Es el error de diagnóstico más fácil de cometer al verificar: `pg_file_settings`
devuelve `applied = false` para la copia que quedó tapada por el archivo leído después, **sin
error**. Si se usa esa vista como semáforo, parece que la configuración falló cuando en
realidad está aplicada dos veces. Además, `pg_settings` **oculta a los roles no superusuario**
los parámetros `SUSET` (`log_directory`, `log_filename`): verificar como `app_web` muestra 12
filas de 14 y no es un problema. La verificación honesta es `pg_settings.source` +
`pg_file_settings.error IS NOT NULL` (§ 1.2).

---

## 5. ¿El archivo de log es un activo sensible? (punto 4 de la consigna)

**Sí, y de los más sensibles del sistema.** No es telemetría operativa: es una copia
paralela y no gobernada de la actividad de la base. En nuestro propio fragmento hay
direcciones de correo de usuarios, la estructura interna del esquema (`GRANT admin_datos TO
app_web`) y **contraseñas en texto plano** (H1); en una base con datos reales contendría
PII de clientes dentro de los `INSERT`, y con `log_statement = 'all'` cualquier secreto que
alguna vez se haya pasado por una sentencia. Además, quien pueda editarlo puede borrar su
propio rastro: es evidencia *y* es el punto donde se rompe la evidencia.

**Quién debería poder leerlo.**

| Actor | Acceso | Fundamento |
|---|---|---|
| DBA / servicio de PostgreSQL | lectura y escritura (es el dueño del directorio) | Es quien lo produce; sin escritura no hay logging. |
| Auditoría / seguridad | **solo lectura**, por grupo | Necesita la evidencia completa, no muestras ni resúmenes. |
| Desarrolladores, soporte, roles de aplicación | **ninguno** | No lo necesitan para operar, y verlo les daría PII y credenciales de otros. `app_web` no puede leerlo ni por SQL ni por sistema de archivos. |
| Asistente de IA / herramientas externas | solo fragmentos **anonimizados** | Mismo criterio de la Parte C y de `usuario_anon`. |

**Con qué permisos.**

- **Sistema operativo (Unix):** directorio propiedad de la cuenta del servicio
  (`postgres`), modo `0700`; archivos `0640` con un grupo tipo `pglog` que solo integra el
  equipo de auditoría. Nada de `0666` ni de directorios dentro de un docroot web.
- **Sistema operativo (Windows):** la ACL NTFS manda (`log_file_mode` no aplica): solo la
  cuenta del servicio con control total, el grupo de auditoría con lectura, y herencia
  deshabilitada para que no se propague a subcarpetas nuevas.
- **Motor:** `pg_read_file()` y `pg_ls_dir()` están limitados a superusuario o a
  `pg_read_server_files`; ese privilegio **no** debe otorgarse a ningún rol de aplicación
  (en la Parte A ninguno lo tiene). `log_directory` no puede estar por encima del directorio
  de datos ni ser escribible por otros procesos.
- **Repositorio:** el log no se versiona. Es la razón por la que `docs/log_auditoria_prueba.txt`
  es un fragmento acotado y de un entorno sintético, y no un archivo de producción.
- **Retención:** rotación diaria/10 MB y envío a un colector externo con retención definida y
  permisos propios; el archivo local no es un archivo de auditoría a largo plazo.

---

## 6. Costo de la configuración y qué cambiaría en producción

`log_statement = 'all'` es correcto para un entorno de desarrollo y **no** para producción:

| Parámetro | Dev (esta entrega) | Producción | Motivo |
|---|---|---|---|
| `log_statement` | `all` | `mod` | Con `all`, cada lectura multiplica el volumen y escribe PII en disco. Las lecturas se auditan con `pgaudit` (`read`), que registra la sentencia sin volcar el resultado. |
| `log_parameter_max_length` | `0` | `0` | Sin esto, las credenciales quedan en el log (H1/H2). |
| `log_connections` / `log_disconnections` | `on` | `on` | Costo despreciable y es la única evidencia de intentos rechazados. |
| `log_min_duration_statement` | `-1` | `200ms` | Para performance no para auditoría: solo las consultas lentas. |
| `pgaudit` | no instalado | `pgaudit.log = 'read, write, ddl'` | Es el salto de "se ejecutó una sentencia" a "se accedió a este objeto", y permite cumplir requisitos que el log nativo no cubre. |
| Colector externo | no | sí | La evidencia tiene que salir del host que audita. |

**Conclusión.** La auditoría nativa alcanza para reconstruir *quién hizo qué, cuándo y desde
dónde* a nivel de sentencia —y eso ya permitió detectar la fuerza bruta de la Parte C con una
consulta— pero no responde cuántas filas ni cuáles, no es a prueba de manipulación y, mal
configurada, **se convierte ella misma en una fuga de credenciales**. Las tres cosas quedan
demostradas con evidencia de este entorno, no con afirmaciones.
