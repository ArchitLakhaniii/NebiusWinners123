#!/usr/bin/env node
// stdio <-> Streamable HTTP bridge for MCP clients that only speak stdio (e.g. Hermes, older
// Claude Desktop). Reads newline-delimited JSON-RPC on stdin and forwards each message to the
// running BrowserSkills app. No dependencies. Licensed under GPL-3.0.
import { readFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';
import { createInterface } from 'node:readline';

const dir = process.env.BROWSERSKILLS_HOME || join(homedir(), 'Library', 'Application Support', 'BrowserSkills');
const url = process.env.BROWSERSKILLS_MCP_URL || `http://127.0.0.1:${process.env.BROWSERSKILLS_MCP_PORT || 4317}/mcp`;
const token = () => readFileSync(join(dir, 'mcp-token'), 'utf8').trim();

const rl = createInterface({ input: process.stdin });
let chain = Promise.resolve();
rl.on('line', (line) => {
  if (!line.trim()) return;
  chain = chain.then(() => forward(line));
});
rl.on('close', () => chain.then(() => process.exit(0)));

async function forward(line) {
  let id = null;
  try { id = JSON.parse(line).id ?? null; } catch { return reply({ jsonrpc: '2.0', id: null, error: { code: -32700, message: 'parse error' } }); }
  try {
    const res = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Accept: 'application/json, text/event-stream', Authorization: `Bearer ${token()}` },
      body: line,
    });
    if (res.status === 202) return;
    const text = await res.text();
    if (text) process.stdout.write(text.trim() + '\n');
  } catch (e) {
    if (id !== null) reply({ jsonrpc: '2.0', id, error: { code: -32000, message: `BrowserSkills is not reachable at ${url}: ${e.message}` } });
  }
}
function reply(msg) { process.stdout.write(JSON.stringify(msg) + '\n'); }
