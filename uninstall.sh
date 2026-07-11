#!/usr/bin/env bash
# =============================================================================
# uninstall.sh — Vollständige Deinstallation von AI Context (v8 Baustein D)
#
# Entfernt (nach EINER globalen Bestätigung, vorher wird alles gelistet):
#   1. Shell-Integration: Marker-Block aus ~/.bashrc / ~/.zshrc
#      (dieselbe awk-Marker-Logik wie install.sh — nichts anderes wird
#      in den RC-Dateien angefasst)
#   2. AI-Context-Hooks aus ~/.claude/settings.json (nur Einträge, deren
#      command auf ai-session-prep/pii-warn/ai-context-selfcheck zeigt)
#   3. Git-Hook post-commit aus registrierten Projekten — NUR wenn der
#      Inhalt exakt dem bekannten AI-Context-Hook entspricht (Hash-
#      Vergleich); fremde oder angepasste Hooks werden NIE angefasst
#   4. ~/.ai-context komplett
#
# NICHT entfernt: _ai_context/-Ordner in den Projekten (das ist
# Projekt-Wissen des Nutzers, oft committed — Löschen wäre Datenverlust).
#
# Usage:
#   bash uninstall.sh          # interaktiv (listet alles, fragt einmal)
#   bash uninstall.sh --yes    # ohne Rückfrage (CI/Tests)
#
# Env: AI_CTX_HOME überschreibt ~/.ai-context (für Tests)
# =============================================================================
set -uo pipefail

GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'
BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'

STORE="${AI_CTX_HOME:-$HOME/.ai-context}"
GLOBAL_SETTINGS="$HOME/.claude/settings.json"

ASSUME_YES=false
[ "${1:-}" = "--yes" ] && ASSUME_YES=true

echo ""
echo -e "${BOLD}🗑  AI Context — Deinstallation${NC}"
echo ""

if [ ! -d "$STORE" ]; then
  echo -e "${YELLOW}⚠️  $STORE existiert nicht — nichts zu deinstallieren.${NC}"
  exit 0
fi

# macOS/Linux-portabler Datei-Hash
portable_hash() {
  md5sum "$1" 2>/dev/null | cut -d' ' -f1 \
    || md5 -q "$1" 2>/dev/null \
    || echo "n/a"
}

# ---- 1. Bestandsaufnahme: was würde entfernt? ----
declare -a RC_HITS=()
for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
  [ -f "$rc" ] || continue
  grep -q '# >>> AI Context v[0-9.]* BEGIN >>>' "$rc" 2>/dev/null && RC_HITS+=("$rc")
done

SETTINGS_HIT=false
if [ -f "$GLOBAL_SETTINGS" ] && grep -qE 'ai-session-prep|pii-warn|ai-context-selfcheck|session-bootstrap' "$GLOBAL_SETTINGS" 2>/dev/null; then
  SETTINGS_HIT=true
fi

# Registrierte Projekte mit exakt passendem AI-Context-post-commit-Hook
KNOWN_HOOK="$STORE/hooks/post-commit"
KNOWN_HASH=""
[ -f "$KNOWN_HOOK" ] && KNOWN_HASH="$(portable_hash "$KNOWN_HOOK")"

declare -a HOOK_PROJECTS=()
declare -a HOOK_SKIPPED=()
if [ -n "$KNOWN_HASH" ] && [ "$KNOWN_HASH" != "n/a" ] && [ -d "$STORE/projects" ]; then
  while IFS= read -r meta; do
    [ -f "$meta" ] || continue
    proj_path="$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d.get('path',''))" "$meta" 2>/dev/null || echo "")"
    [ -n "$proj_path" ] && [ -d "$proj_path" ] || continue
    hook="$proj_path/.git/hooks/post-commit"
    [ -f "$hook" ] || continue
    if [ "$(portable_hash "$hook")" = "$KNOWN_HASH" ]; then
      HOOK_PROJECTS+=("$hook")
    else
      HOOK_SKIPPED+=("$hook")
    fi
  done < <(find "$STORE/projects" -name ".meta.json" 2>/dev/null)
fi

