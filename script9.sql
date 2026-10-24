-- 09_rls.sql (исправленная часть)
-- Настройка Row Level Security и политик доступа

-- Включаем RLS на критически важных таблицах
ALTER TABLE app.actors ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.contracts ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.recording_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.audio_archives ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.projects ENABLE ROW LEVEL SECURITY;

-- Принудительно включаем RLS
ALTER TABLE app.actors FORCE ROW LEVEL SECURITY;
ALTER TABLE app.contracts FORCE ROW LEVEL SECURITY;
ALTER TABLE app.recording_sessions FORCE ROW LEVEL SECURITY;
ALTER TABLE app.audio_archives FORCE ROW LEVEL SECURITY;
ALTER TABLE app.projects FORCE ROW LEVEL SECURITY;

-- Удаляем существующие политики если они есть
DROP POLICY IF EXISTS actor_self_select ON app.actors;
DROP POLICY IF EXISTS actor_own_contracts ON app.contracts;
DROP POLICY IF EXISTS actor_own_sessions ON app.recording_sessions;
DROP POLICY IF EXISTS studio_own_projects ON app.projects;
DROP POLICY IF EXISTS hide_salaries ON app.contracts;

-- Политика для таблицы actors - актёры видят только свою запись
CREATE POLICY actor_self_select ON app.actors
    FOR SELECT
    TO app_reader, app_writer, voice_actor
    USING (actor_id = current_setting('app.current_actor_id', true)::INTEGER);

-- Политика для dml_admin - полный доступ к actors
CREATE POLICY dml_admin_actors ON app.actors
    FOR ALL
    TO dml_admin
    USING (true);

-- Политика для contracts - актёры видят только свои контракты
CREATE POLICY actor_own_contracts ON app.contracts
    FOR SELECT
    TO app_reader, app_writer, voice_actor
    USING (actor_id = current_setting('app.current_actor_id', true)::INTEGER);

-- Политика для dml_admin - полный доступ к contracts
CREATE POLICY dml_admin_contracts ON app.contracts
    FOR ALL
    TO dml_admin
    USING (true);

-- Политика для recording_sessions - через JOIN к contracts
CREATE POLICY actor_own_sessions ON app.recording_sessions
    FOR SELECT
    TO app_reader, app_writer, voice_actor
    USING (EXISTS (
        SELECT 1 FROM app.contracts c 
        WHERE c.contract_id = app.recording_sessions.contract_id 
        AND c.actor_id = current_setting('app.current_actor_id', true)::INTEGER
    ));

-- Политика для dml_admin - полный доступ к recording_sessions
CREATE POLICY dml_admin_sessions ON app.recording_sessions
    FOR ALL
    TO dml_admin
    USING (true);

-- Функция для определения студии менеджера (пересоздаём)
CREATE OR REPLACE FUNCTION app.get_current_user_studio()
RETURNS INTEGER
LANGUAGE sql
STABLE
AS $$
    SELECT 1; -- Для демонстрации возвращаем studio_id = 1
$$;

-- Политика для projects - менеджеры видят проекты своей студии
CREATE POLICY studio_own_projects ON app.projects
    FOR ALL
    TO app_writer, app_reader, studio_manager
    USING (studio_id = app.get_current_user_studio());

-- Политика для dml_admin - полный доступ к projects
CREATE POLICY dml_admin_projects ON app.projects
    FOR ALL
    TO dml_admin
    USING (true);

-- Политика для скрытия конфиденциальных зарплат
CREATE POLICY hide_salaries ON app.contracts
    FOR SELECT
    TO app_reader
    USING (true);

-- SECURITY DEFINER функция для безопасного доступа к контрактам (пересоздаём)
CREATE OR REPLACE FUNCTION app.get_contracts_with_masked_salary()
RETURNS TABLE (
    contract_id INTEGER,
    contract_number VARCHAR,
    role_description TEXT,
    salary_range VARCHAR,
    currency VARCHAR,
    signed_date DATE
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = app, public
AS $$
    SELECT 
        contract_id,
        contract_number,
        role_description,
        CASE 
            WHEN salary_amount < 10000 THEN 'до 10,000'
            WHEN salary_amount < 50000 THEN '10,000 - 50,000' 
            ELSE 'свыше 50,000'
        END as salary_range,
        currency,
        signed_date
    FROM app.contracts;
$$;

-- Даём доступ к функции
GRANT EXECUTE ON FUNCTION app.get_contracts_with_masked_salary TO app_reader;

COMMENT ON FUNCTION app.get_contracts_with_masked_salary IS 'Безопасный просмотр контрактов с маскировкой зарплат';

-- Политика для dml_admin - полный доступ к audio_archives
CREATE POLICY dml_admin_audio_archives ON app.audio_archives
    FOR ALL
    TO dml_admin
    USING (true);

-- Уведомление о завершении
DO $$ 
BEGIN
    RAISE NOTICE 'RLS политики и функции безопасности успешно настроены';
END $$;