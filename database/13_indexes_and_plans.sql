/* =====================================================================
   HostelHub | 13_indexes_and_plans.sql
   ---------------------------------------------------------------------
   RUN AS: HOSTELHUB, after 00_run_all.sql (needs the seed data).
   Requirement (Optimization): at least 2 suitable indexes with a reason
   for each, and a documented BEFORE / AFTER query-plan comparison
   using EXPLAIN PLAN + DBMS_XPLAN.

   The two tuning indexes
   ----------------------
   IX1  ix_meal_date_type  ON meal_log (meal_date, meal_type_id)
        Business question: "How many breakfasts / lunches / dinners were
        served on a given day?" The mess manager asks this every day for
        kitchen planning, and the dashboard asks it for a date range.
        MEAL_LOG is the biggest table (~4,200 rows now, and it grows by
        about 90 rows every day). Its only existing index,
        uq_meal_once (student_id, meal_date, meal_type_id), starts with
        student_id, so a filter on the DATE alone cannot use it for a
        range scan: Oracle has to read the whole index or table.
        Putting meal_date first lets Oracle jump straight to one day.
        meal_type_id is added so the count per meal type is answered
        from the index alone (no table access at all).

   IX2  ix_students_upper_name  ON students (UPPER(full_name))
        Business question: the "Search students" screen of the website
        finds a student by the start of the name, case-insensitively:
          WHERE UPPER(full_name) LIKE UPPER(:q) || '%'
        A normal index on full_name cannot be used once the column is
        wrapped in UPPER(), so this is a FUNCTION-BASED index on exactly
        the expression the query uses. (A search with a LEADING wildcard,
        LIKE '%ali%', can never use a B-tree index, so the API should use
        prefix search for this to help.)

   What the script does for each index
     1. drop the index if it exists (so the script is re-runnable)
     2. gather statistics, EXPLAIN PLAN the query, show the plan (BEFORE)
     3. run the query once and show the real execution statistics
        (DBMS_XPLAN.DISPLAY_CURSOR ... 'ALLSTATS LAST': rows, buffers)
     4. create the index, gather statistics, repeat 2 and 3 (AFTER)
   Copy the BEFORE / AFTER plans into the report (section "Optimization")
   and fill in the comparison table in docs/indexes_and_plans.md.

   Note: DISPLAY_CURSOR reads V$SQL, which is why 01_create_user.sql
   grants SELECT_CATALOG_ROLE. If it prints "cannot fetch plan", the
   EXPLAIN PLAN output above it is still valid evidence.
   ===================================================================== */

-- SERVEROUTPUT must be OFF, or DISPLAY_CURSOR shows the DBMS_OUTPUT call
SET SERVEROUTPUT OFF
SET LINESIZE 200
SET PAGESIZE 200
SET FEEDBACK ON
COLUMN plan_table_output FORMAT A160

-- ---------------------------------------------------------------------
-- 0. Start clean: drop both tuning indexes if an earlier run left them
-- ---------------------------------------------------------------------
BEGIN
  FOR i IN (SELECT index_name FROM user_indexes
             WHERE index_name IN ('IX_MEAL_DATE_TYPE', 'IX_STUDENTS_UPPER_NAME')) LOOP
    EXECUTE IMMEDIATE 'DROP INDEX ' || i.index_name;
  END LOOP;
END;
/

-- Fresh optimizer statistics, so the optimizer sees the real row counts
EXEC DBMS_STATS.GATHER_SCHEMA_STATS(USER)

PROMPT
PROMPT =====================================================================
PROMPT IX1  meal_log (meal_date, meal_type_id)
PROMPT Query: meals served per meal type on 20-Nov-2026
PROMPT =====================================================================

PROMPT ----- IX1 BEFORE: EXPLAIN PLAN (expect a FULL scan of MEAL_LOG or of UQ_MEAL_ONCE)
EXPLAIN PLAN SET STATEMENT_ID = 'IX1_BEFORE' FOR
SELECT mt.name AS meal, COUNT(*) AS meals_served
  FROM meal_log ml
  JOIN meal_types mt ON mt.meal_type_id = ml.meal_type_id
 WHERE ml.meal_date = DATE '2026-11-20'
 GROUP BY mt.name;

SELECT plan_table_output
  FROM TABLE(DBMS_XPLAN.DISPLAY('PLAN_TABLE', 'IX1_BEFORE', 'TYPICAL'));

PROMPT ----- IX1 BEFORE: actual run statistics (look at the Buffers column)
SELECT /*+ GATHER_PLAN_STATISTICS IX1_BEFORE */ mt.name AS meal, COUNT(*) AS meals_served
  FROM meal_log ml
  JOIN meal_types mt ON mt.meal_type_id = ml.meal_type_id
 WHERE ml.meal_date = DATE '2026-11-20'
 GROUP BY mt.name;

SELECT plan_table_output
  FROM TABLE(DBMS_XPLAN.DISPLAY_CURSOR(NULL, NULL, 'ALLSTATS LAST'));

