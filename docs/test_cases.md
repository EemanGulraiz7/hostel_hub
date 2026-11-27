# HostelHub test cases (T01 to T13)

This is the test table for the report (requirement section 5). The database tests were run on Oracle 23ai Free on 27 Nov 2026 and their **Actual** column is the real output. Rows marked **TO FILL** need the website, mongosh or APEX. For the web rows, `cd backend && npm run test:api` prints Input / Expected / Actual / PASS-FAIL for each one (T05-web, T06a-c, T07b, T09 to T11 through the API, T12a, T12b, T13), so paste its output, then add a browser screenshot for each. T07a (mongosh) and the APEX report are done by hand.

How to reproduce the database rows: run `database/00_run_all.sql` (T01 to T04, T05, T08 rollback, T09 to T11 print in `run_all.log`), then `database/13_indexes_and_plans.sql` (T08 index) and the steps in `docs/backup_restore.md` (T08 recovery).

The test data is listed at the top of `database/11_tests.sql`. Allocation IDs (28, 30) can differ on your machine if you have run extra allocations.

## Summary table (copy this into the report)

| Test ID | What it shows | Input | Expected result | Actual result | Pass/Fail |
|---|---|---|---|---|---|
| T01a | Constraint accepts valid data | INSERT student 239001, gender M, semester 1 | 1 row inserted | 1 row inserted | Pass |
| T01b | UNIQUE rejects a duplicate | INSERT student with roll_no 231001 (already used) | ORA-00001 on UQ_STUDENTS_ROLL | ORA-00001: unique constraint (HOSTELHUB.UQ_STUDENTS_ROLL) violated | Pass |
| T01c | FOREIGN KEY rejects an orphan | INSERT bed with room_unit_id 99999 | ORA-02291 on FK_BEDS_ROOM | ORA-02291: integrity constraint (HOSTELHUB.FK_BEDS_ROOM) violated, parent key not found | Pass |
| T01d | CHECK rejects bad value | INSERT student with semester 9 | ORA-02290 on CK_STUDENTS_SEMESTER | ORA-02290: check constraint (HOSTELHUB.CK_STUDENTS_SEMESTER) violated | Pass |
| T01e | NOT NULL rejects missing value | INSERT student with full_name NULL | ORA-01400 | ORA-01400: cannot insert NULL into STUDENTS.FULL_NAME | Pass |
| T02a | BEFORE trigger accepts | Allocation: boy 231014 to boys' bed A202-B, current term | 1 row inserted | 1 row inserted (then rolled back) | Pass |
| T02b | BEFORE trigger rejects wrong gender | Allocation: girl 231028 to boys' bed A203-C | ORA-20004 | ORA-20004: Student gender (F) does not match block A policy (M) | Pass |
| T02c | BEFORE trigger rejects ended term | Allocation for term Spring 2026 | ORA-20005 | ORA-20005: Term has already ended on 30-JUN-2026 | Pass |
| T02d | AFTER audit trigger | Payment 1,000 on UNPAID invoice 49 (total 25,180) | +1 audit row; invoice UNPAID to PARTIAL | +1 audit row; invoice UNPAID to PARTIAL | Pass |
| T02e | AFTER trigger rejects over-payment | Payment of total + 500 on invoice 49 | ORA-20024; no payment, no audit row | ORA-20024: Payments (25680) would exceed invoice 49 total (25180); nothing kept | Pass |
| T03 | Multi-table procedure succeeds | `pr_allocate_bed('TEST-T03', 231015, A203-B, Fall 2026, admin)` | CREATED; +1 allocation; bed OCCUPIED; 1 success audit row | CREATED id 28; +1 allocation; bed OCCUPIED; 1 success audit row | Pass |
| T04a | Failed procedure leaves no partial change | `pr_allocate_bed('TEST-T04', 231016, A204-D)` (bed under MAINTENANCE) | ORA-20002; no allocation; bed still MAINTENANCE; no success audit | ORA-20002: Bed 30 is not available; allocations +0; bed MAINTENANCE; success audit 0 | Pass |
| T04b | Trigger error inside the procedure rolls back everything | `pr_allocate_bed('TEST-T04B', 231028, A203-C)` | ORA-20004; no allocation; bed AVAILABLE; failure logged only | ORA-20004; allocations +0; bed AVAILABLE; 1 ALLOCATE_FAILED row, no success row | Pass |
| T05 | Analytical reports | `10_analytics.sql` A1 running total, A2 7-day moving average, A3 RANK per block, A4 LAG/LEAD month trend | Each report returns rows; A1 total restarts each month | All four ran without error; output in run_all.log (section 10) | Pass |
| T05-web | Analytical report on the website | Open Dashboard, mess revenue chart (`v_mess_daily_revenue`) | Daily revenue and running total for the month are shown | TO FILL | TO FILL |
| T06a | Browser CRUD: add | Students screen, add a student with valid data | "Student added" message; row in STUDENTS | TO FILL | TO FILL |
| T06b | Browser CRUD: edit and delete | Edit the student's phone, then delete the student | Success messages; change visible in the list | TO FILL | TO FILL |
| T06c | Business transaction from the browser | Allocate Bed screen: free student + vacant bed | "Bed allocated" message; bed leaves the vacant list | TO FILL | TO FILL |
| T07a | MongoDB CRUD in mongosh | `insertMany` (20+ complaints), `find`, `updateOne` (status to RESOLVED), `deleteOne` | Counts and documents change as expected (before/after screenshots) | TO FILL | TO FILL |
| T07b | MongoDB from the website | Complaints screen: submit a complaint, then see it in the list | Complaint saved through the API and listed | TO FILL | TO FILL |
| T08a | Index and query plan | `13_indexes_and_plans.sql`: IX1 meals per type on 20-Nov-2026 | Plan changes from full scan to INDEX RANGE SCAN; cost and buffers drop | INDEX FAST FULL SCAN on UQ_MEAL_ONCE (cost 10, 31 buffers) became INDEX RANGE SCAN on IX_MEAL_DATE_TYPE (cost 4, 10 buffers) | Pass |
| T08b | Function-based index | IX2 search `UPPER(full_name) LIKE 'AYESHA%'` | TABLE ACCESS FULL becomes INDEX RANGE SCAN | TABLE ACCESS FULL (cost 3, 7 buffers) became INDEX RANGE SCAN on IX_STUDENTS_UPPER_NAME (cost 2, 3 buffers) | Pass |
| T08c | COMMIT / SAVEPOINT / ROLLBACK | `12_transaction_control.sql`: wrong UPDATE after a savepoint | ROLLBACK TO SAVEPOINT undoes only the mistake; COMMIT keeps step 1 | Step 2 undone, step 1 committed; full ROLLBACK restored deleted meals | Pass |
| T08d | Logical backup and restore | `expdp` schema, then delete all payments + COMMIT, then `impdp tables=PAYMENTS table_exists_action=REPLACE` | 42 payments and 842,610.00 received restored; all counts equal the pre-loss check | Before: 42 / 842,610.00. After loss: 0. After import: 42 / 842,610.00, all 12 table counts identical, 0 invalid objects | Pass |
| T09 | New request (retry-safe) | `pr_allocate_bed('TEST-T09', 231014, A202-B)` | CREATED; exactly one allocation and one success audit | CREATED id 30; +1 allocation; success audit 1 | Pass |
| T10 | Identical retry | Same request ID, same student, bed and term | REPLAYED; same id; nothing new | REPLAYED id 30; allocations +0; audit +0 | Pass |
| T11 | Conflicting retry | Same request ID, bed A203-C instead | ORA-20010; original untouched | ORA-20010; original stays on A202-B; A203-C still AVAILABLE | Pass |
| T09-web | Retry from the browser / API | Submit Allocate Bed, then resend the same request (double click, or repeat the API call with the same `client_request_id`) | First: "allocated"; repeat: saved result returned, no second allocation | TO FILL | TO FILL |
| T11-web | Conflicting retry through the API | Repeat the API call with the same `client_request_id` but another bed | Clear business error shown (from ORA-20010) | TO FILL | TO FILL |
| T12a | Login and role access | Log in as `warden.ali`, open an admin-only page or API (for example user management) | Access denied (403) | TO FILL | TO FILL |
| T12b | Wrong password | Log in as `admin` with a wrong password | "Invalid username or password", no session | TO FILL | TO FILL |
| T13 | Invalid input rejected by the backend | Add student with an invalid email or semester 9 (bypass the browser check, for example with Postman) | Server-side validation error; nothing inserted | TO FILL | TO FILL |

