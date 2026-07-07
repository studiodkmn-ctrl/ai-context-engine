#!/usr/bin/env bash
# =============================================================================
# ai-context-doctor.sh — Selbst-Reparatur des Kontext-Systems (v6.5 — Phase 4)
#
# Erkennt Defekte in _ai_context/ und repariert mechanische selbst.
# Orchestriert bestehende Tools (check_context_hash.sh, ai-context-registry.sh),
# ergänzt nur die echten Lücken.
#
# Checks:
#   - Anker fehlen          (mechanisch fixbar)
#   - Interaction-Map-Drift (mechanisch fixbar)
#   - Kaputte ⇒-Pointer     (für Claude)
#   - Platzhalter-Reste     (für Claude)
#   - Tote @-Referenzen     (für Claude)
#   - Index ↔ Datei         (für Claude)
#   - Übergroße Dateien     (für Claude)
#   - Regel-Konflikte       (für Claude — via check_context_hash.sh)
#   - Script-Drift (W7)     (für Claude — Projekt-Kopie ↔ globales Template)
#
# Usage:
#   bash ai-context-doctor.sh            # --check: Health-Report (exit 0/1)
#   bash ai-context-doctor.sh --fix      # mechanische Defekte reparieren
#   bash ai-context-doctor.sh --session  # still fixen, EINE Zeile (SessionStart)
# =============================================================================
set -uo pipefail

CONTEXT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_DIR="$(cd "$CONTEXT_DIR/.." && pwd)"
PROJECT_NAME="$(basename "$PROJECT_DIR")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; RED='\033[0;31m'; NC='\033[0m'

MODE="check"
case "${1:-}" in
  --fix)     MODE="fix" ;;
  --session) MODE="session" ;;
  --check|"") MODE="check" ;;
  *) echo "Usage: ai-context-doctor.sh [--check|--fix|--session]" >&2; exit 2 ;;
esac

# --fix ist Pro-only (Simple: zurückfallen auf --check mit Hinweis)
if [ "$MODE" = "fix" ] && [ "$(cat "$HOME/.ai-context/edition" 2>/dev/null || echo simple)" != "pro" ]; then
  echo -e "${YELLOW}⚠️  --fix ist AI Context Pro (automatische Reparatur).${NC}"
  echo -e "   --check läuft weiterhin — zeigt alle Defekte an."
  echo -e "   Upgrade: ${CYAN}bash ~/.ai-context/install.sh --pro${NC}"
  echo ""
  MODE="check"
fi

CHECKER="$(mktemp -t aictx-doctor.XXXXXX.py)"
REPORT="$(mktemp -t aictx-doctor.XXXXXX.txt)"
trap 'rm -f "$CHECKER" "$REPORT"' EXIT

cat > "$CHECKER" << 'PYEOF'
import sys, re, pathlib, subprocess

ctx = pathlib.Path(sys.argv[1])
proj = pathlib.Path(sys.argv[2])

sys.path.insert(0, sys.argv[3])
import ctx as ctxlib  # scripts/lib/ctx.py — shared token/registry/freshness helpers (v7)

KNOWLEDGE = ['_gotchas.md', 'debug_patterns.md', 'security.md', 'testing.md',
             'backend/auth.md', 'backend/database.md', 'backend/endpoints.md',
             'frontend/components.md', 'frontend/state.md', 'frontend/routing.md']

results = []  # (check_id, status, fixkind, message, [details])

def emit(cid, status, fixkind, msg, details=None):
    results.append((cid, status, fixkind, msg, details or []))

def context_md_files():
    for p in sorted(ctx.rglob('*.md')):
        if p.name == '_SESSION.md':
            continue
        if '_cache' in p.parts:
            continue
        yield p

def rel(p):
    return str(p.relative_to(ctx))

def est_tokens(text):
    return ctxlib.count_tokens(text)

# ---- alle Anker projektweit sammeln (für Pointer-Check) ----
all_anchors = set()
anchor_re = re.compile(r'<!-- #(\w+) -->')
for p in context_md_files():
    for m in anchor_re.finditer(p.read_text(encoding='utf-8', errors='ignore')):
        all_anchors.add(m.group(1))

