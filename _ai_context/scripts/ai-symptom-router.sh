#!/usr/bin/env bash
# =============================================================================
# ai-symptom-router.sh — Symptom-Router (v6.5 — Phase 2)
#
# Nimmt eine Bug-Beschreibung und findet die wahrscheinlichste Ursache, OHNE
# die Codebase zu durchsuchen. Matcht gegen:
#   - _interaction_map.md   (welches Element -> Datei:Zeile -> Handler -> ...)
#   - debug_patterns.md     (bekannte Symptome + Fixes)
#   - _gotchas.md           (bekannte Fallen)
#
# Gibt gerankte Verdächtige + eine exakte Lese-Empfehlung aus. Wird vom
# /ai-fix Skill aufgerufen.
#
# Usage:
#   bash ai-symptom-router.sh "login button reagiert nicht"
# =============================================================================
set -euo pipefail

CONTEXT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_DIR="$(cd "$CONTEXT_DIR/.." && pwd)"
IMPACT_GRAPH="$HOME/.ai-context/projects/$(basename "$PROJECT_DIR")/impact-graph.yaml"

QUERY="$*"
if [ -z "$QUERY" ]; then
  echo "Usage: ai-symptom-router.sh \"<bug beschreibung>\"" >&2
  exit 1
fi

ROUTER_PY="$(mktemp -t aictx-router.XXXXXX.py)"
trap 'rm -f "$ROUTER_PY"' EXIT

cat > "$ROUTER_PY" << 'PYEOF'
import sys, re, pathlib

context_dir = pathlib.Path(sys.argv[1])
query = sys.argv[2]
graph_path = pathlib.Path(sys.argv[3]) if len(sys.argv) > 3 else None

STOP = {'the', 'a', 'an', 'is', 'are', 'not', 'does', 'doesnt', 'do', 'my',
        'on', 'in', 'at', 'to', 'it', 'this', 'that', 'when', 'and', 'or',
        'der', 'die', 'das', 'ein', 'eine', 'und', 'oder', 'nicht', 'kein',
        'keine', 'ist', 'geht', 'mehr', 'wenn', 'beim', 'mir', 'ich', 'sich',
        'wird', 'war', 'aber', 'dann', 'noch', 'auch', 'reagiert', 'funktioniert',
        'works', 'work', 'broken', 'bug', 'fix', 'fehler', 'problem', 'kaputt'}

def tokens(text):
    raw = re.findall(r'[a-zA-Z\xe4\xf6\xfc\xc4\xd6\xdc\xdf0-9]{2,}', (text or '').lower())
    return [t for t in raw if t not in STOP]

q_tokens = set(tokens(query))
q_raw = query.lower()

# ---------------------------------------------------------------- Map-Zeilen
def parse_map():
    fp = context_dir / '_interaction_map.md'
    rows = []
    if not fp.exists():
        return rows, 'missing'
    text = fp.read_text(encoding='utf-8', errors='ignore')
    if 'leer bis zum ersten Scan' in text:
        return rows, 'empty'
    for line in text.splitlines():
        if not line.startswith('|') or '---' in line:
            continue
        cells = [c.strip() for c in line.strip().strip('|').split('|')]
        if len(cells) != 5 or cells[0] in ('Element',):
            continue
        elem, loc, handler, store, endpoint = cells
        rows.append({
            'elem': elem, 'loc': loc.strip('`'), 'handler': handler.strip('`'),
            'store': store, 'endpoint': endpoint,
        })
    return rows, 'ok'

def score_map(row):
    label = re.sub(r'^[^`]*`|`.*$', '', row['elem'])  # Text zwischen Backticks
    base = pathlib.Path(row['loc'].split(':')[0]).stem
    hay_text = ' '.join([label, row['handler'], base, row['endpoint'], row['elem']])
    hay = set(tokens(hay_text))
    score = len(q_tokens & hay)
    # Substring-Bonus: Query-Wort steckt im Label/Handler
    for qt in q_tokens:
        if len(qt) >= 4 and (qt in label.lower() or qt in row['handler'].lower()):
            score += 2
    # Kind-Bonus: "button"/"link"/"form"/"nav" explizit genannt
    for kind in ('button', 'link', 'form', 'nav'):
        if kind in q_raw and kind in row['elem'].lower():
            score += 1
    return score

# ------------------------------------------------------- Knowledge-Chunks
def parse_chunks(filename):
    fp = context_dir / filename
    chunks = []
    if not fp.exists():
        return chunks
    text = fp.read_text(encoding='utf-8', errors='ignore')
    for block in re.findall(r'```\s*\n((?:ID:|RULE:)[\s\S]*?)```', text):
        idm = re.search(r'(?:ID:|RULE:)\s*(\S+)', block)
        pm = re.search(r'\nP:\s*([123])', block)
        symptom = ''
        sm = re.search(r'\n\?\s*([^\n]+)', block)
        if sm:
            symptom = sm.group(1).strip()
        files = ''
        fm = re.search(r'\n@\s*([^\n]+)', block)
        if fm:
            files = fm.group(1).strip()
        chunks.append({
            'id': idm.group(1) if idm else '?',
            'prio': pm.group(1) if pm else '2',
            'symptom': symptom, 'files': files, 'body': block,
        })
    return chunks

