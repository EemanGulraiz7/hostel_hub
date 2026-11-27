/* =====================================================================
   HostelHub | 11_tests.sql
   ---------------------------------------------------------------------
   RUN AS: HOSTELHUB, after 02 to 10.
   Database-side test cases with Input / Expected / Actual / PASS-FAIL,
   printed with DBMS_OUTPUT so they can be copied into the report's test
   table. The script is RE-RUNNABLE: it first removes rows left by an
   earlier run (all test requests use client_request_id 'TEST-...').

     T01  constraints: accepted and rejected rows (UNIQUE, FK, CHECK, NOT NULL)
     T02  triggers: BEFORE validation and AFTER audit, accepted and rejected
     T03  successful multi-table procedure (pr_allocate_bed)
     T04  failed procedure leaves NO partial changes
     T09  retry-safe allocation: new request
     T10  retry-safe allocation: identical retry  -> REPLAYED, nothing new
     T11  retry-safe allocation: conflicting retry -> -20010, original untouched
     F1-3 functions, including NULL / unknown input

   Covered by other scripts: T05 analytics (10_analytics.sql), T06 to T08
   and T12 to T13 are web, MongoDB, index and backup tests (M3 / M4).

   Test data used (from 06_seed_data.sql):
     231014 Junaid Akram (M), 231015 Waleed Asif (M), 231016 Moiz Sheikh (M)
     and 231028 Kinza Yousaf (F) have NO bed; A202-B, A203-B, A203-C are
     vacant boys' beds; A204-D is under MAINTENANCE.
   ===================================================================== */

SET SERVEROUTPUT ON SIZE UNLIMITED FORMAT WRAPPED
SET LINESIZE 200
SET PAGESIZE 100
COLUMN client_request_id FORMAT A12
COLUMN bed               FORMAT A8
COLUMN action            FORMAT A18
COLUMN details           FORMAT A72

-- ---------------------------------------------------------------------
-- 0. Clean up rows left by a previous run of this script
-- ---------------------------------------------------------------------
BEGIN
  DELETE FROM payments
   WHERE invoice_id IN (SELECT invoice_id FROM invoices
                         WHERE allocation_id IN (SELECT allocation_id FROM allocations
                                                  WHERE client_request_id LIKE 'TEST-%'));
  DELETE FROM invoices
   WHERE allocation_id IN (SELECT allocation_id FROM allocations WHERE client_request_id LIKE 'TEST-%');
  UPDATE beds SET status = 'AVAILABLE'
   WHERE bed_id IN (SELECT bed_id FROM allocations
                     WHERE client_request_id LIKE 'TEST-%' AND status = 'ACTIVE');
  DELETE FROM allocations WHERE client_request_id LIKE 'TEST-%';
  DELETE FROM audit_log   WHERE client_request_id LIKE 'TEST-%';
  COMMIT;
END;
/

