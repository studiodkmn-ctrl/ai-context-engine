#!/usr/bin/env bash
# =============================================================================
# ai-context-refresh.sh — Manual Context Refresh (v5)
#
# Prüft welche Kontextdateien veraltet sind und markiert sie.
# Nutze dies wenn du merkst dass der Kontext nicht mehr stimmt.
#
# Usage:
#   bash _ai_context/scripts/ai-context-refresh.sh          # Check + mark stale
#   bash _ai_context/scripts/ai-context-refresh.sh --reset   # Reset all to ✅
#   bash _ai_context/scripts/ai-context-refresh.sh --prep    # Check + regenerate _SESSION.md
# =============================================================================
set -euo pipefail

CONTEXT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_DIR="$(cd "$CONTEXT_DIR/.." && pwd)"
INDEX_FILE="$CONTEXT_DIR/_ai_index.md"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'
TODAY=$(date +"%Y-%m-%d")

[ ! -f "$INDEX_FILE" ] && echo -e "${RED}❌ _ai_index.md nicht gefunden${NC}" && exit 1

MODE="${1:-check}"

# ---- Reset mode ----
if [ "$MODE" = "--reset" ]; then
  # FIX: Die Marker ✅/⚠️/❌ stehen in den Domain-Indizes (_idx/*.md), nicht in
  # _ai_index.md — dort ist es Spalte 3 mit 🟢/🟡/🔴. Der Reset lief bisher nur
  # gegen _ai_index.md und traf damit nichts.
  for _idx in "$CONTEXT_DIR"/_idx/*.md; do
    [ -f "$_idx" ] || continue
    sed -i.bak 's/| ⚠️ |/| ✅ |/g; s/| ❌ |/| ✅ |/g' "$_idx"
    rm -f "${_idx}.bak"
  done
  sed -i.bak 's/| 🟡 |/| 🟢 |/g; s/| 🔴 |/| 🟢 |/g' "$INDEX_FILE"
  rm -f "${INDEX_FILE}.bak"
  echo -e "${GREEN}✅ Alle Status zurückgesetzt (_idx/*.md → ✅, _ai_index.md → 🟢)${NC}"
  exit 0
fi

# ---- Get stored hash ----
# Pipefail-safe: grep may find no match in newer index format ("Git:" instead).
STORED_HASH=$( { grep -E "Last known git hash:|Git:" "$INDEX_FILE" 2>/dev/null || true; } \
  | head -1 | sed 's/.*: *//' | tr -d ' ')
CURRENT_HASH=$(cd "$PROJECT_DIR" && git log -1 --format="%H" 2>/dev/null || echo "no-git")

if [ "$STORED_HASH" = "$CURRENT_HASH" ]; then
  echo -e "${GREEN}✅ Git-Hash unverändert — Kontext ist aktuell${NC}"
  # Still check non-git changes
  if [ -f "$CONTEXT_DIR/check_context_hash.sh" ]; then
    echo -e "${CYAN}Prüfe Non-Git-Änderungen...${NC}"
    (cd "$PROJECT_DIR" && bash "$CONTEXT_DIR/check_context_hash.sh") || true
  fi
