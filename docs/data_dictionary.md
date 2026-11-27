# HostelHub data dictionary

Generated from the Oracle data dictionary (`USER_TAB_COLUMNS`, `USER_CONSTRAINTS`) after running the scripts in `database/`. Null? = N means NOT NULL.

Function-based unique indexes (not shown as constraints): `UX_ALLOC_ACTIVE_STUDENT` (one ACTIVE allocation per student per term), `UX_ALLOC_ACTIVE_BED` (one ACTIVE allocation per bed per term), `UX_TERMS_ONE_CURRENT` (only one current term).

## APP_USERS

Staff accounts for the web app (ADMIN, WARDEN). Passwords stored as bcrypt hashes only.

| # | Column | Type | Null? | Keys |
|---|---|---|---|---|
| 1 | USER_ID | NUMBER | N | PK |
| 2 | USERNAME | VARCHAR2(30) | N | UNIQUE |
| 3 | PASSWORD_HASH | VARCHAR2(100) | N |  |
| 4 | FULL_NAME | VARCHAR2(80) | N |  |
| 5 | ROLE | VARCHAR2(10) | N |  |
| 6 | IS_ACTIVE | CHAR(1) | N |  |
| 7 | CREATED_AT | TIMESTAMP(6) | N |  |

CHECK constraints:

- `CK_APP_USERS_ACTIVE`: `is_active IN ('Y','N')`
- `CK_APP_USERS_HASH`: `password_hash LIKE '$2_$%' AND LENGTH(password_hash) = 60`
- `CK_APP_USERS_ROLE`: `role IN ('ADMIN','WARDEN')`

## STUDENTS

Hostel residents and applicants.

| # | Column | Type | Null? | Keys |
|---|---|---|---|---|
| 1 | STUDENT_ID | NUMBER | N | PK |
| 2 | ROLL_NO | VARCHAR2(20) | N | UNIQUE |
| 3 | FULL_NAME | VARCHAR2(80) | N |  |
| 4 | GENDER | CHAR(1) | N |  |
| 5 | EMAIL | VARCHAR2(100) | N | UNIQUE |
| 6 | PHONE | VARCHAR2(20) | Y |  |
| 7 | PROGRAM | VARCHAR2(40) | N |  |
| 8 | SEMESTER | NUMBER(1) | N |  |
| 9 | CREATED_AT | TIMESTAMP(6) | N |  |

CHECK constraints:

- `CK_STUDENTS_EMAIL`: `email LIKE '_%@_%._%'`
- `CK_STUDENTS_GENDER`: `gender IN ('M','F')`
- `CK_STUDENTS_SEMESTER`: `semester BETWEEN 1 AND 8`

## ROOM_TYPES

Room categories; monthly rent depends on the type (3NF).

| # | Column | Type | Null? | Keys |
|---|---|---|---|---|
| 1 | ROOM_TYPE_ID | NUMBER | N | PK |
| 2 | NAME | VARCHAR2(20) | N | UNIQUE |
| 3 | BEDS_PER_ROOM | NUMBER(1) | N |  |
| 4 | MONTHLY_RENT | NUMBER(10,2) | N |  |
| 5 | DESCRIPTION | VARCHAR2(200) | Y |  |

CHECK constraints:

- `CK_ROOM_TYPES_BEDS`: `beds_per_room BETWEEN 1 AND 6`
- `CK_ROOM_TYPES_RENT`: `monthly_rent > 0`

## HOSTEL_UNITS

Self-referencing hostel layout: BLOCK > FLOOR > ROOM.

| # | Column | Type | Null? | Keys |
|---|---|---|---|---|
| 1 | UNIT_ID | NUMBER | N | PK |
| 2 | PARENT_UNIT_ID | NUMBER | Y | FK -> HOSTEL_UNITS, UNIQUE |
| 3 | UNIT_TYPE | VARCHAR2(5) | N |  |
| 4 | UNIT_CODE | VARCHAR2(20) | N | UNIQUE |
| 5 | UNIT_NAME | VARCHAR2(60) | N |  |
| 6 | GENDER_POLICY | CHAR(1) | Y |  |
| 7 | ROOM_TYPE_ID | NUMBER | Y | FK -> ROOM_TYPES |

