-- =====================================================
-- SECURITY DEFINER-функции для чувствительных операций
-- =====================================================

-- Устанавливаем роль для создания функций
SET ROLE app_owner;

-- =====================================================
-- ФУНКЦИЯ 1: create_contract
-- Создание контракта с актёром (чувствительная операция)
-- =====================================================

CREATE OR REPLACE FUNCTION app.create_contract(
    p_project_id INTEGER,
    p_actor_id INTEGER,
    p_contract_number VARCHAR(50),
    p_role_description TEXT,
    p_salary_amount DECIMAL(10,2),
    p_currency VARCHAR(3) DEFAULT 'USD',
    p_terms TEXT DEFAULT NULL,
    p_signed_date DATE DEFAULT CURRENT_DATE,
    p_end_date DATE DEFAULT NULL
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = app, ref, audit, public
AS $$
DECLARE
    v_start_time TIMESTAMPTZ;
    v_end_time TIMESTAMPTZ;
    v_execution_time NUMERIC;
    v_contract_id INTEGER;
    v_input_params JSONB;
    v_return_value JSONB;
BEGIN
    -- Засекаем время выполнения
    v_start_time := clock_timestamp();
    
    -- Формируем JSON с параметрами для логирования
    v_input_params := jsonb_build_object(
        'project_id', p_project_id,
        'actor_id', p_actor_id,
        'contract_number', p_contract_number,
        'role_description', p_role_description,
        'salary_amount', p_salary_amount,
        'currency', p_currency
    );
    
    -- ВАЛИДАЦИЯ ВХОДНЫХ ДАННЫХ
    
    -- Проверка существования проекта
    IF NOT EXISTS (SELECT 1 FROM app.projects WHERE project_id = p_project_id) THEN
        PERFORM audit.log_function_call(
            'app', 'create_contract',
            v_input_params,
            NULL,
            false,
            'ОШИБКА: Проект с ID ' || p_project_id || ' не существует',
            NULL
        );
        RAISE EXCEPTION 'Проект с ID % не существует', p_project_id;
    END IF;
    
    -- Проверка существования актёра
    IF NOT EXISTS (SELECT 1 FROM app.actors WHERE actor_id = p_actor_id AND is_active = true) THEN
        PERFORM audit.log_function_call(
            'app', 'create_contract',
            v_input_params,
            NULL,
            false,
            'ОШИБКА: Актёр с ID ' || p_actor_id || ' не существует или неактивен',
            NULL
        );
        RAISE EXCEPTION 'Актёр с ID % не существует или неактивен', p_actor_id;
    END IF;
    
    -- Проверка уникальности номера контракта
    IF EXISTS (SELECT 1 FROM app.contracts WHERE contract_number = p_contract_number) THEN
        PERFORM audit.log_function_call(
            'app', 'create_contract',
            v_input_params,
            NULL,
            false,
            'ОШИБКА: Контракт с номером ' || p_contract_number || ' уже существует',
            NULL
        );
        RAISE EXCEPTION 'Контракт с номером % уже существует', p_contract_number;
    END IF;
    
    -- Проверка суммы контракта
    IF p_salary_amount IS NULL OR p_salary_amount <= 0 THEN
        PERFORM audit.log_function_call(
            'app', 'create_contract',
            v_input_params,
            NULL,
            false,
            'ОШИБКА: Сумма контракта должна быть положительным числом',
            NULL
        );
        RAISE EXCEPTION 'Сумма контракта должна быть положительным числом';
    END IF;
    
    -- Проверка дат (end_date должен быть после signed_date)
    IF p_end_date IS NOT NULL AND p_signed_date IS NOT NULL AND p_end_date < p_signed_date THEN
        PERFORM audit.log_function_call(
            'app', 'create_contract',
            v_input_params,
            NULL,
            false,
            'ОШИБКА: Дата окончания контракта не может быть раньше даты подписания',
            NULL
        );
        RAISE EXCEPTION 'Дата окончания контракта не может быть раньше даты подписания';
    END IF;
    
    -- Проверка обязательных полей
    IF p_contract_number IS NULL OR trim(p_contract_number) = '' THEN
        PERFORM audit.log_function_call(
            'app', 'create_contract',
            v_input_params,
            NULL,
            false,
            'ОШИБКА: Номер контракта обязателен для заполнения',
            NULL
        );
        RAISE EXCEPTION 'Номер контракта обязателен для заполнения';
    END IF;
    
    IF p_role_description IS NULL OR trim(p_role_description) = '' THEN
        PERFORM audit.log_function_call(
            'app', 'create_contract',
            v_input_params,
            NULL,
            false,
            'ОШИБКА: Описание роли обязательно для заполнения',
            NULL
        );
        RAISE EXCEPTION 'Описание роли обязательно для заполнения';
    END IF;
    
    -- СОЗДАНИЕ КОНТРАКТА
    INSERT INTO app.contracts (
        project_id,
        actor_id,
        contract_number,
        role_description,
        salary_amount,
        currency,
        terms,
        signed_date,
        end_date,
        status
    ) VALUES (
        p_project_id,
        p_actor_id,
        p_contract_number,
        p_role_description,
        p_salary_amount,
        p_currency,
        p_terms,
        p_signed_date,
        p_end_date,
        'active'
    )
    RETURNING contract_id INTO v_contract_id;
    
    -- Формируем возвращаемое значение для логирования
    v_return_value := jsonb_build_object('contract_id', v_contract_id);
    
    -- Вычисляем время выполнения
    v_end_time := clock_timestamp();
    v_execution_time := EXTRACT(EPOCH FROM (v_end_time - v_start_time)) * 1000;
    
    -- ЛОГИРОВАНИЕ УСПЕШНОГО ВЫЗОВА
    PERFORM audit.log_function_call(
        'app', 'create_contract',
        v_input_params,
        v_return_value,
        true,
        NULL,
        v_execution_time
    );
    
    RETURN v_contract_id;
    
EXCEPTION
    WHEN OTHERS THEN
        -- Вычисляем время выполнения при ошибке
        v_end_time := clock_timestamp();
        v_execution_time := EXTRACT(EPOCH FROM (v_end_time - v_start_time)) * 1000;
        
        -- ЛОГИРОВАНИЕ ОШИБКИ
        PERFORM audit.log_function_call(
            'app', 'create_contract',
            v_input_params,
            NULL,
            false,
            'ОШИБКА: ' || SQLERRM,
            v_execution_time
        );
        
        -- Пробрасываем ошибку дальше
        RAISE;
END;
$$;

-- =====================================================
-- ФУНКЦИЯ 2: update_contract_salary
-- Обновление зарплаты в контракте (конфиденциальные данные)
-- =====================================================

CREATE OR REPLACE FUNCTION app.update_contract_salary(
    p_contract_id INTEGER,
    p_new_salary_amount DECIMAL(10,2),
    p_reason TEXT DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = app, ref, audit, public
AS $$
DECLARE
    v_start_time TIMESTAMPTZ;
    v_end_time TIMESTAMPTZ;
    v_execution_time NUMERIC;
    v_old_salary DECIMAL(10,2);
    v_input_params JSONB;
    v_return_value JSONB;
BEGIN
    v_start_time := clock_timestamp();
    
    -- Формируем JSON с параметрами
    v_input_params := jsonb_build_object(
        'contract_id', p_contract_id,
        'new_salary_amount', p_new_salary_amount,
        'reason', p_reason
    );
    
    -- ВАЛИДАЦИЯ
    
    -- Проверка существования контракта
    SELECT salary_amount INTO v_old_salary
    FROM app.contracts
    WHERE contract_id = p_contract_id;
    
    IF NOT FOUND THEN
        PERFORM audit.log_function_call(
            'app', 'update_contract_salary',
            v_input_params,
            NULL,
            false,
            'ОШИБКА: Контракт с ID ' || p_contract_id || ' не найден',
            NULL
        );
        RAISE EXCEPTION 'Контракт с ID % не найден', p_contract_id;
    END IF;
    
    -- Проверка суммы
    IF p_new_salary_amount IS NULL OR p_new_salary_amount <= 0 THEN
        PERFORM audit.log_function_call(
            'app', 'update_contract_salary',
            v_input_params,
            NULL,
            false,
            'ОШИБКА: Новая сумма должна быть положительным числом',
            NULL
        );
        RAISE EXCEPTION 'Новая сумма должна быть положительным числом';
    END IF;
    
    -- Проверка, что сумма изменилась
    IF p_new_salary_amount = v_old_salary THEN
        PERFORM audit.log_function_call(
            'app', 'update_contract_salary',
            v_input_params,
            NULL,
            false,
            'ОШИБКА: Новая сумма совпадает со старой',
            NULL
        );
        RAISE EXCEPTION 'Новая сумма совпадает со старой (%.2f)', v_old_salary;
    END IF;
    
    -- Проверка статуса контракта
    IF EXISTS (
        SELECT 1 FROM app.contracts 
        WHERE contract_id = p_contract_id 
        AND status IN ('cancelled', 'completed')
    ) THEN
        PERFORM audit.log_function_call(
            'app', 'update_contract_salary',
            v_input_params,
            NULL,
            false,
            'ОШИБКА: Нельзя изменить зарплату в завершённом или отменённом контракте',
            NULL
        );
        RAISE EXCEPTION 'Нельзя изменить зарплату в завершённом или отменённом контракте';
    END IF;
    
    -- ОБНОВЛЕНИЕ ЗАРПЛАТЫ
    UPDATE app.contracts
    SET 
        salary_amount = p_new_salary_amount
    WHERE contract_id = p_contract_id;
    
    -- Формируем возвращаемое значение
    v_return_value := jsonb_build_object(
        'contract_id', p_contract_id,
        'old_salary', v_old_salary,
        'new_salary', p_new_salary_amount,
        'updated', true
    );
    
    -- Вычисляем время выполнения
    v_end_time := clock_timestamp();
    v_execution_time := EXTRACT(EPOCH FROM (v_end_time - v_start_time)) * 1000;
    
    -- ЛОГИРОВАНИЕ
    PERFORM audit.log_function_call(
        'app', 'update_contract_salary',
        v_input_params,
        v_return_value,
        true,
        NULL,
        v_execution_time
    );
    
    RETURN true;
    
EXCEPTION
    WHEN OTHERS THEN
        v_end_time := clock_timestamp();
        v_execution_time := EXTRACT(EPOCH FROM (v_end_time - v_start_time)) * 1000;
        
        PERFORM audit.log_function_call(
            'app', 'update_contract_salary',
            v_input_params,
            NULL,
            false,
            'ОШИБКА: ' || SQLERRM,
            v_execution_time
        );
        
        RAISE;
END;
$$;

-- =====================================================
-- ФУНКЦИЯ 3: register_recording_session
-- Регистрация сессии записи (бизнес-транзакция)
-- =====================================================

CREATE OR REPLACE FUNCTION app.register_recording_session(
    p_contract_id INTEGER,
    p_session_date DATE,
    p_session_time TIME,
    p_studio_location VARCHAR(100),
    p_duration_hours DECIMAL(4,2),
    p_notes TEXT DEFAULT NULL
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = app, ref, audit, public
AS $$
DECLARE
    v_start_time TIMESTAMPTZ;
    v_end_time TIMESTAMPTZ;
    v_execution_time NUMERIC;
    v_session_id INTEGER;
    v_contract_status VARCHAR(20);
    v_input_params JSONB;
    v_return_value JSONB;
BEGIN
    v_start_time := clock_timestamp();
    
    -- Формируем JSON с параметрами
    v_input_params := jsonb_build_object(
        'contract_id', p_contract_id,
        'session_date', p_session_date,
        'session_time', p_session_time,
        'studio_location', p_studio_location,
        'duration_hours', p_duration_hours
    );
    
    -- ВАЛИДАЦИЯ
    
    -- Проверка существования контракта
    SELECT status INTO v_contract_status
    FROM app.contracts
    WHERE contract_id = p_contract_id;
    
    IF NOT FOUND THEN
        PERFORM audit.log_function_call(
            'app', 'register_recording_session',
            v_input_params,
            NULL,
            false,
            'ОШИБКА: Контракт с ID ' || p_contract_id || ' не найден',
            NULL
        );
        RAISE EXCEPTION 'Контракт с ID % не найден', p_contract_id;
    END IF;
    
    -- Проверка статуса контракта
    IF v_contract_status != 'active' THEN
        PERFORM audit.log_function_call(
            'app', 'register_recording_session',
            v_input_params,
            NULL,
            false,
            'ОШИБКА: Контракт должен быть активным (текущий статус: ' || v_contract_status || ')',
            NULL
        );
        RAISE EXCEPTION 'Контракт должен быть активным (текущий статус: %)', v_contract_status;
    END IF;
    
    -- Проверка даты сессии (не должна быть в прошлом более чем на 1 день)
    IF p_session_date < CURRENT_DATE - INTERVAL '1 day' THEN
        PERFORM audit.log_function_call(
            'app', 'register_recording_session',
            v_input_params,
            NULL,
            false,
            'ОШИБКА: Дата сессии не может быть в прошлом более чем на 1 день',
            NULL
        );
        RAISE EXCEPTION 'Дата сессии не может быть в прошлом более чем на 1 день';
    END IF;
    
    -- Проверка длительности
    IF p_duration_hours IS NULL OR p_duration_hours <= 0 OR p_duration_hours > 24 THEN
        PERFORM audit.log_function_call(
            'app', 'register_recording_session',
            v_input_params,
            NULL,
            false,
            'ОШИБКА: Длительность сессии должна быть от 0 до 24 часов',
            NULL
        );
        RAISE EXCEPTION 'Длительность сессии должна быть от 0 до 24 часов';
    END IF;
    
    -- Проверка обязательных полей
    IF p_studio_location IS NULL OR trim(p_studio_location) = '' THEN
        PERFORM audit.log_function_call(
            'app', 'register_recording_session',
            v_input_params,
            NULL,
            false,
            'ОШИБКА: Место проведения сессии обязательно для заполнения',
            NULL
        );
        RAISE EXCEPTION 'Место проведения сессии обязательно для заполнения';
    END IF;
    
    -- СОЗДАНИЕ СЕССИИ
    INSERT INTO app.recording_sessions (
        contract_id,
        session_date,
        session_time,
        studio_location,
        duration_hours,
        notes,
        status
    ) VALUES (
        p_contract_id,
        p_session_date,
        p_session_time,
        p_studio_location,
        p_duration_hours,
        p_notes,
        'scheduled'
    )
    RETURNING session_id INTO v_session_id;
    
    -- Формируем возвращаемое значение
    v_return_value := jsonb_build_object(
        'session_id', v_session_id,
        'contract_id', p_contract_id,
        'session_date', p_session_date,
        'status', 'scheduled'
    );
    
    -- Вычисляем время выполнения
    v_end_time := clock_timestamp();
    v_execution_time := EXTRACT(EPOCH FROM (v_end_time - v_start_time)) * 1000;
    
    -- ЛОГИРОВАНИЕ
    PERFORM audit.log_function_call(
        'app', 'register_recording_session',
        v_input_params,
        v_return_value,
        true,
        NULL,
        v_execution_time
    );
    
    RETURN v_session_id;
    
EXCEPTION
    WHEN OTHERS THEN
        v_end_time := clock_timestamp();
        v_execution_time := EXTRACT(EPOCH FROM (v_end_time - v_start_time)) * 1000;
        
        PERFORM audit.log_function_call(
            'app', 'register_recording_session',
            v_input_params,
            NULL,
            false,
            'ОШИБКА: ' || SQLERRM,
            v_execution_time
        );
        
        RAISE;
END;
$$;

-- Сбрасываем роль
RESET ROLE;

-- Даём доступ к функциям нужным ролям
GRANT EXECUTE ON FUNCTION app.create_contract TO app_writer, studio_manager;
GRANT EXECUTE ON FUNCTION app.update_contract_salary TO app_writer, studio_manager;
GRANT EXECUTE ON FUNCTION app.register_recording_session TO app_writer, studio_manager;

-- Комментарии к функциям
COMMENT ON FUNCTION app.create_contract IS 'SECURITY DEFINER: Создание контракта с актёром. Валидирует входные данные и логирует операцию';
COMMENT ON FUNCTION app.update_contract_salary IS 'SECURITY DEFINER: Обновление зарплаты в контракте. Проверяет права и статус контракта';
COMMENT ON FUNCTION app.register_recording_session IS 'SECURITY DEFINER: Регистрация сессии записи. Валидирует контракт и параметры сессии';

-- Уведомление
DO $$ 
BEGIN
    RAISE NOTICE '✅ SECURITY DEFINER-функции успешно созданы:';
    RAISE NOTICE '   - app.create_contract';
    RAISE NOTICE '   - app.update_contract_salary';
    RAISE NOTICE '   - app.register_recording_session';
END $$;