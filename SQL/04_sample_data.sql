-- Populate Dates table using generate series
INSERT INTO entries.dates_table (date_key, date_year, quarters, month_num, month_short, day_short, day_of_week_index, is_weekend)
SELECT 
    datum AS date_key,
    EXTRACT(YEAR FROM datum)::SMALLINT AS date_year,
    EXTRACT(QUARTER FROM datum)::SMALLINT AS quarters,
    EXTRACT(MONTH FROM datum)::SMALLINT AS month_num,
    TO_CHAR(datum, 'Mon') AS month_short,
    TO_CHAR(datum, 'Dy') AS day_short,
    EXTRACT(ISODOW FROM datum)::SMALLINT AS day_of_week_index,
    CASE 
        WHEN EXTRACT(ISODOW FROM datum) IN (6, 7) THEN TRUE 
        ELSE FALSE 
    END AS is_weekend
FROM generate_series('2025-01-01'::DATE, '2027-12-31'::DATE, '1 day'::INTERVAL) AS datum;

-- For Series Metadata
INSERT INTO entries.series_metadata (title,country,year_released,year_completed,total_seasons,total_episodes,avg_runtime,genres,platform,status,seasons_pre_log,tmdb_id) 
VALUES
('Justice League Unlimited','US',2004,2006,3,39,22,'{Action,Animation,Superhero}','HBO','Ended',0,84200),
('Peacemaker','US',2022,NULL,2,16,42,'{Action,Comedy,Superhero}','HBO','Ended',1,110492),
('It: Welcome To Derry','US',2025,NULL,1,8,55,'{Horror,Thriller}','HBO','Returning',0,200875),
('Creature Commandos','US',2024,NULL,1,7,22,'{Superhero,Comedy,Animation}','HBO','Returning',0,219543),
('White Lotus','US',2021,NULL,3,21,60,'{Drama,Comedy}','HBO','Returning',0,111803),
('Veep','US',2012,2019,7,65,28,'{Comedy}','HBO','Ended',0,2947),
('Batman Beyond','US',1999,2001,3,52,22,'{Animation,Superhero,Cyberpunk}','CARTOON NETWORK','Ended',0,513),
('The Expanse','US',2015,2022,6,62,50,'{Drama,SciFi}','AMAZON PRIME VIDEO','Ended',0,63639),
('Better Call Saul','US',2015,2022,6,63,55,'{Drama,Crime}','AMC/AMC+','Ended',4,60059),
('My Happy Marriage','JP',2023,NULL,2,26,25,'{Romance,Drama}','NETFLIX','TBD',0,196944);

-- Movie Metadata
INSERT INTO entries.movie_metadata (title,year_released,country,director,runtime_mins,genres,tmdb_id) 
VALUES
('Don''t Move',2024,'US','Brian Netto',92,'{Horror,Thriller}',1063877),
('Megamind vs. The Doom Syndicate',2024,'US','Eric Fogel',83,'{Animation,Comedy}',1239251),
('Inglourious Basterds',2009,'DE','Quentin Tarantino',153,'{Drama,Thriller,War}',16869),
('Jurassic Park',1993,'US','Steven Spielberg',127,'{Adventure,SciFi}',329),
('Whistle',2026,'IE','Corin Hardy',100,'{Horror,Mystery}',1193501),
('War Machine',2026,'AU','Patrick Hughes',110,'{Action,SciFi,Thriller}',1265609),
('The Secret Agent',2025,'BR','Kleber Mendonça Filho',161,'{Crime,Drama,Thriller}',1220564),
('The Incredible Hulk',2008,'US','Louis Leterrier',114,'{SciFi,Action,Adventure}',1724),
('Captain America: The First Avenger',2011,'US','Joe Johnston',124,'{Action,Adventure,SciFi}',1771);

