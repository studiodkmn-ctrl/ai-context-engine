#!/usr/bin/env bash
# =============================================================================
# ai-context-doctor.sh — Selbst-Reparatur des Kontext-Systems (v6.5 — Phase 4, v7: Freshness + localtemplatedrift)
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
#   bash ai-context-doctor.sh --ack <id> # Warnung dauerhaft akzeptieren
#   bash ai-context-doctor.sh --unack <id>
#
# v8: mechanische Fixes sind Standard (kein Pro-Gate mehr) — sie sind rein
# strukturell (Anker, Map, Session-Refresh, Orphan-Archivierung) und
# schreiben nie Fließtext-Inhalt. Jede Auto-Reparatur hinterlässt eine
# Log-Zeile in _temp_notes.md (Recent Changes). Inhaltliche Korrekturen
# (fixkind CLAUDE) bleiben wie bisher /ai-doctor vorbehalten.
#
# Env: AI_CTX_ORPHAN_DAYS — Frist, nach der Orphan-Chunks archiviert
#      werden (Default 30 Tage seit `seen`).
# =============================================================================
set -uo pipefail

CONTEXT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_DIR="$(cd "$CONTEXT_DIR/.." && pwd)"
PROJECT_NAME="$(basename "$PROJECT_DIR")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ORPHAN_DAYS="${AI_CTX_ORPHAN_DAYS:-30}"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; RED='\033[0;31m'; NC='\033[0m'

MODE="check"
ACK_TARGET=""
case "${1:-}" in
  --fix)     MODE="fix" ;;
  --session) MODE="session" ;;
  --check|"") MODE="check" ;;
  --ack)     MODE="ack";   ACK_TARGET="${2:-}" ;;
  --unack)   MODE="unack"; ACK_TARGET="${2:-}" ;;
  *) echo "Usage: ai-context-doctor.sh [--check|--fix|--session|--ack <id>|--unack <id>]" >&2; exit 2 ;;
esac

# ---- Bestätigte Warnungen (V10 R1b) ----------------------------------------
# Manche Warnungen sind dauerhaft und bewusst so: ein Projekt, das die
# Demo-Regeln legitim übernommen hat (demo_content), eine auto-generierte
# Datei, die immer groß ist (oversize/_idx). Ohne Quittier-Möglichkeit
# meldet der SessionStart-Hook sie in JEDER Session — und eine Warnung, die
# immer da ist, liest bald niemand mehr. Bestätigte Checks bleiben im
# vollen --check-Report sichtbar (als "bestätigt" markiert), zählen aber
# nicht mehr als offener Punkt und schweigen in --session.
ACK_FILE="$CONTEXT_DIR/.doctor-ack"

is_acked() {  # is_acked <check-id>
  [ -f "$ACK_FILE" ] || return 1
  grep -qE "^[[:space:]]*$1[[:space:]]*(#.*)?$" "$ACK_FILE" 2>/dev/null
}

CHECKER="$(mktemp -t aictx-doctor.XXXXXX.py)"
REPORT="$(mktemp -t aictx-doctor.XXXXXX.txt)"
trap 'rm -f "$CHECKER" "$REPORT"' EXIT

cat > "$CHECKER" << 'PYEOF'
import sys, re, pathlib, subprocess

ctx = pathlib.Path(sys.argv[1])
proj = pathlib.Path(sys.argv[2])

sys.path.insert(0, sys.argv[3])
import ctx as ctxlib  # scripts/lib/ctx.py — shared token/registry/freshness helpers (v7)

# v9-a: einzige Quelle der Wahrheit ist knowledge.manifest.yaml (siehe
# decisions.md#knowledge_manifest). Fallback auf die alte Liste, falls das
# Manifest fehlt (sehr alte/fremde Installation).
_manifest_entries = ctxlib.load_knowledge_manifest(str(ctx / "knowledge.manifest.yaml"))
if _manifest_entries:
    KNOWLEDGE = [e["path"] for e in _manifest_entries]
    _marker_union = sorted({m for e in _manifest_entries for m in e["markers"]}) or ['ID', 'RULE', 'PLAYBOOK']
