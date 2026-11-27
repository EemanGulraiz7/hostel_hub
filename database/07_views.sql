/* =====================================================================
   HostelHub | 07_views.sql
   ---------------------------------------------------------------------
   RUN AS: HOSTELHUB
   Requirement: at least 3 views, including one multi-table report.
     v_bed_occupancy  MULTI-TABLE report: block, floor, room, room type,
                      bed, current allocation and student (6 tables)
     v_vacant_beds    beds a warden can allocate right now (used by the
                      Allocate Bed screen and the APEX report)
     v_student_dues   billed, paid and outstanding amount per student
   ===================================================================== */

-- ---------------------------------------------------------------------
-- v_bed_occupancy: one row per bed with its full location and, if the
-- bed is taken in the CURRENT term, who is in it.
-- The hierarchy is fixed at 3 levels, so a bed's room, floor and block
-- are found with three joins to HOSTEL_UNITS (aliases r, fl, blk).
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_bed_occupancy AS
SELECT b.bed_id,
       blk.unit_id        AS block_id,
       blk.unit_code      AS block_code,
       blk.unit_name      AS block_name,
       blk.gender_policy,
       fl.unit_id         AS floor_id,
       fl.unit_code       AS floor_code,
       r.unit_id          AS room_id,
       r.unit_code        AS room_code,
       rt.name            AS room_type,
       rt.monthly_rent,
       b.bed_label,
       r.unit_code || '-' || b.bed_label AS bed_code,
       b.status           AS bed_status,
       a.allocation_id,
       a.allocated_at,
       s.student_id,
       s.roll_no,
       s.full_name        AS student_name
  FROM beds b
  JOIN hostel_units r   ON r.unit_id   = b.room_unit_id
  JOIN hostel_units fl  ON fl.unit_id  = r.parent_unit_id
  JOIN hostel_units blk ON blk.unit_id = fl.parent_unit_id
  JOIN room_types   rt  ON rt.room_type_id = r.room_type_id
  LEFT JOIN allocations a
         ON a.bed_id  = b.bed_id
        AND a.status  = 'ACTIVE'
        AND a.term_id IN (SELECT term_id FROM academic_terms WHERE is_current = 'Y')
  LEFT JOIN students s ON s.student_id = a.student_id;

-- ---------------------------------------------------------------------
-- v_vacant_beds: only beds that can be allocated now.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_vacant_beds AS
SELECT bed_id, bed_code, block_code, block_name, gender_policy,
       floor_code, room_code, room_type, monthly_rent
  FROM v_bed_occupancy
 WHERE bed_status = 'AVAILABLE';

-- ---------------------------------------------------------------------
-- v_student_dues: money summary per student.
-- Invoices and payments are aggregated SEPARATELY before joining, so a
-- student with 2 invoices and 3 payments is not counted 6 times
-- (the classic "fan-out" mistake).
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_student_dues AS
SELECT s.student_id,
       s.roll_no,
       s.full_name,
       s.gender,
       NVL(i.invoice_count, 0)                       AS invoice_count,
       NVL(i.total_billed, 0)                        AS total_billed,
       NVL(p.total_paid, 0)                          AS total_paid,
       NVL(i.total_billed, 0) - NVL(p.total_paid, 0) AS outstanding,
       i.last_billing_month
  FROM students s
  LEFT JOIN (SELECT student_id,
                    COUNT(*)           AS invoice_count,
                    SUM(total_amount)  AS total_billed,
                    MAX(billing_month) AS last_billing_month
               FROM invoices
              GROUP BY student_id) i ON i.student_id = s.student_id
  LEFT JOIN (SELECT inv.student_id, SUM(pay.amount) AS total_paid
               FROM payments pay
               JOIN invoices inv ON inv.invoice_id = pay.invoice_id
              GROUP BY inv.student_id) p ON p.student_id = s.student_id;

PROMPT 07_views.sql finished: 3 views created.

-- Quick look at each view
SELECT block_code, room_code, bed_code, bed_status, roll_no, student_name
  FROM v_bed_occupancy
 ORDER BY bed_code
 FETCH FIRST 12 ROWS ONLY;

SELECT * FROM v_vacant_beds ORDER BY bed_code;

SELECT roll_no, full_name, invoice_count, total_billed, total_paid, outstanding
  FROM v_student_dues
 WHERE invoice_count > 0
 ORDER BY outstanding DESC;
