-- Migracion de reglas de negocio adicionales (Actualizada con Regla 3)
BEGIN;

-- 1. Validacion de formato de email en cliente (si ya existe, DROP preventivo o CREATE IF NOT EXISTS simulado)
DO $$ 
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.table_constraints 
        WHERE constraint_name = 'chk_cliente_email_formato' AND table_name = 'cliente'
    ) THEN
        ALTER TABLE cliente 
        ADD CONSTRAINT chk_cliente_email_formato 
        CHECK (email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$');
    END IF;
END $$;

-- 2. Trigger para asegurar que un producto pertenezca a una categoria activa (Regla 2)
CREATE OR REPLACE FUNCTION fn_check_producto_categoria_activa()
RETURNS TRIGGER AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM categoria 
        WHERE id_categoria = NEW.id_categoria AND activo = TRUE
    ) THEN
        RAISE EXCEPTION 'Regla violada: No se puede asociar un producto a una categoria inactiva o inexistente.';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_valida_categoria_activa ON producto;
CREATE TRIGGER trg_valida_categoria_activa
BEFORE INSERT OR UPDATE ON producto
FOR EACH ROW
EXECUTE FUNCTION fn_check_producto_categoria_activa();

-- 3. Trigger para impedir desactivar una categoria que cuenta con productos activos (Regla 3)
CREATE OR REPLACE FUNCTION fn_check_categoria_puede_desactivarse()
RETURNS TRIGGER AS $$
BEGIN
    -- Si se intenta cambiar 'activo' de TRUE a FALSE
    IF OLD.activo = TRUE AND NEW.activo = FALSE THEN
        IF EXISTS (
            SELECT 1 FROM producto 
            WHERE id_categoria = NEW.id_categoria AND activo = TRUE
        ) THEN
            RAISE EXCEPTION 'Regla violada: No se puede desactivar la categoria porque tiene productos activos asociados.';
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_valida_categoria_desactivacion ON categoria;
CREATE TRIGGER trg_valida_categoria_desactivacion
BEFORE UPDATE ON categoria
FOR EACH ROW
EXECUTE FUNCTION fn_check_categoria_puede_desactivarse();

COMMIT;
