-- lr3_01_segment_model.sql
-- Лабораторная работа №3: подготовка сегментации и перенос данных

SET search_path TO app, ref, audit, stg, public;
SET ROLE app_owner;

DO $$
BEGIN
    RAISE NOTICE 'LR3: начало настройки сегментации данных';
END $$;

-- 1. Справочник сегментов (ось изоляции — филиал / студия)
CREATE TABLE IF NOT EXISTS ref.segments (
    segment_id SERIAL PRIMARY KEY,
    segment_code VARCHAR(30) UNIQUE NOT NULL,
    segment_name TEXT NOT NULL,
    studio_id INTEGER NOT NULL UNIQUE REFERENCES ref.studios(studio_id),
    region VARCHAR(100),
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

COMMENT ON TABLE ref.segments IS 'Сегменты (филиалы/студии) для RLS-изоляции';
COMMENT ON COLUMN ref.segments.segment_code IS 'Уникальный код сегмента для SET LOCAL app.segment_id';

INSERT INTO ref.segments (segment_code, segment_name, studio_id, region)
VALUES
    ('SEG-MSK', 'Филиал Москва (ЗвукЗапись)', 1, 'Москва'),
    ('SEG-SPB', 'Филиал Санкт-Петербург (ГолосДубляжа)', 2, 'Санкт-Петербург'),
    ('SEG-NSK', 'Филиал Новосибирск (АудиоМир)', 3, 'Новосибирск'),
    ('SEG-EKB', 'Филиал Екатеринбург (ВолнаЗвука)', 4, 'Екатеринбург'),
    ('SEG-KGD', 'Филиал Калининград (Синхрон)', 5, 'Калининград'),
    ('SEG-KYA', 'Филиал Красноярск (РечевойЦентр)', 6, 'Красноярск'),
    ('SEG-VVO', 'Филиал Владивосток (ЗвуковыеВолны)', 7, 'Владивосток'),
    ('SEG-SAM', 'Филиал Самара (Артикуляция)', 8, 'Самара'),
    ('SEG-NNV', 'Филиал Нижний Новгород (ГолосМастер)', 9, 'Нижний Новгород'),
    ('SEG-CHK', 'Филиал Челябинск (АудиоПрофи)', 10, 'Челябинск')
ON CONFLICT (studio_id) DO UPDATE
    SET segment_code = EXCLUDED.segment_code,
        segment_name = EXCLUDED.segment_name,
        region = EXCLUDED.region,
        is_active = TRUE;

CREATE INDEX IF NOT EXISTS idx_segments_code ON ref.segments(segment_code);

-- 2. ACL сегментов для ролей
CREATE TABLE IF NOT EXISTS app.segment_role_acl (
    acl_id SERIAL PRIMARY KEY,
    role_name TEXT NOT NULL,
    segment_id INTEGER NOT NULL REFERENCES ref.segments(segment_id) ON DELETE CASCADE,
    can_manage BOOLEAN DEFAULT FALSE,
    UNIQUE(role_name, segment_id)
);

COMMENT ON TABLE app.segment_role_acl IS 'Допустимые соответствия роль ↔ сегмент для установки контекста RLS';

INSERT INTO app.segment_role_acl (role_name, segment_id, can_manage)
VALUES
    ('studio_manager', 1, TRUE),
    ('studio_manager', 2, FALSE),
    ('app_writer', 1, TRUE),
    ('app_writer', 2, TRUE),
    ('app_writer', 3, TRUE),
    ('app_reader', 1, FALSE),
    ('app_reader', 2, FALSE),
    ('voice_actor', 1, FALSE)
ON CONFLICT DO NOTHING;

-- 3. Добавление segment_id в ключевые таблицы app.*

-- helper to enforce FK after backfill
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'app' AND table_name = 'projects' AND column_name = 'segment_id'
    ) THEN
        ALTER TABLE app.projects ADD COLUMN segment_id INTEGER;
    END IF;

    UPDATE app.projects p
    SET segment_id = s.segment_id
    FROM ref.segments s
    WHERE p.segment_id IS NULL
      AND s.studio_id = p.studio_id;

    ALTER TABLE app.projects
        ALTER COLUMN segment_id SET NOT NULL;

    BEGIN
        ALTER TABLE app.projects
            ADD CONSTRAINT projects_segment_fk FOREIGN KEY (segment_id) REFERENCES ref.segments(segment_id);
    EXCEPTION WHEN duplicate_object THEN
        NULL;
    END;
