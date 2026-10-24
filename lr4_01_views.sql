
SET search_path TO app, ref, audit, stg, public;
SET ROLE app_owner;

DO $$
BEGIN
    RAISE NOTICE 'LR4: Создание безопасных представлений';
END $$;

-- =====================================================
-- 1. UPDATABLE VIEW с WITH CHECK OPTION
-- =====================================================
-- Представление для работы с неконфиденциальными полями проектов
-- Исключаем: client_contacts (Internal), budget (Confidential)

DROP VIEW IF EXISTS app.projects_public_view CASCADE;

-- Делаем представление обновляемым с WITH CHECK OPTION
-- WITH CHECK OPTION гарантирует, что через VIEW нельзя вставить/обновить строки,
-- которые не будут видны через это же VIEW
CREATE VIEW app.projects_public_view AS
SELECT 
    project_id,
    studio_id,
    segment_id,
    title,
    original_language,
    description,
    start_date,
    end_date,
    status,
    created_at
FROM app.projects
WITH CHECK OPTION;

-- Создаём INSTEAD OF триггеры для поддержки INSERT/UPDATE/DELETE
CREATE OR REPLACE FUNCTION app.projects_public_view_insert()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = app, ref, public
AS $$
BEGIN
    -- Проверка условий VIEW (аналог WITH CHECK OPTION)
    -- Проверяем, что segment_id соответствует текущему сегменту пользователя
    IF NOT app.segment_is_visible(NEW.segment_id) THEN
        RAISE EXCEPTION 'new row violates WITH CHECK OPTION for view "projects_public_view"';
    END IF;
    
    INSERT INTO app.projects (
        studio_id,
        segment_id,
        title,
        original_language,
        description,
        start_date,
        end_date,
        status
    ) VALUES (
        NEW.studio_id,
        NEW.segment_id,
        NEW.title,
        NEW.original_language,
        NEW.description,
        NEW.start_date,
        NEW.end_date,
        COALESCE(NEW.status, 'active')
    )
    RETURNING project_id INTO NEW.project_id;
    
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION app.projects_public_view_update()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = app, ref, public
AS $$
BEGIN
    -- Проверка условий VIEW (аналог WITH CHECK OPTION)
    IF NOT app.segment_is_visible(NEW.segment_id) THEN
        RAISE EXCEPTION 'new row violates WITH CHECK OPTION for view "projects_public_view"';
    END IF;
    
    UPDATE app.projects
    SET 
        studio_id = NEW.studio_id,
        segment_id = NEW.segment_id,
        title = NEW.title,
        original_language = NEW.original_language,
        description = NEW.description,
        start_date = NEW.start_date,
        end_date = NEW.end_date,
        status = NEW.status
    WHERE project_id = NEW.project_id;
    
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION app.projects_public_view_delete()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = app, ref, public
AS $$
BEGIN
    DELETE FROM app.projects
    WHERE project_id = OLD.project_id;
    
    RETURN OLD;
END;
$$;

-- Создаём триггеры INSTEAD OF
DROP TRIGGER IF EXISTS projects_public_view_insert_trigger ON app.projects_public_view;
DROP TRIGGER IF EXISTS projects_public_view_update_trigger ON app.projects_public_view;
DROP TRIGGER IF EXISTS projects_public_view_delete_trigger ON app.projects_public_view;

CREATE TRIGGER projects_public_view_insert_trigger
    INSTEAD OF INSERT ON app.projects_public_view
    FOR EACH ROW EXECUTE FUNCTION app.projects_public_view_insert();

CREATE TRIGGER projects_public_view_update_trigger
    INSTEAD OF UPDATE ON app.projects_public_view
    FOR EACH ROW EXECUTE FUNCTION app.projects_public_view_update();

CREATE TRIGGER projects_public_view_delete_trigger
    INSTEAD OF DELETE ON app.projects_public_view
    FOR EACH ROW EXECUTE FUNCTION app.projects_public_view_delete();

-- Представление для неконфиденциальных полей контрактов
-- Исключаем: salary_amount (Confidential), terms (Confidential)
DROP VIEW IF EXISTS app.contracts_public_view CASCADE;

CREATE VIEW app.contracts_public_view AS
SELECT 
    contract_id,
    project_id,
    actor_id,
    segment_id,
    contract_number,
    role_description,
    currency,
    signed_date,
    end_date,
    status,
    created_at
FROM app.contracts
WITH CHECK OPTION;

