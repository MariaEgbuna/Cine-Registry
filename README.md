# Cine Registry

I used to track what I watched using spreadsheets. Then, while I was learning SQL (specifically psql), I decided to try building something more useful with it. This started as a fun side project: a database that logs what I watch, when I start and finish it, and other details about each movie or show.

Later I took it further and added Python and the TMDB API. I use Python scripts to fetch metadata about whatever I'm about to watch, then stored procedures handle registering it in the database: genre, year released, year completed (for series), runtime, and other details like that.

---

## How It's Wired (ERD)

![Cine Registry ER Diagram](Images/ER%20Diagram.png)

| Table | What it stores | Role in the system |
|-------|---------------|-------------------|
| `dates_table` | A pre-generated calendar of dates | Every watch log points to a date in here. This way I can run date-based reports without writing messy joins every time. |
| `series_metadata` | One row per show: title, TMDB ID, genre array, total episodes, etc. | The master list of shows. Keeps me from adding the same show twice, and every series log points back to a row here. |
| `movie_metadata` | One row per film: title, TMDB ID, genre array, runtime, etc. | Same idea as series_metadata, just for movies. |
| `series_log` | One row per watch session for a show | Tracks which episode and season I watched, and when. Links back to series_metadata and dates_table. |
| `movie_log` | One row per movie watch | Tracks the watch date, whether it was a rewatch, and if I finished it. Links back to movie_metadata and dates_table. |

---

## Project Structure

```
Cine-Registry/
├── SQL/
│   ├── 01_schema.sql        -- Table definitions, constraints, and foreign keys
│   ├── 02_triggers.sql      -- PL/pgSQL trigger functions (status updates, audit logging, timestamps)
│   ├── 03_procedures.sql    -- Stored procedures used as the write API
│   └── 04_sample_data.sql   -- Test data and verification scripts
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
 
I made a decision early on that I wasn't going to write directly to any of the tables, no matter how tempting it is just to run an INSERT when I'm in a hurry. Everything has to go through a stored procedure written in PL/pgSQL. It felt like extra work at first, but it means every single write follows the same rules, whether it's coming from the Python pipeline, a manual query, or something I add later.
 
`add_metadata` is the starting point for anything new. Before a show or movie can appear in a watch log, it must exist in the metadata table, and this procedure handles that registration. I did this on purpose so that referential integrity isn't just something the database enforces through a foreign key constraint sitting quietly in the background. It's something the application itself is built around.

`series_watch` and `movie_watch` are both used to record a watch session, one for shows and one for movies. Both include rewatch detection: if I log something that's already in the log from a previous watch, the procedure creates a new record for that session but flags it as a rewatch.
 
### Automation via PL/pgSQL Triggers
 
Alongside the stored procedures, three trigger functions run in the background whenever certain things happen to the data, without me having to call them directly.
 
`fn_progress_protector` fires after a `series_log` update. It checks whether the number of episodes I've watched matches the total number of episodes of the show. If it does, the trigger sets the status to `Finished` and records the end date by itself (unless I choose to use a specific date instead). That's one less thing I have to remember to update manually every time I finish a series.
 
`fn_set_last_updated` fires whenever a row changes on any of the main tables. It stamps the exact time of the update, but it pulls that timestamp from the database server clock. That way, the timestamp stays accurate and consistent no matter what's written to the database, whether it's the Python pipeline or a manual edit.
 
Then there are the audit triggers, which only fire when a row gets deleted. Right before that row disappears, the trigger takes the data, converts it into JSONB, and writes it into a matching audit table, either `series_metadata_audit` or `movie_metadata_audit` depending on what was deleted. So if I ever delete something by mistake, the record still exists somewhere, and I can recover it.
 
### Python as the Data Pipeline
 
The last piece is a Python pipeline that I've kept private. Mostly because I don't feel like sharing it publicly. The script sits between the TMDB API and the database, and its whole job is to fetch metadata like genre, runtime, and episode counts for whatever I'm about to save to the database, clean that data up so it's actually usable, and then hand it off to the correct stored procedure to write it into the database.

---

## Docs

| Document | What it covers |
|----------|---------------|
| [Deployment & Setup Guide](Docs/getting_started.md) | Prerequisites, SQL execution order, and verification steps |
| [System Audit](Docs/system_audit.md) | Audit trigger design, data recovery workflow, and trigger health checks |
| [View Architecture & Indexing](Docs/view_indexing.md) | Analytical views for Power BI, GIN indexing for genre arrays, and materialized views for retrospective reports |

---

## Tech Stack

- **Database:** PostgreSQL 17
- **Database Language:** SQL / PL/pgSQL
- **Scripting:** Python 3 (private)
- **External API:** TMDB API (private pipeline)
- **Tooling:** DBeaver, VS Code
- **Visualisation:** Power BI
