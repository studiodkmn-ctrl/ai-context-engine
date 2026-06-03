#!/usr/bin/env bash
# =============================================================================
# ai-impact-learn.sh — Impact-Graph aus echten Fixes füttern (v6.5 — Phase 5)
#
# Merged eine gelernte Datei-Beziehung in den impact-graph.yaml des Projekts.
# Wird vom /ai-fix Skill nach einem erfolgreichen Verify-Loop aufgerufen:
# "Bug war in X, mitbehoben wurden Y und Z" → Edge source:X affects:[Y,Z].
#
# Format identisch zu ai-context-sync.sh — beide schreiben denselben Graph,
# den ai-session-prep.sh (Cascade) und ai-symptom-router.sh (Co-Change) lesen.
#
# Usage:
#   bash ai-impact-learn.sh <source-datei> <betroffene-datei> [weitere...]
# =============================================================================
set -euo pipefail

# ---- Pro-Edition-Guard ----
if [ "$(cat "$HOME/.ai-context/edition" 2>/dev/null)" != "pro" ]; then
  echo "❌ ai-impact-learn.sh ist AI Context Pro." >&2
  echo "   Upgrade: bash ~/.ai-context/install.sh --pro" >&2
  exit 1
fi

CONTEXT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_DIR="$(cd "$CONTEXT_DIR/.." && pwd)"
PROJECT_NAME="$(basename "$PROJECT_DIR")"
STORE_DIR="$HOME/.ai-context/projects/$PROJECT_NAME"
GRAPH="$STORE_DIR/impact-graph.yaml"

GREEN='\033[0;32m'; NC='\033[0m'

SOURCE="${1:-}"
shift || true
if [ -z "$SOURCE" ] || [ "$#" -eq 0 ]; then
  echo "Usage: ai-impact-learn.sh <source-datei> <betroffene-datei> [weitere...]" >&2
  exit 1
fi

mkdir -p "$STORE_DIR"

python3 - "$GRAPH" "$SOURCE" "$@" << 'PYEOF'
import sys, pathlib
from datetime import date

graph_p = pathlib.Path(sys.argv[1])
source = sys.argv[2].strip()
affected_new = [a.strip() for a in sys.argv[3:] if a.strip()]
today = date.today().isoformat()

# Bestehenden Graph parsen (Format wie ai-context-sync.sh)
edges = {}
if graph_p.exists():
    cur = None
    for line in graph_p.read_text(encoding='utf-8').splitlines():
        s = line.strip()
        if s.startswith('- source:'):
            cur = s.split(':', 1)[1].strip()
            edges[cur] = {'affects': set(), 'confidence': 0, 'last_seen': today}
        elif cur and s.startswith('affects:'):
            raw = s.split(':', 1)[1].strip().strip('[]')
            edges[cur]['affects'] = {x.strip() for x in raw.split(',') if x.strip()}
        elif cur and s.startswith('confidence:'):
            try: edges[cur]['confidence'] = int(s.split(':', 1)[1].strip())
            except ValueError: pass
        elif cur and s.startswith('last_seen:'):
            edges[cur]['last_seen'] = s.split(':', 1)[1].strip()

e = edges.setdefault(source, {'affects': set(), 'confidence': 0, 'last_seen': today})
before = len(e['affects'])
e['affects'] |= {a for a in affected_new if a and a != source}
e['confidence'] += 1
e['last_seen'] = today

out = ['# impact-graph.yaml — gelernte Datei-Beziehungen',
       '# Auto-generiert von ai-context-sync.sh + ai-impact-learn.sh.',
       '# confidence: wie oft diese Beziehung beobachtet wurde.', '',
       'edges:']
for src in sorted(edges):
    ed = edges[src]
    out.append(f'  - source: {src}')
    out.append(f"    affects: [{', '.join(sorted(ed['affects']))}]")
    out.append(f"    confidence: {ed['confidence']}")
    out.append(f"    last_seen: {ed['last_seen']}")
graph_p.write_text('\n'.join(out) + '\n', encoding='utf-8')

added = len(e['affects']) - before
print(f"impact-graph: {source} -> {len(e['affects'])} Datei(en) "
      f"(+{added} neu, confidence {e['confidence']})")
PYEOF
echo -e "${GREEN}✅ Impact-Graph aktualisiert${NC}"
