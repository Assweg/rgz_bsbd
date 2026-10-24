-- =====================================================
-- РГЗ: Главный скрипт инициализации системы временных привилегий
-- =====================================================
-- Выполняет все скрипты РГЗ в правильном порядке

DO $$
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE 'РГЗ: Начало инициализации системы временных привилегий';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Время начала: %', NOW();
END $$;

-- Проверяем, что необходимые компоненты ЛР1-ЛР4 уже созданы
DO $$
DECLARE
    v_schema_count INTEGER;
    v_table_count INTEGER;
    v_function_count INTEGER;
BEGIN
    -- Проверяем схемы
    SELECT COUNT(*) INTO v_schema_count
    FROM information_schema.schemata
    WHERE schema_name IN ('app', 'ref', 'audit', 'stg');
    
    IF v_schema_count < 4 THEN
        RAISE EXCEPTION 'Не все необходимые схемы созданы. Сначала выполните скрипты ЛР1-ЛР4.';
    END IF;
    
    -- Проверяем таблицу function_calls (из ЛР2)
    SELECT COUNT(*) INTO v_function_count
    FROM information_schema.tables
    WHERE table_schema = 'audit' AND table_name = 'function_calls';
    
    IF v_function_count = 0 THEN
        RAISE EXCEPTION 'Таблица audit.function_calls не найдена. Сначала выполните скрипты ЛР2.';
    END IF;
    
    RAISE NOTICE '✅ Проверка зависимостей пройдена';
    RAISE NOTICE '   Схемы: %/4', v_schema_count;
    RAISE NOTICE '   Таблица function_calls: найдена';
END $$;

-- Выполняем скрипты РГЗ
-- ВНИМАНИЕ: Этот файл предназначен для ручного запуска через psql
-- Для автоматического запуска используйте: ./rgz_run_all.sh

DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE 'ВНИМАНИЕ: Для выполнения скриптов РГЗ используйте:';
    RAISE NOTICE '  \i rgz_01_temp_privileges.sql';
    RAISE NOTICE '  \i rgz_02_safe_delete_functions.sql';
    RAISE NOTICE '  \i rgz_03_tests.sql';
    RAISE NOTICE '';
    RAISE NOTICE 'Или запустите автоматический скрипт: ./rgz_run_all.sh';
END $$;

DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'РГЗ: Инициализация завершена';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Время завершения: %', NOW();
    RAISE NOTICE '';
    RAISE NOTICE 'Созданные компоненты:';
    RAISE NOTICE '  ✅ Таблица audit.temp_access_log';
    RAISE NOTICE '  ✅ Таблица audit.allowed_temp_operations';
    RAISE NOTICE '  ✅ Функция app.request_temp_privilege()';
    RAISE NOTICE '  ✅ Функция audit.check_temp_privilege()';
    RAISE NOTICE '  ✅ Функция app.safe_delete_contract()';
    RAISE NOTICE '  ✅ Функция app.safe_delete_actor()';
    RAISE NOTICE '  ✅ Функция app.safe_delete_recording_session()';
    RAISE NOTICE '';
    RAISE NOTICE 'Для использования:';
    RAISE NOTICE '  1. SET ROLE app_writer;';
    RAISE NOTICE '  2. PERFORM app.set_session_ctx(1, NULL);';
    RAISE NOTICE '  3. PERFORM app.request_temp_privilege(''delete_contract'', 5);';
    RAISE NOTICE '  4. PERFORM app.safe_delete_contract(contract_id);';
END $$;

