/**
 * student-form.js  -  Screen 4: add / edit form
 *   /student-form.html          -> POST /api/students      (add)
 *   /student-form.html?id=12    -> PUT  /api/students/12   (edit)
 * The browser checks the fields first for quick feedback; the server
 * checks them again and Oracle constraints are the last line of defence
 * (e.g. duplicate roll number -> ORA-00001 -> "already exists").
 */
const form = document.getElementById('studentForm');
const studentId = new URLSearchParams(location.search).get('id');

(async function start() {
  await initPage();
  if (studentId) {
    document.getElementById('formTitle').textContent = 'Edit student';
    try {
      const { student } = await api('GET', `/api/students/${encodeURIComponent(studentId)}`);
      ['roll_no', 'full_name', 'gender', 'email', 'phone', 'program', 'semester'].forEach((f) => {
        form[f].value = student[f] ?? '';
      });
      document.getElementById('bedInfo').innerHTML = `
        <label>Current bed / dues</label>
        <div>${student.bed_code ? `<span class="badge badge-blue">${escapeHtml(student.bed_code)}</span> ${escapeHtml(student.block_name)}` : '<span class="muted">No bed this term</span>'}
        &middot; Outstanding: <strong>${money(student.outstanding)}</strong>
        <span class="muted small">(PL/SQL fn_outstanding_balance)</span></div>`;
    } catch (err) {
      showMessage('error', err);
      form.querySelector('button[type=submit]').disabled = true;
    }
  }
})();

/** Browser-side checks: the same rules as backend/src/validation.js */
function checkForm(v) {
  const f = {};
  if (!/^\d{6}$/.test(v.roll_no)) f.roll_no = 'Roll number must be exactly 6 digits.';
  if (v.full_name.length < 3) f.full_name = 'Name must be at least 3 characters.';
  if (!v.gender) f.gender = 'Choose a gender.';
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(v.email)) f.email = 'Enter a valid email address.';
  if (v.phone && !/^[0-9+\- ]{7,20}$/.test(v.phone)) f.phone = 'Phone may contain digits, spaces, + and -.';
  if (!v.program) f.program = 'Choose a program.';
  if (!v.semester) f.semester = 'Choose a semester.';
  return f;
}

form.addEventListener('submit', async (event) => {
  event.preventDefault();
  clearMessage();
  const values = {
    roll_no: form.roll_no.value.trim(),
    full_name: form.full_name.value.trim(),
    gender: form.gender.value,
    email: form.email.value.trim(),
    phone: form.phone.value.trim(),
    program: form.program.value,
    semester: form.semester.value,
  };

  const errors = checkForm(values);
  showFieldErrors(form, errors);
  if (Object.keys(errors).length) {
    showMessage('error', 'Please correct the highlighted fields.');
    return;
  }

  await withBusy(document.getElementById('saveBtn'), async () => {
    try {
      const r = studentId
        ? await api('PUT', `/api/students/${encodeURIComponent(studentId)}`, values)
        : await api('POST', '/api/students', values);
      sessionStorage.setItem('flash', r.message);
      window.location.href = '/students.html';
    } catch (err) {
      showFieldErrors(form, err.fields);
      // Map Oracle unique-constraint errors to the right field
      if (err.body && err.body.constraint === 'UQ_STUDENTS_ROLL') showFieldErrors(form, { roll_no: err.message });
      if (err.body && err.body.constraint === 'UQ_STUDENTS_EMAIL') showFieldErrors(form, { email: err.message });
      showMessage('error', err);
    }
  });
});
