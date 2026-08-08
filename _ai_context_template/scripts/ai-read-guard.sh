#!/usr/bin/env bash
# =============================================================================
# ai-read-guard.sh — Duplicate-Read-Guard (PreToolUse-Hook auf "Read")
#
# Verhindert, dass eine im selben Session bereits gelesene, unveraenderte
# Datei erneut gelesen wird — reiner Token-Verlust, da der Inhalt bereits
# im Kontext steht. Blockt NIE einen neuen oder geaenderten Read.
#
# Vertrag (Claude Code PreToolUse-Hook):
#   stdin:  JSON {session_id, hook_event_name, tool_name, tool_input:{file_path}}
#   stdout: bei Ablehnung {"hookSpecificOutput":{"hookEventName":"PreToolUse",
#           "permissionDecision":"deny","permissionDecisionReason":"..."}}
#           sonst: kein Output.
#   exit:   immer 0 — Entscheidung geht ausschliesslich ueber stdout-JSON.
#
# Fail-open: jeder Fehler (kaputtes JSON, fehlende Datei, o.ae.) -> exit 0
# ohne Output, also normales Verhalten. Dieses Script darf NIE einen Read
# blockieren, den es nicht mit Sicherheit als exaktes Duplikat erkannt hat.
# =============================================================================
set -uo pipefail

CONTEXT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LEDGER_DIR="$CONTEXT_DIR/.session"

# WICHTIG: "python3 -" wuerde das Skript selbst von stdin lesen und damit
# mit dem JSON-Input kollidieren (der ebenfalls ueber stdin kommt). Daher
# das Skript in eine Temp-Datei schreiben und stdin unangetastet lassen.
GUARD_PY="$(mktemp -t aictx-readguard.XXXXXX.py)"
trap 'rm -f "$GUARD_PY"' EXIT

cat > "$GUARD_PY" << 'PYEOF'
import sys, json, hashlib, pathlib, re

ledger_dir = pathlib.Path(sys.argv[1])

try:
    payload = json.load(sys.stdin)
except Exception:
    sys.exit(0)

if payload.get("tool_name") != "Read":
    sys.exit(0)

file_path = (payload.get("tool_input") or {}).get("file_path")
session_id = payload.get("session_id") or "unknown"
if not file_path:
    sys.exit(0)

p = pathlib.Path(file_path)

skip_markers = ("_ai_context/", "_ai_context_template/", "/.git/")
posix = p.as_posix()
if any(m in posix for m in skip_markers):
    sys.exit(0)

try:
    data = p.read_bytes()
except Exception:
    sys.exit(0)

digest = hashlib.sha1(data).hexdigest()

safe_session = re.sub(r'[^a-zA-Z0-9_-]', '_', session_id)[:80] or "unknown"
ledger_dir.mkdir(parents=True, exist_ok=True)
ledger_path = ledger_dir / f"{safe_session}.reads.jsonl"

seen_hash = None
if ledger_path.exists():
    try:
        for line in ledger_path.read_text(encoding="utf-8").splitlines():
            if not line.strip():
                continue
            entry = json.loads(line)
            if entry.get("file") == str(p):
                seen_hash = entry.get("hash")
    except Exception:
        seen_hash = None

if seen_hash == digest:
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": (
                "Datei unveraendert seit letztem Read in dieser Session "
                "— Inhalt ist bereits im Kontext, kein erneuter Read noetig."
            ),
        }
    }))
    sys.exit(0)

try:
    with ledger_path.open("a", encoding="utf-8") as f:
        f.write(json.dumps({"file": str(p), "hash": digest}) + "\n")
except Exception:
    pass

sys.exit(0)
PYEOF

python3 "$GUARD_PY" "$LEDGER_DIR" 2>/dev/null || exit 0
exit 0
