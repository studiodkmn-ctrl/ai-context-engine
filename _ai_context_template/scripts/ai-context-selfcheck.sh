#!/usr/bin/env bash
# =============================================================================
# ai-context-selfcheck.sh — Selbst-Update-Loop (v8 Baustein A)
#
# Vergleicht die installierte Version (~/.ai-context/VERSION) mit der
# Installations-Quelle (Git-Checkout, hinterlegt in ~/.ai-context/.source-path)
# und wendet verfügbare Updates automatisch an — mit Backup und
# Integritäts-Guard. Kein Netzwerkzugriff ohne bekannte Git-Quelle.
#
# Ablauf bei Update:
#   1. Integritäts-Guard: Remote-URL der Quelle == ~/.ai-context/.trusted-origin
#   2. Backup: _ai_context_template + mcp/dist → ~/.ai-context/.backups/<ts>/
#      (max. 3 Backups, älteste werden gelöscht)
#   3. Quelle fast-forwarden (nur wenn Worktree sauber), dann
#      install.sh --refresh (Dateien/MCP aktualisieren, keine Interaktion)
#   4. auto-update-all.sh (migrate.sh pro registriertem Projekt — additiv,
#      NIE git add/commit im Zielprojekt)
#
# Usage:
#   bash ai-context-selfcheck.sh               # prüfen + anwenden (verbose)
#   bash ai-context-selfcheck.sh --check-only  # nur melden, nie anwenden
#   bash ai-context-selfcheck.sh --session     # SessionStart: rate-limitiert
#                                              # (max 1×/7 Tage), still wenn
#                                              # nichts zu tun ist
#   bash ai-context-selfcheck.sh --force       # Rate-Limit ignorieren
#
# Env:
#   AI_CTX_HOME   überschreibt ~/.ai-context (für Tests)
#
# Exit: 0 = aktuell/angewendet/übersprungen | 1 = Fehler/Guard verweigert
# =============================================================================
set -uo pipefail

GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'
RED='\033[0;31m'; NC='\033[0m'

STORE="${AI_CTX_HOME:-$HOME/.ai-context}"
INTERVAL_DAYS="${AI_CTX_SELFCHECK_DAYS:-7}"
STAMP_FILE="$STORE/.last-selfcheck"
BACKUP_ROOT="$STORE/.backups"
MAX_BACKUPS=3

MODE="apply"        # apply | check-only
SESSION=false
FORCE=false
for arg in "$@"; do
  case "$arg" in
    --check-only) MODE="check-only" ;;
    --session)    SESSION=true ;;
    --force)      FORCE=true ;;
    *) echo "Usage: ai-context-selfcheck.sh [--check-only|--session|--force]" >&2; exit 2 ;;
  esac
done

# Im Session-Modus nur sprechen, wenn etwas passiert ist (Update/Fehler) —
# Session-Start darf nicht lauter werden.
say() { $SESSION || echo -e "$@"; }
announce() { echo -e "$@"; }

[ -d "$STORE" ] || { say "${YELLOW}⚠️  Keine globale Installation ($STORE fehlt) — nichts zu prüfen.${NC}"; exit 0; }

# ---- Rate-Limit: frühestens alle $INTERVAL_DAYS Tage (Session-Modus) ----
NOW="$(date +%s)"
if $SESSION && ! $FORCE && [ -f "$STAMP_FILE" ]; then
  LAST="$(cat "$STAMP_FILE" 2>/dev/null || echo 0)"
  case "$LAST" in (*[!0-9]*|'') LAST=0 ;; esac
  if [ $((NOW - LAST)) -lt $((INTERVAL_DAYS * 86400)) ]; then
    exit 0
  fi
fi

# ---- Installationstyp erkennen: nur Git-Checkout-Quellen sind updatebar ----
SOURCE_PATH="$(cat "$STORE/.source-path" 2>/dev/null || echo "")"
if [ -z "$SOURCE_PATH" ] || [ ! -d "$SOURCE_PATH/.git" ]; then
  # Kein Silent-Netzwerkzugriff ohne bekannte Quelle.
  printf '%s\n' "$NOW" > "$STAMP_FILE"
  say "${YELLOW}ℹ️  Update-Check nicht verfügbar für diese Installationsart${NC}"
  say "   (Quelle kein Git-Checkout — Update manuell: git pull + bash install.sh)"
  exit 0
