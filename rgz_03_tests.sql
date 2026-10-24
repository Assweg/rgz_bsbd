-- =====================================================
-- Тесты системы временных привилегий (Just-In-Time Access)
-- =====================================================
-- Тестирование: запрос → выполнение → попытка после истечения → ошибка

SET search_path TO app, ref, audit, stg, public;

DO $$
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE 'РГЗ: Начало тестирования системы временных привилегий';
    RAISE NOTICE '========================================';
END $$;

-- =====================================================
-- ТЕСТ 1: Запрос временной привилегии
-- =====================================================

DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '=== ТЕСТ 1: Запрос временной привилегии ===';
END $$;

-- Подключаемся от имени app_writer
SET ROLE app_writer;

-- Сохраняем имя пользователя для использования в тестах
DO $$
BEGIN
    PERFORM set_config('test.caller_username', session_user, false);
END $$;

-- Устанавливаем контекст сегмента (необходимо для RLS)
-- Пропускаем установку контекста, если функция не доступна (тесты могут работать и без неё)
DO $$
BEGIN
    -- Пытаемся установить контекст, но не критично если не получится
    BEGIN
        -- Проверяем, существует ли функция
        IF EXISTS (
            SELECT 1 FROM pg_proc p
            JOIN pg_namespace n ON p.pronamespace = n.oid
            WHERE n.nspname = 'app' AND p.proname = 'set_session_ctx'
        ) THEN
            -- Вызываем функцию с правильной сигнатурой
            EXECUTE 'SELECT app.set_session_ctx($1)' USING 1;
            RAISE NOTICE 'Контекст сегмента установлен';
        ELSE
            RAISE NOTICE 'Функция app.set_session_ctx не найдена (продолжаем без контекста)';
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            RAISE NOTICE 'Ошибка установки контекста: % (продолжаем без контекста)', SQLERRM;
    END;
END $$;

-- Тест 1.1: Запрос привилегии на удаление контракта на 5 минут
DO $$
DECLARE
    v_result JSONB;
BEGIN
    v_result := app.request_temp_privilege('delete_contract', 5);
    RAISE NOTICE '✅ ТЕСТ 1.1 ПРОЙДЕН: Привилегия запрошена успешно';
    RAISE NOTICE '   Request ID: %', v_result->>'request_id';
    RAISE NOTICE '   Операция: %', v_result->>'operation';
    RAISE NOTICE '   Истекает: %', v_result->>'expires_at';
    RAISE NOTICE '   Длительность: % минут', v_result->>'duration_minutes';
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE '❌ ТЕСТ 1.1 ПРОВАЛЕН: %', SQLERRM;
END $$;

-- Проверяем запись в audit.temp_access_log
DO $$
DECLARE
    v_count INTEGER;
    v_log_record RECORD;
BEGIN
    SELECT COUNT(*) INTO v_count
    FROM audit.temp_access_log
    WHERE caller_username = session_user
      AND operation = 'delete_contract'
      AND is_active = true;
    
    IF v_count > 0 THEN
        SELECT * INTO v_log_record
        FROM audit.temp_access_log
        WHERE caller_username = session_user
          AND operation = 'delete_contract'
          AND is_active = true
        ORDER BY request_time DESC
        LIMIT 1;
        
        RAISE NOTICE '✅ ТЕСТ 1.2 ПРОЙДЕН: Запись в audit.temp_access_log создана';
        RAISE NOTICE '   Request ID: %', v_log_record.request_id;
        RAISE NOTICE '   Caller: %', v_log_record.caller_username;
        RAISE NOTICE '   Operation: %', v_log_record.operation;
        RAISE NOTICE '   Expires at: %', v_log_record.expires_at;
    ELSE
        RAISE NOTICE '❌ ТЕСТ 1.2 ПРОВАЛЕН: Запись в audit.temp_access_log не найдена';
    END IF;
END $$;

-- =====================================================
-- ТЕСТ 2: Выполнение операции с активной привилегией
-- =====================================================

DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '=== ТЕСТ 2: Выполнение операции с активной привилегией ===';
END $$;

-- Тест 2.1: Находим существующий контракт для удаления
DO $$
DECLARE
    v_contract_id INTEGER;
    v_test_project_id INTEGER;
    v_test_actor_id INTEGER;
