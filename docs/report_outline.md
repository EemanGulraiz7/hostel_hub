# Group report outline (8 to 12 pages)

Target: **10 pages** of body plus a title page, so there is room either way. A4, 11 pt font, 2.5 cm margins. Screenshots should be cropped and about half a page wide, two per row where possible. Code goes in an appendix or the ZIP, not the body: show at most 10 to 15 lines of any script, the part that proves the point.

Each section lists the source files to copy from, so most of the text already exists.

| # | Section | Pages | Written by | Copy from |
|---|---|---|---|---|
| 0 | Title page | (not counted) | Zoha | below |
| 1 | Introduction and problem | 0.5 | Eeman | M1 doc, README intro |
| 2 | Team and contributions | 0.5 | Zoha | README member table |
| 3 | Database design: ERD, schema, 3NF, constraints | 1.5 | Eeman | M1 doc, `02_schema.sql`, `docs/data_dictionary.md` |
| 4 | SQL, views and recursive query | 1 | Eeman | `07_views.sql`, `08_queries.sql` |
| 5 | PL/SQL: functions, procedures, triggers, cursor, exceptions | 1.5 | Eeman | `03` to `05`, `09_billing_run.sql` |
| 6 | Retry-safe transaction and audit trail | 1 | Eeman | README "core transaction", `04_procedures.sql` |
| 7 | Analytical reports | 0.75 | Iman | `10_analytics.sql`, dashboard screenshot |
| 8 | Web application (frontend + API) and MongoDB | 1.5 | Iman (frontend, MongoDB), Eeman (API) | web app README, screenshots |
| 9 | Oracle APEX mini-demo | 0.25 | Zoha | `docs/apex_report.md` screenshots |
| 10 | Optimization: indexes and query plans | 0.75 | Zoha | `13_indexes_and_plans.sql`, `docs/evidence/13_indexes_and_plans_output.txt` |
| 11 | Administration: transactions, backup/restore, HA/RAC | 1.5 | Zoha | `12_transaction_control.sql`, `docs/backup_restore.md`, `docs/ha_rac_design.md` |
| 12 | Testing | 1 | Zoha | `docs/test_cases.md` |
| 13 | Conclusion and limitations | 0.25 | Eeman | below |
| | **Total** | **~12 max, ~10 target** | | |

If you run long, cut first from sections 4 and 5 (move full query lists to the appendix) and keep the evidence sections (6, 10, 11, 12) whole, because those are the ones the rubric checks line by line.

---

## 0. Title page

- IT433 DB Administration & Management Lab, BSIT 7th semester
- **HostelHub: Hostel Room Allocation & Mess Billing System**
- Members: Eeman Gulraiz (230909), Iman Khan (230971), Zoha Saleem (230963)
- Instructor name, submission date
- Repository link: github.com/eemangulraiz7/hostel_hub

## 1. Introduction and problem

- The problem: hostel offices allocate beds in registers or spreadsheets, double-book beds, and compute mess bills by hand.
- What HostelHub does: allocate beds per term with gender and availability rules, log meals, generate monthly invoices (rent + mess), record payments, track complaints.
- Users and roles: ADMIN (everything, user management, billing) and WARDEN (allocations, meals, complaints). No student login.
- Technology: Oracle 23ai Free (core data and PL/SQL), Node.js + Express API with node-oracledb, web frontend, MongoDB (complaints), Oracle APEX (mini-demo).

## 2. Team and contributions

Table: name, roll number, contribution. Agree the final wording as a group. Suggested:

| Member | Roll no. | Contribution |
|---|---|---|
| Eeman Gulraiz (lead) | 230909 | Schema and constraints, PL/SQL (functions, procedures, triggers, cursor), retry-safe allocation, backend API |
| Iman Khan | 230971 | Frontend screens, MongoDB complaints module (shell CRUD + web feature), analytical reports and dashboard chart |
| Zoha Saleem | 230963 | Oracle APEX report, indexes and query plans, Data Pump backup/restore, HA/RAC design, test cases, report editing |

## 3. Database design

- ERD figure (from the M1 doc), full width.
- One line per table (12 tables): purpose and key relationships. Point to the data dictionary in the appendix for every column.
- **3NF justification:** rent depends on ROOM_TYPES not on the room; meal rate on MEAL_TYPES; the hostel layout is one self-referencing HOSTEL_UNITS table. Documented exception: INVOICES stores a snapshot of rent and mess amounts so a later rate change never rewrites an old bill.
- **Constraints:** named PK, FK, UNIQUE, NOT NULL, CHECK (give 4 or 5 examples), plus the function-based unique indexes that allow only one ACTIVE allocation per student and per bed per term.
- Rejected records: refer to tests T01b (duplicate) and T01c (invalid FK) in section 12.

## 4. SQL, views and recursive query

- The 3 views, one sentence each; `v_bed_occupancy` is the 6-table report (show 5 rows of output).
- The 5 business queries (Q1 to Q5): the question each answers and the technique (join, subquery, GROUP BY/HAVING). One short code sample.
- Recursive query: the BLOCK > FLOOR > ROOM tree with `CONNECT BY` (R1) or recursive `WITH` (R2). Show the output and explain how the indentation/level shows the hierarchy.

## 5. PL/SQL

Table: component, name, what it does, evidence (test ID).

