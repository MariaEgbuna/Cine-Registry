# Cine Registry

A personal movie and TV show tracking system built on PostgreSQL, with Python handling the data pipeline. Instead of maintaining manual lists, I built a proper relational database that automates the tedious parts: status updates, rewatch detection, audit logging, and feeds clean data directly into Power BI dashboards.

---

## How It's Wired (ERD)

![Cine Registry ER Diagram](Images/ER%20Diagram.png)

| Table | What it stores | Role in the system |
|-------|---------------|-------------------|
| `dates_table` | A pre-generated calendar of dates | Central time reference for all watch logs; enables date-based reporting without messy joins |
| `series_metadata` | One row per show: title, TMDB ID, genre array, total episodes, etc. | The master show registry; prevents duplicate entries and acts as the FK reference for all series logs |
| `movie_metadata` | One row per film: title, TMDB ID, genre array, runtime, etc. | The master film registry, same principle as series_metadata |
| `series_log` | One row per watch session for a show | Tracks episode progress, season, and watch date; links to both series_metadata and dates_table |
| `movie_log` | One row per movie watch | Tracks watch date, rewatch flag, and completion; links to movie_metadata and dates_table |

---

## Project Structure

```
Cine-Registry/
├── SQL/
│   ├── 01_schema.sql        -- Table definitions, constraints, and foreign keys
│   ├── 02_triggers.sql      -- PL/pgSQL trigger functions (status updates, audit logging, timestamps)
│   ├── 03_procedures.sql    -- Stored procedures used as the write API (add_series, movie_watch, etc.)
│   └── 04_sample_data.sql   -- Test data and verification scripts
├── Python/
│   ├── add_movie.py         -- Fetches movie details from TMDB and calls add_movie procedure
│   └── add_series.py        -- Fetches show details from TMDB and calls add_series procedure
├── Docs/
│   ├── getting_started.md   -- Setup and deployment guide
│   ├── system_audit.md      -- Audit logging, data recovery, and trigger health checks
│   └── view_indexing.md     -- Analytical views, GIN indexing, and materialized views
├── Images/
├── .gitignore
└── README.md
```

---

## How It Works

### Controlled Writes via Stored Procedures

I don't write directly to the tables. All data goes through PL/pgSQL stored procedures that act as a controlled write API:

- `add_series` / `add_movie`: Registers a new title in the metadata table before any watch log can reference it. This enforces referential integrity at the application level, not just through database constraints.
- `series_watch`: Handles the full lifecycle of a watch session: starts a new season record if needed, increments the episode counter, and triggers the status update logic.
- `movie_watch`: Includes rewatch detection. If the movie already exists in the log, it automatically links the new session to the original record and flags it as a rewatch.

### Automation via PL/pgSQL Triggers

Three trigger functions run automatically on data changes:

- `fn_progress_protector`: Fires after each `series_log` update. If `episodes_watched` matches `total_episodes`, it sets the status to `Finished` and stamps the end date. No manual updates needed.
- `fn_set_last_updated`: Fires on any row update across the main tables. Records the exact timestamp using the database server clock, independent of the application layer.
- Audit triggers: Fire on `DELETE` operations. Serialize the deleted row as JSONB and write it to a corresponding audit table (`series_metadata_audit`, `movie_metadata_audit`), enabling full data recovery.

### Python as the Data Pipeline

The Python scripts sit between the TMDB API and the database:

- Fetch structured metadata (genres, runtime, episode counts, TMDB IDs) from the TMDB API before any insert
- Validate and clean the incoming data
- Call the appropriate stored procedure with the cleaned payload
- Credentials are managed via a `.env` file (excluded from version control via `.gitignore`)

---

## Docs

| Document | What it covers |
|----------|---------------|
| [Deployment & Setup Guide](Docs/getting_started.md) | Prerequisites, SQL execution order, Python setup, and verification steps |
| [System Audit](Docs/system_audit.md) | Audit trigger design, data recovery workflow, and trigger health checks |
| [View Architecture & Indexing](Docs/view_indexing.md) | Analytical views for Power BI, GIN indexing for genre arrays, and materialized views for retrospective reports |

---

## Tech Stack

- **Database:** PostgreSQL 17
- **Database Language:** SQL / PL/pgSQL
- **Scripting:** Python 3
- **External API:** TMDB API
- **Tooling:** DBeaver, VS Code
