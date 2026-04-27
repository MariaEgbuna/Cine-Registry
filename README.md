# A Database with a Brain

My database, called Cine Registry, is built using PostgreSQL. It makes tracking my movies and shows easy by doing the hard work for me. It uses smart rules to automatically update my watch status and keep track of my binge-watching habits. Instead of keeping messy manual records, I now have one strong and reliable place for all my data.

---
## The Architecture

I organized my data into three specific areas:

- Registry: Stores permanent details like titles, years, and directors.
- Watchlogs: Records my activity, including watch dates, ratings, and rewatch status.
- Archive: Acts as a backup "black box" that saves copies of any deleted data to keep my history safe.

### How it's wired (ERD)

![Cine_Registry ER Diagram](Images/ER%20Diagram.png)

| Component   | Role   | Why it exists |
| :---   | :---   | :--- |
| **`dates_table`**   | The Calendar   | A central timeline for all temporal and seasonal analysis. |
| **`series_metadata`**   | The Show Catalog   | A unique registry for every show, preventing data duplication. |
| **`series_log`**   | The Session Tracker   | Where the daily "watching" happens, linked back to the metadata. |
| **`movies`**   | The Film Vault   | Individual movie entries mapped to the central calendar. |

### The Logic Behind the Design

- **Series Normalization**: By using a 1:N relationship between `series_metadata` and `series_log`, I can track multiple seasons or rewatches without ever having to re-type the show's title or genre.
- **Time-Stamping**: Every movie and series entry maps back to the dates_table. This ensures that when I run a "Yearly Wrapped" report, the data is perfectly aligned across the entire engine.
- **Audit & Traceability**: I built `series_metadata_audit`, `series_log_audit`, and `movies_audit` to act as a flight recorder. If a record is deleted, the system automatically captures the "who, what, and when" so no data ever truly vanishes into the void.
- **API Ready**: Both layers include a tmdb_id, allowing the engine to sync with external metadata providers seamlessly.

---

## Data Integrity and Automation

This "Database-First" approach eliminates manual status updates and minimizes human error.

### 1. The Progress Protector

I wrote a trigger called fn_progress_protector that acts as a logic gate. The moment episodes_watched matches total_episodes, the system automatically:

- Flips the watch_status to 'Finished'.

- Stamps the end_date to close the record.
This ensures my "Active" views stay clean without me having to manually "check off" a show.

### 2. The Procedural "Write API"

To maintain a clean state, I never use raw INSERT statements. Everything flows through a set of Stored Procedures that act as a private API for the database:

- **add_series**: My entry point for new content. This ensures a strict Parent-Child initialization; it populates the `series_metadata` (seasons, runtime, etc.) before a single episode is logged. Because of Foreign Key constraints, an "orphaned" watch session can't exist.

- **series_watch**: My "daily driver". It handles the logic of starting a new season, incrementing episode counts, and refreshing the last_updated timestamp to keep my dashboard accurate in real-time.

- **movie_watch**: This procedure features "Smart Detective" logic. It automatically scans for existing title and year combinations; if it finds a match, it links the entry and flags it as a Rewatch automatically.

### 3. The Python Gateway (Security)

To bridge the gap between the web and the database, I built Python utilities (movie_logger.py, add_series.py) that handle the external heavy lifting.

- Metadata Enrichment: The scripts fetch deep metadata (Genres, TMDB IDs, etc.) from the TMDB API before the database even sees the record.

- Decoupled Security: I use python-dotenv to manage credentials. API keys and DB passwords stay in a local .env file, keeping the GitHub repo safe and clean.

- Input Sanitization: Python performs the initial data cleanup, ensuring that only valid, formatted parameters reach the PostgreSQL procedures.

---

## Deployment, Logic, and Operations

Ready to deploy the schema? Follow the step-by-step instructions to set up your PostgreSQL environment and Python metadata gateway:

- [Deployment & Setup Guide](Docs/getting_started.md)

If you want to see the "why" behind the code, check out these deep dives in the docs folder:

- [System Audit](Docs/system_audit.md): My approach to disaster recovery via JSONB snapshots and keeping the engine healthy.
- [View Architecture & Indexing](Docs/view_indexing.md): A look at how I use GIN indexes for fast genre searching and tiered views for Power BI.

---

## Tech Stack

- **Language:** SQL / PL/pgSQL, Python
- **Database:** PostgreSQL 17
- **APIs:** TMDB API
- **Tooling:** DBeaver, VS Code

---

*Maintained by Maria  
Self-Taught Analyst & SQL Enthusiast*
