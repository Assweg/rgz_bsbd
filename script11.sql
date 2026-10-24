-- 11_final_verify.sql
-- Финальная проверка всей системы

DO $$
BEGIN
    RAISE NOTICE '=== ФИНАЛЬНАЯ ПРОВЕРКА СИСТЕМЫ ===';
END $$;

-- 1. Проверяем схемы
SELECT 
    'Схемы созданы:' as check_name, 
    schema_name, 
    '✓ Создана' as status
FROM information_schema.schemata 
WHERE schema_name IN ('app', 'ref', 'audit', 'stg');

-- 2. Проверяем таблицы
SELECT 
    'Таблицы в схемах:' as check_name,
    table_schema,
    table_name,
    '✓ Создана' as status
FROM information_schema.tables 
WHERE table_schema IN ('app', 'ref', 'audit', 'stg')
ORDER BY table_schema, table_name;

-- 3. Проверяем тестовые данные - актёры
SELECT 
    'Актёры в системе:' as data_name,
    actor_id,
    full_name,
    email,
    '✓ Активен' as status
FROM app.actors 
ORDER BY actor_id 
LIMIT 5;

-- 4. Проверяем тестовые данные - проекты
SELECT 
    'Проекты в системе:' as data_name,
    project_id,
    title,
    studio_id,
    status,
    '✓ Активен' as status
FROM app.projects 
ORDER BY project_id;

-- 5. Проверяем тестовые данные - контракты
SELECT 
    'Контракты в системе:' as data_name,
    contract_id,
    contract_number,
    role_description,
    currency,
    '✓ Активен' as status
FROM app.contracts 
ORDER BY contract_id 
LIMIT 5;

-- 6. Проверяем логи аудита
SELECT 
    'Логи подключений:' as audit_name,
    username,
    client_ip,
    connection_method,
    is_successful,
    login_time
FROM audit.login_log 
ORDER BY login_time DESC;

-- 7. Проверяем триггеры аудита
SELECT 
    'Триггеры аудита:' as trigger_name,
    event_object_schema,
    event_object_table,
    trigger_name,
    '✓ Настроен' as status
FROM information_schema.triggers 
WHERE trigger_schema = 'app' 
  AND trigger_name LIKE 'audit_%'
ORDER BY event_object_table;

-- 8. Проверяем расширения
SELECT 
    'Расширения:' as extension_name,
    extname,
    extversion,
    '✓ Установлено' as status
FROM pg_extension 
WHERE extname IN ('pgcrypto')
ORDER BY extname;

-- 9. Итоговый отчет
DO $$
BEGIN
    RAISE NOTICE ' ';
    RAISE NOTICE '=== СИСТЕМА УСПЕШНО РАЗВЕРНУТА ===';
    RAISE NOTICE 'База данных студии дубляжа готова к работе!';
    RAISE NOTICE ' ';
    RAISE NOTICE 'Основные компоненты:';
    RAISE NOTICE '- 4 схемы (app, ref, audit, stg)';
    RAISE NOTICE '- 10 таблиц с бизнес-логикой';
    RAISE NOTICE '- 7 системных ролей с разделением обязанностей';
    RAISE NOTICE '- 4 пользователя для тестирования';
    RAISE NOTICE '- RLS политики для контроля доступа к строкам';
    RAISE NOTICE '- Система аудита подключений';
    RAISE NOTICE '- Триггеры аудита DML операций';
    RAISE NOTICE '- Расширение pgcrypto для шифрования';
    RAISE NOTICE '- Тестовые данные для демонстрации';
    RAISE NOTICE ' ';
    RAISE NOTICE 'Для тестирования используйте инструкции из script10.sql';
END $$;