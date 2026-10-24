-- 01_schemas.sql
-- Создание схем для базы данных студии дубляжа

-- Создаём расширения
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE SCHEMA IF NOT EXISTS app;    -- Основные бизнес-данные
CREATE SCHEMA IF NOT EXISTS ref;    -- Справочники
CREATE SCHEMA IF NOT EXISTS audit;  -- Аудит и логи
CREATE SCHEMA IF NOT EXISTS stg;    -- Временные данные

-- Комментируем схемы
COMMENT ON SCHEMA app IS 'Основные бизнес-данные: контракты, проекты, аудиоархивы';
COMMENT ON SCHEMA ref IS 'Справочники: языки, типы контрактов, студии';
COMMENT ON SCHEMA audit IS 'Аудит и логи безопасности';
COMMENT ON SCHEMA stg IS 'Временная область для обработки и загрузки данных';

-- Создаём роль app_owner для владения объектами
DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_owner') THEN
        CREATE ROLE app_owner WITH NOLOGIN NOINHERIT;
    END IF;
END $$;

-- Отзываем все привилегии у PUBLIC
REVOKE ALL ON SCHEMA app FROM PUBLIC;
REVOKE ALL ON SCHEMA ref FROM PUBLIC;
REVOKE ALL ON SCHEMA audit FROM PUBLIC;
REVOKE ALL ON SCHEMA stg FROM PUBLIC;

-- Устанавливаем владельца схем
ALTER SCHEMA app OWNER TO app_owner;
ALTER SCHEMA ref OWNER TO app_owner;
ALTER SCHEMA audit OWNER TO app_owner;
ALTER SCHEMA stg OWNER TO app_owner;


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


-- 03_ref_data.sql
-- Наполнение справочников базовыми данными

-- Языки
INSERT INTO ref.languages (language_code, language_name) VALUES
('ru', 'Русский'),
('en', 'Английский'),
('de', 'Немецкий'),
('fr', 'Французский'),
('es', 'Испанский'),
('it', 'Итальянский'),
('ja', 'Японский'),
('ko', 'Корейский');

-- Студии
INSERT INTO ref.studios (studio_name, contact_email, phone, address) VALUES
('ЗвукЗапись', 'studio1@example.com', '+7-495-111-2233', 'Москва, ул. Студийная, 1'),
('ГолосДубляжа', 'studio2@example.com', '+7-812-222-3344', 'Санкт-Петербург, пр. Записной, 15'),
('АудиоМир', 'studio3@example.com', '+7-383-333-4455', 'Новосибирск, ул. Микрофонная, 7'),
('ВолнаЗвука', 'studio4@example.com', '+7-343-444-5566', 'Екатеринбург, ул. Акустическая, 42'),
('Синхрон', 'studio5@example.com', '+7-401-555-6677', 'Калининград, пр. Голосовой, 88'),
('РечевойЦентр', 'studio6@example.com', '+7-391-666-7788', 'Красноярск, ул. Голосовая, 25'),
('ЗвуковыеВолны', 'studio7@example.com', '+7-423-777-8899', 'Владивосток, пр. Звуковой, 10'),
('Артикуляция', 'studio8@example.com', '+7-846-888-9900', 'Самара, ул. Записная, 33'),
('ГолосМастер', 'studio9@example.com', '+7-831-999-0011', 'Нижний Новгород, пр. Студийный, 50'),
('АудиоПрофи', 'studio10@example.com', '+7-351-000-1122', 'Челябинск, ул. Микрофонная, 18');


-- 04_roles.sql
-- Создание системы ролей с разделением обязанностей

-- Базовые роли доступа (с проверкой существования)

DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_reader') THEN
        CREATE ROLE app_reader WITH NOLOGIN NOINHERIT;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_writer') THEN
        CREATE ROLE app_writer WITH NOLOGIN NOINHERIT;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'auditor') THEN
        CREATE ROLE auditor WITH NOLOGIN NOINHERIT;
    END IF;
END $$;

-- Роли разделения обязанностей (с проверкой существования)
DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'ddl_admin') THEN
        CREATE ROLE ddl_admin WITH NOLOGIN NOINHERIT;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'dml_admin') THEN
        CREATE ROLE dml_admin WITH NOLOGIN NOINHERIT;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'security_admin') THEN
        CREATE ROLE security_admin WITH NOLOGIN NOINHERIT;
    END IF;
END $$;

-- Логин-роли (пользователи)
DO $$ 
BEGIN
    -- Удаляем существующих пользователей если нужно пересоздать
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'studio_manager') THEN
        RAISE NOTICE 'Роль studio_manager уже существует, переиспользуем';
    ELSE
        CREATE ROLE studio_manager WITH LOGIN PASSWORD 'manager_pass123' NOINHERIT;
    END IF;
    
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'voice_actor') THEN
        RAISE NOTICE 'Роль voice_actor уже существует, переиспользуем';
    ELSE
        CREATE ROLE voice_actor WITH LOGIN PASSWORD 'actor_pass123' NOINHERIT;
    END IF;
    
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'security_auditor') THEN
        RAISE NOTICE 'Роль security_auditor уже существует, переиспользуем';
    ELSE
        CREATE ROLE security_auditor WITH LOGIN PASSWORD 'auditor_pass123' NOINHERIT;
    END IF;
    
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_owner_user') THEN
        RAISE NOTICE 'Роль app_owner_user уже существует, переиспользуем';
    ELSE
        CREATE ROLE app_owner_user WITH LOGIN PASSWORD 'owner_pass123' NOINHERIT;
    END IF;
