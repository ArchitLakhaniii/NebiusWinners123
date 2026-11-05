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

const page = (title, body) => `<!doctype html><html><head><meta charset="utf-8"><title>${title === 'Northwind' ? 'Northwind' : esc(title) + ' · Northwind'}</title>
<style>:root{color-scheme:light;--ink:#1f3a5f;--text:#1a1a1c;--text2:#6b6b70;--line:#e7e5e1;--page:#fbfaf8}
body{font:15px/1.45 -apple-system,system-ui,sans-serif;margin:0;color:var(--text);background:var(--page)}
nav{display:flex;align-items:center;gap:28px;padding:0 36px;height:62px;border-bottom:1px solid var(--line)}
nav a{color:var(--text2);text-decoration:none;font-size:15px}nav a:hover{color:var(--text)}
nav a:first-child{color:var(--ink);font:400 26px/1 Georgia,"Times New Roman",serif;letter-spacing:-0.01em;margin-right:14px}
nav span{margin-left:auto;color:var(--text2);font-size:14px}
main{max-width:860px;margin:0 auto;padding:40px 36px 56px}h1{font-size:22px;font-weight:500;margin:0 0 6px}
.lede{color:var(--text2);margin:0 0 22px}label{display:block;color:var(--text);font-size:14px;margin-bottom:8px}
form{display:flex;gap:12px;flex-wrap:wrap;align-items:flex-end;margin:0 0 32px}form>div{display:flex;flex-direction:column}
input,select,button{font:inherit;padding:10px 14px;border:1px solid #d9d7d2;border-radius:7px;background:#fff;height:42px;box-sizing:border-box}
input{min-width:300px}input:focus,select:focus{outline:2px solid var(--ink);outline-offset:-1px}
button{background:var(--ink);color:#fff;border:0;font-weight:500;cursor:pointer;padding:0 18px}button:hover{background:#294a75}
.card{margin:8px 0 0}.eyebrow{color:var(--text2);font-size:14px;margin:0 0 4px}
.headline{font:400 48px/1.1 Georgia,"Times New Roman",serif;margin:0 0 22px;letter-spacing:-0.01em}
.facts{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,max-content));gap:28px}
.facts dt{color:var(--text2);font-size:14px;margin-bottom:4px}.facts dd{margin:0;font-size:17px}
table{border-collapse:collapse;width:100%}td,th{text-align:left;padding:12px 8px;border-bottom:1px solid var(--line)}th{color:var(--text2);font-weight:500;font-size:13px}
ul{padding-left:18px}li{margin:6px 0}a{color:var(--ink)}
.note{color:var(--text2);font-size:13px;margin-top:40px}</style></head>
<body><nav><a href="/">Northwind</a><a href="/orders">Orders</a><a href="/flights">Flights</a><a href="/inventory">Inventory</a><span>ops@northwind.example</span></nav>
<main><h1>${esc(title)}</h1>${body}<p class="note">Demo data changes every minute.</p></main></body></html>`;

const routes = {
  '/': () => page('Northwind', `<p class="lede">Three lookups people repeat every day. Do one twice in BrowserSkills and it offers to save it as a skill.</p>
    <ul><li><a href="/orders">Order status</a>: order number to status, carrier, ETA</li>
    <li><a href="/flights">Flight status</a>: airline and flight to state, gate</li>
    <li><a href="/inventory">Inventory search</a>: keyword to products with live price and stock</li></ul>`),
  '/orders': (q) => {
    const id = (q.get('order') || '').trim();
    const form = `<p class="lede">Enter an order number to see where it is.</p><form action="/orders" method="get"><div><label for="order">Order number</label>
      <input id="order" name="order" placeholder="e.g. A-1042" value="${esc(id)}" required></div><button type="submit">Look up</button></form>`;
    if (!id) return page('Order status', form);
    const o = order(id);
    return page('Order status', form + `<div class="card" id="order-result"><p class="eyebrow">Order <span id="order-id">${esc(o.id)}</span></p>
      <p class="headline" id="order-status">${o.status}</p><dl class="facts">
      <div><dt>Carrier</dt><dd id="order-carrier">${o.carrier}</dd></div><div><dt>Estimated delivery</dt><dd id="order-eta">${o.eta}</dd></div>
      <div><dt>Total</dt><dd id="order-total">${o.total}</dd></div></dl></div>`);
  },
  '/flights': (q) => {
    const airline = q.get('airline') || '', number = (q.get('number') || '').trim();
    const opts = ['NV', 'UA', 'DL', 'AA', 'BA'].map((a) => `<option value="${a}" ${a === airline ? 'selected' : ''}>${a}</option>`).join('');
    const form = `<p class="lede">Pick the airline and enter the flight number.</p><form action="/flights" method="get"><div><label for="airline">Airline</label><select id="airline" name="airline">${opts}</select></div>
      <div><label for="number">Flight number</label><input id="number" name="number" placeholder="e.g. 204" value="${esc(number)}" required></div>
      <button type="submit">Check flight</button></form>`;
    if (!number) return page('Flight status', form);
    const f = flight(airline, number);
    return page('Flight status', form + `<div class="card"><p class="eyebrow">Flight <span id="flight-name">${esc(f.flight)}</span></p>
      <p class="headline" id="flight-state">${f.state}</p><dl class="facts">
      <div><dt>Gate</dt><dd id="flight-gate">${f.gate}</dd></div><div><dt>Terminal</dt><dd id="flight-terminal">${f.terminal}</dd></div></dl></div>`);
  },
  '/inventory': (q) => {
    const term = (q.get('q') || '').trim();
    const form = `<p class="lede">Live price and stock for every product that matches.</p><form action="/inventory" method="get"><div><label for="q">Search products</label><input id="q" name="q" placeholder="e.g. RTX" value="${esc(term)}" required></div>
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
