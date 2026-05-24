# View Architecture and Indexing Strategy

This document covers the analytical layer built on top of the raw tables: the views that Power BI connects to, the GIN index used for genre-based queries, and the materialized views used for retrospective reports.

---

## 1. Analytical Views

Rather than querying the raw log tables directly from Power BI, I built a view layer that consolidates the joins, calculations, and status logic into clean, flat outputs. This keeps the raw tables normalized and moves the complexity into one place.

### `v_series_dashboard`: Show Progress Monitor

The main view powering the series dashboard in Power BI. It joins `series_metadata` with `series_log` and calculates:

- A single `completion_percentage` that accounts for both pre-system history (manually entered backlog data) and new log entries
- A derived status tag: `Caught Up` if all available seasons are finished, `Backlog` if episodes remain

![Series Dashboard](../Images/Series%20Dashboard.png)

### `v_resume_list`: Active Watch Queue

A focused daily-use view that filters out `On-Hold` and `Dropped` shows, leaving only what's currently active. It also calculates the per-show completion percentage so I can see at a glance exactly where I left off in each series.

![Resume Dashboard](../Images/Resume%20Dashboard.png)

---

## 2. GIN Indexing for Genre Queries

Genres are stored as a PostgreSQL text array directly on each metadata row (e.g., `ARRAY['Drama', 'Thriller']`), rather than in a separate junction table. This keeps the schema flat and simple.

The trade-off is that array columns aren't natively supported by standard B-Tree indexes. To keep genre-based lookups fast, I created a **GIN (Generalized Inverted Index)** on the `genre` column. A GIN index works like the index at the back of a book, it maps each individual array element to the rows that contain it, so the database can find all rows matching a specific genre without scanning the entire table.

### Verifying the Index is Being Used

I used `EXPLAIN ANALYZE` to confirm the query planner is using the GIN index rather than falling back to a sequential scan:

```sql
EXPLAIN ANALYZE
SELECT movie_title
FROM entries.movie_metadata
WHERE genre @> ARRAY['Sci-Fi']::text[];
```

![GIN Index Analyze](../Images/Gin%20Index%20Analyze.png)

The query plan shows a **Bitmap Index Scan** on the GIN index, meaning the database resolves the `Sci-Fi` filter from the index alone before touching the table. On this dataset the query resolves in under 1ms.

---

## 3. Materialized Views for Retrospective Reports

For heavier aggregations -- like a full year of watch history, I use materialized views. Unlike regular views (which re-execute their query every time they're accessed), a materialized view stores the query result physically on disk. Loading a year's worth of watch history becomes a single table read rather than a repeated multi-table join.

I also add a B-Tree index on the materialized view's primary key column (`movie_id`), which makes point lookups for individual film statistics as fast as a single row fetch.

The materialized view needs to be refreshed manually after new data is added:

```sql
REFRESH MATERIALIZED VIEW entries.mv_2025_movie_retrospective;
```

### `mv_2025_movie_retrospective` -- 2025 Watch History

This materialized view joins `movie_log` with `dates_table` to produce a flat, pre-aggregated table of every movie watched in 2025. Each row includes the watch month, completion status, and rewatch flag, all pre-calculated so Power BI doesn't have to re-derive them on every report load.

![Movie Retrospective Data](../Images/2025%20mv.png)
