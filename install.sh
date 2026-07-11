#!/usr/bin/env bash
# =============================================================================
# install.sh — Globale Installation von AI Context v7.0
#
# Modi:
#   bash install.sh                        → Simple (Basis: Templates + Shell-Aliase)
#   bash install.sh --pro                  → Pro (+ Ollama + RAG-Cache + Embeddings)
#   bash install.sh --migrate-all          → Alle bekannten Projekte migrieren (Simple)
#   bash install.sh --pro --migrate-all    → Pro installieren + alle Projekte migrieren
#
# =============================================================================
set -euo pipefail

GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; BOLD='\033[1m'; RED='\033[0;31m'; NC='\033[0m'

# AI_CTX_HOME: Override für Tests / Wegwerf-Umgebungen (Default ~/.ai-context)
INSTALL_DIR="${AI_CTX_HOME:-$HOME/.ai-context}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---- Flag-Parsing ----
PRO_MODE=false
MIGRATE_ALL=false
REFRESH=false
for arg in "$@"; do
  [ "$arg" = "--pro" ]          && PRO_MODE=true
  [ "$arg" = "--migrate-all" ]  && MIGRATE_ALL=true
  [ "$arg" = "--refresh" ]      && REFRESH=true
  [ "$arg" = "--skip-ollama" ]  && {
    echo -e "${YELLOW}⚠️  --skip-ollama ist veraltet. Standard ist jetzt Simple-Modus (ohne Ollama).${NC}"
    echo -e "   Für Ollama+RAG: bash install.sh --pro"
    echo ""
  }
done

# --refresh (v8): nicht-interaktive Datei-Aktualisierung für den Selbst-Update-
# Loop (ai-context-selfcheck.sh). Behält die installierte Edition bei, fasst
# weder Ollama noch Shell-RC-Dateien an — nur Templates, Scripts, MCP, Hooks.
if $REFRESH; then
  if [ "$(cat "$INSTALL_DIR/edition" 2>/dev/null || echo simple)" = "pro" ]; then
    PRO_MODE=true
  fi
  echo -e "${BOLD}🔄 AI Context — Refresh (Selbst-Update)${NC}"
elif $PRO_MODE; then
  echo -e "${BOLD}🧠 AI Context v7.0 — Pro Installation${NC}"
  echo -e "   Basis + Ollama + RAG-Cache + Embeddings"
else
  echo -e "${BOLD}🧠 AI Context v7.0 — Simple Installation${NC}"
  echo -e "   Basis: Templates + Registry + Shell-Aliase"
fi
echo ""

# =============================================================================
# ---- SIMPLE: Basis-Installation (immer) ----
# =============================================================================

# ---- Erstelle Verzeichnisse ----
mkdir -p "$INSTALL_DIR"/{projects,shared}

# ---- Kopiere Dateien ----
cp -r "$SCRIPT_DIR/_ai_context_template" "$INSTALL_DIR/"
cp -r "$SCRIPT_DIR/hooks" "$INSTALL_DIR/"
cp "$SCRIPT_DIR/setup_ai_context.sh" "$INSTALL_DIR/"
cp "$SCRIPT_DIR/CLAUDE.md" "$INSTALL_DIR/"
[ -f "$SCRIPT_DIR/migrate.sh" ] && cp "$SCRIPT_DIR/migrate.sh" "$INSTALL_DIR/" && chmod +x "$INSTALL_DIR/migrate.sh"
[ -f "$SCRIPT_DIR/auto-update-all.sh" ] && cp "$SCRIPT_DIR/auto-update-all.sh" "$INSTALL_DIR/" && chmod +x "$INSTALL_DIR/auto-update-all.sh"
[ -f "$SCRIPT_DIR/context_manager_agent.py" ] && cp "$SCRIPT_DIR/context_manager_agent.py" "$INSTALL_DIR/"
[ -f "$SCRIPT_DIR/ai-anon.sh" ] && cp "$SCRIPT_DIR/ai-anon.sh" "$INSTALL_DIR/" && chmod +x "$INSTALL_DIR/ai-anon.sh"

# ---- MCP-Server (Phase 2): kopieren + bauen ----
if [ -d "$SCRIPT_DIR/mcp" ]; then
  rm -rf "$INSTALL_DIR/mcp"
  mkdir -p "$INSTALL_DIR/mcp"
  cp -r "$SCRIPT_DIR/mcp/src" "$SCRIPT_DIR/mcp/package.json" "$SCRIPT_DIR/mcp/tsconfig.json" "$INSTALL_DIR/mcp/" 2>/dev/null
  [ -d "$SCRIPT_DIR/mcp/test" ] && cp -r "$SCRIPT_DIR/mcp/test" "$INSTALL_DIR/mcp/"
  if command -v npm > /dev/null 2>&1; then
    ( cd "$INSTALL_DIR/mcp" && npm install --silent && npm run build --silent ) \
      && printf '   ✓ MCP-Server gebaut (~/.ai-context/mcp/dist/server.js)\n' \
      || printf '   ⚠ MCP-Build fehlgeschlagen — manuell: cd ~/.ai-context/mcp && npm install && npm run build\n'
  else
    printf '   ⚠ npm fehlt — MCP-Server nicht gebaut. Node 18+ installieren, dann: cd ~/.ai-context/mcp && npm install && npm run build\n'
  fi
