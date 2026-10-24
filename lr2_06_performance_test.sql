-- =====================================================
-- Тест производительности CHECK vs триггер
-- =====================================================

\echo '====================================================='
\echo 'ТЕСТ ПРОИЗВОДИТЕЛЬНОСТИ: CHECK vs TRIGGER'
\echo '====================================================='

-- Запускаем тест на 10,000 строк
\echo ''
\echo 'Запуск теста на 10,000 строк...'
\echo 'Это может занять некоторое время...'

SELECT * FROM app.test_performance_check_vs_trigger(10000);

\echo ''
\echo '====================================================='
\echo 'СТАТИСТИКА'
\echo '====================================================='

-- Показываем количество записей в каждой таблице
SELECT 
    'CHECK метод' as method,
    COUNT(*) as total_records
FROM app.contracts_check_test
UNION ALL
SELECT 
    'TRIGGER метод' as method,
    COUNT(*) as total_records
FROM app.contracts_trigger_test;

-- Показываем примеры записей
\echo ''
\echo 'Примеры записей из CHECK таблицы:'
SELECT * FROM app.contracts_check_test LIMIT 5;

\echo ''
\echo 'Примеры записей из TRIGGER таблицы:'
SELECT * FROM app.contracts_trigger_test LIMIT 5;

\echo ''
\echo '====================================================='
\echo 'ПРОВЕРКА ВАЛИДАЦИИ'
\echo '====================================================='

-- Проверяем, что все записи валидны
SELECT 
    'CHECK: Валидных записей' as check_type,
    COUNT(*) as valid_count
FROM app.contracts_check_test
WHERE (end_date IS NULL OR end_date >= signed_date)
  AND (status != 'completed' OR (end_date IS NOT NULL AND end_date <= CURRENT_DATE))
UNION ALL
SELECT 
    'CHECK: Всего записей' as check_type,
    COUNT(*) as total_count
FROM app.contracts_check_test;

SELECT 
    'TRIGGER: Всего записей' as check_type,
    COUNT(*) as total_count
FROM app.contracts_trigger_test;

\echo ''
\echo '====================================================='
\echo 'Сравнение CHECK и TRIGGER'
\echo '====================================================='

-- Сохраняем результаты один раз для использования
WITH performance_results AS (
    SELECT * FROM app.test_performance_check_vs_trigger(10000)
),
check_data AS (
    SELECT * FROM performance_results WHERE method = 'CHECK'
),
trigger_data AS (
    SELECT * FROM performance_results WHERE method = 'TRIGGER'
),
comparison_table AS (
    SELECT 
        1 as sort_order,
        'Успешно вставлено' as "Параметр",
        c.inserted_count::TEXT as "CHECK",
        t.inserted_count::TEXT as "TRIGGER",
        CASE 
            WHEN c.inserted_count > t.inserted_count THEN
                '+' || (c.inserted_count - t.inserted_count)::TEXT
            ELSE
                (c.inserted_count - t.inserted_count)::TEXT
        END as "Разница"
    FROM check_data c, trigger_data t
    UNION ALL
    SELECT 
        2,
        'Неудачных вставок',
        c.failed_count::TEXT,
        t.failed_count::TEXT,
        CASE 
            WHEN c.failed_count > t.failed_count THEN
                '+' || (c.failed_count - t.failed_count)::TEXT
            ELSE
                (c.failed_count - t.failed_count)::TEXT
        END
    FROM check_data c, trigger_data t
    UNION ALL
    SELECT 
        3,
        'Общее время (мс)',
        ROUND(c.total_time_ms, 2)::TEXT,
        ROUND(t.total_time_ms, 2)::TEXT,
        CASE 
            WHEN c.total_time_ms > t.total_time_ms THEN
                '+' || ROUND(c.total_time_ms - t.total_time_ms, 2)::TEXT || ' мс (' ||
                ROUND((c.total_time_ms - t.total_time_ms) / c.total_time_ms * 100, 1)::TEXT || '%)'
            ELSE
                ROUND(c.total_time_ms - t.total_time_ms, 2)::TEXT || ' мс (' ||
                ROUND(ABS(c.total_time_ms - t.total_time_ms) / t.total_time_ms * 100, 1)::TEXT || '%)'
        END
    FROM check_data c, trigger_data t
    UNION ALL
    SELECT 
        4,
        'Среднее время на вставку (мс)',
        ROUND(c.avg_time_per_insert_ms, 5)::TEXT,
        ROUND(t.avg_time_per_insert_ms, 5)::TEXT,
        CASE 
            WHEN c.avg_time_per_insert_ms > t.avg_time_per_insert_ms THEN
                '+' || ROUND(c.avg_time_per_insert_ms - t.avg_time_per_insert_ms, 5)::TEXT || ' мс'
            ELSE
                ROUND(c.avg_time_per_insert_ms - t.avg_time_per_insert_ms, 5)::TEXT || ' мс'
        END
    FROM check_data c, trigger_data t
)
SELECT "Параметр", "CHECK", "TRIGGER", "Разница"
FROM comparison_table
ORDER BY sort_order;

\echo ''
\echo '====================================================='
\echo 'ПРОВЕРКА ВАЛИДАЦИИ'
\echo '====================================================='
\echo ''
\echo 'Попытка вставить невалидные данные для проверки...'

-- Тест CHECK: попытка вставить невалидные данные
DO $$
BEGIN
    BEGIN
        INSERT INTO app.contracts_check_test (
            contract_number,
            signed_date,
            end_date,
            status
        ) VALUES (
            'TEST-INVALID-001',
            CURRENT_DATE,
            CURRENT_DATE - INTERVAL '1 day', -- Невалидно: end_date < signed_date
            'active'
        );
        
        RAISE NOTICE '❌ ОШИБКА: CHECK не сработал!';
    EXCEPTION
        WHEN check_violation THEN
            RAISE NOTICE '✅ CHECK сработал корректно: %', SQLERRM;
        WHEN OTHERS THEN
            RAISE NOTICE '⚠️  Неожиданная ошибка: %', SQLERRM;
    END;
END $$;

-- Тест TRIGGER: попытка вставить невалидные данные
DO $$
BEGIN
    BEGIN
        INSERT INTO app.contracts_trigger_test (
            contract_number,
            signed_date,
            end_date,
            status
        ) VALUES (
            'TEST-INVALID-002',
            CURRENT_DATE,
            CURRENT_DATE - INTERVAL '1 day', -- Невалидно: end_date < signed_date
            'active'
        );
        
        RAISE NOTICE '❌ ОШИБКА: TRIGGER не сработал!';
    EXCEPTION
        WHEN OTHERS THEN
            RAISE NOTICE '✅ TRIGGER сработал корректно: %', SQLERRM;
    END;
END $$;

\echo ''
\echo '====================================================='
