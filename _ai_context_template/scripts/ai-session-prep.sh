#!/usr/bin/env bash
# =============================================================================
# ai-session-prep.sh — Zero-Step Startup Engine (v5.1)
#
# NEU in v5.1:
#   - Zweistufiger Index: Micro-Index + Domain-Index
#   - Globale Gotchas aus ~/.ai-context/shared/ eingebunden
#   - Auto-Sync zum lokalen Store nach Generierung
#   - Task-Detection verbessert
#   - Token-Zählung pro Sektion
#
# Usage:
#   bash _ai_context/scripts/ai-session-prep.sh              # Standard
#   bash _ai_context/scripts/ai-session-prep.sh --task UI    # Task-Hint
#   bash _ai_context/scripts/ai-session-prep.sh --full       # Alle P2 inline
#   bash _ai_context/scripts/ai-session-prep.sh --minimal    # Nur Quick Facts
# =============================================================================
set -euo pipefail

CONTEXT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_DIR="$(cd "$CONTEXT_DIR/.." && pwd)"
SESSION_FILE="$CONTEXT_DIR/_SESSION.md"
INDEX_FILE="$CONTEXT_DIR/_ai_index.md"
QUICK_FILE="$CONTEXT_DIR/_quick_facts.md"
GOTCHAS_FILE="$CONTEXT_DIR/_gotchas.md"
HASH_SCRIPT="$CONTEXT_DIR/check_context_hash.sh"
IDX_DIR="$CONTEXT_DIR/_idx"
HANDOFF_FILE="$CONTEXT_DIR/HANDOFF.md"
LIB_DIR="$CONTEXT_DIR/scripts/lib"

# Phase B: Impact-Graph aus lokalem Store (lernende Cascade-Beziehungen)
PROJECT_NAME="$(basename "$PROJECT_DIR")"
IMPACT_GRAPH="$HOME/.ai-context/projects/$PROJECT_NAME/impact-graph.yaml"

# Global store
SHARED_DIR="$HOME/.ai-context/shared"
GLOBAL_GOTCHAS="$SHARED_DIR/gotchas_global.md"

TODAY=$(date +"%Y-%m-%d %H:%M")
TASK_HINT=""
FEATURE_FILTER=""
FULL_MODE=false
MINIMAL_MODE=false
FORCE_REGEN=false

# ---- Token Budget ----
TOKEN_BUDGET_SOFT=2000    # Soft-Limit → P2/P3 zu Pointern kollabieren
BUDGET_GOTCHAS=600        # Max-Budget für Gotchas-Sektion
# Hard-Limit nur in Pro (Simple: keine Truncation)
if [ "$(cat "$HOME/.ai-context/edition" 2>/dev/null || echo simple)" = "pro" ]; then
  TOKEN_BUDGET_HARD=2500
else
  TOKEN_BUDGET_HARD=99999
fi

# ---- Inkrementeller Cache ----
CACHE_DIR="$CONTEXT_DIR/_cache"
CACHE_SECTIONS="$CACHE_DIR/sections"
mkdir -p "$CACHE_SECTIONS" 2>/dev/null || true

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --full)        FULL_MODE=true; shift ;;
    --minimal)     MINIMAL_MODE=true; shift ;;
    --force-regen) FORCE_REGEN=true; shift ;;
    --task)        TASK_HINT="${2:-}"; shift 2 ;;
    --feature)     FEATURE_FILTER="${2:-}"; shift 2 ;;
    *)             TASK_HINT="$1"; shift ;;
  esac
done

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; RED='\033[0;31m'; NC='\033[0m'

# ---- Collect git data ----
GIT_HASH=$(cd "$PROJECT_DIR" && git log -1 --format="%H" 2>/dev/null || echo "no-git")
GIT_MSG=$(cd "$PROJECT_DIR" && git log -1 --format="%s" 2>/dev/null || echo "")
RECENT_COMMITS=$(cd "$PROJECT_DIR" && git log --oneline -5 2>/dev/null || echo "keine Git-History")

# Changed files since last session
STORED_HASH=""
if [ -f "$INDEX_FILE" ]; then
  STORED_HASH=$(grep "Git:" "$INDEX_FILE" 2>/dev/null | sed 's/.*: *//' | tr -d ' ' || true)
  # Fallback for old format
  [ -z "$STORED_HASH" ] && STORED_HASH=$(grep "Last known git hash:" "$INDEX_FILE" 2>/dev/null | sed 's/.*: *//' | tr -d ' ' || true)
fi

CHANGED_FILES=""
if [ -n "$STORED_HASH" ] && [ "$STORED_HASH" != "[GIT_HASH]" ] && [ "$STORED_HASH" != "no-git" ]; then
  CHANGED_FILES=$(cd "$PROJECT_DIR" && git diff --name-only "$STORED_HASH" HEAD 2>/dev/null | head -20 || echo "")
fi

# Stale files
STALE_FILES=""
if [ -f "$INDEX_FILE" ]; then
  STALE_FILES=$(grep -E '\| (⚠️|❌) \|' "$INDEX_FILE" 2>/dev/null || echo "")
fi

