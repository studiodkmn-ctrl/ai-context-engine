#!/usr/bin/env bash
# =============================================================================
# ai-context-scan.sh — Auto-Fill Context from Real Project (v5.1)
#
# Scannt das echte Projekt und befüllt die Kontextdateien automatisch.
# Kein API-Key nötig — rein dateisystem-basiert.
#
# Was es scannt:
#   - package.json / requirements.txt → Stack + Dependencies
#   - Ordnerstruktur → Komponenten, API-Routen, Models
#   - Schema-Dateien → DB-Modelle + Relationen
#   - .env.example → Env-Variablen
#   - Bestehender Code → Endpoints, Components, State
#
# Usage:
#   bash _ai_context/scripts/ai-context-scan.sh          # Scan + fill
#   bash _ai_context/scripts/ai-context-scan.sh --dry-run # Nur anzeigen
#   bash _ai_context/scripts/ai-context-scan.sh --force   # Überschreibe existierende
# =============================================================================
set -euo pipefail

CONTEXT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_DIR="$(cd "$CONTEXT_DIR/.." && pwd)"
PROJECT_NAME="$(basename "$PROJECT_DIR")"
TODAY=$(date +"%Y-%m-%d")

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
# shellcheck disable=SC2034  # Farb-Palette: einheitlich deklariert, nicht jede Farbe wird genutzt
RED='\033[0;31m'

DRY_RUN=false
FORCE=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true
[[ "${1:-}" == "--force" ]] && FORCE=true

echo -e "${BOLD}🔍 AI Context Scanner — $PROJECT_NAME${NC}"
echo ""

# ---- Helper: write to file (respects dry-run and force) ----
write_context() {
  local file="$1"
  local content="$2"
  local target="$CONTEXT_DIR/$file"
  
  if $DRY_RUN; then
    echo -e "${CYAN}[DRY-RUN] Würde schreiben: $file${NC}"
    echo "$content" | head -5
    echo "  ..."
    return
  fi
  
  # Only overwrite if --force or file has placeholders
  if [ -f "$target" ] && ! $FORCE; then
    if ! grep -q '\[PROJECT_NAME\]\|\[DATE\]\|placeholder\|\[z\.B\.\|\[e\.g\.\|\[VERSION\]\|\[PROJECT_STACK\]\|Health-Check\|auto-generiert' "$target" 2>/dev/null; then
      echo -e "${YELLOW}⚠️  $file bereits befüllt — übersprungen (--force zum Überschreiben)${NC}"
      return
    fi
  fi
  
  mkdir -p "$(dirname "$target")"
  echo "$content" > "$target"
  echo -e "${GREEN}✅ $file${NC}"
}

# ====================================================================
# SCAN 1: Stack + Dependencies → _quick_facts.md
# ====================================================================
echo -e "${CYAN}▶ Scanne Stack + Dependencies...${NC}"

STACK=""
PHASE="MVP"
KEY_DEPS=""
ENV_VARS=""

