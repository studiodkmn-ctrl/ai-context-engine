#!/usr/bin/env bash
# =============================================================================
# auto-update-all.sh — Global Auto-Update: alle registrierten Projekte → v6.6
#
# Liest alle Projekte aus ~/.ai-context/projects/*.meta.json,
# prüft ob sie noch existieren, und pushed die neuen v6.6 Scripts:
#   - ai-symbol-map.sh        → _ai_context/scripts/
#   - ai-interface-snapshot.sh → _ai_context/scripts/
#   - ai-session-prep.sh      → _ai_context/scripts/ (v6.6 Integration)
#   - hot_paths.md            → _ai_context/ (nur wenn noch nicht vorhanden)
#   - _ai_index.md Fokus-Sektion → wenn noch nicht vorhanden
#
# Nach dem Kopieren: symbol-map + interface-snapshot einmalig generieren.
#
# Usage:
#   bash ~/.ai-context/auto-update-all.sh         # Alle registrierten Projekte
#   bash ~/.ai-context/auto-update-all.sh --dry   # Nur zeigen, nichts schreiben
# =============================================================================
set -euo pipefail

GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'
BOLD='\033[1m'; RED='\033[0;31m'; DIM='\033[2m'; NC='\033[0m'

STORE="$HOME/.ai-context"
TEMPLATE="$STORE/_ai_context_template"
PROJECTS_DIR="$STORE/projects"

DRY=false
[ "${1:-}" = "--dry" ] && DRY=true

echo ""
echo -e "${BOLD}🔄 AI Context — Global Auto-Update → v6.6${NC}"
echo -e "${DIM}Template: $TEMPLATE${NC}"
$DRY && echo -e "${YELLOW}(Dry-Run — kein Schreiben)${NC}"
echo ""

# ---- Voraussetzungen ----
if [ ! -d "$TEMPLATE/scripts" ]; then
  echo -e "${RED}❌ Globales Template nicht gefunden: $TEMPLATE/scripts${NC}"
  echo -e "   Führe zuerst aus: bash ~/.ai-context/setup_ai_context.sh"
  exit 1
fi

for required in ai-symbol-map.sh ai-interface-snapshot.sh ai-session-prep.sh; do
  if [ ! -f "$TEMPLATE/scripts/$required" ]; then
    echo -e "${RED}❌ $required fehlt im globalen Template${NC}"
    echo -e "   Kopiere es manuell: cp /path/to/ai-context-v6.6/_ai_context_template/scripts/$required $TEMPLATE/scripts/"
    exit 1
  fi
done

# ---- Projekte sammeln ----
declare -a LIVE_PROJECTS=()
declare -a SKIP_PROJECTS=()

while IFS= read -r meta; do
  [ -f "$meta" ] || continue
  path=$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d.get('path',''))" "$meta" 2>/dev/null || echo "")
  name=$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d.get('project','?'))" "$meta" 2>/dev/null || echo "?")
  [ -z "$path" ] && continue
  if [ -d "$path/_ai_context/scripts" ]; then
    LIVE_PROJECTS+=("$path|$name")
  else
    SKIP_PROJECTS+=("$path|$name")
  fi
done < <(find "$PROJECTS_DIR" -name ".meta.json" 2>/dev/null)

echo -e "${BOLD}Projekte gefunden:${NC}"
echo -e "  ${GREEN}Aktiv:${NC}    ${#LIVE_PROJECTS[@]}"
echo -e "  ${DIM}Übersprungen: ${#SKIP_PROJECTS[@]} (Pfad nicht vorhanden)${NC}"
echo ""