# Also check domain indexes for staleness
for idx_file in "$IDX_DIR"/*.md; do
  [ ! -f "$idx_file" ] && continue
  stale=$(grep -E '\| (⚠️|❌) \|' "$idx_file" 2>/dev/null || echo "")
  [ -n "$stale" ] && STALE_FILES="${STALE_FILES}\n${stale}"
done

# ---- New Project Mode Detection ----
NEW_PROJECT_MODE=false
CODE_FILE_COUNT=$(find "$PROJECT_DIR" -maxdepth 4 \
  \( -name "*.ts" -o -name "*.tsx" -o -name "*.js" -o -name "*.jsx" \
     -o -name "*.py" -o -name "*.go" -o -name "*.rs" -o -name "*.rb" \
     -o -name "*.php" -o -name "*.dart" -o -name "*.java" -o -name "*.kt" \
     -o -name "package.json" -o -name "requirements.txt" -o -name "pyproject.toml" \
     -o -name "go.mod" -o -name "Cargo.toml" \) \
  -not -path "*/node_modules/*" -not -path "*/.git/*" -not -path "*/_ai_context/*" \
  2>/dev/null | wc -l | tr -d ' ')

STACK_KNOWN=$(grep -iE "Stack:\s*\S+" "$QUICK_FILE" 2>/dev/null | grep -viE "Unbekannt|\[e\.g\." | head -1 || echo "")

if [ "$CODE_FILE_COUNT" -lt 3 ] && [ -z "$STACK_KNOWN" ]; then
  NEW_PROJECT_MODE=true
fi

# ---- Smart task detection ----
SUGGESTED_DOMAIN=""
SUGGESTED_FILES=""

if [ -n "$TASK_HINT" ]; then
  case "$TASK_HINT" in
    UI|ui|frontend|component*|css|style*|layout*)
      SUGGESTED_DOMAIN="frontend"
      SUGGESTED_FILES="frontend/components.md" ;;
    state|store|hook*|context|redux|zustand)
      SUGGESTED_DOMAIN="frontend"
      SUGGESTED_FILES="frontend/state.md" ;;
    rout*|nav*|page*)
      SUGGESTED_DOMAIN="frontend"
      SUGGESTED_FILES="frontend/routing.md" ;;
    API|api|backend|endpoint*|route*)
      SUGGESTED_DOMAIN="backend"
      SUGGESTED_FILES="backend/endpoints.md" ;;
    auth*|login|JWT|session|middleware)
      SUGGESTED_DOMAIN="backend"
      SUGGESTED_FILES="backend/auth.md" ;;
    DB|db|database|schema*|prisma|migration*)
      SUGGESTED_DOMAIN="backend"
      SUGGESTED_FILES="backend/database.md" ;;
    debug*|fix*|bug*|error*)
      SUGGESTED_DOMAIN="infra"
      SUGGESTED_FILES="debug_patterns.md" ;;
    test*|spec*|jest|pytest)
      SUGGESTED_DOMAIN="infra"
      SUGGESTED_FILES="testing.md" ;;
    security*|CORS|XSS|injection)
      SUGGESTED_DOMAIN="infra"
      SUGGESTED_FILES="security.md" ;;
    arch*|design*|refactor*)
      SUGGESTED_DOMAIN="project"
      SUGGESTED_FILES="architecture.md" ;;
    sprint*|task*|plan*)
      SUGGESTED_DOMAIN="project"
      SUGGESTED_FILES="_temp_notes.md" ;;
    decision*|why*|ADR)
      SUGGESTED_DOMAIN="project"
      SUGGESTED_FILES="decisions.md" ;;
    *)
      SUGGESTED_DOMAIN="" ;;
  esac
elif [ -n "$CHANGED_FILES" ]; then
  # Auto-detect domain from recent changes
  echo "$CHANGED_FILES" | grep -qiE 'component|\.tsx|\.jsx|\.css|\.vue|\.svelte' && SUGGESTED_DOMAIN="frontend"
  echo "$CHANGED_FILES" | grep -qiE 'api/|route|endpoint|view|controller' && SUGGESTED_DOMAIN="${SUGGESTED_DOMAIN:-backend}"
  echo "$CHANGED_FILES" | grep -qiE 'schema|model|migration|prisma' && SUGGESTED_DOMAIN="${SUGGESTED_DOMAIN:-backend}"
  echo "$CHANGED_FILES" | grep -qiE 'test|spec' && SUGGESTED_DOMAIN="${SUGGESTED_DOMAIN:-infra}"
fi

# ---- Count tokens helper (v7 — delegiert an scripts/lib/ctx.py, siehe dort) ----
count_tokens() {
  local file="$1"
  [ ! -f "$file" ] && echo "0" && return
  python3 "$LIB_DIR/ctx.py" count_tokens < "$file"
}

# Zählt Tokens aus einem String (nicht Datei)
count_tokens_str() {
  local content="$1"
  printf '%s' "$content" | python3 "$LIB_DIR/ctx.py" count_tokens
}

# ---- Inkrementeller Cache ----
# Prüft ob der Cache für eine Sektion noch gültig ist (mtime-basiert)
is_cache_valid() {
  local section="$1"
  local source_file="$2"
  local cache_file="$CACHE_SECTIONS/${section}.cache"
  [ ! -f "$cache_file" ] && echo "false" && return
  [ ! -f "$source_file" ] && echo "false" && return
  $FORCE_REGEN && echo "false" && return
  local src_sig
  src_sig="$(stat -f '%m-%z' "$source_file" 2>/dev/null || stat -c '%Y-%s' "$source_file" 2>/dev/null || echo 'unknown')"
  local cached_sig
  cached_sig=$(head -1 "$cache_file" 2>/dev/null | sed 's/^#SIG://')
  [ "$src_sig" = "$cached_sig" ] && echo "true" || echo "false"
}

write_cache() {
  local section="$1"
  local source_file="$2"
  local content="$3"
  local cache_file="$CACHE_SECTIONS/${section}.cache"
  local src_sig
  src_sig="$(stat -f '%m-%z' "$source_file" 2>/dev/null || stat -c '%Y-%s' "$source_file" 2>/dev/null || echo 'unknown')"
  printf '#SIG:%s\n%s' "$src_sig" "$content" > "$cache_file" 2>/dev/null || true
}

# ---- Phase A: HANDOFF Signal Propagation ----
# Liest HANDOFF.md neue Felder (⚠️/🔍/🌐), updated _ai_index.md Status-Spalte,
# erzeugt Priority-Sektion für _SESSION.md.
PRIORITY_SIGNALS_TMP="$CONTEXT_DIR/_priority_signals.tmp"
rm -f "$PRIORITY_SIGNALS_TMP"

if [ -f "$HANDOFF_FILE" ] && [ -f "$INDEX_FILE" ]; then
  python3 - "$HANDOFF_FILE" "$INDEX_FILE" "$QUICK_FILE" "$PRIORITY_SIGNALS_TMP" "$IMPACT_GRAPH" 2>/dev/null << 'PYEOF' || true
import sys, re, pathlib
from datetime import date

handoff_p = pathlib.Path(sys.argv[1])
index_p   = pathlib.Path(sys.argv[2])
quick_p   = pathlib.Path(sys.argv[3])
out_p     = pathlib.Path(sys.argv[4])
graph_p   = pathlib.Path(sys.argv[5]) if len(sys.argv) > 5 else None

if not handoff_p.exists():
    sys.exit(0)

text = handoff_p.read_text(encoding='utf-8')

def extract_section(heading):
    m = re.search(rf'## {re.escape(heading)}\s*\n([\s\S]*?)(?=\n## |\n---|\Z)', text)
    if not m:
        return ''
    content = re.sub(r'<!--[\s\S]*?-->', '', m.group(1))
    if '[leer wenn nichts]' in content:
        return ''
    return content.strip()

needs_update = extract_section('⚠️ Welche Kontextdatei muss aktualisiert werden?')
incomplete   = extract_section('🔍 Welche Scope-Datei war unvollständig?')
globals_hit  = extract_section('🌐 Welche globalen Abhängigkeiten wurden berührt?')

if not (needs_update or incomplete or globals_hit):
    sys.exit(0)

def parse_lines(blob):
    out = []
    for line in blob.splitlines():
        line = line.strip().lstrip('-').strip()
        if not line or line.startswith('['):
            continue
        m = re.match(r'`?([^\s`—\-]+\.\w+)`?\s*(?:[—\-]+\s*(.*))?', line)
        if m:
            out.append((m.group(1).strip(), (m.group(2) or '').strip()))
    return out

warnings = parse_lines(needs_update)
critical = parse_lines(incomplete)
globals_ = parse_lines(globals_hit)

# Impact-Map aus _quick_facts.md "Genutzt von"-Tabelle
impact_map = {}
if quick_p.exists():
    qtext = quick_p.read_text(encoding='utf-8')
    for m in re.finditer(r'\|\s*`([^`]+)`\s*\|[^|]*\|\s*([^|]+)\|', qtext):
        code_file = m.group(1).strip()
        contexts = [c.strip() for c in m.group(2).split(',') if '.md' in c]
        if contexts:
            impact_map[code_file] = contexts

# Phase B: impact-graph.yaml als zweite Quelle (gelernt aus Vergangenheit)
# Wenn _quick_facts.md keine Map hat, schaut Cascade in den lernenden Graph
if graph_p and graph_p.exists():
    gtext = graph_p.read_text(encoding='utf-8')
    cur = None
    for line in gtext.splitlines():
        s = line.strip()
        if s.startswith('- source:'):
            cur = s.split(':', 1)[1].strip()
        elif cur and s.startswith('affects:'):
            raw = s.split(':', 1)[1].strip().strip('[]')
            ctxs = [x.strip() for x in raw.split(',') if x.strip().endswith('.md')]
            # Nur ergänzen wenn _quick_facts.md keine Daten hatte
            if cur not in impact_map and ctxs:
                impact_map[cur] = ctxs
            elif cur in impact_map:
                # Vereinige (gelernt + manuell)
                impact_map[cur] = list(dict.fromkeys(impact_map[cur] + ctxs))

# Cascade: max 5 betroffene Dateien pro globaler Dep
cascade = {}
for code_file, reason in globals_:
    for ctx in impact_map.get(code_file, [])[:5]:
        cascade[ctx] = f"{code_file} geändert" + (f" — {reason}" if reason else "")

# _ai_index.md Status-Spalte updaten
itext = index_p.read_text(encoding='utf-8')
today = date.today().strftime('%d.%m')

def set_status(content, file_rel, new_status):
    pat = re.compile(
        r'(\|\s*`' + re.escape(file_rel) + r'`\s*\|[^|]*\|\s*)([^|]+?)(\s*\|\s*)([^|]+?)(\s*\|)'
    )
    return pat.sub(
        lambda m: f"{m.group(1)}{new_status}{m.group(3)}{today}{m.group(5)}",
        content, count=1
    )

changed = set()
for f, _ in critical:
    new = set_status(itext, f, '🔴')
    if new != itext:
        itext = new; changed.add(f)
for f, _ in warnings:
    if f in changed: continue
    new = set_status(itext, f, '⚠️')
    if new != itext:
        itext = new; changed.add(f)
for f in cascade:
    if f in changed: continue
    new = set_status(itext, f, '⚠️')
    if new != itext:
        itext = new; changed.add(f)

if changed:
    index_p.write_text(itext, encoding='utf-8')

# Priority-Sektion für _SESSION.md
crit_set = {f for f, _ in critical}
warn_set = {f for f, _ in warnings}
lines = ['## 🚨 Priorität laut HANDOFF', '> Diese Dateien brauchen Aufmerksamkeit BEVOR neue Coding-Tasks starten.', '']
for f, reason in critical:
    lines.append(f"- 🔴 `{f}` — unvollständig" + (f": {reason}" if reason else ""))
for f, reason in warnings:
    if f in crit_set: continue
    lines.append(f"- ⚠️ `{f}` — Update nötig" + (f": {reason}" if reason else ""))
for ctx, reason in cascade.items():
    if ctx in crit_set or ctx in warn_set: continue
    lines.append(f"- ⚠️ `{ctx}` — {reason} (Cascade)")

if len(lines) > 3:
    lines.append('')
    out_p.write_text('\n'.join(lines), encoding='utf-8')
PYEOF
fi

# ---- Phase B+: Symbol Map + Interface Snapshot (v6.6) ----
# Regeneriert _idx/symbols.md und _idx/interfaces.md wenn Source-Dateien
# neuer sind als die generierten Dateien — eliminiert 50-70% der Exploration-Reads.
SYMBOLS_FILE="$IDX_DIR/symbols.md"
INTERFACES_FILE="$IDX_DIR/interfaces.md"
SYMBOL_MAP_SCRIPT="$CONTEXT_DIR/scripts/ai-symbol-map.sh"
INTERFACE_SCRIPT="$CONTEXT_DIR/scripts/ai-interface-snapshot.sh"

_needs_regen() {
  local target="$1"
  [ ! -f "$target" ] && return 0
  # Regen wenn Source neuer als Target (vergleiche mtime)
  local src_newer
  src_newer=$(find "$PROJECT_DIR" \( -name "*.ts" -o -name "*.tsx" -o -name "*.py" -o -name "*.go" -o -name "*.rs" \) \
    -newer "$target" -not -path "*/node_modules/*" -not -path "*/_ai_context/*" \
    -not -path "*/dist/*" -not -path "*/.next/*" 2>/dev/null | head -1)
  [ -n "$src_newer" ] && return 0
  return 1
}

if [ -f "$SYMBOL_MAP_SCRIPT" ] && ! $MINIMAL_MODE; then
  if _needs_regen "$SYMBOLS_FILE" || $FORCE_REGEN; then
    bash "$SYMBOL_MAP_SCRIPT" 2>/dev/null || true
  fi
fi

if [ -f "$INTERFACE_SCRIPT" ] && ! $MINIMAL_MODE; then
  if _needs_regen "$INTERFACES_FILE" || $FORCE_REGEN; then
    bash "$INTERFACE_SCRIPT" 2>/dev/null || true
  fi
fi

# ---- Assemble _SESSION.md ----
TOTAL_TOKENS=0

{
  cat << 'HEADER'
# 🧠 _SESSION.md — Pre-assembled Context (Auto-Generated)
> **Diese Datei wurde automatisch generiert. Nicht manuell editieren.**
> Neu generieren: `bash _ai_context/scripts/ai-session-prep.sh`

---

## 🎯 Behavior Rules (MUST apply)

Diese Regeln überschreiben das Default-Verhalten und müssen strikt angewendet werden:

1. **Bei Fehlerberichten / Stack-Traces / Bug-Meldungen**:
   BEVOR du antwortest, scanne `_gotchas.md` und `debug_patterns.md` nach einer passenden ID.
   Bei Match antworte zuerst mit: `Bekannter Fehler gefunden (Priorität: P{N}): {ID}`
   Dann zeige den Fix. Bei mehreren betroffenen Dateien biete Auto-Fix für alle an.
   Bei UI-/Button-/Navigation-Bugs zusätzlich: lies `_interaction_map.md` und
   verfolge das betroffene Element → Datei:Zeile → Handler → State → Endpoint,
   BEVOR du die Codebase durchsuchst.

2. **Bei Code-Aufgaben** (Route/Komponente/Schema erstellen):
   BEVOR du eine Quelldatei komplett liest:
   a) Suche in `_idx/symbols.md` nach Funktionsname → springe direkt zu Datei:Zeile
   b) Suche in `_idx/interfaces.md` nach Interface-/Type-Namen → Felder sofort bekannt
   c) Lies nur die betroffene Stelle, nicht die ganze Datei
   Sage dann explizit welche Kontextdateien du liest und erstelle Code mit Projektregeln.

3. **Bei Sprint-/Status-Fragen** ("Was haben wir diese Woche gemacht?"):
   Lade `_temp_notes.md` + `git log --since='7 days ago' --oneline`.
   Zeige im Format:
   ```
   ✅ Abgeschlossen: <bullet list>
   🔨 In Arbeit:    <bullet list>
   📋 Offen:         <bullet list>
   ```

4. **Projektregeln sind verbindlich**: Auth-Check, Prisma-Singleton, etc. aus Quick Facts
   wendest du bei neuem Code automatisch an — kein Disclaimer, keine Nachfrage nötig.

5. **Sprachregel**: Kommunikation Deutsch, Code & Identifier Englisch.

6. **Session-Übergabe** (HANDOFF.md):
   → Bei Session-Start: Falls HANDOFF-Sektion unten "Status: in_progress" zeigt,
     LIES sie zuerst und setze die Arbeit dort fort.
   → Bei Session-Ende: Wenn Aufgabe NICHT fertig ist, schreibe Zustand
     in `HANDOFF.md` (Status, Was läuft, Nächster Schritt, Geänderte Dateien).
     Wenn Aufgabe FERTIG ist: HANDOFF.md leeren oder `Status: done` setzen.

---
HEADER

  # Section 0.3: New Project Mode (injected when empty project detected)
  if $NEW_PROJECT_MODE; then
    cat << 'NPM_RULE'

## 🆕 NEW PROJECT MODE (aktiv — leeres Projekt erkannt)

**Gilt für die ERSTE Nutzer-Nachricht dieser Session:**

→ Lies die erste Nachricht — extrahiere **still** (ohne zu fragen):
   Projektname, Stack, Hauptziel, grobe Architektur
→ Schreibe sofort in:
   - `_ai_context/_quick_facts.md` → Identity-Block (Project, Stack, Phase)
   - `_ai_context/architecture.md` → 3-4 Sätze: Was, Wie, Warum
→ Antworte dann **normal** auf die Anfrage — kein Kommentar über das Schreiben
→ Beispiel:
   Aus: "bau mir einen YouTube RAG chatbot mit Next.js und OpenAI"
   → Project: youtube-rag-chatbot | Stack: Next.js + OpenAI API | Phase: MVP
   → architecture.md: RAG-Chatbot der YouTube-Transkripte indexiert und per Chat abfragt

---
NPM_RULE
  fi

  # Section 0.4: Priority Signals from HANDOFF (NEW v6.2)
  if [ -f "$PRIORITY_SIGNALS_TMP" ]; then
    echo ""
    cat "$PRIORITY_SIGNALS_TMP"
    echo ""
    T=$(count_tokens "$PRIORITY_SIGNALS_TMP")
    TOTAL_TOKENS=$((TOTAL_TOKENS + T))
    rm -f "$PRIORITY_SIGNALS_TMP"
  fi

  # Section 0.5: Active Handoff (only if in_progress)
  if [ -f "$HANDOFF_FILE" ] && grep -qE '^\*\*Status:\*\*\s*in_progress' "$HANDOFF_FILE"; then
    echo ""
    echo "## 🤝 Aktive Session-Übergabe (in_progress)"
    echo "> Vorherige Session unfertig. Lies das zuerst, dann setze Arbeit fort."
    echo ""
    # Inline only the body — strip header comments
    sed -n '/^\*\*Status:/,/^---$/p' "$HANDOFF_FILE" | sed '$d'
    echo ""
    T=$(count_tokens "$HANDOFF_FILE")
    TOTAL_TOKENS=$((TOTAL_TOKENS + T))
  fi

  # Section 0.6: Code-Navigation (v6.6) — Symbol Map + Interface Snapshot + Hot Paths
  # Zeigt Pointer zu auto-generierten Navigationsdateien + inlined hot_paths wenn vorhanden
  HOT_PATHS_FILE="$CONTEXT_DIR/hot_paths.md"
  NAV_SHOWN=false

  if [ -f "$SYMBOLS_FILE" ] || [ -f "$INTERFACES_FILE" ] || [ -f "$HOT_PATHS_FILE" ]; then
    echo ""
    echo "## 🧭 Code-Navigation"
    echo ""
    NAV_SHOWN=true
  fi

  if [ -f "$SYMBOLS_FILE" ]; then
    SYM_COUNT=$(grep -c "^  " "$SYMBOLS_FILE" 2>/dev/null || echo "?")
    SYM_FILES=$(grep -c "^## \`" "$SYMBOLS_FILE" 2>/dev/null || echo "?")
    echo "**Symbol Map** (\`_idx/symbols.md\`) — ${SYM_FILES} Dateien, ~${SYM_COUNT} Symbole mit Zeilennummern"
    echo "> Bevor du eine Datei komplett liest: Suche hier nach Funktionsname → springe direkt zu Datei:Zeile"
    echo ""
    T=$(count_tokens "$SYMBOLS_FILE")
    TOTAL_TOKENS=$((TOTAL_TOKENS + T))
  fi

  if [ -f "$INTERFACES_FILE" ]; then
    IFACE_COUNT=$(grep -cE "^[A-Za-z]" "$INTERFACES_FILE" 2>/dev/null || echo "?")
    echo "**Interface Snapshot** (\`_idx/interfaces.md\`) — ~${IFACE_COUNT} Typen mit Feldern"
    echo "> Bevor du shared.ts/types.ts liest: Suche hier nach Interface-Namen + Felder"
    echo ""
    T=$(count_tokens "$INTERFACES_FILE")
    TOTAL_TOKENS=$((TOTAL_TOKENS + T))
  fi

  if [ -f "$HOT_PATHS_FILE" ] && ! grep -q "\[EXAMPLE_PATTERN" "$HOT_PATHS_FILE" 2>/dev/null; then
    echo "---"
    echo ""
    echo "## 🔥 Hot Paths (Kritische Runtime-Invarianten)"
    echo "> Stabile Nicht-Offensichtliche Muster — einmal lesen, dann nicht mehr rekonstruieren"
    echo ""
    # Skip header lines (first 4), show content
    tail -n +5 "$HOT_PATHS_FILE"
    echo ""
    T=$(count_tokens "$HOT_PATHS_FILE")
    TOTAL_TOKENS=$((TOTAL_TOKENS + T))
  fi

  # Section 1: Quick Facts (always inline)
  if [ -f "$QUICK_FILE" ]; then
    echo ""
    echo "## ⚡ Quick Facts"
    echo ""
    sed -n '/^## Identity/,$ p' "$QUICK_FILE"
    echo ""
    T=$(count_tokens "$QUICK_FILE")
    TOTAL_TOKENS=$((TOTAL_TOKENS + T))
  fi

  # Section 2: Session Status
  cat << EOF

---

## 📊 Session Status
\`\`\`
Generiert:      $TODAY
Git Hash:       ${GIT_HASH:0:12}
Letzter Commit: $GIT_MSG
Domain-Fokus:   ${SUGGESTED_DOMAIN:-auto-detect}
\`\`\`

EOF

  # Stale warnings
  if [ -n "$STALE_FILES" ]; then
    echo "### ⚠️ Veraltete Kontextdateien"
    echo '```'
    echo -e "$STALE_FILES"
    echo '```'
    echo ""
  fi

  # Changed files
  if [ -n "$CHANGED_FILES" ]; then
    echo "### 🔄 Geändert seit letzter Session"
    echo '```'
    echo "$CHANGED_FILES"
    echo '```'
    echo ""
    
    # Diff-only: show what actually changed in context files
    CONTEXT_DIFF=""
    if [ -n "$STORED_HASH" ] && [ "$STORED_HASH" != "[GIT_HASH]" ] && [ "$STORED_HASH" != "no-git" ]; then
      while IFS= read -r ctx_md; do
        rel_path="${ctx_md#$PROJECT_DIR/}"
        file_diff=$( (cd "$PROJECT_DIR" && git diff "$STORED_HASH" HEAD -- "$rel_path" 2>/dev/null | grep '^[+-]' | grep -v '^[+-][+-][+-]' | head -5) || true)
        if [ -n "$file_diff" ]; then
          CONTEXT_DIFF="${CONTEXT_DIFF}\n${rel_path}:\n${file_diff}\n"
        fi
      done < <(find "$CONTEXT_DIR" -name "*.md" -not -name "_SESSION.md" -type f 2>/dev/null)
    fi
    
    if [ -n "$CONTEXT_DIFF" ]; then
      echo "### 📋 Kontext-Diff (nur Änderungen)"
      echo '```'
      echo -e "$CONTEXT_DIFF"
      echo '```'
      echo ""
    fi
  fi

  echo "### 📝 Letzte Commits"
  echo '```'
  echo "$RECENT_COMMITS"
  echo '```'
  echo ""

  # Section 3: Two-tier routing (NEW in v5.1)
  echo "---"
  echo ""
  echo "## 🗂️ Kontext-Router (Zweistufig)"
  echo ""
  
  if [ -f "$INDEX_FILE" ]; then
    # Extract domain router table from micro-index
    sed -n '/## 🗂️ Domain-Router/,/^## /p' "$INDEX_FILE" 2>/dev/null | head -10
    echo ""
  fi

  # Inline the relevant domain index
  if [ -n "$SUGGESTED_DOMAIN" ] && [ -f "$IDX_DIR/${SUGGESTED_DOMAIN}.md" ]; then
    echo "### 📌 Aktiver Domain-Index: ${SUGGESTED_DOMAIN}"
    echo ""
    cat "$IDX_DIR/${SUGGESTED_DOMAIN}.md"
    echo ""
    T=$(count_tokens "$IDX_DIR/${SUGGESTED_DOMAIN}.md")
    TOTAL_TOKENS=$((TOTAL_TOKENS + T))
  else
    # Show all domain indexes compactly
    echo "### Domain-Indizes (alle)"
    for idx_file in "$IDX_DIR"/*.md; do
      [ ! -f "$idx_file" ] && continue
      domain=$(basename "$idx_file" .md)
      echo ""
      echo "#### $domain"
      # Just show the table, not the header
      grep '^|' "$idx_file" 2>/dev/null
      echo ""
    done
  fi

  # Section 3c: Interaction Map (Bug-Fix-Beschleuniger v6.5)
  IMAP_FILE="$CONTEXT_DIR/_interaction_map.md"
  if [ -f "$IMAP_FILE" ] && ! grep -q 'leer bis zum ersten Scan' "$IMAP_FILE" 2>/dev/null; then
    IMAP_ELEMS=$(grep -cE '^\| (🔘|📋|🔗)' "$IMAP_FILE" 2>/dev/null || echo 0)
    if [ "${IMAP_ELEMS:-0}" -gt 0 ]; then
      echo "---"
      echo ""
      echo "## 🔗 Interaction Map"
      echo "> $IMAP_ELEMS interaktive Elemente gemappt."
      echo "> Bei UI-/Button-/Navigation-Bugs ZUERST laden — verfolgt das Element"
      echo "> in 1 Hop zur Ursache (Datei:Zeile → Handler → State → Endpoint):"
      echo "> ⇒ \`_ai_context/_interaction_map.md\`"
      echo ""
    fi
  fi

  # Section 3d: Cross-Projekt-Ideen (Transfer-Inbox v6.5 — Phase 7)
  TRANSFER_INBOX="$HOME/.ai-context/projects/$PROJECT_NAME/transfer-inbox.yaml"
  if [ -f "$TRANSFER_INBOX" ]; then
    TI_COUNT=$(grep -c '^  - id:' "$TRANSFER_INBOX" 2>/dev/null || echo 0)
    TI_COUNT="${TI_COUNT//[^0-9]/}"
    if [ "${TI_COUNT:-0}" -gt 0 ]; then
      echo "---"
      echo ""
      echo "## 💡 Cross-Projekt-Ideen"
      echo "> $TI_COUNT Idee(n) aus anderen Projekten könnten hier passen."
      echo "> Details + Aufwandsschätzung: \`/ai-transfer\`"
      echo ""
    fi
  fi

  # Section 4: Suggested files
  if [ -n "$SUGGESTED_FILES" ]; then
    echo "---"
    echo ""
    echo "## 🎯 Empfohlene Dateien"
    echo '```'
    for f in $SUGGESTED_FILES; do
      if [ -f "$CONTEXT_DIR/$f" ]; then
        T=$(count_tokens "$CONTEXT_DIR/$f")
        echo "  ✅ $f (~${T} Tokens)"
      else
        echo "  ❌ $f (nicht vorhanden)"
      fi
    done
    echo '```'
    echo ""
  fi

  # Section 5: Gotchas (v6.0 registry-aware ODER v5.2 Fallback)
  # v6.0: Nur P1-Chunks + task-relevante Chunks inline; Rest als Pointer-Zeilen
  # v5.2: Alle Chunks aus _gotchas.md laden (wenn kein registry.yaml vorhanden)
  REGISTRY_FILE="$CONTEXT_DIR/registry.yaml"
  REGISTRY_TOOL="$(dirname "${BASH_SOURCE[0]}")/ai-context-registry.sh"

  if ! $MINIMAL_MODE; then
    RAG_CACHE_TOOL="$(dirname "${BASH_SOURCE[0]}")/ai-rag-cache.sh"

    if [ -f "$REGISTRY_FILE" ] && [ -f "$REGISTRY_TOOL" ]; then
      # ---- v6.0: Registry-aware (YAML-Registry Sprint 1+2) ----

      # Sprint 2: Ollama semantische Suche → chunk IDs für Python vorberechnen
      OLLAMA_IDS=""
      if [ -n "${TASK_HINT:-}" ] && [ -f "$RAG_CACHE_TOOL" ]; then
        # --find gibt Zeilen aus wie: "  P2  auth_version  ..." → nur IDs extrahieren
        RAW_FIND=$(bash "$RAG_CACHE_TOOL" --find "$TASK_HINT" "$REGISTRY_FILE" 2>/dev/null || true)
        OLLAMA_IDS=$(printf '%s\n' "$RAW_FIND" \
          | grep -oE 'P[123][[:space:]]+[a-z][a-z0-9_]+' \
          | awk '{print $2}' \
          | tr '\n' ',' \
          | sed 's/,$//' || true)
      fi

      GOTCHA_OUT=$(python3 - "$REGISTRY_FILE" "$CONTEXT_DIR" "${TASK_HINT:-}" "$FULL_MODE" "${OLLAMA_IDS}" "${FEATURE_FILTER:-}" "$LIB_DIR" 2>/dev/null << 'PYEOF'
import sys, re, pathlib

registry_path = sys.argv[1]
context_dir = pathlib.Path(sys.argv[2])
task_hint = sys.argv[3].lower() if len(sys.argv) > 3 else ''
full_mode = (sys.argv[4].lower() == 'true') if len(sys.argv) > 4 else False

sys.path.insert(0, sys.argv[7])
import ctx as ctxlib  # scripts/lib/ctx.py — shared registry/token/chunk helpers (v7)

# Registry parsen (ctx.py, kein yaml-Modul erforderlich)
chunks = ctxlib.parse_registry(registry_path)['chunks']

KNOWLEDGE_TYPES = {'gotcha', 'debug', 'security', 'rule'}
knowledge_chunks = [c for c in chunks if c['type'] in KNOWLEDGE_TYPES]

# Phase C: Feature-Filter (argv[6]) — wenn gesetzt, NUR feature:<name> + P1 inline
feature_filter = sys.argv[6].strip().lower() if len(sys.argv) > 6 else ''
if feature_filter:
    feature_tag = f'feature:{feature_filter}'
    feature_chunks = [c for c in knowledge_chunks if feature_tag in [t.lower() for t in c['tags']]]
    p1_chunks = [c for c in knowledge_chunks if c['priority'] == 1]
    # Vereinige (P1 immer dabei) — Duplikate via id-Set entfernen
    seen = set(); merged = []
    for c in feature_chunks + p1_chunks:
        if c['id'] not in seen:
            seen.add(c['id']); merged.append(c)
    knowledge_chunks = merged

if not knowledge_chunks:
    sys.exit(0)

task_words = set(re.findall(r'[a-z][a-z0-9_-]+', task_hint)) if task_hint else set()

# Inline-IDs bestimmen: P1 immer + task-relevante
inline_ids = set()
for c in knowledge_chunks:
    if c['priority'] == 1:
        inline_ids.add(c['id'])
    if feature_filter and f'feature:{feature_filter}' in [t.lower() for t in c['tags']]:
        inline_ids.add(c['id'])

# Sprint 2: Ollama-Ergebnisse aus pre-computed IDs (Shell ruft --find vor Python-Aufruf auf)
# Shell übergibt komma-getrennte IDs als 6. Argument (argv[5])
ollama_ids_raw = sys.argv[5] if len(sys.argv) > 5 else ''
if ollama_ids_raw and not full_mode:
    for oid in ollama_ids_raw.split(','):
        oid = oid.strip()
        if oid and len(inline_ids) < 8:
            inline_ids.add(oid)

# Keyword-Fallback: wenn keine Ollama-IDs
if task_words and not ollama_ids_raw and not full_mode:
    for c in sorted(knowledge_chunks, key=lambda x: x['priority']):
        if c['id'] in inline_ids or len(inline_ids) >= 8:
            break
        haystack = set([c['id']] + c['tags'] + [c['type']])
        haystack.update(re.split(r'[_\-]', c['id']))
        if task_words & haystack:
            inline_ids.add(c['id'])

if full_mode:
    inline_ids = {c['id'] for c in knowledge_chunks}

def extract_chunk(chunk_id, file_rel):
    """Chunk-Text zwischen HTML-Ankern extrahieren (ctx.py, ohne .strip())."""
    return ctxlib.extract_chunk(str(context_dir / file_rel), chunk_id)

inline_parts = []
pointer_parts = []

for c in knowledge_chunks:
    if c['id'] in inline_ids:
        text = extract_chunk(c['id'], c['file'])
        if text:
            inline_parts.append(text)
    else:
        # Kurzbeschreibung NUR aus Chunk-Inhalt (nicht aus ganzer Datei)
        desc = ''
        chunk_text = extract_chunk(c['id'], c['file'])
        if chunk_text:
            # → Zeile bevorzugen, sonst scope/violates
            arrow_m = re.search(r'→\s*([^\n]+)', chunk_text)
            if arrow_m:
                desc = arrow_m.group(1)[:55]
            else:
                fallback_m = re.search(r'(?:scope|violates):\s*([^\n]+)', chunk_text)
                if fallback_m:
                    desc = fallback_m.group(1)[:55]
        pointer_parts.append(f"⇒ {c['id']} — {desc} [P{c['priority']}]")

total = len(knowledge_chunks)
mode_str = "P1+task-relevant" if not full_mode else "alle"
print(f"## ⚡ Gotchas ({total} gesamt, {mode_str} inline)")
print()

# chunk_text enthält bereits die ``` Markdown-Fences
for part in inline_parts:
    print(part)
    print()

if pointer_parts:
    print('// Weitere Chunks (--full für Details | Sprint 2: Ollama findet automatisch):')
    print('```')
    for p in pointer_parts:
        print(p)
    print('```')
    print()
PYEOF
)

      if [ -n "$GOTCHA_OUT" ]; then
        echo "---"
        echo ""
        echo "$GOTCHA_OUT"
        T=$(count_tokens_str "$GOTCHA_OUT")
        TOTAL_TOKENS=$((TOTAL_TOKENS + T))
      fi

    elif [ -f "$GOTCHAS_FILE" ]; then
      # ---- v5.2 Fallback: Original-Code (unverändert) ----
      GOTCHA_COUNT=$(python3 -c "
import re, pathlib
c = pathlib.Path('$GOTCHAS_FILE').read_text(encoding='utf-8')
print(len(re.findall(r'\`\`\`\s*\n(?:ID:|RULE:)', c)))
" 2>/dev/null || grep -cE "^(### )?ID:" "$GOTCHAS_FILE" 2>/dev/null || echo "0")
      GOTCHA_COUNT="${GOTCHA_COUNT//[^0-9]/}"
      GOTCHA_COUNT=${GOTCHA_COUNT:-0}
      if [ "$GOTCHA_COUNT" -gt 0 ]; then
        echo "---"
        echo ""
        echo "## ⚡ Gotchas (${GOTCHA_COUNT} aktiv)"
        echo ""
        if [ "$(is_cache_valid "gotchas" "$GOTCHAS_FILE")" = "true" ]; then
          tail -n +2 "$CACHE_SECTIONS/gotchas.cache" 2>/dev/null
        else
          if grep -q "## Aktiv" "$GOTCHAS_FILE" 2>/dev/null; then
            SECTION_CONTENT=$(sed -n '/^## Aktiv/,/^## Legende/p' "$GOTCHAS_FILE" | sed '$d')
          else
            SECTION_CONTENT=$(sed -n '/^### ID:/,$ p' "$GOTCHAS_FILE")
          fi
          echo "$SECTION_CONTENT"
          write_cache "gotchas" "$GOTCHAS_FILE" "$SECTION_CONTENT"
        fi
        echo ""
        T=$(count_tokens "$GOTCHAS_FILE")
        TOTAL_TOKENS=$((TOTAL_TOKENS + T))
      fi
    fi
  fi

  # Section 5b: Global Gotchas (v5.2 — Stack-basiert gefiltert)
  if ! $MINIMAL_MODE && [ -f "$GLOBAL_GOTCHAS" ]; then
    # Lese aktuellen Stack aus _quick_facts.md für Relevanz-Filter
    CURRENT_STACK=$(grep -iE "Stack:|Framework:|Tech:" "$QUICK_FILE" 2>/dev/null | head -3 | sed 's/.*: *//' | tr '[:upper:]' '[:lower:]' | tr '\n' ' ' || echo "")
    FILTERED_GLOBAL=$(python3 - "$GLOBAL_GOTCHAS" "$CURRENT_STACK" << 'PYEOF'
import re, sys

fpath, stack_str = sys.argv[1], sys.argv[2].lower()
stack_keywords = set(re.findall(r'[a-z][a-z0-9.]+', stack_str))

content = open(fpath, encoding='utf-8').read()
# Unterstütze beide Formate: ``` ID: ... ``` und ### ID: ...
blocks_new = re.findall(r'```\s*\n((?:ID:|RULE:)[\s\S]*?)```', content)
blocks_old = re.findall(r'### (ID:|RULE:.*?)\n([\s\S]*?)(?=^###|\Z)', content, re.MULTILINE)

matched = []
for block in blocks_new:
    tags_match = re.search(r'\ntags:\s*([^\n]+)', block)
    if not tags_match:
        matched.append('```\n' + block + '```')  # Kein Tag → immer inkludieren
        continue
    tags_raw = tags_match.group(1).lower()
    stack_tags = {t.split(':')[1] for t in re.findall(r'stack:[a-z0-9.]+', tags_raw)}
    if not stack_tags or any(st in stack_str for st in stack_tags):
        matched.append('```\n' + block + '```')

# Fallback: altes Format (### ID:) ohne Tag-Unterstützung → immer inkludieren
for prefix, body in blocks_old:
    matched.append(f'### {prefix}\n{body}')

for m in matched:
    print(m)
    print()

import sys as _sys
_sys.stderr.write(f"Stack-Filter: {len(matched)} global gotchas relevant\n")
PYEOF
2>/dev/null || echo "")

    if [ -n "$FILTERED_GLOBAL" ]; then
      FILTERED_COUNT=$(echo "$FILTERED_GLOBAL" | python3 -c "import re,sys; print(len(re.findall(r'ID:|RULE:', sys.stdin.read())))" 2>/dev/null || echo "?")
      echo "---"
      echo ""
      echo "## 🌍 Globale Gotchas (${FILTERED_COUNT} stack-relevant)"
      echo ""
      echo "$FILTERED_GLOBAL"
      echo ""
    fi
  fi

  # Section 6: Full mode — inline all context files
  if $FULL_MODE; then
    echo "---"
    echo ""
    echo "## 📦 Vollständiger Kontext (--full)"
    echo ""
    for f in architecture.md decisions.md frontend/components.md frontend/state.md frontend/routing.md backend/endpoints.md backend/auth.md backend/database.md; do
      fpath="$CONTEXT_DIR/$f"
      if [ -f "$fpath" ]; then
        T=$(count_tokens "$fpath")
        echo "### 📄 $f (~${T} Tokens)"
        echo ""
        cat "$fpath"
        echo ""
        echo "---"
        echo ""
        TOTAL_TOKENS=$((TOTAL_TOKENS + T))
      fi
    done
    # Fallback: old api.md if new split files don't exist
    if [ ! -f "$CONTEXT_DIR/backend/endpoints.md" ] && [ -f "$CONTEXT_DIR/backend/api.md" ]; then
      T=$(count_tokens "$CONTEXT_DIR/backend/api.md")
      echo "### 📄 backend/api.md (~${T} Tokens)"
      echo ""
      cat "$CONTEXT_DIR/backend/api.md"
      echo ""
      TOTAL_TOKENS=$((TOTAL_TOKENS + T))
    fi
  fi

  # Section 7: Compact rules
  cat << 'RULES'
