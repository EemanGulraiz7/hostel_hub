/**
 * seedMongo.js  -  npm run seed:mongo
 * ---------------------------------------------------------------------
 * Loads mongodb/complaints_seed.json (22 complaints) into the
 * "complaints" collection, replacing what is there. The same file is
 * used by the mongosh demo script (mongodb/complaints_crud.mongosh.js).
 */
const fs = require('fs');
const path = require('path');
const { MongoClient, BSON } = require('mongodb');

const { EJSON } = BSON;
const config = require('./config');

async function main() {
  const file = path.join(__dirname, '..', '..', 'mongodb', 'complaints_seed.json');
  // EJSON turns {"$date": "..."} into real Date objects
  const docs = EJSON.parse(fs.readFileSync(file, 'utf8'));

  const client = new MongoClient(config.mongo.uri);
  await client.connect();
  const db = client.db(config.mongo.dbName);

  await db.collection('complaints').deleteMany({});
  const result = await db.collection('complaints').insertMany(docs);
  await db.collection('counters').updateOne(
    { _id: 'complaint_no' },
    { $set: { seq: docs.length } },
    { upsert: true }
  );
  console.log(`Inserted ${result.insertedCount} complaints into ${config.mongo.dbName}.complaints`);
  await client.close();
}

main().catch((err) => {
  console.error('Seeding failed:', err.message);
  process.exit(1);
});
