import { z } from 'zod';
import { execFileSync } from 'node:child_process';
import { findProjectRoot } from '../lib/paths.js';
import { saveFact, FactType } from '../lib/save.js';

interface Suggestion {
  type: FactType;
  content: string;
}

export const captureFromDiffTool = {
  name: 'capture_from_diff',
  config: {
    title: 'Wissen aus git-diff vorschlagen',
    description:
      'Liest den aktuellen git-diff und schlägt Erkenntnisse vor (neue Endpoints, Gotchas/TODOs, ' +
      'Entscheidungen). Default: nur Vorschläge. Mit apply=true werden sie direkt ins Gedächtnis ' +
      'geschrieben (memory_save, mit Dedup). Gedacht für den post-commit-Hook.',
    inputSchema: {
      apply: z.boolean().optional().describe('true = Vorschläge direkt speichern (Default false)'),
      range: z
        .string()
        .optional()
        .describe('git-Diff-Range, z. B. "HEAD~1..HEAD". Default: gestaged, sonst HEAD~1..HEAD'),
    },
  },
  async handler({ apply, range }: { apply?: boolean; range?: string }) {
    const root = findProjectRoot();
    const diff = readDiff(root, range);
    if (!diff) {
      return text('Kein git-diff verfügbar (kein Repo oder keine Änderungen).');
    }

    const suggestions = analyze(diff);
    if (suggestions.length === 0) {
      return text('Keine eindeutigen Erkenntnisse im Diff gefunden.');
    }

    if (!apply) {
      const lines = ['Vorschläge (apply=true zum Speichern):', ''];
      for (const s of suggestions) lines.push(`- [${s.type}] ${s.content}`);
      return text(lines.join('\n'));
    }

    const results: string[] = [];
    for (const s of suggestions) {
      const r = saveFact(root, s.type, s.content);
      results.push(`${r.saved ? '✓' : '–'} [${s.type}] ${s.content}`);
    }
    return text(['Gespeichert:', '', ...results].join('\n'));
  },
};

function readDiff(root: string, range?: string): string | null {
  const tryGit = (args: string[]): string | null => {
    try {
      const out = execFileSync('git', args, {
        cwd: root,
        encoding: 'utf8',
        timeout: 10_000,
        stdio: ['ignore', 'pipe', 'ignore'],
        maxBuffer: 8 * 1024 * 1024,
      });
      return out.trim() ? out : null;
    } catch {
      return null;
    }
  };

  if (range) return tryGit(['diff', range]);
  // bevorzugt gestagte Änderungen, sonst der letzte Commit
  return tryGit(['diff', '--cached']) ?? tryGit(['diff', 'HEAD~1..HEAD']);
}

/** Heuristiken über hinzugefügte (`+`) Diff-Zeilen. */
function analyze(diff: string): Suggestion[] {
  const out: Suggestion[] = [];
  const seen = new Set<string>();
  const push = (type: FactType, content: string) => {
    const key = type + '|' + content;
    if (seen.has(key)) return;
    seen.add(key);
    out.push({ type, content });
  };

  let currentFile = '';
  for (const raw of diff.split('\n')) {
    if (raw.startsWith('+++ b/')) {
      currentFile = raw.slice(6).trim();
      continue;
    }
    if (!raw.startsWith('+') || raw.startsWith('+++')) continue;
    const line = raw.slice(1).trim();
    if (!line) continue;

    // Code-Heuristiken nur in Code-Dateien — Doku (.md/.txt) erzeugt sonst Rauschen.
    const isCode = !/\.(md|markdown|txt|rst)$/i.test(currentFile);

    // HTTP-Endpoints
    const ep = isCode &&
      /\b(app|router)\.(get|post|put|patch|delete)\s*\(\s*['"`]([^'"`]+)['"`]/.exec(line);
    if (ep) {
      push('endpoint', `${ep[2].toUpperCase()} ${ep[3]}  (@ ${currentFile})`);
      continue;
    }

    // TODO / FIXME / HACK → Gotcha
    const todo = /\b(TODO|FIXME|HACK|XXX)\b[:\s]*(.+)/.exec(line);
    if (todo && todo[2]) {
      push('gotcha', `${todo[1]}: ${todo[2].trim()}  (@ ${currentFile})`);
      continue;
    }

    // Neue Umgebungsvariablen
    const env = isCode && /process\.env\.([A-Z][A-Z0-9_]{2,})/.exec(line);
    if (env) {
      push('note', `Env-Var benötigt: ${env[1]}  (@ ${currentFile})`);
      continue;
    }
  }
  return out.slice(0, 5);
}

function text(t: string) {
  return { content: [{ type: 'text' as const, text: t }] };
}
