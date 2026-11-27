/**
 * server.js  -  HostelHub backend entry point
 * ---------------------------------------------------------------------
 * Start with:  npm start     (then open http://localhost:3000)
 *
 * Architecture (the browser NEVER connects to a database directly):
 *
 *   Browser (frontend/ HTML, CSS, JS)
 *        |  fetch('/api/...')  JSON over HTTP
 *        v
 *   Express API (this backend)  -- validation, login, roles
 *        |                    \
 *        v                     v
 *   Oracle (node-oracledb)    MongoDB (complaints)
 *   tables + PL/SQL
 */
const path = require('path');
const express = require('express');
const helmet = require('helmet');
const cookieParser = require('cookie-parser');

const config = require('./config');
const oracle = require('./db/oracle');
const mongo = require('./db/mongo');
const { requireLogin, requireRole } = require('./middleware/auth');
const { errorHandler } = require('./middleware/errors');

const app = express();

// Security headers (Content-Security-Policy etc.). Our pages load scripts
// only from this server, so the default policy works.
app.use(helmet());
app.use(express.json({ limit: '100kb' }));
app.use(cookieParser());

// ---------- API routes ----------
app.use('/api/auth', require('./routes/auth'));

// Everything below needs a logged-in user
app.use('/api/dashboard', requireLogin, require('./routes/dashboard'));
app.use('/api/students', requireLogin, require('./routes/students'));
app.use('/api/allocations', requireLogin, require('./routes/allocations'));
app.use('/api/invoices', requireLogin, require('./routes/invoices'));
app.use('/api/reports', requireLogin, require('./routes/reports'));
app.use('/api/complaints', requireLogin, require('./routes/complaints'));
app.use('/api/audit', requireLogin, requireRole('ADMIN'), require('./routes/audit'));

// Unknown /api/... address
app.use('/api', (req, res) => res.status(404).json({ error: 'API endpoint not found.' }));

// ---------- Frontend (static files) ----------
// Chart.js is installed with npm and served from node_modules, so the
// dashboard chart works without an internet connection.
app.use('/vendor/chart.js', express.static(path.join(__dirname, '..', 'node_modules', 'chart.js', 'dist')));
app.use(express.static(path.join(__dirname, '..', '..', 'frontend'), { extensions: ['html'] }));
app.get('/', (req, res) => res.redirect('/login.html'));

// Error handler must be the LAST middleware
app.use(errorHandler);

async function start() {
  try {
    await oracle.init();
  } catch (err) {
    console.error('Could not connect to Oracle:', err.message);
    console.error('Check ORACLE_USER / ORACLE_PASSWORD / ORACLE_CONNECT_STRING in backend/.env and that the database is running.');
    process.exit(1);
  }
  await mongo.init(); // optional: the app still runs without MongoDB

  const server = app.listen(config.port, () => {
    console.log(`HostelHub running at http://localhost:${config.port}`);
  });

  // Close connections cleanly on Ctrl+C
  const shutdown = async () => {
    console.log('\nShutting down...');
    server.close();
    await Promise.allSettled([oracle.close(), mongo.close()]);
    process.exit(0);
  };
  process.on('SIGINT', shutdown);
  process.on('SIGTERM', shutdown);
}

start();
