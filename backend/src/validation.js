/**
 * validation.js
 * ---------------------------------------------------------------------
 * Server-side validation. The browser also checks the forms, but a
 * user can bypass the browser (e.g. with Postman or curl), so the
 * backend ALWAYS checks again before anything reaches Oracle/MongoDB.
 *
 * Each validator returns { value, fields }:
 *   value  - the cleaned data (trimmed, converted to numbers, ...)
 *   fields - { fieldName: 'error message' } ; empty when everything is OK
 * badRequest() turns the field errors into a 400 response.
 */

/** Build an error that the error handler sends as HTTP 400 with field messages. */
function badRequest(fields, message = 'Please correct the highlighted fields.') {
  const err = new Error(message);
  err.status = 400;
  err.fields = fields;
  return err;
}

function str(v) {
  return typeof v === 'string' ? v.trim() : v == null ? '' : String(v).trim();
}

/** Positive whole number (used for ids), or null if not valid. */
function toId(v) {
  const n = Number(v);
  return Number.isInteger(n) && n > 0 ? n : null;
}

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const MONTH_RE = /^\d{4}-(0[1-9]|1[0-2])$/; // YYYY-MM
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

/** Student add/edit form (matches the STUDENTS table constraints). */
function validateStudent(body) {
  const fields = {};
  const value = {
    roll_no: str(body.roll_no),
    full_name: str(body.full_name),
    gender: str(body.gender).toUpperCase(),
    email: str(body.email).toLowerCase(),
    phone: str(body.phone) || null,
    program: str(body.program).toUpperCase(),
    semester: Number(body.semester),
  };

  if (!/^\d{6}$/.test(value.roll_no)) fields.roll_no = 'Roll number must be exactly 6 digits, e.g. 231031.';
  if (value.full_name.length < 3 || value.full_name.length > 80) fields.full_name = 'Name must be 3 to 80 characters.';
  else if (!/^[A-Za-z .'-]+$/.test(value.full_name)) fields.full_name = 'Name may contain letters, spaces, dots, hyphens and apostrophes only.';
  if (!['M', 'F'].includes(value.gender)) fields.gender = 'Choose Male or Female.';
  if (!EMAIL_RE.test(value.email) || value.email.length > 100) fields.email = 'Enter a valid email address.';
  if (value.phone && !/^[0-9+\- ]{7,20}$/.test(value.phone)) fields.phone = 'Phone may contain digits, spaces, + and - (7 to 20 characters).';
  if (!value.program || value.program.length > 40) fields.program = 'Program is required (max 40 characters).';
  if (!Number.isInteger(value.semester) || value.semester < 1 || value.semester > 8) fields.semester = 'Semester must be a whole number from 1 to 8.';

  return { value, fields };
}

/** Allocate Bed request. */
function validateAllocation(body) {
  const fields = {};
  const value = {
    client_request_id: str(body.client_request_id),
    student_id: toId(body.student_id),
    bed_id: toId(body.bed_id),
    term_id: toId(body.term_id),
  };
  if (!UUID_RE.test(value.client_request_id)) fields.client_request_id = 'client_request_id must be a UUID created by the browser.';
  if (!value.student_id) fields.student_id = 'Choose a student.';
  if (!value.bed_id) fields.bed_id = 'Choose a bed.';
  if (!value.term_id) fields.term_id = 'Choose a term.';
  return { value, fields };
}

/** Generate invoice request. */
function validateInvoice(body) {
  const fields = {};
  const value = { student_id: toId(body.student_id), month: str(body.month) };
  if (!value.student_id) fields.student_id = 'Choose a student.';
  if (!MONTH_RE.test(value.month)) fields.month = 'Month must be in YYYY-MM format.';
  return { value, fields };
}

/** Record payment request. */
function validatePayment(body) {
  const fields = {};
  const value = {
    amount: Number(body.amount),
    method: str(body.method).toUpperCase(),
    reference_no: str(body.reference_no) || null,
  };
  if (!Number.isFinite(value.amount) || value.amount <= 0) fields.amount = 'Amount must be greater than 0.';
  else if (Math.round(value.amount * 100) !== value.amount * 100) fields.amount = 'Amount can have at most 2 decimal places.';
  if (!['CASH', 'BANK', 'CARD'].includes(value.method)) fields.method = 'Method must be CASH, BANK or CARD.';
  if (value.reference_no && value.reference_no.length > 40) fields.reference_no = 'Reference must be at most 40 characters.';
  return { value, fields };
}

// Values allowed in the MongoDB complaints collection
const COMPLAINT_CATEGORIES = ['ELECTRICAL', 'PLUMBING', 'FURNITURE', 'CLEANLINESS', 'MESS_FOOD', 'INTERNET', 'SECURITY', 'OTHER'];
const COMPLAINT_PRIORITIES = ['LOW', 'MEDIUM', 'HIGH'];
const COMPLAINT_STATUSES = ['OPEN', 'IN_PROGRESS', 'RESOLVED'];

/** New complaint form. */
function validateComplaint(body) {
  const fields = {};
  const value = {
    roll_no: str(body.roll_no),
    category: str(body.category).toUpperCase(),
    priority: str(body.priority).toUpperCase() || 'MEDIUM',
    title: str(body.title),
    description: str(body.description),
  };
  if (!/^\d{6}$/.test(value.roll_no)) fields.roll_no = 'Enter the student\'s 6-digit roll number.';
  if (!COMPLAINT_CATEGORIES.includes(value.category)) fields.category = 'Choose a category.';
  if (!COMPLAINT_PRIORITIES.includes(value.priority)) fields.priority = 'Priority must be LOW, MEDIUM or HIGH.';
  if (value.title.length < 5 || value.title.length > 100) fields.title = 'Title must be 5 to 100 characters.';
  if (value.description.length < 10 || value.description.length > 1000) fields.description = 'Description must be 10 to 1000 characters.';
  return { value, fields };
}

module.exports = {
  badRequest, toId, str, MONTH_RE,
  validateStudent, validateAllocation, validateInvoice, validatePayment, validateComplaint,
  COMPLAINT_CATEGORIES, COMPLAINT_PRIORITIES, COMPLAINT_STATUSES,
};