-- Триггеры для contracts_public_view
CREATE OR REPLACE FUNCTION app.contracts_public_view_insert()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = app, ref, public
AS $$
BEGIN
    -- Проверка условий VIEW (аналог WITH CHECK OPTION)
    IF NOT app.segment_is_visible(NEW.segment_id) THEN
        RAISE EXCEPTION 'new row violates WITH CHECK OPTION for view "contracts_public_view"';
    END IF;
    
    INSERT INTO app.contracts (
        project_id,
        actor_id,
        segment_id,
        contract_number,
        role_description,
        currency,
        signed_date,
        end_date,
        status,
        salary_amount  -- Устанавливаем значение по умолчанию
    ) VALUES (
        NEW.project_id,
        NEW.actor_id,
        NEW.segment_id,
        NEW.contract_number,
        NEW.role_description,
        COALESCE(NEW.currency, 'USD'),
        NEW.signed_date,
        NEW.end_date,
        COALESCE(NEW.status, 'active'),
        0.00  -- Значение по умолчанию для скрытого поля
    )
    RETURNING contract_id INTO NEW.contract_id;
    
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION app.contracts_public_view_update()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = app, ref, public
AS $$
BEGIN
    -- Проверка условий VIEW (аналог WITH CHECK OPTION)
    IF NOT app.segment_is_visible(NEW.segment_id) THEN
        RAISE EXCEPTION 'new row violates WITH CHECK OPTION for view "contracts_public_view"';
    END IF;
    
    UPDATE app.contracts
    SET 
        project_id = NEW.project_id,
        actor_id = NEW.actor_id,
        segment_id = NEW.segment_id,
        contract_number = NEW.contract_number,
        role_description = NEW.role_description,
        currency = NEW.currency,
        signed_date = NEW.signed_date,
        end_date = NEW.end_date,
        status = NEW.status
    WHERE contract_id = NEW.contract_id;
    
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION app.contracts_public_view_delete()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = app, ref, public
AS $$
BEGIN
    DELETE FROM app.contracts
    WHERE contract_id = OLD.contract_id;
    
    RETURN OLD;
END;
$$;

DROP TRIGGER IF EXISTS contracts_public_view_insert_trigger ON app.contracts_public_view;
DROP TRIGGER IF EXISTS contracts_public_view_update_trigger ON app.contracts_public_view;
DROP TRIGGER IF EXISTS contracts_public_view_delete_trigger ON app.contracts_public_view;

CREATE TRIGGER contracts_public_view_insert_trigger
    INSTEAD OF INSERT ON app.contracts_public_view
    FOR EACH ROW EXECUTE FUNCTION app.contracts_public_view_insert();

CREATE TRIGGER contracts_public_view_update_trigger
    INSTEAD OF UPDATE ON app.contracts_public_view
    FOR EACH ROW EXECUTE FUNCTION app.contracts_public_view_update();

CREATE TRIGGER contracts_public_view_delete_trigger
    INSTEAD OF DELETE ON app.contracts_public_view
    FOR EACH ROW EXECUTE FUNCTION app.contracts_public_view_delete();

-- =====================================================
-- 2. SECURITY BARRIER VIEW для агрегатов/отчётов
-- =====================================================
-- Представление для агрегированной статистики по проектам
-- SECURITY BARRIER предотвращает утечку данных через условия HAVING или подзапросы

DROP VIEW IF EXISTS app.projects_statistics_view CASCADE;

CREATE VIEW app.projects_statistics_view
WITH (security_barrier = true) AS
SELECT 
    segment_id,
    status,
    COUNT(*) as project_count,
    COUNT(DISTINCT studio_id) as studios_count,
    MIN(start_date) as earliest_start,
    MAX(end_date) as latest_end
FROM app.projects
GROUP BY segment_id, status;

-- Представление для агрегированной статистики по контрактам
-- (без раскрытия деталей о зарплатах)
DROP VIEW IF EXISTS app.contracts_statistics_view CASCADE;

CREATE VIEW app.contracts_statistics_view
WITH (security_barrier = true) AS
SELECT 
    c.segment_id,
    c.status,
    COUNT(*) as contract_count,
    COUNT(DISTINCT c.actor_id) as actors_count,
    COUNT(DISTINCT c.project_id) as projects_count,
    MIN(c.signed_date) as earliest_signed,
    MAX(c.end_date) as latest_end,
    -- Агрегированная сумма (без детализации)
    SUM(c.salary_amount) as total_salary_amount,
    AVG(c.salary_amount) as avg_salary_amount
FROM app.contracts c
GROUP BY c.segment_id, c.status;

-- Представление для статистики по актёрам (без персональных данных)
DROP VIEW IF EXISTS app.actors_statistics_view CASCADE;