def score_chunk(chunk):
    hay = set(tokens(chunk['body']))
    score = len(q_tokens & hay)
    sym = set(tokens(chunk['symptom']))
    score += 3 * len(q_tokens & sym)          # Symptom-Zeile zählt dreifach
    return score

# --------------------------------------------------------------- Auswertung
map_rows, map_state = parse_map()
debug_chunks = parse_chunks('debug_patterns.md')
gotcha_chunks = parse_chunks('_gotchas.md')

map_hits = sorted(((score_map(r), r) for r in map_rows),
                  key=lambda x: -x[0])
map_hits = [(s, r) for s, r in map_hits if s > 0][:3]

debug_hits = sorted(((score_chunk(c), c) for c in debug_chunks),
                    key=lambda x: -x[0])
debug_hits = [(s, c) for s, c in debug_hits if s > 0][:3]

gotcha_hits = sorted(((score_chunk(c), c) for c in gotcha_chunks),
                     key=lambda x: -x[0])
gotcha_hits = [(s, c) for s, c in gotcha_hits if s > 0][:3]

print(f'\U0001f50e Symptom-Router — "{query}"')
print()

print('INTERACTION MAP:')
if map_state == 'missing':
    print('  (keine Map — erst `bash _ai_context/scripts/ai-context-map.sh` laufen lassen)')
elif map_state == 'empty':
    print('  (Map noch nicht gescannt)')
elif not map_hits:
    print('  (kein UI-Element passt — Symptom evtl. nicht UI-bezogen)')
else:
    for s, r in map_hits:
        print(f'  [score {s}] {r["elem"]}  ->  {r["loc"]}')
        print(f'            Handler: {r["handler"]} | Store: {r["store"]} '
              f'| Endpoint: {r["endpoint"]}')
print()

print('DEBUG PATTERNS:')
if not debug_hits:
    print('  (keine bekannten Patterns passen)')
else:
    for s, c in debug_hits:
        print(f'  [score {s}] ID: {c["id"]} (P{c["prio"]})'
              + (f' — ? {c["symptom"]}' if c['symptom'] else ''))
        if c['files']:
            print(f'            @ {c["files"]}')
if debug_hits and debug_hits[0][0] >= 3:
    print()
    print(f'TOP-FIX (bekanntes Pattern {debug_hits[0][1]["id"]} — direkt anwendbar):')
    print('```')
    print(debug_hits[0][1]['body'].strip())
    print('```')
print()

print('GOTCHAS:')
if not gotcha_hits:
    print('  (keine Treffer)')
else:
    for s, c in gotcha_hits:
        print(f'  [score {s}] ID: {c["id"]} (P{c["prio"]})'
              + (f' — {c["symptom"]}' if c['symptom'] else ''))
print()

# ------------------------------------------------- Lese-Empfehlung
# to_read: list[(file, line|None)] — Zeile durchreichen für Editor-Sprung
to_read = []
seen = set()
for s, r in map_hits:
    file_part, _, line_part = r['loc'].partition(':')
    line_no = int(line_part) if line_part.isdigit() else None
    if file_part and file_part not in seen:
        to_read.append((file_part, line_no))
        seen.add(file_part)
for s, c in debug_hits:
    for tok in re.split(r'[,\s]+', c['files']):
        tok = tok.strip()
        if not tok or '.' not in tok:
            continue
        file_part, _, line_part = tok.partition(':')
        line_no = int(line_part) if line_part.isdigit() else None
        if file_part and file_part not in seen:
            to_read.append((file_part, line_no))
            seen.add(file_part)

print('EMPFOHLEN ZU LESEN (in dieser Reihenfolge):')
if to_read:
    for file_part, line_no in to_read[:5]:
        if line_no is not None:
            print(f'  - {file_part}:{line_no}')
        else:
            print(f'  - {file_part}')
else:
    print('  - (kein eindeutiger Verdächtiger — _interaction_map.md manuell prüfen)')

# Co-Change aus Impact-Graph — was bei früheren Fixes mit-betroffen war
if graph_path and graph_path.exists() and to_read:
    g_edges = {}
    g_cur = None
    for gline in graph_path.read_text(encoding='utf-8', errors='ignore').splitlines():
        gs = gline.strip()
        if gs.startswith('- source:'):
            g_cur = gs.split(':', 1)[1].strip()
        elif g_cur and gs.startswith('affects:'):
            raw = gs.split(':', 1)[1].strip().strip('[]')
            g_edges[g_cur] = [x.strip() for x in raw.split(',') if x.strip()]
            g_cur = None
    cochange = [(f, g_edges[f]) for f, _ in to_read if g_edges.get(f)]
    if cochange:
        print()
        print('HÄUFIG MIT-BETROFFEN (gelernt aus früheren Fixes):')
        for f, affs in cochange:
            print(f'  {f}  ->  {", ".join(affs[:5])}')

# Maschinenlesbarer Marker für das Skill
print()
print('__ROUTER__:' + ('|'.join(f for f, _ in to_read[:5]) if to_read else 'none'))
PYEOF

python3 "$ROUTER_PY" "$CONTEXT_DIR" "$QUERY" "$IMPACT_GRAPH"