-- ---------------------------------------------------------------------
-- 1. The tests
-- ---------------------------------------------------------------------
DECLARE
  g_pass   PLS_INTEGER := 0;
  g_fail   PLS_INTEGER := 0;

  v_term_id     NUMBER;
  v_old_term    NUMBER;
  v_warden      NUMBER;
  v_alloc_id    NUMBER;
  v_alloc_id2   NUMBER;
  v_result      VARCHAR2(20);
  v_n1          NUMBER;
  v_n2          NUMBER;
  v_n3          NUMBER;
  v_txt         VARCHAR2(400);
  v_txt2        VARCHAR2(40);
  -- ids of the test students and beds (filled at the start)
  s_231014  NUMBER;  s_231015  NUMBER;  s_231016  NUMBER;  s_231028  NUMBER;
  b_A202B   NUMBER;  b_A203B   NUMBER;  b_A203C   NUMBER;  b_A204D   NUMBER;

  -- ---- helpers --------------------------------------------------------
  PROCEDURE report (p_id VARCHAR2, p_title VARCHAR2, p_input VARCHAR2,
                    p_expected VARCHAR2, p_actual VARCHAR2, p_pass BOOLEAN) IS
  BEGIN
    IF p_pass THEN g_pass := g_pass + 1; ELSE g_fail := g_fail + 1; END IF;
    DBMS_OUTPUT.PUT_LINE(RPAD(p_id, 6) || p_title);
    DBMS_OUTPUT.PUT_LINE('      Input   : ' || p_input);
    DBMS_OUTPUT.PUT_LINE('      Expected: ' || p_expected);
    DBMS_OUTPUT.PUT_LINE('      Actual  : ' || SUBSTR(REPLACE(p_actual, CHR(10), ' '), 1, 150));
    DBMS_OUTPUT.PUT_LINE('      Result  : ' || CASE WHEN p_pass THEN 'PASS' ELSE '*** FAIL ***' END);
    DBMS_OUTPUT.PUT_LINE('');
  END report;

  FUNCTION student (p_roll VARCHAR2) RETURN NUMBER IS
    v NUMBER;
  BEGIN
    SELECT student_id INTO v FROM students WHERE roll_no = p_roll;
    RETURN v;
  END student;

  FUNCTION bed (p_code VARCHAR2) RETURN NUMBER IS         -- 'A202-B' -> bed_id
    v NUMBER;
  BEGIN
    SELECT b.bed_id INTO v
      FROM beds b JOIN hostel_units r ON r.unit_id = b.room_unit_id
     WHERE r.unit_code || '-' || b.bed_label = p_code;
    RETURN v;
  END bed;

  FUNCTION bed_status (p_code VARCHAR2) RETURN VARCHAR2 IS
    v VARCHAR2(12);
    v_id NUMBER := bed(p_code);     -- local functions cannot be called inside SQL,
  BEGIN                             -- so the id is fetched into a variable first
    SELECT status INTO v FROM beds WHERE bed_id = v_id;
    RETURN v;
  END bed_status;

  FUNCTION count_rows (p_sql VARCHAR2) RETURN NUMBER IS
    v NUMBER;
  BEGIN
    EXECUTE IMMEDIATE p_sql INTO v;
    RETURN v;
  END count_rows;