- Functions: `fn_occupancy_pct` (calculation) + `fn_occupancy_band` (classification); `fn_outstanding_balance` (input validation, NO_DATA_FOUND).
- Procedures: `pr_allocate_bed` (multi-table transaction, OUT parameters), `pr_generate_invoice` (IN/OUT, returns totals).
- Triggers: `trg_alloc_validate` (BEFORE, validation), `trg_payment_audit` (AFTER, audit; compound trigger). Tests T02a to T02e.
- Cursor, nested block, exceptions: `09_billing_run.sql` (parameterized cursor, nested block per student, NO_DATA_FOUND and a custom business error, RAISE_APPLICATION_ERROR codes).
- Custom error code table (from README), shortened.

## 6. Retry-safe transaction and audit trail

- The flow: browser makes one `client_request_id` (UUID) per form submission, the API passes it to `pr_allocate_bed`, Oracle enforces `UNIQUE (client_request_id)`.
- The four required cases in a table (new, identical retry, conflicting retry, failure) with the result of each: CREATED, REPLAYED, ORA-20010, full ROLLBACK.
- Race protection: `SELECT ... FOR UPDATE` on the bed and a second request-ID check after the lock.
- Audit: `ALLOCATE_SUCCESS` only on commit; `ALLOCATE_FAILED` kept through an autonomous transaction.
- Evidence: T09 to T11 database output + the browser/API screenshot (T09-web).

## 7. Analytical reports

Four short subsections, each with the business question, the window function, and 5 or 6 rows of output:
A1 running total of daily mess revenue (restarts each month), A2 7-day moving average of meals served, A3 RANK / DENSE_RANK of rooms by occupancy inside each block, A4 LAG/LEAD change in each student's mess bill from last month. Add the dashboard chart screenshot to show a report on the website.

## 8. Web application and MongoDB

- Architecture figure: browser, API, Oracle, MongoDB (can reuse the left part of the HA diagram).
- The 5+ screens with one screenshot each: login, dashboard, student search/list, add/edit form, Allocate Bed (success and error message), complaints.
- Security: bcrypt password hashes, two roles enforced in the API, parameterized SQL (bind variables), server-side validation, credentials only in the backend `.env` (`.env.example` in the ZIP), the frontend never connects to a database.
- MongoDB: why complaints fit a document model (free text, optional photos/tags, status history); the collection with 20+ documents; mongosh CRUD before/after screenshots (insertMany, find, updateOne, deleteOne); the web feature that creates and lists complaints through the API.

## 9. Oracle APEX mini-demo

One paragraph and two screenshots: the Interactive Report on `v_vacant_beds`, grouped by block, and the filtered view. State that APEX is a supporting demo and the custom website is the main application.

## 10. Optimization

- The two indexes and the reason for each (copy the header of `13_indexes_and_plans.sql`).
- Before/after table:

| Index | Before | After |
|---|---|---|
| IX1 `meal_log(meal_date, meal_type_id)` | INDEX FAST FULL SCAN on UQ_MEAL_ONCE, cost 10, 31 buffers | INDEX RANGE SCAN on IX_MEAL_DATE_TYPE, cost 4, 10 buffers |
| IX2 `students(UPPER(full_name))` | TABLE ACCESS FULL, cost 3, 7 buffers | INDEX RANGE SCAN on IX_STUDENTS_UPPER_NAME, cost 2, 3 buffers |

- Screenshot of one before and one after DBMS_XPLAN output.
- Observation: gains are small because the tables are small (30 students, 4,200 meals); MEAL_LOG grows by about 90 rows a day, so IX1 matters more each month. IX2 helps prefix searches only. The website's Students screen matches anywhere in the name (`LIKE '%ALI%'`), which still does a full scan (shown by the last plan in the script), so say so honestly: IX2 is demonstrated as a SQL plan comparison, and switching the screen to prefix search would let it use the index.

## 11. Administration

- **Transactions:** the SAVEPOINT story from `12_transaction_control.sql` (mistaken UPDATE undone with ROLLBACK TO SAVEPOINT, correct change committed). One screenshot.
- **Backup and restore:** the five-step Data Pump exercise, with the before / after-loss / after-restore counts table and screenshots. One paragraph on why ROLLBACK is not a backup (table in `backup_restore.md`), and the `REPLACE` vs `TRUNCATE` trigger finding.
- **HA/RAC:** the one-page diagram (landscape page) plus the short explanation and RPO/RTO table from `ha_rac_design.md`.

## 12. Testing

The T01 to T13 table from `docs/test_cases.md` (Test ID, Input, Expected, Actual, Pass/Fail). Shorten long error messages to the ORA code and constraint name so the table fits.

## 13. Conclusion and limitations

- What works end to end.
- Limitations: no student self-service portal, no payment gateway (not required), HA is a design only, local deployment only.
- Possible future work: student portal, SMS reminders for unpaid invoices, room-change requests.

## Appendix (does not count toward the page limit if your instructor agrees; otherwise keep it in the ZIP only)

- A. Data dictionary (`docs/data_dictionary.md`)
- B. Full test output (`run_all.log` tail)
- C. How to run the project (README steps)

---

## Submission ZIP: `IT433_HostelHub.zip`

```
IT433_HostelHub/
  report/       IT433_HostelHub_Report.pdf
  README.md     how to set up and run everything
  database/     00 to 16 .sql scripts
  backend/      Node.js API source + .env.example (no real secrets, no node_modules)
  frontend/     web app source
  mongodb/      complaints seed (20+ documents) + mongosh CRUD script
  apex/         hostelhub_apex_export.sql + screenshots
  docs/         ERD, data dictionary, HA diagram, backup guide, test cases
  evidence/     screenshots named by test ID (T01_..., T08d_step3_..., T12a_...)
```

Before zipping: delete `node_modules`, any `.env` with real passwords, and `*.log` files except the final `run_all.log` you want to show.