fi

# ---- Integritäts-Guard: Quelle muss der beim Erstinstall vertrauten Remote
# entsprechen — verhindert, dass ein untergeschobener Checkout Updates liefert.
ACTUAL_ORIGIN="$(git -C "$SOURCE_PATH" remote get-url origin 2>/dev/null || echo "")"
TRUSTED_ORIGIN="$(cat "$STORE/.trusted-origin" 2>/dev/null || echo "")"
if [ -n "$TRUSTED_ORIGIN" ] && [ "$ACTUAL_ORIGIN" != "$TRUSTED_ORIGIN" ]; then
  announce "${RED}⛔ Selfcheck: Quelle nicht vertrauenswürdig — Update verweigert.${NC}"
  announce "   Erwartet: $TRUSTED_ORIGIN"
  announce "   Gefunden: ${ACTUAL_ORIGIN:-<keine origin-Remote>} ($SOURCE_PATH)"
  announce "   Wenn der Wechsel beabsichtigt ist: $STORE/.trusted-origin manuell anpassen."
  exit 1
fi
if [ -z "$TRUSTED_ORIGIN" ] && [ -n "$ACTUAL_ORIGIN" ]; then
  # Ältere Installation ohne .trusted-origin: einmalig auf aktuelle Quelle
  # festlegen (First-Use-Trust), danach nie wieder automatisch überschreiben.
  printf '%s\n' "$ACTUAL_ORIGIN" > "$STORE/.trusted-origin"
  say "   ${CYAN}ℹ️  .trusted-origin initialisiert: $ACTUAL_ORIGIN${NC}"
fi

# ---- Versionsstand ermitteln ----
LOCAL_VERSION="$(cat "$STORE/VERSION" 2>/dev/null || echo "unbekannt")"
if [ -n "$ACTUAL_ORIGIN" ]; then
  git -C "$SOURCE_PATH" fetch --quiet origin main 2>/dev/null || \
    say "${YELLOW}⚠️  git fetch fehlgeschlagen (offline?) — prüfe lokalen Quellstand.${NC}"
fi
BEHIND="$(git -C "$SOURCE_PATH" rev-list HEAD..origin/main --count 2>/dev/null || echo 0)"
SOURCE_VERSION="$(cat "$SOURCE_PATH/VERSION" 2>/dev/null || echo "unbekannt")"

printf '%s\n' "$NOW" > "$STAMP_FILE"

if [ "${BEHIND:-0}" -eq 0 ] && [ "$LOCAL_VERSION" = "$SOURCE_VERSION" ]; then
  say "${GREEN}✅ AI Context aktuell (v$LOCAL_VERSION)${NC}"
  exit 0
fi

# ---- Update verfügbar ----
if [ "$MODE" = "check-only" ]; then
  announce "${CYAN}🔄 Update verfügbar:${NC} installiert v$LOCAL_VERSION, Quelle v$SOURCE_VERSION (${BEHIND} Commit(s) hinter origin/main)"
  announce "   Anwenden: ${CYAN}bash $STORE/_ai_context_template/scripts/ai-context-selfcheck.sh${NC}"
  exit 0
fi

announce "${CYAN}🔄 AI Context Update: v$LOCAL_VERSION → v$SOURCE_VERSION wird angewendet...${NC}"

