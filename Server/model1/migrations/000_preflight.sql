-- -------------------------------------------------------------------------------------------------
-- @file       000_preflight.sql
-- @brief      Read-only preflight for the exact private Model 1.0 staging database
-- @details    Uses explicit schema names, independent of phpMyAdmin's current database context.
--             Returns one row only if the intended schema exists. Creates/changes/deletes nothing.
-- -------------------------------------------------------------------------------------------------
SELECT
    SCHEMA_NAME AS inspected_database,
    DEFAULT_CHARACTER_SET_NAME AS default_charset,
    DEFAULT_COLLATION_NAME AS default_collation,
    (SELECT COUNT(*) FROM information_schema.TABLES
     WHERE TABLE_SCHEMA = 'justirl2_plenact_m1_stage') AS tables_and_views,
    (SELECT COUNT(*) FROM information_schema.ROUTINES
     WHERE ROUTINE_SCHEMA = 'justirl2_plenact_m1_stage') AS routines,
    (SELECT COUNT(*) FROM information_schema.TRIGGERS
     WHERE TRIGGER_SCHEMA = 'justirl2_plenact_m1_stage') AS triggers,
    (SELECT COUNT(*) FROM information_schema.EVENTS
     WHERE EVENT_SCHEMA = 'justirl2_plenact_m1_stage') AS events
FROM information_schema.SCHEMATA
WHERE SCHEMA_NAME = 'justirl2_plenact_m1_stage';
