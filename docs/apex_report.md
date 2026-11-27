# Oracle APEX mini-demo: Vacant Beds report

Requirement: *one small APEX report or form connected to an Oracle table; include a screenshot or export as APEX lab evidence. APEX supports the lab topic but does not replace the custom web application.*

**What we build:** an Interactive Report on the view `v_vacant_beds` (from `database/07_views.sql`), which lists every bed a warden can allocate right now, with its block, floor, room, room type and monthly rent. Interactive Reports come with search, filters, sorting and CSV download built in, so the demo needs no code.

Owner: Zoha Saleem (230963). Time needed: about 30 minutes.

## Where to run APEX

Oracle 23ai Free and 21c XE do **not** come with APEX installed. Pick one option:

| Option | When to use it | Effort |
|---|---|---|
| **A. Free workspace on apex.oracle.com** (recommended) | Easiest. Oracle hosts APEX and gives you a schema. | 10 min sign-up, approval email usually within minutes |
| B. Install APEX + ORDS on your own 23ai Free | Only if the lab instructor wants APEX on the same database as the project | 1 to 2 hours |

The steps below use Option A. In Option B, the steps from "Step 3" onwards are the same.

## Step 1: get a workspace (Option A)

1. Go to <https://apex.oracle.com> and choose **Get started for free** then **Request a free workspace**.
2. Workspace name: `HOSTELHUB_IT433` (anything unique works). Schema name: `HOSTELHUB`.
3. Open the approval email, set your password and sign in.

## Step 2: load the HostelHub tables, data and views

The APEX schema is a separate database, so load the project objects into it once.

1. **SQL Workshop > SQL Scripts > Upload**. Upload these files from `database/`, in this order: `02_schema.sql`, `03_functions.sql`, `04_procedures.sql`, `05_triggers.sql`, `06_seed_data.sql`, `07_views.sql`.
2. Click **Run** on each one, in the same order (02 first). APEX ignores the SQL*Plus lines such as `SET` and `PROMPT` and shows them as skipped; that is fine.
3. Check the result in **SQL Workshop > SQL Commands**:
   ```sql
   SELECT COUNT(*) FROM v_vacant_beds;
   ```
   It should return the number of vacant beds (14 with fresh seed data before any test or web allocations).

## Step 3: create the app and the report

1. **App Builder > Create > New Application**. Name: `HostelHub APEX Demo`.
2. Click **Add Page > Interactive Report**.
   - Page name: `Vacant Beds`
   - Data source: **Table / View**, choose `V_VACANT_BEDS`
3. Leave authentication as the default (APEX accounts) and click **Create Application**.
4. Click **Run Application** and sign in with your workspace user.

## Step 4: make the report useful

On the running report:

1. **Actions > Columns:** show `BED_CODE`, `BLOCK_NAME`, `GENDER_POLICY`, `FLOOR_CODE`, `ROOM_TYPE`, `MONTHLY_RENT`; hide `BED_ID`.
2. **Actions > Format > Control Break** on `BLOCK_NAME`, so beds are grouped per block.
3. **Actions > Data > Aggregate:** `Count` on `BED_CODE` (vacant beds per block) and `Average` on `MONTHLY_RENT`.
4. **Actions > Report > Save Report** as the Primary (default) report so the layout stays.
5. Optional, in Page Designer: change column headings (`BED_CODE` to "Bed", `MONTHLY_RENT` to "Rent (PKR)") and set the rent format mask to `999G999`.

## Step 5: evidence for the report

1. **Screenshot A:** the Vacant Beds report grouped by block, with the counts visible.
2. **Screenshot B:** the same report with a filter applied (for example `GENDER_POLICY = F` through the search bar or **Actions > Filter**), showing that APEX queries the live Oracle view.
3. **Screenshot C (link to the main app):** allocate one of the listed beds in the HostelHub website (or run `pr_allocate_bed` in SQL Commands), refresh the APEX report and show that the bed is gone. Only possible if the website and APEX use the same database (Option B); with Option A, run `pr_allocate_bed` in SQL Commands instead.
4. **Export:** App Builder > your app > **Export / Import > Export**, keep the defaults and download `f<app_id>.sql`. Save it in the repository as `apex/hostelhub_apex_export.sql`.

Put Screenshots A and B (and C if you have it) in the report under "Oracle APEX", with one sentence saying the main application is the custom website and APEX is a supporting mini-demo.
