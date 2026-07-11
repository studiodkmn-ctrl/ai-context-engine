#!/usr/bin/env bash
# =============================================================================
# ai-context-map.sh — Interaction Map Generator (v6.5 — Phase 1, v7: verdrahtet + concise-arrow Fix)
#
# Scannt interaktive UI-Elemente (Buttons, Links, Forms) und baut eine
# Ein-Hop-Trace-Tabelle:
#
#   Element → Component-Datei:Zeile → Handler → State/Store → Endpoint
#
# Zweck: "Login-Button reagiert nicht" → Ursache in EINEM Lookup statt
#        grep-from-scratch. Stack-aware: React/Next, Vue, Svelte.
#
# Kein API-Key, keine Cloud — rein dateisystem-basiert (Regex + Brace-Match).
#
# Usage:
#   bash ai-context-map.sh             # Scan + schreibe _interaction_map.md
#   bash ai-context-map.sh --dry-run   # Nur Statistik anzeigen, kein Write
#   bash ai-context-map.sh --stdout    # Tabelle nach stdout
# =============================================================================
set -euo pipefail

CONTEXT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_DIR="$(cd "$CONTEXT_DIR/.." && pwd)"
PROJECT_NAME="$(basename "$PROJECT_DIR")"
MAP_FILE="$CONTEXT_DIR/_interaction_map.md"
TODAY=$(date +"%Y-%m-%d")

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
# shellcheck disable=SC2034  # Farb-Palette: einheitlich deklariert, nicht jede Farbe wird genutzt
RED='\033[0;31m'

MODE="write"
case "${1:-}" in
  --dry-run) MODE="dry" ;;
  --stdout)  MODE="stdout" ;;
esac

[ "$MODE" != "stdout" ] && echo -e "${CYAN}🔗 Interaction Map — $PROJECT_NAME${NC}"

# Python-Extraktor in Temp-Datei schreiben (Heredoc außerhalb von $(),
# damit Backticks im Code nicht als Command-Substitution gelten).
EXTRACTOR="$(mktemp -t aictx-map.XXXXXX.py)"
trap 'rm -f "$EXTRACTOR"' EXIT

cat > "$EXTRACTOR" << 'PYEOF'
import sys, re, pathlib

project_dir = pathlib.Path(sys.argv[1])
EXCLUDES = {'node_modules', '.git', '.next', 'dist', 'build', 'out',
            '_ai_context', '_ai_context_template', '.venv', 'venv',
            '__pycache__', 'coverage', '.turbo', '.cache', '.svelte-kit'}
EXTS = {'.tsx', '.jsx', '.vue', '.svelte', '.js', '.ts'}
MAX_ROWS = 90
QUOTE = '[`\'"]'   # Template-Literal / String-Quote-Klasse

def walk():
    for p in sorted(project_dir.rglob('*')):
        if not p.is_file() or p.suffix not in EXTS:
            continue
        rel = p.relative_to(project_dir)
        if any(part in EXCLUDES for part in rel.parts):
            continue
        if p.stat().st_size > 400_000:
            continue
        yield p, rel

# ---- Handler-Body via Brace-Matching extrahieren ----
def extract_fn_body(content, name):
    if not name or not re.match(r'^[A-Za-z_$][\w$]*$', name):
        return ''
    n = re.escape(name)
    pats = [
        re.compile(r'\b(?:async\s+)?function\s+' + n + r'\s*\([^)]*\)\s*\{'),
        re.compile(r'\b(?:const|let|var)\s+' + n + r'\s*=\s*(?:async\s*)?\([^)]*\)\s*'
                   r'(?::\s*[\w<>\[\] ,|]+\s*)?=>\s*\{'),
        re.compile(r'\b(?:const|let|var)\s+' + n + r'\s*=\s*(?:async\s*)?function\s*\*?\s*'
                   r'\([^)]*\)\s*\{'),
        re.compile(r'(?<![\w$])' + n + r'\s*\([^)]*\)\s*\{'),  # Vue/Methods-Objekt
    ]
    for pat in pats:
        m = pat.search(content)
        if not m:
            continue
        start = content.rindex('{', m.start(), m.end())
        depth = 0
        for i in range(start, min(len(content), start + 6000)):
            c = content[i]
            if c == '{':
                depth += 1
            elif c == '}':
                depth -= 1
                if depth == 0:
                    return content[start:i + 1]
    # v7: knappe Arrow-Function ohne Block-Body — const NAME = (...) => expr;
    # (kein '{' nach '=>', daher kein Brace-Match moeglich — Text bis zum
    # Statement-Ende reicht als Pseudo-Body fuer analyze()'s Endpoint-Suche.)
    concise = re.compile(
        r'\b(?:const|let|var)\s+' + n + r'\s*=\s*(?:async\s*)?\([^)]*\)\s*'
        r'(?::\s*[\w<>\[\] ,|]+\s*)?=>\s*(?!\{)([^\n;]{1,300})')
    m = concise.search(content)
    if m:
        return m.group(1)
    return ''

