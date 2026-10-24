-- =====================================================
-- Комплексные тесты для всех ролей системы дубляжа
-- =====================================================

-- Тестирование роли app_reader (чтение бизнес-данных)
\echo '=== ТЕСТИРОВАНИЕ РОЛИ app_reader ==='

SET ROLE app_reader;

-- Должны работать: чтение основных таблиц
\echo '1. Чтение actors:'
SELECT COUNT(*) as actors_count FROM app.actors;

\echo '2. Чтение projects:'
SELECT COUNT(*) as projects_count FROM app.projects;

\echo '3. Чтение contracts (без зарплат):'
SELECT contract_id, contract_number, role_description, currency, signed_date 
FROM app.contracts LIMIT 3;

\echo '4. Чтение справочников:'
SELECT COUNT(*) as studios_count FROM ref.studios;
SELECT COUNT(*) as languages_count FROM ref.languages;

-- Должна быть ОШИБКА: чтение аудита
\echo '5. Попытка чтения audit.login_log (должна быть ошибка):'
SELECT * FROM audit.login_log LIMIT 1;

-- Должна быть ОШИБКА: запись данных
\echo '6. Попытка вставки в actors (должна быть ошибка):'
INSERT INTO app.actors (full_name) VALUES ('Test Actor');

RESET ROLE;

-- Тестирование роли app_writer (запись бизнес-данных)
\echo ''
\echo '=== ТЕСТИРОВАНИЕ РОЛИ app_writer ==='

SET ROLE app_writer;

-- Должны работать: чтение и запись
\echo '1. Чтение actors:'
SELECT COUNT(*) as actors_count FROM app.actors;

\echo '2. Вставка тестового актера:'
INSERT INTO app.actors (full_name, phone, email) 
VALUES ('Test Writer Actor', '+7-999-999-9999', 'test@example.com')
RETURNING actor_id, full_name;

\echo '3. Обновление актера:'
UPDATE app.actors SET phone = '+7-888-888-8888' 
WHERE full_name = 'Test Writer Actor'
RETURNING actor_id, full_name, phone;

-- Должна быть ОШИБКА: удаление данных
\echo '4. Попытка удаления (должна быть ошибка):'
DELETE FROM app.actors WHERE full_name = 'Test Writer Actor';

-- Должна быть ОШИБКА: доступ к аудиту
\echo '5. Попытка чтения аудита (должна быть ошибка):'
SELECT * FROM audit.login_log LIMIT 1;

-- Очистка тестовых данных
DELETE FROM app.actors WHERE full_name = 'Test Writer Actor';

RESET ROLE;

-- Тестирование роли studio_manager (менеджер студии)
\echo ''
\echo '=== ТЕСТИРОВАНИЕ РОЛИ studio_manager ==='

SET ROLE studio_manager;

-- Должны работать: чтение и запись бизнес-данных
\echo '1. Чтение projects:'
SELECT COUNT(*) as projects_count FROM app.projects;

\echo '2. Чтение contracts:'
SELECT COUNT(*) as contracts_count FROM app.contracts;

\echo '3. Вставка тестового проекта:'
INSERT INTO app.projects (studio_id, title, original_language, description) 
VALUES (1, 'Тестовый проект', 'ru', 'Проект для тестирования')
RETURNING project_id, title;

\echo '4. Обновление проекта:'
UPDATE app.projects SET description = 'Обновленное описание' 
WHERE title = 'Тестовый проект'
RETURNING project_id, title, description;

-- Должна быть ОШИБКА: доступ к аудиту
\echo '5. Попытка чтения аудита (должна быть ошибка):'
SELECT * FROM audit.login_log LIMIT 1;

-- Очистка тестовых данных
DELETE FROM app.projects WHERE title = 'Тестовый проект';

RESET ROLE;

-- Тестирование роли voice_actor (актер озвучивания)
\echo ''
\echo '=== ТЕСТИРОВАНИЕ РОЛИ voice_actor ==='

SET ROLE voice_actor;

-- Настройка контекста для RLS (имитация актера с ID=1)
SET app.current_actor_id = '1';

\echo '1. Просмотр своих контрактов (только актер ID=1):'
SELECT contract_id, contract_number, role_description 
FROM app.contracts LIMIT 3;

\echo '2. Просмотр своих сессий записи:'
SELECT session_id, session_date, session_time, studio_location 
FROM app.recording_sessions LIMIT 3;

\echo '3. Использование безопасной функции для зарплат:'
SELECT * FROM app.get_contracts_with_masked_salary() LIMIT 3;

-- Должна быть ОШИБКА: просмотр всех актеров
\echo '4. Попытка просмотра всех актеров (должна быть ошибка RLS):'
SELECT COUNT(*) FROM app.actors;

