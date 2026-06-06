#!/usr/bin/env bash
# =============================================================================
# ai-symbol-map.sh — Symbol Map Generator (v6.6)
#
# Generiert _idx/symbols.md: Funktion/Klassen-Namen mit Zeilennummern.
# Eliminiert ~60% der Exploration-Reads: statt 1488 Zeilen lesen → 20 Zeilen.
#
# Unterstützt: TypeScript, JavaScript, Python, Go, Rust
# Kein API-Key, keine Cloud — rein regex-basiert (grep + embedded Python).
#
# Usage:
#   bash _ai_context/scripts/ai-symbol-map.sh          # Standard → _idx/symbols.md
#   bash _ai_context/scripts/ai-symbol-map.sh --dry    # Nur Statistik, kein Write
#   bash _ai_context/scripts/ai-symbol-map.sh --stdout # Ausgabe nach stdout
# =============================================================================
set -euo pipefail

CONTEXT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_DIR="$(cd "$CONTEXT_DIR/.." && pwd)"
IDX_DIR="$CONTEXT_DIR/_idx"
OUTPUT_FILE="$IDX_DIR/symbols.md"
TODAY=$(date +"%Y-%m-%d %H:%M")

GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; NC='\033[0m'

MODE="write"
case "${1:-}" in
  --dry)    MODE="dry" ;;
  --stdout) MODE="stdout" ;;
esac

[ "$MODE" != "stdout" ] && echo -e "${CYAN}🔍 Symbol Map — $(basename "$PROJECT_DIR")${NC}"

# Embedded Python: portabel, kein Dependency-Hell
EXTRACTOR="$(mktemp -t aictx-sym.XXXXXX.py)"
trap 'rm -f "$EXTRACTOR"' EXIT

cat > "$EXTRACTOR" << 'PYEOF'
import re, sys, pathlib

project_dir = pathlib.Path(sys.argv[1])
EXCLUDES = {
    'node_modules', '.git', '.next', 'dist', 'build', 'out',
    '_ai_context', '_ai_context_template', '.venv', 'venv',
    '__pycache__', 'coverage', '.turbo', '.cache', '.svelte-kit',
    '.expo', 'vendor', 'target', '.cargo', 'worktrees', 'skills'
}
EXTS = {'.ts', '.tsx', '.js', '.jsx', '.py', '.go', '.rs'}
MAX_SYMBOLS_PER_FILE = 30
MAX_FILES = 200

# Patterns: (regex, only_if_exported)
TS_PATS = [
    (re.compile(r'^export\s+(?:async\s+)?function\s+(\w+)'), True),
    (re.compile(r'^export\s+const\s+(\w+)\s*(?::\s*\S+\s*)?=\s*(?:async\s*)?\('), True),
    (re.compile(r'^export\s+(?:default\s+)?(?:abstract\s+)?class\s+(\w+)'), True),
    (re.compile(r'^export\s+default\s+(?:async\s+)?function\s+(\w+)'), True),
    (re.compile(r'^(?:async\s+)?function\s+(\w+)'), False),
    (re.compile(r'^const\s+(\w+)\s*(?::\s*\S+\s*)?=\s*(?:async\s*)?\('), False),
]
PY_PATS = [
    (re.compile(r'^(?:async\s+)?def\s+(\w+)'), False),
    (re.compile(r'^class\s+(\w+)'), False),
]
GO_PATS = [
    (re.compile(r'^func\s+(?:\(\w+\s+\*?\w+\)\s+)?(\w+)'), False),
]
RS_PATS = [
    (re.compile(r'^(?:pub(?:\s*\([^)]*\))?\s+)?(?:async\s+)?fn\s+(\w+)'), False),
    (re.compile(r'^(?:pub(?:\s*\([^)]*\))?\s+)?struct\s+(\w+)'), False),
]
EXT_MAP = {
    '.ts': TS_PATS, '.tsx': TS_PATS,
    '.js': TS_PATS, '.jsx': TS_PATS,
    '.py': PY_PATS, '.go': GO_PATS, '.rs': RS_PATS,
}

def get_signature(raw_line):
    """Extrahiert Funktionssignatur ab dem ersten '(' bis zur schließenden ')' (max 70 Zeichen)."""
    start = raw_line.find('(')
    if start == -1:
        return ''
    depth = 0
    chars = []
    for ch in raw_line[start:]:
        if ch == '(':
            depth += 1
        elif ch == ')':
            depth -= 1
            chars.append(ch)
            if depth == 0:
                break
        chars.append(ch) if ch != ')' else None
    # Füge schließende Klammer korrekt ein
    sig = raw_line[start:start + raw_line[start:].find(')') + 1] if ')' in raw_line[start:] else ''
    # Return-Typ für TypeScript `: Type` direkt nach ')'
    after = raw_line[start + len(sig):].strip() if sig else ''
    ret = ''
    if after.startswith(':'):
        ret_match = re.match(r':\s*([^{;]+)', after)
        if ret_match:
            ret = ': ' + ret_match.group(1).strip()
    full = (sig + ret)[:70]
    return full

