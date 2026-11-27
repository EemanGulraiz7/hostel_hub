/* =====================================================================
   HostelHub | 00_run_all.sql
   ---------------------------------------------------------------------
   Runs scripts 02 to 13 in the right order and writes everything to
   run_all.log (in the folder you started from), so you can send the log back when
   something fails.

   RUN AS: HOSTELHUB, after 01_create_user.sql was run once as SYSTEM.
     SQL*Plus / SQLcl : cd into the database folder, connect, then
                        @00_run_all.sql
     SQL Developer    : open this file and press F5 (Run Script)
   Safe to re-run: 02_schema.sql drops and recreates everything.
   ===================================================================== */

SET ECHO OFF
SET SERVEROUTPUT ON SIZE UNLIMITED FORMAT WRAPPED
SET LINESIZE 200
SET PAGESIZE 100
SET DEFINE OFF
SPOOL run_all.log

PROMPT ===== 02 schema =====
@@02_schema.sql
PROMPT ===== 03 functions =====
@@03_functions.sql
PROMPT ===== 04 procedures =====
@@04_procedures.sql
PROMPT ===== 05 triggers =====
@@05_triggers.sql
PROMPT ===== 06 seed data =====
@@06_seed_data.sql
PROMPT ===== 07 views =====
@@07_views.sql
PROMPT ===== 08 queries and recursive queries =====
@@08_queries.sql
PROMPT ===== 09 billing run (cursor, nested block, exceptions) =====
@@09_billing_run.sql
PROMPT ===== 10 analytics =====
@@10_analytics.sql
PROMPT ===== 11 tests =====
@@11_tests.sql
PROMPT ===== 12 COMMIT / SAVEPOINT / ROLLBACK =====
@@12_transaction_control.sql
PROMPT ===== 13 indexes and query plans (before / after) =====
@@13_indexes_and_plans.sql

PROMPT ===== Invalid objects (should be "no rows selected") =====
SELECT object_name, object_type FROM user_objects WHERE status = 'INVALID';

SPOOL OFF
PROMPT Done. Output saved to run_all.log
