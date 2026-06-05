import * as fs from 'node:fs';
import * as path from 'node:path';
import * as os from 'node:os';

/**
 * Findet die Projektwurzel: startet bei AI_CONTEXT_ROOT oder cwd und läuft
 * aufwärts, bis ein `_ai_context`-Ordner oder `.git` gefunden ist.
 */
export function findProjectRoot(start?: string): string {
  let dir = path.resolve(start || process.env.AI_CONTEXT_ROOT || process.cwd());
  const root = path.parse(dir).root;
  while (true) {
    if (fs.existsSync(path.join(dir, '_ai_context'))) return dir;
    if (fs.existsSync(path.join(dir, '.git'))) return dir;
    if (dir === root) break;
    dir = path.dirname(dir);
  }
  // Fallback: ursprüngliches cwd
  return path.resolve(start || process.cwd());
}

/** Pfad zum projektlokalen `_ai_context`-Ordner. */
export function localContextDir(root = findProjectRoot()): string {
  return path.join(root, '_ai_context');
}

/** Globaler AI-Context-Ordner (`~/.ai-context`). */
export function globalContextDir(): string {
  return path.join(os.homedir(), '.ai-context');
}

/** Cross-Projekt-Speicher: `~/.ai-context/projects/<id>/`. */
export function crossProjectsDir(): string {
  return path.join(globalContextDir(), 'projects');
}

/** Liefert alle vorhandenen Cross-Projekt-Kontextordner (außer dem aktuellen). */
export function crossProjectContextDirs(excludeId?: string): string[] {
  const base = crossProjectsDir();
  if (!fs.existsSync(base)) return [];
  const out: string[] = [];
  for (const entry of fs.readdirSync(base, { withFileTypes: true })) {
    if (!entry.isDirectory()) continue;
    if (excludeId && entry.name === excludeId) continue;
    const ctx = path.join(base, entry.name, '_ai_context');
    if (fs.existsSync(ctx)) out.push(ctx);
    else out.push(path.join(base, entry.name));
  }
  return out;
}
