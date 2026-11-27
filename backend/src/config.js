/**
 * config.js
 * ---------------------------------------------------------------------
 * Reads settings from the .env file (via dotenv) in ONE place, so the
 * rest of the code never touches process.env directly.
 * Database passwords live only here, on the server. They are never
 * sent to the browser.
 */
const path = require('path');

// Load backend/.env no matter which folder `npm start` is run from.
require('dotenv').config({ path: path.join(__dirname, '..', '.env'), quiet: true });

// Stop early with a clear message if a required setting is missing.
const required = ['ORACLE_USER', 'ORACLE_PASSWORD', 'ORACLE_CONNECT_STRING', 'JWT_SECRET'];
const missing = required.filter((name) => !process.env[name]);
if (missing.length > 0) {
  console.error(`Missing settings in backend/.env: ${missing.join(', ')}`);
  console.error('Copy backend/.env.example to backend/.env and fill it in.');
  process.exit(1);
}

module.exports = {
  port: Number(process.env.PORT) || 3000,
  oracle: {
    user: process.env.ORACLE_USER,
    password: process.env.ORACLE_PASSWORD,
    connectString: process.env.ORACLE_CONNECT_STRING,
  },
  mongo: {
    uri: process.env.MONGO_URI || 'mongodb://localhost:27017',
    dbName: process.env.MONGO_DB || 'hostelhub',
  },
  jwt: {
    secret: process.env.JWT_SECRET,
    expiresIn: process.env.JWT_EXPIRES_IN || '8h',
  },
};