fi

chmod +x "$INSTALL_DIR/setup_ai_context.sh"
find "$INSTALL_DIR/_ai_context_template/scripts" -name "*.sh" -exec chmod +x {} \;
chmod +x "$INSTALL_DIR/_ai_context_template/check_context_hash.sh"
chmod +x "$INSTALL_DIR/_ai_context_template/scripts/ai-rag-cache.sh"
find "$INSTALL_DIR/hooks" -type f -exec chmod +x {} \;

# ---- v8: Versions- und Quell-Metadaten für den Selbst-Update-Loop ----
# VERSION: installierter Stand (Vergleichsbasis für ai-context-selfcheck.sh)
[ -f "$SCRIPT_DIR/VERSION" ] && cp "$SCRIPT_DIR/VERSION" "$INSTALL_DIR/VERSION" || true
# .source-path: woher diese Installation kam (Git-Checkout → Updates möglich)
printf '%s\n' "$SCRIPT_DIR" > "$INSTALL_DIR/.source-path"
# .trusted-origin: Remote-URL beim ALLERERSTEN Install — wird danach nie
# automatisch überschrieben (Integritäts-Guard gegen untergeschobene Quellen).
if [ ! -f "$INSTALL_DIR/.trusted-origin" ]; then
  SOURCE_ORIGIN="$(git -C "$SCRIPT_DIR" remote get-url origin 2>/dev/null || echo "")"
  [ -n "$SOURCE_ORIGIN" ] && printf '%s\n' "$SOURCE_ORIGIN" > "$INSTALL_DIR/.trusted-origin" || true
fi

# ---- Edition festlegen (simple / pro) ----
if $PRO_MODE; then
  printf 'pro\n' > "$INSTALL_DIR/edition"
  echo -e "${GREEN}✅ Edition: Pro${NC}"
else
  printf 'simple\n' > "$INSTALL_DIR/edition"
  echo -e "${GREEN}✅ Edition: Simple${NC}"

  # Pro-only Scripts entfernen (sind nicht verfügbar in Simple)
  for _s in ai-rag-cache.sh ai-impact-learn.sh ai-context-transfer.sh; do
    rm -f "$INSTALL_DIR/_ai_context_template/scripts/$_s"
  done
  # Pro-only Skills entfernen
  rm -rf "$INSTALL_DIR/_ai_context_template/.claude/skills/ai-fix"
  rm -rf "$INSTALL_DIR/_ai_context_template/.claude/skills/ai-transfer"
  echo -e "   (Pro-Features ausgeblendet — ${CYAN}bash install.sh --pro${NC} zum Upgraden)"
fi

echo -e "${GREEN}✅ Dateien installiert nach $INSTALL_DIR${NC}"

# ---- Globale Gotchas/Patterns initialisieren ----
if [ ! -f "$INSTALL_DIR/shared/gotchas_global.md" ]; then
  cat > "$INSTALL_DIR/shared/gotchas_global.md" << 'EOF'
# Globale Gotchas — Projektübergreifend
> Gotchas die in mehreren Projekten auftreten.
> Hinzufügen: `bash _ai_context/scripts/ai-context-sync.sh --share-gotcha "ID: beschreibung"`

EOF
fi

if [ ! -f "$INSTALL_DIR/shared/patterns_global.md" ]; then
  cat > "$INSTALL_DIR/shared/patterns_global.md" << 'EOF'
# Globale Debug-Patterns — Projektübergreifend
> Patterns die in mehreren Projekten auftreten.

EOF
fi

# ---- Globale Hooks in ~/.claude/settings.json ----
# SessionStart:      Kontext-Vorbereitung (läuft in ALLEN Claude-Umgebungen)
# UserPromptSubmit:  PII-Guardrail (Option A: ap: → pass-through, Option B: raw-PII → Warn-Injection)
GLOBAL_SETTINGS="$HOME/.claude/settings.json"
SESSION_HOOK_CMD='[ -f _ai_context/scripts/ai-session-prep.sh ] && bash _ai_context/scripts/ai-session-prep.sh 2>&1 | awk "/^(🧠|✅|__AI_CTX__)/ || /Session bereit/ || /Kontext wird vorbereitet/" || true'
PII_HOOK_CMD='if [ -f ~/.ai-context/hooks/pii-warn.sh ]; then bash ~/.ai-context/hooks/pii-warn.sh; fi'
# Selfcheck (v8): rate-limitiert (1×/7 Tage), still wenn alles aktuell —
# meldet sich nur, wenn ein Update angewendet wurde oder fehlschlug.
SELFCHECK_HOOK_CMD='if [ -f ~/.ai-context/_ai_context_template/scripts/ai-context-selfcheck.sh ]; then bash ~/.ai-context/_ai_context_template/scripts/ai-context-selfcheck.sh --session 2>&1 || true; fi'