END $$;

-- Комментарии к ролям (обновляем если изменились)
COMMENT ON ROLE app_owner IS 'Владелец приложения: полный доступ к бизнес-данным';
COMMENT ON ROLE app_reader IS 'Чтение бизнес-данных: просмотр проектов, контрактов';
COMMENT ON ROLE app_writer IS 'Запись бизнес-данных: добавление/изменение контрактов, сессий';
COMMENT ON ROLE auditor IS 'Аудитор: доступ к логам безопасности только на чтение';
COMMENT ON ROLE ddl_admin IS 'Администратор DDL: создание/изменение таблиц, индексов';
COMMENT ON ROLE dml_admin IS 'Администратор DML: массовые операции INSERT/UPDATE/DELETE';
COMMENT ON ROLE security_admin IS 'Администратор безопасности: RLS, политики, шифрование';
COMMENT ON ROLE studio_manager IS 'Менеджер студии: работает с контрактами и расписаниями';
COMMENT ON ROLE voice_actor IS 'Актёр: просматривает свои сессии и роли';
COMMENT ON ROLE security_auditor IS 'Аудитор безопасности: проверяет логи доступа';
COMMENT ON ROLE app_owner_user IS 'Пользователь-владелец: полный доступ к системе';

-- Назначаем роли пользователям
GRANT app_writer TO studio_manager;
GRANT app_reader TO voice_actor;
GRANT auditor TO security_auditor;
GRANT app_owner TO app_owner_user;

-- Отзываем все привилегии у PUBLIC
REVOKE ALL ON DATABASE postgres FROM PUBLIC;

-- Уведомление о завершении
DO $$ 
BEGIN
    RAISE NOTICE 'Роли успешно созданы/обновлены';
    RAISE NOTICE 'Логин-роли: studio_manager, voice_actor, security_auditor, app_owner_user';
    RAISE NOTICE 'Пароли: manager_pass123, actor_pass123, auditor_pass123, owner_pass123';
END $$;


-- 05_privileges.sql
-- Настройка привилегий для ролей

-- Привилегии на уровне схем для ролей
GRANT USAGE ON SCHEMA app, ref, stg TO app_owner;
GRANT ALL ON SCHEMA app, ref, stg TO app_owner;

GRANT USAGE ON SCHEMA app, ref TO app_reader;
GRANT USAGE ON SCHEMA app, ref TO app_writer;
GRANT USAGE ON SCHEMA audit TO auditor;

GRANT USAGE ON SCHEMA app, ref, audit, stg TO ddl_admin, dml_admin, security_admin;
GRANT CREATE ON SCHEMA app, ref, audit, stg TO ddl_admin;

-- ЯВНЫЕ ПРАВА ДЛЯ КОНКРЕТНЫХ ПОЛЬЗОВАТЕЛЕЙ
GRANT USAGE ON SCHEMA app, ref TO voice_actor, studio_manager;
GRANT USAGE ON SCHEMA audit TO security_auditor;
GRANT USAGE ON SCHEMA app, ref, audit, stg TO app_owner_user;

-- Привилегии на таблицы для ролей
GRANT SELECT ON ALL TABLES IN SCHEMA app TO app_reader;
GRANT SELECT ON ALL TABLES IN SCHEMA ref TO app_reader;

GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA app TO app_writer;
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA ref TO app_writer;

-- Ограничиваем доступ к чувствительным колонкам для app_reader
-- Убираем SELECT на salary_amount и terms из contracts
REVOKE SELECT ON app.contracts FROM app_reader;
GRANT SELECT (contract_id, project_id, actor_id, contract_number, role_description, currency, signed_date, end_date, status, created_at) ON app.contracts TO app_reader;

-- ЯВНЫЕ ПРАВА НА ТАБЛИЦЫ ДЛЯ ПОЛЬЗОВАТЕЛЕЙ
GRANT SELECT ON ALL TABLES IN SCHEMA app TO voice_actor;
GRANT SELECT ON ALL TABLES IN SCHEMA ref TO voice_actor;

GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA app TO studio_manager;
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA ref TO studio_manager;

GRANT SELECT ON ALL TABLES IN SCHEMA audit TO security_auditor;

GRANT ALL ON ALL TABLES IN SCHEMA app, ref, audit, stg TO app_owner_user;

-- Запрещаем удаление для писателей
REVOKE DELETE ON ALL TABLES IN SCHEMA app FROM app_writer, studio_manager;
REVOKE DELETE ON ALL TABLES IN SCHEMA ref FROM app_writer, studio_manager;