else:
    KNOWLEDGE = ['_gotchas.md', 'debug_patterns.md', 'security.md', 'testing.md',
                 'backend/auth.md', 'backend/database.md', 'backend/endpoints.md',
                 'frontend/components.md', 'frontend/state.md', 'frontend/routing.md',
                 'playbooks.md']
    _marker_union = ['ID', 'RULE', 'PLAYBOOK']

results = []  # (check_id, status, fixkind, message, [details])

def emit(cid, status, fixkind, msg, details=None):
    results.append((cid, status, fixkind, msg, details or []))

def context_md_files():
    for p in sorted(ctx.rglob('*.md')):
        if p.name == '_SESSION.md':
            continue
        # _cache/ und .session/ sind transienter Laufzeit-Zustand (Read-Guard-
        # Ledger, reflect-inbox), kein gepflegtes Wissen — sie hier mitzupruefen
        # meldet z.B. eine wachsende reflect-inbox als "zu grosse Wissensdatei".
        if '_cache' in p.parts or '.session' in p.parts:
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
block_re = re.compile(r'```[ \t]*\n(?:' + '|'.join(_marker_union) + r'):\s*(\S+)', re.MULTILINE)
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
# FIX (v8.0.2): *_archive.md (und *_extended.md) existieren genau dafuer,
# Overflow aufzunehmen, das ist ihr Zweck (siehe ai-context-drawer.sh) -- sie
# hier trotzdem als "zu gross" zu flaggen, macht die Split-Regel gegen sich
# selbst arbeiten: jede wachsende Archiv-Datei waere dauerhaft rot. Andere
# Checks (Anker/Pointer/Deadrefs) laufen weiterhin ueber sie.
oversized = []
for p in context_md_files():
    if p.name.endswith('_archive.md'):
        continue
    t = est_tokens(p.read_text(encoding='utf-8', errors='ignore'))
    if t > 600:
        oversized.append(f'{rel(p)} (~{t} Tokens)')
if oversized:
    emit('oversize', 'WARN', 'CLAUDE',
         f'{len(oversized)} Datei(en) > 600 Tokens (Split-Regel)', oversized)
else:
    emit('oversize', 'PASS', 'NONE', 'alle Dateien im Token-Rahmen')

# ====================== Check 7b: Freshness (v7) ============================
# Liest registry.yaml (seen/code_touched/status, siehe ai-context-registry.sh
# --scan) und meldet orphans (naechster --scan raeumt automatisch mechanisch
# nicht auf, das ist fuer Claude) + wie viele Chunks 'check' brauchen.
registry_path = ctx / 'registry.yaml'
if registry_path.exists():
    reg_chunks = ctxlib.parse_registry(str(registry_path))['chunks']
    fresh_n = sum(1 for c in reg_chunks if c.get('status') == 'fresh')
    check_n = sum(1 for c in reg_chunks if c.get('status') == 'check')
    orphan_n = sum(1 for c in reg_chunks if c.get('status') == 'orphan')
    orphan_ids = [c['id'] for c in reg_chunks if c.get('status') == 'orphan']
    if orphan_n > 0:
        emit('freshness', 'WARN', 'CLAUDE',
             f'{orphan_n} verwaiste(r) Chunk(s) (Code-Datei fehlt) — {fresh_n} fresh, {check_n} check',
             orphan_ids)
    elif check_n > 0:
        emit('freshness', 'WARN', 'CLAUDE',
             f'{check_n} Chunk(s) moeglw. veraltet (Code neuer als seen) — {fresh_n} fresh',
             [c['id'] for c in reg_chunks if c.get('status') == 'check'])
    else:
        emit('freshness', 'PASS', 'NONE', f'alle {fresh_n} Chunks fresh')
