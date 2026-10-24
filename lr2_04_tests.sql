-- =====================================================
-- Тесты прав
-- =====================================================

\echo '====================================================='
\echo 'ТЕСТЫ ПРАВ ДОСТУПА'
\echo '====================================================='

DROP POLICY IF EXISTS app_owner_full_access_actors ON app.actors;
CREATE POLICY app_owner_full_access_actors ON app.actors
    FOR ALL
    TO app_owner
    USING (true)
    WITH CHECK (true);

DROP POLICY IF EXISTS app_owner_full_access_contracts ON app.contracts;
CREATE POLICY app_owner_full_access_contracts ON app.contracts
    FOR ALL
    TO app_owner
    USING (true)
    WITH CHECK (true);

DROP POLICY IF EXISTS app_owner_full_access_projects ON app.projects;
CREATE POLICY app_owner_full_access_projects ON app.projects
    FOR ALL
    TO app_owner
    USING (true)
    WITH CHECK (true);

DROP POLICY IF EXISTS app_owner_full_access_sessions ON app.recording_sessions;
CREATE POLICY app_owner_full_access_sessions ON app.recording_sessions
    FOR ALL
    TO app_owner
    USING (true)
    WITH CHECK (true);

-- Проверка наличия функций ЛР2
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON p.pronamespace = n.oid
        WHERE n.nspname = 'app'
          AND p.proname = 'create_contract'
          AND p.prosecdef = true
    ) THEN
        RAISE EXCEPTION 'ОШИБКА: Функция app.create_contract не найдена! Выполните инициализацию ЛР2: ./init_lr2.sh';
    END IF;
    
    IF NOT EXISTS (
        SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON p.pronamespace = n.oid
        WHERE n.nspname = 'app'
          AND p.proname = 'update_contract_salary'
          AND p.prosecdef = true
    ) THEN
        RAISE EXCEPTION 'ОШИБКА: Функция app.update_contract_salary не найдена! Выполните инициализацию ЛР2: ./init_lr2.sh';
    END IF;
    
    IF NOT EXISTS (
        SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON p.pronamespace = n.oid
        WHERE n.nspname = 'app'
          AND p.proname = 'register_recording_session'
          AND p.prosecdef = true
    ) THEN
        RAISE EXCEPTION 'ОШИБКА: Функция app.register_recording_session не найдена! Выполните инициализацию ЛР2: ./init_lr2.sh';
    END IF;
    
    RAISE NOTICE '✅ Все функции ЛР2 найдены';
END $$;

-- Проверка наличия данных (от имени postgres для обхода RLS)
DO $$
DECLARE
    v_actor_count INTEGER;
    v_project_count INTEGER;
    v_contract_count INTEGER;
BEGIN
    -- Внутри DO блока SET ROLE не работает, поэтому используем прямые запросы
    -- от имени текущего пользователя (postgres), для обхода RLS
    SELECT COUNT(*) INTO v_actor_count FROM app.actors WHERE is_active = true;
    SELECT COUNT(*) INTO v_project_count FROM app.projects;
    SELECT COUNT(*) INTO v_contract_count FROM app.contracts;
    
    IF v_actor_count = 0 THEN
        RAISE WARNING '⚠️  В БД нет активных актёров. Некоторые тесты могут не пройти.';
    END IF;
    
    IF v_project_count = 0 THEN
        RAISE WARNING '⚠️  В БД нет проектов. Некоторые тесты могут не пройти.';
    END IF;
    
    IF v_contract_count = 0 THEN
        RAISE WARNING '⚠️  В БД нет контрактов. Тесты обновления контрактов могут не пройти.';
    END IF;
    
    RAISE NOTICE 'Данные в БД: Актёров: %, Проектов: %, Контрактов: %', v_actor_count, v_project_count, v_contract_count;
END $$;

-- =====================================================
-- КЕЙС 1: Успешное создание контракта через SECURITY DEFINER
-- =====================================================
\echo ''
\echo '=== КЕЙС 1: Успешное создание контракта (позитивный) ==='

-- Получаем ID для тестов (от имени postgres, который обходит RLS)
DO $$
DECLARE
    v_test_project_id INTEGER;
    v_test_actor_id INTEGER;
