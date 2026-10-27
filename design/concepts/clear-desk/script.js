(function () {
  var root = document.documentElement;
  var q = new URLSearchParams(location.search);
  var states = ['browse', 'skills', 'teach', 'assistant', 'settings'];

  function setState(s) {
    if (states.indexOf(s) < 0) return;
    root.setAttribute('data-state', s);
    var open = s !== 'browse';
    document.querySelectorAll('.panel-tabs [data-panel]').forEach(function (b) {
      b.setAttribute('aria-selected', String(b.dataset.panel === s));
    });
    document.querySelector('[data-action="panel"]').setAttribute('aria-pressed', String(open));
    document.querySelectorAll('.switcher [data-state]').forEach(function (b) {
      b.classList.toggle('on', b.dataset.state === s);
    });
  }
  function setTheme(t) { root.setAttribute('data-theme', t); }

  if (q.get('state')) setState(q.get('state'));
  if (q.get('theme')) setTheme(q.get('theme'));
  if (q.has('shot')) root.classList.add('shot');
  setState(root.getAttribute('data-state'));

  document.addEventListener('click', function (e) {
    var t = e.target.closest('[data-state],[data-panel],[data-action],.skill-head,.tab');
    if (!t) return;
    if (t.dataset.state) return setState(t.dataset.state);
    if (t.dataset.panel) return setState(t.dataset.panel);
    if (t.classList.contains('tab')) {
      e.preventDefault();
      if (e.target.classList.contains('close')) { t.remove(); return; }
      document.querySelectorAll('.tab').forEach(function (x) { x.classList.remove('selected'); });
      t.classList.add('selected');
      return;
    }
    if (t.classList.contains('skill-head')) {
      var card = t.parentElement, was = card.classList.contains('expanded');
      document.querySelectorAll('.skill').forEach(function (c) { c.classList.remove('expanded'); c.querySelector('.skill-head').setAttribute('aria-expanded', 'false'); });
      if (!was) { card.classList.add('expanded'); t.setAttribute('aria-expanded', 'true'); }
      return;
    }
    switch (t.dataset.action) {
      case 'theme': setTheme(root.getAttribute('data-theme') === 'dark' ? 'light' : 'dark'); break;
      case 'panel': setState(root.getAttribute('data-state') === 'browse' ? 'skills' : 'browse'); break;
      case 'closepanel': setState('browse'); break;
      case 'teach': setState('teach'); break;
      case 'adopt': setState('teach'); break;
      case 'dismiss': root.classList.add('suggest-dismissed'); break;
      case 'discard': setState('browse'); root.classList.remove('picking'); break;
      case 'pick': root.classList.toggle('picking'); break;
      case 'save': root.classList.remove('picking'); setState('skills'); break;
      case 'run': run(t); break;
      case 'savesettings': flash(t.parentElement.querySelector('.saved')); break;
      case 'copyconfig': t.textContent = 'Copied'; setTimeout(function () { t.textContent = 'Copy MCP config'; }, 1400); break;
      case 'clear': document.querySelectorAll('.chat .line').forEach(function (l) { l.remove(); }); break;
    }
  });

  document.querySelector('.composer input').addEventListener('keydown', function (e) {
    if (e.key !== 'Enter' || !this.value.trim()) return;
    e.preventDefault();
    var chat = document.querySelector('.chat'), busy = chat.querySelector('.busy');
    var u = document.createElement('div'); u.className = 'line user'; u.textContent = this.value.trim();
    chat.insertBefore(u, busy); this.value = '';
  });

  document.querySelectorAll('.pickable').forEach(function (el) {
    el.addEventListener('click', function () {
      if (!root.classList.contains('picking')) return;
      el.classList.add('picked'); root.classList.remove('picking');
    });
  });

  function run(btn) {
    var body = btn.closest('.skill-body'), line = body.querySelector('.runline');
    btn.disabled = true; btn.textContent = 'Running';
    body.classList.add('running');
    setTimeout(function () {
      body.classList.remove('running');
      btn.disabled = false; btn.textContent = 'Run';
      var id = Math.random().toString(16).slice(2, 10);
      body.querySelector('.run-head .mono').textContent = 'run ' + id;
      body.querySelector('.run-head .dim:last-child').textContent = (2 + Math.random()).toFixed(1) + ' s';
      body.querySelector('.outputs dd').textContent = ['In transit', 'Delivered', 'Packed'][Math.floor(Math.random() * 3)];
    }, 1500);
  }
  function flash(el) { el.classList.add('show'); setTimeout(function () { el.classList.remove('show'); }, 1200); }

  document.addEventListener('keydown', function (e) {
    if (e.target.matches('input,textarea')) return;
    var i = parseInt(e.key, 10);
    if (i >= 1 && i <= 5) setState(states[i - 1]);
    if (e.key === 'l' || e.key === 'L') setTheme(root.getAttribute('data-theme') === 'dark' ? 'light' : 'dark');
    if (e.key === 'Escape') setState('browse');
  });
})();
