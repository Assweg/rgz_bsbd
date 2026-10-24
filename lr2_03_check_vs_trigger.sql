-- =====================================================
-- Сравнение CHECK vs триггер для бизнес-правил
-- =====================================================

-- БИЗНЕС-ПРАВИЛО: 
-- Дата окончания контракта (end_date) должна быть >= даты подписания (signed_date)
-- И если контракт завершён (status = 'completed'), то end_date должна быть <= CURRENT_DATE

-- =====================================================
-- ВАРИАНТ 1: CHECK CONSTRAINT
-- =====================================================

-- Создаём тестовую таблицу с CHECK
CREATE TABLE IF NOT EXISTS app.contracts_check_test (
    contract_id SERIAL PRIMARY KEY,
    contract_number VARCHAR(50) NOT NULL UNIQUE,
    signed_date DATE NOT NULL,
    end_date DATE,
    status VARCHAR(20) DEFAULT 'active',
    -- CHECK ограничение: end_date >= signed_date
    CONSTRAINT chk_end_after_start CHECK (
        end_date IS NULL OR end_date >= signed_date
    ),
    -- CHECK ограничение: если завершён, то end_date <= CURRENT_DATE
    CONSTRAINT chk_completed_end_date CHECK (
        status != 'completed' OR (end_date IS NOT NULL AND end_date <= CURRENT_DATE)
    )
);

COMMENT ON TABLE app.contracts_check_test IS 'Тестовая таблица для проверки CHECK ограничений';

-- =====================================================
-- ВАРИАНТ 2: TRIGGER
-- =====================================================

-- Создаём тестовую таблицу без CHECK (будет проверка через триггер)
CREATE TABLE IF NOT EXISTS app.contracts_trigger_test (
    contract_id SERIAL PRIMARY KEY,
    contract_number VARCHAR(50) NOT NULL UNIQUE,
    signed_date DATE NOT NULL,
    end_date DATE,
    status VARCHAR(20) DEFAULT 'active'
);

COMMENT ON TABLE app.contracts_trigger_test IS 'Тестовая таблица для проверки триггеров';

-- Функция триггера для валидации
CREATE OR REPLACE FUNCTION app.validate_contract_dates()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    -- Проверка: end_date >= signed_date
    IF NEW.end_date IS NOT NULL AND NEW.end_date < NEW.signed_date THEN
        RAISE EXCEPTION 'ОШИБКА ВАЛИДАЦИИ: Дата окончания контракта (%) не может быть раньше даты подписания (%)',
            NEW.end_date, NEW.signed_date;
    END IF;
    
    -- Проверка: если завершён, то end_date <= CURRENT_DATE
    IF NEW.status = 'completed' THEN
        IF NEW.end_date IS NULL THEN
            RAISE EXCEPTION 'ОШИБКА ВАЛИДАЦИИ: Завершённый контракт должен иметь дату окончания';
        END IF;
        IF NEW.end_date > CURRENT_DATE THEN
            RAISE EXCEPTION 'ОШИБКА ВАЛИДАЦИИ: Дата окончания завершённого контракта (%) не может быть в будущем',
                NEW.end_date;
        END IF;
    END IF;
    
    RETURN NEW;
END;
$$;

-- Создаём триггер
DROP TRIGGER IF EXISTS trg_validate_contract_dates ON app.contracts_trigger_test;
CREATE TRIGGER trg_validate_contract_dates
    BEFORE INSERT OR UPDATE ON app.contracts_trigger_test
    FOR EACH ROW
    EXECUTE FUNCTION app.validate_contract_dates();

COMMENT ON FUNCTION app.validate_contract_dates IS 'Триггерная функция для валидации дат контракта';
COMMENT ON TRIGGER trg_validate_contract_dates ON app.contracts_trigger_test IS 'Триггер валидации дат контракта';

-- =====================================================
-- ТЕСТИРОВАНИЕ ПРОИЗВОДИТЕЛЬНОСТИ
-- =====================================================

