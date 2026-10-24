-- =====================================================
-- ТЕСТЫ ДЛЯ ПРОВЕРКИ БД СТУДИИ ДУБЛЯЖА
-- Соответствие ТЗ: Лабораторная работа №1
-- =====================================================

\echo '====================================================='
\echo 'ТЕСТИРОВАНИЕ БД СТУДИИ ДУБЛЯЖА'
\echo '====================================================='

-- =====================================================
-- ТЕСТ 1: ПРОВЕРКА СХЕМ
-- =====================================================
\echo ''
\echo '=== ТЕСТ 1: ПРОВЕРКА СХЕМ ==='

SELECT 'Схемы созданы:' as test_name, COUNT(*) as result
FROM information_schema.schemata 
WHERE schema_name IN ('app', 'ref', 'audit', 'stg');

-- Должно быть: 4

-- =====================================================
-- ТЕСТ 2: ПРОВЕРКА ТАБЛИЦ
-- =====================================================
\echo ''
\echo '=== ТЕСТ 2: ПРОВЕРКА ТАБЛИЦ ==='

SELECT 'Таблицы в app:' as test_name, COUNT(*) as result
FROM information_schema.tables 
WHERE table_schema = 'app';

SELECT 'Таблицы в ref:' as test_name, COUNT(*) as result
FROM information_schema.tables 
WHERE table_schema = 'ref';

SELECT 'Таблицы в audit:' as test_name, COUNT(*) as result
FROM information_schema.tables 
WHERE table_schema = 'audit';

-- Должно быть: app=6, ref=2, audit=2

-- =====================================================
-- ТЕСТ 3: ПРОВЕРКА РОЛЕЙ
-- =====================================================
\echo ''
\echo '=== ТЕСТ 3: ПРОВЕРКА РОЛЕЙ ==='

SELECT 'Системные роли:' as test_name, COUNT(*) as result
FROM pg_roles 
WHERE rolname IN ('app_owner', 'app_reader', 'app_writer', 'auditor', 'ddl_admin', 'dml_admin', 'security_admin');

SELECT 'Пользователи:' as test_name, COUNT(*) as result
FROM pg_roles 
WHERE rolname IN ('studio_manager', 'voice_actor', 'security_auditor', 'db_developer');

-- Должно быть: 7 системных + 4 пользователя

-- =====================================================
-- ТЕСТ 4: ПРОВЕРКА RLS
-- =====================================================
\echo ''
\echo '=== ТЕСТ 4: ПРОВЕРКА RLS ==='

SELECT 'RLS включен:' as test_name, COUNT(*) as result
FROM pg_tables 
WHERE schemaname = 'app' 
  AND rowsecurity = true;

SELECT 'Политики RLS:' as test_name, COUNT(*) as result
FROM pg_policies 
WHERE schemaname = 'app';

-- Должно быть: RLS на всех таблицах, политики настроены

-- =====================================================
-- ТЕСТ 5: ПРОВЕРКА ВНЕШНИХ КЛЮЧЕЙ
-- =====================================================
\echo ''
\echo '=== ТЕСТ 5: ПРОВЕРКА ВНЕШНИХ КЛЮЧЕЙ ==='

SELECT 'Внешние ключи:' as test_name, COUNT(*) as result
FROM information_schema.table_constraints 
WHERE constraint_type = 'FOREIGN KEY' 
  AND table_schema = 'app';

-- Должно быть: минимум 3 FK

-- =====================================================
-- ТЕСТ 6: ПРОВЕРКА M:N СВЯЗИ
-- =====================================================
\echo ''
\echo '=== ТЕСТ 6: ПРОВЕРКА M:N СВЯЗИ ==='

SELECT 'M:N связь voice_roles:' as test_name, COUNT(*) as result
FROM app.voice_roles;

-- Должно быть: записи в таблице voice_roles

-- =====================================================
-- ТЕСТ 7: ПРОВЕРКА ЧУВСТВИТЕЛЬНЫХ ДАННЫХ
-- =====================================================
\echo ''
\echo '=== ТЕСТ 7: ПРОВЕРКА ЧУВСТВИТЕЛЬНЫХ ДАННЫХ ==='

SELECT 'Чувствительные поля:' as test_name, COUNT(*) as result
FROM information_schema.columns 
WHERE (column_name LIKE '%passport%' OR 
       column_name LIKE '%salary%' OR 
       column_name LIKE '%bank%' OR
       column_name LIKE '%encrypted%')
  AND table_schema = 'app';

-- Должно быть: минимум 1 поле с чувствительными данными

-- =====================================================
-- ТЕСТ 8: ПРОВЕРКА АУДИТА
-- =====================================================
\echo ''
\echo '=== ТЕСТ 8: ПРОВЕРКА АУДИТА ==='

SELECT 'Триггеры аудита:' as test_name, COUNT(*) as result
FROM information_schema.triggers 
WHERE trigger_schema = 'app' 
  AND trigger_name LIKE 'audit_%';

SELECT 'Логи подключений:' as test_name, COUNT(*) as result
FROM audit.login_log;

-- Должно быть: триггеры созданы, логи есть

