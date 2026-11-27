/**
 * app.js  -  shared code loaded by every page (except login)
 * ---------------------------------------------------------------------
 * - api()            : calls the backend (/api/...) and handles errors
 * - initPage()       : checks login, draws the sidebar, hides admin-only parts
 * - showMessage()    : success / error messages at the top of the page
 * - showFieldErrors(): red messages under form fields (from server validation)
 * - small helpers    : money(), escapeHtml(), newRequestId(), badge()
 *
 * NOTE: the browser only talks to OUR backend. It never connects to
 * Oracle or MongoDB and never sees a database password.
 */

/* ---------- calling the backend ---------- */

/**
 * api('GET', '/api/students?q=ali')
 * api('POST', '/api/students', { roll_no: '231031', ... })
 * Returns the JSON body. On an error status it throws an Error with:
 *   err.status  HTTP status (400, 401, 403, 404, 409, 500 ...)
 *   err.fields  { field: message } from server-side validation
 *   err.body    the full JSON error body (oracle_code, detail ...)
 */
async function api(method, url, body) {
  const options = { method, headers: {}, credentials: 'same-origin' };
  if (body !== undefined) {
    options.headers['Content-Type'] = 'application/json';
    options.body = JSON.stringify(body);
  }

  let response;
  try {
    response = await fetch(url, options);
  } catch (networkError) {
    const err = new Error('Cannot reach the server. Is the backend running (npm start)?');
    err.status = 0;
    throw err;
  }

  let data = {};
  try { data = await response.json(); } catch (_) { /* empty body */ }

  if (response.status === 401 && !url.startsWith('/api/auth/login')) {
    // Not logged in or session expired -> back to the login page
    window.location.href = '/login.html?expired=1';
    throw new Error(data.error || 'Please log in.');
  }
  if (!response.ok) {
    const err = new Error(data.error || `Request failed (${response.status})`);
    err.status = response.status;
    err.fields = data.fields || {};
    err.body = data;
    throw err;
  }
  return data;
}

/* ---------- page set-up ---------- */

const NAV_ITEMS = [
  { href: '/dashboard.html', label: 'Dashboard', page: 'dashboard' },
  { href: '/students.html', label: 'Students', page: 'students' },
  { href: '/allocate.html', label: 'Allocate Bed', page: 'allocate' },
  { href: '/invoices.html', label: 'Invoices', page: 'invoices' },
  { href: '/reports.html', label: 'Reports', page: 'reports' },
  { href: '/complaints.html', label: 'Complaints', page: 'complaints' },
  { href: '/audit.html', label: 'Audit Log', page: 'audit', role: 'ADMIN' },
];

let currentUser = null;

/**
 * Call at the top of every page script:
 *   const user = await initPage();
 * Redirects to login when not logged in; if the page is ADMIN-only and
 * the user is a WARDEN, shows an "access denied" message instead.
 */
async function initPage() {
  const { user } = await api('GET', '/api/auth/me');
  currentUser = user;
  renderSidebar(user);

  // Elements marked data-role="ADMIN" are only shown to admins.
  // (This is only for a tidy screen. The REAL check is on the server,
  // which answers 403 if a warden calls an admin-only API.)
  document.querySelectorAll('[data-role]').forEach((el) => {
    if (el.dataset.role !== user.role) el.classList.add('hidden');
  });

  const pageRole = document.body.dataset.requiresRole;
  if (pageRole && pageRole !== user.role) {
    document.querySelector('main').innerHTML =
      `<div class="alert alert-error">Access denied: only ${escapeHtml(pageRole)} users can open this page.</div>`;
    throw new Error('access denied');
  }
  return user;
}

function renderSidebar(user) {
  const aside = document.getElementById('sidebar');
  if (!aside) return;
  const page = document.body.dataset.page;
  const links = NAV_ITEMS
    .filter((item) => !item.role || item.role === user.role)
    .map((item) => `<a href="${item.href}" class="${item.page === page ? 'active' : ''}">${item.label}</a>`)
    .join('');

  aside.innerHTML = `
    <div class="brand">HostelHub</div>
    <div class="brand-sub">Room Allocation &amp; Mess Billing</div>
    <nav>${links}</nav>
    <div class="user-box">
      <div><strong>${escapeHtml(user.full_name)}</strong>
      <span class="small">${escapeHtml(user.username)} &middot; ${escapeHtml(user.role)}</span></div>
      <button class="btn btn-ghost btn-small" id="logoutBtn" type="button">Log out</button>
    </div>`;

  document.getElementById('logoutBtn').addEventListener('click', async () => {
    await api('POST', '/api/auth/logout');
    window.location.href = '/login.html';
  });
}