# ---- Backup anlegen (letzte 3 behalten) ----
TS="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$BACKUP_ROOT/$TS"
mkdir -p "$BACKUP_DIR"
[ -d "$STORE/_ai_context_template" ] && cp -R "$STORE/_ai_context_template" "$BACKUP_DIR/_ai_context_template"
[ -d "$STORE/mcp/dist" ] && { mkdir -p "$BACKUP_DIR/mcp"; cp -R "$STORE/mcp/dist" "$BACKUP_DIR/mcp/dist"; }
cp "$STORE/VERSION" "$BACKUP_DIR/VERSION" 2>/dev/null || true
announce "   📦 Backup: $BACKUP_DIR"
# Älteste Backups über MAX_BACKUPS hinaus löschen (Timestamp-Namen: sortieren
# = chronologisch; head -n -N ist auf macOS nicht portabel, daher awk).
BACKUP_COUNT="$(ls -1 "$BACKUP_ROOT" 2>/dev/null | wc -l | tr -d ' ')"
if [ "${BACKUP_COUNT:-0}" -gt "$MAX_BACKUPS" ]; then
  ls -1 "$BACKUP_ROOT" | sort | awk -v keep="$MAX_BACKUPS" -v total="$BACKUP_COUNT" 'NR <= (total - keep)' | while IFS= read -r old; do
    rm -rf "${BACKUP_ROOT:?}/$old"
  done
fi

# ---- Quelle aktualisieren (nur fast-forward, nur bei sauberem Worktree) ----
if [ "${BEHIND:-0}" -gt 0 ]; then
  if [ -n "$(git -C "$SOURCE_PATH" status --porcelain 2>/dev/null)" ]; then
    announce "${YELLOW}⚠️  Quelle hat uncommittete Änderungen — kein Pull. Wende lokalen Quellstand an.${NC}"
  elif ! git -C "$SOURCE_PATH" merge --ff-only origin/main --quiet 2>/dev/null; then
    announce "${YELLOW}⚠️  Quelle nicht fast-forwardbar (lokale Commits?) — wende lokalen Quellstand an.${NC}"
  else
    SOURCE_VERSION="$(cat "$SOURCE_PATH/VERSION" 2>/dev/null || echo "$SOURCE_VERSION")"
    announce "   ✅ Quelle auf origin/main aktualisiert"
  fi
fi

# ---- Anwenden: install.sh --refresh (Dateien + MCP), dann Projekte migrieren ----
if [ ! -f "$SOURCE_PATH/install.sh" ]; then
  announce "${RED}❌ install.sh fehlt in der Quelle ($SOURCE_PATH) — Update abgebrochen.${NC}"
  announce "   Rollback: bash $STORE/_ai_context_template/scripts/ai-context-rollback.sh"
  exit 1
fi

REFRESH_LOG="$(mktemp -t aictx-refresh.XXXXXX.log)"
if AI_CTX_HOME="$STORE" bash "$SOURCE_PATH/install.sh" --refresh > "$REFRESH_LOG" 2>&1; then
  announce "   ✅ Globaler Store aktualisiert (v$(cat "$STORE/VERSION" 2>/dev/null || echo '?'))"
else
  announce "${RED}❌ install.sh --refresh fehlgeschlagen — Log: $REFRESH_LOG${NC}"
  announce "   Rollback: bash $STORE/_ai_context_template/scripts/ai-context-rollback.sh"
  exit 1
fi
rm -f "$REFRESH_LOG"

if [ -f "$STORE/auto-update-all.sh" ]; then
  UPDATE_LOG="$(mktemp -t aictx-update-all.XXXXXX.log)"
  if AI_CTX_HOME="$STORE" bash "$STORE/auto-update-all.sh" > "$UPDATE_LOG" 2>&1; then
    # grep -c gibt bei 0 Treffern selbst "0" aus (Exit 1 ist hier kein Fehler)
    MIGRATED="$(grep -cE '✅ migriert' "$UPDATE_LOG" 2>/dev/null || true)"
    announce "   ✅ Projekte migriert: $MIGRATED (additiv, uncommittet — git diff im Projekt prüfen)"
    rm -f "$UPDATE_LOG"
  else
    announce "${YELLOW}⚠️  auto-update-all.sh mit Fehlern — Log: $UPDATE_LOG${NC}"
  fi
fi

announce "${GREEN}✅ Update angewendet: v$LOCAL_VERSION → v$(cat "$STORE/VERSION" 2>/dev/null || echo '?')${NC}"
announce "   Rückgängig: ${CYAN}bash $STORE/_ai_context_template/scripts/ai-context-rollback.sh${NC}"
exit 0