AXIOS_RE   = re.compile(r'axios(?:\.(get|post|put|patch|delete))?\s*\(\s*' + QUOTE + r'([^`\'"]+)')
APICALL_RE = re.compile(r'\bapi\.(get|post|put|patch|delete)\s*\(\s*' + QUOTE + r'([^`\'"]+)')
FETCH_RE   = re.compile(r'(?:fetch|\$fetch|useFetch|useSWR|useQuery)\s*\(\s*' + QUOTE + r'([^`\'"]+)')
METHOD_OPT = re.compile(r'method\s*:\s*' + QUOTE + r'(\w+)', re.I)
STORE_RE   = re.compile(r'\buse([A-Z][\w]*?)(Store|Context|Dispatch|Selector|Mutation)\b')
NAV_RE     = re.compile(r'(?:router\.(?:push|replace)|navigate|redirect|goto)\s*\(\s*' + QUOTE + r'([^`\'"]+)')

def analyze(body):
    """Aus einem Funktions-/Arrow-Body Endpoint + Store ableiten."""
    if not body:
        return ('', '')
    endpoint = ''
    m = AXIOS_RE.search(body)
    if m:
        endpoint = f'{(m.group(1) or "get").upper()} {m.group(2)}'
    if not endpoint:
        m = APICALL_RE.search(body)
        if m:
            endpoint = f'{m.group(1).upper()} {m.group(2)}'
    if not endpoint:
        m = FETCH_RE.search(body)
        if m:
            meth = 'GET'
            mo = METHOD_OPT.search(body)
            if mo:
                meth = mo.group(1).upper()
            endpoint = f'{meth} {m.group(1)}'
    if not endpoint:
        m = NAV_RE.search(body)
        if m:
            endpoint = f'nav -> {m.group(1)}'
    stores = []
    for sm in STORE_RE.finditer(body):
        s = 'use' + sm.group(1) + sm.group(2)
        if s not in stores:
            stores.append(s)
    return (endpoint, ', '.join(stores[:3]))

def resolve_handler(expr, content):
    """Handler-Ausdruck -> (Anzeigename, Body-zum-Analysieren)."""
    expr = (expr or '').strip()
    if not expr:
        return ('', '')
    if re.fullmatch(r'[A-Za-z_$][\w$.]*', expr):          # reiner Identifier
        name = expr.split('.')[0]
        body = extract_fn_body(content, name)
        return (expr, body or expr)
    cm = re.search(r'([A-Za-z_$][\w$]*)\s*\(', expr)      # Arrow/inline -> erster Call
    if cm:
        body = extract_fn_body(content, cm.group(1))
        if body:
            return (cm.group(1), body)
        return ('(inline)', expr)        # inline-Aktion ohne benannte Funktion
    return ('(inline)', expr)

def brace_value(content, brace_start):
    """Wert eines {...}-Attributs -> (text, end_index der schliessenden '}')."""
    depth = 0
    for i in range(brace_start, min(len(content), brace_start + 800)):
        c = content[i]
        if c == '{':
            depth += 1
        elif c == '}':
            depth -= 1
            if depth == 0:
                return content[brace_start + 1:i].strip(), i
    return '', brace_start

def tag_bounds(content, attr_pos):
    """Grenzen des umschliessenden JSX-Open-Tags fuer eine Attribut-Position."""
    start = content.rfind('<', max(0, attr_pos - 600), attr_pos)
    if start < 0:
        start = max(0, attr_pos - 600)
    depth = 0
    i = attr_pos
    while i < len(content) and i < attr_pos + 1400:
        c = content[i]
        if c == '{':
            depth += 1
        elif c == '}':
            depth -= 1
        elif c == '>' and depth <= 0:
            return start, i
        i += 1
    return start, min(len(content), attr_pos + 200)

LABEL_ATTRS = (r'data-testid\s*=\s*[\'"]([^\'"]+)',
               r'aria-label\s*=\s*[\'"]([^\'"]+)',
               r'\bname\s*=\s*[\'"]([^\'"]+)',
               r'\btitle\s*=\s*[\'"]([^\'"]{2,40})[\'"]')

