-- =====================================================
-- ЛАБОРАТОРНАЯ РАБОТА №2
-- Главный скрипт инициализации
-- =====================================================

DO $$
BEGIN
    RAISE NOTICE '=====================================================';
    RAISE NOTICE 'НАЧАЛО ИНИЦИАЛИЗАЦИИ ЛАБОРАТОРНОЙ РАБОТЫ №2';
    RAISE NOTICE 'Точечное повышение привилегий и контроль бизнес-логики';
    RAISE NOTICE 'Время начала: %', NOW();
    RAISE NOTICE '=====================================================';
END $$;

-- Проверяем, что первая лабораторная выполнена
DO $$
DECLARE
    v_schema_count INTEGER;
    v_table_count INTEGER;
BEGIN
    -- Проверяем схемы
    SELECT COUNT(*) INTO v_schema_count 
    FROM information_schema.schemata 
    WHERE schema_name IN ('app', 'ref', 'audit', 'stg');
    
    -- Проверяем таблицы
    SELECT COUNT(*) INTO v_table_count 
    FROM information_schema.tables 
    WHERE table_schema IN ('app', 'ref', 'audit', 'stg')
      AND table_name IN ('actors', 'contracts', 'projects', 'login_log');
    
    IF v_schema_count < 4 THEN
        RAISE EXCEPTION 'ОШИБКА: Схемы из ЛР1 не найдены. Выполните сначала скрипты ЛР1!';
    END IF;
    
    IF v_table_count < 4 THEN
        RAISE EXCEPTION 'ОШИБКА: Таблицы из ЛР1 не найдены. Выполните сначала скрипты ЛР1!';
    END IF;
    
    RAISE NOTICE '✅ Проверка ЛР1 пройдена: схемы и таблицы найдены';
END $$;

-- Выполняем скрипты в порядке
-- Примечание: Для выполнения используйте psql с флагом -f для каждого скрипта
-- или выполните их последовательно вручную

DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE 'Выполнение скрипта 1: Создание таблицы журнала вызовов...';
    RAISE NOTICE 'Выполните: \i lr2_01_function_calls_log.sql';
    RAISE NOTICE '';
    RAISE NOTICE 'Выполнение скрипта 2: Создание SECURITY DEFINER-функций...';
    RAISE NOTICE 'Выполните: \i lr2_02_security_definer_functions.sql';
    RAISE NOTICE '';
    RAISE NOTICE 'Выполнение скрипта 3: Сравнение CHECK vs триггер...';
    RAISE NOTICE 'Выполните: \i lr2_03_check_vs_trigger.sql';
    RAISE NOTICE '';
    RAISE NOTICE 'Выполнение скрипта 4: Тесты прав доступа...';
    RAISE NOTICE 'Выполните: \i lr2_04_tests.sql';
    RAISE NOTICE '';
    RAISE NOTICE 'Выполнение скрипта 5: Демонстрация журнала вызовов...';
    RAISE NOTICE 'Выполните: \i lr2_05_demo_function_log.sql';
    RAISE NOTICE '';
    RAISE NOTICE 'Или выполните все скрипты одной командой:';
    RAISE NOTICE 'psql -U postgres -d dubbing_studio -f lr2_01_function_calls_log.sql';
    RAISE NOTICE 'psql -U postgres -d dubbing_studio -f lr2_02_security_definer_functions.sql';
    RAISE NOTICE 'psql -U postgres -d dubbing_studio -f lr2_03_check_vs_trigger.sql';
END $$;

-- Итоговая проверка
DO $$
DECLARE
    v_function_count INTEGER;
    v_log_table_exists BOOLEAN;
    v_test_table_check BOOLEAN;
    v_test_table_trigger BOOLEAN;
BEGIN
    -- Проверяем функции
    SELECT COUNT(*) INTO v_function_count
    FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE n.nspname = 'app'
      AND p.proname IN ('create_contract', 'update_contract_salary', 'register_recording_session');
    
    -- Проверяем таблицу журнала
    SELECT EXISTS (
        SELECT 1 FROM information_schema.tables 
        WHERE table_schema = 'audit' 
        AND table_name = 'function_calls'
    ) INTO v_log_table_exists;
    
    -- Проверяем тестовые таблицы
    SELECT EXISTS (
        SELECT 1 FROM information_schema.tables 
        WHERE table_schema = 'app' 
        AND table_name = 'contracts_check_test'
    ) INTO v_test_table_check;
    
    SELECT EXISTS (
        SELECT 1 FROM information_schema.tables 
        WHERE table_schema = 'app' 
        AND table_name = 'contracts_trigger_test'
    ) INTO v_test_table_trigger;
    
    RAISE NOTICE '';
    RAISE NOTICE '=====================================================';
    RAISE NOTICE 'ИТОГОВАЯ ПРОВЕРКА УСТАНОВКИ';
    RAISE NOTICE '=====================================================';
    RAISE NOTICE 'SECURITY DEFINER-функции: %/3', v_function_count;
    RAISE NOTICE 'Таблица журнала вызовов: %', CASE WHEN v_log_table_exists THEN '✅' ELSE '❌' END;
    RAISE NOTICE 'Тестовая таблица CHECK: %', CASE WHEN v_test_table_check THEN '✅' ELSE '❌' END;
    RAISE NOTICE 'Тестовая таблица TRIGGER: %', CASE WHEN v_test_table_trigger THEN '✅' ELSE '❌' END;
    
    IF v_function_count = 3 AND v_log_table_exists AND v_test_table_check AND v_test_table_trigger THEN
        RAISE NOTICE '';
        RAISE NOTICE '✅ ВСЕ КОМПОНЕНТЫ ЛР2 УСПЕШНО УСТАНОВЛЕНЫ!';
        RAISE NOTICE '';
        RAISE NOTICE 'Для запуска тестов производительности:';
        RAISE NOTICE '  SELECT * FROM app.test_performance_check_vs_trigger(10000);';
        RAISE NOTICE '';
        RAISE NOTICE 'Для просмотра журнала вызовов:';
        RAISE NOTICE '  SET ROLE auditor;';
        RAISE NOTICE '  SELECT * FROM audit.function_calls ORDER BY call_time DESC;';
    ELSE
        RAISE WARNING '⚠️  Некоторые компоненты не установлены полностью';
    END IF;
    
    RAISE NOTICE '=====================================================';
    RAISE NOTICE 'Время завершения: %', NOW();
    RAISE NOTICE '=====================================================';
END $$;
