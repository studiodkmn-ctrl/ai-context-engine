#!/usr/bin/env bash
# =============================================================================
# auto-update-all.sh — Global Auto-Update: alle registrierten Projekte → v7.0
#
# Liest alle Projekte aus ~/.ai-context/projects/*.meta.json, prüft ob sie
# noch existieren, und ruft für jedes lebende Projekt migrate.sh auf (die
# additive v5.x/v6.x→v7-Migration — dieselbe Logik wie bei manueller
# Einzelprojekt-Migration, nur automatisiert über alle Projekte hinweg).
#
# migrate.sh fasst NUR _ai_context/**, .claude/settings.json, hooks/** an —
# nie Quellcode, nie _gotchas.md/decisions.md/_quick_facts.md-Inhalte, nie
# git (kein add/commit). Bereits vorhandene uncommittete Änderungen im
# Zielprojekt bleiben unangetastet liegen.
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
MIGRATE_SCRIPT="$STORE/migrate.sh"

DRY=false
[ "${1:-}" = "--dry" ] && DRY=true

echo ""
echo -e "${BOLD}🔄 AI Context — Global Auto-Update → v7.0${NC}"
echo -e "${DIM}Template: $TEMPLATE${NC}"
$DRY && echo -e "${YELLOW}(Dry-Run — kein Schreiben)${NC}"
echo ""

# ---- Voraussetzungen ----
if [ ! -d "$TEMPLATE/scripts" ]; then
  echo -e "${RED}❌ Globales Template nicht gefunden: $TEMPLATE/scripts${NC}"
  echo -e "   Führe zuerst aus: bash ~/.ai-context/install.sh"
  exit 1
fi

if [ ! -f "$MIGRATE_SCRIPT" ]; then
  echo -e "${RED}❌ migrate.sh fehlt im globalen Store: $MIGRATE_SCRIPT${NC}"
  echo -e "   install.sh erneut ausführen: bash /pfad/zu/ai-context-v7/install.sh"
  exit 1
fi

for required in ai-context-registry.sh ai-context-doctor.sh ai-symptom-router.sh; do
  if [ ! -f "$TEMPLATE/scripts/$required" ]; then
    echo -e "${RED}❌ $required fehlt im globalen Template${NC}"
    echo -e "   install.sh erneut ausführen, um das Template zu aktualisieren."
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

# ---- Update-Funktion: pro Projekt migrate.sh aufrufen ----
UPDATED=0
FAILED=0
declare -a FAILED_PROJECTS=()

update_project() {
  local proj_path="$1"
  local proj_name="$2"

  echo -e "${CYAN}▶ $proj_name${NC} ${DIM}($proj_path)${NC}"

  # Transparenz: vorhandene uncommittete Änderungen zeigen (nicht blockierend —
  # migrate.sh fasst nur _ai_context/**, .claude/settings.json, hooks/** an,
  # nie Quellcode, daher ist ein "dirty" Arbeitsverzeichnis hier ungefährlich).
  if git -C "$proj_path" rev-parse --is-inside-work-tree > /dev/null 2>&1; then
    local dirty_count
    dirty_count=$(git -C "$proj_path" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
    [ "${dirty_count:-0}" -gt 0 ] && \
      echo -e "   ${DIM}ℹ  $dirty_count uncommittete Änderung(en) im Projekt — bleiben unangetastet${NC}"
  fi

  if $DRY; then
    echo -e "   ${DIM}[dry] würde migrate.sh ausführen (Scripts, drawers.yaml, scripts/lib/,${NC}"
    echo -e "   ${DIM}[dry] Registry-Rescan mit Frische-Feldern, SessionStart-Hook)${NC}"
    echo ""
    return
  fi

  local log
  log=$(cd "$proj_path" && bash "$MIGRATE_SCRIPT" 2>&1)
  local exit_code=$?

  if [ "$exit_code" -eq 0 ]; then
    echo -e "   ${GREEN}✅ migriert auf v7.0${NC}"
    # Kurzstatus aus dem migrate.sh-Log extrahieren
    echo "$log" | grep -E "drawers\.yaml|registry\.yaml.*gescannt|scripts/lib" | sed 's/^/   /'
    UPDATED=$((UPDATED + 1))
  else
    echo -e "   ${RED}❌ migrate.sh fehlgeschlagen (exit $exit_code)${NC}"
    echo "$log" | tail -5 | sed 's/^/   /'
    FAILED=$((FAILED + 1))
    FAILED_PROJECTS+=("$proj_name")
  fi
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
  echo -e "${BOLD}${GREEN}  ✅ $UPDATED Projekte auf v7.0 migriert${NC}"
  if [ "$FAILED" -gt 0 ]; then
    echo -e "   ${RED}❌ $FAILED fehlgeschlagen: ${FAILED_PROJECTS[*]}${NC}"
  fi
fi
echo -e "${BOLD}${GREEN}═══════════════════════════════════════════════════${NC}"
echo ""
echo -e "${BOLD}Was jetzt tun:${NC}"
echo -e "  Nichts zwingend — alles ist additiv und unkommittiert liegen geblieben."
echo -e "  Pro Projekt bei Gelegenheit: ${CYAN}git diff _ai_context/ .claude/${NC} prüfen und committen."
echo -e "  ${CYAN}_ai_context/drawers.yaml${NC} wurde mit generischen Globs angelegt — bei"
echo -e "  Bedarf an die echte Projektstruktur anpassen (Next.js-Defaults als Startpunkt)."
echo ""