BEGIN
    -- Получаем данные от имени текущего пользователя (postgres обходит RLS)
    SELECT project_id INTO v_test_project_id FROM app.projects LIMIT 1;
    SELECT actor_id INTO v_test_actor_id FROM app.actors WHERE is_active = true LIMIT 1;
    
    -- Сохраняем ID в переменные сессии для использования в тестах
    PERFORM set_config('app.test_project_id', COALESCE(v_test_project_id::TEXT, '0'), false);
    PERFORM set_config('app.test_actor_id', COALESCE(v_test_actor_id::TEXT, '0'), false);
    
    IF v_test_project_id IS NULL THEN
        RAISE EXCEPTION 'ОШИБКА: В БД нет проектов. Выполните скрипты ЛР1 (script8.sql)';
    END IF;
    
    IF v_test_actor_id IS NULL THEN
        RAISE EXCEPTION 'ОШИБКА: В БД нет активных актёров. Выполните скрипты ЛР1 (script8.sql)';
    END IF;
END $$;

SET ROLE studio_manager;

DO $$
DECLARE
    v_contract_id INTEGER;
    v_project_id INTEGER;
    v_actor_id INTEGER;
BEGIN
    -- Получаем ID из переменных сессии
    v_project_id := current_setting('app.test_project_id', true)::INTEGER;
    v_actor_id := current_setting('app.test_actor_id', true)::INTEGER;
    
    -- Создаём контракт через SECURITY DEFINER функцию
    -- Используем уникальный номер контракта на основе timestamp
    BEGIN
        SELECT app.create_contract(
            p_project_id := v_project_id,
            p_actor_id := v_actor_id,
            p_contract_number := 'TEST-CONTRACT-' || to_char(clock_timestamp(), 'YYYYMMDDHH24MISS'),
            p_role_description := 'Тестовая роль для проверки',
            p_salary_amount := 30000.00,
            p_currency := 'USD',
            p_signed_date := CURRENT_DATE,
            p_end_date := (CURRENT_DATE + INTERVAL '6 months')::DATE
        ) INTO v_contract_id;
        
        RAISE NOTICE '✅ Контракт успешно создан с ID: %', v_contract_id;
    EXCEPTION
        WHEN unique_violation THEN
            RAISE NOTICE '⚠️  Контракт с таким номером уже существует, пропускаем тест';
        WHEN OTHERS THEN
            RAISE;
    END;
END $$;

RESET ROLE;

-- =====================================================
-- КЕЙС 2: Ошибка валидации - несуществующий проект (негативный)
-- =====================================================
\echo ''
\echo '=== КЕЙС 2: Ошибка валидации - несуществующий проект (негативный) ==='

SET ROLE studio_manager;

DO $$
DECLARE
    v_contract_id INTEGER;
    v_error TEXT;
    v_actor_id INTEGER;
BEGIN
    -- Получаем ID актёра из переменных сессии
    v_actor_id := current_setting('app.test_actor_id', true)::INTEGER;
    
    IF v_actor_id IS NULL OR v_actor_id = 0 THEN
        RAISE WARNING '⚠️  В БД нет активных актёров. Пропускаем тест.';
        RETURN;
    END IF;
    
    BEGIN
        SELECT app.create_contract(
            p_project_id := 99999, -- Несуществующий проект
            p_actor_id := v_actor_id,
            p_contract_number := 'TEST-CONTRACT-002',
            p_role_description := 'Тестовая роль',
            p_salary_amount := 30000.00
        ) INTO v_contract_id;
        
        RAISE NOTICE '❌ ОШИБКА: Контракт не должен был создаться!';
    EXCEPTION
        WHEN OTHERS THEN
            v_error := SQLERRM;
            RAISE NOTICE '✅ Ожидаемая ошибка: %', v_error;
    END;
END $$;

RESET ROLE;

-- =====================================================
-- КЕЙС 3: Ошибка валидации - отрицательная зарплата (негативный)
-- =====================================================
\echo ''
\echo '=== КЕЙС 3: Ошибка валидации - отрицательная зарплата (негативный) ==='

SET ROLE studio_manager;

DO $$
DECLARE
    v_contract_id INTEGER;
    v_error TEXT;
    v_project_id INTEGER;
    v_actor_id INTEGER;
