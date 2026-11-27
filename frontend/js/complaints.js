/**
 * complaints.js  -  MongoDB complaints screen
 *   create  -> POST  /api/complaints        (insertOne)
 *   read    -> GET   /api/complaints        (find with filters)
 *   update  -> PATCH /api/complaints/:id    (updateOne: $set + $push)
 *   delete  -> DELETE /api/complaints/:id   (deleteOne, ADMIN only)
 */
const form = document.getElementById('complaintForm');
const filterForm = document.getElementById('filterForm');
let user = null;

(async function start() {
  user = await initPage();
  load();
  loadStats();
})();

filterForm.addEventListener('submit', (e) => { e.preventDefault(); load(); });

async function load() {
  const params = new URLSearchParams({
    q: filterForm.q.value.trim(), status: filterForm.status.value, category: filterForm.category.value,
  });
  const tbody = document.getElementById('rows');
  try {
    const { rows } = await api('GET', `/api/complaints?${params}`);
    tbody.innerHTML = rows.length ? rows.map(rowHtml).join('')
      : '<tr><td colspan="9" class="empty">No complaints found.</td></tr>';
    tbody.querySelectorAll('select[data-status]').forEach((s) => s.addEventListener('change', () => changeStatus(s)));
    tbody.querySelectorAll('button[data-delete]').forEach((b) => b.addEventListener('click', () => remove(b)));
  } catch (err) {
    tbody.innerHTML = '<tr><td colspan="9" class="empty">Complaints are not available.</td></tr>';
    showMessage('error', err);
  }
}

function rowHtml(c) {
  const last = c.updates && c.updates.length ? c.updates[c.updates.length - 1] : null;
  const options = ['OPEN', 'IN_PROGRESS', 'RESOLVED']
    .map((s) => `<option ${s === c.status ? 'selected' : ''}>${s}</option>`).join('');
  return `<tr>
    <td class="mono">${escapeHtml(c.complaint_no)}</td>
    <td class="small">${new Date(c.created_at).toLocaleDateString('en-GB')}</td>
    <td>${escapeHtml(c.student.full_name)}<br><span class="muted small mono">${escapeHtml(c.student.roll_no)}</span></td>
    <td>${escapeHtml(c.student.room_code || '-')}</td>
    <td class="small">${escapeHtml(c.category.replace('_', ' / '))}</td>
    <td>${badge(c.priority)}</td>
    <td class="wrap"><strong>${escapeHtml(c.title)}</strong><br><span class="small muted">${escapeHtml(c.description)}</span>
      ${last ? `<ul class="timeline"><li>Last update: ${escapeHtml(last.note)} (${escapeHtml(last.by)}, ${new Date(last.at).toLocaleString('en-GB')})</li></ul>` : ''}</td>
    <td>${badge(c.status)}</td>
    <td>
      <select data-status="${c._id}" aria-label="Change status" style="width:auto">${options}</select>
      ${user.role === 'ADMIN' ? `<button class="btn btn-danger btn-small" data-delete="${c._id}" style="margin-top:4px">Delete</button>` : ''}
    </td>
  </tr>`;
}

async function loadStats() {
  try {
    const { byStatus, byCategory } = await api('GET', '/api/complaints/stats');
    document.getElementById('stats').innerHTML = `
      <div class="grid grid-3" style="margin-bottom:14px">
        ${byStatus.map((s) => `<div class="card kpi"><div class="label">${escapeHtml(s._id.replace('_', ' '))}</div><div class="value">${s.count}</div></div>`).join('')}
      </div>
      <table><thead><tr><th>Category</th><th class="num">Complaints</th></tr></thead>
      <tbody>${byCategory.map((c) => `<tr><td>${escapeHtml(c._id.replace('_', ' / '))}</td><td class="num">${c.count}</td></tr>`).join('')}</tbody></table>`;
  } catch (err) {
    document.getElementById('stats').innerHTML = `<p class="muted">${escapeHtml(err.message)}</p>`;
  }
}

form.addEventListener('submit', async (e) => {
  e.preventDefault();
  clearMessage();
  const body = {
    roll_no: form.roll_no.value.trim(), category: form.category.value, priority: form.priority.value,
    title: form.title.value.trim(), description: form.description.value.trim(),
  };
  const errors = {};
  if (!/^\d{6}$/.test(body.roll_no)) errors.roll_no = 'Enter a 6-digit roll number.';
  if (!body.category) errors.category = 'Choose a category.';
  if (body.title.length < 5) errors.title = 'Title must be at least 5 characters.';
  if (body.description.length < 10) errors.description = 'Description must be at least 10 characters.';
  showFieldErrors(form, errors);
  if (Object.keys(errors).length) { showMessage('error', 'Please correct the highlighted fields.'); return; }

  await withBusy(document.getElementById('saveBtn'), async () => {
    try {
      const r = await api('POST', '/api/complaints', body);
      showMessage('success', r.message);
      form.reset();
      load();
      loadStats();
    } catch (err) {
      showFieldErrors(form, err.fields);
      showMessage('error', err);
    }
  });
});

async function changeStatus(select) {
  try {
    const r = await api('PATCH', `/api/complaints/${select.dataset.status}`, { status: select.value });
    showMessage('success', r.message);
    load();
    loadStats();
  } catch (err) {
    showMessage('error', err);
  }
}

async function remove(button) {
  if (button.dataset.armed !== 'yes') {
    button.dataset.armed = 'yes';
    button.textContent = 'Click again';
    setTimeout(() => { button.dataset.armed = ''; button.textContent = 'Delete'; }, 4000);
    return;
  }
  try {
    const r = await api('DELETE', `/api/complaints/${button.dataset.delete}`);
    showMessage('success', r.message);
    load();
    loadStats();
  } catch (err) {
    showMessage('error', err);
  }
}