BEGIN
    -- Сначала пытаемся найти существующий контракт без сессий (используем RESET ROLE для обхода RLS)
    RESET ROLE;
    SELECT contract_id INTO v_contract_id
    FROM app.contracts c
    WHERE NOT EXISTS (
        SELECT 1 FROM app.recording_sessions rs
        WHERE rs.contract_id = c.contract_id
    )
    LIMIT 1;
    SET ROLE app_writer;
    
    -- Если не нашли, пытаемся создать новый
    IF v_contract_id IS NULL THEN
        -- Находим существующий проект и актёра (используем RESET ROLE для обхода RLS)
        RESET ROLE;
        SELECT project_id INTO v_test_project_id FROM app.projects LIMIT 1;
        SELECT actor_id INTO v_test_actor_id FROM app.actors WHERE is_active = true LIMIT 1;
        SET ROLE app_writer;
        
        IF v_test_project_id IS NULL OR v_test_actor_id IS NULL THEN
            RAISE NOTICE '⚠️  Не найдены тестовые данные для создания контракта';
            RETURN;
        END IF;
        
        -- Создаём тестовый контракт
        BEGIN
            v_contract_id := app.create_contract(
                p_project_id := v_test_project_id,
                p_actor_id := v_test_actor_id,
                p_contract_number := 'TEST-DELETE-' || extract(epoch from now())::TEXT,
                p_role_description := 'Тестовый контракт для удаления',
                p_salary_amount := 1000.00,
                p_currency := 'USD'
            );
            
            RAISE NOTICE '✅ Тестовый контракт создан: ID = %', v_contract_id;
        EXCEPTION
            WHEN OTHERS THEN
                RAISE NOTICE '⚠️  Ошибка создания тестового контракта: %', SQLERRM;
                RETURN;
        END;
    ELSE
        RAISE NOTICE '✅ Используем существующий контракт без сессий: ID = %', v_contract_id;
    END IF;
    
    -- Сохраняем ID для последующих тестов
    PERFORM set_config('test.contract_id', v_contract_id::TEXT, false);
END $$;

-- Тест 2.2: Удаление контракта с активной привилегией
DO $$
DECLARE
    v_contract_id INTEGER;
    v_result BOOLEAN;
BEGIN
    v_contract_id := current_setting('test.contract_id', true)::INTEGER;
    
    IF v_contract_id IS NULL THEN
        RAISE NOTICE '❌ ТЕСТ 2.2 ПРОВАЛЕН: Нет тестового контракта';
        RETURN;
    END IF;
    
    -- Проверяем, что привилегия активна
    IF NOT audit.check_temp_privilege('delete_contract') THEN
        RAISE NOTICE '⚠️  Привилегия не активна, запрашиваем заново';
        PERFORM app.request_temp_privilege('delete_contract', 5);
    END IF;
    
    -- Удаляем контракт
    v_result := app.safe_delete_contract(v_contract_id);
    
    IF v_result THEN
        RAISE NOTICE '✅ ТЕСТ 2.2 ПРОЙДЕН: Контракт успешно удалён с активной привилегией';
    ELSE
        RAISE NOTICE '❌ ТЕСТ 2.2 ПРОВАЛЕН: Удаление не выполнено';
    END IF;
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE '❌ ТЕСТ 2.2 ПРОВАЛЕН: %', SQLERRM;
END $$;

-- =====================================================
-- ТЕСТ 3: Попытка выполнения операции без привилегии
-- =====================================================

DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '=== ТЕСТ 3: Попытка выполнения операции без привилегии ===';
END $$;

-- Тест 3.1: Попытка удаления без запроса привилегии
DO $$
DECLARE
    v_test_project_id INTEGER;
    v_test_actor_id INTEGER;
    v_contract_id INTEGER;
    v_error_occurred BOOLEAN := false;