mkdir -p "$HOME/.claude"
if command -v python3 &>/dev/null; then
  python3 - "$GLOBAL_SETTINGS" "$SESSION_HOOK_CMD" "$PII_HOOK_CMD" "$SELFCHECK_HOOK_CMD" << 'PYEOF'
import json, sys, pathlib
path = pathlib.Path(sys.argv[1])
session_cmd, pii_cmd, selfcheck_cmd = sys.argv[2], sys.argv[3], sys.argv[4]

if path.exists():
    try:
        data = json.loads(path.read_text(encoding='utf-8'))
    except json.JSONDecodeError:
        print(f"⚠️  {path} ist kein valides JSON — Hooks manuell hinzufügen")
        sys.exit(0)
else:
    data = {}

hooks = data.setdefault("hooks", {})

def ensure_hook(event_name, needle, command):
    groups = hooks.setdefault(event_name, [])
    present = any(
        any(needle in h.get("command", "") for h in g.get("hooks", []))
        for g in groups
    )
    if not present:
        groups.append({"matcher": "", "hooks": [{"type": "command", "command": command}]})
        return True
    return False

changed = False
if ensure_hook("SessionStart",     "ai-session-prep.sh",      session_cmd):   changed = True
if ensure_hook("SessionStart",     "ai-context-selfcheck.sh", selfcheck_cmd): changed = True
if ensure_hook("UserPromptSubmit", "pii-warn.sh",             pii_cmd):       changed = True

if changed:
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False), encoding='utf-8')
    print("✅ SessionStart + UserPromptSubmit-Hooks in ~/.claude/settings.json eingefügt")
else:
    print("✅ Hooks bereits in ~/.claude/settings.json vorhanden")
PYEOF
else
  echo -e "${YELLOW}⚠️  python3 nicht gefunden — Hooks manuell in ~/.claude/settings.json eintragen${NC}"
fi

# =============================================================================
# ---- PRO: Ollama + RAG-Cache (nur mit --pro) ----
# =============================================================================
OLLAMA_CONF="$INSTALL_DIR/ollama.conf"
EMBED_MODEL="nomic-embed-text"
OLLAMA_OK=false

