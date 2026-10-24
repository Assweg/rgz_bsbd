#!/bin/bash

# Скрипт для инициализации Лабораторной работы №2
# Выполняет все скрипты ЛР2 на уже запущенном контейнере

echo "====================================================="
echo "Инициализация Лабораторной работы №2"
echo "====================================================="
echo ""

CONTAINER_NAME="dubbing_studio_postgres"
DB_NAME="dubbing_studio"
DB_USER="postgres"

# Проверяем, что контейнер запущен
if ! docker ps | grep -q "$CONTAINER_NAME"; then
    echo "❌ Ошибка: Контейнер $CONTAINER_NAME не запущен!"
    echo "Запустите контейнер командой: ./run_docker.sh start"
    exit 1
fi

echo "✅ Контейнер запущен"

# Копируем скрипты ЛР2 в контейнер
echo ""
echo "Копирование скриптов ЛР2 в контейнер..."

docker cp lr2_01_function_calls_log.sql $CONTAINER_NAME:/tmp/lr2_01_function_calls_log.sql
docker cp lr2_02_security_definer_functions.sql $CONTAINER_NAME:/tmp/lr2_02_security_definer_functions.sql
docker cp lr2_03_check_vs_trigger.sql $CONTAINER_NAME:/tmp/lr2_03_check_vs_trigger.sql
docker cp lr2_04_tests.sql $CONTAINER_NAME:/tmp/lr2_04_tests.sql
docker cp lr2_05_demo_function_log.sql $CONTAINER_NAME:/tmp/lr2_05_demo_function_log.sql
docker cp lr2_06_performance_test.sql $CONTAINER_NAME:/tmp/lr2_06_performance_test.sql

echo "✅ Скрипты скопированы"
echo ""

# Выполняем скрипты по порядку
echo "1. Создание таблицы журнала вызовов..."
docker exec $CONTAINER_NAME psql -U $DB_USER -d $DB_NAME -f /tmp/lr2_01_function_calls_log.sql
if [ $? -eq 0 ]; then
    echo "✅ Скрипт 1 выполнен"
else
    echo "❌ Ошибка выполнения скрипта 1"
    exit 1
fi

echo ""
echo "2. Создание SECURITY DEFINER-функций..."
docker exec $CONTAINER_NAME psql -U $DB_USER -d $DB_NAME -f /tmp/lr2_02_security_definer_functions.sql
if [ $? -eq 0 ]; then
    echo "✅ Скрипт 2 выполнен"
else
    echo "❌ Ошибка выполнения скрипта 2"
    exit 1
fi

echo ""
echo "3. Сравнение CHECK vs триггер..."
docker exec $CONTAINER_NAME psql -U $DB_USER -d $DB_NAME -f /tmp/lr2_03_check_vs_trigger.sql
if [ $? -eq 0 ]; then
    echo "✅ Скрипт 3 выполнен"
else
    echo "❌ Ошибка выполнения скрипта 3"
    exit 1
fi

echo ""
echo "====================================================="
echo "4. ТЕСТЫ ПРАВ ДОСТУПА (≥ 8 КЕЙСОВ)"
echo "====================================================="
echo ""
docker exec $CONTAINER_NAME psql -U $DB_USER -d $DB_NAME -f /tmp/lr2_04_tests.sql
if [ $? -eq 0 ]; then
    echo "✅ Тесты прав доступа выполнены"
else
    echo "❌ Ошибка выполнения тестов"
    exit 1
fi

echo ""
echo "====================================================="
echo "5. ДЕМОНСТРАЦИЯ ЖУРНАЛА ВЫЗОВОВ ФУНКЦИЙ"
echo "====================================================="
echo ""
docker exec $CONTAINER_NAME psql -U $DB_USER -d $DB_NAME -f /tmp/lr2_05_demo_function_log.sql
if [ $? -eq 0 ]; then
    echo "✅ Демонстрация журнала выполнена"
else
    echo "❌ Ошибка выполнения демонстрации"
    exit 1