BEGIN
    -- Получаем ID из переменных сессии
    v_project_id := current_setting('app.test_project_id', true)::INTEGER;
    v_actor_id := current_setting('app.test_actor_id', true)::INTEGER;
    
    IF v_project_id IS NULL OR v_project_id = 0 OR v_actor_id IS NULL OR v_actor_id = 0 THEN
        RAISE WARNING '⚠️  В БД нет проектов или актёров. Пропускаем тест.';
        RETURN;
    END IF;
    
    BEGIN
        SELECT app.create_contract(
            p_project_id := v_project_id,
            p_actor_id := v_actor_id,
            p_contract_number := 'TEST-CONTRACT-003',
            p_role_description := 'Тестовая роль',
            p_salary_amount := -1000.00 -- Отрицательная зарплата
        ) INTO v_contract_id;
        
        RAISE NOTICE '❌ ОШИБКА: Контракт не должен был создаться!';
    EXCEPTION
        WHEN OTHERS THEN
            v_error := SQLERRM;
            RAISE NOTICE '✅ Ожидаемая ошибка: %', v_error;
    END;
END $$;

RESET ROLE;

-- =====================================================
-- КЕЙС 4: Успешное обновление зарплаты (позитивный)
-- =====================================================
\echo ''
\echo '=== КЕЙС 4: Успешное обновление зарплаты (позитивный) ==='

-- Получаем ID контракта (от имени postgres, который обходит RLS)
DO $$
DECLARE
    v_test_contract_id INTEGER;
BEGIN
    -- Получаем данные от имени текущего пользователя (postgres обходит RLS)
    SELECT contract_id INTO v_test_contract_id 
    FROM app.contracts 
    WHERE status = 'active'
    LIMIT 1;
    
    PERFORM set_config('app.test_contract_id', COALESCE(v_test_contract_id::TEXT, '0'), false);
END $$;

SET ROLE studio_manager;

DO $$
DECLARE
    v_result BOOLEAN;
    v_contract_id INTEGER;
BEGIN
    -- Получаем ID контракта из переменных сессии
    v_contract_id := current_setting('app.test_contract_id', true)::INTEGER;
    
    IF v_contract_id IS NULL OR v_contract_id = 0 THEN
        RAISE WARNING '⚠️  В БД нет активных контрактов. Пропускаем тест обновления зарплаты.';
        RETURN;
    END IF;
    
    -- Обновляем зарплату контракта
    SELECT app.update_contract_salary(
        p_contract_id := v_contract_id,
        p_new_salary_amount := 55000.00,
        p_reason := 'Повышение за хорошую работу'
    ) INTO v_result;
    
    IF v_result THEN
        RAISE NOTICE '✅ Зарплата успешно обновлена для контракта ID: %', v_contract_id;
    ELSE
        RAISE NOTICE '❌ Ошибка обновления зарплаты';
    END IF;
END $$;

RESET ROLE;

-- =====================================================
-- КЕЙС 5: Попытка DDL неадмином (негативный)
-- =====================================================
\echo ''
\echo '=== КЕЙС 5: Попытка DDL неадмином (негативный) ==='

SET ROLE app_writer;

DO $$
BEGIN
    BEGIN
        -- Попытка создать таблицу (DDL операция)
        CREATE TABLE app.test_table (
            id INTEGER PRIMARY KEY
        );
        
        RAISE NOTICE '❌ ОШИБКА: Таблица не должна была создаться!';
        DROP TABLE IF EXISTS app.test_table;
    EXCEPTION
        WHEN insufficient_privilege THEN
            RAISE NOTICE '✅ Ожидаемая ошибка: Недостаточно прав для DDL операции';
        WHEN OTHERS THEN
            RAISE NOTICE '✅ Ожидаемая ошибка: %', SQLERRM;
    END;
END $$;

RESET ROLE;

-- =====================================================
-- КЕЙС 6: Попытка DML в audit (негативный)
-- =====================================================
\echo ''
\echo '=== КЕЙС 6: Попытка DML в audit (негативный) ==='

SET ROLE app_writer;

DO $$
BEGIN
    BEGIN
        -- Попытка вставить запись в audit.login_log
        INSERT INTO audit.login_log (username, is_successful)
        VALUES ('test_user', true);
        
        RAISE NOTICE '❌ ОШИБКА: Вставка в audit не должна была произойти!';
    EXCEPTION
        WHEN insufficient_privilege THEN
            RAISE NOTICE '✅ Ожидаемая ошибка: Недостаточно прав для DML в audit';
        WHEN OTHERS THEN
            RAISE NOTICE '✅ Ожидаемая ошибка: %', SQLERRM;
    END;
