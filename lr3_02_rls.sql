-- lr3_02_rls.sql
-- Лабораторная работа №3: RLS политики и передача контекста

SET search_path TO app, ref, audit, stg, public;
SET ROLE app_owner;

DO $$
BEGIN
    RAISE NOTICE 'LR3: начало перенастройки RLS и функций контекста';
END $$;

-- Удаляем устаревшие политики ЛР1/ЛР2
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN 
        SELECT policyname, tablename 
        FROM pg_policies 
        WHERE schemaname = 'app'
          AND policyname IN (
              'actor_self_select', 'dml_admin_actors',
              'actor_own_contracts', 'dml_admin_contracts',
              'actor_own_sessions', 'dml_admin_sessions',
              'studio_own_projects', 'dml_admin_projects',
              'hide_salaries', 'dml_admin_audio_archives'
          )
    LOOP
        EXECUTE format('DROP POLICY IF EXISTS %I ON app.%I', r.policyname, r.tablename);
    END LOOP;
END $$;

-- Включаем (повторно) RLS и FORCE на ключевых таблицах
ALTER TABLE app.actors ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.contracts ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.projects ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.recording_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.audio_archives ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.voice_roles ENABLE ROW LEVEL SECURITY;

ALTER TABLE app.actors FORCE ROW LEVEL SECURITY;
ALTER TABLE app.contracts FORCE ROW LEVEL SECURITY;
ALTER TABLE app.projects FORCE ROW LEVEL SECURITY;
ALTER TABLE app.recording_sessions FORCE ROW LEVEL SECURITY;
ALTER TABLE app.audio_archives FORCE ROW LEVEL SECURITY;
ALTER TABLE app.voice_roles FORCE ROW LEVEL SECURITY;

-- Вспомогательные функции
DROP FUNCTION IF EXISTS app.get_current_user_studio();

CREATE OR REPLACE FUNCTION app.segment_is_visible(p_segment_id INTEGER)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_segment TEXT;
BEGIN
    v_segment := current_setting('app.segment_id', true);
    IF v_segment IS NULL THEN
        RAISE EXCEPTION 'Сегмент не установлен. Вызовите app.set_session_ctx() перед обращением к данным.';
    END IF;
    RETURN p_segment_id = v_segment::INTEGER;
END;
$$;

CREATE OR REPLACE FUNCTION app.actor_scope_allows(p_actor_id INTEGER)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_actor TEXT;
BEGIN
    IF current_user <> 'voice_actor' THEN
        RETURN TRUE;
    END IF;

    v_actor := current_setting('app.actor_id', true);
    IF v_actor IS NULL THEN
        RAISE EXCEPTION 'Для роли voice_actor необходимо установить actor_id через app.set_session_ctx().';
    END IF;

    RETURN p_actor_id = v_actor::INTEGER;
END;
$$;

-- SECURITY DEFINER-функция передачи контекста
CREATE OR REPLACE FUNCTION app.set_session_ctx(p_segment_id INTEGER, p_actor_id INTEGER DEFAULT NULL)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = app, ref, public
AS $$
DECLARE
    v_effective_role TEXT;
BEGIN
    v_effective_role := current_setting('role', true);
    IF v_effective_role IS NULL THEN
        v_effective_role := session_user;
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM app.segment_role_acl
        WHERE role_name = v_effective_role
          AND segment_id = p_segment_id
    ) THEN
        RAISE EXCEPTION 'Роль % не имеет доступа к сегменту %', v_effective_role, p_segment_id;
    END IF;

    PERFORM set_config('app.segment_id', p_segment_id::TEXT, FALSE);

    IF p_actor_id IS NULL THEN
        PERFORM set_config('app.actor_id', NULL, FALSE);
    ELSE
        IF NOT EXISTS (
            SELECT 1 FROM app.actors
            WHERE actor_id = p_actor_id
              AND segment_id = p_segment_id
        ) THEN
            RAISE EXCEPTION 'Актёр % не принадлежит сегменту %', p_actor_id, p_segment_id;
        END IF;
        PERFORM set_config('app.actor_id', p_actor_id::TEXT, FALSE);
    END IF;
END;
$$;

COMMENT ON FUNCTION app.set_session_ctx(INTEGER, INTEGER) IS
'Устанавливает безопасный контекст сегмента и актёра для политик RLS (SEG + actor)';

