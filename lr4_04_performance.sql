
SET search_path TO app, ref, audit, stg, public;
SET ROLE app_owner;

-- =====================================================
-- Создание таблицы для хранения результатов анализа
-- =====================================================

GRANT USAGE ON SCHEMA audit TO app_writer, app_reader;

-- Удаляем старую таблицу, если она существует, чтобы пересоздать с правильной структурой
DROP TABLE IF EXISTS audit.performance_analysis CASCADE;

CREATE TABLE audit.performance_analysis (
    analysis_id SERIAL PRIMARY KEY,
    analysis_time TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    query_name VARCHAR(200) NOT NULL,
    rls_enabled BOOLEAN NOT NULL,
    execution_time_ms NUMERIC(10, 3),
    planning_time_ms NUMERIC(10, 3),
    buffers_shared_hit BIGINT DEFAULT 0,
    buffers_shared_read BIGINT DEFAULT 0,
    buffers_local_hit BIGINT DEFAULT 0,
    buffers_local_read BIGINT DEFAULT 0,
    buffers_temp_read BIGINT DEFAULT 0,
    buffers_temp_written BIGINT DEFAULT 0,
    rows_examined BIGINT,
    rows_returned BIGINT,
    explain_plan TEXT,
    indexes_used TEXT[]
);

COMMENT ON TABLE audit.performance_analysis IS 
'Результаты анализа производительности запросов до/после RLS';

GRANT SELECT, INSERT ON audit.performance_analysis TO app_writer, app_reader, auditor, security_admin;
GRANT USAGE, SELECT ON SEQUENCE audit.performance_analysis_analysis_id_seq TO app_writer, app_reader;
GRANT USAGE ON SCHEMA audit TO app_writer, app_reader;

-- =====================================================
-- Функция для парсинга EXPLAIN (ANALYZE, BUFFERS) и сохранения результатов
-- =====================================================