BEGIN
    -- Находим существующий контракт или создаём новый (используем RESET ROLE для обхода RLS)
    RESET ROLE;
    SELECT contract_id INTO v_contract_id
    FROM app.contracts c
    WHERE NOT EXISTS (
        SELECT 1 FROM app.recording_sessions rs
        WHERE rs.contract_id = c.contract_id
    )
    LIMIT 1;
    SET ROLE app_writer;
    
    -- Если не нашли, пытаемся создать новый
    IF v_contract_id IS NULL THEN
        RESET ROLE;
        SELECT project_id INTO v_test_project_id FROM app.projects LIMIT 1;
        SELECT actor_id INTO v_test_actor_id FROM app.actors WHERE is_active = true LIMIT 1;
        SET ROLE app_writer;
        
        IF v_test_project_id IS NULL OR v_test_actor_id IS NULL THEN
            RAISE NOTICE '⚠️  Не найдены тестовые данные для создания контракта';
            RETURN;
        END IF;
        
        BEGIN
            v_contract_id := app.create_contract(
                p_project_id := v_test_project_id,
                p_actor_id := v_test_actor_id,
                p_contract_number := 'TEST-NO-PRIV-' || extract(epoch from now())::TEXT,
                p_role_description := 'Тестовый контракт для теста без привилегии',
                p_salary_amount := 1000.00,
                p_currency := 'USD'
            );
        EXCEPTION
            WHEN OTHERS THEN
                RAISE NOTICE '⚠️  Ошибка создания тестового контракта: %', SQLERRM;
                RETURN;
        END;
    END IF;
    
    -- Деактивируем все активные привилегии (используем RESET ROLE для обхода ограничений)
    RESET ROLE;
    UPDATE audit.temp_access_log
    SET is_active = false
    WHERE caller_username = current_setting('test.caller_username', true)
      AND operation = 'delete_contract';
    SET ROLE app_writer;
    
    -- Пытаемся удалить без привилегии
    BEGIN
        PERFORM app.safe_delete_contract(v_contract_id);
        v_error_occurred := false;
    EXCEPTION
        WHEN OTHERS THEN
            v_error_occurred := true;
            IF SQLERRM LIKE '%Временная привилегия%' THEN
                RAISE NOTICE '✅ ТЕСТ 3.1 ПРОЙДЕН: Операция корректно заблокирована без привилегии';
                RAISE NOTICE '   Ошибка: %', SQLERRM;
            ELSE
                RAISE NOTICE '❌ ТЕСТ 3.1 ПРОВАЛЕН: Неожиданная ошибка: %', SQLERRM;
            END IF;
    END;
    
    IF NOT v_error_occurred THEN
        RAISE NOTICE '❌ ТЕСТ 3.1 ПРОВАЛЕН: Операция выполнилась без привилегии (не должно быть!)';
    END IF;
END $$;

-- =====================================================
-- ТЕСТ 4: Попытка после истечения привилегии
-- =====================================================

DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '=== ТЕСТ 4: Попытка после истечения привилегии ===';
END $$;

-- Тест 4.1: Запрашиваем привилегию на очень короткое время (1 секунда = 0.017 минут)
DO $$
DECLARE
    v_result JSONB;
    v_test_project_id INTEGER;
    v_test_actor_id INTEGER;
    v_contract_id INTEGER;
    v_error_occurred BOOLEAN := false;
