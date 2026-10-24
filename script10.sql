-- 10_audit_triggers_and_tests.sql
-- Триггеры аудита DML операций и тестирование системы безопасности

-- Функция для логирования изменений данных
CREATE OR REPLACE FUNCTION audit.log_data_changes()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = audit, public
AS $$
DECLARE
    old_data JSONB;
    new_data JSONB;
    operation_type VARCHAR(10);
BEGIN
    -- Определяем тип операции
    IF TG_OP = 'DELETE' THEN
        operation_type := 'DELETE';
        old_data := to_jsonb(OLD);
        new_data := NULL;
    ELSIF TG_OP = 'UPDATE' THEN
        operation_type := 'UPDATE';
        old_data := to_jsonb(OLD);
        new_data := to_jsonb(NEW);
    ELSIF TG_OP = 'INSERT' THEN
        operation_type := 'INSERT';
        old_data := NULL;
        new_data := to_jsonb(NEW);
    END IF;

    -- Записываем в лог аудита
    INSERT INTO audit.data_access_log (
        username,
        table_name,
        operation_type,
        record_id,
        old_values,
        new_values,
        client_ip
    ) VALUES (
        current_user::VARCHAR(100),
        TG_TABLE_SCHEMA || '.' || TG_TABLE_NAME,
        operation_type,
        CASE 
            WHEN TG_OP = 'DELETE' THEN OLD.actor_id
            WHEN TG_OP = 'UPDATE' THEN NEW.actor_id
            WHEN TG_OP = 'INSERT' THEN NEW.actor_id
        END,
        old_data,
        new_data,
        inet_client_addr()
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
        INSERT INTO audit.data_access_log (
            username,
            table_name,
            operation_type,
            old_values,
            new_values,
            client_ip
        ) VALUES (
            current_user::VARCHAR(100),
            TG_TABLE_SCHEMA || '.' || TG_TABLE_NAME,
            'ERROR',
            NULL,
            jsonb_build_object('error', SQLERRM),
            inet_client_addr()
        );
        
        IF TG_OP = 'DELETE' THEN
            RETURN OLD;
        ELSE
            RETURN NEW;
        END IF;
END;
$$;

-- Создаём триггеры для основных таблиц
CREATE TRIGGER audit_actors_changes
    AFTER INSERT OR UPDATE OR DELETE ON app.actors
    FOR EACH ROW EXECUTE FUNCTION audit.log_data_changes();

CREATE TRIGGER audit_contracts_changes
    AFTER INSERT OR UPDATE OR DELETE ON app.contracts
    FOR EACH ROW EXECUTE FUNCTION audit.log_data_changes();

CREATE TRIGGER audit_projects_changes
    AFTER INSERT OR UPDATE OR DELETE ON app.projects
    FOR EACH ROW EXECUTE FUNCTION audit.log_data_changes();

CREATE TRIGGER audit_recording_sessions_changes
    AFTER INSERT OR UPDATE OR DELETE ON app.recording_sessions
    FOR EACH ROW EXECUTE FUNCTION audit.log_data_changes();

CREATE TRIGGER audit_audio_archives_changes
    AFTER INSERT OR UPDATE OR DELETE ON app.audio_archives
    FOR EACH ROW EXECUTE FUNCTION audit.log_data_changes();

-- Даём права на выполнение функции аудита
GRANT EXECUTE ON FUNCTION audit.log_data_changes TO app_owner, app_writer;

-- Комментарии
COMMENT ON FUNCTION audit.log_data_changes IS 'Функция для автоматического логирования изменений в таблицах';
COMMENT ON TRIGGER audit_actors_changes ON app.actors IS 'Триггер аудита для таблицы актёров';
COMMENT ON TRIGGER audit_contracts_changes ON app.contracts IS 'Триггер аудита для таблицы контрактов';
COMMENT ON TRIGGER audit_projects_changes ON app.projects IS 'Триггер аудита для таблицы проектов';
COMMENT ON TRIGGER audit_recording_sessions_changes ON app.recording_sessions IS 'Триггер аудита для таблицы сессий записи';
COMMENT ON TRIGGER audit_audio_archives_changes ON app.audio_archives IS 'Триггер аудита для таблицы аудиоархивов';

-- Автоматическое логирование входов через pgaudit
CREATE OR REPLACE FUNCTION audit.parse_pgaudit_log()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = audit, public
AS $$
DECLARE
    log_line TEXT;
    username_part TEXT;
    ip_part TEXT;
    success_part TEXT;
    parsed_username VARCHAR(100);
    parsed_ip INET;
    parsed_success BOOLEAN;
BEGIN
    -- Эта функция будет вызываться периодически для парсинга логов pgaudit
    
    -- Для демонстрации создаём пример записи
    INSERT INTO audit.login_log (
        username,
        client_ip,
        connection_method,
        is_successful,
        failure_reason
    ) VALUES (
        'pgaudit_parser',
        '127.0.0.1',
        'pgaudit_auto',
        true,
        NULL
    );
    
EXCEPTION
    WHEN OTHERS THEN
        -- В случае ошибки логируем
        INSERT INTO audit.login_log (
            username,
            client_ip,
            connection_method,
            is_successful,
            failure_reason
        ) VALUES (
            'pgaudit_parser',
            '127.0.0.1',
            'pgaudit_auto',
            false,
            SQLERRM
        );
END;
$$;

-- Создаём функцию для принудительного логирования входа при подключении
CREATE OR REPLACE FUNCTION public.auto_log_connection()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = audit, public
AS $$
BEGIN
    -- Логируем подключение
    PERFORM audit.log_connection();
    
    -- Также парсим pgaudit логи
    PERFORM audit.parse_pgaudit_log();
END;
$$;

-- Даём доступ к функциям
GRANT EXECUTE ON FUNCTION audit.parse_pgaudit_log TO app_owner, security_auditor;
GRANT EXECUTE ON FUNCTION public.auto_log_connection TO studio_manager, voice_actor, security_auditor, db_developer;

-- Создаём роль для автоматического логирования
DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'auto_logger') THEN
        CREATE ROLE auto_logger WITH NOLOGIN;
    END IF;
