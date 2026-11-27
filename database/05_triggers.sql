/* =====================================================================
   HostelHub | 05_triggers.sql
   ---------------------------------------------------------------------
   RUN AS: HOSTELHUB
   Requirement: at least 2 triggers
     (1) a BEFORE validation trigger -> trg_alloc_validate
     (2) an AFTER audit trigger      -> trg_payment_audit
   Extra:
     (3) BEFORE validation on meals  -> trg_meal_validate

   Custom error numbers:
     -20001  Bed does not exist
     -20004  Student gender does not match block policy
     -20005  Term has already ended
     -20006  Student does not exist
     -20007  Term does not exist
     -20024  Payments would exceed the invoice total
     -20050  Meal date is in the future
     -20051  Student is not a hostel resident on that date
   ===================================================================== */

-- ---------------------------------------------------------------------
-- trg_alloc_validate  (BEFORE INSERT, row level)
-- Runs before every new allocation row and REJECTS it when:
--   * the student's gender does not match the gender policy of the
--     block that contains the bed   (-20004)
--   * the term has already ended    (-20005)
-- The block is found by walking UP the hostel hierarchy from the bed's
-- room (room -> floor -> block) with CONNECT BY.
-- ---------------------------------------------------------------------
CREATE OR REPLACE TRIGGER trg_alloc_validate
BEFORE INSERT ON allocations
FOR EACH ROW
DECLARE
  v_gender      students.gender%TYPE;
  v_policy      hostel_units.gender_policy%TYPE;
  v_block_code  hostel_units.unit_code%TYPE;
  v_end_date    academic_terms.end_date%TYPE;
BEGIN
  -- Student gender
  BEGIN
    SELECT gender INTO v_gender FROM students WHERE student_id = :NEW.student_id;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      RAISE_APPLICATION_ERROR(-20006, 'Student ' || :NEW.student_id || ' does not exist');
  END;

  -- Gender policy of the block that holds this bed
  BEGIN
    SELECT u.gender_policy, u.unit_code
      INTO v_policy, v_block_code
      FROM hostel_units u
     WHERE u.unit_type = 'BLOCK'
     START WITH u.unit_id = (SELECT b.room_unit_id FROM beds b WHERE b.bed_id = :NEW.bed_id)
   CONNECT BY u.unit_id = PRIOR u.parent_unit_id;     -- walk upwards
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      RAISE_APPLICATION_ERROR(-20001, 'Bed ' || :NEW.bed_id || ' does not exist');
  END;

  IF v_gender <> v_policy THEN
    RAISE_APPLICATION_ERROR(-20004,
      'Student gender (' || v_gender || ') does not match block ' || v_block_code
      || ' policy (' || v_policy || ')');
  END IF;

  -- Term must not be over
  BEGIN
    SELECT end_date INTO v_end_date FROM academic_terms WHERE term_id = :NEW.term_id;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      RAISE_APPLICATION_ERROR(-20007, 'Term ' || :NEW.term_id || ' does not exist');
  END;

  IF v_end_date < TRUNC(SYSDATE) THEN
    RAISE_APPLICATION_ERROR(-20005,
      'Term has already ended on ' || TO_CHAR(v_end_date, 'DD-MON-YYYY'));
  END IF;

  -- Normalise: a new allocation always starts ACTIVE.
  :NEW.status     := 'ACTIVE';
  :NEW.vacated_at := NULL;
END trg_alloc_validate;
/
SHOW ERRORS

