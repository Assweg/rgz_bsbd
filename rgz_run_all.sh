#!/bin/bash

# Автоматический запуск РГЗ (система временных привилегий) внутри Docker

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
    if [ $? -eq 0 ]; then
        echo "✅ $1 выполнен успешно."
    else
        echo "❌ Ошибка при выполнении $1"
        exit 1
    fi
}

echo "====================================================="
echo "  РАСЧЕТНО-ГРАФИЧЕСКОЕ ЗАДАНИЕ (РГЗ)"
echo "  Система временных привилегий (Just-In-Time Access)"
echo "====================================================="
echo ""

ensure_stack_running

# Проверяем, что ЛР1-ЛР4 выполнены
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Проверка зависимостей (ЛР1-ЛР4)..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

HAS_FUNCTION_CALLS=$(docker exec "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -tAc "SELECT EXISTS(SELECT 1 FROM information_schema.tables WHERE table_schema = 'audit' AND table_name = 'function_calls');" 2>/dev/null || echo "false")
HAS_SEGMENTS=$(docker exec "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -tAc "SELECT EXISTS(SELECT 1 FROM information_schema.tables WHERE table_schema = 'ref' AND table_name = 'segments');" 2>/dev/null || echo "false")
HAS_ROW_CHANGE_LOG=$(docker exec "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -tAc "SELECT EXISTS(SELECT 1 FROM information_schema.tables WHERE table_schema = 'audit' AND table_name = 'row_change_log');" 2>/dev/null || echo "false")

if [ "$HAS_FUNCTION_CALLS" != "t" ]; then
    echo "❌ Ошибка: Таблица audit.function_calls не найдена."
    echo "   Сначала выполните скрипты ЛР2."
    exit 1
fi

if [ "$HAS_SEGMENTS" != "t" ]; then
    echo "❌ Ошибка: Таблица ref.segments не найдена."
    echo "   Сначала выполните скрипты ЛР3."
    exit 1
fi

if [ "$HAS_ROW_CHANGE_LOG" != "t" ]; then
    echo "⚠️  Предупреждение: Таблица audit.row_change_log не найдена."
    echo "   Рекомендуется выполнить скрипты ЛР4."
fi

echo "✅ Зависимости проверены."

# Выполняем скрипты РГЗ
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Выполнение скриптов РГЗ..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

run_sql "rgz_01_temp_privileges.sql"
run_sql "rgz_02_safe_delete_functions.sql"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Запуск тестов РГЗ..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Тесты выполняются отдельно, так как они могут выводить много информации
run_sql "rgz_03_tests.sql"

echo ""
echo "====================================================="
echo "  РГЗ: ВСЕ СКРИПТЫ ВЫПОЛНЕНЫ УСПЕШНО"
echo "====================================================="
echo ""
echo "Созданные компоненты:"
echo "  ✅ Таблица audit.temp_access_log"
echo "  ✅ Таблица audit.allowed_temp_operations"
echo "  ✅ Функция app.request_temp_privilege()"
echo "  ✅ Функция audit.check_temp_privilege()"
echo "  ✅ Функция app.safe_delete_contract()"
echo "  ✅ Функция app.safe_delete_actor()"
echo "  ✅ Функция app.safe_delete_recording_session()"
echo ""
echo "Для использования:"
echo "  1. docker exec -it $DB_CONTAINER psql -U $DB_USER -d $DB_NAME"
echo "  2. SET ROLE app_writer;"
echo "  3. PERFORM app.set_session_ctx(1, NULL);"
echo "  4. SELECT app.request_temp_privilege('delete_contract', 5);"
echo "  5. SELECT app.safe_delete_contract(contract_id);"
echo ""
echo "Для просмотра журнала:"
echo "  SELECT * FROM audit.temp_access_log ORDER BY request_time DESC;"
echo ""