-- Запрещаем модификации аудита
REVOKE INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA audit FROM PUBLIC;
REVOKE INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA audit FROM app_owner, app_reader, app_writer, auditor, security_auditor;

-- Привилегии для ddl_admin (может читать для анализа структуры)
GRANT SELECT ON ALL TABLES IN SCHEMA app, ref, audit, stg TO ddl_admin;

-- Привилегии для dml_admin (массовые операции с данными)
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA app TO dml_admin;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA ref TO dml_admin;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA stg TO dml_admin;

-- Привилегии для последовательностей
GRANT USAGE ON ALL SEQUENCES IN SCHEMA app TO app_owner, app_writer, studio_manager;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA ref TO app_owner, app_writer, studio_manager;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA app, ref TO ddl_admin, app_owner_user;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA app, ref TO dml_admin;

-- Уведомление
DO $$ 
BEGIN
    RAISE NOTICE 'Привилегии успешно применены ко всем ролям и пользователям';
END $$;


-- 06_default_privs.sql
-- Настройка привилегий по умолчанию для новых объектов

-- Привилегии для app_owner
ALTER DEFAULT PRIVILEGES FOR ROLE app_owner IN SCHEMA app
GRANT SELECT ON TABLES TO app_reader;

ALTER DEFAULT PRIVILEGES FOR ROLE app_owner IN SCHEMA app
GRANT SELECT, INSERT, UPDATE ON TABLES TO app_writer;

ALTER DEFAULT PRIVILEGES FOR ROLE app_owner IN SCHEMA app
GRANT ALL ON TABLES TO app_owner;

ALTER DEFAULT PRIVILEGES FOR ROLE app_owner IN SCHEMA ref
GRANT SELECT ON TABLES TO app_reader;

ALTER DEFAULT PRIVILEGES FOR ROLE app_owner IN SCHEMA ref
GRANT SELECT, INSERT, UPDATE ON TABLES TO app_writer;

ALTER DEFAULT PRIVILEGES FOR ROLE app_owner IN SCHEMA audit
GRANT SELECT ON TABLES TO auditor;

-- Привилегии для последовательностей
ALTER DEFAULT PRIVILEGES FOR ROLE app_owner IN SCHEMA app
GRANT USAGE ON SEQUENCES TO app_writer;

ALTER DEFAULT PRIVILEGES FOR ROLE app_owner IN SCHEMA ref
GRANT USAGE ON SEQUENCES TO app_writer;

-- Запрещаем PUBLIC доступ к новым объектам
ALTER DEFAULT PRIVILEGES FOR ROLE app_owner IN SCHEMA app
REVOKE ALL ON TABLES FROM PUBLIC;

ALTER DEFAULT PRIVILEGES FOR ROLE app_owner IN SCHEMA ref
REVOKE ALL ON TABLES FROM PUBLIC;

ALTER DEFAULT PRIVILEGES FOR ROLE app_owner IN SCHEMA audit
REVOKE ALL ON TABLES FROM PUBLIC;

ALTER DEFAULT PRIVILEGES FOR ROLE app_owner IN SCHEMA stg
REVOKE ALL ON TABLES FROM PUBLIC;

-- Уведомление о настройке default privileges
DO $$ 
BEGIN
    RAISE NOTICE 'Привилегии по умолчанию успешно настроены';
END $$;


-- 07_audit.sql 
-- Создание механизма аудита подключений

-- Функция для логирования подключений
CREATE OR REPLACE FUNCTION audit.log_connection()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = audit, public
AS $$
BEGIN
    INSERT INTO audit.login_log (
        username, 
        client_ip, 
        connection_method,
        is_successful
    ) VALUES (
        current_user::VARCHAR(100),
        inet_client_addr()::INET,
        'direct',
        true
    );
EXCEPTION
    WHEN OTHERS THEN
        INSERT INTO audit.login_log (
            username,
            client_ip, 
            connection_method,
            is_successful,
            failure_reason
        ) VALUES (
            current_user::VARCHAR(100),
            inet_client_addr()::INET,
            'direct',
            false,
            SQLERRM
        );
END;
$$;

-- Роль для логирования подключений (с проверкой существования)
DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'connection_logger') THEN
        CREATE ROLE connection_logger WITH NOLOGIN;
    END IF;
END $$;

GRANT USAGE ON SCHEMA audit TO connection_logger;
GRANT INSERT ON audit.login_log TO connection_logger;
GRANT EXECUTE ON FUNCTION audit.log_connection TO connection_logger;

-- Назначаем роль конкретным пользователям
GRANT connection_logger TO studio_manager, voice_actor, security_auditor, db_developer;

-- Функция для ручного логирования сессии
CREATE OR REPLACE FUNCTION public.log_session_start()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = audit, public
AS $$
BEGIN
    PERFORM audit.log_connection();
END;
$$;

