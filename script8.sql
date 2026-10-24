-- 08_test_data.sql
-- Наполнение тестовыми данными

-- Актёры
INSERT INTO app.actors (last_name, first_name, middle_name, phone, email, voice_characteristics) VALUES
('Петров', 'Иван', 'Сергеевич', '+7-911-111-1111', 'ivan@example.com', 'Низкий баритон, эмоциональный'),
('Сидорова', 'Мария', 'Александровна', '+7-922-222-2222', 'maria@example.com', 'Сопрано, чистая дикция'),
('Козлов', 'Алексей', NULL, '+7-933-333-3333', 'alex@example.com', 'Тенор, комедийный тембр'),
('Новикова', 'Елена', 'Дмитриевна', '+7-944-444-4444', 'elena@example.com', 'Меццо-сопрано, драматический'),
('Волков', 'Дмитрий', 'Игоревич', '+7-955-555-5555', 'dmitry@example.com', 'Бас, authoritative'),
('Белова', 'Ольга', 'Владимировна', '+7-966-666-6666', 'olga@example.com', 'Сопрано, детские голоса'),
('Орлов', 'Сергей', NULL, '+7-977-777-7777', 'sergey@example.com', 'Баритон, лирический'),
('Ковалёва', 'Анна', 'Петровна', '+7-988-888-8888', 'anna@example.com', 'Альт, глубокий тембр'),
('Морозов', 'Павел', 'Андреевич', '+7-999-999-9999', 'pavel@example.com', 'Тенор, героический'),
('Павлова', 'Наталья', NULL, '+7-900-000-0000', 'natalia@example.com', 'Сопрано, нежный голос');

-- Проекты
INSERT INTO app.projects (studio_id, title, original_language, description, client_contacts, budget, start_date, end_date) VALUES
(1, 'Звёздные войны: Новый рассвет', 'en', 'Фантастический блокбастер', 'disney@example.com', 500000.00, '2024-01-01', '2024-06-30'),
(2, 'Магия Парижа', 'fr', 'Романтическая комедия', 'frenchfilms@example.com', 250000.00, '2024-02-01', '2024-05-31'),
(1, 'Тайна океана', 'en', 'Документальный фильм', 'natgeo@example.com', 150000.00, '2024-03-01', '2024-04-30'),
(3, 'Берлинские тени', 'de', 'Детективный триллер', 'germanstudio@example.com', 300000.00, '2024-01-15', '2024-07-31'),
(2, 'Римские каникулы', 'it', 'Приключенческий фильм', 'italiancinema@example.com', 200000.00, '2024-02-15', '2024-06-15'),
(4, 'Мадридские ночи', 'es', 'Романтическая драма', 'spanishfilms@example.com', 180000.00, '2024-03-15', '2024-08-31'),
(3, 'Токио: Город огней', 'ja', 'Научно-фантастический фильм', 'japanstudio@example.com', 420000.00, '2024-04-01', '2024-09-30'),
(5, 'Амстердамские каналы', 'nl', 'Детективная драма', 'dutchcinema@example.com', 220000.00, '2024-03-20', '2024-07-20'),
(4, 'Лондонский туман', 'en', 'Мистический триллер', 'britishfilms@example.com', 350000.00, '2024-04-10', '2024-10-31'),
(5, 'Варшавская весна', 'pl', 'Историческая драма', 'polishstudio@example.com', 280000.00, '2024-04-15', '2024-08-15');

-- Контракты
INSERT INTO app.contracts (project_id, actor_id, contract_number, role_description, salary_amount, currency, signed_date) VALUES
(1, 1, 'CNTR-2024-001', 'Главный герой - Люк Скайуокер', 50000.00, 'USD', '2024-01-15'),
(1, 2, 'CNTR-2024-002', 'Принцесса Лея', 45000.00, 'USD', '2024-01-16'),
(1, 3, 'CNTR-2024-003', 'Злодей - Дарт Вейдер', 40000.00, 'USD', '2024-01-17'),
(2, 4, 'CNTR-2024-004', 'Главная героиня - Мари', 30000.00, 'EUR', '2024-02-01'),
(2, 5, 'CNTR-2024-005', 'Главный герой - Пьер', 32000.00, 'EUR', '2024-02-02'),
(3, 6, 'CNTR-2024-006', 'Рассказчик', 20000.00, 'USD', '2024-03-01'),
(4, 7, 'CNTR-2024-007', 'Детектив Мюллер', 35000.00, 'EUR', '2024-01-20'),
(4, 8, 'CNTR-2024-008', 'Подозреваемая Анна', 28000.00, 'EUR', '2024-01-22'),
(5, 9, 'CNTR-2024-009', 'Турист Марко', 25000.00, 'EUR', '2024-02-20'),
(5, 10, 'CNTR-2024-010', 'Гид София', 23000.00, 'EUR', '2024-02-21');

