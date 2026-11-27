/**
 * allocate.js  -  Screen 5: the business transaction (Allocate Bed)
 * ---------------------------------------------------------------------
 * Retry safety from the browser side:
 *   - When the form opens we create ONE client_request_id (a UUID).
 *   - "Allocate bed" and "Send same request again" both send that SAME id.
 *   - Only "Start new allocation" creates a new id.
 * Oracle decides: CREATED (first time), REPLAYED (identical retry) or
 * ORA-20010 (same id, different details).
 */
const form = document.getElementById('allocForm');
const studentSelect = document.getElementById('student_id');
const bedSelect = document.getElementById('bed_id');
const showAll = document.getElementById('showAllBeds');
const retryBtn = document.getElementById('retryBtn');

let options = { students: [], beds: [], term: null };

(async function start() {
  await initPage();
  newRequest();
  await loadOptions();
  const pre = new URLSearchParams(location.search).get('student');
  if (pre) { studentSelect.value = pre; fillBeds(); }
  loadAllocations();
})();

/** New UUID = a new, separate allocation attempt. */
function newRequest() {
  const id = newRequestId();
  form.client_request_id.value = id;
  document.getElementById('requestIdText').textContent = id;
  retryBtn.disabled = true;
}

async function loadOptions() {
  try {
    options = await api('GET', '/api/allocations/options');
    form.term_id.value = options.term.term_id;
    document.getElementById('termText').textContent =
      `${options.term.name} (${options.term.start_date} to ${options.term.end_date})`;

    const keep = studentSelect.value;
    studentSelect.innerHTML = '<option value="">Choose a student...</option>' +
      options.students.map((s) => `<option value="${s.student_id}" data-gender="${s.gender}">
        ${escapeHtml(s.roll_no)} - ${escapeHtml(s.full_name)} (${s.gender === 'M' ? 'Male' : 'Female'}, ${escapeHtml(s.program)})</option>`).join('');
    if ([...studentSelect.options].some((o) => o.value === keep)) studentSelect.value = keep;
    fillBeds();
  } catch (err) {
    showMessage('error', err);
  }
}

/** Show only beds in blocks that match the chosen student's gender (unless "show all" is ticked). */
function fillBeds() {
  const opt = studentSelect.selectedOptions[0];
  const gender = opt ? opt.dataset.gender : null;
  const keep = bedSelect.value;
  const beds = options.beds.filter((b) => showAll.checked || !gender || b.gender_policy === gender);
  bedSelect.innerHTML = '<option value="">Choose a bed...</option>' +
    beds.map((b) => `<option value="${b.bed_id}">${escapeHtml(b.bed_code)} - ${escapeHtml(b.block_name)}, ${escapeHtml(b.room_type)} room, ${money(b.monthly_rent)}/month</option>`).join('');
  if ([...bedSelect.options].some((o) => o.value === keep)) bedSelect.value = keep;
}

studentSelect.addEventListener('change', fillBeds);
showAll.addEventListener('change', fillBeds);

document.getElementById('newBtn').addEventListener('click', async () => {
  newRequest();
  clearMessage();
  document.getElementById('result').innerHTML = '<p class="muted">New request ID created. Submit the form to see the result here.</p>';
  document.getElementById('auditRows').innerHTML = '<tr><td colspan="4" class="empty">-</td></tr>';
  await loadOptions();
});

form.addEventListener('submit', (e) => { e.preventDefault(); send(document.getElementById('allocateBtn')); });
retryBtn.addEventListener('click', () => send(retryBtn));

async function send(button) {
  clearMessage();
  const body = {
    client_request_id: form.client_request_id.value,
    student_id: studentSelect.value,
    bed_id: bedSelect.value,
    term_id: form.term_id.value,
  };

  const errors = {};
  if (!body.student_id) errors.student_id = 'Choose a student.';
  if (!body.bed_id) errors.bed_id = 'Choose a bed.';
  showFieldErrors(form, errors);
  if (Object.keys(errors).length) {
    showMessage('error', 'Please choose a student and a bed.');
    return;
  }

  await withBusy(button, async () => {
    try {
      const r = await api('POST', '/api/allocations', body);
      showMessage('success', r.message);
      showResult(r.result, r.allocation, null);
      retryBtn.disabled = false; // now the same request can be re-sent
    } catch (err) {
      showFieldErrors(form, err.fields);
      showMessage('error', err);
      showResult('ERROR', null, err);
      if (err.status === 409 || err.status === 404) retryBtn.disabled = false;
    }
    await loadAuditTrail(body.client_request_id);
    loadAllocations();
    // The student and bed lists are NOT reloaded here, so the same
    // selections stay on screen and the request can be re-sent (T10) or
    // re-sent with a changed bed (T11). "Start new allocation" reloads them.
  });
}

