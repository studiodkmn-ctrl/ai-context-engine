import * as fs from 'node:fs';
import * as path from 'node:path';
import * as os from 'node:os';
import { localContextDir, crossProjectsDir } from './paths.js';

/**
 * locate() — der eine Griff für alle Schubladen (v7).
 *
 * Portierung der Scoring-Logik aus ai-symptom-router.sh (tokens/score_map/
 * score_chunk, 1:1 — siehe dort für die Bash/Python-Referenzimplementierung,
 * die jetzt diesen Code über den CLI-Wrapper aufruft statt selbst zu rechnen)
 * + Registry-Chunks (Frische-Status aus registry.yaml) + Invariants +
 * Impact-Graph + Symbol/Interface-Index + drawers.yaml-Routing.
 */

const STOP = new Set([
  'the', 'a', 'an', 'is', 'are', 'not', 'does', 'doesnt', 'do', 'my',
  'on', 'in', 'at', 'to', 'it', 'this', 'that', 'when', 'and', 'or',
  'der', 'die', 'das', 'ein', 'eine', 'und', 'oder', 'nicht', 'kein',
  'keine', 'ist', 'geht', 'mehr', 'wenn', 'beim', 'mir', 'ich', 'sich',
  'wird', 'war', 'aber', 'dann', 'noch', 'auch', 'reagiert', 'funktioniert',
  'works', 'work', 'broken', 'bug', 'fix', 'fehler', 'problem', 'kaputt',
]);

function tokens(text: string | undefined | null): string[] {
  const raw = (text || '').toLowerCase().match(/[a-zäöüßA-ZÄÖÜ0-9]{2,}/g) || [];
  return raw.filter(t => !STOP.has(t));
}

// ------------------------------------------------------------ synonyms.txt
function loadSynonyms(libDir: string): Map<string, string[]> {
  const out = new Map<string, string[]>();
  const p = path.join(libDir, 'synonyms.txt');
  let raw = '';
  try {
    raw = fs.readFileSync(p, 'utf8');
  } catch {
    return out;
  }
  for (const line of raw.split('\n')) {
    const l = line.trim();
    if (!l || l.startsWith('#') || !l.includes('=')) continue;
    const [word, aliases] = l.split('=', 2);
    const aliasList = aliases.split(',').map(a => a.trim().toLowerCase()).filter(Boolean);
    if (word.trim() && aliasList.length) out.set(word.trim().toLowerCase(), aliasList);
  }
  return out;
}

function expandQueryTokens(qTokens: Set<string>, synonyms: Map<string, string[]>): Set<string> {
  const expanded = new Set(qTokens);
  for (const [word, aliases] of synonyms) {
    if (qTokens.has(word) || aliases.some(a => qTokens.has(a))) {
      expanded.add(word);
      for (const a of aliases) expanded.add(a);
    }
  }
  return expanded;
}

// ------------------------------------------------------------ drawers.yaml
interface Drawer {
  id: string;
  index: string;
  globs: string[];
  keywords: string[];
}

function parseDrawers(contextDir: string): Drawer[] {
  const p = path.join(contextDir, 'drawers.yaml');
  let raw = '';
  try {
    raw = fs.readFileSync(p, 'utf8');
  } catch {
    return [];
  }
  const drawers: Drawer[] = [];
  let cur: Partial<Drawer> | null = null;
  for (const line of raw.split('\n')) {
    const s = line.trim();
    if (s.startsWith('- id:')) {
      if (cur && cur.id) drawers.push(cur as Drawer);
      cur = { id: s.slice(5).trim(), index: '', globs: [], keywords: [] };
    } else if (cur && s.startsWith('index:')) {
      cur.index = s.slice(6).trim();
    } else if (cur && s.startsWith('globs:')) {
      cur.globs = [...s.matchAll(/"([^"]+)"/g)].map(m => m[1]);
    } else if (cur && s.startsWith('keywords:')) {
      const raw2 = s.slice(9).trim().replace(/^\[|\]$/g, '');
      cur.keywords = raw2.split(',').map(k => k.trim().toLowerCase()).filter(Boolean);
    }
  }
  if (cur && cur.id) drawers.push(cur as Drawer);
  return drawers;
}

