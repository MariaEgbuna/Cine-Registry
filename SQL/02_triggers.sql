/* ================================================================================
   							TRIGGER FUNCTIONS MASTER BACKUP
   ================================================================================
   Schema: cine_registry
   Description: Automated logic for ID generation, status protection, and auditing.
   ================================================================================ */

-- Drop Functions
DROP FUNCTION IF EXISTS cine_registry.fn_generate_unique_id() CASCADE;
DROP FUNCTION IF EXISTS cine_registry.fn_sanitize_registry_entries() CASCADE;
DROP FUNCTION IF EXISTS cine_registry.fn_progress_protector() CASCADE;
DROP FUNCTION IF EXISTS cine_registry.fn_set_last_updated() CASCADE;
DROP FUNCTION IF EXISTS cine_registry.fn_audit_metadata_deletion() CASCADE;
DROP FUNCTION IF EXISTS cine_registry.fn_audit_movie_deletion() CASCADE;
DROP FUNCTION IF EXISTS cine_registry.fn_clean_dates_logic();

/* ================================================================================
 1. ID GENERATION LOGIC
================================================================================
 DESCRIPTION:
    I designed this as the foundation of my registry to automate the creation of 
    standardized, unique identifiers. This ensures my primary keys remain 
    consistent and human-readable across both Movies and Series.

FUNCTION NAME: fn_generate_unique_id
   
 LOGIC:
        * 3-Character Prefixing: I built this to extract and clean titles, 
          intelligently ignoring articles like 'The', 'A', or 'An' to get to 
          the core name.
        * Year Suffixing: I append the last two digits of the release year to 
          provide immediate chronological context within the ID itself.
        * Collision Handling: I implemented a safeguard that scans both 
          registries for existing codes; if I hit a duplicate, it automatically 
          appends a numeric increment (e.g., -1, -2) to maintain uniqueness.
    - Series Branch: 
        * I enforce a strict Prefix-YY format specifically for the 
          series_metadata table to keep my show tracking organized.

 TABLES IMPACTED: series_metadata (series_code), movies (movie_id)
================================================================================*/

CREATE OR REPLACE FUNCTION cine_registry.fn_generate_unique_id()
RETURNS trigger
AS $function$
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
    -- MOVIES BRANCH
    IF TG_TABLE_NAME = 'movies' THEN
        SELECT movie_id INTO v_existing_id FROM cine_registry.movies
         WHERE movie_title = NEW.movie_title AND year_released = NEW.year_released LIMIT 1;
        IF v_existing_id IS NOT NULL THEN
            NEW.movie_id := v_existing_id;
            RETURN NEW;
        END IF;
        IF NEW.movie_id IS NOT NULL AND TRIM(NEW.movie_id) != '' THEN 
            RETURN NEW; 
        END IF;
        v_title       := NEW.movie_title;
        v_year        := RIGHT(NEW.year_released::TEXT, 2);
        v_clean_title := REGEXP_REPLACE(TRIM(v_title), '^\s*(the|a|an)\s+', '', 'i');
        v_clean_title := REGEXP_REPLACE(v_clean_title, '[^a-zA-Z0-9]', '', 'g');
        v_base_prefix := UPPER(RPAD(LEFT(v_clean_title, 3), 3, 'X'));
        v_base_code   := v_base_prefix || '-' || v_year;
        IF EXISTS (SELECT 1 FROM cine_registry.movies WHERE movie_id = v_base_code
                   UNION ALL
                   SELECT 1 FROM cine_registry.series_metadata WHERE series_code = v_base_code) THEN
            SELECT COALESCE(MAX(CAST(SUBSTRING(movie_id FROM '-([0-9]+)$') AS INTEGER)), 0) + 1
              INTO v_next_num FROM cine_registry.movies
             WHERE movie_id = v_base_code OR movie_id ~ ('^' || v_base_code || '-[0-9]+$');
            v_final_code := v_base_code || '-' || v_next_num;
        ELSE
            v_final_code := v_base_code;
        END IF;
        NEW.movie_id := v_final_code;
        RETURN NEW;

    -- SERIES BRANCH
    ELSIF TG_TABLE_NAME = 'series_metadata' THEN
        IF NEW.series_code IS NOT NULL AND TRIM(NEW.series_code) != '' THEN
            RETURN NEW;
        END IF;
        v_title       := NEW.title;
        v_year        := RIGHT(NEW.year_released::TEXT, 2);
        v_clean_title := REGEXP_REPLACE(TRIM(v_title), '^\s*(the|a|an)\s+', '', 'i');
        v_clean_title := REGEXP_REPLACE(v_clean_title, '[^a-zA-Z0-9]', '', 'g');
        v_base_prefix := UPPER(LEFT(v_clean_title, 3)); 
        v_base_code   := v_base_prefix || '-' || v_year;
        IF EXISTS (
            SELECT 1 FROM cine_registry.series_metadata WHERE series_code = v_base_code
            UNION ALL
            SELECT 1 FROM cine_registry.movies WHERE movie_id = v_base_code
        ) THEN
            SELECT COALESCE(
                MAX(CAST(SUBSTRING(series_code FROM '-([0-9]+)$') AS INTEGER)), 0
            ) + 1
              INTO v_next_num
              FROM cine_registry.series_metadata
             WHERE series_code LIKE (v_base_code || '-%');
            v_final_code := v_base_code || '-' || v_next_num;
        ELSE
            v_final_code := v_base_code;
        END IF;
        NEW.series_code := v_final_code;
        RETURN NEW;
    END IF;
    RETURN NEW;
