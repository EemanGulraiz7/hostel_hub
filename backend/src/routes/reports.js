/**
 * routes/reports.js   ->  /api/reports
 * ---------------------------------------------------------------------
 * The 4 analytical SQL reports from database/10_analytics.sql, shown on
 * the website (Reports screen):
 *   GET /running-total?month=YYYY-MM  (i)   running total      SUM() OVER (PARTITION BY .. ORDER BY ..)
 *   GET /moving-average               (ii)  framed window      AVG() OVER (ROWS BETWEEN 6 PRECEDING ..)
 *   GET /room-ranking                 (iii) partitioned rank   RANK() / DENSE_RANK() OVER (PARTITION BY block)
 *   GET /mess-trend?month=YYYY-MM     (iv)  comparative trend  LAG() / LEAD()
 */
const express = require('express');
const db = require('../db/oracle');
const { MONTH_RE } = require('../validation');

const router = express.Router();

/** Latest month that has data, used when no month is given. */
async function latestMonth(sql) {
  const rows = await db.query(sql);
  return rows[0] ? rows[0].month : null;
}

router.get('/running-total', async (req, res) => {
  const month = MONTH_RE.test(req.query.month || '')
    ? req.query.month
    : await latestMonth(`SELECT TO_CHAR(MAX(month_start), 'YYYY-MM') AS month FROM v_mess_daily_revenue`);
  const rows = await db.query(
    `SELECT TO_CHAR(meal_date, 'YYYY-MM-DD Dy') AS day,
            meals_served, revenue,
            SUM(revenue) OVER (PARTITION BY TRUNC(meal_date, 'MM')
                               ORDER BY meal_date
                               ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS running_total
       FROM v_mess_daily_revenue
      WHERE month_start = TO_DATE(:month, 'YYYY-MM')
      ORDER BY meal_date`,
    { month }
  );
  res.json({ month, rows });
});

router.get('/moving-average', async (req, res) => {
  // The window is computed over ALL days in the inner query; the outer
  // query only keeps the last 30 days for display.
  const rows = await db.query(
    `SELECT day, meals_served, moving_avg_7d, days_in_window
       FROM (SELECT meal_date,
                    TO_CHAR(meal_date, 'YYYY-MM-DD Dy') AS day,
                    meals_served,
                    ROUND(AVG(meals_served) OVER (ORDER BY meal_date
                          ROWS BETWEEN 6 PRECEDING AND CURRENT ROW), 1) AS moving_avg_7d,
                    COUNT(*) OVER (ORDER BY meal_date
                          ROWS BETWEEN 6 PRECEDING AND CURRENT ROW)     AS days_in_window,
                    ROW_NUMBER() OVER (ORDER BY meal_date DESC)         AS days_back
               FROM v_mess_daily_revenue)
      WHERE days_back <= 30
      ORDER BY meal_date`
  );
  res.json({ rows });
});

router.get('/room-ranking', async (req, res) => {
  const rows = await db.query(
    `SELECT block_name, room_code, room_type, beds, occupied, occupancy_pct,
            RANK()       OVER (PARTITION BY block_name ORDER BY occupancy_pct DESC) AS rank_in_block,
            DENSE_RANK() OVER (PARTITION BY block_name ORDER BY occupancy_pct DESC) AS dense_rank_in_block
       FROM (SELECT block_name, room_code, room_type,
                    COUNT(*) AS beds,
                    SUM(CASE WHEN bed_status = 'OCCUPIED' THEN 1 ELSE 0 END) AS occupied,
                    ROUND(100 * SUM(CASE WHEN bed_status = 'OCCUPIED' THEN 1 ELSE 0 END) / COUNT(*), 1) AS occupancy_pct
               FROM v_bed_occupancy
              GROUP BY block_name, room_code, room_type)
      ORDER BY block_name, rank_in_block, room_code`
  );
  res.json({ rows });
});

router.get('/mess-trend', async (req, res) => {
  // Hostel-wide month-on-month change (one row per billed month)
  const monthly = await db.query(
    `SELECT TO_CHAR(billing_month, 'YYYY-MM')                    AS month,
            SUM(mess_amount)                                      AS mess_total,
            LAG(SUM(mess_amount)) OVER (ORDER BY billing_month)   AS prev_month_total,
            ROUND(100 * (SUM(mess_amount) - LAG(SUM(mess_amount)) OVER (ORDER BY billing_month))
                  / NULLIF(LAG(SUM(mess_amount)) OVER (ORDER BY billing_month), 0), 1) AS change_pct,
            LEAD(SUM(mess_amount)) OVER (ORDER BY billing_month)  AS next_month_total
       FROM invoices
      GROUP BY billing_month
      ORDER BY billing_month`
  );

  const month = MONTH_RE.test(req.query.month || '')
    ? req.query.month
    : monthly.length ? monthly[monthly.length - 1].month : null;

  // Per student: this month's mess bill vs the previous month (LAG).
  // LAG is calculated over ALL months in the inner query, then filtered.
  const students = await db.query(
    `SELECT roll_no, full_name, month, mess_amount, prev_month, change_amt, change_pct
       FROM (SELECT s.roll_no, s.full_name,
                    TO_CHAR(i.billing_month, 'YYYY-MM') AS month,
                    i.mess_amount,
                    LAG(i.mess_amount) OVER (PARTITION BY i.student_id ORDER BY i.billing_month) AS prev_month,
                    i.mess_amount - LAG(i.mess_amount) OVER (PARTITION BY i.student_id ORDER BY i.billing_month) AS change_amt,
                    ROUND(100 * (i.mess_amount - LAG(i.mess_amount) OVER (PARTITION BY i.student_id ORDER BY i.billing_month))
                          / NULLIF(LAG(i.mess_amount) OVER (PARTITION BY i.student_id ORDER BY i.billing_month), 0), 1) AS change_pct
               FROM invoices i
               JOIN students s ON s.student_id = i.student_id)
      WHERE month = :month
      ORDER BY change_amt NULLS LAST, roll_no`,
    { month }
  );
  res.json({ month, monthly, students });
});

module.exports = router;