CHECK constraints:

- `CK_UNITS_BLOCK_RULES`: `	     (unit_type = 'BLOCK' AND parent_unit_id IS NULL AND gender_policy IS NOT NULL)	 OR (unit_type <> 'BLOCK' AND parent_unit_id IS NOT NULL AND gender_policy IS NULL)`
- `CK_UNITS_GENDER`: `gender_policy IN ('M','F')`
- `CK_UNITS_ROOM_RULES`: `	    (unit_type = 'ROOM'  AND room_type_id IS NOT NULL)	    OR (unit_type <> 'ROOM' AND room_type_id IS NULL)`
- `CK_UNITS_TYPE`: `unit_type IN ('BLOCK','FLOOR','ROOM')`

## BEDS

Beds inside a ROOM unit, with their current status.

| # | Column | Type | Null? | Keys |
|---|---|---|---|---|
| 1 | BED_ID | NUMBER | N | PK |
| 2 | ROOM_UNIT_ID | NUMBER | N | FK -> HOSTEL_UNITS, UNIQUE |
| 3 | BED_LABEL | VARCHAR2(5) | N | UNIQUE |
| 4 | STATUS | VARCHAR2(12) | N |  |

CHECK constraints:

- `CK_BEDS_STATUS`: `status IN ('AVAILABLE','OCCUPIED','MAINTENANCE')`

## ACADEMIC_TERMS

Terms; exactly one is marked current.

| # | Column | Type | Null? | Keys |
|---|---|---|---|---|
| 1 | TERM_ID | NUMBER | N | PK |
| 2 | NAME | VARCHAR2(20) | N | UNIQUE |
| 3 | START_DATE | DATE | N |  |
| 4 | END_DATE | DATE | N |  |
| 5 | IS_CURRENT | CHAR(1) | N |  |

CHECK constraints:

- `CK_TERMS_CURRENT`: `is_current IN ('Y','N')`
- `CK_TERMS_DATES`: `end_date > start_date`

## ALLOCATIONS

Student-to-bed assignment for a term. Hub of the retry-safe core transaction.

| # | Column | Type | Null? | Keys |
|---|---|---|---|---|
| 1 | ALLOCATION_ID | NUMBER | N | PK |
| 2 | CLIENT_REQUEST_ID | VARCHAR2(64) | N | UNIQUE |
| 3 | STUDENT_ID | NUMBER | N | FK -> STUDENTS |
| 4 | BED_ID | NUMBER | N | FK -> BEDS |
| 5 | TERM_ID | NUMBER | N | FK -> ACADEMIC_TERMS |
| 6 | ALLOCATED_BY | NUMBER | N | FK -> APP_USERS |
| 7 | ALLOCATED_AT | TIMESTAMP(6) | N |  |
| 8 | STATUS | VARCHAR2(8) | N |  |
| 9 | VACATED_AT | TIMESTAMP(6) | Y |  |

CHECK constraints:

- `CK_ALLOC_STATUS`: `status IN ('ACTIVE','VACATED')`
- `CK_ALLOC_VACATED`: ` 	(status = 'ACTIVE'  AND vacated_at IS NULL)	 OR (status = 'VACATED' AND vacated_at IS NOT NULL)`

## MEAL_TYPES

Breakfast, Lunch, Dinner and their rates (3NF).

| # | Column | Type | Null? | Keys |
|---|---|---|---|---|
| 1 | MEAL_TYPE_ID | NUMBER | N | PK |
| 2 | NAME | VARCHAR2(20) | N | UNIQUE |
| 3 | RATE | NUMBER(8,2) | N |  |
| 4 | SERVE_ORDER | NUMBER(1) | N |  |

