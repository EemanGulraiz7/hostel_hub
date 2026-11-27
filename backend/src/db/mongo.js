/**
 * db/mongo.js
 * ---------------------------------------------------------------------
 * MongoDB connection for the complaints module.
 * Only the backend talks to MongoDB; the browser calls /api/complaints.
 *
 * If MongoDB is not running, the rest of the app still works and the
 * complaints screen shows "MongoDB is not available".
 */
const { MongoClient } = require('mongodb');
const config = require('../config');

let client = null;
let db = null;

async function init() {
  try {
    client = new MongoClient(config.mongo.uri, { serverSelectionTimeoutMS: 3000 });
    await client.connect();
    db = client.db(config.mongo.dbName);
    // Indexes for the queries the website runs (safe to call every start).
    await db.collection('complaints').createIndex({ status: 1, created_at: -1 });
    await db.collection('complaints').createIndex({ 'student.roll_no': 1 });
    console.log(`MongoDB connected (${config.mongo.dbName})`);
  } catch (err) {
    db = null;
    console.warn(`MongoDB NOT connected: ${err.message}`);
    console.warn('The complaints screen will be unavailable until MongoDB is running.');
  }
}

/** Returns the complaints collection, or throws a 503 error if MongoDB is down. */
function complaints() {
  if (!db) {
    const err = new Error('MongoDB is not available. Start MongoDB and restart the backend.');
    err.status = 503;
    throw err;
  }
  return db.collection('complaints');
}

async function close() {
  if (client) await client.close();
}

module.exports = { init, close, complaints };
