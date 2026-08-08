#!/usr/bin/env bash
# =============================================================================
# ai-verify-self.sh — End-to-End-Selbsttest der AI Context Engine (v8 Baustein C)
#
# NICHT verwechseln mit ai-verify.sh (führt Typecheck/Lint des NUTZER-Projekts
# aus). Dieses Skript testet die ENGINE selbst: baut ein Dummy-Next.js-Projekt
# in einem Temp-Verzeichnis, richtet AI Context darauf ein und prüft die
# Kernpfade — exakt die manuellen Checks aus dem v7-Rollout, automatisiert.
#
# Checks:
#   1. setup_ai_context.sh läuft durch, _ai_context/ existiert
#   2. drawers.yaml hat die erkannten Projekt-Globs (kein Platzhalter)
#   3. _interaction_map.md enthält den Dummy-Button (Handler + Endpoint)
#   4. ai-context-doctor.sh --check meldet 0 [FAIL]
#   5. locate() (mcp/dist/locate-cli.js) routet eine Button-Query zur
#      Component-Datei
#   6. post-commit invalidiert nach einer API-Änderung backend/endpoints.md
#      wirklich (Wirkung, nicht nur fehlerfreier Durchlauf)
#   7. knowledge.manifest.yaml (v9-a): seed:true-Dateien existieren nach
#      Setup UND tauchen nach Löschen + erneuter Migration wieder auf
#
# Aufruf (aus dem Engine-Repo oder via CI):
#   bash _ai_context_template/scripts/ai-verify-self.sh
#
# Env:
#   AI_CTX_ENGINE_ROOT  Engine-Repo-Root (Default: zwei Ebenen über diesem
#                       Skript, sonst ~/.ai-context)
#   KEEP_SANDBOX=1      Temp-Verzeichnis nach dem Lauf behalten (Debugging)
#
# Exit: 0 = alle Checks PASS | 1 = mindestens ein Check FAIL
# =============================================================================
set -uo pipefail

GREEN='\033[0;32m'; RED='\033[0;31m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Engine-Root auflösen: explizit > Repo-Layout (Skript liegt in
# _ai_context_template/scripts/) > globale Installation.
if [ -n "${AI_CTX_ENGINE_ROOT:-}" ]; then
  ENGINE_ROOT="$AI_CTX_ENGINE_ROOT"
elif [ -f "$SCRIPT_DIR/../../setup_ai_context.sh" ]; then
  ENGINE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
elif [ -f "$HOME/.ai-context/setup_ai_context.sh" ]; then
  ENGINE_ROOT="$HOME/.ai-context"
else
  echo -e "${RED}❌ Engine-Root nicht gefunden (setup_ai_context.sh fehlt).${NC}"
  exit 1
fi

# mktemp: explizites Template statt -t, GNU mktemp verlangt XXXXXX (macOS nicht)
SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/aictx-verify-self.XXXXXX")"
PROJ="$SANDBOX/dummy-next-app"
FAILS=0

cleanup() {
  if [ "${KEEP_SANDBOX:-0}" = "1" ]; then
    echo -e "${YELLOW}Sandbox behalten: $SANDBOX${NC}"
  else
    rm -rf "$SANDBOX"
  fi
}
trap cleanup EXIT

check() { # check <beschreibung> <kommando...>
  local desc="$1"; shift
  if "$@" > /dev/null 2>&1; then
    echo -e "  ${GREEN}✓${NC} $desc"
  else
    echo -e "  ${RED}✗${NC} $desc"
    FAILS=$((FAILS + 1))
  fi
}

echo -e "${CYAN}🧪 ai-verify-self — Engine: $ENGINE_ROOT${NC}"

# ---- Dummy-Next.js-Projekt bauen ----
mkdir -p "$PROJ/src/components" "$PROJ/src/app/api/submit"
cd "$PROJ" || exit 1

cat > package.json << 'EOF'
{
  "name": "dummy-next-app",
  "private": true,
  "dependencies": {
    "next": "14.2.0",
    "react": "18.3.0",
    "typescript": "5.4.0"
  }
}
EOF

cat > src/components/SubmitButton.tsx << 'EOF'
'use client';
import { useState } from 'react';

export function SubmitButton() {
  const [busy, setBusy] = useState(false);

  async function handleSubmit() {
    setBusy(true);
    await fetch('/api/submit', { method: 'POST' });
    setBusy(false);
  }

  return (
    <button onClick={handleSubmit} disabled={busy}>
      Absenden
    </button>
  );
}
EOF

cat > src/app/api/submit/route.ts << 'EOF'
export async function POST(): Promise<Response> {
  return Response.json({ ok: true });
}
EOF

