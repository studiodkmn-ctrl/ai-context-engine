#!/usr/bin/env bash
# =============================================================================
# check_context_hash.sh — Hash-based Change Detection (v5.2, v7: STOPWORDS via ctx.py)
# Detects file changes that happen OUTSIDE git (npm install, AI edits, codegen)
#
# Usage:
#   bash _ai_context/check_context_hash.sh           # check + update hash
#   bash _ai_context/check_context_hash.sh --update  # force update hash
#   bash _ai_context/check_context_hash.sh --dedup [file]   # Duplikat-Check
#   bash _ai_context/check_context_hash.sh --conflicts      # Konflikt-Scan
#
# Run this at session start (Claude calls it during Startup Sequence).
# =============================================================================

CONTEXT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HASH_FILE="$CONTEXT_DIR/.context_hash"
INDEX_FILE="$CONTEXT_DIR/_ai_index.md"
TEMP_HASH="/tmp/.context_hash_new"

YELLOW='\033[1;33m'; CYAN='\033[0;36m'; GREEN='\033[0;32m'; NC='\033[0m'
# shellcheck disable=SC2034  # Farb-Palette: einheitlich deklariert, nicht jede Farbe wird genutzt
RED='\033[0;31m'

# ---- Registry-basierter Dedup (v6.0) — schneller als Jaccard ----
# Usage: bash check_context_hash.sh --dedup-registry
# Delegiert an ai-context-registry.sh --dedup
if [ "${1:-}" = "--dedup-registry" ]; then
  REGISTRY="$CONTEXT_DIR/registry.yaml"
  REGISTRY_TOOL="$CONTEXT_DIR/scripts/ai-context-registry.sh"
  if [ ! -f "$REGISTRY" ]; then
    echo -e "${YELLOW}⚠️  registry.yaml nicht gefunden.${NC}"
    echo -e "   Bitte zuerst: bash $CONTEXT_DIR/scripts/ai-context-registry.sh --add-anchors && --scan"
    exit 1
  fi
  bash "$REGISTRY_TOOL" --dedup
  exit 0
fi

# ---- Semantische Duplikat-Erkennung (kein API-Key) ----
# Usage: bash check_context_hash.sh --dedup [_gotchas.md]
# Gibt pro Eintragspaar aus wenn Jaccard-Ähnlichkeit > 70%
if [ "${1:-}" = "--dedup" ]; then
  TARGET_FILE="${2:-$CONTEXT_DIR/_gotchas.md}"
  echo -e "${CYAN}🔍 Deduplication-Check: $(basename "$TARGET_FILE")${NC}"
  python3 - "$TARGET_FILE" "$CONTEXT_DIR/scripts/lib" << 'PYEOF'
import re, sys, itertools, pathlib

fpath = pathlib.Path(sys.argv[1])
if not fpath.exists():
    print("Datei nicht gefunden:", sys.argv[1])
    sys.exit(1)

sys.path.insert(0, sys.argv[2])
import ctx as ctxlib  # scripts/lib/ctx.py — konsolidierte STOPWORDS (v7)

content = fpath.read_text(encoding='utf-8')
blocks = re.findall(r'```\s*\n((?:ID:|RULE:)[\s\S]*?)```', content)

def extract_keywords(text):
    words = re.findall(r'[a-zA-Z_][a-zA-Z0-9_]{2,}', text.lower())
    return set(w for w in words if w not in ctxlib.STOPWORDS_DE_EN and len(w) > 3)

def jaccard(s1, s2):
    if not s1 or not s2:
        return 0.0
    return len(s1 & s2) / len(s1 | s2)

print(f"Prüfe {len(blocks)} Einträge (Threshold: 70% Keyword-Overlap)\n")
found = 0
for i, b1 in enumerate(blocks):
    id1 = re.search(r'(?:ID:|RULE:)\s*(\S+)', b1)
    if not id1:
        continue
    kw1 = extract_keywords(b1)
    for j, b2 in enumerate(blocks[i+1:], i+1):
        id2 = re.search(r'(?:ID:|RULE:)\s*(\S+)', b2)
        if not id2:
            continue
        kw2 = extract_keywords(b2)
        sim = jaccard(kw1, kw2)
        if sim >= 0.5:
            print(f"  ⚠️  Potentielle Duplikate ({sim:.0%} Overlap):")
            print(f"       {id1.group(1)}  ↔  {id2.group(1)}")
            print(f"       → Empfehlung: Merge oder einen löschen")
            found += 1