def get_comment(lines, idx):
    """Extract one-line description from JSDoc or // comment above the symbol."""
    if idx == 0:
        return ''
    prev = lines[idx - 1].strip()
    # Single-line JSDoc: /** ... */ or // ...
    m = re.match(r'^/\*\*?\s*(.+?)\s*\*+/$', prev)
    if m:
        return m.group(1)[:60]
    m = re.match(r'^//+\s*(.+)', prev)
    if m:
        return m.group(1)[:60]
    # Python docstring: look for """ on next line
    if idx + 1 < len(lines):
        nxt = lines[idx + 1].strip()
        m = re.match(r'^"""(.+?)"""', nxt)
        if m:
            return m.group(1)[:60]
        m = re.match(r'^"""(.+)', nxt)
        if m:
            return m.group(1)[:60]
    return ''

def extract_symbols(path):
    ext = path.suffix
    patterns = EXT_MAP.get(ext)
    if not patterns:
        return []
    try:
        lines = path.read_text(encoding='utf-8', errors='replace').splitlines()
    except Exception:
        return []
    results = []
    for i, line in enumerate(lines):
        stripped = line.lstrip()
        for pat, exported_only in patterns:
            m = pat.match(stripped)
            if not m:
                continue
            name = m.group(1)
            if not name or name.startswith('_') and exported_only:
                continue
            # Skip test helpers and internal utilities when exported_only
            if exported_only and name.startswith('_'):
                continue
            desc = get_comment(lines, i)
            sig = get_signature(line)
            results.append((i + 1, name, sig, desc))
            if len(results) >= MAX_SYMBOLS_PER_FILE:
                break
        if len(results) >= MAX_SYMBOLS_PER_FILE:
            break
    return results

def walk_files():
    files = []
    for p in sorted(project_dir.rglob('*')):
        if not p.is_file() or p.suffix not in EXTS:
            continue
        rel = p.relative_to(project_dir)
        if any(part in EXCLUDES for part in rel.parts):
            continue
        files.append((rel, p))
    return files[:MAX_FILES]

files = walk_files()
results = {}
total_syms = 0

for rel, p in files:
    syms = extract_symbols(p)
    if syms:
        results[str(rel)] = syms
        total_syms += len(syms)

# Output format
print(f"FILES:{len(results)} SYMBOLS:{total_syms}")
for rel_path, syms in sorted(results.items()):
    print(f"FILE:{rel_path}")
    for lineno, name, sig, desc in syms:
        # Signatur in desc-Spalte, Name bleibt sauber (kein :-Konflikt im Parser)
        if sig and desc:
            desc_part = f"  {sig}  — {desc}"
        elif sig:
            desc_part = f"  {sig}"
        elif desc:
            desc_part = f"  — {desc}"
        else:
            desc_part = ""
        print(f"  SYM:{lineno}:{name}:{desc_part}")
PYEOF

output=$(python3 "$EXTRACTOR" "$PROJECT_DIR" 2>/dev/null)

if [ -z "$output" ]; then
  [ "$MODE" != "stdout" ] && echo -e "${YELLOW}  ⚠️  Keine Symbole gefunden (Python fehlt oder kein Source-Code)${NC}"
  exit 0
fi

stats=$(echo "$output" | grep "^FILES:")
file_count=$(echo "$stats" | grep -o 'FILES:[0-9]*' | cut -d: -f2)
sym_count=$(echo "$stats" | grep -o 'SYMBOLS:[0-9]*' | cut -d: -f2)

# Build Markdown
build_md() {
  echo "# Symbol Map — $(basename "$PROJECT_DIR")"
  echo "> Auto-generiert: $TODAY | Neu generieren: \`bash _ai_context/scripts/ai-symbol-map.sh\`"
  echo "> $file_count Dateien · $sym_count Symbole · Direkt springen: Datei:Zeilennummer"
  echo ""

  current_file=""
  while IFS= read -r line; do
    if [[ "$line" == FILE:* ]]; then
      current_file="${line#FILE:}"
      echo "## \`$current_file\`"
    elif [[ "$line" == "  SYM:"* ]]; then
      rest="${line#  SYM:}"
      lineno="${rest%%:*}"
      rest2="${rest#*:}"
      name="${rest2%%:*}"
      desc="${rest2#*:}"
      # Align columns (name sauber, sig+comment in desc-Spalte)
      printf "  %-35s L%-6s%s\n" "$name" "$lineno" "$desc"
    fi
  done <<< "$output"
}

result_md="$(build_md)"

case "$MODE" in
  dry)
    echo -e "${GREEN}  ✅ $file_count Dateien, $sym_count Symbole (kein Write — dry mode)${NC}"
    ;;
  stdout)
    echo "$result_md"
    ;;
  write)
    mkdir -p "$IDX_DIR"
    echo "$result_md" > "$OUTPUT_FILE"
    echo -e "${GREEN}  ✅ $file_count Dateien, $sym_count Symbole → $OUTPUT_FILE${NC}"
    ;;
esac