---

## 📋 Runtime-Regeln
```
ROUTER:   Micro-Index → Domain-Index → Kontextdatei (max 3 Dateien pro Kette)
LADEN:    Max 4 Dateien pro Session gesamt
NAVIGATE: Vor Datei-Read → _idx/symbols.md (Funktion → Zeile) + _idx/interfaces.md (Typen)
HOTPATHS: hot_paths.md lesen statt Invarianten aus Code rekonstruieren
GOTCHAS:  Immer bei Coding-Tasks (oben inline wenn vorhanden)
WRITE:    Nach jeder Aufgabe → relevante Kontextdatei + Domain-Index Status aktualisieren
DEDUP:    Vor Writeback IDs prüfen → Update statt Duplikat
LIMITS:   _gotchas.md/debug_patterns.md max 15 | security.md/testing.md max 10 | _temp_notes max 5
SPLIT:    Datei > 500 Tokens? → Aufteilen in kleinere Domain-Dateien
SCAN:     Domain-Router beachten — nur Dateien aus relevanter Domain laden
NIE:      Ganzen Codebase laden | Alle Kontextdateien auf einmal | Stack raten
```
RULES

} > "$SESSION_FILE"

# ---- Token Budget Enforcement (v5.2) ----
SESSION_TOKENS_REAL=$(count_tokens "$SESSION_FILE")