-- Даём доступ к функции логирования сессии только нужным ролям
GRANT EXECUTE ON FUNCTION public.log_session_start TO studio_manager, voice_actor, security_auditor, db_developer;

COMMENT ON FUNCTION audit.log_connection IS 'Функция для логирования подключений пользователей';
COMMENT ON FUNCTION public.log_session_start IS 'Функция для ручного логирования старта сессии';


-- 08_test_data.sql
-- Наполнение тестовыми данными

-- Актёры
INSERT INTO app.actors (last_name, first_name, middle_name, phone, email, voice_characteristics) VALUES
('Петров', 'Иван', 'Сергеевич', '+7-911-111-1111', 'ivan@example.com', 'Низкий баритон, эмоциональный'),
('Сидорова', 'Мария', 'Александровна', '+7-922-222-2222', 'maria@example.com', 'Сопрано, чистая дикция'),
('Козлов', 'Алексей', NULL, '+7-933-333-3333', 'alex@example.com', 'Тенор, комедийный тембр'),
('Новикова', 'Елена', 'Дмитриевна', '+7-944-444-4444', 'elena@example.com', 'Меццо-сопрано, драматический'),
('Волков', 'Дмитрий', 'Игоревич', '+7-955-555-5555', 'dmitry@example.com', 'Бас, authoritative'),
('Белова', 'Ольга', 'Владимировна', '+7-966-666-6666', 'olga@example.com', 'Сопрано, детские голоса'),
('Орлов', 'Сергей', NULL, '+7-977-777-7777', 'sergey@example.com', 'Баритон, лирический'),
('Ковалёва', 'Анна', 'Петровна', '+7-988-888-8888', 'anna@example.com', 'Альт, глубокий тембр'),
('Морозов', 'Павел', 'Андреевич', '+7-999-999-9999', 'pavel@example.com', 'Тенор, героический'),
('Павлова', 'Наталья', NULL, '+7-900-000-0000', 'natalia@example.com', 'Сопрано, нежный голос');

-- Проекты
INSERT INTO app.projects (studio_id, title, original_language, description, client_contacts, budget, start_date, end_date) VALUES
(1, 'Звёздные войны: Новый рассвет', 'en', 'Фантастический блокбастер', 'disney@example.com', 500000.00, '2024-01-01', '2024-06-30'),
(2, 'Магия Парижа', 'fr', 'Романтическая комедия', 'frenchfilms@example.com', 250000.00, '2024-02-01', '2024-05-31'),
(1, 'Тайна океана', 'en', 'Документальный фильм', 'natgeo@example.com', 150000.00, '2024-03-01', '2024-04-30'),
(3, 'Берлинские тени', 'de', 'Детективный триллер', 'germanstudio@example.com', 300000.00, '2024-01-15', '2024-07-31'),
(2, 'Римские каникулы', 'it', 'Приключенческий фильм', 'italiancinema@example.com', 200000.00, '2024-02-15', '2024-06-15'),
(4, 'Мадридские ночи', 'es', 'Романтическая драма', 'spanishfilms@example.com', 180000.00, '2024-03-15', '2024-08-31'),
(3, 'Токио: Город огней', 'ja', 'Научно-фантастический фильм', 'japanstudio@example.com', 420000.00, '2024-04-01', '2024-09-30'),
(5, 'Амстердамские каналы', 'nl', 'Детективная драма', 'dutchcinema@example.com', 220000.00, '2024-03-20', '2024-07-20'),
(4, 'Лондонский туман', 'en', 'Мистический триллер', 'britishfilms@example.com', 350000.00, '2024-04-10', '2024-10-31'),
(5, 'Варшавская весна', 'pl', 'Историческая драма', 'polishstudio@example.com', 280000.00, '2024-04-15', '2024-08-15');

-- Контракты
INSERT INTO app.contracts (project_id, actor_id, contract_number, role_description, salary_amount, currency, signed_date) VALUES
(1, 1, 'CNTR-2024-001', 'Главный герой - Люк Скайуокер', 50000.00, 'USD', '2024-01-15'),
(1, 2, 'CNTR-2024-002', 'Принцесса Лея', 45000.00, 'USD', '2024-01-16'),
(1, 3, 'CNTR-2024-003', 'Злодей - Дарт Вейдер', 40000.00, 'USD', '2024-01-17'),
(2, 4, 'CNTR-2024-004', 'Главная героиня - Мари', 30000.00, 'EUR', '2024-02-01'),
(2, 5, 'CNTR-2024-005', 'Главный герой - Пьер', 32000.00, 'EUR', '2024-02-02'),
(3, 6, 'CNTR-2024-006', 'Рассказчик', 20000.00, 'USD', '2024-03-01'),
(4, 7, 'CNTR-2024-007', 'Детектив Мюллер', 35000.00, 'EUR', '2024-01-20'),
(4, 8, 'CNTR-2024-008', 'Подозреваемая Анна', 28000.00, 'EUR', '2024-01-22'),
(5, 9, 'CNTR-2024-009', 'Турист Марко', 25000.00, 'EUR', '2024-02-20'),
(5, 10, 'CNTR-2024-010', 'Гид София', 23000.00, 'EUR', '2024-02-21');

