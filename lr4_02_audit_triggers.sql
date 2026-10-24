
SET search_path TO app, ref, audit, stg, public;
SET ROLE app_owner;

DO $$
BEGIN
    RAISE NOTICE 'LR4: Создание таблицы аудита изменений и триггеров';
END $$;

-- =====================================================
-- Создание таблицы audit.row_change_log
-- =====================================================

CREATE TABLE IF NOT EXISTS audit.row_change_log (
    log_id BIGSERIAL PRIMARY KEY,
    change_time TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    changed_by VARCHAR(100) NOT NULL,
    table_schema VARCHAR(100) NOT NULL,
    table_name VARCHAR(100) NOT NULL,
    operation_type VARCHAR(10) NOT NULL CHECK (operation_type IN ('INSERT', 'UPDATE', 'DELETE')),
    record_id INTEGER,
    old_values JSONB,
    new_values JSONB,
    changed_fields TEXT[],
    client_ip INET,
    session_info JSONB
);

-- Индексы для быстрого поиска
CREATE INDEX IF NOT EXISTS idx_row_change_log_time ON audit.row_change_log(change_time);
CREATE INDEX IF NOT EXISTS idx_row_change_log_table ON audit.row_change_log(table_schema, table_name);
CREATE INDEX IF NOT EXISTS idx_row_change_log_user ON audit.row_change_log(changed_by);
CREATE INDEX IF NOT EXISTS idx_row_change_log_operation ON audit.row_change_log(operation_type);
CREATE INDEX IF NOT EXISTS idx_row_change_log_record ON audit.row_change_log(table_schema, table_name, record_id);

-- Комментарии
COMMENT ON TABLE audit.row_change_log IS 
'Журнал изменений строк в критичных таблицах. Записывает кто, что, когда изменил с маскированием чувствительных полей.';

COMMENT ON COLUMN audit.row_change_log.old_values IS 'Старые значения (чувствительные поля замаскированы/хэшированы)';
COMMENT ON COLUMN audit.row_change_log.new_values IS 'Новые значения (чувствительные поля замаскированы/хэшированы)';
COMMENT ON COLUMN audit.row_change_log.changed_fields IS 'Список изменённых полей';

-- =====================================================
-- Функция маскирования чувствительных данных
-- =====================================================

CREATE OR REPLACE FUNCTION audit.mask_sensitive_data(data JSONB, table_name TEXT)
RETURNS JSONB
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    result JSONB;
    key TEXT;
    value TEXT;
    masked_value TEXT;
BEGIN
    result := data;
    
    IF data IS NULL THEN
        RETURN NULL;
    END IF;
    
    -- Маскирование для разных таблиц
    CASE table_name
        WHEN 'app.actors' THEN
            -- Маскируем паспортные данные и ИНН
            IF result ? 'passport_data' THEN
                value := result->>'passport_data';
                IF value IS NOT NULL AND length(value) > 0 THEN
                    masked_value := '***' || right(value, 4);
                    result := result || jsonb_build_object('passport_data', masked_value);
                END IF;
            END IF;
            
            IF result ? 'tax_id' THEN
                value := result->>'tax_id';
                IF value IS NOT NULL AND length(value) > 0 THEN
                    masked_value := '***' || right(value, 2);
                    result := result || jsonb_build_object('tax_id', masked_value);
                END IF;
            END IF;
            
        WHEN 'app.contracts' THEN
            -- Хэшируем salary_amount и terms
            IF result ? 'salary_amount' THEN
                value := result->>'salary_amount';
                IF value IS NOT NULL THEN
                    -- Используем MD5 хэш для конфиденциальных данных
                    masked_value := 'HASH:' || md5(value || 'salt_contract_salary');
                    result := result || jsonb_build_object('salary_amount', masked_value);
                END IF;
            END IF;
            
            IF result ? 'terms' THEN
                value := result->>'terms';
                IF value IS NOT NULL AND length(value) > 0 THEN
                    -- Маскируем условия контракта
                    masked_value := '***CONFIDENTIAL***';
                    result := result || jsonb_build_object('terms', masked_value);
                END IF;
            END IF;
            
        WHEN 'app.projects' THEN
            -- Маскируем client_contacts и budget
            IF result ? 'client_contacts' THEN
                value := result->>'client_contacts';
                IF value IS NOT NULL AND length(value) > 0 THEN
                    masked_value := '***INTERNAL***';
                    result := result || jsonb_build_object('client_contacts', masked_value);
                END IF;
            END IF;
            
            IF result ? 'budget' THEN
                value := result->>'budget';
                IF value IS NOT NULL THEN
                    masked_value := 'HASH:' || md5(value || 'salt_project_budget');
                    result := result || jsonb_build_object('budget', masked_value);
                END IF;
            END IF;
            
        ELSE
            -- Для других таблиц не маскируем
            NULL;
    END CASE;
    
    RETURN result;
END;
$$;

-- =====================================================
-- Функция логирования изменений строк
-- =====================================================

CREATE OR REPLACE FUNCTION audit.log_row_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = audit, public
AS $$
DECLARE
    old_data JSONB;
    new_data JSONB;
    changed_fields TEXT[];
    record_id_val INTEGER;
    table_full_name TEXT;
