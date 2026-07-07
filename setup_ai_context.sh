#!/usr/bin/env bash
# =============================================================================
# setup_ai_context.sh — v6.5 (MCP-Schicht + Symbol Map + Invariant Layer)
#
# NEU in v6.0:
#   - Universale Stack-Erkennung (20+ Frameworks)
#   - Zweistufiger Index (_idx/ Domain-Indizes)
#   - Feinere Backend-Granularität (auth.md, endpoints.md)
#   - Frontend routing.md
#   - Auto-Sync zum persistenten Store
#   - macOS BSD-sed kompatibel
# =============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

# macOS-portable Hash-Funktion (md5sum existiert nicht auf macOS)
portable_md5() {
  md5sum "$1" 2>/dev/null | cut -d' ' -f1 \
    || md5 -r "$1" 2>/dev/null | cut -d' ' -f1 \
    || echo "n/a"
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -d "$HOME/.ai-context/_ai_context_template" ] && SCRIPT_DIR="$HOME/.ai-context"

TEMPLATE_DIR="$SCRIPT_DIR/_ai_context_template"
HOOKS_DIR="$SCRIPT_DIR/hooks"
TARGET_DIR="$(pwd)"
CONTEXT_DIR="$TARGET_DIR/_ai_context"
GLOBAL_CLAUDE="$HOME/.claude/CLAUDE.md"
TODAY=$(date +"%Y-%m-%d")
PROJECT_NAME="${1:-$(basename "$TARGET_DIR")}"
GIT_HASH=$(git log -1 --format="%H" 2>/dev/null || echo "no-git")