CHECK constraints:

- `CK_MEAL_TYPES_RATE`: `rate > 0`

## MEAL_LOG

One row per meal eaten; never charged twice.

| # | Column | Type | Null? | Keys |
|---|---|---|---|---|
| 1 | MEAL_LOG_ID | NUMBER | N | PK |
| 2 | STUDENT_ID | NUMBER | N | FK -> STUDENTS, UNIQUE |
| 3 | MEAL_TYPE_ID | NUMBER | N | FK -> MEAL_TYPES, UNIQUE |
| 4 | MEAL_DATE | DATE | N | UNIQUE |
| 5 | RECORDED_BY | NUMBER | N | FK -> APP_USERS |
| 6 | RECORDED_AT | TIMESTAMP(6) | N |  |

CHECK constraints:

- `CK_MEAL_DATE_TRUNC`: `meal_date = TRUNC(meal_date)`

## INVOICES

Monthly bill: rent + mess snapshot.

| # | Column | Type | Null? | Keys |
|---|---|---|---|---|
| 1 | INVOICE_ID | NUMBER | N | PK |
| 2 | STUDENT_ID | NUMBER | N | FK -> STUDENTS, UNIQUE |
| 3 | ALLOCATION_ID | NUMBER | N | FK -> ALLOCATIONS |
| 4 | BILLING_MONTH | DATE | N | UNIQUE |
| 5 | RENT_AMOUNT | NUMBER(10,2) | N |  |
| 6 | MESS_AMOUNT | NUMBER(10,2) | N |  |
| 7 | TOTAL_AMOUNT | NUMBER(10,2) | N |  |
| 8 | STATUS | VARCHAR2(8) | N |  |
| 9 | DUE_DATE | DATE | N |  |
| 10 | GENERATED_BY | NUMBER | Y | FK -> APP_USERS |
| 11 | GENERATED_AT | TIMESTAMP(6) | N |  |

CHECK constraints:

- `CK_INV_AMOUNTS`: `rent_amount >= 0 AND mess_amount >= 0 AND total_amount >= 0`
- `CK_INV_MONTH`: `billing_month = TRUNC(billing_month, 'MM')`
- `CK_INV_STATUS`: `status IN ('UNPAID','PARTIAL','PAID')`
- `CK_INV_TOTAL`: `total_amount = rent_amount + mess_amount`

## PAYMENTS

Money received against an invoice.

| # | Column | Type | Null? | Keys |
|---|---|---|---|---|
| 1 | PAYMENT_ID | NUMBER | N | PK |
| 2 | INVOICE_ID | NUMBER | N | FK -> INVOICES |
| 3 | AMOUNT | NUMBER(10,2) | N |  |
| 4 | METHOD | VARCHAR2(5) | N |  |
| 5 | REFERENCE_NO | VARCHAR2(40) | Y |  |
| 6 | PAID_AT | TIMESTAMP(6) | N |  |
| 7 | RECEIVED_BY | NUMBER | N | FK -> APP_USERS |

CHECK constraints:

- `CK_PAY_AMOUNT`: `amount > 0`
- `CK_PAY_METHOD`: `method IN ('CASH','BANK','CARD')`

## AUDIT_LOG

Trail of allocations, failures and payments.

| # | Column | Type | Null? | Keys |
|---|---|---|---|---|
| 1 | AUDIT_ID | NUMBER | N | PK |
| 2 | USER_ID | NUMBER | Y | FK -> APP_USERS |
| 3 | ACTION | VARCHAR2(30) | N |  |
| 4 | CLIENT_REQUEST_ID | VARCHAR2(64) | Y |  |
| 5 | TABLE_NAME | VARCHAR2(30) | Y |  |
| 6 | RECORD_ID | NUMBER | Y |  |
| 7 | DETAILS | VARCHAR2(4000) | Y |  |
| 8 | LOGGED_AT | TIMESTAMP(6) | N |  |
