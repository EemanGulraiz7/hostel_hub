/**
 * routes/dashboard.js   ->  /api/dashboard
 * ---------------------------------------------------------------------
 *   GET /           KPI cards, block occupancy (PL/SQL functions),
 *                   open complaints (MongoDB), recent activity
 *   GET /revenue    daily mess revenue + running total for the chart
 *                   (view v_mess_daily_revenue, analytic SUM() OVER)
 */
const express = require('express');
const db = require('../db/oracle');
const mongo = require('../db/mongo');
const { MONTH_RE } = require('../validation');

const router = express.Router();

router.get('/', async (req, res) => {
  // Bed counts by status in one pass (conditional aggregation)
  const [beds] = await db.query(
    `SELECT COUNT(*)                                              AS total_beds,
            COUNT(CASE WHEN status = 'OCCUPIED'    THEN 1 END)    AS occupied,
            COUNT(CASE WHEN status = 'AVAILABLE'   THEN 1 END)    AS available,
            COUNT(CASE WHEN status = 'MAINTENANCE' THEN 1 END)    AS maintenance
       FROM beds`
  );

  // Occupancy per block using our two PL/SQL functions:
  //   fn_occupancy_pct  (calculation, walks the hierarchy with CONNECT BY)
  //   fn_occupancy_band (classification: LOW / MEDIUM / HIGH / FULL)
  const blocks = await db.query(
    `SELECT unit_id, unit_code, unit_name, gender_policy,
            fn_occupancy_pct(unit_id)                    AS occupancy_pct,
            fn_occupancy_band(fn_occupancy_pct(unit_id)) AS band
       FROM hostel_units
      WHERE unit_type = 'BLOCK'
      ORDER BY unit_code`
  );

  const [dues] = await db.query(
    `SELECT NVL(SUM(outstanding), 0) AS total_outstanding,
            COUNT(CASE WHEN outstanding > 0 THEN 1 END) AS students_with_dues
       FROM v_student_dues`
  );

  const [students] = await db.query('SELECT COUNT(*) AS total_students FROM students');

  const recent = await db.query(
    `SELECT a.action, a.details, TO_CHAR(a.logged_at, 'YYYY-MM-DD HH24:MI') AS logged_at,
            u.full_name AS user_name
       FROM audit_log a
       LEFT JOIN app_users u ON u.user_id = a.user_id
      WHERE a.action NOT LIKE 'LOGIN%'
      ORDER BY a.audit_id DESC
      FETCH FIRST 6 ROWS ONLY`
  );

  // MongoDB part is optional: the dashboard still loads if MongoDB is down.
  let openComplaints = null;
  try {
    openComplaints = await mongo.complaints().countDocuments({ status: { $ne: 'RESOLVED' } });
  } catch (_) {
    openComplaints = null;
  }

  res.json({
    beds: { ...beds, occupancy_pct: beds.total_beds ? Math.round((beds.occupied / beds.total_beds) * 1000) / 10 : 0 },
    blocks,
    dues,
    total_students: students.total_students,
    open_complaints: openComplaints,
    recent,
  });
});

router.get('/revenue', async (req, res) => {
  const months = await db.query(
    `SELECT DISTINCT TO_CHAR(month_start, 'YYYY-MM') AS month
       FROM v_mess_daily_revenue
      ORDER BY month DESC`
  );
  const month = MONTH_RE.test(req.query.month || '') ? req.query.month : months[0] && months[0].month;

  const rows = await db.query(
    `SELECT TO_CHAR(meal_date, 'YYYY-MM-DD') AS meal_date,
            meals_served, revenue, month_running_total
       FROM v_mess_daily_revenue
      WHERE month_start = TO_DATE(:month, 'YYYY-MM')
      ORDER BY meal_date`,
    { month: month || null }
  );
  res.json({ month, months: months.map((m) => m.month), rows });
});

module.exports = router;