# --refresh überspringt Ollama (interaktiv) — die bestehende Installation
# bleibt unangetastet.
if $PRO_MODE && ! $REFRESH; then
  echo ""
  echo -e "${BOLD}🤖 Ollama Setup — vollautomatisch${NC}"
  echo ""

  OS="$(uname -s)"

  # ==========================================================================
  # -- 1. Ollama installieren --
  # ==========================================================================
  if command -v ollama &>/dev/null; then
    OLLAMA_VER=$(ollama --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "?")
    echo -e "${GREEN}✅ Ollama bereits installiert (v${OLLAMA_VER})${NC}"
    OLLAMA_OK=true
  else
    echo -e "${CYAN}📦 Ollama nicht gefunden — Installation startet...${NC}"

    if [ "$OS" = "Darwin" ]; then
      if command -v brew &>/dev/null; then
        echo -e "   → ${CYAN}brew install ollama${NC}"
        if brew install ollama 2>&1 | grep -v "^==>.*Already"; then
          :
        fi
        if command -v ollama &>/dev/null; then
          OLLAMA_VER=$(ollama --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "?")
          echo -e "${GREEN}✅ Ollama installiert (v${OLLAMA_VER})${NC}"
          OLLAMA_OK=true
        else
          echo -e "${RED}❌ brew install ollama fehlgeschlagen.${NC}"
          echo -e ""
          echo -e "   Mögliche Ursachen:"
          echo -e "   • brew ist veraltet  → ${CYAN}brew update && brew install ollama${NC}"
          echo -e "   • Netzwerkproblem    → Verbindung prüfen"
          echo -e ""
          echo -e "   Oder Ollama manuell installieren:"
          echo -e "   ${CYAN}https://ollama.com/download${NC}"
          echo -e ""
          read -r -p "   Ollama manuell installiert? [Enter] zum Fortfahren, [Ctrl+C] zum Abbrechen: "
          if command -v ollama &>/dev/null; then
            OLLAMA_OK=true
            echo -e "${GREEN}✅ Ollama gefunden${NC}"
          else
            echo -e "${YELLOW}⚠️  Ollama nicht gefunden — Basis-Installation läuft weiter.${NC}"
            echo -e "   RAG-Cache im Keyword-Fallback-Modus (ohne Embeddings)."
          fi
        fi
      else
        echo -e "${YELLOW}⚠️  Homebrew nicht gefunden.${NC}"
        echo -e ""
        echo -e "   Homebrew installieren (empfohlen):"
        echo -e "   ${CYAN}/bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"${NC}"
        echo -e ""
        echo -e "   Oder Ollama direkt herunterladen:"
        echo -e "   ${CYAN}https://ollama.com/download${NC}"
        echo -e ""
        read -r -p "   Ollama installiert? [Enter] zum Fortfahren, [Ctrl+C] zum Abbrechen: "
        if command -v ollama &>/dev/null; then
          OLLAMA_OK=true
          echo -e "${GREEN}✅ Ollama gefunden${NC}"
        else
          echo -e "${YELLOW}⚠️  Ollama nicht gefunden — Keyword-Fallback-Modus aktiv.${NC}"
        fi
      fi

    elif [ "$OS" = "Linux" ]; then
      echo -e "   → ${CYAN}curl -fsSL https://ollama.com/install.sh | sh${NC}"
      if curl -fsSL https://ollama.com/install.sh | sh; then
        if command -v ollama &>/dev/null; then
          OLLAMA_VER=$(ollama --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "?")
          echo -e "${GREEN}✅ Ollama installiert (v${OLLAMA_VER})${NC}"
          OLLAMA_OK=true
        fi
      else
        echo -e "${RED}❌ Installation fehlgeschlagen.${NC}"
        echo -e "   Manuell: ${CYAN}https://ollama.com/download${NC}"
      fi

    else
      echo -e "${YELLOW}⚠️  Unbekanntes Betriebssystem: $OS${NC}"
      echo -e "   Ollama manuell installieren: ${CYAN}https://ollama.com/download${NC}"
      read -r -p "   [Enter] nach Installation: "
      command -v ollama &>/dev/null && OLLAMA_OK=true
    fi
  fi

  # ==========================================================================
  # -- 2. Ollama starten (falls nicht läuft) --
  # ==========================================================================
  if $OLLAMA_OK; then
    if curl -sf http://localhost:11434/api/tags &>/dev/null; then
      echo -e "${GREEN}✅ Ollama läuft bereits${NC}"
    else
      echo -e "${CYAN}🚀 Starte Ollama...${NC}"
      nohup ollama serve &>/tmp/ollama-install.log &
      STARTED=false
      for i in $(seq 1 20); do
        sleep 1
        if curl -sf http://localhost:11434/api/tags &>/dev/null; then
          STARTED=true
          break
        fi
        printf "   Warte auf Ollama... %2ds\r" "$i"
      done
      if $STARTED; then
        echo -e "${GREEN}✅ Ollama gestartet                ${NC}"
      else
        echo -e "${YELLOW}⚠️  Ollama antwortet nicht nach 20s.${NC}"
        echo -e "   Log: ${CYAN}cat /tmp/ollama-install.log${NC}"
        OLLAMA_OK=false
      fi
    fi
  fi

  # ==========================================================================
  # -- 3. Embedding-Modell pullen --
  # ==========================================================================
  if $OLLAMA_OK; then
    if ollama list 2>/dev/null | grep -q "$EMBED_MODEL"; then
      echo -e "${GREEN}✅ $EMBED_MODEL bereits vorhanden${NC}"
    else
      echo -e "${CYAN}📥 Lade $EMBED_MODEL (~274 MB) — einmalig, wird lokal gecacht...${NC}"
      if ollama pull "$EMBED_MODEL"; then
        echo -e "${GREEN}✅ $EMBED_MODEL bereit${NC}"
      else
        echo -e "${RED}❌ Pull fehlgeschlagen — RAG-Cache arbeitet im Keyword-Fallback-Modus.${NC}"
        echo -e "   Später nachholen: ${CYAN}ollama pull $EMBED_MODEL${NC}"
        OLLAMA_OK=false
      fi
    fi
  fi

  # ==========================================================================
  # -- 4. Auto-Start einrichten --
  # ==========================================================================
  if $OLLAMA_OK && [ "$OS" = "Darwin" ]; then
    PLIST="$HOME/Library/LaunchAgents/com.ollama.server.plist"
    if [ ! -f "$PLIST" ]; then
      echo -e "${CYAN}⚙️  Richte launchd Auto-Start ein (Ollama startet bei Login)...${NC}"
      OLLAMA_BIN="$(command -v ollama)"
      cat > "$PLIST" << PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.ollama.server</string>
  <key>ProgramArguments</key>
  <array>
    <string>${OLLAMA_BIN}</string>
    <string>serve</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>/tmp/ollama.log</string>
  <key>StandardErrorPath</key>
  <string>/tmp/ollama.log</string>
</dict>
</plist>
PLIST_EOF
      launchctl load "$PLIST" 2>/dev/null && \
        echo -e "${GREEN}✅ Auto-Start aktiviert (launchd)${NC}" || \
        echo -e "${YELLOW}⚠️  launchctl fehlgeschlagen — Ollama manuell mit: ${CYAN}ollama serve${NC}"
    else
      echo -e "${GREEN}✅ Auto-Start bereits eingerichtet${NC}"
    fi
  fi

  if $OLLAMA_OK && [ "$OS" = "Linux" ] && command -v systemctl &>/dev/null; then
    if ! systemctl --user is-enabled ollama &>/dev/null 2>&1; then
      echo -e "${CYAN}⚙️  Richte systemd User-Service ein...${NC}"
      OLLAMA_BIN="$(command -v ollama)"
      mkdir -p "$HOME/.config/systemd/user"
      cat > "$HOME/.config/systemd/user/ollama.service" << SVC_EOF
[Unit]
Description=Ollama Server (AI Context RAG)
After=network.target

[Service]
ExecStart=${OLLAMA_BIN} serve
Restart=always
RestartSec=5

