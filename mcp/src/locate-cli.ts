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
  const args = process.argv.slice(2);
  // --strict (V10 R2): nur starke Treffer ausgeben. Genutzt vom
  // Prompt-Router, der bei JEDEM Prompt laeuft — dort ist ein schwacher
  // Treffer teurer (ungefragte Injektion) als gar keiner. Manuelle Aufrufe
  // und /ai-fix lassen das Flag weg und sehen weiterhin alles.
  const strict = args.includes('--strict');
  const query = args.filter(a => a !== '--strict').join(' ').trim();
  if (!query) {
    process.stderr.write('Usage: locate-cli.js [--strict] "<bug beschreibung>"\n');
    process.exit(1);
  }
  const root = findProjectRoot();
  const res = await locateQuery(query, root, { strongOnly: strict });

  if (strict && res.strength === 'weak') {
    process.stdout.write(`Kein Index-Treffer für "${query}".\n\n__ROUTER__:none\n`);
    return;
  }

  const marker = '__ROUTER__:' + (res.filesToRead.length ? res.filesToRead.join('|') : 'none');
  process.stdout.write(res.markdown + '\n\n' + marker + '\n');
}

main().catch(err => {
  process.stderr.write(`locate-cli Fehler: ${err?.message || err}\n`);
  process.exit(1);
});