BEGIN
    table_full_name := TG_TABLE_SCHEMA || '.' || TG_TABLE_NAME;
    
    -- Определяем ID записи (универсальный подход через JSONB)
    CASE TG_OP
        WHEN 'DELETE' THEN
            old_data := to_jsonb(OLD);
            new_data := NULL;
            -- Получаем ID из JSONB (пробуем разные варианты имён полей)
            record_id_val := COALESCE(
                (old_data->>'project_id')::INTEGER,
                (old_data->>'contract_id')::INTEGER,
                (old_data->>'actor_id')::INTEGER
            );
            
        WHEN 'UPDATE' THEN
            old_data := to_jsonb(OLD);
            new_data := to_jsonb(NEW);
            -- Получаем ID из JSONB
            record_id_val := COALESCE(
                (new_data->>'project_id')::INTEGER,
                (new_data->>'contract_id')::INTEGER,
                (new_data->>'actor_id')::INTEGER
            );
            
            -- Определяем изменённые поля
            SELECT ARRAY(
                SELECT key 
                FROM jsonb_each(old_data) 
                WHERE value IS DISTINCT FROM (new_data->key)
            ) INTO changed_fields;
            
        WHEN 'INSERT' THEN
            old_data := NULL;
            new_data := to_jsonb(NEW);
            -- Получаем ID из JSONB
            record_id_val := COALESCE(
                (new_data->>'project_id')::INTEGER,
                (new_data->>'contract_id')::INTEGER,
                (new_data->>'actor_id')::INTEGER
            );
    END CASE;
    
    -- Маскируем чувствительные данные
    old_data := audit.mask_sensitive_data(old_data, table_full_name);
    new_data := audit.mask_sensitive_data(new_data, table_full_name);
    
    -- Записываем в лог
    INSERT INTO audit.row_change_log (
        changed_by,
        table_schema,
        table_name,
        operation_type,
        record_id,
        old_values,
        new_values,
        changed_fields,
        client_ip,
        session_info
    ) VALUES (
        current_user::VARCHAR(100),
        TG_TABLE_SCHEMA,
        TG_TABLE_NAME,
        TG_OP,
        record_id_val,
        old_data,
        new_data,
        changed_fields,
        inet_client_addr(),
        jsonb_build_object(
            'session_user', session_user,
            'current_database', current_database(),
            'application_name', current_setting('application_name', true)
        )
    );
    
    -- Возвращаем соответствующий результат
    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    ELSE
        RETURN NEW;
    END IF;
EXCEPTION
    WHEN OTHERS THEN
        -- В случае ошибки логируем и продолжаем
        INSERT INTO audit.row_change_log (
            changed_by,
            table_schema,
            table_name,
            operation_type,
            old_values,
            new_values,
            client_ip
        ) VALUES (
            current_user::VARCHAR(100),
            TG_TABLE_SCHEMA,
            TG_TABLE_NAME,
            'ERROR',
            jsonb_build_object('error', SQLERRM),
            NULL,
            inet_client_addr()
        );
        
        IF TG_OP = 'DELETE' THEN
            RETURN OLD;
        ELSE
            RETURN NEW;
        END IF;
END;
$$;

-- =====================================================
-- Создание триггеров на критичных таблицах
-- =====================================================

-- Удаляем старые триггеры, если они есть
DROP TRIGGER IF EXISTS audit_row_change_projects ON app.projects;
DROP TRIGGER IF EXISTS audit_row_change_contracts ON app.contracts;
DROP TRIGGER IF EXISTS audit_row_change_actors ON app.actors;

-- Триггер на app.projects (критичная таблица)
CREATE TRIGGER audit_row_change_projects
    AFTER UPDATE OR DELETE ON app.projects
    FOR EACH ROW EXECUTE FUNCTION audit.log_row_change();

-- Триггер на app.contracts (критичная таблица)
CREATE TRIGGER audit_row_change_contracts
    AFTER UPDATE OR DELETE ON app.contracts
    FOR EACH ROW EXECUTE FUNCTION audit.log_row_change();

-- Триггер на app.actors (критичная таблица)
CREATE TRIGGER audit_row_change_actors
    AFTER UPDATE OR DELETE ON app.actors
    FOR EACH ROW EXECUTE FUNCTION audit.log_row_change();

-- Выдаём права на чтение логов аудита
GRANT SELECT ON audit.row_change_log TO auditor, security_admin, app_writer, app_reader;
GRANT USAGE ON SCHEMA audit TO auditor, security_admin, app_writer, app_reader;

-- Комментарии
COMMENT ON FUNCTION audit.log_row_change() IS 
'Триггерная функция для логирования изменений строк в критичных таблицах с маскированием чувствительных данных.';

COMMENT ON FUNCTION audit.mask_sensitive_data(JSONB, TEXT) IS 
'Функция маскирования/хэширования чувствительных полей в данных аудита.';

COMMENT ON TRIGGER audit_row_change_projects ON app.projects IS 
'Триггер аудита изменений для таблицы проектов. Логирует UPDATE и DELETE.';

COMMENT ON TRIGGER audit_row_change_contracts ON app.contracts IS 
'Триггер аудита изменений для таблицы контрактов. Логирует UPDATE и DELETE.';

COMMENT ON TRIGGER audit_row_change_actors ON app.actors IS 
'Триггер аудита изменений для таблицы актёров. Логирует UPDATE и DELETE.';

DO $$
BEGIN
    RAISE NOTICE 'LR4: Триггеры аудита изменений успешно созданы';
    RAISE NOTICE '  • Таблица: audit.row_change_log';
    RAISE NOTICE '  • Триггеры на: app.projects, app.contracts, app.actors';
    RAISE NOTICE '  • Маскирование: passport_data, tax_id, salary_amount, terms, client_contacts, budget';
END $$;

RESET ROLE;