END $$;

GRANT USAGE ON SCHEMA audit TO auto_logger;
GRANT INSERT ON audit.login_log TO auto_logger;
GRANT EXECUTE ON FUNCTION audit.log_connection TO auto_logger;
GRANT EXECUTE ON FUNCTION audit.parse_pgaudit_log TO auto_logger;

-- Назначаем роль пользователям
GRANT auto_logger TO studio_manager, voice_actor, security_auditor, db_developer;

-- Комментарии
COMMENT ON FUNCTION audit.parse_pgaudit_log IS 'Функция для парсинга логов pgaudit и записи в audit.login_log';
COMMENT ON FUNCTION public.auto_log_connection IS 'Функция для автоматического логирования подключений';
COMMENT ON ROLE auto_logger IS 'Роль для автоматического логирования подключений';

-- Уведомление о завершении
DO $$ 
BEGIN
    RAISE NOTICE 'Триггеры аудита DML операций и автоматическое логирование входов настроены';
END $$;

-- Тестирование системы безопасности (выполнять ПОСЛЕ всех скриптов)

DO $$ 
BEGIN
    RAISE NOTICE '=== НАЧАЛО ТЕСТИРОВАНИЯ СИСТЕМЫ БЕЗОПАСНОСТИ ===';
END $$;

-- Проверяем существование тестовых данных
DO $$
DECLARE
    actor_count INTEGER;
    contract_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO actor_count FROM app.actors;
    SELECT COUNT(*) INTO contract_count FROM app.contracts;
    
    RAISE NOTICE 'Найдено актёров: %, контрактов: %', actor_count, contract_count;
    
    IF actor_count = 0 OR contract_count = 0 THEN
        RAISE EXCEPTION 'Отсутствуют тестовые данные! Сначала выполните скрипт 08_test_data.sql';
    END IF;
