#!/usr/bin/env bash
# =============================================================================
# ai-context-sync.sh — Persistent Local Context Store (v5.1)
#
# Synchronisiert _ai_context/ → ~/.ai-context/projects/<projekt>/
# Ermöglicht: Cross-Interface (Chat/Code/Cowork), Cross-Projekt-Lernen
#
# Usage:
#   bash _ai_context/scripts/ai-context-sync.sh              # Sync zum Store
#   bash _ai_context/scripts/ai-context-sync.sh --restore    # Restore vom Store
#   bash _ai_context/scripts/ai-context-sync.sh --list       # Alle Projekte zeigen
#   bash _ai_context/scripts/ai-context-sync.sh --export     # _SESSION.md → Clipboard
#   bash _ai_context/scripts/ai-context-sync.sh --share-gotcha "ID: beschreibung"
# =============================================================================
set -euo pipefail

CONTEXT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_DIR="$(cd "$CONTEXT_DIR/.." && pwd)"
PROJECT_NAME="$(basename "$PROJECT_DIR")"

STORE_DIR="$HOME/.ai-context/projects/$PROJECT_NAME"
SHARED_DIR="$HOME/.ai-context/shared"
GLOBAL_GOTCHAS="$SHARED_DIR/gotchas_global.md"
GLOBAL_PATTERNS="$SHARED_DIR/patterns_global.md"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; RED='\033[0;31m'; NC='\033[0m'
TODAY=$(date +"%Y-%m-%d %H:%M")

MODE="${1:-sync}"

# ---- Ensure store exists ----
mkdir -p "$STORE_DIR"
mkdir -p "$SHARED_DIR"

# ---- Init global files if needed ----
init_global() {
  if [ ! -f "$GLOBAL_GOTCHAS" ]; then
    cat > "$GLOBAL_GOTCHAS" << 'EOF'
# 🌍 Globale Gotchas — Projektübergreifend
> Gotchas die in mehreren Projekten auftreten.
> Automatisch geteilt wenn mit `--share-gotcha` markiert.

EOF
  fi
  if [ ! -f "$GLOBAL_PATTERNS" ]; then
    cat > "$GLOBAL_PATTERNS" << 'EOF'
# 🌍 Globale Debug-Patterns — Projektübergreifend
> Patterns die in mehreren Projekten auftreten.

EOF
  fi
}

init_global

case "$MODE" in

  # ---- Sync: Projekt → Store ----
  sync|--sync)
    echo -e "${CYAN}🔄 Sync: $PROJECT_NAME → lokaler Store${NC}"

    # Sync all context files
    rsync -a --delete \
      --exclude='.context_hash' \
      --exclude='*.bak' \
      "$CONTEXT_DIR/" "$STORE_DIR/_ai_context/"

    # Store metadata
    cat > "$STORE_DIR/.meta.json" << EOF
{
  "project": "$PROJECT_NAME",
  "path": "$PROJECT_DIR",
  "synced": "$TODAY",
  "stack": "$(grep 'Stack:' "$CONTEXT_DIR/_quick_facts.md" 2>/dev/null | sed 's/.*: *//' || echo 'unknown')"
}
EOF

    # ---- Phase B: Handoff-Archive + Impact-Graph ----
    HANDOFF="$CONTEXT_DIR/HANDOFF.md"
    HANDOFFS_DIR="$STORE_DIR/handoffs"
    IMPACT_GRAPH="$STORE_DIR/impact-graph.yaml"
    QUICK="$CONTEXT_DIR/_quick_facts.md"

    if [ -f "$HANDOFF" ]; then
      mkdir -p "$HANDOFFS_DIR"
      python3 - "$HANDOFF" "$HANDOFFS_DIR" "$IMPACT_GRAPH" "$QUICK" 2>/dev/null << 'PYEOF' || true
import sys, re, hashlib, pathlib
from datetime import date

handoff_p, archive_dir, graph_p, quick_p = [pathlib.Path(p) for p in sys.argv[1:5]]

text = handoff_p.read_text(encoding='utf-8')
status_m = re.search(r'\*\*Status:\*\*\s*(\w+)', text)
status = status_m.group(1) if status_m else 'none'

# Skip wenn keine echte Übergabe (none/leer)
if status in ('none', '_none_'):
    sys.exit(0)

# Snapshot-Hash damit identische HANDOFFs nicht dupliziert werden
content_hash = hashlib.md5(text.encode()).hexdigest()[:8]
today = date.today().isoformat()
snap = archive_dir / f"{today}_{status}_{content_hash}.md"
if not snap.exists():
    snap.write_text(text, encoding='utf-8')
    print(f"  📦 HANDOFF archiviert: {snap.name}")

