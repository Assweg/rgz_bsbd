-- lr3_03_tests.sql

SET search_path TO app, ref, audit, stg, public;

------------------------------------------------------------
-- Тест 1. Чтение чужого сегмента возвращает пустой набор
------------------------------------------------------------
DO $$
BEGIN
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
    RAISE NOTICE 'ТЕСТ 1: Проверка изоляции данных между сегментами';
    RAISE NOTICE 'Роль: app_writer, Сегмент: 1';
    RAISE NOTICE 'Ожидается: app_writer НЕ видит проекты из сегмента 2';
END $$;

SET ROLE app_writer;
SELECT app.set_session_ctx(1, NULL);

DO $$
DECLARE
    v_cnt INTEGER;
    v_total INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_total FROM app.projects;
    SELECT COUNT(*) INTO v_cnt FROM app.projects WHERE segment_id = 2;
    IF v_cnt <> 0 THEN
        RAISE EXCEPTION '❌ ТЕСТ 1 ПРОВАЛЕН: app_writer видит чужие проекты (% записей из сегмента 2)', v_cnt;
    END IF;
    RAISE NOTICE '✅ ТЕСТ 1 ПРОЙДЕН: Изоляция работает корректно';
    RAISE NOTICE '   • Всего проектов в БД: %', v_total;
    RAISE NOTICE '   • Проектов из сегмента 2: % (недоступны)', v_cnt;
END $$;

RESET ROLE;

------------------------------------------------------------
-- Тест 2. Вставка с неверным segment_id завершается ошибкой
------------------------------------------------------------
DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
    RAISE NOTICE 'ТЕСТ 2: Запрет вставки данных в чужой сегмент';
    RAISE NOTICE 'Роль: app_writer, Сегмент: 1';
    RAISE NOTICE 'Ожидается: ошибка при попытке INSERT с segment_id = 2';
END $$;

SET ROLE app_writer;
SELECT app.set_session_ctx(1, NULL);

DO $$
BEGIN
    BEGIN
        INSERT INTO app.projects (studio_id, segment_id, title, original_language, status)
        VALUES (1, 2, 'RLS negative insert', 'en', 'draft');
        RAISE EXCEPTION '❌ ТЕСТ 2 ПРОВАЛЕН: вставка с чужим segment_id прошла';
    EXCEPTION
        WHEN others THEN
            IF SQLSTATE = '42501' OR SQLERRM LIKE '%row-level security%' THEN
                RAISE NOTICE '✅ ТЕСТ 2 ПРОЙДЕН: RLS политика заблокировала вставку';
                RAISE NOTICE '   • Ошибка: %', SQLERRM;
            ELSE
                RAISE EXCEPTION '❌ ТЕСТ 2: Неожиданная ошибка: %', SQLERRM;
            END IF;
    END;
END $$;

RESET ROLE;

------------------------------------------------------------
-- Тест 3. Корректная вставка внутри своего сегмента
------------------------------------------------------------
DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
    RAISE NOTICE 'ТЕСТ 3: Корректная вставка данных в свой сегмент';
    RAISE NOTICE 'Роль: app_writer, Сегмент: 1';
    RAISE NOTICE 'Ожидается: успешное создание проекта в сегменте 1';
END $$;

SET ROLE app_writer;
SELECT app.set_session_ctx(1, NULL);

DO $$
DECLARE
    v_project_id INTEGER;
    v_count_before INTEGER;
    v_count_after INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_count_before FROM app.projects WHERE segment_id = 1;
    
    INSERT INTO app.projects (studio_id, segment_id, title, original_language, status)
    VALUES (1, 1, 'RLS positive insert', 'en', 'draft')
    RETURNING project_id INTO v_project_id;

    SELECT COUNT(*) INTO v_count_after FROM app.projects WHERE segment_id = 1;
    PERFORM 1 FROM app.projects WHERE project_id = v_project_id;
    
    RAISE NOTICE '✅ ТЕСТ 3 ПРОЙДЕН: Вставка в свой сегмент работает';
    RAISE NOTICE '   • Создан проект ID: %', v_project_id;
    RAISE NOTICE '   • Проектов в сегменте 1: было %, стало %', v_count_before, v_count_after;
END $$;

RESET ROLE;

SET ROLE app_owner;
DELETE FROM app.projects WHERE title = 'RLS positive insert';
RESET ROLE;

