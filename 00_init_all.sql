-- 00_init_all.sql
-- Главный скрипт инициализации всей системы
-- В Docker контейнере скрипты выполняются автоматически по алфавитному порядку

DO $$
BEGIN
    RAISE NOTICE '=== НАЧАЛО ИНИЦИАЛИЗАЦИИ СИСТЕМЫ БЕЗОПАСНОСТИ БД СТУДИИ ДУБЛЯЖА ===';
    RAISE NOTICE 'Время начала: %', NOW();
    RAISE NOTICE 'Этот скрипт выполняется после всех остальных скриптов';
END $$;

-- Проверяем, что все компоненты системы созданы
DO $$
DECLARE
    schema_count INTEGER;
    table_count INTEGER;
    role_count INTEGER;
    extension_count INTEGER;
BEGIN
    -- Проверяем схемы
    SELECT COUNT(*) INTO schema_count 
    FROM information_schema.schemata 
    WHERE schema_name IN ('app', 'ref', 'audit', 'stg');
    
    -- Проверяем таблицы
    SELECT COUNT(*) INTO table_count 
    FROM information_schema.tables 
    WHERE table_schema IN ('app', 'ref', 'audit', 'stg');
    
    -- Проверяем роли
    SELECT COUNT(*) INTO role_count 
    FROM pg_roles 
    WHERE rolname IN ('app_owner', 'app_reader', 'app_writer', 'auditor', 'ddl_admin', 'dml_admin', 'security_admin');
    
    -- Проверяем расширения
    SELECT COUNT(*) INTO extension_count 
    FROM pg_extension 
    WHERE extname IN ('pgcrypto', 'pgaudit');
    
    RAISE NOTICE 'Проверка системы:';
    RAISE NOTICE '- Схемы: %/4', schema_count;
    RAISE NOTICE '- Таблицы: %', table_count;
    RAISE NOTICE '- Роли: %/7', role_count;
    RAISE NOTICE '- Расширения: %/2', extension_count;
    
    IF schema_count = 4 AND table_count > 0 AND role_count = 7 AND extension_count = 2 THEN
        RAISE NOTICE '✅ Все компоненты системы успешно инициализированы!';
    ELSE
        RAISE WARNING '⚠️  Некоторые компоненты системы не инициализированы полностью';
    END IF;
END $$;

DO $$
BEGIN
    RAISE NOTICE '=== ИНИЦИАЛИЗАЦИЯ ЗАВЕРШЕНА ===';
    RAISE NOTICE 'Время завершения: %', NOW();
    RAISE NOTICE 'Система готова к работе!';
    RAISE NOTICE 'Подключитесь к БД: psql -h localhost -U postgres -d dubbing_studio';
    RAISE NOTICE 'Пароль: secure_password_123';
END $$;