function showResult(outcome, a, err) {
  const box = document.getElementById('result');
  if (err) {
    box.innerHTML = `<p><span class="badge badge-red">REJECTED</span> HTTP ${err.status}</p>
      <dl class="kv">
        <dt>Message</dt><dd>${escapeHtml(err.message)}</dd>
        ${err.body && err.body.oracle_code ? `<dt>Oracle error</dt><dd class="mono">${escapeHtml(err.body.oracle_code)}: ${escapeHtml(err.body.detail || '')}</dd>` : ''}
        <dt>Database</dt><dd>Rolled back: no allocation, bed unchanged, no success audit row.</dd>
      </dl>`;
    return;
  }
  box.innerHTML = `<p>${badge(outcome)} ${outcome === 'CREATED' ? 'HTTP 201: new allocation saved' : 'HTTP 200: saved result returned, nothing changed'}</p>
    <dl class="kv">
      <dt>Allocation #</dt><dd><strong>${a.allocation_id}</strong></dd>
      <dt>Student</dt><dd>${escapeHtml(a.roll_no)} - ${escapeHtml(a.full_name)}</dd>
      <dt>Bed</dt><dd>${escapeHtml(a.bed_code)} (${escapeHtml(a.block_name)})</dd>
      <dt>Allocated at</dt><dd>${escapeHtml(a.allocated_at)}</dd>
      <dt>client_request_id</dt><dd class="mono">${escapeHtml(a.client_request_id)}</dd>
    </dl>`;
}

async function loadAuditTrail(requestId) {
  try {
    const { rows } = await api('GET', `/api/allocations/audit/${encodeURIComponent(requestId)}`);
    document.getElementById('auditRows').innerHTML = rows.length
      ? rows.map((r) => `<tr><td>${r.audit_id}</td><td>${badge(r.action)}</td>
          <td class="wrap small">${escapeHtml(r.details)}</td><td class="small">${escapeHtml(r.logged_at)}</td></tr>`).join('')
      : '<tr><td colspan="4" class="empty">No audit rows for this request ID.</td></tr>';
  } catch (err) {
    showMessage('error', err);
  }
}

async function loadAllocations() {
  const tbody = document.getElementById('allocRows');
  try {
    const { rows } = await api('GET', '/api/allocations');
    document.getElementById('allocCount').textContent = `(${rows.length})`;
    tbody.innerHTML = rows.length
      ? rows.map((a) => `<tr>
          <td>${a.allocation_id}</td>
          <td class="mono">${escapeHtml(a.roll_no)}</td>
          <td>${escapeHtml(a.full_name)}</td>
          <td><span class="badge badge-blue">${escapeHtml(a.bed_code)}</span></td>
          <td>${escapeHtml(a.block_name)}</td>
          <td>${escapeHtml(a.room_type)}</td>
          <td class="num">${money(a.monthly_rent)}</td>
          <td class="small">${escapeHtml(a.allocated_at)}</td>
          <td class="small">${escapeHtml(a.allocated_by)}</td>
          <td><button class="btn btn-secondary btn-small" data-vacate="${a.allocation_id}">Vacate</button></td>
        </tr>`).join('')
      : '<tr><td colspan="10" class="empty">No allocations this term.</td></tr>';
    tbody.querySelectorAll('button[data-vacate]').forEach((b) => b.addEventListener('click', () => vacate(b)));
  } catch (err) {
    tbody.innerHTML = '<tr><td colspan="10" class="empty">Could not load allocations.</td></tr>';
  }
}

async function vacate(button) {
  if (button.dataset.armed !== 'yes') {
    button.dataset.armed = 'yes';
    button.textContent = 'Click again to confirm';
    setTimeout(() => { button.dataset.armed = ''; button.textContent = 'Vacate'; }, 4000);
    return;
  }
  try {
    const r = await api('POST', `/api/allocations/${button.dataset.vacate}/vacate`);
    showMessage('success', r.message);
    loadAllocations();
    loadOptions();
  } catch (err) {
    showMessage('error', err);
  }
}