/* ---------- messages ---------- */

/**
 * showMessage('success', 'Student added.')
 * showMessage('error', err)   // an Error from api(): shows message + Oracle code
 */
function showMessage(type, messageOrError, { target = 'messages', keep = false } = {}) {
  const box = document.getElementById(target);
  if (!box) return;
  let text = messageOrError;
  let detail = '';
  if (messageOrError instanceof Error) {
    text = messageOrError.message;
    const b = messageOrError.body || {};
    if (b.oracle_code) detail = `${b.oracle_code}${b.detail ? ': ' + b.detail : ''}`;
  }
  const cls = { success: 'alert-success', error: 'alert-error', info: 'alert-info', warning: 'alert-warning' }[type] || 'alert-info';
  box.innerHTML = `<div class="alert ${cls}" role="${type === 'error' ? 'alert' : 'status'}">
      ${escapeHtml(text)}${detail ? `<span class="detail mono">${escapeHtml(detail)}</span>` : ''}
    </div>`;
  box.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
  if (!keep && type === 'success') {
    setTimeout(() => { if (box.firstElementChild) box.innerHTML = ''; }, 6000);
  }
}

function clearMessage(target = 'messages') {
  const box = document.getElementById(target);
  if (box) box.innerHTML = '';
}

/** Put server-side validation messages under the matching form fields. */
function showFieldErrors(form, fields = {}) {
  clearFieldErrors(form);
  Object.entries(fields).forEach(([name, message]) => {
    const input = form.querySelector(`[name="${name}"]`);
    if (!input) return;
    const field = input.closest('.field');
    field.classList.add('invalid');
    const el = field.querySelector('.field-error');
    if (el) el.textContent = message;
  });
}

function clearFieldErrors(form) {
  form.querySelectorAll('.field.invalid').forEach((f) => f.classList.remove('invalid'));
  form.querySelectorAll('.field-error').forEach((e) => { e.textContent = ''; });
}

/* ---------- helpers ---------- */

function escapeHtml(value) {
  return String(value ?? '')
    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
}

function money(n) {
  if (n === null || n === undefined) return '-';
  return 'Rs ' + Number(n).toLocaleString('en-PK', { maximumFractionDigits: 2 });
}

function num(n) {
  return n === null || n === undefined ? '-' : Number(n).toLocaleString('en-PK');
}

/** A new UUID for client_request_id (one per allocation form submission). */
function newRequestId() {
  if (window.crypto && crypto.randomUUID) return crypto.randomUUID();
  // Fallback for old browsers: RFC 4122 version 4 from crypto.getRandomValues
  const b = crypto.getRandomValues(new Uint8Array(16));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  const h = [...b].map((x) => x.toString(16).padStart(2, '0')).join('');
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20)}`;
}

/** Coloured status badge. */
function badge(text) {
  const colours = {
    PAID: 'green', RESOLVED: 'green', CREATED: 'green', ALLOCATE_SUCCESS: 'green', LOW: 'blue',
    PARTIAL: 'amber', IN_PROGRESS: 'amber', MEDIUM: 'amber', REPLAYED: 'blue', HIGH: 'red',
    UNPAID: 'red', OPEN: 'red', ALLOCATE_FAILED: 'red', LOGIN_FAILED: 'red',
  };
  const c = colours[text];
  return `<span class="badge ${c ? 'badge-' + c : ''}">${escapeHtml(String(text).replace(/_/g, ' '))}</span>`;
}

/** Disable a button while an async action runs (stops double clicks). */
async function withBusy(button, work) {
  const label = button.textContent;
  button.disabled = true;
  button.textContent = 'Please wait...';
  try {
    return await work();
  } finally {
    button.disabled = false;
    button.textContent = label;
  }
}

/** Simple pager under a table. */
function renderPager(el, { page, pageSize, total }, onPage) {
  const pages = Math.max(1, Math.ceil(total / pageSize));
  el.innerHTML = `
    <span class="muted small">${total} record(s) &middot; page ${page} of ${pages}</span>
    <span>
      <button class="btn btn-secondary btn-small" data-go="${page - 1}" ${page <= 1 ? 'disabled' : ''}>Previous</button>
      <button class="btn btn-secondary btn-small" data-go="${page + 1}" ${page >= pages ? 'disabled' : ''}>Next</button>
    </span>`;
  el.querySelectorAll('button[data-go]').forEach((b) =>
    b.addEventListener('click', () => onPage(Number(b.dataset.go))));
}
