-- =====================================================
-- SECURITY DEFINER-функции для безопасного удаления
-- с проверкой временных привилегий
-- =====================================================

SET search_path TO app, ref, audit, stg, public;
SET ROLE app_owner;

DO $$
BEGIN
    RAISE NOTICE 'РГЗ: Создание функций безопасного удаления с проверкой временных привилегий';
END $$;

-- =====================================================
-- ФУНКЦИЯ 1: safe_delete_contract
-- Безопасное удаление контракта с проверкой временной привилегии
-- =====================================================

CREATE OR REPLACE FUNCTION app.safe_delete_contract(
    p_contract_id INTEGER
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = app, ref, audit, public
AS $$
DECLARE
    v_start_time TIMESTAMPTZ;
    v_end_time TIMESTAMPTZ;
    v_execution_time NUMERIC;
    v_has_privilege BOOLEAN;
    v_contract_exists BOOLEAN;
    v_input_params JSONB;
    v_return_value JSONB;
BEGIN
    v_start_time := clock_timestamp();
    
    -- Формируем JSON с параметрами
    v_input_params := jsonb_build_object(
        'contract_id', p_contract_id,
        'operation', 'delete_contract'
    );
    
    -- ПРОВЕРКА 1: Проверяем наличие временной привилегии
    SELECT audit.check_temp_privilege('delete_contract') INTO v_has_privilege;
    
    IF NOT v_has_privilege THEN
        PERFORM audit.log_function_call(
            'app', 'safe_delete_contract',
            v_input_params,
            NULL,
            false,
            'ОШИБКА: Временная привилегия на удаление контракта не активна или истекла. Вызовите app.request_temp_privilege(''delete_contract'', duration_min)',
            NULL
        );
        RAISE EXCEPTION 'Временная привилегия на удаление контракта не активна или истекла. Вызовите app.request_temp_privilege(''delete_contract'', duration_min)';
    END IF;
    
    -- ПРОВЕРКА 2: Проверяем существование контракта
    SELECT EXISTS (
        SELECT 1 FROM app.contracts WHERE contract_id = p_contract_id
    ) INTO v_contract_exists;
    
    IF NOT v_contract_exists THEN
        PERFORM audit.log_function_call(
            'app', 'safe_delete_contract',
            v_input_params,
            NULL,
            false,
            'ОШИБКА: Контракт с ID ' || p_contract_id || ' не найден',
            NULL
        );
        RAISE EXCEPTION 'Контракт с ID % не найден', p_contract_id;
    END IF;
    
    -- ПРОВЕРКА 3: Проверяем, нет ли связанных записей (сессии записи)
    IF EXISTS (
        SELECT 1 FROM app.recording_sessions WHERE contract_id = p_contract_id
    ) THEN
        PERFORM audit.log_function_call(
            'app', 'safe_delete_contract',
            v_input_params,
            NULL,
            false,
            'ОШИБКА: Невозможно удалить контракт, так как существуют связанные сессии записи',
            NULL
        );
        RAISE EXCEPTION 'Невозможно удалить контракт с ID %, так как существуют связанные сессии записи', p_contract_id;
    END IF;
    
    -- УДАЛЕНИЕ КОНТРАКТА
    DELETE FROM app.contracts
    WHERE contract_id = p_contract_id;
    
    -- Формируем возвращаемое значение
    v_return_value := jsonb_build_object(
        'contract_id', p_contract_id,
        'deleted', true,
        'message', 'Контракт успешно удалён'
    );
    
    -- Вычисляем время выполнения
    v_end_time := clock_timestamp();
    v_execution_time := EXTRACT(EPOCH FROM (v_end_time - v_start_time)) * 1000;
    
    -- ЛОГИРОВАНИЕ УСПЕШНОГО УДАЛЕНИЯ
    PERFORM audit.log_function_call(
        'app', 'safe_delete_contract',
        v_input_params,
        v_return_value,
        true,
        NULL,
        v_execution_time
    );
    
    RETURN true;
    
EXCEPTION
    WHEN OTHERS THEN
        v_end_time := clock_timestamp();
        v_execution_time := EXTRACT(EPOCH FROM (v_end_time - v_start_time)) * 1000;
        
        PERFORM audit.log_function_call(
            'app', 'safe_delete_contract',
            v_input_params,
            NULL,
            false,
            'ОШИБКА: ' || SQLERRM,
            v_execution_time
        );
        
        RAISE;
END;
$$;

COMMENT ON FUNCTION app.safe_delete_contract(INTEGER) IS 
'SECURITY DEFINER: Безопасное удаление контракта с проверкой временной привилегии. Требует активную временную привилегию delete_contract.';

-- =====================================================
-- ФУНКЦИЯ 2: safe_delete_actor
-- Безопасное удаление актёра с проверкой временной привилегии
-- =====================================================

CREATE OR REPLACE FUNCTION app.safe_delete_actor(
    p_actor_id INTEGER
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = app, ref, audit, public
AS $$
DECLARE
    v_start_time TIMESTAMPTZ;
    v_end_time TIMESTAMPTZ;
    v_execution_time NUMERIC;
    v_has_privilege BOOLEAN;
    v_actor_exists BOOLEAN;
    v_input_params JSONB;
    v_return_value JSONB;
BEGIN
    v_start_time := clock_timestamp();
    
    -- Формируем JSON с параметрами
    v_input_params := jsonb_build_object(
        'actor_id', p_actor_id,
        'operation', 'delete_actor'
    );
    
    -- ПРОВЕРКА 1: Проверяем наличие временной привилегии
    SELECT audit.check_temp_privilege('delete_actor') INTO v_has_privilege;
    
    IF NOT v_has_privilege THEN
        PERFORM audit.log_function_call(
            'app', 'safe_delete_actor',
            v_input_params,
            NULL,
            false,
            'ОШИБКА: Временная привилегия на удаление актёра не активна или истекла. Вызовите app.request_temp_privilege(''delete_actor'', duration_min)',
            NULL
        );
        RAISE EXCEPTION 'Временная привилегия на удаление актёра не активна или истекла. Вызовите app.request_temp_privilege(''delete_actor'', duration_min)';
    END IF;
    
    -- ПРОВЕРКА 2: Проверяем существование актёра
    SELECT EXISTS (
        SELECT 1 FROM app.actors WHERE actor_id = p_actor_id
    ) INTO v_actor_exists;
    
    IF NOT v_actor_exists THEN
        PERFORM audit.log_function_call(
            'app', 'safe_delete_actor',
            v_input_params,
            NULL,
            false,
            'ОШИБКА: Актёр с ID ' || p_actor_id || ' не найден',
            NULL
        );
        RAISE EXCEPTION 'Актёр с ID % не найден', p_actor_id;
    END IF;
    
    -- ПРОВЕРКА 3: Проверяем, нет ли связанных контрактов
    IF EXISTS (
        SELECT 1 FROM app.contracts WHERE actor_id = p_actor_id
    ) THEN
        PERFORM audit.log_function_call(
            'app', 'safe_delete_actor',
            v_input_params,
            NULL,
            false,
            'ОШИБКА: Невозможно удалить актёра, так как существуют связанные контракты',
            NULL
        );
        RAISE EXCEPTION 'Невозможно удалить актёра с ID %, так как существуют связанные контракты', p_actor_id;
    END IF;
    
    -- УДАЛЕНИЕ АКТЁРА
    DELETE FROM app.actors
    WHERE actor_id = p_actor_id;
    
    -- Формируем возвращаемое значение
    v_return_value := jsonb_build_object(
        'actor_id', p_actor_id,
        'deleted', true,
        'message', 'Актёр успешно удалён'
    );
    
    -- Вычисляем время выполнения
    v_end_time := clock_timestamp();
    v_execution_time := EXTRACT(EPOCH FROM (v_end_time - v_start_time)) * 1000;
    
    -- ЛОГИРОВАНИЕ УСПЕШНОГО УДАЛЕНИЯ
    PERFORM audit.log_function_call(
        'app', 'safe_delete_actor',
        v_input_params,
        v_return_value,
        true,
        NULL,
        v_execution_time
    );
    
    RETURN true;
    
EXCEPTION
    WHEN OTHERS THEN
        v_end_time := clock_timestamp();
        v_execution_time := EXTRACT(EPOCH FROM (v_end_time - v_start_time)) * 1000;
        
        PERFORM audit.log_function_call(
            'app', 'safe_delete_actor',
            v_input_params,
            NULL,
            false,
            'ОШИБКА: ' || SQLERRM,
            v_execution_time
        );
        
        RAISE;
END;
$$;

COMMENT ON FUNCTION app.safe_delete_actor(INTEGER) IS 
'SECURITY DEFINER: Безопасное удаление актёра с проверкой временной привилегии. Требует активную временную привилегию delete_actor.';

-- =====================================================
-- ФУНКЦИЯ 3: safe_delete_recording_session
-- Безопасное удаление сессии записи с проверкой временной привилегии
-- =====================================================

CREATE OR REPLACE FUNCTION app.safe_delete_recording_session(
    p_session_id INTEGER
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = app, ref, audit, public
AS $$
DECLARE
    v_start_time TIMESTAMPTZ;
    v_end_time TIMESTAMPTZ;
    v_execution_time NUMERIC;
    v_has_privilege BOOLEAN;
    v_session_exists BOOLEAN;
    v_input_params JSONB;
    v_return_value JSONB;
BEGIN
    v_start_time := clock_timestamp();
    
    -- Формируем JSON с параметрами
    v_input_params := jsonb_build_object(
        'session_id', p_session_id,
        'operation', 'delete_recording_session'
    );
    
    -- ПРОВЕРКА 1: Проверяем наличие временной привилегии
    SELECT audit.check_temp_privilege('delete_recording_session') INTO v_has_privilege;
    
    IF NOT v_has_privilege THEN
        PERFORM audit.log_function_call(
            'app', 'safe_delete_recording_session',
            v_input_params,
            NULL,
            false,
            'ОШИБКА: Временная привилегия на удаление сессии записи не активна или истекла. Вызовите app.request_temp_privilege(''delete_recording_session'', duration_min)',
            NULL
        );
        RAISE EXCEPTION 'Временная привилегия на удаление сессии записи не активна или истекла. Вызовите app.request_temp_privilege(''delete_recording_session'', duration_min)';
    END IF;
    
    -- ПРОВЕРКА 2: Проверяем существование сессии
    SELECT EXISTS (
        SELECT 1 FROM app.recording_sessions WHERE session_id = p_session_id
    ) INTO v_session_exists;
    
    IF NOT v_session_exists THEN
        PERFORM audit.log_function_call(
            'app', 'safe_delete_recording_session',
            v_input_params,
            NULL,
            false,
            'ОШИБКА: Сессия записи с ID ' || p_session_id || ' не найдена',
            NULL
        );
        RAISE EXCEPTION 'Сессия записи с ID % не найдена', p_session_id;
    END IF;
    
    -- ПРОВЕРКА 3: Проверяем, нет ли связанных аудиоархивов
    IF EXISTS (
        SELECT 1 FROM app.audio_archives WHERE session_id = p_session_id
    ) THEN
        PERFORM audit.log_function_call(
            'app', 'safe_delete_recording_session',
            v_input_params,
            NULL,
            false,
            'ОШИБКА: Невозможно удалить сессию записи, так как существуют связанные аудиоархивы',
            NULL
        );
        RAISE EXCEPTION 'Невозможно удалить сессию записи с ID %, так как существуют связанные аудиоархивы', p_session_id;
    END IF;
    
    -- УДАЛЕНИЕ СЕССИИ
    DELETE FROM app.recording_sessions
    WHERE session_id = p_session_id;
    
    -- Формируем возвращаемое значение
    v_return_value := jsonb_build_object(
        'session_id', p_session_id,
        'deleted', true,
        'message', 'Сессия записи успешно удалена'
    );
    
    -- Вычисляем время выполнения
    v_end_time := clock_timestamp();
    v_execution_time := EXTRACT(EPOCH FROM (v_end_time - v_start_time)) * 1000;
    
    -- ЛОГИРОВАНИЕ УСПЕШНОГО УДАЛЕНИЯ
    PERFORM audit.log_function_call(
        'app', 'safe_delete_recording_session',
        v_input_params,
        v_return_value,
        true,
        NULL,
        v_execution_time
    );
    
    RETURN true;
    
EXCEPTION
    WHEN OTHERS THEN
        v_end_time := clock_timestamp();
        v_execution_time := EXTRACT(EPOCH FROM (v_end_time - v_start_time)) * 1000;
        
        PERFORM audit.log_function_call(
            'app', 'safe_delete_recording_session',
            v_input_params,
            NULL,
            false,
            'ОШИБКА: ' || SQLERRM,
            v_execution_time
        );
        
        RAISE;
END;
$$;

COMMENT ON FUNCTION app.safe_delete_recording_session(INTEGER) IS 
'SECURITY DEFINER: Безопасное удаление сессии записи с проверкой временной привилегии. Требует активную временную привилегию delete_recording_session.';

-- Даём доступ к функциям
GRANT EXECUTE ON FUNCTION app.safe_delete_contract(INTEGER) TO app_writer, studio_manager;
GRANT EXECUTE ON FUNCTION app.safe_delete_actor(INTEGER) TO app_writer, studio_manager;
GRANT EXECUTE ON FUNCTION app.safe_delete_recording_session(INTEGER) TO app_writer, studio_manager;

DO $$
BEGIN
    RAISE NOTICE 'РГЗ: Функции безопасного удаления успешно созданы:';
    RAISE NOTICE '   - app.safe_delete_contract';
    RAISE NOTICE '   - app.safe_delete_actor';
    RAISE NOTICE '   - app.safe_delete_recording_session';
END $$;

RESET ROLE;