if [ "$SESSION_TOKENS_REAL" -gt "$TOKEN_BUDGET_SOFT" ]; then
  echo -e "${YELLOW}⚠️  TOKEN BUDGET: ${SESSION_TOKENS_REAL} > ${TOKEN_BUDGET_SOFT} (Soft-Limit)${NC}"

  # Komprimiere P2/P3-Gotchas zu Pointern in SESSION.md
  python3 - "$SESSION_FILE" "$GOTCHAS_FILE" "$BUDGET_GOTCHAS" << 'PYEOF'
import re, sys, pathlib

session_path = pathlib.Path(sys.argv[1])
gotchas_path = pathlib.Path(sys.argv[2])
budget = int(sys.argv[3])

if not session_path.exists():
    sys.exit(0)

content = session_path.read_text(encoding='utf-8')

# Finde Gotchas-Sektion in SESSION.md
gotcha_section = re.search(r'(## ⚡ Gotchas.*?)(---|\Z)', content, re.DOTALL)
if not gotcha_section:
    sys.exit(0)

# Extrahiere alle Einträge aus der Sektion
section_text = gotcha_section.group(1)
blocks = re.findall(r'```\s*\n((?:ID:|RULE:)[\s\S]*?)```', section_text)

def get_priority(block):
    m = re.search(r'\nP:\s*([123])', block)
    return int(m.group(1)) if m else 2