if found == 0:
    print("✅ Keine Duplikate gefunden")
else:
    print(f"\n{found} potentielle Duplikat-Paare → vor Writeback prüfen")
PYEOF
  exit 0
fi

# ---- Konflikt-Scan (ALWAYS vs NEVER, ENABLE vs DISABLE, etc.) ----
# Usage: bash check_context_hash.sh --conflicts
if [ "${1:-}" = "--conflicts" ]; then
  echo -e "${CYAN}🔍 Konflikt-Scan in Kontextdateien...${NC}"
  python3 - "$CONTEXT_DIR" << 'PYEOF'
import re, sys, itertools, pathlib

ctx = pathlib.Path(sys.argv[1])

# Lade Einträge aus allen Wissensdateien
all_entries = []
for fname in ['_gotchas.md', 'debug_patterns.md', 'security.md']:
    fpath = ctx / fname
    if not fpath.exists():
        continue
    content = fpath.read_text(encoding='utf-8')
    blocks = re.findall(r'```\s*\n((?:ID:|RULE:)[\s\S]*?)```', content)
    for block in blocks:
        id_m = re.search(r'(?:ID:|RULE:)\s*(\S+)', block)
        if id_m:
            all_entries.append({'id': id_m.group(1), 'body': block.lower(), 'file': fname})

# Konflikt-Muster: (positiv, negativ) Pattern-Paare
CONFLICT_PAIRS = [
    (r'\balways\b|\bimmer\b|\bpflicht\b|\bmust\b',
     r'\boptional\b|\bsometimes\b|\bbei bedarf\b|\bnur wenn\b'),
    (r'\benable\b|\baktivieren\b|\beinschalten\b',
     r'\bdisable\b|\bdeaktivieren\b|\bausschalten\b'),
    (r'\bauth.*first\b|\bauth.*zuerst\b|\bauth.*check\b',
     r'\bskip.*auth\b|\bno.*auth\b|\bauth.*überspringen\b'),
    (r'\bnew\s+prisma\s*client\b',
     r'\bsingleton\b|\beine\s+instanz\b|\breuse\b'),
    (r'\buse\s+client\b|\bclient\s+component\b',
     r'\bserver\s+component\b|\bserver\s+side\b|\buse\s+server\b'),
]

conflicts = []
for e1, e2 in itertools.combinations(all_entries, 2):
    if e1['id'] == e2['id']:
        continue
    b1, b2 = e1['body'], e2['body']
    for pos_pat, neg_pat in CONFLICT_PAIRS:
        # Konflikt wenn: A hat pos UND B hat neg (oder umgekehrt)
        if (re.search(pos_pat, b1) and re.search(neg_pat, b2)) or \
           (re.search(neg_pat, b1) and re.search(pos_pat, b2)):
            conflicts.append((e1['id'], e1['file'], e2['id'], e2['file']))
            break

if conflicts:
    print(f"⚠️  {len(conflicts)} potentielle Konflikte erkannt:\n")
    for id1, f1, id2, f2 in conflicts:
        print(f"  {id1} ({f1})")
        print(f"    ↔  {id2} ({f2})")
        print(f"  → Letzte/neuere Regel hat Vorrang. Alte ggf. löschen.")
        print()
else:
    print("✅ Keine Konflikte erkannt")
PYEOF
  exit 0
fi

