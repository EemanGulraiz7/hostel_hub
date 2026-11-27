/**
 * routes/invoices.js   ->  /api/invoices
 * ---------------------------------------------------------------------
 *   GET  /                  list invoices (filters + paging)       ADMIN, WARDEN
 *   GET  /:id               one invoice with its payments          ADMIN, WARDEN
 *   POST /generate          invoice for ONE student and month      ADMIN only
 *                           -> calls PL/SQL pr_generate_invoice (IN/OUT)
 *   POST /generate-month    invoices for ALL residents of a month  ADMIN only
 *   POST /:id/payments      record a payment                       ADMIN only
 *                           -> trg_payment_audit (AFTER trigger) writes the
 *                              audit row and updates the invoice status
 */
const express = require('express');
const db = require('../db/oracle');
const { requireRole } = require('../middleware/auth');
const { validateInvoice, validatePayment, badRequest, toId, str, MONTH_RE } = require('../validation');
const { toHttpError } = require('../middleware/errors');

const router = express.Router();
const { BIND_OUT, NUMBER } = db.oracledb;

router.get('/', async (req, res) => {
  const month = MONTH_RE.test(req.query.month || '') ? req.query.month : null;
  const status = ['UNPAID', 'PARTIAL', 'PAID'].includes(req.query.status) ? req.query.status : null;
  const q = str(req.query.q) || null;
  const pageSize = Math.min(toId(req.query.pageSize) || 15, 50);
  const page = toId(req.query.page) || 1;

  // Payments are summed in a sub-query first, so each invoice appears once.
  const rows = await db.query(
    `SELECT i.invoice_id, s.student_id, s.roll_no, s.full_name,
            TO_CHAR(i.billing_month, 'YYYY-MM') AS billing_month,
            i.rent_amount, i.mess_amount, i.total_amount,
            NVL(p.paid, 0)                     AS paid_amount,
            i.total_amount - NVL(p.paid, 0)    AS balance,
            i.status,
            TO_CHAR(i.due_date, 'YYYY-MM-DD')  AS due_date,
            CASE WHEN i.status <> 'PAID' AND i.due_date < TRUNC(SYSDATE) THEN 'Y' ELSE 'N' END AS is_overdue,
            COUNT(*) OVER ()                   AS total_rows
       FROM invoices i
       JOIN students s ON s.student_id = i.student_id
       LEFT JOIN (SELECT invoice_id, SUM(amount) AS paid
                    FROM payments
                   GROUP BY invoice_id) p ON p.invoice_id = i.invoice_id
      WHERE (:month  IS NULL OR i.billing_month = TO_DATE(:month, 'YYYY-MM'))
        AND (:status IS NULL OR i.status = :status)
        AND (:q      IS NULL OR s.roll_no LIKE :q || '%' OR UPPER(s.full_name) LIKE '%' || UPPER(:q) || '%')
      ORDER BY i.billing_month DESC, s.roll_no
      OFFSET :skip ROWS FETCH NEXT :take ROWS ONLY`,
    { month, status, q, skip: (page - 1) * pageSize, take: pageSize }
  );
  const total = rows.length ? rows[0].total_rows : 0;
  rows.forEach((r) => delete r.total_rows);

  // Month list for the filter drop-down + totals per month (GROUP BY)
  const months = await db.query(
    `SELECT TO_CHAR(billing_month, 'YYYY-MM') AS month,
            COUNT(*) AS invoices, SUM(total_amount) AS billed
       FROM invoices
      GROUP BY billing_month
      ORDER BY billing_month DESC`
  );
  res.json({ rows, total, page, pageSize, months });
});

router.get('/:id', async (req, res) => {
  const id = toId(req.params.id);
  if (!id) throw badRequest({ id: 'Invalid invoice id.' });
  const inv = await db.query(
    `SELECT i.invoice_id, s.roll_no, s.full_name, TO_CHAR(i.billing_month, 'YYYY-MM') AS billing_month,
            i.rent_amount, i.mess_amount, i.total_amount, i.status,
            TO_CHAR(i.due_date, 'YYYY-MM-DD') AS due_date
       FROM invoices i JOIN students s ON s.student_id = i.student_id
      WHERE i.invoice_id = :id`,
    { id }
  );
  if (!inv.length) return res.status(404).json({ error: 'Invoice not found.' });
  const payments = await db.query(
    `SELECT p.payment_id, p.amount, p.method, p.reference_no,
            TO_CHAR(p.paid_at, 'YYYY-MM-DD HH24:MI') AS paid_at, u.full_name AS received_by
       FROM payments p JOIN app_users u ON u.user_id = p.received_by
      WHERE p.invoice_id = :id
      ORDER BY p.paid_at`,
    { id }
  );
  return res.json({ invoice: inv[0], payments });
});

