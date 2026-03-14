/* ================================================================================
   							STORED PROCEDURES MASTER BACKUP
   ================================================================================
*/

/* --------------------------------------------------------------------------------
 * add_series (Series Metadata Intake)
 * PURPOSE: Registers new TV show into the series_metadata table.
*/
CREATE OR REPLACE PROCEDURE entries.add_series(
    p_title          TEXT, 
    p_country        TEXT, 
    p_released       INTEGER, 
    p_completed      INTEGER DEFAULT NULL, 
    p_seasons        INTEGER DEFAULT NULL, 
    p_episodes       INTEGER DEFAULT NULL, 
    p_runtime        INTEGER DEFAULT NULL, 
    p_genres         TEXT[] DEFAULT NULL, 
    p_platform       TEXT DEFAULT NULL, 
    p_status         TEXT DEFAULT 'Returning', 
    p_seasons_pre_log INTEGER DEFAULT 0,
    p_tmdb_id        INTEGER DEFAULT NULL
)
LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_exists BOOLEAN;
    v_clean_genres TEXT[];
    v_clean_platform TEXT;
BEGIN
    -- 1. Data Sanitization Logic
    v_clean_genres := array_replace(p_genres, 'Science Fiction', 'SciFi');
    v_clean_platform := UPPER(p_platform);

    -- 2. TMDB ID Guard: If we have an ID, check it first.
    IF p_tmdb_id IS NOT NULL THEN
        SELECT EXISTS (
            SELECT 1 FROM entries.series_metadata WHERE tmdb_id = p_tmdb_id
        ) INTO v_exists;
    ELSE
        -- Fallback: Title + Year guard if TMDB ID is missing
        SELECT EXISTS (
            SELECT 1 FROM entries.series_metadata 
            WHERE title = p_title AND year_released = p_released::SMALLINT
        ) INTO v_exists;
    END IF;

    IF v_exists THEN
        RAISE NOTICE 'Series "%" is already registered. Skipping.', p_title;
        RETURN;
    END IF;

    -- 3. Insertion into series_metadata using sanitized variables
    INSERT INTO entries.series_metadata (
        title, country, year_released, year_completed, total_seasons, total_episodes, 
        avg_runtime, genres, platform, status, seasons_pre_log, tmdb_id
    )
    VALUES (
        p_title, p_country, p_released::SMALLINT, p_completed::SMALLINT, p_seasons::SMALLINT, p_episodes::SMALLINT,
        p_runtime::SMALLINT, v_clean_genres, v_clean_platform, p_status, p_seasons_pre_log::SMALLINT, p_tmdb_id
    );

    RAISE NOTICE 'Series "%" (%) registered successfully.', p_title, p_released;
END;
$procedure$;

/* --------------------------------------------------------------------------------
 * series_watch (Progress Tracking)
 * PURPOSE: for managing active episodic viewing.
*/

CREATE OR REPLACE PROCEDURE entries.series_watch(
    p_series_code      TEXT, 
    p_season_no        INTEGER, 
    p_total_episodes   INTEGER, 
    p_episodes_watched INTEGER, 
    p_watch_type       TEXT, 
    p_rating           NUMERIC, 
    p_review           TEXT, 
    p_watch_status     TEXT DEFAULT 'Watching', 
    p_is_rewatch       BOOLEAN DEFAULT FALSE, 
    p_start_date       DATE DEFAULT CURRENT_DATE, 
    p_end_date         DATE DEFAULT NULL
)
LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_log_id    INT;
    v_series_id INT;
BEGIN
    -- Translate Code to ID
    SELECT series_id INTO v_series_id 
      FROM entries.series_metadata 
     WHERE series_code = p_series_code;

    IF v_series_id IS NULL THEN
        RAISE EXCEPTION 'Series code % not found.', p_series_code;
    END IF;

    -- Find existing log based on the provided status
    SELECT log_id
      INTO v_log_id
      FROM entries.series_log
     WHERE series_id    = v_series_id
       AND season_no    = p_season_no::SMALLINT
       AND watch_status = p_watch_status 
       AND is_rewatch   = p_is_rewatch
     ORDER BY start_date DESC
     LIMIT 1;

    -- Update existing or Insert new
    IF v_log_id IS NOT NULL THEN
        UPDATE entries.series_log
           SET episodes_watched = p_episodes_watched::SMALLINT,
               total_episodes   = p_total_episodes::SMALLINT,
               watch_type       = p_watch_type,
               watch_status     = p_watch_status, 
               rating           = p_rating,
               review           = p_review,
               end_date         = COALESCE(p_end_date, end_date)
         WHERE log_id = v_log_id;
         
        RAISE NOTICE 'Updated % status for % Season %.', p_watch_status, p_series_code, p_season_no;
    ELSE
        INSERT INTO entries.series_log (
            series_id, season_no, total_episodes,
            episodes_watched, watch_type, watch_status,
            rating, review, is_rewatch, start_date, end_date
        )
        VALUES (
            v_series_id, p_season_no::SMALLINT, p_total_episodes::SMALLINT, p_episodes_watched::SMALLINT,
            p_watch_type, p_watch_status, p_rating, p_review, p_is_rewatch, p_start_date, p_end_date
        );
        
        RAISE NOTICE 'Started new % log for % Season %.', p_watch_status, p_series_code, p_season_no;
    END IF;
