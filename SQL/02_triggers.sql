-- AUDIT SYSTEM
CREATE OR REPLACE FUNCTION entries.fn_audit_deletions()
RETURNS trigger AS $$
BEGIN
    IF TG_TABLE_NAME = 'series_metadata' THEN
        INSERT INTO entries.metadata_audit (entity_id, content_type, original_data)
        VALUES (OLD.series_id, 'series', to_jsonb(OLD));

    ELSIF TG_TABLE_NAME = 'movie_metadata' THEN
        INSERT INTO entries.metadata_audit (entity_id, content_type, original_data)
        VALUES (OLD.movie_id, 'movie', to_jsonb(OLD));

    ELSIF TG_TABLE_NAME = 'series_log' THEN
        INSERT INTO entries.log_audit (log_id, entity_id, content_type, row_data)
        VALUES (OLD.log_id, OLD.series_id, 'series', to_jsonb(OLD));

    ELSIF TG_TABLE_NAME = 'movie_log' THEN
        INSERT INTO entries.log_audit (log_id, entity_id, content_type, row_data)
        VALUES (OLD.log_id, OLD.movie_id, 'movie', to_jsonb(OLD) );
    END IF;
    
    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

-- Metadata Triggers (Registry Schema)
CREATE TRIGGER trg_audit_series_metadata
AFTER DELETE ON entries.series_metadata
FOR EACH ROW EXECUTE FUNCTION entries.fn_audit_deletions();

CREATE TRIGGER trg_audit_movie_metadata
AFTER DELETE ON entries.movie_metadata
FOR EACH ROW EXECUTE FUNCTION entries.fn_audit_deletions();

-- Log Triggers (Watchlogs Schema)
CREATE TRIGGER trg_audit_series_log
AFTER DELETE ON entries.series_log
FOR EACH ROW EXECUTE FUNCTION entries.fn_audit_deletions();

CREATE TRIGGER trg_audit_movie_log
AFTER DELETE ON entries.movie_log
FOR EACH ROW EXECUTE FUNCTION entries.fn_audit_deletions();

-- ==================================================================

-- CALENDAR MANAGEMENT
CREATE OR REPLACE FUNCTION entries.fn_clean_dates_logic()
RETURNS TRIGGER AS $$
BEGIN
    NEW.day_short   := TO_CHAR(NEW.date_key, 'Dy');
    NEW.month_short := TO_CHAR(NEW.date_key, 'Mon');
    NEW.is_weekend  := EXTRACT(ISODOW FROM NEW.date_key) IN (6, 7);
    NEW.day_of_week_index := (EXTRACT(ISODOW FROM NEW.date_key) - 1)::SMALLINT;
    NEW.date_year := EXTRACT(YEAR FROM NEW.date_key)::SMALLINT;
    NEW.month_num := EXTRACT(MONTH FROM NEW.date_key)::SMALLINT;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_clean_dates 
BEFORE INSERT OR UPDATE ON entries.dates_table 
FOR EACH ROW EXECUTE FUNCTION entries.fn_clean_dates_logic();

-- ==================================================================

CREATE OR REPLACE FUNCTION entries.fn_process_metadata()
RETURNS TRIGGER AS $$
DECLARE
    -- Sanitization Variables
    v_title_parts   TEXT[];
    v_dir_parts     TEXT[];
    v_genre_item    TEXT;
    v_split_genre   TEXT;
    v_cleaned_genres TEXT[] := '{}';
    -- ID Generation Variables
    v_clean_title   TEXT;
    v_base_prefix   TEXT;
    v_base_code     TEXT;
    v_final_code    TEXT;
    v_next_num      INTEGER;
    v_existing_id   TEXT;
