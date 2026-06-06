#!/usr/bin/env bash
# =============================================================================
# ai-invariant-check.sh — Invariant Layer Check (v1.0)
#
# Prüft ob geänderte Dateien bekannte Invarianten berühren.
# Liest invariants.yaml und vergleicht gegen den aktuellen git-Status.
#
# Geeignet als pre-commit Hook oder manueller Check.
#
# Usage:
#   bash _ai_context/scripts/ai-invariant-check.sh           # staged + unstaged
#   bash _ai_context/scripts/ai-invariant-check.sh --staged  # nur staged
#   bash _ai_context/scripts/ai-invariant-check.sh --all     # alle geänderten
# =============================================================================
set -euo pipefail

CONTEXT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_DIR="$(cd "$CONTEXT_DIR/.." && pwd)"
INVARIANTS_FILE="$CONTEXT_DIR/invariants.yaml"

RED='\033[0;31m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
GREEN='\033[0;32m'

if [ ! -f "$INVARIANTS_FILE" ]; then
  echo "  (keine invariants.yaml — überspringe Invariant-Check)"
  exit 0
fi

MODE="${1:-}"
if [ "$MODE" = "--staged" ]; then
  CHANGED=$(cd "$PROJECT_DIR" && git diff --cached --name-only 2>/dev/null || true)
elif [ "$MODE" = "--all" ]; then
  CHANGED=$(cd "$PROJECT_DIR" && { git diff --name-only; git diff --cached --name-only; } 2>/dev/null | sort -u || true)
else
  CHANGED=$(cd "$PROJECT_DIR" && { git diff --name-only; git diff --cached --name-only; } 2>/dev/null | sort -u || true)
fi

if [ -z "$CHANGED" ]; then
  echo -e "${GREEN}  ✅ Keine geänderten Dateien — Invariant-Check übersprungen${NC}"
  exit 0
fi

# Python-basierter YAML-Parser und Matcher
CHECK_PY="$(mktemp -t aictx-inv.XXXXXX.py)"
trap 'rm -f "$CHECK_PY"' EXIT

cat > "$CHECK_PY" << 'PYEOF'
import sys, re, pathlib, os

invariants_file = pathlib.Path(sys.argv[1])
changed_files_raw = sys.argv[2]
symbols_file = pathlib.Path(sys.argv[3]) if len(sys.argv) > 3 else None
changed_files = [f.strip() for f in changed_files_raw.split('\n') if f.strip()]

# Lade used_in aus symbols.md: defining_file → set(caller_files)
# Format: ## `file.ts` → SYM-Zeile → USED-Zeile
file_callers = {}  # defining_file_basename → set of caller files
if symbols_file and symbols_file.exists():
    current_section = None
    for line in symbols_file.read_text(encoding='utf-8').splitlines():
        sec_m = re.match(r'^## `(.+)`', line)
        if sec_m:
            current_section = sec_m.group(1)
            if current_section not in file_callers:
                file_callers[current_section] = set()
        used_m = re.match(r'^\s+→ used in:\s*(.+)', line)
        if used_m and current_section:
            callers = [c.strip() for c in used_m.group(1).split('·') if c.strip()]
            file_callers[current_section].update(callers)

# Parse invariants.yaml
invariants = []
cur = None
for line in invariants_file.read_text(encoding='utf-8').splitlines():
    id_m = re.match(r'^\s+-\s+id:\s*(.+)', line)
    if id_m:
        if cur and cur.get('id'):
            invariants.append(cur)
        cur = {'id': id_m.group(1).strip(), 'level': 'hint', 'rule': '', 'scope': '*', 'depends': []}
        continue
    if not cur:
        continue
    lv = re.match(r'^\s+level:\s*(\w+)', line)
    if lv: cur['level'] = lv.group(1).strip(); continue
    rl = re.match(r'^\s+rule:\s*"([^"]+)"', line)
    if rl: cur['rule'] = rl.group(1); continue
    sc = re.match(r'^\s+scope:\s*"([^"]+)"', line)
    if sc: cur['scope'] = sc.group(1); continue
    dp = re.match(r'^\s+depends:\s*\[(.+)\]', line)
    if dp:
        refs = re.findall(r'"([^"]+)"', dp.group(1))
        cur['depends'].extend({'type': 'file', 'ref': r} for r in refs)
if cur and cur.get('id'):
    invariants.append(cur)

# Match changed files against invariant depends
BADGE = {'hard': '⚠ INVARIANTE (hard)', 'soft': '⚠  Invariante (soft)', 'hint': 'ℹ  Hinweis (hint)'}
hits = []
for inv in invariants:
    matched_by = []
    for cf in changed_files:
        base = os.path.basename(cf)
        for dep in inv['depends']:
            if dep['type'] == 'file':
                ref = dep['ref']
                if cf.endswith(ref) or ref.endswith(base) or base in ref or ref in cf:
                    matched_by.append(cf)
                    break
    if matched_by:
        hits.append((inv, matched_by))

if not hits:
    print("OK")
    sys.exit(0)

print(f"HITS:{len(hits)}")
for inv, files in hits:
    badge = BADGE.get(inv['level'], '?')
    print(f"{badge}: [{inv['id']}]")
    print(f"  Regel:  {inv['rule']}")
    print(f"  Scope:  {inv['scope']}")
    print(f"  Durch:  {', '.join(files[:3])}")
    # Statische Verifikation: welche Dateien rufen die Dependency-Files auf?
    # → Das sind die Enforcement-Points wo die Invariante geprüft werden muss
    enforce_points = set()
    for dep in inv['depends']:
        if dep['type'] == 'file':
            dep_key = dep['ref']  # z.B. "src/lib/auth.ts"
            for section_path, callers in file_callers.items():
                if dep_key.endswith(section_path) or section_path.endswith(dep_key) or dep_key in section_path:
                    enforce_points.update(callers)
    if enforce_points:
        pts = sorted(enforce_points)[:4]
        print(f"  Check:  {', '.join(pts)}")
    print()
PYEOF

SYMBOLS_FILE="$CONTEXT_DIR/_idx/symbols.md"
result=$(python3 "$CHECK_PY" "$INVARIANTS_FILE" "$CHANGED" "$SYMBOLS_FILE" 2>/dev/null)

if [ "$result" = "OK" ]; then
  echo -e "${GREEN}  ✅ Keine Invarianten berührt${NC}"
  exit 0
fi

echo -e "${CYAN}🔍 Invariant Check — $(basename "$PROJECT_DIR")${NC}"
echo ""

# Formatierte Ausgabe
while IFS= read -r line; do
  if [[ "$line" == *"INVARIANTE (hard)"* ]]; then
    echo -e "${RED}  $line${NC}"
  elif [[ "$line" == *"Invariante (soft)"* ]]; then
    echo -e "${YELLOW}  $line${NC}"
  elif [[ "$line" == HITS:* ]]; then
    count="${line#HITS:}"
    echo -e "  ${count} Invariante(n) berührt:\n"
  else
    echo "  $line"
  fi
done <<< "$result"

echo ""
echo -e "  ${CYAN}→ Prüfe ob die Regel noch gilt. Details: _ai_context/invariants.yaml${NC}"