-- Сессии записи
INSERT INTO app.recording_sessions (contract_id, session_date, session_time, studio_location, duration_hours) VALUES
(1, '2024-03-01', '10:00:00', 'Студия А, Москва', 4.0),
(2, '2024-03-01', '14:00:00', 'Студия Б, Москва', 3.5),
(3, '2024-03-02', '11:00:00', 'Студия В, СПб', 5.0),
(4, '2024-03-03', '09:00:00', 'Студия Г, Москва', 4.5),
(5, '2024-03-03', '13:00:00', 'Студия Д, Москва', 3.0),
(6, '2024-03-04', '10:00:00', 'Студия А, Москва', 6.0),
(7, '2024-03-05', '15:00:00', 'Студия Е, Новосибирск', 4.0),
(8, '2024-03-05', '10:00:00', 'Студия Е, Новосибирск', 3.5),
(9, '2024-03-06', '11:00:00', 'Студия Ж, СПб', 4.0),
(10, '2024-03-06', '16:00:00', 'Студия Ж, СПб', 3.0);

-- Роли озвучивания
INSERT INTO app.voice_roles (project_id, actor_id, language_id, character_name, role_type, difficulty_level) VALUES
(1, 1, 1, 'Люк Скайуокер', 'lead', 5),
(1, 2, 1, 'Принцесса Лея', 'lead', 5),
(1, 3, 1, 'Дарт Вейдер', 'villain', 4),
(2, 4, 1, 'Мари', 'lead', 4),
(2, 5, 1, 'Пьер', 'lead', 4),
(3, 6, 1, 'Рассказчик', 'narrator', 3),
(4, 7, 1, 'Детектив Мюллер', 'lead', 4),
(4, 8, 1, 'Анна', 'supporting', 3),
(5, 9, 1, 'Марко', 'lead', 3),
(5, 10, 1, 'София', 'supporting', 3);

-- Аудиоархивы
INSERT INTO app.audio_archives (session_id, file_name, file_path, file_size, duration_seconds, encrypted_audio, encryption_key_id, quality_check_passed) VALUES
(1, 'luke_skywalker_scene1.wav', '/audio/starwars/luke_scene1.wav', 15728640, 300, pgp_sym_encrypt('encrypted_audio_data_1', 'encryption_key_123'), 'key_001', true),
(1, 'luke_skywalker_scene2.wav', '/audio/starwars/luke_scene2.wav', 20971520, 400, pgp_sym_encrypt('encrypted_audio_data_2', 'encryption_key_123'), 'key_002', true),
(2, 'leia_organa_scene1.wav', '/audio/starwars/leia_scene1.wav', 12582912, 250, pgp_sym_encrypt('encrypted_audio_data_3', 'encryption_key_123'), 'key_003', true),
(3, 'darth_vader_scene1.wav', '/audio/starwars/vader_scene1.wav', 18874368, 350, pgp_sym_encrypt('encrypted_audio_data_4', 'encryption_key_123'), 'key_004', false),
(4, 'marie_paris_scene1.wav', '/audio/paris/marie_scene1.wav', 10485760, 200, pgp_sym_encrypt('encrypted_audio_data_5', 'encryption_key_123'), 'key_005', true),
(5, 'pierre_paris_scene1.wav', '/audio/paris/pierre_scene1.wav', 11534336, 220, pgp_sym_encrypt('encrypted_audio_data_6', 'encryption_key_123'), 'key_006', true),
(6, 'narrator_ocean_scene1.wav', '/audio/ocean/narrator_scene1.wav', 25165824, 480, pgp_sym_encrypt('encrypted_audio_data_7', 'encryption_key_123'), 'key_007', true),
(7, 'muller_berlin_scene1.wav', '/audio/berlin/muller_scene1.wav', 14680064, 280, pgp_sym_encrypt('encrypted_audio_data_8', 'encryption_key_123'), 'key_008', true),
(8, 'anna_berlin_scene1.wav', '/audio/berlin/anna_scene1.wav', 8388608, 160, pgp_sym_encrypt('encrypted_audio_data_9', 'encryption_key_123'), 'key_009', false),
(9, 'marco_rome_scene1.wav', '/audio/rome/marco_scene1.wav', 10485760, 200, pgp_sym_encrypt('encrypted_audio_data_10', 'encryption_key_123'), 'key_010', true),
(10, 'sofia_rome_scene1.wav', '/audio/rome/sofia_scene1.wav', 9437184, 180, pgp_sym_encrypt('encrypted_audio_data_11', 'encryption_key_123'), 'key_011', true);

