const btn = document.getElementById('theme-toggle');
if (btn) {
  btn.addEventListener('click', () => {
    const next = document.body.dataset.theme === 'dark' ? 'light' : 'dark';
    document.body.dataset.theme = next;
    try {
      localStorage.setItem('oh-theme', next);
    } catch (_) {}
  });
}