function globToRegExp(glob: string): RegExp {
  let re = '';
  for (let i = 0; i < glob.length; i++) {
    const c = glob[i];
    if (c === '*' && glob[i + 1] === '*') {
      re += '.*';
      i++;
    } else if (c === '*') {
      re += '[^/]*';
    } else if (c === '?') {
      re += '.';
    } else if ('.+^${}()|[]\\'.includes(c)) {
      re += '\\' + c;
    } else {
      re += c;
    }
  }
  return new RegExp('^' + re + '$');
}

function matchingDrawers(qTokens: Set<string>, drawers: Drawer[]): Drawer[] {
  return drawers.filter(d => d.keywords.some(k => qTokens.has(k)));
}

function fileInDrawer(file: string, drawer: Drawer): boolean {
  return drawer.globs.some(g => globToRegExp(g).test(file));
}

// ------------------------------------------------------------ interaction_map.md
interface MapRow {
  elem: string;
  loc: string;
  handler: string;
  store: string;
  endpoint: string;
}

function parseInteractionMap(contextDir: string): { rows: MapRow[]; state: 'ok' | 'missing' | 'empty' } {
  const fp = path.join(contextDir, '_interaction_map.md');
  let text: string;
  try {
    text = fs.readFileSync(fp, 'utf8');
  } catch {
    return { rows: [], state: 'missing' };
  }
  if (text.includes('leer bis zum ersten Scan')) return { rows: [], state: 'empty' };
  const rows: MapRow[] = [];
  for (const line of text.split('\n')) {
    if (!line.startsWith('|') || line.includes('---')) continue;
    const cells = line.trim().replace(/^\||\|$/g, '').split('|').map(c => c.trim());
    if (cells.length !== 5 || cells[0] === 'Element') continue;
    rows.push({
      elem: cells[0],
      loc: cells[1].replace(/`/g, ''),
      handler: cells[2].replace(/`/g, ''),
      store: cells[3],
      endpoint: cells[4],
    });
  }
  return { rows, state: 'ok' };
}

