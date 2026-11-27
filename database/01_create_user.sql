/* =====================================================================
   HostelHub | 01_create_user.sql
   ---------------------------------------------------------------------
   RUN AS: SYSTEM (or another DBA account), connected to the PLUGGABLE
           database, not the root container:
             - Oracle 23ai Free : service name FREEPDB1
             - Oracle 21c XE    : service name XEPDB1
   WHAT IT DOES: creates the HOSTELHUB schema that owns every table,
                 view and PL/SQL object of the project, and gives it
                 only the privileges it needs (least privilege).
   Run this ONCE. To start completely fresh, uncomment the DROP line.
   ===================================================================== */

-- DROP USER hostelhub CASCADE;

-- Change the password before you use it anywhere real.
-- The backend will read the real password from its .env file.
CREATE USER hostelhub IDENTIFIED BY "Hostel_Hub_2026"
  DEFAULT TABLESPACE users
  QUOTA UNLIMITED ON users;

-- Only what the project needs: log in and create its own objects.
GRANT CREATE SESSION,
      CREATE TABLE,
      CREATE VIEW,
      CREATE SEQUENCE,
      CREATE PROCEDURE,
      CREATE TRIGGER
TO hostelhub;

-- Lets the schema read execution plans (DBMS_XPLAN) for the index
-- before/after comparison in milestone M4.
GRANT SELECT_CATALOG_ROLE TO hostelhub;
