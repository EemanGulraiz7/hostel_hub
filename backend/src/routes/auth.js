/**
 * routes/auth.js   ->  /api/auth
 * ---------------------------------------------------------------------
 * POST /login   check username + password against APP_USERS (bcrypt)
 * POST /logout  clear the login cookie
 * GET  /me      who is logged in (the frontend calls this on every page)
 */
const express = require('express');
const bcrypt = require('bcryptjs');
const db = require('../db/oracle');
const { setLoginCookie, clearLoginCookie, requireLogin } = require('../middleware/auth');
const { str } = require('../validation');

const router = express.Router();

// A real bcrypt hash of a random string. Used when the username does not
// exist, so a wrong username takes as long as a wrong password and an
// attacker cannot tell which usernames exist.
const DUMMY_HASH = '$2b$10$tjnBJSWhF8q/e7ct9h9uE.nnZWS1KIi2k8MF2XyGfiKOrAiE8NF8a';

/** Write LOGIN_SUCCESS / LOGIN_FAILED to AUDIT_LOG (never blocks the login). */
async function auditLogin(userId, action, username) {
  try {
    await db.query(
      `INSERT INTO audit_log (user_id, action, table_name, record_id, details)
       VALUES (:user_id, :action, 'APP_USERS', :user_id, :details)`,
      { user_id: userId, action, details: `username=${username.slice(0, 30)}` },
      { autoCommit: true }
    );
  } catch (err) {
    console.warn('Could not write login audit row:', err.message);
  }
}

router.post('/login', async (req, res) => {
  const username = str(req.body.username).toLowerCase();
  const password = typeof req.body.password === 'string' ? req.body.password : '';

  // Server-side validation
  const fields = {};
  if (!username) fields.username = 'Username is required.';
  if (!password) fields.password = 'Password is required.';
  if (Object.keys(fields).length) {
    return res.status(400).json({ error: 'Please enter your username and password.', fields });
  }

  const rows = await db.query(
    `SELECT user_id, username, password_hash, full_name, role
       FROM app_users
      WHERE username = :username
        AND is_active = 'Y'`,
    { username }
  );
  const user = rows[0];

  // bcrypt.compare hashes the typed password with the stored salt and
  // compares. The plain password is never stored or logged.
  const ok = await bcrypt.compare(password, user ? user.password_hash : DUMMY_HASH);
  if (!user || !ok) {
    await auditLogin(user ? user.user_id : null, 'LOGIN_FAILED', username);
    return res.status(401).json({ error: 'Wrong username or password.' });
  }

  await auditLogin(user.user_id, 'LOGIN_SUCCESS', username);
  setLoginCookie(res, user);
  return res.json({
    user: { user_id: user.user_id, username: user.username, full_name: user.full_name, role: user.role },
  });
});

router.post('/logout', (req, res) => {
  clearLoginCookie(res);
  res.json({ message: 'Logged out.' });
});

router.get('/me', requireLogin, (req, res) => {
  const { user_id, username, full_name, role } = req.user;
  res.json({ user: { user_id, username, full_name, role } });
});

module.exports = router;
