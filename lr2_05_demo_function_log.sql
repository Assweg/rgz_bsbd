-- =====================================================
-- ЛАБОРАТОРНАЯ РАБОТА №2
-- Скрипт 5: Демонстрация журнала вызовов функций
-- =====================================================

\echo '====================================================='
\echo 'ЖУРНАЛ ВЫЗОВОВ SECURITY DEFINER-ФУНКЦИЙ'
\echo '====================================================='

-- Выполняем несколько вызовов функций для демонстрации
\echo ''
\echo 'Выполняем тестовые вызовы функций...'

SET ROLE studio_manager;

-- Вызов 1: Успешное создание контракта
DO $$
DECLARE
    v_contract_id INTEGER;
BEGIN
    SELECT app.create_contract(
        p_project_id := 1,
        p_actor_id := 3,
        p_contract_number := 'DEMO-CONTRACT-001',
        p_role_description := 'Демонстрационный контракт',
        p_salary_amount := 35000.00,
        p_currency := 'USD'
    ) INTO v_contract_id;
    
    RAISE NOTICE 'Создан контракт ID: %', v_contract_id;
END $$;

-- Вызов 2: Успешное обновление зарплаты
DO $$
BEGIN
    PERFORM app.update_contract_salary(
        p_contract_id := 1,
        p_new_salary_amount := 60000.00,
        p_reason := 'Демонстрационное обновление'
    );
    RAISE NOTICE 'Зарплата обновлена';
END $$;

-- Вызов 3: Успешная регистрация сессии
DO $$
DECLARE
    v_session_id INTEGER;
BEGIN
    SELECT app.register_recording_session(
        p_contract_id := 1,
        p_session_date := (CURRENT_DATE + INTERVAL '2 days')::DATE,
        p_session_time := '14:00:00'::TIME,
        p_studio_location := 'Студия Б, Москва',
        p_duration_hours := 3.5
    ) INTO v_session_id;
    
    RAISE NOTICE 'Зарегистрирована сессия ID: %', v_session_id;
END $$;

-- Вызов 4: Ошибка валидации (несуществующий проект)
DO $$
DECLARE
    v_error TEXT;
BEGIN
    BEGIN
        PERFORM app.create_contract(
            p_project_id := 99999,
            p_actor_id := 1,
            p_contract_number := 'DEMO-ERROR-001',
            p_role_description := 'Ошибочный контракт',
            p_salary_amount := 20000.00
        );
    EXCEPTION
        WHEN OTHERS THEN
            v_error := SQLERRM;
            RAISE NOTICE 'Ожидаемая ошибка: %', v_error;
    END;
END $$;

RESET ROLE;

-- =====================================================
-- ПРОСМОТР ЖУРНАЛА ВЫЗОВОВ
-- =====================================================

\echo ''
\echo '====================================================='
\echo 'ВСЕ ЗАПИСИ В ЖУРНАЛЕ ВЫЗОВОВ'
\echo '====================================================='

SET ROLE auditor;

SELECT 
    call_id,
    call_time,
    function_schema || '.' || function_name as function_full_name,
    caller_username,
    caller_role,
    success,
    error_message,
    execution_time_ms,
    client_ip
FROM audit.function_calls
ORDER BY call_time DESC
LIMIT 20;

\echo ''
\echo '====================================================='
\echo 'СТАТИСТИКА ПО ФУНКЦИЯМ'
\echo '====================================================='

SELECT 
    function_schema || '.' || function_name as function_name,
    COUNT(*) as total_calls,
    COUNT(*) FILTER (WHERE success = true) as successful_calls,
    COUNT(*) FILTER (WHERE success = false) as failed_calls,
    ROUND(AVG(execution_time_ms)::NUMERIC, 2) as avg_execution_time_ms,
    ROUND(MIN(execution_time_ms)::NUMERIC, 2) as min_execution_time_ms,
    ROUND(MAX(execution_time_ms)::NUMERIC, 2) as max_execution_time_ms
FROM audit.function_calls
WHERE function_schema = 'app'
GROUP BY function_schema, function_name
ORDER BY total_calls DESC;

\echo ''
\echo '====================================================='
\echo 'ПРИМЕРЫ ВХОДНЫХ ПАРАМЕТРОВ (JSON)'
\echo '====================================================='

SELECT 
    call_id,
    function_name,
    caller_username,
    input_params,
    return_value,
    success
FROM audit.function_calls
WHERE function_schema = 'app'
  AND input_params IS NOT NULL
ORDER BY call_time DESC
LIMIT 5;

\echo ''
\echo '====================================================='
\echo 'ПРИМЕРЫ ОШИБОК'
\echo '====================================================='

SELECT 
    call_id,
    call_time,
    function_name,
    caller_username,
    error_message,
    input_params
FROM audit.function_calls
WHERE success = false
ORDER BY call_time DESC
LIMIT 5;

RESET ROLE;

\echo ''
\echo '====================================================='
\echo 'ДЕМОНСТРАЦИЯ ЗАВЕРШЕНА!'
\echo '====================================================='