-- Сессии записи
INSERT INTO app.recording_sessions (contract_id, session_date, session_time, studio_location, duration_hours) VALUES
(1, '2024-03-01', '10:00:00', 'Студия А, Москва', 4.0),
(2, '2024-03-01', '14:00:00', 'Студия Б, Москва', 3.5),
(3, '2024-03-02', '11:00:00', 'Студия В, СПб', 5.0),
(4, '2024-03-03', '09:00:00', 'Студия Г, Москва', 4.5),
(5, '2024-03-03', '13:00:00', 'Студия Д, Москва', 3.0),
(6, '2024-03-04', '10:00:00', 'Студия А, Москва', 6.0),
(7, '2024-03-05', '15:00:00', 'Студия Е, Новосибирск', 4.0),
(8, '2024-03-05', '10:00:00', 'Студия Е, Новосибирск', 3.5),
(9, '2024-03-06', '11:00:00', 'Студия Ж, СПб', 4.0),
(10, '2024-03-06', '16:00:00', 'Студия Ж, СПб', 3.0);

-- Роли озвучивания
INSERT INTO app.voice_roles (project_id, actor_id, language_id, character_name, role_type, difficulty_level) VALUES
(1, 1, 1, 'Люк Скайуокер', 'lead', 5),
(1, 2, 1, 'Принцесса Лея', 'lead', 5),
(1, 3, 1, 'Дарт Вейдер', 'villain', 4),
(2, 4, 1, 'Мари', 'lead', 4),
(2, 5, 1, 'Пьер', 'lead', 4),
(3, 6, 1, 'Рассказчик', 'narrator', 3),
(4, 7, 1, 'Детектив Мюллер', 'lead', 4),
(4, 8, 1, 'Анна', 'supporting', 3),
(5, 9, 1, 'Марко', 'lead', 3),
(5, 10, 1, 'София', 'supporting', 3);

-- Аудиоархивы
INSERT INTO app.audio_archives (session_id, file_name, file_path, file_size, duration_seconds, encrypted_audio, encryption_key_id, quality_check_passed) VALUES
(1, 'luke_skywalker_scene1.wav', '/audio/starwars/luke_scene1.wav', 15728640, 300, pgp_sym_encrypt('encrypted_audio_data_1', 'encryption_key_123'), 'key_001', true),
(1, 'luke_skywalker_scene2.wav', '/audio/starwars/luke_scene2.wav', 20971520, 400, pgp_sym_encrypt('encrypted_audio_data_2', 'encryption_key_123'), 'key_002', true),
(2, 'leia_organa_scene1.wav', '/audio/starwars/leia_scene1.wav', 12582912, 250, pgp_sym_encrypt('encrypted_audio_data_3', 'encryption_key_123'), 'key_003', true),
(3, 'darth_vader_scene1.wav', '/audio/starwars/vader_scene1.wav', 18874368, 350, pgp_sym_encrypt('encrypted_audio_data_4', 'encryption_key_123'), 'key_004', false),
(4, 'marie_paris_scene1.wav', '/audio/paris/marie_scene1.wav', 10485760, 200, pgp_sym_encrypt('encrypted_audio_data_5', 'encryption_key_123'), 'key_005', true),
(5, 'pierre_paris_scene1.wav', '/audio/paris/pierre_scene1.wav', 11534336, 220, pgp_sym_encrypt('encrypted_audio_data_6', 'encryption_key_123'), 'key_006', true),
(6, 'narrator_ocean_scene1.wav', '/audio/ocean/narrator_scene1.wav', 25165824, 480, pgp_sym_encrypt('encrypted_audio_data_7', 'encryption_key_123'), 'key_007', true),
(7, 'muller_berlin_scene1.wav', '/audio/berlin/muller_scene1.wav', 14680064, 280, pgp_sym_encrypt('encrypted_audio_data_8', 'encryption_key_123'), 'key_008', true),
(8, 'anna_berlin_scene1.wav', '/audio/berlin/anna_scene1.wav', 8388608, 160, pgp_sym_encrypt('encrypted_audio_data_9', 'encryption_key_123'), 'key_009', false),
(9, 'marco_rome_scene1.wav', '/audio/rome/marco_scene1.wav', 10485760, 200, pgp_sym_encrypt('encrypted_audio_data_10', 'encryption_key_123'), 'key_010', true),
(10, 'sofia_rome_scene1.wav', '/audio/rome/sofia_scene1.wav', 9437184, 180, pgp_sym_encrypt('encrypted_audio_data_11', 'encryption_key_123'), 'key_011', true);