def label_from(attrs, text):
    """Label NUR aus dem eigenen Tag (attrs) bzw. direktem Textinhalt."""
    for pat in LABEL_ATTRS:
        m = re.search(pat, attrs)
        if m:
            return m.group(1).strip()[:34]
    tm = re.match(r'\s*([A-Za-zÀ-ž0-9 ,.!?&\-]{2,38})', text or '')
    if tm and tm.group(1).strip():
        return tm.group(1).strip()
    return ''

def text_after(content, gt_pos):
    """Direkter Textinhalt nach dem schliessenden '>' eines Open-Tags."""
    seg = content[gt_pos + 1:gt_pos + 120]
    cut = seg.find('<')
    return seg[:cut] if cut >= 0 else seg

def submit_label(content, form_gt):
    """Label des Submit-Buttons innerhalb eines <form> — ein Formular wird vom
    Nutzer ueber seinen Button-Text beschrieben, nicht ueber den Handler."""
    seg = content[form_gt:form_gt + 900]
    bm = re.search(r'<button\b', seg)
    if not bm:
        return ''
    bs, bgt = tag_bounds(content, form_gt + bm.start() + 1)
    return label_from(content[bs:bgt], text_after(content, bgt))

COMP_DECL_RE = re.compile(
    r'(?:export\s+(?:default\s+)?)?(?:function|const|class)\s+([A-Z][\w]*)')

def line_of(content, pos):
    return content.count('\n', 0, pos) + 1

HANDLER_RE = re.compile(r'on(Click|Submit)\s*=\s*\{')
LINKTAG_RE = re.compile(r'<(Link|NavLink|a)\b([^>]*?)>', re.S)
HREF_RE    = re.compile(r'(?:href|to)\s*=\s*(?:[`\'"]([^`\'"]+)|\{[`\'"]?([^}`\'"]+))')
VUE_CLICK_RE = re.compile(r'@(?:click|submit)(?:\.\w+)*\s*=\s*"([^"]+)"')
VUE_LINK_RE  = re.compile(r'<(router-link|RouterLink|NuxtLink)\b([^>]*?)>', re.S)
SV_CLICK_RE  = re.compile(r'on:(?:click|submit)(?:\|\w+)*\s*=\s*\{')

rows = []
seen = set()
stats = {'files': 0, 'react': 0, 'vue': 0, 'svelte': 0}

def add(rel, line, kind, label, handler, store, endpoint):
    key = (str(rel), line)
    if key in seen:
        return
    seen.add(key)
    rows.append((str(rel), line, kind, label, handler, store, endpoint))

for path, rel in walk():
    try:
        content = path.read_text(encoding='utf-8', errors='ignore')
    except Exception:
        continue
    stats['files'] += 1
    suffix = path.suffix

    # Store-Hooks auf Komponenten-Ebene (Fallback wenn Handler-Body keinen nennt)
    _fs = []
    for sm in STORE_RE.finditer(content):
        s = 'use' + sm.group(1) + sm.group(2)
        if s not in _fs:
            _fs.append(s)
    file_stores = ', '.join(_fs[:3])

    def add_link(m, attrs):
        hm = HREF_RE.search(attrs)
        if not hm:
            return
        href = hm.group(1) or hm.group(2) or ''
        if not href or href.startswith('http') or href == '#':
            return
        label = label_from(attrs, text_after(content, m.end() - 1)) or href
        add(rel, line_of(content, m.start()), 'link', label, '-', '',
            f'nav -> {href}')

    if suffix in ('.tsx', '.jsx', '.js', '.ts'):
        for m in HANDLER_RE.finditer(content):
            line = line_of(content, m.start())
            kind = 'form' if m.group(1) == 'Submit' else 'button'
            expr, _ = brace_value(content, m.end() - 1)
            hname, body = resolve_handler(expr, content)
            endpoint, store = analyze(body)
            tstart, tgt = tag_bounds(content, m.start())
            label = label_from(content[tstart:tgt], text_after(content, tgt))
            if kind == 'form':
                label = submit_label(content, tgt) or label
            label = label or hname or '-'
            add(rel, line, kind, label, hname or '-', store or file_stores, endpoint)
            stats['react'] += 1
        for m in LINKTAG_RE.finditer(content):
            add_link(m, m.group(2))

    elif suffix == '.vue':
        stats['vue'] += 1
        for m in VUE_CLICK_RE.finditer(content):
            line = line_of(content, m.start())
            hname, body = resolve_handler(m.group(1), content)
            endpoint, store = analyze(body)
            tstart, tgt = tag_bounds(content, m.start())
            label = label_from(content[tstart:tgt],
                               text_after(content, tgt)) or hname or '-'
            add(rel, line, 'button', label, hname or '-', store or file_stores, endpoint)
        for m in VUE_LINK_RE.finditer(content):
            add_link(m, m.group(2))

    elif suffix == '.svelte':
        stats['svelte'] += 1
        for m in SV_CLICK_RE.finditer(content):
            line = line_of(content, m.start())
            expr, _ = brace_value(content, m.end() - 1)
            hname, body = resolve_handler(expr, content)
            endpoint, store = analyze(body)
            tstart, tgt = tag_bounds(content, m.start())
            label = label_from(content[tstart:tgt],
                               text_after(content, tgt)) or hname or '-'
            add(rel, line, 'button', label, hname or '-', store or file_stores, endpoint)
        for m in LINKTAG_RE.finditer(content):
            add_link(m, m.group(2))