-- Проверяем наличие segment_id в actors перед созданием VIEW
-- Если колонки нет, пытаемся добавить её (для совместимости)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'app' AND table_name = 'actors' AND column_name = 'segment_id'
    ) THEN
        RAISE NOTICE 'Колонка segment_id не найдена в app.actors. Пытаемся добавить...';
        
        -- Добавляем колонку
        ALTER TABLE app.actors ADD COLUMN segment_id INTEGER;
        
        -- Обновляем segment_id из contracts
        UPDATE app.actors a
        SET segment_id = (
            SELECT c.segment_id
            FROM app.contracts c
            WHERE c.actor_id = a.actor_id
            ORDER BY c.contract_id
            LIMIT 1
        )
        WHERE a.segment_id IS NULL;
        
        -- Устанавливаем значение по умолчанию для оставшихся NULL
        UPDATE app.actors
        SET segment_id = 1
        WHERE segment_id IS NULL;
        
        -- Устанавливаем NOT NULL
        ALTER TABLE app.actors
            ALTER COLUMN segment_id SET NOT NULL;
        
        -- Добавляем внешний ключ
        BEGIN
            ALTER TABLE app.actors
                ADD CONSTRAINT actors_segment_fk FOREIGN KEY (segment_id) REFERENCES ref.segments(segment_id);
        EXCEPTION WHEN duplicate_object THEN
            NULL;
        END;
        
        RAISE NOTICE 'Колонка segment_id успешно добавлена в app.actors';
    END IF;
END $$;

CREATE VIEW app.actors_statistics_view
WITH (security_barrier = true) AS
SELECT 
    a.segment_id,
    COUNT(*) as actors_count,
    COUNT(*) FILTER (WHERE a.is_active = true) as active_actors_count,
    COUNT(DISTINCT vr.language_id) as languages_count,
    COUNT(DISTINCT vr.project_id) as projects_involved
FROM app.actors a
LEFT JOIN app.voice_roles vr ON a.actor_id = vr.actor_id
GROUP BY a.segment_id;

-- Представление для статистики по сессиям записи
DROP VIEW IF EXISTS app.sessions_statistics_view CASCADE;

CREATE VIEW app.sessions_statistics_view
WITH (security_barrier = true) AS
SELECT 
    rs.segment_id,
    rs.status,
    COUNT(*) as sessions_count,
    SUM(rs.duration_hours) as total_hours,
    AVG(rs.duration_hours) as avg_duration_hours,
    MIN(rs.session_date) as earliest_session,
    MAX(rs.session_date) as latest_session
FROM app.recording_sessions rs
GROUP BY rs.segment_id, rs.status;

-- Выдаём права на представления
GRANT SELECT ON app.projects_public_view TO app_reader, app_writer, studio_manager, voice_actor;
GRANT INSERT, UPDATE, DELETE ON app.projects_public_view TO app_writer, studio_manager;

GRANT SELECT ON app.contracts_public_view TO app_reader, app_writer, studio_manager, voice_actor;
GRANT INSERT, UPDATE, DELETE ON app.contracts_public_view TO app_writer, studio_manager;

GRANT SELECT ON app.projects_statistics_view TO app_reader, app_writer, studio_manager, voice_actor, auditor;
GRANT SELECT ON app.contracts_statistics_view TO app_reader, app_writer, studio_manager, voice_actor, auditor;
GRANT SELECT ON app.actors_statistics_view TO app_reader, app_writer, studio_manager, voice_actor, auditor;
GRANT SELECT ON app.sessions_statistics_view TO app_reader, app_writer, studio_manager, voice_actor, auditor;

-- Комментарии
COMMENT ON VIEW app.projects_public_view IS 
'Updatable VIEW с WITH CHECK OPTION для неконфиденциальных полей проектов. Исключает client_contacts и budget.';

COMMENT ON VIEW app.contracts_public_view IS 
'Updatable VIEW с WITH CHECK OPTION для неконфиденциальных полей контрактов. Исключает salary_amount и terms.';

COMMENT ON VIEW app.projects_statistics_view IS 
'SECURITY BARRIER VIEW для агрегированной статистики по проектам. Предотвращает утечку данных через HAVING/подзапросы.';

COMMENT ON VIEW app.contracts_statistics_view IS 
'SECURITY BARRIER VIEW для агрегированной статистики по контрактам. Показывает только агрегаты, без детализации.';

COMMENT ON VIEW app.actors_statistics_view IS 
'SECURITY BARRIER VIEW для статистики по актёрам без персональных данных.';

COMMENT ON VIEW app.sessions_statistics_view IS 
'SECURITY BARRIER VIEW для статистики по сессиям записи.';

DO $$
BEGIN
    RAISE NOTICE 'LR4: Безопасные представления успешно созданы';
    RAISE NOTICE '  • Updatable VIEW с WITH CHECK OPTION: projects_public_view, contracts_public_view';
    RAISE NOTICE '  • SECURITY BARRIER VIEW: projects_statistics_view, contracts_statistics_view, actors_statistics_view, sessions_statistics_view';
END $$;

RESET ROLE;