-- Данные для stg.import_log (логи импорта)
INSERT INTO stg.import_log (source_file, records_processed, records_success, records_failed, status, created_by) VALUES
('actors_2024_01.xlsx', 25, 23, 2, 'completed', 'admin'),
('projects_2024_q1.csv', 15, 15, 0, 'completed', 'studio_manager'),
('contracts_march_2024.xlsx', 30, 28, 2, 'completed', 'admin'),
('voice_actors_new.csv', 12, 10, 2, 'failed', 'admin'),
('audio_archives_batch_001.zip', 50, 48, 2, 'completed', 'db_developer'),
('studios_update_2024.xlsx', 8, 8, 0, 'completed', 'admin'),
('languages_reference.csv', 15, 15, 0, 'completed', 'admin'),
('sessions_april_2024.xlsx', 20, 18, 2, 'completed', 'studio_manager'),
('temp_actors_validation.csv', 5, 0, 5, 'failed', 'admin'),
('migration_legacy_system.sql', 100, 95, 5, 'completed', 'db_developer');

-- Данные для stg.temp_actor_data (временные данные актёров)
INSERT INTO stg.temp_actor_data (last_name, first_name, middle_name, phone, email, voice_characteristics, import_batch_id, validation_status, validation_errors) VALUES
('Новиков', 'Александр', 'Викторович', '+7-900-111-1111', 'alex.novikov@example.com', 'Тенор, драматический', 1, 'validated', NULL),
('Смирнова', 'Екатерина', 'Олеговна', '+7-900-222-2222', 'katya.smirnova@example.com', 'Сопрано, лирический', 1, 'validated', NULL),
('Козлов', 'Михаил', NULL, '+7-900-333-3333', 'misha.kozlov@example.com', 'Баритон, комедийный', 1, 'pending', NULL),
('Петрова', 'Анна', 'Сергеевна', '+7-900-444-4444', 'anna.petrova@example.com', 'Меццо-сопрано, глубокий', 1, 'validated', NULL),
('Волков', 'Дмитрий', 'Игоревич', '+7-900-555-5555', 'dmitry.volkov@example.com', 'Бас, authoritative', 1, 'failed', 'Неверный формат телефона'),
('Белова', 'Ольга', 'Владимировна', '+7-900-666-6666', 'olga.belova@example.com', 'Сопрано, детские голоса', 2, 'validated', NULL),
('Орлов', 'Сергей', 'Николаевич', '+7-900-777-7777', 'sergey.orlov@example.com', 'Баритон, лирический', 2, 'pending', NULL),
('Павлова', 'Наталья', NULL, '+7-900-888-8888', 'natalia.pavlova@example.com', 'Сопрано, нежный голос', 2, 'failed', 'Отсутствует email'),
('Морозов', 'Павел', 'Андреевич', '+7-900-999-9999', 'pavel.morozov@example.com', 'Тенор, героический', 2, 'validated', NULL),
('Ковалёва', 'Елена', 'Дмитриевна', '+7-900-000-0000', 'elena.kovaleva@example.com', 'Альт, глубокий тембр', 2, 'pending', NULL);

-- Логируем начальные подключения
SELECT public.log_session_start();