END;
$function$ 
LANGUAGE plpgsql;

-- TRIGGER (Series Metadata Table)
CREATE TRIGGER trg_generate_series_id 
BEFORE INSERT ON cine_registry.series_metadata 
FOR EACH ROW EXECUTE FUNCTION cine_registry.fn_generate_unique_id();

-- TRIGGER (Movies Table)
CREATE TRIGGER trg_generate_movie_id 
BEFORE INSERT ON cine_registry.movies 
FOR EACH ROW EXECUTE FUNCTION cine_registry.fn_generate_unique_id();


/* ================================================================================
 2. DATA SANITIZATION & CLEANING
================================================================================
 DESCRIPTION:
    I implemented this layer to maintain high data quality. It standardizes my 
    text inputs and scrubs my arrays to ensure everything is perfectly formatted 
    before it's committed to the registry.

FUNCTION NAME: fn_sanitize_registry_entries

 LOGIC:
        * Whitespace Normalization: I use REGEXP_REPLACE here to trim leading/trailing 
          spaces and collapse internal multi-spaces into a single space, keeping 
          titles and names clean.
        * Country Standardization: I ensure the 'country' column is properly 
          trimmed to prevent duplicate entries caused by stray spaces.
        * Genre Array Scrubbing: I designed this to unnest my genre arrays, 
          filter out any NULLs or empty strings, and then re-aggregate the 
          cleaned elements back into a tidy list.
        * Platform Cleaning: I apply specific formatting rules to the platform 
          field so my streaming service labels remain consistent.

 TABLES IMPACTED: series_metadata, movies
================================================================================*/

CREATE OR REPLACE FUNCTION cine_registry.fn_sanitize_registry_entries()
RETURNS trigger
AS $function$
BEGIN
    -- Normalize whitespace based on table structure
    IF TG_TABLE_NAME = 'movies' THEN
        NEW.movie_title := TRIM(REGEXP_REPLACE(NEW.movie_title, '\s+', ' ', 'g'));
    ELSIF TG_TABLE_NAME = 'series_metadata' THEN
        NEW.title    := TRIM(REGEXP_REPLACE(NEW.title,    '\s+', ' ', 'g'));
        IF NEW.platform IS NOT NULL THEN
            NEW.platform := TRIM(NEW.platform);
        END IF;
    END IF;
    -- Standardize Country
    NEW.country := TRIM(NEW.country);
    -- Clean Genre Arrays
    IF NEW.genre IS NOT NULL AND CARDINALITY(NEW.genre) > 0 THEN
        NEW.genre := ARRAY(
            SELECT TRIM(g)
              FROM UNNEST(NEW.genre) AS g
             WHERE g IS NOT NULL
               AND TRIM(g) != ''
        );
    END IF;
    RETURN NEW;
END;
$function$ 
LANGUAGE plpgsql;

-- TRIGGER (SERIES_METADATA)
CREATE TRIGGER trg_sanitize_series 
BEFORE INSERT OR UPDATE ON cine_registry.series_metadata 
FOR EACH ROW EXECUTE FUNCTION cine_registry.fn_sanitize_registry_entries();

-- TRIGGER (MOVIES)
CREATE TRIGGER trg_sanitize_movies 
BEFORE INSERT OR UPDATE ON cine_registry.movies 
FOR EACH ROW EXECUTE FUNCTION cine_registry.fn_sanitize_registry_entries();

