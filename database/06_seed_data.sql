/* =====================================================================
   HostelHub | 06_seed_data.sql
   ---------------------------------------------------------------------
   RUN AS: HOSTELHUB, after 02 to 05.
   WHAT IT DOES: loads meaningful sample data. Because the triggers and
   procedures already exist, the seed data is VALIDATED by them too
   (e.g. a boy cannot be seeded into the girls' block).

   Resulting data set (approximate):
     APP_USERS        3   (1 admin, 2 wardens)
     STUDENTS        30   (16 male, 14 female)
     ROOM_TYPES       4
     HOSTEL_UNITS    22   (2 blocks, 4 floors, 16 rooms)
     BEDS            40
     ACADEMIC_TERMS   3
     ALLOCATIONS     24   (6 students left unallocated for the tests)
     MEAL_TYPES       3
     MEAL_LOG     ~4,200  (1 Sep to 26 Nov 2026)
     INVOICES        48   (Sep + Oct 2026; Nov is created by 09_billing_run.sql)
     PAYMENTS        42   (some invoices partly paid or unpaid on purpose)
     AUDIT_LOG       66

   Demo logins (the hashes below are bcrypt, cost 10):
     admin        / Admin@123     (ADMIN)
     warden.ali   / Warden@123    (WARDEN)
     warden.sana  / Warden@123    (WARDEN)
   ===================================================================== */

SET SERVEROUTPUT ON
SET DEFINE OFF
ALTER SESSION SET NLS_DATE_FORMAT = 'YYYY-MM-DD';

-- ---------------------------------------------------------------------
-- 1. Staff users
-- ---------------------------------------------------------------------
INSERT INTO app_users (username, password_hash, full_name, role) VALUES
  ('admin',       '$2b$10$M1FmDLuYgu1VPRx58CxuCuMzue8P8otm2C.8c9r8.edkWAId2/fwi', 'Hostel Manager',  'ADMIN');
INSERT INTO app_users (username, password_hash, full_name, role) VALUES
  ('warden.ali',  '$2b$10$DKKGvWXk0TJgJlBmURRNoecC02wG8rNkefcTiAMmtdFEQ8VgqdCN2', 'Ali Raza',        'WARDEN');
INSERT INTO app_users (username, password_hash, full_name, role) VALUES
  ('warden.sana', '$2b$10$DKKGvWXk0TJgJlBmURRNoecC02wG8rNkefcTiAMmtdFEQ8VgqdCN2', 'Sana Tariq',      'WARDEN');