# ============================ Check 1: Anker fehlen ========================
block_re = re.compile(r'```[ \t]*\n(?:ID:|RULE:)\s*(\S+)', re.MULTILINE)
missing_anchor = []
for rf in KNOWLEDGE:
    fp = ctx / rf
    if not fp.exists():
        continue
    content = fp.read_text(encoding='utf-8', errors='ignore')
    for m in block_re.finditer(content):
        cid = m.group(1)
        if cid.startswith('_') or cid.lower() == 'template':
            continue
        if f'<!-- #{cid} -->' not in content:
            missing_anchor.append(f'{cid} ({rf})')
if missing_anchor:
    emit('anchors', 'WARN', 'MECH',
         f'{len(missing_anchor)} Block/Bloecke ohne HTML-Anker', missing_anchor)
else:
    emit('anchors', 'PASS', 'MECH', 'alle ID:/RULE:-Bloecke verankert')

# ====================== Check 2: kaputte ⇒-Pointer =========================
broken_ptr = []
ptr_re = re.compile(r'⇒\s*([^\s,)]+)')
for p in context_md_files():
    for ln, line in enumerate(p.read_text(encoding='utf-8', errors='ignore').splitlines(), 1):
        if '⇒' not in line or '⇒ =' in line or 'Pointer' in line:
            continue
        for m in ptr_re.finditer(line):
            tok = m.group(1).strip().rstrip('.`')
            if '.md' in tok:
                fpart, _, anchor = tok.partition('#')
                target = ctx / fpart
                if not target.exists():
                    # auch nur Basename in bekannten Ordnern testen
                    cand = list(ctx.rglob(pathlib.Path(fpart).name))
                    if not cand:
                        broken_ptr.append(f'⇒ {tok} — Datei fehlt ({rel(p)}:{ln})')
                        continue
                    target = cand[0]
                if anchor and f'<!-- #{anchor} -->' not in \
                        target.read_text(encoding='utf-8', errors='ignore'):
                    broken_ptr.append(f'⇒ {tok} — Anker fehlt ({rel(p)}:{ln})')
            elif tok.startswith('#'):
                if tok[1:] not in all_anchors:
                    broken_ptr.append(f'⇒ {tok} — Anker unbekannt ({rel(p)}:{ln})')
if broken_ptr:
    emit('pointers', 'WARN', 'CLAUDE',
         f'{len(broken_ptr)} kaputte ⇒-Verweise', broken_ptr)
else:
    emit('pointers', 'PASS', 'NONE', 'alle ⇒-Verweise gueltig')

# ====================== Check 3: Platzhalter-Reste =========================
# Nur echte Substitutions-Platzhalter (setup ersetzt diese) — NICHT [e.g.]/[z.B.],
# das sind Vorlagen-Hinweise und kein Defekt.
PLACEHOLDERS = ['[PROJECT_NAME]', '[DATE]', '[GIT_HASH]', '[PROJECT_STACK]',
                '[VERSION]']
ph_hits = []
for p in context_md_files():
    content = p.read_text(encoding='utf-8', errors='ignore')
    for ph in PLACEHOLDERS:
        if ph in content:
            ph_hits.append(f'{ph} in {rel(p)}')
if ph_hits:
    emit('placeholders', 'WARN', 'CLAUDE',
         f'{len(ph_hits)} Platzhalter-Rest(e)', ph_hits)
else:
    emit('placeholders', 'PASS', 'NONE', 'keine Platzhalter-Reste')

# ====================== Check 4: tote @-Referenzen =========================
CODE_EXT = ('.ts', '.tsx', '.js', '.jsx', '.py', '.go', '.rs', '.vue',
            '.svelte', '.prisma', '.rb', '.php', '.java', '.kt')
