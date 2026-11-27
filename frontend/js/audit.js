/**
 * audit.js  -  Audit log screen (ADMIN only; a WARDEN gets "access denied"
 * here and HTTP 403 from GET /api/audit).
 */
const filterForm = document.getElementById('filterForm');
let page = 1;
let filled = false;

(async function start() {
  await initPage();
  load();
})();

filterForm.addEventListener('submit', (e) => { e.preventDefault(); page = 1; load(); });

async function load() {
  try {
    const d = await api('GET', `/api/audit?${new URLSearchParams({ action: filterForm.action.value, page })}`);
    if (!filled) {
      filterForm.action.innerHTML += d.actions.map((a) => `<option value="${escapeHtml(a.action)}">${escapeHtml(a.action)} (${a.n})</option>`).join('');
      filled = true;
    }
    document.getElementById('rows').innerHTML = d.rows.length ? d.rows.map((r) => `<tr>
      <td>${r.audit_id}</td><td class="small">${escapeHtml(r.logged_at)}</td><td>${escapeHtml(r.username || '-')}</td>
      <td>${badge(r.action)}</td><td class="small">${escapeHtml(r.table_name || '')}</td><td>${r.record_id ?? ''}</td>
      <td class="mono small">${escapeHtml(r.client_request_id || '')}</td><td class="wrap small">${escapeHtml(r.details || '')}</td></tr>`).join('')
      : '<tr><td colspan="8" class="empty">No audit rows.</td></tr>';
    renderPager(document.getElementById('pager'), d, (p) => { page = p; load(); });
  } catch (err) {
    showMessage('error', err);
  }
}