-- ---------------------------------------------------------------------
-- 2. Students (roll_no, name, gender, email, phone, program, semester)
-- ---------------------------------------------------------------------
INSERT INTO students (roll_no, full_name, gender, email, phone, program, semester)
SELECT * FROM (
  SELECT '231001','Ahmed Khan','M','ahmed.khan@student.edu.pk','0300-1110001','BSIT',7 FROM dual UNION ALL
  SELECT '231002','Bilal Hussain','M','bilal.hussain@student.edu.pk','0300-1110002','BSCS',5 FROM dual UNION ALL
  SELECT '231003','Usman Tariq','M','usman.tariq@student.edu.pk','0300-1110003','BSIT',3 FROM dual UNION ALL
  SELECT '231004','Hamza Ali','M','hamza.ali@student.edu.pk','0300-1110004','BSSE',7 FROM dual UNION ALL
  SELECT '231005','Fahad Iqbal','M','fahad.iqbal@student.edu.pk','0300-1110005','BSCS',1 FROM dual UNION ALL
  SELECT '231006','Saad Ahmed','M','saad.ahmed@student.edu.pk','0300-1110006','BBA',3 FROM dual UNION ALL
  SELECT '231007','Zain Malik','M','zain.malik@student.edu.pk','0300-1110007','BSIT',5 FROM dual UNION ALL
  SELECT '231008','Talha Siddiqui','M','talha.siddiqui@student.edu.pk','0300-1110008','BSAI',1 FROM dual UNION ALL
  SELECT '231009','Hassan Raza','M','hassan.raza@student.edu.pk','0300-1110009','BSCS',7 FROM dual UNION ALL
  SELECT '231010','Omar Farooq','M','omar.farooq@student.edu.pk','0300-1110010','BSSE',3 FROM dual UNION ALL
  SELECT '231011','Ali Haider','M','ali.haider@student.edu.pk','0300-1110011','BSIT',1 FROM dual UNION ALL
  SELECT '231012','Shahzaib Butt','M','shahzaib.butt@student.edu.pk','0300-1110012','BBA',5 FROM dual UNION ALL
  SELECT '231013','Danish Nawaz','M','danish.nawaz@student.edu.pk','0300-1110013','BSAI',3 FROM dual UNION ALL
  SELECT '231014','Junaid Akram','M','junaid.akram@student.edu.pk','0300-1110014','BSCS',1 FROM dual UNION ALL
  SELECT '231015','Waleed Asif','M','waleed.asif@student.edu.pk','0300-1110015','BSIT',3 FROM dual UNION ALL
  SELECT '231016','Moiz Sheikh','M','moiz.sheikh@student.edu.pk','0300-1110016','BSSE',5 FROM dual UNION ALL
  SELECT '231017','Ayesha Noor','F','ayesha.noor@student.edu.pk','0300-1110017','BSIT',7 FROM dual UNION ALL
  SELECT '231018','Fatima Zahra','F','fatima.zahra@student.edu.pk','0300-1110018','BSCS',5 FROM dual UNION ALL
  SELECT '231019','Hira Aslam','F','hira.aslam@student.edu.pk','0300-1110019','BSSE',3 FROM dual UNION ALL
  SELECT '231020','Maryam Javed','F','maryam.javed@student.edu.pk','0300-1110020','BSAI',1 FROM dual UNION ALL
  SELECT '231021','Sana Mirza','F','sana.mirza@student.edu.pk','0300-1110021','BBA',7 FROM dual UNION ALL
  SELECT '231022','Iqra Shah','F','iqra.shah@student.edu.pk','0300-1110022','BSIT',3 FROM dual UNION ALL
  SELECT '231023','Amna Qureshi','F','amna.qureshi@student.edu.pk','0300-1110023','BSCS',1 FROM dual UNION ALL
  SELECT '231024','Mahnoor Abbas','F','mahnoor.abbas@student.edu.pk','0300-1110024','BSSE',5 FROM dual UNION ALL
  SELECT '231025','Zainab Rehman','F','zainab.rehman@student.edu.pk','0300-1110025','BSIT',5 FROM dual UNION ALL
  SELECT '231026','Laiba Saeed','F','laiba.saeed@student.edu.pk','0300-1110026','BSAI',3 FROM dual UNION ALL
  SELECT '231027','Rabia Anwar','F','rabia.anwar@student.edu.pk','0300-1110027','BBA',1 FROM dual UNION ALL
  SELECT '231028','Kinza Yousaf','F','kinza.yousaf@student.edu.pk','0300-1110028','BSCS',7 FROM dual UNION ALL
  SELECT '231029','Areeba Khalid','F','areeba.khalid@student.edu.pk','0300-1110029','BSIT',1 FROM dual UNION ALL
  SELECT '231030','Noor Fatima','F','noor.fatima@student.edu.pk','0300-1110030','BSSE',3 FROM dual
);

-- ---------------------------------------------------------------------
-- 3. Room types (rent in PKR per month)
-- ---------------------------------------------------------------------
INSERT INTO room_types (name, beds_per_room, monthly_rent, description) VALUES ('Single', 1, 15000, 'Private room with study desk and attached bath');
INSERT INTO room_types (name, beds_per_room, monthly_rent, description) VALUES ('Double', 2, 11000, 'Shared by two students');
INSERT INTO room_types (name, beds_per_room, monthly_rent, description) VALUES ('Triple', 3,  9000, 'Shared by three students');
INSERT INTO room_types (name, beds_per_room, monthly_rent, description) VALUES ('Quad',   4,  7500, 'Economy room shared by four students');

-- ---------------------------------------------------------------------
-- 4. Hostel layout: BLOCK > FLOOR > ROOM
--    Block A = boys (M), Block B = girls (F); 2 floors each; 4 rooms per
--    floor: x01 Single, x02 Double, x03 Triple, x04 Quad.
-- ---------------------------------------------------------------------
INSERT INTO hostel_units (parent_unit_id, unit_type, unit_code, unit_name, gender_policy)
VALUES (NULL, 'BLOCK', 'A', 'Iqbal Block (Boys)', 'M');
INSERT INTO hostel_units (parent_unit_id, unit_type, unit_code, unit_name, gender_policy)
VALUES (NULL, 'BLOCK', 'B', 'Fatima Jinnah Block (Girls)', 'F');

