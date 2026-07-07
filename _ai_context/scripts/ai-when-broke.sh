#!/usr/bin/env bash
# =============================================================================
# ai-when-broke.sh — Regressions-Zeitfenster aus Verify-Log ableiten
#
# Findet das Zeitfenster zwischen letztem PASS und erstem FAIL danach.
# Gibt geänderte Dateien + den wahrscheinlichsten Verdächtigen aus.
#
# Usage:
#   bash ai-when-broke.sh [dateiname-oder-stichwort]
#
# Exit 0: Fenster gefunden, Output auf stdout
# Exit 1: kein Fenster (stumm — kein stderr)
#
# Edition: Free — kein Pro-Guard
# =============================================================================
set -euo pipefail

PROJECT_NAME="$(basename "$PWD")"
VERIFY_LOG="$HOME/.ai-context/projects/$PROJECT_NAME/.verify-log.jsonl"

[ -f "$VERIFY_LOG" ] || exit 1
[ -s "$VERIFY_LOG" ] || exit 1

WHEN_PY="$(mktemp -t aictx-whenbroke.XXXXXX.py)"
trap 'rm -f "$WHEN_PY"' EXIT

cat > "$WHEN_PY" << 'PYEOF'
import sys, json, subprocess

log_file = sys.argv[1]
keyword  = sys.argv[2] if len(sys.argv) > 2 else ''

entries = []
with open(log_file, 'r', encoding='utf-8') as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            e = json.loads(line)
            if 'ts' in e and 'result' in e:
                entries.append(e)
        except Exception:
            pass

if not entries:
    sys.exit(1)

# Optional: keyword-Filter auf .file-Feld
if keyword:
    filtered = [e for e in entries if keyword.lower() in e.get('file', '').lower()]
    if filtered:
        entries = filtered

# Chronologisch sortieren
entries.sort(key=lambda e: e.get('ts', ''))

# Letztes PASS finden, dann erstes FAIL danach
last_pass = None
first_fail = None
for e in entries:
    if e['result'] == 'PASS':
        last_pass = e
        first_fail = None  # Neues PASS: Fenster-Suche neu starten
    elif e['result'] == 'FAIL' and last_pass is not None and first_fail is None:
        first_fail = e

if not last_pass or not first_fail:
    sys.exit(1)

pass_git  = last_pass.get('git', '')
fail_git  = first_fail.get('git', '')
pass_date = last_pass['ts'][:10]
fail_date = first_fail['ts'][:10]

print(f'BROKE_WINDOW: {pass_date} → {fail_date}')

if not pass_git or not fail_git or pass_git == fail_git:
    print('CHANGED_FILES: (git-Hashes fehlen oder identisch)')
    print('SUSPECT: (kein git-Diff möglich)')
    sys.exit(0)

# git diff --name-only
try:
    diff = subprocess.run(
        ['git', 'diff', '--name-only', pass_git, fail_git],
        capture_output=True, text=True, timeout=10
    )
    changed = [f.strip() for f in diff.stdout.splitlines() if f.strip()]
except Exception:
    changed = []

if not changed:
    print('CHANGED_FILES: (keine git-Diffs ermittelbar)')
    print('SUSPECT: (kein git-Diff möglich)')
    sys.exit(0)

print(f'CHANGED_FILES: {", ".join(changed)}')

# Suspect: Datei mit meisten Commit-Auftritten im Fenster
try:
    log = subprocess.run(
        ['git', 'log', '--name-only', '--pretty=format:', f'{pass_git}..{fail_git}'],
        capture_output=True, text=True, timeout=10
    )
    counts: dict[str, int] = {}
    for line in log.stdout.splitlines():
        line = line.strip()
        if line and '.' in line:
            counts[line] = counts.get(line, 0) + 1
    if counts:
        suspect = max(counts, key=lambda k: counts[k])
        n = counts[suspect]
        plural = 'en' if n != 1 else ''
        print(f'SUSPECT: {suspect} ({n} Änderung{plural} in Fenster)')
    else:
        print(f'SUSPECT: {changed[0]} (aus git diff)')
except Exception:
    print(f'SUSPECT: {changed[0]} (aus git diff)')
PYEOF

python3 "$WHEN_PY" "$VERIFY_LOG" "${1:-}"
