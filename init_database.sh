#!/bin/bash

# Скрипт для инициализации базы данных

echo "Инициализация базы данных студии дубляжа..."

# Подключаемся к БД и выполняем скрипты
docker exec dubbing_studio_postgres psql -U postgres -d dubbing_studio -f /docker-entrypoint-initdb.d/00_extensions_stub.sql
docker exec dubbing_studio_postgres psql -U postgres -d dubbing_studio -f /docker-entrypoint-initdb.d/01_schemas.sql
docker exec dubbing_studio_postgres psql -U postgres -d dubbing_studio -f /docker-entrypoint-initdb.d/02_tables.sql
docker exec dubbing_studio_postgres psql -U postgres -d dubbing_studio -f /docker-entrypoint-initdb.d/03_ref_data.sql
docker exec dubbing_studio_postgres psql -U postgres -d dubbing_studio -f /docker-entrypoint-initdb.d/04_roles.sql
docker exec dubbing_studio_postgres psql -U postgres -d dubbing_studio -f /docker-entrypoint-initdb.d/05_privileges.sql
docker exec dubbing_studio_postgres psql -U postgres -d dubbing_studio -f /docker-entrypoint-initdb.d/06_default_privs.sql
docker exec dubbing_studio_postgres psql -U postgres -d dubbing_studio -f /docker-entrypoint-initdb.d/07_audit.sql
docker exec dubbing_studio_postgres psql -U postgres -d dubbing_studio -f /docker-entrypoint-initdb.d/08_test_data.sql
docker exec dubbing_studio_postgres psql -U postgres -d dubbing_studio -f /docker-entrypoint-initdb.d/09_rls.sql
docker exec dubbing_studio_postgres psql -U postgres -d dubbing_studio -f /docker-entrypoint-initdb.d/10_audit_triggers_and_tests.sql
docker exec dubbing_studio_postgres psql -U postgres -d dubbing_studio -f /docker-entrypoint-initdb.d/11_final_verify.sql

echo "Инициализация завершена!"