BEGIN
    NEW.title := INITCAP(TRIM(NEW.title));
    v_title_parts := STRING_TO_ARRAY(NEW.title, '''');
    IF ARRAY_LENGTH(v_title_parts, 1) > 1 THEN
        FOR i IN 2..ARRAY_LENGTH(v_title_parts, 1) LOOP
            v_title_parts[i] := LOWER(LEFT(v_title_parts[i], 1)) || SUBSTR(v_title_parts[i], 2);
        END LOOP;
        NEW.title := ARRAY_TO_STRING(v_title_parts, '''');
    END IF;

    NEW.title := REGEXP_REPLACE(NEW.title, '\yIii\y', 'III', 'g');
    NEW.title := REGEXP_REPLACE(NEW.title, '\yIi\y', 'II', 'g');
    NEW.title := REGEXP_REPLACE(NEW.title, '\yIv\y', 'IV', 'g');
    NEW.title := REGEXP_REPLACE(NEW.title, '\yVs\y', 'vs', 'g');

    IF NEW.genres IS NOT NULL THEN
        FOREACH v_genre_item IN ARRAY NEW.genres LOOP
            FOREACH v_split_genre IN ARRAY STRING_TO_ARRAY(v_genre_item, '&') LOOP
                v_split_genre := TRIM(v_split_genre);
                IF v_split_genre ~* 'Sci-Fi|Sci Fi|SciFi|Science Fiction' THEN
                    v_split_genre := 'SciFi';
                ELSE
                    v_split_genre := INITCAP(v_split_genre);
                END IF;
                IF NOT (v_cleaned_genres @> ARRAY[v_split_genre]) THEN
                    v_cleaned_genres := ARRAY_APPEND(v_cleaned_genres, v_split_genre);
                END IF;
            END LOOP;
        END LOOP;
        NEW.genres := v_cleaned_genres;
    END IF;

    IF TG_TABLE_NAME = 'series_metadata' THEN
        IF NEW.platform IS NOT NULL THEN
            NEW.platform := UPPER(TRIM(NEW.platform));
        END IF;
    ELSIF TG_TABLE_NAME = 'movie_metadata' THEN
        IF NEW.director IS NOT NULL THEN
            NEW.director := INITCAP(TRIM(NEW.director));
            v_dir_parts := STRING_TO_ARRAY(NEW.director, '''');
            IF ARRAY_LENGTH(v_dir_parts, 1) > 1 THEN
                FOR i IN 2..ARRAY_LENGTH(v_dir_parts, 1) LOOP
                    v_dir_parts[i] := LOWER(LEFT(v_dir_parts[i], 1)) || SUBSTR(v_dir_parts[i], 2);
                END LOOP;
                NEW.director := ARRAY_TO_STRING(v_dir_parts, '''');
            END IF;
        END IF;
        IF NEW.country IS NOT NULL THEN
            NEW.country := UPPER(TRIM(NEW.country));
        END IF;
    END IF;

    -- ==========================================
    IF TG_OP = 'INSERT' THEN

        IF TG_TABLE_NAME = 'movie_metadata' THEN
            SELECT movie_code INTO v_existing_id FROM entries.movie_metadata
             WHERE title = NEW.title AND year_released = NEW.year_released LIMIT 1;
            
            IF v_existing_id IS NOT NULL THEN
                NEW.movie_code := v_existing_id;
            END IF;
            
            IF NEW.movie_code IS NULL OR TRIM(NEW.movie_code) = '' THEN
                v_clean_title := REGEXP_REPLACE(TRIM(NEW.title), '^\s*(the|a|an)\s+', '', 'i');
                v_clean_title := REGEXP_REPLACE(v_clean_title, '[^a-zA-Z0-9]', '', 'g');
                v_base_prefix := UPPER(RPAD(LEFT(v_clean_title, 3), 3, 'X'));
                v_base_code   := v_base_prefix || '-' || RIGHT(NEW.year_released::TEXT, 2);

                -- Global Collision Check
                IF EXISTS (SELECT 1 FROM entries.movie_metadata WHERE movie_code = v_base_code
                           UNION ALL
                           SELECT 1 FROM entries.series_metadata WHERE series_code = v_base_code) THEN
                    SELECT COALESCE(MAX(CAST(SUBSTRING(movie_code FROM '-([0-9]+)$') AS INTEGER)), 0) + 1
                      INTO v_next_num FROM entries.movie_metadata
                     WHERE movie_code ~ ('^' || v_base_code || '-[0-9]+$');
                    NEW.movie_code := v_base_code || '-' || COALESCE(v_next_num, 1);
                ELSE
                    NEW.movie_code := v_base_code;
                END IF;
            END IF;

        ELSIF TG_TABLE_NAME = 'series_metadata' THEN
            IF NEW.series_code IS NULL OR TRIM(NEW.series_code) = '' THEN
                v_clean_title := REGEXP_REPLACE(TRIM(NEW.title), '^\s*(the|a|an)\s+', '', 'i');
                v_clean_title := REGEXP_REPLACE(v_clean_title, '[^a-zA-Z0-9]', '', 'g');
                v_base_prefix := UPPER(RPAD(LEFT(v_clean_title, 3), 3, 'X'));
                v_base_code   := v_base_prefix || '-' || RIGHT(NEW.year_released::TEXT, 2);

                -- Global Collision Check
                IF EXISTS (SELECT 1 FROM entries.series_metadata WHERE series_code = v_base_code
                           UNION ALL
                           SELECT 1 FROM entries.movie_metadata WHERE movie_code = v_base_code) THEN
                    SELECT COALESCE(MAX(CAST(SUBSTRING(series_code FROM '-([0-9]+)$') AS INTEGER)), 0) + 1
                      INTO v_next_num FROM entries.series_metadata
                     WHERE series_code ~ ('^' || v_base_code || '-[0-9]+$');
                    NEW.series_code := v_base_code || '-' || COALESCE(v_next_num, 1);
                ELSE
                    NEW.series_code := v_base_code;
                END IF;
            END IF;
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_process_series_metadata
BEFORE INSERT OR UPDATE ON entries.series_metadata
FOR EACH ROW EXECUTE FUNCTION entries.fn_process_metadata();

CREATE TRIGGER trg_process_movie_metadata
BEFORE INSERT OR UPDATE ON entries.movie_metadata
FOR EACH ROW EXECUTE FUNCTION entries.fn_process_metadata();

-- ====================================================================

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

-- ====================================================================

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

-- ============================================================

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