# ---- Generate current hashes ----
generate_hash() {
  {
    # Source files — scan what exists
    [ -d "src" ]     && find src -type f \( -name "*.ts" -o -name "*.tsx" -o -name "*.js" -o -name "*.jsx" \) -exec shasum {} \;
    [ -d "app" ]     && find app -type f \( -name "*.ts" -o -name "*.tsx" \) -exec shasum {} \;
    [ -d "pages" ]   && find pages -type f \( -name "*.ts" -o -name "*.tsx" \) -exec shasum {} \;
    # Python
    [ -d "api" ]     && find api -name "*.py" -exec shasum {} \;
    [ -d "routers" ] && find routers -name "*.py" -exec shasum {} \;
    # Config files
    [ -f "package.json" ]          && shasum package.json
    [ -f "requirements.txt" ]      && shasum requirements.txt
    [ -f "pyproject.toml" ]        && shasum pyproject.toml
    [ -f "prisma/schema.prisma" ]  && shasum prisma/schema.prisma
    [ -f "alembic.ini" ]           && shasum alembic.ini
  } 2>/dev/null | sort
}

# ---- Force update mode ----
if [ "${1:-}" = "--update" ]; then
  generate_hash > "$HASH_FILE"
  echo -e "${GREEN}✅ Context hash updated${NC}"
  exit 0
fi

# ---- First run: create hash baseline ----
if [ ! -f "$HASH_FILE" ]; then
  generate_hash > "$HASH_FILE"
  echo -e "${GREEN}✅ Context hash baseline created${NC}"
  exit 0
fi

# ---- Compare current vs stored ----
generate_hash > "$TEMP_HASH"

if diff -q "$HASH_FILE" "$TEMP_HASH" > /dev/null 2>&1; then
  echo -e "${GREEN}✅ No changes detected outside git${NC}"
  rm -f "$TEMP_HASH"
  exit 0
fi

# ---- Changes found — identify affected files ----
echo ""
echo -e "${YELLOW}⚠️  Changes detected outside git (npm install / AI edits / codegen):${NC}"

CHANGED_FILES=$(diff "$HASH_FILE" "$TEMP_HASH" | grep "^>" | awk '{print $3}' | head -10)

# Map changed files to context files
AFFECTED=()
while IFS= read -r file; do
  echo -e "   ${YELLOW}~  $file${NC}"
  case "$file" in
    *package.json*|*requirements.txt*|*pyproject.toml*)
      AFFECTED+=("architecture.md" "decisions.md") ;;
    *prisma/schema*|*models.py*)
      AFFECTED+=("backend/database.md" "backend/endpoints.md") ;;
    *src/app/api/*|*routers/*|*views.py*)
      AFFECTED+=("backend/endpoints.md") ;;
    *src/components/*)
      AFFECTED+=("frontend/components.md") ;;
    *store/*|*context/*)
      AFFECTED+=("frontend/state.md") ;;
  esac
done <<< "$CHANGED_FILES"

# Deduplicate
# shellcheck disable=SC2207  # Elemente sind Kontext-Dateipfade ohne Whitespace
UNIQUE_AFFECTED=($(echo "${AFFECTED[@]}" | tr ' ' '\n' | sort -u))

# Mark affected context files as ⚠️
for ctx_file in "${UNIQUE_AFFECTED[@]}"; do
  full_path="$CONTEXT_DIR/$ctx_file"
  [ ! -f "$full_path" ] && continue
  echo -e "   ${YELLOW}→ $ctx_file marked ⚠️${NC}"

  # Update domain index staleness (v5.1 two-tier)
  idx_dir="$CONTEXT_DIR/_idx"
  for idx_file in "$idx_dir"/*.md; do
    [ ! -f "$idx_file" ] && continue
    escaped=$(echo "$ctx_file" | sed 's/\//\\\//g')
    sed -i.bak "s/| \`${escaped}\` | ✅ /| \`${escaped}\` | ⚠️ /" "$idx_file" 2>/dev/null
    rm -f "${idx_file}.bak"
  done

  # Fallback: also update _ai_index.md if it has file entries (v5.0 compat)
  if [ -f "$INDEX_FILE" ]; then
    escaped=$(echo "$ctx_file" | sed 's/\//\\\//g')
    sed -i.bak "s/| \`${escaped}\` | ✅ /| \`${escaped}\` | ⚠️ /" "$INDEX_FILE" 2>/dev/null
    rm -f "${INDEX_FILE}.bak"
  fi
done

# Update hash baseline
mv "$TEMP_HASH" "$HASH_FILE"
echo ""
echo -e "${CYAN}   Hash baseline updated. Run 'context-update: file.md' after reviewing.${NC}"
echo ""
