-- Реализация механизма временных привилегий для роли app_writer
-- Позволяет временно (на N минут) получать право на выполнение 
-- чувствительных операций (например, удаление записи)

SET search_path TO app, ref, audit, stg, public;
SET ROLE app_owner;

DO $$
BEGIN
    RAISE NOTICE 'РГЗ: Начало создания системы временных привилегий (Just-In-Time Access)';
END $$;

-- =====================================================
-- 1. Создание таблицы audit.temp_access_log
-- =====================================================

CREATE TABLE IF NOT EXISTS audit.temp_access_log (
    request_id BIGSERIAL PRIMARY KEY,
    request_time TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    caller_role VARCHAR(100) NOT NULL,
    caller_username VARCHAR(100) NOT NULL,
    operation VARCHAR(100) NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    duration_minutes INTEGER NOT NULL,
    is_active BOOLEAN DEFAULT true,
    used_at TIMESTAMPTZ,
    client_ip INET,
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

-- Индексы для быстрого поиска
CREATE INDEX IF NOT EXISTS idx_temp_access_log_caller ON audit.temp_access_log(caller_username, operation);
CREATE INDEX IF NOT EXISTS idx_temp_access_log_expires ON audit.temp_access_log(expires_at) WHERE is_active = true;
CREATE INDEX IF NOT EXISTS idx_temp_access_log_active ON audit.temp_access_log(is_active, expires_at);

-- Комментарии
COMMENT ON TABLE audit.temp_access_log IS 
'Журнал запросов временных привилегий (Just-In-Time Access). Записывает кто, какую операцию и на сколько времени запросил.';

COMMENT ON COLUMN audit.temp_access_log.request_id IS 'Уникальный идентификатор запроса';
COMMENT ON COLUMN audit.temp_access_log.request_time IS 'Время запроса временной привилегии';
COMMENT ON COLUMN audit.temp_access_log.caller_role IS 'Роль, запросившая привилегию';
COMMENT ON COLUMN audit.temp_access_log.caller_username IS 'Пользователь, запросивший привилегию';
COMMENT ON COLUMN audit.temp_access_log.operation IS 'Название операции (например, delete_contract, delete_actor)';
COMMENT ON COLUMN audit.temp_access_log.expires_at IS 'Время истечения привилегии';
COMMENT ON COLUMN audit.temp_access_log.duration_minutes IS 'Длительность привилегии в минутах';
COMMENT ON COLUMN audit.temp_access_log.is_active IS 'Активна ли привилегия (автоматически становится false после истечения)';
COMMENT ON COLUMN audit.temp_access_log.used_at IS 'Время последнего использования привилегии';

-- Запрещаем прямой доступ к таблице (только через функции)
REVOKE ALL ON audit.temp_access_log FROM PUBLIC;
REVOKE INSERT, UPDATE, DELETE ON audit.temp_access_log FROM PUBLIC, app_writer, studio_manager;

-- Разрешаем чтение auditor, security_admin и app_writer (только свои записи)
-- Также даём USAGE на схему audit для app_writer и studio_manager
GRANT USAGE ON SCHEMA audit TO app_writer, studio_manager;
GRANT SELECT ON audit.temp_access_log TO auditor, security_admin, app_writer, studio_manager;

-- Создаём роль для логирования временных привилегий
-- Используем существующую роль function_logger или создаём новую только если есть права
DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'temp_privilege_logger') THEN
        BEGIN
            CREATE ROLE temp_privilege_logger WITH NOLOGIN;
        EXCEPTION WHEN insufficient_privilege THEN
            -- Если нет прав на создание роли, используем существующую роль function_logger
            IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'function_logger') THEN
                RAISE NOTICE 'Используем существующую роль function_logger вместо temp_privilege_logger';
            ELSE
                RAISE EXCEPTION 'Не удалось создать роль temp_privilege_logger и не найдена роль function_logger';
            END IF;
        END;
    END IF;
END $$;

-- Выдаём права на схему и таблицу
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'temp_privilege_logger') THEN
        GRANT USAGE ON SCHEMA audit TO temp_privilege_logger;
        GRANT INSERT, UPDATE ON audit.temp_access_log TO temp_privilege_logger;
        GRANT USAGE ON SEQUENCE audit.temp_access_log_request_id_seq TO temp_privilege_logger;
    ELSIF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'function_logger') THEN
        -- Используем существующую роль function_logger
        GRANT INSERT, UPDATE ON audit.temp_access_log TO function_logger;
        GRANT USAGE ON SEQUENCE audit.temp_access_log_request_id_seq TO function_logger;
    END IF;
