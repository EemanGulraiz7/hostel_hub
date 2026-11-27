/* =====================================================================
   HostelHub | 10_analytics.sql
   ---------------------------------------------------------------------
   RUN AS: HOSTELHUB, after 09_billing_run.sql (A4 needs 3 months of
   invoices).
   Requirement: 4 analytical reports using window functions
     A1  running total                -> SUM() OVER (PARTITION BY .. ORDER BY ..)
     A2  moving / framed window       -> AVG() OVER (ORDER BY .. ROWS BETWEEN 6 PRECEDING AND CURRENT ROW)
     A3  partitioned ranking          -> RANK() / DENSE_RANK() OVER (PARTITION BY .. ORDER BY ..)
     A4  LAG / LEAD comparative trend -> LAG() / LEAD() OVER (PARTITION BY .. ORDER BY ..)
   A window function calculates across a set of rows RELATED to the
   current row but, unlike GROUP BY, keeps every row in the output.
   ===================================================================== */

SET LINESIZE 200
SET PAGESIZE 200
COLUMN full_name  FORMAT A18
COLUMN block_name FORMAT A28
COLUMN room_code  FORMAT A6

/* ---------------------------------------------------------------------
   View for the website dashboard: daily mess revenue with a running
   total that restarts every month. The backend reads this view to draw
   the "mess revenue this month" chart.
   --------------------------------------------------------------------- */