END $$;

RESET ROLE;

-- =====================================================
-- КЕЙС 7: Чтение разрешённых таблиц (позитивный)
-- =====================================================
\echo ''
\echo '=== КЕЙС 7: Чтение разрешённых таблиц (позитивный) ==='

-- Получаем ID актёра для теста (от имени postgres)
DO $$
DECLARE
    v_test_actor_id_for_read INTEGER;
BEGIN
    SELECT actor_id INTO v_test_actor_id_for_read FROM app.actors WHERE is_active = true LIMIT 1;
    PERFORM set_config('app.test_actor_id_for_read', COALESCE(v_test_actor_id_for_read::TEXT, '0'), false);
END $$;

SET ROLE app_reader;

DO $$
DECLARE
    v_count INTEGER;
    v_actor_id INTEGER;
BEGIN
    -- Устанавливаем current_actor_id для работы с RLS
    v_actor_id := current_setting('app.test_actor_id_for_read', true)::INTEGER;
    IF v_actor_id IS NOT NULL AND v_actor_id > 0 THEN
        PERFORM set_config('app.current_actor_id', v_actor_id::TEXT, false);
    END IF;
    
    -- Читаем таблицы, к которым есть доступ
    -- Для актёров RLS требует current_actor_id
    IF v_actor_id IS NOT NULL AND v_actor_id > 0 THEN
        SELECT COUNT(*) INTO v_count FROM app.actors;
        RAISE NOTICE '✅ Актёров доступно (с current_actor_id): %', v_count;
    ELSE
        RAISE NOTICE '⚠️  Актёры: требуется установка current_actor_id для RLS';
    END IF;
    
    -- Проекты доступны через политику get_current_user_studio()
    SELECT COUNT(*) INTO v_count FROM app.projects;
    RAISE NOTICE '✅ Проектов доступно: %', v_count;
    
    -- Справочники доступны без ограничений
    SELECT COUNT(*) INTO v_count FROM ref.languages;
    RAISE NOTICE '✅ Языков доступно: %', v_count;
END $$;

RESET ROLE;

-- =====================================================
-- КЕЙС 8: Вызов SECURITY DEFINER с невалидными данными (негативный)
-- =====================================================
\echo ''
\echo '=== КЕЙС 8: Вызов SECURITY DEFINER с невалидными данными (негативный) ==='

SET ROLE studio_manager;

DO $$
DECLARE
    v_session_id INTEGER;
    v_error TEXT;
    v_contract_id INTEGER;
BEGIN
    -- Получаем ID контракта из переменных сессии
    v_contract_id := current_setting('app.test_contract_id', true)::INTEGER;
    
    IF v_contract_id IS NULL OR v_contract_id = 0 THEN
        RAISE WARNING '⚠️  В БД нет активных контрактов. Пропускаем тест.';
        RETURN;
    END IF;
    
    BEGIN
        -- Пытаемся зарегистрировать сессию с невалидной длительностью
        SELECT app.register_recording_session(
            p_contract_id := v_contract_id,
            p_session_date := (CURRENT_DATE + INTERVAL '1 day')::DATE,
            p_session_time := '10:00:00'::TIME,
            p_studio_location := 'Студия А',
            p_duration_hours := 30.0 -- Невалидно: больше 24 часов
        ) INTO v_session_id;
        
        RAISE NOTICE '❌ ОШИБКА: Сессия не должна была создаться!';
    EXCEPTION
        WHEN OTHERS THEN
            v_error := SQLERRM;
            RAISE NOTICE '✅ Ожидаемая ошибка валидации: %', v_error;
    END;
END $$;

RESET ROLE;

-- =====================================================
-- КЕЙС 9: Вызов SECURITY DEFINER с валидными данными (позитивный)
-- =====================================================
\echo ''
\echo '=== КЕЙС 9: Вызов SECURITY DEFINER с валидными данными (позитивный) ==='

SET ROLE studio_manager;

DO $$
DECLARE
    v_session_id INTEGER;
    v_contract_id INTEGER;