# Node.js / package.json
if [ -f "$PROJECT_DIR/package.json" ]; then
  # Extract real dependencies
  DEPS=$(python3 -c "
import json, sys
try:
    pkg = json.load(open('$PROJECT_DIR/package.json'))
    deps = list(pkg.get('dependencies', {}).keys())
    dev = list(pkg.get('devDependencies', {}).keys())
    
    # Detect stack
    stack = []
    for d in deps + dev:
        if d == 'next': stack.append('Next.js')
        elif d == 'react' and 'next' not in [x for x in deps]: stack.append('React')
        elif d == 'vue': stack.append('Vue')
        elif d == 'svelte': stack.append('Svelte')
        elif d == '@angular/core': stack.append('Angular')
        elif d == 'express': stack.append('Express')
        elif d == 'fastify': stack.append('Fastify')
        elif d == 'prisma' or d == '@prisma/client': stack.append('Prisma')
        elif d == 'drizzle-orm': stack.append('Drizzle')
        elif d == 'mongoose': stack.append('Mongoose')
        elif d == 'next-auth': stack.append('NextAuth')
        elif d == '@clerk/nextjs': stack.append('Clerk')
        elif d == '@supabase/supabase-js': stack.append('Supabase')
        elif d == 'tailwindcss': stack.append('Tailwind')
        elif d == 'typescript': stack.append('TypeScript')

    # Dedupe — z. B. \"prisma\" + \"@prisma/client\" mappen beide auf 'Prisma'
    stack = list(dict.fromkeys(stack))

    # Get versions for key deps
    key = []
    for s in stack:
        name = s.lower().replace('.js','').replace('css','')
        for d in deps + dev:
            if name in d.lower():
                ver = pkg.get('dependencies',{}).get(d, pkg.get('devDependencies',{}).get(d,''))
                key.append(f'{s} {ver}')
                break
        else:
            key.append(s)
    
    print(' + '.join(stack[:8]) if stack else 'Node.js')
    print(', '.join(key[:8]))
except Exception as e:
    print('Node.js')
    print('')
" 2>/dev/null)
  STACK=$(echo "$DEPS" | head -1)
  KEY_DEPS=$(echo "$DEPS" | tail -1)
fi

# Python
if [ -f "$PROJECT_DIR/requirements.txt" ]; then
  PY_DEPS=$(python3 -c "
lines = open('$PROJECT_DIR/requirements.txt').readlines()
deps = [l.strip().split('==')[0].split('>=')[0] for l in lines if l.strip() and not l.startswith('#')]
stack = []
for d in deps:
    dl = d.lower()
    if 'django' == dl: stack.append('Django')
    elif 'fastapi' == dl: stack.append('FastAPI')
    elif 'flask' == dl: stack.append('Flask')
    elif 'sqlalchemy' == dl: stack.append('SQLAlchemy')
    elif 'anthropic' == dl: stack.append('Claude API')
    elif 'langchain' in dl: stack.append('LangChain')
    elif 'celery' == dl: stack.append('Celery')
print(' + '.join(stack) if stack else 'Python')
print(', '.join(deps[:10]))
" 2>/dev/null)
  STACK="${STACK:+$STACK + }$(echo "$PY_DEPS" | head -1)"
  KEY_DEPS="${KEY_DEPS:+$KEY_DEPS, }$(echo "$PY_DEPS" | tail -1)"
fi

# Rust / Go / Other
[ -f "$PROJECT_DIR/Cargo.toml" ] && STACK="${STACK:+$STACK + }Rust"
[ -f "$PROJECT_DIR/go.mod" ] && STACK="${STACK:+$STACK + }Go"
[ -f "$PROJECT_DIR/Gemfile" ] && STACK="${STACK:+$STACK + }Ruby"
[ -f "$PROJECT_DIR/Dockerfile" ] && STACK="${STACK:+$STACK + }Docker"

STACK="${STACK:-Unbekannter Stack}"

# Env vars from .env.example or .env
ENV_FILE=""
[ -f "$PROJECT_DIR/.env.example" ] && ENV_FILE="$PROJECT_DIR/.env.example"
[ -z "$ENV_FILE" ] && [ -f "$PROJECT_DIR/.env" ] && ENV_FILE="$PROJECT_DIR/.env"

if [ -n "$ENV_FILE" ]; then
  ENV_VARS=$(grep -E '^[A-Z_]+=' "$ENV_FILE" 2>/dev/null | sed 's/=.*//' | head -10 | while read var; do
    echo "$var"
  done)
fi

# Key file paths (auto-detect)
DB_SCHEMA="$(find "$PROJECT_DIR" -maxdepth 3 -name 'schema.prisma' -o -name 'models.py' 2>/dev/null | head -1 | sed "s#$PROJECT_DIR/##")"
AUTH_FILE="$(find "$PROJECT_DIR" -maxdepth 4 -name 'auth.*' -not -path '*/node_modules/*' 2>/dev/null | head -1 | sed "s#$PROJECT_DIR/##")"
API_DIR="$(find "$PROJECT_DIR" -maxdepth 3 -type d \( -name 'api' -o -name 'routers' -o -name 'routes' \) -not -path '*/node_modules/*' 2>/dev/null | head -1 | sed "s#$PROJECT_DIR/##")"
COMP_DIR="$(find "$PROJECT_DIR" -maxdepth 3 -type d -name 'components' -not -path '*/node_modules/*' 2>/dev/null | head -1 | sed "s#$PROJECT_DIR/##")"

echo -e "   Stack: $STACK"
echo -e "   Deps:  $KEY_DEPS"

# Write _quick_facts.md
QF_CONTENT="# ⚡ Quick Facts — $PROJECT_NAME
> **Immer laden. ≤150 Tokens. Nur permanente Fakten.**
> Zuletzt aktualisiert: $TODAY | Auto-generiert von ai-context-scan.sh

## Identity
\`\`\`
Project:  $PROJECT_NAME
Stack:    $STACK
Phase:    $PHASE
Repo:     $PROJECT_DIR
\`\`\`

## 📍 Key File Paths
\`\`\`
${DB_SCHEMA:+DB Schema:       $DB_SCHEMA}
${AUTH_FILE:+Auth:            $AUTH_FILE}
${API_DIR:+API Routes:      $API_DIR/}
${COMP_DIR:+Components:      $COMP_DIR/}
\`\`\`

## 🔑 Environment Variables
\`\`\`
${ENV_VARS:-keine gefunden}
\`\`\`

## 🔗 Quick References
\`\`\`
Sprint / Tasks     → _temp_notes.md
Gotchas            → _gotchas.md
Debug Patterns     → debug_patterns.md
\`\`\`
> RULE: Nur permanente Fakten. Kein Sprint-Info, keine Gotchas."
write_context "_quick_facts.md" "$QF_CONTENT"


# ====================================================================
# SCAN 2: Endpoints → backend/endpoints.md
# ====================================================================
echo -e "${CYAN}▶ Scanne API Endpoints...${NC}"

ENDPOINTS=""

# Next.js App Router: src/app/api/**/route.ts
if [ -d "$PROJECT_DIR/src/app/api" ]; then
  ENDPOINTS=$(find "$PROJECT_DIR/src/app/api" -name 'route.ts' -o -name 'route.js' 2>/dev/null | while read f; do
    path=$(echo "$f" | sed "s#$PROJECT_DIR/src/app##" | sed 's#/route\.[tj]s$##')
    methods=$(grep -oE 'export.*function (GET|POST|PUT|DELETE|PATCH)' "$f" 2>/dev/null | grep -oE 'GET|POST|PUT|DELETE|PATCH' | tr '\n' ',' | sed 's/,$//')
    [ -z "$methods" ] && methods="GET"
    echo "| $methods | $path | ? | auto-detected |"
  done)
fi

# Express/Fastify: router.get/post/put/delete
if [ -z "$ENDPOINTS" ] && [ -n "$API_DIR" ]; then
  ENDPOINTS=$(grep -rnoE '(router|app)\.(get|post|put|delete|patch)\s*\(['\''"]([^'\''"]+)' "$PROJECT_DIR/$API_DIR" 2>/dev/null | head -20 | while IFS= read -r line; do
    method=$(echo "$line" | grep -oE '\.(get|post|put|delete|patch)' | tr -d '.' | tr '[:lower:]' '[:upper:]')
    path=$(echo "$line" | grep -oE "['\"][^'\"]+['\"]" | tr -d "'" | tr -d '"')
    echo "| $method | $path | ? | auto-detected |"
  done)
fi

# Django: urlpatterns
if [ -z "$ENDPOINTS" ] && [ -f "$PROJECT_DIR/manage.py" ]; then
  ENDPOINTS=$(find "$PROJECT_DIR" -name 'urls.py' -not -path '*/node_modules/*' 2>/dev/null | while read f; do
    grep -oE "path\(['\"]([^'\"]+)" "$f" 2>/dev/null | sed "s/path(['\"]//;s/['\"]$//" | while read path; do
      echo "| ? | /$path | ? | auto-detected |"
    done
  done | head -20)
fi

if [ -n "$ENDPOINTS" ]; then
  EP_COUNT=$(printf "%s\n" "$ENDPOINTS" | grep -c "^|" || true)
else
  EP_COUNT=0
fi
echo -e "   $EP_COUNT Endpoints gefunden"

if [ "$EP_COUNT" -gt 0 ]; then
  write_context "backend/endpoints.md" "# 🌐 Endpoints — $PROJECT_NAME
> **Auto-generiert von ai-context-scan.sh am $TODAY**
> $EP_COUNT Endpoints erkannt. Bitte Auth-Spalte manuell prüfen.

## Endpoints
| Method | Path | Auth | Beschreibung |
|---|---|---|---|
$ENDPOINTS

## Env-Variablen (API-relevant)
\`\`\`
$(echo "$ENV_VARS" | grep -iE 'API|URL|SECRET|KEY|TOKEN' || echo "keine gefunden")
\`\`\`
> Writeback: Neuer Endpoint → Tabelle ergänzen."
fi


# ====================================================================
# SCAN 3: Components → frontend/components.md
# ====================================================================
echo -e "${CYAN}▶ Scanne Components...${NC}"

COMPONENTS=""
if [ -n "$COMP_DIR" ] && [ -d "$PROJECT_DIR/$COMP_DIR" ]; then
  COMPONENTS=$(find "$PROJECT_DIR/$COMP_DIR" -maxdepth 2 \( -name '*.tsx' -o -name '*.jsx' -o -name '*.vue' -o -name '*.svelte' \) 2>/dev/null | while read f; do
    name=$(basename "$f" | sed 's/\.[^.]*$//')
    rel=$(echo "$f" | sed "s#$PROJECT_DIR/##")
    # Try to detect if it's a client component (React)
    is_client=""
    grep -q "'use client'" "$f" 2>/dev/null && is_client=" (client)"
    echo "| \`$name\`$is_client | \`$rel\` |"
  done | sort)
fi

if [ -n "$COMPONENTS" ]; then
  COMP_COUNT=$(printf "%s\n" "$COMPONENTS" | grep -c "^|" || true)
else
  COMP_COUNT=0
fi
echo -e "   $COMP_COUNT Components gefunden"

if [ "$COMP_COUNT" -gt 0 ]; then
  write_context "frontend/components.md" "# 🧩 Components — $PROJECT_NAME
> **Auto-generiert von ai-context-scan.sh am $TODAY**
> $COMP_COUNT Components erkannt.

## Component Inventory
| Name | Pfad |
|---|---|
$COMPONENTS

> Writeback: Neue Komponente → Tabelle ergänzen."
fi


# ====================================================================
# SCAN 4: DB Schema → backend/database.md
# ====================================================================
echo -e "${CYAN}▶ Scanne Datenbank-Schema...${NC}"

MODELS=""
if [ -n "$DB_SCHEMA" ] && [ -f "$PROJECT_DIR/$DB_SCHEMA" ]; then
  if echo "$DB_SCHEMA" | grep -q "prisma"; then
    # Prisma schema
    MODELS=$(grep -E '^model ' "$PROJECT_DIR/$DB_SCHEMA" 2>/dev/null | while read line; do
      name=$(echo "$line" | awk '{print $2}')
      fields=$(awk "/^model $name/,/^}/" "$PROJECT_DIR/$DB_SCHEMA" | grep -cE '^\s+\w' 2>/dev/null || echo "?")
      echo "| \`$name\` | $fields Felder |"
    done)
  elif echo "$DB_SCHEMA" | grep -q "models.py"; then
    # Django models
    MODELS=$(grep -E '^class .*(models\.Model)' "$PROJECT_DIR/$DB_SCHEMA" 2>/dev/null | while read line; do
      name=$(echo "$line" | sed 's/class //;s/(.*//;s/://')
      echo "| \`$name\` | Django Model |"
    done)
  fi
fi

if [ -n "$MODELS" ]; then
  MODEL_COUNT=$(printf "%s\n" "$MODELS" | grep -c "^|" || true)
else
  MODEL_COUNT=0
fi
echo -e "   $MODEL_COUNT Models gefunden"

if [ "$MODEL_COUNT" -gt 0 ]; then
  write_context "backend/database.md" "# 🗄️ Database — $PROJECT_NAME
> **Auto-generiert von ai-context-scan.sh am $TODAY**
> $MODEL_COUNT Models erkannt aus \`$DB_SCHEMA\`

## Schema-Übersicht
| Model | Details |
|---|---|
$MODELS

## DB-Konfiguration
\`\`\`
Schema:   $DB_SCHEMA
$(echo "$ENV_VARS" | grep -iE 'DATABASE|DB_|POSTGRES|MONGO|MYSQL' || echo "Env-Vars: nicht erkannt")
\`\`\`
> Writeback: Neues Model → Tabelle ergänzen."
fi


# ====================================================================
# SCAN 5: Architecture → architecture.md
# ====================================================================
echo -e "${CYAN}▶ Scanne Projekt-Struktur...${NC}"

# Top-level structure
STRUCTURE=$(find "$PROJECT_DIR" -maxdepth 2 -type d \
  -not -path '*/node_modules/*' \
  -not -path '*/.git/*' \
  -not -path '*/.next/*' \
  -not -path '*/__pycache__/*' \
  -not -path '*/_ai_context/*' \
  -not -path '*/dist/*' \
  -not -path '*/.venv/*' \
  2>/dev/null | sed "s#$PROJECT_DIR/##" | sort | head -30)

write_context "architecture.md" "# 🏗️ Architecture — $PROJECT_NAME
> **Auto-generiert von ai-context-scan.sh am $TODAY**

## Stack
\`\`\`
$STACK
Key Dependencies: $KEY_DEPS
\`\`\`

## Ordner-Struktur (Top 2 Ebenen)
\`\`\`
$(echo "$STRUCTURE" | sed 's/^/  /')
\`\`\`

## Datenfluss
\`\`\`
[Bitte manuell ergänzen: Client → API → DB Fluss]
\`\`\`
> Writeback: Architektur-Änderungen hier dokumentieren."


# ====================================================================
# UPDATE Domain Indexes
# ====================================================================
echo -e "${CYAN}▶ Aktualisiere Domain-Indizes...${NC}"

# Update token counts in domain indexes
for idx_file in "$CONTEXT_DIR"/_idx/*.md; do
  [ ! -f "$idx_file" ] && continue
  
  # For each referenced file in the index, count real tokens
  while IFS= read -r line; do
    if echo "$line" | grep -q '^\| `'; then
      ref_file=$(echo "$line" | grep -oE '`[^`]+`' | head -1 | tr -d '`' || true)
      [ -z "$ref_file" ] && continue
      ref_path="$CONTEXT_DIR/$ref_file"
      if [ -f "$ref_path" ]; then
        real_tokens=$(($(wc -w < "$ref_path") * 4 / 3))
        # Update the token count in the index line (approximate replacement)
        sed -i.bak "s#| \`${ref_file}\` | ✅ | ~[0-9]* |#| \`${ref_file}\` | ✅ | ~${real_tokens} |#" "$idx_file" 2>/dev/null
        rm -f "${idx_file}.bak"
      fi
    fi
  done < "$idx_file"
done

echo -e "${GREEN}✅ Domain-Indizes aktualisiert${NC}"


# ====================================================================
# Summary
# ====================================================================
echo ""
echo -e "${BOLD}${GREEN}═══════════════════════════════════════════════════${NC}"
echo -e "${BOLD}${GREEN}  🔍 Scan abgeschlossen!${NC}"
echo -e "${BOLD}${GREEN}═══════════════════════════════════════════════════${NC}"
echo ""
echo -e "  Stack:       $STACK"
echo -e "  Endpoints:   $EP_COUNT"
echo -e "  Components:  $COMP_COUNT"
echo -e "  DB Models:   $MODEL_COUNT"
echo ""

# Count total tokens
TOTAL=0
while IFS= read -r f; do
  T=$(($(wc -w < "$f") * 4 / 3))
  TOTAL=$((TOTAL + T))
done < <(find "$CONTEXT_DIR" -name "*.md" -not -name "_SESSION.md" -type f)
echo -e "  ${CYAN}Gesamt-Kontext: ~$TOTAL Tokens (über alle Dateien)${NC}"
echo ""

if ! $DRY_RUN; then
  echo -e "${CYAN}Nächster Schritt:${NC}"
  echo -e "  1. Prüfe die generierten Dateien in _ai_context/"
  echo -e "  2. Ergänze manuell: Auth-Details, Datenfluss, Gotchas"
  echo -e "  3. Starte Claude: ${GREEN}claude${NC}"
fi
echo ""