## Extra function tests (from `11_tests.sql`, optional in the report)

| Test ID | Input | Expected | Actual | Pass/Fail |
|---|---|---|---|---|
| F1 | `fn_occupancy_pct(block A)` | 75 (15 of 20 beds) | 75, band HIGH | Pass |
| F2 | `fn_outstanding_balance(231023)` | 48,250 (same as v_student_dues) | 48,250 | Pass |
| F3 | `fn_outstanding_balance(-1)` | ORA-20032 (NO_DATA_FOUND handled) | ORA-20032: Student -1 does not exist | Pass |

## Evidence checklist (screenshots for the report)

- [ ] `run_all.log` tail showing `PASSED: 19 FAILED: 0`
- [ ] T08a / T08b before and after plans (text is in `docs/evidence/13_indexes_and_plans_output.txt`; a screenshot from SQL Developer is better in the report)
- [ ] T08d five backup screenshots (steps 1 to 5 in `docs/backup_restore.md`)
- [ ] Website: login, dashboard with chart, student list with search, add/edit form, Allocate Bed success and error, complaints page
- [ ] T09-web: the browser's network tab or the API response showing `REPLAYED`
- [ ] mongosh before/after for insertMany, find, updateOne, deleteOne
- [ ] APEX Vacant Beds report (see `docs/apex_report.md`)
