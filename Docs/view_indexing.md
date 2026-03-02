# View Architecture & Indexing Strategy

This document outlines the Cine Registry analytical layer and the indexing strategies used to keep queries and dashboard fast.

---

## 1. The Analytical View Layer

I use layered views to bridge my old show data with my live progress logs. This keeps my main tables clean and ensures that all the heavy math and logic stay in one central spot rather than cluttering up the database.

### v_series_dashboard: The "Health" Monitor

This is the primary source for Power BI. It calculates real-time completion percentages by joining series_metadata with the most recent entries in series_log.

* Logic: It reconciles the seasons_pre_log (legacy data) against current SQL logs to show true progress.
* Status Mapping: Automatically classifies shows as 'Caught Up' if seasons_completed >= total_seasons or 'Backlog' if there is still work to do.

![Series Dashboard](<../Images/Series Dashboard.png>)
> **Note:** This is the 'source of truth' for my reports. I built it to bridge the gap between my old records and new logs, so I can see exactly how much of a show is left without manually checking the episode counts.

### v_resume_list: The "Active" Queue

A focused view for daily use that filters out 'On-Hold' or 'Dropped' shows. It calculates the percent_complete for every active show, making it easy to see exactly where a session left off.

![Active Queue Dashboard](<../Images/Resume Dashboard.png>)
> **Note:** I call this my 'Daily Driver.' It cuts through the noise of my entire library to show me only what I'm currently watching, ranked by progress so I know exactly what to hit play on next.

---

## 2. GIN Indexing for Genre Discovery

Instead of a messy join table, I used a TEXT[] array for genres. To keep searches instant, I backed them with a GIN (Generalized Inverted Index).

### The Performance Test

I ran an EXPLAIN ANALYZE to see if the database was actually using the index or just brute-forcing the table.

``` SQL
-- Force the index for the test
SET enable_seqscan = off;

EXPLAIN ANALYZE 
SELECT movie_title 
FROM the_receipts_sandbox.movies 
WHERE genre @> ARRAY['Sci-Fi']::text[];
```

### The Result

![GIN index](<../Images/Gin Index Analyze.png>)

> As shown in the query plan, the database performs a Bitmap Index Scan. It skips the junk and hits the exact "Sci-Fi" records in under 1ms. This keeps the schema flat and simple without sacrificing speed as the registry grows.

---

## 3. Temporal Analytics with dates_table

I built the dates_table to act as a pre-computed "cheat sheet" for time. Instead of making the database calculate years, months, or weekends every time I run a report, I just join to this table for instant answers.

**Why go this route?**

* v_binge_patterns: This view joins my watch logs to the date dimension to see if my "binge spikes" actually line up with weekends or holidays.

* Weekend Logic: By using a simple is_weekend flag, I can feed clean data into Power BI to visualize "Binge Velocity"—basically, how much faster I watch shows on Saturdays vs. workdays.

![The Binge Patterns View](<../Images/Binge Patterns.png>)
> **Note:** Joining to a static table keeps things lightning-fast and lets me pull complex stats like *All Night Counts* or *Binge Span* without the performance hit of dynamic math.

---

## 4. Materialized Snapshots

For heavy historical reporting (like my "Year in Review" stats), I use Materialized Views. Think of these as high-performance snapshots. Instead of calculating complex math every time I open a dashboard, the database saves the final result to the disk.

**Why use Materialized Views?**  

* Speed: Because the data is physically stored, reading a year's worth of data is instantaneous.

* Indexing: I can actually add indexes to the view itself (like B-Tree indexes on movie_id), making lifetime aggregations feel like a single-row lookup.

### mv_2025_movie_retrospective: Flattened History

This view is my 2025 time capsule. It merges my watch logs with the date dimension so I can see exactly how my habits shifted month-to-month.

![Movie Retrospective Data](../Images/2025%20mv.png)
> Insight: The 2025 Retrospective view automates the "boring" parts of data prep, instantly pulling attributes like month_short, completion_status, and is_rewatch status into a single, flat table.

---

*Document Version: 1.0.0*  
*Maintained by Maria*  
*Analytics Engineering Portfolio*
