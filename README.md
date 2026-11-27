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
  00_run_all.sql       runs 02 to 12 and saves the output to run_all.log
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
docs/
  data_dictionary.md   every table, column and constraint (for the report)
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
   It runs scripts 02 to 12 in order and writes the output to `run_all.log`.
3. Check the end of the output:
   - the test block prints `PASSED: 19   FAILED: 0`
   - the invalid-objects query prints `no rows selected`

From a terminal instead (SQLcl or SQL*Plus):

```bash
cd database
sql hostelhub/Hostel_Hub_2026@localhost:1521/FREEPDB1   # or: sqlplus ...
SQL> @00_run_all.sql
```

You can also run the files one by one in number order (02 to 12). The whole set is re-runnable: `02_schema.sql` drops and recreates every table, so running `00_run_all.sql` again always gives the same clean data.

> If something fails, send back `run_all.log` (or a screenshot of the first error).

### Demo logins (for the web app in M3)

| Username | Password | Role |
|---|---|---|
| `admin` | `Admin@123` | ADMIN |
| `warden.ali` | `Warden@123` | WARDEN |
| `warden.sana` | `Warden@123` | WARDEN |

Only bcrypt hashes are stored in `APP_USERS`. These are demo passwords for the lab; the real database password for the backend goes in a `.env` file that is never committed.

## Web application (M3): how to run it

```
backend/                 Node.js + Express API (the only thing that talks to the databases)
  .env.example           copy to .env and fill in (never commit .env)
  src/server.js          starts the app, mounts the routes, serves frontend/
  src/config.js          reads .env
  src/db/oracle.js       node-oracledb pool, bind-variable helpers
  src/db/mongo.js        MongoDB connection (complaints)
  src/middleware/        auth.js (JWT cookie, roles), errors.js (ORA-200xx -> messages)
  src/validation.js      server-side validation for every form
  src/routes/            auth, dashboard, students, allocations, invoices, reports, complaints, audit
  src/seedMongo.js       npm run seed:mongo
  tests/api_tests.js     npm run test:api  (28 checks: T01 to T13 through the API)
frontend/                plain HTML + CSS + JavaScript, no build step
  *.html                 one file per screen
  js/app.js              shared: api() calls, sidebar, messages, field errors
  js/<screen>.js         one script per screen
mongodb/
  complaints_seed.json   22 complaint documents
  complaints_crud.mongosh.js  insertMany / insertOne / find / updateOne / deleteOne with before and after
```

### What you need