END $$;

CREATE INDEX IF NOT EXISTS idx_projects_segment_status ON app.projects(segment_id, status);

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'app' AND table_name = 'contracts' AND column_name = 'segment_id'
    ) THEN
        ALTER TABLE app.contracts ADD COLUMN segment_id INTEGER;
    END IF;

    UPDATE app.contracts c
    SET segment_id = p.segment_id
    FROM app.projects p
    WHERE c.segment_id IS NULL
      AND c.project_id = p.project_id;

    ALTER TABLE app.contracts
        ALTER COLUMN segment_id SET NOT NULL;

    BEGIN
        ALTER TABLE app.contracts
            ADD CONSTRAINT contracts_segment_fk FOREIGN KEY (segment_id) REFERENCES ref.segments(segment_id);
    EXCEPTION WHEN duplicate_object THEN
        NULL;
    END;
END $$;

CREATE INDEX IF NOT EXISTS idx_contracts_segment_actor ON app.contracts(segment_id, actor_id);

DO $$
DECLARE
    v_null_count INTEGER;
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'app' AND table_name = 'recording_sessions' AND column_name = 'segment_id'
    ) THEN
        ALTER TABLE app.recording_sessions ADD COLUMN segment_id INTEGER;
    END IF;

    -- Временно снимаем NOT NULL, если он установлен
    BEGIN
        ALTER TABLE app.recording_sessions ALTER COLUMN segment_id DROP NOT NULL;
    EXCEPTION WHEN OTHERS THEN
        NULL;
    END;

    -- Обновляем segment_id из contracts
    UPDATE app.recording_sessions rs
    SET segment_id = c.segment_id
    FROM app.contracts c
    WHERE rs.segment_id IS NULL
      AND rs.contract_id = c.contract_id
      AND c.segment_id IS NOT NULL;

    -- Если остались NULL, устанавливаем значение по умолчанию
    UPDATE app.recording_sessions
    SET segment_id = 1
    WHERE segment_id IS NULL;

    -- Проверяем, что все записи имеют segment_id
    SELECT COUNT(*) INTO v_null_count
    FROM app.recording_sessions
    WHERE segment_id IS NULL;

    IF v_null_count > 0 THEN
        RAISE EXCEPTION 'Не удалось установить segment_id для % записей в recording_sessions', v_null_count;
    END IF;

    ALTER TABLE app.recording_sessions
        ALTER COLUMN segment_id SET NOT NULL;

    BEGIN
        ALTER TABLE app.recording_sessions
            ADD CONSTRAINT sessions_segment_fk FOREIGN KEY (segment_id) REFERENCES ref.segments(segment_id);
    EXCEPTION WHEN duplicate_object THEN
        NULL;
    END;
END $$;

CREATE INDEX IF NOT EXISTS idx_sessions_segment_date ON app.recording_sessions(segment_id, session_date);

DO $$
DECLARE
    v_null_count INTEGER;
    v_total_count INTEGER;
    v_updated_count INTEGER;
    v_updated_from_sessions INTEGER;
    v_updated_from_contracts INTEGER;
