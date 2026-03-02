-- *********************************************************************************************
-- 					04_SAMPLE_DATA.SQL - INTEGRATION & DEMO SUITE
-- *********************************************************************************************
/* PURPOSE: This script populates the Cine_Registry schema with a diversified set of 
   sample data to demonstrate trigger automation, state transitions, and view logic.
   It serves as a functional test for the Procedural API.
*/

-- 1. POPULATE SERIES METADATA (The Registry)
INSERT INTO cine_registry.series_metadata 
(title, country, year_released, year_completed, total_seasons, total_episodes, avg_runtime, genre, platform, status, seasons_pre_log, tmdb_id)
VALUES
('The Mighty Nein', 'US', 2025, NULL, 1, 12, 25, ARRAY['Adventure','Animation','Fantasy'], Amazon Prime Video, Returning, 0, 219080),
('Severance', 'US', 2022, NULL, 2, 19, 45, ARRAY['Sci-Fi','Thriller'], Apple TV+, Returning, 1, 95396),
('Silo', 'US', 2023, NULL, 2, 20, 50, ARRAY['Drama','Sci-Fi'], Apple TV+, Returning, 0, 125988),
('Special Operations: Lioness', 'US', 2023, NULL, 2, 16, 45, ARRAY['Action','Thriller'], Paramount+, Returning, 0, 113962),
('Squid Game', 'KR', 2021, 2025, 3, 22, 55, ARRAY['Drama','Thriller'], Netflix, Ended, 1, 93405),
('Narcos: Mexico', 'US', 2018, 2021, 3, 30, 55, ARRAY['Drama','Thriller'], Netflix, Ended, 0, 80968),
('Dandadan', 'JP', 2024,NULL ,2 ,24 ,24 ,ARRAY['Animation','Supernatural','Shonen'] ,Netflix ,Returning ,0 ,240411),
('The Newsreader', 'AU',2021 ,2025 ,3 ,18 ,55 ,ARRAY['Drama'] ,ABC ,Ended ,0 ,130842),
('Vigilante', 'KR',2023,NULL ,1 ,8 ,45 ,ARRAY['Action','Crime','Thriller'] ,'Disney+' ,'Returning' ,'0' ,'205082'),
('Beyond Evil', 'KR',2021 ,2021 ,1 ,16 ,65 ,ARRAY['Mystery','Thriller'] ,JTBC ,Ended ,0 ,116612);


-- 2. POPULATE MOVIES (The Cinema Archive)
INSERT INTO cine_registry.movies 
(date_watched, movie_title, release_year, country, genre, runtime, rating, review, is_rewatch)
VALUES
('2026-01-10', 'Inception', 2010, 'US', '{"Sci-Fi", "Action"}', 148, 8.2, 'Best rewatch value.', FALSE),
('2026-01-15', 'Parasite', 2019, 'KR', '{"Thriller", "Social Commentary"}', 132, 9.0, 'Flawless execution.', FALSE),
('2026-02-01', 'Dune: Part Two', 2024, 'US', '{"Sci-Fi", "Adventure"}', 166, 7.6, 'Visual spectacle.', FALSE);

