# Deployment and Setup Guide

This guide walks you through setting up the `cine_registry` database from scratch.

---

## Prerequisites

Before you start, make sure you have the following:

- **PostgreSQL 17** installed and running locally
- A database named `cine_registry` already created (`CREATE DATABASE cine_registry;`)
- A schema named `entries` created inside that database (`CREATE SCHEMA entries;`)
- A PostgreSQL client to run the SQL files: psql, DBeaver, or similar

---

## 1. Database Setup

Run the SQL files in this exact order. Each file depends on the one before it -- running them out of order will cause errors.

1. `01_schema.sql`: Creates all tables, constraints, and foreign key relationships.
2. `02_triggers.sql`: Installs the PL/pgSQL trigger functions (status automation, audit logging, timestamps).
3. `03_procedures.sql`: Installs the stored procedures used as the write API.
4. `04_sample_data.sql`: Loads test data and runs verification checks.

You can run these using `psql`, DBeaver, or any PostgreSQL client:

```bash
psql -U your_user -d cine_registry -f SQL/01_schema.sql
psql -U your_user -d cine_registry -f SQL/02_triggers.sql
psql -U your_user -d cine_registry -f SQL/03_procedures.sql
psql -U your_user -d cine_registry -f SQL/04_sample_data.sql
```

---

## 2. Verifying the Setup

The sample data script does more than just populate tables; it's designed to confirm that the core automation is working correctly. After running it, check the following:

**Test 1: ID generation**
Query `entries.series_metadata` and confirm every row has a unique `series_code` (e.g. `JUS-04`, `PEA-22`). These are generated automatically by the `fn_process_metadata` trigger on insert, no manual input required.

**Test 2: The `fn_progress_protector` trigger**
Every series log row in the sample data has `episodes_watched` equal to `total_episodes`. Query `entries.series_log` and confirm that all rows have `watch_status = 'Finished'` and a populated `end_date`. If either column is missing, the trigger did not fire correctly.

**Test 3: Rewatch detection**
Two movies in the sample data: Inglourious Basterds and Jurassic Park, are inserted with `is_rewatch = true`. Query `entries.movie_log` and confirm those two rows have the flag set. These test that the `fn_stamp_movie_rewatch` trigger correctly identifies prior watch sessions.

**Test 4: Audit logging**
Try deleting one row from `entries.series_metadata`, then query `entries.metadata_audit`. A record of the deleted row should appear there as a JSONB snapshot, confirming the `fn_audit_deletions` trigger is active.

---

## 3. Using the System

Once the SQL files are loaded and verified, the database is fully operational. Data is written directly through the stored procedures using any PostgreSQL client (psql, DBeaver, etc.), or through a private Python pipeline that integrates with the TMDB API to fetch and insert metadata automatically.
