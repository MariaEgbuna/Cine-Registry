# System Audit and Operational Logging

This document explains how I manage the database, including recovering lost data, watching for errors, and checking system health.

---

## 1. Data Recovery using Audit Logs

When I delete a record, the system uses a special rule to take a snapshot of that data. I save this in an audit table as a JSON file. This allows me to perfectly restore the data if I ever delete something by mistake.

### Restoring a Deleted Entry

If I accidentally delete a show, I can find the saved details in the `series_metadata_audit` table. I keep a simple script in my cheat sheet that takes those saved details and puts them back into the main database exactly as they were before.

``` SQL
INSERT INTO entries.series_metadata 
SELECT * FROM jsonb_populate_record(
    NULL::entries.series_metadata, 
    (SELECT original_data FROM entries.series_metadata_audit 
     WHERE series_code = 'ENTER_CODE_HERE' 
     LIMIT 1)
);
```

Result: The record is re-inserted into the primary registry, and all original attributes, including GIN-indexed arrays and foreign keys, are restored.

---

## 2. Trigger and Procedure Health Check

I use a system view to make sure everything in my database is running smoothly. By checking the system information, I can verify that all my automated rules are correctly connected to their tables. This ensures that the "brain" of my database is always active and guarding my data.

### Audit Query

``` SQL
SELECT 
    event_object_table AS table_name, 
    trigger_name, 
    event_manipulation AS event
FROM information_schema.triggers 
WHERE trigger_schema = 'entries';
```

---

## 3. Automated Date Stamping

Every time I change a record, a rule called `fn_set_last_updated` automatically records the time of that update down to the nanosecond.  Because the system clock creates this time, it is always accurate and does not depend on me typing it in. This keeps my history reliable and makes it easy for my Power BI reports to show exactly when my data changed.

### Timestamp Verification

``` SQL
SELECT title, series_code, last_updated 
FROM entries.series_metadata
ORDER BY last_updated DESC
LIMIT 5;
```

---

## 4. The "Progress Protector"

The `fn_progress_protector` rule handles the status of each show for me. By letting the database manage these changes, I do not have to update them myself.

| Current State | Condition | Automated Result |
| :--- | :--- | :--- |
| **Watching** | I have not finished all episodes. | Status is "Watching"; no end date. |
| **Finished** | I have watched every episode. | Status changes to "Finished"; current date is added. |
| **Dropped** | I manually stop the show. | Record closes; current date is added. |
| **On-Hold** | I manually pause the show. | Record stays open; no end date. |

---

*Operational Audit Version: 1.0.0*  
*Maintained by Maria*  
*Focus on Database Reliability & Integrity*
