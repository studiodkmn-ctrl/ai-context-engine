import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StdioClientTransport } from '@modelcontextprotocol/sdk/client/stdio.js';
import * as path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const serverPath = path.join(__dirname, '..', 'dist', 'server.js');
const projectRoot = process.argv[2] || process.cwd();

function pass(msg) { console.log(`  ✓ ${msg}`); }
function fail(msg) { console.error(`  ✗ ${msg}`); process.exitCode = 1; }

const transport = new StdioClientTransport({
  command: 'node',
  args: [serverPath],
  env: { ...process.env, AI_CONTEXT_ROOT: projectRoot },
});

const client = new Client({ name: 'smoke', version: '0.0.0' });
await client.connect(transport);
console.log(`MCP verbunden — Kontext: ${projectRoot}\n`);

// 1) tools/list → genau 4
const { tools } = await client.listTools();
const names = tools.map(t => t.name).sort();
console.log('Tools:', names.join(', '));
const expected = ['capture_from_diff', 'locate', 'memory_save', 'memory_search', 'session_context'];
if (JSON.stringify(names) === JSON.stringify(expected)) pass('genau 5 Tools registriert');
else fail(`falsche Tools: ${names.join(',')}`);

const callText = async (name, args = {}) => {
  const r = await client.callTool({ name, arguments: args });
  return r.content.map(c => c.text).join('\n');
};

// 2) session_context
const ctx = await callText('session_context');
console.log('\n[session_context]\n' + ctx.slice(0, 200) + (ctx.length > 200 ? ' …' : ''));
ctx.length > 0 ? pass('session_context liefert Inhalt') : fail('session_context leer');

// 3) memory_save → round-trip via memory_search
const marker = 'SMOKE-' + Date.now();
const saveRes = await callText('memory_save', {
  content: `Testfakt ${marker}: stdio MCP funktioniert`,
  type: 'note',
});
console.log('\n[memory_save] ' + saveRes);
saveRes.includes('Gespeichert') ? pass('memory_save schreibt') : fail('memory_save fehlgeschlagen');

// Dedup: zweites Mal identisch → nicht doppelt
const saveRes2 = await callText('memory_save', {
  content: `Testfakt ${marker}: stdio MCP funktioniert`,
  type: 'note',
});
saveRes2.includes('Schon vorhanden') ? pass('Dedup greift (kein Doppel-Write)') : fail('Dedup griff nicht: ' + saveRes2);

// 4) memory_search findet den eben gespeicherten Fakt
const searchRes = await callText('memory_search', { query: marker });
console.log('\n[memory_search ' + marker + ']\n' + searchRes.slice(0, 240));
searchRes.includes(marker) ? pass('memory_search findet gespeicherten Fakt') : fail('Round-trip fehlgeschlagen');

// 5) memory_search ohne Treffer → leer/graceful
const empty = await callText('memory_search', { query: 'zxqwvbnmplkjhgfdsa-unfindbar' });
empty.includes('Kein Treffer') ? pass('Leersuche graceful') : fail('Leersuche unerwartet: ' + empty);

// 5b) locate — findet einen Gotcha per Symptom-Match.
// Bewusst ein ENGINE-EIGENER P1-Chunk (P: 1 = "nie löschen") statt eines
// Demo-Chunks: der Test hing vorher an `prisma_singleton` aus dem Template
// und brach, sobald die Demo-Inhalte korrekt entfernt wurden (V10 R1).
const locateRes = await callText('locate', { query: 'hook laeuft fehlerfrei durch bewirkt aber nichts' });
console.log('\n[locate silent_noop]\n' + locateRes.slice(0, 240));
locateRes.includes('silent_noop_needs_effect_test')
  ? pass('locate findet silent_noop_needs_effect_test')
  : fail('locate fand silent_noop_needs_effect_test nicht: ' + locateRes);

// 6) capture_from_diff (nur Vorschlag-Modus, darf auch leer sein)
const cap = await callText('capture_from_diff', {});
console.log('\n[capture_from_diff]\n' + cap.slice(0, 200));
cap.length > 0 ? pass('capture_from_diff antwortet') : fail('capture_from_diff stumm');

await client.close();
console.log('\nFertig.');