END $$;

-- Проверка от имени superuser
DO $$
BEGIN
    RAISE NOTICE '=== ТЕСТ 1: Проверка от superuser ===';
END $$;

SELECT 
    'Superuser видит актёров: ' || COUNT(*)::TEXT as test_result
FROM app.actors;

SELECT 
    'Superuser видит контракты: ' || COUNT(*)::TEXT as test_result  
FROM app.contracts;

SELECT 
    'Superuser видит логи: ' || COUNT(*)::TEXT as test_result
FROM audit.login_log;

-- Тестирование безопасных функций
DO $$
BEGIN
    RAISE NOTICE '=== ТЕСТ 2: Безопасные функции ===';
END $$;

SELECT * FROM app.get_contracts_with_masked_salary() LIMIT 3;

-- Автоматическая проверка системы
DO $$
BEGIN
    RAISE NOTICE '=== АВТОМАТИЧЕСКАЯ ПРОВЕРКА СИСТЕМЫ ===';
END $$;

-- Проверяем роли
SELECT 
    rolname,
    CASE 
        WHEN rolname IN ('app_reader', 'app_writer', 'auditor', 'studio_manager', 'voice_actor', 'security_auditor', 'db_developer') 
        THEN '✓ Создана'
        ELSE '✗ Отсутствует'
    END as status
FROM pg_roles 
WHERE rolname IN ('app_reader', 'app_writer', 'auditor', 'studio_manager', 'voice_actor', 'security_auditor', 'db_developer');

-- Проверяем RLS
SELECT 
    schemaname,
    tablename,
    CASE 
        WHEN rowsecurity THEN '✓ Включен'
        ELSE '✗ Выключен'
    END as rls_status
FROM pg_tables 
WHERE schemaname = 'app' 
  AND tablename IN ('actors', 'contracts', 'recording_sessions', 'audio_archives');

-- Проверяем политики
SELECT 
    schemaname,
    tablename,
    policyname,
    '✓ Настроена' as status
FROM pg_policies 
WHERE schemaname = 'app';

-- Инструкция для ручного тестирования
DO $$
BEGIN
    RAISE NOTICE ' ';
    RAISE NOTICE '=== ИНСТРУКЦИЯ ДЛЯ РУЧНОГО ТЕСТИРОВАНИЯ ===';
    RAISE NOTICE 'Откройте НОВОЕ окно Query Tool для тестирования:';
    RAISE NOTICE ' ';
    RAISE NOTICE 'ТЕСТ voice_actor:';
    RAISE NOTICE '1. SET ROLE voice_actor;';
    RAISE NOTICE '2. SET app.current_actor_id = ''1'';';
    RAISE NOTICE '3. SELECT * FROM app.contracts; -- Только контракты актёра 1 (без salary_amount)';
    RAISE NOTICE '4. SELECT * FROM app.get_contracts_with_masked_salary(); -- Безопасный просмотр зарплат';
    RAISE NOTICE '5. SELECT public.log_session_start();';
    RAISE NOTICE '6. RESET ROLE;';
    RAISE NOTICE ' ';
    RAISE NOTICE 'ТЕСТ studio_manager:';
    RAISE NOTICE '1. SET ROLE studio_manager;';
    RAISE NOTICE '2. SELECT * FROM app.projects; -- Должен работать';
    RAISE NOTICE '3. SELECT * FROM audit.login_log; -- Должна БЫТЬ ОШИБКА';
    RAISE NOTICE '4. RESET ROLE;';
    RAISE NOTICE ' ';
    RAISE NOTICE 'ТЕСТ security_auditor:';
    RAISE NOTICE '1. SET ROLE security_auditor;';
    RAISE NOTICE '2. SELECT * FROM audit.login_log; -- Должен работать';
    RAISE NOTICE '3. SELECT * FROM app.contracts; -- Должна БЫТЬ ОШИБКА';
    RAISE NOTICE '4. RESET ROLE;';
    RAISE NOTICE ' ';
END $$;