/**
 * invoices.js  -  Invoices screen
 * Everyone can view; only ADMIN can generate invoices and record payments
 * (the server enforces this with requireRole('ADMIN')).
 */
const filterForm = document.getElementById('filterForm');
const genForm = document.getElementById('genForm');
const payForm = document.getElementById('payForm');
let user = null;
let page = 1;
let payingInvoice = null;

(async function start() {
  user = await initPage();
  // Default billing month = current month
  genForm.month.value = new Date().toISOString().slice(0, 7);
  if (user.role === 'ADMIN') {
    try {
      const { rows } = await api('GET', '/api/students?status=ALLOCATED&pageSize=50');
      genForm.student_id.innerHTML += rows.map((s) =>
        `<option value="${s.student_id}">${escapeHtml(s.roll_no)} - ${escapeHtml(s.full_name)}</option>`).join('');
    } catch (err) { showMessage('error', err); }
  }
  load(true);
})();

filterForm.addEventListener('submit', (e) => { e.preventDefault(); page = 1; load(); });

async function load(fillMonths = false) {
  const params = new URLSearchParams({
    q: filterForm.q.value.trim(), month: filterForm.month.value, status: filterForm.status.value, page, pageSize: 15,
  });
  const tbody = document.getElementById('rows');
  try {
    const data = await api('GET', `/api/invoices?${params}`);
    if (fillMonths) {
      filterForm.month.innerHTML = '<option value="">All months</option>' +
        data.months.map((m) => `<option value="${m.month}">${m.month} (${m.invoices} invoices, ${money(m.billed)})</option>`).join('');
    }
    tbody.innerHTML = data.rows.length ? data.rows.map(rowHtml).join('')
      : '<tr><td colspan="12" class="empty">No invoices found.</td></tr>';
    renderPager(document.getElementById('pager'), data, (p) => { page = p; load(); });
    tbody.querySelectorAll('button[data-pay]').forEach((b) => b.addEventListener('click', () => openPay(b.dataset)));
  } catch (err) {
    tbody.innerHTML = '<tr><td colspan="12" class="empty">Could not load invoices.</td></tr>';
    showMessage('error', err);
  }
}

function rowHtml(i) {
  return `<tr>
    <td>${i.invoice_id}</td>
    <td>${escapeHtml(i.billing_month)}</td>
    <td class="mono">${escapeHtml(i.roll_no)}</td>
    <td>${escapeHtml(i.full_name)}</td>
    <td class="num">${num(i.rent_amount)}</td>
    <td class="num">${num(i.mess_amount)}</td>
    <td class="num"><strong>${num(i.total_amount)}</strong></td>
    <td class="num">${num(i.paid_amount)}</td>
    <td class="num">${num(i.balance)}</td>
    <td>${badge(i.status)} ${i.is_overdue === 'Y' ? '<span class="badge badge-red">OVERDUE</span>' : ''}</td>
    <td class="small">${escapeHtml(i.due_date)}</td>
    <td>${user.role === 'ADMIN' && i.status !== 'PAID'
      ? `<button class="btn btn-secondary btn-small" data-pay="${i.invoice_id}" data-balance="${i.balance}" data-label="#${i.invoice_id} ${escapeHtml(i.roll_no)} ${escapeHtml(i.billing_month)}">Pay</button>` : ''}</td>
  </tr>`;
}

/* ---------- generate ---------- */
genForm.addEventListener('submit', async (e) => {
  e.preventDefault();
  clearMessage();
  const body = { student_id: genForm.student_id.value, month: genForm.month.value };
  if (!/^\d{4}-\d{2}$/.test(body.month)) {
    showFieldErrors(genForm, { month: 'Choose a month.' });
    return;
  }
  clearFieldErrors(genForm);
  await withBusy(document.getElementById('genBtn'), async () => {
    try {
      const r = body.student_id
        ? await api('POST', '/api/invoices/generate', body)
        : await api('POST', '/api/invoices/generate-month', { month: body.month });
      let text = r.message;
      if (r.skipped && r.skipped.length) text += ` Skipped ${r.skipped.length}: ${r.skipped.map((s) => s.reason).join(' ')}`;
      showMessage('success', text, { keep: true });
      page = 1;
      load(true);
    } catch (err) {
      showFieldErrors(genForm, err.fields);
      showMessage('error', err);
    }
  });
});

/* ---------- payments ---------- */
function openPay(data) {
  payingInvoice = data.pay;
  document.getElementById('payFor').textContent = `for invoice ${data.label}`;
  payForm.amount.value = data.balance;
  document.getElementById('payCard').classList.remove('hidden');
  document.getElementById('payHint').classList.add('hidden');
  payForm.amount.focus();
}

function closePay() {
  payingInvoice = null;
  payForm.reset();
  clearFieldErrors(payForm);
  document.getElementById('payCard').classList.add('hidden');
  document.getElementById('payHint').classList.remove('hidden');
}
document.getElementById('payCancel').addEventListener('click', closePay);

payForm.addEventListener('submit', async (e) => {
  e.preventDefault();
  clearMessage();
  const body = { amount: payForm.amount.value, method: payForm.method.value, reference_no: payForm.reference_no.value.trim() };
  if (!(Number(body.amount) > 0)) {
    showFieldErrors(payForm, { amount: 'Amount must be greater than 0.' });
    return;
  }
  await withBusy(document.getElementById('payBtn'), async () => {
    try {
      const r = await api('POST', `/api/invoices/${payingInvoice}/payments`, body);
      showMessage('success', r.message);
      closePay();
      load();
    } catch (err) {
      showFieldErrors(payForm, err.fields);
      showMessage('error', err);
    }
  });
});
