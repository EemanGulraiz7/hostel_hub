/**
 * dashboard.js  -  Screen 2: Dashboard
 * KPI tiles, the analytics chart (running total of mess revenue), block
 * occupancy from PL/SQL functions and the latest audit entries.
 */
let chart = null;

/** Colour for the occupancy band returned by fn_occupancy_band. */
function bandBadge(band) {
  const c = { LOW: 'blue', MEDIUM: 'amber', HIGH: 'green', FULL: 'red' }[band] || '';
  return `<span class="badge badge-${c}">${escapeHtml(band)}</span>`;
}

(async function start() {
  const user = await initPage();
  document.getElementById('welcome').textContent = `Welcome, ${user.full_name}`;

  try {
    const d = await api('GET', '/api/dashboard');
    document.getElementById('kpiOcc').textContent = `${d.beds.occupancy_pct}%`;
    document.getElementById('kpiOccSub').textContent = `${d.beds.occupied} of ${d.beds.total_beds} beds occupied`;
    document.getElementById('kpiVacant').textContent = d.beds.available;
    document.getElementById('kpiVacantSub').textContent = `${d.beds.maintenance} under maintenance`;
    document.getElementById('kpiDues').textContent = money(d.dues.total_outstanding);
    document.getElementById('kpiDuesSub').textContent = `${d.dues.students_with_dues} students with dues`;
    document.getElementById('kpiComplaints').textContent = d.open_complaints ?? 'n/a';

    document.getElementById('blocks').innerHTML = d.blocks.map((b) => `
      <div style="margin-bottom:14px">
        <div style="display:flex;justify-content:space-between;gap:8px">
          <strong>${escapeHtml(b.unit_name)}</strong>
          <span>${b.occupancy_pct}% ${bandBadge(b.band)}</span>
        </div>
        <div class="bar"><span style="width:${Math.min(100, b.occupancy_pct)}%"></span></div>
        <span class="muted small">Block ${escapeHtml(b.unit_code)} &middot; ${b.gender_policy === 'M' ? 'Boys' : 'Girls'}</span>
      </div>`).join('');

    document.getElementById('recent').innerHTML = d.recent.length
      ? d.recent.map((r) => `<tr>
          <td class="small">${escapeHtml(r.logged_at)}</td>
          <td>${badge(r.action)}</td>
          <td>${escapeHtml(r.user_name || '-')}</td></tr>`).join('')
      : '<tr><td colspan="3" class="empty">No activity yet.</td></tr>';
  } catch (err) {
    showMessage('error', err);
  }

  await loadRevenue();
  document.getElementById('monthSelect').addEventListener('change', (e) => loadRevenue(e.target.value));
})();

async function loadRevenue(month) {
  try {
    const data = await api('GET', '/api/dashboard/revenue' + (month ? `?month=${encodeURIComponent(month)}` : ''));
    const select = document.getElementById('monthSelect');
    if (!select.options.length) {
      select.innerHTML = data.months.map((m) => `<option value="${m}">${m}</option>`).join('');
    }
    select.value = data.month;
    drawChart(data.rows);
  } catch (err) {
    showMessage('error', err);
  }
}

function drawChart(rows) {
  const labels = rows.map((r) => r.meal_date.slice(8)); // day of month
  if (chart) chart.destroy();
  chart = new Chart(document.getElementById('revenueChart'), {
    data: {
      labels,
      datasets: [
        { type: 'bar', label: 'Daily revenue (Rs)', data: rows.map((r) => r.revenue), backgroundColor: '#8cc7da', yAxisID: 'y' },
        { type: 'line', label: 'Running total (Rs)', data: rows.map((r) => r.month_running_total), borderColor: '#16324f', backgroundColor: '#16324f', tension: 0.2, pointRadius: 2, yAxisID: 'y1' },
      ],
    },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      interaction: { mode: 'index', intersect: false },
      scales: {
        x: { title: { display: true, text: 'Day of month' }, grid: { display: false } },
        y: { position: 'left', title: { display: true, text: 'Daily (Rs)' }, beginAtZero: true },
        y1: { position: 'right', title: { display: true, text: 'Running total (Rs)' }, beginAtZero: true, grid: { drawOnChartArea: false } },
      },
      plugins: {
        tooltip: { callbacks: { label: (c) => `${c.dataset.label}: ${Number(c.raw).toLocaleString('en-PK')}` } },
      },
    },
  });
}
