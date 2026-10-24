-- =====================================================
-- ДЕМОНСТРАЦИЯ: Ручной вызов функции backup_audit_logs
-- Для использования в pgAdmin
-- =====================================================

SET ROLE app_owner;

-- =====================================================
-- ШАГ 1: Проверяем текущее состояние
-- =====================================================

SELECT 
    'Основная таблица (audit.row_change_log)' as таблица,
    COUNT(*) as всего_записей,
    COUNT(*) FILTER (WHERE change_time < NOW() - INTERVAL '30 days') as старше_30_дней,
    MIN(change_time)::date as старейшая_запись,
    MAX(change_time)::date as новейшая_запись
FROM audit.row_change_log
UNION ALL
SELECT 
    'Архивная таблица (audit.row_change_log_archive)',
    COUNT(*),
    NULL,
    MIN(change_time)::date,
    MAX(change_time)::date
FROM audit.row_change_log_archive;

-- =====================================================
-- ШАГ 2: Создаём старые записи для демонстрации
-- (если их ещё нет)
-- =====================================================

INSERT INTO audit.row_change_log (
    change_time,
    changed_by,
    table_schema,
    table_name,
    operation_type,
    record_id,
    old_values,
    new_values,
    changed_fields
) VALUES
    (NOW() - INTERVAL '35 days', 'demo_user', 'app', 'projects', 'UPDATE', 600, 
     '{"title": "Старый проект 1", "status": "draft"}'::JSONB, 
     '{"title": "Новый проект 1", "status": "active"}'::JSONB, 
     ARRAY['title', 'status']),
    (NOW() - INTERVAL '40 days', 'demo_user', 'app', 'contracts', 'INSERT', 601, 
     NULL, 
     '{"status": "active", "start_date": "2024-01-01"}'::JSONB, 
     ARRAY['status', 'start_date']),
    (NOW() - INTERVAL '45 days', 'demo_user', 'app', 'actors', 'DELETE', 602, 
     '{"first_name": "Иван", "last_name": "Иванов"}'::JSONB, 
     NULL, 
     ARRAY['first_name', 'last_name']),
    (NOW() - INTERVAL '50 days', 'demo_user', 'app', 'projects', 'UPDATE', 603, 
     '{"budget": 100000}'::JSONB, 
     '{"budget": 150000}'::JSONB, 
     ARRAY['budget']),
    (NOW() - INTERVAL '55 days', 'demo_user', 'app', 'recording_sessions', 'UPDATE', 604, 
     '{"duration_hours": 2, "status": "scheduled"}'::JSONB, 
     '{"duration_hours": 3, "status": "completed"}'::JSONB, 
     ARRAY['duration_hours', 'status'])
ON CONFLICT DO NOTHING;

-- Проверяем, сколько записей старше 30 дней
SELECT 
    'После создания тестовых записей' as статус,
    COUNT(*) as всего_записей,
    COUNT(*) FILTER (WHERE change_time < NOW() - INTERVAL '30 days') as старше_30_дней
FROM audit.row_change_log;

-- =====================================================
-- ШАГ 3: ВЫЗОВ ФУНКЦИИ backup_audit_logs(30) ВРУЧНУЮ
-- =====================================================

SELECT * FROM audit.backup_audit_logs(30);

-- =====================================================
-- ШАГ 4: Проверяем результат после архивирования
-- =====================================================

SELECT 
    'Основная таблица (audit.row_change_log)' as таблица,
    COUNT(*) as записей,
    MIN(change_time)::date as старейшая_запись,
    MAX(change_time)::date as новейшая_запись
FROM audit.row_change_log
UNION ALL
SELECT 
    'Архивная таблица (audit.row_change_log_archive)',
    COUNT(*),
    MIN(change_time)::date,
    MAX(change_time)::date
FROM audit.row_change_log_archive;

-- =====================================================
-- ШАГ 5: Показываем перенесённые записи в архиве
-- =====================================================

SELECT 
    log_id,
    change_time::date as дата_изменения,
    changed_by as пользователь,
    table_schema || '.' || table_name as таблица,
    operation_type as операция,
    archived_at::timestamp(0) as время_архивирования
FROM audit.row_change_log_archive
ORDER BY change_time DESC
LIMIT 10;

-- =====================================================
-- ШАГ 6: Статистика архива
-- =====================================================

SELECT * FROM audit.get_archive_statistics();

-- =====================================================
-- ИТОГОВАЯ ИНФОРМАЦИЯ
-- =====================================================

SELECT 
    '✅ Демонстрация завершена!' as результат,
    'Функция backup_audit_logs(30) успешно:' as описание
UNION ALL
SELECT 
    '  • Перенесла старые записи в архив',
    '  • Удалила их из основной таблицы'
UNION ALL
SELECT 
    '  • Сохранила все данные',
    '  • Добавила метку времени архивирования';

