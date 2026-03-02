/* ================================================================================
-- 0. ENVIRONMENT SETUP
-- Purpose: Initialize the physical database and logical namespace.
================================================================================ */

-- Create Database (Note: In many environments, this must be run separately)
CREATE DATABASE media_vault;

-- Create Schema
CREATE SCHEMA IF NOT EXISTS cine_registry;

/* 
================================================================================
				CINE_REGISTRY DDL: SYSTEM RESET BLOCK
================================================================================
*/

--  Drop Tables
DROP TABLE IF EXISTS cine_registry.dates_table CASCADE;
DROP TABLE IF EXISTS cine_registry.series_metadata CASCADE;
DROP TABLE IF EXISTS cine_registry.series_metadata_audit CASCADE;
DROP TABLE IF EXISTS cine_registry.series_log CASCADE;
DROP TABLE IF EXISTS cine_registry.movies CASCADE;
DROP TABLE IF EXISTS cine_registry.movies_audit CASCADE;


/* 
================================================================================
							   1. DATES TABLE
================================================================================ 
*/
CREATE TABLE cine_registry.dates_table (
    date_key DATE PRIMARY KEY,
    date_year SMALLINT NOT NULL,
    month_num SMALLINT NOT NULL CHECK (month_num BETWEEN 1 AND 12),
    month_name VARCHAR(15) NOT NULL,
    month_short CHAR(3) NOT NULL,
    day_num SMALLINT NOT NULL CHECK (day_num BETWEEN 1 AND 31),
    day_of_week VARCHAR(15) NOT NULL,
    day_short CHAR(3) NOT NULL,
    day_of_week_index SMALLINT NOT NULL CHECK (day_of_week_index BETWEEN 0 AND 6),
    is_weekend BOOLEAN NOT NULL
);

INSERT INTO cine_registry.dates_table (date_key, date_year, month_num, month_name, month_short, day_num, day_of_week, day_short, day_of_week_index, is_weekend)
SELECT
    datum AS date_key,
    EXTRACT(YEAR FROM datum)::SMALLINT AS date_year,
    EXTRACT(MONTH FROM datum)::SMALLINT AS month_num,
    TRIM(TO_CHAR(datum, 'Month')) AS month_name,
    TO_CHAR(datum, 'Mon') AS month_short,
    EXTRACT(DAY FROM datum)::SMALLINT AS day_num,
    TRIM(TO_CHAR(datum, 'Day')) AS day_of_week,
    TO_CHAR(datum, 'Dy') AS day_short,
    (EXTRACT(ISODOW FROM datum) - 1)::SMALLINT AS day_of_week_index,
    EXTRACT(ISODOW FROM datum) IN (6, 7) AS is_weekend
FROM generate_series('2025-01-01'::DATE, '2029-12-31'::DATE, '1 day'::INTERVAL) AS datum;


/* 
================================================================================
   							2. SERIES METADATA
================================================================================
*/
CREATE TABLE cine_registry.series_metadata (
    series_id SERIAL,
    series_code VARCHAR(20) PRIMARY KEY,
    title VARCHAR(255) NOT NULL,
    country VARCHAR(100),
    year_released SMALLINT,
    year_completed SMALLINT,
    total_seasons SMALLINT,
    total_episodes SMALLINT,
    avg_runtime SMALLINT,
    genre TEXT[],
    platform TEXT,
    status VARCHAR(50) NOT NULL DEFAULT 'Returning' CHECK (status IN ('Returning', 'Ended', 'Cancelled', 'Limited', 'TBD')),
    seasons_pre_log SMALLINT NOT NULL DEFAULT 0,
    tmdb_id INTEGER UNIQUE,
    last_updated TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_genre ON cine_registry.series_metadata USING GIN (genre);
CREATE INDEX idx_platform ON cine_registry.series_metadata (platform);


/* 
================================================================================
							   3. SERIES LOG
================================================================================ 
*/
CREATE TABLE cine_registry.series_log (
    log_id SERIAL PRIMARY KEY,
    series_code VARCHAR(20) NOT NULL REFERENCES cine_registry.series_metadata(series_code) ON DELETE RESTRICT ON UPDATE CASCADE,
    start_date DATE NOT NULL REFERENCES cine_registry.dates_table(date_key) ON DELETE RESTRICT ON UPDATE CASCADE,
    end_date DATE REFERENCES cine_registry.dates_table(date_key) ON DELETE RESTRICT ON UPDATE CASCADE,
    season_no SMALLINT NOT NULL,
    total_episodes SMALLINT NOT NULL,
    episodes_watched SMALLINT NOT NULL DEFAULT 0,
    watch_type VARCHAR(30) CHECK (watch_type IN ('Background', 'Weekly', 'Binge', 'All-Nighter', 'One-a-Day', 'Batch', 'Casual')),
    watch_status VARCHAR(20) NOT NULL CHECK (watch_status IN ('Watching','Finished','On-Hold','Dropped')),
    is_rewatch BOOLEAN NOT NULL DEFAULT FALSE,
    rating NUMERIC(3,1) CHECK (rating > 0 AND rating <= 10),
    review TEXT,
    last_updated TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT check_dates CHECK (end_date IS NULL OR end_date >= start_date),
    CONSTRAINT limit_episodes_watched CHECK (episodes_watched <= total_episodes)
);

CREATE INDEX idx_series_log_code ON cine_registry.series_log (series_code);
CREATE INDEX idx_series_log_status ON cine_registry.series_log (watch_status);
CREATE INDEX idx_series_log_dates ON cine_registry.series_log (start_date, end_date);


/* 
================================================================================
   								4. MOVIES
================================================================================ 
*/
CREATE TABLE cine_registry.movies (
    log_id SERIAL PRIMARY KEY,
    movie_id TEXT NOT NULL,
    date_watched DATE NOT NULL DEFAULT CURRENT_DATE REFERENCES cine_registry.dates_table(date_key) ON DELETE RESTRICT ON UPDATE CASCADE,
    movie_title VARCHAR(255) NOT NULL,
    year_released SMALLINT,
    country VARCHAR(100),
    genre TEXT[],
    runtime SMALLINT,
    rating NUMERIC(3,1) CHECK (rating > 0 AND rating <= 10),
    review  TEXT,
    is_rewatch BOOLEAN NOT NULL DEFAULT FALSE,
    last_updated TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    completion_status TEXT DEFAULT 'Finished' CHECK (completion_status IN ('Finished', 'Skimmed', 'Dropped')),
    tmdb_id INTEGER
);

CREATE INDEX idx_movie_genre ON cine_registry.movies USING GIN (genre);
CREATE INDEX idx_movies_country ON cine_registry.movies (country);


/* 
================================================================================
  							 5. AUDIT SYSTEM
================================================================================ 
*/
CREATE TABLE cine_registry.series_metadata_audit (
    audit_id BIGSERIAL PRIMARY KEY,
    series_code VARCHAR(20),
    title TEXT,
    deleted_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    deleted_by TEXT NOT NULL DEFAULT CURRENT_USER,
    original_data JSONB
);

CREATE TABLE cine_registry.movies_audit (
    audit_id BIGSERIAL PRIMARY KEY,
    log_id INT,
    movie_id TEXT,
    movie_title TEXT,
    deleted_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    deleted_by TEXT NOT NULL DEFAULT CURRENT_USER,
    original_data JSONB
);
