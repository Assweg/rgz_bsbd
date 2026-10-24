#!/bin/bash

# Автоматический запуск ЛР4 (безопасные представления, аудит изменений, анализ производительности) внутри Docker

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DB_CONTAINER="dubbing_studio_postgres"
DB_NAME="dubbing_studio"
DB_USER="postgres"
COMPOSE_CMD=""

detect_compose() {
    if command -v docker-compose >/dev/null 2>&1; then
        COMPOSE_CMD="docker-compose"
    elif docker compose version >/dev/null 2>&1; then
        COMPOSE_CMD="docker compose"
    else
        echo "❌ Docker Compose не установлен. Установите docker compose или docker-compose."
        exit 1
    fi
}

container_running() {
    docker ps --format '{{.Names}}' | grep -Fxq "$DB_CONTAINER"
}

ensure_stack_running() {
    detect_compose

    if container_running; then
        echo "✅ Контейнер $DB_CONTAINER уже запущен."
    else
        echo "⚠️  Контейнер $DB_CONTAINER не найден в списке активных. Запускаем стек..."
        (cd "$PROJECT_ROOT" && $COMPOSE_CMD up -d)
    fi

    echo "⏳ Ожидаем готовности базы данных..."
    for _ in {1..30}; do
        if docker exec "$DB_CONTAINER" pg_isready -U "$DB_USER" -d "$DB_NAME" >/dev/null 2>&1; then
            echo "✅ База данных готова."
            return
        fi
        sleep 2
    done

    echo "❌ Не удалось дождаться готовности PostgreSQL в контейнере $DB_CONTAINER."
    exit 1
}

run_sql() {
    local script_path="$PROJECT_ROOT/$1"
    if [ ! -f "$script_path" ]; then
        echo "❌ Файл $script_path не найден."
        exit 1
    fi

    echo ""
    echo "▶️  Выполняем $1 ..."
    docker exec -i "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 < "$script_path"
    echo "✅ $1 выполнен успешно."
}

echo "====================================================="
echo " Лабораторная работа №4 — запуск через Docker"
echo "====================================================="
echo ""
echo "ЛР4 включает:"
echo "  1. Безопасные представления (VIEW с WITH CHECK OPTION и SECURITY BARRIER)"
echo "  2. История изменений (триггеры аудита на критичных таблицах)"
echo "  3. Тесты доступов (4 кейса)"
echo "  4. Анализ производительности (EXPLAIN до/после RLS)"
echo "  5. Автоматическое резервное копирование audit-логов"
echo ""

ensure_stack_running

run_sql "lr4_01_views.sql"
run_sql "lr4_02_audit_triggers.sql"
run_sql "lr4_03_tests.sql"
run_sql "lr4_04_performance.sql"
run_sql "lr4_05_backup_audit.sql"

echo ""
echo "====================================================="
echo "🎉  ЛР4 успешно применена и все тесты отработали без ошибок."
echo "====================================================="
echo ""
echo "Для просмотра результатов:"
echo "  • Тесты доступов: см. вывод выше"
echo "  • Анализ производительности: SELECT * FROM audit.performance_analysis;"
echo "  • Статистика архива: SELECT * FROM audit.get_archive_statistics();"
echo ""

