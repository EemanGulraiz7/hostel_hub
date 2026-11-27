# HostelHub: Hostel Room Allocation & Mess Billing System

IT433 DB Administration & Management Lab, BSIT 7th semester, semester project.

HostelHub lets hostel staff allocate beds to students each term, log daily meals, and generate monthly invoices (room rent + mess charges). The core business workflow lives in **Oracle** (tables, PL/SQL, views, analytics). A Node.js API and web frontend (M3), a MongoDB complaints module (M3), and the APEX, index, backup and HA work (M4) are built on top of it.

| Member | Roll no. | Main contribution |
|---|---|---|
| Eeman Gulraiz (lead) | 230909 | Oracle schema, PL/SQL, retry-safe allocation, backend API |
| Iman Khan | 230971 | Frontend screens, MongoDB complaints module, analytics reports |
| Zoha Saleem | 230963 | Oracle APEX page, indexes and backup demos, HA diagram, testing, report |

## Repository layout

```
database/              Oracle scripts, numbered in run order
  00_run_all.sql       runs 02 to 13 and saves the output to run_all.log
  01_create_user.sql   run ONCE as SYSTEM: creates the HOSTELHUB schema
  02_schema.sql        12 tables with PK, FK, UNIQUE, NOT NULL, CHECK
  03_functions.sql     fn_occupancy_pct, fn_occupancy_band, fn_outstanding_balance, fn_meal_charges
  04_procedures.sql    pr_allocate_bed (retry-safe), pr_generate_invoice, pr_vacate_bed
  05_triggers.sql      trg_alloc_validate (BEFORE), trg_payment_audit (AFTER), trg_meal_validate
  06_seed_data.sql     sample data: 30 students, 40 beds, 24 allocations, ~4,200 meals, invoices, payments
  07_views.sql         v_bed_occupancy, v_vacant_beds, v_student_dues
  08_queries.sql       5 business queries, 2 recursive queries, CRUD demo
  09_billing_run.sql   parameterized cursor, nested block, exception handling (November billing)
  10_analytics.sql     running total, moving average, ranking, LAG/LEAD
  11_tests.sql         T01-T04 and T09-T11 with Input / Expected / Actual / PASS-FAIL
  12_transaction_control.sql  COMMIT, SAVEPOINT, ROLLBACK
  13_indexes_and_plans.sql    2 tuning indexes with DBMS_XPLAN before/after plans
  14_backup_setup.sql         run ONCE as SYSTEM: Data Pump directory for backups
  15_backup_check.sql         row counts and totals, before/after a restore
  16_simulate_data_loss.sql   backup exercise only: deletes payments and commits
docs/
  data_dictionary.md   every table, column and constraint (for the report)
  backup_restore.md    step-by-step Data Pump backup and restore exercise
  apex_report.md       APEX Vacant Beds report, step by step
  ha_rac_design.md     HA/RAC design, RPO/RTO (diagram: ha_rac_diagram.png / .svg)
  test_cases.md        test table T01 to T13 (database rows filled, web rows to fill)
  report_outline.md    8 to 12 page report plan and ZIP layout
  evidence/            real outputs from the test run (plans, backup logs)
```

## How to run the database scripts (on your own computer)

You need **Oracle Database 23ai Free** (or 21c XE) and **SQL Developer** (or SQLcl / SQL*Plus).

### Step 1: create the schema user (once)

1. In SQL Developer, create a connection as `SYSTEM`:
   - Host `localhost`, Port `1521`
   - **Service name** `FREEPDB1` (23ai Free) or `XEPDB1` (21c XE). Use the pluggable database, not `FREE`/`XE`.
2. Open `database/01_create_user.sql` and press **F5** (Run Script).
   It creates the user `HOSTELHUB` with password `Hostel_Hub_2026`.

### Step 2: run everything as HOSTELHUB

1. Create a second connection: user `hostelhub`, password `Hostel_Hub_2026`, same host, port and service name.
2. Open `database/00_run_all.sql` with that connection and press **F5**.
   It runs scripts 02 to 13 in order and writes the output to `run_all.log`.
3. Check the end of the output:
   - the test block prints `PASSED: 19   FAILED: 0`
   - the invalid-objects query prints `no rows selected`

From a terminal instead (SQLcl or SQL*Plus):

```bash
cd database
sql hostelhub/Hostel_Hub_2026@localhost:1521/FREEPDB1   # or: sqlplus ...
SQL> @00_run_all.sql
```

You can also run the files one by one in number order (02 to 13). The whole set is re-runnable: `02_schema.sql` drops and recreates every table, so running `00_run_all.sql` again always gives the same clean data.

> If something fails, send back `run_all.log` (or a screenshot of the first error).

### Demo logins (for the web app in M3)

