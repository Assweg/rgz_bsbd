# БСБД · расчётно-графическое задание

`PostgreSQL · PL/pgSQL · Docker` · 5 семестр

Временные привилегии и безопасное удаление данных на основе схемы студии дубляжа.

## Содержание

| Файл или каталог | Тип |
|---|---|
| [.dockerignore](.dockerignore) | Файл |
| [00_init_all.sql](00_init_all.sql) | SQL |
| [all_scripts.sql](all_scripts.sql) | SQL |
| [demo_backup_audit_logs.sh](demo_backup_audit_logs.sh) | Файл |
| [demo_backup_audit_manual.sql](demo_backup_audit_manual.sql) | SQL |
| [demo_backup_manual.sh](demo_backup_manual.sh) | Файл |
| [docker-compose.yml](docker-compose.yml) | Файл |
| [docker.txt](docker.txt) | Файл |
| [Dockerfile](Dockerfile) | Файл |
| [init_database.sh](init_database.sh) | Файл |
| [init_lr2.sh](init_lr2.sh) | Файл |
| [lr2_00_init_all.sql](lr2_00_init_all.sql) | SQL |
| [lr2_01_function_calls_log.sql](lr2_01_function_calls_log.sql) | SQL |
| [lr2_02_security_definer_functions.sql](lr2_02_security_definer_functions.sql) | SQL |
| [lr2_03_check_vs_trigger.sql](lr2_03_check_vs_trigger.sql) | SQL |
| [lr2_04_tests.sql](lr2_04_tests.sql) | SQL |
| [lr2_05_demo_function_log.sql](lr2_05_demo_function_log.sql) | SQL |
| [lr2_06_performance_test.sql](lr2_06_performance_test.sql) | SQL |
| [lr2_run_all.sh](lr2_run_all.sh) | Файл |
| [lr3_01_segment_model.sql](lr3_01_segment_model.sql) | SQL |
| [lr3_02_rls.sql](lr3_02_rls.sql) | SQL |
| [lr3_03_tests.sql](lr3_03_tests.sql) | SQL |
| [lr3_run_all.sh](lr3_run_all.sh) | Файл |
| [lr4_01_views.sql](lr4_01_views.sql) | SQL |
| [lr4_02_audit_triggers.sql](lr4_02_audit_triggers.sql) | SQL |
| [lr4_03_tests.sql](lr4_03_tests.sql) | SQL |
| [lr4_04_performance.sql](lr4_04_performance.sql) | SQL |
| [lr4_05_backup_audit.sql](lr4_05_backup_audit.sql) | SQL |
| [lr4_run_all.sh](lr4_run_all.sh) | Файл |
| [README_ORIGINAL.md](README_ORIGINAL.md) | Инструкция |
| [rgz_00_init_all.sql](rgz_00_init_all.sql) | SQL |
| [rgz_01_temp_privileges.sql](rgz_01_temp_privileges.sql) | SQL |
| [rgz_02_safe_delete_functions.sql](rgz_02_safe_delete_functions.sql) | SQL |
| [rgz_03_tests.sql](rgz_03_tests.sql) | SQL |
| [rgz_run_all.sh](rgz_run_all.sh) | Файл |
| [role_testing_scenarios.sql](role_testing_scenarios.sql) | SQL |
| [run_all_labs.sh](run_all_labs.sh) | Файл |
| [run_all_with_rgz.sh](run_all_with_rgz.sh) | Файл |
| [run_docker.sh](run_docker.sh) | Файл |
| [script1.sql](script1.sql) | SQL |
| [script10.sql](script10.sql) | SQL |
| [script11.sql](script11.sql) | SQL |
| [script2.sql](script2.sql) | SQL |
| [script3.sql](script3.sql) | SQL |
| [script4.sql](script4.sql) | SQL |
| [script5.sql](script5.sql) | SQL |
| [script6.sql](script6.sql) | SQL |
| [script7.sql](script7.sql) | SQL |
| [script8.sql](script8.sql) | SQL |
| [script9.sql](script9.sql) | SQL |
| [test.sql](test.sql) | SQL |
| [test_login_logging.sql](test_login_logging.sql) | SQL |
| [test_rolling.sql](test_rolling.sql) | SQL |
| [БСБД_БутаковН.М._РГЗ.docx](%D0%91%D0%A1%D0%91%D0%94_%D0%91%D1%83%D1%82%D0%B0%D0%BA%D0%BE%D0%B2%D0%9D.%D0%9C._%D0%A0%D0%93%D0%97.docx) | Отчёт |
| [БСБД_БутаковН.М._РГЗ.pdf](%D0%91%D0%A1%D0%91%D0%94_%D0%91%D1%83%D1%82%D0%B0%D0%BA%D0%BE%D0%B2%D0%9D.%D0%9C._%D0%A0%D0%93%D0%97.pdf) | PDF |
| [БСБД_БутаковН.М._РГР.docx](%D0%91%D0%A1%D0%91%D0%94_%D0%91%D1%83%D1%82%D0%B0%D0%BA%D0%BE%D0%B2%D0%9D.%D0%9C._%D0%A0%D0%93%D0%A0.docx) | Отчёт |
| [ргр.txt](%D1%80%D0%B3%D1%80.txt) | Файл |

## Запуск

Нужны Docker и Docker Compose.

```bash
docker compose up --build -d
```

## Примечания

Основные сценарии задания имеют префикс rgz_. Предыдущие лабораторные включены как основа общей схемы БД.

## Статус

Сохранены исходные материалы учебной работы. Полная установка зависимостей, сборка и запуск при публикации не выполнялись.

### Отчёты и документы

- [БСБД_БутаковН.М._РГЗ.docx](%D0%91%D0%A1%D0%91%D0%94_%D0%91%D1%83%D1%82%D0%B0%D0%BA%D0%BE%D0%B2%D0%9D.%D0%9C._%D0%A0%D0%93%D0%97.docx)
- [БСБД_БутаковН.М._РГЗ.pdf](%D0%91%D0%A1%D0%91%D0%94_%D0%91%D1%83%D1%82%D0%B0%D0%BA%D0%BE%D0%B2%D0%9D.%D0%9C._%D0%A0%D0%93%D0%97.pdf)
- [БСБД_БутаковН.М._РГР.docx](%D0%91%D0%A1%D0%91%D0%94_%D0%91%D1%83%D1%82%D0%B0%D0%BA%D0%BE%D0%B2%D0%9D.%D0%9C._%D0%A0%D0%93%D0%A0.docx)

---

[Каталог учебных репозиториев](https://github.com/Assweg/nstu) · [Assweg](https://github.com/Assweg)
