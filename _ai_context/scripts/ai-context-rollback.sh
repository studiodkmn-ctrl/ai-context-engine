#!/usr/bin/env bash
# =============================================================================
# ai-context-rollback.sh — stellt das jüngste Selfcheck-Backup wieder her
# (v8 Baustein A — Gegenstück zu ai-context-selfcheck.sh)
#
# Backups liegen in ~/.ai-context/.backups/<timestamp>/ und enthalten:
#   _ai_context_template/   (Template-Stand vor dem Update)
#   mcp/dist/               (gebauter MCP-Server vor dem Update)
#   VERSION
#
# Usage:
#   bash ai-context-rollback.sh           # jüngstes Backup wiederherstellen
#   bash ai-context-rollback.sh --list    # verfügbare Backups anzeigen
#   bash ai-context-rollback.sh <ts>      # bestimmtes Backup (Timestamp-Name)
#
# Env: AI_CTX_HOME überschreibt ~/.ai-context (für Tests)
# =============================================================================
set -uo pipefail

GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'

STORE="${AI_CTX_HOME:-$HOME/.ai-context}"
BACKUP_ROOT="$STORE/.backups"

if [ ! -d "$BACKUP_ROOT" ] || [ -z "$(ls -A "$BACKUP_ROOT" 2>/dev/null)" ]; then
  echo -e "${YELLOW}⚠️  Keine Backups vorhanden ($BACKUP_ROOT).${NC}"
  exit 1
fi

if [ "${1:-}" = "--list" ]; then
  echo -e "${CYAN}Verfügbare Backups:${NC}"
  for d in "$BACKUP_ROOT"/*/; do
    [ -d "$d" ] || continue
    name="$(basename "$d")"
    ver="$(cat "$d/VERSION" 2>/dev/null || echo '?')"
    echo "  $name  (v$ver)"
  done
  exit 0
fi

if [ -n "${1:-}" ]; then
  TARGET="$BACKUP_ROOT/$1"
  if [ ! -d "$TARGET" ]; then
    echo -e "${RED}❌ Backup nicht gefunden: $TARGET${NC}"
    echo -e "   Verfügbar: bash $0 --list"
    exit 1
  fi
else
  TARGET="$BACKUP_ROOT/$(ls -1 "$BACKUP_ROOT" | sort | tail -1)"
fi

echo -e "${CYAN}⏪ Rollback aus: $TARGET${NC}"

if [ -d "$TARGET/_ai_context_template" ]; then
  rm -rf "$STORE/_ai_context_template"
  cp -R "$TARGET/_ai_context_template" "$STORE/_ai_context_template"
  echo -e "   ✅ _ai_context_template wiederhergestellt"
fi

if [ -d "$TARGET/mcp/dist" ]; then
  rm -rf "$STORE/mcp/dist"
  mkdir -p "$STORE/mcp"
  cp -R "$TARGET/mcp/dist" "$STORE/mcp/dist"
  echo -e "   ✅ mcp/dist wiederhergestellt"
fi

if [ -f "$TARGET/VERSION" ]; then
  cp "$TARGET/VERSION" "$STORE/VERSION"
  echo -e "   ✅ VERSION → v$(cat "$STORE/VERSION")"
fi

echo -e "${GREEN}✅ Rollback abgeschlossen.${NC}"
echo -e "   Hinweis: bereits migrierte Projekte bleiben auf dem neueren Stand —"
echo -e "   dort bei Bedarf: ${CYAN}git checkout -- _ai_context/${NC} (falls uncommittet)."
exit 0