else:
    emit('freshness', 'PASS', 'NONE', 'registry.yaml nicht vorhanden — --scan ausfuehren')

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

  # Check 10 (v7): lokaler Template-Drift — NUR relevant für dieses
  # Repo selbst (ai-context-engine), wo _ai_context_template/ neben
  # _ai_context/ liegt. Andere Prüfrichtung als scriptdrift oben (das
  # vergleicht gegen das GLOBALE ~/.ai-context/_ai_context_template,
  # hier geht es um Drift zwischen den zwei Kopien IM SELBEN Repo).
  local local_tmpl_scripts="$PROJECT_DIR/_ai_context_template/scripts"
  if [ -d "$local_tmpl_scripts" ] && [ -d "$SCRIPT_DIR" ] && [ "$local_tmpl_scripts" != "$SCRIPT_DIR" ]; then
    local ldrifted=()
    local lf lbase ltmpl
    for lf in "$SCRIPT_DIR"/*.sh; do
      [ -f "$lf" ] || continue
      lbase="$(basename "$lf")"
      ltmpl="$local_tmpl_scripts/$lbase"
      [ -f "$ltmpl" ] || continue
      if [ "$(portable_hash "$lf")" != "$(portable_hash "$ltmpl")" ]; then
        ldrifted+=("$lbase")
      fi
    done
    if [ ${#ldrifted[@]} -gt 0 ]; then
      echo "CHECK|localtemplatedrift|WARN|CLAUDE|${#ldrifted[@]} Script(s) weichen vom repo-lokalen _ai_context_template ab" >> "$REPORT"
      local ld
      for ld in "${ldrifted[@]}"; do
        echo "DETAIL|localtemplatedrift|$ld — sync via: cp $local_tmpl_scripts/$ld $SCRIPT_DIR/$ld" >> "$REPORT"
      done
    else
      echo "CHECK|localtemplatedrift|PASS|NONE|_ai_context/scripts ↔ _ai_context_template/scripts synchron" >> "$REPORT"
    fi
  fi

  # Check 11 (V10 R1): Demo-Inhalte nie ersetzt + falsche Projekt-Identität.
  # setup_ai_context.sh liefert Demo-Chunks (prisma_singleton, auth_first, ...)
  # als Startpunkt aus — bleiben sie unverändert, matcht locate() gegen ein
  # fiktives Next.js-Projekt statt gegen das echte. Genau das war im
  # Engine-Repo selbst monatelang der Fall (7 von 10 Chunks Demo-Reste, siehe
  # decisions.md#demo_content). NUR warnen, nie löschen: in echten
  # Next.js-Projekten können die Demo-Regeln zufällig zutreffen.
  local tmpl_root=""
  if [ -d "$HOME/.ai-context/_ai_context_template" ]; then
    tmpl_root="$HOME/.ai-context/_ai_context_template"
  elif [ -d "$PROJECT_DIR/_ai_context_template" ]; then
    tmpl_root="$PROJECT_DIR/_ai_context_template"
  fi

  if [ -n "$tmpl_root" ] && [ -f "$SCRIPT_DIR/lib/ctx.py" ]; then
    local demo_findings=()

    # -- Teil 1: Chunks, die Zeichen für Zeichen dem Template entsprechen --
    local manifest="$CONTEXT_DIR/knowledge.manifest.yaml"
    local kfiles=()
    if [ -f "$manifest" ]; then
      while IFS= read -r kf; do
        [ -n "$kf" ] && kfiles+=("$kf")
      done < <(python3 "$SCRIPT_DIR/lib/ctx.py" list_knowledge_files "$manifest" 2>/dev/null)
    fi

    local kf proj_file tmpl_file
    for kf in "${kfiles[@]}"; do
      proj_file="$CONTEXT_DIR/$kf"
      tmpl_file="$tmpl_root/$kf"
      [ -f "$proj_file" ] && [ -f "$tmpl_file" ] || continue
      while IFS= read -r dup_id; do
        [ -n "$dup_id" ] && demo_findings+=("$dup_id ($kf) — unverändert aus Template")
      done < <(python3 - "$proj_file" "$tmpl_file" "$SCRIPT_DIR/lib" << 'PYEOF' 2>/dev/null
import sys, pathlib
sys.path.insert(0, sys.argv[3])
import ctx as ctxlib

proj = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8", errors="ignore")
tmpl = pathlib.Path(sys.argv[2]).read_text(encoding="utf-8", errors="ignore")

def chunks(text):
    out = {}
    for m in ctxlib.ANCHOR_RE.finditer(text):
        cid = m.group(1)
        if cid.startswith("_") or cid.lower() == "template":
            continue
        out[cid] = " ".join(m.group(2).split())
    return out

p, t = chunks(proj), chunks(tmpl)
for cid, body in p.items():
    if cid in t and t[cid] == body:
        print(cid)
PYEOF
      )
    done

    # -- Teil 1b: Dateien, die nur aus Vorlagen-Hinweisen bestehen --
    # Ganze Domain-Dateien (backend/auth.md, frontend/routing.md, ...) haben
    # keine Anker und entgehen daher Teil 1. Sie sind aber genauso Fiktion,
    # wenn sie nie befuellt wurden — erkennbar an gehaeuften "[z.B. ...]"/
    # "[Bitte ...]"-Hinweisen (Check 3 ignoriert die bewusst einzeln, ab 3
    # Stueck in einer Datei ist es aber ein klares "nie angefasst"-Signal).
    while IFS= read -r hint_line; do
      [ -n "$hint_line" ] && demo_findings+=("$hint_line")
    done < <(python3 - "$CONTEXT_DIR" << 'PYEOF' 2>/dev/null
import sys, re, pathlib

ctx = pathlib.Path(sys.argv[1])
HINT = re.compile(r'\[(?:z\.B\.|e\.g\.|Bitte |Kurzbeschreibung|was falsch|betroffene )')
# Vorlagen-BLOECKE (ID: _template ...) sind legitime Muster-Beispiele und
# duerfen nicht als "nie befuellt" zaehlen — sonst meldet jede korrekt
# gepflegte Wissensdatei einen Fehlalarm.
TEMPLATE_BLOCK = re.compile(r'```\s*\n(?:ID|RULE|PLAYBOOK):\s*_[\s\S]*?```')

for p in sorted(ctx.rglob("*.md")):
    parts = set(p.parts)
    if "_cache" in parts or p.name == "_SESSION.md":
        continue
    try:
        text = p.read_text(encoding="utf-8", errors="ignore")
    except Exception:
        continue
    n = len(HINT.findall(TEMPLATE_BLOCK.sub("", text)))
    if n >= 3:
        print(f"{p.relative_to(ctx)} — {n} Vorlagen-Hinweise, nie befüllt")
PYEOF
    )

    # -- Teil 2: Projekt-Identität in _quick_facts.md --
    local quick="$CONTEXT_DIR/_quick_facts.md"
    if [ -f "$quick" ]; then
      local declared actual norm_declared norm_actual
      declared="$(grep -m1 '^Project:' "$quick" 2>/dev/null | sed 's/^Project:[[:space:]]*//' | tr -d '\r')"
      actual="$(basename "$PROJECT_DIR")"
      norm_declared="$(printf '%s' "$declared" | tr '[:upper:]' '[:lower:]' | tr '_' '-')"
      norm_actual="$(printf '%s' "$actual" | tr '[:upper:]' '[:lower:]' | tr '_' '-')"
      if [ -n "$norm_declared" ] && [ "$norm_declared" != "$norm_actual" ]; then
        demo_findings+=("_quick_facts.md — Project: '$declared' ≠ Verzeichnis '$actual'")
      fi
    fi

    if [ ${#demo_findings[@]} -gt 0 ]; then
      echo "CHECK|demo_content|WARN|CLAUDE|${#demo_findings[@]} Demo-/Identitäts-Rest(e) — Kontext beschreibt fremdes Projekt" >> "$REPORT"
      local df
      for df in "${demo_findings[@]}"; do
        echo "DETAIL|demo_content|$df" >> "$REPORT"
      done
    else
      echo "CHECK|demo_content|PASS|NONE|Kontext ist projekteigen (keine Template-Reste)" >> "$REPORT"
    fi
  fi
}

# ---- Auto-Fix-Protokoll: eine Zeile in _temp_notes.md (Recent Changes) ----
# Format folgt der post-commit-Konvention "[YYYY-MM-DD] — text" (der Trim in
# hooks/post-commit matcht ^\[20\d\d- und behält die letzten 5 Zeilen).
# Schreibt NUR ins Log — stdout bleibt frei (apply_mechanical_fixes gibt
# den Zähler über stdout zurück).
log_auto_fix() {
  local msg="$1"
  python3 - "$CONTEXT_DIR/_temp_notes.md" "$(date +%Y-%m-%d)" "$msg" << 'PYEOF' > /dev/null 2>&1 || true
import sys, pathlib, re
p = pathlib.Path(sys.argv[1])
if not p.exists():
    sys.exit(0)
today, msg = sys.argv[2], sys.argv[3]
text = p.read_text(encoding='utf-8')
# Recent-Changes-Block finden: Heading, dann ```-Fence — neue Zeile ans
# Block-Ende (Trim behält die letzten 5 → unten = neueste).
m = re.search(r'(##[^\n]*Recent Changes[^\n]*\n+```[^\n]*\n)([\s\S]*?)(```)', text)
if not m:
    sys.exit(0)
line = f'[{today}] — {msg}\n'
body = m.group(2)
if line in body:
    sys.exit(0)
new = text[:m.start(2)] + body + line + text[m.end(2):]
p.write_text(new, encoding='utf-8')
PYEOF
}

# ---- Orphan-Archivierung: status=orphan + seen älter als $ORPHAN_DAYS ----
# Verschiebt den kompletten Block (inkl. Anker) in die Archivdatei des
# jeweiligen Wissensfiles (_gotchas.md → _gotchas_archive.md usw.) — NIE
# löschen, nur verschieben. Gibt die Anzahl archivierter Blöcke auf stdout.
archive_stale_orphans() {
  python3 - "$CONTEXT_DIR" "$SCRIPT_DIR/lib" "$ORPHAN_DAYS" << 'PYEOF' 2>/dev/null || echo 0
import sys, re, pathlib, datetime

ctx = pathlib.Path(sys.argv[1])
sys.path.insert(0, sys.argv[2])
import ctx as ctxlib
grace_days = int(sys.argv[3])

reg_path = ctx / 'registry.yaml'
if not reg_path.exists():
    print(0); sys.exit(0)

today = datetime.date.today()
stale = []
for c in ctxlib.parse_registry(str(reg_path))['chunks']:
    if c.get('status') != 'orphan' or not c.get('seen') or not c.get('file'):
        continue
    try:
        seen = datetime.date.fromisoformat(c['seen'])
    except ValueError:
        continue
    if (today - seen).days >= grace_days:
        stale.append(c)

archived = 0
for c in stale:
    src = ctx / c['file']
    if not src.exists():
        continue
    text = src.read_text(encoding='utf-8')
    cid = re.escape(c['id'])
    # Block = optionaler Anker davor + ```-Fence mit ID:/RULE: <id> + optionaler End-Anker
    pat = re.compile(
        r'(?:<!-- #' + cid + r' -->\s*\n)?'
        r'```[ \t]*\n(?:ID:|RULE:)\s*' + cid + r'\b[\s\S]*?```\s*\n'
        r'(?:<!-- /' + cid + r' -->\s*\n)?'
    )
    m = pat.search(text)
    if not m:
        continue
    block = m.group(0).rstrip() + '\n'
    stem = pathlib.Path(c['file']).name.removesuffix('.md').lstrip('_')
    dst = src.parent / f'_{stem}_archive.md'
    if dst.exists():
        arch = dst.read_text(encoding='utf-8')
    else:
        arch = (f'# 📦 {stem} Archiv — automatisch archivierte Einträge\n'
                f'> Orphan-Einträge (Code-Datei existiert nicht mehr, seen älter als {grace_days} Tage).\n'
                f'> Verschoben von ai-context-doctor.sh — Inhalt unverändert, nichts gelöscht.\n\n'
                f'## Archiviert\n')
    stamp = f'<!-- archiviert {today.isoformat()}: orphan seit >={grace_days}d -->\n'
    arch = arch.rstrip() + '\n\n' + stamp + block
    dst.write_text(arch, encoding='utf-8')
    src.write_text(text[:m.start()] + text[m.end():], encoding='utf-8')
    archived += 1

print(archived)
PYEOF
}

# ---- mechanische Fixes ----
apply_mechanical_fixes() {
  local fixed=0
  local reg="$SCRIPT_DIR/ai-context-registry.sh"
  local map="$SCRIPT_DIR/ai-context-map.sh"
  if grep -q '^CHECK|anchors|WARN' "$REPORT" && [ -f "$reg" ]; then
    bash "$reg" --add-anchors > /dev/null 2>&1
    bash "$reg" --scan > /dev/null 2>&1
    log_auto_fix "Auto-Fix: fehlende HTML-Anker injiziert (doctor)"
    fixed=$((fixed + 1))
  fi
  if grep -q '^CHECK|mapdrift|WARN' "$REPORT" && [ -f "$map" ]; then
    bash "$map" > /dev/null 2>&1
    log_auto_fix "Auto-Fix: Interaction Map regeneriert (doctor)"
    fixed=$((fixed + 1))
  fi
  local prep="$SCRIPT_DIR/ai-session-prep.sh"
  if grep -q '^CHECK|stalesession|WARN' "$REPORT" && [ -f "$prep" ]; then
    bash "$prep" > /dev/null 2>&1
    log_auto_fix "Auto-Fix: veraltete _SESSION.md regeneriert (doctor)"
    fixed=$((fixed + 1))
  fi
  # Orphan-Chunks (Code-Datei weg, seen > $ORPHAN_DAYS Tage) → Archiv.
  # Läuft nur, wenn der Freshness-Check Orphans gemeldet hat.
  if grep -q '^CHECK|freshness|WARN' "$REPORT"; then
    local archived
    archived="$(archive_stale_orphans)"
    case "$archived" in (*[!0-9]*|'') archived=0 ;; esac
    if [ "$archived" -gt 0 ]; then
      [ -f "$reg" ] && bash "$reg" --scan > /dev/null 2>&1
      log_auto_fix "Auto-Fix: $archived Orphan-Eintrag/-Einträge archiviert (>${ORPHAN_DAYS}d ohne Code-Datei)"
      fixed=$((fixed + 1))
    fi
  fi
  echo "$fixed"
}

# ---- Zähler (reines awk — kein grep mit '|' im Muster) ----
count_status() {
  awk -F'|' -v st="$1" '$1=="CHECK" && $3==st {n++} END{print n+0}' "$REPORT"
}
count_fixkind_warn() {
  # Bestätigte Checks (.doctor-ack) zählen nicht als offener Punkt —
  # sonst bleibt der SessionStart-Hinweis dauerhaft stehen.
  local total=0 cid
  while IFS='|' read -r tag cid status fixkind _rest; do
    [ "$tag" = "CHECK" ] && [ "$status" = "WARN" ] && [ "$fixkind" = "$1" ] || continue
    is_acked "$cid" && continue
    total=$((total + 1))
  done < "$REPORT"
  printf '%s' "$total"
}

# ---- Report formatieren ----
print_report() {
  echo -e "${CYAN}🩺 ai-context-doctor — $PROJECT_NAME${NC}"
  echo ""
  # shellcheck disable=SC2034  # fixkind = Platzhalter der IFS-Spaltung (Feld 4)
  while IFS='|' read -r tag cid status fixkind msg; do
    [ "$tag" = "CHECK" ] || continue
    if [ "$status" != "PASS" ] && is_acked "$cid"; then
      # Bestätigt: sichtbar, aber als erledigt markiert und ohne Details.
      echo -e "  ${CYAN}[ ok ]${NC} ${cid} — ${msg} ${CYAN}(bestätigt)${NC}"
      continue
    fi
    case "$status" in
      PASS) echo -e "  ${GREEN}[PASS]${NC} ${cid} — ${msg}" ;;
      WARN) echo -e "  ${YELLOW}[WARN]${NC} ${cid} — ${msg}" ;;
      FAIL) echo -e "  ${RED}[FAIL]${NC} ${cid} — ${msg}" ;;
    esac
    if [ "$status" != "PASS" ]; then
      grep "^DETAIL|${cid}|" "$REPORT" | sed 's/^DETAIL|[^|]*|/         /' \
        | head -6
      echo -e "         ${CYAN}dauerhaft so gewollt?${NC} bash _ai_context/scripts/ai-context-doctor.sh --ack ${cid}"
    fi
  done < "$REPORT"
}

