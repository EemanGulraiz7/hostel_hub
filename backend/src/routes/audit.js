/**
 * routes/audit.js   ->  /api/audit   (ADMIN only, see server.js)
 * ---------------------------------------------------------------------
 * Read-only view of AUDIT_LOG: allocations, payments, logins, failures.
 */
const express = require('express');
const db = require('../db/oracle');
const { toId, str } = require('../validation');

const router = express.Router();

router.get('/', async (req, res) => {
  const action = str(req.query.action).toUpperCase() || null;
  const pageSize = Math.min(toId(req.query.pageSize) || 20, 100);
  const page = toId(req.query.page) || 1;

  const rows = await db.query(
    `SELECT a.audit_id, a.action, a.client_request_id, a.table_name, a.record_id, a.details,
            TO_CHAR(a.logged_at, 'YYYY-MM-DD HH24:MI:SS') AS logged_at,
            u.username,
            COUNT(*) OVER () AS total_rows
       FROM audit_log a
       LEFT JOIN app_users u ON u.user_id = a.user_id
      WHERE (:action IS NULL OR a.action = :action)
      ORDER BY a.audit_id DESC
      OFFSET :skip ROWS FETCH NEXT :take ROWS ONLY`,
    { action, skip: (page - 1) * pageSize, take: pageSize }
  );
  const total = rows.length ? rows[0].total_rows : 0;
  rows.forEach((r) => delete r.total_rows);

  const actions = await db.query(
    'SELECT action, COUNT(*) AS n FROM audit_log GROUP BY action ORDER BY action'
  );
  res.json({ rows, total, page, pageSize, actions });
});

module.exports = router;
