-- Trigger Functions

-- CALENDAR MANAGEMENT
CREATE OR REPLACE FUNCTION entries.fn_clean_dates_logic()
RETURNS TRIGGER AS $$
BEGIN
    NEW.day_of_week := TRIM(TO_CHAR(NEW.date_key, 'Day'));
    NEW.month_name  := TRIM(TO_CHAR(NEW.date_key, 'Month'));
    NEW.day_short   := TO_CHAR(NEW.date_key, 'Dy');
    NEW.month_short := TO_CHAR(NEW.date_key, 'Mon');
    NEW.is_weekend  := EXTRACT(ISODOW FROM NEW.date_key) IN (6, 7);
    NEW.day_of_week_index := (EXTRACT(ISODOW FROM NEW.date_key) - 1)::SMALLINT;
    NEW.date_year := EXTRACT(YEAR FROM NEW.date_key)::SMALLINT;
    NEW.month_num := EXTRACT(MONTH FROM NEW.date_key)::SMALLINT;
    NEW.day_num   := EXTRACT(DAY FROM NEW.date_key)::SMALLINT;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_clean_dates 
BEFORE INSERT OR UPDATE ON entries.dates_table 
FOR EACH ROW EXECUTE FUNCTION entries.fn_clean_dates_logic();


--  ID GENERATION LOGIC
CREATE OR REPLACE FUNCTION entries.fn_generate_unique_id()
RETURNS TRIGGER AS $$
DECLARE
    v_title       TEXT;
    v_year        TEXT;
    v_clean_title TEXT;
    v_base_prefix TEXT;
    v_base_code   TEXT;
    v_final_code  TEXT;
    v_next_num    INTEGER;
    v_existing_id TEXT;
BEGIN
    -- MOVIE METADATA LOGIC
    IF TG_TABLE_NAME = 'movie_metadata' THEN
        SELECT movie_code INTO v_existing_id FROM entries.movie_metadata
         WHERE title = NEW.title AND year_released = NEW.year_released LIMIT 1;
        
        IF v_existing_id IS NOT NULL THEN
            NEW.movie_code := v_existing_id;
            RETURN NEW;
        END IF;

        -- Respect manually provided codes if they already exist
        IF NEW.movie_code IS NOT NULL AND TRIM(NEW.movie_code) != '' THEN 
            RETURN NEW; 
        END IF;

        v_title := NEW.title;
        v_year := RIGHT(NEW.year_released::TEXT, 2);
        v_clean_title := REGEXP_REPLACE(TRIM(v_title), '^\s*(the|a|an)\s+', '', 'i');
        v_clean_title := REGEXP_REPLACE(v_clean_title, '[^a-zA-Z0-9]', '', 'g');
        v_base_prefix := UPPER(RPAD(LEFT(v_clean_title, 3), 3, 'X'));
        v_base_code := v_base_prefix || '-' || v_year;

        IF EXISTS (SELECT 1 FROM entries.movie_metadata WHERE movie_code = v_base_code
                   UNION ALL
                   SELECT 1 FROM entries.series_metadata WHERE series_code = v_base_code) THEN
            SELECT COALESCE(MAX(CAST(SUBSTRING(movie_code FROM '-([0-9]+)$') AS INTEGER)), 0) + 1
              INTO v_next_num FROM entries.movie_metadata
             WHERE movie_code ~ ('^' || v_base_code || '-[0-9]+$');
            
            v_final_code := v_base_code || '-' || COALESCE(v_next_num, 1);
        ELSE
            v_final_code := v_base_code;
        END IF;
        
        NEW.movie_code := v_final_code;

    -- SERIES METADATA LOGIC
    ELSIF TG_TABLE_NAME = 'series_metadata' THEN
        IF NEW.series_code IS NOT NULL AND TRIM(NEW.series_code) != '' THEN
            RETURN NEW;
        END IF;

        v_title       := NEW.title;
        v_year        := RIGHT(NEW.year_released::TEXT, 2);
        v_clean_title := REGEXP_REPLACE(TRIM(v_title), '^\s*(the|a|an)\s+', '', 'i');
        v_clean_title := REGEXP_REPLACE(v_clean_title, '[^a-zA-Z0-9]', '', 'g');
        v_base_prefix := UPPER(RPAD(LEFT(v_clean_title, 3), 3, 'X')); 
        v_base_code   := v_base_prefix || '-' || v_year;

        IF EXISTS (SELECT 1 FROM entries.series_metadata WHERE series_code = v_base_code
                   UNION ALL
                   SELECT 1 FROM entries.movie_metadata WHERE movie_code = v_base_code) THEN
            SELECT COALESCE(MAX(CAST(SUBSTRING(series_code FROM '-([0-9]+)$') AS INTEGER)), 0) + 1
              INTO v_next_num FROM entries.series_metadata
             WHERE series_code ~ ('^' || v_base_code || '-[0-9]+$');

            v_final_code := v_base_code || '-' || COALESCE(v_next_num, 1);
        ELSE
            v_final_code := v_base_code;
        END IF;

        NEW.series_code := v_final_code;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER trg_generate_series_code 