-- =====================================================
-- ТЕСТ 9: ПРОВЕРКА ТЕСТОВЫХ ДАННЫХ
-- =====================================================
\echo ''
\echo '=== ТЕСТ 9: ПРОВЕРКА ТЕСТОВЫХ ДАННЫХ ==='

SELECT 'Актёры:' as test_name, COUNT(*) as result FROM app.actors;
SELECT 'Проекты:' as test_name, COUNT(*) as result FROM app.projects;
SELECT 'Контракты:' as test_name, COUNT(*) as result FROM app.contracts;
SELECT 'Сессии:' as test_name, COUNT(*) as result FROM app.recording_sessions;

-- Должно быть: минимум 10 записей в ключевых таблицах

-- =====================================================
-- ТЕСТ 10: ТЕСТ БЕЗОПАСНОСТИ РОЛЕЙ
-- =====================================================
\echo ''
\echo '=== ТЕСТ 10: ТЕСТ БЕЗОПАСНОСТИ РОЛЕЙ ==='

-- Тест voice_actor
\echo '--- Тест voice_actor ---'
SET ROLE voice_actor;
SET app.current_actor_id = '1';

SELECT 'Контракты актёра 1:' as test_name, 
       contract_id, contract_number, role_description, currency, signed_date
FROM app.contracts;

-- Проверяем, что не видит salary_amount
SELECT 'salary_amount скрыт:' as test_name, 
       CASE WHEN COUNT(*) = 0 THEN 'ДА' ELSE 'НЕТ' END as result
FROM information_schema.column_privileges 
WHERE grantee = 'app_reader' 
  AND table_name = 'contracts' 
  AND column_name = 'salary_amount';

RESET ROLE;

-- Тест studio_manager
\echo '--- Тест studio_manager ---'
SET ROLE studio_manager;

SELECT 'Проекты менеджера:' as test_name, 
       project_id, title, studio_id, status, created_at
FROM app.projects;

-- Проверяем, что не может удалять
SELECT 'DELETE запрещён:' as test_name,
       CASE WHEN has_table_privilege('studio_manager', 'app.contracts', 'DELETE') 
            THEN 'НЕТ' ELSE 'ДА' END as result;

RESET ROLE;

-- Тест security_auditor
\echo '--- Тест security_auditor ---'
SET ROLE security_auditor;

SELECT 'Логи аудита:' as test_name, 
       username, client_ip, connection_method, is_successful, login_time
FROM audit.login_log;

-- Проверяем, что не может читать бизнес-данные
SELECT 'Контракты недоступны:' as test_name,
       CASE WHEN has_table_privilege('security_auditor', 'app.contracts', 'SELECT') 
            THEN 'НЕТ' ELSE 'ДА' END as result;

RESET ROLE;

-- =====================================================
-- ТЕСТ 11: ПРОВЕРКА РАСШИРЕНИЙ
-- =====================================================
\echo ''
\echo '=== ТЕСТ 11: ПРОВЕРКА РАСШИРЕНИЙ ==='

SELECT 'Расширения:' as test_name, COUNT(*) as result
FROM pg_extension 
WHERE extname IN ('pgcrypto', 'pgaudit');

-- Должно быть: минимум pgcrypto

-- =====================================================
-- ТЕСТ 12: ПРОВЕРКА ИНДЕКСОВ
-- =====================================================
\echo ''
\echo '=== ТЕСТ 12: ПРОВЕРКА ИНДЕКСОВ ==='

SELECT 'Индексы:' as test_name, COUNT(*) as result
FROM pg_indexes 
WHERE schemaname = 'app';

-- Должно быть: несколько индексов для производительности

-- =====================================================
-- ТЕСТ 13: ПРОВЕРКА SECURITY DEFINER ФУНКЦИЙ
-- =====================================================
\echo ''
\echo '=== ТЕСТ 13: ПРОВЕРКА SECURITY DEFINER ФУНКЦИЙ ==='

SELECT 'SECURITY DEFINER функции:' as test_name, COUNT(*) as result
FROM pg_proc 
WHERE prosecdef = true 
  AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'app');

-- Должно быть: минимум 1 функция

-- =====================================================
-- ТЕСТ 14: ПРОВЕРКА ЗАПРЕТА PUBLIC ДОСТУПА
-- =====================================================
\echo ''
\echo '=== ТЕСТ 14: ПРОВЕРКА ЗАПРЕТА PUBLIC ДОСТУПА ==='

SELECT 'PUBLIC доступ запрещён:' as test_name,
       CASE WHEN has_schema_privilege('public', 'app', 'USAGE') 
            THEN 'НЕТ' ELSE 'ДА' END as result;

-- Должно быть: ДА

-- =====================================================
-- ИТОГОВЫЙ ОТЧЁТ
-- =====================================================
\echo ''
\echo '====================================================='
\echo 'ИТОГОВЫЙ ОТЧЁТ'
\echo '====================================================='

SELECT 'Всего тестов выполнено: 14' as summary;

\echo ''
\echo 'ПРОВЕРЬТЕ РЕЗУЛЬТАТЫ ВЫШЕ!'
\echo 'Все тесты должны показать корректные значения'
\echo '====================================================='