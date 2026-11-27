# Logical backup and restore with Oracle Data Pump

Requirement (Administration): *show a logical backup/data restoration method. ROLLBACK is not a substitute for backup.*

HostelHub uses **Oracle Data Pump** (`expdp` / `impdp`), Oracle's standard tool for logical backups. A logical backup saves the schema's objects (tables, constraints, indexes, views, PL/SQL, triggers) and its rows into a dump file. It can bring back one table or the whole schema, even after the bad change was committed, which ROLLBACK cannot do.

The exercise below was run on Oracle 23ai Free and every step worked. The outputs from that run are in [`docs/evidence/`](evidence/) (files starting with `backup_`), so you know what your screen should show.

## How ROLLBACK and backup differ

| | ROLLBACK (`12_transaction_control.sql`) | Data Pump backup (this exercise) |
|---|---|---|
| Undoes | uncommitted changes in your own session | any loss, committed or not, from any session |
| Lifetime | until COMMIT or the session ends | as long as the dump file is kept |
| Protects against | a mistake you notice before COMMIT | committed mistakes, dropped tables, a broken or lost database |
| Granularity | the whole transaction, or back to a SAVEPOINT | one table, several tables, or the full schema |

## Files

| File | Run as | Purpose |
|---|---|---|
| `database/14_backup_setup.sql` | SYSTEM, once | creates the `HH_BACKUP_DIR` directory object and grants it to HOSTELHUB |
| `database/15_backup_check.sql` | HOSTELHUB | row counts and money totals, run before and after so you can compare |
| `database/16_simulate_data_loss.sql` | HOSTELHUB | the "accident": deletes every payment and COMMITs |

## Step 0: one-time setup

1. Create a folder on the machine where Oracle runs:
   - **Windows (native install):** `mkdir C:\hostelhub_backup`
   - **Oracle in Docker:** `docker exec -u oracle <container> mkdir -p /opt/oracle/backup`
2. Open `database/14_backup_setup.sql` in SQL Developer **as SYSTEM** (on FREEPDB1 / XEPDB1). If you use Docker, swap the two `DEFINE backup_path` lines as the comment says. Press **F5**.
3. Make sure it prints `HH_BACKUP_DIR` with your folder path.

## Step 1: check the good state

As **HOSTELHUB**, run `database/15_backup_check.sql` (F5). **Screenshot 1.** Expected with the seed data (plus any web activity you did): 42 payments, total received 842,610.00, 0 invalid objects.

## Step 2: take the backup (export)

Open a terminal (Command Prompt on Windows) and run:

```bash
expdp hostelhub/Hostel_Hub_2026@localhost:1521/FREEPDB1 schemas=HOSTELHUB directory=HH_BACKUP_DIR dumpfile=hostelhub_backup.dmp logfile=hostelhub_export.log reuse_dumpfiles=YES
```

On Docker, put `docker exec -it <container>` in front of the same command.

It should end with `Job "HOSTELHUB"."SYS_EXPORT_SCHEMA_01" successfully completed` and list every table with its row count (for example `exported "HOSTELHUB"."PAYMENTS" ... 42 rows`). **Screenshot 2.** The dump file `hostelhub_backup.dmp` is now in the backup folder.

> `expdp` is in the Oracle `bin` folder. If Windows says it is not recognized, run it from that folder (for example `C:\app\<you>\product\23ai\dbhomeFree\bin`) or add the folder to PATH.

## Step 3: the accident

As **HOSTELHUB**, run `database/16_simulate_data_loss.sql`. It deletes all 42 payments and **commits**, then shows that `ROLLBACK` brings nothing back: payments stay at 0 and every student now looks unpaid (total outstanding rises to the full billed amount, 1,521,940.00). **Screenshot 3.**

## Step 4: restore the lost table (import)

```bash
impdp hostelhub/Hostel_Hub_2026@localhost:1521/FREEPDB1 directory=HH_BACKUP_DIR dumpfile=hostelhub_backup.dmp logfile=hostelhub_import_payments.log tables=PAYMENTS table_exists_action=REPLACE
```

Expected: `imported "HOSTELHUB"."PAYMENTS" ... 42 rows` and `successfully completed`. **Screenshot 4.**

**Why `REPLACE` and not `TRUNCATE` or `APPEND`:** PAYMENTS has an AFTER INSERT audit trigger (`trg_payment_audit`). With `TRUNCATE` or `APPEND`, Data Pump loads the rows into the existing table and the trigger fires for every row. When we tested this it wrote 42 fake `PAYMENT_RECEIVED` rows into AUDIT_LOG (71 rows became 113). `REPLACE` drops the table, recreates it from the dump, loads the rows, and only then recreates its indexes, constraints and trigger, so no trigger fires during the load. The identity column also carries on from the backed-up value (the next payment gets ID 43).

## Step 5: prove the restore

Run `database/15_backup_check.sql` again. **Screenshot 5.** Every row count and money total must equal Screenshot 1 (only the "Checked at" time changes). The script first recompiles invalid objects, because replacing PAYMENTS marks `fn_outstanding_balance`, which reads it, as INVALID until it is recompiled.

## Optional: restore the whole schema into a new user

This shows the backup can rebuild the full database, not just one table. It does not touch HOSTELHUB. As **SYSTEM** in SQL Developer:

```sql
CREATE USER hostelhub_restore IDENTIFIED BY "Restore_2026"
  DEFAULT TABLESPACE users QUOTA UNLIMITED ON users;
GRANT CREATE SESSION, CREATE TABLE, CREATE VIEW, CREATE SEQUENCE,
      CREATE PROCEDURE, CREATE TRIGGER TO hostelhub_restore;
```

Then in the terminal:

```bash
impdp system/<system_password>@localhost:1521/FREEPDB1 directory=HH_BACKUP_DIR dumpfile=hostelhub_backup.dmp logfile=hostelhub_import_full.log schemas=HOSTELHUB remap_schema=HOSTELHUB:HOSTELHUB_RESTORE
```

Check it in SQL Developer as SYSTEM:

```sql
SELECT COUNT(*) FROM hostelhub_restore.payments;   -- 42
SELECT COUNT(*) FROM hostelhub_restore.meal_log;   -- 4213
SELECT COUNT(*) FROM dba_objects WHERE owner = 'HOSTELHUB_RESTORE';  -- same as for HOSTELHUB
```

The user must be created first because HOSTELHUB exported only its own schema and has no right to create users. Clean up afterwards with `DROP USER hostelhub_restore CASCADE;`.

## Backup policy for a real hostel (for the report)

| Item | Choice |
|---|---|
| Logical backup | `expdp` of the HOSTELHUB schema every night at 02:00 (Windows Task Scheduler or cron), dump name with the date, keep 14 days |
| Off-site copy | copy each night's dump to a second machine or cloud storage |
| Physical backup | in production, RMAN full backup weekly plus daily incrementals and archived redo logs (point-in-time recovery). Data Pump complements RMAN and does not replace it |
| Restore test | restore into `HOSTELHUB_RESTORE` once a month to prove the dumps work |
| RPO / RTO | see `docs/ha_rac_design.md`: Data Guard covers server loss; Data Pump covers user mistakes such as this one |
