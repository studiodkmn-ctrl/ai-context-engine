#!/usr/bin/env bash
# =============================================================================
# ai-context-drawer.sh — Automatisches Schubladen-System (v5.2)
#
# Überwacht Overflow-Bedingungen und erstellt Schubladen autonom:
#   - _gotchas.md P3-Einträge > 5 → verschiebt in _gotchas_archive.md
#   - frontend/components.md > 80 Zeilen → splitte in _core + _extended
#   - backend/endpoints.md > 80 Zeilen → splitte analog
#   - Aktualisiert _ai_index.md mit Schubladen-Pointern
#
# Wird automatisch nach jedem Commit (post-commit Hook) aufgerufen.
# Kann auch manuell ausgeführt werden: bash _ai_context/scripts/ai-context-drawer.sh
# =============================================================================
set -euo pipefail

CONTEXT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INDEX_FILE="$CONTEXT_DIR/_ai_index.md"
LIB_DIR="$CONTEXT_DIR/scripts/lib"
DRAWERS_FILE="$CONTEXT_DIR/drawers.yaml"
TODAY=$(date +"%Y-%m-%d")

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

DRAWERS_CREATED=0

# ---- Funktion: P3-Gotchas in Archiv verschieben ----
archive_p3_gotchas() {
  local src="$CONTEXT_DIR/_gotchas.md"
  local archive="$CONTEXT_DIR/_gotchas_archive.md"
  [ ! -f "$src" ] && return

  python3 - "$src" "$archive" "$TODAY" << 'PYEOF'
import re, sys, pathlib

src_path, archive_path, today = sys.argv[1], pathlib.Path(sys.argv[2]), sys.argv[3]
content = pathlib.Path(src_path).read_text(encoding='utf-8')

# Extrahiere alle Code-Block-Einträge
block_pattern = re.compile(r'```\s*\n(?:ID:|RULE:)[\s\S]*?```', re.MULTILINE)
all_blocks = block_pattern.findall(content)

def get_priority(block):
    m = re.search(r'\nP:\s*([123])', block)
    return int(m.group(1)) if m else 2

p3_blocks = [b for b in all_blocks if get_priority(b) == 3]
keep_blocks = [b for b in all_blocks if get_priority(b) != 3]

if not p3_blocks:
    print("NO_P3")
    sys.exit(0)

# Erstelle oder aktualisiere Archiv
if archive_path.exists():
    archive_content = archive_path.read_text(encoding='utf-8')
else:
    archive_content = f"""# 📦 Gotchas Archiv — Ausgelagerte P3-Einträge
> Erstellt: {today}
> Nur bei spezifischen Problemen laden. Im normalen Workflow ignorieren.
> Lade mit: `_gotchas_archive.md` | Letzte Archivierung: {today}

## Archiviert

"""

# Füge P3-Blöcke am Anfang des Archivs ein (nach dem Header)
archiv_section_match = re.search(r'^## Archiviert\s*\n', archive_content, re.MULTILINE)
insert_pos = archiv_section_match.end() if archiv_section_match else len(archive_content)

new_archive_entries = "\n".join(p3_blocks) + "\n\n"
archive_content = archive_content[:insert_pos] + new_archive_entries + archive_content[insert_pos:]

# Update "Letzte Archivierung" Datum
archive_content = re.sub(r'Letzte Archivierung: \d{4}-\d{2}-\d{2}', f'Letzte Archivierung: {today}', archive_content)

archive_path.write_text(archive_content, encoding='utf-8')

# Schreibe bereinigte Hauptdatei zurück
first_match = block_pattern.search(content)
header = content[:first_match.start()] if first_match else ""
last_match = list(block_pattern.finditer(content))[-1]
footer = content[last_match.end():]

pathlib.Path(src_path).write_text(header + "\n".join(keep_blocks) + footer, encoding='utf-8')
print(f"ARCHIVED:{len(p3_blocks)}")
PYEOF
}

# ---- Funktion: Domain-Datei aufteilen wenn > threshold Zeilen ----
split_domain_file() {
  local rel_file="$1"   # z.B. "frontend/components.md"
  local threshold="${2:-80}"
  local abs_file="$CONTEXT_DIR/$rel_file"
  [ ! -f "$abs_file" ] && return

  local line_count
  line_count=$(wc -l < "$abs_file")
  [ "$line_count" -le "$threshold" ] && return

  local base="${rel_file%.md}"
  local dir
  dir=$(dirname "$abs_file")
  local fname
  fname=$(basename "$abs_file" .md)
  local core_path="$dir/${fname}_core.md"
  local ext_path="$dir/${fname}_extended.md"
  local core_rel="${base}_core.md"
  local ext_rel="${base}_extended.md"

  # Bereits gesplittet?
  [ -f "$core_path" ] && return

  local midpoint=$(( line_count / 2 ))

  # Core: erste Hälfte (kritische/häufige Einträge)
  {
    echo "# $(head -1 "$abs_file" | sed 's/#//' | xargs) — Core"
    echo "> Automatisch gesplittet aus \`$rel_file\` ($line_count Zeilen > $threshold)."
    echo "> Extended-Einträge: \`$ext_rel\`"
    echo ""
    tail -n +2 "$abs_file" | head -"$midpoint"
  } > "$core_path"

  # Extended: zweite Hälfte (seltenere Fälle)
  {
    echo "# $(head -1 "$abs_file" | sed 's/#//' | xargs) — Extended"
    echo "> Erweiterte Einträge. Core: \`$core_rel\`"
    echo ""
    tail -n +"$midpoint" "$abs_file"
  } > "$ext_path"

  echo -e "  ${CYAN}↳ Split: $rel_file → ${fname}_core.md + ${fname}_extended.md${NC}"
  DRAWERS_CREATED=$(( DRAWERS_CREATED + 1 ))

  # Domain-Index aktualisieren (falls vorhanden)
  local domain
  domain=$(dirname "$rel_file")
  local idx_file="$CONTEXT_DIR/_idx/${domain}.md"
  if [ -f "$idx_file" ]; then
    local escaped
    escaped=$(echo "$rel_file" | sed 's/\//\\\//g')
    local core_escaped
    core_escaped=$(echo "$core_rel" | sed 's/\//\\\//g')
    local ext_escaped
    ext_escaped=$(echo "$ext_rel" | sed 's/\//\\\//g')
    # Ersetze alten Eintrag durch zwei neue
    sed -i.bak "s#| \`${escaped}\` | ✅ | .* |#| \`${core_escaped}\` | ✅ | Core (Split) |\n| \`${ext_escaped}\` | ✅ | Extended (bei Bedarf laden) |#" "$idx_file" 2>/dev/null && rm -f "${idx_file}.bak"
  fi
}

