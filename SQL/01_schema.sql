/* 
================================================================================
-- 0. ENVIRONMENT SETUP
================================================================================ 
*/

-- Create Database (Note: In many environments, this must be run separately)
-- CREATE DATABASE media_registry;

-- Create Schema
CREATE SCHEMA IF NOT EXISTS entries;
SET search_path TO entries, public;

/* 
================================================================================
                        CALENDAR ASPECT (DATES TABLE)
================================================================================ 
*/
CREATE TABLE entries.dates_table (
    date_key DATE PRIMARY KEY,
    date_year SMALLINT NOT NULL CHECK (date_year >= 2025),
    quarters SMALLINT NOT NULL CHECK (quarters BETWEEN 1 AND 4),
    month_num SMALLINT NOT NULL CHECK (month_num BETWEEN 1 AND 12),
    month_short CHAR(3) NOT NULL,
    day_short CHAR(3) NOT NULL,
    day_of_week_index SMALLINT NOT NULL CHECK (day_of_week_index BETWEEN 1 AND 7),
    is_weekend BOOLEAN NOT NULL
);

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
FROM generate_series('2025-01-01'::DATE, '2029-12-31'::DATE, '1 day'::INTERVAL) AS datum;

/* 
================================================================================
    SERIES ARCHITECTURE: METADATA, AUDIT, AND VIEWING LOGS
================================================================================
*/
-- 1. Series Metadata Table: The official registrar for show information
CREATE TABLE entries.series_metadata (
    series_id SERIAL PRIMARY KEY, 
    series_code VARCHAR(20) UNIQUE NOT NULL,
    title VARCHAR(255) NOT NULL,
    country VARCHAR(10), 
    year_released SMALLINT,
    year_completed SMALLINT,
    total_seasons SMALLINT,
    total_episodes SMALLINT,
    avg_runtime SMALLINT,
    genres TEXT[],
    platform VARCHAR(50),
    status VARCHAR(50) NOT NULL DEFAULT 'Returning' CHECK (status IN ('Returning', 'Ended', 'Cancelled', 'Limited', 'TBD')),
    seasons_pre_log SMALLINT NOT NULL DEFAULT 0,
    tmdb_id INTEGER UNIQUE,
    last_updated TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Optimization: GIN index for fast searching within the genres array
CREATE INDEX idx_genre ON entries.series_metadata USING GIN (genres);
CREATE INDEX idx_platform ON entries.series_metadata (platform);
CREATE INDEX idx_series_title ON entries.series_metadata (title);

-- 2. Audit System: Archives metadata deleted from the registry
CREATE TABLE entries.series_metadata_audit (
    audit_id BIGSERIAL PRIMARY KEY,
    series_id INT, 
    series_code VARCHAR(20),
    title TEXT,
    deleted_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    deleted_by TEXT NOT NULL DEFAULT CURRENT_USER,
    original_data JSONB
);

-- 3. Series Log: The activity tracker for individual season progress
CREATE TABLE entries.series_log (
    log_id SERIAL PRIMARY KEY,
    series_id INTEGER NOT NULL REFERENCES entries.series_metadata(series_id) ON DELETE RESTRICT,
    start_date DATE NOT NULL REFERENCES entries.dates_table(date_key) ON DELETE RESTRICT,
    end_date DATE REFERENCES entries.dates_table(date_key) ON DELETE RESTRICT,
    season_no SMALLINT NOT NULL,
    total_episodes SMALLINT NOT NULL,
    episodes_watched SMALLINT NOT NULL DEFAULT 0,
    watch_type VARCHAR(30) CHECK (watch_type IN ('Background', 'Binge', 'Casual', 'Batch', 'Daily Dose', 'Simulcast')),
    watch_status VARCHAR(20) NOT NULL CHECK (watch_status IN ('Watching','Finished','On-Hold','Dropped')),
    is_rewatch BOOLEAN NOT NULL DEFAULT FALSE,
    rating NUMERIC(3,1) CHECK (rating > 0 AND rating <= 10),
    review TEXT,
    last_updated TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT check_dates CHECK (end_date IS NULL OR end_date >= start_date),
    CONSTRAINT limit_episodes_watched CHECK (episodes_watched <= total_episodes)
);

-- Performance indices for frequent log filtering and sorting
CREATE INDEX idx_series_log_id ON entries.series_log (series_id);
CREATE INDEX idx_series_log_status ON entries.series_log (watch_status);
CREATE INDEX idx_series_log_dates ON entries.series_log (start_date, end_date);

-- 4. Audit System: Archives data deleted from the series_log
CREATE TABLE entries.series_log_audit (
    audit_id SERIAL PRIMARY KEY,
    log_id INTEGER,
    series_id INTEGER,
    season_no INTEGER,
    watch_status VARCHAR(20),
    is_rewatch BOOLEAN,
    operation TEXT, -- Captures 'UPDATE' or 'DELETE'
    changed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    changed_by TEXT DEFAULT CURRENT_USER
);

/* 
================================================================================
          MOVIE ARCHITECTURE: METADATA, AUDIT, AND VIEWING LOGS
================================================================================
*/
-- 1. Movie Metadata: The official catalog of films
CREATE TABLE entries.movie_metadata ( 
    movie_id SERIAL PRIMARY KEY,
    movie_code VARCHAR(20) UNIQUE NOT NULL,
    title TEXT NOT NULL,
    year_released SMALLINT,
    country VARCHAR(10),
    director TEXT NULL,
    runtime_mins SMALLINT,
    genres TEXT[],
    tmdb_id INTEGER UNIQUE,
    status VARCHAR(20) NOT NULL DEFAULT 'Backlog' CHECK (status IN ('Backlog', 'Logged')),
    last_updated TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- Optimized Indexing for rapid terminal filtering
CREATE INDEX idx_movie_metadata_country ON entries.movie_metadata (country);
CREATE INDEX idx_movie_metadata_year ON entries.movie_metadata (year_released);
CREATE INDEX idx_movie_genres ON entries.movie_metadata USING GIN (genres);

-- 2. Audit System: Archives removed film records
CREATE TABLE entries.movies_audit (
    audit_id      BIGSERIAL PRIMARY KEY,
    movie_id      INTEGER NOT NULL,
    movie_title   TEXT,
    deleted_at    TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    deleted_by    TEXT NOT NULL DEFAULT CURRENT_USER,
    original_data JSONB  
);

-- 3. Movie Log: Records of individual viewing sessions
CREATE TABLE entries.movie_log ( 
    log_id SERIAL PRIMARY KEY,
    movie_id INTEGER NOT NULL REFERENCES entries.movie_metadata(movie_id) ON UPDATE CASCADE ON DELETE RESTRICT,
    date_watched DATE DEFAULT CURRENT_DATE REFERENCES entries.dates_table(date_key),
    date_finished DATE REFERENCES entries.dates_table(date_key),
    rating NUMERIC(3, 1) CHECK (rating > 0 AND rating <= 10),
    is_rewatch BOOLEAN DEFAULT FALSE,
    completion_status TEXT DEFAULT 'Finished' CHECK (completion_status IN ('Finished', 'Skimmed', 'Dropped')),
    review TEXT,
    last_updated TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_no_rating_for_dropped CHECK ( (completion_status = 'Dropped' AND rating IS NULL) OR (completion_status != 'Dropped') ),
    CONSTRAINT chk_movie_finish_date CHECK (date_finished IS NULL OR date_finished >= date_watched)
);

-- Performance indexing for chronological history and metadata lookups
CREATE INDEX idx_movie_started_log_date ON entries.movie_log (date_watched);
CREATE INDEX idx_movie_finished_log_date ON entries.movie_log (date_finished);
