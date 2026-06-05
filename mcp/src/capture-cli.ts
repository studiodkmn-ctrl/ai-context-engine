#!/usr/bin/env node
/**
 * Schlanke CLI für den post-commit-Hook: ruft dieselbe Capture-Logik wie das
 * MCP-Tool auf, aber ohne Protokoll-Overhead. Schreibt direkt ins Gedächtnis.
 *
 * Aufruf:  node capture-cli.js [--apply] [range]
 * Default ohne --apply: nur Vorschläge nach stderr (greift nie in Dateien ein).
 */
import { captureFromDiffTool } from './tools/capture_from_diff.js';

async function main(): Promise<void> {
  const args = process.argv.slice(2);
  const apply = args.includes('--apply');
  const range = args.find(a => !a.startsWith('--'));

  const res = await captureFromDiffTool.handler({ apply, range });
  const text = res.content.map(c => c.text).join('\n');
  // Hook-Ausgabe geht nach stderr, damit nichts versehentlich Pipes verschmutzt.
  process.stderr.write(text + '\n');
}

main().catch(err => {
  process.stderr.write(`capture-cli Fehler: ${err?.message || err}\n`);
  // Hook darf nie den Commit-Flow brechen.
  process.exit(0);
});