GRANT EXECUTE ON FUNCTION app.set_session_ctx(INTEGER, INTEGER) TO app_reader, app_writer, studio_manager, voice_actor;

-- Универсальная проверка сегмента для политик (с режимом auditor)
CREATE OR REPLACE FUNCTION app.segment_filter(p_segment_id INTEGER)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
    IF current_user = 'auditor' THEN
        RETURN TRUE;
    END IF;
    RETURN app.segment_is_visible(p_segment_id);
END;
$$;

-- Политики для app.projects
DROP POLICY IF EXISTS seg_projects_select ON app.projects;
DROP POLICY IF EXISTS seg_projects_insert ON app.projects;
DROP POLICY IF EXISTS seg_projects_update ON app.projects;
DROP POLICY IF EXISTS seg_projects_delete ON app.projects;
DROP POLICY IF EXISTS dml_admin_projects_all ON app.projects;

CREATE POLICY seg_projects_select ON app.projects
    FOR SELECT
    TO app_reader, app_writer, studio_manager, voice_actor, auditor
    USING (current_user = 'auditor' OR app.segment_is_visible(segment_id));

CREATE POLICY seg_projects_insert ON app.projects
    FOR INSERT
    TO app_writer, studio_manager
    WITH CHECK (app.segment_is_visible(segment_id));

CREATE POLICY seg_projects_update ON app.projects
    FOR UPDATE
    TO app_writer, studio_manager
    USING (app.segment_is_visible(segment_id))
    WITH CHECK (app.segment_is_visible(segment_id));

CREATE POLICY seg_projects_delete ON app.projects
    FOR DELETE
    TO app_writer, studio_manager
    USING (app.segment_is_visible(segment_id));

CREATE POLICY dml_admin_projects_all ON app.projects
    FOR ALL
    TO dml_admin
    USING (TRUE);

-- Политики для app.contracts
DROP POLICY IF EXISTS seg_contracts_select ON app.contracts;
DROP POLICY IF EXISTS seg_contracts_insert ON app.contracts;
DROP POLICY IF EXISTS seg_contracts_update ON app.contracts;
DROP POLICY IF EXISTS seg_contracts_delete ON app.contracts;
DROP POLICY IF EXISTS dml_admin_contracts_all ON app.contracts;

CREATE POLICY seg_contracts_select ON app.contracts
    FOR SELECT
    TO app_reader, app_writer, studio_manager, voice_actor, auditor
    USING (
        current_user = 'auditor'
        OR (app.segment_is_visible(segment_id) AND app.actor_scope_allows(actor_id))
    );

CREATE POLICY seg_contracts_insert ON app.contracts
    FOR INSERT
    TO app_writer, studio_manager
    WITH CHECK (app.segment_is_visible(segment_id));

CREATE POLICY seg_contracts_update ON app.contracts
    FOR UPDATE
    TO app_writer, studio_manager
    USING (app.segment_is_visible(segment_id))
    WITH CHECK (app.segment_is_visible(segment_id));

CREATE POLICY seg_contracts_delete ON app.contracts
    FOR DELETE
    TO app_writer, studio_manager
    USING (app.segment_is_visible(segment_id));

CREATE POLICY dml_admin_contracts_all ON app.contracts
    FOR ALL
    TO dml_admin
    USING (TRUE);

-- Политики для app.actors
DROP POLICY IF EXISTS seg_actors_select ON app.actors;
DROP POLICY IF EXISTS seg_actors_update ON app.actors;
DROP POLICY IF EXISTS dml_admin_actors_all ON app.actors;

CREATE POLICY seg_actors_select ON app.actors
    FOR SELECT
    TO app_reader, app_writer, studio_manager, voice_actor, auditor
    USING (
        current_user = 'auditor'
        OR (app.segment_is_visible(segment_id) AND app.actor_scope_allows(actor_id))
    );

CREATE POLICY seg_actors_update ON app.actors
    FOR UPDATE
    TO app_writer, studio_manager
    USING (app.segment_is_visible(segment_id))
    WITH CHECK (app.segment_is_visible(segment_id));

CREATE POLICY dml_admin_actors_all ON app.actors
    FOR ALL
    TO dml_admin
    USING (TRUE);

