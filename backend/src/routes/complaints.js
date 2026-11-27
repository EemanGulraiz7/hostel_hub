/**
 * routes/complaints.js   ->  /api/complaints
 * ---------------------------------------------------------------------
 * MongoDB module: hostel maintenance / mess complaints.
 * A complaint is a natural DOCUMENT: it has a varying list of status
 * updates (an embedded array) and a snapshot of the student's room, so
 * it fits MongoDB better than a fixed Oracle table.
 *
 *   GET    /           list + filters (find)                 ADMIN, WARDEN
 *   GET    /stats      counts per status and category (aggregate)
 *   GET    /:id        one complaint                          ADMIN, WARDEN
 *   POST   /           new complaint (insertOne)              ADMIN, WARDEN
 *   PATCH  /:id        change status + note (updateOne)       ADMIN, WARDEN
 *   DELETE /:id        delete (deleteOne)                     ADMIN only
 *
 * The student's roll number is checked against ORACLE before saving, so
 * a complaint always belongs to a real student (cross-database check).
 */
const express = require('express');
const { ObjectId } = require('mongodb');
const mongo = require('../db/mongo');
const db = require('../db/oracle');
const { requireRole } = require('../middleware/auth');
const {
  validateComplaint, badRequest, str,
  COMPLAINT_CATEGORIES, COMPLAINT_STATUSES,
} = require('../validation');

const router = express.Router();

/** Escape user text before using it inside a regular expression. */
function escapeRegex(text) {
  return text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function toObjectId(id) {
  if (!ObjectId.isValid(id)) throw badRequest({ id: 'Invalid complaint id.' });
  return new ObjectId(id);
}

router.get('/', async (req, res) => {
  // Build the MongoDB filter only from allowed values (no raw user objects,
  // which prevents NoSQL injection such as { "$ne": null }).
  const filter = {};
  if (COMPLAINT_STATUSES.includes(req.query.status)) filter.status = req.query.status;
  if (COMPLAINT_CATEGORIES.includes(req.query.category)) filter.category = req.query.category;
  const q = str(req.query.q);
  if (q) {
    const re = new RegExp(escapeRegex(q.slice(0, 50)), 'i');
    filter.$or = [{ 'student.roll_no': re }, { 'student.full_name': re }, { title: re }, { complaint_no: re }];
  }

  const rows = await mongo
    .complaints()
    .find(filter)
    .sort({ created_at: -1 })
    .limit(100)
    .toArray();
  res.json({ rows });
});

router.get('/stats', async (req, res) => {
  const [byStatus, byCategory] = await Promise.all([
    mongo.complaints().aggregate([{ $group: { _id: '$status', count: { $sum: 1 } } }, { $sort: { _id: 1 } }]).toArray(),
    mongo.complaints().aggregate([{ $group: { _id: '$category', count: { $sum: 1 } } }, { $sort: { count: -1 } }]).toArray(),
  ]);
  res.json({ byStatus, byCategory });
});

router.get('/:id', async (req, res) => {
  const doc = await mongo.complaints().findOne({ _id: toObjectId(req.params.id) });
  if (!doc) return res.status(404).json({ error: 'Complaint not found.' });
  return res.json({ complaint: doc });
});

router.post('/', async (req, res) => {
  const { value, fields } = validateComplaint(req.body);
  if (Object.keys(fields).length) throw badRequest(fields);

  // Cross-check the student in Oracle and take a snapshot of their room.
  const students = await db.query(
    `SELECT s.student_id, s.roll_no, s.full_name, o.block_code, o.room_code, o.bed_code
       FROM students s
       LEFT JOIN v_bed_occupancy o ON o.student_id = s.student_id
      WHERE s.roll_no = :roll_no`,
    { roll_no: value.roll_no }
  );
  if (!students.length) throw badRequest({ roll_no: 'No student with this roll number exists in Oracle.' });
  const s = students[0];

  // Readable number like CMP-0023 from a counter document ($inc is atomic,
  // so two complaints saved at the same moment never get the same number).
  const counter = await mongo.complaints().db.collection('counters').findOneAndUpdate(
    { _id: 'complaint_no' },
    { $inc: { seq: 1 } },
    { upsert: true, returnDocument: 'after' }
  );
  const complaintNo = `CMP-${String(counter.seq).padStart(4, '0')}`;

  const now = new Date();
  const doc = {
    complaint_no: complaintNo,
    student: {
      student_id: s.student_id,
      roll_no: s.roll_no,
      full_name: s.full_name,
      block_code: s.block_code,
      room_code: s.room_code,
      bed_code: s.bed_code,
    },
    category: value.category,
    priority: value.priority,
    title: value.title,
    description: value.description,
    status: 'OPEN',
    created_by: { username: req.user.username, role: req.user.role },
    created_at: now,
    updates: [{ at: now, by: req.user.username, status: 'OPEN', note: 'Complaint logged' }],
  };
  const result = await mongo.complaints().insertOne(doc);
  res.status(201).json({ message: `Complaint ${complaintNo} saved.`, id: result.insertedId, complaint_no: complaintNo });
});

router.patch('/:id', async (req, res) => {
  const _id = toObjectId(req.params.id);
  const status = str(req.body.status).toUpperCase();
  const note = str(req.body.note);
  const fields = {};
  if (!COMPLAINT_STATUSES.includes(status)) fields.status = 'Status must be OPEN, IN_PROGRESS or RESOLVED.';
  if (note.length > 300) fields.note = 'Note must be at most 300 characters.';
  if (Object.keys(fields).length) throw badRequest(fields);

  const now = new Date();
  const update = {
    $set: { status, resolved_at: status === 'RESOLVED' ? now : null },
    $push: { updates: { at: now, by: req.user.username, status, note: note || `Status changed to ${status}` } },
  };
  const result = await mongo.complaints().updateOne({ _id }, update);
  if (!result.matchedCount) return res.status(404).json({ error: 'Complaint not found.' });
  return res.json({ message: `Complaint marked ${status}.` });
});

router.delete('/:id', requireRole('ADMIN'), async (req, res) => {
  const result = await mongo.complaints().deleteOne({ _id: toObjectId(req.params.id) });
  if (!result.deletedCount) return res.status(404).json({ error: 'Complaint not found.' });
  return res.json({ message: 'Complaint deleted.' });
});

module.exports = router;
