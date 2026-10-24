-- 02_tables.sql
-- Создание таблиц базы данных

-- Устанавливаем поисковый путь
SET search_path TO app, ref, audit, stg, public;

-- Устанавливаем роль для создания объектов
SET ROLE app_owner;

-- Таблицы в схеме ref (справочники)
CREATE TABLE ref.studios (
    studio_id SERIAL PRIMARY KEY,
    studio_name VARCHAR(100) NOT NULL,
    contact_email VARCHAR(100),
    phone VARCHAR(20),
    address TEXT,
    bank_details TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE ref.languages (
    language_id SERIAL PRIMARY KEY,
    language_code VARCHAR(10) NOT NULL UNIQUE,
    language_name VARCHAR(50) NOT NULL,
    is_active BOOLEAN DEFAULT true
);

-- Таблицы в схеме app (бизнес-данные)
CREATE TABLE app.actors (
    actor_id SERIAL PRIMARY KEY,
    last_name VARCHAR(100) NOT NULL,
    first_name VARCHAR(100) NOT NULL,
    middle_name VARCHAR(100),
    phone VARCHAR(20),
    email VARCHAR(100),
    passport_data TEXT,
    tax_id VARCHAR(50),
    voice_characteristics TEXT,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE app.projects (
    project_id SERIAL PRIMARY KEY,
    studio_id INTEGER NOT NULL REFERENCES ref.studios(studio_id),
    title VARCHAR(300) NOT NULL,
    original_language VARCHAR(10) NOT NULL,
    description TEXT,
    client_contacts TEXT,
    budget DECIMAL(15,2),
    start_date DATE,
    end_date DATE,
    status VARCHAR(20) DEFAULT 'active',
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE app.contracts (
    contract_id SERIAL PRIMARY KEY,
    project_id INTEGER NOT NULL REFERENCES app.projects(project_id),
    actor_id INTEGER NOT NULL REFERENCES app.actors(actor_id),
    contract_number VARCHAR(50) NOT NULL UNIQUE,
    role_description TEXT NOT NULL,
    salary_amount DECIMAL(10,2) NOT NULL,
    currency VARCHAR(3) DEFAULT 'USD',
    terms TEXT,
    signed_date DATE,
    end_date DATE,
    status VARCHAR(20) DEFAULT 'active',
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE app.recording_sessions (
    session_id SERIAL PRIMARY KEY,
    contract_id INTEGER NOT NULL REFERENCES app.contracts(contract_id),
    session_date DATE NOT NULL,
    session_time TIME NOT NULL,
    studio_location VARCHAR(100) NOT NULL,
    duration_hours DECIMAL(4,2),
    status VARCHAR(20) DEFAULT 'scheduled',
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE app.audio_archives (
    archive_id SERIAL PRIMARY KEY,
    session_id INTEGER NOT NULL REFERENCES app.recording_sessions(session_id),
    file_name VARCHAR(255) NOT NULL,
    file_path TEXT NOT NULL,
    file_size BIGINT,
    duration_seconds INTEGER,
    encrypted_audio BYTEA,
    encryption_key_id VARCHAR(100),
    quality_check_passed BOOLEAN DEFAULT false,
    upload_date TIMESTAMPTZ DEFAULT NOW(),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE app.voice_roles (
    role_id SERIAL PRIMARY KEY,
    project_id INTEGER NOT NULL REFERENCES app.projects(project_id),
    actor_id INTEGER NOT NULL REFERENCES app.actors(actor_id),
    language_id INTEGER NOT NULL REFERENCES ref.languages(language_id),
    character_name VARCHAR(100) NOT NULL,
    role_type VARCHAR(50) NOT NULL,
    difficulty_level INTEGER CHECK (difficulty_level BETWEEN 1 AND 5),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(project_id, actor_id, language_id, character_name)
);

-- Таблицы в схеме audit (логирование)
CREATE TABLE audit.login_log (
    log_id BIGSERIAL PRIMARY KEY,
    login_time TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    username VARCHAR(100) NOT NULL,
    client_ip INET,
    connection_method VARCHAR(50),
    is_successful BOOLEAN DEFAULT true,
    failure_reason TEXT
);

CREATE TABLE audit.data_access_log (
    access_id BIGSERIAL PRIMARY KEY,
    access_time TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    username VARCHAR(100) NOT NULL,
    table_name VARCHAR(100) NOT NULL,
    operation_type VARCHAR(10) NOT NULL,
    record_id INTEGER,
    old_values JSONB,
    new_values JSONB,
    client_ip INET
);

-- Таблицы в схеме stg (временные/обслуживающие данные)
CREATE TABLE stg.import_log (
    import_id SERIAL PRIMARY KEY,
    import_date TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    source_file VARCHAR(255) NOT NULL,
    records_processed INTEGER DEFAULT 0,
    records_success INTEGER DEFAULT 0,
    records_failed INTEGER DEFAULT 0,
    status VARCHAR(20) DEFAULT 'running',
    error_message TEXT,
    created_by VARCHAR(100) NOT NULL
);

CREATE TABLE stg.temp_actor_data (
    temp_id SERIAL PRIMARY KEY,
    last_name VARCHAR(100),
    first_name VARCHAR(100),
    middle_name VARCHAR(100),
    phone VARCHAR(20),
    email VARCHAR(100),
    voice_characteristics TEXT,
    import_batch_id INTEGER,
    validation_status VARCHAR(20) DEFAULT 'pending',
    validation_errors TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Создаём индексы для производительности
CREATE INDEX idx_contracts_project_id ON app.contracts(project_id);
CREATE INDEX idx_contracts_actor_id ON app.contracts(actor_id);
CREATE INDEX idx_sessions_contract_id ON app.recording_sessions(contract_id);
CREATE INDEX idx_audio_session_id ON app.audio_archives(session_id);
CREATE INDEX idx_voice_roles_project_id ON app.voice_roles(project_id);
CREATE INDEX idx_voice_roles_actor_id ON app.voice_roles(actor_id);
CREATE INDEX idx_voice_roles_language_id ON app.voice_roles(language_id);
CREATE INDEX idx_actors_active ON app.actors(is_active) WHERE is_active = true;
CREATE INDEX idx_projects_status ON app.projects(status);
CREATE INDEX idx_contracts_status ON app.contracts(status);
CREATE INDEX idx_sessions_date ON app.recording_sessions(session_date);
CREATE INDEX idx_login_log_time ON audit.login_log(login_time);
CREATE INDEX idx_login_log_user ON audit.login_log(username);

-- Комментарии к таблицам и колонкам
COMMENT ON TABLE ref.studios IS 'Студии дубляжа';
COMMENT ON COLUMN ref.studios.bank_details IS 'Confidential: Банковские реквизиты';
COMMENT ON TABLE ref.languages IS 'Языки для дубляжа';
COMMENT ON TABLE app.actors IS 'Актёры озвучивания';
COMMENT ON COLUMN app.actors.last_name IS 'Internal: Фамилия актёра';
COMMENT ON COLUMN app.actors.first_name IS 'Internal: Имя актёра';
COMMENT ON COLUMN app.actors.middle_name IS 'Internal: Отчество актёра';
COMMENT ON COLUMN app.actors.passport_data IS 'Restricted: Паспортные данные';
COMMENT ON COLUMN app.actors.tax_id IS 'Confidential: ИНН/налоговый номер';
COMMENT ON TABLE app.projects IS 'Проекты дубляжа (фильмы, сериалы)';
COMMENT ON COLUMN app.projects.client_contacts IS 'Internal: Контакты клиента';
COMMENT ON TABLE app.contracts IS 'Контракты с актёрами';
COMMENT ON COLUMN app.contracts.salary_amount IS 'Confidential: Сумма контракта';
COMMENT ON COLUMN app.contracts.terms IS 'Confidential: Условия контракта';
COMMENT ON TABLE app.recording_sessions IS 'Сессии записи дубляжа';
COMMENT ON TABLE app.audio_archives IS 'Архив аудиофайлов';
COMMENT ON TABLE app.voice_roles IS 'Роли озвучивания';
COMMENT ON TABLE audit.login_log IS 'Логи подключений пользователей';
COMMENT ON TABLE audit.data_access_log IS 'Логи доступа к данным';

-- Сбрасываем роль
RESET ROLE;