/**
 * login.js  -  Screen 1: Login
 * Sends the username and password to POST /api/auth/login. The server
 * checks the bcrypt hash and sets an httpOnly cookie on success.
 */
const form = document.getElementById('loginForm');

if (new URLSearchParams(location.search).get('expired')) {
  showMessage('info', 'Please log in to continue.');
}

// Already logged in? Go straight to the dashboard.
fetch('/api/auth/me', { credentials: 'same-origin' }).then((r) => {
  if (r.ok) window.location.href = '/dashboard.html';
});

form.addEventListener('submit', async (event) => {
  event.preventDefault();
  clearFieldErrors(form);
  clearMessage();

  const username = form.username.value.trim();
  const password = form.password.value;

  // Browser-side check (the server checks again)
  const fields = {};
  if (!username) fields.username = 'Username is required.';
  if (!password) fields.password = 'Password is required.';
  if (Object.keys(fields).length) {
    showFieldErrors(form, fields);
    return;
  }

  await withBusy(document.getElementById('loginBtn'), async () => {
    try {
      await api('POST', '/api/auth/login', { username, password });
      window.location.href = '/dashboard.html';
    } catch (err) {
      showFieldErrors(form, err.fields);
      showMessage('error', err);
      form.password.value = '';
      form.password.focus();
    }
  });
});
