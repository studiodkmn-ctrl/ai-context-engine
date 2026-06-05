import * as fs from 'node:fs';
import * as path from 'node:path';

export interface SearchHit {
  file: string;        // absoluter Pfad
  relFile: string;     // kurzer, anzeigbarer Pfad
  line: number;        // 1-basiert, Beginn des Blocks
  snippet: string;     // der gematchte Block (gekürzt)
  score: number;
  source: 'local' | 'cross';
  project?: string;    // bei cross: Projektordnername
}

const SKIP_DIRS = new Set(['node_modules', '.git', 'dist', 'out', 'scripts']);
const MAX_SNIPPET = 600;

/** Sammelt rekursiv alle Markdown-Dateien unterhalb von `dir`. */
function collectMarkdown(dir: string, acc: string[] = []): string[] {
  let entries: fs.Dirent[];
  try {
    entries = fs.readdirSync(dir, { withFileTypes: true });
  } catch {
    return acc;
  }
  for (const e of entries) {
    if (e.isDirectory()) {
      if (SKIP_DIRS.has(e.name)) continue;
      collectMarkdown(path.join(dir, e.name), acc);
    } else if (e.isFile() && e.name.endsWith('.md')) {
      acc.push(path.join(dir, e.name));
    }
  }
  return acc;
}

/** Zerlegt Markdown in Blöcke (an Überschriften und Leerzeilen) mit Startzeile. */
function splitBlocks(content: string): { text: string; line: number }[] {
  const lines = content.split('\n');
  const blocks: { text: string; line: number }[] = [];
  let cur: string[] = [];
  let startLine = 1;
  const flush = () => {
    const text = cur.join('\n').trim();
    if (text) blocks.push({ text, line: startLine });
    cur = [];
  };
  for (let i = 0; i < lines.length; i++) {
    const l = lines[i];
    const isHeading = /^#{1,6}\s/.test(l);
    if (isHeading || l.trim() === '') {
      flush();
      if (isHeading) {
        cur.push(l);
        startLine = i + 1;
        flush();
      }
      startLine = i + 2;
    } else {
      if (cur.length === 0) startLine = i + 1;
      cur.push(l);
    }
  }
  flush();
  return blocks;
}

function tokenize(q: string): string[] {
  return q
    .toLowerCase()
    .split(/[^\p{L}\p{N}_]+/u)
    .map(t => t.trim())
    .filter(t => t.length >= 2);
}

function scoreBlock(textLower: string, terms: string[]): number {
  let score = 0;
  for (const term of terms) {
    let idx = textLower.indexOf(term);
    while (idx !== -1) {
      score += 1;
      idx = textLower.indexOf(term, idx + term.length);
    }
  }
  return score;
}

interface Source {
  dir: string;
  kind: 'local' | 'cross';
  project?: string;
}

/**
 * Keyword-Suche über die Markdown-Dateien einer Menge von Kontextordnern.
 * Keine DB, kein RAG. Nichts gefunden → leeres Array (Agent fällt auf
 * normales Dateilesen zurück).
 */
export function searchContext(query: string, sources: Source[], limit = 6): SearchHit[] {
  const terms = tokenize(query);
  if (terms.length === 0) return [];

  const hits: SearchHit[] = [];
  for (const src of sources) {
    const files = collectMarkdown(src.dir);
    for (const file of files) {
      let content: string;
      try {
        content = fs.readFileSync(file, 'utf8');
      } catch {
        continue;
      }
      for (const block of splitBlocks(content)) {
        const score = scoreBlock(block.text.toLowerCase(), terms);
        if (score <= 0) continue;
        hits.push({
          file,
          relFile: path.relative(src.dir, file) || path.basename(file),
          line: block.line,
          snippet:
            block.text.length > MAX_SNIPPET
              ? block.text.slice(0, MAX_SNIPPET) + ' …'
              : block.text,
          score,
          source: src.kind,
          project: src.project,
        });
      }
    }
  }

  // Lokale Treffer bei Gleichstand bevorzugen.
  hits.sort((a, b) => b.score - a.score || (a.source === b.source ? 0 : a.source === 'local' ? -1 : 1));
  return hits.slice(0, limit);
}