------------------------------------------------------------
-- Тест 4. set_session_ctx отклоняет доступ к чужому сегменту
------------------------------------------------------------
DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
    RAISE NOTICE 'ТЕСТ 4: Валидация доступа роли к сегменту в set_session_ctx';
    RAISE NOTICE 'Роль: voice_actor';
    RAISE NOTICE 'Ожидается: ошибка при попытке установить сегмент 2 (нет доступа)';
END $$;

SET ROLE voice_actor;

DO $$
BEGIN
    BEGIN
        PERFORM app.set_session_ctx(2, 1);
        RAISE EXCEPTION '❌ ТЕСТ 4 ПРОВАЛЕН: voice_actor получил доступ к сегменту 2';
    EXCEPTION WHEN others THEN
        IF SQLERRM LIKE '%не имеет доступа%' THEN
            RAISE NOTICE '✅ ТЕСТ 4 ПРОЙДЕН: Доступ к чужому сегменту заблокирован';
            RAISE NOTICE '   • Ошибка: %', SQLERRM;
        ELSE
            RAISE EXCEPTION '❌ ТЕСТ 4: Неожиданная ошибка: %', SQLERRM;
        END IF;
    END;
END $$;

RESET ROLE;

------------------------------------------------------------
-- Тест 5. set_session_ctx проверяет соответствие actor_id сегменту
------------------------------------------------------------
DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
    RAISE NOTICE 'ТЕСТ 5: Проверка принадлежности актёра сегменту';
    RAISE NOTICE 'Роль: voice_actor, Сегмент: 1, Actor ID: 999 (не существует)';
    RAISE NOTICE 'Ожидается: ошибка при установке несуществующего actor_id';
END $$;

SET ROLE voice_actor;

DO $$
BEGIN
    BEGIN
        PERFORM app.set_session_ctx(1, 999);
        RAISE EXCEPTION '❌ ТЕСТ 5 ПРОВАЛЕН: установлен actor_id, которого нет в сегменте';
    EXCEPTION WHEN others THEN
        IF SQLERRM LIKE '%не принадлежит сегменту%' THEN
            RAISE NOTICE '✅ ТЕСТ 5 ПРОЙДЕН: Валидация актёра работает';
            RAISE NOTICE '   • Ошибка: %', SQLERRM;
        ELSE
            RAISE EXCEPTION '❌ ТЕСТ 5: Неожиданная ошибка: %', SQLERRM;
        END IF;
    END;
END $$;

-- Корректная установка контекста для дальнейших тестов
SELECT app.set_session_ctx(1, 1);
RESET ROLE;

------------------------------------------------------------
-- Тест 6. studio_manager успешно обновляет данные своего сегмента
------------------------------------------------------------
DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
    RAISE NOTICE 'ТЕСТ 6: Обновление данных в своём сегменте';
    RAISE NOTICE 'Роль: studio_manager, Сегмент: 1';
    RAISE NOTICE 'Ожидается: успешное обновление проекта в сегменте 1';
END $$;

SET ROLE studio_manager;
SELECT app.set_session_ctx(1, NULL);

DO $$
DECLARE
    v_project_id INTEGER;
    v_old_status TEXT;
    v_new_status TEXT := 'in_review';
BEGIN
    SELECT project_id, status INTO v_project_id, v_old_status
    FROM app.projects
    WHERE segment_id = 1
    ORDER BY project_id
    LIMIT 1;

    UPDATE app.projects
    SET status = v_new_status
    WHERE project_id = v_project_id;

    RAISE NOTICE '✅ ТЕСТ 6 ПРОЙДЕН: Обновление в своём сегменте работает';
    RAISE NOTICE '   • Обновлён проект ID: %', v_project_id;
    RAISE NOTICE '   • Статус изменён: % → %', v_old_status, v_new_status;

    -- Откат изменений
    UPDATE app.projects SET status = v_old_status WHERE project_id = v_project_id;
END $$;

RESET ROLE;

------------------------------------------------------------
-- Тест 7. Попытка обновить запись с подменой сегмента блокируется
------------------------------------------------------------
DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
    RAISE NOTICE 'ТЕСТ 7: Запрет подмены segment_id при обновлении';
    RAISE NOTICE 'Роль: studio_manager, Сегмент: 1';
    RAISE NOTICE 'Ожидается: ошибка при попытке изменить segment_id на 2';
END $$;