-- Должна быть ОШИБКА: запись данных
\echo '5. Попытка вставки (должна быть ошибка):'
INSERT INTO app.recording_sessions (contract_id, session_date, session_time, studio_location) 
VALUES (1, '2024-01-01', '10:00:00', 'Test Studio');

RESET ROLE;

-- Тестирование роли security_auditor (аудитор безопасности)
\echo ''
\echo '=== ТЕСТИРОВАНИЕ РОЛИ security_auditor ==='

SET ROLE security_auditor;

-- Должны работать: чтение аудита
\echo '1. Чтение логов подключений:'
SELECT COUNT(*) as login_logs_count FROM audit.login_log;

\echo '2. Чтение логов доступа к данным:'
SELECT COUNT(*) as access_logs_count FROM audit.data_access_log;

\echo '3. Пример логов подключений:'
SELECT username, login_time, client_ip, is_successful 
FROM audit.login_log 
ORDER BY login_time DESC 
LIMIT 3;

-- Должна быть ОШИБКА: доступ к бизнес-данным
\echo '4. Попытка чтения contracts (должна быть ошибка):'
SELECT * FROM app.contracts LIMIT 1;

-- Должна быть ОШИБКА: запись в аудит
\echo '5. Попытка вставки в аудит (должна быть ошибка):'
INSERT INTO audit.login_log (username, client_ip) VALUES ('test', '127.0.0.1');

RESET ROLE;

-- Тестирование роли db_developer (разработчик БД)
\echo ''
\echo '=== ТЕСТИРОВАНИЕ РОЛИ db_developer ==='

SET ROLE db_developer;

