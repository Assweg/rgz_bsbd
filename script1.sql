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