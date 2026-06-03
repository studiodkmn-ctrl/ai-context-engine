#!/usr/bin/env bash
# =============================================================================
# pii-warn.sh — UserPromptSubmit Hook (Option C: Block-Mode) v6.3
#
# Liest Hook-Input (JSON) von stdin:
#   {"session_id":"...","prompt":"...","hook_event_name":"UserPromptSubmit", ...}
#
# Verhalten:
#   - Placeholder ([P1], [MAIL_1] …) vorhanden → pass-through
#   - Rohe PII erkannt → BLOCK (exit 2) + Hinweis "Bitte 'ap: …' verwenden"
#   - Sonst: still exit 0.
# =============================================================================
set -uo pipefail

# Opt-in: PII-Schutz nur aktiv wenn Flag-Datei existiert
# Aktivieren: pii-on  |  Deaktivieren: pii-off
[ ! -f "$HOME/.ai-context/pii-mode" ] && exit 0

# Stdin einlesen BEVOR Heredoc stdin beansprucht
AI_ANON_HOOK_INPUT="$(cat 2>/dev/null || echo '')"
export AI_ANON_HOOK_INPUT

python3 - << 'PYEOF'
import json, re, os, sys

raw = os.environ.get("AI_ANON_HOOK_INPUT", "")
if not raw.strip():
    sys.exit(0)
try:
    data = json.loads(raw)
except Exception:
    sys.exit(0)

prompt = data.get("prompt", "") or ""
if not prompt:
    sys.exit(0)

# ── Pass-through: Platzhalter bereits vorhanden (ap: wurde verwendet) ──
if re.search(r'\[(?:P|ORT|TEL|MAIL|B|DAT|UHR|IBAN|FIRMA|PROJ)_?\d+\]', prompt):
    sys.exit(0)

# ── Raw-PII-Detection (case-insensitive wo sinnvoll) ──
patterns = [
    (r'\b[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}\b',            "E-Mail"),
    (r'\b[A-Z]{2}\d{2}(?:\s?\d{1,4}){4,9}\b',                            "IBAN"),
    (r'(?:\+\d{1,3}[\s\-\/]?)?\(?\d{3,5}\)?[\s\-\/]?\d{3,5}[\s\-\/]?\d{3,5}', "Telefon"),
    (r'(?i)(?:[a-zäöü][a-zäöüß\-\.]{1,25}\s){1,3}(?:gmbh|ag|ug|kg|ohg|gbr|e\.v\.|inc\.?|ltd\.?|llc|corp\.?|s\.a\.|bv|nv)\b', "Firma"),
    (r'(?i)\b\d{5}\s+[a-zäöü][a-zäöüß\-]{2,}', "Adresse"),
    (r'(?i)\b(?:herr|frau|hr\.|fr\.|dr\.|prof\.)\s+[a-zäöü][a-zäöüß\-]{2,}', "Personenname"),
    (r'(?i)\b\d+(?:[.,]\d+)*\s?(?:€|£|\$|eur|euro|usd|dollar|chf|gbp|pfund|yen|jpy)(?!\w)', "Betrag"),
    (r'(?i)\b(?:eur|euro|usd|dollar|chf|gbp|pfund|yen|jpy)\s?\d+(?:[.,]\d+)*(?!\w)', "Betrag"),
    (r'(?:€|\$|£)\s?\d+(?:[.,]\d{1,3})*(?:[.,]\d{2})?(?!\w)', "Betrag"),
]

hits = []
for pat, label in patterns:
    if re.search(pat, prompt):
        hits.append(label)

if not hits:
    sys.exit(0)

categories = ", ".join(sorted(set(hits)))

# BLOCK-Mode: stderr → User-sichtbare Meldung + Claude-Feedback
# exit 2 → Claude Code blockiert den Prompt
print(
    f"\033[1;31m🛑 Prompt blockiert — sensible Daten erkannt ({categories}).\033[0m\n"
    f"\033[1;33m   Claude hat deinen Prompt nicht gesehen.\033[0m\n"
    f"\033[0;36m   → Eingabe erneut mit Prefix:\033[0m \033[1;32map: <dein-Text>\033[0m\n"
    f"\033[0;37m     (PII wird lokal durch [FIRMA_1], [P1] … ersetzt, bevor Claude sie liest.)\033[0m",
    file=sys.stderr
)

sys.exit(2)
PYEOF
