/**
 * routes/allocations.js   ->  /api/allocations
 * ---------------------------------------------------------------------
 * THE CORE BUSINESS TRANSACTION: Allocate Bed (retry-safe).
 *
 *   GET  /options        current term, students without a bed, vacant beds
 *   GET  /               active allocations of the current term
 *   POST /               allocate a bed  -> calls PL/SQL pr_allocate_bed
 *   POST /:id/vacate     vacate a bed    -> calls PL/SQL pr_vacate_bed
 *   GET  /audit/:requestId   AUDIT_LOG rows for one client_request_id
 *
 * How the retry safety works (see README "Safe retries"):
 *   1. The browser creates ONE client_request_id (UUID) when the form is
 *      opened, and sends the SAME id again if the user retries.
 *   2. The backend passes it to pr_allocate_bed. Oracle has
 *      UNIQUE (client_request_id) on ALLOCATIONS.
 *   3. pr_allocate_bed returns 'CREATED' the first time and 'REPLAYED'
 *      for an identical retry (nothing changes). The same id with other
 *      details raises ORA-20010, which we return as HTTP 409.
 *   4. pr_allocate_bed does its own COMMIT / ROLLBACK, so a failed call
 *      never leaves half a transaction behind.
 */
const express = require('express');
const db = require('../db/oracle');
const { validateAllocation, badRequest, toId } = require('../validation');

const router = express.Router();
const { BIND_OUT, NUMBER, STRING } = db.oracledb;

/** Current term (the one marked is_current = 'Y'). */
async function currentTerm() {
  const rows = await db.query(
    `SELECT term_id, name,
            TO_CHAR(start_date, 'YYYY-MM-DD') AS start_date,
            TO_CHAR(end_date,   'YYYY-MM-DD') AS end_date
       FROM academic_terms
      WHERE is_current = 'Y'`
  );
  return rows[0] || null;
}

router.get('/options', async (req, res) => {
  const term = await currentTerm();
  if (!term) return res.status(409).json({ error: 'No academic term is marked as current.' });

  // Students who have NO active allocation in the current term
  // (NOT EXISTS subquery).
  const students = await db.query(
    `SELECT s.student_id, s.roll_no, s.full_name, s.gender, s.program
       FROM students s
      WHERE NOT EXISTS (SELECT 1
                          FROM allocations a
                         WHERE a.student_id = s.student_id
                           AND a.term_id    = :term_id
                           AND a.status     = 'ACTIVE')
      ORDER BY s.roll_no`,
    { term_id: term.term_id }
  );

  // Vacant beds from the view (includes the block's gender policy so the
  // page can show only beds that match the chosen student).
  const beds = await db.query(
    `SELECT bed_id, bed_code, block_code, block_name, gender_policy,
            floor_code, room_code, room_type, monthly_rent
       FROM v_vacant_beds
      ORDER BY bed_code`
  );

  return res.json({ term, students, beds });
});

router.get('/', async (req, res) => {
  const term = await currentTerm();
  const rows = await db.query(
    `SELECT a.allocation_id, a.client_request_id,
            TO_CHAR(a.allocated_at, 'YYYY-MM-DD HH24:MI') AS allocated_at,
            s.student_id, s.roll_no, s.full_name,
            o.bed_code, o.block_name, o.room_type, o.monthly_rent,
            u.full_name AS allocated_by
       FROM allocations a
       JOIN students        s ON s.student_id = a.student_id
       JOIN v_bed_occupancy o ON o.bed_id     = a.bed_id
       JOIN app_users       u ON u.user_id    = a.allocated_by
      WHERE a.status  = 'ACTIVE'
        AND a.term_id = :term_id
      ORDER BY a.allocated_at DESC, a.allocation_id DESC`,
    { term_id: term ? term.term_id : null }
  );
  res.json({ term, rows });
});

router.post('/', async (req, res) => {
  // 1. Server-side validation (the browser checks too, but never trust it).
  const { value, fields } = validateAllocation(req.body);
  if (Object.keys(fields).length) throw badRequest(fields);

  // 2. Call the PL/SQL procedure with bind variables. IN values come from
  //    the request; the user id comes from the login token, NOT from the
  //    browser, so a user cannot pretend to be someone else.
  const result = await db.withConnection((conn) =>
    conn.execute(
      `BEGIN
         pr_allocate_bed(
           p_client_request_id => :client_request_id,
           p_student_id        => :student_id,
           p_bed_id            => :bed_id,
           p_term_id           => :term_id,
           p_user_id           => :user_id,
           o_allocation_id     => :allocation_id,
           o_result            => :result);
       END;`,
      {
        ...value,
        user_id: req.user.user_id,
        allocation_id: { dir: BIND_OUT, type: NUMBER },
        result: { dir: BIND_OUT, type: STRING, maxSize: 10 },
      }
    )
  );

  const { allocation_id, result: outcome } = result.outBinds;

  // 3. Read back the saved allocation so the page can show it.
  const saved = await db.query(
    `SELECT a.allocation_id, a.client_request_id, s.roll_no, s.full_name, o.bed_code,
            o.block_name, TO_CHAR(a.allocated_at, 'YYYY-MM-DD HH24:MI:SS') AS allocated_at
       FROM allocations a
       JOIN students        s ON s.student_id = a.student_id
       JOIN v_bed_occupancy o ON o.bed_id     = a.bed_id
      WHERE a.allocation_id = :id`,
    { id: allocation_id }
  );

  // 201 Created for a new allocation, 200 OK when an identical retry is replayed.
  res.status(outcome === 'CREATED' ? 201 : 200).json({
    result: outcome,
    message:
      outcome === 'CREATED'
        ? 'Bed allocated successfully.'
        : 'This request was already processed. The saved allocation is shown; nothing was changed.',
    allocation: saved[0],
  });
});

router.post('/:id/vacate', async (req, res) => {
  const id = toId(req.params.id);
  if (!id) throw badRequest({ id: 'Invalid allocation id.' });
  await db.withConnection((conn) =>
    conn.execute('BEGIN pr_vacate_bed(:id, :user_id); END;', { id, user_id: req.user.user_id })
  );
  res.json({ message: 'Bed vacated. It is available again.' });
});

router.get('/audit/:requestId', async (req, res) => {
  const rows = await db.query(
    `SELECT a.audit_id, a.action, a.table_name, a.record_id, a.details,
            TO_CHAR(a.logged_at, 'YYYY-MM-DD HH24:MI:SS') AS logged_at,
            u.username
       FROM audit_log a
       LEFT JOIN app_users u ON u.user_id = a.user_id
      WHERE a.client_request_id = :rid
      ORDER BY a.audit_id`,
    { rid: String(req.params.requestId).slice(0, 64) }
  );
  res.json({ rows });
});

module.exports = router;
