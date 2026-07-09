#!/usr/bin/env bash
# =============================================================================
# ai-interface-snapshot.sh — Interface Snapshot Generator (v6.6)
#
# Generiert _idx/interfaces.md: TypeScript interfaces/types mit Feldern.
# Eliminiert ~30% der Interface-Reads: statt shared.ts/types.ts lesen →
# kompakte Tabelle mit Feldern und Quelldatei:Zeile.
#
# Unterstützt: TypeScript interfaces, type aliases, Python TypedDict/dataclass
#
# Usage:
#   bash _ai_context/scripts/ai-interface-snapshot.sh          # → _idx/interfaces.md
#   bash _ai_context/scripts/ai-interface-snapshot.sh --dry    # Statistik only
#   bash _ai_context/scripts/ai-interface-snapshot.sh --stdout # nach stdout
# =============================================================================
set -euo pipefail

CONTEXT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_DIR="$(cd "$CONTEXT_DIR/.." && pwd)"
IDX_DIR="$CONTEXT_DIR/_idx"
OUTPUT_FILE="$IDX_DIR/interfaces.md"
TODAY=$(date +"%Y-%m-%d %H:%M")

GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; NC='\033[0m'

MODE="write"
case "${1:-}" in
  --dry)    MODE="dry" ;;
  --stdout) MODE="stdout" ;;
esac

[ "$MODE" != "stdout" ] && echo -e "${CYAN}🔷 Interface Snapshot — $(basename "$PROJECT_DIR")${NC}"

EXTRACTOR="$(mktemp -t aictx-iface.XXXXXX.py)"
trap 'rm -f "$EXTRACTOR"' EXIT

cat > "$EXTRACTOR" << 'PYEOF'
import re, sys, pathlib

project_dir = pathlib.Path(sys.argv[1])
EXCLUDES = {
    'node_modules', '.git', '.next', 'dist', 'build', 'out',
    '_ai_context', '_ai_context_template', '.venv', 'venv',
    '__pycache__', 'coverage', '.turbo', '.cache', '.svelte-kit',
    '.expo', 'vendor', 'target', '.cargo'
}
EXTS = {'.ts', '.tsx', '.py'}
MAX_FIELDS = 8
MAX_INTERFACES = 120

def extract_ts_interfaces(lines, path_str):
    """Extract TypeScript interface/type definitions with their fields."""
    results = []
    i = 0
    while i < len(lines):
        line = lines[i].strip()

        # interface X { or interface X extends Y {
        m = re.match(r'^(?:export\s+)?interface\s+(\w+)', line)
        if not m:
            # type X = { or type X = Pick<...> & {
            m = re.match(r'^(?:export\s+)?type\s+(\w+)\s*(?:<[^>]*>)?\s*=\s*(?:\w+[^{]*&\s*)?{', line)

        if m:
            name = m.group(1)
            fields = []
            # Collect fields: look for lines inside the braces
            depth = line.count('{') - line.count('}')
            j = i
            if depth <= 0 and '{' not in line:
                i += 1
                continue
            # If opening brace is on same line, start scanning next line
            scan_from = j if '{' in line else j + 1
            for k in range(scan_from, min(scan_from + 40, len(lines))):
                field_line = lines[k].strip()
                if not field_line or field_line.startswith('//') or field_line.startswith('*'):
                    if k == scan_from and depth > 0:
                        depth += field_line.count('{') - field_line.count('}')
                    continue
                depth += field_line.count('{') - field_line.count('}')
                if depth <= 0:
                    break
                # Extract field name (before : or ?)
                fm = re.match(r'^(?:readonly\s+)?(\w+)\s*[\?!]?\s*:', field_line)
                if fm and len(fields) < MAX_FIELDS:
                    fname = fm.group(1)
                    # Mark optional fields
                    if '?' in field_line[:field_line.find(':')]:
                        fname += '?'
                    fields.append(fname)
            if fields:
                results.append((i + 1, name, fields))
                if len(results) >= MAX_INTERFACES:
                    break
        i += 1
    return results