[Install]
WantedBy=default.target
SVC_EOF
      systemctl --user daemon-reload
      systemctl --user enable ollama
      systemctl --user start ollama && \
        echo -e "${GREEN}✅ systemd User-Service aktiviert${NC}" || \
        echo -e "${YELLOW}⚠️  systemd-Start fehlgeschlagen.${NC}"
    else
      echo -e "${GREEN}✅ systemd Service bereits aktiv${NC}"
    fi
  fi

  # ==========================================================================
  # -- 5. Konfiguration speichern --
  # ==========================================================================
  cat > "$OLLAMA_CONF" << CONF_EOF
# AI Context v7.0 — Ollama-Konfiguration
# Automatisch erstellt von install.sh --pro

OLLAMA_URL="http://localhost:11434"
OLLAMA_EMBED_MODEL="$EMBED_MODEL"
CONF_EOF
  echo -e "${GREEN}✅ Konfiguration gespeichert: $OLLAMA_CONF${NC}"
  echo ""

fi  # Ende PRO_MODE

# =============================================================================
# ---- Shell Integration ----
# =============================================================================

if $PRO_MODE; then
  SHELL_BLOCK='
# >>> AI Context v7.0 BEGIN >>>
# (Auto-generated by install.sh — edit between markers only if you know what you do)
alias ai-context-setup="bash ~/.ai-context/setup_ai_context.sh"
alias ai-context-sync="bash _ai_context/scripts/ai-context-sync.sh"
alias ai-prep="bash _ai_context/scripts/ai-session-prep.sh"
alias ai-rag="bash _ai_context/scripts/ai-rag-cache.sh"
alias ai-registry="bash _ai_context/scripts/ai-context-registry.sh"
alias ai-doctor="bash _ai_context/scripts/ai-context-doctor.sh"
alias ai-verify="bash _ai_context/scripts/ai-verify.sh"
alias ai-map="bash _ai_context/scripts/ai-context-map.sh"
alias ai-migrate="bash ~/.ai-context/migrate.sh"
alias ai-anon="bash ~/.ai-context/ai-anon.sh"
alias ai-stats="bash ~/.ai-context/_ai_context_template/scripts/ai-session-log.sh stats"

# pii-on / pii-off — PII-Schutz ein-/ausschalten (standardmäßig AUS)
pii-on()  { touch ~/.ai-context/pii-mode && printf "\033[0;32m🔒 PII-Schutz aktiviert\033[0m\n"; }
pii-off() { rm -f ~/.ai-context/pii-mode && printf "\033[0;33m🔓 PII-Schutz deaktiviert\033[0m\n"; }

# ap: <text>   → anonymisiert Text + Clipboard (keine Quotes nötig)
# ar           → de-anonymisiert Clipboard-Inhalt (löscht Session-Map)
ap() {
  local input="$*"
  if [ -z "$input" ]; then
    echo "Usage: ap: dein text mit sensiblen Daten" >&2
    return 1
  fi
  local anon
  anon=$(printf "%s" "$input" | bash ~/.ai-context/ai-anon.sh --protect)
  if command -v pbcopy &>/dev/null; then
    printf "%s" "$anon" | pbcopy
    echo "→ Anonymisiert in Zwischenablage (Cmd+V)"
  elif command -v xclip &>/dev/null; then
    printf "%s" "$anon" | xclip -selection clipboard
    echo "→ Anonymisiert in Zwischenablage (Ctrl+V)"
  fi
  printf "   \033[0;32m%s\033[0m\n" "$anon"
}
# `?`/`*` in zsh globben sonst (zsh: "no matches found") — noglob schaltet das ab
if [ -n "${ZSH_VERSION:-}" ]; then
  alias "ap:"="noglob ap"
else
  alias "ap:"="ap"
fi
ar() {
  local input="${*:-}"
  if [ -z "$input" ] && command -v pbpaste &>/dev/null; then
    input=$(pbpaste)
  elif [ -z "$input" ] && command -v xclip &>/dev/null; then
    input=$(xclip -selection clipboard -o 2>/dev/null || echo "")
  fi
  if [ -z "$input" ]; then
    echo "Usage: ar \"text mit [P1]...\"  oder  ar (nutzt Clipboard)" >&2
    return 1
  fi
  printf "%s" "$input" | bash ~/.ai-context/ai-anon.sh --restore
}

# Auto-prep: wraps claude command to auto-generate _SESSION.md
claude() {
  if [ -d "_ai_context/scripts" ] && [ -f "_ai_context/scripts/ai-session-prep.sh" ]; then
    printf "\033[0;32m🧠 AI Context Pro: Kontext wird vorbereitet...\033[0m\n"
    _CTX_OUT=$(bash _ai_context/scripts/ai-session-prep.sh 2>/dev/null)
    _CTX_LINE=$(printf "%s\n" "$_CTX_OUT" | grep "^__AI_CTX__:" | head -1)
    if [ -n "$_CTX_LINE" ]; then
      _TOKENS=$(printf "%s" "$_CTX_LINE" | cut -d: -f2)
      _DOMAIN=$(printf "%s" "$_CTX_LINE" | cut -d: -f3)
      printf "\033[0;32m✅ Session bereit (~%s Tokens) — Domain: %s\033[0m\n\n" "$_TOKENS" "$_DOMAIN"
    else
      printf "\033[0;32m✅ Session bereit\033[0m\n\n"
    fi
    unset _CTX_OUT _CTX_LINE _TOKENS _DOMAIN
  fi
  command claude "$@"
}
# <<< AI Context v7.0 END <<<
'
else
  SHELL_BLOCK='