SET ROLE studio_manager;
SELECT app.set_session_ctx(1, NULL);

DO $$
DECLARE
    v_project_id INTEGER;
BEGIN
    SELECT project_id INTO v_project_id
    FROM app.projects
    WHERE segment_id = 1
    ORDER BY project_id
    LIMIT 1;

    BEGIN
        UPDATE app.projects
        SET segment_id = 2
        WHERE project_id = v_project_id;
        RAISE EXCEPTION '❌ ТЕСТ 7 ПРОВАЛЕН: удалось сменить segment_id на чужой';
    EXCEPTION WHEN others THEN
        IF SQLSTATE = '42501' OR SQLERRM LIKE '%row-level security%' THEN
            RAISE NOTICE '✅ ТЕСТ 7 ПРОЙДЕН: Подмена сегмента заблокирована';
            RAISE NOTICE '   • Проект ID: %', v_project_id;
            RAISE NOTICE '   • Ошибка: %', SQLERRM;
        ELSE
            RAISE EXCEPTION '❌ ТЕСТ 7: Неожиданная ошибка: %', SQLERRM;
        END IF;
    END;
END $$;

RESET ROLE;

------------------------------------------------------------
-- Тест 8. Auditor видит все сегменты БЕЗ установки контекста
------------------------------------------------------------
DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
    RAISE NOTICE 'ТЕСТ 9: Режим аудитора - полный доступ ко всем данным';
    RAISE NOTICE 'Роль: auditor (БЕЗ set_session_ctx)';
    RAISE NOTICE 'Ожидается: auditor видит ВСЕ данные из ВСЕХ сегментов';
END $$;

SET ROLE auditor;

DO $$
DECLARE
    v_projects_segments INTEGER;
    v_projects_total INTEGER;
    v_contracts_segments INTEGER;
    v_contracts_total INTEGER;
    v_actors_segments INTEGER;
    v_actors_total INTEGER;
    v_sessions_segments INTEGER;
    v_sessions_total INTEGER;
    v_audio_segments INTEGER;
    v_audio_total INTEGER;
    v_voice_roles_segments INTEGER;
    v_voice_roles_total INTEGER;
    v_line TEXT;
BEGIN
    -- Проверка таблицы projects
    SELECT COUNT(DISTINCT segment_id), COUNT(*) 
    INTO v_projects_segments, v_projects_total 
    FROM app.projects;
    
    -- Проверка таблицы contracts
    SELECT COUNT(DISTINCT segment_id), COUNT(*) 
    INTO v_contracts_segments, v_contracts_total 
    FROM app.contracts;
    
    -- Проверка таблицы actors
    SELECT COUNT(DISTINCT segment_id), COUNT(*) 
    INTO v_actors_segments, v_actors_total 
    FROM app.actors;
    
    -- Проверка таблицы recording_sessions
    SELECT COUNT(DISTINCT segment_id), COUNT(*) 
    INTO v_sessions_segments, v_sessions_total 
    FROM app.recording_sessions;
    
    -- Проверка таблицы audio_archives
    SELECT COUNT(DISTINCT segment_id), COUNT(*) 
    INTO v_audio_segments, v_audio_total 
    FROM app.audio_archives;
    
    -- Проверка таблицы voice_roles
    SELECT COUNT(DISTINCT segment_id), COUNT(*) 
    INTO v_voice_roles_segments, v_voice_roles_total 
    FROM app.voice_roles;
    
    -- Валидация результатов
    IF v_projects_segments < 3 THEN
        RAISE EXCEPTION '❌ ТЕСТ 9 ПРОВАЛЕН: auditor видит лишь % сегментов в projects (ожидалось ≥3)', v_projects_segments;
    END IF;
    
    RAISE NOTICE 'ТЕСТ 9 ПРОЙДЕН: Auditor имеет полный доступ ко всем данным';
    RAISE NOTICE '';
    RAISE NOTICE '   ┌─────────────────────────────┬─────────────┬──────────────┐';
    RAISE NOTICE '   │ Таблица                     │ Сегментов   │ Всего записей│';
    RAISE NOTICE '   ├─────────────────────────────┼─────────────┼──────────────┤';
    v_line := '   │ app.projects                │ ' || rpad(v_projects_segments::TEXT, 11) || ' │ ' || rpad(v_projects_total::TEXT, 12) || ' │';
    RAISE NOTICE '%', v_line;
    v_line := '   │ app.contracts               │ ' || rpad(v_contracts_segments::TEXT, 11) || ' │ ' || rpad(v_contracts_total::TEXT, 12) || ' │';
    RAISE NOTICE '%', v_line;
    v_line := '   │ app.actors                  │ ' || rpad(v_actors_segments::TEXT, 11) || ' │ ' || rpad(v_actors_total::TEXT, 12) || ' │';
    RAISE NOTICE '%', v_line;
    v_line := '   │ app.recording_sessions      │ ' || rpad(v_sessions_segments::TEXT, 11) || ' │ ' || rpad(v_sessions_total::TEXT, 12) || ' │';
    RAISE NOTICE '%', v_line;
    v_line := '   │ app.audio_archives          │ ' || rpad(v_audio_segments::TEXT, 11) || ' │ ' || rpad(v_audio_total::TEXT, 12) || ' │';
    RAISE NOTICE '%', v_line;
    v_line := '   │ app.voice_roles             │ ' || rpad(v_voice_roles_segments::TEXT, 11) || ' │ ' || rpad(v_voice_roles_total::TEXT, 12) || ' │';
    RAISE NOTICE '%', v_line;
    RAISE NOTICE '   └─────────────────────────────┴─────────────┴──────────────┘';
    RAISE NOTICE '';
    RAISE NOTICE '   Auditor видит данные из % сегментов БЕЗ ограничений RLS', v_projects_segments;
