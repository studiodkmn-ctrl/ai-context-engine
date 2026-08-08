#!/usr/bin/env bash
# =============================================================================
# migrate.sh — Additive Migration: AI Context v5.x+ → aktuelle Version (siehe VERSION)
#
# Aufruf aus dem Root des Ziel-Projekts:
#   bash /path/to/ai-context-v7/migrate.sh
#   bash ~/.ai-context/migrate.sh
#
# Was passiert:
#   1. Neue Scripts → _ai_context/scripts/
#   2. Skills       → .claude/skills/
#   3. Hooks patchen (post-commit, pii-warn.sh)
#   4. .claude/settings.json mergen (Doctor --session als erster Hook)
#   5. _interaction_map.md Placeholder anlegen (falls fehlt)
#   6. ai-context-doctor.sh --check ausführen
#   9. v7: scripts/lib/ (ctx.py, synonyms.txt), drawers.yaml,
#      seen-Felder nachtragen (Registry-Scan), SessionStart-Hook für
#      _SESSION.md-Injektion
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
ENGINE_VERSION="$(cat "$SCRIPT_DIR/VERSION" 2>/dev/null || echo "?")"

echo ""
echo -e "${BOLD}🔄 AI Context — Migration → v${ENGINE_VERSION}${NC}"
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
  echo -e "   Projekt-Version: ${YELLOW}$(cat VERSION)${NC} → ${GREEN}${ENGINE_VERSION}${NC}"
else
  echo -e "   AI Context v5.x/v6.x erkannt → ${GREEN}v${ENGINE_VERSION}${NC}"
fi
echo ""

# =============================================================================
# 2. Neue Scripts kopieren
# =============================================================================

echo -e "${CYAN}📜 Scripts installieren...${NC}"

