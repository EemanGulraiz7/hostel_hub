/* =====================================================================
   HostelHub | 04_procedures.sql
   ---------------------------------------------------------------------
   RUN AS: HOSTELHUB
   Requirement: at least 2 stored procedures
     (1) a parameterized procedure doing a multi-table transaction
           -> pr_allocate_bed   (the retry-safe CORE TRANSACTION)
     (2) a procedure with IN/OUT parameters returning useful results
           -> pr_generate_invoice
   Extras used by the web app:
           -> pr_vacate_bed
           -> pr_audit_failure  (autonomous transaction helper)

   Custom error numbers (the backend maps these to friendly messages):
     -20000  Required input missing
     -20001  Bed does not exist
     -20002  Bed is not available
     -20003  Student already has an active allocation in this term
     -20004  Student gender does not match block policy   (trigger)
     -20005  Term has already ended                        (trigger)
     -20006  Student does not exist
     -20007  Term does not exist                           (trigger)
     -20010  Request ID already used with different details
     -20020  Student has no active allocation for that month
     -20021  Invalid invoice input
     -20022  Invoice already exists for that month
     -20023  Student does not exist (invoicing)
     -20040  Allocation does not exist
     -20041  Allocation is already vacated
   ===================================================================== */

-- ---------------------------------------------------------------------
-- pr_audit_failure
-- Writes a FAILED row to AUDIT_LOG in its OWN transaction
-- (PRAGMA AUTONOMOUS_TRANSACTION). So when the main transaction rolls
-- back, the failure note still survives, but NO success row and NO
-- business change survive. This is exactly what the retry rules ask for.
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE pr_audit_failure (
  p_user_id           IN NUMBER,
  p_action            IN VARCHAR2,
  p_client_request_id IN VARCHAR2,
  p_details           IN VARCHAR2
)
IS
  PRAGMA AUTONOMOUS_TRANSACTION;
BEGIN
  INSERT INTO audit_log (user_id, action, client_request_id, table_name, details)
  VALUES (
    -- only keep the user id if it really exists, so the FK cannot fail here
    (SELECT MAX(user_id) FROM app_users WHERE user_id = p_user_id),
    p_action, p_client_request_id, 'ALLOCATIONS', SUBSTR(p_details, 1, 4000));
  COMMIT;   -- commits ONLY this autonomous insert
END pr_audit_failure;
/
SHOW ERRORS

-- ---------------------------------------------------------------------
-- pr_allocate_bed  [CORE TRANSACTION, retry-safe]
--
-- The browser creates ONE client_request_id (a UUID) per form submit
-- and re-sends the same id on every retry. Results:
--   new id                        -> allocation created  (o_result = 'CREATED')
--   same id + same details        -> saved allocation id (o_result = 'REPLAYED'),
--                                    nothing changes
--   same id + different details   -> error -20010, original untouched
--   any failure                   -> ROLLBACK: no partial rows, no success audit
--
-- Tables touched in ONE transaction: ALLOCATIONS (insert), BEDS (update),
-- AUDIT_LOG (insert); STUDENTS / ACADEMIC_TERMS / HOSTEL_UNITS are read
-- by the validation trigger.
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE pr_allocate_bed (
  p_client_request_id IN  VARCHAR2,
  p_student_id        IN  NUMBER,
  p_bed_id            IN  NUMBER,
  p_term_id           IN  NUMBER,
  p_user_id           IN  NUMBER,
  o_allocation_id     OUT NUMBER,
  o_result            OUT VARCHAR2      -- 'CREATED' or 'REPLAYED'
)
IS
  v_existing    allocations%ROWTYPE;
  v_found       BOOLEAN := FALSE;
  v_bed_status  beds.status%TYPE;
  v_dummy       NUMBER;
  v_active      NUMBER;

  -- Local helper: look for an earlier request with the same id.
  -- Returns TRUE and fills v_existing when one exists.
  FUNCTION find_request RETURN BOOLEAN IS
  BEGIN
    SELECT * INTO v_existing
      FROM allocations
     WHERE client_request_id = p_client_request_id;
    RETURN TRUE;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      RETURN FALSE;
  END find_request;

  -- Local helper: decide REPLAYED vs conflict for an existing request.
  PROCEDURE handle_existing IS
  BEGIN
    IF  v_existing.student_id = p_student_id
    AND v_existing.bed_id     = p_bed_id
    AND v_existing.term_id    = p_term_id THEN
      o_allocation_id := v_existing.allocation_id;
      o_result        := 'REPLAYED';
    ELSE
      RAISE_APPLICATION_ERROR(-20010,
        'Request ID already used with different details (allocation '
        || v_existing.allocation_id || ')');
    END IF;
  END handle_existing;

