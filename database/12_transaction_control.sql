/* =====================================================================
   HostelHub | 12_transaction_control.sql
   ---------------------------------------------------------------------
   RUN AS: HOSTELHUB (run it in SQL Developer with F5 / "Run Script",
   or in SQL*Plus, so each statement's output is visible).
   Demonstrates COMMIT, SAVEPOINT and ROLLBACK (requirement area
   "Administration"). Note: ROLLBACK undoes uncommitted work in ONE
   session; it is NOT a backup. The logical backup/restore with Data
   Pump is a separate exercise in M4.

   Story: the warden puts the vacant beds of floor B2 under maintenance
   for painting. By mistake they then run an UPDATE without the floor
   filter, which would also hit every bed in the hostel. They roll back
   to the savepoint, keep the correct change and COMMIT. At the end the
   beds are made AVAILABLE again so the other scripts still work.
   ===================================================================== */

SET SERVEROUTPUT ON
SET FEEDBACK ON
COLUMN floor_code FORMAT A6

PROMPT ===== Before: bed status per floor =====
SELECT floor_code, bed_status, COUNT(*) AS beds
  FROM v_bed_occupancy GROUP BY floor_code, bed_status ORDER BY floor_code, bed_status;

PROMPT ===== Step 1 (intended): vacant beds on floor B2 -> MAINTENANCE =====
UPDATE beds
   SET status = 'MAINTENANCE'
 WHERE status = 'AVAILABLE'
   AND room_unit_id IN (SELECT unit_id FROM hostel_units
                         WHERE parent_unit_id = (SELECT unit_id FROM hostel_units WHERE unit_code = 'B2'));

SAVEPOINT after_floor_b2;

PROMPT ===== Step 2 (MISTAKE): UPDATE without the floor filter =====
UPDATE beds SET status = 'MAINTENANCE' WHERE status = 'AVAILABLE';

SELECT floor_code, bed_status, COUNT(*) AS beds
  FROM v_bed_occupancy GROUP BY floor_code, bed_status ORDER BY floor_code, bed_status;

PROMPT ===== Step 3: ROLLBACK TO SAVEPOINT undoes only step 2 =====
ROLLBACK TO SAVEPOINT after_floor_b2;

SELECT floor_code, bed_status, COUNT(*) AS beds
  FROM v_bed_occupancy GROUP BY floor_code, bed_status ORDER BY floor_code, bed_status;

PROMPT ===== Step 4: COMMIT makes step 1 permanent =====
COMMIT;

PROMPT ===== Step 5: a full ROLLBACK (no savepoint) undoes everything since the last COMMIT =====
DELETE FROM meal_log WHERE meal_date = DATE '2026-11-26';
SELECT COUNT(*) AS meals_on_26_nov FROM meal_log WHERE meal_date = DATE '2026-11-26';
ROLLBACK;
SELECT COUNT(*) AS meals_on_26_nov FROM meal_log WHERE meal_date = DATE '2026-11-26';

PROMPT ===== Step 6: painting finished, put floor B2 beds back to AVAILABLE and COMMIT =====
UPDATE beds
   SET status = 'AVAILABLE'
 WHERE status = 'MAINTENANCE'
   AND bed_id NOT IN (SELECT b.bed_id FROM beds b JOIN hostel_units r ON r.unit_id = b.room_unit_id
                       WHERE r.unit_code || '-' || b.bed_label IN ('A204-D', 'B204-A'))   -- the two seeded maintenance beds stay
   AND room_unit_id IN (SELECT unit_id FROM hostel_units
                         WHERE parent_unit_id = (SELECT unit_id FROM hostel_units WHERE unit_code = 'B2'));
COMMIT;

SELECT floor_code, bed_status, COUNT(*) AS beds
  FROM v_bed_occupancy GROUP BY floor_code, bed_status ORDER BY floor_code, bed_status;
