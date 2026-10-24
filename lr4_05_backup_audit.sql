
SET search_path TO app, ref, audit, stg, public;
SET ROLE app_owner;

-- =====================================================
-- Создание архивной таблицы
-- =====================================================

CREATE TABLE IF NOT EXISTS audit.row_change_log_archive (
    log_id BIGINT PRIMARY KEY,
    change_time TIMESTAMPTZ NOT NULL,
    changed_by VARCHAR(100) NOT NULL,
    table_schema VARCHAR(100) NOT NULL,
    table_name VARCHAR(100) NOT NULL,
    operation_type VARCHAR(10) NOT NULL,
    record_id INTEGER,
    old_values JSONB,
    new_values JSONB,
    changed_fields TEXT[],
    client_ip INET,
    session_info JSONB,
    archived_at TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

-- Индексы для архивной таблицы
CREATE INDEX IF NOT EXISTS idx_row_change_log_archive_time 
ON audit.row_change_log_archive(change_time);
CREATE INDEX IF NOT EXISTS idx_row_change_log_archive_table 
ON audit.row_change_log_archive(table_schema, table_name);
CREATE INDEX IF NOT EXISTS idx_row_change_log_archive_user 
ON audit.row_change_log_archive(changed_by);
CREATE INDEX IF NOT EXISTS idx_row_change_log_archive_archived 
ON audit.row_change_log_archive(archived_at);

COMMENT ON TABLE audit.row_change_log_archive IS 
'Архивная таблица для старых записей из audit.row_change_log. Записи старше N дней переносятся сюда.';

-- =====================================================
-- Функция резервного копирования audit-логов
-- =====================================================

CREATE OR REPLACE FUNCTION audit.backup_audit_logs(days_interval INT)
RETURNS TABLE (
    records_moved BIGINT,
    oldest_record_date TIMESTAMPTZ,
    newest_record_date TIMESTAMPTZ,
    backup_time TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = audit, public
AS $$
DECLARE
    v_cutoff_date TIMESTAMPTZ;
    v_records_moved BIGINT;
    v_oldest_date TIMESTAMPTZ;
    v_newest_date TIMESTAMPTZ;
    v_start_time TIMESTAMPTZ;
    v_end_time TIMESTAMPTZ;
    v_duration INTERVAL;
BEGIN
    v_start_time := clock_timestamp();
    
    -- Вычисляем дату отсечки
    v_cutoff_date := NOW() - (days_interval || ' days')::INTERVAL;
    
    RAISE NOTICE '';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
    RAISE NOTICE 'НАЧАЛО РЕЗЕРВНОГО КОПИРОВАНИЯ AUDIT-ЛОГОВ';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
    RAISE NOTICE 'Параметры:';
    RAISE NOTICE '  • Интервал архивирования: % дней', days_interval;
    RAISE NOTICE '  • Дата отсечки: %', v_cutoff_date;
    RAISE NOTICE '';
    
    -- Получаем информацию о записях, которые будут перемещены
    SELECT 
        COUNT(*),
        MIN(change_time),
        MAX(change_time)
    INTO 
        v_records_moved,
        v_oldest_date,
        v_newest_date
    FROM audit.row_change_log
    WHERE change_time < v_cutoff_date;
    
    RAISE NOTICE 'Анализ записей для архивирования:';
    RAISE NOTICE '  • Записей для перемещения: %', v_records_moved;
    
    IF v_records_moved = 0 THEN
        RAISE NOTICE '';
        RAISE NOTICE '⚠️  Нет записей для архивирования (все записи новее % дней)', days_interval;
        RAISE NOTICE '';
        
        RETURN QUERY SELECT 
            0::BIGINT,
            NULL::TIMESTAMPTZ,
            NULL::TIMESTAMPTZ,
            clock_timestamp();
        RETURN;
    END IF;
    
    IF v_oldest_date IS NOT NULL THEN
        RAISE NOTICE '  • Старейшая запись: %', v_oldest_date;
    END IF;
    IF v_newest_date IS NOT NULL THEN
        RAISE NOTICE '  • Новейшая запись: %', v_newest_date;
    END IF;
    RAISE NOTICE '';
    
    -- Перемещаем записи в архив
    RAISE NOTICE '▶ Перемещение записей в архивную таблицу...';
    
    INSERT INTO audit.row_change_log_archive (
        log_id,
        change_time,
        changed_by,
        table_schema,
        table_name,
        operation_type,
        record_id,
        old_values,
        new_values,
        changed_fields,
        client_ip,
        session_info
    )
    SELECT 
        log_id,
        change_time,
        changed_by,
        table_schema,
        table_name,
        operation_type,
        record_id,
        old_values,
        new_values,
        changed_fields,
        client_ip,
        session_info
    FROM audit.row_change_log
    WHERE change_time < v_cutoff_date
    ON CONFLICT (log_id) DO NOTHING;
    
    RAISE NOTICE '  ✅ Записи перемещены в архив';
    
    -- Удаляем перемещённые записи из основной таблицы
    RAISE NOTICE '▶ Удаление записей из основной таблицы...';
    
    DELETE FROM audit.row_change_log
    WHERE change_time < v_cutoff_date;
    
    RAISE NOTICE '  ✅ Записи удалены из основной таблицы';
    
    v_end_time := clock_timestamp();
    v_duration := v_end_time - v_start_time;
    
    -- Возвращаем результаты
    RETURN QUERY SELECT 
        v_records_moved,
        v_oldest_date,
        v_newest_date,
        v_end_time;
    
    -- Итоговая информация
    RAISE NOTICE '';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
    RAISE NOTICE 'РЕЗЕРВНОЕ КОПИРОВАНИЕ ЗАВЕРШЕНО УСПЕШНО';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
    RAISE NOTICE 'Результаты:';
    RAISE NOTICE '  • Перемещено записей: %', v_records_moved;
    RAISE NOTICE '  • Время выполнения: %', v_duration;
    RAISE NOTICE '  • Завершено в: %', v_end_time;
    RAISE NOTICE '';
    
EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'Ошибка при резервном копировании: %', SQLERRM;
END;
$$;

-- =====================================================
-- Функция для просмотра статистики архива
-- =====================================================

CREATE OR REPLACE FUNCTION audit.get_archive_statistics()
RETURNS TABLE (
    total_archived BIGINT,
    oldest_record TIMESTAMPTZ,
    newest_record TIMESTAMPTZ,
    records_by_table JSONB,
    records_by_operation JSONB
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_records_by_table JSONB;
    v_records_by_operation JSONB;
BEGIN
    -- Статистика по таблицам
    SELECT jsonb_object_agg(table_name, count) INTO v_records_by_table
    FROM (
        SELECT 
            table_name,
            COUNT(*)::BIGINT as count
        FROM audit.row_change_log_archive
        GROUP BY table_name
        ORDER BY count DESC
    ) stats;
    
    -- Статистика по операциям
    SELECT jsonb_object_agg(operation_type, count) INTO v_records_by_operation
    FROM (
        SELECT 
            operation_type,
            COUNT(*)::BIGINT as count
        FROM audit.row_change_log_archive
        GROUP BY operation_type
        ORDER BY count DESC
    ) stats;
    
    RETURN QUERY
    SELECT 
        COUNT(*)::BIGINT as total_archived,
        MIN(change_time) as oldest_record,
        MAX(change_time) as newest_record,
        COALESCE(v_records_by_table, '{}'::JSONB) as records_by_table,
        COALESCE(v_records_by_operation, '{}'::JSONB) as records_by_operation
    FROM audit.row_change_log_archive;
END;
$$;

-- Выдаём права
GRANT EXECUTE ON FUNCTION audit.backup_audit_logs(INT) TO dml_admin, security_admin;
GRANT EXECUTE ON FUNCTION audit.get_archive_statistics() TO auditor, security_admin;
GRANT SELECT ON audit.row_change_log_archive TO auditor, security_admin;

COMMENT ON FUNCTION audit.backup_audit_logs(INT) IS 
'Переносит записи старше N дней из audit.row_change_log в audit.row_change_log_archive и удаляет их из основной таблицы.';

COMMENT ON FUNCTION audit.get_archive_statistics() IS 
'Возвращает статистику по архивным записям: общее количество, диапазон дат, распределение по таблицам и операциям.';

-- =====================================================
-- Демонстрация работы функции
-- =====================================================

DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
    RAISE NOTICE 'ДЕМОНСТРАЦИЯ: Резервное копирование записей старше 30 дней';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
END $$;

-- Сначала проверяем текущее состояние
DO $$
DECLARE
    v_total_records BIGINT;
    v_old_records BIGINT;
    v_archive_records BIGINT;
    v_oldest_record TIMESTAMPTZ;
    v_newest_record TIMESTAMPTZ;
BEGIN
    SELECT COUNT(*) INTO v_total_records FROM audit.row_change_log;
    SELECT COUNT(*) INTO v_old_records 
    FROM audit.row_change_log 
    WHERE change_time < NOW() - INTERVAL '30 days';
    SELECT COUNT(*) INTO v_archive_records FROM audit.row_change_log_archive;
    
    SELECT MIN(change_time), MAX(change_time)
    INTO v_oldest_record, v_newest_record
    FROM audit.row_change_log;
    
    RAISE NOTICE '';
    RAISE NOTICE 'ТЕКУЩЕЕ СОСТОЯНИЕ:';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
    RAISE NOTICE 'Основная таблица (audit.row_change_log):';
    RAISE NOTICE '  • Всего записей: %', v_total_records;
    IF v_oldest_record IS NOT NULL THEN
        RAISE NOTICE '  • Старейшая запись: %', v_oldest_record;
    END IF;
    IF v_newest_record IS NOT NULL THEN
        RAISE NOTICE '  • Новейшая запись: %', v_newest_record;
    END IF;
    RAISE NOTICE '  • Записей старше 30 дней: %', v_old_records;
    RAISE NOTICE '';
    RAISE NOTICE 'Архивная таблица (audit.row_change_log_archive):';
    RAISE NOTICE '  • Всего записей в архиве: %', v_archive_records;
    RAISE NOTICE '';
END $$;

-- Выполняем резервное копирование
DO $$
DECLARE
    v_result RECORD;
    v_stats RECORD;
BEGIN
    -- Вызываем функцию резервного копирования
    SELECT * INTO v_result
    FROM audit.backup_audit_logs(30);
    
    -- Получаем статистику архива
    SELECT * INTO v_stats
    FROM audit.get_archive_statistics();
    
    RAISE NOTICE '';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
    RAISE NOTICE 'СТАТИСТИКА АРХИВА ПОСЛЕ РЕЗЕРВНОГО КОПИРОВАНИЯ';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
    RAISE NOTICE 'Общая информация:';
    RAISE NOTICE '  • Всего записей в архиве: %', v_stats.total_archived;
    IF v_stats.oldest_record IS NOT NULL THEN
        RAISE NOTICE '  • Старейшая запись: %', v_stats.oldest_record;
    END IF;
    IF v_stats.newest_record IS NOT NULL THEN
        RAISE NOTICE '  • Новейшая запись: %', v_stats.newest_record;
    END IF;
    RAISE NOTICE '';
    
    IF v_stats.records_by_table IS NOT NULL AND v_stats.records_by_table != '{}'::JSONB THEN
        RAISE NOTICE 'Распределение по таблицам:';
        -- Выводим статистику по таблицам (упрощённо)
        RAISE NOTICE '  %', v_stats.records_by_table::TEXT;
    END IF;
    
    IF v_stats.records_by_operation IS NOT NULL AND v_stats.records_by_operation != '{}'::JSONB THEN
        RAISE NOTICE '';
        RAISE NOTICE 'Распределение по операциям:';
        RAISE NOTICE '  %', v_stats.records_by_operation::TEXT;
    END IF;
    
    RAISE NOTICE '';
END $$;

-- Проверяем результат
DO $$
DECLARE
    v_total_records BIGINT;
    v_archive_records BIGINT;
BEGIN
    SELECT COUNT(*) INTO v_total_records FROM audit.row_change_log;
    SELECT COUNT(*) INTO v_archive_records FROM audit.row_change_log_archive;
    
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
    RAISE NOTICE 'ИТОГОВОЕ СОСТОЯНИЕ';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
    RAISE NOTICE '  • Записей в row_change_log: %', v_total_records;
    RAISE NOTICE '  • Записей в row_change_log_archive: %', v_archive_records;
    RAISE NOTICE '';
END $$;

DO $$
BEGIN
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
    RAISE NOTICE '✅ СИСТЕМА РЕЗЕРВНОГО КОПИРОВАНИЯ AUDIT-ЛОГОВ НАСТРОЕНА';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
    RAISE NOTICE '';
    RAISE NOTICE 'Использование:';
    RAISE NOTICE '  SELECT * FROM audit.backup_audit_logs(30);  -- Архивировать записи старше 30 дней';
    RAISE NOTICE '  SELECT * FROM audit.get_archive_statistics();  -- Просмотр статистики архива';
    RAISE NOTICE '';
END $$;

RESET ROLE;
