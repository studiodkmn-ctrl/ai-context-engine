#!/usr/bin/env bash
# =============================================================================
# ai-session-log.sh — Multi-Session Token-Tracking für AI Context v6.0
#
# Usage:
#   ai-session-log.sh append <project_dir> <tokens> <domain>
#   ai-session-log.sh stats [--week|--month|--all]
#
# Log-Format (JSONL): {"ts":"2026-04-13T10:30:00Z","project":"myapp","tokens":310,"domain":"backend"}
# =============================================================================
set -euo pipefail

GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; BOLD='\033[1m'; NC='\033[0m'

LOG_FILE="${HOME}/.ai-context/.session_log.jsonl"
mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true

MODE="${1:-}"

# ---- APPEND Modus ----
if [ "$MODE" = "append" ]; then
  PROJECT="${2:-unknown}"
  TOKENS="${3:-0}"
  DOMAIN="${4:-project}"
  TOKENS="${TOKENS//[^0-9]/}"   # Integer-Sanitize
  TOKENS=${TOKENS:-0}
  TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  PROJECT_NAME=$(basename "$PROJECT")

  # Nur appendieren wenn sinnvoll
  [ "$TOKENS" -lt 10 ] && exit 0

  printf '{"ts":"%s","project":"%s","tokens":%s,"domain":"%s"}\n' \
    "$TS" "$PROJECT_NAME" "$TOKENS" "$DOMAIN" >> "$LOG_FILE"
  exit 0
fi

# ---- STATS Modus ----
if [ "$MODE" = "stats" ] || [ -z "$MODE" ]; then
  PERIOD="${2:---week}"

  if [ ! -f "$LOG_FILE" ]; then
    echo -e "${YELLOW}Noch keine Session-Historie vorhanden.${NC}"
    echo -e "   Log-Datei: $LOG_FILE"
    exit 0
  fi

  python3 - "$LOG_FILE" "$PERIOD" << 'PYEOF'
import json, sys, pathlib
from datetime import datetime, timedelta, timezone
from collections import defaultdict

log = pathlib.Path(sys.argv[1])
period = sys.argv[2]

now = datetime.now(timezone.utc)
cutoff = {
    "--week":  now - timedelta(days=7),
    "--month": now - timedelta(days=30),
    "--all":   datetime.min.replace(tzinfo=timezone.utc),
}.get(period, now - timedelta(days=7))

period_label = {"--week": "letzte 7 Tage", "--month": "letzte 30 Tage", "--all": "alle Zeit"}[period]

sessions = []
for line in log.read_text(encoding='utf-8').splitlines():
    line = line.strip()
    if not line:
        continue
    try:
        e = json.loads(line)
        ts = datetime.fromisoformat(e["ts"].replace("Z", "+00:00"))
        if ts >= cutoff:
            sessions.append(e)
    except (json.JSONDecodeError, KeyError, ValueError):
        continue

if not sessions:
    print(f"\033[1;33mKeine Sessions im Zeitraum '{period_label}'.\033[0m")
    sys.exit(0)

total_tokens = sum(s.get("tokens", 0) for s in sessions)
# Ersparnis-Faktor: ohne System braucht Claude ~6.5× mehr Tokens (Full-Codebase-Reads)
baseline = total_tokens * 6.5
saved = baseline - total_tokens

# Kosten-Schätzung: $3/M Input-Tokens (Sonnet)
cost = total_tokens * 3 / 1_000_000

# Pro Projekt + Domain
by_project = defaultdict(int)
by_domain  = defaultdict(int)
for s in sessions:
    by_project[s.get("project", "?")] += s.get("tokens", 0)
    by_domain[s.get("domain", "?")]   += s.get("tokens", 0)

BOLD = "\033[1m"; GREEN = "\033[0;32m"; CYAN = "\033[0;36m"; NC = "\033[0m"

print(f"\n{BOLD}📊 AI Context — Session-Statistik ({period_label}){NC}\n")
print(f"  Sessions:           {len(sessions)}")
print(f"  {GREEN}Tokens gesamt:      ~{total_tokens:,}{NC}")
print(f"  {GREEN}Kosten (Input):     ~${cost:.3f}{NC}")
print(f"  {GREEN}Ersparnis geschätzt: ~{int(saved):,} Tokens (vs. ohne System){NC}\n")

print(f"  {CYAN}Top Projekte:{NC}")
for proj, tok in sorted(by_project.items(), key=lambda x: -x[1])[:5]:
    print(f"    {proj:<20} {tok:>7,} Tokens")

print(f"\n  {CYAN}Top Domains:{NC}")
for dom, tok in sorted(by_domain.items(), key=lambda x: -x[1])[:5]:
    print(f"    {dom:<20} {tok:>7,} Tokens")
print()
PYEOF
  exit 0
fi

# ---- Hilfe ----
echo -e "${BOLD}ai-session-log.sh — Multi-Session Token-Tracking${NC}"
echo ""
echo -e "${CYAN}Usage:${NC}"
echo -e "  ai-session-log.sh append <project_dir> <tokens> <domain>"
echo -e "  ai-session-log.sh stats [--week|--month|--all]"
echo ""
echo -e "${CYAN}Shortcut (nach Installation):${NC}"
echo -e "  ai-stats                    # letzte 7 Tage"
echo -e "  ai-stats --month"
echo -e "  ai-stats --all"
