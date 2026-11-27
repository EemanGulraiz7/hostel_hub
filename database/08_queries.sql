/* =====================================================================
   HostelHub | 08_queries.sql
   ---------------------------------------------------------------------
   RUN AS: HOSTELHUB
   Part A  5 business queries (joins, subqueries, GROUP BY / HAVING)
   Part B  recursive / hierarchical queries on HOSTEL_UNITS
   Part C  basic CRUD on STUDENTS (insert, read, update, delete)
   Each query starts with the business question it answers.
   ===================================================================== */

SET LINESIZE 200
SET PAGESIZE 100
COLUMN block_name   FORMAT A28
COLUMN full_name    FORMAT A18
COLUMN unit_tree    FORMAT A34
COLUMN unit_path    FORMAT A26

/* ---------------------------------------------------------------------
   Q1  [JOIN + GROUP BY]
   "How many beds are vacant in each block, split by room type?"
   --------------------------------------------------------------------- */
SELECT blk.unit_name                                   AS block_name,
       rt.name                                         AS room_type,
       COUNT(*)                                        AS total_beds,
       SUM(CASE WHEN b.status = 'AVAILABLE' THEN 1 ELSE 0 END) AS vacant_beds,
       rt.monthly_rent
  FROM beds b
  JOIN hostel_units r   ON r.unit_id   = b.room_unit_id
  JOIN hostel_units fl  ON fl.unit_id  = r.parent_unit_id
  JOIN hostel_units blk ON blk.unit_id = fl.parent_unit_id
  JOIN room_types   rt  ON rt.room_type_id = r.room_type_id
 GROUP BY blk.unit_name, rt.name, rt.monthly_rent
 ORDER BY blk.unit_name, rt.monthly_rent DESC;

/* ---------------------------------------------------------------------
   Q2  [SUBQUERY]
   "Which students owe more than the average outstanding balance?"
   The inner query computes the average over students who were billed.
   --------------------------------------------------------------------- */
SELECT roll_no, full_name, total_billed, total_paid, outstanding
  FROM v_student_dues
 WHERE outstanding > (SELECT AVG(outstanding)
                        FROM v_student_dues
                       WHERE invoice_count > 0)
 ORDER BY outstanding DESC;

/* ---------------------------------------------------------------------
   Q3  [GROUP BY + HAVING]
   "Which floors are at least 50% occupied?" (helps decide which floor
   to open next).
   --------------------------------------------------------------------- */
SELECT fl.unit_code                                            AS floor_code,
       COUNT(*)                                                AS total_beds,
       SUM(CASE WHEN b.status = 'OCCUPIED' THEN 1 ELSE 0 END)  AS occupied,
       ROUND(100 * SUM(CASE WHEN b.status = 'OCCUPIED' THEN 1 ELSE 0 END) / COUNT(*), 1)
                                                               AS occupancy_pct
  FROM beds b
  JOIN hostel_units r  ON r.unit_id  = b.room_unit_id
  JOIN hostel_units fl ON fl.unit_id = r.parent_unit_id
 GROUP BY fl.unit_code
HAVING SUM(CASE WHEN b.status = 'OCCUPIED' THEN 1 ELSE 0 END) / COUNT(*) >= 0.5
 ORDER BY occupancy_pct DESC;

/* ---------------------------------------------------------------------
   Q4  [CORRELATED SUBQUERY with NOT EXISTS]
   "Which current residents had NO meals at all in November 2026?"
   (expected: 231013 Danish Nawaz, who went home for the month)
   --------------------------------------------------------------------- */
SELECT s.roll_no, s.full_name, v.bed_code
  FROM students s
  JOIN v_bed_occupancy v ON v.student_id = s.student_id
 WHERE NOT EXISTS (SELECT 1
                     FROM meal_log ml
                    WHERE ml.student_id = s.student_id
                      AND ml.meal_date >= DATE '2026-11-01'
                      AND ml.meal_date <  DATE '2026-12-01');

/* ---------------------------------------------------------------------
   Q5  [MULTI-TABLE JOIN + GROUP BY + ORDER BY / FETCH FIRST]
   "Who are the top 5 mess users of the current term, and what did
   their meals cost?"
   --------------------------------------------------------------------- */
SELECT s.roll_no,
       s.full_name,
       COUNT(*)                                             AS meals_taken,
       SUM(CASE WHEN mt.name = 'Breakfast' THEN 1 ELSE 0 END) AS breakfasts,
       SUM(CASE WHEN mt.name = 'Lunch'     THEN 1 ELSE 0 END) AS lunches,
       SUM(CASE WHEN mt.name = 'Dinner'    THEN 1 ELSE 0 END) AS dinners,
       SUM(mt.rate)                                         AS meal_cost
  FROM meal_log ml
  JOIN meal_types     mt ON mt.meal_type_id = ml.meal_type_id
  JOIN students       s  ON s.student_id    = ml.student_id
  JOIN academic_terms t  ON ml.meal_date BETWEEN t.start_date AND t.end_date
 WHERE t.is_current = 'Y'
 GROUP BY s.roll_no, s.full_name
 ORDER BY meals_taken DESC, meal_cost DESC
 FETCH FIRST 5 ROWS ONLY;


