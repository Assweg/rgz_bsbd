-- 05_privileges.sql
-- Настройка привилегий для ролей

-- Привилегии на уровне схем для ролей
GRANT USAGE ON SCHEMA app, ref, stg TO app_owner;
GRANT ALL ON SCHEMA app, ref, stg TO app_owner;

GRANT USAGE ON SCHEMA app, ref TO app_reader;
GRANT USAGE ON SCHEMA app, ref TO app_writer;
GRANT USAGE ON SCHEMA app, audit TO auditor;

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
GRANT SELECT ON ALL TABLES IN SCHEMA app TO auditor;

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