/** Call pr_generate_invoice on an open connection (the caller commits). */
async function generateOne(conn, studentId, month, userId) {
  const r = await conn.execute(
    `BEGIN
       pr_generate_invoice(p_student_id => :student_id,
                           p_month      => TO_DATE(:month, 'YYYY-MM'),
                           o_invoice_id => :invoice_id,
                           o_total      => :total,
                           p_user_id    => :user_id);
     END;`,
    {
      student_id: studentId,
      month,
      user_id: userId,
      invoice_id: { dir: BIND_OUT, type: NUMBER },
      total: { dir: BIND_OUT, type: NUMBER },
    }
  );
  return r.outBinds;
}

router.post('/generate', requireRole('ADMIN'), async (req, res) => {
  const { value, fields } = validateInvoice(req.body);
  if (Object.keys(fields).length) throw badRequest(fields);

  const out = await db.withConnection(async (conn) => {
    const o = await generateOne(conn, value.student_id, value.month, req.user.user_id);
    await conn.commit(); // pr_generate_invoice does not commit by itself
    return o;
  });
  res.status(201).json({
    message: `Invoice #${out.invoice_id} created. Total: Rs ${out.total.toLocaleString('en-PK')}.`,
    invoice_id: out.invoice_id,
    total: out.total,
  });
});

router.post('/generate-month', requireRole('ADMIN'), async (req, res) => {
  const month = str(req.body.month);
  if (!MONTH_RE.test(month)) throw badRequest({ month: 'Month must be in YYYY-MM format.' });

  // Residents whose allocation's term overlaps the month and who have no
  // invoice for it yet.
  const residents = await db.query(
    `SELECT DISTINCT a.student_id
       FROM allocations a
       JOIN academic_terms t ON t.term_id = a.term_id
      WHERE a.status = 'ACTIVE'
        AND t.start_date <  ADD_MONTHS(TO_DATE(:month, 'YYYY-MM'), 1)
        AND t.end_date   >= TO_DATE(:month, 'YYYY-MM')
        AND NOT EXISTS (SELECT 1 FROM invoices i
                         WHERE i.student_id = a.student_id
                           AND i.billing_month = TO_DATE(:month, 'YYYY-MM'))`,
    { month }
  );

  // One transaction for the whole run, with a SAVEPOINT per student: a
  // student that fails is rolled back to its savepoint and skipped, the
  // others are kept. One COMMIT at the end.
  const summary = await db.withConnection(async (conn) => {
    let created = 0;
    let total = 0;
    const skipped = [];
    for (const r of residents) {
      await conn.execute('SAVEPOINT before_invoice');
      try {
        const o = await generateOne(conn, r.student_id, month, req.user.user_id);
        created += 1;
        total += o.total;
      } catch (err) {
        await conn.execute('ROLLBACK TO SAVEPOINT before_invoice');
        skipped.push({ student_id: r.student_id, reason: toHttpError(err).body.error });
      }
    }
    await conn.commit();
    return { created, total, skipped };
  });

  res.status(201).json({
    message: summary.created
      ? `${summary.created} invoice(s) created for ${month}, total Rs ${summary.total.toLocaleString('en-PK')}.`
      : `No new invoices: every resident already has an invoice for ${month}.`,
    ...summary,
  });
});

router.post('/:id/payments', requireRole('ADMIN'), async (req, res) => {
  const id = toId(req.params.id);
  if (!id) throw badRequest({ id: 'Invalid invoice id.' });
  const { value, fields } = validatePayment(req.body);
  if (Object.keys(fields).length) throw badRequest(fields);

  // The compound trigger trg_payment_audit rejects an over-payment with
  // ORA-20024, writes the PAYMENT_INSERT audit row and sets the invoice
  // status (UNPAID / PARTIAL / PAID), all inside this transaction.
  const out = await db.withConnection(async (conn) => {
    const r = await conn.execute(
      `INSERT INTO payments (invoice_id, amount, method, reference_no, received_by)
       VALUES (:id, :amount, :method, :reference_no, :user_id)
       RETURNING payment_id INTO :payment_id`,
      { id, ...value, user_id: req.user.user_id, payment_id: { dir: BIND_OUT, type: NUMBER } }
    );
    const s = await conn.execute('SELECT status FROM invoices WHERE invoice_id = :id', { id });
    await conn.commit();
    return { payment_id: r.outBinds.payment_id[0], status: s.rows[0].STATUS };
  });
  res.status(201).json({ message: `Payment recorded. Invoice is now ${out.status}.`, ...out });
});

module.exports = router;
