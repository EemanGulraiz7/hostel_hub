/**
 * reports.js  -  Analytical reports screen (4 window-function reports)
 */
(async function start() {
  await initPage();
  await Promise.all([loadRunningTotal(), loadMovingAverage(), loadRanking(), loadTrend()]);
  document.getElementById('rtMonth').addEventListener('change', (e) => loadRunningTotal(e.target.value));
  document.getElementById('trendMonth').addEventListener('change', (e) => loadTrend(e.target.value));
})();

async function loadRunningTotal(month) {
  try {
    const d = await api('GET', '/api/reports/running-total' + (month ? `?month=${month}` : ''));
    const sel = document.getElementById('rtMonth');
    if (!sel.options.length) {
      const { months } = await api('GET', '/api/dashboard/revenue');
      sel.innerHTML = months.map((m) => `<option>${m}</option>`).join('');
    }
    sel.value = d.month;
    document.getElementById('rtRows').innerHTML = d.rows.map((r) => `<tr>
      <td>${escapeHtml(r.day)}</td><td class="num">${r.meals_served}</td>
      <td class="num">${num(r.revenue)}</td><td class="num"><strong>${num(r.running_total)}</strong></td></tr>`).join('');
  } catch (err) { showMessage('error', err); }
}

async function loadMovingAverage() {
  try {
    const { rows } = await api('GET', '/api/reports/moving-average');
    new Chart(document.getElementById('maChart'), {
      data: {
        labels: rows.map((r) => r.day.slice(5)),
        datasets: [
          { type: 'bar', label: 'Meals served', data: rows.map((r) => r.meals_served), backgroundColor: '#c9e4ee' },
          { type: 'line', label: '7-day moving average', data: rows.map((r) => r.moving_avg_7d), borderColor: '#1f6f8b', backgroundColor: '#1f6f8b', tension: 0.3, pointRadius: 2 },
        ],
      },
      options: { responsive: true, maintainAspectRatio: false, interaction: { mode: 'index', intersect: false },
        scales: { y: { beginAtZero: false, title: { display: true, text: 'Meals per day' } }, x: { grid: { display: false } } } },
    });
  } catch (err) { showMessage('error', err); }
}

async function loadRanking() {
  try {
    const { rows } = await api('GET', '/api/reports/room-ranking');
    document.getElementById('rankRows').innerHTML = rows.map((r) => `<tr>
      <td class="small">${escapeHtml(r.block_name)}</td><td>${escapeHtml(r.room_code)}</td><td>${escapeHtml(r.room_type)}</td>
      <td class="num">${r.beds}</td><td class="num">${r.occupied}</td><td class="num">${r.occupancy_pct}</td>
      <td class="num"><strong>${r.rank_in_block}</strong></td><td class="num">${r.dense_rank_in_block}</td></tr>`).join('');
  } catch (err) { showMessage('error', err); }
}

async function loadTrend(month) {
  try {
    const d = await api('GET', '/api/reports/mess-trend' + (month ? `?month=${month}` : ''));
    document.getElementById('trendMonthly').innerHTML = d.monthly.map((m) => `<tr>
      <td>${m.month}</td><td class="num">${num(m.mess_total)}</td><td class="num">${num(m.prev_month_total)}</td>
      <td class="num">${m.change_pct == null ? '-' : m.change_pct + '%'}</td><td class="num">${num(m.next_month_total)}</td></tr>`).join('');
    const sel = document.getElementById('trendMonth');
    if (!sel.options.length) sel.innerHTML = d.monthly.map((m) => `<option>${m.month}</option>`).reverse().join('');
    sel.value = d.month;
    document.getElementById('trendStudents').innerHTML = d.students.map((s) => `<tr>
      <td class="mono">${escapeHtml(s.roll_no)}</td><td>${escapeHtml(s.full_name)}</td>
      <td class="num">${num(s.mess_amount)}</td><td class="num">${num(s.prev_month)}</td>
      <td class="num" style="color:${s.change_amt < 0 ? 'var(--success)' : s.change_amt > 0 ? 'var(--danger)' : 'inherit'}">${s.change_amt == null ? '-' : (s.change_amt > 0 ? '+' : '') + num(s.change_amt)}</td>
      <td class="num">${s.change_pct == null ? '-' : s.change_pct + '%'}</td></tr>`).join('');
  } catch (err) { showMessage('error', err); }
}
