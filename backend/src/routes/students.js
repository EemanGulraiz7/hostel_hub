/**
 * routes/students.js   ->  /api/students
 * ---------------------------------------------------------------------
 * Browser-based Oracle CRUD on the STUDENTS table.
 *   GET    /           search / list (filters + paging)      ADMIN, WARDEN
 *   GET    /:id        one student + current bed + dues      ADMIN, WARDEN
 *   POST   /           add a student                         ADMIN, WARDEN
 *   PUT    /:id        edit a student                        ADMIN, WARDEN
 *   DELETE /:id        delete a student                      ADMIN only
 * Every statement uses bind variables (:name), never string concatenation.
 */
const express = require('express');
const db = require('../db/oracle');
const { requireRole } = require('../middleware/auth');
const { validateStudent, badRequest, toId, str } = require('../validation');

const router = express.Router();

router.get('/', async (req, res) => {
  const q = str(req.query.q) || null;
  const gender = ['M', 'F'].includes(req.query.gender) ? req.query.gender : null;
  const status = ['ALLOCATED', 'UNALLOCATED'].includes(req.query.status) ? req.query.status : null;
  const pageSize = Math.min(toId(req.query.pageSize) || 10, 50);
  const page = toId(req.query.page) || 1;

  // v_bed_occupancy gives the CURRENT-term bed, v_student_dues the balance.
  // COUNT(*) OVER () returns the total number of matches on every row,
  // so one query gives both the page of rows and the total for paging.
  const rows = await db.query(
    `SELECT s.student_id, s.roll_no, s.full_name, s.gender, s.email, s.phone,
            s.program, s.semester,
            o.bed_code, o.block_name,
            NVL(d.outstanding, 0) AS outstanding,
            COUNT(*) OVER ()      AS total_rows
       FROM students s
       LEFT JOIN v_bed_occupancy o ON o.student_id = s.student_id
       LEFT JOIN v_student_dues  d ON d.student_id = s.student_id
      WHERE (:q IS NULL
             OR UPPER(s.full_name) LIKE '%' || UPPER(:q) || '%'
             OR s.roll_no          LIKE :q || '%'
             OR s.email            LIKE '%' || LOWER(:q) || '%'
             OR s.program          =    UPPER(:q))
        AND (:gender IS NULL OR s.gender = :gender)
        AND (:status IS NULL
             OR (:status = 'ALLOCATED'   AND o.bed_id IS NOT NULL)
             OR (:status = 'UNALLOCATED' AND o.bed_id IS NULL))
      ORDER BY s.roll_no
      OFFSET :skip ROWS FETCH NEXT :take ROWS ONLY`,
    { q, gender, status, skip: (page - 1) * pageSize, take: pageSize }
  );

  const total = rows.length ? rows[0].total_rows : 0;
  rows.forEach((r) => delete r.total_rows);
  res.json({ rows, total, page, pageSize });
});

router.get('/:id', async (req, res) => {
  const id = toId(req.params.id);
  if (!id) throw badRequest({ id: 'Invalid student id.' });

  const rows = await db.query(
    `SELECT s.student_id, s.roll_no, s.full_name, s.gender, s.email, s.phone,
            s.program, s.semester,
            o.allocation_id, o.bed_code, o.block_name,
            fn_outstanding_balance(s.student_id) AS outstanding   -- PL/SQL function
       FROM students s
       LEFT JOIN v_bed_occupancy o ON o.student_id = s.student_id
      WHERE s.student_id = :id`,
    { id }
  );
  if (!rows.length) return res.status(404).json({ error: 'Student not found.' });
  return res.json({ student: rows[0] });
});

router.post('/', async (req, res) => {
  const { value, fields } = validateStudent(req.body);
  if (Object.keys(fields).length) throw badRequest(fields);

  // RETURNING ... INTO gives back the IDENTITY value Oracle generated.
  const result = await db.withConnection(async (conn) => {
    const r = await conn.execute(
      `INSERT INTO students (roll_no, full_name, gender, email, phone, program, semester)
       VALUES (:roll_no, :full_name, :gender, :email, :phone, :program, :semester)
       RETURNING student_id INTO :new_id`,
      { ...value, new_id: { dir: db.oracledb.BIND_OUT, type: db.oracledb.NUMBER } }
    );
    await conn.commit();
    return r;
  });
  res.status(201).json({ message: `Student ${value.full_name} added.`, student_id: result.outBinds.new_id[0] });
});

router.put('/:id', async (req, res) => {
  const id = toId(req.params.id);
  if (!id) throw badRequest({ id: 'Invalid student id.' });
  const { value, fields } = validateStudent(req.body);
  if (Object.keys(fields).length) throw badRequest(fields);

  const changed = await db.withConnection(async (conn) => {
    // A student who already lives in a gender-restricted block cannot
    // have their gender changed (it would break the block policy).
    const current = await conn.execute(
      `SELECT s.gender, o.gender_policy
         FROM students s
         LEFT JOIN v_bed_occupancy o ON o.student_id = s.student_id
        WHERE s.student_id = :id`,
      { id }
    );
    if (!current.rows.length) return 0;
    const { GENDER, GENDER_POLICY } = current.rows[0];
    if (GENDER_POLICY && GENDER !== value.gender) {
      throw badRequest({ gender: 'This student has a bed in a block for ' + (GENDER_POLICY === 'M' ? 'male' : 'female') + ' students. Vacate the bed before changing gender.' });
    }

    const r = await conn.execute(
      `UPDATE students
          SET roll_no = :roll_no, full_name = :full_name, gender = :gender,
              email = :email, phone = :phone, program = :program, semester = :semester
        WHERE student_id = :id`,
      { ...value, id }
    );
    await conn.commit();
    return r.rowsAffected;
  });
  if (!changed) return res.status(404).json({ error: 'Student not found.' });
  return res.json({ message: `Student ${value.full_name} updated.` });
});

router.delete('/:id', requireRole('ADMIN'), async (req, res) => {
  const id = toId(req.params.id);
  if (!id) throw badRequest({ id: 'Invalid student id.' });
  // If the student has allocations, meals or invoices, the foreign keys
  // stop the delete (ORA-02292) and the error handler explains why.
  const rows = await db.withConnection(async (conn) => {
    const r = await conn.execute('DELETE FROM students WHERE student_id = :id', { id });
    await conn.commit();
    return r.rowsAffected;
  });
  if (!rows) return res.status(404).json({ error: 'Student not found.' });
  return res.json({ message: 'Student deleted.' });
});

module.exports = router;
