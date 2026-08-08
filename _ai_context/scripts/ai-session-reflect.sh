#!/usr/bin/env bash
# =============================================================================
# ai-session-reflect.sh — Stop/PreCompact-Hook: automatisches Lernen (v9-c)
#
# Liest das Session-Transcript (JSONL) und schlägt Playbook-/Debug-Pattern-
# Kandidaten in _ai_context/.session/reflect-inbox.md vor (NIE direkt in
# playbooks.md/debug_patterns.md — Mensch/Agent bleibt Kurator). Schreibt
# HANDOFF.md automatisch, wenn eine Aufgabe unfertig endet und niemand
# daran gedacht hat.
#
# WICHTIG: Stop feuert nach JEDEM Assistant-Turn, nicht nur am Session-Ende
# (verifiziert an einem echten Transcript dieser Session) — das Skript muss
# billig und idempotent sein: wiederholte Läufe duplizieren nichts (Content-
# Hash-Dedup) und überschreiben nie ein bereits gesetztes HANDOFF.
#
# Vertrag: stdin-JSON {session_id, transcript_path, hook_event_name, cwd}.
# Exit immer 0, kein Output nötig — die Wirkung ist rein dateibasiert für
# die naechste Session. Fail-open bei jedem Fehler.
# =============================================================================
set -uo pipefail

CONTEXT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

HOOK_INPUT="$(cat 2>/dev/null || echo '')"
[ -z "$HOOK_INPUT" ] && exit 0

REFLECT_PY="$(mktemp -t aictx-reflect.XXXXXX.py)"
trap 'rm -f "$REFLECT_PY"' EXIT

cat > "$REFLECT_PY" << 'PYEOF'
import json, sys, os, re, hashlib, pathlib, subprocess
from datetime import datetime, timezone