BEGIN
    -- Добавляем колонку, если её нет
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'app' AND table_name = 'audio_archives' AND column_name = 'segment_id'
    ) THEN
        ALTER TABLE app.audio_archives ADD COLUMN segment_id INTEGER;
    END IF;

    -- Временно снимаем NOT NULL, если он установлен (чтобы можно было обновить NULL значения)
    BEGIN
        ALTER TABLE app.audio_archives ALTER COLUMN segment_id DROP NOT NULL;
    EXCEPTION WHEN OTHERS THEN
        NULL; -- Игнорируем ошибки
    END;

    -- Подсчитываем общее количество записей
    SELECT COUNT(*) INTO v_total_count FROM app.audio_archives;

    -- ШАГ 1: Обновляем segment_id в recording_sessions из contracts (если еще не обновлено)
    UPDATE app.recording_sessions rs
    SET segment_id = c.segment_id
    FROM app.contracts c
    WHERE rs.segment_id IS NULL
      AND rs.contract_id = c.contract_id
      AND c.segment_id IS NOT NULL;
    
    GET DIAGNOSTICS v_updated_from_contracts = ROW_COUNT;
    
    IF v_updated_from_contracts > 0 THEN
        RAISE NOTICE 'Обновлено segment_id для % сессий из контрактов', v_updated_from_contracts;
    END IF;

    -- ШАГ 2: Обновляем segment_id в audio_archives из связанных recording_sessions
    UPDATE app.audio_archives aa
    SET segment_id = rs.segment_id
    FROM app.recording_sessions rs
    WHERE aa.segment_id IS NULL
      AND aa.session_id = rs.session_id
      AND rs.segment_id IS NOT NULL;

    GET DIAGNOSTICS v_updated_from_sessions = ROW_COUNT;
    
    IF v_updated_from_sessions > 0 THEN
        RAISE NOTICE 'Обновлено segment_id для % архивов из сессий', v_updated_from_sessions;
    END IF;

    -- ШАГ 3: Если остались записи без segment_id, устанавливаем значение по умолчанию (сегмент 1)
    UPDATE app.audio_archives
    SET segment_id = 1
    WHERE segment_id IS NULL;

    GET DIAGNOSTICS v_updated_count = ROW_COUNT;
    
    IF v_updated_count > 0 THEN
        RAISE NOTICE 'Установлен segment_id = 1 по умолчанию для % архивов', v_updated_count;
    END IF;

    -- Проверяем, что все записи имеют segment_id
    SELECT COUNT(*) INTO v_null_count
    FROM app.audio_archives
    WHERE segment_id IS NULL;

    IF v_null_count > 0 THEN
        RAISE EXCEPTION 'Не удалось установить segment_id для % записей из % в audio_archives. Обновлено из sessions: %, из contracts: %', v_null_count, v_total_count, v_updated_from_sessions, v_updated_from_contracts;
    END IF;

    -- Теперь устанавливаем NOT NULL
    ALTER TABLE app.audio_archives
        ALTER COLUMN segment_id SET NOT NULL;

    -- Добавляем внешний ключ
    BEGIN
        ALTER TABLE app.audio_archives
            ADD CONSTRAINT audio_segment_fk FOREIGN KEY (segment_id) REFERENCES ref.segments(segment_id);
    EXCEPTION WHEN duplicate_object THEN
        NULL;
    END;

    RAISE NOTICE 'audio_archives: установлен segment_id для всех % записей', v_total_count;
END $$;

CREATE INDEX IF NOT EXISTS idx_audio_segment_session ON app.audio_archives(segment_id, session_id);

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'app' AND table_name = 'voice_roles' AND column_name = 'segment_id'
    ) THEN
        ALTER TABLE app.voice_roles ADD COLUMN segment_id INTEGER;
    END IF;

    UPDATE app.voice_roles vr
    SET segment_id = p.segment_id
    FROM app.projects p
    WHERE vr.segment_id IS NULL
      AND vr.project_id = p.project_id;

    ALTER TABLE app.voice_roles
        ALTER COLUMN segment_id SET NOT NULL;

    BEGIN
        ALTER TABLE app.voice_roles
            ADD CONSTRAINT voice_roles_segment_fk FOREIGN KEY (segment_id) REFERENCES ref.segments(segment_id);
    EXCEPTION WHEN duplicate_object THEN
        NULL;
    END;
END $$;

CREATE INDEX IF NOT EXISTS idx_voice_roles_segment_project ON app.voice_roles(segment_id, project_id);

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'app' AND table_name = 'actors' AND column_name = 'segment_id'
    ) THEN
        ALTER TABLE app.actors ADD COLUMN segment_id INTEGER;
    END IF;

    UPDATE app.actors a
    SET segment_id = (
        SELECT c.segment_id
        FROM app.contracts c
        WHERE c.actor_id = a.actor_id
        ORDER BY c.contract_id
        LIMIT 1
    )
    WHERE a.segment_id IS NULL;

    UPDATE app.actors
    SET segment_id = 1
    WHERE segment_id IS NULL;

    ALTER TABLE app.actors
        ALTER COLUMN segment_id SET NOT NULL;

    BEGIN
        ALTER TABLE app.actors
            ADD CONSTRAINT actors_segment_fk FOREIGN KEY (segment_id) REFERENCES ref.segments(segment_id);
    EXCEPTION WHEN duplicate_object THEN
        NULL;
    END;
END $$;

CREATE INDEX IF NOT EXISTS idx_actors_segment ON app.actors(segment_id, actor_id);

DO $$
BEGIN
    RAISE NOTICE 'LR3: сегментация успешно применена';
END $$;

RESET ROLE;

