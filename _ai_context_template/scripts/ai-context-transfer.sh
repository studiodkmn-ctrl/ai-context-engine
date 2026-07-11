#!/usr/bin/env bash
# =============================================================================
# ai-context-transfer.sh — Cross-Projekt-Intelligenz (v6.5 — Phase 7)
#
# Entsteht in einem Projekt eine neue Technik (neuer Gotcha/Pattern), prüft
# dieses Tool die anderen bekannten Projekte und legt einen Vorschlag in deren
# transfer-inbox, falls die Idee dort auch passen könnte.
#
# Du suchst nicht — das System erinnert dich (stille SessionStart-Zeile).
# Die inhaltliche Bewertung macht /ai-transfer; dieses Skript liefert nur
# die Kandidaten-Paare.
#
# Usage:
#   bash ai-context-transfer.sh --detect          # neue Chunks verteilen
#   bash ai-context-transfer.sh --inbox           # eigene Vorschläge zeigen
#   bash ai-context-transfer.sh --dismiss <id>    # Vorschlag verwerfen
#
# Voraussetzung: ≥2 Projekte im Store (~/.ai-context/projects/).
# =============================================================================
set -uo pipefail

# ---- Pro-Edition-Guard ----
if [ "$(cat "$HOME/.ai-context/edition" 2>/dev/null)" != "pro" ]; then
  echo "❌ ai-context-transfer.sh ist AI Context Pro." >&2
  echo "   Upgrade: bash ~/.ai-context/install.sh --pro" >&2
  exit 1
fi

CONTEXT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_DIR="$(cd "$CONTEXT_DIR/.." && pwd)"
PROJECT_NAME="$(basename "$PROJECT_DIR")"
PROJECTS_ROOT="$HOME/.ai-context/projects"
SELF_STORE="$PROJECTS_ROOT/$PROJECT_NAME"
REGISTRY="$CONTEXT_DIR/registry.yaml"
SEEN_FILE="$SELF_STORE/.transfer-seen"
INBOX="$SELF_STORE/transfer-inbox.yaml"


MODE="${1:-}"

case "$MODE" in

  # ---------------------------------------------------------------- detect
  --detect)
    [ ! -f "$REGISTRY" ] && exit 0
    [ ! -d "$PROJECTS_ROOT" ] && exit 0
    mkdir -p "$SELF_STORE"
    python3 - "$REGISTRY" "$PROJECTS_ROOT" "$PROJECT_NAME" "$SEEN_FILE" << 'PYEOF'
import sys, json, re, pathlib
from datetime import date

self_registry = pathlib.Path(sys.argv[1])
projects_root = pathlib.Path(sys.argv[2])
self_name     = sys.argv[3]
seen_file     = pathlib.Path(sys.argv[4])
today = date.today().isoformat()
KNOWLEDGE_TYPES = {'gotcha', 'debug', 'security', 'rule'}

def parse_registry(path):
    chunks, cur = [], {}
    if not path.exists():
        return chunks
    for line in path.read_text(encoding='utf-8', errors='ignore').splitlines():
        s = line.strip()
        if s.startswith('- id:'):
            if cur.get('id'):
                chunks.append(cur)
            cur = {'id': s.split(':', 1)[1].strip(), 'type': '', 'tags': [], 'file': ''}
        elif s.startswith('type:') and cur:
            cur['type'] = s.split(':', 1)[1].strip()
        elif s.startswith('tags:') and cur:
            raw = s.split(':', 1)[1].strip().strip('[]')
            cur['tags'] = [t.strip() for t in raw.split(',') if t.strip()]
        elif s.startswith('file:') and cur:
            cur['file'] = s.split(':', 1)[1].strip()
    if cur.get('id'):
        chunks.append(cur)
    return chunks

def meta_stack(meta_path):
    if not meta_path.exists():
        return set()
    try:
        m = json.loads(meta_path.read_text(encoding='utf-8'))
    except Exception:
        return set()
    return set(re.findall(r'[a-z][a-z0-9.]+', m.get('stack', '').lower()))

self_chunks = parse_registry(self_registry)
self_ids = {c['id'] for c in self_chunks}

seen = set()
if seen_file.exists():
    seen = {l.strip() for l in seen_file.read_text().splitlines() if l.strip()}

new_chunks = [c for c in self_chunks
              if c['id'] not in seen and c['type'] in KNOWLEDGE_TYPES]

# Seen-Set immer auf aktuellen Stand bringen
seen_file.parent.mkdir(parents=True, exist_ok=True)
seen_file.write_text('\n'.join(sorted(self_ids)) + '\n', encoding='utf-8')

if not new_chunks:
    print('TRANSFER: keine neuen Chunks')
    sys.exit(0)

self_stack = meta_stack(projects_root / self_name / '.meta.json')
others = [d for d in projects_root.iterdir()
          if d.is_dir() and d.name != self_name]
if not others:
    print('TRANSFER: keine anderen Projekte im Store')
    sys.exit(0)

