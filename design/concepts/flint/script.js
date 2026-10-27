// State toggles only. No layout work happens here.
(function () {
  var root = document.documentElement;
  var states = ['browse', 'skills', 'teach', 'assistant', 'settings'];

  function apply() {
    var h = location.hash.replace('#', '');
    var parts = h.split('+');
    var state = states.indexOf(parts[0]) >= 0 ? parts[0] : 'browse';
    var theme = parts.indexOf('light') >= 0 ? 'light' : 'dark';
    root.dataset.state = state;
    root.dataset.theme = theme;
    document.querySelectorAll('[data-go]').forEach(function (b) {
      b.classList.toggle('on', b.dataset.go === state);
    });
    var tb = document.getElementById('themeBtn');
    if (tb) tb.textContent = theme === 'dark' ? 'L Light' : 'L Dark';
  }

  function go(state, theme) {
    theme = theme || root.dataset.theme;
    location.hash = state + (theme === 'light' ? '+light' : '');
  }

  document.querySelectorAll('[data-go]').forEach(function (b) {
    b.addEventListener('click', function () { go(b.dataset.go); });
  });
  document.getElementById('themeBtn').addEventListener('click', function () {
    go(root.dataset.state, root.dataset.theme === 'dark' ? 'light' : 'dark');
  });
  document.getElementById('panelBtn').addEventListener('click', function () {
    go(root.dataset.state === 'browse' ? 'skills' : 'browse');
  });
  document.getElementById('teachBtn').addEventListener('click', function () { go('teach'); });

  document.addEventListener('keydown', function (e) {
    if (e.metaKey || e.ctrlKey || e.altKey) return;
    if (e.target && /INPUT|TEXTAREA/.test(e.target.tagName)) return;
    var n = parseInt(e.key, 10);
    if (n >= 1 && n <= 5) go(states[n - 1]);
    if (e.key === 'l' || e.key === 'L') go(root.dataset.state, root.dataset.theme === 'dark' ? 'light' : 'dark');
  });

  // Quiet micro-interactions: copy confirms in place, run shows a progress line.
  var copy = document.getElementById('copyCfg');
  if (copy) copy.addEventListener('click', function () {
    var label = copy.lastChild;
    var old = label.textContent;
    label.textContent = 'Copied';
    copy.classList.add('done');
    setTimeout(function () { label.textContent = old; copy.classList.remove('done'); }, 1200);
  });
  document.querySelectorAll('.skill-row').forEach(function (r) {
    r.addEventListener('click', function () { r.parentElement.classList.toggle('open'); });
  });

  window.addEventListener('hashchange', apply);
  apply();
})();