dead_refs = []
ref_re = re.compile(r'^@\s*(.+)$', re.MULTILINE)
for rf in ['_gotchas.md', 'debug_patterns.md', 'security.md']:
    fp = ctx / rf
    if not fp.exists():
        continue
    for m in ref_re.finditer(fp.read_text(encoding='utf-8', errors='ignore')):
        for tok in re.split(r'[,\s]+', m.group(1).strip()):
            tok = tok.strip('`')
            if not tok or not tok.endswith(CODE_EXT):
                continue
            if not (proj / tok).exists() and not list(proj.rglob(pathlib.Path(tok).name)):
                dead_refs.append(f'@ {tok} ({rf})')
if dead_refs:
    emit('deadrefs', 'WARN', 'CLAUDE',
         f'{len(dead_refs)} @-Referenz(en) auf fehlenden Code', dead_refs)
else:
    emit('deadrefs', 'PASS', 'NONE', 'alle @-Referenzen existieren')

# ====================== Check 5: Interaction-Map-Drift =====================
imap = ctx / '_interaction_map.md'
if imap.exists() and 'leer bis zum ersten Scan' not in \
        imap.read_text(encoding='utf-8', errors='ignore'):
    drift = []
    for line in imap.read_text(encoding='utf-8', errors='ignore').splitlines():
        if not line.startswith('|') or '---' in line:
            continue
        cells = [c.strip() for c in line.strip().strip('|').split('|')]
        if len(cells) != 5 or cells[0] == 'Element':
            continue
        loc = cells[1].strip('`').split(':')[0]
        if loc and not (proj / loc).exists():
            drift.append(loc)
    drift = sorted(set(drift))
    if drift:
        emit('mapdrift', 'WARN', 'MECH',
             f'{len(drift)} Map-Eintrag/-Eintraege auf geloeschten Dateien', drift)
    else:
        emit('mapdrift', 'PASS', 'MECH', 'Interaction Map aktuell')

# ====================== Check 6: Index ↔ Datei ============================
idx_files = [ctx / '_ai_index.md'] + sorted((ctx / '_idx').glob('*.md')) \
    if (ctx / '_idx').exists() else [ctx / '_ai_index.md']
missing_idx = []
backtick_re = re.compile(r'`([^`]+\.md)`')
for idx in idx_files:
    if not idx.exists():
        continue
    for m in backtick_re.finditer(idx.read_text(encoding='utf-8', errors='ignore')):
        ref = m.group(1)
        if not (ctx / ref).exists():
            missing_idx.append(f'{ref} (gelistet in {idx.name})')
missing_idx = sorted(set(missing_idx))
if missing_idx:
    emit('index', 'WARN', 'CLAUDE',
         f'{len(missing_idx)} Index-Eintrag/-Eintraege ohne Datei', missing_idx)
else:
    emit('index', 'PASS', 'NONE', 'Index ↔ Dateien konsistent')

# ====================== Check 7: übergroße Dateien =========================
oversized = []
for p in context_md_files():
    t = est_tokens(p.read_text(encoding='utf-8', errors='ignore'))
    if t > 600:
        oversized.append(f'{rel(p)} (~{t} Tokens)')
if oversized:
    emit('oversize', 'WARN', 'CLAUDE',
         f'{len(oversized)} Datei(en) > 600 Tokens (Split-Regel)', oversized)
else:
    emit('oversize', 'PASS', 'NONE', 'alle Dateien im Token-Rahmen')

# ============= Check 8b: Session-Datum veraltet ============================
# Liest "Session: YYYY-MM-DD" aus _ai_index.md und warnt wenn > 14 Tage alt.
import datetime
idx_path = ctx / '_ai_index.md'
if idx_path.exists():
    m = re.search(r'Session:\s*(\d{4}-\d{2}-\d{2})', idx_path.read_text(encoding='utf-8', errors='ignore'))
    if m:
        try:
            session_date = datetime.date.fromisoformat(m.group(1))
            age = (datetime.date.today() - session_date).days
            if age > 14:
                emit('stalesession', 'WARN', 'MECH',
                     f'Session-Kontext {age} Tage alt (letzte Session: {m.group(1)}) — ai-session-prep.sh ausführen')
            else:
                emit('stalesession', 'PASS', 'NONE', f'Session-Kontext aktuell ({age} Tage)')
        except ValueError:
            pass