-- Floors: A1, A2 under block A; B1, B2 under block B
INSERT INTO hostel_units (parent_unit_id, unit_type, unit_code, unit_name)
SELECT b.unit_id, 'FLOOR', b.unit_code || f.n, b.unit_code || ' Block, Floor ' || f.n
  FROM hostel_units b
 CROSS JOIN (SELECT LEVEL AS n FROM dual CONNECT BY LEVEL <= 2) f
 WHERE b.unit_type = 'BLOCK';

-- Rooms: A101..A104, A201..A204, B101..B104, B201..B204
INSERT INTO hostel_units (parent_unit_id, unit_type, unit_code, unit_name, room_type_id)
SELECT fl.unit_id, 'ROOM',
       fl.unit_code || '0' || rt.beds_per_room,        -- e.g. A1 + 0 + 3 = A103
       'Room ' || fl.unit_code || '0' || rt.beds_per_room,
       rt.room_type_id
  FROM hostel_units fl
 CROSS JOIN room_types rt
 WHERE fl.unit_type = 'FLOOR';

-- ---------------------------------------------------------------------
-- 5. Beds: one bed per place in the room, labelled A, B, C, D
-- ---------------------------------------------------------------------
INSERT INTO beds (room_unit_id, bed_label)
SELECT r.unit_id, CHR(64 + n.n)                        -- 1 -> 'A', 2 -> 'B', ...
  FROM hostel_units r
  JOIN room_types rt ON rt.room_type_id = r.room_type_id
  JOIN (SELECT LEVEL AS n FROM dual CONNECT BY LEVEL <= 6) n ON n.n <= rt.beds_per_room
 WHERE r.unit_type = 'ROOM';

-- Two beds are under maintenance (used by the failure test T04).
UPDATE beds SET status = 'MAINTENANCE'
 WHERE (room_unit_id, bed_label) IN (
       SELECT unit_id, 'D' FROM hostel_units WHERE unit_code = 'A204'
       UNION ALL
       SELECT unit_id, 'A' FROM hostel_units WHERE unit_code = 'B204');

-- ---------------------------------------------------------------------
-- 6. Academic terms (Fall 2026 is the current term)
-- ---------------------------------------------------------------------
INSERT INTO academic_terms (name, start_date, end_date, is_current) VALUES ('Spring 2026', DATE '2026-02-01', DATE '2026-06-30', 'N');
INSERT INTO academic_terms (name, start_date, end_date, is_current) VALUES ('Fall 2026',   DATE '2026-08-15', DATE '2027-01-31', 'Y');
INSERT INTO academic_terms (name, start_date, end_date, is_current) VALUES ('Spring 2027', DATE '2027-02-15', DATE '2027-06-30', 'N');

-- ---------------------------------------------------------------------
-- 7. Meal types (PKR per meal)
-- ---------------------------------------------------------------------
INSERT INTO meal_types (name, rate, serve_order) VALUES ('Breakfast', 120, 1);
INSERT INTO meal_types (name, rate, serve_order) VALUES ('Lunch',     220, 2);
INSERT INTO meal_types (name, rate, serve_order) VALUES ('Dinner',    200, 3);

COMMIT;

-- ---------------------------------------------------------------------
-- 8. Allocations for Fall 2026 (made on move-in day, 20 Aug 2026).
--    Inserted directly (not through pr_allocate_bed) so the historic
--    date can be set; trg_alloc_validate still checks every row.
--    Each pair is (student roll_no, room code + bed label).
-- ---------------------------------------------------------------------
DECLARE
  TYPE t_list IS TABLE OF VARCHAR2(20);
  v_rolls  t_list := t_list(
    -- 13 boys -> Block A
    '231001','231002','231003','231004','231005','231006','231007',
    '231008','231009','231010','231011','231012','231013',
    -- 11 girls -> Block B
    '231017','231018','231019','231020','231021','231022','231023',
    '231024','231025','231026','231027');
  v_beds   t_list := t_list(
    'A101-A','A102-A','A102-B','A103-A','A103-B','A103-C','A104-A',
    'A104-B','A104-C','A201-A','A202-A','A203-A','A204-A',
    'B101-A','B102-A','B102-B','B103-A','B103-B','B103-C','B104-A',
    'B104-B','B201-A','B202-A','B202-B');
  v_term_id     NUMBER;
  v_user_id     NUMBER;
  v_student_id  NUMBER;
  v_bed_id      NUMBER;
  v_alloc_id    NUMBER;