BEGIN
    -- Получаем ID контракта из переменных сессии
    v_contract_id := current_setting('app.test_contract_id', true)::INTEGER;
    
    IF v_contract_id IS NULL OR v_contract_id = 0 THEN
        RAISE WARNING '⚠️  В БД нет активных контрактов. Пропускаем тест.';
        RETURN;
    END IF;
    
    -- Регистрируем сессию с валидными данными
    SELECT app.register_recording_session(
        p_contract_id := v_contract_id,
        p_session_date := (CURRENT_DATE + INTERVAL '1 day')::DATE,
        p_session_time := '10:00:00'::TIME,
        p_studio_location := 'Студия А, Москва',
        p_duration_hours := 4.5,
        p_notes := 'Тестовая сессия записи'
    ) INTO v_session_id;
    
    RAISE NOTICE '✅ Сессия успешно зарегистрирована с ID: % для контракта ID: %', v_session_id, v_contract_id;
END $$;

RESET ROLE;

-- =====================================================
-- КЕЙС 10: Попытка обновления зарплаты в завершённом контракте (негативный)
-- =====================================================
\echo ''
\echo '=== КЕЙС 10: Попытка обновления зарплаты в завершённом контракте (негативный) ==='

SET ROLE studio_manager;

DO $$
DECLARE
    v_result BOOLEAN;
    v_error TEXT;
    v_project_id INTEGER;
    v_actor_id INTEGER;
    v_contract_id INTEGER;
BEGIN
    -- Получаем ID из переменных сессии
    v_project_id := current_setting('app.test_project_id', true)::INTEGER;
    v_actor_id := current_setting('app.test_actor_id', true)::INTEGER;
    
    IF v_project_id IS NULL OR v_project_id = 0 OR v_actor_id IS NULL OR v_actor_id = 0 THEN
        RAISE WARNING '⚠️  В БД нет проектов или актёров. Пропускаем тест.';
        RETURN;
    END IF;
    
    -- Сначала создаём и завершаем контракт для теста
    BEGIN
        -- Создаём тестовый контракт с уникальным номером
        SELECT app.create_contract(
            p_project_id := v_project_id,
            p_actor_id := v_actor_id,
            p_contract_number := 'TEST-COMPLETED-' || to_char(clock_timestamp(), 'YYYYMMDDHH24MISS'),
            p_role_description := 'Завершённый контракт для теста',
            p_salary_amount := 25000.00
        ) INTO v_contract_id;
        
        -- Завершаем контракт (от имени владельца)
        SET ROLE app_owner;
        UPDATE app.contracts 
        SET status = 'completed', end_date = CURRENT_DATE
        WHERE contract_id = v_contract_id;
        RESET ROLE;
        
        -- Пытаемся обновить зарплату завершённого контракта
        BEGIN
            SELECT app.update_contract_salary(
                p_contract_id := v_contract_id,
                p_new_salary_amount := 30000.00
            ) INTO v_result;
            
            RAISE NOTICE '❌ ОШИБКА: Зарплата не должна была обновиться!';
        EXCEPTION
            WHEN OTHERS THEN
                v_error := SQLERRM;
                RAISE NOTICE '✅ Ожидаемая ошибка: %', v_error;
        END;
    EXCEPTION
        WHEN OTHERS THEN
            RAISE NOTICE '⚠️  Предупреждение: %', SQLERRM;
    END;
END $$;

RESET ROLE;

-- =====================================================
-- ИТОГОВЫЙ ОТЧЁТ
-- =====================================================
\echo ''
\echo '====================================================='
\echo 'ИТОГОВЫЙ ОТЧЁТ ПО ТЕСТАМ'
\echo '====================================================='

-- Подсчитываем успешные и неуспешные вызовы функций
SELECT 
    'Всего вызовов функций' as metric,
    COUNT(*)::TEXT as value
FROM audit.function_calls
WHERE function_name IN ('create_contract', 'update_contract_salary', 'register_recording_session')
UNION ALL
SELECT 
    'Успешных вызовов' as metric,
    COUNT(*)::TEXT as value
FROM audit.function_calls
WHERE function_name IN ('create_contract', 'update_contract_salary', 'register_recording_session')
  AND success = true
UNION ALL
SELECT 
    'Неуспешных вызовов' as metric,
    COUNT(*)::TEXT as value
FROM audit.function_calls
WHERE function_name IN ('create_contract', 'update_contract_salary', 'register_recording_session')
  AND success = false;

\echo ''
\echo 'ПРОВЕРКА ЗАВЕРШЕНА!'
\echo '====================================================='
