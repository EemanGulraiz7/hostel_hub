/**
 * db/oracle.js
 * ---------------------------------------------------------------------
 * Oracle connection pool and two small helpers used by every route.
 *
 * node-oracledb runs in "Thin" mode by default, so NO Oracle Instant
 * Client is needed on your computer.
 *
 * SECURITY: every helper takes SQL with :named bind variables and a
 * separate binds object. Values are sent to Oracle separately from the
 * SQL text, so user input can never change the SQL (no SQL injection).
 *   GOOD:  query('SELECT * FROM students WHERE roll_no = :roll', { roll })
 *   NEVER: query("SELECT * FROM students WHERE roll_no = '" + roll + "'")
 */
const oracledb = require('oracledb');
const config = require('../config');

// Rows come back as { COLUMN_NAME: value } objects instead of arrays.
oracledb.outFormat = oracledb.OUT_FORMAT_OBJECT;
// NUMBER columns come back as JS numbers; CLOBs as strings.
oracledb.fetchAsString = [oracledb.CLOB];

let pool = null;

/** Create the pool once when the server starts. */
async function init() {
  pool = await oracledb.createPool({
    user: config.oracle.user,
    password: config.oracle.password,
    connectString: config.oracle.connectString,
    poolMin: 1,
    poolMax: 5,
    poolIncrement: 1,
  });
  // Quick check so a wrong password is reported at start-up.
  const rows = await query('SELECT USER AS schema_name FROM dual');
  console.log(`Oracle connected as ${rows[0].schema_name} (${config.oracle.connectString})`);
}

/** Close the pool on shutdown (Ctrl+C). */
async function close() {
  if (pool) await pool.close(5);
}

/** Oracle returns UPPERCASE column names; convert them to lowercase for JSON. */
function lowerKeys(row) {
  const out = {};
  for (const [key, value] of Object.entries(row)) out[key.toLowerCase()] = value;
  return out;
}

/**
 * Run ONE statement on its own connection and return the rows.
 * Use autoCommit: true for a single INSERT/UPDATE/DELETE that should be
 * saved immediately.
 */
async function query(sql, binds = {}, options = {}) {
  let conn;
  try {
    conn = await pool.getConnection();
    const result = await conn.execute(sql, binds, options);
    return (result.rows || []).map(lowerKeys);
  } finally {
    if (conn) await conn.close(); // always give the connection back to the pool
  }
}

/**
 * Run several statements on the SAME connection (one transaction).
 * The callback gets the connection; call conn.commit() when everything
 * worked. If the callback throws, everything is rolled back.
 *
 *   await withConnection(async (conn) => {
 *     await conn.execute(...);
 *     await conn.execute(...);
 *     await conn.commit();
 *   });
 */
async function withConnection(work) {
  let conn;
  try {
    conn = await pool.getConnection();
    return await work(conn);
  } catch (err) {
    if (conn) {
      try { await conn.rollback(); } catch (_) { /* connection may already be broken */ }
    }
    throw err;
  } finally {
    if (conn) await conn.close();
  }
}

module.exports = { oracledb, init, close, query, withConnection, lowerKeys };
