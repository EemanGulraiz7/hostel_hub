/**
 * students.js  -  Screen 3: searchable student list
 * GET /api/students with search filters and paging. Admins also see a
 * Delete button (DELETE /api/students/:id is ADMIN-only on the server).
 */
const filterForm = document.getElementById('filterForm');
let state = { page: 1 };
let user = null;

(async function start() {
  user = await initPage();
  const flash = sessionStorage.getItem('flash');
  if (flash) { showMessage('success', flash); sessionStorage.removeItem('flash'); }
  load();
})();

filterForm.addEventListener('submit', (e) => { e.preventDefault(); state.page = 1; load(); });
filterForm.addEventListener('reset', () => { setTimeout(() => { state.page = 1; load(); }, 0); });

async function load() {
  const params = new URLSearchParams({
    q: filterForm.q.value.trim(),
    gender: filterForm.gender.value,
    status: filterForm.status.value,
    page: state.page,
    pageSize: 10,
  });
  const tbody = document.getElementById('rows');
  try {
    const data = await api('GET', `/api/students?${params}`);
    tbody.innerHTML = data.rows.length
      ? data.rows.map(rowHtml).join('')
      : '<tr><td colspan="9" class="empty">No students match your search.</td></tr>';
    renderPager(document.getElementById('pager'), data, (p) => { state.page = p; load(); });
    tbody.querySelectorAll('button[data-delete]').forEach((b) => b.addEventListener('click', () => removeStudent(b)));
  } catch (err) {
    tbody.innerHTML = '<tr><td colspan="9" class="empty">Could not load students.</td></tr>';
    showMessage('error', err);
  }
}

function rowHtml(s) {
  return `<tr>
    <td class="mono">${escapeHtml(s.roll_no)}</td>
    <td>${escapeHtml(s.full_name)}</td>
    <td>${s.gender === 'M' ? 'Male' : 'Female'}</td>
    <td>${escapeHtml(s.program)}</td>
    <td>${s.semester}</td>
    <td class="small">${escapeHtml(s.email)}</td>
    <td>${s.bed_code ? `<span class="badge badge-blue">${escapeHtml(s.bed_code)}</span>` : '<span class="muted small">none</span>'}</td>
    <td class="num">${s.outstanding > 0 ? `<strong>${money(s.outstanding)}</strong>` : money(0)}</td>
    <td>
      <a class="btn btn-secondary btn-small" href="/student-form.html?id=${s.student_id}">Edit</a>
      ${s.bed_code ? '' : `<a class="btn btn-secondary btn-small" href="/allocate.html?student=${s.student_id}">Allocate</a>`}
      ${user.role === 'ADMIN' ? `<button class="btn btn-danger btn-small" data-delete="${s.student_id}" data-name="${escapeHtml(s.full_name)}">Delete</button>` : ''}
    </td>
  </tr>`;
}

async function removeStudent(button) {
  // Ask twice-click style instead of window.confirm: first click arms the button.
  if (button.dataset.armed !== 'yes') {
    button.dataset.armed = 'yes';
    button.textContent = 'Click again to delete';
    setTimeout(() => { button.dataset.armed = ''; button.textContent = 'Delete'; }, 4000);
    return;
  }
  try {
    const r = await api('DELETE', `/api/students/${button.dataset.delete}`);
    showMessage('success', `${r.message} (${button.dataset.name})`);
    load();
  } catch (err) {
    showMessage('error', err);
  }
}