-- Должны работать: DDL операции
\echo '1. Создание тестовой таблицы:'
CREATE TABLE app.test_developer_table (
    id SERIAL PRIMARY KEY,
    test_data TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

\echo '2. Вставка данных в тестовую таблицу:'
INSERT INTO app.test_developer_table (test_data) VALUES ('Тестовые данные разработчика');

\echo '3. Чтение тестовой таблицы:'
SELECT * FROM app.test_developer_table;

\echo '4. Создание индекса:'
CREATE INDEX idx_test_developer_data ON app.test_developer_table(test_data);

\echo '5. Удаление тестовой таблицы:'
DROP TABLE app.test_developer_table;

\echo '6. Доступ ко всем схемам:'
SELECT COUNT(*) as app_tables FROM information_schema.tables WHERE table_schema = 'app';
SELECT COUNT(*) as ref_tables FROM information_schema.tables WHERE table_schema = 'ref';
SELECT COUNT(*) as audit_tables FROM information_schema.tables WHERE table_schema = 'audit';

RESET ROLE;

-- Тестирование функций логирования
\echo ''
\echo '=== ТЕСТИРОВАНИЕ ФУНКЦИЙ ЛОГИРОВАНИЯ ==='

\echo '1. Тестирование ручного логирования сессии:'
SET ROLE studio_manager;
SELECT public.log_session_start();
RESET ROLE;

SET ROLE voice_actor;
SELECT public.log_session_start();
RESET ROLE;

\echo '2. Проверка записей в логах:'
SET ROLE security_auditor;
SELECT username, login_time, is_successful 
FROM audit.login_log 
WHERE username IN ('studio_manager', 'voice_actor')
ORDER BY login_time DESC 
LIMIT 5;
RESET ROLE;

-- Проверка RLS политик
\echo ''
\echo '=== ПРОВЕРКА RLS ПОЛИТИК ==='

\echo '1. Статус RLS на основных таблицах:'
SELECT 
    schemaname,
    tablename,
    rowsecurity as rls_enabled
FROM pg_tables 
WHERE schemaname = 'app' 
  AND tablename IN ('actors', 'contracts', 'recording_sessions', 'projects');

\echo '2. Существующие политики:'
SELECT 
    schemaname,
    tablename,
    policyname,
    cmd,
    roles
FROM pg_policies 
WHERE schemaname = 'app';

-- Финальный отчет
\echo ''
\echo '=== ФИНАЛЬНЫЙ ОТЧЕТ ==='

\echo 'Проверьте вывод выше на наличие ошибок.'
\echo 'Успешное выполнение:'
\echo '- app_reader: чтение бизнес-данных ✓'
\echo '- app_writer: чтение/запись бизнес-данных ✓' 
\echo '- studio_manager: управление проектами ✓'
\echo '- voice_actor: доступ только к своим данным ✓'
\echo '- security_auditor: доступ только к аудиту ✓'
\echo '- db_developer: полный доступ к структуре ✓'
\echo ''
\echo 'Все ошибки доступа должны быть ожидаемыми и соответствовать политикам безопасности.'



-- Тестирование роли app_owner (владелец приложения)
\echo ''
\echo '=== ТЕСТИРОВАНИЕ РОЛИ app_owner ==='

SET ROLE app_owner;

\echo '1. Полный доступ к app схемам:'
SELECT COUNT(*) as app_tables FROM information_schema.tables WHERE table_schema = 'app';
SELECT COUNT(*) as ref_tables FROM information_schema.tables WHERE table_schema = 'ref';

\echo '2. DCL операции - выдача прав:'
GRANT SELECT ON app.actors TO app_reader;

\echo '3. Полный доступ к данным:'
INSERT INTO app.actors (full_name, phone) VALUES ('Test Owner Actor', '+7-777-777-7777') 
RETURNING actor_id, full_name;

UPDATE app.actors SET phone = '+7-888-888-8888' WHERE full_name = 'Test Owner Actor';

DELETE FROM app.actors WHERE full_name = 'Test Owner Actor';

\echo '4. Доступ к последовательностям:'
SELECT nextval('app.actors_actor_id_seq'::regclass);

RESET ROLE;

-- Тестирование роли dml_admin (администратор DML)
\echo ''
\echo '=== ТЕСТИРОВАНИЕ РОЛИ dml_admin ==='

SET ROLE dml_admin;

\echo '1. Массовые операции с данными:'
INSERT INTO app.actors (full_name, phone) VALUES 
('DML Admin Actor 1', '+7-111-111-1111'),
('DML Admin Actor 2', '+7-222-222-2222')
RETURNING actor_id, full_name;

\echo '2. Массовое обновление:'
UPDATE app.actors SET phone = '+7-999-999-9999' 
WHERE full_name LIKE 'DML Admin Actor%'
RETURNING actor_id, full_name, phone;

\echo '3. Массовое удаление:'
DELETE FROM app.actors WHERE full_name LIKE 'DML Admin Actor%'
RETURNING actor_id, full_name;

\echo '4. Доступ ко всем схемам данных:'
SELECT COUNT(*) as app_count FROM app.actors;
SELECT COUNT(*) as ref_count FROM ref.studios;
SELECT COUNT(*) as stg_count FROM stg.temp_actor_data;

RESET ROLE;

-- Тестирование роли ddl_admin (администратор DDL)
\echo ''
\echo '=== ТЕСТИРОВАНИЕ РОЛИ ddl_admin ==='

SET ROLE ddl_admin;

\echo '1. Создание таблиц в разных схемах:'
CREATE TABLE app.test_ddl_table (
    id SERIAL PRIMARY KEY,
    data TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE ref.test_ddl_ref (
    id SERIAL PRIMARY KEY,
    code VARCHAR(10)
);

\echo '2. Создание индексов:'
CREATE INDEX idx_test_ddl_data ON app.test_ddl_table(data);
CREATE INDEX idx_test_ddl_code ON ref.test_ddl_ref(code);

\echo '3. Изменение структуры:'
ALTER TABLE app.test_ddl_table ADD COLUMN new_column VARCHAR(100);
ALTER TABLE ref.test_ddl_ref ALTER COLUMN code TYPE VARCHAR(20);

\echo '4. Удаление объектов:'
DROP INDEX idx_test_ddl_data;
DROP TABLE app.test_ddl_table, ref.test_ddl_ref;

\echo '5. Создание объектов в stg:'
CREATE TABLE stg.test_ddl_stg (
    batch_id SERIAL PRIMARY KEY,
    import_data JSONB
);
DROP TABLE stg.test_ddl_stg;

RESET ROLE;

-- Тестирование роли security_admin (администратор безопасности)
\echo ''
\echo '=== ТЕСТИРОВАНИЕ РОЛИ security_admin ==='

SET ROLE security_admin;

\echo '1. Наследование прав ddl_admin:'
CREATE TABLE app.test_security_table (id SERIAL PRIMARY KEY, data TEXT);

\echo '2. Наследование прав dml_admin:'
INSERT INTO app.test_security_table (data) VALUES ('Security Test Data');
SELECT * FROM app.test_security_table;

\echo '3. Управление привилегиями:'
GRANT SELECT ON app.test_security_table TO app_reader;
REVOKE SELECT ON app.test_security_table FROM app_reader;

\echo '4. Доступ ко всем схемам:'
SELECT COUNT(*) as audit_tables FROM information_schema.tables WHERE table_schema = 'audit';

\echo '5. Очистка:'
DROP TABLE app.test_security_table;

RESET ROLE;