# Teile in inline (P1) und pointer (P2/P3)
inline_blocks = []
pointer_lines = []
for block in blocks:
    p = get_priority(block)
    id_m = re.search(r'(?:ID:|RULE:)\s*(\S+)', block)
    desc_m = re.search(r'→\s*([^\n]+)', block)
    id_val = id_m.group(1) if id_m else '?'
    desc = (desc_m.group(1)[:60] if desc_m else '')
    if p == 1:
        inline_blocks.append('```\n' + block + '```')
    else:
        pointer_lines.append(f'⇒ {id_val} — {desc} [P{p}]')

# Baue neue komprimierte Sektion
new_section = gotcha_section.group(0)[:gotcha_section.group(0).index(section_text[100:])] if len(section_text) > 100 else "## ⚡ Gotchas (komprimiert)\n\n"
compressed_section = f"## ⚡ Gotchas ({len(blocks)} total, P1 inline)\n\n"
if inline_blocks:
    compressed_section += "\n".join(inline_blocks) + "\n\n"
if pointer_lines:
    compressed_section += "// P2/P3 komprimiert (--full für Details):\n"
    compressed_section += "```\n" + "\n".join(pointer_lines) + "\n```\n\n"

# Ersetze in SESSION.md
new_content = content[:gotcha_section.start()] + compressed_section + content[gotcha_section.end():]
session_path.write_text(new_content, encoding='utf-8')
print(f"  Komprimiert: {len(inline_blocks)} P1 inline, {len(pointer_lines)} P2/P3 als Pointer")
PYEOF

  SESSION_TOKENS_REAL=$(count_tokens "$SESSION_FILE")
  echo -e "   Nach Kompression: ${SESSION_TOKENS_REAL} Tokens"