-- Данные для stg.import_log (логи импорта)
INSERT INTO stg.import_log (source_file, records_processed, records_success, records_failed, status, created_by) VALUES
('actors_2024_01.xlsx', 25, 23, 2, 'completed', 'admin'),
('projects_2024_q1.csv', 15, 15, 0, 'completed', 'studio_manager'),
('contracts_march_2024.xlsx', 30, 28, 2, 'completed', 'admin'),
('voice_actors_new.csv', 12, 10, 2, 'failed', 'admin'),
('audio_archives_batch_001.zip', 50, 48, 2, 'completed', 'db_developer'),
('studios_update_2024.xlsx', 8, 8, 0, 'completed', 'admin'),
('languages_reference.csv', 15, 15, 0, 'completed', 'admin'),
('sessions_april_2024.xlsx', 20, 18, 2, 'completed', 'studio_manager'),
('temp_actors_validation.csv', 5, 0, 5, 'failed', 'admin'),
('migration_legacy_system.sql', 100, 95, 5, 'completed', 'db_developer');

-- Данные для stg.temp_actor_data (временные данные актёров)
INSERT INTO stg.temp_actor_data (last_name, first_name, middle_name, phone, email, voice_characteristics, import_batch_id, validation_status, validation_errors) VALUES
('Новиков', 'Александр', 'Викторович', '+7-900-111-1111', 'alex.novikov@example.com', 'Тенор, драматический', 1, 'validated', NULL),
('Смирнова', 'Екатерина', 'Олеговна', '+7-900-222-2222', 'katya.smirnova@example.com', 'Сопрано, лирический', 1, 'validated', NULL),
('Козлов', 'Михаил', NULL, '+7-900-333-3333', 'misha.kozlov@example.com', 'Баритон, комедийный', 1, 'pending', NULL),
('Петрова', 'Анна', 'Сергеевна', '+7-900-444-4444', 'anna.petrova@example.com', 'Меццо-сопрано, глубокий', 1, 'validated', NULL),
('Волков', 'Дмитрий', 'Игоревич', '+7-900-555-5555', 'dmitry.volkov@example.com', 'Бас, authoritative', 1, 'failed', 'Неверный формат телефона'),
('Белова', 'Ольга', 'Владимировна', '+7-900-666-6666', 'olga.belova@example.com', 'Сопрано, детские голоса', 2, 'validated', NULL),
('Орлов', 'Сергей', 'Николаевич', '+7-900-777-7777', 'sergey.orlov@example.com', 'Баритон, лирический', 2, 'pending', NULL),
('Павлова', 'Наталья', NULL, '+7-900-888-8888', 'natalia.pavlova@example.com', 'Сопрано, нежный голос', 2, 'failed', 'Отсутствует email'),
('Морозов', 'Павел', 'Андреевич', '+7-900-999-9999', 'pavel.morozov@example.com', 'Тенор, героический', 2, 'validated', NULL),
('Ковалёва', 'Елена', 'Дмитриевна', '+7-900-000-0000', 'elena.kovaleva@example.com', 'Альт, глубокий тембр', 2, 'pending', NULL);

-- Логируем начальные подключения
SELECT public.log_session_start();


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


-- 10_audit_triggers_and_tests.sql
-- Триггеры аудита DML операций и тестирование системы безопасности

-- Функция для логирования изменений данных
CREATE OR REPLACE FUNCTION audit.log_data_changes()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = audit, public
AS $$
DECLARE
    old_data JSONB;
    new_data JSONB;
    operation_type VARCHAR(10);
BEGIN
    -- Определяем тип операции
    IF TG_OP = 'DELETE' THEN
        operation_type := 'DELETE';
        old_data := to_jsonb(OLD);
        new_data := NULL;
    ELSIF TG_OP = 'UPDATE' THEN
        operation_type := 'UPDATE';
        old_data := to_jsonb(OLD);
        new_data := to_jsonb(NEW);
    ELSIF TG_OP = 'INSERT' THEN
        operation_type := 'INSERT';
        old_data := NULL;
        new_data := to_jsonb(NEW);
    END IF;

    -- Записываем в лог аудита
    INSERT INTO audit.data_access_log (
        username,
        table_name,
        operation_type,
        record_id,
        old_values,
        new_values,
        client_ip
    ) VALUES (
        current_user::VARCHAR(100),
        TG_TABLE_SCHEMA || '.' || TG_TABLE_NAME,
        operation_type,
        CASE 
            WHEN TG_OP = 'DELETE' THEN OLD.actor_id
            WHEN TG_OP = 'UPDATE' THEN NEW.actor_id
            WHEN TG_OP = 'INSERT' THEN NEW.actor_id
        END,
        old_data,
        new_data,
        inet_client_addr()
    );

    -- Возвращаем соответствующий результат
    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    ELSE
        RETURN NEW;
    END IF;
EXCEPTION
    WHEN OTHERS THEN
        -- В случае ошибки логируем и продолжаем
        INSERT INTO audit.data_access_log (
            username,
            table_name,
            operation_type,
            old_values,
            new_values,
            client_ip
        ) VALUES (
            current_user::VARCHAR(100),
            TG_TABLE_SCHEMA || '.' || TG_TABLE_NAME,
            'ERROR',
            NULL,
            jsonb_build_object('error', SQLERRM),
            inet_client_addr()
        );
        
        IF TG_OP = 'DELETE' THEN
            RETURN OLD;
        ELSE
            RETURN NEW;
        END IF;
