import * as fs from 'node:fs';
import * as path from 'node:path';
import * as crypto from 'node:crypto';
import { localContextDir } from './paths.js';

export type FactType =
  | 'gotcha'
  | 'debug'
  | 'security'
  | 'decision'
  | 'endpoint'
  | 'auth'
  | 'component'
  | 'note';

export interface SaveResult {
  saved: boolean;
  file: string;
  reason?: string;
}

/** Routing-Tabelle laut CLAUDE.md Writeback-Protokoll. */
const ROUTE: Record<FactType, string> = {
  gotcha: '_gotchas.md',
  debug: 'debug_patterns.md',
  security: 'security.md',
  decision: 'decisions.md',
  endpoint: path.join('backend', 'endpoints.md'),
  auth: path.join('backend', 'auth.md'),
  component: path.join('frontend', 'components.md'),
  note: '_temp_notes.md',
};

function contentHash(s: string): string {
  return crypto.createHash('md5').update(s.trim()).digest('hex').slice(0, 12);
}

/**
 * Schreibt einen Fakt in die typgerechte Markdown-Datei. Dedup über
 * Content-Hash-Marker (W1-Muster): identischer Inhalt wird nie doppelt
 * angehängt.
 */
export function saveFact(
  root: string,
  type: FactType,
  content: string,
  priority: 1 | 2 | 3 = 2,
): SaveResult {
  const rel = ROUTE[type] ?? ROUTE.note;
  const dest = path.join(localContextDir(root), rel);
  const hash = contentHash(content);
  const marker = `<!-- hash:${hash} -->`;

  let existing = '';
  try {
    existing = fs.readFileSync(dest, 'utf8');
  } catch {
    // Datei existiert noch nicht
  }

  if (existing.includes(marker)) {
    return { saved: false, file: dest, reason: 'duplicate' };
  }

  const stamp = new Date().toISOString().slice(0, 10);
  const usesPriority = type === 'gotcha' || type === 'debug' || type === 'security';
  const entry = usesPriority
    ? `\n- ${content.trim()}  (P: ${priority}, ${stamp}) ${marker}\n`
    : `\n- ${content.trim()}  (${stamp}) ${marker}\n`;

  try {
    fs.mkdirSync(path.dirname(dest), { recursive: true });
    fs.appendFileSync(dest, entry, 'utf8');
  } catch (err) {
    return { saved: false, file: dest, reason: `write-error: ${(err as Error).message}` };
  }
  return { saved: true, file: dest };
}
