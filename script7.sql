-- 07_audit.sql 
-- Создание механизма аудита подключений

-- Функция для логирования подключений
CREATE OR REPLACE FUNCTION audit.log_connection()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = audit, public
AS $$
BEGIN
    INSERT INTO audit.login_log (
        username, 
        client_ip, 
        connection_method,
        is_successful
    ) VALUES (
        current_user::VARCHAR(100),
        inet_client_addr()::INET,
        'direct',
        true
    );
EXCEPTION
    WHEN OTHERS THEN
        INSERT INTO audit.login_log (
            username,
            client_ip, 
            connection_method,
            is_successful,
            failure_reason
        ) VALUES (
            current_user::VARCHAR(100),
            inet_client_addr()::INET,
            'direct',
            false,
            SQLERRM
        );
END;
$$;

-- Роль для логирования подключений (с проверкой существования)
DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'connection_logger') THEN
        CREATE ROLE connection_logger WITH NOLOGIN;
    END IF;
END $$;

GRANT USAGE ON SCHEMA audit TO connection_logger;
GRANT INSERT ON audit.login_log TO connection_logger;
GRANT EXECUTE ON FUNCTION audit.log_connection TO connection_logger;

-- Назначаем роль конкретным пользователям
GRANT connection_logger TO studio_manager, voice_actor, security_auditor, db_developer;

-- Функция для ручного логирования сессии
CREATE OR REPLACE FUNCTION public.log_session_start()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = audit, public
AS $$
BEGIN
    PERFORM audit.log_connection();
END;
$$;

-- Даём доступ к функции логирования сессии только нужным ролям
GRANT EXECUTE ON FUNCTION public.log_session_start TO studio_manager, voice_actor, security_auditor, db_developer;

COMMENT ON FUNCTION audit.log_connection IS 'Функция для логирования подключений пользователей';
COMMENT ON FUNCTION public.log_session_start IS 'Функция для ручного логирования старта сессии';