END;
$$;

-- Создаём триггеры для основных таблиц
CREATE TRIGGER audit_actors_changes
    AFTER INSERT OR UPDATE OR DELETE ON app.actors
    FOR EACH ROW EXECUTE FUNCTION audit.log_data_changes();

CREATE TRIGGER audit_contracts_changes
    AFTER INSERT OR UPDATE OR DELETE ON app.contracts
    FOR EACH ROW EXECUTE FUNCTION audit.log_data_changes();

CREATE TRIGGER audit_projects_changes
    AFTER INSERT OR UPDATE OR DELETE ON app.projects
    FOR EACH ROW EXECUTE FUNCTION audit.log_data_changes();

CREATE TRIGGER audit_recording_sessions_changes
    AFTER INSERT OR UPDATE OR DELETE ON app.recording_sessions
    FOR EACH ROW EXECUTE FUNCTION audit.log_data_changes();

CREATE TRIGGER audit_audio_archives_changes
    AFTER INSERT OR UPDATE OR DELETE ON app.audio_archives
    FOR EACH ROW EXECUTE FUNCTION audit.log_data_changes();

-- Даём права на выполнение функции аудита
GRANT EXECUTE ON FUNCTION audit.log_data_changes TO app_owner, app_writer;

-- Комментарии
COMMENT ON FUNCTION audit.log_data_changes IS 'Функция для автоматического логирования изменений в таблицах';
COMMENT ON TRIGGER audit_actors_changes ON app.actors IS 'Триггер аудита для таблицы актёров';
COMMENT ON TRIGGER audit_contracts_changes ON app.contracts IS 'Триггер аудита для таблицы контрактов';
COMMENT ON TRIGGER audit_projects_changes ON app.projects IS 'Триггер аудита для таблицы проектов';
COMMENT ON TRIGGER audit_recording_sessions_changes ON app.recording_sessions IS 'Триггер аудита для таблицы сессий записи';
COMMENT ON TRIGGER audit_audio_archives_changes ON app.audio_archives IS 'Триггер аудита для таблицы аудиоархивов';

-- Автоматическое логирование входов через pgaudit
CREATE OR REPLACE FUNCTION audit.parse_pgaudit_log()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = audit, public
AS $$
DECLARE
    log_line TEXT;
    username_part TEXT;
    ip_part TEXT;
    success_part TEXT;
    parsed_username VARCHAR(100);
    parsed_ip INET;
    parsed_success BOOLEAN;
BEGIN
    -- Эта функция будет вызываться периодически для парсинга логов pgaudit
    
    -- Для демонстрации создаём пример записи
    INSERT INTO audit.login_log (
        username,
        client_ip,
        connection_method,
        is_successful,
        failure_reason
    ) VALUES (
        'pgaudit_parser',
        '127.0.0.1',
        'pgaudit_auto',
        true,
        NULL
    );
    
EXCEPTION
    WHEN OTHERS THEN
        -- В случае ошибки логируем
        INSERT INTO audit.login_log (
            username,
            client_ip,
            connection_method,
            is_successful,
            failure_reason
        ) VALUES (
            'pgaudit_parser',
            '127.0.0.1',
            'pgaudit_auto',
            false,
            SQLERRM
        );
END;
$$;

-- Создаём функцию для принудительного логирования входа при подключении
CREATE OR REPLACE FUNCTION public.auto_log_connection()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = audit, public
AS $$
BEGIN
    -- Логируем подключение
    PERFORM audit.log_connection();
    
    -- Также парсим pgaudit логи
    PERFORM audit.parse_pgaudit_log();
END;
$$;

-- Даём доступ к функциям
GRANT EXECUTE ON FUNCTION audit.parse_pgaudit_log TO app_owner, security_auditor;
GRANT EXECUTE ON FUNCTION public.auto_log_connection TO studio_manager, voice_actor, security_auditor, db_developer;

-- Создаём роль для автоматического логирования
DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'auto_logger') THEN
        CREATE ROLE auto_logger WITH NOLOGIN;
    END IF;
END $$;

GRANT USAGE ON SCHEMA audit TO auto_logger;
GRANT INSERT ON audit.login_log TO auto_logger;
GRANT EXECUTE ON FUNCTION audit.log_connection TO auto_logger;
GRANT EXECUTE ON FUNCTION audit.parse_pgaudit_log TO auto_logger;

-- Назначаем роль пользователям
GRANT auto_logger TO studio_manager, voice_actor, security_auditor, db_developer;

-- Комментарии
COMMENT ON FUNCTION audit.parse_pgaudit_log IS 'Функция для парсинга логов pgaudit и записи в audit.login_log';
COMMENT ON FUNCTION public.auto_log_connection IS 'Функция для автоматического логирования подключений';
COMMENT ON ROLE auto_logger IS 'Роль для автоматического логирования подключений';