END $$;

-- =====================================================
-- 2. Справочник разрешённых операций для ролей
-- =====================================================

CREATE TABLE IF NOT EXISTS audit.allowed_temp_operations (
    operation_id SERIAL PRIMARY KEY,
    operation_name VARCHAR(100) NOT NULL UNIQUE,
    role_name VARCHAR(100) NOT NULL,
    description TEXT,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

COMMENT ON TABLE audit.allowed_temp_operations IS 
'Справочник разрешённых операций для временных привилегий по ролям';

-- Заполняем справочник разрешённых операций
INSERT INTO audit.allowed_temp_operations (operation_name, role_name, description) VALUES
    ('delete_contract', 'app_writer', 'Удаление контракта'),
    ('delete_actor', 'app_writer', 'Удаление актёра'),
    ('delete_project', 'app_writer', 'Удаление проекта'),
    ('delete_recording_session', 'app_writer', 'Удаление сессии записи'),
    ('delete_audio_archive', 'app_writer', 'Удаление аудиоархива')
ON CONFLICT (operation_name) DO UPDATE
    SET description = EXCLUDED.description,
        is_active = TRUE;

-- Запрещаем прямой доступ к справочнику
REVOKE ALL ON audit.allowed_temp_operations FROM PUBLIC;
GRANT SELECT ON audit.allowed_temp_operations TO app_writer, studio_manager, auditor, security_admin;

-- =====================================================
-- 3. Функция проверки активной временной привилегии
-- =====================================================

CREATE OR REPLACE FUNCTION audit.check_temp_privilege(
    p_operation VARCHAR(100)
)
RETURNS BOOLEAN
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = audit, public
AS $$
DECLARE
    v_expires_at TIMESTAMPTZ;
    v_is_active BOOLEAN;
    v_caller_username VARCHAR(100);
    v_request_id BIGINT;
BEGIN
    v_caller_username := session_user;
    
    -- Проверяем наличие активной привилегии
    SELECT request_id, expires_at, is_active
    INTO v_request_id, v_expires_at, v_is_active
    FROM audit.temp_access_log
    WHERE caller_username = v_caller_username
      AND operation = p_operation
      AND is_active = true
    ORDER BY request_time DESC
    LIMIT 1;
    
    -- Если привилегия не найдена
    IF NOT FOUND THEN
        RETURN false;
    END IF;
    
    -- Если привилегия истекла, помечаем её как неактивную
    IF v_expires_at < NOW() THEN
        UPDATE audit.temp_access_log
        SET is_active = false
        WHERE request_id = v_request_id;
        
        RETURN false;
    END IF;
    
    -- Обновляем время последнего использования
    UPDATE audit.temp_access_log
    SET used_at = NOW()
    WHERE request_id = v_request_id;
    
    RETURN true;
END;
$$;

COMMENT ON FUNCTION audit.check_temp_privilege(VARCHAR) IS 
'Проверяет, активна ли временная привилегия для текущего пользователя на указанную операцию';

-- =====================================================
-- 4. Функция запроса временной привилегии
-- =====================================================

CREATE OR REPLACE FUNCTION app.request_temp_privilege(
    p_operation_name TEXT,
    p_duration_min INTEGER
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = app, ref, audit, public
AS $$
DECLARE
    v_caller_role VARCHAR(100);
    v_caller_username VARCHAR(100);
    v_expires_at TIMESTAMPTZ;
    v_request_id BIGINT;
    v_is_allowed BOOLEAN;
    v_result JSONB;
BEGIN
    -- Получаем информацию о вызывающем
    v_caller_role := COALESCE(current_setting('role', true), session_user);
    v_caller_username := session_user;
    
    -- ВАЛИДАЦИЯ 1: Проверяем, разрешена ли операция для роли
    SELECT EXISTS (
        SELECT 1
        FROM audit.allowed_temp_operations
        WHERE operation_name = p_operation_name
          AND role_name = v_caller_role
          AND is_active = true
    ) INTO v_is_allowed;
    
    IF NOT v_is_allowed THEN
        PERFORM audit.log_function_call(
            'app', 'request_temp_privilege',
            jsonb_build_object(
                'operation_name', p_operation_name,
                'duration_min', p_duration_min,
                'caller_role', v_caller_role
            ),
            NULL,
            false,
            'ОШИБКА: Операция ' || p_operation_name || ' не разрешена для роли ' || v_caller_role,
            NULL
        );
        RAISE EXCEPTION 'Операция % не разрешена для роли %', p_operation_name, v_caller_role;
    END IF;
    
    -- ВАЛИДАЦИЯ 2: Проверяем длительность (от 1 до 60 минут)
    IF p_duration_min IS NULL OR p_duration_min < 1 OR p_duration_min > 60 THEN
        PERFORM audit.log_function_call(
            'app', 'request_temp_privilege',
            jsonb_build_object(
                'operation_name', p_operation_name,
                'duration_min', p_duration_min
            ),
            NULL,
            false,
            'ОШИБКА: Длительность должна быть от 1 до 60 минут',
            NULL
        );
        RAISE EXCEPTION 'Длительность должна быть от 1 до 60 минут, получено: %', p_duration_min;
    END IF;
    
    -- Вычисляем время истечения
    v_expires_at := NOW() + (p_duration_min || ' minutes')::INTERVAL;
    
    -- Деактивируем предыдущие активные привилегии для этой операции
    UPDATE audit.temp_access_log
    SET is_active = false
    WHERE caller_username = v_caller_username
      AND operation = p_operation_name
      AND is_active = true;
    
    -- Записываем запрос в audit.temp_access_log
    INSERT INTO audit.temp_access_log (
        caller_role,
        caller_username,
        operation,
        expires_at,
        duration_minutes,
        is_active,
        client_ip
    ) VALUES (
        v_caller_role,
        v_caller_username,
        p_operation_name,
        v_expires_at,
        p_duration_min,
        true,
        inet_client_addr()
    )
    RETURNING request_id INTO v_request_id;
    
    -- Устанавливаем временную метку истечения через GUC
    PERFORM set_config('app.temp_privilege_until', v_expires_at::TEXT, false);
    
    -- Формируем результат
    v_result := jsonb_build_object(
        'request_id', v_request_id,
        'operation', p_operation_name,
        'expires_at', v_expires_at,
        'duration_minutes', p_duration_min,
        'status', 'granted'
    );
    
    -- Логируем успешный вызов
    PERFORM audit.log_function_call(
        'app', 'request_temp_privilege',
        jsonb_build_object(
            'operation_name', p_operation_name,
            'duration_min', p_duration_min
        ),
        v_result,
        true,
        NULL,
        NULL
    );
    
    RETURN v_result;
    
EXCEPTION
    WHEN OTHERS THEN
        -- Логируем ошибку
        PERFORM audit.log_function_call(
            'app', 'request_temp_privilege',
            jsonb_build_object(
                'operation_name', p_operation_name,
                'duration_min', p_duration_min
            ),
            NULL,
            false,
            'ОШИБКА: ' || SQLERRM,
            NULL
        );
        
        RAISE;
END;
$$;

COMMENT ON FUNCTION app.request_temp_privilege(TEXT, INTEGER) IS 
'SECURITY DEFINER: Запрашивает временную привилегию на выполнение чувствительной операции. Проверяет права роли, записывает в audit.temp_access_log и устанавливает GUC app.temp_privilege_until.';

-- Даём доступ к функции
GRANT EXECUTE ON FUNCTION app.request_temp_privilege(TEXT, INTEGER) TO app_writer, studio_manager;
GRANT EXECUTE ON FUNCTION audit.check_temp_privilege(VARCHAR) TO app_writer, studio_manager, app_owner;

-- Назначаем роль для логирования (если она существует)
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'temp_privilege_logger') THEN
        GRANT temp_privilege_logger TO app_owner;
    ELSIF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'function_logger') THEN
        -- function_logger уже назначена app_owner в ЛР2
        NULL;
    END IF;
END $$;

DO $$
BEGIN
    RAISE NOTICE 'РГЗ: Таблица audit.temp_access_log и функция request_temp_privilege успешно созданы';
END $$;

RESET ROLE;

