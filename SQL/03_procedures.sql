/* ================================================================================
   							STORED PROCEDURES MASTER BACKUP
   ================================================================================
   Schema: cine_registry
   Description: Core logic for metadata registration and progress tracking.
   ================================================================================ */

-- Drop Procedures
DROP PROCEDURE IF EXISTS cine_registry.series_watch;
DROP PROCEDURE IF EXISTS cine_registry.movie_watch;
DROP PROCEDURE IF EXISTS cine_registry.add_series;

/* --------------------------------------------------------------------------------
   1. REGISTRY MANAGEMENT: add_series
   Description: Registers core details of a TV show into the metadata library.
   Logic: 
    - Soft duplicate guard (Title + Year).
    - Relies on 'fn_sanitize_registry_entries' and 'fn_generate_unique_id'.
   --------------------------------------------------------------------------------*/

CREATE OR REPLACE PROCEDURE cine_registry.add_series(
    p_title text, 
    p_country text, 
    p_released integer, 
    p_completed integer DEFAULT NULL, 
    p_seasons integer DEFAULT NULL, 
    p_episodes integer DEFAULT NULL, 
    p_runtime integer DEFAULT NULL, 
    p_genre text[] DEFAULT NULL, 
    p_platform text DEFAULT NULL, 
    p_status text DEFAULT 'Returning', 
    p_seasons_pre_log integer DEFAULT 0,
    p_tmdb_id integer DEFAULT NULL
)
AS $procedure$
DECLARE
    v_exists BOOLEAN;
BEGIN
    -- 1. TMDB ID Guard: If we have an ID, check it first.
    IF p_tmdb_id IS NOT NULL THEN
        SELECT EXISTS (
            SELECT 1 FROM cine_registry.series_metadata WHERE tmdb_id = p_tmdb_id
        ) INTO v_exists;
    ELSE
        -- Fallback: Title + Year guard if TMDB ID is missing
        SELECT EXISTS (
            SELECT 1 FROM cine_registry.series_metadata 
            WHERE title = p_title AND year_released = p_released::SMALLINT
        ) INTO v_exists;
    END IF;

    IF v_exists THEN
        RAISE NOTICE 'Series "%" is already registered. Skipping.', p_title;
        RETURN;
    END IF;

    -- 2. Insertion
    INSERT INTO cine_registry.series_metadata (
    	title, country, year_released, year_completed,total_seasons, total_episodes, 
    	avg_runtime, genre, platform, status, seasons_pre_log, tmdb_id
    )
    VALUES (
        p_title, p_country, p_released::SMALLINT, p_completed::SMALLINT, p_seasons::SMALLINT, p_episodes::SMALLINT,
        p_runtime::SMALLINT, p_genre, p_platform, p_status, p_seasons_pre_log::SMALLINT, p_tmdb_id
    );

    RAISE NOTICE 'Series "%" (%) registered successfully with TMDB ID %.', p_title, p_released, p_tmdb_id;
END;
$procedure$ 
LANGUAGE plpgsql;


/* --------------------------------------------------------------------------------
   2. MOVIE LOGGING: movie_watch
   Description: Logs a movie session with automatic rewatch detection.
   Logic:
    - Automatically sets is_rewatch = TRUE if title/year exists.
    - Reuses existing movie_id for consistent rewatch tracking.
   -------------------------------------------------------------------------------- 
*/

CREATE OR REPLACE PROCEDURE cine_registry.movie_watch(
    p_title text, 
    p_year integer, 
    p_country text, 
    p_genre text[], 
    p_runtime integer, 
    p_rating numeric, 
    p_review text, 
    p_completion_status text DEFAULT 'Finished',
    p_manual_rewatch boolean DEFAULT false, 
    p_date_watched date DEFAULT CURRENT_DATE,
    p_tmdb_id integer DEFAULT NULL 
)
AS $procedure$
DECLARE
    v_is_rewatch BOOLEAN;
    v_final_rating NUMERIC := p_rating;
BEGIN
    -- IMPROVED REWATCH LOGIC: 
    -- Check by TMDB ID first for 100% accuracy, fallback to title + year.
    IF p_tmdb_id IS NOT NULL THEN
        SELECT EXISTS (
            SELECT 1 FROM cine_registry.movies WHERE tmdb_id = p_tmdb_id
        ) INTO v_is_rewatch;
    ELSE
        SELECT EXISTS (
            SELECT 1 FROM cine_registry.movies 
            WHERE movie_title = p_title AND year_released = p_year::SMALLINT
        ) INTO v_is_rewatch;
    END IF;
    
    -- If DB found it, it's a rewatch. Otherwise, use the user's manual flag.
    v_is_rewatch := COALESCE(v_is_rewatch, p_manual_rewatch);

    -- Rating Guard
    IF p_completion_status = 'Dropped' THEN
        v_final_rating := NULL;
    END IF;

    INSERT INTO cine_registry.movies (
        date_watched, movie_title, year_released, country, genre,
        runtime, rating, review, is_rewatch, completion_status, tmdb_id  
    	)
    VALUES (
        p_date_watched, p_title, p_year::SMALLINT, p_country, p_genre,
        p_runtime::SMALLINT, v_final_rating, p_review, v_is_rewatch, p_completion_status, p_tmdb_id
    	);
END;
$procedure$ 
LANGUAGE plpgsql;


/* --------------------------------------------------------------------------------
   3. PROGRESS TRACKING: series_watch
   Description: Primary tool for tracking episode-by-episode progress.
   Logic:
    - Updates active 'Watching' logs or opens new sessions.
    - Relies on 'fn_progress_protector' for automatic status changes.
   -------------------------------------------------------------------------------- 
*/

CREATE OR REPLACE PROCEDURE cine_registry.series_watch(
    p_series_code text, 
    p_season_no integer, 
    p_total_episodes integer, 
    p_episodes_watched integer, 
    p_watch_type text, 
    p_rating numeric, 
    p_review text, 
    p_is_rewatch boolean DEFAULT false, 
    p_start_date date DEFAULT CURRENT_DATE, 
    p_end_date date DEFAULT NULL
)
AS $procedure$
DECLARE
    v_log_id INT;
BEGIN
    SELECT log_id
      INTO v_log_id
      FROM cine_registry.series_log
     WHERE series_code  = p_series_code
       AND season_no    = p_season_no::SMALLINT
       AND watch_status = 'Watching'
       AND is_rewatch   = p_is_rewatch
     ORDER BY start_date DESC
     LIMIT 1;
    IF v_log_id IS NOT NULL THEN
        UPDATE cine_registry.series_log
           SET episodes_watched = p_episodes_watched::SMALLINT,
               total_episodes   = p_total_episodes::SMALLINT,
               watch_type       = p_watch_type,
               watch_status     = 'Watching',
               rating           = p_rating,
               review           = p_review,
               end_date         = COALESCE(p_end_date, end_date)
         WHERE log_id = v_log_id;
    ELSE
        INSERT INTO cine_registry.series_log (
            series_code, season_no, total_episodes,
            episodes_watched, watch_type, watch_status,
            rating, review, is_rewatch, start_date, end_date
        )
        VALUES (
            p_series_code, p_season_no::SMALLINT, p_total_episodes::SMALLINT, p_episodes_watched::SMALLINT,
            p_watch_type, 'Watching', p_rating, p_review, p_is_rewatch, p_start_date, p_end_date
        );
    END IF;
END;
$procedure$ 
LANGUAGE plpgsql;

