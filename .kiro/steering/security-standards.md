---
inclusion: always
---
# Normas de seguridad del proyecto
- Nunca hardcodear contraseñas, tokens ni claves de API en el código.
  Todo secreto va en `.env`, que está en `.gitignore`.
- Validar y sanitizar todo input que venga del usuario antes de
  usarlo en una consulta SQL (usar parámetros, nunca concatenar strings).
- Las contraseñas de usuarios se guardan siempre hasheadas (bcrypt/argon2),
  nunca en texto plano.
- No exponer mensajes de error de la base de datos directamente al cliente.

---

## Reglas CRÍTICAS de operación segura sobre la base de datos (protocolo obligatorio)

1. **Siempre trabajar sobre una base de desarrollo o copia de trabajo, nunca sobre la base con datos que importan o producción.**
   - Crear la copia de trabajo con: `createdb -T plantilla_base copia_trabajo`
   - Confirmar que toda conexión apunta a esta base antes de ejecutar cualquier script.

2. **Ejecución cautelosa con transacción y rollback para inspección previa.**
   - TODO script que modifica datos debe ejecutarse PRIMERO dentro de:
     ```
     BEGIN;
     -- operaciones
     ROLLBACK;
     ```
   - Sólo si el efecto es el esperado (filas, mensajes, sin errores), repetir con COMMIT.

3. **Backup (pg_dump) de la base ANTES de cambios estructurales.**
   - Antes de cualquier ALTER, DROP, o migración:
     `pg_dump -U usuario -d copia_trabajo > db/backups/backup_PRECAMBIO.sql`
   - Así puede revertirse el estado incluso si el ROLLBACK no cubre todo.

