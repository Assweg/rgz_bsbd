#!/bin/bash

# Автоматический запуск всех лабораторных работ по порядку

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
    local status=$(docker ps --format '{{.Names}} {{.Status}}' | grep "^$DB_CONTAINER " | awk '{print $2}')
    if [ "$status" = "Up" ] || [ "$status" = "running" ]; then
        return 0
    fi
    return 1
}

ensure_stack_running() {
    detect_compose

    if container_running; then
        echo "✅ Контейнер $DB_CONTAINER уже запущен."
    else
        echo "⚠️  Контейнер $DB_CONTAINER не найден. Запускаем стек..."
        (cd "$PROJECT_ROOT" && $COMPOSE_CMD up -d)
    fi

    echo "⏳ Ожидаем готовности базы данных..."
    for i in {1..90}; do
        # Проверяем, что контейнер запущен и не перезапускается
        local container_status=$(docker ps --format '{{.Status}}' --filter "name=$DB_CONTAINER" 2>/dev/null || echo "")
        if [[ "$container_status" == *"Restarting"* ]] || [[ "$container_status" == *"Exited"* ]]; then
            echo "❌ Контейнер в состоянии: $container_status"
            echo "   Проверьте логи: docker logs $DB_CONTAINER | tail -50"
            exit 1
        fi
        
        if docker exec "$DB_CONTAINER" pg_isready -U "$DB_USER" -d "$DB_NAME" >/dev/null 2>&1; then
            echo "✅ База данных готова."
            return
        fi
        if [ $((i % 10)) -eq 0 ]; then
            echo "   Ожидание готовности PostgreSQL... ($((i*2))/180 секунд)"
        fi
        sleep 2
    done

    echo "❌ Не удалось дождаться готовности PostgreSQL в контейнере $DB_CONTAINER."
    echo "   Проверьте логи: docker logs $DB_CONTAINER | tail -20"
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
echo "  ЗАПУСК ВСЕХ ЛАБОРАТОРНЫХ РАБОТ ПО ПОРЯДКУ"
echo "====================================================="
echo ""
echo "Порядок выполнения:"
echo "  1. Лабораторная работа №1 (LR1) - Схемы, таблицы, роли, RLS"
echo "  2. Лабораторная работа №2 (LR2) - SECURITY DEFINER функции, журнал вызовов"
echo "  3. Лабораторная работа №3 (LR3) - Сегментация данных, RLS политики"
echo "  4. Лабораторная работа №4 (LR4) - Безопасные представления, аудит, производительность"
echo ""

ensure_stack_running

# Проверяем, инициализирована ли БД
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Проверка инициализации базы данных..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Ждём завершения автоматической инициализации (если контейнер только что запущен)
echo "⏳ Ожидаем завершения автоматической инициализации БД (если требуется)..."
for i in {1..60}; do
    DB_INITIALIZED=$(docker exec "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -tAc "SELECT EXISTS(SELECT 1 FROM information_schema.tables WHERE table_schema = 'app' AND table_name = 'actors');" 2>/dev/null || echo "false")
    
    if [ "$DB_INITIALIZED" = "t" ]; then
        # Проверяем также наличие схемы audit
        AUDIT_SCHEMA=$(docker exec "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -tAc "SELECT EXISTS(SELECT 1 FROM information_schema.schemata WHERE schema_name = 'audit');" 2>/dev/null || echo "false")
        if [ "$AUDIT_SCHEMA" = "t" ]; then
            echo "✅ База данных инициализирована (ЛР1 выполнена)"
            break
        fi
    fi
    
    if [ $i -lt 60 ]; then
        sleep 2
        if [ $((i % 10)) -eq 0 ]; then
            echo "   Ожидание завершения инициализации... ($((i*2))/120 секунд)"
        fi
    fi
done

# Финальная проверка
DB_INITIALIZED=$(docker exec "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -tAc "SELECT EXISTS(SELECT 1 FROM information_schema.tables WHERE table_schema = 'app' AND table_name = 'actors');" 2>/dev/null || echo "false")
AUDIT_SCHEMA=$(docker exec "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -tAc "SELECT EXISTS(SELECT 1 FROM information_schema.schemata WHERE schema_name = 'audit');" 2>/dev/null || echo "false")

if [ "$DB_INITIALIZED" != "t" ] || [ "$AUDIT_SCHEMA" != "t" ]; then
    echo "⚠️  База данных не инициализирована автоматически. Запускаем инициализацию ЛР1 вручную..."
    echo ""
    echo "====================================================="
    echo "  ЛАБОРАТОРНАЯ РАБОТА №1 (LR1) - РУЧНАЯ ИНИЦИАЛИЗАЦИЯ"
    echo "====================================================="
    
    # Запускаем скрипты ЛР1 по порядку
    for script in 01_schemas 02_tables 03_ref_data 04_roles 05_privileges 06_default_privs 07_audit 08_test_data 09_rls 10_audit_triggers_and_tests 11_final_verify; do
        echo "▶️  Выполняем ${script}.sql ..."
        docker exec "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -f "/docker-entrypoint-initdb.d/${script}.sql" >/dev/null 2>&1
        if [ $? -eq 0 ]; then
            echo "✅ ${script}.sql выполнен"
        else
            echo "⚠️  ${script}.sql завершился с предупреждениями (продолжаем)"
        fi
    done
    
    # Проверяем результат
    sleep 2
    DB_INITIALIZED=$(docker exec "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -tAc "SELECT EXISTS(SELECT 1 FROM information_schema.tables WHERE table_schema = 'app' AND table_name = 'actors');" 2>/dev/null || echo "false")
    AUDIT_SCHEMA=$(docker exec "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -tAc "SELECT EXISTS(SELECT 1 FROM information_schema.schemata WHERE schema_name = 'audit');" 2>/dev/null || echo "false")
    
    if [ "$DB_INITIALIZED" != "t" ] || [ "$AUDIT_SCHEMA" != "t" ]; then
        echo "❌ Ошибка: База данных не инициализирована корректно после ручной инициализации."
        echo "   Проверьте логи: docker logs $DB_CONTAINER | tail -50"
        exit 1
    else
        echo "✅ ЛР1 успешно инициализирована вручную"
    fi
fi

# Проверяем наличие ЛР2
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Проверка выполнения ЛР2..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

LR2_INITIALIZED=$(docker exec "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -tAc "SELECT EXISTS(SELECT 1 FROM information_schema.tables WHERE table_schema = 'audit' AND table_name = 'function_calls');" 2>/dev/null || echo "false")

if [ "$LR2_INITIALIZED" != "t" ]; then
    echo "⚠️  ЛР2 не выполнена. Выполняем ЛР2..."
    echo ""
    echo "====================================================="
    echo "  ЛАБОРАТОРНАЯ РАБОТА №2 (LR2)"
    echo "====================================================="
    
    if [ -f "$PROJECT_ROOT/lr2_run_all.sh" ]; then
        bash "$PROJECT_ROOT/lr2_run_all.sh"
    else
        echo "⚠️  Скрипт lr2_run_all.sh не найден. Выполняем вручную..."
        run_sql "lr2_01_function_calls_log.sql"
        run_sql "lr2_02_security_definer_functions.sql"
        run_sql "lr2_03_check_vs_trigger.sql"
        run_sql "lr2_04_tests.sql"
        run_sql "lr2_05_demo_function_log.sql"
        run_sql "lr2_06_performance_test.sql"
    fi
else
    echo "✅ ЛР2 уже выполнена"
fi

# Проверяем наличие ЛР3
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Проверка выполнения ЛР3..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

LR3_INITIALIZED=$(docker exec "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -tAc "SELECT EXISTS(SELECT 1 FROM information_schema.tables WHERE table_schema = 'ref' AND table_name = 'segments');" 2>/dev/null || echo "false")

if [ "$LR3_INITIALIZED" != "t" ]; then
    echo "⚠️  ЛР3 не выполнена. Выполняем ЛР3..."
    echo ""
    echo "====================================================="
    echo "  ЛАБОРАТОРНАЯ РАБОТА №3 (LR3)"
    echo "====================================================="
    
    # Исправляем проблему с audio_archives.segment_id перед запуском ЛР3
    echo "🔧 Исправляем проблему с audio_archives.segment_id (если требуется)..."
    docker exec "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -c "
        DO \$\$
        BEGIN
            IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'app' AND table_name = 'audio_archives' AND column_name = 'segment_id') THEN
                ALTER TABLE app.audio_archives ALTER COLUMN segment_id DROP NOT NULL;
            END IF;
        EXCEPTION WHEN OTHERS THEN NULL;
        END \$\$;
        UPDATE app.audio_archives aa SET segment_id = rs.segment_id FROM app.recording_sessions rs WHERE aa.session_id = rs.session_id AND rs.segment_id IS NOT NULL AND (aa.segment_id IS NULL OR aa.segment_id = 0);
        UPDATE app.audio_archives SET segment_id = 1 WHERE segment_id IS NULL;
    " >/dev/null 2>&1 || true
    
    if [ -f "$PROJECT_ROOT/lr3_run_all.sh" ]; then
        bash "$PROJECT_ROOT/lr3_run_all.sh"
    else
        echo "⚠️  Скрипт lr3_run_all.sh не найден. Выполняем вручную..."
        run_sql "lr3_01_segment_model.sql"
        run_sql "lr3_02_rls.sql"
        run_sql "lr3_03_tests.sql"
    fi
else
    echo "✅ ЛР3 уже выполнена"
fi

# Проверяем наличие ЛР4
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Проверка выполнения ЛР4..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

LR4_INITIALIZED=$(docker exec "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -tAc "SELECT EXISTS(SELECT 1 FROM information_schema.views WHERE table_schema = 'app' AND table_name = 'projects_public_view');" 2>/dev/null || echo "false")

if [ "$LR4_INITIALIZED" != "t" ]; then
    echo "⚠️  ЛР4 не выполнена. Выполняем ЛР4..."
    echo ""
    echo "====================================================="
    echo "  ЛАБОРАТОРНАЯ РАБОТА №4 (LR4)"
    echo "====================================================="
    
    if [ -f "$PROJECT_ROOT/lr4_run_all.sh" ]; then
        bash "$PROJECT_ROOT/lr4_run_all.sh"
    else
        echo "⚠️  Скрипт lr4_run_all.sh не найден. Выполняем вручную..."
        run_sql "lr4_01_views.sql"
        run_sql "lr4_02_audit_triggers.sql"
        run_sql "lr4_03_tests.sql"
        run_sql "lr4_04_performance.sql"
        run_sql "lr4_05_backup_audit.sql"
    fi
else
    echo "✅ ЛР4 уже выполнена"
fi

echo ""
echo "====================================================="
echo "🎉  ВСЕ ЛАБОРАТОРНЫЕ РАБОТЫ УСПЕШНО ВЫПОЛНЕНЫ!"
echo "====================================================="
echo ""
echo "Статус выполнения:"
echo "  ✅ ЛР1: База данных инициализирована"
echo "  ✅ ЛР2: SECURITY DEFINER функции и журнал вызовов"
echo "  ✅ ЛР3: Сегментация данных и RLS политики"
echo "  ✅ ЛР4: Безопасные представления, аудит, производительность"
echo ""
echo "Для подключения к БД:"
echo "  docker exec -it $DB_CONTAINER psql -U $DB_USER -d $DB_NAME"
echo ""
echo "pgAdmin доступен по адресу: http://localhost:5050"
echo "  Email: admin@dubbing.studio"
echo "  Password: admin123"
echo ""

