/* =====================================================================
   HostelHub | 02_schema.sql
   ---------------------------------------------------------------------
   RUN AS: HOSTELHUB
   WHAT IT DOES: drops (if present) and creates the 12 tables of the
   HostelHub design with every PK, FK, UNIQUE, NOT NULL and CHECK
   constraint. Constraints are NAMED (pk_, fk_, uq_, ck_) so that an
   error message such as "ORA-00001: unique constraint
   (HOSTELHUB.UQ_STUDENTS_ROLL) violated" tells you exactly what failed.

   Table overview (parents first):
     APP_USERS       staff who log in (ADMIN / WARDEN)
     STUDENTS        hostel residents
     ROOM_TYPES      Single / Double / Triple / Quad with rent
     HOSTEL_UNITS    BLOCK > FLOOR > ROOM hierarchy (self-referencing)
     BEDS            beds inside a ROOM
     ACADEMIC_TERMS  Spring / Fall terms
     ALLOCATIONS     student <-> bed for a term (core transaction)
     MEAL_TYPES      Breakfast / Lunch / Dinner with rate
     MEAL_LOG        one row per meal eaten
     INVOICES        monthly bill (rent + mess)
     PAYMENTS        money received against an invoice
     AUDIT_LOG       trail of important actions

   Primary keys use IDENTITY columns (Oracle 12c+), so Oracle generates
   the numbers and no separate sequences are needed.
   ===================================================================== */

SET SERVEROUTPUT ON

-- ---------------------------------------------------------------------
-- 0. Drop old objects so the script can be re-run safely.
--    ORA-00942 (table does not exist) is ignored on the first run.
-- ---------------------------------------------------------------------
BEGIN
  FOR t IN (SELECT column_value AS table_name
              FROM TABLE(sys.odcivarchar2list(
                     'AUDIT_LOG','PAYMENTS','INVOICES','MEAL_LOG','MEAL_TYPES',
                     'ALLOCATIONS','ACADEMIC_TERMS','BEDS','HOSTEL_UNITS',
                     'ROOM_TYPES','STUDENTS','APP_USERS'))) LOOP
    BEGIN
      EXECUTE IMMEDIATE 'DROP TABLE ' || t.table_name || ' CASCADE CONSTRAINTS PURGE';
      DBMS_OUTPUT.PUT_LINE('Dropped ' || t.table_name);
    EXCEPTION
      WHEN OTHERS THEN
        IF SQLCODE != -942 THEN RAISE; END IF;
    END;
  END LOOP;
END;
/

-- ---------------------------------------------------------------------
-- 1. APP_USERS: staff accounts for the web application.
--    Passwords are stored ONLY as bcrypt hashes, never plain text.
-- ---------------------------------------------------------------------
CREATE TABLE app_users (
  user_id        NUMBER        GENERATED ALWAYS AS IDENTITY,
  username       VARCHAR2(30)  NOT NULL,
  password_hash  VARCHAR2(100) NOT NULL,
  full_name      VARCHAR2(80)  NOT NULL,
  role           VARCHAR2(10)  NOT NULL,
  is_active      CHAR(1)       DEFAULT 'Y' NOT NULL,
  created_at     TIMESTAMP     DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT pk_app_users        PRIMARY KEY (user_id),
  CONSTRAINT uq_app_users_name   UNIQUE (username),
  CONSTRAINT ck_app_users_role   CHECK (role IN ('ADMIN','WARDEN')),
  CONSTRAINT ck_app_users_active CHECK (is_active IN ('Y','N')),
  -- a bcrypt hash always starts with $2a$, $2b$ or $2y$ and is 60 chars
  CONSTRAINT ck_app_users_hash   CHECK (password_hash LIKE '$2_$%' AND LENGTH(password_hash) = 60)
);

-- ---------------------------------------------------------------------
-- 2. STUDENTS
-- ---------------------------------------------------------------------
CREATE TABLE students (
  student_id   NUMBER        GENERATED ALWAYS AS IDENTITY,
  roll_no      VARCHAR2(20)  NOT NULL,
  full_name    VARCHAR2(80)  NOT NULL,
  gender       CHAR(1)       NOT NULL,
  email        VARCHAR2(100) NOT NULL,
  phone        VARCHAR2(20),
  program      VARCHAR2(40)  NOT NULL,
  semester     NUMBER(1)     NOT NULL,
  created_at   TIMESTAMP     DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT pk_students          PRIMARY KEY (student_id),
  CONSTRAINT uq_students_roll     UNIQUE (roll_no),
  CONSTRAINT uq_students_email    UNIQUE (email),
  CONSTRAINT ck_students_gender   CHECK (gender IN ('M','F')),
  CONSTRAINT ck_students_semester CHECK (semester BETWEEN 1 AND 8),
  CONSTRAINT ck_students_email    CHECK (email LIKE '_%@_%._%')
);

