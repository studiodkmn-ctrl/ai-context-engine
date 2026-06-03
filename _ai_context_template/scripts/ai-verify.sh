#!/usr/bin/env bash
# =============================================================================
# ai-verify.sh — Verifier für den Verify-Loop (v6.5 — Phase 3)
#
# Prüft nach einem Fix, ob das Projekt noch sauber ist. Wählt bewusst ein
# SCHNELLES, NICHT-INTERAKTIVES Kommando (typecheck/lint) — nicht test/build,
# damit der Loop nicht hängt oder Minuten kostet.
#
# Reihenfolge der Kommando-Wahl:
#   1. Verify-Command aus _quick_facts.md  (manueller Override)
#   2. package.json scripts: typecheck > type-check > lint > check
#   3. Fallback: npx tsc --noEmit  (wenn tsconfig.json existiert)
#   4. Python: ruff check .  > mypy .
#
# Usage:
#   bash ai-verify.sh            # erkennen + ausführen, PASS/FAIL melden
#   bash ai-verify.sh --detect   # nur das erkannte Kommando ausgeben
#   bash ai-verify.sh --set "npm run typecheck"   # Override in _quick_facts.md
#
# Exit: 0 = PASS | 1 = FAIL/TIMEOUT | 2 = kein Kommando gefunden
# =============================================================================
set -uo pipefail

CONTEXT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_DIR="$(cd "$CONTEXT_DIR/.." && pwd)"
QUICK_FILE="$CONTEXT_DIR/_quick_facts.md"
TIMEOUT_S=120

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'

cd "$PROJECT_DIR"

# --- Override aus _quick_facts.md lesen ---
read_override() {
  [ -f "$QUICK_FILE" ] || return 0
  grep -iE '^[[:space:]]*Verify-Command:' "$QUICK_FILE" 2>/dev/null \
    | head -1 \
    | sed 's/.*[Vv]erify-[Cc]ommand:[[:space:]]*//' \
    | sed 's/^\[.*\]$//' \
    | tr -d '\r' \
    | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

# --- Verify-Kommando bestimmen ---
detect_cmd() {
  local override
  override="$(read_override)"
  if [ -n "$override" ]; then
    echo "$override"
    return 0
  fi
  if [ -f package.json ]; then
    local script
    script="$(python3 - package.json 2>/dev/null << 'PY'
import json, sys
try:
    scripts = json.load(open(sys.argv[1])).get('scripts', {})
except Exception:
    scripts = {}
for key in ('typecheck', 'type-check', 'tsc', 'lint', 'check'):
    if key in scripts:
        print(key)
        break
PY
)"
    if [ -n "$script" ]; then
      if [ -f pnpm-lock.yaml ]; then echo "pnpm run $script"
      elif [ -f yarn.lock ]; then echo "yarn $script"
      else echo "npm run $script"; fi
      return 0
    fi
    if [ -f tsconfig.json ]; then
      echo "npx --no-install tsc --noEmit"
      return 0
    fi
  fi
  if [ -f pyproject.toml ] || [ -f requirements.txt ] || ls ./*.py >/dev/null 2>&1; then
    if command -v ruff >/dev/null 2>&1; then echo "ruff check ."; return 0; fi
    if command -v mypy >/dev/null 2>&1; then echo "mypy ."; return 0; fi
  fi
  return 0
}

# --- Portabler Timeout (macOS hat kein `timeout`) ---
run_with_timeout() {
  local secs="$1"; shift
  if command -v timeout >/dev/null 2>&1; then
    timeout "$secs" "$@"; return $?
  elif command -v gtimeout >/dev/null 2>&1; then
    gtimeout "$secs" "$@"; return $?
  fi
  "$@" & local pid=$!
  ( sleep "$secs"; kill -TERM "$pid" 2>/dev/null ) & local watcher=$!
  wait "$pid" 2>/dev/null; local rc=$?
  kill "$watcher" 2>/dev/null; wait "$watcher" 2>/dev/null
  return $rc
}

# ===========================================================================
# --set: Override in _quick_facts.md schreiben
# ===========================================================================
if [ "${1:-}" = "--set" ]; then
  NEW_CMD="${2:-}"
  [ -z "$NEW_CMD" ] && echo "Usage: ai-verify.sh --set \"<kommando>\"" >&2 && exit 2
  [ -f "$QUICK_FILE" ] || { echo "❌ _quick_facts.md fehlt" >&2; exit 2; }
  if grep -qiE '^[[:space:]]*Verify-Command:' "$QUICK_FILE"; then
    python3 - "$QUICK_FILE" "$NEW_CMD" << 'PY'
import sys, re
fp, cmd = sys.argv[1], sys.argv[2]
t = open(fp, encoding='utf-8').read()
t = re.sub(r'(?im)^([ \t]*Verify-Command:).*$', r'\1  ' + cmd, t, count=1)
open(fp, 'w', encoding='utf-8').write(t)
PY
    echo -e "${GREEN}✅ Verify-Command gesetzt:${NC} $NEW_CMD"
  else
    echo -e "${YELLOW}⚠️  Kein Verify-Command-Feld in _quick_facts.md — manuell ergänzen.${NC}"
    exit 2
  fi
  exit 0
fi

# ===========================================================================
# --detect: nur erkanntes Kommando ausgeben
# ===========================================================================
CMD="$(detect_cmd)"

if [ "${1:-}" = "--detect" ]; then
  if [ -n "$CMD" ]; then echo "$CMD"; else echo "(keins gefunden)"; fi
  exit 0
fi

# ===========================================================================
# Standard: ausführen
# ===========================================================================
if [ -z "$CMD" ]; then
  echo "VERIFY: (kein Kommando)"
  echo "RESULT: NO-COMMAND"
  echo -e "${YELLOW}Kein typecheck/lint erkannt. In _quick_facts.md setzen:${NC}"
  echo "   bash _ai_context/scripts/ai-verify.sh --set \"npm run <script>\""
  exit 2
fi

echo -e "${CYAN}VERIFY:${NC} $CMD"
LOG="$(mktemp -t aictx-verify.XXXXXX.log)"
trap 'rm -f "$LOG"' EXIT

run_with_timeout "$TIMEOUT_S" bash -c "$CMD" > "$LOG" 2>&1
RC=$?

if [ "$RC" -eq 0 ]; then
  echo -e "RESULT: ${GREEN}PASS${NC}"
  exit 0
elif [ "$RC" -eq 124 ] || [ "$RC" -eq 143 ]; then
  echo -e "RESULT: ${RED}TIMEOUT${NC} (>${TIMEOUT_S}s)"
  echo "--- Letzte Ausgabe ---"
  tail -n 20 "$LOG"
  exit 1
else
  echo -e "RESULT: ${RED}FAIL${NC} (exit $RC)"
  echo "--- Fehler (gekürzt) ---"
  # Fehlerzeilen bevorzugt, sonst Tail
  ERR="$(grep -iE 'error|fail|✗|✘' "$LOG" | head -n 25 || true)"
  if [ -n "$ERR" ]; then echo "$ERR"; else tail -n 25 "$LOG"; fi
  exit 1
fi
