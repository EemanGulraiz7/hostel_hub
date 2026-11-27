/* =====================================================================
   HostelHub | 15_backup_check.sql
   ---------------------------------------------------------------------
   RUN AS: HOSTELHUB. Run it THREE times during the backup exercise
   (docs/backup_restore.md) and screenshot each result:
     1. right after the export   -> the "good" state that was backed up
     2. after 16_simulate_data_loss.sql -> payments are gone
     3. after the import         -> must match run 1 exactly
   It prints the row count of every table and a few money totals, so
   "the restore worked" is proved by numbers, not by eye.
   ===================================================================== */

SET SERVEROUTPUT ON SIZE UNLIMITED
SET LINESIZE 200
SET PAGESIZE 100
-- After a table is replaced by impdp, objects that depend on it (for
-- example fn_outstanding_balance reads PAYMENTS) are marked INVALID until
-- recompiled. This recompiles only the invalid ones; it changes nothing
-- when everything is already valid.
EXEC DBMS_UTILITY.COMPILE_SCHEMA(schema => USER, compile_all => FALSE)

SET FEEDBACK OFF
COLUMN table_name FORMAT A16
COLUMN check_name FORMAT A34
COLUMN value      FORMAT A20

PROMPT ===== Row count per table =====
SELECT 'APP_USERS' AS table_name, COUNT(*) AS row_count FROM app_users      UNION ALL
SELECT 'STUDENTS',       COUNT(*) FROM students       UNION ALL
SELECT 'ROOM_TYPES',     COUNT(*) FROM room_types     UNION ALL
SELECT 'HOSTEL_UNITS',   COUNT(*) FROM hostel_units   UNION ALL
SELECT 'BEDS',           COUNT(*) FROM beds           UNION ALL
SELECT 'ACADEMIC_TERMS', COUNT(*) FROM academic_terms UNION ALL
SELECT 'ALLOCATIONS',    COUNT(*) FROM allocations    UNION ALL
SELECT 'MEAL_TYPES',     COUNT(*) FROM meal_types     UNION ALL
SELECT 'MEAL_LOG',       COUNT(*) FROM meal_log       UNION ALL
SELECT 'INVOICES',       COUNT(*) FROM invoices       UNION ALL
SELECT 'PAYMENTS',       COUNT(*) FROM payments       UNION ALL
SELECT 'AUDIT_LOG',      COUNT(*) FROM audit_log;

PROMPT ===== Business totals =====
SELECT 'Total billed (invoices)'      AS check_name, TO_CHAR(NVL(SUM(total_amount), 0), 'FM999,999,990.00') AS value FROM invoices UNION ALL
SELECT 'Total received (payments)',   TO_CHAR(NVL(SUM(amount), 0), 'FM999,999,990.00') FROM payments UNION ALL
SELECT 'Total outstanding (v_student_dues)', TO_CHAR(NVL(SUM(outstanding), 0), 'FM999,999,990.00') FROM v_student_dues UNION ALL
SELECT 'Invalid objects',             TO_CHAR(COUNT(*)) FROM user_objects WHERE status = 'INVALID' UNION ALL
SELECT 'Checked at',                  TO_CHAR(SYSTIMESTAMP, 'DD-MON-YY HH24:MI:SS') FROM dual;

SET FEEDBACK ON