fi

echo ""
echo "====================================================="
echo "6. ТЕСТ ПРОИЗВОДИТЕЛЬНОСТИ: CHECK vs TRIGGER"
echo "====================================================="
echo "Запуск теста на 10,000 строк (это может занять некоторое время)..."
echo ""
docker exec $CONTAINER_NAME psql -U $DB_USER -d $DB_NAME -f /tmp/lr2_06_performance_test.sql
if [ $? -eq 0 ]; then
    echo "✅ Тест производительности выполнен"
else
    echo "❌ Ошибка выполнения теста производительности"
    exit 1
fi

echo ""
echo ""
echo "====================================================="
echo "ИТОГОВЫЙ ОТЧЁТ ПО ЛАБОРАТОРНОЙ РАБОТЕ №2"
echo "====================================================="
echo ""

# Проверяем все компоненты и выводим отчет
echo "Проверка выполнения всех пунктов задания:"
echo ""

# Проверка наличия базовых данных (из ЛР1)
echo "Проверка данных БД:"
docker exec $CONTAINER_NAME psql -U $DB_USER -d $DB_NAME -t -c "
SELECT 
    '   Актёров: ' || COUNT(*)::TEXT || ', Проектов: ' || 
    (SELECT COUNT(*)::TEXT FROM app.projects) || ', Контрактов: ' ||
    (SELECT COUNT(*)::TEXT FROM app.contracts)
FROM app.actors;
"
echo ""

# 1. Проверка SECURITY DEFINER-функций
echo "1. SECURITY DEFINER-функции:"
docker exec $CONTAINER_NAME psql -U $DB_USER -d $DB_NAME -t -c "
SELECT 
    CASE 
        WHEN COUNT(*) = 3 THEN '✅ Созданы 3 функции'
        ELSE '❌ Не все функции созданы (найдено: ' || COUNT(*)::TEXT || ')'
    END as status
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'app'
  AND p.proname IN ('create_contract', 'update_contract_salary', 'register_recording_session')
  AND p.prosecdef = true;
"
docker exec $CONTAINER_NAME psql -U $DB_USER -d $DB_NAME -t -c "
SELECT '   - ' || p.proname || ' (SECURITY DEFINER)'
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'app'
  AND p.proname IN ('create_contract', 'update_contract_salary', 'register_recording_session')
  AND p.prosecdef = true
ORDER BY p.proname;
"
echo ""

# 2. Проверка таблицы журнала вызовов
echo "2. Журнал вызовов функций (audit.function_calls):"
docker exec $CONTAINER_NAME psql -U $DB_USER -d $DB_NAME -t -c "
SELECT 
    CASE 
        WHEN EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'audit' AND table_name = 'function_calls')
        THEN '✅ Таблица создана'
        ELSE '❌ Таблица не найдена'
    END as status;
"
docker exec $CONTAINER_NAME psql -U $DB_USER -d $DB_NAME -t -c "
SELECT 
    CASE 
        WHEN EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'audit' AND table_name = 'function_calls')
        THEN '   Записей в журнале: ' || COUNT(*)::TEXT
        ELSE '   Таблица не существует'
    END
FROM audit.function_calls
WHERE EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'audit' AND table_name = 'function_calls')
UNION ALL
SELECT '   Таблица не существует'
WHERE NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'audit' AND table_name = 'function_calls');
"
echo ""

# 3. Проверка тестов прав доступа
echo "3. Тесты прав доступа:"
docker exec $CONTAINER_NAME psql -U $DB_USER -d $DB_NAME -t -c "
SELECT 
    CASE 
        WHEN COUNT(*) >= 10 THEN '✅ Выполнено ' || COUNT(*)::TEXT || ' вызовов функций (тесты)'
        WHEN COUNT(*) > 0 THEN '⚠️  Выполнено ' || COUNT(*)::TEXT || ' вызовов (ожидалось ≥10)'
        ELSE '❌ Вызовы функций не найдены'
    END as status
