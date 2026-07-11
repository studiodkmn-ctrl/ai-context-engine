#!/usr/bin/env bash
# =============================================================================
# session-bootstrap.sh — Einmalige Setup-Einladung (v8 Baustein D)
#
# Läuft als SessionStart-Hook. Wenn Claude Code in einem Git-Repo OHNE
# _ai_context/ startet und die globale Installation (~/.ai-context)
# existiert, wird EINMAL pro Projekt eine Einladung ausgegeben — statt
# dass der Nutzer wissen muss, dass `ai-context-setup` existiert.
#
# Bewusst NUR eine Einladung, KEIN automatisches Setup: ein komplettes
# Projekt-Setup ist ein größerer Eingriff und braucht ein explizites Ja
# (anders als die additiven Wartungs-Fixes von Doctor/Selfcheck).
#
# Gemerkte Projekte: ~/.ai-context/.bootstrap-invited (eine Zeile = ein Pfad).
#
# Env: AI_CTX_HOME überschreibt ~/.ai-context (für Tests)
# =============================================================================
set -uo pipefail

STORE="${AI_CTX_HOME:-$HOME/.ai-context}"
INVITED="$STORE/.bootstrap-invited"

# Nur relevant, wenn global installiert + Projekt noch ohne AI Context
[ -d "$STORE/_ai_context_template" ] || exit 0
[ -d "_ai_context" ] && exit 0
git rev-parse --is-inside-work-tree > /dev/null 2>&1 || exit 0

PROJECT_PATH="$(pwd)"

# Schon eingeladen? Dann still bleiben (einmalig pro Projekt).
if [ -f "$INVITED" ] && grep -qxF "$PROJECT_PATH" "$INVITED" 2>/dev/null; then
  exit 0
fi
printf '%s\n' "$PROJECT_PATH" >> "$INVITED"

CYAN='\033[0;36m'; DIM='\033[2m'; NC='\033[0m'
echo -e "${CYAN}🧠 Dieses Projekt hat noch kein AI Context.${NC}"
echo -e "   Einrichten (Kontext-Karte, Gedächtnis, locate()):"
echo -e "   ${CYAN}bash ~/.ai-context/setup_ai_context.sh${NC}  ${DIM}(alias: ai-context-setup)${NC}"
echo -e "   ${DIM}Dieser Hinweis erscheint nur einmal pro Projekt.${NC}"
exit 0
