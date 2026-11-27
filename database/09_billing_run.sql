/* =====================================================================
   HostelHub | 09_billing_run.sql
   ---------------------------------------------------------------------
   RUN AS: HOSTELHUB
   Month-end billing for NOVEMBER 2026. Demonstrates:
     * an explicit PARAMETERIZED CURSOR           (c_residents)
     * an ANONYMOUS block with a NESTED block     (one inner block per student)
     * exception handling:
         - NO_DATA_FOUND      (predefined Oracle exception)
         - e_no_allocation    (custom business error, mapped to -20020)
         - e_invoice_exists   (custom business error, mapped to -20022)
         - OTHERS             (anything unexpected)
     * a SAVEPOINT per student, so one bad record is undone on its own
       and does not stop the run; COMMIT once at the end.
   Part B shows the two custom/NO_DATA_FOUND paths on purpose.
   Re-running Part A is safe: already-billed students are skipped.
   ===================================================================== */

SET SERVEROUTPUT ON SIZE UNLIMITED FORMAT WRAPPED

-- ---------------------------------------------------------------------
-- PART A: billing run with a parameterized cursor and nested blocks
-- ---------------------------------------------------------------------
DECLARE
  -- Custom exceptions bound to the error numbers raised by pr_generate_invoice
  e_no_allocation   EXCEPTION;
  e_invoice_exists  EXCEPTION;
  PRAGMA EXCEPTION_INIT(e_no_allocation,  -20020);
  PRAGMA EXCEPTION_INIT(e_invoice_exists, -20022);

  -- Explicit cursor with PARAMETERS: active residents of a given term
  CURSOR c_residents (p_term_id NUMBER) IS
    SELECT a.student_id, s.roll_no, s.full_name
      FROM allocations a
      JOIN students s ON s.student_id = a.student_id
     WHERE a.term_id = p_term_id
       AND a.status  = 'ACTIVE'
     ORDER BY s.roll_no;

  v_month       DATE := DATE '2026-11-01';
  v_term_id     academic_terms.term_id%TYPE;
  v_term_name   academic_terms.name%TYPE;
  v_admin_id    app_users.user_id%TYPE;
  v_invoice_id  invoices.invoice_id%TYPE;
  v_total       invoices.total_amount%TYPE;
  v_ok          PLS_INTEGER := 0;
  v_skipped     PLS_INTEGER := 0;
  v_failed      PLS_INTEGER := 0;
  v_sum         NUMBER := 0;
BEGIN
  -- Which term is current? NO_DATA_FOUND here means no current term is set.
  BEGIN
    SELECT term_id, name INTO v_term_id, v_term_name
      FROM academic_terms
     WHERE is_current = 'Y';
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      RAISE_APPLICATION_ERROR(-20060, 'No current term is set; cannot run billing');
  END;

  SELECT user_id INTO v_admin_id FROM app_users WHERE username = 'admin';

  DBMS_OUTPUT.PUT_LINE('Billing run for ' || TO_CHAR(v_month, 'Month YYYY') || ' / term ' || v_term_name);
  DBMS_OUTPUT.PUT_LINE(RPAD('-', 70, '-'));

  FOR r IN c_residents(v_term_id) LOOP          -- open, fetch, close handled by the FOR loop
    -- ===== NESTED BLOCK: one per student =====
    BEGIN
      SAVEPOINT before_student;
      pr_generate_invoice(r.student_id, v_month, v_invoice_id, v_total, v_admin_id);
      v_ok  := v_ok + 1;
      v_sum := v_sum + v_total;
      DBMS_OUTPUT.PUT_LINE(RPAD(r.roll_no || ' ' || r.full_name, 32)
                           || ' invoice ' || LPAD(v_invoice_id, 4) || '  total ' || LPAD(TO_CHAR(v_total, 'FM99,990'), 8));
    EXCEPTION
      WHEN e_invoice_exists THEN
        v_skipped := v_skipped + 1;
        DBMS_OUTPUT.PUT_LINE(RPAD(r.roll_no || ' ' || r.full_name, 32) || ' skipped: already billed');
      WHEN e_no_allocation THEN
        ROLLBACK TO before_student;
        v_failed := v_failed + 1;
        DBMS_OUTPUT.PUT_LINE(RPAD(r.roll_no || ' ' || r.full_name, 32) || ' skipped: no allocation');
      WHEN OTHERS THEN
        ROLLBACK TO before_student;            -- undo only this student's work
        v_failed := v_failed + 1;
        DBMS_OUTPUT.PUT_LINE(RPAD(r.roll_no || ' ' || r.full_name, 32) || ' FAILED: ' || SQLERRM);
    END;
    -- ===== end of nested block; the loop continues with the next student =====
  END LOOP;

  COMMIT;
  DBMS_OUTPUT.PUT_LINE(RPAD('-', 70, '-'));
  DBMS_OUTPUT.PUT_LINE('Invoices created: ' || v_ok || '   skipped: ' || v_skipped
                       || '   failed: ' || v_failed || '   amount billed: ' || TO_CHAR(v_sum, 'FM999,990'));
END;
/

-- ---------------------------------------------------------------------
-- PART B: exception handling on purpose
--   B1  NO_DATA_FOUND : bill a roll number that does not exist
--   B2  e_no_allocation (custom business error): bill a registered
--       student who has no bed (231030 Noor Fatima)
--   B3  custom error from a function: fn_outstanding_balance(NULL)
-- Nothing is changed: every path ends in ROLLBACK or raises before DML.
-- ---------------------------------------------------------------------
DECLARE
  e_no_allocation  EXCEPTION;
  PRAGMA EXCEPTION_INIT(e_no_allocation, -20020);

  v_student_id  students.student_id%TYPE;
  v_invoice_id  NUMBER;
  v_total       NUMBER;
  v_balance     NUMBER;
BEGIN
  -- B1
  BEGIN
    SELECT student_id INTO v_student_id FROM students WHERE roll_no = '999999';
    DBMS_OUTPUT.PUT_LINE('B1 unexpected: student found');
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      DBMS_OUTPUT.PUT_LINE('B1 NO_DATA_FOUND caught: roll number 999999 is not registered');
  END;

  -- B2
  BEGIN
    SELECT student_id INTO v_student_id FROM students WHERE roll_no = '231030';  -- Noor Fatima, never allocated
    pr_generate_invoice(v_student_id, DATE '2026-11-01', v_invoice_id, v_total);
    DBMS_OUTPUT.PUT_LINE('B2 unexpected: invoice ' || v_invoice_id || ' created');
    ROLLBACK;
  EXCEPTION
    WHEN e_no_allocation THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('B2 custom business error caught: ' || SQLERRM);
  END;

  -- B3
  BEGIN
    v_balance := fn_outstanding_balance(NULL);
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLCODE = -20031 THEN
        DBMS_OUTPUT.PUT_LINE('B3 NULL input rejected: ' || SQLERRM);
      ELSE
        RAISE;
      END IF;
  END;
END;
/

-- Result: November invoices
SELECT i.invoice_id, s.roll_no, s.full_name, i.rent_amount, i.mess_amount, i.total_amount, i.status, i.due_date
  FROM invoices i JOIN students s ON s.student_id = i.student_id
 WHERE i.billing_month = DATE '2026-11-01'
 ORDER BY s.roll_no;
