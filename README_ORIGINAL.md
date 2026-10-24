# База данных студии дубляжа

Система управления доступом к авторским материалам, контрактам с актёрами, расписаниям записей и защищённым архивам аудиофайлов.

## Архитектура

### Схемы данных
- **app** - основные бизнес-данные (актёры, проекты, контракты, сессии записи, аудиоархивы)
- **ref** - справочники (языки, студии)
- **audit** - аудит и логи безопасности
- **stg** - временная/служебная область

### Роли и разделение обязанностей
- **app_owner** - владелец приложения (полный доступ к бизнес-данным)
- **app_reader** - чтение бизнес-данных
- **app_writer** - запись бизнес-данных
- **auditor** - доступ к логам безопасности только на чтение
- **ddl_admin** - администратор DDL (создание/изменение таблиц, индексов)
- **dml_admin** - администратор DML (массовые операции)
- **security_admin** - администратор безопасности (RLS, политики, шифрование)

### Пользователи для тестирования
- **studio_manager** (manager_pass123) - менеджер студии
- **voice_actor** (actor_pass123) - актёр озвучивания
- **security_auditor** (auditor_pass123) - аудитор безопасности
- **app_owner_user** (owner_pass123) - владелец системы

## Развёртывание

### Через Docker (рекомендуется)

#### Быстрый запуск
```bash
# Запуск контейнера и инициализация БД
./run_docker.sh start

# Подключение к БД
./run_docker.sh connect

# Просмотр логов
./run_docker.sh logs

# Запуск тестов
./run_docker.sh test

# Остановка
./run_docker.sh stop
```

#### Ручная инициализация (если нужно)
```bash
# Если контейнер уже запущен, но БД не инициализирована
./run_docker.sh init
```

#### Ручной запуск
```bash
# Сборка и запуск
docker-compose up -d

# Подключение к БД
docker exec -it dubbing_studio_postgres psql -U postgres -d dubbing_studio

# Остановка
docker-compose down
```

#### Параметры подключения к PostgreSQL
- **Host**: localhost
- **Port**: 5432
- **Database**: dubbing_studio
- **User**: postgres
- **Password**: secure_password_123

#### pgAdmin (веб-интерфейс)
После запуска контейнеров pgAdmin доступен по адресу: **http://localhost:5050**

**Учетные данные для входа:**
- **Email**: `admin@dubbing.studio`
- **Password**: `admin123`

### Проверка подключения pgAdmin к БД

Для проверки, что pgAdmin может подключиться к базе данных, выполните:

```bash
bash check_pgadmin_connection.sh
```

Этот скрипт проверит:
- ✅ Статус контейнеров (PostgreSQL и pgAdmin)
- ✅ Сетевое подключение между контейнерами
- ✅ Доступность порта PostgreSQL
- ✅ Доступность pgAdmin через HTTP
- ✅ Подключение к базе данных

### Параметры подключения к серверу БД в pgAdmin

После входа в pgAdmin, для подключения к серверу БД используйте:

- **Host name/address**: `dubbing-studio-db` ⚠️ **ВАЖНО: Используйте имя сервиса Docker, НЕ localhost!**
- **Port**: `5432`
- **Maintenance database**: `dubbing_studio`
- **Username**: `postgres`
- **Password**: `secure_password_123`

Подробная инструкция по подключению: см. [PGADMIN_CONNECTION_GUIDE.md](PGADMIN_CONNECTION_GUIDE.md)

**Для подключения к базе данных в pgAdmin:**
1. После входа в pgAdmin, щёлкните правой кнопкой на "Servers" → "Register" → "Server"
2. Вкладка **General**:
   - **Name**: `Dubbing Studio DB`
3. Вкладка **Connection**:
   - **Host name/address**: `dubbing-studio-db` (имя сервиса в Docker)
   - **Port**: `5432`
   - **Maintenance database**: `dubbing_studio`
   - **Username**: `postgres`
   - **Password**: `secure_password_123`