# ---- Universal Stack Detection ----
detect_stack() {
  local stack=""
  local details=""
  
  # JavaScript / TypeScript Ecosystems
  if [ -f "$TARGET_DIR/package.json" ]; then
    local pkg="$TARGET_DIR/package.json"
    
    # Frameworks
    grep -q '"next"' "$pkg" 2>/dev/null && stack="Next.js" && \
      details="${details}$(grep -o '"next": *"[^"]*"' "$pkg" 2>/dev/null | head -1), "
    grep -q '"nuxt"' "$pkg" 2>/dev/null && stack="${stack:+$stack + }Nuxt"
    grep -q '"@angular/core"' "$pkg" 2>/dev/null && stack="${stack:+$stack + }Angular"
    grep -q '"react"' "$pkg" 2>/dev/null && ! echo "$stack" | grep -q "Next" && stack="${stack:+$stack + }React"
    grep -q '"vue"' "$pkg" 2>/dev/null && ! echo "$stack" | grep -q "Nuxt" && stack="${stack:+$stack + }Vue"
    grep -q '"svelte"' "$pkg" 2>/dev/null && stack="${stack:+$stack + }Svelte"
    grep -q '"astro"' "$pkg" 2>/dev/null && stack="${stack:+$stack + }Astro"
    grep -q '"remix"' "$pkg" 2>/dev/null && stack="${stack:+$stack + }Remix"
    
    # Backend
    grep -q '"express"' "$pkg" 2>/dev/null && stack="${stack:+$stack + }Express"
    grep -q '"fastify"' "$pkg" 2>/dev/null && stack="${stack:+$stack + }Fastify"
    grep -q '"hono"' "$pkg" 2>/dev/null && stack="${stack:+$stack + }Hono"
    grep -q '"nestjs"' "$pkg" 2>/dev/null && stack="${stack:+$stack + }NestJS"
    
    # ORM / DB
    grep -q '"prisma"' "$pkg" 2>/dev/null && stack="${stack:+$stack + }Prisma"
    grep -q '"drizzle-orm"' "$pkg" 2>/dev/null && stack="${stack:+$stack + }Drizzle"
    grep -q '"mongoose"' "$pkg" 2>/dev/null && stack="${stack:+$stack + }MongoDB"
    grep -q '"typeorm"' "$pkg" 2>/dev/null && stack="${stack:+$stack + }TypeORM"
    
    # Auth
    grep -q '"next-auth"' "$pkg" 2>/dev/null && stack="${stack:+$stack + }NextAuth"
    grep -q '"@clerk"' "$pkg" 2>/dev/null && stack="${stack:+$stack + }Clerk"
    grep -q '"@supabase"' "$pkg" 2>/dev/null && stack="${stack:+$stack + }Supabase"
    
    # TypeScript
    grep -q '"typescript"' "$pkg" 2>/dev/null && stack="${stack:+$stack + }TypeScript"
  fi
  
  # Python Ecosystems
  for pyfile in "$TARGET_DIR/requirements.txt" "$TARGET_DIR/pyproject.toml" "$TARGET_DIR/Pipfile"; do
    [ ! -f "$pyfile" ] && continue
    grep -qi 'django' "$pyfile" 2>/dev/null && stack="${stack:+$stack + }Django"
    grep -qi 'fastapi' "$pyfile" 2>/dev/null && stack="${stack:+$stack + }FastAPI"
    grep -qi 'flask' "$pyfile" 2>/dev/null && stack="${stack:+$stack + }Flask"
    grep -qi 'sqlalchemy' "$pyfile" 2>/dev/null && stack="${stack:+$stack + }SQLAlchemy"
    grep -qi 'celery' "$pyfile" 2>/dev/null && stack="${stack:+$stack + }Celery"
    grep -qi 'langchain' "$pyfile" 2>/dev/null && stack="${stack:+$stack + }LangChain"
    grep -qi 'anthropic' "$pyfile" 2>/dev/null && stack="${stack:+$stack + }Claude API"
  done
  [ -f "$TARGET_DIR/manage.py" ] && ! echo "$stack" | grep -q "Django" && stack="${stack:+$stack + }Django"
  
  # Rust
  [ -f "$TARGET_DIR/Cargo.toml" ] && stack="${stack:+$stack + }Rust"
  grep -qi 'actix' "$TARGET_DIR/Cargo.toml" 2>/dev/null && stack="${stack:+$stack + }Actix"
  grep -qi 'axum' "$TARGET_DIR/Cargo.toml" 2>/dev/null && stack="${stack:+$stack + }Axum"
  
  # Go
  [ -f "$TARGET_DIR/go.mod" ] && stack="${stack:+$stack + }Go"
  
  # Ruby
  [ -f "$TARGET_DIR/Gemfile" ] && stack="${stack:+$stack + }Ruby"
  grep -qi 'rails' "$TARGET_DIR/Gemfile" 2>/dev/null && stack="${stack:+$stack + }Rails"
  
  # Java / Kotlin
  [ -f "$TARGET_DIR/pom.xml" ] && stack="${stack:+$stack + }Java/Maven"
  [ -f "$TARGET_DIR/build.gradle" ] && stack="${stack:+$stack + }Gradle"
  grep -qi 'spring' "$TARGET_DIR/pom.xml" 2>/dev/null && stack="${stack:+$stack + }Spring"
  grep -qi 'spring' "$TARGET_DIR/build.gradle" 2>/dev/null && stack="${stack:+$stack + }Spring"
  
  # PHP
  [ -f "$TARGET_DIR/composer.json" ] && stack="${stack:+$stack + }PHP"
  grep -qi 'laravel' "$TARGET_DIR/composer.json" 2>/dev/null && stack="${stack:+$stack + }Laravel"
  
  # Mobile
  [ -f "$TARGET_DIR/pubspec.yaml" ] && stack="${stack:+$stack + }Flutter/Dart"
  [ -f "$TARGET_DIR/ios/Podfile" ] && stack="${stack:+$stack + }iOS"
  [ -f "$TARGET_DIR/android/build.gradle" ] && stack="${stack:+$stack + }Android"
  
  # Infra
  [ -f "$TARGET_DIR/Dockerfile" ] && stack="${stack:+$stack + }Docker"
  [ -f "$TARGET_DIR/docker-compose.yml" ] || [ -f "$TARGET_DIR/docker-compose.yaml" ] && \
    ! echo "$stack" | grep -q "Docker" && stack="${stack:+$stack + }Docker Compose"
  [ -f "$TARGET_DIR/terraform.tf" ] || [ -d "$TARGET_DIR/.terraform" ] && stack="${stack:+$stack + }Terraform"
  
  echo "${stack:-Unbekannter Stack}"
}

STACK=$(detect_stack)

# ---- Smart Domain Detection ----
HAS_FRONTEND=false
HAS_BACKEND=false
HAS_DB=false

# Frontend detection
echo "$STACK" | grep -qiE 'react|vue|svelte|angular|next|nuxt|astro|remix|flutter' && HAS_FRONTEND=true
[ -d "$TARGET_DIR/src/components" ] || [ -d "$TARGET_DIR/components" ] || [ -d "$TARGET_DIR/src/app" ] && HAS_FRONTEND=true
[ -d "$TARGET_DIR/lib" ] && ls "$TARGET_DIR/lib"/*.dart 2>/dev/null | head -1 >/dev/null && HAS_FRONTEND=true

# Backend detection
echo "$STACK" | grep -qiE 'express|fastapi|django|flask|rails|spring|laravel|nestjs|hono|fastify|actix|axum' && HAS_BACKEND=true
[ -d "$TARGET_DIR/src/app/api" ] || [ -d "$TARGET_DIR/routers" ] || [ -d "$TARGET_DIR/routes" ] && HAS_BACKEND=true
[ -f "$TARGET_DIR/manage.py" ] || [ -d "$TARGET_DIR/api" ] && HAS_BACKEND=true

# DB detection
echo "$STACK" | grep -qiE 'prisma|drizzle|typeorm|sqlalchemy|mongoose|mongodb' && HAS_DB=true
[ -f "$TARGET_DIR/prisma/schema.prisma" ] || [ -d "$TARGET_DIR/migrations" ] && HAS_DB=true
[ -f "$TARGET_DIR/alembic.ini" ] || [ -d "$TARGET_DIR/prisma" ] && HAS_DB=true
# Django ORM: manage.py + irgendein models.py = DB
[ -f "$TARGET_DIR/manage.py" ] && find "$TARGET_DIR" -maxdepth 3 -name "models.py" -type f 2>/dev/null | grep -q . && HAS_DB=true

# If nothing detected, assume full-stack
if ! $HAS_FRONTEND && ! $HAS_BACKEND; then
  HAS_FRONTEND=true; HAS_BACKEND=true
fi

# ---- Auto-detect paths ----
API_PATH="src/app/api/"
UI_PATH="src/components/"
DB_PATH="prisma/schema.prisma"
AUTH_PATH="src/lib/auth.ts"
STATE_PATH="src/store/"
ROUTE_PATH="src/app/"

# Next.js
[ -d "$TARGET_DIR/src/app/api" ] && API_PATH="src/app/api/"
[ -d "$TARGET_DIR/src/pages/api" ] && API_PATH="src/pages/api/"
[ -f "$TARGET_DIR/src/middleware.ts" ] && AUTH_PATH="src/middleware.ts"

# Django
[ -f "$TARGET_DIR/manage.py" ] && { API_PATH="**/views.py"; DB_PATH="**/models.py"; AUTH_PATH="**/settings.py"; }
[ -d "$TARGET_DIR/api" ] && API_PATH="api/"

# FastAPI
[ -d "$TARGET_DIR/routers" ] && API_PATH="routers/"
[ -d "$TARGET_DIR/app/routers" ] && API_PATH="app/routers/"

# Vue / Nuxt
[ -d "$TARGET_DIR/components" ] && UI_PATH="components/"
[ -d "$TARGET_DIR/stores" ] && STATE_PATH="stores/"
[ -d "$TARGET_DIR/pages" ] && ROUTE_PATH="pages/"

# Go / Rust
[ -f "$TARGET_DIR/go.mod" ] && { API_PATH="handlers/ or cmd/"; DB_PATH="models/ or internal/"; }
[ -f "$TARGET_DIR/Cargo.toml" ] && { API_PATH="src/routes/ or src/handlers/"; DB_PATH="src/models/"; }

# Hashes
PKG_HASH=$(portable_md5 "$TARGET_DIR/package.json" 2>/dev/null || portable_md5 "$TARGET_DIR/requirements.txt" 2>/dev/null || echo "n/a")
SCHEMA_HASH=$(portable_md5 "$TARGET_DIR/prisma/schema.prisma" 2>/dev/null || echo "n/a")
ENV_EXISTS=$([ -f "$TARGET_DIR/.env" ] && echo "yes" || echo "no")

# ---- Header ----
echo ""
echo -e "${BOLD}${BLUE}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${BLUE}║  🧠 AI Context Setup v6.5 — MCP + Symbol Map      ║${NC}"
echo -e "${BOLD}${BLUE}╚══════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${CYAN}Projekt:${NC}   $PROJECT_NAME"
echo -e "${CYAN}Stack:${NC}     $STACK"
echo -e "${CYAN}Frontend:${NC}  $($HAS_FRONTEND && echo "✅ erkannt" || echo "❌ nicht erkannt")"
echo -e "${CYAN}Backend:${NC}   $($HAS_BACKEND && echo "✅ erkannt" || echo "❌ nicht erkannt")"
echo -e "${CYAN}Datenbank:${NC} $($HAS_DB && echo "✅ erkannt" || echo "❌ nicht erkannt")"
echo ""

# ---- Prerequisites ----
if ! git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
  echo -e "${YELLOW}⚠️  Kein Git-Repository. Git Hooks werden nicht installiert.${NC}"
fi

# ---- Determine which templates to skip ----
SKIP_PATTERNS=""
$HAS_FRONTEND || SKIP_PATTERNS="frontend/ _idx/frontend.md _interaction_map.md"
$HAS_BACKEND  || SKIP_PATTERNS="$SKIP_PATTERNS backend/ _idx/backend.md"
$HAS_DB       || SKIP_PATTERNS="$SKIP_PATTERNS backend/database.md"

should_skip() {
  local file="$1"
  for pattern in $SKIP_PATTERNS; do
    echo "$file" | grep -q "$pattern" && return 0
  done
  return 1
}

# ---- Create structure ----
echo -e "${CYAN}▶ Erstelle _ai_context/ Struktur...${NC}"

if [ ! -d "$TEMPLATE_DIR" ]; then
  echo -e "${RED}❌ Template-Verzeichnis nicht gefunden: $TEMPLATE_DIR${NC}"
  exit 1
fi

mkdir -p "$CONTEXT_DIR"/{scripts,_idx}
$HAS_FRONTEND && mkdir -p "$CONTEXT_DIR/frontend"
$HAS_BACKEND && mkdir -p "$CONTEXT_DIR/backend"

# Copy templates with substitution + smart filtering
while IFS= read -r f; do
  relative="${f#$TEMPLATE_DIR/}"
  target="$CONTEXT_DIR/$relative"

  # Skip irrelevant templates
  if should_skip "$relative"; then
    echo -e "   ⏭️  $relative (nicht relevant für $STACK)"
    continue
  fi

  mkdir -p "$(dirname "$target")"

  if [ ! -f "$target" ]; then
    sed \
      -e "s#\[PROJECT_NAME\]#$PROJECT_NAME#g" \
      -e "s#\[DATE\]#$TODAY#g" \
      -e "s#\[GIT_HASH\]#$GIT_HASH#g" \
      -e "s#\[STORE GIT HASH HERE after each session\]#$GIT_HASH#g" \
      -e "s#\[PROJECT_STACK\]#$STACK#g" \
      -e "s#pkg.json hash:.*#pkg.json hash:          sha256:${PKG_HASH}#" \
      -e "s#schema hash:.*#schema hash:            sha256:${SCHEMA_HASH}#" \
      -e "s#.env exists:.*#.env exists:            ${ENV_EXISTS}#" \
      -e "s#src/app/api/#${API_PATH}#g" \
      -e "s#src/components/#${UI_PATH}#g" \
      -e "s#prisma/schema.prisma#${DB_PATH}#g" \
      -e "s#src/lib/auth.ts#${AUTH_PATH}#g" \
      -e "s#src/store/#${STATE_PATH}#g" \
      "$f" > "$target"
    echo -e "${GREEN}✅   $relative${NC}"
  else
    echo -e "${YELLOW}⚠️    $relative existiert bereits${NC}"
  fi
done < <(find "$TEMPLATE_DIR" -name "*.md" -type f)

# Copy scripts
for f in "$TEMPLATE_DIR"/scripts/*.sh; do
  [ ! -f "$f" ] && continue
  target="$CONTEXT_DIR/scripts/$(basename "$f")"
  cp "$f" "$target"
  chmod +x "$target"
done
# scripts/lib/ (ctx.py, synonyms.txt — v7 shared helpers, kein *.sh)
if [ -d "$TEMPLATE_DIR/scripts/lib" ]; then
  mkdir -p "$CONTEXT_DIR/scripts/lib"
  cp -r "$TEMPLATE_DIR/scripts/lib/." "$CONTEXT_DIR/scripts/lib/"
fi
echo -e "${GREEN}✅   Scripts installiert${NC}"

# Copy check_context_hash.sh
if [ -f "$TEMPLATE_DIR/check_context_hash.sh" ]; then
  cp "$TEMPLATE_DIR/check_context_hash.sh" "$CONTEXT_DIR/"
  chmod +x "$CONTEXT_DIR/check_context_hash.sh"
fi

# ---- drawers.yaml (v7 Schubladen-Manifest) — aus erkannter Projektstruktur ----
# Wandelt einen Auto-detect-Pfad (Verzeichnis oder Datei) in ein Glob-Pattern:
#   "src/components/" -> "src/components/**" (Verzeichnis, Trailing-Slash)
#   "**/views.py"      -> unverändert (schon ein Glob)
#   "src/lib/auth.ts"   -> unverändert (Datei mit Extension)
#   "handlers"          -> "handlers/**" (bare Verzeichnisname ohne Slash)
path_to_glob() {
  local p="$1"
  case "$p" in
    *'*'*) printf '%s' "$p" ;;
    */)    printf '%s**' "$p" ;;
    *.*)   printf '%s' "$p" ;;
    *)     printf '%s/**' "$p" ;;
  esac
}