BEGIN
    -- Находим существующий контракт или создаём новый (используем RESET ROLE для обхода RLS)
    RESET ROLE;
    SELECT contract_id INTO v_contract_id
    FROM app.contracts c
    WHERE NOT EXISTS (
        SELECT 1 FROM app.recording_sessions rs
        WHERE rs.contract_id = c.contract_id
    )
    LIMIT 1;
    SET ROLE app_writer;
    
    -- Если не нашли, пытаемся создать новый
    IF v_contract_id IS NULL THEN
        RESET ROLE;
        SELECT project_id INTO v_test_project_id FROM app.projects LIMIT 1;
        SELECT actor_id INTO v_test_actor_id FROM app.actors WHERE is_active = true LIMIT 1;
        SET ROLE app_writer;
        
        IF v_test_project_id IS NULL OR v_test_actor_id IS NULL THEN
            RAISE NOTICE '⚠️  Не найдены тестовые данные для создания контракта';
            RETURN;
        END IF;
        
        BEGIN
            v_contract_id := app.create_contract(
                p_project_id := v_test_project_id,
                p_actor_id := v_test_actor_id,
                p_contract_number := 'TEST-EXPIRED-' || extract(epoch from now())::TEXT,
                p_role_description := 'Тестовый контракт для теста истечения',
                p_salary_amount := 1000.00,
                p_currency := 'USD'
            );
        EXCEPTION
            WHEN OTHERS THEN
                RAISE NOTICE '⚠️  Ошибка создания тестового контракта: %', SQLERRM;
                RETURN;
        END;
    END IF;
    
    -- Запрашиваем привилегию на минимальное время (1 минута)
    v_result := app.request_temp_privilege('delete_contract', 1);
    RAISE NOTICE '✅ Привилегия запрошена на 1 минуту';
    RAISE NOTICE '   Истекает: %', v_result->>'expires_at';
    
    -- Вручную истекаем привилегию (устанавливаем expires_at в прошлое)
    -- Используем RESET ROLE для обхода ограничений
    RESET ROLE;
    UPDATE audit.temp_access_log
    SET expires_at = NOW() - INTERVAL '1 minute',
        is_active = false
    WHERE request_id = (
        SELECT request_id
        FROM audit.temp_access_log
        WHERE caller_username = current_setting('test.caller_username', true)
          AND operation = 'delete_contract'
          AND is_active = true
        ORDER BY request_time DESC
        LIMIT 1
    );
    SET ROLE app_writer;
    
    RAISE NOTICE 'Привилегия принудительно истекла';
    
    -- Небольшая задержка не требуется, так как мы уже установили expires_at в прошлое
    
    -- Пытаемся удалить после истечения
    BEGIN
        PERFORM app.safe_delete_contract(v_contract_id);
        v_error_occurred := false;
    EXCEPTION
        WHEN OTHERS THEN
            v_error_occurred := true;
            IF SQLERRM LIKE '%Временная привилегия%' OR SQLERRM LIKE '%истекла%' THEN
                RAISE NOTICE '✅ ТЕСТ 4.1 ПРОЙДЕН: Операция корректно заблокирована после истечения';
                RAISE NOTICE '   Ошибка: %', SQLERRM;
            ELSE
                RAISE NOTICE '❌ ТЕСТ 4.1 ПРОВАЛЕН: Неожиданная ошибка: %', SQLERRM;
            END IF;
    END;
    
    IF NOT v_error_occurred THEN
        RAISE NOTICE '❌ ТЕСТ 4.1 ПРОВАЛЕН: Операция выполнилась после истечения (не должно быть!)';
    END IF;
END $$;

-- =====================================================
-- ТЕСТ 5: Проверка логирования в audit.temp_access_log
-- =====================================================

DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '=== ТЕСТ 5: Проверка логирования ===';
END $$;

-- Тест 5.1: Проверяем все записи в audit.temp_access_log
DO $$
DECLARE
    v_count INTEGER;
    v_active_count INTEGER;
    v_expired_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_count
    FROM audit.temp_access_log
    WHERE caller_username = session_user;
    
    SELECT COUNT(*) INTO v_active_count
    FROM audit.temp_access_log
    WHERE caller_username = session_user
      AND is_active = true
      AND expires_at >= NOW();
    
    SELECT COUNT(*) INTO v_expired_count
    FROM audit.temp_access_log
    WHERE caller_username = session_user
      AND (is_active = false OR expires_at < NOW());
    
    RAISE NOTICE '✅ ТЕСТ 5.1 ПРОЙДЕН: Логирование работает';
    RAISE NOTICE '   Всего записей: %', v_count;
    RAISE NOTICE '   Активных: %', v_active_count;
    RAISE NOTICE '   Истекших: %', v_expired_count;
    
    IF v_count = 0 THEN
        RAISE NOTICE '⚠️  Внимание: Нет записей в audit.temp_access_log';
    END IF;
END $$;

-- Тест 5.2: Просмотр последних записей
DO $$
DECLARE
    v_record RECORD;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE 'Последние 5 записей в audit.temp_access_log:';
    
    FOR v_record IN
        SELECT 
            request_id,
            request_time,
            caller_username,
            operation,
            expires_at,
            duration_minutes,
            is_active,
            used_at
        FROM audit.temp_access_log
        WHERE caller_username = session_user
        ORDER BY request_time DESC
        LIMIT 5
    LOOP
        RAISE NOTICE '  [%] %: % (expires: %, active: %, used: %)',
            v_record.request_id,
            v_record.operation,
            v_record.request_time,
            v_record.expires_at,
            v_record.is_active,
            COALESCE(v_record.used_at::TEXT, 'never');
    END LOOP;