-- Series Log
-- Using subqueries to look up series_id by series_code avoids hardcoded IDs
-- and prevents sequence conflicts when new rows are added later.
INSERT INTO entries.series_log (series_id,start_date,end_date,season_no,total_episodes,episodes_watched,watch_type,watch_status,is_rewatch,rating,review) 
VALUES
((SELECT series_id FROM entries.series_metadata WHERE tmdb_id = 84200),'2025-09-26','2025-09-28',1,13,13,'Batch','Finished',false,8.8,'Better and better.'),
((SELECT series_id FROM entries.series_metadata WHERE tmdb_id = 84200),'2025-10-01','2025-10-02',2,13,13,'Binge','Finished',false,8.7,'Me likey.'),
((SELECT series_id FROM entries.series_metadata WHERE tmdb_id = 84200),'2025-10-02','2025-10-05',3,13,13,'Batch','Finished',false,8.1,'Bit weak.'),
((SELECT series_id FROM entries.series_metadata WHERE tmdb_id = 110492),'2025-08-21','2025-10-09',2,8,8,'Simulcast','Finished',false,7.3,'Decent follow up.'),
((SELECT series_id FROM entries.series_metadata WHERE tmdb_id = 200875),'2025-12-20','2025-12-20',1,8,8,'Binge','Finished',false,8.4,'Really awesome.'),
((SELECT series_id FROM entries.series_metadata WHERE tmdb_id = 219543),'2025-01-05','2025-01-05',1,7,7,'Binge','Finished',false,7.8,'It''s short, sweet, and straight to the point.'),
((SELECT series_id FROM entries.series_metadata WHERE tmdb_id = 111803),'2025-04-18','2025-04-18',1,6,6,'Binge','Finished',false,8.9,'Favourite show of the month.'),
((SELECT series_id FROM entries.series_metadata WHERE tmdb_id = 111803),'2025-05-02','2025-05-02',2,7,7,'Binge','Finished',false,9.8,'A perfect season.'),
((SELECT series_id FROM entries.series_metadata WHERE tmdb_id = 111803),'2025-06-27','2025-06-29',3,8,8,'Batch','Finished',false,8.7,'Wanted more tho.'),
((SELECT series_id FROM entries.series_metadata WHERE tmdb_id = 2947),'2025-05-26','2025-05-26',1,8,8,'Binge','Finished',false,8.1,'Pretty funny.'),
((SELECT series_id FROM entries.series_metadata WHERE tmdb_id = 2947),'2025-05-28','2025-05-28',2,10,10,'Binge','Finished',false,8.4,'Hilarious.'),
((SELECT series_id FROM entries.series_metadata WHERE tmdb_id = 2947),'2025-05-31','2025-05-31',3,10,10,'Binge','Finished',false,8.8,'I love this show.');

-- Movie Log
INSERT INTO entries.movie_log (movie_id,date_watched,date_finished,rating,is_rewatch,completion_status,review) 
VALUES
((SELECT movie_id FROM entries.movie_metadata WHERE tmdb_id = 1063877),'2025-03-12',NULL,NULL,false,'Dropped','My anxiety went through the roof.'),
((SELECT movie_id FROM entries.movie_metadata WHERE tmdb_id = 1239251),'2026-03-06',NULL,NULL,false,'Dropped','This is an abomination.'),
((SELECT movie_id FROM entries.movie_metadata WHERE tmdb_id = 16869),'2025-01-07','2025-01-07',7.6,true,'Finished','I loved this movie.'),
((SELECT movie_id FROM entries.movie_metadata WHERE tmdb_id = 329),'2025-01-04','2025-01-04',7.1,true,'Finished','A good start to the universe. His suit could have been better but it''s good.'),
((SELECT movie_id FROM entries.movie_metadata WHERE tmdb_id = 1193501),'2026-03-09',NULL,NULL,false,'Dropped','I forgot to finish it.'),
((SELECT movie_id FROM entries.movie_metadata WHERE tmdb_id = 1265609),'2026-03-13','2026-03-13',5.2,false,'Finished','This was definitely something.'),
((SELECT movie_id FROM entries.movie_metadata WHERE tmdb_id = 1220564),'2026-03-13',NULL,NULL,false,'In Progress','TBA'),
((SELECT movie_id FROM entries.movie_metadata WHERE tmdb_id = 1724),'2026-03-13',NULL,NULL,false,'Dropped','It was so bland.'),
((SELECT movie_id FROM entries.movie_metadata WHERE tmdb_id = 1771),'2026-03-14',NULL,NULL,false,'In Progress','TBA');

-- ============================================================================
-- VERIFICATION
-- ============================================================================
SELECT * FROM series_metadata;
SELECT * FROM movie_metadata;
SELECT * FROM series_log;
SELECT * FROM movie_log;