generate_drawers_yaml() {
  local target="$CONTEXT_DIR/drawers.yaml"
  if [ -f "$target" ]; then
    echo -e "${YELLOW}⚠️    drawers.yaml existiert bereits — nicht überschrieben${NC}"
    return
  fi
  local ui_glob api_glob auth_glob data_glob state_glob route_glob
  ui_glob=$(path_to_glob "$UI_PATH")
  api_glob=$(path_to_glob "$API_PATH")
  auth_glob=$(path_to_glob "$AUTH_PATH")
  data_glob=$(path_to_glob "$DB_PATH")
  state_glob=$(path_to_glob "$STATE_PATH")
  route_glob=$(path_to_glob "$ROUTE_PATH")

  cat > "$target" << YAML
# drawers.yaml — Schubladen-Manifest (v7)
# Auto-generiert von setup_ai_context.sh aus der erkannten Projektstruktur ($STACK).
# Erweiterbar: eigene Schubladen ergänzen (z.B. payments, emails, cron) —
# wird nicht überschrieben, wenn diese Datei bereits existiert.
#
# locate() (MCP-Tool) nutzt dieses Manifest zum Routing: Query-Keywords
# treffen eine Schublade -> deren "index"-Datei wird zuerst durchsucht.
version: "7.0"
drawers:
  - id: ui_controls
    label: "Interaktive UI-Elemente"
    index: _interaction_map.md
    match:
      globs: ["$ui_glob", "$route_glob"]
      keywords: [button, nav, menu, link, form, click, dropdown, schaltfläche]

  - id: api
    label: "API-Endpoints"
    index: backend/endpoints.md
    match:
      globs: ["$api_glob"]
      keywords: [endpoint, route, fetch, api]

  - id: auth
    label: "Authentifizierung"
    index: backend/auth.md
    match:
      globs: ["$auth_glob"]
      keywords: [login, session, jwt, auth, anmelden, signin]

  - id: data
    label: "Datenbank/Schema"
    index: backend/database.md
    match:
      globs: ["$data_glob"]
      keywords: [schema, migration, db, query, datenbank]

  - id: state
    label: "Client-State"
    index: frontend/state.md
    match:
      globs: ["$state_glob"]
      keywords: [store, state, context, redux, zustand]

  - id: infra
    label: "Infrastruktur/CI"
    index: decisions.md
    match:
      globs: ["Dockerfile", "docker-compose*.yml", ".github/workflows/**"]
      keywords: [deploy, docker, ci, pipeline, workflow]
YAML
  echo -e "${GREEN}✅   drawers.yaml erstellt (${target#$TARGET_DIR/})${NC}"
}