echo -e "${BOLD}Folgendes wird entfernt:${NC}"
echo ""
echo -e "  ${CYAN}Globaler Store:${NC}"
echo -e "    $STORE  ${DIM}($(du -sh "$STORE" 2>/dev/null | cut -f1 || echo '?') )${NC}"
echo ""
if [ ${#RC_HITS[@]} -gt 0 ]; then
  echo -e "  ${CYAN}Shell-Integration (nur der AI-Context-Marker-Block):${NC}"
  for rc in "${RC_HITS[@]}"; do echo -e "    $rc"; done
  echo ""
fi
if $SETTINGS_HIT; then
  echo -e "  ${CYAN}Hooks in ~/.claude/settings.json:${NC}"
  echo -e "    Einträge mit ai-session-prep / pii-warn / ai-context-selfcheck"
  echo ""
fi
if [ ${#HOOK_PROJECTS[@]} -gt 0 ]; then
  echo -e "  ${CYAN}Git-Hooks (Inhalt == bekannter AI-Context-Hook):${NC}"
  for h in "${HOOK_PROJECTS[@]}"; do echo -e "    $h"; done
  echo ""
fi
if [ ${#HOOK_SKIPPED[@]} -gt 0 ]; then
  echo -e "  ${YELLOW}Übersprungen (Hook verändert/fremd — bleibt liegen):${NC}"
  for h in "${HOOK_SKIPPED[@]}"; do echo -e "    ${DIM}$h${NC}"; done
  echo ""
fi
echo -e "  ${DIM}Bleibt erhalten: _ai_context/-Ordner in deinen Projekten (Projekt-Wissen).${NC}"
echo ""

# ---- 2. Eine globale Bestätigung ----
if ! $ASSUME_YES; then
  read -r -p "Alles oben Gelistete entfernen? [y/N] " answer
  case "$answer" in
    [yY]|[yY][eE][sS]) ;;
    *) echo -e "${YELLOW}Abgebrochen — nichts wurde entfernt.${NC}"; exit 0 ;;
  esac
  echo ""
fi

# ---- 3. Shell-RC: Marker-Block entfernen (Logik aus install.sh) ----
for rc in "${RC_HITS[@]+"${RC_HITS[@]}"}"; do
  [ -f "$rc" ] || continue
  awk '
    /# >>> AI Context v[0-9.]+ BEGIN >>>/ { skip=1; next }
    /# <<< AI Context v[0-9.]+ END <<</   { skip=0; next }
    skip { next }
    { print }
  ' "$rc" > "${rc}.tmp" 2>/dev/null || cp "$rc" "${rc}.tmp"
  mv "${rc}.tmp" "$rc"
  echo -e "  ${GREEN}✅ Shell-Block entfernt: $rc${NC}"
done

# ---- 4. Hooks aus ~/.claude/settings.json entfernen ----
if $SETTINGS_HIT && command -v python3 &>/dev/null; then
  python3 - "$GLOBAL_SETTINGS" << 'PYEOF'
import json, sys, pathlib

path = pathlib.Path(sys.argv[1])
try:
    data = json.loads(path.read_text(encoding='utf-8'))
except (json.JSONDecodeError, OSError):
    print("  ⚠️  settings.json nicht lesbar — Hooks manuell entfernen")
    sys.exit(0)

NEEDLES = ('ai-session-prep', 'pii-warn', 'ai-context-selfcheck', 'session-bootstrap')
hooks = data.get('hooks', {})
removed = 0
for event, groups in list(hooks.items()):
    for g in groups:
        before = len(g.get('hooks', []))
        g['hooks'] = [h for h in g.get('hooks', [])
                      if not any(n in h.get('command', '') for n in NEEDLES)]
        removed += before - len(g['hooks'])
    hooks[event] = [g for g in groups if g.get('hooks')]
    if not hooks[event]:
        del hooks[event]
if removed:
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False), encoding='utf-8')
    print(f"  ✅ {removed} Hook-Eintrag/-Einträge aus ~/.claude/settings.json entfernt")
else:
    print("  ✅ Keine AI-Context-Hooks in ~/.claude/settings.json")
PYEOF
fi

# ---- 5. Git-Hooks aus registrierten Projekten (nur exakte Matches) ----
for h in "${HOOK_PROJECTS[@]+"${HOOK_PROJECTS[@]}"}"; do
  rm -f "$h" && echo -e "  ${GREEN}✅ Git-Hook entfernt: $h${NC}"
done

# ---- 6. Globalen Store löschen ----
rm -rf "$STORE"
echo -e "  ${GREEN}✅ $STORE gelöscht${NC}"

echo ""
echo -e "${GREEN}${BOLD}✅ AI Context deinstalliert.${NC}"
echo -e "   ${DIM}Terminal neu starten (oder: source ~/.zshrc), damit Aliase verschwinden.${NC}"
echo -e "   ${DIM}Projekt-Ordner _ai_context/ bei Bedarf manuell löschen.${NC}"
echo ""
exit 0