# FIX (v8.0.1): Hier standen zwei handgeführte Allowlists (NEW_SCRIPTS /
# UPDATED_SCRIPTS). Jedes Script, das in beiden fehlte — u.a.
# ai-context-refresh.sh, ai-verify-self.sh, ai-rag-cache.sh, ai-session-log.sh,
# ai-context-scan.sh — erreichte bestehende Projekte NIE, egal wie oft migriert
# wurde. Bugfixes darin blieben dauerhaft im Template hängen.
# _ai_context/scripts/ ist ein Spiegel des Templates (genau das prüft
# ai-context-doctor.sh mit "scriptdrift"), deshalb jetzt Vollsynchronisation
# statt Liste — neue Scripts können nicht mehr vergessen werden.
SCRIPTS_NEW=0
SCRIPTS_UPD=0
for src in "$SRC_TEMPLATE"/scripts/*.sh; do
  [ -f "$src" ] || continue
  script="$(basename "$src")"
  dst="_ai_context/scripts/$script"

  if [ ! -f "$dst" ]; then
    cp "$src" "$dst"
    chmod +x "$dst"
    echo -e "   ✅ $script (neu)"
    SCRIPTS_NEW=$((SCRIPTS_NEW + 1))
  elif ! diff -q "$src" "$dst" > /dev/null 2>&1; then
    cp "$src" "$dst"
    chmod +x "$dst"
    echo -e "   🔄 $script (aktualisiert)"
    SCRIPTS_UPD=$((SCRIPTS_UPD + 1))
  fi
done

if [ "$SCRIPTS_NEW" -eq 0 ] && [ "$SCRIPTS_UPD" -eq 0 ]; then
  echo -e "   ${GREEN}✓${NC} Scripts bereits aktuell"
fi

# check_context_hash.sh liegt eine Ebene höher
if [ -f "$SRC_TEMPLATE/check_context_hash.sh" ] && [ -f "_ai_context/check_context_hash.sh" ]; then
  cp "$SRC_TEMPLATE/check_context_hash.sh" "_ai_context/check_context_hash.sh"
  chmod +x "_ai_context/check_context_hash.sh"
  echo -e "   🔄 check_context_hash.sh (aktualisiert)"
fi

# v7: scripts/lib/ (ctx.py, synonyms.txt) — von ai-context-registry.sh,
# ai-session-prep.sh, ai-context-doctor.sh, ai-symptom-router.sh benötigt.
if [ -d "$SRC_TEMPLATE/scripts/lib" ]; then
  mkdir -p "_ai_context/scripts/lib"
  cp -r "$SRC_TEMPLATE/scripts/lib/." "_ai_context/scripts/lib/"
  echo -e "   ✅ scripts/lib/ (ctx.py, synonyms.txt)"
fi

# v9-a: knowledge.manifest.yaml additiv anlegen (wie drawers.yaml: nur wenn
# noch nicht vorhanden, NIE überschreiben — projekteigene Anpassungen an
# Limits/Typen sollen eine Migration überleben).
if [ ! -f "_ai_context/knowledge.manifest.yaml" ] && [ -f "$SRC_TEMPLATE/knowledge.manifest.yaml" ]; then
  cp "$SRC_TEMPLATE/knowledge.manifest.yaml" "_ai_context/knowledge.manifest.yaml"
  echo -e "   ✅ _ai_context/knowledge.manifest.yaml angelegt"
fi

# v9-a: Wissensdateien mit seed:true additiv anlegen (wie hot_paths.md/
# drawers.yaml: nur wenn noch nicht vorhanden, NIE überschreiben — sonst
# gingen projekteigene Einträge bei jeder Migration verloren). Generisch
# über das Manifest statt einer Datei-für-Datei-Sonderbehandlung — das war
# genau die Lücke, die playbooks.md bei bestehenden Projekten anfangs verpasst
# hat (siehe decisions.md#knowledge_manifest).
MANIFEST_FOR_SEED="_ai_context/knowledge.manifest.yaml"
CTX_PY="_ai_context/scripts/lib/ctx.py"
if [ -f "$MANIFEST_FOR_SEED" ] && [ -f "$CTX_PY" ]; then
  PROJECT_NAME_SEED="$(basename "$(pwd)")"
  while IFS= read -r seed_file; do
    [ -z "$seed_file" ] && continue
    if [ ! -f "_ai_context/$seed_file" ] && [ -f "$SRC_TEMPLATE/$seed_file" ]; then
      mkdir -p "_ai_context/$(dirname "$seed_file")"
      sed "s/\[PROJECT_NAME\]/$PROJECT_NAME_SEED/g" "$SRC_TEMPLATE/$seed_file" > "_ai_context/$seed_file"
      echo -e "   ✅ _ai_context/$seed_file angelegt (Manifest: seed:true)"
    fi
  done < <(python3 "$CTX_PY" list_knowledge_files "$MANIFEST_FOR_SEED" --seed-only 2>/dev/null)
fi

# ctx.py erzeugt bei jedem Aufruf __pycache__/ — ohne .gitignore-Eintrag
# landet das sonst versehentlich im nächsten Commit.
if [ -f ".gitignore" ] && ! grep -q "__pycache__" ".gitignore" 2>/dev/null; then
  printf '\n# Python bytecode cache (_ai_context/scripts/lib/ctx.py)\n__pycache__/\n*.pyc\n' >> ".gitignore"
  echo -e "   ✅ .gitignore um __pycache__/ ergänzt"
elif [ ! -f ".gitignore" ]; then
  printf '__pycache__/\n*.pyc\n' > ".gitignore"
  echo -e "   ✅ .gitignore angelegt (__pycache__/)"
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
CAT_SESSION_CMD="cat _ai_context/_SESSION.md 2>/dev/null || true"
PII_CMD="if [ -f ~/.ai-context/hooks/pii-warn.sh ]; then bash ~/.ai-context/hooks/pii-warn.sh; fi"
SELFCHECK_CMD="if [ -f ~/.ai-context/_ai_context_template/scripts/ai-context-selfcheck.sh ]; then bash ~/.ai-context/_ai_context_template/scripts/ai-context-selfcheck.sh --session 2>&1 || true; fi"
READGUARD_CMD="[ -f _ai_context/scripts/ai-read-guard.sh ] && bash _ai_context/scripts/ai-read-guard.sh || true"
ROUTER_CMD="[ -f _ai_context/scripts/ai-prompt-router.sh ] && bash _ai_context/scripts/ai-prompt-router.sh || true"
REFLECT_CMD="[ -f _ai_context/scripts/ai-session-reflect.sh ] && bash _ai_context/scripts/ai-session-reflect.sh || true"

mkdir -p ".claude"

if command -v python3 &>/dev/null; then
  python3 - "$SETTINGS" "$DOCTOR_CMD" "$SESSION_CMD" "$PII_CMD" "$CAT_SESSION_CMD" "$SELFCHECK_CMD" "$READGUARD_CMD" "$ROUTER_CMD" "$REFLECT_CMD" << 'PYEOF'
import json, sys, pathlib

path      = pathlib.Path(sys.argv[1])
doctor_cmd  = sys.argv[2]
session_cmd = sys.argv[3]
pii_cmd     = sys.argv[4]
cat_session_cmd = sys.argv[5]
selfcheck_cmd   = sys.argv[6]
readguard_cmd   = sys.argv[7]
router_cmd      = sys.argv[8]
reflect_cmd     = sys.argv[9]

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

# ---- v7: _SESSION.md direkt injizieren (statt nur Statuszeile) ----
has_cat_session = any(
    any("_SESSION.md" in h.get("command", "") for h in g.get("hooks", []))
    for g in groups
)
if not has_cat_session:
    target = groups[0] if groups else {"matcher": "", "hooks": []}
    target.setdefault("hooks", []).append({"type": "command", "command": cat_session_cmd})
    if not groups:
        groups.insert(0, target)
    else:
        groups[0] = target
    changed = True
    print("   ✅ SessionStart: _SESSION.md-Injektion hinzugefügt")
else:
    print("   ✅ SessionStart: _SESSION.md-Injektion bereits vorhanden")

# ---- v8: Selfcheck (Selbst-Update-Loop, rate-limitiert, still wenn aktuell) ----
has_selfcheck = any(
    any("ai-context-selfcheck" in h.get("command", "") for h in g.get("hooks", []))
    for g in groups
)
if not has_selfcheck:
    target = groups[0] if groups else {"matcher": "", "hooks": []}
    target.setdefault("hooks", []).append({"type": "command", "command": selfcheck_cmd})
    if not groups:
        groups.insert(0, target)
    else:
        groups[0] = target
    changed = True
    print("   ✅ SessionStart: ai-context-selfcheck (Selbst-Update) hinzugefügt")
else:
    print("   ✅ SessionStart: ai-context-selfcheck bereits vorhanden")

# ---- UserPromptSubmit ----
pii_groups = hooks.setdefault("UserPromptSubmit", [])
has_pii    = any(any("pii-warn" in h.get("command","") for h in g.get("hooks",[])) for g in pii_groups)
if not has_pii:
    pii_groups.append({"matcher": "", "hooks": [{"type": "command", "command": pii_cmd}]})
    changed = True
    print("   ✅ UserPromptSubmit: pii-warn.sh hinzugefügt")
else:
    print("   ✅ UserPromptSubmit: pii-warn.sh bereits vorhanden")

# ---- v9-b: UserPromptSubmit — Prompt-Router (locate() ohne Kommando) ----
has_router = any(
    any("ai-prompt-router" in h.get("command", "") for h in g.get("hooks", []))
    for g in pii_groups
)
if not has_router:
    pii_groups.append({"matcher": "", "hooks": [{"type": "command", "command": router_cmd}]})
    changed = True
    print("   ✅ UserPromptSubmit: ai-prompt-router.sh hinzugefügt")
else:
    print("   ✅ UserPromptSubmit: ai-prompt-router.sh bereits vorhanden")

# ---- v8.1: PreToolUse — Duplicate-Read-Guard ----
rg_groups = hooks.setdefault("PreToolUse", [])
has_readguard = any(
    any("ai-read-guard" in h.get("command", "") for h in g.get("hooks", []))
    for g in rg_groups
)
if not has_readguard:
    rg_groups.append({"matcher": "Read", "hooks": [{"type": "command", "command": readguard_cmd}]})
    changed = True
    print("   ✅ PreToolUse: ai-read-guard.sh hinzugefügt")
else:
    print("   ✅ PreToolUse: ai-read-guard.sh bereits vorhanden")

# ---- v9-c: Stop + PreCompact — Session-Reflexion ----
for event in ("Stop", "PreCompact"):
    ev_groups = hooks.setdefault(event, [])
    has_reflect = any(
        any("ai-session-reflect" in h.get("command", "") for h in g.get("hooks", []))
        for g in ev_groups
    )
    if not has_reflect:
        ev_groups.append({"matcher": "", "hooks": [{"type": "command", "command": reflect_cmd}]})
        changed = True
        print(f"   ✅ {event}: ai-session-reflect.sh hinzugefügt")
    else:
        print(f"   ✅ {event}: ai-session-reflect.sh bereits vorhanden")

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
# 7. v6.6 — hot_paths.md + Fokus-Sektion + Symbol-Map generieren
# =============================================================================

echo -e "${CYAN}🔥 v6.6: hot_paths.md + Symbol-Map + Interface-Snapshot...${NC}"

# hot_paths.md anlegen (nur wenn noch nicht vorhanden — ist manuell)
if [ ! -f "_ai_context/hot_paths.md" ] && [ -f "$SRC_TEMPLATE/hot_paths.md" ]; then
  PROJECT_NAME="$(basename "$(pwd)")"
  sed "s/\[PROJECT_NAME\]/$PROJECT_NAME/g" "$SRC_TEMPLATE/hot_paths.md" > "_ai_context/hot_paths.md"
  echo -e "   ${GREEN}✅ _ai_context/hot_paths.md${NC} angelegt (manuell befüllen)"
else
  echo -e "   ✅ hot_paths.md bereits vorhanden"
fi

# _ai_index.md Fokus-Sektion einfügen wenn noch nicht vorhanden
if [ -f "_ai_context/_ai_index.md" ] && ! grep -q "Aktueller Fokus" "_ai_context/_ai_index.md"; then
  python3 - "_ai_context/_ai_index.md" << 'PYEOF' || true
import sys, pathlib, re

idx_path = pathlib.Path(sys.argv[1])
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

target = re.search(r'^## (Projekt|Übersicht|Overview)', content, re.MULTILINE)
if target:
    pos = target.start()
    content = content[:pos] + fokus_block + content[pos:]
else:
    m = re.search(r'^>.*\n', content, re.MULTILINE)
    pos = m.end() if m else 0
    content = content[:pos] + '\n' + fokus_block + content[pos:]

idx_path.write_text(content, encoding='utf-8')
PYEOF
  echo -e "   ${GREEN}✅ _ai_index.md${NC} Fokus-Sektion hinzugefügt"
fi

# _idx/ Verzeichnis anlegen
mkdir -p "_ai_context/_idx"

# Symbol-Map + Interface-Snapshot generieren
if [ -f "_ai_context/scripts/ai-symbol-map.sh" ]; then
  bash "_ai_context/scripts/ai-symbol-map.sh" 2>/dev/null || true
fi
if [ -f "_ai_context/scripts/ai-interface-snapshot.sh" ]; then
  bash "_ai_context/scripts/ai-interface-snapshot.sh" 2>/dev/null || true
fi

echo ""

# =============================================================================
# 9. v7 — drawers.yaml + Frische-Felder (seen/code_touched/status)
# =============================================================================

echo -e "${CYAN}🗂️  v7: drawers.yaml + Frische-Modell...${NC}"

# drawers.yaml: generische Next.js-Default-Globs (kein Stack-Autodetect wie in
# setup_ai_context.sh — bei Bedarf manuell an die echte Projektstruktur anpassen).
if [ ! -f "_ai_context/drawers.yaml" ] && [ -f "$SRC_TEMPLATE/drawers.yaml" ]; then
  cp "$SRC_TEMPLATE/drawers.yaml" "_ai_context/drawers.yaml"
  echo -e "   ${GREEN}✅ _ai_context/drawers.yaml${NC} angelegt (generische Globs — ggf. anpassen)"
else
  echo -e "   ✅ drawers.yaml bereits vorhanden"
fi

# Interaction Map einmalig scannen, falls noch nie befüllt
if [ -f "_ai_context/_interaction_map.md" ] && grep -q "leer bis zum ersten Scan" "_ai_context/_interaction_map.md" 2>/dev/null; then
  if [ -f "_ai_context/scripts/ai-context-map.sh" ]; then
    bash "_ai_context/scripts/ai-context-map.sh" 2>/dev/null || true
  fi
fi

# Registry neu scannen: trägt seen/code_touched/status für alle Chunks nach
# (bestehende Chunks ohne seen: → seen = bisheriges updated-Datum, additiv).
# Vorher Anker injizieren — v5.x-Projekte haben ID:-Blöcke ohne HTML-Anker,
# die der Scan sonst nicht indexieren kann.
if [ -f "_ai_context/scripts/ai-context-registry.sh" ]; then
  bash "_ai_context/scripts/ai-context-registry.sh" --add-anchors 2>/dev/null || true
  bash "_ai_context/scripts/ai-context-registry.sh" --scan 2>/dev/null || true
  echo -e "   ${GREEN}✅ registry.yaml${NC} neu gescannt (seen/code_touched/status)"
fi

echo ""

# =============================================================================
# 8. Health-Check
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
echo -e "${GREEN}${BOLD}║  ✅  Migration → AI Context v${ENGINE_VERSION} fertig  ║${NC}"
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