| Username | Password | Role |
|---|---|---|
| `admin` | `Admin@123` | ADMIN |
| `warden.ali` | `Warden@123` | WARDEN |
| `warden.sana` | `Warden@123` | WARDEN |

Only bcrypt hashes are stored in `APP_USERS`. These are demo passwords for the lab; the real database password for the backend goes in a `.env` file that is never committed.

## The core transaction: retry-safe Allocate Bed

`pr_allocate_bed(p_client_request_id, p_student_id, p_bed_id, p_term_id, p_user_id, o_allocation_id, o_result)`

The browser generates one `client_request_id` (UUID) per form submission and reuses it on every retry. Oracle enforces `UNIQUE (client_request_id)` on `ALLOCATIONS`.

| Case | Result |
|---|---|
| New request | Allocation inserted, bed set to OCCUPIED, `ALLOCATE_SUCCESS` audit row, COMMIT. `o_result = 'CREATED'` |
| Same request ID, same details | Saved allocation returned, nothing changes. `o_result = 'REPLAYED'` |
| Same request ID, different details | Error `-20010`, original untouched |
| Any failure | Full ROLLBACK: no allocation, bed unchanged, no success audit (an `ALLOCATE_FAILED` note is kept via an autonomous transaction) |

The bed row is locked with `SELECT ... FOR UPDATE`, and the request ID is checked again after the lock, so two identical requests that race still produce one allocation.

## Requirement map (database part)

| Requirement | Where |
|---|---|
| 6+ related tables, constraints, sample data | `02_schema.sql` (12 tables), `06_seed_data.sql` |
| 2 rejected records | `11_tests.sql` T01b (duplicate roll_no), T01c (invalid FK), plus CHECK and NOT NULL |
| 5 SQL queries (joins, subqueries, GROUP BY/HAVING) | `08_queries.sql` Q1 to Q5 |
| 3 views incl. multi-table report | `07_views.sql` (`v_bed_occupancy` joins 6 tables) |
| 2 functions (calculation, validation/NULL) | `03_functions.sql` |
| 2 procedures (multi-table transaction, IN/OUT) | `04_procedures.sql` |
| 2 triggers (BEFORE validation, AFTER audit) with pass/reject tests | `05_triggers.sql`, tests T02a to T02e |
| Cursor, anonymous/nested block, NO_DATA_FOUND, custom error | `09_billing_run.sql` |
| Recursive / hierarchical query | `08_queries.sql` R1 (`CONNECT BY`), R2 (recursive `WITH`) |
| 4 analytical reports | `10_analytics.sql` A1 to A4 (+ view `v_mess_daily_revenue` for the dashboard) |
| Retry-safe transaction with `client_request_id` | `pr_allocate_bed`, tests T09 to T11 |
| COMMIT / SAVEPOINT / ROLLBACK | `12_transaction_control.sql` |
| 2 indexes + before/after plan | `13_indexes_and_plans.sql`, results in `docs/evidence/` |
| Logical backup / restore | `14` to `16` + `docs/backup_restore.md` (Data Pump) |
| APEX report | `docs/apex_report.md` (Interactive Report on `v_vacant_beds`) |
| HA / RAC diagram, RPO / RTO | `docs/ha_rac_design.md`, `docs/ha_rac_diagram.png` |
| Test table T01 to T13 | `docs/test_cases.md` |

### Custom error codes (the backend maps these to messages)

| Code | Meaning |
|---|---|
| -20000 | Required input missing |
| -20001 | Bed does not exist |
| -20002 | Bed is not available |
| -20003 | Student already has an active allocation in this term |
| -20004 | Student gender does not match block policy |
| -20005 | Term has already ended |
| -20006 | Student does not exist |
| -20007 | Term does not exist |
| -20010 | Request ID already used with different details |
| -20020 | Student has no active allocation for that month |
| -20022 | Invoice already exists for that month |
| -20024 | Payment would exceed the invoice total |
| -20031 / -20032 | Student ID missing / student does not exist |
| -20040 / -20041 | Allocation does not exist / already vacated |
| -20050 / -20051 | Meal date in the future / student not a resident on that date |

## Milestones

- **M1** Proposal, ERD, 3NF, core transaction design (done)
- **M2** Oracle database: this folder (done)
- **M3** Node.js + Express API (node-oracledb, bind variables), frontend screens, login with two roles, MongoDB complaints module
- **M4** Indexes with before/after `DBMS_XPLAN`, Data Pump backup/restore, APEX report, HA/RAC diagram, test table (done in this repo); report and ZIP (outline in `docs/report_outline.md`)

## Note on dates

The sample data is fixed to the Fall 2026 term (15 Aug 2026 to 31 Jan 2027) with meals logged up to 26 Nov 2026. The allocation trigger rejects terms that have already ended, so if you demo after 31 Jan 2027, move the Fall 2026 `end_date` forward in `06_seed_data.sql`.