PROMPT ----- IX1: create the index
CREATE INDEX ix_meal_date_type ON meal_log (meal_date, meal_type_id);
EXEC DBMS_STATS.GATHER_TABLE_STATS(USER, 'MEAL_LOG', cascade => TRUE)

PROMPT ----- IX1 AFTER: EXPLAIN PLAN (expect INDEX RANGE SCAN on IX_MEAL_DATE_TYPE)
EXPLAIN PLAN SET STATEMENT_ID = 'IX1_AFTER' FOR
SELECT mt.name AS meal, COUNT(*) AS meals_served
  FROM meal_log ml
  JOIN meal_types mt ON mt.meal_type_id = ml.meal_type_id
 WHERE ml.meal_date = DATE '2026-11-20'
 GROUP BY mt.name;

SELECT plan_table_output
  FROM TABLE(DBMS_XPLAN.DISPLAY('PLAN_TABLE', 'IX1_AFTER', 'TYPICAL'));

PROMPT ----- IX1 AFTER: actual run statistics
SELECT /*+ GATHER_PLAN_STATISTICS IX1_AFTER */ mt.name AS meal, COUNT(*) AS meals_served
  FROM meal_log ml
  JOIN meal_types mt ON mt.meal_type_id = ml.meal_type_id
 WHERE ml.meal_date = DATE '2026-11-20'
 GROUP BY mt.name;

SELECT plan_table_output
  FROM TABLE(DBMS_XPLAN.DISPLAY_CURSOR(NULL, NULL, 'ALLSTATS LAST'));

PROMPT
PROMPT =====================================================================
PROMPT IX2  students (UPPER(full_name))   function-based index
PROMPT Query: website search "ayesha" -> UPPER(full_name) LIKE 'AYESHA%'
PROMPT =====================================================================

PROMPT ----- IX2 BEFORE: EXPLAIN PLAN (expect TABLE ACCESS FULL on STUDENTS)
EXPLAIN PLAN SET STATEMENT_ID = 'IX2_BEFORE' FOR
SELECT student_id, roll_no, full_name, program
  FROM students
 WHERE UPPER(full_name) LIKE 'AYESHA%';

SELECT plan_table_output
  FROM TABLE(DBMS_XPLAN.DISPLAY('PLAN_TABLE', 'IX2_BEFORE', 'TYPICAL'));

PROMPT ----- IX2 BEFORE: actual run statistics
SELECT /*+ GATHER_PLAN_STATISTICS IX2_BEFORE */ student_id, roll_no, full_name, program
  FROM students
 WHERE UPPER(full_name) LIKE 'AYESHA%';

SELECT plan_table_output
  FROM TABLE(DBMS_XPLAN.DISPLAY_CURSOR(NULL, NULL, 'ALLSTATS LAST'));

PROMPT ----- IX2: create the function-based index
CREATE INDEX ix_students_upper_name ON students (UPPER(full_name));
EXEC DBMS_STATS.GATHER_TABLE_STATS(USER, 'STUDENTS', cascade => TRUE)

PROMPT ----- IX2 AFTER: EXPLAIN PLAN (expect INDEX RANGE SCAN on IX_STUDENTS_UPPER_NAME)
EXPLAIN PLAN SET STATEMENT_ID = 'IX2_AFTER' FOR
SELECT student_id, roll_no, full_name, program
  FROM students
 WHERE UPPER(full_name) LIKE 'AYESHA%';

SELECT plan_table_output
  FROM TABLE(DBMS_XPLAN.DISPLAY('PLAN_TABLE', 'IX2_AFTER', 'TYPICAL'));

PROMPT ----- IX2 AFTER: actual run statistics
SELECT /*+ GATHER_PLAN_STATISTICS IX2_AFTER */ student_id, roll_no, full_name, program
  FROM students
 WHERE UPPER(full_name) LIKE 'AYESHA%';

SELECT plan_table_output
  FROM TABLE(DBMS_XPLAN.DISPLAY_CURSOR(NULL, NULL, 'ALLSTATS LAST'));

PROMPT ----- IX2 counter-example: a LEADING wildcard cannot use the index (still a FULL scan)
EXPLAIN PLAN SET STATEMENT_ID = 'IX2_WILDCARD' FOR
SELECT student_id, roll_no, full_name
  FROM students
 WHERE UPPER(full_name) LIKE '%ALI%';

SELECT plan_table_output
  FROM TABLE(DBMS_XPLAN.DISPLAY('PLAN_TABLE', 'IX2_WILDCARD', 'BASIC +PREDICATE'));

PROMPT
PROMPT ===== The two tuning indexes now in the schema =====
COLUMN index_name  FORMAT A24
COLUMN table_name  FORMAT A12
COLUMN column_expr FORMAT A40
SELECT i.index_name, i.table_name, i.index_type, i.distinct_keys, i.leaf_blocks
  FROM user_indexes i
 WHERE i.index_name IN ('IX_MEAL_DATE_TYPE', 'IX_STUDENTS_UPPER_NAME')
 ORDER BY i.index_name;

PROMPT 13_indexes_and_plans.sql finished.