function scoreMapRow(row: MapRow, qTokens: Set<string>, qRaw: string): number {
  const label = row.elem.replace(/^[^`]*`|`.*$/g, '');
  const base = path.basename(row.loc.split(':')[0]).replace(/\.[^.]+$/, '');
  const hay = new Set(tokens([label, row.handler, base, row.endpoint, row.elem].join(' ')));
  let score = [...qTokens].filter(t => hay.has(t)).length;
  for (const qt of qTokens) {
    if (qt.length >= 4 && (label.toLowerCase().includes(qt) || row.handler.toLowerCase().includes(qt))) {
      score += 2;
    }
  }
  for (const kind of ['button', 'link', 'form', 'nav']) {
    if (qRaw.includes(kind) && row.elem.toLowerCase().includes(kind)) score += 1;
  }
  return score;
}

// ------------------------------------------------------------ registry.yaml (Chunks)
interface RegistryChunk {
  id: string;
  type: string;
  priority: number;
  file: string;
  tags: string[];
  seen: string;
  code_touched: string;
  status: string;
}

function parseRegistry(contextDir: string): RegistryChunk[] {
  const p = path.join(contextDir, 'registry.yaml');
  let raw = '';
  try {
    raw = fs.readFileSync(p, 'utf8');
  } catch {
    return [];
  }
  const chunks: RegistryChunk[] = [];
  let cur: Partial<RegistryChunk> | null = null;
  for (const line of raw.split('\n')) {
    const s = line.trim();
    if (s.startsWith('- id:')) {
      if (cur && cur.id) chunks.push(cur as RegistryChunk);
      cur = { id: s.slice(5).trim(), type: '', priority: 2, file: '', tags: [], seen: '', code_touched: '', status: '' };
    } else if (!cur) {
      continue;
    } else if (s.startsWith('type:')) {
      cur.type = s.slice(5).trim();
    } else if (s.startsWith('priority:')) {
      cur.priority = parseInt(s.slice(9).trim(), 10) || 2;
    } else if (s.startsWith('file:')) {
      cur.file = s.slice(5).trim();
    } else if (s.startsWith('tags:')) {
      cur.tags = s.slice(5).trim().replace(/^\[|\]$/g, '').split(',').map(t => t.trim()).filter(Boolean);
    } else if (s.startsWith('seen:')) {
      cur.seen = s.slice(5).trim();
    } else if (s.startsWith('code_touched:')) {
      cur.code_touched = s.slice(13).trim();
    } else if (s.startsWith('status:')) {
      cur.status = s.slice(7).trim();
    }
  }
  if (cur && cur.id) chunks.push(cur as RegistryChunk);
  return chunks;
}

/**
 * Fallback wenn registry.yaml (noch) nicht existiert — sie ist gitignored,
 * ein frischer Clone / ein nie gescanntes Projekt hat also keine. Die
 * Chunk-Anker in den Knowledge-.md-Dateien sind aber committet: direkt
 * daraus Pseudo-Chunks bauen (ohne tags/seen/status — die kommen erst
 * mit dem ersten `ai-context-registry.sh --scan`).
 *
 * Datei→Typ-Zuordnung kommt seit v9-a aus knowledge.manifest.yaml (einzige
 * Quelle der Wahrheit, siehe decisions.md#knowledge_manifest) statt aus
 * einer hier dupliziert gepflegten Liste. Fällt das Manifest weg (sehr
 * alte/fremde Installation), FALLBACK_KNOWLEDGE_FILES verhindert einen
 * Totalausfall.
 */
const FALLBACK_KNOWLEDGE_FILES: Array<[string, string]> = [
  ['_gotchas.md', 'gotcha'],
  ['debug_patterns.md', 'debug'],
  ['security.md', 'security'],
  ['testing.md', 'rule'],
  ['backend/auth.md', 'rule'],
  ['backend/database.md', 'rule'],
  ['backend/endpoints.md', 'endpoint'],
  ['frontend/components.md', 'component'],
  ['frontend/state.md', 'rule'],
  ['frontend/routing.md', 'rule'],
  ['architecture.md', 'arch'],
  ['decisions.md', 'arch'],
  ['playbooks.md', 'playbook'],
];

interface ManifestEntry {
  path: string;
  type: string;
}

/** Minimaler zeilenbasierter Parser, gleicher Stil wie parseDrawers. */
function parseKnowledgeManifest(contextDir: string): ManifestEntry[] {
  const p = path.join(contextDir, 'knowledge.manifest.yaml');
  let raw = '';
  try {
    raw = fs.readFileSync(p, 'utf8');
  } catch {
    return [];
  }
  const entries: ManifestEntry[] = [];
  let cur: Partial<ManifestEntry> | null = null;
  for (const line of raw.split('\n')) {
    const s = line.trim();
    if (s.startsWith('- path:')) {
      if (cur && cur.path) entries.push(cur as ManifestEntry);
      cur = { path: s.slice(7).trim(), type: '' };
    } else if (cur && s.startsWith('type:')) {
      cur.type = s.slice(5).trim();
    }
  }
  if (cur && cur.path) entries.push(cur as ManifestEntry);
  return entries;
}

function knowledgeFiles(contextDir: string): Array<[string, string]> {
  const fromManifest = parseKnowledgeManifest(contextDir);
  if (fromManifest.length > 0) {
    return fromManifest.map(e => [e.path, e.type]);
  }
  return FALLBACK_KNOWLEDGE_FILES;
}

function chunksFromMarkdownFallback(contextDir: string): RegistryChunk[] {
  const chunks: RegistryChunk[] = [];
  const anchorRe = /<!-- #(\w+) -->\n([\s\S]*?)<!-- \/\1 -->/g;
  for (const [relFile, type] of knowledgeFiles(contextDir)) {
    let content: string;
    try {
      content = fs.readFileSync(path.join(contextDir, relFile), 'utf8');
    } catch {
      continue;
    }
    for (const m of content.matchAll(anchorRe)) {
      const id = m[1];
      if (id.startsWith('_') || id.toLowerCase() === 'template') continue;
      const pm = m[2].match(/\nP:\s*([123])/);
      chunks.push({
        id, type,
        priority: pm ? parseInt(pm[1], 10) : 2,
        file: relFile, tags: [], seen: '', code_touched: '', status: '',
      });
    }
  }
  return chunks;
}

function extractChunkBody(contextDir: string, file: string, id: string): string | null {
  const fp = path.join(contextDir, file);
  let content: string;
  try {
    content = fs.readFileSync(fp, 'utf8');
  } catch {
    return null;
  }
  const re = new RegExp(`<!-- #${escapeRe(id)} -->\\n([\\s\\S]*?)<!-- /${escapeRe(id)} -->`);
  const m = content.match(re);
  return m ? m[1].trim() : null;
}

function escapeRe(s: string): string {
  return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function symptomLine(body: string): string {
  const m = body.match(/\n\?\s*([^\n]+)/);
  return m ? m[1].trim() : '';
}

/** Plausible Dateipfade aus der `@ file1, file2, ...`-Zeile (siehe ctx.py parse_at_files). */
function extractAtFiles(body: string): string[] {
  const m = body.match(/\n@\s*([^\n]+)/);
  if (!m) return [];
  return m[1].split(',').map(f => f.trim()).filter(f => f && (f.includes('/') || /\.\w{1,4}$/.test(f)));
}

function scoreChunk(body: string, qTokens: Set<string>): number {
  const hay = new Set(tokens(body));
  let score = [...qTokens].filter(t => hay.has(t)).length;
  const sym = new Set(tokens(symptomLine(body)));
  score += 3 * [...qTokens].filter(t => sym.has(t)).length;
  return score;
}

function freshnessNote(chunk: RegistryChunk): string {
  if (chunk.status === 'orphan') return ' — ⚠ VERWAIST (Code-Datei fehlt)';
  if (chunk.status === 'check') return ` — ⚠ PRÜFEN (Code neuer als seen ${chunk.seen})`;
  return chunk.seen ? ` — ✅ fresh (${chunk.seen})` : '';
}

// ------------------------------------------------------------ _idx/symbols.md
interface SymbolHit {
  name: string;
  file: string;
  line: string;
  args: string;
  score: number;
}

function parseSymbols(contextDir: string, qTokens: Set<string>): SymbolHit[] {
  const fp = path.join(contextDir, '_idx', 'symbols.md');
  let text: string;
  try {
    text = fs.readFileSync(fp, 'utf8');
  } catch {
    return [];
  }
  const hits: SymbolHit[] = [];
  let currentFile = '';
  for (const line of text.split('\n')) {
    const headerM = line.match(/^## `([^`]+)`/);
    if (headerM) {
      currentFile = headerM[1];
      continue;
    }
    const symM = line.match(/^\s{2}(\S+)\s+(L\d+)\s*(.*)$/);
    if (!symM || !currentFile) continue;
    const [, name, lineNo, rest] = symM;
    const hay = new Set(tokens([name, currentFile, rest].join(' ')));
    const score = [...qTokens].filter(t => hay.has(t)).length +
      (qTokens.has(name.toLowerCase()) ? 3 : 0);
    if (score > 0) hits.push({ name, file: currentFile, line: lineNo, args: rest.trim(), score });
  }
  return hits.sort((a, b) => b.score - a.score);
}

// ------------------------------------------------------------ _idx/interfaces.md
interface InterfaceHit {
  name: string;
  file: string;
  line: string;
  fields: string;
  score: number;
}

function parseInterfaces(contextDir: string, qTokens: Set<string>): InterfaceHit[] {
  const fp = path.join(contextDir, '_idx', 'interfaces.md');
  let text: string;
  try {
    text = fs.readFileSync(fp, 'utf8');
  } catch {
    return [];
  }
  const hits: InterfaceHit[] = [];
  for (const line of text.split('\n')) {
    const m = line.match(/^(\S+)\s+(\S+):(\d+)\s+(.*)$/);
    if (!m) continue;
    const [, name, file, lineNo, fields] = m;
    const hay = new Set(tokens([name, fields].join(' ')));
    const score = [...qTokens].filter(t => hay.has(t)).length +
      (qTokens.has(name.toLowerCase()) ? 3 : 0);
    if (score > 0) hits.push({ name, file, line: lineNo, fields, score });
  }
  return hits.sort((a, b) => b.score - a.score);
}

// ------------------------------------------------------------ invariants.yaml
interface Invariant {
  id: string;
  level: string;
  rule: string;
  scope: string;
}

function parseInvariants(contextDir: string): Invariant[] {
  const p = path.join(contextDir, 'invariants.yaml');
  let raw = '';
  try {
    raw = fs.readFileSync(p, 'utf8');
  } catch {
    return [];
  }
  const out: Invariant[] = [];
  let cur: Partial<Invariant> | null = null;
  for (const line of raw.split('\n')) {
    const s = line.trim();
    if (s.startsWith('- id:')) {
      if (cur && cur.id) out.push(cur as Invariant);
      cur = { id: s.slice(5).trim(), level: '', rule: '', scope: '' };
    } else if (!cur) {
      continue;
    } else if (s.startsWith('level:')) {
      cur.level = s.slice(6).trim();
    } else if (s.startsWith('rule:')) {
      cur.rule = s.slice(5).trim().replace(/^"|"$/g, '');
    } else if (s.startsWith('scope:')) {
      cur.scope = s.slice(6).trim().replace(/^"|"$/g, '');
    }
  }
  if (cur && cur.id) out.push(cur as Invariant);
  return out;
}

// ------------------------------------------------------------ impact-graph.yaml
function parseImpactGraph(graphPath: string): Map<string, string[]> {
  const out = new Map<string, string[]>();
  let raw = '';
  try {
    raw = fs.readFileSync(graphPath, 'utf8');
  } catch {
    return out;
  }
  let cur: string | null = null;
  for (const line of raw.split('\n')) {
    const s = line.trim();
    if (s.startsWith('- source:')) {
      cur = s.slice(9).trim();
    } else if (cur && s.startsWith('affects:')) {
      const raw2 = s.slice(8).trim().replace(/^\[|\]$/g, '');
      out.set(cur, raw2.split(',').map(x => x.trim()).filter(Boolean));
      cur = null;
    }
  }
  return out;
}

// ------------------------------------------------------------------ locate()
export interface LocateResult {
  markdown: string;
  hitCount: number;
  /** Empfohlene Lese-Reihenfolge — für ai-symptom-router.sh's __ROUTER__-Marker (/ai-fix Skill). */
  filesToRead: string[];
}

export async function locateQuery(query: string, root: string): Promise<LocateResult> {
  const contextDir = localContextDir(root);
  const libDir = path.join(contextDir, 'scripts', 'lib');
  const synonyms = loadSynonyms(libDir);
  const qRaw = query.toLowerCase();
  const qTokens = expandQueryTokens(new Set(tokens(query)), synonyms);

  const drawers = parseDrawers(contextDir);
  const hitDrawers = matchingDrawers(qTokens, drawers);

  // ---- (a) Interaction Map ----
  const { rows: mapRows, state: mapState } = parseInteractionMap(contextDir);
  const mapHits = mapRows
    .map(r => ({ row: r, score: scoreMapRow(r, qTokens, qRaw) }))
    .filter(h => h.score > 0)
    .sort((a, b) => b.score - a.score)
    .slice(0, 3);

  // ---- (b)+(c) Symbols + Interfaces ----
  const symbolHits = parseSymbols(contextDir, qTokens).slice(0, 3);
  const interfaceHits = parseInterfaces(contextDir, qTokens).slice(0, 3);

  // ---- (d) Registry Chunks (Gotchas/Debug/Security/Rules) ----
  // registry.yaml ist gitignored — frischer Clone / ungescanntes Projekt
  // fällt auf direktes Anker-Parsing der Knowledge-.md-Dateien zurück.
  let chunks = parseRegistry(contextDir);
  if (chunks.length === 0) {
    chunks = chunksFromMarkdownFallback(contextDir);
  }
  const chunkHits = chunks
    .map(c => {
      const body = extractChunkBody(contextDir, c.file, c.id) || '';
      return { chunk: c, body, score: scoreChunk(body, qTokens) };
    })
    .filter(h => h.score > 0)
    .sort((a, b) => b.score - a.score)
    .slice(0, 4);

  // Drawer-Boost: Treffer, deren Datei zu einer keyword-matchenden Schublade
  // gehört, werden nach oben priorisiert (stabiler Sort, daher Re-Sort mit Boost).
  const boost = (file: string): number =>
    hitDrawers.some(d => fileInDrawer(file, d)) ? 2 : 0;

  const anyHit = mapHits.length > 0 || symbolHits.length > 0 ||
    interfaceHits.length > 0 || chunkHits.length > 0;

  if (!anyHit) {
    const suggested = [...qTokens].slice(0, 3).join(' ');
    const drawerHint = hitDrawers.length
      ? `\nSchublade "${hitDrawers[0].id}" passt thematisch — direkt lesen: \`${hitDrawers[0].index}\``
      : '';
    return {
      hitCount: 0,
      filesToRead: [],
      markdown: `Kein Index-Treffer für "${query}".${drawerHint}\nVersuch: \`grep -rn "${suggested}" .\``,
    };
  }

  const lines: string[] = [];
  lines.push(`🔎 locate("${query}")`);
  lines.push('');

  // Bestes Ergebnis für Datei-basierte Folgeabschnitte (Gotchas/Invariants/Impact)
  let topFile = '';
  let topScore = -1;

  if (mapHits.length) {
    const top = mapHits[0];
    // row.elem enthält bereits ein Icon-Präfix (🔘 button / 📋 form / 🔗 link,
    // siehe ai-context-map.sh ICON-Map) — hier keins mehr voranstellen.
    lines.push(`${top.row.elem}  ${top.row.loc}`);
    lines.push(`   handler: ${top.row.handler}  |  state: ${top.row.store}  |  endpoint: ${top.row.endpoint}`);
    topFile = top.row.loc.split(':')[0];
    topScore = top.score + boost(topFile);
  }
  if (symbolHits.length && symbolHits[0].score + boost(symbolHits[0].file) > topScore) {
    const top = symbolHits[0];
    lines.push(`ƒ ${top.name}  ${top.file}:${top.line}  ${top.args}`.trimEnd());
    topFile = top.file;
    topScore = top.score + boost(topFile);
  } else if (symbolHits.length) {
    const top = symbolHits[0];
    lines.push(`ƒ ${top.name}  ${top.file}:${top.line}  ${top.args}`.trimEnd());
  }
  if (interfaceHits.length) {
    const top = interfaceHits[0];
    lines.push(`◇ ${top.name}  ${top.file}:${top.line}  { ${top.fields} }`);
    if (!topFile) topFile = top.file;
  }

  const playbookHits = chunkHits.filter(h => h.chunk.type === 'playbook');
  const knowledgeHits = chunkHits.filter(h => h.chunk.type !== 'playbook');

  if (playbookHits.length) {
    lines.push('');
    lines.push('📘 Passendes Playbook:');
    for (const h of playbookHits) {
      lines.push(`   ${h.chunk.id} [P${h.chunk.priority}]${freshnessNote(h.chunk)}`);
      if (!topFile) topFile = h.chunk.file;
    }
  }

  if (knowledgeHits.length) {
    lines.push('');
    lines.push('⚡ Verwandte Gotchas/Patterns:');
    for (const h of knowledgeHits) {
      lines.push(`   ${h.chunk.id} [P${h.chunk.priority}]${freshnessNote(h.chunk)}`);
      if (!topFile) topFile = h.chunk.file;
    }
  }

  // ---- (e) Invariants — scope-Glob gegen topFile ----
  if (topFile) {
    const invariants = parseInvariants(contextDir).filter(inv => globToRegExp(inv.scope).test(topFile));
    if (invariants.length) {
      lines.push('');
      lines.push('🔒 Invariante:');
      for (const inv of invariants.slice(0, 2)) {
        lines.push(`   ${inv.id} (${inv.level}) — ${inv.rule}`);
      }
    }
  }

  // ---- (f) Impact-Graph ----
  // ~/.ai-context/projects/<basename(root)>/impact-graph.yaml — dieselbe
  // basename()-Konvention wie ai-symptom-router.sh/ai-session-prep.sh, NICHT
  // getProjectId()s sha1-Hash (andere ID-Familie, für memory_search reserviert).
  if (topFile) {
    const graphPath = path.join(crossProjectsDir(), path.basename(root), 'impact-graph.yaml');
    const graph = parseImpactGraph(graphPath);
    const affects = graph.get(topFile);
    if (affects && affects.length) {
      lines.push('');
      lines.push(`🕸 Impact: ${topFile} ändert sich oft mit ${affects.slice(0, 4).join(', ')}`);
    }
  }

  // ---- (g) Hot Paths — nur wenn Query-Token im Pattern-Namen matcht ----
  const hotPathsFile = path.join(contextDir, 'hot_paths.md');
  try {
    const hp = fs.readFileSync(hotPathsFile, 'utf8');
    if (!hp.includes('[EXAMPLE_PATTERN')) {
      const headings = [...hp.matchAll(/^## ([^\n(]+)\(([^)]+)\)/gm)];
      for (const m of headings) {
        const headTokens = new Set(tokens(m[1]));
        if ([...qTokens].some(t => headTokens.has(t))) {
          lines.push('');
          lines.push(`🔥 Hot Path: ${m[1].trim()} (${m[2]})`);
          break;
        }
      }
    }
  } catch {
    // hot_paths.md optional
  }

  if (hitDrawers.length) {
    lines.push('');
    lines.push(`🗂 Schublade: ${hitDrawers.map(d => d.id).join(', ')} — Index: ${hitDrawers.map(d => d.index).join(', ')}`);
  }

  // Empfohlene Lese-Reihenfolge (analog to_read im alten ai-symptom-router.sh):
  // Map-Treffer zuerst, dann Symbol/Interface-Dateien, dann Chunk-@-Dateien.
  const filesToRead: string[] = [];
  const addFile = (f: string) => {
    if (f && !filesToRead.includes(f)) filesToRead.push(f);
  };
  for (const h of mapHits) addFile(h.row.loc.split(':')[0]);
  for (const h of symbolHits) addFile(h.file);
  for (const h of interfaceHits) addFile(h.file);
  for (const h of chunkHits) for (const f of extractAtFiles(h.body)) addFile(f);

  const markdown = lines.join('\n');
  return {
    hitCount: mapHits.length + symbolHits.length + interfaceHits.length + chunkHits.length,
    filesToRead: filesToRead.slice(0, 5),
    markdown,
  };
}

// re-export for locate-cli.ts / tools/locate.ts
export { tokens, loadSynonyms, expandQueryTokens };
