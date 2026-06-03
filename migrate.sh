#!/usr/bin/env bash
# =============================================================================
# migrate.sh — Additive Migration: AI Context v5.x → v6.5
#
# Aufruf aus dem Root des Ziel-Projekts:
#   bash /path/to/ai-context-v5.2/migrate.sh
#   bash ~/.ai-context/migrate.sh
#
# Was passiert:
#   1. Neue Scripts → _ai_context/scripts/
#   2. Skills       → .claude/skills/
#   3. Hooks patchen (post-commit, pii-warn.sh)
#   4. .claude/settings.json mergen (Doctor --session als erster Hook)
#   5. _interaction_map.md Placeholder anlegen (falls fehlt)
#   6. ai-context-doctor.sh --check ausführen
#
# Was NICHT angefasst wird:
#   _gotchas.md, debug_patterns.md, security.md, _quick_facts.md,
#   _SESSION.md, alle Domain-Dateien in backend/ frontend/
# =============================================================================
set -euo pipefail

GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'
BOLD='\033[1m'; RED='\033[0;31m'; NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_TEMPLATE="$SCRIPT_DIR/_ai_context_template"

echo ""
echo -e "${BOLD}🔄 AI Context — Migration → v6.5${NC}"
echo ""

# =============================================================================
# 1. Voraussetzungen prüfen
# =============================================================================

if [ ! -d "_ai_context/scripts" ]; then
  echo -e "${RED}❌ Kein AI Context v5+ Projekt gefunden.${NC}"
  echo -e "   Voraussetzung: _ai_context/scripts/ muss existieren."
  echo -e "   Script aus dem Root des Ziel-Projekts ausführen."
  exit 1
fi

if [ ! -d "$SRC_TEMPLATE/scripts" ]; then
  echo -e "${RED}❌ Quell-Template nicht gefunden: $SRC_TEMPLATE/scripts${NC}"
  echo -e "   migrate.sh muss aus dem ai-context-v5.2 Verzeichnis aufgerufen werden."
  exit 1
fi

# Bereits auf v6.5? Warnen, aber nicht abbrechen
if [ -f "_ai_context/scripts/ai-context-doctor.sh" ] && \
   [ -f "_ai_context/scripts/ai-context-map.sh" ] && \
   [ -f "_ai_context/scripts/ai-context-transfer.sh" ]; then
  echo -e "${YELLOW}⚠️  v6.5-Scripts bereits vorhanden — Migration aktualisiert trotzdem.${NC}"
  echo ""
fi

# Version anzeigen
if [ -f "VERSION" ]; then
  echo -e "   Projekt-Version: ${YELLOW}$(cat VERSION)${NC} → ${GREEN}6.5${NC}"
else
  echo -e "   AI Context v5.x erkannt → ${GREEN}v6.5${NC}"
fi
echo ""

# =============================================================================
# 2. Neue Scripts kopieren
# =============================================================================

echo -e "${CYAN}📜 Scripts installieren...${NC}"

NEW_SCRIPTS=(
  "ai-context-doctor.sh"
  "ai-context-map.sh"
  "ai-context-transfer.sh"
  "ai-impact-learn.sh"
  "ai-symptom-router.sh"
  "ai-verify.sh"
)

for script in "${NEW_SCRIPTS[@]}"; do
  src="$SRC_TEMPLATE/scripts/$script"
  dst="_ai_context/scripts/$script"
  if [ -f "$src" ]; then
    cp "$src" "$dst"
    chmod +x "$dst"
    echo -e "   ✅ $script (neu)"
  else
    echo -e "   ${YELLOW}⚠️  $script nicht im Template — übersprungen${NC}"
  fi
done

# Modifizierte Scripts aktualisieren (v6.5 bringt neue Sektionen)
UPDATED_SCRIPTS=(
  "ai-session-prep.sh"
  "ai-context-registry.sh"
  "ai-context-sync.sh"
  "ai-context-drawer.sh"
)

for script in "${UPDATED_SCRIPTS[@]}"; do
  src="$SRC_TEMPLATE/scripts/$script"
  dst="_ai_context/scripts/$script"
  if [ -f "$src" ] && [ -f "$dst" ]; then
    cp "$src" "$dst"
    chmod +x "$dst"
    echo -e "   🔄 $script (aktualisiert)"
  fi
done

# check_context_hash.sh liegt eine Ebene höher
if [ -f "$SRC_TEMPLATE/check_context_hash.sh" ] && [ -f "_ai_context/check_context_hash.sh" ]; then
  cp "$SRC_TEMPLATE/check_context_hash.sh" "_ai_context/check_context_hash.sh"
  chmod +x "_ai_context/check_context_hash.sh"
  echo -e "   🔄 check_context_hash.sh (aktualisiert)"
