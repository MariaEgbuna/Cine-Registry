# System Audit and Operational Logging

This document covers how the database protects itself: audit triggers that capture deleted data as JSONB snapshots, the recovery workflow for restoring lost records, timestamp automation, and how to verify that all triggers are active.

---

## 1. Data Recovery via Audit Triggers

When a row is deleted from a primary table, a `BEFORE DELETE` trigger fires and serializes the full row as a JSONB object into a corresponding audit table (`series_metadata_audit` or `movie_metadata_audit`). This means no deletion is truly permanent, the original record can always be reconstructed exactly as it was.

### Restoring a Deleted Record

If a show is accidentally deleted from `series_metadata`, find its snapshot in the audit table and re-insert it using `jsonb_populate_record`, which maps the stored JSONB back to the table's original row type:

```sql
INSERT INTO entries.series_metadata
SELECT * FROM jsonb_populate_record(
    NULL::entries.series_metadata,
    (SELECT original_data
     FROM entries.series_metadata_audit
     WHERE series_code = 'ENTER_CODE_HERE'
     LIMIT 1)
);
```

This restores the record with all original attributes intact, including GIN-indexed genre arrays and any foreign key values. The audit row itself is kept in place as a permanent log of the deletion event.

---

## 2. Trigger Health Check

You can verify that all triggers are correctly attached to their tables by querying `information_schema.triggers`. This is useful after any schema migration or if you suspect a trigger isn't firing.

```sql
SELECT
    event_object_table AS table_name,
    trigger_name,
    event_manipulation AS event
FROM information_schema.triggers
WHERE trigger_schema = 'entries'
ORDER BY table_name, event;
```

The output should list every trigger across every table in the `entries` schema. If a trigger is missing from the results, it was either not installed or was accidentally dropped -- re-run `02_triggers.sql` to restore it.

---

## 3. Automated Timestamp Logging

The `fn_set_last_updated` trigger fires automatically on every `UPDATE` to the main metadata and log tables. It writes the current database server timestamp to the `last_updated` column, accurate to the nanosecond.

This is intentionally handled at the database level rather than the application level, it means the timestamp is always reliable regardless of which tool or script made the change.

To verify timestamps are being recorded correctly:

```sql
SELECT title, series_code, last_updated
FROM entries.series_metadata
ORDER BY last_updated DESC
LIMIT 5;
```

---

## 4. The `fn_progress_protector` Trigger

This trigger fires after each insert or update to `series_log`. It compares `episodes_watched` against `total_episodes` in the linked `series_metadata` row and manages the watch status automatically.

| Status | Condition | Automated result |
|--------|-----------|-----------------|
| `Watching` | `episodes_watched` is less than `total_episodes` | Status stays as `Watching`; `end_date` remains null |
| `Finished` | `episodes_watched` equals `total_episodes` | Status updated to `Finished`; `end_date` set to current date |
| `Dropped` | Manually set via `series_watch` procedure | Status set to `Dropped`; `end_date` set to current date |
| `On-Hold` | Manually set via `series_watch` procedure | Status set to `On-Hold`; `end_date` remains null |

The `Dropped` and `On-Hold` states bypass the progress check and are set explicitly through the `series_watch` stored procedure rather than triggered automatically.