# ===========================================================================
case "$MODE" in

  ack)
    if [ -z "$ACK_TARGET" ]; then
      echo "Usage: ai-context-doctor.sh --ack <check-id>" >&2; exit 2
    fi
    if is_acked "$ACK_TARGET"; then
      echo -e "${CYAN}'$ACK_TARGET' war bereits bestätigt.${NC}"
      exit 0
    fi
    if [ ! -f "$ACK_FILE" ]; then
      cat > "$ACK_FILE" << 'ACKEOF'
# .doctor-ack — bewusst akzeptierte Doctor-Warnungen
# Eine Check-ID pro Zeile. Bestätigte Checks bleiben im vollen Report
# sichtbar (als "bestätigt"), zählen aber nicht als offener Punkt und
# lösen keinen SessionStart-Hinweis mehr aus.
# Rückgängig: ai-context-doctor.sh --unack <check-id>
ACKEOF
    fi
    printf '%s   # bestätigt am %s\n' "$ACK_TARGET" "$(date +%Y-%m-%d)" >> "$ACK_FILE"
    echo -e "${GREEN}✅ '$ACK_TARGET' bestätigt${NC} — meldet sich nicht mehr pro Session."
    echo -e "   ${CYAN}Rückgängig:${NC} bash _ai_context/scripts/ai-context-doctor.sh --unack $ACK_TARGET"
    exit 0
    ;;

  unack)
    if [ -z "$ACK_TARGET" ]; then
      echo "Usage: ai-context-doctor.sh --unack <check-id>" >&2; exit 2
    fi
    if [ ! -f "$ACK_FILE" ] || ! is_acked "$ACK_TARGET"; then
      echo -e "${YELLOW}'$ACK_TARGET' war nicht bestätigt.${NC}"; exit 0
    fi
    grep -vE "^[[:space:]]*$ACK_TARGET[[:space:]]*(#.*)?$" "$ACK_FILE" > "${ACK_FILE}.tmp" \
      && mv "${ACK_FILE}.tmp" "$ACK_FILE"
    echo -e "${GREEN}✅ '$ACK_TARGET' wird wieder gemeldet.${NC}"
    exit 0
    ;;

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
    FIXED="$(apply_mechanical_fixes)"
    [ "$FIXED" -gt 0 ] && run_checks
    CLAUDE="$(count_fixkind_warn CLAUDE)"
    # FIXED statt "MECH vor dem Lauf" zählen: auch die Orphan-Archivierung
    # (hängt am CLAUDE-markierten freshness-Check) muss sichtbar sein —
    # keine stille Auto-Reparatur.
    if [ "$FIXED" -gt 0 ] && [ "$CLAUDE" -gt 0 ]; then
      echo -e "${CYAN}🩺 Doctor:${NC} $FIXED auto-fix, $CLAUDE offen — ${CYAN}/ai-doctor${NC}"
    elif [ "$FIXED" -gt 0 ]; then
      echo -e "${CYAN}🩺 Doctor:${NC} $FIXED mechanisch repariert, sonst gesund"
    elif [ "$CLAUDE" -gt 0 ]; then
      echo -e "${CYAN}🩺 Doctor:${NC} $CLAUDE Punkt(e) offen — ${CYAN}/ai-doctor${NC}"
    else
      echo -e "${CYAN}🩺 Doctor:${NC} ${GREEN}alles gesund${NC}"
    fi
    exit 0
    ;;
esac