CREATE OR REPLACE VIEW v_mess_daily_revenue AS
SELECT d.meal_date,
       TRUNC(d.meal_date, 'MM')  AS month_start,
       d.meals_served,
       d.revenue,
       SUM(d.revenue) OVER (PARTITION BY TRUNC(d.meal_date, 'MM')
                            ORDER BY d.meal_date
                            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS month_running_total
  FROM (SELECT ml.meal_date,
               COUNT(*)     AS meals_served,
               SUM(mt.rate) AS revenue
          FROM meal_log ml
          JOIN meal_types mt ON mt.meal_type_id = ml.meal_type_id
         GROUP BY ml.meal_date) d;

/* ---------------------------------------------------------------------
   A1  RUNNING TOTAL
   "How is mess revenue building up day by day in November 2026?"
   PARTITION BY month makes the total restart on the 1st; ORDER BY date
   with the default frame adds each day to all days before it.
   --------------------------------------------------------------------- */
SELECT TO_CHAR(meal_date, 'DD-MON-YY DY') AS day,
       meals_served,
       revenue,
       month_running_total
  FROM v_mess_daily_revenue
 WHERE month_start = DATE '2026-11-01'
 ORDER BY meal_date;

/* ---------------------------------------------------------------------
   A2  MOVING (FRAMED) WINDOW
   "What is the 7-day moving average of meals served?" It smooths the
   weekend dip so the kitchen can plan food quantities.
   ROWS BETWEEN 6 PRECEDING AND CURRENT ROW = today + the 6 days before.
   The first 6 rows of September average fewer days (window not full yet),
   shown by days_in_window.
   --------------------------------------------------------------------- */
-- The window is calculated in the inner query over ALL days; the outer
-- WHERE only chooses which rows to show. (Filtering in the same query
-- would remove rows BEFORE the window is calculated and give wrong
-- averages.)
SELECT day, meals_served, moving_avg_7d, days_in_window, diff_from_avg
  FROM (SELECT meal_date,
               TO_CHAR(meal_date, 'DD-MON-YY DY') AS day,
               meals_served,
               ROUND(AVG(meals_served) OVER (ORDER BY meal_date
                                             ROWS BETWEEN 6 PRECEDING AND CURRENT ROW), 1) AS moving_avg_7d,
               COUNT(*) OVER (ORDER BY meal_date
                              ROWS BETWEEN 6 PRECEDING AND CURRENT ROW)                    AS days_in_window,
               ROUND(meals_served - AVG(meals_served) OVER (ORDER BY meal_date
                                             ROWS BETWEEN 6 PRECEDING AND CURRENT ROW), 1) AS diff_from_avg
          FROM v_mess_daily_revenue)
 WHERE meal_date < DATE '2026-09-10'          -- the start, while the window fills up
    OR meal_date >= DATE '2026-11-01'         -- and the latest month
 ORDER BY meal_date;

/* ---------------------------------------------------------------------
   A3  PARTITIONED RANKING
   (a) "Rank the rooms by occupancy inside each block."
       PARTITION BY block restarts the ranking for each block.
       RANK leaves gaps after ties (1,1,1,4); DENSE_RANK does not (1,1,1,2).
   --------------------------------------------------------------------- */
SELECT block_name,
       room_code,
       room_type,
       beds,
       occupied,
       occupancy_pct,
       RANK()       OVER (PARTITION BY block_name ORDER BY occupancy_pct DESC) AS rank_in_block,
       DENSE_RANK() OVER (PARTITION BY block_name ORDER BY occupancy_pct DESC) AS dense_rank_in_block
  FROM (SELECT block_name, room_code, room_type,
               COUNT(*) AS beds,
               SUM(CASE WHEN bed_status = 'OCCUPIED' THEN 1 ELSE 0 END) AS occupied,
               ROUND(100 * SUM(CASE WHEN bed_status = 'OCCUPIED' THEN 1 ELSE 0 END) / COUNT(*), 1) AS occupancy_pct
          FROM v_bed_occupancy
         GROUP BY block_name, room_code, room_type)
 ORDER BY block_name, rank_in_block, room_code;

/*  (b) "Who are the top 3 mess spenders of November in each block?"
        Ranking inside a sub-query, then filtering on the rank.          */
SELECT *
  FROM (SELECT v.block_name,
               s.roll_no,
               s.full_name,
               i.mess_amount,
               RANK() OVER (PARTITION BY v.block_name ORDER BY i.mess_amount DESC) AS spend_rank
          FROM invoices i
          JOIN students s        ON s.student_id = i.student_id
          JOIN v_bed_occupancy v ON v.student_id = i.student_id
         WHERE i.billing_month = DATE '2026-11-01')
 WHERE spend_rank <= 3
 ORDER BY block_name, spend_rank;

/* ---------------------------------------------------------------------
   A4  LAG / LEAD: COMPARATIVE TREND
   "How did each student's mess bill change from last month?"
   LAG  looks one row BACK  in the student's own months (previous month)
   LEAD looks one row AHEAD (next month; NULL for the latest month)
   NULLIF avoids division by zero when last month's bill was 0.
   Note: November covers meals up to 26 Nov only, so most bills drop.
   --------------------------------------------------------------------- */
SELECT s.roll_no,
       s.full_name,
       TO_CHAR(i.billing_month, 'MON-YY')                                         AS month,
       i.mess_amount,
       LAG(i.mess_amount)  OVER (PARTITION BY i.student_id ORDER BY i.billing_month) AS prev_month,
       i.mess_amount
         - LAG(i.mess_amount) OVER (PARTITION BY i.student_id ORDER BY i.billing_month) AS change_amt,
       ROUND(100 * (i.mess_amount
                    - LAG(i.mess_amount) OVER (PARTITION BY i.student_id ORDER BY i.billing_month))
             / NULLIF(LAG(i.mess_amount) OVER (PARTITION BY i.student_id ORDER BY i.billing_month), 0), 1)
                                                                                 AS change_pct,
       LEAD(i.mess_amount) OVER (PARTITION BY i.student_id ORDER BY i.billing_month) AS next_month
  FROM invoices i
  JOIN students s ON s.student_id = i.student_id
 ORDER BY s.roll_no, i.billing_month;

/*  Hostel-wide version (one row per month), handy for a dashboard card */
SELECT TO_CHAR(billing_month, 'MON-YY')                         AS month,
       SUM(mess_amount)                                          AS mess_total,
       LAG(SUM(mess_amount)) OVER (ORDER BY billing_month)       AS prev_month_total,
       ROUND(100 * (SUM(mess_amount) - LAG(SUM(mess_amount)) OVER (ORDER BY billing_month))
             / NULLIF(LAG(SUM(mess_amount)) OVER (ORDER BY billing_month), 0), 1) AS change_pct
  FROM invoices
 GROUP BY billing_month
 ORDER BY billing_month;