-- Функция для генерации тестовых данных
CREATE OR REPLACE FUNCTION app.generate_test_contracts(
    p_count INTEGER,
    p_table_name VARCHAR
)
RETURNS TABLE (
    inserted_count INTEGER,
    failed_count INTEGER,
    total_time_ms NUMERIC
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_start_time TIMESTAMPTZ;
    v_end_time TIMESTAMPTZ;
    v_execution_time NUMERIC;
    v_inserted INTEGER := 0;
    v_failed INTEGER := 0;
    v_i INTEGER;
    v_signed_date DATE;
    v_end_date DATE;
    v_status VARCHAR(20);
BEGIN
    v_start_time := clock_timestamp();
    
    FOR v_i IN 1..p_count LOOP
        BEGIN
            -- Генерируем случайные, но валидные данные
            v_signed_date := CURRENT_DATE - (random() * 365)::INTEGER;
            v_end_date := v_signed_date + (random() * 180)::INTEGER;
            
            IF random() > 0.7 THEN
                v_status := 'completed';
                -- Для завершённых контрактов end_date должна быть в прошлом
                IF v_end_date > CURRENT_DATE THEN
                    v_end_date := CURRENT_DATE - (random() * 30)::INTEGER;
                END IF;
            ELSE
                v_status := 'active';
            END IF;
            
            -- Вставляем в соответствующую таблицу
            IF p_table_name = 'check' THEN
                INSERT INTO app.contracts_check_test (
                    contract_number,
                    signed_date,
                    end_date,
                    status
                ) VALUES (
                    'TEST-CHECK-' || v_i,
                    v_signed_date,
                    v_end_date,
                    v_status
                );
            ELSIF p_table_name = 'trigger' THEN
                INSERT INTO app.contracts_trigger_test (
                    contract_number,
                    signed_date,
                    end_date,
                    status
                ) VALUES (
                    'TEST-TRIGGER-' || v_i,
                    v_signed_date,
                    v_end_date,
                    v_status
                );
            END IF;
            
            v_inserted := v_inserted + 1;
            
        EXCEPTION
            WHEN OTHERS THEN
                v_failed := v_failed + 1;
                -- Игнорируем ошибки и продолжаем
        END;
    END LOOP;
    
    v_end_time := clock_timestamp();
    v_execution_time := EXTRACT(EPOCH FROM (v_end_time - v_start_time)) * 1000;
    
    RETURN QUERY SELECT v_inserted, v_failed, v_execution_time;
END;
$$;

-- Функция для тестирования производительности
CREATE OR REPLACE FUNCTION app.test_performance_check_vs_trigger(
    p_test_count INTEGER DEFAULT 10000
)
RETURNS TABLE (
    method VARCHAR,
    inserted_count INTEGER,
    failed_count INTEGER,
    total_time_ms NUMERIC,
    avg_time_per_insert_ms NUMERIC
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_check_result RECORD;
    v_trigger_result RECORD;
BEGIN
    -- Очищаем тестовые таблицы
    TRUNCATE TABLE app.contracts_check_test;
    TRUNCATE TABLE app.contracts_trigger_test;
    
    -- Тест CHECK
    SELECT * INTO v_check_result
    FROM app.generate_test_contracts(p_test_count, 'check');
    
    -- Тест TRIGGER
    SELECT * INTO v_trigger_result
    FROM app.generate_test_contracts(p_test_count, 'trigger');
    
    -- Возвращаем результаты
    RETURN QUERY
    SELECT 
        'CHECK'::VARCHAR as method,
        v_check_result.inserted_count,
        v_check_result.failed_count,
        v_check_result.total_time_ms,
        CASE 
            WHEN v_check_result.inserted_count > 0 
            THEN v_check_result.total_time_ms / v_check_result.inserted_count
            ELSE 0
        END as avg_time_per_insert_ms
    UNION ALL
    SELECT 
        'TRIGGER'::VARCHAR as method,
        v_trigger_result.inserted_count,
        v_trigger_result.failed_count,
        v_trigger_result.total_time_ms,
        CASE 
            WHEN v_trigger_result.inserted_count > 0 
            THEN v_trigger_result.total_time_ms / v_trigger_result.inserted_count
            ELSE 0
        END as avg_time_per_insert_ms;
END;
$$;

-- Даём права на тестовые таблицы
GRANT SELECT, INSERT ON app.contracts_check_test TO app_owner;
GRANT SELECT, INSERT ON app.contracts_trigger_test TO app_owner;
GRANT EXECUTE ON FUNCTION app.generate_test_contracts TO app_owner;
GRANT EXECUTE ON FUNCTION app.test_performance_check_vs_trigger TO app_owner;

COMMENT ON FUNCTION app.generate_test_contracts IS 'Генерация тестовых данных для сравнения CHECK vs триггер';
COMMENT ON FUNCTION app.test_performance_check_vs_trigger IS 'Тест производительности CHECK vs триггер на заданном количестве строк';

-- Уведомление
DO $$ 
BEGIN
    RAISE NOTICE '✅ Тестовые таблицы и функции для сравнения CHECK vs триггер созданы';
    RAISE NOTICE '   Для запуска теста выполните: SELECT * FROM app.test_performance_check_vs_trigger(10000);';
END $$;