distributed = 0
for other in others:
    o_stack = meta_stack(other / '.meta.json')
    # Stack-Overlap Pflicht (wenn beide Stacks bekannt)
    if self_stack and o_stack and not (self_stack & o_stack):
        continue
    o_chunks = parse_registry(other / '_ai_context' / 'registry.yaml')
    o_ids = {c['id'] for c in o_chunks}
    o_relevance = set(o_stack)
    for c in o_chunks:
        o_relevance.update(t.lower() for t in c['tags'])

    inbox = other / 'transfer-inbox.yaml'
    existing = inbox.read_text(encoding='utf-8') if inbox.exists() else ''
    dismissed_file = other / '.transfer-dismissed'
    dismissed = set()
    if dismissed_file.exists():
        dismissed = {l.strip() for l in dismissed_file.read_text().splitlines() if l.strip()}

    new_entries = []
    for c in new_chunks:
        sug_id = f"{c['id']}__from__{self_name}"
        if sug_id in dismissed or sug_id in existing or c['id'] in o_ids:
            continue
        ctags = {t.lower() for t in c['tags']}
        if not ctags:
            continue
        # Hat das Zielprojekt schon ein Äquivalent? (Tag-Jaccard ≥ 0.5)
        equiv = False
        for oc in o_chunks:
            octags = {t.lower() for t in oc['tags']}
            if octags and len(ctags & octags) / len(ctags | octags) >= 0.5:
                equiv = True
                break
        if equiv:
            continue
        # Relevanz: Thema im Zielprojekt überhaupt präsent?
        if not (ctags & o_relevance):
            continue
        new_entries.append((sug_id, c))

    if new_entries:
        if not existing:
            existing = ('# transfer-inbox.yaml — Cross-Projekt-Vorschläge\n'
                        '# Erzeugt von ai-context-transfer.sh --detect\n'
                        'suggestions:\n')
        block = []
        for sug_id, c in new_entries:
            block += [
                f'  - id: {sug_id}',
                f'    chunk: {c["id"]}',
                f'    from_project: {self_name}',
                f'    type: {c["type"]}',
                f'    file: {c["file"]}',
                f'    tags: [{", ".join(c["tags"])}]',
                f'    added: {today}',
            ]
        inbox.write_text(existing.rstrip() + '\n' + '\n'.join(block) + '\n',
                         encoding='utf-8')
        distributed += len(new_entries)
        print(f'TRANSFER: {len(new_entries)} Vorschlag/Vorschläge -> {other.name}')

print(f'TRANSFER: {distributed} Kandidat(en) verteilt')
PYEOF
    ;;

  # ----------------------------------------------------------------- inbox
  --inbox)
    if [ ! -f "$INBOX" ]; then
      echo "Keine Cross-Projekt-Vorschläge für $PROJECT_NAME."
      exit 0
    fi
    python3 - "$INBOX" "$PROJECT_NAME" << 'PYEOF'
import sys, pathlib

inbox = pathlib.Path(sys.argv[1])
proj = sys.argv[2]
text = inbox.read_text(encoding='utf-8', errors='ignore')

sugs, cur = [], {}
for line in text.splitlines():
    s = line.strip()
    if s.startswith('- id:'):
        if cur:
            sugs.append(cur)
        cur = {'id': s.split(':', 1)[1].strip()}
    elif cur and ':' in s and not s.startswith('#'):
        k, _, v = s.partition(':')
        cur[k.strip()] = v.strip()
if cur:
    sugs.append(cur)

if not sugs:
    print(f'Keine Cross-Projekt-Vorschläge für {proj}.')
    sys.exit(0)

print(f'\U0001f4a1 {len(sugs)} Cross-Projekt-Vorschlag/Vorschläge für {proj}:\n')
for s in sugs:
    print(f"  [{s['id']}]")
    print(f"    Chunk:   {s.get('chunk','?')} ({s.get('type','?')})")
    print(f"    Aus:     Projekt {s.get('from_project','?')}  ({s.get('file','?')})")
    print(f"    Tags:    {s.get('tags','')}")
    print(f"    Seit:    {s.get('added','?')}")
    print()
print('→ /ai-transfer liefert pro Vorschlag die volle Analyse.')
PYEOF
    ;;

  # --------------------------------------------------------------- dismiss
  --dismiss)
    SUG_ID="${2:-}"
    [ -z "$SUG_ID" ] && echo "Usage: ai-context-transfer.sh --dismiss <id>" >&2 && exit 1
    [ ! -f "$INBOX" ] && echo "Keine Inbox vorhanden." && exit 0
    python3 - "$INBOX" "$SELF_STORE/.transfer-dismissed" "$SUG_ID" << 'PYEOF'
import sys, pathlib

inbox = pathlib.Path(sys.argv[1])
dismissed_file = pathlib.Path(sys.argv[2])
target = sys.argv[3]

lines = inbox.read_text(encoding='utf-8', errors='ignore').splitlines()
out, skip, found = [], False, False
for line in lines:
    s = line.strip()
    if s.startswith('- id:'):
        skip = (s.split(':', 1)[1].strip() == target)
        if skip:
            found = True
            continue
    if skip and (line.startswith('    ') or not s):
        continue
    skip = False
    out.append(line)

inbox.write_text('\n'.join(out).rstrip() + '\n', encoding='utf-8')
prev = ''
if dismissed_file.exists():
    prev = dismissed_file.read_text(encoding='utf-8')
if target not in prev:
    dismissed_file.write_text(prev.rstrip() + '\n' + target + '\n', encoding='utf-8')
print('verworfen: ' + target if found else 'nicht gefunden: ' + target)
PYEOF
    ;;

  *)
    echo "Usage: ai-context-transfer.sh [--detect|--inbox|--dismiss <id>]"
    exit 1
    ;;
esac