generate_drawers_yaml

# ---- .claude/settings.json (SessionStart Hook für VS Code, Cursor, JetBrains) ----
CLAUDE_PROJECT_DIR="$TARGET_DIR/.claude"
CLAUDE_SETTINGS_TEMPLATE="$TEMPLATE_DIR/.claude/settings.json"
CLAUDE_SETTINGS_TARGET="$CLAUDE_PROJECT_DIR/settings.json"
if [ -f "$CLAUDE_SETTINGS_TEMPLATE" ]; then
  mkdir -p "$CLAUDE_PROJECT_DIR"
  if [ -f "$CLAUDE_SETTINGS_TARGET" ] && command -v python3 &>/dev/null; then
    # Merge: existierende Settings behalten, fehlende Hooks ergänzen
    python3 - "$CLAUDE_SETTINGS_TARGET" "$CLAUDE_SETTINGS_TEMPLATE" << 'PYMERGE'
import json, sys, pathlib, re
target = pathlib.Path(sys.argv[1])
tmpl   = pathlib.Path(sys.argv[2])
try:
    dst = json.loads(target.read_text(encoding='utf-8'))
except Exception:
    dst = {}
src = json.loads(tmpl.read_text(encoding='utf-8'))

dst_hooks = dst.setdefault("hooks", {})
changed = []