-- ---------------------------------------------------------------------
-- 3. ROOM_TYPES: rent depends on the TYPE of room (3NF), not the room.
-- ---------------------------------------------------------------------
CREATE TABLE room_types (
  room_type_id   NUMBER        GENERATED ALWAYS AS IDENTITY,
  name           VARCHAR2(20)  NOT NULL,
  beds_per_room  NUMBER(1)     NOT NULL,
  monthly_rent   NUMBER(10,2)  NOT NULL,
  description    VARCHAR2(200),
  CONSTRAINT pk_room_types       PRIMARY KEY (room_type_id),
  CONSTRAINT uq_room_types_name  UNIQUE (name),
  CONSTRAINT ck_room_types_beds  CHECK (beds_per_room BETWEEN 1 AND 6),
  CONSTRAINT ck_room_types_rent  CHECK (monthly_rent > 0)
);

-- ---------------------------------------------------------------------
-- 4. HOSTEL_UNITS: the hostel layout as ONE self-referencing table.
--    BLOCK (parent NULL) > FLOOR (parent = block) > ROOM (parent = floor)
--    This hierarchy is what the recursive CONNECT BY query walks.
-- ---------------------------------------------------------------------
CREATE TABLE hostel_units (
  unit_id         NUMBER        GENERATED ALWAYS AS IDENTITY,
  parent_unit_id  NUMBER,
  unit_type       VARCHAR2(5)   NOT NULL,
  unit_code       VARCHAR2(20)  NOT NULL,
  unit_name       VARCHAR2(60)  NOT NULL,
  gender_policy   CHAR(1),               -- only for BLOCKs: M or F
  room_type_id    NUMBER,                -- only for ROOMs
  CONSTRAINT pk_hostel_units        PRIMARY KEY (unit_id),
  CONSTRAINT fk_units_parent        FOREIGN KEY (parent_unit_id) REFERENCES hostel_units (unit_id),
  CONSTRAINT fk_units_room_type     FOREIGN KEY (room_type_id)   REFERENCES room_types (room_type_id),
  CONSTRAINT uq_units_parent_code   UNIQUE (parent_unit_id, unit_code),
  CONSTRAINT ck_units_type          CHECK (unit_type IN ('BLOCK','FLOOR','ROOM')),
  CONSTRAINT ck_units_gender        CHECK (gender_policy IN ('M','F')),
  -- a BLOCK is a top-level unit with a gender policy; nothing else may have one
  CONSTRAINT ck_units_block_rules   CHECK (
        (unit_type = 'BLOCK' AND parent_unit_id IS NULL AND gender_policy IS NOT NULL)
     OR (unit_type <> 'BLOCK' AND parent_unit_id IS NOT NULL AND gender_policy IS NULL)),
  -- only a ROOM has a room type
  CONSTRAINT ck_units_room_rules    CHECK (
        (unit_type = 'ROOM'  AND room_type_id IS NOT NULL)
     OR (unit_type <> 'ROOM' AND room_type_id IS NULL))
);

-- ---------------------------------------------------------------------
-- 5. BEDS
-- ---------------------------------------------------------------------
CREATE TABLE beds (
  bed_id        NUMBER        GENERATED ALWAYS AS IDENTITY,
  room_unit_id  NUMBER        NOT NULL,
  bed_label     VARCHAR2(5)   NOT NULL,
  status        VARCHAR2(12)  DEFAULT 'AVAILABLE' NOT NULL,
  CONSTRAINT pk_beds            PRIMARY KEY (bed_id),
  CONSTRAINT fk_beds_room       FOREIGN KEY (room_unit_id) REFERENCES hostel_units (unit_id),
  CONSTRAINT uq_beds_room_label UNIQUE (room_unit_id, bed_label),
  CONSTRAINT ck_beds_status     CHECK (status IN ('AVAILABLE','OCCUPIED','MAINTENANCE'))
);

-- ---------------------------------------------------------------------
-- 6. ACADEMIC_TERMS
-- ---------------------------------------------------------------------
CREATE TABLE academic_terms (
  term_id     NUMBER        GENERATED ALWAYS AS IDENTITY,
  name        VARCHAR2(20)  NOT NULL,
  start_date  DATE          NOT NULL,
  end_date    DATE          NOT NULL,
  is_current  CHAR(1)       DEFAULT 'N' NOT NULL,
  CONSTRAINT pk_academic_terms   PRIMARY KEY (term_id),
  CONSTRAINT uq_terms_name       UNIQUE (name),
  CONSTRAINT ck_terms_dates      CHECK (end_date > start_date),
  CONSTRAINT ck_terms_current    CHECK (is_current IN ('Y','N'))
);
-- Only ONE term may be marked current: a unique index that ignores 'N' rows
-- (Oracle does not index rows where every indexed expression is NULL).
CREATE UNIQUE INDEX ux_terms_one_current
  ON academic_terms (CASE WHEN is_current = 'Y' THEN 'Y' END);

