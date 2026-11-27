/* =====================================================================
   HostelHub | 03_functions.sql
   ---------------------------------------------------------------------
   RUN AS: HOSTELHUB
   Requirement: at least 2 functions
     (1) a calculation / classification function   -> fn_occupancy_pct
                                                     -> fn_occupancy_band
     (2) a function with input validation / NULL    -> fn_outstanding_balance
         handling
   Plus a helper used by invoicing                   -> fn_meal_charges

   Custom error numbers used in this file (-20030 .. -20039):
     -20030  Unit does not exist
     -20031  Student ID is required (NULL input)
     -20032  Student does not exist
     -20033  Billing month is required
   ===================================================================== */

-- ---------------------------------------------------------------------
-- fn_occupancy_pct(p_unit_id)  [CALCULATION]
-- Percentage of beds that are OCCUPIED under ANY unit: a block, a floor
-- or a single room. It uses a hierarchical (CONNECT BY) sub-query to
-- find every room below the given unit, so the same function works at
-- every level of the hostel.
--   fn_occupancy_pct(<block id>)  -> e.g. 65   (13 of 20 beds)
-- Returns 0 for a unit with no beds, NULL for a NULL input.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_occupancy_pct (
  p_unit_id IN hostel_units.unit_id%TYPE
) RETURN NUMBER
IS
  v_exists    NUMBER;
  v_total     NUMBER;
  v_occupied  NUMBER;
BEGIN
  IF p_unit_id IS NULL THEN
    RETURN NULL;
  END IF;

  -- Validate the unit exists (COUNT never raises NO_DATA_FOUND).
  SELECT COUNT(*) INTO v_exists FROM hostel_units WHERE unit_id = p_unit_id;
  IF v_exists = 0 THEN
    RAISE_APPLICATION_ERROR(-20030, 'Unit ' || p_unit_id || ' does not exist');
  END IF;

  SELECT COUNT(*),
         COUNT(CASE WHEN b.status = 'OCCUPIED' THEN 1 END)
    INTO v_total, v_occupied
    FROM beds b
   WHERE b.room_unit_id IN (SELECT u.unit_id
                              FROM hostel_units u
                             START WITH u.unit_id = p_unit_id
                           CONNECT BY PRIOR u.unit_id = u.parent_unit_id);

  IF v_total = 0 THEN
    RETURN 0;                       -- avoid division by zero
  END IF;

  RETURN ROUND(v_occupied / v_total * 100, 1);
END fn_occupancy_pct;
/
SHOW ERRORS

-- ---------------------------------------------------------------------
-- fn_occupancy_band(p_pct)  [CLASSIFICATION]
-- Turns a percentage into a label for the dashboard.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_occupancy_band (
  p_pct IN NUMBER
) RETURN VARCHAR2
IS
BEGIN
  RETURN CASE
           WHEN p_pct IS NULL THEN 'UNKNOWN'
           WHEN p_pct >= 90   THEN 'FULL'
           WHEN p_pct >= 60   THEN 'HIGH'
           WHEN p_pct >= 30   THEN 'MEDIUM'
           ELSE                    'LOW'
         END;
END fn_occupancy_band;
/
SHOW ERRORS

-- ---------------------------------------------------------------------
-- fn_outstanding_balance(p_student_id)  [VALIDATION + NULL HANDLING]
-- Total invoiced minus total paid for one student.
--   * NULL input              -> custom error -20031
--   * student does not exist  -> NO_DATA_FOUND is caught and turned
--                                into custom error -20032
--   * student with no invoices or no payments -> NVL turns the NULL
--                                sums into 0, so the result is 0, not NULL
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_outstanding_balance (
  p_student_id IN students.student_id%TYPE
) RETURN NUMBER
IS
  v_roll      students.roll_no%TYPE;
  v_billed    NUMBER;
  v_paid      NUMBER;
BEGIN
  IF p_student_id IS NULL THEN
    RAISE_APPLICATION_ERROR(-20031, 'Student ID is required');
  END IF;

  -- SELECT INTO raises NO_DATA_FOUND when no row matches.
  SELECT roll_no INTO v_roll FROM students WHERE student_id = p_student_id;

  SELECT NVL(SUM(total_amount), 0)
    INTO v_billed
    FROM invoices
   WHERE student_id = p_student_id;

  SELECT NVL(SUM(p.amount), 0)
    INTO v_paid
    FROM payments p
    JOIN invoices i ON i.invoice_id = p.invoice_id
   WHERE i.student_id = p_student_id;

  RETURN v_billed - v_paid;
EXCEPTION
  WHEN NO_DATA_FOUND THEN
    RAISE_APPLICATION_ERROR(-20032, 'Student ' || p_student_id || ' does not exist');
END fn_outstanding_balance;
/
SHOW ERRORS

-- ---------------------------------------------------------------------
-- fn_meal_charges(p_student_id, p_month)  [CALCULATION, helper]
-- Sum of (meal rate) for every meal the student ate in that month.
-- p_month can be any date in the month; it is truncated to the 1st.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_meal_charges (
  p_student_id IN students.student_id%TYPE,
  p_month      IN DATE
) RETURN NUMBER
IS
  v_total NUMBER;
BEGIN
  IF p_month IS NULL THEN
    RAISE_APPLICATION_ERROR(-20033, 'Billing month is required');
  END IF;

  SELECT NVL(SUM(mt.rate), 0)
    INTO v_total
    FROM meal_log ml
    JOIN meal_types mt ON mt.meal_type_id = ml.meal_type_id
   WHERE ml.student_id = p_student_id
     AND ml.meal_date >= TRUNC(p_month, 'MM')
     AND ml.meal_date <  ADD_MONTHS(TRUNC(p_month, 'MM'), 1);

  RETURN v_total;
END fn_meal_charges;
/
SHOW ERRORS

PROMPT 03_functions.sql finished.