BEFORE INSERT ON entries.series_metadata 
FOR EACH ROW EXECUTE FUNCTION entries.fn_generate_unique_id();

CREATE OR REPLACE TRIGGER trg_generate_movie_code 
BEFORE INSERT ON entries.movie_metadata
FOR EACH ROW EXECUTE FUNCTION entries.fn_generate_unique_id();


--  DATA SANITIZATION & CLEANING
CREATE OR REPLACE FUNCTION entries.fn_sanitize_registry_entries()
RETURNS trigger AS $$
DECLARE
    title_parts text[];
    director_parts text[];
    genre_item text;
    split_genre text;
    cleaned_genres text[] := '{}';
BEGIN
    NEW.title := initcap(trim(NEW.title));
    -- Fix 'T, 'S, etc. 
    title_parts := string_to_array(NEW.title, '''');
    IF array_length(title_parts, 1) > 1 THEN
        FOR i IN 2..array_length(title_parts, 1) LOOP
            title_parts[i] := lower(left(title_parts[i], 1)) || substr(title_parts[i], 2);
        END LOOP;
        NEW.title := array_to_string(title_parts, '''');
    END IF;
    -- Fix Roman Numerals and 'vs'
    NEW.title := regexp_replace(NEW.title, '\yIii\y', 'III', 'g');
    NEW.title := regexp_replace(NEW.title, '\yIi\y', 'II', 'g');
    NEW.title := regexp_replace(NEW.title, '\yIv\y', 'IV', 'g');
    NEW.title := regexp_replace(NEW.title, '\yVs\y', 'vs', 'g');
    -- This handles the "&" split and forces "SciFi" as the default
    IF NEW.genres IS NOT NULL THEN
        FOREACH genre_item IN ARRAY NEW.genres LOOP
            -- Split by ampersand and iterate through results
            FOREACH split_genre IN ARRAY string_to_array(genre_item, '&') LOOP
                split_genre := trim(split_genre);
                -- Normalize Sci-Fi variants to "SciFi"
                IF split_genre ~* 'Sci-Fi|Sci Fi|SciFi' THEN split_genre := 'SciFi';
                ELSE
                    split_genre := initcap(split_genre);
                END IF;
                IF NOT (cleaned_genres @> ARRAY[split_genre]) THEN
                    cleaned_genres := array_append(cleaned_genres, split_genre);
                END IF;
            END LOOP;
        END LOOP;
        NEW.genres := cleaned_genres;
    END IF;

    IF TG_TABLE_NAME = 'series_metadata' THEN
        IF NEW.platform IS NOT NULL THEN
            NEW.platform := upper(trim(NEW.platform));
        END IF;

    ELSIF TG_TABLE_NAME = 'movie_metadata' THEN
        IF NEW.director IS NOT NULL THEN
            NEW.director := initcap(trim(NEW.director));
            director_parts := string_to_array(NEW.director, '''');
            IF array_length(director_parts, 1) > 1 THEN
                FOR i IN 2..array_length(director_parts, 1) LOOP
                    director_parts[i] := lower(left(director_parts[i], 1)) || substr(director_parts[i], 2);
                END LOOP;
                NEW.director := array_to_string(director_parts, '''');
            END IF;
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_sanitize_series 
BEFORE INSERT OR UPDATE ON entries.series_metadata 
FOR EACH ROW EXECUTE FUNCTION entries.fn_sanitize_registry_entries();

CREATE TRIGGER trg_sanitize_movies 
BEFORE INSERT OR UPDATE ON entries.movie_metadata
FOR EACH ROW EXECUTE FUNCTION entries.fn_sanitize_registry_entries();

-- TIMESTAMPING
CREATE OR REPLACE FUNCTION entries.fn_set_last_updated()
RETURNS trigger
AS $function$
BEGIN
    NEW.last_updated := CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$function$ 
LANGUAGE plpgsql;

-- 1. Metadata Aspect
CREATE TRIGGER trg_last_updated_series_metadata
BEFORE UPDATE ON entries.series_metadata
FOR EACH ROW EXECUTE FUNCTION entries.fn_set_last_updated();

CREATE TRIGGER trg_last_updated_movie_metadata
BEFORE UPDATE ON entries.movie_metadata
FOR EACH ROW EXECUTE FUNCTION entries.fn_set_last_updated();

-- 2. Log Aspect
CREATE TRIGGER trg_last_updated_series_log
BEFORE UPDATE ON entries.series_log
FOR EACH ROW EXECUTE FUNCTION entries.fn_set_last_updated();

CREATE TRIGGER trg_last_updated_movie_log
BEFORE UPDATE ON entries.movie_log
FOR EACH ROW EXECUTE FUNCTION entries.fn_set_last_updated();

-- PROGRESS PROTECTOR
CREATE OR REPLACE FUNCTION entries.fn_progress_protector()
RETURNS TRIGGER AS $$
BEGIN
    CASE NEW.watch_status
        WHEN 'On-Hold' THEN
            NEW.end_date := NULL;
        WHEN 'Dropped', 'Finished' THEN
            IF NEW.end_date IS NULL THEN 
                NEW.end_date := CURRENT_DATE; 
            END IF;
        ELSE
            NULL;
    END CASE;

    IF NEW.episodes_watched >= NEW.total_episodes AND NEW.total_episodes > 0 THEN
        NEW.watch_status := 'Finished';
        IF NEW.end_date IS NULL THEN 
            NEW.end_date := CURRENT_DATE; 
        END IF;
    -- If episodes are still remaining, flip back to Watching
    ELSIF NEW.episodes_watched < NEW.total_episodes 
          AND NEW.watch_status NOT IN ('Dropped', 'On-Hold') THEN
        NEW.watch_status := 'Watching';
        NEW.end_date     := NULL;
    END IF;
    -- Prevent watched count from exceeding total
    IF NEW.episodes_watched > NEW.total_episodes AND NEW.total_episodes > 0 THEN
        NEW.episodes_watched := NEW.total_episodes;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_progress_protector 
BEFORE INSERT OR UPDATE ON entries.series_log 
FOR EACH ROW EXECUTE FUNCTION entries.fn_progress_protector();

-- AUDIT SYSTEM
-- 1. SERIES METADATA AUDIT
CREATE OR REPLACE FUNCTION entries.fn_audit_series_deletion()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO entries.series_metadata_audit 
   ( series_id, series_code, title, original_data)
    VALUES 
   ( OLD.series_id, OLD.series_code, OLD.title, to_jsonb(OLD) ); -- Preserves all column values as a JSON object 
    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_audit_series_delete 
BEFORE DELETE ON entries.series_metadata 
FOR EACH ROW EXECUTE FUNCTION entries.fn_audit_series_deletion();

-- 2. MOVIE LOG AUDIT
CREATE OR REPLACE FUNCTION entries.fn_audit_movie_deletion()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO entries.movies_audit 
   ( movie_id, original_data )
    VALUES 
   ( OLD.movie_id, to_jsonb(OLD) );
    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_audit_movie_delete 
BEFORE DELETE ON entries.movie_log 
FOR EACH ROW EXECUTE FUNCTION entries.fn_audit_movie_deletion();

-- 3. SERIES LOG AUDIT
CREATE OR REPLACE FUNCTION entries.fn_audit_series_log_changes()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO entries.series_log_audit (
        log_id, series_id, season_no, 
        watch_status, is_rewatch, operation
    )
    VALUES (
        OLD.log_id, OLD.series_id, OLD.season_no, 
        OLD.watch_status, OLD.is_rewatch, TG_OP
    );

    IF (TG_OP = 'DELETE') THEN
        RETURN OLD;
    ELSE
        RETURN NEW;
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_audit_series_log_delete
BEFORE DELETE ON entries.series_log
FOR EACH ROW
EXECUTE FUNCTION entries.fn_audit_series_log_changes();

CREATE TRIGGER trg_audit_series_log_update
AFTER UPDATE ON entries.series_log
FOR EACH ROW
WHEN (OLD.* IS DISTINCT FROM NEW.*)
EXECUTE FUNCTION entries.fn_audit_series_log_changes();


-- 	MOVIE LOG STATUS
CREATE OR REPLACE FUNCTION entries.fn_sync_movie_status()
RETURNS TRIGGER AS $$
DECLARE
    v_movie_id INTEGER; 
BEGIN
    IF (TG_OP = 'DELETE') THEN
        v_movie_id := OLD.movie_id;
    ELSE
        v_movie_id := NEW.movie_id;
    END IF;

    IF EXISTS (SELECT 1 FROM entries.movie_log WHERE movie_id = v_movie_id) THEN
        UPDATE entries.movie_metadata 
        SET status = 'Logged' 
        WHERE movie_id = v_movie_id;
    ELSE
        UPDATE entries.movie_metadata 
        SET status = 'Backlog' 
        WHERE movie_id = v_movie_id;
    END IF;

    RETURN NULL; 
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_sync_movie_status
AFTER INSERT OR UPDATE OR DELETE ON entries.movie_log
FOR EACH ROW EXECUTE FUNCTION entries.fn_sync_movie_status();


-- MOVIE LOG REWATCH STAMP
CREATE OR REPLACE FUNCTION entries.fn_stamp_movie_rewatch()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.is_rewatch = TRUE THEN
        RETURN NEW;
    END IF;
    IF EXISTS (
        SELECT 1 
        FROM entries.movie_log 
        WHERE movie_id = NEW.movie_id 
          AND completion_status IN ('Finished', 'Skimmed')
    ) THEN
        NEW.is_rewatch := TRUE;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_movie_rewatch_stamp
BEFORE INSERT ON entries.movie_log
FOR EACH ROW
EXECUTE FUNCTION entries.fn_stamp_movie_rewatch();


-- SERIES LOG REWATCH STAMP
CREATE OR REPLACE FUNCTION entries.fn_determine_rewatch_status()
RETURNS TRIGGER AS $$
DECLARE
    v_pre_log_limit INTEGER;
    v_previous_session_exists BOOLEAN;
BEGIN
    IF NEW.is_rewatch = TRUE THEN
        RETURN NEW;
    END IF;

    SELECT seasons_pre_log INTO v_pre_log_limit
    FROM entries.series_metadata
    WHERE series_id = NEW.series_id;

    SELECT EXISTS (
        SELECT 1 
        FROM entries.series_log 
        WHERE series_id = NEW.series_id 
          AND season_no = NEW.season_no 
          AND watch_status = 'Finished'
    ) INTO v_previous_session_exists;

    IF (NEW.season_no <= COALESCE(v_pre_log_limit, 0)) OR v_previous_session_exists THEN
        NEW.is_rewatch := TRUE;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_01_series_rewatch_check
BEFORE INSERT ON entries.series_log
FOR EACH ROW
EXECUTE FUNCTION entries.fn_determine_rewatch_status();
