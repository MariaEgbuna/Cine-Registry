-- ADD METADATA: Registers a new TV show or Movie into the metadata table
CREATE OR REPLACE PROCEDURE registry.add_metadata(
    p_type           TEXT, 
    p_title          TEXT, 
    p_year           INTEGER, 
    p_country        TEXT DEFAULT 'US',
    p_extra_info     TEXT DEFAULT 'Unknown', -- Acts as Platform for Series and Director for movies
    p_runtime        INTEGER DEFAULT NULL,
    p_genres         TEXT[] DEFAULT NULL, 
    p_tmdb_id        INTEGER DEFAULT NULL,
    p_status         TEXT DEFAULT NULL,
    p_completed      INTEGER DEFAULT NULL, 
    p_seasons        INTEGER DEFAULT NULL, 
    p_episodes       INTEGER DEFAULT NULL, 
    p_seasons_pre_log INTEGER DEFAULT 0
)
LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_exists BOOLEAN;
    v_type   TEXT := UPPER(p_type);
BEGIN
    IF p_tmdb_id IS NULL THEN
        RAISE EXCEPTION 'Registration failed: tmdb_id is required and cannot be NULL.';
    END IF;

    -- Duplicate check based on TMDB ID
    IF v_type = 'SERIES' THEN
        SELECT EXISTS (SELECT 1 FROM registry.series_metadata WHERE tmdb_id = p_tmdb_id) INTO v_exists;
    ELSIF v_type = 'MOVIE' THEN
        SELECT EXISTS (SELECT 1 FROM registry.movie_metadata WHERE tmdb_id = p_tmdb_id) INTO v_exists;
    ELSE
        RAISE EXCEPTION 'Invalid media type: %. Use "MOVIE" or "SERIES".', v_type;
    END IF;

    IF v_exists THEN
        RAISE NOTICE '% (%) is already in the % library.', p_title, p_year, v_type;
        RETURN;
    END IF;
    
    IF v_type = 'SERIES' THEN
        INSERT INTO registry.series_metadata (
            title, country, year_released, year_completed, total_seasons, total_episodes, 
            avg_runtime, genres, platform, status, seasons_pre_log, tmdb_id
        )
        VALUES (
            p_title, p_country, p_year::SMALLINT, p_completed::SMALLINT, p_seasons::SMALLINT, 
            p_episodes::SMALLINT, p_runtime::SMALLINT, p_genres, p_extra_info, 
            COALESCE(p_status, 'Returning'), p_seasons_pre_log::SMALLINT, p_tmdb_id
        );
    ELSE
        INSERT INTO registry.movie_metadata (
            title, year_released, country, director, 
            runtime_mins, genres, tmdb_id
        )
        VALUES (
            p_title, p_year::SMALLINT, p_country, p_extra_info, 
			p_runtime::SMALLINT,  p_genres, p_tmdb_id
        );
    END IF;

    RAISE NOTICE '% (%) registered successfully as %.', p_title, p_year, v_type;
END;
$procedure$;

-- SERIES WATCH: for managing active episodic viewing.
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

    -- Find existing log
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

-- MOVIE WATCH (Movie Activity Logger): Records a specific viewing event within the movie_log table.
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
    -- Lookup
    SELECT movie_id 
    FROM entries.movie_metadata 
    WHERE movie_code = p_movie_code
    INTO v_movie_id;

    IF v_movie_id IS NULL THEN
        RAISE EXCEPTION 'Movie code "%" not found.', p_movie_code;
    END IF;

    -- Check if dates are logically sound
    IF p_date_finished IS NOT NULL AND p_date_finished < p_date_watched THEN
        RAISE EXCEPTION 'Finish date (%) cannot be earlier than start date (%).', p_date_finished, p_date_watched;
    END IF;

    IF p_completion_status = 'Dropped' THEN
        p_rating := NULL;
        p_date_finished := NULL;
    ELSIF p_completion_status IN ('Finished', 'Skimmed') AND p_date_finished IS NULL THEN
        -- Default to same-day finish if not specified
        p_date_finished := p_date_watched;
    END IF;

    INSERT INTO entries.movie_log (
        movie_id, date_watched, date_finished, rating, 
        review, is_rewatch, completion_status
    )
    VALUES (
        v_movie_id, p_date_watched, p_date_finished, p_rating, 
        p_review, p_is_rewatch, p_completion_status
    );
  
    RAISE NOTICE 'Watch logged successfully for: %', p_movie_code;
END;
$procedure$;