git init -q -b main
git -c user.email=ci@test -c user.name=ci add -A
git -c user.email=ci@test -c user.name=ci commit -qm "dummy app" > /dev/null

# setup_ai_context.sh bevorzugt ~/.ai-context, wenn vorhanden — für einen
# reproduzierbaren Test muss IMMER der Engine-Root unter Test verwendet
# werden, daher Sandbox-HOME.
export HOME="$SANDBOX/home"
mkdir -p "$HOME"

# ---- 1. Setup ----
if bash "$ENGINE_ROOT/setup_ai_context.sh" dummy-next-app > "$SANDBOX/setup.log" 2>&1; then
  echo -e "  ${GREEN}✓${NC} setup_ai_context.sh läuft durch"
else
  echo -e "  ${RED}✗${NC} setup_ai_context.sh fehlgeschlagen — Log:"
  tail -20 "$SANDBOX/setup.log" | sed 's/^/      /'
  FAILS=$((FAILS + 1))
fi
check "struktur: _ai_context/ angelegt"        test -d _ai_context/scripts
check "struktur: registry.yaml vorhanden"      test -f _ai_context/registry.yaml

# ---- 2. drawers.yaml mit erkannten Globs ----
check "drawers: Datei erzeugt"                 test -f _ai_context/drawers.yaml
check "drawers: ui-Glob (src/components)"      grep -q 'src/components/\*\*' _ai_context/drawers.yaml
check "drawers: api-Glob (src/app/api)"        grep -q 'src/app/api/\*\*' _ai_context/drawers.yaml

# ---- 3. Interaction Map ----
bash _ai_context/scripts/ai-context-map.sh > "$SANDBOX/map.log" 2>&1
check "map: SubmitButton erfasst"              grep -q 'SubmitButton' _ai_context/_interaction_map.md
check "map: Handler erkannt"                   grep -q 'handleSubmit' _ai_context/_interaction_map.md
check "map: Endpoint erkannt"                  grep -q '/api/submit' _ai_context/_interaction_map.md

# ---- 4. Doctor: 0 FAIL ----
DOCTOR_OUT="$(bash _ai_context/scripts/ai-context-doctor.sh --check 2>&1 || true)"
FAIL_COUNT="$(printf '%s\n' "$DOCTOR_OUT" | grep -c '\[FAIL\]' || true)"
if [ "${FAIL_COUNT:-0}" -eq 0 ]; then
  echo -e "  ${GREEN}✓${NC} doctor: 0 FAIL"
else
  echo -e "  ${RED}✗${NC} doctor: $FAIL_COUNT FAIL"
  printf '%s\n' "$DOCTOR_OUT" | grep '\[FAIL\]' | sed 's/^/      /'
  FAILS=$((FAILS + 1))
fi

# ---- 5. locate() findet den Button ----
LOCATE_CLI="$ENGINE_ROOT/mcp/dist/locate-cli.js"
if [ -f "$LOCATE_CLI" ] && command -v node > /dev/null 2>&1; then
  LOCATE_OUT="$(node "$LOCATE_CLI" "button klick sendet nicht ab" 2>&1 || true)"
  if printf '%s' "$LOCATE_OUT" | grep -q 'SubmitButton'; then
    echo -e "  ${GREEN}✓${NC} locate: Button-Query → SubmitButton.tsx"
  else
    echo -e "  ${RED}✗${NC} locate: SubmitButton nicht gefunden — Ausgabe:"
    printf '%s\n' "$LOCATE_OUT" | head -10 | sed 's/^/      /'
    FAILS=$((FAILS + 1))
  fi
else
  echo -e "  ${YELLOW}⚠${NC} locate: mcp/dist/locate-cli.js fehlt — vorher bauen: cd mcp && npm run build"
  FAILS=$((FAILS + 1))
fi

# ---- 6. post-commit: Auto-Invalidierung greift wirklich ----
# Regression v8.0.1: invalidate_index schrieb das _idx-Muster (| `file` | ✅ |)
# nach _ai_index.md (Spalte 3, 🟢/🟡/🔴) und war damit vollständig wirkungslos —
# unbemerkt seit v5, weil kein Test die Wirkung geprüft hat. Nur den Aufruf zu
# testen reicht nicht: der Hook lief fehlerfrei durch und tat trotzdem nichts.
PC_HOOK="$ENGINE_ROOT/hooks/post-commit"
IDX_BACKEND="_ai_context/_idx/backend.md"
if [ ! -f "$PC_HOOK" ] || [ ! -f "$IDX_BACKEND" ]; then
  echo -e "  ${YELLOW}⚠${NC} post-commit: Hook oder $IDX_BACKEND fehlt — übersprungen"
  FAILS=$((FAILS + 1))