fi

# Hard-Limit als letzter Ausweg
if [ "$SESSION_TOKENS_REAL" -gt "$TOKEN_BUDGET_HARD" ]; then
  echo -e "${RED}❌ Hard-Truncate: ${SESSION_TOKENS_REAL} > ${TOKEN_BUDGET_HARD} Tokens${NC}"
  # Kürze auf Byte-Basis (grobe Annäherung: 1 Token ≈ 3.5 Bytes)
  head -c $((TOKEN_BUDGET_HARD * 3)) "$SESSION_FILE" > "${SESSION_FILE}.tmp"
  printf '\n\n> ⚠️ SESSION.md hard-truncated (%d Tokens). `--full` für vollständigen Kontext.\n' "$SESSION_TOKENS_REAL" >> "${SESSION_FILE}.tmp"
  mv "${SESSION_FILE}.tmp" "$SESSION_FILE"
  SESSION_TOKENS_REAL=$(count_tokens "$SESSION_FILE")
fi

# ---- Update stored hash ----
if [ -f "$INDEX_FILE" ]; then
  sed -i.bak "s#Git:.*#Git:      $GIT_HASH#" "$INDEX_FILE" 2>/dev/null
  sed -i.bak "s#Session:.*#Session:  $(date +%Y-%m-%d)#" "$INDEX_FILE" 2>/dev/null
  # Fallback for old format
  sed -i.bak "s#Last known git hash:.*#Last known git hash:    $GIT_HASH#" "$INDEX_FILE" 2>/dev/null
  sed -i.bak "s#Last session date:.*#Last session date:      $(date +%Y-%m-%d)#" "$INDEX_FILE" 2>/dev/null
  rm -f "${INDEX_FILE}.bak"