/* ================================================================================
 3. PROGRESS PROTECTOR
================================================================================
 DESCRIPTION:
    I built this as the core automation engine for my series tracking. It 
    autonomously manages the transitions between 'Watching', 'Finished', 
    'On-Hold', and 'Dropped' states based on my logging activity.

FUNCTION NAME: fn_progress_protector: 

 LOGIC:
        * Status Overrides: I designed this to explicitly respect 'On-Hold' and 
          'Dropped' statuses set by me, ensuring the counter never 
          accidentally forces a 'Finished' state.
        * Auto-Promotion: I programmed it to automatically flip the watch_status 
          to 'Finished' the exact moment my 'episodes_watched' matches the 
          'total_episodes' count.
        * Date Management: I use this to stamp the 'end_date' upon completion 
          or dropping, and I ensure it clears if I move a show back to 
          'Watching' or 'On-Hold'.
        * History Protection: I've added a safeguard so it only stamps the 
          'end_date' if it's currently NULL; I don't want to overwrite my 
          original completion dates during metadata updates.

 TABLES IMPACTED: series_log
================================================================================*/

CREATE OR REPLACE FUNCTION cine_registry.fn_progress_protector()
RETURNS trigger
AS $function$
BEGIN
    -- Status Signal Logic
    CASE NEW.watch_status
        WHEN 'On-Hold' THEN
            NEW.end_date := NULL;
            RETURN NEW;
        WHEN 'Dropped' THEN
            IF NEW.end_date IS NULL THEN NEW.end_date := CURRENT_DATE; END IF;
            RETURN NEW;
        WHEN 'Finished' THEN
            IF NEW.end_date IS NULL THEN NEW.end_date := CURRENT_DATE; END IF;
            RETURN NEW;
        ELSE
            NULL;
    END CASE;
    -- Auto-Promotion Logic
    IF NEW.episodes_watched = NEW.total_episodes AND NEW.total_episodes > 0 THEN
        NEW.watch_status := 'Finished';
        IF NEW.end_date IS NULL THEN NEW.end_date := CURRENT_DATE; END IF;
    ELSIF NEW.episodes_watched < NEW.total_episodes THEN
        NEW.watch_status := 'Watching';
        NEW.end_date     := NULL;
    END IF;
    RETURN NEW;
END;
$function$ 
LANGUAGE plpgsql;

-- TRIGGER (The Automatic "Finished" Flip)
CREATE TRIGGER trg_progress_protector 
BEFORE INSERT OR UPDATE ON cine_registry.series_log 
FOR EACH ROW EXECUTE FUNCTION cine_registry.fn_progress_protector();

/* ================================================================================
 4. AUDIT & TIMESTAMPING
================================================================================
 DESCRIPTION: 
    I built this layer to act as the "black box" for the registry. It captures 
    deleted records for emergency recovery and maintains a constant 'last_updated' 
    heartbeat across my core tables.

FUNCTION NAME(S): fn_set_last_updated, fn_audit_metadata_deletion, fn_audit_movie_deletion

 LOGIC:
    - : fn_set_last_updated
        * I use this as a reusable stamper to ensure the 'last_updated' column 
          always reflects the exact system time during any UPDATE operation.
    - fn_audit_metadata_deletion: 
        * Before I let a Series row vanish, this function archives the entire 
          record into a JSONB audit table so I never truly lose my history.
    - fn_audit_movie_deletion: 
        * I apply the same safety net for Movies, capturing the data in a 
          dedicated audit table prior to any permanent deletion.

 TABLES IMPACTED: series_metadata, movies, series_log, movies_audit, series_metadata_audit
================================================================================*/

CREATE OR REPLACE FUNCTION cine_registry.fn_set_last_updated()
RETURNS trigger
AS $function$
BEGIN
    NEW.last_updated := CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$function$ 
LANGUAGE plpgsql;

-- TRIGGER (SERIES_LOG): LAST UPDATE
CREATE TRIGGER trg_last_updated_series_log 
BEFORE UPDATE ON cine_registry.series_log 
FOR EACH ROW EXECUTE FUNCTION cine_registry.fn_set_last_updated();

-- TRIGGER (SERIES_METADATA): LAST UPDATE
CREATE TRIGGER trg_last_updated_series 
BEFORE UPDATE ON cine_registry.series_metadata 
FOR EACH ROW EXECUTE FUNCTION cine_registry.fn_set_last_updated();

-- TRIGGER (MOVIES): LAST UPDATE
CREATE TRIGGER trg_last_updated_movies 
BEFORE UPDATE ON cine_registry.movies 
FOR EACH ROW EXECUTE FUNCTION cine_registry.fn_set_last_updated();

-- **********************************************************************

CREATE OR REPLACE FUNCTION cine_registry.fn_audit_metadata_deletion()
RETURNS trigger
AS $function$
BEGIN
    INSERT INTO cine_registry.series_metadata_audit (series_code, title, original_data)
    VALUES (OLD.series_code, OLD.title, to_jsonb(OLD));
    RETURN OLD;
END;
$function$ 
LANGUAGE plpgsql;

-- TRIGGER (SERIES_METADATA): RECYCLE BIN
CREATE TRIGGER trg_audit_series_delete 
BEFORE DELETE ON cine_registry.series_metadata 
FOR EACH ROW EXECUTE FUNCTION cine_registry.fn_audit_metadata_deletion();