# >>> AI Context v7.0 BEGIN >>>
# (Auto-generated by install.sh — edit between markers only if you know what you do)
alias ai-context-setup="bash ~/.ai-context/setup_ai_context.sh"
alias ai-context-sync="bash _ai_context/scripts/ai-context-sync.sh"
alias ai-prep="bash _ai_context/scripts/ai-session-prep.sh"
alias ai-doctor="bash _ai_context/scripts/ai-context-doctor.sh"
alias ai-verify="bash _ai_context/scripts/ai-verify.sh"
alias ai-map="bash _ai_context/scripts/ai-context-map.sh"
alias ai-migrate="bash ~/.ai-context/migrate.sh"
alias ai-anon="bash ~/.ai-context/ai-anon.sh"
alias ai-stats="bash ~/.ai-context/_ai_context_template/scripts/ai-session-log.sh stats"

# pii-on / pii-off — PII-Schutz ein-/ausschalten (standardmäßig AUS)
pii-on()  { touch ~/.ai-context/pii-mode && printf "\033[0;32m🔒 PII-Schutz aktiviert\033[0m\n"; }
pii-off() { rm -f ~/.ai-context/pii-mode && printf "\033[0;33m🔓 PII-Schutz deaktiviert\033[0m\n"; }

# ap: <text>   → anonymisiert Text + Clipboard (keine Quotes nötig)
# ar           → de-anonymisiert Clipboard-Inhalt (löscht Session-Map)
ap() {
  local input="$*"
  if [ -z "$input" ]; then
    echo "Usage: ap: dein text mit sensiblen Daten" >&2
    return 1
  fi
  local anon
  anon=$(printf "%s" "$input" | bash ~/.ai-context/ai-anon.sh --protect)
  if command -v pbcopy &>/dev/null; then
    printf "%s" "$anon" | pbcopy
    echo "→ Anonymisiert in Zwischenablage (Cmd+V)"
  elif command -v xclip &>/dev/null; then
    printf "%s" "$anon" | xclip -selection clipboard
    echo "→ Anonymisiert in Zwischenablage (Ctrl+V)"
  fi
  printf "   \033[0;32m%s\033[0m\n" "$anon"
}
# `?`/`*` in zsh globben sonst (zsh: "no matches found") — noglob schaltet das ab
if [ -n "${ZSH_VERSION:-}" ]; then
  alias "ap:"="noglob ap"
else
  alias "ap:"="ap"
fi
ar() {
  local input="${*:-}"
  if [ -z "$input" ] && command -v pbpaste &>/dev/null; then
    input=$(pbpaste)
  elif [ -z "$input" ] && command -v xclip &>/dev/null; then
    input=$(xclip -selection clipboard -o 2>/dev/null || echo "")
  fi
  if [ -z "$input" ]; then
    echo "Usage: ar \"text mit [P1]...\"  oder  ar (nutzt Clipboard)" >&2
    return 1
  fi
  printf "%s" "$input" | bash ~/.ai-context/ai-anon.sh --restore
}

# Auto-prep: wraps claude command to auto-generate _SESSION.md
claude() {
  if [ -d "_ai_context/scripts" ] && [ -f "_ai_context/scripts/ai-session-prep.sh" ]; then
    printf "\033[0;32m🧠 AI Context: Kontext wird vorbereitet...\033[0m\n"
    _CTX_OUT=$(bash _ai_context/scripts/ai-session-prep.sh 2>/dev/null)
    _CTX_LINE=$(printf "%s\n" "$_CTX_OUT" | grep "^__AI_CTX__:" | head -1)
    if [ -n "$_CTX_LINE" ]; then
      _TOKENS=$(printf "%s" "$_CTX_LINE" | cut -d: -f2)
      _DOMAIN=$(printf "%s" "$_CTX_LINE" | cut -d: -f3)
      printf "\033[0;32m✅ Session bereit (~%s Tokens) — Domain: %s\033[0m\n\n" "$_TOKENS" "$_DOMAIN"
    else
      printf "\033[0;32m✅ Session bereit\033[0m\n\n"
    fi
    unset _CTX_OUT _CTX_LINE _TOKENS _DOMAIN
  fi
  command claude "$@"
}
# <<< AI Context v7.0 END <<<
'
fi