# Merge ignorePatterns (ensure _ai_context/** is always excluded)
src_patterns = src.get("ignorePatterns", [])
dst_patterns = dst.setdefault("ignorePatterns", [])
for p in src_patterns:
    if p not in dst_patterns:
        dst_patterns.append(p)
        changed.append(f"ignorePatterns/{p}")

for event, groups in src.get("hooks", {}).items():
    dst_groups = dst_hooks.setdefault(event, [])
    for g in groups:
        for h in g.get("hooks", []):
            cmd = h.get("command", "")
            sm = re.search(r'([\w-]+\.sh)', cmd)
            needle = sm.group(1) if sm else cmd[:24]
            present = any(
                any(needle in hh.get("command","") for hh in dg.get("hooks",[]))
                for dg in dst_groups
            )
            if not present:
                dst_groups.append({"matcher": g.get("matcher",""), "hooks": [h]})
                changed.append(f"{event}/{needle}")

if changed:
    target.write_text(json.dumps(dst, indent=2, ensure_ascii=False), encoding='utf-8')
    print("MERGED:" + ",".join(changed))
else:
    print("UPTODATE")
PYMERGE
    merge_result=$?
    echo -e "${GREEN}✅   .claude/settings.json (Hooks gemerged in existierende Datei)${NC}"
  elif [ -f "$CLAUDE_SETTINGS_TARGET" ]; then
    echo -e "${YELLOW}⚠️  .claude/settings.json existiert + python3 fehlt — Hooks manuell hinzufügen${NC}"
  else
    cp "$CLAUDE_SETTINGS_TEMPLATE" "$CLAUDE_SETTINGS_TARGET"
    echo -e "${GREEN}✅   .claude/settings.json (SessionStart + UserPromptSubmit Hooks)${NC}"
  fi
