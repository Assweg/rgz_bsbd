#!/bin/bash

# Демонстрация ручного запуска функции backup_audit_logs
# Показывает весь процесс: создание старых записей, запуск функции, проверка результата

set -e

echo "====================================================="
echo "  ДЕМОНСТРАЦИЯ: backup_audit_logs(days_interval INT)"
echo "  Ручной запуск функции и показ результата"
echo "====================================================="
echo ""

# Проверяем контейнер
if ! docker ps | grep -q "dubbing_studio_postgres"; then
    echo "❌ Контейнер PostgreSQL не запущен!"
    exit 1
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "ШАГ 1: Проверяем текущее состояние таблиц"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
docker exec dubbing_studio_postgres psql -U postgres -d dubbing_studio <<'SQL'
SET ROLE app_owner;

SELECT 
    'Основная таблица (audit.row_change_log)' as таблица,
    COUNT(*) as всего_записей,
    COUNT(*) FILTER (WHERE change_time < NOW() - INTERVAL '30 days') as старше_30_дней,
    MIN(change_time)::date as старейшая,
    MAX(change_time)::date as новейшая
FROM audit.row_change_log
UNION ALL
SELECT 
    'Архивная таблица (audit.row_change_log_archive)',
    COUNT(*),
    NULL,
    MIN(change_time)::date,
    MAX(change_time)::date
FROM audit.row_change_log_archive;
SQL

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "ШАГ 2: Создаём тестовые старые записи (старше 30 дней)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
docker exec dubbing_studio_postgres psql -U postgres -d dubbing_studio <<'SQL'
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
    (NOW() - INTERVAL '35 days', 'demo_user', 'app', 'projects', 'UPDATE', 300, '{"title": "Old Project Title"}'::JSONB, '{"title": "New Project Title"}'::JSONB, ARRAY['title']),
    (NOW() - INTERVAL '40 days', 'demo_user', 'app', 'contracts', 'INSERT', 301, NULL, '{"status": "active", "salary_amount": 50000}'::JSONB, ARRAY['status', 'salary_amount']),
    (NOW() - INTERVAL '45 days', 'demo_user', 'app', 'actors', 'DELETE', 302, '{"first_name": "John", "last_name": "Doe"}'::JSONB, NULL, ARRAY['first_name', 'last_name'])
ON CONFLICT DO NOTHING;

SELECT 
    'После добавления' as статус,
    COUNT(*) as всего_записей,
    COUNT(*) FILTER (WHERE change_time < NOW() - INTERVAL '30 days') as старше_30_дней
FROM audit.row_change_log;
SQL

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "ШАГ 3: Запускаем функцию backup_audit_logs(30) ВРУЧНУЮ"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
docker exec dubbing_studio_postgres psql -U postgres -d dubbing_studio <<'SQL'
SET ROLE app_owner;

SELECT * FROM audit.backup_audit_logs(30);
SQL

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "ШАГ 4: Проверяем результат после архивирования"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
docker exec dubbing_studio_postgres psql -U postgres -d dubbing_studio <<'SQL'
SET ROLE app_owner;

SELECT 
    'Основная таблица (audit.row_change_log)' as таблица,
    COUNT(*) as записей,
    MIN(change_time)::date as старейшая,
    MAX(change_time)::date as новейшая
FROM audit.row_change_log
UNION ALL
SELECT 
    'Архивная таблица (audit.row_change_log_archive)',
    COUNT(*),
    MIN(change_time)::date,
    MAX(change_time)::date
FROM audit.row_change_log_archive;
SQL

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "ШАГ 5: Показываем перенесённые записи в архиве"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
docker exec dubbing_studio_postgres psql -U postgres -d dubbing_studio <<'SQL'
SET ROLE app_owner;

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
SQL

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "ШАГ 6: Статистика архива"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
docker exec dubbing_studio_postgres psql -U postgres -d dubbing_studio <<'SQL'
SET ROLE app_owner;

SELECT * FROM audit.get_archive_statistics();
SQL

echo ""
echo "====================================================="
echo "✅ ДЕМОНСТРАЦИЯ ЗАВЕРШЕНА"
echo "====================================================="
echo ""
echo "Результат выполнения функции backup_audit_logs(30):"
echo "  ✅ Старые записи (старше 30 дней) перенесены в архив"
echo "  ✅ Записи удалены из основной таблицы audit.row_change_log"
echo "  ✅ Все данные сохранены в audit.row_change_log_archive"
echo "  ✅ Добавлена метка времени архивирования (archived_at)"
echo ""
echo "Функция готова к использованию:"
echo "  SELECT * FROM audit.backup_audit_logs(30);  -- Архивировать записи старше 30 дней"
echo "  SELECT * FROM audit.get_archive_statistics();  -- Просмотр статистики"
echo ""

