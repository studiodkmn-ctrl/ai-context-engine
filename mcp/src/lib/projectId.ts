import * as fs from 'node:fs';
import * as path from 'node:path';
import { execFileSync } from 'node:child_process';
import * as crypto from 'node:crypto';
import { localContextDir } from './paths.js';

interface Meta {
  projectId: string;
  origin: string | null;
  createdAt: string;
}

/**
 * Stabile Projekt-Identität (W2): bevorzugt den git-Remote-`origin`, fällt auf
 * den absoluten Projektpfad zurück. Wird in `_ai_context/.meta.json` gecacht,
 * damit MCP-Server und Shell-Scripts dieselbe ID verwenden.
 */
export function getProjectId(root: string): string {
  const metaPath = path.join(localContextDir(root), '.meta.json');
  try {
    const cached = JSON.parse(fs.readFileSync(metaPath, 'utf8')) as Meta;
    if (cached.projectId) return cached.projectId;
  } catch {
    // keine/kaputte Meta — neu berechnen
  }

  const origin = readGitOrigin(root);
  const basis = origin || path.resolve(root);
  const projectId = crypto.createHash('sha1').update(basis).digest('hex').slice(0, 12);

  const meta: Meta = { projectId, origin, createdAt: new Date().toISOString() };
  try {
    fs.mkdirSync(path.dirname(metaPath), { recursive: true });
    fs.writeFileSync(metaPath, JSON.stringify(meta, null, 2) + '\n', 'utf8');
  } catch {
    // Schreibfehler ist nicht fatal — ID bleibt deterministisch
  }
  return projectId;
}

function readGitOrigin(root: string): string | null {
  try {
    const url = execFileSync('git', ['config', '--get', 'remote.origin.url'], {
      cwd: root,
      encoding: 'utf8',
      timeout: 5000,
      stdio: ['ignore', 'pipe', 'ignore'],
    }).trim();
    return url || null;
  } catch {
    return null;
  }
}