- The Oracle database from the steps above (HOSTELHUB schema loaded)
- **Node.js 18 or newer** (https://nodejs.org, LTS version)
- **MongoDB Community Server** and **mongosh** (https://www.mongodb.com/try/download/community). MongoDB Compass is optional.

No Oracle Instant Client is needed: node-oracledb runs in Thin mode.

### Step 1: configure and install

```bash
cd backend
copy .env.example .env        # Windows   (Mac/Linux: cp .env.example .env)
npm install
```

Open `backend/.env` and set `ORACLE_PASSWORD=Hostel_Hub_2026`, check `ORACLE_CONNECT_STRING` (`localhost:1521/FREEPDB1`, or `XEPDB1` for 21c XE), and put any long random text in `JWT_SECRET`.

### Step 2: load the MongoDB complaints

With MongoDB running, either:

```bash
npm run seed:mongo                     # from backend/: loads the 22 complaints
```

or run the CRUD demo for the report screenshots (from the repository's top folder). It reloads the 22 documents and then shows insertOne, find, updateOne and deleteOne with before/after output:

```bash
mongosh "mongodb://localhost:27017/hostelhub" mongodb/complaints_crud.mongosh.js
```

### Step 3: start the app

```bash
cd backend
npm start
```

You should see `Oracle connected as HOSTELHUB`, `MongoDB connected` and `HostelHub running at http://localhost:3000`. Open **http://localhost:3000** and log in with a demo account above. If MongoDB is not running the app still starts; only the Complaints screen is unavailable.

### Step 4 (optional): run the API tests

Leave `npm start` running, open a second terminal:

```bash
cd backend
npm run test:api
```

It prints a table with Test ID, Expected, Actual and PASS/FAIL (`PASSED: 28   FAILED: 0`). It leaves one "Api Test Student" (roll 29xxxx) behind, because a student with allocation history cannot be deleted; re-run `database/00_run_all.sql` before the final demo for clean data.

### Screens

| # | Screen | What it shows | Roles |
|---|---|---|---|
| 1 | Login (`login.html`) | bcrypt password check, error on wrong password | everyone |
| 2 | Dashboard | KPI tiles, **analytics chart** (daily mess revenue + running total from `v_mess_daily_revenue`), block occupancy from `fn_occupancy_pct` / `fn_occupancy_band`, recent audit rows | ADMIN, WARDEN |
| 3 | Students | search by name / roll / email / program, gender and bed filters, paging | ADMIN, WARDEN (Delete: ADMIN) |
| 4 | Add / edit student | form with browser + server validation, Oracle constraint errors shown on the right field | ADMIN, WARDEN |
| 5 | **Allocate Bed** | the business transaction: calls `pr_allocate_bed` with a browser-generated `client_request_id`; shows CREATED / REPLAYED / ORA-20010 and the audit rows for that request; vacate button (`pr_vacate_bed`) | ADMIN, WARDEN |
| 6 | Invoices | list and filters; generate invoices (`pr_generate_invoice`, one student or every resident with a SAVEPOINT per student); record payments (`trg_payment_audit`) | view: both; billing: ADMIN |
| 7 | Reports | the 4 analytical reports: running total, 7-day moving average, partitioned RANK, LAG/LEAD trend | ADMIN, WARDEN |
| 8 | Complaints | **MongoDB** create (insertOne), list/search (find), status change (updateOne), stats (aggregate), delete (ADMIN) | ADMIN, WARDEN |
| 9 | Audit log | every AUDIT_LOG row with filters | ADMIN only (a warden gets "access denied" and HTTP 403) |

### Demonstrating safe retries in the browser (T09 to T11)

1. Allocate Bed: choose a student and a bed, click **Allocate bed**: result **CREATED** (HTTP 201), one `ALLOCATE_SUCCESS` audit row.
2. Click **Send same request again**: result **REPLAYED** (HTTP 200), same allocation number, no new audit row, bed count unchanged.
3. Pick a different bed and click **Send same request again**: rejected with **ORA-20010** (HTTP 409); the first allocation is unchanged and only an `ALLOCATE_FAILED` note is logged.
4. **Start new allocation** creates a new request ID for the next, separate allocation.

### API endpoints

All under `/api`, JSON in and out. Everything except login needs the login cookie.

| Method and path | Does | Oracle / MongoDB |
|---|---|---|
| `POST /auth/login`, `POST /auth/logout`, `GET /auth/me` | login with two roles | `APP_USERS` (bcrypt), `AUDIT_LOG` |
| `GET /dashboard`, `GET /dashboard/revenue` | dashboard data and chart | functions, views, `countDocuments` |
| `GET/POST /students`, `GET/PUT/DELETE /students/:id` | student CRUD (DELETE: ADMIN) | `STUDENTS`, `fn_outstanding_balance` |
| `GET /allocations/options`, `GET /allocations` | form lists and current allocations | `v_vacant_beds`, `v_bed_occupancy` |
| `POST /allocations` | **allocate (retry-safe)** | `pr_allocate_bed` |
| `POST /allocations/:id/vacate` | vacate | `pr_vacate_bed` |
| `GET /allocations/audit/:requestId` | audit rows of one request | `AUDIT_LOG` |
| `GET /invoices`, `GET /invoices/:id` | invoices | `INVOICES`, `PAYMENTS` |
| `POST /invoices/generate`, `POST /invoices/generate-month` | billing (ADMIN) | `pr_generate_invoice`, SAVEPOINT |
| `POST /invoices/:id/payments` | payment (ADMIN) | `trg_payment_audit` |
| `GET /reports/running-total`, `/moving-average`, `/room-ranking`, `/mess-trend` | 4 analytical reports | window functions |
| `GET/POST /complaints`, `GET /complaints/stats`, `GET/PATCH/DELETE /complaints/:id` | complaints | MongoDB `complaints` |
| `GET /audit` | audit log (ADMIN) | `AUDIT_LOG` |

### Security choices (for the report)

- The browser only calls the backend. Database users and passwords exist only in `backend/.env`.
- Every Oracle statement uses bind variables (`:name`), never string concatenation, so input cannot change the SQL. MongoDB filters are built only from allowed values, and search text is regex-escaped.
- Passwords are stored as bcrypt hashes; login compares hashes and takes the same time for an unknown username.
- The login is a signed JWT in an `httpOnly`, `sameSite=strict` cookie. Roles are checked on the server (`requireRole('ADMIN')`); hiding buttons in the page is only for a tidy screen.
- The user id passed to PL/SQL comes from the login token, never from the browser.
- Every form is validated in the browser for quick feedback and again on the server (`src/validation.js`); Oracle constraints and triggers are the last line of defence. Errors come back as clear messages with the Oracle code (for example `ORA-20010`).
- `helmet` adds security headers, including a Content-Security-Policy that only allows scripts from this server.

### Requirement map (web part)

| Requirement | Where |
|---|---|
| Custom frontend + backend API connected to Oracle | `frontend/`, `backend/src/routes/` |
| 5+ screens: login, dashboard, search/list, add/edit, transaction | screens 1 to 5 above (9 in total) |
| Validation and error messages | `src/validation.js`, `src/middleware/errors.js`, `showMessage()` / `showFieldErrors()` in `js/app.js` |
| Analytical report visible on the website | Dashboard chart + Reports screen |
| Critical action calls PL/SQL with parameterized SQL | `routes/allocations.js` -> `pr_allocate_bed` |
| Login, two roles, no plaintext passwords, `.env.example` | `routes/auth.js`, `middleware/auth.js`, `backend/.env.example` |
| `client_request_id` passed to Oracle, retries tested from the browser and API | Allocate Bed screen, `tests/api_tests.js` T09 to T11 |
| MongoDB collection with 20+ documents, mongosh CRUD | `mongodb/complaints_seed.json` (22), `mongodb/complaints_crud.mongosh.js` |
| MongoDB create/read feature on the website | Complaints screen, `routes/complaints.js` |

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
- **M4** Indexes with before/after `DBMS_XPLAN`, Data Pump backup/restore, APEX report, HA/RAC diagram, test table, report and ZIP

## Note on dates

The sample data is fixed to the Fall 2026 term (15 Aug 2026 to 31 Jan 2027) with meals logged up to 26 Nov 2026. The allocation trigger rejects terms that have already ended, so if you demo after 31 Jan 2027, move the Fall 2026 `end_date` forward in `06_seed_data.sql`.