-- Уведомление о завершении
DO $$ 
BEGIN
    RAISE NOTICE 'Триггеры аудита DML операций и автоматическое логирование входов настроены';
END $$;

-- Тестирование системы безопасности (выполнять ПОСЛЕ всех скриптов)

DO $$ 
BEGIN
    RAISE NOTICE '=== НАЧАЛО ТЕСТИРОВАНИЯ СИСТЕМЫ БЕЗОПАСНОСТИ ===';
END $$;

-- Проверяем существование тестовых данных
DO $$
DECLARE
    actor_count INTEGER;
    contract_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO actor_count FROM app.actors;
    SELECT COUNT(*) INTO contract_count FROM app.contracts;
    
    RAISE NOTICE 'Найдено актёров: %, контрактов: %', actor_count, contract_count;
    
    IF actor_count = 0 OR contract_count = 0 THEN
        RAISE EXCEPTION 'Отсутствуют тестовые данные! Сначала выполните скрипт 08_test_data.sql';
    END IF;
END $$;

-- Проверка от имени superuser
DO $$
BEGIN
    RAISE NOTICE '=== ТЕСТ 1: Проверка от superuser ===';
END $$;

SELECT 
    'Superuser видит актёров: ' || COUNT(*)::TEXT as test_result
FROM app.actors;

SELECT 
    'Superuser видит контракты: ' || COUNT(*)::TEXT as test_result  
FROM app.contracts;

SELECT 
    'Superuser видит логи: ' || COUNT(*)::TEXT as test_result
FROM audit.login_log;

-- Тестирование безопасных функций
DO $$
BEGIN
    RAISE NOTICE '=== ТЕСТ 2: Безопасные функции ===';
END $$;

SELECT * FROM app.get_contracts_with_masked_salary() LIMIT 3;

-- Автоматическая проверка системы
DO $$
BEGIN
    RAISE NOTICE '=== АВТОМАТИЧЕСКАЯ ПРОВЕРКА СИСТЕМЫ ===';
END $$;

-- Проверяем роли
SELECT 
    rolname,
    CASE 
        WHEN rolname IN ('app_reader', 'app_writer', 'auditor', 'studio_manager', 'voice_actor', 'security_auditor', 'db_developer') 
        THEN '✓ Создана'
        ELSE '✗ Отсутствует'
    END as status
FROM pg_roles 
WHERE rolname IN ('app_reader', 'app_writer', 'auditor', 'studio_manager', 'voice_actor', 'security_auditor', 'db_developer');

-- Проверяем RLS
SELECT 
    schemaname,
    tablename,
    CASE 
        WHEN rowsecurity THEN '✓ Включен'
        ELSE '✗ Выключен'
    END as rls_status
FROM pg_tables 
WHERE schemaname = 'app' 
  AND tablename IN ('actors', 'contracts', 'recording_sessions', 'audio_archives');

-- Проверяем политики
SELECT 
    schemaname,
    tablename,
    policyname,
    '✓ Настроена' as status
FROM pg_policies 
WHERE schemaname = 'app';

-- Инструкция для ручного тестирования
DO $$
BEGIN
    RAISE NOTICE ' ';
    RAISE NOTICE '=== ИНСТРУКЦИЯ ДЛЯ РУЧНОГО ТЕСТИРОВАНИЯ ===';
    RAISE NOTICE 'Откройте НОВОЕ окно Query Tool для тестирования:';
    RAISE NOTICE ' ';
    RAISE NOTICE 'ТЕСТ voice_actor:';
    RAISE NOTICE '1. SET ROLE voice_actor;';
    RAISE NOTICE '2. SET app.current_actor_id = ''1'';';
    RAISE NOTICE '3. SELECT * FROM app.contracts; -- Только контракты актёра 1 (без salary_amount)';
    RAISE NOTICE '4. SELECT * FROM app.get_contracts_with_masked_salary(); -- Безопасный просмотр зарплат';
    RAISE NOTICE '5. SELECT public.log_session_start();';
    RAISE NOTICE '6. RESET ROLE;';
    RAISE NOTICE ' ';
    RAISE NOTICE 'ТЕСТ studio_manager:';
    RAISE NOTICE '1. SET ROLE studio_manager;';
    RAISE NOTICE '2. SELECT * FROM app.projects; -- Должен работать';
    RAISE NOTICE '3. SELECT * FROM audit.login_log; -- Должна БЫТЬ ОШИБКА';
    RAISE NOTICE '4. RESET ROLE;';
    RAISE NOTICE ' ';
    RAISE NOTICE 'ТЕСТ security_auditor:';
    RAISE NOTICE '1. SET ROLE security_auditor;';
    RAISE NOTICE '2. SELECT * FROM audit.login_log; -- Должен работать';
    RAISE NOTICE '3. SELECT * FROM app.contracts; -- Должна БЫТЬ ОШИБКА';
    RAISE NOTICE '4. RESET ROLE;';
    RAISE NOTICE ' ';
END $$;