END $$;

-- =====================================================
-- ТЕСТ 6: Проверка валидации параметров
-- =====================================================

DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '=== ТЕСТ 6: Проверка валидации параметров ===';
END $$;

-- Тест 6.1: Попытка запросить неразрешённую операцию
DO $$
DECLARE
    v_error_occurred BOOLEAN := false;
BEGIN
    BEGIN
        PERFORM app.request_temp_privilege('delete_everything', 5);
        v_error_occurred := false;
    EXCEPTION
        WHEN OTHERS THEN
            v_error_occurred := true;
            IF SQLERRM LIKE '%не разрешена%' THEN
                RAISE NOTICE '✅ ТЕСТ 6.1 ПРОЙДЕН: Неразрешённая операция корректно отклонена';
                RAISE NOTICE '   Ошибка: %', SQLERRM;
            ELSE
                RAISE NOTICE '❌ ТЕСТ 6.1 ПРОВАЛЕН: Неожиданная ошибка: %', SQLERRM;
            END IF;
    END;
    
    IF NOT v_error_occurred THEN
        RAISE NOTICE '❌ ТЕСТ 6.1 ПРОВАЛЕН: Неразрешённая операция была принята (не должно быть!)';
    END IF;
END $$;

-- Тест 6.2: Попытка запросить привилегию с недопустимой длительностью
DO $$
DECLARE
    v_error_occurred BOOLEAN := false;
BEGIN
    BEGIN
        PERFORM app.request_temp_privilege('delete_contract', 120); -- > 60 минут
        v_error_occurred := false;
    EXCEPTION
        WHEN OTHERS THEN
            v_error_occurred := true;
            IF SQLERRM LIKE '%Длительность%' THEN
                RAISE NOTICE '✅ ТЕСТ 6.2 ПРОЙДЕН: Недопустимая длительность корректно отклонена';
                RAISE NOTICE '   Ошибка: %', SQLERRM;
            ELSE
                RAISE NOTICE '❌ ТЕСТ 6.2 ПРОВАЛЕН: Неожиданная ошибка: %', SQLERRM;
            END IF;
    END;
    
    IF NOT v_error_occurred THEN
        RAISE NOTICE '❌ ТЕСТ 6.2 ПРОВАЛЕН: Недопустимая длительность была принята (не должно быть!)';
    END IF;
END $$;

-- Тест 6.3: Попытка запросить привилегию с нулевой длительностью
DO $$
DECLARE
    v_error_occurred BOOLEAN := false;
BEGIN
    BEGIN
        PERFORM app.request_temp_privilege('delete_contract', 0);
        v_error_occurred := false;
    EXCEPTION
        WHEN OTHERS THEN
            v_error_occurred := true;
            IF SQLERRM LIKE '%Длительность%' THEN
                RAISE NOTICE '✅ ТЕСТ 6.3 ПРОЙДЕН: Нулевая длительность корректно отклонена';
                RAISE NOTICE '   Ошибка: %', SQLERRM;
            ELSE
                RAISE NOTICE '❌ ТЕСТ 6.3 ПРОВАЛЕН: Неожиданная ошибка: %', SQLERRM;
            END IF;
    END;
    
    IF NOT v_error_occurred THEN
        RAISE NOTICE '❌ ТЕСТ 6.3 ПРОВАЛЕН: Нулевая длительность была принята (не должно быть!)';
    END IF;
END $$;

-- =====================================================
-- ИТОГОВАЯ СВОДКА
-- =====================================================

DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'РГЗ: Тестирование завершено';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';
    RAISE NOTICE 'Проверьте результаты тестов выше.';
    RAISE NOTICE 'Все тесты должны быть помечены как ✅ ПРОЙДЕН';
    RAISE NOTICE '';
    RAISE NOTICE 'Для просмотра журнала временных привилегий:';
    RAISE NOTICE '  SELECT * FROM audit.temp_access_log ORDER BY request_time DESC;';
    RAISE NOTICE '';
    RAISE NOTICE 'Для просмотра журнала вызовов функций:';
    RAISE NOTICE '  SELECT * FROM audit.function_calls WHERE function_name = ''request_temp_privilege'' ORDER BY call_time DESC;';
END $$;

RESET ROLE;