fi

echo ""

# =============================================================================
# 3. Skills kopieren
# =============================================================================

echo -e "${CYAN}🎯 Skills installieren...${NC}"

SKILLS_SRC="$SRC_TEMPLATE/.claude/skills"

if [ -d "$SKILLS_SRC" ]; then
  mkdir -p ".claude/skills"
  for skill_dir in "$SKILLS_SRC"/*/; do
    [ -d "$skill_dir" ] || continue
    skill_name="$(basename "$skill_dir")"
    mkdir -p ".claude/skills/$skill_name"
    if [ -f "$SKILLS_SRC/$skill_name/SKILL.md" ]; then
      cp "$SKILLS_SRC/$skill_name/SKILL.md" ".claude/skills/$skill_name/SKILL.md"
      echo -e "   ✅ /$skill_name"
    fi
  done
else
  echo -e "   ${YELLOW}⚠️  Keine Skills im Template gefunden${NC}"
fi

echo ""

# =============================================================================
# 4. Hooks patchen
# =============================================================================

echo -e "${CYAN}🪝 Hooks patchen...${NC}"

mkdir -p "hooks"

# 4a. post-commit ersetzen (Backup wenn geändert)
NEW_PC="$SCRIPT_DIR/hooks/post-commit"
if [ -f "$NEW_PC" ]; then
  if [ -f "hooks/post-commit" ]; then
    if ! diff -q "hooks/post-commit" "$NEW_PC" > /dev/null 2>&1; then
      cp "hooks/post-commit" "hooks/post-commit.bak"
      echo -e "   📦 Backup: hooks/post-commit.bak"
    fi
  fi
  cp "$NEW_PC" "hooks/post-commit"
  chmod +x "hooks/post-commit"
  echo -e "   ✅ hooks/post-commit (v6.5)"

  # .git/hooks/post-commit aktualisieren wenn es kein Symlink ist
  if [ -d ".git/hooks" ] && [ ! -L ".git/hooks/post-commit" ]; then
    cp "$NEW_PC" ".git/hooks/post-commit"
    chmod +x ".git/hooks/post-commit"
    echo -e "   ✅ .git/hooks/post-commit"
  fi
else
  echo -e "   ${YELLOW}⚠️  Kein post-commit im Quell-Verzeichnis — übersprungen${NC}"
fi

# 4b. pii-warn.sh kopieren (nur wenn noch nicht vorhanden)
NEW_PII="$SCRIPT_DIR/hooks/pii-warn.sh"
if [ -f "$NEW_PII" ]; then
  if [ ! -f "hooks/pii-warn.sh" ]; then
    cp "$NEW_PII" "hooks/pii-warn.sh"
    chmod +x "hooks/pii-warn.sh"
    echo -e "   ✅ hooks/pii-warn.sh (PII-Schutz, opt-in)"
  else
    echo -e "   ✅ hooks/pii-warn.sh bereits vorhanden"
  fi
fi

echo ""

# =============================================================================
# 5. .claude/settings.json mergen
# =============================================================================

echo -e "${CYAN}⚙️  .claude/settings.json mergen...${NC}"

SETTINGS=".claude/settings.json"
DOCTOR_CMD="[ -f _ai_context/scripts/ai-context-doctor.sh ] && bash _ai_context/scripts/ai-context-doctor.sh --session 2>&1 || true"
SESSION_CMD="[ -f _ai_context/scripts/ai-session-prep.sh ] && bash _ai_context/scripts/ai-session-prep.sh 2>&1 | awk '/^(🧠|✅|__AI_CTX__)/ || /Session bereit/ || /Kontext wird vorbereitet/' || true"
PII_CMD="if [ -f ~/.ai-context/hooks/pii-warn.sh ]; then bash ~/.ai-context/hooks/pii-warn.sh; fi"

mkdir -p ".claude"

if command -v python3 &>/dev/null; then
  python3 - "$SETTINGS" "$DOCTOR_CMD" "$SESSION_CMD" "$PII_CMD" << 'PYEOF'
import json, sys, pathlib

path      = pathlib.Path(sys.argv[1])
doctor_cmd  = sys.argv[2]
session_cmd = sys.argv[3]
pii_cmd     = sys.argv[4]

if path.exists():
    try:
        data = json.loads(path.read_text(encoding='utf-8'))
    except json.JSONDecodeError:
        print(f"   ⚠️  {path} ist kein valides JSON — Hooks manuell prüfen")
        sys.exit(0)
else:
    data = {}

hooks   = data.setdefault("hooks", {})
changed = False

# ---- SessionStart ----
groups      = hooks.setdefault("SessionStart", [])
has_doctor  = any(any("ai-context-doctor"  in h.get("command","") for h in g.get("hooks",[])) for g in groups)
has_session = any(any("ai-session-prep"    in h.get("command","") for h in g.get("hooks",[])) for g in groups)

if not has_doctor and not has_session:
    groups.insert(0, {"matcher": "", "hooks": [
        {"type": "command", "command": doctor_cmd},
        {"type": "command", "command": session_cmd},
    ]})
    changed = True
    print("   ✅ SessionStart: doctor --session + session-prep hinzugefügt")
elif not has_doctor:
    # session-prep vorhanden, doctor fehlt → als ersten Hook in erster Gruppe prepend
    target = groups[0] if groups else {"matcher": "", "hooks": []}
    target.setdefault("hooks", []).insert(0, {"type": "command", "command": doctor_cmd})
    if not groups:
        groups.insert(0, target)
    else:
        groups[0] = target
    changed = True
    print("   ✅ SessionStart: doctor --session als erster Hook eingefügt")
else:
    print("   ✅ SessionStart: doctor --session bereits vorhanden")

# ---- UserPromptSubmit ----
pii_groups = hooks.setdefault("UserPromptSubmit", [])
has_pii    = any(any("pii-warn" in h.get("command","") for h in g.get("hooks",[])) for g in pii_groups)
if not has_pii:
    pii_groups.append({"matcher": "", "hooks": [{"type": "command", "command": pii_cmd}]})
    changed = True
    print("   ✅ UserPromptSubmit: pii-warn.sh hinzugefügt")
else:
    print("   ✅ UserPromptSubmit: pii-warn.sh bereits vorhanden")

if changed:
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False), encoding='utf-8')
PYEOF
else
  echo -e "   ${YELLOW}⚠️  python3 nicht gefunden — settings.json manuell prüfen${NC}"
  echo -e "   Trage ein: Doctor-Hook vor session-prep im SessionStart-Array"
fi

echo ""

# =============================================================================
# 6. _interaction_map.md anlegen (Placeholder für ai-context-map.sh)
# =============================================================================

if [ ! -f "_ai_context/_interaction_map.md" ]; then
  MAP_TPL="$SRC_TEMPLATE/_interaction_map.md"
  if [ -f "$MAP_TPL" ]; then
    cp "$MAP_TPL" "_ai_context/_interaction_map.md"
    echo -e "${CYAN}🗺️  _ai_context/_interaction_map.md angelegt${NC}"
    echo -e "   Befüllen: ${CYAN}bash _ai_context/scripts/ai-context-map.sh${NC}"
    echo ""
  fi
fi

# =============================================================================
# 7. Health-Check
# =============================================================================

echo -e "${CYAN}🩺 Health-Check (ai-context-doctor --check)...${NC}"
echo ""

DOCTOR="_ai_context/scripts/ai-context-doctor.sh"
if [ -f "$DOCTOR" ]; then
  bash "$DOCTOR" --check || true
else
  echo -e "   ${YELLOW}⚠️  Doctor nicht gefunden — Schritt 2 prüfen${NC}"
fi

echo ""

# =============================================================================
# Summary
# =============================================================================

echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════╗${NC}"
echo -e "${GREEN}${BOLD}║  ✅  Migration → AI Context v6.5 fertig  ║${NC}"
echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BOLD}Neue Befehle in Claude Code:${NC}"
echo -e "  ${CYAN}/ai-fix${NC}       → Bug via Symptom-Router + Verify-Loop beheben"
echo -e "  ${CYAN}/ai-doctor${NC}    → Kontext-Defekte diagnostizieren & reparieren"
echo -e "  ${CYAN}/ai-transfer${NC}  → Cross-Projekt-Ideen aus Inbox anzeigen"
echo ""
echo -e "${BOLD}Nützliche Shell-Befehle:${NC}"
echo -e "  ${CYAN}bash _ai_context/scripts/ai-context-map.sh${NC}"
echo -e "        → Interaction Map für dieses Projekt generieren"
echo -e "  ${CYAN}bash _ai_context/scripts/ai-context-doctor.sh --check${NC}"
echo -e "        → Health-Report manuell starten"
echo -e "  ${CYAN}bash _ai_context/scripts/ai-verify.sh --detect${NC}"
echo -e "        → Erkannten Verify-Befehl anzeigen"
echo ""
echo -e "${YELLOW}Hinweis:${NC} _quick_facts.md unterstützt jetzt ein optionales Feld:"
echo -e "  ${CYAN}Verify-Command: npm run typecheck${NC}"
echo -e "  (In _ai_context/_quick_facts.md ergänzen für präziseren Verify-Loop)"
echo ""