def main():
    context_dir = pathlib.Path(sys.argv[1])
    raw = os.environ.get("REFLECT_HOOK_INPUT", "")
    if not raw.strip():
        return
    try:
        hook = json.loads(raw)
    except Exception:
        return

    transcript_path = hook.get("transcript_path")
    cwd = hook.get("cwd") or str(context_dir.parent)
    session_id = hook.get("session_id") or "unknown"

    if not transcript_path or not pathlib.Path(transcript_path).exists():
        return

    user_prompts = []
    touched_files = []
    error_fingerprints = {}

    EDIT_TOOLS = {"Edit", "Write", "MultiEdit", "NotebookEdit"}

    try:
        with open(transcript_path, encoding="utf-8", errors="ignore") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    entry = json.loads(line)
                except Exception:
                    continue

                etype = entry.get("type")
                msg = entry.get("message") or {}
                content = msg.get("content")

                if etype == "user" and not entry.get("isMeta"):
                    if isinstance(content, str) and content and not content.startswith("<"):
                        user_prompts.append(content)
                    elif isinstance(content, list):
                        for block in content:
                            if not isinstance(block, dict):
                                continue
                            if block.get("type") == "tool_result" and block.get("is_error"):
                                c = block.get("content")
                                txt = c if isinstance(c, str) else json.dumps(c)
                                fp = txt[:80].strip()
                                if fp:
                                    error_fingerprints[fp] = error_fingerprints.get(fp, 0) + 1

                elif etype == "assistant" and isinstance(content, list):
                    for block in content:
                        if not isinstance(block, dict):
                            continue
                        if block.get("type") == "tool_use" and block.get("name") in EDIT_TOOLS:
                            fp = (block.get("input") or {}).get("file_path")
                            if fp and (not touched_files or touched_files[-1] != fp):
                                touched_files.append(fp)
    except Exception:
        return

    distinct_files = list(dict.fromkeys(touched_files))
    today = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    session_short = session_id[:8]

    candidates = []

    # ---- Playbook-Kandidat ----
    if len(distinct_files) >= 4 and user_prompts:
        trigger_words = " ".join(re.findall(r"[a-zA-ZäöüßÄÖÜ0-9]+", user_prompts[0])[:8]).lower()
        steps = "\n".join(f"  {i+1}. {fp}" for i, fp in enumerate(distinct_files[:8]))
        body = (
            f"PLAYBOOK: session_{session_short}\n"
            f"P: 3\n"
            f"trigger: {trigger_words}\n"
            f"steps:\n{steps}\n"
            f"learned_from: Session {today} (automatisch vorgeschlagen — bitte pruefen)"
        )
        candidates.append(("Playbook-Vorschlag", body))

    # ---- Debug-Pattern-Kandidat ----
    repeated = [(fp, n) for fp, n in error_fingerprints.items() if n >= 2]
    for fp, n in repeated[:2]:
        slug = re.sub(r"[^a-z0-9_]+", "_", fp.lower())[:30].strip("_") or "error"
        body = (
            f"ID: session_{session_short}_{slug}\n"
            f"P: 3\n"
            f"? {fp} ({n}x aufgetreten)\n"
            f"@ automatisch vorgeschlagen — Datei(en) bitte pruefen"
        )
        candidates.append(("Debug-Pattern-Vorschlag", body))

    if not candidates:
        return

    inbox_path = context_dir / ".session" / "reflect-inbox.md"
    inbox_path.parent.mkdir(parents=True, exist_ok=True)
    existing = inbox_path.read_text(encoding="utf-8") if inbox_path.exists() else (
        "# reflect-inbox.md — Vorschlaege aus Session-Reflexion (v9-c)\n"
        "> Automatisch vorgeschlagen, NIE automatisch uebernommen. Pruefen und\n"
        "> per Hand in playbooks.md / debug_patterns.md eintragen, dann diesen\n"
        "> Eintrag hier loeschen. Max 10 Eintraege (aelteste fliegen zuerst raus).\n\n"
    )

    appended = False
    for label, body in candidates:
        h = hashlib.md5(body.strip().encode()).hexdigest()[:12]
        marker = f"<!-- hash:{h} -->"
        if marker in existing:
            continue
        entry = f"## {label} — Session {session_short} ({today})\n{marker}\n```\n{body}\n```\n\n"
        existing += entry
        appended = True

    if appended:
        # Cap auf 10 Eintraege (aelteste zuerst raus)
        blocks = re.split(r"(?=^## )", existing, flags=re.MULTILINE)
        header = blocks[0]
        entries = [b for b in blocks[1:] if b.strip()]
        if len(entries) > 10:
            entries = entries[-10:]
        inbox_path.write_text(header + "".join(entries), encoding="utf-8")

    # ---- HANDOFF.md automatisch schreiben (nur wenn noetig + nie ueberschreiben) ----
    try:
        git_status = subprocess.run(
            ["git", "-C", cwd, "status", "--porcelain"],
            capture_output=True, text=True, timeout=5,
        ).stdout.strip()
    except Exception:
        git_status = ""

    if not git_status:
        return

    handoff_path = context_dir / "HANDOFF.md"
    current = handoff_path.read_text(encoding="utf-8") if handoff_path.exists() else ""
    status_m = re.search(r"\*\*Status:\*\*\s*(\S+)", current)
    current_status = status_m.group(1) if status_m else "_none_"
    if current_status not in ("_none_", "none", ""):
        return  # bereits bewusst gesetzt -> nie ueberschreiben

    last_prompt = (user_prompts[-1] if user_prompts else "").strip().replace("\n", " ")[:200]
    changed_lines = "\n".join(
        f"- {ln[3:].strip()} — Status: WIP" for ln in git_status.splitlines()[:15] if len(ln) > 3
    ) or "- (keine erkannt)"

    new_handoff = f"""# 🤝 HANDOFF.md — Session-Übergabe
> **Wann nutzen:** Aufgabe ist nicht fertig wenn Session endet.
> **Wann ignorieren:** Aufgabe abgeschlossen → Status: done oder leer.
> **Auto-Load:** Wird in `_SESSION.md` inline geladen wenn `Status: in_progress`.
> **Auto-Reaktion:** ai-session-prep.sh propagiert die ⚠️/🔍/🌐-Felder als Status in _ai_index.md.

---

**Status:** in_progress   <!-- automatisch gesetzt von ai-session-reflect.sh (v9-c) -->
**Datum:** {today}

## Was läuft
{last_prompt or "(kein Prompt erfasst)"}

## Nächster Schritt
(automatisch generiert — bitte pruefen/praezisieren)

## Geänderte Dateien
{changed_lines}

## ⚠️ Welche Kontextdatei muss aktualisiert werden?
[leer wenn nichts]

## 🔍 Welche Scope-Datei war unvollständig?
[leer wenn nichts]

## 🌐 Welche globalen Abhängigkeiten wurden berührt?
[leer wenn nichts]

## 🧬 Kontext-Triage (vor Session-Cut)
**MUSS erhalten bleiben:**
[leer wenn nichts]

**Nur historisch:**
[leer wenn nichts]

**Gefährlich zu verlieren:**
[leer wenn nichts]

## Blocker / offene Fragen
[Optional]

---
> Wenn fertig: `Status: done` setzen oder Datei leeren.
"""
    handoff_path.write_text(new_handoff, encoding="utf-8")

try:
    main()
except Exception:
    pass
PYEOF

REFLECT_HOOK_INPUT="$HOOK_INPUT" python3 "$REFLECT_PY" "$CONTEXT_DIR" 2>/dev/null || true
exit 0
