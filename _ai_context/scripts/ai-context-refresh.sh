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
  sed -i.bak 's/| ⚠️ |/| ✅ |/g; s/| ❌ |/| ✅ |/g' "$INDEX_FILE"
  rm -f "${INDEX_FILE}.bak"
  echo -e "${GREEN}✅ Alle Status auf ✅ zurückgesetzt${NC}"
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
    
    invalidate() {
      local context_file="$1"
      local marker="$2"
      local escaped
      escaped=$(echo "$context_file" | sed 's/\//\\\//g')
      
      # Fix: match the actual table format in _ai_index.md
      # Pattern: | `filename` | ✅ | or | `filename` | ⚠️ |
      if grep -q "\`${context_file}\`" "$INDEX_FILE" 2>/dev/null; then
        sed -i.bak "s/| \`${escaped}\` | ✅ /| \`${escaped}\` | ${marker} /" "$INDEX_FILE" 2>/dev/null
        # Only escalate ⚠️ → ❌, never downgrade ❌ → ⚠️
        if [ "$marker" = "❌" ]; then
          sed -i.bak "s/| \`${escaped}\` | ⚠️ /| \`${escaped}\` | ${marker} /" "$INDEX_FILE" 2>/dev/null
        fi
        rm -f "${INDEX_FILE}.bak"
        echo -e "   ${YELLOW}${marker} ${context_file}${NC}"
        INVALIDATED=$((INVALIDATED + 1))
      fi
    }

    # Check patterns
    echo "$CHANGED" | grep -qiE 'prisma|schema|model|migration' && invalidate "backend/database.md" "❌" && invalidate "backend/api.md" "⚠️"
    echo "$CHANGED" | grep -qiE 'api/|route|views\.py|routers/' && invalidate "backend/api.md" "❌"
    echo "$CHANGED" | grep -qiE 'component|\.tsx|\.jsx' && invalidate "frontend/components.md" "❌"
    echo "$CHANGED" | grep -qiE 'store|context|hook|state' && invalidate "frontend/state.md" "❌"
    echo "$CHANGED" | grep -qiE 'package\.json|requirements\.txt|pyproject' && invalidate "architecture.md" "⚠️" && invalidate "decisions.md" "⚠️"
    echo "$CHANGED" | grep -qiE '\.env' && invalidate "backend/api.md" "⚠️"
    echo "$CHANGED" | grep -qiE 'middleware|auth' && invalidate "backend/api.md" "❌" && invalidate "frontend/state.md" "⚠️"
    echo "$CHANGED" | grep -qiE 'tailwind|css' && invalidate "frontend/components.md" "⚠️"
    echo "$CHANGED" | grep -qiE 'next\.config|vite\.config' && invalidate "architecture.md" "⚠️"
    echo "$CHANGED" | grep -qiE 'test|spec|\.test\.' && invalidate "testing.md" "⚠️"

    echo ""
    echo -e "${CYAN}${INVALIDATED} Dateien invalidiert${NC}"
  fi

  # Update stored hash
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