BEGIN
  SELECT term_id INTO v_term_id FROM academic_terms WHERE name = 'Fall 2026';
  SELECT user_id INTO v_user_id FROM app_users WHERE username = 'warden.ali';

  FOR i IN 1 .. v_rolls.COUNT LOOP
    SELECT student_id INTO v_student_id FROM students WHERE roll_no = v_rolls(i);

    SELECT b.bed_id INTO v_bed_id
      FROM beds b JOIN hostel_units r ON r.unit_id = b.room_unit_id
     WHERE r.unit_code || '-' || b.bed_label = v_beds(i);

    INSERT INTO allocations (client_request_id, student_id, bed_id, term_id, allocated_by, allocated_at)
    VALUES ('SEED-' || LPAD(i, 4, '0'), v_student_id, v_bed_id, v_term_id, v_user_id,
            TIMESTAMP '2026-08-20 09:00:00' + NUMTODSINTERVAL(i * 7, 'MINUTE'))
    RETURNING allocation_id INTO v_alloc_id;

    UPDATE beds SET status = 'OCCUPIED' WHERE bed_id = v_bed_id;

    INSERT INTO audit_log (user_id, action, client_request_id, table_name, record_id, details, logged_at)
    VALUES (v_user_id, 'ALLOCATE_SUCCESS', 'SEED-' || LPAD(i, 4, '0'), 'ALLOCATIONS', v_alloc_id,
            'student=' || v_student_id || ' bed=' || v_bed_id || ' term=' || v_term_id || ' (seed)',
            TIMESTAMP '2026-08-20 09:00:00' + NUMTODSINTERVAL(i * 7, 'MINUTE'));
  END LOOP;
  COMMIT;
  DBMS_OUTPUT.PUT_LINE(v_rolls.COUNT || ' allocations created');
END;
/

-- ---------------------------------------------------------------------
-- 9. Meal log: 1 Sep to 26 Nov 2026 for every resident.
--    A deterministic formula (no random numbers) decides who ate which
--    meal, so every run produces exactly the same data and the same
--    report results:
--      Breakfast 30-70% (varies by student), Lunch 60-80% on weekdays
--      and 50% on weekends, Dinner 90%.
--    Student 231013 (Danish Nawaz) went home for November, so he has no
--    November meals (used by the NOT EXISTS query in 08_queries.sql).
-- ---------------------------------------------------------------------
INSERT INTO meal_log (student_id, meal_type_id, meal_date, recorded_by, recorded_at)
SELECT a.student_id,
       mt.meal_type_id,
       d.meal_date,
       CASE WHEN s.gender = 'M' THEN (SELECT user_id FROM app_users WHERE username = 'warden.ali')
            ELSE                     (SELECT user_id FROM app_users WHERE username = 'warden.sana') END,
       CAST(d.meal_date AS TIMESTAMP) + NUMTODSINTERVAL(7 + mt.serve_order * 5, 'HOUR')
  FROM allocations a
  JOIN students s ON s.student_id = a.student_id
 CROSS JOIN meal_types mt
 CROSS JOIN (SELECT DATE '2026-09-01' + LEVEL - 1 AS meal_date
               FROM dual CONNECT BY LEVEL <= DATE '2026-11-26' - DATE '2026-09-01' + 1) d
 WHERE a.status = 'ACTIVE'
   AND NOT (s.roll_no = '231013' AND d.meal_date >= DATE '2026-11-01')
   AND MOD(a.student_id * 7 + (d.meal_date - DATE '2026-09-01') * 3 + mt.serve_order * 5, 10)
       < CASE mt.name
           WHEN 'Breakfast' THEN 3 + MOD(a.student_id, 5)          -- 30% to 70% depending on the student
           WHEN 'Lunch'     THEN CASE WHEN TO_CHAR(d.meal_date, 'DY', 'NLS_DATE_LANGUAGE=ENGLISH')
                                           IN ('SAT','SUN') THEN 5   -- weekends: 50%
                                      ELSE 6 + MOD(a.student_id, 3) END  -- weekdays: 60% to 80%
           ELSE 9                                                  -- dinner: 90%
         END;