# ============= Check 9: Symbol-Drift (semantische Verjaehrung) =============
# Fuer jeden Gotcha/Pattern mit @-Datei-Referenz: pruefen ob im Body genannte
# Identifier (camelCase/snake_case-Tokens) noch via `git grep -w` im Projekt
# zu finden sind. Hit-Rate < 50% (mind. 2 Symbole erforderlich) → WARN.
SYM_STOP = {
    'true','false','null','none','this','self','that','then','else','async',
    'await','return','const','class','function','import','export','default',
    'public','private','protected','static','void','undefined','typeof',
    'string','number','boolean','object','array','promise','response','request',
    'props','state','error','params','config','options','client','server',
    'gotcha','pattern','rule','file','line','code','test','spec',
    'beschreibung','symptom','dateien','prio','status',
}
def _extract_identifiers(text):
    out = set()
    # camelCase / PascalCase: must contain at least one inner uppercase
    for m in re.finditer(r'\b[A-Za-z][A-Za-z0-9]{3,}\b', text):
        tok = m.group(0)
        if tok.lower() in SYM_STOP:
            continue
        has_inner_upper = any(c.isupper() for c in tok[1:])
        if not has_inner_upper:
            continue
        out.add(tok)
    # snake_case: must contain at least one underscore between letters
    for m in re.finditer(r'\b[a-z][a-z0-9_]*_[a-z0-9_]+\b', text):
        tok = m.group(0)
        if tok.lower() in SYM_STOP:
            continue
        out.add(tok)
    return out

_grep_available = None
def _has_symbol(sym):
    global _grep_available
    if _grep_available is False:
        return None
    try:
        if _grep_available is None:
            t = subprocess.run(['git', 'rev-parse', '--is-inside-work-tree'],
                               cwd=str(proj), capture_output=True, timeout=3)
            _grep_available = t.returncode == 0
            if not _grep_available:
                return None
        r = subprocess.run(['git', 'grep', '-q', '-w', '--', sym],
                           cwd=str(proj), capture_output=True, timeout=5)
        return r.returncode == 0
    except Exception:
        return None

drift_entries = []
checked_total = 0
for rf in ('_gotchas.md', 'debug_patterns.md', 'security.md'):
    fp = ctx / rf
    if not fp.exists():
        continue
    text = fp.read_text(encoding='utf-8', errors='ignore')
    for m in re.finditer(r'```\s*\n((?:ID:|RULE:)[\s\S]*?)```', text):
        body = m.group(1)
        idm = re.search(r'(?:ID:|RULE:)\s*(\S+)', body)
        if not idm:
            continue
        cid = idm.group(1)
        # nur Eintraege mit @-Datei-Referenz checken
        if not re.search(r'\n@\s*\S+', body):
            continue
        idents = list(_extract_identifiers(body))[:6]
        if len(idents) < 2:
            continue
        found_ct = 0
        usable = 0
        for s in idents:
            res = _has_symbol(s)
            if res is None:
                continue  # git nicht verfuegbar — Symbol ueberspringen
            usable += 1
            if res:
                found_ct += 1
        if usable < 2:
            continue
        checked_total += 1
        if found_ct / usable < 0.5:
            drift_entries.append(
                f'{cid} ({rf}) — {found_ct}/{usable} Symbol(e) im Code')

if drift_entries:
    emit('symboldrift', 'WARN', 'CLAUDE',
         f'{len(drift_entries)} Eintrag/Eintraege mit verjaehrten Symbolen',
         drift_entries)
elif checked_total > 0:
    emit('symboldrift', 'PASS', 'NONE',
         f'alle @-referenzierten Symbole aktiv ({checked_total} geprueft)')
# wenn checked_total == 0 (kein git oder keine Eintraege mit @): kein Check-Ergebnis

# ---- Ausgabe (maschinenlesbar) ----
for cid, status, fixkind, msg, details in results:
    print(f'CHECK|{cid}|{status}|{fixkind}|{msg}')
    for d in details:
        print(f'DETAIL|{cid}|{d}')
PYEOF