-- Политики для app.recording_sessions
DROP POLICY IF EXISTS seg_sessions_select ON app.recording_sessions;
DROP POLICY IF EXISTS seg_sessions_insert ON app.recording_sessions;
DROP POLICY IF EXISTS seg_sessions_update ON app.recording_sessions;
DROP POLICY IF EXISTS seg_sessions_delete ON app.recording_sessions;
DROP POLICY IF EXISTS dml_admin_sessions_all ON app.recording_sessions;

CREATE POLICY seg_sessions_select ON app.recording_sessions
    FOR SELECT
    TO app_reader, app_writer, studio_manager, voice_actor, auditor
    USING (current_user = 'auditor' OR app.segment_is_visible(segment_id));

CREATE POLICY seg_sessions_insert ON app.recording_sessions
    FOR INSERT
    TO app_writer, studio_manager
    WITH CHECK (app.segment_is_visible(segment_id));

CREATE POLICY seg_sessions_update ON app.recording_sessions
    FOR UPDATE
    TO app_writer, studio_manager
    USING (app.segment_is_visible(segment_id))
    WITH CHECK (app.segment_is_visible(segment_id));

CREATE POLICY seg_sessions_delete ON app.recording_sessions
    FOR DELETE
    TO app_writer, studio_manager
    USING (app.segment_is_visible(segment_id));

CREATE POLICY dml_admin_sessions_all ON app.recording_sessions
    FOR ALL
    TO dml_admin
    USING (TRUE);

-- Политики для app.audio_archives
DROP POLICY IF EXISTS seg_audio_select ON app.audio_archives;
DROP POLICY IF EXISTS seg_audio_insert ON app.audio_archives;
DROP POLICY IF EXISTS seg_audio_update ON app.audio_archives;
DROP POLICY IF EXISTS seg_audio_delete ON app.audio_archives;
DROP POLICY IF EXISTS dml_admin_audio_all ON app.audio_archives;

CREATE POLICY seg_audio_select ON app.audio_archives
    FOR SELECT
    TO app_reader, app_writer, studio_manager, voice_actor, auditor
    USING (current_user = 'auditor' OR app.segment_is_visible(segment_id));

CREATE POLICY seg_audio_insert ON app.audio_archives
    FOR INSERT
    TO app_writer, studio_manager
    WITH CHECK (app.segment_is_visible(segment_id));

CREATE POLICY seg_audio_update ON app.audio_archives
    FOR UPDATE
    TO app_writer, studio_manager
    USING (app.segment_is_visible(segment_id))
    WITH CHECK (app.segment_is_visible(segment_id));

CREATE POLICY seg_audio_delete ON app.audio_archives
    FOR DELETE
    TO app_writer, studio_manager
    USING (app.segment_is_visible(segment_id));

CREATE POLICY dml_admin_audio_all ON app.audio_archives
    FOR ALL
    TO dml_admin
    USING (TRUE);

-- Политики для app.voice_roles
DROP POLICY IF EXISTS seg_voice_roles_select ON app.voice_roles;
DROP POLICY IF EXISTS seg_voice_roles_insert ON app.voice_roles;
DROP POLICY IF EXISTS seg_voice_roles_update ON app.voice_roles;
DROP POLICY IF EXISTS seg_voice_roles_delete ON app.voice_roles;
DROP POLICY IF EXISTS dml_admin_voice_roles_all ON app.voice_roles;

CREATE POLICY seg_voice_roles_select ON app.voice_roles
    FOR SELECT
    TO app_reader, app_writer, studio_manager, voice_actor, auditor
    USING (current_user = 'auditor' OR app.segment_is_visible(segment_id));

CREATE POLICY seg_voice_roles_insert ON app.voice_roles
    FOR INSERT
    TO app_writer, studio_manager
    WITH CHECK (app.segment_is_visible(segment_id));

CREATE POLICY seg_voice_roles_update ON app.voice_roles
    FOR UPDATE
    TO app_writer, studio_manager
    USING (app.segment_is_visible(segment_id))
    WITH CHECK (app.segment_is_visible(segment_id));

CREATE POLICY seg_voice_roles_delete ON app.voice_roles
    FOR DELETE
    TO app_writer, studio_manager
    USING (app.segment_is_visible(segment_id));

CREATE POLICY dml_admin_voice_roles_all ON app.voice_roles
    FOR ALL
    TO dml_admin
    USING (TRUE);

DO $$
BEGIN
    RAISE NOTICE 'LR3: политики RLS и функция app.set_session_ctx успешно обновлены';
END $$;

RESET ROLE;