-- ---------------------------------------------------------------------
-- trg_payment_audit  (AFTER INSERT OR UPDATE, COMPOUND trigger)
-- For every payment row inserted or updated:
--   AFTER EACH ROW   -> write an AUDIT_LOG row, remember the invoice id
--   AFTER STATEMENT  -> recompute each touched invoice's status
--                       (UNPAID / PARTIAL / PAID) from the SUM of its
--                       payments, and reject over-payment (-20024).
-- Why compound? A normal row-level trigger on PAYMENTS may not SELECT
-- from PAYMENTS (ORA-04091 "table is mutating"). The AFTER STATEMENT
-- section runs when the statement is finished, so reading PAYMENTS is
-- allowed there.
-- If -20024 is raised, Oracle undoes the whole statement: the payment
-- AND its audit rows disappear together.
-- ---------------------------------------------------------------------
CREATE OR REPLACE TRIGGER trg_payment_audit
FOR INSERT OR UPDATE ON payments
COMPOUND TRIGGER

  TYPE t_id_list IS TABLE OF NUMBER INDEX BY PLS_INTEGER;
  g_invoices  t_id_list;          -- invoice ids touched by this statement

  AFTER EACH ROW IS
    v_action   audit_log.action%TYPE;
    v_details  audit_log.details%TYPE;
  BEGIN
    -- INSERTING / UPDATING are PL/SQL predicates, so they are evaluated
    -- here first (they cannot be used inside the SQL INSERT itself).
    v_details := 'invoice=' || :NEW.invoice_id || ' amount=' || :NEW.amount
                 || ' method=' || :NEW.method;
    IF INSERTING THEN
      v_action := 'PAYMENT_INSERT';
    ELSE
      v_action  := 'PAYMENT_UPDATE';
      v_details := v_details || ' (old amount=' || :OLD.amount || ')';
    END IF;

    INSERT INTO audit_log (user_id, action, table_name, record_id, details)
    VALUES (:NEW.received_by, v_action, 'PAYMENTS', :NEW.payment_id, v_details);

    g_invoices(g_invoices.COUNT + 1) := :NEW.invoice_id;
    IF UPDATING AND :OLD.invoice_id <> :NEW.invoice_id THEN
      g_invoices(g_invoices.COUNT + 1) := :OLD.invoice_id;   -- moved payment
    END IF;
  END AFTER EACH ROW;

  AFTER STATEMENT IS
    v_total  invoices.total_amount%TYPE;
    v_paid   NUMBER;
  BEGIN
    FOR i IN 1 .. g_invoices.COUNT LOOP
      SELECT total_amount INTO v_total FROM invoices WHERE invoice_id = g_invoices(i);
      SELECT NVL(SUM(amount), 0) INTO v_paid FROM payments WHERE invoice_id = g_invoices(i);

      IF v_paid > v_total THEN
        RAISE_APPLICATION_ERROR(-20024,
          'Payments (' || v_paid || ') would exceed invoice ' || g_invoices(i)
          || ' total (' || v_total || ')');
      END IF;

      UPDATE invoices
         SET status = CASE WHEN v_paid = 0       THEN 'UNPAID'
                           WHEN v_paid < v_total THEN 'PARTIAL'
                           ELSE                       'PAID' END
       WHERE invoice_id = g_invoices(i);
    END LOOP;
  END AFTER STATEMENT;

END trg_payment_audit;
/
SHOW ERRORS

-- ---------------------------------------------------------------------
-- trg_meal_validate  (BEFORE INSERT, row level)
-- A meal can only be logged for a student who holds an ACTIVE allocation
-- in a term covering the meal date, and never for a future date.
-- Also strips any time part from meal_date.
-- ---------------------------------------------------------------------
CREATE OR REPLACE TRIGGER trg_meal_validate
BEFORE INSERT ON meal_log
FOR EACH ROW
DECLARE
  v_resident NUMBER;
BEGIN
  :NEW.meal_date := TRUNC(:NEW.meal_date);

  IF :NEW.meal_date > TRUNC(SYSDATE) THEN
    RAISE_APPLICATION_ERROR(-20050, 'Meal date ' || TO_CHAR(:NEW.meal_date, 'DD-MON-YYYY')
                                    || ' is in the future');
  END IF;

  SELECT COUNT(*) INTO v_resident
    FROM allocations a
    JOIN academic_terms t ON t.term_id = a.term_id
   WHERE a.student_id = :NEW.student_id
     AND a.status     = 'ACTIVE'
     AND :NEW.meal_date BETWEEN t.start_date AND t.end_date;

  IF v_resident = 0 THEN
    RAISE_APPLICATION_ERROR(-20051, 'Student ' || :NEW.student_id
                                    || ' is not a hostel resident on ' || TO_CHAR(:NEW.meal_date, 'DD-MON-YYYY'));
  END IF;
END trg_meal_validate;
/
SHOW ERRORS

PROMPT 05_triggers.sql finished.