fi

# ---- .claude/skills/ (ai-fix, ai-doctor, ai-transfer — stack-agnostisch) ----
CLAUDE_SKILLS_TEMPLATE="$TEMPLATE_DIR/.claude/skills"
if [ -d "$CLAUDE_SKILLS_TEMPLATE" ]; then
  mkdir -p "$CLAUDE_PROJECT_DIR/skills"
  cp -r "$CLAUDE_SKILLS_TEMPLATE/." "$CLAUDE_PROJECT_DIR/skills/"
  echo -e "${GREEN}✅   .claude/skills/ (ai-fix, ai-doctor, ai-transfer)${NC}"
fi

# ---- Git hooks ----
if git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
  GIT_HOOKS_DIR="$(git rev-parse --git-dir)/hooks"
  echo -e "${CYAN}▶ Installiere Git Hooks...${NC}"
  for hook in post-commit commit-msg; do
    if [ -f "$HOOKS_DIR/$hook" ]; then
      cp "$HOOKS_DIR/$hook" "$GIT_HOOKS_DIR/$hook"
      chmod +x "$GIT_HOOKS_DIR/$hook"
      echo -e "${GREEN}✅   $hook${NC}"
    fi
  done
fi

# ---- CLAUDE.md ----
echo -e "${CYAN}▶ Installiere CLAUDE.md...${NC}"
CLAUDE_SOURCE="$SCRIPT_DIR/CLAUDE.md"
if [ -f "$CLAUDE_SOURCE" ]; then
  mkdir -p "$HOME/.claude"
  if [ ! -f "$GLOBAL_CLAUDE" ]; then
    cp "$CLAUDE_SOURCE" "$GLOBAL_CLAUDE"
    echo -e "${GREEN}✅   Global: $GLOBAL_CLAUDE${NC}"
  else
    echo -e "${YELLOW}⚠️    Global existiert — manuell updaten:${NC}"
    echo -e "          cp $CLAUDE_SOURCE $GLOBAL_CLAUDE"
  fi
  if [ ! -f "$TARGET_DIR/CLAUDE.md" ]; then
    cp "$CLAUDE_SOURCE" "$TARGET_DIR/CLAUDE.md"
    echo -e "${GREEN}✅   Projekt: $TARGET_DIR/CLAUDE.md${NC}"
  fi