# ---- Aktualisiere _ai_index.md Schubladen-Sektion ----
update_index_drawers() {
  [ ! -f "$INDEX_FILE" ] && return

  # Sammle alle Archiv-Dateien
  local drawer_entries=""
  for archive_file in "$CONTEXT_DIR"/_*_archive.md "$CONTEXT_DIR"/*/*_extended.md; do
    [ ! -f "$archive_file" ] && continue
    local rel
    rel="${archive_file#$CONTEXT_DIR/}"
    local desc
    desc=$(head -2 "$archive_file" | tail -1 | sed 's/^> //')
    drawer_entries="${drawer_entries}\n\`${rel}\`  ← ${desc}"
  done

  [ -z "$drawer_entries" ] && return

  local drawer_section
  printf -v drawer_section "## 📦 Schubladen (Archiv-Pointer)\n\`\`\`%b\`\`\`\n" "$drawer_entries"

  if grep -q "## 📦 Schubladen" "$INDEX_FILE" 2>/dev/null; then
    # Update existierende Sektion
    python3 - "$INDEX_FILE" "$drawer_section" << 'PYEOF'
import re, sys, pathlib
content = pathlib.Path(sys.argv[1]).read_text(encoding='utf-8')
new_section = sys.argv[2]
result = re.sub(r'## 📦 Schubladen[\s\S]*?(?=^##|\Z)', new_section + '\n', content, flags=re.MULTILINE)
pathlib.Path(sys.argv[1]).write_text(result, encoding='utf-8')
PYEOF
  else
    # Füge am Ende hinzu
    printf '\n%s' "$drawer_section" >> "$INDEX_FILE"
  fi
}

# ========== MAIN ==========
echo -e "${CYAN}🗂️  Schubladen-Check...${NC}"

# 1. P3-Gotchas archivieren (Trigger: > 5 P3-Einträge)
GOTCHAS_FILE="$CONTEXT_DIR/_gotchas.md"
if [ -f "$GOTCHAS_FILE" ]; then
  P3_COUNT=$(python3 -c "
import re, pathlib
c = pathlib.Path('$GOTCHAS_FILE').read_text(encoding='utf-8')
blocks = re.findall(r'\`\`\`\s*\n(?:ID:|RULE:)[\s\S]*?\`\`\`', c)
print(sum(1 for b in blocks if re.search(r'\nP:\s*3', b)))
" 2>/dev/null || echo "0")
  if [ "${P3_COUNT:-0}" -gt 5 ]; then
    echo -e "  ${YELLOW}P3-Gotchas: $P3_COUNT > 5 → Archiviere...${NC}"
    RESULT=$(archive_p3_gotchas 2>&1 || echo "ERROR")
    ARCHIVED=$(echo "$RESULT" | grep "ARCHIVED:" | cut -d: -f2 || echo "0")
    if [ "${ARCHIVED:-0}" -gt 0 ]; then
      echo -e "  ${GREEN}✅ $ARCHIVED P3-Einträge → _gotchas_archive.md${NC}"
      DRAWERS_CREATED=$(( DRAWERS_CREATED + 1 ))
    fi
  fi
fi

# 2. Übervolle Domain-Dateien splitten (Trigger: > 80 Zeilen)
# v7: Liste kommt aus drawers.yaml statt hartkodiert — fällt auf die alte
# v6.x-Liste zurück, falls noch kein Manifest existiert (Alt-Projekte vor v7).
if [ -f "$DRAWERS_FILE" ] && [ -f "$LIB_DIR/ctx.py" ]; then
  DRAWER_INDEXES=$(python3 "$LIB_DIR/ctx.py" list_drawer_indexes "$DRAWERS_FILE" 2>/dev/null || true)
else
  DRAWER_INDEXES=$'frontend/components.md\nfrontend/state.md\nbackend/endpoints.md\nbackend/database.md\nbackend/auth.md'
fi
while IFS= read -r check_file; do
  [ -n "$check_file" ] && split_domain_file "$check_file" 80
done <<< "$DRAWER_INDEXES"

# 3. _ai_index.md mit Schubladen-Pointern aktualisieren
if [ "$DRAWERS_CREATED" -gt 0 ]; then
  update_index_drawers
  echo -e "${GREEN}✅ $DRAWERS_CREATED Schubladen erstellt/aktualisiert${NC}"
else
  echo -e "${GREEN}✅ Kein Overflow — keine Schubladen nötig${NC}"
fi