BEGIN
  -- 0. Server-side validation of required input.
  IF p_client_request_id IS NULL OR p_student_id IS NULL OR p_bed_id IS NULL
     OR p_term_id IS NULL OR p_user_id IS NULL THEN
    RAISE_APPLICATION_ERROR(-20000, 'Request ID, student, bed, term and user are all required');
  END IF;

  -- 1. Fast path: was this request already processed?
  IF find_request THEN
    handle_existing;
    RETURN;                                -- nothing changed, nothing to commit
  END IF;

  -- 2. Student must exist (clear message instead of an FK error).
  BEGIN
    SELECT 1 INTO v_dummy FROM students WHERE student_id = p_student_id;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      RAISE_APPLICATION_ERROR(-20006, 'Student ' || p_student_id || ' does not exist');
  END;

  -- 3. Lock the bed row. Any other session trying to allocate the same
  --    bed now WAITS here until we COMMIT or ROLLBACK.
  BEGIN
    SELECT status INTO v_bed_status
      FROM beds
     WHERE bed_id = p_bed_id
       FOR UPDATE;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      RAISE_APPLICATION_ERROR(-20001, 'Bed ' || p_bed_id || ' does not exist');
  END;

  -- 3b. Re-check the request id AFTER getting the lock. If two identical
  --     requests raced, the first one has committed by now; we must return
  --     its result instead of reporting "bed not available".
  IF find_request THEN
    handle_existing;
    ROLLBACK;                              -- releases the bed lock
    RETURN;
  END IF;

  IF v_bed_status <> 'AVAILABLE' THEN
    RAISE_APPLICATION_ERROR(-20002, 'Bed ' || p_bed_id || ' is not available (status '
                                    || v_bed_status || ')');
  END IF;

  -- 4. One active allocation per student per term.
  SELECT COUNT(*) INTO v_active
    FROM allocations
   WHERE student_id = p_student_id
     AND term_id    = p_term_id
     AND status     = 'ACTIVE';
  IF v_active > 0 THEN
    RAISE_APPLICATION_ERROR(-20003, 'Student already has an active allocation in this term');
  END IF;

  -- 5. Insert the allocation. trg_alloc_validate (BEFORE INSERT) checks
  --    gender vs block policy and that the term has not ended.
  INSERT INTO allocations (client_request_id, student_id, bed_id, term_id, allocated_by)
  VALUES (p_client_request_id, p_student_id, p_bed_id, p_term_id, p_user_id)
  RETURNING allocation_id INTO o_allocation_id;

  -- 6. Mark the bed occupied.
  UPDATE beds SET status = 'OCCUPIED' WHERE bed_id = p_bed_id;

  -- 7. Success audit row, in the SAME transaction.
  INSERT INTO audit_log (user_id, action, client_request_id, table_name, record_id, details)
  VALUES (p_user_id, 'ALLOCATE_SUCCESS', p_client_request_id, 'ALLOCATIONS', o_allocation_id,
          'student=' || p_student_id || ' bed=' || p_bed_id || ' term=' || p_term_id);

  -- 8. All or nothing.
  COMMIT;
  o_result := 'CREATED';

EXCEPTION
  WHEN DUP_VAL_ON_INDEX THEN
    -- A unique index fired. Either the same request id was inserted by a
    -- parallel session (-> replay or conflict), or the student/bed got an
    -- active allocation in the meantime.
    ROLLBACK;
    IF find_request THEN
      handle_existing;
    ELSE
      pr_audit_failure(p_user_id, 'ALLOCATE_FAILED', p_client_request_id,
                       'Duplicate active allocation for student or bed');
      RAISE_APPLICATION_ERROR(-20003, 'Student or bed already has an active allocation in this term');
    END IF;
  WHEN OTHERS THEN
    -- Undo EVERYTHING this call did (allocation, bed update, audit row),
    -- note the failure in its own transaction, then pass the error on.
    ROLLBACK;
    pr_audit_failure(p_user_id, 'ALLOCATE_FAILED', p_client_request_id, SQLERRM);
    RAISE;
END pr_allocate_bed;
/
SHOW ERRORS

