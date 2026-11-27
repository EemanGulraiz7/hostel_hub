/* =====================================================================
   HostelHub | 14_backup_setup.sql
   ---------------------------------------------------------------------
   RUN AS: SYSTEM, connected to the pluggable database (FREEPDB1 or
           XEPDB1), ONCE, before the first backup.
   WHAT IT DOES: Data Pump (expdp / impdp) writes its dump and log files
   only into an Oracle DIRECTORY object: a name inside the database that
   points to a real folder on the database server. This script creates
   that directory object and lets HOSTELHUB read and write it.

   BEFORE RUNNING: create the folder on the machine where Oracle runs,
   then set backup_path below to it.
     Windows (native install) : mkdir C:\hostelhub_backup
     Oracle in Docker          : docker exec -u oracle <container> mkdir -p /opt/oracle/backup
   Full step-by-step guide: docs/backup_restore.md
   ===================================================================== */

SET DEFINE ON
-- Windows native install:
DEFINE backup_path = 'C:\hostelhub_backup'
-- Oracle in Docker (gvenzl/oracle-free): comment the line above and use
-- DEFINE backup_path = '/opt/oracle/backup'

CREATE OR REPLACE DIRECTORY hh_backup_dir AS '&backup_path';

-- HOSTELHUB exports and imports ITS OWN schema, so it needs only
-- READ/WRITE on the folder (plus CREATE TABLE, which it already has,
-- for the Data Pump job's master table). No DBA role is given.
GRANT READ, WRITE ON DIRECTORY hh_backup_dir TO hostelhub;

COLUMN directory_name FORMAT A16
COLUMN directory_path FORMAT A40
SELECT directory_name, directory_path FROM all_directories WHERE directory_name = 'HH_BACKUP_DIR';

PROMPT 14_backup_setup.sql finished: directory HH_BACKUP_DIR is ready.
