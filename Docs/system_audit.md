# System Audit & Operational Logging

This document shows how I handle the administrative side of the cine_registry engine, focusing on data recovery, trigger monitoring, and system health checks.

---

## 1. Data Recovery via JSONB Audit

The system uses AFTER DELETE triggers to take snapshots of records right before they are removed. This lets me perform a 1:1 restoration using the original_data JSONB column.

### Scenario: Restoring a Deleted Entry

When something is deleted, the metadata is captured in series_metadata_audit. I keep this recovery snippet in my v_cheat_sheet so I can restore a record with 100% fidelity:

``` SQL
INSERT INTO cine_registry.series_metadata 
SELECT * FROM jsonb_populate_record(
    NULL::cine_registry.series_metadata, 
    (SELECT original_data FROM cine_registry.series_metadata_audit 
     WHERE series_code = 'ENTER_CODE_HERE' 
     LIMIT 1)
);
```

Result: The record is re-inserted into the primary registry, and all original attributes, including GIN-indexed arrays and foreign keys, are restored.

---

## 2. Trigger & Procedure Health Check

To make sure the State Machine is active, I use a system audit view that queries the information_schema. This lets me verify that all defensive triggers are correctly bound to their tables.

### Audit Query

``` SQL
SELECT 
    event_object_table AS table_name, 
    trigger_name, 
    event_manipulation AS event
FROM information_schema.triggers 
WHERE trigger_schema = 'cine_registry';
```

### Operational Guardrails

* trg_series_progress_sync: Keeps watch status consistent with episodic progress.
* trg_audit_series_delete: Prevents permanent data loss via JSONB snapshotting.
* trg_clean_movies: Standardizes data entry using REGEXP_REPLACE.

---

## 3. Automated Metadata Stamping

The system tracks the *last_updated* column through the `fn_set_last_updated` trigger. This ensures the analytical layer in Power BI can accurately filter by the most recent changes.

### Timestamp Verification

``` SQL
SELECT title, series_code, last_updated 
FROM cine_registry
ORDER BY last_updated DESC
LIMIT 5;
```

Every INSERT or UPDATE produces a nanosecond-precise timestamp, ensuring the system clock, not user input, governs the record history.

---

## 4. The "Progress Protector" State Machine

To keep the `series_log` accurate, the `fn_progress_protector` trigger manages the lifecycle of a show. This moves state management away from the user and into the database.

| Current State | Condition | Automated Result |
| :--- | :--- | :--- |
| **Watching** | `episodes_watched < total_episodes` | `status = 'Watching'`, `end_date = NULL` |
| **Finished** | `episodes_watched == total_episodes` | `status = 'Finished'`, `end_date = CURRENT_DATE` |
| **Dropped** | User manual override | `end_date = CURRENT_DATE` (closes record) |
| **On-Hold** | User manual override | `end_date = NULL` (keeps record open) |

---

*Operational Audit Version: 1.0.0*  
*Maintained by Maria*  
*Focus on Database Reliability & Integrity*