# --refresh fasst Shell-RC-Dateien nicht an (automatisierter Lauf soll keine
# Nutzer-Dotfiles umschreiben — Marker-Block ändert sich selten; ein manueller
# install.sh-Lauf aktualisiert ihn bei Bedarf).
$REFRESH || for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
  if [ -f "$rc" ]; then
    # Entferne kompletten Block zwischen Markern (neues Format v6.0)
    awk '
      /# >>> AI Context v[0-9.]+ BEGIN >>>/ { skip=1; next }
      /# <<< AI Context v[0-9.]+ END <<</   { skip=0; next }
      skip { next }
      { print }
    ' "$rc" > "${rc}.tmp" 2>/dev/null || cp "$rc" "${rc}.tmp"
    mv "${rc}.tmp" "$rc"

    # Legacy-Zeilen entfernen (alte Installationen vor Marker-Schema)
    awk '
      /# AI Context v[0-9]/ { next }
      /^alias ai-context-setup=|^alias ai-context-sync=|^alias ai-prep=|^alias ai-rag=|^alias ai-registry=|^alias ai-doctor=|^alias ai-verify=|^alias ai-anon=|^alias ai-stats=|^alias ap:=|^alias "ap:"=/ { next }
      /^claude\(\) \{/ { lf=1 }
      lf && /^\}/       { lf=0; next }
      lf                 { next }
      /^ap\(\) \{/       { ap=1 }
      ap && /^\}/        { ap=0; next }
      ap                 { next }
      /^ar\(\) \{/       { ar=1 }
      ar && /^\}/        { ar=0; next }
      ar                 { next }
      { print }
    ' "$rc" > "${rc}.tmp" 2>/dev/null || cp "$rc" "${rc}.tmp"
    mv "${rc}.tmp" "$rc"

    printf '%s\n' "$SHELL_BLOCK" >> "$rc"
    echo -e "${GREEN}✅ Shell-Integration: $rc${NC}"
  fi
done

# =============================================================================
# ---- Summary ----
# =============================================================================
echo ""
echo -e "${GREEN}✅ AI Context v7.0 installiert${NC}"
echo ""

if $PRO_MODE; then
  echo -e "${BOLD}Edition:${NC} ${GREEN}Pro${NC} — Ollama + RAG-Cache + /ai-fix + Cross-Projekt-Transfer"
  echo ""
  echo -e "${BOLD}⚡ Zero-Touch Startup:${NC}"
  echo -e "  Tippe einfach ${GREEN}claude${NC} in einem Projekt mit _ai_context/"
  echo ""
  echo -e "${BOLD}Alle Befehle:${NC}"
  echo -e "  ${CYAN}ai-context-setup [name]${NC}     → Neues Projekt einrichten"
  echo -e "  ${CYAN}ai-migrate${NC}                  → Bestehendes Projekt migrieren"
  echo -e "  ${CYAN}ai-prep${NC}                     → Session manuell vorbereiten"
  echo -e "  ${CYAN}ai-map${NC}                      → Interaction Map generieren"
  echo -e "  ${CYAN}ai-doctor --check${NC}           → Health-Report"
  echo -e "  ${CYAN}ai-doctor --fix${NC}             → Kontext-Defekte auto-reparieren"
  echo -e "  ${CYAN}ai-verify${NC}                   → Projekt-Typecheck/Lint ausführen"
  echo -e "  ${CYAN}ai-registry --find 'auth'${NC}   → Semantische Chunk-Suche"
  echo -e "  ${CYAN}ai-rag --embed-chunks${NC}       → Alle Chunks mit Ollama einbetten"
  echo -e "  ${CYAN}ai-context-sync --export${NC}    → Für Claude Chat (Clipboard)"
  echo ""
  echo -e "${BOLD}Claude Code Skills:${NC}  ${CYAN}/ai-fix${NC}  ${CYAN}/ai-doctor${NC}  ${CYAN}/ai-transfer${NC}"
  echo ""
  if $OLLAMA_OK; then
    echo -e "  ${GREEN}🤖 Ollama:${NC} aktiv — Modell '${EMBED_MODEL}' bereit"
  else
    echo -e "  ${YELLOW}⚠️  Ollama nicht verfügbar — Keyword-Fallback aktiv${NC}"
    echo -e "     Nachrüsten: ${CYAN}brew install ollama && ollama pull $EMBED_MODEL${NC}"
  fi
else
  echo -e "${BOLD}Edition:${NC} ${CYAN}Simple${NC} — Basis-System ohne Ollama/RAG"
  echo ""
  echo -e "${BOLD}⚡ Zero-Touch Startup:${NC}"
  echo -e "  Tippe einfach ${GREEN}claude${NC} in einem Projekt mit _ai_context/"
  echo ""
  echo -e "${BOLD}Verfügbare Befehle:${NC}"
  echo -e "  ${CYAN}ai-context-setup [name]${NC}     → Neues Projekt einrichten"
  echo -e "  ${CYAN}ai-migrate${NC}                  → Bestehendes Projekt migrieren"
  echo -e "  ${CYAN}ai-prep${NC}                     → Session manuell vorbereiten"
  echo -e "  ${CYAN}ai-map${NC}                      → Interaction Map generieren"
  echo -e "  ${CYAN}ai-doctor --check${NC}           → Health-Report (anzeigen)"
  echo -e "  ${CYAN}ai-doctor --fix${NC}             → Kontext-Defekte auto-reparieren"
  echo -e "  ${CYAN}ai-verify${NC}                   → Projekt-Typecheck/Lint ausführen"
  echo -e "  ${CYAN}ai-context-sync --export${NC}    → Für Claude Chat (Clipboard)"
  echo ""
  echo -e "${BOLD}Claude Code Skills:${NC}  ${CYAN}/ai-doctor${NC}"
  echo ""
  echo -e "${BOLD}Pro-Features freischalten:${NC}"
  echo -e "  ${CYAN}bash install.sh --pro${NC}"
  echo -e "  → Ollama • /ai-fix • /ai-transfer • RAG-Cache • Impact-Graph"
