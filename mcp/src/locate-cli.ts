#!/usr/bin/env node
/**
 * Schlanke CLI für ai-symptom-router.sh: ruft dieselbe locate()-Logik wie
 * das MCP-Tool auf, aber ohne Protokoll-Overhead.
 *
 * Hängt zusätzlich den __ROUTER__:<file1>|<file2>-Marker an (Rückwärts-
 * kompatibilität mit dem /ai-fix Skill, das ihn aus der alten
 * ai-symptom-router.sh-Ausgabe parst) — das MCP-Tool selbst (tools/locate.ts)
 * gibt nur die reine Markdown-Karte zurück, ohne diesen Marker.
 *
 * Aufruf: node locate-cli.js "<bug beschreibung>"
 */
import { findProjectRoot } from './lib/paths.js';
import { locateQuery } from './lib/locate.js';

async function main(): Promise<void> {
  const query = process.argv.slice(2).join(' ').trim();
  if (!query) {
    process.stderr.write('Usage: locate-cli.js "<bug beschreibung>"\n');
    process.exit(1);
  }
  const root = findProjectRoot();
  const res = await locateQuery(query, root);
  const marker = '__ROUTER__:' + (res.filesToRead.length ? res.filesToRead.join('|') : 'none');
  process.stdout.write(res.markdown + '\n\n' + marker + '\n');
}

main().catch(err => {
  process.stderr.write(`locate-cli Fehler: ${err?.message || err}\n`);
  process.exit(1);
});