-- ---------------------------------------------------------------------
-- 7. ALLOCATIONS: the hub of the core "Allocate Bed" transaction.
--    client_request_id is UNIQUE, so a retried browser request can
--    never create a second allocation.
-- ---------------------------------------------------------------------
CREATE TABLE allocations (
  allocation_id      NUMBER        GENERATED ALWAYS AS IDENTITY,
  client_request_id  VARCHAR2(64)  NOT NULL,
  student_id         NUMBER        NOT NULL,
  bed_id             NUMBER        NOT NULL,
  term_id            NUMBER        NOT NULL,
  allocated_by       NUMBER        NOT NULL,
  allocated_at       TIMESTAMP     DEFAULT SYSTIMESTAMP NOT NULL,
  status             VARCHAR2(8)   DEFAULT 'ACTIVE' NOT NULL,
  vacated_at         TIMESTAMP,
  CONSTRAINT pk_allocations         PRIMARY KEY (allocation_id),
  CONSTRAINT uq_alloc_request       UNIQUE (client_request_id),
  CONSTRAINT fk_alloc_student       FOREIGN KEY (student_id)   REFERENCES students (student_id),
  CONSTRAINT fk_alloc_bed           FOREIGN KEY (bed_id)       REFERENCES beds (bed_id),
  CONSTRAINT fk_alloc_term          FOREIGN KEY (term_id)      REFERENCES academic_terms (term_id),
  CONSTRAINT fk_alloc_user          FOREIGN KEY (allocated_by) REFERENCES app_users (user_id),
  CONSTRAINT ck_alloc_status        CHECK (status IN ('ACTIVE','VACATED')),
  -- vacated_at is filled exactly when the allocation is VACATED
  CONSTRAINT ck_alloc_vacated       CHECK (
        (status = 'ACTIVE'  AND vacated_at IS NULL)
     OR (status = 'VACATED' AND vacated_at IS NOT NULL))
);
-- Function-based UNIQUE indexes: only ACTIVE rows are indexed, so
--   * a student can hold only ONE active allocation per term, and
--   * a bed can be given to only ONE student per term,
-- while any number of old VACATED rows can stay for history.
CREATE UNIQUE INDEX ux_alloc_active_student ON allocations (
  CASE WHEN status = 'ACTIVE' THEN student_id END,
  CASE WHEN status = 'ACTIVE' THEN term_id    END);
CREATE UNIQUE INDEX ux_alloc_active_bed ON allocations (
  CASE WHEN status = 'ACTIVE' THEN bed_id  END,
  CASE WHEN status = 'ACTIVE' THEN term_id END);

-- ---------------------------------------------------------------------
-- 8. MEAL_TYPES: a meal's price depends on its type (3NF).
-- ---------------------------------------------------------------------
CREATE TABLE meal_types (
  meal_type_id  NUMBER        GENERATED ALWAYS AS IDENTITY,
  name          VARCHAR2(20)  NOT NULL,
  rate          NUMBER(8,2)   NOT NULL,
  serve_order   NUMBER(1)     NOT NULL,
  CONSTRAINT pk_meal_types       PRIMARY KEY (meal_type_id),
  CONSTRAINT uq_meal_types_name  UNIQUE (name),
  CONSTRAINT ck_meal_types_rate  CHECK (rate > 0)
);

-- ---------------------------------------------------------------------
-- 9. MEAL_LOG: one row per meal eaten.
--    UNIQUE (student, date, meal type) so a meal is never charged twice.
-- ---------------------------------------------------------------------
CREATE TABLE meal_log (
  meal_log_id   NUMBER     GENERATED ALWAYS AS IDENTITY,
  student_id    NUMBER     NOT NULL,
  meal_type_id  NUMBER     NOT NULL,
  meal_date     DATE       NOT NULL,
  recorded_by   NUMBER     NOT NULL,
  recorded_at   TIMESTAMP  DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT pk_meal_log          PRIMARY KEY (meal_log_id),
  CONSTRAINT fk_meal_student      FOREIGN KEY (student_id)   REFERENCES students (student_id),
  CONSTRAINT fk_meal_type         FOREIGN KEY (meal_type_id) REFERENCES meal_types (meal_type_id),
  CONSTRAINT fk_meal_user         FOREIGN KEY (recorded_by)  REFERENCES app_users (user_id),
  CONSTRAINT uq_meal_once         UNIQUE (student_id, meal_date, meal_type_id),
  CONSTRAINT ck_meal_date_trunc   CHECK (meal_date = TRUNC(meal_date))  -- date only, no time part
);

