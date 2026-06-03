#!/usr/bin/env bash
# =============================================================================
# ai-context-migrate-priorities.sh — Einmalige Migration zu v5.2
#
# Fügt P: 2 (neutraler Default) zu allen bestehenden Einträgen hinzu
# die noch kein P: Feld haben. Rückwärtskompatibel — bereits vorhandene
# P: Werte werden nicht überschrieben.
#
# Usage: bash _ai_context/scripts/ai-context-migrate-priorities.sh
#        bash _ai_context/scripts/ai-context-migrate-priorities.sh --dry-run
# =============================================================================
set -euo pipefail

CONTEXT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DRY_RUN=false
[ "${1:-}" = "--dry-run" ] && DRY_RUN=true

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

echo -e "${CYAN}🔄 Migration zu v5.2 Priority-Format${NC}"
$DRY_RUN && echo -e "${YELLOW}   (Dry-Run — keine Änderungen)${NC}"
echo ""

# Dateien die migriert werden sollen
MIGRATE_FILES=(
  "_gotchas.md"
  "debug_patterns.md"
  "security.md"
  "testing.md"
)

TOTAL_MIGRATED=0

for fname in "${MIGRATE_FILES[@]}"; do
  fpath="$CONTEXT_DIR/$fname"
  [ ! -f "$fpath" ] && continue

  MIGRATED=$(python3 - "$fpath" "$DRY_RUN" << 'PYEOF'
import re, sys, pathlib

fpath = pathlib.Path(sys.argv[1])
dry_run = sys.argv[2].lower() == 'true'

content = fpath.read_text(encoding='utf-8')

# Finde ``` Blöcke mit ID: oder RULE: als erste Zeile
block_pattern = re.compile(r'(```\s*\n)((?:ID:|RULE:)[^\n]+\n)([\s\S]*?)(```)', re.MULTILINE)

count = 0
def add_priority_if_missing(m):
    global count
    open_fence = m.group(1)
    first_line = m.group(2)   # "ID: foo\n" oder "RULE: bar\n"
    body = m.group(3)
    close_fence = m.group(4)

    # Prüfe ob P: bereits vorhanden (in den ersten 5 Zeilen des Blocks)
    block_head = first_line + body[:200]
    if re.search(r'\nP:\s*[123]', block_head):
        return m.group(0)  # Bereits vorhanden → unverändert

    # P: 2 nach der ersten Zeile (ID:/RULE:) einfügen
    new_body = 'P: 2\n' + body
    count += 1
    return open_fence + first_line + new_body + close_fence

new_content = block_pattern.sub(add_priority_if_missing, content)

if count > 0 and not dry_run:
    fpath.write_text(new_content, encoding='utf-8')

print(count)
PYEOF
)

  if [ "${MIGRATED:-0}" -gt 0 ]; then
    echo -e "  ${GREEN}✅ $fname: $MIGRATED Einträge auf P: 2 gesetzt${NC}"
    TOTAL_MIGRATED=$(( TOTAL_MIGRATED + MIGRATED ))
  else
    echo -e "  ℹ️  $fname: keine Migration nötig (alle Einträge haben bereits P:)"
  fi
done

echo ""
if [ "$TOTAL_MIGRATED" -gt 0 ]; then
  if $DRY_RUN; then
    echo -e "${YELLOW}Dry-Run: $TOTAL_MIGRATED Einträge würden auf P: 2 gesetzt${NC}"
    echo -e "Ohne --dry-run ausführen um zu migrieren."
  else
    echo -e "${GREEN}✅ Migration abgeschlossen: $TOTAL_MIGRATED Einträge auf P: 2 gesetzt${NC}"
    echo ""
    echo -e "Nächste Schritte:"
    echo -e "  1. Wichtige Einträge manuell auf P: 1 hochstufen"
    echo -e "  2. Nice-to-Know Einträge auf P: 3 setzen"
    echo -e "  3. P: 1 = niemals löschen | P: 3 = zuerst archiviert"
  fi
else
  echo -e "${GREEN}✅ Alle Dateien bereits im v5.2 Format${NC}"
fi