fi

# ---- Hash baseline ----
if [ -f "$HASH_SCRIPT" ]; then
  (cd "$PROJECT_DIR" && bash "$HASH_SCRIPT" --update) > /dev/null 2>&1 || true
fi

# ---- Auto-sync to local store ----
SYNC_SCRIPT="$(dirname "${BASH_SOURCE[0]}")/ai-context-sync.sh"
if [ -f "$SYNC_SCRIPT" ]; then
  bash "$SYNC_SCRIPT" sync > /dev/null 2>&1 || true
fi

# ---- Session-Log für Multi-Session-Statistik ----
LOG_SCRIPT="$(dirname "${BASH_SOURCE[0]}")/ai-session-log.sh"
if [ -f "$LOG_SCRIPT" ]; then
  SESSION_TOKENS_FOR_LOG=${SESSION_TOKENS_REAL:-0}
  bash "$LOG_SCRIPT" append "$PROJECT_DIR" "$SESSION_TOKENS_FOR_LOG" "${SUGGESTED_DOMAIN:-project}" > /dev/null 2>&1 || true
fi

# ---- Output ----
SESSION_TOKENS=${SESSION_TOKENS_REAL:-$(count_tokens "$SESSION_FILE")}

echo ""
echo -e "${GREEN}✅ _SESSION.md generiert${NC} (~${SESSION_TOKENS} Tokens)"
echo -e "   ${CYAN}Pfad: $SESSION_FILE${NC}"
[ -n "$STALE_FILES" ] && echo -e "   ${YELLOW}⚠️  Veraltete Dateien erkannt${NC}"
[ -n "$SUGGESTED_DOMAIN" ] && echo -e "   ${CYAN}🎯 Domain: $SUGGESTED_DOMAIN${NC}"
[ -n "$SUGGESTED_FILES" ] && echo -e "   ${CYAN}📄 Empfohlen: $SUGGESTED_FILES${NC}"
echo ""