CREATE OR REPLACE FUNCTION audit.save_explain_result(
    p_query_name TEXT,
    p_rls_enabled BOOLEAN,
    p_explain_text TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = audit, public
AS $$
DECLARE
    v_execution_time NUMERIC := NULL;
    v_planning_time NUMERIC := NULL;
    v_buffers_shared_hit BIGINT := 0;
    v_buffers_shared_read BIGINT := 0;
    v_buffers_local_hit BIGINT := 0;
    v_buffers_local_read BIGINT := 0;
    v_buffers_temp_read BIGINT := 0;
    v_buffers_temp_written BIGINT := 0;
    v_rows_examined BIGINT := NULL;
    v_rows_returned BIGINT := NULL;
    v_indexes_used TEXT[] := ARRAY[]::TEXT[];
    v_lines TEXT[];
    v_line TEXT;
    v_match TEXT;
BEGIN
    -- Парсим результаты из EXPLAIN (ANALYZE, BUFFERS)
    -- Ищем строки вида: "Planning Time: 0.123 ms"
    -- "Execution Time: 1.456 ms"
    -- "Buffers: shared hit=10 read=5"
    
    v_lines := string_to_array(p_explain_text, E'\n');
    
    FOREACH v_line IN ARRAY v_lines
    LOOP
        -- Парсим Planning Time (формат: "Planning Time: 0.319 ms")
        IF v_line ~* 'Planning Time:' THEN
            v_match := substring(v_line from 'Planning Time:\s*([0-9]+\.[0-9]+|[0-9]+)\s*ms');
            IF v_match IS NOT NULL THEN
                v_planning_time := v_match::NUMERIC;
            END IF;
        END IF;
        
        -- Парсим Execution Time (формат: "Execution Time: 0.033 ms")
        IF v_line ~* 'Execution Time:' THEN
            v_match := substring(v_line from 'Execution Time:\s*([0-9]+\.[0-9]+|[0-9]+)\s*ms');
            IF v_match IS NOT NULL THEN
                v_execution_time := v_match::NUMERIC;
            END IF;
        END IF;
        
        -- Парсим Buffers (может быть несколько строк)
        IF v_line ~* 'Buffers:' THEN
            -- shared hit
            v_match := substring(v_line from 'shared hit=(\d+)');
            IF v_match IS NOT NULL THEN
                v_buffers_shared_hit := v_buffers_shared_hit + v_match::BIGINT;
            END IF;
            -- shared read
            v_match := substring(v_line from 'shared read=(\d+)');
            IF v_match IS NOT NULL THEN
                v_buffers_shared_read := v_buffers_shared_read + v_match::BIGINT;
            END IF;
            -- local hit
            v_match := substring(v_line from 'local hit=(\d+)');
            IF v_match IS NOT NULL THEN
                v_buffers_local_hit := v_buffers_local_hit + v_match::BIGINT;
            END IF;
            -- local read
            v_match := substring(v_line from 'local read=(\d+)');
            IF v_match IS NOT NULL THEN
                v_buffers_local_read := v_buffers_local_read + v_match::BIGINT;
            END IF;
            -- temp read
            v_match := substring(v_line from 'temp read=(\d+)');
            IF v_match IS NOT NULL THEN
                v_buffers_temp_read := v_buffers_temp_read + v_match::BIGINT;
            END IF;
            -- temp written
            v_match := substring(v_line from 'temp written=(\d+)');
            IF v_match IS NOT NULL THEN
                v_buffers_temp_written := v_buffers_temp_written + v_match::BIGINT;
            END IF;
        END IF;
        
        -- Парсим индексы (ищем строки с Index Scan, Index Only Scan)
        IF v_line ~* 'Index (Only )?Scan' THEN
            v_match := substring(v_line from 'Index (Only )?Scan (?:using )?(\w+)');
            IF v_match IS NOT NULL THEN
                v_indexes_used := array_append(v_indexes_used, v_match);
            END IF;
        END IF;
    END LOOP;
    
    -- Пытаемся найти rows examined/returned из плана
    -- Это упрощённая версия, в реальности нужно парсить весь план
    v_rows_examined := NULL;
    v_rows_returned := NULL;
    
    INSERT INTO audit.performance_analysis (
        query_name,
        rls_enabled,
        execution_time_ms,
        planning_time_ms,
        buffers_shared_hit,
        buffers_shared_read,
        buffers_local_hit,
        buffers_local_read,
        buffers_temp_read,
        buffers_temp_written,
        rows_examined,
        rows_returned,
        explain_plan,
        indexes_used
    ) VALUES (
        p_query_name,
        p_rls_enabled,
        v_execution_time,
        v_planning_time,
        v_buffers_shared_hit,
        v_buffers_shared_read,
        v_buffers_local_hit,
        v_buffers_local_read,
        v_buffers_temp_read,
        v_buffers_temp_written,
        v_rows_examined,
        v_rows_returned,
        p_explain_text,
        v_indexes_used
    );
END;
$$;

-- =====================================================
-- Вспомогательная функция для выполнения EXPLAIN и сохранения результатов
-- =====================================================

CREATE OR REPLACE FUNCTION audit.run_explain_test(
    p_query_name TEXT,
    p_query_sql TEXT,
    p_rls_enabled BOOLEAN
)
RETURNS TABLE (
    execution_time_ms NUMERIC,
    planning_time_ms NUMERIC,
    total_buffers_read BIGINT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = audit, public
AS $$
DECLARE
    v_explain_text TEXT := '';
    v_line TEXT;
    v_result RECORD;
    v_rec RECORD;
BEGIN
    -- Выполняем EXPLAIN (ANALYZE, BUFFERS) и собираем все строки
    FOR v_rec IN 
        EXECUTE format('EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT) %s', p_query_sql)
    LOOP
        v_explain_text := v_explain_text || v_rec."QUERY PLAN" || E'\n';
    END LOOP;
    
    -- Сохраняем результат
    PERFORM audit.save_explain_result(p_query_name, p_rls_enabled, v_explain_text);
    
    -- Возвращаем метрики
    SELECT 
        pa.execution_time_ms,
        pa.planning_time_ms,
        (pa.buffers_shared_read + pa.buffers_local_read)::BIGINT as total_buffers_read
    INTO v_result
    FROM audit.performance_analysis pa
    WHERE pa.query_name = p_query_name 
      AND pa.rls_enabled = p_rls_enabled
    ORDER BY pa.analysis_time DESC
    LIMIT 1;
    
    RETURN QUERY SELECT 
        v_result.execution_time_ms,
        v_result.planning_time_ms,
        v_result.total_buffers_read;
END;
$$;

-- =====================================================
-- Создание индексов для оптимизации RLS политик
-- =====================================================

DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
    RAISE NOTICE 'СОЗДАНИЕ ИНДЕКСОВ ДЛЯ УСЛОВИЙ ПОЛИТИК RLS';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
END $$;

-- Индекс для projects (segment_id, status) - часто используется в политиках
CREATE INDEX IF NOT EXISTS idx_projects_segment_status 
ON app.projects(segment_id, status);

-- Индекс для contracts (segment_id, actor_id)
CREATE INDEX IF NOT EXISTS idx_contracts_segment_actor 
ON app.contracts(segment_id, actor_id);

-- Индекс для recording_sessions (segment_id, session_date)
CREATE INDEX IF NOT EXISTS idx_sessions_segment_date 
ON app.recording_sessions(segment_id, session_date);

-- Индекс для actors (segment_id)
CREATE INDEX IF NOT EXISTS idx_actors_segment 
ON app.actors(segment_id);

-- =====================================================
-- ТЕСТ 1: Выборка проектов по segment_id и status
-- =====================================================

DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
    RAISE NOTICE 'ТЕСТ 1: Выборка проектов по segment_id и status';
    RAISE NOTICE 'Запрос: SELECT * FROM app.projects WHERE segment_id = 1 AND status = ''active''';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
END $$;

-- Тест БЕЗ RLS
DO $$
DECLARE
    v_result RECORD;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '▶ Выполнение теста БЕЗ RLS...';
    
    -- Очищаем кэш планов для справедливого сравнения
    DISCARD PLANS;
    
    -- Временно отключаем RLS на таблице projects
    ALTER TABLE app.projects DISABLE ROW LEVEL SECURITY;
    
    -- Выполняем тест
    SELECT * INTO v_result
    FROM audit.run_explain_test(
        'TEST1: Projects by segment and status',
        'SELECT * FROM app.projects WHERE segment_id = 1 AND status = ''active''',
        FALSE
    );
    
    -- Включаем RLS обратно
    ALTER TABLE app.projects ENABLE ROW LEVEL SECURITY;
    
    IF v_result.execution_time_ms IS NOT NULL THEN
        RAISE NOTICE '   Время выполнения: % ms', ROUND(v_result.execution_time_ms::NUMERIC, 3);
    ELSE
        RAISE NOTICE '   Время выполнения: не определено';
    END IF;
    IF v_result.planning_time_ms IS NOT NULL THEN
        RAISE NOTICE '   Время планирования: % ms', ROUND(v_result.planning_time_ms::NUMERIC, 3);
    ELSE
        RAISE NOTICE '   Время планирования: не определено';
    END IF;
    RAISE NOTICE '   Буферов прочитано: %', COALESCE(v_result.total_buffers_read, 0);
END $$;

-- Тест С RLS
DO $$
DECLARE
    v_result RECORD;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '▶ Выполнение теста С RLS...';
    
    -- Очищаем кэш планов для справедливого сравнения
    DISCARD PLANS;
    
    SET ROLE app_writer;
    PERFORM app.set_session_ctx(1, NULL);
    
    -- Выполняем тест
    SELECT * INTO v_result
    FROM audit.run_explain_test(
        'TEST1: Projects by segment and status',
        'SELECT * FROM app.projects WHERE segment_id = 1 AND status = ''active''',
        TRUE
    );
    
    RESET ROLE;
    
    IF v_result.execution_time_ms IS NOT NULL THEN
        RAISE NOTICE '   Время выполнения: % ms', ROUND(v_result.execution_time_ms::NUMERIC, 3);
    ELSE
        RAISE NOTICE '   Время выполнения: не определено';
    END IF;
    IF v_result.planning_time_ms IS NOT NULL THEN
        RAISE NOTICE '   Время планирования: % ms', ROUND(v_result.planning_time_ms::NUMERIC, 3);
    ELSE
        RAISE NOTICE '   Время планирования: не определено';
    END IF;
    RAISE NOTICE '   Буферов прочитано: %', COALESCE(v_result.total_buffers_read, 0);
END $$;

-- =====================================================
-- ТЕСТ 2: Выборка контрактов с JOIN к актёрам
-- =====================================================

DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
    RAISE NOTICE 'ТЕСТ 2: Выборка контрактов с JOIN к актёрам';
    RAISE NOTICE 'Запрос: SELECT c.*, a.first_name, a.last_name FROM app.contracts c JOIN app.actors a ON c.actor_id = a.actor_id WHERE c.segment_id = 1';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
END $$;

-- Тест БЕЗ RLS
DO $$
DECLARE
    v_result RECORD;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '▶ Выполнение теста БЕЗ RLS...';
    
    -- Очищаем кэш планов для справедливого сравнения
    DISCARD PLANS;
    
    -- Временно отключаем RLS
    ALTER TABLE app.contracts DISABLE ROW LEVEL SECURITY;
    ALTER TABLE app.actors DISABLE ROW LEVEL SECURITY;
    
    -- Выполняем тест
    SELECT * INTO v_result
    FROM audit.run_explain_test(
        'TEST2: Contracts with JOIN to actors',
        'SELECT c.*, a.first_name, a.last_name FROM app.contracts c JOIN app.actors a ON c.actor_id = a.actor_id WHERE c.segment_id = 1',
        FALSE
    );
    
    -- Включаем RLS обратно
    ALTER TABLE app.contracts ENABLE ROW LEVEL SECURITY;
    ALTER TABLE app.actors ENABLE ROW LEVEL SECURITY;
    
    IF v_result.execution_time_ms IS NOT NULL THEN
        RAISE NOTICE '   Время выполнения: % ms', ROUND(v_result.execution_time_ms::NUMERIC, 3);
    ELSE
        RAISE NOTICE '   Время выполнения: не определено';
    END IF;
    IF v_result.planning_time_ms IS NOT NULL THEN
        RAISE NOTICE '   Время планирования: % ms', ROUND(v_result.planning_time_ms::NUMERIC, 3);
    ELSE
        RAISE NOTICE '   Время планирования: не определено';
    END IF;
    RAISE NOTICE '   Буферов прочитано: %', COALESCE(v_result.total_buffers_read, 0);
END $$;

-- Тест С RLS
DO $$
DECLARE
    v_result RECORD;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '▶ Выполнение теста С RLS...';
    
    -- Очищаем кэш планов для справедливого сравнения
    DISCARD PLANS;
    
    SET ROLE app_writer;
    PERFORM app.set_session_ctx(1, NULL);
    
    -- Выполняем тест
    SELECT * INTO v_result
    FROM audit.run_explain_test(
        'TEST2: Contracts with JOIN to actors',
        'SELECT c.*, a.first_name, a.last_name FROM app.contracts c JOIN app.actors a ON c.actor_id = a.actor_id WHERE c.segment_id = 1',
        TRUE
    );
    
    RESET ROLE;
    
    IF v_result.execution_time_ms IS NOT NULL THEN
        RAISE NOTICE '   Время выполнения: % ms', ROUND(v_result.execution_time_ms::NUMERIC, 3);
    ELSE
        RAISE NOTICE '   Время выполнения: не определено';
    END IF;
    IF v_result.planning_time_ms IS NOT NULL THEN
        RAISE NOTICE '   Время планирования: % ms', ROUND(v_result.planning_time_ms::NUMERIC, 3);
    ELSE
        RAISE NOTICE '   Время планирования: не определено';
    END IF;
    RAISE NOTICE '   Буферов прочитано: %', COALESCE(v_result.total_buffers_read, 0);
END $$;

-- =====================================================
-- ТЕСТ 3: Агрегирующий запрос по сессиям записи
-- =====================================================

DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
    RAISE NOTICE 'ТЕСТ 3: Агрегирующий запрос по сессиям записи';
    RAISE NOTICE 'Запрос: SELECT segment_id, status, COUNT(*), SUM(duration_hours) FROM app.recording_sessions GROUP BY segment_id, status';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
END $$;

-- Тест БЕЗ RLS
DO $$
DECLARE
    v_result RECORD;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '▶ Выполнение теста БЕЗ RLS...';
    
    -- Очищаем кэш планов для справедливого сравнения
    DISCARD PLANS;
    
    -- Временно отключаем RLS
    ALTER TABLE app.recording_sessions DISABLE ROW LEVEL SECURITY;
    
    -- Выполняем тест
    SELECT * INTO v_result
    FROM audit.run_explain_test(
        'TEST3: Aggregate query on recording_sessions',
        'SELECT segment_id, status, COUNT(*), SUM(duration_hours) FROM app.recording_sessions GROUP BY segment_id, status',
        FALSE
    );
    
    -- Включаем RLS обратно
    ALTER TABLE app.recording_sessions ENABLE ROW LEVEL SECURITY;
    
    IF v_result.execution_time_ms IS NOT NULL THEN
        RAISE NOTICE '   Время выполнения: % ms', ROUND(v_result.execution_time_ms::NUMERIC, 3);
    ELSE
        RAISE NOTICE '   Время выполнения: не определено';
    END IF;
    IF v_result.planning_time_ms IS NOT NULL THEN
        RAISE NOTICE '   Время планирования: % ms', ROUND(v_result.planning_time_ms::NUMERIC, 3);
    ELSE
        RAISE NOTICE '   Время планирования: не определено';
    END IF;
    RAISE NOTICE '   Буферов прочитано: %', COALESCE(v_result.total_buffers_read, 0);
END $$;

-- Тест С RLS
DO $$
DECLARE
    v_result RECORD;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '▶ Выполнение теста С RLS...';
    
    -- Очищаем кэш планов для справедливого сравнения
    DISCARD PLANS;
    
    SET ROLE app_writer;
    PERFORM app.set_session_ctx(1, NULL);
    
    -- Выполняем тест
    SELECT * INTO v_result
    FROM audit.run_explain_test(
        'TEST3: Aggregate query on recording_sessions',
        'SELECT segment_id, status, COUNT(*), SUM(duration_hours) FROM app.recording_sessions GROUP BY segment_id, status',
        TRUE
    );
    
    RESET ROLE;
    
    IF v_result.execution_time_ms IS NOT NULL THEN
        RAISE NOTICE '   Время выполнения: % ms', ROUND(v_result.execution_time_ms::NUMERIC, 3);
    ELSE
        RAISE NOTICE '   Время выполнения: не определено';
    END IF;
    IF v_result.planning_time_ms IS NOT NULL THEN
        RAISE NOTICE '   Время планирования: % ms', ROUND(v_result.planning_time_ms::NUMERIC, 3);
    ELSE
        RAISE NOTICE '   Время планирования: не определено';
    END IF;
    RAISE NOTICE '   Буферов прочитано: %', COALESCE(v_result.total_buffers_read, 0);
END $$;

-- =====================================================
-- Сравнение производительности: вывод результатов
-- =====================================================

DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
    RAISE NOTICE 'СРАВНЕНИЕ ПРОИЗВОДИТЕЛЬНОСТИ: ДО/ПОСЛЕ RLS';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
END $$;

-- Выводим детальное сравнение
SELECT 
    query_name as "Запрос",
    CASE WHEN rls_enabled THEN 'ДА' ELSE 'НЕТ' END as "RLS",
    ROUND(execution_time_ms::NUMERIC, 3) as "Время выполнения (мс)",
    ROUND(planning_time_ms::NUMERIC, 3) as "Время планирования (мс)",
    (buffers_shared_read + buffers_local_read) as "Буферов прочитано",
    buffers_shared_hit as "Буферов из кэша",
    COALESCE(array_to_string(indexes_used, ', '), 'нет') as "Использованные индексы"
FROM audit.performance_analysis
WHERE query_name LIKE 'TEST%'
ORDER BY query_name, rls_enabled;

-- Выводим сравнение для каждого теста
DO $$
DECLARE
    v_test_name TEXT;
    v_without_rls RECORD;
    v_with_rls RECORD;
    v_overhead NUMERIC;
BEGIN
    FOR v_test_name IN 
        SELECT DISTINCT query_name 
        FROM audit.performance_analysis 
        WHERE query_name LIKE 'TEST%'
        ORDER BY query_name
    LOOP
        -- Получаем результаты БЕЗ RLS
        SELECT * INTO v_without_rls
        FROM audit.performance_analysis
        WHERE query_name = v_test_name AND rls_enabled = FALSE
        ORDER BY analysis_time DESC
        LIMIT 1;
        
        -- Получаем результаты С RLS
        SELECT * INTO v_with_rls
        FROM audit.performance_analysis
        WHERE query_name = v_test_name AND rls_enabled = TRUE
        ORDER BY analysis_time DESC
        LIMIT 1;
        
        IF v_without_rls IS NOT NULL AND v_with_rls IS NOT NULL THEN
            v_overhead := ((v_with_rls.execution_time_ms - v_without_rls.execution_time_ms) / NULLIF(v_without_rls.execution_time_ms, 0) * 100);
            
            RAISE NOTICE '';
            RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
            RAISE NOTICE '%', v_test_name;
            RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
            RAISE NOTICE 'БЕЗ RLS:';
            IF v_without_rls.execution_time_ms IS NOT NULL THEN
                RAISE NOTICE '  • Время выполнения: % мс', ROUND(v_without_rls.execution_time_ms::NUMERIC, 3);
            ELSE
                RAISE NOTICE '  • Время выполнения: не определено';
            END IF;
            IF v_without_rls.planning_time_ms IS NOT NULL THEN
                RAISE NOTICE '  • Время планирования: % мс', ROUND(v_without_rls.planning_time_ms::NUMERIC, 3);
            ELSE
                RAISE NOTICE '  • Время планирования: не определено';
            END IF;
            RAISE NOTICE '  • Буферов прочитано: %', COALESCE((v_without_rls.buffers_shared_read + v_without_rls.buffers_local_read), 0);
            RAISE NOTICE '';
            RAISE NOTICE 'С RLS:';
            IF v_with_rls.execution_time_ms IS NOT NULL THEN
                RAISE NOTICE '  • Время выполнения: % мс', ROUND(v_with_rls.execution_time_ms::NUMERIC, 3);
            ELSE
                RAISE NOTICE '  • Время выполнения: не определено';
            END IF;
            IF v_with_rls.planning_time_ms IS NOT NULL THEN
                RAISE NOTICE '  • Время планирования: % мс', ROUND(v_with_rls.planning_time_ms::NUMERIC, 3);
            ELSE
                RAISE NOTICE '  • Время планирования: не определено';
            END IF;
            RAISE NOTICE '  • Буферов прочитано: %', COALESCE((v_with_rls.buffers_shared_read + v_with_rls.buffers_local_read), 0);
            RAISE NOTICE '';
            RAISE NOTICE 'ЭФФЕКТ RLS:';
            IF v_without_rls.execution_time_ms IS NOT NULL AND v_with_rls.execution_time_ms IS NOT NULL THEN
                RAISE NOTICE '  • Прирост времени выполнения: %%%', ROUND(v_overhead::NUMERIC, 2);
                RAISE NOTICE '  • Разница во времени: % мс', ROUND((v_with_rls.execution_time_ms - v_without_rls.execution_time_ms)::NUMERIC, 3);
            ELSE
                RAISE NOTICE '  • Прирост времени выполнения: не определено';
            END IF;
            RAISE NOTICE '  • Разница в буферах: %', COALESCE(((v_with_rls.buffers_shared_read + v_with_rls.buffers_local_read) - (v_without_rls.buffers_shared_read + v_without_rls.buffers_local_read)), 0);
        END IF;
    END LOOP;
END $$;

-- =====================================================
-- Функция для сравнения производительности
-- =====================================================

DROP FUNCTION IF EXISTS audit.compare_performance() CASCADE;

CREATE OR REPLACE FUNCTION audit.compare_performance()
RETURNS TABLE (
    query_name TEXT,
    rls_enabled BOOLEAN,
    execution_time_ms NUMERIC,
    planning_time_ms NUMERIC,
    total_buffers_read BIGINT,
    buffers_from_cache BIGINT
) 
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = audit, public
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        pa.query_name::TEXT,
        pa.rls_enabled,
        pa.execution_time_ms,
        pa.planning_time_ms,
        (pa.buffers_shared_read + pa.buffers_local_read)::BIGINT as total_buffers_read,
        pa.buffers_shared_hit::BIGINT as buffers_from_cache
    FROM audit.performance_analysis pa
    WHERE pa.query_name LIKE 'TEST%'
    ORDER BY pa.query_name, pa.rls_enabled;
END;
$$;

GRANT EXECUTE ON FUNCTION audit.save_explain_result(TEXT, BOOLEAN, TEXT) TO app_reader, app_writer, auditor, security_admin;
GRANT EXECUTE ON FUNCTION audit.run_explain_test(TEXT, TEXT, BOOLEAN) TO app_reader, app_writer, auditor, security_admin;
GRANT EXECUTE ON FUNCTION audit.compare_performance() TO app_reader, app_writer, auditor, security_admin;

RESET ROLE;