-- 3. POPULATE SERIES_LOG (The Daily Log)
INSERT INTO series_log (series_code,start_date,end_date,season_no,total_episodes,episodes_watched,watch_type,watch_status,is_rewatch,rating,review) 
VALUES
	 ('SQU-21','2025-01-01','2025-01-03',2,7,7,'Batch','Finished',false,7.8,'Don''t know why there''s a second season, but it wasn''t bad.'),
	 ('SIL-23','2025-01-02','2025-01-12',1,10,10,'One-a-Day','Finished',false,8.5,'I decided to watch this on whim and I was not disappointed.'),
	 ('SEV-22','2025-01-10','2025-01-15',1,9,9,'Batch','Finished',true,8.8,'This was a rewatch and wow. The world building is insane.'),
	 ('SEV-22','2025-01-17','2025-03-21',2,10,10,'Weekly','Finished',false,8.2,'Good follow up.'),
	 ('SIL-23','2025-02-15','2025-02-25',2,10,10,'One-a-Day','Finished',false,7.8,'Not a bad second season.'),
	 ('NEW-21','2025-02-26','2025-02-26',1,6,6,'All-Nighter','Finished',false,8.2,'A lovely surprise.'),
	 ('NEW-21','2025-02-27','2025-02-27',2,6,6,'All-Nighter','Finished',false,8.7,'I can''t stop watching.'),
	 ('NEW-21','2025-02-28','2025-02-28',3,6,6,'All-Nighter','Finished',false,8.3,'Sam Reid is an amazing actor.'),
	 ('VIG-23','2025-04-10','2025-04-15',1,8,8,'Batch','Finished',true,7.5,'Decent show.'),
	 ('BEY-21','2025-05-12','2025-05-30',1,16,16,'Casual','Finished',true,6.9,'16eps was too much.'),
	 ('DAN-24','2025-06-04','2025-06-16',1,12,12,'One-a-Day','Finished',false,7.3,'I won''t bother watching S2.'),
	 ('SQU-21','2025-07-01','2025-07-03',3,6,6,'Batch','Finished',false,7.3,'Netflix wanted to milk it.'),
	 ('SHI-13','2025-07-20','2025-07-28',1,25,25,'Batch','Finished',true,8.5,'Amazing first season.'),
	 ('SHI-13','2025-08-11','2025-08-11',2,12,12,'Binge','Finished',true,8.7,'Crazy season!!'),
	 ('SHI-13','2025-09-13','2025-09-18',3,22,22,'Batch','Finished',true,8.3,'Still good.'),
	 ('SPE-23','2025-10-01','2025-10-08',1,8,8,'One-a-Day','Finished',false,7.7,'Not my kind of show.'),
	 ('NAR-18','2026-01-02','2026-01-07',1,10,10,'Batch','Finished',false,8.0,'Impressive.'),
	 ('MIG-25','2026-01-04','2026-01-05',1,8,8,'Binge','Finished',false,7.2,'Vox machina vibes.'),
	 ('NAR-18','2026-01-06','2026-01-08',2,10,10,'Binge','Finished',false,8.8,'Better than Narcos Colombia.'),
	 ('JUJ-20','2026-01-08',NULL,3,24,7,'Weekly','Watching',false,NULL,'The animation was fucking amazing this season. Story is cooking so far.'),
	 ('NAR-18','2026-01-11','2026-01-12',3,10,10,'Binge','Finished',false,8.6,'Fantastic.'),
	 ('SHI-13','2026-01-12','2026-01-23',4,35,35,'Batch','Finished',true,9.2,'Never be a show like this.');

-- ============================================================================
-- 3. VERIFICATION
-- ============================================================================
SELECT * FROM cine_registry.series_metadata;
SELECT * FROM cine_registry.movies;
SELECT * FROM cine_registry.series_log;

-- ============================================================================
-- 4. PROCEDURAL API DEMONSTRATION
-- ============================================================================

-- A. Registering New Content via Procedure
/*
Triggers will automatically generate 'BEA-22' series_code and clean the genre array.
CALL cine_registry.add_series(
    '${title}', 
    '${country}', 
    ${year_released}, 
    ${year_completed}, 
    ${total_seasons}, 
    ${total_episodes}, 
    ${avg_runtime}, 
    ARRAY[${genres}], 
    '${platform}', (Hulu, Netflix, Apple TV+, etc.)
    '${status}', (Ended/TBD/Limited/Returning/Cancelled)
    ${seasons_pre_log},
    ${tmdb_id} -- Optional
);
*/

CALL cine_registry.add_series('The Bear', 'US', 2022, NULL, 4, 32, 30, ARRAY['Drama', 'Comedy'], 'Hulu', 'Returning', 0);

-- B. Logging Movies (Smart ID Linking)
/* The movie_watch procedure handles ID retrieval and rewatch flagging automatically.
CALL cine_registry.movie_watch(
    '${movie_title}', 
    ${year_released}, 
    '${country}', 
    ARRAY[${genres}], 
    ${runtime}, 
    ${rating}, 
    '${review}', 
    '${completion_status}', (Finished/Skimmed/Dropped)
    ${is_rewatch}, TRUE/FALSE
    '${date_watched}',
    ${tmdb_id} -- Optional
);
*/

-- This will be logged as a rewatch since 'Inception' (2010) is already in the movies table.
CALL cine_registry.movie_watch('Inception', 2010, 'US', '{"Sci-Fi", "Action"}', 148, 8.8, 'Masterpiece.', 'Finished');

-- C. Daily Episode Tracking (State Machine Test)
/* 
Triggers will keep status as 'Watching' for this entry.
Syntax: 
CALL cine_registry.series_watch(
	'${series_code}', 
	${season_no}, 
	${total_eps}, 
	${eps_watched}, 
	'${watch_type}', (Binge/Weekly/Background/All-Nighter/One-a-Day/Batch/Casual)
	${rating}, 
	'${review}', 
	${is_rewatch}, TRUE/FALSE
	'${optional_start_date}', (Stamps current_date if NULL)
	${optional_end_date} (Stamps NULL if NULL, auto-updates to current_date when season completes)
);
*/

-- Mid-season update, should remain 'Watching' with NULL end_date.
CALL cine_registry.series_watch('SEV-22', 1, 9, 4, 'Casual', 8.1, 'Eerie world-building.', FALSE); 

-- Season completion update, should auto-flip to 'Finished' and stamp end_date.
CALL cine_registry.series_watch('SEV-22', 1, 9, 9, 'Casual', 8.1, 'Eerie world-building.', FALSE); 