fi

# ---- .gitignore ----
GITIGNORE="$TARGET_DIR/.gitignore"
touch "$GITIGNORE"
for pattern in "_ai_context/_SESSION.md" "_ai_context/.context_hash" "_ai_context/registry.yaml" "*.bak"; do
  grep -q "$pattern" "$GITIGNORE" 2>/dev/null || printf '%s\n' "$pattern" >> "$GITIGNORE"
done

# ---- .gitattributes ----
GITATTR="$TARGET_DIR/.gitattributes"
if [ ! -f "$GITATTR" ] || ! grep -q "_ai_context" "$GITATTR" 2>/dev/null; then
  echo "_ai_context/*.md merge=union" >> "$GITATTR"
fi

# ---- Auto-Scan: Fill templates with real project data ----
SCAN_SCRIPT="$CONTEXT_DIR/scripts/ai-context-scan.sh"
if [ -f "$SCAN_SCRIPT" ]; then
  echo ""
  echo -e "${CYAN}▶ Scanne Projekt und befülle Kontextdateien...${NC}"
  (cd "$TARGET_DIR" && bash "$SCAN_SCRIPT")
fi

# ---- Registry v6.0: Anker injizieren + registry.yaml aufbauen ----
REGISTRY_SCRIPT="$CONTEXT_DIR/scripts/ai-context-registry.sh"
RAG_CACHE_SCRIPT="$CONTEXT_DIR/scripts/ai-rag-cache.sh"
if [ -f "$REGISTRY_SCRIPT" ]; then
  echo -e "${CYAN}▶ Registry v6.0: Anker injizieren...${NC}"
  bash "$REGISTRY_SCRIPT" --add-anchors 2>/dev/null || true
  echo -e "${CYAN}▶ Registry v6.0: registry.yaml aufbauen...${NC}"
  bash "$REGISTRY_SCRIPT" --scan 2>/dev/null || true
fi

# ---- RAG-Cache v6.0 Sprint 2: SQLite-DB initialisieren ----
if [ -f "$RAG_CACHE_SCRIPT" ]; then
  echo -e "${CYAN}▶ RAG-Cache v6.0: Datenbank initialisieren...${NC}"
  bash "$RAG_CACHE_SCRIPT" --init 2>/dev/null && \
    echo -e "${GREEN}✅   RAG-Cache DB bereit (~/.ai-context/rag.db)${NC}" || true
  # Embeddings generieren wenn Ollama läuft (nicht blockieren)
  if curl -sf http://localhost:11434/api/tags &>/dev/null 2>&1; then
    echo -e "${CYAN}▶ RAG-Cache: Generiere Chunk-Embeddings (Hintergrund)...${NC}"
    bash "$RAG_CACHE_SCRIPT" --embed-chunks "$CONTEXT_DIR/registry.yaml" > /dev/null 2>&1 &
    echo -e "${GREEN}✅   Embedding-Job gestartet (PID $!)${NC}"
  else
    echo -e "${YELLOW}⚠️   Ollama nicht verfügbar — Embeddings werden beim ersten --find generiert.${NC}"
  fi
