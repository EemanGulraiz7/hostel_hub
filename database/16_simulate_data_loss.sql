/* =====================================================================
   HostelHub | 16_simulate_data_loss.sql
   ---------------------------------------------------------------------
   RUN AS: HOSTELHUB, ONLY during the backup exercise, AFTER the expdp
   export (docs/backup_restore.md step 2).
   Story: a staff member "cleans up" the PAYMENTS table by mistake and
   COMMITs. Once committed, ROLLBACK cannot bring the rows back: this is
   exactly why a separate backup is needed (ROLLBACK is not a backup).
   ===================================================================== */

SET FEEDBACK ON

PROMPT ===== Payments before the mistake =====
SELECT COUNT(*) AS payments, SUM(amount) AS total_received FROM payments;

PROMPT ===== The mistake: every payment deleted, then COMMIT =====
DELETE FROM payments;
COMMIT;

PROMPT ===== ROLLBACK now does nothing: the delete is already committed =====
ROLLBACK;
SELECT COUNT(*) AS payments, SUM(amount) AS total_received FROM payments;

PROMPT ===== Effect on the business: every student now looks unpaid =====
SELECT SUM(total_paid) AS total_paid, SUM(outstanding) AS total_outstanding FROM v_student_dues;

PROMPT Data lost. Now restore PAYMENTS from the dump file with impdp (step 4 of docs/backup_restore.md).