# Token breakdown
echo -e "${CYAN}Token-Aufschlüsselung:${NC}"
[ -f "$QUICK_FILE" ] && echo -e "   Quick Facts:    ~$(count_tokens "$QUICK_FILE") Tokens"
[ -n "$SUGGESTED_DOMAIN" ] && [ -f "$IDX_DIR/${SUGGESTED_DOMAIN}.md" ] && \
  echo -e "   Domain-Index:   ~$(count_tokens "$IDX_DIR/${SUGGESTED_DOMAIN}.md") Tokens"
[ -f "$GOTCHAS_FILE" ] && echo -e "   Gotchas:        ~$(count_tokens "$GOTCHAS_FILE") Tokens"
BUDGET_STATUS=""
if [ "$SESSION_TOKENS" -le "$TOKEN_BUDGET_SOFT" ]; then
  BUDGET_STATUS="${GREEN}✅ im Budget (<${TOKEN_BUDGET_SOFT})${NC}"
elif [ "$SESSION_TOKENS" -le "$TOKEN_BUDGET_HARD" ]; then
  BUDGET_STATUS="${YELLOW}⚠️ Soft-Limit überschritten${NC}"
else
  BUDGET_STATUS="${RED}❌ Hard-Limit überschritten${NC}"
fi
echo -e "   ${GREEN}Gesamt _SESSION:   ~${SESSION_TOKENS} Tokens${NC} — ${BUDGET_STATUS}"
echo ""

echo -e "${GREEN}Claude Code starten:${NC} cd $PROJECT_DIR && claude"

# Machine-readable marker — parsed by claude() shell wrapper
printf '__AI_CTX__:%s:%s\n' "${SESSION_TOKENS}" "${SUGGESTED_DOMAIN:-project}"
echo ""