# Sektionen extrahieren
def section(heading):
    m = re.search(rf'## {re.escape(heading)}\s*\n([\s\S]*?)(?=\n## |\n---|\Z)', text)
    if not m: return ''
    c = re.sub(r'<!--[\s\S]*?-->', '', m.group(1))
    return '' if '[leer wenn nichts]' in c else c.strip()

globals_hit = section('🌐 Welche globalen Abhängigkeiten wurden berührt?')
changed_files = section('Geänderte Dateien')

def parse_files(blob):
    out = []
    for line in blob.splitlines():
        line = line.strip().lstrip('-').strip()
        if not line or line.startswith('['): continue
        m = re.match(r'`?([^\s`—\-]+\.\w+)`?', line)
        if m: out.append(m.group(1).strip())
    return out

globals_files = parse_files(globals_hit)
changed = [f for f in parse_files(changed_files) if f.endswith('.md')]

# Quick-Facts Impact-Map einlesen für Auto-Edges
qmap = {}
if quick_p.exists():
    qtext = quick_p.read_text(encoding='utf-8')
    for m in re.finditer(r'\|\s*`([^`]+)`\s*\|[^|]*\|\s*([^|]+)\|', qtext):
        contexts = [c.strip() for c in m.group(2).split(',') if '.md' in c]
        if contexts:
            qmap[m.group(1).strip()] = contexts

# Graph laden (oder neu)
edges = {}
if graph_p.exists():
    gtext = graph_p.read_text(encoding='utf-8')
    cur = None
    for line in gtext.splitlines():
        s = line.strip()
        if s.startswith('- source:'):
            cur = s.split(':', 1)[1].strip()
            edges[cur] = {'affects': set(), 'confidence': 0, 'last_seen': today}
        elif cur and s.startswith('affects:'):
            raw = s.split(':', 1)[1].strip().strip('[]')
            edges[cur]['affects'] = {x.strip() for x in raw.split(',') if x.strip()}
        elif cur and s.startswith('confidence:'):
            try: edges[cur]['confidence'] = int(s.split(':', 1)[1].strip())
            except: pass
        elif cur and s.startswith('last_seen:'):
            edges[cur]['last_seen'] = s.split(':', 1)[1].strip()

# Neue Edges aus diesem HANDOFF lernen
for src in globals_files:
    affected = set(qmap.get(src, [])) | set(changed)
    if not affected: continue
    e = edges.setdefault(src, {'affects': set(), 'confidence': 0, 'last_seen': today})
    e['affects'] |= affected
    e['confidence'] += 1
    e['last_seen'] = today

# Schreiben (alphabetisch sortiert für stabile diffs)
if edges:
    out = ['# impact-graph.yaml — gelernte Datei-Beziehungen',
           '# Auto-generiert von ai-context-sync.sh aus HANDOFF.md Daten.',
           '# confidence: wie oft diese Beziehung in HANDOFFs erwähnt wurde.', '',
           'edges:']
    for src in sorted(edges):
        e = edges[src]
        affects = sorted(e['affects'])
        out.append(f"  - source: {src}")
        out.append(f"    affects: [{', '.join(affects)}]")
        out.append(f"    confidence: {e['confidence']}")
        out.append(f"    last_seen: {e['last_seen']}")
    graph_p.write_text('\n'.join(out) + '\n', encoding='utf-8')
    print(f"  🧠 impact-graph: {len(edges)} edges")
