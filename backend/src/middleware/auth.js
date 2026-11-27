/**
 * middleware/auth.js
 * ---------------------------------------------------------------------
 * Login sessions with a signed JSON Web Token (JWT) kept in an
 * httpOnly cookie:
 *   - httpOnly : browser JavaScript cannot read the cookie (protects
 *                against token theft through XSS)
 *   - sameSite : the cookie is not sent by other websites (CSRF guard)
 * The token holds the user's id, name and role, and is signed with
 * JWT_SECRET, so it cannot be changed by the user.
 */
const jwt = require('jsonwebtoken');
const config = require('../config');

const COOKIE_NAME = 'hh_token';

/** Create the token after a successful login and put it in the cookie. */
function setLoginCookie(res, user) {
  const token = jwt.sign(
    { user_id: user.user_id, username: user.username, full_name: user.full_name, role: user.role },
    config.jwt.secret,
    { expiresIn: config.jwt.expiresIn }
  );
  res.cookie(COOKIE_NAME, token, {
    httpOnly: true,
    sameSite: 'strict',
    secure: false, // set to true when the site is served over HTTPS
    maxAge: 8 * 60 * 60 * 1000,
  });
}

function clearLoginCookie(res) {
  res.clearCookie(COOKIE_NAME);
}

/** Every protected route uses this. Puts the user in req.user. */
function requireLogin(req, res, next) {
  const token = req.cookies[COOKIE_NAME];
  if (!token) {
    return res.status(401).json({ error: 'Please log in first.' });
  }
  try {
    req.user = jwt.verify(token, config.jwt.secret);
    return next();
  } catch (err) {
    clearLoginCookie(res);
    return res.status(401).json({ error: 'Your session has expired. Please log in again.' });
  }
}

/**
 * Role check, used AFTER requireLogin.
 *   router.delete('/:id', requireRole('ADMIN'), ...)
 * A WARDEN calling an ADMIN-only route gets 403 Forbidden.
 */
function requireRole(...roles) {
  return (req, res, next) => {
    if (!req.user || !roles.includes(req.user.role)) {
      return res.status(403).json({ error: `Only ${roles.join(' or ')} users can do this.` });
    }
    return next();
  };
}

module.exports = { setLoginCookie, clearLoginCookie, requireLogin, requireRole };