BEGIN
  SELECT term_id INTO v_term_id  FROM academic_terms WHERE is_current = 'Y';
  SELECT term_id INTO v_old_term FROM academic_terms WHERE name = 'Spring 2026';
  SELECT user_id INTO v_warden   FROM app_users WHERE username = 'warden.ali';
  s_231014 := student('231014');  s_231015 := student('231015');
  s_231016 := student('231016');  s_231028 := student('231028');
  b_A202B  := bed('A202-B');      b_A203B  := bed('A203-B');
  b_A203C  := bed('A203-C');      b_A204D  := bed('A204-D');

  DBMS_OUTPUT.PUT_LINE('========== HostelHub database tests ==========');
  DBMS_OUTPUT.PUT_LINE('');

  /* =================== T01 CONSTRAINTS =================== */
  BEGIN
    INSERT INTO students (roll_no, full_name, gender, email, program, semester)
    VALUES ('239001', 'Test Valid', 'M', 'test.valid@student.edu.pk', 'BSIT', 1);
    report('T01a', 'Valid student is accepted',
           'INSERT student 239001, gender M, semester 1',
           '1 row inserted', SQL%ROWCOUNT || ' row inserted', SQL%ROWCOUNT = 1);
    ROLLBACK;
  EXCEPTION WHEN OTHERS THEN
    ROLLBACK;
    report('T01a', 'Valid student is accepted', 'INSERT student 239001', '1 row inserted', SQLERRM, FALSE);
  END;

  BEGIN
    INSERT INTO students (roll_no, full_name, gender, email, program, semester)
    VALUES ('231001', 'Duplicate Roll', 'M', 'dup.roll@student.edu.pk', 'BSIT', 1);
    ROLLBACK;
    report('T01b', 'Duplicate roll number is rejected (UNIQUE)',
           'INSERT student with roll_no 231001 (already used)', 'ORA-00001 on UQ_STUDENTS_ROLL',
           'row was inserted', FALSE);
  EXCEPTION WHEN OTHERS THEN
    ROLLBACK;
    report('T01b', 'Duplicate roll number is rejected (UNIQUE)',
           'INSERT student with roll_no 231001 (already used)', 'ORA-00001 on UQ_STUDENTS_ROLL',
           SQLERRM, SQLCODE = -1 AND INSTR(SQLERRM, 'UQ_STUDENTS_ROLL') > 0);
  END;

  BEGIN
    INSERT INTO beds (room_unit_id, bed_label) VALUES (99999, 'A');
    ROLLBACK;
    report('T01c', 'Bed in a non-existent room is rejected (FOREIGN KEY)',
           'INSERT bed with room_unit_id 99999', 'ORA-02291 on FK_BEDS_ROOM', 'row was inserted', FALSE);
  EXCEPTION WHEN OTHERS THEN
    ROLLBACK;
    report('T01c', 'Bed in a non-existent room is rejected (FOREIGN KEY)',
           'INSERT bed with room_unit_id 99999', 'ORA-02291 on FK_BEDS_ROOM',
           SQLERRM, SQLCODE = -2291);
  END;

  BEGIN
    INSERT INTO students (roll_no, full_name, gender, email, program, semester)
    VALUES ('239002', 'Bad Semester', 'M', 'bad.semester@student.edu.pk', 'BSIT', 9);
    ROLLBACK;
    report('T01d', 'Semester 9 is rejected (CHECK)',
           'INSERT student with semester 9', 'ORA-02290 on CK_STUDENTS_SEMESTER', 'row was inserted', FALSE);
  EXCEPTION WHEN OTHERS THEN
    ROLLBACK;
    report('T01d', 'Semester 9 is rejected (CHECK)',
           'INSERT student with semester 9', 'ORA-02290 on CK_STUDENTS_SEMESTER',
           SQLERRM, SQLCODE = -2290);
  END;

  BEGIN
    INSERT INTO students (roll_no, full_name, gender, email, program, semester)
    VALUES ('239003', NULL, 'F', 'no.name@student.edu.pk', 'BSIT', 1);
    ROLLBACK;
    report('T01e', 'Missing name is rejected (NOT NULL)',
           'INSERT student with full_name NULL', 'ORA-01400', 'row was inserted', FALSE);
  EXCEPTION WHEN OTHERS THEN
    ROLLBACK;
    report('T01e', 'Missing name is rejected (NOT NULL)',
           'INSERT student with full_name NULL', 'ORA-01400', SQLERRM, SQLCODE = -1400);
  END;

  /* =================== T02 TRIGGERS =================== */
  -- BEFORE trigger trg_alloc_validate, accepted
  BEGIN
    INSERT INTO allocations (client_request_id, student_id, bed_id, term_id, allocated_by)
    VALUES ('TEST-T02A', s_231014, b_A202B, v_term_id, v_warden);
    report('T02a', 'BEFORE trigger accepts a valid allocation',
           'INSERT allocation: boy 231014 -> boys bed A202-B, current term',
           '1 row inserted (then rolled back)', SQL%ROWCOUNT || ' row inserted', SQL%ROWCOUNT = 1);
    ROLLBACK;
  EXCEPTION WHEN OTHERS THEN
    ROLLBACK;
    report('T02a', 'BEFORE trigger accepts a valid allocation', 'boy -> boys bed', '1 row inserted', SQLERRM, FALSE);
  END;

  -- BEFORE trigger, rejected: gender mismatch
  BEGIN
    INSERT INTO allocations (client_request_id, student_id, bed_id, term_id, allocated_by)
    VALUES ('TEST-T02B', s_231028, b_A203C, v_term_id, v_warden);
    ROLLBACK;
    report('T02b', 'BEFORE trigger rejects wrong gender',
           'INSERT allocation: girl 231028 -> boys bed A203-C', 'ORA-20004', 'row was inserted', FALSE);
  EXCEPTION WHEN OTHERS THEN
    ROLLBACK;
    report('T02b', 'BEFORE trigger rejects wrong gender',
           'INSERT allocation: girl 231028 -> boys bed A203-C', 'ORA-20004', SQLERRM, SQLCODE = -20004);
  END;

  -- BEFORE trigger, rejected: term already ended
  BEGIN
    INSERT INTO allocations (client_request_id, student_id, bed_id, term_id, allocated_by)
    VALUES ('TEST-T02C', s_231014, b_A203C, v_old_term, v_warden);
    ROLLBACK;
    report('T02c', 'BEFORE trigger rejects an ended term',
           'INSERT allocation for term Spring 2026', 'ORA-20005', 'row was inserted', FALSE);
  EXCEPTION WHEN OTHERS THEN
    ROLLBACK;
    report('T02c', 'BEFORE trigger rejects an ended term',
           'INSERT allocation for term Spring 2026', 'ORA-20005', SQLERRM, SQLCODE = -20005);
  END;

  -- AFTER trigger trg_payment_audit, accepted: audit row + status change
  DECLARE
    v_inv     invoices%ROWTYPE;
    v_status  invoices.status%TYPE;
  BEGIN
    SELECT * INTO v_inv FROM invoices
     WHERE status = 'UNPAID' AND billing_month = DATE '2026-11-01'
     ORDER BY invoice_id FETCH FIRST 1 ROW ONLY;
    v_n1 := count_rows('SELECT COUNT(*) FROM audit_log WHERE action = ''PAYMENT_INSERT''');

    INSERT INTO payments (invoice_id, amount, method, received_by)
    VALUES (v_inv.invoice_id, 1000, 'CASH', v_warden);

    v_n2 := count_rows('SELECT COUNT(*) FROM audit_log WHERE action = ''PAYMENT_INSERT''');
    SELECT status INTO v_status FROM invoices WHERE invoice_id = v_inv.invoice_id;
    report('T02d', 'AFTER trigger audits a payment and updates the invoice',
           'INSERT payment 1000 on UNPAID invoice ' || v_inv.invoice_id || ' (total ' || v_inv.total_amount || ')',
           '+1 PAYMENT_INSERT audit row; invoice UNPAID -> PARTIAL',
           '+' || (v_n2 - v_n1) || ' audit row; invoice ' || v_inv.status || ' -> ' || v_status,
           v_n2 - v_n1 = 1 AND v_status = 'PARTIAL');
    ROLLBACK;
  EXCEPTION WHEN OTHERS THEN
    ROLLBACK;
    report('T02d', 'AFTER trigger audits a payment', 'payment 1000', 'audit + PARTIAL', SQLERRM, FALSE);
  END;

  -- AFTER trigger, rejected: over-payment; payment AND audit row both undone
  DECLARE
    v_inv  invoices%ROWTYPE;
  BEGIN
    SELECT * INTO v_inv FROM invoices
     WHERE status = 'UNPAID' AND billing_month = DATE '2026-11-01'
     ORDER BY invoice_id FETCH FIRST 1 ROW ONLY;
    v_n1 := count_rows('SELECT COUNT(*) FROM audit_log');
    BEGIN
      INSERT INTO payments (invoice_id, amount, method, received_by)
      VALUES (v_inv.invoice_id, v_inv.total_amount + 500, 'CARD', v_warden);
      v_txt := 'payment accepted';
    EXCEPTION WHEN OTHERS THEN
      v_txt := SQLERRM;
      v_n3  := SQLCODE;
    END;
    v_n2 := count_rows('SELECT COUNT(*) FROM audit_log');
    report('T02e', 'AFTER trigger rejects an over-payment',
           'INSERT payment of total + 500 on invoice ' || v_inv.invoice_id,
           'ORA-20024; no payment and no audit row kept',
           v_txt || ' | audit rows added: ' || (v_n2 - v_n1),
           v_n3 = -20024 AND v_n2 = v_n1);
    ROLLBACK;
  END;

  /* =================== T03 SUCCESSFUL MULTI-TABLE PROCEDURE =================== */
  BEGIN
    v_n1 := count_rows('SELECT COUNT(*) FROM allocations');
    pr_allocate_bed('TEST-T03', s_231015, b_A203B, v_term_id, v_warden, v_alloc_id, v_result);
    v_n2 := count_rows('SELECT COUNT(*) FROM allocations');
    v_n3 := count_rows('SELECT COUNT(*) FROM audit_log WHERE client_request_id = ''TEST-T03'' AND action = ''ALLOCATE_SUCCESS''');
    report('T03', 'pr_allocate_bed completes a multi-table transaction',
           'TEST-T03: student 231015 -> bed A203-B',
           'CREATED; +1 allocation; bed OCCUPIED; 1 success audit row',
           v_result || ' id ' || v_alloc_id || '; +' || (v_n2 - v_n1) || ' allocation; bed '
             || bed_status('A203-B') || '; ' || v_n3 || ' success audit row',
           v_result = 'CREATED' AND v_n2 - v_n1 = 1 AND bed_status('A203-B') = 'OCCUPIED' AND v_n3 = 1);
  EXCEPTION WHEN OTHERS THEN
    report('T03', 'pr_allocate_bed completes a multi-table transaction', 'TEST-T03', 'CREATED', SQLERRM, FALSE);
  END;

  /* =================== T04 FAILED PROCEDURE, NO PARTIAL CHANGES =================== */
  BEGIN
    v_n1 := count_rows('SELECT COUNT(*) FROM allocations');
    BEGIN
      pr_allocate_bed('TEST-T04', s_231016, b_A204D, v_term_id, v_warden, v_alloc_id, v_result);
      v_txt := 'allocation created';
    EXCEPTION WHEN OTHERS THEN
      v_txt := SQLERRM;
      v_n3  := SQLCODE;
    END;
    v_n2 := count_rows('SELECT COUNT(*) FROM allocations');
    report('T04a', 'Allocation to a MAINTENANCE bed fails cleanly',
           'TEST-T04: student 231016 -> bed A204-D (MAINTENANCE)',
           'ORA-20002; allocations unchanged; bed still MAINTENANCE; no success audit',
           v_txt || ' | allocations +' || (v_n2 - v_n1) || '; bed ' || bed_status('A204-D')
             || '; success audit rows ' || count_rows('SELECT COUNT(*) FROM audit_log WHERE client_request_id = ''TEST-T04'' AND action = ''ALLOCATE_SUCCESS'''),
           v_n3 = -20002 AND v_n2 = v_n1 AND bed_status('A204-D') = 'MAINTENANCE'
             AND count_rows('SELECT COUNT(*) FROM audit_log WHERE client_request_id = ''TEST-T04'' AND action = ''ALLOCATE_SUCCESS''') = 0);
  END;

  -- Failure deeper inside: the bed is locked and the INSERT is attempted,
  -- then the trigger rejects it. Everything must still be rolled back.
  BEGIN
    v_n1 := count_rows('SELECT COUNT(*) FROM allocations');
    v_n3 := NULL;
    BEGIN
      pr_allocate_bed('TEST-T04B', s_231028, b_A203C, v_term_id, v_warden, v_alloc_id, v_result);
      v_txt := 'allocation created';
    EXCEPTION WHEN OTHERS THEN
      v_txt := SQLERRM;
      v_n3  := SQLCODE;
    END;
    v_n2 := count_rows('SELECT COUNT(*) FROM allocations');
    report('T04b', 'Trigger failure inside the procedure leaves no partial rows',
           'TEST-T04B: girl 231028 -> boys bed A203-C',
           'ORA-20004; allocations unchanged; bed still AVAILABLE; failure logged, no success audit',
           v_txt || ' | allocations +' || (v_n2 - v_n1) || '; bed ' || bed_status('A203-C')
             || '; ALLOCATE_FAILED rows ' || count_rows('SELECT COUNT(*) FROM audit_log WHERE client_request_id = ''TEST-T04B'' AND action = ''ALLOCATE_FAILED'''),
           v_n3 = -20004 AND v_n2 = v_n1 AND bed_status('A203-C') = 'AVAILABLE'
             AND count_rows('SELECT COUNT(*) FROM audit_log WHERE client_request_id = ''TEST-T04B'' AND action = ''ALLOCATE_SUCCESS''') = 0);
  END;

  /* =================== T09 / T10 / T11 RETRY-SAFE ALLOCATION =================== */
  -- T09: brand-new request
  BEGIN
    v_n1 := count_rows('SELECT COUNT(*) FROM allocations');
    pr_allocate_bed('TEST-T09', s_231014, b_A202B, v_term_id, v_warden, v_alloc_id, v_result);
    v_n2 := count_rows('SELECT COUNT(*) FROM allocations');
    report('T09', 'New request creates exactly one allocation',
           'TEST-T09: student 231014 -> bed A202-B',
           'CREATED; +1 allocation; bed OCCUPIED; 1 success audit row',
           v_result || ' id ' || v_alloc_id || '; +' || (v_n2 - v_n1) || ' allocation; bed ' || bed_status('A202-B')
             || '; success audit rows ' || count_rows('SELECT COUNT(*) FROM audit_log WHERE client_request_id = ''TEST-T09'' AND action = ''ALLOCATE_SUCCESS'''),
           v_result = 'CREATED' AND v_n2 - v_n1 = 1 AND bed_status('A202-B') = 'OCCUPIED'
             AND count_rows('SELECT COUNT(*) FROM audit_log WHERE client_request_id = ''TEST-T09'' AND action = ''ALLOCATE_SUCCESS''') = 1);
  EXCEPTION WHEN OTHERS THEN
    report('T09', 'New request creates exactly one allocation', 'TEST-T09', 'CREATED', SQLERRM, FALSE);
  END;

  -- T10: the browser sends the SAME request again (double click / timeout retry)
  BEGIN
    v_n1 := count_rows('SELECT COUNT(*) FROM allocations');
    v_n3 := count_rows('SELECT COUNT(*) FROM audit_log');
    pr_allocate_bed('TEST-T09', s_231014, b_A202B, v_term_id, v_warden, v_alloc_id2, v_result);
    v_n2 := count_rows('SELECT COUNT(*) FROM allocations');
    report('T10', 'Identical retry returns the saved result, changes nothing',
           'TEST-T09 again with the same student, bed and term',
           'REPLAYED; same allocation id ' || v_alloc_id || '; no new allocation or audit rows',
           v_result || ' id ' || v_alloc_id2 || '; allocations +' || (v_n2 - v_n1)
             || '; audit rows +' || (count_rows('SELECT COUNT(*) FROM audit_log') - v_n3),
           v_result = 'REPLAYED' AND v_alloc_id2 = v_alloc_id AND v_n2 = v_n1
             AND count_rows('SELECT COUNT(*) FROM audit_log') = v_n3);
  EXCEPTION WHEN OTHERS THEN
    report('T10', 'Identical retry returns the saved result', 'TEST-T09 again', 'REPLAYED', SQLERRM, FALSE);
  END;

  -- T11: same request id but a DIFFERENT bed
  BEGIN
    v_n1 := count_rows('SELECT COUNT(*) FROM allocations');
    v_n3 := NULL;
    BEGIN
      pr_allocate_bed('TEST-T09', s_231014, b_A203C, v_term_id, v_warden, v_alloc_id2, v_result);
      v_txt := 'request accepted (' || v_result || ')';
    EXCEPTION WHEN OTHERS THEN
      v_txt := SQLERRM;
      v_n3  := SQLCODE;
    END;
    v_n2 := count_rows('SELECT COUNT(*) FROM allocations');
    SELECT r.unit_code || '-' || b.bed_label INTO v_txt2
      FROM allocations a JOIN beds b ON b.bed_id = a.bed_id JOIN hostel_units r ON r.unit_id = b.room_unit_id
     WHERE a.client_request_id = 'TEST-T09';
    report('T11', 'Conflicting retry is rejected, original untouched',
           'TEST-T09 again but bed A203-C instead of A202-B',
           'ORA-20010; allocation still on A202-B; A203-C still AVAILABLE',
           v_txt || ' | original bed ' || v_txt2 || '; A203-C ' || bed_status('A203-C')
             || '; allocations +' || (v_n2 - v_n1),
           v_n3 = -20010 AND v_txt2 = 'A202-B' AND bed_status('A203-C') = 'AVAILABLE' AND v_n2 = v_n1);
  END;

  /* =================== FUNCTIONS =================== */
  DECLARE
    v_pct NUMBER;
  BEGIN
    SELECT fn_occupancy_pct(unit_id) INTO v_pct FROM hostel_units WHERE unit_code = 'A' AND unit_type = 'BLOCK';
    v_n1 := count_rows('SELECT COUNT(*) FROM v_bed_occupancy WHERE block_code = ''A'' AND bed_status = ''OCCUPIED''');
    v_n2 := count_rows('SELECT COUNT(*) FROM v_bed_occupancy WHERE block_code = ''A''');
    report('F1', 'fn_occupancy_pct matches a manual count',
           'fn_occupancy_pct(block A)', ROUND(v_n1 / v_n2 * 100, 1) || ' (' || v_n1 || ' of ' || v_n2 || ' beds)',
           v_pct || ' -> band ' || fn_occupancy_band(v_pct), v_pct = ROUND(v_n1 / v_n2 * 100, 1));
  END;

  BEGIN
    v_n1 := fn_outstanding_balance(student('231023'));
    SELECT outstanding INTO v_n2 FROM v_student_dues WHERE roll_no = '231023';
    report('F2', 'fn_outstanding_balance matches v_student_dues',
           'fn_outstanding_balance(231023)', TO_CHAR(v_n2), TO_CHAR(v_n1), v_n1 = v_n2);
  END;

  BEGIN
    v_n1 := fn_outstanding_balance(-1);
    report('F3', 'Unknown student is rejected', 'fn_outstanding_balance(-1)', 'ORA-20032', 'returned ' || v_n1, FALSE);
  EXCEPTION WHEN OTHERS THEN
    report('F3', 'Unknown student is rejected (NO_DATA_FOUND handled)',
           'fn_outstanding_balance(-1)', 'ORA-20032', SQLERRM, SQLCODE = -20032);
  END;

  DBMS_OUTPUT.PUT_LINE('==============================================');
  DBMS_OUTPUT.PUT_LINE('PASSED: ' || g_pass || '   FAILED: ' || g_fail);
END;
/

-- Evidence: the allocation rows and audit trail created by the tests
SELECT a.allocation_id, a.client_request_id, s.roll_no, r.unit_code || '-' || b.bed_label AS bed, a.status
  FROM allocations a
  JOIN students s     ON s.student_id = a.student_id
  JOIN beds b         ON b.bed_id = a.bed_id
  JOIN hostel_units r ON r.unit_id = b.room_unit_id
 WHERE a.client_request_id LIKE 'TEST-%'
 ORDER BY a.allocation_id;

SELECT audit_id, action, client_request_id, record_id, SUBSTR(details, 1, 70) AS details
  FROM audit_log
 WHERE client_request_id LIKE 'TEST-%'
 ORDER BY audit_id;