-- *********************************************************************

CREATE OR REPLACE FUNCTION cine_registry.fn_audit_movie_deletion()
RETURNS trigger
AS $function$
BEGIN
    INSERT INTO cine_registry.movies_audit (log_id, movie_id, movie_title, original_data)
    VALUES (OLD.log_id, OLD.movie_id, OLD.movie_title, to_jsonb(OLD));
    RETURN OLD;
END;
$function$ 
LANGUAGE plpgsql;

-- TRIGGER (MOVIES): RECYCLE BIN
CREATE TRIGGER trg_audit_movie_delete 
BEFORE DELETE ON cine_registry.movies 
FOR EACH ROW EXECUTE FUNCTION cine_registry.fn_audit_movie_deletion();


/* ================================================================================
 5. CALENDAR MANAGEMENT
================================================================================
 DESCRIPTION:
    I maintain this reference layer to ensure my time-series analysis and 
    binge-watching detection are pinpoint accurate. It keeps the dates_table 
    clean and standardized across all my reporting tools.

FUNCTION NAME: fn_clean_dates_logic

 LOGIC:
        * Text Normalization: I built this to strip the annoying whitespace from 
          day and month names that TO_CHAR often leaves behind during my data loads.
        * Weekend Logic: I automate the 'is_weekend' flag here, strictly following 
          ISO standards where Saturday (6) and Sunday (7) are the markers.
        * Indexing: I generate a custom 'day_of_week_index' (0-6) so that my 
          visualizations in Power BI actually sort by Monday-first, the way they should.

 TABLES IMPACTED: dates_table
================================================================================*/

CREATE OR REPLACE FUNCTION cine_registry.fn_clean_dates_logic()
RETURNS trigger
AS $function$
BEGIN
    -- Standardize existing text columns
    NEW.day_of_week := TRIM(TO_CHAR(NEW.date_key, 'Day'));
    NEW.month_name  := TRIM(TO_CHAR(NEW.date_key, 'Month'));
    
    -- Handle the new short columns
    NEW.day_short   := TO_CHAR(NEW.date_key, 'Dy');
    NEW.month_short := TO_CHAR(NEW.date_key, 'Mon');
    
    -- Refresh calculations based on the date_key
    NEW.is_weekend  := EXTRACT(ISODOW FROM NEW.date_key) IN (6, 7);
    NEW.day_of_week_index := (EXTRACT(ISODOW FROM NEW.date_key) - 1)::SMALLINT;
    
    -- Auto-fill Year/Month/Day numbers in case they were missed
    NEW.date_year := EXTRACT(YEAR FROM NEW.date_key)::SMALLINT;
    NEW.month_num := EXTRACT(MONTH FROM NEW.date_key)::SMALLINT;
    NEW.day_num   := EXTRACT(DAY FROM NEW.date_key)::SMALLINT;

    RETURN NEW;
END;
$function$ 
LANGUAGE plpgsql;

-- TRIGGER (DATES_TABLE)
CREATE TRIGGER trg_clean_dates 
BEFORE INSERT OR UPDATE ON cine_registry.dates_table 
FOR EACH ROW EXECUTE FUNCTION cine_registry.fn_clean_dates_logic();


/* ================================================================================
 6. SERIES PROGRESS VALIDATION
================================================================================
 DESCRIPTION:
    I designed this layer to safeguard the series_log against "future-dated" 
    entries. It ensures that any logged season strictly adheres to the actual 
    season count I've defined in the series_metadata table.

FUNCTION NAME: fn_check_season_limit

 LOGIC:
        * Metadata Bridge: I use this function to bridge the gap between tables, 
          using the 'series_code' from my log to look up 'total_seasons'.
        * Threshold Enforcement: I compare my current 'season_no' against the 
          master 'total_seasons' count to prevent data overflow.
        * Optimization: I marked this as STABLE so the engine knows it can 
          safely cache results during bulk logging sessions.

 TABLES IMPACTED: 
    - series_log: (I've bound this via the 'chk_season_bounds' constraint)
    - series_metadata: (Acts as the source of truth for season limits)
================================================================================*/

CREATE OR REPLACE FUNCTION cine_registry.fn_check_season_limit(series_code_input TEXT, season_no_input INT)
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 
        FROM cine_registry.series_metadata
        WHERE series_code = series_code_input 
        AND total_seasons >= season_no_input
    );
END;
$$ LANGUAGE plpgsql STABLE;

-- THE CONSTRAINT: This applies the function to the log table (series_log) to enforce season limits
ALTER TABLE cine_registry.series_log
ADD CONSTRAINT chk_season_bounds
CHECK (cine_registry.fn_check_season_limit(series_code, season_no));