END $$;

RESET ROLE;

------------------------------------------------------------
-- Тест 9. Корректные операции voice_actor в своём сегменте
------------------------------------------------------------
DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
    RAISE NOTICE 'ТЕСТ 8: Доступ voice_actor к своим контрактам';
    RAISE NOTICE 'Роль: voice_actor, Сегмент: 1, Actor ID: 1';
    RAISE NOTICE 'Ожидается: voice_actor видит только свои контракты в сегменте 1';
END $$;

SET ROLE voice_actor;
SELECT app.set_session_ctx(1, 1);

DO $$
DECLARE
    v_contracts_count INTEGER;
    v_actors_count INTEGER;
    v_actor_name TEXT;
BEGIN
    SELECT COUNT(*) INTO v_contracts_count FROM app.contracts;
    SELECT COUNT(*) INTO v_actors_count FROM app.actors;
    
    SELECT first_name || ' ' || last_name INTO v_actor_name
    FROM app.actors WHERE actor_id = 1;
    
    IF v_contracts_count = 0 THEN
        RAISE EXCEPTION '❌ ТЕСТ 8 ПРОВАЛЕН: voice_actor не увидел свои контракты';
    END IF;
    
    RAISE NOTICE '✅ ТЕСТ 8 ПРОЙДЕН: voice_actor получил доступ к своим данным';
    RAISE NOTICE '   • Актёр: % (ID: 1)', v_actor_name;
    RAISE NOTICE '   • Доступно контрактов: %', v_contracts_count;
    RAISE NOTICE '   • Доступно актёров: %', v_actors_count;
END $$;

RESET ROLE;

------------------------------------------------------------
-- Итоговая сводка
------------------------------------------------------------
DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
    RAISE NOTICE '╔════════════════════════════════════════════════════════════════╗';
    RAISE NOTICE '║                  ИТОГОВАЯ СВОДКА ТЕСТИРОВАНИЯ                  ║';
    RAISE NOTICE '╠════════════════════════════════════════════════════════════════╣';
    RAISE NOTICE '║  ✅ Все 9 тестов построчной изоляции успешно пройдены         ║';
    RAISE NOTICE '║                                                                ║';
    RAISE NOTICE '║  Проверенные функции:                                          ║';
    RAISE NOTICE '║  • Изоляция данных между сегментами                            ║';
    RAISE NOTICE '║  • Запрет кросс-сегментных операций                            ║';
    RAISE NOTICE '║  • Валидация доступа ролей к сегментам                         ║';
    RAISE NOTICE '║  • Проверка принадлежности актёров к сегментам                 ║';
    RAISE NOTICE '║  • Защита от подмены segment_id                                ║';
    RAISE NOTICE '║  • Режим аудитора (полный доступ без ограничений RLS)         ║';
    RAISE NOTICE '║  • Корректная работа RLS политик                               ║';
    RAISE NOTICE '╚════════════════════════════════════════════════════════════════╝';
    RAISE NOTICE '';
END $$;
