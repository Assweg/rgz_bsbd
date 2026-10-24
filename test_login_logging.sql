-- Тест логирования подключений
-- Этот скрипт должен выполняться от имени разных пользователей

\echo '=== ТЕСТ ЛОГИРОВАНИЯ ПОДКЛЮЧЕНИЙ ==='

-- Логируем текущее подключение
SELECT public.auto_log_connection();

-- Показываем текущего пользователя
SELECT 'Текущий пользователь:' as info, current_user as username;

-- Показываем все логи
SELECT 'Логи подключений:' as info, 
       username, 
       client_ip, 
       connection_method, 
       is_successful, 
       login_time
FROM audit.login_log 
ORDER BY login_time DESC 
LIMIT 5;
