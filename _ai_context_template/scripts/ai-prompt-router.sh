#!/usr/bin/env bash
# =============================================================================
# ai-prompt-router.sh — UserPromptSubmit-Hook: locate() ohne Kommando (v9-b)
#
# Prüft JEDEN Prompt still gegen locate() und injiziert das Ergebnis als
# Kontext, BEVOR Claude antwortet — kein /ai-fix, kein manueller Aufruf
# nötig. Bei Fehlanzeige (kein Treffer, trivialer Prompt, kein Build)
# passiert nichts: kein Output, keine Kosten, kein Rauschen.
#
# Vertrag (Claude Code UserPromptSubmit-Hook, siehe hooks/pii-warn.sh):
#   stdin:  JSON {session_id, prompt, hook_event_name, ...}
#   stdout: bei Treffer die locate()-Karte + Präambel (wird von Claude Code
#           als zusätzlicher Kontext vor die Antwort gehängt — exakt der
#           Mechanismus, den der SessionStart-Hook "cat _SESSION.md" schon
#           nutzt)
#   exit:   immer 0 — nie einen Prompt blockieren.
#
# Fail-open: jeder Fehler (kaputtes JSON, kein locate-cli.js gebaut, o.ä.)
# -> exit 0 ohne Output, Prompt läuft normal weiter.
# =============================================================================
set -uo pipefail

CONTEXT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Stdin einlesen BEVOR ein Heredoc/Subprozess es beanspruchen könnte.
PROMPT_HOOK_INPUT="$(cat 2>/dev/null || echo '')"
[ -z "$PROMPT_HOOK_INPUT" ] && exit 0

# ---- Prompt aus JSON extrahieren (fail-open) ----
PROMPT="$(printf '%s' "$PROMPT_HOOK_INPUT" | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
    print(data.get("prompt", "") or "")
except Exception:
    pass
' 2>/dev/null)"
[ -z "$PROMPT" ] && exit 0

# Session-ID fuer das Dedup-Ledger (siehe unten)
HOOK_INPUT_SESSION="$(printf '%s' "$PROMPT_HOOK_INPUT" | python3 -c '
import json, sys
try:
    print(json.load(sys.stdin).get("session_id", "") or "")
except Exception:
    pass
' 2>/dev/null)"

# ---- Trivial-Filter: < 4 Woerter -> kein Aufruf (spart den Node-Start) ----
WORD_COUNT=$(printf '%s' "$PROMPT" | wc -w | tr -d ' ')
[ "${WORD_COUNT:-0}" -lt 4 ] && exit 0

# ---- locate-cli.js auflösen (gleiche Kandidatenliste wie ai-symptom-router.sh) ----
LOCATE_CLI=""
for _CANDIDATE in "$CONTEXT_DIR/../mcp/dist/locate-cli.js" "$HOME/.ai-context/mcp/dist/locate-cli.js"; do
  if [ -f "$_CANDIDATE" ]; then
    LOCATE_CLI="$_CANDIDATE"
    break
  fi
done
[ -z "$LOCATE_CLI" ] && exit 0
command -v node > /dev/null 2>&1 || exit 0

# ---- locate() aufrufen ----
# --strict (V10 R2): nur STARKE Treffer. Bei jedem Prompt zu laufen heisst,
# dass eine schwache Prosa-Ueberlappung hier teurer ist (ungefragte
# Injektion in JEDEN Prompt) als gar kein Treffer. Manuelle locate()-Aufrufe
# und /ai-fix nutzen den vollen Pfad ohne Flag.
LOCATE_OUT="$(node "$LOCATE_CLI" --strict "$PROMPT" 2>/dev/null)" || exit 0
[ -z "$LOCATE_OUT" ] && exit 0

# Kein Treffer -> still (dasselbe Signal, das locate() intern fuer den
# "Kein Index-Treffer"-Zweig nutzt, siehe locate.ts::locateQuery anyHit).
printf '%s' "$LOCATE_OUT" | grep -q "Kein Index-Treffer" && exit 0

# __ROUTER__:-Marker ist nur fuer /ai-fix gedacht, nicht fuer die Injektion.
LOCATE_CARD="$(printf '%s\n' "$LOCATE_OUT" | grep -v '^__ROUTER__:')"

# ---- Session-Dedup (V10 R2) ----
# Ohne das injiziert derselbe Chunk in einer laufenden Session bei jedem
# thematisch aehnlichen Prompt erneut — der Agent hat ihn laengst im
# Kontext. Ledger-Muster wie beim Read-Guard (v8.1).
SESSION_ID="$(printf '%s' "$HOOK_INPUT_SESSION" | tr -c 'a-zA-Z0-9_-' '_' | cut -c1-80)"
[ -z "$SESSION_ID" ] && SESSION_ID="unknown"
LEDGER="$CONTEXT_DIR/.session/${SESSION_ID}.injected.jsonl"

# Chunk-IDs aus der Karte ziehen (Zeilen der Form "   <id> [P<n>] ...")
NEW_IDS="$(printf '%s\n' "$LOCATE_CARD" | sed -n 's/^   \([a-zA-Z0-9_]*\) \[P[0-9]\].*/\1/p')"
if [ -n "$NEW_IDS" ] && [ -f "$LEDGER" ]; then
  UNSEEN=""
  while IFS= read -r cid; do
    [ -z "$cid" ] && continue
    grep -qxF "$cid" "$LEDGER" 2>/dev/null || UNSEEN="${UNSEEN}${cid}"$'\n'
  done <<< "$NEW_IDS"
  # Alles schon injiziert -> still bleiben.
  [ -z "$(printf '%s' "$UNSEEN" | tr -d '[:space:]')" ] && exit 0
fi

mkdir -p "$CONTEXT_DIR/.session" 2>/dev/null
if [ -n "$NEW_IDS" ]; then
  printf '%s\n' "$NEW_IDS" | grep -v '^$' >> "$LEDGER" 2>/dev/null || true
fi

echo "🔎 Automatisch gefunden (locate(), kein Kommando nötig):"
printf '%s\n' "$LOCATE_CARD"
exit 0