PYEOF
    fi

    SYNC_SIZE=$(du -sh "$STORE_DIR" | cut -f1)
    echo -e "${GREEN}✅ Synchronisiert ($SYNC_SIZE)${NC}"
    echo -e "   Store: $STORE_DIR"
    ;;

  # ---- Restore: Store → Projekt ----
  --restore)
    if [ ! -d "$STORE_DIR/_ai_context" ]; then
      echo -e "${RED}❌ Kein gespeicherter Kontext für '$PROJECT_NAME'${NC}"
      echo -e "   Verfügbare Projekte:"
      ls -1 "$HOME/.ai-context/projects/" 2>/dev/null | sed 's/^/     /'
      exit 1
    fi
    
    echo -e "${YELLOW}⚠️  Restore überschreibt lokale _ai_context/ Dateien${NC}"
    read -p "Fortfahren? (j/n) " -n 1 -r
    echo
    [[ ! $REPLY =~ ^[jJyY]$ ]] && exit 0
    
    rsync -a "$STORE_DIR/_ai_context/" "$CONTEXT_DIR/"
    echo -e "${GREEN}✅ Kontext wiederhergestellt aus Store${NC}"
    ;;

  # ---- List: Alle gespeicherten Projekte ----
  --list)
    echo -e "${CYAN}📦 Gespeicherte Projekte:${NC}"
    echo ""
    
    for proj_dir in "$HOME/.ai-context/projects"/*/; do
      [ ! -d "$proj_dir" ] && continue
      proj_name=$(basename "$proj_dir")
      meta="$proj_dir/.meta.json"
      
      if [ -f "$meta" ]; then
        synced=$(grep '"synced"' "$meta" | sed 's/.*: *"//' | sed 's/".*//')
        stack=$(grep '"stack"' "$meta" | sed 's/.*: *"//' | sed 's/".*//')
        path=$(grep '"path"' "$meta" | sed 's/.*: *"//' | sed 's/".*//')
        size=$(du -sh "$proj_dir" | cut -f1)
        echo -e "  ${GREEN}$proj_name${NC}"
        echo -e "    Stack:   $stack"
        echo -e "    Pfad:    $path"
        echo -e "    Sync:    $synced"
        echo -e "    Größe:   $size"
        echo ""
      else
        echo -e "  ${YELLOW}$proj_name${NC} (kein Metadata)"
      fi
    done
    ;;

  # ---- Export: _SESSION.md → Clipboard (für Chat/Cowork) ----
  --export)
    SESSION="$CONTEXT_DIR/_SESSION.md"
    if [ ! -f "$SESSION" ]; then
      echo -e "${YELLOW}Generiere _SESSION.md...${NC}"
      bash "$(dirname "${BASH_SOURCE[0]}")/ai-session-prep.sh"
    fi
    
    # macOS
    if command -v pbcopy &>/dev/null; then
      cat "$SESSION" | pbcopy
      echo -e "${GREEN}✅ _SESSION.md in Zwischenablage kopiert${NC}"
      echo -e "   Einfach in Claude Chat einfügen (Cmd+V)"
    # Linux
    elif command -v xclip &>/dev/null; then
      cat "$SESSION" | xclip -selection clipboard
      echo -e "${GREEN}✅ _SESSION.md in Zwischenablage kopiert${NC}"
    else
      echo -e "${YELLOW}Clipboard nicht verfügbar. Inhalt:${NC}"
      echo "---"
      cat "$SESSION"
    fi
    
    WORDS=$(wc -w < "$SESSION")
    echo -e "   ${CYAN}$WORDS Wörter ≈ $((WORDS * 4 / 3)) Tokens${NC}"
    ;;

  # ---- Share Gotcha: Projekt → Global ----
  --share-gotcha)
    GOTCHA="${2:-}"
    if [ -z "$GOTCHA" ]; then
      echo -e "${RED}Usage: --share-gotcha \"ID: beschreibung\"${NC}"
      exit 1
    fi
    
    # Check if already exists
    if grep -q "$GOTCHA" "$GLOBAL_GOTCHAS" 2>/dev/null; then
      echo -e "${YELLOW}⚠️  Gotcha existiert bereits global${NC}"
    else
      echo "" >> "$GLOBAL_GOTCHAS"
      echo "### $GOTCHA" >> "$GLOBAL_GOTCHAS"
      echo "Quelle: $PROJECT_NAME ($TODAY)" >> "$GLOBAL_GOTCHAS"
      echo "" >> "$GLOBAL_GOTCHAS"
      echo -e "${GREEN}✅ Gotcha global geteilt${NC}"
    fi
    ;;

  # ---- Import Global Gotchas → Projekt ----
  --import-global)
    if [ ! -f "$GLOBAL_GOTCHAS" ]; then
      echo -e "${YELLOW}Keine globalen Gotchas vorhanden${NC}"
      exit 0
    fi
    
    GOTCHA_FILE="$CONTEXT_DIR/_gotchas.md"
    if [ -f "$GOTCHA_FILE" ]; then
      GLOBAL_COUNT=$(grep -c "^### " "$GLOBAL_GOTCHAS" 2>/dev/null || echo "0")
      echo -e "${CYAN}$GLOBAL_COUNT globale Gotchas verfügbar${NC}"
      echo -e "Globale Gotchas werden in _SESSION.md eingebunden."
    fi
    ;;

  *)
    echo "Usage: ai-context-sync.sh [sync|--restore|--list|--export|--share-gotcha|--import-global]"
    exit 1
    ;;
esac