else
  echo -e "${YELLOW}⚠️  Git-Hash hat sich geändert${NC}"
  echo -e "   Gespeichert: ${STORED_HASH:0:12}"
  echo -e "   Aktuell:     ${CURRENT_HASH:0:12}"
  echo ""

  # Get changed files — -M50% detects renames (>= 50% similarity).
  # --name-status emits "A\tfile" | "M\tfile" | "D\tfile" | "R<NN>\told\tnew".
  # We collect both sides of a rename so that domain patterns match either path
  # AND the old path is invalidated even if the new name does not match any pattern.
  RAW_DIFF=""
  if [ -n "$STORED_HASH" ] && [ "$STORED_HASH" != "[STORE" ]; then
    RAW_DIFF=$(cd "$PROJECT_DIR" && git diff -M50% --name-status "$STORED_HASH" "$CURRENT_HASH" 2>/dev/null || echo "")
  else
    RAW_DIFF=$(cd "$PROJECT_DIR" && git diff -M50% --name-status HEAD~1 HEAD 2>/dev/null || echo "")
  fi
  CHANGED=$(awk -F'\t' '$1 ~ /^R/ { print $2; print $3; next } { for(i=2;i<=NF;i++) print $i }' <<< "$RAW_DIFF")

  if [ -n "$CHANGED" ]; then
    echo -e "${CYAN}Geänderte Dateien:${NC}"
    echo "$CHANGED" | head -15 | sed 's/^/   /'
    echo ""

    # Apply invalidation rules
    INVALIDATED=0
    
    # FIX: Das Muster "| `file` | ✅ |" gehört zu den Domain-Indizes (_idx/*.md,
    # Status in Spalte 2); angewandt wurde es auf _ai_index.md (Spalte 3, 🟢/🟡/🔴)
    # → sed traf nie etwas. Gemeldet wurde trotzdem Erfolg, sobald der Dateiname
    # irgendwo im Index vorkam. Jetzt: richtige Datei, und Meldung nur bei echter
    # Änderung. _ai_index.md pflegen post-commit und ai-session-prep.sh.
    invalidate() {
      local context_file="$1"
      local marker="$2"
      local changed_any=false

      # Schubladen-Split berücksichtigen: X.md kann als X_core.md/X_extended.md
      # im Index stehen (ai-context-drawer.sh).
      local base="${context_file%.md}"
      local target esc f before after
      for target in "$context_file" "${base}_core.md" "${base}_extended.md"; do
        esc=$(echo "$target" | sed 's/\//\\\//g')

        for f in "$CONTEXT_DIR"/_idx/*.md; do
          [ -f "$f" ] || continue
          grep -q "| \`${target}\` |" "$f" 2>/dev/null || continue
          before=$(cat "$f")
          sed -i.bak "s/| \`${esc}\` | ✅ |/| \`${esc}\` | ${marker} |/" "$f" 2>/dev/null
          # Nur eskalieren ⚠️ → ❌, nie zurückstufen ❌ → ⚠️
          if [ "$marker" = "❌" ]; then
            sed -i.bak "s/| \`${esc}\` | ⚠️ |/| \`${esc}\` | ${marker} |/" "$f" 2>/dev/null
          fi
          rm -f "${f}.bak"
          after=$(cat "$f")
          if [ "$before" != "$after" ]; then
            changed_any=true
          fi
        done
      done

      if $changed_any; then
        echo -e "   ${YELLOW}${marker} ${context_file}${NC}"
        INVALIDATED=$((INVALIDATED + 1))
      fi
    }

    # Check patterns
    echo "$CHANGED" | grep -qiE 'prisma|schema|model|migration' && invalidate "backend/database.md" "❌" && invalidate "backend/endpoints.md" "⚠️"
    echo "$CHANGED" | grep -qiE 'api/|route|views\.py|routers/' && invalidate "backend/endpoints.md" "❌"
    echo "$CHANGED" | grep -qiE 'component|\.tsx|\.jsx' && invalidate "frontend/components.md" "❌"
    echo "$CHANGED" | grep -qiE 'store|context|hook|state' && invalidate "frontend/state.md" "❌"
    echo "$CHANGED" | grep -qiE 'package\.json|requirements\.txt|pyproject' && invalidate "architecture.md" "⚠️" && invalidate "decisions.md" "⚠️"
    echo "$CHANGED" | grep -qiE '\.env' && invalidate "backend/endpoints.md" "⚠️"
    echo "$CHANGED" | grep -qiE 'middleware|auth' && invalidate "backend/endpoints.md" "❌" && invalidate "frontend/state.md" "⚠️"
    echo "$CHANGED" | grep -qiE 'tailwind|css' && invalidate "frontend/components.md" "⚠️"
    echo "$CHANGED" | grep -qiE 'next\.config|vite\.config' && invalidate "architecture.md" "⚠️"
    echo "$CHANGED" | grep -qiE 'test|spec|\.test\.' && invalidate "testing.md" "⚠️"

    echo ""
    echo -e "${CYAN}${INVALIDATED} Dateien invalidiert${NC}"
  fi

  # Update stored hash
  # v6+ nutzt "Git:"/"Session:", v4/v5 "Last known git hash:"/"Last session date:".
  # Beide anfassen — die im jeweiligen Projekt fehlende Variante ist ein No-Op.
  sed -i.bak "s#^Git:.*#Git:      $CURRENT_HASH#" "$INDEX_FILE" 2>/dev/null
  sed -i.bak "s#^Session:.*#Session:  $TODAY#" "$INDEX_FILE" 2>/dev/null
  sed -i.bak "s#Last known git hash:.*#Last known git hash:    $CURRENT_HASH#" "$INDEX_FILE" 2>/dev/null
  sed -i.bak "s#Last session date:.*#Last session date:      $TODAY#" "$INDEX_FILE" 2>/dev/null
  rm -f "${INDEX_FILE}.bak"
fi

# ---- Prep mode: also regenerate _SESSION.md ----
if [ "$MODE" = "--prep" ]; then
  echo ""
  echo -e "${CYAN}Regeneriere _SESSION.md...${NC}"
  bash "$SCRIPT_DIR/ai-session-prep.sh"
fi

echo ""
echo -e "${GREEN}Fertig.${NC}"
