// Licensed under GPL-3.0. See LICENSE.
//
//  Scripts.swift
//  BrowserSkills
//
//  Page scripts. All run in the isolated `BrowserSkills` content world, so the page can neither
//  call them nor forge a recorded action. Selector generation is adapted from Nook's
//  DevPickerScript (nook-browser/Nook, GPL-3.0).
//

import WebKit

enum Scripts {
    static let world = WKContentWorld.world(name: "BrowserSkills")
    static let recorderHandler = "bsRecorder"
    static let pickerHandler = "bsPicker"

    /// Shared helpers: unique selectors, alternates, accessible names, element resolution.
    static let common = #"""
    window.__bs = window.__bs || (function () {
      function unique(sel) { try { return document.querySelectorAll(sel).length === 1; } catch (_) { return false; } }
      function esc(v) { return CSS.escape(v); }
      function attrSel(tag, name, v) { return tag + '[' + name + '="' + String(v).replace(/"/g, '\\"') + '"]'; }

      function pathSelector(el) {
        const parts = [];
        for (let node = el; node && node.nodeType === 1 && node !== document.documentElement; node = node.parentElement) {
          const test = node.getAttribute('data-testid');
          if (test && unique('[data-testid="' + esc(test) + '"]')) { parts.unshift('[data-testid="' + esc(test) + '"]'); break; }
          if (node !== el && node.id && unique('#' + esc(node.id))) { parts.unshift('#' + esc(node.id)); break; }
          let part = node.tagName.toLowerCase();
          // Readable class names only; hashed ones (css-1x2y3z, sc-abc123) change on every build.
          const classes = typeof node.className === 'string'
            ? node.className.trim().split(/\s+/).filter(c => c && !/\d{2}|^(css|sc|jsx)-/.test(c)).slice(0, 2) : [];
          if (classes.length) part += '.' + classes.map(esc).join('.');
          const parent = node.parentElement;
          if (parent && Array.from(parent.children).filter(c => c.matches(part)).length > 1) {
            part += ':nth-of-type(' + (Array.from(parent.children).filter(c => c.tagName === node.tagName).indexOf(node) + 1) + ')';
          }
          parts.unshift(part);
          if (unique(parts.join(' > '))) break;
        }
        return parts.join(' > ');
      }

      /// Stable selectors first: id, test id, name, aria-label, placeholder, then a DOM path.
      function selectors(el) {
        const tag = el.tagName.toLowerCase();
        const out = [];
        const add = s => { if (s && !out.includes(s) && unique(s)) out.push(s); };
        if (el.id && !/\d{3,}/.test(el.id)) add('#' + esc(el.id));
        const test = el.getAttribute('data-testid'); if (test) add('[data-testid="' + esc(test) + '"]');
        const name = el.getAttribute('name'); if (name) add(attrSel(tag, 'name', name));
        const aria = el.getAttribute('aria-label'); if (aria) add(attrSel(tag, 'aria-label', aria));
        const ph = el.getAttribute('placeholder'); if (ph) add(attrSel(tag, 'placeholder', ph));
        if (tag === 'a' && el.getAttribute('href') && !/^javascript:/i.test(el.getAttribute('href'))) add(attrSel('a', 'href', el.getAttribute('href')));
        add(pathSelector(el));
        return out;
      }

      function nameOf(el) {
        const by = el.getAttribute('aria-labelledby');
        const labelled = by && by.split(/\s+/).map(id => document.getElementById(id)).filter(Boolean).map(n => n.textContent).join(' ');
        const forLabel = (el.id && document.querySelector('label[for="' + esc(el.id) + '"]')) ||
          (el.matches('input, select, textarea') && el.closest('label'));
        const name = el.getAttribute('aria-label') || labelled || el.getAttribute('alt') || el.getAttribute('title') ||
          (forLabel && forLabel.textContent) || el.getAttribute('placeholder') ||
          (el.matches('input[type=submit], input[type=button]') ? el.value : '') || el.textContent || '';
        return name.replace(/\s+/g, ' ').trim().slice(0, 120);
      }

      function isSecret(el) {
        const t = (el.getAttribute('type') || '').toLowerCase();
        const hint = [el.name, el.id, el.getAttribute('autocomplete')].join(' ');
        return t === 'password' || /pass|otp|one-time|cvv|cvc|card.?num|cc-num|ssn|secret|token/i.test(hint);
      }

      function visible(el) {
        const r = el.getBoundingClientRect();
        const cs = getComputedStyle(el);
        return r.width > 0 && r.height > 0 && cs.visibility !== 'hidden' && cs.display !== 'none';
      }

      /// Exactly one element for a target, or an error naming why not.
      function resolve(target) {
        const tried = [target.selector].concat(target.fallbacks || []);
        for (const sel of tried) {
          let found;
          try { found = Array.from(document.querySelectorAll(sel)); } catch (_) { continue; }
          const shown = found.filter(visible);
          const pool = shown.length ? shown : found;
          if (pool.length === 1) return { el: pool[0], via: sel };
          if (pool.length > 1) return { error: 'ambiguous', detail: sel + ' matched ' + pool.length + ' elements' };
        }
        if (target.label) {
          const want = target.label.toLowerCase();
          const all = Array.from(document.querySelectorAll('a, button, input, select, textarea, [role=button], [role=link], label'))
            .filter(e => visible(e) && nameOf(e).toLowerCase() === want);
          if (all.length === 1) return { el: all[0], via: 'label' };
          if (all.length > 1) return { error: 'ambiguous', detail: 'label "' + target.label + '" matched ' + all.length + ' elements' };
        }
        return { error: 'not_found', detail: 'no element for ' + tried.join(' | ') };
      }

      function setValue(el, value) {
        el.focus();
        const proto = el.tagName === 'TEXTAREA' ? HTMLTextAreaElement.prototype
          : el.tagName === 'SELECT' ? HTMLSelectElement.prototype : HTMLInputElement.prototype;
        const setter = Object.getOwnPropertyDescriptor(proto, 'value').set;
        setter.call(el, value);
        el.dispatchEvent(new Event('input', { bubbles: true }));
        el.dispatchEvent(new Event('change', { bubbles: true }));
      }

      function readText(el) {
        if (el.matches('input, textarea, select')) return el.value;
        return (el.innerText || el.textContent || '').replace(/\s+/g, ' ').trim();
      }

      return { unique, selectors, nameOf, isSecret, visible, resolve, setValue, readText, pathSelector };
    })();
    """#

    /// Records clicks, typed values, menu choices and Enter presses. Never records a secret value.
    static let recorder = #"""
    (function () {
      if (window.__bsRecorder) return; window.__bsRecorder = true;
      const post = m => { try { window.webkit.messageHandlers.bsRecorder.postMessage(Object.assign({ url: location.href }, m)); } catch (_) {} };
      const bs = window.__bs;
      const lastPosted = new WeakMap();
      function describe(el) {
        const sels = bs.selectors(el);
        return { selector: sels[0] || null, fallbacks: sels.slice(1), label: bs.nameOf(el), tag: el.tagName.toLowerCase(),
                 inputType: (el.getAttribute('type') || '').toLowerCase() };
      }
      function postValue(el) {
        if (!el.matches('input, textarea, select')) return;
        const t = (el.getAttribute('type') || '').toLowerCase();
        if (['checkbox', 'radio', 'submit', 'button', 'file', 'hidden'].includes(t)) return;
        if (lastPosted.get(el) === el.value) return;
        lastPosted.set(el, el.value);
        const secret = bs.isSecret(el);
        post(Object.assign(describe(el), { type: el.tagName === 'SELECT' ? 'select' : 'fill', value: secret ? null : el.value, secret }));
      }
      document.addEventListener('change', e => postValue(e.target), true);
      document.addEventListener('blur', e => { if (e.target && e.target.matches && e.target.matches('input, textarea')) postValue(e.target); }, true);
      document.addEventListener('keydown', e => {
        if (e.key !== 'Enter' || !e.target.matches || !e.target.matches('input')) return;
        postValue(e.target);
        post(Object.assign(describe(e.target), { type: 'press', key: 'Enter' }));
      }, true);
      document.addEventListener('click', e => {
        const el = e.target.closest && e.target.closest('a, button, input[type=submit], input[type=button], input[type=checkbox], input[type=radio], [role=button], [role=link], [role=tab], [role=menuitem], summary, [onclick]');
        if (!el) return;
        // A click on a submit button commits typed values first.
        document.querySelectorAll('input, textarea').forEach(i => { if (i.form && i.form === el.form) postValue(i); });
        post(Object.assign(describe(el), { type: 'click' }));
      }, true);
    })();
    """#

    /// Hover outline plus click-to-pick, used to mark result fields. Dormant until `__bsPicker.start()`.
    static let picker = #"""
    (function () {
      if (window.__bsPicker) return;
      const bs = window.__bs;
      let box = null, current = null, on = false;
      function ensureBox() {
        if (box) return;
        box = document.createElement('div');
        box.style.cssText = 'position:fixed;pointer-events:none;z-index:2147483647;border:2px solid #76b900;background:rgba(118,185,0,.15);border-radius:3px;transition:all .05s';
        document.documentElement.appendChild(box);
      }
      function move(ev) {
        const el = document.elementFromPoint(ev.clientX, ev.clientY);
        if (!el || el === box) return;
        current = el;
        const r = el.getBoundingClientRect();
        Object.assign(box.style, { left: r.left + 'px', top: r.top + 'px', width: r.width + 'px', height: r.height + 'px', display: 'block' });
      }
      /// A list selector: the picked element's path with its last :nth-of-type dropped, when that matches siblings.
      function listSelector(el) {
        const path = bs.pathSelector(el);
        const general = path.replace(/:nth-of-type\(\d+\)(?!.*:nth-of-type)/, '');
        try { const n = document.querySelectorAll(general).length; if (general !== path && n > 1) return { selector: general, count: n }; } catch (_) {}
        return null;
      }
      function pick(ev) {
        ev.preventDefault(); ev.stopPropagation(); ev.stopImmediatePropagation();
        if (!current) return;
        const sels = bs.selectors(current);
        const list = listSelector(current);
        window.webkit.messageHandlers.bsPicker.postMessage({
          selector: sels[0] || bs.pathSelector(current), text: bs.readText(current).slice(0, 300),
          label: bs.nameOf(current), listSelector: list && list.selector, listCount: list ? list.count : 1 });
        stop();
      }
      function swallow(ev) { if (on) { ev.preventDefault(); ev.stopPropagation(); ev.stopImmediatePropagation(); } }
      function start() { ensureBox(); on = true; document.addEventListener('mousemove', move, true); document.addEventListener('click', pick, true);
        ['mousedown', 'mouseup', 'pointerdown', 'pointerup'].forEach(t => document.addEventListener(t, swallow, true)); }
      function stop() { on = false; if (box) box.style.display = 'none'; document.removeEventListener('mousemove', move, true);
        document.removeEventListener('click', pick, true); ['mousedown', 'mouseup', 'pointerdown', 'pointerup'].forEach(t => document.removeEventListener(t, swallow, true)); }
      window.__bsPicker = { start, stop };
    })();
    """#

    /// Page-as-MCP: a compact model of the page (readable text, forms, actions) with stable refs.
    static let describePage = #"""
    const bs = window.__bs;
    let n = 0;
    const ref = el => { if (!el.dataset.bsRef) el.dataset.bsRef = 'e' + (++n + Math.floor(Math.random() * 1e6)).toString(36); return el.dataset.bsRef; };
    const forms = Array.from(document.forms).filter(bs.visible).slice(0, 10).map(f => ({
      ref: ref(f), name: f.getAttribute('aria-label') || f.getAttribute('name') || f.id || '',
      fields: Array.from(f.querySelectorAll('input, select, textarea')).filter(e => e.type !== 'hidden' && bs.visible(e)).slice(0, 25).map(e => ({
        ref: ref(e), label: bs.nameOf(e), type: e.tagName === 'SELECT' ? 'select' : (e.getAttribute('type') || e.tagName.toLowerCase()),
        name: e.name || '', required: e.required, secret: bs.isSecret(e),
        options: e.tagName === 'SELECT' ? Array.from(e.options).slice(0, 30).map(o => o.text.trim()) : undefined })),
      submit: (() => { const s = f.querySelector('button[type=submit], input[type=submit], button:not([type])'); return s ? { ref: ref(s), label: bs.nameOf(s) } : null; })()
    }));
    const actions = Array.from(document.querySelectorAll('a[href], button, [role=button], [role=link], [role=tab]'))
      .filter(e => bs.visible(e) && !e.closest('form')).slice(0, 60)
      .map(e => ({ ref: ref(e), label: bs.nameOf(e), kind: e.tagName === 'A' ? 'link' : 'button', href: e.getAttribute('href') || undefined }))
      .filter(a => a.label);
    const main = document.querySelector('main, [role=main], article') || document.body;
    return { title: document.title, url: location.href, text: bs.readText(main).slice(0, maxText), forms, actions };
    """#

    /// Page-as-MCP: act on a ref from describePage.
    static let actOnRef = #"""
    const bs = window.__bs;
    const el = document.querySelector('[data-bs-ref="' + CSS.escape(ref) + '"]');
    if (!el) return { ok: false, error: 'not_found', detail: 'no element with ref ' + ref + '; call page_describe again' };
    if (op === 'fill' || op === 'select') { bs.setValue(el, value || ''); return { ok: true, detail: op + ' ' + bs.nameOf(el) }; }
    if (op === 'submit') { const f = el.form || el.closest('form') || el; if (f.requestSubmit) f.requestSubmit(); else f.submit(); return { ok: true, detail: 'submitted' }; }
    el.scrollIntoView({ block: 'center' });
    el.click();
    return { ok: true, detail: 'clicked ' + bs.nameOf(el) };
    """#

    /// One executor step against the current page. Arguments: step (object), value (string|null).
    static let runStep = #"""
    const bs = window.__bs;
    const deadline = Date.now() + (step.timeoutMs || 8000);
    let found;
    while (true) {
      found = bs.resolve(step.target);
      if (found.el || found.error === 'ambiguous' || Date.now() > deadline) break;
      await new Promise(r => setTimeout(r, 150));
    }
    if (!found.el) return { ok: false, error: found.error, detail: found.detail };
    const el = found.el;
    el.scrollIntoView({ block: 'center' });
    switch (step.kind) {
      case 'fill': case 'select': bs.setValue(el, value || ''); break;
      case 'click': el.click(); break;
      case 'press': {
        const opts = { key: step.key, code: step.key, keyCode: step.key === 'Enter' ? 13 : 0, bubbles: true, cancelable: true };
        const go = el.dispatchEvent(new KeyboardEvent('keydown', opts));
        el.dispatchEvent(new KeyboardEvent('keyup', opts));
        if (go && step.key === 'Enter' && el.form) { if (el.form.requestSubmit) el.form.requestSubmit(); else el.form.submit(); }
        break;
      }
      case 'waitFor': break;
    }
    return { ok: true, via: found.via, label: bs.nameOf(el) };
    """#

    /// Reads outputs. Arguments: outputs ([{name, selector, many}]), timeoutMs.
    static let extract = #"""
    const bs = window.__bs;
    const deadline = Date.now() + (timeoutMs || 8000);
    const result = {};
    for (const o of outputs) {
      let value = o.many ? [] : null;
      while (true) {
        let els = [];
        try { els = Array.from(document.querySelectorAll(o.selector)); } catch (_) {}
        if (o.many && els.length) { value = els.map(bs.readText).filter(Boolean); break; }
        if (!o.many && els.length) { value = bs.readText(els[0]); if (value) break; }
        if (Date.now() > deadline) break;
        await new Promise(r => setTimeout(r, 150));
      }
      result[o.name] = value;
    }
    const loginWall = !!document.querySelector('input[type=password]');
    return { outputs: result, url: location.href, title: document.title, loginWall };
    """#

    static func userScripts() -> [WKUserScript] {
        [
            WKUserScript(source: common, injectionTime: .atDocumentStart, forMainFrameOnly: true, in: world),
            WKUserScript(source: recorder, injectionTime: .atDocumentStart, forMainFrameOnly: true, in: world),
            WKUserScript(source: picker, injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: world),
        ]
    }
}