else
  BEFORE_ROW="$(grep 'backend/endpoints.md' "$IDX_BACKEND" 2>/dev/null || true)"
  if ! printf '%s' "$BEFORE_ROW" | grep -q '✅'; then
    echo -e "  ${RED}✗${NC} post-commit: Ausgangsstatus ist nicht ✅ — Test aussagelos"
    echo "      Zeile: $BEFORE_ROW"
    FAILS=$((FAILS + 1))
  else
    printf '\nexport const revalidate = 0;\n' >> src/app/api/submit/route.ts
    git -c user.email=ci@test -c user.name=ci add -A
    git -c user.email=ci@test -c user.name=ci commit -qm "touch api route" > /dev/null 2>&1
    bash "$PC_HOOK" > "$SANDBOX/post-commit.log" 2>&1
    AFTER_ROW="$(grep 'backend/endpoints.md' "$IDX_BACKEND" 2>/dev/null || true)"
    if printf '%s' "$AFTER_ROW" | grep -q '❌'; then
      echo -e "  ${GREEN}✓${NC} post-commit: API-Änderung invalidiert backend/endpoints.md"
    else
      echo -e "  ${RED}✗${NC} post-commit: Status wurde nicht invalidiert"
      echo "      vorher:  $BEFORE_ROW"
      echo "      nachher: $AFTER_ROW"
      FAILS=$((FAILS + 1))
    fi
  fi
fi

# ---- 7. Manifest-Parität: seed:true-Dateien überstehen eine Migration ----
# Regression v8.1: playbooks.md war zunächst hartcodiert in migrate.sh
# verdrahtet und wurde dort vergessen — 9 Projekte liefen wochenlang ohne
# sie, bis ein manueller Test es zeigte. v9-a macht das generisch über
# knowledge.manifest.yaml; dieser Check beweist, dass die Fehlerklasse
# nicht wiederkommen kann: seed-Dateien müssen nach Setup existieren UND
# nach Löschen + erneuter Migration wieder auftauchen.
MANIFEST="_ai_context/knowledge.manifest.yaml"
CTX_PY="_ai_context/scripts/lib/ctx.py"
if [ ! -f "$MANIFEST" ] || [ ! -f "$CTX_PY" ]; then
  echo -e "  ${YELLOW}⚠${NC} manifest: knowledge.manifest.yaml oder ctx.py fehlt — übersprungen"
  FAILS=$((FAILS + 1))
else
  SEED_FILES="$(python3 "$CTX_PY" list_knowledge_files "$MANIFEST" --seed-only 2>/dev/null)"
  if [ -z "$SEED_FILES" ]; then
    echo -e "  ${YELLOW}⚠${NC} manifest: keine seed:true-Einträge — Test aussagelos"
    FAILS=$((FAILS + 1))
  else
    ALL_PRESENT=true
    while IFS= read -r sf; do
      [ -z "$sf" ] && continue
      [ -f "_ai_context/$sf" ] || ALL_PRESENT=false
    done <<< "$SEED_FILES"
    if $ALL_PRESENT; then
      echo -e "  ${GREEN}✓${NC} manifest: alle seed:true-Dateien nach Setup vorhanden"
    else
      echo -e "  ${RED}✗${NC} manifest: mindestens eine seed:true-Datei fehlt nach Setup"
      FAILS=$((FAILS + 1))
    fi

    # Löschen + Migration erneut laufen lassen → müssen wieder auftauchen
    while IFS= read -r sf; do
      [ -z "$sf" ] && continue
      rm -f "_ai_context/$sf"
    done <<< "$SEED_FILES"
    bash "$ENGINE_ROOT/migrate.sh" > "$SANDBOX/migrate-reseed.log" 2>&1 || true
    RESEEDED=true
    while IFS= read -r sf; do
      [ -z "$sf" ] && continue
      [ -f "_ai_context/$sf" ] || RESEEDED=false
    done <<< "$SEED_FILES"
    if $RESEEDED; then
      echo -e "  ${GREEN}✓${NC} manifest: seed:true-Dateien nach Re-Migration wiederhergestellt"
    else
      echo -e "  ${RED}✗${NC} manifest: seed:true-Dateien NICHT wiederhergestellt — Log:"
      tail -10 "$SANDBOX/migrate-reseed.log" | sed 's/^/      /'
      FAILS=$((FAILS + 1))
    fi
  fi
fi

echo ""
if [ "$FAILS" -eq 0 ]; then
  echo -e "${GREEN}✅ ai-verify-self: alle Checks PASS${NC}"
  exit 0
else
  echo -e "${RED}❌ ai-verify-self: $FAILS Check(s) FAIL${NC}"
  exit 1
fi