END;
$procedure$;

/* --------------------------------------------------------------------------------
 * add_movie (Movie Metadata Intake)
 * PURPOSE: Official registrar for film details within movie_metadata table.
--------------------------------------------------------------------------------*/

CREATE OR REPLACE PROCEDURE entries.add_movie(
    p_title         TEXT,
    p_year          INTEGER,
    p_country       TEXT DEFAULT 'US',
    p_director      TEXT DEFAULT 'Unknown',
    p_runtime_mins  INTEGER DEFAULT NULL,
    p_genres        TEXT[] DEFAULT NULL,
    p_tmdb_id       INTEGER DEFAULT NULL,
    p_status        TEXT DEFAULT 'Backlog'
)
LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_exists        BOOLEAN;
    v_clean_genres  TEXT[];
    v_clean_country TEXT;
    v_new_id        INTEGER; -- Variable to capture the generated ID
BEGIN
    -- 1. Data Sanitization
    v_clean_genres := array_replace(p_genres, 'Science Fiction', 'SciFi');
    v_clean_country := UPPER(p_country);

    -- 2. Existence Guard
    IF p_tmdb_id IS NOT NULL THEN
        SELECT EXISTS (
            SELECT 1 FROM entries.movie_metadata WHERE tmdb_id = p_tmdb_id
        ) INTO v_exists;
    ELSE
        SELECT EXISTS (
            SELECT 1 FROM entries.movie_metadata 
            WHERE title = p_title AND year_released = p_year::SMALLINT
        ) INTO v_exists;
    END IF;

    IF v_exists THEN
        RAISE NOTICE 'Movie "%" (%) is already in the library.', p_title, p_year;
        RETURN;
    END IF;

    -- 3. Insertion with ID Capture
    INSERT INTO entries.movie_metadata (
        title, 
        year_released, 
        country, 
        director, 
        runtime_mins, 
        genres, 
        tmdb_id,
        status
    )
    VALUES (
        p_title, 
        p_year::SMALLINT, 
        v_clean_country, 
        p_director,
        p_runtime_mins::SMALLINT, 
        v_clean_genres, 
        p_tmdb_id,
        p_status
    )
    RETURNING movie_id INTO v_new_id; -- The "Golden Link" for your logs

    RAISE NOTICE 'Movie "%" registered successfully with ID: %.', p_title, v_new_id;
END;
$procedure$;

/* --------------------------------------------------------------------------------
 * movie_watch (Movie Activity Logger)
 * PURPOSE: Records a specific viewing event within the movie_log table.
   -------------------------------------------------------------------------------- */
CREATE OR REPLACE PROCEDURE entries.movie_watch(
    p_movie_code        TEXT, 
    p_rating            NUMERIC DEFAULT NULL, 
    p_review            TEXT DEFAULT NULL, 
    p_completion_status TEXT DEFAULT 'Finished',
    p_is_rewatch        BOOLEAN DEFAULT FALSE,
    p_date_watched      DATE DEFAULT CURRENT_DATE,
    p_date_finished     DATE DEFAULT NULL
)
LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_movie_id INTEGER;
BEGIN
    -- 1. Metadata Lookup
    SELECT movie_id 
    FROM entries.movie_metadata 
    WHERE movie_code = p_movie_code
    INTO v_movie_id;

    IF v_movie_id IS NULL THEN
        RAISE EXCEPTION 'Movie code "%" not found.', p_movie_code;
    END IF;

    -- 2. Constraint Validation Logic
    -- Check if dates are logically sound
    IF p_date_finished IS NOT NULL AND p_date_finished < p_date_watched THEN
        RAISE EXCEPTION 'Invalid Dates: Finish date (%) cannot be earlier than start date (%).', 
                        p_date_finished, p_date_watched;
    END IF;

    -- 3. Status Clean-up
    IF p_completion_status = 'Dropped' THEN
        p_rating := NULL;
        p_date_finished := NULL;
    ELSIF p_completion_status IN ('Finished', 'Skimmed') AND p_date_finished IS NULL THEN
        -- Default to same-day finish if not specified
        p_date_finished := p_date_watched;
    END IF;

    -- 4. Execution
    INSERT INTO entries.movie_log (
        movie_id, 
        date_watched, 
        date_finished, 
        rating, 
        review, 
        is_rewatch, 
        completion_status
    )
    VALUES (
        v_movie_id, 
        p_date_watched, 
        p_date_finished, 
        p_rating, 
        p_review, 
        p_is_rewatch, 
        p_completion_status
    );
  
    RAISE NOTICE 'Watch logged successfully for: %', p_movie_code;
END;
$procedure$;