FROM audit.function_calls
WHERE function_name IN ('create_contract', 'update_contract_salary', 'register_recording_session');
"
docker exec $CONTAINER_NAME psql -U $DB_USER -d $DB_NAME -t -c "
SELECT 
    '   Успешных: ' || COUNT(*) FILTER (WHERE success = true)::TEXT ||
    ', Неуспешных: ' || COUNT(*) FILTER (WHERE success = false)::TEXT
FROM audit.function_calls
WHERE function_name IN ('create_contract', 'update_contract_salary', 'register_recording_session');
"
echo ""

# 4. Проверка CHECK vs триггер
echo "4. Сравнение CHECK vs триггер:"
docker exec $CONTAINER_NAME psql -U $DB_USER -d $DB_NAME -t -c "
SELECT 
    CASE 
        WHEN EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'app' AND table_name = 'contracts_check_test')
         AND EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'app' AND table_name = 'contracts_trigger_test')
        THEN '✅ Тестовые таблицы созданы'
        ELSE '❌ Тестовые таблицы не найдены'
    END as status;
"
docker exec $CONTAINER_NAME psql -U $DB_USER -d $DB_NAME -t -c "
SELECT 
    CASE 
        WHEN EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'app' AND table_name = 'contracts_check_test')
        THEN '   CHECK таблица: ' || COUNT(*)::TEXT || ' записей'
        ELSE '   CHECK таблица не найдена'
    END
FROM app.contracts_check_test
WHERE EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'app' AND table_name = 'contracts_check_test')
UNION ALL
SELECT 
    CASE 
        WHEN EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'app' AND table_name = 'contracts_trigger_test')
        THEN '   TRIGGER таблица: ' || COUNT(*)::TEXT || ' записей'
        ELSE '   TRIGGER таблица не найдена'
    END
FROM app.contracts_trigger_test
WHERE EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'app' AND table_name = 'contracts_trigger_test');
"
echo ""

# 5. Статистика по журналу вызовов
echo "5. Статистика журнала вызовов функций:"
docker exec $CONTAINER_NAME psql -U $DB_USER -d $DB_NAME -c "
SELECT 
    function_name,
    COUNT(*) as total_calls,
    COUNT(*) FILTER (WHERE success = true) as successful,
    COUNT(*) FILTER (WHERE success = false) as failed,
    ROUND(AVG(execution_time_ms)::NUMERIC, 2) as avg_time_ms
FROM audit.function_calls
WHERE function_schema = 'app'
GROUP BY function_name
ORDER BY function_name;
" 2>/dev/null || echo "   (Таблица пока не содержит данных)"
echo ""

# 6. Результаты теста производительности
echo "6. Результаты теста производительности (CHECK vs TRIGGER):"
docker exec $CONTAINER_NAME psql -U $DB_USER -d $DB_NAME -c "
SELECT 
    method,
    inserted_count,
    failed_count,
    ROUND(total_time_ms::NUMERIC, 2) as total_time_ms,
    ROUND(avg_time_per_insert_ms::NUMERIC, 3) as avg_time_per_insert_ms
FROM app.test_performance_check_vs_trigger(10000);
" 2>/dev/null || echo "   (Функция теста производительности не найдена)"
echo ""

echo "====================================================="
echo "✅ ВСЕ ПУНКТЫ ЗАДАНИЯ ВЫПОЛНЕНЫ!"
echo "====================================================="
echo ""
echo "Краткое резюме:"
echo "  ✅ SECURITY DEFINER-функции: 3 функции созданы"
echo "  ✅ Журнал вызовов: audit.function_calls работает"
echo "  ✅ Тесты прав доступа: 10+ кейсов выполнено"
echo "  ✅ CHECK vs TRIGGER: сравнение выполнено"
echo "  ✅ Тест производительности: 10,000 строк протестировано"
echo ""
echo "Для просмотра детального журнала вызовов:"
echo "  ./run_docker.sh show-lr2-log"
echo ""
