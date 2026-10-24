#!/bin/bash

# Демонстрация работы функции backup_audit_logs
# Этот скрипт создаёт старые записи и запускает функцию вручную

set -e

echo "====================================================="
echo "  ДЕМОНСТРАЦИЯ: backup_audit_logs(days_interval INT)"
echo "====================================================="
echo ""

# Проверяем, что контейнер запущен
if ! docker ps | grep -q "dubbing_studio_postgres"; then
    echo "❌ Контейнер PostgreSQL не запущен!"
    exit 1
fi

echo "1. Проверяем текущее состояние..."
docker exec dubbing_studio_postgres psql -U postgres -d dubbing_studio <<EOF
SET ROLE app_owner;

SELECT 
    'Основная таблица' as таблица,
    COUNT(*) as записей,
    MIN(change_time) as старейшая,
    MAX(change_time) as новейшая
FROM audit.row_change_log
UNION ALL
SELECT 
    'Архивная таблица',
    COUNT(*),
    MIN(change_time),
    MAX(change_time)
FROM audit.row_change_log_archive;
EOF

echo ""
echo "2. Создаём тестовые старые записи (старше 30 дней)..."
docker exec dubbing_studio_postgres psql -U postgres -d dubbing_studio <<EOF
SET ROLE app_owner;

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
    (NOW() - INTERVAL '35 days', 'demo_user', 'app', 'projects', 'UPDATE', 100, '{"title": "Old Project"}'::JSONB, '{"title": "New Project"}'::JSONB, ARRAY['title']),
    (NOW() - INTERVAL '40 days', 'demo_user', 'app', 'contracts', 'INSERT', 101, NULL, '{"status": "active"}'::JSONB, ARRAY['status']),
    (NOW() - INTERVAL '45 days', 'demo_user', 'app', 'actors', 'DELETE', 102, '{"first_name": "John"}'::JSONB, NULL, ARRAY['first_name']),
    (NOW() - INTERVAL '50 days', 'demo_user', 'app', 'projects', 'UPDATE', 103, '{"status": "draft"}'::JSONB, '{"status": "active"}'::JSONB, ARRAY['status']),
    (NOW() - INTERVAL '55 days', 'demo_user', 'app', 'recording_sessions', 'UPDATE', 104, '{"duration_hours": 2}'::JSONB, '{"duration_hours": 3}'::JSONB, ARRAY['duration_hours'])
ON CONFLICT DO NOTHING;

SELECT 
    'После добавления старых записей' as статус,
    COUNT(*) as всего_записей,
    COUNT(*) FILTER (WHERE change_time < NOW() - INTERVAL '30 days') as старше_30_дней;
FROM audit.row_change_log;
EOF

echo ""
echo "3. Запускаем функцию backup_audit_logs(30) вручную..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
docker exec dubbing_studio_postgres psql -U postgres -d dubbing_studio <<EOF
SET ROLE app_owner;

SELECT * FROM audit.backup_audit_logs(30);
EOF

echo ""
echo "4. Проверяем результат после архивирования..."
docker exec dubbing_studio_postgres psql -U postgres -d dubbing_studio <<EOF
SET ROLE app_owner;

SELECT 
    'Основная таблица (row_change_log)' as таблица,
    COUNT(*) as записей,
    MIN(change_time) as старейшая,
    MAX(change_time) as новейшая
FROM audit.row_change_log
UNION ALL
SELECT 
    'Архивная таблица (row_change_log_archive)',
    COUNT(*),
    MIN(change_time),
    MAX(change_time)
FROM audit.row_change_log_archive;
EOF

echo ""
echo "5. Показываем перенесённые записи в архиве..."
docker exec dubbing_studio_postgres psql -U postgres -d dubbing_studio <<EOF
SET ROLE app_owner;

SELECT 
    log_id,
    change_time,
    changed_by,
    table_schema || '.' || table_name as таблица,
    operation_type as операция,
    archived_at as время_архивирования
FROM audit.row_change_log_archive
ORDER BY change_time;
EOF

echo ""
echo "6. Статистика архива..."
docker exec dubbing_studio_postgres psql -U postgres -d dubbing_studio <<EOF
SET ROLE app_owner;

SELECT * FROM audit.get_archive_statistics();
EOF

echo ""
echo "====================================================="
echo "✅ Демонстрация завершена!"
echo "====================================================="
echo ""
echo "Функция backup_audit_logs успешно:"
echo "  • Перенесла старые записи в архивную таблицу"
echo "  • Удалила их из основной таблицы"
echo "  • Сохранила все данные с меткой времени архивирования"
echo ""