fi

# ---- Generate Symbol Map + Interface Snapshot (v6.6) ----
if [ -f "$CONTEXT_DIR/scripts/ai-symbol-map.sh" ]; then
  echo -e "${CYAN}▶ Generiere Symbol Map (_idx/symbols.md)...${NC}"
  bash "$CONTEXT_DIR/scripts/ai-symbol-map.sh" 2>/dev/null || true
fi
if [ -f "$CONTEXT_DIR/scripts/ai-interface-snapshot.sh" ]; then
  echo -e "${CYAN}▶ Generiere Interface Snapshot (_idx/interfaces.md)...${NC}"
  bash "$CONTEXT_DIR/scripts/ai-interface-snapshot.sh" 2>/dev/null || true
fi

# ---- Generate Interaction Map (v7) — einmalig beim Setup, danach übernimmt
# der post-commit Hook (bei Komponenten-Änderungen). Nur bei erkanntem
# Frontend; das Script selbst überspringt sich still, wenn 0 Elemente
# gefunden werden (kein sinnloses Leer-File).
if $HAS_FRONTEND && [ -f "$CONTEXT_DIR/scripts/ai-context-map.sh" ]; then
  echo -e "${CYAN}▶ Generiere Interaction Map (_interaction_map.md)...${NC}"
  bash "$CONTEXT_DIR/scripts/ai-context-map.sh" 2>/dev/null || true
fi

# ---- Generate _SESSION.md ----
echo -e "${CYAN}▶ Generiere _SESSION.md...${NC}"
bash "$CONTEXT_DIR/scripts/ai-session-prep.sh"

# ---- Create hash baseline ----
if [ -f "$CONTEXT_DIR/check_context_hash.sh" ]; then
  (cd "$TARGET_DIR" && bash "$CONTEXT_DIR/check_context_hash.sh" --update) > /dev/null 2>&1 || true
fi

# ---- Auto-sync to store ----
if [ -f "$CONTEXT_DIR/scripts/ai-context-sync.sh" ]; then
  bash "$CONTEXT_DIR/scripts/ai-context-sync.sh" sync > /dev/null 2>&1 || true
  echo -e "${GREEN}✅   Kontext gespeichert in ~/.ai-context/projects/$PROJECT_NAME${NC}"
fi

# ---- Summary ----
echo ""
echo -e "${BOLD}${GREEN}═══════════════════════════════════════════════════${NC}"
echo -e "${BOLD}${GREEN}  ✅ AI Context v6.6 Setup abgeschlossen!${NC}"
echo -e "${BOLD}${GREEN}═══════════════════════════════════════════════════${NC}"
echo ""
echo -e "${BOLD}⚡ Einfach tippen:${NC} ${GREEN}claude${NC}"
echo -e "   _SESSION.md wird automatisch generiert, dann startet Claude Code."
echo ""
echo -e "${BOLD}Weitere Befehle:${NC}"
echo -e "  ${CYAN}ai-prep --task API${NC}              → Task-spezifisch (Ollama-RAG automatisch)"
echo -e "  ${CYAN}ai-context-sync --export${NC}        → Für Claude Chat (Clipboard)"
echo -e "  ${CYAN}ai-registry --find 'auth'${NC}       → Semantische Chunk-Suche"
echo -e "  ${CYAN}ai-rag --stats${NC}                  → RAG-Cache Statistiken"
echo -e "  ${CYAN}bash _ai_context/scripts/ai-context-scan.sh${NC} → Projekt neu scannen"
echo -e "  ${CYAN}bash _ai_context/scripts/ai-symbol-map.sh${NC}  → Symbol Map neu generieren"
echo -e "  ${CYAN}bash _ai_context/scripts/ai-interface-snapshot.sh${NC} → Interface Snapshot neu generieren"
echo ""
