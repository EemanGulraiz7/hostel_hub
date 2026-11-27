/**
 * middleware/errors.js
 * ---------------------------------------------------------------------
 * Turns database errors into clear messages for the user.
 *
 * Our PL/SQL raises custom errors with RAISE_APPLICATION_ERROR(-200xx).
 * node-oracledb reports them as err.errorNum = 200xx (no minus sign)
 * and err.message = "ORA-200xx: <our message>\nORA-06512: at ...".
 * The table below gives each code an HTTP status and a friendly text.
 * The list matches the "Custom error codes" table in the README.
 */

// Oracle custom error number -> [HTTP status, message for the user]
const ORACLE_BUSINESS_ERRORS = {
  20000: [400, 'Some required information is missing.'],
  20001: [404, 'That bed does not exist.'],
  20002: [409, 'That bed is not available any more. Please choose another bed.'],
  20003: [409, 'This student already has a bed in this term (or the bed was just taken).'],
  20004: [409, "The student's gender does not match this block's policy."],
  20005: [409, 'This term has already ended. Beds cannot be allocated in a past term.'],
  20006: [404, 'That student does not exist.'],
  20007: [404, 'That term does not exist.'],
  20010: [409, 'This request ID was already used with different details. The original allocation was NOT changed.'],
  20020: [409, 'The student has no active allocation in that month, so no invoice can be made.'],
  20021: [400, 'Student and billing month are required.'],
  20022: [409, 'An invoice already exists for this student and month.'],
  20023: [404, 'That student does not exist.'],
  20024: [409, 'This payment is more than the amount still due on the invoice.'],
  20030: [404, 'That hostel unit does not exist.'],
  20031: [400, 'Student ID is required.'],
  20032: [404, 'That student does not exist.'],
  20033: [400, 'Billing month is required.'],
  20040: [404, 'That allocation does not exist.'],
  20041: [409, 'That allocation is already vacated.'],
  20050: [400, 'A meal cannot be logged for a future date.'],
  20051: [409, 'The student was not a hostel resident on that date.'],
};

// Named constraints from 02_schema.sql -> message (for ORA-00001 / ORA-02290 / ORA-02291 / ORA-02292)
const CONSTRAINT_MESSAGES = {
  UQ_STUDENTS_ROLL: 'A student with this roll number already exists.',
  UQ_STUDENTS_EMAIL: 'A student with this email already exists.',
  CK_STUDENTS_GENDER: 'Gender must be M or F.',
  CK_STUDENTS_SEMESTER: 'Semester must be between 1 and 8.',
  CK_STUDENTS_EMAIL: 'Email address is not valid.',
  UQ_INV_STUDENT_MONTH: 'An invoice already exists for this student and month.',
  CK_PAY_AMOUNT: 'Payment amount must be greater than 0.',
  CK_PAY_METHOD: 'Payment method must be CASH, BANK or CARD.',
  FK_PAY_INVOICE: 'That invoice does not exist.',
};

/** Pull the first line of an ORA- message without the "ORA-20xxx: " prefix. */
function cleanOracleMessage(message) {
  const firstLine = String(message).split('\n')[0];
  return firstLine.replace(/^ORA-\d+:\s*/, '');
}

/** Constraint name from "... constraint (HOSTELHUB.UQ_STUDENTS_ROLL) violated". */
function constraintName(message) {
  const match = /\(\w+\.(\w+)\)/.exec(String(message));
  return match ? match[1].toUpperCase() : null;
}

/**
 * Convert any error into { status, body }.
 * Exported so routes can use it too (e.g. the allocation page shows
 * the Oracle code next to the message for the test evidence).
 */
function toHttpError(err) {
  // Errors we created ourselves in the routes (err.status set).
  if (err.status && !err.errorNum) {
    return { status: err.status, body: { error: err.message, fields: err.fields } };
  }

  const num = err.errorNum;
  if (num && ORACLE_BUSINESS_ERRORS[num]) {
    const [status, message] = ORACLE_BUSINESS_ERRORS[num];
    return {
      status,
      body: { error: message, oracle_code: `ORA-${num}`, detail: cleanOracleMessage(err.message) },
    };
  }

  const name = constraintName(err.message);
  switch (num) {
    case 1: // ORA-00001 unique constraint violated
      return { status: 409, body: { error: CONSTRAINT_MESSAGES[name] || 'This record already exists.', oracle_code: 'ORA-00001', constraint: name } };
    case 1400: // ORA-01400 cannot insert NULL
      return { status: 400, body: { error: 'A required field is empty.', oracle_code: 'ORA-01400' } };
    case 2290: // ORA-02290 check constraint violated
      return { status: 400, body: { error: CONSTRAINT_MESSAGES[name] || 'A value is not allowed.', oracle_code: 'ORA-02290', constraint: name } };
    case 2291: // ORA-02291 parent key not found
      return { status: 400, body: { error: CONSTRAINT_MESSAGES[name] || 'A linked record does not exist.', oracle_code: 'ORA-02291', constraint: name } };
    case 2292: // ORA-02292 child record found
      return { status: 409, body: { error: 'This record is still used by other records (allocations, invoices or meals), so it cannot be deleted.', oracle_code: 'ORA-02292', constraint: name } };
    case 12899: // ORA-12899 value too large for column
      return { status: 400, body: { error: 'One of the values is too long.', oracle_code: 'ORA-12899' } };
    default:
      break;
  }

  // Anything else: log the details on the server, show a generic message.
  console.error(err);
  return { status: 500, body: { error: 'Something went wrong on the server. Check the backend console.' } };
}

/** Express error handler: must be registered LAST in server.js. */
// eslint-disable-next-line no-unused-vars
function errorHandler(err, req, res, next) {
  // Malformed JSON body
  if (err.type === 'entity.parse.failed') {
    return res.status(400).json({ error: 'The request body is not valid JSON.' });
  }
  const { status, body } = toHttpError(err);
  return res.status(status).json(body);
}

module.exports = { errorHandler, toHttpError };
