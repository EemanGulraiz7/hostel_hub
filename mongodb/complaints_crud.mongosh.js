/* =====================================================================
   HostelHub | complaints_crud.mongosh.js
   ---------------------------------------------------------------------
   MongoDB CRUD demonstration for the report (requirement: insertOne /
   insertMany, find, updateOne and deleteOne with BEFORE / AFTER results).

   HOW TO RUN (from the repository's top folder):
       mongosh "mongodb://localhost:27017/hostelhub" mongodb/complaints_crud.mongosh.js
   or inside mongosh:
       use hostelhub
       load("mongodb/complaints_crud.mongosh.js")

   Take screenshots of the output for the report (T07).
   The script is re-runnable: step 1 resets the collection.
   ===================================================================== */

db = db.getSiblingDB('hostelhub');

function title(text) {
  print('\n' + '='.repeat(70));
  print(text);
  print('='.repeat(70));
}

// ---------------------------------------------------------------------
// 1. CREATE (insertMany): load the 22 seed complaints
//    EJSON.parse converts {"$date": "..."} into real dates.
// ---------------------------------------------------------------------
title('1. insertMany: load 22 complaints from complaints_seed.json');
const seed = EJSON.parse(fs.readFileSync('mongodb/complaints_seed.json', 'utf8'));
db.complaints.deleteMany({});
const many = db.complaints.insertMany(seed);
print('Inserted documents: ' + Object.keys(many.insertedIds).length);
db.counters.updateOne({ _id: 'complaint_no' }, { $set: { seq: seed.length } }, { upsert: true });
print('Total in collection: ' + db.complaints.countDocuments());

// Indexes used by the website (status filter + newest first, roll number search)
db.complaints.createIndex({ status: 1, created_at: -1 });
db.complaints.createIndex({ 'student.roll_no': 1 });

// ---------------------------------------------------------------------
// 2. CREATE (insertOne): a new complaint
// ---------------------------------------------------------------------
title('2. insertOne: new complaint CMP-0023');
const now = new Date();
const one = db.complaints.insertOne({
  complaint_no: 'CMP-0023',
  student: { student_id: 14, roll_no: '231014', full_name: 'Junaid Akram',
             block_code: 'A', room_code: 'A202', bed_code: 'A202-B' },
  category: 'ELECTRICAL',
  priority: 'MEDIUM',
  title: 'Room light switch broken',
  description: 'The main light switch in room A202 is loose and sometimes does not turn on.',
  status: 'OPEN',
  created_by: { username: 'warden.ali', role: 'WARDEN' },
  created_at: now,
  updates: [{ at: now, by: 'warden.ali', status: 'OPEN', note: 'Complaint logged' }],
  resolved_at: null
});
db.counters.updateOne({ _id: 'complaint_no' }, { $inc: { seq: 1 } });
print('insertedId: ' + one.insertedId);
print('Total in collection: ' + db.complaints.countDocuments());

// ---------------------------------------------------------------------
// 3. READ (find): several useful queries
// ---------------------------------------------------------------------
title('3a. find: all OPEN complaints, newest first (projection = selected fields)');
db.complaints.find(
  { status: 'OPEN' },
  { _id: 0, complaint_no: 1, 'student.roll_no': 1, category: 1, priority: 1, title: 1 }
).sort({ created_at: -1 }).forEach(printjson);

title('3b. find: HIGH priority complaints in Block B (query on an embedded field)');
db.complaints.find(
  { priority: 'HIGH', 'student.block_code': 'B' },
  { _id: 0, complaint_no: 1, title: 1, status: 1 }
).forEach(printjson);

title('3c. aggregate: number of complaints per category and how many are still open');
db.complaints.aggregate([
  { $group: { _id: '$category',
              total: { $sum: 1 },
              still_open: { $sum: { $cond: [{ $ne: ['$status', 'RESOLVED'] }, 1, 0] } } } },
  { $sort: { total: -1 } }
]).forEach(printjson);

// ---------------------------------------------------------------------
// 4. UPDATE (updateOne): BEFORE / AFTER
//    $set changes the status, $push adds an entry to the updates array.
// ---------------------------------------------------------------------
title('4. updateOne: CMP-0023 OPEN -> IN_PROGRESS');
print('BEFORE:');
printjson(db.complaints.findOne({ complaint_no: 'CMP-0023' }, { _id: 0, complaint_no: 1, status: 1, updates: 1 }));

const upd = db.complaints.updateOne(
  { complaint_no: 'CMP-0023' },
  { $set:  { status: 'IN_PROGRESS' },
    $push: { updates: { at: new Date(), by: 'warden.ali', status: 'IN_PROGRESS',
                        note: 'Electrician will visit tomorrow' } } }
);
print('matchedCount: ' + upd.matchedCount + ', modifiedCount: ' + upd.modifiedCount);

print('AFTER:');
printjson(db.complaints.findOne({ complaint_no: 'CMP-0023' }, { _id: 0, complaint_no: 1, status: 1, updates: 1 }));

// ---------------------------------------------------------------------
// 5. DELETE (deleteOne): BEFORE / AFTER
// ---------------------------------------------------------------------
title('5. deleteOne: remove CMP-0023');
print('BEFORE: documents with complaint_no CMP-0023 = ' + db.complaints.countDocuments({ complaint_no: 'CMP-0023' })
      + ', total = ' + db.complaints.countDocuments());

const del = db.complaints.deleteOne({ complaint_no: 'CMP-0023' });
print('deletedCount: ' + del.deletedCount);

print('AFTER:  documents with complaint_no CMP-0023 = ' + db.complaints.countDocuments({ complaint_no: 'CMP-0023' })
      + ', total = ' + db.complaints.countDocuments());

// Put the counter back so the website continues from CMP-0023
db.counters.updateOne({ _id: 'complaint_no' }, { $set: { seq: seed.length } });

title('Done. The collection now holds the 22 seed complaints again.');