def extract_py_interfaces(lines, path_str):
    """Extract Python TypedDict and dataclass definitions."""
    results = []
    i = 0
    while i < len(lines):
        line = lines[i].strip()
        # class X(TypedDict) or class X(TypedDict, total=False)
        m = re.match(r'^class\s+(\w+)\s*\((?:.*TypedDict|.*BaseModel|.*Protocol)[^)]*\)', line)
        # @dataclass
        is_dataclass = (i > 0 and '@dataclass' in lines[i-1])
        if not m and is_dataclass:
            m = re.match(r'^class\s+(\w+)', line)
        if m:
            name = m.group(1)
            fields = []
            for k in range(i + 1, min(i + 30, len(lines))):
                fl = lines[k].strip()
                if not fl or fl.startswith('#'):
                    continue
                if fl.startswith('class ') or fl.startswith('def '):
                    break
                fm = re.match(r'^(\w+)\s*:', fl)
                if fm and len(fields) < MAX_FIELDS:
                    fields.append(fm.group(1))
            if fields:
                results.append((i + 1, name, fields))
        i += 1
    return results

def walk_files():
    files = []
    for p in sorted(project_dir.rglob('*')):
        if not p.is_file() or p.suffix not in EXTS:
            continue
        rel = p.relative_to(project_dir)
        if any(part in EXCLUDES for part in rel.parts):
            continue
        # Prioritize type/interface files
        name = p.name.lower()
        priority = 0 if any(k in name for k in ('type', 'interface', 'model', 'schema', 'shared')) else 1
        files.append((priority, str(rel), p))
    return sorted(files)

all_results = []  # (file_path, lineno, name, fields)

for _, rel_str, p in walk_files():
    try:
        lines = p.read_text(encoding='utf-8', errors='replace').splitlines()
    except Exception:
        continue
    if p.suffix in ('.ts', '.tsx'):
        syms = extract_ts_interfaces(lines, rel_str)
    elif p.suffix == '.py':
        syms = extract_py_interfaces(lines, rel_str)
    else:
        syms = []
    for lineno, name, fields in syms:
        all_results.append((rel_str, lineno, name, fields))

print(f"COUNT:{len(all_results)}")
for rel_str, lineno, name, fields in all_results:
    fields_str = ', '.join(fields[:MAX_FIELDS])
    if len(fields) > MAX_FIELDS:
        fields_str += ', ...'
    print(f"IFACE:{lineno}:{name}:{rel_str}:{fields_str}")
PYEOF

output=$(python3 "$EXTRACTOR" "$PROJECT_DIR" 2>/dev/null)

if [ -z "$output" ]; then
  [ "$MODE" != "stdout" ] && echo -e "${YELLOW}  ⚠️  Keine Interfaces gefunden${NC}"
  exit 0
fi

count=$(echo "$output" | grep "^COUNT:" | cut -d: -f2)

build_md() {
  echo "# Interface Snapshot — $(basename "$PROJECT_DIR")"
  echo "> Auto-generiert: $TODAY | Neu generieren: \`bash _ai_context/scripts/ai-interface-snapshot.sh\`"
  echo "> $count Interfaces/Types — Format: \`Name  Datei:Zeile  Felder\`"
  echo ""

  while IFS= read -r line; do
    if [[ "$line" == IFACE:* ]]; then
      rest="${line#IFACE:}"
      lineno="${rest%%:*}"; rest="${rest#*:}"
      name="${rest%%:*}";   rest="${rest#*:}"
      file="${rest%%:*}";   fields="${rest#*:}"
      printf "%-30s  %-35s  %s\n" "$name" "$file:$lineno" "$fields"
    fi
  done <<< "$output"
}

result_md="$(build_md)"

case "$MODE" in
  dry)
    echo -e "${GREEN}  ✅ $count Interfaces gefunden (kein Write — dry mode)${NC}"
    ;;
  stdout)
    echo "$result_md"
    ;;
  write)
    mkdir -p "$IDX_DIR"
    echo "$result_md" > "$OUTPUT_FILE"
    echo -e "${GREEN}  ✅ $count Interfaces → $OUTPUT_FILE${NC}"
    ;;
esac