/* =====================================================================
   PART B: RECURSIVE / HIERARCHICAL QUERIES
   HOSTEL_UNITS points to itself (parent_unit_id), forming the tree
       Block  ->  Floor  ->  Room   (and BEDS hang off rooms)
   ===================================================================== */

/* ---------------------------------------------------------------------
   R1  [CONNECT BY]  Hostel tree with bed counts at every level.
     START WITH parent_unit_id IS NULL   -> begin at the blocks (roots)
     CONNECT BY PRIOR unit_id = parent_unit_id -> then each child
     LEVEL                -> 1 = block, 2 = floor, 3 = room
     SYS_CONNECT_BY_PATH  -> full path from the root, e.g. /A/A1/A103
     ORDER SIBLINGS BY    -> sort children inside each parent
   The WITH clause (unit_beds) first counts total / vacant beds under
   EVERY unit using a recursive WITH (see R2 for how that works).
   How to read the result: each block line shows totals for the whole
   block; indented lines drill down to floors and rooms, so you can see
   at a glance where the vacant beds are.
   --------------------------------------------------------------------- */
WITH descendants (ancestor_id, unit_id) AS (
       SELECT unit_id, unit_id FROM hostel_units          -- every unit is its own descendant
       UNION ALL
       SELECT d.ancestor_id, c.unit_id                    -- plus the children of its descendants
         FROM descendants d
         JOIN hostel_units c ON c.parent_unit_id = d.unit_id),
     unit_beds AS (
       SELECT d.ancestor_id AS unit_id,
              COUNT(b.bed_id) AS total_beds,
              COUNT(CASE WHEN b.status = 'AVAILABLE' THEN 1 END) AS vacant_beds
         FROM descendants d
         LEFT JOIN beds b ON b.room_unit_id = d.unit_id
        GROUP BY d.ancestor_id)
SELECT LEVEL                                                   AS lvl,
       LPAD(' ', (LEVEL - 1) * 4) || u.unit_type || ' ' || u.unit_code AS unit_tree,
       SYS_CONNECT_BY_PATH(u.unit_code, '/')                   AS unit_path,
       ub.total_beds,
       ub.vacant_beds,
       fn_occupancy_pct(u.unit_id)                             AS occupancy_pct,
       fn_occupancy_band(fn_occupancy_pct(u.unit_id))          AS band
  FROM hostel_units u
  JOIN unit_beds ub ON ub.unit_id = u.unit_id
 START WITH u.parent_unit_id IS NULL
CONNECT BY PRIOR u.unit_id = u.parent_unit_id
 ORDER SIBLINGS BY u.unit_code;

/* ---------------------------------------------------------------------
   R2  [RECURSIVE WITH, the SQL-standard form]
   Walk UP from every vacant bed to its block, to print a readable
   "address" for each vacant bed, e.g.
       Iqbal Block (Boys) > A Block, Floor 2 > Room A203 > Bed B
   Anchor member     : the bed's room (depth 1)
   Recursive member  : join to the parent of the previous row
   The recursion stops when parent_unit_id IS NULL (the block).
   --------------------------------------------------------------------- */
WITH up_path (bed_id, bed_label, unit_id, parent_unit_id, address, depth) AS (
       SELECT b.bed_id, b.bed_label, r.unit_id, r.parent_unit_id,
              CAST(r.unit_name AS VARCHAR2(400)), 1
         FROM beds b
         JOIN hostel_units r ON r.unit_id = b.room_unit_id
        WHERE b.status = 'AVAILABLE'
       UNION ALL
       SELECT p.bed_id, p.bed_label, u.unit_id, u.parent_unit_id,
              CAST(u.unit_name || ' > ' || p.address AS VARCHAR2(400)), p.depth + 1
         FROM up_path p
         JOIN hostel_units u ON u.unit_id = p.parent_unit_id)
SELECT bed_id, address || ' > Bed ' || bed_label AS vacant_bed_address
  FROM up_path
 WHERE parent_unit_id IS NULL                -- keep only the finished (block-level) rows
 ORDER BY bed_id;


/* =====================================================================
   PART C: CRUD ON STUDENTS (Create, Read, Update, Delete)
   The web app does the same with bind variables; here literals are used
   so the script runs on its own. The demo row is deleted at the end, so
   the data set is unchanged afterwards.
   ===================================================================== */

-- CREATE
INSERT INTO students (roll_no, full_name, gender, email, phone, program, semester)
VALUES ('239999', 'Demo Student', 'M', 'demo.student@student.edu.pk', '0300-0000000', 'BSIT', 1);

-- READ
SELECT student_id, roll_no, full_name, program, semester FROM students WHERE roll_no = '239999';

-- UPDATE
UPDATE students SET semester = 2, phone = '0311-2223334' WHERE roll_no = '239999';
SELECT student_id, roll_no, full_name, phone, semester FROM students WHERE roll_no = '239999';

-- DELETE
DELETE FROM students WHERE roll_no = '239999';
SELECT COUNT(*) AS demo_rows_left FROM students WHERE roll_no = '239999';

COMMIT;
