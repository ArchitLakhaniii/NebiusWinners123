#!/usr/bin/env node
// Demo portal for BrowserSkills: three read-only lookups whose answers change over time, so a
// cached workflow has to actually re-run to be right. No dependencies. Licensed under GPL-3.0.
import { createServer } from 'node:http';

const PORT = Number(process.env.PORT || 4318);
const minute = () => Math.floor(Date.now() / 60000);
const hash = (s) => [...String(s)].reduce((h, c) => (h * 31 + c.charCodeAt(0)) >>> 0, 7);
const esc = (s) => String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);

const STATUSES = ['Processing', 'Packed', 'Shipped', 'Out for delivery', 'Delivered'];
const CARRIERS = ['UPS', 'FedEx', 'DHL', 'USPS'];
const FLIGHT_STATES = ['On time', 'Boarding', 'Delayed 25 min', 'Departed', 'Delayed 1h 10m', 'Landed'];
const PRODUCTS = ['RTX 5090 Founders', 'Jetson Orin Nano', 'DGX Spark', 'H200 NVL', 'GB200 Superchip', 'RTX 5080', 'Jetson AGX Thor', 'RTX PRO 6000'];

function order(id) {
  const h = hash(id), step = (h + minute()) % STATUSES.length;
  const eta = new Date(Date.now() + ((h % 5) + 1) * 86400000).toDateString();
  return { id, status: STATUSES[step], carrier: CARRIERS[h % CARRIERS.length], eta, total: `$${(20 + (h % 480)).toFixed(2)}` };
}
function flight(airline, number) {
  const h = hash(airline + number);
  return { flight: `${airline} ${number}`, state: FLIGHT_STATES[(h + minute()) % FLIGHT_STATES.length], gate: `${'ABCDE'[h % 5]}${(h % 40) + 1}`, terminal: (h % 4) + 1 };
}
function inventory(q) {
  const m = minute();
  return PRODUCTS.filter((p) => p.toLowerCase().includes(q.toLowerCase())).map((p) => {
    const h = hash(p);
    return { name: p, price: `$${(((h % 3000) + 200) * (1 + ((m + h) % 7) / 100)).toFixed(2)}`, stock: (h + m * 3) % 50 };
  });
}

const page = (title, body) => `<!doctype html><html><head><meta charset="utf-8"><title>${esc(title)} · Acme Portal</title>
<style>body{font:15px -apple-system,system-ui,sans-serif;max-width:760px;margin:40px auto;padding:0 20px;color:#1d1d1f}
nav a{margin-right:16px;color:#76b900;font-weight:600;text-decoration:none}h1{font-size:26px}form{display:flex;gap:8px;flex-wrap:wrap;margin:16px 0}
input,select,button{font:inherit;padding:8px 10px;border:1px solid #ccc;border-radius:8px}button{background:#76b900;color:#fff;border:0;font-weight:600;cursor:pointer}
.card{border:1px solid #e5e5e5;border-radius:12px;padding:16px;margin:12px 0}dt{color:#666;font-size:13px}dd{margin:0 0 10px;font-size:17px;font-weight:600}
table{border-collapse:collapse;width:100%}td,th{text-align:left;padding:8px;border-bottom:1px solid #eee}</style></head>
<body><nav><a href="/">Acme Portal</a><a href="/orders">Order status</a><a href="/flights">Flight status</a><a href="/inventory">Inventory</a></nav>
<h1>${esc(title)}</h1>${body}<p style="color:#999;font-size:12px;margin-top:40px">Demo data changes every minute.</p></body></html>`;

const routes = {
  '/': () => page('Acme Portal', `<p>Three lookups people repeat every day. Do one twice in BrowserSkills and it will offer to cache it as a skill.</p>
    <ul><li><a href="/orders">Order status</a> — order number → status, carrier, ETA</li>
    <li><a href="/flights">Flight status</a> — airline + flight → state, gate</li>
    <li><a href="/inventory">Inventory search</a> — keyword → products with live price and stock</li></ul>`),
  '/orders': (q) => {
    const id = (q.get('order') || '').trim();
    const form = `<form action="/orders" method="get"><label for="order">Order number</label>
      <input id="order" name="order" placeholder="e.g. A-1042" value="${esc(id)}" required><button type="submit">Look up</button></form>`;
    if (!id) return page('Order status', form);
    const o = order(id);
    return page('Order status', form + `<div class="card" id="order-result"><dl>
      <dt>Order</dt><dd id="order-id">${esc(o.id)}</dd><dt>Status</dt><dd id="order-status">${o.status}</dd>
      <dt>Carrier</dt><dd id="order-carrier">${o.carrier}</dd><dt>Estimated delivery</dt><dd id="order-eta">${o.eta}</dd>
      <dt>Total</dt><dd id="order-total">${o.total}</dd></dl></div>`);
  },
  '/flights': (q) => {
    const airline = q.get('airline') || '', number = (q.get('number') || '').trim();
    const opts = ['NV', 'UA', 'DL', 'AA', 'BA'].map((a) => `<option value="${a}" ${a === airline ? 'selected' : ''}>${a}</option>`).join('');
    const form = `<form action="/flights" method="get"><label for="airline">Airline</label><select id="airline" name="airline">${opts}</select>
      <label for="number">Flight number</label><input id="number" name="number" placeholder="e.g. 204" value="${esc(number)}" required>
      <button type="submit">Check flight</button></form>`;
    if (!number) return page('Flight status', form);
    const f = flight(airline, number);
    return page('Flight status', form + `<div class="card"><dl><dt>Flight</dt><dd id="flight-name">${esc(f.flight)}</dd>
      <dt>Status</dt><dd id="flight-state">${f.state}</dd><dt>Gate</dt><dd id="flight-gate">${f.gate}</dd>
      <dt>Terminal</dt><dd id="flight-terminal">${f.terminal}</dd></dl></div>`);
  },
  '/inventory': (q) => {
    const term = (q.get('q') || '').trim();
    const form = `<form action="/inventory" method="get"><input name="q" aria-label="Search products" placeholder="Search products" value="${esc(term)}" required>
      <button type="submit">Search</button></form>`;
    if (!term) return page('Inventory', form);
    const rows = inventory(term);
    return page('Inventory', form + (rows.length ? `<table id="results"><thead><tr><th>Product</th><th>Price</th><th>In stock</th></tr></thead><tbody>
      ${rows.map((r) => `<tr class="result"><td class="name">${r.name}</td><td class="price">${r.price}</td><td class="stock">${r.stock}</td></tr>`).join('')}
      </tbody></table>` : `<p id="no-results">No products match “${esc(term)}”.</p>`));
  },
};

createServer((req, res) => {
  const u = new URL(req.url, `http://${req.headers.host}`);
  if (u.pathname === '/health') { res.writeHead(200, { 'Content-Type': 'application/json' }); return res.end('{"ok":true}'); }
  const route = routes[u.pathname];
  if (!route || req.method !== 'GET') { res.writeHead(404); return res.end('not found'); }
  res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store' });
  res.end(route(u.searchParams));
}).listen(PORT, '127.0.0.1', () => console.log(`demo portal on http://127.0.0.1:${PORT}`));