fi
echo ""
echo -e "${YELLOW}⚠️  Terminal neu starten oder: source ~/.zshrc${NC}"
echo ""

# =============================================================================
# ---- --migrate-all: alle bekannten Projekte automatisch migrieren ----
# =============================================================================
if $MIGRATE_ALL; then
  echo ""
  echo -e "${BOLD}🔄 --migrate-all — Alle bekannten Projekte aktualisieren${NC}"
  echo ""

  MIGRATE_SCRIPT="$INSTALL_DIR/migrate.sh"
  PROJECTS_DIR="$INSTALL_DIR/projects"

  if [ ! -f "$MIGRATE_SCRIPT" ]; then
    echo -e "${RED}❌ migrate.sh nicht gefunden: $MIGRATE_SCRIPT${NC}"
    echo -e "   Installation unvollständig — install.sh erneut ausführen."
    exit 1
  fi

  # Projekte-Store leer?
  if [ ! -d "$PROJECTS_DIR" ] || [ -z "$(ls -A "$PROJECTS_DIR" 2>/dev/null)" ]; then
    echo -e "${YELLOW}⚠️  Keine bekannten Projekte in $PROJECTS_DIR${NC}"
    echo -e "   Projekte werden automatisch registriert wenn du in einem Projekt"
    echo -e "   ${CYAN}bash _ai_context/scripts/ai-context-sync.sh${NC} ausführst."
    echo ""
    exit 0
  fi

  COUNT_OK=0
  COUNT_SKIP=0
  COUNT_FAIL=0
  FAIL_LOG=""

  for proj_dir in "$PROJECTS_DIR"/*/; do
    [ -d "$proj_dir" ] || continue
    proj_name="$(basename "$proj_dir")"
    meta="$proj_dir/.meta.json"

    # Pfad aus .meta.json lesen (gesetzt von ai-context-sync.sh)
    proj_path=""
    if [ -f "$meta" ]; then
      proj_path="$(grep '"path"' "$meta" 2>/dev/null \
        | sed 's/.*"path"[[:space:]]*:[[:space:]]*"//' \
        | sed 's/".*//' \
        | tr -d '\r')"
    fi

    # Kein Pfad in meta.json
    if [ -z "$proj_path" ]; then
      echo -e "   ${YELLOW}⏭  $proj_name${NC} — kein Pfad in .meta.json"
      echo -e "      (einmalig ${CYAN}ai-context-sync${NC} im Projekt ausführen)"
      COUNT_SKIP=$((COUNT_SKIP + 1))
      continue
    fi

    # Pfad existiert nicht mehr
    if [ ! -d "$proj_path" ]; then
      echo -e "   ${YELLOW}⏭  $proj_name${NC} — Verzeichnis nicht mehr vorhanden"
      echo -e "      $proj_path"
      COUNT_SKIP=$((COUNT_SKIP + 1))
      continue
    fi

    # Kein AI Context Projekt
    if [ ! -d "$proj_path/_ai_context/scripts" ]; then
      echo -e "   ${YELLOW}⏭  $proj_name${NC} — kein _ai_context/scripts/ gefunden"
      COUNT_SKIP=$((COUNT_SKIP + 1))
      continue
    fi

    # Migration ausführen
    printf "   Migriere ${BOLD}%s${NC}..." "$proj_name"
    LOG_FILE="/tmp/aictx-migrate-${proj_name}-$$.log"
    if (cd "$proj_path" && bash "$MIGRATE_SCRIPT" > "$LOG_FILE" 2>&1); then
      echo -e " ${GREEN}✅${NC}"
      COUNT_OK=$((COUNT_OK + 1))
    else
      echo -e " ${RED}❌${NC}"
      FAIL_LOG="$FAIL_LOG\n     $proj_name → $LOG_FILE"
      COUNT_FAIL=$((COUNT_FAIL + 1))
    fi
  done

  echo ""
  echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${BOLD}Migration abgeschlossen${NC}"
  echo -e "  ${GREEN}✅ Migriert:     $COUNT_OK${NC}"
  [ "$COUNT_SKIP" -gt 0 ] && \
    echo -e "  ${YELLOW}⏭  Übersprungen: $COUNT_SKIP${NC}"
  [ "$COUNT_FAIL" -gt 0 ] && {
    echo -e "  ${RED}❌ Fehler:        $COUNT_FAIL${NC}"
    echo -e "${RED}   Logs:${NC}"
    printf '%b\n' "$FAIL_LOG"
  }
  echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""
fi