COMMIT;

-- ---------------------------------------------------------------------
-- 10. Invoices for September and October 2026, made by the procedure
--     pr_generate_invoice (so the numbers come from the real billing
--     logic). November is billed later by 09_billing_run.sql.
-- ---------------------------------------------------------------------
DECLARE
  v_admin      NUMBER;
  v_invoice_id NUMBER;
  v_total      NUMBER;
  v_count      PLS_INTEGER := 0;
BEGIN
  SELECT user_id INTO v_admin FROM app_users WHERE username = 'admin';

  FOR m IN (SELECT DATE '2026-09-01' AS mon FROM dual UNION ALL
            SELECT DATE '2026-10-01'        FROM dual) LOOP
    FOR r IN (SELECT student_id FROM allocations WHERE status = 'ACTIVE' ORDER BY student_id) LOOP
      pr_generate_invoice(r.student_id, m.mon, v_invoice_id, v_total, v_admin);
      v_count := v_count + 1;
    END LOOP;
  END LOOP;

  -- make generated_at look like month-end billing
  UPDATE invoices SET generated_at = CAST(LAST_DAY(billing_month) AS TIMESTAMP) + INTERVAL '18' HOUR;
  COMMIT;
  DBMS_OUTPUT.PUT_LINE(v_count || ' invoices generated');
END;
/

-- ---------------------------------------------------------------------
-- 11. Payments. trg_payment_audit writes an AUDIT_LOG row for each one
--     and sets the invoice status to PARTIAL / PAID automatically.
--       September: everyone paid in full except 3 students who paid half
--       October  : 14 paid in full, 4 paid half, 6 have not paid yet
-- ---------------------------------------------------------------------
DECLARE
  v_methods sys.odcivarchar2list := sys.odcivarchar2list('CASH','BANK','CARD');
  v_amount  NUMBER;
  v_n       PLS_INTEGER := 0;
BEGIN
  FOR inv IN (SELECT i.invoice_id, i.billing_month, i.total_amount,
                     ROW_NUMBER() OVER (PARTITION BY i.billing_month ORDER BY i.student_id) AS rn,
                     CASE WHEN s.gender = 'M' THEN 'warden.ali' ELSE 'warden.sana' END AS warden
                FROM invoices i JOIN students s ON s.student_id = i.student_id
               ORDER BY i.billing_month, i.student_id) LOOP

    v_amount := NULL;
    IF inv.billing_month = DATE '2026-09-01' THEN
      v_amount := CASE WHEN inv.rn IN (5, 12, 20) THEN ROUND(inv.total_amount / 2) ELSE inv.total_amount END;
    ELSIF inv.rn <= 14 THEN
      v_amount := inv.total_amount;
    ELSIF inv.rn <= 18 THEN
      v_amount := ROUND(inv.total_amount / 2);
    END IF;                                   -- rn 19..24 in October: unpaid

    IF v_amount IS NOT NULL THEN
      INSERT INTO payments (invoice_id, amount, method, reference_no, paid_at, received_by)
      VALUES (inv.invoice_id, v_amount, v_methods(MOD(inv.rn, 3) + 1),
              'RCPT-' || TO_CHAR(inv.billing_month, 'YYMM') || '-' || LPAD(inv.rn, 3, '0'),
              CAST(ADD_MONTHS(inv.billing_month, 1) + 4 + MOD(inv.rn, 5) AS TIMESTAMP) + INTERVAL '11' HOUR,
              (SELECT user_id FROM app_users WHERE username = inv.warden));
      v_n := v_n + 1;
    END IF;
  END LOOP;
  COMMIT;
  DBMS_OUTPUT.PUT_LINE(v_n || ' payments recorded');
END;
/

-- ---------------------------------------------------------------------
-- 12. Row counts, so you can check the load worked.
-- ---------------------------------------------------------------------
SELECT 'APP_USERS' AS table_name, COUNT(*) AS row_count FROM app_users UNION ALL
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

PROMPT 06_seed_data.sql finished.
