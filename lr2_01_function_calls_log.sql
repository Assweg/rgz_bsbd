-- =====================================================
-- Создание таблицы журнала вызовов функций
-- =====================================================

-- Создаём таблицу для журнала вызовов SECURITY DEFINER-функций
CREATE TABLE IF NOT EXISTS audit.function_calls (
    call_id BIGSERIAL PRIMARY KEY,
    call_time TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    function_name VARCHAR(255) NOT NULL,
    function_schema VARCHAR(100) NOT NULL,
    caller_role VARCHAR(100) NOT NULL,
    caller_username VARCHAR(100) NOT NULL,
    input_params JSONB,
    return_value JSONB,
    success BOOLEAN NOT NULL DEFAULT true,
    error_message TEXT,
    execution_time_ms NUMERIC(10, 3),
    client_ip INET,
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

-- Создаём индексы для быстрого поиска
CREATE INDEX IF NOT EXISTS idx_function_calls_time ON audit.function_calls(call_time);
CREATE INDEX IF NOT EXISTS idx_function_calls_function ON audit.function_calls(function_schema, function_name);
CREATE INDEX IF NOT EXISTS idx_function_calls_caller ON audit.function_calls(caller_username);
CREATE INDEX IF NOT EXISTS idx_function_calls_success ON audit.function_calls(success) WHERE success = false;

-- Комментарии
COMMENT ON TABLE audit.function_calls IS 'Журнал вызовов SECURITY DEFINER-функций для аудита безопасности';
COMMENT ON COLUMN audit.function_calls.call_id IS 'Уникальный идентификатор записи';
COMMENT ON COLUMN audit.function_calls.call_time IS 'Время вызова функции';
COMMENT ON COLUMN audit.function_calls.function_name IS 'Имя вызванной функции';
COMMENT ON COLUMN audit.function_calls.function_schema IS 'Схема функции';
COMMENT ON COLUMN audit.function_calls.caller_role IS 'Роль, от имени которой вызвана функция';
COMMENT ON COLUMN audit.function_calls.caller_username IS 'Имя пользователя, вызвавшего функцию';
COMMENT ON COLUMN audit.function_calls.input_params IS 'Параметры вызова в формате JSON';
COMMENT ON COLUMN audit.function_calls.return_value IS 'Возвращаемое значение (если есть)';
COMMENT ON COLUMN audit.function_calls.success IS 'Успешность выполнения функции';
COMMENT ON COLUMN audit.function_calls.error_message IS 'Сообщение об ошибке (если была)';
COMMENT ON COLUMN audit.function_calls.execution_time_ms IS 'Время выполнения в миллисекундах';
COMMENT ON COLUMN audit.function_calls.client_ip IS 'IP-адрес клиента';

-- Запрещаем прямой доступ к таблице (только через функции)
REVOKE ALL ON audit.function_calls FROM PUBLIC;
REVOKE INSERT, UPDATE, DELETE ON audit.function_calls FROM PUBLIC;

-- Разрешаем чтение только auditor
GRANT SELECT ON audit.function_calls TO auditor;

-- Создаём роль для логирования (только INSERT)
DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'function_logger') THEN
        CREATE ROLE function_logger WITH NOLOGIN;
    END IF;
END $$;

GRANT USAGE ON SCHEMA audit TO function_logger;
GRANT INSERT ON audit.function_calls TO function_logger;
GRANT USAGE ON SEQUENCE audit.function_calls_call_id_seq TO function_logger;

-- Функция-хелпер для логирования вызова функции
CREATE OR REPLACE FUNCTION audit.log_function_call(
    p_function_schema VARCHAR,
    p_function_name VARCHAR,
    p_input_params JSONB DEFAULT NULL,
    p_return_value JSONB DEFAULT NULL,
    p_success BOOLEAN DEFAULT true,
    p_error_message TEXT DEFAULT NULL,
    p_execution_time_ms NUMERIC DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = audit, public
AS $$
BEGIN
    INSERT INTO audit.function_calls (
        function_schema,
        function_name,
        caller_role,
        caller_username,
        input_params,
        return_value,
        success,
        error_message,
        execution_time_ms,
        client_ip
    ) VALUES (
        p_function_schema,
        p_function_name,
        COALESCE(current_setting('role', true), session_user)::VARCHAR,
        session_user::VARCHAR(100),
        p_input_params,
        p_return_value,
        p_success,
        p_error_message,
        p_execution_time_ms,
        inet_client_addr()
    );
EXCEPTION
    WHEN OTHERS THEN
        -- В случае ошибки логирования просто игнорируем (чтобы не ломать основную функцию)
        NULL;
END;
$$;

-- Даём доступ к функции логирования
GRANT EXECUTE ON FUNCTION audit.log_function_call TO function_logger;
GRANT function_logger TO app_owner;

COMMENT ON FUNCTION audit.log_function_call IS 'Вспомогательная функция для логирования вызовов SECURITY DEFINER-функций';

-- Уведомление
DO $$ 
BEGIN
    RAISE NOTICE '✅ Таблица audit.function_calls и функция логирования успешно созданы';
END $$;