rows.sort(key=lambda r: (r[0], r[1]))
truncated = len(rows) > MAX_ROWS
rows = rows[:MAX_ROWS]

ICON = {'button': '\U0001f518 button', 'form': '\U0001f4cb form', 'link': '\U0001f517 link'}

def cell(s):
    return (s or '-').replace('|', '\\|').replace('\n', ' ').strip()[:48] or '-'

out = ['| Element | Component:Zeile | Handler | State/Store | Endpoint |',
       '|---|---|---|---|---|']
for f, line, kind, label, handler, store, endpoint in rows:
    out.append(f'| {ICON.get(kind, kind)} `{cell(label)}` | `{f}:{line}` | '
               f'`{cell(handler)}` | {cell(store)} | {cell(endpoint)} |')

print(f'STATS files={stats["files"]} react={stats["react"]} '
      f'vue={stats["vue"]} svelte={stats["svelte"]} '
      f'elements={len(seen)} truncated={"yes" if truncated else "no"}')
print('\n'.join(out))
PYEOF

MAP_BODY="$(python3 "$EXTRACTOR" "$PROJECT_DIR")"

STATS_LINE="$(printf '%s\n' "$MAP_BODY" | head -1)"
TABLE="$(printf '%s\n' "$MAP_BODY" | tail -n +2)"

ELEMENTS="$(echo "$STATS_LINE" | grep -oE 'elements=[0-9]+' | cut -d= -f2)"
FILES="$(echo "$STATS_LINE" | grep -oE 'files=[0-9]+' | cut -d= -f2)"
ELEMENTS="${ELEMENTS:-0}"; FILES="${FILES:-0}"

# Kein Frontend gefunden -> keine sinnlose leere Datei erzeugen (Apple-Prinzip)
if [ "$ELEMENTS" = "0" ]; then
  [ "$MODE" != "stdout" ] && \
    echo -e "   ${YELLOW}Keine interaktiven UI-Elemente gefunden — Map übersprungen.${NC}"
  exit 0
fi

MAP_CONTENT="# Interaction Map — $PROJECT_NAME
> **Auto-generiert von ai-context-map.sh am $TODAY. Nicht manuell editieren.**
> Zweck: Bug in einem UI-Element -> Ursache in 1 Lookup (statt grep-from-scratch).
> Regeneriert via post-commit Hook bei Komponenten-Änderungen.

## Interaktive Elemente
> $ELEMENTS Elemente aus $FILES Dateien. Spalten: was klickbar ist ->
> wo es lebt -> welche Funktion -> welcher State -> welcher API-Call.

$TABLE

---
> Lesart Bug-Fix: kaputtes Element in Spalte 1 finden -> Spalten 2-5 sind
> die Verdächtigen. Fehlt eine Spalte (-), ist dort nichts verdrahtet.
"

if [ "$MODE" = "stdout" ]; then
  printf '%s\n' "$MAP_CONTENT"
  exit 0
fi

if [ "$MODE" = "dry" ]; then
  echo -e "   ${CYAN}[DRY-RUN]${NC} $ELEMENTS Elemente, $FILES Dateien — kein Write"
  echo "   $STATS_LINE"
  exit 0
fi

printf '%s\n' "$MAP_CONTENT" > "$MAP_FILE"
echo -e "   ${GREEN}✅ _interaction_map.md${NC} — $ELEMENTS Elemente aus $FILES Dateien"