if [ ${#LIVE_PROJECTS[@]} -eq 0 ]; then
  echo -e "${YELLOW}Keine aktiven Projekte registriert.${NC}"
  exit 0
fi

# ---- Update-Funktion ----
UPDATED=0
SKIPPED=0
GENERATED=0

update_project() {
  local proj_path="$1"
  local proj_name="$2"
  local scripts_dir="$proj_path/_ai_context/scripts"
  local context_dir="$proj_path/_ai_context"
  local idx_dir="$context_dir/_idx"

  echo -e "${CYAN}▶ $proj_name${NC} ${DIM}($proj_path)${NC}"

  if $DRY; then
    echo -e "   ${DIM}[dry] ai-symbol-map.sh, ai-interface-snapshot.sh, ai-session-prep.sh${NC}"
    echo -e "   ${DIM}[dry] hot_paths.md (wenn fehlt), _idx/ erstellen, Symbole generieren${NC}"
    return
  fi

  # 1. Scripts kopieren (immer — neueste Version)
  cp "$TEMPLATE/scripts/ai-symbol-map.sh"         "$scripts_dir/"
  cp "$TEMPLATE/scripts/ai-interface-snapshot.sh" "$scripts_dir/"
  cp "$TEMPLATE/scripts/ai-session-prep.sh"        "$scripts_dir/"
  chmod +x "$scripts_dir/ai-symbol-map.sh" \
            "$scripts_dir/ai-interface-snapshot.sh" \
            "$scripts_dir/ai-session-prep.sh"
  echo -e "   ${GREEN}✅ Scripts kopiert${NC} (symbol-map, interface-snapshot, session-prep)"

  # 2. hot_paths.md (nur wenn noch nicht vorhanden — ist manuell)
  if [ ! -f "$context_dir/hot_paths.md" ] && [ -f "$TEMPLATE/hot_paths.md" ]; then
    cp "$TEMPLATE/hot_paths.md" "$context_dir/hot_paths.md"
    # Projektname eintragen
    sed -i.bak "s/\[PROJECT_NAME\]/$proj_name/g" "$context_dir/hot_paths.md" && \
      rm -f "$context_dir/hot_paths.md.bak" 2>/dev/null || true
    echo -e "   ${GREEN}✅ hot_paths.md${NC} angelegt (Template — bitte manuell befüllen)"
  else
    echo -e "   ${DIM}⏭  hot_paths.md bereits vorhanden${NC}"
  fi

  # 3. _ai_index.md — Fokus-Sektion einfügen wenn noch nicht vorhanden
  local idx_file="$context_dir/_ai_index.md"
  if [ -f "$idx_file" ] && ! grep -q "Aktueller Fokus" "$idx_file" 2>/dev/null; then
    python3 - "$idx_file" "$proj_name" << 'PYEOF'
import sys, pathlib, re

idx_path = pathlib.Path(sys.argv[1])
proj_name = sys.argv[2]
content = idx_path.read_text(encoding='utf-8')

fokus_block = """## ⚡ Aktueller Fokus
```
Fokus:          [Was gerade aktiv entwickelt wird]
Seit:           [DATE]
Letzter Commit: [Kurzbeschreibung]
Nächstes:       [Was als nächstes ansteht]
```
> REGEL: Diesen Block bei jedem Commit aktuell halten — verhindert 10-Minuten-Orientierungsphase.

"""

# Einfügen nach der ersten Zeile (## Projekt oder ## Übersicht)
target = re.search(r'^## (Projekt|Übersicht|Overview)', content, re.MULTILINE)
if target:
    pos = target.start()
    new_content = content[:pos] + fokus_block + content[pos:]
else:
    # Fallback: nach der Header-Zeile (>)
    m = re.search(r'^>.*\n', content, re.MULTILINE)
    pos = m.end() if m else 0
    new_content = content[:pos] + '\n' + fokus_block + content[pos:]

idx_path.write_text(new_content, encoding='utf-8')
print("ok")
PYEOF
    echo -e "   ${GREEN}✅ _ai_index.md${NC} Fokus-Sektion hinzugefügt"
  else
    echo -e "   ${DIM}⏭  _ai_index.md Fokus-Sektion bereits vorhanden${NC}"
  fi

  # 4. _idx/ Verzeichnis + Tabellen-Einträge in _ai_index.md
  mkdir -p "$idx_dir"

  # _idx/symbols.md und _idx/interfaces.md Einträge in Datei-Tabelle einfügen wenn fehlen
  if [ -f "$idx_file" ] && ! grep -q "symbols.md" "$idx_file" 2>/dev/null; then
    python3 - "$idx_file" << 'PYEOF'
import sys, pathlib, re
idx_path = pathlib.Path(sys.argv[1])
content = idx_path.read_text(encoding='utf-8')
new_rows = (
    "| `hot_paths.md` | Kritische Runtime-Invarianten (max 6) | 🟢 | — |\n"
    "| `_idx/symbols.md` | Symbol-Map mit Zeilennummern (auto-gen) | 🟢 | — |\n"
    "| `_idx/interfaces.md` | Interface/Type-Snapshot (auto-gen) | 🟢 | — |\n"
)
# Suche letzte Tabellenzeile vor "## 🗂️ Domain-Router" oder "## ⚡"
m = re.search(r'(\| `HANDOFF\.md`[^\n]*\n)', content)
if m:
    pos = m.end()
    content = content[:pos] + new_rows + content[pos:]
    idx_path.write_text(content, encoding='utf-8')
PYEOF
  fi

  # 5. Symbol-Map + Interface-Snapshot einmalig generieren
  echo -e "   ${CYAN}⟳  Generiere Symbol-Map + Interface-Snapshot...${NC}"
  (cd "$proj_path" && bash "$scripts_dir/ai-symbol-map.sh" 2>/dev/null || true)
  (cd "$proj_path" && bash "$scripts_dir/ai-interface-snapshot.sh" 2>/dev/null || true)

  if [ -f "$idx_dir/symbols.md" ]; then
    sym_count=$(grep -c "^  " "$idx_dir/symbols.md" 2>/dev/null || echo "?")
    echo -e "   ${GREEN}✅ symbols.md${NC} (~$sym_count Symbole)"
    GENERATED=$((GENERATED + 1))
  fi
  if [ -f "$idx_dir/interfaces.md" ]; then
    iface_count=$(grep -cE "^[A-Za-z]" "$idx_dir/interfaces.md" 2>/dev/null || echo "?")
    echo -e "   ${GREEN}✅ interfaces.md${NC} (~$iface_count Typen)"
  fi

  UPDATED=$((UPDATED + 1))
  echo ""
}

# ---- Alle Projekte updaten ----
for entry in "${LIVE_PROJECTS[@]}"; do
  proj_path="${entry%%|*}"
  proj_name="${entry##*|}"
  update_project "$proj_path" "$proj_name"
done

# ---- Summary ----
echo -e "${BOLD}${GREEN}═══════════════════════════════════════════════════${NC}"
if $DRY; then
  echo -e "${BOLD}${YELLOW}  Dry-Run: ${#LIVE_PROJECTS[@]} Projekte würden geupdated${NC}"
else
  echo -e "${BOLD}${GREEN}  ✅ $UPDATED Projekte auf v6.6 geupdated${NC}"
  echo -e "${BOLD}${GREEN}     $GENERATED Symbol-Maps generiert${NC}"
fi
echo -e "${BOLD}${GREEN}═══════════════════════════════════════════════════${NC}"
echo ""
echo -e "${BOLD}Was jetzt tun:${NC}"
echo -e "  1. ${CYAN}hot_paths.md${NC} in jedem Projekt mit Runtime-Invarianten befüllen"
echo -e "  2. ${CYAN}_ai_context/_ai_index.md${NC} → Fokus-Block aktuell halten"
echo -e "  3. Symbol-Map wird automatisch bei jedem Session-Start regeneriert"
echo ""
