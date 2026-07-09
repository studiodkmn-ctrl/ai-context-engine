import { z } from 'zod';
import { execFileSync } from 'node:child_process';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { findProjectRoot, localContextDir } from '../lib/paths.js';
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

    const intentSuggestion = readCommitIntent(root);
    const suggestions = [
      ...analyze(diff),
      ...detectGaps(diff, root),
      ...checkInvariants(diff, root),
      ...(intentSuggestion ? [intentSuggestion] : []),
    ];
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

    // TODO / FIXME / HACK → Gotcha (nur Code — TODOs in Doku sind Prosa, kein Schulden-Marker)
    const todo = isCode && /\b(TODO|FIXME|HACK|XXX)\b[:\s]*(.+)/.exec(line);
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

// ── Gap-Detection ────────────────────────────────────────────────────────────

function extractChangedFiles(diff: string): Set<string> {
  const files = new Set<string>();
  for (const line of diff.split('\n')) {
    if (line.startsWith('+++ b/')) files.add(line.slice(6).trim());
  }
  return files;
}

function loadImpactGraph(root: string): Map<string, string[]> {
  const projectName = path.basename(root);
  const graphPath = path.join(os.homedir(), '.ai-context', 'projects', projectName, 'impact-graph.yaml');
  const graph = new Map<string, string[]>();
  try {
    const content = fs.readFileSync(graphPath, 'utf8');
    let currentSource = '';
    for (const line of content.split('\n')) {
      const src = /^\s*-\s*source:\s*(.+)/.exec(line);
      if (src) { currentSource = src[1].trim(); continue; }
      const aff = /^\s*affects:\s*\[(.+)\]/.exec(line);
      if (aff && currentSource) {
        graph.set(currentSource, aff[1].split(',').map(s => s.trim()).filter(Boolean));
        currentSource = '';
      }
    }
  } catch { /* kein Graph vorhanden */ }
  return graph;
}

/** Vergleicht geänderte Dateien gegen den Impact Graph und meldet fehlende Co-Changes. */
function detectGaps(diff: string, root: string): Suggestion[] {
  const graph = loadImpactGraph(root);
  if (graph.size === 0) return [];

  const changed = extractChangedFiles(diff);
  const warnings: Suggestion[] = [];
  const seen = new Set<string>();

  for (const file of changed) {
    const expected = graph.get(file);
    if (!expected || expected.length < 2) continue;
    const missing = expected.filter(f => !changed.has(f));
    if (missing.length < 2) continue;
    const key = `gap|${file}`;
    if (seen.has(key)) continue;
    seen.add(key);
    warnings.push({
      type: 'gotcha',
      content: `Unvollständige Änderung? ${file} — typisch mitgeändert: ${missing.join(', ')} (${expected.length}× zusammen in Vergangenheit)`,
    });
  }
  return warnings;
}

// ── Invariant Layer ───────────────────────────────────────────────────────────

interface InvariantDep {
  type: 'file' | 'function' | 'endpoint';
  ref: string;
}

interface Invariant {
  id: string;
  level: 'hard' | 'soft' | 'hint';
  rule: string;
  scope: string;
  depends: InvariantDep[];
}

/** Lädt invariants.yaml aus dem _ai_context-Ordner. Kein Fehler wenn nicht vorhanden. */
function loadInvariants(root: string): Invariant[] {
  const invPath = path.join(localContextDir(root), 'invariants.yaml');
  const result: Invariant[] = [];
  try {
    const lines = fs.readFileSync(invPath, 'utf8').split('\n');
    let cur: Partial<Invariant> & { depends: InvariantDep[] } = { depends: [] };

    const flush = () => {
      if (cur.id) {
        result.push({ id: cur.id, level: cur.level ?? 'hint', rule: cur.rule ?? '', scope: cur.scope ?? '*', depends: cur.depends });
      }
      cur = { depends: [] };
    };

    for (const line of lines) {
      const id   = /^\s+-\s+id:\s*(.+)/.exec(line);
      if (id)   { flush(); cur.id = id[1].trim(); continue; }

      const lvl  = /^\s+level:\s*(\w+)/.exec(line);
      if (lvl)  { cur.level  = lvl[1].trim() as Invariant['level']; continue; }

      const rule = /^\s+rule:\s*"([^"]+)"/.exec(line);
      if (rule) { cur.rule   = rule[1]; continue; }

      const scp  = /^\s+scope:\s*"([^"]+)"/.exec(line);
      if (scp)  { cur.scope  = scp[1]; continue; }

      // depends: ["file1", "file2"]  (inline array format)
      const deps = /^\s+depends:\s*\[(.+)\]/.exec(line);
      if (deps) {
        const refs = [...deps[1].matchAll(/"([^"]+)"/g)].map(m => m[1]);
        for (const ref of refs) cur.depends.push({ type: 'file', ref });
      }
    }
    flush();
  } catch { /* invariants.yaml fehlt — kein Problem */ }
  return result;
}

/** Prüft ob geänderte Dateien Invarianten berühren und gibt Warnungen zurück. */
function checkInvariants(diff: string, root: string): Suggestion[] {
  const invariants = loadInvariants(root);
  if (invariants.length === 0) return [];

  const changed = extractChangedFiles(diff);
  const warnings: Suggestion[] = [];
  const seen = new Set<string>();

  for (const file of changed) {
    const base = path.basename(file);
    for (const inv of invariants) {
      if (seen.has(inv.id)) continue;
      const affected = inv.depends.some(d =>
        d.type === 'file' && (file.endsWith(d.ref) || d.ref.endsWith(base) || d.ref.includes(base))
      );
      if (!affected) continue;
      seen.add(inv.id);

      const factType: FactType = inv.level === 'hard' ? 'security' : 'gotcha';
      const badge = inv.level === 'hard' ? '⚠ INVARIANTE' : inv.level === 'soft' ? 'Invariante' : 'Hinweis';
      warnings.push({
        type: factType,
        content: `${badge} [${inv.id}] ${inv.rule}  (scope: ${inv.scope})`,
      });
    }
  }
  return warnings;
}

// ── Intent-Tagging ────────────────────────────────────────────────────────────

/** Liest den letzten Commit-Titel und speichert ihn als Intent wenn er bedeutsam ist. */
function readCommitIntent(root: string): Suggestion | null {
  try {
    const msg = execFileSync('git', ['log', '-1', '--format=%s'], {
      cwd: root,
      encoding: 'utf8',
      timeout: 5_000,
      stdio: ['ignore', 'pipe', 'ignore'],
    }).trim();
    if (!msg || msg.length < 10) return null;
    if (!/\b(add|feat|implement|refactor|fix|remove|migrate|upgrade|extract)\b/i.test(msg)) return null;
    return { type: 'note', content: `Intent: ${msg}` };
  } catch { return null; }
}

// ─────────────────────────────────────────────────────────────────────────────

function text(t: string) {
  return { content: [{ type: 'text' as const, text: t }] };
}
