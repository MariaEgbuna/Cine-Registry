# View Architecture and Indexing Strategy

This section explains how I organize my data for analysis and keep my reports running quickly.

---

## 1. The Analytical View Layer

I use "views", which are like saved searches, to combine my old show history with my new logs. This keeps my raw data clean and moves all the complex math into one place, making my dashboard much faster.

### v_series_dashboard: The Health Monitor

This is the main view I use for my Power BI reports. It shows me exactly how far along I am with my shows.

* **Calculated Progress**: It compares my old data (before I started using this system) with my new logs to give me a single completion percentage.
* **Status Mapping**: It automatically tags a show as "Caught Up" if I have finished all seasons, or "Backlog" if I still have more episodes to watch.

![Series Dashboard](<../Images/Series Dashboard.png>)

### v_resume_list: The Active Queue

This is a focused view I use every day. It hides shows that are "On-Hold" or "Dropped" so I can see only what I am currently watching. It also calculates the completion percentage for each show, helping me quickly identify exactly where I left off.

![Active Queue Dashboard](<../Images/Resume Dashboard.png>)

---

## 2. GIN Indexing for Genre Discovery

Instead of using a separate, complicated table to track genres, I store them in a simple text list (array) directly in the record. To make sure searches are instant, I use a GIN index. This is a special type of index that acts like the index in the back of a book, allowing the database to find specific genres without looking at every single row.

### The Performance Test

I used an `EXPLAIN ANALYZE` command to check the database. This shows me exactly how it performs a search. It proves that the database is using my index to find the data quickly instead of "brute-forcing" it, which means scanning every single row one by one.

``` SQL
EXPLAIN ANALYZE 
SELECT movie_title 
FROM the_receipts_sandbox.movies 
WHERE genre @> ARRAY['Sci-Fi']::text[];
```

![GIN index](<../Images/Gin Index Analyze.png>)

> The query plan confirms that the database uses a "Bitmap Index Scan." Because of the GIN index, it skips the irrelevant rows and finds the exact "Sci-Fi" records in under 1ms. This keeps my database structure simple and flat without slowing down as I add more entries to my registry.

---

## 3. Materialized Snapshots

For heavy reports, like my "Year in Review," I use Materialized Views. Think of these as permanent snapshots of a report. Instead of forcing the database to redo complex math every time I open my dashboard, it saves the final result directly to the disk.

* Why use Materialized Views? *

- Speed: Because the results are already saved, loading a full year of history is nearly instant.
- Indexing: I can add indexes directly to these views, like a B-Tree index on a movie ID, which makes finding specific lifetime stats as fast as looking up a single row in a table.

### mv_2025_movie_retrospective: Flattened History

This view is my 2025 time capsule. It combines all my watch logs with a date calendar so I can easily see how my viewing habits changed from month to month.

![Movie Retrospective Data](../Images/2025%20mv.png)
> Insight: The 2025 Retrospective view does the "boring" work for me. It automatically gathers information like the month, whether I finished a movie, and if I watched it again. It saves all of this into one simple, neat table so I do not have to do it manually.

---

*Document Version: 1.0.0*  
*Maintained by Maria*  
*Analytics Engineering Portfolio*
