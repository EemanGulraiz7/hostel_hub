/**
 * tests/api_tests.js  -  npm run test:api
 * ---------------------------------------------------------------------
 * Calls the RUNNING backend (npm start in another terminal) the same
 * way the browser does, and prints a test table for the report:
 *   Test ID | What | Expected | Actual | PASS/FAIL
 *
 * It creates one test student (roll number 29xxxx), allocates a bed,
 * then vacates it again, so it can be run many times. For the cleanest
 * demo data, re-run database/00_run_all.sql afterwards.
 */
const crypto = require('crypto');
const BASE = process.env.API_URL || 'http://localhost:3000';

/** Tiny client that keeps the login cookie, like a browser. */
function client() {
  let cookie = '';
  return async (method, path, body) => {
    const res = await fetch(BASE + path, {
      method,
      headers: { 'Content-Type': 'application/json', ...(cookie ? { Cookie: cookie } : {}) },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    const set = res.headers.get('set-cookie');
    if (set) cookie = set.split(';')[0];
    let data = {};
    try { data = await res.json(); } catch (_) { /* no body */ }
    return { status: res.status, data };
  };
}

const results = [];
function check(id, what, expected, actual, pass) {
  results.push({ id, what, expected, actual, result: pass ? 'PASS' : 'FAIL' });
}

async function main() {
  const admin = client();
  const warden = client();

  // ---- T12: login and roles ----
  let r = await admin('POST', '/api/auth/login', { username: 'admin', password: 'wrong-password' });
  check('T12b', 'Login with wrong password', '401, no cookie', `${r.status} ${r.data.error}`, r.status === 401);

  r = await admin('POST', '/api/auth/login', { username: 'admin', password: 'Admin@123' });
  check('T12', 'Admin login', '200, role ADMIN', `${r.status} ${r.data.user && r.data.user.role}`, r.status === 200 && r.data.user.role === 'ADMIN');
  r = await warden('POST', '/api/auth/login', { username: 'warden.ali', password: 'Warden@123' });
  check('T12', 'Warden login', '200, role WARDEN', `${r.status} ${r.data.user && r.data.user.role}`, r.status === 200 && r.data.user.role === 'WARDEN');

  r = await warden('GET', '/api/audit');
  check('T12a', 'Warden opens ADMIN-only audit API', '403 Forbidden', `${r.status} ${r.data.error}`, r.status === 403);
  r = await client()('GET', '/api/students');
  check('T12', 'API call without login', '401', `${r.status}`, r.status === 401);

  // ---- T13: server-side validation ----
  r = await warden('POST', '/api/students', { roll_no: '12', full_name: 'X', gender: 'Z', email: 'not-an-email', program: 'BSIT', semester: 9 });
  check('T13', 'Add student with bad roll/email/semester', '400 with field errors',
    `${r.status} fields: ${Object.keys(r.data.fields || {}).join(', ')}`, r.status === 400 && r.data.fields.email && r.data.fields.semester);

  // ---- T06: browser CRUD on Oracle ----
  const roll = '29' + String(Date.now()).slice(-4);
  const student = { roll_no: roll, full_name: 'Api Test Student', gender: 'M', email: `api.${roll}@student.edu.pk`, phone: '0300-0000000', program: 'BSIT', semester: 3 };
  r = await warden('POST', '/api/students', student);
  const studentId = r.data.student_id;
  check('T06a', 'Add student (POST /api/students)', '201 + new id', `${r.status} id=${studentId}`, r.status === 201 && studentId > 0);

  r = await warden('POST', '/api/students', { ...student, email: `other.${roll}@student.edu.pk` });
  check('T01-web', 'Add student with duplicate roll number', '409 ORA-00001 UQ_STUDENTS_ROLL', `${r.status} ${r.data.oracle_code} ${r.data.constraint}`, r.status === 409 && r.data.constraint === 'UQ_STUDENTS_ROLL');

  r = await warden('PUT', `/api/students/${studentId}`, { ...student, semester: 4 });
  check('T06b', 'Edit student (PUT)', '200', `${r.status} ${r.data.message}`, r.status === 200);

  // A student with no allocations, invoices or meals can be deleted (ADMIN)
  const roll2 = String(Number(roll) + 1);
  r = await warden('POST', '/api/students', { ...student, roll_no: roll2, email: `api.${roll2}@student.edu.pk` });
  r = await admin('DELETE', `/api/students/${r.data.student_id}`);
  check('T06c', 'Admin deletes a student with no history', '200', `${r.status} ${r.data.message}`, r.status === 200);

  r = await warden('DELETE', `/api/students/${studentId}`);
  check('T12a', 'Warden deletes a student (ADMIN only)', '403', `${r.status}`, r.status === 403);

  // ---- T09-T11: retry-safe Allocate Bed ----
  const opts = (await warden('GET', '/api/allocations/options')).data;
  const maleBeds = opts.beds.filter((b) => b.gender_policy === 'M');
  const femaleBed = opts.beds.find((b) => b.gender_policy === 'F');
  const termId = opts.term.term_id;
  const requestId = crypto.randomUUID();
  const body = { client_request_id: requestId, student_id: studentId, bed_id: maleBeds[0].bed_id, term_id: termId };

  if (femaleBed) {
    r = await warden('POST', '/api/allocations', { ...body, client_request_id: crypto.randomUUID(), bed_id: femaleBed.bed_id });
    check('T04-web', 'Allocate male student to girls block', '409 ORA-20004, nothing saved', `${r.status} ${r.data.oracle_code}`, r.status === 409 && r.data.oracle_code === 'ORA-20004');
  }

  r = await warden('POST', '/api/allocations', body);
  const allocationId = r.data.allocation && r.data.allocation.allocation_id;
  check('T09', 'New request (new client_request_id)', '201 CREATED', `${r.status} ${r.data.result} #${allocationId}`, r.status === 201 && r.data.result === 'CREATED');

  r = await warden('POST', '/api/allocations', body);
  check('T10', 'Same request ID + same details', '200 REPLAYED, same allocation id', `${r.status} ${r.data.result} #${r.data.allocation && r.data.allocation.allocation_id}`,
    r.status === 200 && r.data.result === 'REPLAYED' && r.data.allocation.allocation_id === allocationId);

  r = await warden('POST', '/api/allocations', { ...body, bed_id: maleBeds[1].bed_id });
  check('T11', 'Same request ID + different bed', '409 ORA-20010, original kept', `${r.status} ${r.data.oracle_code}`, r.status === 409 && r.data.oracle_code === 'ORA-20010');

  const audit = (await admin('GET', `/api/allocations/audit/${requestId}`)).data.rows;
  const successRows = audit.filter((a) => a.action === 'ALLOCATE_SUCCESS').length;
  check('T09-T11', 'Audit rows for the request ID', 'exactly 1 ALLOCATE_SUCCESS', `${successRows} success, ${audit.length} total`, successRows === 1);

  const list = (await warden('GET', '/api/allocations')).data.rows.filter((a) => a.student_id === studentId);
  check('T10', 'Allocations for the test student', 'exactly 1 active', `${list.length}`, list.length === 1);

  // ---- T05: analytics on the website ----
  r = await warden('GET', '/api/dashboard/revenue');
  check('T05-web', 'Dashboard chart data (v_mess_daily_revenue)', '200 with daily rows', `${r.status} ${r.data.rows && r.data.rows.length} rows`, r.status === 200 && r.data.rows.length > 0);
  for (const rep of ['running-total', 'moving-average', 'room-ranking', 'mess-trend']) {
    r = await warden('GET', `/api/reports/${rep}`);
    check('T05-web', `Report ${rep}`, '200', `${r.status}`, r.status === 200);
  }

  // ---- Payment trigger rejects over-payment ----
  const inv = (await admin('GET', '/api/invoices?status=UNPAID&pageSize=1')).data.rows[0];
  if (inv) {
    r = await admin('POST', `/api/invoices/${inv.invoice_id}/payments`, { amount: inv.balance + 1000, method: 'CASH' });
    check('T02-web', 'Payment larger than the invoice balance', '409 ORA-20024', `${r.status} ${r.data.oracle_code}`, r.status === 409 && r.data.oracle_code === 'ORA-20024');
  }

  // ---- T07b: MongoDB create + read through the website ----
  r = await warden('POST', '/api/complaints', { roll_no: roll, category: 'PLUMBING', priority: 'LOW', title: 'API test complaint', description: 'Created by the automated API test.' });
  const complaintId = r.data.id;
  check('T07b', 'Create complaint (insertOne)', '201', `${r.status} ${r.data.complaint_no || r.data.error}`, r.status === 201);
  r = await warden('GET', `/api/complaints?q=${roll}`);
  check('T07b', 'Read complaints (find)', 'list contains the new complaint', `${r.status} ${r.data.rows ? r.data.rows.length : 0} found`, r.status === 200 && r.data.rows.some((c) => c._id === complaintId));
  r = await warden('POST', '/api/complaints', { roll_no: '999999', category: 'PLUMBING', title: 'Unknown student', description: 'This student does not exist in Oracle.' });
  check('T13', 'Complaint for a roll number not in Oracle', '400', `${r.status} ${r.data.fields && r.data.fields.roll_no}`, r.status === 400);

  // ---- clean up ----
  if (complaintId) await admin('DELETE', `/api/complaints/${complaintId}`);
  if (allocationId) {
    r = await warden('POST', `/api/allocations/${allocationId}/vacate`);
    check('T06c', 'Vacate the test allocation (pr_vacate_bed)', '200', `${r.status}`, r.status === 200);
  }
  r = await admin('DELETE', `/api/students/${studentId}`);
  check('T06c', 'Delete student who has allocation history', '409 ORA-02292 (FK protects history)', `${r.status} ${r.data.oracle_code}`, r.status === 409 && r.data.oracle_code === 'ORA-02292');

  console.table(results);
  const failed = results.filter((x) => x.result === 'FAIL').length;
  console.log(`PASSED: ${results.length - failed}   FAILED: ${failed}`);
  process.exit(failed ? 1 : 0);
}

main().catch((err) => {
  console.error('Test run stopped:', err.message, '\nIs the backend running? (cd backend && npm start)');
  process.exit(1);
});
