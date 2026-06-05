import * as fs from 'node:fs';
import * as path from 'node:path';
import { findProjectRoot, localContextDir } from '../lib/paths.js';

const MAX_CHARS = 8000;

export const sessionContextTool = {
  name: 'session_context',
  config: {
    title: 'Session-Kontext laden',
    description:
      'Gibt den kompakten Projektkontext zurück (was _SESSION.md enthält): Ziele, Regeln, ' +
      'aktueller Stand. Ruf das einmal am Anfang auf, statt dich durch viele Dateien zu lesen.',
    inputSchema: {},
  },
  async handler() {
    const root = findProjectRoot();
    const dir = localContextDir(root);

    const session = read(path.join(dir, '_SESSION.md'));
    if (session) {
      return text(clip(session));
    }

    // Fallback: aus Index + Quick-Facts zusammensetzen
    const parts: string[] = [];
    const index = read(path.join(dir, '_ai_index.md'));
    const facts = read(path.join(dir, '_quick_facts.md'));
    if (index) parts.push('## Index\n' + index);
    if (facts) parts.push('## Quick Facts\n' + facts);

    if (parts.length === 0) {
      return text(
        `Kein _ai_context-Kontext in ${root} gefunden. ` +
          `Lege _ai_context/ an oder starte ai-session-prep.sh.`,
      );
    }
    return text(clip(parts.join('\n\n')));
  },
};

function read(file: string): string | null {
  try {
    const s = fs.readFileSync(file, 'utf8').trim();
    return s || null;
  } catch {
    return null;
  }
}

function clip(s: string): string {
  return s.length > MAX_CHARS ? s.slice(0, MAX_CHARS) + '\n\n… (gekürzt)' : s;
}

function text(t: string) {
  return { content: [{ type: 'text' as const, text: t }] };
}