-- ---------------------------------------------------------------------
-- pr_generate_invoice  [IN / OUT parameters]
--   IN  p_student_id, p_month (any date in the month), p_user_id
--   OUT o_invoice_id, o_total
-- Builds one invoice = room rent (from the room type of the student's
-- bed) + mess charges (fn_meal_charges).
-- It does NOT commit: the caller decides (the billing run in
-- 09_billing_run.sql commits once at the end, the web API commits after
-- each call).
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE pr_generate_invoice (
  p_student_id  IN  NUMBER,
  p_month       IN  DATE,
  o_invoice_id  OUT NUMBER,
  o_total       OUT NUMBER,
  p_user_id     IN  NUMBER DEFAULT NULL
)
IS
  v_month          DATE := TRUNC(p_month, 'MM');
  v_dummy          NUMBER;
  v_allocation_id  allocations.allocation_id%TYPE;
  v_rent           room_types.monthly_rent%TYPE;
  v_mess           NUMBER;
BEGIN
  IF p_student_id IS NULL OR p_month IS NULL THEN
    RAISE_APPLICATION_ERROR(-20021, 'Student and billing month are required');
  END IF;

  BEGIN
    SELECT 1 INTO v_dummy FROM students WHERE student_id = p_student_id;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      RAISE_APPLICATION_ERROR(-20023, 'Student ' || p_student_id || ' does not exist');
  END;

  -- Do not bill the same month twice (the UNIQUE constraint would also
  -- stop it, but this gives a clearer message).
  SELECT COUNT(*) INTO v_dummy
    FROM invoices
   WHERE student_id = p_student_id AND billing_month = v_month;
  IF v_dummy > 0 THEN
    RAISE_APPLICATION_ERROR(-20022, 'Invoice already exists for student ' || p_student_id
                                    || ' and month ' || TO_CHAR(v_month, 'MON-YYYY'));
  END IF;

  -- Find the ACTIVE allocation whose term overlaps the billing month,
  -- and the monthly rent of that bed's room type.
  BEGIN
    SELECT a.allocation_id, rt.monthly_rent
      INTO v_allocation_id, v_rent
      FROM allocations    a
      JOIN academic_terms t  ON t.term_id  = a.term_id
      JOIN beds           b  ON b.bed_id   = a.bed_id
      JOIN hostel_units   r  ON r.unit_id  = b.room_unit_id
      JOIN room_types     rt ON rt.room_type_id = r.room_type_id
     WHERE a.student_id = p_student_id
       AND a.status     = 'ACTIVE'
       AND t.start_date <  ADD_MONTHS(v_month, 1)
       AND t.end_date   >= v_month
     ORDER BY t.start_date DESC
     FETCH FIRST 1 ROW ONLY;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      RAISE_APPLICATION_ERROR(-20020, 'Student ' || p_student_id
                                      || ' has no active allocation for ' || TO_CHAR(v_month, 'MON-YYYY'));
  END;

  v_mess  := fn_meal_charges(p_student_id, v_month);
  o_total := v_rent + v_mess;

  INSERT INTO invoices (student_id, allocation_id, billing_month, rent_amount, mess_amount,
                        total_amount, due_date, generated_by)
  VALUES (p_student_id, v_allocation_id, v_month, v_rent, v_mess,
          o_total, ADD_MONTHS(v_month, 1) + 9,          -- due on the 10th of next month
          p_user_id)
  RETURNING invoice_id INTO o_invoice_id;
END pr_generate_invoice;
/
SHOW ERRORS

-- ---------------------------------------------------------------------
-- pr_vacate_bed: student leaves; allocation VACATED, bed AVAILABLE,
-- audit row. Multi-table, all-or-nothing.
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE pr_vacate_bed (
  p_allocation_id IN NUMBER,
  p_user_id       IN NUMBER
)
IS
  v_status  allocations.status%TYPE;
  v_bed_id  allocations.bed_id%TYPE;
BEGIN
  BEGIN
    SELECT status, bed_id INTO v_status, v_bed_id
      FROM allocations
     WHERE allocation_id = p_allocation_id
       FOR UPDATE;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      RAISE_APPLICATION_ERROR(-20040, 'Allocation ' || p_allocation_id || ' does not exist');
  END;

  IF v_status = 'VACATED' THEN
    RAISE_APPLICATION_ERROR(-20041, 'Allocation ' || p_allocation_id || ' is already vacated');
  END IF;

  UPDATE allocations
     SET status = 'VACATED', vacated_at = SYSTIMESTAMP
   WHERE allocation_id = p_allocation_id;

  UPDATE beds SET status = 'AVAILABLE' WHERE bed_id = v_bed_id;

  INSERT INTO audit_log (user_id, action, table_name, record_id, details)
  VALUES (p_user_id, 'VACATE_SUCCESS', 'ALLOCATIONS', p_allocation_id, 'bed=' || v_bed_id);

  COMMIT;
EXCEPTION
  WHEN OTHERS THEN
    ROLLBACK;
    RAISE;
END pr_vacate_bed;
/
SHOW ERRORS

PROMPT 04_procedures.sql finished.
