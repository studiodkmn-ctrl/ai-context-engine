#!/usr/bin/env bash
# =============================================================================
# ai-agents-sync.sh — Multi-Agent-Adapter generieren (v9-e Baustein E)
#
# _ai_context/ ist bereits agent-neutral (Markdown + Bash) — nur die
# Anbindung fehlt bei Nicht-Claude-Code-Agenten. Erzeugt/aktualisiert 4
# duenne Zeiger-Dateien mit einem Managed-Block: nur der Block zwischen
# <!-- ai-context:managed:start --> und :end wird ersetzt, alles davor/
# danach (eigene Projekt-Konventionen) bleibt unangetastet. Sicher beliebig
# oft erneut ausfuehrbar (idempotent).
#
# AGENTS.md ist die primaere Datei (offener Standard, von Codex/Cursor/
# Gemini CLI/Amp/Jules nativ gelesen) — die anderen 3 verweisen nur darauf.
#
# Usage: bash _ai_context/scripts/ai-agents-sync.sh
# =============================================================================
set -uo pipefail

CONTEXT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_DIR="$(cd "$CONTEXT_DIR/.." && pwd)"
cd "$PROJECT_DIR" || exit 0

MARK_START="<!-- ai-context:managed:start -->"
MARK_END="<!-- ai-context:managed:end -->"

# sync_block <datei> <block-inhalt-datei>
sync_block() {
  local target="$1"
  local block_file="$2"
  mkdir -p "$(dirname "$target")"

  if [ ! -f "$target" ]; then
    { echo "$MARK_START"; cat "$block_file"; echo "$MARK_END"; } > "$target"
    echo "  ✅ $target (neu)"
    return 0
  fi

  local status
  status=$(python3 - "$target" "$block_file" "$MARK_START" "$MARK_END" << 'PYEOF'
import sys, pathlib

target = pathlib.Path(sys.argv[1])
block = pathlib.Path(sys.argv[2]).read_text(encoding="utf-8")
start, end = sys.argv[3], sys.argv[4]

content = target.read_text(encoding="utf-8")
new_block = f"{start}\n{block}{end}"

if start in content and end in content:
    pre = content.split(start, 1)[0]
    post = content.split(end, 1)[1]
    new_content = pre + new_block + post
else:
    sep = "\n\n" if content and not content.endswith("\n\n") else ""
    new_content = content + sep + new_block + "\n"

if new_content != content:
    target.write_text(new_content, encoding="utf-8")
    print("changed")
else:
    print("unchanged")
PYEOF
)
  if [ "$status" = "changed" ]; then
    echo "  ✅ $target (aktualisiert)"
  else
    echo "  →  $target (bereits aktuell)"
  fi
}

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

# ---- AGENTS.md (primaer, offener Standard) ----
cat > "$TMP_DIR/agents.md" << 'EOF'
## AI Context Engine — Navigation

Vor Datei-Suche/-Erstellung bei Bug-Beschreibungen, "wo ist X"-Fragen oder
Code-Aufgaben zuerst ausfuehren:

    bash _ai_context/scripts/ai-symptom-router.sh "<beschreibung>"

Routet ueber Interaction Map, Symbol Map, Gotchas/Debug-Patterns (mit
Frische-Status), Invarianten und Impact-Graph zu den wahrscheinlichsten
Dateien — statt die Codebase blind zu durchsuchen. Kein Treffer? Normal
grep/lesen.

Nach Aufgaben-Abschluss neue Erkenntnisse eintragen — welche Datei
zustaendig ist, steht in `_ai_context/knowledge.manifest.yaml` (Format-
Beispiele: `_ai_context/_gotchas.md`).

Unterstuetzt dein Tool MCP (z.B. Cursor)? `.mcp.json` im Projekt-Root
registriert den `ai-context`-Server mit den Werkzeugen `locate`,
`memory_search`, `memory_save`, `session_context`, `capture_from_diff` —
dann direkt diese nutzen statt der Bash-Route.
EOF

# ---- Duenne Pointer fuer GEMINI.md / Copilot / Cursor-Rules ----
cat > "$TMP_DIR/pointer.md" << 'EOF'
## AI Context Engine

Siehe `AGENTS.md` im Projekt-Root fuer die vollstaendige Anleitung. Kurz:
vor Datei-Suche `bash _ai_context/scripts/ai-symptom-router.sh "<beschreibung>"`
ausfuehren statt die Codebase blind zu durchsuchen.
EOF

echo "🤖 Multi-Agent-Adapter synchronisieren..."
sync_block "AGENTS.md" "$TMP_DIR/agents.md"
sync_block "GEMINI.md" "$TMP_DIR/pointer.md"
sync_block ".github/copilot-instructions.md" "$TMP_DIR/pointer.md"
sync_block ".cursor/rules/ai-context.mdc" "$TMP_DIR/pointer.md"

exit 0