-- ---------------------------------------------------------------------
-- 10. INVOICES: one bill per student per month.
--     rent_amount and mess_amount are a SNAPSHOT of what was billed, so a
--     later rate change never rewrites an old invoice (documented 3NF
--     exception). total_amount must equal rent + mess.
-- ---------------------------------------------------------------------
CREATE TABLE invoices (
  invoice_id     NUMBER        GENERATED ALWAYS AS IDENTITY,
  student_id     NUMBER        NOT NULL,
  allocation_id  NUMBER        NOT NULL,
  billing_month  DATE          NOT NULL,
  rent_amount    NUMBER(10,2)  NOT NULL,
  mess_amount    NUMBER(10,2)  NOT NULL,
  total_amount   NUMBER(10,2)  NOT NULL,
  status         VARCHAR2(8)   DEFAULT 'UNPAID' NOT NULL,
  due_date       DATE          NOT NULL,
  generated_by   NUMBER,
  generated_at   TIMESTAMP     DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT pk_invoices          PRIMARY KEY (invoice_id),
  CONSTRAINT fk_inv_student       FOREIGN KEY (student_id)    REFERENCES students (student_id),
  CONSTRAINT fk_inv_allocation    FOREIGN KEY (allocation_id) REFERENCES allocations (allocation_id),
  CONSTRAINT fk_inv_user          FOREIGN KEY (generated_by)  REFERENCES app_users (user_id),
  CONSTRAINT uq_inv_student_month UNIQUE (student_id, billing_month),
  CONSTRAINT ck_inv_amounts       CHECK (rent_amount >= 0 AND mess_amount >= 0 AND total_amount >= 0),
  CONSTRAINT ck_inv_total         CHECK (total_amount = rent_amount + mess_amount),
  CONSTRAINT ck_inv_month         CHECK (billing_month = TRUNC(billing_month, 'MM')), -- 1st of month
  CONSTRAINT ck_inv_status        CHECK (status IN ('UNPAID','PARTIAL','PAID'))
);

-- ---------------------------------------------------------------------
-- 11. PAYMENTS
-- ---------------------------------------------------------------------
CREATE TABLE payments (
  payment_id    NUMBER        GENERATED ALWAYS AS IDENTITY,
  invoice_id    NUMBER        NOT NULL,
  amount        NUMBER(10,2)  NOT NULL,
  method        VARCHAR2(5)   NOT NULL,
  reference_no  VARCHAR2(40),
  paid_at       TIMESTAMP     DEFAULT SYSTIMESTAMP NOT NULL,
  received_by   NUMBER        NOT NULL,
  CONSTRAINT pk_payments        PRIMARY KEY (payment_id),
  CONSTRAINT fk_pay_invoice     FOREIGN KEY (invoice_id)  REFERENCES invoices (invoice_id),
  CONSTRAINT fk_pay_user        FOREIGN KEY (received_by) REFERENCES app_users (user_id),
  CONSTRAINT ck_pay_amount      CHECK (amount > 0),
  CONSTRAINT ck_pay_method      CHECK (method IN ('CASH','BANK','CARD'))
);

-- ---------------------------------------------------------------------
-- 12. AUDIT_LOG: written by the allocation procedure and the payment
--     trigger. user_id is optional because a few system actions have no
--     logged-in user.
-- ---------------------------------------------------------------------
CREATE TABLE audit_log (
  audit_id           NUMBER          GENERATED ALWAYS AS IDENTITY,
  user_id            NUMBER,
  action             VARCHAR2(30)    NOT NULL,
  client_request_id  VARCHAR2(64),
  table_name         VARCHAR2(30),
  record_id          NUMBER,
  details            VARCHAR2(4000),
  logged_at          TIMESTAMP       DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT pk_audit_log     PRIMARY KEY (audit_id),
  CONSTRAINT fk_audit_user    FOREIGN KEY (user_id) REFERENCES app_users (user_id)
);

-- ---------------------------------------------------------------------
-- Indexes on foreign-key columns that are joined often. (Oracle does
-- NOT index FKs automatically.) The two "tuning" indexes with a
-- before/after plan comparison come in M4: 13_indexes_and_plans.sql.
-- ---------------------------------------------------------------------
CREATE INDEX ix_beds_room        ON beds (room_unit_id);
CREATE INDEX ix_units_parent     ON hostel_units (parent_unit_id);
CREATE INDEX ix_alloc_term       ON allocations (term_id, status);
CREATE INDEX ix_invoices_alloc   ON invoices (allocation_id);
CREATE INDEX ix_payments_invoice ON payments (invoice_id);

PROMPT 02_schema.sql finished: 12 tables created.