4. Нажмите "Save"

**Или используйте команду:**
```bash
./run_docker.sh pgadmin
```

### Ручное развёртывание

1. Создайте БД PostgreSQL 14+ с расширениями pgcrypto и pgaudit
2. Выполните скрипты в порядке:
```bash
psql -U postgres -d dubbing_studio -f 00_init_all.sql
```

## Безопасность

### Row Level Security (RLS)
- Включён для всех критически важных таблиц
- Актёры видят только свои данные
- Менеджеры видят только проекты своей студии

### Аудит
- **Логирование входов**: автоматическое через pgaudit + ручное через функции
- **Аудит DML**: триггеры на все основные таблицы записывают изменения в audit.data_access_log

### Классификация данных
- **Public**: общая информация о проектах
- **Internal**: контакты клиентов
- **Confidential**: банковские реквизиты, суммы контрактов
- **Restricted**: паспортные данные, налоговые номера

## Тестирование

### Тесты ЛР1 (роли)
```bash
# Запуск тестов ролей
./run_docker.sh test-roles
```

### Тесты ЛР2
```bash
# Запуск тестов ЛР2
./run_docker.sh test-lr2

# Тест производительности (CHECK vs триггер)
./run_docker.sh test-lr2-performance

# Просмотр журнала вызовов функций
./run_docker.sh show-lr2-log
```

## Структура файлов

### Лабораторная работа №1 (ЛР1)
- `00_init_all.sql` - главный скрипт инициализации
- `script1.sql` - схемы и расширения
- `script2.sql` - таблицы
- `script3.sql` - справочные данные
- `script4.sql` - роли
- `script5.sql` - привилегии
- `script6.sql` - DEFAULT PRIVILEGES
- `script7.sql` - аудит подключений
- `script8.sql` - тестовые данные
- `script9.sql` - RLS и политики
- `script10.sql` - триггеры аудита DML и тестирование системы
- `script11.sql` - финальная проверка
- `test.sql` - тесты БД
- `role_testing_scenarios.sql` - сценарии проверки ролей

### Лабораторная работа №2 (ЛР2)
- `lr2_00_init_all.sql` - главный скрипт инициализации ЛР2
- `lr2_01_function_calls_log.sql` - таблица журнала вызовов функций
- `lr2_02_security_definer_functions.sql` - SECURITY DEFINER-функции
- `lr2_03_check_vs_trigger.sql` - сравнение CHECK vs триггер
- `lr2_04_tests.sql` - тесты прав доступа (10+ кейсов)
- `lr2_05_demo_function_log.sql` - демонстрация журнала вызовов
- `lr2_06_performance_test.sql` - тест производительности
- `init_lr2.sh` - скрипт инициализации ЛР2 для Docker
- `README_LR2.md` - документация по ЛР2

### Лабораторная работа №3 (ЛР3)
- `lr3_01_segment_model.sql` - создание справочника сегментов, ACL и добавление `segment_id` во все таблицы `app.*`
- `lr3_02_rls.sql` - функция `app.set_session_ctx`, вспомогательные функции и новые политики RLS с режимом `auditor`
- `lr3_03_tests.sql` - 9 автоматизированных сценариев проверки изоляции (вставка/обновление/аудитор/сессии)
- `lr3_run_all.sh` - автоматический запуск ЛР3 внутри Docker (старт контейнера, накатывание скриптов, тесты)
- `README_LR3.md` - отчёт по ЛР3 с описанием сегментации, политик и тестов

### Docker и развёртывание
- `docker-compose.yml` - конфигурация Docker
- `Dockerfile` - образ PostgreSQL с расширениями (автоматически выполняет ЛР1 и ЛР2)
- `run_docker.sh` - скрипт управления Docker контейнером
- `init_database.sh` - скрипт инициализации БД для Docker

**Примечание:** При первом запуске Docker контейнера (`./run_docker.sh start`) автоматически выполняются все скрипты ЛР1 и ЛР2.