# macOS/Linux-portabler Datei-Hash (md5sum | md5).
portable_hash() {
  md5sum "$1" 2>/dev/null | cut -d' ' -f1 \
    || md5 -q "$1" 2>/dev/null \
    || echo "n/a"
}

# ---- Checks ausführen → REPORT ----
run_checks() {
  : > "$REPORT"
  python3 "$CHECKER" "$CONTEXT_DIR" "$PROJECT_DIR" "$SCRIPT_DIR/lib" >> "$REPORT" 2>/dev/null
  # Check 8: Regel-Konflikte — bestehendes Tool wiederverwenden
  local hash_tool="$CONTEXT_DIR/check_context_hash.sh"
  if [ -f "$hash_tool" ]; then
    local cout
    cout="$(cd "$PROJECT_DIR" && bash "$hash_tool" --conflicts 2>/dev/null || true)"
    if echo "$cout" | grep -q 'Keine Konflikte'; then
      echo "CHECK|conflicts|PASS|NONE|keine Regel-Konflikte" >> "$REPORT"
    elif echo "$cout" | grep -q 'Konflikte erkannt'; then
      local n
      n="$(echo "$cout" | grep -oE '[0-9]+ potentielle' | grep -oE '[0-9]+' | head -1)"
      echo "CHECK|conflicts|WARN|CLAUDE|${n:-?} potentielle Regel-Konflikte" >> "$REPORT"
      echo "$cout" | grep -E '↔|→' | sed 's/^/DETAIL|conflicts|/' >> "$REPORT"
    fi
  fi

  # Check 9 (W7): Script-Drift — Projekt-Kopie ↔ globales Template.
  # Warnt, wenn die zwei Script-Kopien auseinanderlaufen (Template aktualisiert,
  # Projekt nicht — oder umgekehrt). Übersprungen, wenn kein globales Template da.
  local tmpl_scripts="$HOME/.ai-context/_ai_context_template/scripts"
  if [ -d "$tmpl_scripts" ] && [ -d "$SCRIPT_DIR" ]; then
    local drifted=()
    local f base tmpl
    for f in "$SCRIPT_DIR"/*.sh; do
      [ -f "$f" ] || continue
      base="$(basename "$f")"
      tmpl="$tmpl_scripts/$base"
      [ -f "$tmpl" ] || continue   # nur gemeinsame Scripts vergleichen
      if [ "$(portable_hash "$f")" != "$(portable_hash "$tmpl")" ]; then
        drifted+=("$base")
      fi
    done
    if [ ${#drifted[@]} -gt 0 ]; then
      echo "CHECK|scriptdrift|WARN|CLAUDE|${#drifted[@]} Script(s) weichen vom globalen Template ab" >> "$REPORT"
      local d
      for d in "${drifted[@]}"; do
        echo "DETAIL|scriptdrift|$d — sync via: cp ~/.ai-context/_ai_context_template/scripts/$d $SCRIPT_DIR/$d" >> "$REPORT"
      done
    else
      echo "CHECK|scriptdrift|PASS|NONE|Scripts ↔ Template synchron" >> "$REPORT"
    fi
  fi
}

# ---- mechanische Fixes ----
apply_mechanical_fixes() {
  local fixed=0
  local reg="$SCRIPT_DIR/ai-context-registry.sh"
  local map="$SCRIPT_DIR/ai-context-map.sh"
  if grep -q '^CHECK|anchors|WARN' "$REPORT" && [ -f "$reg" ]; then
    bash "$reg" --add-anchors > /dev/null 2>&1
    bash "$reg" --scan > /dev/null 2>&1
    fixed=$((fixed + 1))
  fi
  if grep -q '^CHECK|mapdrift|WARN' "$REPORT" && [ -f "$map" ]; then
    bash "$map" > /dev/null 2>&1
    fixed=$((fixed + 1))
  fi
  local prep="$SCRIPT_DIR/ai-session-prep.sh"
  if grep -q '^CHECK|stalesession|WARN' "$REPORT" && [ -f "$prep" ]; then
    bash "$prep" > /dev/null 2>&1
    fixed=$((fixed + 1))
  fi
  echo "$fixed"
}

# ---- Zähler (reines awk — kein grep mit '|' im Muster) ----
count_status() {
  awk -F'|' -v st="$1" '$1=="CHECK" && $3==st {n++} END{print n+0}' "$REPORT"
}
count_fixkind_warn() {
  awk -F'|' -v fk="$1" \
    '$1=="CHECK" && $3=="WARN" && $4==fk {n++} END{print n+0}' "$REPORT"
}

# ---- Report formatieren ----
print_report() {
  echo -e "${CYAN}🩺 ai-context-doctor — $PROJECT_NAME${NC}"
  echo ""
  while IFS='|' read -r tag cid status fixkind msg; do
    [ "$tag" = "CHECK" ] || continue
    case "$status" in
      PASS) echo -e "  ${GREEN}[PASS]${NC} ${cid} — ${msg}" ;;
      WARN) echo -e "  ${YELLOW}[WARN]${NC} ${cid} — ${msg}" ;;
      FAIL) echo -e "  ${RED}[FAIL]${NC} ${cid} — ${msg}" ;;
    esac
    if [ "$status" != "PASS" ]; then
      grep "^DETAIL|${cid}|" "$REPORT" | sed 's/^DETAIL|[^|]*|/         /' \
        | head -6
    fi
  done < "$REPORT"
}

# ===========================================================================
case "$MODE" in

  check)
    run_checks
    print_report
    MECH="$(count_fixkind_warn MECH)"
    CLAUDE="$(count_fixkind_warn CLAUDE)"
    PASS="$(count_status PASS)"
    echo ""
    echo -e "  ${CYAN}─────${NC}"
    echo -e "  Mechanisch fixbar: $MECH  |  Für Claude: $CLAUDE  |  Gesund: $PASS"
    [ "$MECH" -gt 0 ] && echo -e "  ${CYAN}→ Reparieren:${NC} bash _ai_context/scripts/ai-context-doctor.sh --fix"
    [ $((MECH + CLAUDE)) -gt 0 ] && exit 1 || exit 0
    ;;

  fix)
    run_checks
    FIXED="$(apply_mechanical_fixes)"
    if [ "$FIXED" -gt 0 ]; then
      echo -e "${GREEN}🔧 $FIXED mechanische Reparatur(en) durchgeführt.${NC}"
      run_checks   # erneut prüfen
    else
      echo -e "${CYAN}Keine mechanischen Defekte.${NC}"
    fi
    echo ""
    print_report
    CLAUDE="$(count_fixkind_warn CLAUDE)"
    if [ "$CLAUDE" -gt 0 ]; then
      echo ""
      echo -e "  ${YELLOW}FLAGGED-FOR-CLAUDE: $CLAUDE Punkt(e) brauchen semantische Korrektur.${NC}"
      echo -e "  ${CYAN}→ /ai-doctor löst sie auf.${NC}"
      exit 1
    fi
    echo ""
    echo -e "  ${GREEN}✅ System gesund.${NC}"
    exit 0
    ;;

  session)
    run_checks
    MECH_BEFORE="$(count_fixkind_warn MECH)"
    FIXED="$(apply_mechanical_fixes)"
    [ "$FIXED" -gt 0 ] && run_checks
    CLAUDE="$(count_fixkind_warn CLAUDE)"
    if [ "$MECH_BEFORE" -gt 0 ] && [ "$CLAUDE" -gt 0 ]; then
      echo -e "${CYAN}🩺 Doctor:${NC} $MECH_BEFORE auto-fix, $CLAUDE offen — ${CYAN}/ai-doctor${NC}"
    elif [ "$MECH_BEFORE" -gt 0 ]; then
      echo -e "${CYAN}🩺 Doctor:${NC} $MECH_BEFORE mechanisch repariert, sonst gesund"
    elif [ "$CLAUDE" -gt 0 ]; then
      echo -e "${CYAN}🩺 Doctor:${NC} $CLAUDE Punkt(e) offen — ${CYAN}/ai-doctor${NC}"
    else
      echo -e "${CYAN}🩺 Doctor:${NC} ${GREEN}alles gesund${NC}"
    fi
    exit 0
    ;;
esac
